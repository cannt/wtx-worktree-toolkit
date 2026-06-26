# wtx — Library API Reference

All library files live under `lib/`. They are sourced (not executed) by scripts. Each file self-sources `lib/wtx-config.sh` on load. All `source ... || true` patterns make the scripts resilient to a missing lib.

---

## `lib/wtx-config.sh`

**Source**: always first. Idempotent (guarded by `_WTX_CONFIG_LOADED`).

```bash
source "$WTX_ROOT/lib/wtx-config.sh"
```

### Public API

#### `wtx_config_get <key> [default]`
Read a scalar value from the active `wtx.toml`.

- `key`: dotted key, e.g. `"forge.org"`, `"jira.projects.my-repo"`, `"defaults.base_branch"`
- Returns value on stdout; returns `default` (or empty) when key is not found
- Falls back to `.worktree-projects` for `jira.projects.*` keys

```bash
org=$(wtx_config_get "forge.org" "fallback-org")
jira_key=$(wtx_config_get "jira.projects.my-repo")
```

#### `wtx_config_get_list <key>`
Read an array value. Returns one item per line.

```bash
while IFS= read -r project; do
    [[ -n "$project" ]] && echo "Project: $project"
done <<< "$(wtx_config_get_list "projects.list")"
```

Falls back to `.worktree-projects` names for `projects.list`.

#### `wtx_detect_project <dir>`
Walk up from `<dir>` to find a project root.

A directory qualifies when:
1. It contains `.git` (file or directory), AND
2. Either `detection.markers` is empty (accept any git repo), OR at least one listed marker file exists in that directory

Returns the absolute path on stdout; exits 1 if not found.

```bash
project_dir=$(wtx_detect_project "$(pwd)") || echo "Not in a project"
```

---

## `lib/worktree-tui.sh`

**Source**: after `wtx-config.sh`.

```bash
source "$WTX_ROOT/lib/worktree-tui.sh"
```

### Tool detection

```bash
has_gum        # returns 0 if gum is in PATH
has_claude     # returns 0 if claude is in PATH
claude_supports_positional_prompt   # returns 0 if `claude "prompt"` works
claude_supports_message_flag        # returns 0 if `claude --message` flag exists
```

All detection results are cached for the session.

### TUI primitives

```bash
# Select one item from a list. gum choose / bash select fallback.
choice=$(tui_choose "Select project:" "repo-a" "repo-b" "repo-c")
choice=$(tui_choose --selected "repo-b" "Select:" "repo-a" "repo-b" "repo-c")

# Yes/No confirmation. Returns 0 = yes, 1 = no.
tui_confirm "Create worktree?" && echo "confirmed"
tui_confirm "Really?" "yes"   # default=yes

# Free-text input.
name=$(tui_input "Branch name:" "feature/my-branch" "placeholder")

# Filterable list (multi-line string as second arg).
items="$(printf 'a\nb\nc')"
selection=$(tui_filter "Pick one:" "$items")

# Spinner while running a command. Captures stdout.
result=$(tui_spin "Fetching..." my_command arg1 arg2)

# Styled box.
tui_style_box "Line one" "Line two" "Line three"

# Abort check after gum calls.
val=$(tui_choose "Select:" "a" "b"); tui_abort_check $?
```

### Registry

```bash
# Add entry to Active Worktrees
update_registry add "$project" "$branch" "$base" "$path" "$name" ["builtin"]

# Move entry to Recently Closed (keeps last 10)
update_registry remove "$project" "$branch" ["$pr_url"] ["$result"] ["$wt_path"]

# Refresh Last Activity timestamps for all Active entries
update_registry refresh
```

### Utilities

```bash
# Open URL in default browser (macOS: open, Linux: xdg-open)
open_url "https://example.com"

# Run command with timeout. Returns 124 on timeout.
result=$(run_with_timeout 30 some_command args)

# Get configured project list (empty when nothing configured)
while IFS= read -r p; do [[ -n "$p" ]] && echo "$p"; done <<< "$(get_known_projects)"
```

---

## `lib/worktree-api.sh`

**Source**: after `wtx-config.sh`. Requires `WORKSPACE_ROOT` to be set.

```bash
source "$WTX_ROOT/lib/worktree-api.sh"
```

All `api_*` functions return `1` on failure; callers must check `$?`.

### Credential management

```bash
# Returns 0 if .mcp.json credentials loaded successfully
has_api_credentials && echo "API ready"
```

### Jira

```bash
# Search Jira (returns raw JSON body)
json=$(api_jira_search "project = PROJ AND status != Done" 10 "key,summary,status")

# Get a single issue (returns raw JSON body)
json=$(api_jira_get_issue "PROJ-1234" "summary,status,description")

# Get current user's tickets — formatted for display
# Returns: "★ KEY | Title | Status" (assigned) / "KEY | Title | Status" (unassigned)
tickets=$(api_jira_my_tickets "PROJ")

# Get ticket details — returns eval-safe assignment string
result=$(api_jira_ticket_details "PROJ-1234")
# Usage (always validate before eval):
if _jira_validate_eval "$result"; then
    local _API_TITLE="" _API_STATUS="" _API_DESCRIPTION="" _API_ISSUE_TYPE="" _API_FIX_VERSIONS="" _API_ACS=""
    eval "$result"
fi
```

### Bitbucket

```bash
# Find a PR for a branch (checks OPEN then MERGED)
# Returns: "PR_TITLE: ...\tPR_URL: ...\tPR_STATE: ..." or empty
pr_info=$(api_bb_find_pr "my-repo" "feature/PROJ-1234")

# Check for open PRs (duplicate detection)
# Returns: "PR: <title> (<url>)" lines or empty
pr_lines=$(api_bb_check_open_prs "my-repo" "PROJ-1234")
```

---

## `lib/worktree-jira.sh`

**Source**: after `worktree-tui.sh` and `worktree-api.sh`.

```bash
source "$WTX_ROOT/lib/worktree-jira.sh"
```

### Ticket fetching

```bash
# Fetch current user's tickets (curl → MCP fallback)
# Returns newline-separated "[★] KEY | Title | Status" lines
tickets=$(jira_fetch_my_tickets "PROJ")

# Get a ticket summary (curl → MCP fallback)
# Returns multi-line: TITLE: ... / STATUS: ... / DESCRIPTION: ...
summary=$(jira_get_ticket_summary "PROJ-1234")
```

### Ticket analysis

```bash
# Full analysis — sets SUGGEST_* and TICKET_* vars
# IMPORTANT: always validate before eval; never use `local` on the eval'd vars
result=$(jira_analyze_ticket "PROJ-1234" "my-repo")
if _jira_validate_eval "$result"; then
    SUGGEST_PREFIX="" SUGGEST_BASE="" SUGGEST_BRANCH_NAME="" SUGGEST_SUMMARY=""
    TICKET_TITLE="" TICKET_STATUS="" TICKET_DESCRIPTION="" TICKET_ACS=""
    eval "$result"
fi

# Deprecated: SUGGEST_* only
result=$(jira_suggest_branch "PROJ-1234" "my-repo")
```

### Project/repo helpers

```bash
# Map repo name to Jira key (reads jira.projects.<repo> from config)
key=$(jira_project_for_repo "my-repo")   # returns "PROJ" or ""
```

### Duplicate and AC checks

```bash
# Check for existing worktrees and open PRs for a ticket
# Returns "WORKTREE: <path>" and/or "PR: <title> (<url>)" lines
dupes=$(check_duplicate_work "PROJ-1234" "/path/to/project")

# Check for an existing PR for a specific branch
# Returns "PR_TITLE: ...\tPR_URL: ...\tPR_STATE: ..." or empty
pr=$(check_existing_pr "feature/PROJ-1234" "my-repo")

# Advisory AC check (requires WORKTREE_CONTEXT.md with AC section)
# Returns unaddressed "- [ ] AC" lines, "NONE" if all addressed, or empty
unaddressed=$(check_ac_completion "/wt/path" "develop" "feature/PROJ-1234")
```

---

## `lib/worktree-interactive.sh`

**Source**: after `worktree-tui.sh` and `worktree-jira.sh`. Also requires `detect_project` and `SCRIPT_DIR` to be defined.

```bash
source "$WTX_ROOT/lib/worktree-interactive.sh"
```

### `interactive_start()`

Runs the full 6-step TUI creation wizard. Sets global variables:
- `NAME`, `BASE_BRANCH`, `PROJECT_DIR`, `PROJECT_NAME`, `BRANCH`
- `TICKET_ID`, `MODE` (`"ticket"` or `"named"`)
- `WORKTREE_PATH`
- `CACHED_TICKET_TITLE`, `CACHED_TICKET_STATUS`, `CACHED_TICKET_DESCRIPTION`, `CACHED_TICKET_ACS`

Note: `CACHED_TICKET_*` must **not** be declared `local` by the caller — they need to persist after the function returns.

---

## `lib/worktree-launch.sh`

```bash
source "$WTX_ROOT/lib/worktree-launch.sh"
```

### `smart_launch_menu <wt_path> <ticket_id> <branch> <project_name> <workspace_root> <no_exec>`

Main entry point. Analyzes the worktree state, shows a menu, and `exec claude "..."`.

- `no_exec="true"`: prints suggested command, no menu shown
- `no_exec="false"`: interactive menu

```bash
smart_launch_menu "$WORKTREE_PATH" "$TICKET_ID" "$BRANCH" "$PROJECT_NAME" "$WORKSPACE_ROOT" "false"
```

### `analyze_worktree <ticket_id> <branch> <workspace_root>`

Lower-level: returns a suggestion string.

```bash
raw=$(analyze_worktree "PROJ-1234" "feature/PROJ-1234-screen" "$WORKSPACE_ROOT")
IFS='|' read -r suggestion artifact_path <<< "$raw"
# suggestion: quick-dev | dev-story | create-story | code-review | quick-spec | just-open
# artifact_path: path to matching tech-spec-*.md (may be empty)
```

---

## `lib/worktree-warp.sh`

```bash
source "$WTX_ROOT/lib/worktree-warp.sh"
```

All functions are no-ops when `~/.warp` does not exist.

```bash
warp_available && echo "Warp is installed"

# Emit 2-pane tab config (claude left, shell right)
warp_emit_tab_config "$WORKTREE_PATH" "$PROJECT_NAME" "$BRANCH" "$TICKET_ID"

# Get the deterministic config file path for a worktree
config_file=$(warp_tab_config_path "$WORKTREE_PATH")

# Open a Warp shell tab at the worktree path
warp_open_tab "$WORKTREE_PATH"

# Delete the tab config on worktree removal
warp_remove_tab_config "$WORKTREE_PATH"
```
