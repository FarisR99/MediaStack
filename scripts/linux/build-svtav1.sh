#!/usr/bin/env bash
# Build SVT-AV1 into the prefix (Ubuntu 22.04 has 0.9.0, several major versions behind).
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
msg "SVT-AV1 $SVTAV1_VERSION -> $MS_PREFIX"

src="$MS_BUILD_ROOT/svtav1/SVT-AV1-$SVTAV1_VERSION"
if [[ ! -d "$src" ]]; then
    mkdir -p "$src"
    curl -fsSL "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/$SVTAV1_VERSION/SVT-AV1-$SVTAV1_VERSION.tar.gz" \
        | tar -xz -C "$src" --strip-components=1
fi
cmake -S "$src" -B "$MS_BUILD_ROOT/svtav1/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$MS_PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DBUILD_SHARED_LIBS=ON -DBUILD_APPS=OFF -DBUILD_TESTING=OFF
cmake --build "$MS_BUILD_ROOT/svtav1/build"
cmake --install "$MS_BUILD_ROOT/svtav1/build"
