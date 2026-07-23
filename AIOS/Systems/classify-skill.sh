#!/bin/sh
# Classify one skill file: what kind, who owns it, what it costs per turn.
# The ONLY place ownership is decided. skills-janitor calls this and never
# re-derives it — an audit that guesses ownership will eventually edit an
# upstream file that the next plugin update silently reverts.
#
# Usage: classify-skill.sh <path-to-SKILL.md-or-vault-note>
set -u

VAULT="${AIOS_VAULT:-$HOME/code/aios}"
# Canonicalise once: a trailing slash or relative AIOS_VAULT must resolve to
# the same absolute form used for the ownership comparison below.
VAULT=$(CDPATH= cd "$VAULT" 2>/dev/null && pwd -P) || { echo "ERROR: AIOS_VAULT does not exist: ${AIOS_VAULT:-$HOME/code/aios}" >&2; exit 1; }

path="${1:-}"
[ -n "$path" ] && [ -f "$path" ] || { echo "ERROR: not a readable file: $path" >&2; exit 1; }

# Resolve symlinks: a skill is where it really lives, not where it is linked.
# macOS readlink has no -f, so chase the leaf link manually (bounded, POSIX).
# Relative link targets are resolved against the link's own directory.
p="$path"
hops=0
while [ -L "$p" ]; do
  hops=$((hops + 1))
  if [ "$hops" -gt 40 ]; then
    echo "ERROR: too many symlink hops (possible cycle): $path" >&2
    exit 1
  fi
  link=$(readlink "$p") || { echo "ERROR: cannot read symlink: $p" >&2; exit 1; }
  case "$link" in
    /*) p="$link" ;;
    *) p="$(dirname "$p")/$link" ;;
  esac
done
# Canonicalise the directory chain once more now that the leaf is resolved.
dir=$(CDPATH= cd "$(dirname "$p")" && pwd -P) || exit 1
real="$dir/$(basename "$p")"

# Frontmatter body only (lines strictly between the first `---` and the next
# `---`); prints nothing if the file has no frontmatter fences. Used so
# invocation/tags matching never bleeds into the body or a fixed head window.
frontmatter() {
  awk '
    NR==1 { if ($0 == "---") { infm=1; next } else { exit } }
    infm && $0 == "---" { exit }
    infm { print }
  ' "$1"
}

case "$(basename "$real")" in
  SKILL.md) kind=portable ;;
  *) if frontmatter "$real" | grep -q 'tags: *\[ *aios *, *skill *\]'; then kind=vault-note; else kind=unknown; fi ;;
esac

case "$real" in
  "$VAULT"/*) ownership=vault ;;
  *) ownership=upstream ;;
esac

if [ "$kind" = portable ]; then
  if frontmatter "$real" | grep -qi '^disable-model-invocation: *true'; then
    invocation=user
  else
    invocation=model
  fi
else
  invocation=na
fi

# Only a model-invoked description is loaded every turn. Everything else is free.
if [ "$invocation" = model ]; then
  bytes=$(frontmatter "$real" | grep -i '^description:' | wc -c | tr -d ' ')
  desc_tokens=$((bytes / 4))
else
  desc_tokens=0
fi

printf 'KIND=%s\nOWNERSHIP=%s\nINVOCATION=%s\nDESC_TOKENS=%s\n' \
  "$kind" "$ownership" "$invocation" "$desc_tokens"
