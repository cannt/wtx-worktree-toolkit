#!/bin/bash
# Built-in Worktree Post-Exit Script (PostToolUse phase)
# Runs after ExitWorktree completes. Updates registry only if the worktree was actually removed.
#
# Usage: bash scripts/worktree/builtin-worktree-post-exit.sh
#
# Called automatically via PostToolUse hook on ExitWorktree.
# Reads metadata saved by builtin-worktree-cleanup.sh (PreToolUse phase).
#
# If the worktree directory still exists → action was "keep" → no registry change.
# If the worktree directory is gone → action was "remove" → move to Recently Closed.
#
# ERROR HANDLING: No set -e. Best-effort — failures don't block the session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Locate the toolkit (keep in sync with hooks/worktree-create.sh) ----------
# This script runs from one of several places — the wtx checkout (scripts/), a
# project's .claude/hooks/, or a vendored copy — so a relative guess alone is
# unsafe. Validate every candidate by probing for lib/wtx-config.sh, and when the
# toolkit isn't nearby (the .claude/hooks/ case) fall back to the `wtx` binary on
# PATH, which is the only reliable anchor there.
_wtx_is_root() { [[ -n "${1:-}" ]] && [[ -f "$1/lib/wtx-config.sh" ]]; }
_wtx_deref() {
    local p="$1" link
    while [[ -L "$p" ]]; do
        link="$(readlink "$p")"
        case "$link" in
            /*) p="$link" ;;
            *)  p="$(cd "$(dirname "$p")" && pwd)/$link" ;;
        esac
    done
    printf '%s' "$p"
}
if ! _wtx_is_root "${WTX_ROOT:-}"; then
    WTX_ROOT=""
    for _wtx_cand in "$SCRIPT_DIR/.." "$SCRIPT_DIR"; do
        if _wtx_is_root "$_wtx_cand"; then
            WTX_ROOT="$(cd "$_wtx_cand" && pwd)"
            break
        fi
    done
    if ! _wtx_is_root "${WTX_ROOT:-}" && command -v wtx >/dev/null 2>&1; then
        _wtx_cand="$(cd "$(dirname "$(_wtx_deref "$(command -v wtx)")")/.." 2>/dev/null && pwd)"
        _wtx_is_root "$_wtx_cand" && WTX_ROOT="$_wtx_cand"
    fi
    unset _wtx_cand
fi

# WORKSPACE_ROOT: the main repo, even when invoked from inside a linked worktree
# (--show-toplevel would return the worktree path instead). The worktree we are
# cleaning up may already be gone, so fall back to CLAUDE_PROJECT_DIR.
if [[ -z "${WORKSPACE_ROOT:-}" ]]; then
    _wtx_gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [[ -n "$_wtx_gcd" && -d "$_wtx_gcd" ]]; then
        WORKSPACE_ROOT="$(dirname "$_wtx_gcd")"
    elif [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR:-}" ]]; then
        WORKSPACE_ROOT="$CLAUDE_PROJECT_DIR"
    else
        WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    unset _wtx_gcd
fi

# Find the metadata file saved by pre-exit script.
# Fast path: follow the PPID-qualified pointer written by cleanup.sh.
# PPID is the parent Claude Code process — shared between pre-exit and post-exit hooks
# within the same session, so concurrent sessions don't collide.
# Fallback: try the legacy non-qualified pointer, then glob for the most-recently
# modified PID-qualified metadata file. The staleness guard below rejects stale files.
LATEST_PTR="${TMPDIR:-/tmp}/.worktree-exit-metadata-latest-${PPID:-0}"
METADATA_FILE=""
if [[ -f "$LATEST_PTR" ]]; then
    METADATA_FILE="$(cat "$LATEST_PTR" 2>/dev/null)"
    rm -f "$LATEST_PTR" 2>/dev/null
fi
# Legacy fallback: non-qualified pointer from older versions
if [[ -z "$METADATA_FILE" ]] || [[ ! -f "$METADATA_FILE" ]]; then
    LEGACY_PTR="${TMPDIR:-/tmp}/.worktree-exit-metadata-latest"
    if [[ -f "$LEGACY_PTR" ]]; then
        METADATA_FILE="$(cat "$LEGACY_PTR" 2>/dev/null)"
        rm -f "$LEGACY_PTR" 2>/dev/null
    fi
fi
if [[ -z "$METADATA_FILE" ]] || [[ ! -f "$METADATA_FILE" ]]; then
    # Glob fallback: ls -t sorts newest first; take the first valid PID-qualified file
    METADATA_FILE=""
    while IFS= read -r _cand; do
        [[ -f "$_cand" ]] && { METADATA_FILE="$_cand"; break; }
    done < <(ls -t "${TMPDIR:-/tmp}"/.worktree-exit-metadata-[0-9]* 2>/dev/null)
fi
if [[ -z "$METADATA_FILE" ]] || [[ ! -f "$METADATA_FILE" ]]; then
    exit 0
fi

# Staleness check: discard metadata older than 300 seconds to prevent cross-session corruption
METADATA_TS=""
WORKTREE_PATH=""
PROJECT_NAME=""
BRANCH=""
while IFS='=' read -r key value; do
    case "$key" in
        WORKTREE_PATH) WORKTREE_PATH="$value" ;;
        PROJECT_NAME)  PROJECT_NAME="$value" ;;
        BRANCH)        BRANCH="$value" ;;
        TIMESTAMP)     METADATA_TS="$value" ;;
    esac
done < "$METADATA_FILE"
rm -f "$METADATA_FILE" 2>/dev/null

if [[ -n "$METADATA_TS" ]]; then
    NOW_TS="$(date +%s)"
    AGE=$((NOW_TS - METADATA_TS))
    if [[ $AGE -gt 300 ]]; then
        exit 0
    fi
fi

# If metadata is incomplete, nothing to do
if [[ -z "$WORKTREE_PATH" ]] || [[ -z "$PROJECT_NAME" ]] || [[ -z "$BRANCH" ]]; then
    exit 0
fi

# If the worktree directory still exists, action was "keep" — don't touch the registry
if [[ -d "$WORKTREE_PATH" ]]; then
    exit 0
fi

# Worktree was removed — update registry
source "$WTX_ROOT/lib/worktree-tui.sh" 2>/dev/null || {
    update_registry() { :; }
}

update_registry remove "$PROJECT_NAME" "$BRANCH" "" "removed" "$WORKTREE_PATH"
