#!/bin/bash
# Worktree Start Script
# Creates a new git worktree with Android-specific setup for multi-project workspace.
#
# Usage: ./scripts/worktree/worktree-start.sh [--no-exec] [--] <name> [base-branch] [project-dir]
#        ./scripts/worktree/worktree-start.sh                    # Interactive mode (requires terminal)
#
# Modes:
#   Interactive: ./scripts/worktree/worktree-start.sh             → TUI-guided flow
#   Ticket:      ./scripts/worktree/worktree-start.sh PROJ-1234    → feature/PROJ-1234
#   Named:       ./scripts/worktree/worktree-start.sh perf-test   → feature/perf-test
#   Custom:      ./scripts/worktree/worktree-start.sh PROJ-1234 main my-project → feature/PROJ-1234 based on main
#
# Flags:
#   --no-exec    Don't exec claude at the end (print command instead)
#
# ERROR HANDLING: No set -e. Validates inputs early, prints clear errors, exits 1 on failure.

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
source "$WTX_ROOT/lib/worktree-launch.sh" 2>/dev/null || {
    smart_launch_menu() {
        local wt_path="$1" no_exec="${6:-false}"
        local prompt="Read $wt_path/WORKTREE_CONTEXT.md and briefly confirm what worktree you are in. Do NOT start any work, exploration, or investigation. Wait for my next message."
        if [[ "$no_exec" == "true" ]]; then
            echo "  claude \"$prompt\""
        else
            cd "$WORKSPACE_ROOT" || { echo "Error: cannot cd to $WORKSPACE_ROOT" >&2; return 1; }
            if claude_supports_positional_prompt; then
                exec claude "$prompt"
            else
                echo "Prompt (paste manually): $prompt" >&2
                exec claude
            fi
        fi
    }
}
source "$WTX_ROOT/lib/worktree-jira.sh" 2>/dev/null || {
    jira_fetch_my_tickets() { echo ""; }
    jira_get_ticket_summary() { echo ""; }
    jira_suggest_branch() { echo "SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY='';"; }
    jira_analyze_ticket() { echo "SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY=''; TICKET_TITLE=''; TICKET_STATUS=''; TICKET_DESCRIPTION=''; TICKET_ACS='';"; }
    jira_project_for_repo() { echo ""; }
    jira_fetch_ticket_context() { echo ""; }
    check_duplicate_work() { echo ""; }
}
source "$WTX_ROOT/lib/worktree-warp.sh" 2>/dev/null || {
    warp_available() { return 1; }
    warp_emit_tab_config() { return 0; }
    warp_open_tab() { return 0; }
    warp_remove_tab_config() { return 0; }
}

# Parse flags
NO_EXEC=false
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --no-exec) NO_EXEC=true; shift ;;
        --)        shift; break ;;
        *)         break ;;
    esac
done

NAME="${1:-}"
BASE_BRANCH="${2:-}"
PROJECT_DIR="${3:-}"

# Auto-detect project from pwd — delegates to wtx_detect_project when the
# config loader is reachable, otherwise falls back to `.git`-only walk.
if [[ -f "$WTX_ROOT/lib/wtx-config.sh" ]]; then
    # shellcheck source=../lib/wtx-config.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-config.sh" 2>/dev/null || true
fi

# Apply config-driven default for BASE_BRANCH when not supplied on the command line.
if [[ -z "$BASE_BRANCH" ]]; then
    if command -v wtx_config_get >/dev/null 2>&1; then
        BASE_BRANCH="$(wtx_config_get "defaults.base_branch" "develop")"
    else
        BASE_BRANCH="develop"
    fi
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

# Pre-initialise cached ticket variables (set by interactive_start if available)
CACHED_TICKET_TITLE=""
CACHED_TICKET_STATUS=""
CACHED_TICKET_DESCRIPTION=""
CACHED_TICKET_ACS=""

# --- INTERACTIVE MODE ---
if [[ -z "$NAME" ]]; then
    # Try to load interactive library
    source "$WTX_ROOT/lib/worktree-interactive.sh" 2>/dev/null
    if type interactive_start &>/dev/null; then
        interactive_start
        # interactive_start sets: NAME, BASE_BRANCH, PROJECT_DIR, PROJECT_NAME, BRANCH, TICKET_ID, MODE, WORKTREE_PATH
    else
        # F20: Clear error message when interactive library is unavailable
        echo "Usage: $0 [--no-exec] [--] <name> [base-branch] [project-dir]" >&2
        echo "" >&2
        echo "Examples:" >&2
        echo "  $0 PROJ-1234             # Ticket mode, based on develop" >&2
        echo "  $0 perf-test main        # Named mode, based on main" >&2
        echo "  $0 PROJ-1234 develop my-project # Explicit project directory" >&2
        echo "" >&2
        echo "Interactive mode unavailable ($WTX_ROOT/lib/worktree-interactive.sh not found)." >&2
        if command -v gum &>/dev/null; then
            echo "gum is installed but the wtx lib is missing. Set WTX_ROOT to the wtx install directory." >&2
        else
            echo "Provide arguments above, or install gum for interactive mode: brew install gum" >&2
        fi
        exit 1
    fi
else
    # --- NON-INTERACTIVE MODE (existing behavior preserved) ---

    # Validate NAME: only alphanumeric, hyphens, underscores
    if [[ ! "$NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Error: Name must contain only alphanumeric characters, hyphens, and underscores." >&2
        exit 1
    fi

    if [[ -z "$PROJECT_DIR" ]]; then
        PROJECT_DIR="$(detect_project "$(pwd)")"
        if [[ -z "$PROJECT_DIR" ]]; then
            echo "Error: Could not detect project. Run from inside a project directory or pass it as third argument." >&2
            exit 1
        fi
    else
        # If relative, resolve from workspace root
        if [[ ! "$PROJECT_DIR" = /* ]]; then
            PROJECT_DIR="$WORKSPACE_ROOT/$PROJECT_DIR"
        fi
        if [[ ! -d "$PROJECT_DIR" ]]; then
            echo "Error: Project directory does not exist: $PROJECT_DIR" >&2
            exit 1
        fi
    fi

    # Resolve to absolute path
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    PROJECT_NAME="$(basename "$PROJECT_DIR")"

    # Detect mode: ticket vs named
    # F17: Use empty string for TICKET_ID instead of "N/A"
    if [[ "$NAME" =~ ^[A-Z]+-[0-9]+$ ]]; then
        MODE="ticket"
        TICKET_ID="$NAME"
        BRANCH="feature/$NAME"
    else
        MODE="named"
        TICKET_ID=""
        BRANCH="feature/$NAME"
    fi

    # Duplicate detection (ticket mode, non-interactive)
    # Only prompt if terminal is available — skip silently in CI/headless
    if [[ "$MODE" == "ticket" ]] && [[ -t 0 || -e /dev/tty ]]; then
        DUPLICATES=$(check_duplicate_work "$TICKET_ID" "$PROJECT_DIR" 2>/dev/null)
        if [[ -n "$DUPLICATES" ]]; then
            echo "" >&2
            echo "⚠  Existing work found for $TICKET_ID:" >&2
            echo "$DUPLICATES" | sed 's/^/   /' >&2
            echo "" >&2
            if ! tui_confirm "Continue creating a new worktree?"; then
                echo "Aborted." >&2
                exit 0
            fi
        fi
    fi

    # Worktree path: sibling to project directory
    WORKTREE_PATH="$(cd "$PROJECT_DIR/.." && pwd)/${PROJECT_NAME}-${NAME}"
fi

# Pre-flight: check worktree doesn't already exist
if [[ -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree path already exists: $WORKTREE_PATH" >&2
    echo "" >&2
    echo "Existing worktrees:" >&2
    git -C "$PROJECT_DIR" worktree list 2>/dev/null >&2
    exit 1
fi

# Pre-flight: check if branch already exists locally
if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    echo "Warning: Branch '$BRANCH' already exists locally." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Use the existing branch" >&2
    echo "  2. Delete it first: git -C $PROJECT_DIR branch -D $BRANCH" >&2
    echo "  3. Choose a different name" >&2
    echo "" >&2
    if tui_confirm "Use existing branch '$BRANCH'?"; then
        echo "Creating worktree with existing branch..."
        git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" "$BRANCH"
        if [[ $? -ne 0 ]]; then
            echo "Error: git worktree add failed" >&2
            exit 1
        fi
    else
        echo "Aborted." >&2
        exit 1
    fi
else
    # Create worktree with new branch
    echo "Creating worktree..."
    git -C "$PROJECT_DIR" worktree add "$WORKTREE_PATH" -b "$BRANCH" "$BASE_BRANCH"
    if [[ $? -ne 0 ]]; then
        echo "Error: git worktree add failed. Is '$BASE_BRANCH' a valid branch?" >&2
        exit 1
    fi
fi

# Run configured setup hook (opt-in via `worktree.setup_hook` in wtx.toml).
SETUP_HOOK=""
if command -v wtx_config_get >/dev/null 2>&1; then
    SETUP_HOOK="$(wtx_config_get "worktree.setup_hook")"
fi
if [[ -n "$SETUP_HOOK" ]]; then
    # Resolve relative to the wtx repo root (one dir above scripts/).
    if [[ "$SETUP_HOOK" != /* ]]; then
        SETUP_HOOK="$WTX_ROOT/$SETUP_HOOK"
    fi
    if [[ -f "$SETUP_HOOK" ]]; then
        bash "$SETUP_HOOK" "$WORKTREE_PATH" "$PROJECT_DIR"
    else
        echo "Warning: setup_hook not found at $SETUP_HOOK" >&2
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
            bash "$GRAPHIFY_HOOK" "$WORKTREE_PATH" "$PROJECT_DIR"
        fi
        ;;
esac

# Generate WORKTREE_CONTEXT.md
# F17: Write empty string as "N/A" in context file for display purposes
if ! cat > "$WORKTREE_PATH/WORKTREE_CONTEXT.md" <<EOF
# Worktree Context
- **Project:** $PROJECT_NAME
- **Branch:** $BRANCH
- **Base Branch:** $BASE_BRANCH
- **Created:** $(date +%Y-%m-%d)
- **Ticket:** ${TICKET_ID:-N/A}
- **Worktree Path:** $WORKTREE_PATH
- **Main Repo:** $PROJECT_DIR
EOF
then
    echo "Warning: Could not write WORKTREE_CONTEXT.md" >&2
fi

# Append ticket details and acceptance criteria
# NOTE: No `local` keyword — this is top-level script scope, not inside a function
if [[ -n "$TICKET_ID" ]]; then
    if [[ -n "${CACHED_TICKET_TITLE:-}" ]]; then
        # Use cached data from jira_analyze_ticket (interactive mode)
        {
            echo ""
            echo "## Ticket Details"
            echo "**Title:** $CACHED_TICKET_TITLE"
            echo "**Status:** $CACHED_TICKET_STATUS"
            echo "**Description:** $CACHED_TICKET_DESCRIPTION"
            if [[ -n "${CACHED_TICKET_ACS:-}" ]]; then
                echo ""
                echo "## Acceptance Criteria"
                echo "$CACHED_TICKET_ACS"
            fi
        } >> "$WORKTREE_PATH/WORKTREE_CONTEXT.md"
    else
        # Fallback: non-interactive mode, no cached data
        TICKET_CONTEXT=$(jira_fetch_ticket_context "$TICKET_ID" 2>/dev/null)
        if [[ -n "$TICKET_CONTEXT" ]]; then
            printf '\n%s\n' "$TICKET_CONTEXT" >> "$WORKTREE_PATH/WORKTREE_CONTEXT.md"
        fi
    fi
fi

# Update worktree registry
registry_name="${TICKET_ID:-$NAME}"
update_registry add "$PROJECT_NAME" "$BRANCH" "$BASE_BRANCH" "$WORKTREE_PATH" "$registry_name"

# Warp integration: emit tab config + auto-open tab at worktree path
if warp_available; then
    if warp_emit_tab_config "$WORKTREE_PATH" "$PROJECT_NAME" "$BRANCH" "$TICKET_ID"; then
        wt_basename="$(basename "$WORKTREE_PATH")"
        if warp_open_tab "$WORKTREE_PATH"; then
            tui_style_box \
                "Warp tab opened" \
                "2-pane layout available via Warp + menu:" \
                "  'wt: $wt_basename'"
        else
            tui_style_box \
                "Warp tab config ready" \
                "Open via Warp + menu:" \
                "  'wt: $wt_basename'"
        fi
        echo ""
    fi
fi

# Print completion message
echo ""
echo "✓ Worktree created: $WORKTREE_PATH"
echo "  Branch: $BRANCH (based on $BASE_BRANCH)"
echo "  Project: $PROJECT_NAME"
echo ""

# Show ticket summary if available
if [[ "$MODE" == "ticket" ]]; then
    if [[ -n "${CACHED_TICKET_TITLE:-}" ]]; then
        echo "Ticket info:"
        echo "  TITLE: $CACHED_TICKET_TITLE"
        echo "  STATUS: $CACHED_TICKET_STATUS"
        echo ""
    else
        ticket_summary=$(jira_get_ticket_summary "$TICKET_ID" 2>/dev/null)
        if [[ -n "$ticket_summary" ]]; then
            echo "Ticket info:"
            echo "$ticket_summary" | sed 's/^/  /'
            echo ""
        fi
    fi
fi

# Offer to open Claude Code
# --no-exec: skip interactive confirm, just print the suggested command
if [[ "$NO_EXEC" == "true" ]]; then
    smart_launch_menu "$WORKTREE_PATH" "$TICKET_ID" "$BRANCH" "$PROJECT_NAME" "$WORKSPACE_ROOT" "true"
elif tui_confirm "Open Claude Code in worktree?" "yes"; then
    smart_launch_menu "$WORKTREE_PATH" "$TICKET_ID" "$BRANCH" "$PROJECT_NAME" "$WORKSPACE_ROOT" "false"
else
    echo "Next steps:"
    echo "  claude \"Read $WORKTREE_PATH/WORKTREE_CONTEXT.md and briefly confirm what worktree you are in. Do NOT start any work, exploration, or investigation. Wait for my next message.\""
fi
