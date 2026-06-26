# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

`wtx` is a portable git worktree management toolkit. The portability overhaul (Phases 1–5) is complete: all Acme-specific hardcodes have been replaced by config-driven lookups against `wtx.toml`. When editing, continue to read values via `wtx_config_get` / `wtx_config_get_list` — do not introduce new hardcoded org/project/Jira literals.

## Commands

- Syntax-check all shell sources: `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
- Run config loader tests: `bash tests/test-wtx-config.sh`
- Run dispatcher tests: `bash tests/test-wtx-dispatcher.sh`
- Run registry helper tests: `bash tests/test-worktree-registry.sh`
- Environment/install check: `bin/wtx doctor`
- Print version: `bin/wtx version`
- Generate a `wtx.toml` interactively in the current git workspace: `bin/wtx init`

There is no package.json, Makefile, or CI — validation is shell-only.

## Architecture

### Entry point and path resolution (`bin/wtx`)

`bin/wtx` is the single user-facing dispatcher. It does two things that every script downstream depends on:

1. **Resolves `WTX_ROOT`** by walking symlinks from `BASH_SOURCE[0]` without using `readlink -f` (macOS-safe). Exports it so child scripts source libs via `$WTX_ROOT/lib/...` instead of relative paths.
2. **Resolves `WORKSPACE_ROOT`** using `git rev-parse --git-common-dir`, not `--show-toplevel`. This is critical: when invoked from inside a linked worktree, `--show-toplevel` returns the worktree path, which breaks registry lookups. Every `scripts/worktree-*.sh` script repeats this same resolution as a fallback when run directly (without the dispatcher), so keep the two in sync.

Subcommands `start`/`done`/`status` `exec` into `scripts/worktree-*.sh`; `init`/`doctor`/`version` are implemented inline in `bin/wtx`.

### Config layer (`lib/wtx-config.sh`)

Flat-TOML loader, bash 3.2 compatible, awk/sed only — **no external parsers, no eval**. Resolution order (first hit wins):

1. `$WTX_CONFIG` (explicit override, used by tests)
2. `$WORKSPACE_ROOT/wtx.toml` (repo-local, normal case)
3. `$HOME/.config/wtx/config.toml` (user global)

The supported schema is intentionally flat: top-level `[section]` tables plus one dotted subtable `[jira.projects]`. Arrays must be single-line. See `wtx.example.toml` for the full schema. Public API:

- `wtx_config_get "section.key" ["default"]` → scalar
- `wtx_config_get_list "section.key"` → newline-separated list

There is a backward-compat fallback to a legacy `$WORKSPACE_ROOT/.worktree-projects` file when no `wtx.toml` is present. When adding new config-driven behavior, extend this loader rather than reparsing TOML ad-hoc.

### Script layer (`scripts/`)

Three top-level scripts implement the main flows; each is a standalone entry point (runnable directly or via `bin/wtx`):

- `worktree-start.sh` — create a worktree. Interactive TUI by default; accepts a Jira ticket (`PROJ-1234`), a free-form name, optional base branch and project dir. `--no-exec` skips the trailing `claude` launch.
- `worktree-done.sh` — finalize: summarize work, push, open PR, remove the worktree and prune the branch. Honors `WORKTREE_DONE_QUIET=1` to suppress browser prompts when called from `worktree-status.sh`.
- `worktree-status.sh` — dashboard across all known projects; interactive menu when no arg, table-only when a project dir is passed.

`builtin-worktree-*.sh` are helper scripts for the Claude Code–managed worktrees under `.claude/worktrees/`. `bmad-dev-loop` is a separate BMAD tool, not part of the core dispatcher.

### Library layer (`lib/`)

- `worktree-tui.sh` — `gum` wrappers with pure-bash fallbacks (`tui_confirm`, `tui_input`, …) and worktree-registry read/write. Every script sources this with an inline stub fallback block so the scripts still work if the lib is missing.
- `worktree-api.sh` — git-plumbing helpers (branch detection, rebase, push).
- `worktree-jira.sh` — Jira ticket fetch + branch-name generation. Jira project keys come from `[jira.projects]` in `wtx.toml` keyed by repo name.
- `worktree-interactive.sh` — shared interactive flows used by both `start` and `status`.
- `worktree-launch.sh` / `worktree-warp.sh` — launchers for `claude` and Warp terminal tabs.

### Hooks and plugins

- `hooks/worktree-create.sh`, `worktree-detect.sh`, `worktree-remove.sh` — Claude Code hook integrations that run around worktree lifecycle events; they are invoked by the Claude harness, not by `bin/wtx` directly.
- `plugins/android-setup.sh` — example post-create hook (Android/Gradle). Referenced from `[worktree].setup_hook` in `wtx.toml`. Treat this as the reference implementation for new setup hooks — do not re-add Android logic into core scripts.

### Error handling convention

Scripts use `set -u` only, **never `set -e`**. They validate inputs early and print clear errors. Optional tooling (`gum`, `jq`, `claude`, `timeout`) must be detected at call sites, not assumed. When touching these scripts, preserve graceful-degradation behavior — do not tighten with `set -e`.

### Testing

Tests live in `tests/` with TOML fixtures under `tests/fixtures/`. They drive the config loader and dispatcher directly by sourcing the libs and setting `WTX_CONFIG`/`WORKSPACE_ROOT` per case. The pattern for new tests: reset loader state with `unset _WTX_CONFIG_LOADED` between cases, then re-`source` the lib — the loader is guarded to be idempotent within one shell.

## Portability rules (in effect until the overhaul is done)

When editing scripts, do not add new hardcoded Acme values. If you find an existing one, the fix is to:

1. Add a field to `wtx.example.toml` with documentation.
2. Read it via `wtx_config_get` with a sensible default.
3. Update call sites.

The Jira project key, forge org, forge type, project list, detection markers, base branch, and branch prefix are already config-driven — use them as the template.

## graphify (knowledge graph — use it selectively)

This repo has a graphify knowledge graph at `graphify-out/` (god nodes, community
structure, cross-file relationships across `bin/`, `lib/`, `scripts/`, `hooks/`,
`plugins/`, `tests/`, and the docs). It is **targeted tooling, not an every-task
step** — reach for it only when a whole-codebase view actually helps.

**Use the graph first** (only when `graphify-out/graph.json` exists) for:
- "How does X work end-to-end?" / onboarding / architecture questions that span files.
- Tracing a flow across the script → lib → config layers (e.g. how `wtx start` reaches `wtx_config_get`).
- Impact analysis before a change: `graphify affected "<symbol>"` — what depends on this?
- Finding the relationship between two things: `graphify path "<A>" "<B>"`.
- Explaining one concept and its neighbors: `graphify explain "<concept>"`.

Default query: `graphify query "<question>"` — returns a scoped subgraph, usually far
smaller than reading files one by one or grepping. Read `graphify-out/GRAPH_REPORT.md`
only for a broad architecture overview when a query doesn't surface enough.

**Skip the graph** (just Read/Edit/grep normally) for:
- Single-file edits, syntax fixes, or anything where you already know the file.
- Running or reading tests; trivial lookups where a direct grep/read is faster.
- Anything depending on **uncommitted** changes — the graph reflects the last commit.

**Freshness:** a git `post-commit`/`post-checkout` hook rebuilds the graph
automatically (AST-only, no API cost). Only run `graphify update .` manually if you
need the graph current against changes you haven't committed yet.

## Autonomous story-automator runs

**Exception — `bmad-story-automator` workers:** when you are a `bmad-story-automator`
worker (e.g. a `dev-story` agent running under `claude-rotate-run --automator`), you
carry the user's standing session-level authorization to make **local commits** for the
story you implement — commit autonomously, without pausing to ask. Before each commit,
run `bash scripts/secret-scan.sh` and confirm it exits clean, then follow this repo's
commit conventions. **Local commits only — do not push** (this repo has a remote at
`cannt/wtx-worktree-toolkit`; pushing is always the user's call).
