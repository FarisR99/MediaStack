# Benchmarks

What the forks gain over the original projects when upscaling anime from 1080p to 4K with Anime4K. Each tool is compared with its unmodified upstream, doing the same job on the same machine.

## Results

Split encoding on (NVENC encodes each frame on all three of the RTX 5090's encoders), shader cache warm:

| Tool | Original | fps | MediaStack | fps | Change |
|---|---|---:|---|---:|---:|
| mpv | `vf=gpu=api=d3d11` not supported | – | `vf=gpu=api=d3d11`, `hw-output` | **247.8** | **+301%** vs upstream Vulkan |
| mpv | upstream `vf=gpu=api=vulkan` | 61.8 | `vf=gpu=api=vulkan`, `hw-output` | 223.9 | +262% |
| FFmpeg | `libplacebo` → copy to RAM → `hevc_nvenc` | 155.7 | `libplacebo` → CUDA → `hevc_nvenc` | **231.9** | +49% |
| NVEncC | rigaya's 9.38 release | 166.1 | MediaStack build | **201.9** | +22% |

The same setups with a cold shader cache (split encoding still on), and with split encoding off (warm cache):

| Tool | Cold cache + split on: original | Cold cache + split on: MediaStack | Change | Split off: original | Split off: MediaStack | Change |
|---|---:|---:|---:|---:|---:|---:|
| mpv (d3d11 `hw-output`) | 63.3 | 208.7 | +230% | 62.2 | 104.7 | +68% |
| mpv (vulkan `hw-output`) | 63.3 | 213.7 | +238% | 62.2 | 105.6 | +70% |
| FFmpeg | 146.2 | 229.9 | +57% | 102.3 | 105.5 | +3% |
| NVEncC | 155.9 | 183.9 | +18% | 89.3 | 99.4 | +11% |

On 90 seconds of the same episode with a faster encoder setting (P1, 10-bit output), NVEncC went from 218 fps (release) to 314 fps (+44%).

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
- **MediaStack:** FFmpeg `3e2cb72a27`, libplacebo `405175f8`, mpv `258cc6bd1b`, NVEnc `c3ab2ec7`, October 2026.

Numbers vary by about ±5% between runs, and occasionally one run in three is 10–15% slower.
