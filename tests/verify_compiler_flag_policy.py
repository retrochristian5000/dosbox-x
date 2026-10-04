#!/usr/bin/env python3
"""Guard generic Autoconf flags against accidental host-ISA narrowing."""

from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
configure = (root / "configure.ac").read_text(encoding="utf-8")

errors = []

# Generic configure policy must remain ABI-neutral. Target-specific build
# drivers may select an architecture explicitly; configure.ac must not infer
# tuning from the build machine.
for flag in ("-march=", "-mcpu=", "-mtune=", "-msse", "-mavx"):
    if flag in configure:
        errors.append(f"configure.ac contains implicit ISA tuning: {flag}")

required = (
    'CPPFLAGS="$CPPFLAGS -DHX_DOS"',
    'CPPFLAGS="$CPPFLAGS -DFORCE_SDLDRAW"',
    'CPPFLAGS="$CPPFLAGS -DOS2 -idirafter /@unixroot/usr/include/os2tk45"',
)
for snippet in required:
    if snippet not in configure:
        errors.append(f"missing portable flag-policy snippet: {snippet}")

for snippet in (
    'CXXFLAGS="$CXXFLAGS -DHX_DOS"',
    'CXXFLAGS="$CXXFLAGS -DFORCE_SDLDRAW"',
    '-march=pentium4',
):
    if snippet in configure:
        errors.append(f"legacy CXXFLAGS/CPU assumption returned: {snippet}")

if errors:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    raise SystemExit(1)

print("compiler flag policy: OK")
