#!/bin/bash
# tests/test-wtx-config.sh — I/O Matrix assertions for lib/wtx-config.sh.
# Run: bash tests/test-wtx-config.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES="$SCRIPT_DIR/fixtures"

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

# Reset loader state between cases
reload_config_lib() {
    unset _WTX_CONFIG_LOADED
    # shellcheck source=../lib/wtx-config.sh
    source "$REPO_ROOT/lib/wtx-config.sh"
}

# -- Case 1: scalar lookup, key present (full fixture)
WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" reload_config_lib
out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get "forge.org")
assert_eq "scalar: forge.org from full fixture" "acme" "$out"

# -- Case 2: inline comment stripped correctly (value shouldn't include '#')
out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get "forge.type")
assert_eq "scalar: forge.type (quoted)" "bitbucket" "$out"

# -- Case 3: unquoted scalar
out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get "defaults.branch_prefix")
assert_eq "scalar: unquoted value" "feature" "$out"

# -- Case 4: dotted subtable [jira.projects]
out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get "jira.projects.web")
assert_eq "scalar: jira.projects.web" "PROJ" "$out"

out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get "jira.projects.mobile")
assert_eq "scalar: jira.projects.mobile" "APP" "$out"

# -- Case 5: list lookup
expected=$'web\nmobile\nbackend'
out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get_list "projects.list")
assert_eq "list: projects.list" "$expected" "$out"

expected=$'settings.gradle\nsettings.gradle.kts'
out=$(WTX_CONFIG="$FIXTURES/config-full.toml" WORKSPACE_ROOT="" wtx_config_get_list "detection.markers")
assert_eq "list: detection.markers" "$expected" "$out"

# -- Case 6: scalar key absent, default returned
out=$(WTX_CONFIG="$FIXTURES/config-partial.toml" WORKSPACE_ROOT="" wtx_config_get "forge.org" "mydefault")
assert_eq "scalar: key present ignores default" "partialco" "$out"

out=$(WTX_CONFIG="$FIXTURES/config-partial.toml" WORKSPACE_ROOT="" wtx_config_get "forge.type" "bitbucket")
assert_eq "scalar: missing key → default" "bitbucket" "$out"

# -- Case 7: scalar absent, no default → empty
out=$(WTX_CONFIG="$FIXTURES/config-partial.toml" WORKSPACE_ROOT="" wtx_config_get "missing.key")
assert_eq "scalar: missing key, no default → empty" "" "$out"

# -- Case 8: no config file anywhere
tmpdir=$(mktemp -d)
out=$(WTX_CONFIG="" WORKSPACE_ROOT="$tmpdir" HOME="$tmpdir" wtx_config_get "forge.org")
assert_eq "scalar: no config anywhere → empty" "" "$out"

out=$(WTX_CONFIG="" WORKSPACE_ROOT="$tmpdir" HOME="$tmpdir" wtx_config_get "forge.org" "fallback")
assert_eq "scalar: no config → default" "fallback" "$out"

out=$(WTX_CONFIG="" WORKSPACE_ROOT="$tmpdir" HOME="$tmpdir" wtx_config_get_list "projects.list")
assert_eq "list: no config → empty" "" "$out"

# -- Case 9: $WTX_CONFIG pointing to missing file falls through
out=$(WTX_CONFIG="$tmpdir/nope.toml" WORKSPACE_ROOT="$tmpdir" HOME="$tmpdir" wtx_config_get "forge.org" "fallback")
assert_eq "scalar: WTX_CONFIG missing → fallthrough" "fallback" "$out"

# -- Case 10: backward-compat fallback via .worktree-projects
legacy_root=$(mktemp -d)
cp "$FIXTURES/worktree-projects-legacy" "$legacy_root/.worktree-projects"

expected=$'web\nmobile\nbackend'
out=$(WTX_CONFIG="" WORKSPACE_ROOT="$legacy_root" HOME="$legacy_root" wtx_config_get_list "projects.list")
assert_eq "compat: projects.list from .worktree-projects" "$expected" "$out"

out=$(WTX_CONFIG="" WORKSPACE_ROOT="$legacy_root" HOME="$legacy_root" wtx_config_get "jira.projects.web")
assert_eq "compat: jira.projects.web from legacy" "PROJ" "$out"

out=$(WTX_CONFIG="" WORKSPACE_ROOT="$legacy_root" HOME="$legacy_root" wtx_config_get "jira.projects.mobile")
assert_eq "compat: jira.projects.mobile from legacy" "APP" "$out"

out=$(WTX_CONFIG="" WORKSPACE_ROOT="$legacy_root" HOME="$legacy_root" wtx_config_get "jira.projects.missing")
assert_eq "compat: jira.projects.missing from legacy → empty" "" "$out"

# -- Case 11: idempotent sourcing
before="$_WTX_CONFIG_LOADED"
source "$REPO_ROOT/lib/wtx-config.sh"
after="$_WTX_CONFIG_LOADED"
assert_eq "idempotent re-source" "$before" "$after"

# -- Case 12: wtx_detect_project — no markers configured, `.git`-only fallback
detect_root=$(mktemp -d)
mkdir -p "$detect_root/repo/sub/deeper"
touch "$detect_root/repo/.git"
out=$(WTX_CONFIG="" WORKSPACE_ROOT="$detect_root" HOME="$detect_root" wtx_detect_project "$detect_root/repo/sub/deeper")
assert_eq "detect: .git-only, finds repo root" "$detect_root/repo" "$out"

# Directory walk fails when no .git exists anywhere
nogit=$(mktemp -d)
mkdir -p "$nogit/child"
out=$(WTX_CONFIG="" WORKSPACE_ROOT="$nogit" HOME="$nogit" wtx_detect_project "$nogit/child")
assert_eq "detect: no .git anywhere → empty" "" "$out"

# -- Case 13: wtx_detect_project — markers configured, only matches when both .git and a marker present
markers_root=$(mktemp -d)
mkdir -p "$markers_root/gradle-proj/app"
touch "$markers_root/gradle-proj/.git"
touch "$markers_root/gradle-proj/settings.gradle.kts"
mkdir -p "$markers_root/plain-git/app"
touch "$markers_root/plain-git/.git"
cat > "$markers_root/wtx.toml" <<'EOF'
[detection]
markers = ["settings.gradle", "settings.gradle.kts"]
EOF
out=$(WTX_CONFIG="" WORKSPACE_ROOT="$markers_root" HOME="$markers_root" wtx_detect_project "$markers_root/gradle-proj/app")
assert_eq "detect: marker present → finds gradle root" "$markers_root/gradle-proj" "$out"

out=$(WTX_CONFIG="" WORKSPACE_ROOT="$markers_root" HOME="$markers_root" wtx_detect_project "$markers_root/plain-git/app")
assert_eq "detect: markers set but none present → empty" "" "$out"

# -- Case 14: relative path input normalises to absolute (no infinite loop)
rel_root=$(mktemp -d)
mkdir -p "$rel_root/proj/sub"
touch "$rel_root/proj/.git"
out=$(cd "$rel_root/proj/sub" && WTX_CONFIG="" WORKSPACE_ROOT="$rel_root" HOME="$rel_root" wtx_detect_project ".")
# mktemp on macOS returns /var/folders/... which is a symlink to /private/var/...;
# `cd && pwd` in wtx_detect_project resolves it, so strip the prefix before compare.
expected_rel="$(cd "$rel_root/proj" && pwd)"
assert_eq "detect: relative '.' normalised, no infinite loop" "$expected_rel" "$out"

# -- Case 15: defaults.base_branch — configured value returned
WTX_CONFIG="$FIXTURES/config-base-branch.toml" WORKSPACE_ROOT="" reload_config_lib
out=$(WTX_CONFIG="$FIXTURES/config-base-branch.toml" WORKSPACE_ROOT="" wtx_config_get "defaults.base_branch" "develop")
assert_eq "defaults.base_branch: configured value" "main" "$out"

# -- Case 16: defaults.base_branch — absent key falls back to supplied default
out=$(WTX_CONFIG="$FIXTURES/config-partial.toml" WORKSPACE_ROOT="" wtx_config_get "defaults.base_branch" "develop")
assert_eq "defaults.base_branch: absent → default 'develop'" "develop" "$out"

# -- Cleanup
rm -rf "$tmpdir" "$legacy_root" "$detect_root" "$nogit" "$markers_root"

printf '\n%d/%d passed\n' "$((TOTAL - FAILS))" "$TOTAL"
if [[ "$FAILS" -gt 0 ]]; then
    exit 1
fi
