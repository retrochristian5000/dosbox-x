#!/usr/bin/env python3
"""Focused POSIX pkgconf seed and Autotools integration tests."""

from pathlib import Path
import os
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "seeds" / "pkgconf.sh"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(args, overrides=None):
    env = os.environ.copy()
    for key in ("DOSBOX_PKGCONF", "DOSBOX_PKGCONF_VERBOSE", "PKG_CONFIG",
                "PKG_CONFIG_PATH", "PKG_CONFIG_LIBDIR", "PKG_CONFIG_SYSROOT_DIR"):
        env.pop(key, None)
    env.update(overrides or {})
    return subprocess.run([str(SEED), *args], cwd=ROOT, env=env,
                          text=True, capture_output=True, check=False)


require(SEED.is_file(), "missing pkgconf seed")
require(SEED.stat().st_mode & stat.S_IXUSR, "pkgconf seed must be executable")
require(SEED.read_text().startswith("#!/bin/sh\n"), "seed must use POSIX sh")
require(subprocess.run(["sh", "-n", str(SEED)], check=False).returncode == 0,
        "seed fails POSIX shell syntax check")

selected = run(["--print-tool"])
require(selected.returncode == 0 and selected.stdout.strip(),
        f"pkg-config compatible tool missing: {selected.stderr}")
tool = selected.stdout.strip()
require(os.path.isfile(tool) and os.access(tool, os.X_OK),
        "selection must resolve an executable file, not a shell function")
require(not selected.stderr, "normal successful tool selection must be quiet")

version = run(["--version"])
require(version.returncode == 0 and version.stdout.strip(),
        "ordinary --version is not passed to the tool")

empty = run(["--print-tool"], {"DOSBOX_PKGCONF": ""})
require(empty.returncode == 127 and "empty" in empty.stderr,
        "empty explicit seed override must fail, not fall back")

missing = run(["--print-tool"], {"DOSBOX_PKGCONF": "/does-not-exist/pkgconf"})
require(missing.returncode == 127 and "unusable" in missing.stderr,
        "invalid explicit tool must not fall back")

standard = run(["--print-tool"], {"PKG_CONFIG": tool})
require(standard.returncode == 0 and standard.stdout.strip() == tool,
        "standard PKG_CONFIG override must be honored")

priority = run(["--print-tool"], {
    "PKG_CONFIG": "/does-not-exist/pkgconf",
    "DOSBOX_PKGCONF": tool,
})
require(priority.returncode == 0 and priority.stdout.strip() == tool,
        "DOSBOX_PKGCONF explicit override must take precedence")

recursive = run(["--print-tool"], {"DOSBOX_PKGCONF": str(SEED)})
require(recursive.returncode == 127 and "recursive" in recursive.stderr,
        "a wrapper must not select itself")

verbose = run(["--version"], {"DOSBOX_PKGCONF_VERBOSE": "1"})
require(verbose.returncode == 0 and "selected host tool" in verbose.stderr,
        "verbose host-tool diagnostics must use stderr")

usage = run(["--check"])
require(usage.returncode == 2 and "usage:" in usage.stderr,
        "--check needs one or more module names")

with tempfile.TemporaryDirectory(prefix="dosbox-pkgconf-") as directory:
    pc = Path(directory) / "dosbox_seed_probe.pc"
    pc.write_text(
        "prefix=/opt/dosbox-seed\n"
        "libdir=${prefix}/lib\n"
        "includedir=${prefix}/include\n"
        "Name: dosbox_seed_probe\n"
        "Description: DOSBox-X host-tool seed test\n"
        "Version: 1.2.3\n"
        "Libs: -L${libdir} -ldosboxseed\n"
        "Cflags: -I${includedir}\n", encoding="utf-8"
    )
    env = {"PKG_CONFIG_LIBDIR": directory, "PKG_CONFIG_PATH": directory}
    cflags = run(["--cflags", "dosbox_seed_probe"], env)
    require(cflags.returncode == 0 and "-I/opt/dosbox-seed/include" in cflags.stdout
            and not cflags.stderr, "cflags passthrough failed")

    libs = run(["--libs", "dosbox_seed_probe"], env)
    require(libs.returncode == 0 and "-ldosboxseed" in libs.stdout,
            "link flags passthrough failed")

    found = run(["--check", "dosbox_seed_probe"], env)
    require(found.returncode == 0 and "found dosbox_seed_probe (1.2.3)" in found.stdout
            and not found.stderr, "diagnostic should find .pc metadata and report version")

    missing_module = "dosbox_seed_definitely_missing"
    absent = run(["--check", "dosbox_seed_probe", missing_module], env)
    require(absent.returncode == 1 and "found dosbox_seed_probe" in absent.stdout
            and f"missing {missing_module}" in absent.stderr
            and f"PKG_CONFIG_PATH={directory}" in absent.stderr
            and f"PKG_CONFIG_LIBDIR={directory}" in absent.stderr,
            "missing module should name dependency and search paths without hiding successes")

    nonexistent = run(["--exists", missing_module], env)
    require(nonexistent.returncode != 0 and not nonexistent.stdout,
            "ordinary --exists must preserve underlying pkgconf failure")

macos = (ROOT / "build-macos").read_text()
configure = (ROOT / "configure.ac").read_text()
acinclude = (ROOT / "acinclude.m4").read_text()
require('pkgconf_tool="$("$top/seeds/pkgconf.sh" --print-tool)"' in macos,
        "macOS must resolve selected pkg-config-compatible tool once per architecture")
require('PKG_CONFIG="$pkgconf_tool"' in macos
        and 'export PKG_CONFIG' in macos,
        "configure must receive chosen host tool")
require('PKG_CONFIG_PATH' in macos and 'dosbox_use_homebrew_paths' in macos,
        "macOS must preserve .pc search path construction")
require("AC_PATH_PROGS([PKG_CONFIG], [pkgconf pkg-config], [no])" in configure,
        "direct configure must discover both compatible tools")
require("dosbox_pkgconf_exists()" in configure,
        "configure checks must share one selected package metadata tool")
require('"$PKG_CONFIG" --exists' in configure
        and "dosbox_pkgconf_exists sdl2" in acinclude
        and "dosbox_pkgconf_exists sdl3" in acinclude,
        "SDL and configure probes must use resolved package metadata tool")
require(not __import__("re").search(r"(?<![\w-])pkg-config\s+--(?:exists|libs|cflags)", configure + "\n" + acinclude),
        "bare pkg-config commands would bypass selected tool")

print("Pkgconf seed and Autotools wiring: ok")
