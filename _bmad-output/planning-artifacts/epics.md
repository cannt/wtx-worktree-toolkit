---
stepsCompleted: [step-01, step-02, step-03, step-04]
inputDocuments:
  - _bmad-output/specs/spec-wtx-install/SPEC.md
  - _bmad-output/specs/spec-wtx-install/ux-flow.md
  - _bmad-output/planning-artifacts/architecture/architecture-wtx-install-2026-06-26/ARCHITECTURE-SPINE.md
---

# wtx - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for wtx, decomposing the requirements from the SPEC (CAP-1..CAP-7), UX Flow, and Architecture (AD-1..AD-13) into implementable stories for the interactive installer feature.

## Requirements Inventory

### Functional Requirements

FR1: `wtx install` must be invocable in any git workspace and guide the developer through complete setup — PATH symlink, config generation, hooks — via a staged TUI, completing without errors. (CAP-1)
FR2: The wizard must use `gum` when available and degrade gracefully to pure-bash `read` prompts, completing end-to-end in both modes. (CAP-1)
FR3: Step 0 preflight must execute in exact order before any prompt or write: (1) parse `--dry-run` → set `WTX_INSTALL_DRY_RUN`; (2) verify git repo or exit 1; (3) detect `gum` → set `GUM_AVAILABLE`. (AD-12)
FR4: The wizard must display a welcome banner (Step 1) showing workspace path and WTX root, with a Ctrl-C abort notice. (CAP-1, ux-flow Step 1)
FR5: Step 2 must check if `wtx` is already on PATH pointing at this install; if so, skip the symlink step; otherwise prompt for install prefix and delegate to `install.sh --prefix <value>` as a subprocess. (CAP-1, AD-3, ux-flow Step 2)
FR6: Step 3 must collect forge type (select from github/gitlab/bitbucket), forge org slug, and optionally a self-hosted base URL. (CAP-2, ux-flow Step 3)
FR7: Step 4 must collect known project directories as a comma-separated optional input. (CAP-2, ux-flow Step 4)
FR8: Step 5 must offer detection marker presets (`.git`, Gradle, Rust, Node.js) plus a Custom option with free-text input. (CAP-2, ux-flow Step 5)
FR9: Step 6 must collect branch defaults: base branch (default `main`) and branch prefix (default `feature`). (CAP-2, ux-flow Step 6)
FR10: Step 7 must collect Jira project key mappings in an iterative loop; the entire step is optional and skippable with empty input. (CAP-2, ux-flow Step 7)
FR11: Step 8 must list setup hooks by scanning `$WTX_ROOT/plugins/*.sh` for `# wtx-plugin-desc:` comment lines; wizard prepends `None` and `Custom path…`; user selects one. (CAP-2, AD-8, ux-flow Step 8)
FR12: The generated `wtx.toml` must contain no placeholder values from `wtx.example.toml` (e.g. `org = "acme"`); all fields must reflect actual user input. (CAP-2, AD-9)
FR13: `wtx.toml` must be written atomically: written to a temp file first, moved into place with `mv`; a `trap` registered at wizard startup cleans up the temp on exit. (CAP-2, AD-4)
FR14: Step 9 must describe the three hook files and ask for confirmation before delegating to `install.sh --hooks`; if declined, no hook files are written or modified. (CAP-3, AD-3, ux-flow Step 9)
FR15: Step 10a must offer the Gradle worktree-cache init script extra via `install.sh --gradle`; Step 10b must offer the PATH hint extra; each installed only on explicit confirmation; declined extras leave the filesystem unchanged. (CAP-4, AD-3, ux-flow Step 10)
FR16: The PATH hint extra (Step 10b) must be suppressed when the install prefix bin directory is already on `$PATH`; it must be recorded in the ledger as `skipped (already on PATH)`. (CAP-4, AD-11)
FR17: When `wtx.toml` already exists, the wizard must offer skip / overwrite / merge before touching any files; this check occurs after Step 0 and before Step 1. (CAP-5, AD-13)
FR18: On the merge path, existing `wtx.toml` values must be loaded via `wtx_config_get` (after resetting `_WTX_CONFIG_LOADED`) and supplied as defaults to each `tui_input` call. (CAP-5, AD-6)
FR19: `wtx install --dry-run` must print every action prefixed with `[dry-run]` (e.g. `[dry-run] would write:`, `[dry-run] would create:`) without modifying the filesystem; all prompts still appear. (CAP-6, AD-5)
FR20: All write operations must be gated through a single `wtx_install_write_or_dryrun <action-label> <cmd...>` helper in `lib/wtx-install.sh`; no other code in the wizard checks `--dry-run` directly. (CAP-6, AD-5)
FR21: Step 11 must display a styled completion summary rendering the ledger as `[✓]` / `[-]` / `[!]` rows plus the exact `wtx doctor` command; in dry-run mode a header note clarifies no files were written. (CAP-7, AD-7)
FR22: The summary ledger must be implemented as two parallel indexed arrays (`_WTX_LEDGER_KEYS`, `_WTX_LEDGER_VALS`) — bash 3.2 safe, no `declare -A` — each wizard step appends one entry. (CAP-7, AD-7)
FR23: `wtx install [--dry-run]` must be routed through `bin/wtx` case statement as `_wtx_exec_script "worktree-install.sh" "$@"` — same pattern as `start`/`done`/`status`. No alternative entry point. (AD-1)
FR24: `_wtx_toml_escape` and `_wtx_csv_to_toml_array` must be defined only in `lib/wtx-install.sh` (guarded by `_WTX_INSTALL_LIB_LOADED`); both `bin/wtx` and `worktree-install.sh` source this lib; no other file defines these functions. (AD-2)
FR25: Every interactive prompt in `worktree-install.sh` must call a `tui_*` function from `lib/worktree-tui.sh`; no bare `read` calls in wizard prompt code. (AD-10)

### NonFunctional Requirements

NFR1: All new code must be bash 3.2 compatible — no `readlink -f`, no `declare -A`, no `mapfile`/`readarray`, no `${var^^}`/`${var,,}`, no process substitution to array.
NFR2: Scripts use `set -u` only, never `set -e`; optional steps tolerate failure by graceful degradation, not exception handling.
NFR3: No hardcoded org, project name, Jira key, forge type, or branch literal in new code; every value comes from user input or the config layer at runtime.
NFR4: Every interactive prompt has a working pure-bash `read` fallback; the wizard completes end-to-end without `gum`.
NFR5: No `eval` of raw user input anywhere in new code.
NFR6: All file paths resolved relative to `WTX_ROOT` or `WORKSPACE_ROOT`; no absolute path assumptions beyond those two exports.
NFR7: Config reads use `wtx_config_get` / `wtx_config_get_list` only; no ad-hoc TOML parsing.
NFR8: `gum`, `jq`, `claude`, and `timeout` absence at any step must not abort the flow; the wizard degrades gracefully.
NFR9: Every path expansion must be quoted (the repo lives in an iCloud Drive path with spaces).
NFR10: Error messages go to stderr (`>&2`) with a `wtx install:` prefix; exit codes are meaningful.
NFR11: `lib/worktree-tui.sh`, `lib/wtx-config.sh`, and `install.sh` are unchanged by this feature; the wizard borrows them without modifying them.
NFR12: After a complete `wtx install`, running `wtx doctor` exits 0 with all required dependencies and install files present.

### Additional Requirements

- **AD-1 (Dispatcher routing):** `bin/wtx` case statement gets an `install)` arm calling `_wtx_exec_script "worktree-install.sh" "$@"`. The `_wtx_usage` function and COMMANDS list are updated to include `install`. No new standalone entry point is created.
- **AD-2 (File layout):** New files: `scripts/worktree-install.sh` (wizard orchestration) and `lib/wtx-install.sh` (TOML helpers + plugin discovery). Existing files with minimal changes: `bin/wtx` (moves helper functions to lib, adds install case). `lib/wtx-config.sh`, `lib/worktree-tui.sh`, and `install.sh` are unchanged.
- **AD-3 (Delegation to install.sh):** The wizard always invokes `install.sh` as a bash subprocess (`bash "$WTX_ROOT/install.sh" ...`), never sources it. Exit code is checked and the result is recorded in the ledger. In dry-run mode `--dry-run` is appended to every subprocess call.
- **AD-4 (Atomic TOML write):** Write to `mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX"`, then `mv` into place. Register `trap 'rm -f "$_WTX_INSTALL_TMP"' EXIT` at wizard startup. In dry-run mode: print `[dry-run] would write:` line only; skip write and mv.
- **AD-5 (Dry-run flag propagation):** `WTX_INSTALL_DRY_RUN` (0 or 1) set at preflight; all install.sh subprocess calls and write ops go through `wtx_install_write_or_dryrun`. No scattered `--dry-run` checks.
- **AD-6 (Merge pre-fill):** On merge path: `unset _WTX_CONFIG_LOADED; WTX_CONFIG="$WORKSPACE_ROOT/wtx.toml"; source lib/wtx-config.sh`. Each `tui_input` call receives existing config value as its default. Existing file replaced only when the new atomic write succeeds.
- **AD-7 (Summary ledger):** Parallel indexed arrays `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` (bash 3.2, no `declare -A`). Each step appends one entry. Step 11 iterates to render the `[✓]/[-]/[!]` table; no step prints its own status.
- **AD-8 (Plugin discovery):** `wtx_install_discover_plugins()` in `lib/wtx-install.sh` globs `$WTX_ROOT/plugins/*.sh`, reads first `# wtx-plugin-desc:` line per file via `grep -m1`, emits `filename\tdescription` newline-separated pairs. Wizard prepends `None` and `Custom path…` before passing to `tui_choose`.
- **AD-9 (No schema extension):** Generated `wtx.toml` contains only keys present in current `wtx.example.toml`. No new TOML keys.
- **AD-10 (TUI consistency):** All prompts in `worktree-install.sh` call `tui_*` functions. `lib/worktree-tui.sh` is sourced with inline stub fallback block.
- **AD-11 (PATH hint gate):** `case ":$PATH:" in *":$WTX_INSTALL_PREFIX/bin:"*` — PATH hint shown only when this does NOT match.
- **AD-12 (Preflight sequence):** Fixed order in Step 0: (1) parse `--dry-run`; (2) git repo check; (3) gum detection. No reordering.
- **AD-13 (Idempotency gate placement):** `wtx.toml` existence check and skip/overwrite/merge prompt immediately after Step 0, before Step 1 (banner). On `skip`: populate ledger from existing file and jump to Step 9.
- **No starter template:** The wizard generates `wtx.toml` from user inputs, not from a scaffold file. `wtx.example.toml` is the schema reference, not a copy-paste base.

### UX Design Requirements

UX-DR1: Step 0 — silent preflight: parse flags, check git repo (exit 1 with clear message if not in a git tree), detect `gum`; if no gum, print: `note: gum not found — using plain prompts (install with: brew install gum)`.
UX-DR2: Step 1 — gum styled box: workspace path, WTX root, Ctrl-C abort notice; fallback: same text via plain `echo`/`printf` without border.
UX-DR3: Step 2 — if already on PATH and pointing to this install: show `[✓] wtx already on PATH` info box and skip; if not: `tui_input` for install prefix (default `~/.local`), then delegate to `install.sh --prefix`; fallback: plain prompt with bracket-default.
UX-DR4: Step 3 — `tui_choose` for forge type (github/gitlab/bitbucket), `tui_input` for org slug, yes/no confirm for self-hosted then `tui_input` for base URL if confirmed; fallback: `Forge type [bitbucket|github|gitlab] (github):` then plain reads.
UX-DR5: Step 4 — single `tui_input` for comma-separated project dirs, optional, with skip hint; fallback: plain `read`.
UX-DR6: Step 5 — `tui_choose` from preset list (`.git`, Gradle, Rust, Node.js, Custom…); if Custom: `tui_input` for comma-separated markers; fallback: numbered menu via `read`.
UX-DR7: Step 6 — two `tui_input` calls: base branch (default `main`), branch prefix (default `feature`); fallback: plain `read` prompts.
UX-DR8: Step 7 — iterative loop: `tui_input` for repo name (blank to skip), `tui_input` for Jira key; `Add another? [y/N]` confirm each iteration; gum table of accumulated pairs when available; fallback: plain text prompts.
UX-DR9: Step 8 — `tui_choose` from discovered plugin list (prepended with `None` and `Custom path…`); if Custom: `tui_input` for relative path; fallback: numbered menu.
UX-DR10: Step 9 — gum styled box describing the three hooks + `Install Claude Code hooks? [Y/n]` confirm; if declined: no files written; fallback: plain yes/no `read`.
UX-DR11: Step 10a — `tui_confirm` with one-line Gradle description; delegates to `install.sh --gradle` if confirmed; fallback: plain yes/no.
UX-DR12: Step 10b — shown only when install prefix bin NOT on `$PATH`; if confirmed: print `export PATH="$HOME/.local/bin:$PATH"` guidance; fallback: plain yes/no.
UX-DR13: Step 11 — styled box with `[✓]`/`[-]`/`[!]` ledger table and `wtx doctor` command; in dry-run mode: `[dry-run] No files were written. Remove --dry-run to apply.` header; fallback: plain text same structure.
UX-DR14: Dry-run visual — every write-action step prints `[dry-run] would write: <path>`, `[dry-run] would create: <link>`, or `[dry-run] would copy: <src> -> <dst>`; all prompts still appear and accept input.
UX-DR15: Wizard step ordering matches the UX rationale table: Step 0 → idempotency gate → Step 1 → Step 2 → Steps 3-8 (core config) → atomic TOML write → Step 9 → Step 10a → Step 10b → Step 11.

### FR Coverage Map

```
FR1:  Epic 1 — CAP-1 wizard invocable end-to-end without errors (Story 1.2)
FR2:  Epic 1 — CAP-1 gum/bash-fallback, completes in both modes (Story 1.2)
FR3:  Epic 1 — AD-12 preflight exact sequence before any prompt or write (Story 1.1)
FR4:  Epic 1 — Step 1 welcome banner with paths + Ctrl-C notice (Story 1.2)
FR5:  Epic 1 — Step 2 binary install: PATH check + install.sh --prefix delegation (Story 1.2)
FR6:  Epic 1 — Step 3 forge type, org, optional base URL collection (Story 1.2)
FR7:  Epic 1 — Step 4 project directories comma-separated input (Story 1.2)
FR8:  Epic 1 — Step 5 detection markers: presets + Custom free-text (Story 1.2)
FR9:  Epic 1 — Step 6 branch defaults: base branch + prefix (Story 1.2)
FR10: Epic 1 — Step 7 Jira key iterative loop, optional, skippable (Story 1.2)
FR11: Epic 1 — Step 8 plugin discovery + hook selection via AD-8 (Story 1.2)
FR12: Epic 1 — CAP-2 no placeholder value surviving in written wtx.toml (Story 1.2)
FR13: Epic 1 — AD-4 atomic write: mktemp + mv, trap EXIT cleanup (Story 1.1 primitive, called in 1.2)
FR14: Epic 1 — CAP-3 Step 9 hooks: show descriptions, confirm, install.sh --hooks (Story 1.3)
FR15: Epic 1 — CAP-4 Step 10 extras: Gradle + PATH hint, each on explicit confirm (Story 1.4)
FR16: Epic 1 — AD-11 PATH hint gate: suppressed when prefix bin already on $PATH (Story 1.4)
FR17: Epic 1 — CAP-5 idempotency: skip/overwrite/merge gate after preflight (Story 1.5)
FR18: Epic 1 — AD-6 merge pre-fill: existing values loaded via wtx_config_get as tui_input defaults (Story 1.5)
FR19: Epic 1 — CAP-6 --dry-run: [dry-run] output, filesystem unchanged (Story 1.6)
FR20: Epic 1 — AD-5 wtx_install_write_or_dryrun single chokepoint for all writes (Story 1.1 primitive)
FR21: Epic 1 — CAP-7 Step 11 ledger-driven [✓]/[-]/[!] summary + wtx doctor (Story 1.7)
FR22: Epic 1 — AD-7 parallel indexed arrays for ledger, bash 3.2 safe (Story 1.7)
FR23: Epic 1 — AD-1 bin/wtx case statement routes install via _wtx_exec_script (Story 1.1)
FR24: Epic 1 — AD-2 lib/wtx-install.sh single home for all primitives (Story 1.1)
FR25: Epic 1 — AD-10 all wizard prompts via tui_* functions, no bare read (Story 1.2)
```

## Epic List

- **Epic 1: Interactive Installer** — End-to-end `wtx install` wizard covering wizard shell, config templating, hooks, extras, idempotency, dry-run, and completion summary.
- **Story S.1 (Standalone): Install & set up graphify** — Separate tooling concern; install graphify from GitHub and wire it into the wtx project.

---

## Epic 1: Interactive Installer

Enable any developer to run `wtx install` in a new git workspace and arrive — without consulting documentation or manually editing files — at a valid PATH symlink, a fully-populated `wtx.toml` (no example placeholder surviving), and optionally installed Claude Code hooks, verified by `wtx doctor`.

---

### Story 1.1: Wizard shell, shared write primitives & preflight

As a wtx developer,
I want `wtx install` routed through the standard dispatcher, the shared write/escape/dry-run primitive helpers defined in `lib/wtx-install.sh`, and the wizard skeleton in place with correct path resolution and preflight sequence,
So that all subsequent installer stories can depend on a stable, tested foundation and no story other than 1.1 needs to implement or re-implement these cross-cutting primitives.

**Acceptance Criteria:**

**Given** `bin/wtx` is invoked as `wtx install` or `wtx install --dry-run`
**When** the dispatcher runs
**Then** it calls `_wtx_exec_script "worktree-install.sh" "$@"` (AD-1); no alternative entry point exists; `_wtx_usage` / COMMANDS list include `install`

**Given** the new file `lib/wtx-install.sh` is sourced
**When** it is sourced more than once in the same shell
**Then** the `_WTX_INSTALL_LIB_LOADED` guard prevents re-execution; `_wtx_toml_escape`, `_wtx_csv_to_toml_array`, `wtx_install_discover_plugins`, and `wtx_install_write_or_dryrun` are defined exactly once (AD-2)

**Given** `_wtx_toml_escape` and `_wtx_csv_to_toml_array` previously lived inline in `bin/wtx`
**When** this story is complete
**Then** both functions are moved to `lib/wtx-install.sh`; `bin/wtx` sources the lib before calling `_wtx_init`; existing `wtx init` behavior is unchanged (AD-2)

**Given** `wtx_install_write_or_dryrun <action-label> <cmd...>` is called with `WTX_INSTALL_DRY_RUN=0`
**When** it executes
**Then** it runs `<cmd...>` and returns its exit code; no `[dry-run]` output is produced (AD-5)

**Given** `wtx_install_write_or_dryrun <action-label> <cmd...>` is called with `WTX_INSTALL_DRY_RUN=1`
**When** it executes
**Then** it prints a `[dry-run] <action-label>` line and returns 0 without executing `<cmd...>`; the command is never invoked (AD-5)

**Given** `scripts/worktree-install.sh` is invoked (directly or via dispatcher)
**When** it starts
**Then** it resolves `WTX_ROOT` and `WORKSPACE_ROOT` using the same `--git-common-dir` / `BASH_SOURCE[0]`-walk pattern as other `scripts/worktree-*.sh` files (project-context.md invariant)

**Given** Step 0 preflight executes
**When** the wizard starts
**Then** the order is exactly: (1) parse `--dry-run` arg → export `WTX_INSTALL_DRY_RUN=1` or `0`; (2) `git rev-parse --git-dir` — exit 1 with `wtx install: not in a git repository` if not in a repo; (3) `command -v gum` → set `GUM_AVAILABLE` (AD-12)

**Given** `gum` is absent when the wizard starts
**When** Step 0 completes
**Then** a single notice line is printed to stdout: `note: gum not found — using plain prompts (install with: brew install gum)` (UX-DR1)

**Given** the wizard registers its cleanup trap at startup
**When** the trap is in place
**Then** `trap 'rm -f "$_WTX_INSTALL_TMP"' EXIT` is registered; `_WTX_INSTALL_TMP` is the path returned by `mktemp "$WORKSPACE_ROOT/.wtx-install-tmp.XXXXXX"`; Story 1.2's TOML write uses `$_WTX_INSTALL_TMP` as the intermediate file and `mv` to place it (AD-4)

**Given** the wizard skeleton initializes at startup
**When** initialization runs (before any step appends to the ledger)
**Then** `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` are initialized as empty bash 3.2 indexed arrays (`_WTX_LEDGER_KEYS=()` and `_WTX_LEDGER_VALS=()`); subsequent steps (Stories 1.2–1.6) append to them and Story 1.7 iterates them (AD-7)

**Given** `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story
**When** syntax-check completes
**Then** it exits 0 with no errors (project-context.md testing rule)

---

### Story 1.2: Reference-templating engine — config prompts, plugin discovery & TOML write

**Prerequisite:** Story 1.1 (write primitives `_wtx_toml_escape`, `_wtx_csv_to_toml_array`, `wtx_install_write_or_dryrun`, and the `$_WTX_INSTALL_TMP` / trap pattern are already defined in `lib/wtx-install.sh`).

As a developer setting up wtx in a new workspace,
I want the wizard to collect my forge, project, branch, Jira, and hook preferences through a polished TUI and write a `wtx.toml` containing my actual values with no example placeholders,
So that I can start using `wtx start` immediately without manually editing any file.

**Acceptance Criteria:**

**Given** the wizard reaches Step 1 (welcome banner)
**When** the banner is displayed
**Then** it shows workspace path (`$WORKSPACE_ROOT`) and WTX root (`$WTX_ROOT`) and a Ctrl-C abort notice; with gum: styled box; without gum: plain `echo`/`printf` lines (UX-DR2)

**Given** the wizard reaches Step 2 (binary install)
**When** `wtx` is already on PATH and resolves to `$WTX_ROOT/bin/wtx`
**Then** the symlink step is skipped and the info text `[✓] wtx already on PATH` is displayed; ledger records `symlink: skipped (already on PATH)`

**Given** the wizard reaches Step 2 and `wtx` is not yet on PATH
**When** the user confirms or edits the install prefix (default `~/.local`)
**Then** the wizard runs `bash "$WTX_ROOT/install.sh" --prefix "$WTX_INSTALL_PREFIX"` as a subprocess via `wtx_install_write_or_dryrun` and checks its exit code (AD-3); ledger records `symlink: done` or `symlink: failed` accordingly

**Given** Steps 3–7 collect forge type, org, project dirs, detection markers, branch defaults, Jira pairs, and setup hook
**When** each prompt is presented
**Then** it calls the appropriate `tui_*` function from `lib/worktree-tui.sh` (AD-10); no bare `read` appears in `worktree-install.sh`; every prompt has a functional pure-bash fallback (NFR4, UX-DR3–UX-DR9)

**Given** the user selects forge type
**When** the `tui_choose` list is shown
**Then** options are exactly `github`, `gitlab`, `bitbucket`; the selected value is stored as `forge_type`; no hardcoded default is written to the config if the user changes it (NFR3, UX-DR4)

**Given** Step 8 (setup hook) is reached
**When** `wtx_install_discover_plugins` runs
**Then** it globs `$WTX_ROOT/plugins/*.sh`, reads each file's first `# wtx-plugin-desc:` comment line via `grep -m1`, and emits `filename\tdescription` pairs; wizard prepends `None` and `Custom path…` before `tui_choose` (AD-8, UX-DR9)

**Given** the user completes all config prompts (Steps 2–8)
**When** the wizard writes `wtx.toml`
**Then** it writes via `_wtx_toml_escape`/`_wtx_csv_to_toml_array` for value escaping, writes to `$_WTX_INSTALL_TMP`, then `mv`s to `$WORKSPACE_ROOT/wtx.toml` (consuming the AD-4 / AD-5 primitives from Story 1.1); no value matching the `wtx.example.toml` placeholder set (e.g. `org = "acme"`, `list = ["web", "mobile", "backend"]`) survives in the written file (CAP-2, AD-9)

**Given** the written `wtx.toml` is validated
**When** `wtx_config_get` reads any key from it
**Then** the returned value matches what the user entered at the corresponding prompt; no example placeholder is present (CAP-2)

**Given** a Jira section with zero mappings is the user's choice
**When** `wtx.toml` is written
**Then** a `[jira.projects]` section is present but contains only a comment; no Jira keys are fabricated (ux-flow Step 7)

**Given** the wizard executes its steps end to end
**When** the flow runs
**Then** the step order matches the UX rationale table: Step 0 → idempotency gate → Step 1 → Step 2 → Steps 3–8 (core config) → atomic TOML write → Step 9 → Step 10a → Step 10b → Step 11 (UX-DR15, AD-12, AD-13)

**Given** `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh` is run after this story
**When** syntax-check completes
**Then** it exits 0 (project-context.md testing rule)

---

### Story 1.3: Claude Code hooks setup (Step 9)

**Prerequisite:** Story 1.1 (`wtx_install_write_or_dryrun` guard and the `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS` arrays are defined in `lib/wtx-install.sh`).

As a developer who has just configured wtx,
I want the wizard to offer to install Claude Code lifecycle hooks with a clear description of what each hook does,
So that I can make an informed choice and have the hooks set up automatically without locating or copying files manually.

**Acceptance Criteria:**

**Given** the wizard reaches Step 9 (Claude Code hooks)
**When** the hooks step is shown
**Then** a gum styled box (or plain text fallback) lists the three hook scripts (`worktree-create.sh`, `worktree-detect.sh`, `worktree-remove.sh`) with a one-line description of each, followed by `Install Claude Code hooks? [Y/n]` (UX-DR10)

**Given** the user confirms hook installation
**When** the wizard proceeds
**Then** it runs `bash "$WTX_ROOT/install.sh" --hooks` as a subprocess (AD-3); the exit code is checked; on success the three files in `.claude/hooks/` are byte-for-byte copies of the sources in `$WTX_ROOT/hooks/` (CAP-3)

**Given** the user declines hook installation
**When** the wizard proceeds
**Then** no hook files are written or modified; `.claude/hooks/` is unchanged (CAP-3)

**Given** hook installation runs in `--dry-run` mode
**When** the subprocess call is made
**Then** `--dry-run` is appended: `bash "$WTX_ROOT/install.sh" --hooks --dry-run`; no files are written; `[dry-run] would copy:` lines are printed for each hook (AD-3, AD-5)

**Given** hook installation completes (success, failure, or skipped)
**When** the ledger is updated
**Then** exactly one entry is appended: key = `hooks`, value = `done`, `failed`, or `skipped` respectively (AD-7)

---

### Story 1.4: Extras menu — Gradle init & PATH hint (Step 10)

**Prerequisite:** Story 1.1 (`wtx_install_write_or_dryrun` guard and the ledger arrays are defined in `lib/wtx-install.sh`).

As a developer finishing wtx setup,
I want the wizard to offer optional extras (Gradle worktree-cache init and a PATH export hint) each with a one-line explanation,
So that I can opt in to useful enhancements without being forced into them.

**Acceptance Criteria:**

**Given** the wizard reaches Step 10a (Gradle extra)
**When** the Gradle option is presented
**Then** a `tui_confirm` (or plain yes/no) explains the Gradle worktree-cache init script in one line; the default is `N` (UX-DR11)

**Given** the user confirms the Gradle extra
**When** the wizard proceeds
**Then** it runs `bash "$WTX_ROOT/install.sh" --gradle` as a subprocess; exit code is checked; result recorded in ledger as key = `gradle`, value = `done` or `failed` (AD-3, AD-7)

**Given** the user declines the Gradle extra
**When** the wizard proceeds
**Then** `install.sh` is not invoked for gradle; `~/.gradle/init.d/` is unchanged; ledger records `gradle: skipped` (CAP-4)

**Given** the wizard reaches Step 10b (PATH hint)
**When** `case ":$PATH:" in *":$WTX_INSTALL_PREFIX/bin:"*` matches
**Then** the PATH hint step is not shown; ledger records `path-hint: skipped (already on PATH)` (AD-11, UX-DR12)

**Given** the wizard reaches Step 10b and the prefix bin dir is NOT on PATH
**When** the user confirms the hint
**Then** the wizard prints `export PATH="$HOME/.local/bin:$PATH"` and restart guidance; ledger records `path-hint: shown` (UX-DR12)

**Given** either extra runs in `--dry-run` mode
**When** the subprocess call would occur
**Then** `--dry-run` is appended to the `install.sh` call; no files are written; `[dry-run] would …` output is printed (AD-5)

---

### Story 1.5: Idempotency — skip / overwrite / merge

**Prerequisite:** Story 1.1 (wizard skeleton, Step 0 preflight, and ledger arrays in place in `lib/wtx-install.sh`).

As a developer running `wtx install` in a workspace that already has a `wtx.toml`,
I want the wizard to detect the existing config and offer me a clear choice between keeping it, overwriting it, or re-running prompts with my existing values pre-filled,
So that a second install run never silently clobbers my configuration.

**Acceptance Criteria:**

**Given** `$WORKSPACE_ROOT/wtx.toml` exists when `wtx install` is invoked
**When** the idempotency gate runs (after Step 0, before Step 1 banner)
**Then** the wizard presents exactly three options: `skip`, `overwrite`, `merge` — no files are touched before this choice is made (CAP-5, AD-13)

**Given** the user chooses `skip`
**When** the wizard proceeds
**Then** no config prompts (Steps 2–8) are executed; the wizard loads the existing file into the ledger and jumps directly to Step 9 (hooks); `wtx.toml` is byte-for-byte identical after the run (CAP-5, AD-13)

**Given** the user chooses `overwrite`
**When** the wizard proceeds
**Then** the full wizard runs from Step 1 with empty defaults for all prompts; the final `wtx.toml` reflects only the new prompt answers (CAP-5)

**Given** the user chooses `merge`
**When** the wizard runs config prompts (Steps 3–8)
**Then** `unset _WTX_CONFIG_LOADED` is called, `WTX_CONFIG` is set to the existing `wtx.toml`, `lib/wtx-config.sh` is re-sourced, and each `tui_input` call receives the current config value as its default argument (CAP-5, AD-6)

**Given** merge mode is active and the user accepts all defaults
**When** the new `wtx.toml` is written atomically
**Then** the file content is semantically equivalent to the original (same values, valid TOML); the original is overwritten only when the atomic move succeeds (AD-4, AD-6)

**Given** `wtx install` is run twice with `skip` chosen on the second run
**When** both runs complete
**Then** `diff` shows the `wtx.toml` is byte-for-byte identical between the first and second run (CAP-5)

---

### Story 1.6: Dry-run mode — end-to-end threading

**Prerequisite:** Story 1.1 (`wtx_install_write_or_dryrun` defined; `WTX_INSTALL_DRY_RUN` exported in preflight; AD-5 guard in place).

As a developer evaluating wtx in a new workspace,
I want to run `wtx install --dry-run` and see a complete preview of every action the wizard would take without any filesystem changes,
So that I can confirm the install plan before committing to it.

**Acceptance Criteria:**

**Given** `wtx install --dry-run` is invoked
**When** Step 0 preflight runs (from Story 1.1)
**Then** `--dry-run` is parsed first — before git check and gum detection — and `WTX_INSTALL_DRY_RUN=1` is exported; all subsequent write operations consult this variable via the AD-5 guard (AD-12, AD-5)

**Given** `WTX_INSTALL_DRY_RUN=1` is active and the wizard reaches any step that would write or copy a file
**When** that step's write call executes
**Then** it goes through `wtx_install_write_or_dryrun` (defined in Story 1.1); the function prints the appropriate `[dry-run]` line (`would write:`, `would create:`, or `would copy:`) with the full target path, and returns without executing the command (CAP-6, AD-5, UX-DR14)

**Given** `WTX_INSTALL_DRY_RUN=1` and the wizard delegates to `install.sh`
**When** any subprocess call is made
**Then** `--dry-run` is always appended to the subprocess arguments regardless of which story's step is executing; no `install.sh` call bypasses `wtx_install_write_or_dryrun` (AD-3, AD-5)

**Given** the wizard runs a complete dry-run from Step 0 through Step 11
**When** `diff` is run against every file the wizard would normally touch
**Then** no changes are detected; the filesystem is identical to the state before the dry run (CAP-6)

**Given** all prompts appear during dry-run
**When** the user answers them
**Then** the prompts behave identically to a real run; every action that would occur in a real run has a corresponding `[dry-run] would …` output line (CAP-6, UX-DR14)

**Given** the dry-run completes and Step 11 summary renders
**When** the summary is displayed
**Then** a header note is printed: `[dry-run] No files were written. Remove --dry-run to apply.` (UX-DR13)

---

### Story 1.7: Completion summary & doctor handoff (Step 11)

**Prerequisite:** Story 1.1 (the `_WTX_LEDGER_KEYS`/`_WTX_LEDGER_VALS` arrays are initialized in `lib/wtx-install.sh`; Stories 1.2–1.6 append to them — integration-tested after those merge).

As a developer who has just finished `wtx install`,
I want a clear summary of everything that was installed, skipped, or failed — plus the exact command to verify my install — displayed before the wizard exits,
So that I know exactly what happened and what to do next.

**Acceptance Criteria:**

**Given** the wizard reaches Step 11 (completion summary)
**When** the summary renders
**Then** it iterates `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` in index order and prints one row per entry: `[✓]` for `done`, `[-]` for `skipped*`, `[!]` for `failed`; with gum: styled box; without gum: plain text (CAP-7, AD-7, UX-DR13)

**Given** the summary is displayed
**When** it finishes rendering
**Then** the exact text `wtx doctor` is printed as the verify command (CAP-7, UX-DR13)

**Given** `wtx doctor` is run immediately after a complete (non-dry-run) install
**When** it completes
**Then** it exits 0 with all required dependencies and installed files present (NFR12, CAP-7)

**Given** a step earlier in the wizard failed (e.g. `install.sh --hooks` returned non-zero)
**When** the ledger is rendered in Step 11
**Then** that step's row shows `[!]` followed by a one-line description; the wizard still exits with a non-zero code (CAP-7)

**Given** the summary ledger arrays `_WTX_LEDGER_KEYS` and `_WTX_LEDGER_VALS` are used
**When** they are defined and populated
**Then** they use bash 3.2 indexed-array syntax only — no `declare -A`, no associative-array operations (FR22, NFR1)

**Given** no step previously printed its own completion status
**When** the ledger is reviewed
**Then** Step 11 is the single source of all summary output; no other step in the wizard prints a `[✓]`/`[-]`/`[!]` line (AD-7)

---

## Story S.1 (Standalone): Install & set up graphify

As a wtx developer,
I want graphify installed and configured in the wtx project,
So that I can use it as a knowledge-graph tool during development.

**Context:** graphify is a separate tooling concern explicitly excluded from the installer epic (SPEC.md non-goals). It is tracked here as a standalone backlog item.

**Acceptance Criteria:**

**Given** the graphify repository at https://github.com/safishamsi/graphify
**When** the install steps complete
**Then** graphify is installed and accessible for use in the wtx project environment

**Given** graphify is installed
**When** it is invoked
**Then** it functions correctly against the wtx repository

*(Implementation details and exact install steps to be refined at story pick-up time after reviewing the graphify README.)*
