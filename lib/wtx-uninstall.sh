#!/usr/bin/env bash
# Shared uninstall logic for `wtx uninstall` and `bootstrap.sh --uninstall`.
#
# Mirrors the install layers, but defaults to *safe*: the PATH symlink is removed
# automatically (delegated to install.sh --uninstall, the same code that created
# it); everything else (per-project hooks, the Gradle init script, the toolkit
# checkout) is only removed after an explicit confirmation. The user's wtx.toml
# is never touched — it is config, not an install artifact.
#
# bash 3.2 compatible. ERROR HANDLING: graceful — `set -u` style, never `set -e`.

if [[ "${_WTX_UNINSTALL_LIB_LOADED:-0}" -eq 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
_WTX_UNINSTALL_LIB_LOADED=1

# Resolve the install prefix from the active `wtx` symlink ($prefix/bin/wtx), so
# uninstall targets the same link install created. Falls back to ~/.local.
_wtx_uninstall_resolve_prefix() {
    local link bindir
    link="$(command -v wtx 2>/dev/null)"
    if [[ -n "$link" ]]; then
        bindir="$(cd "$(dirname "$link")" && pwd 2>/dev/null)"
        if [[ -n "$bindir" ]]; then
            dirname "$bindir"
            return 0
        fi
    fi
    printf '%s' "$HOME/.local"
}

# True when $WTX_ROOT is a bootstrap-managed toolkit home (safe to offer for
# deletion) rather than a hand-cloned source checkout living anywhere else.
_wtx_uninstall_is_managed_home() {
    case "$WTX_ROOT" in
        "${XDG_DATA_HOME:-$HOME/.local/share}/wtx") return 0 ;;
        "$HOME/.local/share/wtx")                   return 0 ;;
    esac
    return 1
}

# Confirm gate honoring --all/--yes (auto-yes) and tty availability (default No).
_wtx_uninstall_confirm() {
    [[ "${_WTX_UNINSTALL_ALL:-0}" -eq 1 || "${_WTX_UNINSTALL_YES:-0}" -eq 1 ]] && return 0
    if command -v tui_confirm >/dev/null 2>&1; then
        tui_confirm "$1"
        return $?
    fi
    local r
    read -r -p "$1 [y/N] " r < /dev/tty 2>/dev/null || return 1
    [[ "$r" =~ ^[Yy] ]]
}

# wtx_uninstall_run [--dry-run] [--all] [--yes] [--prefix PATH]
wtx_uninstall_run() {
    local dry=0 prefix="" arg
    _WTX_UNINSTALL_ALL=0
    _WTX_UNINSTALL_YES=0
    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --dry-run) dry=1; shift ;;
            --all)     _WTX_UNINSTALL_ALL=1; shift ;;
            --yes|-y)  _WTX_UNINSTALL_YES=1; shift ;;
            --prefix)  [[ $# -ge 2 ]] || { printf 'wtx uninstall: --prefix requires a path\n' >&2; return 2; }; prefix="$2"; shift 2 ;;
            --prefix=*) prefix="${arg#--prefix=}"; shift ;;
            *) printf 'wtx uninstall: unknown option: %s\n' "$arg" >&2; return 2 ;;
        esac
    done

    [[ -n "$prefix" ]] || prefix="$(_wtx_uninstall_resolve_prefix)"

    local rc=0
    printf 'wtx uninstall\n\n'

    # --- Layer 1: PATH symlink (always, delegated to install.sh) ---------------
    if [[ $dry -eq 1 ]]; then
        bash "$WTX_ROOT/install.sh" --uninstall --prefix "$prefix" --dry-run || rc=$?
    else
        bash "$WTX_ROOT/install.sh" --uninstall --prefix "$prefix" || rc=$?
    fi

    # --- Layer 2: per-project Claude Code hooks --------------------------------
    local destdir="$WORKSPACE_ROOT/.claude/hooks"
    local present=() h
    for h in worktree-create.sh worktree-detect.sh worktree-remove.sh; do
        [[ -f "$destdir/$h" ]] && present+=("$h")
    done
    if [[ ${#present[@]} -gt 0 ]]; then
        printf '\n'
        if [[ $dry -eq 1 ]]; then
            for h in "${present[@]}"; do printf '  [dry-run] would remove %s\n' "$destdir/$h"; done
        elif _wtx_uninstall_confirm "Remove this workspace's Claude hooks (${#present[@]} file(s) in .claude/hooks/)?"; then
            for h in "${present[@]}"; do
                rm -f "$destdir/$h" && printf '  removed %s\n' "$h"
            done
            rmdir "$destdir" 2>/dev/null && printf '  removed empty %s\n' "$destdir"
        else
            printf '  kept Claude hooks in %s\n' "$destdir"
        fi
    fi

    # --- Layer 3: Gradle worktree-cache init script ----------------------------
    local gradle="$HOME/.gradle/init.d/worktree-cache.init.gradle.kts"
    if [[ -f "$gradle" ]]; then
        printf '\n'
        if [[ $dry -eq 1 ]]; then
            printf '  [dry-run] would remove %s\n' "$gradle"
        elif _wtx_uninstall_confirm "Remove the Gradle worktree-cache init script?"; then
            rm -f "$gradle" && printf '  removed %s\n' "$gradle"
        else
            printf '  kept %s\n' "$gradle"
        fi
    fi

    # --- Layer 4: toolkit checkout (only if bootstrap-managed home) ------------
    printf '\n'
    if _wtx_uninstall_is_managed_home; then
        if [[ $dry -eq 1 ]]; then
            printf '  [dry-run] would remove toolkit checkout %s\n' "$WTX_ROOT"
        elif _wtx_uninstall_confirm "Remove the toolkit checkout at $WTX_ROOT?"; then
            if git -C "$WTX_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
               && [[ -n "$(git -C "$WTX_ROOT" status --porcelain 2>/dev/null)" ]]; then
                printf '  NOT removing %s — it has local changes (delete manually if intended)\n' "$WTX_ROOT"
            else
                rm -rf "$WTX_ROOT" && printf '  removed toolkit checkout %s\n' "$WTX_ROOT"
            fi
        else
            printf '  kept toolkit checkout %s\n' "$WTX_ROOT"
        fi
    else
        printf '  toolkit checkout left in place: %s\n' "$WTX_ROOT"
        printf '    (not a bootstrap-managed home — remove manually if you want it gone)\n'
    fi

    # --- Active worktrees: user work, never removed — just remind --------------
    local wt_count=0
    if git -C "$WORKSPACE_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        wt_count="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')"
        # Exclude the main checkout itself.
        [[ "$wt_count" -gt 0 ]] && wt_count=$((wt_count - 1))
    fi
    if [[ "$wt_count" -gt 0 ]]; then
        printf '\n  note: %d active worktree(s) remain — uninstall does not remove them.\n' "$wt_count"
        printf '        use `git worktree remove <path>` (or `wtx done` before uninstalling).\n'
        local reg="$WORKSPACE_ROOT/.claude/worktree-registry.md"
        [[ -f "$reg" ]] && printf '        tracked in %s\n' "$reg"
    fi

    # --- Always-kept config ----------------------------------------------------
    if [[ -f "$WORKSPACE_ROOT/wtx.toml" ]]; then
        printf '\n  wtx.toml left in place: %s\n' "$WORKSPACE_ROOT/wtx.toml"
    fi
    if command -v npm >/dev/null 2>&1; then
        printf '  note: if you used `npx wtx-toolkit`, nothing global was installed by npx.\n'
    fi

    return $rc
}
