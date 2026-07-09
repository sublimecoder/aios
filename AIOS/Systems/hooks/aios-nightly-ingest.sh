#!/bin/sh
# AIOS nightly ingest — launchd runs this at 03:00 local; headless /aios-ingest
# when session digests are queued. Loaded via ~/Library/LaunchAgents/com.aios.nightly-ingest.plist.
# Log: ~/Library/Logs/aios-ingest.log
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
VAULT="${AIOS_VAULT:-$HOME/code/aios}"
LOG="$HOME/Library/Logs/aios-ingest.log"
TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

count_queue() {
  find "$VAULT/+/_sessions" -name '*.md' ! -empty 2>/dev/null \
    | grep -v '/.state/' | grep -v '/.memory/' | wc -l | tr -d ' '
}

Q=$(count_queue)
if [ "$Q" -eq 0 ]; then
  echo "$(TS) queue empty, skipping" >> "$LOG"
  exit 0
fi

echo "$(TS) ingesting $Q digest(s)" >> "$LOG"
# Scoped tool allowlist instead of --dangerously-skip-permissions: an unattended
# agent gets only what /aios-ingest needs (read/write vault, git, fan-out workers).
# Network/browser tools are denied by omission — no exfil surface. The
# vault-write-guard PreToolUse hook still constrains WHERE writes land (defense in depth).
cd "$VAULT" && timeout 3600 claude -p "/aios-ingest" \
  --permission-mode acceptEdits \
  --allowedTools "Read,Write,Edit,Grep,Glob,Bash,Task,TodoWrite" \
  > "$HOME/Library/Logs/aios-ingest-transcript.log" 2>&1

# claude -p exits 0 even on session-limit / mid-run death, so exit code is not a
# success signal. Real check: did the queue drain AND is the tree committed? A
# partial run (files written, commit skipped) leaves the tree dirty — surface it.
REMAIN=$(count_queue)
DIRTY=$(git -C "$VAULT" status --porcelain 2>/dev/null)
if [ "$REMAIN" -gt 0 ]; then
  echo "$(TS) FAILED — $REMAIN digest(s) still queued (session limit or error); rerun /aios-ingest" >> "$LOG"
elif [ -n "$DIRTY" ]; then
  echo "$(TS) INCOMPLETE — queue drained but tree dirty (commit step skipped); run 'git -C $VAULT status'" >> "$LOG"
else
  echo "$(TS) done — queue drained, committed" >> "$LOG"
fi
