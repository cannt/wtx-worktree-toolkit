# Orchestrator: Commit Check

You are the BMAD Dev Loop Orchestrator. Load your full knowledge base from `.claude/skills/orchestrator/SKILL.md`.

## Pre-loaded State

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

State is pre-loaded above. Source `bmad-state.sh` only for write operations.

## Arguments

Parse `$ARGUMENTS` for:
- **Phase name** (required) — e.g., `create-story`, `dev-story`, `code-review`

If no phase name is provided, HALT: "Usage: /orchestrator-commit-check {phase}"

## Read Current Story Key

Parse the pre-loaded state above for `current_story`. Otherwise fall back to:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
read_state
```

The current story key is available as `STATE_CURRENT_STORY`.

## Check for Uncommitted Changes

```bash
git status --porcelain
```

### If changes exist:

1. Stage only relevant files — story files, implementation artifacts, sprint-status, and command files. Do NOT use `git add -A` (it stages everything including unrelated files and potential secrets). Instead stage selectively:

```bash
git add _bmad-output/implementation-artifacts/
git add .claude/commands/
git add .claude/skills/
git add scripts/
```

   If other specific files were created or modified as part of this phase, add them explicitly. Do NOT stage `.env` files, credential files, or files unrelated to this story.

2. Create a checkpoint commit with the standard format:

```bash
git commit -m "checkpoint: {phase} {story_key}"
```

For example: `checkpoint: dev-story bdl-2-4`

3. Verify the commit succeeded (exit code 0), then report: "Checkpoint commit created: checkpoint: {phase} {story_key}"

4. If `git commit` fails (pre-commit hook rejection, nothing staged, or other error), report the error and HALT — do not proceed without a successful checkpoint commit.

### If no changes exist:

Report: "No changes to commit for {phase} {story_key}. Continuing."

## Standing Rules

All SKILL.md Standing Rules apply. Additionally for this command:

- Commit message format is exactly: `checkpoint: {phase} {story_key}`
- Do NOT push — only commit locally
- Do NOT use `git add -A` — stage selectively to avoid committing secrets or unrelated changes
