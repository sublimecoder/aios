#!/usr/bin/env bash
# Self-check for vault-write-guard.sh. Run: bash .claude/hooks/test_vault_write_guard.sh
# Builds a throwaway vault with a known layers.tsv and asserts each rule.
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/vault-write-guard.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/AIOS/Systems" "$TMP/alpha/sources" "$TMP/alpha/notes" "$TMP/work/projects" "$TMP/archive"

printf '%s\n' \
  '# layer	label	content-globs	tokens	allow-from' \
  'alpha	Alpha	alpha/*	stagename|alpha\.example	-' \
  'beta	Beta	beta/*	realname|beta\.example	-' \
  'work	Work	work/*	acmecorp|codename9	beta' \
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

# Rule A — <scope>/sources/ immutable.
run 2 "A: write into sources/ blocked"        Write "alpha/sources/raw.md" "anything"
run 2 "A: edit inside sources/ blocked"       Edit  "alpha/sources/raw.md" "anything"

# Rule B — no NEW ai notes in <scope>/notes/, but editing an existing one is allowed.
run 2 "B: new note in notes/ blocked"         Write "alpha/notes/fresh.md" "clean"
touch "$TMP/alpha/notes/existing.md"
run 0 "B: existing notes/ note editable"      Write "alpha/notes/existing.md" "clean"

# Rule C — cross-scope tokens.
# NOTE: use an EXISTING notes/ file, else Rule B blocks first and every Rule C
# assertion below would pass for the wrong reason.
touch "$TMP/alpha/notes/n.md"
run 0 "C: clean alpha content allowed"        Write "alpha/notes/n.md" "just notes"
run 2 "C: beta token in alpha content"        Write "alpha/notes/n.md" "ask RealName about it"
run 2 "C: work token in alpha content"        Write "alpha/notes/n.md" "shipped at AcmeCorp"
run 2 "C: case-insensitive match"             Write "alpha/notes/n.md" "ACMECORP ships"
run 2 "C: regex token (beta.example)"         Write "alpha/notes/n.md" "see beta.example/x"
run 0 "C: own-scope token is fine"            Write "alpha/notes/n.md" "signed, StageName"
run 2 "C: Edit reads new_string field"        Edit  "alpha/notes/n.md" "RealName" new_string
run 0 "C: Edit clean new_string allowed"      Edit  "alpha/notes/n.md" "tidy up"  new_string
run 0 "C: scope-root me.md, own token fine"   Write "alpha/me.md" "I am StageName"
run 2 "C: scope-root me.md, other token"      Write "alpha/me.md" "aka RealName"

# Rule C — allow-from: work tolerates beta, but NOT the reverse.
run 0 "C: allow-from lets beta into work"     Write "work/projects/w.md" "RealName leads this"
run 2 "C: work token still blocked in alpha"  Write "alpha/notes/n.md" "codename9"
run 2 "C: alpha token blocked in work"        Write "work/projects/w.md" "StageName was here"

# Scaffolding is unguarded by design (it documents the wall).
run 0 "scaffolding: AIOS/ unguarded"          Write "AIOS/Maps/x.md" "AcmeCorp and StageName"
run 0 "scaffolding: archive/ unguarded"       Write "archive/d.md"   "RealName and AcmeCorp"

# Unclaimed paths fall through.
run 0 "unclaimed path allowed"                Write "README.md" "AcmeCorp"

# --- The wall is OPT-IN: tokens="-" must make Rule C inert (the default config).
printf '%s\n' \
  '# layer	label	content-globs	tokens	allow-from' \
  'alpha	Alpha	alpha/*	-	-' \
  'beta	Beta	beta/*	-	-' \
  > "$TMP/AIOS/Systems/layers.tsv"

run 0 "wall off: other scope's name allowed"  Write "alpha/notes/n.md" "RealName at AcmeCorp"
run 2 "wall off: Rule A still enforced"       Write "alpha/sources/raw.md" "x"
run 2 "wall off: Rule B still enforced"       Write "alpha/notes/brand-new.md" "x"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
