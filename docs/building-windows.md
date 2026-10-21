# Building on Windows

Most of the stack is built with MSYS2's **UCRT64** toolchain. NVEncC is the exception: upstream only supports building it with Visual Studio, so it gets its own step.

> **Status:** all four steps have been run on a real Windows PC (RTX 5090), and the FFmpeg, mpv and NVEncC smoke tests pass.

## 1. Install the dependencies (once)

Open **MSYS2 UCRT64** from the Start menu, `cd` to the repo (e.g. `cd /c/src/MediaStack`), then:

```bash
scripts/windows/deps.sh
```

This installs compilers, meson and the libraries the stack uses (Vulkan, shaderc, libass, dav1d, x264/x265, SVT-AV1, libvpl, ANGLE, ...). It does **not** install pacman's own FFmpeg or libplacebo, because MediaStack builds its own. If you already have those packages installed, the script warns you. Removing them avoids confusion (`pacman -R mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-libplacebo`), but builds work either way.

## 2. Build

```bash
scripts/windows/build.sh            # everything except NVEncC
scripts/windows/build.sh mpv        # just one project (rebuilds are incremental)
scripts/windows/build.sh ffmpeg mpv # several, in the order given
```

Everything is installed into the **dev prefix**, `out\ucrt64\prefix`. To try your build straight away from the UCRT64 shell:

```bash
out/ucrt64/prefix/bin/mpv --version
out/ucrt64/prefix/bin/ffmpeg -hide_banner -encoders | grep nvenc
```

Build order matters: if you change libplacebo, rebuild FFmpeg and mpv afterwards (`scripts/windows/build.sh libplacebo ffmpeg mpv`).

## 3. NVEncC (Visual Studio)

Open **Developer PowerShell for VS 2022**, `cd` to the repo, then:

```powershell
.\scripts\windows\nvencc-spike.ps1
```

This links NVEncC against the FFmpeg you built in step 2. FFmpeg's MinGW build already produces the `.lib` files Visual Studio needs. The script:

1. downloads the SDK headers NVEnc needs (AviSynth+, VapourSynth, OpenCL, Vship, ONNX Runtime) into `out\ucrt64\build\nvenc-headers\`, the same ones NVEnc's own release builds use. If you've installed any of those SDKs yourself and set `AVISYNTH_SDK`, `VAPOURSYNTH_SDK`, `OPENCL_HEADERS`, `VSHIP_DIR` or `ONNXRUNTIME_DIR`, yours is used instead
2. fills `nvenc\ffmpeg_lgpl\`
3. builds `NVEncC64.exe`
4. copies it to `out\ucrt64\nvencc\`
5. runs a quick `--version` / `--check-avcodec-dll` test

If linking fails, or NVEncC crashes at startup, try the fallback, which builds a separate MSVC-native FFmpeg for NVEncC only:

```powershell
.\scripts\windows\nvencc-spike.ps1 -Route B
```

NVEncC has about 90 very large CUDA files. If the build fails with "compiler is out of heap space" or "LLVM error : out of memory", too many of them compiled at once. The script compiles half as many files at a time as you have CPU threads; pass a lower number, e.g. `-Jobs 4`. Rerunning is incremental, so files that already compiled aren't redone.

A first build with `-Jobs 1` takes about 45 minutes; later builds only recompile what changed.

`out\ucrt64\nvencc\` on its own won't start (it needs DLLs from the prefix and from UCRT64). Run `scripts/windows/package.sh` and use `NVEncC64.exe` from `out\ucrt64\dist\`.

> **Status:** Route A (the default) works: built and tested on Windows 11 with Visual Studio 2022 and CUDA 13.0 in October 2026. Route B hasn't been needed.

### ONNX filters (`--vpp-onnx`, `--vpp-onnx-deint`)

NVEncC's ONNX filters run neural-network models, such as the HDRTVNet++ SDR-to-HDR model, through ONNX Runtime on the GPU. MediaStack doesn't include ONNX Runtime or the models, so download both from rigaya's [HWEnc-onnx-models releases](https://github.com/rigaya/HWEnc-onnx-models/releases):

- **Runtime DLLs:** [`nvenc_vpp_onnx_dlls_20260627.7z`](https://github.com/rigaya/HWEnc-onnx-models/releases/download/20260627/nvenc_vpp_onnx_dlls_20260627.7z) (1.9 GB): ONNX Runtime GPU for CUDA 12 plus the cuDNN 9 and TensorRT 10 DLLs it needs. Extract it and put all the DLLs next to `NVEncC64.exe`, in `out\ucrt64\dist\` or your copy of it. The TensorRT DLLs are only loaded with `provider=tensorrt`. To collect the DLLs yourself instead, see the "Required module details" list under `--vpp-onnx` in [NVEncC's option docs](https://github.com/rigaya/NVEnc/blob/master/NVEncC_Options.en.md#--vpp-onnx-param1value1param2value2). The pieces come from [ONNX Runtime releases](https://github.com/microsoft/onnxruntime/releases) (`onnxruntime-win-x64-gpu-*.zip`; MediaStack builds against 1.23.2, `NVENC_ONNXRUNTIME_URL` in `stack.conf`), [CUDA 12](https://developer.nvidia.com/cuda-toolkit-archive) and [cuDNN 9](https://developer.nvidia.com/cudnn-downloads).
- **Models:** the newest release, [`20260808`](https://github.com/rigaya/HWEnc-onnx-models/releases/tag/20260808), splits them into [`onnx_models_20260808_main.zip`](https://github.com/rigaya/HWEnc-onnx-models/releases/download/20260808/onnx_models_20260808_main.zip) (2.0 GB, most models), [`onnx_models_20260808_fbcnn_nafnet.zip`](https://github.com/rigaya/HWEnc-onnx-models/releases/download/20260808/onnx_models_20260808_fbcnn_nafnet.zip) (1.8 GB, the FBCNN and NAFNet restoration models) and [`onnx_models_20260808_deint_ddd.zip`](https://github.com/rigaya/HWEnc-onnx-models/releases/download/20260808/onnx_models_20260808_deint_ddd.zip) (3.5 MB, for `--vpp-onnx-deint`). Extract them into one folder (`SHA256SUMS.txt` lists the checksums) and pass it with `--vpp-onnx-model-dir`. Short names like `model=artcnn_c4f32` then work, and `--vpp-onnx list` shows what's available.

> **Not yet tested with MediaStack's NVEncC,** which is built with CUDA 13; the DLL bundle is the CUDA 12 build that rigaya's releases use.

## 4. Package a portable folder

Back in the UCRT64 shell:

```bash
scripts/windows/package.sh
```

`out\ucrt64\dist\` now holds:

- `mpv.exe`, `ffmpeg.exe`, `ffprobe.exe`, NVEncC (if you built it)
- every DLL they need
- NVIDIA's runtime DLLs for RTX Video HDR and Super Resolution, NVIDIA's video effects filters, frame interpolation for NVEncC and FFmpeg's `fruc_cuda` and its Vship quality metrics (`nvngx_truehdr.dll`, `nvngx_vsr.dll`, `NvOFFRUC.dll`, `libvship.dll` and friends). The first run downloads them (about 180 MB) from the NVEnc release bundles named in `stack.conf`; later runs reuse the download. They make the folder about 465 MB.
- a `BUILDINFO.txt` recording exactly which commits went in

The folder runs on any Windows PC with an NVIDIA driver; it doesn't need MSYS2. Don't share it outside your own machines (see [licensing](licensing.md)).

To use it from a PowerShell window, run:

```powershell
D:\path\to\MediaStack\scripts\windows\activate.ps1
```

This puts the folder **first** on PATH for that window only, ahead of any older mpv or FFmpeg you have installed. Nothing is saved, so closing the window undoes it. Check with `Get-Command mpv, ffmpeg`. In PowerShell, plain `where` is a different command; use `where.exe`. If PowerShell refuses to run scripts, run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once.

## What gets built

| Project | Notable options on Windows |
|---|---|
| libvmaf | built from source (MSYS2's package lacks the built-in VMAF models) |
| libplacebo | Vulkan, D3D11, OpenGL, shaderc, lcms2, libdovi |
| FFmpeg | shared; GPL + nonfree; libplacebo, Vulkan, NVENC/NVDEC/CUVID, CUDA filters (via clang), D3D11VA, DXVA2, QSV (libvpl), AMF, libass, dav1d, x264, x265, SVT-AV1, lcms2, libvmaf |
| mpv | libmpv; Vulkan, D3D11, ANGLE, D3D hwaccel, AMF, Lua, libarchive, Blu-ray, rubberband |
| NVEncC | Visual Studio `RelStatic` x64, using the FFmpeg above |
