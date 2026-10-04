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
compat = read("src/platform/macos/native_macos_compat.h")
native = read("src/platform/macos/native_macos.mm")

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
require(build, '"${CC:-cc}" ${arch_flags} -x c -fsyntax-only -',
        "macOS build must probe system headers through the selected compiler")
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
