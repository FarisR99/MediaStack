#!/usr/bin/env bash
# Bring in commits pushed to the forks from elsewhere (another PC, the GitHub
# UI): fetch origin and fast-forward each tracked branch to origin/<branch>.
# Never resets or rebases. A diverged branch is reported and left alone.
#
# Usage: pull.sh [--bump] [project...]
#   project  defaults to every submodule that tracks a branch
#   --bump   record the new pins afterwards (scripts/bump.sh)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
cd "$STACK_ROOT"

bump=0
projects=()
for a in "$@"; do
    case "$a" in
        --bump) bump=1 ;;
        *) check_project "$a"; projects+=("$a") ;;
    esac
done
if (( ${#projects[@]} == 0 )); then
    for p in $STACK_PROJECTS; do
        [[ -n "$(tracked_branch "$p")" ]] && projects+=("$p")
    done
fi

moved=()
failed=0
for p in "${projects[@]}"; do
    branch=$(tracked_branch "$p")
    if [[ -z "$branch" ]]; then
        warn "$p is pinned to an upstream tag, not a branch; skipping"
        continue
    fi
    if [[ "$(git -C "$p" symbolic-ref -q --short HEAD)" != "$branch" ]]; then
        warn "$p is not on $branch; run scripts/setup.sh"; failed=1; continue
    fi
    git -C "$p" fetch -q origin "$branch"
    behind=$(git -C "$p" rev-list --count "HEAD..origin/$branch")
    ahead=$(git -C "$p" rev-list --count "origin/$branch..HEAD")
    if (( behind == 0 )); then
        note=""
        (( ahead )) && note=" ($ahead local commits not pushed)"
        msg "$p: up to date with origin/$branch$note"
        continue
    fi
    if (( ahead > 0 )); then
        warn "$p has diverged from origin/$branch ($ahead local, $behind remote). Merge it yourself:"
        warn "    git -C $p merge origin/$branch"
        failed=1; continue
    fi
    # --ff-only refuses rather than clobbering uncommitted changes it would touch.
    if git -C "$p" merge -q --ff-only "origin/$branch"; then
        msg "$p: fast-forwarded $behind commits to origin/$branch"
        moved+=("$p")
    else
        warn "$p: fast-forward refused (uncommitted changes in the way?)"; failed=1
    fi
done

if (( ${#moved[@]} )); then
    if (( bump )); then
        scripts/bump.sh "${moved[@]}"
    else
        echo
        echo "The superrepo pins are now behind. To record them: scripts/bump.sh ${moved[*]}"
    fi
fi
exit "$failed"
