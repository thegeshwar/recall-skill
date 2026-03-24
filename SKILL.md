---
name: recall
description: "Morning briefing that reads Claude sessions, updates a GitHub Project roadmap timeline, checks service health, and gives a focused sitrep on active tasks with continue prompts. Use this skill whenever the user runs /recall, asks for a morning briefing, wants to know what they worked on recently, asks 'what was I doing', or wants to catch up on recent work. Also triggers for /start-day since this replaces it. Usage: /recall [hours] — defaults to 24."
user_invocable: true
---

# Recall

You're giving the user their morning briefing. Tell them what they're actively working on, where they left off, and how to continue.

The user is non-technical. Keep it clear, focused, and actionable.

**Everything must be in Pacific Time (PST/PDT).** The server runs in UTC. Use `TZ=America/Los_Angeles date +%Y-%m-%d` for today's date and `TZ=America/Los_Angeles date` for times.

`$ARGUMENTS` contains the lookback hours. Default to 24 if empty or not a number.

---

## Phase 1: Gather (do ALL in parallel)

### A. Find sessions

```bash
HOURS=${ARGUMENTS:-24}
HOURS=$(echo "$HOURS" | grep -oE '^[0-9]+$' || echo 24)
CUTOFF=$(date -d "$HOURS hours ago" +%s)000
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
            display = entry.get('display','')[:100]
            if sid and sid not in seen:
                seen.add(sid)
                print(json.dumps({'sessionId': sid, 'project': proj, 'display': display, 'timestamp': ts}))
    except:
        pass
"
```

### B. Read the roadmap

```bash
gh project item-list 7 --owner thegeshwar --format json --limit 100
```

### C. Read memory

Read `~/.claude/projects/-home-ubuntu/memory/MEMORY.md` and referenced files for context.

### D. Service health check

```bash
for url in https://qmsleader.com https://qms.thegeshwar.com https://qmsagents.ai https://outreach.dev.thegeshwar.com https://n8n.thegeshwar.com https://portfolio.thegeshwar.com https://snapfinance.thegeshwar.com; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
  echo "$url → $code"
done
systemctl is-active qms-leader 2>/dev/null
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -20
```

### E. Git activity

```bash
for dir in /home/ubuntu/qms-leader /home/ubuntu/portfolio /home/ubuntu/SnapFinance /home/ubuntu/jobagent /home/ubuntu/job-applier /home/ubuntu/qms-agents /home/ubuntu/linkedin-outreach /home/ubuntu/calldeck; do
  if [ -d "$dir/.git" ]; then
    echo "=== $(basename $dir) ==="
    cd "$dir" && git log --since="${HOURS} hours ago" --oneline --all 2>/dev/null
  fi
done
```

---

## Phase 2: Read Sessions (be selective)

Sessions are research material — read them to understand what happened, but don't reproduce them in the output.

**If there are more than 10 sessions**, only read the most recent 10. Skip older ones — the roadmap already has history.

For each session:
1. Convert project path: `/home/ubuntu/foo` → `-home-ubuntu-foo`
2. Session log at: `~/.claude/projects/{sanitized-name}/{sessionId}.jsonl`
3. Read only `head -50` and `tail -30` — just enough to get intent and outcome
4. Write down ONE line: "{session} → advanced {project} work on {topic}: {outcome}"

---

## Phase 3: Update the Roadmap

### Step 1: Build an index of existing items

Before touching anything, list every non-SERVICE item from the roadmap you read in Phase 1B. Write it down:

```
EXISTING ITEMS:
- {item_id} | {project_label} | {status} | {title}
- {item_id} | {project_label} | {status} | {title}
...
```

This is your lookup table. You will use it in Step 2.

### Step 2: Match each session to an existing item

For each session you read in Phase 2, find its match in the index:
- Look at what project the session worked on (jobagent, linkedin-outreach, calldeck, etc.)
- Find the item in your index with that project label
- That's the match. All work on the same project goes to the same item.

**You should almost never need to create a new item.** Only create one if a session worked on a project that has ZERO items in the index. This is rare — most projects already have an item.

### Step 3: Apply updates

For each item that was touched by sessions:
- Extend End date to today (PST) if work happened today
- Change status to In Progress if it was Todo and work happened
- Change status to Done only if you're confident the work is finished

For items NOT touched by any session: leave them alone.

### Step 4: Check for duplicates

If two items share the same project label, merge them: delete the newer one, keep the older one.

### Reference: Field IDs

**Project**: `7` (owner: `thegeshwar`, node ID: `PVT_kwHOAz2d0c4BSmVV`)

| Field | ID |
|-------|-----|
| Status | `PVTSSF_lAHOAz2d0c4BSmVVzhAFewY` |
| Project | `PVTSSF_lAHOAz2d0c4BSmVVzhAFey0` |
| Type | `PVTSSF_lAHOAz2d0c4BSmVVzhAFe0I` |
| Start date | `PVTF_lAHOAz2d0c4BSmVVzhAFfB0` |
| End date | `PVTF_lAHOAz2d0c4BSmVVzhAFfB8` |

**Status:** Todo=`f75ad846`, In Progress=`47fc9ee4`, Done=`98236657`

**Project:** linkedin-outreach=`62cf1c92`, jobagent=`4bf8cd59`, qms-agents=`48f0a5fc`, qms-leader=`bad90081`, calldeck=`10bc5236`, portfolio=`c497a712`, snapfinance=`bc6154b1`, remoteflow=`db77ab1f`, claude-config=`6703f40c`, other=`51edd8be`

**Type:** task=`bc2735cc`, service=`bb19aa1b`, daily-log=`1f543262`, blocker=`47188be2`, decision=`856bd4a8`

```bash
gh project item-edit --project-id PVT_kwHOAz2d0c4BSmVV --id {ITEM_ID} --field-id {FIELD_ID} --single-select-option-id {OPTION_ID}
gh project item-edit --project-id PVT_kwHOAz2d0c4BSmVV --id {ITEM_ID} --field-id {DATE_FIELD_ID} --date YYYY-MM-DD
gh project item-create 7 --owner thegeshwar --title "Title" --format json
```

---

## Phase 4: Present the Briefing

**The entire briefing should fit on one screen.** If you're writing more than ~30 lines of output, you're writing too much.

### Part 1: Services (visual dashboard)

Show a quick visual grid of all services. Use checkmarks and X marks so the user can glance at it:

```
Services:
  qmsleader.com        ✓    qms.thegeshwar.com    ✓
  qmsagents.ai         ✓    outreach.dev          ✓
  n8n.thegeshwar.com   ✓    portfolio             ✓
  snapfinance          ✓    test.dev (staging)    ✓
  Production: active   Docker: 19 containers up
```

If something is down, mark it with ✗ and a reason:
```
  outreach.dev          ✗ 502
```

### Part 2: Active Tasks

Pull ONLY "In Progress" items from the roadmap. For each:

**{n}. {Task Name}** ({project})
> {Current situation in 2-3 sentences. What's the state right now, not a history.}
>
> **To continue** (paste this into a fresh Claude session):
> ```
> {Write this as a message FROM the user TO Claude. NOT terminal commands.
>  The prompt must reflect WHERE THE WORK ACTUALLY LEFT OFF — not a general project summary.
>
>  If the last session was INTERRUPTED (disconnected mid-work):
>  "I was working on [specific thing] in [project] at [path] and got disconnected.
>   I was in the middle of [exact last action — e.g., debugging the multiselect dropdown,
>   implementing the login page, fixing the hydration error]. Please pick up where I left off.
>   Check if this project has a GitHub Project board and update it."
>
>  If the last session COMPLETED naturally:
>  "I'm working on [project] at [path]. Last session I finished [what was done].
>   Next step is [what to do]. Check if this project has a GitHub Project board
>   and update it."
>
>  Be specific. "Pick up the CallDeck login page fix" is better than "work on CallDeck."}
> ```

### Part 3: Recently Completed

One line each, no details:
> Done: CallDeck, RemoteFlow nav, QMS Agents site

### Part 4: Roadmap Changes

> Updated end dates on: Workday A-Flow, LinkedIn hydration
> No new items created.

---

### Proposed Memory Changes

Only propose memory changes if something genuinely new was learned — a preference, a decision, an architectural choice. Not stats, not progress, not "X is now hydrated."

If nothing worth saving: **"No memory changes."**

**Want me to save these? Yes / No / Edit**

---

## Rules

1. Sessions are research, not output. Never show a session log table.
2. One roadmap item per project. Build the index first, match by project label.
3. Never put numbers in roadmap titles or memory proposals.
4. Everything in Pacific Time.
5. Continue prompts are messages FROM the user TO a fresh Claude session. Never write terminal commands like "cd" or "docker logs" — write conversational prompts that tell Claude what to work on.
6. Services section is always a visual grid, even when everything is up.
