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

- `AI: libplacebo: load the libplacebo API version compiled against` (`NVEncCore/rgy_libplacebo.cpp`): it also tries `libplacebo-<PL_API_VER>.dll` / `libplacebo.so.<PL_API_VER>` and `pl_log_create_<PL_API_VER>`, from the headers it was built with. Upstream only knew APIs ≤ 360; the stack's libplacebo is 7.377+. Keep this through merges. If upstream adds its own equivalent, drop ours in favour of theirs.

Add every new fork commit here (and to the superrepo's `docs/customisations.md`).
