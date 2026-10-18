#!/usr/bin/env bash
# One-screen overview of every submodule: branch, pin, local/remote drift.
#
# Usage: status.sh [--fetch]
#   --fetch  fetch origin and upstream first (otherwise uses what's already fetched)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
cd "$STACK_ROOT"

if [[ "${1:-}" == --fetch ]]; then
    for p in $STACK_PROJECTS; do
        git -C "$p" fetch -q --all 2>/dev/null || warn "$p: fetch failed"
    done
fi

printf '%-17s %-12s %-9s %-22s %-20s %-16s %s\n' PROJECT BRANCH HEAD PIN ORIGIN UPSTREAM TREE
for p in $STACK_PROJECTS; do
    if [[ ! -e "$p/.git" ]]; then
        printf '%-17s not initialised (run scripts/setup.sh)\n' "$p"
        continue
    fi
    head=$(git -C "$p" rev-parse HEAD)
    pin=$(pinned_sha "$p")
    branch=$(git -C "$p" symbolic-ref -q --short HEAD || git -C "$p" describe --tags --exact-match 2>/dev/null || echo detached)
    tracked=$(tracked_branch "$p")

    if [[ "$head" == "$pin" ]]; then
        pinstate="= pin"
    elif git -C "$p" merge-base --is-ancestor "$pin" "$head" 2>/dev/null; then
        pinstate="+$(git -C "$p" rev-list --count "$pin..$head") unbumped"
    elif git -C "$p" merge-base --is-ancestor "$head" "$pin" 2>/dev/null; then
        pinstate="-$(git -C "$p" rev-list --count "$head..$pin") behind pin"
    else
        pinstate="diverged from pin"
    fi

    origin="-"
    if [[ -n "$tracked" ]]; then
        if git -C "$p" show-ref -q --verify "refs/remotes/origin/$tracked"; then
            read -r behind ahead < <(git -C "$p" rev-list --left-right --count "origin/$tracked...HEAD")
            origin="+$ahead/-$behind"
            (( ahead > 0 )) && origin+=" unpushed"
        else
            origin="branch not pushed"
        fi
    fi

    upstream="-"
    if git -C "$p" show-ref -q --verify "refs/remotes/upstream/$UPSTREAM_BRANCH"; then
        upstream="-$(git -C "$p" rev-list --count "HEAD..upstream/$UPSTREAM_BRANCH") to merge"
    fi

    tree=clean
    [[ -n "$(git -C "$p" status --porcelain)" ]] && tree=dirty
    [[ -n "$tracked" && "$branch" != "$tracked" ]] && tree+=" (expected $tracked)"

    printf '%-17s %-12s %-9s %-22s %-20s %-16s %s\n' "$p" "$branch" "${head:0:8}" "$pinstate" "$origin" "$upstream" "$tree"
done

echo
if ! "$STACK_ROOT/scripts/sync-agent-docs.sh" --check >/dev/null; then
    warn "agent docs in the checkouts are stale; run scripts/sync-agent-docs.sh"
fi
superdirty=$(git status --porcelain --ignore-submodules=all)
[[ -n "$superdirty" ]] && echo "superrepo has uncommitted changes:" && echo "$superdirty"
exit 0
