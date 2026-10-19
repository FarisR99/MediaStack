# Building on Linux

On Linux the whole stack is built inside a Docker container (Ubuntu 22.04 with a current CUDA). The result is a single folder, `/opt/mediastack`, which you install on any Ubuntu 22.04+ machine, WSL included.

Building in a container means your host needs nothing installed except Docker, and every host gets identical binaries.

## Build

From the repo root:

```bash
scripts/linux/export.sh
```

The first build downloads the CUDA image, the Vulkan SDK and Rust, then compiles everything; expect a while. Later builds are much faster:

- Docker reuses everything up to the first project that changed. Editing mpv rebuilds only mpv and NVEncC.
- Compiler caches persist between builds.

The result is `out/linux/mediastack-<commit>.tar.zst`, plus a `mediastack-latest.tar.zst` link to the newest one. The build uses your working tree **as it is**, including uncommitted changes; in that case the file name ends in `-dirty`.

Useful options (any `docker build` flag is passed through):

```bash
scripts/linux/export.sh --progress=plain   # full build log
scripts/linux/export.sh --no-cache         # rebuild everything from scratch
```

## Install on a host

On the machine that should run it (this can be the build machine):

```bash
sudo scripts/linux/install-host.sh                       # newest build
sudo scripts/linux/install-host.sh path/to/mediastack-abc1234.tar.zst
```

This:

- replaces `/opt/mediastack` with the new build
- installs the few Ubuntu runtime packages it needs (libass, x264, ...)
- registers `/opt/mediastack/lib` with the system linker (`ldconfig`), so other programs can use the libraries too
- adds `/opt/mediastack/bin` to everyone's `PATH`

Open a new terminal afterwards, then check what's installed:

```bash
cat /opt/mediastack/BUILDINFO.txt
mpv --version
ffmpeg -hide_banner -version
nvencc --version
```

To install on another machine, copy the `.tar.zst` file and the `scripts/` folder over (or clone the repo there), then run the same command.

### Updating and uninstalling

- **Update:** build again, then run `install-host.sh` again. The previous version is replaced.
- **Uninstall:** `sudo scripts/linux/uninstall-host.sh`. It removes `/opt/mediastack` and the linker/PATH entries; the Ubuntu runtime packages stay installed.

## WSL notes

- NVENC, NVDEC and CUDA work in WSL2 through the Windows NVIDIA driver; nothing extra to install inside WSL.
- WSL has **no NVIDIA Vulkan driver**. Vulkan falls back to a slower software (lavapipe) or D3D12-translated (dzn) device. mpv's `--vf=gpu=api=vulkan` and libplacebo filters therefore work, but slowly. For heavy libplacebo work, use Windows natively or a real Linux machine.

## What gets built

| Project | Notable options on Linux |
|---|---|
| dav1d, libdovi, libvmaf | built from source; Ubuntu 22.04's versions are too old or missing |
| libplacebo | Vulkan, OpenGL, shaderc, lcms2, libdovi |
| FFmpeg | shared; GPL + nonfree; libplacebo, Vulkan, NVENC/NVDEC/CUVID, CUDA filters (nvcc), libass, dav1d, x264, x265, libvmaf |
| mpv | libmpv; Vulkan, EGL/OpenGL, X11, CUDA hwaccel, ALSA, PulseAudio, Lua |
| NVEncC | libplacebo filters (Vulkan), libass, libdovi; no VapourSynth/AviSynth readers |

Versions of the build tools (CUDA, Vulkan SDK, meson, ...) are set in `stack.conf`.
