#!/bin/bash
# Worktree Create Hook
# Programmatic entry point for Claude to create worktrees.
#
# CRITICAL CONTRACT:
#   - ONLY the absolute worktree path is printed to stdout on success
#   - ALL progress messages go to /dev/tty
#   - Error messages go to stderr
#   - On failure: stderr message, exit 1, NO stdout
#
# Usage: bash .claude/hooks/worktree-create.sh <worktree-name> [project-dir]
#
# ERROR HANDLING: No set -e. Fail gracefully.

NAME="$1"
PROJECT_DIR="$2"
BASE_BRANCH="${3:-develop}"

if [[ -z "$NAME" ]]; then
    echo "Usage: $0 <worktree-name> [project-dir] [base-branch]" >&2
    exit 1
fi

# WORKSPACE_ROOT: prefer dispatcher env, then CLAUDE_PROJECT_ROOT; otherwise
# resolve the main repo (not the current linked worktree).
if [[ -z "${WORKSPACE_ROOT:-}" ]]; then
    if [[ -n "${CLAUDE_PROJECT_ROOT:-}" ]]; then
        WORKSPACE_ROOT="$CLAUDE_PROJECT_ROOT"
    else
        _wtx_gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
        if [[ -n "$_wtx_gcd" && -d "$_wtx_gcd" ]]; then
            WORKSPACE_ROOT="$(dirname "$_wtx_gcd")"
        else
            WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
        fi
        unset _wtx_gcd
    fi
fi

# Resolve WTX_ROOT: prefer env from dispatcher; else self-resolve from this
# hook's own location (hooks/ is a sibling of lib/ in the wtx install).
if [[ -z "${WTX_ROOT:-}" ]]; then
    _wtx_hook_self="${BASH_SOURCE[0]}"
    while [[ -L "$_wtx_hook_self" ]]; do
        _wtx_hook_link="$(readlink "$_wtx_hook_self")"
        if [[ "$_wtx_hook_link" = /* ]]; then
            _wtx_hook_self="$_wtx_hook_link"
        else
            _wtx_hook_self="$(cd "$(dirname "$_wtx_hook_self")" && pwd)/$_wtx_hook_link"
        fi
    done
    WTX_ROOT="$(cd "$(dirname "$_wtx_hook_self")/.." && pwd)"
    unset _wtx_hook_self _wtx_hook_link
fi

# Auto-detect project from pwd — delegates to wtx_detect_project when the
# config loader is reachable, otherwise falls back to `.git`-only walk.
if [[ -f "$WTX_ROOT/lib/wtx-config.sh" ]]; then
    # shellcheck source=../lib/wtx-config.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-config.sh" 2>/dev/null || true
fi
detect_project() {
    if command -v wtx_detect_project >/dev/null 2>&1; then
        wtx_detect_project "$1"
        return $?
    fi
    local dir="$1"
    while [[ "$dir" != "/" ]] && [[ -n "$dir" ]]; do
        if [[ -e "$dir/.git" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(detect_project "$(pwd)")"
    if [[ -z "$PROJECT_DIR" ]]; then
        echo "Error: Could not detect project. Pass project-dir as second argument." >&2
        exit 1
    fi
else
    if [[ ! "$PROJECT_DIR" = /* ]]; then
        PROJECT_DIR="$WORKSPACE_ROOT/$PROJECT_DIR"
    fi
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
    echo "Error: Project directory does not exist: $PROJECT_DIR" >&2
    exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

# Validate NAME: only alphanumeric, hyphens, underscores
if [[ ! "$NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Error: Name must contain only alphanumeric characters, hyphens, and underscores." >&2
    exit 1
fi

# Detect ticket vs named mode
if [[ "$NAME" =~ ^[A-Z]+-[0-9]+$ ]]; then
    TICKET_ID="$NAME"
    BRANCH="feature/$NAME"
else
    TICKET_ID=""
    BRANCH="feature/$NAME"
fi

# Worktree path
WORKTREE_PATH="$(cd "$PROJECT_DIR/.." && pwd)/${PROJECT_NAME}-${NAME}"

# Pre-flight
if [[ -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree already exists: $WORKTREE_PATH" >&2
    exit 1
fi

# Create worktree
echo "Creating worktree: $BRANCH..." >/dev/tty 2>/dev/null || true

if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" "$BRANCH" >/dev/null 2>/dev/tty
else
    git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH" "$BASE_BRANCH" >/dev/null 2>/dev/tty
fi

if [[ $? -ne 0 ]]; then
    echo "Error: git worktree add failed" >&2
    exit 1
fi

# Run configured setup hook (opt-in via `worktree.setup_hook` in wtx.toml).
SETUP_HOOK=""
if command -v wtx_config_get >/dev/null 2>&1; then
    SETUP_HOOK="$(wtx_config_get "worktree.setup_hook")"
fi
if [[ -n "$SETUP_HOOK" ]]; then
    if [[ "$SETUP_HOOK" != /* ]]; then
        SETUP_HOOK="$WTX_ROOT/$SETUP_HOOK"
    fi
    if [[ -f "$SETUP_HOOK" ]]; then
        bash "$SETUP_HOOK" "$WORKTREE_PATH" "$PROJECT_DIR" >/dev/tty 2>/dev/tty || true
    else
        echo "Warning: setup_hook not found at $SETUP_HOOK" >&2
    fi
fi

# Generate WORKTREE_CONTEXT.md
cat > "$WORKTREE_PATH/WORKTREE_CONTEXT.md" <<EOF
# Worktree Context
- **Project:** $PROJECT_NAME
- **Branch:** $BRANCH
- **Base Branch:** $BASE_BRANCH
- **Created:** $(date +%Y-%m-%d)
- **Ticket:** ${TICKET_ID:-N/A}
- **Worktree Path:** $WORKTREE_PATH
- **Main Repo:** $PROJECT_DIR
EOF

echo "✓ Worktree ready" >/dev/tty 2>/dev/null || true

# CRITICAL: stdout = ONLY the absolute path
echo "$WORKTREE_PATH"
