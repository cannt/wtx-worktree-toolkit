#!/bin/bash
# tests/test-wtx-install.sh — assertions for install wizard primitives.
# Run: bash tests/test-wtx-install.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LIB="$REPO_ROOT/lib/wtx-install.sh"
WIZARD="$REPO_ROOT/scripts/worktree-install.sh"

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

# -- Case 1: lib can be sourced repeatedly and defines installer primitives
source "$LIB"
source "$LIB"
assert_eq "lib guard: set" 1 "${_WTX_INSTALL_LIB_LOADED:-0}"
for fn in _wtx_toml_escape _wtx_csv_to_toml_array wtx_install_discover_plugins wtx_install_write_or_dryrun; do
    if command -v "$fn" >/dev/null 2>&1; then
        TOTAL=$((TOTAL + 1)); printf 'PASS  lib defines %s\n' "$fn"
    else
        FAILS=$((FAILS + 1)); TOTAL=$((TOTAL + 1))
        printf 'FAIL  lib defines %s\n' "$fn"
    fi
done
out=$(bash -c "source \"$LIB\"; _wtx_toml_escape() { printf sentinel; }; source \"$LIB\"; _wtx_toml_escape ignored" 2>&1); rc=$?
assert_eq "lib guard: repeat source does not redefine" "sentinel" "$out"
assert_eq "lib guard: repeat source rc" 0 "$rc"
set -f
out="$(_wtx_csv_to_toml_array "a,*,c")"
case "$-" in
    *f*) noglob_state=1 ;;
    *) noglob_state=0 ;;
esac
set +f
assert_eq "csv helper: preserves existing noglob" 1 "$noglob_state"
assert_eq "csv helper: preserves output with noglob" '["a", "*", "c"]' "$out"

# -- Case 2: write chokepoint executes command and propagates exit code
tmpdir="$(mktemp -d)"
marker="$tmpdir/marker"
WTX_INSTALL_DRY_RUN=0
out=$(wtx_install_write_or_dryrun "write marker" touch "$marker" 2>&1); rc=$?
assert_eq "write: exit 0" 0 "$rc"
assert_eq "write: no dry-run output" "" "$out"
[[ -f "$marker" ]]; assert_ok "write: command executed" $?
out=$(wtx_install_write_or_dryrun "fail marker" bash -c 'exit 7' 2>&1); rc=$?
assert_eq "write: propagates failure" 7 "$rc"

# -- Case 3: dry-run prints action and skips command
rm -f "$marker"
WTX_INSTALL_DRY_RUN=1
out=$(wtx_install_write_or_dryrun "write marker" touch "$marker" 2>&1); rc=$?
assert_eq "dry-run helper: exit 0" 0 "$rc"
assert_eq "dry-run helper: announces action" "[dry-run] write marker" "$out"
[[ ! -e "$marker" ]]; assert_ok "dry-run helper: skips command" $?

# -- Case 4: plugin discovery uses desc metadata and filename fallback
plugin_root="$tmpdir/wtx"
mkdir -p "$plugin_root/plugins"
cat > "$plugin_root/plugins/alpha.sh" <<'EOF'
#!/bin/bash
# wtx-plugin-desc: Alpha plugin
EOF
cat > "$plugin_root/plugins/beta-plugin.sh" <<'EOF'
#!/bin/bash
echo beta
EOF
WTX_ROOT="$plugin_root"
out="$(wtx_install_discover_plugins)"
expected="$(printf 'alpha.sh\tAlpha plugin\nbeta-plugin.sh\tbeta-plugin')"
assert_eq "plugins: discover metadata + fallback" "$expected" "$out"
rm -rf "$tmpdir"

# -- Case 5: wizard rejects unknown options before git/gum work
out=$(bash "$WIZARD" --bogus 2>&1 >/dev/null); rc=$?
assert_eq "wizard args: unknown exits 2" 2 "$rc"
assert_contains "wizard args: stderr prefix" "wtx install:" "$out"

# -- Case 6: wizard outside git fails after parsing dry-run
tmpdir="$(mktemp -d)"
stdout_file="$tmpdir/stdout"
stderr_file="$tmpdir/stderr"
trace_file="$tmpdir/git-trace"
( cd "$tmpdir" && GIT_TRACE="$trace_file" env -u WORKSPACE_ROOT WTX_ROOT="$REPO_ROOT" bash "$WIZARD" --dry-run >"$stdout_file" 2>"$stderr_file" ); rc=$?
stdout="$(cat "$stdout_file")"
stderr="$(cat "$stderr_file")"
assert_eq "wizard git: outside repo exits 1" 1 "$rc"
assert_contains "wizard git: clear error" "wtx install: not in a git repository" "$stderr"
assert_eq "wizard git: no stdout before git check" "" "$stdout"
trace="$(cat "$trace_file" 2>/dev/null || true)"
case "$trace" in
    *"--git-common-dir"*|*"--show-toplevel"*) preflight_order=0 ;;
    *) preflight_order=1 ;;
esac
assert_eq "wizard git: no workspace resolution before git gate" 1 "$preflight_order"
leftovers=$(find "$tmpdir" -name '.wtx-install-tmp.*' -print)
assert_eq "wizard git: no temp before git check" "" "$leftovers"
rm -rf "$tmpdir"

# -- Case 7: wizard no-gum notice, temp cleanup, and dry-run path
tmpdir="$(mktemp -d)"
( cd "$tmpdir" && git init -q )
stdout_file="$tmpdir/stdout"
stderr_file="$tmpdir/stderr"
( cd "$tmpdir" && PATH="/usr/bin:/bin" WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$tmpdir" bash "$WIZARD" --dry-run >"$stdout_file" 2>"$stderr_file" ); rc=$?
stdout="$(cat "$stdout_file")"
stderr="$(cat "$stderr_file")"
assert_eq "wizard preflight: exit 0" 0 "$rc"
assert_eq "wizard preflight: exact no-gum notice" "note: gum not found — using plain prompts (install with: brew install gum)" "$stdout"
assert_eq "wizard preflight: no stderr" "" "$stderr"
leftovers=$(find "$tmpdir" -name '.wtx-install-tmp.*' -print)
assert_eq "wizard preflight: temp cleaned" "" "$leftovers"
rm -rf "$tmpdir"

# -- Case 8: wizard gum-available path suppresses fallback notice
tmpdir="$(mktemp -d)"
bindir="$tmpdir/bin"
mkdir -p "$bindir"
( cd "$tmpdir" && git init -q )
cat > "$bindir/gum" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$bindir/gum"
out=$(cd "$tmpdir" && PATH="$bindir:/usr/bin:/bin" WTX_ROOT="$REPO_ROOT" WORKSPACE_ROOT="$tmpdir" bash "$WIZARD" --dry-run 2>&1); rc=$?
assert_eq "wizard gum: exit 0 when available" 0 "$rc"
assert_eq "wizard gum: no fallback notice" "" "$out"
rm -rf "$tmpdir"

# -- Case 9: direct symlink invocation resolves WTX_ROOT and WORKSPACE_ROOT
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/far/away" "$tmpdir/repo"
( cd "$tmpdir/repo" && git init -q )
ln -s "$WIZARD" "$tmpdir/far/away/worktree-install.sh"
out=$(cd "$tmpdir/repo" && env -u WTX_ROOT -u WORKSPACE_ROOT PATH="/usr/bin:/bin" bash "$tmpdir/far/away/worktree-install.sh" --dry-run 2>&1); rc=$?
assert_eq "wizard symlink: exit 0" 0 "$rc"
assert_contains "wizard symlink: sourced real lib" "note: gum not found" "$out"
leftovers=$(find "$tmpdir/repo" -name '.wtx-install-tmp.*' -print)
assert_eq "wizard symlink: temp cleaned" "" "$leftovers"
rm -rf "$tmpdir"

# -- Case 10: direct invocation supports installed layout with lib/ beside script
tmpdir="$(mktemp -d)"
install_root="$tmpdir/install-root"
mkdir -p "$install_root/lib" "$tmpdir/repo"
cp "$WIZARD" "$install_root/worktree-install.sh"
cp "$LIB" "$install_root/lib/wtx-install.sh"
( cd "$tmpdir/repo" && git init -q )
out=$(cd "$tmpdir/repo" && env -u WTX_ROOT -u WORKSPACE_ROOT PATH="/usr/bin:/bin" bash "$install_root/worktree-install.sh" --dry-run 2>&1); rc=$?
assert_eq "wizard direct layout: exit 0" 0 "$rc"
assert_contains "wizard direct layout: uses adjacent lib" "note: gum not found" "$out"
leftovers=$(find "$tmpdir/repo" -name '.wtx-install-tmp.*' -print)
assert_eq "wizard direct layout: temp cleaned" "" "$leftovers"
rm -rf "$tmpdir"

# -- Case 11: wizard syntax
bash -n "$WIZARD"; rc=$?
assert_eq "wizard syntax: bash -n" 0 "$rc"

echo
if [[ $FAILS -eq 0 ]]; then
    printf '%d/%d passed\n' "$TOTAL" "$TOTAL"
    exit 0
else
    printf '%d/%d passed, %d failed\n' "$((TOTAL - FAILS))" "$TOTAL" "$FAILS"
    exit 1
fi
