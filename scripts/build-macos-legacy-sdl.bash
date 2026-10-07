#!/usr/bin/env bash

# Legacy SDL runtime dependencies for the explicit build-macos-sdl2 backend.
# This file is sourced by build-macos only when DOSBOX_MACOS_BACKEND=sdl2.
# Native AppKit/CoreAudio/IOKit builds must never source it.

chmod +x "$top/vs/sdl2/build-dosbox.sh"

sdl_key="$(dependency_key sdl2)"
if dependency_is_fresh "$top/vs/sdl2/linux-host" "$sdl_key" \
    "$top/vs/sdl2" "$top/vs/sdl2/build-dosbox.sh"; then
    echo "Reusing cached SDL 2.x for ${arch}"
else
    echo "Compiling the legacy in-tree SDL 2.x backend"
    (cd "$top/vs/sdl2" && ./build-dosbox.sh) || return 1
    mark_dependency "$top/vs/sdl2/linux-host" "$sdl_key"
fi
CPPFLAGS="${CPPFLAGS} -I${top}/vs/sdl2/linux-host/include "
LDFLAGS="${LDFLAGS} -L${top}/vs/sdl2/linux-host/lib "

sdlnet_key="$(dependency_key sdl2net)"
if dependency_is_fresh "$top/vs/sdl2net/linux-host" "$sdlnet_key" \
    "$top/vs/sdl2net" "$top/vs/sdl2net/build-dosbox.sh"; then
    echo "Reusing cached SDL2_net for ${arch}"
else
    echo "Compiling the legacy in-tree SDL2_net backend"
    chmod +x "$top"/vs/sdl2net/*.sh
    (cd "$top/vs/sdl2net" && ./build-dosbox.sh) || return 1
    mark_dependency "$top/vs/sdl2net/linux-host" "$sdlnet_key"
fi
CPPFLAGS="${CPPFLAGS} -I${top}/vs/sdl2net/linux-host/include "
LDFLAGS="${LDFLAGS} -L${top}/vs/sdl2net/linux-host/lib "
