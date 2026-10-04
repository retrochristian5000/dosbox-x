#!/usr/bin/env python3
"""Guard the SDL-free native macOS host boundary.

This is a static policy check that runs on any host. The macOS build itself
adds a second guard with otool(1) and nm(1) after linking.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def require(text, needle, label):
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


build = read("build-macos")
legacy = read("build-macos-sdl2")
sdk_resolver = read("scripts/resolve-macos-sdk.bash")
llvm_bootstrap = read("scripts/bootstrap-native-llvm.bash")
configure = read("configure.ac")
makefile = read("src/Makefile.am")
gui_makefile = read("src/gui/Makefile.am")
output_makefile = read("src/output/Makefile.am")
compat = read("src/platform/macos/native_macos_compat.h")
native = read("src/platform/macos/native_macos.mm")
menu = read("src/gui/menu_macos.mm")
metal = read("src/output/output_metal.mm")
metal_header = read("src/output/output_metal.h")
sdlmain_header = read("include/sdlmain.h")
mapper_header = read("include/mapper.h")
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
require(build, 'orig_OBJCXXFLAGS="${OBJCXXFLAGS}"',
        "macOS build must preserve caller Objective-C++ flags")
require(build, 'SDKROOT="$(bash "$top/scripts/resolve-macos-sdk.bash")"',
        "macOS build must resolve the active SDK")
require(build, '"${CC:-cc}" ${CPPFLAGS} ${CFLAGS} -x c -fsyntax-only -',
        "macOS build must probe system headers through the selected compiler and effective flags")
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

for arc_source, label in ((native, "native_macos.mm"), (metal, "output_metal.mm")):
    if " release]" in arc_source or " autorelease]" in arc_source:
        raise AssertionError(f"ARC source contains manual Objective-C ownership: {label}")

if "using namespace std;" in metal_header:
    raise AssertionError("Objective-C++ Metal header leaks the std namespace")
for unused_header in ("<sys/types.h>", "<assert.h>", "<math.h>"):
    if unused_header in metal_header:
        raise AssertionError(f"Metal Objective-C++ header carries unused system dependency: {unused_header}")
for required_header in ("<cstdint>", "<vector>"):
    if required_header not in metal_header:
        raise AssertionError(f"Metal Objective-C++ header misses direct C++ dependency: {required_header}")

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
