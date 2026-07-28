#!/bin/bash
# tests/test-wtx-clean.sh — assertions for lib/wtx-clean.sh and the
# plugins/jetbrains-cleanup.sh scanner.
#
# Everything runs against a throwaway HOME and workspace built under a temp
# dir, so the suite never touches real caches. Run: bash tests/test-wtx-clean.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CLEAN_LIB="$REPO_ROOT/lib/wtx-clean.sh"
JB_SCANNER="$REPO_ROOT/plugins/jetbrains-cleanup.sh"

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

assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      expected NOT to contain: %q\n' "$needle"
    fi
}

assert_exists() {
    local name="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -e "$path" ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s (missing: %s)\n' "$name" "$path"
    fi
}

assert_gone() {
    local name="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [[ ! -e "$path" ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s (still present: %s)\n' "$name" "$path"
    fi
}

# --- Sandbox ------------------------------------------------------------------

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/wtx-clean-test.XXXXXX")" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT

REAL_HOME="$HOME"
export HOME="$SANDBOX/home"
mkdir -p "$HOME"

export WORKSPACE_ROOT="$HOME/workspace"
mkdir -p "$WORKSPACE_ROOT/live-worktree"        # a worktree that still exists
# …and "gone-worktree" deliberately never created.

CACHE="$HOME/Library/Caches/fakeide"
mkdir -p "$CACHE/orphan-cache" "$CACHE/live-cache"
echo "payload" > "$CACHE/orphan-cache/data"
echo "payload" > "$CACHE/live-cache/data"

# shellcheck source=../lib/wtx-clean.sh disable=SC1091
source "$CLEAN_LIB"

# --- Case 1: the safety envelope ---------------------------------------------

_wtx_clean_target_ok "$CACHE/orphan-cache" && ok=yes || ok=no
assert_eq "envelope: accepts a deep cache path under HOME" "yes" "$ok"

_wtx_clean_target_ok "relative/path" && ok=yes || ok=no
assert_eq "envelope: rejects relative path" "no" "$ok"

_wtx_clean_target_ok "$HOME" && ok=yes || ok=no
assert_eq "envelope: rejects HOME itself" "no" "$ok"

mkdir -p "$HOME/Shallow"
_wtx_clean_target_ok "$HOME/Shallow" && ok=yes || ok=no
assert_eq "envelope: rejects shallow path under HOME" "no" "$ok"

_wtx_clean_target_ok "$WORKSPACE_ROOT/live-worktree" && ok=yes || ok=no
assert_eq "envelope: rejects paths inside the workspace" "no" "$ok"

_wtx_clean_target_ok "$CACHE/../../../etc" && ok=yes || ok=no
assert_eq "envelope: rejects .. traversal" "no" "$ok"

_wtx_clean_target_ok "$CACHE/does-not-exist" && ok=yes || ok=no
assert_eq "envelope: rejects a nonexistent target" "no" "$ok"

_wtx_clean_target_ok "$REAL_HOME/../../tmp/x" && ok=yes || ok=no
assert_eq "envelope: rejects paths outside HOME" "no" "$ok"

# --- Case 2: the orphan rule --------------------------------------------------

_wtx_clean_refs_orphaned "$WORKSPACE_ROOT/gone-worktree" && ok=yes || ok=no
assert_eq "orphan rule: all references missing -> orphan" "yes" "$ok"

_wtx_clean_refs_orphaned "$WORKSPACE_ROOT/live-worktree" && ok=yes || ok=no
assert_eq "orphan rule: a live reference -> not orphan" "no" "$ok"

_wtx_clean_refs_orphaned "$WORKSPACE_ROOT/gone-worktree,$WORKSPACE_ROOT/live-worktree" && ok=yes || ok=no
assert_eq "orphan rule: any live reference wins -> not orphan" "no" "$ok"

_wtx_clean_refs_orphaned "" && ok=yes || ok=no
assert_eq "orphan rule: no evidence -> not orphan" "no" "$ok"

_wtx_clean_refs_orphaned "$WORKSPACE_ROOT/gone-worktree,$WORKSPACE_ROOT/gone-two" && ok=yes || ok=no
assert_eq "orphan rule: several missing references -> orphan" "yes" "$ok"

# --- Case 3: end-to-end with a stub scanner -----------------------------------

STUB="$SANDBOX/stub-cleanup.sh"
cat > "$STUB" <<EOF
#!/bin/bash
printf 'delete\t%s\t%s\t%s\n' "$CACHE/orphan-cache" "orphan-cache" "$WORKSPACE_ROOT/gone-worktree"
printf 'delete\t%s\t%s\t%s\n' "$CACHE/live-cache"   "live-cache"   "$WORKSPACE_ROOT/live-worktree"
printf 'note\t-\ta warning line\n'
EOF

# 3a: dry run reports the orphan but deletes nothing.
out="$(wtx_clean_run --dry-run --scanner "$STUB" 2>&1)"
assert_contains "dry-run: reports the orphan"        "orphan-cache" "$out"
assert_contains "dry-run: says nothing was deleted"  "Dry run"      "$out"
assert_contains "dry-run: surfaces scanner notes"    "a warning line" "$out"
assert_exists   "dry-run: orphan still on disk"      "$CACHE/orphan-cache"
assert_exists   "dry-run: live cache still on disk"  "$CACHE/live-cache"

# 3b: verbose names what it kept and why.
out="$(wtx_clean_run --dry-run --verbose --scanner "$STUB" 2>&1)"
assert_contains "verbose: lists the kept cache" "keep" "$out"
assert_contains "verbose: names the live worktree" "live-worktree" "$out"

# 3c: the real thing removes only the orphan.
out="$(wtx_clean_run --yes --scanner "$STUB" 2>&1)"
assert_gone   "clean: orphan removed"          "$CACHE/orphan-cache"
assert_exists "clean: live cache untouched"    "$CACHE/live-cache"
assert_contains "clean: reports what it did"   "Removed 1 item" "$out"

# 3d: a second run finds nothing left to do.
out="$(wtx_clean_run --yes --scanner "$STUB" 2>&1)"
assert_contains "clean: idempotent" "Nothing to reclaim" "$out"

# --- Case 4: a misbehaving scanner cannot escape the envelope -----------------

mkdir -p "$CACHE/keep-me"
BAD="$SANDBOX/bad-cleanup.sh"
cat > "$BAD" <<EOF
#!/bin/bash
printf 'delete\t%s\t%s\t%s\n' "$HOME"                       "home-itself"  "$WORKSPACE_ROOT/gone-worktree"
printf 'delete\t%s\t%s\t%s\n' "$WORKSPACE_ROOT/live-worktree" "in-workspace" "$WORKSPACE_ROOT/gone-worktree"
printf 'delete\t%s\t%s\t%s\n' "../relative"                 "relative"     "$WORKSPACE_ROOT/gone-worktree"
printf 'delete\t%s\t%s\t%s\n' "$CACHE/keep-me"              "no-evidence"  ""
EOF

out="$(wtx_clean_run --yes --scanner "$BAD" 2>&1)"
assert_exists "envelope e2e: HOME survives"                  "$HOME"
assert_exists "envelope e2e: workspace content survives"     "$WORKSPACE_ROOT/live-worktree"
assert_exists "envelope e2e: no-evidence target survives"    "$CACHE/keep-me"
assert_contains "envelope e2e: nothing reclaimed" "Nothing to reclaim" "$out"

# --- Case 5: the JetBrains scanner -------------------------------------------

AS="$HOME/Library/Caches/Google/AndroidStudio2026.1.3"
mkdir -p "$AS/projects/gone-worktree.abc123" \
         "$AS/projects/live-worktree.def456" \
         "$AS/vcs-log/gone-wo_abc123_99887766" \
         "$AS/compile-server/gone-worktree_5f5f5f" \
         "$AS/compiler/gone-worktree.abc123"

# Cache metadata names the project by absolute path — that is the evidence.
echo "project at $WORKSPACE_ROOT/gone-worktree indexed" > "$AS/projects/gone-worktree.abc123/cache-state.xml"
echo "project at $WORKSPACE_ROOT/live-worktree indexed" > "$AS/projects/live-worktree.def456/cache-state.xml"
echo "vcs data" > "$AS/vcs-log/gone-wo_abc123_99887766/data"
echo "jps data" > "$AS/compile-server/gone-worktree_5f5f5f/data"
echo "cmp data" > "$AS/compiler/gone-worktree.abc123/data"

ANALYZER="$HOME/Library/Caches/JetBrains/analyzer/workspaces"
mkdir -p "$ANALYZER/aaa111/rocks" "$ANALYZER/bbb222/rocks"
# The model file may not name the project; the RocksDB index does. Split the
# evidence across both to prove the scanner reads the whole workspace.
echo "no paths here" > "$ANALYZER/aaa111/workspace-model.cache"
echo "indexed $WORKSPACE_ROOT/gone-worktree" > "$ANALYZER/aaa111/rocks/000001.sst"
echo "no paths here" > "$ANALYZER/bbb222/workspace-model.cache"
echo "indexed $WORKSPACE_ROOT/live-worktree" > "$ANALYZER/bbb222/rocks/000001.sst"

records="$(WORKSPACE_ROOT="$WORKSPACE_ROOT" bash "$JB_SCANNER" scan 2>/dev/null)"

assert_contains "scanner: finds the orphaned project cache" \
    "projects/gone-worktree.abc123" "$records"
assert_contains "scanner: attributes it to the right worktree" \
    "gone-worktree" "$records"
assert_contains "scanner: correlates vcs-log by shared hash" \
    "vcs-log/gone-wo_abc123_99887766" "$records"
assert_contains "scanner: correlates compile-server by name" \
    "compile-server/gone-worktree_5f5f5f" "$records"
assert_contains "scanner: reads analyzer evidence from RocksDB" \
    "analyzer/workspaces/aaa111" "$records"

# The live project must still be reported (core decides), tagged as in use.
assert_contains "scanner: reports the live cache too" \
    "projects/live-worktree.def456" "$records"

# End-to-end: only the orphaned IDE caches go.
out="$(wtx_clean_run --yes --scanner "$JB_SCANNER" 2>&1)"
assert_gone   "jetbrains e2e: orphan project cache removed"  "$AS/projects/gone-worktree.abc123"
assert_gone   "jetbrains e2e: orphan vcs-log removed"        "$AS/vcs-log/gone-wo_abc123_99887766"
assert_gone   "jetbrains e2e: orphan compile-server removed" "$AS/compile-server/gone-worktree_5f5f5f"
assert_gone   "jetbrains e2e: orphan analyzer workspace removed" "$ANALYZER/aaa111"
assert_exists "jetbrains e2e: live project cache kept"       "$AS/projects/live-worktree.def456"
assert_exists "jetbrains e2e: live analyzer workspace kept"  "$ANALYZER/bbb222"

# --- Case 6: a scanner for an absent tool is silent ---------------------------

rm -rf "$HOME/Library/Caches/Google" "$HOME/Library/Caches/JetBrains"
records="$(WORKSPACE_ROOT="$WORKSPACE_ROOT" bash "$JB_SCANNER" scan 2>/dev/null)"
assert_not_contains "scanner: no IDE installed -> no delete records" "delete" "$records"

# --- Summary ------------------------------------------------------------------

echo
if [[ "$FAILS" -eq 0 ]]; then
    printf 'All %d assertions passed.\n' "$TOTAL"
    exit 0
fi
printf '%d of %d assertions FAILED.\n' "$FAILS" "$TOTAL"
exit 1
