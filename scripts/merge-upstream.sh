#!/usr/bin/env bash
# Merge upstream into a project's custom branch (we merge, never rebase, so
# pinned SHAs stay reachable). Merge commits keep git's default message and
# are never given the "AI:" prefix.
#
# Usage: merge-upstream.sh <project>
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
cd "$STACK_ROOT"

p=${1:-}
[[ -n "$p" ]] || die "usage: $0 <project>"
check_project "$p"
[[ -n "$(upstream_url "$p")" ]] || die "$p has no upstream remote (it is pinned to an upstream tag; bump it by checking out a newer tag)"
branch=$(tracked_branch "$p")
[[ "$(git -C "$p" symbolic-ref -q --short HEAD)" == "$branch" ]] || die "$p is not on $branch; run scripts/setup.sh"
[[ -z "$(git -C "$p" status --porcelain --untracked-files=no)" ]] || die "$p has uncommitted changes"

msg "Fetching $p upstream"
git -C "$p" fetch upstream "$UPSTREAM_BRANCH"
count=$(git -C "$p" rev-list --count "HEAD..upstream/$UPSTREAM_BRANCH")
if (( count == 0 )); then
    msg "$p is already up to date with upstream/$UPSTREAM_BRANCH"
    exit 0
fi

msg "Merging $count upstream commits into $p/$branch"
if ! git -C "$p" merge --no-edit "upstream/$UPSTREAM_BRANCH"; then
    cat >&2 <<MSG

Merge conflicts in $p. Resolve them, then:
    git -C $p add <files> && git -C $p commit --no-edit
or abort with:
    git -C $p merge --abort
MSG
    exit 1
fi

cat <<MSG

Merged. Next:
  1. rebuild and smoke-test (docs/testing.md)
  2. push the fork:  git -C $p push origin $branch
  3. bump the pin:   scripts/bump.sh $p
MSG
