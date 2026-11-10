#!/usr/bin/env bash
# aios-install-nightly.sh — schedule the nightly ingest so the vault compounds
# without you remembering to run /aios-ingest.
#
#   scripts/aios-install-nightly.sh [HH:MM]     install (default 03:00 local)
#   scripts/aios-install-nightly.sh --status    is it scheduled? did it run?
#   scripts/aios-install-nightly.sh --uninstall
#   scripts/aios-install-nightly.sh --dry-run   run the ingest once, right now
#
# macOS -> a launchd LaunchAgent. Linux -> a crontab line. Idempotent either way.
#
# THE FALLBACK SCHEDULER, not the default one. AIOS/Systems/aios-scheduler.sh is
# the default: it runs two jobs instead of one and guards the hazard this script
# cannot see — two MACHINES sharing one vault, which it settles with the tracked
# AIOS/Systems/scheduler-host marker. Use this one when its Linux backend does
# not fit, because systemd user timers need a user session (and `loginctl
# enable-linger` to fire while logged out) and cron does not.
#
# What this script guards instead is the opposite hazard, and it is the only one
# that does: two VAULTS on one machine. The launchd label and the cron line are
# global, so a second vault installing from here would silently replace the
# first — see the fail-closed check below.
#
# The two know nothing about each other. Install one. Running both puts two jobs
# on one queue.
set -uo pipefail

VAULT="${AIOS_VAULT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="$VAULT/AIOS/Systems/hooks/aios-nightly-ingest.sh"
LABEL="com.aios.nightly-ingest"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

die() { echo "error: $*" >&2; exit 1; }

[ -x "$SCRIPT" ] || die "$SCRIPT missing or not executable (chmod +x it)"
[ -d "$VAULT/AIOS" ] || die "no vault at $VAULT (set AIOS_VAULT)"

# Must mirror the resolution order in aios-nightly-ingest.sh, or --status tails
# a log the job never writes to.
if [ -n "${AIOS_LOG_DIR:-}" ]; then LOG_DIR="$AIOS_LOG_DIR"
elif [ -d "$HOME/Library/Logs" ]; then LOG_DIR="$HOME/Library/Logs"
else LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/aios"; fi
LOG="$LOG_DIR/aios-ingest.log"

# BOTH OVERRIDABLE, and only so this is testable in both directions on one
# machine. The launchd half of this script is macOS-only, so on a Linux box it is
# unreachable — and a suite that cannot reach it does not report "skipped", it
# reports FAILED, forever, which is how a permanently-red check stops being read.
# Same reasoning and the same env-var convention as AIOS_UNAME_S in
# AIOS/Systems/aios-check.sh.
#
# Neither is a knob for real use: they default to the real `uname` and to
# PlistBuddy at its absolute path, because resolving PlistBuddy through $PATH
# would be an injection point on the one platform where this branch runs.
UNAME_S="${AIOS_UNAME_S:-$(uname -s)}"
PLISTBUDDY="${AIOS_PLISTBUDDY:-/usr/libexec/PlistBuddy}"

is_macos() { [ "$UNAME_S" = "Darwin" ]; }

# The launchd label and the crontab line are GLOBAL, but a vault is not. Two
# vaults installing the same label means the second silently replaces the first.
# Report which vault the installed job actually targets, never just "installed".
#
# Two ways to learn it, because an older install may predate the env var:
#   1. EnvironmentVariables:AIOS_VAULT   (what we write today)
#   2. the script path in ProgramArguments, minus the known hooks suffix
# If a job exists and BOTH fail, say so — callers must treat unknown as "occupied",
# never as "free". Failing open here silently disables someone's nightly ingest.
HOOK_SUFFIX="/AIOS/Systems/hooks/aios-nightly-ingest.sh"

job_installed() {
  if is_macos; then [ -f "$PLIST" ]
  else crontab -l 2>/dev/null | grep -q "aios-nightly-ingest.sh"; fi
}

installed_vault() {
  v=""
  if is_macos && [ -f "$PLIST" ]; then
    v=$("$PLISTBUDDY" -c 'Print :EnvironmentVariables:AIOS_VAULT' "$PLIST" 2>/dev/null)
    if [ -z "$v" ]; then
      p=$("$PLISTBUDDY" -c 'Print :ProgramArguments:1' "$PLIST" 2>/dev/null)
      case "$p" in *"$HOOK_SUFFIX") v="${p%"$HOOK_SUFFIX"}";; esac
    fi
  elif ! is_macos; then
    line=$(crontab -l 2>/dev/null | grep "aios-nightly-ingest.sh" | head -1)
    v=$(printf '%s' "$line" | sed -n "s/.*AIOS_VAULT='\([^']*\)'.*/\1/p")
    if [ -z "$v" ]; then
      p=$(printf '%s' "$line" | sed -n "s#.*'\(/[^']*$HOOK_SUFFIX\)'.*#\1#p")
      [ -n "$p" ] && v="${p%"$HOOK_SUFFIX"}"
    fi
  fi
  printf '%s' "$v"
}

# ---------------------------------------------------------------------- status
if [ "${1:-}" = "--status" ]; then
  echo "vault:  $VAULT"
  echo "script: $SCRIPT"
  other=$(installed_vault)
  if is_macos; then
    if [ -f "$PLIST" ]; then
      echo "launchd: installed ($PLIST)"
      echo "targets: ${other:-<unknown>}"
      launchctl list 2>/dev/null | grep -q "$LABEL" && echo "loaded:  yes" || echo "loaded:  NO — run: launchctl bootstrap gui/\$(id -u) '$PLIST'"
    else
      echo "launchd: not installed"
    fi
  else
    if crontab -l 2>/dev/null | grep -q "aios-nightly-ingest.sh"; then
      echo "cron:    installed"; echo "targets: ${other:-<unknown>}"
    else
      echo "cron:    not installed"
    fi
  fi
  if [ -n "$other" ] && [ "$other" != "$VAULT" ]; then
    echo
    echo "WARNING: the scheduled job targets a DIFFERENT vault than this one."
    echo "  scheduled: $other"
    echo "  this one:  $VAULT"
    echo "The launchd label / cron line is global. Installing from here would"
    echo "replace that job, and '$other' would stop ingesting."
  fi
  echo
  if [ -f "$LOG" ]; then echo "--- last 5 log lines ($LOG) ---"; tail -5 "$LOG"
  else echo "no log yet at $LOG (it has never run, or never had a queue to drain)"; fi
  exit 0
fi

# ------------------------------------------------------------------- uninstall
if [ "${1:-}" = "--uninstall" ]; then
  if is_macos; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    rm -f "$PLIST" && echo "removed $PLIST"
  else
    crontab -l 2>/dev/null | grep -v "aios-nightly-ingest.sh" | crontab - && echo "removed cron entry"
  fi
  exit 0
fi

# ---------------------------------------------------------------------- dry run
if [ "${1:-}" = "--dry-run" ]; then
  echo "running the nightly ingest once, now (same code path launchd/cron will use)"
  echo "log: $LOG"
  # Forward AIOS_LOG_DIR too, or a dry run writes into the default log instead of
  # the one --status reads.
  AIOS_VAULT="$VAULT" AIOS_LOG_DIR="$LOG_DIR" sh "$SCRIPT"
  echo "--- log tail ---"; tail -3 "$LOG" 2>/dev/null || echo "(no log written)"
  exit 0
fi

# ---------------------------------------------------------------------- install
WHEN="${1:-03:00}"
[[ "$WHEN" =~ ^([0-9]{1,2}):([0-9]{2})$ ]] || die "time must be HH:MM (got '$WHEN')"
HH=$((10#${BASH_REMATCH[1]})); MM=$((10#${BASH_REMATCH[2]}))
{ [ "$HH" -le 23 ] && [ "$MM" -le 59 ]; } || die "not a valid time: $WHEN"

# Don't quietly hijack another vault's nightly job. FAIL CLOSED: an existing job
# whose vault we cannot identify is treated as someone else's, not as free space.
if job_installed && [ "${AIOS_FORCE:-}" != "1" ]; then
  prev=$(installed_vault)
  if [ -z "$prev" ]; then
    die "a nightly ingest job named '$LABEL' is already scheduled, but its target
  vault could not be determined (an older install predating AIOS_VAULT).
  Installing here would silently replace it. Inspect it first:
    $( is_macos && echo "cat '$PLIST'" || echo "crontab -l | grep aios-nightly-ingest" )
  Then re-run with:  AIOS_FORCE=1 $0 $WHEN"
  elif [ "$prev" != "$VAULT" ]; then
    die "a nightly ingest is already scheduled for a different vault:
    scheduled: $prev
    this one:  $VAULT
  The launchd label / cron line is global, so installing here would stop '$prev'
  from ingesting. If that is what you want:  AIOS_FORCE=1 $0 $WHEN"
  fi
fi

mkdir -p "$LOG_DIR"

if is_macos; then
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$SCRIPT</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>AIOS_VAULT</key><string>$VAULT</string>
    <key>AIOS_LOG_DIR</key><string>$LOG_DIR</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>$HH</integer>
    <key>Minute</key><integer>$MM</integer>
  </dict>
  <key>StandardErrorPath</key><string>$LOG_DIR/aios-ingest.launchd.log</string>
  <key>StandardOutPath</key><string>$LOG_DIR/aios-ingest.launchd.log</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
EOF
  # bootout first so a re-run picks up an edited plist rather than silently keeping the old one.
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
    || die "launchctl bootstrap failed. Load it by hand: launchctl bootstrap gui/\$(id -u) '$PLIST'"
  echo "launchd: scheduled $LABEL at $(printf '%02d:%02d' "$HH" "$MM") local"
  echo "plist:   $PLIST"
else
  LINE="$MM $HH * * * AIOS_VAULT='$VAULT' AIOS_LOG_DIR='$LOG_DIR' /bin/sh '$SCRIPT'"
  current=$(crontab -l 2>/dev/null | grep -v "aios-nightly-ingest.sh")
  printf '%s\n%s\n' "$current" "$LINE" | sed '/^$/d' | crontab - \
    || die "failed to write crontab"
  echo "cron:    scheduled at $(printf '%02d:%02d' "$HH" "$MM") local"
  echo "line:    $LINE"
fi

cat <<EOF

Log: $LOG

Sanity-check it end to end before trusting it:

  $0 --dry-run     # run the ingest once, now
  $0 --status      # is it scheduled, and what did the last run say?

The script is a no-op when the queue is empty, so a dry run on a clean vault
just logs "queue empty, skipping" — that is a pass, not a failure.

It runs 'claude -p /aios-ingest' unattended with a scoped tool allowlist
(no network, no browser). The vault-write-guard hook still constrains where
writes can land. It commits the vault; it never pushes.
EOF
