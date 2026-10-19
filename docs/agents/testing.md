# Testing (agent notes)

Human version, with expected output: `docs/testing.md`.

No project's own test suite runs in the stack build. Verify with these smoke tests, and run the project's tests yourself when you change its logic (`meson test` for libplacebo and mpv, `make fate` for FFmpeg; FATE needs samples, so ask first).

## Without installing (Linux)

The exported tree is relocatable (RPATH `$ORIGIN/../lib`), so you can test straight from `out/linux/stage` with no sudo:

```bash
S=out/linux/stage
ldd $S/bin/ffmpeg $S/bin/mpv $S/bin/nvencc | grep 'not found'      # must print nothing
$S/bin/ffmpeg -hide_banner -version | head -1
$S/bin/ffmpeg -hide_banner -encoders | grep -E 'nvenc'               # h264/hevc/av1_nvenc
$S/bin/ffmpeg -hide_banner -filters  | grep -E 'libplacebo|scale_cuda'
$S/bin/mpv --version                                                 # shows FFmpeg + libplacebo versions
$S/bin/mpv --vf=gpu=api=help --no-config                             # vulkan/egl listed
$S/bin/nvencc --version
$S/bin/nvencc --check-hw                                             # needs the GPU (works in WSL)
```

If `ldd` reports missing libs, either `runtime-apt.txt` lists packages this host lacks (install them, or let `install-host.sh` do it), or `finalize.sh` missed a bundle.

## Encode tests (need an NVIDIA GPU; work in WSL)

```bash
T=$(mktemp -d)
$S/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=1920x1080:r=30 -t 3 -c:v hevc_nvenc $T/nvenc.mkv
$S/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=1280x720:r=30 -t 2 \
    -vf "format=yuv420p,hwupload_cuda,scale_cuda=1920:1080" -c:v h264_nvenc $T/cuda.mkv   # nonfree CUDA filter
$S/bin/ffmpeg -hide_banner -init_hw_device vulkan -f lavfi -i testsrc2=s=1280x720 -t 2 \
    -vf "libplacebo=w=1920:h=1080" -c:v hevc_nvenc $T/placebo.mkv                       # slow on WSL (software Vulkan)
$S/bin/mpv --no-config $T/nvenc.mkv --vf=gpu=api=vulkan --o=$T/mpv.mkv --ovc=hevc_nvenc  # mpv encoder path
$S/bin/nvencc -i $T/nvenc.mkv --codec hevc -o $T/nvencc.mkv
$S/bin/nvencc -i $T/nvenc.mkv --codec hevc --vpp-resize libplacebo-spline36 --output-res 2560x1440 -o $T/nvencc-pl.mkv
$S/bin/nvencc -i $T/nvenc.mkv --codec hevc --vpp-libplacebo-deband -o $T/nvencc-deband.mkv
$S/bin/ffprobe -hide_banner $T/*.mkv 2>&1 | grep -E 'Input|Stream'
```

Report which of these you ran, and their results, in your summary or commit body.

Environment limits, which are not regressions; say so explicitly:
- **WSL / containers without an NVIDIA Vulkan ICD:** FFmpeg's `libplacebo` filter and mpv's `--vf=gpu=api=vulkan` work on Mesa lavapipe (`apt install mesa-vulkan-drivers`), slowly. NVEncC's libplacebo filters (`--vpp-resize libplacebo-*`, `--vpp-libplacebo-*`) fail with "vulkan device not set", because they need an NVIDIA Vulkan device that can share memory with CUDA. They only work on native Linux with the NVIDIA driver, or on Windows (D3D11).
- With no Vulkan ICD at all, Vulkan tests fail with `VK_ERROR_INCOMPATIBLE_DRIVER`.

## Clean-host install test (recommended after packaging changes)

This tests `install-host.sh`, the runtime package list and RPATHs in a throwaway Ubuntu 22.04 container with the GPU, leaving this host untouched. It needs the NVIDIA Container Toolkit (`docker info | grep nvidia`).

```bash
docker run --rm --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all -v "$PWD":/repo:ro ubuntu:22.04 bash -c '
  apt-get update -qq && cd /repo && DEBIAN_FRONTEND=noninteractive scripts/linux/install-host.sh &&
  apt-get install -y -qq mesa-vulkan-drivers && . /etc/profile.d/mediastack.sh &&
  ldd /opt/mediastack/bin/* | grep "not found"; ffmpeg -hide_banner -encoders | grep nvenc; nvencc --check-hw'
```

## Windows

From an ordinary Linux box you can't run these yourself. Hand the user the equivalent commands from `docs/testing.md` (Windows section), and say that's what you did.

From WSL on a Windows host with MSYS2 (SERVER-1, checkout `C:\src\MediaStack`), you can. Copy a script to `/mnt/c/msys64/tmp/` and run it with `/mnt/c/msys64/usr/bin/bash.exe -c "MSYSTEM=UCRT64 exec /usr/bin/bash -l /tmp/<script>"` (strip `\r` from the output). Windows `.exe`s also run directly from WSL; pass them Windows paths.

**Vulkan → CUDA → NVENC** (the FFmpeg fork's interop fix). It must encode frames; a regression fails with `CUDA_ERROR_INVALID_VALUE` from `cuExternalMemoryGetMappedMipmappedArray`:

```powershell
ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk -f lavfi -i testsrc2=s=1920x1080:d=5 `
  -vf "format=nv12,hwupload,libplacebo=w=3840:h=2160:format=nv12,hwupload=derive_device=cuda" -c:v hevc_nvenc -f null -
```
