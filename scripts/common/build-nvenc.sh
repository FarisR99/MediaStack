#!/usr/bin/env bash
# Build NVEncC with meson (Linux). On Windows NVEncC is an MSVC build; see
# scripts/windows/nvencc-spike.ps1.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
[[ "$MS_TARGET" == linux ]] || die "build-nvenc.sh is Linux-only; on Windows use scripts/windows/nvencc-spike.ps1"
msg "nvenc -> $MS_PREFIX"

export CUDA_PATH=${CUDA_PATH:-/usr/local/cuda}
meson_build nvenc \
    -Denable_libplacebo=enabled -Denable_vulkan=enabled -Denable_libass=true \
    -Denable_vapoursynth=false -Denable_avisynth=false \
    -Denable_onnxruntime=disabled -Denable_vmaf=disabled -Denable_libvship=disabled \
    -Dnvenc_cuda_cc="${NVENC_CUDA_CC:-}"
