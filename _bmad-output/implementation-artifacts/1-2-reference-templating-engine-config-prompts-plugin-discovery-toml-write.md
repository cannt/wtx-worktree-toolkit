---
baseline_commit: daac6e0129dd23a22047577d5b36355df5347e36
---

# Story 1.2: Reference-templating engine — config prompts, plugin discovery & TOML write

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer setting up wtx in a new workspace,
I want the wizard to collect my forge, project, branch, Jira, and hook preferences through a polished TUI and write a `wtx.toml` containing my actual values with no example placeholders,
so that I can start using `wtx start` immediately without manually editing any file.

**Prerequisite:** Story 1.1 is `done`. The write primitives `_wtx_toml_escape`, `_wtx_csv_to_toml_array`, `wtx_install_discover_plugins`, and `wtx_install_write_or_dryrun`, plus the `$_WTX_INSTALL_TMP` temp-file + `trap … EXIT` pattern and the empty `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS` arrays, are already defined and verified in `lib/wtx-install.sh` and `scripts/worktree-install.sh`. This story CONSUMES them — it does not re-implement them. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#File-List]

## Acceptance Criteria

1. Given the wizard reaches Step 1 (welcome banner), when the banner is displayed, then it shows workspace path (`$WORKSPACE_ROOT`) and WTX root (`$WTX_ROOT`) and a Ctrl-C abort notice; with gum a styled box (`tui_style_box`), without gum the same text via plain `echo`/`printf` without border. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-1--Welcome-banner] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]

2. Given the wizard reaches Step 2 (binary install) and `wtx` is already on PATH and resolves (after symlink-walk) to `$WTX_ROOT/bin/wtx`, when Step 2 runs, then the symlink step is skipped, the info text `[✓] wtx already on PATH` is displayed, and the ledger appends one entry: key `symlink`, value `skipped (already on PATH)`. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-2--Binary-install] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]

3. Given the wizard reaches Step 2 and `wtx` is not yet on PATH (or resolves elsewhere), when the user confirms or edits the install prefix (default `~/.local`), then the wizard runs `bash "$WTX_ROOT/install.sh" --prefix "$WTX_INSTALL_PREFIX"` as a subprocess routed through `wtx_install_write_or_dryrun` and checks its exit code; the ledger records `symlink: done` (exit 0) or `symlink: failed` (non-zero). [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh] [Source: install.sh#usage]

4. Given Steps 3–7 collect forge type, forge org, optional self-hosted base URL, project dirs, detection markers, branch defaults, and Jira pairs, when each prompt is presented, then it calls the appropriate `tui_*` function from `lib/worktree-tui.sh`; no bare `read` appears anywhere in `worktree-install.sh`; every prompt has a functional pure-bash fallback. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency] [Source: _bmad-output/planning-artifacts/epics.md#NonFunctional-Requirements]

5. Given the user selects forge type (Step 3), when the `tui_choose` list is shown, then the options are exactly `github`, `gitlab`, `bitbucket`; the selected value is stored as `forge_type` and written verbatim to `[forge].type`; no hardcoded default survives in the config when the user changes it. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-3--Forge-configuration] [Source: _bmad-output/planning-artifacts/epics.md#NonFunctional-Requirements]

6. Given Step 8 (setup hook) is reached, when `wtx_install_discover_plugins` runs, then it globs `$WTX_ROOT/plugins/*.sh`, reads each file's first `# wtx-plugin-desc:` line via `grep -m1`/line scan, and emits `filename<TAB>description` pairs; the wizard prepends `None` and `Custom path…` before passing the display list to `tui_choose`; the selected plugin is written to `[worktree].setup_hook` as `plugins/<filename>` (None → key omitted/commented; Custom → user-supplied relative path). [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-8--Plugin-discovery] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-8--Setup-hook] [Source: wtx.example.toml#worktree]

7. Given the user completes all config prompts (Steps 2–8), when the wizard writes `wtx.toml`, then it builds the file content using `_wtx_toml_escape` for scalars and `_wtx_csv_to_toml_array` for comma-input arrays, writes to `$_WTX_INSTALL_TMP`, then `mv`s it to `$WORKSPACE_ROOT/wtx.toml` — both gated through `wtx_install_write_or_dryrun` (consuming the AD-4 / AD-5 primitives from Story 1.1); no value matching the `wtx.example.toml` placeholder set (e.g. `org = "acme"`, `list = ["web", "mobile", "backend"]`, `markers = ["settings.gradle", ...]`) survives in the written file. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-4--Atomic-TOML-write] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-9--No-config-schema-extension]

8. Given the written `wtx.toml` is validated, when `wtx_config_get` reads any key from it, then the returned value matches what the user entered at the corresponding prompt; no example placeholder is present. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: lib/wtx-config.sh#wtx_config_get]

9. Given a Jira section with zero mappings is the user's choice (Step 7), when `wtx.toml` is written, then a `[jira.projects]` section is present but contains only a comment; no Jira keys are fabricated. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-7--Jira-project-key-mapping]

10. Given the wizard executes its steps end to end, when the flow runs, then the step order matches the UX rationale table: Step 0 → idempotency gate (placeholder until Story 1.5) → Step 1 → Step 2 → Steps 3–8 (core config) → atomic TOML write → Step 9 (placeholder until Story 1.3) → Step 10a/10b (placeholders until Story 1.4) → Step 11 (placeholder until Story 1.7); this story implements Step 1 through the TOML write only. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Wizard-ordering-rationale] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-13--Idempotency-gate-placement]

11. Given `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story, when syntax-check completes, then it exits 0 with no errors. [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write] [Source: _bmad-output/project-context.md#Technology-Stack--Versions]

## Tasks / Subtasks

- [x] Implement Step 1 — welcome banner (AC: 1)
  - [x] Add `_wtx_install_step_banner` that renders workspace path, WTX root, and Ctrl-C abort notice via `tui_style_box`.
  - [x] Confirm `tui_style_box` already falls back to a plain box/echo when `has_gum` is false — do not add a second fallback path.
- [x] Implement Step 2 — binary install with PATH detection (AC: 2, 3)
  - [x] Detect existing `wtx`: `command -v wtx`, then symlink-walk the result (no `readlink -f`; reuse the `BASH_SOURCE`/`readlink` walk style already in this script) and compare against `$WTX_ROOT/bin/wtx`.
  - [x] On match: print `[✓] wtx already on PATH`, append ledger entry `symlink` = `skipped (already on PATH)`, skip the prefix prompt.
  - [x] On no match: `tui_input "Install prefix" "$HOME/.local"` → `WTX_INSTALL_PREFIX`; export it (Story 1.4 Step 10b consumes it).
  - [x] Delegate: `wtx_install_write_or_dryrun "would create: \$WTX_INSTALL_PREFIX/bin/wtx" bash "$WTX_ROOT/install.sh" --prefix "$WTX_INSTALL_PREFIX"`; check the return code; append ledger `symlink` = `done` / `failed`.
  - [x] Append `--dry-run` to the `install.sh` argument list when `WTX_INSTALL_DRY_RUN=1` (AD-3). (Full dry-run sweep is Story 1.6; wire the flag at this site now.)
- [x] Implement Steps 3–7 — config prompts (AC: 4, 5, 9)
  - [x] Step 3: `tui_choose "Forge type" github gitlab bitbucket` → `forge_type`; `tui_input "Forge org / owner slug"` → `forge_org`; `tui_confirm "Self-hosted instance?"` then `tui_input "Base URL"` → optional `forge_base_url`.
  - [x] Step 4: `tui_input "Known project dirs (comma-separated, optional)"` → `projects_csv` (may be empty).
  - [x] Step 5: `tui_choose` from preset list (`.git (any git repo — default)`, `Gradle / Android`, `Rust`, `Node.js`, `Custom…`); map to marker arrays (.git → none; Gradle → `settings.gradle,settings.gradle.kts`; Rust → `Cargo.toml`; Node.js → `package.json`); Custom → `tui_input` CSV → `detection_csv`.
  - [x] Step 6: `tui_input "Default base branch" "main"` → `base_branch`; `tui_input "Default branch prefix" "feature"` → `branch_prefix`.
  - [x] Step 7: iterative loop — `tui_input "Repo name (blank to skip)"`; if non-blank, `tui_input "Jira key for \"$repo\""`, accumulate into the parallel arrays `_WTX_JIRA_REPOS`/`_WTX_JIRA_KEYS` (bash 3.2 indexed, no `declare -A`), then `tui_confirm "Add another?"`; loop until blank/decline.
- [x] Implement Step 8 — plugin discovery + setup-hook selection (AC: 6)
  - [x] Call `wtx_install_discover_plugins`; read its `filename<TAB>desc` lines into parallel indexed arrays (split on the literal tab; do not use `declare -A`).
  - [x] Build a display list prepended with `None` and `Custom path…`; pass to `tui_choose`; resolve the chosen label back to a filename (or capture a `tui_input` custom relative path).
  - [x] Store as `setup_hook` = empty (None) / `plugins/<filename>` / `<custom-path>`.
- [x] Implement the atomic TOML write (AC: 7, 8, 9)
  - [x] Add `_wtx_install_emit_toml` that prints the full file to stdout using `_wtx_toml_escape` for every scalar and `_wtx_csv_to_toml_array` for `projects.list` and `detection.markers`.
  - [x] Add `_wtx_install_commit_toml`: `_wtx_install_emit_toml > "$_WTX_INSTALL_TMP" && mv "$_WTX_INSTALL_TMP" "$WORKSPACE_ROOT/wtx.toml"`.
  - [x] Gate the commit through `wtx_install_write_or_dryrun "would write: $WORKSPACE_ROOT/wtx.toml" _wtx_install_commit_toml` so dry-run skips both the temp build and the `mv` (AD-4 / AD-5).
  - [x] Append ledger `config` = `done` (real) — in dry-run the helper prints the `[dry-run] would write:` line; do not append a fake `done`.
  - [x] Emit every section present in `wtx.example.toml` and ONLY those keys: `[forge]` (type, org, optional base_url), `[jira.projects]` (accumulated pairs or comment-only), `[projects]` (list), `[detection]` (markers or comment), `[worktree]` (registry_path, builtin_path defaults, optional setup_hook), `[defaults]` (base_branch, branch_prefix). No new keys (AD-9).
- [x] Wire the step sequence into `_wtx_install_run` (AC: 10)
  - [x] After `_wtx_install_preflight`, call: banner → Step 2 → Steps 3–8 → TOML write. Leave explicit no-op placeholder calls/comments for the idempotency gate (Story 1.5), Step 9 (1.3), Step 10 (1.4), Step 11 (1.7) so the ordering is visible but unimplemented.
  - [x] Do NOT implement the idempotency gate, hooks, extras, full dry-run threading, or the summary render here.
- [x] Add or extend focused tests (AC: 1–11)
  - [x] Extend `tests/test-wtx-install.sh`: add a non-interactive test that drives `_wtx_install_emit_toml` (or a generated-TOML fixture path) and asserts via `wtx_config_get` that user values round-trip and no placeholder (`acme`, `web`/`mobile`/`backend`, `settings.gradle`) survives.
  - [x] Add a test asserting zero Jira pairs yields a `[jira.projects]` section with only a comment (grep the emitted output).
  - [x] Add a test for Step 8 selection mapping: discovered plugin filename → `setup_hook = "plugins/<filename>"`.
  - [x] Assert `worktree-install.sh` contains no interactive `read` outside `tui_*` fallbacks (AD-10 guard).
  - [x] Run the full validation set in Testing Standards below.

## Dev Notes

### Scope Boundary

- This story implements **Step 1 (banner) through the atomic `wtx.toml` write only** — Steps 2–8 prompts and the templated TOML output. It CONSUMES the Story 1.1 primitives; it must not redefine `_wtx_toml_escape`, `_wtx_csv_to_toml_array`, `wtx_install_discover_plugins`, `wtx_install_write_or_dryrun`, the temp/trap, or the ledger arrays. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Architecture-Guardrails]
- **Out of scope (other stories):** idempotency skip/overwrite/merge gate = Story 1.5 (AD-13/AD-6); Step 9 Claude Code hooks = Story 1.3; Step 10a/10b extras = Story 1.4; full `--dry-run` end-to-end threading + diff verification = Story 1.6; Step 11 completion summary render = Story 1.7. Leave these as visible placeholders only. [Source: _bmad-output/planning-artifacts/epics.md#FR-Coverage-Map]
- `install.sh`, `lib/wtx-config.sh`, and `lib/worktree-tui.sh` are UNCHANGED by this feature — source/reuse them, never edit them. [Source: _bmad-output/planning-artifacts/epics.md#NonFunctional-Requirements] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Structural-Seed]

### Current State of `scripts/worktree-install.sh` (the file you modify)

Story 1.1 left a working skeleton. Read it fully before editing. Today it:
- Resolves `WTX_ROOT` (symlink-walk + `lib/` probe) and exports it (lines 6–25).
- `_wtx_install_resolve_workspace_root` uses `git rev-parse --path-format=absolute --git-common-dir` with `--show-toplevel`/`pwd` fallback (lines 27–41) — **do not** change this to `--show-toplevel`. [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- `_wtx_install_source_libs` sources `wtx-install.sh`, `wtx-config.sh`, `worktree-tui.sh` with the inline `tui_*` stub-fallback block (lines 43–66). Your new prompt code calls these `tui_*` functions; the stubs already cover the no-lib case.
- `_wtx_install_parse_args` parses only `--dry-run` and exports `WTX_INSTALL_DRY_RUN` (lines 68–84).
- `_wtx_install_preflight` runs: dry-run parse → git check → gum detect (sets/export `GUM_AVAILABLE`) → resolve workspace → source libs → `mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX"` into `_WTX_INSTALL_TMP` + `trap 'rm -f "$_WTX_INSTALL_TMP"' EXIT` → init `_WTX_LEDGER_KEYS=()` / `_WTX_LEDGER_VALS=()` (lines 86–110).
- `_wtx_install_run` currently just calls preflight and returns 0 (lines 112–115). **This is the integration point** — extend it to call your new step functions in order.
- **Preserve:** the Step 0 ordering, the trap, the workspace resolution, and the `WTX_INSTALL_*` / `_wtx_install_*` / `_WTX_INSTALL_*` naming convention. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Consistency-Conventions]

### `lib/wtx-install.sh` primitives you call (do not modify)

- `wtx_install_write_or_dryrun "<action-label>" cmd args…` — in real mode runs `cmd` and returns its exit code; in dry-run prints `[dry-run] <action-label>` and returns 0 without running. This is the ONLY place a write decision is made. Route the `install.sh --prefix` subprocess AND the TOML `mv` through it. [Source: lib/wtx-install.sh] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
- `_wtx_toml_escape "$value"` — backslash-then-quote escape; wrap each scalar you embed between `"…"`. [Source: lib/wtx-install.sh]
- `_wtx_csv_to_toml_array "$csv"` — trims items, drops empties, glob-safe; returns a `["a", "b"]` literal (empty input → `[]`). Use for `projects.list` and `detection.markers`. [Source: lib/wtx-install.sh]
- `wtx_install_discover_plugins` — emits `filename<TAB>description` lines (description defaults to filename stem). It does NOT prepend `None`/`Custom path…` — the wizard UI owns that. [Source: lib/wtx-install.sh] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-8--Plugin-discovery]

### TUI primitive signatures (from `lib/worktree-tui.sh`, unchanged)

- `tui_choose [--selected "value"] "prompt" opt1 opt2 …` → echoes the chosen option to stdout. gum + `select`-based bash fallback, both reading `/dev/tty`. [Source: lib/worktree-tui.sh#tui_choose]
- `tui_input "prompt" ["default"] ["placeholder"]` → echoes entered value (or default) to stdout. [Source: lib/worktree-tui.sh#tui_input]
- `tui_confirm "prompt?" [default_yes]` → returns exit status (0 = yes). Pass a non-empty 2nd arg for a `[Y/n]` default-yes prompt (e.g. "Add another?" should default NO; leave 2nd arg empty). [Source: lib/worktree-tui.sh#tui_confirm]
- `tui_style_box "line1" "line2" …` → rounded gum box, or a bash-drawn border, or plain when stubbed. Use for the banner. [Source: lib/worktree-tui.sh#tui_style_box]
- **AD-10:** every prompt goes through a `tui_*` function. `read` may appear ONLY inside `tui_*` fallback bodies in `worktree-tui.sh` — never directly in `worktree-install.sh`. Capture values with command substitution: `forge_type="$(tui_choose …)"`. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]

### `install.sh` delegation interface (subprocess only — never source it)

`install.sh [--prefix PATH] [--hooks] [--gradle] [--force] [--dry-run]`. For Step 2 call `bash "$WTX_ROOT/install.sh" --prefix "$WTX_INSTALL_PREFIX"` (append `--dry-run` when `WTX_INSTALL_DRY_RUN=1`). Sourcing is unsafe — its top-level arg parsing has side effects. [Source: install.sh#usage] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]

### TOML output contract (AD-9 — no schema extension)

Emit exactly the sections/keys present in `wtx.example.toml`; introduce no new keys. The generated file must contain NONE of the placeholder values. [Source: wtx.example.toml] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-9--No-config-schema-extension]

| Section | Key(s) | Source | Empty/skip behavior |
|---|---|---|---|
| `[forge]` | `type`, `org`, optional `base_url` | Step 3 | `base_url` omitted (or left commented) when not self-hosted |
| `[jira.projects]` | `repo = "KEY"` pairs | Step 7 | zero pairs → section header + comment only (AC 9) |
| `[projects]` | `list` | Step 4 | empty input → `list = []` via `_wtx_csv_to_toml_array ""` |
| `[detection]` | `markers` | Step 5 | `.git` default → no `markers` key, comment only |
| `[worktree]` | `registry_path`, `builtin_path`, optional `setup_hook` | defaults + Step 8 | None → `setup_hook` omitted/commented |
| `[defaults]` | `base_branch`, `branch_prefix` | Step 6 | always written (defaults `main` / `feature`) |

- `registry_path` (`.claude/worktree-registry.md`) and `builtin_path` (`.claude/worktrees`) are not prompted in 1.2 — write the `wtx.example.toml` defaults verbatim. [Source: wtx.example.toml#worktree]
- **Note:** `wtx.example.toml` ships `base_branch = "develop"`, but FR9/UX-DR7 require the wizard's prompt DEFAULT to be `main`. Use `main` as the `tui_input` default; the written value reflects user input. [Source: _bmad-output/planning-artifacts/epics.md#Functional-Requirements] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-6--Branch-defaults]
- Detection-marker presets: Gradle → `["settings.gradle", "settings.gradle.kts"]`, Rust → `["Cargo.toml"]`, Node.js → `["package.json"]`, Custom → CSV input. These exact strings are the placeholder set you must NOT emit unless the user actually selected that preset. [Source: wtx.example.toml#detection] [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-5--Detection-markers]

### Bash 3.2 / portability guardrails (non-negotiable)

- `set -u` only — never `set -e`. Check return codes explicitly (especially the `install.sh` subprocess and the `mv`). [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash]
- No `declare -A`, `mapfile`/`readarray`, `${var^^}`/`${var,,}`, `readlink -f`, or process substitution into arrays. The Jira pairs and the plugin list must use **parallel indexed arrays** (the same shape as `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS`). [Source: _bmad-output/project-context.md#Language-Specific-Rules-Bash] [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]
- Quote every path expansion — this repo lives under a path with spaces. Especially `"$WORKSPACE_ROOT"`, `"$WTX_ROOT"`, `"$_WTX_INSTALL_TMP"`, `"$WTX_INSTALL_PREFIX"`. [Source: _bmad-output/project-context.md#Critical-Dont-Miss-Rules]
- No `eval`, no ad-hoc TOML parsing for reads — round-trip validation uses `wtx_config_get` / `wtx_config_get_list`. [Source: _bmad-output/project-context.md#Framework-Specific-Rules-wtx-architecture]
- Errors to stderr with the `wtx install:` prefix; meaningful exit codes. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Consistency-Conventions]

### Reuse — do NOT reinvent

- Don't hand-roll TOML escaping, CSV→array conversion, plugin scanning, the dry-run check, prompts, or box-drawing — all exist (`lib/wtx-install.sh`, `lib/worktree-tui.sh`). Reinventing any of these is a review-blocking regression. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Architecture-Guardrails]
- Don't add a config key for things `wtx.example.toml` already documents; don't prompt for `registry_path`/`builtin_path` (write defaults).

### Previous Story Intelligence (Story 1.1)

- 1.1 was implemented TDD (red → green) with senior-review auto-fixes. Three fixes are relevant guardrails for you: (1) Step 0 ordering must stay dry-run → git → gum — don't reorder when you insert steps after preflight; (2) direct-invocation `WTX_ROOT` fallback resolves the real script dir and uses it when it contains `lib/` — leave intact; (3) `_wtx_csv_to_toml_array` preserves the caller's `noglob` state — rely on it, don't wrap your calls in extra `set -f`/`set +f`. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Senior-Developer-Review-AI]
- Test file `tests/test-wtx-install.sh` already exists with `assert_eq`/`assert_contains`/`assert_ok` helpers and cases for the lib primitives + preflight. Extend it in the same style; do NOT add bats/shunit2/CI. [Source: tests/test-wtx-install.sh]
- Untracked `_bmad-output/story-automator/` files are unrelated — don't touch them. [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Recent-Repository-Context]

### Testing Notes

- The wizard is interactive; follow the existing pattern — test the **pure functions** (`_wtx_install_emit_toml`, plugin-selection mapping) directly by sourcing, not by driving the full TUI. Set `WTX_ROOT`/`WORKSPACE_ROOT`/`WTX_CONFIG` per case; for round-trip reads `unset _WTX_CONFIG_LOADED` before re-sourcing `lib/wtx-config.sh`. [Source: _bmad-output/project-context.md#Testing-Rules]
- A new feature that reads config must ship a fixture-driven `wtx_config_get` test including the default-fallback path. [Source: _bmad-output/project-context.md#Testing-Rules]
- Interactive end-to-end flow has no harness — same deferral as existing scripts. Cover the deterministic surfaces. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Deferred]

### Testing Standards

Required after this story:
- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- `bash tests/test-wtx-config.sh`
- `bash tests/test-wtx-dispatcher.sh`
- `bash tests/test-wtx-install.sh`
- `bash tests/test-install.sh`
- `bash tests/test-worktree-registry.sh`

## Project Structure Notes

- File expected to change: `scripts/worktree-install.sh` (add step functions + wire `_wtx_install_run`).
- File expected to change: `tests/test-wtx-install.sh` (add TOML-emit / round-trip / Jira-empty / plugin-mapping cases).
- Files that MUST remain behaviorally unchanged: `lib/wtx-install.sh`, `lib/wtx-config.sh`, `lib/worktree-tui.sh`, `install.sh`, `bin/wtx`.
- Naming: `_wtx_install_*` private wizard helpers, `WTX_INSTALL_*` exported session vars, `_WTX_INSTALL_*` / `_WTX_*` script-local state, kebab-case files. [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#Consistency-Conventions]
- Generated artifact (`$WORKSPACE_ROOT/wtx.toml`) is produced at runtime, not committed by this story.

## References

- [Source: _bmad-output/planning-artifacts/epics.md#Story-1.2-Reference-templating-engine--config-prompts-plugin-discovery--TOML-write]
- [Source: _bmad-output/planning-artifacts/epics.md#FR-Coverage-Map]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-3--Delegation-to-installsh]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-4--Atomic-TOML-write]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-5--Dry-run-flag-propagation]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-7--Summary-ledger]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-8--Plugin-discovery]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-9--No-config-schema-extension]
- [Source: _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md#AD-10--TUI-consistency]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-1--Welcome-banner]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-2--Binary-install]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-3--Forge-configuration]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-5--Detection-markers]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-7--Jira-project-key-mapping]
- [Source: _bmad-output/specs/spec-wtx-install/ux-flow.md#Step-8--Setup-hook]
- [Source: _bmad-output/implementation-artifacts/1-1-wizard-shell-shared-write-primitives-preflight.md#Senior-Developer-Review-AI]
- [Source: lib/wtx-install.sh]
- [Source: lib/worktree-tui.sh]
- [Source: scripts/worktree-install.sh]
- [Source: wtx.example.toml]
- [Source: install.sh#usage]
- [Source: _bmad-output/project-context.md#Critical-Implementation-Rules]

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- Tests 7 & 8 (Story 1.1 preflight assertions) needed relaxation: wizard now runs interactive steps after preflight, so stdout and stderr changed shape. Updated to `assert_contains` and absence checks.
- "jira empty: no fabricated keys" test pattern `*'= "'*` also matched comment lines (`# repo = "PROJKEY"`). Fixed awk to filter only non-commented lines (`/^[^#]/`).
- "setup_hook absent when empty" pattern `*'setup_hook = "'*` matched the commented-out fallback line. Fixed to grep only uncommented lines (`^setup_hook = "`).
- Step 8 originally used `while IFS= read -r line` to parse plugin output — flagged by AD-10 test. Refactored to capture output with `$(...)` then split via `IFS=$'\n'` array expansion.

### Completion Notes List

- Ultimate context engine analysis completed - comprehensive developer guide created.
- Implemented `_wtx_install_step_banner` using `tui_style_box` (AC 1).
- Implemented `_wtx_install_step2_binary`: symlink-walk PATH detection, ledger append, `install.sh` delegation with `--dry-run` passthrough (AC 2, 3).
- Implemented `_wtx_install_steps3_7_config`: forge type/org/base_url, project dirs, detection marker presets, branch defaults, iterative Jira pair loop using parallel indexed arrays (AC 4, 5, 9).
- Implemented `_wtx_install_step8_hook`: plugin discovery via `wtx_install_discover_plugins`, display list with None/Custom prepended, label-to-filename resolution (AC 6). No bare `read` — uses IFS array split.
- Implemented `_wtx_install_emit_toml` and `_wtx_install_commit_toml`: full TOML output exactly matching `wtx.example.toml` schema, all scalars via `_wtx_toml_escape`, arrays via `_wtx_csv_to_toml_array`, atomic write through `wtx_install_write_or_dryrun` (AC 7, 8, 9).
- Wired `_wtx_install_run` with placeholder comments for Stories 1.3–1.7 (AC 10).
- Extended `tests/test-wtx-install.sh` with Cases 12–25: TOML round-trip, no-placeholder, jira-empty section, setup_hook absent, plugin map, AD-10 guard, QA gap coverage, and failure propagation guards. 85/85 pass.
- All 6 suites pass: syntax, test-wtx-config, test-wtx-dispatcher, test-wtx-install, test-install, test-worktree-registry.

### Senior Developer Review (AI)

Reviewer: Codex on 2026-06-27

Outcome: Approved after auto-fixes. No critical issues remain.

Inputs loaded:
- Story file: `_bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md`
- Story context: no separate story-context file found; reviewed story, SPEC, UX flow, epics, project context, and architecture spine.
- Epic tech spec: no standalone epic tech spec found; reviewed `_bmad-output/specs/spec-wtx-install/SPEC.md`, `_bmad-output/specs/spec-wtx-install/ux-flow.md`, `_bmad-output/planning-artifacts/epics.md`, and the install architecture spine.
- Tech stack: pure Bash targeting bash 3.2, shell-only tests.
- External doc fallback: GNU Bash Reference Manual, Arrays section (`https://www.gnu.org/software/bash/manual/bash.html#Arrays`).

Findings fixed:
- HIGH: `_wtx_install_step2_binary` recorded `symlink=failed` but always returned 0 after a failed `install.sh` subprocess, so `_wtx_install_run` could continue and exit successfully despite AC 3/NFR10 failure. Fixed by returning the delegated command rc and propagating it from `_wtx_install_run`.
- HIGH: TOML write failures from `wtx_install_write_or_dryrun ... _wtx_install_commit_toml` were ignored, leaving no failed ledger entry and returning success despite AC 7/NFR10. Fixed by recording `config=failed` and returning the TOML write rc.
- MEDIUM: `tests/test-wtx-install.sh` stubbed `wtx_install_write_or_dryrun` but attempted to restore it by sourcing `lib/wtx-install.sh`; the idempotent guard prevented restoration, which could mask later test failures. Fixed by unsetting the stub and `_WTX_INSTALL_LIB_LOADED` before re-sourcing the lib.

Validation:
- `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` passed.
- `bash tests/test-wtx-config.sh` passed: 26/26.
- `bash tests/test-wtx-dispatcher.sh` passed: 22/22.
- `bash tests/test-wtx-install.sh` passed: 85/85.
- `bash tests/test-install.sh` passed: 25/25.
- `bash tests/test-worktree-registry.sh` passed: 19/19.

### File List

- `scripts/worktree-install.sh` — added step functions, wired `_wtx_install_run`, and propagated critical failure return codes
- `tests/test-wtx-install.sh` — extended with Cases 12–25 (TOML emit, Jira empty, plugin map, AD-10 guard, QA gap coverage, failure propagation)
- `_bmad-output/implementation-artifacts/1-2-reference-templating-engine-config-prompts-plugin-discovery-toml-write.md` — story file (status, tasks, file list, dev agent record)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — updated to `done`

### Change Log

- 2026-06-27: Story 1.2 implemented — added Steps 1–8 config prompts, atomic TOML write, plugin discovery, and focused tests. All ACs satisfied, 53/53 tests pass.
- 2026-06-27: Senior review auto-fixes applied — propagated symlink/TOML failure return codes, restored the test write-helper stub correctly, added regression coverage, and marked story done.
