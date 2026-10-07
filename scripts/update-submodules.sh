#!/bin/sh
set -eu

SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${WHP_SUBMODULES:-auto}

case "$mode" in
    auto|0|1) ;;
    *)
        printf 'error: WHP_SUBMODULES must be auto, 0, or 1: %s\n' "$mode" >&2
        exit 1
        ;;
esac

[ "$mode" != 0 ] || exit 0

warn_or_fail()
{
    message=$1
    if [ "$mode" = 1 ]; then
        printf 'error: %s\n' "$message" >&2
        exit 1
    fi
    printf 'warning: %s; leaving the affected submodule unchanged\n' "$message" >&2
    return 0
}

if ! command -v git >/dev/null 2>&1; then
    warn_or_fail 'git is unavailable, so pinned submodules cannot be refreshed'
    exit 0
fi

if ! git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn_or_fail 'source tree is not a Git worktree'
    exit 0
fi

if [ ! -f "$SOURCE_DIR/.gitmodules" ]; then
    exit 0
fi

if [ "$#" -gt 0 ]; then
    submodules="$*"
else
    submodules=$(
        git -C "$SOURCE_DIR" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null |
            awk '{print $2}'
    )
fi

[ -n "$submodules" ] || exit 0

for path in $submodules; do
    expected=$(
        git -C "$SOURCE_DIR" ls-tree HEAD -- "$path" 2>/dev/null |
            awk '$2 == "commit" { print $3; exit }'
    )
    if [ -z "$expected" ]; then
        warn_or_fail "gitlink is missing from HEAD for '$path'"
        continue
    fi

    if ! git -C "$SOURCE_DIR" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null |
         awk '{print $2}' | grep -Fxq "$path"; then
        warn_or_fail "path is not a declared submodule: '$path'"
        continue
    fi

    git -C "$SOURCE_DIR" submodule sync -- "$path" >/dev/null

    initialized=0
    dirty=0
    actual=
    if git -C "$SOURCE_DIR/$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        initialized=1
        actual=$(git -C "$SOURCE_DIR/$path" rev-parse HEAD 2>/dev/null || true)
        if [ -n "$(git -C "$SOURCE_DIR/$path" status --porcelain --untracked-files=normal 2>/dev/null || true)" ]; then
            dirty=1
        fi
    fi

    if [ "$initialized" = 1 ] && [ "$actual" = "$expected" ]; then
        printf 'DOSBox-X submodule current: %s @ %s\n' "$path" "$expected" >&2
        continue
    fi

    if [ "$dirty" = 1 ]; then
        warn_or_fail "local changes in '$path' prevent checkout of pinned commit $expected"
        continue
    fi

    printf 'DOSBox-X submodule update: %s -> %s\n' "$path" "$expected" >&2
    if ! git -C "$SOURCE_DIR" submodule update --init --depth 1 -- "$path"; then
        printf 'DOSBox-X submodule update: shallow checkout failed for %s; retrying exact gitlink normally\n' "$path" >&2
        if ! git -C "$SOURCE_DIR" submodule update --init -- "$path"; then
            warn_or_fail "failed to materialize pinned submodule '$path'"
            continue
        fi
    fi

    actual=$(git -C "$SOURCE_DIR/$path" rev-parse HEAD 2>/dev/null || true)
    if [ "$actual" != "$expected" ]; then
        warn_or_fail "submodule '$path' drifted: expected $expected, got ${actual:-missing}"
        continue
    fi

    printf 'DOSBox-X submodule pinned: %s @ %s\n' "$path" "$expected" >&2
done
