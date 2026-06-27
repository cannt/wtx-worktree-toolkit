#!/usr/bin/env bash
# Shared primitives for the interactive installer.

if [[ "${_WTX_INSTALL_LIB_LOADED:-0}" -eq 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
_WTX_INSTALL_LIB_LOADED=1

# Backslash-escape `\` then `"` so a string is safe to embed between "..." in
# a TOML scalar. Order matters: escape backslashes first.
_wtx_toml_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# Convert a comma-separated input to a TOML array literal. Whitespace around
# items is trimmed. Globs are preserved verbatim by disabling pathname expansion.
_wtx_csv_to_toml_array() {
    local input="$1" item out="[" first=1
    local had_noglob=0
    case "$-" in
        *f*) had_noglob=1 ;;
    esac
    set -f
    local OLDIFS="$IFS"
    IFS=','
    # shellcheck disable=SC2206
    local items=( $input )
    IFS="$OLDIFS"
    if [[ $had_noglob -eq 0 ]]; then
        set +f
    fi
    for item in "${items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        [[ -z "$item" ]] && continue
        if [[ $first -eq 1 ]]; then first=0; else out+=", "; fi
        out+="\"$(_wtx_toml_escape "$item")\""
    done
    out+="]"
    printf '%s' "$out"
}

wtx_install_discover_plugins() {
    local root="${WTX_ROOT:-}" plugin filename stem desc line
    [[ -n "$root" ]] || return 0
    for plugin in "$root"/plugins/*.sh; do
        [[ -f "$plugin" ]] || continue
        filename="$(basename "$plugin")"
        stem="${filename%.sh}"
        desc="$stem"
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                "# wtx-plugin-desc:"*)
                    desc="${line#"# wtx-plugin-desc:"}"
                    desc="${desc#"${desc%%[![:space:]]*}"}"
                    desc="${desc%"${desc##*[![:space:]]}"}"
                    break
                    ;;
            esac
        done < "$plugin"
        printf '%s\t%s\n' "$filename" "$desc"
    done
}

wtx_install_write_or_dryrun() {
    if [[ $# -lt 2 ]]; then
        echo "wtx install: write_or_dryrun requires an action label and command" >&2
        return 2
    fi

    local action_label="$1"
    shift
    if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
        printf '[dry-run] %s\n' "$action_label"
        return 0
    fi

    "$@"
    return $?
}
