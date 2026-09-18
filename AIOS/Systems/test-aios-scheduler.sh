#!/bin/sh
# Self-check for aios-scheduler.sh.
#
# The property worth proving is not "does it copy a file" — it is that the
# DANGEROUS direction is refused and the SAFE one never is. install must refuse
# on a non-owner; uninstall must work on any host, owner or not; and both OS
# branches must be exercised, because the macOS half IS the rollback path and a
# suite that only ran the host it sits on would leave it permanently unasserted.
#
# systemctl/launchctl/loginctl are stubbed to a logging script: the assertions
# are about which commands were issued, not about a live scheduler.
set -u
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
SUT="$HERE/${SCHEDUT:-aios-scheduler.sh}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
V="$TMP/vault"; mkdir -p "$V/AIOS/Systems/hooks" "$TMP/bin" "$TMP/home"

# The four Linux units and two macOS agents, as bare fixtures.
for u in aios-scheduled-ingest.timer aios-scheduled-ingest.service \
         aios-weekly-register.timer aios-weekly-register.service; do
  printf '[Unit]\n' > "$V/AIOS/Systems/hooks/$u"
done
for p in com.aios.scheduled-ingest.plist com.aios.weekly-register.plist; do
  printf '<plist/>\n' > "$V/AIOS/Systems/hooks/$p"
done

# One stub for all three system commands; every invocation is appended to a log.
cat > "$TMP/bin/stub" <<'EOF'
#!/bin/sh
echo "$(basename "$0") $*" >> "$STUBLOG"
exit 0
EOF
chmod +x "$TMP/bin/stub"
for c in systemctl launchctl loginctl; do cp "$TMP/bin/stub" "$TMP/bin/$c"; done

# A separate git stub: logs the call AND whether it could still see an ssh agent,
# then succeeds or fails according to $GITRC. The agent question is the point of
# the whole preflight, so the suite has to be able to see the answer.
cat > "$TMP/bin/git" <<'EOF'
#!/bin/sh
echo "git $* SSH_AUTH_SOCK=[${SSH_AUTH_SOCK-<unset>}]" >> "$STUBLOG"
exit ${GITRC:-0}
EOF
chmod +x "$TMP/bin/git"
STUBLOG="$TMP/calls.log"; export STUBLOG

marker() { printf '# rationale header, must survive a claim\n%s\n' "$1" > "$V/AIOS/Systems/scheduler-host"; }

# run <os> <host> [args...]
run() {
  os=$1; host=$2; shift 2
  : > "$STUBLOG"
  AIOS_VAULT="$V" AIOS_UNAME_S="$os" AIOS_HOSTNAME="$host" \
  AIOS_SYSTEMCTL="$TMP/bin/systemctl" AIOS_LAUNCHCTL="$TMP/bin/launchctl" \
  AIOS_LOGINCTL="$TMP/bin/loginctl" AIOS_GIT="$TMP/bin/git" \
  AIOS_UNIT_DIR="$TMP/home/.config/systemd/user" AIOS_AGENT_DIR="$TMP/home/Library/LaunchAgents" \
  HOME="$TMP/home" sh "$SUT" "$@" 2>&1
}
rc_of() { run "$@" >/dev/null 2>&1; echo $?; }
n_installed() { ls "$1" 2>/dev/null | wc -l | tr -d ' '; }

LX="$TMP/home/.config/systemd/user"; MC="$TMP/home/Library/LaunchAgents"

echo "aios-scheduler self-check"

# --- status is the default and must change nothing ---------------------------
marker otherbox
out=$(run Linux thisbox)
printf '%s' "$out" | grep -q 'not the owner, nothing installed here' \
  && ok "default action is status: non-owner with nothing installed is ok" \
  || bad "default status verdict wrong: $out"
[ "$(n_installed "$LX")" = 0 ] && ok "status installed nothing" || bad "status wrote unit files"

# --- THE SAFETY PROPERTY: install refuses on a non-owner ---------------------
rc=$(rc_of Linux thisbox install)
[ "$rc" = 1 ] && ok "install REFUSES when this host is not the declared owner" \
              || bad "install did not refuse on a non-owner (rc=$rc)"
[ "$(n_installed "$LX")" = 0 ] && ok "refused install left no unit files" || bad "refused install still copied files"
run Linux thisbox install 2>&1 | grep -q 'Uninstall on' \
  && ok "the refusal names the stop-the-other-machine-first order" \
  || bad "refusal does not say to uninstall on the owner first"

# --- install on the owner, Linux --------------------------------------------
marker thisbox
out=$(run Linux thisbox install)
[ "$(n_installed "$LX")" = 4 ] && ok "owner install copies all 4 Linux units" \
                               || bad "expected 4 units, got $(n_installed "$LX")"
grep -q 'systemctl --user daemon-reload' "$STUBLOG" && ok "install runs daemon-reload" || bad "no daemon-reload"
grep -q 'enable --now aios-scheduled-ingest.timer' "$STUBLOG" && ok "install enables the ingest timer" || bad "ingest timer not enabled"
grep -q 'enable --now aios-weekly-register.timer'  "$STUBLOG" && ok "install enables the register timer" || bad "register timer not enabled"
grep -qv 'enable --now aios-scheduled-ingest.service' "$STUBLOG" \
  && ! grep -q 'enable --now aios-scheduled-ingest.service' "$STUBLOG" \
  && ok "install does NOT enable a .service directly (the timer pulls it)" \
  || bad "a .service was enabled directly"
grep -q 'loginctl enable-linger' "$STUBLOG" \
  && ok "install enables lingering (or user timers never fire)" || bad "linger not enabled"
printf '%s' "$out" | grep -q 'ok — this host owns the timers and has them installed' \
  && ok "post-install status reads ok" || bad "post-install verdict wrong: $out"

# --- uninstall is allowed on the OWNER too ----------------------------------
out=$(run Linux thisbox uninstall)
[ "$(n_installed "$LX")" = 0 ] && ok "uninstall removes every unit file" \
                               || bad "units remained: $(n_installed "$LX")"
grep -q 'disable --now aios-scheduled-ingest.timer' "$STUBLOG" && ok "uninstall disables the ingest timer" || bad "ingest timer not disabled"
printf '%s' "$out" | grep -q 'UNWIRED' && ok "owner with nothing installed reports UNWIRED" || bad "expected UNWIRED: $out"

# --- ...and on a NON-owner, which is the whole point of the fallback ---------
# A machine that must be stopped is usually the one that is no longer the owner.
# If uninstall required ownership, the only way to stop a runaway scheduler
# would be to first hand it the vault.
marker thisbox
run Linux thisbox install >/dev/null
marker otherbox
out=$(run Linux thisbox uninstall)
[ "$(n_installed "$LX")" = 0 ] && ok "uninstall works on a NON-owner (the fallback case)" \
                               || bad "non-owner uninstall left files"
printf '%s' "$out" | grep -q 'not the owner, nothing installed here' \
  && ok "after a non-owner uninstall the verdict is silent-and-correct" || bad "wrong verdict: $out"

# --- the DOUBLE-SCHEDULER verdict -------------------------------------------
marker thisbox
run Linux thisbox install >/dev/null
marker otherbox
run Linux thisbox status | grep -q 'DOUBLE-SCHEDULER' \
  && ok "non-owner WITH timers installed reports DOUBLE-SCHEDULER" || bad "no DOUBLE-SCHEDULER verdict"
run Linux thisbox uninstall >/dev/null

# --- macOS branch: the rollback path ----------------------------------------
marker macbox
out=$(run Darwin macbox install)
[ "$(n_installed "$MC")" = 2 ] && ok "Darwin install copies the 2 plists" \
                               || bad "expected 2 plists, got $(n_installed "$MC")"
grep -q 'launchctl load' "$STUBLOG" && ok "Darwin install uses launchctl load" || bad "no launchctl load"
grep -q 'systemctl' "$STUBLOG" && bad "Darwin install shelled out to systemctl" || ok "Darwin install never calls systemctl"
[ "$(n_installed "$LX")" = 0 ] && ok "Darwin install did not touch the systemd dir" || bad "Darwin wrote systemd units"

out=$(run Darwin macbox uninstall)
grep -q 'launchctl unload' "$STUBLOG" && ok "Darwin uninstall uses launchctl unload" || bad "no launchctl unload"
[ "$(n_installed "$MC")" = 0 ] && ok "Darwin uninstall removes the plists" || bad "plists remained"

# --- preflight: can an UNATTENDED run reach the remote? ----------------------
# The 2026-09-05 cutover installed cleanly and the first fire committed without
# ever pushing, because a systemd user service has no ssh agent. install now
# proves the remote is reachable WITHOUT one before it wires anything.
marker thisbox
run Linux thisbox uninstall >/dev/null

GITRC=1; export GITRC
rc=$(rc_of Linux thisbox install)
[ "$rc" = 1 ] && ok "install REFUSES when the remote is unreachable agentless" \
              || bad "install proceeded despite a failing preflight (rc=$rc)"
[ "$(n_installed "$LX")" = 0 ] && ok "a failed preflight installs nothing" || bad "failed preflight still wired units"
run Linux thisbox install 2>&1 | grep -q 'deploy key' \
  && ok "the preflight failure names the deploy-key fix" || bad "failure message does not name the fix"
run Linux thisbox install 2>&1 | grep -q 'skip-preflight' \
  && ok "the preflight failure names the escape hatch" || bad "failure message hides --skip-preflight"

# The escape hatch must actually work — offline, or pushing by hand on purpose.
run Linux thisbox install --skip-preflight >/dev/null
[ "$(n_installed "$LX")" = 4 ] && ok "--skip-preflight installs anyway" || bad "--skip-preflight did not install"
run Linux thisbox uninstall >/dev/null

GITRC=0; export GITRC
out=$(run Linux thisbox install)
[ "$(n_installed "$LX")" = 4 ] && ok "a passing preflight lets install proceed" || bad "passing preflight blocked install"
printf '%s' "$out" | grep -q 'preflight  remote reachable' && ok "install reports the preflight passed" || bad "no preflight line"

# THE ASSERTION THAT MATTERS. A preflight run with the operator's agent still
# loaded would pass on a machine where every unattended fire fails — certifying
# the broken state rather than catching it.
grep -q 'fetch .*SSH_AUTH_SOCK=\[<unset>\]' "$STUBLOG" \
  && ok "the preflight fetch runs with SSH_AUTH_SOCK UNSET (as the unit does)" \
  || bad "preflight ran with an ssh agent still visible: $(grep fetch "$STUBLOG")"
grep -q 'fetch -q --dry-run origin' "$STUBLOG" \
  && ok "the preflight is a dry-run fetch (mutates no refs)" || bad "preflight is not a dry-run fetch"
run Linux thisbox uninstall >/dev/null

# uninstall must NOT preflight: stopping a machine can never depend on the
# network, or a broken box could not be stopped.
GITRC=1
run Linux thisbox install --skip-preflight >/dev/null
out=$(run Linux thisbox uninstall)
[ "$(n_installed "$LX")" = 0 ] && ok "uninstall works with the remote unreachable" || bad "uninstall blocked by a dead remote"
GITRC=0

# --- claim -------------------------------------------------------------------
marker oldbox
out=$(run Linux newbox claim)
grep -q '^newbox$' "$V/AIOS/Systems/scheduler-host" && ok "claim writes this host into the marker" || bad "claim did not write the host"
grep -q '^# rationale header' "$V/AIOS/Systems/scheduler-host" \
  && ok "claim preserves the marker's comment header" || bad "claim destroyed the rationale header"
[ "$(grep -cv '^#' "$V/AIOS/Systems/scheduler-host")" = 1 ] \
  && ok "claim leaves exactly one hostname line" || bad "marker has more than one hostname"
printf '%s' "$out" | grep -q 'UNINSTALL' && ok "claim warns to stop the old owner first" || bad "claim did not warn"
run Linux newbox claim | grep -q 'already the declared owner' \
  && ok "claiming twice is a no-op that says so" || bad "second claim not idempotent"

# --- an undeclared owner is BROKEN, not silently permissive ------------------
rm -f "$V/AIOS/Systems/scheduler-host"
run Linux thisbox status | grep -q 'BROKEN' && ok "a missing marker reports BROKEN" || bad "missing marker not reported"
rc=$(rc_of Linux thisbox install)
[ "$rc" = 1 ] && ok "install refuses when no owner is declared" || bad "install proceeded with no owner (rc=$rc)"

# --- an unknown subcommand is an error, not a silent status ------------------
rc=$(rc_of Linux thisbox frobnicate)
[ "$rc" = 1 ] && ok "an unknown subcommand exits 1" || bad "unknown subcommand did not fail (rc=$rc)"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
