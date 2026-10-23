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

**D3D11 P010 hardware output** (validated on the RTX 5090 against the Vulkan path). Both runs must log `Rendering directly to p010 hardware frames`; their decoded frames must be identical:

```powershell
ffmpeg -f lavfi -i testsrc2=s=1920x1080:r=30 -t 2 -c:v hevc_nvenc -profile:v main10 -pix_fmt p010le in10.mkv
mpv.com --no-config in10.mkv --vf=gpu=api=d3d11:hw-output=yes:hw-format=p010 `
  --o=d3d11-p010.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,rc=constqp,qp=22,profile=main10 -v
mpv.com --no-config in10.mkv --vf=gpu=api=vulkan:hw-output=yes:hw-format=p010 `
  --o=vulkan-p010.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,rc=constqp,qp=22,profile=main10 -v
ffmpeg -i d3d11-p010.mkv -f framemd5 - | findstr /v "^#"
ffmpeg -i vulkan-p010.mkv -f framemd5 - | findstr /v "^#"
```

With an 8-bit source the two paths differ by rounding only (per-frame PSNR ≥ 92 dB); the 8-bit NV12 path must stay bit-identical. QSV P010 mapping also works on the UHD 770 (`--d3d11-adapter=Intel --ovc=hevc_qsv`).

**AMD AMF (built, but not yet run on AMD hardware).** Everything AMF needs is already in the Windows build (`--enable-amf`, `amf-headers` from MSYS2). AMF takes D3D11 frames directly, so the zero-copy path is the same one NVENC uses; the AMF-specific risks are driver behaviour (texture views, synchronisation, colour conversion), not our code. Run this when an AMD GPU is available:

```powershell
ffmpeg -hide_banner -encoders | findstr amf     # h264_amf, hevc_amf, av1_amf (AV1 needs RDNA3)
ffmpeg -hide_banner -filters  | findstr amf     # vpp_amf, sr_amf, vqe_amf, frc_amf

# 8-bit zero-copy: render on the AMD GPU, hand NV12 D3D11 frames straight to AMF
mpv.com --no-config in8.mkv --vf=gpu=api=d3d11:hw-output=yes:hw-format=nv12 `
  --o=amf.mkv --ovc=hevc_amf --ovcopts=usage=transcoding,quality=quality,rc=cqp,qp_i=22,qp_p=22 -v

# 10-bit zero-copy (P010)
mpv.com --no-config in10.mkv --vf=gpu=api=d3d11:hw-output=yes:hw-format=p010 `
  --o=amf10.mkv --ovc=hevc_amf --ovcopts=usage=transcoding,quality=quality,rc=cqp,qp_i=22,qp_p=22,profile=main10 -v

# Compare with the download path
mpv.com --no-config in8.mkv --vf=gpu=api=d3d11:hw-output=no `
  --o=amf-sw.mkv --ovc=hevc_amf --ovcopts=usage=transcoding,quality=quality,rc=cqp,qp_i=22,qp_p=22 -v
```

Check, in order:

1. The log says `Rendering directly to nv12`/`p010 hardware frames`, not `Downloading`. No `Could not map` or AMF error.
2. `ffprobe -show_entries stream=pix_fmt,profile,color_primaries,color_transfer,color_space` matches the source (10-bit → `yuv420p10le`/`Main 10`; HDR → BT.2020/PQ tags).
3. HDR10 metadata is written when the source has it: `ffprobe -show_frames -show_entries frame=side_data_list` shows the mastering-display and content-light side data (AMF reads it per frame, unlike NVENC).
4. Decode the result and compare against the download-path encode with PSNR. AMF need not be deterministic, so don't compare bytes.
5. Record the GPU, the Adrenalin/driver version and the AMF runtime version (`ffmpeg -v verbose` logs it), plus fps for both paths. A driver older than 23.30 has no 10-bit AMF support.

If AMF fails, `hw-output=no` is the workaround; `hw-output=auto` already picks the D3D11 path for AMF, so a failure is a regression for AMD users. Known gaps, not bugs to chase: no Vulkan → AMF mapping (so `api=vulkan` and Linux still download/upload), no 4:4:4, and `--ovc-device=amf` cannot select an adapter.

## Finding a performance bottleneck (Windows)

Use a 60 s clip, not 20 s: start-up is about 15% of a 20 s run.

1. **Isolate the stages.** Time the full pipeline, then decode only (`-f null -`), filter only (`-c:v wrapped_avframe -f null -`), and encode without the shader. Sample `nvidia-smi dmon -s u` (columns: shader, memory, encoder and decoder use) during the runs. Also sample per-thread CPU with `Get-Process` → `.Threads[].TotalProcessorTime`. If no stage is busy and one thread sits near 100% of a core, the pipeline is serialised on that thread.
2. **Trace the API calls** with Nsight Systems, which is installed with the driver tools on SERVER-1 (`C:\Program Files\NVIDIA Corporation\Nsight Systems <ver>\target-windows-x64\nsys.exe`): `nsys profile --trace=cuda,vulkan,nvtx,wddm --sample=none -o out <exe> ...`, then `nsys stats --report cuda_api_sum,vulkan_api_sum out.nsys-rep`. For per-thread sequences, `nsys export --type sqlite` and query `VULKAN_API` / `CUPTI_ACTIVITY_KIND_RUNTIME` by `globalTid`. The calls just before and after a long `vkWaitSemaphores` identify who is blocking. The MinGW builds have no PDBs, so CPU backtraces are not useful.

Known costs on NVIDIA on Windows: `vkQueueSubmit2` takes about 15 µs and a zero-timeout `vkWaitSemaphores` 6-8 µs. Anything that does either per render pass shows up with Anime4K.
