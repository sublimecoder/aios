#!/bin/sh
# AIOS SessionStart hook — load this repo's layer context from the vault.
# Pure read. Zero write. Output becomes the session's hot context.
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

REPO="${CLAUDE_PROJECT_DIR:-$PWD}"
res=$(aios_lookup "$REPO") || exit 0
LAYER=$(echo "$res" | awk '{print $1}')
PROJECT=$(echo "$res" | awk '{print $2}')

ME="$AIOS_VAULT/AIOS/me-$LAYER.md"
NOTE="$AIOS_VAULT/AIOS/Projects/$LAYER/$PROJECT.md"

echo "=== AIOS brain ($LAYER/$PROJECT) — auto-loaded from vault ==="
if [ -f "$ME" ]; then
  echo "--- me-$LAYER (durable) ---"
  SECTION=$(awk '/^##[[:space:]]+Durable/{f=1; next} /^##/{f=0} f' "$ME")
  [ -z "$SECTION" ] && SECTION=$(head -40 "$ME")
  echo "$SECTION"
fi
if [ -f "$NOTE" ]; then
  echo "--- AIOS/Projects/$LAYER/$PROJECT.md ---"
  cat "$NOTE"
fi
echo "To log a durable fact now, follow $AIOS_VAULT/AIOS/Skills/aios-log.md (or /aios-log)."
echo "Identity wall: this is the $LAYER layer — never mix in other layers."
