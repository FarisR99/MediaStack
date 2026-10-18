#!/usr/bin/env bash
# Remove a MediaStack install made by install-host.sh. Runtime apt packages are
# left installed.
# Usage: sudo uninstall-host.sh
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common/lib.sh"
(( EUID == 0 )) || die "run as root (sudo $0)"

rm -rf "$LINUX_PREFIX" "$LINUX_PREFIX.new" "$LINUX_PREFIX.old"
rm -f /etc/ld.so.conf.d/mediastack.conf /etc/profile.d/mediastack.sh
ldconfig
msg "Removed $LINUX_PREFIX"
