#!/bin/sh
# Self-contained test for the AIOS hooks. Builds a temp vault + fake repos,
# exercises both hooks, asserts the wall + no-op floor + fail-closed behavior.
set -e
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AIOS_VAULT="$TMP/vault"
HOOKS="$AIOS_VAULT/AIOS/Systems/hooks"
SRC=$(CDPATH= cd "$(dirname "$0")" && pwd)

mkdir -p "$HOOKS" "$AIOS_VAULT/+/_sessions" "$AIOS_VAULT/AIOS/Projects"
cp "$SRC/lib.sh" "$SRC/aios-digest.sh" "$SRC/aios-context.sh" "$HOOKS/"
printf 'fakerepo\tcreator\tfakerepo\nprofrepo\tprofessional\tprofrepo\nnogit\tcreator\tnogit\nmemrepo\tprofessional\tmemrepo\n' > "$AIOS_VAULT/AIOS/Systems/repo-layers.tsv"
printf '# me\n## Durable preferences\n- first-person always\n' > "$AIOS_VAULT/AIOS/me-creator.md"

git -C "$AIOS_VAULT" init -q
git -C "$AIOS_VAULT" config user.email t@t; git -C "$AIOS_VAULT" config user.name t
git -C "$AIOS_VAULT" config commit.gpgsign false   # ponytail: throwaway repo, fake t@t identity has no GPG key
git -C "$AIOS_VAULT" add -A; git -C "$AIOS_VAULT" commit -qm init

REPO="$TMP/fakerepo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false   # ponytail: throwaway repo, fake t@t identity has no GPG key
echo hi > "$REPO/a.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm "add a"
echo more >> "$REPO/a.txt"   # uncommitted → dirty

fail() { echo "FAIL: $1"; exit 1; }
Q="$AIOS_VAULT/+/_sessions/creator/fakerepo.md"

# 1. happy path
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
[ -f "$Q" ] || fail "digest not written"
grep -q "branch:" "$Q" || fail "digest malformed"

# 2. wall: no professional queue created
[ ! -d "$AIOS_VAULT/+/_sessions/professional" ] || fail "cross-layer queue created"

# 3. no-op floor: clean tree + unchanged HEAD writes nothing new
git -C "$REPO" checkout -- a.txt
BEFORE=$(wc -l < "$Q")
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
AFTER=$(wc -l < "$Q")
[ "$BEFORE" = "$AFTER" ] || fail "no-op session wrote a digest"

# 3b. no-op floor, dirty edition: a repo carrying a long-lived uncommitted file
# is dirty every session. An unchanged dirty tree at an unchanged HEAD is not
# news — it must NOT append a block each time. Regression guard: this once
# shipped 30 identical blocks into one queue.
printf 'one\n' > "$REPO/lessons.md"
git -C "$REPO" add lessons.md; git -C "$REPO" commit -qm "track lessons"  # tracked, like the real one
printf 'one\ntwo\n' > "$REPO/lessons.md"                                  # long-lived uncommitted edit
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"   # 1st sight of it → digests
BEFORE=$(wc -l < "$Q")
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
[ "$(wc -l < "$Q")" = "$BEFORE" ] || fail "unchanged dirty tree re-digested (the identical-blocks bug)"

# 3c. the duplicate that survived 3b: an edit that changes CONTENT but leaves the
# diffstat identical (ticking an item off a todo list — same line count) must NOT
# fire, because the block it would emit is byte-identical to the last one.
printf 'one\nTWO\n' > "$REPO/lessons.md"   # same 1-line diffstat, different bytes
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
[ "$(wc -l < "$Q")" = "$BEFORE" ] || fail "content-only edit re-digested an identical block (the duplicate-diffstat bug)"
# but an edit that MOVES the diffstat is real news and must still fire
printf 'one\nTWO\nthree\nfour\n' > "$REPO/lessons.md"
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
[ "$(wc -l < "$Q")" -gt "$BEFORE" ] || fail "a changed diffstat did not fire a digest"

# 3d. no block may be emitted with nothing in it — untracked-only churn never
# reaches `diff --stat`, so a block fired for it would carry no word of the file.
git -C "$REPO" checkout -- lessons.md; git -C "$REPO" checkout -- a.txt
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"   # settle the state
BEFORE=$(wc -l < "$Q")
echo scratch > "$REPO/untracked.tmp"
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
[ "$(wc -l < "$Q")" = "$BEFORE" ] || fail "untracked-only churn emitted an empty block"
rm "$REPO/untracked.tmp"
echo more >> "$REPO/a.txt"   # restore the dirty tree the later tests assume

# 4. fail-closed: repo not in manifest → exit 0, nothing written
OTHER="$TMP/unknown"; mkdir -p "$OTHER"; git -C "$OTHER" init -q
CLAUDE_PROJECT_DIR="$OTHER" sh "$HOOKS/aios-digest.sh" || fail "non-manifest repo errored"
find "$AIOS_VAULT/+/_sessions" -name 'unknown.md' | grep -q . && fail "wrote for non-manifest repo"

# 5. context hook emits me-creator durable + log pointer
OUT=$(CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-context.sh")
echo "$OUT" | grep -q "first-person always" || fail "context missing me-creator"
echo "$OUT" | grep -q "aios-log.md" || fail "context missing log pointer"

# 6. not-a-git-repo guard: in manifest but not a git repo → exit 0, writes nothing
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"   # no git init
CLAUDE_PROJECT_DIR="$NOGIT" sh "$HOOKS/aios-digest.sh" || fail "non-git repo errored"
[ ! -f "$AIOS_VAULT/+/_sessions/creator/nogit.md" ] || fail "wrote for non-git repo"

# 7. bidirectional wall: professional repo lands under professional, NOT creator
PROF="$TMP/profrepo"; mkdir -p "$PROF"
git -C "$PROF" init -q
git -C "$PROF" config user.email t@t; git -C "$PROF" config user.name t
git -C "$PROF" config commit.gpgsign false
echo p > "$PROF/p.txt"; git -C "$PROF" add -A; git -C "$PROF" commit -qm "add p"
echo more >> "$PROF/p.txt"   # dirty
CLAUDE_PROJECT_DIR="$PROF" sh "$HOOKS/aios-digest.sh"
[ -f "$AIOS_VAULT/+/_sessions/professional/profrepo.md" ] || fail "professional digest not written"
[ ! -f "$AIOS_VAULT/+/_sessions/creator/profrepo.md" ] || fail "professional repo leaked into creator queue"

# 8. native-memory mirror: a memory file Claude Code wrote is mirrored into the
#    vault under the right layer, triggers a digest even on a git no-op, and
#    rsync --delete retracts it from the mirror when removed upstream.
MEMR="$TMP/memrepo"; mkdir -p "$MEMR"
git -C "$MEMR" init -q
git -C "$MEMR" config user.email t@t; git -C "$MEMR" config user.name t
git -C "$MEMR" config commit.gpgsign false
echo m > "$MEMR/m.txt"; git -C "$MEMR" add -A; git -C "$MEMR" commit -qm "add m"
# must match the hook's encoding exactly (temp paths can contain _ and .)
MEMR_FLAT=$(printf '%s' "$MEMR" | sed 's#[^a-zA-Z0-9]#-#g')
MSRC="$TMP/mem/$MEMR_FLAT/memory"; mkdir -p "$MSRC"
MQ="$AIOS_VAULT/+/_sessions/professional/memrepo.md"
MIRROR="$AIOS_VAULT/+/_sessions/.memory/professional/memrepo"
# prime: clean run records HEAD so the next git no-op would normally floor out
AIOS_MEMORY_BASE="$TMP/mem" CLAUDE_PROJECT_DIR="$MEMR" sh "$HOOKS/aios-digest.sh"
BEFORE=$(wc -l < "$MQ")
# Claude Code "writes" a durable memory; repo git tree stays clean + HEAD unchanged
printf -- '---\nname: x\n---\nfact\n' > "$MSRC/fact.md"
AIOS_MEMORY_BASE="$TMP/mem" CLAUDE_PROJECT_DIR="$MEMR" sh "$HOOKS/aios-digest.sh"
[ -f "$MIRROR/fact.md" ] || fail "memory file not mirrored into vault"
grep -q "memory: .*fact.md" "$MQ" || fail "digest missing memory: line"
[ "$(wc -l < "$MQ")" -gt "$BEFORE" ] || fail "memory change did not trigger a digest on git no-op"
# retraction: removing the memory upstream removes the vault mirror copy
rm "$MSRC/fact.md"
AIOS_MEMORY_BASE="$TMP/mem" CLAUDE_PROJECT_DIR="$MEMR" sh "$HOOKS/aios-digest.sh"
[ ! -f "$MIRROR/fact.md" ] || fail "retracted memory not removed from mirror (rsync --delete)"

# 9. the digest commit takes ONLY its own paths — never the rest of the index.
# A bare `git commit` commits the whole index, so staged human/agent work gets
# swept into an unattended, scope-tagged commit. Regression guard.
printf 'staged by a human\n' > "$AIOS_VAULT/UNRELATED.md"
git -C "$AIOS_VAULT" add UNRELATED.md
echo more >> "$REPO/a.txt"                       # make the repo dirty so a digest fires
CLAUDE_PROJECT_DIR="$REPO" sh "$HOOKS/aios-digest.sh"
git -C "$AIOS_VAULT" log -1 --name-only --format= | grep -q '^UNRELATED.md$' \
  && fail "digest commit swallowed a staged file outside its own paths"
git -C "$AIOS_VAULT" diff --cached --name-only | grep -q '^UNRELATED.md$' \
  || fail "digest commit consumed the staged file (it must remain staged, uncommitted)"
git -C "$AIOS_VAULT" log -1 --name-only --format= | grep -q '_sessions/creator/fakerepo.md' \
  || fail "digest commit did not include its own digest file"

echo "ALL PASS"
