#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/resolve-macos-homebrew.bash"
base=$(mktemp -d)
trap 'rm -rf "$base"' EXIT
mkdir -p "$base/arm/bin" "$base/intel/bin" "$base/arm/include" "$base/arm/lib/pkgconfig" "$base/arm/share/pkgconfig" "$base/arm/opt/libslirp/lib/pkgconfig" "$base/arm/opt/fluid-synth/lib/pkgconfig" "$base/intel/lib/pkgconfig"
for tree in arm intel; do
  cat > "$base/$tree/bin/brew" <<'SH'
#!/bin/sh
if [ "$1" = --prefix ]; then
  dirname "$(dirname "$0")"
else
  echo "mock brew: $*"
fi
SH
  chmod +x "$base/$tree/bin/brew"
done
export DOSBOX_HOMEBREW_ARM64_PREFIX="$base/arm"
export DOSBOX_HOMEBREW_X86_64_PREFIX="$base/intel"
CPPFLAGS='-DTEST' LDFLAGS='-Wl,-dead_strip' PKG_CONFIG_PATH=/preserved/pkg
dosbox_select_homebrew arm64 arm64
test "$DOSBOX_BREW_PREFIX" = "$base/arm"
dosbox_use_homebrew_paths
[[ " $CPPFLAGS " == *" -I$base/arm/include "* ]]
[[ " $LDFLAGS " == *" -L$base/arm/lib "* ]]
[[ "$PKG_CONFIG_PATH" == "$base/arm/lib/pkgconfig:"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/share/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"$base/arm/opt/libslirp/lib/pkgconfig"* ]]
[[ "$PKG_CONFIG_PATH" == *"/preserved/pkg" ]]
test "$(dosbox_brew --prefix)" = "$base/arm"
dosbox_select_homebrew x86_64 x86_64
test "$DOSBOX_BREW_PREFIX" = "$base/intel"
test "$DOSBOX_BREW_BINARY" = "$base/intel/bin/brew"
DOSBOX_HOMEBREW_ARM64_PREFIX=/not/real/path
if dosbox_select_homebrew arm64 arm64 2>/dev/null; then exit 1; fi
printf 'macOS Homebrew resolver: OK\n'
