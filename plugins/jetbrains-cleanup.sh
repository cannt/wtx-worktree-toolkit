#!/bin/bash
# JetBrains / Android Studio cache scanner for `wtx clean`.
#
# IDEs park a per-project index outside the project, keyed by its absolute
# path, and never notice when that path disappears. A worktree that was opened
# in Android Studio therefore strands roughly a gigabyte of RocksDB indexes
# and cache state after `wtx done` removes it.
#
# Usage: jetbrains-cleanup.sh scan
#
# Prints TAB-separated records on stdout for lib/wtx-clean.sh:
#
#   delete <TAB> <absolute-path> <TAB> <label> <TAB> <ref>[,<ref>...]
#   note   <TAB> -               <TAB> <message>
#
# `ref` values are absolute project paths the cache actually names, read out of
# its own metadata. This scanner never decides what is garbage — it only
# reports evidence. Core (`wtx clean`) applies the orphan rule and owns every
# deletion.
#
# ERROR HANDLING: no set -e. Missing IDE, missing caches, unreadable files —
# all degrade to "no records", never to an error.

set -u

MODE="${1:-scan}"

if [[ "$MODE" != "scan" ]]; then
    echo "Usage: $0 scan" >&2
    exit 2
fi

if [[ -z "${WORKSPACE_ROOT:-}" ]] || [[ ! -d "$WORKSPACE_ROOT" ]]; then
    exit 0
fi

TAB=$'\t'

# The search domain, supplied by core. Standalone runs (tests, manual
# invocation) fall back to the same rule core uses: the workspace and its
# parent, because `wtx start` creates worktrees as siblings of the repo.
if [[ -n "${WTX_CLEAN_ROOTS:-}" ]]; then
    ROOTS="$WTX_CLEAN_ROOTS"
else
    ROOTS="$WORKSPACE_ROOT"
    _parent="$(dirname "$WORKSPACE_ROOT")"
    if [[ -n "${HOME:-}" ]] && [[ "$_parent" == "$HOME"/* ]]; then
        ROOTS="$ROOTS"$'\n'"$_parent"
    fi
fi

# Metadata that names a project is always small; a multi-gigabyte file here is
# an index, and those are handled separately with early exit.
MAX_PROBE_BYTES=$((32 * 1024 * 1024))

# --- Match expression ---------------------------------------------------------

_ere_escape() {
    printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\\/]/\\&/g'
}

# One alternation over every domain root: "<root-a>/[names]+|<root-b>/[names]+".
MATCH_ERE=""
while IFS= read -r _root; do
    [[ -n "$_root" ]] || continue
    _esc="$(_ere_escape "$_root")"
    if [[ -n "$MATCH_ERE" ]]; then
        MATCH_ERE="${MATCH_ERE}|${_esc}/[A-Za-z0-9._-]+"
    else
        MATCH_ERE="${_esc}/[A-Za-z0-9._-]+"
    fi
done <<< "$ROOTS"

[[ -n "$MATCH_ERE" ]] || exit 0

# --- Reference extraction -----------------------------------------------------

# _paths_in <file>...
# Absolute in-domain paths named by these files, one per line, deduplicated.
# Binary caches yield trailing junk on some matches (a real path followed by
# raw bytes). That is harmless: a garbage path simply reads as a project that
# no longer exists, while the clean copy of the same path also appears and is
# what keeps a live cache alive.
_paths_in() {
    LC_ALL=C grep -a -h -o -E "$MATCH_ERE" "$@" 2>/dev/null | sort -u
}

# _any_live <<< paths — true if any of these paths still exists.
_any_live() {
    local p
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        [[ -e "$p" ]] && return 0
    done
    return 1
}

# _scan_files_until_live <file>...
# Accumulate references file by file, stopping as soon as one of them proves
# the project is still alive. Two reasons to do it in this order: a live cache
# costs one file instead of a full read of a 12 GB index, and the earliest
# possible exit is also the safest outcome — the moment we know a cache is in
# use there is nothing left to decide.
_scan_files_until_live() {
    local f acc="" hits
    for f in "$@"; do
        [[ -f "$f" ]] || continue
        hits="$(_paths_in "$f")"
        [[ -n "$hits" ]] || continue
        acc="${acc}${hits}"$'\n'
        if printf '%s\n' "$hits" | _any_live; then
            break
        fi
    done
    printf '%s' "$acc" | grep -v '^$' | sort -u
}

_to_csv() {
    paste -sd, - 2>/dev/null
}

_emit_delete() {
    # <path> <label> <refs-csv>
    [[ -n "${3:-}" ]] || return 0   # no evidence, no record
    printf 'delete%s%s%s%s%s%s\n' "$TAB" "$1" "$TAB" "$2" "$TAB" "$3"
}

# --- Scan ---------------------------------------------------------------------

# Per-product caches: <root>/JetBrains/<Product>/ and <root>/Google/<Product>/.
#
# `projects/<name>.<hash>` is the entry that holds real project metadata, so it
# is scanned first and becomes the source of truth. Sibling directories
# (compiler/, vcs-log/, compile-server/) contain no path references at all —
# they can only be identified by the id they share with a projects/ entry, so
# they inherit that entry's references rather than inventing their own.
_scan_product_dir() {
    local product="$1" product_name
    product_name="$(basename "$product")"

    local entry name name_part hash_part refs files f
    local index=""   # "<name_part>|<hash_part>|<refs-csv>" per line

    for entry in "$product"/projects/*; do
        [[ -d "$entry" ]] || continue
        name="$(basename "$entry")"
        # IntelliJ names these "<project-basename>.<hash>".
        case "$name" in
            *.*) hash_part="${name##*.}"; name_part="${name%.*}" ;;
            *)   hash_part=""; name_part="$name" ;;
        esac

        files="$(find "$entry" -type f -size -"$((MAX_PROBE_BYTES / 1024))"k 2>/dev/null | head -400)"
        [[ -n "$files" ]] || continue

        local list=()
        while IFS= read -r f; do
            [[ -n "$f" ]] && list+=("$f")
        done <<< "$files"
        [[ "${#list[@]}" -gt 0 ]] || continue

        refs="$(_scan_files_until_live "${list[@]}" | _to_csv)"
        [[ -n "$refs" ]] || continue

        index="${index}${name_part}|${hash_part}|${refs}"$'\n'
        _emit_delete "$entry" "$product_name/projects/$name" "$refs"
    done

    [[ -n "$index" ]] || return 0

    local sub sib sib_name key matches match_refs count
    for sub in compiler vcs-log compile-server external_build_system; do
        [[ -d "$product/$sub" ]] || continue
        for sib in "$product/$sub"/*; do
            [[ -e "$sib" ]] || continue
            sib_name="$(basename "$sib")"

            # Prefer the hash: it is unique per project and survives the name
            # truncation that vcs-log applies ("rfid-sync-fixes" -> "rfid-sy").
            matches=""
            while IFS='|' read -r name_part hash_part refs; do
                [[ -n "$hash_part" ]] || continue
                case "$sib_name" in
                    *"$hash_part"*) matches="${matches}${refs}"$'\n' ;;
                esac
            done <<< "$index"

            if [[ -z "$matches" ]]; then
                # Fall back to an exact name match on the part before the last
                # underscore ("rfid-adw-1563_1fb39acb" -> "rfid-adw-1563").
                key="${sib_name%_*}"
                while IFS='|' read -r name_part hash_part refs; do
                    [[ -n "$name_part" ]] || continue
                    if [[ "$key" == "$name_part" ]] || [[ "$sib_name" == "$name_part" ]]; then
                        matches="${matches}${refs}"$'\n'
                    fi
                done <<< "$index"
            fi

            # Ambiguity is a reason to do nothing: if two projects share a name
            # we cannot tell whose cache this is, and guessing risks deleting a
            # live project's index.
            match_refs="$(printf '%s' "$matches" | grep -v '^$' | sort -u)"
            count="$(printf '%s\n' "$match_refs" | grep -c . )"
            [[ "$count" -eq 1 ]] || continue

            _emit_delete "$sib" "$product_name/$sub/$sib_name" "$match_refs"
        done
    done
}

# The Analyzer index is shared across products and keyed only by an opaque
# hash — nothing in the directory name identifies the project. These are the
# big ones (~1 GB per worktree), so getting them right matters most.
#
# workspace-model.cache is the obvious place to look, but it names the project
# only sometimes: of three workspaces observed, one recorded its path there and
# two recorded it only inside the RocksDB index. Probing just the model file
# would leave an orphan looking identical to a workspace whose live project
# simply wasn't mentioned — and that confusion is what would get a live 4 GB
# index deleted. So probe the index too, model file first and stopping at the
# first proof of life.
_scan_analyzer() {
    local workspaces="$1" ws refs files f

    for ws in "$workspaces"/*; do
        [[ -d "$ws" ]] || continue
        # A workspace with no model file is not one of these caches.
        [[ -f "$ws/workspace-model.cache" ]] || continue

        # Model file first (cheap, often decisive), then index files newest
        # first — the most recently written ones are likeliest to name a path.
        files="$(find "$ws" -type f -not -name workspace-model.cache -exec ls -t {} + 2>/dev/null | head -200)"

        local list=("$ws/workspace-model.cache")
        while IFS= read -r f; do
            [[ -n "$f" ]] && list+=("$f")
        done <<< "$files"

        refs="$(_scan_files_until_live "${list[@]}" | _to_csv)"
        [[ -n "$refs" ]] || continue

        _emit_delete "$ws" "analyzer/workspaces/$(basename "$ws")" "$refs"
    done
}

_root=""
_found_any=0
while IFS= read -r _base; do
    [[ -d "$_base" ]] || continue
    for _vendor in "$_base/JetBrains" "$_base/Google"; do
        [[ -d "$_vendor" ]] || continue
        for _product in "$_vendor"/*; do
            [[ -d "$_product" ]] || continue
            _found_any=1
            if [[ "$(basename "$_product")" == "analyzer" ]]; then
                [[ -d "$_product/workspaces" ]] && _scan_analyzer "$_product/workspaces"
                continue
            fi
            _scan_product_dir "$_product"
        done
    done
done <<EOF
$HOME/Library/Caches
$HOME/.cache
EOF

# A running IDE will not corrupt anything here — these caches belong to
# projects that no longer exist — but it can rewrite its own state on exit, so
# say so rather than let it look like the cleanup failed.
if [[ "$_found_any" -eq 1 ]] && command -v pgrep >/dev/null 2>&1; then
    if pgrep -f "Android Studio|idea|IntelliJ" >/dev/null 2>&1; then
        printf 'note%s-%sAn IDE is running; it may re-create some entries on exit.\n' "$TAB" "$TAB"
    fi
fi

exit 0
