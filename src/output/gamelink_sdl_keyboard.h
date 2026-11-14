#ifndef DOSBOX_OUTPUT_GAMELINK_SDL_KEYBOARD_H
#define DOSBOX_OUTPUT_GAMELINK_SDL_KEYBOARD_H

// The protocol sends Windows scancodes. Translate them to a native SDL
// keyboard event at the output boundary; do not expose either SDL ABI to
// the GameLink shared-memory protocol.
#if defined(C_SDL2) && defined(C_SDL3)
#error "GameLink cannot compile with both SDL2 and SDL3 event layouts"
#endif

static inline SDL_Event GameLink_MakeKeyboardEvent(SDL_Scancode scancode, bool pressed)
{
    SDL_Event event = {};
#if defined(C_SDL3)
    // SDL3 removes keysym and state: key.scancode/key.down live directly
    // in SDL_KeyboardEvent, and event types use SDL_EVENT_KEY_*.
    event.key.type = pressed ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
    event.key.scancode = scancode;
    event.key.key = SDLK_UNKNOWN;
    event.key.mod = SDL_KMOD_NONE;
    event.key.down = pressed;
    event.key.repeat = false;
#elif defined(C_SDL2)
    event.key.type = pressed ? SDL_KEYDOWN : SDL_KEYUP;
    event.key.keysym.scancode = scancode;
    event.key.keysym.sym = SDLK_UNKNOWN;
    event.key.keysym.mod = KMOD_NONE;
    event.key.state = pressed ? SDL_PRESSED : SDL_RELEASED;
    event.key.repeat = 0;
#else
#error "GameLink keyboard events require an SDL2 or SDL3 host"
#endif
    return event;
}

#endif // DOSBOX_OUTPUT_GAMELINK_SDL_KEYBOARD_H
