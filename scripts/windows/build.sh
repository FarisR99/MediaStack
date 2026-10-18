#!/usr/bin/env bash
# Build the stack (except NVEncC) into out/ucrt64/prefix, the dev prefix.
# Usage: build.sh [project...]    e.g. build.sh mpv   to rebuild just mpv
set -euo pipefail
[[ "${MSYSTEM:-}" == UCRT64 ]] || { echo "error: run from the MSYS2 UCRT64 shell" >&2; exit 1; }
export MS_TARGET=ucrt64
exec "$(dirname "${BASH_SOURCE[0]}")/../common/build-all.sh" "$@"
