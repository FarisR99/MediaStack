#!/usr/bin/env bash
# Build libdovi (from quietvoid/dovi_tool) into the prefix. Ubuntu 22.04 has
# no package for it; libplacebo and NVEncC both link it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
msg "libdovi $LIBDOVI_TAG -> $MS_PREFIX"

src="$MS_BUILD_ROOT/libdovi/dovi_tool-$LIBDOVI_TAG"
if [[ ! -d "$src" ]]; then
    mkdir -p "$src"
    curl -fsSL "https://github.com/quietvoid/dovi_tool/archive/refs/tags/$LIBDOVI_TAG.tar.gz" \
        | tar -xz -C "$src" --strip-components=1
fi
cd "$src/dolby_vision"
cargo cinstall --release --prefix="$MS_PREFIX" --libdir="$MS_PREFIX/lib" \
    --target-dir="$MS_BUILD_ROOT/libdovi/target"
