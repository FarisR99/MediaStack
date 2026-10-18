#!/usr/bin/env bash
# Route B for NVEncC on Windows: a minimal shared FFmpeg built with the MSVC
# toolchain into out/msvc/prefix. Started by nvencc-spike.ps1 -Route B through
# msys2_shell.cmd -use-full-path, so the VS Developer environment (cl.exe,
# link.exe) is inherited. Only what NVEncC needs: demux/decode/filters/audio.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
command -v cl.exe >/dev/null || die "cl.exe not on PATH: start from a VS Developer PowerShell via nvencc-spike.ps1"

prefix="$STACK_ROOT/out/msvc/prefix"
build="$STACK_ROOT/out/msvc/build/ffmpeg"
mkdir -p "$build"
cd "$build"
"$STACK_ROOT/ffmpeg/configure" \
    --toolchain=msvc --prefix="$prefix" \
    --enable-shared --disable-static \
    --enable-gpl --enable-version3 \
    --disable-programs --disable-doc --disable-debug \
    --enable-d3d11va --enable-dxva2 \
    --extra-cflags="-I$STACK_ROOT/out/ucrt64/prefix/include"   # ffnvcodec headers
make -j "$(jobs_count)"
make install
