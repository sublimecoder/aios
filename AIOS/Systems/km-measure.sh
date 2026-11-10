#!/bin/sh
# km-measure.sh — the ONE way to measure Knowledge Map line length.
#
# WHY THIS FILE EXISTS. The 1500 limit is enforced by aios-check.sh and authored
# against by aios-ingest step 1c, and for three consecutive runs those two
# disagreed about what was being counted:
#
#   - aios-check gates on `awk length`, which counts BYTES.
#   - step 1c told the author to come in under "1500 chars" and named no command,
#     so runs measured with Python `len` (CHARACTERS) and shipped a line at 1488
#     that the gate then failed at 1504.
#   - a map line is dense with em dashes, arrows and ⚠️ at 3-6 bytes each, so the
#     two units run 1-2% apart — right at the threshold, every time.
#
# Worse, wiki-lint-runner reported the limit breached with figures marked
# "(estimated)": ~1700/~1800/~2200 against a true 1373/1277/1445, and again
# ~2000+/~2000+/~1600+ against 1348/1439/1313. Every one of those was false, and
# the proposed remedy was km-rotate — a restructure of the file the retrieval
# policy says to read first, justified by a number nobody counted.
#
# So: one command, printing the unit the gate actually uses. An agent that runs
# this cannot estimate, and cannot pick the wrong unit.
#
# Usage:
#   km-measure.sh                 every over-limit line (silent when clean)
#   km-measure.sh --all           every line with its length
#   km-measure.sh -n 34           one line's length
#   km-measure.sh --file <path>   measure a different file
#
# Exit 1 when any line is over the limit, 0 otherwise — same direction as
# aios-check, so it is usable as a pre-write gate.
set -u

VAULT="${AIOS_VAULT:-$HOME/code/aios}"
KM="$VAULT/AIOS/Maps/Knowledge Map.md"
MAX="${KM_MAX:-1500}"
MODE=over
LINE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --all)   MODE=all ;;
    -n)      shift; LINE="${1:-}" ;;
    --file)  shift; KM="${1:-}" ;;
    --max)   shift; MAX="${1:-1500}" ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  esac
  shift
done

[ -f "$KM" ] || { echo "km-measure: no such file: $KM" >&2; exit 2; }

# BYTES, deliberately, because that is what KM_MAX is compared against in
# aios-check.sh -- and BYTES have to be FORCED, not assumed.
#
# This comment used to say `awk length` is byte-based "regardless of locale
# (verified both LC_ALL=C and en_US.UTF-8)". That verification ran on macOS BWK
# awk, where it is true. It is FALSE on gawk: GNU awk's `length` counts
# CHARACTERS in a UTF-8 locale, and a map line dense with em dashes and arrows
# runs 16-20 bytes under its true size. Measured on Arch 2026-09-05 -- KM line 13
# reported 1476 and is really 1496, i.e. 4 bytes of headroom against the gate
# rather than 24, with the check still printing "clean".
#
# LC_ALL=C is what makes `length` mean bytes on BOTH awks. It is not decoration
# and it must stay on every one of these invocations: the failure is silent, it
# under-reports in the permissive direction, and it defeats the exact
# unit-confusion this whole file exists to end.
case "$MODE" in
  all)
    LC_ALL=C awk '{ printf "%d\t%d\n", NR, length }' "$KM"
    exit 0
    ;;
esac

if [ -n "$LINE" ]; then
  LC_ALL=C awk -v n="$LINE" 'NR==n { print length }' "$KM"
  exit 0
fi

over=$(LC_ALL=C awk -v m="$MAX" 'length > m { printf "line %d: %d bytes (limit %d)\n", NR, length, m }' "$KM")
if [ -n "$over" ]; then
  printf '%s\n' "$over"
  exit 1
fi
exit 0
