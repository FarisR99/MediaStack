# Getting started

This page takes you from nothing to a working checkout on a new machine.

## What you need

### Every machine

- Git, plus SSH access to GitHub if you want to push. The submodules are fetched over HTTPS, so cloning works without SSH.

### Windows PCs

- **[MSYS2](https://www.msys2.org/)**, installed to `C:\msys64`. Always use the **MSYS2 UCRT64** shell for MediaStack; the scripts refuse to run in the other MSYS2 shells.
- **For NVEncC only:**
  - **Visual Studio 2022** with the "Desktop development with C++" workload. Not a newer Visual Studio: CUDA 13.0 only integrates with 2022.
  - the **CUDA Toolkit 13.0** (it sets `CUDA_PATH`). Newer versions aren't recognised by NVEnc's project yet. In the installer choose *Custom* and untick the driver, so it doesn't replace your newer one.
  - nothing else: the build script downloads the other SDK headers NVEnc needs
- An NVIDIA driver new enough for the pinned nv-codec-headers version (see [troubleshooting](troubleshooting.md#nvenc-says-the-driver-is-too-old)).

### Linux / WSL hosts

- **Docker** with BuildKit (Docker 23+ has it on by default). You don't need the NVIDIA Container Toolkit just to *build*; the build doesn't use the GPU.
- To *run* the result: Ubuntu 22.04 or newer and an NVIDIA driver. On WSL2, the Windows NVIDIA driver provides CUDA/NVENC inside WSL.

## First clone

```bash
git clone --recursive git@github.com:FarisR99/MediaStack.git
cd MediaStack
scripts/setup.sh
```

`setup.sh` is safe to run any time. It:

- makes sure every submodule is checked out, **on its branch** rather than a "detached HEAD"
- adds an `upstream` remote to each fork, pointing at the original project
- sets the fork remotes to push over SSH
- copies the agent docs into each project folder (git ignores them)

Afterwards, `scripts/status.sh` shows where everything stands:

```
PROJECT           BRANCH       HEAD      PIN                    ORIGIN               UPSTREAM         TREE
nv-codec-headers  n13.1.15.0   0a6fba9a  = pin                  -                    -                clean
libplacebo        mediastack   ccb74c6c  = pin                  +0/-0                -0 to merge      clean
...
```

- **PIN**: whether the project matches the commit MediaStack has recorded.
- **ORIGIN**: commits you haven't pushed to your fork yet (`+`), and commits on the fork you don't have locally (`-`).
- **UPSTREAM**: how many upstream commits are waiting to be merged.

## Before the very first push

The `mediastack` branches were created locally, so they don't exist on the forks until you push them:

```bash
git -C ffmpeg push -u origin mediastack
git -C libplacebo push -u origin mediastack
git -C nvenc push -u origin mediastack
git push -u origin master
```

The superrepo refuses to push while a submodule commit it points to isn't on GitHub yet; that's deliberate. Until you've pushed, a clone on another PC fails to fetch those commits.

## Next

- [Build on Windows](building-windows.md)
- [Build on Linux](building-linux.md)
- [Daily workflow](daily-workflow.md)
