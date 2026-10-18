# Daily workflow

## How the pieces fit

Each project folder (`ffmpeg/`, `mpv/`, ...) is its own git repository, a *submodule*, with its own history, branches and remote (your fork). MediaStack itself only records **which commit** of each project goes together. That record is called the *pin*.

So every change is two steps: commit in the project, then update the pin in MediaStack.

## Making a change

1. **Check the state.**
   ```bash
   scripts/status.sh
   ```
   The project should be on its branch (`mediastack`, or `master` for mpv) and `clean`.

2. **Edit, build and test** as usual ([Windows](building-windows.md), [Linux](building-linux.md), [testing](testing.md)).

3. **Commit inside the project:**
   ```bash
   cd ffmpeg
   git add -p
   git commit -m "avcodec/nvenc: ..."
   cd ..
   ```

4. **Update the pin** in MediaStack:
   ```bash
   scripts/bump.sh ffmpeg
   ```
   This creates a MediaStack commit like `bump: ffmpeg`, listing the project commits it brings in.

5. **Push when you're ready.** Push the project first, then MediaStack:
   ```bash
   git -C ffmpeg push
   git push
   ```
   If you forget the first push, the second one stops and tells you. That protects other PCs from getting a pin they can't fetch.

Changes to MediaStack's own files (scripts, docs, `stack.conf`) are ordinary commits in the top-level repo.

## On another PC: getting the latest

```bash
git pull
scripts/setup.sh
```

`setup.sh` moves each project to the newly pinned commit, staying on its branch. Then rebuild.

## Seeing what's going on

```bash
scripts/status.sh           # quick overview, using what's already fetched
scripts/status.sh --fetch   # fetch from forks and upstreams first
```

## Agents

Agents follow the same flow, guided by `AGENTS.md`. Their commits are marked `AI: ...` so you can always tell them apart (`git log --grep '^AI:'`). Agents never push unless you ask them to.
