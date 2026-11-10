#!/bin/sh
# Self-check for km-measure.sh.
#
# The script exists because a threshold was measured three different ways by
# three different callers, so this suite's job is to pin the ONE property that
# matters: km-measure agrees with aios-check's gate, in bytes, exactly at the
# boundary. A test that only checked "big line is caught" would pass on a
# character-counting implementation — which is the bug.
set -u
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
M="$HERE/${KMM:-km-measure.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$2] got [$3])"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
F="$TMP/km.md"

echo "km-measure self-check"

# --- ASCII: bytes and characters agree, so this only proves basic counting ---
printf 'abc\n' > "$F"
chk "counts a short ascii line" "3" "$(sh "$M" --file "$F" -n 1)"

# --- the byte-vs-char case, which is the entire point -----------------------
# 'a—b' is 3 CHARACTERS and 5 BYTES (the em dash is 3 bytes in UTF-8). A
# character-counting implementation returns 3 here and silently under-reports
# every dense map line by 1-2% — exactly enough to ship a line the gate rejects.
printf 'a—b\n' > "$F"
chk "counts BYTES not characters (em dash)" "5" "$(sh "$M" --file "$F" -n 1)"
# ⚠️ is 6 bytes (U+26A0 + VS16), 2 characters.
printf '⚠️\n' > "$F"
chk "counts BYTES not characters (warning sign + VS16)" "6" "$(sh "$M" --file "$F" -n 1)"

# --- boundary behaviour, both sides -----------------------------------------
# Exactly at the limit is ALLOWED (the gate is `length > m`), one over is not.
# Off-by-one here is the difference between agreeing with aios-check and not.
awk 'BEGIN{ s=""; for(i=0;i<1500;i++) s=s "x"; print s }' > "$F"
sh "$M" --file "$F" >/dev/null 2>&1
chk "a line of exactly 1500 bytes is clean (exit 0)" "0" "$?"

awk 'BEGIN{ s=""; for(i=0;i<1501;i++) s=s "x"; print s }' > "$F"
out=$(sh "$M" --file "$F" 2>&1); rc=$?
chk "a line of 1501 bytes is flagged (exit 1)" "1" "$rc"
chk "the finding names the measured value" "1" "$(printf '%s' "$out" | grep -c '1501 bytes')"

# --- agreement with the real gate, on the real file -------------------------
# The property that actually matters: whatever aios-check would flag, this flags,
# and vice versa. Compares against aios-check's own awk expression rather than
# its output, so it holds even if the message wording changes again.
KM="$HERE/../Maps/Knowledge Map.md"
if [ -f "$KM" ]; then
  gate=$(awk 'length > 1500 { print NR }' "$KM" | tr '\n' ' ')
  mine=$(sh "$M" --file "$KM" 2>/dev/null | sed 's/^line \([0-9]*\):.*/\1/' | tr '\n' ' ')
  chk "agrees with aios-check's gate on the live Knowledge Map" "$gate" "$mine"

  # --all must report every line, not just the over-limit ones.
  lines=$(wc -l < "$KM" | tr -d ' ')
  chk "--all reports every line" "$lines" "$(sh "$M" --file "$KM" --all | wc -l | tr -d ' ')"
fi

# --- a missing file is an error, not a silent pass --------------------------
# Silence would read as "clean" to a caller that only checks the exit code.
sh "$M" --file "$TMP/nope.md" >/dev/null 2>&1
chk "a missing file exits 2, never 0" "2" "$?"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
