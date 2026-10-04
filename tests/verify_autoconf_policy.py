#!/usr/bin/env python3
"""Static guard for modern, portable configure.ac conventions."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIGURE = (ROOT / "configure.ac").read_text(encoding="utf-8")
ACINCLUDE = (ROOT / "acinclude.m4").read_text(encoding="utf-8")


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
    "c11_supported=yes": "C11 probe must keep M4 errors outside custom flag callbacks",
    "AS_IF([test \"x$c11_supported\" != xyes]": "C11 failure must be handled by Autoconf",
    "cxx14_supported=yes": "C++14 probe must keep M4 errors outside custom flag callbacks",
    "AS_IF([test \"x$cxx14_supported\" != xyes]": "C++14 failure must be handled by Autoconf",
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

for bad in (
    "AC_CHECK_CFLAGS([-std=gnu11], [],\n      [AC_MSG_ERROR",
    "AC_CHECK_CXXFLAGS([-std=gnu++14], [],\n      [AC_MSG_ERROR",
):
    if bad in CONFIGURE:
        raise AssertionError("M4 macro callback is overquoted inside custom compiler flag probe")

for obsolete in ("AC_TRY_COMPILE", "AC_LANG_SAVE", "AC_LANG_C", "AC_LANG_RESTORE"):
    if obsolete in ACINCLUDE:
        raise AssertionError(f"acinclude.m4 still uses obsolete Autoconf construct: {obsolete}")

for required in ("AC_LANG_PUSH([C])", "AC_COMPILE_IFELSE(", "AC_LANG_POP([C])"):
    if required not in ACINCLUDE:
        raise AssertionError(f"modern ALSA compile probe is missing: {required}")

print("Autoconf policy: ok")
