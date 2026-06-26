#!/bin/bash
# tests/test-worktree-registry.sh — Registry helpers read registry_path from config.
# Run: bash tests/test-worktree-registry.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"

FAILS=0
TOTAL=0

assert_file_exists() {
    local name="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [[ -f "$path" ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      missing: %s\n' "$path"
    fi
}

assert_file_absent() {
    local name="$1" path="$2"
    TOTAL=$((TOTAL + 1))
    if [[ ! -f "$path" ]]; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      unexpected file: %s\n' "$path"
    fi
}

# Assert that 'pattern' appears in 'file' AFTER the '## Recently Closed' header.
assert_in_recently_closed() {
    local name="$1" file="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if awk -v pat="$pattern" 'BEGIN{rc=1} /^## Recently Closed/{found=1} found && index($0, pat){rc=0; exit} END{exit rc}' "$file" 2>/dev/null; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      pattern "%s" not found under ## Recently Closed in: %s\n' "$pattern" "$file"
    fi
}

assert_file_contains() {
    local name="$1" file="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    if awk -v pat="$pattern" 'index($0, pat){found=1; exit} END{exit found ? 0 : 1}' "$file" 2>/dev/null; then
        printf 'PASS  %s\n' "$name"
    else
        FAILS=$((FAILS + 1))
        printf 'FAIL  %s\n' "$name"
        printf '      pattern "%s" not found in: %s\n' "$pattern" "$file"
    fi
}

# Load worktree-tui.sh (and therefore wtx-config.sh) fresh with the given config.
# Sets WTX_CONFIG and WORKSPACE_ROOT in the current shell before sourcing so that
# wtx_config_get() sees them at call time (not just at source time).
load_tui_with_config() {
    unset _WTX_CONFIG_LOADED
    WTX_CONFIG="$1"
    WORKSPACE_ROOT="$2"
    HOME="$2"
    # shellcheck source=../lib/worktree-tui.sh
    source "$REPO_ROOT/lib/worktree-tui.sh"
}

# ---------------------------------------------------------------------------
# Case 1: Default path used when no worktree.registry_path in config
# ---------------------------------------------------------------------------
tmpdir1=$(mktemp -d)
load_tui_with_config "" "$tmpdir1"
update_registry add "proj" "feat/x" "main" "$tmpdir1/wt" "my-ticket"
assert_file_exists "default: registry created at .claude/worktree-registry.md" \
    "$tmpdir1/.claude/worktree-registry.md"
assert_file_absent "default: no file at unexpected path" \
    "$tmpdir1/.custom-reg/my-registry.md"

# ---------------------------------------------------------------------------
# Case 2: Custom registry_path from config is respected (add)
# ---------------------------------------------------------------------------
tmpdir2=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-custom-registry.toml" "$tmpdir2"
update_registry add "proj" "feat/y" "main" "$tmpdir2/wt" "my-ticket"
assert_file_exists "custom: registry created at .custom-reg/my-registry.md" \
    "$tmpdir2/.custom-reg/my-registry.md"
assert_file_absent "custom: no file at default path" \
    "$tmpdir2/.claude/worktree-registry.md"
assert_file_contains "custom: registry contains added ticket" \
    "$tmpdir2/.custom-reg/my-registry.md" "my-ticket"

# ---------------------------------------------------------------------------
# Case 3: remove uses the same custom path; entry appears under Recently Closed
# ---------------------------------------------------------------------------
tmpdir3=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-custom-registry.toml" "$tmpdir3"
update_registry add "proj" "feat/z" "main" "$tmpdir3/wt" "ticket-rm"
update_registry remove "proj" "feat/z"
assert_file_exists "remove: custom registry still exists after remove" \
    "$tmpdir3/.custom-reg/my-registry.md"
assert_in_recently_closed "remove: entry appears under Recently Closed" \
    "$tmpdir3/.custom-reg/my-registry.md" "ticket-rm"

# ---------------------------------------------------------------------------
# Case 4: refresh uses the custom path
# ---------------------------------------------------------------------------
tmpdir4=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-custom-registry.toml" "$tmpdir4"
update_registry add "proj" "feat/w" "main" "$tmpdir4/wt" "ticket-refresh"
update_registry refresh
assert_file_exists "refresh: custom registry still exists after refresh" \
    "$tmpdir4/.custom-reg/my-registry.md"
assert_file_absent "refresh: no file at default path" \
    "$tmpdir4/.claude/worktree-registry.md"
assert_file_contains "refresh: custom registry was refreshed" \
    "$tmpdir4/.custom-reg/my-registry.md" "- **Last Activity:** (missing)"

# ---------------------------------------------------------------------------
# Case 5: else branch — fallback default when wtx_config_get is unavailable
# ---------------------------------------------------------------------------
tmpdir5=$(mktemp -d)
load_tui_with_config "" "$tmpdir5"
# Temporarily remove the function to simulate missing config lib
unset -f wtx_config_get
update_registry add "proj" "feat/v" "main" "$tmpdir5/wt" "ticket-fallback"
assert_file_exists "fallback: default path used when wtx_config_get unavailable" \
    "$tmpdir5/.claude/worktree-registry.md"
assert_file_absent "fallback: no file at unexpected custom path" \
    "$tmpdir5/.custom-reg/my-registry.md"

# ---------------------------------------------------------------------------
# Case 6: invalid registry_path values fall back to the default path
# ---------------------------------------------------------------------------
tmpdir6=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-registry-parent.toml" "$tmpdir6"
update_registry add "proj" "feat/u" "main" "$tmpdir6/wt" "ticket-parent"
assert_file_exists "invalid parent: default registry created" \
    "$tmpdir6/.claude/worktree-registry.md"
assert_file_absent "invalid parent: escaped registry not created" \
    "$(dirname "$tmpdir6")/wtx-registry-parent.md"

tmpdir7=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-registry-nested-parent.toml" "$tmpdir7"
update_registry add "proj" "feat/t" "main" "$tmpdir7/wt" "ticket-nested-parent"
assert_file_exists "invalid nested parent: default registry created" \
    "$tmpdir7/.claude/worktree-registry.md"
assert_file_absent "invalid nested parent: configured path not created" \
    "$tmpdir7/registry.md"

tmpdir8=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-registry-absolute.toml" "$tmpdir8"
update_registry add "proj" "feat/s" "main" "$tmpdir8/wt" "ticket-absolute"
assert_file_exists "invalid absolute: default registry created" \
    "$tmpdir8/.claude/worktree-registry.md"
assert_file_absent "invalid absolute: configured path not created under workspace" \
    "$tmpdir8/tmp/wtx-registry-absolute.md"

tmpdir9=$(mktemp -d)
load_tui_with_config "$FIXTURES/config-registry-empty.toml" "$tmpdir9"
update_registry add "proj" "feat/r" "main" "$tmpdir9/wt" "ticket-empty"
assert_file_exists "invalid empty: default registry created" \
    "$tmpdir9/.claude/worktree-registry.md"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$tmpdir1" "$tmpdir2" "$tmpdir3" "$tmpdir4" "$tmpdir5" "$tmpdir6" "$tmpdir7" "$tmpdir8" "$tmpdir9"

printf '\n%d/%d passed\n' "$((TOTAL - FAILS))" "$TOTAL"
if [[ "$FAILS" -gt 0 ]]; then
    exit 1
fi
