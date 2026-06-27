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

    _WTX_INSTALL_TMP="$(mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX")" || return 1
    trap 'rm -f "$_WTX_INSTALL_TMP"' EXIT

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

    wtx_install_write_or_dryrun "would create: $WTX_INSTALL_PREFIX/bin/wtx" "${install_args[@]}"
    local rc=$?

    _WTX_LEDGER_KEYS+=("symlink")
    if [[ $rc -eq 0 ]]; then
        _WTX_LEDGER_VALS+=("done")
    else
        _WTX_LEDGER_VALS+=("failed")
    fi
    return $rc
}

# ---------------------------------------------------------------------------
# Steps 3–7 — Config prompts (AC: 4, 5, 9)
# ---------------------------------------------------------------------------
_wtx_install_steps3_7_config() {
    # Step 3 — Forge configuration
    forge_type="$(tui_choose "Forge type" "github" "gitlab" "bitbucket")"
    forge_org="$(tui_input "Forge org / owner slug")"
    forge_base_url=""
    if tui_confirm "Self-hosted instance?"; then
        forge_base_url="$(tui_input "Base URL")"
    fi

    # Step 4 — Project dirs
    projects_csv="$(tui_input "Known project dirs (comma-separated, optional)")"

    # Step 5 — Detection markers
    local marker_choice
    marker_choice="$(tui_choose "Detection markers" \
        ".git (any git repo — default)" \
        "Gradle / Android" \
        "Rust" \
        "Node.js" \
        "Custom…")"
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
            detection_csv="$(tui_input "Detection markers (comma-separated)")"
            ;;
        *)
            detection_csv=""
            ;;
    esac

    # Step 6 — Branch defaults
    base_branch="$(tui_input "Default base branch" "main")"
    branch_prefix="$(tui_input "Default branch prefix" "feature")"

    # Step 7 — Jira project key mapping (parallel indexed arrays, bash 3.2)
    _WTX_JIRA_REPOS=()
    _WTX_JIRA_KEYS=()
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

    local chosen
    chosen="$(tui_choose "Setup hook (runs after worktree create)" "${display_items[@]}")"

    case "$chosen" in
        "None")
            setup_hook=""
            ;;
        "Custom path…")
            setup_hook="$(tui_input "Relative path to setup hook script")"
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

_wtx_install_commit_toml() {
    _wtx_install_emit_toml > "$_WTX_INSTALL_TMP" && mv "$_WTX_INSTALL_TMP" "$WORKSPACE_ROOT/wtx.toml"
}

# ---------------------------------------------------------------------------
# Main run — wire step sequence (AC: 10)
# ---------------------------------------------------------------------------
_wtx_install_run() {
    _wtx_install_preflight "$@" || return $?

    # Step 0 — idempotency gate (placeholder — Story 1.5 / AD-13)
    # _wtx_install_step0_idempotency

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
    if [[ $toml_rc -eq 0 && "${WTX_INSTALL_DRY_RUN:-0}" != "1" ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("done")
    elif [[ $toml_rc -ne 0 ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("failed")
        return $toml_rc
    fi

    # Step 9 — Claude Code hooks setup (placeholder — Story 1.3)
    # _wtx_install_step9_claude_hooks

    # Step 10a/10b — Extras menu (placeholder — Story 1.4)
    # _wtx_install_step10_extras

    # Step 11 — Completion summary + doctor handoff (placeholder — Story 1.7)
    # _wtx_install_step11_summary

    return 0
}

_wtx_install_run "$@"
