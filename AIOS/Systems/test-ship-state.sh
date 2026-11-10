#!/bin/sh
# Self-check for ship-state.sh. Run: sh AIOS/Systems/test-ship-state.sh
#
# The query order (forge -> fallback -> ancestry-confirm-only) is the entire
# point of ship-state.sh, so every branch is exercised both ways: the state
# that should fire, and the sibling state that must NOT fire from the same
# fixture. A fake `gh` shim (ahead of the real one on PATH) makes the forge
# branch deterministic and offline; the fallback and ancestry branches use a
# real local bare "origin" so no network or GitHub account is needed either.
set -u
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
SHIP="$HERE/ship-state.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { # label expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi
}
contains() { # label needle haystack
  case "$3" in (*"$2"*) ok "$1" ;; (*) bad "$1 (expected to contain [$2], got [$3])" ;; esac
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- fixture: a real local "origin" so origin/HEAD and origin/main resolve
# without any network or GitHub account. -----------------------------------
BARE="$TMP/origin.git"
REPO="$TMP/work"
git init -q --bare "$BARE"
git init -q "$REPO"
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" remote add origin "$BARE"
echo a > "$REPO/a.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm base
git -C "$REPO" branch -M main
git -C "$REPO" push -q -u origin main
git -C "$REPO" remote set-head origin main
BASE_SHA=$(git -C "$REPO" rev-parse HEAD)

# A commit already on main, standing in for a squash-merged PR whose commit
# subject survived the squash.
echo b > "$REPO/b.txt"; git -C "$REPO" add -A
git -C "$REPO" commit -qm "widget: add support"
git -C "$REPO" push -q origin main

# A never-pushed commit with the SAME subject: the pre-squash feature-branch
# commit, sha never appears on main, only its subject does. Branches from
# the captured BASE_SHA, not a relative main~1 — main keeps gaining commits
# below, so a relative ref here would silently point somewhere else each
# time this fixture is extended.
git -C "$REPO" checkout -qb squash-feature "$BASE_SHA"
echo c > "$REPO/c.txt"; git -C "$REPO" add -A
git -C "$REPO" commit -qm "widget: add support"
SQUASH_SHA=$(git -C "$REPO" rev-parse HEAD)

# A never-pushed commit whose subject appears NOWHERE on main and is not an
# ancestor of it either — the genuinely-unresolvable case.
git -C "$REPO" checkout -qb orphan-feature "$BASE_SHA"
echo d > "$REPO/d.txt"; git -C "$REPO" add -A
git -C "$REPO" commit -qm "unmerged experiment, never landed"
ORPHAN_SHA=$(git -C "$REPO" rev-parse HEAD)

# An empty-message commit ON main (pushed): a literal ancestor whose subject
# is "", so the fallback's `[ -n "$subject" ]` guard skips it and only
# ancestry can resolve it. Carries a file change so its tree — and so its
# sha — cannot collide with the orphan counterpart below even if both land
# in the same second with the same parent and the same empty message.
git -C "$REPO" checkout -q main
echo e > "$REPO/e.txt"; git -C "$REPO" add -A
git -C "$REPO" commit -q --allow-empty-message -m ""
git -C "$REPO" push -q origin main
ANCESTOR_EMPTY_SHA=$(git -C "$REPO" rev-parse HEAD)

# The same empty-subject shape, but on a never-pushed branch off BASE_SHA:
# NOT an ancestor of main. Isolates the "no is discarded, never OPEN"
# contract from the fallback (subject-match is already excluded by
# construction). A distinct file change again guarantees a distinct sha from
# ANCESTOR_EMPTY_SHA above.
git -C "$REPO" checkout -qb orphan-empty "$BASE_SHA"
echo f > "$REPO/f.txt"; git -C "$REPO" add -A
git -C "$REPO" commit -q --allow-empty-message -m ""
ORPHAN_EMPTY_SHA=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" checkout -q main

# --- fake gh: makes the forge branch deterministic and offline -------------
# Controlled via env: FAKE_GH_AUTH_OK, FAKE_GH_PR_NUM, FAKE_GH_PR_STATE,
# FAKE_GH_MERGE_SHA. Ahead of the real gh on PATH, so `command -v gh` finds
# this one first regardless of what's installed on the machine running the
# test.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'SHIM'
#!/bin/sh
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  [ "${FAKE_GH_AUTH_OK:-1}" = "1" ] && exit 0 || exit 1
fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  # FAKE_GH_LIST_FAIL fakes the throttle/network/expired-token case: nonzero exit
  # with a reason on stderr and nothing on stdout — indistinguishable on stdout
  # alone from "the forge answered and no PR references this sha".
  if [ -n "${FAKE_GH_LIST_FAIL:-}" ]; then
    echo "HTTP 403: API rate limit exceeded" >&2
    exit 1
  fi
  [ -n "${FAKE_GH_PR_NUM:-}" ] && echo "$FAKE_GH_PR_NUM"
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  # ship-state.sh makes exactly one view call per PR now (state, mergedAt,
  # mergeCommit together) — one output shape to fake.
  printf '%s\t%s\t%s\n' "${FAKE_GH_PR_STATE:-}" "${FAKE_GH_MERGED_AT:-}" "${FAKE_GH_MERGE_SHA:-}"
  exit 0
fi
exit 1
SHIM
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

run() { FAKE_GH_AUTH_OK="${1:-1}" FAKE_GH_PR_NUM="${2:-}" FAKE_GH_PR_STATE="${3:-}" \
        FAKE_GH_MERGE_SHA="${4:-}" FAKE_GH_MERGED_AT="${6:-}" sh "$SHIP" "$REPO" "$5"; }

echo "ship-state self-check"

# --- 1. forge MERGED is the only affirmative answer for LANDED -------------
out=$(run 1 42 MERGED deadc0de "$SQUASH_SHA" 2026-01-02T00:00:00Z)
contains "forge MERGED -> LANDED" "LANDED" "$out"
contains "forge MERGED -> evidence names the PR" "PR #42" "$out"
contains "forge MERGED -> evidence carries the merge sha" "deadc0de" "$out"
contains "forge MERGED -> evidence carries mergedAt (not fetched-and-dropped)" "2026-01-02T00:00:00Z" "$out"

# --- 2. same PR, OPEN instead of MERGED: the sibling state must fire, not
# LANDED. Mutation of test 1's fixture, not a hand-edit of the script. ------
out=$(run 1 42 OPEN "" "$SQUASH_SHA")
check "forge OPEN -> OPEN, not LANDED" "OPEN" "$out"

# --- 3. a forge PR that is neither MERGED nor OPEN (e.g. closed without
# merging) is not an affirmative answer for anything. With no subject match
# and no ancestry either, the only honest answer is UNKNOWN — never OPEN. ---
out=$(run 1 7 CLOSED "" "$ORPHAN_SHA")
check "forge CLOSED, no fallback/ancestry match -> UNKNOWN" "UNKNOWN" "$out"

# --- 4. forge unreachable (bad auth) falls to the squash-subject fallback --
out=$(run 0 "" "" "" "$SQUASH_SHA")
contains "forge unreachable, subject matches main -> LANDED" "LANDED" "$out"
contains "fallback evidence names the match" "squash-subject match" "$out"

# --- 5. mutation of test 4: same fixture, but the ref's subject does not
# appear on main and it is not an ancestor -> the fallback must NOT fire. ---
out=$(run 0 "" "" "" "$ORPHAN_SHA")
check "forge unreachable, no subject match, not an ancestor -> UNKNOWN" "UNKNOWN" "$out"

# --- 6. ancestry may CONFIRM: an empty-subject commit skips the fallback's
# subject guard entirely, so only ancestry can resolve it. It IS an ancestor
# of main here -> LANDED. -----------------------------------------------
out=$(run 0 "" "" "" "$ANCESTOR_EMPTY_SHA")
contains "empty subject + real ancestor -> LANDED" "LANDED" "$out"
contains "ancestry evidence names the branch" "ancestor of" "$out"

# --- 7. mutation of test 6: identical empty-subject shape, but NOT an
# ancestor. THE DANGEROUS DIRECTION: a merge-base "no" must be discarded,
# never recorded as OPEN. Without that discard rule this would misreport
# OPEN (or worse, LANDED) on a commit that never shipped. -------------------
out=$(run 0 "" "" "" "$ORPHAN_EMPTY_SHA")
check "empty subject, NOT an ancestor -> UNKNOWN (never OPEN)" "UNKNOWN" "$out"

# --- 8. an unresolvable ref must never crash and must never read as OPEN ---
out=$(run 1 "" "" "" "deadbeef")
check "nonsense ref -> UNKNOWN, no crash" "UNKNOWN" "$out"

# --- a FAILED forge query is distinguishable from a genuine no-answer ------
# Both print a bare UNKNOWN on stdout and always will — the three-shape stdout
# contract is what several ingest steps branch on, so widening it is a separate
# decision. What changed is that the FAILURE now says so on stderr. On 2026-08-12
# a rate limit produced 7 spurious BRANCH STATE flags and the reason was
# unrecoverable afterwards, because the only evidence had gone to /dev/null.
# ORPHAN_SHA, not SQUASH_SHA: a failed forge query is NOT automatically UNKNOWN —
# step 2's squash-subject fallback still runs and can settle it from local git
# alone, which narrows what the 2026-08-12 throttle could actually have corrupted
# to refs the fallback ALSO could not match. Using a resolvable sha here asserted
# the wrong thing and caught it on the first run.
out=$(FAKE_GH_LIST_FAIL=1 FAKE_GH_AUTH_OK=1 sh "$SHIP" "$REPO" "$ORPHAN_SHA" 2>/dev/null)
check "a failed forge query on an unresolvable ref still answers UNKNOWN" "UNKNOWN" "$out"

# ...and the fallback is NOT disabled by the failure: a ref it can resolve still
# resolves. This is the half that bounds the blast radius.
out=$(FAKE_GH_LIST_FAIL=1 FAKE_GH_AUTH_OK=1 sh "$SHIP" "$REPO" "$SQUASH_SHA" 2>/dev/null)
case "$out" in
  LANDED*) ok "a failed forge query still lets the local fallback answer" ;;
  *) bad "forge failure suppressed the local fallback: $out" ;;
esac

err=$(FAKE_GH_LIST_FAIL=1 FAKE_GH_AUTH_OK=1 sh "$SHIP" "$REPO" "$ORPHAN_SHA" 2>&1 >/dev/null)
case "$err" in
  *"forge query FAILED"*"rate limit"*) ok "the failure names itself, and the reason, on stderr" ;;
  *) bad "failed query diagnostic missing or unreasoned: $err" ;;
esac

# THE DANGEROUS DIRECTION. A SUCCESSFUL query that simply finds no PR must stay
# silent — keying the diagnostic on stderr being non-empty instead of on the exit
# status would fire here too (gh writes advisory notices on success), and a warning
# that cries wolf on the common path is one that gets ignored on the real one.
err=$(FAKE_GH_AUTH_OK=1 sh "$SHIP" "$REPO" "$ORPHAN_SHA" 2>&1 >/dev/null)
case "$err" in
  *"forge query FAILED"*) bad "a successful no-PR query wrongly reported a failure: $err" ;;
  *) ok "a successful query that finds no PR stays silent on stderr" ;;
esac

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
