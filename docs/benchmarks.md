# Benchmarks

What the forks gain over the original projects when upscaling anime from 1080p to 4K with Anime4K. Each tool is compared with its unmodified upstream, doing the same job on the same machine.

## Results

Split encoding on (NVENC encodes each frame on all three of the RTX 5090's encoders), shader cache warm:

| Tool | Original | fps | MediaStack | fps | Change |
|---|---|---:|---|---:|---:|
| mpv | upstream `vf=gpu=api=vulkan` | 59.5 | `vf=gpu=api=d3d11`, `hw-output` | **209.3** | **3.5×** |
| mpv | | | `vf=gpu=api=vulkan`, `hw-output` | 165.7 | 2.8× |
| FFmpeg | `libplacebo` → copy to RAM → `hevc_nvenc` | 160.6 | `libplacebo` → CUDA → `hevc_nvenc` | **183.9** | +15% |
| NVEncC | rigaya's 9.38 release | 111.4 | MediaStack build | **153.2** | +38% |

The same setups with a cold shader cache, and with split encoding off:

| Tool | Cold cache: original | Cold cache: MediaStack | Split off: original | Split off: MediaStack |
|---|---:|---:|---:|---:|
| mpv (d3d11 `hw-output`) | 59.0 | 139.1 | 59.8 | 100.5 |
| mpv (vulkan `hw-output`) | 59.0 | 132.8 | 59.8 | 92.1 |
| FFmpeg | 158.6 | 182.2 | 96.5 | 96.6 |
| NVEncC | 108.1 | 119.5 | 70.8 | 77.7 |

On a longer clip, the NVEncC gap widens: on 90 seconds of the same episode (P1, 10-bit output), the release ran at 218 fps and the MediaStack build at 314 fps (+44%).

## Where the gains come from

- **mpv:** upstream's `gpu` filter can only render with Vulkan or OpenGL, and reads every frame back to system memory, as RGB, waiting for each one. That caps it at about 60 fps, whatever the encoder does. The fork adds:
  - Direct3D 11 rendering;
  - `hw-output`, which hands frames to the encoder without leaving the GPU, as D3D11 or Vulkan frames;
  - GPU conversion to NV12;
  - background downloads, for when frames do have to come back;
  - a shader cache, so Anime4K isn't recompiled on every run.

  See [What's customised](customisations.md#mpv).
- **FFmpeg:** upstream can't pass `libplacebo`'s Vulkan frames to NVENC through CUDA on NVIDIA (it fails with `CUDA_ERROR_INVALID_VALUE`), so frames have to be copied to system memory and back. The fork fixes that hand-over. The gain only shows with split encoding on: without it, NVENC is the bottleneck either way.
- **NVEncC:** the fork hands frames between CUDA and Direct3D 11 for libplacebo once per frame instead of once per plane, without stalling the rest of the pipeline, and keeps a shader cache. The cache explains most of the gap between the cold and warm numbers; the hand-over explains the rest.

## Recommended settings

The fastest MediaStack setting for each tool, from the runs above (split encoding on, warm cache):

```powershell
# mpv: 209 fps
mpv.com in.mkv --no-audio --glsl-shaders=Anime4K_ModeA.glsl `
  --vf=gpu=api=d3d11:w=3840:h=2160:hw-output=yes:hw-format=nv12 `
  --o=out.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,tune=hq,rc=constqp,qp=22,split_encode_mode=3

# FFmpeg: 184 fps (194 fps with -hwaccel cuda decoding; see below)
ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk `
  -hwaccel vulkan -hwaccel_output_format vulkan -i in.mkv -an `
  -vf "libplacebo=w=3840:h=2160:format=nv12:custom_shader_path=Anime4K_ModeA.glsl:shader_cache=pl.cache,hwupload=derive_device=cuda" `
  -c:v hevc_nvenc -preset p5 -tune hq -rc constqp -qp 22 -split_encode_mode 3 out.mkv

# NVEncC: 153 fps
NVEncC64.exe --avhw -i in.mkv -c hevc --preset P5 --cqp 22 --split-enc forced_3 `
  --vpp-libplacebo-shader shader=Anime4K_ModeA.glsl,res=3840x2160 -o out.mkv
```

Some other things the runs showed:
- **Split encoding matters most.** Without it every tool tops out at 70–100 fps, because one NVENC encoder can't encode 4K any faster.
- **mpv needs a warm shader cache to win.** It's on by default. If you run with `--no-config`, set `--gpu-shader-cache-dir`, otherwise every run starts cold and mpv falls to about 140 fps.
- **With a cold cache, FFmpeg is the fastest.** It barely slows down, because its Vulkan path compiles shaders quickly.
- **FFmpeg is slightly faster with NVDEC decoding:** `-init_hw_device cuda=cu:0 -init_hw_device vulkan=vk@cu -hwaccel cuda -hwaccel_output_format cuda` and `hwupload,` in front of `libplacebo` reached 194 fps in an earlier run.
- **`hevc_vulkan` doesn't need split encoding.** It runs at about the same speed as NVENC with split encoding on (about 188 fps in FFmpeg, 155–160 in mpv). It's useful when you want to stay entirely in Vulkan.
- **mpv's hardware decoding doesn't help here.** In encoding mode only the `-copy` variants work, and software decoding of 1080p is cheap.

## How these were measured

- **Machine:** Windows 11, RTX 5090 (driver 617.14), 24 CPU threads.
- **Clip:** 20 seconds (480 frames) of a 1080p 10-bit HEVC anime episode, starting 10 minutes in.
- **Work:** Anime4K ModeA (`Anime4K_ModeA.glsl`) to 3840×2160, then HEVC with NVENC: preset P5, tune hq, constant QP 22, 8-bit NV12.
- **FPS:** output frames divided by wall-clock time, start-up included, so short clips understate steady-state speed. Each figure is the median of three runs. "Cold" means the tool's shader cache was deleted first (the NVIDIA driver's own cache stays warm).
- **Decoding:**
  - mpv decodes in software.
  - FFmpeg decodes with Vulkan.
  - NVEncC decodes with NVDEC (`--avhw`).
- **Originals:**
  - **NVEncC** is rigaya's 9.38 release.
  - **mpv** is upstream mpv (commit `6a262d11f6`), built with the same options against the same FFmpeg and libplacebo.
  - **FFmpeg:** the original is the MediaStack build forced through the system-memory path (`hwdownload`), the only path upstream FFmpeg can run here. The two runs use identical FFmpeg code apart from the hand-over.
- **MediaStack:** superrepo `d9122a7` (FFmpeg `e51256182c`, mpv `258cc6bd1b`, NVEnc `c3ab2ec7`, libplacebo `285d1cc8`), October 2026.

Numbers vary by about ±5% between runs.
