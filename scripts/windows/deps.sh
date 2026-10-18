#!/usr/bin/env bash
# Install the MSYS2 UCRT64 packages the Windows build needs. Run from the
# "MSYS2 UCRT64" shell. FFmpeg and libplacebo are deliberately NOT installed
# from pacman: the stack builds its own.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
[[ "${MSYSTEM:-}" == UCRT64 ]] || die "run this from the MSYS2 UCRT64 shell (MSYSTEM is '${MSYSTEM:-unset}')"

p=mingw-w64-ucrt-x86_64
pacman -S --needed --noconfirm \
    git make diffutils patch zstd \
    $p-toolchain $p-meson $p-ninja $p-pkgconf $p-nasm $p-ccache $p-python $p-tools-git \
    $p-clang \
    $p-vulkan-headers $p-vulkan-loader $p-shaderc $p-spirv-cross \
    $p-lcms2 $p-libdovi $p-libass $p-dav1d $p-x264 $p-x265 $p-libvpl $p-amf-headers \
    $p-luajit $p-angleproject $p-libjpeg-turbo $p-libarchive $p-libbluray \
    $p-uchardet $p-rubberband

for shadow in $p-ffmpeg $p-libplacebo; do
    if pacman -Q "$shadow" >/dev/null 2>&1; then
        warn "$shadow is installed. The stack's own build takes precedence through PKG_CONFIG_PATH, but consider 'pacman -R $shadow' to avoid picking up its DLLs by accident."
    fi
done
msg "Dependencies installed. Next: scripts/windows/build.sh"
