# NVEnc / NVEncC (FarisR99 fork): agent guide

The source of truth for this doc is `agents/nvenc/AGENTS.md` in the MediaStack superrepo. For stack-wide rules, see the superrepo's root `AGENTS.md`.

**Upstream also ships its own `CLAUDE.md` and `AGENTS.md` (Japanese).** They describe NVEnc's internal structure. Read them for that, and never edit them for stack purposes. The headline points:
- `rgy_*` files are shared with QSVEnc/VCEEnc/rkmppenc, so keep them encoder-neutral and switch behaviour with `ENCODER_NVENC` etc. from `rgy_version.h`.
- `NVEncCore` holds the implementation; `NVEncC` is the CLI.
- When you add an option, update `NVEncC_Options*.md` and the help text in `rgy_cmd.cpp`.

- **Repo:** github.com/FarisR99/NVEnc. Tracked branch **`mediastack`**, cut from upstream `master`. Remote `upstream` is rigaya/NVEnc. Upstream comes in by merge: `scripts/merge-upstream.sh nvenc`.
- **Nested submodules:** `dtl`, `cppcodec`, `build_pkg`.
- **Role in the stack:** a standalone NVENC encoder (`nvencc` on Linux, `NVEncC64.exe` on Windows). It uses the stack's FFmpeg for demux/decode/audio, and the stack's libplacebo, loaded at runtime, for `--vpp-libplacebo-*`.

## Build

- **Linux:** meson, in the Docker `nvenc` stage (`scripts/common/build-nvenc.sh`). It needs CUDA (`CUDA_PATH`); the SM targets are derived from the nvcc version in `meson.build`. libdovi comes from the prefix. libhdr10plus is fetched and built by NVEnc's own `build_libhdr10plus.sh` (needs network and cargo). Optional readers and metrics are disabled, which also prevents their configure-time downloads.
- **Windows:** MSVC only (`NVEnc.sln`, config `RelStatic|x64`, target `NVEncC`). FFmpeg comes in through `ffmpeg_lgpl/` (gitignored). See the superrepo's `docs/agents/build-windows.md` and `scripts/windows/nvencc-spike.ps1`.
- Files are **CRLF with a UTF-8 BOM**, and `.gitattributes` has `* -text`. Preserve both when editing: write with CRLF and keep the BOM. Never let a tool normalise line endings across a whole file.

## Stack-specific facts

- libplacebo loader: `NVEncCore/rgy_libplacebo.cpp`. It tries the library by soname (= libplacebo API version) and the `pl_log_create_<api>` symbol.
- FFmpeg DLL names on Windows: `AVCODEC_DLL_NAME` in `NVEncCore/rgy_avutil.h` (`avcodec-63.dll`, ...). **Update them when FFmpeg bumps a major version.**
- libass is loaded at runtime as `libass-9.dll` on Windows (`rgy_libass.cpp`).

## Customisations on this branch

- `AI: libplacebo: load the libplacebo API version compiled against` (`NVEncCore/rgy_libplacebo.cpp`): it also tries `libplacebo-<PL_API_VER>.dll` / `libplacebo.so.<PL_API_VER>` and `pl_log_create_<PL_API_VER>`, from the headers it was built with. Upstream only knew APIs ≤ 360; the stack's libplacebo is 7.388+. Keep this through merges. If upstream adds its own equivalent, drop ours in favour of theirs.
- `AI: libplacebo: handle pl_render_params.transparency in the legacy shim` (`NVEncCore/rgy_libplacebo.cpp`): the shim converts the current `pl_render_params` to the API 338/349/351 layouts. Upstream API 381 added `pl_render_params.transparency`; the conversions drop it (and `blur_radius` for 349/351) and the threshold is now 381. If libplacebo adds another `pl_render_params` field, update the shim and the `PLRenderBackground338` static assert.

- `AI: libplacebo: map D3D11 textures once per frame on the filter stream` (`NVEncCore/NVEncFilterD3D11.*`, `NVEncFilterLibplacebo.*`, `run_filter`): on D3D11, all planes are mapped/unmapped in one `cudaGraphicsMapResources` call on the filter's (`cudaStreamNonBlocking`) stream instead of per plane on stream 0. The interop textures are wrapped into `pl_tex` once (`m_plTexIn`/`m_plTexOut`, `wrapTextures`) instead of every frame. The Vulkan path is untouched. On a merge conflict in `run_filter`, keep the D3D11 branches mapping with `stream`.
- `AI: libplacebo: persistent shader cache` (`rgy_libplacebo.*`, `NVEncFilterLibplacebo.*`): `pl_cache` with `pl_cache_get_file`/`pl_cache_set_file` in `%LOCALAPPDATA%\NVEncC\libplacebo_cache\` or `$XDG_CACHE_HOME`/`~/.cache` `nvencc/libplacebo_cache/`. The loader treats the cache functions as optional (API >= 351).
- Both are built and benchmarked (2026-10-19, RTX 5090, Route A, CUDA 13.0), although their commit bodies say otherwise. Anime4K ModeA 1080p → 4K HEVC, `--cqp 22 --output-depth 10`, vs rigaya's NVEncC 9.38 release: P5 80 → 98 fps; P5 `--split-enc forced_3` 137 → 143 cold cache, 206 warm; P1 forced_3 143 → 167 cold; 90 s clip, P1 forced_3, warm: 218 → 314 fps. Output sizes match the release to within 0.1%. The cache saves roughly 1.2 s of shader compilation per run; the rest is the interop change. To compare, rerun with the cache folder deleted.
- `AI: ngx-truehdr: run FRUC first and tag HDR10 output` (`NVEncCore/NVEncCore.cpp`: the fixed `filterPipeline` list, `InitFilters` VUI, `InitInput` HDR SEI): with `--vpp-ngx-truehdr` + `--vpp-fruc`, `CL_FRUC` is pushed before `NGX_TRUEHDR` (FRUC is 8-bit; after TrueHDR it degraded the HDR output to 52 dB, now bit-exact). With TrueHDR, unset `--colormatrix/--colorprim/--transfer` become `auto` (the encoder only applies the filter chain's VUI to auto values, so TrueHDR's BT.2020/PQ was dropped), and empty `--max-cll`/`--master-display` default to `maxluminance` with BT.2020 primaries `G(8500,39850)B(6550,2300)R(35400,14600)WP(15635,16450)`. Documented in `NVEncC_Options.en.md` only. On merges, keep the `frucBeforeTrueHDR` lines if upstream reorders the pipeline list.

- `AI: maa: separable resize and tiled rotations` (`NVEncCore/NVEncFilter.h` `NVEncFilterParamResize::separable`, `NVEncFilterResize.cu` `kernel_resize_sep_h/_v` + `resize_frame_separable`, `NVEncFilterMaa.cu`): `--vpp-maa`'s two spline36 supersampling resizes run as a horizontal pass into a float buffer (`m_separableTmp`) then a vertical pass, instead of `kernel_resize`'s full 2D window (196 vs 28 taps at 2x). Same filter: weights are wx*wy normalised by (Σwx)(Σwy); output matches the old build to 90-110 dB (truncation flips ±1 at a few pixels). Only maa sets `separable`, so `--vpp-resize` is unchanged; it could use it too. `kernel_maa_fturn_left/right` use a 32x32 shared tile (coalesced reads and writes). RTX 5090: maa kernels 4.3 -> 2.2 ms/frame at 4K; Anime4K ultra 1080p->4K + maa 104 -> 131 fps. A shared-tile rewrite of `kernel_maa_sangnom_smooth_3d` was slower than upstream's (680 vs 373 us) and isn't used; smooth is now the largest maa kernel. On merges, keep the `separable` flag and the maa `prmUp/prmDn->separable = true` lines.

Add every new fork commit here (and to the superrepo's `docs/customisations.md`).
