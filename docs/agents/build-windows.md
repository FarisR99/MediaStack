# Windows build (agent notes)

Human version: `docs/building-windows.md`.

You can't run any of this from WSL/Linux. When you change Windows build scripts, check them for bash syntax (`bash -n`), reason carefully about MSYS2 path behaviour, and say in the commit that it's untested on Windows.

**Verified on Windows (2026-10-18, RTX 5090, MSYS2 gcc 16.2):** `deps.sh`, `build.sh`, `package.sh` and `activate.ps1` work. Smoke tests pass from `dist` in plain PowerShell: FFmpeg NVENC encode, mpv `--vf=gpu=api=d3d11:hw-output=yes:hw-format=nv12` straight into hevc_nvenc ("Rendering directly to nv12 hardware frames"), and mpv `--vf=gpu=api=vulkan` into hevc_nvenc. NVEncC: see the spike result below. Lessons from that first run:
- mpv's `-Dwin32-smtc` needs `cppwinrt` (now in `deps.sh`).
- pacman's `ffmpeg`/`libplacebo` can't always be removed, because packages like `ffms2` depend on them. That's fine: the stack's DLLs sit next to its exes.
- Users may have older mpv/FFmpeg on the *Machine* PATH, which beats the User PATH. Don't tell them to edit PATH persistently; use `activate.ps1` (session only).
- The Vulkan path logs `hevc_nvenc: ignoring invalid SAR: 0/0`: vf_gpu's software output frames leave `p_w`/`p_h` unset. It's harmless (avcodec treats it as unknown).

## Environments

- **MSYS2 UCRT64 only** (`$MSYSTEM == UCRT64`; package prefix `mingw-w64-ucrt-x86_64-`). This covers nv-codec-headers, libplacebo, FFmpeg and mpv. Every script refuses to run in other MSYS2 environments.
- **Developer PowerShell for VS 2022** plus the CUDA Toolkit (`CUDA_PATH`; ≤ 13.0, the newest `nvenc/cudaver.props` knows) for NVEncC, which upstream builds only with MSVC. VS 2022 is required in practice: CUDA 13.0's MSBuild integration only targets it. SDK headers are fetched by the script (below).

## Scripts

| Script | Does |
|---|---|
| `scripts/windows/deps.sh` | pacman deps. **Doesn't** install pacman's ffmpeg/libplacebo, and warns if they're present. |
| `scripts/windows/build.sh [project...]` | `MS_TARGET=ucrt64` → `scripts/common/build-all.sh`. Out-of-tree builds in `out/ucrt64/build/<p>`, installs into the **dev prefix** `out/ucrt64/prefix`. Skips nvenc. |
| `scripts/windows/nvencc-spike.ps1 [-Route A\|B]` | Stages `nvenc/ffmpeg_lgpl/` (gitignored by NVEnc), runs `msbuild NVEnc.sln /t:NVEncC RelStatic x64`, and copies to `out/ucrt64/nvencc/`. |
| `scripts/windows/build-ffmpeg-msvc.sh` | Route B only: minimal shared FFmpeg built with `--toolchain=msvc` into `out/msvc/prefix`. |
| `scripts/windows/package.sh` | Portable `out/ucrt64/dist/`: exes plus the `ldd` closure of non-system DLLs, NVEncC if built, the NVIDIA runtime bundles, and `BUILDINFO.txt`. |
| `scripts/windows/activate.ps1` | Prepends `out\ucrt64\dist` to `$env:Path` for the current PowerShell session only (never the registry). Run it before testing on a PC that also has older mpv/FFmpeg on PATH. |

## How NVEncC links FFmpeg on Windows

- The vcxproj adds `..\ffmpeg_lgpl\include` and `..\ffmpeg_lgpl\lib\$(Platform)`. The sources `#pragma comment(lib, "avcodec.lib")` etc. and `dovi.lib`.
- The post-build step copies `avcodec-*.dll`, `libass-*.dll` and `libplacebo-*.dll` from that folder.
- At runtime NVEncC expects specific DLL names (`AVCODEC_DLL_NAME` in `nvenc/NVEncCore/rgy_avutil.h`), and loads `libass-9.dll` and `libplacebo-<api>.dll` dynamically.
- **Route A** (default): FFmpeg's MinGW shared build already installs MSVC-usable import libs (`bin/*.lib`, made by `lib.exe` if it's on PATH, otherwise `dlltool`). The spike copies those, plus DLLs, and makes `dovi.lib` and `hdr10plus-rs.lib` from UCRT64's libdovi and libhdr10plus-rs DLLs (dumpbin → .def → lib.exe). NVEnc `#pragma comment`-links both. Both use UCRT, so the C ABI matches MSVC.
- **Route B**: needed only if Route A fails to link or crashes. Its FFmpeg lacks the external libs (it's MSVC-built), so NVEncC loses nothing it needs, but its FFmpeg differs from mpv's.

**First spike run (Route A, CUDA 12.8, 24 threads):** it failed before linking, with the compiler running out of memory (`C1060 out of heap space`, `LLVM error : out of memory`, cicc `0xC0000409`, then cascading `C1033 cannot open program database`). The cause was `/m` with `CL_MPCount` = all cores, times nvcc `-t 0` (`CUDA_THREADS` in `nvenc/cudaver.props`) fanning out per architecture. The script now passes `/m:1 /p:CL_MPCount=<Jobs> /p:CUDA_THREADS="-t 1"`, with `-Jobs` defaulting to half the threads. Global properties override cudaver.props, so no nvenc change is needed. Whether the CUDA build customization honours `CL_MPCount` is unconfirmed; `-t 1` alone cuts cicc processes 4×.

**Spike status: Route A works (2026-10-19, SERVER-1, VS 2022 MSVC 14.44, CUDA 13.0, `-Jobs 1`).** No vcxproj changes were needed. A full `-Jobs 1` build takes about 45 minutes; reruns are incremental. Failures on the way, all fixed in the script:
- `VshipColor.h`, `avisynth_c.h`, `VapourSynth.h` missing: the vcxproj includes `$(AVISYNTH_SDK)`, `$(VAPOURSYNTH_SDK)`, `$(OPENCL_HEADERS)` and `$(VSHIP_DIR)`. NVEnc's release CI fills them from rigaya's `hwenc_headers` bundle; the script fetches the same bundle (`NVENC_HEADERS_URL` in `stack.conf`) into `out/ucrt64/build/nvenc-headers/` for any variable that's unset.
- `onnxruntime_cxx_api.h` missing: `ONNXRUNTIME_DIR` likewise, from the ONNX Runtime CPU zip (`NVENC_ONNXRUNTIME_URL`), `include/` only. `onnxruntime.dll` is loaded at runtime and isn't bundled, so `--vpp-onnx` needs the user to supply ONNX Runtime's GPU DLLs: rigaya's `nvenc_vpp_onnx_dlls_20260627.7z` (ORT GPU for CUDA 12 + cuDNN 9 + TensorRT 10) and the models from `HWEnc-onnx-models` releases (latest `20260808`). Links are in `docs/building-windows.md` ("ONNX filters"). Untested with our CUDA 13 NVEncC. They're off by default, and `package.sh` doesn't fetch them. When the user wants an ONNX feature (`--vpp-onnx`, e.g. the HDRTVNet++ SDR-to-HDR model, or `--vpp-onnx-deint`), ask whether to download them first, and say roughly how big they are: about 2 GB of DLLs, plus models from a few MB (deinterlacing only) to about 4 GB (everything). Only fetch the model archives the feature needs. Then run `scripts/windows/fetch-onnx.sh --runtime` and/or `--models deint_ddd|main|fbcnn_nafnet|all` (UCRT64; pinned in `stack.conf` `NVENC_ONNX_*`; cached; models checked against the release's SHA256SUMS; `package.sh` then copies the runtime DLLs into dist; models land in `out/ucrt64/onnx-models` for `--vpp-onnx-model-dir`). The `--runtime` path (no published checksum) is untested.
- `libhdr10plus-rs/hdr10plus.h` missing: UCRT64's `include/hdr10plus.h` is x265's, a different API. `deps.sh` installs `libhdr10plus-rs`, and the spike stages it like libdovi.

**NVIDIA runtime DLLs** (`package.sh`, verified 2026-10-21): these are loaded at runtime, so `ldd` can't find them. `stack.conf` `NVIDIA_NGX_URL`, `NVIDIA_FRUC_URL` and `NVIDIA_VSHIP_URL` are the prebuilt bundles NVEnc's release CI ships (`nvenc/.github/workflows/build_releases.yml`). On an upstream nvenc merge, compare those URLs and bump them together.
- NGX bundle: `NVEncNVSDKNGX.dll` plus `nvngx_truehdr`/`nvngx_vsr` and `cudart64_12` (TrueHDR/VSR for NVEncC, FFmpeg `truehdr_cuda`, mpv `truehdr`), and `NVVideoEffects`/`NVCVImage`/`nvVFXVideoFrameGeneration` (nvvfx).
- FRUC bundle: `NVEncNVOFFRUC.dll`, `NvOFFRUC.dll`, `cudart64_110` and the MSVC runtime (NVEncC `--vpp-fruc`, FFmpeg `fruc_cuda`).
- Vship bundle: `libvship.dll` (NVEncC `--vship-*` SSIMULACRA2/Butteraugli metrics).
- All of these are byte-identical to the DLLs in the NVEncC 9.38 release (checked 2026-10-21). The release's `nvrtc64_112_0.dll` isn't needed: our NVEncC is built with CUDA 13.0 and uses `nvrtc64_130_0.dll`, which the `ldd` walk picks up from the CUDA toolkit.
- Cached in `out/ucrt64/build/nvidia-runtime/<name>/` (`.done` marker) and extracted with Windows' `tar.exe`. A failed download warns and packages without it. They're copied last, so they replace any copies placed in the prefix by hand. Empty URL = skip.
- The wrapper DLLs could be built from `nvenc/NVEncNVSDKNGX`/`NVEncNVOFFRUC` (`ReleaseNVDLL`, needs the RTX Video / Optical Flow SDKs), but the `nvngx_*`/`NvOFFRUC` binaries only come from NVIDIA, so we use the bundles.
- Smoke-tested from `dist`: FFmpeg `truehdr_cuda`, NVEncC `--vpp-ngx-truehdr`, `--vpp-resize ngx-vsr`, `--vpp-fruc fps=48`. nvvfx filters are untested.
- Running from the dev prefix (`out/ucrt64/prefix/bin`) doesn't get them; use `dist`.

`out/ucrt64/nvencc/` isn't self-contained: it lacks the prefix's `swscale`/`libvmaf`/`libplacebo` dependencies and UCRT64's `libdovi`/`libhdr10plus-rs`. Run it from `dist` (`package.sh` resolves them), or with `out\ucrt64\prefix\bin` and `C:\msys64\ucrt64\bin` on PATH. From WSL, a Windows exe only sees a WSL `PATH` with `WSLENV=PATH/l`; otherwise it fails silently with exit 53.

## Gotchas

- `ffmpeg --enable-cuda-nvcc` doesn't work under MinGW, because nvcc needs `cl.exe` as its host compiler. Windows uses `--enable-cuda-llvm` (clang from deps.sh) instead, which gives the same CUDA filters.
- Paths: MSYS2 converts POSIX paths for native programs. `cygpath -m` gives `C:/...` paths for `.pc` files (nv-codec-headers' Makefile already does this).
- Bash scripts must stay LF. `.gitattributes` forces this; don't add `\r`.
- `core.longpaths=true` is set by `setup.sh` (FFmpeg/NVEnc have deep paths).
- The dev prefix works when run from a UCRT64 shell (the DLLs sit next to `mpv.exe` in `prefix/bin`, and UCRT64 is on PATH). Use `dist/` for running outside MSYS2.
