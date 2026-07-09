#!/usr/bin/env bash
# Self-check for aios-install-nightly.sh — the vault-detection and hijack guard.
# Never touches the real LaunchAgents dir or crontab: everything runs against a
# fake $HOME with a fake plist, and we only exercise the pure functions plus the
# guard's decision, never the launchctl/crontab writes.
#
# Run: bash scripts/test_aios_install_nightly.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/aios-install-nightly.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok(){ pass=$((pass+1)); }
no(){ fail=$((fail+1)); echo "FAIL: $1"; }

SUFFIX="/AIOS/Systems/hooks/aios-nightly-ingest.sh"

mkvault() { # mkvault <path>
  mkdir -p "$1/AIOS/Systems/hooks" "$1/+/_sessions"
  printf '#!/bin/sh\nexit 0\n' > "$1$SUFFIX"; chmod +x "$1$SUFFIX"
}

mkplist() { # mkplist <home> <script-path> [vault-env]
  mkdir -p "$1/Library/LaunchAgents"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    echo '<key>Label</key><string>com.aios.nightly-ingest</string>'
    echo '<key>ProgramArguments</key><array><string>/bin/sh</string>'
    echo "<string>$2</string></array>"
    if [ -n "${3:-}" ]; then
      echo "<key>EnvironmentVariables</key><dict><key>AIOS_VAULT</key><string>$3</string></dict>"
    fi
    echo '</dict></plist>'
  } > "$1/Library/LaunchAgents/com.aios.nightly-ingest.plist"
}

VA="$TMP/vaultA"; VB="$TMP/vaultB"
mkvault "$VA"; mkvault "$VB"

# --- 1. No job installed: install path proceeds past the guard.
H="$TMP/home1"; mkdir -p "$H/Library/Logs"
out=$(HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" --status 2>&1)
echo "$out" | grep -q 'not installed' && ok || no "clean home should report 'not installed'"

# --- 2. Modern plist (has AIOS_VAULT) for the SAME vault: status agrees, no warning.
H="$TMP/home2"; mkdir -p "$H/Library/Logs"; mkplist "$H" "$VA$SUFFIX" "$VA"
out=$(HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" --status 2>&1)
echo "$out" | grep -q "targets: $VA" && ok || no "should read AIOS_VAULT from plist"
echo "$out" | grep -q 'WARNING' && no "same vault must not warn" || ok

# --- 3. Modern plist for a DIFFERENT vault: status warns, install refuses.
H="$TMP/home3"; mkdir -p "$H/Library/Logs"; mkplist "$H" "$VB$SUFFIX" "$VB"
out=$(HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" --status 2>&1)
echo "$out" | grep -q 'WARNING' && ok || no "different vault should warn in --status"
HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" 03:00 >/dev/null 2>&1 \
  && no "install should refuse to hijack another vault" || ok

# --- 4. THE REGRESSION. Legacy plist with NO AIOS_VAULT env key (an older
#        install). The vault must still be derived from the script path, and the
#        guard must refuse rather than silently replacing the job.
H="$TMP/home4"; mkdir -p "$H/Library/Logs"; mkplist "$H" "$VB$SUFFIX"    # no env key
out=$(HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" --status 2>&1)
echo "$out" | grep -q "targets: $VB" && ok || no "must derive vault from ProgramArguments when env key absent"
echo "$out" | grep -q 'WARNING' && ok || no "legacy plist for another vault should warn"
before=$(cat "$H/Library/LaunchAgents/com.aios.nightly-ingest.plist")
HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" 03:00 >/dev/null 2>&1 \
  && no "install must refuse when a legacy job targets another vault" || ok
after=$(cat "$H/Library/LaunchAgents/com.aios.nightly-ingest.plist")
[ "$before" = "$after" ] && ok || no "refused install must not have rewritten the plist"

# --- 5. Unidentifiable job (weird script path, no env key): FAIL CLOSED.
H="$TMP/home5"; mkdir -p "$H/Library/Logs"; mkplist "$H" "/opt/somewhere/else.sh"
HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" 03:00 >/dev/null 2>&1 \
  && no "unidentifiable existing job must NOT be treated as free space" || ok
out=$(HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" 03:00 2>&1)
echo "$out" | grep -q 'could not be determined' && ok || no "should explain why it refused"

# --- 6. Bad times rejected before any write.
H="$TMP/home6"; mkdir -p "$H/Library/Logs"
for t in 25:00 9:5 xx:yy; do
  HOME="$H" AIOS_VAULT="$VA" bash "$SCRIPT" "$t" >/dev/null 2>&1 \
    && no "time '$t' should be rejected" || ok
done
[ -e "$H/Library/LaunchAgents/com.aios.nightly-ingest.plist" ] && no "rejected time still wrote a plist" || ok

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
