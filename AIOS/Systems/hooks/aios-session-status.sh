#!/bin/sh
# AIOS SessionStart status — the vault's own hot context and its four health
# checks, in one testable file.
#
# These were five inline shell commands in .claude/settings.json, one of them a
# multi-line git pipeline. Inline hooks are unquotable, undiffable and unreachable
# from test_hooks.sh, while the peer hooks (aios-context.sh, aios-digest.sh) have
# been files with a harness since day one. Same output, one file.
#
# Pure read. Zero write. Never fails a session: every check is best-effort and the
# script always exits 0.
VAULT="${CLAUDE_PROJECT_DIR:-${AIOS_VAULT:-$HOME/code/aios}}"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"   # mtime()/nosleep() — the BSD/GNU shim

# VAULT SESSIONS ONLY — an identity-wall requirement, not a preference.
#
# Under Claude Code this hook is wired in the vault's own .claude/settings.json,
# so it could only ever fire on a vault session and this check would be dead
# code. jcode's `session_start` is GLOBAL (~/.jcode/config.toml, no per-project
# hook table), so without this the hook fires in EVERY repo on the machine.
#
# What it emits is the reason that matters: Home.md plus the last 12 Log entries,
# which name every scope in one blob — each scope's brands, projects and the
# legal name, together. Injecting that into an unrelated project session is
# exactly the cross-layer mixing CLAUDE.md forbids ("never mix layers in the same
# output"), done automatically, at every session start, into whatever repo
# happens to be open. Measured from one project session: 5551 bytes of
# mixed-layer context, including work-layer material.
#
# The cwd is the test, and $0 resolves the vault (never CLAUDE_PROJECT_DIR, which
# is unset under jcode and is what made the fallback fire everywhere). Silent
# exit 0: a project session is a normal, expected case, not a warning.
SELF_VAULT="$(CDPATH= cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)"
case "${JCODE_HOOK_CWD:-$PWD}" in
  "$SELF_VAULT"|"$SELF_VAULT"/*) : ;;
  *) [ -n "$CLAUDE_PROJECT_DIR" ] || exit 0 ;;
esac

LOG="$VAULT/AIOS/History/Log.md"
LOG_ENTRIES=12          # newest entries to surface
LOG_WIDTH=220           # per-entry budget, trimmed at a word boundary

# --- hot context -------------------------------------------------------------
echo '=== AIOS hot context (auto-loaded) ==='
if [ -f "$VAULT/Home.md" ]; then
  echo '--- Home.md ---'
  cat "$VAULT/Home.md"
  echo
fi
if [ -f "$LOG" ]; then
  echo "--- Recent memory: AIOS/History/Log.md (newest $LOG_ENTRIES) ---"
  # Trim at the last space inside the budget and mark the cut. The old
  # `cut -c1-200` sliced mid-word, so every line ended in half a token
  # ("collaps", "the post went li") — tokens spent on nothing readable.
  grep -E '^- (\*\*|~~\*\*)[0-9]{4}-' "$LOG" \
    | head -"$LOG_ENTRIES" \
    | awk -v w="$LOG_WIDTH" '
        { if (length($0) <= w) { print; next }
          s = substr($0, 1, w); i = length(s)
          while (i > 1 && substr(s, i, 1) != " ") i--
          print substr(s, 1, (i > 1 ? i - 1 : w)) " …" }'
  echo
fi
echo 'Read order: AIOS/Systems/layers.tsv (the scopes), then the me file for the scope this task belongs to (<scope>/me.md), then AIOS/Maps/Vault Map.md + Skill Map.md. Each scope is one top-level dir; a path'"'"'s first segment names its scope, and that prefix is what the write guard, ingest and leak audits key on.'

# --- pending session digests -------------------------------------------------
# A digest is exactly +/_sessions/<layer>/<project>.md — the depth scoping is what
# keeps _sessions/README.md and the .memory/ mirror out of the count.
Q=$(find "$VAULT/+/_sessions" -mindepth 2 -maxdepth 2 -name '*.md' ! -empty 2>/dev/null | wc -l | tr -d ' ')
# "as of session start" is load-bearing, not politeness: this number is printed once
# and never revised, while the scheduled fires (08:00/12:00/16:00) drain the queue
# mid-session. A human reading the banner hours later asked for 4 digests to be
# ingested when 1 remained. Timestamping the claim is the honest fix — refreshing it
# is impossible from a hook that runs once.
[ "${Q:-0}" -gt 0 ] 2>/dev/null && \
  echo "AIOS: $Q pending session digest(s) as of session start — run /aios-ingest to compound them into the wiki (it re-counts; the scheduled fires may have drained some since)."

# --- graphify staleness ------------------------------------------------------
# Keyed on the rebuild stamp, not on graph.json — the 1.28MB blob was tracked
# solely to answer this one question and is now untracked (see .gitignore).
GC=$(git -C "$VAULT" log -1 --format=%H -- graphify-out/.rebuild-stamp 2>/dev/null)
if [ -n "$GC" ]; then
  N=$(git -C "$VAULT" log --oneline "$GC"..HEAD -- . ':(exclude)graphify-out' 2>/dev/null | wc -l | tr -d ' ')
  [ "${N:-0}" -gt 0 ] 2>/dev/null && \
    echo "AIOS: $N commit(s) touched vault content since the last graphify rebuild — run /graphify-layers to refresh the structural cross-check."
fi

# --- scheduled ingest health -------------------------------------------------
# Pair each start line with its OWN terminal line. The previous version grepped for
# terminal lines and took `tail -1`, so a run killed by sleep/SIGKILL/reboot — which
# writes no terminal line at all — matched the PREVIOUS run's "done" and fell through
# the case silently. 3 such deaths in 78 fires, every one invisible.
INGEST_LOG="${AIOS_INGEST_LOG:-$(aios_log_dir)/aios-ingest.log}"
# The wrapper's own stale-lock threshold (aios-scheduled-ingest.sh: `timeout 3600`
# + 600s grace). Reused rather than re-invented: if the detector and the reaper
# disagree, one of them is lying about the same lock.
LOCK_STALE_S=4200
if [ -f "$INGEST_LOG" ]; then
  START=$(grep -n 'ingesting [0-9]* digest(s)' "$INGEST_LOG" 2>/dev/null | tail -1)
  if [ -n "$START" ]; then
    SLN=${START%%:*}
    TERMLINE=$(tail -n +"$((SLN + 1))" "$INGEST_LOG" \
               | grep -E 'done — queue drained|FAILED —|INCOMPLETE —|UNSYNCED —' | tail -1)
    if [ -n "$TERMLINE" ]; then
      case "$TERMLINE" in
        # UNSYNCED must be BOTH in the grep above and here. In the grep alone it
        # would count as a terminal line and go unreported; missing from the grep
        # it would read as no terminal line at all and mis-report a silent death.
        *FAILED*|*INCOMPLETE*|*UNSYNCED*) echo "AIOS: the scheduled ingest is NOT healthy — its last run ended: ${TERMLINE#* }" ;;
      esac
    else
      # No terminal line: the run never finished. A held lock does NOT prove it is
      # still alive — a SIGKILL never fires the wrapper's EXIT trap, so the lock
      # outlives the process. Only a lock young enough to belong to a live run buys
      # silence; a stranded one is exactly the death this check exists to catch.
      ALIVE=0
      if [ -d "$VAULT/.aios-ingest.lock" ]; then
        AGE=$(( $(date +%s) - $(mtime "$VAULT/.aios-ingest.lock" || date +%s) ))
        [ "$AGE" -le "$LOCK_STALE_S" ] && ALIVE=1
      fi
      [ "$ALIVE" -eq 1 ] || \
        echo "AIOS: the scheduled ingest died silently — started '${START#*:}' and never wrote a terminal line; its digest(s) may be unarchived. Run /aios-ingest — step 0 reconciles a partial run."
    fi
  fi
fi

# --- the mechanical janitor sweep --------------------------------------------
sh "$VAULT/AIOS/Systems/aios-check.sh" 2>/dev/null

exit 0
