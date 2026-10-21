# mpv (FarisR99 fork): agent guide

The source of truth for this doc is `agents/mpv/AGENTS.md` in the MediaStack superrepo. For stack-wide rules, see the superrepo's root `AGENTS.md`.

- **Repo:** github.com/FarisR99/mpv. Tracked branch **`master`**, which is the fork itself, so changes are committed straight to it. Remote `upstream` is mpv-player/mpv. Upstream comes in by merge (the fork's history already has `Merge remote-tracking branch 'upstream/master'` commits).
- **Role in the stack:** a player, and also an **encoder**: `--vf=gpu` renders with libplacebo, then `vo_lavc` encodes with FFmpeg (NVENC/QSV). It links the stack's FFmpeg (≥ libavcodec 60.31) and libplacebo (≥ 7.360.1). Vulkan is **required** in this fork.

## Build

- Inside the stack: `scripts/windows/build.sh mpv` (UCRT64) or the Docker `mpv` stage. Options are in `scripts/common/build-mpv.sh`.
- Standalone, against the stack prefix: `PKG_CONFIG_PATH=<prefix>/lib/pkgconfig meson setup build && meson compile -C build`.
- The fork's own `Dockerfile` and `ci/` predate MediaStack. The superrepo's Docker build replaces that Dockerfile; leave it alone unless the user asks.

## Conventions

- C style per `DOCS/contribute.md`: 4 spaces, `talloc`, `MP_*` logging, no new global state.
- Commit subject `area: summary` (`ci/lint-commit-msg.py`). Fork-only agent commits add the `AI: ` prefix: `AI: vf_gpu: ...`.
- A user-visible option change needs `DOCS/man/*.rst`, plus an entry in `DOCS/interface-changes/` (one file per change) when it alters an interface.
- Say in the commit body what was compiled and what was run. The existing fork commits do this ("Syntax-checked ... for the Windows target; not yet run on Windows").

## Key files for our customisations

| Area | Files |
|---|---|
| GPU filter (render with the VO renderer inside the filter chain) | `video/filter/vf_gpu.c`, `vf_gpu.h`, `vf_gpu_vulkan.c`, `vf_gpu_d3d11.c`, `vf_gpu_angle.c`, `vf_gpu_egl.c`, `vf_gpu_ngx.c` (TrueHDR) |
| Encoder output / hw frame negotiation | `video/out/vo_lavc.c`, `common/encode_lavc.c` |
| libplacebo RA glue | `video/out/placebo/ra_pl.c`, `ra_pl.h` |
| OpenGL readback | `video/out/opengl/` |
| Build gating | `meson.build` (vf_gpu sources around the `vf_gpu*` lines), `meson.options` |
| Docs | `DOCS/man/vf.rst` (`gpu=` section) |

## Customisations on this branch

Fork-only commits (`git log --oneline upstream/master..master --no-merges` lists them):

- **vf_gpu backends:** `vf_gpu_vulkan` (uses `--vulkan-device`, allows software Vulkan devices), `vf_gpu_angle` and `vf_gpu_d3d11` (Windows). libplacebo frame dropping is disabled explicitly. D3D11 scaling is skipped at scale 1. The vf=gpu warning is hidden.
- **Hardware output for encoding:**
  - `hw-output=<auto|yes|no>`: D3D11 or Vulkan frames go straight to the encoder; auto turns it on for encoders that accept them.
  - Vulkan (`vf_gpu_vulkan.c` `get_hw_frame`/`end_hw_frame`): FFmpeg Vulkan frames on libplacebo's own device, handed to libplacebo and back with the frame's timeline semaphore, like `hwdec_vulkan`. The FFmpeg device's `free` callback owns the `mpvk_ctx`, so encoders can outlive the filter. Two layouts (`offscreen_ctx.num_hw_layouts`): multi-planar for `*_vulkan` encoders, one image per plane (`AV_VK_FRAME_FLAG_DISABLE_MULTIPLANE`) for CUDA. `vo_lavc` copies Vulkan → CUDA for NVENC (`transfer_frames`). BGRA renders through a `B8G8R8A8` view, because FFmpeg stores BGRA in `R8G8B8A8` images. `mppl_create_vulkan` requests video encode extensions and queues.
  - `hw-format=<auto|nv12|p010|bgra>`: GPU NV12/P010 conversion with BT.709 (BT.2020 for BT.2020 primaries), limited range and left-sited chroma.
  - Frames are flushed instead of finished.
  - D3D11 frames are mapped to QSV encoders.
  - NVENC RGB input is tagged BT.601.
  - Supported hw frames are preserved during encoder negotiation.
  - HDR encodes: `reconfig2` copies mastering display / content light level side data (from `pl_avframe_set_color` on the first frame's params) into `encoder->decoded_side_data`, which hevc_nvenc/av1_nvenc/libx265 need at open time to write HDR10 SEI/OBUs. Frames already carried it (`mp_image_to_av_frame`).
- **Robustness:**
  - persistent libplacebo shader cache (`vf_gpu_shader.cache`)
  - D3D11/ANGLE device options honoured; `gpu-debug` honoured for EGL
  - context binding and teardown fixes; subtitle state restored on teardown
  - software input format negotiation
  - framebuffer readback without `glReadBuffer`
  - `ra_pl` clears without blit support
- **Faster software readback:** `vf_gpu` downloads software output frames asynchronously, when the GPU supports downloading into buffers. It renders into a ring of targets, downloads each into a persistent buffer, and reads it back only after up to two later frames have been submitted, so rendering overlaps the download.
- **NV12 software output:** `sw-format=<auto|nv12|p010|rgb>` (`DOCS/man/vf.rst`). With async downloads, the GPU converts to NV12, as it does for NV12 hw frames, and both planes are downloaded: 1.5 instead of 4 bytes per pixel, and no BT.601 conversion in NVENC. auto picks NV12 when the encoder accepts it. `p010` is the 10-bit form.
- **10-bit 4:4:4 output:** `hw-format=yuv444p10` / `sw-format=yuv444p10` (`IMGFMT_YUV444P10/16` in `vf_gpu.h`, generic `IMGFMT_AVPIXFMT_START + AV_PIX_FMT_*`). Software: yuv444p10 (LSB-aligned); Vulkan hw: yuv444p16 MSB-aligned (bit_shift 6, like P010), which hevc_nvenc encodes as 10-bit 4:4:4. `render_yuv` adds a third plane and skips chroma siting; `init_slot`/`get_hw_frame` make all planes full size. D3D11 has no 4:4:4 frames (falls back to software). Verified bit-identical for every existing format.
- **RTX Video TrueHDR:** `truehdr=yes` plus `truehdr-contrast/-saturation/-middle-gray/-max-luma` (`vf_gpu_ngx.c`, meson feature `vf-gpu-ngx`: Windows + Vulkan + cuda-interop). gl_video renders into an RGBA8 texture exported to CUDA; NVEncNVSDKNGX.dll (loaded at runtime, needs nvngx_truehdr.dll and cudart64_12.dll beside mpv.exe; the superrepo's package.sh bundles all three) writes RGBA16F linear light (1.0 = 100 nits, verified against NVEncC to 51 dB) into a second shared texture; `render_yuv` converts it to BT.2020 PQ P010 via a `color_adjustment.contrast` scale. Vulkan↔CUDA sync uses timeline semaphores (hold/release with `VK_QUEUE_FAMILY_EXTERNAL`), as `hwdec_cuda_vk.c` does. Output is always P010; hw-format/sw-format must be unset. FreeLibrary on destroy resets the DLL's once-per-process NGX init. HDR10 metadata: `truehdr_color` sets BT.2020 mastering primaries, min 0.0001 and max/MaxCLL = max-luma. **Never mention NVEncC in mpv's own docs, messages or comments.**
- **`vf=lavfi` `hwdevice=<type>`** (`filters/f_lavfi.c`, also lavfi-bridge): creates an AVHWDeviceContext and sets it on every filter *before* init. `precreate_graph` does parse → `create_filters` → set device → `avfilter_graph_segment_apply` (create is idempotent; apply keeps FFmpeg's error messages) instead of `avfilter_graph_parse2`, which runs the same steps (hwupload's init needs the device; the hwdec path sets it after parsing, too late). With it, `--vf=gpu=api=vulkan,lavfi=[hwupload,fruc_cuda]:hwdevice=cuda` hands vf_gpu's Vulkan frames (CUDA layout, chosen because vf_gpu queries the *encoder*, not the next filter) to CUDA; the encoder then gets CUDA frames. vf_gpu has no RGBA hw format; for `truehdr_cuda` (rgba) use `hw-format=bgra` and `scale_cuda=format=rgba` before it (GPU only, 78.9 fps vs 60.3 for `hw-output=no:sw-format=rgb`). Tested: plain graphs, `o=`, bridge, `--lavfi-complex`, errors. Untested: playback with `--hwdec`, audio graphs.
- **Auto device for hardware filters by name** (`mp_lavfi_create_auto_filter`, used by `user_filters.c` for `--vf=<ffmpeg filter>`): if the name's suffix after the last `_` is an FFmpeg device type (`av_hwdevice_find_type_by_name`), `setup_auto_hw` reuses the hwdec device of that type or creates one (fails with "needs a <type> device"), and the direct-filter graph gets an `hwupload` in front. Name-based because filter pixel formats aren't public API. Explicit `lavfi`/`lavfi-bridge` don't do this. `fruc_vulkan` after vf_gpu fails: it uses the frames' Vulkan device (vf_gpu's), which has no optical flow queues.
- **Upstreamable fixes:** `vf_gpu_vulkan` no longer crashes when Vulkan context creation fails (the destructor ran with `priv` unset). Upstream mpv has the same bug.
- **Repo/CI:** Vulkan is a required dependency. macOS/FreeBSD/OpenBSD CI is removed, and MSYS2 builds are uploaded. Local build scripts are gitignored.

When you resolve merge conflicts, keep these behaviours. Add new fork features to this list (and to `docs/customisations.md`).
