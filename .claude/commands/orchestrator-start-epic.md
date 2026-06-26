# Orchestrator: Start Epic

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<sprint-summary>
!`bash -c 'source scripts/bmad-dev-loop/lib/bdl-orchestrator-precompute.sh 2>/dev/null && sprint_status_summary "_bmad-output/implementation-artifacts/sprint-status.yaml"' 2>/dev/null || echo "summary unavailable"`
</sprint-summary>

State and sprint summary are pre-loaded above. Use state to check for existing epic state conflicts before initialization.

## Arguments

Parse `$ARGUMENTS` for:
- **Epic ID** (required) — e.g., `bdl-2`
- **`--no-opencode`** (optional) — if present, set `use_opencode=false` in state (forces Claude-only validation)
- **`--mode {value}`** (optional) — orchestration mode: `claude-all`, `claude+codex`, `claude+opencode`, `opencode-all`, `opencode+claude`. Defaults to env `$ORCHESTRATION_MODE` or `claude+codex`

If no epic ID is provided, HALT: "Usage: /orchestrator-start-epic {epic-id} [--no-opencode]"

## Pre-flight Check

Before starting, verify the orchestrator is running inside tmux. This is REQUIRED for Telegram live interaction:

```bash
if [[ -z "${TMUX:-}" ]]; then
    echo "⚠️  Orchestrator must run inside tmux for Telegram live interaction."
    echo ""
    echo "Start it with:"
    echo "  tmux -L orchestrator new-session -s bmad-orchestrator -c $PWD"
    echo "  claude --dangerously-skip-permissions"
    echo "  /orchestrator-start-epic {epic-id}"
    echo ""
    echo "Or if you don't need Telegram interaction, continue anyway."
fi
```

If NOT in tmux, warn the user but allow them to continue (Telegram will fall back to signal files instead of live delivery).

## Startup

1. Run `caffeinate -i &` to prevent system sleep (or use `start_caffeinate` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh`)
2. Set environment: `export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70`
3. Source model resolver: `source scripts/bmad-dev-loop/lib/bmad-model-resolver.sh`
4. Source session profiler: `source scripts/bmad-dev-loop/lib/bmad-session-profiler.sh`
5. Read command prefix:
```bash
CMD_PREFIX=$(grep 'command_prefix:' scripts/bmad-dev-loop/bdl-config.yaml 2>/dev/null | awk '{print $2}' | tr -d '" \t')
export CMD_PREFIX="${CMD_PREFIX:-bmad}"
```
6. Source state lib and clear stale signals: `source scripts/bmad-dev-loop/lib/bmad-state.sh && mkdir -p "$SIGNAL_DIR" && find "$SIGNAL_DIR" -maxdepth 1 -type f -delete 2>/dev/null`
7. Export schema path: `export SPRINT_STATUS_SCHEMA="$STATE_DIR/sprint-status-schema.json"`
8. Start the monitor in a tmux session (MANDATORY — monitors worker sessions for HALTs, stalls, auto-dismiss):

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-tmux.sh && ensure_server && kill_session "bmad-monitor" 2>/dev/null'
tmux -L orchestrator new-session -d -s bmad-monitor -c "$PWD"
tmux -L orchestrator send-keys -t bmad-monitor "bash scripts/bmad-dev-loop/bmad-monitor.sh --poll-interval 15" Enter
```

## Initialize State

**External tool detection:** Run `which opencode` and `which codex` to check available tools. The `use_opencode` field is a legacy compatibility flag; the authoritative setting is `orchestration_mode` (default: `claude+codex`). If `--no-opencode` is in `$ARGUMENTS`, set `use_opencode=false` to force Claude-only validation.

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh

# Auto-clear stale state from a different epic
if [[ -f "$STATE_FILE" ]]; then
    existing_epic=$(STATE_FILE="$STATE_FILE" python3 -c "import json, os; print(json.load(open(os.environ[\"STATE_FILE\"])).get(\"epic_id\",\"\"))" 2>/dev/null)
    if [[ -n "$existing_epic" && "$existing_epic" != "{epic_id}" ]]; then
        clear_state
    fi
fi

# Detect external tool installation (legacy field — orchestration_mode is authoritative)
use_opencode="false"
if which opencode >/dev/null 2>&1 || which codex >/dev/null 2>&1; then
    use_opencode="true"
fi
# --no-opencode flag in $ARGUMENTS overrides tool detection — substitute "true" if flag was present
[[ "{no_opencode}" == "true" ]] && use_opencode="false"

init_state "{epic_id}" "$(basename "$PWD")" "$use_opencode"

# Store orchestration mode — from --mode flag, env $ORCHESTRATION_MODE, or default claude+codex
update_state "orchestration_mode" "{mode}"
'
```

**Important:** The `project_folder` argument is informational only (auto-detected from directory name). Workers must always be launched in `$PWD` (the workspace root where `.claude/` lives), NOT in project subdirectories.

## Execute Lifecycle

Follow SKILL.md lifecycle in order:

### Step 0 — Readiness Gate

1. `/clear`
2. Run `/${CMD_PREFIX}-check-implementation-readiness`
3. If PASS: continue to Step 1
4. If FAIL: run `notify_error "{epic_id}" "Readiness gate failed"` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh` and HALT for human resolution

### Step 1 — Sprint-Status Query

1. `/clear`
2. Query sprint-status using the `-p` worker pattern from SKILL.md Step 1
3. Parse the JSON response — check `subtype` field:
   - `"success"` — extract `next_story` key and count stories by status for `story_count`
   - If `next_story` is null/empty AND all stories are `done` or `blocked` → proceed to Step 7 (epic completion)
   - If no `ready-for-dev` stories but `backlog` stories exist → proceed to Step 2 (create first story)
4. Store the story key and `story_count` for subsequent steps

### Notify Epic Started

After Step 1 resolves `story_count`, notify:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-telegram.sh && notify_epic_started "{epic_id}" "{story_count}"'
```

### Enter Story Cycle

With the first story key determined, set the story in state and enter the correct lifecycle phase:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh && update_story "{story_key}" "create-story"'
```

(The phase is set to `create-story` as a safe initial value; it will be updated to the correct phase when the routing step below executes.)

Route based on the story's current status in sprint-status:

| Status | Action |
|--------|--------|
| `backlog` | Execute Step 2 (create-story) per SKILL.md |
| `ready-for-dev` | **Verify artifact first (see below)**, then Execute Step 4 (dev-story) per SKILL.md |
| `in-progress` | **Verify artifact first (see below)**, then Resume Step 4 (dev-story) per SKILL.md — notify human via Telegram per SKILL.md Restart Recovery |
| `review` | Execute Step 5 (code-review) per SKILL.md |

**Story artifact verification (required before dispatching dev-story):**

When status is `ready-for-dev` or `in-progress`, first confirm the story file exists:

```bash
find _bmad-output/implementation-artifacts -maxdepth 1 -name "{story_key}*.md" 2>/dev/null | head -1
```

- **File found** → proceed to dev-story as planned.
- **File not found** → the prior create-story session was aborted before writing the artifact. Override routing:
  1. Log: `⚠️  Story {story_key} marked '{status}' but story artifact missing — falling back to create-story`
  2. Notify: `bash -c 'source scripts/bmad-dev-loop/lib/bmad-telegram.sh && notify_error "{story_key}" "story artifact missing — routing to create-story"'`
  3. Execute Step 2 (create-story) instead.

For each subsequent phase, use `/orchestrator-next-phase` to determine and execute the next step.

## Standing Rules

All SKILL.md Standing Rules apply.
