# Shared helpers for MediaStack scripts. Source it; don't execute it.
# Sets STACK_ROOT and loads stack.conf.

STACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../stack.conf
. "$STACK_ROOT/stack.conf"

msg()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# upstream_url <project>: upstream remote URL from stack.conf (empty if none).
upstream_url() {
    local var="UPSTREAM_${1//-/_}"
    printf '%s' "${!var}"
}

# tracked_branch <project>: branch recorded in .gitmodules (empty if pinned to a tag).
tracked_branch() {
    git -C "$STACK_ROOT" config -f .gitmodules --get "submodule.$1.branch" || true
}

# check_project <project>: die unless it is a known submodule.
check_project() {
    case " $STACK_PROJECTS " in
        *" $1 "*) ;;
        *) die "unknown project '$1' (known: $STACK_PROJECTS)" ;;
    esac
}

# detect_target: ucrt64 or linux.
detect_target() {
    if [[ -n "${MSYSTEM:-}" ]]; then
        printf '%s' "${MSYSTEM,,}"
    else
        printf 'linux'
    fi
}

# nproc that also works in MSYS2.
jobs_count() {
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4
}

# pinned_sha <project>: the submodule commit recorded in the superrepo index.
pinned_sha() {
    git -C "$STACK_ROOT" ls-files -s -- "$1" | awk '$1 == "160000" { print $2 }'
}
