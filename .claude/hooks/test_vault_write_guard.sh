#!/usr/bin/env bash
# Self-check for vault-write-guard.sh. Run: bash .claude/hooks/test_vault_write_guard.sh
# Builds a throwaway vault with a known layers.tsv and asserts each rule.
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/vault-write-guard.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/AIOS/Systems" "$TMP/Sources/alpha" "$TMP/Atlas/Alpha" "$TMP/Efforts/Work" "$TMP/Calendar"

printf '%s\n' \
  '# layer	label	content-globs	tokens	allow-from' \
  'alpha	Alpha	Atlas/Alpha/*|Sources/alpha/*	stagename|alpha\.example	-' \
  'beta	Beta	Efforts/Projects/*	realname|beta\.example	-' \
  'work	Work	Efforts/Work/*	acmecorp|codename9	beta' \
  > "$TMP/AIOS/Systems/layers.tsv"

pass=0; fail=0
# run <expect 0|2> <name> <tool> <relpath> <content> [field=content|new_string]
run() {
  local want=$1 name=$2 tool=$3 rel=$4 body=$5 field=${6:-content} got
  # CLAUDE_PROJECT_DIR must be exported for the GUARD, not just for jq.
  jq -n --arg t "$tool" --arg p "$TMP/$rel" --arg c "$body" --arg f "$field" \
    '{tool_name:$t, tool_input:({file_path:$p} + {($f):$c})}' \
    | CLAUDE_PROJECT_DIR="$TMP" bash "$GUARD" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: $name (want exit $want, got $got)"
  fi
}

# Rule A — Sources/ immutable.
run 2 "A: write into Sources/ blocked"        Write "Sources/alpha/raw.md" "anything"
run 2 "A: edit inside Sources/ blocked"       Edit  "Sources/alpha/raw.md" "anything"

# Rule B — no NEW ai notes in Atlas/, but editing an existing one is allowed.
run 2 "B: new note in Atlas/ blocked"         Write "Atlas/Alpha/fresh.md" "clean"
touch "$TMP/Atlas/Alpha/existing.md"
run 0 "B: existing Atlas note editable"       Write "Atlas/Alpha/existing.md" "clean"

# Rule C — cross-layer tokens.
# NOTE: use an EXISTING Atlas note, else Rule B blocks first and every Rule C
# assertion below would pass for the wrong reason.
touch "$TMP/Atlas/Alpha/n.md"
run 0 "C: clean alpha content allowed"        Write "Atlas/Alpha/n.md" "just notes"
run 2 "C: beta token in alpha content"        Write "Atlas/Alpha/n.md" "ask RealName about it"
run 2 "C: work token in alpha content"        Write "Atlas/Alpha/n.md" "shipped at AcmeCorp"
run 2 "C: case-insensitive match"             Write "Atlas/Alpha/n.md" "ACMECORP ships"
run 2 "C: regex token (beta.example)"         Write "Atlas/Alpha/n.md" "see beta.example/x"
run 0 "C: own-layer token is fine"            Write "Atlas/Alpha/n.md" "signed, StageName"
run 2 "C: Edit reads new_string field"        Edit  "Atlas/Alpha/n.md" "RealName" new_string
run 0 "C: Edit clean new_string allowed"      Edit  "Atlas/Alpha/n.md" "tidy up"  new_string

# Rule C — allow-from: work tolerates beta, but NOT the reverse.
run 0 "C: allow-from lets beta into work"     Write "Efforts/Work/w.md" "RealName leads this"
run 2 "C: work token still blocked in alpha"  Write "Atlas/Alpha/n.md" "codename9"
run 2 "C: alpha token blocked in work"        Write "Efforts/Work/w.md" "StageName was here"

# Scaffolding is unguarded by design (it documents the wall).
run 0 "scaffolding: AIOS/ unguarded"          Write "AIOS/Maps/x.md" "AcmeCorp and StageName"
run 0 "scaffolding: Calendar/ unguarded"      Write "Calendar/d.md"  "RealName and AcmeCorp"

# Unclaimed paths fall through.
run 0 "unclaimed path allowed"                Write "README.md" "AcmeCorp"

# --- The wall is OPT-IN: tokens="-" must make Rule C inert (the default config).
printf '%s\n' \
  '# layer	label	content-globs	tokens	allow-from' \
  'alpha	Alpha	Atlas/Alpha/*|Sources/alpha/*	-	-' \
  'beta	Beta	Efforts/Projects/*	-	-' \
  > "$TMP/AIOS/Systems/layers.tsv"

run 0 "wall off: other scope's name allowed"  Write "Atlas/Alpha/n.md" "RealName at AcmeCorp"
run 2 "wall off: Rule A still enforced"       Write "Sources/alpha/raw.md" "x"
run 2 "wall off: Rule B still enforced"       Write "Atlas/Alpha/brand-new.md" "x"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
