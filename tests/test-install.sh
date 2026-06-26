#!/bin/bash
# tests/test-install.sh — assertions for install.sh (symlink/prefix installer).
# Run: bash tests/test-install.sh
#
# Hermetic: every case installs into a scratch --prefix under a single mktemp
# root that is removed on exit. Nothing touches $HOME/.local. The --gradle path
# is intentionally NOT exercised here because its destination (~/.gradle/init.d)
# is not configurable and the test must not write into the real home dir.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL="$REPO_ROOT/install.sh"

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

# Assert a boolean condition already evaluated by the caller ($1=name, $2=0|1).
assert_ok() {
    local name="$1" rc="$2"
    TOTAL=$((TOTAL + 1))
    if [[ "$rc" -eq 0 ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
    fi
}

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# -- Case 1: --dry-run announces the symlink and changes nothing
PREFIX="$TMPROOT/prefix"
out=$(bash "$INSTALL" --prefix "$PREFIX" --dry-run 2>&1); rc=$?
assert_eq       "dry-run: exit 0" 0 "$rc"
assert_contains "dry-run: announces symlink" "would symlink" "$out"
[[ ! -e "$PREFIX" ]]; assert_ok "dry-run: creates nothing" $?

# -- Case 2: real install creates a working symlink
out=$(bash "$INSTALL" --prefix "$PREFIX" 2>&1); rc=$?
assert_eq "install: exit 0" 0 "$rc"
LINK="$PREFIX/bin/wtx"
assert_eq "install: symlink points at repo bin/wtx" "$REPO_ROOT/bin/wtx" "$(readlink "$LINK" 2>/dev/null)"
# The dispatcher must resolve WTX_ROOT correctly *through* the symlink.
ver_direct=$(bash "$REPO_ROOT/bin/wtx" version 2>/dev/null)
ver_link=$(bash "$LINK" version 2>/dev/null)
assert_eq "install: version via symlink matches direct" "$ver_direct" "$ver_link"

# -- Case 3: re-running is idempotent
out=$(bash "$INSTALL" --prefix "$PREFIX" 2>&1); rc=$?
assert_eq       "reinstall: exit 0" 0 "$rc"
assert_contains "reinstall: reports already linked" "already linked" "$out"

# -- Case 4: refuses to clobber a non-symlink file without --force
P2="$TMPROOT/p2"
mkdir -p "$P2/bin"
printf 'i am a real file\n' > "$P2/bin/wtx"
stderr=$(bash "$INSTALL" --prefix "$P2" 2>&1 >/dev/null); rc=$?
assert_eq       "clobber: exit 1 without --force" 1 "$rc"
assert_contains "clobber: error suggests --force" "use --force" "$stderr"
assert_eq       "clobber: original file left intact" "i am a real file" "$(cat "$P2/bin/wtx")"

# -- Case 5: --force overwrites the file with the symlink
out=$(bash "$INSTALL" --prefix "$P2" --force 2>&1); rc=$?
assert_eq "force: exit 0" 0 "$rc"
[[ -L "$P2/bin/wtx" ]]; assert_ok "force: target is now a symlink" $?
assert_eq "force: symlink points at repo bin/wtx" "$REPO_ROOT/bin/wtx" "$(readlink "$P2/bin/wtx" 2>/dev/null)"

# -- Case 6: --hooks copies executable hooks into $PWD/.claude/hooks/
REPO="$TMPROOT/repo"
mkdir -p "$REPO"
( cd "$REPO" && git init -q )
( cd "$REPO" && bash "$INSTALL" --prefix "$P2" --hooks >/dev/null 2>&1 )
[[ -x "$REPO/.claude/hooks/worktree-create.sh" ]]; assert_ok "hooks: worktree-create.sh installed +x" $?
[[ -x "$REPO/.claude/hooks/worktree-detect.sh" ]]; assert_ok "hooks: worktree-detect.sh installed +x" $?
[[ -x "$REPO/.claude/hooks/worktree-remove.sh" ]]; assert_ok "hooks: worktree-remove.sh installed +x" $?

# -- Case 7: --uninstall removes the symlink and is idempotent
out=$(bash "$INSTALL" --prefix "$PREFIX" --uninstall 2>&1); rc=$?
assert_eq "uninstall: exit 0" 0 "$rc"
[[ ! -e "$PREFIX/bin/wtx" ]]; assert_ok "uninstall: symlink removed" $?
out=$(bash "$INSTALL" --prefix "$PREFIX" --uninstall 2>&1); rc=$?
assert_contains "uninstall: idempotent (nothing to remove)" "nothing to remove" "$out"

# -- Case 8: argument validation
out=$(bash "$INSTALL" --prefix 2>&1); rc=$?
assert_eq "args: --prefix without value exits 2" 2 "$rc"
out=$(bash "$INSTALL" --bogus 2>&1); rc=$?
assert_eq "args: unknown option exits 2" 2 "$rc"
bash "$INSTALL" --help >/dev/null 2>&1; rc=$?
assert_eq "args: --help exits 0" 0 "$rc"

# -- Case 9: refuses to run from an incomplete checkout (no bin/wtx alongside)
FAKE="$TMPROOT/fake"
mkdir -p "$FAKE"
cp "$INSTALL" "$FAKE/install.sh"
stderr=$(bash "$FAKE/install.sh" --prefix "$TMPROOT/x" 2>&1 >/dev/null); rc=$?
assert_eq       "guard: incomplete checkout exits 1" 1 "$rc"
assert_contains "guard: explains missing bin/wtx" "cannot find bin/wtx" "$stderr"

# -- Summary
echo
if [[ $FAILS -eq 0 ]]; then
    printf '%d/%d passed\n' "$TOTAL" "$TOTAL"
    exit 0
else
    printf '%d/%d passed, %d failed\n' "$((TOTAL - FAILS))" "$TOTAL" "$FAILS"
    exit 1
fi
