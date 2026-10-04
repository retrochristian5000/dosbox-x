#include "config.h"

#if !(defined(C_NATIVE_MACOS) && C_NATIVE_MACOS)
#include <SDL_syswm.h>
#endif

#include "sdlmain.h"
#include "control.h"
#include "dosbox.h"
#include "logging.h"
#include "macosx_host.h"
#include "menudef.h"
#include "render.h"
#include "vga.h"
#include "../ints/int10.h"
#include "output_surface.h"
#include "output_tools.h"

#include <string>
#include <vector>

#if defined(MACOSX) && C_METAL
#if defined(C_SDL2)

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <AppKit/AppKit.h>

#if defined(__clang__)
# if !__has_feature(objc_arc)
#  error "output_metal.mm requires ARC"
# endif
#endif

#include "output_metal.h"

extern VGA_Type vga;
extern VideoModeBlock* CurMode;

class CMetal {
public:
    CMetal();
    ~CMetal();

    bool Initialize(void* nsview, int w, int h);
    void Shutdown();

    bool StartUpdate(uint8_t*& pixels, Bitu& pitch);
    void EndUpdate();

    bool Resize(uint32_t window_w, uint32_t window_h,
        uint32_t tex_w, uint32_t tex_h);

    void ResizeCPUBuffer(uint32_t src_w, uint32_t src_h);
    bool CreateSampler();
    void GetRenderMode();
    bool CreatePipeline();
    bool CreateFrameTexture(uint32_t w, uint32_t h);
    void SetSamplerMode(id<MTLRenderCommandEncoder> encoder);
    void CheckSourceResolution();

    uint32_t frame_width = 0;
    uint32_t frame_height = 0;

    int cpu_pitch = 0;
    std::vector<uint8_t> cpu_buffer;
    uint32_t window_width = 0;
    uint32_t window_height = 0;
    uint32_t last_window_w = 0;
    uint32_t last_window_h = 0;
    uint32_t last_tex_w = 0;
    uint32_t last_tex_h = 0;
    uint32_t last_scalesize = 0;
    bool was_fullscreen = false;

private:
    NSView* view = nil;
    NSView* metalView = nil;

    id<MTLDevice> device = nil;
    id<MTLCommandQueue> queue = nil;
    id<MTLCommandBuffer> submittedFrame = nil;
    CAMetalLayer* layer = nil;

    id<MTLTexture> frameTexture = nil;
    id<MTLSamplerState> samplerNearest = nil;
    id<MTLSamplerState> samplerLinear = nil;
    id<MTLRenderPipelineState> pipeline = nil;

    bool textureMapped = false;
    int current_render_mode = ASPECT_NEAREST;
    MTLViewport currentViewport = {};
};


CMetal::CMetal() {}
CMetal::~CMetal() { Shutdown(); }

bool CMetal::Initialize(void* nsview, int w, int h)
{
    /* ---------------------------------
     * 1. Metal Device
     * --------------------------------- */
    device = MTLCreateSystemDefaultDevice();
    if (!device) {
        LOG_MSG("Metal: No device available");
        return false;
    }

    queue = [device newCommandQueue];
    if (!queue) {
        LOG_MSG("Metal: Failed to create command queue");
        return false;
    }
    this->view = (__bridge NSView*)nsview;

    /* ---------------------------------
    * 2. Create Metal Layer + SubView
    * --------------------------------- */
    layer = [CAMetalLayer layer];
    layer.device = device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;

    /* Metal専用NSViewを作る */
    metalView = [[NSView alloc] initWithFrame:view.bounds];

    metalView.autoresizingMask =
        NSViewWidthSizable | NSViewHeightSizable;

    metalView.wantsLayer = YES;
    metalView.layer = layer;

    /* SDLのcontentViewに追加 */
    [view addSubview:metalView];

    /*
     * Let AppKit translate logical window points to backing pixels.  This is
     * more accurate than multiplying by backingScaleFactor and automatically
     * follows the window between Retina and non-Retina displays.
     */
    layer.frame = metalView.bounds;
    const NSRect initialBacking = [metalView convertRectToBacking:metalView.bounds];
    layer.contentsScale = metalView.window ? metalView.window.backingScaleFactor : 1.0;
    layer.drawableSize = initialBacking.size;

    /* ---------------------------------
     * 4. CPU framebuffer
     * --------------------------------- */
    frame_width  = w;
    frame_height = h;

    cpu_pitch = w * 4;
    cpu_buffer.resize(cpu_pitch * h);

    /* ---------------------------------
     * 5. GPU resources
     * --------------------------------- */
    if (!CreateFrameTexture(w, h)) {
        LOG_MSG("Metal: CreateFrameTexture failed");
        return false;
    }

    if (!CreatePipeline()) {
        LOG_MSG("Metal: CreatePipeline failed");
        return false;
    }

    if (!CreateSampler()) {
        LOG_MSG("Metal: CreateSampler failed");
        return false;
    }
    CheckSourceResolution();
    LOG_MSG("Metal: Initialize complete");

    return true;
}
void CMetal::CheckSourceResolution()
{
    if(frame_width == sdl.draw.width &&
        frame_height == sdl.draw.height)
        return;

    LOG_MSG("Metal: VGA source resolution changed %ux%u -> %ux%u",
        frame_width, frame_height,
        sdl.draw.width, sdl.draw.height);

    // Resize CPU buffer（don't shrink if smaller）
    ResizeCPUBuffer(
        sdl.draw.width,
        sdl.draw.height);

    Resize(
        sdl.draw.width, sdl.draw.height,   // Window size
        sdl.draw.width, sdl.draw.height);  // Frame texture size

}

void CMetal::ResizeCPUBuffer(uint32_t src_w, uint32_t src_h)
{
    const uint32_t required_pitch = src_w * 4; // BGRA32
    const uint32_t required_size = required_pitch * src_h;

    // Resize CPU buffer（don't shrink if smaller）
    if(cpu_buffer.size() < required_size) {
        cpu_buffer.resize(required_size);
        //LOG_MSG("D3D11: CPU buffer resized to %u bytes", required_size);
    }

    cpu_pitch = required_pitch;
}

void CMetal::Shutdown()
{
    [submittedFrame waitUntilCompleted];
    submittedFrame = nil;
    [metalView removeFromSuperview];
    metalView.layer = nil;
    metalView = nil;
    layer = nil;
    view = nil;
    frameTexture = nil;
    pipeline = nil;
    queue = nil;
    device = nil;
    samplerNearest = nil;
    samplerLinear = nil;
    textureMapped = false;
}

bool CMetal::StartUpdate(uint8_t*& pixels, Bitu& pitch)
{
    if(textureMapped) return false;

    // Begin frame update by returning the CPU-side framebuffer
    pixels = cpu_buffer.data();
    pitch = cpu_pitch;
    render.scale.outWrite = cpu_buffer.data();
    render.scale.outPitch = cpu_pitch;
    textureMapped = true;
    return true;
}

void CMetal::EndUpdate()
{
    if(!textureMapped){
        //LOG_MSG("METAL: EndUpdate textureMapped=false");
        return;
    }
    // A missing drawable must not leave subsequent frame updates locked out.
    textureMapped = false;

    @autoreleasepool {
        // The single upload texture must no longer be in use by the previous frame.
        [submittedFrame waitUntilCompleted];
        submittedFrame = nil;

        MTLRegion region = {
            {0,0,0},
            {frame_width, frame_height, 1}
        };

        [frameTexture replaceRegion : region
            mipmapLevel : 0
            withBytes : cpu_buffer.data()
            bytesPerRow : cpu_pitch] ;

        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            return;
        }
        MTLRenderPassDescriptor* pass =
            [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].clearColor =
            MTLClearColorMake(0, 0, 0, 1); // Black
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        if (!cmd)
            return;

        id<MTLRenderCommandEncoder> enc =
            [cmd renderCommandEncoderWithDescriptor : pass];
        if (!enc)
            return;
        [enc setViewport:currentViewport];
        [enc setRenderPipelineState : pipeline] ;
        [enc setFragmentTexture : frameTexture atIndex : 0] ;
        GetRenderMode();
        SetSamplerMode(enc);

        [enc drawPrimitives : MTLPrimitiveTypeTriangleStrip
                vertexStart : 0
                vertexCount : 4];
        [enc endEncoding] ;

        [cmd presentDrawable : drawable] ;
        [cmd commit] ;
        submittedFrame = cmd;
    }
}


bool CMetal::CreateSampler()
{
    MTLSamplerDescriptor* s = [[MTLSamplerDescriptor alloc]init];

    // ---- Nearest ----
    s.minFilter = MTLSamplerMinMagFilterNearest;
    s.magFilter = MTLSamplerMinMagFilterNearest;
    samplerNearest = [device newSamplerStateWithDescriptor : s];

    // ---- Linear ----
    s.minFilter = MTLSamplerMinMagFilterLinear;
    s.magFilter = MTLSamplerMinMagFilterLinear;
    samplerLinear = [device newSamplerStateWithDescriptor : s];
    if(!(samplerNearest && samplerLinear)) LOG_MSG("METAL:CreateSampler failed");
    return samplerNearest && samplerLinear;
}

void CMetal::SetSamplerMode(id<MTLRenderCommandEncoder> encoder)
{
    id<MTLSamplerState> s = samplerLinear;

    if(current_render_mode == ASPECT_NEAREST)
        s = samplerNearest;

    [encoder setFragmentSamplerState : s atIndex : 0] ;
}

void CMetal::GetRenderMode() {
    Section_prop* section = static_cast<Section_prop*>(control->GetSection("render"));
    std::string s_aspect = section->Get_string("aspect");

    if(s_aspect == "nearest") {
        current_render_mode = ASPECT_NEAREST;
    }
    else if(s_aspect == "bilinear") {
        current_render_mode = ASPECT_BILINEAR;
    }
    else {
        current_render_mode = ASPECT_NEAREST; // default
    }
}

bool CMetal::CreatePipeline()
{
    NSError* err = nil;

    NSString* src = @"\
    #include <metal_stdlib>\n\
    using namespace metal;\n\
    \
    struct VSOut {\
        float4 pos [[position]];\
        float2 uv;\
    };\
    \
    vertex VSOut vs_main(uint vid [[vertex_id]]) {\
        float2 pos[4] = {\
            {-1.0,-1.0},{ 1.0,-1.0},\
            {-1.0, 1.0},{ 1.0, 1.0}\
        };\
        float2 uv[4] = {\
            {0.0,1.0},{1.0,1.0},\
            {0.0,0.0},{1.0,0.0}\
        };\
        VSOut o;\
        o.pos = float4(pos[vid],0,1);\
        o.uv  = uv[vid];\
        return o;\
    }\
    \
    fragment float4 ps_main(VSOut in [[stage_in]],\
                            texture2d<float> tex [[texture(0)]],\
                            sampler smp [[sampler(0)]]) {\
        return tex.sample(smp, in.uv);\
    }";

    id<MTLLibrary> lib =
        [device newLibraryWithSource:src options:nil error:&err];

    if (!lib) {
        LOG_MSG("Metal: Shader compile error: %s",
                err.localizedDescription.UTF8String);
        return false;
    }

    id<MTLFunction> vs = [lib newFunctionWithName:@"vs_main"];
    id<MTLFunction> ps = [lib newFunctionWithName:@"ps_main"];

    if (!vs || !ps) {
        LOG_MSG("Metal: Shader function missing");
        return false;
    }

    MTLRenderPipelineDescriptor* desc =
        [[MTLRenderPipelineDescriptor alloc] init];

    desc.vertexFunction   = vs;
    desc.fragmentFunction = ps;
    desc.colorAttachments[0].pixelFormat =
        MTLPixelFormatBGRA8Unorm;

    desc.colorAttachments[0].blendingEnabled = NO;

    pipeline =
        [device newRenderPipelineStateWithDescriptor:desc
                                               error:&err];

    if (!pipeline) {
        LOG_MSG("Metal: Pipeline creation failed: %s",
                err.localizedDescription.UTF8String);
        return false;
    }

    return true;
}

static CMetal* metal = nullptr;

void metal_init(void)
{
    OUTPUT_Metal_Shutdown();

    sdl.desktop.want_type = SCREEN_METAL;

    //LOG_MSG("OUTPUT METAL: Init called");

    if(!sdl.window) {
        sdl.window = GFX_SetSDLWindowMode(640, 400, SCREEN_SURFACE);

        if(!sdl.window) {
            LOG_MSG("SDL: Failed to create window: %s", SDL_GetError());
            OUTPUT_SURFACE_Select();
            return;
        }

        sdl.surface = SDL_GetWindowSurface(sdl.window);
        sdl.desktop.pixelFormat = SDL_GetWindowPixelFormat(sdl.window);
    }

    NSView *view = nil;
#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS
    /*
     * The native host already owns the AppKit view. Avoid round-tripping
     * through SDL_SysWMinfo just to recover an object we created ourselves.
     */
    view = (__bridge NSView *)macosx_native_content_view();
#else
    SDL_SysWMinfo wmi = {};
    SDL_VERSION(&wmi.version);

    if(!SDL_GetWindowWMInfo(sdl.window, &wmi) || wmi.subsystem != SDL_SYSWM_COCOA) {
        LOG_MSG("METAL: Failed to get Cocoa WM info");
        OUTPUT_SURFACE_Select();
        return;
    }

    NSWindow *nswin = wmi.info.cocoa.window;
    view = [nswin contentView];
#endif

    if(!view) {
        LOG_MSG("METAL: Failed to get native NSView");
        OUTPUT_SURFACE_Select();
        return;
    }

    if(sdl.desktop.fullscreen)
        GFX_CaptureMouse();

    metal = new CMetal();

    int w = sdl.draw.width ? sdl.draw.width : 640;
    int h = sdl.draw.height ? sdl.draw.height : 400;

    bool initialized = false;
    @autoreleasepool {
        initialized = metal->Initialize((__bridge void*)view, w, h);
    }
    if(!initialized) {
        LOG_MSG("METAL: Initialize failed");
        delete metal;
        metal = nullptr;
        OUTPUT_SURFACE_Select();
        return;
    }

    sdl.desktop.type = SCREEN_METAL;
}


void OUTPUT_Metal_Select()
{
    sdl.desktop.want_type = SCREEN_METAL;
    render.aspectOffload = true;
}

Bitu OUTPUT_Metal_GetBestMode(Bitu flags)
{
    flags |= GFX_SCALING;
    flags &= ~(GFX_CAN_8 | GFX_CAN_15 | GFX_CAN_16);
    flags |= GFX_CAN_32;
    return flags;
}

Bitu OUTPUT_Metal_SetSize(void)
{
    if (!metal)
        metal_init();
    if (!metal) {
        LOG_MSG("Metal: Not initialized");
        return 0;
    }

    /* ------------------------
     * Framebuffer (texture) size
     * ------------------------ */
    uint32_t tex_w = sdl.draw.width;
    uint32_t tex_h = sdl.draw.height;
    if (!tex_w || !tex_h)
        return 0;

    /* ------------------------
     * Window logical size
     * ------------------------ */
    int cur_w = 0, cur_h = 0;
    SDL_GetWindowSize(sdl.window, &cur_w, &cur_h);

    if (cur_w <= 0 || cur_h <= 0)
        return 0;

    /* ------------------------
     * Fullscreen handling
     * ------------------------ */
    if(!sdl.desktop.fullscreen && !metal->was_fullscreen){
        metal->window_width = cur_w;
        metal->window_height = cur_h;
    }

    if(sdl.desktop.fullscreen && !metal->was_fullscreen) {
        metal->was_fullscreen = true;
        metal->window_width = cur_w;
        metal->window_height = cur_w * sdl.draw.height / sdl.draw.width;
        SDL_SetWindowFullscreen(
            sdl.window,
            SDL_WINDOW_FULLSCREEN_DESKTOP);
    }
    else if(!sdl.desktop.fullscreen && metal->was_fullscreen){
        SDL_SetWindowFullscreen(sdl.window, 0);
        cur_w = metal->window_width;
        cur_h = metal->window_height;
        metal->was_fullscreen = false;
    }

    /* ------------------------
     * Metal resize
     * ------------------------ */
    if (!metal->Resize(cur_w, cur_h, tex_w, tex_h)) {
        LOG_MSG("Metal: Resize failed");
        return 0;
    }

    return GFX_CAN_32 | GFX_SCALING | GFX_HARDWARE;
}

extern bool hardware_scaler_selected;
bool CMetal::Resize(uint32_t window_w,
                    uint32_t window_h,
                    uint32_t tex_w,
                    uint32_t tex_h)
{
    if (!layer || !view || !metalView)
        return false;
    // Firmware boot paths can render before the DOS BIOS supplies mode metadata.
    const uint32_t mode_w = CurMode && CurMode->swidth ? CurMode->swidth : tex_w;
    const uint32_t mode_h = CurMode && CurMode->sheight ? CurMode->sheight : tex_h;
    //LOG_MSG("Resize called: win=%u,%u tex=%u,%u", window_w, window_h, tex_w, tex_h);

    const bool reset_window_size =
        (((userResizeWindowWidth == 0) && (userResizeWindowHeight == 0)) ||
        (tex_w != last_tex_w || tex_h != last_tex_h))
        && !sdl.desktop.fullscreen;

    double target_ratio = 4.0 / 3.0; // default aspect ratio 4:3
    if(render.aspect) { // "Fit to aspect ratio" is enabled 
        if(aspect_ratio_x > 0 && aspect_ratio_y > 0)
            target_ratio = (double)aspect_ratio_x / aspect_ratio_y;    // user-defined / preset aspect ratio
        else if(aspect_ratio_x < 0 && aspect_ratio_y < 0 || IS_PC98_ARCH)
            target_ratio = (double)mode_w / mode_h; // Use current mode's aspect ratio
    }
    else if(tex_h != mode_h) {
        target_ratio = (double)mode_w / mode_h;
    }
    else target_ratio = (double)tex_w / tex_h;

    uint32_t width=0, height=0;
    if(!sdl.desktop.fullscreen) {
        if(hardware_scaler_selected) {
            render.scale.hardware = true;
            hardware_scaler_selected = false;
        }
        if(reset_window_size || render.scale.size != last_scalesize){
            if(tex_h >= mode_h * 2) { // doublescan mode
                width = tex_w;
                height = tex_h;
                if(render.aspect) {
                    width = (uint32_t)((double)height * mode_w / mode_h +0.5); // First adjust width to match the original aspect ratio.
                    height = (uint32_t)((double)width / target_ratio + 0.5); // Then adjust height to match the target aspect ratio. This ensures the final window size maintains the target aspect ratio, even in doublescan mode.
                }
                window_w = (uint32_t)(height * target_ratio * (render.scale.hardware ? (double)render.scale.size / 2.0 : 1u) + 0.5);
                window_h = (uint32_t)(height * (render.scale.hardware ? (double)render.scale.size / 2.0 : 1u) + 0.5);
            }
            else {
                window_w = tex_w * (render.scale.hardware ? render.scale.size : 1);
                if(CurMode && CurMode->type == M_TEXT && vga.mode != M_HERC_GFX) window_w = (uint32_t)((double)window_w / 2.0 + 0.5); // Suppress window size in text mode
                if(window_w < tex_w) window_w = tex_w; // Keep at least original size
                window_h = (uint32_t)((double)window_w / target_ratio + 0.5);
            }
            if(window_w != last_window_w || window_h != last_window_h) SDL_SetWindowSize(sdl.window, window_w, window_h);
            last_scalesize = render.scale.size;
        }
        if(render.aspect) {
            int real_w = 0, real_h = 0;
            SDL_GetWindowSize(sdl.window, &real_w, &real_h);
            if(real_w > 0) {
                window_w = real_w;
                window_h = (uint32_t)((double)window_w / target_ratio + 0.5);
            }
            if(window_w != last_window_w || window_h != last_window_h) SDL_SetWindowSize(sdl.window, window_w, window_h);
            //LOG_MSG("window_w=%d, window_h=%d, sdl.draw.width=%d, real_w=%d, real_h=%d, w/h=%lf, target=%lf", window_w, window_h, sdl.draw.width, real_w, real_h, (double)real_w/real_h, target_ratio);
        }
    }

    /*
     * The backing geometry is checked after AppKit has had a chance to resize
     * the view. A display move can change backing pixels without changing the
     * logical window dimensions, so logical dimensions alone are not enough
     * for an early return.
     */

    /* ---------------------------------
     * 1. Recreate Frame Texture
     * --------------------------------- */

    if (tex_w != frame_width ||
        tex_h != frame_height)
    {
        frame_width  = tex_w;
        frame_height = tex_h;
        ResizeCPUBuffer(frame_width, frame_height);

        if (!CreateFrameTexture(frame_width,
                                frame_height))
        {
            LOG_MSG("Metal: CreateFrameTexture failed in Resize");
            return false;
        }
        LOG_MSG("Metal: Texture resized to %ux%u", tex_w, tex_h);
    }

    // Texture size is fixed
    frame_width = tex_w;
    frame_height = tex_h;

    if(sdl.window && !sdl.desktop.fullscreen) {
        int actual_w = 0;
        int actual_h = 0;
        SDL_GetWindowSize(sdl.window, &actual_w, &actual_h);
        if (actual_w != static_cast<int>(window_w) ||
            actual_h != static_cast<int>(window_h)) {
            SDL_SetWindowSize(sdl.window, window_w, window_h);
        }
    }

    /*
     * AppKit owns the logical view size. Keep the Metal subview attached to
     * those bounds and ask AppKit for the corresponding backing-pixel rect.
     */
    metalView.frame = view.bounds;
    const NSRect logicalBounds = metalView.bounds;
    const NSRect backingBounds = [metalView convertRectToBacking:logicalBounds];
    const CGFloat scale = metalView.window ? metalView.window.backingScaleFactor : 1.0;
    const CGFloat backing_scale_x = logicalBounds.size.width > 0.0
                                        ? backingBounds.size.width / logicalBounds.size.width
                                        : scale;
    const CGFloat backing_scale_y = logicalBounds.size.height > 0.0
                                        ? backingBounds.size.height / logicalBounds.size.height
                                        : scale;

    width = static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(logicalBounds.size.width)));
    height = static_cast<uint32_t>(std::max<CGFloat>(1.0, std::round(logicalBounds.size.height)));

    layer.contentsScale = scale;
    layer.frame = logicalBounds;
    layer.drawableSize = CGSizeMake(std::max<CGFloat>(1.0, std::round(backingBounds.size.width)),
                                    std::max<CGFloat>(1.0, std::round(backingBounds.size.height)));

    uint32_t dw = static_cast<uint32_t>(layer.drawableSize.width);
    uint32_t dh = static_cast<uint32_t>(layer.drawableSize.height);

    if (window_w == last_window_w &&
        window_h == last_window_h &&
        tex_w == last_tex_w &&
        tex_h == last_tex_h &&
        width == last_window_w &&
        height == last_window_h &&
        currentViewport.width > 0.0 &&
        currentViewport.height > 0.0 &&
        layer.drawableSize.width == currentViewport.width &&
        layer.drawableSize.height == currentViewport.height &&
        !sdl.desktop.fullscreen) {
        return true;
    }

    if (sdl.desktop.fullscreen && render.aspect) {

        double win_ratio = (double)dw / (double)dh;

        double vp_w, vp_h;
        double vp_x = 0.0;
        double vp_y = 0.0;

        if (win_ratio > target_ratio) {
            vp_h = dh;
            vp_w = vp_h * target_ratio;
            vp_x = (dw - vp_w) * 0.5;
        }
        else {
            vp_w = dw;
            vp_h = vp_w / target_ratio;
            vp_y = (dh - vp_h) * 0.5;
        }

        currentViewport = { vp_x, vp_y, vp_w, vp_h, 0.0, 1.0 };
    }
    else {
        currentViewport = { 0.0, 0.0, (double)dw, (double)dh, 0.0, 1.0 };
    }

    // Mouse coordinates use AppKit points, while Metal's viewport uses backing pixels.
    sdl.clip.x = static_cast<Sint16>(currentViewport.originX / backing_scale_x);
    sdl.clip.y = static_cast<Sint16>(currentViewport.originY / backing_scale_y);
    sdl.clip.w = static_cast<Uint16>(currentViewport.width / backing_scale_x);
    sdl.clip.h = static_cast<Uint16>(currentViewport.height / backing_scale_y);

    last_window_w = width;
    last_window_h = height;
    last_tex_w = frame_width;
    last_tex_h = frame_height;
    return true;
}


bool CMetal::CreateFrameTexture(uint32_t w, uint32_t h)
{
    MTLTextureDescriptor* desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
            MTLPixelFormatBGRA8Unorm
            width:w
            height:h
            mipmapped:NO];

    desc.usage = MTLTextureUsageShaderRead;
    
    // Keep Metal's hardware-specific default: shared on Apple GPUs, managed on Intel/AMD.

    frameTexture = [device newTextureWithDescriptor:desc];

    if(!frameTexture)
        LOG_MSG("METAL: CreateFrameTexture failed");

    return frameTexture != nil;
}

bool OUTPUT_Metal_StartUpdate(uint8_t*& pixels, Bitu& pitch)
{
    //LOG_MSG("D3D11: StartUpdate");
    bool result = false;
    if(metal) result = metal->StartUpdate(pixels, pitch);
    return result;
}

void OUTPUT_Metal_EndUpdate(const uint16_t* changedLines)
{
    //LOG_MSG("METAL: EndUpdate called, changedLines=%p", changedLines);
    if(metal)
        metal->EndUpdate();
}

void OUTPUT_Metal_Shutdown()
{
    delete metal;
    metal = nullptr;
}

void OUTPUT_Metal_CheckSourceResolution()
{
    if(metal) metal->CheckSourceResolution();
}

#endif //#if defined(C_SDL2)
#endif //#if defined(MACOSX)
