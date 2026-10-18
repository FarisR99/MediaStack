# Updating from upstream

Your forks keep their custom commits on top of the upstream project. To pick up new upstream work, **merge** upstream into your branch. Don't rebase: merging keeps every commit MediaStack has ever pinned reachable, so old builds stay reproducible and nobody has to force-push.

## Merge one project

```bash
scripts/merge-upstream.sh libplacebo
```

This fetches the upstream `master` and merges it into your branch.

- **No conflicts:** you're done merging. The script prints the next steps.
- **Conflicts:** it stops and tells you. Fix the files, then:
  ```bash
  git -C libplacebo add <files>
  git -C libplacebo commit --no-edit
  ```
  If you'd rather back out: `git -C libplacebo merge --abort`.

  [What's customised](customisations.md) lists what your fork changes, which helps decide which side of a conflict to keep.

## After merging

1. **Rebuild**, including everything that depends on the project:
   - libplacebo → also FFmpeg, mpv and NVEncC
   - FFmpeg → also mpv and NVEncC
2. **Test** ([testing](testing.md)).
3. **Push the fork:** `git -C libplacebo push`
4. **Update the pin:** `scripts/bump.sh libplacebo`, then `git push`.

## Things that need extra care

- **FFmpeg major version bumps.** When upstream FFmpeg bumps a library's major version (e.g. `avcodec-63` → `avcodec-64`), NVEncC on Windows looks for the old DLL names, and that list has to be updated in the NVEnc fork. An agent can do this; ask it to "check NVEncC's FFmpeg DLL names after the FFmpeg merge".
- **libplacebo API changes.** Every libplacebo update changes its API number and its library file name. NVEncC handles that automatically through a fix in the fork, but it must be **rebuilt**.
- **mpv** already lives on your fork's `master`. The same script works: `scripts/merge-upstream.sh mpv`.
- **nv-codec-headers** isn't merged; it moves to a newer release tag. Newer tags need newer NVIDIA drivers on every machine you use. See `agents/nv-codec-headers/AGENTS.md`, or ask an agent to bump it.
