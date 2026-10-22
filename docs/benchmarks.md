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

## RTX HDR and frame interpolation

The same Anime4K 1080p → 4K upscale with NVIDIA's RTX HDR (SDR to HDR10), frame interpolation (FRUC, 2× frame rate), both, or neither, compared across the three tools.

The tools use these features:
- **FFmpeg:** `truehdr_cuda` and `fruc_cuda`.
- **mpv:** `vf=gpu`'s `truehdr`, or the same FFmpeg filters through `lavfi`.
- **NVEncC:** `--vpp-ngx-truehdr` and `--vpp-fruc`.

Output fps; with FRUC, every input frame produces two output frames.

| Features | Split encoding | FFmpeg | mpv | NVEncC |
|---|---|---:|---:|---:|
| Neither | off | **102.0** | 101.6 | 97.7 |
| Neither | forced 3 | **211.9** | 200.1 | 191.3 |
| RTX HDR | off | **97.3** | 96.2 | 91.9 |
| RTX HDR | forced 3 | **184.5** | 168.6 | 155.5 |
| FRUC | off | 99.8 | **104.0** | 92.1 |
| FRUC | forced 3 | 101.9 | **103.4** | 87.5 |
| RTX HDR + FRUC | off | 92.2 | **93.8** | 85.0 |
| RTX HDR + FRUC | forced 3 | 91.8 | **93.7** | 84.9 |

For mpv with RTX HDR alone, `vf=gpu`'s own `truehdr=yes` and `lavfi`'s `truehdr_cuda` are within 2% of each other (96.2 vs 93.4 without split encoding; 166.2 vs 168.6 with it); the table shows the faster.

- **Without FRUC, NVENC is the limit,** so split encoding roughly doubles every tool. RTX HDR costs FFmpeg 5–13%.
- **With FRUC, FRUC is the limit.** NVIDIA's FRUC takes about 16 ms per interpolated 4K frame, so split encoding makes little difference. mpv and FFmpeg now beat NVEncC by 8–18%.
- **`fruc_cuda` runs NVIDIA's FRUC on a worker thread.** The FRUC call blocks until its frame is done. When `fruc_cuda` made that call on the filter thread, nothing else could happen meanwhile, so the next frame's Anime4K render waited for it. That hit mpv hardest: its renderer uses about five times FFmpeg's CPU time for the same frames (7.8 s vs 1.5 s for this clip without FRUC), and that work could no longer overlap with the GPU, leaving mpv 6–9% behind FFmpeg. Now the filter fetches the next frame while FRUC runs, so the two overlap. Against the earlier version in the same runs, this made mpv 18–40% faster and FFmpeg 8–27% faster:

  | Features | Split encoding | FFmpeg before → now | mpv before → now |
  |---|---|---:|---:|
  | FRUC | off | 89.6 → 99.8 (+11%) | 82.6 → 104.0 (+26%) |
  | FRUC | forced 3 | 80.4 → 101.9 (+27%) | 73.6 → 103.4 (+40%) |
  | RTX HDR + FRUC | off | 85.7 → 92.2 (+8%) | 79.7 → 93.8 (+18%) |
  | RTX HDR + FRUC | forced 3 | 79.8 → 91.8 (+15%) | 72.6 → 93.7 (+29%) |
- **Combining RTX HDR and FRUC in mpv:** `truehdr=yes` can't be combined with FRUC, because it outputs 10-bit and FRUC needs 8-bit input. Use `lavfi` with `hw-format=bgra`, `scale_cuda=format=rgba` and `truehdr_cuda`, which keeps frames on the GPU. Going through system memory instead (`hw-output=no:sw-format=rgb`) ran at 60.3 fps without split encoding with the earlier `fruc_cuda`, 24% slower than the GPU route at the time.

The fastest command for RTX HDR + FRUC in each tool (split encoding off):

```powershell
# FFmpeg: 92 fps
ffmpeg -init_hw_device vulkan=vk:0,disable_multiplane=1 -filter_hw_device vk `
  -hwaccel vulkan -hwaccel_output_format vulkan -i in.mkv -an `
  -vf "libplacebo=w=3840:h=2160:format=rgba:custom_shader_path=Anime4K_ModeA.glsl:shader_cache=pl.cache,hwupload=derive_device=cuda,fruc_cuda,truehdr_cuda" `
  -c:v hevc_nvenc -preset p5 -tune hq -rc constqp -qp 22 -profile:v main10 out.mkv

# mpv: 94 fps
mpv.com in.mkv --no-audio --glsl-shaders=Anime4K_ModeA.glsl `
  "--vf=gpu=api=vulkan:w=3840:h=2160:hw-output=yes:hw-format=bgra,lavfi=[hwupload,fruc_cuda,scale_cuda=format=rgba,truehdr_cuda]:hwdevice=cuda" `
  --o=out.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,tune=hq,rc=constqp,qp=22,profile=main10

# NVEncC: 85 fps
NVEncC64.exe --avhw -i in.mkv -c hevc --preset P5 --cqp 22 --output-depth 10 `
  --vpp-libplacebo-shader shader=Anime4K_ModeA.glsl,res=3840x2160 `
  --vpp-ngx-truehdr maxluminance=1000 --vpp-fruc double -o out.mkv
```

These runs differ from the rest of this page; they were measured as follows:
- **Clip:** 30 seconds (720 frames) of a different 1080p anime clip: a 10-second action scene repeated three times.
- **Upscale:** Anime4K to 3840×2160 with EWA Lanczos4-sharpest resampling in all three tools.
- **Output:** HEVC Main 10, 10-bit, at P5, tune hq, constant QP 22, 3 B-frames. RTX HDR at its defaults (1000 nits).
- **FPS:** wall-clock time including start-up, best of two runs, warm shader caches.
- **Decoding:** mpv in software, FFmpeg with Vulkan, NVEncC with NVDEC.
- **mpv rendering:** Vulkan (`vf=gpu=api=vulkan`), which RTX HDR and the CUDA filters need.
- **Builds:** FFmpeg `9163c37eff` (rows without FRUC) and the `fruc_cuda` worker-thread commit (rows with FRUC), mpv `21955ff8f6`, NVEnc `e251b079`. The rows with FRUC come from a later run with the same settings, all three tools in the same session.

Don't compare these figures directly with the tables above.

## Intel integrated graphics (UHD 770)

The same Anime4K 1080p → 4K upscale on the Intel UHD 770 built into the CPU, with the RTX 5090 used only for encoding (or not at all). The Intel graphics driver matters more than anything else here: updating it from the motherboard maker's July 2022 driver (31.0.101.3302) to Intel's own September 2026 driver (32.0.101.7092) made every run about five times as fast.

| Shader | Tool | Rendering | Decode → encode | Old driver fps | New driver fps | Change |
|---|---|---|---|---:|---:|---:|
| Mode C | mpv | `vf=gpu=api=vulkan` | QSV (`qsv-copy`) → `hevc_nvenc` | – | **8.12** | – |
| Mode C | mpv | `vf=gpu=api=vulkan` | software → `hevc_nvenc` | 1.54 | 7.86 | +410% |
| Mode C | FFmpeg | `libplacebo` (Vulkan) | software → `hevc_nvenc` | 1.31 | 7.00 | +434% |
| Mode C | mpv | `vf=gpu=api=d3d11` | software → `hevc_nvenc` | 1.49 | 6.57 | +341% |
| Mode C | FFmpeg | `libplacebo` (Vulkan) | QSV → `hevc_qsv` | – | 6.04 | – |
| Mode A | mpv | `vf=gpu=api=vulkan` | software → `hevc_nvenc` | – | **4.34** | – |
| Mode A | FFmpeg | `libplacebo` (Vulkan) | software → `hevc_nvenc` | 0.77 | 4.00 | +419% |
| Mode A | FFmpeg | `libplacebo` (Vulkan) | software → `libx265` | 0.76 | – | – |
| Mode A | FFmpeg | `libplacebo` (Vulkan) | QSV → `hevc_qsv` | failed | – | – |

- **Update the Intel driver first.** Get it from Intel ("Intel 11th–14th Gen Processor Graphics"), not from the PC or motherboard maker, whose drivers can be years old. The old driver's Vulkan support was also older (1.3.219), and the all-Intel QSV route failed on it: after about 2 minutes the driver reported `VK_ERROR_OUT_OF_DEVICE_MEMORY`, `hevc_qsv` failed with `Invalid FrameType:0`, and FFmpeg hung instead of exiting.
- **Anime4K is the limit, not the encoder.** On the old driver, encoding with `libx265` on the CPU and with NVENC on the RTX 5090 gave the same speed.
- **mpv with Vulkan is the fastest route:** 12% ahead of FFmpeg with Mode C and 9% with Mode A. On the new driver it's also 20% faster than mpv's D3D11 rendering; on the old driver the two were within 3%.
- **Keeping everything on the Intel GPU costs about 14%** (6.04 vs 7.00 fps), because decoding, Anime4K and encoding then share it. That route is for PCs without an NVIDIA GPU.
- **Mode C is about 80% faster than Mode A** on the new driver (7.86 vs 4.34 fps in mpv).
- **To decode on the Intel GPU in mpv, use `--hwdec=qsv-copy`.** It uses FFmpeg's QSV decoders, which always run on the Intel GPU. It measured 3% faster than software decoding (8.12 vs 7.86 fps), within run-to-run variation. MediaStack's mpv now decodes `vulkan-copy` and `d3d11va-copy` on the GPU picked with `--vulkan-device` and `--d3d11-adapter` (upstream mpv uses the default GPU, here the RTX 5090). `d3d11va-copy` works on the UHD 770, but `vulkan-copy` there crashes inside Intel's driver on the first frame; the cause isn't known yet.
- **To decode on the RTX 5090 instead,** while Anime4K runs on the Intel GPU, use `--hwdec=nvdec-copy`, or `--hwdec=vulkan-copy` with `--vulkan-decode-device="NVIDIA GeForce RTX 5090"`.

The fastest command in each tool (Mode C, new driver). Select the Intel GPU by name in mpv (`mpv --vulkan-device=help` lists them) and by index in FFmpeg (`1` here):

```powershell
# mpv: 7.86 fps
mpv.com in.mkv --no-audio --hwdec=no --glsl-shaders=Anime4K_ModeC.glsl `
  --scale=ewa_lanczos --dscale=ewa_lanczos "--vulkan-device=Intel(R) UHD Graphics 770" `
  --vf=gpu=api=vulkan:w=3840:h=2160:hw-output=no:sw-format=nv12 `
  --o=out.mkv --ovc=hevc_nvenc --ovcopts=preset=p5,rc=constqp,qp=22

# FFmpeg: 7.00 fps
ffmpeg -init_hw_device vulkan=vk:1 -filter_hw_device vk -i in.mkv -an `
  -vf "libplacebo=w=3840:h=2160:upscaler=ewa_lanczos:downscaler=ewa_lanczos:custom_shader_path=Anime4K_ModeC.glsl,format=nv12" `
  -c:v hevc_nvenc -preset p5 -rc constqp -qp 22 out.mkv

# FFmpeg, Intel GPU only: 6.04 fps
ffmpeg -init_hw_device qsv=qs -init_hw_device vulkan=vk:1 -filter_hw_device vk `
  -hwaccel qsv -hwaccel_device qs -hwaccel_output_format qsv -i in.mkv -an `
  -vf "hwdownload,format=nv12,libplacebo=w=3840:h=2160:upscaler=ewa_lanczos:downscaler=ewa_lanczos:custom_shader_path=Anime4K_ModeC.glsl,format=nv12" `
  -c:v hevc_qsv -preset fast -global_quality 22 out.mkv
```

`vf=gpu=api=d3d11` takes `--d3d11-adapter=Intel` to pick the Intel GPU. It ignores `sw-format=nv12` (it has no buffer downloads) and reads frames back as RGB.

### Faster shaders: half precision and Anime4K's Fast sets

Two shader changes speed up Anime4K on the UHD 770 far more than any of the settings above. mpv `vf=gpu=api=vulkan`, software decoding, `hevc_nvenc`. PSNR is measured against the same mode at normal precision, over 48 frames captured losslessly.

| Shader | Precision | fps | Change | PSNR vs the normal shader |
|---|---|---:|---:|---:|
| Mode C | normal | 7.86 | – | – |
| Mode C | **half** | 14.10 | +79% | 65.4 dB |
| Mode C Fast | normal | 20.51 | +161% | 50.5 dB |
| Mode C Fast | **half** | **26.96** | **+243%** | – |
| Mode A | normal | 4.34 | – | – |
| Mode A | **half** | 8.03 | +85% | 63.8 dB |
| Mode A Fast | normal | 15.07 | +247% | 44.0 dB |
| Mode A Fast | **half** | **21.52** | **+396%** | – |

Mode C Fast at half precision is 67.4 dB from Mode C Fast at normal precision. For scale, Mode A and Mode C differ from each other by 37.7 dB.

- **Half precision costs nothing visible on an Intel iGPU.** The UHD 770 does 16-bit maths at twice the rate of 32-bit, and Anime4K's networks are almost all multiply-adds. Adding the line `precision mediump float;` to each shader pass, after its `//!` header lines, lets the driver use 16-bit maths. The output stays within 64–65 dB of normal precision, so on 8-bit video almost every pixel is identical.
- **Don't use half precision on NVIDIA.** On the RTX 5090 (mpv, 720 frames, median of three runs), Mode A went from 246.4 to 238.8 fps (−3%) and Mode C from 303.6 to 303.5 fps. It does 16-bit maths at the same rate as 32-bit. Intel Arc graphics cards weren't measured.
- **The Fast sets change the picture.** They're Anime4K's own presets for weaker GPUs, built from its smaller networks: Mode C Fast is Clamp_Highlights, Upscale_Denoise_CNN_x2_M, AutoDownscalePre_x2, AutoDownscalePre_x4 and Upscale_CNN_x2_S, and Mode A Fast is Clamp_Highlights, Restore_CNN_M, Upscale_CNN_x2_M, AutoDownscalePre_x2, AutoDownscalePre_x4 and Upscale_CNN_x2_S. They're the bigger speed-up but a real quality trade-off: 44–50 dB from the normal sets.

### Encoding with the Intel GPU in mpv

For PCs without an NVIDIA GPU. Mode C, QSV decoding (`qsv-copy`), `hevc_qsv`:

| Rendering | Frames to the encoder | fps |
|---|---|---:|
| `vf=gpu=api=vulkan` | read back to system memory (`sw-format=nv12`) | **6.83** |
| `vf=gpu=api=d3d11` | read back to system memory | 6.04 |
| `vf=gpu=api=d3d11` | handed straight to QSV (`hw-output=yes:hw-format=nv12`) | 5.91 |

- **Vulkan is the fastest route here,** 13% ahead of FFmpeg's all-Intel route (6.04 fps).
- **Handing D3D11 frames straight to QSV works** ("Rendering directly to nv12 hardware frames"), but gains nothing on this GPU: copying frames isn't the limit.
- **Supported encoders:** `hevc_qsv` (8-bit and Main 10 with `sw-format=p010`) and `h264_qsv` work. `av1_qsv` fails, because the UHD 770 has no AV1 encoder.

These runs differ from the rest of this page; they were measured as follows:
- **Clip:** 10 seconds (240 frames) of a 1080p anime clip, re-encoded to 8-bit H.264 so that the Intel GPU can decode it.
- **Upscale:** Anime4K Mode A (`Anime4K_ModeA.glsl`) or Mode C (`Anime4K_ModeC.glsl`) to 3840×2160, with EWA Lanczos resampling (`--scale=ewa_lanczos --dscale=ewa_lanczos` in mpv, libplacebo's `ewa_lanczos` in FFmpeg).
- **Output:** HEVC, 8-bit. NVENC at P5, constant QP 22; `hevc_qsv` at preset fast, `global_quality` 22; `libx265` at preset fast, CRF 22.
- **FPS:** wall-clock time including start-up, single runs.
- **Shaders:** Mode A and Mode C are Anime4K 4.0.1's standard high-quality presets; the Fast sets come from the same release.
- **Builds:** MediaStack `5fa9c13` (FFmpeg `f223bcfcbe`, libplacebo `405175f8`, mpv `30f05d3b01`), October 2026.

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
