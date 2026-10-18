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
| GPU filter (render with the VO renderer inside the filter chain) | `video/filter/vf_gpu.c`, `vf_gpu.h`, `vf_gpu_vulkan.c`, `vf_gpu_d3d11.c`, `vf_gpu_angle.c`, `vf_gpu_egl.c` |
| Encoder output / hw frame negotiation | `video/out/vo_lavc.c`, `common/encode_lavc.c` |
| libplacebo RA glue | `video/out/placebo/ra_pl.c`, `ra_pl.h` |
| OpenGL readback | `video/out/opengl/` |
| Build gating | `meson.build` (vf_gpu sources around the `vf_gpu*` lines), `meson.options` |
| Docs | `DOCS/man/vf.rst` (`gpu=` section) |

## Customisations on this branch

Fork-only commits (`git log --oneline upstream/master..master --no-merges` lists them):

- **vf_gpu backends:** `vf_gpu_vulkan` (uses `--vulkan-device`, allows software Vulkan devices), `vf_gpu_angle` and `vf_gpu_d3d11` (Windows). libplacebo frame dropping is disabled explicitly. D3D11 scaling is skipped at scale 1. The vf=gpu warning is hidden.
- **Hardware output for encoding:**
  - `hw-output=<auto|yes|no>`: D3D11 frames go straight to the encoder; auto turns it on for encoders that accept them.
  - `hw-format=<auto|nv12|bgra>`: GPU NV12 conversion with BT.709 (BT.2020 for BT.2020 primaries), limited range and left-sited chroma.
  - Frames are flushed instead of finished.
  - D3D11 frames are mapped to QSV encoders.
  - NVENC RGB input is tagged BT.601.
  - Supported hw frames are preserved during encoder negotiation.
- **Robustness:**
  - persistent libplacebo shader cache (`vf_gpu_shader.cache`)
  - D3D11/ANGLE device options honoured; `gpu-debug` honoured for EGL
  - context binding and teardown fixes; subtitle state restored on teardown
  - software input format negotiation
  - framebuffer readback without `glReadBuffer`
  - `ra_pl` clears without blit support
- **Faster software readback:** `vf_gpu` downloads software output frames asynchronously, when the GPU supports downloading into buffers. It renders into a ring of targets, downloads each into a persistent buffer, and reads it back only after up to two later frames have been submitted, so rendering overlaps the download.
- **Upstreamable fixes:** `vf_gpu_vulkan` no longer crashes when Vulkan context creation fails (the destructor ran with `priv` unset). Upstream mpv has the same bug.
- **Repo/CI:** Vulkan is a required dependency. macOS/FreeBSD/OpenBSD CI is removed, and MSYS2 builds are uploaded. Local build scripts are gitignored.

When you resolve merge conflicts, keep these behaviours. Add new fork features to this list (and to `docs/customisations.md`).
