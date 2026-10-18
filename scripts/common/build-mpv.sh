#!/usr/bin/env bash
# Build mpv (and libmpv) against the stack's FFmpeg and libplacebo.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
msg "mpv -> $MS_PREFIX"

args=(
    -Dlibmpv=true -Dtests=false
    -Dvulkan=enabled -Dlcms2=enabled -Dlua=enabled
    -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled
)
case "$MS_TARGET" in
    ucrt64)
        # Same set as the fork's ci/build-msys2.sh, minus what isn't in deps.sh.
        args+=(
            -Dd3d11=enabled -Dd3d-hwaccel=enabled -Damf=enabled -Dshaderc=enabled
            -Dspirv-cross=enabled -Degl-angle=enabled -Degl-angle-lib=enabled
            -Degl-angle-win32=enabled -Dwin32-smtc=enabled
            -Djpeg=enabled -Dlibarchive=enabled -Dlibbluray=enabled
            -Duchardet=enabled -Drubberband=enabled -Dvapoursynth=disabled
        )
        ;;
    linux)
        args+=(
            -Degl=enabled -Dgl=enabled -Dx11=enabled -Dcuda-hwaccel=enabled
            -Dcuda-interop=enabled -Dalsa=enabled -Dpulse=enabled
        )
        ;;
esac

meson_build mpv "${args[@]}"
