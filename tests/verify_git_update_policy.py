#!/usr/bin/env python3
"""Guard DOSBox-X source/submodule update policy."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def require(text, needle, label):
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


source = read("scripts/update-source.sh")
submodules = read("scripts/update-submodules.sh")
build = read("build")
llvm = read("scripts/bootstrap-native-llvm.bash")
zlib = read("build-scripts/zlib/build-dosbox.sh")

for needle in (
    "git -C \"$SOURCE_DIR\" ls-remote \"$remote\" \"$merge_ref\"",
    "fetch --no-tags --no-recurse-submodules",
    "merge --ff-only",
    "submodule sync --recursive",
):
    require(source, needle, "targeted parent-repository update")

for forbidden in (
    "git -C \"$SOURCE_DIR\" pull ",
    "reset --hard",
    "clean -fd",
    "fetch --all",
):
    if forbidden in source:
        raise AssertionError(f"unsafe parent-repository update operation: {forbidden}")

if "submodule update --init" in source:
    raise AssertionError("parent source updater must not materialize submodules")

for needle in (
    "git -C \"$SOURCE_DIR\" ls-tree HEAD -- \"$path\"",
    "status --porcelain --untracked-files=normal",
    "submodule update --init --depth 1 -- \"$path\"",
    "submodule update --init -- \"$path\"",
):
    require(submodules, needle, "pinned submodule update")

for forbidden in (
    "submodule update --remote",
    "reset --hard",
    "clean -fd",
    "submodule foreach",
):
    if forbidden in submodules:
        raise AssertionError(f"unsafe submodule update operation: {forbidden}")

require(build, 'WHP_SOURCE_UPDATE=${WHP_SOURCE_UPDATE:-auto}',
        "build source-update policy")
require(build, 'WHP_SUBMODULES=${WHP_SUBMODULES:-auto}',
        "build submodule-update policy")
require(build, '/bin/sh "$root/scripts/update-source.sh"',
        "build parent updater integration")
require(build, 'WHP_SOURCE_UPDATE_DONE=1',
        "build source-update re-entry guard")
require(build, 'exec "$root/build" "$@"',
        "build re-entry after parent fast-forward")
require(build, 'submodule_paths+=(vs/zlib)',
        "macOS zlib pin selection")
require(build, 'submodule_paths+=(toolchains/llvm-project)',
        "LLVM pin selection")
require(build, '/bin/sh "$root/scripts/update-submodules.sh" "${submodule_paths[@]}"',
        "build pinned submodule integration")

require(llvm, '/bin/sh "$root/scripts/update-submodules.sh" "$submodule_path"',
        "LLVM bootstrap pinned-submodule fallback")
require(zlib, '/bin/sh "$root/scripts/update-submodules.sh" vs/zlib',
        "zlib pinned-submodule fallback")

if "submodule update --init --depth 1" in llvm:
    raise AssertionError("LLVM bootstrap still bypasses the central submodule updater")
if "git -C \"$root\" submodule update" in zlib:
    raise AssertionError("zlib helper still bypasses the central submodule updater")

print("DOSBox-X Git update policy: ok")
