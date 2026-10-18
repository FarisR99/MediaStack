#!/usr/bin/env bash
# Build the whole stack in dependency order, or only the named projects.
# Usage: build-all.sh [project...]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"

projects=("$@")
if (( ${#projects[@]} == 0 )); then
    read -ra projects <<< "$STACK_PROJECTS"
fi
for p in "${projects[@]}"; do
    check_project "$p"
    if [[ "$p" == nvenc && "$MS_TARGET" != linux ]]; then
        warn "skipping nvenc: on Windows build it from a VS Developer PowerShell (scripts/windows/nvencc-spike.ps1)"
        continue
    fi
    "$STACK_ROOT/scripts/common/build-$p.sh"
done
msg "Built: ${projects[*]} -> $MS_PREFIX"
