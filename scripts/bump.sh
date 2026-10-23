#!/usr/bin/env bash
# Record the current HEAD of submodules as the new pins and commit, listing
# the commits each pin pulls in.
#
# Usage: bump.sh [--ai] [project...] [-- <extra git commit args>]
#   project  defaults to every submodule whose HEAD differs from its pin
#   --ai     prefix the subject with "AI: " (agent-authored commits)
#   e.g. scripts/bump.sh --ai nvenc -- --no-verify
#   Claude Code also passes -- --trailer "Co-Authored-By: <Claude model> <noreply@anthropic.com>"
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
cd "$STACK_ROOT"

prefix=""
projects=()
while (( $# )); do
    case "$1" in
        --ai) prefix="AI: " ;;
        --) shift; break ;;
        *) check_project "$1"; projects+=("$1") ;;
    esac
    shift
done
if (( ${#projects[@]} == 0 )); then
    for p in $STACK_PROJECTS; do
        [[ "$(git -C "$p" rev-parse HEAD)" != "$(git rev-parse -q --verify "HEAD:$p" || true)" ]] && projects+=("$p")
    done
fi
(( ${#projects[@]} )) || { msg "Nothing to bump"; exit 0; }

body=""
for p in "${projects[@]}"; do
    [[ -z "$(git -C "$p" status --porcelain --untracked-files=no)" ]] || die "$p has uncommitted changes; commit them in the submodule first"
    old=$(git rev-parse -q --verify "HEAD:$p" || true)
    new=$(git -C "$p" rev-parse HEAD)
    branch=$(tracked_branch "$p")
    if [[ -n "$branch" ]] && ! git -C "$p" branch -r --contains "$new" 2>/dev/null | grep -q "origin/"; then
        warn "$p ${new:0:10} is not on origin yet; push it before pushing the superrepo"
    fi
    git add -- "$p"
    body+="$p: ${old:0:10} -> ${new:0:10}"$'\n'
    if [[ -n "$old" ]] && git -C "$p" cat-file -e "$old^{commit}" 2>/dev/null; then
        log=$(git -C "$p" log --oneline --no-decorate --first-parent "$old..$new" | head -n 50)
        n=$(git -C "$p" rev-list --count --first-parent "$old..$new")
        body+="$log"$'\n'
        (( n > 50 )) && body+="... and $((n - 50)) more"$'\n'
    fi
    body+=$'\n'
done

subject="${prefix}bump: $(printf '%s, ' "${projects[@]}")"
subject=${subject%, }
printf '%s\n\n%s' "$subject" "$body" | git commit -q -F - "$@"
git log --oneline -1
