#!/bin/sh
# AIOS mechanical check — every janitor-skill step that a command can settle.
# Prints ONLY failures (quiet when clean, so it can hang off SessionStart) and
# exits 1 if any check failed. Nothing here edits a file; each hit names the
# skill that fixes it.
#
# Covers, by skill:
#   km-rotate   step 1   — oversized Knowledge Map lines
#   log-rollup  step 1   — Log entries older than the current month
#   open-flags  steps 1-2 — the flag register (count per note, oldest by blame)
#   after-action step 2  — dead paths, dangling wikilinks, Skill Map gaps,
#                          missing global symlinks
#   wiki-lint   checks 1,3,4 — the mechanical half (schema, Knowledge Map coverage
#                          both ways). Check 2 — the external-claim TTL half only:
#                          `(checked|verified YYYY-MM-DD)` tags older than 7 days.
#                          Check 5 (orphans) is NOT implemented here; the rest of
#                          check 2 (untagged staleness), duplicates and
#                          contradictions stay judgment and stay in the skill.
#
# Usage: sh AIOS/Systems/aios-check.sh [--verbose] [--file <path>]
#
# --file runs ONLY the three authorship-time checks — dead paths, dangling
# wikilinks, Skill Map registration — scoped to one file, and exits. Same
# detection code, second trigger point: the whole-vault run happens at
# SessionStart, which catches a bad `[[link]]` at the start of the NEXT session,
# capped at 5 lines and competing with every other standing backlog for
# attention. Scoped to the file being written, it lands in the same turn as the
# edit. Wired to PostToolUse in .claude/settings.json.
#
# The other ~20 checks are deliberately NOT available per-file: they measure
# whole-vault state (Log bytes, KM line widths, the flag register, launchd
# parity) where one file's contribution means nothing.
#
# ponytail: POSIX sh, no bashisms. Detection only — the skills still do the work.
set -u

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
VAULT="${AIOS_VAULT:-$HOME/code/aios}"
cd "$VAULT" || { echo "aios-check: no vault at $VAULT" >&2; exit 2; }

KM="AIOS/Maps/Knowledge Map.md"
LOG="AIOS/History/Log.md"
SKILL_MAP="AIOS/Maps/Skill Map.md"
KM_MAX=1500          # km-rotate's own threshold
KM_WARN=$((KM_MAX * 9 / 10))   # 90% of it — the km-rotate lead-time band. Derived,
                     # never a second literal, so the two cannot drift apart (same
                     # call as ARCHIVE_MAX == SHARD_MAX below).
LOG_MAX=200000       # log-rollup: the LIVE Log.md trip (cadence)
ARCHIVE_MAX=100000   # log-rollup: an archive part's cap (readability; == SHARD_MAX)
FLAG_AGE_DAYS=30     # open-flags step 4 escalation age
WIRE_STALE_DAYS=7    # digest-wire liveness: how long a moved-but-undigested tip may
                     # sit before it stops being ordinary hook lateness. A digest
                     # arrives at the NEXT session end, so this must be days, not
                     # hours — see the wire-liveness block for why absence alone is
                     # the wrong signal.
MAX_LIST=5           # cap per-check output; --verbose lifts it

# --- the scope list, derived ------------------------------------------------
# Every check below that walks "the scopes" reads this, so adding a scope to
# AIOS/Systems/layers.tsv is the ONE edit needed — no check carries its own
# hardcoded list. A hardcoded list is how a new scope ends up silently
# unchecked while every check still reports clean.
#
# SCOPE_GLOBS holds shell glob PATTERNS, left unquoted at each use so they
# expand. A scope whose directory does not exist yet contributes a pattern that
# matches nothing, which every consumer already handles with `[ -f "$f" ]`.
SCOPES=$(awk -F'\t' '/^[[:space:]]*#/ {next} NF >= 3 && $1 != "" {print $1}' \
           "AIOS/Systems/layers.tsv" 2>/dev/null)
scope_globs() { # $1 = suffix pattern, e.g. projects/*.md
  for _s in $SCOPES; do printf '%s/%s ' "$_s" "$1"; done
}
SCOPE_PROJECTS="$(scope_globs 'projects/*.md')$(scope_globs 'projects/*/*.md')"
SCOPE_PROJECT_DIRS="$(scope_globs 'projects')"
SCOPE_NOTES="$(scope_globs 'notes/*.md')$(scope_globs 'notes/*/*.md')"

ONE_FILE=""          # --file <path>: scope the authorship-time checks to one file
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose) MAX_LIST=1000 ;;
    --file)    shift; ONE_FILE="${1:-}" ;;
  esac
  [ $# -gt 0 ] && shift
done

# The caller is a hook and sends an absolute path; the globs below are all
# vault-relative. Normalise once, here, rather than at each use.
case "$ONE_FILE" in "$VAULT"/*) ONE_FILE=${ONE_FILE#"$VAULT"/} ;; esac

# The source sets the three checks below read. Whole-vault by default; one file
# under --file. Left unquoted at the point of use so the globs still expand —
# no path in these trees carries a space.
SCOPE_DEAD="AIOS/Skills/*.md AIOS/Systems/*.md .claude/agents/*.md"
SCOPE_LINK="AIOS/Skills/*.md AIOS/Systems/*.md"
SCOPE_SKILL=""       # --file only: the one skill name to check for registration
if [ -n "$ONE_FILE" ]; then
  # A file outside the three trees has nothing here to check. Exit 0 rather than
  # complain: the hook fires on EVERY write, and a per-file check that objects to
  # files it does not cover is a check that gets unwired within a day.
  case "$ONE_FILE" in
    AIOS/Skills/*.md|AIOS/Systems/*.md|.claude/agents/*.md) ;;
    *) exit 0 ;;
  esac
  [ -f "$ONE_FILE" ] || exit 0    # deleted or renamed between write and hook
  SCOPE_DEAD=$ONE_FILE
  # The wikilink check covers Skills and Systems only, and --file must not quietly
  # widen it: an agent file's links have never been in that population, and the
  # failure message names the two trees. Same scope, fewer files.
  SCOPE_LINK=""
  case "$ONE_FILE" in AIOS/Skills/*.md|AIOS/Systems/*.md) SCOPE_LINK=$ONE_FILE ;; esac
  # Only a file in AIOS/Skills/ is a skill that Skill Map must carry. Resolved
  # here, not inside the check's command substitution: a `case` nested in `$( )`
  # is a parser trap — the pattern's `)` closes the substitution in some shells.
  case "$ONE_FILE" in AIOS/Skills/*.md) SCOPE_SKILL=$(basename "$ONE_FILE" .md) ;; esac
  MAX_LIST=1000                   # one file cannot flood; never truncate its findings
fi

FAILED=0
fail() { FAILED=1; echo "$@"; }

# On-demand output dirs a skill names but must NOT be pre-created: an empty
# untracked dir is the invisible-stray-tree failure ([[Log]] 2026-08-04), so the
# skill's own mkdir -p makes it on first real use. Every after-action run since
# has re-derived that ruling by hand — it lives here now so it stops being
# re-litigated once a day.
PATH_EXEMPT="AIOS/History/reviews"

# WHOLE-VAULT-ONLY CHECKS START HERE and end at the dead-path block below. Every
# one of them measures aggregate state — KM line widths, Log bytes, the flag
# register — which one edited file cannot move and which --file has no business
# printing on every write. Guarded as a block rather than per-check on purpose: a
# check added inside this range is whole-vault by default, which is the safe
# direction. A check that should be per-file goes below the `fi`.
if [ -z "$ONE_FILE" ]; then

# --- km-rotate: Knowledge Map lines that have become logs ---------------------
# BYTES, and the message says so -- but bytes must be FORCED with LC_ALL=C, not
# assumed. The old claim here ("byte-based, verified under both LC_ALL=C and
# en_US.UTF-8") held on macOS BWK awk and is FALSE on gawk, whose `length` counts
# CHARACTERS in a UTF-8 locale. On Arch this gate under-reported every map line
# by its multibyte overhead -- 16-20 bytes on a typical line -- in the PERMISSIVE
# direction, so a line could cross 1500 while the check still printed clean.
# Measured 2026-09-05: KM line 13 reported 1476, true size 1496. Keep LC_ALL=C on
# both invocations below and on all three in km-measure.sh; the two are pinned
# against each other by test-km-measure.sh and must be changed together.
# This also printed "chars" for months while
# aios-ingest step 1c also said "chars" — so a run measured with Python `len`,
# shipped a line at 1488 characters, and this gate failed it at 1504 bytes. A map
# line is dense with em dashes, arrows and ⚠️ at 3-6 bytes each, which is 1-2%
# right where the threshold sits. AIOS/Systems/km-measure.sh prints this same
# number and is what the skill and the lint runner are pointed at.
if [ -f "$KM" ]; then
  over=$(LC_ALL=C awk -v m="$KM_MAX" 'length > m { printf "line %d: %d bytes\n", NR, length }' "$KM")
  if [ -n "$over" ]; then
    n=$(printf '%s\n' "$over" | wc -l | tr -d ' ')
    fail "aios-check: $n Knowledge Map line(s) over ${KM_MAX} bytes — run km-rotate (measure with: sh AIOS/Systems/km-measure.sh):"
    printf '%s\n' "$over" | head -"$MAX_LIST" | sed 's/^/  /'
  fi

  # THE LEAD-TIME BAND — echo, not fail, and deliberately NOT verbose-gated.
  # Echo, because a line under the gate is not drift: nothing is broken, the fix is
  # elective, and the exit code must stay 0. Default-visible, against this file's own
  # verbose-only ruling, because that ruling is scoped to a PERMANENT known non-problem
  # (the legacy PR numbers, the wall-clock TTL, the oversized shards) and this band is
  # neither: it is bounded and self-clearing — one km-rotate run rewrites the line as a
  # ~500-byte summary and silences it. Verbose-only would reproduce the exact failure it
  # exists to stop, since the runs the gate catches are unattended ingests that never
  # pass --verbose.
  # Evidence: the work-layer line measured 1480/1500 on 2026-08-13 and 1491/1500 on
  # 2026-08-16, and this check exited 0 both times. The 08-16 ingest then DECLINED to
  # record a standing rule at step 1c rather than pay for an unplanned rotation mid-run
  # — a non-write, which leaves no artifact anywhere. A binary gate at the ceiling gives
  # the rotation zero lead time and hands the bill to the one run least able to pay it.
  # BOTH BOUNDS EXCLUSIVE. Exactly KM_WARN is silent (same call as the TTL block's
  # age > 7), and a line over KM_MAX belongs to the gate above and must not ALSO print
  # this softer instruction — two contradictory lines about one line is worse than one.
  # TRIPWIRE: if this band ever holds a standing population instead of a line or two, it
  # has become a backlog and the verbose-only ruling starts applying to it.
  near=$(LC_ALL=C awk -v m="$KM_MAX" -v w="$KM_WARN" \
           'length > w && length <= m { printf "line %d: %d bytes (%d%% of %d)\n", NR, length, int(length * 100 / m), m }' "$KM")
  if [ -n "$near" ]; then
    n=$(printf '%s\n' "$near" | wc -l | tr -d ' ')
    echo "aios-check: $n Knowledge Map line(s) past ${KM_WARN} bytes and still under the ${KM_MAX} gate — run km-rotate now, while it is cheap (measure with: sh AIOS/Systems/km-measure.sh):"
    printf '%s\n' "$near" | head -"$MAX_LIST" | sed 's/^/  /'
  fi
fi

# --- log-rollup: entries left behind by the month, and the byte gate ---------
# The month check alone went blind to the volume. On 2026-08-14 the Log held 166
# entries ALL dated 2026-08 — 289KB that no month boundary would touch for
# another 17 days — while Log-2026-07.md had already reached 319KB, larger than
# the live Log and past what an agent reads in one call. A calendar bucket sized
# for the June rate (~27KB/month) does nothing at the August rate (~20KB/day),
# so log-rollup now trips on bytes and the month check is the second of two.
#
# ARCHIVES ARE MEASURED TOO, and by a STRICTER number. The rotation destination is
# exactly where the unreadable file turned up, so exempting archives the way the
# shard check does would re-create the hole one level down. The two caps differ on
# purpose: Log.md is read constantly but by TAIL (the SessionStart hook takes the
# newest handful), so its size is a cadence question and a low cap just means
# rotating every other day. An archive is read rarely and WHOLE, by something
# hunting old context, so its size is a readability question and stays at 100KB.
if [ -f "$LOG" ]; then
  now=$(date +%Y-%m)
  stale=$(grep -oE '^- \*\*[0-9]{4}-[0-9]{2}' "$LOG" | sed 's/^- \*\*//' \
          | awk -v now="$now" '$1 < now' | sort | uniq -c | tr -s ' ')
  if [ -n "$stale" ]; then
    total=$(printf '%s\n' "$stale" | awk '{s += $1} END {print s}')
    fail "aios-check: $total Log entr(ies) predate $now — run log-rollup:"
    printf '%s\n' "$stale" | head -"$MAX_LIST" | sed 's/^ */  /'
  fi

  # ECHO, NOT FAIL — same ruling as the project-shard scan below it. Rotation is
  # cheap but it is still a deliberate act on the audit trail, and a standing
  # backlog that paints every session red is the nag channel open-flags Mode B
  # exists to prevent.
  oversize=$(for f in "$LOG" AIOS/History/Log-*.md; do
               [ -f "$f" ] || continue
               # Leading-paren patterns, as at the Knowledge Map scan above: a bare
               # `pattern)` inside $( ) closes the command substitution early in
               # some shells, and this whole loop is inside one.
               case "$f" in ("$LOG") cap=$LOG_MAX ;; (*) cap=$ARCHIVE_MAX ;; esac
               sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
               [ -n "$sz" ] && [ "$sz" -gt "$cap" ] && printf '%s\t%s\t%s\n' "$sz" "$f" "$cap"
               continue
             done | sort -rn)
  if [ -n "$oversize" ]; then
    n=$(printf '%s\n' "$oversize" | grep -c .)
    echo "aios-check: $n Log file(s) over cap (Log.md $((LOG_MAX / 1000))KB, archives $((ARCHIVE_MAX / 1000))KB) — run log-rollup (measure with: wc -c AIOS/History/Log*.md):"
    printf '%s\n' "$oversize" | head -"$MAX_LIST" \
      | awk -F'\t' '{ printf "  %6.0fKB  %s  (cap %.0fKB)\n", $1/1000, $2, $3/1000 }'
  fi
fi

# --- open-flags: the register, and flags nobody has touched in a month -------
# git blame dates the flag LINE'S LAST CHANGE — an anchor outside the vault's own
# prose, per the Orchestrator's "score against what can't argue back". It is a
# LOWER BOUND on flag age: a shard an ingest rewrites IN PLACE resets those lines'
# blame. An APPENDED provenance entry does not — which is why source-history.md,
# long assumed to have useless blame, in fact holds the oldest valid flag dates in
# the vault and must NOT be skipped here.
#
# ONE blame per file, indexed by line. The per-line version forked `git blame` 295
# times and cost 6.0s of a 6.5s SessionStart hook that runs on every startup and
# every ingest — to compute a number that is guaranteed zero until the corpus is
# older than the threshold. Same output, 23 forks.
FLAG_RE='⚠️|OPEN —|OPEN:|parity gap'
# A marker inside a provenance/Source note is a RECORD OF a flag, not a flag —
# "resolved 1 — the EC-1508 marker", "all other ⚠️ pre-existing". source-history.md
# alone held 88 such lines, about a third of the project's apparent flag load, every
# one a false positive. Same exclusion open-flags.md applies in both its modes; if
# these two ever disagree the check is lying about the skill it exists to trigger.
# The optional -YYYY-MM suffix covers the monthly archives [[provenance-rollup]]
# rotates out: matching the shard by exact basename would let a rotated archive
# re-enter the flag population wholesale on the next SessionStart.
#
# The second alternative covers relocated SECTIONS, which the basename rule cannot
# reach: provenance-rollup's --extract mode moves a non-provenance section (today
# _history/km-activity-trail.md, 18 ⚠️ + 1 "parity gap") out of the shard under a
# name of its own. Same class of artifact, same false positives — a marker inside
# it is still a RECORD OF a flag. It was silent only because a new file's blame is
# younger than FLAG_AGE_DAYS; it would have started lying about 30 days after the
# move, which is the worst possible time to discover it.
#
# ANCHORED STRUCTURALLY, and that is the whole point. `_history` must be the
# IMMEDIATE parent: the leading (^|/) stops `incident_history/` and `my_history/`
# from matching, and the trailing [^/]+\.md$ stops the pattern crossing a `/` into
# a nested subdirectory. Rule D's carve-out was shipped as a loose `*_history/*`
# case-glob and had to be re-tightened as a security fix for exactly this reason.
# An over-broad exclusion here is the same failure in the other direction — it
# silently drops REAL flags from the population, and a flag register that quietly
# under-reports is worse than one that over-reports.
#
# SCOPE, DECIDED RATHER THAN INHERITED: this grep spans ./*/projects, so the
# _history exemption covers every scope, while the Rule D
# carve-out it resembles is work-only. That is deliberate, not an oversight. Rule
# D is a WRITE guard scoped to work/ because it enforces work-note TICKET
# conventions — an unrelated reason. The reason here is that a marker inside a
# provenance record is a record OF a flag in any layer, which is why the sibling
# source-history exclusion on this same line has always been layer-neutral too.
# Scoping one of the two alternatives to work/ would make this line disagree with
# itself. Note the exemption is currently broader than the tool that fills it:
# provenance-rotate.py --extract refuses shards outside work/projects|work/notes,
# so only work/ can produce a relocated section today.
# THE SECTION-LEVEL HALF, shipped 2026-08-16 — the two rules above are PATH-keyed
# and open-flags.md:12 has always excluded a third shape they cannot reach: a
# provenance section INSIDE an otherwise ordinary note. An unsharded project keeps
# its provenance in a `## Source` section of the note itself rather than in a
# source-history shard, so every "resolved 1 — the … marker" line in it was counted.
# Row 76 (2026-08-08) recorded that it had put this exclusion into BOTH consumers and
# put it into one; the skill excluded these markers and this file counted them for
# eight days, which is the exact failure the invariant above names. Measured at the
# time of the fix: 11 false positives across 3 notes (7 + 3 + 1).
#
# ANCHORED STRUCTURALLY, same rule as the _history carve-out: a HEADING match, never
# prose. `##+` so a deeper nesting still counts, `Sources?` for both spellings, and a
# non-alphanumeric or end-of-line after it so `## Sourcemap` is not a provenance
# section. The cut is the FIRST such heading — provenance sits at the tail of a note
# by convention, and taking the first is the conservative direction: a marker above
# it stays in the population.
#
# The exemption is deliberately NOT the whole file. A note with a `## Source` section
# still has live flags in its body, and dropping the file wholesale would silently
# under-report — the failure direction this block calls worse than over-reporting.
SRC_HEAD_RE='^##+[[:space:]]*Sources?([^[:alnum:]]|$)'
# flag_cut <file> — 1-based line of the first provenance heading, or 0 for none
# (0 means count every line).
flag_cut() {
  awk -v re="$SRC_HEAD_RE" '$0 ~ re { print NR; found=1; exit } END { if (!found) print 0 }' "$1"
}
flagged=$(grep -rlE "$FLAG_RE" ./*/projects 2>/dev/null | sed 's|^\./||' \
          | grep -vE 'source-history(-[0-9]{4}-[0-9]{2})?\.md$|(^|/)_history/[^/]+\.md$')
if [ -n "$flagged" ]; then
  cutoff=$(( $(date +%s) - FLAG_AGE_DAYS * 86400 ))
  old_total=0
  old_list=""
  for f in $flagged; do
    cut=$(flag_cut "$f")
    # `git blame --line-porcelain` emits in file order, so counting content lines
    # (the `^\t` ones) tracks the file's own line number and the same cut applies.
    old=$(git blame --line-porcelain -- "$f" 2>/dev/null | awk -v cutoff="$cutoff" -v re="$FLAG_RE" -v cut="$cut" '
      /^author-time /      { ts = $2; next }
      /^\t/                { ln++
                             if (cut > 0 && ln >= cut) { ts = ""; next }
                             if (ts != "" && ts < cutoff && $0 ~ re) n++ ; ts = "" }
      END                  { print n + 0 }')
    if [ "${old:-0}" -gt 0 ]; then
      old_total=$((old_total + old))
      old_list="$old_list$old  $f
"
    fi
  done
  if [ "$old_total" -gt 0 ]; then
    # echo, not fail. Once the corpus ages past the threshold this is permanently
    # non-zero by construction — Mode B is read-only over the notes, so a sweep
    # never resets blame — and a permanently-red exit code stops distinguishing a
    # real dead path from the standing backlog. Same call as the other two backlogs.
    echo "aios-check: $old_total flag(s) untouched for ${FLAG_AGE_DAYS}d+ — run open-flags Mode B (the standalone sweep; rows go to AIOS/History/audits/flag-register.md, NOT the Log):"
    printf '%s' "$old_list" | sort -rn | head -"$MAX_LIST" | sed 's/^/  /'
  fi
  # open-flags step 1's register, verbatim input for the skill. Informational —
  # a flag is a commitment, not a failure, so it never sets the exit code.
  if [ "$MAX_LIST" -gt 5 ]; then
    echo "aios-check: open-flags register (informational):"
    for f in $flagged; do
      printf '  %4d  %s\n' \
        "$(awk -v re="$FLAG_RE" -v cut="$(flag_cut "$f")" \
             'cut > 0 && NR >= cut { exit } $0 ~ re { n++ } END { print n + 0 }' "$f")" "$f"
    done | sort -rn
  fi
fi

fi   # end whole-vault-only block

# --- after-action step 2: dead paths named in skills/systems/agents ----------
# Only backticked, unambiguous VAULT paths. Three filters, each earned on the
# first run: no globs or <placeholders>; no YYYY/MM/NNNN format templates; and
# the first segment must be a real top-level dir — that one drops `layer/project`
# (a Log-line tag shape) and paths belonging to some other repo entirely.
dead=$(grep -ohE '`[A-Za-z+][A-Za-z0-9_./+-]*/[A-Za-z0-9_./+-]*`' \
         $SCOPE_DEAD 2>/dev/null \
       | tr -d '`' | grep -v '[<*?]' | grep -vE 'YYYY|MM-DD|NNNN|####' \
       | sed 's|/$||' | grep '/' | sort -u \
       | grep -vxF "$PATH_EXEMPT" \
       | while read -r p; do
           [ -d "${p%%/*}" ] || continue
           [ -e "$p" ] || echo "$p"
         done)
if [ -n "$dead" ]; then
  n=$(printf '%s\n' "$dead" | wc -l | tr -d ' ')
  fail "aios-check: $n path(s) named in a skill/system/agent do not exist:"
  printf '%s\n' "$dead" | head -"$MAX_LIST" | sed 's/^/  /'
fi

# --- after-action step 2: dangling wikilinks ---------------------------------
# Code spans are stripped first — a `[[Log-2026-05]]` inside a format example
# names a file that need not exist.
dangling=$([ -n "$SCOPE_LINK" ] && sed 's/`[^`]*`//g' $SCOPE_LINK 2>/dev/null \
           | grep -ohE '\[\[[^]|#]+' | sed 's/\[\[//' | grep -v '[<>]' | sort -u \
           | while read -r l; do
               b=$(basename "$l")
               find . -path ./.git -prune -o -name "$b.md" -print 2>/dev/null | grep -q . || echo "$l"
             done)
if [ -n "$dangling" ]; then
  n=$(printf '%s\n' "$dangling" | wc -l | tr -d ' ')
  fail "aios-check: $n dangling wikilink(s) in AIOS/Skills or AIOS/Systems:"
  printf '%s\n' "$dangling" | head -"$MAX_LIST" | sed 's/^/  /'
fi

# --- after-action step 2: Skill Map registration drift -----------------------
missing=$( { if [ -n "$ONE_FILE" ]; then
               # --file: only this file's own registration. A newly written skill
               # is unregistered by construction for the seconds between the two
               # writes, so this is the check that fires on the edit that creates
               # the gap — not on the 40 that follow it.
               [ -n "$SCOPE_SKILL" ] && echo "$SCOPE_SKILL"
             else
               for f in AIOS/Skills/*.md; do basename "$f" .md; done
               for d in skills/*/; do basename "$d"; done
             fi; } 2>/dev/null \
           | while read -r n; do grep -qF "$n" "$SKILL_MAP" || echo "$n"; done)
if [ -n "$missing" ]; then
  n=$(printf '%s\n' "$missing" | wc -l | tr -d ' ')
  fail "aios-check: $n skill(s) missing from Skill Map:"
  printf '%s\n' "$missing" | head -"$MAX_LIST" | sed 's/^/  /'
fi

# --file stops here. Everything past this point measures whole-vault state, where
# one file's contribution is meaningless — and the hook that calls this runs on
# every write, so a per-file invocation must stay cheap enough to be invisible.
if [ -n "$ONE_FILE" ]; then
  [ "$FAILED" = 0 ] || echo "  (in $ONE_FILE — run 'sh AIOS/Systems/aios-check.sh' for the whole vault)"
  exit "$FAILED"
fi

# --- after-action step 2: portable skills not projected globally -------------
unlinked=$(for d in skills/*/; do
             n=$(basename "$d"); [ -e "$HOME/.claude/skills/$n" ] || echo "$n"
           done)
if [ -n "$unlinked" ]; then
  n=$(printf '%s\n' "$unlinked" | wc -l | tr -d ' ')
  fail "aios-check: $n portable skill(s) missing from ~/.claude/skills — run 'sh skills/link-global.sh':"
  printf '%s\n' "$unlinked" | head -"$MAX_LIST" | sed 's/^/  /'
fi

# --- wiki-lint check 1: frontmatter schema on wiki notes ---------------------
# A note carrying `parent:` inherits `sources` from its hub (2026-07-25 exemption).
badschema=$(for f in $SCOPE_PROJECTS; do
              [ -f "$f" ] || continue
              # agents.md is per-project CONFIG (aios-setup-project writes it),
              # not a wiki note — the note schema does not apply to it.
              [ "$(basename "$f")" = "agents.md" ] && continue
              head=$(head -30 "$f")
              printf '%s\n' "$head" | grep -q '^parent:' && continue
              printf '%s\n' "$head" | grep -q '^sources:' || echo "$f (no sources:, no parent:)"
            done)
if [ -n "$badschema" ]; then
  n=$(printf '%s\n' "$badschema" | wc -l | tr -d ' ')
  fail "aios-check: $n project note(s) missing frontmatter provenance — wiki-lint check 1:"
  printf '%s\n' "$badschema" | head -"$MAX_LIST" | sed 's/^/  /'
fi

# --- wiki-lint check 2: external-claim TTL (the mechanical half) ------------
# A `(checked YYYY-MM-DD)` / `(verified YYYY-MM-DD ...)` tag records that an external
# identifier (a SHA, a build id, a deploy state) was checked against its SOURCE on
# that date — not that the claim stays true. Nothing in the vault re-examines it, so
# the tag ages on wall-clock while `updated` and every other metadata test stays
# "fresh" (the failure mode wiki-lint check 2 names: a stale build id survived days
# past a deploy because nothing re-read it). Opt-in by construction: an UNTAGGED
# claim — hundreds of bare SHAs in the corpus, mostly immutable historical landing
# references that never go stale — is never flagged. Only a claim someone explicitly
# tagged ages out, which is why this starts near zero noise instead of firing on
# everything.
# Boundary: exactly 7 days old is still inside the window (age > 7, not >= 7) — the
# tag means "good for about a week," and day 7 is still that week.
# Echo, not fail: a wall-clock TTL is permanently non-zero once any tag ages past 7
# days — same standing-backlog shape open-flags/after-action reserve echo for above.
# And verbose-only for the same reason, which echo alone does not cover: this fires
# TODAY and in every SessionStart thereafter, so an unconditional line about a known
# standing backlog would break the header's "prints ONLY failures (quiet when clean)"
# promise that [[Skill Map]] repeats — the identical ruling the legacy PR-number block
# and the local-only digest wire below each already earned. The exit code is untouched
# either way; only whether the line lands in every session's context changes.
TTL_DAYS=7
civil_days() { # $1=YYYY $2=MM $3=DD -> days since a fixed epoch. Howard Hinnant's
                # days_from_civil: pure integer arithmetic, portable POSIX awk, no
                # mktime/gawk and no `date -d`/`date -j` flag split to maintain.
  awk -v y="$1" -v m="$2" -v d="$3" 'BEGIN {
    if (m <= 2) y -= 1
    e = int((y >= 0 ? y : y - 399) / 400); yoe = y - e * 400
    mm = (m > 2) ? m - 3 : m + 9
    doy = int((153 * mm + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    print e * 146097 + doe - 719468
  }'
}
today_days=$(civil_days "$(date +%Y)" "$(date +%m)" "$(date +%d)")
tags=$(grep --include='*.md' -rnoE '\((checked|verified) [0-9]{4}-[0-9]{2}-[0-9]{2}' \
         $SCOPE_PROJECT_DIRS 2>/dev/null)
if [ -n "$tags" ]; then
  stale=$(printf '%s\n' "$tags" | while IFS=: read -r f ln rest; do
            kind=$(printf '%s' "$rest" | grep -oE 'checked|verified')
            dt=$(printf '%s' "$rest" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
            y=${dt%%-*}; r2=${dt#*-}; mo=${r2%%-*}; da=${r2#*-}
            td=$(civil_days "$y" "$mo" "$da")
            age=$((today_days - td))
            [ "$age" -gt "$TTL_DAYS" ] && echo "  ${age}d  $f:$ln  ($kind $dt)"
          done)
  if [ -n "$stale" ] && [ "$MAX_LIST" -gt 5 ]; then
    n=$(printf '%s\n' "$stale" | wc -l | tr -d ' ')
    echo "aios-check: $n external-claim tag(s) older than ${TTL_DAYS}d — wiki-lint check 2, re-verify against the source (never trust a recorded SHA):"
    printf '%s\n' "$stale" | sort -rn | head -"$MAX_LIST"
  fi
fi

# --- wiki-lint checks 3+4: Knowledge Map coverage both ways ------------------
# Same `parent:` exemption as check 1: a shard or draft hanging off a hub is
# covered by the hub's map entry and does not earn a line of its own.
kmmissing=$(for f in $SCOPE_PROJECTS $SCOPE_NOTES; do
              [ -f "$f" ] || continue
              # `_`-prefixed files are hub/index notes (_Work.md, _Projects.md): they
              # index other notes rather than being wiki notes, and they carry no
              # `parent:` of their own, so the exemption below cannot reach them.
              case "$(basename "$f")" in (_*) continue ;; esac
              head -30 "$f" | grep -q '^parent:' && continue
              grep -qF "$(basename "$f" .md)" "$KM" || echo "$f"
            done)
if [ -n "$kmmissing" ]; then
  n=$(printf '%s\n' "$kmmissing" | wc -l | tr -d ' ')
  fail "aios-check: $n note(s) absent from Knowledge Map — wiki-lint checks 3-4:"
  printf '%s\n' "$kmmissing" | head -"$MAX_LIST" | sed 's/^/  /'
fi

kmdead=$(grep -ohE '→ [A-Za-z][A-Za-z0-9_./+-]*\.md' "$KM" 2>/dev/null | sed 's/^→ //' | sort -u \
         | while read -r p; do [ -e "$p" ] || echo "$p"; done)
if [ -n "$kmdead" ]; then
  n=$(printf '%s\n' "$kmdead" | wc -l | tr -d ' ')
  fail "aios-check: $n Knowledge Map entr(ies) point at a missing file — wiki-lint check 4:"
  printf '%s\n' "$kmdead" | head -"$MAX_LIST" | sed 's/^/  /'
fi

# --- wiki-lint: a hand-written count in an always-loaded file has no gate ---------
# "N section notes" drifted from 13 to 19 over two days — the shards were added to the
# hub index and to the map's narrative, and nobody re-counted the number in the same
# sentence. Any claim of the form "<N> section notes" is checkable against the dir it
# names, so it is checked here rather than trusted.
countclaims=$(grep -rhoE '[0-9]+ (section|shard) notes? under `[A-Za-z0-9_./+-]+/`' \
                "$KM" $SCOPE_PROJECTS 2>/dev/null | sort -u)
if [ -n "$countclaims" ]; then
  bad=$(printf '%s\n' "$countclaims" | while read -r claim; do
          want=${claim%% *}
          dir=$(printf '%s' "$claim" | sed 's/.*`\(.*\)`/\1/')
          [ -d "$dir" ] || continue
          # A rotated provenance archive is not a section note, and one more
          # appears every month — counting them would make this claim drift by
          # construction, for a reason that has nothing to do with shards.
          have=$(find "$dir" -maxdepth 1 -name '*.md' \
                 | grep -vE 'source-history-[0-9]{4}-[0-9]{2}\.md$' | wc -l | tr -d ' ')
          [ "$want" = "$have" ] || echo "  claims $want, dir holds $have: $dir"
        done)
  if [ -n "$bad" ]; then
    fail "aios-check: a written shard/section count disagrees with its directory:"
    printf '%s\n' "$bad" | head -"$MAX_LIST"
  fi
fi

# --- work-layer identifier convention, swept rather than only enforced on write ---
# vault-write-guard.sh blocks a raw PR number at write time, so NEW text has held the
# line since; nothing ever checked the text already on disk, which is how legacy lines
# came to violate a rule new content cannot. Reported, never auto-fixed — the ponytail
# amendment says pre-existing mess is not the writer's to delete unasked.
# `EC-####` is the one accepted identifier and is exempt by construction (the pattern
# requires a bare `#`); a letter-bearing hex colour (`#1a2b3c`, `#0f0`) and `#` inside
# code fences are the known false positives. An all-numeric hex (`#003366`) is NOT a
# false positive here — it is indistinguishable from an issue reference and is flagged
# on purpose, same as the write-time guard. This reports rather than blocks.
legacy=$(grep -rnE '(^|[^A-Za-z0-9])#[0-9]+([^0-9A-Za-z]|$)' work/ 2>/dev/null \
         | grep -v '^work/sources/' | cut -d: -f1,2)
# Informational, and deliberately NOT a failure: 107 pre-existing hits would turn a
# clean exit red every session forever, which is the nag-channel failure mode that
# open-flags Mode B was just split out to avoid. A standing backlog is not drift. The
# write guard stops it growing; this line keeps its size visible until it is swept.
# Verbose-only. The header promises "prints ONLY failures (quiet when clean)" and
# [[Skill Map]] repeats it; an unconditional line about a known non-problem broke
# that contract and landed in every session's context — the nag channel this block
# was written to avoid.
if [ -n "$legacy" ] && [ "$MAX_LIST" -gt 5 ]; then
  n=$(printf '%s\n' "$legacy" | wc -l | tr -d ' ')
  echo "aios-check: $n legacy raw PR/issue number(s) in work/ notes — pre-existing, not drift (bare EC-#### is the convention; new ones are blocked at write time):"
  printf '%s\n' "$legacy" | sed 's/^/  /'
fi

# --- the after-action register's own backlog --------------------------------------
# The loop's detection half is autonomous (57 rows in 9 days, never a gap); its
# application half has never once run without a human asking. `applied` sat frozen at
# 14 from 08-04 to 08-07 while `open` climbed to 35, and every repeat-instance row in
# the register recurred while its own fix sat open — recurrence is a symptom of
# non-application, not of bad fixes. km-rotate, log-rollup and open-flags Mode B each
# got a detection line here and each started draining; the register had none. Same
# shape as the log-rollup row: "rotation is defined but fires only when a human types
# it." Informational, like the flag register — a backlog is not drift.
REG="AIOS/History/audits/after-action.md"
if [ -f "$REG" ]; then
  regopen=$(grep -c '| open |' "$REG" 2>/dev/null || echo 0)
  if [ "${regopen:-0}" -gt 8 ] 2>/dev/null; then
    oldest=$(grep '| open |' "$REG" | sed -n 's/^| \(2026-[0-9-]*\).*/\1/p' | sort | head -1)
    echo "aios-check: after-action register has $regopen open rows (oldest $oldest) — nothing closes them but a deliberate pass. Open $REG, or list them with: grep -n '| open |' $REG"
  fi
fi

# --- a public repo must carry no scope tokens -------------------------------------
# A second repo you push publicly — a dotfiles repo carrying the scope-neutral
# half of your agent setup, a template, a blog — is where a scope token does the
# most damage, because it is the one place a leak leaves the machine. Point
# AIOS_PUBLIC_REPO at it and this gate scans it on every run.
#
# THE TOKENS ARE NOT WRITTEN HERE. They are read at run time from your own
# AIOS/Systems/layers.tsv, which is exactly right for a check that ships inside a
# public template: a hardcoded list would publish the very strings it searches
# for. Scopes whose token column is "-" have the wall off and contribute nothing.
#
# Tracked files only (git grep) — a scratch file never leaves the machine.
PUB="${AIOS_PUBLIC_REPO:-}"
if [ -n "$PUB" ] && git -C "$PUB" rev-parse --git-dir >/dev/null 2>&1; then
  # Column 4 of every scope that declares tokens, joined. An empty result must
  # add nothing: a bare trailing "|" matches every line, which is worse than the
  # gate it is meant to tighten.
  pub_pattern=$(awk -F'\t' '/^[[:space:]]*#/ {next} NF >= 4 && $4 != "" && $4 != "-" {print $4}' \
                  "AIOS/Systems/layers.tsv" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
  # Column-1 repo names of every scoped row in the wire manifest, regex-escaped.
  # A repo name IS a scope token — it names the project as surely as its brand
  # does — and this is the one list here that grows without a code change.
  pub_repo_names=$(awk -F'\t' '/^[[:space:]]*#/ {next} NF >= 3 && $1 != "" {print $1}' \
                      "AIOS/Systems/repo-layers.tsv" 2>/dev/null \
                    | sed -e 's/[.[\*^$()+?{}|]/\\&/g' | tr '\n' '|' | sed 's/|$//')
  [ -n "$pub_repo_names" ] && pub_pattern="${pub_pattern:+$pub_pattern|}$pub_repo_names"

  if [ -z "$pub_pattern" ]; then
    # Silence here is correct, not a disabled gate: no scope declares tokens, so
    # the wall is off everywhere and there is nothing to leak.
    :
  else
    # WORKING TREE AND HEAD, both. A leak once committed and then only edited out
    # of the working tree (never committed as a removal) still ships in every
    # clone and in `git log -p` — scanning the checkout alone would call that
    # clean. A hit on EITHER fails.
    pub_wt_hits=$(git -C "$PUB" grep -IliE "$pub_pattern" 2>/dev/null); pub_wt_rc=$?
    pub_head_hits=""; pub_head_rc=1
    if git -C "$PUB" rev-parse --verify -q HEAD >/dev/null 2>&1; then
      pub_head_hits=$(git -C "$PUB" grep -IliE "$pub_pattern" HEAD 2>/dev/null); pub_head_rc=$?
    fi
    case "$pub_wt_rc:$pub_head_rc" in
      0:*|*:0)
        fail "aios-check: PUBLIC repo ($PUB) tracks file(s) naming a walled scope — scrub before any push, and rewrite history if already pushed:"
        # Print each list only when it has entries: an empty HEAD list piped
        # through sed would otherwise emit a lone "[HEAD] " line.
        { [ -n "$pub_wt_hits" ] && printf '%s\n' "$pub_wt_hits"
          [ -n "$pub_head_hits" ] && printf '%s\n' "$pub_head_hits" | sed 's/^/[HEAD] /'; } \
          | head -"$MAX_LIST" | sed 's/^/  /' ;;
      1:1) : ;;   # git grep found nothing in either place — clean, stay silent
      *) fail "aios-check: PUBLIC repo ($PUB) gate could not run (git grep exit $pub_wt_rc, HEAD exit $pub_head_rc)" ;;
    esac
  fi
fi

# --- every shell script in the OS parses ------------------------------------------
# A syntax error in vault-write-guard.sh makes PreToolUse fail, and a failing
# PreToolUse blocks Edit, Write AND Bash — so the guard bricks the vault including its
# own repair, and recovery needs a human at a shell. That happened on 2026-08-08 from
# two apostrophes inside its sh single-quoted perl block. Failing closed stays correct;
# this catches an unparseable script at SessionStart instead of at the next write.
badsyntax=$(for s in .claude/hooks/*.sh AIOS/Systems/*.sh AIOS/Systems/hooks/*.sh; do
              [ -f "$s" ] || continue
              sh -n "$s" 2>/dev/null || echo "  $s"
            done)
if [ -n "$badsyntax" ]; then
  fail "aios-check: shell script(s) do NOT parse — if one is a hook, it is blocking every write right now:"
  printf '%s\n' "$badsyntax"
fi

# --- the write guard's own regression gate ----------------------------------------
# The parse sweep above was the answer to 2026-08-08, when an unparseable guard made
# PreToolUse fail and so blocked Edit, Write AND Bash — bricking the vault including
# its own repair. But parse-clean is not the dangerous failure. A guard that PARSES
# and has stopped BLOCKING fails OPEN, silently, and its 17-case suite was invoked by
# nothing at all: Rule D — the most recurring gate finding in the vault's history —
# had no assertion anywhere.
# Running the suite every session costs 1.8s measured, on a hook that already fought
# its way down from 6.5s, so it is gated on the guard's own checksum. Read-and-
# compare only: this file edits nothing (see the header), so re-stamping is a
# deliberate human act — the same shape Rule E gives the @import doctrine files.
# Gated on EITHER file existing, not just the guard: a guard deleted outright while
# its tracked stamp survives is the identical fail-open shape as one that silently
# stopped blocking. Both paths below are tracked in this repo (git ls-files), so
# neither can be legitimately absent from a checkout — unlike a per-machine
# LaunchAgents plist twin, which genuinely can be.
#
# TWO FILES, NOT ONE, since 2026-08-09. The Rules C/D literals were factored out of
# the guard into AIOS/Systems/hooks/rules-lib.sh, which moved security-relevant
# content OUT from under the gate that stamps it: editing a brand token there —
# the exact edit the wall depends on — no longer tripped this check, while the
# identical edit inside the guard still did. The refactor was right; leaving the
# stamp on one half was not. Hashes are compared in a fixed order (guard first),
# path-independently, so the remediation command can spell the paths however it
# likes and a missing library shows up as a mismatch rather than a skip.
GUARD=".claude/hooks/vault-write-guard.sh"
GUARD_LIB="AIOS/Systems/hooks/rules-lib.sh"
GUARD_SHA="AIOS/Systems/guard.sha"
# `shasum` is a perl script, and Arch ships it in /usr/bin/core_perl -- NOT on the
# hardened PATH the scheduled hooks set, and not somewhere `command -v` finds it
# under a stripped environment. sha1sum (GNU coreutils, /usr/bin) emits the same
# SHA-1 in the same "hash  path" format, so either tool validates either stamp.
# Resolve ONCE and name the tool in the remediation command, or the operator is
# told to run something their machine does not have.
GUARD_SHA_TOOL=$(command -v shasum 2>/dev/null || command -v sha1sum 2>/dev/null)
GUARD_STAMP="sh $PWD/.claude/hooks/test_vault_write_guard.sh && ${GUARD_SHA_TOOL:-shasum} $PWD/$GUARD $PWD/$GUARD_LIB > $PWD/$GUARD_SHA"
if [ -f "$GUARD" ] || [ -f "$GUARD_LIB" ] || [ -f "$GUARD_SHA" ]; then
  if [ ! -f "$GUARD_SHA" ]; then
    # A missing stamp must FAIL, not skip: a check that silently disables itself when
    # its own input disappears is the fail-open shape this section exists to catch.
    fail "aios-check: $GUARD has no verification stamp — the guard regression gate is disabled. Verify and stamp it:
  $GUARD_STAMP"
  else
    want=$(cut -d' ' -f1 < "$GUARD_SHA")
    # No hashing tool at all is its OWN failure, reported as itself. Without this
    # branch `have` came back empty and the mismatch arm fired, telling the
    # operator the guard had CHANGED -- sending them to diff a file that is
    # byte-identical, when the real fault is a missing binary on the PATH.
    if [ -z "$GUARD_SHA_TOOL" ]; then
      fail "aios-check: neither shasum nor sha1sum is on PATH, so the guard verification stamp cannot be checked at all. On Arch shasum lives in /usr/bin/core_perl (perl-Digest-SHA); sha1sum is coreutils. This check fails rather than skips: an unverifiable guard is the fail-open case it exists to catch."
      have=""
    else
      have=$("$GUARD_SHA_TOOL" "$GUARD" "$GUARD_LIB" 2>/dev/null | cut -d' ' -f1)
    fi
    if [ -n "$GUARD_SHA_TOOL" ] && [ "$want" != "$have" ]; then
      fail "aios-check: $GUARD or $GUARD_LIB changed since it was last verified — a guard that parses but has stopped blocking fails OPEN, and the rule patterns it enforces live in the library. Re-verify and re-stamp BOTH:
  $GUARD_STAMP"
    fi
  fi
fi

# --- digest wire parity: the manifest says wired, the repo must agree -------------
# repo-layers.tsv registers a project as digest-wired and nothing ever checked that
# the wire exists. ember_pack was registered, carried Knowledge Map entries and a
# project config, and had never been digested once — no settings*.json at all — and
# the digest hook's fail-closed design makes a missing wire silent by construction.
# A manifest row and a repo that disagree is drift, not a backlog: both fixes are
# one bounded act (write the hook, or drop the row), so this fails rather than nags.
MANIFEST="AIOS/Systems/repo-layers.tsv"
if [ -f "$MANIFEST" ]; then
  TAB=$(printf '\t')
  unwired=""
  localonlybad=""
  stalematch=""
  wiredead=""
  while IFS="$TAB" read -r repo layer _slug repo_path flags; do
    case "$repo" in ''|\#*) continue ;; esac
    flags="${flags:-}"   # column 5 is optional; a 3- or 4-field row leaves it empty
    # column 4 is the recorded path; a row not yet migrated (3 fields) falls
    # back to the old assumption this column exists to retire.
    dir="${repo_path:-$HOME/code/$repo}"
    # Column 4 is stored `~/code/...` (portable across the two machines). The
    # tilde is data here, not syntax, so it must be expanded or every row looks
    # like an uncloned repo and this whole check silently passes. Mirrors
    # aios_expand_home() in hooks/lib.sh, which this file does not source.
    case "$dir" in "~/"*) dir="$HOME/${dir#\~/}" ;; esac
    # A missing repo dir is not an error — another machine, or simply not cloned
    # here. Same ruling as a plist with no installed twin, below.
    [ -d "$dir" ] || continue
    hits=$(grep -l 'aios-digest' "$dir"/.claude/settings*.json 2>/dev/null)
    if [ -z "$hits" ]; then
      unwired="$unwired  $repo ($layer) — no settings*.json references aios-digest
"
    elif [ -z "$(printf '%s\n' "$hits" | grep -v 'settings\.local\.json$')" ]; then
      # DELIBERATE vs ACCIDENTAL, and the manifest is the only thing that knows.
      # An untracked-only wire works here and nowhere else — which is a defect in a
      # repo that simply never got its wire committed, and a REQUIREMENT in one where
      # nothing about the wire may be committed at all. A local-only repo is the second
      # kind: the employer-repo wiring is deliberately local-only (`CLAUDE.local.md` +
      # `.claude/settings.local.json`, both gitignored) and a first pass that committed
      # it to a branch was reverted for exactly that reason ([[Log]] 2026-08-13).
      # Before column 5 existed the two shared one echo line, so the channel could only
      # ever report a permanent non-problem and the accidental case had nowhere to be
      # loud. Flagged rows drop out; unflagged ones now FAIL rather than nag, because
      # an uncommitted wire is one bounded act from fixed — the same ruling the
      # unwired case above earned.
      case ",$flags," in
        *,local-only,*) : ;;
        *) localonlybad="$localonlybad  $repo ($layer) — only settings.local.json, which is untracked; commit the wire, or mark the row \`local-only\` in $MANIFEST if it must never be committed there
" ;;
      esac
    fi
    # A SessionStart matcher that omits compact loses the context wire the moment a
    # long session compacts — and loses it invisibly, because the CLAUDE.md @imports
    # (effort-table, reasoning-doctrine, ponytail-amendment) DO survive. The rules
    # stay, the facts vanish, and the session reads as fully wired. Same failure on
    # /clear. "startup" appears in no other hook event's matcher, so anchoring on it
    # is precise without parsing JSON. Source enum, read from the Claude Code 2.1.226
    # payload schema: startup, resume, clear, compact, fork. fork is correctly absent
    # from the required set — a fork inherits its parent's context.
    # --- WIRE LIVENESS: wired is not the same as firing ------------------------
    # The checks above ask whether the hook EXISTS. This asks whether it RAN. A hook
    # present in a config its harness reads, that has silently stopped firing, passes
    # every one of them — and the fail-closed design makes a dead digest look exactly
    # like a quiet week.
    #
    # AGE, NOT ABSENCE, and that distinction is the whole design (register row 105
    # correcting row 102). A digest arrives at the NEXT session end, so a commit made
    # minutes ago legitimately has no digest yet; alerting on mere absence fires on
    # every ordinary session that ends after a commit, and a probe that cries wolf is
    # one that gets unwired. The question is not "did the hook never fire" but "has it
    # been late for longer than lateness explains".
    #
    # A DORMANT REPO IS SILENT BY CONSTRUCTION, which is what keeps this from becoming
    # a standing backlog: its tip was digested whenever it was last worked, so the tip
    # matches and nothing prints. Only a repo that MOVED and was never digested ages in.
    #
    # PREFIX MATCH, not equality: digest blocks record an abbreviated `HEAD:` and the
    # abbreviation length varies between blocks (9 and 7 chars both occur today), so
    # comparing full shas would report every repo as undigested — silently, and
    # permanently, which is the failure mode this file calls worse than over-reporting.
    tip=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    if [ -n "$tip" ]; then
      seen=0
      for d in $(grep -hoE 'HEAD: *[0-9a-f]{4,}' \
                   "$VAULT/+/_sessions/$layer/$_slug.md" \
                   "$VAULT/AIOS/History/_ingested/$layer/$_slug"-*.md 2>/dev/null \
                 | sed 's/HEAD: *//'); do
        case "$tip" in "$d"*) seen=1; break ;; esac
      done
      if [ "$seen" -eq 0 ]; then
        tipts=$(git -C "$dir" log -1 --format=%ct HEAD 2>/dev/null)
        if [ -n "$tipts" ]; then
          age=$(( ( $(date +%s) - tipts ) / 86400 ))
          if [ "$age" -ge "$WIRE_STALE_DAYS" ]; then
            wiredead="$wiredead  $repo ($layer) — tip $(git -C "$dir" rev-parse --short HEAD 2>/dev/null) is ${age}d old and appears in no digest
"
          fi
        fi
      fi
    fi

    stale=$(grep -hE '"matcher"[[:space:]]*:[[:space:]]*"startup[^"]*"' \
      "$dir"/.claude/settings*.json 2>/dev/null | grep -v compact)
    if [ -n "$stale" ]; then
      stalematch="$stalematch  $repo ($layer) — $(printf '%s' "$stale" | sed 's/^[[:space:]]*//' | head -1)
"
    fi
  done < "$MANIFEST"
  if [ -n "$unwired" ]; then
    n=$(printf '%s' "$unwired" | grep -c .)
    fail "aios-check: $n manifest-declared repo(s) have no digest hook — they will never be digested, and the fail-closed design means nothing else reports it:"
    printf '%s' "$unwired" | head -"$MAX_LIST"
  fi
  # fail, not echo: the wire is not merely unreproducible elsewhere, it is broken
  # here for the rest of every compacted session. One bounded fix — widen the
  # matcher to "startup|resume|clear|compact" — so this is drift, not a backlog.
  if [ -n "$stalematch" ]; then
    n=$(printf '%s' "$stalematch" | grep -c .)
    fail "aios-check: $n repo(s) wire SessionStart on a matcher that omits compact — the vault context silently stops re-firing after a compaction or /clear, while the @imported rules stay put. Widen to \"startup|resume|clear|compact\":"
    printf '%s' "$stalematch" | head -"$MAX_LIST"
  fi
  # fail, not echo — CHANGED 2026-08-16, and the reasoning it replaces is worth keeping.
  # This was echo + verbose-only, on the ruling that "the wire WORKS, it is simply not
  # reproducible on another machine" and that turning a session red over a working hook
  # is the nag channel this file avoids. That ruling was right about the case it had:
  # a repo whose local-only wiring is deliberate and permanent. It was wrong as
  # a policy, because it made one channel carry two opposite meanings — a repo that must
  # never commit its wire, and a repo that simply has not — and the second is one bounded
  # act from fixed. With the deliberate case now named in the manifest (column 5
  # `local-only`), everything reaching here is the accidental kind, so it fails like the
  # unwired case above rather than nagging in verbose forever. The nag-channel ruling
  # survives intact; it just moved to the manifest, which is where the distinction lives.
  # echo, not fail: a dead wire is not vault DRIFT — the vault is internally
  # consistent, it is the world outside that moved without telling it — and the fix
  # may be in a harness this check cannot see. Default-visible rather than
  # verbose-gated, for the same reason as the km-rotate band: the runs this protects
  # are unattended, and an unattended run never passes --verbose. Self-clearing by
  # construction — one digest silences it — so it is not the permanent-backlog shape
  # the verbose-only ruling was written for.
  # TRIPWIRE: if this ever holds several repos at once, it is reporting "you have not
  # opened a session in these repos lately" rather than a broken hook, and the
  # threshold or the signal is wrong.
  if [ -n "$wiredead" ]; then
    n=$(printf '%s' "$wiredead" | grep -c .)
    echo "aios-check: $n repo(s) wired for digests but silent — a tip that moved and was never digested, older than ${WIRE_STALE_DAYS}d. Wired is not firing; check the harness that ran there:"
    printf '%s' "$wiredead" | head -"$MAX_LIST"
  fi
  if [ -n "$localonlybad" ]; then
    n=$(printf '%s' "$localonlybad" | grep -c .)
    fail "aios-check: $n digest wire(s) present but untracked — they work on this machine and nowhere else:"
    printf '%s' "$localonlybad" | head -"$MAX_LIST"
  fi
fi

# --- scheduler ownership: exactly ONE machine may run the timers ------------------
# Two hosts firing /aios-ingest at 08:00 against one vault double-drain
# +/_sessions/ and race the push, and .aios-ingest.lock is a per-machine mkdir
# lock that cannot see across machines. The dangerous window is the HANDOFF --
# install on the new box, forget to unload the old one, and both fire tomorrow
# morning with nothing reporting it until the queue is already corrupted.
#
# uname -s and uname -n are overridable ONLY so this is testable in both
# directions on one machine; a suite that can exercise just the host it runs on
# would leave the non-owner-with-timers case -- the entire reason for the check --
# permanently unasserted.
SCHED_FILE="AIOS/Systems/scheduler-host"
SCHED_OS="${AIOS_UNAME_S:-$(uname -s)}"
SCHED_THIS="${AIOS_HOSTNAME:-$(uname -n | cut -d. -f1)}"
# First non-comment, non-blank line, whitespace stripped.
SCHED_OWNER=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$SCHED_FILE" 2>/dev/null \
              | grep -v '^$' | head -1)

# "Installed" means the unit files this host's scheduler actually reads are
# present. File presence, not `launchctl list`/`systemctl --user list-timers`:
# the same choice the plist-twin check below makes, and the only one a fixture
# can exercise. Hoisted ABOVE the marker test because whether a missing marker
# is an error depends on it.
sched_installed=no
if [ "$SCHED_OS" = Darwin ]; then
  for u in AIOS/Systems/hooks/*.plist; do
    [ -f "$u" ] || continue
    [ -f "$HOME/Library/LaunchAgents/$(basename "$u")" ] && sched_installed=yes
  done
else
  for u in AIOS/Systems/hooks/*.timer; do
    [ -f "$u" ] || continue
    [ -f "$HOME/.config/systemd/user/$(basename "$u")" ] && sched_installed=yes
  done
fi

# NOTHING RUNNING HERE = NOTHING TO OWN. A clone with no timers installed on this
# machine cannot be half of a double-fire, so an undeclared owner costs nothing
# yet. Staying silent here is NOT the fail-open shape the next branch argues
# against: that one is the owner being UNKNOWN while timers are LIVE. Nagging a
# fresh clone for a marker it has no use for is how a check gets unwired, taking
# the double-fire case with it.
if [ "$sched_installed" = no ] && { [ ! -f "$SCHED_FILE" ] || [ -z "$SCHED_OWNER" ]; }; then
  :
elif [ ! -f "$SCHED_FILE" ] || [ -z "$SCHED_OWNER" ]; then
  # Timers ARE installed here and nothing says who owns them. A missing marker
  # must FAIL, not skip: every case below is decided by comparing against it, so
  # an absent owner silently makes the double-ingest case unreachable — the same
  # fail-open shape as a missing guard.sha, with a worse blast radius.
  fail "aios-check: $SCHED_FILE is missing or has no hostname, but this host HAS AIOS timers installed — scheduler ownership is undeclared, so the two-machines-both-firing case cannot be detected at all. Write the owning host into it: uname -n | cut -d. -f1"
else
  if [ "$SCHED_THIS" = "$SCHED_OWNER" ]; then
    if [ "$sched_installed" = no ]; then
      fail "aios-check: this host ($SCHED_THIS) is the declared scheduler owner in $SCHED_FILE but has no timers installed — nothing is running the ingest or the register. Install them (see the port plan, Task 2.4), or hand ownership to the machine that is."
    fi
  elif [ "$sched_installed" = yes ]; then
    # THE CASE THE FILE EXISTS FOR. Hard fail, never a warning: by the time a
    # human notices a double-drained queue the damage is already committed.
    fail "aios-check: DOUBLE-SCHEDULER — this host ($SCHED_THIS) is NOT the declared owner ($SCHED_OWNER in $SCHED_FILE) yet has AIOS timers installed. Two machines firing /aios-ingest at one vault double-drain +/_sessions/ and race the push, and .aios-ingest.lock cannot see across machines. Unload them here, or make this host the owner — never both."
  fi
fi

# --- the vault's launchd copy of record vs what is actually installed -------------
# The vault plist said 03/07/11 while ~/Library/LaunchAgents ran 08/12/16 — a full day
# of schedule drift, invisible because the vault copy is never compared to the twin
# that actually fires. Only flags a real divergence; a missing twin is not an error
# (another machine, or the agent simply not installed here).
#
# GATED ON OWNER AND DARWIN since 2026-09-05. Once the Mac deliberately unloads its
# agents it is not the owner, and reporting permanent drift for a plist it removed
# on purpose trains you to ignore the one check that catches a real handoff error.
# Linux never has a LaunchAgents dir at all, so the loop was already a no-op there.
if [ "$SCHED_OS" = Darwin ] && [ "$SCHED_THIS" = "$SCHED_OWNER" ]; then
for plist in AIOS/Systems/hooks/*.plist; do
  [ -f "$plist" ] || continue
  twin="$HOME/Library/LaunchAgents/$(basename "$plist")"
  [ -f "$twin" ] || continue
  # COMPARE THE SUBSTITUTED FORM. The tracked plist carries __AIOS_VAULT__ and
  # __HOME__ placeholders (aios-scheduler.sh expands them on install), so a raw
  # cmp would report drift on every machine, every run — and a check that always
  # fails is a check nobody reads, which costs the real handoff error it exists
  # to catch. Same substitution as the installer, kept beside it on purpose.
  rendered=$(sed -e "s|__AIOS_VAULT__|$VAULT|g" -e "s|__HOME__|$HOME|g" "$plist")
  if [ "$rendered" != "$(cat "$twin")" ]; then
    fail "aios-check: $(basename "$plist") differs from the installed ~/Library/LaunchAgents copy — the vault copy of record is not what fires:"
    printf '%s\n' "$rendered" | diff - "$twin" 2>/dev/null | head -6 | sed 's/^/  /'
  fi
done
fi

# --- the harness actually in use must be wired to the guard ----------------------
# EVERY check above this line, and every rule the guard enforces, reached the
# session through .claude/settings.json — a file only Claude Code reads. jcode is
# the harness in daily use here and has its own global hook table in
# ~/.jcode/config.toml. On 2026-08-11 that table wired session_end (the digest)
# and nothing else, so under jcode:
#   - the write guard never ran. sources/ immutability, the personal-notes rule,
#     the cross-layer leak tripwire, the work-note conventions and the
#     orchestrator-only shared files were all unenforced, silently.
#   - this very file never ran. The SessionStart health checks — queue depth,
#     scheduled-ingest failure, km-rotate/log-rollup thresholds — reported nothing.
# Both halves looked completely healthy the whole time: the tests passed, guard.sha
# verified, and the wall existed only as prose in CLAUDE.md.
#
# `pre_tool_timeout_ms` was present WITHOUT `pre_tool`, which is the shape that
# makes this worth a mechanical check rather than a memory — the section reads as
# configured at a glance and enforces nothing.
#
# fail, not echo: an unenforced identity wall is the most expensive silent state
# in this vault, and the fix is one bounded edit to one file.
#
# AIOS_JCODE_CONFIG exists so the self-check can point this at a fixture. $HOME
# is not usable as the override here — line 25 already resolves the vault from
# $HOME, so moving it relocates the vault out from under the whole script and
# every check above this one silently stops running.
JCODE_CFG="${AIOS_JCODE_CONFIG:-$HOME/.jcode/config.toml}"
if [ -f "$JCODE_CFG" ]; then
  missing=""
  # Values are compared by BASENAME, so a path written with ~, $HOME or in full
  # all satisfy it. The point is that the hook is wired to the vault's script,
  # not which spelling of the vault's path the user prefers.
  check_jcode_hook() { # $1=hook key  $2=expected script basename
    line=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$JCODE_CFG" 2>/dev/null | head -1)
    case "$line" in
      *"$2"*) return 0 ;;
      "")     missing="$missing  $1 — not set; expected the vault's $2
" ;;
      *)      missing="$missing  $1 — set, but not to $2: $(printf '%s' "$line" | sed 's/^[[:space:]]*//')
" ;;
    esac
  }
  check_jcode_hook pre_tool      vault-write-guard.sh
  check_jcode_hook session_start aios-session-status.sh
  check_jcode_hook session_end   aios-digest.sh
  if [ -n "$missing" ]; then
    n=$(printf '%s' "$missing" | grep -c .)
    fail "aios-check: $n jcode hook(s) not wired to the vault in ~/.jcode/config.toml — under jcode the affected rules do not run AT ALL, and nothing else reports it (the Claude Code wiring in .claude/settings.json is a different file jcode never reads). Fix: sh AIOS/Systems/aios-install.sh --apply (dry-run by default; backs up the config first):"
    printf '%s' "$missing" | head -"$MAX_LIST"
  fi
fi

# --- no layer-merged graph artifact may be TRACKED -------------------------------
# graphify writes its whole-vault outputs to graphify-out/'s root BEFORE
# split_layers.py partitions them, so every root artifact mixes all three
# identity layers in one file. Two of them were committed on every rebuild for
# months: GRAPH_REPORT.md (hits from one scope's brand sitting beside another's
# nodes) and manifest.json (an index of all three layers' paths). Meanwhile
# [[Knowledge Map]] described these graphs as "one per identity layer (never
# merged — that would violate the layer wall)" and the skill called never merging
# "the one thing this skill exists to prevent". The per-layer splits obeyed; the
# root files were simply never looked at.
#
# .gitignore now covers them, but an ignore does not un-track a file — `git add -f`,
# a rebase, or a future rename lands them again silently. This asserts the property
# the wall actually needs (nothing merged is IN the repo) rather than trusting the
# ignore list to be complete.
#
# Checks tracked-ness only. These files existing on disk is normal and expected:
# they are the tool's own local byproducts and the skill tells you to regenerate them.
#
# .graphify_labels.json is in the list because the ROOT copy held whole-vault
# community labels — one scope's epics beside another scope's content ideas —
# and was tracked despite already matching the graphify-out/.graphify_* ignore
# rule. An ignore pattern does nothing to a file git is already tracking, which is
# the exact reason this check tests the index rather than the ignore list. The
# PER-LAYER copies at graphify-out/<layer>/.graphify_labels.json are the ones the
# skill documents and stay tracked.
merged=$(git ls-files graphify-out/GRAPH_REPORT.md graphify-out/manifest.json \
                      graphify-out/graph.json graphify-out/.graphify_labels.json 2>/dev/null)
if [ -n "$merged" ]; then
  n=$(printf '%s\n' "$merged" | grep -c .)
  fail "aios-check: $n whole-vault graphify artifact(s) are TRACKED — these are pre-split, so each mixes every identity layer in one committed file (the wall the per-layer graphs exist to keep). Untrack with: git rm --cached <path>"
  printf '%s\n' "$merged" | sed 's/^/  /' | head -"$MAX_LIST"
fi

# --- project shards that have outgrown a single read -----------------------------
# The Knowledge Map has km-rotate and a 1500-byte gate; the Log has log-rollup and a
# 100KB gate (this same number, deliberately). PROJECT SHARDS — the files an ingest
# actually reads and rewrites
# every run — had neither, and they only ever grow. domain-tenancy.md went
# 145KB -> 193KB in six days, monotonically, never once shrinking, and at 264 lines
# it averages 730 bytes per line with a single line of 8371. The rotation machinery
# already exists (provenance-rotate.py, --extract, the _history/ convention); what
# was missing is anything that SAYS a shard has reached the point of needing it.
#
# ECHO, NOT FAIL, and verbose-only — the same ruling the legacy PR-number scan
# earned above it. Six files are already over the line, so failing would paint every
# session red over a standing backlog, which is precisely the nag channel open-flags
# Mode B was split out to prevent. Rotation is also a JUDGMENT act (which sections
# are settled history vs live standing state), so this can only ever point.
#
# ARCHIVES ARE EXEMPT BY NAME, not by size. `<name>-YYYY-MM.md` and anything under
# `_history/` ARE the rotation destination — flagging them would tell you to rotate
# the thing you rotated into, forever.
#
# `find`, NOT `git ls-files`. The size that matters is the size an ingest reads off
# disk, which has nothing to do with whether git has indexed the file yet. This
# vault has already been bitten by a git-blind check: the write observer diffs
# `git status` and is structurally blind to gitignored paths, documented as a hole
# in vault-write-guard's Rule F notes. No reason to build a second one.
SHARD_MAX=${SHARD_MAX:-100000}
if [ "$MAX_LIST" -gt 5 ]; then
  big=$(find $SCOPE_PROJECT_DIRS -name '*.md' -type f 2>/dev/null \
        | grep -vE -- '-[0-9]{4}-[0-9]{2}\.md$|/_history/' \
        | while read -r f; do
            sz=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
            [ -n "$sz" ] && [ "$sz" -gt "$SHARD_MAX" ] && printf '%s\t%s\n' "$sz" "$f"
            continue
          done | sort -rn)
  if [ -n "$big" ]; then
    n=$(printf '%s\n' "$big" | grep -c .)
    echo "aios-check: $n project shard(s) over $((SHARD_MAX / 1000))KB — an ingest reads these whole, every run. Rotate settled history out with: python3 AIOS/Systems/provenance-rotate.py <shard> --extract '## <heading>' <dest.md> (dry-run by default):"
    printf '%s\n' "$big" | head -"$MAX_LIST" | awk -F'\t' '{ printf "  %6.0fKB  %s\n", $1/1000, $2 }'
  fi
fi

# ── jcode compute-routing mirrors (added 2026-08-12) ─────────────────────────
#
# WHY THIS CHECK EXISTS. `effort-table.md` reaches every Claude Code session by
# @import from ~/.claude/CLAUDE.md. jcode reads NEITHER that file NOR @import
# directives, so the tiers must be restated inline in two jcode-owned files:
#
#   ~/.jcode/prompt-overlay.md   general compute routing, every jcode session
#   ~/.jcode/swarm-prompt.md     swarm spawn routing (OVERRIDES jcode's built-in
#                                default, which ships Fable 5 — our xhigh
#                                escalation row — as the DEFAULT worker model)
#
# Those are MANUAL MIRRORS of a file that changes. A mirror nobody checks is a
# mirror that silently goes stale, and stale here means every jcode agent on the
# machine dispatches at the wrong tier — the failure this whole wiring exists to
# prevent. So: assert each model id in the table appears in each mirror.
#
# Detection only, per this script's contract. It cannot know which side is
# right — if the table moved, update the mirrors; if a mirror was edited by
# hand, reconcile it to the table.
#
# ⚠️ VISIBILITY LIMIT — this check is NOT self-announcing under jcode. Two
# independent reasons, both verified 2026-08-12:
#   1. jcode's `session_start` is an OBSERVER — spawned detached, stdout
#      discarded (jcode docs/HOOKS.md). Nothing this script prints can reach a
#      jcode session, whatever the cwd.
#   2. aios-session-status.sh (the only caller) deliberately exits early outside
#      the vault under jcode, because its normal output mixes all three identity
#      layers and would leak into unrelated repos.
# So under jcode this fires only on a vault session, and even there it is
# invisible. It IS visible under Claude Code's SessionStart in the vault, and on
# any manual `sh AIOS/Systems/aios-check.sh`. Treat it as a janitor-sweep check
# you will see when tending the vault — not as a live guardrail. The live
# guardrail is the mirrors themselves being correct.
ET="AIOS/Systems/effort-table.md"
# GATED ON JCODE BEING PRESENT. These mirrors exist only to carry the table into a
# harness that cannot @import; a machine without that harness has nothing to
# mirror, and demanding two files it will never use is a false positive on every
# run — which trains you to ignore the output, costing the drift this check is
# for. Claude Code reads the table through its own config and needs no mirror.
if [ -f "$ET" ] && [ -d "$HOME/.jcode" ]; then
  # ONLY the tier table's own rows. Scoping to lines starting with `|` matters:
  # the note prose below the table names other model ids (e.g. a prior Opus pin
  # in the changelog), and pulling those in makes the check demand ids the
  # mirrors are correct NOT to carry — a false positive, which is worse than no
  # check because it trains you to ignore the output.
  et_models=$(grep '^|' "$ET" | grep -oE '`claude-[a-z0-9.-]+`' | tr -d '`' | sort -u)
  [ -n "$et_models" ] || et_models=""
  for mirror in "$HOME/.jcode/prompt-overlay.md" "$HOME/.jcode/swarm-prompt.md"; do
    if [ ! -f "$mirror" ]; then
      fail "aios-check: MISSING $mirror — the effort table does not reach jcode sessions without it (jcode ignores ~/.claude/CLAUDE.md and @import). Recreate it as an inline mirror of $ET."
      continue
    fi
    missing=$(for m in $et_models; do
                grep -qF "$m" "$mirror" || echo "  $m"
              done)
    if [ -n "$missing" ]; then
      fail "aios-check: $mirror has drifted from $ET — model id(s) in the table but not the mirror:"
      printf '%s\n' "$missing"
      fail "  Reconcile by hand: jcode prompt files cannot @import, so the tiers are restated there deliberately."
    fi
  done
fi

# ── signing is on but this shell reaches no agent (added 2026-09-06) ─────────
#
# WHY THIS CHECK EXISTS. Every commit protocol in this vault assumes `git commit`
# works. On 2026-09-06 it did not, on a machine where nothing was actually
# broken: the key was decrypted and loaded in a running systemd ssh-agent, and
# the harness's shell simply had no SSH_AUTH_SOCK, so git never found the agent,
# fell back to the key file, and died on `ssh_askpass ... No such file` — with no
# tty to prompt from and no askpass binary to prompt with.
#
# The symptom names the wrong thing, which is the whole reason this is worth a
# check. "ssh-askpass missing" reads as a missing package; installing one would
# have produced a passphrase prompt for a key that never needed unlocking. The
# actual state — agent reachable: no — is one command to ask and is never asked,
# because it only surfaces at the moment a commit is already failing.
#
# Same family as the unwired-guard checks above: the wire exists, it just does
# not reach the harness's shell, and everything looks healthy until the step that
# needs it runs. Fixed for both shells by an export in dotfiles' shared/shellrc;
# this check is what notices the next machine, shell or harness that lacks it.
#
# Scoped deliberately: only when the vault itself is configured to sign with ssh
# (a gpg signer needs no ssh-agent, and an unsigned repo needs no key at all), so
# this stays silent everywhere it would be noise. It reports on the shell it runs
# in — which IS the harness's shell, and therefore the one whose commits fail.
if [ "$(git config --get commit.gpgsign 2>/dev/null)" = "true" ] &&
   [ "$(git config --get gpg.format 2>/dev/null)" = "ssh" ] &&
   command -v ssh-add >/dev/null 2>&1; then
  ssh-add -l >/dev/null 2>&1
  # ssh-add's exit codes separate the two failures, and they have different fixes:
  # 2 = could not talk to an agent at all, 1 = agent answered but holds no key.
  case $? in
    2) fail "aios-check: signing is on (commit.gpgsign + gpg.format=ssh) but this shell reaches NO ssh-agent — SSH_AUTH_SOCK is '${SSH_AUTH_SOCK:-unset}'. Every signed commit from this shell dies on ssh_askpass, even with the key already unlocked in a running agent. systemd's ssh-agent.service does not export the variable; a graphical login gets it elsewhere, an agent-spawned shell does not. Fix: export SSH_AUTH_SOCK=\"\${XDG_RUNTIME_DIR}/ssh-agent.socket\" from the shell rc both shells source (dotfiles' shared/shellrc carries it), then start a new session — a harness snapshots the environment at startup." ;;
    1) fail "aios-check: an ssh-agent is reachable but holds NO identity, and signing is on (commit.gpgsign + gpg.format=ssh) — the next signed commit will fall back to the key file and prompt for a passphrase this shell has no tty to answer. Fix: ssh-add $(git config --get user.signingkey 2>/dev/null | sed 's/\.pub$//') from a terminal that can prompt." ;;
  esac
fi

exit $FAILED
