#!/usr/bin/env python3
"""Source-level guard for direct SDL3 lifecycle migration (not a full SDL3 build)."""

from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "src/gui/sdlmain.cpp").read_text(encoding="utf-8")


def require(fragment, description):
    if fragment not in SOURCE:
        raise AssertionError(f"{description}: missing {fragment!r}")


for fragment, description in (
    ('#elif defined(C_SDL3)\n    LOG(LOG_GUI,LOG_DEBUG)("This version uses the SDL3 API directly")',
     "SDL3 startup identity"),
    ('const int sdl3_version = SDL_GetVersion();', "SDL3 GUI version getter"),
    ('const bool sdl_initialized = SDL_Init(SDL_INIT_AUDIO | SDL_INIT_VIDEO);',
     "SDL3 boolean initialization without removed flags"),
    ('const int sdl_version = SDL_GetVersion();', "SDL3 runtime version getter"),
    ('SDL_VERSIONNUM_MAJOR(sdl_version)', "SDL3 major version"),
    ('SDL_VERSIONNUM_MINOR(sdl_version)', "SDL3 minor version"),
    ('SDL_VERSIONNUM_MICRO(sdl_version)', "SDL3 micro version"),
    ('const bool joystick_initialized = SDL_InitSubSystem(SDL_INIT_JOYSTICK);',
     "SDL3 boolean joystick initialization"),
    ('SDL_JoystickID *joysticks = SDL_GetJoysticks(&joystick_count);',
     "SDL3 joystick enumeration by ID"),
    ('SDL_free(joysticks);', "SDL3 joystick-list cleanup"),
    ('#endif /* SDL3 has no SDL CD-ROM subsystem. */',
     "removed SDL3 CD-ROM initialization guarded"),
    ('LOG_MSG("Host: native macOS (SDL-free)")', "native macOS runtime identity"),
):
    require(fragment, description)

# Never regress into the old SDL2-style comparisons in the SDL3-specific paths.
for forbidden in (
    'SDL_Init(SDL_INIT_AUDIO | SDL_INIT_VIDEO) >= 0',
    'SDL_GetVersion(&sdl3_version)',
    'SDL_GetJoysticks()',
):
    if forbidden in SOURCE:
        raise AssertionError(f"retired SDL3 call convention: {forbidden}")

print("SDL3 lifecycle API policy: ok (source level only)")
