#!/bin/sh
# AIOS hook shared lib — resolve layer/project from a repo dir via the manifest.
# ponytail: POSIX sh, no bashisms; macOS /bin/sh is fine.
# Override AIOS_VAULT if your vault lives elsewhere (set it in your shell rc).
AIOS_VAULT="${AIOS_VAULT:-$HOME/code/aios}"
AIOS_MANIFEST="$AIOS_VAULT/AIOS/Systems/repo-layers.tsv"

# aios_lookup <repo-path>: prints "LAYER PROJECT" and returns 0 on a manifest
# hit; returns 1 (no output) if the repo is not listed. Layer is NEVER guessed.
aios_lookup() {
  base=$(basename "$1")
  [ -f "$AIOS_MANIFEST" ] || return 1
  awk -v r="$base" '
    /^[[:space:]]*#/ { next }
    NF < 3           { next }
    $1 == r          { print $2, $3; found=1; exit }
    END              { if (!found) exit 1 }
  ' "$AIOS_MANIFEST"
}
