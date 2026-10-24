# MediaStack: agent guide

MediaStack is a superrepo that pins and builds five media projects as one stack. Most code changes happen inside a submodule; the superrepo itself holds the scripts, the shared build config and the docs.

This file is always loaded, so it stays short. **Read the routed doc before you act on a topic it covers.** README.md and `docs/*.md` are written for humans; `docs/agents/` and `agents/` are written for you.

## Repo map

| Path | What it is |
|---|---|
| `ffmpeg/` | FarisR99/FFmpeg, branch `mediastack` (upstream FFmpeg/FFmpeg master) |
| `libplacebo/` | FarisR99/libplacebo, branch `mediastack` (upstream haasn/libplacebo master) |
| `nvenc/` | FarisR99/NVEnc, branch `mediastack` (upstream rigaya/NVEnc master); builds NVEncC |
| `mpv/` | FarisR99/mpv, branch `master` (the fork itself; upstream mpv-player/mpv) |
| `nv-codec-headers/` | FFmpeg/nv-codec-headers, pinned to a release tag; not forked, never modified |
| `stack.conf` | Single source of truth: project list, upstream URLs, tool/CUDA/SDK versions |
| `scripts/` | `setup.sh`, `status.sh`, `pull.sh`, `bump.sh`, `merge-upstream.sh`, `sync-agent-docs.sh`; `common/` (shared build scripts), `windows/`, `linux/` |
| `agents/<project>/AGENTS.md` | Per-project agent docs (source of truth; copied into each checkout) |
| `docs/agents/` | On-demand agent topic docs (router below) |
| `out/` | Build trees, prefixes, packages (gitignored) |

Build order (each one links the previous ones from the stack prefix): nv-codec-headers → libdovi (Linux only) → libplacebo → FFmpeg → mpv → NVEncC.

## Golden rules

1. **Work on the tracked branch, never on a detached HEAD.** That's `mediastack`, or `master` for mpv. If a submodule is detached, run `scripts/setup.sh`.
2. **Commit inside the submodule first, then bump the pin** in the superrepo with `scripts/bump.sh --ai <project>`. A superrepo commit must never point at a submodule commit that exists only on your machine without saying so. `push.recurseSubmodules=check` blocks such pushes.
3. **Never push** a fork or the superrepo unless the user asks.
4. **Never commit agent docs into a fork.** `<project>/AGENTS.md`, `AGENTS.override.md` and `CLAUDE.local.md` are generated, and git-excluded. Edit `agents/<project>/AGENTS.md`, then run `scripts/sync-agent-docs.sh`.
5. **Upstream changes come in by merge, never by rebase** (`scripts/merge-upstream.sh <project>`). Don't rewrite published history on any branch.
6. **Commit messages:** agent-authored commits start with `AI: <area>: <summary>`, in every repo including this one. Add a `Co-Authored-By:` trailer **only when the agent is Claude Code** (naming the Claude model); other harnesses and models must omit it, because GitHub resolves `noreply@anthropic.com` to the claude account. Merge commits keep git's default message, with no `AI:` prefix. Details: `docs/agents/commit-conventions.md`.
7. **Say what you didn't test.** Windows-only code can't be built from WSL/Linux. Say so in the commit body, e.g. "Not yet built on Windows."
8. **FFmpeg is built GPL + nonfree.** Never publish or redistribute the binaries.
9. Keep `stack.conf` the only place versions are written down. Scripts and the Dockerfile read from it.
10. **All build output goes under `out/`**, the only build location that is gitignored. Never build in-tree: no `meson setup build` or `./configure` inside a submodule, and no `build/` dir at the root. Use the stack scripts, or point `meson setup` at `out/<target>/build/<project>`. If a stray build directory or generated file shows up in `git status`, treat it as a bug. Find what created it and fix that, then delete the stray output after checking what it contains. Never paper over it by adding it to `.gitignore` or `info/exclude`.
11. Respect each upstream's style inside its tree (see the per-project doc). Keep the diff against upstream small and self-contained, so that merges stay cheap.

## Router

Read the matching doc **before** starting work of that kind.

| When you are... | Read |
|---|---|
| Changing anything under `ffmpeg/` | `agents/ffmpeg/AGENTS.md` |
| Changing anything under `libplacebo/` | `agents/libplacebo/AGENTS.md` |
| Changing anything under `mpv/` | `agents/mpv/AGENTS.md` |
| Changing anything under `nvenc/` | `agents/nvenc/AGENTS.md` |
| Touching `nv-codec-headers/` (bumping the tag) | `agents/nv-codec-headers/AGENTS.md` |
| Working out how the pieces talk to each other (vf_gpu → hw frames → encoders, NVEncC ↔ libplacebo) | `docs/agents/architecture.md` |
| Branching, committing, bumping pins, merging upstream, fixing detached submodules | `docs/agents/submodule-workflow.md` |
| Writing a commit message | `docs/agents/commit-conventions.md` |
| Building or packaging on Windows (MSYS2 UCRT64, MSVC NVEncC) | `docs/agents/build-windows.md` |
| Building in Docker, exporting or installing on a Linux host | `docs/agents/build-linux-docker.md` |
| Changing or packaging the Anime4K shader presets | `docs/anime4k-presets.md` |
| Changing FFmpeg configure flags or another project's build options | `docs/agents/build-config.md` |
| Verifying a change (smoke tests) | `docs/agents/testing.md` |
| A build or runtime failure | `docs/agents/troubleshooting.md` |
| Editing these docs, or adding a project | `docs/agents/maintaining-docs.md` |

## Quick commands

```bash
scripts/setup.sh                 # after clone or pull: init, align branches, copy agent docs
scripts/status.sh [--fetch]      # branch / pin / push / upstream state of every submodule
scripts/pull.sh [project...]     # fast-forward forks to commits pushed to origin from elsewhere
scripts/bump.sh --ai <project>   # record new pins (agents: always pass --ai)
scripts/linux/export.sh          # Docker build -> out/linux/mediastack-<sha>.tar.zst
```
