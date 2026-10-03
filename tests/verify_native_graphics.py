#!/usr/bin/env python3
"""Compile the production output policy without an SDL or macOS SDK.

This checks selection, mode negotiation, and pixel layout, not GPU presentation.
Run with Python 3 and CXX set to a C++14 compiler (defaults to c++).
"""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def function(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


POLICY = "\n".join([
    function("src/output/output_tools.cpp", "std::string GetDefaultOutput()"),
    function("src/output/output_ttf.cpp", "void SetOutputSwitch("),
    function("src/output/output_metal.mm", "Bitu OUTPUT_Metal_GetBestMode("),
    function("src/output/output_metal.mm", "Bitu OUTPUT_Metal_SetSize("),
    function("src/gui/sdlmain.cpp", "Bitu GFX_GetBestMode("),
    function("src/gui/sdlmain.cpp", "Bitu GFX_GetRGB("),
    function("src/gui/sdlmain.cpp", "unsigned int GFX_GetBShift("),
    function("src/gui/sdlmain.cpp", "void GFX_LogSDLState("),
])

HARNESS = r'''
#include <cassert>
#include <cstdint>
#include <cstring>
#include <string>
#include <strings.h>
#define LOG_MSG(...) ((void)0)
#define LOG(...) LogSink{}
#define SDL_LIL_ENDIAN 1234
#define SDL_BYTEORDER SDL_LIL_ENDIAN
using Bitu = uint32_t;
enum { GFX_CAN_8 = 1, GFX_CAN_15 = 2, GFX_CAN_16 = 4,
       GFX_CAN_32 = 8, GFX_SCALING = 16, GFX_HARDWARE = 32 };
enum { SCREEN_SURFACE, SCREEN_OPENGL, SCREEN_TTF, SCREEN_DIRECT3D,
       SCREEN_DIRECT3D11, SCREEN_GAMELINK, SCREEN_METAL };
enum { SDL_WINDOW_FULLSCREEN_DESKTOP = 1 };
struct LogSink { template<class... Args> void operator()(Args...) {} };
struct PixelFormat {
    unsigned int Bshift = 8, Rshift = 16, Gshift = 0, Ashift = 24;
    unsigned int Rmask = 0xff0000, Gmask = 0xff, Bmask = 0xff00, Amask = 0xff000000;
    unsigned int BitsPerPixel = 32;
};
struct Surface { PixelFormat* format; int w = 640, h = 400; };
PixelFormat format;
Surface surface{&format};
struct State {
    struct Desktop {
        int type = SCREEN_SURFACE, want_type = SCREEN_SURFACE;
        bool fullscreen = false;
    } desktop;
    struct Clip { int x = 0, y = 0, w = 640, h = 400; } clip;
    struct Draw { unsigned int width = 640, height = 400; } draw;
    void* window = nullptr;
    Surface* surface = &::surface;
} sdl;
bool isVirtualBox = false;
int switchoutput = -1;
int surface_selections = 0;
uint32_t GFX_Rmask, GFX_Gmask, GFX_Bmask, GFX_Amask;
unsigned char GFX_Rshift, GFX_Gshift, GFX_Bshift, GFX_Ashift, GFX_bpp;
void OUTPUT_SURFACE_Select() {
    sdl.desktop.want_type = SCREEN_SURFACE;
    ++surface_selections;
}
Bitu OUTPUT_SURFACE_GetBestMode(Bitu flags) { return flags; }
Bitu OUTPUT_OPENGL_GetBestMode(Bitu flags) { return flags; }
Bitu OUTPUT_DIRECT3D_GetBestMode(Bitu flags) { return flags; }
Bitu SDL_MapRGB(PixelFormat*, uint8_t, uint8_t, uint8_t) { return 0x12345678; }
void SDL_GetWindowSize(void*, int* w, int* h) { *w = 640; *h = 400; }
void SDL_SetWindowFullscreen(void*, int) {}
// The initialization boundary is the GPU; the SetSize control flow is production code.
struct CMetal {
    bool was_fullscreen = false;
    int window_width = 0, window_height = 0;
    bool Resize(unsigned int, unsigned int, unsigned int w, unsigned int h) {
        return w == sdl.draw.width && h == sdl.draw.height;
    }
} test_metal;
CMetal* metal = nullptr;
bool fail_initialization = false;
int initialization_count = 0;
void metal_init() {
    ++initialization_count;
    if (fail_initialization) OUTPUT_SURFACE_Select();
    else metal = &test_metal;
}
'''

CHECKS = r'''
int main() {
    assert(GetDefaultOutput() == EXPECTED_OUTPUT);
    SetOutputSwitch("surface");
    assert(switchoutput == 0);
#if C_OPENGL
    SetOutputSwitch("opengl");
    assert(switchoutput == 3);
    SetOutputSwitch("openglnb");
    assert(switchoutput == 4);
    SetOutputSwitch("openglpp");
    assert(switchoutput == 5);
#endif
    SetOutputSwitch("auto");
    assert(switchoutput == EXPECTED_TTF_AUTO);
#if defined(MACOSX) && defined(C_SDL2) && C_METAL
    SetOutputSwitch("metal");
    assert(switchoutput == 14);
    sdl.desktop.want_type = SCREEN_METAL;
    const Bitu input = GFX_CAN_8 | GFX_CAN_15 | GFX_CAN_16 | 64;
    const Bitu mode = GFX_GetBestMode(input);
    assert(mode & GFX_CAN_32);
    assert(mode & GFX_SCALING);
    assert(mode & 64);
    assert(!(mode & (GFX_CAN_8 | GFX_CAN_15 | GFX_CAN_16)));
    assert(sdl.desktop.want_type == SCREEN_METAL);
    assert(surface_selections == 0);
    assert(OUTPUT_Metal_SetSize() & GFX_CAN_32);
    assert(initialization_count == 1);
    assert(OUTPUT_Metal_SetSize() & GFX_CAN_32);
    assert(initialization_count == 1); // Reuse the initialized renderer.
    metal = nullptr;
    fail_initialization = true;
    assert(OUTPUT_Metal_SetSize() == 0);
    assert(sdl.desktop.want_type == SCREEN_SURFACE);
    sdl.desktop.type = SCREEN_METAL;
    sdl.surface = nullptr; // Native framebuffer metadata must not depend on SDL.
    assert(GFX_GetRGB(0xff, 0, 0) == 0xffff0000);
    assert(GFX_GetRGB(0, 0xff, 0) == 0xff00ff00);
    assert(GFX_GetRGB(0, 0, 0xff) == 0xff0000ff);
    assert(GFX_GetRGB(0, 0, 0) == 0xff000000);
    assert(GFX_GetRGB(0xff, 0xff, 0xff) == 0xffffffff);
    assert(GFX_GetBShift() == 0);
    GFX_LogSDLState();
    assert(GFX_bpp == 32);
    assert(GFX_Rmask == 0x00ff0000 && GFX_Rshift == 16);
    assert(GFX_Gmask == 0x0000ff00 && GFX_Gshift == 8);
    assert(GFX_Bmask == 0x000000ff && GFX_Bshift == 0);
    assert(GFX_Amask == 0xff000000 && GFX_Ashift == 24);
#endif
    sdl.desktop.type = SCREEN_SURFACE;
    sdl.surface = &surface;
    assert(GFX_GetRGB(1, 2, 3) == 0x12345678);
    assert(GFX_GetBShift() == 8);
    GFX_LogSDLState();
    assert(GFX_Bshift == 8 && GFX_Bmask == format.Bmask);
}
'''

# Expected behavior comes from the platform/output contract, not the selector.
CASES = [
    ("macOS Metal", {"MACOSX": 1, "C_SDL2": 1, "C_METAL": 1, "C_OPENGL": 1}, "metal", 14),
    ("Apple silicon Metal", {"MACOSX": 1, "__arm64__": 1, "C_SDL2": 1, "C_METAL": 1, "C_OPENGL": 1}, "metal", 14),
    ("macOS Metal without OpenGL", {"MACOSX": 1, "C_SDL2": 1, "C_METAL": 1}, "metal", 14),
    ("macOS without Metal", {"MACOSX": 1, "C_SDL2": 1, "C_OPENGL": 1}, "opengl", 3),
    ("macOS software only", {"MACOSX": 1, "C_SDL2": 1}, "surface", -1),
    ("legacy macOS", {"MACOSX": 1, "C_METAL": 1, "C_OPENGL": 1}, "opengl", 3),
    ("Linux SDL2", {"LINUX": 1, "C_SDL2": 1, "C_OPENGL": 1}, "opengl", 3),
    ("Linux software only", {"LINUX": 1, "C_SDL2": 1}, "surface", -1),
    ("Windows Direct3D", {"WIN32": 1, "C_SDL2": 1, "C_DIRECT3D": 1, "C_OPENGL": 1}, "direct3d", 6),
    ("Windows OpenGL", {"WIN32": 1, "C_SDL2": 1, "C_OPENGL": 1}, "opengl", 3),
    ("Windows software only", {"WIN32": 1, "C_SDL2": 1}, "surface", -1),
]


def main():
    failures = []
    with tempfile.TemporaryDirectory(prefix="dosbox-native-graphics-") as directory:
        source = Path(directory) / "policy.cpp"
        binary = Path(directory) / "policy"
        source.write_text(HARNESS + POLICY + CHECKS)
        for name, features, output, ttf_auto in CASES:
            defines = dict(C_METAL=0, C_OPENGL=0, C_DIRECT3D=0, C_GAMELINK=0,
                           USE_TTF=1, EXPECTED_OUTPUT='"' + output + '"',
                           EXPECTED_TTF_AUTO=ttf_auto)
            defines.update(features)
            command = shlex.split(os.environ.get("CXX", "c++"))
            command += ["-std=c++14", "-Wall", "-Wextra", "-Werror"]
            command += ["-D" + key + "=" + str(value) for key, value in defines.items()]
            command += [str(source), "-o", str(binary)]
            subprocess.run(command, check=True)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            print(("FAIL " if result.returncode else "PASS ") + name)
            if result.returncode:
                failures.append(name)
                print(result.stderr.strip())
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
