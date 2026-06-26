---
id: SPEC-wtx-install
companions:
  - ux-flow.md
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate.

# wtx Interactive Project Installer

## Why

Adopting wtx in a new git workspace today requires three separate manual steps: run `install.sh` to create the PATH symlink, run `wtx init` to generate a partial `wtx.toml` (no Jira key mapping, no setup-hook selection, no gum polish), then edit the file by hand to fill in the gaps. There is no single command that takes a developer from zero to a fully-wired workspace. The friction is sharpest when onboarding a teammate or dropping wtx into a new project for the first time — the multi-step process breaks flow and leaves placeholder values in configs that silently produce wrong behavior. A unified, visually polished install wizard removes this barrier and makes first use as smooth as `npx bmad-method install`.

## Capabilities

- **CAP-1: Guided install wizard**
  - **intent:** A developer can run `wtx install` in any git workspace and be guided through the complete wtx setup — binary on PATH, config generated, hooks optionally wired — via a staged TUI (gum when available, pure-bash `read` fallback otherwise) without consulting documentation or editing files manually.
  - **success:** Running `wtx install` from a clean workspace completes without errors, produces a valid `wtx.toml` and PATH symlink, and exits 0. The same command run without `gum` installed also completes without errors using plain prompts.

- **CAP-2: Reference-templating engine**
  - **intent:** The wizard replaces every placeholder value in the generated `wtx.toml` — forge type, forge org, Jira project key map, project directory list, detection markers, base branch, branch prefix, and setup hook — with values the user provides during the session, so no example placeholder survives into the written file.
  - **success:** The `wtx.toml` written after a completed wizard contains no value that matches the generic placeholder set in `wtx.example.toml` (e.g., `org = "acme"`, `list = ["web", "mobile", "backend"]`, `base_branch = "develop"` when the user chose `main`); all fields reflect the user's actual inputs.

- **CAP-3: Hooks setup**
  - **intent:** After generating the config, the wizard offers to install Claude Code lifecycle hooks into the current workspace, showing what each hook does before asking for confirmation, so the user can make an informed choice without reading separate documentation.
  - **success:** When the user confirms, the three hook files (`worktree-create.sh`, `worktree-detect.sh`, `worktree-remove.sh`) are present in `.claude/hooks/` and are byte-for-byte copies of the source files in `$WTX_ROOT/hooks/`. When the user declines, no hook files are written or modified.

- **CAP-4: Extras menu**
  - **intent:** After core install, the wizard offers optional extras — Gradle worktree-cache init script and a shell rc PATH hint — each explained in one line, installed only on explicit confirmation.
  - **success:** Each extra is installed if and only if the user confirmed it. Declining all extras leaves the filesystem identical to the state before the extras step.

- **CAP-5: Idempotency**
  - **intent:** When `wtx.toml` already exists in the workspace, the wizard detects it before touching any files and offers three choices: skip config generation (keep existing file), overwrite (re-run all config prompts from scratch), or merge (re-run prompts with the existing values pre-filled as defaults).
  - **success:** Running `wtx install` twice in succession, confirming "skip" on the second run, leaves `wtx.toml` byte-for-byte identical to what the first run wrote. Running with "overwrite" produces a freshly written file from new prompt answers. Running with "merge" uses existing values as prompt defaults.

- **CAP-6: Dry-run mode**
  - **intent:** `wtx install --dry-run` shows exactly what the wizard would do — every file it would write, every symlink it would create, every hook it would copy — without modifying the filesystem, so a user can preview the effect before committing.
  - **success:** A dry run produces console output listing each action prefixed with `[dry-run]`. After the dry run completes, `diff` shows no changes to any file in the workspace or on the filesystem that the wizard would normally touch.

- **CAP-7: Completion summary**
  - **intent:** At the end of a successful install, the wizard displays a styled summary of every action taken (items installed, files written, items skipped) and the exact `wtx doctor` command to verify the install.
  - **success:** The summary is printed before the wizard exits. Running `wtx doctor` immediately after a complete install exits 0 with all required dependencies and install files present.

## Constraints

- bash 3.2 compatible: no `readlink -f`, no associative arrays, no process substitution to array — the wizard runs on macOS's built-in bash without Homebrew.
- `set -u` only, never `set -e` anywhere in new code; optional steps tolerate failure by convention, not by exception.
- No hardcoded org, project name, Jira key, forge type, or branch literal anywhere in new code — every value comes from user input or from the config layer at runtime.
- Every interactive prompt has a working pure-bash `read` fallback; the wizard must complete end-to-end when `gum` is absent.
- No `eval` of raw user input anywhere.
- All file paths resolved relative to `WTX_ROOT` or `WORKSPACE_ROOT`; no absolute path assumptions beyond what those two exports provide.
- Config reads in new code use `wtx_config_get` / `wtx_config_get_list`; no ad-hoc TOML parsing.
- `gum`, `jq`, `claude`, and `timeout` absent at any wizard step must not abort the flow; the wizard degrades to the next available mechanism.

## Non-goals

- graphify integration — tracked separately as its own story.
- Implementation architecture — which files change, how helpers are split, where the subcommand is wired — deferred to the Create Architecture step.
- New config schema fields beyond those already in `wtx.example.toml`; the wizard configures the existing schema, it does not extend it.
- CI/CD, packaging, or distribution changes — `wtx install` is an interactive user command, not a machine-invoked step.
- Auto-detection of forge type or org from git remote URLs — the wizard asks; it does not guess.

## Success signal

A developer with no prior wtx configuration runs `wtx install` in a new git workspace, answers the wizard prompts, and arrives at: a valid symlink at `$HOME/.local/bin/wtx`, a `wtx.toml` at `$WORKSPACE_ROOT/wtx.toml` with their actual org and project values and no example placeholder surviving, and `wtx doctor` reporting all required dependencies present — without the developer having edited any file manually.

## Assumptions

- The wizard is invoked from inside a git repository; it may check for this and error early if the current directory is not in a git tree.
- `install.sh` remains the canonical authority for symlink creation; the wizard delegates to it rather than reimplementing that logic.
- `wtx init` remains independently usable as a lower-level config command for scripted or testing use; the wizard does not deprecate or remove it.
- Jira integration is optional at install time; the wizard accepts zero Jira project key mappings and still produces a valid config.

## Open Questions

- **Merge behavior (CAP-5):** When the user chooses merge, should each wizard prompt be pre-filled with the value from the existing `wtx.toml` (user edits in place), or should the existing file be accepted as-is with only fields absent from the file prompted for?
- **Setup hook discovery:** Is a directory scan of `$WTX_ROOT/plugins/` sufficient to populate the hook selection menu, or do plugins need a lightweight manifest (name, one-line description) so the TUI can display meaningful labels rather than raw filenames?
- **PATH check:** Should the wizard detect whether `$PREFIX/bin` is already on `PATH` and suppress the PATH hint when it is already present?
