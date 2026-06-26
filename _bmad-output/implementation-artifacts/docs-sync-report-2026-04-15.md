# Docs-Sync Report — 2026-04-15

**Epic:** manual
**Run ID:** run-20260415-201839

## Statistics

- **Docs scanned:** 9
- **Clean (no issues):** 8
- **Auto-fixed:** 1 issue across 1 doc (`docs/development.md` — stale test-case counts)
- **Sent to backlog:** 4 code discrepancies
- **Max cycles hit:** 0 docs
- **Errors:** 0 docs
- **Oversized (excluded, >200KB):** 0 docs

## Per-Doc Breakdown

| Doc | Cycles | Auto-Fixed | Backlogged | Status |
|---|---|---|---|---|
| CLAUDE.md | 1 | 0 | 1 | clean |
| _bmad-output/project-context.md | 1 | 0 | 0 | clean |
| README.md | 1 | 0 | 0 | clean |
| docs/architecture.md | 1 | 0 | 2 | clean |
| docs/commands.md | 1 | 0 | 1 | clean |
| docs/configuration.md | 1 | 0 | 0 | clean |
| docs/development.md | 1 | 1 | 0 | clean |
| docs/index.md | 1 | 0 | 0 | clean |
| docs/library-api.md | 1 | 0 | 0 | clean |

## Polish

All 9 docs polished. No prose or structural changes applied — docs are well-written with no CUT/CONDENSE/MOVE/MERGE recommendations.

## Triage

- **Items triaged:** 3 / 4
- **Storied (new story created):** 2
  - `story-config-driven-base-branch.md` — wire `worktree-start.sh` to read `defaults.base_branch` from config
  - `story-config-driven-registry-path.md` — wire `worktree-tui.sh` to read `worktree.registry_path` from config
- **Dismissed (doc fixed inline):** 1
  - `docs/architecture.md` — removed `_wtx_config_resolve_path` from Public API table (private function)
- **Still pending:** 1
  - `CLAUDE.md` — same root cause as registry-path story; will auto-resolve once that story lands

## Backlog

See `docs-sync-backlog.md` for full entries. 1 item remains pending and will be
re-presented on the next docs-sync run.

## Commit

- **Committed:** true
- **Commit hash:** 516e9bf
- **Message:** checkpoint: docs-sync manual
