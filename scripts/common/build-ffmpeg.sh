#!/usr/bin/env bash
# Build FFmpeg (shared, GPL + nonfree) into the prefix. Needs libplacebo and
# nv-codec-headers installed there first.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
msg "ffmpeg -> $MS_PREFIX"

# libvmaf isn't a stack project; build it here when the prefix lacks the pinned version.
if [[ "$(cat "$MS_PREFIX/share/mediastack/vmaf-version" 2>/dev/null)" != "$VMAF_VERSION" ]]; then
    "$(dirname "${BASH_SOURCE[0]}")/build-vmaf.sh"
fi

src="$MS_SRC_ROOT/ffmpeg"
build="$MS_BUILD_ROOT/ffmpeg"
mkdir -p "$build"

args=(
    --prefix="$MS_PREFIX"
    --enable-shared --disable-static
    --enable-gpl --enable-version3 --enable-nonfree
    --disable-doc --disable-debug
    --enable-libplacebo --enable-vulkan   # Vulkan shaders are compiled at build time with glslc
    --enable-ffnvcodec --enable-nvenc --enable-nvdec --enable-cuvid
    --enable-libass --enable-libdav1d --enable-libx264 --enable-libx265 --enable-libvmaf
)
case "$MS_TARGET" in
    ucrt64)
        # CUDA filters come from --enable-cuda-llvm (clang, autodetected): nvcc
        # would need MSVC's cl.exe as host compiler, which MinGW builds lack.
        args+=(--enable-d3d11va --enable-dxva2 --enable-libvpl --enable-amf --enable-cuda-llvm
               --enable-lcms2)   # Ubuntu 22.04's lcms2 (2.12) is older than FFmpeg's 2.13 minimum
        ;;
    linux)
        # CUDA filters (scale_cuda, ...) via nvcc are what makes this build nonfree.
        if have_cuda; then
            cuda=${CUDA_PATH:-/usr/local/cuda}
            args+=(--enable-cuda-nvcc --nvcc="$cuda/bin/nvcc"
                   --extra-cflags="-I$cuda/include" --extra-ldflags="-L$cuda/lib64")
        else
            warn "nvcc not found: building without --enable-cuda-nvcc"
        fi
        ;;
esac
[[ -n "$MS_CCACHE" ]] && args+=(--cc="ccache gcc" --cxx="ccache g++")

# Reconfigure when the flags change, or when an upstream merge changes configure
# or the component lists it generates config.h and *_list.c from (configure is
# slow, so skip it otherwise).
stamp="$build/.mediastack-configure-args"
want="${args[*]} $(cd "$src" && cat configure libavfilter/allfilters.c libavdevice/alldevices.c \
    libavformat/allformats.c libavformat/protocols.c libavcodec/allcodecs.c libavcodec/parsers.c \
    libavcodec/bitstream_filters.c libavcodec/hwaccels.h | sha1sum | cut -d' ' -f1)"
if [[ ! -f "$build/ffbuild/config.mak" || "$(cat "$stamp" 2>/dev/null)" != "$want" ]]; then
    if ! (cd "$build" && "$src/configure" "${args[@]}"); then
        tail -n 40 "$build/ffbuild/config.log" >&2
        die "ffmpeg configure failed (full log: $build/ffbuild/config.log)"
    fi
    printf '%s' "$want" > "$stamp"
fi
make_args=()
# Builds without .git (Docker) get their version string from FFMPEG_REVISION.
[[ -n "${FFMPEG_REVISION:-}" ]] && make_args+=(REVISION="$FFMPEG_REVISION")
# FFmpeg only refreshes its version string when .git/logs/HEAD changes, which
# doesn't exist in a submodule (.git is a file). version.sh rewrites
# ffversion.h only if the version changed, so always let it run.
rm -f "$build/.version"
make -C "$build" -j "$MS_JOBS" "${make_args[@]}"
make -C "$build" install "${make_args[@]}"
