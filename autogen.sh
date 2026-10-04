#!/bin/sh

# If an error occurs, quit the script and inform the user. This ensures scripts
# like ./build-macos and ./build-macos-sdl2 etc. Don't continue on if Autotools isn't installed.
finish() {
  if [ "${success}" -eq 0 ]; then
    echo 'autogen.sh failed to complete: verify that GNU Autotools is installed on the system and try again'
  fi
}

success=0
trap finish EXIT
set -e

# zlib is a pinned source dependency. Initialize only this gitlink so normal
# builds do not recursively fetch the much larger LLVM toolchain submodule.
if [ ! -f vs/zlib/zlib.h ]; then
  if [ -d .git ] || [ -f .git ]; then
    echo "Initializing pinned zlib source"
    git submodule update --init --depth 1 -- vs/zlib
  fi
fi
if [ ! -f vs/zlib/zlib.h ]; then
  echo "autogen.sh: pinned zlib source is missing (vs/zlib)" >&2
  exit 1
fi

echo "Generating build information using aclocal, autoheader, automake and autoconf"
echo "This may take a while ..."

# Regenerate configuration files.

aclocal
autoheader
automake -Woverride -Wportability --include-deps --add-missing --copy 
autoconf

echo "Now you are ready to run ./configure."
echo "You can also run  ./configure --help for extra features to enable/disable."

# Don't quit on errors again from here on out (for calling scripts).
set +e
success=1
