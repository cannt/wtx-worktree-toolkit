# wtx — Command Reference

## Dispatcher: `bin/wtx`

```
wtx <command> [args...]
```

All subcommands are dispatched by `bin/wtx`, which first resolves and exports:
- `WTX_ROOT` — the wtx install directory (symlink-safe, macOS-compatible)
- `WORKSPACE_ROOT` — the main repo root (via `--git-common-dir`, safe inside linked worktrees)

---

## `wtx start`

**Create a new git worktree.**

```bash
# Interactive (TUI-guided)
wtx start

# Ticket mode — creates feature/<PROJ-1234>
wtx start PROJ-1234

# Named mode — creates feature/perf-test
wtx start perf-test

# Named with explicit base branch and project
wtx start PROJ-1234 develop my-repo

# Print suggested claude command instead of launching it
wtx start --no-exec
```

**Flags**:
- `--no-exec` — skip `exec claude` at the end; print the command instead
- `--` — end of flags

**Arguments**:
1. `<name>` — ticket key (`PROJ-1234`) or free-form name (`perf-test`)
2. `[base-branch]` — default: `develop` (or `defaults.base_branch` from config)
3. `[project-dir]` — project directory path (relative to `WORKSPACE_ROOT` or absolute)

**Interactive flow**:
1. Auto-detect project from current directory, or pick from configured list
2. Fetch Jira tickets (if `jira.projects.<repo>` is configured and Claude is available)
3. Run duplicate detection and ticket analysis in parallel
4. Pick base branch from remote list (AI suggestion pinned at top)
5. Pick branch prefix (derived from existing repo branches; AI suggestion first)
6. Confirm summary box
7. `git worktree add`
8. Run `worktree.setup_hook` if configured
9. Write `WORKTREE_CONTEXT.md`
10. Update worktree registry
11. Emit Warp tab config (if Warp is installed)
12. `exec claude "<smart-prompt>"`

**Branch naming** (ticket mode): `<prefix>/<TICKET_ID>-<slug>`  
e.g. `feature/PROJ-1234-user-login-screen`

---

## `wtx done`

**Finalize, push, create PR, and remove a worktree.**

```bash
# Auto-detect worktree from current directory
wtx done

# By worktree name
wtx done PROJ-1234

# By full path
wtx done /path/to/worktree
```

**What it does**:
1. Resolve worktree path (from arg, name, built-in search, or pwd walk)
2. Verify it's a worktree (`.git` is a file)
3. Show work summary: commit count, diff stat
4. Run advisory AC completion check (requires `WORKTREE_CONTEXT.md` + AC section)
5. Warn about uncommitted changes
6. Offer push (`git push -u origin <branch>`)
7. Check for existing PR → show and optionally open in browser
8. Offer to generate PR description via `exec claude "/pr-write ..."`
9. Confirm removal
10. Clean `.build-cache/` if present
11. `git worktree remove`
12. Remove Warp tab config
13. Move registry entry to Recently Closed
14. Offer to open PR creation URL in browser
15. Offer local branch deletion

**Environment**:
- `WORKTREE_DONE_QUIET=1` — suppress all browser-open prompts (used by `wtx status` stale cleanup)

---

## `wtx status`

**Worktree dashboard — list, manage, and rebase.**

```bash
# Interactive dashboard across all known projects
wtx status

# Non-interactive table for a specific project
wtx status /path/to/project
wtx status my-repo
```

**Table columns**: Branch | Ticket | Changes | Last Commit  
**Stale indicator**: `(stale)` when last commit > 7 days ago  
**Divergence indicator**: `↓N` in Changes column when N commits behind base  
**Built-in indicator**: `[B]` suffix on branch name

**Interactive menu actions**:
- Select a worktree → submenu:
  - **Open Claude Code here** (exits dashboard) → `smart_launch_menu`
  - **Remove this worktree** → `wtx done` (quiet mode)
  - **Rebase on base branch** → `git rebase origin/<base>`
  - **Back**
- **Create new worktree** → `wtx start --no-exec`
- **Clean up N stale worktrees** → `wtx done` (quiet) for each stale entry
- **Exit**

---

## `wtx init`

**Generate `wtx.toml` interactively in the current workspace.**

```bash
wtx init
```

Requires an interactive terminal. Refuses to overwrite an existing `wtx.toml`.

Prompts:
1. Forge type (`bitbucket` / `github` / `gitlab`)
2. Forge org/owner
3. Known project dirs (comma-separated, optional)
4. Detection markers (comma-separated, default `.git`)
5. Default base branch (default `main`)
6. Default branch prefix (default `feature`)

Writes to `$WORKSPACE_ROOT/wtx.toml`.

---

## `wtx doctor`

**Check dependencies and install integrity.**

```bash
wtx doctor
```

Checks:
- **Required**: `git`, `bash`, `python3`, `curl`
- **Optional**: `gum`, `claude`, `timeout`, `jq`
- **Install files**: `lib/wtx-config.sh`, `scripts/worktree-{start,done,status}.sh`
- **Paths**: `WTX_ROOT`, `WORKSPACE_ROOT`, active config file

Exits 0 if all required dependencies and install files are present. Exits 1 otherwise.

---

## `wtx version`

```bash
wtx version   # or: wtx --version / wtx -V
```

Prints the version from `$WTX_ROOT/VERSION`, or `0.1.0-dev` if the file is absent. Output is trimmed and stripped of a leading `v`.

---

## `wtx help`

```bash
wtx help   # or: wtx --help / wtx -h / wtx (no args)
```

Prints usage summary. Shows current `WTX_ROOT` and `WORKSPACE_ROOT` values.

---

## Hooks (Non-Interactive, Claude Code Integration)

### `hooks/worktree-create.sh`

```bash
bash hooks/worktree-create.sh <name> [project-dir] [base-branch]
```

Programmatic create (no TUI). Called by Claude Code or scripts.

**stdout contract**: prints only the absolute worktree path on success.  
**stderr**: error messages.  
Progress messages go to `/dev/tty`.

### `hooks/worktree-detect.sh`

```bash
bash hooks/worktree-detect.sh
```

SessionStart hook. Prints `WORKTREE_CONTEXT.md` content and uncommitted change count when invoked inside a worktree directory.

### `hooks/worktree-remove.sh`

```bash
bash hooks/worktree-remove.sh <worktree-path>
```

Programmatic remove. Blocks if the worktree has uncommitted changes.  
**stdout**: removed path on success.

---

## Built-in Worktree Scripts

These are called automatically by Claude Code hooks:

### `scripts/builtin-worktree-enhance.sh`

```bash
bash scripts/builtin-worktree-enhance.sh [worktree-path] [project-dir] [--force]
```

PostToolUse (EnterWorktree). Runs setup hook, writes `WORKTREE_CONTEXT.md`, updates registry. Skips if `WORKTREE_CONTEXT.md` already exists (use `--force` to re-run).

### `scripts/builtin-worktree-cleanup.sh`

```bash
bash scripts/builtin-worktree-cleanup.sh [worktree-path]
```

PreToolUse (ExitWorktree). Reads the hook's JSON stdin to determine `action` (`keep` or `remove`). Saves metadata to a PPID-qualified temp file. Cleans `.build-cache/` only when action is `remove`.

### `scripts/builtin-worktree-post-exit.sh`

```bash
bash scripts/builtin-worktree-post-exit.sh
```

PostToolUse (ExitWorktree). Reads metadata saved by cleanup script. If the worktree directory is gone, moves its registry entry to Recently Closed.

---

## Running Tests

```bash
# Config loader test suite
bash tests/test-wtx-config.sh

# Dispatcher test suite
bash tests/test-wtx-dispatcher.sh

# Registry helper test suite
bash tests/test-worktree-registry.sh

# Syntax check all shell files
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh
```
