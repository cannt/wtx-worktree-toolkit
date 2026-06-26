---
project: wtx
type: cli
language: bash
scan_level: exhaustive
generated: 2026-04-15
parts: 1
---

# wtx — Project Documentation Index

`wtx` is a bash CLI toolkit for managing git worktrees in a multi-project workspace. It provides interactive and scripted flows for creating, monitoring, and finalizing worktrees, with optional integrations for Jira, Bitbucket/GitHub/GitLab, Claude Code (AI), and Warp terminal.

**Status**: Portability overhaul in progress. Phases 1–4 complete (config system, de-hardcoding, dispatcher, installer). Phase 5 (full README/LICENSE) pending.

---

## Documentation

| Document | Description |
|---|---|
| [architecture.md](./architecture.md) | Full architecture: layers, data flows, path resolution, hook system |
| [commands.md](./commands.md) | All commands and flags: `wtx start`, `done`, `status`, `init`, `doctor`, `version` |
| [configuration.md](./configuration.md) | `wtx.toml` schema, env vars, API credentials, backward-compat `.worktree-projects` |
| [library-api.md](./library-api.md) | Library API reference for all `lib/*.sh` public functions |
| [development.md](./development.md) | Dev guide: running tests, code conventions, adding commands/plugins |

---

## Quick Reference

### Installation

```bash
git clone <repo> ~/wtx
~/wtx/install.sh        # symlink bin/wtx -> ~/.local/bin/wtx (override with --prefix)
wtx doctor              # verify (ensure ~/.local/bin is on your PATH)
```

`install.sh` flags: `--prefix PATH`, `--hooks` (Claude Code hooks into `$PWD/.claude/hooks/`), `--gradle` (Gradle build-cache init script → `~/.gradle/init.d/`), `--uninstall`, `--dry-run`. To skip the installer, add `bin/` to your PATH directly:

```bash
export PATH="$HOME/wtx/bin:$PATH"
```

### Key Commands

```bash
wtx start               # Create worktree (interactive TUI)
wtx start PROJ-1234     # Create worktree for Jira ticket
wtx done                # Finalize + push + PR + remove worktree
wtx status              # Dashboard across all projects
wtx init                # Generate wtx.toml
wtx doctor              # Check environment
```

### Minimal `wtx.toml`

```toml
[forge]
type = "github"
org = "your-org"

[jira.projects]
my-repo = "PROJ"

[projects]
list = ["my-repo"]

[defaults]
base_branch = "main"
```

---

## Architecture Summary

```
bin/wtx  ──────────────────────────────────────────────  dispatcher
   │
   ├─► scripts/worktree-start.sh   (create worktree)
   │       sources: tui, api, jira, interactive, launch, warp
   ├─► scripts/worktree-done.sh    (finalize worktree)
   │       sources: tui, api, jira, warp
   ├─► scripts/worktree-status.sh  (dashboard)
   │       sources: tui, launch
   ├─► wtx init    (inline in bin/wtx)
   ├─► wtx doctor  (inline in bin/wtx)
   └─► wtx version (inline in bin/wtx)

lib/
   wtx-config.sh          ← base: flat-TOML loader, project detection
   worktree-tui.sh         ← gum wrappers + registry
   worktree-api.sh         ← curl REST (Jira + Bitbucket)
   worktree-jira.sh        ← Jira integration + AI branch naming
   worktree-interactive.sh ← 6-step TUI wizard
   worktree-launch.sh      ← BMAD-aware Claude Code launch menu
   worktree-warp.sh        ← Warp terminal integration

hooks/                     ← Claude Code hook integrations
plugins/android-setup.sh   ← Reference post-create setup hook
```

---

## Technology Stack

| Category | Technology |
|---|---|
| Language | Bash 3.2+ (macOS compatible) |
| JSON parsing | Python 3 (stdlib only) |
| REST API | curl (Jira REST API v3, Bitbucket REST API 2.0) |
| TUI (optional) | `gum` (charmbracelet) |
| AI (optional) | `claude` CLI (Claude Code) |
| Timeout | `timeout`/`gtimeout` with bash-native fallback |
| Config format | Flat TOML (awk/sed parser, no external libs) |
| Test runner | Bash (no framework — plain `assert_eq` functions) |
| Build cache | Gradle (Kotlin DSL init script) |

---

## Key Design Properties

- **Graceful degradation**: works without `gum`, `claude`, `jq`, API credentials
- **Eval safety**: structured output is whitelist-validated by Python3 before any `eval`
- **bash 3.2 compatible**: no associative arrays, no `readarray`
- **No `set -e`**: manual error handling with clear messages
- **Config-driven**: all forge/project/Jira values from `wtx.toml`; no hardcoded org names
- **Dual-path API**: curl for data (fast), `claude -p` with MCP for fallback and AI reasoning
- **Inline stubs**: every `source` call has a fallback block so scripts run on broken installs
- **Atomic registry writes**: `mktemp` + `mv` prevents corruption
