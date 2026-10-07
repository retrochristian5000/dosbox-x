#!/usr/bin/env python3
"""Guard the SDL-free native macOS host boundary.

This is a static policy check that runs on any host. The macOS build itself
adds a second guard with otool(1) and nm(1) after linking.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def require(text, needle, label):
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


def native_macos_view(text):
    """Keep branches that survive when the native macOS backend is active."""
    lines = text.splitlines()
    output = []
    i = 0
    native_marker = "#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS"
    legacy_marker = "#if defined(C_SDL2) && !(defined(C_NATIVE_MACOS) && C_NATIVE_MACOS)"
    while i < len(lines):
        stripped = lines[i].strip()
        if stripped not in (native_marker, legacy_marker):
            output.append(lines[i])
            i += 1
            continue

        depth = 1
        native_lines = []
        active = stripped == native_marker
        i += 1
        while i < len(lines) and depth:
            stripped = lines[i].strip()
            if stripped.startswith("#if") or stripped.startswith("#ifdef") or stripped.startswith("#ifndef"):
                depth += 1
                if active:
                    native_lines.append(lines[i])
            elif stripped.startswith("#endif"):
                depth -= 1
                if depth and active:
                    native_lines.append(lines[i])
            elif stripped.startswith("#elif") and depth == 1:
                active = False
            elif stripped.startswith("#else") and depth == 1:
                active = not active
            elif active:
                native_lines.append(lines[i])
            i += 1

        if depth:
            raise AssertionError("unterminated native macOS preprocessor branch")
        output.extend(native_lines)

    return "\n".join(output)


build = read("build-macos")
driver = read("build")
legacy = read("build-macos-sdl2")
legacy_sdl_deps = read("scripts/build-macos-legacy-sdl.bash")
acinclude = read("acinclude.m4")
sdk_resolver = read("scripts/resolve-macos-sdk.bash")
llvm_bootstrap = read("scripts/bootstrap-native-llvm.bash")
configure = read("configure.ac")
root_makefile = read("Makefile.am")
makefile = read("src/Makefile.am")
gui_makefile = read("src/gui/Makefile.am")
output_makefile = read("src/output/Makefile.am")
output_tools_header = read("src/output/output_tools.h")
compat = read("src/platform/macos/native_macos_compat.h")
native = read("src/platform/macos/native_macos.mm")
menu = read("src/gui/menu_macos.mm")
metal = read("src/output/output_metal.mm")
metal_header = read("src/output/output_metal.h")
sdlmain_header = read("include/sdlmain.h")
mapper_header = read("include/mapper.h")
codepage_header = read("include/codepage.h")
macosx_host_header = read("include/macosx_host.h")
native_macos_abi = read("include/native_macos_sdl_abi.h")
include_makefile = read("include/Makefile.am")
messages_cpp = read("src/misc/messages.cpp")
clipboard_cpp = read("src/misc/clipboard.cpp")
menu_cpp = read("src/gui/menu.cpp")
sdl_gui = read("src/gui/sdl_gui.cpp")
sdlmain_cpp = read("src/gui/sdlmain.cpp")
midi_cpp = read("src/gui/midi.cpp")
sdl_mapper = read("src/gui/sdl_mapper.cpp")
sdl_ttf = read("src/gui/sdl_ttf.c")
savestates_cpp = read("src/misc/savestates.cpp")
support_cpp = read("src/misc/support.cpp")

require(build, 'macos_backend="${DOSBOX_MACOS_BACKEND:-native}"',
        "build-macos must default to native")
require(build, 'if [ "${macos_backend}" = "sdl2" ]; then',
        "SDL construction must be isolated behind the legacy backend")
require(build, 'source "$top/scripts/build-macos-legacy-sdl.bash" || exit 1',
        "legacy SDL construction must live outside the native build body")
require(legacy_sdl_deps, "Compiling the legacy in-tree SDL 2.x backend",
        "isolated legacy SDL2 dependency build")
require(legacy_sdl_deps, "Compiling the legacy in-tree SDL2_net backend",
        "isolated legacy SDL2_net dependency build")
for forbidden_inline_sdl_build in (
    '(cd vs/sdl2 && ./build-dosbox.sh)',
    '(cd vs/sdl2net && ./build-dosbox.sh)',
):
    if forbidden_inline_sdl_build in build:
        raise AssertionError(
            f"build-macos still contains inline SDL construction: {forbidden_inline_sdl_build}"
        )
require(build, "--enable-native-macos --disable-opengl",
        "native configure flags")
if "--enable-native-macos --disable-sdl2" in build:
    raise AssertionError("native build invocation still carries an SDL2 configure switch")
require(build, "Native macOS build refuses explicit SDL runtime link flags",
        "native build must reject caller-supplied SDL runtime link flags")
require(build, "unset SDL_CONFIG SDL2_CONFIG SDL2_CFLAGS SDL2_LIBS",
        "native build must clear inherited SDL discovery state")
require(build, "otool -L src/dosbox-x", "native dylib dependency guard")
require(build, "nm -u src/dosbox-x", "native unresolved-symbol guard")
require(build, 'orig_OBJCXXFLAGS="${OBJCXXFLAGS:-}"',
        "macOS build must preserve caller Objective-C++ flags")
require(build, 'SDKROOT="$(bash "$top/scripts/resolve-macos-sdk.bash")"',
        "macOS build must resolve the active SDK")
require(build, '"${CC:-cc}" ${CPPFLAGS} ${CFLAGS} -x c -fsyntax-only -',
        "macOS build must probe system headers through the selected compiler and effective flags")
require(build, 'clean_build="${DOSBOX_CLEAN_BUILD:-0}"',
        "macOS incremental build must keep an explicit clean escape hatch")
require(build, "dependency_is_fresh()", "macOS dependency cache validator")
require(build, "macos-active-config.key", "macOS active configure fingerprint")
require(build, "package_config_digest()", "configure cache must notice package feature changes")
require(build, "Reusing DOSBox-X configure state", "macOS configure-state reuse")
require(build, "Incrementally compiling DOSBox-X", "macOS incremental compile path")
require(driver, "--clean", "top-level clean-build control")
require(driver, "--reconfigure", "top-level reconfigure control")
require(driver, "export DOSBOX_CLEAN_BUILD=1", "top-level clean-build forwarding")
require(driver, "export DOSBOX_RECONFIGURE=1", "top-level reconfigure forwarding")
require(build, 'cmp -s src/dosbox-x "${arch_binary}"',
        "unchanged architecture binaries must preserve timestamps")
require(root_makefile, "MACOS_APP_RESOURCES =", "incremental macOS app resource set")
require(root_makefile, "dosbox-x.app: dosbox-x.app/.stamp", "incremental macOS app target")
require(root_makefile, "touch dosbox-x.app/.stamp", "macOS app bundle completion stamp")
require(sdk_resolver, 'xcrun --sdk macosx --show-sdk-path',
        "macOS SDK resolver must use the active Xcode SDK")
require(sdk_resolver, '$sdk/usr/include/sys/types.h',
        "macOS SDK resolver must validate sys/types.h")
require(llvm_bootstrap, 'export SDKROOT',
        "standalone LLVM must inherit the macOS SDK")
require(llvm_bootstrap, '"-DCMAKE_OSX_SYSROOT=$SDKROOT"',
        "LLVM bootstrap must use the same macOS SDK")
require(build, 'OBJCXXFLAGS="${arch_flags}${orig_OBJCXXFLAGS}"',
        "macOS target flags must reach Objective-C++ sources")
for polluted in ('CFLAGS="${CFLAGS}${new}"', 'CXXFLAGS="${CXXFLAGS}${new}"'):
    if polluted in build:
        raise AssertionError(f"macOS include search paths leaked into language flags: {polluted}")
require(legacy, "DOSBOX_MACOS_BACKEND=sdl2", "legacy SDL2 wrapper")

require(configure, "--enable-native-macos", "configure switch")
require(configure, """if test x"$enable_native_macos" = xyes; then
  enable_sdl2=no
  enable_sdlnet=no
fi""",
        "native configure mode must disable SDL runtime networking itself")
require(configure, 'SDL2_CONFIG=no', "native configure SDL2 discovery reset")
require(configure, 'SDL2_CFLAGS=""', "native configure SDL2 compile flags reset")
require(configure, 'SDL2_LIBS=""', "native configure SDL2 link flags reset")
require(configure, 'SDL3_CONFIG=no', "native configure SDL3 discovery reset")
require(configure, 'SDL3_CFLAGS=""', "native configure SDL3 compile flags reset")
require(configure, 'SDL3_LIBS=""', "native configure SDL3 link flags reset")
require(acinclude,
        "if test x$enable_native_macos != xyes && test x$enable_sdl2enable = xyes ; then",
        "SDL2 discovery must be vetoed by native macOS mode")
require(acinclude,
        "if test x$enable_native_macos != xyes && test x$enable_sdl3enable = xyes ; then",
        "SDL3 discovery must be vetoed by native macOS mode")
require(configure, "AC_DEFINE([C_NATIVE_MACOS]", "native config define")
require(configure, "AM_CONDITIONAL([NATIVE_MACOS]", "native automake conditional")
require(configure, 'SDL_STRING="NativeMacOS"', "native SDL-network isolation")
require(makefile, "platform/macos/native_macos.mm", "native Objective-C++ source")
require(makefile, "-fobjc-arc", "native Objective-C++ ARC")
require(gui_makefile, "-fno-objc-arc", "menu Objective-C++ manual-reference-counting mode")
require(output_makefile, "-fobjc-arc", "Metal Objective-C++ ARC mode")
require(native, 'error "native_macos.mm requires ARC"', "native ARC compile guard")
require(native, "struct SDL_Window;",
        "native AppKit classes must use the SDL_Window C++ forward declaration")
require(native, "@interface DOSBoxMacSurfaceView : NSView",
        "complete native surface-view declaration")
require(native, "@interface DOSBoxMacWindowDelegate : NSObject <NSWindowDelegate>",
        "complete native window-delegate declaration")
if "@class DOSBoxMacSurfaceView;" in native or "@class DOSBoxMacWindowDelegate;" in native:
    raise AssertionError(
        "native_macos.mm still relies on Objective-C class forward declarations "
        "for SDL_Window-owned AppKit objects"
    )
if native.index("@interface DOSBoxMacSurfaceView : NSView") > native.index("struct SDL_Window {"):
    raise AssertionError("DOSBoxMacSurfaceView must be complete before SDL_Window stores it")
if native.index("@interface DOSBoxMacWindowDelegate : NSObject <NSWindowDelegate>") > native.index("struct SDL_Window {"):
    raise AssertionError("DOSBoxMacWindowDelegate must be complete before SDL_Window stores it")
if native.count("@interface DOSBoxMacSurfaceView : NSView") != 1:
    raise AssertionError("DOSBoxMacSurfaceView interface must have one canonical declaration")
if native.count("@interface DOSBoxMacWindowDelegate : NSObject <NSWindowDelegate>") != 1:
    raise AssertionError("DOSBoxMacWindowDelegate interface must have one canonical declaration")
require(native, "SDL_Window *owner = self.owner;",
        "surface view must snapshot its non-owning SDL_Window owner")
require(native, "NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];",
        "surface view must acquire the AppKit graphics context explicitly")
require(native, "CGContextRef target = graphicsContext ? [graphicsContext CGContext] : nullptr;",
        "surface view must guard the Core Graphics target")
require(native, """if (!target) {
        CGImageRelease(image);
        return;
    }""",
        "surface view must release its image if no draw context exists")
require(native, "window->view.owner = nullptr;",
        "window teardown must clear the surface view's non-owning owner")
require(metal, 'error "output_metal.mm requires ARC"', "Metal ARC compile guard")
require(metal, '#include "output_tools.h"',
        "Metal implementation must import shared output aspect declarations")
require(output_tools_header, "extern int aspect_ratio_x, aspect_ratio_y;",
        "shared output aspect-ratio declaration")
if "extern int aspect_ratio_x, aspect_ratio_y;" in metal:
    raise AssertionError("Metal implementation must not redeclare shared aspect-ratio state")
require(menu, 'error "menu_macos.mm uses manual reference counting', "menu MRC compile guard")
require(menu, "CFRelease(source);", "IME copied input source release")
require(menu, "CFRelease(sources);", "IME created input-source list release")
require(menu, "return [item autorelease];", "Touch Bar delegate MRC return ownership")
require(menu, "static DOSBoxXTouchBarDelegate *touchBarDelegate = nil;",
        "Touch Bar weak delegate must have explicit process lifetime")
if "touchBar.delegate = [DOSBoxXTouchBarDelegate alloc];" in menu:
    raise AssertionError("Touch Bar weak delegate depends on a leaked allocation")
require(menu, "NSWindow *wnd = macosx_active_window();",
        "Touch Bar must target the active AppKit window")
require(menu, "[wnd setTouchBar:touchBar];",
        "SDL2-shaped macOS builds must install Touch Bar through AppKit")
require(menu, "[touchBar release];",
        "manual-reference-counted direct Touch Bar install must balance ownership")
require(menu, "[super touchesCancelledWithEvent:event];", "Touch Bar cancellation superclass dispatch")
require(menu, "[alert release];", "manual NSAlert ownership cleanup")
require(menu, "NSControlStateValueOn", "current AppKit menu on-state constant")
require(menu, "NSControlStateValueOff", "current AppKit menu off-state constant")
if "NSOnState" in menu or "NSOffState" in menu:
    raise AssertionError("menu_macos.mm still uses legacy AppKit control state constants")
require(menu, "bool macosx_clipboard_get(std::string &result)",
        "AppKit clipboard read implementation")
require(menu, "bool macosx_clipboard_set(const std::string &value)",
        "AppKit clipboard write implementation")
require(menu, "[NSPasteboard generalPasteboard]",
        "macOS clipboard must use NSPasteboard")

for forbidden in ("CFBridgingRelease", "__bridge", "[panel release]"):
    if forbidden in menu:
        raise AssertionError(f"manual-reference-counted menu code contains ARC/over-release pattern: {forbidden}")

for declaration, owner in (
    ("SDL_Window* GFX_GetSDLWindow(void);", sdlmain_header),
    ("void NewInstanceEvent(bool pressed);", sdlmain_header),
    ("void GUI_Run(bool pressed);", sdlmain_header),
    ("bool GUI_IsRunning(void);", sdlmain_header),
    ("extern bool is_paused;", sdlmain_header),
    ("extern bool unpause_now;", sdlmain_header),
    ("bool MAPPER_IsRunning(void);", mapper_header),
    ("void MapperCapCursorToggle(void);", mapper_header),
    ("void ext_signal_host_key(bool enable);", mapper_header),
):
    if declaration not in owner:
        raise AssertionError(f"shared forward declaration is missing from its header: {declaration}")

for body_decl in (
    "SDL_Window* GFX_GetSDLWindow(void);",
    "void NewInstanceEvent(bool pressed);",
    "extern void MAPPER_Run(bool pressed);",
    "extern void MapperCapCursorToggle(void);",
    "extern void GUI_Run(bool pressed);",
    "extern bool unpause_now;",
    "extern void PauseDOSBox(bool pressed);",
):
    if body_decl in menu:
        raise AssertionError(f"menu_macos.mm still carries ad-hoc forward declaration: {body_decl}")

if "SDL_Window* GFX_GetSDLWindow(void);" in sdl_gui:
    raise AssertionError("sdl_gui.cpp still redeclares GFX_GetSDLWindow inside function bodies")
if "extern bool is_paused;" in menu_cpp:
    raise AssertionError("menu.cpp still redeclares shared pause state")
if "extern void GUI_Run(bool pressed);" in sdlmain_cpp:
    raise AssertionError("sdlmain.cpp still redeclares GUI_Run instead of using sdlmain.h")
if "static int my_quartz_match_window_to_monitor" not in menu:
    raise AssertionError("private Quartz helper should have internal linkage")

for declaration in (
    "bool InitCodePage(void);",
    "bool CodePageHostToGuestUTF8(char *dst, const char *src);",
    "bool CodePageGuestToHostUTF8(char *dst, const char *src);",
    "bool CodePageHostToGuestUTF16(char *dst, const uint16_t *src);",
    "bool CodePageGuestToHostUTF16(uint16_t *dst, const char *src);",
):
    if declaration not in codepage_header:
        raise AssertionError(f"codepage API declaration is missing: {declaration}")

for source, label in (
    (menu, "menu_macos.mm"),
    (sdlmain_cpp, "sdlmain.cpp"),
    (messages_cpp, "messages.cpp"),
    (clipboard_cpp, "clipboard.cpp"),
):
    for pattern in (
        r"(?m)^\\s*(?:extern\\s+)?bool\\s+InitCodePage\\s*\\([^)]*\\)\\s*;",
        r"(?m)^\\s*(?:extern\\s+)?bool\\s+CodePageGuestToHostUTF8\\s*\\([^)]*\\)\\s*;",
    ):
        if re.search(pattern, source):
            raise AssertionError(
                f"{label} still carries ad-hoc codepage forward declaration: {pattern}"
            )

for declaration in (
    "bool macosx_detect_nstouchbar(void);",
    "void macosx_init_touchbar(void);",
    "void macosx_reload_touchbar(void);",
    "void macosx_GetWindowDPI(ScreenSizeInfo &info);",
    "bool macosx_clipboard_get(std::string &text);",
    "bool macosx_clipboard_set(const std::string &text);",
    "void macosx_native_shutdown(void);",
    "void sdl_hax_macosx_setmenu(void *nsMenu);",
    "void menu_macosx_set_menuobj(DOSBoxMenu *new_altMenu);",
):
    if declaration not in macosx_host_header:
        raise AssertionError(f"macOS host declaration is missing from macosx_host.h: {declaration}")

for stale, source, label in (
    ("extern bool has_touch_bar_support;", sdlmain_cpp, "sdlmain.cpp"),
    ("void macosx_reload_touchbar(void);", sdl_gui, "sdl_gui.cpp"),
    ("void GetClipboard(std::string* result);", clipboard_cpp, "clipboard.cpp"),
    ("bool SetClipboard(std::string value);", clipboard_cpp, "clipboard.cpp"),
    ("void sdl_hax_nsMenuAddApplicationMenu(void *nsMenu);", menu_cpp, "menu.cpp"),
    ("void sdl_hax_macosx_setmenu(void *nsMenu);", menu_cpp, "menu.cpp"),
):
    if stale in source:
        raise AssertionError(f"{label} still hand-declares macOS host API: {stale}")

if "#import" in macosx_host_header or "NSWindow" in macosx_host_header:
    raise AssertionError("macosx_host.h must remain C++-safe and AppKit-opaque")

for arc_source, label in ((native, "native_macos.mm"), (metal, "output_metal.mm")):
    if " release]" in arc_source or " autorelease]" in arc_source:
        raise AssertionError(f"ARC source contains manual Objective-C ownership: {label}")

require(metal, "bool CMetal::Initialize(NSView *nsview, int w, int h)",
        "Metal private API should use typed Objective-C++ view pointers")
require(metal, "NSView *view = (__bridge NSView *)macosx_content_view();",
        "ARC host boundary must use an explicit non-owning bridge")
if "NSView *view = (NSView *)macosx_content_view();" in metal:
    raise AssertionError("Metal host boundary uses an ARC-invalid plain C pointer cast")
if "Initialize((__bridge void*)view" in metal or "Initialize((__bridge void *)view" in metal:
    raise AssertionError("Metal private API unnecessarily round-trips NSView through void *")

if "using namespace std;" in metal_header:
    raise AssertionError("Metal public header leaks the std namespace")
for implementation_token in ("#import", "@class", "@protocol", "id<", "NSView", "CAMetalLayer", "class CMetal"):
    if implementation_token in metal_header:
        raise AssertionError(
            f"Metal public header leaks Objective-C++ implementation detail: {implementation_token}"
        )
if "<cstdint>" not in metal_header:
    raise AssertionError("Metal public header misses fixed-width integer declarations")
if "class CMetal" not in metal:
    raise AssertionError("Metal implementation no longer owns its private CMetal class")
require(sdlmain_cpp, "#include <output/output_metal.h>",
        "sdlmain must consume the Metal public header")
require(sdl_gui, "#include <output/output_metal.h>",
        "GUI must consume the Metal public header")
for stale in (
    "void metal_init();",
    "void OUTPUT_Metal_Select();",
    "void OUTPUT_Metal_Shutdown();",
):
    if stale in sdlmain_cpp:
        raise AssertionError(f"sdlmain.cpp still hand-declares Metal API: {stale}")
if "void OUTPUT_Metal_Shutdown();" in sdl_gui:
    raise AssertionError("sdl_gui.cpp still hand-declares the Metal shutdown API")

for api in (
    "SDL_Init",
    "SDL_CreateWindow",
    "SDL_OpenAudioDevice",
    "SDL_NumJoysticks",
    "SDL_CreateMutex",
    "SDL_CreateSemaphore",
    "SDL_CreateThread",
    "SDL_RWFromFile",
):
    require(compat, f"#define {api}", f"native ABI remap for {api}")

require(native_macos_abi, "#define DOSBOX_NATIVE_MACOS_SDL_ABI 1",
        "native macOS ABI quarantine marker")
require(compat, '#include "native_macos_sdl_abi.h"',
        "native compatibility layer must load the quarantined ABI")
require(include_makefile, "native_macos_sdl_abi.h",
        "native ABI quarantine header must ship in source distributions")
require(sdlmain_header, "#if !defined(DOSBOX_NATIVE_MACOS_SDL_ABI)",
        "sdlmain must skip the SDL umbrella under the native ABI quarantine")
require(native, '#include "config.h"',
        "native host implementation must load generated platform configuration")
require(native, '#include "native_macos_compat.h"',
        "native host implementation must import remapped DOSBoxMac declarations")
require(native, '#include "macosx_host.h"',
        "native host implementation must import native host declarations")
if native.index('#include "config.h"') > native.index('#include "macosx_host.h"'):
    raise AssertionError(
        "native_macos.mm must load config.h before macosx_host.h so "
        "MACOSX/C_NATIVE_MACOS declarations are visible"
    )
require(macosx_host_header, "void macosx_native_shutdown(void);",
        "native shutdown declaration must live in macosx_host.h")
if '#include "native_macos_sdl_abi.h"' in native:
    raise AssertionError(
        "native_macos.mm bypasses the compatibility declaration layer and can "
        "leave DOSBoxMac_* cross-calls undeclared"
    )

for declaration_remap in (
    "#define SDL_InitSubSystem               DOSBoxMac_InitSubSystem",
    "#define SDL_FreeSurface                 DOSBoxMac_FreeSurface",
    "#define SDL_CloseAudioDevice            DOSBoxMac_CloseAudioDevice",
    "#define SDL_DestroyWindow               DOSBoxMac_DestroyWindow",
    "#define SDL_GetWindowSize               DOSBoxMac_GetWindowSize",
):
    require(compat, declaration_remap,
            f"native implementation declaration remap for {declaration_remap}")
native_umbrella_guard = """#if !defined(DOSBOX_NATIVE_MACOS_SDL_ABI)
#include "SDL.h"
#endif"""
for source_name, source in (
    ("menu.cpp", menu_cpp),
    ("midi.cpp", midi_cpp),
    ("sdl_gui.cpp", sdl_gui),
    ("sdl_mapper.cpp", sdl_mapper),
    ("sdl_ttf.c", sdl_ttf),
    ("savestates.cpp", savestates_cpp),
    ("support.cpp", support_cpp),
):
    require(source, native_umbrella_guard,
            f"{source_name} must respect the native macOS SDL umbrella quarantine")

require(support_cpp, '#include "macosx_host.h"',
        "support fatal-exit path must consume the native macOS host API")
require(support_cpp, """#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS
    macosx_native_shutdown();
#else
	SDL_Quit();
#endif""",
        "native fatal exit must bypass SDL_Quit")
native_support = native_macos_view(support_cpp)
if re.search(r"\bSDL_Quit\s*\(", native_support):
    raise AssertionError("support.cpp native macOS fatal-exit path still calls SDL_Quit")

if '#include "SDL_syswm.h"' in menu_cpp:
    raise AssertionError("menu.cpp still carries an unused SDL SysWM dependency")
require(sdl_gui, """#if defined(_WIN32) && !defined(HX_DOS)
#include "SDL_syswm.h"
#endif""",
        "sdl_gui SysWM must stay Windows-only")
require(sdl_mapper, """#if defined(_WIN32) && !defined(HX_DOS)
#include "SDL_syswm.h"
#endif""",
        "sdl_mapper top-level SysWM must stay Windows-only")
for forbidden_umbrella in ('#include "SDL.h"', '#include <SDL.h>',
                           '#include "SDL_syswm.h"', '#include <SDL_syswm.h>'):
    if forbidden_umbrella in native_macos_abi:
        raise AssertionError(
            f"native ABI quarantine imports forbidden SDL umbrella: {forbidden_umbrella}"
        )
if '#include "SDL.h"' in native or '#include <SDL.h>' in native:
    raise AssertionError("native_macos.mm still imports the SDL umbrella directly")

for framework_marker in (
    "#import <AppKit/AppKit.h>",
    "#import <AudioUnit/AudioUnit.h>",
    "#import <IOKit/hid/IOHIDLib.h>",
):
    require(native, framework_marker, "native framework implementation")

for native_display_marker in (
    "initWithContentRect:rect",
    "screen:screen",
    "frameRectForContentRect:content",
    "CGDisplayBounds(display_id)",
    "CGDisplayModeGetWidth(cgmode)",
    "DOSBoxMac_GetWindowDisplayIndex",
    "windowDidChangeBackingProperties:",
    "windowDidChangeScreen:",
    "windowWillEnterFullScreen:",
    "windowDidFailToEnterFullScreen:",
    "windowDidFailToExitFullScreen:",
):
    require(native, native_display_marker,
            f"native AppKit/CoreGraphics display integration for {native_display_marker}")

require(compat, "#define SDL_GetWindowDisplayIndex",
        "native display-index ABI remap")
require(metal, "convertRectToBacking:metalView.bounds",
        "Metal drawable size must come from AppKit backing conversion")
require(metal, "#include <algorithm>",
        "Metal geometry must declare std::max dependency")
require(metal, "#include <cmath>",
        "Metal geometry must declare std::round dependency")
require(metal, "layer.framebufferOnly = YES;",
        "Metal drawable should use framebuffer-only optimization")
require(macosx_host_header, "void *macosx_content_view(void);",
        "opaque macOS content-view accessor declaration")
require(macosx_host_header, "void *macosx_native_window(void);",
        "native AppKit window accessor declaration")
for declaration in (
    "bool macosx_native_get_window_size(int &width, int &height);",
    "bool macosx_native_set_window_size(int width, int height);",
    "bool macosx_native_set_fullscreen(bool fullscreen);",
):
    require(macosx_host_header, declaration,
            f"native AppKit window-control declaration for {declaration}")
require(native, "void *macosx_native_window(void)",
        "native AppKit window accessor implementation")
require(native, "bool macosx_native_get_window_size(int &width, int &height)",
        "native AppKit window-size query implementation")
require(native, "bool macosx_native_set_window_size(const int width, const int height)",
        "native AppKit window-size setter implementation")
require(native, "bool macosx_native_set_fullscreen(const bool fullscreen)",
        "native AppKit fullscreen implementation")
require(native, "void macosx_native_shutdown(void)",
        "native host shutdown implementation")
require(native, """void macosx_native_shutdown(void)
{
    DOSBoxMac_CloseAudioDevice(1);
    shutdown_appkit_events();
    shutdown_iokit_hid();""",
        "native shutdown must tear down AppKit events and IOKit directly")
if "DOSBoxMac_QuitSubSystem(SDL_INIT_JOYSTICK)" in native:
    raise AssertionError(
        "native shutdown still routes through SDL_INIT_JOYSTICK compatibility"
    )
require(native, "void activate_application()",
        "AppKit activation compatibility helper")
require(native, "bool initialize_appkit_application()",
        "native AppKit application initializer")
require(native, "bool initialize_iokit_hid()",
        "native IOKit HID initializer")
require(native, "void shutdown_iokit_hid()",
        "native IOKit HID shutdown")
require(native, "IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone)",
        "native IOKit HID manager construction")
require(native, "const IOReturn result = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);",
        "native IOKit HID manager open result")
require(native, "if (result != kIOReturnSuccess)",
        "native IOKit HID open failure handling")
require(native, "IOHIDManagerClose(hid_manager, kIOHIDOptionsTypeNone);",
        "native IOKit HID manager shutdown")
require(native, "NSApplication *application = [NSApplication sharedApplication];",
        "native AppKit application construction")
require(native, "if (!appkit_initialized)",
        "AppKit finishLaunching must be idempotent")
require(native, "[application finishLaunching];",
        "native AppKit launch completion")
require(native, """if (!initialize_appkit_events())
            return nullptr;""",
        "native window creation must initialize the AppKit event loop directly")
if "SDL_INIT_VIDEO" in native:
    raise AssertionError(
        "native_macos.mm must not gate AppKit video setup on SDL_INIT_VIDEO"
    )
for declaration in (
    "extern int SDLCALL DOSBoxMac_Init(Uint32 flags);",
    "extern int SDLCALL DOSBoxMac_InitSubSystem(Uint32 flags);",
    "extern void SDLCALL DOSBoxMac_QuitSubSystem(Uint32 flags);",
    "extern void SDLCALL DOSBoxMac_Quit(void);",
):
    require(compat, declaration,
            f"explicit native core compatibility declaration for {declaration}")

require(native, """int SDLCALL DOSBoxMac_Init(Uint32)
{
    /*
     * Native macOS host services initialize lazily through AppKit, CoreAudio,
     * and IOKit operations. SDL init entry points remain only as compatibility
     * ABI symbols for long-lived host-facing code.
     */
    return 0;
}

int SDLCALL DOSBoxMac_InitSubSystem(Uint32)
{
    return 0;
}""",
        "native core compatibility init entry points must remain independent no-ops")
if "return DOSBoxMac_InitSubSystem(" in native:
    raise AssertionError(
        "DOSBoxMac_Init must not depend on a later DOSBoxMac_InitSubSystem definition"
    )

require(native, "bool initialize_appkit_events()",
        "native AppKit event-loop initializer")
require(native, "void shutdown_appkit_events()",
        "native AppKit event-loop shutdown")
require(native, "[NSApp nextEventMatchingMask:NSEventMaskAny",
        "native AppKit event retrieval")
require(native, "[NSApp sendEvent:event];",
        "native AppKit event dispatch")
require(native, "[NSApp updateWindows];",
        "native AppKit window event servicing")
require(native, """if (!initialize_appkit_events())
        return;""",
        "native event pump must ensure AppKit event initialization")
require(native, """int SDLCALL DOSBoxMac_PollEvent(SDL_Event *event)
{
    @autoreleasepool {
        pump_appkit_once(false);
    }""",
        "SDL event compatibility polling must dispatch directly to AppKit")
if "DOSBoxMac_PumpEvents();\n    return pop_event(event)" in native:
    raise AssertionError(
        "native PollEvent still bounces through the SDL-shaped pump wrapper"
    )

if "SDL_INIT_EVENTS" in native:
    raise AssertionError(
        "native_macos.mm must not gate AppKit event delivery on SDL_INIT_EVENTS"
    )
if "DOSBoxMac_InitSubSystem(SDL_INIT_EVENTS)" in native:
    raise AssertionError(
        "native event implementation still routes through SDL_INIT_EVENTS compatibility"
    )
require(native, "AppKit event delivery is a native host service initialized lazily",
        "native event subsystem must document its AppKit-owned lifecycle")

if "SDL_INIT_JOYSTICK" in native:
    raise AssertionError(
        "native_macos.mm must not gate IOKit HID on SDL_INIT_JOYSTICK"
    )
require(native, "bool hid_devices_initialized = false;",
        "native IOKit HID inventory initialization state")
require(native, "bool ensure_hid_devices()",
        "native IOKit HID lazy inventory helper")
require(native, "return hid_devices_initialized || refresh_hid_devices();",
        "native IOKit HID lazy inventory dispatch")
require(native, """SDL_Joystick *SDLCALL DOSBoxMac_JoystickOpen(int device_index)
{
    if (!ensure_hid_devices())
        return nullptr;""",
        "joystick open must lazily initialize native IOKit HID")
require(native, """const char *SDLCALL DOSBoxMac_JoystickNameForIndex(int device_index)
{
    if (!ensure_hid_devices())
        return nullptr;""",
        "joystick name lookup must lazily initialize native IOKit HID")
require(native, "hid_devices_initialized = false;",
        "native IOKit HID shutdown must invalidate inventory state")
require(native, "IOKit HID are native host",
        "native joystick subsystem must document its IOKit-owned lifecycle")
require(native, "if (@available(macOS 14.0, *))",
        "new AppKit activation API availability guard")
require(native, "[NSApp activate];",
        "macOS 14+ cooperative AppKit activation")
require(native, '# pragma clang diagnostic ignored "-Wdeprecated-declarations"',
        "pre-macOS 14 activation fallback warning isolation")
require(native, """void SDLCALL DOSBoxMac_Quit(void)
{
    macosx_native_shutdown();
}""", "SDL compatibility quit must delegate to native host shutdown")
require(menu, "return (NSWindow *)macosx_native_window();",
        "native menu/DPI path must consume the AppKit window directly")
require(menu, "void *macosx_content_view(void)",
        "shared opaque macOS content-view implementation")
require(metal, "macosx_content_view()",
        "Metal must consume the host-owned AppKit content view")
for marker in (
    "macosx_native_get_window_size(width, height)",
    "macosx_native_set_window_size(width, height)",
    "macosx_native_set_fullscreen(fullscreen)",
):
    require(metal, marker, f"native Metal AppKit window control for {marker}")

for source_name, source in (
    ("output_metal.mm", metal),
    ("menu_macos.mm", menu),
):
    native_source = native_macos_view(source)
    stray_calls = sorted(set(re.findall(r"\b(SDL_[A-Za-z0-9_]+)\s*\(", native_source)))
    if stray_calls:
        raise AssertionError(
            f"{source_name} native macOS branch still calls SDL APIs: "
            + ", ".join(stray_calls)
        )

for source_name, source in (
    ("native_macos.mm", native),
    ("output_metal.mm", metal),
):
    for stale_syswm in (
        "SDL_syswm.h",
        "SDL_SysWMinfo",
        "SDL_GetWindowWMInfo",
        "SDL_SYSWM_COCOA",
    ):
        if stale_syswm in source:
            raise AssertionError(
                f"{source_name} still depends on SDL SysWM token {stale_syswm}"
            )
if "#define SDL_GetWindowWMInfo" in compat:
    raise AssertionError("native compatibility layer still remaps SDL_GetWindowWMInfo")

for forbidden_clipboard_remap in (
    "#define SDL_GetClipboardText",
    "#define SDL_SetClipboardText",
):
    if forbidden_clipboard_remap in compat:
        raise AssertionError(
            f"native compatibility layer must not remap clipboard through SDL: "
            f"{forbidden_clipboard_remap}"
        )

require(clipboard_cpp, '#include "macosx_host.h"',
        "clipboard code must consume the macOS host API")
require(clipboard_cpp, """#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS
    if (!macosx_clipboard_get(text))
        return;
#elif defined(C_SDL2)
    char *sdl_text = SDL_GetClipboardText();""",
        "native clipboard reads must take AppKit before the SDL2 compatibility branch")
require(clipboard_cpp, """#if defined(C_NATIVE_MACOS) && C_NATIVE_MACOS
    macosx_clipboard_set(result);
#elif defined(C_SDL2)
    SDL_SetClipboardText(result.c_str());""",
        "native clipboard writes must take AppKit before the SDL2 compatibility branch")
require(sdlmain_cpp, "SDL_WINDOWEVENT_DISPLAY_CHANGED",
        "macOS display changes must refresh output geometry")
require(sdlmain_cpp, "static int GFX_GetActiveDisplayIndex()",
        "SDL2 display sizing must follow the active window display")
require(sdlmain_cpp, "SDL_GetWindowDisplayIndex(sdl.window)",
        "active display lookup must use the current window")
require(menu, "#if defined(C_SDL2) && !(defined(C_NATIVE_MACOS) && C_NATIVE_MACOS)",
        "SDL headers in menu_macos must be legacy-backend-only")
require(menu, "SDL_Window *window = GFX_GetSDLWindow();",
        "SDL Cocoa bridge must validate the active SDL window")
require(menu, "SDL_GetWindowWMInfo(window, &wminfo) == SDL_TRUE",
        "SDL Cocoa bridge must require an explicit successful SysWM query")
if "SDL_GetWindowWMInfo(GFX_GetSDLWindow(), &wminfo) >= 0" in menu:
    raise AssertionError("SDL Cocoa bridge still treats SDL_FALSE as success")
require(menu, 'NSScreen *screen = [wnd screen];',
        "macOS DPI helper must use AppKit's authoritative window screen")
require(menu, 'CGDisplayModeGetPixelWidth(mode)',
        "macOS DPI must use backing-pixel width")
require(menu, 'CGDisplayModeGetPixelHeight(mode)',
        "macOS DPI must use backing-pixel height")
require(native, "- (void)windowDidFailToEnterFullScreen:(NSWindow *)window",
        "NSWindowDelegate enter-fullscreen failure signature")
require(native, "- (void)windowDidFailToExitFullScreen:(NSWindow *)window",
        "NSWindowDelegate exit-fullscreen failure signature")
if "- (void)windowDidFailToEnterFullScreen:(NSNotification *)" in native:
    raise AssertionError("delegate enter-fullscreen failure callback uses notification signature")
if "- (void)windowDidFailToExitFullScreen:(NSNotification *)" in native:
    raise AssertionError("delegate exit-fullscreen failure callback uses notification signature")
if "FIXME display index" in sdlmain_cpp:
    raise AssertionError("stale primary-display fallback remains in SDL2 display sizing")

for entry in (
    "DOSBoxMac_CreateWindow",
    "DOSBoxMac_OpenAudioDevice",
    "DOSBoxMac_NumJoysticks",
    "DOSBoxMac_CreateMutex",
    "DOSBoxMac_CreateSemaphore",
    "DOSBoxMac_CreateThread",
    "DOSBoxMac_RWFromFile",
):
    require(native, entry, f"native implementation for {entry}")

for forbidden in ("-lSDL", "-lSDL2", "-lSDL2_net"):
    if forbidden in native:
        raise AssertionError(f"native host source links SDL directly: {forbidden}")

print("native macOS host policy: ok")
