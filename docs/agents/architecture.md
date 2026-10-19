# Architecture (agent notes)

For the long-form version written for people, see `docs/customisations.md`.

## Purpose of the stack

The stack renders video through libplacebo shaders (scaling, tone mapping, user shaders) and encodes the result with hardware encoders, mostly NVENC. Two front ends do this:

1. **mpv as an encoder.** `--vf=gpu` (the fork's `video/filter/vf_gpu*.c`) renders each frame with the same renderer `--vo=gpu-next` uses, then `vo_lavc` (`--o=... --ovc=hevc_nvenc`) encodes through FFmpeg's libavcodec.
2. **NVEncC.** rigaya's standalone NVENC encoder uses FFmpeg (libavformat/libavcodec) for demux/decode/audio and loads libplacebo **at runtime** for `--vpp-libplacebo-*` filters.

FFmpeg's own `vf_libplacebo` and the NVENC/NVDEC/CUVID support are built in too, so `ffmpeg` on its own is also a usable front end. Its zero-copy path is `vf_libplacebo` (Vulkan frames) → `hwupload=derive_device=cuda` → NVENC, on a Vulkan device with `disable_multiplane=1` or derived from CUDA. On NVIDIA this needs our FFmpeg fork's host-transfer fix (`agents/ffmpeg/AGENTS.md`).

## Data flow

```
                      libplacebo (shaders, Vulkan / D3D11 / OpenGL)
                         ▲                 ▲                 ▲
 input ─ FFmpeg demux/decode ─► mpv vf_gpu ┘                 │
                                   │ RGB, or D3D11 NV12/BGRA hw frames (Windows: hw-output, hw-format)
                                   ▼                         │
                          mpv vo_lavc ─► FFmpeg encoder (hevc_nvenc, *_qsv, ...)
                                                             │
 input ─ FFmpeg demux/decode (libav* DLLs/.so) ─► NVEncC ────┘ dlopen("libplacebo-<api>.dll" / "libplacebo.so.<api>")
                                                   └─► NVENC via NVENC SDK + CUDA
```

## Version coupling (what breaks when one moves)

| Dependency | Constraint | Where it's enforced |
|---|---|---|
| mpv → libplacebo | `>= 7.360.1` | `mpv/meson.build` |
| mpv → FFmpeg | current master API (fork tracks upstream master) | mpv meson |
| FFmpeg → libplacebo | `>= 7.351.0` (vf_libplacebo) | `ffmpeg/configure` |
| FFmpeg → Vulkan headers | `>= 1.4.317`, plus `glslc`/`glslang` at build time (shaders compiled into the binary) | `ffmpeg/configure` |
| NVEncC → libplacebo | loads the library by **soname = API version**, and looks up `pl_log_create_<api>`. Upstream NVEnc only knows APIs 338/349/351/360. Our `nvenc` `mediastack` branch also tries `PL_API_VER` from the headers it was compiled against (commit "AI: libplacebo: load the libplacebo API version compiled against"). Keep that commit through merges. | `nvenc/NVEncCore/rgy_libplacebo.cpp` |
| NVEncC (Windows) → FFmpeg | expects DLL names like `avcodec-63.dll`, `avutil-61.dll` (`AVCODEC_DLL_NAME` in `nvenc/NVEncCore/rgy_avutil.h`). When FFmpeg bumps a major version, this list must change. | `rgy_avutil.h` |
| NVEncC → CUDA | meson picks SM targets from the nvcc version; CUDA 13 → sm_75/86/120 | `nvenc/meson.build` |
| FFmpeg/NVEncC → driver | the nv-codec-headers tag sets the minimum NVIDIA driver | `agents/nv-codec-headers/AGENTS.md` |

## Platform specifics

- **Windows (UCRT64):** mpv uses `vf_gpu` `api=d3d11` (libplacebo D3D11) with `hw-output` → D3D11 frames → NVENC/QSV with no download. libplacebo is built with `d3d11=enabled`, both for mpv and because NVEncC's Windows filters call `pl_d3d11_*`. NVEncC is an MSVC build that links FFmpeg through `nvenc/ffmpeg_lgpl/`; see `build-windows.md`.
- **Linux (Docker, Ubuntu 22.04):** mpv uses `vf_gpu` `api=vulkan` or `egl`; the D3D11 hardware output isn't available. NVEncC is built with meson, and its libplacebo filters use Vulkan.
- **WSL2:** CUDA, NVENC and NVDEC work through `/usr/lib/wsl/lib` (`libcuda`, `libnvcuvid`, `libnvidia-encode`). There is **no NVIDIA Vulkan ICD** in WSL:
  - Vulkan falls back to Mesa (lavapipe/dzn, from `mesa-vulkan-drivers`). mpv `vf_gpu` and FFmpeg `vf_libplacebo` run on it (verified), slowly.
  - NVEncC's Linux libplacebo filters need CUDA↔Vulkan interop on an NVIDIA Vulkan device, so they **cannot** work in WSL ("vulkan device not set").
- **Vulkan loader:** build-time only, built in the Dockerfile from Khronos `vulkan-sdk-<VULKAN_SDK_VERSION>`. At runtime everything uses the host's `libvulkan1` (Ubuntu 22.04: 1.3.204, enough for Vulkan 1.3). libplacebo links it (`vk-proc-addr=enabled`), so mpv works without passing its own `vkGetInstanceProcAddr`.
