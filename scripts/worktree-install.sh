#!/bin/bash
# Interactive installer wizard skeleton.

set -u

_wtx_install_self="${BASH_SOURCE[0]}"
while [[ -L "$_wtx_install_self" ]]; do
    _wtx_install_link="$(readlink "$_wtx_install_self")"
    if [[ "$_wtx_install_link" = /* ]]; then
        _wtx_install_self="$_wtx_install_link"
    else
        _wtx_install_self="$(cd "$(dirname "$_wtx_install_self")" && pwd)/$_wtx_install_link"
    fi
done
_wtx_install_dir="$(cd "$(dirname "$_wtx_install_self")" && pwd)"

if [[ -z "${WTX_ROOT:-}" ]]; then
    if [[ -d "$_wtx_install_dir/lib" ]]; then
        WTX_ROOT="$_wtx_install_dir"
    else
        WTX_ROOT="$(cd "$_wtx_install_dir/.." && pwd)"
    fi
fi
export WTX_ROOT
unset _wtx_install_self _wtx_install_link _wtx_install_dir

_wtx_install_resolve_workspace_root() {
    if [[ -n "${WORKSPACE_ROOT:-}" ]]; then
        export WORKSPACE_ROOT
        return 0
    fi

    local gcd
    gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [[ -n "$gcd" && -d "$gcd" ]]; then
        WORKSPACE_ROOT="$(dirname "$gcd")"
    else
        WORKSPACE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    export WORKSPACE_ROOT
}

_wtx_install_source_libs() {
    # shellcheck source=../lib/wtx-install.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-install.sh"
    # shellcheck source=../lib/wtx-config.sh disable=SC1091
    source "$WTX_ROOT/lib/wtx-config.sh" 2>/dev/null || true
    # shellcheck source=../lib/worktree-tui.sh disable=SC1091
    source "$WTX_ROOT/lib/worktree-tui.sh" 2>/dev/null || {
        tui_confirm() { local r; read -r -p "$1 [y/N] " r < /dev/tty; [[ "$r" =~ ^[Yy]$ ]]; }
        tui_input() { local v; read -r -p "$1 [${2:-}]: " v < /dev/tty; echo "${v:-$2}"; }
        tui_choose() {
            if [[ "${1:-}" = "--selected" ]]; then
                shift 2
            fi
            local p="$1"; shift; PS3="$p "; select o in "$@"; do echo "$o"; break; done < /dev/tty
        }
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
}

_wtx_install_parse_args() {
    WTX_INSTALL_DRY_RUN=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                WTX_INSTALL_DRY_RUN=1
                shift
                ;;
            *)
                printf 'wtx install: unknown option: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done
    export WTX_INSTALL_DRY_RUN
    return 0
}

_wtx_install_preflight() {
    _wtx_install_parse_args "$@" || return $?

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "wtx install: not in a git repository" >&2
        return 1
    fi

    if command -v gum >/dev/null 2>&1; then
        GUM_AVAILABLE=1
    else
        GUM_AVAILABLE=0
        echo "note: gum not found — using plain prompts (install with: brew install gum)"
    fi
    export GUM_AVAILABLE

    _wtx_install_resolve_workspace_root || return $?
    _wtx_install_source_libs || return $?

    _WTX_INSTALL_TMP=""
    trap '[[ -z "${_WTX_INSTALL_TMP:-}" ]] || rm -f "$_WTX_INSTALL_TMP"' EXIT

    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
}

# ---------------------------------------------------------------------------
# Step 1 — Welcome banner (AC: 1)
# ---------------------------------------------------------------------------
_wtx_install_step_banner() {
    tui_style_box \
        "wtx install" \
        "Workspace: $WORKSPACE_ROOT" \
        "WTX root:  $WTX_ROOT" \
        "Press Ctrl-C at any time to abort."
}

_wtx_install_done_ledger_value() {
    if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
        printf 'previewed (dry-run)'
    else
        printf 'done'
    fi
}

# ---------------------------------------------------------------------------
# Step 2 — Binary install with PATH detection (AC: 2, 3)
# ---------------------------------------------------------------------------
_wtx_install_step2_binary() {
    local wtx_on_path resolved

    # Symlink-walk any existing 'wtx' on PATH — same style as WTX_ROOT resolution above
    if command -v wtx >/dev/null 2>&1; then
        resolved="$(command -v wtx)"
        while [[ -L "$resolved" ]]; do
            local lnk
            lnk="$(readlink "$resolved")"
            if [[ "$lnk" = /* ]]; then
                resolved="$lnk"
            else
                resolved="$(cd "$(dirname "$resolved")" && pwd)/$lnk"
            fi
        done
        wtx_on_path="$resolved"
    else
        wtx_on_path=""
    fi

    if [[ -n "$wtx_on_path" && "$wtx_on_path" = "$WTX_ROOT/bin/wtx" ]]; then
        printf '[✓] wtx already on PATH\n'
        _WTX_LEDGER_KEYS+=("symlink")
        _WTX_LEDGER_VALS+=("skipped (already on PATH)")
        return 0
    fi

    # Not on PATH — prompt for install prefix
    WTX_INSTALL_PREFIX="$(tui_input "Install prefix" "$HOME/.local")"
    export WTX_INSTALL_PREFIX

    local install_args=("bash" "$WTX_ROOT/install.sh" "--prefix" "$WTX_INSTALL_PREFIX")
    if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
        install_args+=("--dry-run")
    fi

    wtx_install_write_or_dryrun "would symlink: $WTX_INSTALL_PREFIX/bin/wtx -> $WTX_ROOT/bin/wtx" "${install_args[@]}"
    local rc=$?

    _WTX_LEDGER_KEYS+=("symlink")
    if [[ $rc -eq 0 ]]; then
        _WTX_LEDGER_VALS+=("$(_wtx_install_done_ledger_value)")
    else
        _WTX_LEDGER_VALS+=("failed")
    fi
    return $rc
}

# ---------------------------------------------------------------------------
# Steps 3–7 — Config prompts (AC: 4, 5, 9)
# ---------------------------------------------------------------------------
_wtx_install_steps3_7_config() {
    local _pf_forge_type="" _pf_forge_org="" _pf_forge_base_url=""
    local _pf_projects="" _pf_detection="" _pf_marker_preset=""
    local _pf_base_branch="main" _pf_branch_prefix="feature"
    if [[ "${_WTX_INSTALL_MODE:-}" = "merge" ]]; then
        _pf_forge_type="$(wtx_config_get "forge.type" "")"
        _pf_forge_org="$(wtx_config_get "forge.org" "")"
        _pf_forge_base_url="$(wtx_config_get "forge.base_url" "")"
        _pf_projects="$(wtx_config_get_list "projects.list" | tr '\n' ',' | sed 's/,$//')"
        _pf_detection="$(wtx_config_get_list "detection.markers" | tr '\n' ',' | sed 's/,$//')"
        _pf_base_branch="$(wtx_config_get "defaults.base_branch" "main")"
        _pf_branch_prefix="$(wtx_config_get "defaults.branch_prefix" "feature")"
        case "$_pf_detection" in
            "") _pf_marker_preset=".git (any git repo — default)" ;;
            "settings.gradle,settings.gradle.kts") _pf_marker_preset="Gradle / Android" ;;
            "Cargo.toml") _pf_marker_preset="Rust" ;;
            "package.json") _pf_marker_preset="Node.js" ;;
            *) _pf_marker_preset="Custom…" ;;
        esac
    fi

    # Step 3 — Forge configuration
    local _forge_sel_args=()
    [[ -n "$_pf_forge_type" ]] && _forge_sel_args=("--selected" "$_pf_forge_type")
    if [[ ${#_forge_sel_args[@]} -gt 0 ]]; then
        forge_type="$(tui_choose "${_forge_sel_args[@]}" "Forge type" "github" "gitlab" "bitbucket")"
    else
        forge_type="$(tui_choose "Forge type" "github" "gitlab" "bitbucket")"
    fi
    forge_org="$(tui_input "Forge org / owner slug" "$_pf_forge_org")"
    forge_base_url=""
    if tui_confirm "Self-hosted instance?" "${_pf_forge_base_url:+yes}"; then
        forge_base_url="$(tui_input "Base URL" "$_pf_forge_base_url")"
    fi

    # Step 4 — Project dirs
    projects_csv="$(tui_input "Known project dirs (comma-separated, optional)" "$_pf_projects")"

    # Step 5 — Detection markers
    local marker_choice
    local _marker_sel_args=()
    [[ -n "$_pf_marker_preset" ]] && _marker_sel_args=("--selected" "$_pf_marker_preset")
    if [[ ${#_marker_sel_args[@]} -gt 0 ]]; then
        marker_choice="$(tui_choose "${_marker_sel_args[@]}" "Detection markers" \
            ".git (any git repo — default)" \
            "Gradle / Android" \
            "Rust" \
            "Node.js" \
            "Custom…")"
    else
        marker_choice="$(tui_choose "Detection markers" \
            ".git (any git repo — default)" \
            "Gradle / Android" \
            "Rust" \
            "Node.js" \
            "Custom…")"
    fi
    case "$marker_choice" in
        ".git (any git repo — default)")
            detection_csv=""
            ;;
        "Gradle / Android")
            detection_csv="settings.gradle,settings.gradle.kts"
            ;;
        "Rust")
            detection_csv="Cargo.toml"
            ;;
        "Node.js")
            detection_csv="package.json"
            ;;
        "Custom…")
            detection_csv="$(tui_input "Detection markers (comma-separated)" "$_pf_detection")"
            ;;
        *)
            detection_csv=""
            ;;
    esac

    # Step 6 — Branch defaults
    base_branch="$(tui_input "Default base branch" "$_pf_base_branch")"
    branch_prefix="$(tui_input "Default branch prefix" "$_pf_branch_prefix")"

    # Step 7 — Jira project key mapping (parallel indexed arrays, bash 3.2)
    _WTX_JIRA_REPOS=()
    _WTX_JIRA_KEYS=()
    if [[ "${_WTX_INSTALL_MODE:-}" = "merge" ]]; then
        printf 'note: Jira mappings are not pre-filled — re-enter them or skip.\n' >&2
    fi
    while true; do
        local jira_repo
        jira_repo="$(tui_input "Repo name for Jira mapping (blank to skip)")"
        [[ -z "$jira_repo" ]] && break
        local jira_key
        jira_key="$(tui_input "Jira project key for \"$jira_repo\"")"
        _WTX_JIRA_REPOS+=("$jira_repo")
        _WTX_JIRA_KEYS+=("$jira_key")
        tui_confirm "Add another Jira mapping?" || break
    done
}

# ---------------------------------------------------------------------------
# Step 8 — Plugin discovery + setup-hook selection (AC: 6)
# ---------------------------------------------------------------------------
_wtx_install_step8_hook() {
    setup_hook=""
    local _pf_setup_hook=""
    if [[ "${_WTX_INSTALL_MODE:-}" = "merge" ]]; then
        _pf_setup_hook="$(wtx_config_get "worktree.setup_hook" "")"
    fi

    # Discover plugins into parallel arrays (bash 3.2, no declare -A, no bare read)
    local _plugin_files=()
    local _plugin_descs=()
    local discovered fname fdesc

    discovered="$(wtx_install_discover_plugins)"
    if [[ -n "$discovered" ]]; then
        local _had_noglob=0
        case "$-" in *f*) _had_noglob=1 ;; esac
        set -f
        local OLDIFS="$IFS"
        IFS=$'\n'
        local _disc_lines
        _disc_lines=( $discovered )
        IFS="$OLDIFS"
        [[ $_had_noglob -eq 0 ]] && set +f
        local _di=0
        while [[ $_di -lt ${#_disc_lines[@]} ]]; do
            local _line="${_disc_lines[$_di]}"
            [[ -z "$_line" ]] && { _di=$((_di + 1)); continue; }
            fname="${_line%%	*}"
            fdesc="${_line#*	}"
            _plugin_files+=("$fname")
            _plugin_descs+=("$fdesc")
            _di=$((_di + 1))
        done
    fi

    # Build display list: None, Custom path…, then discovered plugins
    local display_items=("None" "Custom path…")
    local i=0
    while [[ $i -lt ${#_plugin_files[@]} ]]; do
        display_items+=("${_plugin_files[$i]} — ${_plugin_descs[$i]}")
        i=$((i + 1))
    done

    local _selected_hook=""
    if [[ "${_WTX_INSTALL_MODE:-}" = "merge" ]]; then
        if [[ -z "$_pf_setup_hook" ]]; then
            _selected_hook="None"
        elif [[ "$_pf_setup_hook" = plugins/* ]]; then
            local _pf_plugin="${_pf_setup_hook#plugins/}"
            local _hi=0
            while [[ $_hi -lt ${#_plugin_files[@]} ]]; do
                if [[ "${_plugin_files[$_hi]}" = "$_pf_plugin" ]]; then
                    _selected_hook="${_plugin_files[$_hi]} — ${_plugin_descs[$_hi]}"
                    break
                fi
                _hi=$((_hi + 1))
            done
        fi
        [[ -z "$_selected_hook" ]] && _selected_hook="Custom path…"
    fi

    local chosen
    local _hook_sel_args=()
    [[ -n "$_selected_hook" ]] && _hook_sel_args=("--selected" "$_selected_hook")
    if [[ ${#_hook_sel_args[@]} -gt 0 ]]; then
        chosen="$(tui_choose "${_hook_sel_args[@]}" "Setup hook (runs after worktree create)" "${display_items[@]}")"
    else
        chosen="$(tui_choose "Setup hook (runs after worktree create)" "${display_items[@]}")"
    fi

    case "$chosen" in
        "None")
            setup_hook=""
            ;;
        "Custom path…")
            setup_hook="$(tui_input "Relative path to setup hook script" "$_pf_setup_hook")"
            ;;
        *)
            # Resolve label back to filename: label format is "filename — desc"
            local chosen_file="${chosen%% — *}"
            setup_hook="plugins/$chosen_file"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Atomic TOML write (AC: 7, 8, 9)
# ---------------------------------------------------------------------------
_wtx_install_emit_toml() {
    # [forge]
    printf '[forge]\n'
    printf 'type = "%s"\n' "$(_wtx_toml_escape "$forge_type")"
    printf 'org = "%s"\n' "$(_wtx_toml_escape "$forge_org")"
    if [[ -n "${forge_base_url:-}" ]]; then
        printf 'base_url = "%s"\n' "$(_wtx_toml_escape "$forge_base_url")"
    else
        printf '# base_url = "https://forge.mycompany.internal"\n'
    fi
    printf '\n'

    # [jira.projects]
    printf '\n[jira.projects]\n'
    local ji=0
    while [[ $ji -lt ${#_WTX_JIRA_REPOS[@]} ]]; do
        printf '%s = "%s"\n' \
            "$(_wtx_toml_escape "${_WTX_JIRA_REPOS[$ji]}")" \
            "$(_wtx_toml_escape "${_WTX_JIRA_KEYS[$ji]}")"
        ji=$((ji + 1))
    done
    if [[ ${#_WTX_JIRA_REPOS[@]} -eq 0 ]]; then
        printf '# repo = "PROJKEY"\n'
    fi
    printf '\n'

    # [projects]
    printf '\n[projects]\n'
    printf 'list = %s\n' "$(_wtx_csv_to_toml_array "${projects_csv:-}")"
    printf '\n'

    # [detection]
    printf '\n[detection]\n'
    if [[ -n "${detection_csv:-}" ]]; then
        printf 'markers = %s\n' "$(_wtx_csv_to_toml_array "$detection_csv")"
    else
        printf '# markers = [".git"]\n'
    fi
    printf '\n'

    # [worktree]
    printf '\n[worktree]\n'
    printf 'registry_path = ".claude/worktree-registry.md"\n'
    printf 'builtin_path = ".claude/worktrees"\n'
    if [[ -n "${setup_hook:-}" ]]; then
        printf 'setup_hook = "%s"\n' "$(_wtx_toml_escape "$setup_hook")"
    else
        printf '# setup_hook = "plugins/android-setup.sh"\n'
    fi
    printf '\n'

    # [defaults]
    printf '\n[defaults]\n'
    printf 'base_branch = "%s"\n' "$(_wtx_toml_escape "${base_branch:-main}")"
    printf 'branch_prefix = "%s"\n' "$(_wtx_toml_escape "${branch_prefix:-feature}")"
}

_wtx_install_prepare_toml_tmp() {
    [[ -n "${_WTX_INSTALL_TMP:-}" ]] && return 0
    _WTX_INSTALL_TMP="$(mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX")" || return 1
}

_wtx_install_commit_toml() {
    _wtx_install_prepare_toml_tmp || return $?
    _wtx_install_emit_toml > "$_WTX_INSTALL_TMP" && mv "$_WTX_INSTALL_TMP" "$WORKSPACE_ROOT/wtx.toml"
}

# ---------------------------------------------------------------------------
# Step 9 — Claude Code hooks setup
# ---------------------------------------------------------------------------
_wtx_install_step9_claude_hooks() {
    tui_style_box \
        "Claude Code hooks — what will be installed:" \
        "  worktree-create.sh  — runs after 'wtx start' creates a worktree" \
        "  worktree-detect.sh  — runs when Claude detects the active worktree" \
        "  worktree-remove.sh  — runs after 'wtx done' removes a worktree"

    if ! tui_confirm "Install Claude Code hooks?" "yes"; then
        _WTX_LEDGER_KEYS+=("hooks")
        _WTX_LEDGER_VALS+=("skipped")
        return 0
    fi

    local install_args=("bash" "$WTX_ROOT/install.sh" "--hooks")
    if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
        install_args+=("--dry-run")
    fi

    local old_pwd rc=0
    if ! old_pwd="$(pwd)"; then
        printf 'wtx install: could not determine current directory\n' >&2
        rc=1
    elif ! cd "$WORKSPACE_ROOT"; then
        printf 'wtx install: cannot cd to workspace root: %s\n' "$WORKSPACE_ROOT" >&2
        rc=1
    else
        wtx_install_write_or_dryrun "would copy: $WTX_ROOT/hooks/worktree-*.sh -> $WORKSPACE_ROOT/.claude/hooks/" "${install_args[@]}"
        rc=$?
        if ! cd "$old_pwd"; then
            printf 'wtx install: could not restore directory: %s\n' "$old_pwd" >&2
            [[ $rc -eq 0 ]] && rc=1
        fi
    fi

    _WTX_LEDGER_KEYS+=("hooks")
    if [[ $rc -eq 0 ]]; then
        _WTX_LEDGER_VALS+=("$(_wtx_install_done_ledger_value)")
    else
        _WTX_LEDGER_VALS+=("failed")
    fi
    return $rc
}

# ---------------------------------------------------------------------------
# Step 10 — Optional extras
# ---------------------------------------------------------------------------
_wtx_install_step10_extras() {
    local rc=0
    local gradle_rc=0
    local prefix="${WTX_INSTALL_PREFIX:-$HOME/.local}"
    WTX_INSTALL_PREFIX="$prefix"
    export WTX_INSTALL_PREFIX

    tui_style_box \
        "Optional extras" \
        "Gradle worktree-cache init script" \
        "  Isolates Gradle build caches per worktree."

    if tui_confirm "Install Gradle worktree-cache init script to ~/.gradle/init.d/?"; then
        local install_args=("bash" "$WTX_ROOT/install.sh" "--gradle")
        if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
            install_args+=("--dry-run")
        fi

        wtx_install_write_or_dryrun "would copy: $WTX_ROOT/share/gradle/worktree-cache.init.gradle.kts -> $HOME/.gradle/init.d/worktree-cache.init.gradle.kts" "${install_args[@]}"
        gradle_rc=$?
        _WTX_LEDGER_KEYS+=("gradle")
        if [[ $gradle_rc -eq 0 ]]; then
            _WTX_LEDGER_VALS+=("$(_wtx_install_done_ledger_value)")
        else
            _WTX_LEDGER_VALS+=("failed")
            rc=$gradle_rc
        fi
    else
        _WTX_LEDGER_KEYS+=("gradle")
        _WTX_LEDGER_VALS+=("skipped")
    fi

    case ":$PATH:" in
        *":$WTX_INSTALL_PREFIX/bin:"*)
            _WTX_LEDGER_KEYS+=("path-hint")
            _WTX_LEDGER_VALS+=("skipped (already on PATH)")
            ;;
        *)
            if tui_confirm "Show PATH setup hint?" "yes"; then
                local hint_bin="$WTX_INSTALL_PREFIX/bin"
                if [[ "$WTX_INSTALL_PREFIX" = "$HOME/.local" ]]; then
                    hint_bin='$HOME/.local/bin'
                fi
                printf '  Add to your shell startup file:\n'
                printf '    export PATH="%s:$PATH"\n' "$hint_bin"
                printf '  then restart your shell (or source that file)\n'
                _WTX_LEDGER_KEYS+=("path-hint")
                _WTX_LEDGER_VALS+=("shown")
            else
                _WTX_LEDGER_KEYS+=("path-hint")
                _WTX_LEDGER_VALS+=("skipped")
            fi
            ;;
    esac

    return $rc
}

# ---------------------------------------------------------------------------
# Main run — wire step sequence (AC: 10)
# ---------------------------------------------------------------------------
_wtx_install_step0_idempotency() {
    _WTX_INSTALL_MODE="overwrite"
    [[ ! -f "$WORKSPACE_ROOT/wtx.toml" ]] && return 0

    tui_style_box \
        "wtx.toml already exists" \
        "  $WORKSPACE_ROOT/wtx.toml"
    _WTX_INSTALL_MODE="$(tui_choose "How do you want to proceed?" "skip" "overwrite" "merge")"
}

_wtx_install_step11_summary() {
    if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
        printf '[dry-run] No files were written. Remove --dry-run to apply.\n'
    fi
}

_wtx_install_run() {
    local _run_rc=0

    _wtx_install_preflight "$@" || return $?

    _wtx_install_step0_idempotency || return $?

    if [[ "${_WTX_INSTALL_MODE:-overwrite}" = "skip" ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("kept (existing)")
        _wtx_install_step9_claude_hooks || _run_rc=$?
        _wtx_install_step10_extras || _run_rc=$?
        _wtx_install_step11_summary || _run_rc=$?
        return $_run_rc
    fi

    if [[ "${_WTX_INSTALL_MODE:-overwrite}" = "merge" ]]; then
        unset _WTX_CONFIG_LOADED
        WTX_CONFIG="$WORKSPACE_ROOT/wtx.toml"
        export WTX_CONFIG
        # shellcheck source=../lib/wtx-config.sh disable=SC1091
        source "$WTX_ROOT/lib/wtx-config.sh"
    fi

    # Step 1 — Welcome banner
    _wtx_install_step_banner || return $?

    # Step 2 — Binary install
    _wtx_install_step2_binary || return $?

    # Steps 3–7 — Config prompts
    _wtx_install_steps3_7_config || return $?

    # Step 8 — Plugin discovery + setup-hook selection
    _wtx_install_step8_hook || return $?

    # Atomic TOML write
    wtx_install_write_or_dryrun "would write: $WORKSPACE_ROOT/wtx.toml" _wtx_install_commit_toml
    local toml_rc=$?
    if [[ $toml_rc -eq 0 ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("$(_wtx_install_done_ledger_value)")
    elif [[ $toml_rc -ne 0 ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("failed")
        return $toml_rc
    fi

    # Step 9 — Claude Code hooks setup
    _wtx_install_step9_claude_hooks || _run_rc=$?

    # Step 10a/10b — Extras menu
    _wtx_install_step10_extras || _run_rc=$?

    # Step 11 — Completion summary + doctor handoff (full table deferred to Story 1.7)
    _wtx_install_step11_summary || _run_rc=$?

    return $_run_rc
}

_wtx_install_run "$@"
