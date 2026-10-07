#!/bin/sh
set -eu

SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${WHP_SOURCE_UPDATE:-auto}

case "$mode" in
    auto|0|1) ;;
    *)
        printf 'error: WHP_SOURCE_UPDATE must be auto, 0, or 1: %s\n' "$mode" >&2
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
    printf 'warning: %s; continuing with the current DOSBox-X checkout\n' "$message" >&2
    return 0
}

if [ "$mode" = auto ] && [ -n "${CI:-}" ]; then
    printf '%s\n' 'DOSBox-X source update: skipped under CI' >&2
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    warn_or_fail 'git is unavailable, so source refresh cannot run'
    exit 0
fi

if ! git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn_or_fail 'source tree is not a Git worktree'
    exit 0
fi

branch=$(git -C "$SOURCE_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
upstream_ref=$(git -C "$SOURCE_DIR" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)
remote=
merge_ref=
if [ -n "$branch" ]; then
    remote=$(git -C "$SOURCE_DIR" config --get "branch.$branch.remote" 2>/dev/null || true)
    merge_ref=$(git -C "$SOURCE_DIR" config --get "branch.$branch.merge" 2>/dev/null || true)
fi

root_dirty=0
git -C "$SOURCE_DIR" diff --quiet --ignore-submodules=all -- || root_dirty=1
git -C "$SOURCE_DIR" diff --cached --quiet --ignore-submodules=all -- || root_dirty=1

if [ "$root_dirty" = 1 ]; then
    warn_or_fail 'tracked DOSBox-X source changes prevent a safe fast-forward update'
elif [ -z "$branch" ]; then
    warn_or_fail 'DOSBox-X checkout is detached, so there is no branch to fast-forward'
elif [ -z "$upstream_ref" ] || [ -z "$remote" ] || [ -z "$merge_ref" ]; then
    warn_or_fail "DOSBox-X branch '$branch' has no complete configured upstream"
else
    printf 'DOSBox-X source update: %s <- %s\n' "$branch" "$upstream_ref" >&2

    if [ "$remote" = "." ]; then
        remote_oid=$(git -C "$SOURCE_DIR" rev-parse "$merge_ref^{commit}" 2>/dev/null || true)
    else
        remote_line=$(git -C "$SOURCE_DIR" ls-remote "$remote" "$merge_ref" 2>/dev/null || true)
        remote_oid=$(printf '%s\n' "$remote_line" | sed -n '1{s/[[:space:]].*//;p;}')
        unset remote_line
    fi

    if [ -z "$remote_oid" ]; then
        warn_or_fail "could not resolve upstream ref '$merge_ref' from '$remote'"
    else
        upstream_oid=$(git -C "$SOURCE_DIR" rev-parse "$upstream_ref^{commit}" 2>/dev/null || true)

        if [ "$remote_oid" != "$upstream_oid" ]; then
            if [ "$remote" != "." ]; then
                printf '%s\n' 'DOSBox-X source update: fetching configured branch only (no tags or submodules)' >&2
                if ! git -C "$SOURCE_DIR" fetch --no-tags --no-recurse-submodules \
                    "$remote" "$merge_ref:$upstream_ref"; then
                    warn_or_fail "targeted fetch from '$remote' failed"
                    upstream_oid=
                else
                    upstream_oid=$(git -C "$SOURCE_DIR" rev-parse "$upstream_ref^{commit}" 2>/dev/null || true)
                fi
            else
                upstream_oid=$remote_oid
            fi
        else
            printf '%s\n' 'DOSBox-X source update: upstream ref unchanged; object fetch skipped' >&2
        fi

        if [ -n "$upstream_oid" ]; then
            if ! git -C "$SOURCE_DIR" merge --ff-only "$upstream_ref"; then
                warn_or_fail "fast-forward update from '$upstream_ref' failed"
            fi
        fi
        unset upstream_oid
    fi
    unset remote_oid
fi

# Keep submodule URL changes from the parent checkout synchronized, but do not
# materialize dependency worktrees here. The separate submodule updater owns
# exact gitlink checkout and dirty-worktree protection.
if [ -f "$SOURCE_DIR/.gitmodules" ]; then
    git -C "$SOURCE_DIR" submodule sync --recursive >/dev/null
fi

printf '%s\n' 'DOSBox-X source update: parent repository current; pinned submodules stay separate' >&2
