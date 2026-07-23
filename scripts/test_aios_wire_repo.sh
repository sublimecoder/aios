#!/usr/bin/env bash
# Self-check for aios-wire-repo.sh. Run: bash scripts/test_aios_wire_repo.sh
set -uo pipefail

WIRE="$(cd "$(dirname "$0")" && pwd)/aios-wire-repo.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Isolate git from the developer's machine. A global init.templateDir (or
# ~/.config/git/template) can seed .git/info/exclude with rules — including
# CLAUDE.local.md itself — which would make the ignore assertions below pass or
# fail for reasons that have nothing to do with this script.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
EMPTY_TMPL="$TMP/empty-template"; mkdir -p "$EMPTY_TMPL"
gitinit() { git -c init.templateDir="$EMPTY_TMPL" init -q "$1"; }

# Fake vault
V="$TMP/vault"; mkdir -p "$V/AIOS/Systems/hooks" "$V/AIOS/Systems/templates"
printf '# layer\tlabel\tglobs\ttokens\tallow\nwork\tWork\twork/*\t-\t-\n' > "$V/AIOS/Systems/layers.tsv"
printf '# repo-dir\tlayer\tproject-slug\n' > "$V/AIOS/Systems/repo-layers.tsv"
for h in aios-context.sh aios-digest.sh; do printf '#!/bin/sh\nexit 0\n' > "$V/AIOS/Systems/hooks/$h"; chmod +x "$V/AIOS/Systems/hooks/$h"; done
printf 'scope={{SCOPE}} project={{PROJECT}} vault={{VAULT}}\n' > "$V/AIOS/Systems/templates/CLAUDE.local.md.tmpl"

# Fake repo
R="$TMP/myrepo"; mkdir -p "$R"; gitinit "$R"

pass=0; fail=0
ok(){ pass=$((pass+1)); }
no(){ fail=$((fail+1)); echo "FAIL: $1"; }
run(){ AIOS_VAULT="$V" bash "$WIRE" "$@" >/dev/null 2>&1; }

# 1. Unknown scope is refused (never invent a scope).
run "$R" nosuchscope && no "unknown scope should be refused" || ok

# 2. Non-git dir is refused (digest hook needs git).
mkdir -p "$TMP/plain"
run "$TMP/plain" work && no "non-git dir should be refused" || ok

# 3. Happy path wires both manifest and settings.
run "$R" work || no "wire should succeed"
grep -qP '^myrepo\twork\tmyrepo$' "$V/AIOS/Systems/repo-layers.tsv" 2>/dev/null \
  || awk -F'\t' '$1=="myrepo" && $2=="work" && $3=="myrepo"{f=1} END{exit !f}' "$V/AIOS/Systems/repo-layers.tsv" \
  && ok || no "manifest row missing or not tab-separated"
jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("aios-context"))' "$R/.claude/settings.json" >/dev/null && ok || no "SessionStart hook not installed"
jq -e '[.hooks.Stop[].hooks[].command]         | any(test("aios-digest"))'  "$R/.claude/settings.json" >/dev/null && ok || no "Stop hook not installed"

# 4. Idempotent: second run changes nothing.
before=$(cat "$R/.claude/settings.json"; cat "$V/AIOS/Systems/repo-layers.tsv")
run "$R" work || no "second wire should succeed"
after=$(cat "$R/.claude/settings.json"; cat "$V/AIOS/Systems/repo-layers.tsv")
[ "$before" = "$after" ] && ok || no "second run mutated state (not idempotent)"
[ "$(awk -F'\t' '!/^#/ && $1=="myrepo"' "$V/AIOS/Systems/repo-layers.tsv" | wc -l | tr -d ' ')" = "1" ] && ok || no "duplicate manifest row"

# 5. Re-wiring the same repo under a DIFFERENT scope must refuse, not silently
#    add a second row (aios_lookup takes the first match — a stale row would win).
run "$R" work otherproject && no "conflicting remap should be refused" || ok

# 6. Existing unrelated settings.json content is preserved.
R2="$TMP/repo2"; mkdir -p "$R2/.claude"; gitinit "$R2"
echo '{"model":"claude-opus-4-8","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$R2/.claude/settings.json"
run "$R2" work
jq -e '.model == "claude-opus-4-8"' "$R2/.claude/settings.json" >/dev/null && ok || no "clobbered unrelated key (.model)"
jq -e '[.hooks.Stop[].hooks[].command] | any(test("echo mine"))' "$R2/.claude/settings.json" >/dev/null && ok || no "clobbered pre-existing Stop hook"
jq -e '[.hooks.Stop[].hooks[].command] | any(test("aios-digest"))' "$R2/.claude/settings.json" >/dev/null && ok || no "did not append digest hook alongside existing"

# 7. Invalid JSON is refused rather than overwritten.
R3="$TMP/repo3"; mkdir -p "$R3/.claude"; gitinit "$R3"
echo '{ not json' > "$R3/.claude/settings.json"
run "$R3" work && no "invalid JSON should be refused" || ok
grep -q 'not json' "$R3/.claude/settings.json" && ok || no "invalid settings.json was overwritten"

# 8. --check reports a missing manifest row rather than lying.
# NOTE: capture to a variable, don't pipe into `grep -q`. Under `set -o pipefail`,
# grep -q exits on first match and SIGPIPEs the producer, so the pipeline status
# becomes 141 whenever grep wins the race — a ~1-in-5 phantom failure.
R4="$TMP/repo4"; mkdir -p "$R4"; gitinit "$R4"
check_out=$(AIOS_VAULT="$V" bash "$WIRE" --check "$R4" 2>/dev/null)
case "$check_out" in *MISSING*) ok ;; *) no "--check should flag an unwired repo" ;; esac

# --- CLAUDE.local.md ---------------------------------------------------------

# 9. Written on wire, placeholders substituted.
md="$R/CLAUDE.local.md"
[ -f "$md" ] && ok || no "CLAUDE.local.md should be written"
grep -q "scope=work project=myrepo vault=$V" "$md" 2>/dev/null && ok || no "placeholders not substituted"
grep -q '{{' "$md" 2>/dev/null && no "unsubstituted {{placeholder}} left behind" || ok

# 10. It is git-ignored (so it can never be committed).
git -C "$R" check-ignore -q CLAUDE.local.md && ok || no "CLAUDE.local.md must be git-ignored"

# 11. NEVER overwrite a user's existing file — this is someone's private notes.
echo 'MY PRIVATE NOTES' > "$md"
run "$R" work
grep -q 'MY PRIVATE NOTES' "$md" && ok || no "existing CLAUDE.local.md was clobbered"

# 12. The ignore rule is added once, not appended on every re-wire.
n=$(grep -c '^CLAUDE\.local\.md$' "$R/.git/info/exclude" 2>/dev/null || echo 0)
[ "$n" -eq 1 ] && ok || no "exclude rule duplicated ($n copies)"

# 13. --no-claude-md skips the file entirely.
R5="$TMP/repo5"; mkdir -p "$R5"; gitinit "$R5"
AIOS_VAULT="$V" bash "$WIRE" --no-claude-md "$R5" work >/dev/null 2>&1
[ -f "$R5/CLAUDE.local.md" ] && no "--no-claude-md should skip the file" || ok
jq -e '[.hooks.Stop[].hooks[].command] | any(test("aios-digest"))' "$R5/.claude/settings.json" >/dev/null \
  && ok || no "--no-claude-md must still wire the hooks"

# 14. A repo that already ignores it via a tracked .gitignore is left alone
#     (we must not append a redundant .git/info/exclude rule).
R6="$TMP/repo6"; mkdir -p "$R6"; gitinit "$R6"
echo 'CLAUDE.local.md' > "$R6/.gitignore"
AIOS_VAULT="$V" bash "$WIRE" "$R6" work >/dev/null 2>&1
[ -f "$R6/CLAUDE.local.md" ] && ok || no "should still write the file"
grep -q 'CLAUDE.local.md' "$R6/.git/info/exclude" 2>/dev/null \
  && no "should not duplicate an ignore rule already in .gitignore" || ok

# 15. --check reports local-md state.
c=$(AIOS_VAULT="$V" bash "$WIRE" --check "$R6" 2>/dev/null)
case "$c" in *"local-md: present, git-ignored"*) ok ;; *) no "--check should report local-md as ignored" ;; esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
