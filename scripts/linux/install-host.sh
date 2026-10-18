#!/usr/bin/env bash
# Install an exported MediaStack tarball on an Ubuntu host (22.04 or newer).
#   - extracts to $LINUX_PREFIX (/opt/mediastack), replacing any previous install
#   - apt-installs the runtime packages listed in share/mediastack/runtime-apt.txt
#   - registers $LINUX_PREFIX/lib with ldconfig and puts $LINUX_PREFIX/bin on PATH
#
# Usage: sudo install-host.sh [tarball]   (default: out/linux/mediastack-latest.tar.*)
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"

tarball=${1:-$(ls "$STACK_ROOT"/out/linux/mediastack-latest.tar.* 2>/dev/null | head -n 1)}
[[ -f "$tarball" ]] || die "no tarball found${tarball:+ at $tarball} (run scripts/linux/export.sh first)"
(( EUID == 0 )) || die "run as root (sudo $0 $*)"

prefix=$LINUX_PREFIX
staging="$prefix.new"
rm -rf "$staging"
mkdir -p "$staging"
msg "Extracting $(basename "$(readlink -f "$tarball")") to $prefix"
tar -xf "$tarball" -C "$staging"   # GNU tar detects zstd/gzip

if [[ -s "$staging/share/mediastack/runtime-apt.txt" ]]; then
    msg "Installing runtime packages"
    apt-get update -qq
    xargs -a "$staging/share/mediastack/runtime-apt.txt" apt-get install -y --no-install-recommends
fi

rm -rf "$prefix.old"
[[ -d "$prefix" ]] && mv "$prefix" "$prefix.old"
mv "$staging" "$prefix"
rm -rf "$prefix.old"

echo "$prefix/lib" > /etc/ld.so.conf.d/mediastack.conf
ldconfig
cat > /etc/profile.d/mediastack.sh <<PROFILE
# Added by MediaStack install-host.sh
case ":\$PATH:" in *":$prefix/bin:"*) ;; *) PATH="$prefix/bin:\$PATH" ;; esac
PROFILE

msg "Installed:"
cat "$prefix/BUILDINFO.txt"
msg "Open a new shell (or: . /etc/profile.d/mediastack.sh), then see docs/testing.md"
