# What's customised

What each fork changes compared to upstream, and why. For how much faster this makes Anime4K upscaling, see [Benchmarks](benchmarks.md). Keep this up to date as features land; it's the first thing to read when an upstream merge conflicts.

To list a fork's own commits:

```bash
git -C mpv log --oneline --no-merges upstream/master..master
git -C ffmpeg log --oneline --no-merges upstream/master..mediastack
```

## mpv

The fork turns mpv into a **GPU-accelerated encoder**. The `gpu` video filter renders frames with libplacebo, the same renderer `--vo=gpu-next` uses, inside the filter chain. mpv's encoding mode then encodes them, typically with NVENC.

- **More rendering back ends for `--vf=gpu`:** Vulkan (including software Vulkan devices, picked with `--vulkan-device`), Direct3D 11, and ANGLE on Windows.
- **Hardware encoding without downloads.**
  - With `hw-output`, frames stay on the GPU and go straight to the encoder, instead of being downloaded to system memory and uploaded again.
  - With `api=d3d11` (Windows) they're D3D11 textures, for NVENC or Intel QSV. This is the fastest way to encode with mpv.
  - With `api=vulkan` (Windows and Linux) they're Vulkan images, for `hevc_vulkan`, or for NVENC through a GPU-side copy into CUDA. On Linux this is the only way to avoid the download. On an RTX 5090 with Anime4K (1080p → 4K, 20 s clip), Vulkan into NVENC ran at about 168 fps, against 150 when downloading and 210 with D3D11; Vulkan into `hevc_vulkan` ran at about 158 fps.
  - With `hw-format=nv12`, the conversion to YUV happens on the GPU: BT.709, or BT.2020 for HDR, limited range, correctly sited chroma. This gives better colour than letting the encoder convert.
- **HDR10 metadata when encoding:** mpv now hands mastering-display and light-level metadata to the encoder when it opens, so `hevc_nvenc`, `av1_nvenc` and `libx265` write it into HDR encodes (upstream mpv drops it). `av1_nvenc` writes only the mastering-display part; FFmpeg alone does the same.
- **Faster encoding from software frames:** the filter reads finished frames back from the GPU in the background while it renders the next ones, instead of waiting for each download. With Vulkan this used to be most of the frame time.
- **RTX Video HDR (TrueHDR) while encoding:** `--vf=gpu=api=vulkan:truehdr=yes` turns SDR into HDR10 with NVIDIA's AI SDR-to-HDR conversion, after Anime4K or any other shaders. The output is 10-bit BT.2020 PQ with HDR10 metadata, so pair it with a 10-bit encoder profile such as `--ovcopts=profile=main10`. `truehdr-contrast`, `truehdr-saturation`, `truehdr-middle-gray` and `truehdr-max-luma` tune it, with the same defaults and ranges as NVEncC's `--vpp-ngx-truehdr`, and the output matches NVEncC's closely (51 dB luma PSNR on the same clip). Windows and RTX GPUs only. It needs `NVEncNVSDKNGX.dll`, `nvngx_truehdr.dll` and `cudart64_12.dll` next to `mpv.exe`; `scripts/windows/package.sh` downloads them into the portable folder. On an RTX 5090, Anime4K 1080p → 4K into NVENC ran at 99 fps with TrueHDR, against 123 without (10 s clips).

  ```powershell
  mpv in.mkv --glsl-shaders=Anime4K.glsl --vf=gpu=api=vulkan:w=3840:h=2160:truehdr=yes `
    --o=out.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,tune=hq,rc=constqp,qp=22,profile=main10,split_encode_mode=3
  ```
- **10-bit output:** `hw-format=p010` and `sw-format=p010` work like `nv12`, but with 10 bits per sample.
- **Smaller, correctly coloured downloads:** when the encoder accepts NV12, the filter converts frames to NV12 on the GPU before reading them back. That's under half the data of RGB, and avoids the encoder's own BT.601 conversion.
- **Persistent shader cache** for the filter, so start-up is faster on repeat runs.
- **Stability fixes:** context set-up and teardown, subtitle state, device options, OpenGL readback. `--vf=gpu=api=vulkan` no longer crashes on machines without a working Vulkan driver; it reports an error instead. That fix would also suit upstream mpv.
- **Repo housekeeping:** Vulkan is required, unused CI platforms are removed, and Windows (MSYS2) CI builds are uploaded.

## NVEncC

- **Faster libplacebo filters on Windows.** NVEncC hands each frame between CUDA and Direct3D 11 for libplacebo. Upstream does this one plane at a time, through a CUDA stream that makes the rest of the pipeline wait. With large shaders like Anime4K, a job ends up waiting rather than using the GPU: on an RTX 5090 one Anime4K 1080p → 4K encode tops out around 140 fps, yet two at once reach about 150 together. The fork hands over all planes at once, on the filter's own stream, and prepares the textures once instead of every frame. On a 90-second Anime4K clip (P1, `--split-enc forced_3`) that took one encode from 218 to 314 fps, without changing the output.
- **Shader cache for libplacebo.** Compiled shaders are kept in `%LOCALAPPDATA%\NVEncC\libplacebo_cache` (Linux: `~/.cache/nvencc/libplacebo_cache`), so big shaders like Anime4K aren't compiled again on every run. Delete the folder at any time. Saves about a second of start-up per run; on a 20-second clip that alone took a P5 encode from 81 to 98 fps.
- **Works with current libplacebo.** Upstream NVEncC only recognises libplacebo releases up to API 360, so with the stack's newer libplacebo its `--vpp-libplacebo-*` filters would silently be unavailable. The fork also accepts whichever libplacebo version it was compiled against.

## FFmpeg

- **libplacebo straight into NVENC.** FFmpeg can hand Vulkan frames to CUDA, which is what NVENC needs, but on NVIDIA that failed with `CUDA_ERROR_INVALID_VALUE` once FFmpeg started creating Vulkan images with "host transfer" usage, which CUDA can't map. The fork leaves that usage off on Vulkan devices set up for CUDA. Upscaling with `libplacebo` and encoding with `hevc_nvenc`/`av1_nvenc` then needs no detour through system memory.

  On an RTX 5090, 1080p → 4K with Anime4K, NVENC `-preset p5` went from about 105 fps (download, then upload) to about 240 fps with `-split_encode_mode 3`, which spreads each frame over the card's three NVENC engines. The split modes only pay off without the CPU round trip. The Vulkan device needs `disable_multiplane=1`, or derive it from CUDA:

  ```powershell
  ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk `
    -hwaccel vulkan -hwaccel_output_format vulkan -i in.mkv `
    -vf "libplacebo=w=3840:h=2160:format=p010:custom_shader_path=shaders.glsl:shader_cache=pl.cache,hwupload=derive_device=cuda" `
    -c:v hevc_nvenc -preset p5 -tune hq -rc vbr -cq 22 -split_encode_mode 3 -profile:v main10 out.mkv
  ```

  To decode with NVDEC instead: `-init_hw_device cuda=cu -init_hw_device vulkan=vk@cu -filter_hw_device vk -hwaccel cuda -hwaccel_output_format cuda`, with `hwupload,` at the start of `-vf`.
- **RTX Video HDR (TrueHDR):** the new `truehdr_cuda` filter turns SDR into HDR10 with NVIDIA's AI SDR-to-HDR conversion, on the GPU, and its output goes straight into NVENC. It writes HDR10 mastering-display and light-level metadata, as mpv's does. Same options and defaults as mpv's `truehdr` and NVEncC's `--vpp-ngx-truehdr`; the output matches NVEncC's to 51 dB. Windows and RTX GPUs only; it needs `NVEncNVSDKNGX.dll`, `nvngx_truehdr.dll` and `cudart64_12.dll` next to `ffmpeg.exe`, which `scripts/windows/package.sh` downloads into the portable folder. On an RTX 5090, Anime4K 1080p → 4K into NVENC ran at 113 fps with TrueHDR, against 132 without (10 s clips).

  ```powershell
  ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk `
    -hwaccel vulkan -hwaccel_output_format vulkan -i in.mkv `
    -vf "libplacebo=w=3840:h=2160:format=rgba:custom_shader_path=Anime4K.glsl,hwupload=derive_device=cuda,truehdr_cuda=max_luma=1000" `
    -c:v hevc_nvenc -preset p5 -tune hq -rc vbr -cq 22 -split_encode_mode 3 -profile:v main10 out.mkv
  ```
- **No waiting when frames go to CUDA.** When handing a Vulkan frame to CUDA, upstream waits on the CPU until the GPU has finished drawing it, twice per frame. CUDA already waits for the frame on the GPU, so the fork skips those waits and FFmpeg can prepare the next frame meanwhile. With the libplacebo changes below, Anime4K 1080p → 4K into NVENC went from about 188 to 233 fps.

## libplacebo

Two changes to the Vulkan backend that make shaders with many passes, like Anime4K, much cheaper on the CPU. Output is unchanged.

- **Fewer submissions.** Upstream hands each render pass to the GPU separately. Anime4K has about 44 passes per frame, and on Windows each hand-over costs more CPU time than the pass takes to run. The fork still hands work over straight away when the GPU would otherwise idle, but otherwise collects passes and hands them over together.
- **Cheaper checks for finished work.** libplacebo checks for finished GPU work several times per pass. The fork reads a counter instead of asking the driver to wait, which is several times cheaper on NVIDIA on Windows.

Together with the FFmpeg change above, FFmpeg's Anime4K upscaling into NVENC went from about 188 to 233 fps, and mpv's Vulkan hardware output from about 160 to 225 fps. mpv's Direct3D 11 output and NVEncC don't use the Vulkan backend, so they're unaffected.

## nv-codec-headers

Never customised; it's pinned to an official release.
