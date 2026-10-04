#!/usr/bin/env python3
"""Guard the pinned zlib source boundary."""

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PIN = "da607da739fa6047df13e66a2af6b8bec7c2a498"

gitmodules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
mac = (ROOT / "build-macos").read_text(encoding="utf-8")
mingw = (ROOT / "build-mingw").read_text(encoding="utf-8")
sln = (ROOT / "vs/dosbox-x.sln").read_text(encoding="utf-8", errors="replace")
project = (ROOT / "vs/zlib-project/zlib.vcxproj").read_text(encoding="utf-8", errors="replace")
wrapper = (ROOT / "build-scripts/zlib/build-dosbox.sh").read_text(encoding="utf-8")
autogen = (ROOT / "autogen.sh").read_text(encoding="utf-8")

for needle in (
    '[submodule "vs/zlib"]',
    'url = https://github.com/retrochristian5000/ZLIB.git',
):
    if needle not in gitmodules:
        raise AssertionError(f"missing zlib submodule metadata: {needle!r}")

index = subprocess.run(
    ["git", "ls-files", "-s", "vs/zlib"],
    cwd=ROOT,
    check=True,
    capture_output=True,
    text=True,
).stdout.strip().split()

if len(index) < 2 or index[0] != "160000":
    raise AssertionError("vs/zlib must be a gitlink, not vendored files")
if index[1] != PIN:
    raise AssertionError(f"unexpected zlib revision: {index[1]} != {PIN}")

for needle in (
    'srcdir="$root/vs/zlib"',
    'git -C "$root" submodule update --init --depth 1 -- vs/zlib',
    '.build/zlib-build',
    '.build/zlib-host',
):
    if needle not in wrapper:
        raise AssertionError(f"missing external zlib build marker: {needle!r}")

for needle in (
    'git submodule update --init --depth 1 -- vs/zlib',
    'pinned zlib source is missing (vs/zlib)',
):
    if needle not in autogen:
        raise AssertionError(f"autogen zlib initialization missing: {needle!r}")

for needle in (
    './build-scripts/zlib/build-dosbox.sh',
    '${top}/.build/zlib-host/include',
    '${top}/.build/zlib-host/lib',
):
    if needle not in mac:
        raise AssertionError(f"macOS zlib path missing: {needle!r}")

if "if false; then" in mingw and "zlib" in mingw:
    raise AssertionError("dead MinGW vendored-zlib fallback returned")

if 'zlib-project\\zlib.vcxproj' not in sln:
    raise AssertionError("Visual Studio zlib project glue path is stale")
for needle in ('..\\zlib\\adler32.c', '..\\zlib\\zlib.h'):
    if needle not in project:
        raise AssertionError(f"Visual Studio is not compiling pinned zlib source: {needle!r}")

print("pinned zlib policy: ok")
