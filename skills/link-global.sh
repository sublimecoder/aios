#!/bin/sh
# link-global.sh — expose the vault's portable skills to EVERY project by
# symlinking each skills/<name>/ into ~/.claude/skills/<name>. Idempotent.
#
# The vault stays canonical (real files live here, version-controlled, edits are
# live); ~/.claude/skills is just the global discovery surface Claude Code scans
# one level deep in any project. Re-run anytime (e.g. after adding a skill, or if
# an `npx skills` run ever prunes these first-party links).
SRC_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)   # <vault>/skills
CLAUDE_SKILLS="$HOME/.claude/skills"
mkdir -p "$CLAUDE_SKILLS"

n=0
for dir in "$SRC_DIR"/*/; do
  [ -f "${dir}SKILL.md" ] || continue            # only real skills
  name=$(basename "$dir")
  link="$CLAUDE_SKILLS/$name"
  target="${dir%/}"
  if [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then continue; fi
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "SKIP $name — a real file/dir already exists at $link (not overwriting)"
    continue
  fi
  ln -sfn "$target" "$link"
  echo "link $name -> $target"
  n=$((n + 1))
done
echo "linked/updated $n skill(s); vault skills now global in ~/.claude/skills"
