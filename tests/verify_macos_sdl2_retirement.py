#!/usr/bin/env python3
"""Fail-closed regression checks for macOS SDL2 build retirement."""

from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]

for retired in (
    "build-macos-sdl2",
    "build-macosold-sdl2",
    "scripts/build-macos-legacy-sdl.bash",
):
    if (ROOT / retired).exists():
        raise AssertionError(f"retired macOS SDL2 builder still exists: {retired}")


def check_rejected(command, description, env=None):
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 2:
        raise AssertionError(
            f"{description}: expected exit 2; got {result.returncode}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
    return result.stderr


environment = os.environ.copy()
environment["DOSBOX_MACOS_BACKEND"] = "sdl2"
error = check_rejected(["bash", "build-macos"], "direct environment backend", environment)
if "macOS SDL2 builds are retired" not in error:
    raise AssertionError("retired backend needs a clear diagnostic")

for retired in ("build-macos-sdl2", "build-macosold-sdl2"):
    error = check_rejected(
        ["bash", "build", "--no-config", "--dry-run", "--profile", retired],
        f"universal launcher profile {retired}",
    )
    if "unknown profile" not in error:
        raise AssertionError("retired profile should be rejected before any build")

workflow = (ROOT / ".github/workflows/macos.yml").read_text(encoding="utf-8")
if "build-macos-sdl2" in workflow or "dosbox-x-sdl2" in workflow:
    raise AssertionError("macOS CI still contains an SDL2 build or artifact")

print("Retired macOS SDL2 build policy: ok")
