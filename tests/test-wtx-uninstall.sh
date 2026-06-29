#!/bin/bash
# tests/test-wtx-uninstall.sh — assertions for lib/wtx-uninstall.sh.
# Run: bash tests/test-wtx-uninstall.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LIB="$REPO_ROOT/lib/wtx-uninstall.sh"

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

source "$LIB"
source "$LIB"
assert_eq "lib guard: set" 1 "${_WTX_UNINSTALL_LIB_LOADED:-0}"
command -v wtx_uninstall_run >/dev/null 2>&1
assert_eq "lib defines wtx_uninstall_run" 0 "$?"

# -- Case: managed-home detection
WTX_ROOT="$HOME/.local/share/wtx" _wtx_uninstall_is_managed_home; assert_eq "managed: default share dir" 0 "$?"
( export XDG_DATA_HOME="/data"; WTX_ROOT="/data/wtx" _wtx_uninstall_is_managed_home ); assert_eq "managed: XDG override" 0 "$?"
WTX_ROOT="/Users/me/Projects/wtx" _wtx_uninstall_is_managed_home; assert_eq "managed: dev checkout is NOT managed" 1 "$?"

# -- Case: prefix resolution falls back to ~/.local when no wtx on PATH
out="$(PATH="/usr/bin:/bin" bash -c 'source "'"$LIB"'"; _wtx_uninstall_resolve_prefix')"
assert_eq "prefix fallback" "$HOME/.local" "$out"

# -- Case: unknown option → rc 2
out="$(WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$(mktemp -d)" bash -c 'source "'"$LIB"'"; wtx_uninstall_run --bogus' 2>&1)"; rc=$?
assert_eq "unknown opt: rc 2" 2 "$rc"
assert_contains "unknown opt: message" "unknown option" "$out"

# -- Case: dry-run removes nothing (symlink + hooks survive)
pfx="$(mktemp -d)/pfx"; ws="$(mktemp -d)/ws"
mkdir -p "$pfx/bin" "$ws/.claude/hooks"
ln -s "$REPO_ROOT/bin/wtx" "$pfx/bin/wtx"
for h in worktree-create.sh worktree-detect.sh worktree-remove.sh; do printf 'x\n' > "$ws/.claude/hooks/$h"; done
out="$(WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$ws" wtx_uninstall_run --dry-run --prefix "$pfx" 2>&1)"; rc=$?
assert_eq "dry-run: rc 0" 0 "$rc"
assert_contains "dry-run: previews symlink removal" "[dry-run] would remove symlink" "$out"
assert_contains "dry-run: previews hook removal" "would remove $ws/.claude/hooks/worktree-create.sh" "$out"
[[ -L "$pfx/bin/wtx" ]]; assert_eq "dry-run: symlink intact" 0 "$?"
[[ -f "$ws/.claude/hooks/worktree-detect.sh" ]]; assert_eq "dry-run: hooks intact" 0 "$?"
rm -rf "$(dirname "$pfx")" "$(dirname "$ws")"

# -- Case: --all actually removes symlink + hooks, leaves non-managed checkout + wtx.toml
pfx="$(mktemp -d)/pfx"; ws="$(mktemp -d)/ws"
mkdir -p "$pfx/bin" "$ws/.claude/hooks"
ln -s "$REPO_ROOT/bin/wtx" "$pfx/bin/wtx"
for h in worktree-create.sh worktree-detect.sh worktree-remove.sh; do printf 'x\n' > "$ws/.claude/hooks/$h"; done
printf '[forge]\n' > "$ws/wtx.toml"
out="$(WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$ws" wtx_uninstall_run --all --prefix "$pfx" 2>&1)"; rc=$?
assert_eq "all: rc 0" 0 "$rc"
[[ ! -e "$pfx/bin/wtx" ]]; assert_eq "all: symlink removed" 0 "$?"
[[ ! -e "$ws/.claude/hooks/worktree-create.sh" ]]; assert_eq "all: hooks removed" 0 "$?"
[[ -f "$ws/wtx.toml" ]]; assert_eq "all: wtx.toml preserved" 0 "$?"
assert_contains "all: reports config kept" "wtx.toml left in place" "$out"
assert_contains "all: dev checkout left in place" "left in place" "$out"
[[ -f "$REPO_ROOT/bin/wtx" ]]; assert_eq "all: real checkout untouched" 0 "$?"
rm -rf "$(dirname "$pfx")" "$(dirname "$ws")"

# -- Case: managed home + dry-run announces toolkit removal (uses a symlinked fake home)
parent="$(mktemp -d)"
ln -s "$REPO_ROOT" "$parent/wtx"
out="$(XDG_DATA_HOME="$parent" WTX_ROOT="$parent/wtx" WORKSPACE_ROOT="$(mktemp -d)" \
        bash -c 'source "'"$LIB"'"; wtx_uninstall_run --dry-run --prefix "'"$(mktemp -d)"'"' 2>&1)"
assert_contains "managed dry-run: announces toolkit removal" "would remove toolkit checkout $parent/wtx" "$out"
rm -rf "$parent"

# -- Case: syntax
bash -n "$LIB"; assert_eq "lib syntax: bash -n" 0 "$?"

printf '\n%d/%d passed\n' "$((TOTAL - FAILS))" "$TOTAL"
[[ $FAILS -eq 0 ]]
