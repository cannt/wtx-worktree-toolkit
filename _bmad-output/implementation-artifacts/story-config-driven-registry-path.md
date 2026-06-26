---
status: done
source: docs-sync-triage
date: 2026-04-15
---

# Story: Read `worktree.registry_path` from config in `worktree-tui.sh`

## Context

`CLAUDE.md`, `docs/architecture.md`, and `_bmad-output/project-context.md` all state
that the worktree registry path is "config-driven via `worktree.registry_path`".
The `wtx.example.toml` documents the key and the portability overhaul lists it as
already wired. However, `lib/worktree-tui.sh`'s `update_registry()` and its callers
hardcode `$WORKSPACE_ROOT/.claude/worktree-registry.md` without calling
`wtx_config_get "worktree.registry_path"`. The default path happens to match, so
the tool works, but the config key is silently ignored.

## Goal

Wire `lib/worktree-tui.sh` to read `worktree.registry_path` from config so that
workspace owners who set a custom registry path in `wtx.toml` get the correct
behaviour.

## Acceptance Criteria

- [x] `update_registry()` in `lib/worktree-tui.sh` resolves the registry path via
  `wtx_config_get "worktree.registry_path" ".claude/worktree-registry.md"` (relative
  to `$WORKSPACE_ROOT`) instead of the hardcoded string.
- [x] All other locations in `worktree-tui.sh` that reference the registry path
  (currently lines ~416, ~537, ~670) are updated consistently to use the same
  config-driven resolution.
- [x] A fixture-driven test case verifies that a non-default `registry_path` in
  `wtx.toml` is respected by the registry helpers.
- [x] `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` passes cleanly.
- [x] Existing test suites still pass.

## Notes

- The config-driven value is relative to `$WORKSPACE_ROOT`; prepend it when building
  the absolute path: `"$WORKSPACE_ROOT/$(wtx_config_get "worktree.registry_path" ".claude/worktree-registry.md")"`.
- `wtx_config_get` is already available inside `worktree-tui.sh` (it sources
  `lib/wtx-config.sh` on load).
- Three docs will become accurate once this lands: `CLAUDE.md`, `docs/architecture.md`,
  and `_bmad-output/project-context.md` — no doc changes needed.

## Dev Agent Record

### Implementation Plan

Added `_registry_path()` helper to `lib/worktree-tui.sh` that centralises the
config-driven path resolution. Updated `update_registry()`, `_registry_add()`,
`_registry_remove()`, and `_registry_refresh()` to call `_registry_path()` instead
of hardcoding the path. Created `tests/fixtures/config-custom-registry.toml` with a
non-default `registry_path` and `tests/test-worktree-registry.sh` with fixture-driven
test cases covering add, remove, refresh, fallback, and invalid configured paths.

### Completion Notes

- `_registry_path()` placed just before `update_registry()` in `lib/worktree-tui.sh`
- Uses `command -v wtx_config_get` guard (same pattern as `get_known_projects()`) so
  the helper degrades gracefully if `wtx-config.sh` failed to source
- All 4 registry functions updated; no hardcoded `.claude/worktree-registry.md` remain
- 19/19 registry tests pass; 26/26 config tests pass; 16/16 dispatcher tests pass; syntax OK

## File List

- `lib/worktree-tui.sh` — added `_registry_path()`, updated 4 functions
- `tests/test-worktree-registry.sh` — fixture-driven registry test suite
- `tests/fixtures/config-custom-registry.toml` — fixture with custom registry_path
- `tests/fixtures/config-registry-absolute.toml` — invalid absolute registry_path fixture
- `tests/fixtures/config-registry-empty.toml` — empty registry_path fixture
- `tests/fixtures/config-registry-nested-parent.toml` — invalid nested parent registry_path fixture
- `tests/fixtures/config-registry-parent.toml` — invalid parent registry_path fixture

## Change Log

- 2026-04-15: Implemented config-driven registry path resolution via `_registry_path()` helper; added `tests/test-worktree-registry.sh`
- 2026-06-26: Applied review fixes for path validation, registry test isolation/coverage, and validation documentation

## Review Findings

- [x] [Review][Patch] Restrict `registry_path` to workspace-contained relative paths, falling back to the default for absolute paths, empty values, and `..` segments. [lib/worktree-tui.sh:395]
- [x] [Review][Patch] Isolate `HOME` in registry-path tests so user global config cannot affect default-path cases. [tests/test-worktree-registry.sh:52]
- [x] [Review][Patch] Strengthen the refresh test to prove `update_registry refresh` touches the configured custom file and does not create/use the default registry path. [tests/test-worktree-registry.sh:97]
- [x] [Review][Patch] Add the new registry test to the documented validation commands so future runs do not skip it. [CLAUDE.md:11]
- [x] [Review][Patch] Make `assert_in_recently_closed` use literal matching instead of interpolating an unescaped regex into awk. [tests/test-worktree-registry.sh:37]
