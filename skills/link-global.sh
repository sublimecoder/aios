#!/bin/sh
# link-global.sh — expose the vault's portable skills to EVERY project by
# symlinking each skills/<name>/ into the destinations in AIOS_LINK_DESTS
# (default: ~/.claude/skills and ~/.agents/skills, the cross-agent "Agent
# Skills" standard). Idempotent.
#
# The vault stays canonical (real files live here, version-controlled, edits are
# live); the destinations are just the global discovery surface Claude Code (and
# other Agent-Skills-compatible tools) scan one level deep in any project.
# Re-run anytime (e.g. after adding a skill, or if an `npx skills` run ever
# prunes these first-party links).
#
# Usage: link-global.sh [--dry-run] [--adopt]
#
#   --adopt   replace a destination entry that is a REAL DIRECTORY whose content
#             is byte-identical to the vault's copy. Off by default; see the
#             COLLISION handling below for why it is opt-in and narrow.
SRC_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd -P)   # .../<vault>/skills, physical
VAULT_DIR=$(dirname "$SRC_DIR")                     # .../<vault>, physical

# ^ `-P` (physical) so this matches the physical resolution done below for the
# vault-recursion guard — otherwise a symlinked path component (e.g. macOS
# /var -> /private/var under $TMPDIR) could make the two disagree.

# `-` and not `:-`: an explicitly-empty AIOS_LINK_DESTS means "no destinations",
# never "silently fall back to the user's real skill directories". Three
# separate agents reached production through that `:-` fallback while
# believing they were sandboxed.
#
# ~/.jcode/skills IS A FIRST-CLASS DESTINATION, not an afterthought. It was
# missing while jcode was the harness in daily use, and jcode's own installer had
# populated it with COPIES of 21 vault skills. A copy defeats the property named
# at the top of this file — the vault stays canonical, edits are live — because a
# vault edit never reaches the tool actually being used. All 21 were byte-identical
# on 2026-08-11, so nothing had diverged YET; that is a snapshot, not a guarantee,
# and it is exactly the window in which this is cheap to fix.
DESTS="${AIOS_LINK_DESTS-$HOME/.claude/skills:$HOME/.agents/skills:$HOME/.jcode/skills}"
DRY=0
ADOPT=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --adopt)   ADOPT=1 ;;
  esac
done

if [ -z "$DESTS" ]; then
  echo "ERROR: AIOS_LINK_DESTS is set but empty — refusing to fall back to the real skill directories" >&2
  exit 1
fi

# dirs_identical <a> <b> — true only when the two trees have exactly the same
# file names AND every pair of files is byte-identical.
#
# This is the entire safety argument for the `rm -rf` in --adopt's branch, so it
# is written to fail CLOSED at every step: any diff output, any read error, any
# name present on one side only, and it returns false. `diff -r` covers all of
# that in one call and reports missing/extra entries as differences, which a
# per-file loop over one side's names would silently miss in the other direction.
#
# Deliberately NOT --brief-only-on-SKILL.md: a skill is its whole directory
# (scripts/, references/, assets), and adopting on a matching SKILL.md while a
# helper script differed would delete the difference. Trees, not files.
dirs_identical() {
  [ -d "$1" ] && [ -d "$2" ] || return 1
  diff -r "$1" "$2" >/dev/null 2>&1
}

n=0
# POSIX sh has no bash arrays / `read -a`; split the colon-separated DESTS by
# temporarily narrowing IFS to ':' and disabling globbing for the split only.
# Word-splitting of $DESTS happens once, right here, when the `for` starts —
# so IFS/glob are restored immediately inside the loop body and stay normal
# for everything else (including the "$SRC_DIR"/*/ glob below).
OLD_IFS=$IFS
IFS=:
set -f
for DEST in $DESTS; do
IFS=$OLD_IFS
set +f
  [ -n "$DEST" ] || continue

  # Never write symlinks back into our own tree. Resolve a symlinked
  # destination root physically and skip if it lands inside the vault.
  if [ -L "$DEST" ]; then
    real=$(cd "$DEST" 2>/dev/null && pwd -P)
    case "$real" in
      "$VAULT_DIR"*)
        echo "SKIP $DEST (symlink resolving into the vault)"
        continue
        ;;
    esac
  fi

  if [ "$DRY" -eq 0 ]; then
    mkdir -p "$DEST" || { echo "ERROR: cannot create $DEST" >&2; exit 1; }
  fi

  for dir in "$SRC_DIR"/*/; do
    [ -f "${dir}SKILL.md" ] || continue            # only real skills
    name=$(basename "$dir")
    target="${dir%/}"
    link="$DEST/$name"

    if [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then
      continue                                      # already correct
    fi
    # COLLISION: something real is already sitting on the name.
    #
    # Refusing is the default and stays the default — clobbering a directory the
    # vault did not create is unrecoverable, and this script has no way to know
    # whether a stranger's skill of the same name matters to someone.
    #
    # --adopt narrows that to the one case that is provably safe: the directory
    # is byte-identical to the vault's copy, so replacing it with a symlink to
    # the vault changes NOTHING about what any tool reads today, and makes every
    # future vault edit reach it. That is precisely the state jcode's installer
    # left behind for 21 skills. Anything that differs is still refused, loudly,
    # because a difference is either local work or drift and both need a human.
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      if [ "$ADOPT" -eq 1 ] && [ -d "$link" ] && dirs_identical "$target" "$link"; then
        if [ "$DRY" -eq 1 ]; then
          echo "DRY  ADOPT $link (identical copy) -> $target"
          continue
        fi
        rm -rf "$link"
        ln -s "$target" "$link" && echo "ADOPT $link -> $target (was an identical copy)"
        n=$((n + 1))
      elif [ -d "$link" ] && ! dirs_identical "$target" "$link"; then
        echo "COLLISION $link is a real directory whose content DIFFERS from the vault — refusing (inspect it; --adopt only replaces identical copies)"
      else
        echo "COLLISION $link already exists and is not a symlink — refusing to replace it$([ "$ADOPT" -eq 1 ] || echo ' (identical directory copies can be adopted with --adopt)')"
      fi
      continue
    fi
    if [ -L "$link" ]; then
      echo "COLLISION $link is a symlink we did not create — refusing"
      continue
    fi

    if [ "$DRY" -eq 1 ]; then
      echo "DRY  $link -> $target"
    else
      ln -s "$target" "$link" && echo "LINK $link -> $target"
      n=$((n + 1))
    fi
  done
done
echo "linked/updated $n skill(s); vault skills now global"
