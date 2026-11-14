#!/bin/sh
# Bootstrap a real host grep without introducing another grep dependency.
# Normal invocation passes every argument and exit status through unchanged.
set -u

if [ "${DOSBOX_GREP+x}" = x ]; then
    requested=$DOSBOX_GREP
else
    requested=grep
fi

if [ -z "$requested" ]; then
    printf '%s\n' 'grep.sh: DOSBOX_GREP is empty; set it to a grep executable' >&2
    exit 127
fi

case "$requested" in
    */*) grep_tool=$requested ;;
    *) grep_tool=$(command -v "$requested" 2>/dev/null) || grep_tool= ;;
esac

if [ -z "$grep_tool" ] || [ ! -x "$grep_tool" ]; then
    printf 'grep.sh: host grep is unavailable or not executable: %s\n' "$requested" >&2
    exit 127
fi

# A seed must never recursively execute itself as its host tool.
case "$grep_tool" in
    */grep.sh|grep.sh)
        printf 'grep.sh: refusing another grep.sh wrapper as DOSBOX_GREP: %s\n' "$grep_tool" >&2
        exit 127
        ;;
esac

if [ "${DOSBOX_GREP_VERBOSE:-0}" = 1 ]; then
    printf 'grep.sh: selected host grep: %s\n' "$grep_tool" >&2
fi

if [ "$#" -eq 1 ] && [ "$1" = --print-tool ]; then
    # Probe actual -q behavior before giving configure a reusable executable.
    if ! printf 'dosbox-grep-seed-check\n' | "$grep_tool" -q dosbox-grep-seed-check; then
        printf 'grep.sh: selected host grep failed its basic -q probe: %s\n' "$grep_tool" >&2
        exit 127
    fi
    printf '%s\n' "$grep_tool"
    exit 0
fi

exec "$grep_tool" "$@"
