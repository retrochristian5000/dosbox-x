#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
srcdir="$root/vs/zlib"
builddir="$root/.build/zlib-build"
instdir="$root/.build/zlib-host"

if [ ! -f "$srcdir/zlib.h" ]; then
    if [ -d "$root/.git" ] || [ -f "$root/.git" ]; then
        echo "Initializing pinned zlib submodule"
        git -C "$root" submodule update --init --depth 1 -- vs/zlib
    fi
fi

if [ ! -f "$srcdir/zlib.h" ] || [ ! -f "$srcdir/configure" ]; then
    echo "zlib source is unavailable; initialize the vs/zlib submodule" >&2
    exit 2
fi

rm -rf "$builddir" "$instdir"
mkdir -p "$builddir" "$instdir/include" "$instdir/lib"

cd "$builddir"
"$srcdir/configure" || exit 1
make -j || exit 1

cp -v "$srcdir/zlib.h" zconf.h "$instdir/include/" || exit 1
cp -v libz.a "$instdir/lib/" || exit 1
