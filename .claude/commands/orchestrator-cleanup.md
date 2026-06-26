# Orchestrator: Cleanup

Stop all orchestrator processes, kill tmux sessions, and clear state for a fresh start.

## Pre-loaded State (for --keep-state display)

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

## Arguments

Parse `$ARGUMENTS` for:
- **`--keep-state`** (optional) — preserve `state.json` for resume (only clears signals and kills sessions)

If no arguments provided, perform full cleanup.

## Cleanup Steps

Run ALL of these commands in sequence:

### 1. Kill all orchestrator tmux sessions

```bash
tmux -L orchestrator kill-server 2>/dev/null && echo "✅ Tmux orchestrator server killed" || echo "ℹ️  No orchestrator server running"
```

### 2. Kill background processes

```bash
pkill -f "bmad-monitor.sh" 2>/dev/null && echo "✅ Monitor processes killed" || echo "ℹ️  No monitor running"
pkill -f "caffeinate -i" 2>/dev/null && echo "✅ Caffeinate killed" || echo "ℹ️  No caffeinate running"
```

### 3. Clear signals (always)

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
find "$SIGNAL_DIR/" -maxdepth 1 -type f -delete 2>/dev/null
echo "✅ Signals cleared"
```

### 4. Clear state (unless `--keep-state`)

If `--keep-state` was NOT in `$ARGUMENTS`:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
rm -f "$STATE_FILE" "$STATE_FILE.bak" 2>/dev/null
echo "✅ State cleared"
```

If `--keep-state` WAS provided:

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
echo "ℹ️  State preserved (--keep-state)"
cat "$STATE_FILE" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "  (no state file found)"
```

### 5. Send Telegram notification

```bash
bash -c 'source scripts/bmad-dev-loop/lib/bmad-telegram.sh 2>/dev/null && send_telegram "🧹 *Orchestrator Cleaned Up*

_All sessions stopped. Ready for fresh start._"' 2>/dev/null
```

## Report

After cleanup, report:

```
🧹 Orchestrator Cleanup Complete

  Tmux server:  killed
  Monitor:      killed
  Caffeinate:   killed
  Signals:      cleared
  State:        cleared (or preserved)

Ready to run /orchestrator-start-epic or /orchestrator-start-story
```
