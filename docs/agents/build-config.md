# Build configuration (agent notes)

Human version: the "What gets built" sections of `docs/building-windows.md` and `docs/building-linux.md`, and `docs/licensing.md`.

## Where flags live

| Project | File | Notes |
|---|---|---|
| all | `scripts/common/env.sh` | `MS_TARGET`, `MS_PREFIX`, `MS_BUILD_ROOT`, `MS_SRC_ROOT`, `MS_JOBS`, `MS_BUILDTYPE`. Puts the prefix first in `PKG_CONFIG_PATH`/`PATH`. `meson_build` helper. |
| nv-codec-headers | `scripts/common/build-nv-codec-headers.sh` | `make PREFIX=... install` (in-tree; `ffnvcodec.pc` is gitignored upstream) |
| libdovi | `scripts/linux/build-libdovi.sh` | Linux only (Windows uses pacman's) |
| libvmaf | `scripts/common/build-vmaf.sh` | Both targets, `VMAF_VERSION` in `stack.conf`. `build-ffmpeg.sh` runs it when `<prefix>/share/mediastack/vmaf-version` doesn't match (the `.pc` version lags the tag). Docker runs it as its own step. Needs `xxd` (MSYS2 `vim`, apt `xxd`): without it libvmaf silently drops its built-in models, as MSYS2's own package does. |
| libplacebo | `scripts/common/build-libplacebo.sh` | `case "$MS_TARGET"` for per-platform options |
| FFmpeg | `scripts/common/build-ffmpeg.sh` | reconfigures only when the args, `configure` or its component lists change (stamp file in the build dir) |
| mpv | `scripts/common/build-mpv.sh` | Windows set mirrors the fork's `ci/build-msys2.sh` |
| NVEncC | `scripts/common/build-nvenc.sh` (Linux), `scripts/windows/nvencc-spike.ps1` (Windows) | |

Per-platform differences go in the `case "$MS_TARGET"` block of the same script. Don't fork the scripts per platform.

## FFmpeg policy

- `--enable-gpl --enable-version3 --enable-nonfree`, shared libs, no static.
- Always on: `libplacebo vulkan ffnvcodec nvenc nvdec cuvid libass libdav1d libx264 libx265 libvmaf`.
- Linux: `cuda-nvcc` (nonfree) when nvcc exists.
- Windows: `d3d11va dxva2 libvpl amf cuda-llvm lcms2`.
- `--enable-libnpp` was removed upstream. Don't add it back.
- Vulkan shaders are compiled at build time by `glslc`/`glslang` (no `--enable-libshaderc` any more). They need Vulkan headers ≥ 1.4.317.
- Before adding an external library, check that it exists on **both** targets (an Ubuntu 22.04 package, or a source build in the Dockerfile; and an MSYS2 UCRT64 package added to `deps.sh`). Otherwise gate it in the platform `case`.

## Changing a pinned tool version

Edit `stack.conf` only. The Dockerfile receives it as `--build-arg`. Then run a full `scripts/linux/export.sh`. When `CUDA_VERSION` changes, check NVEnc's SM list (`nvenc/meson.build`) and the minimum host driver.
