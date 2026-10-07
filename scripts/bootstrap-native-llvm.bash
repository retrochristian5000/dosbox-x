#!/usr/bin/env bash
set -euo pipefail

root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
submodule_path="${DOSBOX_X_LLVM_SUBMODULE_PATH:-toolchains/llvm-project}"
source_dir="$root/$submodule_path"
work_root="${DOSBOX_X_LLVM_WORK_ROOT:-$root/.build/llvm-native}"
jobs="${LLVM_JOBS:-2}"
force="${DOSBOX_X_LLVM_FORCE_REBUILD:-0}"

case "$jobs" in
    ''|0|*[!0-9]*) printf 'error: LLVM_JOBS must be a positive integer: %s\n' "$jobs" >&2; exit 2 ;;
esac
case "$force" in
    0|1) ;;
    *) printf 'error: DOSBOX_X_LLVM_FORCE_REBUILD must be 0 or 1\n' >&2; exit 2 ;;
esac

for tool in git cmake ninja; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: LLVM bootstrap dependency not found: %s\n' "$tool" >&2
        exit 1
    }
done

host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_os" in
    Darwin)
        host_tag=macos
        SDKROOT="$(bash "$root/scripts/resolve-macos-sdk.bash")"
        export SDKROOT
        ;;
    Linux) host_tag=linux ;;
    *) printf 'error: WHP LLVM bootstrap currently supports macOS and Linux hosts, not %s\n' "$host_os" >&2; exit 1 ;;
esac
case "$host_arch" in
    arm64|aarch64) llvm_target=AArch64; cmake_arch=arm64 ;;
    x86_64|amd64) llvm_target=X86; cmake_arch=x86_64 ;;
    *) printf 'error: unsupported native LLVM host architecture: %s\n' "$host_arch" >&2; exit 1 ;;
esac

prefix="${DOSBOX_X_LLVM_PREFIX:-$work_root/install-$host_tag-$host_arch}"
build_dir="${DOSBOX_X_LLVM_BUILD_DIR:-$work_root/build-$host_tag-$host_arch}"
marker="$prefix/.dosbox-x-llvm"

expected_revision="$(git -C "$root" ls-tree HEAD -- "$submodule_path" | awk '{print $3}')"
[ -n "$expected_revision" ] || {
    printf 'error: LLVM gitlink is missing from HEAD: %s\n' "$submodule_path" >&2
    exit 1
}

submodule_mode="${WHP_SUBMODULES:-auto}"
case "$submodule_mode" in
    auto|0|1) ;;
    *) printf 'error: WHP_SUBMODULES must be auto, 0, or 1\n' >&2; exit 2 ;;
esac

actual_revision="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)"
if [ "$actual_revision" != "$expected_revision" ]; then
    if [ "$submodule_mode" = 0 ]; then
        printf 'error: LLVM submodule is not at the pinned gitlink and WHP_SUBMODULES=0\n' >&2
        exit 1
    fi
    WHP_SUBMODULES="$submodule_mode" \
        /bin/sh "$root/scripts/update-submodules.sh" "$submodule_path" >&2
fi

[ -f "$source_dir/llvm/CMakeLists.txt" ] && [ -f "$source_dir/clang/CMakeLists.txt" ] || {
    printf 'error: LLVM submodule is incomplete: %s\n' "$source_dir" >&2
    exit 1
}
actual_revision="$(git -C "$source_dir" rev-parse HEAD)"
[ "$actual_revision" = "$expected_revision" ] || {
    printf 'error: LLVM submodule drift: expected %s, got %s\n' "$expected_revision" "$actual_revision" >&2
    exit 1
}

usable() {
    local p="$1" tool
    for tool in clang clang++ llvm-ar llvm-ranlib llvm-nm llvm-strip llvm-objcopy llvm-objdump; do
        [ -x "$p/bin/$tool" ] || return 1
    done
    "$p/bin/clang" --version >/dev/null 2>&1 || return 1
    printf 'int dosbox_x_llvm_probe(void) { return 0; }\n' |
        "$p/bin/clang" -x c -c - -o /dev/null >/dev/null 2>&1 || return 1
}

expected_marker="LLVM_GIT_COMMIT=$expected_revision
HOST_OS=$host_os
HOST_ARCH=$host_arch
LLVM_TARGETS_TO_BUILD=$llvm_target
BOOTSTRAP_SCHEMA=1"

if [ "$force" = 0 ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "$expected_marker" ] && usable "$prefix"; then
    printf 'DOSBox-X LLVM is current: %s\n' "$prefix" >&2
    printf '%s\n' "$prefix"
    exit 0
fi

seed_cc="${CC_FOR_BUILD:-cc}"
seed_cxx="${CXX_FOR_BUILD:-c++}"
command -v "$seed_cc" >/dev/null 2>&1 || { printf 'error: bootstrap C compiler not found: %s\n' "$seed_cc" >&2; exit 1; }
command -v "$seed_cxx" >/dev/null 2>&1 || { printf 'error: bootstrap C++ compiler not found: %s\n' "$seed_cxx" >&2; exit 1; }

mkdir -p "$build_dir" "$prefix"
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS OBJCFLAGS OBJCXXFLAGS

cmake_args=(
    -S "$source_dir/llvm"
    -B "$build_dir"
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER="$seed_cc"
    -DCMAKE_CXX_COMPILER="$seed_cxx"
    -DCMAKE_INSTALL_PREFIX="$prefix"
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
    -DLLVM_ENABLE_PROJECTS=clang
    -DLLVM_TARGETS_TO_BUILD="$llvm_target"
    -DLLVM_DISTRIBUTION_COMPONENTS=clang\;clang-resource-headers\;llvm-ar\;llvm-ranlib\;llvm-nm\;llvm-strip\;llvm-objcopy\;llvm-objdump
    -DLLVM_APPEND_VC_REV=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_ENABLE_BINDINGS=OFF
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DCLANG_INCLUDE_TESTS=OFF
)
if [ "$host_os" = Darwin ]; then
    cmake_args+=(
        "-DCMAKE_OSX_ARCHITECTURES=$cmake_arch"
        "-DCMAKE_OSX_SYSROOT=$SDKROOT"
    )
fi

printf 'Configuring pinned LLVM %s for %s/%s\n' "$expected_revision" "$host_os" "$host_arch" >&2
cmake "${cmake_args[@]}" >&2
if [ "$force" = 1 ]; then
    cmake --build "$build_dir" --target clean --parallel "$jobs" >&2
fi
cmake --build "$build_dir" --target distribution --parallel "$jobs" -- -k 0 >&2
cmake --build "$build_dir" --target install-distribution --parallel "$jobs" >&2

usable "$prefix" || {
    printf 'error: installed LLVM toolchain is incomplete: %s\n' "$prefix" >&2
    exit 1
}
printf '%s\n' "$expected_marker" > "$marker"
printf 'DOSBox-X LLVM ready: %s\n' "$prefix" >&2
printf '%s\n' "$prefix"
