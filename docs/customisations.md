# What's customised

What each fork changes compared to upstream, and why. Keep this up to date as features land; it's the first thing to read when an upstream merge conflicts.

To list a fork's own commits:

```bash
git -C mpv log --oneline --no-merges upstream/master..master
git -C ffmpeg log --oneline --no-merges upstream/master..mediastack
```

## mpv

The fork turns mpv into a **GPU-accelerated encoder**. The `gpu` video filter renders frames with libplacebo, the same renderer `--vo=gpu-next` uses, inside the filter chain. mpv's encoding mode then encodes them, typically with NVENC.

- **More rendering back ends for `--vf=gpu`:** Vulkan (including software Vulkan devices, picked with `--vulkan-device`), Direct3D 11, and ANGLE on Windows.
- **Zero-copy hardware encoding on Windows.**
  - With `hw-output`, frames stay on the GPU as D3D11 textures and go straight to NVENC or Intel QSV encoders, instead of being downloaded to system memory and uploaded again.
  - With `hw-format=nv12`, the conversion to YUV happens on the GPU: BT.709, or BT.2020 for HDR, limited range, correctly sited chroma. This gives better colour than letting the encoder convert.
- **Persistent shader cache** for the filter, so start-up is faster on repeat runs.
- **Stability fixes:** context set-up and teardown, subtitle state, device options, OpenGL readback. `--vf=gpu=api=vulkan` no longer crashes on machines without a working Vulkan driver; it reports an error instead. That fix would also suit upstream mpv.
- **Repo housekeeping:** Vulkan is required, unused CI platforms are removed, and Windows (MSYS2) CI builds are uploaded.

## NVEncC

- **Works with current libplacebo.** Upstream NVEncC only recognises libplacebo releases up to API 360, so with the stack's newer libplacebo its `--vpp-libplacebo-*` filters would silently be unavailable. The fork also accepts whichever libplacebo version it was compiled against.

## FFmpeg

No changes yet; the `mediastack` branch matches upstream.

## libplacebo

No changes yet; the `mediastack` branch matches upstream.

## nv-codec-headers

Never customised; it's pinned to an official release.
