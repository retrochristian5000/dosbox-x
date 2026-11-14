#!/usr/bin/env python3
"""Exercise the POSIX grep host-tool seed without building DOSBox-X."""

from pathlib import Path
import os
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "seeds" / "grep.sh"
MACOS = (ROOT / "build-macos").read_text(encoding="utf-8")


def check(condition, detail):
    if not condition:
        raise AssertionError(detail)


def run(arguments, *, input_text=None, overrides=None):
    environment = os.environ.copy()
    environment.pop("DOSBOX_GREP", None)
    environment.pop("DOSBOX_GREP_VERBOSE", None)
    if overrides:
        environment.update(overrides)
    return subprocess.run(
        [str(SEED), *arguments],
        cwd=ROOT, env=environment, input=input_text,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False,
    )


check(SEED.is_file(), "missing seeds/grep.sh")
check(SEED.stat().st_mode & stat.S_IXUSR, "grep seed lost executable bit")
check(SEED.read_text(encoding="utf-8").startswith("#!/bin/sh\n"),
      "grep seed must be a POSIX shell script")
syntax = subprocess.run(["sh", "-n", str(SEED)], cwd=ROOT, check=False)
check(syntax.returncode == 0, "grep seed failed POSIX sh syntax check")

tool = run(["--print-tool"])
check(tool.returncode == 0 and tool.stdout.strip(), "host grep discovery failed")
check(not tool.stderr, "successful discovery should be quiet by default")
tool_path = tool.stdout.strip()
check(os.access(tool_path, os.X_OK), "resolved grep tool must be executable")

matched = run(["-E", "alpha|gamma"], input_text="alpha\nbeta\ngamma\n")
check(matched.returncode == 0 and matched.stdout == "alpha\ngamma\n"
      and not matched.stderr, "grep -E must forward matches and stdout exactly")

quiet = run(["-qi", "APPLE"], input_text="apple\n")
check(quiet.returncode == 0 and quiet.stdout == "",
      "grep -q/-i must preserve successful quiet-match semantics")

unmatched = run(["-q", "not-there"], input_text="a line\n")
check(unmatched.returncode == 1 and not unmatched.stdout,
      "grep should preserve exit code 1 on a non-match")

missing_file = run(["something", "/does-not-exist/dosbox-x-grep-seed"])
check(missing_file.returncode == 2 and missing_file.stderr,
      "native grep errors should preserve exit code 2 and stderr")

explicit = run(["--print-tool"], overrides={"DOSBOX_GREP": tool_path})
check(explicit.returncode == 0 and explicit.stdout.strip() == tool_path,
      "explicit grep executable override was ignored")

verbose = run(["-q", "yes"], input_text="yes\n",
              overrides={"DOSBOX_GREP_VERBOSE": "1"})
check(verbose.returncode == 0 and verbose.stdout == ""
      and "selected host grep" in verbose.stderr,
      "verbose diagnostics must be stderr-only")

empty = run(["--print-tool"], overrides={"DOSBOX_GREP": ""})
check(empty.returncode == 127 and "empty" in empty.stderr,
      "explicit empty override must fail clearly")

missing = run(["--print-tool"], overrides={
    "DOSBOX_GREP": "/does-not-exist/dosbox-x-missing-grep"
})
check(missing.returncode == 127 and "not executable" in missing.stderr,
      "missing tool must fail clearly, not fall back silently")

recursive = run(["--print-tool"], overrides={"DOSBOX_GREP": str(SEED)})
check(recursive.returncode == 127 and "refusing" in recursive.stderr,
      "seed must refuse recursive self-execution")

check('grep_tool="$("$top/seeds/grep.sh" --print-tool)"' in MACOS,
      "macOS host must resolve grep through the seed")
check(MACOS.count('| "$grep_tool" -q .') == 2,
      "both macOS dependency-cache checks must use the resolved grep")
check('if otool -L src/dosbox-x | grep -Eiq' in MACOS,
      "SDL-free linkage guards must remain separate from cache probes")
check("PATH=\"$top/seeds" not in MACOS,
      "do not prepend the seeds directory to PATH")

print("Grep host-tool seed: ok")
