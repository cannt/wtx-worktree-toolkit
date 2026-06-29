#!/bin/bash
# Worktree Remove Hook
# Programmatic entry point for Claude to remove worktrees.
#
# Usage: bash .claude/hooks/worktree-remove.sh <worktree-path>
#
# Contract:
#   - On success: prints removed path to stdout
#   - On failure: stderr message, exit 1
#
# ERROR HANDLING: No set -e. Graceful failure.

WORKTREE_PATH="$1"

if [[ -z "$WORKTREE_PATH" ]]; then
    echo "Usage: $0 <worktree-path>" >&2
    exit 1
fi

if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Path does not exist: $WORKTREE_PATH" >&2
    exit 1
fi

# Verify it's a worktree (.git is a file, not directory)
if [[ ! -f "$WORKTREE_PATH/.git" ]]; then
    echo "Error: Not a worktree (no .git file): $WORKTREE_PATH" >&2
    exit 1
fi

# Check uncommitted changes — block removal if dirty
CHANGES="$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null)"
if [[ -n "$CHANGES" ]]; then
    CHANGE_COUNT="$(echo "$CHANGES" | wc -l | tr -d ' ')"
    echo "Error: Worktree has $CHANGE_COUNT uncommitted changes. Commit or stash first." >&2
    echo "To force removal: git -C <main-repo> worktree remove --force $WORKTREE_PATH" >&2
    exit 1
fi

# Find main repo from .git file
GITDIR="$(sed 's/^gitdir: //; s/\r$//' "$WORKTREE_PATH/.git" 2>/dev/null)"
if [[ -z "$GITDIR" ]]; then
    echo "Error: Could not parse .git file" >&2
    exit 1
fi

# Resolve relative gitdir paths
if [[ ! "$GITDIR" = /* ]]; then
    GITDIR="$(cd "$WORKTREE_PATH" && cd "$(dirname "$GITDIR")" && pwd)/$(basename "$GITDIR")"
fi

# Walk up from .git/worktrees/<name> to .git to repo root
MAIN_GIT="$(cd "$GITDIR/../.." 2>/dev/null && pwd)"
if [[ -z "$MAIN_GIT" ]] || [[ ! -d "$MAIN_GIT" ]]; then
    echo "Error: Could not determine main repo path" >&2
    exit 1
fi
MAIN_REPO="$(dirname "$MAIN_GIT")"

# Clean .build-cache
if [[ -d "$WORKTREE_PATH/.build-cache" ]]; then
    rm -rf "$WORKTREE_PATH/.build-cache" 2>/dev/null
    echo "Cleaned .build-cache/" >/dev/tty 2>/dev/null || true
fi

# Remove the per-worktree knowledge graph before `git worktree remove`, so an
# un-gitignored graphify-out/ can't trip git's untracked-files guard.
if [[ -d "$WORKTREE_PATH/graphify-out" ]]; then
    rm -rf "$WORKTREE_PATH/graphify-out" 2>/dev/null
    echo "Cleaned graphify-out/" >/dev/tty 2>/dev/null || true
fi

# Remove worktree
git -C "$MAIN_REPO" worktree remove "$WORKTREE_PATH" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo "Error: Could not remove worktree. It may have uncommitted changes." >&2
    echo "Try: git -C $MAIN_REPO worktree remove --force $WORKTREE_PATH" >&2
    exit 1
fi

echo "$WORKTREE_PATH"
