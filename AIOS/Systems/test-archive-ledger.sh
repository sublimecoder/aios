#!/bin/sh
# Self-check for archive-ledger.sh. Run: sh AIOS/Systems/test-archive-ledger.sh
#
# Fixtures exercise, on purpose: both heading shapes (with/without `local:`),
# a HEAD sha that reappears as its own block's first commit-list entry (a
# real, common, same-block "duplicate" that must be SUPPRESSED, not
# reported), a sha that recurs across blocks in one file, a sha that recurs
# across FILES at two different abbrev lengths (the 8->9 core.abbrev growth
# this repo actually hit), a literal `none` HEAD, a forced heading/`---`
# mismatch (plus a cancelling pair across two files, so an aggregate
# implementation can't fake a pass), an `uncommitted:` diffstat line shaped
# like an unanchored commit line, a genuine 7-char abbrev COLLISION (two
# different commits sharing a 7-char prefix, which must NOT transitively
# merge), and the argument-order survivor contract the wired
# `aios-ingest.md` command depends on.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
LEDGER="$HERE/archive-ledger.sh"
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
fails=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$2] got [$3]"; fails=$((fails+1)); fi
}
check_has() { # name haystack needle
  case "$2" in
    *"$3"*) echo "ok   - $1" ;;
    *) echo "FAIL - $1: did not find [$3]"; fails=$((fails+1)) ;;
  esac
}
check_not_has() { # name haystack needle
  case "$2" in
    *"$3"*) echo "FAIL - $1: unexpectedly found [$3]"; fails=$((fails+1)) ;;
    *) echo "ok   - $1" ;;
  esac
}

cat > "$D/fixtureA.md" <<'EOF'
## 2026-01-01T00:00:00Z — branch: main — HEAD: aaaaaaaa
commits:
aaaaaaaa first commit subject
bbbbbbbb second commit subject
---

## 2026-01-02T00:00:00Z — branch: main — HEAD: cccccccc
commits:
cccccccc third commit subject
bbbbbbbb second commit subject
---
EOF

cat > "$D/fixtureB.md" <<'EOF'
## 2026-01-03T00:00:00Z — local: 2026-01-02 17:00 PDT — branch: feature/x — HEAD: dddddddd
commits:
dddddddd fourth commit subject
bbbbbbbbb second commit subject at 9-char abbrev
---

## 2026-01-04T00:00:00Z — local: 2026-01-03 17:00 PDT — branch: main — HEAD: none
memory: MEMORY.md
---
EOF

cat > "$D/fixtureC.md" <<'EOF'
## 2026-01-05T00:00:00Z — branch: main — HEAD: eeeeeeee
commits:
eeeeeeee only commit
---
---
EOF

cat > "$D/fixtureD.md" <<'EOF'
## 2026-01-06T00:00:00Z — branch: main — HEAD: ffffffff
commits:
ffffffff only commit in section
uncommitted:
abcdef12 unindented-diffstat-lookalike | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
memory: MEMORY.md
---
EOF

# Genuine 7-char abbrev collision: abcdef12 and abcdef13 are DIFFERENT
# commits that happen to share their first 7 hex chars; a later block
# refers to the same prefix at only 7 chars, which is ambiguous between
# them and must not be resolved either way.
cat > "$D/fixtureE.md" <<'EOF'
## 2026-02-01T00:00:00Z — branch: main — HEAD: abcdef12
commits:
abcdef12 first genuinely distinct commit
---

## 2026-02-02T00:00:00Z — branch: main — HEAD: abcdef13
commits:
abcdef13 second genuinely distinct commit, only shares a 7-char prefix
---

## 2026-02-03T00:00:00Z — branch: main — HEAD: abcdef1
commits:
abcdef1 ambiguous 7-char reference — could be either block above
---
EOF

# Cancelling pair for the per-file mismatch cross-check (finding 5): file X
# has 3 headings / 2 separators, file Y has 2 headings / 3 separators. Summed
# in aggregate that's 5/5 — an aggregate implementation would report zero
# mismatches here even though BOTH files are individually wrong.
cat > "$D/fixtureX.md" <<'EOF'
## 2026-04-01T00:00:00Z — branch: main — HEAD: 11111111
commits:
11111111 one
---

## 2026-04-02T00:00:00Z — branch: main — HEAD: 22222222
commits:
22222222 two

## 2026-04-03T00:00:00Z — branch: main — HEAD: 33333333
commits:
33333333 three
---
EOF

cat > "$D/fixtureY.md" <<'EOF'
## 2026-04-04T00:00:00Z — branch: main — HEAD: 44444444
commits:
44444444 four
---
---

## 2026-04-05T00:00:00Z — branch: main — HEAD: 55555555
commits:
55555555 five
---
EOF

# Argument-order survivor contract: same sha, two files, one block each.
# Whichever file is named FIRST on the command line owns the survivor.
cat > "$D/fixtureF.md" <<'EOF'
## 2026-03-01T00:00:00Z — branch: main — HEAD: 99999999
commits:
99999999 shared commit
---
EOF

cat > "$D/fixtureG.md" <<'EOF'
## 2026-03-02T00:00:00Z — branch: main — HEAD: 99999999
commits:
99999999 shared commit again
---
EOF

# 1. count: both heading shapes, no mismatch, exit 0.
out="$(sh "$LEDGER" count "$D/fixtureA.md" "$D/fixtureB.md")"; rc=$?
check "count A+B total" "TOTAL 4 blocks, 2 files, 0 mismatches" "$(printf '%s\n' "$out" | tail -1)"
check "count A+B exit code" "0" "$rc"

# 2. count: forced heading/--- mismatch is caught PER FILE and fails the run.
out="$(sh "$LEDGER" count "$D/fixtureC.md" 2>/tmp/al-test-mismatch.$$)"; rc=$?
check "count C total" "TOTAL 1 blocks, 1 files, 1 mismatches" "$(printf '%s\n' "$out" | tail -1)"
check "count C exit code (mismatch fails)" "1" "$rc"
check_has "count C reports the mismatch" "$(cat /tmp/al-test-mismatch.$$)" "MISMATCH"
rm -f /tmp/al-test-mismatch.$$

# 2b. count: cancelling pair (X: 3/2, Y: 2/3) — aggregate is 5/5 but BOTH
# files are individually wrong. Pins the PER-FILE property (finding 5): an
# aggregate-only implementation would report 0 mismatches here.
out="$(sh "$LEDGER" count "$D/fixtureX.md" "$D/fixtureY.md" 2>/tmp/al-test-cancel.$$)"; rc=$?
check "count X+Y total (aggregate would look balanced)" "TOTAL 5 blocks, 2 files, 2 mismatches" "$(printf '%s\n' "$out" | tail -1)"
check "count X+Y exit code" "1" "$rc"
check_has "count X+Y flags fixtureX" "$(cat /tmp/al-test-cancel.$$)" "MISMATCH $D/fixtureX.md: headings=3 separators=2"
check_has "count X+Y flags fixtureY" "$(cat /tmp/al-test-cancel.$$)" "MISMATCH $D/fixtureY.md: headings=2 separators=3"
rm -f /tmp/al-test-cancel.$$

# 3. count: missing file exits 2, names itself.
out="$(sh "$LEDGER" count "$D/nope.md" 2>&1)"; rc=$?
check "count missing file exit code" "2" "$rc"
check_has "count missing file names itself" "$out" "nope.md"

# 4. dedupe: prefix-collapse (8-char vs 9-char) + cross-file duplication,
# with same-block self-matches (HEAD == own first commit) SUPPRESSED.
out="$(sh "$LEDGER" dedupe "$D/fixtureA.md" "$D/fixtureB.md")"
check "dedupe A+B occurrences" "OCCURRENCES 9" "$(printf '%s\n' "$out" | grep '^OCCURRENCES')"
check "dedupe A+B groups" "GROUPS 4" "$(printf '%s\n' "$out" | grep '^GROUPS')"
# 5 raw pairs minus 3 same-block self-matches (aaaaaaaa, cccccccc, dddddddd
# each restate their own HEAD as their first commit) = 2.
check "dedupe A+B redundant (self-matches suppressed)" "REDUNDANT 2" "$(printf '%s\n' "$out" | grep '^REDUNDANT')"
check "dedupe A+B cross-file" "CROSS-FILE 1" "$(printf '%s\n' "$out" | grep '^CROSS-FILE')"
check_not_has "dedupe A+B never prints a same-block self-match" "$out" "duplicates	aaaaaaaa	$D/fixtureA.md	## 2026-01-01T00:00:00Z — branch: main — HEAD: aaaaaaaa"
# The 9-char sha (fixtureB) must be reported as a duplicate naming the
# SURVIVING block (fixtureA's first bbbbbbbb, not string-equal to it) —
# proves min-length prefix-collapse, not exact-string equality, and proves
# every DUP line names its surviving block.
check_has "dedupe collapses 9-char onto 8-char survivor" "$out" \
  "DUP	bbbbbbbbb	$D/fixtureB.md	## 2026-01-03T00:00:00Z — local: 2026-01-02 17:00 PDT — branch: feature/x — HEAD: dddddddd	duplicates	bbbbbbbb	$D/fixtureA.md	## 2026-01-01T00:00:00Z — branch: main — HEAD: aaaaaaaa"
# HEAD `none` must not crash and must not become an occurrence.
check_not_has "dedupe never records literal 'none' as a sha" "$out" "	none	"
# Per-block roll-up (finding 4): cccccccc's block has 2 commit-list entries,
# 1 of which (bbbbbbbb) duplicates something earlier.
check_has "dedupe BLOCK roll-up names n-of-m for a partially-duplicate block" "$out" \
  "BLOCK	$D/fixtureA.md	## 2026-01-02T00:00:00Z — branch: main — HEAD: cccccccc	1/2 already-elsewhere"
check_has "dedupe BLOCK roll-up shows 0-of-m for the first, wholly-original block" "$out" \
  "BLOCK	$D/fixtureA.md	## 2026-01-01T00:00:00Z — branch: main — HEAD: aaaaaaaa	0/2 already-elsewhere"

# 5. dedupe: the commits:-section anchor. A line shaped exactly like a
# commit-list entry (hex + space) sitting inside `uncommitted:` must NOT be
# picked up — only inside an actual `commits:` section.
out="$(sh "$LEDGER" dedupe "$D/fixtureD.md")"
check "dedupe D occurrences (anchor holds)" "OCCURRENCES 2" "$(printf '%s\n' "$out" | grep '^OCCURRENCES')"
check_not_has "dedupe D never sees the uncommitted-section lookalike" "$out" "abcdef1"

# 6. dedupe: 7-char abbrev collision must NOT transitively merge (finding 3).
# abcdef12 and abcdef13 are different commits; abcdef1 is ambiguous between
# them and must be refused, not guessed — zero DUP lines, three groups.
out="$(sh "$LEDGER" dedupe "$D/fixtureE.md")"
check "dedupe E groups (collision stays 3 separate identities)" "GROUPS 3" "$(printf '%s\n' "$out" | grep '^GROUPS')"
check "dedupe E redundant (nothing legitimately collapses)" "REDUNDANT 0" "$(printf '%s\n' "$out" | grep '^REDUNDANT')"
check_not_has "dedupe E never prints a DUP line for the collision" "$out" "DUP"

# 7. dedupe: argument-order IS the survivor contract (finding 1) — the file
# named FIRST on the command line owns the survivor, whichever file it is.
outFG="$(sh "$LEDGER" dedupe "$D/fixtureF.md" "$D/fixtureG.md")"
check_has "dedupe F,G: survivor is F (named first)" "$outFG" \
  "duplicates	99999999	$D/fixtureF.md	## 2026-03-01T00:00:00Z — branch: main — HEAD: 99999999"
check_not_has "dedupe F,G: G is never the survivor" "$outFG" \
  "duplicates	99999999	$D/fixtureG.md"
outGF="$(sh "$LEDGER" dedupe "$D/fixtureG.md" "$D/fixtureF.md")"
check_has "dedupe G,F: survivor is G (named first) — direction inverts with argument order" "$outGF" \
  "duplicates	99999999	$D/fixtureG.md	## 2026-03-02T00:00:00Z — branch: main — HEAD: 99999999"
check_not_has "dedupe G,F: F is never the survivor" "$outGF" \
  "duplicates	99999999	$D/fixtureF.md"

echo "---"; [ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails FAILED"; exit 1; }
