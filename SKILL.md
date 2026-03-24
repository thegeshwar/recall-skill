---
name: recall
description: "Morning briefing with auto-discovered services, 7-day session context, roadmap sync, and smart continue prompts that capture the user's journey. Use this skill whenever the user runs /recall, asks for a morning briefing, wants to know what they worked on recently, asks 'what was I doing', or wants to catch up on recent work. Also triggers for /start-day since this replaces it. Usage: /recall [hours] — focus window for continue prompts (default: most recent per active project). Always loads 7 days of context."
user_invocable: true
---

# Recall v2

You're giving the user their morning briefing. Tell them what they're actively working on, where they left off, and how to continue.

The user is non-technical. Keep it clear, focused, and actionable.

**Everything must be in Pacific Time (PST/PDT).** The server runs in UTC. Use `TZ=America/Los_Angeles date +%Y-%m-%d` for today's date and `TZ=America/Los_Angeles date` for times.

**Argument handling:**
- `$ARGUMENTS` contains an optional focus window in hours (e.g., `/recall 6`)
- Parse into `FOCUS_HOURS`. If empty or not a number, leave empty (triggers "most recent per active project" mode)
- Session/git data gathering ALWAYS uses a **7-day window** regardless of the argument
- The argument only controls which tasks get continue prompts in Phase 4

---

## Phase 1: Gather (do ALL in parallel)

### A. Find sessions (always 7 days)

```bash
CUTOFF=$(date -d "7 days ago" +%s)000
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

### D. Auto-discover services and health check

**Step 1 — Discover domains from nginx:**

```bash
for conf in /etc/nginx/sites-enabled/*; do
  python3 -c "
import re, sys
text = open('$conf').read()
blocks = re.findall(r'server\s*\{[^}]*listen\s+443[^}]*\}', text, re.DOTALL)
if not blocks:
    blocks = re.findall(r'server\s*\{[^}]*\}', text, re.DOTALL)
for block in blocks:
    names = re.findall(r'server_name\s+([^;]+);', block)
    proxy = re.findall(r'proxy_pass\s+https?://[^:]+:(\d+)', block)
    root_dir = re.findall(r'root\s+([^;]+);', block)
    has_ssl = 'listen 443' in block or 'ssl_certificate' in block
    for name_group in names:
        for domain in name_group.split():
            if domain == '_': continue
            port = proxy[0] if proxy else 'static'
            proto = 'https' if has_ssl else 'http'
            print(f'{domain}|{port}|{proto}')
" 2>/dev/null
done | sort -u
```

**Step 2 — Match ports to processes:**

```bash
ss -tlnp 2>/dev/null | grep LISTEN | python3 -c "
import sys, re, os
for line in sys.stdin:
    port_match = re.search(r':(\d+)\s', line)
    pid_match = re.search(r'pid=(\d+)', line)
    if port_match and pid_match:
        port = port_match.group(1)
        pid = pid_match.group(1)
        try:
            cwd = os.readlink(f'/proc/{pid}/cwd')
            name = os.path.basename(cwd)
        except:
            name = 'unknown'
        print(f'{port}|{name}|{cwd}')
"
```

**Step 3 — Health check each discovered domain:**

For each unique domain from Step 1, curl it:
```bash
curl -s -o /dev/null -w "%{http_code}" --max-time 5 "https://${domain}" 2>/dev/null
```

**Step 4 — Additional checks:**
```bash
systemctl is-active qms-leader 2>/dev/null
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | head -25
```

**Domain filtering:** When multiple domains share the same port AND the same upstream (e.g., `expert.qmsleader.com` and `qmsleader.com` both route to :3000), show only the primary domain (shortest name or the one without a subdomain prefix). Each unique port+project combination gets one row.

**Fallback:** If nginx parsing yields zero results, fall back to curling domains from the roadmap's SERVICE-type items.

### E. Auto-discover git repos and activity

```bash
for gitdir in $(find /home/ubuntu -maxdepth 2 -name .git -type d \
  -not -path '*/.claude/*' \
  -not -path '*/node_modules/*' \
  -not -path '*/.cache/*' \
  -not -path '*/.local/*' \
  -not -path '*/supabase/*' \
  -not -path '*-worktrees/*' 2>/dev/null); do
  dir=$(dirname "$gitdir")
  echo "=== $(basename $dir) ==="
  cd "$dir" && git log --since="7 days ago" --oneline --all 2>/dev/null
done
```

---

## Phase 2: Read Sessions (build per-project arcs)

Sessions are research material — read them to understand what happened, but don't reproduce them in the output.

**Read up to 15 most recent sessions** (head -50 and tail -30 each). For older sessions (day 3-7), only read if the project is still In Progress — skip sessions for completed work.

For each session:
1. Convert project path: `/home/ubuntu/foo` → `-home-ubuntu-foo`
2. Session log at: `~/.claude/projects/{sanitized-name}/{sessionId}.jsonl`
3. Read only `head -50` and `tail -30` — just enough to get intent and outcome

**Build a per-project arc:** After reading sessions, organize your notes by project. For each project, write down:
- **Timeline:** what happened each day over the 7 days
- **Trajectory:** ramping up, winding down, or stuck?
- **Latest state:** what was the user doing in the most recent session? Did it complete or get interrupted?
- **User's intent:** what is the user trying to achieve with this project overall?
- **Blockers/frustrations:** anything that's been a recurring problem?

This per-project arc powers the smart continue prompts in Phase 4.

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

**You should almost never need to create a new item.** Only create one if a session worked on a project that has ZERO items in the index AND the project has meaningful activity (2+ commits in 7 days or an active session). Single-commit repos or empty scaffolds are not worth creating items for.

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

**Keep it compact (~40 lines max).** The 7-day context makes prompts smarter, not longer.

### Part 1: Services (auto-discovered dashboard)

Show every discovered service with domain, port, project name, and health:

```
Services:
  qmsleader.com           :3000  qms-leader         ✓
  calldeck.thegeshwar.com :3002  calldeck           ✓
  outreach.dev.thegeshwar :7681  linkedin-outreach  ✓
  n8n.thegeshwar.com      :5678  n8n                ✓
  qmsagents.ai            :3002  calldeck           ✓
  portfolio.thegeshwar    static nginx              ✓
  snapfinance.thegeshwar  static nginx              ✓
  Production: active   Docker: N containers up
```

If something is down, mark it with ✗ and the HTTP code:
```
  outreach.dev          :7681  linkedin-outreach  ✗ 502
```

### Part 2: Active Tasks (focus-window controlled)

**Determine which tasks get continue prompts:**
- If `FOCUS_HOURS` is set: only tasks with session/git activity in the last `FOCUS_HOURS` hours
- If `FOCUS_HOURS` is empty: most recent task per active project within the last 72 hours

**"Active project"** = In Progress on roadmap AND has git/session activity in last 72 hours.

**Stalled projects:** If a roadmap item is In Progress but has NO activity in 72 hours, list it as a one-liner under a "Stalled" note — no continue prompt. Example:
> Stalled: Workday A-Flow (no activity in 4 days)

**For each active task, write:**

**{n}. {Task Name}** ({project})
> {2-3 sentence summary. Focus on CURRENT STATE and what matters, not history. Plain language. Frame around what the user cares about.}
>
> **To continue:**
> ```
> {Smart continue prompt — see prompt construction rules below}
> ```

#### Smart Continue Prompt Construction

Continue prompts are messages FROM the user TO a fresh Claude session. They must feel like the user wrote them — capturing their journey, intent, and momentum.

**How to construct each prompt:**

1. **Use the per-project arc** you built in Phase 2. What's the full story of this project over 7 days?
2. **Identify the trajectory:** Is the user on a roll (ramping up), stuck (repeated attempts), or wrapping up?
3. **Write in first person, casually.** The user is talking to a fresh Claude. Sound like them, not a report.
4. **Include specific technical details** — file paths, function names, what was last touched
5. **Capture emotional context** — if they've been fighting something, say so. If they're on a roll, convey that energy.
6. **End with clear next action** and always include "Check the GitHub Project board and update it."

**Examples of GOOD prompts:**

Momentum:
```
I've been building out CallDeck all week at /home/ubuntu/calldeck — started from scratch
and got through the full app: login, dashboard, all core pages, prospect discovery with
Google Places, and bulk lead enrichment. I'm on a roll and want to keep going. The enrichment
pipeline is working (86% industry coverage). Next I need to figure out the partner login
password situation and then tackle [next feature]. Check the GitHub Project board and update it.
```

Stuck/blocked:
```
I've been trying to get Workday automated form filling working at /home/ubuntu/jobagent
but email verification keeps blocking the flow — tried multiple approaches over the past
few days and it's still an issue. I need a fresh approach — either find a workaround for
email verification or identify which Workday instances don't require it. Pick up where
I left off. Check the GitHub Project board and update it.
```

Returning after a break:
```
I haven't touched the LinkedIn outreach agent at /home/ubuntu/linkedin-outreach in a few
days. Last time I was redesigning the dashboard with a Kanban pipeline view and live polling.
The pipeline itself is running fine (234 posters discovered, all hydrated). I want to pick
back up on the dashboard redesign. Check the GitHub Project board and update it.
```

**BAD prompt (never do this):**
```
I'm working on CallDeck at /home/ubuntu/calldeck. Last session I implemented bulk enrichment.
Next step is to implement the next feature. Check the GitHub Project board and update it.
```
This is bad because it's mechanical, has no arc, no momentum, no specifics.

### Part 3: Recently Completed

One line each, no details:
> Done: RemoteFlow nav, QMS Agents site polish

### Part 4: Roadmap Changes

> Updated end dates on: CallDeck, LinkedIn Outreach
> New project detected: {name} — want me to add it to the roadmap?
> No new items created.

Only show "New project detected" if a discovered git repo has 2+ commits in 7 days and doesn't match any existing roadmap item.

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
6. Services section is always a visual grid with domain, port, project, and health status.
7. Always gather 7 days of data. The argument only controls the focus window for continue prompts.
8. Build per-project arcs before writing continue prompts. The arc is what makes prompts smart.
9. Auto-discover everything — services from nginx, repos from filesystem. Never hardcode lists.
