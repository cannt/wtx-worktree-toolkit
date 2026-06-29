#!/bin/bash
# Built-in Worktree Enhancement Script
# Enhances a worktree created by Claude Code's EnterWorktree with Android-specific setup.
#
# Usage: bash scripts/worktree/builtin-worktree-enhance.sh [worktree-path] [project-dir]
#
# Called automatically via PostToolUse hook on EnterWorktree, or manually after entering.
#
# What it does:
#   1. Runs the configured worktree.setup_hook (e.g. plugins/android-setup.sh)
#   2. Generates WORKTREE_CONTEXT.md
#   3. Updates the worktree registry
#
# ERROR HANDLING: No set -e. Best-effort — failures don't block the session.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Prefer env from `bin/wtx` dispatcher; self-resolve when invoked directly.
: "${WTX_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
# WORKSPACE_ROOT: prefer the main repo's root even when invoked from inside a
# linked worktree (show-toplevel would return the worktree path instead).
if [[ -z "${WORKSPACE_ROOT:-}" ]]; then
    _wtx_gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [[ -n "$_wtx_gcd" && -d "$_wtx_gcd" ]]; then
        WORKSPACE_ROOT="$(dirname "$_wtx_gcd")"
    else
        WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    unset _wtx_gcd
fi

WORKTREE_PATH="${1:-$PWD}"
PROJECT_DIR="${2:-}"

# Source TUI library for registry (with stub fallback)
source "$WTX_ROOT/lib/worktree-tui.sh" 2>/dev/null || {
    echo "Warning: worktree-tui.sh not found — registry will not be updated" >&2
    update_registry() { :; }
}

# Validate: must be a git worktree (.git is a file, not directory)
if [[ ! -f "$WORKTREE_PATH/.git" ]]; then
    echo "Not a worktree (no .git file): $WORKTREE_PATH" >&2
    exit 0
fi

# Skip if WORKTREE_CONTEXT.md already exists (already enhanced or custom worktree)
# Use --force as $3 to re-run enhancement (e.g., after partial failure)
FORCE="${3:-}"
if [[ -f "$WORKTREE_PATH/WORKTREE_CONTEXT.md" ]] && [[ "$FORCE" != "--force" ]]; then
    exit 0
fi

# Auto-detect project dir by finding the main repo from the worktree's .git file
if [[ -z "$PROJECT_DIR" ]]; then
    GITDIR="$(sed 's/^gitdir: //; s/\r$//' "$WORKTREE_PATH/.git" 2>/dev/null)"
    if [[ -n "$GITDIR" ]]; then
        # Resolve relative paths
        if [[ ! "$GITDIR" = /* ]]; then
            GITDIR="$(cd "$WORKTREE_PATH" && cd "$(dirname "$GITDIR")" 2>/dev/null && pwd)/$(basename "$GITDIR")"
        fi
        # .git/worktrees/<name> -> .git/worktrees -> .git -> repo root
        GIT_DIR_PARENT="$(cd "$GITDIR/../.." 2>/dev/null && pwd)"
        if [[ -n "$GIT_DIR_PARENT" ]] && [[ -d "$GIT_DIR_PARENT" ]]; then
            PROJECT_DIR="$(dirname "$GIT_DIR_PARENT")"
        fi
    fi
fi

if [[ -z "$PROJECT_DIR" ]] || [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Warning: Could not detect project directory" >&2
    exit 0
fi

PROJECT_NAME="$(basename "$PROJECT_DIR")"
BRANCH="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)"

# Detect base branch: the branch HEAD was on when EnterWorktree created this worktree.
# EnterWorktree branches from HEAD, so the base is whatever branch HEAD points to in the main repo.
BASE_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
if [[ -z "$BASE_BRANCH" ]] || [[ "$BASE_BRANCH" == "HEAD" ]]; then
    # Fallback: use the SHA if main repo is in detached HEAD
    BASE_BRANCH="$(git -C "$WORKTREE_PATH" rev-parse HEAD 2>/dev/null)"
fi
# Step 1: Run configured setup hook (opt-in via `worktree.setup_hook` in wtx.toml).
if [[ -f "$WTX_ROOT/lib/wtx-config.sh" ]]; then
    # shellcheck source=../lib/wtx-config.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-config.sh" 2>/dev/null || true
fi
SETUP_HOOK=""
if command -v wtx_config_get >/dev/null 2>&1; then
    SETUP_HOOK="$(wtx_config_get "worktree.setup_hook")"
fi
if [[ -n "$SETUP_HOOK" ]]; then
    if [[ "$SETUP_HOOK" != /* ]]; then
        SETUP_HOOK="$WTX_ROOT/$SETUP_HOOK"
    fi
    if [[ -f "$SETUP_HOOK" ]]; then
        bash "$SETUP_HOOK" "$WORKTREE_PATH" "$PROJECT_DIR" 2>/dev/null
    fi
fi

# Seed a knowledge graph into the new worktree so `graphify query` works
# immediately (opt-out via `worktree.graphify_on_create = false`). The plugin
# self-skips when the graphify CLI isn't installed, so default-on is safe.
GRAPHIFY_ON_CREATE="true"
if command -v wtx_config_get >/dev/null 2>&1; then
    GRAPHIFY_ON_CREATE="$(wtx_config_get "worktree.graphify_on_create" "true")"
fi
case "$GRAPHIFY_ON_CREATE" in
    false|0|no|off) : ;;  # explicitly disabled
    *)
        GRAPHIFY_HOOK="$WTX_ROOT/plugins/graphify-setup.sh"
        if [[ -f "$GRAPHIFY_HOOK" ]]; then
            bash "$GRAPHIFY_HOOK" "$WORKTREE_PATH" "$PROJECT_DIR" 2>/dev/null
        fi
        ;;
esac

# Extract ticket ID from branch name or worktree name (e.g. PROJ-1234-my-feature)
REGISTRY_NAME="$(basename "$WORKTREE_PATH")"
TICKET="N/A"
if [[ "$BRANCH" =~ ([A-Z]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
elif [[ "$REGISTRY_NAME" =~ ([A-Z]+-[0-9]+) ]]; then
    TICKET="${BASH_REMATCH[1]}"
fi

# Preserve original Created date on --force re-runs so we don't reset it
CREATED_DATE="$(date +%Y-%m-%d)"
if [[ -f "$WORKTREE_PATH/WORKTREE_CONTEXT.md" ]] && [[ "$FORCE" == "--force" ]]; then
    OLD_DATE="$(grep '^\- \*\*Created:\*\*' "$WORKTREE_PATH/WORKTREE_CONTEXT.md" 2>/dev/null | sed 's/.*\*\*Created:\*\* *//' | tr -d '[:space:]')"
    [[ -n "$OLD_DATE" ]] && CREATED_DATE="$OLD_DATE"
fi

# Step 2: Generate WORKTREE_CONTEXT.md
cat > "$WORKTREE_PATH/WORKTREE_CONTEXT.md" <<EOF
# Worktree Context
- **Project:** $PROJECT_NAME
- **Branch:** $BRANCH
- **Base Branch:** $BASE_BRANCH
- **Created:** $CREATED_DATE
- **Ticket:** $TICKET
- **Worktree Path:** $WORKTREE_PATH
- **Main Repo:** $PROJECT_DIR
- **Type:** builtin
EOF

# Step 3: Update worktree registry (use full BASE_BRANCH — truncation breaks git log in refresh)
update_registry add "$PROJECT_NAME" "$BRANCH" "$BASE_BRANCH" "$WORKTREE_PATH" "$REGISTRY_NAME" "builtin"

echo "Enhanced: $WORKTREE_PATH ($PROJECT_NAME)"
