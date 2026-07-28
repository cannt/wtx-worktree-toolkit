#!/bin/bash
# wtx-clean — reclaim host-level state stranded by removed worktrees.
#
# `wtx done` cleans everything it owns: the worktree directory, the git
# registration, the local branch, the registry entry, the Warp tab. What it
# cannot clean is state that *other* tools keyed by the worktree's absolute
# path and parked outside it — IDE indexes, per-project caches. Those survive
# the worktree by design, and accumulate roughly a gigabyte per worktree that
# was ever opened in an IDE.
#
# This library finds and removes that state. It is deliberately built around
# one policy, enforced here in core and never delegated to a plugin:
#
#   A cache is an orphan iff it references at least one path inside the search
#   domain and *every* path it references there is gone from disk.
#
# The domain is $WORKSPACE_ROOT plus its parent directory. The parent matters:
# `wtx start` creates worktrees as *siblings* of the repo (Mango/rfid ->
# Mango/rfid-ADW-1563), while $WORKSPACE_ROOT resolves to the repo itself when
# wtx is invoked from inside it. Without the parent, every sibling worktree
# would sit outside the domain and no orphan would ever be found.
#
# That rule is evidence-based, not name-based: a plugin has to prove which
# worktrees a cache belongs to by pointing at real references it extracted
# from the cache's own metadata. It fails safe in both directions — a cache
# for a live worktree keeps a live reference and is skipped, and a cache for
# some unrelated project outside this workspace yields no references at all
# and is likewise skipped.
#
# Scanners (see plugins/*-cleanup.sh) own the tool-specific half: where the
# caches live and how to read a project path out of them. Core owns the
# dangerous half: deciding what counts as garbage and doing the deleting.
#
# ERROR HANDLING: `set -u` only, no `set -e` — a scanner for a tool you don't
# have installed must degrade to "no records", never to an aborted run.

# --- Fallback stubs -----------------------------------------------------------
# This lib is sourced by bin/wtx after worktree-tui.sh, but also directly by
# tests. Define no-op stubs for anything optional so both paths work.
if ! command -v wtx_log >/dev/null 2>&1; then
    wtx_log() { :; }
fi

# --- Record format ------------------------------------------------------------
# Scanners print TAB-separated records on stdout, one per line:
#
#   delete <TAB> <absolute-path> <TAB> <label> <TAB> <ref>[,<ref>...]
#   note   <TAB> -               <TAB> <message>
#
# `ref` values are absolute project paths the cache actually names, extracted
# from its own metadata (comma-separated; paths containing a comma are not
# supported). `note` records are printed as warnings and never delete anything.
#
# Scanners receive the domain in $WTX_CLEAN_ROOTS (newline-separated) so they
# know which paths are worth reporting. Core re-checks it regardless.

WTX_CLEAN_TAB=$'\t'

# _wtx_clean_domain_roots
# Directories a reference must live under to count as evidence. Keeps a cache
# belonging to some unrelated project — which names no path in the domain, and
# so yields no evidence — from ever being judged an orphan.
_wtx_clean_domain_roots() {
    [[ -n "${WORKSPACE_ROOT:-}" ]] || return 0
    printf '%s\n' "$WORKSPACE_ROOT"

    local parent
    parent="$(dirname "$WORKSPACE_ROOT")"
    # Only widen to the parent when it is still a private directory: a repo
    # checked out directly in $HOME must not turn all of $HOME into evidence.
    if [[ -n "${HOME:-}" ]] && [[ "$parent" == "$HOME"/* ]] && [[ "$parent" != "$HOME" ]]; then
        printf '%s\n' "$parent"
    fi
}

# _wtx_clean_in_domain <path>
_wtx_clean_in_domain() {
    local p="${1:-}" root
    [[ -n "$p" ]] || return 1
    while IFS= read -r root; do
        [[ -n "$root" ]] || continue
        case "$p" in
            "$root"/*) return 0 ;;
        esac
    done < <(_wtx_clean_domain_roots)
    return 1
}

# --- Safety envelope ----------------------------------------------------------

# _wtx_clean_target_ok <path>
# Core's veto on what a scanner is allowed to have us delete. A scanner bug
# must not be able to reach outside the user's cache areas.
_wtx_clean_target_ok() {
    local t="${1:-}"

    [[ -n "$t" ]]                || return 1
    [[ "$t" = /* ]]              || return 1   # absolute only
    [[ "$t" != *".."* ]]         || return 1   # no traversal
    [[ -e "$t" ]]                || return 1   # must still exist
    [[ -n "${HOME:-}" ]]         || return 1
    [[ "$t" != "$HOME" ]]        || return 1
    [[ "$t" == "$HOME"/* ]]      || return 1   # must live under $HOME

    # Require depth: at least three components below $HOME, so a malformed
    # record can never name something like ~/Library or ~/Documents.
    local rel depth
    rel="${t#"$HOME"/}"
    depth="$(printf '%s' "$rel" | tr -cd '/' | wc -c | tr -d ' ')"
    [[ "${depth:-0}" -ge 2 ]]    || return 1

    # Never touch anything inside the workspace itself — that is `wtx done`'s
    # territory and it dies with the worktree anyway.
    if [[ -n "${WORKSPACE_ROOT:-}" ]]; then
        case "$t" in
            "$WORKSPACE_ROOT"|"$WORKSPACE_ROOT"/*) return 1 ;;
        esac
    fi

    return 0
}

# _wtx_clean_refs_orphaned <comma-separated-absolute-paths>
# True when the cache names at least one in-domain path and every one of them
# is gone. Out-of-domain references are ignored rather than counted as
# missing — they are not evidence about this workspace either way.
_wtx_clean_refs_orphaned() {
    local refs="${1:-}" ref seen=0
    [[ -n "$refs" ]] || return 1
    [[ -n "${WORKSPACE_ROOT:-}" ]] || return 1

    local old_ifs="$IFS"
    IFS=','
    # shellcheck disable=SC2206
    local list=($refs)
    IFS="$old_ifs"

    for ref in "${list[@]}"; do
        [[ -n "$ref" ]] || continue
        [[ "$ref" = /* ]] || continue          # malformed record
        [[ "$ref" != *".."* ]] || continue
        _wtx_clean_in_domain "$ref" || continue
        seen=1
        if [[ -e "$ref" ]]; then
            return 1   # a live project still uses this cache
        fi
    done

    [[ "$seen" -eq 1 ]]
}

# --- Sizing -------------------------------------------------------------------

_wtx_clean_size_kb() {
    local t="${1:-}" kb
    kb="$(du -sk "$t" 2>/dev/null | awk 'NR==1{print $1}')"
    printf '%s' "${kb:-0}"
}

# Refs are absolute paths and there can be dozens; show basenames so the
# report stays readable, and cap the list.
_wtx_clean_refs_display() {
    printf '%s' "${1:-}" \
        | tr ',' '\n' \
        | sed 's|.*/||' \
        | grep -v '^$' \
        | sort -u \
        | head -4 \
        | paste -sd, - 2>/dev/null
}

_wtx_clean_human() {
    local kb="${1:-0}"
    awk -v k="$kb" 'BEGIN{
        if (k >= 1048576) printf "%.1fG", k/1048576;
        else if (k >= 1024) printf "%.0fM", k/1024;
        else printf "%dK", k;
    }'
}

# --- Scanner discovery --------------------------------------------------------

# Resolve the scanner list: explicit `[clean].scanners` when configured,
# otherwise every plugins/*-cleanup.sh in the install. Auto-discovery is safe
# because a scanner for a tool you don't have prints nothing.
_wtx_clean_scanners() {
    local configured="" entry resolved

    if command -v wtx_config_get_list >/dev/null 2>&1; then
        configured="$(wtx_config_get_list "clean.scanners" 2>/dev/null)"
    fi

    if [[ -n "$configured" ]]; then
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            if [[ "$entry" = /* ]]; then
                resolved="$entry"
            else
                resolved="${WTX_ROOT:-.}/$entry"
            fi
            if [[ -f "$resolved" ]]; then
                printf '%s\n' "$resolved"
            else
                printf 'wtx clean: configured scanner not found: %s\n' "$resolved" >&2
                wtx_log WARN "clean: scanner missing: $resolved"
            fi
        done <<< "$configured"
        return 0
    fi

    for resolved in "${WTX_ROOT:-.}"/plugins/*-cleanup.sh; do
        [[ -f "$resolved" ]] && printf '%s\n' "$resolved"
    done
    return 0
}

# --- Usage --------------------------------------------------------------------

_wtx_clean_usage() {
    cat <<EOF
wtx clean — remove host-level caches stranded by deleted worktrees

USAGE:
  wtx clean [--dry-run] [--yes] [--scanner PATH] [-v]

OPTIONS:
  -n, --dry-run       Report what would be removed; delete nothing
  -y, --yes           Skip the confirmation prompt (for scripts)
      --scanner PATH  Run only this scanner (repeatable)
  -v, --verbose       Also list caches that were inspected and kept
  -h, --help          Show this help

A cache is removed only when every project path it references is gone from
disk. Caches belonging to live worktrees, and to projects outside this
workspace, are always left alone.

Scanners: \`[clean].scanners\` in wtx.toml, else plugins/*-cleanup.sh.
EOF
}

# --- Main ---------------------------------------------------------------------

wtx_clean_run() {
    local dry_run=0 assume_yes=0 verbose=0 arg
    local explicit_scanners=""

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            -n|--dry-run) dry_run=1 ;;
            -y|--yes)     assume_yes=1 ;;
            -v|--verbose) verbose=1 ;;
            --scanner)
                shift
                [[ $# -gt 0 ]] || { echo "wtx clean: --scanner needs a path" >&2; return 2; }
                explicit_scanners="${explicit_scanners}$1"$'\n'
                ;;
            -h|--help)    _wtx_clean_usage; return 0 ;;
            *)
                printf 'wtx clean: unknown option: %s\n\n' "$arg" >&2
                _wtx_clean_usage >&2
                return 2
                ;;
        esac
        shift
    done

    if [[ -z "${WORKSPACE_ROOT:-}" ]] || [[ ! -d "$WORKSPACE_ROOT" ]]; then
        echo "wtx clean: no workspace root — run this from inside a git repo" >&2
        return 1
    fi

    local scanners
    if [[ -n "$explicit_scanners" ]]; then
        scanners="$explicit_scanners"
    else
        scanners="$(_wtx_clean_scanners)"
    fi

    echo "wtx clean — workspace: $WORKSPACE_ROOT"
    echo

    # --- Generic pass: stale git worktree administrative dirs -----------------
    # Cheap, always safe (git only prunes entries whose worktree is gone), and
    # it covers worktrees removed by hand rather than through `wtx done`.
    local pruned
    pruned="$(git -C "$WORKSPACE_ROOT" worktree prune --verbose --dry-run 2>/dev/null)"
    if [[ -n "$pruned" ]]; then
        echo "Stale git worktree registrations:"
        printf '%s\n' "$pruned" | sed 's/^/  /'
        if [[ "$dry_run" -eq 0 ]]; then
            git -C "$WORKSPACE_ROOT" worktree prune 2>/dev/null
            echo "  ✓ pruned"
            wtx_log INFO "clean: pruned stale git worktree registrations"
        fi
        echo
    fi

    if [[ -z "$scanners" ]]; then
        echo "No cache scanners found (plugins/*-cleanup.sh)."
        echo "Nothing else to do."
        return 0
    fi

    # --- Scanner pass ---------------------------------------------------------
    local tmp_records tmp_targets scanner
    tmp_records="$(mktemp "${TMPDIR:-/tmp}/wtx-clean-rec.XXXXXX")" || return 1
    tmp_targets="$(mktemp "${TMPDIR:-/tmp}/wtx-clean-tgt.XXXXXX")" || { rm -f "$tmp_records"; return 1; }

    while IFS= read -r scanner; do
        [[ -n "$scanner" ]] || continue
        if [[ ! -f "$scanner" ]]; then
            printf 'wtx clean: scanner not found: %s\n' "$scanner" >&2
            continue
        fi
        # Scanners read multi-gigabyte IDE indexes; say what is happening so a
        # ten-second pause doesn't look like a hang.
        printf 'Scanning %s …\n' "$(basename "$scanner")" >&2
        wtx_log INFO "clean: running scanner $scanner"
        # A scanner that dies must not take the run down with it.
        WORKSPACE_ROOT="$WORKSPACE_ROOT" WTX_ROOT="${WTX_ROOT:-}" \
        WTX_CLEAN_ROOTS="$(_wtx_clean_domain_roots)" \
            bash "$scanner" scan 2>/dev/null >> "$tmp_records" || \
            wtx_log WARN "clean: scanner failed: $scanner"
    done <<< "$scanners"

    local total_kb=0 orphan_count=0 kept_count=0
    local kind target label refs kb human

    while IFS="$WTX_CLEAN_TAB" read -r kind target label refs; do
        case "$kind" in
            note)
                # Notes carry their text in the label field; the target column
                # is a placeholder so the record stays TAB-aligned.
                printf '  ⚠  %s\n' "${label:-$target}"
                continue
                ;;
            delete) ;;
            *) continue ;;
        esac

        if ! _wtx_clean_target_ok "$target"; then
            wtx_log WARN "clean: rejected target outside safety envelope: $target"
            continue
        fi

        if ! _wtx_clean_refs_orphaned "${refs:-}"; then
            kept_count=$((kept_count + 1))
            if [[ "$verbose" -eq 1 ]]; then
                local shown
                shown="$(_wtx_clean_refs_display "${refs:-}")"
                printf '  keep  %-46s %s\n' "${label:-$target}" "(in use: ${shown:-no in-domain references})"
            fi
            continue
        fi

        kb="$(_wtx_clean_size_kb "$target")"
        total_kb=$((total_kb + kb))
        orphan_count=$((orphan_count + 1))
        printf '%s\n' "$target" >> "$tmp_targets"
        human="$(_wtx_clean_human "$kb")"
        printf '  %-6s %-46s %s\n' "$human" "${label:-$(basename "$target")}" "$(_wtx_clean_refs_display "$refs")"
    done < "$tmp_records"

    rm -f "$tmp_records"

    echo
    if [[ "$orphan_count" -eq 0 ]]; then
        echo "Nothing to reclaim ($kept_count cache(s) inspected, all in use)."
        rm -f "$tmp_targets"
        return 0
    fi

    printf 'Reclaimable: %s across %d item(s); %d kept (in use).\n' \
        "$(_wtx_clean_human "$total_kb")" "$orphan_count" "$kept_count"
    echo

    if [[ "$dry_run" -eq 1 ]]; then
        echo "Dry run — nothing deleted."
        rm -f "$tmp_targets"
        return 0
    fi

    if [[ "$assume_yes" -ne 1 ]]; then
        if command -v tui_confirm >/dev/null 2>&1; then
            if ! tui_confirm "Delete these $orphan_count item(s)?" false; then
                echo "Aborted."
                rm -f "$tmp_targets"
                return 0
            fi
        else
            local answer=""
            read -r -p "Delete these $orphan_count item(s)? [y/N] " answer < /dev/tty || true
            case "$answer" in
                y|Y|yes|YES) ;;
                *) echo "Aborted."; rm -f "$tmp_targets"; return 0 ;;
            esac
        fi
    fi

    local removed=0 failed=0
    while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        # Re-validate: the confirmation prompt is a window in which state can
        # change, and this is the last gate before an rm -rf.
        if ! _wtx_clean_target_ok "$target"; then
            failed=$((failed + 1))
            continue
        fi
        if rm -rf "$target" 2>/dev/null; then
            removed=$((removed + 1))
            wtx_log INFO "clean: removed $target"
        else
            failed=$((failed + 1))
            printf '  ⚠  could not remove: %s\n' "$target" >&2
            wtx_log WARN "clean: failed to remove $target"
        fi
    done < "$tmp_targets"

    rm -f "$tmp_targets"

    printf '✓ Removed %d item(s), reclaimed ~%s.\n' "$removed" "$(_wtx_clean_human "$total_kb")"
    if [[ "$failed" -gt 0 ]]; then
        printf '  %d item(s) could not be removed — see above.\n' "$failed" >&2
        return 1
    fi
    return 0
}
