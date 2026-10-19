# Licensing

## MediaStack itself

The scripts, docs and configuration in this repository are under the [MIT license](../LICENSE). That covers only MediaStack's own files, not the projects inside it.

## The bundled projects

| Project | License |
|---|---|
| FFmpeg | LGPL 2.1+ by default. **This stack builds it as GPL 3 + nonfree** (see below). |
| libplacebo | LGPL 2.1+ |
| mpv | GPL 2+ (or LGPL 2.1+ when built with `-Dgpl=false`; this stack uses the GPL default) |
| NVEnc / NVEncC | MIT, plus bundled third-party code under its own licenses |
| nv-codec-headers | MIT |
| x264, x265 | GPL 2+ |
| libass, dav1d, libdovi | ISC, BSD-2-Clause, MIT |
| libvmaf | BSD-2-Clause-Patent |

## Why the builds are "personal use only"

FFmpeg is configured with:

- `--enable-gpl`, because x264, x265 and some filters are GPL. The resulting binaries are GPL.
- `--enable-version3`, which upgrades the license terms to (L)GPL version 3.
- `--enable-nonfree`. On Linux this turns on FFmpeg's CUDA filters compiled with NVIDIA's `nvcc`. NVIDIA's license terms for those parts are incompatible with the GPL.

A build that's both GPL and nonfree **can't legally be redistributed**: you can't satisfy both licenses at once. Using it yourself, on your own machines, is fine.

In practice:

- Don't upload the packages from `out/` (Windows `dist/`, Linux `.tar.zst`) anywhere public, or share them with others.
- Sharing the *source*, meaning these repos, is fine. Each project's license allows it.
- If you ever need a redistributable build, remove `--enable-nonfree` (and `--enable-cuda-nvcc`) in `scripts/common/build-ffmpeg.sh`. The result is then GPL v3 and shareable under its terms.
