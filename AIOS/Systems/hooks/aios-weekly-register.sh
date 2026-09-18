#!/bin/sh
# AIOS weekly register pass — launchd runs this Sunday 09:00, retrying at 13:00
# and 17:00; headless `/after-action-apply --draft` when the after-action register
# has open rows, no-op when it doesn't.
# Loaded via ~/Library/LaunchAgents/com.aios.weekly-register.plist.
# launchd (not cron) so a fire missed while the Mac slept runs on wake.
# Log: $(aios_log_dir)/aios-register.log — see aios-scheduled-ingest.sh.
#
# WHY THIS JOB EXISTS. Measured 2026-08-07: detection on the after-action register
# is autonomous — 57 rows on 8 of 9 days — and **application has never once run
# without a human asking**. `applied` sat frozen at 14 for four days while `open`
# climbed 13 → 35. km-rotate, log-rollup and open-flags each started draining the
# moment aios-check.sh grew a detection line for them; this register got the
# detection line and no act half. This is the trigger.
#
# WHY --draft, AND WHY THAT IS THE WHOLE POINT. after-action's standing constraint
# is that mechanical drift applies itself and judgment waits for you, and it holds
# "on the unattended scheduled run, where nobody is watching" — which is this run.
# So this job never applies anything. It does the half that is expensive and safe:
# open every row's target file and reach a defensible verdict. Saying yes stays a
# human act, and by then the reading is already done.
#
# A job that applied its own verdicts would rewrite the OS's own procedure files
# weekly with nobody reading either the change or the reasoning. That is a worse
# failure than the backlog it would be clearing.
# /usr/bin/core_perl is where Arch puts `shasum` (perl-Digest-SHA); without it
# the guard-drift stamp is unverifiable under this stripped PATH. /opt/homebrew
# stays for the macOS side -- an absent dir on PATH costs nothing.
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/usr/bin/core_perl:/bin"
# The plist passes AIOS_VAULT; honor it rather than hardcoding, so the two cannot
# silently disagree if the vault ever moves.
VAULT="${AIOS_VAULT:-$HOME/code/aios}"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"   # mtime()/nosleep() — the BSD/GNU shim
REGISTER="$VAULT/AIOS/History/audits/after-action.md"
AIOS_LOGDIR=$(aios_log_dir)
LOG="$AIOS_LOGDIR/aios-register.log"

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
WEEKSTAMP="$AIOS_LOGDIR/aios-register.lastweek"
ROWS=5          # rows per pass; see the bound below
TS() { date -u +%Y-%m-%dT%H:%M:%SZ; }

count_open() { grep -c '| open |' "$REGISTER" 2>/dev/null || echo 0; }

# stray_paths: given `git status --porcelain` on stdin, print the entries that are
# NOT the two files a --draft pass is allowed to touch. This is the check that
# catches an unattended run applying a change, so it gets a self-check of its own —
# a violation detector whose regex silently matches nothing is worse than none,
# because it reports success on every run including the bad one.
stray_paths() {
  awk 'NF' | grep -vE ' (AIOS/History/audits/after-action\.md|AIOS/History/Log\.md)$' || true
}

# `sh aios-weekly-register.sh --selftest` — asserts both directions and exits.
# No fixtures, no claude, no launchd; runnable any time.
if [ "${1:-}" = "--selftest" ]; then
  p=0; f=0
  t() { got=$(printf '%s\n' "$2" | stray_paths | awk 'NF' | wc -l | tr -d ' ')
        if [ "$got" = "$3" ]; then p=$((p+1)); echo "  ok   $1"
        else f=$((f+1)); echo "  FAIL $1 (wanted $3 stray, got $got)"; fi; }
  t "a clean tree is not a violation"                    ""                                            0
  t "the register alone is allowed"                      " M AIOS/History/audits/after-action.md"      0
  t "the Log alone is allowed"                           " M AIOS/History/Log.md"                      0
  t "register + Log together are allowed"                " M AIOS/History/audits/after-action.md
 M AIOS/History/Log.md"                                                                                0
  t "an APPLIED skill edit is a violation"               " M AIOS/Skills/aios-ingest.md"               1
  t "a hook edit is a violation"                         " M .claude/hooks/vault-write-guard.sh"       1
  t "a violation is caught alongside allowed files"      " M AIOS/History/Log.md
 M AIOS/Skills/after-action.md"                                                                        1
  t "an untracked new file is a violation"               "?? AIOS/Skills/invented-skill.md"            1
  # The trap that makes the regex worth testing: the allowed paths are anchored to
  # end-of-line, so a DIFFERENT file whose name merely contains one of them must
  # still count. Without the anchor+space this passes as clean.
  t "a lookalike path is not mistaken for the register"  " M archive/AIOS/History/Log.md.bak"           1
  echo "aios-weekly-register --selftest: $p passed, $f failed"
  [ "$f" -eq 0 ]
  exit $?
fi

echo "$(TS) heartbeat — invoked" >> "$LOG"

# Three fires a week, ONE pass. 09:00 is the real run; 13:00 and 17:00 exist
# because the 08:00 ingest can still hold the lock at 09:00 (they share it, see
# below) and a weekly job that silently skips a whole week on a 15-minute overlap
# is a weekly job that runs monthly. The week stamp is what keeps the retries from
# becoming three passes: %G-%V is the ISO week, so it rolls on Monday and a
# Sunday-evening retry still matches its own Sunday morning.
WEEK=$(date +%G-%V)
# Rotating whole-note wall sweep, one layer per week (register row 138). A per-diff
# gate cannot see a crossing that PREDATES the diff — by construction — so a crossing
# introduced by an earlier run is invisible to every future gate. On 2026-08-17 a
# whole-note pass found two the diff gates had passed over for weeks. One layer a week
# keeps each pass cheap and covers the vault monthly; the modulus is the ISO week, so
# the rotation is deterministic and needs no stored cursor.
# `10#` is load-bearing: date +%V zero-pads, and POSIX arithmetic reads a leading zero
# as OCTAL — so weeks 08 and 09 are invalid octal and would abort this script under
# `set -u` two weeks a year, silently skipping both the drain and the sweep.
# THE ROTATION IS DERIVED from layers.tsv, so a vault with one scope sweeps that
# scope every week and a vault with five covers all five — no edit here either way.
# `AIOS` is appended as its own slot: the OS's own files are nobody's scope and
# would otherwise never be swept. A vault with no declared scopes still sweeps AIOS.
WALL_SCOPES=$(awk -F'\t' '/^[[:space:]]*#/ {next} NF >= 3 && $1 != "" {print $1}' \
                "$VAULT/AIOS/Systems/layers.tsv" 2>/dev/null)
WALL_SCOPES="$WALL_SCOPES
AIOS"
WALL_N=$(printf '%s\n' "$WALL_SCOPES" | grep -c .)
WALL_LAYER=$(printf '%s\n' "$WALL_SCOPES" | grep . \
             | sed -n "$(( 10#$(date +%V) % WALL_N + 1 ))p")
if [ "$(cat "$WEEKSTAMP" 2>/dev/null)" = "$WEEK" ]; then
  echo "$(TS) already ran this week ($WEEK), skipping" >> "$LOG"
  exit 0
fi

OPEN=$(count_open)
if [ "$OPEN" -eq 0 ]; then
  echo "$(TS) register empty, skipping" >> "$LOG"
  echo "$WEEK" > "$WEEKSTAMP"
  exit 0
fi

# SHARES THE INGEST'S LOCK, deliberately. Both this job and /aios-ingest's Mode A
# write AIOS/History/audits/after-action.md — the ingest appends rows while this
# annotates them — and two agents rewriting one markdown table is how a register
# loses rows. One lock is the serialization point for "something is rewriting the
# vault"; a second lock would only serialize this job against itself, which launchd
# already does. Cost: a register pass blocked by a live ingest waits for the next
# retry fire, which is exactly what the retries are for.
LOCK="$VAULT/.aios-ingest.lock"
if [ -d "$LOCK" ]; then
  AGE=$(( $(date +%s) - $(mtime "$LOCK" || date +%s) ))
  # Same 4200s reaper as aios-scheduled-ingest.sh: a SIGKILL or reboot mid-run
  # strands the mkdir lock (the EXIT trap never fires) and every later fire skips.
  if [ "$AGE" -gt 4200 ]; then
    echo "$(TS) reaping stale lock (age ${AGE}s)" >> "$LOG"
    rmdir "$LOCK" 2>/dev/null
  fi
fi
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(TS) ingest or register pass in flight (lock held), skipping to next fire" >> "$LOG"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

echo "$(TS) drafting verdicts for $ROWS of $OPEN open row(s); wall sweep layer: $WALL_LAYER" >> "$LOG"

# One transcript per run, pruned at 14 days. The ingest learned this the hard way:
# 45 of 46 failures were undiagnosable because the next fire clobbered the evidence.
TRANSCRIPT="$AIOS_LOGDIR/aios-register-transcript-$(date -u +%Y%m%dT%H%M%SZ).log"
find "$AIOS_LOGDIR" -name 'aios-register-transcript-*.log' -mtime +14 -delete 2>/dev/null

# caffeinate -i: launchd DarkWakes the Mac to fire this and macOS re-sleeps ~40s
# later, which kills a multi-minute `claude -p` mid-stream. ⚠️ KNOWN INSUFFICIENT —
# proved for the ingest on 2026-08-05: -i blocks idle sleep but does not hold open a
# DarkWake maintenance window, and an unattended fire on battery with the lid shut
# still cannot hold a network stream. Same open problem, same partial mitigation;
# this job is cheaper to lose than an ingest, since nothing is applied.
# timeout -k: plain `timeout` sends TERM only and claude ignores it. 1800s is
# generous for 5 read-only workers.
# Scoped allowlist, not --dangerously-skip-permissions. --draft writes exactly two
# things — register annotations and a Log line — plus the commit; the
# vault-write-guard PreToolUse hook still constrains where any write can land.
cd "$VAULT" && nosleep timeout -k 300 1800 claude -p "/after-action-apply $ROWS --draft

You are the scheduled weekly register pass, launched by aios-weekly-register.sh. The \`.aios-ingest.lock\` directory and any running \`claude -p\` process you may find are YOUR OWN — the wrapper took the lock before starting you. Do not interpret them as a concurrent run and do not stand down.

--draft is not advisory and it is not a formality. Apply NOTHING. Do not edit a single skill, system, agent, command or settings file. Every row you verdict keeps Status \`open\`; your output is the verdict and the literal old/new text written into that row's *Proposed change* cell, so that a human can say yes in seconds instead of re-reading five target files. A run that applied a change is a failed run even if every change was correct.

PREFER ROWS THAT CARRY NO PRIOR VERDICT. Oldest-first is the ordering, but a row already annotated by an earlier draft pass, or already marked ESCALATED with its analysis recorded, has had its expensive half paid — re-verdicting it every week burns the batch on the same rows forever. Two of the oldest open rows are permanently un-actionable by an agent (one targets a file the write guard refuses agent edits to; one targets a repo outside this vault), so a strict oldest-five would spend 40% of every pass on them. Skip a row whose Proposed-change cell already ends in a recorded verdict and take the next unverdicted one; if every open row is already verdicted, say so and drain nothing.

THEN, SEPARATELY, run a WHOLE-NOTE wall sweep over the $WALL_LAYER layer — dispatch \`layer-leak-auditor\` per note, NOT diff-scoped. This is the half a per-diff gate cannot do: it audits each run's own added lines, so a cross-layer crossing introduced by an earlier run is invisible to it forever. Findings become NEW register rows scoped to that layer, applied nothing. Obey the sanitize rule when you write them: a row about a crossing NAMES the shape and the location and never reproduces the identity string — a register row is a report, and on 2026-08-17 one carried the very address its own fix had just removed.

No human is attached to this run and no answer will ever come back. Never end your turn on a question — decide, act, and finish. If a register-worker dies, retry it once; if it still fails, record that row as un-verdicted this pass and move to the next. Always finish by writing the one Log line and committing." \
  --permission-mode acceptEdits \
  --allowedTools "Read,Write,Edit,Grep,Glob,Bash,Task,TodoWrite" \
  > "$TRANSCRIPT" 2>&1

# An expired/revoked OAuth token exits 0 and writes nothing, so it would otherwise
# land as the same generic failure line as a genuinely hard row. Name it — four
# consecutive ingest fires died this way on 2026-08-02/03 and every one read as a
# queue problem until someone opened the transcript by hand.
AUTH_RE='Failed to authenticate|OAuth access token has been revoked|OAuth session expired'
if grep -qiE "$AUTH_RE" "$TRANSCRIPT" 2>/dev/null; then
  echo "$(TS) AUTH FAILED — $(grep -iEm1 "$AUTH_RE" "$TRANSCRIPT" | cut -c1-160)" >> "$LOG"
  echo "$(TS) fix: run \`claude\` interactively and /login; the next fire recovers on its own" >> "$LOG"
fi

# claude -p exits 0 even on session-limit or mid-run death, so the exit code proves
# nothing. The real check is the two invariants --draft promises:
#   1. it drafted    → the register changed
#   2. it applied nothing → NOTHING ELSE changed
# (2) is the one worth failing loudly over. A run that edited a skill file has
# violated the constraint this whole job is shaped around, and it must not be
# discovered a week later.
DIRTY=$(git -C "$VAULT" status --porcelain 2>/dev/null)
STRAY=$(printf '%s\n' "$DIRTY" | stray_paths)
if [ -n "$STRAY" ]; then
  echo "$(TS) ⚠️ DRAFT VIOLATION — the pass left changes outside the register and the Log:" >> "$LOG"
  printf '%s\n' "$STRAY" | sed 's/^/    /' >> "$LOG"
  echo "$(TS) transcript: $TRANSCRIPT — review before committing anything" >> "$LOG"
  exit 1
fi

if [ -n "$DIRTY" ]; then
  # Drafted but did not commit: real verdicts sit uncommitted and the next fire's
  # git state is ambiguous. Commit them here rather than leaving the tree dirty —
  # the content is annotations, and losing them costs the whole pass again.
  git -C "$VAULT" add AIOS/History/audits/after-action.md AIOS/History/Log.md 2>/dev/null
  git -C "$VAULT" commit -qm "aios: weekly register draft — verdicts for $ROWS row(s), none applied" 2>/dev/null \
    && echo "$(TS) committed the pass's uncommitted draft" >> "$LOG"
fi

AFTER=$(count_open)
echo "$(TS) done — $OPEN open before, $AFTER after (drafts do not close rows; run /after-action-apply to confirm them)" >> "$LOG"
echo "$WEEK" > "$WEEKSTAMP"
