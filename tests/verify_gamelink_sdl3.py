#!/usr/bin/env python3
"""Compile-test GameLink's SDL2/SDL3 keyboard adapter without SDL runtime.

The two isolated fixtures model the published keyboard-event structures.
They do not claim that DOSBox-X's full SDL3 renderer/event loop is ported.
"""

from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "src/output/gamelink_sdl_keyboard.h"
OUTPUT = (ROOT / "src/output/output_gamelink.cpp").read_text(encoding="utf-8")
SCANCODES = (ROOT / "src/gamelink/scancodes_windows.h").read_text(encoding="utf-8")
CONFIGURE = (ROOT / "configure.ac").read_text(encoding="utf-8")
GAMELINK_CPP = (ROOT / "src/gamelink/gamelink.cpp").read_text(encoding="utf-8")
AUTOMAKE = (ROOT / "src/output/Makefile.am").read_text(encoding="utf-8")

def require(condition, reason):
    if not condition:
        raise AssertionError(reason)

cxx = shutil.which("c++") or shutil.which("g++") or shutil.which("clang++")
require(cxx is not None, "C++14 compiler required for keyboard adapter check")
require(HEADER.is_file(), "missing keyboard adapter header")
require('gamelink_sdl_keyboard.h' in AUTOMAKE,
        "Automake source distribution must contain the keyboard adapter")
require('GameLink_MakeKeyboardEvent(scancode, is_pressed)' in OUTPUT,
        "GameLink must route keyboard state transitions through the versioned adapter")
require('was_pressed != is_pressed' in OUTPUT,
        "GameLink must dispatch only keyboard state transitions")
require('#if defined(C_SDL3)' in SCANCODES
        and '#include <SDL3/SDL_scancode.h>' in SCANCODES,
        "Windows scancode table must support the SDL3 header layout")
require('"SDL_syswm.h"' not in GAMELINK_CPP,
        "Shared-memory transport must not directly depend on SDL2 SysWM headers")
require('x$SDL_STRING" = xSDL2' in CONFIGURE
        and "GameLink needs SDL2 output today" in CONFIGURE,
        "Partial SDL3 support must not enable an unported renderer")
require('#error "GameLink SDL3 window/output integration is not implemented"' in OUTPUT,
        "SDL3 output must remain blocked until window ownership is ported")

def source_for(sdl3):
    if sdl3:
        definitions = r"""
#define C_SDL3 1
typedef int SDL_Scancode;
typedef int SDL_Keycode;
typedef unsigned int SDL_EventType;
enum { SDL_EVENT_KEY_DOWN = 0x300, SDL_EVENT_KEY_UP = 0x301, SDLK_UNKNOWN = 0, SDL_KMOD_NONE = 0 };
struct SDL_KeyboardEvent {
    SDL_EventType type;
    SDL_Scancode scancode;
    SDL_Keycode key;
    unsigned short mod;
    bool down;
    bool repeat;
};
union SDL_Event { unsigned int type; SDL_KeyboardEvent key; };
"""
        checks = r"""
    if (pressed.type != SDL_EVENT_KEY_DOWN || pressed.key.type != SDL_EVENT_KEY_DOWN ||
        !pressed.key.down || pressed.key.scancode != 42 ||
        pressed.key.key != SDLK_UNKNOWN || pressed.key.mod != SDL_KMOD_NONE ||
        pressed.key.repeat) return 1;
    if (released.type != SDL_EVENT_KEY_UP || released.key.down ||
        released.key.scancode != 42) return 2;
"""
    else:
        definitions = r"""
#define C_SDL2 1
typedef int SDL_Scancode;
enum { SDL_KEYDOWN = 0x300, SDL_KEYUP = 0x301, SDL_PRESSED = 1, SDL_RELEASED = 0, SDLK_UNKNOWN = 0, KMOD_NONE = 0 };
struct SDL_Keysym { SDL_Scancode scancode; int sym; int mod; };
struct SDL_KeyboardEvent {
    unsigned int type;
    unsigned char state;
    unsigned char repeat;
    SDL_Keysym keysym;
};
union SDL_Event { unsigned int type; SDL_KeyboardEvent key; };
"""
        checks = r"""
    if (pressed.type != SDL_KEYDOWN || pressed.key.type != SDL_KEYDOWN ||
        pressed.key.state != SDL_PRESSED || pressed.key.keysym.scancode != 42 ||
        pressed.key.keysym.mod != KMOD_NONE || pressed.key.keysym.sym != SDLK_UNKNOWN ||
        pressed.key.repeat) return 1;
    if (released.type != SDL_KEYUP || released.key.state != SDL_RELEASED ||
        released.key.keysym.scancode != 42) return 2;
"""
    return definitions + '\n#include "src/output/gamelink_sdl_keyboard.h"\n' + r"""
int main()
{
    const SDL_Event pressed = GameLink_MakeKeyboardEvent(42, true);
    const SDL_Event released = GameLink_MakeKeyboardEvent(42, false);
""" + checks + "    return 0;\n}\n"

with tempfile.TemporaryDirectory(prefix="dosbox-gamelink-abi-") as directory:
    executable = Path(directory) / "event-check"
    for mode in (False, True):
        compiled = subprocess.run(
            [cxx, "-std=c++14", "-Wall", "-Wextra", "-Werror",
             "-I", str(ROOT), "-x", "c++", "-",
             "-o", str(executable)],
            input=source_for(mode), text=True, capture_output=True, check=False
        )
        require(compiled.returncode == 0,
                ("SDL3" if mode else "SDL2") + " event adapter compile failed: " + compiled.stderr)
        result = subprocess.run([str(executable)], capture_output=True, check=False)
        require(result.returncode == 0,
                ("SDL3" if mode else "SDL2") + " event adapter behavior failed")

print("GameLink SDL2/SDL3 keyboard-event adapter: ok (full SDL3 output not enabled)")
