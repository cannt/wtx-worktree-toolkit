---
baseline_commit: f2c9e12fa49c084801742ffe06ca26452f6ec78f
---

# Story 1.1: Wizard shell, shared write primitives & preflight

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a wtx developer,
I want `wtx install` routed through the standard dispatcher, the shared write/escape/dry-run primitive helpers defined in `lib/wtx-install.sh`, and the wizard skeleton in place with correct path resolution and preflight sequence,
so that all subsequent installer stories can depend on a stable, tested foundation and no story other than 1.1 needs to implement or re-implement these cross-cutting primitives.

## Acceptance Criteria

1. Given `bin/wtx` is invoked as `wtx install` or `wtx install --dry-run`, when the dispatcher runs, then it calls `_wtx_exec_script "worktree-install.sh" "$@"`; no alternative entry point exists; `_wtx_usage` and COMMANDS list include `install`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-1--Dispatcher-routing]
2. Given the new file `lib/wtx-install.sh` is sourced, when it is sourced more than once in the same shell, then the `_WTX_INSTALL_LIB_LOADED` guard prevents re-execution; `_wtx_toml_escape`, `_wtx_csv_to_toml_array`, `wtx_install_discover_plugins`, and `wtx_install_write_or_dryrun` are defined exactly once. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-2--File-layout]
3. Given `_wtx_toml_escape` and `_wtx_csv_to_toml_array` currently live inline in `bin/wtx`, when this story is complete, then both functions are moved to `lib/wtx-install.sh`; `bin/wtx` sources the lib before calling `_wtx_init`; existing `wtx init` behavior is unchanged. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: bin/wtx#Small-helpers]
4. Given `wtx_install_write_or_dryrun <action-label> <cmd...>` is called with `WTX_INSTALL_DRY_RUN=0`, when it executes, then it runs `<cmd...>` and returns that command's exit code; no `[dry-run]` output is produced. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
5. Given `wtx_install_write_or_dryrun <action-label> <cmd...>` is called with `WTX_INSTALL_DRY_RUN=1`, when it executes, then it prints a `[dry-run] <action-label>` line and returns 0 without executing `<cmd...>`; the command is never invoked. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Dry-run-visual-difference]
6. Given `scripts/worktree-install.sh` is invoked directly or via dispatcher, when it starts, then it resolves `WTX_ROOT` and `WORKSPACE_ROOT` using the same symlink-safe `BASH_SOURCE[0]` walk and `git rev-parse --path-format=absolute --git-common-dir` pattern as existing `scripts/worktree-*.sh` files. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: scripts/worktree-start.sh#WTX_ROOT-resolution]
7. Given Step 0 preflight executes, when the wizard starts, then the order is exactly: parse `--dry-run` and export `WTX_INSTALL_DRY_RUN=1` or `0`; run `git rev-parse --git-dir` and exit 1 with `wtx install: not in a git repository` when outside a repo; run `command -v gum` and set `GUM_AVAILABLE`. No prompt, `tui_*` call, temp file creation, or write occurs before these checks complete. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-12--Preflight-sequence]
8. Given `gum` is absent when the wizard starts, when Step 0 completes, then a single notice line is printed to stdout: `note: gum not found — using plain prompts (install with: brew install gum)`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-0--Preflight]
9. Given the wizard registers its cleanup trap at startup, when the trap is in place, then `trap 'rm -f "$_WTX_INSTALL_TMP"' EXIT` is registered; `_WTX_INSTALL_TMP` is the path returned by `mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX"`; Story 1.2's TOML write uses `$_WTX_INSTALL_TMP` as the intermediate file and `mv` to place it. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-4--Atomic-TOML-write]
10. Given the wizard skeleton initializes at startup, when initialization runs before any step appends to the ledger, then `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` are initialized as empty bash 3.2 indexed arrays (`_WTX_LEDGER_KEYS=()` and `_WTX_LEDGER_VALS=()`); subsequent stories append to them and Story 1.7 iterates them. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]
11. Given `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story, when syntax-check completes, then it exits 0 with no errors. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight] [Source: _bmad-output/project-context.md#Technology-Stack--Versions]

## Tasks / Subtasks

- [x] Route `wtx install` through the dispatcher (AC: 1)
  - [x] Update `bin/wtx` usage text and COMMANDS list to include `install`.
  - [x] Add `install)` case arm that delegates with `_wtx_exec_script "worktree-install.sh" "$@"`.
  - [x] Preserve existing `start`, `done`, `status`, `init`, `doctor`, `version`, and `help` behavior.
- [x] Create shared installer library `lib/wtx-install.sh` (AC: 2, 3, 4, 5)
  - [x] Add shebang-compatible sourceable module style with `set -u` assumptions but no top-level side effects beyond definitions.
  - [x] Guard with `_WTX_INSTALL_LIB_LOADED` so repeated sourcing is idempotent.
  - [x] Move `_wtx_toml_escape` and `_wtx_csv_to_toml_array` from `bin/wtx` into this lib without changing output behavior.
  - [x] Implement `wtx_install_discover_plugins` per AD-8 even though full Step 8 UI is Story 1.2, so the primitive exists for downstream stories.
  - [x] Implement `wtx_install_write_or_dryrun <action-label> <cmd...>` as the single dry-run/write chokepoint.
- [x] Update `bin/wtx` to source `lib/wtx-install.sh` (AC: 2, 3)
  - [x] Source via `$WTX_ROOT/lib/wtx-install.sh` after `WTX_ROOT` is resolved and before `_wtx_init` can run.
  - [x] Do not source `install.sh`; it remains a subprocess-only lower layer.
  - [x] Keep `wtx init` writing the same TOML shape and escaping edge cases.
- [x] Add wizard skeleton `scripts/worktree-install.sh` (AC: 6, 7, 8, 9, 10)
  - [x] Use existing `scripts/worktree-start.sh` path-resolution pattern for direct invocation fallback.
  - [x] Source `lib/wtx-install.sh`, `lib/wtx-config.sh`, and `lib/worktree-tui.sh` through `$WTX_ROOT`; include the same inline `worktree-tui.sh` stub fallback pattern used by existing scripts.
  - [x] Parse only `--dry-run` for this story; reject unknown options with a `wtx install:` stderr message and exit 2.
  - [x] Export `WTX_INSTALL_DRY_RUN=1` or `0` before any git/gum/tui/write work.
  - [x] Check git repo second with `git rev-parse --git-dir`; outside a repo, print `wtx install: not in a git repository` to stderr and exit 1.
  - [x] Detect `gum` third, set/export `GUM_AVAILABLE`, and print the no-gum notice once to stdout when absent.
  - [x] Allocate `_WTX_INSTALL_TMP` with `mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX"` after the git check succeeds; register the exact cleanup trap.
  - [x] Initialize `_WTX_LEDGER_KEYS=()` and `_WTX_LEDGER_VALS=()` as bash 3.2 indexed arrays.
  - [x] Keep later wizard steps as explicit no-op placeholders or minimal functions only; do not implement Stories 1.2-1.7 behavior here.
- [x] Add or update focused tests (AC: 1-11)
  - [x] Extend `tests/test-wtx-dispatcher.sh` to assert help output includes `install` and dispatcher routing reaches `scripts/worktree-install.sh`.
  - [x] Move helper assertions currently sourced from `bin/wtx` to cover `lib/wtx-install.sh` directly, while keeping a regression that `bin/wtx` still exposes the helpers to `_wtx_init`.
  - [x] Add dry-run helper tests verifying command execution vs skipped execution and exit-code propagation.
  - [x] Add plugin discovery tests using scratch plugin files, including missing `# wtx-plugin-desc:` fallback to filename stem.
  - [x] Add `scripts/worktree-install.sh` preflight tests for `--dry-run`, outside-git failure, no-gum notice, temp cleanup, and bash syntax.
  - [x] Run the full local validation set listed in Dev Notes.

## Dev Notes

### Scope Boundary

- This story creates the foundation only: dispatcher arm, shared installer lib, wizard script skeleton, Step 0 preflight, temp/trap primitive, and empty ledger arrays. Do not implement config prompts, TOML generation from prompts, hooks installation UI, extras UI, idempotency UI, full dry-run threading, or completion summary. Those are Stories 1.2-1.7. [Source: _bmad-output/planning-artifacts/epics.md#FR-Coverage-Map]
- `install.sh` is unchanged by this feature; the wizard will delegate to it in later stories. Do not move symlink, hooks, or Gradle file-operation logic out of `install.sh`. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]
- `lib/wtx-config.sh` and `lib/worktree-tui.sh` are unchanged by this feature; source and reuse them. [Source: _bmad-output/planning-artifacts/epics.md#NonFunctional-Requirements]

### Current Files To Touch

- `bin/wtx` currently owns `_wtx_toml_escape` and `_wtx_csv_to_toml_array`, then uses both inside `_wtx_init`. Move the definitions, not the behavior. Preserve the current escaping order: backslash first, then double quote. Preserve CSV behavior: disable globbing, split on commas, trim whitespace, drop empty items, TOML-escape each item. [Source: bin/wtx#Small-helpers] [Source: tests/test-wtx-dispatcher.sh#Case-6]
- `bin/wtx` already has the correct symlink-safe `WTX_ROOT` resolution and `WORKSPACE_ROOT` resolution using `git rev-parse --path-format=absolute --git-common-dir`; keep that dispatcher pattern intact and only add the `install` command. [Source: bin/wtx#WTX_ROOT-resolution] [Source: bin/wtx#WORKSPACE_ROOT-resolution]
- `scripts/worktree-start.sh` is the closest template for direct script invocation fallback and inline `worktree-tui.sh` stub sourcing. Copy the pattern conceptually, but rename installer-specific variables/functions with `WTX_INSTALL_*` and `_wtx_install_*`. [Source: scripts/worktree-start.sh#WTX_ROOT-resolution]
- `tests/test-wtx-dispatcher.sh` currently sources `bin/wtx` to test TOML helpers. After moving helpers to `lib/wtx-install.sh`, preserve those assertions either by sourcing the new lib directly or by verifying both the lib and sourced dispatcher path. [Source: tests/test-wtx-dispatcher.sh#Case-6]

### Architecture Guardrails

- Dependency direction is fixed: `bin/wtx` dispatches down to `scripts/worktree-install.sh`; the wizard sources libs and calls `install.sh` only as a subprocess. No lower layer calls back up. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Design-Paradigm]
- `lib/wtx-install.sh` is the only home for `_wtx_toml_escape`, `_wtx_csv_to_toml_array`, `wtx_install_discover_plugins`, and `wtx_install_write_or_dryrun`. After this story, `rg '_wtx_toml_escape|_wtx_csv_to_toml_array'` should show definitions only in `lib/wtx-install.sh`; call sites may remain in `bin/wtx` and future wizard code. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-2--File-layout]
- `wtx_install_discover_plugins` should output newline-separated `filename<TAB>description` pairs from `$WTX_ROOT/plugins/*.sh`, using the first `# wtx-plugin-desc:` line when present and filename stem when absent. It should not prepend `None` or `Custom path...`; the wizard UI owns that in Story 1.2. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-8--Plugin-discovery]
- `wtx_install_write_or_dryrun` must be command-generic. In dry-run mode it prints exactly the action label prefixed with `[dry-run]` and does not execute the command. In real mode it executes the command and returns the command's exit code. This helper is the only place in the wizard/lib that decides whether a write command runs. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
- Step 0 order is dry-run parse, git check, gum detection. Ignore the older `.memlog.md` line that says git/gum/dry-run; it conflicts with the adopted architecture spine and epics. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-12--Preflight-sequence] [Source: _bmad-output/planning-artifacts/epics.md#Functional-Requirements]

### Bash And Portability Rules

- Target bash 3.2. Use indexed arrays only; no `declare -A`, `mapfile`, `readarray`, `${var^^}`, `${var,,}`, process substitution into arrays, or `readlink -f`. [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- Use `set -u` only. Do not add `set -e`; explicit return-code checks are required for optional-tool and file-operation paths. [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- Quote all path expansions, especially `"$WTX_ROOT"`, `"$WORKSPACE_ROOT"`, `"$WTX_INSTALL_TMP"`, and command arguments passed through `wtx_install_write_or_dryrun`. [Source: _bmad-output/project-context.md#Critical-Dont-Miss-Rules]
- Do not use `eval`, ad-hoc TOML parsers, or new dependencies. The runtime remains shell-only. [Source: _bmad-output/project-context.md#Technology-Stack--Versions]
- External check: GNU Bash documents indexed arrays and associative arrays, with associative arrays created by `declare -A`; because macOS ships bash 3.2, the project rule to use indexed arrays and avoid associative arrays remains the correct compatibility constraint. [Source: https://www.gnu.org/software/bash/manual/bash.html#Arrays]
- External check: Gum provides `choose`, `confirm`, `input`, `style`, and related prompt commands, but this project must keep gum optional and always provide pure-bash fallbacks. [Source: https://github.com/charmbracelet/gum#commands]

### Testing Standards

- Required syntax check:
  - `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- Required regression tests after this story:
  - `bash tests/test-wtx-config.sh`
  - `bash tests/test-wtx-dispatcher.sh`
  - `bash tests/test-install.sh`
  - `bash tests/test-worktree-registry.sh`
- Add focused tests in the existing shell-script style. Do not add bats, shunit2, CI tooling, package managers, or a new test harness. [Source: _bmad-output/project-context.md#Testing-Rules]

### Recent Repository Context

- Recent commits are mostly planning/harness work: `0e2a362` added BMAD planning artifacts for this feature, `ac21a46` added `scripts/secret-scan.sh`, and `f2c9e12` wired story automator settings. No prior implementation story exists for Epic 1, so there are no previous story learnings to incorporate. [Source: git log --oneline -5]
- Worktree has untracked `_bmad-output/story-automator/` files. They are unrelated to this story and should not be modified as part of implementation unless a later workflow explicitly asks for it. [Source: git status --short]

## Project Structure Notes

- New files expected:
  - `lib/wtx-install.sh`
  - `scripts/worktree-install.sh`
- Existing file expected to change:
  - `bin/wtx`
- Existing tests expected to change or be added within:
  - `tests/test-wtx-dispatcher.sh`
  - Optionally a new shell test under `tests/` if keeping install-lib/preflight tests separate is clearer.
- Files expected to remain behaviorally unchanged:
  - `install.sh`
  - `lib/wtx-config.sh`
  - `lib/worktree-tui.sh`
  - existing `scripts/worktree-start.sh`, `scripts/worktree-done.sh`, `scripts/worktree-status.sh`
- Naming must follow existing layout: kebab-case files, `wtx_install_*` public functions in `lib/wtx-install.sh`, `_wtx_install_*` private wizard helpers in `scripts/worktree-install.sh`, `WTX_INSTALL_*` exported/session variables, `_WTX_INSTALL_*` script-local state. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Consistency-Conventions]

## References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.1-Wizard-shell-shared-write-primitives--preflight]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-1--Dispatcher-routing]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-2--File-layout]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-4--Atomic-TOML-write]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-8--Plugin-discovery]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-12--Preflight-sequence]
- [Source: _bmad-output/specs/spec-wtx-install/SPEC.md#Capabilities]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-0--Preflight]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]
- [Source: bin/wtx#Small-helpers]
- [Source: scripts/worktree-start.sh#WTX_ROOT-resolution]
- [Source: tests/test-wtx-dispatcher.sh#Case-6]
- [Source: https://www.gnu.org/software/bash/manual/bash.html#Arrays]
- [Source: https://github.com/charmbracelet/gum#commands]

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- 2026-06-27: Red phase confirmed focused install tests failed before `lib/wtx-install.sh`, `scripts/worktree-install.sh`, and dispatcher routing existed.
- 2026-06-27: Validation passed: `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`; `bash tests/test-wtx-config.sh`; `bash tests/test-wtx-dispatcher.sh`; `bash tests/test-wtx-install.sh`; `bash tests/test-install.sh`; `bash tests/test-worktree-registry.sh`.

### Completion Notes List

- Ultimate context engine analysis completed - comprehensive developer guide created.
- Discovery loaded epics, architecture spine, SPEC, UX flow, readiness report, project context, current dispatcher/scripts/tests, git history, and official Bash/Gum references.
- Routed `wtx install` through the standard dispatcher and kept existing command behavior covered by dispatcher regression tests.
- Moved TOML escaping and CSV-to-TOML array helpers into `lib/wtx-install.sh`, added idempotent source guard, plugin discovery, and dry-run/write chokepoint primitives.
- Added `scripts/worktree-install.sh` skeleton with direct-invocation path resolution, Step 0 preflight ordering, gum fallback notice, temp cleanup trap, and empty ledger arrays only.
- Added focused shell tests for installer primitives, preflight behavior, symlink invocation, and dispatcher install routing.
- Senior review auto-fixed preflight ordering, direct invocation layout compatibility, and CSV helper shell-option preservation; full validation passed after fixes.

### File List

- `_bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `bin/wtx`
- `lib/wtx-install.sh`
- `scripts/worktree-install.sh`
- `tests/test-wtx-dispatcher.sh`
- `tests/test-wtx-install.sh`

### Senior Developer Review (AI)

Reviewer: GPT-5 Codex on 2026-06-27

Outcome: Approved after auto-fixes. No critical issues remain.

Findings fixed:

- HIGH: `scripts/worktree-install.sh` resolved `WORKSPACE_ROOT` with `git rev-parse --git-common-dir` before parsing/exporting `WTX_INSTALL_DRY_RUN`, violating the Step 0 order. Fixed by moving workspace resolution after dry-run parse, git repo gate, and gum detection.
- HIGH: Direct invocation did not fully match the existing `scripts/worktree-start.sh` WTX_ROOT fallback pattern for an installed layout with `lib/` beside the script. Fixed by resolving the real script directory and using it as `WTX_ROOT` when it contains `lib/`.
- MEDIUM: `_wtx_csv_to_toml_array` always restored globbing with `set +f`, even when the caller already had `noglob` enabled. Fixed by preserving the caller's original shell option state.

Validation:

- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- `bash tests/test-wtx-config.sh`
- `bash tests/test-wtx-dispatcher.sh`
- `bash tests/test-wtx-install.sh`
- `bash tests/test-install.sh`
- `bash tests/test-worktree-registry.sh`

### Change Log

- 2026-06-27: Senior review auto-fixed Step 0 preflight ordering, direct invocation WTX_ROOT fallback, CSV helper shell-option preservation, and added focused regression coverage.
- 2026-06-27: Implemented Story 1.1 installer foundation, shared primitives, wizard preflight skeleton, and focused regression coverage.
