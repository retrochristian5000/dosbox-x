#!/usr/bin/env python3
"""Guard the first-party Automake graph and portable make policy."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
CONFIGURE = (ROOT / "configure.ac").read_text(encoding="utf-8")
AUTOGEN = (ROOT / "autogen.sh").read_text(encoding="utf-8")
TOP_MAKEFILE = (ROOT / "Makefile.am").read_text(encoding="utf-8")

FIRST_PARTY = sorted(
    path
    for path in ROOT.rglob("Makefile.am")
    if path.relative_to(ROOT).parts[0] != "vs"
)


def fail(message):
    raise AssertionError(message)


if "AM_PROG_AR" not in CONFIGURE:
    fail("static-library builds must use AM_PROG_AR for portable archiver discovery")
if "AC_CHECK_TOOL(AR, ar)" in CONFIGURE:
    fail("plain AC_CHECK_TOOL(AR, ar) bypasses Automake archiver interface detection")

if "-Woverride" not in AUTOGEN or "-Wportability" not in AUTOGEN:
    fail("autogen.sh must enable Automake override and portability diagnostics")

match = re.search(r"AC_CONFIG_FILES\(\[(.*?)\]\)", CONFIGURE, re.S)
if not match:
    fail("could not locate AC_CONFIG_FILES block")

configured = set(
    re.findall(r"(?m)^\s*([A-Za-z0-9_./+-]*Makefile)\s*$", match.group(1))
)
tracked = {
    str(path.relative_to(ROOT))[:-3]
    for path in FIRST_PARTY
}

orphans = sorted(tracked - configured)
if orphans:
    fail("orphan Makefile.am files are not configured: " + ", ".join(orphans))

missing_sources = sorted(
    item for item in configured
    if item.endswith("Makefile") and not (ROOT / (item + ".am")).is_file()
)
if missing_sources:
    fail("configured Makefiles lack Makefile.am sources: " + ", ".join(missing_sources))

for path in FIRST_PARTY:
    text = path.read_text(encoding="utf-8")
    rel = path.relative_to(ROOT)

    if "[[" in text:
        fail(f"{rel}: Bash [[ ... ]] leaked into an Automake recipe")
    if "$'" in text:
        fail(f"{rel}: Bash ANSI-C quoting leaked into an Automake recipe")

    meaningful = [
        line.strip()
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if meaningful and all(
        re.match(r"^(?:DIST_)?SUBDIRS\s*=", line)
        for line in meaningful
    ):
        fail(f"{rel}: empty recursive Automake directory adds build-system overhead")

    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(
            r"^\s*[A-Za-z0-9_]+_(CFLAGS|CXXFLAGS|CPPFLAGS|OBJCFLAGS|OBJCXXFLAGS)\s*(?:\+?=)",
            line,
        )
        if m:
            user_var = m.group(1)
            block = [line]
            while block[-1].rstrip().endswith("\\") and i + 1 < len(lines):
                i += 1
                block.append(lines[i])
            joined = "\n".join(block)
            if f"$({user_var})" in joined:
                fail(
                    f"{rel}: {user_var} is manually reinjected into a package/per-target "
                    "flag variable; Automake appends the user variable automatically"
                )
        i += 1

if "$(shell uname -m)" in TOP_MAKEFILE:
    fail("top-level Makefile.am must not depend on GNU make $(shell ...) for ABI naming")
if "\tg++ " in TOP_MAKEFILE:
    fail("top-level helper build must honor the configured CXX compiler")
if "{msdos,demoscene}-compat.html" in TOP_MAKEFILE:
    fail("top-level recipe still relies on shell brace expansion")

if "$(prefix)/share/" in TOP_MAKEFILE:
    fail("top-level install rules must honor Automake datadir instead of hard-coding prefix/share")

for target in ("install", "uninstall", "install_strip", "install-strip"):
    if re.search(rf"(?m)^{re.escape(target)}\s*:", TOP_MAKEFILE):
        fail(f"top-level Makefile.am overrides Automake standard target: {target}")

for hook in ("install-data-hook:", "install-exec-hook:", "uninstall-hook:"):
    if hook not in TOP_MAKEFILE:
        fail(f"top-level Makefile.am is missing Automake extension hook: {hook}")

print("Automake policy: ok")
