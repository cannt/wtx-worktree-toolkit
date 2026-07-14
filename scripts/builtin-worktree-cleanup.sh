#!/bin/bash
# Built-in Worktree Cleanup Script (PreToolUse phase)
# Runs before ExitWorktree. Cleans .build-cache and saves metadata for post-exit registry update.
#
# Usage: bash scripts/worktree/builtin-worktree-cleanup.sh [worktree-path]
#
# Called automatically via PreToolUse hook on ExitWorktree, or manually.
# Only operates on built-in worktrees (under .claude/worktrees/).
# Silently exits for custom worktrees (handled by worktree-done.sh).
#
# Registry update is deferred to builtin-worktree-post-exit.sh (PostToolUse),
# which verifies the outcome by checking if the directory still exists.
# The action is read from stdin (hook JSON) to conditionally preserve .build-cache.
#
# ERROR HANDLING: No set -e. Best-effort — failures don't block ExitWorktree.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# NOTE: this script deliberately needs no WTX_ROOT/WORKSPACE_ROOT. It derives
# everything it needs from the worktree path itself and hands the registry update
# off to builtin-worktree-post-exit.sh, so it works from any install layout.

WORKTREE_PATH="${1:-$PWD}"

# Read the ExitWorktree action from hook stdin (JSON tool input).
# Only attempted when stdin is a pipe (hook context), not a TTY (manual invocation).
# If action is "keep", we must NOT delete the build cache — the worktree will live on.
HOOK_ACTION=""
if [[ ! -t 0 ]]; then
    HOOK_ACTION="$(python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('action',''))" 2>/dev/null)"
fi

# Only operate on built-in worktrees
if [[ "$WORKTREE_PATH" != *"/.claude/worktrees/"* ]]; then
    exit 0
fi

# Validate: must be a git worktree
if [[ ! -f "$WORKTREE_PATH/.git" ]]; then
    exit 0
fi

# Get branch and project info before cleanup (needed by post-exit script)
BRANCH="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)"

PROJECT_NAME=""
GITDIR="$(sed 's/^gitdir: //; s/\r$//' "$WORKTREE_PATH/.git" 2>/dev/null)"
if [[ -n "$GITDIR" ]]; then
    if [[ ! "$GITDIR" = /* ]]; then
        GITDIR="$(cd "$WORKTREE_PATH" && cd "$(dirname "$GITDIR")" 2>/dev/null && pwd)/$(basename "$GITDIR")"
    fi
    GIT_DIR_PARENT="$(cd "$GITDIR/../.." 2>/dev/null && pwd)"
    if [[ -n "$GIT_DIR_PARENT" ]] && [[ -d "$GIT_DIR_PARENT" ]]; then
        PROJECT_NAME="$(basename "$(dirname "$GIT_DIR_PARENT")")"
    fi
fi

# Save metadata for post-exit registry update
# PID-qualified filename prevents race conditions if multiple sessions exit concurrently.
# Written with printf (not heredoc) to prevent shell expansion in branch names.
METADATA_FILE="${TMPDIR:-/tmp}/.worktree-exit-metadata-$$"
printf 'WORKTREE_PATH=%s\nPROJECT_NAME=%s\nBRANCH=%s\nTIMESTAMP=%s\nMETADATA_FILE=%s\n' \
    "$WORKTREE_PATH" "$PROJECT_NAME" "$BRANCH" "$(date +%s)" "$METADATA_FILE" > "$METADATA_FILE"

# Write the metadata file path to a PPID-qualified pointer so post-exit can find it.
# PPID identifies the parent Claude Code process, shared by pre-exit and post-exit hooks
# within the same session, avoiding collisions between concurrent sessions.
echo "$METADATA_FILE" > "${TMPDIR:-/tmp}/.worktree-exit-metadata-latest-${PPID:-0}"

# Clean .build-cache only when removing the worktree, not when keeping it.
# Keeping the worktree implies re-entry later — destroying the cache forces a full rebuild.
if [[ "$HOOK_ACTION" != "keep" ]] && [[ -d "$WORKTREE_PATH/.build-cache" ]]; then
    rm -rf "$WORKTREE_PATH/.build-cache" 2>/dev/null
fi

# Same gating as .build-cache: drop the per-worktree knowledge graph only when
# actually removing the worktree, never when keeping it for re-entry (a kept
# worktree wants its graph to survive).
if [[ "$HOOK_ACTION" != "keep" ]] && [[ -d "$WORKTREE_PATH/graphify-out" ]]; then
    rm -rf "$WORKTREE_PATH/graphify-out" 2>/dev/null
fi
