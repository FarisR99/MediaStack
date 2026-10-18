# Linux Docker build (agent notes)

Human version: `docs/building-linux.md`.

## Shape

- `scripts/linux/export.sh [docker args]` does three things:
  1. writes `out/linux/meta/BUILDINFO.txt`
  2. runs `docker build -f scripts/linux/Dockerfile --build-context meta=out/linux/meta --target export --output type=local,dest=out/linux/stage .`
  3. tars the result to `out/linux/mediastack-<sha>[-dirty].tar.zst`, with a `mediastack-latest.tar.zst` symlink
- Versions (`CUDA_VERSION`, `UBUNTU_VERSION`, `MESON_VERSION`, `VULKAN_SDK_VERSION`, `CARGO_C_VERSION`, `LINUX_PREFIX`) come from `stack.conf` and are passed as `--build-arg`. Change them only in `stack.conf`; the Dockerfile defaults are fallbacks.
- **Context:** the superrepo working tree, *including uncommitted changes*. `scripts/linux/Dockerfile.dockerignore` drops `.git`, `out`, the docs and the agent docs. With no `.git` in the image, FFmpeg's version comes from `FFMPEG_REVISION` (`git describe --match N`).
- **Base image:** `nvidia/cuda:<CUDA_VERSION>-devel-ubuntu22.04`. 22.04 keeps glibc old enough for 22.04 hosts. Ubuntu packages that are too old get replaced:
  - pip `meson`
  - LunarG Vulkan SDK in `/opt/vulkan-sdk` (headers ≥ 1.4.317 for FFmpeg, `glslc`, shaderc for libplacebo)
  - rustup + prebuilt cargo-c (libdovi, NVEnc's bundled libhdr10plus)
- **Stages:** one `COPY <project>` + `RUN build-<project>.sh` per project in build order, so editing mpv rebuilds only mpv and NVEncC. Build dirs (`/build/<p>`) and ccache are BuildKit cache mounts, so rebuilds are incremental. Use `--no-cache` only when you suspect a stale cache.
- `scripts/linux/finalize.sh` runs last. It:
  - sets RPATH `$ORIGIN/../lib` (bins) and `$ORIGIN` (libs) with patchelf
  - bundles shared libs that no Ubuntu package owns (the Vulkan SDK's `libshaderc_shared`, CUDA runtime pieces)
  - writes `share/mediastack/runtime-apt.txt` (the dpkg owners of the other deps) and `BUILDINFO.txt`
  - never bundles driver libs (`libcuda`, `libnvcuvid`, `libnvidia-*`)
- The export stage is `FROM scratch` and contains only `/opt/mediastack`.

## Host install

`sudo scripts/linux/install-host.sh [tarball]`:
1. extracts to `/opt/mediastack.new` and swaps it in
2. `apt-get install`s the packages in `runtime-apt.txt`
3. writes `/etc/ld.so.conf.d/mediastack.conf`, then runs `ldconfig`
4. writes `/etc/profile.d/mediastack.sh` (PATH)

`uninstall-host.sh` reverses all of that.

**Never run install/uninstall without the user's go-ahead.** They need sudo and change the host.

## Build options that differ from Windows

- FFmpeg: `--enable-cuda-nvcc` (that's the nonfree part) using the container's nvcc. No lcms2, because 22.04's is older than FFmpeg's ≥ 2.13 minimum. No d3d11va/libvpl/amf.
- libplacebo: `d3d11=disabled`. libdovi comes from `scripts/linux/build-libdovi.sh` (tag `LIBDOVI_TAG`).
- mpv: x11, egl, gl, alsa, pulse, cuda-hwaccel/interop. Wayland is off, because 22.04's protocols are too old.
- NVEncC: meson with `enable_libplacebo=enabled`, `enable_vulkan=enabled`. VapourSynth/AviSynth/ONNX/VMAF/vship are off, which also stops their configure-time downloads.

## Iterating

- Faster loop for one project: after one full export, the image cache makes `export.sh` cheap for later edits, since only changed stages rerun.
- Debug a failing stage: `docker build -f scripts/linux/Dockerfile --build-context meta=out/linux/meta --target builder --progress=plain .`, or add `RUN false` temporarily and inspect the cache. Logs show the failing `#NN` step.
