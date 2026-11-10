#!/bin/sh
# AIOS nightly ingest — runs headless /aios-ingest when session digests are queued.
# Install with: scripts/aios-install-nightly.sh   (launchd on macOS, cron elsewhere)
#
# The runner for the CRON FALLBACK scheduler. aios-scheduled-ingest.sh beside it
# is the runner for the default one, and carries what this does not: a
# concurrent-writer pathspec, stand-down detection, and `timeout -k` escalation.
# The two overlap and consolidating them is open work — do not edit one and
# assume the other followed.
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

# Heartbeat: unambiguous "the job fired" marker, written before any branch below.
# The dated log line proves it ran even if it dies mid-run; the .lastrun file is
# stat-able for a quick "when did it last fire" check.
echo "$(TS) heartbeat — invoked" >> "$LOG"
touch "$LOG_DIR/aios-nightly.lastrun" 2>/dev/null

Q=$(count_queue)
if [ "$Q" -eq 0 ]; then
  echo "$(TS) queue empty, skipping" >> "$LOG"
  exit 0
fi

# The scheduler may fire this several times a day, and it can't see a human
# session already running /aios-ingest — two agents rewriting the same project
# note and racing a commit is how the queue gets double-counted. macOS has no
# flock → atomic mkdir lock, same pattern as aios-digest.sh. No wait loop: if an
# ingest is already in flight, this fire has nothing to add — the next one picks
# it up.
LOCK="$VAULT/.aios-ingest.lock"
# Reap a stale lock: a SIGKILL/reboot mid-run strands the mkdir lock (the EXIT
# trap never fires) and every later fire silently skips. The ingest is capped at
# timeout 3600, so a lock older than 3600+600s cannot belong to a live run.
if [ -d "$LOCK" ]; then
  MTIME=$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || date +%s)
  AGE=$(( $(date +%s) - MTIME ))
  if [ "$AGE" -gt 4200 ]; then
    echo "$(TS) reaping stale lock (age ${AGE}s)" >> "$LOG"
    rmdir "$LOCK" 2>/dev/null
  fi
fi
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(TS) another ingest in flight (lock held), skipping" >> "$LOG"
  exit 0
fi
# ponytail: trap covers the timeout kill + normal exit; a hard SIGKILL (or a
# reboot mid-run) strands the lock — the stale-lock reaper above clears it on
# the next fire once it ages past 4200s.
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

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
