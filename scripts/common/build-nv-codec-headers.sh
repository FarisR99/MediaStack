#!/usr/bin/env bash
# Install the NVIDIA codec headers (ffnvcodec) into the prefix.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
msg "nv-codec-headers -> $MS_PREFIX"
make -C "$MS_SRC_ROOT/nv-codec-headers" PREFIX="$MS_PREFIX" install
