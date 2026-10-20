# Testing

Quick checks that a build works end to end. Run them after building, and after every upstream merge.

## Linux

After `sudo scripts/linux/install-host.sh` and opening a new terminal:

```bash
cat /opt/mediastack/BUILDINFO.txt            # which commits you're running
ffmpeg -hide_banner -encoders | grep nvenc   # expect h264_nvenc, hevc_nvenc, av1_nvenc
mpv --version                                # mentions the FFmpeg and libplacebo versions
nvencc --check-hw                            # lists your GPU and its codecs
```

You can also test a fresh build **without installing it**, because the build output runs from where it is:

```bash
out/linux/stage/bin/ffmpeg -hide_banner -version
```

### Encoding

Each of these makes a short test video in `/tmp`, then you can play it or check it with `ffprobe`:

```bash
# FFmpeg + NVENC
ffmpeg -f lavfi -i testsrc2=s=1920x1080:r=30 -t 3 -c:v hevc_nvenc /tmp/nvenc.mkv

# FFmpeg CUDA scaling (the "nonfree" part)
ffmpeg -f lavfi -i testsrc2=s=1280x720 -t 2 \
  -vf "format=yuv420p,hwupload_cuda,scale_cuda=1920:1080" -c:v h264_nvenc /tmp/cuda.mkv

# mpv as an encoder, rendering through libplacebo
mpv --no-config /tmp/nvenc.mkv --vf=gpu=api=vulkan --o=/tmp/mpv.mkv --ovc=hevc_nvenc

# NVEncC, with and without libplacebo filters
nvencc -i /tmp/nvenc.mkv --codec hevc -o /tmp/nvencc.mkv
nvencc -i /tmp/nvenc.mkv --codec hevc --vpp-resize libplacebo-spline36 --output-res 2560x1440 -o /tmp/nvencc-pl.mkv
nvencc -i /tmp/nvenc.mkv --codec hevc --vpp-libplacebo-deband -o /tmp/nvencc-deband.mkv
```

**On WSL**, there's no NVIDIA Vulkan driver, so:

- mpv's `--vf=gpu=api=vulkan` and FFmpeg's `libplacebo` filter only work after `sudo apt install mesa-vulkan-drivers`, and then run slowly on the CPU.
- NVEncC's libplacebo filters don't work at all ("vulkan device not set"). They need the NVIDIA Vulkan driver, so use native Linux or Windows for those.

Everything NVENC/CUDA-based works normally on WSL.

## Windows

From the portable folder (`out\ucrt64\dist`) in a normal Command Prompt or PowerShell:

```powershell
.\ffmpeg.exe -hide_banner -encoders | findstr nvenc
.\mpv.com --version
.\NVEncC64.exe --check-hw
.\ffmpeg.exe -f lavfi -i testsrc2=s=1920x1080:r=30 -t 3 -c:v hevc_nvenc nvenc.mkv

# mpv's zero-copy path: render with D3D11, hand NV12 frames straight to NVENC
.\mpv.com --no-config nvenc.mkv --vf=gpu=api=d3d11:hw-output=yes:hw-format=nv12 --o=mpv.mkv --ovc=hevc_nvenc -v

.\NVEncC64.exe -i nvenc.mkv --codec hevc --vpp-resize libplacebo-spline36 --output-res 2560x1440 -o nvencc-pl.mkv
```

In mpv's `-v` output, look for `Rendering directly to nv12 hardware frames`. When it's working there's no `Downloading` line.

The same with Vulkan (works on Linux too), into NVENC and into FFmpeg's Vulkan encoder:

```powershell
.\mpv.com --no-config nvenc.mkv --vf=gpu=api=vulkan:hw-output=yes:hw-format=nv12 --o=mpv-vk.mkv --ovc=hevc_nvenc -v
.\mpv.com --no-config nvenc.mkv --vf=gpu=api=vulkan:hw-output=yes:hw-format=nv12 --o=mpv-vkenc.mkv --ovc=hevc_vulkan -v
```
