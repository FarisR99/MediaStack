#!/usr/bin/env bash
# Initialise and align the MediaStack checkout. Idempotent: run it after every
# clone and after every `git pull` of the superrepo.
#
# For each submodule:
#   - initialise it if needed and make sure the pinned commit is present
#   - check out its tracked branch (.gitmodules 'branch') instead of a detached
#     HEAD, fast-forwarding the branch to the pin when the pin is newer
#   - add the 'upstream' remote and an SSH push URL for origin
# Then configure the superrepo and copy agent docs into the checkouts.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
cd "$STACK_ROOT"

msg "Superrepo git config"
git config push.recurseSubmodules check   # refuse to push pins whose commits aren't on the forks
git config status.submoduleSummary true
git config diff.submodule log
if [[ -n "${MSYSTEM:-}" || "${OS:-}" == Windows_NT ]]; then
    git config core.longpaths true
fi

git submodule sync -q

for p in $STACK_PROJECTS; do
    msg "$p"
    if [[ ! -e "$p/.git" ]]; then
        git submodule update --init --recursive -- "$p"
    fi

    pin=$(pinned_sha "$p")
    if ! git -C "$p" cat-file -e "$pin^{commit}" 2>/dev/null; then
        git -C "$p" fetch -q origin
    fi

    up=$(upstream_url "$p")
    if [[ -n "$up" ]]; then
        if git -C "$p" remote get-url upstream >/dev/null 2>&1; then
            git -C "$p" remote set-url upstream "$up"
        else
            git -C "$p" remote add upstream "$up"
        fi
        # Version strings (FFmpeg's N-<count>-g<sha>, mpv's v0.x) come from
        # upstream tags, which forks often lack.
        if [[ -z "$(git -C "$p" tag -l | head -n 1)" ]]; then
            git -C "$p" fetch -q --tags upstream "$UPSTREAM_BRANCH"
        fi
    fi

    origin=$(git -C "$p" remote get-url origin)
    if [[ "$origin" == https://github.com/FarisR99/* ]]; then
        git -C "$p" remote set-url --push origin "git@github.com:${origin#https://github.com/}"
    fi

    branch=$(tracked_branch "$p")
    if [[ -z "$branch" ]]; then
        # Pinned to a tag (nv-codec-headers): just check out the pin.
        git submodule update --init -q -- "$p"
        continue
    fi

    if ! git -C "$p" show-ref -q --verify "refs/heads/$branch"; then
        git -C "$p" branch -q "$branch" "$pin"
    fi
    tip=$(git -C "$p" rev-parse "refs/heads/$branch")
    if [[ "$tip" != "$pin" ]]; then
        if git -C "$p" merge-base --is-ancestor "$tip" "$pin"; then
            # Pin is newer (e.g. after pulling the superrepo): fast-forward.
            if [[ "$(git -C "$p" symbolic-ref -q --short HEAD)" == "$branch" ]]; then
                git -C "$p" merge -q --ff-only "$pin"
            else
                git -C "$p" branch -q -f "$branch" "$pin"
            fi
        elif git -C "$p" merge-base --is-ancestor "$pin" "$tip"; then
            warn "$p: $branch is ahead of the pin (unbumped local work); leaving it"
        else
            warn "$p: $branch and the pin have diverged; leaving $branch alone, resolve by hand"
        fi
    fi
    if [[ "$(git -C "$p" symbolic-ref -q --short HEAD)" != "$branch" ]]; then
        if [[ -n "$(git -C "$p" status --porcelain --untracked-files=no)" ]]; then
            warn "$p: uncommitted changes; not switching to $branch"
        else
            git -C "$p" checkout -q "$branch"
        fi
    fi
    if git -C "$p" show-ref -q --verify "refs/remotes/origin/$branch"; then
        git -C "$p" branch -q --set-upstream-to="origin/$branch" "$branch"
    fi
    git -C "$p" submodule update --init --recursive -q
done

"$STACK_ROOT/scripts/sync-agent-docs.sh"
msg "Done. Run scripts/status.sh for an overview."
