#!/usr/bin/env bash
# Build libvmaf into the prefix, for FFmpeg's libvmaf filter. Built from source
# on both targets: Ubuntu 22.04 has no package, and MSYS2's has no built-in
# models (they need xxd at build time), so every model= needed a JSON path.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
msg "vmaf $VMAF_VERSION -> $MS_PREFIX"

command -v xxd >/dev/null || die "xxd not found; it compiles the VMAF models into the library (MSYS2: pacman -S vim; Ubuntu: apt install xxd)"

src="$MS_BUILD_ROOT/vmaf/vmaf-$VMAF_VERSION"
if [[ ! -d "$src" ]]; then
    mkdir -p "$src"
    curl -fsSL "https://github.com/Netflix/vmaf/archive/refs/tags/$VMAF_VERSION.tar.gz" \
        | tar -xz -C "$src" --strip-components=1
fi
MS_SRC_ROOT="$src" MS_BUILD_ROOT="$MS_BUILD_ROOT/vmaf/build" \
    meson_build libvmaf -Dbuilt_in_models=true -Denable_tests=false -Denable_docs=false
# libvmaf.pc's version lags the release tag (v3.2.1 says 3.2.0), so record the tag.
mkdir -p "$MS_PREFIX/share/mediastack"
printf '%s\n' "$VMAF_VERSION" > "$MS_PREFIX/share/mediastack/vmaf-version"
