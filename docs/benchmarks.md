# Benchmarks

What the forks gain over the original projects when upscaling anime from 1080p to 4K with Anime4K. Each tool is compared with its unmodified upstream, doing the same job on the same machine.

## Results

### Typical run (warm shader cache, split encoding on)

Shaders are already compiled, and NVENC encodes each frame on all three of the RTX 5090's encoders. This is what you get from the second run onwards with the recommended settings below.

| Tool | Original | fps | MediaStack | fps | Change |
|---|---|---:|---|---:|---:|
| mpv | `vf=gpu=api=d3d11` not supported | – | `vf=gpu=api=d3d11`, `hw-output` | **247.8** | **+301%** vs upstream Vulkan |
| mpv | upstream `vf=gpu=api=vulkan` | 61.8 | `vf=gpu=api=vulkan`, `hw-output` | 223.9 | +262% |
| FFmpeg | `libplacebo` → copy to RAM → `hevc_nvenc` | 155.7 | `libplacebo` → CUDA → `hevc_nvenc` | **231.9** | +49% |
| NVEncC | rigaya's 9.38 release | 166.1 | MediaStack build | **201.9** | +22% |

On 90 seconds of the same episode with a faster encoder setting (P1, 10-bit output), NVEncC went from 218 fps (release) to 314 fps (+44%).

### First run (cold shader cache)

The first time a shader is used, or after clearing the cache, it has to be compiled before encoding starts. Split encoding on.

| Tool | Original fps | MediaStack fps | Change |
|---|---:|---:|---:|
| mpv (d3d11 `hw-output`) | – (not supported) | 208.7 | +230% vs upstream Vulkan |
| mpv (vulkan `hw-output`) | 63.3 | 213.7 | +238% |
| FFmpeg | 146.2 | 229.9 | +57% |
| NVEncC | 155.9 | 183.9 | +18% |

### Without split encoding

For GPUs with a single NVENC encoder, or with split encoding turned off. Shader cache warm.

| Tool | Original fps | MediaStack fps | Change |
|---|---:|---:|---:|
| mpv (d3d11 `hw-output`) | – (not supported) | 104.7 | +68% vs upstream Vulkan |
| mpv (vulkan `hw-output`) | 62.2 | 105.6 | +70% |
| FFmpeg | 102.3 | 105.5 | +3% |
| NVEncC | 89.3 | 99.4 | +11% |

The gains are small here because a single encoder is the bottleneck: it tops out at about 100 fps for 4K, however fast the upscaling is. Upstream mpv is the exception, because it's held back at about 60 fps by its copies back to system memory.

## Where the gains come from

- **mpv:** upstream's `gpu` filter can only render with Vulkan or OpenGL, and reads every frame back to system memory, as RGB, waiting for each one. That caps it at about 60 fps, whatever the encoder does. The fork adds:
  - Direct3D 11 rendering;
  - `hw-output`, which hands frames to the encoder without leaving the GPU, as D3D11 or Vulkan frames;
  - GPU conversion to NV12;
  - background downloads, for when frames do have to come back;
  - a shader cache, so Anime4K isn't recompiled on every run.

  The Vulkan path also benefits from the libplacebo changes below. See [What's customised](customisations.md#mpv).
- **FFmpeg:**
  - Upstream can't pass `libplacebo`'s Vulkan frames to NVENC through CUDA on NVIDIA (it fails with `CUDA_ERROR_INVALID_VALUE`), so frames have to be copied to system memory and back. The fork fixes that hand-over.
  - When handing a frame to CUDA, upstream also waits on the CPU until the GPU has finished drawing it. The fork lets CUDA wait on the GPU instead, so FFmpeg can prepare the next frame meanwhile.
  - The gains only show with split encoding on: without it, NVENC is the bottleneck either way.
- **libplacebo (used by FFmpeg and mpv's Vulkan path):** Anime4K runs about 44 shader passes per frame. Upstream hands each one to the GPU separately and keeps asking the driver whether earlier work has finished; on Windows that CPU overhead alone limited FFmpeg to about 190 fps. The fork groups passes while the GPU is busy and checks for finished work more cheaply.
- **NVEncC:** the fork hands frames between CUDA and Direct3D 11 for libplacebo once per frame instead of once per plane, without stalling the rest of the pipeline, and keeps a shader cache.

## Recommended settings

The fastest MediaStack setting for each tool, from the runs above (split encoding on, warm cache):

```powershell
# mpv: 248 fps
mpv.com in.mkv --no-audio --glsl-shaders=Anime4K_ModeA.glsl `
  --vf=gpu=api=d3d11:w=3840:h=2160:hw-output=yes:hw-format=nv12 `
  --o=out.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,tune=hq,rc=constqp,qp=22,split_encode_mode=3

# FFmpeg: 232 fps
ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk `
  -hwaccel vulkan -hwaccel_output_format vulkan -i in.mkv -an `
  -vf "libplacebo=w=3840:h=2160:format=nv12:custom_shader_path=Anime4K_ModeA.glsl:shader_cache=pl.cache,hwupload=derive_device=cuda" `
  -c:v hevc_nvenc -preset p5 -tune hq -rc constqp -qp 22 -split_encode_mode 3 out.mkv

# NVEncC: 202 fps
NVEncC64.exe --avhw -i in.mkv -c hevc --preset P5 --cqp 22 --split-enc forced_3 `
  --vpp-libplacebo-shader shader=Anime4K_ModeA.glsl,res=3840x2160 -o out.mkv
```

Some other things the runs showed:
- **Split encoding matters most.** Without it every tool tops out at 90–110 fps, because one NVENC encoder can't encode 4K any faster.
- **mpv and FFmpeg are now close to NVENC's limit.** At P5, NVENC alone (no Anime4K) manages about 240–275 fps on this card. To go faster, use a faster preset: P1 took mpv from 242 to 347 fps, at some cost in quality per bit.
- **mpv needs a warm shader cache for its best speed.** It's on by default. If you run with `--no-config`, set `--gpu-shader-cache-dir`, otherwise every run starts cold.
- **With a cold cache, FFmpeg is the fastest.** It barely slows down, because its Vulkan path compiles shaders quickly.
- **`hevc_vulkan` doesn't need split encoding.** Before the libplacebo and FFmpeg changes it ran at about the same speed as NVENC with split encoding on (about 188 fps in FFmpeg, 155–160 in mpv); it hasn't been re-measured since. It's useful when you want to stay entirely in Vulkan.
- **mpv's hardware decoding doesn't help here.** In encoding mode only the `-copy` variants work, and software decoding of 1080p is cheap (about 680 fps).

## Other encoders

The same Anime4K 1080p → 4K upscale with other encoders, each at a fast preset, with software and hardware decoding.

| Encoder (preset) | FFmpeg, sw decode | FFmpeg, hw decode | mpv, sw decode | mpv, hw decode | NVEncC, sw decode | NVEncC, hw decode |
|---|---:|---:|---:|---:|---:|---:|
| `libx264` (fast, CRF 22) | 39.6 | **40.9** | 27.0 | 27.3 | – | – |
| `libx265` (fast, CRF 22) | 20.4 | **20.8** | 6.7 | 6.7 | – | – |
| `libsvtav1` (preset 8, CRF 30) | 46.8 | **49.5** | 30.1 | 31.4 | – | – |
| `h264_nvenc` (P1, QP 22) | 169.5 | 190.5 | **201.6** | 188.1 | 175.4 | 184.2 |
| `av1_nvenc` (P1, QP 88, split encoding) | 292.5 | 293.9 | **309.4** | 199.0 | 260.0 | 265.5 |

Hardware decoding means Vulkan in FFmpeg (`-hwaccel vulkan`), `d3d11va-copy` in mpv and NVDEC in NVEncC (`--avhw`). NVEncC can only use NVENC, so it has no CPU-encoder figures.

- **CPU encoders: use FFmpeg.** The CPU is the limit, so the decoding method makes little difference. mpv reaches only about two-thirds of FFmpeg's speed with them; why hasn't been investigated. `libx265` is worse still in mpv: mpv's `gpu` filter can only output NV12 or RGB, x265 takes neither, so mpv converts every frame from RGB on the CPU.
- **`h264_nvenc` can't use split encoding**, so it stays below 200 fps whatever the tool.
- **`av1_nvenc` at P1 with split encoding is the fastest option measured**, ahead of HEVC at P5 (about 230–250 fps). The mpv figure varied a lot between runs (244–330 fps); FFmpeg's was steadier (292–306 fps).
- AV1 QP runs from 0 to 255 in NVENC, so QP 88 is roughly comparable to QP 22 for H.264/HEVC. CRF 30 for SVT-AV1 is a common middle-quality setting. File sizes and quality differ between encoders; these numbers only compare speed.

The fastest command for each encoder:

```powershell
# libx264 (FFmpeg, Vulkan decoding): 41 fps. For libx265 (21 fps) use -c:v libx265 -preset fast -crf 22;
# for SVT-AV1 (50 fps) use -c:v libsvtav1 -preset 8 -crf 30.
ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk `
  -hwaccel vulkan -hwaccel_output_format vulkan -i in.mkv -an `
  -vf "libplacebo=w=3840:h=2160:format=yuv420p:custom_shader_path=Anime4K_ModeA.glsl:shader_cache=pl.cache,hwdownload,format=yuv420p" `
  -c:v libx264 -preset fast -crf 22 out.mkv

# h264_nvenc (mpv, software decoding): 202 fps
mpv.com in.mkv --no-audio --hwdec=no --glsl-shaders=Anime4K_ModeA.glsl `
  --vf=gpu=api=d3d11:w=3840:h=2160:hw-output=yes:hw-format=nv12 `
  --o=out.mkv --ovc=h264_nvenc --ovcopts=preset=p1,rc=constqp,qp=22

# av1_nvenc (mpv, software decoding): 309 fps
mpv.com in.mkv --no-audio --hwdec=no --glsl-shaders=Anime4K_ModeA.glsl `
  --vf=gpu=api=d3d11:w=3840:h=2160:hw-output=yes:hw-format=nv12 `
  --o=out.mkv --ovc=av1_nvenc --ovcopts=preset=p1,rc=constqp,qp=88,split_encode_mode=3
```

NVENC figures are the median of three runs on the 60-second clip. CPU-encoder figures are single runs on 20 seconds of the same clip: at these speeds start-up is negligible and run-to-run variation is small. Everything else is as described below.

## How these were measured

- **Machine:** Windows 11, RTX 5090 (driver 617.14), 24 CPU threads.
- **Clip:** 60 seconds (1440 frames) of a 1080p 10-bit HEVC anime episode, starting 10 minutes in. Shorter clips understate the differences: for the first couple of seconds FFmpeg's queues are still filling and every build runs fast, so a 20-second clip (about 2 seconds of encoding) hid most of the FFmpeg gain.
- **Work:** Anime4K ModeA (`Anime4K_ModeA.glsl`) to 3840×2160, then HEVC with NVENC: preset P5, tune hq, constant QP 22, 8-bit NV12.
- **FPS:** output frames divided by wall-clock time, start-up included. Each figure is the median of three runs; cold-cache figures are single runs. "Cold" means the tool's shader cache was deleted first (the NVIDIA driver's own cache stays warm).
- **Decoding:**
  - mpv decodes in software.
  - FFmpeg decodes with Vulkan.
  - NVEncC decodes with NVDEC (`--avhw`).
- **Originals:**
  - **NVEncC** is rigaya's 9.38 release.
  - **mpv** is upstream mpv (commit `6a262d11f6`), built with the same options against the same FFmpeg, with upstream libplacebo.
  - **FFmpeg:** the original is the MediaStack build from before the CUDA hand-over and libplacebo changes, with upstream libplacebo, forced through the system-memory path (`hwdownload`), the only path upstream FFmpeg can run here.
- **MediaStack:** FFmpeg `3e2cb72a27`, libplacebo `405175f8`, mpv `258cc6bd1b`, NVEnc `c3ab2ec7`, October 2026. The "Other encoders" runs used the same builds with SVT-AV1 4.2.0 added.

Numbers vary by about ±5% between runs, and occasionally one run in three is 10–15% slower.
