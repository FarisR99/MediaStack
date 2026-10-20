# FFmpeg (FarisR99 fork): agent guide

The source of truth for this doc is `agents/ffmpeg/AGENTS.md` in the MediaStack superrepo. For stack-wide rules, see the superrepo's root `AGENTS.md`.

- **Repo:** github.com/FarisR99/FFmpeg. Tracked branch **`mediastack`**, cut from upstream `master`. Remote `upstream` is FFmpeg/FFmpeg (a GitHub mirror of code.ffmpeg.org). Upstream comes in by merge: `scripts/merge-upstream.sh ffmpeg`.
- **Role in the stack:**
  - it supplies libav* to mpv (`vo_lavc` encoding, decoding) and to NVEncC (demux/decode/audio)
  - the `ffmpeg`/`ffprobe` CLIs
  - `vf_libplacebo` (links the stack's libplacebo)
  - NVENC/NVDEC/CUVID via nv-codec-headers

## Build

- Inside the stack: `scripts/windows/build.sh ffmpeg` or the Docker `ffmpeg` stage. Flags are in `scripts/common/build-ffmpeg.sh`; policy is in the superrepo's `docs/agents/build-config.md`.
- The build is out-of-tree (`out/<target>/build/ffmpeg`). Never run `./configure` inside `ffmpeg/`: an in-tree configure breaks later out-of-tree builds. If it happens, clean up with `git -C ffmpeg clean -xdf` after checking what it would delete.
- Reconfiguring happens automatically when the flag list changes, or when `configure` or a component list it reads (`allformats.c`, `allcodecs.c`, `allfilters.c`, …) changes, e.g. after an upstream merge. To force it, delete `out/<target>/build/ffmpeg/.mediastack-configure-args`.

## Conventions

- Upstream style (`doc/developer.texi`): 4 spaces, K&R braces, no C99 `//` comments in new code where upstream avoids them. Use `av_log` with a context, and always check allocation failures.
- Commit subject `lib/area: summary`, e.g. `avcodec/nvenc: ...`, `avfilter/vf_libplacebo: ...`. Agent commits prefix it with `AI: `.
- API changes (rare in a fork, but possible) need `doc/APIchanges` plus a minor bump in `lib*/version.h`. Prefer not to change public API at all: it ripples into mpv and NVEncC.
- **Major version bumps from upstream** (`lib*/version_major.h`) change the DLL names NVEncC expects on Windows (`nvenc/NVEncCore/rgy_avutil.h`, `AVCODEC_DLL_NAME`). Check this after every upstream merge.

## Key files

| Area | Files |
|---|---|
| NVENC encoders | `libavcodec/nvenc.c`, `nvenc.h`, `nvenc_*.c` |
| NVDEC/CUVID | `libavcodec/nvdec*.c`, `cuviddec.c` |
| libplacebo filter | `libavfilter/vf_libplacebo.c` |
| Vulkan hwcontext / filters | `libavutil/hwcontext_vulkan.c`, `libavfilter/vulkan*`, `*_vulkan.c` |
| D3D11 / QSV | `libavutil/hwcontext_d3d11va.c`, `hwcontext_qsv.c`, `libavcodec/qsv*.c` |
| Build system | `configure`, `ffbuild/` |

## Customisations on this branch

List every fork commit here as it lands (and in the superrepo's `docs/customisations.md`). `git log --oneline --no-merges upstream/master..mediastack` lists them.

- **Vulkan ↔ CUDA interop on NVIDIA** (`libavutil/hwcontext_vulkan.c`, `vulkan_frames_init`): on devices with `disable_multiplane` (set by deriving from CUDA, or the device option), and for frames with `AV_VK_FRAME_FLAG_DISABLE_MULTIPLANE` (mpv's `vf_gpu` Vulkan hardware output for NVENC), frames are created without `VK_IMAGE_USAGE_HOST_TRANSFER_BIT_EXT`. CUDA can't map images with that usage (`cuExternalMemoryGetMappedMipmappedArray` → `CUDA_ERROR_INVALID_VALUE`), which broke `hwupload` between `vulkan` and `cuda` frames in both directions. This enables `vf_libplacebo` → `hevc_nvenc` without a CPU round trip. If an upstream merge rewrites the host-transfer usage logic, keep `!p->disable_multiplane` and the frame-flag check in the condition, then retest with the recipe in `docs/agents/testing.md`.
