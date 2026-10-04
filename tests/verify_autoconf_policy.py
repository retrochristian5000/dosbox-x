#!/usr/bin/env python3
"""Static guard for modern, portable configure.ac conventions."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIGURE = (ROOT / "configure.ac").read_text(encoding="utf-8")


def require(needle, label):
    if needle not in CONFIGURE:
        raise AssertionError(f"{label}: missing {needle!r}")


def forbid(needle, label):
    if needle in CONFIGURE:
        raise AssertionError(f"{label}: found retired construct {needle!r}")


for needle, label in {
    "AC_CONFIG_HEADER(": "use AC_CONFIG_HEADERS",
    "AC_HELP_STRING(": "use AS_HELP_STRING",
    "\nAC_C_CONST\n": "C11 makes the legacy const probe unnecessary",
    "\nAC_STRUCT_TM\n": "modern time.h provides struct tm",
    "if [[": "generated configure must remain portable /bin/sh",
    "${LIBS//": "Bash-only parameter replacement is not portable",
    "disable_sdl_net": "use positive enable_sdlnet option state",
}.items():
    forbid(needle, label)

for needle, label in {
    "AC_CONFIG_HEADERS([config.h])": "modern config header declaration",
    "[enable_force_menu_sdldraw=$enableval]": "force-menu option must respect --disable",
    "[enable_hx=$enableval]": "HX option must respect --disable",
    "[enable_opencow=$enableval]": "OpenCOW option must respect --disable",
    "[enable_sdlnet=$enableval]": "SDL_net option must respect --disable",
    "[enable_sdl3=$enableval]": "SDL3 option must respect --disable",
}.items():
    require(needle, label)

if CONFIGURE.count("AC_CHECK_LIB(GL, main") != 1:
    raise AssertionError("OpenGL library probe must have exactly one source of truth")
if CONFIGURE.count("AC_CHECK_HEADER(d3d9.h") != 1:
    raise AssertionError("Direct3D 9 header probe must have exactly one source of truth")

print("Autoconf policy: ok")
