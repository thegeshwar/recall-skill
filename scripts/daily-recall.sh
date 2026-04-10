#!/bin/bash
# Daily Recall — runs /recall via Claude Code CLI
# Triggered by launchd at 8:00 AM Pacific daily

LOG_DIR="$HOME/scripts/recall/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/recall-$(date +%Y-%m-%d).log"

echo "=== Daily Recall started at $(date) ===" >> "$LOG_FILE"

# Set PATH so claude and all tools are available
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Force bash as shell — zsh has read-only variables (e.g. "status") that
# break Claude's generated bash commands
export SHELL=/bin/bash

# Run recall skill via Claude Code in non-interactive print mode
# --output-format json: required because -p text mode swallows output when tools are used
# --permission-mode auto: auto-approve tool calls
# Working directory is home so CLAUDE.md and configs are found
cd "$HOME"

# Pre-launch Reminders so it's warm + iCloud-synced before the script needs it
# This runs as /bin/bash (TCC-approved) — not Claude (which loses TCC on every update)
# Also: kill Reminders first to unwedge any stuck state from prior runs
pkill -9 -x Reminders 2>/dev/null
sleep 2
open -a Reminders
sleep 10

RESULT=$(claude -p --dangerously-skip-permissions --output-format json \
  "Invoke the recall skill to run the full morning briefing. Use the Skill tool with skill: recall" \
  2>> "$LOG_FILE")

# Extract the text result from JSON output
if [ -n "$RESULT" ]; then
    echo "$RESULT" | jq -r '.result // "No result field in JSON"' >> "$LOG_FILE" 2>&1
else
    echo "ERROR: claude -p returned empty output" >> "$LOG_FILE"
fi

# Create reminders from JSON file (if Claude wrote one)
# This runs as /bin/bash which has permanent TCC approval for Reminders
if [ -f /tmp/recall-reminders.json ]; then
    echo "=== Creating Reminders ===" >> "$LOG_FILE"
    "$HOME/scripts/recall/create-reminders.sh" /tmp/recall-reminders.json "$LOG_FILE"
fi

echo "=== Daily Recall finished at $(date) ===" >> "$LOG_FILE"

# Clean up logs older than 14 days
find "$LOG_DIR" -name "recall-*.log" -mtime +14 -delete 2>/dev/null
