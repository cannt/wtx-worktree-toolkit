---
baseline_commit: f3a676ce4c1c97b15b4c95a823b5038f69a6d513
---

# Story 1.3: Claude Code hooks setup (Step 9)

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer who has just configured wtx,
I want the wizard to offer to install Claude Code lifecycle hooks with a clear description of what each hook does,
so that I can make an informed choice and have the hooks set up automatically without locating or copying files manually.

**Prerequisite:** Story 1.1 is `done`. `wtx_install_write_or_dryrun`, `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS`, and `WTX_INSTALL_DRY_RUN` are already defined and verified in `lib/wtx-install.sh` and `scripts/worktree-install.sh`. This story CONSUMES them — do not re-implement them. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Architecture-Guardrails]

## Acceptance Criteria

1. Given the wizard reaches Step 9 (Claude Code hooks), when the hooks step is shown, then a gum styled box (`tui_style_box`) or plain-text fallback lists the three hook scripts (`worktree-create.sh`, `worktree-detect.sh`, `worktree-remove.sh`) with a one-line description of each, followed by `Install Claude Code hooks? [Y/n]`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3-Claude-Code-hooks-setup-Step-9] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-9--Claude-Code-hooks] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]

2. Given the user confirms hook installation, when the wizard proceeds, then it runs `bash "$WTX_ROOT/install.sh" --hooks` as a subprocess via `wtx_install_write_or_dryrun`; the exit code is checked; on success the three files in `$WORKSPACE_ROOT/.claude/hooks/` are byte-for-byte copies of the sources in `$WTX_ROOT/hooks/`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3-Claude-Code-hooks-setup-Step-9] [Source: install.sh#install_hooks] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]

3. Given the user declines hook installation, when the wizard proceeds, then no hook files are written or modified; `$WORKSPACE_ROOT/.claude/hooks/` is unchanged; the ledger records `hooks: skipped`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3-Claude-Code-hooks-setup-Step-9] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]

4. Given hook installation runs in `--dry-run` mode (`WTX_INSTALL_DRY_RUN=1`), when the subprocess call is made, then `--dry-run` is appended to the arguments: `bash "$WTX_ROOT/install.sh" --hooks --dry-run`; no files are written; `install.sh` itself prints `[dry-run] would copy:` lines for each hook (this is `install.sh`'s own dry-run output — no additional printing needed in the wizard). [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3-Claude-Code-hooks-setup-Step-9] [Source: install.sh#install_hooks] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]

5. Given hook installation completes (success, failure, or skipped), when the ledger is updated, then exactly one entry is appended: key = `hooks`, value = `done` (exit 0 after confirm), `failed` (non-zero exit after confirm), or `skipped` (user declined) respectively. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3-Claude-Code-hooks-setup-Step-9] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]

6. Given `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story, when syntax-check completes, then it exits 0 with no errors. [Source: _bmad-output/project-context.md#Technology-Stack--Versions]

## Tasks / Subtasks

- [x] Implement `_wtx_install_step9_claude_hooks` in `scripts/worktree-install.sh` (AC: 1, 2, 3, 4, 5)
  - [x] Display the hooks info block via `tui_style_box` with one-line description for each of the three hooks; fall back naturally via existing `tui_style_box` stub (no second fallback needed).
  - [x] Call `tui_confirm "Install Claude Code hooks?" "yes"` (pass non-empty 2nd arg for `[Y/n]` default-yes behavior per `tui_confirm` signature).
  - [x] On decline: append ledger `hooks=skipped`; return 0 immediately.
  - [x] On confirm: build subprocess args `("bash" "$WTX_ROOT/install.sh" "--hooks")`; append `"--dry-run"` when `WTX_INSTALL_DRY_RUN=1`.
  - [x] Delegate via `wtx_install_write_or_dryrun "would copy: hooks -> $WORKSPACE_ROOT/.claude/hooks/" "${install_args[@]}"`.
  - [x] Capture return code; append ledger `hooks=done` (rc=0) or `hooks=failed` (rc≠0); return the rc.
- [x] Replace the placeholder comment in `_wtx_install_run` and wire the failure (AC: 5)
  - [x] Remove the two placeholder lines (`# Step 9 — ...` comment and `# _wtx_install_step9_claude_hooks`).
  - [x] Add a tracked-rc pattern to `_wtx_install_run` so hooks failure is recorded but execution continues to Steps 10/11 (see Dev Notes for the `_run_rc` pattern — do NOT use `|| return $?` for Step 9).
  - [x] Ensure `_wtx_install_run` propagates any non-zero rc at exit (`return $_run_rc`).
- [x] Add focused tests in `tests/test-wtx-install.sh` (AC: 1–6)
  - [x] Case: user declines — assert ledger key=`hooks`, val=`skipped`; assert no subprocess invoked.
  - [x] Case: user confirms, subprocess exits 0 — assert ledger key=`hooks`, val=`done`; assert return 0.
  - [x] Case: user confirms, subprocess exits non-zero — assert ledger key=`hooks`, val=`failed`; assert function returns non-zero.
  - [x] Case: dry-run mode — assert `--dry-run` appended to subprocess args (stub `wtx_install_write_or_dryrun` to capture args, assert `--dry-run` present).
  - [x] Assert `worktree-install.sh` still contains no bare `read` outside `tui_*` stub bodies (AD-10 guard already exists in Case NN — re-run passes).
  - [x] Run the full validation suite listed in Testing Standards.

## Dev Notes

### Scope Boundary

This story implements **Step 9 only** — the Claude Code hooks description + confirm + `install.sh --hooks` delegation. Do NOT implement Step 10 extras (Story 1.4), idempotency gate (Story 1.5), dry-run end-to-end diff verification (Story 1.6), or Step 11 summary render (Story 1.7). Leave their placeholder comments untouched. [Source: _bmad-output/planning-artifacts/epics.md#FR-Coverage-Map]

`install.sh`, `lib/wtx-install.sh`, `lib/wtx-config.sh`, and `lib/worktree-tui.sh` are UNCHANGED by this story. [Source: _bmad-output/planning-artifacts/epics.md#NonFunctional-Requirements]

### Exact Placeholder to Replace in `scripts/worktree-install.sh`

At line 394–395 (current after Story 1.2):

```bash
    # Step 9 — Claude Code hooks setup (placeholder — Story 1.3)
    # _wtx_install_step9_claude_hooks
```

Replace with:

```bash
    # Step 9 — Claude Code hooks setup
    _wtx_install_step9_claude_hooks || _run_rc=$?
```

And change the end of `_wtx_install_run` from `return 0` to `return $_run_rc`, initializing `_run_rc=0` near the top of the function body (before Step 1 call).

### Why `_run_rc` Instead of `|| return $?`

Story 1.7 AC requires: "the wizard still exits with non-zero code" when a step fails, but Step 11 summary must still render. Using `|| return $?` would abort before Step 11 (currently a placeholder, but Story 1.7 will fill it in). Using a tracked `_run_rc` lets all remaining steps complete while preserving the failure signal. Introduce `local _run_rc=0` at the top of `_wtx_install_run`'s body and change the final `return 0` to `return $_run_rc`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.7-Completion-summary--doctor-handoff-Step-11]

**Important:** Steps 2 and the TOML write already use `|| return $?` (abort-on-failure). Do NOT change those — they are intentionally abort-style because the wizard cannot proceed meaningfully without PATH or a valid config. Only Step 9 onwards uses the tracked-rc pattern. If you need to maintain the `return $toml_rc` for TOML failure, do so before introducing `_run_rc` tracking:

```bash
_wtx_install_run() {
    local _run_rc=0
    _wtx_install_preflight "$@" || return $?
    # ... (idempotency gate placeholder)
    _wtx_install_step_banner || return $?
    _wtx_install_step2_binary || return $?
    _wtx_install_steps3_7_config || return $?
    _wtx_install_step8_hook || return $?
    wtx_install_write_or_dryrun "would write: $WORKSPACE_ROOT/wtx.toml" _wtx_install_commit_toml
    local toml_rc=$?
    if [[ $toml_rc -eq 0 && "${WTX_INSTALL_DRY_RUN:-0}" != "1" ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("done")
    elif [[ $toml_rc -ne 0 ]]; then
        _WTX_LEDGER_KEYS+=("config")
        _WTX_LEDGER_VALS+=("failed")
        return $toml_rc
    fi
    # Step 9 — Claude Code hooks setup
    _wtx_install_step9_claude_hooks || _run_rc=$?
    # Step 10a/10b — Extras menu (placeholder — Story 1.4)
    # _wtx_install_step10_extras
    # Step 11 — Completion summary + doctor handoff (placeholder — Story 1.7)
    # _wtx_install_step11_summary
    return $_run_rc
}
```

### `tui_confirm` Signature and Default-Yes Behavior

```bash
tui_confirm "prompt?" [default_yes_arg]
```

Pass a non-empty second argument to produce a `[Y/n]` prompt (default yes). The UX-DR10 spec requires `[Y/n]` for hooks. Example:

```bash
tui_confirm "Install Claude Code hooks?" "yes"
```

The return status is 0 for yes, non-zero for no. No bare `read` — the stub fallback in `_wtx_install_source_libs` already implements `tui_confirm() { local r; read -r -p "$1 [y/N] " r < /dev/tty; [[ "$r" =~ ^[Yy]$ ]]; }`. [Source: lib/worktree-tui.sh#tui_confirm] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]

### `tui_style_box` for the Hooks Description

Use `tui_style_box` to display the multi-line hook description. Example structure:

```bash
tui_style_box \
    "Claude Code hooks — what will be installed:" \
    "  worktree-create.sh  — runs after 'wtx start' creates a worktree" \
    "  worktree-detect.sh  — runs when Claude detects the active worktree" \
    "  worktree-remove.sh  — runs after 'wtx done' removes a worktree"
```

`tui_style_box` already has a pure-bash fallback via the stub block in `_wtx_install_source_libs` (line 55: `tui_style_box() { for l in "$@"; do echo "  $l"; done; }`). No second fallback needed. [Source: scripts/worktree-install.sh#_wtx_install_source_libs]

### `install.sh --hooks` Interface (subprocess only — never source)

```bash
bash "$WTX_ROOT/install.sh" --hooks [--dry-run]
```

`install.sh`'s `install_hooks()` copies `worktree-create.sh`, `worktree-detect.sh`, `worktree-remove.sh` from `$WTX_ROOT/hooks/` to `$PWD/.claude/hooks/` (where `$PWD` is the workspace root at subprocess time — which is the same as `$WORKSPACE_ROOT` when the dispatcher sets it). When `--dry-run` is appended, `install.sh` itself prints `[dry-run] would copy hooks/$h -> $destdir/$h` and returns 0 without touching any file. [Source: install.sh#install_hooks] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]

**Important:** `install.sh` uses `$PWD/.claude/hooks` as the destination — the subprocess inherits the CWD from the wizard process, so ensure `WORKSPACE_ROOT` is the CWD when invoking the subprocess, OR confirm that the existing tests in Story 1.1/1.2 already establish this contract (they do — the dispatcher `exec`s scripts from `WORKSPACE_ROOT`).

### Dry-Run Pattern (established by Story 1.2, Step 2)

Follow the exact same pattern used in `_wtx_install_step2_binary`:

```bash
local install_args=("bash" "$WTX_ROOT/install.sh" "--hooks")
if [[ "${WTX_INSTALL_DRY_RUN:-0}" = "1" ]]; then
    install_args+=("--dry-run")
fi
wtx_install_write_or_dryrun "would copy: hooks -> $WORKSPACE_ROOT/.claude/hooks/" "${install_args[@]}"
local rc=$?
```

In dry-run mode, `wtx_install_write_or_dryrun` prints `[dry-run] would copy: hooks -> …` and returns 0 without executing. When it DOES execute, `install.sh --hooks --dry-run` itself prints the per-file `[dry-run] would copy:` lines. No double-printing needed. [Source: lib/wtx-install.sh#wtx_install_write_or_dryrun] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]

### Ledger Append Pattern (established by Stories 1.1/1.2)

```bash
_WTX_LEDGER_KEYS+=("hooks")
_WTX_LEDGER_VALS+=("done")   # or "failed" or "skipped"
```

Append exactly ONE entry regardless of outcome. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]

### Testing Pattern (mirrors Story 1.2 step2 tests)

Drive `_wtx_install_step9_claude_hooks` directly by sourcing `scripts/worktree-install.sh` in a temp git repo — the same pattern used for existing step tests in `tests/test-wtx-install.sh`. Stub `wtx_install_write_or_dryrun` to capture invocation and control the exit code, then assert the ledger state. Re-use `assert_eq` / `assert_contains` / `assert_ok` helpers already in the file (do NOT add any test framework). Reset ledger arrays and unset `_WTX_INSTALL_LIB_LOADED` between cases as needed. [Source: _bmad-output/project-context.md#Testing-Rules] [Source: tests/test-wtx-install.sh#assert-helpers]

### Learnings from Stories 1.1 and 1.2 — Critical Guardrails

1. **Step 0 ordering stays intact:** Do not reorder `dry-run parse → git check → gum detect` inside `_wtx_install_preflight`. Step 9 runs AFTER preflight; `WTX_INSTALL_DRY_RUN` is already exported. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Senior-Developer-Review-AI]

2. **Failure rc must flow:** Story 1.2 review found HIGH issue where `step2_binary` silently swallowed a failed subprocess rc. The hooks step MUST return the subprocess rc on failure (non-zero), not always return 0. `_wtx_install_run` tracks it via `_run_rc`. [Source: _bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md#Senior-Developer-Review-AI]

3. **Test stub restoration:** Story 1.2 review found MEDIUM issue: `unset` the stub AND `_WTX_INSTALL_LIB_LOADED` before re-sourcing the lib to restore the real `wtx_install_write_or_dryrun`. [Source: _bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md#Senior-Developer-Review-AI]

4. **No bare `read`:** AD-10 guard test already exists in the suite. Adding a bare `read` anywhere in `worktree-install.sh` (outside stub bodies in the tui fallback block) will fail Case NN. [Source: _bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md#Debug-Log-References]

5. **`_wtx_csv_to_toml_array` preserves caller's noglob state** — do not wrap new calls in extra `set -f`/`set +f` if you add any. (No TOML write in this story, but worth knowing.) [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Senior-Developer-Review-AI]

### Bash 3.2 / Portability Guardrails (non-negotiable)

- `set -u` only — never `set -e`. [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- No `declare -A`, `mapfile`/`readarray`, `${var^^}`/`${var,,}`, `readlink -f`, or process substitution into arrays. [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- Quote every path: `"$WTX_ROOT"`, `"$WORKSPACE_ROOT"`. [Source: _bmad-output/project-context.md#Critical-Dont-Miss-Rules]
- Errors to stderr via `printf 'wtx install: %s\n' "…" >&2` with meaningful exit codes. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Consistency-Conventions]

### Project Structure Notes

- **File to modify:** `scripts/worktree-install.sh` — add `_wtx_install_step9_claude_hooks()`, replace placeholder, change `_wtx_install_run` to tracked-rc pattern.
- **File to modify:** `tests/test-wtx-install.sh` — add focused test cases for Step 9 (decline, confirm-success, confirm-failure, dry-run).
- **Files that MUST remain behaviorally unchanged:** `lib/wtx-install.sh`, `lib/wtx-config.sh`, `lib/worktree-tui.sh`, `install.sh`, `bin/wtx`.
- **Naming:** `_wtx_install_step9_claude_hooks` (private wizard helper — `_wtx_install_*` prefix), `_run_rc` (local var in `_wtx_install_run`). [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Consistency-Conventions]

### Testing Standards

Required after this story:
- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- `bash tests/test-wtx-config.sh`
- `bash tests/test-wtx-dispatcher.sh`
- `bash tests/test-wtx-install.sh`
- `bash tests/test-install.sh`
- `bash tests/test-worktree-registry.sh`

## References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.3-Claude-Code-hooks-setup-Step-9]
- [Source: _bmad-output/planning-artifacts/epics.md#FR-Coverage-Map]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-12--Preflight-sequence]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-9--Claude-Code-hooks]
- [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Senior-Developer-Review-AI]
- [Source: _bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md#Senior-Developer-Review-AI]
- [Source: install.sh#install_hooks]
- [Source: lib/wtx-install.sh#wtx_install_write_or_dryrun]
- [Source: lib/worktree-tui.sh#tui_confirm]
- [Source: lib/worktree-tui.sh#tui_style_box]
- [Source: scripts/worktree-install.sh#_wtx_install_run]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]

## Dev Agent Record

### Agent Model Used

gpt-5-codex

### Debug Log References

- 2026-06-27: Added failing Step 9 tests first; initial run failed because `_wtx_install_step9_claude_hooks` was not implemented and `_wtx_install_run` returned 0 after the placeholder.
- 2026-06-27: Fixed the decline test harness to capture stdout via a file so ledger mutations remain in the parent shell.
- 2026-06-27: Validation passed: `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`.
- 2026-06-27: Validation passed: `bash tests/test-wtx-config.sh` (26/26), `bash tests/test-wtx-dispatcher.sh` (22/22), `bash tests/test-wtx-install.sh` (104/104), `bash tests/test-install.sh` (25/25), `bash tests/test-worktree-registry.sh` (19/19).
- 2026-06-27: Senior review found that Step 9 delegated `install.sh --hooks` from the caller's current directory, so hooks could be copied under a nested `$PWD/.claude/hooks` instead of `$WORKSPACE_ROOT/.claude/hooks`. Fixed by running the delegated hook install from `WORKSPACE_ROOT` and restoring the caller directory.
- 2026-06-27: Review validation passed: `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`; `bash tests/test-wtx-config.sh` (26/26); `bash tests/test-wtx-dispatcher.sh` (22/22); `bash tests/test-wtx-install.sh` (118/118); `bash tests/test-install.sh` (25/25); `bash tests/test-worktree-registry.sh` (19/19).

### Completion Notes List

- Implemented `_wtx_install_step9_claude_hooks` with the required hooks description box, default-yes confirmation, decline skip path, `install.sh --hooks` delegation, dry-run argument propagation, and exactly one `hooks` ledger entry for each outcome.
- Replaced the Step 9 placeholder in `_wtx_install_run` with tracked `_run_rc` handling so a hooks failure is surfaced at wizard exit while later placeholders can still execute.
- Added focused Step 9 tests covering decline, success, failure, dry-run args, AD-10 read guard, and `_wtx_install_run` Step 9 rc propagation.
- Senior review auto-fixed the hook installation working directory so actual hook copies land in `$WORKSPACE_ROOT/.claude/hooks/` even when `wtx install` is invoked from a nested directory, with byte-for-byte regression coverage for all three hooks.

### Senior Developer Review (AI)

Reviewer: Codex on 2026-06-27

Outcome: Approved after auto-fix. No critical issues remain.

Inputs loaded:
- Story file: `_bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md`
- Story context: no separate story-context file found; reviewed story, UX flow, epics, project context, architecture spine, dispatcher, install script, wizard source, and tests.
- Epic tech spec: no standalone epic tech spec found; reviewed `_bmad-output/planning-artifacts/epics.md`, `_bmad-output/specs/spec-wtx-install/ux-flow.md`, and `_bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md`.
- Tech stack: pure Bash targeting bash 3.2, shell-only tests.
- MCP/doc search: no MCP documentation resources were available in this environment.

Findings fixed:
- HIGH: `_wtx_install_step9_claude_hooks` delegated `bash "$WTX_ROOT/install.sh" --hooks` without ensuring the subprocess ran from `WORKSPACE_ROOT`. Because `install.sh` copies hooks to `$PWD/.claude/hooks`, invoking `wtx install` from a nested directory could satisfy the ledger while leaving `$WORKSPACE_ROOT/.claude/hooks/` unchanged, violating AC 2. Fixed by changing to `WORKSPACE_ROOT` around the delegated write and restoring the caller directory afterward; added regression coverage that compares all three copied hooks byte-for-byte.

Validation:
- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` passed.
- `bash tests/test-wtx-config.sh` passed: 26/26.
- `bash tests/test-wtx-dispatcher.sh` passed: 22/22.
- `bash tests/test-wtx-install.sh` passed: 118/118.
- `bash tests/test-install.sh` passed: 25/25.
- `bash tests/test-worktree-registry.sh` passed: 19/19.

### File List

- scripts/worktree-install.sh
- tests/test-wtx-install.sh
- _bmad-output/implementation-artifacts/1-3-claude-code-hooks-setup-step-9.md
- _bmad-output/implementation-artifacts/sprint-status.yaml
- _bmad-output/implementation-artifacts/tests/test-summary.md

### Change Log

- 2026-06-27: Implemented Story 1.3 Claude Code hooks setup and marked story ready for review.
- 2026-06-27: Senior review auto-fixed Step 9 hook destination handling, added nested-cwd byte-for-byte regression coverage, and marked story done.
