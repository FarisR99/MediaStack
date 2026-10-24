#!/usr/bin/env bash
# Package the pinned Anime4K shaders into combined presets (low/medium/high/ultra).
# Each preset is the concatenation of the upstream files listed in
# scripts/anime4k-presets.conf, with the license notices once, an attribution
# banner and a blank line between source files. The upstream commit and hashes are
# pinned in stack.conf and scripts/anime4k-presets.lock, so output is reproducible.
#
# Usage: anime4k-presets.sh [--out DIR] [--preset NAME]... [--offline]
#                           [--refresh] [--update-lock] [--list]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common/lib.sh"
cd "$STACK_ROOT"

repo=bloc97/Anime4K
manifest=scripts/anime4k-presets.conf
lock=scripts/anime4k-presets.lock

out=out/shaders/anime4k
cache=
presets=()
offline=0
refresh=0
update_lock=0
list=0

work=
lock_tmp=

usage() {
    cat <<'EOF'
Usage: anime4k-presets.sh [options]

Download the Anime4K shaders pinned in stack.conf (ANIME4K_VERSION and
ANIME4K_COMMIT), verify them against scripts/anime4k-presets.lock, and write
clean combined presets.

  --out DIR        output directory (default: out/shaders/anime4k)
  --preset NAME    preset to build; repeatable or comma-separated (default: all)
  --cache DIR      upstream cache (default: out/cache/anime4k/<commit>)
  --offline        never download; require valid cache entries
  --refresh        re-download even when a valid cache entry exists
  --update-lock    download every shader in the manifest and rewrite the lock
  --list           print presets and their shader chains, then exit
  -h, --help       show this help

Adding a preset: edit scripts/anime4k-presets.conf, then run
  scripts/anime4k-presets.sh --update-lock
EOF
}

cleanup() {
    if [[ -n $work && -d $work ]]; then
        rm -rf "$work"
    fi
    if [[ -n $lock_tmp && -f $lock_tmp ]]; then
        rm -f "$lock_tmp"
    fi
    return 0
}
trap cleanup EXIT

add_presets() {
    [[ -n $1 ]] || die "--preset needs a name"
    local list=$1 part
    local IFS=,
    for part in $list; do
        if [[ -n $part ]]; then
            presets+=("$part")
        fi
    done
}

while (( $# )); do
    case "$1" in
        --out)
            [[ $# -ge 2 && -n $2 ]] || die "--out needs a directory"
            out=$2
            shift
            ;;
        --out=*)
            out=${1#*=}
            [[ -n $out ]] || die "--out needs a directory"
            ;;
        --preset)
            [[ $# -ge 2 ]] || die "--preset needs a name"
            add_presets "$2"
            shift
            ;;
        --preset=*) add_presets "${1#*=}" ;;
        --cache)
            [[ $# -ge 2 && -n $2 ]] || die "--cache needs a directory"
            cache=$2
            shift
            ;;
        --cache=*)
            cache=${1#*=}
            [[ -n $cache ]] || die "--cache needs a directory"
            ;;
        --offline) offline=1 ;;
        --refresh) refresh=1 ;;
        --update-lock) update_lock=1 ;;
        --list) list=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1' (try --help)" ;;
    esac
    shift
done

[[ -f $manifest ]] || die "missing manifest: $manifest"

declare -A preset_files=()
manifest_presets=()
cur=
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z $line || $line == '#'* ]] && continue

    if [[ $line =~ ^([A-Za-z0-9_.-]+):[[:space:]]*$ ]]; then
        name=${BASH_REMATCH[1]}
        if [[ -n ${preset_files[$name]+x} ]]; then
            die "duplicate preset '$name' in $manifest"
        fi
        manifest_presets+=("$name")
        preset_files[$name]=""
        cur=$name
        continue
    fi

    if [[ $line =~ ^[[:space:]]+([^[:space:]]+)[[:space:]]*$ ]]; then
        [[ -n $cur ]] || die "shader '$line' is outside a preset in $manifest"
        path=${BASH_REMATCH[1]}
        if [[ $path != glsl/* || $path == *..* || $path =~ [[:space:]] ]]; then
            die "invalid shader path '$path' in $manifest"
        fi
        if [[ " ${preset_files[$cur]} " == *" $path "* ]]; then
            die "duplicate shader '$path' in preset '$cur'"
        fi
        preset_files[$cur]+=" $path"
        continue
    fi

    die "cannot parse $manifest line: $line"
done < "$manifest"

(( ${#manifest_presets[@]} )) || die "no presets in $manifest"
for name in "${manifest_presets[@]}"; do
    [[ -n ${preset_files[$name]} ]] || die "preset '$name' has no shaders in $manifest"
done

if (( ${#presets[@]} == 0 )); then
    presets=("${manifest_presets[@]}")
else
    declare -a selected=()
    for p in "${presets[@]}"; do
        dup=0
        for q in "${selected[@]}"; do
            if [[ $q == "$p" ]]; then dup=1; break; fi
        done
        if (( dup == 0 )); then selected+=("$p"); fi
    done
    presets=("${selected[@]}")
fi
for p in "${presets[@]}"; do
    [[ -n ${preset_files[$p]+x} ]] || die "unknown preset '$p' (available: ${manifest_presets[*]})"
done

if (( list )); then
    for name in "${presets[@]}"; do
        printf '%s:\n' "$name"
        read -r -a files <<< "${preset_files[$name]}" || true
        for path in "${files[@]}"; do printf '  %s\n' "$path"; done
    done
    exit 0
fi

[[ -n ${ANIME4K_VERSION:-} ]] || die "stack.conf is missing ANIME4K_VERSION"
[[ ${ANIME4K_COMMIT:-} =~ ^[0-9a-f]{40}$ ]] ||
    die "stack.conf has no valid ANIME4K_COMMIT (40 lowercase hex characters)"
if [[ -z $cache ]]; then
    cache="out/cache/anime4k/$ANIME4K_COMMIT"
fi

command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required (coreutils)"
if (( offline )); then
    (( update_lock == 0 )) || die "--update-lock needs network and cannot be used with --offline"
    (( refresh == 0 )) || die "--refresh needs network and cannot be used with --offline"
else
    command -v curl >/dev/null 2>&1 || die "curl is required to download the shaders"
fi

declare -A lock_hash=()
lock_version=
lock_commit=
if [[ -f $lock ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ -z $line ]] && continue
        if [[ $line == '# version: '* ]]; then
            lock_version=${line#'# version: '}
            continue
        fi
        if [[ $line == '# commit: '* ]]; then
            lock_commit=${line#'# commit: '}
            continue
        fi
        [[ $line == '#'* ]] && continue
        [[ $line =~ ^([0-9a-f]{64})[[:space:]]+(.+)$ ]] ||
            die "cannot parse $lock line: $line"
        [[ -z ${lock_hash[${BASH_REMATCH[2]}]+x} ]] ||
            die "duplicate hash for ${BASH_REMATCH[2]} in $lock"
        lock_hash[${BASH_REMATCH[2]}]=${BASH_REMATCH[1]}
    done < "$lock"
fi

if (( update_lock == 0 )); then
    [[ -f $lock ]] || die "missing $lock; run --update-lock"
    [[ -n $lock_commit ]] || die "no commit header in $lock; run --update-lock"
    if [[ $lock_commit != "$ANIME4K_COMMIT" ]]; then
        die "lock is for commit $lock_commit but stack.conf pins $ANIME4K_COMMIT; run --update-lock after bumping the pin"
    fi
    if [[ -n $lock_version && $lock_version != "$ANIME4K_VERSION" ]]; then
        warn "lock is for version $lock_version but stack.conf says $ANIME4K_VERSION (commit matches; continuing)"
    fi
fi

declare -a fetch_list=()
declare -a src_presets=()
declare -a src_files=()
if (( update_lock )); then
    src_presets=("${manifest_presets[@]}")
else
    src_presets=("${presets[@]}")
fi
for name in "${src_presets[@]}"; do
    read -r -a src_files <<< "${preset_files[$name]}" || true
    fetch_list+=("${src_files[@]}")
done
mapfile -t fetch_list < <(printf '%s\n' "${fetch_list[@]}" | LC_ALL=C sort -u)
(( ${#fetch_list[@]} )) || die "no shader files selected"

if (( update_lock == 0 )); then
    for path in "${fetch_list[@]}"; do
        [[ -n ${lock_hash[$path]:-} ]] ||
            die "no pinned hash for '$path' in $lock; run --update-lock"
    done
fi

sha256_file() {
    local line
    line=$(sha256sum -- "$1")
    printf '%s\n' "${line%% *}"
}

repo_url="https://raw.githubusercontent.com/$repo/$ANIME4K_COMMIT"

fetch_one() {
    local path=$1 expected=$2
    local file="$cache/$path" got tmp
    if (( update_lock == 0 && refresh == 0 )) && [[ -f $file ]]; then
        got=$(sha256_file "$file")
        if [[ -z $expected || $got == "$expected" ]]; then
            return 0
        fi
        warn "cached $path has the wrong SHA-256; fetching it again"
    fi
    if (( offline )); then
        die "no valid cached copy of $path (--offline)"
    fi
    mkdir -p "$(dirname "$file")"
    tmp="$file.part.$$"
    msg "Fetching $path"
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "$tmp" "$repo_url/$path"; then
        rm -f "$tmp"
        die "could not download $path from $repo_url"
    fi
    if ! grep -q '^//!DESC' "$tmp"; then
        rm -f "$tmp"
        die "downloaded file has no //!DESC pass: $path"
    fi
    got=$(sha256_file "$tmp")
    if [[ -n $expected && $got != "$expected" ]]; then
        rm -f "$tmp"
        die "SHA-256 mismatch for $path: pinned $expected, got $got; if Anime4K changed, bump ANIME4K_* in stack.conf and run --update-lock"
    fi
    mv -f "$tmp" "$file"
}

for path in "${fetch_list[@]}"; do
    if (( update_lock )); then
        fetch_one "$path" ""
    else
        fetch_one "$path" "${lock_hash[$path]:-}"
    fi
done

if (( update_lock )); then
    lock_tmp="$lock.tmp.$$"
    {
        printf '# Anime4K preset upstream lock\n'
        printf '# version: %s\n' "$ANIME4K_VERSION"
        printf '# commit: %s\n' "$ANIME4K_COMMIT"
        for path in "${fetch_list[@]}"; do
            printf '%s  %s\n' "$(sha256_file "$cache/$path")" "$path"
        done
    } > "$lock_tmp"
    mv -f "$lock_tmp" "$lock"
    lock_tmp=
    msg "Updated $lock (${#fetch_list[@]} files at $ANIME4K_VERSION)"
fi

# Strip a leading MIT or Unlicense header from $1, writing the header to $2 and
# the remaining shader body (CR-free, no leading/trailing blank lines) to $3.
# AutoDownscalePre shaders use the Unlicense; everything else uses MIT.
extract_shader() {
    local src=$1 hdr=$2 body=$3 last
    : > "$hdr"
    : > "$body"
    awk -v hdr="$hdr" -v body="$body" '
        {
            sub(/\r$/, "")
            if (state == 0) {
                if ($0 == "") next
                if ($0 == "// MIT License") {
                    term = "// SOFTWARE."
                    state = 1; print > hdr; next
                }
                if ($0 == "// This is free and unencumbered software released into the public domain.") {
                    term = "// For more information, please refer to <https://unlicense.org>"
                    state = 1; print > hdr; next
                }
                state = 3
            } else if (state == 1) {
                print > hdr
                if ($0 == term) state = 2
                next
            } else if (state == 2) {
                if ($0 == "") next
                state = 3
            }
            print > body
        }
    ' "$src"
    last=$(awk 'NF { n = NR } END { print n + 0 }' "$body")
    if (( last == 0 )); then
        : > "$body"
    else
        head -n "$last" "$body" > "$body.tmp"
        mv -f "$body.tmp" "$body"
    fi
}

build_preset() {
    local name=$1 mit_hdr= unlicense_hdr= hdrfile body path passes i
    local -a files=()
    local -a unlicense_files=()
    read -r -a files <<< "${preset_files[$name]}" || true
    (( ${#files[@]} )) || die "preset '$name' has no shaders"

    work=$(mktemp -d "$out/.anime4k.XXXXXX") || die "cannot create a temporary directory in $out"
    i=0
    for path in "${files[@]}"; do
        hdrfile="$work/hdr.$i"
        body="$work/body.$i"
        extract_shader "$cache/$path" "$hdrfile" "$body"
        [[ -s $body ]] || die "empty shader body: $path"
        grep -q '^//!DESC' "$body" || die "no //!DESC pass in $path"
        if [[ -s $hdrfile ]]; then
            case "$(head -n 1 "$hdrfile")" in
                '// MIT License')
                    if [[ -z $mit_hdr ]]; then mit_hdr=$hdrfile; fi
                    ;;
                '// This is free and unencumbered software released into the public domain.')
                    if [[ -z $unlicense_hdr ]]; then unlicense_hdr=$hdrfile; fi
                    unlicense_files+=("$path")
                    ;;
                *) die "unrecognised license header in $path" ;;
            esac
        fi
        i=$((i + 1))
    done
    [[ -n $mit_hdr || -n $unlicense_hdr ]] || die "preset '$name' has no license header to carry"

    {
        if [[ -n $mit_hdr ]]; then
            cat "$mit_hdr"
            printf '\n'
        fi
        if [[ -n $unlicense_hdr ]]; then
            cat "$unlicense_hdr"
            printf '\n'
        fi
        printf '// Generated by MediaStack scripts/anime4k-presets.sh\n'
        printf '// Source: %s %s (%s)\n' "$repo" "$ANIME4K_VERSION" "$ANIME4K_COMMIT"
        printf '// Preset: %s\n' "$name"
        if [[ -n $mit_hdr && -n $unlicense_hdr ]]; then
            printf '// Licenses: MIT and Unlicense.\n'
        elif [[ -n $mit_hdr ]]; then
            printf '// License: MIT.\n'
        else
            printf '// License: Unlicense.\n'
        fi
        if (( ${#unlicense_files[@]} )); then
            printf '// Unlicense sources:\n'
            for path in "${unlicense_files[@]}"; do
                printf '//   %s\n' "$path"
            done
        fi
        printf '// Sources:\n'
        for path in "${files[@]}"; do
            printf '//   %s\n' "$path"
        done
        printf '// Do not edit; edit scripts/anime4k-presets.conf and regenerate.\n'
        printf '\n'
        i=0
        for path in "${files[@]}"; do
            if (( i > 0 )); then
                printf '\n'
            fi
            cat "$work/body.$i"
            i=$((i + 1))
        done
    } > "$work/$name.glsl"

    mv -f "$work/$name.glsl" "$out/$name.glsl"
    passes=$(awk '/^\/\/!DESC/ { n++ } END { print n + 0 }' "$out/$name.glsl")
    msg "$name: ${#files[@]} shaders, $passes passes -> $out/$name.glsl"
    rm -rf "$work"
    work=
}

mkdir -p "$out" || die "cannot create output directory $out"
for name in "${presets[@]}"; do
    build_preset "$name"
done
