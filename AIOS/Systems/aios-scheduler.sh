#!/bin/sh
# aios-scheduler.sh — install / uninstall the AIOS timers on THIS machine, and
# move ownership between machines without ever having two of them firing.
#
# WHY A SCRIPT AND NOT A RUNBOOK. Two hosts firing /aios-ingest at 08:00 against
# one vault double-drain +/_sessions/ and race the push; .aios-ingest.lock is a
# per-machine mkdir lock and cannot see across machines. The dangerous window is
# the HANDOFF, and a handoff done from memory at the end of a long session is
# where the mistake lands. The rollback to macOS has to be as cheap as the move
# away from it, or it stops being a real fallback.
#
# THE ONE SAFETY PROPERTY: `install` refuses unless this host is the declared
# owner in AIOS/Systems/scheduler-host, and `uninstall` is ALWAYS allowed. The
# dangerous direction is gated on a tracked declaration; the safe direction never
# is. That asymmetry is the whole design — you can always stop a machine, and you
# can only start one by saying so in a commit.
#
# Usage:
#   aios-scheduler.sh                 status (default — reads only, changes nothing)
#   aios-scheduler.sh status
#   aios-scheduler.sh install         install + enable here (owner only)
#     --skip-preflight                install without proving the remote is
#                                     reachable WITHOUT an ssh agent
#   aios-scheduler.sh uninstall       disable + remove here (always allowed)
#   aios-scheduler.sh claim           declare THIS host the owner (edits the marker)
#
# The cutover, in the order that cannot corrupt the queue:
#   1. losing machine:  aios-scheduler.sh uninstall
#   2. either machine:  aios-scheduler.sh claim   (then commit + push the marker)
#   3. winning machine: git pull --ff-only && aios-scheduler.sh install
#   4. both machines:   sh AIOS/Systems/aios-check.sh
# Reverse the two machines to roll back. A GAP costs one skipped ingest, which
# the next fire absorbs; an OVERLAP costs a corrupted queue. Always stop first.
set -u

VAULT="${AIOS_VAULT:-$HOME/code/aios}"
MARKER="$VAULT/AIOS/Systems/scheduler-host"
UNITS="$VAULT/AIOS/Systems/hooks"

# Overridable ONLY so test-aios-scheduler.sh can drive both OS branches and stub
# the system commands. A suite that can exercise just the host it runs on would
# leave the rollback path — the macOS half — permanently unasserted, which is the
# half this file exists to keep working.
OS="${AIOS_UNAME_S:-$(uname -s)}"
THIS="${AIOS_HOSTNAME:-$(uname -n | cut -d. -f1)}"
SYSTEMCTL="${AIOS_SYSTEMCTL:-systemctl}"
LAUNCHCTL="${AIOS_LAUNCHCTL:-launchctl}"
LOGINCTL="${AIOS_LOGINCTL:-loginctl}"
GIT="${AIOS_GIT:-git}"
UNIT_DIR="${AIOS_UNIT_DIR:-$HOME/.config/systemd/user}"
AGENT_DIR="${AIOS_AGENT_DIR:-$HOME/Library/LaunchAgents}"

die() { echo "aios-scheduler: $*" >&2; exit 1; }

owner() {
  [ -f "$MARKER" ] || return 1
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$MARKER" 2>/dev/null | grep -v '^$' | head -1
}

# The unit/agent files this OS actually uses, basenames only.
units_for_os() {
  if [ "$OS" = Darwin ]; then
    for f in "$UNITS"/com.aios.*.plist; do [ -f "$f" ] && basename "$f"; done
  else
    for f in "$UNITS"/aios-*.timer "$UNITS"/aios-*.service; do [ -f "$f" ] && basename "$f"; done
  fi
}

# Installed = the file is present where this OS's scheduler reads it. File
# presence, not `systemctl is-enabled` / `launchctl list`: it is what
# aios-check.sh's ownership table uses, and the two MUST agree or one of them
# is lying. Consequence worth knowing: a unit staged but not enabled still reads
# as installed, which is why `install` and `uninstall` move the files rather than
# only toggling the scheduler.
dest_dir() { [ "$OS" = Darwin ] && echo "$AGENT_DIR" || echo "$UNIT_DIR"; }

installed_count() {
  d=$(dest_dir); n=0
  for u in $(units_for_os); do [ -f "$d/$u" ] && n=$((n+1)); done
  echo "$n"
}

cmd_status() {
  o=$(owner) || o=""
  n=$(installed_count)
  total=$(units_for_os | wc -l | tr -d ' ')
  echo "host:      $THIS ($OS)"
  echo "owner:     ${o:-<UNDECLARED>}"
  echo "installed: $n of $total unit file(s) in $(dest_dir)"
  if [ -z "$o" ]; then
    echo "verdict:   BROKEN — no owner declared; aios-check cannot detect a double scheduler."
  elif [ "$THIS" = "$o" ] && [ "$n" -gt 0 ]; then
    echo "verdict:   ok — this host owns the timers and has them installed."
  elif [ "$THIS" = "$o" ]; then
    echo "verdict:   UNWIRED — this host owns the timers but none are installed. Run: $0 install"
  elif [ "$n" -gt 0 ]; then
    echo "verdict:   DOUBLE-SCHEDULER — this host is NOT the owner but has timers installed."
    echo "           Two machines firing at one vault double-drain +/_sessions/. Run: $0 uninstall"
  else
    echo "verdict:   ok — not the owner, nothing installed here."
  fi
}

# preflight_remote — can an UNATTENDED run reach the remote?
#
# THE STRIPPED ENVIRONMENT IS THE ENTIRE POINT. A systemd user service inherits
# no SSH_AUTH_SOCK, and the interactive agent socket is a random per-session path
# that cannot be hardcoded. So this unsets the agent before asking: a check that
# runs with YOUR agent loaded passes on a machine where every unattended fire
# will fail, which is worse than no check because it certifies the broken state.
#
# Earned 2026-09-05: the first fire after the Omarchy cutover drained the queue,
# wrote the wiki, committed -- and could not push, because the vault key has a
# passphrase. It logged "done" and exited 0. The fix was a passphrase-less deploy
# key scoped to this repo; this gate is what stops the next machine repeating it.
# Subshell-unset rather than `env -u`, which is not POSIX.
preflight_remote() {
  ( unset SSH_AUTH_SOCK SSH_AGENT_PID; "$GIT" -C "$VAULT" fetch -q --dry-run origin ) 2>&1
}

cmd_install() {
  o=$(owner) || die "no owner declared in $MARKER. Run '$0 claim' on the machine that should run the timers."
  [ "$THIS" = "$o" ] || die "refusing: this host is '$THIS' but the declared owner is '$o'.
  Installing here would put two machines on one vault, which double-drains
  +/_sessions/ and races the push. Uninstall on '$o' FIRST, then '$0 claim' here,
  commit the marker, and run install again."

  if [ "${SKIP_PREFLIGHT:-0}" = 0 ]; then
    if ! err=$(preflight_remote); then
      die "preflight FAILED — this machine cannot reach the vault remote without an
  ssh agent, so the timers would drain the queue, commit, and never push. The
  run would still exit 0; you would find out from the UNSYNCED line at the next
  session start, days later.

  git said:
$(printf '%s' "$err" | sed 's/^/    /')

  Fix: give this machine a passphrase-less deploy key scoped to the vault repo
  and point the remote at it (see the Omarchy port plan). Then re-run install.
  To install anyway — offline, or pushing by hand on purpose:
      $0 install --skip-preflight"
    fi
    echo "  preflight  remote reachable without an ssh agent"
  fi

  d=$(dest_dir); mkdir -p "$d"
  # SUBSTITUTED, NOT COPIED. The tracked unit files carry __AIOS_VAULT__ and
  # __HOME__ placeholders rather than this machine's paths: a unit file with an
  # absolute path baked in is correct on exactly one checkout and silently wrong
  # on every other, and launchd reports a bad ProgramArguments path as a job that
  # simply never runs. aios-check.sh applies the same substitution before it
  # compares the tracked copy to the installed twin, so the two stay comparable.
  for u in $(units_for_os); do
    sed -e "s|__AIOS_VAULT__|$VAULT|g" -e "s|__HOME__|$HOME|g" "$UNITS/$u" > "$d/$u" \
      && echo "  install  $d/$u"
  done

  if [ "$OS" = Darwin ]; then
    for u in $(units_for_os); do "$LAUNCHCTL" load "$d/$u" && echo "  load     $u"; done
  else
    "$SYSTEMCTL" --user daemon-reload
    for u in $(units_for_os); do
      case "$u" in *.timer) "$SYSTEMCTL" --user enable --now "$u" && echo "  enable   $u" ;; esac
    done
    # User timers do not fire unless the user is logged in. This is the single
    # most likely reason a correct-looking unit silently never runs.
    "$LOGINCTL" enable-linger "${USER:-$(id -un)}" 2>/dev/null \
      && echo "  linger   enabled for ${USER:-$(id -un)}"
  fi
  echo
  cmd_status
}

# Always permitted, on any host, owner or not. Stopping is never the dangerous
# direction, and a fallback you have to argue with is not a fallback.
cmd_uninstall() {
  d=$(dest_dir); n=0
  if [ "$OS" = Darwin ]; then
    for u in $(units_for_os); do
      [ -f "$d/$u" ] || continue
      "$LAUNCHCTL" unload "$d/$u" 2>/dev/null; rm -f "$d/$u"
      echo "  unload   $u"; n=$((n+1))
    done
  else
    for u in $(units_for_os); do
      [ -f "$d/$u" ] || continue
      case "$u" in *.timer) "$SYSTEMCTL" --user disable --now "$u" 2>/dev/null ;; esac
      rm -f "$d/$u"; echo "  remove   $u"; n=$((n+1))
    done
    [ "$n" -gt 0 ] && "$SYSTEMCTL" --user daemon-reload
  fi
  # The files are REMOVED, not just disabled: aios-check reads presence, so a
  # disabled-but-present unit would keep reporting DOUBLE-SCHEDULER forever. The
  # copies of record stay in the vault, which is what makes this reversible.
  [ "$n" -eq 0 ] && echo "  nothing installed here — no change"
  echo
  cmd_status
}

cmd_claim() {
  o=$(owner) || o=""
  [ "$THIS" = "$o" ] && { echo "aios-scheduler: '$THIS' is already the declared owner — nothing to do."; exit 0; }
  [ -n "$o" ] && cat >&2 <<EOF
aios-scheduler: moving ownership '$o' -> '$THIS'.
  UNINSTALL ON '$o' FIRST if you have not already. Claiming while the old owner
  still has its timers loaded is exactly the overlap this marker exists to
  prevent, and nothing here can see that machine to check.
EOF
  tmp="$MARKER.tmp.$$"
  # Preserve the file's rationale header; replace only the hostname line.
  { sed -e '/^[[:space:]]*#/!d' "$MARKER" 2>/dev/null; echo "$THIS"; } > "$tmp" \
    && mv "$tmp" "$MARKER" || die "could not write $MARKER"
  echo "aios-scheduler: $MARKER now declares '$THIS'."
  echo "  Commit and push it, then run '$0 install' here:"
  echo "    git -C \"$VAULT\" commit -am 'aios: scheduler ownership -> $THIS' && git -C \"$VAULT\" push"
}

SKIP_PREFLIGHT=0
for _a in "$@"; do
  case "$_a" in --skip-preflight) SKIP_PREFLIGHT=1 ;; esac
done

case "${1:-status}" in
  status)    cmd_status ;;
  install)   cmd_install ;;
  uninstall) cmd_uninstall ;;
  claim)     cmd_claim ;;
  -h|--help) sed -n '2,32p' "$0" ;;
  *)         die "unknown command '${1}'. Try: status | install | uninstall | claim [--skip-preflight]" ;;
esac
