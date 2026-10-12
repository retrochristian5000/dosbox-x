dnl SDL3 is discovered through pkg-config; it has no sdl3-config executable.
dnl configure.ac owns the --enable-sdl3 option and its default.
AC_DEFUN([AM_PATH_SDL3], [
  AH_TEMPLATE([C_SDL3], [Define to 1 to enable SDL 3.x support])
  SDL3_CFLAGS=
  SDL3_LIBS=
  AS_IF([test "x$enable_native_macos" != xyes && test "x$enable_sdl3" = xyes], [
    AC_MSG_CHECKING([for SDL3 using pkg-config])
    AS_IF([command -v pkg-config >/dev/null 2>&1 && pkg-config --exists sdl3], [
      SDL3_CFLAGS=`pkg-config sdl3 --cflags`
      SDL3_LIBS=`pkg-config sdl3 --libs`
      AC_DEFINE([C_SDL3], [1])
      AC_MSG_RESULT([yes])
    ], [
      AC_MSG_RESULT([no])
    ])
  ])
  AC_SUBST([SDL3_CFLAGS])
  AC_SUBST([SDL3_LIBS])
])

dnl configure.ac owns the --enable-sdl2 option and its default.
dnl Prefer pinned SDL2, then an explicit SDL2_CONFIG/prefix, then pkg-config,
dnl and finally a discovered sdl2-config executable.
AC_DEFUN([AM_PATH_SDL2], [
  AC_ARG_WITH([sdl2-prefix],
    [AS_HELP_STRING([--with-sdl2-prefix=PFX], [prefix where SDL2 is installed])],
    [sdl2_prefix=$withval], [sdl2_prefix=])
  AC_ARG_WITH([sdl2-exec-prefix],
    [AS_HELP_STRING([--with-sdl2-exec-prefix=PFX], [execution prefix where SDL2 is installed])],
    [sdl2_exec_prefix=$withval], [sdl2_exec_prefix=])
  dnl Retained for older callers; neither backend executes a runtime SDL2 test.
  AC_ARG_ENABLE([sdl2test],
    [AS_HELP_STRING([--disable-sdl2test], [legacy compatibility option (no runtime test)])])

  AH_TEMPLATE([C_SDL2], [Define to 1 to enable SDL 2.x support])
  SDL2_CFLAGS=
  SDL2_LIBS=

  AS_IF([test "x$enable_native_macos" != xyes && test "x$enable_sdl2" = xyes], [
    sdl2_config_args=
    sdl2_explicit_config=no
    AS_IF([test -x vs/sdl2/linux-host/bin/sdl2-config], [
      SDL2_CONFIG=vs/sdl2/linux-host/bin/sdl2-config
      sdl2_explicit_config=yes
    ], [
      AS_IF([test -n "$sdl2_exec_prefix"], [
        SDL2_CONFIG="$sdl2_exec_prefix/bin/sdl2-config"
        sdl2_config_args="$sdl2_config_args --exec-prefix=$sdl2_exec_prefix"
        sdl2_explicit_config=yes
      ])
      AS_IF([test -n "$sdl2_prefix"], [
        AS_IF([test "x$sdl2_explicit_config" != xyes],
          [SDL2_CONFIG="$sdl2_prefix/bin/sdl2-config"])
        sdl2_config_args="$sdl2_config_args --prefix=$sdl2_prefix"
        sdl2_explicit_config=yes
      ])
      AS_IF([test -n "$SDL2_CONFIG"], [sdl2_explicit_config=yes])
    ])
    AC_PATH_PROG([SDL2_CONFIG], [sdl2-config], [no])
    AC_MSG_CHECKING([for SDL2])
    AS_IF([test "x$sdl2_explicit_config" != xyes &&
           command -v pkg-config >/dev/null 2>&1 &&
           pkg-config --exists sdl2], [
      SDL2_CFLAGS=`pkg-config sdl2 --cflags`
      SDL2_LIBS=`pkg-config sdl2 --libs`
      AC_DEFINE([C_SDL2], [1])
      AC_MSG_RESULT([found using pkg-config])
    ], [
      AS_IF([test "x$SDL2_CONFIG" != xno &&
             "$SDL2_CONFIG" $sdl2_config_args --cflags >/dev/null 2>&1 &&
             "$SDL2_CONFIG" $sdl2_config_args --libs >/dev/null 2>&1], [
        SDL2_CFLAGS=`"$SDL2_CONFIG" $sdl2_config_args --cflags`
        SDL2_LIBS=`"$SDL2_CONFIG" $sdl2_config_args --libs`
        AC_DEFINE([C_SDL2], [1])
        AC_MSG_RESULT([found using sdl2-config])
      ], [
        AC_MSG_RESULT([not found])
      ])
    ])
  ])
  AC_SUBST([SDL2_CFLAGS])
  AC_SUBST([SDL2_LIBS])
])

dnl Configure Paths for Alsa
dnl Some modifications by Richard Boulton <richard-alsa@tartarus.org>
dnl Christopher Lansdown <lansdoct@cs.alfred.edu>
dnl Jaroslav Kysela <perex@suse.cz>
dnl Last modification: alsa.m4,v 1.22 2002/05/27 11:14:20 tiwai Exp
dnl AM_PATH_ALSA([MINIMUM-VERSION [, ACTION-IF-FOUND [, ACTION-IF-NOT-FOUND]]])
dnl Test for libasound, and define ALSA_CFLAGS and ALSA_LIBS as appropriate.
dnl enables arguments --with-alsa-prefix=
dnl                   --with-alsa-enc-prefix=
dnl                   --disable-alsatest  (this has no effect, as yet)
dnl
dnl For backwards compatibility, if ACTION_IF_NOT_FOUND is not specified,
dnl and the alsa libraries are not found, a fatal AC_MSG_ERROR() will result.
dnl
AC_DEFUN([AM_PATH_ALSA],
[dnl Save the original CFLAGS, LDFLAGS, and LIBS
alsa_save_CFLAGS="$CFLAGS"
alsa_save_LDFLAGS="$LDFLAGS"
alsa_save_LIBS="$LIBS"
alsa_found=yes

dnl
dnl Get the cflags and libraries for alsa
dnl
AC_ARG_WITH([alsa-prefix],
  [AS_HELP_STRING([--with-alsa-prefix=PFX], [prefix where ALSA is installed])],
  [alsa_prefix="$withval"], [alsa_prefix=""])

AC_ARG_WITH([alsa-inc-prefix],
  [AS_HELP_STRING([--with-alsa-inc-prefix=PFX], [ALSA include directory])],
  [alsa_inc_prefix="$withval"], [alsa_inc_prefix=""])

dnl FIXME: this is not yet implemented
AC_ARG_ENABLE([alsatest],
  [AS_HELP_STRING([--disable-alsatest], [legacy compatibility option (no runtime test)])],
  [enable_alsatest=$enableval], [enable_alsatest=yes])

dnl Add any special include directories
AC_MSG_CHECKING(for ALSA CFLAGS)
if test "$alsa_inc_prefix" != "" ; then
	ALSA_CFLAGS="$ALSA_CFLAGS -I$alsa_inc_prefix"
	CFLAGS="$CFLAGS -I$alsa_inc_prefix"
fi
AC_MSG_RESULT($ALSA_CFLAGS)

dnl add any special lib dirs
AC_MSG_CHECKING(for ALSA LDFLAGS)
if test "$alsa_prefix" != "" ; then
	ALSA_LIBS="$ALSA_LIBS -L$alsa_prefix"
	LDFLAGS="$LDFLAGS $ALSA_LIBS"
fi

dnl add the alsa library
ALSA_LIBS="$ALSA_LIBS -lasound -lm -ldl -lpthread"
LIBS=`echo $LIBS | sed 's/-lm//'`
LIBS=`echo $LIBS | sed 's/-ldl//'`
LIBS=`echo $LIBS | sed 's/-lpthread//'`
LIBS=`echo $LIBS | sed 's/  //'`
LIBS="$ALSA_LIBS $LIBS"
AC_MSG_RESULT($ALSA_LIBS)

dnl Check for a working version of libasound that is of the right version.
min_alsa_version=m4_if([$1], [], [0.1.1], [$1])
AC_MSG_CHECKING(for libasound headers version >= $min_alsa_version)
no_alsa=""
    alsa_min_major_version=`echo $min_alsa_version | \
           sed 's/\([[0-9]]*\).\([[0-9]]*\).\([[0-9]]*\)/\1/'`
    alsa_min_minor_version=`echo $min_alsa_version | \
           sed 's/\([[0-9]]*\).\([[0-9]]*\).\([[0-9]]*\)/\2/'`
    alsa_min_micro_version=`echo $min_alsa_version | \
           sed 's/\([[0-9]]*\).\([[0-9]]*\).\([[0-9]]*\)/\3/'`

AC_LANG_PUSH([C])
AC_COMPILE_IFELSE(
  [AC_LANG_PROGRAM([[
#include <alsa/asoundlib.h>

/* ensure backward compatibility */
#if !defined(SND_LIB_MAJOR) && defined(SOUNDLIB_VERSION_MAJOR)
#define SND_LIB_MAJOR SOUNDLIB_VERSION_MAJOR
#endif
#if !defined(SND_LIB_MINOR) && defined(SOUNDLIB_VERSION_MINOR)
#define SND_LIB_MINOR SOUNDLIB_VERSION_MINOR
#endif
#if !defined(SND_LIB_SUBMINOR) && defined(SOUNDLIB_VERSION_SUBMINOR)
#define SND_LIB_SUBMINOR SOUNDLIB_VERSION_SUBMINOR
#endif

#if (SND_LIB_MAJOR < $alsa_min_major_version) || \
    (SND_LIB_MAJOR == $alsa_min_major_version && \
     SND_LIB_MINOR < $alsa_min_minor_version) || \
    (SND_LIB_MAJOR == $alsa_min_major_version && \
     SND_LIB_MINOR == $alsa_min_minor_version && \
     SND_LIB_SUBMINOR < $alsa_min_micro_version)
#error libasound headers are too old
#endif
  ]], [[]])],
  [AC_MSG_RESULT([found.])],
  [AC_MSG_RESULT([not present.])
   m4_if([$3], [], [AC_MSG_ERROR([Sufficiently new version of libasound not found.])])
   alsa_found=no]
)
AC_LANG_POP([C])

dnl Now that we know that we have the right version, let's see if we have the library and not just the headers.
AC_CHECK_LIB([asound], [snd_ctl_open],,
	[m4_if([$3], [], [AC_MSG_ERROR([No linkable libasound was found.])])
	 alsa_found=no]
)

if test "x$alsa_found" = "xyes" ; then
   m4_if([$2], [], [:], [$2])
   LIBS=`echo $LIBS | sed 's/-lasound//g'`
   LIBS=`echo $LIBS | sed 's/  //'`
   LIBS="-lasound $LIBS"
fi
if test "x$alsa_found" = "xno" ; then
   m4_if([$3], [], [:], [$3])
   CFLAGS="$alsa_save_CFLAGS"
   LDFLAGS="$alsa_save_LDFLAGS"
   LIBS="$alsa_save_LIBS"
   ALSA_CFLAGS=""
   ALSA_LIBS=""
fi

dnl That should be it.  Now just export out symbols:
AC_SUBST(ALSA_CFLAGS)
AC_SUBST(ALSA_LIBS)
])

AH_TOP([
/*
 *  Copyright (C) 2002-2021  The DOSBox Team
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Library General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with this program; if not, write to the Free Software Foundation, Inc.,
 *  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */
])

AH_BOTTOM([#if C_ATTRIBUTE_ALWAYS_INLINE
#define INLINE inline __attribute__((always_inline))
#else
#define INLINE inline
#endif])

AH_BOTTOM([#if C_ATTRIBUTE_FASTCALL
#define DB_FASTCALL __attribute__((fastcall))
#else
#define DB_FASTCALL
#endif])


AH_BOTTOM([#if C_HAS_ATTRIBUTE
#define GCC_ATTRIBUTE(x) __attribute__ ((x))
#else
#define GCC_ATTRIBUTE(x) /* attribute not supported */
#endif])

AH_BOTTOM([#if C_HAS_BUILTIN_EXPECT
#define GCC_UNLIKELY(x) __builtin_expect((x),0)
#define GCC_LIKELY(x) __builtin_expect((x),1)
#else
#define GCC_UNLIKELY(x) (x)
#define GCC_LIKELY(x) (x)
#endif])

dnl These custom typedefs are unnecessary and should be deprecated.
dnl Linux systems for ages now have had stdint.h to define uint8_t, etc.
AH_BOTTOM([
#if !defined(FLUIDINC)
#include <cstdint>

typedef uintptr_t Bitu;
typedef intptr_t Bits;
#endif
])
