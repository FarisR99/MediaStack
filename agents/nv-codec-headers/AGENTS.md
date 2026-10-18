# nv-codec-headers: agent guide

The source of truth for this doc is `agents/nv-codec-headers/AGENTS.md` in the MediaStack superrepo. For stack-wide rules, see the superrepo's root `AGENTS.md`.

- **Repo:** github.com/FFmpeg/nv-codec-headers (upstream; **not forked, never modified**). It's pinned to a release tag (currently `n13.1.15.0`), so its HEAD is detached by design and `.gitmodules` has no branch for it.
- **Role:** provides `ffnvcodec` (the NVENC/NVDEC/CUDA dynamic-loading headers plus `ffnvcodec.pc`) that FFmpeg builds against. FFmpeg loads the driver libraries at runtime, so no NVIDIA SDK is needed for FFmpeg itself.
- **Build:** `make PREFIX=<prefix> install` (`scripts/common/build-nv-codec-headers.sh`). The generated `ffnvcodec.pc` is gitignored upstream, so the tree stays clean.

## Bumping

1. `git -C nv-codec-headers fetch --tags`, then pick the newest `n<major>.<minor>.<x>.<y>` tag.
2. **Check the driver requirement.** Each SDK major/minor needs a minimum NVIDIA driver (see the tag's README). Every host that runs the stack, including WSL hosts whose Windows driver is what counts, must meet it. Otherwise NVENC fails at runtime with "Driver does not support the required nvenc API version".
3. `git -C nv-codec-headers checkout <tag>`, rebuild FFmpeg (and everything after it), then smoke-test NVENC.
4. `scripts/bump.sh --ai nv-codec-headers`, and update the tag named in this file.

FFmpeg's configure accepts `ffnvcodec >= 12.1.14.0` (or older 12.0/11.1 lines). Don't go below that.
