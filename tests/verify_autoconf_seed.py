#!/usr/bin/env python3
"""No-network tests for the Autoconf seed and clean-checkout preflight."""

from pathlib import Path
import os
import shutil
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SEED = ROOT / "seeds/autoconf.sh"
AUTOGEN = (ROOT / "autogen.sh").read_text(encoding="utf-8")


def check(value, reason):
    if not value:
        raise AssertionError(reason)


check(SEED.exists() and SEED.stat().st_mode & stat.S_IXUSR,
      "autoconf seed must exist and be executable")
check(SEED.read_text().startswith("#!/bin/sh\n"), "autoconf seed must use POSIX sh")
check(subprocess.run(["sh", "-n", str(SEED)], check=False).returncode == 0,
      "POSIX shell parse failed")
check(subprocess.run(["sh", "-n", "autogen.sh"], cwd=ROOT, check=False).returncode == 0,
      "autogen.sh shell parse failed")

with tempfile.TemporaryDirectory(prefix="dosbox-autoconf-seed-") as folder:
    project = Path(folder) / "source"
    scripts = project / "seeds"
    scripts.mkdir(parents=True)
    fake_bin = project / "tools with spaces"
    fake_bin.mkdir()
    seed = scripts / "autoconf.sh"
    shutil.copy2(SEED, seed)

    def executable(name, body):
        path = fake_bin / name
        path.write_text("#!/bin/sh\n" + body + "\n", encoding="utf-8")
        path.chmod(0o755)
        return path

    fake_autoconf = executable(
        "autoconf",
        'if [ "$1" = "--version" ]; then printf "autoconf (GNU Autoconf) 2.72\\n"; '
        'else printf "forwarded:%s\\n" "$@"; fi'
    )
    older = executable(
        "autoconf-old",
        'if [ "$1" = "--version" ]; then printf "autoconf (GNU Autoconf) 2.68\\n"; fi'
    )
    incompatible = executable(
        "autoconf-other",
        'if [ "$1" = "--version" ]; then printf "OtherAutoconf 2.99\\n"; fi'
    )
    for name in ("aclocal", "autoheader", "automake", "autom4te", "m4", "perl", "git"):
        executable(
            name,
            'if [ "$1" = "--version" ]; then printf "'
            + ("m4 (GNU M4)" if name == "m4" else
               "autoconf (GNU Autoconf)" if name in ("autoheader", "autom4te") else name)
            + (" 2.72\\n" if name in ("autoheader", "autom4te") else ' 1.0\\n')
            + '"; elif [ "$1" = "-e" ]; then exit 0; '
              'else printf "unexpected invocation\\n" >&2; exit 2; fi'
        )

    def run(args, extra=None):
        env = os.environ.copy()
        for key in ("AUTOCONF", "DOSBOX_AUTOCONF", "DOSBOX_AUTOCONF_VERBOSE",
                    "WHP_SUBMODULES"):
            env.pop(key, None)
        env["PATH"] = str(fake_bin)
        env.update(extra or {})
        return subprocess.run(
            [str(seed), *args], cwd=project, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
        )

    selected = run(["--print-tool"])
    check(selected.returncode == 0 and selected.stdout.strip() == str(fake_autoconf)
          and not selected.stderr, "autoconf discovery must be quiet and exact")

    direct = run(["--trace", "AC_INIT", "--output", "temporary output"])
    check(direct.returncode == 0 and direct.stdout.splitlines() ==
          ["forwarded:--trace", "forwarded:AC_INIT", "forwarded:--output",
           "forwarded:temporary output"], "pass-through must preserve arguments")

    explicit = run(["--print-tool"], {"DOSBOX_AUTOCONF": str(fake_autoconf)})
    check(explicit.returncode == 0 and explicit.stdout.strip() == str(fake_autoconf),
          "explicit override containing spaces must remain one path")
    standard = run(["--print-tool"], {"AUTOCONF": str(fake_autoconf)})
    check(standard.returncode == 0, "conventional AUTOCONF override must work")
    empty = run(["--print-tool"], {"DOSBOX_AUTOCONF": ""})
    check(empty.returncode == 127 and "empty" in empty.stderr,
          "empty explicit override must fail")
    missing = run(["--print-tool"], {"DOSBOX_AUTOCONF": "/no/such/autoconf"})
    check(missing.returncode == 127 and "missing" in missing.stderr,
          "missing override must fail without fallback")
    recursive = run(["--print-tool"], {"DOSBOX_AUTOCONF": str(seed)})
    check(recursive.returncode == 127 and "recursive" in recursive.stderr,
          "seed must refuse recursion")
    outdated = run(["--print-tool"], {"DOSBOX_AUTOCONF": str(older)})
    check(outdated.returncode == 127 and "2.69" in outdated.stderr,
          "GNU Autoconf 2.68 must be rejected")
    wrong = run(["--print-tool"], {"DOSBOX_AUTOCONF": str(incompatible)})
    check(wrong.returncode == 127 and "GNU Autoconf" in wrong.stderr,
          "non-GNU replacement must be rejected")
    verbose = run(["--print-tool"], {"DOSBOX_AUTOCONF_VERBOSE": "1"})
    check(verbose.returncode == 0 and "selected" in verbose.stderr
          and verbose.stdout.strip() == str(fake_autoconf),
          "verbose mode must use stderr only")

    # Clean source archive: generated configure and submodule are both absent.
    empty_checkout = run(["--doctor"])
    check(empty_checkout.returncode == 1
          and "no Git metadata" in empty_checkout.stderr
          and "configure: absent" in empty_checkout.stdout,
          "archive without a pinned zlib checkout must explain the blocker")

    # A clone may fetch pinned zlib after the doctor completes; the doctor never fetches.
    (project / ".git").mkdir()
    clone = run(["--doctor"])
    check(clone.returncode == 0 and "will attempt pinned" in clone.stdout,
          "Git clone must disclose the later submodule initialization")
    check(not (project / "vs/zlib/zlib.h").exists(),
          "preflight must not materialize a submodule")
    frozen = run(["--doctor"], {"WHP_SUBMODULES": "0"})
    check(frozen.returncode == 1 and "forbids initialization" in frozen.stderr,
          "explicit submodule freeze must be respected")

    # A fully materialized source tree is also safe without Git metadata.
    (project / ".git").rmdir()
    (project / "vs/zlib").mkdir(parents=True)
    (project / "vs/zlib/zlib.h").write_text("/* fixture */\n", encoding="utf-8")
    ready = run(["--doctor"], {"WHP_SUBMODULES": "0"})
    check(ready.returncode == 0 and "zlib source: present" in ready.stdout,
          "materialized archive must support read-only readiness checks")

    # A different version of autom4te is a hidden bootstrap mismatch.
    executable(
        "autom4te",
        'if [ "$1" = "--version" ]; then printf "autom4te (GNU Autoconf) 2.68\\n"; fi'
    )
    mismatched = run(["--doctor"])
    check(mismatched.returncode == 1 and "version mismatch" in mismatched.stderr,
          "mismatched autom4te must fail before regeneration")
    executable(
        "autom4te",
        'if [ "$1" = "--version" ]; then printf "autom4te (GNU Autoconf) 2.72\\n"; fi'
    )

    # A concealed dependency should be reported, not invoked through a fallback.
    (fake_bin / "autom4te").unlink()
    absent_companion = run(["--doctor"])
    check(absent_companion.returncode == 1
          and "autom4te: missing or unusable" in absent_companion.stderr,
          "missing autom4te must fail early with a specific diagnostic")

check('./seeds/autoconf.sh --doctor || exit 1' in AUTOGEN,
      "autogen must preflight before side effects")
check(AUTOGEN.index('./seeds/autoconf.sh --doctor') <
      AUTOGEN.index('git submodule update --init --depth 1 -- vs/zlib'),
      "no implicit fetch may precede the doctor")
check('autoconf_tool=$(./seeds/autoconf.sh --print-tool)' in AUTOGEN
      and '"$autoconf_tool"' in AUTOGEN,
      "autogen must invoke the verified explicit Autoconf executable")
check('if [ "${WHP_SUBMODULES:-auto}" = 0 ]; then' in AUTOGEN,
      "autogen must honor the submodule initialization opt-out")

print("Autoconf bootstrap seed: ok")
