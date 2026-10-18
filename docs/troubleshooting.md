# Troubleshooting

## Setup and git

### A project says "detached" in `scripts/status.sh`

Run `scripts/setup.sh`. It puts each project back on its branch. This often happens after `git pull` or `git submodule update`, which check out the exact pinned commit rather than the branch.

### "diverged from pin"

You have local commits in a project, and someone (maybe you on another PC) pinned different commits. Inside the project, merge the remote branch, e.g. `git -C mpv pull`. Then `scripts/bump.sh mpv`.

### `git push` refuses: submodule commits not pushed

MediaStack points at a project commit that isn't on GitHub yet. Push the project first (`git -C <project> push`), then MediaStack.

### Scripts fail on Windows with `$'\r': command not found`

A script got Windows line endings. The repo's `.gitattributes` normally prevents this. Re-checkout the file: `git checkout -- scripts/`.

## Building

### Linux: Docker build fails

Rerun with the full log: `scripts/linux/export.sh --progress=plain`. The step that failed is near the end. For FFmpeg, the last lines of its `config.log` are printed too. If you suspect a stale cache, `scripts/linux/export.sh --no-cache` rebuilds everything.

### Windows: the wrong FFmpeg or libplacebo gets used

If pacman's FFmpeg or libplacebo packages are installed, remove them:

```bash
pacman -R mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-libplacebo
```

### Windows: NVEncC build fails

Note the error. Then try the fallback route: `.\scripts\windows\nvencc-spike.ps1 -Route B`. Record what happened in [building-windows.md](building-windows.md).

## Running

### NVENC says the driver is too old

The message is "Driver does not support the required nvenc API version". The pinned nv-codec-headers release needs a newer NVIDIA driver than the machine has. Update the driver. On WSL, update the **Windows** NVIDIA driver; WSL uses it.

### `error while loading shared libraries` after installing on Linux

Run `sudo scripts/linux/install-host.sh` again; it installs the runtime packages the build needs. If it persists, `ldd /opt/mediastack/bin/mpv | grep "not found"` shows what's missing. Ask an agent to fix the packaging.

### NVEncC: libplacebo filters "not found"

NVEncC has to be rebuilt every time libplacebo changes. Rebuild the whole stack.

### Vulkan is very slow in WSL

That's expected. WSL has no NVIDIA Vulkan driver, so Vulkan runs on the CPU or through a translation layer. NVENC and CUDA are unaffected. Use Windows or a native Linux machine for heavy libplacebo work.
