#!/bin/sh
# AIOS nightly ingest — runs headless /aios-ingest when session digests are queued.
# Install with: scripts/aios-install-nightly.sh   (launchd on macOS, cron elsewhere)
#
# Env:
#   AIOS_VAULT    vault root         (default ~/code/aios)
#   AIOS_LOG_DIR  where logs land    (default ~/Library/Logs on macOS, else
#                                     $XDG_STATE_HOME/aios or ~/.local/state/aios)
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
VAULT="${AIOS_VAULT:-$HOME/code/aios}"

if [ -n "${AIOS_LOG_DIR:-}" ]; then
  LOG_DIR="$AIOS_LOG_DIR"
elif [ -d "$HOME/Library/Logs" ]; then
  LOG_DIR="$HOME/Library/Logs"
else
  LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/aios"
fi
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/aios-ingest.log"
TRANSCRIPT="$LOG_DIR/aios-ingest-transcript.log"

TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

command -v claude >/dev/null 2>&1 || {
  echo "$(TS) FAILED — 'claude' not on PATH ($PATH)" >> "$LOG"; exit 1; }
[ -d "$VAULT/AIOS" ] || {
  echo "$(TS) FAILED — no vault at $VAULT (set AIOS_VAULT)" >> "$LOG"; exit 1; }

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
  > "$TRANSCRIPT" 2>&1

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
