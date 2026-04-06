---
name: recall
description: "Morning briefing and ADHD project management system. Scans Gmail (4 accounts), iMessage, WhatsApp, Mac + VPS services, 7-day session/git history, and auto-ranks projects by activity. Pushes a dashboard notification + task list with named session commands to macOS Reminders. Use whenever the user runs /recall, asks for a morning briefing, 'what was I doing', 'catch me up', 'what do I need to do', or wants to start their day. Also triggers for /start-day. Usage: /recall [hours]"
user_invocable: true
---

# Recall — Morning Briefing + ADHD Project Management

You're Thegeshwar's external executive function. Your job: gather everything, auto-rank his projects by actual activity, build a clear dashboard, and push it to his phone so he can start his day knowing exactly where everything stands.

The user has ADHD. He has 18+ projects. Things slip through cracks. This system prevents that by:
- Auto-ranking projects by recency (no manual management, no asking him to choose)
- Showing the top 3 as "focus" with real status + named session commands + continue prompts
- Keeping everything else visible but quiet
- Rebuilding the full task list fresh every run (no stale items)

**Everything in Pacific Time.** Use `TZ=America/Los_Angeles date +%Y-%m-%d` for today's date.

**Argument handling:**
- `$ARGUMENTS` = optional focus window in hours (e.g., `/recall 6`)
- Session/git gathering ALWAYS uses a **7-day window**
- The argument only controls which tasks get continue prompts in Phase 5

---

## Phase 1: Gather (do ALL in parallel)

### A. Gmail — All Inboxes

search_gmail_messages(query="is:unread newer_than:1d", user_google_email="thegeshwar@gmail.com", page_size=10)
search_gmail_messages(query="is:unread newer_than:1d", user_google_email="thegeshwar.sivamoorthy@gmail.com", page_size=10)
search_gmail_messages(query="is:unread newer_than:1d", user_google_email="thejeshwa@gmail.com", page_size=10)
search_gmail_messages(query="is:unread newer_than:1d", user_google_email="sivamoorthythegeshwar@gmail.com", page_size=10)

Batch-read the top 15 important threads. Categorize: Action Required, FYI, or Skip. Focus on real people, calendar invites, bills, legal/immigration, clients. Skip newsletters.

### B. iMessage — Recent Conversations

```bash
~/scripts/recall/imessage-scan.sh
```

This wraps `imessage-exporter` (brew installed) and outputs a JSON array of conversations with activity in the last 24h. **DO NOT use raw sqlite on chat.db** — the `text` column is NULL for ~16% of messages on macOS Ventura+ (text moved to `attributedBody` binary blob), and there's no contact-name resolution. The wrapper handles both.

Each entry: `{contact, last_msg, last_time, last_from_me, needs_reply, msg_count_24h}`. Contacts are real names (auto-resolved from Contacts.app's AddressBook DB by imessage-exporter — no permission prompts needed).

Sorted with `needs_reply: true` first. Use those for the 💬 Reply task reminders. **Never invent contact names or pull them from MEMORY.md** — only use what this script returns. If `contact` looks like a phone number, that person isn't in Contacts; show the number as-is.

### C. WhatsApp — Check for Unreads

Open WhatsApp via osascript, scan for unread badges. If not logged in, skip.

### D. Mac Session History (7 days)

Read ~/.claude/history.jsonl, filter to last 7 days, deduplicate by sessionId.

### E. Project Registry + Git Activity

Read `~/.claude/project-registry.json`. For EVERY project (not just focus ones), check:
- `git log --since="7 days ago"` — recent commits
- `git status` — uncommitted work
- Update `last_activity` in the registry based on findings

### F. Mac Services

Check `docker ps` and `lsof` for common dev ports (3000, 3001, 4000, 5000, 5432, 5678, 8000, 8080).

### G. VPS Full Report (via SSH)

SSH into oracle. Gather: session history (7 days), service status (systemctl, docker ps), git activity for all VPS projects, disk usage.

Health check every domain with `curl -sL` (follow redirects — check FINAL response code).

**Known service map (source of truth — auto-discovery must not contradict):**

| Domain | Port | Project | Notes |
|--------|------|---------|-------|
| qmsleader.com | 3000 | qms-leader (prod) | PRODUCTION |
| qms.thegeshwar.com | 3001 | qms-leader (dev) | Dev |
| qmsagents.ai | 3002 | qms-agents | Marketing |
| calldeck.thegeshwar.com | 3003 | calldeck | Cold calling |
| test.dev.thegeshwar.com | 3003 | calldeck (staging) | Staging |
| outreach.dev.thegeshwar.com | 7681 | linkedin-outreach | ttyd |
| n8n.thegeshwar.com | 5678 | n8n | Workflows |
| portfolio.thegeshwar.com | static | nginx | Static |
| snapfinance.thegeshwar.com | static | nginx | Static |

### H. Roadmap

```bash
gh project item-list 7 --owner thegeshwar --format json --limit 100
```

### I. Read Memory

Read ~/.claude/projects/-Users-thegeshwar/memory/MEMORY.md and referenced files.

---

## Phase 2: Auto-Rank Projects

The user does not pick focus projects — the system ranks them automatically based on actual activity.

### Step 1: Score every project

For each project in the registry, calculate a recency score:
- Use `last_activity` date from git findings in Phase 1E
- If a project has session activity (from Phase 1D or VPS sessions), use the most recent of git or session date
- Score = days since last activity (lower = more recent = higher rank)

### Step 2: Assign statuses

Sort all projects by recency score (most recent first).
- **Top 3** → `status: "focus"`
- **Projects 4+** with activity in last 14 days → `status: "active"`
- **Projects with no activity in 14+ days** → `status: "paused"`

### Step 3: Write updated registry

Write the updated `~/.claude/project-registry.json` with new statuses and dates.

### Step 4: Detect transitions

Note any projects that changed status since last run:
- Newly promoted to focus → user started working on it
- Dropped from focus → user hasn't touched it
- Include transitions in the briefing

---

## Phase 2B: Read Sessions (build arcs for focus projects)

Sessions are research material — read them to understand context, don't reproduce them.

Read up to 15 most recent sessions from BOTH Mac and VPS. For each, read head -50 and tail -30.

Build a per-project arc for each **focus** project:
- Timeline: what happened each day over 7 days
- Trajectory: ramping up, winding down, or stuck?
- Latest state: what was the user doing most recently?
- What they're trying to achieve
- Blockers/frustrations

Also build a lighter 1-line status for each **active** project.

---

## Phase 3: Update the Roadmap

Step 1: Build index of existing items from Phase 1H
Step 2: Match sessions to existing items by project label
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

**Recall owns exactly two lists: "Morning Brief" and "Tasks". Never touch any other list.**

**CRITICAL — every osascript call in this phase MUST be wrapped in `timeout 15`**, e.g. `timeout 15 osascript -e '...'`. Reminders.app talks to `cloudd` (iCloud sync daemon); when `cloudd` wedges, AppleScript hangs forever instead of erroring. A timeout is the only safe escape.

If ANY osascript in this phase exits non-zero (including exit 124 = timeout), retry **once**. If it fails again: skip the rest of Phase 4, note "⚠️ Reminders unavailable (cloudd wedged?) — dashboard text only" in the final briefing, and **still complete Phase 5 (notification)**. Never let Reminders failures eat the whole run.

### Step 1: Ensure lists exist (iCloud, not "On My Mac")

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

If this fails, retry once. If it fails again, skip Reminders and note it in the briefing.

### Step 2: Wipe both lists clean

Every run starts fresh. Delete ALL uncompleted reminders from both lists. No stale items ever.

```bash
osascript -e '
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
'
```

### Step 3: Create Morning Brief (1 notification — this buzzes)

One reminder with `remind me date` set to now. This is the ONE notification that hits the phone. The body is the complete dashboard.

**Body structure:**

```
FOCUS (your top 3 right now)
1. {name} ({Mac/VPS}) — {real 1-line status from session/git data}
   Start: claude --name "{shortname}"
2. {name} ({Mac/VPS}) — {real 1-line status}
   Start: claude --name "{shortname}"
3. {name} ({Mac/VPS}) — {real 1-line status}
   Start: claude --name "{shortname}"

ACTIVE (touched in last 14 days)
• {name} — {1-line status}
• {name} — {1-line status}

PAUSED (14+ days untouched)
• {name} — last {date} ({N} days ago)
• {name} — last {date} ({N} days ago)

COMMS
• Gmail: {X} unread ({Y} action required)
• iMessage: {who needs reply, or "all clear"}
• WhatsApp: {status}

SERVICES
{domain} | {health ✓/✗}
...

SYSTEM
Mac disk: {X}% | VPS disk: {X}%
```

The 1-line status for each focus project must be REAL — pulled from actual git commits or session data. Not generic descriptions. Examples:
- GOOD: "BiRefNet silhouettes done, 3D hero mesh demos deployed to test.dev"
- GOOD: "auth 401 blocking submissions, 124 successful before failure"
- BAD: "In progress" / "Working on features" / "Active development"

```bash
osascript -e '
tell application "Reminders"
    tell list "Morning Brief"
        make new reminder with properties {name:"DATE — Morning Brief", body:"DASHBOARD_TEXT", remind me date:current date}
    end tell
end tell
'
```

### Step 4: Create Task reminders

**Focus projects (top 3) — one-paste session start with continue prompt baked in:**

Reminder name: `🎯 {project name} — {short status}`

Reminder body — the start command IS the continue prompt (one copy-paste launches a named session with the prompt as the first message):

```
claude --name "{shortname}" "{Full continue prompt — first person, casual, with arc and specifics}"

Resume: claude --resume "{shortname}"
```

The `claude --name "{shortname}" "{prompt}"` format starts a named interactive session and sends the continue prompt as the first message automatically. The user copies ONE line, pastes it in the terminal, and they're working. The resume command is on a separate line below for when the terminal crashes.

**Session naming rules:**
- Use a short, memorable, lowercase name: `nadhirah`, `infographic`, `jobagent`, `calldeck`, `remoteflow`, etc.
- Same name every day — no dates. Tomorrow's run creates fresh tasks with the same names.
- Derive from the project's `name` field, shortened to one word if possible.
- `--name` starts a fresh named interactive session. `--resume` reconnects if the terminal dies.

**The workflow this enables:**
1. User opens Reminders on phone, taps a 🎯 focus project
2. Opens Termius (or any terminal), copies the first line of the body
3. Pastes it — session starts with name AND continue prompt in one shot
4. Terminal dies (network issues, Termius crash)? Copies the `claude --resume "..."` line — back in same session
5. Next morning: recall wipes everything, creates fresh tasks with the same session names

`remind me date`: NOT set (no buzz — the Morning Brief already buzzed)

---

**Active projects (4-14 days) — one-paste start with brief context:**

Reminder name: `🛠 {project name} — {1-line status}`

Reminder body:
```
claude --name "{shortname}" "{Brief context — 1-2 sentences from git/session data. Working on this will auto-promote it to focus.}"

Resume: claude --resume "{shortname}"
```

`remind me date`: NOT set

---

**Paused projects (14+ days) — gentle visibility:**

Reminder name: `💤 {project name} — {N} days`

Reminder body: Last known state in 1 line.

`remind me date`: NOT set

---

**Urgent/reply items — these DO buzz:**

```
🔥 {description}  →  remind me date: current date (buzzes immediately)
💬 Reply: {person}  →  remind me date: current date (buzzes immediately)
```

---

**Creation order** (so they appear correctly in list):
1. 🔥 Urgent (if any)
2. 💬 Reply needed (if any)
3. 🎯 Focus projects (top 3, with full session kit)
4. 🛠 Active projects (with start command)
5. 💤 Paused projects

---

## Phase 5: Present the Briefing

Keep it compact (~80 lines max).

### Part 1: Communications
Inbox summary, action required emails, iMessage, WhatsApp.

### Part 2: Focus Projects (your top 3)

For each focus project, show the session commands and continue prompt:

```
1. {Project Name} ({Mac/VPS})
   Status: {2-3 sentence real status from session data}
   Start: claude --name "{shortname}"
   Resume: claude --resume "{shortname}"
   
   To continue:
   "{Full continue prompt — first person, casual, captures the journey}"
```

**Continue Prompt Construction Rules:**

The continue prompt is the most valuable output of recall. It's a message FROM the user TO a fresh Claude session. It must:

1. Use the per-project arc from Phase 2B — what happened over the last few days, not just the last commit
2. Sound like the user talking casually ("I've been working on...", "I got stuck on...", "Next I need to...")
3. Include specific technical details: file paths, function names, what was last modified, error messages
4. Capture the trajectory: is this ramping up, stuck, or almost done?
5. End with a clear next action + "Check the GitHub Project board and update it."
6. Reference the actual project path from the registry

GOOD: "I've been working on Nadhirah's dance portfolio at ~/nadhirah-portfolio — switched from ISNet to BiRefNet_lite for silhouette extraction because ISNet had a leg-merge artifact from downsampling. Reprocessed all 1920 frames via PyTorch+MPS with threshold bumped to 200. The DanceSection multi-span edge-detect fix is deployed to test.dev. For the hero section, particles were unrecognizable so I built 3 Three.js mesh-frag demos (marble+gold shader, shape cycling) at test.dev.thegeshwar.com/3d-demos/. Next: pick the best 3D approach and integrate the silhouette frames into DanceSection.tsx. Check the GitHub Project board and update it."

BAD: "I'm working on nadhirah-portfolio. Continue the silhouette work." — No arc, no specifics, useless.

### Part 3: Active Projects (brief)
One line each with start command.

### Part 4: Paused Projects
List with last-touched dates.

### Part 5: VPS Services
Dashboard grid: domain, port, project, health.

### Part 6: System
Mac services, disk space, VPS disk space.

### Part 7: Reminders Summary

```
📱 Morning Brief notification sent.

Tasks rebuilt:
  🎯 3 focus projects (with session commands + continue prompts)
  🛠 N active projects (with start commands)
  💤 N paused projects
  🔥 N urgent (if any — these buzzed)
  💬 N replies needed (if any — these buzzed)
```

### Part 8: Transitions
If any projects changed rank since last run, note it:
```
↑ calldeck promoted to focus (you worked on it yesterday)
↓ jobagent dropped to active (no activity in 4 days)
```

---

Proposed Memory Changes

Only propose if something genuinely new was learned. If nothing: "No memory changes."
Want me to save these? Yes / No / Edit

---

## Rules

1. Sessions are research, not output. Never show session log tables.
2. Everything in Pacific Time.
3. **Auto-rank, don't ask.** The user never picks focus projects. The system ranks by recency. Top 3 = focus. Period.
4. **Wipe then rebuild.** Every run deletes all uncompleted reminders from "Morning Brief" and "Tasks", then creates fresh ones.
5. **Only Morning Brief, 🔥, and 💬 buzz.** Everything else has no `remind me date`. This prevents notification overload.
6. **Recall only touches "Morning Brief" and "Tasks" lists.** Never touch Grocery or any other list.
7. **Real statuses only.** Every project's status line must come from actual git/session data. Generic descriptions like "in progress" are forbidden.
8. **Continue prompts need arcs.** Read sessions, understand the journey, write prompts that capture momentum and specifics. A shallow prompt is worse than no prompt.
9. **Every project appears somewhere.** Focus (top 3), active (14 days), or paused (14+ days). Nothing is left out.
10. **The registry auto-updates every run.** New repos get added, dates get refreshed, statuses get recalculated. No manual management.
11. **Named sessions.** Every focus project gets `claude --name "{shortname}"` and `claude --resume "{shortname}"` commands. Same short names every day (no dates). This lets the user resume after terminal crashes.
12. If SSH to VPS fails, present Mac-only briefing and note VPS is unreachable.
13. If a Gmail account fails auth, note it and continue with others.
14. One roadmap item per project. Build index first, match by project label.
15. Comms scan last 24h. Git/sessions scan 7 days.
16. The service map table is the source of truth for VPS domains/ports. Never show different ports than the map.
