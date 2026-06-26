# Orchestrator: Start Story

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<pending-signals>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && ls "$SIGNAL_DIR/" 2>/dev/null | grep -v '^heartbeat_' || echo "none"`
</pending-signals>

<sprint-status>
!`cat _bmad-output/implementation-artifacts/sprint-status.yaml 2>/dev/null`
</sprint-status>

State, signals, and sprint-status are pre-loaded above. Use them to check existing state and route to the correct phase. Source `bmad-state.sh` only for write operations.

## Arguments

Parse `$ARGUMENTS` for:
- **Story key** (required) — e.g., `bdl-2-4`
- **`--no-opencode`** (optional) — if present, set `use_opencode=false` in state (forces Claude-only validation)
- **`--mode {value}`** (optional) — orchestration mode: `claude-all`, `claude+codex`, `claude+opencode`, `opencode-all`, `opencode+claude`. Defaults to env `$ORCHESTRATION_MODE` or `claude+codex`

If no story key is provided, HALT: "Usage: /orchestrator-start-story {story-key} [--no-opencode]"

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

Derive the epic ID from the story key (e.g., `bdl-2-4` → epic `bdl-2`) and initialize state at the story level, skipping the epic readiness gate.

**External tool detection:** Run `which opencode` and `which codex` to check available tools. The `use_opencode` field is a legacy compatibility flag; the authoritative setting is `orchestration_mode` (default: `claude+codex`). If `--no-opencode` is in `$ARGUMENTS`, set `use_opencode=false` to force Claude-only validation.

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh

# Detect external tool installation (legacy field — orchestration_mode is authoritative)
use_opencode="false"
if which opencode >/dev/null 2>&1 || which codex >/dev/null 2>&1; then
    use_opencode="true"
fi
# --no-opencode flag in $ARGUMENTS overrides tool detection — substitute "true" if flag was present
[[ "{no_opencode}" == "true" ]] && use_opencode="false"

init_state "{epic_id}" "$(basename "$PWD")" "$use_opencode"

# Store orchestration mode (from --mode flag, env $ORCHESTRATION_MODE, or default)
update_state "orchestration_mode" "{mode}"  # default: claude+codex
```

**Important:** The `project_folder` argument is informational only (auto-detected from directory name). Workers must always be launched in `$PWD` (the workspace root where `.claude/` lives), NOT in project subdirectories.

Then set the current story:

```bash
update_story "{story_key}" "create-story"
```

(The phase passed to `update_story` will be overridden when the correct phase is executed below.)

## Determine Current Story Status

Read `_bmad-output/implementation-artifacts/sprint-status.yaml` to find the current status of the specified story key.

Handle legacy status mappings per SKILL.md:
- `drafted` → treat as `ready-for-dev`
- `contexted` → treat as `in-progress`

## Route to Correct Phase

Based on the story's current status, enter the lifecycle at the appropriate point:

| Status | Action |
|--------|--------|
| `backlog` | Execute Step 2 (create-story) per SKILL.md — the story file does not exist yet |
| `ready-for-dev` | Execute Step 4 (dev-story) per SKILL.md — story file exists, skip creation/validation |
| `in-progress` | Resume Step 4 (dev-story) per SKILL.md — story was partially implemented |
| `review` | Execute Step 5 (code-review) per SKILL.md — implementation done, needs review |
| `done` | Report: "Story {story_key} is already done. Nothing to do." |
| `blocked` | Report: "Story {story_key} is blocked. Use Telegram `retry` signal to unblock, or choose a different story." |
| Not found | HALT: "Story key {story_key} not found in sprint-status.yaml" |

## After Phase Entry

Once the initial phase completes, use `/orchestrator-next-phase` to continue the lifecycle.

## Standing Rules

All SKILL.md Standing Rules apply.
