#!/usr/bin/env bash
# Sourced by build-macos. Resolve one Homebrew tree per target architecture.
# Never mix an Apple Silicon tree with Rosetta's Intel dependency search path.

dosbox_brew() {
    if [ "$DOSBOX_BREW_ARCH" = x86_64 ] && [ "$DOSBOX_BREW_HOST_ARCH" = arm64 ]; then
        /usr/bin/arch -x86_64 "$DOSBOX_BREW_BINARY" "$@"
    else
        "$DOSBOX_BREW_BINARY" "$@"
    fi
}

dosbox_select_homebrew() {
    local target="$1" host="$2" override="" default="" candidate=""
    DOSBOX_BREW_BINARY=""
    DOSBOX_BREW_PREFIX=""
    DOSBOX_BREW_ARCH="$target"
    DOSBOX_BREW_HOST_ARCH="$host"

    case "$target" in
        arm64)
            override="${DOSBOX_HOMEBREW_ARM64_PREFIX:-}"
            default=/opt/homebrew
            ;;
        x86_64)
            override="${DOSBOX_HOMEBREW_X86_64_PREFIX:-}"
            default=/usr/local
            ;;
        *) printf 'Unsupported Homebrew architecture: %s\n' "$target" >&2; return 2 ;;
    esac

    if [ -n "$override" ]; then
        candidate="$override/bin/brew"
        if [ ! -x "$candidate" ]; then
            printf 'Homebrew override has no executable brew: %s\n' "$candidate" >&2
            return 2
        fi
    elif [ "$target" = "$host" ] && [ -n "${HOMEBREW_PREFIX:-}" ]; then
        candidate="$HOMEBREW_PREFIX/bin/brew"
        if [ ! -x "$candidate" ]; then
            printf 'HOMEBREW_PREFIX has no executable brew: %s\n' "$candidate" >&2
            return 2
        fi
    elif [ -x "$default/bin/brew" ]; then
        candidate="$default/bin/brew"
    elif [ "$target" = x86_64 ] && [ -x /usr/local/Homebrew/bin/brew ]; then
        candidate=/usr/local/Homebrew/bin/brew
    elif [ "$target" = "$host" ]; then
        candidate="$(command -v brew 2>/dev/null || true)"
        [ -x "$candidate" ] || candidate=""
    fi

    [ -n "$candidate" ] || return 0
    DOSBOX_BREW_BINARY="$candidate"
    DOSBOX_BREW_PREFIX="$(dosbox_brew --prefix)" || return 1
    if [ ! -d "$DOSBOX_BREW_PREFIX" ]; then
        printf 'Homebrew returned an invalid prefix: %s\n' "$DOSBOX_BREW_PREFIX" >&2
        return 2
    fi
    # Autoconf's space-separated compiler flags cannot safely encode these paths.
    case "$DOSBOX_BREW_PREFIX" in
        *[[:space:]]*) printf 'Homebrew prefix contains whitespace: %s\n' "$DOSBOX_BREW_PREFIX" >&2; return 2 ;;
    esac
}

dosbox_use_homebrew_paths() {
    [ -n "$DOSBOX_BREW_PREFIX" ] || return 0
    local pc_dir brew_pc_path=""
    local opt
    for opt in libslirp fluid-synth libpcap; do
        [ -d "$DOSBOX_BREW_PREFIX/opt/$opt/include" ] && \
            CPPFLAGS="$CPPFLAGS -I$DOSBOX_BREW_PREFIX/opt/$opt/include"
        [ -d "$DOSBOX_BREW_PREFIX/opt/$opt/lib" ] && \
            LDFLAGS="$LDFLAGS -L$DOSBOX_BREW_PREFIX/opt/$opt/lib"
    done
    CPPFLAGS="$CPPFLAGS -I$DOSBOX_BREW_PREFIX/include"
    LDFLAGS="$LDFLAGS -L$DOSBOX_BREW_PREFIX/lib"

    for pc_dir in \
        "$DOSBOX_BREW_PREFIX/lib/pkgconfig" \
        "$DOSBOX_BREW_PREFIX/share/pkgconfig" \
        "$DOSBOX_BREW_PREFIX/opt/libslirp/lib/pkgconfig" \
        "$DOSBOX_BREW_PREFIX/opt/fluid-synth/lib/pkgconfig" \
        "$DOSBOX_BREW_PREFIX/opt/libpcap/lib/pkgconfig"; do
        [ -d "$pc_dir" ] || continue
        brew_pc_path="${brew_pc_path:+$brew_pc_path:}$pc_dir"
    done
    if [ -n "$brew_pc_path" ]; then
        PKG_CONFIG_PATH="$brew_pc_path${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    fi
    export CPPFLAGS LDFLAGS PKG_CONFIG_PATH
}
