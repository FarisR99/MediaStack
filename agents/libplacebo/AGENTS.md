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

None yet: `mediastack` == upstream master at the time it was branched (API 7.377). List every fork commit here as it lands (and in the superrepo's `docs/customisations.md`).
