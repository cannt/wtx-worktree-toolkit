# wtx — Architecture

## Overview

`wtx` is a bash CLI toolkit for managing git worktrees in a multi-project workspace. It provides interactive and scripted flows for creating, monitoring, and finalizing worktrees, with optional integrations for Jira, Bitbucket/GitHub/GitLab, Claude Code (AI), and Warp terminal.

The project is currently in a **portability overhaul** (Phases 1–3 complete, 4–5 pending): all Acme-specific hardcoding has been replaced by config-driven lookups via `wtx.toml`.

---

## Directory Layout

```
bin/
  wtx                        # Dispatcher: resolves WTX_ROOT + WORKSPACE_ROOT, routes subcommands

lib/
  wtx-config.sh              # Flat-TOML config loader (the base layer — sourced by all)
  worktree-tui.sh            # gum wrappers + bash fallbacks, worktree registry read/write
  worktree-api.sh            # curl-first REST API (Jira + Bitbucket)
  worktree-jira.sh           # Jira integration, branch suggestion, duplicate detection
  worktree-interactive.sh    # Interactive TUI creation flow (extracted from worktree-start)
  worktree-launch.sh         # Claude Code smart launch menu (BMAD-aware)
  worktree-warp.sh           # Warp terminal 2-pane tab config generation

scripts/
  worktree-start.sh          # Create a worktree (interactive or scripted)
  worktree-done.sh           # Finalize: push, PR, remove worktree
  worktree-status.sh         # Dashboard: list, manage, rebase worktrees
  builtin-worktree-enhance.sh   # PostToolUse hook: setup newly-created built-in worktree
  builtin-worktree-cleanup.sh   # PreToolUse hook: pre-exit cleanup + metadata save
  builtin-worktree-post-exit.sh # PostToolUse hook: registry update after exit

hooks/
  worktree-create.sh         # Programmatic create (invoked by Claude Code)
  worktree-detect.sh         # SessionStart: display WORKTREE_CONTEXT.md if present
  worktree-remove.sh         # Programmatic remove (invoked by Claude Code)

plugins/
  android-setup.sh           # Reference post-create setup hook (Android/Gradle)

share/
  gradle/worktree-cache.init.gradle.kts  # Gradle build-cache isolation per worktree

tests/
  test-wtx-config.sh         # Config loader I/O assertions
  test-wtx-dispatcher.sh     # bin/wtx dispatcher assertions
  test-worktree-registry.sh  # Registry helper assertions
  fixtures/                  # TOML + legacy .worktree-projects test fixtures
```

---

## Layer Architecture

### Layer 1 — Config (`lib/wtx-config.sh`)

The base layer. Loaded by every other component via `source ... || true`. Provides:

| Function | Purpose |
|---|---|
| `wtx_config_get "section.key" [default]` | Read a scalar from wtx.toml |
| `wtx_config_get_list "section.key"` | Read an array (newline-separated output) |
| `wtx_detect_project <dir>` | Walk up from `<dir>` to find a project root |

**Resolution order** (first hit wins):
1. `$WTX_CONFIG` env var (explicit path — used by tests/CI)
2. `$WORKSPACE_ROOT/wtx.toml` (repo-local, normal case)
3. `$HOME/.config/wtx/config.toml` (user global)

**Backward compat**: falls back to `$WORKSPACE_ROOT/.worktree-projects` (legacy format) for `projects.list` and `jira.projects.<repo>` when no TOML is found.

**Safety properties**:
- `bash 3.2` compatible (no `declare -A`, no `readarray`)
- Pure `awk`/`sed` — no external TOML parsers
- Idempotent: guarded by `_WTX_CONFIG_LOADED`
- Never `eval`s user-supplied content

---

### Layer 2 — TUI + Registry (`lib/worktree-tui.sh`)

Provides interactive UI primitives and the worktree registry. All `tui_*` functions degrade gracefully when `gum` is absent.

**TUI functions**:
| Function | Purpose |
|---|---|
| `tui_choose [--selected val] "prompt" items...` | Select one from a list |
| `tui_confirm "prompt" [default_yes]` | Yes/No prompt |
| `tui_input "prompt" [default] [placeholder]` | Free-text input |
| `tui_filter "prompt" "newline-list"` | Filterable list (gum filter fallback: select) |
| `tui_spin "message" cmd args...` | Spinner while running a command |
| `tui_style_box "line1" "line2"...` | Bordered box output |
| `tui_abort_check <rc>` | Exit cleanly on gum Esc/Ctrl+C (rc=130) |

**Tool detection** (cached per session):
- `has_gum` → checks `command -v gum`
- `has_claude` → checks `command -v claude`
- `claude_supports_positional_prompt` → inspects `claude --help` output
- `claude_supports_message_flag` → inspects `claude --help` output

**Registry** (`update_registry add|remove|refresh`):
- Markdown file at `$WORKSPACE_ROOT/.claude/worktree-registry.md`
- Path is config-driven via `worktree.registry_path`
- Atomic writes via `mktemp` + `mv`
- `add`: upserts entry under `## Active Worktrees`
- `remove`: moves entry to `## Recently Closed` (keeps last 10)
- `refresh`: updates commit counts and timestamps for active entries

**Other utilities**:
- `get_known_projects` → reads `projects.list` from config
- `run_with_timeout <secs> cmd` → wraps `timeout`/`gtimeout` with a bash-native fallback
- `open_url <url>` → `open` on macOS, `xdg-open` on Linux

---

### Layer 3 — API (`lib/worktree-api.sh`)

Direct REST API layer. curl-first approach using credentials from `$WORKSPACE_ROOT/.mcp.json` (same file the MCP servers use). All functions return `1` on failure to enable MCP fallback.

**Credential loading** (lazy, cached in session):
- Reads from `.mcp.json` → `mcpServers.jira_confluence.env` and `mcpServers.bitbucket.env`
- Required fields: `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`, `ATLASSIAN_USER_EMAIL`, `ATLASSIAN_API_TOKEN`
- `has_api_credentials` → returns 0 when loaded successfully

**Jira API functions**:
| Function | Returns |
|---|---|
| `api_jira_search <jql> <max> <fields>` | Raw JSON body |
| `api_jira_get_issue <PROJ-1234> <fields>` | Raw JSON body |
| `api_jira_my_tickets <PROJ_KEY>` | Newline-separated `[★] KEY \| Title \| Status` lines |
| `api_jira_ticket_details <PROJ-1234>` | Eval-safe `VAR='val';` line (whitelist-validated) |

**Bitbucket API functions**:
| Function | Returns |
|---|---|
| `api_bb_find_pr <repo> <branch>` | `PR_TITLE: …\tPR_URL: …\tPR_STATE: …` or empty |
| `api_bb_check_open_prs <repo> <ticket>` | `PR: <title> (<url>)` lines or empty |

**Eval safety** on `api_jira_ticket_details`: Python3 whitelist-validates the output against `^([A-Z_]+='[^']*';\s*)+$` before any caller evals it.

---

### Layer 4 — Jira Integration (`lib/worktree-jira.sh`)

Dual-path pattern: **curl for data** → **claude for reasoning**. Falls back to full MCP call if curl fails.

**Key functions**:

| Function | Description |
|---|---|
| `jira_fetch_my_tickets <PROJ_KEY>` | Fetch ticket list (curl → MCP fallback) |
| `jira_get_ticket_summary <PROJ-1234>` | Fetch title/status/description |
| `jira_analyze_ticket <PROJ-1234> <repo>` | curl data + AI reasoning → 8 vars (SUGGEST_* + TICKET_*) |
| `jira_suggest_branch <PROJ-1234> <repo>` | Deprecated wrapper → calls `jira_analyze_ticket` |
| `jira_project_for_repo <repo>` | Reads `jira.projects.<repo>` from config |
| `check_duplicate_work <ticket> <proj_dir>` | Local worktrees + open PRs for ticket |
| `check_existing_pr <branch> <repo>` | Find existing PR for branch |
| `check_ac_completion <wt_path> <base> <branch>` | AI advisory: unaddressed ACs |

**`jira_analyze_ticket` output format** (eval-safe single line):
```
SUGGEST_PREFIX='feature'; SUGGEST_BASE='develop'; SUGGEST_BRANCH_NAME='my-feature'; SUGGEST_SUMMARY='...';
TICKET_TITLE='...'; TICKET_STATUS='In Progress'; TICKET_DESCRIPTION='...'; TICKET_ACS='- [ ] AC1\n- [ ] AC2';
```

**AI model**: `claude-haiku-4-5-20251001` by default. Override: `WORKTREE_AI_MODEL=...`  
**Speed env vars** (reduce startup from ~6s to ~3s for reasoning-only calls):  
`CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING=1 DISABLE_TELEMETRY=1`

---

### Layer 5 — Interactive Flow (`lib/worktree-interactive.sh`)

Extracted TUI flow for `worktree-start.sh`. Implements `interactive_start()` which drives a 6-step wizard:

1. **Project selection** — detect from pwd, or pick from configured list
2. **Ticket/name input** — fetch Jira tickets, filterable list → manual fallback
3. **Parallel fan-out** — duplicate detection + ticket analysis run concurrently (background PIDs)
4. **Base branch** — filterable list from `git branch -r`, AI suggestion pinned at top
5. **Branch prefix** — inferred from repo's existing branch namespace, AI suggestion first
6. **Confirmation** — styled summary box, final confirm

Sets global vars used by `worktree-start.sh`: `NAME`, `BASE_BRANCH`, `PROJECT_DIR`, `PROJECT_NAME`, `BRANCH`, `TICKET_ID`, `MODE`, `WORKTREE_PATH`, `CACHED_TICKET_*`.

---

### Layer 6 — Launch (`lib/worktree-launch.sh`)

Smart Claude Code launch menu. Inspects BMAD artifacts to pick the best `/bmad-*` command.

**`analyze_worktree <ticket> <branch> <workspace_root>`** decision tree:
1. No `_bmad/` directory → `just-open`
2. No `_bmad-output/implementation-artifacts/` → `quick-spec`
3. Matching `tech-spec-*.md` with `ready-for-dev`/`in-progress` status → `quick-dev|<spec_path>`
4. Matching `tech-spec-*.md` with `draft` status → `quick-spec|<spec_path>`
5. Sprint status YAML lookup → `code-review`, `dev-story`, `create-story`, or `none`
6. Default → `quick-spec`

**Mapped BMAD commands**: `/bmad-bmm-quick-dev`, `/bmad-bmm-dev-story`, `/bmad-bmm-create-story`, `/bmad-bmm-code-review`, `/bmad-bmm-quick-spec`

---

### Layer 7 — Warp (`lib/worktree-warp.sh`)

Optional Warp terminal integration. No-op when `~/.warp` does not exist.

- `warp_emit_tab_config <wt_path> <project> <branch> [ticket]` — writes a 2-pane TOML (claude pane left, shell pane right)
- `warp_open_tab <wt_path>` — opens a plain shell tab via `warp://` URI
- `warp_remove_tab_config <wt_path>` — deletes the TOML on worktree removal
- Tab config filenames are deterministic: `wt-<sanitized-basename>-<8-char-cksum-hash>.toml`

---

## Data Flows

### `wtx start` (interactive)

```
bin/wtx start
  → scripts/worktree-start.sh
      source: tui, api, launch, jira, warp, interactive
      interactive_start()
        detect_project() via wtx_detect_project()
        get_known_projects() via wtx_config_get_list("projects.list")
        jira_fetch_my_tickets() → curl → MCP fallback
        parallel: check_duplicate_work() + jira_analyze_ticket()
        tui_filter: branch list + prefix list
        tui_style_box: confirmation summary
      git worktree add
      wtx_config_get("worktree.setup_hook") → bash $SETUP_HOOK
      write WORKTREE_CONTEXT.md
      jira_fetch_ticket_context() (non-interactive mode)
      update_registry add
      warp_emit_tab_config + warp_open_tab
      smart_launch_menu → exec claude "..."
```

### `wtx done`

```
bin/wtx done
  → scripts/worktree-done.sh
      find_main_repo() via .git file
      git log --stat (work summary)
      check_ac_completion() → advisory AI review
      git push -u origin <branch>
      check_existing_pr() → show/open existing PR
        or: exec claude "/pr-write ..."
      git worktree remove
      warp_remove_tab_config
      update_registry remove
      _wtx_build_pr_url() → forge-aware URL
      open_url() → browser
      git branch -D
```

### `wtx status`

```
bin/wtx status [project-dir]
  → scripts/worktree-status.sh
      collect_all_worktrees() → per-project git worktree list --porcelain
        compute_stale_divergence() per worktree
      display_worktrees() → unicode table
      interactive_menu()
        choices: select worktree → Open Claude Code | Remove | Rebase | Back
        Create new worktree → worktree-start.sh --no-exec
        Clean stale → WORKTREE_DONE_QUIET=1 worktree-done.sh
```

---

## Path Resolution Strategy

Every script resolves two critical variables using identical logic:

**`WTX_ROOT`** — the install directory of `wtx`:
- In `bin/wtx`: symlink-safe loop via `readlink`, resolves the real script directory
- In scripts: `: "${WTX_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"` (prefer dispatcher export)
- In hooks: self-resolve from `BASH_SOURCE[0]` using same symlink-safe loop

**`WORKSPACE_ROOT`** — the main repo root (not the worktree's path):
- Uses `git rev-parse --path-format=absolute --git-common-dir` (returns main `.git` dir in both main repo and linked worktrees)
- Falls back to `git rev-parse --show-toplevel` or `pwd`
- Critical: `--show-toplevel` would return the worktree path when invoked from inside a linked worktree — `--git-common-dir` always points to the main repo

---

## Hook System

Three hook integration points for Claude Code:

| Hook | Phase | Script | Purpose |
|---|---|---|---|
| SessionStart | on startup | `hooks/worktree-detect.sh` | Display `WORKTREE_CONTEXT.md` when in a worktree |
| PostToolUse (EnterWorktree) | after creating built-in worktree | `scripts/builtin-worktree-enhance.sh` | Setup + WORKTREE_CONTEXT.md + registry add |
| PreToolUse (ExitWorktree) | before removing built-in worktree | `scripts/builtin-worktree-cleanup.sh` | Save metadata + clean .build-cache |
| PostToolUse (ExitWorktree) | after removing built-in worktree | `scripts/builtin-worktree-post-exit.sh` | Registry remove if worktree gone |

The pre/post-exit pair uses a PPID-qualified temp file (`/tmp/.worktree-exit-metadata-<PPID>`) to pass metadata between phases within the same Claude session.

---

## Plugin System

`worktree.setup_hook` in `wtx.toml` specifies a script (relative to `$WTX_ROOT`) to run after every worktree creation. Called as `bash <hook> <wt_path> <project_dir>`.

`plugins/android-setup.sh` is the reference implementation:
1. Reads `$WORKSPACE_ROOT/.worktreeinclude` — copies listed files into the new worktree
2. Creates `.build-cache/` directory
3. Verifies `ANDROID_HOME` or `local.properties` SDK path
4. Appends `.build-cache/` and `WORKTREE_CONTEXT.md` to `.git/info/exclude`

---

## Two Worktree Types

| Type | Path Pattern | Created By | Registered |
|---|---|---|---|
| **Custom** | `<parent>/<project>-<name>/` | `wtx start` / `hooks/worktree-create.sh` | Yes (registry `add`) |
| **Built-in** | `<project>/.claude/worktrees/<name>/` | Claude Code `EnterWorktree` | Yes (via `builtin-worktree-enhance.sh`) |

Built-in worktrees are created and managed by Claude Code itself; `builtin-worktree-*.sh` scripts bridge the lifecycle back into the registry.

---

## Error Handling Convention

All scripts use `set -u` (undeclared variables are errors) but **never `set -e`**. Each operation:
- Validates inputs at entry, prints clear error, exits non-zero on hard failures
- Continues with graceful degradation on optional tooling (`gum`, `claude`, `timeout`, API credentials)
- Optional tooling is detected at call sites via `command -v` or `type -t`, never assumed present

---

## Gradle Build Cache Integration

`share/gradle/worktree-cache.init.gradle.kts` installs as `~/.gradle/init.d/worktree-cache.init.gradle.kts`. It detects whether `.git` is a file (worktree) or directory (main repo) and enables an isolated local Gradle build cache at `.build-cache/` only in worktrees. The remote cache is untouched.
