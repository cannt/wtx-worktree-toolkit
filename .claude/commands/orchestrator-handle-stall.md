# Orchestrator: Handle Stall

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<pending-signals>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && ls "$SIGNAL_DIR/" 2>/dev/null | grep -v '^heartbeat_' || echo "none"`
</pending-signals>

State and signals are pre-loaded above. Source `bmad-state.sh` only when you need to WRITE (update_state, write_signal).

## Read Current State

Parse the pre-loaded state above for: `current_story`, `current_phase`, `tmux_session`, `escalation_tier`. Otherwise fall back to:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
read_state
```

This exports: `STATE_CURRENT_STORY`, `STATE_CURRENT_PHASE`, `STATE_TMUX_SESSION`, `STATE_ESCALATION_TIER`.

## Determine Escalation Tier

The current `STATE_ESCALATION_TIER` determines which action to take. This command executes the **tier 3** response (triggered when `STATE_ESCALATION_TIER` is 2) and the **tier 4** response (triggered when `STATE_ESCALATION_TIER` is 3). Monitor-side handling for tiers 1–2 has already been exhausted before this command is invoked.

If `STATE_ESCALATION_TIER` is 0 or 1, report: "Tier {n} stalls are handled by the monitor — nothing to do here." and exit.

If `STATE_ESCALATION_TIER` is 4 or higher, the system is already at maximum escalation — skip to Tier 4 to re-notify and re-write `needs_human` signal (idempotent).

If `STATE_ESCALATION_TIER` is -1 (abort state), report: "Orchestrator is in abort state — no stall handling." and exit.

### Tier 3: Kill and Recreate

If `STATE_ESCALATION_TIER` is 2 (tier 2 has been exhausted, escalating to tier 3):

1. Update escalation tier in state first, before any action:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
update_state "escalation_tier" "3"
```

2. Kill the stalled session:

```bash
source scripts/bmad-dev-loop/lib/bmad-tmux.sh
kill_session "$STATE_TMUX_SESSION"
```

3. Create a fresh session and retry the last command per SKILL.md Worker Launch Patterns for the current phase (`STATE_CURRENT_PHASE`)

4. Monitor the new session for completion signals from `$SIGNAL_DIR/` (resolved by `bmad-state.sh`)

5. If the fresh session succeeds:
   - Reset escalation tier: `update_state "escalation_tier" "0"`
   - Continue lifecycle via `/orchestrator-next-phase`

6. If the fresh session also stalls (monitor sets tier to 3 again and re-invokes this command), escalate to tier 4

### Tier 4: Telegram Notification and Pause

If `STATE_ESCALATION_TIER` is 3 (tier 3 has been exhausted, escalating to tier 4):

1. Update escalation tier in state:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
update_state "escalation_tier" "4"
```

2. Send Telegram notification:

```bash
source scripts/bmad-dev-loop/lib/bmad-telegram.sh
notify_stall "$STATE_CURRENT_STORY" "4"
```

3. Write a `needs_human` signal:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
write_signal "needs_human"
```

4. HALT — wait for human intervention via Telegram command signal (`retry`, `skip`, or `abort`)

## After Human Response

When the orchestrator resumes after receiving a Telegram signal:
- `retry` → reset escalation tier to 0 via `update_state "escalation_tier" "0"`, re-run current phase via `/orchestrator-next-phase`
- `skip` → run story skip flow per SKILL.md
- `abort` → kill all sessions, commit partial work, notify via `notify_error "$STATE_CURRENT_STORY" "aborted by operator"`, stop

## Standing Rules

All SKILL.md Standing Rules apply. Additionally for this command:

- Kill/recreate only between workflows, never mid-execution (Rule 4 for dev-story)
- Use `STATE_TMUX_SESSION` (not `STATE_TMUX_SESSION_NAME`) — the exported variable name from `bmad-state.sh`
