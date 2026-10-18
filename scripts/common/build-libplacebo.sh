#!/usr/bin/env bash
# Build libplacebo into the prefix.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
msg "libplacebo -> $MS_PREFIX"

args=(
    -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false
    -Dvulkan=enabled -Dvk-proc-addr=enabled -Dshaderc=enabled -Dglslang=disabled
    -Dlcms=enabled -Dlibdovi=enabled -Dopengl=enabled
)
case "$MS_TARGET" in
    ucrt64) args+=(-Dd3d11=enabled) ;;   # NVEncC's Windows libplacebo filters use pl_d3d11_*
    linux)  args+=(-Dd3d11=disabled) ;;
esac

meson_build libplacebo "${args[@]}"
