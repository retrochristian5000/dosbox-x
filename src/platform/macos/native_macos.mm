/*
 * Native macOS host services for the SDL2-shaped DOSBox-X host ABI.
 *
 * This file intentionally uses AppKit, Core Audio/AudioUnit, IOKit HID,
 * pthreads, and libc directly.  The native macOS build pre-includes
 * native_macos_compat.h, so public SDL entry points used by old host-facing
 * code are renamed to DOSBoxMac_* at compile time.  No SDL library is linked.
 */

#include "native_macos_sdl_abi.h"
#include "macosx_host.h"

#import <AppKit/AppKit.h>
#import <AudioUnit/AudioUnit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/hid/IOHIDLib.h>
#import <IOKit/hid/IOHIDUsageTables.h>

#if defined(__clang__)
# if !__has_feature(objc_arc)
#  error "native_macos.mm requires ARC"
# endif
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

#include <pthread.h>
#include <unistd.h>

@class DOSBoxMacSurfaceView;
@class DOSBoxMacWindowDelegate;

struct SDL_Window {
    __strong NSWindow *nswindow = nil;
    __strong DOSBoxMacSurfaceView *view = nil;
    __strong DOSBoxMacWindowDelegate *delegate = nil;
    SDL_Surface *surface = nullptr;
    Uint32 flags = 0;
    SDL_bool keyboard_grab = SDL_FALSE;
    SDL_DisplayMode mode = {};
    bool fullscreen_transition = false;
};

struct SDL_mutex {
    pthread_mutex_t mutex;
};

struct SDL_semaphore {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    Uint32 value = 0;
};

struct SDL_Thread {
    pthread_t thread = {};
    pthread_mutex_t state_mutex = {};
    SDL_ThreadFunction fn = nullptr;
    void *data = nullptr;
    int status = 0;
    bool joined = false;
    bool detached = false;
    bool finished = false;
};

struct _SDL_Joystick {
    IOHIDDeviceRef device = nullptr;
    std::vector<IOHIDElementRef> axes = {};
    std::vector<IOHIDElementRef> buttons = {};
    std::vector<IOHIDElementRef> hats = {};
    std::string name = {};
};

namespace {

std::mutex event_mutex;
std::deque<SDL_Event> event_queue;
std::string last_error;
SDL_Window *main_window = nullptr;
bool text_input_enabled = true;
bool relative_mouse = false;
bool cursor_hidden = false;
SDL_Keymod mod_state = KMOD_NONE;
std::unordered_set<SDL_Surface *> owned_surfaces;

struct AudioState {
    AudioUnit unit = nullptr;
    SDL_AudioSpec spec = {};
    pthread_mutex_t mutex = {};
    bool mutex_ready = false;
    bool opened = false;
    bool running = false;
} audio_state;

IOHIDManagerRef hid_manager = nullptr;
std::vector<IOHIDDeviceRef> hid_devices;
std::string hid_index_name;

void set_error(const char *message)
{
    last_error = message ? message : "";
}

void activate_application()
{
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
        return;
    }
#endif

#if defined(__clang__)
# pragma clang diagnostic push
# pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    [NSApp activateIgnoringOtherApps:YES];
#if defined(__clang__)
# pragma clang diagnostic pop
#endif
}

void push_event(const SDL_Event &event)
{
    std::lock_guard<std::mutex> lock(event_mutex);
    event_queue.push_back(event);
}

bool pop_event(SDL_Event *event)
{
    if (!event)
        return false;

    std::lock_guard<std::mutex> lock(event_mutex);
    if (event_queue.empty())
        return false;

    *event = event_queue.front();
    event_queue.pop_front();
    return true;
}

CGDirectDisplayID display_id_for_screen(NSScreen *screen)
{
    if (!screen)
        return kCGNullDirectDisplay;
    NSNumber *number = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
    return number ? static_cast<CGDirectDisplayID>([number unsignedIntValue])
                  : kCGNullDirectDisplay;
}

NSScreen *screen_for_index(const int index)
{
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (index < 0 || index >= static_cast<int>([screens count]))
        return nil;
    return [screens objectAtIndex:static_cast<NSUInteger>(index)];
}

int screen_index(NSScreen *screen)
{
    const CGDirectDisplayID target = display_id_for_screen(screen);
    if (target == kCGNullDirectDisplay)
        return -1;

    NSArray<NSScreen *> *screens = [NSScreen screens];
    for (NSUInteger i = 0; i < [screens count]; ++i) {
        if (display_id_for_screen([screens objectAtIndex:i]) == target)
            return static_cast<int>(i);
    }
    return -1;
}

int display_index_from_window_position(const int position)
{
    if (SDL_WINDOWPOS_ISCENTERED(position) || SDL_WINDOWPOS_ISUNDEFINED(position))
        return position & 0xffff;
    return -1;
}

NSScreen *screen_for_window_position(const int x, const int y)
{
    int index = display_index_from_window_position(x);
    if (index < 0)
        index = display_index_from_window_position(y);
    if (NSScreen *screen = screen_for_index(index))
        return screen;

    if (!SDL_WINDOWPOS_ISCENTERED(x) && !SDL_WINDOWPOS_ISUNDEFINED(x) &&
        !SDL_WINDOWPOS_ISCENTERED(y) && !SDL_WINDOWPOS_ISUNDEFINED(y)) {
        const CGPoint point = CGPointMake(static_cast<CGFloat>(x),
                                          static_cast<CGFloat>(y));
        for (NSScreen *candidate in [NSScreen screens]) {
            const CGDirectDisplayID display_id = display_id_for_screen(candidate);
            if (display_id != kCGNullDirectDisplay &&
                CGRectContainsPoint(CGDisplayBounds(display_id), point))
                return candidate;
        }
    }

    return [NSScreen mainScreen];
}

NSScreen *screen_for_window(SDL_Window *window)
{
    if (window && window->nswindow && [window->nswindow screen])
        return [window->nswindow screen];
    return [NSScreen mainScreen];
}

CGFloat cocoa_desktop_top()
{
    const CGRect mainBounds = CGDisplayBounds(CGMainDisplayID());
    return CGRectGetMaxY(mainBounds);
}

NSRect sdl_content_rect_from_window(SDL_Window *window)
{
    if (!window || !window->nswindow)
        return NSZeroRect;
    NSRect rect = [window->nswindow contentRectForFrameRect:[window->nswindow frame]];
    rect.origin.y = cocoa_desktop_top() - rect.origin.y - rect.size.height;
    return rect;
}

SDL_Keymod modifiers_from_flags(const NSEventModifierFlags flags)
{
    Uint16 result = KMOD_NONE;
    if (flags & NSEventModifierFlagShift)
        result |= KMOD_SHIFT;
    if (flags & NSEventModifierFlagControl)
        result |= KMOD_CTRL;
    if (flags & NSEventModifierFlagOption)
        result |= KMOD_ALT;
    if (flags & NSEventModifierFlagCommand)
        result |= KMOD_GUI;
    if (flags & NSEventModifierFlagCapsLock)
        result |= KMOD_CAPS;
    return static_cast<SDL_Keymod>(result);
}

SDL_Scancode scancode_from_keycode(const unsigned short code)
{
    switch (code) {
    case 0: return SDL_SCANCODE_A;
    case 1: return SDL_SCANCODE_S;
    case 2: return SDL_SCANCODE_D;
    case 3: return SDL_SCANCODE_F;
    case 4: return SDL_SCANCODE_H;
    case 5: return SDL_SCANCODE_G;
    case 6: return SDL_SCANCODE_Z;
    case 7: return SDL_SCANCODE_X;
    case 8: return SDL_SCANCODE_C;
    case 9: return SDL_SCANCODE_V;
    case 11: return SDL_SCANCODE_B;
    case 12: return SDL_SCANCODE_Q;
    case 13: return SDL_SCANCODE_W;
    case 14: return SDL_SCANCODE_E;
    case 15: return SDL_SCANCODE_R;
    case 16: return SDL_SCANCODE_Y;
    case 17: return SDL_SCANCODE_T;
    case 18: return SDL_SCANCODE_1;
    case 19: return SDL_SCANCODE_2;
    case 20: return SDL_SCANCODE_3;
    case 21: return SDL_SCANCODE_4;
    case 22: return SDL_SCANCODE_6;
    case 23: return SDL_SCANCODE_5;
    case 24: return SDL_SCANCODE_EQUALS;
    case 25: return SDL_SCANCODE_9;
    case 26: return SDL_SCANCODE_7;
    case 27: return SDL_SCANCODE_MINUS;
    case 28: return SDL_SCANCODE_8;
    case 29: return SDL_SCANCODE_0;
    case 30: return SDL_SCANCODE_RIGHTBRACKET;
    case 31: return SDL_SCANCODE_O;
    case 32: return SDL_SCANCODE_U;
    case 33: return SDL_SCANCODE_LEFTBRACKET;
    case 34: return SDL_SCANCODE_I;
    case 35: return SDL_SCANCODE_P;
    case 36: return SDL_SCANCODE_RETURN;
    case 37: return SDL_SCANCODE_L;
    case 38: return SDL_SCANCODE_J;
    case 39: return SDL_SCANCODE_APOSTROPHE;
    case 40: return SDL_SCANCODE_K;
    case 41: return SDL_SCANCODE_SEMICOLON;
    case 42: return SDL_SCANCODE_BACKSLASH;
    case 43: return SDL_SCANCODE_COMMA;
    case 44: return SDL_SCANCODE_SLASH;
    case 45: return SDL_SCANCODE_N;
    case 46: return SDL_SCANCODE_M;
    case 47: return SDL_SCANCODE_PERIOD;
    case 48: return SDL_SCANCODE_TAB;
    case 49: return SDL_SCANCODE_SPACE;
    case 50: return SDL_SCANCODE_GRAVE;
    case 51: return SDL_SCANCODE_BACKSPACE;
    case 53: return SDL_SCANCODE_ESCAPE;
    case 55: return SDL_SCANCODE_LGUI;
    case 56: return SDL_SCANCODE_LSHIFT;
    case 57: return SDL_SCANCODE_CAPSLOCK;
    case 58: return SDL_SCANCODE_LALT;
    case 59: return SDL_SCANCODE_LCTRL;
    case 60: return SDL_SCANCODE_RSHIFT;
    case 61: return SDL_SCANCODE_RALT;
    case 62: return SDL_SCANCODE_RCTRL;
    case 65: return SDL_SCANCODE_KP_PERIOD;
    case 67: return SDL_SCANCODE_KP_MULTIPLY;
    case 69: return SDL_SCANCODE_KP_PLUS;
    case 71: return SDL_SCANCODE_NUMLOCKCLEAR;
    case 75: return SDL_SCANCODE_KP_DIVIDE;
    case 76: return SDL_SCANCODE_KP_ENTER;
    case 78: return SDL_SCANCODE_KP_MINUS;
    case 81: return SDL_SCANCODE_KP_EQUALS;
    case 82: return SDL_SCANCODE_KP_0;
    case 83: return SDL_SCANCODE_KP_1;
    case 84: return SDL_SCANCODE_KP_2;
    case 85: return SDL_SCANCODE_KP_3;
    case 86: return SDL_SCANCODE_KP_4;
    case 87: return SDL_SCANCODE_KP_5;
    case 88: return SDL_SCANCODE_KP_6;
    case 89: return SDL_SCANCODE_KP_7;
    case 91: return SDL_SCANCODE_KP_8;
    case 92: return SDL_SCANCODE_KP_9;
    case 96: return SDL_SCANCODE_F5;
    case 97: return SDL_SCANCODE_F6;
    case 98: return SDL_SCANCODE_F7;
    case 99: return SDL_SCANCODE_F3;
    case 100: return SDL_SCANCODE_F8;
    case 101: return SDL_SCANCODE_F9;
    case 103: return SDL_SCANCODE_F11;
    case 109: return SDL_SCANCODE_F10;
    case 111: return SDL_SCANCODE_F12;
    case 115: return SDL_SCANCODE_HOME;
    case 116: return SDL_SCANCODE_PAGEUP;
    case 117: return SDL_SCANCODE_DELETE;
    case 118: return SDL_SCANCODE_F4;
    case 119: return SDL_SCANCODE_END;
    case 120: return SDL_SCANCODE_F2;
    case 121: return SDL_SCANCODE_PAGEDOWN;
    case 122: return SDL_SCANCODE_F1;
    case 123: return SDL_SCANCODE_LEFT;
    case 124: return SDL_SCANCODE_RIGHT;
    case 125: return SDL_SCANCODE_DOWN;
    case 126: return SDL_SCANCODE_UP;
    default: return SDL_SCANCODE_UNKNOWN;
    }
}

SDL_Keycode keycode_from_event(NSEvent *event, const SDL_Scancode scancode)
{
    switch (scancode) {
    case SDL_SCANCODE_RETURN: return SDLK_RETURN;
    case SDL_SCANCODE_ESCAPE: return SDLK_ESCAPE;
    case SDL_SCANCODE_BACKSPACE: return SDLK_BACKSPACE;
    case SDL_SCANCODE_TAB: return SDLK_TAB;
    case SDL_SCANCODE_SPACE: return SDLK_SPACE;
    case SDL_SCANCODE_DELETE: return SDLK_DELETE;
    case SDL_SCANCODE_LEFT: return SDLK_LEFT;
    case SDL_SCANCODE_RIGHT: return SDLK_RIGHT;
    case SDL_SCANCODE_UP: return SDLK_UP;
    case SDL_SCANCODE_DOWN: return SDLK_DOWN;
    case SDL_SCANCODE_HOME: return SDLK_HOME;
    case SDL_SCANCODE_END: return SDLK_END;
    case SDL_SCANCODE_PAGEUP: return SDLK_PAGEUP;
    case SDL_SCANCODE_PAGEDOWN: return SDLK_PAGEDOWN;
    case SDL_SCANCODE_LSHIFT: return SDLK_LSHIFT;
    case SDL_SCANCODE_RSHIFT: return SDLK_RSHIFT;
    case SDL_SCANCODE_LCTRL: return SDLK_LCTRL;
    case SDL_SCANCODE_RCTRL: return SDLK_RCTRL;
    case SDL_SCANCODE_LALT: return SDLK_LALT;
    case SDL_SCANCODE_RALT: return SDLK_RALT;
    case SDL_SCANCODE_LGUI: return SDLK_LGUI;
    default: break;
    }

    if (scancode >= SDL_SCANCODE_F1 && scancode <= SDL_SCANCODE_F12)
        return SDL_SCANCODE_TO_KEYCODE(scancode);
    if (scancode >= SDL_SCANCODE_KP_DIVIDE && scancode <= SDL_SCANCODE_KP_PERIOD)
        return SDL_SCANCODE_TO_KEYCODE(scancode);

    NSString *characters = [[event charactersIgnoringModifiers] lowercaseString];
    if ([characters length] == 1) {
        const unichar ch = [characters characterAtIndex:0];
        if (ch < 128)
            return static_cast<SDL_Keycode>(ch);
    }
    return SDL_SCANCODE_TO_KEYCODE(scancode);
}

void push_text_input(NSEvent *event)
{
    if (!text_input_enabled)
        return;

    NSString *characters = [event characters];
    if (![characters length])
        return;

    const char *utf8 = [characters UTF8String];
    if (!utf8 || !*utf8)
        return;

    bool printable = false;
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(utf8); *p; ++p) {
        if (*p >= 0x20) {
            printable = true;
            break;
        }
    }
    if (!printable)
        return;

    SDL_Event text = {};
    text.type = SDL_TEXTINPUT;
    std::strncpy(text.text.text, utf8, sizeof(text.text.text) - 1);
    push_event(text);
}

void translate_event(NSEvent *event)
{
    if (!event)
        return;

    SDL_Event out = {};
    switch ([event type]) {
    case NSEventTypeKeyDown:
    case NSEventTypeKeyUp:
    case NSEventTypeFlagsChanged: {
        const SDL_Scancode sc = scancode_from_keycode([event keyCode]);
        bool down = [event type] == NSEventTypeKeyDown;

        if ([event type] == NSEventTypeFlagsChanged) {
            const NSEventModifierFlags f = [event modifierFlags];
            switch (sc) {
            case SDL_SCANCODE_LSHIFT:
            case SDL_SCANCODE_RSHIFT: down = (f & NSEventModifierFlagShift) != 0; break;
            case SDL_SCANCODE_LCTRL:
            case SDL_SCANCODE_RCTRL: down = (f & NSEventModifierFlagControl) != 0; break;
            case SDL_SCANCODE_LALT:
            case SDL_SCANCODE_RALT: down = (f & NSEventModifierFlagOption) != 0; break;
            case SDL_SCANCODE_LGUI: down = (f & NSEventModifierFlagCommand) != 0; break;
            case SDL_SCANCODE_CAPSLOCK: down = (f & NSEventModifierFlagCapsLock) != 0; break;
            default: break;
            }
        }

        mod_state = modifiers_from_flags([event modifierFlags]);
        out.type = down ? SDL_KEYDOWN : SDL_KEYUP;
        out.key.state = down ? SDL_PRESSED : SDL_RELEASED;
        out.key.repeat = ([event type] == NSEventTypeKeyDown && [event isARepeat]) ? 1 : 0;
        out.key.keysym.scancode = sc;
        out.key.keysym.sym = keycode_from_event(event, sc);
        out.key.keysym.mod = mod_state;
        push_event(out);

        if ([event type] == NSEventTypeKeyDown)
            push_text_input(event);
        break;
    }
    case NSEventTypeMouseMoved:
    case NSEventTypeLeftMouseDragged:
    case NSEventTypeRightMouseDragged:
    case NSEventTypeOtherMouseDragged: {
        if (!main_window || !main_window->nswindow)
            break;
        const NSPoint point = [event locationInWindow];
        const NSRect bounds = [main_window->view bounds];
        out.type = SDL_MOUSEMOTION;
        out.motion.x = static_cast<Sint32>(std::lround(point.x));
        out.motion.y = static_cast<Sint32>(std::lround(bounds.size.height - point.y));
        out.motion.xrel = static_cast<Sint32>(std::lround([event deltaX]));
        out.motion.yrel = static_cast<Sint32>(std::lround([event deltaY]));
        out.motion.state = 0;
        push_event(out);
        break;
    }
    case NSEventTypeLeftMouseDown:
    case NSEventTypeLeftMouseUp:
    case NSEventTypeRightMouseDown:
    case NSEventTypeRightMouseUp:
    case NSEventTypeOtherMouseDown:
    case NSEventTypeOtherMouseUp: {
        if (!main_window)
            break;
        const bool down = [event type] == NSEventTypeLeftMouseDown ||
                          [event type] == NSEventTypeRightMouseDown ||
                          [event type] == NSEventTypeOtherMouseDown;
        const NSInteger button = [event buttonNumber];
        Uint8 mapped = SDL_BUTTON_MIDDLE;
        if (button == 0)
            mapped = SDL_BUTTON_LEFT;
        else if (button == 1)
            mapped = SDL_BUTTON_RIGHT;

        const NSPoint point = [event locationInWindow];
        const NSRect bounds = [main_window->view bounds];
        out.type = down ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
        out.button.state = down ? SDL_PRESSED : SDL_RELEASED;
        out.button.button = mapped;
        out.button.clicks = static_cast<Uint8>(std::min<NSInteger>([event clickCount], 255));
        out.button.x = static_cast<Sint32>(std::lround(point.x));
        out.button.y = static_cast<Sint32>(std::lround(bounds.size.height - point.y));
        push_event(out);
        break;
    }
    case NSEventTypeScrollWheel:
        out.type = SDL_MOUSEWHEEL;
        out.wheel.x = static_cast<Sint32>(std::lround([event scrollingDeltaX]));
        out.wheel.y = static_cast<Sint32>(std::lround([event scrollingDeltaY]));
        out.wheel.direction = SDL_MOUSEWHEEL_NORMAL;
        push_event(out);
        break;
    default:
        break;
    }
}

void pump_appkit_once(const bool wait)
{
    if (!NSApp)
        return;

    NSDate *until = wait ? [NSDate distantFuture] : [NSDate distantPast];
    NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                        untilDate:until
                                           inMode:NSDefaultRunLoopMode
                                          dequeue:YES];
    if (event) {
        translate_event(event);
        [NSApp sendEvent:event];
    }

    if (!wait) {
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:[NSDate distantPast]
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES])) {
            translate_event(event);
            [NSApp sendEvent:event];
        }
    }
    [NSApp updateWindows];
}

void mask_layout(const Uint32 mask, Uint8 &shift, Uint8 &loss)
{
    if (!mask) {
        shift = 0;
        loss = 8;
        return;
    }

    shift = static_cast<Uint8>(__builtin_ctz(mask));
    const unsigned bits = static_cast<unsigned>(__builtin_popcount(mask));
    loss = static_cast<Uint8>(bits >= 8 ? 0 : 8 - bits);
}

SDL_PixelFormat *make_format(const Uint32 format,
                             const int depth,
                             const Uint32 rmask,
                             const Uint32 gmask,
                             const Uint32 bmask,
                             const Uint32 amask)
{
    auto *pf = static_cast<SDL_PixelFormat *>(std::calloc(1, sizeof(SDL_PixelFormat)));
    if (!pf)
        return nullptr;

    pf->format = format;
    pf->BitsPerPixel = static_cast<Uint8>(depth);
    pf->BytesPerPixel = static_cast<Uint8>((depth + 7) / 8);
    pf->Rmask = rmask;
    pf->Gmask = gmask;
    pf->Bmask = bmask;
    pf->Amask = amask;
    mask_layout(rmask, pf->Rshift, pf->Rloss);
    mask_layout(gmask, pf->Gshift, pf->Gloss);
    mask_layout(bmask, pf->Bshift, pf->Bloss);
    mask_layout(amask, pf->Ashift, pf->Aloss);
    pf->refcount = 1;
    return pf;
}

Uint8 channel_from_pixel(const Uint32 pixel, const Uint32 mask, const Uint8 shift, const Uint8 loss)
{
    if (!mask)
        return 0;
    const Uint32 raw = (pixel & mask) >> shift;
    const unsigned bits = 8u - loss;
    if (bits >= 8)
        return static_cast<Uint8>(raw);
    const Uint32 maxv = (1u << bits) - 1u;
    return maxv ? static_cast<Uint8>((raw * 255u) / maxv) : 0;
}

Uint32 read_pixel(const SDL_Surface *surface, const int x, const int y)
{
    const auto *p = static_cast<const Uint8 *>(surface->pixels) +
                    y * surface->pitch + x * surface->format->BytesPerPixel;
    switch (surface->format->BytesPerPixel) {
    case 1: return *p;
    case 2: return *reinterpret_cast<const Uint16 *>(p);
    case 3:
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
        return (static_cast<Uint32>(p[0]) << 16) |
               (static_cast<Uint32>(p[1]) << 8) | p[2];
#else
        return p[0] | (static_cast<Uint32>(p[1]) << 8) |
               (static_cast<Uint32>(p[2]) << 16);
#endif
    default: return *reinterpret_cast<const Uint32 *>(p);
    }
}

void write_pixel(SDL_Surface *surface, const int x, const int y, const Uint32 pixel)
{
    auto *p = static_cast<Uint8 *>(surface->pixels) +
              y * surface->pitch + x * surface->format->BytesPerPixel;
    switch (surface->format->BytesPerPixel) {
    case 1: *p = static_cast<Uint8>(pixel); break;
    case 2: *reinterpret_cast<Uint16 *>(p) = static_cast<Uint16>(pixel); break;
    case 3:
#if SDL_BYTEORDER == SDL_BIG_ENDIAN
        p[0] = static_cast<Uint8>(pixel >> 16);
        p[1] = static_cast<Uint8>(pixel >> 8);
        p[2] = static_cast<Uint8>(pixel);
#else
        p[0] = static_cast<Uint8>(pixel);
        p[1] = static_cast<Uint8>(pixel >> 8);
        p[2] = static_cast<Uint8>(pixel >> 16);
#endif
        break;
    default: *reinterpret_cast<Uint32 *>(p) = pixel; break;
    }
}

Uint32 convert_pixel(const SDL_Surface *src, SDL_Surface *dst, const Uint32 pixel)
{
    if (src->format->Rmask == dst->format->Rmask &&
        src->format->Gmask == dst->format->Gmask &&
        src->format->Bmask == dst->format->Bmask &&
        src->format->Amask == dst->format->Amask)
        return pixel;

    const Uint8 r = channel_from_pixel(pixel, src->format->Rmask,
                                       src->format->Rshift, src->format->Rloss);
    const Uint8 g = channel_from_pixel(pixel, src->format->Gmask,
                                       src->format->Gshift, src->format->Gloss);
    const Uint8 b = channel_from_pixel(pixel, src->format->Bmask,
                                       src->format->Bshift, src->format->Bloss);
    return DOSBoxMac_MapRGB(dst->format, r, g, b);
}

OSStatus audio_render(void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *,
                      UInt32, UInt32 frame_count, AudioBufferList *buffers)
{
    if (!audio_state.opened || !audio_state.spec.callback || !buffers)
        return noErr;

    const UInt32 wanted = frame_count * 4u;
    pthread_mutex_lock(&audio_state.mutex);
    for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) {
        AudioBuffer &buffer = buffers->mBuffers[i];
        if (!buffer.mData)
            continue;
        const UInt32 bytes = std::min(buffer.mDataByteSize, wanted);
        std::memset(buffer.mData, 0, buffer.mDataByteSize);
        if (i == 0)
            audio_state.spec.callback(audio_state.spec.userdata,
                                      static_cast<Uint8 *>(buffer.mData),
                                      static_cast<int>(bytes));
    }
    pthread_mutex_unlock(&audio_state.mutex);
    return noErr;
}

long hid_number(CFTypeRef value, const long fallback = 0)
{
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID())
        return fallback;
    long result = fallback;
    CFNumberGetValue(reinterpret_cast<CFNumberRef>(value), kCFNumberLongType, &result);
    return result;
}

long hid_property_number(IOHIDDeviceRef device, CFStringRef key, const long fallback = 0)
{
    return hid_number(IOHIDDeviceGetProperty(device, key), fallback);
}

bool is_controller(IOHIDDeviceRef device)
{
    const long page = hid_property_number(device, CFSTR(kIOHIDPrimaryUsagePageKey));
    const long usage = hid_property_number(device, CFSTR(kIOHIDPrimaryUsageKey));
    return page == kHIDPage_GenericDesktop &&
           (usage == kHIDUsage_GD_Joystick ||
            usage == kHIDUsage_GD_GamePad ||
            usage == kHIDUsage_GD_MultiAxisController);
}

void refresh_hid_devices()
{
    for (auto device : hid_devices)
        CFRelease(device);
    hid_devices.clear();

    if (!hid_manager) {
        hid_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (!hid_manager)
            return;
        IOHIDManagerSetDeviceMatching(hid_manager, nullptr);
        IOHIDManagerOpen(hid_manager, kIOHIDOptionsTypeNone);
    }

    CFSetRef devices = IOHIDManagerCopyDevices(hid_manager);
    if (!devices)
        return;

    const CFIndex count = CFSetGetCount(devices);
    std::vector<const void *> values(static_cast<size_t>(count));
    CFSetGetValues(devices, values.data());
    for (const void *value : values) {
        auto device = reinterpret_cast<IOHIDDeviceRef>(const_cast<void *>(value));
        if (is_controller(device)) {
            CFRetain(device);
            hid_devices.push_back(device);
        }
    }
    CFRelease(devices);
}

std::string device_name(IOHIDDeviceRef device)
{
    if (!device)
        return "macOS HID controller";

    CFTypeRef value = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (!value || CFGetTypeID(value) != CFStringGetTypeID())
        return "macOS HID controller";

    char buffer[256] = {};
    if (CFStringGetCString(reinterpret_cast<CFStringRef>(value),
                           buffer, sizeof(buffer), kCFStringEncodingUTF8))
        return buffer;
    return "macOS HID controller";
}

void retain_element(std::vector<IOHIDElementRef> &target, IOHIDElementRef element)
{
    CFRetain(element);
    target.push_back(element);
}

void enumerate_elements(SDL_Joystick *joystick)
{
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(joystick->device, nullptr,
                                                          kIOHIDOptionsTypeNone);
    if (!elements)
        return;

    const CFIndex count = CFArrayGetCount(elements);
    for (CFIndex i = 0; i < count; ++i) {
        auto element = reinterpret_cast<IOHIDElementRef>(
                const_cast<void *>(CFArrayGetValueAtIndex(elements, i)));
        const IOHIDElementType type = IOHIDElementGetType(element);
        if (type != kIOHIDElementTypeInput_Misc &&
            type != kIOHIDElementTypeInput_Button &&
            type != kIOHIDElementTypeInput_Axis)
            continue;

        const uint32_t page = IOHIDElementGetUsagePage(element);
        const uint32_t usage = IOHIDElementGetUsage(element);
        if (page == kHIDPage_Button) {
            retain_element(joystick->buttons, element);
        } else if (page == kHIDPage_GenericDesktop &&
                   usage == kHIDUsage_GD_Hatswitch) {
            retain_element(joystick->hats, element);
        } else if (page == kHIDPage_GenericDesktop &&
                   (usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y ||
                    usage == kHIDUsage_GD_Z || usage == kHIDUsage_GD_Rx ||
                    usage == kHIDUsage_GD_Ry || usage == kHIDUsage_GD_Rz ||
                    usage == kHIDUsage_GD_Slider || usage == kHIDUsage_GD_Dial ||
                    usage == kHIDUsage_GD_Wheel)) {
            retain_element(joystick->axes, element);
        }
    }
    CFRelease(elements);
}

CFIndex element_value(IOHIDDeviceRef device, IOHIDElementRef element, bool &ok)
{
    IOHIDValueRef value = nullptr;
    const IOReturn rc = IOHIDDeviceGetValue(device, element, &value);
    ok = rc == kIOReturnSuccess && value;
    return ok ? IOHIDValueGetIntegerValue(value) : 0;
}

struct FileRW {
    FILE *file = nullptr;
};

Sint64 SDLCALL file_size(SDL_RWops *rw)
{
    auto *ctx = static_cast<FileRW *>(rw->hidden.unknown.data1);
    if (!ctx || !ctx->file)
        return -1;
    const off_t old = ftello(ctx->file);
    if (old < 0 || fseeko(ctx->file, 0, SEEK_END) != 0)
        return -1;
    const off_t end = ftello(ctx->file);
    fseeko(ctx->file, old, SEEK_SET);
    return static_cast<Sint64>(end);
}

Sint64 SDLCALL file_seek(SDL_RWops *rw, Sint64 offset, int whence)
{
    auto *ctx = static_cast<FileRW *>(rw->hidden.unknown.data1);
    if (!ctx || !ctx->file || fseeko(ctx->file, static_cast<off_t>(offset), whence) != 0)
        return -1;
    return static_cast<Sint64>(ftello(ctx->file));
}

size_t SDLCALL file_read(SDL_RWops *rw, void *ptr, size_t size, size_t maxnum)
{
    auto *ctx = static_cast<FileRW *>(rw->hidden.unknown.data1);
    return (ctx && ctx->file) ? std::fread(ptr, size, maxnum, ctx->file) : 0;
}

size_t SDLCALL file_write(SDL_RWops *rw, const void *ptr, size_t size, size_t num)
{
    auto *ctx = static_cast<FileRW *>(rw->hidden.unknown.data1);
    return (ctx && ctx->file) ? std::fwrite(ptr, size, num, ctx->file) : 0;
}

int SDLCALL file_close(SDL_RWops *rw)
{
    auto *ctx = static_cast<FileRW *>(rw->hidden.unknown.data1);
    int rc = 0;
    if (ctx && ctx->file)
        rc = std::fclose(ctx->file);
    delete ctx;
    std::free(rw);
    return rc;
}

Sint64 SDLCALL mem_size(SDL_RWops *rw)
{
    return rw ? static_cast<Sint64>(rw->hidden.mem.stop - rw->hidden.mem.base) : -1;
}

Sint64 SDLCALL mem_seek(SDL_RWops *rw, Sint64 offset, int whence)
{
    if (!rw)
        return -1;
    Uint8 *target = nullptr;
    if (whence == RW_SEEK_SET)
        target = rw->hidden.mem.base + offset;
    else if (whence == RW_SEEK_CUR)
        target = rw->hidden.mem.here + offset;
    else if (whence == RW_SEEK_END)
        target = rw->hidden.mem.stop + offset;
    else
        return -1;

    target = std::max(rw->hidden.mem.base, std::min(target, rw->hidden.mem.stop));
    rw->hidden.mem.here = target;
    return static_cast<Sint64>(target - rw->hidden.mem.base);
}

size_t SDLCALL mem_read(SDL_RWops *rw, void *ptr, size_t size, size_t maxnum)
{
    if (!rw || !ptr || !size)
        return 0;
    const size_t available = static_cast<size_t>(rw->hidden.mem.stop - rw->hidden.mem.here);
    const size_t objects = std::min(maxnum, available / size);
    const size_t bytes = objects * size;
    std::memcpy(ptr, rw->hidden.mem.here, bytes);
    rw->hidden.mem.here += bytes;
    return objects;
}

size_t SDLCALL mem_write(SDL_RWops *rw, const void *ptr, size_t size, size_t num)
{
    if (!rw || !ptr || !size || rw->type == SDL_RWOPS_MEMORY_RO)
        return 0;
    const size_t available = static_cast<size_t>(rw->hidden.mem.stop - rw->hidden.mem.here);
    const size_t objects = std::min(num, available / size);
    const size_t bytes = objects * size;
    std::memcpy(rw->hidden.mem.here, ptr, bytes);
    rw->hidden.mem.here += bytes;
    return objects;
}

int SDLCALL mem_close(SDL_RWops *rw)
{
    std::free(rw);
    return 0;
}

} // namespace

@interface DOSBoxMacSurfaceView : NSView
@property(nonatomic, assign) SDL_Window *owner;
@end

@implementation DOSBoxMacSurfaceView
- (BOOL)isFlipped
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    SDL_Surface *surface = self.owner ? self.owner->surface : nullptr;
    if (!surface || !surface->pixels || !surface->format || surface->format->BytesPerPixel != 4)
        return;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace)
        return;

    CGContextRef bitmap = CGBitmapContextCreate(surface->pixels,
                                                 static_cast<size_t>(surface->w),
                                                 static_cast<size_t>(surface->h),
                                                 8,
                                                 static_cast<size_t>(surface->pitch),
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little |
                                                 kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);
    if (!bitmap)
        return;

    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    if (!image)
        return;

    CGContextRef target = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(target);
    CGContextTranslateCTM(target, 0, self.bounds.size.height);
    CGContextScaleCTM(target, 1, -1);
    CGContextDrawImage(target, NSRectToCGRect(self.bounds), image);
    CGContextRestoreGState(target);
    CGImageRelease(image);
}
@end

@interface DOSBoxMacWindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, assign) SDL_Window *owner;
@end

@implementation DOSBoxMacWindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender
{
    (void)sender;
    SDL_Event event = {};
    event.type = SDL_QUIT;
    push_event(event);
    return NO;
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    (void)notification;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_FOCUS_GAINED;
    push_event(event);
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    (void)notification;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_FOCUS_LOST;
    push_event(event);
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    (void)notification;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_MINIMIZED;
    push_event(event);
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    (void)notification;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_RESTORED;
    push_event(event);
}

- (void)windowDidMove:(NSNotification *)notification
{
    (void)notification;
    if (self.owner && self.owner->fullscreen_transition)
        return;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_MOVED;
    if (self.owner) {
        int x = 0;
        int y = 0;
        DOSBoxMac_GetWindowPosition(self.owner, &x, &y);
        event.window.data1 = x;
        event.window.data2 = y;
    }
    push_event(event);
}

- (void)windowDidResize:(NSNotification *)notification
{
    (void)notification;
    if (!self.owner || self.owner->fullscreen_transition)
        return;
    int w = 0;
    int h = 0;
    DOSBoxMac_GetWindowSize(self.owner, &w, &h);
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_RESIZED;
    event.window.data1 = w;
    event.window.data2 = h;
    push_event(event);
}

- (void)windowDidChangeScreen:(NSNotification *)notification
{
    (void)notification;
    if (!self.owner || self.owner->fullscreen_transition)
        return;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_DISPLAY_CHANGED;
    event.window.data1 = screen_index(screen_for_window(self.owner));
    push_event(event);
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification
{
    (void)notification;
    if (!self.owner || self.owner->fullscreen_transition)
        return;
    SDL_Event event = {};
    event.type = SDL_WINDOWEVENT;
    event.window.event = SDL_WINDOWEVENT_DISPLAY_CHANGED;
    event.window.data1 = screen_index(screen_for_window(self.owner));
    push_event(event);
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    (void)notification;
    if (self.owner)
        self.owner->fullscreen_transition = true;
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    (void)notification;
    if (!self.owner)
        return;

    self.owner->fullscreen_transition = false;
    self.owner->flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;

    int w = 0;
    int h = 0;
    DOSBoxMac_GetWindowSize(self.owner, &w, &h);
    SDL_Event resized = {};
    resized.type = SDL_WINDOWEVENT;
    resized.window.event = SDL_WINDOWEVENT_RESIZED;
    resized.window.data1 = w;
    resized.window.data2 = h;
    push_event(resized);
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    (void)notification;
    if (self.owner)
        self.owner->fullscreen_transition = true;
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    (void)notification;
    if (!self.owner)
        return;

    self.owner->fullscreen_transition = false;
    self.owner->flags &= ~(SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP);

    int w = 0;
    int h = 0;
    DOSBoxMac_GetWindowSize(self.owner, &w, &h);
    SDL_Event resized = {};
    resized.type = SDL_WINDOWEVENT;
    resized.window.event = SDL_WINDOWEVENT_RESIZED;
    resized.window.data1 = w;
    resized.window.data2 = h;
    push_event(resized);
}

- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
    (void)window;
    if (!self.owner)
        return;
    self.owner->fullscreen_transition = false;
    self.owner->flags &= ~(SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP);
    set_error("AppKit failed to enter fullscreen");
}

- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
    (void)window;
    if (!self.owner)
        return;
    self.owner->fullscreen_transition = false;
    self.owner->flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    set_error("AppKit failed to exit fullscreen");
}
@end

void *macosx_native_window(void)
{
    return main_window && main_window->nswindow
               ? (__bridge void *)main_window->nswindow
               : nullptr;
}

bool macosx_native_get_window_size(int &width, int &height)
{
    if (!main_window || !main_window->nswindow || !main_window->view)
        return false;

    const NSRect bounds = [main_window->view bounds];
    width = static_cast<int>(std::lround(bounds.size.width));
    height = static_cast<int>(std::lround(bounds.size.height));
    return width > 0 && height > 0;
}

bool macosx_native_set_window_size(const int width, const int height)
{
    if (!main_window || !main_window->nswindow)
        return false;

    NSRect content =
            [main_window->nswindow contentRectForFrameRect:[main_window->nswindow frame]];
    const CGFloat top = NSMaxY(content);
    content.size = NSMakeSize(std::max(width, 1), std::max(height, 1));
    content.origin.y = top - content.size.height;
    [main_window->nswindow
            setFrame:[main_window->nswindow frameRectForContentRect:content]
             display:YES];

    if (main_window->surface &&
        (main_window->surface->w != width || main_window->surface->h != height)) {
        DOSBoxMac_FreeSurface(main_window->surface);
        main_window->surface = nullptr;
    }
    return true;
}

bool macosx_native_set_fullscreen(const bool fullscreen)
{
    if (!main_window || !main_window->nswindow)
        return false;

    const bool is_fullscreen =
            ([main_window->nswindow styleMask] & NSWindowStyleMaskFullScreen) != 0;
    if (fullscreen != is_fullscreen && !main_window->fullscreen_transition) {
        main_window->fullscreen_transition = true;
        [main_window->nswindow toggleFullScreen:nil];
    }

    if (fullscreen)
        main_window->flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    else
        main_window->flags &= ~(SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP);
    return true;
}

extern "C" {

int SDLCALL DOSBoxMac_Init(Uint32 flags)
{
    return DOSBoxMac_InitSubSystem(flags);
}

int SDLCALL DOSBoxMac_InitSubSystem(Uint32 flags)
{
    @autoreleasepool {
        if (flags & (SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
            [NSApplication sharedApplication];
            if ([NSApp activationPolicy] == NSApplicationActivationPolicyProhibited)
                [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp finishLaunching];
        }
        if (flags & SDL_INIT_JOYSTICK)
            refresh_hid_devices();
    }
    return 0;
}

void SDLCALL DOSBoxMac_QuitSubSystem(Uint32 flags)
{
    if ((flags & SDL_INIT_JOYSTICK) && hid_manager) {
        for (auto device : hid_devices)
            CFRelease(device);
        hid_devices.clear();
        IOHIDManagerClose(hid_manager, kIOHIDOptionsTypeNone);
        CFRelease(hid_manager);
        hid_manager = nullptr;
    }
}

void SDLCALL DOSBoxMac_Quit(void)
{
    macosx_native_shutdown();
}

} // extern "C"

void macosx_native_shutdown(void)
{
    DOSBoxMac_CloseAudioDevice(1);
    DOSBoxMac_QuitSubSystem(SDL_INIT_JOYSTICK);
    if (main_window)
        DOSBoxMac_DestroyWindow(main_window);
}

extern "C" {

const char *SDLCALL DOSBoxMac_GetError(void)
{
    return last_error.c_str();
}

int SDLCALL DOSBoxMac_Error(SDL_errorcode code)
{
    switch (code) {
    case SDL_ENOMEM: set_error("Out of memory"); break;
    case SDL_EFREAD: set_error("Read error"); break;
    case SDL_EFWRITE: set_error("Write error"); break;
    case SDL_EFSEEK: set_error("Seek error"); break;
    case SDL_UNSUPPORTED: set_error("Unsupported operation"); break;
    default: set_error("SDL compatibility error"); break;
    }
    return -1;
}

int SDLCALL DOSBoxMac_SetError(const char *fmt, ...)
{
    if (!fmt) {
        last_error.clear();
        return -1;
    }
    char buffer[1024] = {};
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    last_error = buffer;
    return -1;
}

void SDLCALL DOSBoxMac_ClearError(void)
{
    last_error.clear();
}

void SDLCALL DOSBoxMac_GetVersion(SDL_version *version)
{
    if (!version)
        return;
    version->major = 2;
    version->minor = 0;
    version->patch = 0;
}

const char *SDLCALL DOSBoxMac_GetCurrentVideoDriver(void)
{
    return "AppKit";
}

const char *SDLCALL DOSBoxMac_GetCurrentAudioDriver(void)
{
    return "CoreAudio";
}

Uint32 SDLCALL DOSBoxMac_GetTicks(void)
{
    using namespace std::chrono;
    static const steady_clock::time_point origin = steady_clock::now();
    return static_cast<Uint32>(duration_cast<milliseconds>(steady_clock::now() - origin).count());
}

void SDLCALL DOSBoxMac_Delay(Uint32 milliseconds)
{
    usleep(static_cast<useconds_t>(milliseconds) * 1000u);
}

SDL_Window *SDLCALL DOSBoxMac_CreateWindow(const char *title, int x, int y,
                                            int w, int h, Uint32 flags)
{
    @autoreleasepool {
        if (DOSBoxMac_InitSubSystem(SDL_INIT_VIDEO) < 0)
            return nullptr;

        auto *window = new SDL_Window();
        NSWindowStyleMask style = NSWindowStyleMaskTitled |
                                  NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable;
        if (flags & SDL_WINDOW_RESIZABLE)
            style |= NSWindowStyleMaskResizable;

        NSScreen *screen = screen_for_window_position(x, y);
        const NSRect screenFrame = screen ? [screen frame] : NSMakeRect(0, 0, 1440, 900);
        const CGFloat width = std::max(w, 1);
        const CGFloat height = std::max(h, 1);

        const bool centered = SDL_WINDOWPOS_ISCENTERED(x) || SDL_WINDOWPOS_ISCENTERED(y);
        const bool undefined = SDL_WINDOWPOS_ISUNDEFINED(x) || SDL_WINDOWPOS_ISUNDEFINED(y);
        CGFloat px = centered || undefined
                         ? NSMidX(screenFrame) - width / 2.0
                         : static_cast<CGFloat>(x);
        CGFloat py = centered || undefined
                         ? NSMidY(screenFrame) - height / 2.0
                         : cocoa_desktop_top() - static_cast<CGFloat>(y) - height;

        NSRect rect = NSMakeRect(px, py, width, height);
        window->nswindow = [[NSWindow alloc] initWithContentRect:rect
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO
                                                          screen:screen];
        if (!window->nswindow) {
            delete window;
            set_error("AppKit could not create an NSWindow");
            return nullptr;
        }

        window->flags = flags | SDL_WINDOW_SHOWN;
        [window->nswindow setColorSpace:[NSColorSpace sRGBColorSpace]];
        [window->nswindow setOneShot:NO];
        [window->nswindow setAcceptsMouseMovedEvents:YES];
        [window->nswindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
        if ([window->nswindow respondsToSelector:@selector(setTabbingMode:)])
            [window->nswindow setTabbingMode:NSWindowTabbingModeDisallowed];

        window->view = [[DOSBoxMacSurfaceView alloc] initWithFrame:
                        NSMakeRect(0, 0, width, height)];
        window->view.owner = window;
        window->view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [window->nswindow setContentView:window->view];

        window->delegate = [[DOSBoxMacWindowDelegate alloc] init];
        window->delegate.owner = window;
        [window->nswindow setDelegate:window->delegate];
        [window->nswindow setReleasedWhenClosed:NO];
        [window->nswindow setTitle:title ? [NSString stringWithUTF8String:title] : @"DOSBox-X"];
        [window->nswindow makeKeyAndOrderFront:nil];
        activate_application();

        main_window = window;
        if (flags & SDL_WINDOW_FULLSCREEN)
            DOSBoxMac_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN_DESKTOP);
        return window;
    }
}

void SDLCALL DOSBoxMac_DestroyWindow(SDL_Window *window)
{
    if (!window)
        return;
    @autoreleasepool {
        if (window->surface)
            DOSBoxMac_FreeSurface(window->surface);
        window->surface = nullptr;
        [window->nswindow setDelegate:nil];
        [window->nswindow orderOut:nil];
        [window->nswindow close];
        window->view.owner = nullptr;
        window->delegate.owner = nullptr;
        if (main_window == window)
            main_window = nullptr;
        delete window;
    }
}

Uint32 SDLCALL DOSBoxMac_GetWindowFlags(SDL_Window *window)
{
    if (!window)
        return 0;
    Uint32 flags = window->flags;
    if ([window->nswindow isMiniaturized])
        flags |= SDL_WINDOW_MINIMIZED;
    if ([window->nswindow isZoomed])
        flags |= SDL_WINDOW_MAXIMIZED;
    return flags;
}

void SDLCALL DOSBoxMac_SetWindowTitle(SDL_Window *window, const char *title)
{
    if (!window || !window->nswindow)
        return;
    @autoreleasepool {
        [window->nswindow setTitle:title ? [NSString stringWithUTF8String:title] : @""];
    }
}

void SDLCALL DOSBoxMac_SetWindowPosition(SDL_Window *window, int x, int y)
{
    if (!window || !window->nswindow)
        return;

    NSScreen *screen = screen_for_window_position(x, y);
    const NSRect screenFrame = screen ? [screen frame] : NSMakeRect(0, 0, 1440, 900);
    NSRect content = [window->nswindow contentRectForFrameRect:[window->nswindow frame]];

    if (SDL_WINDOWPOS_ISCENTERED(x))
        content.origin.x = NSMidX(screenFrame) - content.size.width / 2.0;
    else if (!SDL_WINDOWPOS_ISUNDEFINED(x))
        content.origin.x = static_cast<CGFloat>(x);

    if (SDL_WINDOWPOS_ISCENTERED(y))
        content.origin.y = NSMidY(screenFrame) - content.size.height / 2.0;
    else if (!SDL_WINDOWPOS_ISUNDEFINED(y))
        content.origin.y = cocoa_desktop_top() - static_cast<CGFloat>(y) - content.size.height;

    [window->nswindow setFrame:[window->nswindow frameRectForContentRect:content] display:YES];
}

void SDLCALL DOSBoxMac_GetWindowPosition(SDL_Window *window, int *x, int *y)
{
    if (!window || !window->nswindow)
        return;
    const NSRect rect = sdl_content_rect_from_window(window);
    if (x)
        *x = static_cast<int>(std::lround(rect.origin.x));
    if (y)
        *y = static_cast<int>(std::lround(rect.origin.y));
}

void SDLCALL DOSBoxMac_SetWindowSize(SDL_Window *window, int w, int h)
{
    if (!window || !window->nswindow)
        return;

    NSRect content = [window->nswindow contentRectForFrameRect:[window->nswindow frame]];
    const CGFloat top = NSMaxY(content);
    content.size = NSMakeSize(std::max(w, 1), std::max(h, 1));
    content.origin.y = top - content.size.height;
    [window->nswindow setFrame:[window->nswindow frameRectForContentRect:content] display:YES];

    if (window->surface && (window->surface->w != w || window->surface->h != h)) {
        DOSBoxMac_FreeSurface(window->surface);
        window->surface = nullptr;
    }
}

void SDLCALL DOSBoxMac_GetWindowSize(SDL_Window *window, int *w, int *h)
{
    if (!window || !window->nswindow)
        return;
    const NSRect bounds = [window->view bounds];
    if (w)
        *w = static_cast<int>(std::lround(bounds.size.width));
    if (h)
        *h = static_cast<int>(std::lround(bounds.size.height));
}

void SDLCALL DOSBoxMac_SetWindowResizable(SDL_Window *window, SDL_bool resizable)
{
    if (!window || !window->nswindow)
        return;
    NSWindowStyleMask style = [window->nswindow styleMask];
    if (resizable)
        style |= NSWindowStyleMaskResizable;
    else
        style &= ~NSWindowStyleMaskResizable;
    [window->nswindow setStyleMask:style];
}

void SDLCALL DOSBoxMac_MaximizeWindow(SDL_Window *window)
{
    if (window && window->nswindow)
        [window->nswindow zoom:nil];
}

int SDLCALL DOSBoxMac_SetWindowFullscreen(SDL_Window *window, Uint32 flags)
{
    if (!window || !window->nswindow)
        return -1;
    const bool want = (flags & (SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP)) != 0;
    const bool have = ([window->nswindow styleMask] & NSWindowStyleMaskFullScreen) != 0;
    if (want != have && !window->fullscreen_transition) {
        window->fullscreen_transition = true;
        [window->nswindow toggleFullScreen:nil];
    }
    if (want)
        window->flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    else
        window->flags &= ~(SDL_WINDOW_FULLSCREEN | SDL_WINDOW_FULLSCREEN_DESKTOP);
    return 0;
}

int SDLCALL DOSBoxMac_SetWindowOpacity(SDL_Window *window, float opacity)
{
    if (!window || !window->nswindow)
        return -1;
    [window->nswindow setAlphaValue:std::max(0.0f, std::min(opacity, 1.0f))];
    return 0;
}

void SDLCALL DOSBoxMac_SetWindowIcon(SDL_Window *, SDL_Surface *)
{
    /* The app-bundle icon is authoritative on macOS. */
}

SDL_Surface *SDLCALL DOSBoxMac_GetWindowSurface(SDL_Window *window)
{
    if (!window)
        return nullptr;
    int w = 0;
    int h = 0;
    DOSBoxMac_GetWindowSize(window, &w, &h);
    if (!window->surface || window->surface->w != w || window->surface->h != h) {
        if (window->surface)
            DOSBoxMac_FreeSurface(window->surface);
        window->surface = DOSBoxMac_CreateRGBSurface(0, std::max(w, 1), std::max(h, 1), 32,
                                                      0x00ff0000u, 0x0000ff00u,
                                                      0x000000ffu, 0xff000000u);
    }
    return window->surface;
}

int SDLCALL DOSBoxMac_UpdateWindowSurface(SDL_Window *window)
{
    if (!window || !window->view)
        return -1;
    [window->view setNeedsDisplay:YES];
    [window->view displayIfNeeded];
    return 0;
}

int SDLCALL DOSBoxMac_UpdateWindowSurfaceRects(SDL_Window *window,
                                               const SDL_Rect *, int)
{
    return DOSBoxMac_UpdateWindowSurface(window);
}

Uint32 SDLCALL DOSBoxMac_GetWindowPixelFormat(SDL_Window *)
{
    return SDL_PIXELFORMAT_BGRA32;
}

int SDLCALL DOSBoxMac_SetWindowDisplayMode(SDL_Window *window, const SDL_DisplayMode *mode)
{
    if (!window)
        return -1;
    if (mode)
        window->mode = *mode;
    else
        window->mode = {};
    return 0;
}

int SDLCALL DOSBoxMac_GetWindowDisplayMode(SDL_Window *window, SDL_DisplayMode *mode)
{
    if (!window || !mode)
        return -1;
    if (window->mode.w > 0 && window->mode.h > 0) {
        *mode = window->mode;
        return 0;
    }
    const int display = DOSBoxMac_GetWindowDisplayIndex(window);
    return DOSBoxMac_GetCurrentDisplayMode(display >= 0 ? display : 0, mode);
}

int SDLCALL DOSBoxMac_GetDesktopDisplayMode(int display, SDL_DisplayMode *mode)
{
    return DOSBoxMac_GetCurrentDisplayMode(display, mode);
}

int SDLCALL DOSBoxMac_GetCurrentDisplayMode(int display, SDL_DisplayMode *mode)
{
    if (!mode)
        return -1;
    NSScreen *screen = screen_for_index(display);
    const CGDirectDisplayID display_id = display_id_for_screen(screen);
    if (!screen || display_id == kCGNullDirectDisplay)
        return -1;

    CGDisplayModeRef cgmode = CGDisplayCopyDisplayMode(display_id);
    if (!cgmode)
        return -1;

    mode->format = SDL_PIXELFORMAT_BGRA32;
    mode->w = static_cast<int>(CGDisplayModeGetWidth(cgmode));
    mode->h = static_cast<int>(CGDisplayModeGetHeight(cgmode));
    const double refresh = CGDisplayModeGetRefreshRate(cgmode);
    mode->refresh_rate = refresh > 0.0 ? static_cast<int>(std::lround(refresh)) : 0;
    mode->driverdata = nullptr;
    CGDisplayModeRelease(cgmode);
    return 0;
}

int SDLCALL DOSBoxMac_GetDisplayBounds(int display, SDL_Rect *rect)
{
    if (!rect)
        return -1;
    NSScreen *screen = screen_for_index(display);
    const CGDirectDisplayID display_id = display_id_for_screen(screen);
    if (!screen || display_id == kCGNullDirectDisplay)
        return -1;

    const CGRect bounds = CGDisplayBounds(display_id);
    rect->x = static_cast<int>(std::lround(bounds.origin.x));
    rect->y = static_cast<int>(std::lround(bounds.origin.y));
    rect->w = static_cast<int>(std::lround(bounds.size.width));
    rect->h = static_cast<int>(std::lround(bounds.size.height));
    return 0;
}

int SDLCALL DOSBoxMac_GetNumVideoDisplays(void)
{
    return static_cast<int>([[NSScreen screens] count]);
}

int SDLCALL DOSBoxMac_GetWindowDisplayIndex(SDL_Window *window)
{
    if (!window || !window->nswindow)
        return -1;
    const int index = screen_index([window->nswindow screen]);
    if (index >= 0)
        return index;
    set_error("Could not determine the display containing the native macOS window");
    return -1;
}

void SDLCALL DOSBoxMac_SetWindowKeyboardGrab(SDL_Window *window, SDL_bool grabbed)
{
    if (window)
        window->keyboard_grab = grabbed;
}

SDL_bool SDLCALL DOSBoxMac_GetWindowKeyboardGrab(SDL_Window *window)
{
    return window ? window->keyboard_grab : SDL_FALSE;
}

int SDLCALL DOSBoxMac_ShowCursor(int toggle)
{
    const bool previous = !cursor_hidden;
    if (toggle == SDL_QUERY)
        return previous ? SDL_ENABLE : SDL_DISABLE;
    if (toggle == SDL_DISABLE && !cursor_hidden) {
        [NSCursor hide];
        cursor_hidden = true;
    } else if (toggle == SDL_ENABLE && cursor_hidden) {
        [NSCursor unhide];
        cursor_hidden = false;
    }
    return previous ? SDL_ENABLE : SDL_DISABLE;
}

int SDLCALL DOSBoxMac_SetRelativeMouseMode(SDL_bool enabled)
{
    const bool want = enabled == SDL_TRUE;
    if (relative_mouse == want)
        return 0;
    relative_mouse = want;
    CGAssociateMouseAndMouseCursorPosition(want ? false : true);
    return 0;
}

void SDLCALL DOSBoxMac_DestroyRenderer(SDL_Renderer *)
{
}

void SDLCALL DOSBoxMac_DestroyTexture(SDL_Texture *)
{
}

void SDLCALL DOSBoxMac_PumpEvents(void)
{
    @autoreleasepool {
        pump_appkit_once(false);
    }
}

int SDLCALL DOSBoxMac_PollEvent(SDL_Event *event)
{
    DOSBoxMac_PumpEvents();
    return pop_event(event) ? 1 : 0;
}

int SDLCALL DOSBoxMac_WaitEvent(SDL_Event *event)
{
    while (!pop_event(event)) {
        @autoreleasepool {
            pump_appkit_once(true);
        }
    }
    return 1;
}

int SDLCALL DOSBoxMac_PushEvent(SDL_Event *event)
{
    if (!event)
        return -1;
    push_event(*event);
    return 1;
}

int SDLCALL DOSBoxMac_PeepEvents(SDL_Event *events, int numevents,
                                 SDL_eventaction action,
                                 Uint32 minType, Uint32 maxType)
{
    if (!events || numevents <= 0)
        return 0;

    std::lock_guard<std::mutex> lock(event_mutex);
    int count = 0;
    for (auto it = event_queue.begin(); it != event_queue.end() && count < numevents;) {
        if (it->type >= minType && it->type <= maxType) {
            events[count++] = *it;
            if (action == SDL_GETEVENT)
                it = event_queue.erase(it);
            else
                ++it;
        } else {
            ++it;
        }
    }
    return count;
}

Uint8 SDLCALL DOSBoxMac_EventState(Uint32, int)
{
    return SDL_ENABLE;
}

SDL_Keymod SDLCALL DOSBoxMac_GetModState(void)
{
    return mod_state;
}

const char *SDLCALL DOSBoxMac_GetKeyName(SDL_Keycode key)
{
    static thread_local char name[32];
    if (key >= 32 && key < 127) {
        name[0] = static_cast<char>(key);
        name[1] = '\0';
        return name;
    }
    switch (key) {
    case SDLK_RETURN: return "Return";
    case SDLK_ESCAPE: return "Escape";
    case SDLK_BACKSPACE: return "Backspace";
    case SDLK_TAB: return "Tab";
    case SDLK_LEFT: return "Left";
    case SDLK_RIGHT: return "Right";
    case SDLK_UP: return "Up";
    case SDLK_DOWN: return "Down";
    case SDLK_LSHIFT: return "Left Shift";
    case SDLK_RSHIFT: return "Right Shift";
    case SDLK_LCTRL: return "Left Ctrl";
    case SDLK_RCTRL: return "Right Ctrl";
    case SDLK_LALT: return "Left Option";
    case SDLK_RALT: return "Right Option";
    case SDLK_LGUI: return "Command";
    default:
        std::snprintf(name, sizeof(name), "Key %d", static_cast<int>(key));
        return name;
    }
}

const char *SDLCALL DOSBoxMac_GetScancodeName(SDL_Scancode scancode)
{
    static thread_local char name[32];
    if (scancode >= SDL_SCANCODE_A && scancode <= SDL_SCANCODE_Z) {
        name[0] = static_cast<char>('A' + (scancode - SDL_SCANCODE_A));
        name[1] = '\0';
        return name;
    }
    std::snprintf(name, sizeof(name), "Scancode %d", static_cast<int>(scancode));
    return name;
}

void SDLCALL DOSBoxMac_StartTextInput(void)
{
    text_input_enabled = true;
}

void SDLCALL DOSBoxMac_StopTextInput(void)
{
    text_input_enabled = false;
}

void SDLCALL DOSBoxMac_SetTextInputRect(const SDL_Rect *)
{
}

SDL_bool SDLCALL DOSBoxMac_SetHint(const char *, const char *)
{
    return SDL_TRUE;
}

SDL_bool SDLCALL DOSBoxMac_SetHintWithPriority(const char *, const char *,
                                               SDL_HintPriority)
{
    return SDL_TRUE;
}

SDL_Surface *SDLCALL DOSBoxMac_CreateRGBSurface(Uint32 flags, int width, int height,
                                                int depth, Uint32 rmask, Uint32 gmask,
                                                Uint32 bmask, Uint32 amask)
{
    if (width <= 0 || height <= 0 || depth <= 0) {
        set_error("invalid surface dimensions");
        return nullptr;
    }

    auto *surface = static_cast<SDL_Surface *>(std::calloc(1, sizeof(SDL_Surface)));
    if (!surface)
        return nullptr;
    surface->format = make_format(SDL_PIXELFORMAT_UNKNOWN, depth, rmask, gmask, bmask, amask);
    if (!surface->format) {
        std::free(surface);
        return nullptr;
    }

    surface->flags = flags;
    surface->w = width;
    surface->h = height;
    surface->pitch = width * surface->format->BytesPerPixel;
    surface->pixels = std::calloc(static_cast<size_t>(height), static_cast<size_t>(surface->pitch));
    if (!surface->pixels) {
        std::free(surface->format);
        std::free(surface);
        return nullptr;
    }
    surface->clip_rect = {0, 0, width, height};
    surface->refcount = 1;
    if (depth <= 8)
        surface->format->palette = DOSBoxMac_AllocPalette(1 << depth);
    owned_surfaces.insert(surface);
    return surface;
}

SDL_Surface *SDLCALL DOSBoxMac_CreateRGBSurfaceFrom(void *pixels, int width, int height,
                                                    int depth, int pitch, Uint32 rmask,
                                                    Uint32 gmask, Uint32 bmask, Uint32 amask)
{
    if (!pixels || width <= 0 || height <= 0)
        return nullptr;
    auto *surface = static_cast<SDL_Surface *>(std::calloc(1, sizeof(SDL_Surface)));
    if (!surface)
        return nullptr;
    surface->format = make_format(SDL_PIXELFORMAT_UNKNOWN, depth, rmask, gmask, bmask, amask);
    if (!surface->format) {
        std::free(surface);
        return nullptr;
    }
    surface->w = width;
    surface->h = height;
    surface->pitch = pitch;
    surface->pixels = pixels;
    surface->clip_rect = {0, 0, width, height};
    surface->refcount = 1;
    return surface;
}

void SDLCALL DOSBoxMac_FreeSurface(SDL_Surface *surface)
{
    if (!surface)
        return;
    if (owned_surfaces.erase(surface))
        std::free(surface->pixels);
    if (surface->format) {
        if (surface->format->palette)
            DOSBoxMac_FreePalette(surface->format->palette);
        std::free(surface->format);
    }
    std::free(surface);
}

int SDLCALL DOSBoxMac_LockSurface(SDL_Surface *surface)
{
    if (!surface)
        return -1;
    ++surface->locked;
    return 0;
}

void SDLCALL DOSBoxMac_UnlockSurface(SDL_Surface *surface)
{
    if (surface && surface->locked > 0)
        --surface->locked;
}

int SDLCALL DOSBoxMac_UpperBlit(SDL_Surface *src, const SDL_Rect *srcrect,
                                SDL_Surface *dst, SDL_Rect *dstrect)
{
    if (!src || !dst || !src->format || !dst->format)
        return -1;
    SDL_Rect s = srcrect ? *srcrect : SDL_Rect{0, 0, src->w, src->h};
    SDL_Rect d = dstrect ? *dstrect : SDL_Rect{0, 0, s.w, s.h};
    const int width = std::max(0, std::min({s.w, d.w, src->w - s.x, dst->w - d.x}));
    const int height = std::max(0, std::min({s.h, d.h, src->h - s.y, dst->h - d.y}));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            write_pixel(dst, d.x + x, d.y + y,
                        convert_pixel(src, dst, read_pixel(src, s.x + x, s.y + y)));
    if (dstrect) {
        dstrect->w = width;
        dstrect->h = height;
    }
    return 0;
}

int SDLCALL DOSBoxMac_UpperBlitScaled(SDL_Surface *src, const SDL_Rect *srcrect,
                                      SDL_Surface *dst, SDL_Rect *dstrect)
{
    if (!src || !dst || !dstrect || dstrect->w <= 0 || dstrect->h <= 0)
        return -1;
    SDL_Rect s = srcrect ? *srcrect : SDL_Rect{0, 0, src->w, src->h};
    for (int y = 0; y < dstrect->h; ++y) {
        const int sy = s.y + (y * s.h) / dstrect->h;
        for (int x = 0; x < dstrect->w; ++x) {
            const int sx = s.x + (x * s.w) / dstrect->w;
            if (dstrect->x + x >= 0 && dstrect->x + x < dst->w &&
                dstrect->y + y >= 0 && dstrect->y + y < dst->h)
                write_pixel(dst, dstrect->x + x, dstrect->y + y,
                            convert_pixel(src, dst, read_pixel(src, sx, sy)));
        }
    }
    return 0;
}

int SDLCALL DOSBoxMac_FillRect(SDL_Surface *dst, const SDL_Rect *rect, Uint32 color)
{
    if (!dst || !dst->format)
        return -1;
    SDL_Rect r = rect ? *rect : SDL_Rect{0, 0, dst->w, dst->h};
    const int x0 = std::max(0, r.x);
    const int y0 = std::max(0, r.y);
    const int x1 = std::min(dst->w, r.x + r.w);
    const int y1 = std::min(dst->h, r.y + r.h);
    for (int y = y0; y < y1; ++y)
        for (int x = x0; x < x1; ++x)
            write_pixel(dst, x, y, color);
    return 0;
}

Uint32 SDLCALL DOSBoxMac_MapRGB(const SDL_PixelFormat *format, Uint8 r, Uint8 g, Uint8 b)
{
    if (!format)
        return 0;
    Uint32 pixel = 0;
    if (format->Rmask)
        pixel |= (static_cast<Uint32>(r >> format->Rloss) << format->Rshift) & format->Rmask;
    if (format->Gmask)
        pixel |= (static_cast<Uint32>(g >> format->Gloss) << format->Gshift) & format->Gmask;
    if (format->Bmask)
        pixel |= (static_cast<Uint32>(b >> format->Bloss) << format->Bshift) & format->Bmask;
    if (format->Amask)
        pixel |= format->Amask;
    return pixel;
}

SDL_PixelFormat *SDLCALL DOSBoxMac_AllocFormat(Uint32 format)
{
    if (format == SDL_PIXELFORMAT_RGB565)
        return make_format(format, 16, 0xf800u, 0x07e0u, 0x001fu, 0);

    if (format == SDL_PIXELFORMAT_RGBA32 || format == SDL_PIXELFORMAT_ABGR8888)
        return make_format(format, 32, 0x000000ffu, 0x0000ff00u,
                           0x00ff0000u, 0xff000000u);

    return make_format(format, 32, 0x00ff0000u, 0x0000ff00u,
                       0x000000ffu, 0xff000000u);
}

void SDLCALL DOSBoxMac_FreeFormat(SDL_PixelFormat *format)
{
    if (!format)
        return;
    if (format->palette)
        DOSBoxMac_FreePalette(format->palette);
    std::free(format);
}

const char *SDLCALL DOSBoxMac_GetPixelFormatName(Uint32 format)
{
    if (format == SDL_PIXELFORMAT_RGB565)
        return "RGB565";
    if (format == SDL_PIXELFORMAT_RGBA32 || format == SDL_PIXELFORMAT_ABGR8888)
        return "RGBA32";
    if (format == SDL_PIXELFORMAT_BGRA32 || format == SDL_PIXELFORMAT_ARGB8888)
        return "BGRA32";
    return "UNKNOWN";
}

SDL_Palette *SDLCALL DOSBoxMac_AllocPalette(int ncolors)
{
    if (ncolors <= 0)
        return nullptr;
    auto *palette = static_cast<SDL_Palette *>(std::calloc(1, sizeof(SDL_Palette)));
    if (!palette)
        return nullptr;
    palette->colors = static_cast<SDL_Color *>(std::calloc(static_cast<size_t>(ncolors),
                                                           sizeof(SDL_Color)));
    if (!palette->colors) {
        std::free(palette);
        return nullptr;
    }
    palette->ncolors = ncolors;
    palette->refcount = 1;
    return palette;
}

void SDLCALL DOSBoxMac_FreePalette(SDL_Palette *palette)
{
    if (!palette)
        return;
    if (palette->refcount > 1) {
        --palette->refcount;
        return;
    }
    std::free(palette->colors);
    std::free(palette);
}

int SDLCALL DOSBoxMac_SetPaletteColors(SDL_Palette *palette, const SDL_Color *colors,
                                       int firstcolor, int ncolors)
{
    if (!palette || !colors || firstcolor < 0 || ncolors < 0 ||
        firstcolor + ncolors > palette->ncolors)
        return -1;
    std::memcpy(palette->colors + firstcolor, colors,
                static_cast<size_t>(ncolors) * sizeof(SDL_Color));
    ++palette->version;
    return 0;
}

int SDLCALL DOSBoxMac_SetSurfacePalette(SDL_Surface *surface, SDL_Palette *palette)
{
    if (!surface || !surface->format)
        return -1;
    if (surface->format->palette && surface->format->palette != palette)
        DOSBoxMac_FreePalette(surface->format->palette);
    surface->format->palette = palette;
    if (palette)
        ++palette->refcount;
    return 0;
}

int SDLCALL DOSBoxMac_SetSurfaceAlphaMod(SDL_Surface *, Uint8)
{
    return 0;
}

int SDLCALL DOSBoxMac_SetSurfaceBlendMode(SDL_Surface *, SDL_BlendMode)
{
    return 0;
}

int SDLCALL DOSBoxMac_SetColorKey(SDL_Surface *, int, Uint32)
{
    return 0;
}

SDL_AudioDeviceID SDLCALL DOSBoxMac_OpenAudioDevice(const char *, int iscapture,
                                                     const SDL_AudioSpec *desired,
                                                     SDL_AudioSpec *obtained,
                                                     int)
{
    if (iscapture || !desired || desired->format != AUDIO_S16SYS ||
        desired->channels != 2 || !desired->callback) {
        set_error("native macOS audio requires signed 16-bit stereo output");
        return 0;
    }

    if (audio_state.opened)
        DOSBoxMac_CloseAudioDevice(1);

    AudioComponentDescription desc = {};
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent component = AudioComponentFindNext(nullptr, &desc);
    if (!component || AudioComponentInstanceNew(component, &audio_state.unit) != noErr) {
        set_error("AudioUnit default output unavailable");
        audio_state.unit = nullptr;
        return 0;
    }

    AudioStreamBasicDescription format = {};
    format.mSampleRate = desired->freq;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 4;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 4;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 16;

    if (AudioUnitSetProperty(audio_state.unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &format, sizeof(format)) != noErr) {
        set_error("AudioUnit rejected DOSBox-X PCM format");
        AudioComponentInstanceDispose(audio_state.unit);
        audio_state.unit = nullptr;
        return 0;
    }

    AURenderCallbackStruct callback = {};
    callback.inputProc = audio_render;
    if (AudioUnitSetProperty(audio_state.unit, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callback, sizeof(callback)) != noErr ||
        AudioUnitInitialize(audio_state.unit) != noErr) {
        set_error("AudioUnit initialization failed");
        AudioComponentInstanceDispose(audio_state.unit);
        audio_state.unit = nullptr;
        return 0;
    }

    if (!audio_state.mutex_ready) {
        pthread_mutexattr_t attr;
        pthread_mutexattr_init(&attr);
        pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&audio_state.mutex, &attr);
        pthread_mutexattr_destroy(&attr);
        audio_state.mutex_ready = true;
    }

    audio_state.spec = *desired;
    if (obtained)
        *obtained = *desired;
    audio_state.opened = true;
    audio_state.running = false;
    return 1;
}

void SDLCALL DOSBoxMac_CloseAudioDevice(SDL_AudioDeviceID)
{
    if (!audio_state.opened)
        return;
    if (audio_state.running)
        AudioOutputUnitStop(audio_state.unit);
    AudioUnitUninitialize(audio_state.unit);
    AudioComponentInstanceDispose(audio_state.unit);
    audio_state.unit = nullptr;
    audio_state.opened = false;
    audio_state.running = false;
}

void SDLCALL DOSBoxMac_PauseAudioDevice(SDL_AudioDeviceID, int pause_on)
{
    if (!audio_state.opened)
        return;
    if (pause_on) {
        if (audio_state.running)
            AudioOutputUnitStop(audio_state.unit);
        audio_state.running = false;
    } else {
        if (!audio_state.running)
            AudioOutputUnitStart(audio_state.unit);
        audio_state.running = true;
    }
}

void SDLCALL DOSBoxMac_LockAudioDevice(SDL_AudioDeviceID)
{
    if (audio_state.mutex_ready)
        pthread_mutex_lock(&audio_state.mutex);
}

void SDLCALL DOSBoxMac_UnlockAudioDevice(SDL_AudioDeviceID)
{
    if (audio_state.mutex_ready)
        pthread_mutex_unlock(&audio_state.mutex);
}

int SDLCALL DOSBoxMac_NumJoysticks(void)
{
    refresh_hid_devices();
    return static_cast<int>(hid_devices.size());
}

SDL_Joystick *SDLCALL DOSBoxMac_JoystickOpen(int device_index)
{
    if (device_index < 0 || device_index >= static_cast<int>(hid_devices.size()))
        return nullptr;
    auto *joystick = new SDL_Joystick();
    joystick->device = hid_devices[static_cast<size_t>(device_index)];
    CFRetain(joystick->device);
    joystick->name = device_name(joystick->device);
    enumerate_elements(joystick);
    return joystick;
}

void SDLCALL DOSBoxMac_JoystickClose(SDL_Joystick *joystick)
{
    if (!joystick)
        return;
    for (auto element : joystick->axes) CFRelease(element);
    for (auto element : joystick->buttons) CFRelease(element);
    for (auto element : joystick->hats) CFRelease(element);
    if (joystick->device) CFRelease(joystick->device);
    delete joystick;
}

void SDLCALL DOSBoxMac_JoystickUpdate(void)
{
}

int SDLCALL DOSBoxMac_JoystickEventState(int state)
{
    return state == SDL_QUERY ? SDL_ENABLE : state;
}

Sint16 SDLCALL DOSBoxMac_JoystickGetAxis(SDL_Joystick *joystick, int axis)
{
    if (!joystick || axis < 0 || axis >= static_cast<int>(joystick->axes.size()))
        return 0;
    IOHIDElementRef element = joystick->axes[static_cast<size_t>(axis)];
    bool ok = false;
    const CFIndex value = element_value(joystick->device, element, ok);
    if (!ok)
        return 0;
    const CFIndex minv = IOHIDElementGetLogicalMin(element);
    const CFIndex maxv = IOHIDElementGetLogicalMax(element);
    if (maxv <= minv)
        return 0;
    const double norm = static_cast<double>(value - minv) /
                        static_cast<double>(maxv - minv);
    const long scaled = std::lround(norm * 65535.0 - 32768.0);
    return static_cast<Sint16>(std::max(-32768L, std::min(32767L, scaled)));
}

Uint8 SDLCALL DOSBoxMac_JoystickGetButton(SDL_Joystick *joystick, int button)
{
    if (!joystick || button < 0 || button >= static_cast<int>(joystick->buttons.size()))
        return 0;
    bool ok = false;
    return element_value(joystick->device,
                         joystick->buttons[static_cast<size_t>(button)], ok) && ok ? 1 : 0;
}

Uint8 SDLCALL DOSBoxMac_JoystickGetHat(SDL_Joystick *joystick, int hat)
{
    if (!joystick || hat < 0 || hat >= static_cast<int>(joystick->hats.size()))
        return SDL_HAT_CENTERED;
    IOHIDElementRef element = joystick->hats[static_cast<size_t>(hat)];
    bool ok = false;
    const CFIndex raw = element_value(joystick->device, element, ok);
    if (!ok)
        return SDL_HAT_CENTERED;
    const CFIndex value = raw - IOHIDElementGetLogicalMin(element);
    switch (value) {
    case 0: return SDL_HAT_UP;
    case 1: return SDL_HAT_RIGHTUP;
    case 2: return SDL_HAT_RIGHT;
    case 3: return SDL_HAT_RIGHTDOWN;
    case 4: return SDL_HAT_DOWN;
    case 5: return SDL_HAT_LEFTDOWN;
    case 6: return SDL_HAT_LEFT;
    case 7: return SDL_HAT_LEFTUP;
    default: return SDL_HAT_CENTERED;
    }
}

const char *SDLCALL DOSBoxMac_JoystickName(SDL_Joystick *joystick)
{
    return joystick ? joystick->name.c_str() : nullptr;
}

const char *SDLCALL DOSBoxMac_JoystickNameForIndex(int device_index)
{
    if (device_index < 0 || device_index >= static_cast<int>(hid_devices.size()))
        return nullptr;
    hid_index_name = device_name(hid_devices[static_cast<size_t>(device_index)]);
    return hid_index_name.c_str();
}

int SDLCALL DOSBoxMac_JoystickNumAxes(SDL_Joystick *joystick)
{
    return joystick ? static_cast<int>(joystick->axes.size()) : 0;
}

int SDLCALL DOSBoxMac_JoystickNumButtons(SDL_Joystick *joystick)
{
    return joystick ? static_cast<int>(joystick->buttons.size()) : 0;
}

int SDLCALL DOSBoxMac_JoystickNumHats(SDL_Joystick *joystick)
{
    return joystick ? static_cast<int>(joystick->hats.size()) : 0;
}

SDL_mutex *SDLCALL DOSBoxMac_CreateMutex(void)
{
    auto *mutex = new SDL_mutex();
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    if (pthread_mutex_init(&mutex->mutex, &attr) != 0) {
        pthread_mutexattr_destroy(&attr);
        delete mutex;
        return nullptr;
    }
    pthread_mutexattr_destroy(&attr);
    return mutex;
}

void SDLCALL DOSBoxMac_DestroyMutex(SDL_mutex *mutex)
{
    if (!mutex)
        return;
    pthread_mutex_destroy(&mutex->mutex);
    delete mutex;
}

int SDLCALL DOSBoxMac_LockMutex(SDL_mutex *mutex)
{
    return mutex ? pthread_mutex_lock(&mutex->mutex) : -1;
}

int SDLCALL DOSBoxMac_UnlockMutex(SDL_mutex *mutex)
{
    return mutex ? pthread_mutex_unlock(&mutex->mutex) : -1;
}

SDL_sem *SDLCALL DOSBoxMac_CreateSemaphore(Uint32 initial_value)
{
    auto *sem = new SDL_semaphore();
    if (pthread_mutex_init(&sem->mutex, nullptr) != 0) {
        delete sem;
        return nullptr;
    }
    if (pthread_cond_init(&sem->cond, nullptr) != 0) {
        pthread_mutex_destroy(&sem->mutex);
        delete sem;
        return nullptr;
    }
    sem->value = initial_value;
    return sem;
}

void SDLCALL DOSBoxMac_DestroySemaphore(SDL_sem *sem)
{
    if (!sem)
        return;
    pthread_cond_destroy(&sem->cond);
    pthread_mutex_destroy(&sem->mutex);
    delete sem;
}

int SDLCALL DOSBoxMac_SemWait(SDL_sem *sem)
{
    if (!sem)
        return -1;
    pthread_mutex_lock(&sem->mutex);
    while (sem->value == 0)
        pthread_cond_wait(&sem->cond, &sem->mutex);
    --sem->value;
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}

int SDLCALL DOSBoxMac_SemTryWait(SDL_sem *sem)
{
    if (!sem)
        return -1;
    pthread_mutex_lock(&sem->mutex);
    if (sem->value == 0) {
        pthread_mutex_unlock(&sem->mutex);
        return SDL_MUTEX_TIMEDOUT;
    }
    --sem->value;
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}

int SDLCALL DOSBoxMac_SemWaitTimeout(SDL_sem *sem, Uint32 timeout)
{
    if (timeout == SDL_MUTEX_MAXWAIT)
        return DOSBoxMac_SemWait(sem);
    if (!sem)
        return -1;

    struct timespec deadline = {};
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += timeout / 1000;
    deadline.tv_nsec += static_cast<long>(timeout % 1000) * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        ++deadline.tv_sec;
        deadline.tv_nsec -= 1000000000L;
    }

    pthread_mutex_lock(&sem->mutex);
    int rc = 0;
    while (sem->value == 0 && rc == 0)
        rc = pthread_cond_timedwait(&sem->cond, &sem->mutex, &deadline);
    if (rc == 0 && sem->value > 0)
        --sem->value;
    pthread_mutex_unlock(&sem->mutex);
    return rc == 0 ? 0 : SDL_MUTEX_TIMEDOUT;
}

int SDLCALL DOSBoxMac_SemPost(SDL_sem *sem)
{
    if (!sem)
        return -1;
    pthread_mutex_lock(&sem->mutex);
    ++sem->value;
    pthread_cond_signal(&sem->cond);
    pthread_mutex_unlock(&sem->mutex);
    return 0;
}

Uint32 SDLCALL DOSBoxMac_SemValue(SDL_sem *sem)
{
    if (!sem)
        return 0;
    pthread_mutex_lock(&sem->mutex);
    const Uint32 value = sem->value;
    pthread_mutex_unlock(&sem->mutex);
    return value;
}

static void *dosbox_mac_thread_start(void *opaque)
{
    auto *thread = static_cast<SDL_Thread *>(opaque);
    const int status = thread->fn ? thread->fn(thread->data) : 0;

    pthread_mutex_lock(&thread->state_mutex);
    thread->status = status;
    thread->finished = true;
    const bool release = thread->detached;
    pthread_mutex_unlock(&thread->state_mutex);

    if (release) {
        pthread_mutex_destroy(&thread->state_mutex);
        delete thread;
    }
    return nullptr;
}

SDL_Thread *SDLCALL DOSBoxMac_CreateThread(SDL_ThreadFunction fn,
                                           const char *name,
                                           void *data)
{
    return DOSBoxMac_CreateThreadWithStackSize(fn, name, 0, data);
}

SDL_Thread *SDLCALL DOSBoxMac_CreateThreadWithStackSize(SDL_ThreadFunction fn,
                                                        const char *name,
                                                        size_t stacksize,
                                                        void *data)
{
    if (!fn)
        return nullptr;
    auto *thread = new SDL_Thread();
    thread->fn = fn;
    thread->data = data;
    if (pthread_mutex_init(&thread->state_mutex, nullptr) != 0) {
        delete thread;
        return nullptr;
    }

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    if (stacksize)
        pthread_attr_setstacksize(&attr, stacksize);
    const int rc = pthread_create(&thread->thread, &attr, dosbox_mac_thread_start, thread);
    pthread_attr_destroy(&attr);
    if (rc != 0) {
        pthread_mutex_destroy(&thread->state_mutex);
        delete thread;
        return nullptr;
    }
    (void)name;
    return thread;
}

void SDLCALL DOSBoxMac_WaitThread(SDL_Thread *thread, int *status)
{
    if (!thread)
        return;

    pthread_mutex_lock(&thread->state_mutex);
    const bool detached = thread->detached;
    pthread_mutex_unlock(&thread->state_mutex);
    if (detached)
        return;

    if (!thread->joined) {
        pthread_join(thread->thread, nullptr);
        thread->joined = true;
    }
    if (status)
        *status = thread->status;
    pthread_mutex_destroy(&thread->state_mutex);
    delete thread;
}

void SDLCALL DOSBoxMac_DetachThread(SDL_Thread *thread)
{
    if (!thread)
        return;

    pthread_detach(thread->thread);
    pthread_mutex_lock(&thread->state_mutex);
    if (thread->detached) {
        pthread_mutex_unlock(&thread->state_mutex);
        return;
    }
    thread->detached = true;
    const bool release = thread->finished;
    pthread_mutex_unlock(&thread->state_mutex);

    if (release) {
        pthread_mutex_destroy(&thread->state_mutex);
        delete thread;
    }
}

SDL_RWops *SDLCALL DOSBoxMac_AllocRW(void)
{
    return static_cast<SDL_RWops *>(std::calloc(1, sizeof(SDL_RWops)));
}

void SDLCALL DOSBoxMac_FreeRW(SDL_RWops *area)
{
    std::free(area);
}

SDL_RWops *SDLCALL DOSBoxMac_RWFromFile(const char *file, const char *mode)
{
    if (!file || !mode)
        return nullptr;
    FILE *fp = std::fopen(file, mode);
    if (!fp)
        return nullptr;
    SDL_RWops *rw = DOSBoxMac_AllocRW();
    if (!rw) {
        std::fclose(fp);
        return nullptr;
    }
    auto *ctx = new FileRW();
    ctx->file = fp;
    rw->size = file_size;
    rw->seek = file_seek;
    rw->read = file_read;
    rw->write = file_write;
    rw->close = file_close;
    rw->type = SDL_RWOPS_STDFILE;
    rw->hidden.unknown.data1 = ctx;
    return rw;
}

SDL_RWops *SDLCALL DOSBoxMac_RWFromMem(void *mem, int size)
{
    if (!mem || size < 0)
        return nullptr;
    SDL_RWops *rw = DOSBoxMac_AllocRW();
    if (!rw)
        return nullptr;
    rw->size = mem_size;
    rw->seek = mem_seek;
    rw->read = mem_read;
    rw->write = mem_write;
    rw->close = mem_close;
    rw->type = SDL_RWOPS_MEMORY;
    rw->hidden.mem.base = static_cast<Uint8 *>(mem);
    rw->hidden.mem.here = static_cast<Uint8 *>(mem);
    rw->hidden.mem.stop = static_cast<Uint8 *>(mem) + size;
    return rw;
}

SDL_RWops *SDLCALL DOSBoxMac_RWFromConstMem(const void *mem, int size)
{
    SDL_RWops *rw = DOSBoxMac_RWFromMem(const_cast<void *>(mem), size);
    if (rw)
        rw->type = SDL_RWOPS_MEMORY_RO;
    return rw;
}

Sint64 SDLCALL DOSBoxMac_RWsize(SDL_RWops *context)
{
    return (context && context->size) ? context->size(context) : -1;
}

Sint64 SDLCALL DOSBoxMac_RWseek(SDL_RWops *context, Sint64 offset, int whence)
{
    return (context && context->seek) ? context->seek(context, offset, whence) : -1;
}

Sint64 SDLCALL DOSBoxMac_RWtell(SDL_RWops *context)
{
    return DOSBoxMac_RWseek(context, 0, RW_SEEK_CUR);
}

size_t SDLCALL DOSBoxMac_RWread(SDL_RWops *context, void *ptr, size_t size, size_t maxnum)
{
    return (context && context->read) ? context->read(context, ptr, size, maxnum) : 0;
}

size_t SDLCALL DOSBoxMac_RWwrite(SDL_RWops *context, const void *ptr, size_t size, size_t num)
{
    return (context && context->write) ? context->write(context, ptr, size, num) : 0;
}

int SDLCALL DOSBoxMac_RWclose(SDL_RWops *context)
{
    return (context && context->close) ? context->close(context) : -1;
}

SDL_threadID SDLCALL DOSBoxMac_ThreadID(void)
{
    uint64_t tid = 0;
    pthread_threadid_np(nullptr, &tid);
    return static_cast<SDL_threadID>(tid);
}

char *SDLCALL DOSBoxMac_getenv(const char *name)
{
    return std::getenv(name);
}

int SDLCALL DOSBoxMac_setenv(const char *name, const char *value, int overwrite)
{
    return ::setenv(name, value, overwrite);
}

} // extern "C"
