# Building on Windows

Most of the stack is built with MSYS2's **UCRT64** toolchain. NVEncC is the exception: upstream only supports building it with Visual Studio, so it gets its own step.

> **Status:** steps 1, 2 and 4 have been run on a real Windows PC (RTX 5090), and FFmpeg's and mpv's NVENC smoke tests pass. Step 3 (NVEncC) hasn't been tried yet.

## 1. Install the dependencies (once)

Open **MSYS2 UCRT64** from the Start menu, `cd` to the repo (e.g. `cd /c/src/MediaStack`), then:

```bash
scripts/windows/deps.sh
```

This installs compilers, meson and the libraries the stack uses (Vulkan, shaderc, libass, dav1d, x264/x265, libvpl, ANGLE, ...). It does **not** install pacman's own FFmpeg or libplacebo, because MediaStack builds its own. If you already have those packages installed, the script warns you. Removing them avoids confusion (`pacman -R mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-libplacebo`), but builds work either way.

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

1. fills `nvenc\ffmpeg_lgpl\`
2. builds `NVEncC64.exe`
3. copies it to `out\ucrt64\nvencc\`
4. runs a quick `--version` / `--check-avcodec-dll` test

If linking fails, or NVEncC crashes at startup, try the fallback, which builds a separate MSVC-native FFmpeg for NVEncC only:

```powershell
.\scripts\windows\nvencc-spike.ps1 -Route B
```

> **Status:** this step hasn't been run on a real Windows machine yet ("spike"). When you've tried it, note which route worked here, and ask an agent to make it the permanent `build-nvencc.ps1`.

## 4. Package a portable folder

Back in the UCRT64 shell:

```bash
scripts/windows/package.sh
```

`out\ucrt64\dist\` now holds:

- `mpv.exe`, `ffmpeg.exe`, `ffprobe.exe`, NVEncC (if you built it)
- every DLL they need
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
| libplacebo | Vulkan, D3D11, OpenGL, shaderc, lcms2, libdovi |
| FFmpeg | shared; GPL + nonfree; libplacebo, Vulkan, NVENC/NVDEC/CUVID, CUDA filters (via clang), D3D11VA, DXVA2, QSV (libvpl), AMF, libass, dav1d, x264, x265, lcms2 |
| mpv | libmpv; Vulkan, D3D11, ANGLE, D3D hwaccel, AMF, Lua, libarchive, Blu-ray, rubberband |
| NVEncC | Visual Studio `RelStatic` x64, using the FFmpeg above |
