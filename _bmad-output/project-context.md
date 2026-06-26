---
project_name: 'wtx'
user_name: 'Ángel'
date: '2026-04-15'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'style_rules', 'workflow_rules', 'dont_miss_rules']
status: 'complete'
rule_count: 60
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **Language:** Pure Bash, targeting **bash 3.2** (macOS default) — no bashisms beyond 3.2
- **Platform:** macOS + Linux; no `readlink -f`, no GNU-only flags
- **Runtime:** shell-only; no Node, no Python, no compiler, no package manager
- **Config format:** flat TOML (`wtx.toml`) — single-level `[section]` + one dotted subtable `[jira.projects]`; arrays single-line; no inline tables
- **Optional tools (feature-detected at call sites, never assumed):** `gum`, `jq`, `claude`, `timeout`
- **Tests:** shell harnesses in `tests/` — `test-wtx-config.sh`, `test-wtx-dispatcher.sh`, `test-worktree-registry.sh` (+ TOML fixtures under `tests/fixtures/`)
- **Validation commands:**
  - `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`
  - `bash tests/test-wtx-config.sh`
  - `bash tests/test-wtx-dispatcher.sh`
  - `bash tests/test-worktree-registry.sh`
- **No CI, no Makefile, no package.json.** `install.sh` is a stub — do not depend on it.
- **Entry point:** `bin/wtx` — the only user-facing dispatcher; everything routes through it or duplicates its path-resolution logic

## Critical Implementation Rules

### Language-Specific Rules (Bash)

- **Use `set -u` only — NEVER `set -e`.** Scripts validate inputs explicitly and must degrade gracefully. Adding `set -e` silently breaks optional-tool fallbacks.
- **Bash 3.2 compatibility is mandatory.** No associative arrays (`declare -A`), no `${var^^}` / `${var,,}`, no `mapfile` / `readarray`, no `[[ =~ ]]` captures assumed to persist across subshells.
- **No `readlink -f`** (missing on macOS). Resolve symlinks by hand — see the `BASH_SOURCE[0]` walk in `bin/wtx` for the canonical pattern.
- **Resolve workspace root via `git rev-parse --git-common-dir`, never `--show-toplevel`.** Inside a linked worktree, `--show-toplevel` returns the worktree path and breaks registry lookups. Every `scripts/worktree-*.sh` must keep this fallback in sync with `bin/wtx`.
- **Source libs through `$WTX_ROOT/lib/...`**, never relative paths. Each script wraps the `source` in an inline stub-fallback block so it still runs if the lib is missing — preserve this pattern when adding new libs.
- **No `eval`. Ever.** The config loader is awk/sed only — do not introduce `eval` or external TOML parsers.
- **Feature-detect optional tools at the call site:** `command -v gum >/dev/null 2>&1`, same for `jq`, `claude`, `timeout`. Never assume presence; always provide a pure-bash fallback path.
- **Errors go to stderr (`>&2`) with a clear prefix**; exit codes are meaningful. Do not swallow errors to keep `set -u` happy — fix the unset variable.
- **Quote everything.** Especially `"$WORKSPACE_ROOT"`, `"$WTX_ROOT"`, and any path — this tree lives under a path with spaces.

### Framework-Specific Rules (wtx architecture)

- **`bin/wtx` is the single entry point.** Subcommands `start` / `done` / `status` `exec` into `scripts/worktree-*.sh`; `init` / `doctor` / `version` are inline. Do not add new user-facing entry points — extend the dispatcher.
- **Config access goes through `lib/wtx-config.sh`.** Use `wtx_config_get "section.key" "default"` for scalars and `wtx_config_get_list "section.key"` for lists. Never re-parse TOML ad-hoc, never hardcode new values.
- **Config resolution order (first hit wins):** `$WTX_CONFIG` → `$WORKSPACE_ROOT/wtx.toml` → `$HOME/.config/wtx/config.toml`. There is a legacy `$WORKSPACE_ROOT/.worktree-projects` fallback — preserve it.
- **Loader is idempotent within a shell** (guarded by `_WTX_CONFIG_LOADED`). To re-source in tests, `unset _WTX_CONFIG_LOADED` first.
- **Portability overhaul is in effect** (`PORTABILITY_PROMPT.md`): when you see Acme-specific hardcodes (Bitbucket org `acme`, Jira keys, Android/Gradle markers), the fix is to add a field to `wtx.example.toml`, read it via `wtx_config_get`, and update call sites. Do not add new hardcodes.
- **Config-driven fields already in place** (use them as the template): Jira project key, forge org, forge type, project list, detection markers, base branch, branch prefix.
- **Setup hooks live in `plugins/`**, referenced via `[worktree].setup_hook` in `wtx.toml`. `plugins/android-setup.sh` is the reference. **Do not re-add Android logic into core `scripts/` or `lib/`.**
- **Claude Code hooks (`hooks/worktree-*.sh`) are invoked by the Claude harness, not by `bin/wtx`.** Keep them independently sourceable.
- **`WORKTREE_DONE_QUIET=1`** suppresses browser prompts when `worktree-done.sh` is called from `worktree-status.sh` — preserve this contract.
- **Worktree registry** lives at `[worktree].registry_path` (default `.claude/worktree-registry.md`). Read/write only via `lib/worktree-tui.sh` helpers.
- **`scripts/bmad-dev-loop` and `scripts/builtin-worktree-*.sh` are NOT part of the core dispatcher.** Don't route them through `bin/wtx`.

### Testing Rules

- **Tests are shell scripts under `tests/`.** Run directly: `bash tests/test-wtx-config.sh`. No harness, no framework — each file is self-contained and prints pass/fail.
- **Drive libs directly by sourcing them** with `WTX_CONFIG` / `WORKSPACE_ROOT` set per case. Do not invoke `bin/wtx` as a subprocess unless you are explicitly testing the dispatcher (`test-wtx-dispatcher.sh`).
- **Reset loader state between cases:** `unset _WTX_CONFIG_LOADED` before re-sourcing `lib/wtx-config.sh`. The guard is intentional — respect it.
- **TOML fixtures live in `tests/fixtures/`.** Add new fixtures there, one per scenario; do not inline multi-line TOML into test scripts.
- **Never mock git.** Dispatcher tests operate on real temporary git repos/worktrees. If you need isolation, create a temp repo under `mktemp -d` and clean up on exit.
- **Always syntax-check before declaring done:** `bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh`. This is the closest thing to CI the project has.
- **Don't add a test framework.** No bats, no shunit2. Keep the suite dependency-free.
- **A new feature that reads config must ship a fixture-driven test case** exercising its `wtx_config_get` call path, including the default fallback.

### Code Quality & Style Rules

- **File layout is fixed:** `bin/` (dispatcher), `lib/` (sourced helpers), `scripts/` (exec'd entry points), `hooks/` (Claude harness), `plugins/` (user-extensible setup hooks), `tests/`. Do not invent new top-level dirs without a config knob to opt in.
- **Naming:** kebab-case for files (`worktree-start.sh`, `wtx-config.sh`); `snake_case` for functions and variables; public loader API is `wtx_*` (e.g. `wtx_config_get`); private helpers prefix with `_` (e.g. `_WTX_CONFIG_LOADED`).
- **One file, one responsibility.** Each `scripts/worktree-*.sh` is a standalone entry point; each `lib/worktree-*.sh` is a concern (tui, api, jira, launch, warp, interactive).
- **Libs are pure sourceable modules** — define functions, do not execute top-level work. Scripts are executable — shebang + `main`-style flow.
- **Comments explain WHY, not WHAT.** Default to no comments. One-liners only when a constraint is non-obvious (macOS quirk, bash 3.2 limitation, intentional `--git-common-dir` choice).
- **No tabs in shell sources**, 2-space indent, `then` / `do` on the same line as `if` / `while`, `fi` / `done` at matching indent.
- **Error messages:** `echo "wtx: <context>: <what went wrong>" >&2`. User-facing output is plain text; `gum` styling is an optional enhancement, never a requirement.
- **Keep `bin/wtx` dispatcher logic minimal.** Business logic belongs in `scripts/` or `lib/`, not in the dispatcher.
- **`wtx.example.toml` is documentation.** Every config key the code reads MUST appear there with a comment explaining defaults and valid values.

### Development Workflow Rules

- **Branch naming:** `feat/<slug>`, `fix/<slug>`, `refactor/<slug>`, `chore/<slug>`. When a Jira ticket is involved, wtx's own `worktree-start` generates the canonical form — use it, don't hand-roll.
- **Commit message format:** `<type>(<scope>): <summary>` (e.g. `feat(wtx): add flat-TOML config loader (Phase 1)`). Scope is almost always `wtx`. Keep the portability-phase tag when relevant (`Phase 1`, `Phase 2`, …).
- **Commits are small and reviewable** — one concern per commit. The portability overhaul is explicitly phased; do not cross phase boundaries in a single commit.
- **Main branch is `main`.** PRs target `main`. Do not force-push `main`.
- **Never `--no-verify`, never `--no-gpg-sign`.** If a hook fails, fix it and make a new commit; do not amend published commits.
- **`install.sh` is a stub.** Do not add install logic until the portability overhaul lands — users source `bin/wtx` directly.
- **When you hardcode, you lose.** Before committing, grep your diff for literal Acme / Bitbucket / Jira / Android values; if any slipped in, route them through `wtx_config_get` and add a key to `wtx.example.toml`.
- **Doctor first when debugging environment issues:** `bin/wtx doctor`. Extend it when you add a new optional-tool dependency or config requirement.
- **`PORTABILITY_PROMPT.md` is the source of truth for the overhaul roadmap.** Keep it in sync when you finish a phase.

### Critical Don't-Miss Rules

**Anti-patterns — do NOT:**
- Add `set -e` "for safety" — it breaks optional-tool fallbacks and silent-degradation flows.
- Use `git rev-parse --show-toplevel` to find the workspace — inside a linked worktree it returns the wrong path. Always `--git-common-dir`.
- Use `readlink -f` — macOS bash 3.2 doesn't have it. Walk `BASH_SOURCE[0]` manually.
- Introduce `eval`, `source <(...)`, or a third-party TOML parser into the config loader.
- Hardcode `acme`, `PROJ`, `settings.gradle`, or any other Acme/Android literal. Route through `wtx_config_get`.
- Assume `gum`, `jq`, `claude`, or `timeout` exist. Feature-detect and provide a pure-bash fallback.
- Put Android/Gradle logic into core `scripts/` or `lib/` — it belongs in `plugins/`.
- Amend published commits or use `--no-verify` to dodge hook failures.
- Add a test framework or CI tool. The suite must stay shell-only and dependency-free.

**Edge cases to handle:**
- Script invoked directly (no dispatcher) → re-resolve `WTX_ROOT` and `WORKSPACE_ROOT` in the script's own fallback block, identical to `bin/wtx`.
- `wtx.toml` missing → fall back to `$HOME/.config/wtx/config.toml`, then to legacy `.worktree-projects`, then to sensible defaults. Never error.
- Config value missing → `wtx_config_get` returns the caller-supplied default. Always pass one; never assume non-empty.
- `WORKTREE_DONE_QUIET=1` set → suppress all interactive prompts, not just the browser one.
- Workspace path contains spaces or tildes (this repo lives under iCloud Drive) → quote every path expansion.
- Repo has no entry in `[jira.projects]` → Jira integration silently disables for that repo; do not prompt.

**Security / safety:**
- Never log Jira tokens, forge credentials, or anything read from `~/.bmad-dev-loop.env`.
- `bin/wtx doctor` must not dump secrets even in verbose mode.
- Destructive git operations (`worktree remove`, branch prune) require an explicit confirm unless `WORKTREE_DONE_QUIET=1`.

**Gotchas:**
- `lib/wtx-config.sh` is guarded by `_WTX_CONFIG_LOADED`; re-sourcing is a no-op. Tests must `unset` it between cases.
- Every `scripts/worktree-*.sh` duplicates the dispatcher's path-resolution block. When you change one, change them all — there is no shared helper (intentional: helpers would require sourcing, which requires path resolution first).
- `bin/wtx` resolves symlinks via a manual `BASH_SOURCE` walk. If you refactor path resolution, run the dispatcher tests from both a symlinked install and a direct one.

---

## Usage Guidelines

**For AI Agents:**
- Read this file before touching any shell source in this repo.
- Follow ALL rules exactly. When in doubt, prefer the more restrictive option.
- Cross-reference `CLAUDE.md` and `PORTABILITY_PROMPT.md` for roadmap context.
- If you discover a new unobvious pattern, propose adding it here.

**For Humans:**
- Keep this file lean and focused on what agents miss.
- Update when the portability overhaul advances a phase or when a new config key is added.
- Remove rules that become obvious or obsolete.

Last Updated: 2026-04-15
