# syntax=docker/dockerfile:1.7
# MediaStack Linux build: Ubuntu 22.04 + CUDA. Build context is the superrepo
# root with submodules checked out; run it through scripts/linux/export.sh,
# which passes the versions from stack.conf and the 'meta' build context.
#
# Each project gets its own COPY + RUN so editing mpv doesn't rebuild FFmpeg.
# Build dirs and ccache live in cache mounts, so rebuilds are incremental.

ARG CUDA_VERSION=13.4.3
ARG UBUNTU_VERSION=22.04

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION} AS builder
ARG MESON_VERSION=1.12.1
ARG VULKAN_SDK_VERSION=1.4.363.0
ARG CARGO_C_VERSION=v0.10.26
ARG LINUX_PREFIX=/opt/mediastack
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates ccache curl file git nasm ninja-build xxd \
        patchelf pkg-config python3-pip xz-utils zstd libssl-dev \
        libass-dev libx264-dev libx265-dev liblcms2-dev \
        libluajit-5.1-dev libasound2-dev libpulse-dev \
        libx11-dev libxext-dev libxpresent-dev libxrandr-dev libxss-dev libxfixes-dev \
        libegl-dev libgl-dev libgbm-dev libdrm-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir "meson==${MESON_VERSION}"

# LunarG Vulkan SDK: headers, loader and shaderc newer than Ubuntu 22.04 ships.
RUN curl -fsSL "https://sdk.lunarg.com/sdk/download/${VULKAN_SDK_VERSION}/linux/vulkansdk-linux-x86_64-${VULKAN_SDK_VERSION}.tar.xz" \
        | tar -xJ -C /opt \
    && mv "/opt/${VULKAN_SDK_VERSION}" /opt/vulkan-sdk
ENV VULKAN_SDK=/opt/vulkan-sdk/x86_64

# The Linux SDK no longer ships the loader, and 22.04's (1.3.204) is too old for
# mpv's vulkan.pc check. Build the matching loader for build time only; at run
# time the binaries use the host's libvulkan1 (finalize.sh never bundles it).
RUN pip3 install --no-cache-dir cmake \
    && git clone --depth 1 --branch "vulkan-sdk-${VULKAN_SDK_VERSION}" \
        https://github.com/KhronosGroup/Vulkan-Loader.git /tmp/vulkan-loader \
    && cmake -S /tmp/vulkan-loader -B /tmp/vulkan-loader/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/vulkan-loader \
        -DCMAKE_INSTALL_LIBDIR=lib -DUPDATE_DEPS=ON \
        -DBUILD_WSI_WAYLAND_SUPPORT=OFF -DBUILD_WSI_XCB_SUPPORT=OFF -DBUILD_TESTS=OFF \
    && cmake --build /tmp/vulkan-loader/build \
    && cmake --install /tmp/vulkan-loader/build \
    && rm -rf /tmp/vulkan-loader

ENV PATH=$VULKAN_SDK/bin:$PATH \
    PKG_CONFIG_PATH=/opt/vulkan-loader/lib/pkgconfig:$VULKAN_SDK/lib/pkgconfig \
    LIBRARY_PATH=/opt/vulkan-loader/lib:$VULKAN_SDK/lib \
    LD_LIBRARY_PATH=/opt/vulkan-loader/lib:$VULKAN_SDK/lib \
    CPATH=$VULKAN_SDK/include

# Rust + cargo-c for libdovi and NVEnc's bundled libhdr10plus.
ENV CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup PATH=/opt/cargo/bin:$PATH
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path \
    && curl -fsSL "https://github.com/lu-zero/cargo-c/releases/download/${CARGO_C_VERSION}/cargo-c-x86_64-unknown-linux-musl.tar.gz" \
        | tar -xz -C /opt/cargo/bin

ENV CUDA_PATH=/usr/local/cuda \
    CCACHE_DIR=/ccache \
    MS_TARGET=linux MS_SRC_ROOT=/ms MS_PREFIX=${LINUX_PREFIX} MS_BUILD_ROOT=/build
WORKDIR /ms
COPY stack.conf ./
COPY scripts/common/lib.sh scripts/common/env.sh scripts/common/

COPY scripts/linux/build-libdovi.sh scripts/linux/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/libdovi \
    scripts/linux/build-libdovi.sh

COPY scripts/linux/build-dav1d.sh scripts/linux/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/dav1d \
    scripts/linux/build-dav1d.sh

COPY scripts/linux/build-svtav1.sh scripts/linux/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/svtav1 \
    scripts/linux/build-svtav1.sh

COPY scripts/common/build-vmaf.sh scripts/common/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/vmaf \
    scripts/common/build-vmaf.sh

COPY nv-codec-headers nv-codec-headers
COPY scripts/common/build-nv-codec-headers.sh scripts/common/
RUN scripts/common/build-nv-codec-headers.sh

COPY libplacebo libplacebo
COPY scripts/common/build-libplacebo.sh scripts/common/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/libplacebo \
    scripts/common/build-libplacebo.sh

COPY ffmpeg ffmpeg
COPY scripts/common/build-ffmpeg.sh scripts/common/
# No .git in the context, so hand FFmpeg its version string.
ARG FFMPEG_REVISION=unknown
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/ffmpeg \
    scripts/common/build-ffmpeg.sh

COPY mpv mpv
COPY scripts/common/build-mpv.sh scripts/common/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/mpv \
    scripts/common/build-mpv.sh

COPY nvenc nvenc
COPY scripts/common/build-nvenc.sh scripts/common/
RUN --mount=type=cache,target=/ccache --mount=type=cache,target=/build/nvenc \
    scripts/common/build-nvenc.sh

COPY scripts/linux/finalize.sh scripts/linux/
COPY --from=meta BUILDINFO.txt /tmp/BUILDINFO.txt
RUN scripts/linux/finalize.sh /tmp/BUILDINFO.txt

FROM scratch AS export
ARG LINUX_PREFIX=/opt/mediastack
COPY --from=builder ${LINUX_PREFIX} /
