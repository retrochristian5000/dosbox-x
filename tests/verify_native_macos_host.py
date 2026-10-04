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


build = read("build-macos")
driver = read("build")
legacy = read("build-macos-sdl2")
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
require(build, "--enable-native-macos --disable-sdl2 --disable-sdlnet --disable-opengl",
        "native configure flags")
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
require(configure, "AC_DEFINE([C_NATIVE_MACOS]", "native config define")
require(configure, "AM_CONDITIONAL([NATIVE_MACOS]", "native automake conditional")
require(configure, 'SDL_STRING="NativeMacOS"', "native SDL-network isolation")
require(makefile, "platform/macos/native_macos.mm", "native Objective-C++ source")
require(makefile, "-fobjc-arc", "native Objective-C++ ARC")
require(gui_makefile, "-fno-objc-arc", "menu Objective-C++ manual-reference-counting mode")
require(output_makefile, "-fobjc-arc", "Metal Objective-C++ ARC mode")
require(native, 'error "native_macos.mm requires ARC"', "native ARC compile guard")
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
require(menu, "[super touchesCancelledWithEvent:event];", "Touch Bar cancellation superclass dispatch")
require(menu, "[alert release];", "manual NSAlert ownership cleanup")

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
    "void sdl_hax_macosx_setmenu(void *nsMenu);",
    "void menu_macosx_set_menuobj(DOSBoxMenu *new_altMenu);",
):
    if declaration not in macosx_host_header:
        raise AssertionError(f"macOS host declaration is missing from macosx_host.h: {declaration}")

for stale, source, label in (
    ("extern bool has_touch_bar_support;", sdlmain_cpp, "sdlmain.cpp"),
    ("void macosx_reload_touchbar(void);", sdl_gui, "sdl_gui.cpp"),
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
require(native, '#include "native_macos_sdl_abi.h"',
        "native host must consume the project-owned ABI quarantine")
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
require(native, "void *macosx_native_window(void)",
        "native AppKit window accessor implementation")
require(menu, "return (NSWindow *)macosx_native_window();",
        "native menu/DPI path must consume the AppKit window directly")
require(menu, "void *macosx_content_view(void)",
        "shared opaque macOS content-view implementation")
require(metal, "macosx_content_view()",
        "Metal must consume the host-owned AppKit content view")
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
require(sdlmain_cpp, "SDL_WINDOWEVENT_DISPLAY_CHANGED",
        "macOS display changes must refresh output geometry")
require(sdlmain_cpp, "static int GFX_GetActiveDisplayIndex()",
        "SDL2 display sizing must follow the active window display")
require(sdlmain_cpp, "SDL_GetWindowDisplayIndex(sdl.window)",
        "active display lookup must use the current window")
require(menu, "#if defined(C_SDL2) && !(defined(C_NATIVE_MACOS) && C_NATIVE_MACOS)",
        "SDL headers in menu_macos must be legacy-backend-only")
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
