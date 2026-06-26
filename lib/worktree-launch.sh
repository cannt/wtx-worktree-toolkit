#!/usr/bin/env bash
# worktree-launch.sh — Smart launch menu for Claude Code worktrees
# Analyzes BMAD artifacts and presents an intelligent launch menu.
# Sourced by worktree-start.sh and worktree-status.sh.

# Result of slash command verification (Task 1).
# true = "/bmad-*" works as positional prompt (Claude CLI processes it as command)
# false = "/bmad-*" is sent as plain text (must suggest command instead)
SLASH_CMD_WORKS=true

# ─────────────────────────────────────────────────────────────────────────────
# analyze_worktree <ticket_id> <branch> <workspace_root>
#
# Echoes a suggestion string: "suggestion" or "suggestion|artifact_path"
# Suggestions: quick-dev, quick-spec, dev-story, create-story, code-review, just-open
# ─────────────────────────────────────────────────────────────────────────────
analyze_worktree() {
    local ticket_id="$1" branch="$2" workspace_root="$3"

    # Step 1 — BMAD gate
    if [[ ! -d "$workspace_root/_bmad" ]]; then
        echo "just-open"
        return
    fi

    local impl_dir="$workspace_root/_bmad-output/implementation-artifacts"
    if [[ ! -d "$impl_dir" ]]; then
        echo "quick-spec"
        return
    fi

    # Step 2 — Tech spec scan (highest priority)
    # Derive search keywords from branch
    local branch_slug=""
    if [[ -n "$ticket_id" ]]; then
        branch_slug="${branch#*"$ticket_id"}"
        branch_slug="${branch_slug#-}"
    elif [[ "$branch" == */* ]]; then
        branch_slug="${branch#*/}"
    fi

    for spec in "$impl_dir"/tech-spec-*.md; do
        [[ -f "$spec" ]] || continue

        # Match: ticket ID in content OR branch slug in filename
        local matched=false
        if [[ -n "$ticket_id" ]] && grep -qiF "$ticket_id" "$spec" 2>/dev/null; then
            matched=true
        elif [[ -n "$branch_slug" ]] && [[ "$(basename "$spec")" == *"$branch_slug"* ]]; then
            matched=true
        fi
        $matched || continue

        # Extract status from YAML frontmatter
        local status
        status=$(awk '
            /^---$/ { if (in_fm) exit; in_fm=1; next }
            in_fm && /^[Ss]tatus:/ {
                val=$0; sub(/^[^:]+:[ \t]*/, "", val)
                gsub(/["\047]/, "", val)
                sub(/[ \t]*#.*$/, "", val)
                gsub(/^[ \t]+|[ \t]+$/, "", val)
                print tolower(val); exit
            }
        ' "$spec")

        case "$status" in
            ready-for-dev|in-progress)
                echo "quick-dev|$spec"; return ;;
            draft)
                echo "quick-spec|$spec"; return ;;
        esac
        # Other statuses (implementation-complete, completed, review) → not actionable
    done

    # Step 3 — Sprint status scan (only if ticket ID is non-empty)
    local sprint_file="$impl_dir/sprint-status.yaml"
    if [[ -z "$ticket_id" ]] || [[ ! -f "$sprint_file" ]]; then
        echo "quick-spec"
        return
    fi

    # Quick check: does ticket appear anywhere?
    grep -qF "$ticket_id" "$sprint_file" 2>/dev/null || { echo "quick-spec"; return; }

    # Parse the section containing the ticket ID
    local best_suggestion
    best_suggestion=$(awk -v ticket="$ticket_id" '
        BEGIN { state="seeking" }

        state == "seeking" {
            if (index($0, ticket)) state = "header"
            next
        }
        state == "header" {
            if (/^[[:space:]]*#/) next
            if (/^[[:space:]]*$/) next
            state = "in_section"
        }
        state == "in_section" && /^[[:space:]]*#[[:space:]]*═══/ { exit }
        state == "in_section" && /^[[:space:]]*#/ { next }

        state == "in_section" && /^[[:space:]]+[a-zA-Z0-9_-]+:/ {
            key=$0; sub(/^[[:space:]]+/, "", key); sub(/:.*$/, "", key)
            val=$0; sub(/^[^:]+:[[:space:]]*/, "", val); gsub(/[[:space:]]+$/, "", val)

            if (key ~ /retrospective/) next

            if (key ~ /epic/) {
                epic_count++
                if (val == "done") done_count++
                next
            }

            if (val == "review")              { has_review=1 }
            else if (val == "ready-for-dev")  { has_ready=1 }
            else if (val == "in-progress")    { has_inprog=1 }
            else if (val == "backlog")        { has_backlog=1 }
        }
        END {
            if (epic_count > 0 && done_count == epic_count) { print "none"; exit }
            if (has_review)                print "code-review"
            else if (has_ready || has_inprog) print "dev-story"
            else if (has_backlog)           print "create-story"
            else                            print "none"
        }
    ' "$sprint_file")

    if [[ "$best_suggestion" != "none" ]] && [[ -n "$best_suggestion" ]]; then
        echo "$best_suggestion"
        return
    fi

    # Step 4 — Default
    echo "quick-spec"
}

# ─────────────────────────────────────────────────────────────────────────────
# build_launch_prompt <selection_key> <worktree_path> [artifact_path]
#
# Echoes the prompt string to pass to `exec claude`.
# ─────────────────────────────────────────────────────────────────────────────
build_launch_prompt() {
    local selection="$1" wt_path="$2" artifact="${3:-}"
    local ctx="Read $wt_path/WORKTREE_CONTEXT.md"
    local guard="Do NOT start any work, exploration, or investigation. Wait for my next message for my approval to continue."
    local guard_simple="Do NOT start any work, exploration, or investigation. Wait for my next message."

    case "$selection" in
        custom)
            echo "$artifact"
            return ;;
        just-open)
            echo "$ctx and briefly confirm what worktree you are in. $guard_simple"
            return ;;
    esac

    # BMAD commands
    local cmd=""
    case "$selection" in
        quick-dev)     cmd="/bmad-bmm-quick-dev" ;;
        dev-story)     cmd="/bmad-bmm-dev-story" ;;
        create-story)  cmd="/bmad-bmm-create-story" ;;
        code-review)   cmd="/bmad-bmm-code-review" ;;
        quick-spec)    cmd="/bmad-bmm-quick-spec" ;;
    esac

    local artifact_ref=""
    if [[ -n "$artifact" ]] && [[ "$selection" != "custom" ]]; then
        artifact_ref=" to implement $artifact"
    fi

    if [[ "${SLASH_CMD_WORKS:-true}" == "true" ]]; then
        echo "$cmd $ctx${artifact_ref}. $guard"
    else
        echo "$ctx and briefly confirm what worktree you are in.${artifact_ref:+ Artifact found:${artifact_ref}.} When ready, run: $cmd. $guard"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# smart_launch_menu <wt_path> <ticket_id> <branch> <project_name> <workspace_root> <no_exec>
#
# Main orchestrator: analyze → menu → prompt → exec
# ─────────────────────────────────────────────────────────────────────────────
smart_launch_menu() {
    local wt_path="$1" ticket_id="$2" branch="$3" project_name="$4" workspace_root="$5" no_exec="${6:-false}"

    # Analyze worktree state
    local raw_suggestion suggestion artifact_path
    raw_suggestion=$(analyze_worktree "$ticket_id" "$branch" "$workspace_root")
    IFS='|' read -r suggestion artifact_path <<< "$raw_suggestion"

    # Build annotation for the suggested option
    local annotation=""
    if [[ -n "$artifact_path" ]]; then
        local spec_status
        spec_status=$(awk '/^---$/{ if(f) exit; f=1; next } f && /^[Ss]tatus:/{
            v=$0; sub(/^[^:]+:[ \t]*/, "", v); gsub(/["'"'"']/, "", v);
            sub(/[ \t]*#.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v);
            print tolower(v); exit }' "$artifact_path")
        annotation=" — $(basename "$artifact_path") ($spec_status)"
    elif [[ "$suggestion" =~ ^(code-review|dev-story|create-story)$ ]]; then
        annotation=" — from sprint"
    fi

    # Check if BMAD is installed
    local has_bmad=false
    [[ -d "$workspace_root/_bmad" ]] && has_bmad=true

    # Build menu options
    local options=()
    local suggested_display=""

    if $has_bmad; then
        # Build options array with annotation on the suggested item
        # Uses case instead of declare -A for bash 3.2 compatibility (macOS default)
        local bmad_keys="quick-dev dev-story create-story code-review quick-spec"
        for key in $bmad_keys; do
            local display=""
            case "$key" in
                quick-dev)     display="Quick Dev" ;;
                dev-story)     display="Dev Story" ;;
                create-story)  display="Create Story" ;;
                code-review)   display="Code Review" ;;
                quick-spec)    display="Quick Spec" ;;
            esac
            if [[ "$key" == "$suggestion" ]]; then
                display="${display}${annotation}"
                suggested_display="$display"
            fi
            options+=("$display")
        done
    fi

    options+=("Custom prompt")
    options+=("Just open")

    # Default suggested_display for non-BMAD or just-open suggestion
    if [[ -z "$suggested_display" ]]; then
        suggested_display="Just open"
    fi

    # --no-exec: print the suggested command, don't show menu
    if [[ "$no_exec" == "true" ]]; then
        local prompt
        prompt=$(build_launch_prompt "$suggestion" "$wt_path" "$artifact_path")
        echo "  claude \"$prompt\""
        return
    fi

    # Show menu
    local choice
    choice=$(tui_choose --selected "$suggested_display" "How would you like to start?" "${options[@]}")
    [[ -z "$choice" ]] && return 1

    # Map selection back to key
    local selected_key=""
    case "$choice" in
        Quick\ Dev*)     selected_key="quick-dev" ;;
        Dev\ Story*)     selected_key="dev-story" ;;
        Create\ Story*)  selected_key="create-story" ;;
        Code\ Review*)   selected_key="code-review" ;;
        Quick\ Spec*)    selected_key="quick-spec" ;;
        "Custom prompt")
            local user_input
            user_input=$(tui_input "Enter your prompt")
            if [[ -z "$user_input" ]]; then
                echo "No prompt entered. Aborting." >&2
                return 1
            fi
            local prompt
            prompt=$(build_launch_prompt "custom" "$wt_path" "$user_input")
            cd "$workspace_root" || { echo "Error: cannot cd to $workspace_root" >&2; return 1; }
            if claude_supports_positional_prompt; then
                exec claude "$prompt"
            else
                echo "Prompt (paste manually): $prompt" >&2
                exec claude
            fi
            ;;
        "Just open")
            selected_key="just-open"
            artifact_path=""
            ;;
        *)
            echo "Unknown selection: $choice" >&2
            return 1
            ;;
    esac

    # Build and execute prompt
    local prompt
    prompt=$(build_launch_prompt "$selected_key" "$wt_path" "$artifact_path")

    cd "$workspace_root" || { echo "Error: cannot cd to $workspace_root" >&2; return 1; }
    if claude_supports_positional_prompt; then
        exec claude "$prompt"
    else
        echo "Prompt (paste manually): $prompt" >&2
        exec claude
    fi
}
