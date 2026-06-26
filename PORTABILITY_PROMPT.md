# wtx Portability Overhaul — Session Prompt

You are working in the `wtx` repo — a standalone git worktree management tool extracted from a Acme monorepo. Your job is to make it fully portable and installable for any team, any git repo. Work in phases. After each phase, run `bash -n` on all `.sh` files, show `git diff --stat`, and wait for my approval before committing or proceeding.

## Repo Context

**Location:** `/Users/juanangeltrujillo/Library/Mobile Documents/com~apple~CloudDocs/PROJECTS/wtx`
**State:** 1 commit on `main`, 20 files (~162KB), clean tree.
**Structure:**
```
bin/wtx                          # Empty dispatcher stub
install.sh                       # Stub
wtx.example.toml                 # Stub (1 line)
scripts/
  worktree-start.sh              # Main TUI flow — creates worktrees
  worktree-done.sh               # Cleanup flow — push, PR, remove
  worktree-status.sh             # Dashboard — list, manage, rebase
  android-worktree-setup.sh      # Android-specific post-create setup
lib/
  worktree-tui.sh                # gum wrappers + bash fallbacks + registry
  worktree-api.sh                # curl-first Jira/Bitbucket REST calls
  worktree-jira.sh               # Jira integration + AI branch suggestion
  worktree-interactive.sh        # Interactive creation flow (extracted)
  worktree-launch.sh             # BMAD-aware Claude Code launch menu
  worktree-warp.sh               # Warp terminal 2-pane tab configs
hooks/
  worktree-create.sh             # Programmatic create (Claude hook)
  worktree-detect.sh             # Session-start context display
  worktree-remove.sh             # Programmatic remove (Claude hook)
share/gradle/
  worktree-cache.init.gradle.kts # Gradle build cache isolation
```

**Key architecture traits to PRESERVE:**
- Dual-path API: curl-first (creds from `.mcp.json`), MCP fallback via `claude -p`
- Graceful degradation: works without gum, claude, Warp, Jira
- Eval safety: whitelist regex + python3 sanitization on all eval sites
- Two worktree types: custom (sibling dirs) and built-in (`.claude/worktrees/`)
- Inline stub fallbacks when libs fail to source (every script has them)
- bash 3.2 compatible (macOS default)

## The 10 Hardcoding Blockers — Exact Locations

1. **`BITBUCKET_ORG` default = `acme`** — `lib/worktree-api.sh:12`, `lib/worktree-jira.sh:15`. Must come from config.
2. **PR URL = `https://bitbucket.org/acme/$REPO/...`** — `scripts/worktree-done.sh:422`. Must be forge-aware (Bitbucket/GitHub/GitLab).
3. **Project list fallback = `web`, `mobile`, `backend`** — `lib/worktree-tui.sh:55-57,65-67`, inline stubs in `worktree-start.sh:36`, `worktree-done.sh:32`, `worktree-status.sh:28`. Must come from config only; no hardcoded project names.
4. **Jira key map fallback = `web->PROJ`, `mobile->APP`** — `lib/worktree-jira.sh:446-447,461-462`, `worktree-start.sh:73`. Config-driven only.
5. **Example placeholder `PROJ-1234`** — `lib/worktree-interactive.sh:85,95` and help text. Replace with `PROJ-1234`.
6. **Example slug `example-feature-screen`** — `lib/worktree-jira.sh:230,328`. Replace with a generic example like `user-login-screen`.
7. **`detect_project()` uses `settings.gradle(.kts)` as root marker** — duplicated in `worktree-start.sh`, `worktree-done.sh`, `worktree-status.sh`, `hooks/worktree-create.sh`. Must be configurable (support any project type via config markers like `Cargo.toml`, `package.json`, `.git` alone, etc.).
8. **`android-worktree-setup.sh`** called unconditionally in `worktree-start.sh` and `hooks/worktree-create.sh`. Must become a plugin (run `setup_hook` from config, default to no-op, Android setup as an opt-in example).
9. **`.claude/` path assumptions** for registry — `lib/worktree-tui.sh` registry functions. Registry path should be configurable via `wtx.toml`; default `.claude/worktree-registry.md` is fine for Claude Code users.
10. **Stubs need implementation** — `bin/wtx`, `install.sh`, `wtx.example.toml`.

## Phase 1: Configuration System

Create `lib/wtx-config.sh` — a config loader sourced by all scripts.

### Config resolution order (first wins):
1. `$WTX_CONFIG` env var (explicit path)
2. `$WORKSPACE_ROOT/wtx.toml` (repo-local)
3. `$HOME/.config/wtx/config.toml` (user global)

### `wtx.toml` schema (implement a parser using awk/sed/grep — no TOML library needed, flat keys only):
```toml
# wtx configuration
[forge]
type = "bitbucket"                    # bitbucket | github | gitlab
org = "acme"                    # org/owner for API + PR URLs
# Optional: base_url for self-hosted (default: inferred from type)

[jira]
# project_key mappings: repo_name = JIRA_KEY
[jira.projects]
web = "PROJ"
mobile = "APP"

[projects]
# Known project directories (relative to workspace root)
list = ["web", "mobile", "backend"]

[detection]
# Root markers for detect_project() — if ANY of these exist, it's a project root
markers = ["settings.gradle", "settings.gradle.kts"]

[worktree]
registry_path = ".claude/worktree-registry.md"
builtin_path = ".claude/worktrees"
# setup_hook: script to run after worktree creation (relative to wtx install dir)
# setup_hook = "plugins/android-setup.sh"

[defaults]
base_branch = "develop"
branch_prefix = "feature"
```

### Requirements:
- `wtx_config_get "forge.org"` returns value or empty string
- `wtx_config_get "forge.org" "mydefault"` returns value or default
- `wtx_config_get_list "projects.list"` returns newline-separated values
- Fall back to `.worktree-projects` for project list + Jira keys (backward compat)
- All scripts source this at the top; stubs remain as final fallback if config not found
- Generate `wtx.example.toml` with all fields documented

## Phase 2: De-hardcode

Replace every Acme-specific reference with config reads. Specific changes:

1. `BITBUCKET_ORG` in api.sh and jira.sh: `BITBUCKET_ORG="${BITBUCKET_ORG:-$(wtx_config_get "forge.org")}"` — empty if not configured.
2. PR URL in done.sh: build URL dynamically based on `forge.type`:
   - `bitbucket`: `https://bitbucket.org/$org/$repo/pull-requests/new?source=$branch`
   - `github`: `https://github.com/$org/$repo/compare/$branch?expand=1`
   - `gitlab`: `https://gitlab.com/$org/$repo/-/merge_requests/new?merge_request[source_branch]=$branch`
3. `get_known_projects()` in tui.sh: read from config, fallback to `.worktree-projects`, then empty list (no hardcoded names).
4. `jira_project_for_repo()` in jira.sh: read from config `jira.projects.$repo`, fallback to `.worktree-projects`, then empty (no hardcoded map).
5. Inline stub fallbacks in start/done/status scripts: `get_known_projects()` stubs must NOT contain `web`/`mobile`/`backend` — return empty instead.
6. `jira_project_for_repo()` stubs: return empty, not hardcoded keys.
7. Placeholder text: `PROJ-1234` -> `PROJ-1234` in interactive.sh and help text.
8. Example slug: `example-feature-screen` -> `user-login-screen` in jira.sh.
9. `detect_project()`: read markers from config `detection.markers`; default to `.git` only (any git repo). Consolidate into a single function in `lib/wtx-config.sh` and source it everywhere — eliminate the 4 duplicates.
10. Setup hook: replace hard-coded `android-worktree-setup.sh` call with: `setup_hook=$(wtx_config_get "worktree.setup_hook")` and run it if set. Move `android-worktree-setup.sh` to `plugins/android-setup.sh`. Same for the hook in `hooks/worktree-create.sh`.

## Phase 3: Dispatcher (`bin/wtx`)

Implement `bin/wtx` as a subcommand router:

```
wtx start [args...]     -> scripts/worktree-start.sh
wtx done [args...]      -> scripts/worktree-done.sh
wtx status [args...]    -> scripts/worktree-status.sh
wtx init                -> interactive wtx.toml generator
wtx doctor              -> check deps (git, bash, python3, curl; optional: gum, claude, timeout)
wtx version             -> print version from VERSION file or embedded string
wtx help | --help | -h  -> usage summary
```

Key details:
- Resolve `WTX_ROOT` (where wtx is installed) from the script's own location
- Set `WORKSPACE_ROOT` to the git repo root (or cwd if not in a git repo)
- Export both for child scripts
- `wtx init`: interactively build `wtx.toml` — ask forge type, org, project list, detection markers. Write to `$WORKSPACE_ROOT/wtx.toml`.
- `wtx doctor`: check each dependency, print green/red status, warn about missing optionals.

## Phase 4: Installer (`install.sh`)

```bash
install.sh [--prefix PATH] [--uninstall]
```

- Default prefix: `$HOME/.local` (symlinks `bin/wtx` to `$prefix/bin/wtx`)
- `--hooks`: also install Claude Code hooks to `$PWD/.claude/hooks/`
- `--gradle`: copy `share/gradle/worktree-cache.init.gradle.kts` to `~/.gradle/init.d/`
- `--uninstall`: remove symlink, print what else to clean up
- Print post-install checklist: ensure `$prefix/bin` is in PATH, run `wtx doctor`

## Phase 5: Polish

- Write `README.md` with: overview, install, quickstart, config reference, architecture diagram (ASCII), FAQ
- Add a `LICENSE` file — ask me which license before creating
- `bash -n` all `.sh` files
- Verify the tool would still work inside the Acme workspace (a `wtx.toml` with the Acme values should reproduce current behavior exactly)
- Final clean commit history with clear messages

## Commit Convention

```
ACTION(wtx): descriptive message
```
Actions: `feat`, `fix`, `refactor`, `test`, `chore`. No co-author footers. Never push without asking.

## Critical Constraints

- **Never break backward compat:** `.worktree-projects` must still work as a fallback
- **Preserve all architecture:** dual-path API, graceful degradation, eval safety, inline stubs
- **bash 3.2 compatible** (no `declare -A`, no `readarray`, etc.)
- **No external TOML parser** — the config is flat enough for awk/sed
- **Keep every existing feature working** — this is a refactor, not a rewrite
- After each phase: `bash -n *.sh` + `git diff --stat` + wait for my approval
