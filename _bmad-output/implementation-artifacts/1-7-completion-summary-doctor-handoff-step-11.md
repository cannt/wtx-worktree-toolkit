---
baseline_commit: 2ac06ccf
---

# Story 1.7: Completion summary and doctor handoff - Step 11

Status: done

## Story

As a developer who has just finished `wtx install`,
I want a clear summary of everything that was installed, skipped, or failed plus the exact command to verify my install displayed before the wizard exits,
so that I know exactly what happened and what to do next.

**Prerequisite:** Stories 1.1 through 1.6 are `done`. The installer wizard already exists, `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` are initialized during preflight, earlier steps append ledger entries, and Story 1.6 added the minimal Step 11 dry-run note. Do not re-implement installer steps, dry-run threading, config writing, hook installation, Gradle installation, PATH hint logic, or `wtx doctor`.

## Acceptance Criteria

1. Given the wizard reaches Step 11, when the completion summary renders, then it iterates `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` in index order and prints one row per ledger entry. Rows map every value the wizard can record: `[✓]` for `done` and `shown`; `[-]` for `skipped`, `skipped (already on PATH)`, and `kept (existing)`; `[!]` for `failed` (and any value beginning `failed`); `[dry-run]` for `previewed (dry-run)`; any other non-empty value falls back to `[-]`. The epic's minimum contract (`[✓]`/`[-]`/`[!]` for `done`/`skipped*`/`failed`) is fully covered; `[dry-run]` is added so previewed rows are not shown as completed installs (Story 1.6 truthfulness requirement). Gum mode uses `tui_style_box`; no-gum mode prints the same content as plain text. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.7; _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-11-Completion-summary; _bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md#AC-7]

2. Given the summary is displayed, when it finishes rendering, then the exact text `wtx doctor` is printed as the verify command. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.7; _bmad-output/specs/spec-wtx-install/SPEC.md#CAP-7-Completion-summary]

3. Given `WTX_INSTALL_DRY_RUN=1`, when Step 11 renders, then it preserves Story 1.6's exact header note `[dry-run] No files were written. Remove --dry-run to apply.` exactly once, renders previewed ledger rows truthfully as dry-run previews rather than completed installs, and still prints `wtx doctor` as the post-run verification command. [Source: _bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md#Acceptance-Criteria; _bmad-output/specs/spec-wtx-install/ux-flow.md#Dry-run-visual-difference]

4. Given a previous optional step failed, when Step 11 renders, then the failed step's row shows `[!]` with a one-line description and `_wtx_install_run` still returns the non-zero tracked status after rendering the summary. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.7; scripts/worktree-install.sh#L622-L631]

5. Given a critical pre-summary step fails before the wizard has enough state to continue, when `_wtx_install_run` returns early, then Step 11 is not required to render; the existing failure return behavior remains unchanged. [Source: scripts/worktree-install.sh#L598-L620]

6. Given `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` are defined and populated, when summary rendering code is implemented, then it uses bash 3.2 indexed-array syntax only: no `declare -A`, no associative-array operations, no `mapfile` or `readarray`, and no GNU-only shell features. [Source: _bmad-output/project-context.md#Technology-Stack-&-Versions; GNU Bash Reference Manual#Arrays]

7. Given the wizard implementation is reviewed after this story, when searching `scripts/worktree-install.sh`, then Step 11 is the only code path that prints summary status glyph rows (`[✓]`, `[-]`, `[!]`, `[dry-run]`). Earlier steps may keep ordinary prompt/explanation output, but must not print completion-summary rows. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7-Summary-ledger]

8. Given a complete non-dry-run install is executed in the existing test harness, when `wtx doctor` is run immediately afterward using the installed checkout, then it exits 0 and reports all required dependencies and install files present. [Source: _bmad-output/specs/spec-wtx-install/SPEC.md#Success-signal; bin/wtx#L145-L190]

9. Given validation is run after implementation, when the required syntax check and shell tests complete, then all commands exit 0. [Source: _bmad-output/project-context.md#Validation-commands]

## Tasks / Subtasks

- [x] Replace the minimal Step 11 placeholder with full ledger rendering (AC: 1-4, 6, 7)
  - [x] Keep `_wtx_install_step11_summary` in `scripts/worktree-install.sh`; extend it rather than adding a second summary function.
  - [x] Iterate by numeric index over the two parallel arrays so key/value ordering is preserved.
  - [x] Render each row as a short, stable one-line description: status token, ledger key, ledger value.
  - [x] Map `done`, `shown`, `skipped*`, `failed`, `previewed (dry-run)`, and `kept (existing)` explicitly. Treat unknown non-empty values conservatively as informational `[-]` unless the value starts with `failed`.
  - [x] Preserve the exact dry-run header note from Story 1.6 and ensure it appears once per run.

- [x] Add the doctor handoff text (AC: 2, 8)
  - [x] Print a small "Verify your install:" section.
  - [x] Include the exact command text `wtx doctor`.
  - [x] Do not invoke `wtx doctor` from the wizard; the story requires handoff text, while tests should run doctor separately.

- [x] Preserve run-control and failure semantics (AC: 4, 5)
  - [x] Keep `_wtx_install_run` returning `_run_rc` after optional Step 9/Step 10 failures.
  - [x] Ensure Step 11 runs on normal, skip, dry-run, overwrite, merge, and optional-failure paths already wired by Story 1.6.
  - [x] Do not force Step 11 after critical early returns from preflight, Step 2, config prompts, Step 8, or TOML commit failure.

- [x] Add focused installer tests in `tests/test-wtx-install.sh` after the Story 1.6 block (AC: 1-9)
  - [x] Unit: summary renders ledger rows in array index order.
  - [x] Unit: status token mapping covers `done`, `skipped`, `skipped (already on PATH)`, `failed`, `previewed (dry-run)`, `kept (existing)`, and `shown`.
  - [x] Unit/run-level: dry-run summary contains the exact Story 1.6 header once, preview rows, and `wtx doctor`.
  - [x] Run-level: optional failure still renders summary and returns the optional failure rc.
  - [x] Static: no associative arrays, `declare -A`, `mapfile`, or `readarray` are introduced for summary logic.
  - [x] Static/output: no non-Step-11 code prints completion-summary glyph rows.
  - [x] E2E: complete non-dry-run wizard output includes summary rows and `wtx doctor`; running `bin/wtx doctor` afterward exits 0.

- [x] Run validation (AC: 9)
  - [x] `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
  - [x] `bash tests/test-wtx-config.sh`
  - [x] `bash tests/test-wtx-dispatcher.sh`
  - [x] `bash tests/test-wtx-install.sh`
  - [x] `bash tests/test-install.sh`
  - [x] `bash tests/test-worktree-registry.sh`

## Dev Notes

### Scope Boundary

This story is only Step 11 completion summary and doctor handoff. Expected production change is `scripts/worktree-install.sh`; expected test change is `tests/test-wtx-install.sh`.

Do not change `install.sh`, `lib/wtx-install.sh`, `lib/wtx-config.sh`, `lib/worktree-tui.sh`, or `bin/wtx` unless implementation proves a hard blocker. `bin/wtx doctor` already exists and should be reused as the command the wizard tells users to run.

### Current Code State

`scripts/worktree-install.sh`:

- `_wtx_install_preflight` initializes `_WTX_LEDGER_KEYS=()` and `_WTX_LEDGER_VALS=()` at lines 113-114. Preserve this; do not move ledger ownership into another module. [Source: scripts/worktree-install.sh#L107-L115]
- `_wtx_install_done_ledger_value` returns `previewed (dry-run)` in dry-run mode and `done` otherwise. Step 11 must render `previewed (dry-run)` as a dry-run preview, not as success. [Source: scripts/worktree-install.sh#L128-L134]
- Step 2 currently prints `[✓] wtx already on PATH` before Step 11. This is an existing informational skip notice from Story 1.2; do not expand this pattern. New completion-summary rows belong only in Step 11. [Source: scripts/worktree-install.sh#L159-L163]
- Step 9 appends `hooks` with `skipped`, `done`/`previewed (dry-run)`, or `failed`; it preserves caller cwd by cd-ing to `WORKSPACE_ROOT` only for the delegated hook install. [Source: scripts/worktree-install.sh#L451-L491]
- Step 10 appends `gradle` and `path-hint`; possible values include `skipped`, `skipped (already on PATH)`, `shown`, `done`/`previewed (dry-run)`, and `failed`. [Source: scripts/worktree-install.sh#L497-L552]
- `_wtx_install_step11_summary` currently only prints the exact dry-run note when `WTX_INSTALL_DRY_RUN=1`; full table rendering is intentionally deferred to this story. Extend this function. [Source: scripts/worktree-install.sh#L568-L572]
- `_wtx_install_run` already calls Step 11 on skip and normal paths and preserves optional Step 9/Step 10 failures in `_run_rc`. Keep that wiring. [Source: scripts/worktree-install.sh#L581-L631]

`bin/wtx`:

- `_wtx_doctor` prints dependency/install checks and returns 0 when required commands and install files are present. Story 1.7 should print `wtx doctor` as the handoff command; it should not call `_wtx_doctor` internally. [Source: bin/wtx#L145-L190]

`tests/test-wtx-install.sh`:

- Tests are dependency-free shell cases with `assert_eq`, `assert_contains`, and `assert_ok`; add Story 1.7 cases near the end, after Story 1.6 Cases 60-68. [Source: tests/test-wtx-install.sh#L1-L48; tests/test-wtx-install.sh#L1693-L1986]
- Existing E2E tests use `_write_install_gum_shim` to drive wizard prompts deterministically. Reuse that shim rather than creating a new test harness. [Source: tests/test-wtx-install.sh#L1851-L1977]
- Story 1.6 tests already assert the dry-run note appears exactly once; update or extend those assertions so the new full summary still preserves that behavior. [Source: tests/test-wtx-install.sh#L1783-L1811; tests/test-wtx-install.sh#L1851-L1888]

### Previous Story Intelligence

- Story 1.6 intentionally used `previewed (dry-run)` as the consistent ledger value for previewed writes. Step 11 should map that value distinctly; do not collapse it into `done`. [Source: _bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md#Completion-Notes-List]
- Story 1.6 wired Step 11 through normal, overwrite, merge, and skip paths while preserving optional failure tracking. Do not remove that wiring. [Source: _bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md#Completion-Notes-List]
- Story 1.5 and 1.6 protected skip and dry-run paths from temp-file allocation. Step 11 must not allocate or modify files. [Source: _bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md#Previous-Story-Intelligence]
- Current git history shows recent installer stories keep implementation in `scripts/worktree-install.sh` and coverage in `tests/test-wtx-install.sh`; follow that established pattern. [Source: git log HEAD 2ac06cc; git show 39eb0b7]

### Architecture Guardrails

- Follow AD-7: summary state lives in the two parallel indexed arrays; each wizard step appends one entry; Step 11 renders the summary table. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7-Summary-ledger]
- Keep bash 3.2 compatibility: no associative arrays, no `mapfile`, no `readarray`, no `${var^^}`, no process substitution to arrays, no GNU-only flags. [Source: _bmad-output/project-context.md#Technology-Stack-&-Versions]
- Use `set -u` only; do not add `set -e`. Use safe defaults such as `"${WTX_INSTALL_DRY_RUN:-0}"` where tests may call functions directly. [Source: _bmad-output/project-context.md#Language-Specific-Rules]
- Use existing `tui_style_box` for styled output; do not call `gum` directly from `scripts/worktree-install.sh`. Gum is optional and all prompt/display behavior must degrade through existing TUI helpers. [Source: _bmad-output/project-context.md#Framework-Specific-Rules; charmbracelet/gum README]
- Quote every path expansion. [Source: _bmad-output/project-context.md#Critical-Dont-Miss-Rules]

### Latest Technical Notes

- Bash upstream documentation confirms Bash supports indexed and associative arrays, but this project targets macOS bash 3.2, so use only indexed array syntax already present in the codebase. Avoid `declare -A` even though modern Bash documents associative arrays. [Source: GNU Bash Reference Manual, Arrays: https://www.gnu.org/software/bash/manual/bash.html#Arrays]
- Gum remains an optional shell UI helper with commands such as `style`, `choose`, `confirm`, and `input`. This story should stay behind `tui_style_box` and existing `tui_*` functions rather than depending on a specific Gum release or CLI flag. [Source: charmbracelet/gum README: https://github.com/charmbracelet/gum]

### Suggested Summary Mapping

Use a small helper inside `scripts/worktree-install.sh` if it keeps Step 11 readable:

```bash
_wtx_install_summary_marker() {
  case "$1" in
    done|shown) printf '[✓]' ;;
    failed*) printf '[!]' ;;
    "previewed (dry-run)") printf '[dry-run]' ;;
    skipped*|"kept (existing)") printf '[-]' ;;
    *) printf '[-]' ;;
  esac
}
```

Keep this bash 3.2-safe and local to the wizard. If the marker helper is added, add a focused unit test for it.

### Testing Standards

Required validation:

```bash
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh
bash tests/test-wtx-config.sh
bash tests/test-wtx-dispatcher.sh
bash tests/test-wtx-install.sh
bash tests/test-install.sh
bash tests/test-worktree-registry.sh
```

## Project Structure Notes

- Expected to change: `scripts/worktree-install.sh`, `tests/test-wtx-install.sh`.
- Story artifact and sprint tracking changes belong under `_bmad-output/implementation-artifacts/`.
- Do not add new top-level directories, new test frameworks, new entry points, or new config keys.

## References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.7-Completion-summary--doctor-handoff-Step-11]
- [Source: _bmad-output/planning-artifacts/epics.md#FR21 / FR22]
- [Source: _bmad-output/specs/spec-wtx-install/SPEC.md#CAP-7-Completion-summary]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-11-Completion-summary]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7-Summary-ledger]
- [Source: _bmad-output/project-context.md#Technology-Stack-&-Versions]
- [Source: _bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md#Previous-Story-Intelligence]
- [Source: scripts/worktree-install.sh#L568-L631]
- [Source: tests/test-wtx-install.sh#L1693-L1986]
- [Source: bin/wtx#L145-L190]
- [Source: GNU Bash Reference Manual, Arrays](https://www.gnu.org/software/bash/manual/bash.html#Arrays)
- [Source: charmbracelet/gum README](https://github.com/charmbracelet/gum)

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

### Completion Notes List

- Added `_wtx_install_summary_marker` helper (bash 3.2-safe, case-based, no associative arrays) that maps ledger values to `[✓]`/`[-]`/`[!]`/`[dry-run]` glyphs.
- Extended `_wtx_install_step11_summary` to iterate `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS` by numeric index, build `summary_args` array, and pass it to `tui_style_box` for styled (gum) or plain-text output.
- Dry-run header note `[dry-run] No files were written. Remove --dry-run to apply.` is printed before the box — same as Story 1.6, exactly once per run.
- Doctor handoff rendered as `"Verify your install:" / "  wtx doctor"` inside the `tui_style_box` call — never invoked programmatically.
- Run-control wiring unchanged: `_wtx_install_run` already calls step11 on all paths; optional failure rc from step9/10 is preserved and returned after step11 renders.
- Added test assertions (Cases 69–75): marker unit, summary unit, dry-run unit, run-level optional-failure, two static checks, and full E2E (non-dry-run wizard + `bin/wtx doctor`).
- Review follow-up (qa-generate-e2e-tests, Cases 76–78): added run-level coverage that critical pre-summary failures (Step 2, TOML commit) return early **without** rendering Step 11 (AC5), that a real `failed` ledger row renders `[!]` at run level with the optional rc preserved (AC4), and that the no-gum pure-bash `tui_style_box` fallback prints the same summary content with a `│` border (AC1). Total install assertions now 327, all passing.

### File List

- `scripts/worktree-install.sh`
- `tests/test-wtx-install.sh`
- `_bmad-output/implementation-artifacts/1-7-completion-summary-doctor-handoff-step-11.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`

## Change Log

- 2026-06-27: Implemented Step 11 full ledger rendering with status-glyph mapping, doctor handoff text, and new test assertions covering unit, run-level, static, and E2E scenarios.
- 2026-06-27: Adversarial review (bmad-story-automator-review). 0 critical / 0 high. Verified all 9 ACs against implementation; all 6 validation suites pass. Committed previously-uncommitted review-follow-up tests (Cases 76–78) closing AC4/AC5/AC1 coverage gaps. Install assertions now 327, all passing. Note (LOW, no change): AC7's literal "only path" wording is contradicted by the pre-existing `[✓] wtx already on PATH` notice at `scripts/worktree-install.sh:160`, which is explicitly out of scope per Dev Notes; the AC7 *intent* (summary table rows live only in Step 11) holds. Status → done.

## Senior Developer Review (AI)

**Reviewer:** Juan Angel Trujillo Jimenez — 2026-06-27
**Outcome:** Approve

- **AC1–AC9:** all verified implemented and tested. `_wtx_install_summary_marker` maps every documented ledger value (`done`/`shown`→`[✓]`, `failed*`→`[!]`, `previewed (dry-run)`→`[dry-run]`, `skipped*`/`kept (existing)`/fallback→`[-]`); `_wtx_install_step11_summary` iterates the parallel indexed arrays in order, renders via `tui_style_box`, preserves the Story 1.6 dry-run header exactly once, and emits `wtx doctor`. Run-control wiring preserves optional-failure rc and skips Step 11 on critical early returns.
- **Validation:** `bash -n` clean; test-wtx-install 327/327, test-install 25/25, test-wtx-config 26/26, test-wtx-dispatcher 22/22, test-worktree-registry 19/19.
- **Findings:** 0 critical, 0 high, 1 medium (now fixed — uncommitted/undocumented Cases 76–78), 1 low (AC7 literal wording vs pre-existing line 160 notice; out of scope, no change).

## Story Completion Status

done
