# wtx — git worktree management toolkit

`wtx` is a portable bash CLI for managing git worktrees across one or more
projects in a shared workspace. It provides TUI-guided flows for creating,
monitoring, and finalizing worktrees, with optional integrations for Jira,
Bitbucket/GitHub/GitLab, [Claude Code](https://claude.ai/code), and Warp
terminal.

```
wtx start PROJ-1234        # create feature/PROJ-1234 worktree, launch editor
wtx status                 # interactive dashboard across all open worktrees
wtx done                   # push, open PR, clean up the current worktree
```

## Requirements

| Tool | Status |
|---|---|
| `git` | **required** |
| `bash` 3.2+ | **required** (macOS-compatible) |
| `python3` | **required** (eval sanitization) |
| `curl` | **required** (Jira/forge API) |
| `gum` | optional — richer TUI; degrades gracefully to plain prompts |
| `claude` | optional — AI branch naming, ticket analysis |
| `timeout` | optional — guards network calls |
| `jq` | optional — faster JSON parsing |

Run `wtx doctor` after install to see what's present.

## Install

`wtx` is a symlink-based install: the repo tree stays in place and
`bin/wtx` is linked onto your `PATH`. Upgrading is just `git pull`.

```bash
# Clone somewhere permanent
git clone https://github.com/your-org/wtx.git ~/.local/share/wtx
cd ~/.local/share/wtx

# Install (default prefix: ~/.local — creates ~/.local/bin/wtx)
./install.sh

# Or choose a custom prefix
./install.sh --prefix /usr/local

# Also install Claude Code lifecycle hooks into the current workspace
./install.sh --hooks

# Also install the Gradle worktree-cache init script (Android/Gradle workspaces)
./install.sh --gradle

# Dry-run to preview
./install.sh --dry-run

# Remove
./install.sh --uninstall
```

After install, add `~/.local/bin` to your `PATH` if it isn't already:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Then verify:

```bash
wtx doctor
```

## Quickstart

**1. Generate a config file in your workspace:**

```bash
cd /path/to/your/workspace
wtx init
```

This walks you through forge type, org, project list, and defaults, then
writes `wtx.toml` at the workspace root.

**2. Create a worktree:**

```bash
# Interactive TUI (picks project, prompts for ticket or name)
wtx start

# Ticket mode — fetches Jira summary, AI-suggests branch name
wtx start PROJ-1234

# Named mode — quick, no Jira lookup
wtx start my-feature

# Explicit: ticket, base branch, project dir
wtx start PROJ-1234 main my-repo
```

The worktree is created as a sibling directory, the branch is created from
the base branch, and (if configured) your editor is launched automatically.

**3. Check what's open:**

```bash
wtx status             # interactive dashboard
wtx status my-repo     # table view for one project
```

**4. Finish the work:**

```bash
# From inside the worktree (or with the worktree path as arg)
wtx done
```

`wtx done` summarizes your commits, pushes, opens a PR URL in the browser,
removes the worktree, and prunes the local branch.

## Subcommands

```
wtx start [TICKET|NAME] [BASE_BRANCH] [PROJECT_DIR]
wtx done  [WORKTREE_PATH]
wtx status [PROJECT_DIR]
wtx init
wtx doctor
wtx version
wtx help
```

| Command | Description |
|---|---|
| `start` | Create a worktree. Interactive by default; accepts a Jira ticket or free-form name. |
| `done` | Push, open PR, remove the worktree and prune the branch. |
| `status` | Dashboard across all known projects. Interactive menu (no args) or table view (project dir). |
| `init` | Interactive `wtx.toml` generator. Writes to `$WORKSPACE_ROOT/wtx.toml`. |
| `doctor` | Check required/optional dependencies and install invariants. |
| `version` | Print the wtx version. |
| `help` | Print usage summary. |

## Configuration

Copy `wtx.example.toml` to `wtx.toml` at your workspace root (or run
`wtx init`). Config resolution order — first match wins:

1. `$WTX_CONFIG` (explicit path — for tests and CI)
2. `$WORKSPACE_ROOT/wtx.toml` (repo-local, normal case)
3. `$HOME/.config/wtx/config.toml` (user global)

### Full schema

```toml
[forge]
# bitbucket | github | gitlab — drives PR URL construction in `wtx done`
type = "github"

# Org/owner slug used for API calls and PR URLs
org = "your-org"

# Optional: override for self-hosted forges
# base_url = "https://gitlab.mycompany.internal"


[jira.projects]
# Map repo-name = "JIRA-KEY" for each project that uses Jira.
# Repos without an entry skip Jira integration entirely.
# my-repo = "PROJ"


[projects]
# Known project dirs relative to workspace root.
# Powers the TUI project picker in `wtx start`.
# Empty list → picker prompts the user to type a path.
list = ["my-repo", "another-repo"]


[detection]
# Root markers for project detection.
# A directory containing .git and any listed marker is a project root.
# Leave unset → any .git directory qualifies.
# markers = ["settings.gradle", "settings.gradle.kts"]  # Gradle/Android
# markers = ["Cargo.toml"]                               # Rust
# markers = ["package.json"]                             # Node.js


[worktree]
registry_path = ".claude/worktree-registry.md"
builtin_path  = ".claude/worktrees"

# Optional post-create setup hook (relative to $WTX_ROOT).
# See plugins/android-setup.sh for an example.
# setup_hook = "plugins/android-setup.sh"


[defaults]
base_branch   = "main"
branch_prefix = "feature"
```

### PR URL patterns

| Forge | URL pattern |
|---|---|
| `github` | `https://github.com/<org>/<repo>/compare/<branch>?expand=1` |
| `gitlab` | `https://gitlab.com/<org>/<repo>/-/merge_requests/new?merge_request[source_branch]=<branch>` |
| `bitbucket` | `https://bitbucket.org/<org>/<repo>/pull-requests/new?source=<branch>` |

### Backward compatibility

When no `wtx.toml` is found, the loader falls back to a legacy
`.worktree-projects` file at `$WORKSPACE_ROOT/.worktree-projects`:

```
# repo-name=JIRA-KEY
my-repo=PROJ
another-repo=
```

### Acme/Android workspace example

```toml
[forge]
type = "bitbucket"
org  = "acme"

[jira.projects]
web          = "PROJ"
mobile = "APP"

[projects]
list = ["web", "mobile", "backend"]

[detection]
markers = ["settings.gradle", "settings.gradle.kts"]

[worktree]
setup_hook = "plugins/android-setup.sh"

[defaults]
base_branch   = "develop"
branch_prefix = "feature"
```

## Architecture

```
┌─────────────┐
│   bin/wtx   │  dispatcher — resolves WTX_ROOT + WORKSPACE_ROOT, routes subcommands
└──────┬──────┘
       │ exec
       ▼
┌─────────────────────────────────────────────────────────────────┐
│  scripts/                                                       │
│    worktree-start.sh    create worktree (interactive/scripted)  │
│    worktree-done.sh     push, PR, remove worktree               │
│    worktree-status.sh   dashboard: list, manage, rebase         │
│    builtin-worktree-*   Claude Code built-in worktree helpers   │
└─────────────┬───────────────────────────────────────────────────┘
              │ source
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  lib/                                                           │
│    wtx-config.sh       flat-TOML loader, detect_project()      │
│    worktree-tui.sh     gum wrappers + bash fallbacks, registry  │
│    worktree-api.sh     curl-first REST (Jira + forge API)       │
│    worktree-jira.sh    Jira integration, branch suggestion      │
│    worktree-interactive.sh  shared interactive creation flow    │
│    worktree-launch.sh  Claude Code smart launch menu            │
│    worktree-warp.sh    Warp terminal 2-pane tab config          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  hooks/   (Claude Code lifecycle hooks)                         │
│    worktree-create.sh   PostToolUse: setup a new worktree       │
│    worktree-detect.sh   PreToolUse: display context on entry    │
│    worktree-remove.sh   PostToolUse: tear down a worktree       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  plugins/                                                       │
│    android-setup.sh     example setup_hook for Gradle/Android   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  share/gradle/                                                  │
│    worktree-cache.init.gradle.kts   Gradle build cache isolator │
└─────────────────────────────────────────────────────────────────┘
```

### Key design decisions

- **bash 3.2 compatible** — works with macOS's built-in bash without Homebrew.
- **Graceful degradation** — every optional tool (`gum`, `claude`, `jq`,
  `timeout`, Jira, Warp) is detected at call sites; missing tools skip that
  feature, never abort.
- **Inline stub fallbacks** — each script carries minimal stubs for the libs
  it needs, so scripts remain runnable even when `lib/` is missing.
- **`set -u` only, never `set -e`** — deliberate: optional code paths
  tolerate failure by convention, not exception.
- **No `eval` of raw input** — all `eval` sites are guarded by a whitelist
  regex and a python3 sanitizer pass.
- **Dual-path API** — `lib/worktree-api.sh` tries direct `curl` first (creds
  from `.mcp.json`); falls back to `claude -p` with MCP tools.
- **`--git-common-dir` for workspace root** — safe when `wtx` is invoked
  from inside a linked worktree (where `--show-toplevel` would return the
  worktree path, breaking registry lookups).

## API credentials (`.mcp.json`)

`wtx` reads Jira and forge credentials from `$WORKSPACE_ROOT/.mcp.json` —
the same file Claude Code uses for MCP servers. No separate credential file.

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

If `.mcp.json` is absent or incomplete, Jira integration is skipped and `wtx`
prompts for a free-form worktree name instead.

## Claude Code integration

Install the lifecycle hooks with `./install.sh --hooks`. They wire three
events into your Claude Code workspace:

| Hook file | Event | What it does |
|---|---|---|
| `hooks/worktree-create.sh` | `PostToolUse: EnterWorktree` | Sets up a new built-in worktree, runs `setup_hook` if configured |
| `hooks/worktree-detect.sh` | session start | Displays current worktree context in the Claude Code sidebar |
| `hooks/worktree-remove.sh` | `PostToolUse: ExitWorktree` | Tears down a built-in worktree, updates the registry |

The registry (`wtx.toml: worktree.registry_path`, default
`.claude/worktree-registry.md`) is a Markdown file Claude Code can read to
understand the current set of open worktrees and their status.

## Running the tests

```bash
bash tests/test-wtx-config.sh        # config loader (26 cases)
bash tests/test-wtx-dispatcher.sh    # bin/wtx dispatcher (16 cases)
bash tests/test-worktree-registry.sh # registry helpers (19 cases)
```

Syntax check all sources:

```bash
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh
```

## FAQ

**Q: Do I need Claude Code or Claude AI to use wtx?**  
No. Claude integration is optional. `wtx start --no-exec` skips the editor
launch entirely, and every AI-assisted feature degrades to a prompt asking
for the same information manually.

**Q: What if I don't use Jira?**  
Leave `[jira.projects]` empty (or omit it). `wtx start` will ask for a
free-form worktree name instead of fetching a ticket.

**Q: Can I use wtx without a `wtx.toml`?**  
Yes. Without a config file, all features that require forge or Jira
credentials are skipped. You still get the full worktree create/done/status
flow. If you have a legacy `.worktree-projects` file, it is automatically
used as a fallback.

**Q: My forge is self-hosted. Is that supported?**  
Partial. Set `forge.base_url` to your instance URL. PR URL construction
uses the configured `base_url`; API calls to self-hosted Jira work via
`JIRA_URL` in `.mcp.json`. Self-hosted GitHub/GitLab/Bitbucket Server API
calls are not yet supported.

**Q: The TUI doesn't look great without `gum`. How do I install it?**  
`brew install gum` on macOS. `wtx` falls back to plain `read` prompts
without it, but `gum` adds fuzzy search, spinners, and color.

## License

[MIT](LICENSE) — © 2026 Juan Angel Trujillo Jimenez
