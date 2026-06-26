# Orchestrator: Next Phase

You are the BMAD Dev Loop Orchestrator. Your core decision logic is in `.claude/skills/orchestrator/SKILL.md` — read it if you need step details. For reference-only sections (notifications, auto-dismiss, error handling, config), read `.claude/skills/orchestrator/SKILL-reference.md` ONLY when needed.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<pending-signals>
!`bash -c 'source scripts/bmad-dev-loop/lib/bdl-orchestrator-precompute.sh 2>/dev/null && signal_summary' 2>/dev/null || (source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && ls "$SIGNAL_DIR/" 2>/dev/null | grep -v '^heartbeat_') || echo "none"`
</pending-signals>

<phase-hint>
!`bash -c 'source scripts/bmad-dev-loop/lib/bdl-orchestrator-precompute.sh 2>/dev/null && phase_route_hint' 2>/dev/null || echo "hint unavailable"`
</phase-hint>

<cmd-prefix>
!`grep 'command_prefix:' scripts/bmad-dev-loop/bdl-config.yaml 2>/dev/null | awk '{print $2}' | tr -d '" \t'`
</cmd-prefix>

Use the value in `<cmd-prefix>` as `CMD_PREFIX` for all module-specific workflow command dispatches (create-story, dev-story, sprint-status, check-implementation-readiness, retrospective). Fall back to `bmad` if empty.

State and signals are pre-loaded above. Source `bmad-state.sh` only when you need to WRITE (update_state, write_signal, update_story). For reads, use the pre-loaded data directly.

## Read Current State

If the pre-loaded state above is valid JSON, parse it directly for: `epic_id`, `current_story`, `current_phase`, `orchestration_mode`, `escalation_tier`, `create_fix_count`, `review_fix_count`. Otherwise fall back to:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh && read_state'
```

This exports: `STATE_EPIC_ID`, `STATE_CURRENT_STORY`, `STATE_CURRENT_PHASE`, `STATE_ORCHESTRATION_MODE`, `STATE_ESCALATION_TIER`, `STATE_CREATE_FIX_COUNT`, `STATE_REVIEW_FIX_COUNT`.

## Check for Pending Signals

Check the pre-loaded signal listing above. If any signals are present (not "none"), source `bmad-state.sh` and call `read_signal` for each pending type to get the payload and atomically delete the signal file:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh
# Only call read_signal for signals that appear in the pre-loaded listing above
read_signal "abort"              # highest priority
read_signal "pause"
read_signal "checkpoint_requested"  # from monitor before account rotation
read_signal "retry"
read_signal "skip"
read_signal "user_message"       # free-text from Telegram
read_signal "needs_human"
read_signal "halt_detected"'
```

If a signal is found, handle it per SKILL.md Signal Protocol:

| Signal | Action |
|--------|--------|
| `abort` | Kill all sessions via `kill_session` from `scripts/bmad-dev-loop/lib/bmad-tmux.sh`, commit partial work, set `escalation_tier: -1` via `update_state`, notify via `notify_error "$STATE_CURRENT_STORY" "aborted by operator"` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh`, HALT |
| `pause` | Finish current sub-step, write `needs_human` signal via `write_signal "needs_human"`, notify via `notify_stall "$STATE_CURRENT_STORY" "$STATE_ESCALATION_TIER"` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh`. HALT. |
| `checkpoint_requested` | The monitor is about to rotate accounts and needs a checkpoint commit. Immediately run `/orchestrator-commit-check dev-story` to save current work. After the commit completes, write `write_signal "checkpoint_done" "committed"` so the monitor can proceed with the rotation. Then continue normal operation (the monitor will kill this session shortly). |
| `retry` | Kill current worker via `kill_session "$STATE_TMUX_SESSION"` from `scripts/bmad-dev-loop/lib/bmad-tmux.sh`, reset fix cycle count to 0, re-run current phase |
| `skip` | Run skip flow: set story to `blocked` in sprint-status, commit partial work, notify via `notify_error "$STATE_CURRENT_STORY" "skipped — marked blocked"`, advance to next story |
| `user_message` | The payload contains a free-text message from the user via Telegram. Read the payload text and process it as user input in the current context. For example: if waiting for a decision, treat the message as the user's decision. If the orchestrator is between phases, treat it as an instruction. Acknowledge via Telegram: `send_telegram "✅ Message received and processed"`. Then continue with the appropriate action based on the message content. |
| `needs_human` | HALT — wait for human intervention |
| `halt_detected` | Read pane content to determine HALT type. For orchestrator-relevant HALTs (A8, A9, A10, B4 per SKILL.md), notify via `notify_error "$STATE_CURRENT_STORY" "HALT detected — {halt_type}"` and HALT. For dev-story-internal HALTs (B1, B2, C1, C2/C3), resume monitoring. |

If no signal is pending, clear any stale signal files that `read_signal` didn't consume (e.g., `phase_complete`, `error`, heartbeat files) before proceeding:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh && clear_signals'
```

Then check for account switch before phase determination.

## Check for Account Switch

If the pre-loaded state JSON contains `"account_switch_completed": true`, the monitor has rotated the Claude account while this orchestrator was down. Handle this before normal phase routing:

1. Read `pre_switch_state` from the state JSON: `phase`, `story`, `usage_pct`, `switched_at`
2. Log to journal:
   ```bash
   source scripts/bmad-dev-loop/lib/bmad-state.sh
   ACTIVE_ACCOUNT=$(STATE_FILE="$STATE_FILE" python3 -c "import json, os; d=json.load(open(os.environ['STATE_FILE'])); print(d.get('active_account_name','unknown'))")
   pre_switch_usage=$(STATE_FILE="$STATE_FILE" python3 -c "import json, os; d=json.load(open(os.environ['STATE_FILE'])); print(d.get('pre_switch_state',{}).get('usage_pct','?'))" 2>/dev/null || echo "?")
   journal_log "$STATE_CURRENT_STORY" "account-switch" "decision" "Account rotated at ${pre_switch_usage}% — now using $ACTIVE_ACCOUNT"
   ```
3. Clear the switch flag:
   ```bash
   source scripts/bmad-dev-loop/lib/bmad-account-rotation.sh
   clear_account_switch_flag
   ```
4. Resume based on the interrupted phase:
   - `pre_switch_state.phase` is `"dev-story"` → Restart dev-story for `STATE_CURRENT_STORY` (Step 4 in SKILL.md). The story file and committed code still exist; dev-story will pick up from committed state.
   - `pre_switch_state.phase` is `"create-story"`, `"validate-story"`, or `"code-review"` → Re-run that phase (these are stateless `-p` workers).
   - `pre_switch_state.phase` is `"init"`, `"idle"`, `""`, or `"step-6-complete"` → Proceed to normal phase determination below.

## Determine Next Phase

`STATE_CURRENT_PHASE` holds the **currently active** phase (set when a phase starts). After validation and code-review phases, the **result** of that phase is stored in `state.json` via `update_state "last_phase_result" "{result}"` (written by this command after parsing the worker's structured JSON output). Read it via `read_state` and check `STATE_LAST_PHASE_RESULT` alongside `STATE_CURRENT_PHASE`.

Based on `STATE_CURRENT_PHASE`, determine what to do next:

| Last Completed Phase | Condition | Next Action |
|---------------------|-----------|-------------|
| `init` or `(empty)` | — | Start from Step 1 — sprint-status query per SKILL.md |
| `create-story` | — | Execute Step 3 — validate story per SKILL.md |
| `validate-story` | `STATE_LAST_PHASE_RESULT` = `"pass"` | Execute Step 4 — dev-story per SKILL.md |
| `validate-story` | `STATE_LAST_PHASE_RESULT` = `"fail"` | Enter create-validate-fix loop per SKILL.md Fix Loop Protocol. Increment `create_fix_count`: `update_state "create_fix_count" "$((STATE_CREATE_FIX_COUNT + 1))"`. If count ≥ 2, escalate via `notify_error "$STATE_CURRENT_STORY" "create-validate-fix loop: $STATE_CREATE_FIX_COUNT cycles exceeded"` and HALT. |
| `dev-story` | — | Execute Step 5 — code review per SKILL.md |
| `code-review` | `STATE_LAST_PHASE_RESULT` = `"clean"` | Execute Step 6 — next story per SKILL.md. Mark current story `done` in sprint-status. |
| `code-review` | `STATE_LAST_PHASE_RESULT` = `"patch"` | Enter code review fix loop per SKILL.md Fix Loop Protocol. Increment `review_fix_count`: `update_state "review_fix_count" "$((STATE_REVIEW_FIX_COUNT + 1))"`. If count ≥ 2, escalate via `notify_error "$STATE_CURRENT_STORY" "code-review-fix loop: $STATE_REVIEW_FIX_COUNT cycles exceeded"` and HALT. |
| `code-review` | `STATE_LAST_PHASE_RESULT` = `"decision_needed"` | Pause for human — notify via `notify_decision_needed "$STATE_CURRENT_STORY" "{finding_description}"` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh`. Write `needs_human` signal. HALT. Do NOT auto-resolve (Rule 8). |
| `step-6-complete` | No more stories in backlog/ready-for-dev | Execute Step 7 — epic completion per SKILL.md |
| `step-6-complete` | More stories remain | Query sprint-status for next story, `update_story "{next_story}" "init"`, then start the next story cycle (Step 1) |

**Session refresh between stories:** After completing a story, the orchestrator's context is near capacity. Step 6 saves all state to `state.json`, runs `/clear`, then runs `/orchestrator-next-phase` to resume with fresh context. The new invocation reads `state.json`, finds `step-6-complete` with a blank story, queries sprint-status for the next story, and begins the cycle anew.

**Writing `last_phase_result`:** After each validation or code-review worker completes, parse the worker's output to determine the result and write:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh && update_state "last_phase_result" "pass"'   # or "fail", "clean", "patch", "decision_needed"
```

## Execute the Phase

1. `/clear`
2. Notify phase start via `notify_story_started "$STATE_CURRENT_STORY" "{phase}"` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh`
3. Dispatch the appropriate worker using the launch pattern from SKILL.md Worker Launch Patterns
4. Monitor for completion signals from `$SIGNAL_DIR/` (resolved by `bmad-state.sh`)
5. On completion, update state:

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-state.sh && update_state "current_phase" "{completed_phase}" && update_state "last_phase_completed_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"'
```

6. Notify phase completion via `notify_phase_completed "$STATE_CURRENT_STORY" "{phase}"` from `scripts/bmad-dev-loop/lib/bmad-telegram.sh`
7. If the completed phase requires a checkpoint commit, run `/orchestrator-commit-check {phase}`

## After Phase Completion

Invoke `/orchestrator-next-phase` again to continue the lifecycle, unless:
- A HALT condition was triggered
- The epic is complete (Step 7 finished)
- A `needs_human` signal is pending

## Standing Rules

All SKILL.md Standing Rules apply. Additionally for this command:

- `current_phase` in state reflects the currently active phase (set when a phase starts) (SKILL.md State Update Rules)
