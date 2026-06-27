# Test Automation Summary — Story 1.6: Dry-run mode end-to-end threading

**Feature:** `wtx install --dry-run` previews every wizard mutation without writing files.
**Story file:** `_bmad-output/implementation-artifacts/1-6-dry-run-mode-end-to-end-threading.md`
**Date:** 2026-06-27
**Framework:** Repo-native bash assertion harness (`assert_eq` / `assert_contains` / `assert_ok`) — shell-only, no external test framework.

## Scope

`wtx` is a shell CLI with no HTTP API and no browser UI. For this story, "E2E" means full wizard runs against temporary git workspaces using the existing gum shim, with filesystem assertions before and after `scripts/worktree-install.sh --dry-run`.

## Generated / extended tests

### API Tests
- [x] Not applicable — Story 1.6 is a Bash CLI installer wizard flow with no HTTP/API endpoint.

### E2E / integration tests
- [x] `tests/test-wtx-install.sh` Story 1.6 Cases 60-68 cover dry-run parsing, write chokepoint behavior, delegated `install.sh --dry-run` arguments, truthful dry-run ledger values, Step 11 note, static no-bypass guard, and full wizard dry-run flows.
- [x] Added direct `--dry-run` parser assertions: `_wtx_install_parse_args --dry-run` returns 0, sets `WTX_INSTALL_DRY_RUN=1`, and exports the flag to child commands.
- [x] Added overwrite dry-run prompt assertions: existing `wtx.toml` + `overwrite` still drives the downstream forge/org/detection/defaults/setup-hook prompts while leaving the file byte-for-byte unchanged.
- [x] `tests/test-wtx-install.sh` Case 66 now also asserts the dry-run does not create `$WORKSPACE_ROOT/.claude/hooks/`, not only individual hook files.
- [x] `tests/test-wtx-install.sh` Case 67 now asserts overwrite dry-run emits the required Step 11 dry-run note exactly once.
- [x] `tests/test-wtx-install.sh` Case 68 now asserts merge dry-run emits the required Step 11 dry-run note exactly once.

## Coverage

- Story 1.6 dry-run helper, parse/export, delegated `--dry-run` args, guarded symlink/TOML/hooks/Gradle preview paths, truthful preview ledger values, no direct `install.sh` bypass, new-config E2E, overwrite E2E, merge E2E, no TOML temp leftovers, no hook directory creation, and exact Step 11 note coverage are now covered.
- API endpoints: 0/0 covered.
- UI/E2E flows for Story 1.6: 3/3 required dry-run wizard paths covered.
- Critical dry-run mutation targets asserted absent/unchanged: `wtx.toml`, `.wtx-install-tmp.*`, `.claude/hooks/worktree-*.sh`, prefix `bin/wtx`, and Gradle init script.
- Critical error/edge cases covered: skipped existing config path preserves optional failure rc, direct `install.sh` bypass static guard, overwrite and merge dry-run preserve existing TOML.

## Validation results

| Suite | Result |
|-------|--------|
| `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` | OK |
| `bash tests/test-wtx-config.sh` | 26/26 OK |
| `bash tests/test-wtx-dispatcher.sh` | 22/22 OK |
| `bash tests/test-wtx-install.sh` | 283/283 OK |
| `bash tests/test-install.sh` | 25/25 OK |
| `bash tests/test-worktree-registry.sh` | 19/19 OK |

## Next Steps

- No further Story 1.6 E2E test gaps identified.

---

# Test Automation Summary — Story 1.5: Idempotency — skip / overwrite / merge

**Feature:** Idempotency gate for `wtx install` when `wtx.toml` already exists.
**Story file:** `_bmad-output/implementation-artifacts/1-5-idempotency-skip-overwrite-merge.md`
**Date:** 2026-06-27
**Framework:** Repo-native bash assertion harness (`assert_eq` / `assert_contains` / `assert_ok`) — shell-only, no bats/shunit2/CI (project convention).

## Scope

`wtx` is a CLI/shell toolkit — no HTTP API, no GUI, so "API/E2E" maps to **wizard
integration tests** that drive `scripts/worktree-install.sh` through `tui_*` stubs and
round-trip generated `wtx.toml` through the real config loader. Story 1.5 already shipped
Cases 46–53; this run audited those against the 7 ACs and filled the remaining branch gaps.

## Gap analysis (Cases 46–53 vs. Story 1.5 ACs)

Eight branches/properties were under-covered and auto-applied to `tests/test-wtx-install.sh` as additions to Case 47 and new Cases 54–59:

| Gap | Added coverage | AC |
|-----|---------------|-----|
| Skip path: ledger count never verified — AC2 requires **exactly one** entry | 2 assertions in Case 47 | AC 2 |
| Skip path: **TOML byte-for-byte unchanged** at unit level (only E2E Case 53 covered it) | 2 assertions in Case 47 | AC 2 |
| Gate with an **existing** `wtx.toml` — style box + chooser offering *exactly* `skip`/`overwrite`/`merge`, mode assigned, file untouched before choice (Case 46 only covered the no-file path) | Case 54 | AC 1 |
| Run-level **merge wiring** in `_wtx_install_run` (unset `_WTX_CONFIG_LOADED` → set `WTX_CONFIG` → re-source loader); Case 50 tested `steps3_7` in isolation with config pre-loaded by hand | Case 55 | AC 4 |
| Detection-markers **`Custom…` pre-fill** when the existing value matches no preset (Case 50 only covered the `Cargo.toml`→Rust preset) | Case 56 | AC 4 |
| Step 8 **non-plugin `setup_hook`** → preselect `Custom path…` + pre-fill input (Case 51 only covered a `plugins/` path) | Case 57 | AC 4 |
| Step 8 **empty `setup_hook`** → preselect `None`, clears hook | Case 58 | AC 4 |
| Full run still created `.wtx-install-tmp.*` during preflight before the idempotency choice; AC1 requires no files touched before the choice | Case 59 plus source fix | AC 1 |

> Note on harness pattern: `tui_*` prompts are invoked via `$(...)` command substitution,
> so stub side-effects must be captured to **files**, not shell variables (the Story 1.4
> file-redirection lesson). Cases 54–59 follow this pattern where needed.

## Generated / extended tests — `tests/test-wtx-install.sh`

- [x] Case 54 — gate (existing TOML): `tui_style_box` shown once; `tui_choose` invoked once offering exactly `skip overwrite merge`; `_WTX_INSTALL_MODE` assigned; `wtx.toml` `cksum` unchanged before the choice (AC 1)
- [x] Case 55 — merge run: `_wtx_install_run` resets the stale loader guard, points `WTX_CONFIG` at `$WORKSPACE_ROOT/wtx.toml`, re-sources `lib/wtx-config.sh`, and the re-sourced config is readable (sentinel `forge.org`) (AC 4)
- [x] Case 56 — merge detection markers (`["Makefile","flake.nix"]`): `tui_choose` pre-selects `Custom…`, custom `tui_input` pre-filled with the CSV, `detection_csv` preserved (AC 4)
- [x] Case 57 — merge Step 8 (`scripts/my-custom-hook.sh`): pre-selects `Custom path…`, path `tui_input` pre-filled, `setup_hook` preserved (AC 4)
- [x] Case 58 — merge Step 8 (no `setup_hook`): pre-selects `None`, `setup_hook` left empty (AC 4)
- [x] Case 59 — real preflight + skip gate: no `.wtx-install-tmp.*` exists before the idempotency choice, and no temp file is left behind (AC 1)

## Coverage

- Story 1.5 ACs with deterministic surface: **AC 1, 2, 3, 4, 5, 6 covered**; AC 7 is the `bash -n` syntax gate (green).
- Pre-existing Cases 46–53 retained (no-file→overwrite, skip ledger/bypass, overwrite no-prefill + run order, merge prompt defaults, merge plugin preselect, merge round-trip equivalence, two-run skip byte-identical).
- Interactive end-to-end TUI driving: **deferred** (no harness — same documented deferral as prior stories).

## Validation results (all required suites)

| Suite | Result |
|-------|--------|
| `bash -n` syntax (bin/lib/scripts/hooks/plugins) | OK |
| `tests/test-wtx-install.sh` | 224/224 ✅ (was 202; +2 in Case 47 + 20 across Cases 54–59) |
| `tests/test-wtx-config.sh` | 26/26 ✅ |
| `tests/test-wtx-dispatcher.sh` | 22/22 ✅ |
| `tests/test-install.sh` | 25/25 ✅ |
| `tests/test-worktree-registry.sh` | 19/19 ✅ |

## Next steps

- No further Story 1.5 branch gaps identified.
- When the interactive TUI gains a test harness, layer end-to-end prompt-driving over the gate.

---

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
