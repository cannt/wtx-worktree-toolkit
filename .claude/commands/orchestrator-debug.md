# Orchestrator: Debug Dump

Collect all available diagnostic evidence for crash/stall investigation and display it inline.

## Pre-loaded Context

<orchestrator-state>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && cat "$STATE_FILE" 2>/dev/null || echo '{"status":"no_state_file"}'`
</orchestrator-state>

<pending-signals>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && ls "$SIGNAL_DIR/" 2>/dev/null | grep -v '^heartbeat_' || echo "none"`
</pending-signals>

<active-sessions>
!`tmux -L orchestrator list-sessions -F "#{session_name}" 2>/dev/null || echo "no tmux server"`
</active-sessions>

<monitor-log-tail>
!`source scripts/bmad-dev-loop/lib/bmad-state.sh >/dev/null 2>&1 && tail -40 "$STATE_DIR/logs/monitor.log" 2>/dev/null || tail -40 /tmp/bmad-monitor.log 2>/dev/null || echo "no monitor log found"`
</monitor-log-tail>

## Steps

### 1. Create the debug dump archive and display briefing.md inline

Run both actions in a single shell invocation so only one archive is created:

```bash
DUMP_ZIP=$(bash scripts/bdl-debug-dump.sh --output-path-only 2>/dev/null)
DUMP_NAME=$(basename "$DUMP_ZIP" .zip)
echo "Archive: $DUMP_ZIP"
echo "---"
unzip -p "$DUMP_ZIP" "${DUMP_NAME}/briefing.md" 2>/dev/null \
  || tar -xzf "$DUMP_ZIP" -O "${DUMP_NAME}/briefing.md" 2>/dev/null \
  || echo "(briefing.md unavailable)"
```

Display the full contents of `briefing.md` in the conversation output.

### 2. Show live pane captures

For each active bmad worker session (skip monitor/dashboard/orchestrator), capture and display the last 50 lines:

```bash
for sess in $(tmux -L orchestrator list-sessions -F "#{session_name}" 2>/dev/null); do
  case "$sess" in bmad-monitor|bmad-dashboard|bmad-orchestrator) continue ;; esac
  pane=$(tmux -L orchestrator list-panes -t "$sess" -F "#{pane_id}" 2>/dev/null | head -1)
  [ -z "$pane" ] && continue
  echo "=== $sess ==="
  tmux -L orchestrator capture-pane -t "$pane" -p -S -50 2>/dev/null
  echo ""
done
```

### 3. Show signal file contents

```bash
source scripts/bmad-dev-loop/lib/bmad-state.sh
for sig in "$SIGNAL_DIR"/*; do
  [ -f "$sig" ] || continue
  printf '  %s: %s\n' "$(basename "$sig")" "$(cat "$sig" 2>/dev/null)"
done
```

### 4. Send Telegram notification (if configured)

```bash
DUMP_ZIP=$(ls -t "$HOME/.bmad-orchestrator/dumps/"bdl-debug-*.zip 2>/dev/null | head -1)
bash -c "source scripts/bmad-dev-loop/lib/bmad-telegram.sh 2>/dev/null \
  && send_telegram '📦 *Debug Dump Created*

Path: \`${DUMP_ZIP}\`

_Run /orchestrator-debug to view inline, or share the zip for remote diagnosis._'" 2>/dev/null || true
```

## Report

After completing all steps, present a consolidated summary:

```
=== BDL Debug Report ===

Archive: {zip_path}

(briefing.md output shown above in Step 1)

Active panes captured: {n}
Signals present: {list or "none"}
Telegram: {notified / not configured}

To share for diagnosis: provide the .zip archive path above.
```

Note: The `briefing.md` is the primary diagnostic artifact. Read it carefully — the **Diagnosis Hints** section at the bottom identifies the most likely root cause.
