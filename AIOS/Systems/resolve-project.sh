#!/usr/bin/env bash
# The skills' entry point for a project's layer, slug, and config path.
#
# The manifest is PARSED in exactly one place — `aios_lookup` in hooks/lib.sh,
# which the Stop and SessionStart hooks also call. This script is the CLI face
# of that function, nothing more. It used to carry its own awk copy while three
# docs called it "the sole reader"; the copy then missed lib.sh's 2026-07-31
# worktree fix, so a session run from a linked worktree resolved UNKNOWN_REPO
# here while the hooks resolved it fine. One parser, one set of fixes.
#
# Usage: resolve-project.sh [dir]                     (defaults to $PWD)
#        resolve-project.sh --project <layer> <project>
#
# The second form is the REVERSE lookup, added 2026-08-16. The first maps a
# directory to a layer/project; an ingest holds the opposite — it knows
# a scope + a project name and has no dir — and step 1b-ship told runs to resolve
# the repo path through this script anyway. `resolve-project.sh <scope> <project>`
# read `work` as a DIRECTORY, so it printed `UNKNOWN_REPO=work` and exit 1, and
# every run fell back to grepping the manifest's 4th field by hand. Five times in
# six days. Both forms print the identical envelope, so a caller can use either.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="${AIOS_VAULT:-$HOME/code/aios}"
# shellcheck source=hooks/lib.sh
. "$HERE/hooks/lib.sh"
MANIFEST="$AIOS_MANIFEST"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 2
fi

if [ "${1:-}" = "--project" ]; then
  layer_arg="${2:-}"
  project_arg="${3:-}"
  if [ -z "$layer_arg" ] || [ -z "$project_arg" ]; then
    echo "ERROR: --project needs <layer> <project>" >&2
    exit 2
  fi
  if ! res="$(aios_lookup_project "$layer_arg" "$project_arg")"; then
    # Distinct from UNKNOWN_REPO on purpose: that one means "this directory is
    # not in the manifest", this one means "this layer/project pair is not".
    # Collapsing them is what sent five runs hunting a manifest bug that was
    # really a wrong argument.
    echo "UNKNOWN_PROJECT=$layer_arg/$project_arg"
    exit 1
  fi
  repo="$project_arg"
else
  dir="${1:-$PWD}"
  repo="$(basename "$dir")"
  if ! res="$(aios_lookup "$dir")"; then
    # Layer = manifest, not guess. Caller must ask.
    echo "UNKNOWN_REPO=$repo"
    exit 1
  fi
fi

layer="$(printf '%s' "$res" | awk '{print $1}')"
project="$(printf '%s' "$res" | awk '{print $2}')"
config="$VAULT/$layer/projects/$project/agents.md"
exists=0; [ -f "$config" ] && exists=1

# repo_path: the manifest's 4th field when the row carries one. A row not yet
# migrated prints no 4th field — fall back to the old implicit assumption
# (~/code/<repo-dir>) here, at the CLI edge, rather than inside aios_lookup:
# the parser reports only what the manifest actually says.
repo_path="$(printf '%s' "$res" | awk '{print $3}')"
[ -n "$repo_path" ] || repo_path="$HOME/code/$repo"
# A recorded path is stored `~/code/...` so the manifest is not pinned to one
# machine. The tilde arrives as DATA and the shell will not expand it, so this
# call is what makes a portable row work at all — without it the value reaches
# `git -C` verbatim and fails as "not a git repository" on every machine.
repo_path="$(aios_expand_home "$repo_path")"

printf 'LAYER=%s\nPROJECT=%s\nCONFIG=%s\nEXISTS=%s\nREPO_PATH=%s\n' \
  "$layer" "$project" "$config" "$exists" "$repo_path"
