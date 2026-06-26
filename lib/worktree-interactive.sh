#!/bin/bash
# Worktree Interactive Library
# Extracted interactive_start() for worktree-start.sh to keep main script under 300 lines.
#
# Usage: source "$SCRIPT_DIR/lib/worktree-interactive.sh"
#
# Prerequisites: worktree-tui.sh and worktree-jira.sh must be sourced first.
# Also requires: detect_project(), SCRIPT_DIR, WORKSPACE_ROOT, NO_EXEC to be defined.

# Logging stub — real implementation provided when worktree-tui.sh is sourced first.
type -t wtx_log >/dev/null 2>&1 || wtx_log() { :; }

# Validate an eval payload against a whitelist regex
# Returns "valid" or "invalid" on stdout
_validate_eval_payload() {
    local payload="$1"
    python3 -c "
import sys, re
line = sys.argv[1].strip()
if re.match(r\"^([A-Z_]+='[^']*';\\s*)+$\", line + ' '):
    print('valid')
else:
    print('invalid')
" "$payload" 2>/dev/null || echo "invalid"
}

# Interactive worktree creation flow
# Sets: NAME, BASE_BRANCH, PROJECT_DIR, PROJECT_NAME, BRANCH, TICKET_ID, MODE, WORKTREE_PATH
# Also sets (for caller): CACHED_TICKET_TITLE, CACHED_TICKET_STATUS, CACHED_TICKET_DESCRIPTION, CACHED_TICKET_ACS
interactive_start() {
    # --- Step 1: Project Selection ---
    local detected_dir
    detected_dir="$(detect_project "$(pwd)")"

    if [[ -n "$detected_dir" ]]; then
        PROJECT_DIR="$(cd "$detected_dir" && pwd)"
        PROJECT_NAME="$(basename "$PROJECT_DIR")"
        # If the detected dir has no remote it's a workspace root, not a project.
        # Fall through to project selection so the user picks the right subdir.
        if [[ -z "$(git -C "$PROJECT_DIR" remote 2>/dev/null)" ]]; then
            detected_dir=""
        elif ! tui_confirm "Working in $PROJECT_NAME?"; then
            # User wants a different project
            detected_dir=""
        fi
    fi

    if [[ -z "$detected_dir" ]]; then
        local projects_list
        projects_list=$(get_known_projects)
        local projects_arr=()
        while IFS= read -r p; do
            [[ -n "$p" ]] && projects_arr+=("$p")
        done <<< "$projects_list"

        if [[ ${#projects_arr[@]} -eq 0 ]]; then
            echo "Error: No projects configured." >&2
            exit 1
        fi

        PROJECT_NAME=$(tui_choose "Select project:" "${projects_arr[@]}")
        PROJECT_DIR="$WORKSPACE_ROOT/$PROJECT_NAME"
        if [[ ! -d "$PROJECT_DIR" ]]; then
            echo "Error: Project directory not found: $PROJECT_DIR" >&2
            exit 1
        fi
        PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    fi

    # --- Step 2: Ticket/Name Selection ---
    local jira_key
    jira_key=$(jira_project_for_repo "$PROJECT_NAME")

    NAME=""
    # F17: Use empty string instead of "N/A" sentinel — safer for future [[ -n ]] checks
    TICKET_ID=""
    MODE="named"

    wtx_log INFO "project=$PROJECT_NAME jira_key=${jira_key:-none} has_claude=$(has_claude && echo yes || echo no) has_gum=$(has_gum && echo yes || echo no)"

    if [[ -n "$jira_key" ]] && has_claude; then
        echo "Fetching your Jira tickets..." >&2
        local tickets
        tickets=$(jira_fetch_my_tickets "$jira_key")

        if [[ -n "$tickets" ]]; then
            wtx_log INFO "ticket list: $(echo "$tickets" | wc -l | tr -d ' ') items"
            # Build filter list with sentinel
            local filter_list
            filter_list=$(printf '%s\n%s' "$tickets" "$(printf '\xe2\x86\x92') Other ticket or custom name...")
            local selection
            selection=$(tui_filter "Select ticket or type a name:" "$filter_list")

            if [[ "$selection" == *"Other ticket or custom name..."* ]]; then
                NAME=$(tui_input "Enter ticket (e.g. PROJ-1234) or name:" "" "my-feature")
            elif [[ -n "$selection" ]]; then
                # Extract ticket key from "[★ ]KEY | Title | Status" — strip ★ prefix if present
                NAME=$(echo "$selection" | awk -F' *\\| *' '{gsub(/[[:space:]]/, "", $1); sub(/^★/, "", $1); gsub(/[[:space:]]/, "", $1); print $1}')
            fi
        fi
    fi

    # Fallback to manual input if no ticket selected
    if [[ -z "$NAME" ]]; then
        wtx_log WARN "no ticket selected — falling back to manual tui_input"
        NAME=$(tui_input "Enter ticket (e.g. PROJ-1234) or name:" "" "my-feature")
    fi

    wtx_log INFO "NAME after input: '${NAME:-<empty>}'"
    if [[ -z "$NAME" ]]; then
        wtx_log WARN "NAME empty after tui_input — user aborted or pressed Enter with no input"
        echo "Error: Name is required." >&2
        exit 1
    fi

    # Validate NAME
    if [[ ! "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        echo "Error: Name must contain only alphanumeric characters, hyphens, and underscores." >&2
        exit 1
    fi

    # Detect mode
    if [[ "$NAME" =~ ^[A-Z]+-[0-9]+$ ]]; then
        MODE="ticket"
        TICKET_ID="$NAME"
    fi
    wtx_log INFO "MODE=$MODE TICKET_ID=${TICKET_ID:-none}"

    # --- Parallel: Duplicate Detection + Ticket Analysis (ticket mode only) ---
    local SUGGEST_PREFIX="" SUGGEST_BASE="" SUGGEST_BRANCH_NAME="" SUGGEST_SUMMARY=""
    # These MUST NOT use `local` — they must be visible to worktree-start.sh after interactive_start() returns
    CACHED_TICKET_TITLE=""
    CACHED_TICKET_STATUS=""
    CACHED_TICKET_DESCRIPTION=""
    CACHED_TICKET_ACS=""

    if [[ "$MODE" == "ticket" ]]; then
        if has_claude; then
            echo "Analyzing ticket..." >&2
            local dup_tmpfile
            dup_tmpfile=$(mktemp)
            local analyze_tmpfile
            analyze_tmpfile=$(mktemp)
            local dup_pid=""
            local analyze_pid=""

            # Trap to clean up background processes and temp files on interrupt
            trap 'kill "$dup_pid" "$analyze_pid" 2>/dev/null; wait "$dup_pid" "$analyze_pid" 2>/dev/null; rm -f "$dup_tmpfile" "$analyze_tmpfile"; exit 130' INT TERM

            ( check_duplicate_work "$TICKET_ID" "$PROJECT_DIR" > "$dup_tmpfile" 2>/dev/null ) &
            dup_pid=$!

            ( jira_analyze_ticket "$TICKET_ID" "$PROJECT_NAME" > "$analyze_tmpfile" 2>/dev/null ) &
            analyze_pid=$!

            wait "$dup_pid" "$analyze_pid" 2>/dev/null

            # Clear parallel-execution trap
            trap - INT TERM

            # Read results from temp files
            local duplicates
            duplicates=$(cat "$dup_tmpfile" 2>/dev/null)
            local suggestions
            suggestions=$(cat "$analyze_tmpfile" 2>/dev/null)
            rm -f "$dup_tmpfile" "$analyze_tmpfile"

            # Validate and apply suggestions
            if [[ -n "$suggestions" ]]; then
                local validation
                validation=$(_validate_eval_payload "$suggestions")
                if [[ "$validation" == "valid" ]]; then
                    eval "$suggestions"
                    # Store ticket context for worktree-start.sh (no `local` — must be visible to caller)
                    CACHED_TICKET_TITLE="$TICKET_TITLE"
                    CACHED_TICKET_STATUS="$TICKET_STATUS"
                    CACHED_TICKET_DESCRIPTION="$TICKET_DESCRIPTION"
                    CACHED_TICKET_ACS="$TICKET_ACS"
                else
                    echo "  Warning: ticket analysis returned unparseable output, continuing without cached data" >&2
                fi
            fi

            if [[ -n "$SUGGEST_SUMMARY" ]]; then
                echo "  $SUGGEST_SUMMARY" >&2
            fi
        else
            # No claude — still check for local worktree duplicates (pure git, no AI)
            local duplicates
            duplicates=$(check_duplicate_work "$TICKET_ID" "$PROJECT_DIR" 2>/dev/null)
        fi

        # Process duplicate warnings
        if [[ -n "$duplicates" ]]; then
            echo "" >&2
            echo "⚠  Existing work found for $TICKET_ID:" >&2
            echo "$duplicates" | sed 's/^/   /' >&2
            echo "" >&2
            if ! tui_confirm "Continue creating a new worktree?"; then
                echo "Aborted." >&2
                exit 0
            fi
        fi
    fi

    # --- Step 3: Base Branch Selection ---
    local remote_branches
    remote_branches=$(git -C "$PROJECT_DIR" branch -r --list 'origin/*' 2>/dev/null | sed 's|^ *origin/||' | grep -v 'HEAD')

    if [[ -n "$remote_branches" ]]; then
        # Pin config default + develop/main/master at top, AI suggestion first if valid
        local config_base=""
        if command -v wtx_config_get >/dev/null 2>&1; then
            config_base="$(wtx_config_get "defaults.base_branch" "develop")"
        else
            config_base="develop"
        fi
        local config_pinned=""
        local pinned=""
        local rest=""
        local ai_pinned=""
        while IFS= read -r b; do
            if [[ -n "$SUGGEST_BASE" ]] && [[ "$b" == "$SUGGEST_BASE" ]]; then
                ai_pinned="${b}"$'\n'
            elif [[ -n "$config_base" && "$b" == "$config_base" ]]; then
                config_pinned="${b}"$'\n'
            elif [[ "$b" == "develop" || "$b" == "main" || "$b" == "master" ]]; then
                pinned="${pinned}${b}"$'\n'
            else
                rest="${rest}${b}"$'\n'
            fi
        done <<< "$remote_branches"
        local branch_list="${ai_pinned}${config_pinned}${pinned}${rest}"
        # Remove trailing newline
        branch_list=$(echo "$branch_list" | sed '/^$/d')

        local ai_hint=""
        if [[ -n "$SUGGEST_BASE" ]]; then
            ai_hint=" (AI suggests: $SUGGEST_BASE)"
        fi

        local valid=false
        while [[ "$valid" != "true" ]]; do
            BASE_BRANCH=$(tui_filter "Select base branch${ai_hint}:" "$branch_list")
            # F6: Guard against empty selection (gum --strict=false can return empty with exit 0)
            if [[ -z "$BASE_BRANCH" ]]; then
                echo "Error: No branch selected." >&2
                exit 1
            fi
            # F7: Sanitize — strip control chars and validate as safe branch ref
            BASE_BRANCH=$(echo "$BASE_BRANCH" | tr -d '\n\r')
            if git -C "$PROJECT_DIR" rev-parse --verify "origin/$BASE_BRANCH" &>/dev/null; then
                valid=true
            else
                echo "Error: Branch '$BASE_BRANCH' does not exist on remote. Try again." >&2
            fi
        done
    else
        if command -v wtx_config_get >/dev/null 2>&1; then
            BASE_BRANCH="$(wtx_config_get "defaults.base_branch" "develop")"
        else
            BASE_BRANCH="develop"
        fi
        echo "No remote branches found. Using base branch: $BASE_BRANCH" >&2
    fi

    # --- Step 4: Branch Prefix Selection ---
    local prefixes
    prefixes=$(git -C "$PROJECT_DIR" branch -r --list 'origin/*' 2>/dev/null \
        | sed 's|^ *origin/||' \
        | grep '/' \
        | sed 's|/.*||' \
        | grep -v 'HEAD' \
        | sort | uniq -c | sort -rn \
        | awk '$1 >= 2 {print $2}')

    # Fallback if filtered list is empty
    if [[ -z "$prefixes" ]]; then
        prefixes=$(git -C "$PROJECT_DIR" branch -r --list 'origin/*' 2>/dev/null \
            | sed 's|^ *origin/||' \
            | grep '/' \
            | sed 's|/.*||' \
            | grep -v 'HEAD' \
            | sort -u)
    fi

    # Final fallback
    if [[ -z "$prefixes" ]]; then
        prefixes="feature"
    fi

    # If AI suggested a prefix, move it to the top
    if [[ -n "$SUGGEST_PREFIX" ]]; then
        local ai_prefix_line=""
        local other_prefixes=""
        while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            if [[ "$p" == "$SUGGEST_PREFIX" ]]; then
                ai_prefix_line="$p"
            else
                other_prefixes="${other_prefixes}${p}"$'\n'
            fi
        done <<< "$prefixes"
        if [[ -n "$ai_prefix_line" ]]; then
            prefixes="${ai_prefix_line}"$'\n'"${other_prefixes}"
        else
            # AI prefix not in repo — add it at top
            prefixes="${SUGGEST_PREFIX}"$'\n'"${prefixes}"
        fi
    fi

    local prefix_list
    prefix_list=$(printf '%s\n%s' "$prefixes" "$(printf '\xe2\x9c\x8f') Custom prefix...")

    local ai_prefix_hint=""
    if [[ -n "$SUGGEST_PREFIX" ]]; then
        ai_prefix_hint=" (AI suggests: $SUGGEST_PREFIX)"
    fi

    local selected_prefix
    selected_prefix=$(tui_filter "Select branch prefix${ai_prefix_hint}:" "$prefix_list")

    if [[ "$selected_prefix" == *"Custom prefix..."* ]]; then
        selected_prefix=$(tui_input "Enter prefix:" "" "spike")
    fi

    # Validate prefix
    selected_prefix=$(echo "$selected_prefix" | tr -d '/ \n\r')
    if [[ ! "$selected_prefix" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: Invalid prefix '$selected_prefix'. Using 'feature'." >&2
        selected_prefix="feature"
    fi

    # --- Step 5: Branch Name Composition ---
    local name_slug="$NAME"
    if [[ "$MODE" == "ticket" ]] && [[ -n "$SUGGEST_BRANCH_NAME" ]]; then
        name_slug="${NAME}-${SUGGEST_BRANCH_NAME}"
    fi
    local composed="${selected_prefix}/${name_slug}"
    BRANCH=$(tui_input "Branch name:" "$composed")

    if [[ -z "$BRANCH" ]]; then
        BRANCH="$composed"
    fi

    # --- Step 6: Confirmation Summary ---
    WORKTREE_PATH="$(cd "$PROJECT_DIR/.." && pwd)/${PROJECT_NAME}-${NAME}"

    # F17: Display "—" for ticket in summary when not in ticket mode
    local display_ticket="${TICKET_ID:-—}"

    tui_style_box \
        "Project:  $PROJECT_NAME" \
        "Ticket:   $display_ticket" \
        "Branch:   $BRANCH" \
        "Base:     $BASE_BRANCH" \
        "Path:     $WORKTREE_PATH"

    if ! tui_confirm "Create worktree?"; then
        echo "Aborted." >&2
        exit 0
    fi
}
