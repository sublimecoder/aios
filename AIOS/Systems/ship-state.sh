#!/bin/sh
# ship-state.sh <repo-path> <ref>...
#
# Answers "did this land?" for one or more refs in a squash-merge-friendly
# repo, where local git alone cannot tell you: a squash merge rewrites the
# commit, so the feature-branch sha never appears in the default branch's
# history even after the PR ships. One line of output per ref, in order:
#   LANDED <evidence>
#   OPEN
#   UNKNOWN
#
# ponytail: POSIX sh, no bashisms.
#
# THE QUERY ORDER IS THE WHOLE POINT — every ingest run has improvised this
# differently by hand; this pins it:
#
#   1. Forge first. `gh pr list --search <sha>` finds PRs that ever carried
#      the commit, then `gh pr view <n> --json state,mergedAt,mergeCommit`
#      confirms each. A forge MERGED is the ONLY affirmative answer -> LANDED.
#      A forge-confirmed OPEN PR (found, not merged, not closed) is likewise
#      a real answer -> OPEN. Any other forge outcome (no PR found, closed
#      without merging, query failed) is NOT an answer — fall through.
#   2. Fallback, used whenever step 1 didn't produce a verdict (forge
#      unreachable, gh missing/unauthenticated, or reachable but silent):
#      squash-subject match — does the ref's commit SUBJECT line appear on
#      the default branch? `git log origin/<default> --oneline --grep=<subject>`.
#      A hit -> LANDED. ponytail: subject-text heuristic, not content-hashed;
#      upgrade to a trailer/Change-Id scheme if subject collisions ever bite.
#   3. Ancestry may only CONFIRM, never refute. `merge-base --is-ancestor`
#      can upgrade UNKNOWN -> LANDED (the ref's own sha, unsquashed, already
#      reached the default branch). A "no" here is DISCARDED, never recorded
#      as OPEN — in a squash-merge repo a negative ancestry result proves
#      nothing about whether the PR shipped under a different sha.
#   4. Nothing resolved it -> UNKNOWN.
#
# `gh` absent, unauthenticated, or otherwise unreachable -> skip straight to
# step 2 and the worst this ref can report is UNKNOWN. This script never
# prints OPEN on the strength of a failed query — OPEN means the forge
# positively confirmed an open PR, nothing less.

set -u

usage() { echo "usage: ship-state.sh <repo-path> <ref>..." >&2; exit 2; }

REPO="${1:-}"
[ -n "$REPO" ] || usage
shift
[ "$#" -ge 1 ] || usage

# The default branch, resolved once for every ref. origin/HEAD is the local
# record of what the remote considers default; not every clone has it set, so
# fall back to a plain origin/main or origin/master, and to the checked-out
# branch itself as a last resort for a repo with no configured remote at all.
default_ref() {
  b=$(git -C "$REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$b" ]; then printf '%s\n' "$b"; return 0; fi
  for cand in origin/main origin/master; do
    if git -C "$REPO" rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null
}
DEFAULT="$(default_ref)"

# gh reachable AND authenticated. Anything less (not installed, not logged
# in, no network) means the forge step is skipped entirely — never treated as
# a negative answer.
GH_READY=0
if command -v gh >/dev/null 2>&1 && (cd "$REPO" 2>/dev/null && gh auth status >/dev/null 2>&1); then
  GH_READY=1
fi

for ref in "$@"; do
  sha=$(git -C "$REPO" rev-parse --verify --quiet "${ref}^{commit}" 2>/dev/null)
  state="UNKNOWN"
  evidence=""

  # --- 1. forge first ---------------------------------------------------
  if [ "$GH_READY" -eq 1 ] && [ -n "$sha" ]; then
    # ponytail: --search is full-text (title/body/comments), not sha-scoped —
    # a PR that merely MENTIONS this sha can match, producing a false OPEN or
    # LANDED. Brief-prescribed query, so kept; narrow to the commit-list API
    # (`gh api .../commits/<sha>/pulls`) if a false match is ever observed.
    # STATUS, not stderr, is what tells the two silences apart — added 2026-08-16.
    # `2>/dev/null` was never the problem: `$?` survives it, so exit 0 + empty output
    # (the forge answered, no PR references this sha) and a nonzero exit (the query
    # FAILED — throttle, network, expired token) were always distinguishable for free.
    # They both printed a bare UNKNOWN, and on 2026-08-12 that turned a rate-limit
    # into ⚠️ BRANCH STATE flags on branches that had in fact merged.
    # Diagnostic goes to STDERR and stdout keeps its three shapes exactly, because
    # LANDED/OPEN/UNKNOWN is a contract several ingest steps branch on; widening it
    # needs the caller taught in the same pass, which is a separate decision.
    # This does not stop a spurious flag. It makes one diagnosable — the transcript
    # now carries the reason, which is what nobody could find on 2026-08-12.
    # ONE call. An earlier draft of this ran the query twice to capture stderr
    # separately — which would have doubled the forge traffic in a fix whose whole
    # subject is rate limiting. stderr goes to a temp file instead.
    # Keyed on the EXIT STATUS, not on stderr being non-empty: gh writes advisory
    # notices to stderr on successful calls too, so presence-of-stderr would cry wolf.
    prerr=$(mktemp)
    prnums=$(cd "$REPO" && gh pr list --search "$sha" --state all --json number --jq '.[].number' 2>"$prerr")
    if [ $? -ne 0 ]; then
      echo "ship-state: forge query FAILED for $ref — the UNKNOWN below means 'not asked', not 'not shipped': $(head -1 "$prerr" | cut -c1-160)" >&2
    fi
    rm -f "$prerr"
    if [ -n "$prnums" ]; then
      open_pr=""
      for n in $prnums; do
        # One view call carries everything both branches below need — a
        # second call for OPEN re-fetching state already read here was N
        # wasted requests for nothing new.
        view=$(cd "$REPO" && gh pr view "$n" --json state,mergedAt,mergeCommit \
                 --jq '[.state, (.mergedAt // ""), (.mergeCommit.oid // "")] | @tsv' 2>/dev/null)
        [ -n "$view" ] || continue
        pstate=$(printf '%s' "$view" | cut -f1)
        mergedat=$(printf '%s' "$view" | cut -f2)
        mergesha=$(printf '%s' "$view" | cut -f3)
        if [ "$pstate" = "MERGED" ]; then
          state="LANDED"
          evidence="PR #$n merged"
          [ -n "$mergedat" ] && evidence="$evidence $mergedat"
          [ -n "$mergesha" ] && evidence="$evidence ($mergesha)"
          break
        fi
        [ "$pstate" = "OPEN" ] && [ -z "$open_pr" ] && open_pr="$n"
      done
      # A MERGED PR anywhere in the list wins; only when none exists does a
      # confirmed-OPEN one settle the answer.
      [ "$state" = "UNKNOWN" ] && [ -n "$open_pr" ] && state="OPEN"
    fi
  fi

  # --- 2. fallback: squash-subject match on the default branch ----------
  # THE REF THIS GREPS IS LOCAL, AND IT IS STALE IN EXACTLY THE CASE THE FALLBACK
  # EXISTS FOR. $DEFAULT is a local ref (origin/<default>), which only moves when
  # someone fetches — and a branch merged AT THE FORGE never advances the local
  # clone at all. So the fallback is least reliable precisely when it is most
  # needed, and it fails CLOSED: no match is indistinguishable from not-merged,
  # and step 1b-ship turns that UNKNOWN into a ⚠️ BRANCH STATE flag.
  #
  # Measured 2026-09-13: `ship-state.sh <creator repo> a2bd507` returned a bare
  # UNKNOWN, then returned `LANDED PR #14 merged` after an unrelated `git fetch`
  # in the same session. The forge call had SUCCEEDED both times (a failed one
  # prints the "forge query FAILED" warning above, and it never appeared) — so the
  # first UNKNOWN came from here: pre-fetch, origin/main sat at or behind 77d4ade,
  # and 77d4ade does not contain the squash e7befe9, so no grep could have matched.
  # A run trusting that answer flags a branch merged fourteen hours earlier.
  #
  # Fetch is scoped to this fallback rather than run at entry: the forge path needs
  # no local refs, and an unattended job should not pay a network round-trip on the
  # common case where the forge already answered. Failure is deliberately ignored —
  # a stale ref is what we already had, so this can only improve the grep.
  # ponytail: fixed 20s timeout, no retry. `timeout` is GNU/coreutils here and on
  # macOS via the same PATH the callers use; if a slow remote ever matters, make it
  # an env knob rather than a loop.
  if [ "$state" = "UNKNOWN" ] && [ -n "$sha" ] && [ -n "$DEFAULT" ]; then
    # --no-tags --quiet: refs are all this needs, and a tag-heavy remote is pure cost.
    timeout 20 git -C "$REPO" fetch --quiet --no-tags origin 2>/dev/null || \
      echo "ship-state: fetch before subject-match failed or timed out for $ref — the fallback below greps a possibly-stale $DEFAULT" >&2
    subject=$(git -C "$REPO" log -1 --format=%s "$sha" 2>/dev/null)
    if [ -n "$subject" ]; then
      match=$(git -C "$REPO" log "$DEFAULT" --oneline -F --grep="$subject" 2>/dev/null | head -1)
      if [ -n "$match" ]; then
        state="LANDED"
        evidence="squash-subject match on $DEFAULT: $match"
      fi
    fi
  fi

  # --- 3. ancestry: confirm only, never refute ---------------------------
  if [ "$state" = "UNKNOWN" ] && [ -n "$sha" ] && [ -n "$DEFAULT" ]; then
    if git -C "$REPO" merge-base --is-ancestor "$sha" "$DEFAULT" 2>/dev/null; then
      state="LANDED"
      evidence="ancestor of $DEFAULT"
    fi
    # a "no" from merge-base is discarded here on purpose — it proves nothing
    # in a squash-merge repo, so it must never turn into OPEN.
  fi

  case "$state" in
    LANDED) echo "LANDED $evidence" ;;
    OPEN)   echo "OPEN" ;;
    *)      echo "UNKNOWN" ;;
  esac
done
