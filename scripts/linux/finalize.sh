#!/usr/bin/env bash
# Make $MS_PREFIX relocatable and self-describing:
#   - RPATH $ORIGIN/../lib on every ELF so the tree works without ldconfig
#   - copy in shared libs that the Ubuntu base image won't have (Vulkan SDK
#     shaderc, CUDA runtime pieces)
#   - list the apt packages the host needs in share/mediastack/runtime-apt.txt
#   - BUILDINFO.txt with the SHAs
# Usage: finalize.sh <BUILDINFO.txt>
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/env.sh"
cd "$MS_PREFIX"

rm -rf share/doc share/man lib/*.a
mkdir -p share/mediastack

elfs() { find bin lib -type f \( -perm -u+x -o -name '*.so*' \) -exec sh -c 'file -b "$1" | grep -q ^ELF' _ {} \; -print; }

for f in $(elfs); do
    case "$f" in
        bin/*) patchelf --set-rpath '$ORIGIN/../lib' "$f" ;;
        lib/*) patchelf --set-rpath '$ORIGIN' "$f" ;;
    esac
done

# Bundle libraries that resolve outside the prefix and outside the Ubuntu
# archive (anything not owned by a dpkg package), e.g. libshaderc_shared.so
# from the Vulkan SDK. libcuda/libnvcuvid/libnvidia-encode come from the host
# driver and must never be bundled.
declare -A pkgs=()
for f in $(elfs); do
    while read -r lib path; do
        [[ -n "$path" && -e "$path" ]] || continue
        case "$path" in "$MS_PREFIX"/*) continue ;; esac
        case "$lib" in
            libcuda.so*|libnvcuvid.so*|libnvidia-*) continue ;;
            libvulkan.so.1) pkgs[libvulkan1]=1; continue ;;   # host loader, not the build-time one
        esac
        if owner=$(dpkg -S "$(readlink -f "$path")" 2>/dev/null || dpkg -S "$path" 2>/dev/null); then
            pkg=${owner%%:*}
            case "$pkg" in cuda-*|libcu*|libnpp*) cp -n -L "$path" lib/ ;; *) pkgs[$pkg]=1 ;; esac
        else
            cp -n -L "$path" lib/
        fi
    done < <(ldd "$f" 2>/dev/null | awk '$2 == "=>" { print $1, $3 }')
done
printf '%s\n' "${!pkgs[@]}" | sort > share/mediastack/runtime-apt.txt

cp "$1" BUILDINFO.txt
echo "nvcc: $(nvcc --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')" >> BUILDINFO.txt

msg "Prefix size: $(du -sh . | cut -f1); host packages: $(wc -l < share/mediastack/runtime-apt.txt)"
