#!/usr/bin/env bash
# PreToolUse guard for Edit|Write. Enforces three CLAUDE.md contracts mechanically:
#   A. <scope>/sources/ is immutable (read-only curated input) — block ALL writes.
#   B. <scope>/notes/ holds your own hand-written notes — block AI-CREATED new
#      notes there (AI notes belong in <scope>/projects|content/ or AIOS/History/).
#   C. Cross-scope leak tripwire — block the most flagrant literal leaks at write
#      time, driven entirely by AIOS/Systems/layers.tsv. This is a cheap grep, not
#      a substitute for layer-leak-auditor's nuanced/inferred pass: it only catches
#      unambiguous, high-signal tokens to keep false positives near zero. Scoped to
#      scope dirs only (column 3 of layers.tsv); AIOS/, archive/, +/ are
#      meta/scaffolding that legitimately name every scope by design.
# Blocks by exiting 2 with a message on stderr (fed back to the agent).
# ponytail: deny-list, not allowlist — guards the named harms only, so legit
# drafts never false-positive. Add zones if a leak shows one.
#
# Requires: jq. Config: AIOS/Systems/layers.tsv (see that file's header).

set -uo pipefail

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

# No path (or a tool we don't guard) → allow.
[ -z "$path" ] && exit 0

# Normalize to repo-relative (strip the vault root prefix if present).
repo="${CLAUDE_PROJECT_DIR:-$PWD}"
rel="${path#"$repo"/}"

# Rule A: <scope>/sources/ is immutable.
case "$rel" in
  */sources/*)
    echo "BLOCKED: sources/ is immutable (read-only curated input per CLAUDE.md). Never edit or delete it — wiki notes summarize it and point back via the 'sources' frontmatter field." >&2
    exit 2
    ;;
esac

# Rule B: don't create NEW AI notes inside <scope>/notes/ (only fires on Write to
# a path that doesn't exist yet; editing an existing note is left to judgment).
if [ "$tool" = "Write" ] && [ ! -e "$path" ]; then
  case "$rel" in
    */notes/*)
      echo "BLOCKED: '$rel' is a NEW note in a notes/ dir (your personal, timeless notes). AI-generated notes default to the scope's projects/ or content/ dirs, or AIOS/History/ — propose edits to personal notes, don't create them there." >&2
      exit 2
      ;;
  esac
fi

# Rule C: cross-layer leak tripwire, driven by layers.tsv.
MANIFEST="$repo/AIOS/Systems/layers.tsv"
[ -f "$MANIFEST" ] || exit 0

# Read the manifest into parallel arrays. Skip comments, blanks, short rows.
layers=(); globs=(); tokens=(); allows=()
while IFS=$'\t' read -r l lbl g t a; do
  case "$l" in ''|'#'*) continue;; esac
  [ -z "${g:-}" ] && continue
  layers+=("$l"); globs+=("$g"); tokens+=("${t:--}"); allows+=("${a:--}")
done < "$MANIFEST"

[ "${#layers[@]}" -eq 0 ] && exit 0

# Which layer does this path belong to? First glob match wins.
own_layer=""; own_idx=-1
for i in "${!layers[@]}"; do
  IFS='|' read -ra pats <<< "${globs[$i]}"
  for p in "${pats[@]}"; do
    # shellcheck disable=SC2053  # intentional glob match, not string equality
    if [[ "$rel" == $p ]]; then own_layer="${layers[$i]}"; own_idx=$i; break 2; fi
  done
done

# Path is scaffolding or unclaimed → not layer content, allow.
[ -z "$own_layer" ] && exit 0

new_content=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty')
[ -z "$new_content" ] && exit 0

# Layers whose tokens are tolerated inside this one.
allowed="|${allows[$own_idx]}|"

for i in "${!layers[@]}"; do
  [ "$i" -eq "$own_idx" ] && continue
  other="${layers[$i]}"
  [ "${tokens[$i]}" = "-" ] && continue                 # layer declares no tokens
  [[ "$allowed" == *"|$other|"* ]] && continue          # explicitly tolerated

  if printf '%s' "$new_content" | grep -qiE "${tokens[$i]}"; then
    echo "BLOCKED: '$rel' is ${own_layer}-layer content but names the ${other} layer. Those layers are walled off from each other per CLAUDE.md and AIOS/Systems/layers.tsv. If this is a legitimate meta-mention (e.g. documenting the wall itself), write it under AIOS/ instead — that is scaffolding and is not guarded." >&2
    exit 2
  fi
done

exit 0
