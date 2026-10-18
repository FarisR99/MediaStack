# Troubleshooting (agent notes)

Human version: `docs/troubleshooting.md`. When you hit and fix a new failure, add it here, and to the human doc if a person could hit it too.

## Linux Docker build

| Symptom | Cause / fix |
|---|---|
| mpv: `Dependency "vulkan" not found` | The LunarG Linux SDK ships no loader or `vulkan.pc`, and 22.04's is too old. The Dockerfile builds the Khronos loader into `/opt/vulkan-loader` for build time. Keep that step in sync with `VULKAN_SDK_VERSION`. |
| `libplacebo built without linking against vkGetInstanceProcAddr` at runtime | libplacebo didn't find the loader at configure time. `build-libplacebo.sh` passes `-Dvk-proc-addr=enabled` so this fails loudly instead. |
| `ERROR: <lib> >= X not found using pkg-config` in FFmpeg configure | Ubuntu 22.04's package is too old. Either build it from source in a `scripts/linux/build-<lib>.sh` stage (as was done for dav1d and libdovi) or gate the flag to Windows (as was done for lcms2). `build-ffmpeg.sh` prints the tail of `config.log` on failure; read it. |
| Linker: `libX.so needed by libplacebo.so, not found` / undefined `shaderc_*` | Transitive dependency in the Vulkan SDK. `LD_LIBRARY_PATH=$VULKAN_SDK/lib` is set in the Dockerfile for this. Keep it. |
| `Unknown option "--enable-libshaderc"` | FFmpeg now compiles Vulkan shaders at build time with `glslc`. Don't pass that option. |
| mpv: `Feature shaderc cannot be disabled` | mpv's shaderc/spirv-cross are Windows-only (`win32-desktop`). Only enable them in the `ucrt64` case. |
| mpv: libdrm/wayland "found X but need Y" | Expected on 22.04. Those features stay off; don't force-enable them. |
| A stage keeps using stale build output | Build dirs are cache mounts. `scripts/linux/export.sh --no-cache` or `docker builder prune --filter type=exec.cachemount`. |
| NVEnc configure tries to download things | An optional feature isn't disabled. Check its `enable_*` option in `nvenc/meson.options` and disable it in `build-nvenc.sh`. |

## Runtime

| Symptom | Cause / fix |
|---|---|
| NVEncC: `--vpp-libplacebo-*` says libplacebo is required but not found | NVEncC was built against different libplacebo headers than the installed library, or our loader fix was lost in a merge (`agents/nvenc/AGENTS.md`). Rebuild NVEncC after every libplacebo change. |
| NVENC: "Driver does not support the required nvenc API version" | nv-codec-headers is newer than the host driver supports. Update the driver, or pin an older tag. |
| mpv segfaults in `vk_ctx_destroy` when Vulkan init fails | Fixed on the fork's `master` ("AI: vf_gpu_vulkan: don't crash when context creation fails"). It was an upstream bug: the destructor ran with `priv` unset. |
| NVEncC (Linux): `libplacebo-*: vulkan device not set` | No NVIDIA Vulkan device (WSL, or a container without the NVIDIA ICD). Expected; see `testing.md`. |
| WSL: Vulkan device is llvmpipe/lavapipe or dzn | There's no NVIDIA Vulkan ICD in WSL. This is expected and slow; CUDA/NVENC still work. |
| `error while loading shared libraries` on a host | `install-host.sh` wasn't run, or `runtime-apt.txt` missed a package. Check with `ldd /opt/mediastack/bin/<exe> \| grep 'not found'`, then fix the bundling logic in `scripts/linux/finalize.sh`. |

## Windows

| Symptom | Cause / fix |
|---|---|
| Scripts fail with `$'\r': command not found` | CRLF in a bash script. `.gitattributes` should prevent it; check `git ls-files --eol scripts/`. |
| mpv/ffmpeg pick up pacman's FFmpeg/libplacebo | `pacman -R mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-libplacebo`. The stack prefix is first on `PKG_CONFIG_PATH`, but stray DLLs on PATH can still win at runtime outside `dist/`. |
| NVEncC can't find `avcodec-NN.dll` | FFmpeg major version bump. Update `AVCODEC_DLL_NAME` in `nvenc/NVEncCore/rgy_avutil.h`. |
