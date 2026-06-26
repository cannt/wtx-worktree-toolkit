#!/bin/bash
# Worktree Status Script
# Shows a dashboard of all worktrees across projects with interactive management.
#
# Usage: ./scripts/worktree/worktree-status.sh [project-dir]
#
# If no argument, scans all known projects and shows interactive menu.
# With argument, shows table only (non-interactive).
#
# ERROR HANDLING: No set -e. Skips projects that error out.

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

# Collected worktree data arrays
ALL_WT_PATHS=()
ALL_WT_BRANCHES=()
ALL_WT_PROJECTS=()
ALL_WT_CHANGES=()
ALL_WT_STALE=()
ALL_WT_BEHIND=()

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

# Compute stale and divergence status for a worktree
# Usage: compute_stale_divergence <path> <branch>
# Sets: _stale and _behind variables (caller must read them)
_stale="0"
_behind="0"
compute_stale_divergence() {
    local wt_path="$1"
    local wt_branch="$2"
    _stale="0"
    _behind="0"
    if [[ ! -d "$wt_path" ]]; then
        return
    fi
    # Stale detection (7-day threshold = 604800 seconds)
    local last_commit_ts="0"
    last_commit_ts="$(git -C "$wt_path" log -1 --format="%ct" 2>/dev/null || echo 0)"
    local now_ts
    now_ts="$(date +%s)"
    if [[ "$last_commit_ts" -gt 0 ]] && [[ $((now_ts - last_commit_ts)) -gt 604800 ]]; then
        _stale="1"
    fi
    # Divergence detection
    local wt_base=""
    local wt_context="$wt_path/WORKTREE_CONTEXT.md"
    if [[ -f "$wt_context" ]]; then
        wt_base=$(grep '\*\*Base Branch:\*\*' "$wt_context" 2>/dev/null | sed 's/.*\*\*Base Branch:\*\* *//' | tr -d '[:space:]')
    fi
    if [[ -n "$wt_base" ]] && [[ -n "$wt_branch" ]]; then
        _behind=$(git -C "$wt_path" rev-list --count "$wt_branch..origin/$wt_base" 2>/dev/null || echo 0)
    fi
}

# Collect worktree data for a project (appends to arrays)
collect_worktrees_for() {
    local project_dir="$1"
    local project_name="$(basename "$project_dir")"

    if [[ ! -d "$project_dir/.git" ]] && [[ ! -f "$project_dir/.git" ]]; then
        return
    fi

    local worktree_data
    worktree_data="$(git -C "$project_dir" worktree list --porcelain 2>/dev/null)"
    if [[ -z "$worktree_data" ]]; then
        return
    fi

    local main_path
    main_path="$(cd "$project_dir" && pwd)"

    local current_path=""
    local current_branch=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^worktree\ (.+) ]]; then
            if [[ -n "$current_path" ]] && [[ "$current_path" != "$main_path" ]]; then
                local changes="0"
                if [[ -d "$current_path" ]]; then
                    changes="$(git -C "$current_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
                fi
                compute_stale_divergence "$current_path" "$current_branch"
                ALL_WT_PATHS+=("$current_path")
                ALL_WT_BRANCHES+=("$current_branch")
                ALL_WT_PROJECTS+=("$project_name")
                ALL_WT_CHANGES+=("$changes")
                ALL_WT_STALE+=("$_stale")
                ALL_WT_BEHIND+=("$_behind")
            fi
            current_path="${BASH_REMATCH[1]}"
            current_branch=""
        elif [[ "$line" =~ ^branch\ refs/heads/(.+) ]]; then
            current_branch="${BASH_REMATCH[1]}"
        elif [[ "$line" == "detached" ]]; then
            # F10: Handle detached HEAD worktrees
            current_branch="(detached HEAD)"
        fi
    done <<< "$worktree_data"

    # Last entry
    if [[ -n "$current_path" ]] && [[ "$current_path" != "$main_path" ]]; then
        local changes="0"
        if [[ -d "$current_path" ]]; then
            changes="$(git -C "$current_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
        fi
        compute_stale_divergence "$current_path" "$current_branch"
        ALL_WT_PATHS+=("$current_path")
        ALL_WT_BRANCHES+=("$current_branch")
        ALL_WT_PROJECTS+=("$project_name")
        ALL_WT_CHANGES+=("$changes")
        ALL_WT_STALE+=("$_stale")
        ALL_WT_BEHIND+=("$_behind")
    fi
}

# Collect worktrees, resetting arrays first
collect_all_worktrees() {
    ALL_WT_PATHS=()
    ALL_WT_BRANCHES=()
    ALL_WT_PROJECTS=()
    ALL_WT_CHANGES=()
    ALL_WT_STALE=()
    ALL_WT_BEHIND=()

    if [[ -n "$1" ]]; then
        collect_worktrees_for "$1"
    else
        # Always scan the workspace meta-repo for built-in worktrees created there
        if [[ -d "$WORKSPACE_ROOT/.git" ]] || [[ -f "$WORKSPACE_ROOT/.git" ]]; then
            collect_worktrees_for "$WORKSPACE_ROOT"
        fi
        # Scan all known projects (not just the detected one) so the dashboard is complete
        local projects_list
        projects_list=$(get_known_projects)
        while IFS= read -r proj; do
            [[ -z "$proj" ]] && continue
            local proj_path="$WORKSPACE_ROOT/$proj"
            if [[ -d "$proj_path" ]]; then
                collect_worktrees_for "$proj_path"
            fi
        done <<< "$projects_list"
    fi
}

# Display collected worktrees as a table
display_worktrees() {
    if [[ ${#ALL_WT_PATHS[@]} -eq 0 ]]; then
        echo "No worktrees found."
        echo ""
        return
    fi

    # Group by project for display
    local current_project=""
    for i in "${!ALL_WT_PATHS[@]}"; do
        local project="${ALL_WT_PROJECTS[$i]}"
        if [[ "$project" != "$current_project" ]]; then
            if [[ -n "$current_project" ]]; then
                printf "└──────────────────────────┴──────────┴──────────┴────────────────────────────────────┘\n"
                echo ""
            fi
            current_project="$project"
            echo "Worktrees for $project:"
            printf "┌──────────────────────────┬──────────┬──────────┬────────────────────────────────────┐\n"
            printf "│ %-24s │ %-8s │ %-8s │ %-34s │\n" "Branch" "Ticket" "Changes" "Last Commit"
            printf "├──────────────────────────┼──────────┼──────────┼────────────────────────────────────┤\n"
        fi

        local wt_path="${ALL_WT_PATHS[$i]}"
        local branch="${ALL_WT_BRANCHES[$i]}"
        local changes="${ALL_WT_CHANGES[$i]}"

        local ticket="—"
        if [[ "$branch" =~ ([A-Z]+-[0-9]+) ]]; then
            ticket="${BASH_REMATCH[1]}"
        fi

        # Built-in worktree indicator
        local builtin_mark=""
        if [[ "$wt_path" == *"/.claude/worktrees/"* ]]; then
            builtin_mark=" [B]"
        fi

        local last_commit="(unavailable)"
        if [[ -d "$wt_path" ]]; then
            last_commit="$(git -C "$wt_path" log -1 --format="%s (%cr)" 2>/dev/null)"
        fi

        # Stale and type indicators
        local suffix_mark="${builtin_mark}"
        local max_branch=24
        if [[ "${ALL_WT_STALE[$i]}" == "1" ]]; then
            suffix_mark="${suffix_mark} (stale)"
        fi
        if [[ -n "$suffix_mark" ]]; then
            max_branch=$((24 - ${#suffix_mark}))
            [[ $max_branch -lt 8 ]] && max_branch=8
        fi
        # F16: Add ellipsis when truncating branch and commit
        local display_branch="${branch:0:$max_branch}"
        [[ ${#branch} -gt $max_branch ]] && display_branch="${display_branch:0:$((max_branch - 1))}…"
        display_branch="${display_branch}${suffix_mark}"
        local display_commit="${last_commit:0:34}"
        [[ ${#last_commit} -gt 34 ]] && display_commit="${last_commit:0:33}…"
        # Divergence indicator
        local changes_display="$changes"
        local behind_val="${ALL_WT_BEHIND[$i]}"
        if [[ "$behind_val" -gt 20 ]]; then
            changes_display="${changes} ↓${behind_val}"
        fi
        printf "│ %-24s │ %-8s │ %8s │ %-34s │\n" "$display_branch" "$ticket" "$changes_display" "$display_commit"
    done

    if [[ -n "$current_project" ]]; then
        printf "└──────────────────────────┴──────────┴──────────┴────────────────────────────────────┘\n"
        echo ""
    fi
}

# Fetch remote refs (call once, not per-loop-iteration)
# Usage: fetch_all_remotes [project_dir]
fetch_all_remotes() {
    if [[ -n "${1:-}" ]]; then
        git -C "$1" fetch origin --quiet 2>/dev/null || true
        return
    fi
    local projects_list
    projects_list=$(get_known_projects)
    while IFS= read -r proj; do
        [[ -z "$proj" ]] && continue
        local proj_path="$WORKSPACE_ROOT/$proj"
        if [[ -d "$proj_path/.git" ]] || [[ -f "$proj_path/.git" ]]; then
            git -C "$proj_path" fetch origin --quiet 2>/dev/null || true
        fi
    done <<< "$projects_list"
}

# Interactive management menu
interactive_menu() {
    # Fetch once before the menu loop to get fresh remote refs for divergence
    fetch_all_remotes
    update_registry refresh
    while true; do
        # Re-collect fresh data
        collect_all_worktrees

        if [[ ${#ALL_WT_PATHS[@]} -eq 0 ]]; then
            local choices=("→ Create new worktree" "Exit")
        else
            local choices=()
            for i in "${!ALL_WT_PATHS[@]}"; do
                local project="${ALL_WT_PROJECTS[$i]}"
                local branch="${ALL_WT_BRANCHES[$i]}"
                local changes="${ALL_WT_CHANGES[$i]}"
                choices+=("$project: $branch ($changes changes)")
            done
            # Count stale worktrees
            local stale_count=0
            for s in "${ALL_WT_STALE[@]}"; do
                [[ "$s" == "1" ]] && stale_count=$((stale_count + 1))
            done
            if [[ $stale_count -gt 0 ]]; then
                choices+=("⚠ Clean up $stale_count stale worktree(s)")
            fi
            choices+=("→ Create new worktree" "Exit")
        fi

        local selection
        selection=$(tui_choose "Select a worktree to manage:" "${choices[@]}")

        if [[ "$selection" == "Exit" ]]; then
            exit 0
        elif [[ "$selection" == "→ Create new worktree" ]]; then
            bash "$SCRIPT_DIR/worktree-start.sh" --no-exec
            continue
        elif [[ "$selection" == "⚠ Clean up"*"stale worktree"* ]]; then
            for i in "${!ALL_WT_PATHS[@]}"; do
                if [[ "${ALL_WT_STALE[$i]}" == "1" ]]; then
                    echo ""
                    echo "Stale: ${ALL_WT_BRANCHES[$i]} (${ALL_WT_PATHS[$i]})"
                    WORKTREE_DONE_QUIET=1 bash "$SCRIPT_DIR/worktree-done.sh" "${ALL_WT_PATHS[$i]}"
                fi
            done
            continue
        fi

        # Find which worktree was selected
        local selected_idx=-1
        for i in "${!ALL_WT_PATHS[@]}"; do
            local project="${ALL_WT_PROJECTS[$i]}"
            local branch="${ALL_WT_BRANCHES[$i]}"
            local changes="${ALL_WT_CHANGES[$i]}"
            if [[ "$selection" == "$project: $branch ($changes changes)" ]]; then
                selected_idx=$i
                break
            fi
        done

        if [[ $selected_idx -lt 0 ]]; then
            echo "Error: Could not find selected worktree." >&2
            continue
        fi

        local wt_path="${ALL_WT_PATHS[$selected_idx]}"
        local wt_branch="${ALL_WT_BRANCHES[$selected_idx]}"

        # Action submenu
        local action
        # F22: Label clarifies that Open Claude Code exits the dashboard
        local behind_val="${ALL_WT_BEHIND[$selected_idx]}"
        local action_choices=("Open Claude Code here (exits dashboard)" "Remove this worktree")
        if [[ "$behind_val" -gt 0 ]]; then
            action_choices+=("Rebase on base branch (${behind_val} behind)")
        fi
        action_choices+=("Back")
        action=$(tui_choose "Action for $wt_branch:" "${action_choices[@]}")

        case "$action" in
            "Open Claude Code here (exits dashboard)")
                if [[ ! -d "$wt_path" ]]; then
                    echo "Worktree no longer exists: $wt_path" >&2
                    continue
                fi
                if ! has_claude; then
                    echo "Error: claude CLI not found in PATH" >&2
                    continue
                fi
                # Extract ticket ID from branch name for smart launch
                local launch_ticket=""
                if [[ "$wt_branch" =~ ([A-Z]+-[0-9]+) ]]; then
                    launch_ticket="${BASH_REMATCH[1]}"
                fi
                smart_launch_menu "$wt_path" "$launch_ticket" "$wt_branch" "${ALL_WT_PROJECTS[$selected_idx]}" "$WORKSPACE_ROOT" "false"
                ;;
            "Remove this worktree")
                WORKTREE_DONE_QUIET=1 bash "$SCRIPT_DIR/worktree-done.sh" "$wt_path"
                continue
                ;;
            *"Rebase on base branch"*)
                local wt_base=""
                local wt_context="${ALL_WT_PATHS[$selected_idx]}/WORKTREE_CONTEXT.md"
                if [[ -f "$wt_context" ]]; then
                    wt_base=$(grep '\*\*Base Branch:\*\*' "$wt_context" 2>/dev/null | sed 's/.*\*\*Base Branch:\*\* *//' | tr -d '[:space:]')
                fi
                if [[ -n "$wt_base" ]] && tui_confirm "Rebase $wt_branch on origin/$wt_base?"; then
                    git -C "$wt_path" rebase "origin/$wt_base"
                    if [[ $? -eq 0 ]]; then
                        echo "✓ Rebase successful"
                    else
                        echo "" >&2
                        echo "⚠  Rebase has conflicts. The worktree is now in mid-rebase state." >&2
                        echo "  Dashboard data for this worktree may be inaccurate until resolved." >&2
                        echo "" >&2
                        echo "  To resolve:" >&2
                        echo "    cd $wt_path" >&2
                        echo "    # Fix conflicts, then: git rebase --continue" >&2
                        echo "    # Or abort: git rebase --abort" >&2
                    fi
                fi
                continue
                ;;
            "Back")
                continue
                ;;
        esac
    done
}

# --- Main ---
if [[ -n "$1" ]]; then
    # Single project specified — non-interactive
    if [[ -d "$1" ]]; then
        PROJECT_DIR="$(cd "$1" && pwd)"
    else
        PROJECT_DIR="$WORKSPACE_ROOT/$1"
    fi

    if [[ -d "$PROJECT_DIR" ]]; then
        fetch_all_remotes "$PROJECT_DIR"
        collect_all_worktrees "$PROJECT_DIR"
        display_worktrees
    else
        echo "Error: Project directory not found: $1" >&2
        exit 1
    fi
else
    # No args — collect, display, then interactive menu
    collect_all_worktrees
    display_worktrees

    if [[ -t 0 ]]; then
        interactive_menu
    fi
fi
