#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
srcdir="$root/vs/zlib"
builddir="$root/.build/zlib-build"
instdir="$root/.build/zlib-host"

if [ ! -f "$srcdir/zlib.h" ]; then
    if [ -d "$root/.git" ] || [ -f "$root/.git" ]; then
        submodule_mode="${WHP_SUBMODULES:-auto}"
        case "$submodule_mode" in
            auto|1)
                echo "Initializing pinned zlib submodule"
                WHP_SUBMODULES="$submodule_mode" \
                    /bin/sh "$root/scripts/update-submodules.sh" vs/zlib
                ;;
            0)
                echo "zlib submodule is unavailable and WHP_SUBMODULES=0" >&2
                exit 2
                ;;
            *)
                echo "WHP_SUBMODULES must be auto, 0, or 1" >&2
                exit 2
                ;;
        esac
        unset submodule_mode
    fi
fi

if [ ! -f "$srcdir/zlib.h" ] || [ ! -f "$srcdir/configure" ]; then
    echo "zlib source is unavailable; initialize the vs/zlib submodule" >&2
    exit 2
fi

rm -rf "$builddir" "$instdir"
mkdir -p "$builddir" "$instdir/include" "$instdir/lib"

cd "$builddir"

# DOSBox-X consumes only the static archive. Do not make the zlib build depend
# on its shared-library or example-program link paths succeeding.
"$srcdir/configure" --static || exit 1

# zlib's Darwin configure path rewrites AR to Apple libtool. If the DOSBox-X
# launcher selected an archiver explicitly (for example llvm-ar), preserve that
# toolchain choice at make time. Otherwise keep zlib's platform default.
if [ -n "${AR-}" ]; then
    make AR="$AR" ARFLAGS="${ARFLAGS:-rc}" RANLIB="${RANLIB:-ranlib}" libz.a || exit 1
else
    make libz.a || exit 1
fi

if [ ! -s zconf.h ] || [ ! -s libz.a ]; then
    echo "zlib build completed without the required staged inputs" >&2
    exit 1
fi

cp -v "$srcdir/zlib.h" zconf.h "$instdir/include/" || exit 1
cp -v libz.a "$instdir/lib/" || exit 1
