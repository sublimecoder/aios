#!/bin/sh
# AIOS Stop hook — append a signal-only session digest to the vault queue, and
# mirror this repo's Claude Code native memory into the vault for /aios-ingest.
# Writes ONLY to the vault; never touches the invoking repo. Best-effort persist.
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

REPO="${CLAUDE_PROJECT_DIR:-$PWD}"
res=$(aios_lookup "$REPO") || exit 0            # not in manifest → silent no-op
LAYER=$(echo "$res" | awk '{print $1}')
PROJECT=$(echo "$res" | awk '{print $2}')

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || exit 0   # not a git repo

HEAD=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo none)
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)

STATE_DIR="$AIOS_VAULT/+/_sessions/.state"
STATE="$STATE_DIR/${LAYER}__${PROJECT}"
LAST=$(cat "$STATE" 2>/dev/null || echo "")

# Fingerprint what the block WILL SAY, not the working tree that produced it.
# A repo carrying a long-lived uncommitted file is dirty every session, so a
# floor testing `-z "$DIRTY"` never trips and every session appends an identical
# block. Fingerprinting the tree instead leaks a subtler duplicate: the block
# only ever carries `diff --stat`, so an edit that changes CONTENT while leaving
# the stat identical (ticking an item off a 15-line todo — still "15 +++++")
# moves the tree hash but emits a block byte-identical to the last one. Hash the
# emitted stat: two sessions that would print the same block collapse to one,
# by construction.
STAT=$(git -C "$REPO" diff --stat HEAD 2>/dev/null)
STAT_SIG=$(printf '%s' "$STAT" | cksum)
STATE_D="$STATE.stat"
LAST_STAT_SIG=$(cat "$STATE_D" 2>/dev/null || echo "")

# Mirror Claude Code's native memory (durable facts it wrote) into the vault,
# partitioned by layer. git is the change detector; /aios-ingest compounds the
# changed files into AIOS/Projects/$LAYER/$PROJECT.md. AIOS_MEMORY_BASE override
# exists for the test harness; real sessions use ~/.claude/projects.
# ponytail: rsync --delete keeps the mirror exact — a memory the user retracted
# upstream is removed here too, so ingest never re-introduces a deleted fact.
MEM_BASE="${AIOS_MEMORY_BASE:-$HOME/.claude/projects}"
# Claude Code names its per-project memory dir by replacing every non-alphanumeric
# char in the abs path with '-' (so '/', '_', '.', '~' all collapse to '-').
# Matching '/' alone silently missed any repo with an underscore (my_project, …).
MEM_SRC="$MEM_BASE/$(printf '%s' "$REPO" | sed 's#[^a-zA-Z0-9]#-#g')/memory"
MEM_DST="$AIOS_VAULT/+/_sessions/.memory/$LAYER/$PROJECT"
MEM_CHANGED=""
if [ -d "$MEM_SRC" ]; then
  mkdir -p "$MEM_DST"
  rsync -a --delete --include='*.md' --exclude='*' "$MEM_SRC/" "$MEM_DST/" 2>/dev/null
  # -uall: list untracked files individually — without it git collapses a newly
  # untracked mirror dir to one "dir/" entry and the basename sed yields empty.
  MEM_CHANGED=$(git -C "$AIOS_VAULT" status --porcelain -uall -- "$MEM_DST" 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')
fi

# No-op floor: bail when the block would say nothing new — no new commits, no
# memory change, and a diffstat that is either empty or the same one already
# digested. Untracked-only churn floors out here: `diff --stat HEAD` never lists
# untracked files, so a block fired for one carries no word of it — an empty
# header and nothing else. Silence beats a block that says nothing.
if [ "$HEAD" = "$LAST" ] && [ -z "$MEM_CHANGED" ]; then
  [ -z "$STAT" ] && exit 0
  [ "$STAT_SIG" = "$LAST_STAT_SIG" ] && exit 0
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
QUEUE_DIR="$AIOS_VAULT/+/_sessions/$LAYER"
QUEUE="$QUEUE_DIR/$PROJECT.md"
mkdir -p "$QUEUE_DIR" "$STATE_DIR"

if [ -n "$LAST" ] && git -C "$REPO" cat-file -e "$LAST" 2>/dev/null; then
  COMMITS=$(git -C "$REPO" log --oneline "$LAST"..HEAD 2>/dev/null)
else
  COMMITS=$(git -C "$REPO" log --oneline -3 2>/dev/null)
fi

{
  echo "## $TS — local: $(date +'%F %H:%M %Z') — branch: $BRANCH — HEAD: $HEAD"
  [ -n "$COMMITS" ]     && { echo "commits:"; echo "$COMMITS"; }
  [ -n "$STAT" ]        && { echo "uncommitted:"; echo "$STAT"; }
  [ -n "$MEM_CHANGED" ] && echo "memory: $MEM_CHANGED"
  echo "---"
  echo
} >> "$QUEUE"

echo "$HEAD" > "$STATE"
echo "$STAT_SIG" > "$STATE_D"

# Persist the vault. macOS has no flock → atomic mkdir lock. All best-effort:
# a failure here never blocks session exit; the digest is already on disk.
LOCK="$AIOS_VAULT/.aios-sync.lock"
i=0
until mkdir "$LOCK" 2>/dev/null; do
  sleep 0.2; i=$((i + 1)); [ "$i" -gt 50 ] && exit 0
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ponytail: digests are machine-generated breadcrumbs — never sign them; a
# gpg-agent cache miss on this unattended commit would block forever holding the lock.
ADD_PATHS="+/_sessions/$LAYER/$PROJECT.md"
[ -d "$MEM_DST" ] && ADD_PATHS="$ADD_PATHS +/_sessions/.memory/$LAYER/$PROJECT"
git -C "$AIOS_VAULT" add $ADD_PATHS 2>/dev/null
# Commit ONLY the digest paths. A bare `commit` takes the whole index, so any
# work a human or agent had staged gets swept into this unattended commit —
# including, on the wrong day, one scope's file into another scope's commit.
# The `--` pathspec makes this a partial commit and leaves the index untouched.
git -C "$AIOS_VAULT" -c commit.gpgsign=false commit -q -m "aios: digest — $LAYER/$PROJECT @ $HEAD" -- $ADD_PATHS 2>/dev/null || exit 0
git -C "$AIOS_VAULT" push -q 2>/dev/null \
  || { git -C "$AIOS_VAULT" pull --rebase -q 2>/dev/null || git -C "$AIOS_VAULT" rebase --abort 2>/dev/null
       git -C "$AIOS_VAULT" push -q 2>/dev/null; }
exit 0
