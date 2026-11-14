#!/usr/bin/env python3
"""Verify executable build.sh entrypoint without building dependencies."""

from pathlib import Path
import os
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "build.sh"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


require(not (ROOT / "build").exists(), "ambiguous former build filename remains")
for name in ("build.sh", "build-macos"):
    script = ROOT / name
    require(script.is_file(), f"missing shell script: {name}")
    require(script.read_text(encoding="utf-8").startswith("#!/usr/bin/env bash"),
            f"missing Bash shebang: {name}")
    require(script.stat().st_mode & stat.S_IXUSR,
            f"Git checkout lost owner executable permission: {name}")

source = LAUNCHER.read_text(encoding="utf-8")
require('exec "$root/build.sh" "$@"' in source,
        "source-update re-entry must use the executable renamed launcher")
menuconfig = (ROOT / "menuconfig").read_text(encoding="utf-8")
require('preview=("$root/build.sh"' in menuconfig,
        "menuconfig preview must use the renamed launcher")

for name in ("build.sh", "menuconfig", "build-macos"):
    check = subprocess.run(["bash", "-n", name], cwd=ROOT, check=False)
    require(check.returncode == 0, f"Bash syntax failed: {name}")

environment = os.environ.copy()
environment["WHP_SOURCE_UPDATE"] = "0"
environment["WHP_SUBMODULES"] = "0"

for arguments, expected_code, expected_text in (
    (["--help"], 0, "Usage: ./build.sh"),
    (["--list"], 0, "Profiles: auto"),
    (["--no-config", "--dry-run", "--profile", "macos"], 0,
     "DOSBox-X build backend: build-macos"),
    (["--no-config", "--dry-run", "--profile", "build-macos-sdl2"], 2,
     "unknown profile"),
):
    result = subprocess.run(
        [str(LAUNCHER), *arguments], cwd=ROOT, env=environment,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False,
    )
    require(result.returncode == expected_code and
            expected_text in result.stdout + result.stderr,
            f"launcher smoke test failed for {arguments}: "
            f"exit={result.returncode}, stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}")

print("Executable build.sh launcher: ok")
