#!/bin/sh
# AIOS scheduled ingest — launchd runs this at 08:00 local, retrying at 12:00
# and 16:00; headless /aios-ingest when session digests are queued, no-op when
# not. NOT nightly: it was 03:00/07:00/11:00 until 2026-08-04, and the old name
# outlived the schedule long enough to mislead two debugging sessions into
# looking for an overnight run that no longer existed. Renamed 2026-08-05.
# Loaded via ~/Library/LaunchAgents/com.aios.scheduled-ingest.plist.
# launchd (not cron) so a fire missed while the Mac slept runs on wake.
# Log: $(aios_log_dir)/aios-ingest.log — ~/Library/Logs on macOS,
#      ${XDG_STATE_HOME:-~/.local/state}/aios on Linux. Streams go to the journal.
# /usr/bin/core_perl is where Arch puts `shasum` (perl-Digest-SHA); without it
# the guard-drift stamp is unverifiable under this stripped PATH. /opt/homebrew
# stays for the macOS side -- an absent dir on PATH costs nothing.
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/usr/bin/core_perl:/bin"
# The plist passes AIOS_VAULT; honor it. Hardcoding the path meant the two could
# silently disagree if the vault ever moves — same value today, a trap tomorrow.
VAULT="${AIOS_VAULT:-$HOME/code/aios}"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"   # mtime()/nosleep() — the BSD/GNU shim
AIOS_LOGDIR=$(aios_log_dir)
LOG="$AIOS_LOGDIR/aios-ingest.log"

# SIGNING KEY FOR AN UNATTENDED RUN. gitconfig sets commit.gpgsign=true with
# gpg.format=ssh, and the default signing key is passphrase-protected. A systemd
# user service inherits no ssh agent, so ssh-keygen cannot decrypt it and the
# commit fails outright with "failed to write commit object" -- the whole run
# drains the queue, writes the wiki, and then cannot record any of it.
#
# Discovered 2026-09-05 the moment the dotfiles were installed on this box: the
# vault had been committing unsigned only because ~/.gitconfig did not exist yet.
# Interactive commits keep the normal key; only this job overrides it, with the
# same passphrase-less deploy key the preflight uses, so unattended commits stay
# SIGNED rather than being exempted from signing.
#
# GIT_CONFIG_* is used rather than `git -c` so the override reaches the git calls
# the agent makes, not just the wrapper's own.
if [ -f "$HOME/.ssh/id_aios_vault.pub" ]; then
  GIT_CONFIG_COUNT=1
  GIT_CONFIG_KEY_0=user.signingkey
  GIT_CONFIG_VALUE_0="$HOME/.ssh/id_aios_vault.pub"
  export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
fi
TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

count_queue() {
  # A digest is exactly +/_sessions/<layer>/<project>.md. Depth-scoping is what
  # excludes the siblings: _sessions/README.md (depth 1) counted as a pending
  # digest under the old name-only match, so an empty queue looked like 1 and this
  # job fired a full headless ingest every time for nothing. .state/ holds no .md and
  # .memory/ nests deeper, so both fall out by construction — no greps needed.
  find "$VAULT/+/_sessions" -mindepth 2 -maxdepth 2 -name '*.md' ! -empty 2>/dev/null \
    | wc -l | tr -d ' '
}

# Heartbeat: unambiguous "the job fired" marker, written before any branch below.
# The dated log line proves it ran even if it dies mid-run; the .lastrun file is
# stat-able for a quick "when did it last fire" check (see below).
echo "$(TS) heartbeat — invoked" >> "$LOG"
touch "$AIOS_LOGDIR/aios-scheduled.lastrun" 2>/dev/null

# THE QUEUE LIVES ON THE REMOTE. Digests are committed and pushed by whichever
# repo session produced them, on whichever machine. count_queue reads THIS
# working tree, so a clone that never pulls reads an empty queue forever and
# logs "queue empty, skipping" while digests pile up on origin. That ran for
# three days (2026-09-06 16:45 -> 09-09 15:14): HEAD frozen at ad51a111, every
# fire a no-op, nothing in the log distinguishable from a genuinely idle vault.
# --ff-only on purpose: an unattended job must never merge or rebase. A dirty
# tree or a real divergence is a human's problem.
#
# RETRIED, because the dominant failure is a RACE, not a broken repo. This box is
# a laptop that is suspended at 08:00/12:00/16:00, so Persistent=true replays one
# coalesced catch-up on resume and that fire starts seconds after wake — before
# the network is up. The pull fails, the local count reads 0, and the old code
# logged "queue empty, skipping": indistinguishable from an idle vault, which is
# the SAME silent-success class as the three-day origin-drift above. Observed
# 2026-09-11 and 09-12, two consecutive days, both the only fire of their day.
#
# The unit's Wants=/After=network-online.target did NOT cover this and never
# could: that target DOES NOT EXIST in the user manager (`systemctl --user
# list-units network-online.target` -> not-found), so both lines were silently
# ignored from the day they were written while their comment called the ordering
# "load-bearing". A dependency on a non-existent unit is not a weak guarantee,
# it is zero guarantee. Retrying in the script needs no target to exist.
PULLED=0
for _try in 1 2 3; do
  if git -C "$VAULT" pull -q --ff-only 2>/dev/null; then PULLED=1; break; fi
  [ "$_try" -lt 3 ] && sleep 20
done

Q=$(count_queue)
# NEVER report a stale zero as an empty queue. Unknown and idle are different
# states and only one of them needs a human.
if [ "$PULLED" -eq 0 ] && [ "$Q" -eq 0 ]; then
  echo "$(TS) UNKNOWN — pull --ff-only failed 3x (network not up on resume, dirty tree, divergence, or no deploy key); local queue reads 0 but that count is STALE, not idle" >> "$LOG"
  exit 0
fi
if [ "$PULLED" -eq 0 ]; then
  echo "$(TS) pull --ff-only failed 3x — proceeding on $Q local digest(s); origin may hold more" >> "$LOG"
fi
if [ "$Q" -eq 0 ]; then
  echo "$(TS) queue empty, skipping" >> "$LOG"
  exit 0
fi

# The 08:00 run is followed by 12:00 + 16:00 retries (see the plist), so an
# ingest fires 3x/day and is likelier to land on top of a human-driven
# /aios-ingest. launchd won't run two copies of THIS job, but it can't see a
# session doing the same work — and two agents rewriting the same project note
# and racing a commit is how the queue gets double-counted. macOS has no flock →
# atomic mkdir lock, same pattern as aios-digest.sh. No wait loop: if an ingest
# is already in flight, this fire has nothing to add — the next one picks it up.
LOCK="$VAULT/.aios-ingest.lock"
# Reap a stale lock: a SIGKILL/reboot mid-run strands the mkdir lock (the EXIT
# trap never fires) and every later fire silently skips. The ingest is capped at
# timeout 3600, so a lock older than 3600+600s cannot belong to a live run.
if [ -d "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(mtime "$LOCK" || date +%s) ))
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
# One transcript per run, not one overwritten every run: 45 of 46 failures since
# 2026-07-15 were undiagnosable because the next fire clobbered the evidence.
# Pruned at 14 days so they can't grow without bound.
TRANSCRIPT="$AIOS_LOGDIR/aios-ingest-transcript-$(date -u +%Y%m%dT%H%M%SZ).log"
find "$AIOS_LOGDIR" -name 'aios-ingest-transcript-*.log' -mtime +14 -delete 2>/dev/null

# PRE-RUN FINGERPRINT OF THE RECOVERY PATHSPEC — the gate for the partial-ingest
# commit far below. Without it that branch fires on `REMAIN > 0` alone, which says
# only "the queue is undrained" and nothing whatever about whether THIS agent wrote
# anything. Those are different questions and on 2026-09-13 16:00 they came apart
# completely: the agent detected an interactive by-hand `/aios-ingest` already mid-run,
# correctly stood down, and wrote nothing — and this wrapper then swept that OTHER
# run's six in-flight files into a commit titled "run died with 3 digest(s) still
# queued", a death that had not happened. It was the very failure the agent had just
# listed as its reason for standing down.
#
# THE PATHSPEC CANNOT DISTINGUISH THEM AND IS NOT SUPPOSED TO. It was narrowed on
# 2026-08-16 to stop `-A` absorbing a concurrent writer, and it does bound the damage
# — but every scope's `projects/`, the map and the
# Log are exactly the paths ANY ingest writes, so it cannot tell a dead agent's
# synthesis from a live peer's. On a stand-down the distinction is total rather than
# partial: there is no own-work at all, so 100% of what it would commit is somebody
# else's. Comparing before against after is what separates the two, and it costs one
# `git status` taken before the agent starts.
#
# ponytail: catches the TOTAL case only — agent wrote nothing, so all dirt is foreign.
# A run that wrote some of its own files while a concurrent writer held others still
# commits both, exactly as before; the 2026-08-16 pathspec narrowing is what bounds
# that, and this does not improve it. Upgrade path if the mixed case ever bites: diff
# PRE against POST per path and stage only the paths that changed — deferred because
# it mis-handles a file both writers touched, which is the case it would exist for.
# SCOPE PATHSPEC, DERIVED. `<scope>/projects` for every scope declared in
# layers.tsv, built once here. A hardcoded list is how a scope added later ends up
# outside the pathspec that bounds a concurrent writer's damage — the omission is
# invisible until two runs overlap.
SCOPE_PROJECT_PATHS=$(awk -F'\t' '/^[[:space:]]*#/ {next} NF >= 3 && $1 != "" {printf "%s/projects ", $1}' \
                        "$VAULT/AIOS/Systems/layers.tsv" 2>/dev/null)

PRE_RUN_DIRT=$(git -C "$VAULT" status --porcelain -- \
  'AIOS/History/Log.md' \
  'AIOS/History/audits/after-action.md' \
  'AIOS/History/_ingested' \
  'AIOS/Maps/Knowledge Map.md' \
  $SCOPE_PROJECT_PATHS \
  '+/_sessions' 2>/dev/null)
# -k: plain `timeout` sends TERM only, and claude ignores it — the 2026-07-31
# 03:00 run overran the 3600s cap by two hours. -k escalates to KILL 300s later.
# The agent must be told it IS the authorized run. The lock and the running
# `claude -p /aios-ingest` process it would find are ITS OWN — the wrapper takes
# the lock before exec'ing it. On 2026-07-31 11:00 the run checked for a
# concurrent ingest, found its own PID and a 59s-old lock, concluded another
# agent was mid-flight, and stood down after 83s. Deterministic self-deadlock,
# not a session limit. One sentence is the whole fix.
# NO HUMAN IS ATTACHED. The 2026-08-04 03:00 run did not crash — it hit an API
# error in the step-2 leak-auditor dispatch, wrote a tidy status summary, and
# ended on "How do you want the gate handled?". In `claude -p` nobody answers, so
# the process exits with the queue undrained and the notes uncommitted. Same
# failure shape as the 07-31 self-deadlock (the paragraph above), different
# question — so the fix is the same: say the quiet part in the prompt.
# caffeinate: launchd DarkWakes the Mac to fire this job and macOS re-sleeps ~40s
# later, because nothing held a power assertion — so a multi-minute `claude -p`
# lost its network stream mid-response. That is the mechanical cause of
# "API Error: Connection closed mid-response", the death string in 4 of the 7
# failed transcripts before 2026-08-04, and it also froze `timeout`'s alarm()
# (the 03:00 run ran 110min against a 65min cap). Assertions are held on the
# utility's behalf and released the moment it exits, so this holds sleep off for
# THIS run only, capped by the timeout below, and never on an empty-queue fire —
# that path exits above, before this line. -i (idle sleep) not -s: -s is AC-only
# and these fires land on battery. Lid-close still sleeps through -i and still
# kills the run; observed cost is 1 clamshell sleep vs 1094 idle-class in 3 days.
# ⚠️ NOT SUFFICIENT — proved 2026-08-05. The 08:00 fire held its caffeinate
# assertion the full 58 min (pmset: PID 33453 PreventUserIdleSystemSleep
# 00:58:26) and STILL died on "Connection closed mid-response", because the Mac
# entered 'Maintenance Sleep' 6s after the run started and 55 times over the
# hour — it never truly woke until the lid opened at 09:56. -i blocks IDLE
# sleep; it does not hold open a DarkWake maintenance window, which is the state
# every asleep-at-fire-time run actually lives in. So the sleep class that kills
# these runs is still unhandled: an unattended fire on battery with the lid shut
# cannot hold a multi-minute network stream. Open, not fixed.
cd "$VAULT" && nosleep timeout -k 300 3600 claude -p "/aios-ingest

You are the scheduled headless ingest, launched by aios-scheduled-ingest.sh. The \`.aios-ingest.lock\` directory and any running \`claude -p /aios-ingest\` process you may find are YOUR OWN — the wrapper took the lock before starting you. Do not interpret them as a concurrent run and do not stand down; the wrapper already guarantees you are the only ingest. Proceed with the skill.

No human is attached to this run and no answer will ever come back. Never end your turn on a question — decide, act, and finish. When a step fails or a subagent dies, retry it once; if it still fails, record the real outcome (e.g. gate NOT-RUN, lint NOT-RUN) in the Log line and carry on to the next step. Always reach step 6 and commit: an undrained queue with uncommitted synthesis is the single worst outcome, worse than any step you had to record as skipped." \
  --permission-mode acceptEdits \
  --allowedTools "Read,Write,Edit,Grep,Glob,Bash,Task,TodoWrite" \
  > "$TRANSCRIPT" 2>&1

# An expired/revoked OAuth token exits 0 and writes nothing to the vault, so it
# lands in the log as the SAME generic "session limit or error" line below as a
# genuinely hard digest. Four consecutive fires on 2026-08-02/03 died on a dead
# token and every one read as a queue problem; the cause was only visible by
# opening the transcript by hand. Name it in the log instead.
# Deliberately NOT an early exit: the token can also expire mid-run (2026-08-03
# 03:09 local ran 37 minutes before failing), which leaves real synthesis
# uncommitted — the queue/dirty logic below still has to run and commit it.
AUTH_RE='Failed to authenticate|OAuth access token has been revoked|OAuth session expired'
if grep -qiE "$AUTH_RE" "$TRANSCRIPT" 2>/dev/null; then
  echo "$(TS) AUTH FAILED — $(grep -iEm1 "$AUTH_RE" "$TRANSCRIPT" | cut -c1-160)" >> "$LOG"
  echo "$(TS) fix: run \`claude\` interactively and /login; the next fire recovers on its own" >> "$LOG"
fi

# claude -p exits 0 even on session-limit / mid-run death, so exit code is not a
# success signal. Real check: did the queue drain AND is the tree committed? A
# partial run (files written, commit skipped) leaves the tree dirty — surface it.
REMAIN=$(count_queue)
DIRTY=$(git -C "$VAULT" status --porcelain 2>/dev/null)
if [ "$REMAIN" -gt 0 ]; then
  # DID THIS AGENT ACTUALLY WRITE ANYTHING? Compare the recovery pathspec's dirt
  # against the fingerprint taken before the agent started. Unchanged means it wrote
  # nothing of its own — it stood down, died on the first call, or never started —
  # and every dirty file under that pathspec therefore belongs to another writer.
  POST_RUN_DIRT=$(git -C "$VAULT" status --porcelain -- \
    'AIOS/History/Log.md' \
    'AIOS/History/audits/after-action.md' \
    'AIOS/History/_ingested' \
    'AIOS/Maps/Knowledge Map.md' \
    $SCOPE_PROJECT_PATHS \
    '+/_sessions' 2>/dev/null)
  # A usage-limit refusal also writes nothing, and until 2026-09-16 it landed here as
  # STOOD DOWN blaming "another writer" (09-15 16:40, 09-16 12:05 — both transcripts
  # were one line: "You've hit your session limit"). Name it, as FAILED, so the
  # session-start health check reports it instead of reading a silent death.
  LIMIT_RE="hit your (session|usage|weekly) limit"
  if [ "$POST_RUN_DIRT" = "$PRE_RUN_DIRT" ] && grep -qiE "$LIMIT_RE" "$TRANSCRIPT" 2>/dev/null; then
    echo "$(TS) FAILED — SESSION LIMIT, $REMAIN digest(s) still queued, nothing written — $(grep -iEm1 "$LIMIT_RE" "$TRANSCRIPT" | cut -c1-160)" >> "$LOG"
    exit 0
  fi
  if [ "$POST_RUN_DIRT" = "$PRE_RUN_DIRT" ]; then
    # NOT a failure of this job in the sense the FAILED line implies, so say what
    # actually happened. Committing here is the 2026-09-13 16:00 bug: it would title
    # another run's live work "run died", and because step 0 recognises partial-ingest
    # commits by that exact message, the next run would then walk back and re-read a
    # commit that is not ingest synthesis at all.
    echo "$(TS) STOOD DOWN — $REMAIN digest(s) still queued and this agent wrote NOTHING under the recovery pathspec (unchanged since before it started). Committing nothing: any dirt there belongs to another writer — most likely an interactive /aios-ingest, which this job's lock cannot see." >> "$LOG"
    if [ -n "$DIRTY" ]; then
      echo "$(TS) left uncommitted (another writer holds these):" >> "$LOG"
      printf '%s\n' "$DIRTY" | sed 's/^/    /' >> "$LOG"
    fi
    exit 0
  fi
  echo "$(TS) FAILED — $REMAIN digest(s) still queued (session limit or error); the next retry fire (08:00/12:00/16:00) will pick it up" >> "$LOG"
  # A dead run leaves synthesized-but-uncommitted note edits. Left dirty, the next
  # fire re-ingests the same digest on top of them. Commit rather than revert —
  # discarding real synthesis to protect against duplicate lines is the worse trade;
  # the commit is labelled so a human can see what to reconcile.
  if [ -n "$DIRTY" ]; then
    # PATHSPEC, NEVER `-A` — changed 2026-08-16 (register row 131's other half).
    # This is a recovery path: the agent died, so nothing here knows which files were
    # its own. `-A` answered that by taking everything, which sweeps a CONCURRENT
    # writer's uncommitted work into a commit titled "aios: partial ingest" — and
    # step 0's walk-back then replays it as if it were ingest synthesis. The vault is
    # one working tree with several writers (interactive sessions, the weekly register
    # pass, the Stop-hook digest), and on 2026-08-16 the inverse fired for real: a
    # 2-line interactive commit absorbed six of this job's files.
    #
    # It does not have to guess. The ingest's legal write targets are enumerated in
    # aios-ingest.md's Rules ("Write only to <layer>/projects/, AIOS/History/Log.md,
    # and Knowledge Map") plus the artifacts its own steps create — the archived
    # digests (step 3), the register rows (step 5) and the queue files it drains.
    # Anything outside that set belongs to another writer BY CONSTRUCTION: a skill, a
    # system script or a hook is not something an ingest edits.
    # KEEP THE MESSAGE — step 0 recognises partial runs by the literal
    # "aios: partial ingest" prefix and by nothing else.
    git -C "$VAULT" add -- \
      'AIOS/History/Log.md' \
      'AIOS/History/audits/after-action.md' \
      'AIOS/History/_ingested' \
      'AIOS/Maps/Knowledge Map.md' \
      $SCOPE_PROJECT_PATHS \
      '+/_sessions' 2>/dev/null
    # `--quiet` exits 1 when something IS staged. An empty stage means the dirt was
    # entirely another writer's, and committing nothing is the correct outcome.
    if ! git -C "$VAULT" diff --cached --quiet 2>/dev/null; then
      git -C "$VAULT" commit -q -m "aios: partial ingest — run died with $REMAIN digest(s) still queued" \
        && echo "$(TS) committed partial work (own paths only); next fire starts on a clean tree — review for duplicated lines" >> "$LOG"
    fi
    # Name what was deliberately left behind. Silence here would be indistinguishable
    # from "there was nothing else", which is what made the absorbing direction
    # invisible for a full day.
    LEFT=$(git -C "$VAULT" status --porcelain 2>/dev/null)
    if [ -n "$LEFT" ]; then
      echo "$(TS) left uncommitted — not this run's paths, another writer holds them:" >> "$LOG"
      printf '%s\n' "$LEFT" | sed 's/^/    /' >> "$LOG"
    fi
  fi
elif [ -n "$DIRTY" ]; then
  echo "$(TS) INCOMPLETE — queue drained but tree dirty (commit step skipped); run 'git -C $VAULT status'" >> "$LOG"
else
  # COMMITTED IS NOT SYNCED, and until 2026-09-05 this branch could not tell the
  # difference. The first fire after the Omarchy cutover drained the queue, wrote
  # the wiki, committed — and could not push, because a systemd user service
  # inherits no SSH agent and the key has a passphrase. It logged "done" and
  # exited 0. Same silent-success class as the Library/Logs bug found the same
  # hour: the vault diverges from the other machine with nothing saying so, and
  # the next session pays for it in a conflicted rebase instead of a fast-forward.
  UP=$(git -C "$VAULT" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo origin/main)
  if ! git -C "$VAULT" fetch -q origin 2>/dev/null; then
    echo "$(TS) UNSYNCED — queue drained and committed, but 'git fetch origin' FAILED (unattended runs have no ssh agent; check the deploy key). This vault is diverging from its remote." >> "$LOG"
  else
    AHEAD=$(git -C "$VAULT" rev-list --count "$UP..HEAD" 2>/dev/null || echo 0)
    if [ "${AHEAD:-0}" -gt 0 ]; then
      echo "$(TS) UNSYNCED — queue drained and committed, but $AHEAD commit(s) never reached $UP; push by hand and check the job's credentials" >> "$LOG"
    else
      echo "$(TS) done — queue drained, committed, pushed" >> "$LOG"
    fi
  fi
fi
