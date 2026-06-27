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
# Story 1.2: wizard now runs interactive steps after preflight; stdout contains
# banner + dry-run lines in addition to the no-gum notice. Use contains.
assert_contains "wizard preflight: no-gum notice present" "note: gum not found" "$stdout"
# stderr may contain tty-unavailable messages when stdin is not a tty (interactive
# prompts abort via tui_abort_check); only verify the wizard does NOT emit a hard
# error about preflight (git check / lib source) — not requiring stderr to be empty.
case "$stderr" in
    *"wtx install:"*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  wizard preflight: no preflight error on stderr\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  wizard preflight: no preflight error on stderr\n' ;;
esac
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
# Story 1.2: stdout now includes dry-run lines; only check fallback notice is absent
case "$out" in
    *"note: gum not found"*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  wizard gum: no fallback notice\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  wizard gum: no fallback notice\n' ;;
esac
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

# ---------------------------------------------------------------------------
# Story 1.2 tests: _wtx_install_emit_toml round-trip, Jira empty, plugin map
# ---------------------------------------------------------------------------

# Helper: source wizard internals without running _wtx_install_run.
# Sets up the minimum environment needed for _wtx_install_emit_toml to work.
_setup_emit_env() {
    local tmpdir="$1"
    ( cd "$tmpdir" && git init -q ) 2>/dev/null
    export WTX_ROOT="$REPO_ROOT"
    export WORKSPACE_ROOT="$tmpdir"
    export WTX_INSTALL_DRY_RUN=0
    export GUM_AVAILABLE=0
    export _WTX_INSTALL_TMP="$tmpdir/.wtx-install-tmp.test"
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    _WTX_JIRA_REPOS=()
    _WTX_JIRA_KEYS=()
    # Source the primitives lib
    source "$LIB"
    # Source config loader (for round-trip reads)
    source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
    # Define TUI stubs (no tty available in test)
    tui_style_box() { for l in "$@"; do echo "  $l"; done; }
    tui_choose() { :; }
    tui_input() { echo "${2:-}"; }
    tui_confirm() { return 1; }
}

# -- Case 12: emit_toml — user values round-trip and no example placeholders survive
(
    tmpdir="$(mktemp -d)"
    _setup_emit_env "$tmpdir"
    # Source emit function from wizard
    source "$WIZARD" --dry-run 2>/dev/null || true
    # (sourcing runs _wtx_install_run in a subshell context; we need to re-source the functions)
) 2>/dev/null; true

# Source just the functions (not the entry point) by wrapping
tmpdir12="$(mktemp -d)"
( cd "$tmpdir12" && git init -q ) 2>/dev/null
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="$tmpdir12"
export WTX_INSTALL_DRY_RUN=0
export GUM_AVAILABLE=0
export _WTX_INSTALL_TMP="$tmpdir12/.wtx-test-tmp"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
_WTX_JIRA_REPOS=()
_WTX_JIRA_KEYS=()
source "$LIB"
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
tui_style_box() { for l in "$@"; do echo "  $l"; done; }
tui_choose() { echo "${3:-github}"; }  # pick first non-prompt arg
tui_input() { echo "${2:-}"; }
tui_confirm() { return 1; }

# Now source just the function definitions from the wizard (not the entry call)
# We do this by extracting and sourcing up to _wtx_install_run invocation
wizard_funcs="$(grep -n '_wtx_install_run "\$@"' "$WIZARD" | head -1 | cut -d: -f1)"
wizard_head="$(head -n "$((wizard_funcs - 1))" "$WIZARD")"
eval "$wizard_head" 2>/dev/null || true

# Set up variables that _wtx_install_emit_toml reads
forge_type="github"
forge_org="myorg"
forge_base_url=""
projects_csv="web,api"
detection_csv="Cargo.toml"
base_branch="main"
branch_prefix="feat"
setup_hook="plugins/android-setup.sh"

emitted="$(_wtx_install_emit_toml 2>/dev/null)"

# Round-trip: write to tmp file and read back with wtx_config_get
echo "$emitted" > "$tmpdir12/wtx.toml"
unset _WTX_CONFIG_LOADED
export WTX_CONFIG="$tmpdir12/wtx.toml"
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true

rt_type="$(wtx_config_get "forge.type" "")"
rt_org="$(wtx_config_get "forge.org" "")"
rt_branch="$(wtx_config_get "defaults.base_branch" "")"
rt_prefix="$(wtx_config_get "defaults.branch_prefix" "")"

assert_eq "emit: forge.type round-trip" "github" "$rt_type"
assert_eq "emit: forge.org round-trip" "myorg" "$rt_org"
assert_eq "emit: defaults.base_branch round-trip" "main" "$rt_branch"
assert_eq "emit: defaults.branch_prefix round-trip" "feat" "$rt_prefix"

# No example placeholders
case "$emitted" in
    *'org = "acme"'*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  emit: no acme placeholder\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  emit: no acme placeholder\n' ;;
esac
case "$emitted" in
    *'"web"'*'"mobile"'*'"backend"'*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  emit: no web/mobile/backend placeholder list\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  emit: no web/mobile/backend placeholder list\n' ;;
esac

# projects.list contains user value
assert_contains "emit: projects.list has user values" '"web"' "$emitted"
assert_contains "emit: projects.list has user values (api)" '"api"' "$emitted"

# detection.markers contains user value
assert_contains "emit: detection.markers has Cargo.toml" '"Cargo.toml"' "$emitted"

# No stray settings.gradle placeholder (would only be present if user chose Gradle)
case "$emitted" in
    *'"settings.gradle"'*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  emit: no settings.gradle placeholder\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  emit: no settings.gradle placeholder\n' ;;
esac

rm -rf "$tmpdir12"
unset WTX_CONFIG

# -- Case 13: emit_toml — zero Jira pairs → [jira.projects] section with only a comment
tmpdir13="$(mktemp -d)"
( cd "$tmpdir13" && git init -q ) 2>/dev/null
_WTX_JIRA_REPOS=()
_WTX_JIRA_KEYS=()
forge_type="gitlab"
forge_org="team"
forge_base_url=""
projects_csv=""
detection_csv=""
base_branch="main"
branch_prefix="feature"
setup_hook=""

emitted13="$(_wtx_install_emit_toml 2>/dev/null)"

# Must contain [jira.projects] section header
assert_contains "jira empty: section header present" '[jira.projects]' "$emitted13"

# Must contain a comment line in that section
assert_contains "jira empty: comment present" '# repo = ' "$emitted13"

# Must NOT contain any uncommented key = "value" lines under jira.projects
jira_block="$(echo "$emitted13" | awk '/^\[jira\.projects\]/{found=1; next} found && /^\[/{found=0} found && /^[^#]/{print}')"
case "$jira_block" in
    *'= "'*)
        FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1))
        printf 'FAIL  jira empty: no fabricated keys\n'
        ;;
    *)
        TOTAL=$((TOTAL+1))
        printf 'PASS  jira empty: no fabricated keys\n'
        ;;
esac

rm -rf "$tmpdir13"

# -- Case 14: emit_toml — setup_hook omitted when "None" selected
_WTX_JIRA_REPOS=()
_WTX_JIRA_KEYS=()
forge_type="github"
forge_org="co"
forge_base_url=""
projects_csv=""
detection_csv=""
base_branch="main"
branch_prefix="feature"
setup_hook=""

emitted14="$(_wtx_install_emit_toml 2>/dev/null)"
# Check that no uncommented setup_hook line is present (commented-out is allowed)
uncommented_hook="$(echo "$emitted14" | grep '^setup_hook = "' || true)"
case "$uncommented_hook" in
    *'setup_hook = "'*)
        FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1))
        printf 'FAIL  emit: setup_hook absent when empty\n'
        ;;
    *)
        TOTAL=$((TOTAL+1))
        printf 'PASS  emit: setup_hook absent when empty\n'
        ;;
esac

# -- Case 15: step 8 plugin selection mapping — filename → plugins/<filename>
tmpdir15="$(mktemp -d)"
( cd "$tmpdir15" && git init -q ) 2>/dev/null
plugin_root15="$tmpdir15/wtx"
mkdir -p "$plugin_root15/plugins"
cat > "$plugin_root15/plugins/mysetup.sh" <<'PLUGEOF'
#!/bin/bash
# wtx-plugin-desc: My setup plugin
PLUGEOF
WTX_ROOT="$plugin_root15"
unset _WTX_INSTALL_LIB_LOADED
source "$LIB"

# Simulate Step 8 logic: discover → choose first plugin label
discovered="$(wtx_install_discover_plugins)"
# discovered = "mysetup.sh\tMy setup plugin"
chosen_file="$(echo "$discovered" | cut -f1)"
chosen_desc="$(echo "$discovered" | cut -f2)"
chosen_label="$chosen_file — $chosen_desc"
# Resolve back as the wizard does
resolved_hook="plugins/${chosen_label%% — *}"
assert_eq "plugin map: filename resolves to plugins/<filename>" "plugins/mysetup.sh" "$resolved_hook"

rm -rf "$tmpdir15"
WTX_ROOT="$REPO_ROOT"

# -- Case 16: no interactive read from /dev/tty in worktree-install.sh outside tui_* stubs
# AD-10: prompts must go via tui_* functions. The stubs are all single-line defs
# (tui_xxx() { ... read ... }) so grep filters them out by function-def pattern.
# Pipeline reads like `while ... read -r var` that parse subprocess output are
# allowed — they do NOT prompt the user from /dev/tty.
tty_reads="$(grep -n 'read.*\/dev\/tty\|read -r -p\|read -p' "$WIZARD" \
    | grep -v 'tui_confirm()\|tui_input()\|tui_choose()' \
    | grep -v '^\s*#' || true)"
case "$tty_reads" in
    "")
        TOTAL=$((TOTAL+1))
        printf 'PASS  AD-10: no interactive read outside tui_* stubs\n'
        ;;
    *)
        FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1))
        printf 'FAIL  AD-10: interactive read found outside tui_* stubs\n'
        printf '      %s\n' "$tty_reads"
        ;;
esac

# ---------------------------------------------------------------------------
# Story 1.2 QA gap coverage (Cases 17–24): banner content, Step 2 ledger,
# forge options, full round-trip via wtx_config_get (base_url / jira / lists /
# worktree defaults), detection .git default, and Step 8 None/Custom mapping.
# Wizard function defs were eval'd into this shell at Case 12, so the
# _wtx_install_* helpers are callable directly.
# ---------------------------------------------------------------------------

# -- Case 17: Step 1 banner shows workspace path, WTX root, and Ctrl-C notice (AC 1)
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="/tmp/wtx-banner-ws"
tui_style_box() { for l in "$@"; do echo "  $l"; done; }
banner_out="$(_wtx_install_step_banner)"
assert_contains "banner: shows workspace path" "Workspace: /tmp/wtx-banner-ws" "$banner_out"
assert_contains "banner: shows WTX root" "WTX root:  $REPO_ROOT" "$banner_out"
assert_contains "banner: shows Ctrl-C abort notice" "Ctrl-C" "$banner_out"

# -- Case 18: Step 2 — wtx already resolves to $WTX_ROOT/bin/wtx → skip + ledger (AC 2)
tmpdir18="$(mktemp -d)"
bindir18="$tmpdir18/bin"
mkdir -p "$bindir18"
ln -sf "$REPO_ROOT/bin/wtx" "$bindir18/wtx"
out18file="$tmpdir18/out"
tui_input() { echo "${2:-}"; }
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
WTX_INSTALL_DRY_RUN=0 PATH="$bindir18:$PATH" _wtx_install_step2_binary > "$out18file"
out18="$(cat "$out18file")"
assert_contains "step2 on-path: prints already-on-PATH info" "[✓] wtx already on PATH" "$out18"
assert_eq "step2 on-path: ledger key" "symlink" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "step2 on-path: ledger value skipped" "skipped (already on PATH)" "${_WTX_LEDGER_VALS[0]:-}"
rm -rf "$tmpdir18"

# -- Case 19: Step 2 — not on PATH → delegate; exit 0 → ledger done, non-zero → failed (AC 3)
# Stub the write chokepoint to isolate the rc→ledger mapping from a real install.sh run.
WTX_INSTALL_DRY_RUN=0
tui_input() { echo "${2:-}"; }
wtx_install_write_or_dryrun() { return 0; }
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
PATH="/usr/bin:/bin" _wtx_install_step2_binary >/dev/null; rc=$?
assert_eq "step2 off-path: exit 0 returns 0" 0 "$rc"
assert_eq "step2 off-path: ledger key" "symlink" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "step2 off-path: exit 0 → done" "done" "${_WTX_LEDGER_VALS[0]:-}"
wtx_install_write_or_dryrun() { return 1; }
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
PATH="/usr/bin:/bin" _wtx_install_step2_binary >/dev/null; rc=$?
assert_eq "step2 off-path: non-zero returns rc" 1 "$rc"
assert_eq "step2 off-path: non-zero → failed" "failed" "${_WTX_LEDGER_VALS[0]:-}"
# Restore the real primitive for any later case.
unset -f wtx_install_write_or_dryrun
unset _WTX_INSTALL_LIB_LOADED
source "$LIB"

# -- Case 20: Step 3 forge options are exactly github / gitlab / bitbucket (AC 5)
forge_step_block="$(sed -n '/# Step 3 — Forge configuration/,/# Step 4 — Project dirs/p' "$WIZARD")"
assert_contains "forge: option github" '"github"' "$forge_step_block"
assert_contains "forge: option gitlab" '"gitlab"' "$forge_step_block"
assert_contains "forge: option bitbucket" '"bitbucket"' "$forge_step_block"
case "$forge_step_block" in
    *gitea*|*"sourcehut"*|*"azure"*)
        FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  forge: no extra forge options\n' ;;
    *)
        TOTAL=$((TOTAL+1)); printf 'PASS  forge: no extra forge options\n' ;;
esac

# -- Case 21: full round-trip via wtx_config_get — base_url, jira pairs, lists,
#             worktree defaults, setup_hook all reflect user input (AC 7, 8)
tmpdir21="$(mktemp -d)"
( cd "$tmpdir21" && git init -q ) 2>/dev/null
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="$tmpdir21"
forge_type="gitlab"
forge_org="myorg"
forge_base_url="https://git.example.internal"
projects_csv="web, api ,worker"
detection_csv="Cargo.toml"
base_branch="develop"
branch_prefix="feat"
setup_hook="plugins/android-setup.sh"
_WTX_JIRA_REPOS=("web" "api")
_WTX_JIRA_KEYS=("WEB" "API")
emitted21="$(_wtx_install_emit_toml 2>/dev/null)"
echo "$emitted21" > "$tmpdir21/wtx.toml"
unset _WTX_CONFIG_LOADED
export WTX_CONFIG="$tmpdir21/wtx.toml"
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
assert_eq "rt: forge.base_url" "https://git.example.internal" "$(wtx_config_get "forge.base_url" "")"
assert_eq "rt: jira.projects.web" "WEB" "$(wtx_config_get "jira.projects.web" "")"
assert_eq "rt: jira.projects.api" "API" "$(wtx_config_get "jira.projects.api" "")"
assert_eq "rt: projects.list trims+splits" "$(printf 'web\napi\nworker')" "$(wtx_config_get_list "projects.list")"
assert_eq "rt: detection.markers" "Cargo.toml" "$(wtx_config_get_list "detection.markers")"
assert_eq "rt: worktree.registry_path default" ".claude/worktree-registry.md" "$(wtx_config_get "worktree.registry_path" "")"
assert_eq "rt: worktree.builtin_path default" ".claude/worktrees" "$(wtx_config_get "worktree.builtin_path" "")"
assert_eq "rt: worktree.setup_hook" "plugins/android-setup.sh" "$(wtx_config_get "worktree.setup_hook" "")"
unset WTX_CONFIG
rm -rf "$tmpdir21"

# -- Case 22: detection .git default (empty CSV) → comment only, no markers key (AC 5)
_WTX_JIRA_REPOS=()
_WTX_JIRA_KEYS=()
forge_type="github"
forge_org="co"
forge_base_url=""
projects_csv=""
detection_csv=""
base_branch="main"
branch_prefix="feature"
setup_hook=""
emitted22="$(_wtx_install_emit_toml 2>/dev/null)"
assert_contains "detection default: commented marker hint present" "# markers = " "$emitted22"
uncommented_markers="$(echo "$emitted22" | grep '^markers = ' || true)"
assert_eq "detection default: no uncommented markers key" "" "$uncommented_markers"
# base_url not self-hosted → commented, not emitted as a live key
uncommented_baseurl="$(echo "$emitted22" | grep '^base_url = ' || true)"
assert_eq "forge: base_url omitted when not self-hosted" "" "$uncommented_baseurl"

# -- Case 23: Step 8 — None selection yields empty setup_hook (AC 6)
export WTX_ROOT="$REPO_ROOT"
tui_choose() { echo "None"; }
tui_input() { echo "${2:-}"; }
setup_hook="sentinel"
_wtx_install_step8_hook
assert_eq "step8 None: setup_hook empty" "" "$setup_hook"

# -- Case 24: Step 8 — Custom path… captures the user-supplied relative path (AC 6)
tui_choose() { echo "Custom path…"; }
tui_input() { echo "scripts/my-hook.sh"; }
setup_hook="sentinel"
_wtx_install_step8_hook
assert_eq "step8 Custom: setup_hook is user path" "scripts/my-hook.sh" "$setup_hook"

# -- Case 25: Step 9 decline records skipped and does not invoke subprocess
tmpdir25="$(mktemp -d)"
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="$tmpdir25"
WTX_INSTALL_DRY_RUN=0
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step9_calls=0
step9_args=""
tui_style_box() { for l in "$@"; do echo "  $l"; done; }
tui_confirm() { return 1; }
wtx_install_write_or_dryrun() {
    step9_calls=$((step9_calls + 1))
    step9_args="$*"
    return 0
}
step9_out_file="$tmpdir25/step9.out"
_wtx_install_step9_claude_hooks > "$step9_out_file"
rc=$?
step9_out="$(cat "$step9_out_file")"
assert_eq "step9 decline: returns 0" 0 "$rc"
assert_contains "step9 info: lists create hook" "worktree-create.sh" "$step9_out"
assert_contains "step9 info: lists detect hook" "worktree-detect.sh" "$step9_out"
assert_contains "step9 info: lists remove hook" "worktree-remove.sh" "$step9_out"
assert_eq "step9 decline: ledger key" "hooks" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "step9 decline: ledger value skipped" "skipped" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "step9 decline: no subprocess" 0 "$step9_calls"
rm -rf "$tmpdir25"

# -- Case 26: Step 9 confirm success records done and delegates install.sh --hooks
tmpdir26="$(mktemp -d)"
export WORKSPACE_ROOT="$tmpdir26"
WTX_INSTALL_DRY_RUN=0
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step9_calls=0
step9_args=""
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() {
    step9_calls=$((step9_calls + 1))
    step9_args="$*"
    return 0
}
_wtx_install_step9_claude_hooks >/dev/null
rc=$?
assert_eq "step9 success: returns 0" 0 "$rc"
assert_eq "step9 success: ledger key" "hooks" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "step9 success: ledger value done" "done" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "step9 success: delegates once" 1 "$step9_calls"
assert_contains "step9 success: command uses bash install.sh" "bash $REPO_ROOT/install.sh --hooks" "$step9_args"
rm -rf "$tmpdir26"

# -- Case 27: Step 9 confirm failure records failed and propagates rc
tmpdir27="$(mktemp -d)"
export WORKSPACE_ROOT="$tmpdir27"
WTX_INSTALL_DRY_RUN=0
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() { return 6; }
_wtx_install_step9_claude_hooks >/dev/null
rc=$?
assert_eq "step9 failure: returns subprocess rc" 6 "$rc"
assert_eq "step9 failure: ledger key" "hooks" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "step9 failure: ledger value failed" "failed" "${_WTX_LEDGER_VALS[0]:-}"
rm -rf "$tmpdir27"

# -- Case 28: Step 9 dry-run appends --dry-run to delegated command args
tmpdir28="$(mktemp -d)"
export WORKSPACE_ROOT="$tmpdir28"
WTX_INSTALL_DRY_RUN=1
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step9_args=""
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() {
    step9_args="$*"
    return 0
}
_wtx_install_step9_claude_hooks >/dev/null
rc=$?
assert_eq "step9 dry-run: returns 0" 0 "$rc"
assert_contains "step9 dry-run: delegated args include dry-run" "--dry-run" "$step9_args"
assert_eq "step9 dry-run: ledger previewed" "previewed (dry-run)" "${_WTX_LEDGER_VALS[0]:-}"
rm -rf "$tmpdir28"

# -- Case 29: _wtx_install_run tracks Step 9 failure but returns it after later placeholders
_wtx_install_preflight() {
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    WTX_INSTALL_DRY_RUN=0
    WORKSPACE_ROOT="/tmp/wtx-run-test"
    export WTX_INSTALL_DRY_RUN WORKSPACE_ROOT
    return 0
}
_wtx_install_step_banner() { return 0; }
_wtx_install_step2_binary() { return 0; }
_wtx_install_steps3_7_config() { return 0; }
_wtx_install_step8_hook() { return 0; }
wtx_install_write_or_dryrun() { return 0; }
_wtx_install_step9_claude_hooks() { return 8; }
_wtx_install_run >/dev/null 2>&1; rc=$?
assert_eq "run: step9 failure returns tracked rc" 8 "$rc"

# -- Case 30: _wtx_install_run propagates critical failures with ledger evidence
_wtx_install_preflight() {
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    WTX_INSTALL_DRY_RUN=0
    WORKSPACE_ROOT="/tmp/wtx-run-test"
    export WTX_INSTALL_DRY_RUN WORKSPACE_ROOT
    return 0
}
_wtx_install_step_banner() { return 0; }
_wtx_install_steps3_7_config() { return 0; }
_wtx_install_step8_hook() { return 0; }

_wtx_install_step2_binary() { return 7; }
_wtx_install_run >/dev/null 2>&1; rc=$?
assert_eq "run: step2 failure returns rc" 7 "$rc"

_wtx_install_step2_binary() { return 0; }
wtx_install_write_or_dryrun() { return 9; }
_wtx_install_run >/dev/null 2>&1; rc=$?
assert_eq "run: TOML write failure returns rc" 9 "$rc"
assert_eq "run: TOML write failure ledger key" "config" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "run: TOML write failure ledger value" "failed" "${_WTX_LEDGER_VALS[0]:-}"

# ---------------------------------------------------------------------------
# Story 1.3 QA gap coverage (Cases 31-34): ledger-count, descriptions,
# workspace-root hook destination, run success
# ---------------------------------------------------------------------------

# Restore real wizard functions (_wtx_install_step9_claude_hooks and _wtx_install_run
# were overridden as stubs in Cases 29–30).
unset -f _wtx_install_step9_claude_hooks _wtx_install_run
eval "$wizard_head" 2>/dev/null || true
tui_style_box() { for l in "$@"; do echo "  $l"; done; }

# -- Case 31: Step 9 — exactly one ledger entry per outcome (AC5)
# AC5 requires *exactly* one entry appended regardless of outcome.
tmpdir31="$(mktemp -d)"
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="$tmpdir31"
wtx_install_write_or_dryrun() { return 0; }

WTX_INSTALL_DRY_RUN=0
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 1; }
_wtx_install_step9_claude_hooks >/dev/null
assert_eq "step9 ledger-count: exactly 1 entry on decline" "1" "${#_WTX_LEDGER_KEYS[@]}"

_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 0; }
_wtx_install_step9_claude_hooks >/dev/null
assert_eq "step9 ledger-count: exactly 1 entry on success" "1" "${#_WTX_LEDGER_KEYS[@]}"

_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() { return 5; }
_wtx_install_step9_claude_hooks >/dev/null; true
assert_eq "step9 ledger-count: exactly 1 entry on failure" "1" "${#_WTX_LEDGER_KEYS[@]}"

rm -rf "$tmpdir31"

# -- Case 32: Step 9 info box contains one-line descriptions for all three hooks (AC1)
# AC1 requires a description beside each hook filename; only filenames were checked before.
tmpdir32="$(mktemp -d)"
export WORKSPACE_ROOT="$tmpdir32"
WTX_INSTALL_DRY_RUN=0
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 1; }
wtx_install_write_or_dryrun() { return 0; }
step32_out="$(_wtx_install_step9_claude_hooks)"
assert_contains "step9 desc: create hook one-liner" "runs after 'wtx start' creates a worktree" "$step32_out"
assert_contains "step9 desc: detect hook one-liner" "runs when Claude detects the active worktree" "$step32_out"
assert_contains "step9 desc: remove hook one-liner" "runs after 'wtx done' removes a worktree" "$step32_out"
rm -rf "$tmpdir32"

# -- Case 33: Step 9 installs hooks into WORKSPACE_ROOT even when invoked below it (AC2)
tmpdir33="$(mktemp -d)"
mkdir -p "$tmpdir33/ws/nested"
( cd "$tmpdir33/ws" && git init -q )
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="$tmpdir33/ws"
WTX_INSTALL_DRY_RUN=0
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 0; }
unset -f wtx_install_write_or_dryrun
unset _WTX_INSTALL_LIB_LOADED
source "$LIB"
start_pwd="$(pwd)"
cd "$tmpdir33/ws/nested" || exit 1
_wtx_install_step9_claude_hooks > "$tmpdir33/step9.out" 2>"$tmpdir33/step9.err"
rc=$?
after_pwd="$(pwd)"
cd "$start_pwd" || exit 1
assert_eq "step9 cwd: returns 0" 0 "$rc"
assert_eq "step9 cwd: restores caller directory" "$tmpdir33/ws/nested" "$after_pwd"
assert_eq "step9 cwd: ledger value done" "done" "${_WTX_LEDGER_VALS[0]:-}"
for hook_name in worktree-create.sh worktree-detect.sh worktree-remove.sh; do
    if cmp -s "$REPO_ROOT/hooks/$hook_name" "$tmpdir33/ws/.claude/hooks/$hook_name"; then
        TOTAL=$((TOTAL+1))
        printf 'PASS  step9 cwd: %s copied byte-for-byte\n' "$hook_name"
    else
        FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1))
        printf 'FAIL  step9 cwd: %s copied byte-for-byte\n' "$hook_name"
    fi
done
[[ ! -e "$tmpdir33/ws/nested/.claude/hooks/worktree-create.sh" ]]
assert_ok "step9 cwd: nested directory left unchanged" $?
rm -rf "$tmpdir33"

# -- Case 34: _wtx_install_run returns 0 when step9 succeeds (tracked _run_rc stays 0)
# Inverse of Case 29: verified failure propagation; this verifies the success path.
_wtx_install_preflight() {
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    WTX_INSTALL_DRY_RUN=0
    WORKSPACE_ROOT="/tmp/wtx-run-test-33"
    export WTX_INSTALL_DRY_RUN WORKSPACE_ROOT
    return 0
}
_wtx_install_step_banner() { return 0; }
_wtx_install_step2_binary() { return 0; }
_wtx_install_steps3_7_config() { return 0; }
_wtx_install_step8_hook() { return 0; }
wtx_install_write_or_dryrun() { return 0; }
_wtx_install_step9_claude_hooks() { return 0; }
_wtx_install_run >/dev/null 2>&1; rc=$?
assert_eq "run: step9 success tracked-rc returns 0" 0 "$rc"

# ---------------------------------------------------------------------------
# Story 1.4 QA gap coverage (Cases 35-43): Step 10 extras menu, Gradle
# delegation, PATH hint behavior, dry-run propagation, and run wiring.
# ---------------------------------------------------------------------------

# Restore real wizard functions before Step 10 focused tests.
unset -f _wtx_install_step9_claude_hooks _wtx_install_step10_extras _wtx_install_run
eval "$wizard_head" 2>/dev/null || true
tui_style_box() { for l in "$@"; do echo "  $l"; done; }

# -- Case 35: Step 10 Gradle decline returns 0, records skipped, and does not delegate
tmpdir35="$(mktemp -d)"
export WTX_ROOT="$REPO_ROOT"
export WTX_INSTALL_PREFIX="$tmpdir35/prefix"
WTX_INSTALL_DRY_RUN=0
PATH="$WTX_INSTALL_PREFIX/bin:/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step10_prompts=""
step10_calls=0
tui_confirm() {
    step10_prompts="${step10_prompts}[$1|${2-__unset__}]"
    return 1
}
wtx_install_write_or_dryrun() {
    step10_calls=$((step10_calls + 1))
    return 0
}
_wtx_install_step10_extras >/dev/null
rc=$?
assert_eq "step10 gradle decline: returns 0" 0 "$rc"
assert_contains "step10 gradle decline: prompt defaults no" "[Install Gradle worktree-cache init script to ~/.gradle/init.d/?|__unset__]" "$step10_prompts"
assert_eq "step10 gradle decline: no delegate" 0 "$step10_calls"
assert_eq "step10 gradle decline: ledger key" "gradle" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "step10 gradle decline: ledger skipped" "skipped" "${_WTX_LEDGER_VALS[0]:-}"
step10_gradle_count=0
set +u
for key in "${_WTX_LEDGER_KEYS[@]}"; do
    [[ "$key" = "gradle" ]] && step10_gradle_count=$((step10_gradle_count + 1))
done
set -u
assert_eq "step10 gradle decline: exactly one gradle entry" "1" "$step10_gradle_count"
rm -rf "$tmpdir35"

# -- Case 36: Step 10 Gradle confirm success delegates install.sh --gradle
tmpdir36="$(mktemp -d)"
export WTX_INSTALL_PREFIX="$tmpdir36/prefix"
WTX_INSTALL_DRY_RUN=0
PATH="$WTX_INSTALL_PREFIX/bin:/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step10_action=""
step10_args=""
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() {
    step10_action="$1"
    shift
    step10_args="$(printf '<%s>' "$@")"
    return 0
}
_wtx_install_step10_extras >/dev/null
rc=$?
assert_eq "step10 gradle success: returns 0" 0 "$rc"
assert_eq "step10 gradle success: action label" "would copy: $REPO_ROOT/share/gradle/worktree-cache.init.gradle.kts -> $HOME/.gradle/init.d/worktree-cache.init.gradle.kts" "$step10_action"
assert_eq "step10 gradle success: delegated args" "<bash><$REPO_ROOT/install.sh><--gradle>" "$step10_args"
assert_eq "step10 gradle success: ledger done" "done" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "step10 gradle success: path-hint skipped (already on PATH)" "skipped (already on PATH)" "${_WTX_LEDGER_VALS[1]:-}"
rm -rf "$tmpdir36"

# -- Case 37: Step 10 Gradle failure returns rc and still runs PATH hint
tmpdir37="$(mktemp -d)"
export WTX_INSTALL_PREFIX="$tmpdir37/prefix"
WTX_INSTALL_DRY_RUN=0
PATH="/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() { return 4; }
step37_out_file="$tmpdir37/out"
_wtx_install_step10_extras > "$step37_out_file"
rc=$?
step37_out="$(cat "$step37_out_file")"
assert_eq "step10 gradle failure: returns delegate rc" 4 "$rc"
assert_eq "step10 gradle failure: ledger gradle failed" "failed" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "step10 gradle failure: still records path hint" "path-hint" "${_WTX_LEDGER_KEYS[1]:-}"
assert_eq "step10 gradle failure: path hint shown" "shown" "${_WTX_LEDGER_VALS[1]:-}"
assert_contains "step10 gradle failure: PATH hint still printed" "export PATH=" "$step37_out"
rm -rf "$tmpdir37"

# -- Case 38: Step 10 Gradle dry-run appends --dry-run to delegated args
tmpdir38="$(mktemp -d)"
export WTX_INSTALL_PREFIX="$tmpdir38/prefix"
WTX_INSTALL_DRY_RUN=1
PATH="$WTX_INSTALL_PREFIX/bin:/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step10_args=""
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() {
    shift
    step10_args="$(printf '<%s>' "$@")"
    return 0
}
_wtx_install_step10_extras >/dev/null
rc=$?
assert_eq "step10 dry-run: returns 0" 0 "$rc"
assert_eq "step10 dry-run: delegated args include dry-run" "<bash><$REPO_ROOT/install.sh><--gradle><--dry-run>" "$step10_args"
assert_eq "step10 dry-run: ledger previewed" "previewed (dry-run)" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "step10 dry-run: path-hint skipped (already on PATH)" "skipped (already on PATH)" "${_WTX_LEDGER_VALS[1]:-}"
rm -rf "$tmpdir38"

# -- Case 39: Step 10 PATH already on PATH skips prompt and hint output
tmpdir39="$(mktemp -d)"
export WTX_INSTALL_PREFIX="$tmpdir39/prefix"
WTX_INSTALL_DRY_RUN=0
PATH="/bin:$WTX_INSTALL_PREFIX/bin:/usr/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step10_prompts=""
tui_confirm() {
    step10_prompts="${step10_prompts}[$1]"
    return 1
}
wtx_install_write_or_dryrun() { return 0; }
step39_out_file="$tmpdir39/out"
_wtx_install_step10_extras > "$step39_out_file"
rc=$?
step39_out="$(cat "$step39_out_file")"
assert_eq "step10 path on PATH: returns 0" 0 "$rc"
case "$step10_prompts" in
    *"Show PATH setup hint?"*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  step10 path on PATH: no PATH prompt\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  step10 path on PATH: no PATH prompt\n' ;;
esac
case "$step39_out" in
    *"export PATH="*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  step10 path on PATH: no hint output\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  step10 path on PATH: no hint output\n' ;;
esac
assert_eq "step10 path on PATH: ledger skipped already" "skipped (already on PATH)" "${_WTX_LEDGER_VALS[1]:-}"
rm -rf "$tmpdir39"

# -- Case 40: Step 10 PATH missing + user declines records skipped and prints no guidance
tmpdir40="$(mktemp -d)"
export WTX_INSTALL_PREFIX="$tmpdir40/prefix"
WTX_INSTALL_DRY_RUN=0
PATH="/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step10_prompts=""
tui_confirm() {
    step10_prompts="${step10_prompts}[$1|${2-__unset__}]"
    return 1
}
wtx_install_write_or_dryrun() { return 0; }
step40_out_file="$tmpdir40/out"
_wtx_install_step10_extras > "$step40_out_file"
rc=$?
step40_out="$(cat "$step40_out_file")"
assert_eq "step10 path decline: returns 0" 0 "$rc"
assert_contains "step10 path decline: prompt defaults yes" "[Show PATH setup hint?|yes]" "$step10_prompts"
case "$step40_out" in
    *"export PATH="*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  step10 path decline: no export guidance\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  step10 path decline: no export guidance\n' ;;
esac
assert_eq "step10 path decline: ledger skipped" "skipped" "${_WTX_LEDGER_VALS[1]:-}"
rm -rf "$tmpdir40"

# -- Case 41: Step 10 PATH missing + default prefix prints $HOME guidance
tmpdir41="$(mktemp -d)"
unset WTX_INSTALL_PREFIX
WTX_INSTALL_DRY_RUN=0
PATH="/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() {
    case "$1" in
        "Install Gradle worktree-cache init script to ~/.gradle/init.d/?") return 1 ;;
        "Show PATH setup hint?") return 0 ;;
    esac
    return 1
}
wtx_install_write_or_dryrun() { return 0; }
step41_out_file="$tmpdir41/out"
_wtx_install_step10_extras > "$step41_out_file"
rc=$?
step41_out="$(cat "$step41_out_file")"
assert_eq "step10 path default hint: returns 0" 0 "$rc"
assert_contains "step10 path default hint: prints HOME export" 'export PATH="$HOME/.local/bin:$PATH"' "$step41_out"
assert_eq "step10 path default hint: ledger shown" "shown" "${_WTX_LEDGER_VALS[1]:-}"
assert_eq "step10 path default hint: exports fallback prefix" "$HOME/.local" "${WTX_INSTALL_PREFIX:-}"
rm -rf "$tmpdir41"

# -- Case 42: Step 10 PATH missing + custom prefix prints custom path
tmpdir42="$(mktemp -d)"
export WTX_INSTALL_PREFIX="$tmpdir42/custom-prefix"
WTX_INSTALL_DRY_RUN=0
PATH="/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
tui_confirm() {
    case "$1" in
        "Install Gradle worktree-cache init script to ~/.gradle/init.d/?") return 1 ;;
        "Show PATH setup hint?") return 0 ;;
    esac
    return 1
}
wtx_install_write_or_dryrun() { return 0; }
step42_out_file="$tmpdir42/out"
_wtx_install_step10_extras > "$step42_out_file"
rc=$?
step42_out="$(cat "$step42_out_file")"
assert_eq "step10 path custom hint: returns 0" 0 "$rc"
assert_contains "step10 path custom hint: prints custom export" "export PATH=\"$WTX_INSTALL_PREFIX/bin:\$PATH\"" "$step42_out"
rm -rf "$tmpdir42"

# -- Case 43: _wtx_install_run wires Step 10 after Step 9 and tracks optional rc
_wtx_install_preflight() {
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    WTX_INSTALL_DRY_RUN=0
    WORKSPACE_ROOT="/tmp/wtx-run-test-14"
    export WTX_INSTALL_DRY_RUN WORKSPACE_ROOT
    return 0
}
_wtx_install_step_banner() { return 0; }
_wtx_install_step2_binary() { return 0; }
_wtx_install_steps3_7_config() { return 0; }
_wtx_install_step8_hook() { return 0; }
wtx_install_write_or_dryrun() { return 0; }
_wtx_install_step9_claude_hooks() { return 0; }
_wtx_install_step10_extras() { return 6; }
_wtx_install_run >/dev/null 2>&1; rc=$?
assert_eq "run: step10 failure returns tracked rc" 6 "$rc"

_wtx_install_step9_claude_hooks() { return 8; }
_wtx_install_step10_extras() { return 0; }
_wtx_install_run >/dev/null 2>&1; rc=$?
assert_eq "run: step9 failure still returns tracked rc" 8 "$rc"

# ---------------------------------------------------------------------------
# Story 1.4 E2E coverage (Cases 44-45): execute the real wizard with a gum
# shim so Step 10 is reached through the public script path.
# ---------------------------------------------------------------------------

_write_install_gum_shim() {
    local shim_dir="$1"
    mkdir -p "$shim_dir"
    cat > "$shim_dir/gum" <<'GUMEOF'
#!/bin/bash
cmd="$1"
shift

_gum_log() {
    if [[ -n "${WTX_GUM_LOG:-}" ]]; then
        printf '%s\n' "$*" >> "$WTX_GUM_LOG"
    fi
}

case "$cmd" in
    input)
        prompt=""
        value=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --prompt) prompt="$2"; shift 2 ;;
                --value) value="$2"; shift 2 ;;
                --placeholder) shift 2 ;;
                *) shift ;;
            esac
        done
        _gum_log "input:$prompt"
        case "$prompt" in
            "Install prefix "*) printf '%s\n' "${WTX_GUM_INSTALL_PREFIX:-$value}" ;;
            "Forge org / owner slug "*) printf '%s\n' "${WTX_GUM_FORGE_ORG:-example-org}" ;;
            "Known project dirs "*) printf '%s\n' "${WTX_GUM_PROJECTS:-}" ;;
            "Default base branch "*) printf '%s\n' "${WTX_GUM_BASE_BRANCH:-$value}" ;;
            "Default branch prefix "*) printf '%s\n' "${WTX_GUM_BRANCH_PREFIX:-$value}" ;;
            "Repo name for Jira mapping "*) printf '\n' ;;
            *) printf '%s\n' "$value" ;;
        esac
        ;;
    choose)
        header=""
        opts=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --header) header="$2"; shift 2 ;;
                --selected) shift 2 ;;
                *) opts+=("$1"); shift ;;
            esac
        done
        _gum_log "choose:$header"
        case "$header" in
            "How do you want to proceed?") printf '%s\n' "${WTX_GUM_IDEMPOTENCY_MODE:-${opts[0]:-skip}}" ;;
            "Forge type") printf 'github\n' ;;
            "Detection markers") printf '.git (any git repo — default)\n' ;;
            "Setup hook (runs after worktree create)") printf 'None\n' ;;
            *) printf '%s\n' "${opts[0]:-}" ;;
        esac
        ;;
    confirm)
        prompt="$1"
        _gum_log "confirm:$prompt"
        case "$prompt" in
            "Self-hosted instance?") exit 1 ;;
            "Add another Jira mapping?") exit 1 ;;
            "Install Claude Code hooks?") [[ "${WTX_GUM_HOOKS:-yes}" = "yes" ]] ;;
            "Install Gradle worktree-cache init script to ~/.gradle/init.d/?") [[ "${WTX_GUM_GRADLE:-no}" = "yes" ]] ;;
            "Show PATH setup hint?") [[ "${WTX_GUM_PATH_HINT:-yes}" = "yes" ]] ;;
            *) exit 1 ;;
        esac
        ;;
    style)
        cat
        ;;
    spin)
        while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
        [[ "${1:-}" = "--" ]] && shift
        "$@"
        ;;
    *)
        exit 1
        ;;
esac
GUMEOF
    chmod +x "$shim_dir/gum"
}

# -- Case 44: full wizard dry-run reaches Step 10 and honors default-no Gradle/default-yes PATH hint
tmpdir44="$(mktemp -d)"
mkdir -p "$tmpdir44/home" "$tmpdir44/repo"
( cd "$tmpdir44/repo" && git init -q )
_write_install_gum_shim "$tmpdir44/bin"
out44="$(
    cd "$tmpdir44/repo" && \
    HOME="$tmpdir44/home" \
    PATH="$tmpdir44/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir44/repo" \
    WTX_GUM_INSTALL_PREFIX="$tmpdir44/prefix" \
    WTX_GUM_GRADLE=no \
    WTX_GUM_PATH_HINT=yes \
    bash "$WIZARD" --dry-run 2>&1
)"
rc=$?
assert_eq "wizard e2e dry-run: exits 0" 0 "$rc"
assert_contains "wizard e2e dry-run: reaches optional extras" "Optional extras" "$out44"
assert_contains "wizard e2e dry-run: shows Gradle one-liner" "Isolates Gradle build caches per worktree." "$out44"
case "$out44" in
    *"[dry-run] would copy: gradle init"*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  wizard e2e dry-run: default-no Gradle skips delegate\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  wizard e2e dry-run: default-no Gradle skips delegate\n' ;;
esac
assert_contains "wizard e2e dry-run: default-yes PATH hint shown" "export PATH=\"$tmpdir44/prefix/bin:\$PATH\"" "$out44"
[[ ! -e "$tmpdir44/repo/wtx.toml" ]]; assert_ok "wizard e2e dry-run: no TOML write" $?
[[ ! -e "$tmpdir44/home/.gradle/init.d/worktree-cache.init.gradle.kts" ]]; assert_ok "wizard e2e dry-run: no Gradle file write" $?
rm -rf "$tmpdir44"

# -- Case 45: full wizard real run confirms Gradle and delegates to install.sh using temporary HOME
tmpdir45="$(mktemp -d)"
mkdir -p "$tmpdir45/home" "$tmpdir45/repo" "$tmpdir45/prefix/bin"
( cd "$tmpdir45/repo" && git init -q )
_write_install_gum_shim "$tmpdir45/bin"
ln -s "$REPO_ROOT/bin/wtx" "$tmpdir45/prefix/bin/wtx"
out45="$(
    cd "$tmpdir45/repo" && \
    HOME="$tmpdir45/home" \
    PATH="$tmpdir45/bin:$tmpdir45/prefix/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir45/repo" \
    WTX_INSTALL_PREFIX="$tmpdir45/prefix" \
    WTX_GUM_INSTALL_PREFIX="$tmpdir45/prefix" \
    WTX_GUM_HOOKS=no \
    WTX_GUM_GRADLE=yes \
    bash "$WIZARD" 2>&1
)"
rc=$?
assert_eq "wizard e2e gradle: exits 0" 0 "$rc"
assert_contains "wizard e2e gradle: install.sh reports copy" "copied worktree-cache.init.gradle.kts" "$out45"
[[ -f "$tmpdir45/home/.gradle/init.d/worktree-cache.init.gradle.kts" ]]; assert_ok "wizard e2e gradle: file installed under temp HOME" $?
[[ -f "$tmpdir45/repo/wtx.toml" ]]; assert_ok "wizard e2e gradle: TOML written" $?
case "$out45" in
    *"Add to your shell startup file:"*) FAILS=$((FAILS+1)); TOTAL=$((TOTAL+1)); printf 'FAIL  wizard e2e gradle: already-on-PATH prints no wizard PATH hint\n' ;;
    *) TOTAL=$((TOTAL+1)); printf 'PASS  wizard e2e gradle: already-on-PATH prints no guidance\n' ;;
esac
rm -rf "$tmpdir45"

# ---------------------------------------------------------------------------
# Story 1.5 idempotency gate (Cases 46-53)
# ---------------------------------------------------------------------------

# Restore real wizard functions after E2E cases.
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook
eval "$wizard_head" 2>/dev/null || true

# -- Case 46: no wtx.toml defaults to overwrite with no chooser prompt
tmpdir46="$(mktemp -d)"
export WORKSPACE_ROOT="$tmpdir46"
choose_calls46=0
style_calls46=0
tui_choose() { choose_calls46=$((choose_calls46 + 1)); echo "skip"; }
tui_style_box() { style_calls46=$((style_calls46 + 1)); }
_WTX_INSTALL_MODE=""
_wtx_install_step0_idempotency >/dev/null
assert_eq "idempotency no file: mode overwrite" "overwrite" "$_WTX_INSTALL_MODE"
assert_eq "idempotency no file: no prompt" 0 "$choose_calls46"
assert_eq "idempotency no file: no style box" 0 "$style_calls46"
rm -rf "$tmpdir46"

# -- Case 47: existing wtx.toml + skip bypasses Steps 1-8 and records kept config
tmpdir47="$(mktemp -d)"
echo '[forge]' > "$tmpdir47/wtx.toml"
run47_early=0
run47_hooks=0
run47_extras=0
_wtx_install_preflight() {
    WORKSPACE_ROOT="$tmpdir47"
    WTX_ROOT="$REPO_ROOT"
    WTX_INSTALL_DRY_RUN=0
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    export WORKSPACE_ROOT WTX_ROOT WTX_INSTALL_DRY_RUN
    return 0
}
tui_style_box() { :; }
tui_choose() { echo "skip"; }
_wtx_install_step_banner() { run47_early=$((run47_early + 1)); return 0; }
_wtx_install_step2_binary() { run47_early=$((run47_early + 1)); return 0; }
_wtx_install_steps3_7_config() { run47_early=$((run47_early + 1)); return 0; }
_wtx_install_step8_hook() { run47_early=$((run47_early + 1)); return 0; }
_wtx_install_step9_claude_hooks() { run47_hooks=$((run47_hooks + 1)); return 0; }
_wtx_install_step10_extras() { run47_extras=$((run47_extras + 1)); return 0; }
_wtx_install_run > "$tmpdir47/out" 2>"$tmpdir47/err"; rc=$?
assert_eq "idempotency skip: run exits 0" 0 "$rc"
assert_eq "idempotency skip: no Steps 1-8" 0 "$run47_early"
assert_eq "idempotency skip: Step 9 called" 1 "$run47_hooks"
assert_eq "idempotency skip: Step 10 called" 1 "$run47_extras"
assert_eq "idempotency skip: ledger key" "config" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "idempotency skip: ledger kept existing" "kept (existing)" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "idempotency skip: exactly one ledger entry" 1 "${#_WTX_LEDGER_KEYS[@]}"
assert_eq "idempotency skip: toml content unchanged" "[forge]" "$(cat "$tmpdir47/wtx.toml")"
rm -rf "$tmpdir47"

# Restore real functions before prompt-level merge/overwrite tests.
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook
eval "$wizard_head" 2>/dev/null || true

# -- Case 48: overwrite config prompts do not pre-read existing config values
cfg_get_calls48=0
cfg_list_calls48=0
wtx_config_get() { cfg_get_calls48=$((cfg_get_calls48 + 1)); echo "SHOULD_NOT_READ"; }
wtx_config_get_list() { cfg_list_calls48=$((cfg_list_calls48 + 1)); echo "SHOULD_NOT_READ"; }
_WTX_INSTALL_MODE="overwrite"
tui_choose() {
    case "$1" in
        "Forge type") echo "github" ;;
        "Detection markers") echo ".git (any git repo — default)" ;;
        *) echo "${2:-}" ;;
    esac
}
tui_input() { echo "${2:-}"; }
tui_confirm() { return 1; }
_wtx_install_steps3_7_config >/dev/null
assert_eq "idempotency overwrite: no scalar prefill reads" 0 "$cfg_get_calls48"
assert_eq "idempotency overwrite: no list prefill reads" 0 "$cfg_list_calls48"
assert_eq "idempotency overwrite: base branch empty defaults main" "main" "$base_branch"
assert_eq "idempotency overwrite: prefix empty defaults feature" "feature" "$branch_prefix"

# -- Case 49: existing wtx.toml + overwrite runs normal Steps 1-8 and writes config
tmpdir49="$(mktemp -d)"
echo '[forge]' > "$tmpdir49/wtx.toml"
run49_order=""
_wtx_install_preflight() {
    WORKSPACE_ROOT="$tmpdir49"
    WTX_ROOT="$REPO_ROOT"
    WTX_INSTALL_DRY_RUN=0
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    export WORKSPACE_ROOT WTX_ROOT WTX_INSTALL_DRY_RUN
    return 0
}
tui_style_box() { :; }
tui_choose() { echo "overwrite"; }
_wtx_install_step_banner() { run49_order="${run49_order}banner "; return 0; }
_wtx_install_step2_binary() { run49_order="${run49_order}step2 "; return 0; }
_wtx_install_steps3_7_config() { run49_order="${run49_order}config "; return 0; }
_wtx_install_step8_hook() { run49_order="${run49_order}hook "; return 0; }
wtx_install_write_or_dryrun() { run49_order="${run49_order}write "; return 0; }
_wtx_install_step9_claude_hooks() { run49_order="${run49_order}step9 "; return 0; }
_wtx_install_step10_extras() { run49_order="${run49_order}step10 "; return 0; }
_wtx_install_run > "$tmpdir49/out" 2>"$tmpdir49/err"; rc=$?
assert_eq "idempotency overwrite: run exits 0" 0 "$rc"
assert_eq "idempotency overwrite: normal run order" "banner step2 config hook write step9 step10 " "$run49_order"
assert_eq "idempotency overwrite: ledger config done" "done" "${_WTX_LEDGER_VALS[0]:-}"
rm -rf "$tmpdir49"

# Restore real functions and config loader before merge tests.
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook wtx_config_get wtx_config_get_list wtx_install_write_or_dryrun
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
eval "$wizard_head" 2>/dev/null || true

# -- Case 50: merge prompts receive existing values as defaults/selected values
tmpdir50="$(mktemp -d)"
cat > "$tmpdir50/wtx.toml" <<'EOF50'
[forge]
type = "gitlab"
org = "team"
base_url = "https://git.example.internal"

[projects]
list = ["api", "web"]

[detection]
markers = ["Cargo.toml"]

[worktree]
setup_hook = "plugins/android-setup.sh"

[defaults]
base_branch = "develop"
branch_prefix = "feat"
EOF50
export WORKSPACE_ROOT="$tmpdir50"
export WTX_ROOT="$REPO_ROOT"
export WTX_CONFIG="$tmpdir50/wtx.toml"
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
_WTX_INSTALL_MODE="merge"
choose_log_file50="$tmpdir50/choose.log"
input_log_file50="$tmpdir50/input.log"
: > "$choose_log_file50"
: > "$input_log_file50"
tui_choose() {
    local selected="" prompt
    if [[ "${1:-}" = "--selected" ]]; then
        selected="$2"; shift 2
    fi
    prompt="$1"; shift
    printf '[%s|%s]' "$prompt" "$selected" >> "$choose_log_file50"
    if [[ -n "$selected" ]]; then
        echo "$selected"
    else
        echo "${1:-}"
    fi
}
tui_input() {
    printf '[%s|%s]' "$1" "${2-__unset__}" >> "$input_log_file50"
    echo "${2:-}"
}
tui_confirm() {
    case "$1" in
        "Self-hosted instance?") return 0 ;;
        *) return 1 ;;
    esac
}
_wtx_install_steps3_7_config > "$tmpdir50/out" 2>"$tmpdir50/err"
choose_log50="$(cat "$choose_log_file50")"
input_log50="$(cat "$input_log_file50")"
assert_contains "idempotency merge: forge selected" "[Forge type|gitlab]" "$choose_log50"
assert_contains "idempotency merge: detection selected" "[Detection markers|Rust]" "$choose_log50"
assert_contains "idempotency merge: forge org default" "[Forge org / owner slug|team]" "$input_log50"
assert_contains "idempotency merge: base URL default" "[Base URL|https://git.example.internal]" "$input_log50"
assert_contains "idempotency merge: projects default" "[Known project dirs (comma-separated, optional)|api,web]" "$input_log50"
assert_contains "idempotency merge: branch default" "[Default base branch|develop]" "$input_log50"
assert_contains "idempotency merge: prefix default" "[Default branch prefix|feat]" "$input_log50"
assert_contains "idempotency merge: Jira note" "Jira mappings are not pre-filled" "$(cat "$tmpdir50/err")"
rm -rf "$tmpdir50"

# -- Case 51: merge Step 8 pre-selects existing setup_hook plugin
tmpdir51="$(mktemp -d)"
cat > "$tmpdir51/wtx.toml" <<'EOF51'
[worktree]
setup_hook = "plugins/android-setup.sh"
EOF51
export WORKSPACE_ROOT="$tmpdir51"
export WTX_ROOT="$REPO_ROOT"
export WTX_CONFIG="$tmpdir51/wtx.toml"
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
_WTX_INSTALL_MODE="merge"
choose_log_file51="$tmpdir51/choose.log"
: > "$choose_log_file51"
tui_choose() {
    local selected="" prompt
    if [[ "${1:-}" = "--selected" ]]; then
        selected="$2"; shift 2
    fi
    prompt="$1"; shift
    printf '[%s|%s]' "$prompt" "$selected" >> "$choose_log_file51"
    echo "$selected"
}
tui_input() { echo "${2:-}"; }
_wtx_install_step8_hook >/dev/null
choose_log51="$(cat "$choose_log_file51")"
assert_contains "idempotency merge: setup hook selected" "Setup hook (runs after worktree create)" "$choose_log51"
assert_contains "idempotency merge: setup hook plugin label" "android-setup.sh" "$choose_log51"
assert_eq "idempotency merge: setup_hook preserved" "plugins/android-setup.sh" "$setup_hook"
rm -rf "$tmpdir51"

# -- Case 52: merge accept-all-defaults preserves installer-emitted config values
tmpdir52="$(mktemp -d)"
export WORKSPACE_ROOT="$tmpdir52"
export WTX_ROOT="$REPO_ROOT"
forge_type="gitlab"
forge_org="team"
forge_base_url=""
projects_csv="api,web"
detection_csv="Cargo.toml"
base_branch="develop"
branch_prefix="feat"
setup_hook="plugins/android-setup.sh"
_WTX_JIRA_REPOS=()
_WTX_JIRA_KEYS=()
_wtx_install_emit_toml > "$tmpdir52/wtx.toml"
export WTX_CONFIG="$tmpdir52/wtx.toml"
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
_WTX_INSTALL_MODE="merge"
tui_choose() {
    local selected=""
    if [[ "${1:-}" = "--selected" ]]; then
        selected="$2"; shift 2
    fi
    [[ -n "$selected" ]] && { echo "$selected"; return 0; }
    echo "${2:-}"
}
tui_input() { echo "${2:-}"; }
tui_confirm() { return 1; }
_wtx_install_steps3_7_config >/dev/null 2>"$tmpdir52/steps.err"
_wtx_install_step8_hook >/dev/null
_wtx_install_emit_toml > "$tmpdir52/merged.toml"
unset _WTX_CONFIG_LOADED
export WTX_CONFIG="$tmpdir52/merged.toml"
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
assert_eq "idempotency merge defaults: forge.type" "gitlab" "$(wtx_config_get "forge.type" "")"
assert_eq "idempotency merge defaults: forge.org" "team" "$(wtx_config_get "forge.org" "")"
assert_eq "idempotency merge defaults: projects.list" "$(printf 'api\nweb')" "$(wtx_config_get_list "projects.list")"
assert_eq "idempotency merge defaults: detection.markers" "Cargo.toml" "$(wtx_config_get_list "detection.markers")"
assert_eq "idempotency merge defaults: base_branch" "develop" "$(wtx_config_get "defaults.base_branch" "")"
assert_eq "idempotency merge defaults: branch_prefix" "feat" "$(wtx_config_get "defaults.branch_prefix" "")"
assert_eq "idempotency merge defaults: setup_hook" "plugins/android-setup.sh" "$(wtx_config_get "worktree.setup_hook" "")"
rm -rf "$tmpdir52"
unset WTX_CONFIG

# -- Case 53: real second run choosing skip leaves wtx.toml byte-for-byte identical
tmpdir53="$(mktemp -d)"
mkdir -p "$tmpdir53/home" "$tmpdir53/repo" "$tmpdir53/prefix/bin"
( cd "$tmpdir53/repo" && git init -q )
_write_install_gum_shim "$tmpdir53/bin"
ln -s "$REPO_ROOT/bin/wtx" "$tmpdir53/prefix/bin/wtx"
(
    cd "$tmpdir53/repo" && \
    HOME="$tmpdir53/home" \
    PATH="$tmpdir53/bin:$tmpdir53/prefix/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir53/repo" \
    WTX_INSTALL_PREFIX="$tmpdir53/prefix" \
    WTX_GUM_HOOKS=no \
    WTX_GUM_GRADLE=no \
    WTX_GUM_PATH_HINT=no \
    bash "$WIZARD" >/dev/null 2>"$tmpdir53/first.err"
)
rc=$?
assert_eq "idempotency skip e2e: first run exits 0" 0 "$rc"
cp "$tmpdir53/repo/wtx.toml" "$tmpdir53/first.toml"
(
    cd "$tmpdir53/repo" && \
    HOME="$tmpdir53/home" \
    PATH="$tmpdir53/bin:$tmpdir53/prefix/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir53/repo" \
    WTX_INSTALL_PREFIX="$tmpdir53/prefix" \
    WTX_GUM_HOOKS=no \
    WTX_GUM_GRADLE=no \
    WTX_GUM_PATH_HINT=no \
    bash "$WIZARD" >/dev/null 2>"$tmpdir53/second.err"
)
rc=$?
assert_eq "idempotency skip e2e: second run exits 0" 0 "$rc"
cmp -s "$tmpdir53/first.toml" "$tmpdir53/repo/wtx.toml"
assert_ok "idempotency skip e2e: wtx.toml unchanged" $?
rm -rf "$tmpdir53"

# ---------------------------------------------------------------------------
# Story 1.5 QA gap coverage (Cases 54-59): gate option set (AC 1), run-level
# merge re-source wiring (AC 4), and the merge pre-fill branches not exercised
# by Cases 46-53 — detection "Custom…", Step 8 custom path, Step 8 "None".
# ---------------------------------------------------------------------------

# Restore real wizard functions after the E2E subshell cases.
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook
eval "$wizard_head" 2>/dev/null || true

# -- Case 54: gate with existing wtx.toml shows box + offers exactly skip/overwrite/merge (AC 1)
tmpdir54="$(mktemp -d)"
printf '[forge]\ntype = "github"\n' > "$tmpdir54/wtx.toml"
orig_sum54="$(cksum < "$tmpdir54/wtx.toml")"
export WORKSPACE_ROOT="$tmpdir54"
style_calls54=0
# tui_choose runs inside $(...) in the gate, so capture its args via a file.
choose_log_file54="$tmpdir54/choose.log"
: > "$choose_log_file54"
tui_style_box() { style_calls54=$((style_calls54 + 1)); }
tui_choose() {
    shift  # drop the prompt/header, leaving only the option list
    printf '%s' "$*" >> "$choose_log_file54"
    echo "merge"
}
_WTX_INSTALL_MODE=""
_wtx_install_step0_idempotency >/dev/null
assert_eq "idempotency gate: style box shown once" 1 "$style_calls54"
assert_eq "idempotency gate: chooser invoked once" 1 "$(grep -c . "$choose_log_file54")"
assert_eq "idempotency gate: offers exactly skip/overwrite/merge" "skip overwrite merge" "$(cat "$choose_log_file54")"
assert_eq "idempotency gate: assigns chosen mode" "merge" "$_WTX_INSTALL_MODE"
assert_eq "idempotency gate: file untouched before choice" "$orig_sum54" "$(cksum < "$tmpdir54/wtx.toml")"
rm -rf "$tmpdir54"
unset WORKSPACE_ROOT

# Restore real functions + config loader before the run-level merge test.
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook wtx_config_get wtx_config_get_list
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
eval "$wizard_head" 2>/dev/null || true

# -- Case 55: merge mode re-sources the config loader against the workspace wtx.toml (AC 4)
tmpdir55="$(mktemp -d)"
cat > "$tmpdir55/wtx.toml" <<'EOF55'
[forge]
type = "gitlab"
org = "merge-sentinel-org"
EOF55
unset WTX_CONFIG
_wtx_install_preflight() {
    WORKSPACE_ROOT="$tmpdir55"
    WTX_ROOT="$REPO_ROOT"
    WTX_INSTALL_DRY_RUN=0
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    export WORKSPACE_ROOT WTX_ROOT WTX_INSTALL_DRY_RUN
    return 0
}
tui_style_box() { :; }
tui_choose() { echo "merge"; }
_wtx_install_step_banner() { return 0; }
_wtx_install_step2_binary() { return 0; }
_wtx_install_steps3_7_config() { return 0; }
_wtx_install_step8_hook() { return 0; }
wtx_install_write_or_dryrun() { return 0; }
_wtx_install_step9_claude_hooks() { return 0; }
_wtx_install_step10_extras() { return 0; }
_WTX_CONFIG_LOADED=stale  # the merge block must reset this before re-sourcing
_wtx_install_run > "$tmpdir55/out" 2>"$tmpdir55/err"; rc=$?
assert_eq "idempotency merge run: exits 0" 0 "$rc"
assert_eq "idempotency merge run: WTX_CONFIG points at workspace toml" "$tmpdir55/wtx.toml" "$WTX_CONFIG"
assert_eq "idempotency merge run: loader guard reset then re-set" "1" "${_WTX_CONFIG_LOADED:-unset}"
assert_eq "idempotency merge run: re-sourced config is readable" "merge-sentinel-org" "$(wtx_config_get "forge.org" "")"
rm -rf "$tmpdir55"
unset WTX_CONFIG

# Restore real functions before the prompt-level merge branch tests.
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook _wtx_install_preflight
eval "$wizard_head" 2>/dev/null || true

# -- Case 56: merge detection markers with no preset match pre-selects Custom… and pre-fills the CSV (AC 4)
tmpdir56="$(mktemp -d)"
cat > "$tmpdir56/wtx.toml" <<'EOF56'
[detection]
markers = ["Makefile", "flake.nix"]
EOF56
export WORKSPACE_ROOT="$tmpdir56"
export WTX_ROOT="$REPO_ROOT"
export WTX_CONFIG="$tmpdir56/wtx.toml"
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
_WTX_INSTALL_MODE="merge"
# Captures go to files: tui_* run inside $(...) subshells, so var writes won't persist.
marker_sel_file56="$tmpdir56/marker.sel"
custom_input_file56="$tmpdir56/custom.in"
: > "$marker_sel_file56"
: > "$custom_input_file56"
tui_choose() {
    local selected=""
    if [[ "${1:-}" = "--selected" ]]; then selected="$2"; shift 2; fi
    local prompt="$1"; shift
    case "$prompt" in
        "Detection markers") printf '%s' "$selected" > "$marker_sel_file56"; echo "Custom…" ;;
        *) if [[ -n "$selected" ]]; then echo "$selected"; else echo "${1:-}"; fi ;;
    esac
}
tui_input() {
    [[ "$1" = "Detection markers (comma-separated)" ]] && printf '%s' "${2-__unset__}" > "$custom_input_file56"
    echo "${2:-}"
}
tui_confirm() { return 1; }
_wtx_install_steps3_7_config >/dev/null 2>&1
assert_eq "idempotency merge custom markers: pre-selects Custom…" "Custom…" "$(cat "$marker_sel_file56")"
assert_eq "idempotency merge custom markers: custom input pre-filled" "Makefile,flake.nix" "$(cat "$custom_input_file56")"
assert_eq "idempotency merge custom markers: detection_csv preserved" "Makefile,flake.nix" "$detection_csv"
rm -rf "$tmpdir56"
unset WTX_CONFIG WORKSPACE_ROOT

# -- Case 57: merge Step 8 with a non-plugin setup_hook pre-selects Custom path… and pre-fills it (AC 4)
tmpdir57="$(mktemp -d)"
cat > "$tmpdir57/wtx.toml" <<'EOF57'
[worktree]
setup_hook = "scripts/my-custom-hook.sh"
EOF57
export WORKSPACE_ROOT="$tmpdir57"
export WTX_ROOT="$REPO_ROOT"
export WTX_CONFIG="$tmpdir57/wtx.toml"
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
_WTX_INSTALL_MODE="merge"
hook_sel_file57="$tmpdir57/hook.sel"
custom_hook_file57="$tmpdir57/hook.in"
: > "$hook_sel_file57"
: > "$custom_hook_file57"
tui_choose() {
    local selected=""
    if [[ "${1:-}" = "--selected" ]]; then selected="$2"; shift 2; fi
    printf '%s' "$selected" > "$hook_sel_file57"
    echo "$selected"
}
tui_input() {
    [[ "$1" = "Relative path to setup hook script" ]] && printf '%s' "${2-__unset__}" > "$custom_hook_file57"
    echo "${2:-}"
}
_wtx_install_step8_hook >/dev/null
assert_eq "idempotency merge custom hook: pre-selects Custom path…" "Custom path…" "$(cat "$hook_sel_file57")"
assert_eq "idempotency merge custom hook: input pre-filled" "scripts/my-custom-hook.sh" "$(cat "$custom_hook_file57")"
assert_eq "idempotency merge custom hook: setup_hook preserved" "scripts/my-custom-hook.sh" "$setup_hook"
rm -rf "$tmpdir57"
unset WTX_CONFIG WORKSPACE_ROOT

# -- Case 58: merge Step 8 with no setup_hook pre-selects None and clears the hook (AC 4)
tmpdir58="$(mktemp -d)"
printf '[forge]\ntype = "github"\n' > "$tmpdir58/wtx.toml"
export WORKSPACE_ROOT="$tmpdir58"
export WTX_ROOT="$REPO_ROOT"
export WTX_CONFIG="$tmpdir58/wtx.toml"
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh" 2>/dev/null || true
_WTX_INSTALL_MODE="merge"
hook_sel_file58="$tmpdir58/hook.sel"
: > "$hook_sel_file58"
tui_choose() {
    local selected=""
    if [[ "${1:-}" = "--selected" ]]; then selected="$2"; shift 2; fi
    printf '%s' "$selected" > "$hook_sel_file58"
    echo "$selected"
}
tui_input() { echo "${2:-}"; }
_wtx_install_step8_hook >/dev/null
assert_eq "idempotency merge no hook: pre-selects None" "None" "$(cat "$hook_sel_file58")"
assert_eq "idempotency merge no hook: setup_hook empty" "" "$setup_hook"
rm -rf "$tmpdir58"
unset WTX_CONFIG WORKSPACE_ROOT

# -- Case 59: real preflight creates no TOML temp file before idempotency choice (AC 1)
unset -f _wtx_install_step0_idempotency _wtx_install_run _wtx_install_steps3_7_config _wtx_install_step8_hook _wtx_install_preflight _wtx_install_prepare_toml_tmp
eval "$wizard_head" 2>/dev/null || true
tmpdir59="$(mktemp -d)"
mkdir -p "$tmpdir59/repo"
( cd "$tmpdir59/repo" && git init -q )
printf '[forge]\ntype = "github"\n' > "$tmpdir59/repo/wtx.toml"
pre_choice_file59="$tmpdir59/pre-choice-temps"
: > "$pre_choice_file59"
_wtx_install_step0_idempotency() {
    find "$WORKSPACE_ROOT" -name '.wtx-install-tmp.*' -print > "$pre_choice_file59"
    _WTX_INSTALL_MODE="skip"
    return 0
}
_wtx_install_step9_claude_hooks() { return 0; }
_wtx_install_step10_extras() { return 0; }
(
    cd "$tmpdir59/repo" && \
    PATH="/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir59/repo" \
    _wtx_install_run > "$tmpdir59/out" 2>"$tmpdir59/err"
)
rc=$?
assert_eq "idempotency gate pre-choice temp: run exits 0" 0 "$rc"
assert_eq "idempotency gate pre-choice temp: no temp before choice" "" "$(cat "$pre_choice_file59")"
leftovers59="$(find "$tmpdir59/repo" -name '.wtx-install-tmp.*' -print)"
assert_eq "idempotency gate pre-choice temp: no leftovers" "" "$leftovers59"
rm -rf "$tmpdir59"
unset WORKSPACE_ROOT WTX_ROOT

# ---------------------------------------------------------------------------
# Story 1.6 dry-run end-to-end threading (Cases 60-68)
# ---------------------------------------------------------------------------

# Restore real wizard functions after Story 1.5 stubs.
unset -f _wtx_install_preflight _wtx_install_step0_idempotency _wtx_install_step_banner \
    _wtx_install_step2_binary _wtx_install_steps3_7_config _wtx_install_step8_hook \
    _wtx_install_step9_claude_hooks _wtx_install_step10_extras _wtx_install_step11_summary \
    _wtx_install_run wtx_install_write_or_dryrun
unset _WTX_INSTALL_LIB_LOADED
source "$LIB"
eval "$wizard_head" 2>/dev/null || true

# -- Case 60: dry-run helper still prints and skips command execution
tmpdir60="$(mktemp -d)"
marker60="$tmpdir60/marker"
WTX_INSTALL_DRY_RUN=0
_wtx_install_parse_args --dry-run
rc=$?
assert_eq "1.6 parse dry-run: returns 0" 0 "$rc"
assert_eq "1.6 parse dry-run: sets flag" "1" "$WTX_INSTALL_DRY_RUN"
bash -c '[[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]'
rc=$?
assert_eq "1.6 parse dry-run: exports flag" 0 "$rc"
WTX_INSTALL_DRY_RUN=1
out60="$(wtx_install_write_or_dryrun "would write: $marker60" touch "$marker60" 2>&1)"
rc=$?
assert_eq "1.6 helper dry-run: returns 0" 0 "$rc"
assert_eq "1.6 helper dry-run: exact preview line" "[dry-run] would write: $marker60" "$out60"
[[ ! -e "$marker60" ]]; assert_ok "1.6 helper dry-run: command skipped" $?
rm -rf "$tmpdir60"

# -- Case 61: Step 2 dry-run prepares --dry-run args, precise label, preview ledger
tmpdir61="$(mktemp -d)"
export WTX_ROOT="$REPO_ROOT"
export HOME="$tmpdir61/home"
WTX_INSTALL_DRY_RUN=1
WTX_INSTALL_PREFIX=""
PATH="/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step61_action=""
step61_args=""
tui_input() { printf '%s\n' "$tmpdir61/prefix"; }
wtx_install_write_or_dryrun() {
    step61_action="$1"
    shift
    step61_args="$(printf '<%s>' "$@")"
    return 0
}
_wtx_install_step2_binary >/dev/null
rc=$?
assert_eq "1.6 step2 dry-run: returns 0" 0 "$rc"
assert_eq "1.6 step2 dry-run: precise symlink label" "would symlink: $tmpdir61/prefix/bin/wtx -> $REPO_ROOT/bin/wtx" "$step61_action"
assert_eq "1.6 step2 dry-run: delegated args include dry-run" "<bash><$REPO_ROOT/install.sh><--prefix><$tmpdir61/prefix><--dry-run>" "$step61_args"
assert_eq "1.6 step2 dry-run: ledger key" "symlink" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "1.6 step2 dry-run: ledger previewed" "previewed (dry-run)" "${_WTX_LEDGER_VALS[0]:-}"
rm -rf "$tmpdir61"

# -- Case 62: Step 9 and Step 10 dry-run prepare --dry-run args and preview ledgers
tmpdir62="$(mktemp -d)"
export WTX_ROOT="$REPO_ROOT"
export WORKSPACE_ROOT="$tmpdir62/workspace"
export HOME="$tmpdir62/home"
export WTX_INSTALL_PREFIX="$tmpdir62/prefix"
mkdir -p "$WORKSPACE_ROOT"
WTX_INSTALL_DRY_RUN=1
PATH="$WTX_INSTALL_PREFIX/bin:/usr/bin:/bin"
_WTX_LEDGER_KEYS=()
_WTX_LEDGER_VALS=()
step62_actions=""
step62_args=""
tui_style_box() { for l in "$@"; do echo "  $l"; done; }
tui_confirm() { return 0; }
wtx_install_write_or_dryrun() {
    step62_actions="${step62_actions}[$1]"
    shift
    step62_args="${step62_args}$(printf '<%s>' "$@")|"
    return 0
}
_wtx_install_step9_claude_hooks >/dev/null
_wtx_install_step10_extras >/dev/null
assert_contains "1.6 step9 dry-run: precise hooks label" "[would copy: $REPO_ROOT/hooks/worktree-*.sh -> $WORKSPACE_ROOT/.claude/hooks/" "$step62_actions"
assert_contains "1.6 step9 dry-run: delegated args include dry-run" "<bash><$REPO_ROOT/install.sh><--hooks><--dry-run>" "$step62_args"
assert_contains "1.6 step10 dry-run: precise Gradle label" "[would copy: $REPO_ROOT/share/gradle/worktree-cache.init.gradle.kts -> $HOME/.gradle/init.d/worktree-cache.init.gradle.kts]" "$step62_actions"
assert_contains "1.6 step10 dry-run: delegated args include dry-run" "<bash><$REPO_ROOT/install.sh><--gradle><--dry-run>" "$step62_args"
assert_eq "1.6 step9 dry-run: ledger previewed" "previewed (dry-run)" "${_WTX_LEDGER_VALS[0]:-}"
assert_eq "1.6 step10 dry-run: ledger previewed" "previewed (dry-run)" "${_WTX_LEDGER_VALS[1]:-}"
rm -rf "$tmpdir62"

# -- Case 63: run-level dry-run config ledger is previewed and Step 11 note appears once
tmpdir63="$(mktemp -d)"
unset -f _wtx_install_run _wtx_install_step11_summary
eval "$wizard_head" 2>/dev/null || true
_wtx_install_preflight() {
    WORKSPACE_ROOT="$tmpdir63"
    WTX_ROOT="$REPO_ROOT"
    WTX_INSTALL_DRY_RUN=1
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    export WORKSPACE_ROOT WTX_ROOT WTX_INSTALL_DRY_RUN
    return 0
}
_wtx_install_step0_idempotency() { _WTX_INSTALL_MODE="overwrite"; return 0; }
_wtx_install_step_banner() { return 0; }
_wtx_install_step2_binary() { return 0; }
_wtx_install_steps3_7_config() { return 0; }
_wtx_install_step8_hook() { return 0; }
wtx_install_write_or_dryrun() { return 0; }
_wtx_install_step9_claude_hooks() { return 0; }
_wtx_install_step10_extras() { return 0; }
out63_file="$tmpdir63/out"
_wtx_install_run > "$out63_file" 2>&1
rc=$?
assert_eq "1.6 run dry-run config: exits 0" 0 "$rc"
assert_eq "1.6 run dry-run config: ledger key" "config" "${_WTX_LEDGER_KEYS[0]:-}"
assert_eq "1.6 run dry-run config: ledger previewed" "previewed (dry-run)" "${_WTX_LEDGER_VALS[0]:-}"
summary_count63="$(grep -F -c '[dry-run] No files were written. Remove --dry-run to apply.' "$out63_file" || true)"
assert_eq "1.6 run dry-run config: summary once" "1" "$summary_count63"
rm -rf "$tmpdir63"

# -- Case 64: skip dry-run keeps config ledger and still reaches Step 11 without hiding optional failures
tmpdir64="$(mktemp -d)"
printf '[forge]\ntype = "github"\n' > "$tmpdir64/wtx.toml"
_wtx_install_preflight() {
    WORKSPACE_ROOT="$tmpdir64"
    WTX_ROOT="$REPO_ROOT"
    WTX_INSTALL_DRY_RUN=1
    _WTX_LEDGER_KEYS=()
    _WTX_LEDGER_VALS=()
    export WORKSPACE_ROOT WTX_ROOT WTX_INSTALL_DRY_RUN
    return 0
}
_wtx_install_step0_idempotency() { _WTX_INSTALL_MODE="skip"; return 0; }
_wtx_install_step9_claude_hooks() { return 5; }
_wtx_install_step10_extras() { return 0; }
out64_file="$tmpdir64/out"
_wtx_install_run > "$out64_file" 2>&1
rc=$?
assert_eq "1.6 skip dry-run: preserves optional failure rc" 5 "$rc"
assert_eq "1.6 skip dry-run: config kept ledger" "kept (existing)" "${_WTX_LEDGER_VALS[0]:-}"
summary_count64="$(grep -F -c '[dry-run] No files were written. Remove --dry-run to apply.' "$out64_file" || true)"
assert_eq "1.6 skip dry-run: summary once" "1" "$summary_count64"
rm -rf "$tmpdir64"

# Restore real functions before static and E2E checks.
unset -f _wtx_install_preflight _wtx_install_step0_idempotency _wtx_install_step_banner \
    _wtx_install_step2_binary _wtx_install_steps3_7_config _wtx_install_step8_hook \
    _wtx_install_step9_claude_hooks _wtx_install_step10_extras _wtx_install_step11_summary \
    _wtx_install_run wtx_install_write_or_dryrun
unset _WTX_INSTALL_LIB_LOADED
source "$LIB"
eval "$wizard_head" 2>/dev/null || true

# -- Case 65: no direct install.sh execution path bypasses the dry-run guard
direct_bypass65="$(grep -n 'bash[[:space:]]*"\$WTX_ROOT/install\.sh"' "$WIZARD" || true)"
assert_eq "1.6 static: no direct install.sh bypass" "" "$direct_bypass65"

# -- Case 66: full dry-run without existing wtx.toml previews every write and creates no files
tmpdir66="$(mktemp -d)"
mkdir -p "$tmpdir66/home" "$tmpdir66/repo"
( cd "$tmpdir66/repo" && git init -q )
_write_install_gum_shim "$tmpdir66/bin"
gum_log66="$tmpdir66/gum.log"
out66="$(
    cd "$tmpdir66/repo" && \
    HOME="$tmpdir66/home" \
    PATH="$tmpdir66/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir66/repo" \
    WTX_GUM_LOG="$gum_log66" \
    WTX_GUM_INSTALL_PREFIX="$tmpdir66/prefix" \
    WTX_GUM_HOOKS=yes \
    WTX_GUM_GRADLE=yes \
    WTX_GUM_PATH_HINT=yes \
    bash "$WIZARD" --dry-run 2>&1
)"
rc=$?
assert_eq "1.6 e2e dry-run new: exits 0" 0 "$rc"
assert_contains "1.6 e2e dry-run new: symlink preview" "[dry-run] would symlink: $tmpdir66/prefix/bin/wtx -> $REPO_ROOT/bin/wtx" "$out66"
assert_contains "1.6 e2e dry-run new: TOML preview" "[dry-run] would write: $tmpdir66/repo/wtx.toml" "$out66"
assert_contains "1.6 e2e dry-run new: hooks preview" "[dry-run] would copy: $REPO_ROOT/hooks/worktree-*.sh -> $tmpdir66/repo/.claude/hooks/" "$out66"
assert_contains "1.6 e2e dry-run new: Gradle preview" "[dry-run] would copy: $REPO_ROOT/share/gradle/worktree-cache.init.gradle.kts -> $tmpdir66/home/.gradle/init.d/worktree-cache.init.gradle.kts" "$out66"
gum_log66_text="$(cat "$gum_log66")"
assert_contains "1.6 e2e dry-run new: hooks prompt runs" "confirm:Install Claude Code hooks?" "$gum_log66_text"
assert_contains "1.6 e2e dry-run new: Gradle prompt runs" "confirm:Install Gradle worktree-cache init script to ~/.gradle/init.d/?" "$gum_log66_text"
assert_contains "1.6 e2e dry-run new: PATH hint prompt runs" "confirm:Show PATH setup hint?" "$gum_log66_text"
summary_count66="$(printf '%s\n' "$out66" | grep -F -c '[dry-run] No files were written. Remove --dry-run to apply.' || true)"
assert_eq "1.6 e2e dry-run new: summary once" "1" "$summary_count66"
[[ ! -e "$tmpdir66/repo/wtx.toml" ]]; assert_ok "1.6 e2e dry-run new: no TOML write" $?
[[ ! -e "$tmpdir66/repo/.claude/hooks/worktree-create.sh" ]]; assert_ok "1.6 e2e dry-run new: no hooks write" $?
[[ ! -d "$tmpdir66/repo/.claude/hooks" ]]; assert_ok "1.6 e2e dry-run new: no hooks directory" $?
[[ ! -e "$tmpdir66/prefix/bin/wtx" ]]; assert_ok "1.6 e2e dry-run new: no symlink write" $?
[[ ! -e "$tmpdir66/home/.gradle/init.d/worktree-cache.init.gradle.kts" ]]; assert_ok "1.6 e2e dry-run new: no Gradle write" $?
leftovers66="$(find "$tmpdir66/repo" -name '.wtx-install-tmp.*' -print)"
assert_eq "1.6 e2e dry-run new: no TOML temp leftovers" "" "$leftovers66"
rm -rf "$tmpdir66"

# -- Case 67: existing wtx.toml + overwrite dry-run leaves file byte-for-byte unchanged
tmpdir67="$(mktemp -d)"
mkdir -p "$tmpdir67/home" "$tmpdir67/repo"
( cd "$tmpdir67/repo" && git init -q )
cat > "$tmpdir67/repo/wtx.toml" <<'EOF67'
[forge]
type = "github"
org = "existing"
EOF67
cp "$tmpdir67/repo/wtx.toml" "$tmpdir67/original.toml"
_write_install_gum_shim "$tmpdir67/bin"
gum_log67="$tmpdir67/gum.log"
out67="$(
    cd "$tmpdir67/repo" && \
    HOME="$tmpdir67/home" \
    PATH="$tmpdir67/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir67/repo" \
    WTX_GUM_LOG="$gum_log67" \
    WTX_GUM_IDEMPOTENCY_MODE=overwrite \
    WTX_GUM_INSTALL_PREFIX="$tmpdir67/prefix" \
    WTX_GUM_HOOKS=no \
    WTX_GUM_GRADLE=no \
    WTX_GUM_PATH_HINT=no \
    bash "$WIZARD" --dry-run 2>&1
)"
rc=$?
assert_eq "1.6 e2e dry-run overwrite: exits 0" 0 "$rc"
assert_contains "1.6 e2e dry-run overwrite: TOML preview" "[dry-run] would write: $tmpdir67/repo/wtx.toml" "$out67"
gum_log67_text="$(cat "$gum_log67")"
assert_contains "1.6 e2e dry-run overwrite: overwrite prompt runs" "choose:How do you want to proceed?" "$gum_log67_text"
assert_contains "1.6 e2e dry-run overwrite: forge prompt runs" "choose:Forge type" "$gum_log67_text"
assert_contains "1.6 e2e dry-run overwrite: org prompt runs" "input:Forge org / owner slug " "$gum_log67_text"
assert_contains "1.6 e2e dry-run overwrite: detection prompt runs" "choose:Detection markers" "$gum_log67_text"
assert_contains "1.6 e2e dry-run overwrite: defaults prompt runs" "input:Default base branch " "$gum_log67_text"
assert_contains "1.6 e2e dry-run overwrite: setup-hook prompt runs" "choose:Setup hook (runs after worktree create)" "$gum_log67_text"
cmp -s "$tmpdir67/original.toml" "$tmpdir67/repo/wtx.toml"
assert_ok "1.6 e2e dry-run overwrite: wtx.toml unchanged" $?
summary_count67="$(printf '%s\n' "$out67" | grep -F -c '[dry-run] No files were written. Remove --dry-run to apply.' || true)"
assert_eq "1.6 e2e dry-run overwrite: summary once" "1" "$summary_count67"
leftovers67="$(find "$tmpdir67/repo" -name '.wtx-install-tmp.*' -print)"
assert_eq "1.6 e2e dry-run overwrite: no TOML temp leftovers" "" "$leftovers67"
rm -rf "$tmpdir67"

# -- Case 68: existing wtx.toml + merge dry-run leaves file byte-for-byte unchanged
tmpdir68="$(mktemp -d)"
mkdir -p "$tmpdir68/home" "$tmpdir68/repo"
( cd "$tmpdir68/repo" && git init -q )
cat > "$tmpdir68/repo/wtx.toml" <<'EOF68'
[forge]
type = "gitlab"
org = "team"

[defaults]
base_branch = "develop"
branch_prefix = "feat"
EOF68
cp "$tmpdir68/repo/wtx.toml" "$tmpdir68/original.toml"
_write_install_gum_shim "$tmpdir68/bin"
gum_log68="$tmpdir68/gum.log"
out68="$(
    cd "$tmpdir68/repo" && \
    HOME="$tmpdir68/home" \
    PATH="$tmpdir68/bin:/usr/bin:/bin" \
    WTX_ROOT="$REPO_ROOT" \
    WORKSPACE_ROOT="$tmpdir68/repo" \
    WTX_GUM_LOG="$gum_log68" \
    WTX_GUM_IDEMPOTENCY_MODE=merge \
    WTX_GUM_INSTALL_PREFIX="$tmpdir68/prefix" \
    WTX_GUM_HOOKS=no \
    WTX_GUM_GRADLE=no \
    WTX_GUM_PATH_HINT=no \
    bash "$WIZARD" --dry-run 2>&1
)"
rc=$?
assert_eq "1.6 e2e dry-run merge: exits 0" 0 "$rc"
assert_contains "1.6 e2e dry-run merge: TOML preview" "[dry-run] would write: $tmpdir68/repo/wtx.toml" "$out68"
gum_log68_text="$(cat "$gum_log68")"
assert_contains "1.6 e2e dry-run merge: merge prompt runs" "choose:How do you want to proceed?" "$gum_log68_text"
assert_contains "1.6 e2e dry-run merge: config prompts run" "input:Default base branch " "$gum_log68_text"
cmp -s "$tmpdir68/original.toml" "$tmpdir68/repo/wtx.toml"
assert_ok "1.6 e2e dry-run merge: wtx.toml unchanged" $?
summary_count68="$(printf '%s\n' "$out68" | grep -F -c '[dry-run] No files were written. Remove --dry-run to apply.' || true)"
assert_eq "1.6 e2e dry-run merge: summary once" "1" "$summary_count68"
leftovers68="$(find "$tmpdir68/repo" -name '.wtx-install-tmp.*' -print)"
assert_eq "1.6 e2e dry-run merge: no TOML temp leftovers" "" "$leftovers68"
rm -rf "$tmpdir68"

echo
if [[ $FAILS -eq 0 ]]; then
    printf '%d/%d passed\n' "$TOTAL" "$TOTAL"
    exit 0
else
    printf '%d/%d passed, %d failed\n' "$((TOTAL - FAILS))" "$TOTAL" "$FAILS"
    exit 1
fi
