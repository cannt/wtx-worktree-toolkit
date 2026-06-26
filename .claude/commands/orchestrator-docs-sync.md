# Orchestrator: Docs-Sync

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

This command triggers the `docs-sync` phase: autonomous documentation validation against the codebase, auto-fixing doc-only issues and collecting ambiguous code-vs-doc discrepancies into a backlog file for later triage.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<docs-sync-config>
!`grep -A 10 '^docs_sync:' scripts/bmad-dev-loop/bdl-config.yaml 2>/dev/null || echo 'no docs_sync config found — using defaults: scan_paths=[], max_validation_cycles=3, auto_trigger_between_epics=false'`
</docs-sync-config>

State is pre-loaded above. Source `bmad-state.sh` only for write operations.

## Arguments

Parse `$ARGUMENTS` for:
- **`--scope <paths>`** (optional) — comma-separated list of specific doc paths to scan, overrides config `scan_paths`
- **`--max-cycles <N>`** (optional) — override `max_validation_cycles` for this run only
- **`--skip-polish`** (optional, Part B) — skip the autonomous editorial pass; jump from validation directly to triage. Sets state field `docs_sync_skip_polish=true`.
- **`--skip-triage`** (optional, Part B) — skip the interactive backlog triage; backlog items remain `pending`. Combined with the absence of human input, this enables **fully autonomous mode**: discovery → validation → polish → report, no prompts. Sets state field `docs_sync_skip_triage=true`.

If no arguments provided, use config defaults (auto-discover docs, run all phases).

**Autonomous mode shortcut:** `/orchestrator-docs-sync --skip-triage` runs the entire pipeline with zero human input and leaves any code discrepancies in the backlog with `Triage status: pending` for a future interactive run.

## Startup

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
source scripts/bmad-dev-loop/lib/bmad-telegram.sh
read_state

# Parse Part B flags from $ARGUMENTS and persist to state so sub-skills can read them
if [[ "$ARGUMENTS" == *"--skip-polish"* ]]; then
    update_state "docs_sync_skip_polish" "true"
else
    update_state "docs_sync_skip_polish" ""
fi

if [[ "$ARGUMENTS" == *"--skip-triage"* ]]; then
    update_state "docs_sync_skip_triage" "true"
else
    update_state "docs_sync_skip_triage" ""
fi
```

Both flags are cleared again by `report.md`'s State Transitions step at the end of the run, so the next invocation starts clean.

## Precondition Check

Before starting docs-sync, verify the orchestrator is in a safe-to-dispatch state.

Use an **allowlist** (not a denylist) — only proceed if `current_phase` matches one of:

- empty / null / `init` — no work in progress
- `step-6-complete` — between stories
- `epic-complete` — after retrospective
- `docs-sync-complete` — previous docs-sync run finished
- `docs-sync-triage` — **resume mode**: a prior triage session was interrupted (user walked away, conversation compacted, monitor restarted). Re-invoking jumps directly into triage.md using the persisted `triage_cursor` + `triage_backlog_sha` — no discovery/validation/polish re-run.

Any other value (including `create-story`, `validate-story`, `dev-story`, `code-review`, `fix`, `docs-sync-discovery`, `docs-sync-validation`, `docs-sync-polish`, `docs-sync-report`, or unknown future phases): HALT with message: "Cannot run docs-sync while current_phase={current_phase}. Allowed states: init, step-6-complete, epic-complete, docs-sync-complete, docs-sync-triage (resume). Wait for the in-flight phase to complete or skip it first."

**Resume flow for `docs-sync-triage`:** when invoked with `current_phase=docs-sync-triage`, skip steps 1–6 below (Discovery / Validation / Polish) entirely and jump straight to step 7 (the triage sub-skill). The sub-skill's version guard reads `triage_backlog_sha` and either resumes from the stored cursor or resets if the backlog has changed since. This is the ONLY supported resume path — users never need to hand-edit `state.json`.

The allowlist prevents (a) racing an active story worker, (b) concurrent docs-sync invocations that could corrupt the manifest/backlog, and (c) unintended dispatch during rate-limit waits or account switches.

## Execute Docs-Sync Phase

Follow the docs-sync phase procedure in `.claude/skills/orchestrator/SKILL.md` (Step 8 — Docs-Sync). In summary:

1. `update_phase "docs-sync-discovery"`
2. Follow `.claude/skills/orchestrator/docs-sync/discovery.md` — produce the manifest
3. `update_phase "docs-sync-validation"`
4. Follow `.claude/skills/orchestrator/docs-sync/validation.md` — iterate the manifest
5. `update_phase "docs-sync-polish"` (Part B — skip if `docs_sync_skip_polish=true`)
6. Follow `.claude/skills/orchestrator/docs-sync/polish.md` — autonomous editorial pass
7. `update_phase "docs-sync-triage"` (Part B — skip if `docs_sync_skip_triage=true` or backlog empty)
8. Follow `.claude/skills/orchestrator/docs-sync/triage.md` — interactive backlog resolution, resumable via `triage_cursor`
9. `update_phase "docs-sync-report"`
10. Follow `.claude/skills/orchestrator/docs-sync/report.md` — commit and report (now includes Polish + Triage sections)
11. `update_phase "docs-sync-complete"`

Notify via Telegram at phase start:
```bash
notify_phase_started "docs-sync" "${STATE_EPIC_ID:-manual}"
```

## Post-Completion

Once report completes successfully:
- `last_phase_result` = `clean` (no errors) or `partial` (errors/max-cycles occurred)
- `current_phase` = `docs-sync-complete`
- The monitor will detect `docs-sync-complete` as idle and dispatch `/orchestrator-next-phase` — which returns to normal lifecycle flow (Step 1 sprint-status query or idle).

## Standing Rules

All SKILL.md Standing Rules apply. Additionally for this command:

- **Never modify source code** — except via Triage [Q] Quick-fix, the single allowed exception (Rule 58)
- **Never auto-fix code discrepancies in validation** — they always go to backlog
- **Always re-validate after applying fixes** — but cap at `max_validation_cycles` to prevent infinite loops
- **Respect Rule 3** — run `/clear` before every BMAD **workflow command** dispatch (`/${CMD_PREFIX}-create-story`, `/${CMD_PREFIX}-dev-story`, etc.). Inline skill dispatches within the orchestrator pane (adversarial-general, editorial-review-prose/structure, correct-course, edge-case-hunter) do NOT require `/clear` — Rule 3 is scoped to workflow commands, not every skill call.
- **Respect Rule 49** — `bmad-review-adversarial-general`, `bmad-review-edge-case-hunter`, `bmad-editorial-review-prose`, `bmad-editorial-review-structure`, `bmad-correct-course` always keep the `bmad-` prefix regardless of `CMD_PREFIX`. Only `${CMD_PREFIX}-create-story` uses the module prefix.
- **Respect Rules 56-58** — Polish skips error/max_cycles_hit docs (56) and frozen regions (57); Triage Quick-fix is the sole source-code escape hatch (58)
- **Polish dispatches sequentially** — never parallelize editorial skill calls across docs (rate limit risk)
- **Triage is resumable** — `triage_cursor` + `triage_backlog_sha` persist in state; re-invoking the slash command with `current_phase=docs-sync-triage` jumps straight back into the triage loop. Status-filtered iteration ensures no orphans.
