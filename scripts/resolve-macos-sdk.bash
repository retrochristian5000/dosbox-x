#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != Darwin ]; then
    printf 'error: macOS SDK resolver called on non-Darwin host\n' >&2
    exit 2
fi

sdk="${DOSBOX_MACOS_SDKROOT:-}"
if [ -z "$sdk" ]; then
    command -v xcrun >/dev/null 2>&1 || {
        printf 'error: xcrun is required to locate the active macOS SDK\n' >&2
        exit 1
    }
    sdk="$(xcrun --sdk macosx --show-sdk-path)" || exit 1
fi

[ -d "$sdk" ] || {
    printf 'error: macOS SDK directory does not exist: %s\n' "$sdk" >&2
    exit 1
}
# SDK headers may come from the compiler's SDK overlay, VFS or search
# paths rather than a fixed physical location. The build validates actual
# #include <sys/types.h> behavior using the selected target compiler.

printf '%s\n' "$sdk"
