# Orchestrator: Status Report

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<pending-signals>
!`bash -c 'source scripts/bmad-dev-loop/lib/bdl-orchestrator-precompute.sh 2>/dev/null && signal_summary' 2>/dev/null || (source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && ls "$SIGNAL_DIR/" 2>/dev/null | grep -v '^heartbeat_') || echo "none"`
</pending-signals>

<sprint-summary>
!`bash -c 'source scripts/bmad-dev-loop/lib/bdl-orchestrator-precompute.sh 2>/dev/null && sprint_status_summary "_bmad-output/implementation-artifacts/sprint-status.yaml"' 2>/dev/null || echo "summary unavailable"`
</sprint-summary>

<phase-hint>
!`bash -c 'source scripts/bmad-dev-loop/lib/bdl-orchestrator-precompute.sh 2>/dev/null && phase_route_hint' 2>/dev/null || echo "hint unavailable"`
</phase-hint>

State, signals, and sprint-status summary are pre-loaded above. Use them directly for the status report. Source bash libraries only for sections that require live queries (tmux sessions, Telegram).

## Gather Status from All Sources

### 1. State (`state.json`)

Parse the pre-loaded state above. If valid, extract directly. Otherwise fall back to:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
read_state
```

Report all exported `STATE_*` variables:
- Epic ID: `STATE_EPIC_ID`
- Current Story: `STATE_CURRENT_STORY`
- Current Phase (last completed): `STATE_CURRENT_PHASE`
- Orchestration Mode: `STATE_ORCHESTRATION_MODE`
- Use OpenCode: `STATE_USE_OPENCODE`
- Escalation Tier: `STATE_ESCALATION_TIER`
- Create Fix Count: `STATE_CREATE_FIX_COUNT`
- Review Fix Count: `STATE_REVIEW_FIX_COUNT`
- Started At: `STATE_STARTED_AT`
- Last Phase Completed At: `STATE_LAST_PHASE_COMPLETED_AT`

If `state.json` does not exist, report: "No orchestrator state found. Run /orchestrator-start-epic or /orchestrator-start-story first."

### 2. Sprint Status Summary

Read `_bmad-output/implementation-artifacts/sprint-status.yaml` and produce a summary:
- Count stories by status: backlog, ready-for-dev, in-progress, review, done, blocked
- List the current epic's stories with their statuses
- Identify the next story to be worked on

If the file does not exist or the pre-loaded `<sprint-summary>` above shows "summary unavailable", report: "Sprint status file not found. Run /orchestrator-start-epic to initialize."

### 3. Active tmux Sessions

```bash
source scripts/bmad-dev-loop/lib/bmad-tmux.sh
list_sessions
```

Report all active sessions on `tmux -L orchestrator`, showing:
- Session name
- Whether it matches the `bmad-{tool}-{phase}-{story}` naming convention
- Any sessions that appear stale or unexpected

### 4. Pending Signal Files

```bash
ls -la "$SIGNAL_DIR/" 2>/dev/null
```

Report:
- Number of pending signal files
- Signal types found (e.g., `phase_complete`, `needs_human`, `halt_detected`)
- If no signals directory exists, report: "Signals directory not found"

### 5. Telegram Connectivity

```bash
source scripts/bmad-dev-loop/lib/bmad-telegram.sh
# Check if credentials are configured
[ -f ~/.bmad-dev-loop.env ] && echo "Telegram configured" || echo "Telegram NOT configured"
```

Report whether Telegram bot credentials are available.

### 6. Deferred Work

Check if `_bmad-output/implementation-artifacts/deferred-work.md` exists:
- If yes: count the number of entries and report
- If no: report "No deferred work file"

## Output Format

Present all information in a structured report:

```
=== BMAD Orchestrator Status ===

State:
  Epic: {epic_id}
  Story: {current_story}
  Phase: {current_phase}
  Escalation: tier {n}
  OpenCode: {true/false}
  Started: {timestamp}
  Last Phase: {timestamp}

Sprint Status:
  Backlog: {n} | Ready: {n} | In-Progress: {n} | Review: {n} | Done: {n} | Blocked: {n}
  Next story: {story_key}

tmux Sessions:
  {session_list or "none active"}

Signals:
  {signal_list or "none pending"}

Telegram: {configured/not configured}
Deferred Work: {n entries / none}
```
