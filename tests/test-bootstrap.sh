#!/bin/bash
# tests/test-bootstrap.sh — assertions for the curl|bash bootstrap entry point.
# Run: bash tests/test-bootstrap.sh
#
# These drive bootstrap.sh in --dry-run (no clone/install) plus the guard paths,
# so nothing touches the network or the real install.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BOOT="$REPO_ROOT/bootstrap.sh"

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

# -- Case 1: syntax
bash -n "$BOOT"; assert_eq "syntax: bash -n" 0 "$?"

# -- Case 2: --help exits 0 and prints usage
out="$(bash "$BOOT" --help 2>&1)"; rc=$?
assert_eq "help: rc 0" 0 "$rc"
assert_contains "help: shows usage banner" "wtx bootstrap" "$out"
assert_contains "help: documents --no-project" "--no-project" "$out"

# -- Case 3: unknown flag exits 2
out="$(bash "$BOOT" --nope 2>&1)"; rc=$?
assert_eq "unknown flag: rc 2" 2 "$rc"
assert_contains "unknown flag: error msg" "unknown option" "$out"

# -- Case 4: dry-run on a fresh home previews clone+install, makes no changes
home="$(mktemp -d)/wtx"
out="$(bash "$BOOT" --dry-run --no-project --home "$home" --repo "file://$REPO_ROOT" 2>&1)"; rc=$?
assert_eq "dry-run fresh: rc 0" 0 "$rc"
assert_contains "dry-run fresh: previews git clone" "[dry-run] git clone" "$out"
assert_contains "dry-run fresh: previews install.sh" "would run: bash $home/install.sh" "$out"
assert_contains "dry-run fresh: honors --no-project" "skipping per-project setup" "$out"
if [[ -e "$home" ]]; then
    FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  dry-run fresh: no home created\n'
else
    TOTAL=$((TOTAL+1)); printf 'PASS  dry-run fresh: no home created\n'
fi
rm -rf "$(dirname "$home")"

# -- Case 5: dry-run reflects env/flag overrides in the banner
out="$(bash "$BOOT" --dry-run --no-project --home "$(mktemp -d)/h" \
        --repo "file://$REPO_ROOT" --ref dev --prefix /tmp/wtxpfx 2>&1)"
assert_contains "overrides: ref shown" "ref    : dev" "$out"
assert_contains "overrides: prefix shown" "prefix : /tmp/wtxpfx" "$out"

# -- Case 6: existing non-wtx directory at home is refused (no clobber)
busy="$(mktemp -d)"
touch "$busy/some-unrelated-file"
out="$(bash "$BOOT" --dry-run --no-project --home "$busy" --repo "file://$REPO_ROOT" 2>&1)"; rc=$?
assert_eq "occupied home: rc 1" 1 "$rc"
assert_contains "occupied home: refuses to overwrite" "refusing to overwrite" "$out"
[[ -f "$busy/some-unrelated-file" ]]; assert_eq "occupied home: leaves files intact" 0 "$?"
rm -rf "$busy"

# -- Case 7: an existing wtx clone at home updates instead of cloning
existing="$(mktemp -d)/wtx"
git -c init.defaultBranch=main clone -q "file://$REPO_ROOT" "$existing"
out="$(bash "$BOOT" --dry-run --no-project --home "$existing" 2>&1)"; rc=$?
assert_eq "existing clone: rc 0" 0 "$rc"
assert_contains "existing clone: takes update path" "Updating existing toolkit" "$out"
rm -rf "$(dirname "$existing")"

printf '\n%d/%d passed\n' "$((TOTAL - FAILS))" "$TOTAL"
[[ $FAILS -eq 0 ]]
