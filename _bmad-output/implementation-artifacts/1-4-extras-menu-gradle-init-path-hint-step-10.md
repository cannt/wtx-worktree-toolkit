---
baseline_commit: 2e8e8a1cc2dfc1ab66b9742f629fbf491cacbc43
---

# Story 1.4: Extras menu -- Gradle init & PATH hint (Step 10)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer finishing wtx setup,
I want the wizard to offer optional extras (Gradle worktree-cache init and a PATH export hint) each with a one-line explanation,
so that I can opt in to useful enhancements without being forced into them.

**Prerequisite:** Story 1.1 is `done`. `wtx_install_write_or_dryrun`, `WTX_INSTALL_DRY_RUN`, and the parallel `_WTX_LEDGER_KEYS` / `_WTX_LEDGER_VALS` arrays already exist. Story 1.3 is `done` and established the tracked `_run_rc` pattern for optional post-config steps. This story consumes those primitives; do not re-implement them. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.4-Extras-menu--Gradle-init--PATH-hint-Step-10] [Source: _bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md#Why-_run_rc-Instead-of--return]

## Acceptance Criteria

1. Given the wizard reaches Step 10a (Gradle extra), when the Gradle option is presented, then a `tui_confirm` prompt explains the Gradle worktree-cache init script in one line and defaults to no (`[y/N]`). [Source: _bmad-output/planning-artifacts/epics.md#Story-1.4-Extras-menu--Gradle-init--PATH-hint-Step-10] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-10--Extras-menu]

2. Given the user confirms the Gradle extra, when the wizard proceeds, then it runs `bash "$WTX_ROOT/install.sh" --gradle` as a subprocess via `wtx_install_write_or_dryrun`; the exit code is checked; the ledger gets exactly one `gradle` entry with value `done` on exit 0 or `failed` on non-zero. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh] [Source: install.sh#install_gradle]

3. Given the user declines the Gradle extra, when the wizard proceeds, then `install.sh` is not invoked for Gradle; `~/.gradle/init.d/` is unchanged; the ledger gets exactly one entry `gradle: skipped`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.4-Extras-menu--Gradle-init--PATH-hint-Step-10] [Source: _bmad-output/specs/spec-wtx-install/SPEC.md#CAP-4-Extras-menu]

4. Given Gradle installation runs in dry-run mode (`WTX_INSTALL_DRY_RUN=1`), when the subprocess call is built, then `--dry-run` is appended: `bash "$WTX_ROOT/install.sh" --gradle --dry-run`; the call still goes through `wtx_install_write_or_dryrun`, no files are written by the wizard, and dry-run output is produced by the shared write guard / delegated installer. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation] [Source: install.sh#install_gradle]

5. Given the wizard reaches Step 10b (PATH hint) and `case ":$PATH:" in *":$WTX_INSTALL_PREFIX/bin:"*)` matches, when Step 10b runs, then no PATH hint prompt is shown and the ledger gets exactly one entry `path-hint: skipped (already on PATH)`. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-11--PATH-hint-gate]

6. Given the wizard reaches Step 10b and `$WTX_INSTALL_PREFIX/bin` is not on `PATH`, when the user declines the hint, then no export guidance is printed and the ledger gets exactly one entry `path-hint: skipped`. [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-10--Extras-menu]

7. Given the wizard reaches Step 10b and `$WTX_INSTALL_PREFIX/bin` is not on `PATH`, when the user confirms the hint, then the wizard prints shell guidance using the actual prefix bin directory. With the default prefix this includes `export PATH="$HOME/.local/bin:$PATH"`; with a custom prefix it uses that custom `"$WTX_INSTALL_PREFIX/bin"` value. The ledger gets exactly one entry `path-hint: shown`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.4-Extras-menu--Gradle-init--PATH-hint-Step-10] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-10--Extras-menu]

8. Given Step 10 completes after hooks, when `_wtx_install_run` continues, then Step 10 is wired after `_wtx_install_step9_claude_hooks || _run_rc=$?` and before the Step 11 placeholder; a Gradle failure updates `_run_rc` but does not prevent the PATH hint from running or the future Step 11 summary from rendering. [Source: scripts/worktree-install.sh#_wtx_install_run] [Source: _bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md#Why-_run_rc-Instead-of--return]

9. Given `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story, when syntax-check completes, then it exits 0 with no errors. [Source: _bmad-output/project-context.md#Technology-Stack--Versions]

## Tasks / Subtasks

- [x] Implement `_wtx_install_step10_extras` in `scripts/worktree-install.sh` (AC: 1-8)
  - [x] Add Step 10a Gradle prompt using `tui_confirm "Install Gradle worktree-cache init script to ~/.gradle/init.d/?"` with no second argument, so fallback and gum both default to no.
  - [x] On Gradle decline: append exactly `gradle=skipped`; return 0 for the Gradle portion.
  - [x] On Gradle confirm: build `local install_args=("bash" "$WTX_ROOT/install.sh" "--gradle")`; append `"--dry-run"` when `WTX_INSTALL_DRY_RUN=1`.
  - [x] Delegate through `wtx_install_write_or_dryrun "would copy: gradle init -> $HOME/.gradle/init.d/worktree-cache.init.gradle.kts" "${install_args[@]}"`; append `gradle=done` or `gradle=failed`; preserve the subprocess rc.
  - [x] Add Step 10b PATH gate using exactly `case ":$PATH:" in *":$WTX_INSTALL_PREFIX/bin:"*) ... esac` after setting a safe fallback for `WTX_INSTALL_PREFIX` if it is unset.
  - [x] If already on PATH: append exactly `path-hint=skipped (already on PATH)` and do not call `tui_confirm`.
  - [x] If not on PATH: call `tui_confirm "Show PATH setup hint?" "yes"` so the prompt defaults to yes (`[Y/n]`); on decline append `path-hint=skipped`.
  - [x] On PATH hint confirm: print the shell guidance and append `path-hint=shown`.
- [x] Wire Step 10 into `_wtx_install_run` (AC: 8)
  - [x] Replace the Step 10 placeholder comment with `_wtx_install_step10_extras || _run_rc=$?`.
  - [x] Keep the Step 11 placeholder in place. Do not implement summary rendering in this story.
  - [x] Keep Step 2 and TOML write abort-on-failure behavior unchanged.
- [x] Add focused tests in `tests/test-wtx-install.sh` (AC: 1-9)
  - [x] Case: Gradle decline returns 0, appends one `gradle=skipped` ledger entry, and does not invoke `wtx_install_write_or_dryrun`.
  - [x] Case: Gradle confirm success delegates `bash "$WTX_ROOT/install.sh" --gradle`, appends one `gradle=done`, and returns 0.
  - [x] Case: Gradle confirm failure appends one `gradle=failed`, returns the delegated rc, and still allows PATH hint code to run.
  - [x] Case: Gradle dry-run includes `--dry-run` in delegated args.
  - [x] Case: PATH already contains `$WTX_INSTALL_PREFIX/bin`; assert no confirm prompt, no hint output, and `path-hint=skipped (already on PATH)`.
  - [x] Case: PATH missing prefix bin + user declines; assert no export guidance and `path-hint=skipped`.
  - [x] Case: PATH missing prefix bin + user confirms with default `$HOME/.local`; assert output contains `export PATH="$HOME/.local/bin:$PATH"` and `path-hint=shown`.
  - [x] Case: PATH missing prefix bin + custom `WTX_INSTALL_PREFIX`; assert output uses the custom prefix rather than hardcoding `$HOME/.local`.
  - [x] Case: `_wtx_install_run` returns Step 10 failure rc via `_run_rc`, while preserving existing Step 9 success/failure behavior.
  - [x] Run the full validation suite listed in Testing Standards.

## Dev Notes

### Scope Boundary

This story implements **Step 10 only**: optional Gradle init install and optional PATH setup hint. Do not implement idempotency (Story 1.5), full end-to-end dry-run verification (Story 1.6), or Step 11 summary rendering / doctor handoff (Story 1.7). Leave their placeholders untouched. [Source: _bmad-output/planning-artifacts/epics.md#FR-Coverage-Map]

Do not change `install.sh`, `lib/wtx-install.sh`, `lib/wtx-config.sh`, or `lib/worktree-tui.sh` unless a test proves Step 10 cannot be implemented safely without doing so. The architecture says Gradle copying is delegated to `install.sh`, not reimplemented in the wizard. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]

### Current Code State

- `scripts/worktree-install.sh` already has `_wtx_install_step9_claude_hooks` at lines 364-405. It changes directory to `WORKSPACE_ROOT` for hook installation and restores the caller directory; this was added after review to prevent nested-directory installs. Step 10 does not need that `cd` pattern because `install.sh --gradle` writes to `$HOME/.gradle/init.d`, not the workspace. [Source: scripts/worktree-install.sh#_wtx_install_step9_claude_hooks]
- `_wtx_install_run` currently initializes `local _run_rc=0`, calls Step 9 as `_wtx_install_step9_claude_hooks || _run_rc=$?`, then leaves the Step 10 placeholder at lines 445-446 and returns `_run_rc`. Replace only that placeholder. [Source: scripts/worktree-install.sh#_wtx_install_run]
- Step 2 sets and exports `WTX_INSTALL_PREFIX` only when `wtx` is not already on PATH. If Step 2 skips because this checkout's `wtx` already resolves on PATH, Step 10 must still have a defined prefix for the PATH gate. Use `local prefix="${WTX_INSTALL_PREFIX:-$HOME/.local}"` and `local prefix_bin="$prefix/bin"`, and assign/export `WTX_INSTALL_PREFIX="$prefix"` if it was unset. [Source: scripts/worktree-install.sh#_wtx_install_step2_binary]
- `install.sh --gradle` copies `$WTX_ROOT/share/gradle/worktree-cache.init.gradle.kts` to `$HOME/.gradle/init.d/worktree-cache.init.gradle.kts`, checks source existence, creates the destination directory, and returns non-zero on failures. In dry-run it prints `[dry-run] would create ...` and `[dry-run] would copy -> ...`, then returns 0. [Source: install.sh#install_gradle]
- `install.sh` has a private `_shell_rc` helper for its own checklist output, but do not source `install.sh` to reuse it. Sourcing `install.sh` is unsafe because it parses arguments and dispatches at top level. For Step 10, generic restart guidance is enough unless you add a private wizard helper. [Source: install.sh#_shell_rc] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]

### Suggested Implementation Shape

Keep the function small and explicit:

```bash
_wtx_install_step10_extras() {
    local rc=0
    local gradle_rc=0
    local prefix="${WTX_INSTALL_PREFIX:-$HOME/.local}"
    local prefix_bin="$prefix/bin"
    WTX_INSTALL_PREFIX="$prefix"
    export WTX_INSTALL_PREFIX

    tui_style_box \
        "Optional extras" \
        "Gradle worktree-cache init script" \
        "  Isolates Gradle build caches per worktree."
    if tui_confirm "Install Gradle worktree-cache init script to ~/.gradle/init.d/?"; then
        local install_args=("bash" "$WTX_ROOT/install.sh" "--gradle")
        if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
            install_args+=("--dry-run")
        fi
        wtx_install_write_or_dryrun "would copy: gradle init -> $HOME/.gradle/init.d/worktree-cache.init.gradle.kts" "${install_args[@]}"
        gradle_rc=$?
        _WTX_LEDGER_KEYS+=("gradle")
        if [[ $gradle_rc -eq 0 ]]; then
            _WTX_LEDGER_VALS+=("done")
        else
            _WTX_LEDGER_VALS+=("failed")
            rc=$gradle_rc
        fi
    else
        _WTX_LEDGER_KEYS+=("gradle")
        _WTX_LEDGER_VALS+=("skipped")
    fi

    case ":$PATH:" in
        *":$prefix_bin:"*)
            _WTX_LEDGER_KEYS+=("path-hint")
            _WTX_LEDGER_VALS+=("skipped (already on PATH)")
            ;;
        *)
            if tui_confirm "Show PATH setup hint?" "yes"; then
                printf '  Add to your shell startup file:\n'
                printf '    export PATH="%s:$PATH"\n' "$prefix_bin"
                printf '  then restart your shell (or source that file)\n'
                _WTX_LEDGER_KEYS+=("path-hint")
                _WTX_LEDGER_VALS+=("shown")
            else
                _WTX_LEDGER_KEYS+=("path-hint")
                _WTX_LEDGER_VALS+=("skipped")
            fi
            ;;
    esac

    return $rc
}
```

The `export PATH="%s:$PATH"` line intentionally keeps `$PATH` literal in the printed command. Do not expand the user's current full PATH into the hint.

### Previous Story Intelligence

- Story 1.3 established the pattern for optional post-config work: a non-zero optional step updates `_run_rc` while later steps still run. Reuse that for Gradle failure so PATH hint and future Step 11 still execute. [Source: _bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md#Why-_run_rc-Instead-of--return]
- Story 1.3 review fixed a working-directory bug for `install.sh --hooks`. Do not cargo-cult the `cd "$WORKSPACE_ROOT"` block into Step 10 unless a test proves it is needed. `install.sh --gradle` targets `$HOME`, so changing directory only adds risk. [Source: _bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md#Debug-Log-References]
- Story 1.2 notes that `WTX_INSTALL_PREFIX` is exported by Step 2 for later use by Story 1.4. Because Step 2 may skip, Step 10 must handle the unset case. [Source: _bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md#Tasks--Subtasks]
- Existing tests source wizard function definitions by evaluating the file up to `_wtx_install_run "$@"`; continue using that pattern instead of invoking the full interactive wizard where focused function tests are enough. [Source: tests/test-wtx-install.sh#Story-1.2-QA-gap-coverage]

### Architecture Guardrails

- Use Bash 3.2 syntax only: no associative arrays, no `mapfile`, no `${var^^}` / `${var,,}`, and no `readlink -f`. Use ordinary indexed arrays and scalar locals. [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- Keep `set -u` only. Do not add `set -e`; optional steps must record failures and continue to later optional work. [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]
- All user prompts in `scripts/worktree-install.sh` must go through `tui_*` functions. Do not add bare `read`; the existing AD-10 grep test should continue to pass. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]
- Quote every path expansion, especially `"$WTX_ROOT"`, `"$HOME"`, `"$WTX_INSTALL_PREFIX"`, and `"$prefix_bin"`. [Source: _bmad-output/project-context.md#Critical-Dont-Miss-Rules]
- Do not move Android/Gradle setup logic into core wizard code. The wizard only asks and delegates; `install.sh --gradle` owns the copy. [Source: _bmad-output/project-context.md#Framework-Specific-Rules-wtx-architecture]
- Append exactly one ledger entry for `gradle` and exactly one ledger entry for `path-hint` on every Step 10 path. Story 1.7 depends on a complete ordered ledger. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]

### Latest Technical Information

GNU Bash has newer releases than the project target, but this repository intentionally targets macOS's Bash 3.2 baseline. Do not use Bash 4+/5 conveniences even if they are available locally. Indexed arrays are enough for this story; associative arrays remain forbidden by project policy. [Source: https://www.gnu.org/software/bash/manual/html_node/Arrays.html] [Source: _bmad-output/project-context.md#Technology-Stack--Versions]

### Project Structure Notes

- **Modify:** `scripts/worktree-install.sh` -- add `_wtx_install_step10_extras`, wire it into `_wtx_install_run`.
- **Modify:** `tests/test-wtx-install.sh` -- add Step 10 focused tests after current Step 9 cases and before the final totals.
- **Do not modify unless tests force it:** `install.sh`, `lib/wtx-install.sh`, `lib/worktree-tui.sh`, `lib/wtx-config.sh`, `bin/wtx`.
- **Existing asset consumed by delegation:** `share/gradle/worktree-cache.init.gradle.kts` is copied by `install.sh --gradle`.

### Testing Standards

Required after implementation:

- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- `bash tests/test-wtx-config.sh`
- `bash tests/test-wtx-dispatcher.sh`
- `bash tests/test-wtx-install.sh`
- `bash tests/test-install.sh`
- `bash tests/test-worktree-registry.sh`

## References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.4-Extras-menu--Gradle-init--PATH-hint-Step-10]
- [Source: _bmad-output/specs/spec-wtx-install/SPEC.md#CAP-4-Extras-menu]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-10--Extras-menu]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-11--PATH-hint-gate]
- [Source: _bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md#Tasks--Subtasks]
- [Source: _bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md#Why-_run_rc-Instead-of--return]
- [Source: install.sh#install_gradle]
- [Source: scripts/worktree-install.sh#_wtx_install_run]
- [Source: tests/test-wtx-install.sh#Story-1.3-QA-gap-coverage]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]
- [Source: https://www.gnu.org/software/bash/manual/html_node/Arrays.html]

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- Added failing Story 1.4 Step 10 tests first; initial focused run failed because `_wtx_install_step10_extras` did not exist.
- Implemented Step 10 and corrected test output capture from command substitution to file redirection so ledger mutations are observed in the same shell.
- Validation passed: `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`, `bash tests/test-wtx-config.sh`, `bash tests/test-wtx-dispatcher.sh`, `bash tests/test-wtx-install.sh`, `bash tests/test-install.sh`, `bash tests/test-worktree-registry.sh`.

### Completion Notes List

- Implemented the optional extras step with a default-no Gradle prompt, delegated `install.sh --gradle` execution through `wtx_install_write_or_dryrun`, dry-run flag propagation, and exact `gradle` ledger outcomes.
- Added PATH hint handling with fallback `WTX_INSTALL_PREFIX`, already-on-PATH skip behavior, default-yes hint prompt when missing, literal `$PATH` guidance, and exact `path-hint` ledger outcomes.
- Wired Step 10 after Step 9 and before the Step 11 placeholder, preserving abort-on-failure behavior for earlier critical steps and tracked optional return-code behavior for Step 9/10.
- Added focused shell tests for all Story 1.4 acceptance paths and full validation coverage.

### File List

- scripts/worktree-install.sh
- tests/test-wtx-install.sh
- _bmad-output/implementation-artifacts/1-4-extras-menu-gradle-init-path-hint-step-10.md
- _bmad-output/implementation-artifacts/sprint-status.yaml
- _bmad-output/implementation-artifacts/tests/test-summary.md

### Senior Developer Review (AI)

**Reviewed: 2026-06-27 | Outcome: Approved**

**Git vs Story Discrepancies (2 MEDIUM):**
- `_bmad-output/implementation-artifacts/tests/test-summary.md` was modified post-commit but missing from File List → **Fixed**: added to File List.
- E2E tests (Cases 44-45) and `test-summary.md` were uncommitted → **Fixed**: committed with review.

**Code Quality (2 LOW):**
- Cases 36 and 38 did not assert `_WTX_LEDGER_VALS[1]` (path-hint ledger) when PATH already contained prefix bin → **Fixed**: added `path-hint: skipped (already on PATH)` assertion to both cases.
- `--dry-run` appended to `install_args` is never consumed (wtx_install_write_or_dryrun short-circuits first); intentional defensive coding per AD-5, not changed.

**All 9 ACs verified as implemented. All tasks marked [x] confirmed done. 165/165 tests pass after fixes.**

### Change Log

- 2026-06-27: Implemented Step 10 optional extras menu, wired it into the install wizard run sequence, and added focused coverage for Gradle/PATH hint behavior.
- 2026-06-27: Code review — added E2E tests (Cases 44-45) with gum shim, tightened path-hint ledger assertions in Cases 36/38, added test-summary.md to File List. Status → done.

## Story Completion Status

Ready for review. All tasks and subtasks are complete, acceptance criteria are covered, and required validation commands pass.
