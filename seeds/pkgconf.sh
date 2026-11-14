#!/bin/sh
# Resolve a real host pkgconf/pkg-config executable without a bootstrap cycle.
# Ordinary invocations are transparent: arguments, output and status pass through.
set -u

requested=
explicit=0
if [ "${DOSBOX_PKGCONF+x}" = x ]; then
    requested=$DOSBOX_PKGCONF
    explicit=1
elif [ "${PKG_CONFIG+x}" = x ]; then
    requested=$PKG_CONFIG
    explicit=1
fi

resolve_candidate() {
    case "$1" in
        */*) executable=$1 ;;
        *) executable=$(command -v "$1" 2>/dev/null) || executable= ;;
    esac

    case "$executable" in
        */pkgconf.sh|pkgconf.sh)
            printf 'pkgconf.sh: refusing recursive tool selection: %s\n' "$executable" >&2
            exit 127
            ;;
    esac

    if [ -n "$executable" ] && [ -x "$executable" ] &&
       "$executable" --version >/dev/null 2>&1; then
        tool=$executable
        return 0
    fi
    return 1
}

tool=
if [ "$explicit" -eq 1 ]; then
    if [ -z "$requested" ]; then
        printf '%s\n' 'pkgconf.sh: explicit pkg-config executable is empty' >&2
        exit 127
    fi
    resolve_candidate "$requested" || :
else
    resolve_candidate pkgconf || resolve_candidate pkg-config || :
fi

if [ -z "$tool" ]; then
    if [ "$explicit" -eq 1 ]; then
        printf 'pkgconf.sh: explicit host tool is missing or unusable: %s\n' "$requested" >&2
    else
        printf '%s\n' 'pkgconf.sh: neither pkgconf nor pkg-config is usable on PATH' >&2
    fi
    exit 127
fi

if [ "${DOSBOX_PKGCONF_VERBOSE:-0}" = 1 ]; then
    printf 'pkgconf.sh: selected host tool: %s\n' "$tool" >&2
fi

if [ "$#" -eq 1 ] && [ "$1" = --print-tool ]; then
    printf '%s\n' "$tool"
    exit 0
fi

if [ "${1:-}" = --check ]; then
    shift
    if [ "$#" -eq 0 ]; then
        printf '%s\n' 'pkgconf.sh: usage: pkgconf.sh --check MODULE [MODULE ...]' >&2
        exit 2
    fi

    missing=0
    for module do
        if details=$("$tool" --print-errors --exists "$module" 2>&1); then
            version=$("$tool" --modversion "$module" 2>/dev/null) || version=unknown
            directory=$("$tool" --variable=pcfiledir "$module" 2>/dev/null) || directory=
            if [ -n "$directory" ]; then
                printf 'pkgconf.sh: found %s (%s) in %s\n' "$module" "$version" "$directory"
            else
                printf 'pkgconf.sh: found %s (%s)\n' "$module" "$version"
            fi
        else
            missing=1
            printf 'pkgconf.sh: missing %s\n' "$module" >&2
            [ -z "$details" ] || printf '%s\n' "$details" >&2
        fi
    done

    if [ "$missing" -ne 0 ]; then
        printf 'pkgconf.sh: PKG_CONFIG_PATH=%s\n' "${PKG_CONFIG_PATH-<unset>}" >&2
        printf 'pkgconf.sh: PKG_CONFIG_LIBDIR=%s\n' "${PKG_CONFIG_LIBDIR-<default>}" >&2
        printf 'pkgconf.sh: PKG_CONFIG_SYSROOT_DIR=%s\n' "${PKG_CONFIG_SYSROOT_DIR-<unset>}" >&2
        defaults=$("$tool" --variable=pc_path pkg-config 2>/dev/null) || defaults=
        [ -z "$defaults" ] || printf 'pkgconf.sh: built-in .pc directories=%s\n' "$defaults" >&2
    fi
    exit "$missing"
fi

exec "$tool" "$@"
