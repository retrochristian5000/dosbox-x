#!/usr/bin/env python3
"""Check that external development headers use compiler search paths.

This deliberately uses a synthetic SDK/include tree outside the repository
and avoids downloading dependencies or assuming a particular macOS layout.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SDK_RESOLVER = ROOT / "scripts/resolve-macos-sdk.bash"
MACOS = (ROOT / "build-macos").read_text(encoding="utf-8")
CONFIGURE = (ROOT / "configure.ac").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/native-graphics.yml").read_text(encoding="utf-8")


def require(condition, reason):
    if not condition:
        raise AssertionError(reason)


with tempfile.TemporaryDirectory(prefix="dosbox-external-headers-") as folder:
    base = Path(folder)
    sdk = base / "sdk"
    sdk.mkdir()
    tools = base / "tools"
    tools.mkdir()
    fake_uname = tools / "uname"
    fake_uname.write_text("#!/bin/sh\nprintf 'Darwin\\n'\n", encoding="utf-8")
    fake_uname.chmod(0o755)
    environment = os.environ.copy()
    environment["PATH"] = str(tools) + os.pathsep + environment.get("PATH", "")
    environment["DOSBOX_MACOS_SDKROOT"] = str(sdk)
    resolved = subprocess.run(
        ["bash", str(SDK_RESOLVER)],
        text=True, capture_output=True, env=environment, check=False,
    )
    require(resolved.returncode == 0 and resolved.stdout.strip() == str(sdk),
            "resolver must accept an SDK directory without a particular system-header file")

    # A broken override still fails rather than silently selecting another SDK.
    environment["DOSBOX_MACOS_SDKROOT"] = str(base / "missing-sdk")
    rejected = subprocess.run(
        ["bash", str(SDK_RESOLVER)],
        text=True, capture_output=True, env=environment, check=False,
    )
    require(rejected.returncode != 0 and "does not exist" in rejected.stderr,
            "missing explicit SDK must remain an error")

    compiler = shutil.which("cc") or shutil.which("clang")
    if compiler is None:
        raise AssertionError("C compiler needed for external-header regression test")
    include = base / "external" / "include"
    (include / "dosbox-probe").mkdir(parents=True)
    (include / "dosbox-probe" / "api.h").write_text(
        "typedef struct { int value; } dosbox_external_header;\n", encoding="utf-8"
    )
    program = (
        "#include <dosbox-probe/api.h>\n"
        "int main(void) { dosbox_external_header item = {0}; return item.value; }\n"
    )
    def compile_with(flags):
        return subprocess.run(
            [compiler, "-std=c11", "-Werror", *flags, "-x", "c",
             "-fsyntax-only", "-"],
            input=program, capture_output=True, text=True, check=False,
        )
    found = compile_with(["-I", str(include)])
    require(found.returncode == 0,
            f"compiler must accept external headers with explicit flags: {found.stderr}")
    missing = compile_with(["-I", str(base / "empty")])
    require(missing.returncode != 0,
            "external-header check must really depend on the supplied search path")

require('CPPFLAGS="$CPPFLAGS -I/usr/local/include"' not in CONFIGURE,
        "configure must not override the selected SDK with /usr/local/include")
require('CPPFLAGS="$CPPFLAGS -include X11/XKBlib.h"' not in CONFIGURE,
        "XKB probes must use Autoconf header preambles")
for name in ("XKBrules.h", "XKBfile.h"):
    require(f"AC_CHECK_HEADER([X11/extensions/{name}]" in CONFIGURE,
            f"XKB extension {name} must use compiler header probing")
require("dosbox_pkgconf_exists ncursesw" in CONFIGURE
        and "dosbox_pkgconf_exists ncurses" in CONFIGURE
        and "ncursescfg=`ncursesw6-config --cflags 2>/dev/null`" in CONFIGURE,
        "MinGW ncurses metadata must work if the config tool is absent or broken")
require("sys/types.h" in MACOS and "-fsyntax-only" in MACOS,
        "native macOS must compile an actual system-header probe")
require("test -f \"$sdk/usr/include/sys/types.h\"" not in WORKFLOW,
        "CI must not assert an SDK physical header pathname")
require("SDKROOT=\"$sdk\" clang" in WORKFLOW,
        "CI must still compile a real macOS SDK system-header test")

print("External header discovery: ok")
