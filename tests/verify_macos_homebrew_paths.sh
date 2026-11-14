#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/resolve-macos-homebrew.bash"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT

mkdir -p "$base/arm/bin" "$base/intel/bin" \
    "$base/arm/include" "$base/arm/lib/pkgconfig" "$base/arm/share/pkgconfig" \
    "$base/arm/opt/ffmpeg@7/include" "$base/arm/opt/ffmpeg@7/lib/pkgconfig" \
    "$base/arm/opt/ffmpeg@7/share/pkgconfig" \
    "$base/arm/opt/libslirp/include" "$base/arm/opt/libslirp/lib/pkgconfig" \
    "$base/arm/opt/fluid-synth/include" "$base/arm/opt/fluid-synth/lib/pkgconfig" \
    "$base/arm/opt/libpcap/include" "$base/arm/opt/libpcap/lib/pkgconfig" \
    "$base/intel/lib/pkgconfig" "$base/intel/opt/libslirp/lib/pkgconfig"

# Simulate the same .pc module in the shared prefix and the keg-only
# ffmpeg@7 prefix. Versioned FFmpeg must win without brew link --force.
printf 'Version: 9.0\n' > "$base/arm/lib/pkgconfig/libavcodec.pc"
printf 'Version: 7.1\n' > "$base/arm/opt/ffmpeg@7/lib/pkgconfig/libavcodec.pc"

for tree in arm intel; do
  cat > "$base/$tree/bin/brew" <<'SH'
#!/bin/sh
prefix=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 1
case "$1" in
  --prefix)
    if [ "$#" -eq 1 ]; then
      printf '%s\n' "$prefix"
    elif [ "$#" -eq 3 ] && [ "$2" = --installed ]; then
      dir="$prefix/opt/$3"
      [ -d "$dir" ] || exit 1
      if [ "$3" = libslirp ] && [ -n "${DOSBOX_TEST_FOREIGN_PREFIX:-}" ]; then
        printf '%s\n' "$DOSBOX_TEST_FOREIGN_PREFIX"
      else
        printf '%s\n' "$dir"
      fi
    else
      exit 2
    fi
    ;;
  *) printf 'unexpected mock brew call: %s\n' "$*" >&2; exit 2 ;;
esac
SH
  chmod +x "$base/$tree/bin/brew"
done

export DOSBOX_HOMEBREW_ARM64_PREFIX="$base/arm"
export DOSBOX_HOMEBREW_X86_64_PREFIX="$base/intel"
CPPFLAGS='-DTEST'
LDFLAGS='-Wl,-dead_strip'
PKG_CONFIG_PATH=/preserved/pkg

dosbox_select_homebrew arm64 arm64
test "$DOSBOX_BREW_PREFIX" = "$base/arm"
test "$(dosbox_brew --prefix)" = "$base/arm"
test "$(dosbox_brew --prefix --installed ffmpeg@7)" = "$base/arm/opt/ffmpeg@7"
dosbox_use_homebrew_paths
[[ " $CPPFLAGS " == *" -I$base/arm/include "* ]]
[[ " $CPPFLAGS " == *" -I$base/arm/opt/ffmpeg@7/include "* ]]
[[ " $CPPFLAGS " == *" -I$base/arm/opt/libpcap/include "* ]]
[[ " $LDFLAGS " == *" -L$base/arm/lib "* ]]
[[ " $LDFLAGS " == *" -L$base/arm/opt/ffmpeg@7/lib "* ]]
[[ "$PKG_CONFIG_PATH" == "$base/arm/opt/ffmpeg@7/lib/pkgconfig:"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/opt/ffmpeg@7/share/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/opt/libslirp/lib/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/opt/fluid-synth/lib/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/opt/libpcap/lib/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/share/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"/preserved/pkg" ]]

# Universal builds must restore initial flags before resolving the Intel
# tree. A missing optional ffmpeg@7 must not leak the ARM metadata path.
CPPFLAGS='-DTEST'
LDFLAGS='-Wl,-dead_strip'
PKG_CONFIG_PATH=/preserved/pkg
dosbox_select_homebrew x86_64 x86_64
test "$DOSBOX_BREW_PREFIX" = "$base/intel"
test "$DOSBOX_BREW_BINARY" = "$base/intel/bin/brew"
dosbox_use_homebrew_paths
[[ "$PKG_CONFIG_PATH" == "$base/intel/opt/libslirp/lib/pkgconfig:"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/intel/lib/pkgconfig:"* ]]
[[ "$PKG_CONFIG_PATH" == *"/preserved/pkg" ]]
[[ "$PKG_CONFIG_PATH" != *"$base/arm/"* ]]
[[ " $CPPFLAGS " != *" $base/arm/"* ]]
[[ " $LDFLAGS " != *" $base/arm/"* ]]

# Fail closed if the Intel brew unexpectedly supplies an ARM formula path.
export DOSBOX_TEST_FOREIGN_PREFIX="$base/arm/opt/libslirp"
if dosbox_use_homebrew_paths >/dev/null 2>&1; then
  printf 'error: accepted cross-architecture Homebrew formula prefix\n' >&2
  exit 1
fi
unset DOSBOX_TEST_FOREIGN_PREFIX

DOSBOX_HOMEBREW_ARM64_PREFIX=/not/real/path
if dosbox_select_homebrew arm64 arm64 2>/dev/null; then exit 1; fi
printf 'macOS Homebrew formula-prefix discovery: OK\n'
