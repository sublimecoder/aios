#!/bin/sh
# aios-install.sh — wire this machine to the vault. Idempotent, dry-run by default.
#
# WHY THIS EXISTS. Every other piece of the vault's enforcement is version
# controlled and self-checking, but the WIRING was not reproducible:
#
#   Claude Code   .claude/settings.json is committed IN the vault, so cloning the
#                 repo wires it. Nothing to install.
#   jcode         ~/.jcode/config.toml lives OUTSIDE the repo, is global, and was
#                 wired entirely by hand on 2026-08-11. A fresh machine, a jcode
#                 reinstall, or a second machine gets a vault whose guard does not
#                 run at all -- the exact silent-unenforced state the guard's own
#                 comments call "strictly worse than no guard".
#   skills        skills/link-global.sh already handles this. Called from here so
#                 there is ONE command to run, not a list to remember.
#   memory        Claude Code's `autoMemoryDirectory` is ignored in committed
#                 settings, so each repo's untracked settings.local.json is set
#                 per machine to point memory at the vault (plus the AIOS hooks
#                 for local-only repos). Without it every machine keeps its own.
#   launchd       the scheduled-ingest plist is copied to ~/Library/LaunchAgents
#                 by hand; aios-check compares them and reports drift. Installing
#                 it is left to a human because it starts a recurring background
#                 job, which is not something an installer should do unasked.
#
# aios-check.sh reports all of this as drift. This is the other half: the thing
# that FIXES what the check reports. A detector with no remedy just relocates the
# manual step.
#
# Usage:
#   aios-install.sh              # dry run: print what would change, touch nothing
#   aios-install.sh --apply      # make the changes
#   aios-install.sh --apply --adopt-skills   # also reclaim identical skill copies
#
# Exit 0 when the machine is (or would be) correctly wired, 1 when --apply is
# needed, 2 on a real error.
set -u

VAULT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
# AIOS_VAULT override is for the test harness: it redirects the manifest and the
# memory dirs to a fixture, never the scripts themselves.
AIOS_VAULT="${AIOS_VAULT:-$VAULT}"
. "$VAULT/AIOS/Systems/hooks/lib.sh"
JCODE_CFG="${AIOS_JCODE_CONFIG:-$HOME/.jcode/config.toml}"
APPLY=0
ADOPT=""
for a in "$@"; do
  case "$a" in
    --apply)         APPLY=1 ;;
    --adopt-skills)  ADOPT="--adopt" ;;
    -h|--help)       sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "aios-install: unknown option: $a" >&2; exit 2 ;;
  esac
done

[ -f "$VAULT/CLAUDE.md" ] && [ -d "$VAULT/AIOS" ] || {
  echo "aios-install: $VAULT does not look like the vault (no CLAUDE.md + AIOS/)" >&2
  exit 2
}

CHANGES=0
ERRORS=0
say() { echo "$@"; }
would() { if [ "$APPLY" -eq 1 ]; then say "  $*"; else say "  [dry-run] $*"; fi; CHANGES=$((CHANGES+1)); }

say "aios-install: vault at $VAULT"
[ "$APPLY" -eq 1 ] || say "DRY RUN — nothing will be written. Re-run with --apply."
say ""

# ---------------------------------------------------------------- jcode hooks
# The three hooks and the vault script each must point at. Kept in the same
# order aios-check verifies them, and the basenames are what that check matches
# on, so the two cannot disagree about what "wired" means.
say "jcode hooks ($JCODE_CFG)"
if ! command -v jcode >/dev/null 2>&1 && [ ! -f "$JCODE_CFG" ]; then
  say "  jcode not installed on this machine — skipping (not an error)"
else
  need=""
  check_hook() { # $1=key $2=script basename $3=path relative to vault
    cur=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$JCODE_CFG" 2>/dev/null | head -1)
    case "$cur" in
      *"$2"*) say "  ok       $1 -> $2" ;;
      "")     need="$need$1 $3
"; would "set      $1 -> \$VAULT/$3" ;;
      *)      need="$need$1 $3
"; would "REPLACE  $1 (currently: $(printf '%s' "$cur" | sed 's/^[[:space:]]*//'))" ;;
    esac
  }
  # pre_tool goes straight to the guard. jcode allows ONE command per hook, so if
  # you add an after-the-fact write observer later it needs a dispatcher here that
  # snapshots first and lets the guard decide the exit code — not a second entry.
  check_hook pre_tool      vault-write-guard.sh   ".claude/hooks/vault-write-guard.sh"
  check_hook session_start aios-session-status.sh "AIOS/Systems/hooks/aios-session-status.sh"
  check_hook session_end   aios-digest.sh         "AIOS/Systems/hooks/aios-digest.sh"

  if [ -n "$need" ] && [ "$APPLY" -eq 1 ]; then
    mkdir -p "$(dirname "$JCODE_CFG")"
    [ -f "$JCODE_CFG" ] || : > "$JCODE_CFG"
    # BACK UP FIRST, and never clobber an existing backup — this file holds the
    # user's keybindings, provider choices and everything else. A timestamped
    # copy means a bad run is always recoverable.
    BAK="$JCODE_CFG.aios-bak-$(date +%Y%m%dT%H%M%S)"
    cp "$JCODE_CFG" "$BAK" && say "  backup   $BAK"

    # Python, not sed: this is a real TOML file with sections, and the edit has
    # to land INSIDE [hooks] (creating it if absent) while leaving every other
    # section untouched. A line-oriented sed cannot do that safely, and getting
    # it wrong corrupts the config for every jcode session on the machine.
    AIOS_VAULT_PATH="$VAULT" AIOS_NEED="$need" python3 - "$JCODE_CFG" <<'PY'
import os, re, sys

cfg   = sys.argv[1]
vault = os.environ["AIOS_VAULT_PATH"]
need  = [l.split() for l in os.environ["AIOS_NEED"].strip().split("\n") if l.strip()]

src = open(cfg, encoding="utf-8").read()

# Write $HOME-relative when possible: the config is portable that way, and jcode
# expands a leading ~/ per its own docs.
home = os.path.expanduser("~")
def fmt(rel):
    p = os.path.join(vault, rel)
    return "~" + p[len(home):] if p.startswith(home + "/") else p

lines = src.split("\n")

# Locate [hooks]: its header index and the index one past its last line.
start = end = None
for i, l in enumerate(lines):
    if re.match(r"^\s*\[hooks\]\s*$", l):
        start = i
        for j in range(i + 1, len(lines)):
            if re.match(r"^\s*\[", lines[j]):
                end = j
                break
        else:
            end = len(lines)
        break

if start is None:
    # No [hooks] section: append one. Trailing blank lines are trimmed first so
    # the file does not accumulate gaps every run.
    while lines and lines[-1].strip() == "":
        lines.pop()
    lines += ["", "[hooks]"]
    start, end = len(lines) - 1, len(lines)

block = lines[start:end]
for key, rel in need:
    val = f'{key} = "{fmt(rel)}"'
    for k, l in enumerate(block):
        if re.match(rf"^\s*{re.escape(key)}\s*=", l):
            block[k] = val          # replace in place, preserving position
            break
    else:
        # Insert after the last assignment in the section rather than at its end,
        # so a trailing comment block stays trailing.
        ins = len(block)
        for k in range(len(block) - 1, -1, -1):
            if "=" in block[k]:
                ins = k + 1
                break
        block.insert(ins, val)

lines[start:end] = block
open(cfg, "w", encoding="utf-8").write("\n".join(lines))
PY
    rc=$?
    if [ "$rc" -ne 0 ]; then
      say "  ERROR    edit failed (rc=$rc) — restoring from $BAK"
      cp "$BAK" "$JCODE_CFG"
      exit 2
    fi
    # VALIDATE, then ROLL BACK on failure. An unparseable config is worse than an
    # unwired one: it can break every jcode session, including the one needed to
    # fix it. Python 3.11+ has tomllib; older falls back to a no-op with a notice
    # rather than a false pass.
    if python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$JCODE_CFG" 2>/dev/null; then
      say "  ok       config still parses as TOML"
    elif python3 -c "import tomllib" 2>/dev/null; then
      say "  ERROR    result is not valid TOML — restoring from $BAK"
      cp "$BAK" "$JCODE_CFG"
      exit 2
    else
      say "  note     python3 has no tomllib (<3.11); could not validate"
    fi
  fi
fi
say ""

# ------------------------------------------------------------------- skills
# Delegated, never reimplemented — link-global.sh owns the collision rules and
# the vault-recursion guard, and a second copy of that logic here would drift.
say "portable skills"
if [ "$APPLY" -eq 1 ]; then
  out=$(sh "$VAULT/skills/link-global.sh" $ADOPT 2>&1)
  printf '%s\n' "$out" | sed 's/^/  /'
  [ -n "$ADOPT" ] || say "  (identical real-dir copies are refused; re-run with --adopt-skills to reclaim them)"
  # Count what link-global actually did, so the verdict below is not an undercount.
  # Without this the apply path only ever counted the jcode hook edits: a fresh
  # machine that linked 42 skills and set 3 hooks reported "applied 3 change(s)".
  n=$(printf '%s\n' "$out" | grep -cE '^(LINK|ADOPT) ') || true
  [ "${n:-0}" -gt 0 ] && CHANGES=$((CHANGES + n))
else
  out=$(sh "$VAULT/skills/link-global.sh" --dry-run ${ADOPT:+--adopt} 2>&1)
  printf '%s\n' "$out" | sed 's/^/  /'
  n=$(printf '%s\n' "$out" | grep -c '^DRY') || true
  [ "${n:-0}" -gt 0 ] && CHANGES=$((CHANGES + n))
fi
say ""

# ------------------------------------------------- Claude Code memory -> vault
# Claude Code keeps memory per machine under ~/.claude/projects unless
# `autoMemoryDirectory` says otherwise. That setting is IGNORED in a committed
# .claude/settings.json (security), so it goes in each repo's untracked
# settings.local.json -- which is also why it cannot travel with the repo and
# has to be installed here, once per machine. See lib.sh "native memory".
#
# Rows flagged local-only have no committed settings.json at all,
# so their context + digest hooks live in the same untracked file and are wired
# here too. Every other repo commits its own wire and gets only the memory key.
say "Claude Code memory -> vault (repos in repo-layers.tsv)"
MANIFEST_ROWS=$(awk -F'\t' '/^[[:space:]]*#/ {next} NF>=4 && $4!="" {print $1"\t"$2"\t"$3"\t"$4"\t"$5}' "$AIOS_MANIFEST" 2>/dev/null)
TAB=$(printf '\t')
while IFS="$TAB" read -r m_repo m_layer m_project m_path m_flags; do
  [ -n "$m_repo" ] || continue
  m_root=$(aios_expand_home "$m_path")
  if ! git -C "$m_root" rev-parse --git-dir >/dev/null 2>&1; then
    say "  skip     $m_repo — not cloned at $m_path"
    continue
  fi
  if ! git -C "$m_root" check-ignore -q .claude/settings.local.json; then
    say "  REFUSE   $m_repo — .claude/settings.local.json is not gitignored there; writing it would make a machine path committable"
    continue
  fi
  m_dst=$(aios_memory_dir "$m_layer" "$m_project")
  case "$m_dst" in "$HOME"/*) m_want="~/${m_dst#"$HOME"/}" ;; *) m_want=$m_dst ;; esac
  m_hooks=0; case ",$m_flags," in *,local-only,*) m_hooks=1 ;; esac
  case "$VAULT" in "$HOME"/*) m_hookbase="\$HOME/${VAULT#"$HOME"/}" ;; *) m_hookbase=$VAULT ;; esac
  # Python for the JSON edit: the file holds the user's permission allowlist,
  # and a sed edit that breaks it breaks every session in that repo.
  m_need=$(python3 - "$m_root/.claude/settings.local.json" "$m_want" "$m_hooks" "$m_hookbase" "$APPLY" <<'PY'
import json, os, sys
path, want, hooks, base, apply = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4], sys.argv[5] == "1"
try:
    d = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
except ValueError:
    print("INVALID"); sys.exit(0)
need = []
if d.get("autoMemoryDirectory") != want:
    need.append("autoMemoryDirectory")
    d["autoMemoryDirectory"] = want
if hooks:
    h = d.setdefault("hooks", {})
    for event, script, matcher, timeout in (("SessionStart", "aios-context.sh", "startup|resume|clear|compact", 10),
                                            ("Stop", "aios-digest.sh", "", 30)):
        if not any(script in x.get("command", "") for m in h.get(event, []) for x in m.get("hooks", [])):
            need.append(event + " hook")
            h.setdefault(event, []).append({"matcher": matcher, "hooks": [
                {"type": "command", "command": f'sh "{base}/AIOS/Systems/hooks/{script}"', "timeout": timeout}]})
if need and apply:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False); f.write("\n")
print(", ".join(need))
PY
)
  case "$m_need" in
    INVALID) say "  ERROR    $m_repo — .claude/settings.local.json is not valid JSON; left untouched" ;;
    "")      say "  ok       $m_repo -> $m_want" ;;
    *)       would "set      $m_repo: $m_need" ;;
  esac
  [ "$m_need" = INVALID ] && continue
  # A machine-local memory dir left behind is absorbed (never overwriting the
  # vault copy) and moved aside, so nothing this machine learned is lost.
  m_stray=$(aios_default_memory_dir "$m_root")
  if [ -d "$m_stray" ]; then
    would "absorb   $m_repo: $(ls "$m_stray" | wc -l | tr -d ' ') local memory file(s) from $m_stray, then move it aside"
    if [ "$APPLY" -eq 1 ]; then
      m_kept=$(aios_absorb_memory "$m_stray" "$m_dst")
      m_aside="$m_stray.pre-vault-$(date +%Y%m%dT%H%M%S)"
      mv "$m_stray" "$m_aside"
      [ "$m_kept" -gt 0 ] && say "  NOTE     $m_kept file(s) differ from the vault copy and were NOT absorbed — reconcile by hand from $m_aside"
    fi
  elif [ "$APPLY" -eq 1 ]; then
    mkdir -p "$m_dst"
  fi
done <<ROWS
$MANIFEST_ROWS
ROWS
say ""

# ------------------------------------------- global Claude settings (vault keys)
# ~/.claude/settings.json has TWO owners. Public dotfiles merges the layer-neutral
# keys; this merges the vault-owned ones: claude-settings.vault.json (skillOverrides
# names one scope's skills) AND every <scope>/projects/*/claude-settings.global.json
# fragment. A project fragment (e.g. a repo's autoMode rules) still lives
# in its own layer dir for the identity wall, but is merged HERE, into the
# machine-local user settings, rather than into that repo's own settings.local.json:
# a live test showed Claude Code honours `autoMode` only in ~/.claude/settings.json,
# never in a repo's settings.local.json. Neither owner touches the other's keys, and
# the merge never deletes, so running both in either order converges.
say "global Claude settings (vault-owned keys)"
CS_TARGET="${AIOS_CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
cs_backup_done=0
for CS_FRAG in "$AIOS_VAULT/AIOS/Systems/claude-settings.vault.json" "$AIOS_VAULT"/*/projects/*/claude-settings.global.json; do
  [ -f "$CS_FRAG" ] || continue
  cs_rel=${CS_FRAG#"$AIOS_VAULT"/}
  # Only the first fragment in this run that actually needs a change gets the
  # `backup` flag -- json-merge.py backs up the target's PRE-RUN state, and a
  # second backup would only capture what the first fragment already wrote.
  if [ "$cs_backup_done" -eq 0 ]; then
    cs_need=$(python3 "$VAULT/AIOS/Systems/json-merge.py" "$CS_TARGET" "$CS_FRAG" "$APPLY" backup) || cs_need=CRASH
  else
    cs_need=$(python3 "$VAULT/AIOS/Systems/json-merge.py" "$CS_TARGET" "$CS_FRAG" "$APPLY") || cs_need=CRASH
  fi
  case "$cs_need" in
    INVALID) say "  ERROR    $CS_TARGET or $cs_rel is not valid JSON; left untouched"; ERRORS=$((ERRORS+1)) ;;
    CRASH)   say "  ERROR    json-merge.py crashed merging $cs_rel into $CS_TARGET; left untouched"; ERRORS=$((ERRORS+1)) ;;
    "")      say "  ok       $CS_TARGET carries $cs_rel" ;;
    *)       would "merge    $cs_need into $CS_TARGET from $cs_rel"; cs_backup_done=1 ;;
  esac
done
say ""

# ------------------------------------------------------- launchd (report only)
# Deliberately NOT installed. This plist starts a recurring background job that
# runs a headless agent against the vault on a schedule; that is a decision, not
# a detail, and an installer should not make it silently. aios-check reports
# drift between the vault copy and the installed twin either way.
say "launchd agents (report only)"
# launchd is macOS-only. On Linux the same jobs are systemd user timers, owned by
# aios-scheduler.sh -- printing launchctl advice there is noise that reads like a TODO.
if [ "${AIOS_UNAME_S:-$(uname -s)}" != Darwin ]; then
  say "  n/a      not macOS — timers on this OS are managed by: sh AIOS/Systems/aios-scheduler.sh"
else for plist in "$VAULT"/AIOS/Systems/hooks/*.plist; do
  [ -f "$plist" ] || continue
  twin="$HOME/Library/LaunchAgents/$(basename "$plist")"
  if [ ! -f "$twin" ]; then
    say "  not installed: $(basename "$plist")"
    say "                 starts a recurring background agent — install by hand if you want it:"
    say "                 cp '$plist' '$twin' && launchctl load '$twin'"
  elif cmp -s "$plist" "$twin"; then
    say "  ok       $(basename "$plist") matches the vault copy"
  else
    say "  DRIFT    $(basename "$plist") differs from the installed copy — the vault copy is not what fires"
  fi
done
fi
say ""

# ------------------------------------------------------------------- verdict
# An INVALID or CRASH ERROR above must not read as success just because the run
# otherwise completed: exit 2 unconditionally, dry run or apply, whenever the
# flag is set. Checked first, before the changes-needed accounting below.
if [ "$ERRORS" -gt 0 ]; then
  say "aios-install: $ERRORS error(s) during the run — see ERROR lines above; nothing there was applied."
  exit 2
fi
if [ "$CHANGES" -eq 0 ]; then
  say "aios-install: already wired, nothing to do."
  exit 0
fi
if [ "$APPLY" -eq 1 ]; then
  say "aios-install: applied $CHANGES change(s)."
  say "NOTE: jcode loads hooks at SESSION START — restart jcode for them to take effect."
  exit 0
fi
say "aios-install: $CHANGES change(s) needed. Re-run with --apply."
exit 1
