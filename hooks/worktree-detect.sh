#!/bin/bash
# Worktree Detect Hook (SessionStart)
# Checks for WORKTREE_CONTEXT.md and prints context if found.
#
# ERROR HANDLING: No set -e. Best-effort display. Silent exit if not in a worktree.

# Check both CWD and CLAUDE_PROJECT_DIR for worktree context
CONTEXT_FILE="WORKTREE_CONTEXT.md"
if [ -f "$CONTEXT_FILE" ]; then
    : # Found in CWD
elif [ -n "$CLAUDE_PROJECT_DIR" ] && [ -f "$CLAUDE_PROJECT_DIR/WORKTREE_CONTEXT.md" ]; then
    CONTEXT_FILE="$CLAUDE_PROJECT_DIR/WORKTREE_CONTEXT.md"
else
    exit 0
fi

echo ""
echo "📂 Worktree session detected:"
echo ""
cat "$CONTEXT_FILE" 2>/dev/null || true
echo ""

# Check for uncommitted changes
CHANGES_COUNT="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$CHANGES_COUNT" -gt 0 ]]; then
    echo "⚠  $CHANGES_COUNT uncommitted changes in this worktree"
fi
