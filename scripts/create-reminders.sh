#!/bin/bash
# create-reminders.sh — Creates Reminders from JSON file
# Called by daily-recall.sh AFTER Claude outputs reminder data.
# Runs as /bin/bash which has permanent TCC approval for Reminders + AppleEvents.
# This avoids the TCC permission popup that breaks every Claude CLI update.
#
# Input: JSON file path as $1 (default: /tmp/recall-reminders.json)
# Format: { "morning_brief": {...}, "tasks": [...] }

set -euo pipefail

JSON_FILE="${1:-/tmp/recall-reminders.json}"
LOG_FILE="${2:-/dev/stderr}"

log() { echo "[reminders] $*" >> "$LOG_FILE"; }

if [ ! -f "$JSON_FILE" ]; then
    log "No reminder data file found at $JSON_FILE — skipping"
    exit 0
fi

# Validate JSON
if ! jq empty "$JSON_FILE" 2>/dev/null; then
    log "Invalid JSON in $JSON_FILE — skipping"
    exit 1
fi

# Step 1: Ensure lists exist (iCloud)
log "Ensuring lists exist..."
timeout 15 osascript -e '
tell application "Reminders"
    if not (exists list "Morning Brief") then
        tell account "iCloud"
            make new list with properties {name:"Morning Brief"}
        end tell
    end if
    if not (exists list "Tasks") then
        tell account "iCloud"
            make new list with properties {name:"Tasks"}
        end tell
    end if
end tell
' 2>>"$LOG_FILE" || {
    log "Failed to ensure lists exist — retrying once"
    sleep 2
    timeout 15 osascript -e '
    tell application "Reminders"
        if not (exists list "Morning Brief") then
            tell account "iCloud"
                make new list with properties {name:"Morning Brief"}
            end tell
        end if
        if not (exists list "Tasks") then
            tell account "iCloud"
                make new list with properties {name:"Tasks"}
            end tell
        end if
    end tell
    ' 2>>"$LOG_FILE" || { log "Lists creation failed twice — aborting"; exit 1; }
}

# Step 2: Wipe both lists clean
log "Wiping existing reminders..."
timeout 15 osascript -e '
tell application "Reminders"
    if exists list "Morning Brief" then
        set oldItems to every reminder of list "Morning Brief" whose completed is false
        repeat with r in oldItems
            delete r
        end repeat
    end if
    if exists list "Tasks" then
        set oldItems to every reminder of list "Tasks" whose completed is false
        repeat with r in oldItems
            delete r
        end repeat
    end if
end tell
' 2>>"$LOG_FILE" || log "Warning: wipe failed, continuing anyway"

# Step 3: Create Morning Brief reminder (this one buzzes)
BRIEF_NAME=$(jq -r '.morning_brief.name // empty' "$JSON_FILE")
BRIEF_BODY=$(jq -r '.morning_brief.body // empty' "$JSON_FILE")

if [ -n "$BRIEF_NAME" ] && [ -n "$BRIEF_BODY" ]; then
    log "Creating Morning Brief..."
    # Escape backslashes and quotes for AppleScript
    ESCAPED_NAME=$(echo "$BRIEF_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
    ESCAPED_BODY=$(echo "$BRIEF_BODY" | sed 's/\\/\\\\/g; s/"/\\"/g')

    timeout 15 osascript -e "
    tell application \"Reminders\"
        tell list \"Morning Brief\"
            make new reminder with properties {name:\"${ESCAPED_NAME}\", body:\"${ESCAPED_BODY}\", remind me date:current date}
        end tell
    end tell
    " 2>>"$LOG_FILE" || log "Warning: Morning Brief creation failed"
else
    log "No morning brief data found in JSON"
fi

# Step 4: Create task reminders
TASK_COUNT=$(jq -r '.tasks | length' "$JSON_FILE" 2>/dev/null || echo "0")
log "Creating $TASK_COUNT task reminders..."

for i in $(seq 0 $((TASK_COUNT - 1))); do
    TASK_NAME=$(jq -r ".tasks[$i].name // empty" "$JSON_FILE")
    TASK_BODY=$(jq -r ".tasks[$i].body // empty" "$JSON_FILE")
    TASK_BUZZ=$(jq -r ".tasks[$i].buzz // false" "$JSON_FILE")

    if [ -z "$TASK_NAME" ]; then
        continue
    fi

    ESCAPED_TASK_NAME=$(echo "$TASK_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
    ESCAPED_TASK_BODY=$(echo "$TASK_BODY" | sed 's/\\/\\\\/g; s/"/\\"/g')

    if [ "$TASK_BUZZ" = "true" ]; then
        # Urgent/reply items — set remind me date to buzz
        timeout 15 osascript -e "
        tell application \"Reminders\"
            tell list \"Tasks\"
                make new reminder with properties {name:\"${ESCAPED_TASK_NAME}\", body:\"${ESCAPED_TASK_BODY}\", remind me date:current date}
            end tell
        end tell
        " 2>>"$LOG_FILE" || log "Warning: Failed to create task: $TASK_NAME"
    else
        # Normal tasks — no buzz
        timeout 15 osascript -e "
        tell application \"Reminders\"
            tell list \"Tasks\"
                make new reminder with properties {name:\"${ESCAPED_TASK_NAME}\", body:\"${ESCAPED_TASK_BODY}\"}
            end tell
        end tell
        " 2>>"$LOG_FILE" || log "Warning: Failed to create task: $TASK_NAME"
    fi
done

log "Done — created Morning Brief + $TASK_COUNT tasks"

# Clean up
rm -f "$JSON_FILE"
