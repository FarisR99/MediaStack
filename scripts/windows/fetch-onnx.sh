#!/usr/bin/env bash
# Download NVEncC's optional ONNX filter files (stack.conf NVENC_ONNX_*). Large,
# so nothing is fetched unless asked for; ask the user first.
#
#   scripts/windows/fetch-onnx.sh [--runtime] [--models <parts>]
#
#   --runtime        ONNX Runtime GPU + cuDNN + TensorRT DLLs (about 2 GB).
#                    package.sh then copies them next to NVEncC64.exe in dist.
#   --models <parts> Comma-separated model archives, or "all":
#                      deint_ddd     --vpp-onnx-deint (a few MB)
#                      main          most --vpp-onnx models (about 2 GB)
#                      fbcnn_nafnet  FBCNN/NAFNet restoration models (about 2 GB)
#                    Extracted into out/ucrt64/onnx-models; pass that folder
#                    to --vpp-onnx-model-dir.
#
# Downloads are cached (re-running fetches nothing new) and model archives are
# checked against the release's SHA256SUMS.txt.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
[[ "$MS_TARGET" == ucrt64 ]] || die "run from the MSYS2 UCRT64 shell"
cd "$STACK_ROOT"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

runtime=0
models=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime) runtime=1 ;;
        --models)  [[ $# -ge 2 ]] || usage; models=$2; shift ;;
        -h|--help) usage ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
[[ $runtime == 1 || -n "$models" ]] || usage
[[ "$models" == all ]] && models="deint_ddd,main,fbcnn_nafnet"

tar_exe="$(cygpath -S)/tar.exe"   # libarchive: reads 7z and zip

# fetch <url> <archive> <sha256 or empty>: download once into out/.
fetch() {
    local url=$1 archive=$2 sha=$3
    if [[ ! -f "$archive" ]]; then
        msg "Downloading $url"
        mkdir -p "$(dirname "$archive")"
        curl -fL --retry 3 -o "$archive.part" "$url"
        mv "$archive.part" "$archive"
    fi
    if [[ -n "$sha" ]]; then
        echo "$sha  $archive" | sha256sum -c --quiet - ||
            { rm -f "$archive"; die "checksum mismatch for $(basename "$archive"); deleted, re-run to retry"; }
    else
        warn "no checksum for $(basename "$archive"); not verified"
    fi
}

# extract <archive> <dir>: extract once (marker <dir>/.done-<archive name>).
extract() {
    local archive=$1 dir=$2 marker
    marker="$2/.done-$(basename "$1")"
    [[ -f "$marker" ]] && return
    mkdir -p "$dir"
    "$tar_exe" -xf "$(cygpath -w "$archive")" -C "$(cygpath -w "$dir")" ||
        die "could not extract $archive"
    touch "$marker"
}

cache=out/ucrt64/build/onnx
mkdir -p "$cache"
if [[ $runtime == 1 ]]; then
    archive=$cache/$(basename "$NVENC_ONNX_RUNTIME_URL")
    fetch "$NVENC_ONNX_RUNTIME_URL" "$archive" "$NVENC_ONNX_RUNTIME_SHA256"
    extract "$archive" out/ucrt64/build/onnx-runtime
    touch out/ucrt64/build/onnx-runtime/.done
    msg "ONNX Runtime DLLs ready; run scripts/windows/package.sh to put them in dist"
fi

if [[ -n "$models" ]]; then
    sums=$cache/SHA256SUMS-$NVENC_ONNX_MODELS_VERSION.txt
    [[ -f "$sums" ]] || curl -fsSL -o "$sums" "$NVENC_ONNX_MODELS_RELEASE/SHA256SUMS.txt"
    for part in ${models//,/ }; do
        case "$part" in
            deint_ddd|main|fbcnn_nafnet) ;;
            *) die "unknown model archive: $part (deint_ddd, main, fbcnn_nafnet or all)" ;;
        esac
        name=onnx_models_${NVENC_ONNX_MODELS_VERSION}_$part.zip
        sha=$(awk -v n="$name" '$2 == n { print $1 }' "$sums")
        [[ -n "$sha" ]] || die "$name is not in the release's SHA256SUMS.txt"
        fetch "$NVENC_ONNX_MODELS_RELEASE/$name" "$cache/$name" "$sha"
        extract "$cache/$name" out/ucrt64/onnx-models
    done
    msg "Models in $(cygpath -w "$STACK_ROOT/out/ucrt64/onnx-models"); use --vpp-onnx-model-dir with that folder"
fi
