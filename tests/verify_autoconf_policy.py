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
    "AS_IF([test \"x$ac_check_cflags_result\" != xyes]": "C11 failure must use compiler-probe result",
    "AS_IF([test \"x$ac_check_cxxflags_result\" != xyes]": "C++14 failure must use compiler-probe result",
    "AC_CONFIG_HEADERS([config.h])": "modern config header declaration",
    "[enable_force_menu_sdldraw=$enableval]": "force-menu option must respect --disable",
    "[enable_hx=$enableval]": "HX option must respect --disable",
    "[enable_opencow=$enableval]": "OpenCOW option must respect --disable",
    "[enable_sdlnet=$enableval]": "SDL_net option must respect --disable",
    "[enable_sdl3=$enableval]": "SDL3 option must respect --disable",
}.items():
    require(needle, label)

# Library probes must not run before the configured C and C++ compilers are
# available; a function named "main" cannot certify that a library works.
probes = (
    "AC_CHECK_LIB([GL], [glGetString]",
    "AC_CHECK_LIB([opengl32], [wglCreateContext]",
    "AC_CHECK_HEADER([GL/gl.h]",
    "AC_CHECK_HEADER([d3d9.h]",
    "AC_CHECK_HEADER([d3dx9math.h]",
    "AC_CHECK_LIB([X11], [XOpenDisplay]",
    "AC_CHECK_LIB([Xrandr], [XRRGetCrtcInfo]",
)
for probe in probes:
    if CONFIGURE.count(probe) != 1:
        raise AssertionError(f"expected exactly one working graphics probe: {probe}")
if min(CONFIGURE.index(probe) for probe in probes[:5]) < CONFIGURE.index("AC_PROG_CXX"):
    raise AssertionError("graphics probes initialize host compilers too early")
if "AC_CHECK_LIB(rt, main" in CONFIGURE or "AC_CHECK_LIB([rt], [main]" in CONFIGURE:
    raise AssertionError("stale librt placeholder check returned")
if "AC_C_INLINE" in CONFIGURE or "STDC_HEADERS" in CONFIGURE:
    raise AssertionError("C11 builds must not depend on obsolete inline/header probes")
if "[-lX11])" not in CONFIGURE:
    raise AssertionError("Xrandr link probe must supply its X11 dependency")

# Both d3d11.h and dxgi.h are necessary; a callback that resets success
# on the final header can wrongly enable Direct3D when an earlier one fails.
for probe in (
    "have_d3d11_h=yes",
    "AC_CHECK_HEADERS([d3d11.h dxgi.h], [], [have_d3d11_h=no])",
):
    if probe not in CONFIGURE:
        raise AssertionError(f"Direct3D 11 header aggregation missing: {probe}")

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

for dead in ("AC_CHECK_CPPFLAGS", "cat > conftest.c", "cat > conftest.c++"):
    if dead in CONFIGURE:
        raise AssertionError(f"configure.ac still carries hand-written compiler probe code: {dead}")

for required in (
    "AC_LANG_PUSH([C])",
    "AC_LANG_PUSH([C++])",
    "AC_COMPILE_IFELSE(",
    "ac_check_cflags_result=yes",
    "ac_check_cxxflags_result=yes",
):
    if required not in CONFIGURE:
        raise AssertionError(f"Autoconf-native compiler flag probe is missing: {required}")

# Keep SDL feature options in configure.ac, not duplicated in acinclude.m4.
# A duplicate default used to silently disable SDL2 detection.
require("AC_PREREQ([2.69])", "minimum supported Autoconf version")
for flag in ("sdl2", "sdl3"):
    require(f"AC_ARG_ENABLE([{flag}]", f"configure owns the {flag} option")
    if f"AC_ARG_ENABLE({flag}," in ACINCLUDE or f"AC_ARG_ENABLE([{flag}]" in ACINCLUDE:
        raise AssertionError(f"duplicate {flag} option default in acinclude.m4")
for old in ("enable_sdl2enable", "enable_sdl3enable", "sdl2conf_args",
            "AC_PATH_PROG([SDL3_CONFIG]", "ifelse("):
    if old in ACINCLUDE:
        raise AssertionError(f"retired SDL/ALSA Autoconf construct: {old}")
for required in (
    'test "x$enable_sdl2" = xyes',
    'test "x$enable_sdl3" = xyes',
    "AC_PATH_PROG([SDL2_CONFIG], [sdl2-config], [no])",
    "AS_HELP_STRING([--with-alsa-prefix=PFX]",
    "m4_if([$1], [], [0.1.1], [$1])",
):
    if required not in ACINCLUDE:
        raise AssertionError(f"missing updated Autoconf macro: {required}")

require("macOS SDL2 builds are retired; use --enable-native-macos", "reject standalone macOS SDL2 configuration")
require('case "$host" in', "macOS host selection guard")

require("Direct SDL3 API support is not implemented", "reject incomplete native SDL3 build")
if 'SDL_STRING="SDL3"' in CONFIGURE:
    raise AssertionError("SDL3 must not advertise an unimplemented direct API backend")
for explicit in ('test -z "$SDL2_CONFIG"', 'test -z "$sdl2_exec_prefix"',
                 'test -z "$sdl2_prefix"'):
    if explicit not in ACINCLUDE:
        raise AssertionError(f"pinned SDL2 discovery overrides explicit selection: {explicit}")

require("AC_PATH_PROGS([PKG_CONFIG], [pkgconf pkg-config], [no])",
        "pkgconf/pkg-config host tool discovery")
require("dosbox_pkgconf_exists()",
        "shared pkg-config feature check helper")
if "pkg-config --exists" in CONFIGURE or "pkg-config --exists" in ACINCLUDE:
    raise AssertionError("bare pkg-config calls bypass selected PKG_CONFIG")

# Reject genuinely obsolete macro calls in both primary M4 inputs. Look at
# call sites rather than comments or strings documenting old constructs.
import re

for source_name, source in (("configure.ac", CONFIGURE), ("acinclude.m4", ACINCLUDE)):
    for deprecated in (
        "AC_TRY_COMPILE", "AC_TRY_LINK", "AC_TRY_RUN", "AC_TRY_CPP",
        "AC_CONFIG_HEADER", "AC_HELP_STRING", "AC_HEADER_STDC",
        "AC_HEADER_TIME", "AC_PROG_CC_STDC", "AC_PROG_CC_C89",
        "AC_PROG_CC_C99", "AC_LANG_SAVE", "AC_LANG_RESTORE",
    ):
        if re.search(r"(?m)^\s*" + deprecated + r"\s*(?:\(|$)", source):
            raise AssertionError(f"{source_name} uses obsolete Autoconf call {deprecated}")

# The iconv link probe must call iconv_open, not merely declare an unused
# function whose unresolved symbol could be discarded by the linker.
if 'iconv_t cd = iconv_open("UTF-8", "UTF-8");' not in CONFIGURE:
    raise AssertionError("iconv link test does not force symbol resolution")

print("Autoconf policy: ok")
