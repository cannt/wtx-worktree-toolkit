#!/bin/bash
# tests/test-wtx-update.sh — assertions for the update layer (lib/wtx-update.sh).
# Run: bash tests/test-wtx-update.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LIB="$REPO_ROOT/lib/wtx-update.sh"

FAILS=0
TOTAL=0

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$actual" == "$expected" ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      expected: %q\n' "$expected"
        printf '      actual:   %q\n' "$actual"
    fi
}

assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      expected to contain: %q\n' "$needle"
        printf '      actual:              %q\n' "$haystack"
    fi
}

# Quiet, deterministic git for fixtures.
_git() { git -c init.defaultBranch=main -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# -- Case 1: lib sources idempotently and defines the public API
source "$LIB"
source "$LIB"
assert_eq "lib guard: set" 1 "${_WTX_UPDATE_LIB_LOADED:-0}"
for fn in wtx_update_toolkit wtx_update_hooks wtx_update_check_schema wtx_update_report wtx_update_run; do
    if command -v "$fn" >/dev/null 2>&1; then
        TOTAL=$((TOTAL + 1)); printf 'PASS  lib defines %s\n' "$fn"
    else
        FAILS=$((FAILS + 1)); TOTAL=$((TOTAL + 1)); printf 'FAIL  lib defines %s\n' "$fn"
    fi
done

# -- Case 2: version reader trims and falls back
tmpv="$(mktemp -d)"
printf '  v1.2.3\n' > "$tmpv/VERSION"
assert_eq "version: trims + strips leading v" "1.2.3" "$(_wtx_update_read_version "$tmpv")"
rm -f "$tmpv/VERSION"
assert_eq "version: fallback when absent" "0.1.0-dev" "$(_wtx_update_read_version "$tmpv")"
rm -rf "$tmpv"

# -- Case 3: non-git WTX_ROOT → toolkit skipped, rc 0
tmpng="$(mktemp -d)"
WTX_ROOT="$tmpng" wtx_update_toolkit; rc=$?
assert_eq "toolkit non-git: rc 0" 0 "$rc"
assert_eq "toolkit non-git: status skipped" "skipped" "$_WTX_UPDATE_TOOLKIT_STATUS"
assert_contains "toolkit non-git: msg mentions git checkout" "not a git checkout" "$_WTX_UPDATE_TOOLKIT_MSG"
rm -rf "$tmpng"

# -- Case 4: dirty checkout → skipped (never clobbers local changes)
tmpd="$(mktemp -d)"
( cd "$tmpd" && _git init -q && echo a > f && _git add f && _git commit -qm init && echo dirty >> f )
WTX_ROOT="$tmpd" wtx_update_toolkit; rc=$?
assert_eq "toolkit dirty: rc 0" 0 "$rc"
assert_eq "toolkit dirty: status skipped" "skipped" "$_WTX_UPDATE_TOOLKIT_STATUS"
assert_contains "toolkit dirty: msg mentions local changes" "local changes" "$_WTX_UPDATE_TOOLKIT_MSG"
rm -rf "$tmpd"

# -- Case 5: clean clone, no upstream commits → up-to-date; then a pushed commit → available + updated
origin="$(mktemp -d)/origin"
clone="$(mktemp -d)/clone"
mkdir -p "$origin"
( cd "$origin" && _git init -q && printf '0.1.0\n' > VERSION && echo x > a && _git add . && _git commit -qm init )
_git clone -q "$origin" "$clone"

WTX_ROOT="$clone" wtx_update_toolkit --dry-run; rc=$?
assert_eq "toolkit dryrun current: rc 0" 0 "$rc"
assert_eq "toolkit dryrun current: up-to-date" "up-to-date" "$_WTX_UPDATE_TOOLKIT_STATUS"

# Advance origin (bump VERSION) so the clone is one commit behind.
( cd "$origin" && printf '0.2.0\n' > VERSION && _git add . && _git commit -qm bump )

WTX_ROOT="$clone" wtx_update_toolkit --dry-run; rc=$?
assert_eq "toolkit dryrun behind: status available" "available" "$_WTX_UPDATE_TOOLKIT_STATUS"
assert_contains "toolkit dryrun behind: counts commit" "1 commit" "$_WTX_UPDATE_TOOLKIT_MSG"

WTX_ROOT="$clone" wtx_update_toolkit; rc=$?
assert_eq "toolkit pull: rc 0" 0 "$rc"
assert_eq "toolkit pull: status updated" "updated" "$_WTX_UPDATE_TOOLKIT_STATUS"
assert_eq "toolkit pull: version before" "0.1.0" "$_WTX_UPDATE_VER_BEFORE"
assert_eq "toolkit pull: version after" "0.2.0" "$_WTX_UPDATE_VER_AFTER"

# Re-running now is a no-op.
WTX_ROOT="$clone" wtx_update_toolkit; rc=$?
assert_eq "toolkit pull again: up-to-date" "up-to-date" "$_WTX_UPDATE_TOOLKIT_STATUS"
rm -rf "$(dirname "$origin")" "$(dirname "$clone")"

# -- Case 6: hooks — none installed → status none
wsnone="$(mktemp -d)"
WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$wsnone" wtx_update_hooks; rc=$?
assert_eq "hooks none: rc 0" 0 "$rc"
assert_eq "hooks none: status none" "none" "$_WTX_UPDATE_HOOKS_STATUS"
assert_eq "hooks none: count 0" 0 "$_WTX_UPDATE_HOOKS_COUNT"
rm -rf "$wsnone"

# -- Case 7: hooks — pre-installed → refreshed byte-for-byte from the checkout
wshook="$(mktemp -d)"
mkdir -p "$wshook/.claude/hooks"
# Seed a stale copy of one hook so we can prove it gets overwritten.
printf 'STALE\n' > "$wshook/.claude/hooks/worktree-create.sh"
printf 'STALE\n' > "$wshook/.claude/hooks/worktree-detect.sh"
printf 'STALE\n' > "$wshook/.claude/hooks/worktree-remove.sh"
WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$wshook" wtx_update_hooks; rc=$?
assert_eq "hooks refresh: rc 0" 0 "$rc"
assert_eq "hooks refresh: status refreshed" "refreshed" "$_WTX_UPDATE_HOOKS_STATUS"
assert_eq "hooks refresh: count 3" 3 "$_WTX_UPDATE_HOOKS_COUNT"
if cmp -s "$REPO_ROOT/hooks/worktree-create.sh" "$wshook/.claude/hooks/worktree-create.sh"; then
    TOTAL=$((TOTAL+1)); printf 'PASS  hooks refresh: create hook overwritten with checkout copy\n'
else
    FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  hooks refresh: create hook overwritten with checkout copy\n'
fi
rm -rf "$wshook"

# -- Case 8: schema drift — no toml / up-to-date / missing key
wssch="$(mktemp -d)"
WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$wssch" wtx_update_check_schema
assert_eq "schema none: status none" "none" "$_WTX_UPDATE_TOML_STATUS"

# A toml that contains every example token → up-to-date.
cp "$REPO_ROOT/wtx.example.toml" "$wssch/wtx.toml"
WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$wssch" wtx_update_check_schema
assert_eq "schema full: status up-to-date" "up-to-date" "$_WTX_UPDATE_TOML_STATUS"

# A minimal toml missing most sections → drift, message names a missing token.
printf '[forge]\ntype = "github"\norg = "x"\n' > "$wssch/wtx.toml"
WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$wssch" wtx_update_check_schema
assert_eq "schema partial: status drift" "drift" "$_WTX_UPDATE_TOML_STATUS"
assert_contains "schema partial: names install merge" "wtx install" "$_WTX_UPDATE_TOML_MSG"
rm -rf "$wssch"

# -- Case 9: wtx_update_run --check on a non-git root prints a report and exits 0 under set -u
out="$(WTX_ROOT="$(mktemp -d)" WORKSPACE_ROOT="$(mktemp -d)" bash -u -c '
    source "'"$LIB"'"
    wtx_update_run --check
' 2>&1)"; rc=$?
assert_eq "run --check non-git: rc 0" 0 "$rc"
assert_contains "run --check non-git: prints report header" "wtx update" "$out"
assert_contains "run --check non-git: toolkit skipped line" "skipped" "$out"

# -- Case 10: wtx_update_run rejects unknown options
out="$(WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$(mktemp -d)" bash -c '
    source "'"$LIB"'"
    wtx_update_run --bogus
' 2>&1)"; rc=$?
assert_eq "run unknown opt: rc 2" 2 "$rc"
assert_contains "run unknown opt: error msg" "unknown option" "$out"

# -- Case 11: --toolkit-only skips the per-project layer
out="$(WTX_ROOT="$(mktemp -d)" WORKSPACE_ROOT="$(mktemp -d)" bash -u -c '
    source "'"$LIB"'"
    wtx_update_run --toolkit-only --check
' 2>&1)"; rc=$?
assert_eq "run toolkit-only: rc 0" 0 "$rc"
case "$out" in
    *hooks:*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  run toolkit-only: omits hooks line\n' ;;
    *)        TOTAL=$((TOTAL+1)); printf 'PASS  run toolkit-only: omits hooks line\n' ;;
esac

# -- Case 12: syntax
bash -n "$LIB"; assert_eq "lib syntax: bash -n" 0 "$?"

printf '\n%d/%d passed\n' "$((TOTAL - FAILS))" "$TOTAL"
[[ $FAILS -eq 0 ]]
