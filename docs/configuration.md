# wtx — Configuration Reference

## Config File Resolution

The config loader (`lib/wtx-config.sh`) searches for a config file in this order (first hit wins):

| Priority | Location | When used |
|---|---|---|
| 1 | `$WTX_CONFIG` (env var) | Explicit override — tests, CI, debugging |
| 2 | `$WORKSPACE_ROOT/wtx.toml` | Repo-local config — normal case |
| 3 | `$HOME/.config/wtx/config.toml` | User-global config |

If none is found, all `wtx_config_get` calls return empty strings or supplied defaults.

---

## Full Schema (`wtx.example.toml`)

```toml
# wtx configuration
# Copy to `wtx.toml` at your workspace root and edit.

[forge]
# Forge type drives PR URL construction.
# One of: bitbucket | github | gitlab
type = "bitbucket"

# Org / owner slug used for API calls and PR URL building.
org = "your-org"

# Optional: base_url for self-hosted forges. Leave unset for SaaS defaults.
# base_url = "https://bitbucket.mycompany.internal"


[jira.projects]
# Map repo_name = "JIRA_KEY" for each project that uses Jira.
# If a repo has no entry here, Jira integration is disabled for it.
# my-repo = "PROJ"
# another-repo = "ANOT"


[projects]
# Known project directories (relative to workspace root).
# These power the TUI project picker in wtx start.
# Empty list = the picker asks the user to type a path.
list = ["my-repo", "another-repo"]


[detection]
# Root markers used by wtx_detect_project().
# If ANY of these files exists in a directory that also has .git,
# wtx treats it as a project root.
# Leave unset to fall back to .git alone (any git repo).
# markers = ["settings.gradle", "settings.gradle.kts"]   # Gradle / Android
# markers = ["Cargo.toml"]                                # Rust
# markers = ["package.json"]                              # Node.js


[worktree]
# Where the registry file lives, relative to workspace root.
registry_path = ".claude/worktree-registry.md"

# Base directory for built-in worktrees (EnterWorktree type).
builtin_path = ".claude/worktrees"

# Optional post-create setup hook.
# Path relative to the wtx install directory ($WTX_ROOT).
# Run as: bash <hook> <worktree-path> <project-dir>
# See plugins/android-setup.sh for a reference implementation.
# setup_hook = "plugins/android-setup.sh"


[defaults]
# Default base branch when none is provided on the command line.
base_branch = "develop"

# Default branch prefix used when generating branch names from tickets.
branch_prefix = "feature"
```

---

## Section Reference

### `[forge]`

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | string | `""` | Forge type: `bitbucket`, `github`, or `gitlab`. Drives PR URL construction in `wtx done`. |
| `org` | string | `""` | Org/owner slug. Used in API calls and PR URLs. Empty = skip PR URL offer. |
| `base_url` | string | `""` | Optional: base URL for self-hosted forges. |

**PR URL patterns by forge type**:
- `bitbucket`: `https://bitbucket.org/<org>/<repo>/pull-requests/new?source=<branch>`
- `github`: `https://github.com/<org>/<repo>/compare/<branch>?expand=1`
- `gitlab`: `https://gitlab.com/<org>/<repo>/-/merge_requests/new?merge_request[source_branch]=<branch>`

---

### `[jira.projects]`

Dotted subtable mapping repository names to Jira project keys.

```toml
[jira.projects]
my-repo = "PROJ"
```

- Key: repository name (basename of `PROJECT_DIR`)
- Value: Jira project key (e.g., `PROJ`, `PROJ`)
- Used by `jira_project_for_repo()` in `lib/worktree-jira.sh`

When a repo has no entry here, Jira ticket fetching is skipped and the TUI asks for a free-form name instead.

---

### `[projects]`

| Key | Type | Default | Description |
|---|---|---|---|
| `list` | array of strings | `[]` | Known project directories relative to `WORKSPACE_ROOT`. Powers `get_known_projects()` and the interactive project picker in `wtx start`. |

---

### `[detection]`

| Key | Type | Default | Description |
|---|---|---|---|
| `markers` | array of strings | `[]` (→ `.git`-only) | Root-marker filenames. `wtx_detect_project()` requires both `.git` and at least one marker to be present in a candidate directory. |

When `markers` is empty or absent, any directory containing `.git` qualifies as a project root.

---

### `[worktree]`

| Key | Type | Default | Description |
|---|---|---|---|
| `registry_path` | string | `.claude/worktree-registry.md` | Registry file path, relative to `WORKSPACE_ROOT`. |
| `builtin_path` | string | `.claude/worktrees` | Base directory for built-in worktrees. |
| `setup_hook` | string | `""` | Post-create hook script, relative to `$WTX_ROOT`. |

---

### `[defaults]`

| Key | Type | Default | Description |
|---|---|---|---|
| `base_branch` | string | `develop` | Default base branch for `wtx start`. |
| `branch_prefix` | string | `feature` | Default branch prefix for generated branch names. |

---

## Backward Compatibility — `.worktree-projects`

When no `wtx.toml` is found, the config loader automatically falls back to a legacy `.worktree-projects` file at `$WORKSPACE_ROOT/.worktree-projects`.

**Legacy format**:
```
# comments allowed
web=PROJ
mobile=APP
backend=
```

- Lines: `<repo-name>=<JIRA-KEY>` (JIRA key optional)
- `wtx_config_get_list "projects.list"` → returns all repo names
- `wtx_config_get "jira.projects.<repo>"` → returns the Jira key

---

## Environment Variables

| Variable | Description |
|---|---|
| `WTX_ROOT` | Path to the wtx install directory. Set by `bin/wtx`; scripts fall back to self-resolving. |
| `WORKSPACE_ROOT` | Main repo root (not worktree path). Set by `bin/wtx`; scripts fall back to `git rev-parse --git-common-dir`. |
| `WTX_CONFIG` | Explicit config file path override. Takes priority over `WORKSPACE_ROOT/wtx.toml`. Useful for tests and CI. |
| `WORKTREE_JIRA_TIMEOUT` | Seconds to wait for Jira queries via `claude -p` (default: 20 for summary, 30 for analysis). |
| `WORKTREE_AI_MODEL` | Claude model for AI reasoning calls (default: `claude-haiku-4-5-20251001`). |
| `WORKTREE_DONE_QUIET` | Set to `1` to suppress browser-open prompts in `wtx done` (used by `wtx status`). |
| `BITBUCKET_ORG` | Overrides `forge.org` for Bitbucket API calls. |
| `CLAUDE_PROJECT_ROOT` | Used by Claude Code hooks to pass the workspace root when invoked inside a worktree. |

---

## API Credentials (`.mcp.json`)

`lib/worktree-api.sh` reads API credentials from `$WORKSPACE_ROOT/.mcp.json` — the same credentials file used by Claude Code MCP servers. This avoids maintaining a separate credential file.

Expected structure:
```json
{
  "mcpServers": {
    "jira_confluence": {
      "env": {
        "JIRA_URL": "https://yourcompany.atlassian.net",
        "JIRA_USERNAME": "you@example.com",
        "JIRA_API_TOKEN": "..."
      }
    },
    "bitbucket": {
      "env": {
        "ATLASSIAN_USER_EMAIL": "you@example.com",
        "ATLASSIAN_API_TOKEN": "..."
      }
    }
  }
}
```

Credentials are loaded lazily and cached for the duration of the process. If `.mcp.json` is missing or incomplete, the API layer returns failure (rc=1) and the Jira layer falls back to `claude -p` with MCP tools.

---

## Generating `wtx.toml` Interactively

```bash
cd /path/to/workspace
wtx init
```

Asks for:
1. Forge type (`bitbucket` / `github` / `gitlab`)
2. Forge org/owner slug
3. Known project dirs (comma-separated, optional)
4. Detection markers (comma-separated, default `.git`)
5. Default base branch (default `main`)
6. Default branch prefix (default `feature`)

Writes `$WORKSPACE_ROOT/wtx.toml`. Refuses to overwrite an existing file.
