#!/usr/bin/env bash
# Self-check for resolve-project.sh. Run: bash AIOS/Systems/test-resolve-project.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RESOLVE="$HERE/resolve-project.sh"
fails=0

# HERMETIC. The reverse-lookup assertions below name a specific scope/project
# pair, so reading the REAL repo-layers.tsv would make this suite pass or fail on
# whatever repos happen to be wired on this machine — green on the author's box,
# red on a fresh clone, and silent about the script either way. The fixture vault
# carries its own manifest; the real one is still width-checked further down,
# because THAT check is about the live file being well-formed.
VAULT=$(mktemp -d)
trap 'rm -rf "$VAULT"' EXIT
mkdir -p "$VAULT/AIOS/Systems" "$VAULT/work/projects/DemoApi"
MANIFEST="$VAULT/AIOS/Systems/repo-layers.tsv"
{
  printf '# repo\tlayer\tproject\trepo-path\tflags\n'
  printf 'DemoApi\twork\tDemoApi\t~/code/DemoApi\tlocal-only\n'
  printf 'other-repo\twork\tOther\t~/code/other-repo\n'
} > "$MANIFEST"
: > "$VAULT/work/projects/DemoApi/agents.md"

# The LIVE manifest still gets its shape checked — it is the one every real
# lookup reads, and a malformed row there breaks the wire for every repo.
LIVE_MANIFEST="$HERE/repo-layers.tsv"

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: expected [$2] got [$3]"; fails=$((fails+1)); fi
}
# check_openable: pins the resolved path's USABILITY, not its shape — a
# tilde stored as literal text (`~/code/x`) round-trips byte-for-byte through
# the manifest -> aios_lookup -> resolve-project.sh chain and would pass
# `check` above even though `git -C '~/code/x'` fails (the shell only expands
# `~` in unquoted words, never in a quoted variable). Only an actual `git -C`
# open proves the value is real.
check_openable() { # name path
  # THREE outcomes, not two. The vault runs on two machines off one branch and
  # neither has every repo cloned, so an ABSENT directory is not a defect --
  # same ruling aios-check.sh already makes for this manifest and for a plist
  # with no installed twin. What still fails is a directory that EXISTS and is
  # not a git repo, which is what a wrong or stale recorded path looks like.
  if [ ! -d "$2" ]; then
    echo "skip - $1: not cloned on this machine"
  elif git -C "$2" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ok   - $1"
  else
    echo "FAIL - $1: '$2' exists but git cannot open it"; fails=$((fails+1))
  fi
}

# 1. Manifest is real TSV: every non-comment row has 3, 4 or 5 tab-separated
# fields — the 4th (repo-path) column is an in-progress migration and the 5th
# (flags) is optional per-row, so this is a WIDTH RANGE, not a fixed count.
# Widened for the 5th column on 2026-08-16 (register row 80, `local-only`); the
# clause below is why that column cannot be read positionally by a plain `read`.
bad="$(awk -F'\t' '$0!~/^#/ && NF>0 && NF<3 && NF>5 {c++} END{print c+0}' "$LIVE_MANIFEST")"
check "manifest rows are 3-to-5 tab-separated fields" "0" "$bad"

# 2. Every non-comment row resolves. A trailing 4th field (repo-path) must
# not leak into `project` — `read` assigns unclaimed trailing words to the
# LAST named variable, so it needs a slot of its own to keep `project` clean.
# The 5th field (flags) needs one for the SAME reason, and did not have one:
# adding `local-only` on 2026-08-16 made `repo_path` read
# `~/code/DemoApi<TAB>local-only` and this loop fail. Every
# new column costs a slot here — that is the standing cost of a positional read.
while IFS=$'\t' read -r repo layer project repo_path flags; do
  case "$repo" in ''|'#'*) continue;; esac
  # Column 4 is stored `~/code/...`; resolve-project.sh expands it, so the
  # expected value has to be expanded here too or every row mismatches.
  case "$repo_path" in "~/"*) repo_path="$HOME/${repo_path#\~/}" ;; esac
  out="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" "/tmp/$repo" 2>/dev/null)"
  got_layer="$(printf '%s\n' "$out" | sed -n 's/^LAYER=//p')"
  got_proj="$(printf '%s\n' "$out" | sed -n 's/^PROJECT=//p')"
  got_path="$(printf '%s\n' "$out" | sed -n 's/^REPO_PATH=//p')"
  check "resolve $repo layer" "$layer" "$got_layer"
  check "resolve $repo project" "$project" "$got_proj"
  if [ -n "$repo_path" ]; then
    check "resolve $repo repo-path" "$repo_path" "$got_path"
    check_openable "resolve $repo repo-path is git-openable" "$got_path"
  fi
done < "$MANIFEST"

# 2b. REVERSE lookup (--project <layer> <project>), added 2026-08-16 for the
# after-action row that fired FIVE times in six days: an ingest holds a
# layer/project pair and no directory, and the forward form read `work` as a
# directory name and returned UNKNOWN_REPO. Both forms must agree exactly —
# a reverse lookup that disagreed with the forward one would be worse than none.
while IFS=$'\t' read -r repo layer project repo_path flags; do
  case "$repo" in ''|'#'*) continue;; esac
  fwd="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" "/tmp/$repo" 2>/dev/null)"
  rev="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" --project "$layer" "$project" 2>/dev/null)"
  check "reverse $layer/$project agrees with forward" "$fwd" "$rev"
done < "$MANIFEST"

# An unknown pair is its OWN failure mode, distinct from UNKNOWN_REPO: collapsing
# the two is what sent five runs hunting a manifest bug that was a wrong argument.
out="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" --project work NoSuchProject 2>/dev/null)"; rc=$?
check "reverse unknown pair exit code" "1" "$rc"
check "reverse unknown pair names the pair" "UNKNOWN_PROJECT=work/NoSuchProject" "$out"

# The exact call the ingest skill makes. This is the regression that matters: the
# old script answered `UNKNOWN_REPO=work` + exit 1 for precisely this input.
out="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" --project work DemoApi 2>/dev/null)"; rc=$?
check "the ingest's own call exits 0" "0" "$rc"
check "the ingest's own call yields a repo path" \
  "REPO_PATH=$HOME/code/DemoApi" \
  "$(printf '%s\n' "$out" | grep '^REPO_PATH=')"

# A flagged row (5th column) must not leak its flag into REPO_PATH — the same
# trailing-field hazard that broke this file's own loop above.
check "a flags column does not leak into REPO_PATH" \
  "REPO_PATH=$HOME/code/DemoApi" \
  "$(AIOS_VAULT="$VAULT" bash "$RESOLVE" --project work DemoApi 2>/dev/null | grep '^REPO_PATH=')"

# Missing arguments are a usage error (exit 2), not a lookup miss (exit 1).
AIOS_VAULT="$VAULT" bash "$RESOLVE" --project work >/dev/null 2>&1; rc=$?
check "reverse with a missing argument is a usage error" "2" "$rc"

# 3. Unlisted repo exits 1 and names itself.
out="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" /tmp/definitely-not-a-repo 2>/dev/null)"; rc=$?
check "unlisted exit code" "1" "$rc"
check "unlisted names repo" "UNKNOWN_REPO=definitely-not-a-repo" "$out"

# 4. CONFIG path is layer-partitioned (the wall, enforced by path).
out="$(AIOS_VAULT="$VAULT" bash "$RESOLVE" /tmp/DemoApi 2>/dev/null)"
cfg="$(printf '%s\n' "$out" | sed -n 's/^CONFIG=//p')"
check "work config path" "$VAULT/work/projects/DemoApi/agents.md" "$cfg"

echo "---"; [ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails FAILED"; exit 1; }
