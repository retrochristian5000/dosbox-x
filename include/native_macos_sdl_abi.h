#pragma once

/*
 * Transitional SDL-shaped ABI for the native macOS host.
 *
 * Native macOS runtime services are implemented with AppKit, CoreAudio,
 * IOKit, pthreads, and libc. Long-lived DOSBox-X code still exchanges a
 * subset of SDL2 data structures at compile time, so keep that surface
 * explicit here instead of importing the all-of-SDL SDL.h umbrella.
 *
 * This is an ABI quarantine, not a runtime dependency. The native build does
 * not link SDL2. Shrink this list as project-owned host types replace the
 * remaining SDL-shaped structures.
 */

#define DOSBOX_NATIVE_MACOS_SDL_ABI 1

#include "SDL_audio.h"
#include "SDL_endian.h"
#include "SDL_events.h"
#include "SDL_hints.h"
#include "SDL_mutex.h"
#include "SDL_render.h"
#include "SDL_rwops.h"
#include "SDL_surface.h"
#include "SDL_thread.h"
#include "SDL_timer.h"
#include "SDL_version.h"
#include "SDL_video.h"
