# MediaStack docs

Start with [Getting started](getting-started.md) on a new machine, then the build page for your platform. The rest you'll need as you go.

## Setting up and building

| Page | Read it when |
|---|---|
| [Getting started](getting-started.md) | You're setting up a new machine: prerequisites, first clone, first push of the forks. |
| [Building on Windows](building-windows.md) | You're building on Windows: MSYS2 UCRT64 for FFmpeg, libplacebo and mpv, Visual Studio for NVEncC, and packaging a portable folder. |
| [Building on Linux](building-linux.md) | You're building on Linux: the Docker build, exporting the result, and installing it on Ubuntu hosts or WSL. |

## Working on the stack

| Page | Read it when |
|---|---|
| [Daily workflow](daily-workflow.md) | You're changing a project: committing in a fork, recording the new pin, checking status, pushing. |
| [Updating from upstream](updating-upstream.md) | You're bringing in upstream changes: merging, resolving conflicts, rebuilding. |
| [Testing](testing.md) | You've built something and want to check it works end to end. |
| [Troubleshooting](troubleshooting.md) | A build or run has failed. |

## What you get

| Page | Read it when |
|---|---|
| [What's customised](customisations.md) | You want to know what each fork changes compared to upstream, and why. |
| [Anime4K presets](anime4k-presets.md) | You want the combined low/medium/high/ultra shader files, or to bump the Anime4K pin. |
| [Benchmarks](benchmarks.md) | You want to see how much faster the forks are than the originals for Anime4K upscaling, and the fastest settings for each tool. |
| [Licensing](licensing.md) | You're wondering what you may share: MediaStack is MIT, but the FFmpeg builds are nonfree and must not be redistributed. |

## For AI agents

Agents start at [AGENTS.md](../AGENTS.md), which routes them to their own notes. Those notes are terse, rule-focused versions of these pages; you don't need to read them.
