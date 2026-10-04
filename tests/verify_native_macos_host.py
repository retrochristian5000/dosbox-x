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
messages_cpp = read("src/misc/messages.cpp")
clipboard_cpp = read("src/misc/clipboard.cpp")
menu_cpp = read("src/gui/menu.cpp")
sdl_gui = read("src/gui/sdl_gui.cpp")
sdlmain_cpp = read("src/gui/sdlmain.cpp")

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
    "SDL_GetWindowWMInfo",
    "SDL_OpenAudioDevice",
    "SDL_NumJoysticks",
    "SDL_CreateMutex",
    "SDL_CreateSemaphore",
    "SDL_CreateThread",
    "SDL_RWFromFile",
):
    require(compat, f"#define {api}", f"native ABI remap for {api}")

for framework_marker in (
    "#import <AppKit/AppKit.h>",
    "#import <AudioUnit/AudioUnit.h>",
    "#import <IOKit/hid/IOHIDLib.h>",
):
    require(native, framework_marker, "native framework implementation")

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
