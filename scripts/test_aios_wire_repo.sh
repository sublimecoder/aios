#!/usr/bin/env bash
# Self-check for aios-wire-repo.sh. Run: bash scripts/test_aios_wire_repo.sh
set -uo pipefail

WIRE="$(cd "$(dirname "$0")" && pwd)/aios-wire-repo.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Fake vault
V="$TMP/vault"; mkdir -p "$V/AIOS/Systems/hooks"
printf '# layer\tlabel\tglobs\ttokens\tallow\nwork\tWork\tEfforts/Work/*\t-\t-\n' > "$V/AIOS/Systems/layers.tsv"
printf '# repo-dir\tlayer\tproject-slug\n' > "$V/AIOS/Systems/repo-layers.tsv"
for h in aios-context.sh aios-digest.sh; do printf '#!/bin/sh\nexit 0\n' > "$V/AIOS/Systems/hooks/$h"; chmod +x "$V/AIOS/Systems/hooks/$h"; done

# Fake repo
R="$TMP/myrepo"; mkdir -p "$R"; git -C "$R" init -q

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
R2="$TMP/repo2"; mkdir -p "$R2/.claude"; git -C "$R2" init -q 2>/dev/null || { mkdir -p "$R2"; git -C "$R2" init -q; }
echo '{"model":"claude-opus-4-8","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > "$R2/.claude/settings.json"
run "$R2" work
jq -e '.model == "claude-opus-4-8"' "$R2/.claude/settings.json" >/dev/null && ok || no "clobbered unrelated key (.model)"
jq -e '[.hooks.Stop[].hooks[].command] | any(test("echo mine"))' "$R2/.claude/settings.json" >/dev/null && ok || no "clobbered pre-existing Stop hook"
jq -e '[.hooks.Stop[].hooks[].command] | any(test("aios-digest"))' "$R2/.claude/settings.json" >/dev/null && ok || no "did not append digest hook alongside existing"

# 7. Invalid JSON is refused rather than overwritten.
R3="$TMP/repo3"; mkdir -p "$R3/.claude"; git -C "$R3" init -q
echo '{ not json' > "$R3/.claude/settings.json"
run "$R3" work && no "invalid JSON should be refused" || ok
grep -q 'not json' "$R3/.claude/settings.json" && ok || no "invalid settings.json was overwritten"

# 8. --check reports a missing manifest row rather than lying.
# NOTE: capture to a variable, don't pipe into `grep -q`. Under `set -o pipefail`,
# grep -q exits on first match and SIGPIPEs the producer, so the pipeline status
# becomes 141 whenever grep wins the race — a ~1-in-5 phantom failure.
R4="$TMP/repo4"; mkdir -p "$R4"; git -C "$R4" init -q
check_out=$(AIOS_VAULT="$V" bash "$WIRE" --check "$R4" 2>/dev/null)
case "$check_out" in *MISSING*) ok ;; *) no "--check should flag an unwired repo" ;; esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
