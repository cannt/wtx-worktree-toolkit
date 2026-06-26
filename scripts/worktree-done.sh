#!/bin/bash
# Worktree Done Script
# Cleans up a git worktree with safety checks, work summary, push prompt, and branch cleanup.
#
# Usage: ./scripts/worktree/worktree-done.sh [name-or-path]
#
# If no argument, detects current worktree from pwd.
#
# Environment variables:
#   WORKTREE_DONE_QUIET — set to 1 to suppress browser-open offers (used by worktree-status.sh)
#
# ERROR HANDLING: No set -e. Graceful failure with clear messages.

ARG="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Prefer env from `bin/wtx` dispatcher; self-resolve when invoked directly.
# In the repo layout scripts/ is one level below WTX_ROOT; in the installed
# layout (e.g. repo/scripts/worktree/) the scripts and lib/ share the same
# parent, so WTX_ROOT equals SCRIPT_DIR.
if [[ -z "${WTX_ROOT:-}" ]]; then
    if [[ -d "$SCRIPT_DIR/lib" ]]; then
        WTX_ROOT="$SCRIPT_DIR"
    else
        WTX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    fi
fi
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

# Source shared libraries with inline stub fallbacks
# F13: Inline has_claude checks command -v (not hardcoded false)
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
source "$WTX_ROOT/lib/worktree-api.sh" 2>/dev/null || {
    _load_api_credentials() { return 1; }
    has_api_credentials() { return 1; }
    api_jira_search() { return 1; }
    api_jira_get_issue() { return 1; }
    api_jira_my_tickets() { return 1; }
    api_jira_ticket_details() { return 1; }
    api_bb_find_pr() { return 1; }
    api_bb_check_open_prs() { return 1; }
}
source "$WTX_ROOT/lib/worktree-jira.sh" 2>/dev/null || {
    jira_fetch_ticket_context() { echo ""; }
    check_duplicate_work() { echo ""; }
    check_existing_pr() { echo ""; }
    check_ac_completion() { echo ""; }
}
source "$WTX_ROOT/lib/worktree-warp.sh" 2>/dev/null || {
    warp_available() { return 1; }
    warp_remove_tab_config() { return 0; }
}

# Auto-detect project from a path — delegates to wtx_detect_project when the
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

# Forge-aware PR URL builder. Returns 1 on unknown forge type.
_wtx_build_pr_url() {
    local forge_type="$1" org="$2" repo="$3" branch="$4"
    case "$forge_type" in
        bitbucket|"") printf 'https://bitbucket.org/%s/%s/pull-requests/new?source=%s\n' "$org" "$repo" "$branch" ;;
        github)       printf 'https://github.com/%s/%s/compare/%s?expand=1\n' "$org" "$repo" "$branch" ;;
        gitlab)       printf 'https://gitlab.com/%s/%s/-/merge_requests/new?merge_request[source_branch]=%s\n' "$org" "$repo" "$branch" ;;
        *)            return 1 ;;
    esac
}

# Find the main repo from a worktree path
# F1: Fixed path arithmetic — .git file contains "gitdir: <path-to-.git/worktrees/name>"
# F15: Handle CRLF line endings in .git file
find_main_repo() {
    local wt_path="$1"
    local git_file="$wt_path/.git"

    if [[ -f "$git_file" ]]; then
        local gitdir
        # F15: Strip both "gitdir: " prefix and trailing \r
        gitdir="$(sed 's/^gitdir: //; s/\r$//' "$git_file" 2>/dev/null)"
        if [[ -n "$gitdir" ]]; then
            # Resolve relative paths
            if [[ ! "$gitdir" = /* ]]; then
                gitdir="$(cd "$wt_path" && cd "$(dirname "$gitdir")" 2>/dev/null && pwd)/$(basename "$gitdir")"
            fi
            # F1: gitdir points to .git/worktrees/<name>
            # Walk up: .git/worktrees/<name> -> .git/worktrees -> .git -> repo root
            local git_dir_parent
            git_dir_parent="$(cd "$gitdir/../.." 2>/dev/null && pwd)"
            if [[ -n "$git_dir_parent" ]] && [[ -d "$git_dir_parent" ]]; then
                # git_dir_parent is the .git directory, repo root is its parent
                local repo_root
                repo_root="$(dirname "$git_dir_parent")"
                if [[ -d "$repo_root" ]]; then
                    echo "$repo_root"
                    return 0
                fi
            fi
        fi
    fi
    return 1
}

# Verify ownership: confirm the worktree's .git file points back into the expected project.
# Prevents a same-named worktree in two projects from being confused.
# Defined at top-level so it is available to any code path that needs it.
_verify_builtin_worktree_owner() {
    local candidate="$1"
    local expected_proj_dir="$2"
    [[ -f "$candidate/.git" ]] || return 1
    local _gitdir
    _gitdir="$(sed 's/^gitdir: //; s/\r$//' "$candidate/.git" 2>/dev/null)"
    [[ -z "$_gitdir" ]] && return 1
    if [[ ! "$_gitdir" = /* ]]; then
        _gitdir="$(cd "$candidate" && cd "$(dirname "$_gitdir")" 2>/dev/null && pwd)/$(basename "$_gitdir")"
    fi
    local _git_root
    _git_root="$(cd "$_gitdir/../.." 2>/dev/null && pwd)"
    local _repo_root
    _repo_root="$(dirname "$_git_root" 2>/dev/null)"
    [[ "$_repo_root" == "$(cd "$expected_proj_dir" && pwd)" ]]
}

# Resolve worktree path
WORKTREE_PATH=""
MAIN_REPO=""
PR_URL_FOUND=""
PR_STATE_FOUND=""

if [[ -n "$ARG" ]]; then
    if [[ -d "$ARG" ]]; then
        WORKTREE_PATH="$(cd "$ARG" && pwd)"
    else
        DETECTED_PROJECT="$(detect_project "$(pwd)")"
        if [[ -n "$DETECTED_PROJECT" ]]; then
            PROJECT_NAME="$(basename "$DETECTED_PROJECT")"
            CANDIDATE="$(cd "$DETECTED_PROJECT/.." && pwd)/${PROJECT_NAME}-${ARG}"
            if [[ -d "$CANDIDATE" ]]; then
                WORKTREE_PATH="$CANDIDATE"
            fi
        fi
    fi

    # Try built-in worktree location (.claude/worktrees/<name>/)
    if [[ -z "$WORKTREE_PATH" ]]; then
        # Check workspace root itself first (meta-repo worktrees)
        _candidate="$WORKSPACE_ROOT/.claude/worktrees/$ARG"
        if [[ -d "$_candidate" ]] && _verify_builtin_worktree_owner "$_candidate" "$WORKSPACE_ROOT"; then
            WORKTREE_PATH="$(cd "$_candidate" && pwd)"
        else
            # Then check each known project
            projects_list=$(get_known_projects 2>/dev/null)
            while IFS= read -r _proj; do
                [[ -z "$_proj" ]] && continue
                _candidate="$WORKSPACE_ROOT/$_proj/.claude/worktrees/$ARG"
                if [[ -d "$_candidate" ]] && _verify_builtin_worktree_owner "$_candidate" "$WORKSPACE_ROOT/$_proj"; then
                    WORKTREE_PATH="$(cd "$_candidate" && pwd)"
                    break
                fi
            done <<< "$projects_list"
        fi
    fi

    if [[ -z "$WORKTREE_PATH" ]]; then
        echo "Error: Could not find worktree: $ARG" >&2
        exit 1
    fi
else
    # Walk up from pwd to find a worktree root (.git is a file in worktrees, a dir in main repos)
    _auto_dir="$(pwd)"
    WORKTREE_PATH=""
    while [[ "$_auto_dir" != "/" ]] && [[ -n "$_auto_dir" ]]; do
        if [[ -f "$_auto_dir/.git" ]]; then
            WORKTREE_PATH="$_auto_dir"
            break
        fi
        _auto_dir="$(dirname "$_auto_dir")"
    done
    if [[ -z "$WORKTREE_PATH" ]]; then
        echo "Error: Not inside a worktree. Provide a name or path as argument." >&2
        echo "Usage: $0 [name-or-path]" >&2
        exit 1
    fi
fi

# Verify it's actually a worktree
if [[ ! -f "$WORKTREE_PATH/.git" ]]; then
    echo "Error: $WORKTREE_PATH does not appear to be a worktree (.git is not a file)" >&2
    exit 1
fi

# Find main repo
MAIN_REPO="$(find_main_repo "$WORKTREE_PATH")"
if [[ -z "$MAIN_REPO" ]]; then
    echo "Error: Could not determine main repo for worktree" >&2
    exit 1
fi

# Get branch name
BRANCH="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)"
WORKTREE_NAME="$(basename "$WORKTREE_PATH")"

echo "Worktree: $WORKTREE_NAME"
echo "  Path:   $WORKTREE_PATH"
echo "  Branch: $BRANCH"
echo "  Main:   $MAIN_REPO"
echo ""

# --- Work Summary ---
CONTEXT_FILE="$WORKTREE_PATH/WORKTREE_CONTEXT.md"
WK_BASE_BRANCH=""
COMMIT_COUNT=0
if [[ -f "$CONTEXT_FILE" ]]; then
    WK_BASE_BRANCH=$(grep '\*\*Base Branch:\*\*' "$CONTEXT_FILE" 2>/dev/null | sed 's/.*\*\*Base Branch:\*\* *//' | tr -d '[:space:]')
fi
# Validate BASE_BRANCH
if [[ -n "$WK_BASE_BRANCH" ]] && ! git -C "$WORKTREE_PATH" rev-parse --verify "$WK_BASE_BRANCH" &>/dev/null; then
    if git -C "$WORKTREE_PATH" rev-parse --verify "origin/$WK_BASE_BRANCH" &>/dev/null; then
        WK_BASE_BRANCH="origin/$WK_BASE_BRANCH"
    else
        WK_BASE_BRANCH=""
    fi
fi

if [[ -n "$WK_BASE_BRANCH" ]]; then
    COMMITS=$(git -C "$WORKTREE_PATH" log --oneline "$WK_BASE_BRANCH..$BRANCH" 2>/dev/null)
    COMMIT_COUNT=0
    if [[ -n "$COMMITS" ]]; then
        COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
    fi

    DIFFSTAT=$(git -C "$WORKTREE_PATH" diff --stat "$WK_BASE_BRANCH..$BRANCH" 2>/dev/null)

    if [[ $COMMIT_COUNT -gt 0 ]]; then
        tui_style_box \
            "Work Summary" \
            "  Commits: $COMMIT_COUNT" \
            "  Base: $WK_BASE_BRANCH"
        echo ""
        if [[ -n "$DIFFSTAT" ]]; then
            echo "$DIFFSTAT"
            echo ""
        fi
    fi
else
    echo "Could not determine base branch for diffstat." >&2
    echo ""
fi

# --- AC Completion Check (advisory) ---
# NOTE: No `local` keyword — this is top-level script scope, not inside a function
if [[ $COMMIT_COUNT -gt 0 ]] && grep -q '^## Acceptance Criteria' "$CONTEXT_FILE" 2>/dev/null; then
    AC_RESULT=$(check_ac_completion "$WORKTREE_PATH" "$WK_BASE_BRANCH" "$BRANCH" 2>/dev/null)
    if [[ -n "$AC_RESULT" ]]; then
        if [[ "$AC_RESULT" == "NONE" ]]; then
            echo "✓ All acceptance criteria appear addressed"
            echo ""
        else
            echo "⚠  Potentially unaddressed acceptance criteria:"
            echo "$AC_RESULT" | sed 's/^/   /'
            echo ""
            echo "  (This is advisory — based on diff analysis, may have false positives)"
            echo ""
        fi
    fi
fi

# Check uncommitted changes
CHANGES="$(git -C "$WORKTREE_PATH" status --porcelain 2>/dev/null)"
if [[ -n "$CHANGES" ]]; then
    CHANGE_COUNT="$(echo "$CHANGES" | wc -l | tr -d ' ')"
    echo "⚠  Worktree has $CHANGE_COUNT uncommitted changes:"
    echo "$CHANGES" | head -10 | sed 's/^/   /'
    if [[ "$CHANGE_COUNT" -gt 10 ]]; then
        echo "   ... and $((CHANGE_COUNT - 10)) more"
    fi
    echo ""
fi

# --- Step A: Push prompt (uses git -C, cwd-immune) ---
if [[ -n "$BRANCH" ]] && [[ "$BRANCH" != "HEAD" ]]; then
    UNPUSHED=$(git -C "$WORKTREE_PATH" log --oneline "@{upstream}..HEAD" 2>/dev/null)
    PUSH_RC=$?
    # Non-zero exit (no upstream) or has unpushed commits
    if [[ $PUSH_RC -ne 0 ]] || [[ -n "$UNPUSHED" ]]; then
        if tui_confirm "Push branch '$BRANCH' before cleanup?"; then
            if ! git -C "$WORKTREE_PATH" push -u origin "$BRANCH"; then
                echo "Push failed." >&2
                if ! tui_confirm "Push failed. Continue with removal anyway? (unpushed work will be lost)"; then
                    echo "Aborted. Worktree preserved at: $WORKTREE_PATH" >&2
                    exit 0
                fi
            fi
        fi
    fi
fi

# --- PR Generation Offer ---
# Only if branch is pushed and claude is available
# NOTE: No `local` keyword — this is top-level script scope, not inside a function
if [[ -n "$BRANCH" ]] && [[ "$BRANCH" != "HEAD" ]] && \
   git -C "$WORKTREE_PATH" rev-parse --verify "origin/$BRANCH" &>/dev/null && \
   [[ ! -f "$WORKTREE_PATH/.pr-generated" ]]; then

    REPO_NAME_PR="$(basename "$MAIN_REPO")"
    EXISTING_PR=$(check_existing_pr "$BRANCH" "$REPO_NAME_PR" 2>/dev/null)

    if [[ -n "$EXISTING_PR" ]]; then
        # PR already exists — parse tab-delimited fields
        # Format: "PR_TITLE: <title>\tPR_URL: <url>\tPR_STATE: <state>"
        PR_TITLE_FOUND=""
        PR_URL_FOUND=""
        PR_STATE_FOUND=""
        # Take only the first line, strip trailing whitespace/newlines
        PR_LINE=$(echo "$EXISTING_PR" | head -1 | tr -d '\n\r')
        if [[ "$PR_LINE" == *"PR_TITLE:"* ]]; then
            # Split on tab (primary) or pipe (fallback for LLM variance)
            # NOTE: No `local` — top-level scope. IFS is scoped to the read command only.
            IFS_CHAR=$'\t'
            if [[ "$PR_LINE" != *$'\t'* ]]; then
                IFS_CHAR='|'
            fi
            IFS="$IFS_CHAR" read -r PR_F1 PR_F2 PR_F3 <<< "$PR_LINE"
            PR_TITLE_FOUND="${PR_F1#*PR_TITLE: }"
            PR_TITLE_FOUND="${PR_TITLE_FOUND%"${PR_TITLE_FOUND##*[! ]}"}"
            PR_URL_FOUND="${PR_F2#*PR_URL: }"
            PR_URL_FOUND="${PR_URL_FOUND#"${PR_URL_FOUND%%[! ]*}"}"  # trim leading spaces
            PR_URL_FOUND="${PR_URL_FOUND%"${PR_URL_FOUND##*[! ]}"}"  # trim trailing spaces
            PR_STATE_FOUND="${PR_F3#*PR_STATE: }"
            PR_STATE_FOUND="${PR_STATE_FOUND#"${PR_STATE_FOUND%%[! ]*}"}"
            PR_STATE_FOUND="${PR_STATE_FOUND%"${PR_STATE_FOUND##*[! ]}"}"
        fi
        echo ""
        tui_style_box \
            "PR exists ($PR_STATE_FOUND)" \
            "  $PR_TITLE_FOUND" \
            "  $PR_URL_FOUND"
        echo ""
        if [[ -n "$PR_URL_FOUND" ]] && [[ -z "${WORKTREE_DONE_QUIET:-}" ]] && tui_confirm "Open PR in browser?"; then
            open_url "$PR_URL_FOUND"
        fi
    elif has_claude; then
        echo ""
        if tui_confirm "Generate PR description? (opens Claude Code with /pr-write)"; then
            echo ""
            echo "Re-run worktree-done.sh after PR creation to complete cleanup."
            echo ""
            # Write marker to prevent re-offering PR generation on re-run
            touch "$WORKTREE_PATH/.pr-generated" 2>/dev/null
            REAL_GIT_DIR="$(git -C "$WORKTREE_PATH" rev-parse --absolute-git-dir 2>/dev/null)"
            if [[ -n "$REAL_GIT_DIR" ]]; then
                mkdir -p "$REAL_GIT_DIR/info" 2>/dev/null
                echo ".pr-generated" >> "$REAL_GIT_DIR/info/exclude" 2>/dev/null
            fi
            # cd to workspace root so Claude has access to .claude/, BMAD, hooks, MCP
            cd "$WORKSPACE_ROOT" || { echo "Error: Could not cd to $WORKSPACE_ROOT" >&2; exit 1; }
            if claude_supports_positional_prompt; then
                exec claude "/pr-write for branch $BRANCH based on $WK_BASE_BRANCH. Worktree at $WORKTREE_PATH."
            elif claude_supports_message_flag; then
                exec claude --message "/pr-write for branch $BRANCH based on $WK_BASE_BRANCH. Worktree at $WORKTREE_PATH."
            else
                echo "Run /pr-write to generate your PR description"
                exec claude
            fi
        fi
    fi
fi

# --- Step B: Escape worktree before removing it ---
cd "$MAIN_REPO" || { echo "Error: Cannot cd to main repo" >&2; exit 1; }

# --- Step C: Removal prompt ---
if [[ -n "$CHANGES" ]]; then
    RESPONSE=$(tui_input "Type 'yes' to confirm removal of $WORKTREE_NAME with $CHANGE_COUNT uncommitted changes:" "" "yes")
    if [[ "$RESPONSE" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
else
    if ! tui_confirm "Remove worktree $WORKTREE_NAME?"; then
        echo "Aborted."
        exit 0
    fi
fi

# Clean .build-cache first
if [[ -d "$WORKTREE_PATH/.build-cache" ]]; then
    rm -rf "$WORKTREE_PATH/.build-cache" 2>/dev/null
    echo "  Cleaned .build-cache/"
fi

# Remove worktree — robust against busy directories and partial removals.
# Finder re-creates .DS_Store mid-delete, which can abort git's recursive
# remove with ENOTEMPTY even after it has already unregistered the worktree.
# Clear that cruft first to avoid the race.
find "$WORKTREE_PATH" -name .DS_Store -type f -delete 2>/dev/null

if ! git -C "$MAIN_REPO" worktree remove "$WORKTREE_PATH" 2>/dev/null; then
    echo "  ⚠  Worktree has untracked or modified files." >&2
    if tui_confirm "Force removal? (untracked files will be lost)" false; then
        git -C "$MAIN_REPO" worktree remove --force "$WORKTREE_PATH" 2>/dev/null
    else
        echo "  Skipped removal. Run manually when ready:" >&2
        echo "    git -C $MAIN_REPO worktree remove --force $WORKTREE_PATH" >&2
        exit 1
    fi
fi

# `git worktree remove` can unregister the worktree yet still fail to delete
# the folder when a file is held open (IDE/terminal) or Finder rewrites
# .DS_Store. If git STILL lists it, that's a genuine failure. Otherwise the
# worktree is logically gone — finish the on-disk cleanup ourselves so the
# rest of the done-flow (registry update, branch deletion, PR offer) still runs
# instead of leaving everything half-done.
if git -C "$MAIN_REPO" worktree list --porcelain 2>/dev/null | grep -qF -- "worktree $WORKTREE_PATH"; then
    echo "  Removal failed — worktree still registered with git." >&2
    echo "    git -C $MAIN_REPO worktree remove --force $WORKTREE_PATH" >&2
    exit 1
fi
if [[ -e "$WORKTREE_PATH" ]]; then
    rm -rf "$WORKTREE_PATH" 2>/dev/null
    git -C "$MAIN_REPO" worktree prune 2>/dev/null
fi
if [[ -e "$WORKTREE_PATH" ]]; then
    # Folder survived even rm -rf — a process is holding files open. The
    # worktree is already unregistered, so warn but keep going.
    echo "  ⚠  Worktree unregistered, but its folder could not be deleted:" >&2
    echo "       $WORKTREE_PATH" >&2
    if command -v lsof >/dev/null 2>&1; then
        _holders="$(lsof +D "$WORKTREE_PATH" 2>/dev/null | awk 'NR>1{print $1" (pid "$2")"}' | sort -u | head -5)"
        if [[ -n "$_holders" ]]; then
            echo "     Still open by:" >&2
            echo "$_holders" | sed 's/^/       /' >&2
        fi
    fi
    echo "     Close it, then run: rm -rf $WORKTREE_PATH" >&2
    unset _holders
else
    echo "  ✓ Worktree removed"
fi

# Warp integration: remove tab config for this worktree
if warp_available; then
    warp_remove_tab_config "$WORKTREE_PATH"
fi

# Update registry — move to Recently Closed
# NOTE: No `local` keyword — this is top-level script scope, not inside a function
# PROJECT_NAME_FOR_REG must match what worktree-start.sh stored in `update_registry add`
PROJECT_NAME_FOR_REG="$(basename "$MAIN_REPO")"
pr_url_for_registry="${PR_URL_FOUND:-}"
result_for_registry="closed"
if [[ -n "${PR_STATE_FOUND:-}" ]]; then
    result_for_registry="$PR_STATE_FOUND"
fi
update_registry remove "$PROJECT_NAME_FOR_REG" "$BRANCH" "$pr_url_for_registry" "$result_for_registry" "$WORKTREE_PATH"

# --- Step D: PR offer FIRST, then branch deletion ---
# F8: Reordered — PR offer before branch deletion so user can create PR for pushed branch
REPO_NAME="$(basename "$MAIN_REPO")"
if [[ -n "$BRANCH" ]] && [[ "$BRANCH" != "HEAD" ]]; then
    FORGE_TYPE=""
    FORGE_ORG=""
    if command -v wtx_config_get >/dev/null 2>&1; then
        FORGE_TYPE="$(wtx_config_get "forge.type")"
        FORGE_ORG="$(wtx_config_get "forge.org")"
    fi
    PR_URL=""
    if [[ -z "$FORGE_ORG" ]]; then
        echo "Warning: forge.org not configured — skipping PR offer." >&2
    elif ! PR_URL="$(_wtx_build_pr_url "$FORGE_TYPE" "$FORGE_ORG" "$REPO_NAME" "$BRANCH")"; then
        echo "Warning: unknown forge.type '$FORGE_TYPE' — skipping PR offer." >&2
        PR_URL=""
    fi
    if [[ -n "$PR_URL" ]]; then
        echo ""
        if [[ -z "${WORKTREE_DONE_QUIET:-}" ]]; then
            if tui_confirm "Open PR creation in browser?"; then
                open_url "$PR_URL"
            else
                echo "  PR URL: $PR_URL"
            fi
        fi
    fi
fi

# Branch deletion
if [[ -n "$BRANCH" ]] && [[ "$BRANCH" != "HEAD" ]]; then
    # F24: Check if branch is checked out in another worktree before offering deletion
    if git -C "$MAIN_REPO" worktree list 2>/dev/null | grep -qF "[$BRANCH]"; then
        echo ""
        echo "  Branch '$BRANCH' is checked out in another worktree — skipping deletion." >&2
    else
        echo ""
        if tui_confirm "Delete local branch '$BRANCH'?"; then
            git -C "$MAIN_REPO" branch -D "$BRANCH" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo "  ✓ Branch deleted: $BRANCH"
            else
                echo "  Warning: Could not delete branch $BRANCH" >&2
            fi
        fi
    fi
fi
