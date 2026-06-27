# Story Automator Learnings

## Run: 2026-06-27

**Epic:** wtx - Epic 1: Interactive Installer
**Stories:** 1.1-1.7

### Patterns Observed
- Both Claude and Codex hit usage/rate limits mid-run on this account tier; the codex-review preset's fallback chain (codex → claude) absorbed every failure without escalation.
- Two "crashed" review sessions for story 1.4 turned out to be silent codex failures with no output file — diagnosing required capturing the tmux pane directly rather than trusting `monitor-session` alone.
- Several create/automate sessions kept running well past `monitor-session`'s default timeout while still doing real work; polling `tmux-status-check` + `sprint-status get` directly was more reliable than the monitor call.
- automate/retro sessions sometimes finish their work then idle at a confirmation prompt ("commit this") instead of exiting — safe to kill once sprint-status/git state confirms the work landed.

### Code Review Insights
- Common issues: none blocking — all 7 stories passed code review within 1 cycle except 1.4 (4 cycles, due to agent crashes, not code issues).
- Average cycles to clean: ~1.4

### Timing Estimates
- create-story: ~5-10 min
- dev-story: ~5-15 min (longer for High complexity)
- automate: ~5-20 min
- code-review: ~5-10 min per cycle

### Recommendations for Future Runs
- Prefer longer poll intervals (60s) with direct `tmux-status-check`/`sprint-status get` over `monitor-session --json` when sessions are expected to run long, since the latter's own timeout produced repeated false "no response" failures.
- When a review session shows `final_state: crashed` with no output file, capture the tmux pane immediately on the next attempt before assuming a code problem — it is often an account-level usage limit.
