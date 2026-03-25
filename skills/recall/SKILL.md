---
name: recall
description: "Morning briefing with Gmail (4 accounts), iMessage, WhatsApp, auto-discovered services on BOTH Mac and VPS, 7-day session context from both machines, roadmap sync, smart continue prompts, and TODO list pushed to macOS Reminders. Use this skill whenever the user runs /recall, asks for a morning briefing, wants to know what they worked on recently, asks 'what was I doing', 'what do I need to do today', 'catch me up', or wants to start their day. Also triggers for /start-day. Usage: /recall [hours] — focus window for continue prompts (default: most recent per active project). Always loads 7 days of context."
user_invocable: true
---

# Recall — Mac + VPS Morning Briefing

You're giving Thegeshwar his morning briefing. Tell him what needs attention across his Mac AND VPS, where he left off, and how to continue.

The user is non-technical. Keep it clear, focused, and actionable.

**Everything must be in Pacific Time (PST/PDT).** Use `TZ=America/Los_Angeles date +%Y-%m-%d` for today's date and `TZ=America/Los_Angeles date` for times.

**Argument handling:**
- `$ARGUMENTS` contains an optional focus window in hours (e.g., `/recall 6`)
- Parse into `FOCUS_HOURS`. If empty or not a number, leave empty (triggers "most recent per active project" mode)
- Session/git data gathering ALWAYS uses a **7-day window** regardless of the argument
- The argument only controls which tasks get continue prompts in Phase 5

---

## Phase 1: Gather (do ALL in parallel)

### A. Gmail — All Inboxes

Use the Google Workspace MCP to scan each account:

search_gmail_messages(query="is:unread newer_than:1d", user_google_email="thegeshwar@gmail.com", page_size=10)
search_gmail_messages(query="is:unread newer_than:1d", user_google_email="thegeshwar.sivamoorthy@gmail.com", page_size=10)
search_gmail_messages(query="is:unread newer_than:1d", user_google_email="thejeshwa@gmail.com", page_size=10)
search_gmail_messages(query="is:unread newer_than:1d", user_google_email="sivamoorthythegeshwar@gmail.com", page_size=10)

Then batch-read the top 15 most important threads using get_gmail_messages_content_batch.

Categorize each as: Action Required, FYI, or Skip.
Focus on: real people, calendar invites, bills, legal/immigration, clients, projects. Skip newsletters.

### B. iMessage — Recent Conversations

sqlite3 ~/Library/Messages/chat.db "SELECT h.id as contact, m.text, datetime(m.date/1000000000 + 978307200, 'unixepoch', 'localtime') as sent_at, m.is_from_me FROM message m JOIN handle h ON m.handle_id = h.ROWID WHERE m.date > (strftime('%s', 'now', '-1 day') - 978307200) * 1000000000 ORDER BY m.date DESC LIMIT 50;"

Identify conversations needing a reply (last message is from someone else).

### C. WhatsApp — Check for Unreads

Open WhatsApp via osascript, then use accessibility to scan for unread badges. If not logged in, note it and skip.

### D. Mac Session History (7 days)

Read ~/.claude/history.jsonl, filter to last 7 days, deduplicate by sessionId.

### E. Mac Git Activity

For each project in ~/.claude/recall-config.json active_projects list, check git log --since="7 days ago" and git status.

### F. Mac Services

Check docker ps and lsof for common dev ports (3000, 3001, 4000, 5000, 5432, 5678, 8000, 8080).

### G. VPS Full Report (via SSH)

SSH into oracle and gather: session history (7 days), service status (systemctl, docker ps), nginx domain discovery, git activity (7 days), disk usage.

For each discovered VPS domain, health check with `curl -sL` (follow redirects — a 301 that leads to a 502 is DOWN, not healthy). Always check the FINAL response code.

**Known service map (use as reference — auto-discovery should confirm, not contradict):**

| Domain | Port | Project | Notes |
|--------|------|---------|-------|
| qmsleader.com | 3000 | qms-leader (prod) | PRODUCTION — never touch without permission |
| qms.thegeshwar.com | 3001 | qms-leader (dev) | Dev environment, free to modify |
| qmsagents.ai | 3002 | qms-agents | Marketing site, systemd service |
| calldeck.thegeshwar.com | 3003 | calldeck | Cold calling terminal |
| test.dev.thegeshwar.com | 3003 | calldeck (staging) | Staging — port/project may change |
| outreach.dev.thegeshwar.com | 7681 | linkedin-outreach | ttyd web terminal |
| n8n.thegeshwar.com | 5678 | n8n | Workflow automation |
| portfolio.thegeshwar.com | static | nginx | Static site |
| snapfinance.thegeshwar.com | static | nginx | Static site |

test.dev.thegeshwar.com is the only domain whose port/project may change — everything else has a fixed assignment.

**The known service map IS the service dashboard.** Do not parse nginx configs for port numbers — the regex is broken for certbot configs and returns wrong data. Instead:
1. Copy the service map table above directly into the briefing as the VPS Services dashboard
2. Run health checks (curl -sL) for each domain to fill in the health column
3. If a NEW domain is discovered that's NOT in the map, add it with port "unknown" and flag it
4. NEVER show a different port than what the map says — if you see conflicting data from auto-discovery, the map wins, period

### H. Read the Roadmap

gh project item-list 7 --owner thegeshwar --format json --limit 100

### I. Read Existing Reminders (for deduplication)

Read all uncompleted reminders from BOTH "Morning Brief" and "Tasks" lists via osascript. Store the Tasks list — in Phase 4, do NOT add any task that essentially duplicates an existing uncompleted reminder.

```bash
osascript -e '
tell application "Reminders"
    set output to ""
    if exists list "Tasks" then
        set theReminders to every reminder of list "Tasks" whose completed is false
        repeat with r in theReminders
            set output to output & name of r & " ||| " & body of r & return
        end repeat
    end if
    return output
end tell
'
```

### J. Read Memory

Read ~/.claude/projects/-Users-thegeshwar/memory/MEMORY.md and referenced files.

---

## Phase 2: Read Sessions (build per-project arcs)

Sessions are research material — read them to understand what happened, but don't reproduce them.

Read up to 15 most recent sessions from BOTH Mac and VPS. For each, read head -50 and tail -30 of the session JSONL.

Build a per-project arc for EACH active project (Mac and VPS):
- Timeline: what happened each day over 7 days
- Trajectory: ramping up, winding down, or stuck?
- Latest state: what was the user doing in the most recent session?
- User's intent: what are they trying to achieve?
- Blockers/frustrations: anything recurring?

---

## Phase 3: Update the Roadmap

Step 1: Build index of existing items from Phase 1H
Step 2: Match each session (Mac AND VPS) to existing items by project label. Almost never create new items.
Step 3: Apply updates (extend dates, change statuses)
Step 4: Check for duplicates

Reference Field IDs:
Project 7, owner thegeshwar, node ID PVT_kwHOAz2d0c4BSmVV
Status: PVTSSF_lAHOAz2d0c4BSmVVzhAFewY (Todo=f75ad846, In Progress=47fc9ee4, Done=98236657)
Project: PVTSSF_lAHOAz2d0c4BSmVVzhAFey0
Type: PVTSSF_lAHOAz2d0c4BSmVVzhAFe0I (task=bc2735cc, service=bb19aa1b, daily-log=1f543262, blocker=47188be2, decision=856bd4a8)
Start date: PVTF_lAHOAz2d0c4BSmVVzhAFfB0
End date: PVTF_lAHOAz2d0c4BSmVVzhAFfB8
Project labels: linkedin-outreach=62cf1c92, jobagent=4bf8cd59, qms-agents=48f0a5fc, qms-leader=bad90081, calldeck=10bc5236, portfolio=c497a712, snapfinance=bc6154b1, remoteflow=db77ab1f, claude-config=6703f40c, other=51edd8be

---

## Phase 4: Create Reminders

Use TWO separate Reminders lists. **FIRST, ensure both lists exist** before doing anything else:

```bash
osascript -e '
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
'
```

Lists MUST be created under the iCloud account (not "On My Mac") so they sync to iPhone. Run this BEFORE any other Reminders operations. If it fails or times out, retry once. If it fails again, skip Reminders entirely and note it in the briefing.

### List 1: "Morning Brief" — ONE reminder per day

Clear any existing uncompleted reminder in this list, then create one new reminder:
- **name**: Today's date (e.g., "Mar 26 — Morning Brief")
- **body**: The full briefing text including:
  - Inbox summary (unread counts across accounts, action items)
  - iMessage / WhatsApp status
  - VPS services dashboard (domain, port, project, health — the full grid)
  - Mac services status (Docker, dev servers)
  - Mac disk space + VPS disk space
  - Active project summaries (both Mac and VPS)
  - Roadmap changes

This is the complete overview. User taps the reminder on their phone, reads the full brief, gets caught up, checks it off. The brief body should be self-contained — someone reading ONLY this reminder should know the full state of both machines.

```bash
osascript -e '
tell application "Reminders"
    if not (exists list "Morning Brief") then
        make new list with properties {name:"Morning Brief"}
    end if
    -- Clear old uncompleted briefs
    set oldBriefs to every reminder of list "Morning Brief" whose completed is false
    repeat with r in oldBriefs
        delete r
    end repeat
    -- Add today brief
    tell list "Morning Brief"
        make new reminder with properties {name:"DATE — Morning Brief", body:"FULL_BRIEFING_TEXT"}
    end tell
end tell
'
```

### List 2: "Tasks" — One reminder per actionable task

Read existing uncompleted reminders first (deduplication). Only add genuinely NEW tasks.

**Categories (use emoji prefix in the name):**

🔥 = Urgent (something is broken, deadline within 48h, security issue)
💬 = Reply needed (a real person waiting for YOUR response — not group chats, not automated)
🛠 = Continue working (active project with smart continue prompt in body)
📅 = Has a deadline (specific date attached)

**What becomes a task:**
- Broken services or critical errors → 🔥
- Messages from real people where Thegeshwar is the one who needs to reply → 💬
- Active projects with session activity in last 72h on EITHER Mac OR VPS → 🛠 (continue prompt in body). This includes Mac projects like short-form-video, bhavya-mailer, remotion, revenue-agent — not just VPS projects
- Anything with a hard deadline → 📅

**What NEVER becomes a task:**
- "Commit your code" — dev hygiene, not a task
- "Review bank statement" — bank app handles notifications
- "Verify SSH key / security alert" — unless genuinely suspicious (new country, unknown device)
- Automated emails, newsletters, promotions
- Group chat unreads (WhatsApp groups, etc.)
- Vague items with no clear action ("ShivYog webinar this week")
- Anything already resolved in a Claude session today

**🛠 Continue tasks are special:**
- Name: `🛠 Continue: {project name} — {short description}`
- Body: The FULL smart continue prompt from Phase 5 Part 4, ready to copy-paste into a Claude session
- These are the most valuable tasks — they let Thegeshwar tap, read the prompt, paste into Claude, and pick up exactly where he left off
- Create one 🛠 reminder for EVERY active project discovered in Phase 2 — Mac AND VPS. If you found 4 VPS projects and 2 Mac projects with recent activity, that's 6 🛠 reminders. Don't skip Mac projects.

```bash
osascript -e '
tell application "Reminders"
    if not (exists list "Tasks") then
        make new list with properties {name:"Tasks"}
    end if
    tell list "Tasks"
        make new reminder with properties {name:"EMOJI TASK_NAME", body:"CONTEXT_OR_CONTINUE_PROMPT"}
    end tell
end tell
'
```

**Deduplication rules:**
- Read all uncompleted reminders from "Tasks" list before adding
- If a task essentially matches an existing one (even different wording), skip it
- 🛠 Continue tasks: UPDATE the body if the continue prompt has changed (project progressed), but don't create a duplicate
- Max 15 tasks total in the list at any time. If at 15, don't add more — mention overflow in the brief

---

## Phase 5: Present the Briefing

Keep it compact (~60 lines max).

Part 1: Communications (inbox summary, action required emails, iMessage, WhatsApp)

Part 2: VPS Services (auto-discovered dashboard grid with domain, port, project, health check mark or X)
Domain filtering: When multiple domains share same port, show only primary domain.

Part 3: Mac Services (Docker containers, dev servers)

Part 4: Active Tasks with Smart Continue Prompts

Determine which tasks get continue prompts:
- If FOCUS_HOURS set: only tasks with activity in last FOCUS_HOURS hours
- If empty: most recent task per active project within 72 hours

Active project = has git/session activity in last 72 hours on EITHER Mac or VPS. Check BOTH:
- Mac: sessions in ~/.claude/history.jsonl + git activity in ~/Projects/
- VPS: sessions from SSH + git activity from SSH
A project doesn't need to be on the roadmap to get a continue prompt — if there's recent session activity, it qualifies. Mac projects (bhavya-mailer, remotion, short-form-video, shivyog-rails) and VPS projects (qms-leader, calldeck, linkedin-outreach, etc.) are BOTH tracked.
Stalled projects: In Progress but no activity in 72 hours — one-liner, no continue prompt.

For each active task:

{n}. {Task Name} ({project} — {Mac/VPS})
> {2-3 sentence summary. Plain language.}
> To continue:
> {Smart continue prompt — first person, casual, captures the journey}

Smart Continue Prompt Construction rules:
1. Use the per-project arc from Phase 2
2. Identify trajectory (ramping up, stuck, wrapping up)
3. Write in first person, casually — sound like the user
4. Include specific technical details (file paths, what was last touched)
5. Capture emotional context
6. End with clear next action + "Check the GitHub Project board and update it."
7. For Mac projects: reference ~/Projects/{project} and note this runs on the Mac (not VPS)
8. For VPS projects: reference the VPS path

GOOD example: "I've been building out the short-form-video project at ~/Projects/short-form-video all week — got the HardCutMontage composition working, added subtitle overlays, and built an asset generator. I'm on a roll. Next I need to polish the duration calculator and test with real video assets. Check the GitHub Project board and update it."

BAD example: "I'm working on short-form-video. Last session I did some work. Continue." — No arc, no momentum, no specifics.

Part 5: Reminders Summary

```
Morning Brief added to "Morning Brief" list.

Tasks list:
  New: 🔥 Fix VPS disk space, 🛠 Continue: CallDeck
  Carrying over: 3 tasks from previous days
  Total open: 5 tasks
```

Part 6: Recently Completed + Roadmap Changes (one line each)

---

Proposed Memory Changes

Only propose if something genuinely new was learned. If nothing: "No memory changes."
Want me to save these? Yes / No / Edit

---

Rules:
1. Sessions are research, not output. Never show session log tables.
2. One roadmap item per project. Build the index first, match by project label.
3. Never put numbers in roadmap titles or memory proposals.
4. Everything in Pacific Time.
5. Continue prompts are messages FROM the user TO a fresh Claude. Conversational, not commands.
6. VPS services section is always a visual grid with domain, port, project, and health.
7. Always gather 7 days of data. Argument only controls focus window for continue prompts.
8. Build per-project arcs before writing continue prompts. The arc makes prompts smart.
9. Auto-discover VPS services from nginx and repos from filesystem. Mac uses config file.
10. NEVER re-add a task that already exists in Reminders. Check first, add only new.
11. Comms (email, iMessage, WhatsApp) scan last 24h. Git/sessions scan 7 days.
12. If SSH to VPS fails, present Mac-only briefing and note VPS is unreachable.
13. If a Gmail account fails auth, note it and continue with the others.
