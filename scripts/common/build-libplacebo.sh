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

# The library is named after its API version (libplacebo-<api>.dll,
# libplacebo.so.<api>), and installing a new one leaves the old one behind,
# which NVEncC's build and package.sh would pick up. Remove other versions.
api=$(sed -n 's/^#define PL_API_VER \([0-9]*\)$/\1/p' "$MS_PREFIX/include/libplacebo/config.h")
[[ -n "$api" ]] || die "can't read PL_API_VER from the installed config.h"
for f in "$MS_PREFIX"/bin/libplacebo-*.dll "$MS_PREFIX"/lib/libplacebo.so.*; do
    [[ -e "$f" ]] || continue
    case "$(basename "$f")" in
        libplacebo-"$api".dll|libplacebo.so."$api"|libplacebo.so."$api".*) ;;
        *) msg "Removing stale $(basename "$f")"; rm -f "$f" ;;
    esac
done
