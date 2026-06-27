# Story 1.6: Dry-run mode - end-to-end threading

Status: ready-for-dev

## Story

As a developer evaluating wtx in a new workspace,
I want to run `wtx install --dry-run` and see a complete preview of every action the wizard would take without any filesystem changes,
so that I can confirm the install plan before committing to it.

**Prerequisite:** Stories 1.1 through 1.5 are `done`. The installer wizard already exists, `WTX_INSTALL_DRY_RUN` is parsed/exported in preflight, `wtx_install_write_or_dryrun` is the shared write guard, Step 9 and Step 10 already append `--dry-run` to delegated `install.sh` argument arrays, and Story 1.5 deferred TOML temp allocation until `_wtx_install_commit_toml`. Do not re-implement those primitives.

## Acceptance Criteria

1. Given `wtx install --dry-run` is invoked, when Step 0 preflight runs, then `--dry-run` is parsed before the git check and gum detection, `WTX_INSTALL_DRY_RUN=1` is exported, and every later mutation path reads this variable only through the dry-run/write guard or a dry-run-aware ledger/status branch. [Source: epics.md#Story-1.6 / AD-12, AD-5]

2. Given `WTX_INSTALL_DRY_RUN=1` and a wizard step would write, create, copy, move, or overwrite a file, when that step reaches the mutation point, then it goes through `wtx_install_write_or_dryrun`; the helper prints a `[dry-run] would ...` line with the target path and returns without executing the command. [Source: epics.md#Story-1.6 / CAP-6, UX-DR14]

3. Given `WTX_INSTALL_DRY_RUN=1` and the wizard prepares to delegate to `install.sh`, when the argument array is built for the symlink, hooks, or Gradle step, then `--dry-run` is present in the delegated arguments and the call is still passed through `wtx_install_write_or_dryrun`; no direct `bash "$WTX_ROOT/install.sh" ...` execution path bypasses the guard. [Source: epics.md#Story-1.6 / AD-3, AD-5]

4. Given the wizard runs a complete dry-run through the normal no-existing-`wtx.toml` path, when the run completes, then these paths are unchanged or absent compared with the pre-run snapshot: `$WORKSPACE_ROOT/wtx.toml`, `$WORKSPACE_ROOT/.wtx-install-tmp.*`, `$WORKSPACE_ROOT/.claude/hooks/worktree-*.sh`, `$WTX_INSTALL_PREFIX/bin/wtx`, and `$HOME/.gradle/init.d/worktree-cache.init.gradle.kts`. [Source: epics.md#Story-1.6 / CAP-6]

5. Given the wizard runs a dry-run when `$WORKSPACE_ROOT/wtx.toml` already exists, when the user chooses `overwrite` or `merge`, then all prompts for that path still run, `[dry-run] would write: $WORKSPACE_ROOT/wtx.toml` is printed, and the existing `wtx.toml` remains byte-for-byte identical after the run. [Source: epics.md#Story-1.6 / CAP-6, Story-1.5]

6. Given the wizard runs a dry-run and the user confirms optional write steps, when Step 9 hooks and Step 10 Gradle execute, then their preview output is visible and no hook directory or Gradle init file is created. [Source: epics.md#Story-1.6 / UX-DR14]

7. Given the wizard records ledger entries during dry-run, when a mutation is previewed rather than performed, then the ledger value must not say or imply that the mutation was actually completed. The config step must record a ledger entry in dry-run so Story 1.7 can render a complete truthful summary. [Source: epics.md#Story-1.6 / AD-7, UX-DR13]

8. Given the dry-run completes and Step 11 summary handling is reached, when `WTX_INSTALL_DRY_RUN=1`, then the output includes exactly this header note: `[dry-run] No files were written. Remove --dry-run to apply.` If the full Step 11 ledger table is still deferred to Story 1.7, implement only the minimal summary hook needed for this dry-run note and leave the full table rendering to Story 1.7. [Source: epics.md#Story-1.6 / UX-DR13, Story-1.7]

9. Given `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` and the shell test suite are run after this story, when validation completes, then all commands exit 0. [Source: project-context.md#Validation-commands]

## Tasks / Subtasks

- [ ] Audit every installer mutation path for dry-run threading (AC: 1-3)
  - [ ] Confirm `_wtx_install_parse_args` still parses `--dry-run` before git/gum work in `_wtx_install_preflight`; do not reorder preflight.
  - [ ] Confirm all real writes are behind `wtx_install_write_or_dryrun`: symlink install, TOML commit, hooks install, Gradle install.
  - [ ] Grep for direct `install.sh` invocations or filesystem mutation commands in `scripts/worktree-install.sh`; remove or guard any bypass.
  - [ ] Keep `install.sh` as a subprocess only; do not source it.

- [ ] Make dry-run preview lines precise enough for an end-to-end install plan (AC: 2, 3, 6)
  - [ ] Keep the existing helper behavior: in dry-run it prints `[dry-run] <action-label>` and does not execute the command.
  - [ ] Improve action labels where needed so the preview names the actual target and, when useful, the source: symlink target, `wtx.toml`, hooks destination, Gradle init destination.
  - [ ] Preserve `--dry-run` in every delegated `install_args` array even though the guard suppresses execution; tests should assert the prepared args include it.

- [ ] Make dry-run ledger values truthful and complete (AC: 7, 8)
  - [ ] In dry-run, do not append ledger values such as `done` for symlink/hooks/gradle/config mutations that were only previewed.
  - [ ] Add a config ledger entry when the TOML write guard returns 0 in dry-run. Suggested value: `previewed (dry-run)`.
  - [ ] Use one consistent dry-run ledger value for previewed write steps so Story 1.7 can map it cleanly; keep existing skipped values for user-declined steps and already-on-PATH checks.
  - [ ] Do not change Story 1.5's skip-path ledger: `config = "kept (existing)"` remains correct when the user chooses `skip`.

- [ ] Add minimal Step 11 dry-run summary handling without stealing Story 1.7 scope (AC: 8)
  - [ ] If `_wtx_install_step11_summary` does not exist, add it near the Step 11 placeholder.
  - [ ] For Story 1.6, the function only needs to print `[dry-run] No files were written. Remove --dry-run to apply.` when `WTX_INSTALL_DRY_RUN=1`; it may be a no-op for non-dry-run.
  - [ ] Call `_wtx_install_step11_summary` from `_wtx_install_run` after Step 10 on normal, overwrite, and merge paths.
  - [ ] Decide whether the Story 1.5 `skip` path should call the summary too. If it does, preserve the existing Step 9/Step 10 optional failure tracking. If it does not, add a test or comment explaining why skip does not represent a complete dry-run install preview.
  - [ ] Do not render the full `[ok]/[-]/[!]` ledger table or run `wtx doctor`; that belongs to Story 1.7.

- [ ] Add focused tests to `tests/test-wtx-install.sh` after the Story 1.5 section (AC: 1-9)
  - [ ] Unit: dry-run helper still prints and skips command execution.
  - [ ] Unit/run-level: symlink, TOML, hooks, and Gradle paths prepare `--dry-run` args and use `wtx_install_write_or_dryrun`.
  - [ ] Unit: dry-run ledger values use the chosen preview value, and config records a dry-run ledger entry.
  - [ ] E2E: real wizard dry-run through the no-existing-`wtx.toml` path with gum shim, hooks=yes, gradle=yes, path-hint=yes; assert prompts run, preview lines print, and no files are created.
  - [ ] E2E: existing `wtx.toml` + `overwrite` dry-run leaves the file byte-for-byte unchanged and prints the TOML preview line.
  - [ ] E2E: existing `wtx.toml` + `merge` dry-run pre-fills prompts and leaves the file byte-for-byte unchanged.
  - [ ] E2E: no `.wtx-install-tmp.*` leftovers remain after every dry-run path.
  - [ ] Summary: dry-run output includes the required Step 11 header note exactly once.

- [ ] Run validation (AC: 9)
  - [ ] `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
  - [ ] `bash tests/test-wtx-config.sh`
  - [ ] `bash tests/test-wtx-dispatcher.sh`
  - [ ] `bash tests/test-wtx-install.sh`
  - [ ] `bash tests/test-install.sh`
  - [ ] `bash tests/test-worktree-registry.sh`

## Dev Notes

### Scope Boundary

This story is about **dry-run correctness end to end**. It may touch `scripts/worktree-install.sh` and `tests/test-wtx-install.sh`. Avoid changes to `install.sh`, `lib/wtx-install.sh`, `lib/wtx-config.sh`, and `lib/worktree-tui.sh` unless the audit proves the current helper contract cannot satisfy the ACs.

Do not implement the full Story 1.7 completion summary. The only Step 11 work in this story is the required dry-run note and any minimal call wiring needed for that note to appear.

### Current Code State

`scripts/worktree-install.sh`:

- `_wtx_install_parse_args` sets and exports `WTX_INSTALL_DRY_RUN` at lines 73-88; `_wtx_install_preflight` calls it before the git check and gum detection at lines 91-104. Preserve this order. [Source: scripts/worktree-install.sh#L73-L104]
- Step 2 builds `install_args=("bash" "$WTX_ROOT/install.sh" "--prefix" "$WTX_INSTALL_PREFIX")`, appends `--dry-run` when active, then calls `wtx_install_write_or_dryrun "would create: $WTX_INSTALL_PREFIX/bin/wtx" ...` at lines 158-168. The label currently lacks the source path. [Source: scripts/worktree-install.sh#L158-L168]
- TOML writing is correctly deferred to `_wtx_install_commit_toml`, which allocates the temp only inside the guarded write path at lines 430-437. In dry-run, the guard should prevent temp allocation. [Source: scripts/worktree-install.sh#L430-L437]
- `_wtx_install_run` calls the TOML guard at line 596 but only appends a config ledger entry when `WTX_INSTALL_DRY_RUN != 1`; this leaves dry-run config unrepresented in the ledger. [Source: scripts/worktree-install.sh#L595-L604]
- Step 9 appends `--dry-run` to hook install args and uses the guard at lines 456-470, but the ledger currently records `done` whenever the guard returns 0. [Source: scripts/worktree-install.sh#L456-L482]
- Step 10 appends `--dry-run` to Gradle install args and uses the guard at lines 501-508, but the ledger currently records `done` whenever the guard returns 0. [Source: scripts/worktree-install.sh#L501-L518]
- `_wtx_install_run` still has a Step 11 placeholder at lines 613-614. Story 1.6 should add/call only the minimal dry-run note hook. [Source: scripts/worktree-install.sh#L607-L616]

`lib/wtx-install.sh`:

- `wtx_install_write_or_dryrun` already enforces the core contract: it requires an action label and command, prints `[dry-run] <action-label>` and returns 0 when `WTX_INSTALL_DRY_RUN=1`, otherwise executes the command and returns its exit code. Reuse this behavior; do not create a second dry-run mechanism. [Source: lib/wtx-install.sh#L68-L83]

`install.sh`:

- `install.sh` has its own dry-run mode and prints detailed dry-run messages for symlink, hooks, and Gradle operations. In the wizard, `install.sh` is still passed `--dry-run` for consistency and testability, but the wizard guard should prevent executing the subprocess in dry-run. Do not rely on `install.sh` output to satisfy wizard dry-run preview lines unless you intentionally change the Story 1.1 guard contract. [Source: install.sh#L10-L21, install.sh#L105-L207]

### Previous Story Intelligence

- Story 1.5 fixed a high-severity review issue where preflight created `.wtx-install-tmp.*` before the idempotency choice. Preserve that fix: dry-run and skip paths must not allocate TOML temp files before the guarded TOML commit path. [Source: 1-5-idempotency-skip-overwrite-merge.md#Senior-Developer-Review]
- Story 1.5 tests use file captures for functions invoked inside command substitutions because variable writes inside those subshells do not persist. Follow that pattern when testing `tui_choose`, `tui_input`, and wizard output. [Source: 1-5-idempotency-skip-overwrite-merge.md#Debug-Log-References]
- Story 1.4 established the optional-step failure pattern: Step 9 and Step 10 use `|| _run_rc=$?` so later optional work still runs. Preserve that pattern when adding Step 11. [Source: 1-5-idempotency-skip-overwrite-merge.md#Previous-Story-Intelligence]
- Story 1.5 skip path jumps directly to Step 9 and Step 10 with `WTX_INSTALL_PREFIX` possibly unset. Step 10 already guards this with `local prefix="${WTX_INSTALL_PREFIX:-$HOME/.local}"`; do not remove it. [Source: scripts/worktree-install.sh#L489-L494]

### Architecture Guardrails

- Bash 3.2 only: no associative arrays, no `mapfile`, no `${var^^}`, no process substitution to arrays, no GNU-only flags. [Source: _bmad-output/project-context.md#Technology-Stack-&-Versions]
- Use `set -u` only; do not add `set -e`. Use `"${WTX_INSTALL_DRY_RUN:-0}"` and similar defaults for variables that may be unset in tests. [Source: _bmad-output/project-context.md#Language-Specific-Rules]
- Keep every path quoted. This repo may live under paths with spaces. [Source: _bmad-output/project-context.md#Critical-Dont-Miss-Rules]
- All prompt behavior stays on `tui_*` functions; do not add bare `read` in the wizard. [Source: _bmad-output/project-context.md#Framework-Specific-Rules]
- Config access stays on `wtx_config_get` and `wtx_config_get_list`. This story should not parse TOML. [Source: _bmad-output/project-context.md#Framework-Specific-Rules]
- `bin/wtx` remains the single user-facing entry point; no new command or script is needed. [Source: docs/architecture.md#Layer-Architecture]

### Testing Standards

Use the existing dependency-free shell test style in `tests/test-wtx-install.sh`. The existing `_write_install_gum_shim` helper already drives full wizard E2E tests with deterministic answers; extend it if you need idempotency choices (`skip` / `overwrite` / `merge`) or additional dry-run prompt variants.

Required validation:

```bash
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh
bash tests/test-wtx-config.sh
bash tests/test-wtx-dispatcher.sh
bash tests/test-wtx-install.sh
bash tests/test-install.sh
bash tests/test-worktree-registry.sh
```

### Project Structure Notes

Files expected to change:

- `scripts/worktree-install.sh` - dry-run labels, ledger values, config dry-run ledger entry, minimal Step 11 dry-run note.
- `tests/test-wtx-install.sh` - Story 1.6 unit and E2E dry-run coverage.

Files expected not to change unless a clear blocker appears:

- `lib/wtx-install.sh` - helper already satisfies the guard contract.
- `install.sh` - subprocess already supports `--dry-run`; wizard should not need installer internals changed.
- `lib/wtx-config.sh`, `lib/worktree-tui.sh`, `bin/wtx` - no new config, prompt API, or dispatcher behavior is required.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.6-Dry-run-mode-end-to-end-threading]
- [Source: _bmad-output/planning-artifacts/epics.md#FR19 / FR20 / FR21]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Dry-run-visual-difference]
- [Source: docs/architecture.md#Path-Resolution-Strategy]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]
- [Source: _bmad-output/implementation-artifacts/1-5-idempotency-skip-overwrite-merge.md#Previous-Story-Intelligence]
- [Source: scripts/worktree-install.sh#L73-L115]
- [Source: scripts/worktree-install.sh#L158-L168]
- [Source: scripts/worktree-install.sh#L430-L437]
- [Source: scripts/worktree-install.sh#L456-L482]
- [Source: scripts/worktree-install.sh#L501-L518]
- [Source: scripts/worktree-install.sh#L595-L616]
- [Source: lib/wtx-install.sh#L68-L83]
- [Source: tests/test-wtx-install.sh#Case-44]

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

### Completion Notes List

### File List
