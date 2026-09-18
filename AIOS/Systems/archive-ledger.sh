#!/bin/sh
# archive-ledger.sh count|dedupe <file>...
#
# The dedupe ledger for AIOS/History/_ingested/. aios-ingest.md calls the
# archive "the dedupe ledger, not just evidence storage" — this is the tool
# that makes that true instead of a hand-count. Two subcommands:
#
#   count <file>...   block count per file (the anchor below), cross-checked
#                      per FILE against `^---$` separators — never in
#                      aggregate, an aggregate total can match by coincidence
#                      while individual files are wrong.
#   dedupe <file>...   every commit/HEAD sha across the given files, grouped
#                      by identity (see prefix-collapse below). ARGUMENT
#                      ORDER IS THE CONTRACT: within a group, the sha seen
#                      in the FIRST file named on the command line is the
#                      survivor, and every later occurrence prints as
#                      "duplicates" it. Callers checking "is this already
#                      archived" must pass the archive glob(s) BEFORE the
#                      file under test — archive-first, candidate-last — or
#                      every duplicate direction inverts and the check finds
#                      nothing, silently, every time. Also emits one BLOCK
#                      line per block with a `commits:` section: how many of
#                      that block's commit-list entries printed as a
#                      duplicate of something earlier, out of how many total
#                      — n==m means the whole block is already accounted for
#                      elsewhere in the file list, in argument order.
#
# Block anchor (corrected — do not add "local: "; two heading shapes exist,
# roughly half the corpus carries a `local:` segment and half doesn't, and
# appending it to the anchor silently drops the other half):
#   ^## [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — <rest>
# Separator is em-dash U+2014, one space each side.
#
# SHA extraction — two line-anchored patterns, each valid only in its own
# context. Never unanchored: commit SUBJECTS contain hex-looking fragments.
#   commit list:  ^([0-9a-f]{7,40}) <rest>   only inside a `commits:` section
#   heading:      — HEAD: ([0-9a-f]{7,40})$
# The literal string `none` is tolerated for HEAD/BRANCH — it is 4 chars and
# not all-hex, so it never matches the sha pattern above; no special case
# needed, it just produces no occurrence for that heading.
#
# One namespace: a HEAD sha and a commits-list sha are the same kind of
# fact (a block's HEAD commonly reappears as the next block's commit-list
# entry, and very often as the FIRST entry of its OWN commit list — the
# digest format restates HEAD there), so dedupe pools both under one
# identity space rather than comparing them separately. That same-block
# restatement is not a dedupe signal though — see "self-match" below.
#
# Self-match suppression: when a duplicate and its survivor are the same
# sha in the same file AND the same block, that is one commit the digest
# format wrote twice (HEAD: line + its own first commits: entry), not two
# occurrences of anything — it is excluded from REDUNDANT and from DUP
# output. It does not affect GROUPS or CROSS-FILE, which are membership
# facts, not print facts.
#
# Prefix-collapse, not string equality, and NOT naively transitive: this
# repo's `core.abbrev` grew 8 -> 9 mid-corpus, so the same commit can appear
# at two lengths, and two shas are the same identity when they agree on the
# first min(len(a),len(b)) characters — but that relation is not transitive.
# `abcdef1` (7) is compatible with both `abcdef12` and `abcdef13` even
# though those two are genuinely different commits (a real 7-char abbrev
# collision) — chaining compatibility through the short one would merge
# them. So within each 7-char-prefix bucket (any pair that can legally
# collapse necessarily shares that prefix, making the bucket a correct,
# not approximate, speedup over all-pairs), every value that is a strict
# prefix of exactly ONE longer ("maximal") value in the bucket collapses
# into that value's group; a value compatible with TWO OR MORE mutually
# incompatible maximal values is ambiguous and is refused — it forms its
# own singleton group rather than guessing, because a false collapse here
# is a false "already archived" and a silently lost block.
#
# ponytail: POSIX sh + POSIX awk, no bashisms, no external deps.

set -u

usage() {
  echo "usage: archive-ledger.sh count <file>..." >&2
  echo "       archive-ledger.sh dedupe <file>...    (archive-first, candidate-last)" >&2
  exit 2
}

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift
[ "$#" -ge 1 ] || usage

for f in "$@"; do
  [ -f "$f" ] || { echo "archive-ledger: no such file: $f" >&2; exit 2; }
done

HEADING_RE='^## [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — '
SEP_RE='^---$'

do_count() {
  total=0
  nfiles=0
  mismatches=0
  for f in "$@"; do
    h=$(grep -cE "$HEADING_RE" -- "$f")
    s=$(grep -cE "$SEP_RE" -- "$f")
    printf '%d\t%s\n' "$h" "$f"
    if [ "$h" -ne "$s" ]; then
      echo "MISMATCH $f: headings=$h separators=$s" >&2
      mismatches=$((mismatches + 1))
    fi
    total=$((total + h))
    nfiles=$((nfiles + 1))
  done
  printf 'TOTAL %d blocks, %d files, %d mismatches\n' "$total" "$nfiles" "$mismatches"
  [ "$mismatches" -eq 0 ]
}

# Parses commits:/HEAD: occurrences out of the given files (in argument
# order — that order IS the survivor rule, see header), prefix-collapses
# them into identity groups without false transitivity, suppresses same-
# block self-matches, and reports every remaining redundant occurrence
# against the surviving (first-seen) one in its group, plus a per-block
# n-of-m already-elsewhere roll-up.
do_dedupe() {
  awk '
    function record(sha, file, block, kind,   k) {
      n++
      occ_sha[n] = sha
      occ_file[n] = file
      occ_block[n] = block
      occ_kind[n] = kind
      k = substr(sha, 1, 7)
      bcnt[k]++
      bidx[k, bcnt[k]] = n
      if (kind == "COMMIT") {
        fb = file SUBSEP block
        m_block[fb]++
        if (!(fb in block_seen)) { block_seen[fb] = 1; block_order[++block_seq] = fb }
      }
    }
    FNR == 1 { in_commits = 0; cur_block = "" }
    {
      line = $0
      if (line ~ /^## [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — /) {
        cur_block = line
        in_commits = 0
        if (match(line, /— HEAD: [0-9a-f]{7,40}$/)) {
          hstr = substr(line, RSTART, RLENGTH)
          if (match(hstr, /[0-9a-f]{7,40}$/)) {
            record(substr(hstr, RSTART, RLENGTH), FILENAME, cur_block, "HEAD")
          }
        }
        next
      }
      if (line == "commits:") { in_commits = 1; next }
      if (line == "uncommitted:" || line == "---" || line ~ /^memory: /) {
        in_commits = 0
        next
      }
      if (in_commits) {
        if (match(line, /^[0-9a-f]{7,40} /)) {
          record(substr(line, RSTART, RLENGTH - 1), FILENAME, cur_block, "COMMIT")
        } else {
          in_commits = 0
        }
        next
      }
    }
    # Same-length values compare by string equality (m==la==lb, trivial);
    # different lengths compare on the shorter one'"'"'s full length.
    function samesha(a, b,   la, lb, m) {
      la = length(a); lb = length(b)
      m = (la < lb) ? la : lb
      return substr(a, 1, m) == substr(b, 1, m)
    }
    # Assigns owner[v] for every distinct sha VALUE in one 7-char bucket.
    # A "maximal" value is not a strict prefix of any other distinct value
    # in the bucket — maximal values are pairwise incompatible by
    # construction (if two were compatible, the shorter would not be
    # maximal), so each is its own group anchor. A non-maximal value
    # collapses into the ONE maximal value it is a prefix of; if it is a
    # prefix of more than one (a real collision, see header), it is left
    # owning itself rather than guessed into either.
    function collapse_bucket(k,   i, j, v, w, nval, vals, seenval, ismax, matches, matched) {
      nval = 0
      for (i = 1; i <= bcnt[k]; i++) {
        v = occ_sha[bidx[k, i]]
        if (!(v in seenval)) { seenval[v] = 1; vals[++nval] = v }
      }
      for (i = 1; i <= nval; i++) ismax[vals[i]] = 1
      for (i = 1; i <= nval; i++) {
        for (j = 1; j <= nval; j++) {
          if (i == j) continue
          if (length(vals[i]) < length(vals[j]) && substr(vals[j], 1, length(vals[i])) == vals[i]) ismax[vals[i]] = 0
        }
      }
      for (i = 1; i <= nval; i++) {
        v = vals[i]
        if (ismax[v]) { owner[v] = v; continue }
        matches = 0; matched = ""
        for (j = 1; j <= nval; j++) {
          w = vals[j]
          if (!ismax[w]) continue
          if (samesha(v, w)) { matches++; matched = w }
        }
        owner[v] = (matches == 1) ? matched : v
      }
    }
    END {
      for (k in bcnt) collapse_bucket(k)
      # Group occurrences under their owner value, in first-seen
      # (ascending k / argument order) order — the first member recorded
      # for an owner is the survivor.
      for (k = 1; k <= n; k++) {
        r = owner[occ_sha[k]]
        gcnt[r]++
        gmem[r, gcnt[r]] = k
        fk = r SUBSEP occ_file[k]
        if (!(fk in gfile_seen)) { gfile_seen[fk] = 1; gfiles[r]++ }
        if (!(r in seen_root)) { seen_root[r] = 1; groups++ }
      }
      for (r in seen_root) {
        if (gcnt[r] > 1) {
          survivor = gmem[r, 1]
          for (mi = 2; mi <= gcnt[r]; mi++) {
            dup = gmem[r, mi]
            if (occ_file[dup] == occ_file[survivor] && occ_block[dup] == occ_block[survivor]) continue
            redundant++
            printf "DUP\t%s\t%s\t%s\tduplicates\t%s\t%s\t%s\n", \
              occ_sha[dup], occ_file[dup], occ_block[dup], \
              occ_sha[survivor], occ_file[survivor], occ_block[survivor]
            if (occ_kind[dup] == "COMMIT") n_block[occ_file[dup] SUBSEP occ_block[dup]]++
          }
        }
        if (gfiles[r] > 1) crossfile++
      }
      for (bi = 1; bi <= block_seq; bi++) {
        fb = block_order[bi]
        split(fb, parts, SUBSEP)
        printf "BLOCK\t%s\t%s\t%d/%d already-elsewhere\n", parts[1], parts[2], n_block[fb] + 0, m_block[fb]
      }
      printf "OCCURRENCES %d\n", n
      printf "GROUPS %d\n", groups
      printf "REDUNDANT %d\n", redundant + 0
      printf "CROSS-FILE %d\n", crossfile + 0
    }
  ' "$@"
}

case "$cmd" in
  count) do_count "$@" ;;
  dedupe) do_dedupe "$@" ;;
  *) usage ;;
esac
