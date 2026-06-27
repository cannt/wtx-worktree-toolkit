#!/bin/bash
# Interactive installer wizard skeleton.

set -u

_wtx_install_self="${BASH_SOURCE[0]}"
while [[ -L "$_wtx_install_self" ]]; do
    _wtx_install_link="$(readlink "$_wtx_install_self")"
    if [[ "$_wtx_install_link" = /* ]]; then
        _wtx_install_self="$_wtx_install_link"
    else
        _wtx_install_self="$(cd "$(dirname "$_wtx_install_self")" && pwd)/$_wtx_install_link"
    fi
done
_wtx_install_dir="$(cd "$(dirname "$_wtx_install_self")" && pwd)"

if [[ -z "${WTX_ROOT:-}" ]]; then
    if [[ -d "$_wtx_install_dir/lib" ]]; then
        WTX_ROOT="$_wtx_install_dir"
    else
        WTX_ROOT="$(cd "$_wtx_install_dir/.." && pwd)"
    fi
fi
export WTX_ROOT
unset _wtx_install_self _wtx_install_link _wtx_install_dir

_wtx_install_resolve_workspace_root() {
    if [[ -n "${WORKSPACE_ROOT:-}" ]]; then
        export WORKSPACE_ROOT
        return 0
    fi

    local gcd
    gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [[ -n "$gcd" && -d "$gcd" ]]; then
        WORKSPACE_ROOT="$(dirname "$gcd")"
    else
        WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    export WORKSPACE_ROOT
}

_wtx_install_source_libs() {
    # shellcheck source=../lib/wtx-install.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-install.sh"
    # shellcheck source=../lib/wtx-config.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-config.sh" 2>/dev/null || true
    # shellcheck source=../lib/worktree-tui.sh disable=SC1091
    source "$WTX_ROOT/lib/worktree-tui.sh" 2>/dev/null || {
        tui_confirm() { local r; read -r -p "$1 [y/N] " r < /dev/tty; [[ "$r" =~ ^[Yy]$ ]]; }
        tui_input() { local v; read -r -p "$1 [${2:-}]: " v < /dev/tty; echo "${v:-$2}"; }
        tui_choose() { local p="$1"; shift; PS3="$p "; select o in "$@"; do echo "$o"; break; done < /dev/tty; }
        tui_filter() { tui_choose "$@"; }
        tui_spin() { local m="$1"; shift; echo "$m" >&2; "$@"; }
        tui_style_box() { for l in "$@"; do echo "  $l"; done; }
        tui_abort_check() { :; }
        open_url() { echo "  URL: $1"; }
        has_gum() { return 1; }
        has_claude() { command -v claude >/dev/null 2>&1; }
        run_with_timeout() { shift; "$@"; }
        get_known_projects() { :; }
        update_registry() { :; }
        claude_supports_positional_prompt() { return 1; }
        claude_supports_message_flag() { return 1; }
    }
}

_wtx_install_parse_args() {
    WTX_INSTALL_DRY_RUN=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                WTX_INSTALL_DRY_RUN=1
                shift
                ;;
            *)
                printf 'wtx install: unknown option: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done
    export WTX_INSTALL_DRY_RUN
    return 0
}

_wtx_install_preflight() {
    _wtx_install_parse_args "$@" || return $?

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "wtx install: not in a git repository" >&2
        return 1
    fi

    if command -v gum >/dev/null 2>&1; then
        GUM_AVAILABLE=1
    else
        GUM_AVAILABLE=0
        echo "note: gum not found — using plain prompts (install with: brew install gum)"
    fi
    export GUM_AVAILABLE

    _wtx_install_resolve_workspace_root || return $?
    _wtx_install_source_libs || return $?

    _WTX_INSTALL_TMP="$(mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX")" || return 1
    trap 'rm -f "$_WTX_INSTALL_TMP"' EXIT

    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
}

_wtx_install_run() {
    _wtx_install_preflight "$@" || return $?
    return 0
}

_wtx_install_run "$@"
