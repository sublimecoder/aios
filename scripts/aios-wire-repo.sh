#!/usr/bin/env bash
# aios-wire-repo.sh — connect a code repo to the AIOS vault.
#
#   scripts/aios-wire-repo.sh <repo-path> <scope> [project-slug]
#   scripts/aios-wire-repo.sh --check <repo-path>
#
# Options:
#   --no-claude-md   skip writing CLAUDE.local.md
#
# Does exactly three things, all idempotent:
#   1. Adds a row to the vault's AIOS/Systems/repo-layers.tsv (a real TAB).
#   2. Merges two hooks into the REPO's .claude/settings.json:
#        SessionStart -> aios-context.sh   (loads that project's brain)
#        Stop         -> aios-digest.sh    (queues a session digest)
#   3. Writes CLAUDE.local.md in the repo — a durable pointer at the vault, for
#      the contexts where the SessionStart hook does not run (subagents, claude -p,
#      other editors). Never overwrites an existing one. Ensures it is git-ignored.
#
# This installer is the ONLY thing in AIOS that writes to a code repo. The hooks
# it installs write only to the vault, never back to the repo.
#
# Requires: jq (same dependency as the write guard).
set -uo pipefail

VAULT="${AIOS_VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="$VAULT/AIOS/Systems/repo-layers.tsv"
LAYERS="$VAULT/AIOS/Systems/layers.tsv"
HOOKS="$VAULT/AIOS/Systems/hooks"
TMPL="$VAULT/AIOS/Systems/templates/CLAUDE.local.md.tmpl"

die() { echo "error: $*" >&2; exit 1; }

# Strip flags out of the positional args.
WRITE_CLAUDE_MD=1
args=()
for a in "$@"; do
  case "$a" in
    --no-claude-md) WRITE_CLAUDE_MD=0 ;;
    *) args+=("$a") ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"

command -v jq >/dev/null || die "jq is required (brew install jq)"
[ -f "$MANIFEST" ] || die "no manifest at $MANIFEST — is AIOS_VAULT right? (got: $VAULT)"
[ -f "$LAYERS" ]   || die "no layers.tsv at $LAYERS"

# ---------------------------------------------------------------- --check mode
if [ "${1:-}" = "--check" ]; then
  repo=$(cd "${2:?usage: --check <repo-path>}" && pwd) || die "no such repo"
  base=$(basename "$repo")
  echo "repo:     $repo"
  row=$(awk -F'\t' -v r="$base" '!/^#/ && $1==r {print; exit}' "$MANIFEST")
  if [ -n "$row" ]; then
    echo "manifest: $row" | tr '\t' ' '
  else
    echo "manifest: MISSING — '$base' is not in repo-layers.tsv (hooks will silently no-op)"
  fi
  s="$repo/.claude/settings.json"
  if [ -f "$s" ]; then
    jq -e --arg c "$HOOKS/aios-context.sh" '[.hooks.SessionStart[]?.hooks[]?.command] | index($c)' "$s" >/dev/null \
      && echo "context:  wired" || echo "context:  MISSING"
    jq -e --arg d "$HOOKS/aios-digest.sh" '[.hooks.Stop[]?.hooks[]?.command] | index($d)' "$s" >/dev/null \
      && echo "digest:   wired" || echo "digest:   MISSING"
  else
    echo "settings: MISSING ($s)"
  fi
  if [ -f "$repo/CLAUDE.local.md" ]; then
    if git -C "$repo" check-ignore -q CLAUDE.local.md 2>/dev/null; then
      echo "local-md: present, git-ignored"
    else
      echo "local-md: present but NOT git-ignored — it will be committed"
    fi
  else
    echo "local-md: MISSING"
  fi
  exit 0
fi

# ------------------------------------------------------------------ wire mode
REPO_IN="${1:?usage: aios-wire-repo.sh <repo-path> <scope> [project-slug]}"
SCOPE="${2:?usage: aios-wire-repo.sh <repo-path> <scope> [project-slug]}"

REPO=$(cd "$REPO_IN" 2>/dev/null && pwd) || die "no such directory: $REPO_IN"
BASE=$(basename "$REPO")
PROJECT="${3:-$BASE}"

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "$REPO is not a git repo (the digest hook needs git)"

# Scope must already exist. Never invent one — that's the whole point of the manifest.
awk -F'\t' -v s="$SCOPE" '!/^#/ && NF>=3 && $1==s {found=1} END{exit !found}' "$LAYERS" \
  || die "scope '$SCOPE' is not in $LAYERS. Add it there first (and create AIOS/me-$SCOPE.md, Sources/$SCOPE/, AIOS/Projects/$SCOPE/)."

for h in aios-context.sh aios-digest.sh; do
  [ -x "$HOOKS/$h" ] || die "$HOOKS/$h missing or not executable (chmod +x it)"
done

# 1. Manifest row -------------------------------------------------------------
existing=$(awk -F'\t' -v r="$BASE" '!/^#/ && $1==r {print $2"\t"$3; exit}' "$MANIFEST")
if [ -n "$existing" ]; then
  want=$(printf '%s\t%s' "$SCOPE" "$PROJECT")
  if [ "$existing" = "$want" ]; then
    echo "manifest: '$BASE' already mapped to $SCOPE/$PROJECT — unchanged"
  else
    die "'$BASE' is already mapped to $(printf '%s' "$existing" | tr '\t' '/') in $MANIFEST. Edit it by hand rather than adding a second row — the lookup takes the first match and a stale row would win silently."
  fi
else
  printf '%s\t%s\t%s\n' "$BASE" "$SCOPE" "$PROJECT" >> "$MANIFEST"
  echo "manifest: added  $BASE -> $SCOPE/$PROJECT"
fi

# 2. Repo settings.json -------------------------------------------------------
SETTINGS="$REPO/.claude/settings.json"
mkdir -p "$REPO/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON — fix it before wiring"

TMP=$(mktemp)
jq --arg ctx "$HOOKS/aios-context.sh" --arg dig "$HOOKS/aios-digest.sh" '
  .hooks //= {}
  | .hooks.SessionStart //= []
  | .hooks.Stop //= []
  | (if ([.hooks.SessionStart[]?.hooks[]?.command] | index($ctx)) then .
     else .hooks.SessionStart += [{matcher:"startup|resume",
                                   hooks:[{type:"command", command:$ctx}]}] end)
  | (if ([.hooks.Stop[]?.hooks[]?.command] | index($dig)) then .
     else .hooks.Stop += [{hooks:[{type:"command", command:$dig}]}] end)
' "$SETTINGS" > "$TMP" || { rm -f "$TMP"; die "jq failed on $SETTINGS"; }

if cmp -s "$TMP" "$SETTINGS"; then
  echo "settings: already wired — unchanged"
  rm -f "$TMP"
else
  mv "$TMP" "$SETTINGS"
  echo "settings: wired    $SETTINGS"
fi

# 3. CLAUDE.local.md -----------------------------------------------------------
# The SessionStart hook covers interactive sessions. This covers everything else:
# subagents, `claude -p`, other editors — anywhere the hook does not fire.
if [ "$WRITE_CLAUDE_MD" = "1" ]; then
  LOCAL_MD="$REPO/CLAUDE.local.md"
  if [ -e "$LOCAL_MD" ]; then
    echo "local-md: already exists — left alone (delete it to regenerate)"
  elif [ ! -f "$TMPL" ]; then
    echo "local-md: SKIPPED — template missing at $TMPL"
  else
    sed -e "s#{{SCOPE}}#$SCOPE#g" -e "s#{{PROJECT}}#$PROJECT#g" -e "s#{{VAULT}}#$VAULT#g" \
      "$TMPL" > "$LOCAL_MD"
    echo "local-md: wrote    $LOCAL_MD"
  fi

  # Make sure it never gets committed. Prefer .git/info/exclude: it is local-only,
  # so we never mutate a tracked .gitignore that the whole team shares.
  if [ -e "$LOCAL_MD" ] && ! git -C "$REPO" check-ignore -q CLAUDE.local.md 2>/dev/null; then
    EXCLUDE="$(git -C "$REPO" rev-parse --git-dir)/info/exclude"
    [ "${EXCLUDE#/}" = "$EXCLUDE" ] && EXCLUDE="$REPO/$EXCLUDE"   # relative git-dir
    mkdir -p "$(dirname "$EXCLUDE")"
    printf 'CLAUDE.local.md\n' >> "$EXCLUDE"
    echo "ignore:   added CLAUDE.local.md to $EXCLUDE"
    echo "          (local-only. If the whole team uses AIOS, put it in .gitignore instead.)"
  fi
fi

cat <<EOF

Wired. Verify by starting a session in the repo:

  cd "$REPO" && claude

SessionStart should print:  === AIOS brain ($SCOPE/$PROJECT) — auto-loaded from vault ===

If it prints nothing, the manifest row didn't match. Column 1 must be exactly
the directory basename ('$BASE'), separated by real TABs. Run:

  $0 --check "$REPO"

Commit .claude/settings.json in the repo if your team wants the wiring shared;
keep it in .git/info/exclude if the vault is yours alone.
EOF
