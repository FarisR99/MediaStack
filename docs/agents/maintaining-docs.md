# Maintaining the docs (agent notes)

## The split (the user's standing rule)

- `README.md` and `docs/*.md` are **for humans**: prose, guided steps, copy-pasteable commands. Keep README to about one screen.
- `AGENTS.md`, `docs/agents/*.md` and `agents/<project>/AGENTS.md` are **for agents**: rules, routing, terse facts, file paths.
- `CLAUDE.md` contains only `@AGENTS.md`. Never put content in it.
- Don't duplicate: an agent doc links to the human doc for long explanations, and vice versa where useful.

## Root AGENTS.md

It's loaded on every prompt, so keep it short: repo map, golden rules, router, quick commands. Anything only some tasks need goes in `docs/agents/` with a router row. When you add a doc, add its router row in the same commit.

## Per-project docs

- The source of truth is `agents/<project>/AGENTS.md` in the superrepo.
- `scripts/sync-agent-docs.sh` (run by `setup.sh`) places them in the checkouts:
  - `<p>/CLAUDE.local.md` is a one-line `@../agents/<p>/AGENTS.md` import. Claude Code loads it on demand when you touch files in `<p>/`. It sits next to any upstream `CLAUDE.md` (nvenc has one) without replacing it.
  - `<p>/AGENTS.md` is a generated copy for Codex and similar tools. Where upstream already tracks an `AGENTS.md` (nvenc), it goes in `<p>/AGENTS.override.md` instead: upstream's text, then ours.
  - All of them go in the submodule's `info/exclude`, so they never show up in `git status` or get committed.
- After editing any `agents/*/AGENTS.md`, run `scripts/sync-agent-docs.sh`. `scripts/status.sh` warns when the copies are stale.
- Keep each project's **Customisations** section current whenever you add, change or drop a fork commit. It's how merge conflicts get resolved correctly. Mirror user-visible changes in `docs/customisations.md`.

## Upstream docs inside submodules

nvenc ships its own `CLAUDE.md`/`AGENTS.md` (in Japanese). Read them for NVEnc's internal conventions. Never edit them for our purposes, because they belong to upstream.

## Human doc index and benchmarks

- `docs/README.md` lists every human doc (not `docs/agents/`). When you add, rename or remove a `docs/*.md` page, update it in the same commit.
- `docs/benchmarks.md` holds the original-vs-fork numbers. When a change affects Anime4K upscaling speed in a fork, rerun the comparison as described in its "How these were measured" section (median of 3, same clip and settings) and update the tables, rather than adding numbers measured differently. Upstream mpv for the comparison is built from `git -C mpv archive upstream/master` into `out/ucrt64/src/mpv-upstream` with `build-mpv.sh`'s options, and run next to a copy of `dist`'s DLLs.
