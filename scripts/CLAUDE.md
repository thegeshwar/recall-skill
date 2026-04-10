# Recall Scripts — Architecture Notes

This directory contains the wrapper scripts that run the `recall` skill on a schedule via launchd. Before editing anything in here, read the whole file — there are non-obvious constraints.

## The Split Architecture (CRITICAL)

Recall is split across two layers on purpose:

1. **Claude layer** (the `recall` skill at `~/.claude/skills/recall/SKILL.md`)
   - Gathers everything (Gmail, iMessage, VPS, git, sessions)
   - Auto-ranks projects
   - Builds the dashboard text and reminder data
   - Writes reminder data to `/tmp/recall-reminders.json`
   - **Does NOT run `osascript` for Reminders**

2. **Bash wrapper layer** (this directory)
   - `daily-recall.sh` → entry point, runs Claude, then creates reminders
   - `create-reminders.sh` → reads `/tmp/recall-reminders.json` and creates actual Reminders via `osascript`

## Why the Split (the rule that caused all the 7 AM failures)

**Never run `osascript` from inside a Claude-invoked skill that runs unattended.**

The Claude CLI lives at `~/.local/share/claude/versions/X.Y.Z/`. macOS TCC (Transparency, Consent, Control) treats every version as a brand new, unknown binary. Every Claude auto-update:

1. Creates a new version path
2. macOS has no record of it → permission defaults to denied
3. Next time Claude tries `osascript` → popup appears asking "Allow?"
4. User is asleep at 7 AM → nobody clicks Allow → skill fails silently

This was broken for a full week before we figured it out. TCC database inspection showed separate entries for versions 2.1.85, 2.1.86, 2.1.92, 2.1.96, 2.1.97, 2.1.101 — all with auth_value=2 (denied) for Reminders.

**The fix:** Move the `osascript` calls into `/bin/bash`, which has permanent TCC approval and is immune to Claude updates.

## How to Apply This Elsewhere

If you're adding a new scheduled automation that needs to control a macOS app (Reminders, Calendar, Contacts, Photos, Messages, etc.):

1. Skill writes a JSON file describing what to do (don't call `osascript` from the skill)
2. Wrapper shell script reads the JSON and runs `osascript`
3. Wrapper pre-warms the app: `pkill -9 -x AppName; sleep 2; open -a AppName; sleep 10`
   - The kill+relaunch unwedges `cloudd`-related AppleEvent timeouts that happen after idle periods
   - `cloudd` itself is SIP-protected, can't be killed
4. Every `osascript` call in the wrapper must be wrapped in `timeout 15` — `cloudd` can wedge forever

Interactive sessions are exempt — the user can click Allow when they're present. This rule is specifically for unattended/scheduled work.

## Files

- `daily-recall.sh` — launchd entry point, runs at 7 AM PST daily
- `create-reminders.sh` — creates reminders from `/tmp/recall-reminders.json`
- `imessage-scan.sh` — wraps `imessage-exporter` for iMessage data
- `logs/` — rotated daily, 14-day retention

## Debugging Failures

Check in order:

1. `tail logs/recall-YYYY-MM-DD.log`
2. Is `/tmp/recall-reminders.json` present? If yes → Claude did its job; problem is in the wrapper layer
3. Run `create-reminders.sh /tmp/recall-reminders.json /dev/stderr` manually to reproduce Reminders errors
4. TCC state: `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT client, service, auth_value FROM access WHERE client LIKE '%claude%'"` — `auth_value=2` means denied
5. AppleEvent timeout (-1712)? Reminders is wedged. `pkill -9 -x Reminders && open -a Reminders` (the wrapper already does this at startup as a safety net)

## History

- **2026-04-10:** Redesigned from direct-osascript-in-skill to JSON + wrapper split. Root cause was TCC-per-version breaking on every Claude update.
