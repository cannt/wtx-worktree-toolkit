# Test Automation Summary

## Generated Tests

### API Tests
- [x] Not applicable - Story 1.4 is a shell installer wizard flow with no API endpoint.

### E2E Tests
- [x] `tests/test-wtx-install.sh` - Case 44: full wizard dry-run reaches Step 10, shows the Gradle one-line explanation, honors default-no Gradle, shows the default-yes PATH hint, and writes no files.
- [x] `tests/test-wtx-install.sh` - Case 45: full wizard real run confirms Gradle, delegates through `install.sh --gradle`, installs the Gradle init file under a temporary `HOME`, writes `wtx.toml`, and suppresses the wizard PATH hint when the prefix is already on `PATH`.

## Coverage

- API endpoints: 0/0 covered.
- UI/E2E flows for Story 1.4: 2/2 added.
- Existing focused Step 10 shell cases retained: Gradle decline/success/failure/dry-run, PATH already present, PATH decline/show with default and custom prefixes, and Step 9/10 `_run_rc` wiring.

## Validation

- [x] `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- [x] `bash tests/test-wtx-config.sh`
- [x] `bash tests/test-wtx-dispatcher.sh`
- [x] `bash tests/test-wtx-install.sh`
- [x] `bash tests/test-install.sh`
- [x] `bash tests/test-worktree-registry.sh`

## Next Steps

- No further Story 1.4 E2E gaps identified.

---

# Test Automation Summary — Story 1.3: Claude Code hooks setup (Step 9)

Generated: 2026-06-27

## QA Gap Cases Added (Cases 31-34)

Four gaps were identified against the Story 1.3 ACs and auto-applied to `tests/test-wtx-install.sh`:

| Gap | Added case | AC |
|-----|-----------|-----|
| Ledger count never asserted — AC5 says "exactly one entry appended" | Case 31 | AC5 |
| Hook descriptions not checked — only filenames were asserted | Case 32 | AC1 |
| Actual hook copy destination not tested when invoked below `WORKSPACE_ROOT` | Case 33 | AC2 |
| `_wtx_install_run` success path not tested (only failure in Case 29) | Case 34 | Integration |

- [x] Case 31 — exactly 1 ledger entry per outcome (decline / success / failure)
- [x] Case 32 — one-liner descriptions for all 3 hooks present in info box
- [x] Case 33 — real `install.sh --hooks` copies all three hooks byte-for-byte into `$WORKSPACE_ROOT/.claude/hooks/` from a nested current directory
- [x] Case 34 — `_wtx_install_run` with step9 returning 0 keeps `_run_rc=0`, returns 0

## Validation results (all required suites)

| Suite | Result |
|-------|--------|
| `bash -n` syntax (bin/lib/scripts/hooks/plugins) | OK |
| `tests/test-wtx-install.sh` | 118/118 ✅ (was 104; +14 assertions across Cases 31-34) |
| `tests/test-wtx-config.sh` | 26/26 ✅ |
| `tests/test-wtx-dispatcher.sh` | 22/22 ✅ |
| `tests/test-install.sh` | 25/25 ✅ |
| `tests/test-worktree-registry.sh` | 19/19 ✅ |

---

# Test Automation Summary — Story 1.2

**Feature:** Reference-templating engine — config prompts, plugin discovery & TOML write
**Story file:** `_bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md`
**Date:** 2026-06-27
**Framework:** Repo-native bash assertion harness (`assert_eq` / `assert_contains` / `assert_ok`). No bats/shunit2/CI — consistent with project convention (shell-only validation).

## Scope

`wtx` is a CLI/shell toolkit — there is no HTTP API and no GUI, so "API/E2E" maps to
**wizard integration tests** that exercise the pure deterministic surfaces of the
install wizard (`scripts/worktree-install.sh`) and round-trip the generated `wtx.toml`
through the real config loader (`wtx_config_get` / `wtx_config_get_list`). Interactive
TUI driving has no harness in this repo (documented deferral) so prompts are exercised
through `tui_*` stubs, exactly as the story's Testing Notes prescribe.

## Gap analysis (pre-existing suite vs. Story 1.2 ACs)

The suite already had Cases 12–16 (TOML round-trip subset, Jira-empty, setup_hook-empty,
plugin map, AD-10 guard). The following ACs were **under-covered** and have now been
filled — auto-applied to `tests/test-wtx-install.sh`:

| AC | Gap before | Added coverage (case) |
|----|-----------|------------------------|
| AC 1 | Banner content never asserted | Case 17 — workspace path, WTX root, Ctrl-C notice |
| AC 2 | Already-on-PATH skip + ledger entry untested | Case 18 — `[✓] wtx already on PATH` + ledger `symlink=skipped (already on PATH)` |
| AC 3 | rc→ledger `done`/`failed` mapping untested | Case 19 — stub chokepoint exit 0 → rc 0 + `done`, non-zero → rc + `failed` |
| AC 5 | Forge options not asserted to be exactly the three | Case 20 — github/gitlab/bitbucket present, no extras |
| AC 7/8 | Only 4 keys round-tripped; base_url, jira pairs, lists, worktree defaults, setup_hook untested | Case 21 — full round-trip via `wtx_config_get`/`wtx_config_get_list` |
| AC 5 | `.git` default → comment-only / base_url omission untested | Case 22 — no uncommented `markers`/`base_url` keys |
| AC 6 | None / Custom-path branches of Step 8 untested | Cases 23–24 — None → empty, Custom → user path |

## Generated / extended tests

### Wizard integration tests — `tests/test-wtx-install.sh`
- [x] Case 17 — Step 1 banner renders workspace path, WTX root, Ctrl-C abort notice (AC 1)
- [x] Case 18 — Step 2 already-on-PATH skip + ledger `skipped (already on PATH)` (AC 2)
- [x] Case 19 — Step 2 delegation rc→ledger `done`/`failed` mapping (AC 3)
- [x] Case 20 — Step 3 forge options are exactly github/gitlab/bitbucket (AC 5)
- [x] Case 21 — full round-trip: base_url, jira pairs, projects.list (trim+split), detection.markers, worktree registry_path/builtin_path defaults, setup_hook (AC 7, 8)
- [x] Case 22 — `.git` detection default → comment-only markers; base_url omitted when not self-hosted (AC 5)
- [x] Case 23 — Step 8 None → empty setup_hook (AC 6)
- [x] Case 24 — Step 8 Custom path… → user-supplied relative path (AC 6)
- [x] Case 25 — `_wtx_install_run` propagates Step 2 and TOML write failures with ledger evidence (AC 3, AC 7, NFR10)

## Coverage

- Story 1.2 acceptance criteria with deterministic surface: **AC 1, 2, 3, 4, 5, 6, 7, 8, 9, 11 covered**.
- AC 10 (full step ordering) is exercised end-to-end by pre-existing Cases 7–8 (dry-run full run) plus the syntax gate (AC 11).
- Interactive end-to-end TUI flow: **deferred** (no harness — same deferral as existing wizard scripts; pure functions tested directly instead).

## Validation results (all required suites)

| Suite | Result |
|-------|--------|
| `bash -n` syntax (bin/lib/scripts/hooks/plugins) | OK |
| `tests/test-wtx-install.sh` | 85/85 ✅ (was 53; +32 assertions) |
| `tests/test-wtx-config.sh` | 26/26 ✅ |
| `tests/test-wtx-dispatcher.sh` | 22/22 ✅ |
| `tests/test-install.sh` | 25/25 ✅ |
| `tests/test-worktree-registry.sh` | 19/19 ✅ |

## Next steps

- When the interactive TUI gains a test harness, layer end-to-end prompt-driving on top.
- Re-run this suite after Stories 1.3–1.7 fill the placeholder steps to guard regressions in the shared write/ledger path.
