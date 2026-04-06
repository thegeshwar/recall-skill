#!/bin/bash
# imessage-scan.sh — scan iMessage for last 24h, output JSON for recall skill
# Uses imessage-exporter (brew install imessage-exporter) which:
#   - decodes attributedBody (handles macOS Ventura+ NULL text column)
#   - resolves phone numbers to contact names automatically
#   - handles reactions, tapbacks, group chats
#
# Output: JSON to stdout with one entry per conversation that had activity in last 24h
# Schema:
#   [{"contact": "Name", "last_msg": "...", "last_time": "...",
#     "last_from_me": bool, "needs_reply": bool, "msg_count_24h": N}, ...]

set -e

OUT_DIR="/tmp/recall-imessage-$$"
trap "rm -rf $OUT_DIR" EXIT

# Last 24h window in PT
START=$(TZ=America/Los_Angeles date -v-1d +%Y-%m-%d)

# Run exporter (timeout 60s — chat.db can be large)
timeout 60 imessage-exporter -f txt -s "$START" -o "$OUT_DIR" >/dev/null 2>&1 || {
  echo '{"error": "imessage-exporter failed or timed out", "messages": []}'
  exit 0
}

# Parse with python (already in PATH per CLAUDE.md allowlist)
python3 - "$OUT_DIR" <<'PYEOF'
import os, sys, json, re
from datetime import datetime, timedelta

out_dir = sys.argv[1]
results = []

# Cutoff: 24h ago in local time
cutoff = datetime.now() - timedelta(hours=24)

# Date format from imessage-exporter: "Apr 06, 2026  8:38:15 AM"
DATE_RE = re.compile(r'^([A-Z][a-z]{2} \d{2}, \d{4}\s+\d{1,2}:\d{2}:\d{2}\s+[AP]M)')

def parse_dt(s):
    s = re.sub(r'\s+', ' ', s.strip())
    return datetime.strptime(s, '%b %d, %Y %I:%M:%S %p')

for fname in sorted(os.listdir(out_dir)):
    if not fname.endswith('.txt') or fname == 'orphaned.txt':
        continue
    path = os.path.join(out_dir, fname)
    with open(path, 'r', errors='replace') as f:
        content = f.read()

    # Split into message blocks separated by blank lines
    blocks = [b.strip() for b in content.split('\n\n') if b.strip()]
    msgs = []
    for b in blocks:
        lines = b.split('\n')
        if not lines:
            continue
        m = DATE_RE.match(lines[0])
        if not m:
            continue
        try:
            dt = parse_dt(m.group(1))
        except ValueError:
            continue
        if dt < cutoff:
            continue
        # Line 2 is sender ("Me" or contact name)
        sender = lines[1] if len(lines) > 1 else ''
        # Lines 3+ are body (skip attachment paths and tapback metadata)
        body_lines = []
        for ln in lines[2:]:
            if ln.startswith('/Users/') or ln.startswith('Tapbacks:') or ln.startswith('Loved by') or ln.startswith('This message responded'):
                continue
            body_lines.append(ln)
        body = ' '.join(body_lines).strip()
        if not body:
            body = '[attachment/reaction]'
        msgs.append({'sender': sender, 'body': body, 'time': dt.isoformat()})

    if not msgs:
        continue

    # Identify the contact name from the first non-Me sender we see
    contact = next((m['sender'] for m in msgs if m['sender'] != 'Me'), None)
    if not contact:
        # All messages were from Me — derive contact from filename
        contact = fname.replace('.txt', '')

    last = msgs[-1]
    last_from_me = (last['sender'] == 'Me')

    results.append({
        'contact': contact,
        'last_msg': last['body'][:200],
        'last_time': last['time'],
        'last_from_me': last_from_me,
        'needs_reply': not last_from_me,
        'msg_count_24h': len(msgs),
    })

# Sort: needs_reply first, then by recency
results.sort(key=lambda r: (not r['needs_reply'], r['last_time']), reverse=True)
print(json.dumps(results, indent=2))
PYEOF
