#!/bin/sh
# Preflight GNU Autoconf and its otherwise indirect bootstrap requirements.
# The seed never installs tools, changes PATH, or fetches submodules.
set -u

if [ "${DOSBOX_AUTOCONF+x}" = x ]; then
    requested=$DOSBOX_AUTOCONF
elif [ "${AUTOCONF+x}" = x ]; then
    requested=$AUTOCONF
else
    requested=autoconf
fi

if [ -z "$requested" ]; then
    printf '%s\n' 'autoconf.sh: selected Autoconf executable is empty' >&2
    exit 127
fi

resolve_tool() {
    case "$1" in
        */*) resolved=$1 ;;
        *) resolved=$(command -v "$1" 2>/dev/null) || resolved= ;;
    esac
    [ -n "$resolved" ] && [ -f "$resolved" ] && [ -x "$resolved" ]
}

if ! resolve_tool "$requested"; then
    printf 'autoconf.sh: Autoconf is missing or not executable: %s\n' "$requested" >&2
    exit 127
fi
autoconf_tool=$resolved
case "$autoconf_tool" in
    */autoconf.sh|autoconf.sh)
        printf 'autoconf.sh: refusing recursive seed selection: %s\n' "$autoconf_tool" >&2
        exit 127
        ;;
esac

version_text=$("$autoconf_tool" --version 2>/dev/null) || {
    printf 'autoconf.sh: cannot execute %s --version\n' "$autoconf_tool" >&2
    exit 127
}
version_line=${version_text%%'
'*}
case "$version_line" in
    *'GNU Autoconf'*) ;;
    *)
        printf 'autoconf.sh: not GNU Autoconf: %s\n' "$version_line" >&2
        exit 127
        ;;
esac
version=${version_line##* }
case "$version" in
    *.*) ;;
    *)
        printf 'autoconf.sh: cannot parse Autoconf version: %s\n' "$version_line" >&2
        exit 127
        ;;
esac
major=${version%%.*}
remainder=${version#*.}
minor=${remainder%%.*}
case "$major:$minor" in
    *[!0123456789:]*|:*|*:)
        printf 'autoconf.sh: cannot parse Autoconf version: %s\n' "$version_line" >&2
        exit 127
        ;;
esac
if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 69 ]; }; then
    printf 'autoconf.sh: GNU Autoconf >= 2.69 required, found %s\n' "$version" >&2
    exit 127
fi

if [ "${DOSBOX_AUTOCONF_VERBOSE:-0}" = 1 ]; then
    printf 'autoconf.sh: selected %s (%s)\n' "$autoconf_tool" "$version" >&2
fi

if [ "$#" -eq 1 ] && [ "$1" = --print-tool ]; then
    printf '%s\n' "$autoconf_tool"
    exit 0
fi

if [ "$#" -eq 1 ] && [ "$1" = --doctor ]; then
    # Resolve the checkout without depending on dirname before tools are checked.
    case "$0" in
        */*) seed_dir=${0%/*} ;;
        *) seed_dir=. ;;
    esac
    root=$(CDPATH= cd -- "$seed_dir/.." && pwd) || exit 1
    missing=0
    printf 'Autotools bootstrap preflight (read-only)\n'
    printf '  autoconf: %s (%s)\n' "$autoconf_tool" "$version"
    for name in aclocal autoheader automake autom4te m4 perl; do
        if resolve_tool "$name"; then
            companion=$resolved
            case "$name" in
                perl) "$companion" -e 'exit 0' >/dev/null 2>&1 ;;
                *) "$companion" --version >/dev/null 2>&1 ;;
            esac
            if [ "$?" -eq 0 ]; then
                case "$name" in
                    m4)
                        description=$("$companion" --version 2>/dev/null) || description=
                        case "$description" in
                            *'GNU M4'*|*'GNU m4'*) ;;
                            *)
                                printf '  m4: incompatible; GNU M4 required (%s)\n' "$companion" >&2
                                missing=1
                                continue
                                ;;
                        esac
                        ;;
                    autom4te|autoheader)
                        description=$("$companion" --version 2>/dev/null) || description=
                        first_line=${description%%'
'*}
                        helper_version=${first_line##* }
                        if [ "$helper_version" != "$version" ]; then
                            printf '  %s: version mismatch: %s (Autoconf %s requires same-version helpers)\n' \
                                "$name" "$helper_version" "$version" >&2
                            missing=1
                            continue
                        fi
                        ;;
                esac
                printf '  %s: %s\n' "$name" "$companion"
                continue
            fi
        fi
        printf '  %s: missing or unusable\n' "$name" >&2
        missing=1
    done

    case "${WHP_SUBMODULES:-auto}" in
        auto|0|1) ;;
        *)
            printf '  submodules: invalid WHP_SUBMODULES=%s\n' "$WHP_SUBMODULES" >&2
            missing=1
            ;;
    esac

    if [ -f "$root/vs/zlib/zlib.h" ]; then
        printf '%s\n' '  zlib source: present (gitlink revision not verified by this seed)'
    elif [ "${WHP_SUBMODULES:-auto}" = 0 ]; then
        printf '%s\n' '  zlib source: missing; WHP_SUBMODULES=0 forbids initialization' >&2
        missing=1
    elif [ -e "$root/.git" ]; then
        if resolve_tool git && "$resolved" --version >/dev/null 2>&1; then
            printf '%s\n' '  zlib source: missing; autogen.sh will attempt pinned vs/zlib submodule initialization'
        else
            printf '%s\n' '  zlib source: missing and git is unavailable' >&2
            missing=1
        fi
    else
        printf '%s\n' '  zlib source: missing and no Git metadata; use a clone with submodules' >&2
        missing=1
    fi

    if [ -f "$root/configure" ]; then
        printf '%s\n' '  configure: already present (may still require regeneration)'
    else
        printf '%s\n' '  configure: absent; autogen.sh will generate it'
    fi
    if [ "$missing" -ne 0 ]; then
        printf '%s\n' 'autoconf.sh: bootstrap prerequisites incomplete; no changes made' >&2
        exit 1
    fi
    printf '%s\n' 'autoconf.sh: bootstrap prerequisites available (not a complete build test)'
    exit 0
fi

exec "$autoconf_tool" "$@"
