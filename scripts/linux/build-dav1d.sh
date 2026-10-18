#!/usr/bin/env bash
# Build dav1d into the prefix (Ubuntu 22.04's is older than FFmpeg's 1.0 minimum).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
msg "dav1d $DAV1D_VERSION -> $MS_PREFIX"

src="$MS_BUILD_ROOT/dav1d/dav1d-$DAV1D_VERSION"
if [[ ! -d "$src" ]]; then
    mkdir -p "$src"
    curl -fsSL "https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz" \
        | tar -xz -C "$src" --strip-components=1
fi
MS_SRC_ROOT="$MS_BUILD_ROOT/dav1d" MS_BUILD_ROOT="$MS_BUILD_ROOT/dav1d/build" \
    meson_build "dav1d-$DAV1D_VERSION" -Denable_tools=false -Denable_tests=false
