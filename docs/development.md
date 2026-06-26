# wtx — Development Guide

## Project Status

`wtx` is a portability overhaul of an internal tool extracted from the Acme Android monorepo. **Phases 1–4 are complete**; Phase 5 remains.

| Phase | Status | Description |
|---|---|---|
| 1 | ✅ Done | Config system (`lib/wtx-config.sh`, `wtx.example.toml`) |
| 2 | ✅ Done | De-hardcode all Acme-specific values |
| 3 | ✅ Done | `bin/wtx` dispatcher, `wtx init`, `wtx doctor` |
| 4 | ✅ Done | `install.sh` (prefix-based installer: `--prefix`, `--hooks`, `--gradle`, `--uninstall`) |
| 5 | 🔲 Pending | Full `README.md`, `LICENSE` file, final Polish |

See `PORTABILITY_PROMPT.md` for the complete specification of all phases.

---

## Getting Started

No build step, no package manager. Clone, then put `wtx` on your PATH — either
with the installer (symlinks `bin/wtx` into `~/.local/bin`):

```bash
git clone <repo> ~/wtx
~/wtx/install.sh    # symlink bin/wtx -> ~/.local/bin/wtx (override with --prefix)
```

or by adding `bin/` to your PATH directly:

```bash
git clone <repo> ~/wtx
export PATH="$HOME/wtx/bin:$PATH"
```

Then:

```bash
wtx doctor          # verify environment
wtx init            # generate wtx.toml in a workspace
wtx start           # create a worktree (interactive)
```

---

## Required Dependencies

| Tool | Reason |
|---|---|
| `bash 3.2+` | All scripts — macOS default (important: no `declare -A`, no `readarray`) |
| `git` | All worktree operations |
| `python3` | JSON parsing, eval-payload sanitization, URL encoding |
| `curl` | Jira and Bitbucket REST API calls |

## Optional Dependencies

| Tool | Provides |
|---|---|
| `gum` | Rich TUI (filterable lists, spinners, styled boxes). Install: `brew install gum` |
| `claude` | AI branch suggestions, PR generation, MCP fallback. Install: `npm install -g @anthropic-ai/claude-code` |
| `timeout` / `gtimeout` | Timeout wrapper for AI calls. `run_with_timeout` has a bash-native fallback. |
| `jq` | Not currently used internally (future use / user convenience) |

---

## Running Tests

```bash
# Config loader tests
bash tests/test-wtx-config.sh

# Dispatcher tests
bash tests/test-wtx-dispatcher.sh

# Registry helper tests
bash tests/test-worktree-registry.sh

# Syntax check all shell files (catches parse errors)
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh
```

Tests use the `WTX_CONFIG` + `WORKSPACE_ROOT` override mechanism to run in isolation with fixture files. No network access required.

### Writing New Tests

Pattern for config loader tests:
```bash
# Always unset loader state between cases
unset _WTX_CONFIG_LOADED
source "$REPO_ROOT/lib/wtx-config.sh"

# Override per case
out=$(WTX_CONFIG="$FIXTURES/my.toml" WORKSPACE_ROOT="" wtx_config_get "section.key")
assert_eq "my test case" "expected" "$out"
```

---

## Code Conventions

### Error Handling
- `set -u` only in all scripts — undeclared variables are errors
- **Never** `set -e`
- Validate inputs at the top of each script/function; `exit 1` with a clear message on hard failure
- Optional integrations (`gum`, `claude`, API credentials): detect at call site, degrade gracefully

### Bash Compatibility (3.2)
The macOS default bash is 3.2. Avoid:
- `declare -A` (associative arrays)
- `readarray` / `mapfile`
- `printf '%q'` with non-ASCII
- Process substitution in `while` loops that modify outer vars (subshell scoping)

Use instead:
- Parallel arrays (same index = same entry)
- `while IFS= read -r line; done <<< "$multiline_var"`
- Temp files for capturing background process output

### Eval Safety
The codebase `eval`s structured output from `jira_analyze_ticket` and `api_jira_ticket_details`. Both:
1. Use Python3 to sanitize the output (strips `'`, `$`, backticks, newlines)
2. Construct a predictable `VAR='val';` format
3. Validate against the whitelist regex `^([A-Z_]+='[^']*';\s*)+$` before the caller can eval

Always call `_jira_validate_eval "$result"` before `eval "$result"`.

### No External Parsers
The config loader uses only `awk` and `sed` — no `python3`, no `jq`, no `tomlq`. This is intentional for portability. The TOML schema is flat by design.

### Inline Stub Fallbacks
Every script that sources a lib file has an inline fallback block:
```bash
source "$WTX_ROOT/lib/some-lib.sh" 2>/dev/null || {
    some_function() { echo "stub behavior"; }
    other_function() { return 1; }
}
```
These stubs keep scripts runnable even when the install is incomplete. When adding new exported functions to a lib, add a stub to every script that sources it.

---

## Adding a New Config Key

1. Add the key to `wtx.example.toml` with inline documentation
2. Update the schema in `docs/configuration.md`
3. Read via `wtx_config_get "section.key" "sensible-default"` at the call site
4. The config loader handles it automatically — no changes to `lib/wtx-config.sh` needed for flat scalar or array keys

---

## Adding a New Subcommand

1. Create `scripts/worktree-<name>.sh` (follow existing script conventions)
2. Add a `<name>)` case in `bin/wtx`'s dispatcher:
   ```bash
   mycommand)
       _wtx_exec_script "worktree-mycommand.sh" "$@"
       ;;
   ```
3. Add inline stub fallbacks for all lib functions the script uses
4. Update `docs/commands.md`

---

## Adding a Setup Hook Plugin

1. Create `plugins/<name>-setup.sh`
2. It receives: `$1 = <worktree-path>`, `$2 = <source-project-path>`
3. Use `/dev/tty` for progress messages (not stdout, which may be consumed by callers)
4. Document in `wtx.example.toml` under `# setup_hook = "plugins/<name>-setup.sh"`

Reference: `plugins/android-setup.sh`.

---

## Portability Rules (Active Until Phase 5)

When editing any script:
- **Do not add new hardcoded values** (org names, project names, Jira keys, branch names, file paths)
- If you find an existing hardcode, fix it:
  1. Add a field to `wtx.example.toml`
  2. Read via `wtx_config_get` with a sensible default
  3. Update call sites
- Already config-driven: Jira project keys, forge org, forge type, project list, detection markers, base branch, branch prefix, registry path, setup hook

---

## Commit Convention

```
ACTION(wtx): descriptive message
```

Actions: `feat`, `fix`, `refactor`, `test`, `chore`

Examples:
```
feat(wtx): add wtx status --json output format
fix(wtx): guard branch deletion when checked out in another worktree
refactor(wtx): extract PR URL builder to lib/worktree-api.sh
test(wtx): add config loader case for CRLF line endings
chore(wtx): add LICENSE (MIT)
```

No co-author footers. Never push without asking.

---

## Testing a Change End-to-End

```bash
# 1. Syntax check
bash -n bin/wtx lib/*.sh scripts/*.sh hooks/*.sh plugins/*.sh

# 2. Unit tests
bash tests/test-wtx-config.sh && bash tests/test-wtx-dispatcher.sh && bash tests/test-worktree-registry.sh

# 3. Environment check
wtx doctor

# 4. Interactive smoke test in a workspace
cd /path/to/your/git/workspace
WTX_ROOT=/path/to/wtx wtx start --no-exec
```
