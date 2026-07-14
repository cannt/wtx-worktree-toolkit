#!/bin/bash
# Worktree TUI Library
# Shared gum wrappers with bash fallbacks for worktree scripts.
#
# Usage: source "$SCRIPT_DIR/lib/worktree-tui.sh"
#
# Prerequisites: WORKSPACE_ROOT must be set by the caller before sourcing.
#
# All tui_* functions work with or without gum installed.
# When gum is absent, basic read/select fallbacks are used.
#
# Environment variables:
#   WORKTREE_JIRA_TIMEOUT — seconds to wait for Jira query via claude -p (default: 20)
#     Example: WORKTREE_JIRA_TIMEOUT=30 ./scripts/worktree/worktree-start.sh

# Cache for tool availability checks
_HAS_GUM=""
_HAS_CLAUDE=""
_GUM_HINT_SHOWN=""

has_gum() {
    if [[ -z "$_HAS_GUM" ]]; then
        if command -v gum >/dev/null 2>&1; then
            _HAS_GUM=1
        else
            _HAS_GUM=0
        fi
    fi
    [[ "$_HAS_GUM" -eq 1 ]]
}

has_claude() {
    if [[ -z "$_HAS_CLAUDE" ]]; then
        if command -v claude >/dev/null 2>&1; then
            _HAS_CLAUDE=1
        else
            _HAS_CLAUDE=0
        fi
    fi
    [[ "$_HAS_CLAUDE" -eq 1 ]]
}

# Show one-time hint about gum
_maybe_show_gum_hint() {
    if ! has_gum && [[ -z "$_GUM_HINT_SHOWN" ]]; then
        _GUM_HINT_SHOWN=1
        echo "Tip: Install gum for a better experience: brew install gum" >&2
    fi
}

# --- Debug logging ---
# Log files: $WTX_LOG_DIR/wtx-YYYY-MM-DD.log  (default: ~/.local/share/wtx/logs/)
# Retention: 7 days — older files deleted on first wtx_log call per session.
# View today's log: cat "$(wtx_log_path)"
_WTX_LOG_DIR="${WTX_LOG_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wtx/logs}"
_WTX_LOG_FILE=""

_wtx_log_init() {
    [[ -n "$_WTX_LOG_FILE" ]] && return 0
    mkdir -p "$_WTX_LOG_DIR" 2>/dev/null || return 1
    _WTX_LOG_FILE="$_WTX_LOG_DIR/wtx-$(date +%Y-%m-%d).log"
    find "$_WTX_LOG_DIR" -name 'wtx-*.log' -mtime +7 -delete 2>/dev/null || true
}

# Usage: wtx_log LEVEL "message"   (LEVEL: INFO DEBUG WARN ERROR)
# Safe to call anywhere — never fails or prints to the terminal.
wtx_log() {
    local level="${1:-INFO}"
    local msg="$2"
    local caller="${FUNCNAME[1]:-main}"
    _wtx_log_init 2>/dev/null || return 0
    [[ -z "$_WTX_LOG_FILE" ]] && return 0
    printf '[%s] [%s] [%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$caller" "$msg" \
        >> "$_WTX_LOG_FILE" 2>/dev/null || true
}

# Print the path to today's log file (creates it if needed).
wtx_log_path() {
    _wtx_log_init 2>/dev/null
    echo "${_WTX_LOG_FILE:-$_WTX_LOG_DIR/wtx-$(date +%Y-%m-%d).log}"
}

# Load wtx config loader (same directory); safe if missing.
_wtx_tui_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_wtx_tui_self_dir/wtx-config.sh" 2>/dev/null || true

# Get known projects from wtx.toml (projects.list) or legacy .worktree-projects.
# Returns empty when nothing is configured — no hardcoded project names.
get_known_projects() {
    if command -v wtx_config_get_list >/dev/null 2>&1; then
        wtx_config_get_list "projects.list"
    fi
}

# Abort check — handles gum's abort exit codes.
# Ctrl+C always exits 130. Esc is component-specific: gum input/write/choose/filter
# quit with exit 1 (printing their own "not submitted"/"nothing selected" message),
# distinct from gum confirm, where exit 1 legitimately means "No" and must not be
# treated as an abort. Pass soft_rc=1 for input/choose/filter call sites only.
# Usage: tui_abort_check $? ["context message"] [soft_rc]
tui_abort_check() {
    local rc="$1"
    local context="${2:-}"
    local soft_rc="${3:-}"
    if [[ "$rc" -eq 130 ]] || { [[ -n "$soft_rc" ]] && [[ "$rc" -eq "$soft_rc" ]]; }; then
        if [[ -n "$context" ]]; then
            echo "Aborted: $context" >&2
        else
            echo "Aborted." >&2
        fi
        exit 0
    fi
}

# Choose from a list of options
# Usage: tui_choose [--selected "value"] "prompt" "option1" "option2" ...
tui_choose() {
    local selected_opt=""
    if [[ "${1:-}" == "--selected" ]]; then
        selected_opt="$2"; shift 2
    fi
    local prompt="$1"; shift
    _maybe_show_gum_hint
    if has_gum; then
        local args=(--header "$prompt")
        if [[ -n "$selected_opt" ]]; then
            args+=(--selected "$selected_opt")
        fi
        gum choose "${args[@]}" "$@"
        local _rc=$?; tui_abort_check $_rc "" 1; return $_rc
    else
        # F9: Detect EOF (Ctrl+D) to avoid infinite spin
        # select returns 0 even on EOF if no body executed, so use a flag
        # Annotate the suggested option with (suggested) suffix
        local display_opts=()
        for opt in "$@"; do
            if [[ -n "$selected_opt" ]] && [[ "$opt" == "$selected_opt" ]]; then
                display_opts+=("$opt (suggested)")
            else
                display_opts+=("$opt")
            fi
        done
        PS3="$prompt "
        while true; do
            local _eof_detected=true
            select chosen in "${display_opts[@]}"; do
                _eof_detected=false
                if [[ -n "$chosen" ]]; then
                    # Strip (suggested) suffix before returning
                    echo "${chosen% (suggested)}"
                    return 0
                fi
                echo "Invalid selection. Try again." >&2
                break
            done < /dev/tty
            if "$_eof_detected"; then
                echo "Aborted." >&2
                exit 0
            fi
        done
    fi
}

# Yes/No confirmation
# Usage: tui_confirm "prompt?" [default_yes]
tui_confirm() {
    local prompt="$1"
    local default_yes="${2:-}"
    _maybe_show_gum_hint
    if has_gum; then
        if [[ -n "$default_yes" ]]; then
            gum confirm "$prompt"
        else
            gum confirm "$prompt" --default=false
        fi
        local _rc=$?; tui_abort_check $_rc; return $_rc
    else
        local suffix="[y/N]"
        if [[ -n "$default_yes" ]]; then
            suffix="[Y/n]"
        fi
        local response
        read -r -p "$prompt $suffix " response < /dev/tty
        # F23: Tighten validation — only y/Y/n/N/empty are meaningful
        if [[ -n "$default_yes" ]]; then
            # Default yes: empty or y/Y = yes, n/N = no, anything else = re-ask
            [[ -z "$response" || "$response" =~ ^[Yy]$ ]]
        else
            # Default no: only y/Y = yes
            [[ "$response" =~ ^[Yy]$ ]]
        fi
    fi
}

# Text input with optional default
# Usage: tui_input "prompt" ["default_value"] ["placeholder"]
tui_input() {
    local prompt="$1"
    local default_value="${2:-}"
    local placeholder="${3:-}"
    _maybe_show_gum_hint
    if has_gum; then
        local args=(--prompt "$prompt ")
        if [[ -n "$default_value" ]]; then
            args+=(--value "$default_value")
        fi
        if [[ -n "$placeholder" ]]; then
            args+=(--placeholder "$placeholder")
        fi
        gum input "${args[@]}"
        local _rc=$?; tui_abort_check $_rc "" 1; return $_rc
    else
        local val
        if [[ -n "$default_value" ]]; then
            read -r -p "$prompt [$default_value]: " val < /dev/tty
        else
            read -r -p "$prompt: " val < /dev/tty
        fi
        echo "${val:-$default_value}"
    fi
}

# Filterable list selection
# Usage: tui_filter "prompt" "item1\nitem2\nitem3"
tui_filter() {
    local prompt="$1"
    local items_string="$2"
    _maybe_show_gum_hint
    if has_gum; then
        echo "$items_string" | gum filter --placeholder "$prompt" --strict=false --no-fuzzy-sort
        local _rc=$?; tui_abort_check $_rc "" 1; return $_rc
    else
        # F14: bash 3.2 compatible, glob-safe, no eval
        local _saved_noglob=false
        [[ -o noglob ]] && _saved_noglob=true
        set -f
        local IFS=$'\n'
        local items_arr=($items_string)
        unset IFS
        if ! "$_saved_noglob"; then set +f; fi
        # Add free-text option
        items_arr+=("$(printf '\xe2\x9c\x8f') Type custom value...")
        # F9: Detect EOF (Ctrl+D) — use flag since select returns 0 on EOF
        PS3="$prompt "
        while true; do
            local _eof_detected=true
            select opt in "${items_arr[@]}"; do
                _eof_detected=false
                if [[ "$opt" == *"Type custom value..."* ]]; then
                    local custom_val
                    read -r -p "Enter value: " custom_val < /dev/tty
                    echo "$custom_val"
                    return 0
                elif [[ -n "$opt" ]]; then
                    echo "$opt"
                    return 0
                fi
                echo "Invalid selection." >&2
                break
            done < /dev/tty
            if "$_eof_detected"; then
                echo "Aborted." >&2
                exit 0
            fi
        done
    fi
}

# Spinner wrapper — runs command with visual feedback
# Usage: RESULT=$(tui_spin "message" command arg1 arg2)
tui_spin() {
    local message="$1"; shift
    if has_gum; then
        local tmpfile
        tmpfile=$(mktemp)
        local errfile
        errfile=$(mktemp)
        local rcfile
        rcfile=$(mktemp)
        # F2/F12: Capture stderr separately, save exit code before sync flush
        ( "$@" > "$tmpfile" 2>"$errfile"; _ec=$?; sync; echo $_ec > "$rcfile" ) &
        local cmd_pid=$!
        sleep 0.1
        # Show spinner that waits for the background PID
        gum spin --title "$message" -- bash -c "while kill -0 $cmd_pid 2>/dev/null; do sleep 0.2; done"
        wait "$cmd_pid" 2>/dev/null
        # F2: Wait for rcfile to be written (brief spin if needed)
        local _wait=0
        while [[ ! -s "$rcfile" ]] && [[ $_wait -lt 10 ]]; do
            sleep 0.1
            _wait=$((_wait + 1))
        done
        cat "$tmpfile"
        local rc
        rc=$(cat "$rcfile" 2>/dev/null || echo 1)
        # F12: Replay stderr on failure for diagnostics
        if [[ "$rc" -ne 0 ]] && [[ -s "$errfile" ]]; then
            cat "$errfile" >&2
        fi
        rm -f "$tmpfile" "$errfile" "$rcfile"
        return "$rc"
    else
        echo "$message" >&2
        "$@"
    fi
}

# Styled box around text
# Usage: tui_style_box "line1" "line2" "line3"
tui_style_box() {
    [[ $# -eq 0 ]] && return 0
    _maybe_show_gum_hint
    if has_gum; then
        printf '%s\n' "$@" | gum style --border rounded --padding "1 2"
    else
        local max_w=0
        for line in "$@"; do
            [[ ${#line} -gt $max_w ]] && max_w=${#line}
        done
        max_w=$((max_w + 2))
        # F18: bash-native border generation (no seq dependency)
        local border=""
        local _i=0
        while [[ $_i -lt $max_w ]]; do
            border="${border}─"
            _i=$((_i + 1))
        done
        echo "┌${border}┐"
        for line in "$@"; do
            printf "│ %-$((max_w - 2))s │\n" "$line"
        done
        echo "└${border}┘"
    fi
}

# Open URL in browser
open_url() {
    local url="$1"
    if command -v open >/dev/null 2>&1; then
        open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url"
    else
        echo "  URL: $url"
    fi
}

# Check if claude CLI supports positional prompt argument
# Returns 0 if supported, 1 if not
# Caches result for the session to avoid repeated checks
_CLAUDE_POSITIONAL_PROMPT=""
claude_supports_positional_prompt() {
    if ! has_claude; then
        return 1
    fi
    if [[ -z "$_CLAUDE_POSITIONAL_PROMPT" ]]; then
        # Check if the Usage: line mentions [prompt] or <prompt>
        local usage_line
        usage_line=$(claude --help 2>&1 | grep -i '^[[:space:]]*usage:' | head -1)
        if echo "$usage_line" | grep -qiE '\[prompt\]|<prompt>' 2>/dev/null; then
            _CLAUDE_POSITIONAL_PROMPT="yes"
        else
            _CLAUDE_POSITIONAL_PROMPT="no"
        fi
    fi
    [[ "$_CLAUDE_POSITIONAL_PROMPT" == "yes" ]]
}

# Check if claude CLI supports --message flag
# Returns 0 if supported, 1 if not. Cached per session.
_CLAUDE_HAS_MESSAGE_FLAG=""
claude_supports_message_flag() {
    if ! has_claude; then
        return 1
    fi
    if [[ -z "$_CLAUDE_HAS_MESSAGE_FLAG" ]]; then
        if claude --help 2>&1 | grep -q -- '--message'; then
            _CLAUDE_HAS_MESSAGE_FLAG="yes"
        else
            _CLAUDE_HAS_MESSAGE_FLAG="no"
        fi
    fi
    [[ "$_CLAUDE_HAS_MESSAGE_FLAG" == "yes" ]]
}

# Worktree registry — tracks active and recently closed worktrees for cross-session discovery.
# Atomic writes via temp file + mv. NOT safe against concurrent mutations (last writer wins),
# which is acceptable — concurrent worktree operations are rare.
# Registry path is config-driven via worktree.registry_path (default: .claude/worktree-registry.md).
#
# Subcommands:
#   update_registry add <project> <branch> <base> <path> <ticket_or_name> [type]
#   update_registry remove <project> <branch> [pr_url] [result]
#   update_registry refresh

# Resolve the registry file path from config, with default fallback.
# Requires WORKSPACE_ROOT to be set by the caller.
_registry_path() {
    local rel_path
    if command -v wtx_config_get >/dev/null 2>&1; then
        rel_path=$(wtx_config_get "worktree.registry_path" ".claude/worktree-registry.md")
    else
        rel_path=".claude/worktree-registry.md"
    fi
    case "$rel_path" in
        ""|/*|..|../*|*/..|*/../*)
            rel_path=".claude/worktree-registry.md"
            ;;
    esac
    echo "$WORKSPACE_ROOT/$rel_path"
}

update_registry() {
    [[ -z "$WORKSPACE_ROOT" ]] && return 0
    local subcommand="$1"; shift

    local registry_file
    registry_file=$(_registry_path)
    local registry_dir
    registry_dir=$(dirname "$registry_file")

    # Ensure directory exists
    [[ -d "$registry_dir" ]] || mkdir -p "$registry_dir" 2>/dev/null || return 0

    # Create initial registry if not exists
    if [[ ! -f "$registry_file" ]]; then
        local init_tmp
        init_tmp=$(mktemp)
        cat > "$init_tmp" <<'INITEOF'
# Worktree Registry
<!-- Machine-generated file. Contains absolute paths — do not commit to version control. -->
Last updated: —

## Active Worktrees

## Recently Closed
INITEOF
        mv "$init_tmp" "$registry_file"
    fi

    case "$subcommand" in
        add)
            _registry_add "$registry_file" "$@"
            ;;
        remove)
            _registry_remove "$registry_file" "$@"
            ;;
        refresh)
            _registry_refresh "$registry_file"
            ;;
    esac
}

# Read registry file into an array (avoids shared-fd issues with nested loops)
# Sets: _REG_LINES array
_registry_read_lines() {
    _REG_LINES=()
    local registry_file="$1"
    [[ -f "$registry_file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        _REG_LINES+=("$line")
    done < "$registry_file"
}

_registry_add() {
    local registry_file="$1"; shift
    local project="$1"
    local branch="$2"
    local base="$3"
    local path="$4"
    local name="$5"
    local type="${6:-custom}"
    local tmp
    tmp=$(mktemp)
    local now
    now=$(date "+%Y-%m-%d %H:%M")
    local today
    today=$(date "+%Y-%m-%d")

    _registry_read_lines "$registry_file"
    local total=${#_REG_LINES[@]}

    local in_active=0
    local wrote_new_entry=0
    local i=0

    while [[ $i -lt $total ]]; do
        local line="${_REG_LINES[$i]}"

        if [[ "$line" == "## Active Worktrees" ]]; then
            in_active=1
            echo "$line" >> "$tmp"
            i=$((i + 1))
            continue
        fi
        if [[ "$line" == "## Recently Closed" ]]; then
            # Insert new entry before Recently Closed if no duplicate was replaced
            if [[ $wrote_new_entry -eq 0 ]]; then
                echo "" >> "$tmp"
                echo "### $name" >> "$tmp"
                echo "- **Project:** $project" >> "$tmp"
                echo "- **Branch:** $branch" >> "$tmp"
                echo "- **Base:** $base" >> "$tmp"
                echo "- **Path:** $path" >> "$tmp"
                [[ "$type" != "custom" ]] && echo "- **Type:** $type" >> "$tmp"
                echo "- **Created:** $today" >> "$tmp"
                echo "- **Last Activity:** $now (0 commits)" >> "$tmp"
                wrote_new_entry=1
            fi
            in_active=0
            echo "$line" >> "$tmp"
            i=$((i + 1))
            continue
        fi

        # Check for duplicate entry in Active section (match name AND project)
        if [[ $in_active -eq 1 ]] && [[ "$line" == "### $name" ]]; then
            # Peek ahead to check if project matches
            local entry_project=""
            local j=$((i + 1))
            while [[ $j -lt $total ]]; do
                local peek="${_REG_LINES[$j]}"
                { [[ "$peek" == "### "* ]] || [[ "$peek" == "## "* ]]; } && break
                if [[ "$peek" == "- **Project:** "* ]]; then
                    entry_project="${peek#- \*\*Project:\*\* }"
                    break
                fi
                j=$((j + 1))
            done

            if [[ "$entry_project" == "$project" ]]; then
                # Duplicate found — replace entry
                echo "### $name" >> "$tmp"
                echo "- **Project:** $project" >> "$tmp"
                echo "- **Branch:** $branch" >> "$tmp"
                echo "- **Base:** $base" >> "$tmp"
                echo "- **Path:** $path" >> "$tmp"
                [[ "$type" != "custom" ]] && echo "- **Type:** $type" >> "$tmp"
                echo "- **Created:** $today" >> "$tmp"
                echo "- **Last Activity:** $now (0 commits)" >> "$tmp"
                wrote_new_entry=1
                # Skip old entry lines
                i=$((i + 1))
                while [[ $i -lt $total ]]; do
                    local skip="${_REG_LINES[$i]}"
                    if [[ "$skip" == "### "* ]] || [[ "$skip" == "## "* ]]; then
                        break  # Don't increment — outer loop processes this line
                    fi
                    i=$((i + 1))
                done
                continue
            fi
        fi

        # Update timestamp header
        if [[ "$line" == "Last updated:"* ]]; then
            echo "Last updated: $now" >> "$tmp"
            i=$((i + 1))
            continue
        fi

        echo "$line" >> "$tmp"
        i=$((i + 1))
    done

    # Fallback: if ## Recently Closed was missing, append the entry and the section header.
    # Guard: only append if ## Recently Closed isn't already in the temp file (prevents duplicates).
    if [[ $wrote_new_entry -eq 0 ]]; then
        echo "" >> "$tmp"
        echo "### $name" >> "$tmp"
        echo "- **Project:** $project" >> "$tmp"
        echo "- **Branch:** $branch" >> "$tmp"
        echo "- **Base:** $base" >> "$tmp"
        echo "- **Path:** $path" >> "$tmp"
        [[ "$type" != "custom" ]] && echo "- **Type:** $type" >> "$tmp"
        echo "- **Created:** $today" >> "$tmp"
        echo "- **Last Activity:** $now (0 commits)" >> "$tmp"
        if ! grep -q '^## Recently Closed' "$tmp" 2>/dev/null; then
            echo "" >> "$tmp"
            echo "## Recently Closed" >> "$tmp"
        fi
    fi

    mv "$tmp" "$registry_file"
}

_registry_remove() {
    local registry_file="$1"; shift
    local project="$1"
    local branch="$2"
    local pr_url="${3:-}"
    local result="${4:-closed}"
    local match_path="${5:-}"  # Optional: prefer path-based match to avoid project+branch collisions
    local tmp
    tmp=$(mktemp)
    local now
    now=$(date "+%Y-%m-%d %H:%M")
    local today
    today=$(date "+%Y-%m-%d")

    _registry_read_lines "$registry_file"
    local total=${#_REG_LINES[@]}

    local in_active=0
    local in_recently_closed=0
    local found_name=""
    local found_type=""
    local closed_count=0
    local i=0

    while [[ $i -lt $total ]]; do
        local line="${_REG_LINES[$i]}"

        if [[ "$line" == "## Active Worktrees" ]]; then
            in_active=1
            echo "$line" >> "$tmp"
            i=$((i + 1))
            continue
        fi
        if [[ "$line" == "## Recently Closed" ]]; then
            in_active=0
            in_recently_closed=1
            echo "$line" >> "$tmp"
            # Insert captured entry at top of Recently Closed
            if [[ -n "$found_name" ]]; then
                echo "" >> "$tmp"
                echo "### $found_name (closed $today)" >> "$tmp"
                echo "- **Project:** $project" >> "$tmp"
                echo "- **Branch:** $branch" >> "$tmp"
                [[ -n "$found_type" ]] && echo "- **Type:** $found_type" >> "$tmp"
                echo "- **PR:** ${pr_url:-none}" >> "$tmp"
                echo "- **Result:** $result" >> "$tmp"
                closed_count=1  # Count the newly-inserted entry
            fi
            i=$((i + 1))
            continue
        fi

        # In Active section — look for matching entry by path (preferred) or project+branch
        if [[ $in_active -eq 1 ]] && [[ -z "$found_name" ]] && [[ "$line" == "### "* ]]; then
            local entry_name="${line#\#\#\# }"
            # Peek ahead to find project, branch, path, and type
            local entry_project=""
            local entry_branch=""
            local entry_path=""
            local entry_type=""
            local entry_end=$((i + 1))
            while [[ $entry_end -lt $total ]]; do
                local peek="${_REG_LINES[$entry_end]}"
                { [[ "$peek" == "### "* ]] || [[ "$peek" == "## "* ]]; } && break
                if [[ "$peek" == "- **Project:** "* ]]; then
                    entry_project="${peek#- \*\*Project:\*\* }"
                elif [[ "$peek" == "- **Branch:** "* ]]; then
                    entry_branch="${peek#- \*\*Branch:\*\* }"
                elif [[ "$peek" == "- **Path:** "* ]]; then
                    entry_path="${peek#- \*\*Path:\*\* }"
                elif [[ "$peek" == "- **Type:** "* ]]; then
                    entry_type="${peek#- \*\*Type:\*\* }"
                fi
                entry_end=$((entry_end + 1))
            done

            # Path-based match when caller provides path (avoids project+branch collisions)
            local is_match=0
            if [[ -n "$match_path" ]]; then
                # Only match by path when path-based matching was requested.
                # If entry has no Path field, skip it — don't fall back to project+branch.
                [[ -n "$entry_path" ]] && [[ "$entry_path" == "$match_path" ]] && is_match=1
            else
                [[ "$entry_project" == "$project" ]] && [[ "$entry_branch" == "$branch" ]] && is_match=1
            fi

            if [[ $is_match -eq 1 ]]; then
                # Match! Skip this entire entry
                found_name="$entry_name"
                found_type="$entry_type"
                i=$entry_end  # Jump past the entry
                continue
            fi
        fi

        # In Recently Closed — count entries and trim to 10
        if [[ $in_recently_closed -eq 1 ]] && [[ "$line" == "### "* ]]; then
            closed_count=$((closed_count + 1))
            if [[ $closed_count -gt 10 ]]; then
                # Skip this entry's field lines, but stop at the next top-level section (## )
                # so future sections added after Recently Closed are preserved.
                i=$((i + 1))
                while [[ $i -lt $total ]]; do
                    local skip="${_REG_LINES[$i]}"
                    [[ "$skip" == "## "* ]] && break
                    i=$((i + 1))
                done
                continue
            fi
        fi

        # Update timestamp header
        if [[ "$line" == "Last updated:"* ]]; then
            echo "Last updated: $now" >> "$tmp"
            i=$((i + 1))
            continue
        fi

        echo "$line" >> "$tmp"
        i=$((i + 1))
    done

    # Fallback: if ## Recently Closed was missing, append the removed entry
    if [[ -n "$found_name" ]] && [[ $in_recently_closed -eq 0 ]]; then
        echo "" >> "$tmp"
        echo "## Recently Closed" >> "$tmp"
        echo "" >> "$tmp"
        echo "### $found_name (closed $today)" >> "$tmp"
        echo "- **Project:** $project" >> "$tmp"
        echo "- **Branch:** $branch" >> "$tmp"
        [[ -n "$found_type" ]] && echo "- **Type:** $found_type" >> "$tmp"
        echo "- **PR:** ${pr_url:-none}" >> "$tmp"
        echo "- **Result:** $result" >> "$tmp"
    fi

    mv "$tmp" "$registry_file"
}

_registry_refresh() {
    local registry_file="$1"
    [[ -f "$registry_file" ]] || return 0
    local tmp
    tmp=$(mktemp)
    local now
    now=$(date "+%Y-%m-%d %H:%M")

    _registry_read_lines "$registry_file"
    local total=${#_REG_LINES[@]}

    local in_active=0
    # Running variables for current entry metadata (avoids grep-on-temp-file)
    local cur_path="" cur_base="" cur_branch=""
    local i=0

    while [[ $i -lt $total ]]; do
        local line="${_REG_LINES[$i]}"

        if [[ "$line" == "## Active Worktrees" ]]; then
            in_active=1
            echo "$line" >> "$tmp"
            i=$((i + 1))
            continue
        fi
        if [[ "$line" == "## Recently Closed" ]]; then
            in_active=0
            echo "$line" >> "$tmp"
            i=$((i + 1))
            continue
        fi

        # Track running entry metadata when in Active section
        if [[ $in_active -eq 1 ]]; then
            if [[ "$line" == "### "* ]]; then
                cur_path="" ; cur_base="" ; cur_branch=""
            elif [[ "$line" == "- **Path:** "* ]]; then
                cur_path="${line#- \*\*Path:\*\* }"
            elif [[ "$line" == "- **Base:** "* ]]; then
                cur_base="${line#- \*\*Base:\*\* }"
            elif [[ "$line" == "- **Branch:** "* ]]; then
                cur_branch="${line#- \*\*Branch:\*\* }"
            elif [[ "$line" == "- **Last Activity:**"* ]]; then
                if [[ -n "$cur_path" ]] && [[ -d "$cur_path" ]]; then
                    local commits=0
                    if [[ -n "$cur_base" ]] && [[ -n "$cur_branch" ]]; then
                        commits=$(git -C "$cur_path" log --oneline "$cur_base..$cur_branch" 2>/dev/null | wc -l | tr -d ' ')
                    fi
                    echo "- **Last Activity:** $now ($commits commits)" >> "$tmp"
                elif [[ -n "$cur_path" ]]; then
                    echo "- **Last Activity:** (missing)" >> "$tmp"
                else
                    echo "$line" >> "$tmp"
                fi
                i=$((i + 1))
                continue
            fi
        fi

        # Update timestamp header
        if [[ "$line" == "Last updated:"* ]]; then
            echo "Last updated: $now" >> "$tmp"
            i=$((i + 1))
            continue
        fi

        echo "$line" >> "$tmp"
        i=$((i + 1))
    done

    mv "$tmp" "$registry_file"
}

# Run command with timeout
# Usage: run_with_timeout <seconds> <command> [args...]
# Returns: command exit code on success, 124 on timeout
run_with_timeout() {
    local secs="$1"; shift
    # Prefer timeout/gtimeout if available
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return $?
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
        return $?
    fi
    # Bash-native fallback
    local tmpfile
    tmpfile=$(mktemp)
    local pidfile
    pidfile=$(mktemp)
    # F3: Save exit code before sync flush to ensure correct value in pidfile
    ( "$@" > "$tmpfile" 2>/dev/null; _ec=$?; sync; echo $_ec > "$pidfile" ) &
    local bg_pid=$!
    local elapsed=0
    while kill -0 "$bg_pid" 2>/dev/null && [[ $elapsed -lt $secs ]]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done
    if kill -0 "$bg_pid" 2>/dev/null; then
        kill -TERM "$bg_pid" 2>/dev/null
        sleep 0.5
        kill -KILL "$bg_pid" 2>/dev/null || true
        wait "$bg_pid" 2>/dev/null
        rm -f "$tmpfile" "$pidfile"
        return 124
    fi
    wait "$bg_pid" 2>/dev/null
    # F3: Wait for pidfile to be written
    local _wait=0
    while [[ ! -s "$pidfile" ]] && [[ $_wait -lt 10 ]]; do
        sleep 0.1
        _wait=$((_wait + 1))
    done
    cat "$tmpfile"
    local rc
    rc=$(cat "$pidfile" 2>/dev/null || echo 1)
    rm -f "$tmpfile" "$pidfile"
    return "$rc"
}
