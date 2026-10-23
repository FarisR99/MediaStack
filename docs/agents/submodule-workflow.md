# Submodule workflow (agent notes)

Human version: `docs/daily-workflow.md` and `docs/updating-upstream.md`.

## Model

- Each submodule has two remotes. `origin` is the fork: fetch over HTTPS, push over SSH (set by `setup.sh`). `upstream` is the original project. nv-codec-headers has only `origin`, which is upstream itself.
- `.gitmodules` records the tracked branch (`submodule.<p>.branch`): `mediastack` for ffmpeg, libplacebo and nvenc, and `master` for mpv. nv-codec-headers has no branch because it's pinned to a tag.
- The superrepo records a **pin**: the exact commit of each submodule. `scripts/status.sh` compares HEAD against the pin, against `origin/<branch>` and against `upstream/master`.

## Making a change in a project

1. `scripts/status.sh`: the project must be on its tracked branch with a clean tree. If it isn't, run `scripts/setup.sh`. If it's still wrong, stop and tell the user.
2. Edit, build and test (`build-*.md`, `testing.md`).
3. Commit **inside the submodule**: `git -C <p> commit` with an `AI:` message (see `commit-conventions.md`).
4. Bump: `scripts/bump.sh --ai <p>`, plus `-- --trailer "Co-Authored-By: <Claude model> <noreply@anthropic.com>"` when the agent is Claude Code (other agents omit it). This stages the gitlink and commits it with a list of the commits it pulls in.
5. Don't push unless asked. When asked, push the submodule first (`git -C <p> push origin <branch>`), then the superrepo. `push.recurseSubmodules=check` refuses the superrepo push otherwise.

Superrepo-only changes (scripts, docs, `stack.conf`) are ordinary commits in the superrepo.

## Pulling fork commits pushed from elsewhere

The user also commits from other machines and pushes to the forks directly. `scripts/pull.sh [--bump] [project...]` fetches `origin` and fast-forwards each tracked branch to `origin/<branch>`. It never resets: if the branch has diverged, it reports that and leaves the branch alone. Then bump the pins (`scripts/bump.sh --ai <p>`, or `--bump`, which commits without the `AI:` prefix, so agents use bump.sh). If a pulled commit adds a fork feature, list it under the project's "Customisations" section.

## Merging upstream

`scripts/merge-upstream.sh <p>` fetches `upstream/master` and merges it with git's default message (no `AI:` prefix, by rule). On conflicts it stops. Resolve them keeping our customisations: look them up in the project's "Customisations" section in `agents/<p>/AGENTS.md`. Then `git -C <p> commit --no-edit`, rebuild, smoke-test, and bump.

Never rebase a tracked branch, and never force-push. Old superrepo pins must stay reachable on the forks.

After merging FFmpeg, check whether a library's major version changed (`lib*/version_major.h`). If it did, NVEncC's Windows DLL list needs updating (`architecture.md`).

After merging libplacebo, the API version changes (`libplacebo/meson.build`, top entry). Rebuild NVEncC too: it embeds the soname it loads.

## Bumping nv-codec-headers

`git -C nv-codec-headers fetch --tags && git -C nv-codec-headers checkout n<X.Y.Z.W>`, then `scripts/bump.sh --ai nv-codec-headers`. Check the driver requirement first (`agents/nv-codec-headers/AGENTS.md`).

## Repairs

| Symptom | Fix |
|---|---|
| Submodule on a detached HEAD | `scripts/setup.sh`. It checks out the tracked branch, fast-forwarding it to the pin when the pin is newer. |
| `status.sh` shows "behind pin" after `git pull` of the superrepo | `scripts/setup.sh` |
| "diverged from pin" | Someone committed on another machine and you committed locally. Merge `origin/<branch>` into the local branch inside the submodule; don't reset. |
| `status.sh` shows origin behind (`-N`) | Commits were pushed from elsewhere: `scripts/pull.sh <p>`, then bump |
| "branch not pushed" | Normal until the user pushes the fork. Mention it; don't push it yourself. |
| Agent docs stale | `scripts/sync-agent-docs.sh` |

## Adding a project

1. Add it to `STACK_PROJECTS` and add `UPSTREAM_<name>` in `stack.conf`.
2. `git submodule add -b <branch> <fork-url> <path>`
3. Write `agents/<name>/AGENTS.md` and add a row to the router in `AGENTS.md`.
4. Add `scripts/common/build-<name>.sh`, and add the project to the Dockerfile in dependency order.
5. Update the human docs: README table, `docs/customisations.md`, `docs/licensing.md`.
