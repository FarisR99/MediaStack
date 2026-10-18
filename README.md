# MediaStack

My customised media toolchain in one repo: FFmpeg, libplacebo, mpv and NVEncC, built together so each one uses the others' custom versions. It builds on Windows (MSYS2) and on Linux (in Docker, then installed on Ubuntu hosts).

| Project | Fork | Branch | Upstream |
|---|---|---|---|
| FFmpeg | [FarisR99/FFmpeg](https://github.com/FarisR99/FFmpeg) | `mediastack` | [FFmpeg/FFmpeg](https://github.com/FFmpeg/FFmpeg) |
| libplacebo | [FarisR99/libplacebo](https://github.com/FarisR99/libplacebo) | `mediastack` | [haasn/libplacebo](https://github.com/haasn/libplacebo) |
| mpv | [FarisR99/mpv](https://github.com/FarisR99/mpv) | `master` | [mpv-player/mpv](https://github.com/mpv-player/mpv) |
| NVEncC | [FarisR99/NVEnc](https://github.com/FarisR99/NVEnc) | `mediastack` | [rigaya/NVEnc](https://github.com/rigaya/NVEnc) |
| nv-codec-headers | (not forked) | release tag | [FFmpeg/nv-codec-headers](https://github.com/FFmpeg/nv-codec-headers) |

## Quick start

```bash
git clone --recursive git@github.com:FarisR99/MediaStack.git
cd MediaStack
scripts/setup.sh
```

**Windows** (in the *MSYS2 UCRT64* shell):

```bash
scripts/windows/deps.sh && scripts/windows/build.sh && scripts/windows/package.sh
```

**Linux** (Docker):

```bash
scripts/linux/export.sh && sudo scripts/linux/install-host.sh
```

## Docs

- [Getting started](docs/getting-started.md): prerequisites and first clone
- [Building on Windows](docs/building-windows.md)
- [Building on Linux](docs/building-linux.md)
- [Daily workflow](docs/daily-workflow.md): changing a project, committing, pushing
- [Updating from upstream](docs/updating-upstream.md)
- [What's customised](docs/customisations.md)
- [Testing](docs/testing.md) · [Troubleshooting](docs/troubleshooting.md) · [Licensing](docs/licensing.md)

---

The MediaStack scripts and docs are MIT licensed. The bundled projects keep their own licenses. Builds include GPL and **nonfree** FFmpeg components, so they're for personal use only and must not be redistributed (see [licensing](docs/licensing.md)).
