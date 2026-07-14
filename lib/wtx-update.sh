#!/usr/bin/env bash
# Shared update logic for `wtx update` and the installer wizard.
#
# Two layers are refreshed, mirroring the two install layers:
#   1. Toolkit  — the wtx git checkout at $WTX_ROOT (git pull --ff-only).
#   2. Project  — the per-workspace artifacts under $WORKSPACE_ROOT
#                 (.claude/hooks/, with a wtx.toml schema-drift hint).
#
# bash 3.2 compatible (no associative arrays, no `declare -A`). Results are
# returned through documented globals so callers can build a summary.
#
# ERROR HANDLING: graceful — `set -u` style, never `set -e`. A missing git
# checkout or local changes are *skipped with a clear note*, not hard failures;
# only a failed `git pull --ff-only` returns non-zero.

if [[ "${_WTX_UPDATE_LIB_LOADED:-0}" -eq 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
_WTX_UPDATE_LIB_LOADED=1

# Read the VERSION file from a checkout root, trimmed (mirrors bin/wtx _wtx_version).
_wtx_update_read_version() {
    local root="$1" v=""
    if [[ -f "$root/VERSION" ]]; then
        v="$(cat "$root/VERSION" 2>/dev/null)"
    fi
    v="$(printf '%s' "$v" | tr -d '[:space:]\r')"
    v="${v#v}"
    printf '%s' "${v:-0.1.0-dev}"
}

# Echo the upstream ref (e.g. "origin/main") for $WTX_ROOT's current branch, or
# nothing if the branch has no tracking configured.
_wtx_update_upstream() {
    git -C "$WTX_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null
}

# Build an actionable "no upstream" message naming the current branch.
_wtx_update_no_upstream_msg() {
    local branch
    branch="$(git -C "$WTX_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    branch="${branch:-main}"
    printf 'no upstream tracking branch — set it with: git branch --set-upstream-to=origin/%s %s' \
        "$branch" "$branch"
}

# ---------------------------------------------------------------------------
# Layer 1 — toolkit checkout. Sets:
#   _WTX_UPDATE_TOOLKIT_STATUS  updated | up-to-date | skipped | failed | available
#   _WTX_UPDATE_TOOLKIT_MSG     human-readable detail
#   _WTX_UPDATE_VER_BEFORE / _WTX_UPDATE_VER_AFTER
#   _WTX_UPDATE_SHA_BEFORE / _WTX_UPDATE_SHA_AFTER
# Returns 1 only on a real pull failure.
# ---------------------------------------------------------------------------
wtx_update_toolkit() {
    local dry_run=0
    [[ "${1:-}" = "--dry-run" ]] && dry_run=1

    _WTX_UPDATE_TOOLKIT_STATUS=""
    _WTX_UPDATE_TOOLKIT_MSG=""
    _WTX_UPDATE_VER_BEFORE="$(_wtx_update_read_version "$WTX_ROOT")"
    _WTX_UPDATE_VER_AFTER="$_WTX_UPDATE_VER_BEFORE"
    _WTX_UPDATE_SHA_BEFORE=""
    _WTX_UPDATE_SHA_AFTER=""

    if ! git -C "$WTX_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        _WTX_UPDATE_TOOLKIT_STATUS="skipped"
        _WTX_UPDATE_TOOLKIT_MSG="$WTX_ROOT is not a git checkout (zip install?) — update manually"
        return 0
    fi

    _WTX_UPDATE_SHA_BEFORE="$(git -C "$WTX_ROOT" rev-parse --short HEAD 2>/dev/null)"
    _WTX_UPDATE_SHA_AFTER="$_WTX_UPDATE_SHA_BEFORE"

    if [[ -n "$(git -C "$WTX_ROOT" status --porcelain 2>/dev/null)" ]]; then
        _WTX_UPDATE_TOOLKIT_STATUS="skipped"
        _WTX_UPDATE_TOOLKIT_MSG="local changes in $WTX_ROOT — commit or stash, then re-run"
        return 0
    fi

    # No upstream tracking → can't compare or pull. Skip gracefully (with a fix
    # hint) rather than letting `git pull --ff-only` fail loudly. Keeps the apply
    # path consistent with --check, and matches the codebase's graceful posture.
    if [[ -z "$(_wtx_update_upstream)" ]]; then
        _WTX_UPDATE_TOOLKIT_STATUS="skipped"
        _WTX_UPDATE_TOOLKIT_MSG="$(_wtx_update_no_upstream_msg)"
        return 0
    fi

    if [[ $dry_run -eq 1 ]]; then
        git -C "$WTX_ROOT" fetch --quiet 2>/dev/null
        local behind=""
        behind="$(git -C "$WTX_ROOT" rev-list --count 'HEAD..@{u}' 2>/dev/null)"
        if [[ -z "$behind" ]]; then
            # Upstream existed above but the count couldn't be computed (e.g. a
            # fetch hiccup); report a skip rather than a false "up to date".
            _WTX_UPDATE_TOOLKIT_STATUS="skipped"
            _WTX_UPDATE_TOOLKIT_MSG="could not compare against upstream — try again"
        elif [[ "$behind" -gt 0 ]]; then
            _WTX_UPDATE_TOOLKIT_STATUS="available"
            _WTX_UPDATE_TOOLKIT_MSG="$behind commit(s) available — run 'wtx update' to apply"
        else
            _WTX_UPDATE_TOOLKIT_STATUS="up-to-date"
            _WTX_UPDATE_TOOLKIT_MSG="already current"
        fi
        return 0
    fi

    local out rc
    out="$(git -C "$WTX_ROOT" pull --ff-only 2>&1)"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        _WTX_UPDATE_TOOLKIT_STATUS="failed"
        _WTX_UPDATE_TOOLKIT_MSG="git pull --ff-only failed: $(printf '%s' "$out" | tr '\n' ' ')"
        return 1
    fi

    _WTX_UPDATE_SHA_AFTER="$(git -C "$WTX_ROOT" rev-parse --short HEAD 2>/dev/null)"
    _WTX_UPDATE_VER_AFTER="$(_wtx_update_read_version "$WTX_ROOT")"
    if [[ "$_WTX_UPDATE_SHA_AFTER" = "$_WTX_UPDATE_SHA_BEFORE" ]]; then
        _WTX_UPDATE_TOOLKIT_STATUS="up-to-date"
        _WTX_UPDATE_TOOLKIT_MSG="already current"
    else
        _WTX_UPDATE_TOOLKIT_STATUS="updated"
        _WTX_UPDATE_TOOLKIT_MSG="${_WTX_UPDATE_SHA_BEFORE} -> ${_WTX_UPDATE_SHA_AFTER}"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Layer 2a — per-project Claude Code hooks. Sets:
#   _WTX_UPDATE_HOOKS_STATUS  refreshed | none | failed | available
#   _WTX_UPDATE_HOOKS_COUNT
# Only refreshes when hooks were previously installed in this workspace; it
# never installs hooks into a workspace that does not already use them.
# Reuses install.sh --hooks (the same copy path the installer uses).
# Returns 1 only on a real copy failure.
# ---------------------------------------------------------------------------
wtx_update_hooks() {
    local dry_run=0
    [[ "${1:-}" = "--dry-run" ]] && dry_run=1

    _WTX_UPDATE_HOOKS_STATUS=""
    _WTX_UPDATE_HOOKS_COUNT=0

    local destdir="$WORKSPACE_ROOT/.claude/hooks"
    # Keep in sync with install_hooks() in install.sh. A workspace that predates
    # the builtin-worktree-* hooks still matches on the original three, so the
    # refresh below (install.sh --hooks) adds the new ones on the next update.
    local found=0 h
    for h in worktree-create.sh worktree-detect.sh worktree-remove.sh \
             builtin-worktree-cleanup.sh builtin-worktree-enhance.sh \
             builtin-worktree-post-exit.sh; do
        [[ -f "$destdir/$h" ]] && found=$((found + 1))
    done

    if [[ $found -eq 0 ]]; then
        _WTX_UPDATE_HOOKS_STATUS="none"
        _WTX_UPDATE_HOOKS_MSG="not installed in this workspace"
        return 0
    fi
    _WTX_UPDATE_HOOKS_COUNT=$found

    if [[ $dry_run -eq 1 ]]; then
        _WTX_UPDATE_HOOKS_STATUS="available"
        _WTX_UPDATE_HOOKS_MSG="$found hook(s) would be refreshed from $WTX_ROOT/hooks/"
        return 0
    fi

    local old_pwd rc=0
    old_pwd="$(pwd)"
    if ! cd "$WORKSPACE_ROOT"; then
        _WTX_UPDATE_HOOKS_STATUS="failed"
        _WTX_UPDATE_HOOKS_MSG="cannot cd to workspace root: $WORKSPACE_ROOT"
        return 1
    fi
    bash "$WTX_ROOT/install.sh" --hooks >/dev/null 2>&1
    rc=$?
    cd "$old_pwd" || true
    if [[ $rc -ne 0 ]]; then
        _WTX_UPDATE_HOOKS_STATUS="failed"
        _WTX_UPDATE_HOOKS_MSG="install.sh --hooks exited $rc"
        return 1
    fi
    _WTX_UPDATE_HOOKS_STATUS="refreshed"
    _WTX_UPDATE_HOOKS_MSG="$found hook(s) re-copied from $WTX_ROOT/hooks/"
    return 0
}

# ---------------------------------------------------------------------------
# Layer 2b — wtx.toml schema drift (advisory only, never rewrites). Sets:
#   _WTX_UPDATE_TOML_STATUS   up-to-date | drift | none
# Compares the uncommented section headers + scalar keys shipped in
# wtx.example.toml against the workspace wtx.toml. The [jira.projects] body is
# user-defined (repo => key) so its mappings are intentionally not compared.
# ---------------------------------------------------------------------------
wtx_update_check_schema() {
    _WTX_UPDATE_TOML_STATUS=""
    _WTX_UPDATE_TOML_MSG=""

    local user_toml="$WORKSPACE_ROOT/wtx.toml"
    local example="$WTX_ROOT/wtx.example.toml"
    if [[ ! -f "$user_toml" ]]; then
        _WTX_UPDATE_TOML_STATUS="none"
        _WTX_UPDATE_TOML_MSG="no wtx.toml in this workspace"
        return 0
    fi
    if [[ ! -f "$example" ]]; then
        _WTX_UPDATE_TOML_STATUS="up-to-date"
        _WTX_UPDATE_TOML_MSG="no schema reference to compare"
        return 0
    fi

    # Tokens = uncommented section headers and top-level scalar keys in the
    # example. grep over the user file for each (commented or not is fine — we
    # only care that the user knows the key exists).
    local tokens token missing=""
    tokens="$(grep -E '^\[|^[A-Za-z_]+ *=' "$example" 2>/dev/null \
        | sed -E 's/ *=.*//' \
        | grep -v -E '^\[jira\.projects\]$')"

    local OLDIFS="$IFS"
    IFS=$'\n'
    for token in $tokens; do
        [[ -z "$token" ]] && continue
        if ! grep -qF "$token" "$user_toml" 2>/dev/null; then
            missing="${missing:+$missing, }${token}"
        fi
    done
    IFS="$OLDIFS"

    if [[ -n "$missing" ]]; then
        _WTX_UPDATE_TOML_STATUS="drift"
        _WTX_UPDATE_TOML_MSG="new keys available ($missing) — run 'wtx install' (merge) to adopt them"
    else
        _WTX_UPDATE_TOML_STATUS="up-to-date"
        _WTX_UPDATE_TOML_MSG="all known keys present"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Render the summary. Uses tui_style_box when available (sourced by the
# wizard); otherwise falls back to a plain bracketed list.
# ---------------------------------------------------------------------------
wtx_update_report() {
    local toolkit_line
    case "${_WTX_UPDATE_TOOLKIT_STATUS:-}" in
        updated)    toolkit_line="toolkit:  v${_WTX_UPDATE_VER_BEFORE} -> v${_WTX_UPDATE_VER_AFTER} (${_WTX_UPDATE_TOOLKIT_MSG})" ;;
        up-to-date) toolkit_line="toolkit:  v${_WTX_UPDATE_VER_AFTER} (up to date)" ;;
        available)  toolkit_line="toolkit:  ${_WTX_UPDATE_TOOLKIT_MSG}" ;;
        skipped)    toolkit_line="toolkit:  skipped — ${_WTX_UPDATE_TOOLKIT_MSG}" ;;
        failed)     toolkit_line="toolkit:  FAILED — ${_WTX_UPDATE_TOOLKIT_MSG}" ;;
        *)          toolkit_line="toolkit:  (not checked)" ;;
    esac

    local lines=("wtx update" "" "$toolkit_line")

    if [[ -n "${_WTX_UPDATE_HOOKS_STATUS:-}" ]]; then
        case "$_WTX_UPDATE_HOOKS_STATUS" in
            refreshed) lines+=("hooks:    refreshed ${_WTX_UPDATE_HOOKS_COUNT} file(s)") ;;
            available) lines+=("hooks:    ${_WTX_UPDATE_HOOKS_MSG}") ;;
            none)      lines+=("hooks:    ${_WTX_UPDATE_HOOKS_MSG}") ;;
            failed)    lines+=("hooks:    FAILED — ${_WTX_UPDATE_HOOKS_MSG}") ;;
        esac
    fi

    if [[ -n "${_WTX_UPDATE_TOML_STATUS:-}" ]]; then
        case "$_WTX_UPDATE_TOML_STATUS" in
            up-to-date) lines+=("wtx.toml: up to date") ;;
            drift)      lines+=("wtx.toml: ${_WTX_UPDATE_TOML_MSG}") ;;
            none)       lines+=("wtx.toml: ${_WTX_UPDATE_TOML_MSG}") ;;
        esac
    fi

    if command -v tui_style_box >/dev/null 2>&1; then
        tui_style_box "${lines[@]}"
    else
        local l
        for l in "${lines[@]}"; do
            printf '  %s\n' "$l"
        done
    fi
}

# ---------------------------------------------------------------------------
# Orchestrator shared by `wtx update` and the installer wizard.
#   --check         dry-run: report what would change, touch nothing
#   --toolkit-only  skip the per-project (hooks + schema) layer
# Returns non-zero only when a hard step (toolkit pull / hook copy) failed.
# ---------------------------------------------------------------------------
wtx_update_run() {
    local dry=0 toolkit_only=0 arg
    for arg in "$@"; do
        case "$arg" in
            --check|--dry-run) dry=1 ;;
            --toolkit-only)    toolkit_only=1 ;;
            --yes|-y)          : ;;  # non-interactive; reserved for future prompts
            *) printf 'wtx update: unknown option: %s\n' "$arg" >&2; return 2 ;;
        esac
    done

    # Branch rather than expand a possibly-empty array — "${arr[@]}" on an empty
    # array trips `set -u` on bash 3.2 (macOS default).
    local rc=0
    if [[ $dry -eq 1 ]]; then
        wtx_update_toolkit --dry-run || rc=$?
    else
        wtx_update_toolkit || rc=$?
    fi
    if [[ $toolkit_only -eq 0 ]]; then
        if [[ $dry -eq 1 ]]; then
            wtx_update_hooks --dry-run || rc=$?
        else
            wtx_update_hooks || rc=$?
        fi
        wtx_update_check_schema || true
    fi
    wtx_update_report
    return $rc
}
