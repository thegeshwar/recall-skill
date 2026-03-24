---
name: recall
description: "Morning briefing that scans Gmail inboxes, iMessage, WhatsApp, git activity, running services, and Claude session history — then synthesizes a curated daily TODO list pushed to macOS Reminders. Use this skill whenever the user runs /recall, asks for a morning briefing, wants to know what they worked on recently, asks 'what was I doing', 'what do I need to do today', 'catch me up', or wants to start their day. Also triggers for /start-day. Usage: /recall [hours] — optional focus window (default: 24h for comms, 7d for git/sessions)."
user_invocable: true
---

# Recall — Mac Morning Briefing

You're giving Thegeshwar his morning briefing. Tell him what needs attention, where he left off, and what to do today.

Keep it clear, focused, and actionable. No jargon. Think of yourself as a personal chief of staff.

**Timezone: Pacific Time (PST/PDT).** The system may run in UTC. Use `TZ=America/Los_Angeles date` for current time.

**Config file:** Read `~/.claude/recall-config.json` for active projects and preferences. If it doesn't exist, use defaults.

**Argument handling:**
- `$ARGUMENTS` may contain a focus window in hours (e.g., `/recall 6`)
- Parse into `FOCUS_HOURS`. If empty, default to 24h for comms, 7d for git/sessions
- Comms scanning (email, iMessage, WhatsApp) uses `FOCUS_HOURS` or 24h
- Git and session history always scan 7 days

---

## Phase 1: Gather (do ALL of these in parallel using subagents)

### A. Gmail — All Inboxes

Use the Gmail MCP tools to scan for unread and important emails.

For each connected account:
```
gmail_search_messages with query: "is:unread newer_than:1d"
```

Then for the top 15 most important-looking threads, read them:
```
gmail_read_message for each
```

Categorize each email as:
- **Action Required** — needs a reply, decision, or task from Thegeshwar
- **FYI** — informational, no action needed
- **Spam/Promo** — can be ignored

Focus on: anything from real people, calendar invites, bills, legal/immigration docs, client communications, job-related, or project-related. Deprioritize newsletters and marketing.

### B. iMessage — Recent Conversations

Query the iMessage database directly:

```bash
sqlite3 ~/Library/Messages/chat.db "
SELECT
  h.id as contact,
  m.text,
  datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as sent_at,
  m.is_from_me
FROM message m
JOIN handle h ON m.handle_id = h.ROWID
WHERE m.date > (strftime('%s', 'now', '-1 day') - 978307200) * 1000000000
ORDER BY m.date DESC
LIMIT 50;
"
```

Identify conversations that need a reply (messages from others where Thegeshwar hasn't responded).

### C. WhatsApp — Check for Unreads

Open WhatsApp and check for unread indicators:

```bash
osascript -e 'tell application "WhatsApp" to activate'
sleep 2
```

Then use accessibility to scan for unread badges:
```bash
osascript -e '
tell application "System Events"
    tell process "WhatsApp"
        set output to ""
        set allElems to entire contents of window 1
        repeat with elem in allElems
            try
                set elemDesc to description of elem
                set elemVal to value of elem
                if elemDesc is not missing value then
                    set output to output & elemDesc & " | " & elemVal & return
                end if
            end try
        end repeat
        return output
    end tell
end tell
'
```

If WhatsApp is not logged in, note that in the briefing and skip.

### D. Git Activity — Active Projects

Read project list from `~/.claude/recall-config.json` (field: `active_projects`), or default to: bhavya-mailer, remotion-project, short-form-video, shivyog-rails.

For each active project, check recent commits:

```bash
for project in $(cat ~/.claude/recall-config.json 2>/dev/null | python3 -c "import sys,json; print(' '.join(json.load(sys.stdin).get('active_projects',[])))" 2>/dev/null || echo "bhavya-mailer remotion-project short-form-video shivyog-rails"); do
  dir=~/Projects/$project
  if [ -d "$dir/.git" ]; then
    echo "=== $project ==="
    cd "$dir"
    git log --oneline --since="7 days ago" --all 2>/dev/null | head -10
    git status --short 2>/dev/null
    echo ""
  fi
done
```

### E. Running Services

```bash
# Docker containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null

# Any dev servers on common ports
lsof -iTCP -sTCP:LISTEN -P 2>/dev/null | grep -E ":(3000|3001|4000|5000|5432|5678|8000|8080)" | awk '{print $1, $9}'
```

### F. Claude Code Session History (7 days)

```bash
CUTOFF=$(python3 -c "import time; print(int((time.time() - 7*86400) * 1000))")
cat ~/.claude/history.jsonl | python3 -c "
import sys, json
cutoff = ${CUTOFF}
seen = set()
for line in sys.stdin:
    try:
        entry = json.loads(line.strip())
        ts = entry.get('timestamp', 0)
        if ts >= cutoff:
            sid = entry.get('sessionId','')
            proj = entry.get('project','')
            display = entry.get('display','')[:120]
            if sid and sid not in seen:
                seen.add(sid)
                print(json.dumps({'sessionId': sid, 'project': proj, 'display': display, 'timestamp': ts}))
    except:
        pass
"
```

### G. Read Memory

Read `~/.claude/projects/-Users-thegeshwar/memory/MEMORY.md` and any referenced memory files for ongoing context about projects, user preferences, and active work.

---

## Phase 2: Synthesize

Now that you have all the data, organize it into a briefing. Think about what Thegeshwar actually needs to do today vs. what's just noise.

### Priority Framework

1. **Urgent**: Time-sensitive emails (bills, legal, expiring deadlines), unanswered messages from important contacts, broken services
2. **Important**: Project-related communications, PRs needing review, active project next steps
3. **Routine**: FYI emails, general catch-up, low-priority messages
4. **Skip**: Spam, promotions, automated notifications with no action needed

---

## Phase 3: Create TODO List in Reminders

Append today's actionable items to macOS Reminders under a list called "Daily Briefing". Do NOT clear existing items — completed items stay as a record, and uncompleted items from previous days naturally carry forward.

Prefix each new item with today's date so items are easy to identify by day.

```bash
TODAY=$(TZ=America/Los_Angeles date +"%b %d")

osascript -e '
tell application "Reminders"
    -- Create list if it doesnt exist
    if not (exists list "Daily Briefing") then
        make new list with properties {name:"Daily Briefing"}
    end if

    tell list "Daily Briefing"
        make new reminder with properties {name:"'"${TODAY}"' — TODO_ITEM_HERE", body:"CONTEXT_HERE"}
    end tell
end tell
'
```

Run one `osascript` call per reminder item, or batch them in a single script. Each reminder should have:
- **name**: Date prefix + short actionable task (e.g., "Mar 25 — Reply to Bhavya re: mailer deploy")
- **body**: Context about why and what to say/do

Limit to 10-15 new items max per day. Prioritize ruthlessly.

---

## Phase 4: Present the Briefing

Format the briefing like this:

```
Good morning! Here's your briefing for [today's date].

## Inbox Summary
[X unread across Y accounts]
- [Key emails needing action, grouped by urgency]

## Messages
### iMessage
- [Conversations needing reply]

### WhatsApp
- [Status or unreads]

## Projects
- [What changed in the last 7 days across active projects]
- [Any broken services or issues]

## Your TODO for Today
1. [Most important task]
2. [Second most important]
...

These have been added to your Reminders app under "Daily Briefing".

## What You Were Working On
[Summary of recent Claude sessions — what was being built/fixed/explored]
```

Keep each section tight. If a section has nothing to report, say so in one line and move on. The whole briefing should be scannable in under 2 minutes.

---

## Notes

- If WhatsApp isn't logged in, just note it and move on
- If Gmail MCP isn't responding, try the search with fewer results
- If a git repo doesn't exist in ~/Projects/, skip it silently
- Don't expose full email contents — summarize what matters
- Existing reminders are preserved — only new items are appended each day
- Once a week (Sunday), mention how many uncompleted items have piled up and suggest cleanup
