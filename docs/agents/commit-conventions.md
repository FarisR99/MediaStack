# Commit conventions (agent notes)

These apply in **every** repo of the stack, including the superrepo.

## Agent-authored commits

```
AI: <area>: <imperative summary, lower case after the colon>

<Why the change is needed and what it does, wrapped prose. Mention what was
and wasn't tested, e.g. "Not yet built on Windows.">

Co-Authored-By: <Claude model> <noreply@anthropic.com>
```

The `Co-Authored-By` trailer is **only for Claude Code**. Name the Claude
model that ran the session, as the existing commits do (`Claude Opus 5.5`).
Any other harness or model (OpenCode, DeepSeek, a local LLM) must omit it:
GitHub resolves `noreply@anthropic.com` to the `claude` account, so the
commit would be credited to Claude even though it never ran.

- `<area>` follows the target project's own convention. For mpv that's the file or subsystem (`vf_gpu`, `vo_lavc`, `ra_pl`; see `mpv/DOCS/contribute.md`). FFmpeg uses `lavc/nvenc` or `avfilter/vf_libplacebo`. libplacebo uses `vulkan`, `renderer` and so on. NVEnc uses the file stem (`libplacebo`, `avutil`). In the superrepo the areas are `scripts`, `docs`, `linux`, `windows`, `stack`, `bump`, and `repo`.
- One logical change per commit, so that upstream merges and cherry-picks stay easy.
- Superrepo pin bumps: `scripts/bump.sh --ai ...` produces `AI: bump: <projects>` with the commit list.

## Merge commits

Merge commits keep git's default message (`Merge remote-tracking branch 'upstream/master' into mediastack`, etc.) with **no `AI:` prefix**, even when an agent ran the merge. A conflict-resolution note in the body is fine.

## Commits by the user

The user's own commits don't need the prefix. Never rewrite them.

## mpv specifics

mpv's `ci/lint-commit-msg.py` enforces upstream's format (`area: summary`, line lengths). The fork's `AI: ` prefix is a deliberate deviation for fork-only commits. Keep the rest of the message lint-clean, so the commit can be upstreamed by dropping the prefix.

## Staging in the superrepo

Stage paths explicitly (`git add <paths>`). Never use `git commit -a` / `-am` in the superrepo: it also stages any moved submodule gitlinks, which hides a pin bump inside an unrelated commit. That happened once (`787beac` carried an mpv bump). Pin changes go through `scripts/bump.sh`.
