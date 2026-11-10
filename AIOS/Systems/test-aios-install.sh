#!/bin/sh
# Self-check for aios-install.sh.
#
# The installer edits a REAL user config that holds keybindings, provider
# choices and everything else, so the properties worth proving are not "does it
# write the key" but: it never corrupts the file, it never loses unrelated
# content, it is idempotent, and a dry run touches nothing. Every case runs
# against a fixture config via AIOS_JCODE_CONFIG; $HOME is never touched.
set -u
HERE=$(CDPATH= cd "$(dirname "$0")" && pwd)
INST="$HERE/${INSTUT:-aios-install.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$2] got [$3])"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/config.toml"

# Skills and launchd are exercised by their own suites / are report-only, so
# point the skill projection at a throwaway dir to keep this suite hermetic.
#
# THE PATH STUB IS PART OF BEING HERMETIC, not a convenience. aios-install.sh
# skips the whole jcode section when `command -v jcode` misses AND no config
# exists -- correct behaviour, nothing to wire for an absent harness. But it made
# this suite's verdict depend on whether the DEVELOPER'S machine happens to have
# jcode installed: green on the Mac, and on Arch the fresh-machine case wired 0
# of 4 and failed. A gate that moves with host state is not a gate, and this one
# is named in the Omarchy port plan as the acceptance criterion for the whole
# Phase 1. So the harness supplies its own jcode and both branches get asserted.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/jcode"; chmod +x "$TMP/bin/jcode"
# The memory section reads repo-layers.tsv and edits each listed repo's
# settings.local.json, so the suite gets its OWN manifest, repos and memory base.
# Without AIOS_VAULT here an `--apply` below would rewrite the developer's real repos.
FV="$TMP/v"; MB="$TMP/mb"
mkdir -p "$FV/AIOS/Systems"
mkrepo() { # <dir> <ignore settings.local.json? 1|0>
  mkdir -p "$1/.claude"; git -C "$1" init -q
  [ "$2" = 1 ] && printf '.claude/settings.local.json\n' > "$1/.gitignore"
}
mkrepo "$TMP/r1" 1; mkrepo "$TMP/r2" 1
printf '{\n  "permissions": {"allow": ["Bash(ls)"]}\n}\n' > "$TMP/r2/.claude/settings.local.json"
printf 'r1\tmain\tr1\t%s\nr2\twork\tr2\t%s\tlocal-only\nr4\tmain\tr4\t%s\n' \
  "$TMP/r1" "$TMP/r2" "$TMP/not-cloned" > "$FV/AIOS/Systems/repo-layers.tsv"
R1STRAY="$MB/$(cd "$TMP/r1" && pwd -P | sed 's#[^a-zA-Z0-9]#-#g')/memory"
mkdir -p "$R1STRAY"
printf 'fact\n' > "$R1STRAY/fact.md"; printf -- '- [F](fact.md)\n' > "$R1STRAY/MEMORY.md"
# A project fragment: merged into the GLOBAL Claude settings, not the repo's own
# settings.local.json (the employer repo's autoMode rides this -- Claude Code
# only honours autoMode in the user-level settings.json).
mkdir -p "$FV/work/projects/r2"
printf '{"autoMode": {"allow": ["Bash(make test)"]}}\n' > "$FV/work/projects/r2/claude-settings.global.json"
r2before=$(cat "$TMP/r2/.claude/settings.local.json")
# Global Claude settings: the installer merges the vault's fragment into
# ~/.claude/settings.json, so every run below gets a FIXTURE file. It sits in a
# subdir so its backup does not collide with the jcode `ls "$TMP" | grep aios-bak`
# count further down.
CS="$TMP/claude/settings.json"; mkdir -p "$TMP/claude"
printf '{\n  "model": "opus",\n  "skillOverrides": {"mine": "on"}\n}\n' > "$CS"
printf '{"skillOverrides": {"noisy": "off"}}\n' > "$FV/AIOS/Systems/claude-settings.vault.json"
csbefore=$(cat "$CS")
run() { PATH="$TMP/bin:$PATH" AIOS_JCODE_CONFIG="$CFG" AIOS_LINK_DESTS="$TMP/skills" AIOS_VAULT="$FV" AIOS_MEMORY_BASE="$MB" AIOS_CLAUDE_SETTINGS="$CS" sh "$INST" "$@" 2>&1; }
# ...and the same call with jcode genuinely absent, for the skip case.
run_nojcode() { AIOS_JCODE_CONFIG="$CFG" AIOS_LINK_DESTS="$TMP/skills" AIOS_VAULT="$FV" AIOS_MEMORY_BASE="$MB" AIOS_CLAUDE_SETTINGS="$CS" \
                  env PATH="/usr/bin:/bin" sh "$INST" "$@" 2>&1; }

wired() { # how many of the three hooks point at the vault's scripts
  c=0
  grep -qE '^\s*pre_tool\s*=.*vault-write-guard\.sh'        "$CFG" 2>/dev/null && c=$((c+1))
  grep -qE '^\s*session_start\s*=.*aios-session-status\.sh' "$CFG" 2>/dev/null && c=$((c+1))
  grep -qE '^\s*session_end\s*=.*aios-digest\.sh'           "$CFG" 2>/dev/null && c=$((c+1))
  echo "$c"
}
valid() { python3 -c "import tomllib,sys;tomllib.load(open(sys.argv[1],'rb'))" "$CFG" 2>/dev/null && echo yes || echo no; }

echo "aios-install self-check"

# --- dry run is the DEFAULT and must write nothing ---------------------------
# The installer touches a file the user did not hand it, so an accidental
# invocation must be inert.
printf '[keybindings]\nscroll_up = "ctrl+k"\n' > "$CFG"
before=$(cat "$CFG")
out=$(run); rc=$?
chk "dry run exits 1 when changes are needed" "1" "$rc"
chk "dry run writes nothing"                  "$before" "$(cat "$CFG")"
chk "dry run says so"                         "1" "$(printf '%s' "$out" | grep -c 'DRY RUN')"
chk "dry run leaves repo settings alone"      "$r2before" "$(cat "$TMP/r2/.claude/settings.local.json")"
chk "dry run creates no settings file"         "no" "$([ -f "$TMP/r1/.claude/settings.local.json" ] && echo yes || echo no)"
chk "dry run leaves the local memory dir"      "yes" "$([ -d "$R1STRAY" ] && echo yes || echo no)"
chk "dry run leaves global settings alone"     "$csbefore" "$(cat "$CS")"

# --- apply, on a config that already has unrelated content -------------------
# The realistic case, and the one where a careless edit does damage.
out=$(run --apply); rc=$?
chk "apply exits 0"                    "0" "$rc"
chk "all three hooks wired"            "3" "$(wired)"
chk "result is valid TOML"             "yes" "$(valid)"
chk "pre-existing section survived"    "1" "$(grep -c 'scroll_up' "$CFG")"
chk "pre-existing section header kept" "1" "$(grep -c '\[keybindings\]' "$CFG")"
chk "a backup was written"             "1" "$(ls "$TMP" | grep -c 'aios-bak')"
chk "hooks landed inside [hooks]"      "1" "$(awk '/^\[hooks\]/{f=1;next} /^\[/{f=0} f&&/pre_tool[[:space:]]*=/{n++} END{print n+0}' "$CFG")"

# --- Claude Code memory -> vault ---------------------------------------------
# Every mapped repo's memory must resolve to the vault dir, a local-only repo
# (no committed settings.json) must also carry the context + digest hooks, and
# unrelated local settings must survive the JSON round trip.
jget() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))" "$@" 2>/dev/null; }
chk "r1 memory points at the vault"   "$FV/+/_sessions/.memory/main/r1" "$(jget "$TMP/r1/.claude/settings.local.json" "d['autoMemoryDirectory']")"
chk "r2 memory points at the vault"   "$FV/+/_sessions/.memory/work/r2" "$(jget "$TMP/r2/.claude/settings.local.json" "d['autoMemoryDirectory']")"
chk "r2 permissions survived"         "['Bash(ls)']" "$(jget "$TMP/r2/.claude/settings.local.json" "d['permissions']['allow']")"
chk "local-only r2 got the context hook" "True" "$(jget "$TMP/r2/.claude/settings.local.json" "any('aios-context.sh' in h['command'] for m in d['hooks']['SessionStart'] for h in m['hooks'])")"
chk "local-only r2 got the digest hook"  "True" "$(jget "$TMP/r2/.claude/settings.local.json" "any('aios-digest.sh' in h['command'] for m in d['hooks']['Stop'] for h in m['hooks'])")"
chk "r1 (committed wire) got no hooks"   "False" "$(jget "$TMP/r1/.claude/settings.local.json" "'hooks' in d")"
chk "local memory absorbed into vault"   "fact" "$(cat "$FV/+/_sessions/.memory/main/r1/fact.md" 2>/dev/null)"
chk "local memory dir moved aside"       "no" "$([ -d "$R1STRAY" ] && echo yes || echo no)"
chk "moved aside, not deleted"           "1" "$(ls -d "$R1STRAY".pre-vault-* 2>/dev/null | wc -l | tr -d ' ')"
chk "uncloned repo is skipped out loud"  "1" "$(printf '%s' "$out" | grep -c 'r4.*not cloned')"

# --- global Claude settings: vault-owned keys ---------------------------------
# Both the vault fragment (skillOverrides) and r2's project fragment (autoMode)
# need a change in this same run, and land on the same global target -- this is
# also the "two fragments both needing changes" case: exactly one backup, both
# keys land.
chk "vault override merged"             "off"  "$(jget "$CS" "d['skillOverrides']['noisy']")"
chk "machine-local override survived"   "on"   "$(jget "$CS" "d['skillOverrides']['mine']")"
chk "unowned key untouched"             "opus" "$(jget "$CS" "d['model']")"
chk "global settings backup written"    "1"    "$(ls "$TMP/claude" | grep -c 'settings.json.aios-bak')"
chk "r2's project fragment landed in global settings" "['Bash(make test)']" "$(jget "$CS" "d['autoMode']['allow']")"
chk "r2's own settings.local.json got no autoMode"    "False" "$(jget "$TMP/r2/.claude/settings.local.json" "'autoMode' in d")"
chk "r2 permissions still survived"      "['Bash(ls)']" "$(jget "$TMP/r2/.claude/settings.local.json" "d['permissions']['allow']")"
chk "r1 (no fragment) got no autoMode"   "False" "$(jget "$TMP/r1/.claude/settings.local.json" "'autoMode' in d")"
chk "no backup beside a repo settings file" "0" "$(ls "$TMP/r2/.claude" | grep -c 'aios-bak')"

# --- idempotence -------------------------------------------------------------
# Re-running must be a no-op, not a second copy of every key. This is what makes
# the installer safe to put in a bootstrap script or run after every update.
snap=$(cat "$CFG"); snap_r2=$(cat "$TMP/r2/.claude/settings.local.json"); snap_cs=$(cat "$CS")
out=$(run --apply); rc=$?
chk "second apply exits 0"                "0" "$rc"
chk "second apply changes nothing"        "$snap" "$(cat "$CFG")"
chk "second apply leaves repo settings byte-identical" "$snap_r2" "$(cat "$TMP/r2/.claude/settings.local.json")"
chk "second apply leaves global settings byte-identical" "$snap_cs" "$(cat "$CS")"
chk "second apply writes no second backup" "1" "$(ls "$TMP/claude" | grep -c 'settings.json.aios-bak')"
chk "second apply reports already wired"  "1" "$(printf '%s' "$out" | grep -c 'already wired')"
chk "no duplicate pre_tool keys"          "1" "$(grep -cE '^\s*pre_tool\s*=' "$CFG")"

# --- launchd advice is macOS-only --------------------------------------------
# On Linux the timers are systemd units (aios-scheduler.sh); launchctl advice there
# is noise. A dry run is enough: this section only reports.
out_os=$(AIOS_UNAME_S=Linux run)
chk "Linux run gives no launchctl advice"  "0" "$(printf '%s' "$out_os" | grep -c 'launchctl')"
chk "Linux run points at aios-scheduler"   "1" "$(printf '%s' "$out_os" | grep -c 'aios-scheduler.sh')"
out_os=$(AIOS_UNAME_S=Darwin run)
chk "macOS run still reports the plists"   "yes" "$(printf '%s' "$out_os" | grep -qE '\.plist' && echo yes || echo no)"
chk "macOS run has no Linux note"          "0" "$(printf '%s' "$out_os" | grep -c 'not macOS')"

# --- a hook wired to somebody else's script ---------------------------------
# Must be REPLACED, not left alone: a foreign pre_tool means the vault's rules do
# not run, which is the silent-unenforced state this whole effort exists to end.
printf '[hooks]\npre_tool = "~/bin/other.sh"\n' > "$CFG"
out=$(run)
chk "dry run flags a foreign hook for replacement" "1" "$(printf '%s' "$out" | grep -c 'REPLACE')"
run --apply >/dev/null
chk "foreign hook replaced"       "3" "$(wired)"
chk "no leftover foreign hook"    "0" "$(grep -c 'other.sh' "$CFG")"

# --- a config with [hooks] but no assignments -------------------------------
printf '[hooks]\n\n[display]\ndiff_mode = "inline"\n' > "$CFG"
run --apply >/dev/null
chk "empty [hooks] section gets filled" "3" "$(wired)"
chk "later section preserved"           "1" "$(grep -c 'diff_mode' "$CFG")"
chk "still valid TOML"                  "yes" "$(valid)"

# --- no config file at all (fresh machine) ----------------------------------
# The case the installer exists for. A missing file is not an error.
rm -f "$CFG"
rm -rf "$TMP/skills"
out=$(run --apply)
chk "creates a config when none exists" "3" "$(wired)"
chk "created config is valid TOML"      "yes" "$(valid)"

# --- ...and with jcode genuinely absent, the SAME fresh machine writes nothing -
# The other half of the branch above. An installer that conjures a config for a
# harness the machine does not have leaves a file nothing reads, and aios-check
# would then report it as wired.
rm -f "$CFG"
out_nj=$(run_nojcode --apply)
chk "absent jcode wires nothing"   "0"  "$(wired)"
chk "absent jcode creates no file" "no" "$([ -f "$CFG" ] && echo yes || echo no)"
printf '%s\n' "$out_nj" | grep -q 'jcode not installed' \
  && ok "absent jcode says so out loud" \
  || bad "absent jcode skipped silently — indistinguishable from success"
# The reported count must include the skills it linked, not just the hooks it
# wrote. A fresh machine that linked 42 skills and set 3 hooks reported "applied
# 3 change(s)" — the summary a user reads to decide whether it worked.
linked=$(printf '%s\n' "$out" | grep -cE '^  (LINK|ADOPT) ')
claimed=$(printf '%s\n' "$out" | sed -n 's/^aios-install: applied \([0-9]*\) change.*/\1/p')
if [ "${linked:-0}" -gt 0 ] && [ "${claimed:-0}" -ge "$linked" ]; then
  ok "the applied count includes linked skills (linked=$linked, reported=$claimed)"
else
  bad "the applied count undercounts: linked=$linked but reported=$claimed"
fi

# --- a malformed config must not be made worse ------------------------------
# Rolling back beats leaving a half-edited file: an unparseable config can break
# every jcode session on the machine, including the one needed to repair it.
printf '[hooks\nbroken = \n' > "$CFG"
broken=$(cat "$CFG")
run --apply >/dev/null 2>&1
if [ "$(valid)" = "yes" ] || [ "$(cat "$CFG")" = "$broken" ]; then
  ok "a malformed config is either fixed or left exactly as found (never half-edited)"
else
  bad "a malformed config was left in a third, different broken state"
fi

# --- a repo where settings.local.json is NOT gitignored ---------------------
# Writing it there creates a file one `git add -A` away from being committed,
# which would publish a machine path (and, for a local-only repo, the AIOS wire).
# GIT_CONFIG_GLOBAL + XDG_CONFIG_HOME: the global gitignores already ignore it,
# which would make this case pass on the developer machine by accident.
rm -f "$CFG"   # the malformed-config case above would stop the run before this section
rm -f "$CFG"   # the malformed-config case above would stop the run before this section
FV2="$TMP/v2"; mkdir -p "$FV2/AIOS/Systems"; mkrepo "$TMP/r3" 0
printf 'r3\tmain\tr3\t%s\n' "$TMP/r3" > "$FV2/AIOS/Systems/repo-layers.tsv"
out3=$(GIT_CONFIG_GLOBAL=/dev/null XDG_CONFIG_HOME="$TMP/xdg" PATH="$TMP/bin:$PATH" AIOS_JCODE_CONFIG="$CFG" AIOS_LINK_DESTS="$TMP/skills" AIOS_VAULT="$FV2" AIOS_MEMORY_BASE="$MB" AIOS_CLAUDE_SETTINGS="$CS" sh "$INST" --apply 2>&1)
chk "unignored settings.local.json is refused" "1" "$(printf '%s' "$out3" | grep -c 'REFUSE.*r3')"
chk "...and not written"                       "no" "$([ -f "$TMP/r3/.claude/settings.local.json" ] && echo yes || echo no)"

# --- a malformed project-level global fragment must be reported, never merged -
# Own fixture (FV4/CS4/r5): a malformed fragment in the main FV/CS fixtures would
# break the assertions above that depend on them. CS4 is pre-seeded to already
# match the vault fragment's merge result, so that fragment is a no-op ("ok") and
# the ONLY thing this run can write is r5's fragment -- isolating the INVALID
# branch to exactly the case being tested, so "byte-identical" below actually
# proves the malformed fragment landed nothing (not just that some other
# fragment happened not to need a change).
FV4="$TMP/v4"; mkdir -p "$FV4/AIOS/Systems"
: > "$FV4/AIOS/Systems/repo-layers.tsv"
mkdir -p "$FV4/work/projects/r5"
printf '{not json' > "$FV4/work/projects/r5/claude-settings.global.json"
printf '{"skillOverrides": {"noisy": "off"}}\n' > "$FV4/AIOS/Systems/claude-settings.vault.json"
CS4="$TMP/claude4/settings.json"; mkdir -p "$TMP/claude4"
printf '{\n  "model": "opus",\n  "skillOverrides": {"noisy": "off"}\n}\n' > "$CS4"
cs4before=$(cat "$CS4")
out4=$(PATH="$TMP/bin:$PATH" AIOS_JCODE_CONFIG="$TMP/config4.toml" AIOS_LINK_DESTS="$TMP/skills4" AIOS_VAULT="$FV4" AIOS_MEMORY_BASE="$MB" AIOS_CLAUDE_SETTINGS="$CS4" sh "$INST" --apply 2>&1); rc4=$?
chk "malformed project-level global fragment reports ERROR" "1" "$(printf '%s' "$out4" | grep -c 'ERROR.*work/projects/r5/claude-settings.global.json')"
chk "vault fragment (no change needed) still reported ok"   "1" "$(printf '%s' "$out4" | grep -c 'ok       .*claude-settings.vault.json')"
chk "malformed fragment left the global file byte-identical" "$cs4before" "$(cat "$CS4")"
chk "an ERROR run (INVALID JSON) exits 2, not 0"      "2" "$rc4"

# --- a crashing helper must not read as success (V1) --------------------------
# A PATH stub is the only hermetic way to make python3 itself fail (exit 1, no
# stdout) rather than merely report bad input -- the case a plain `$(...)` with
# no captured exit status reads as "nothing to change" and the run exits 0.
# Its own fixture, like FV4 above: an empty manifest and no jcode config means
# the ONLY python3 invocation on this run is the global-settings merge, so the
# ERROR line is unambiguous.
TMP5=$(mktemp -d)
mkdir -p "$TMP5/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP5/bin/python3"; chmod +x "$TMP5/bin/python3"
FV5="$TMP5/v"; mkdir -p "$FV5/AIOS/Systems"
: > "$FV5/AIOS/Systems/repo-layers.tsv"
CS5="$TMP5/claude/settings.json"; mkdir -p "$TMP5/claude"
printf '{"model":"opus"}\n' > "$CS5"
printf '{"skillOverrides":{"noisy":"off"}}\n' > "$FV5/AIOS/Systems/claude-settings.vault.json"
out5=$(PATH="$TMP5/bin:/usr/bin:/bin" AIOS_JCODE_CONFIG="$TMP5/config.toml" AIOS_LINK_DESTS="$TMP5/skills" AIOS_VAULT="$FV5" AIOS_MEMORY_BASE="$TMP5/mb" AIOS_CLAUDE_SETTINGS="$CS5" sh "$INST" --apply 2>&1); rc5=$?
chk "a crashing python3 is reported as ERROR, not silent success" "1" "$(printf '%s' "$out5" | grep -c 'ERROR.*crashed')"
chk "a crashing helper run exits 2"                               "2" "$rc5"
chk "global settings left untouched by a crashed merge"           '{"model":"opus"}' "$(cat "$CS5")"
rm -rf "$TMP5"

# --- a non-object JSON target (array/null) must be INVALID, not merged as {} --
FV6="$TMP/v6"; mkdir -p "$FV6/AIOS/Systems"
: > "$FV6/AIOS/Systems/repo-layers.tsv"
CS6="$TMP/claude6/settings.json"; mkdir -p "$TMP/claude6"
printf '[]\n' > "$CS6"
printf '{"skillOverrides":{"noisy":"off"}}\n' > "$FV6/AIOS/Systems/claude-settings.vault.json"
out6=$(AIOS_JCODE_CONFIG="$TMP/config6.toml" AIOS_LINK_DESTS="$TMP/skills6" AIOS_VAULT="$FV6" AIOS_MEMORY_BASE="$TMP/mb6" AIOS_CLAUDE_SETTINGS="$CS6" sh "$INST" --apply 2>&1); rc6=$?
chk "a JSON array target is INVALID, not silently merged into" "1" "$(printf '%s' "$out6" | grep -c "ERROR.*$CS6")"
chk "array-target run exits 2"                                  "2" "$rc6"
chk "array target left byte-identical"                          "[]" "$(cat "$CS6")"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
