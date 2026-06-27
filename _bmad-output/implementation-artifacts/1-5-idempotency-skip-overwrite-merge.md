---
baseline_commit: 45aefd1
---

# Story 1.5: Idempotency — skip / overwrite / merge

Status: done

## Story

As a developer running `wtx install` in a workspace that already has a `wtx.toml`,
I want the wizard to detect the existing config and offer me a clear choice between keeping it, overwriting it, or re-running prompts with my existing values pre-filled,
so that a second install run never silently clobbers my configuration.

**Prerequisite:** Story 1.1 is `done`. The wizard skeleton, `_wtx_install_preflight`, `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS`, and `wtx_install_write_or_dryrun` are defined in `lib/wtx-install.sh`. Story 1.4 is `done`; `_wtx_install_run` (lines 471-513 of `scripts/worktree-install.sh`) has a placeholder comment at lines 476-477 that this story replaces. Do not re-implement any primitive from Stories 1.1-1.4.

## Acceptance Criteria

1. Given `$WORKSPACE_ROOT/wtx.toml` exists when `wtx install` is invoked, when the idempotency gate runs (after `_wtx_install_preflight`, before `_wtx_install_step_banner`), then the wizard presents exactly three options: `skip`, `overwrite`, `merge` — no files are touched before this choice is made. [Source: epics.md#Story-1.5 / CAP-5, AD-13]

2. Given the user chooses `skip`, when the wizard proceeds, then no config prompts (Steps 1–8) are executed; exactly one ledger entry is appended: `config = "kept (existing)"`; the wizard jumps directly to Step 9 (hooks); `wtx.toml` is byte-for-byte identical after the run. [Source: epics.md#Story-1.5 / CAP-5, AD-13]

3. Given the user chooses `overwrite`, when the wizard proceeds, then the full wizard runs from Step 1 with empty defaults for all prompts; the final `wtx.toml` reflects only the new prompt answers; no values are pre-read from the existing file. [Source: epics.md#Story-1.5 / CAP-5]

4. Given the user chooses `merge`, when the wizard runs config prompts (Steps 3–8), then `unset _WTX_CONFIG_LOADED` is called, `WTX_CONFIG` is set to the existing `wtx.toml`, `lib/wtx-config.sh` is re-sourced, and each `tui_input` call receives the current config value as its second argument; `tui_choose` calls for forge type and detection markers receive the current value via `--selected`. [Source: epics.md#Story-1.5 / CAP-5, AD-6]

5. Given merge mode is active and the user accepts all defaults, when the new `wtx.toml` is written atomically (AD-4), then the file content is semantically equivalent to the original (same values, valid TOML); the original is overwritten only when the atomic move succeeds. [Source: epics.md#Story-1.5 / AD-4, AD-6]

6. Given `wtx install` is run twice with `skip` chosen on the second run, when both runs complete, then `diff` shows `wtx.toml` is byte-for-byte identical before and after. [Source: epics.md#Story-1.5 / CAP-5]

7. Given `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story, when syntax-check completes, then it exits 0 with no errors. [Source: project-context.md#Validation-commands]

## Tasks / Subtasks

- [x] Implement `_wtx_install_step0_idempotency` in `scripts/worktree-install.sh` (AC: 1-3, 5-6)
  - [x] Insert the function immediately before `_wtx_install_run` (around line 471).
  - [x] If `"$WORKSPACE_ROOT/wtx.toml"` does NOT exist: set `_WTX_INSTALL_MODE="overwrite"` and return 0 with no UI output.
  - [x] If it exists: display a `tui_style_box` indicating the file exists, then call `tui_choose "How do you want to proceed?" "skip" "overwrite" "merge"` and assign the result to `_WTX_INSTALL_MODE` (script-level variable, not `local`).
  - [x] **Do NOT call this function with command substitution** (`$(...)`) — `tui_style_box` and `tui_choose` write to stdout; calling via subshell would capture the UI output instead of showing it.

- [x] Update `_wtx_install_run` to branch on `_WTX_INSTALL_MODE` (AC: 1-3, 6)
  - [x] Replace the two placeholder comment lines 476-477 with `_wtx_install_step0_idempotency || return $?`.
  - [x] Immediately after, add the `skip` early-return block (see Implementation Strategy).
  - [x] Immediately before `_wtx_install_step_banner`, add the `merge` pre-load block (see Implementation Strategy).
  - [x] Keep Steps 1-8, TOML write, Step 9, and Step 10 calls fully intact for both `overwrite` and `merge` paths.

- [x] Add merge pre-fill to `_wtx_install_steps3_7_config` (AC: 4, 5)
  - [x] At the top of the function, declare pre-fill locals and populate them only when `_WTX_INSTALL_MODE = "merge"` (use `[[ "${_WTX_INSTALL_MODE:-}" = "merge" ]]`).
  - [x] Read each scalar with `wtx_config_get`; read arrays with `wtx_config_get_list | tr '\n' ',' | sed 's/,$//'` to convert to CSV.
  - [x] Update forge type `tui_choose` to use `--selected` via a local indexed array (see Implementation Strategy).
  - [x] Update `tui_input` calls for forge_org, forge_base_url, projects_csv, base_branch, branch_prefix to pass the pre-fill value as the second argument.
  - [x] For detection markers `tui_choose`: map the existing value to a preset option (see Implementation Strategy); if no preset matches, pre-select `"Custom…"` and pre-fill the custom `tui_input`.
  - [x] Jira mappings (Step 7): **do not pre-fill**. The `[jira.projects]` dotted-subtable uses variable key names that `wtx_config_get` cannot enumerate; start the Jira loop empty on all paths and print a one-line note to stderr when `_WTX_INSTALL_MODE = "merge"`: `printf 'note: Jira mappings are not pre-filled — re-enter them or skip.\n' >&2`.

- [x] Add merge pre-fill to `_wtx_install_step8_hook` (AC: 4)
  - [x] Read `_pf_setup_hook="$(wtx_config_get "worktree.setup_hook" "")"` when `_WTX_INSTALL_MODE = "merge"`.
  - [x] Build a local indexed array `_sel_args` and pass it to `tui_choose` for the hook list (same `--selected` pattern used for forge type).

- [x] Add Story 1.5 tests to `tests/test-wtx-install.sh` (AC: 1-7)
  - [x] Add `# Story 1.5 idempotency gate (Cases N+...)` section header after the Story 1.4 E2E block (currently ends around line 1043).
  - [x] Case: no `wtx.toml` → `_WTX_INSTALL_MODE` is `"overwrite"` after gate call; no `tui_choose` prompt invoked.
  - [x] Case: `wtx.toml` exists + choose `skip` → `_WTX_INSTALL_MODE="skip"`; no Steps 1-8 executed; ledger `_WTX_LEDGER_KEYS[0]="config"`, `_WTX_LEDGER_VALS[0]="kept (existing)"`; Steps 9-10 still called.
  - [x] Case: `wtx.toml` exists + choose `overwrite` → `_WTX_INSTALL_MODE="overwrite"`; no pre-fill reads; Steps 1-8 called normally.
  - [x] Case: `wtx.toml` exists + choose `merge` → config loader re-sourced; each `tui_input` receives existing value as default; forge type `tui_choose` receives `--selected` with existing value.
  - [x] Case: merge + accept-all-defaults → new `wtx.toml` is semantically equivalent to original (same key-value pairs, valid TOML structure).
  - [x] Case: two runs, `skip` on second → `diff "$first_toml" "$WORKSPACE_ROOT/wtx.toml"` is empty.
  - [x] Run full validation suite (see Testing Standards).

## Dev Notes

### Scope Boundary

This story implements **the idempotency gate only**: the `skip`/`overwrite`/`merge` prompt, the `_wtx_install_run` branching, and the merge pre-fill for Steps 3-8. Do not implement dry-run verification (Story 1.6) or Step 11 summary rendering / `wtx doctor` handoff (Story 1.7). Leave their placeholder comments untouched. Do not modify `lib/wtx-install.sh`, `lib/wtx-config.sh`, `lib/worktree-tui.sh`, or `install.sh`. [Source: epics.md#FR-Coverage-Map]

### Current Code State

`scripts/worktree-install.sh` — key areas to touch:

**`_wtx_install_run` (lines 471-513) — current shape:**
```bash
_wtx_install_run() {
    local _run_rc=0
    _wtx_install_preflight "$@" || return $?
    # Step 0 — idempotency gate (placeholder — Story 1.5 / AD-13)
    # _wtx_install_step0_idempotency          ← REPLACE THESE TWO LINES
    # Step 1 — Welcome banner
    _wtx_install_step_banner || return $?
    # Step 2 — Binary install
    _wtx_install_step2_binary || return $?
    # Steps 3–7 — Config prompts
    _wtx_install_steps3_7_config || return $?
    # Step 8 — Plugin discovery + setup-hook selection
    _wtx_install_step8_hook || return $?
    # Atomic TOML write
    wtx_install_write_or_dryrun "would write: $WORKSPACE_ROOT/wtx.toml" _wtx_install_commit_toml
    local toml_rc=$?
    if [[ $toml_rc -eq 0 && "${WTX_INSTALL_DRY_RUN:-0}" != "1" ]]; then
        _WTX_LEDGER_KEYS+=("config"); _WTX_LEDGER_VALS+=("done")
    elif [[ $toml_rc -ne 0 ]]; then
        _WTX_LEDGER_KEYS+=("config"); _WTX_LEDGER_VALS+=("failed")
        return $toml_rc
    fi
    # Step 9 — Claude Code hooks setup
    _wtx_install_step9_claude_hooks || _run_rc=$?
    # Step 10a/10b — Extras menu
    _wtx_install_step10_extras || _run_rc=$?
    # Step 11 — Completion summary + doctor handoff (placeholder — Story 1.7)
    # _wtx_install_step11_summary
    return $_run_rc
}
```

**`_wtx_install_steps3_7_config` (lines 177-235) — current step 3 prompts:**
```bash
forge_type="$(tui_choose "Forge type" "github" "gitlab" "bitbucket")"
forge_org="$(tui_input "Forge org / owner slug")"
```
All prompt calls need pre-fill support in merge mode.

**`_wtx_install_step8_hook` (line 240+)** — sets `setup_hook` via `tui_choose`; needs `--selected` support on merge.

### Implementation Strategy

**Gate function `_wtx_install_step0_idempotency`:**
```bash
_wtx_install_step0_idempotency() {
    _WTX_INSTALL_MODE="overwrite"
    [[ ! -f "$WORKSPACE_ROOT/wtx.toml" ]] && return 0
    tui_style_box \
        "wtx.toml already exists" \
        "  $WORKSPACE_ROOT/wtx.toml"
    _WTX_INSTALL_MODE="$(tui_choose "How do you want to proceed?" \
        "skip" "overwrite" "merge")"
}
```
`_WTX_INSTALL_MODE` is a script-level variable (not `local`) so `_wtx_install_run` sees it after the function returns without a subshell.

**Updated `_wtx_install_run` branching:**

Replace lines 476-477 (the two placeholder comment lines) with:
```bash
_wtx_install_step0_idempotency || return $?

if [[ "${_WTX_INSTALL_MODE:-overwrite}" = "skip" ]]; then
    _WTX_LEDGER_KEYS+=("config")
    _WTX_LEDGER_VALS+=("kept (existing)")
    _wtx_install_step9_claude_hooks || _run_rc=$?
    _wtx_install_step10_extras || _run_rc=$?
    return $_run_rc
fi

if [[ "${_WTX_INSTALL_MODE:-overwrite}" = "merge" ]]; then
    unset _WTX_CONFIG_LOADED
    WTX_CONFIG="$WORKSPACE_ROOT/wtx.toml"
    export WTX_CONFIG
    # shellcheck source=lib/wtx-config.sh
    source "$WTX_ROOT/lib/wtx-config.sh"
fi
```

This goes between `_wtx_install_preflight "$@" || return $?` and `_wtx_install_step_banner || return $?`. The `merge` pre-load block must come before `_wtx_install_step_banner` so the config is loaded before any prompt reads defaults.

**Pre-fill pattern for `tui_choose` with optional `--selected` (bash 3.2 safe):**
```bash
local _sel_args=()
[[ -n "$_pf_forge_type" ]] && _sel_args=("--selected" "$_pf_forge_type")
forge_type="$(tui_choose "${_sel_args[@]}" "Forge type" "github" "gitlab" "bitbucket")"
```
`"${_sel_args[@]}"` when the array is empty expands to zero arguments — correct bash 3.2 behavior (not `""`).

**Detection markers pre-fill in `_wtx_install_steps3_7_config`:**
```bash
local _pf_detection _pf_marker_preset
_pf_detection="$(wtx_config_get_list "worktree.detection_markers" | tr '\n' ',' | sed 's/,$//')"
case "$_pf_detection" in
    "")                                     _pf_marker_preset=".git (any git repo — default)" ;;
    "settings.gradle,settings.gradle.kts") _pf_marker_preset="Gradle / Android" ;;
    "Cargo.toml")                           _pf_marker_preset="Rust" ;;
    "package.json")                         _pf_marker_preset="Node.js" ;;
    *)                                      _pf_marker_preset="Custom…" ;;
esac
```
Pass `_pf_marker_preset` as `--selected` to the preset `tui_choose`. If the user lands on `"Custom…"` (either because they chose it or the existing value matched nothing), pre-fill the custom `tui_input` with `$_pf_detection`.

**Projects CSV pre-fill:**
```bash
local _pf_projects
_pf_projects="$(wtx_config_get_list "worktree.projects" | tr '\n' ',' | sed 's/,$//')"
# then:
projects_csv="$(tui_input "Known project dirs (comma-separated, optional)" "$_pf_projects")"
```

**Config keys used for merge pre-fill:**

| Variable in wizard | TOML section/key | `wtx_config_get` call |
|---|---|---|
| `forge_type` | `forge.type` | `wtx_config_get "forge.type" ""` |
| `forge_org` | `forge.org` | `wtx_config_get "forge.org" ""` |
| `forge_base_url` | `forge.base_url` | `wtx_config_get "forge.base_url" ""` |
| `projects_csv` | `worktree.projects` | `wtx_config_get_list "worktree.projects"` → CSV |
| `detection_csv` | `worktree.detection_markers` | `wtx_config_get_list "worktree.detection_markers"` → CSV |
| `base_branch` | `worktree.base_branch` | `wtx_config_get "worktree.base_branch" "main"` |
| `branch_prefix` | `worktree.branch_prefix` | `wtx_config_get "worktree.branch_prefix" "feature"` |
| `setup_hook` | `worktree.setup_hook` | `wtx_config_get "worktree.setup_hook" ""` |
| Jira mappings | `jira.projects.*` | **Not pre-filled** (variable key names) |

### Previous Story Intelligence

- Story 1.4 established that `_wtx_install_step9_claude_hooks` and `_wtx_install_step10_extras` are called with `|| _run_rc=$?` so optional failures don't abort later steps. The `skip` path must mirror this exact pattern (not `|| return $?`). [Source: 1-4-extras-menu-gradle-init-path-hint-step-10.md#Tasks]
- Story 1.4 debug log: "corrected test output capture from command substitution to file redirection so ledger mutations are observed in the same shell." Tests for 1.5 must follow the same file-redirection pattern for any function that mutates `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS`. [Source: 1-4-extras-menu-gradle-init-path-hint-step-10.md#Debug-Log-References]
- Story 1.3 review noted a working-directory bug fixed by `cd "$WORKSPACE_ROOT"` before `install.sh --hooks`. Story 1.5 does not call `install.sh` directly (only the gate + config re-source), so no `cd` is needed here. [Source: 1-4-extras-menu-gradle-init-path-hint-step-10.md#Previous-Story-Intelligence]
- Story 1.2 notes: `WTX_INSTALL_PREFIX` is set and exported in Step 2. On the `skip` path, Step 2 never runs, so `WTX_INSTALL_PREFIX` may be unset when Step 10 later runs. Story 1.4 already handles this with `local prefix="${WTX_INSTALL_PREFIX:-$HOME/.local}"` — do not change that guard; the `skip` path is safe. [Source: 1-4-extras-menu-gradle-init-path-hint-step-10.md#Current-Code-State]

### Architecture Guardrails

- **Do NOT call `_wtx_install_step0_idempotency` via command substitution.** The function must set `_WTX_INSTALL_MODE` as a script-level variable and be called bare: `_wtx_install_step0_idempotency || return $?`. Command substitution would capture TUI stdout output instead of displaying it. [Source: ARCHITECTURE-SPINE.md#Dependency-direction]
- **Config re-source on merge path uses the public API**: `unset _WTX_CONFIG_LOADED` then `source "$WTX_ROOT/lib/wtx-config.sh"`. The guard `_WTX_CONFIG_LOADED` makes the lib idempotent — resetting it allows the re-source. Never re-parse `wtx.toml` ad-hoc. [Source: ARCHITECTURE-SPINE.md#AD-6 / project-context.md#Framework-Specific-Rules]
- **Bash 3.2**: use indexed arrays `local _sel_args=()` for optional `--selected` args to `tui_choose`. No `declare -A`, no `${var^^}`, no `mapfile`. [Source: project-context.md#Language-Specific-Rules]
- **`set -u` only, never `set -e`**. Access `_WTX_INSTALL_MODE` with `"${_WTX_INSTALL_MODE:-overwrite}"` to avoid unbound-variable errors if somehow unset. [Source: project-context.md#Language-Specific-Rules]
- **All prompts in `worktree-install.sh` must go through `tui_*` functions.** The `tui_choose` call in the gate function satisfies AD-10. Do not add bare `read` calls. [Source: ARCHITECTURE-SPINE.md#AD-10]
- **Append exactly one `config` ledger entry on every path**: `"done"` / `"failed"` from the TOML write (existing logic), `"kept (existing)"` on the `skip` path. Story 1.7 depends on a complete ordered ledger. [Source: ARCHITECTURE-SPINE.md#AD-7]
- **Quote every path expansion**: `"$WORKSPACE_ROOT/wtx.toml"`, `"$WTX_ROOT/lib/wtx-config.sh"`, `"$WORKSPACE_ROOT"`. [Source: project-context.md#Critical-Dont-Miss-Rules]

### Testing Standards

Required after implementation — all must pass:

```bash
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh
bash tests/test-wtx-config.sh
bash tests/test-wtx-dispatcher.sh
bash tests/test-wtx-install.sh
bash tests/test-install.sh
bash tests/test-worktree-registry.sh
```

### Project Structure Notes

**Files to modify:**
- `scripts/worktree-install.sh` — add `_wtx_install_step0_idempotency`, update `_wtx_install_run`, add merge pre-fill to `_wtx_install_steps3_7_config` and `_wtx_install_step8_hook`
- `tests/test-wtx-install.sh` — add Story 1.5 focused tests after the Story 1.4 E2E block

**Do not modify:** `lib/wtx-install.sh`, `lib/wtx-config.sh`, `lib/worktree-tui.sh`, `install.sh`, `bin/wtx`.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.5-Idempotency]
- [Source: _bmad-output/planning-artifacts/epics.md#FR17 / FR18]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-6]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-13]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10]
- [Source: scripts/worktree-install.sh#_wtx_install_run (lines 471-513)]
- [Source: scripts/worktree-install.sh#_wtx_install_steps3_7_config (lines 177-235)]
- [Source: scripts/worktree-install.sh#_wtx_install_step8_hook (line 240+)]
- [Source: lib/worktree-tui.sh#tui_choose (line 113 — --selected flag)]
- [Source: lib/worktree-tui.sh#tui_input (line 193 — second arg is default_value)]
- [Source: _bmad-output/implementation-artifacts/1-4-extras-menu-gradle-init-path-hint-step-10.md#Debug-Log-References]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]
- [Source: _bmad-output/project-context.md#Testing-Rules]

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- Config keys in `_wtx_install_steps3_7_config` use the actual emitted TOML section names (`projects.list`, `detection.markers`, `defaults.base_branch`, `defaults.branch_prefix`) — not the `worktree.*` keys listed in the Dev Notes table, which were inconsistent with the emitter. Verified against `_wtx_install_emit_toml` before writing.
- `_wtx_install_step8_hook` pre-fill uses a plugin-label lookup loop rather than a simple `--selected "$_pf_setup_hook"` because the display list uses `"filename — desc"` labels; passing the raw path would not match.
- `tui_confirm "Self-hosted instance?"` in merge mode: when `_pf_forge_base_url` is non-empty, the confirm prompt receives `"${_pf_forge_base_url:+yes}"` as default so the existing base URL surfaces naturally.
- 2026-06-27: Senior review found the full run still created `.wtx-install-tmp.*` during preflight before the idempotency choice. Fixed by deferring TOML temp allocation until `_wtx_install_commit_toml`, so skip and dry-run paths do not touch a TOML temp file before the gate.
- 2026-06-27: Review validation passed: `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`; `bash tests/test-wtx-config.sh` (26/26); `bash tests/test-wtx-dispatcher.sh` (22/22); `bash tests/test-wtx-install.sh` (224/224); `bash tests/test-install.sh` (25/25); `bash tests/test-worktree-registry.sh` (19/19).

### Completion Notes List

- Implemented `_wtx_install_step0_idempotency`: sets `_WTX_INSTALL_MODE="overwrite"` (no-op when no TOML), shows `tui_style_box` + `tui_choose` when file exists. Called bare (not via command substitution) so TUI output goes to the terminal.
- Updated `_wtx_install_run`: replaced two placeholder comment lines with real call + `skip` early-return block + `merge` config-reload block (unset loader guard, set `WTX_CONFIG`, re-source `lib/wtx-config.sh`).
- Updated `_wtx_install_steps3_7_config`: added pre-fill locals populated only when `_WTX_INSTALL_MODE=merge`; forge type/detection markers use `--selected` via indexed arrays; `tui_input` calls pass pre-fill as second arg; Jira loop unchanged with stderr note on merge.
- Updated `_wtx_install_step8_hook`: reads `worktree.setup_hook`; resolves plugin label via discovery array for `--selected`; falls back to `"Custom path…"` for custom or unmatched paths.
- Added Story 1.5 assertions (Cases 46-53) covering: no-file mode, skip path, overwrite path, merge pre-fill, merge round-trip semantic equivalence, two-run skip diff, and E2E via real wizard with gum shim.
- All 202/202 install tests pass; 26/26 config, 22/22 dispatcher, 19/19 registry, 25/25 install.sh; syntax check clean.
- Senior review added QA gap coverage (Cases 54-59) for existing-file gate options, merge re-source wiring, custom marker/hook merge paths, empty hook merge path, and the run-level no-temp-before-choice guarantee.
- Senior review auto-fixed TOML temp allocation timing: preflight now registers cleanup with an empty `_WTX_INSTALL_TMP`; the temp file is allocated only when the real TOML commit command runs.

### Senior Developer Review (AI)

Reviewer: Codex on 2026-06-27

Outcome: Approved after auto-fix. No critical issues remain.

Inputs loaded:
- Story file: `_bmad-output/implementation-artifacts/1-5-idempotency-skip-overwrite-merge.md`
- Story context: no separate story-context file found; reviewed story, epics, project context, architecture spine, wizard source, installer lib/config/TUI helpers, sprint status, and tests.
- Epic tech spec: no standalone epic tech spec found; reviewed `_bmad-output/planning-artifacts/epics.md` and `_bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md`.
- Tech stack: pure Bash targeting bash 3.2, shell-only tests.
- MCP/doc search: no MCP documentation resources were available in this environment.

Findings fixed:
- HIGH: `_wtx_install_preflight` created `.wtx-install-tmp.*` before `_wtx_install_step0_idempotency`, so a full `wtx install` touched a workspace file before the user chose `skip`, `overwrite`, or `merge`, violating AC 1's no-files-touched-before-choice requirement. Fixed by deferring temp allocation to `_wtx_install_commit_toml`; added Case 59 to assert the real preflight has no pre-choice TOML temp files.
- MEDIUM: QA coverage did not exercise several Story 1.5 branches at run level: existing-file gate option set, merge config re-source, custom detection markers, custom setup hook, and empty setup hook. Fixed with Cases 54-58.
- MEDIUM: `_bmad-output/implementation-artifacts/tests/test-summary.md` was changed by QA automation but missing from the story File List. Fixed by adding it below.

Validation:
- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` passed.
- `bash tests/test-wtx-config.sh` passed: 26/26.
- `bash tests/test-wtx-dispatcher.sh` passed: 22/22.
- `bash tests/test-wtx-install.sh` passed: 224/224.
- `bash tests/test-install.sh` passed: 25/25.
- `bash tests/test-worktree-registry.sh` passed: 19/19.

### File List

- `scripts/worktree-install.sh`
- `tests/test-wtx-install.sh`
- `_bmad-output/implementation-artifacts/1-5-idempotency-skip-overwrite-merge.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `_bmad-output/implementation-artifacts/tests/test-summary.md`
- `_bmad-output/story-automator/orchestration-1-20260626-224222.md`

## Change Log

- 2026-06-27: Story 1.5 — Idempotency gate. Added `_wtx_install_step0_idempotency` function; updated `_wtx_install_run` with skip/merge branching; added merge pre-fill to `_wtx_install_steps3_7_config` and `_wtx_install_step8_hook`; added Story 1.5 assertions in `tests/test-wtx-install.sh` (Cases 46-53).
- 2026-06-27: Code review — deferred TOML temp allocation until commit time, added Case 59 for no pre-choice temp files, retained QA gap coverage Cases 54-58, updated File List, and marked status done.

## Story Completion Status

done
