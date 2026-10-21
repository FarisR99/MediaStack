#!/usr/bin/env bash
# Assemble a portable folder (out/ucrt64/dist) that runs outside MSYS2:
# stack binaries + every DLL they need from the prefix and from UCRT64, plus
# NVEncC if scripts/windows/nvencc-spike.ps1 has built it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
[[ "$MS_TARGET" == ucrt64 ]] || die "run from the MSYS2 UCRT64 shell"
cd "$STACK_ROOT"

dist=out/ucrt64/dist
rm -rf "$dist"
mkdir -p "$dist"

for f in mpv.exe mpv.com ffmpeg.exe ffprobe.exe; do
    [[ -f "$MS_PREFIX/bin/$f" ]] && cp "$MS_PREFIX/bin/$f" "$dist/"
done
cp "$MS_PREFIX"/bin/*.dll "$dist/"

nvencc=out/ucrt64/nvencc
if [[ -f "$nvencc/NVEncC64.exe" ]]; then
    cp -n "$nvencc"/*.exe "$nvencc"/*.dll "$dist/" 2>/dev/null || true
else
    warn "NVEncC not built yet (scripts/windows/nvencc-spike.ps1); packaging without it"
fi

# NVIDIA runtime DLLs (stack.conf NVIDIA_*_URL), loaded at runtime so ldd can't
# find them. Fetched once into out/; Windows' tar.exe (libarchive) reads 7z.
# Copied over any hand-placed copies in the prefix.
for url in "$NVIDIA_NGX_URL" "$NVIDIA_FRUC_URL"; do
    [[ -n "$url" ]] || continue
    name=$(basename "$url" .7z)
    dir=out/ucrt64/build/nvidia-runtime/$name
    if [[ ! -f "$dir/.done" ]]; then
        msg "Fetching $url"
        rm -rf "$dir" && mkdir -p "$dir"
        if curl -fsSL -o "$dir.7z" "$url" &&
           "$(cygpath -S)/tar.exe" -xf "$(cygpath -w "$dir.7z")" -C "$(cygpath -w "$dir")"; then
            touch "$dir/.done"
        else
            warn "could not fetch $name; packaging without it"
        fi
        rm -f "$dir.7z"
    fi
    [[ -f "$dir/.done" ]] && cp -f "$dir"/*.dll "$dist/"
done

# ldd lists the full dependency closure; keep everything that isn't a system DLL.
for f in "$dist"/*.exe "$dist"/*.dll; do
    ldd "$f" 2>/dev/null | awk '$2 == "=>" { print $3 }'
done | sort -u | while read -r dll; do
    case "${dll,,}" in
        /c/windows/*|"not") continue ;;
    esac
    [[ -f "$dll" && ! -f "$dist/$(basename "$dll")" ]] && cp "$dll" "$dist/"
done

{
    echo "MediaStack $(git rev-parse --short HEAD 2>/dev/null || echo uncommitted)"
    echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ) on $(hostname)"
    echo "target: ucrt64"
    for p in $STACK_PROJECTS; do
        printf '%-17s %s\n' "$p:" "$(git -C "$p" describe --tags --always --dirty 2>/dev/null)"
    done
    for url in "$NVIDIA_NGX_URL" "$NVIDIA_FRUC_URL"; do
        [[ -n "$url" ]] && echo "nvidia runtime:   $(basename "$url")"
    done
} > "$dist/BUILDINFO.txt"

msg "Packaged $(ls "$dist" | wc -l) files into $dist ($(du -sh "$dist" | cut -f1))"
