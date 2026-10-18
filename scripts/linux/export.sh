#!/usr/bin/env bash
# Build the stack in Docker and export it as out/linux/mediastack-<sha>.tar.zst (.tar.gz without zstd)
# (contents of /opt/mediastack). Builds whatever is checked out, including
# uncommitted changes, and records that in BUILDINFO.txt.
#
# Usage: export.sh [extra docker build args...]   e.g. --no-cache, --progress=plain
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
cd "$STACK_ROOT"

out=out/linux
mkdir -p "$out/meta"
rm -rf "$out/stage"

describe() { git -C "$1" describe --tags --always --dirty 2>/dev/null || git -C "$1" rev-parse --short HEAD; }

sha=$(git rev-parse --short HEAD 2>/dev/null || echo uncommitted)
[[ -n "$(git status --porcelain --ignore-submodules=none 2>/dev/null)" ]] && sha+="-dirty"
{
    echo "MediaStack $sha"
    echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname)"
    echo "target: linux (Ubuntu $UBUNTU_VERSION, CUDA $CUDA_VERSION)"
    for p in $STACK_PROJECTS; do
        printf '%-17s %s %s\n' "$p:" "$(git -C "$p" rev-parse --short=12 HEAD)" "$(describe "$p")"
    done
} > "$out/meta/BUILDINFO.txt"
cat "$out/meta/BUILDINFO.txt"

DOCKER_BUILDKIT=1 docker build \
    -f scripts/linux/Dockerfile \
    --build-context meta="$out/meta" \
    --build-arg CUDA_VERSION="$CUDA_VERSION" \
    --build-arg UBUNTU_VERSION="$UBUNTU_VERSION" \
    --build-arg MESON_VERSION="$MESON_VERSION" \
    --build-arg VULKAN_SDK_VERSION="$VULKAN_SDK_VERSION" \
    --build-arg CARGO_C_VERSION="$CARGO_C_VERSION" \
    --build-arg LINUX_PREFIX="$LINUX_PREFIX" \
    --build-arg FFMPEG_REVISION="$(git -C ffmpeg describe --tags --match N 2>/dev/null || describe ffmpeg)" \
    --target export \
    --output "type=local,dest=$out/stage" \
    "$@" .

if command -v zstd >/dev/null; then
    ext=tar.zst comp=--zstd
else
    ext=tar.gz comp=--gzip
    warn "zstd not installed; writing a .tar.gz instead (apt install zstd for smaller, faster archives)"
fi
tarball="$out/mediastack-$sha.$ext"
rm -f "$out"/mediastack-latest.tar.*
tar "$comp" -cf "$tarball" -C "$out/stage" .
ln -sfn "$(basename "$tarball")" "$out/mediastack-latest.$ext"
msg "Exported $tarball ($(du -h "$tarball" | cut -f1))"
msg "Install on this host with: sudo scripts/linux/install-host.sh"
