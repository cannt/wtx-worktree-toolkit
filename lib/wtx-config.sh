#!/bin/bash
# wtx Config Loader
# Flat-TOML config parser for wtx. Source this from any script that needs
# access to per-repo configuration.
#
# Usage:
#   source "$WTX_ROOT/lib/wtx-config.sh"
#   org=$(wtx_config_get "forge.org" "mydefault")
#   wtx_config_get_list "projects.list"   # newline-separated
#
# Resolution order (first hit wins):
#   1. $WTX_CONFIG                              (explicit override)
#   2. $WORKSPACE_ROOT/wtx.toml                 (repo-local)
#   3. $HOME/.config/wtx/config.toml            (user global)
#
# Backward compatibility:
#   If no wtx.toml is found but $WORKSPACE_ROOT/.worktree-projects exists,
#   wtx_config_get_list "projects.list" and wtx_config_get "jira.projects.<repo>"
#   transparently fall back to that legacy file.
#
# Safety:
#   - bash 3.2 compatible (no declare -A, no readarray)
#   - No external parsers (awk/sed only)
#   - Never evals user-supplied strings
#   - Idempotent (_WTX_CONFIG_LOADED guard)

if [[ -n "${_WTX_CONFIG_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_WTX_CONFIG_LOADED=1

# Resolve which config file (if any) wtx should read.
# Prints the absolute path on stdout, or empty if none found.
_wtx_config_resolve_path() {
    if [[ -n "${WTX_CONFIG:-}" && -f "$WTX_CONFIG" ]]; then
        printf '%s\n' "$WTX_CONFIG"
        return 0
    fi
    if [[ -n "${WORKSPACE_ROOT:-}" && -f "$WORKSPACE_ROOT/wtx.toml" ]]; then
        printf '%s\n' "$WORKSPACE_ROOT/wtx.toml"
        return 0
    fi
    if [[ -f "$HOME/.config/wtx/config.toml" ]]; then
        printf '%s\n' "$HOME/.config/wtx/config.toml"
        return 0
    fi
    return 0
}

# Parse a scalar value from a flat TOML file.
# $1 = file path, $2 = dotted key (e.g. "forge.org" or "jira.projects.web")
# Prints the value or nothing.
_wtx_config_parse_scalar() {
    local file="$1" target="$2"
    [[ -f "$file" ]] || return 0
    awk -v target="$target" '
        function trim(s) {
            sub(/^[[:space:]\r]+/, "", s)
            sub(/[[:space:]\r]+$/, "", s)
            return s
        }
        BEGIN { section = "" }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            s = $0
            sub(/^[[:space:]]*\[/, "", s)
            sub(/\][[:space:]\r]*$/, "", s)
            section = trim(s)
            next
        }
        /^[[:space:]]*#/ { next }
        /^[[:space:]\r]*$/ { next }
        /=/ {
            eq = index($0, "=")
            key = trim(substr($0, 1, eq - 1))
            val = substr($0, eq + 1)
            val = trim(val)
            # list values handled separately
            if (substr(val, 1, 1) == "[") next
            # strip trailing inline comment (only when preceded by whitespace)
            if (match(val, /[[:space:]]+#/)) {
                val = substr(val, 1, RSTART - 1)
                val = trim(val)
            }
            # strip surrounding double quotes
            if (length(val) >= 2 && substr(val, 1, 1) == "\"" && substr(val, length(val), 1) == "\"") {
                val = substr(val, 2, length(val) - 2)
            }
            full = (section == "" ? key : section "." key)
            if (full == target) {
                print val
                exit
            }
        }
    ' "$file"
}

# Parse a list value from a flat TOML file.
# $1 = file path, $2 = dotted key
# Prints one value per line.
_wtx_config_parse_list() {
    local file="$1" target="$2"
    [[ -f "$file" ]] || return 0
    awk -v target="$target" '
        function trim(s) {
            sub(/^[[:space:]\r]+/, "", s)
            sub(/[[:space:]\r]+$/, "", s)
            return s
        }
        BEGIN { section = "" }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            s = $0
            sub(/^[[:space:]]*\[/, "", s)
            sub(/\][[:space:]\r]*$/, "", s)
            section = trim(s)
            next
        }
        /^[[:space:]]*#/ { next }
        /^[[:space:]\r]*$/ { next }
        /=/ {
            eq = index($0, "=")
            key = trim(substr($0, 1, eq - 1))
            val = substr($0, eq + 1)
            val = trim(val)
            if (substr(val, 1, 1) != "[") next
            full = (section == "" ? key : section "." key)
            if (full != target) next
            # strip brackets
            sub(/^\[/, "", val)
            sub(/\][[:space:]\r]*$/, "", val)
            # strip trailing inline comment
            if (match(val, /[[:space:]]+#/)) {
                val = substr(val, 1, RSTART - 1)
            }
            n = split(val, parts, ",")
            for (i = 1; i <= n; i++) {
                item = trim(parts[i])
                if (length(item) >= 2 && substr(item, 1, 1) == "\"" && substr(item, length(item), 1) == "\"") {
                    item = substr(item, 2, length(item) - 2)
                }
                if (item != "") print item
            }
            exit
        }
    ' "$file"
}

# Parse legacy .worktree-projects file.
# Format: `repo=JIRAKEY` per line, `#` comments, blank lines allowed.
# $1 = "names" to print all repo names, or "key:<repo>" to print the jira key for <repo>.
_wtx_config_fallback_worktree_projects() {
    local mode="$1"
    local file="${WORKSPACE_ROOT:-.}/.worktree-projects"
    [[ -f "$file" ]] || return 0
    case "$mode" in
        names)
            awk -F= '!/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
                gsub(/[[:space:]]/, "", $1)
                if ($1 != "") print $1
            }' "$file"
            ;;
        key:*)
            local repo="${mode#key:}"
            awk -F= -v name="$repo" '!/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
                gsub(/[[:space:]]/, "", $1)
                gsub(/[[:space:]]/, "", $2)
                sub(/#.*/, "", $2)
                if ($1 == name) { print $2; exit }
            }' "$file"
            ;;
    esac
}

# Public: get a scalar config value.
# Usage: wtx_config_get "section.key" ["default"]
wtx_config_get() {
    local key="$1"
    local default="${2:-}"
    local file value
    file="$(_wtx_config_resolve_path)"
    if [[ -n "$file" ]]; then
        value="$(_wtx_config_parse_scalar "$file" "$key")"
        if [[ -n "$value" ]]; then
            printf '%s\n' "$value"
            return 0
        fi
    fi
    # Backward-compat fallback: jira.projects.<repo> -> .worktree-projects
    case "$key" in
        jira.projects.*)
            local repo="${key#jira.projects.}"
            value="$(_wtx_config_fallback_worktree_projects "key:$repo")"
            if [[ -n "$value" ]]; then
                printf '%s\n' "$value"
                return 0
            fi
            ;;
    esac
    if [[ -n "$default" ]]; then
        printf '%s\n' "$default"
    fi
    return 0
}

# Public: walk up from $1 looking for a project root.
# A directory qualifies when it contains `.git` AND (no markers configured OR
# any one of the `detection.markers` list entries is present inside it).
# Prints the resolved directory on success, exit 1 on failure.
wtx_detect_project() {
    local dir="$1"
    [[ -n "$dir" ]] || return 1
    # Normalize to an absolute path so `dirname` converges on `/` instead of
    # looping forever on relative inputs (dirname "." == ".").
    if [[ "$dir" != /* ]]; then
        dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
    fi
    local markers
    markers="$(wtx_config_get_list "detection.markers")"
    local prev=""
    while [[ -n "$dir" && "$dir" != "/" && "$dir" != "$prev" ]]; do
        if [[ -e "$dir/.git" ]]; then
            if [[ -z "$markers" ]]; then
                printf '%s\n' "$dir"
                return 0
            fi
            local m
            while IFS= read -r m; do
                [[ -n "$m" ]] || continue
                if [[ -e "$dir/$m" ]]; then
                    printf '%s\n' "$dir"
                    return 0
                fi
            done <<< "$markers"
        fi
        prev="$dir"
        dir="$(dirname "$dir")"
    done
    return 1
}

# Public: get a list config value (one entry per line).
# Usage: wtx_config_get_list "section.key"
wtx_config_get_list() {
    local key="$1"
    local file value
    file="$(_wtx_config_resolve_path)"
    if [[ -n "$file" ]]; then
        value="$(_wtx_config_parse_list "$file" "$key")"
        if [[ -n "$value" ]]; then
            printf '%s\n' "$value"
            return 0
        fi
    fi
    # Backward-compat fallback: projects.list -> .worktree-projects
    if [[ "$key" == "projects.list" ]]; then
        _wtx_config_fallback_worktree_projects "names"
    fi
    return 0
}
