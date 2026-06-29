#!/bin/bash
# Graphify Worktree Setup
# Seeds a freshly created worktree with a knowledge graph so `graphify query`
# works immediately, then lets graphify's own git post-commit hook keep it fresh.
# Called by worktree-start.sh and builtin-worktree-enhance.sh after `git worktree add`.
#
# Behavior:
#   - graphify CLI not installed       -> skip silently (exit 0)
#   - source repo already has a graph  -> copy it in (instant, and accurate
#                                         because a new worktree == its base
#                                         branch at creation time)
#   - graphify installed, no graph yet -> build one in the background
#
# Usage: ./plugins/graphify-setup.sh <worktree-path> <source-project-path>
#
# ERROR HANDLING: No set -e. Every step is best-effort; a graph failure must
# never block worktree creation. Always exits 0.

WORKTREE_PATH="$1"
SOURCE_PROJECT="$2"

# Announce on the controlling tty when present (so it shows during interactive
# `wtx start`), otherwise fall back to stdout.
_g_say() { ( echo "  [graphify] $*" >/dev/tty ) 2>/dev/null || echo "  [graphify] $*"; }

if [[ -z "$WORKTREE_PATH" ]] || [[ -z "$SOURCE_PROJECT" ]]; then
    echo "Usage: $0 <worktree-path> <source-project-path>" >&2
    exit 0
fi
[[ -d "$WORKTREE_PATH" ]] || exit 0

# 1) Graceful skip when graphify is not available on this machine.
if ! command -v graphify >/dev/null 2>&1; then
    exit 0
fi

# Idempotent: never clobber a graph that already exists in the worktree.
if [[ -e "$WORKTREE_PATH/graphify-out/graph.json" ]]; then
    exit 0
fi

SRC_GRAPH="$SOURCE_PROJECT/graphify-out"

if [[ -f "$SRC_GRAPH/graph.json" ]]; then
    # 2) Seed from the source repo's graph — instant and accurate, since the new
    #    branch is identical to its base at creation time.
    if cp -R "$SRC_GRAPH" "$WORKTREE_PATH/graphify-out" 2>/dev/null; then
        # Pin the graph root to the worktree itself so the shared post-commit
        # hook rebuilds *this* worktree (not the source repo) on later commits.
        printf '.' > "$WORKTREE_PATH/graphify-out/.graphify_root" 2>/dev/null
        _g_say "seeded knowledge graph from $(basename "$SOURCE_PROJECT")"
    else
        _g_say "could not copy graph from source; skipping"
    fi
else
    # 3) No graph in the source yet — build one without blocking creation.
    _g_say "no source graph; building in background (graphify update)"
    ( cd "$WORKTREE_PATH" && graphify update . >/dev/null 2>&1 & ) >/dev/null 2>&1
fi

exit 0
