# Anime4K shader presets

MediaStack builds four combined Anime4K shader files, `low.glsl`, `medium.glsl`, `high.glsl` and `ultra.glsl`, from the upstream shaders pinned in `stack.conf`. They are generated, not tracked: the preset manifest and upstream hash lock are committed, and the files are rebuilt from them.

| Preset | Chain, in order | Passes |
|---|---|---:|
| `low` | `Clamp_Highlights`, `Upscale_Denoise_CNN_x2_VL`, `AutoDownscalePre_x2`, `AutoDownscalePre_x4`, `Restore_CNN_M`, `Upscale_CNN_x2_M` | 40 |
| `medium` | `Clamp_Highlights`, `Restore_CNN_Soft_VL`, `Upscale_CNN_x2_VL`, `AutoDownscalePre_x2`, `AutoDownscalePre_x4`, `Restore_CNN_Soft_M`, `Upscale_CNN_x2_M` | 57 |
| `high` | `Clamp_Highlights`, `Restore_CNN_VL`, `Upscale_CNN_x2_VL`, `AutoDownscalePre_x2`, `AutoDownscalePre_x4`, `Upscale_CNN_x2_M` | 49 |
| `ultra` | `Clamp_Highlights`, `Restore_CNN_VL`, `Upscale_CNN_x2_VL`, `Restore_CNN_M`, `AutoDownscalePre_x2`, `AutoDownscalePre_x4`, `Upscale_CNN_x2_M` | 57 |

## Generating

```bash
scripts/anime4k-presets.sh                          # out/shaders/anime4k
scripts/anime4k-presets.sh --out D:/shaders/a4k     # somewhere else
scripts/anime4k-presets.sh --preset high,ultra      # only some presets
scripts/anime4k-presets.sh --list                   # show the chains
```

The first run downloads the ten upstream shaders into `out/cache/anime4k/<commit>/` and verifies each one against `scripts/anime4k-presets.lock`. Later runs use the cache, and `--offline` makes that mandatory. `--refresh` re-downloads anyway.

The script refuses to continue if the lock is for another commit, a shader is missing from the lock, or a download does not match its pinned SHA-256. Existing outputs are left alone on failure. After a download failure, `--update-lock` is the only way to accept the new files, and that should only follow a deliberate pin bump.

## Where they end up

| Context | Path |
|---|---|
| Default output | `out/shaders/anime4k/` |
| Windows portable package | `dist/shaders/anime4k/` |
| Linux install and export | `$LINUX_PREFIX/share/mediastack/shaders/anime4k/` (default `/opt/mediastack/...`) |

Use them wherever a single shader file is accepted:

```bash
mpv in.mkv --glsl-shaders=out/shaders/anime4k/high.glsl

ffmpeg -init_hw_device vulkan=vk:0 -filter_hw_device vk -i in.mkv \
  -vf "libplacebo=w=3840:h=2160:custom_shader_path=out/shaders/anime4k/high.glsl" ...

NVEncC64.exe --avhw -i in.mkv --vpp-libplacebo-shader shader=out/shaders/anime4k/high.glsl ...
```

## Format and licenses

Each file starts with the upstream license notices once, then a banner naming the Anime4K version, commit, preset and source files. The per-shader copies of those headers are removed from the bodies, and a blank line separates the source files. Pass text itself is untouched, and the order is exactly the manifest order.

Most shaders are MIT licensed; the two `AutoDownscalePre` shaders are Unlicense. Both notices are carried in every preset, and the banner lists which sources are Unlicense.

## Updating the pin

1. Set `ANIME4K_VERSION` and `ANIME4K_COMMIT` in `stack.conf` to the new tag and commit.
2. Run `scripts/anime4k-presets.sh --update-lock`. This downloads every shader in the manifest, computes their hashes, rewrites the lock and regenerates the selected presets (all by default).
3. Check the regenerated files, especially if a shader file was renamed.
4. Commit `stack.conf`, `scripts/anime4k-presets.lock` and, if paths changed, `scripts/anime4k-presets.conf`. Do not commit `out/`.

`--update-lock` needs the network and always downloads; it does not trust the cache, because a new pin has no hashes to check it against yet.

## Adding a preset

Add a block to `scripts/anime4k-presets.conf`:

```text
my_preset:
    glsl/Restore/Anime4K_Clamp_Highlights.glsl
    glsl/Upscale/Anime4K_Upscale_CNN_x2_M.glsl
```

The indented lines are one upstream path each and their order is the pass order. If the block uses shaders that are not already in the lock, run `--update-lock`; then run the script with `--preset my_preset`. New presets are picked up by the Windows and Linux packages automatically.

## Requirements

`bash`, `curl` and `sha256sum`; both MSYS2 UCRT64 and Linux provide them. No Python or `jq` is needed.
