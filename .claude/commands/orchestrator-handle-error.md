# Orchestrator: Handle Error

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

State is pre-loaded above. Source `bmad-state.sh` only when you need to WRITE (update_state, write_signal).

## Arguments

Parse `$ARGUMENTS` for:
- **Error context** (required) — a string describing the error, e.g., `"budget exceeded on create-story"` or `"session died during dev-story"`

Store the parsed string: `error_context="<parsed value>"`

If no context is provided, HALT: "Usage: /orchestrator-handle-error {context}"

## Read Current State

Parse the pre-loaded state above for: `current_story`, `current_phase`, `error_retry_count`. Otherwise fall back to:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
read_state
```

## Classify the Error

Analyze the error context string and classify as **recoverable** or **fatal**.

### Recoverable Errors

| Error Type | Detection Keywords | Recovery Action |
|-----------|-------------------|----------------|
| Budget exceeded | `budget`, `max_budget_usd`, `error_max_budget_usd` | Retry with higher `--max-budget-usd` limit (e.g., double the previous cap) |
| Structured output failure | `structured_output`, `error_max_structured_output_retries` | Retry; if count ≥ 3, escalate |
| Session died | `session_dead`, `session died`, `tmux` | Kill via `kill_session "$STATE_TMUX_SESSION"` from `scripts/bmad-dev-loop/lib/bmad-tmux.sh`, recreate fresh session, retry phase |
| Rate limit | Patterns from `RATE_LIMIT_PATTERNS` in `scripts/bmad-dev-loop/lib/bmad-patterns.conf` | Retry with exponential backoff: wait 30s before attempt 1, 60s before attempt 2, 120s before attempt 3 (max 3 retries) |

### Fatal Errors

| Error Type | Detection Keywords | Action |
|-----------|-------------------|--------|
| Persistent failure | `3 consecutive`, `max retries`, `cycle 2` | Escalate |
| Missing configuration | `config`, `missing`, `not found` | Escalate |
| Human decision required | `decision_needed`, `ambiguous` | Escalate |
| Unknown/unclassifiable | (none of the above) | Escalate |

## Recovery Attempt (Recoverable Errors)

Track recovery attempts using a dedicated counter stored separately from the stall escalation tier.

1. Read `STATE_ERROR_RETRY_COUNT` from the already-loaded state above (default 0 if absent)
2. If this is the **first or second attempt** (count < 3): increment the counter and execute the recovery action from the table above:

```bash
update_state "error_retry_count" "$((STATE_ERROR_RETRY_COUNT + 1))"
```

3. If this is the **third attempt** (count ≥ 3): reclassify as fatal and escalate

After successful recovery, reset:

```bash
update_state "error_retry_count" "0"
```

Then re-dispatch the current phase per SKILL.md Worker Launch Patterns for `STATE_CURRENT_PHASE`, or invoke `/orchestrator-next-phase` to continue the lifecycle.

## Escalation (Fatal Errors)

1. Send Telegram notification with story key and description as separate arguments:

```bash
source scripts/bmad-dev-loop/lib/bmad-telegram.sh
notify_error "$STATE_CURRENT_STORY" "$error_context"
```

2. Write a `needs_human` signal:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
write_signal "needs_human"
```

3. HALT — wait for human intervention

## Standing Rules

All SKILL.md Standing Rules apply. Additionally for this command:

- Use `error_retry_count` (not `escalation_tier`) for error recovery tracking — `escalation_tier` is reserved for stall tier management
- Use `STATE_TMUX_SESSION` (not `STATE_TMUX_SESSION_NAME`) when killing sessions
