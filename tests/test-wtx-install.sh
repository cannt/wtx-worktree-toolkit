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
forge_choose_line="$(grep -n 'tui_choose "Forge type"' "$WIZARD" || true)"
assert_contains "forge: option github" '"github"' "$forge_choose_line"
assert_contains "forge: option gitlab" '"gitlab"' "$forge_choose_line"
assert_contains "forge: option bitbucket" '"bitbucket"' "$forge_choose_line"
case "$forge_choose_line" in
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
assert_eq "step9 dry-run: ledger done" "done" "${_WTX_LEDGER_VALS[0]:-}"
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

echo
if [[ $FAILS -eq 0 ]]; then
    printf '%d/%d passed\n' "$TOTAL" "$TOTAL"
    exit 0
else
    printf '%d/%d passed, %d failed\n' "$((TOTAL - FAILS))" "$TOTAL" "$FAILS"
    exit 1
fi
