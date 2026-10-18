# Build environment shared by the per-project build scripts. Source it.
#
# Inputs (environment, all optional):
#   MS_TARGET      ucrt64 | linux             (default: detected)
#   MS_SRC_ROOT    where the project sources are (default: the superrepo)
#   MS_PREFIX      install prefix              (default: out/<target>/prefix)
#   MS_BUILD_ROOT  out-of-tree build dirs      (default: out/<target>/build)
#   MS_BUILDTYPE   meson buildtype             (default: release)
#   MS_JOBS        parallel jobs               (default: nproc)
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MS_TARGET=${MS_TARGET:-$(detect_target)}
MS_SRC_ROOT=${MS_SRC_ROOT:-$STACK_ROOT}
MS_PREFIX=${MS_PREFIX:-$STACK_ROOT/out/$MS_TARGET/prefix}
MS_BUILD_ROOT=${MS_BUILD_ROOT:-$STACK_ROOT/out/$MS_TARGET/build}
MS_BUILDTYPE=${MS_BUILDTYPE:-release}
MS_JOBS=${MS_JOBS:-$(jobs_count)}
export MS_TARGET MS_SRC_ROOT MS_PREFIX MS_BUILD_ROOT MS_BUILDTYPE MS_JOBS

case "$MS_TARGET" in
    ucrt64|linux) ;;
    *) die "unsupported target '$MS_TARGET' (use the MSYS2 UCRT64 shell on Windows)" ;;
esac

# Stack libraries win over pacman/apt copies.
export PKG_CONFIG_PATH="$MS_PREFIX/lib/pkgconfig:$MS_PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PATH="$MS_PREFIX/bin:$PATH"
if [[ "$MS_TARGET" == linux ]]; then
    export LD_LIBRARY_PATH="$MS_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

if command -v ccache >/dev/null 2>&1 && [[ -z "${MS_NO_CCACHE:-}" ]]; then
    MS_CCACHE=1
else
    MS_CCACHE=
fi

# have_cuda: true if an nvcc is usable (enables FFmpeg's nonfree CUDA filters).
have_cuda() {
    command -v nvcc >/dev/null 2>&1 || [[ -x "${CUDA_PATH:-/usr/local/cuda}/bin/nvcc" ]]
}

# meson_build <project> <args...>: configure (once) + build + install a meson project.
meson_build() {
    local p=$1; shift
    local src="$MS_SRC_ROOT/$p" build="$MS_BUILD_ROOT/$p"
    if [[ ! -f "$build/build.ninja" ]]; then
        meson setup "$build" "$src" --prefix="$MS_PREFIX" --libdir=lib \
            --buildtype="$MS_BUILDTYPE" "$@"
    else
        meson configure "$build" "$@" >/dev/null
    fi
    meson compile -C "$build" -j "$MS_JOBS"
    meson install -C "$build" --quiet
}
