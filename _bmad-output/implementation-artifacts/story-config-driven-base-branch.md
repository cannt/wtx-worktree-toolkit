---
status: done
source: docs-sync-triage
date: 2026-04-15
---

# Story: Read `defaults.base_branch` from config in `worktree-start.sh`

## Context

`docs/commands.md` (and `CLAUDE.md`) document that `wtx start`'s `[base-branch]`
argument defaults to `develop` **or** `defaults.base_branch` from `wtx.toml`.
The portability overhaul (`PORTABILITY_PROMPT.md`) explicitly lists `base_branch`
as "already config-driven". However, `scripts/worktree-start.sh` line 107 hardcodes
`BASE_BRANCH="${2:-develop}"` and never calls `wtx_config_get "defaults.base_branch"`.
`lib/worktree-interactive.sh` similarly hardcodes `develop` as the default base branch
in the TUI flow.

## Goal

Wire `scripts/worktree-start.sh` and the interactive TUI flow in
`lib/worktree-interactive.sh` to read `defaults.base_branch` from config (with `develop`
as the fallback when the key is absent), so that workspace owners who set
`base_branch = "main"` in their `wtx.toml` get the correct default without passing
an explicit argument.

## Acceptance Criteria

- [x] `scripts/worktree-start.sh` reads `defaults.base_branch` via
  `wtx_config_get "defaults.base_branch" "develop"` when no `[base-branch]` argument
  is supplied. Explicit argument on the command line still wins.
- [x] `lib/worktree-interactive.sh`'s `interactive_start()` uses the same config-driven
  default when populating the base-branch TUI step.
- [x] A new fixture-driven test case in `tests/test-wtx-config.sh` (or a new test file)
  verifies that `wtx_config_get "defaults.base_branch"` returns the configured value
  and falls back to `develop` when absent.
- [x] `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` passes cleanly.
- [x] Existing test suites (`test-wtx-config.sh`, `test-wtx-dispatcher.sh`) still pass.

## Out of scope

- `defaults.branch_prefix` config-driven behavior (may or may not already be wired;
  out of scope for this story).
- `hooks/worktree-create.sh` — verify separately whether it also needs the same fix.

## Notes

- `wtx_config_get` must be sourced before use; the inline-stub fallback pattern applies.
- `worktree-start.sh` already sources `lib/wtx-config.sh` indirectly via
  `lib/worktree-tui.sh`. No new source lines needed — just add the `wtx_config_get` call.
- `lib/worktree-interactive.sh` sources `lib/worktree-tui.sh`, which sources
  `lib/wtx-config.sh`, so `wtx_config_get` is already available there too.

## Dev Agent Record

### Completion Notes

Wired `defaults.base_branch` config key in both call sites using the `command -v wtx_config_get` guard pattern already established in `worktree-start.sh` (see setup_hook lookup). Explicit CLI arg still wins via `BASE_BRANCH="${2:-}"` → config fallback ordering. The interactive TUI fallback (no remote branches found) follows the same guard. New fixture `tests/fixtures/config-base-branch.toml` with `base_branch = "main"` drives two new test cases (Cases 15–16) covering the configured-value and absent-key paths. All 26 config tests and 16 dispatcher tests pass; syntax check clean.

## File List

- `scripts/worktree-start.sh` — replaced hardcoded `${2:-develop}` with config-driven resolution after config sourcing
- `lib/worktree-interactive.sh` — replaced hardcoded `BASE_BRANCH="develop"` fallback with `wtx_config_get` call
- `tests/fixtures/config-base-branch.toml` — new fixture for `defaults.base_branch = "main"`
- `tests/test-wtx-config.sh` — added Cases 15–16 for `defaults.base_branch`

## Review Findings

- [x] [Review][Patch] Interactive TUI does not guarantee the configured base branch is the default [lib/worktree-interactive.sh:197]

## Change Log

- 2026-04-15: Wired `defaults.base_branch` from config in `worktree-start.sh` and `worktree-interactive.sh`; added fixture and two test cases
