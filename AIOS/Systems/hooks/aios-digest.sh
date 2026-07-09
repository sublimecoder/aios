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
DIRTY=$(git -C "$REPO" status --porcelain 2>/dev/null)

STATE_DIR="$AIOS_VAULT/+/_sessions/.state"
STATE="$STATE_DIR/${LAYER}__${PROJECT}"
LAST=$(cat "$STATE" 2>/dev/null || echo "")

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

# No-op floor: bail only if NOTHING changed — git state AND native memory stable.
[ -z "$DIRTY" ] && [ "$HEAD" = "$LAST" ] && [ -z "$MEM_CHANGED" ] && exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
QUEUE_DIR="$AIOS_VAULT/+/_sessions/$LAYER"
QUEUE="$QUEUE_DIR/$PROJECT.md"
mkdir -p "$QUEUE_DIR" "$STATE_DIR"

if [ -n "$LAST" ] && git -C "$REPO" cat-file -e "$LAST" 2>/dev/null; then
  COMMITS=$(git -C "$REPO" log --oneline "$LAST"..HEAD 2>/dev/null)
else
  COMMITS=$(git -C "$REPO" log --oneline -3 2>/dev/null)
fi
STAT=$(git -C "$REPO" diff --stat HEAD 2>/dev/null)

{
  echo "## $TS — branch: $BRANCH — HEAD: $HEAD"
  [ -n "$COMMITS" ]     && { echo "commits:"; echo "$COMMITS"; }
  [ -n "$STAT" ]        && { echo "uncommitted:"; echo "$STAT"; }
  [ -n "$MEM_CHANGED" ] && echo "memory: $MEM_CHANGED"
  echo "---"
  echo
} >> "$QUEUE"

echo "$HEAD" > "$STATE"

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
git -C "$AIOS_VAULT" -c commit.gpgsign=false commit -q -m "aios: digest — $LAYER/$PROJECT @ $HEAD" 2>/dev/null || exit 0
git -C "$AIOS_VAULT" push -q 2>/dev/null \
  || { git -C "$AIOS_VAULT" pull --rebase -q 2>/dev/null || git -C "$AIOS_VAULT" rebase --abort 2>/dev/null
       git -C "$AIOS_VAULT" push -q 2>/dev/null; }
exit 0
