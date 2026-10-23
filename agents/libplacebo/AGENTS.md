# libplacebo (FarisR99 fork): agent guide

The source of truth for this doc is `agents/libplacebo/AGENTS.md` in the MediaStack superrepo. For stack-wide rules, see the superrepo's root `AGENTS.md`.

- **Repo:** github.com/FarisR99/libplacebo. Tracked branch **`mediastack`**, cut from upstream `master`. Remote `upstream` is haasn/libplacebo (a GitHub mirror of code.videolan.org/videolan/libplacebo). Upstream comes in by merge: `scripts/merge-upstream.sh libplacebo`.
- **Role in the stack:** the GPU renderer behind mpv's `--vf=gpu`/`--vo=gpu-next`, FFmpeg's `vf_libplacebo` and NVEncC's `--vpp-libplacebo-*`. Everything else in the stack depends on it, so changes here ripple the furthest.
- **Submodules:** `3rdparty/` (Vulkan-Headers, glad, jinja, markupsafe, fast_float). `setup.sh` initialises them recursively.

## Build

- Inside the stack: `scripts/windows/build.sh libplacebo` or the Docker `libplacebo` stage. Options are in `scripts/common/build-libplacebo.sh`: Vulkan, shaderc, lcms and libdovi everywhere, plus D3D11 on Windows (NVEncC's Windows filters use `pl_d3d11_*`).
- After changing libplacebo, rebuild **FFmpeg, mpv and NVEncC** too. FFmpeg and mpv link it; NVEncC compiles against its headers and loads it by soname.

## API/ABI versioning (important)

- The version is `7.<API>.<fix>`. The API number is the top key of the dictionary in `meson.build`. **Every API addition or change bumps it** with a one-line description, following the existing entries.
- The soname is the API number (`libplacebo.so.<API>`, `libplacebo-<API>.dll`). `pl_log_create` is a macro for `pl_log_create_<API>`.
- NVEncC loads `libplacebo-<PL_API_VER>.dll` / `libplacebo.so.<PL_API_VER>` (our nvenc fix) and looks up `pl_log_create_<PL_API_VER>`. Bumping the API here therefore needs an NVEncC rebuild, but no NVEncC code change.
- Avoid changing existing struct layouts or function signatures in a fork commit. Add new fields and functions behind a new API version, as upstream does.

## Conventions

- C11, 4 spaces, upstream naming (`pl_` prefix, `params` structs with `PL_*_DEFAULTS`). Public headers live in `src/include/libplacebo/`.
- Commit subject `area: summary` (`vulkan: ...`, `renderer: ...`, `shaders/colorspace: ...`). Agent commits prefix it with `AI: `.
- Tests: `meson setup build -Dtests=true && meson test -C build`. The stack build disables them.

## Key files

| Area | Files |
|---|---|
| Renderer | `src/renderer.c`, `src/include/libplacebo/renderer.h` |
| Colour / tone mapping | `src/colorspace.c`, `src/tone_mapping.c`, `src/gamut_mapping.c`, `src/shaders/colorspace.c` |
| Scaling / sampling | `src/shaders/sampling.c`, `src/filters.c` |
| User shaders (mpv .hook) | `src/shaders/custom_mpv.c` |
| Backends | `src/vulkan/`, `src/d3d11/`, `src/opengl/` |
| Dolby Vision | `src/shaders/dovi.c`, `src/include/libplacebo/utils/dolbyvision.h` |

## Customisations on this branch

List every fork commit here as it lands (and in the superrepo's `docs/customisations.md`). `git log --oneline --no-merges upstream/master..mediastack` lists them. One API addition so far: API 388 (`pl_mpv_user_shader_parse_params`). It was 381 until upstream took 381-387 (merge of 2026-10-23), and 378 before that until upstream took 378-380 (merge of 2026-10-22): **on an upstream merge that adds API versions, renumber ours to the next free number above upstream's** in `meson.build`. FFmpeg and mpv detect it with `#ifdef pl_mpv_user_shader_params`, not a version number, so they need no change; NVEncC must be rebuilt (DLL name).

- **Cheaper semaphore polls** (`src/vulkan/command.c` `vk_sync_poll`): zero-timeout polls read the timeline counter (`vkGetSemaphoreCounterValue`) instead of calling `vkWaitSemaphores`. On NVIDIA on Windows the wait costs 6-8 µs, and `vk_poll_commands(vk, 0)` runs several times per pass.
- **Per-pass submission only when the GPU would idle** (`src/vulkan/gpu_pass.c` end of `vk_pass_run`, `vk_cmds_busy()` in `command.c`): upstream submits after every pass. The fork keeps recording while the last submitted command is still executing. The descriptor-set slow path in `vk_pass_run` submits before blocking, because the sets may be held by unsubmitted passes. Together with the poll change this took Anime4K 1080p → 4K from about 188 to 233 fps in FFmpeg and from about 160 to 225 fps in mpv's Vulkan `hw-output`. If an upstream merge reworks submission or polling, keep both behaviours and re-measure (`docs/benchmarks.md`).
- **Half-precision user shaders (API 388)** (`src/shaders/custom_mpv.c`, `src/include/libplacebo/shaders/custom.h`): `pl_mpv_user_shader_parse_params()` with `pl_mpv_user_shader_params.half_precision`. Each pass declares `precision mediump float;` before the hook body, and `<tex>_tex`/`_gather` samples go through a per-pass `mediump vec4 f(mediump vec4)` helper (`sh_fresh(sh, "half")`), because the highp `scale` spec constant otherwise keeps all math on samples highp (without the helper: ~0% gain). Intel UHD 770: Anime4K +59% (Mode C) / +88% (Mode A) via FFmpeg, 64–65 dB from full precision; no gain on NVIDIA, so opt-in. `pl_mpv_user_shader_parse` is unchanged (calls it with NULL). If a merge changes `bind_pass_tex` or the hook body emission, keep both parts.
