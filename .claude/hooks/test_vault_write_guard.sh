#!/usr/bin/env bash
# Smoke test for vault-write-guard.sh (Rules A-G) plus the harness- and
# diff-shape normalization. One assert per rule, each with a control that fails
# if the rule starts over-matching, per ponytail's "leave one runnable check"
# rule for branch/security logic.
#
# HERMETIC BY CONSTRUCTION. The suite builds a throwaway vault in $TMP — its own
# layers.tsv, its own scope dirs — and runs a COPY of the live guard from inside
# it, so $TMP becomes the guard's own GUARD_VAULT and the fixtures decide the
# rules. Mutating the live guard in place would leave the repo bricked if the
# harness were killed before its restore trap ran, and a bricked guard blocks
# Edit, Write AND Bash, including the repair.
#
# The copy is verified byte-identical to the live file before anything runs: a
# suite that passes against a stale or broken copy is indistinguishable from a
# suite that passes.
set -e

HERE="$(CDPATH= cd "$(dirname "$0")" && pwd)"
LIVE_GUARD="${GUARD_UNDER_TEST:-$HERE/vault-write-guard.sh}"
LIVE_RULES="$HERE/../../AIOS/Systems/hooks/rules-lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TMP"

fail() { echo "FAIL: $1"; exit 1; }

# 0. THE GUARD MUST PARSE. This runs before every behavioural assertion because
# a guard that does not parse does not fail a test — it exits nonzero on EVERY
# PreToolUse call, which the harness reads as deny, so Edit, Write and Bash all
# stop working AND the repair is blocked too. Recovering needs a shell outside
# the session.
#
# The live trigger for this check: the Rule F regex sits inside a single-quoted
# shell string, and a comment added there containing one apostrophe closes the
# string mid-regex. Every assertion below would still pass against a COPY,
# because the copy would be equally broken and every write refused — which is
# indistinguishable from a very strict guard.
bash -n "$LIVE_GUARD" 2>/dev/null \
  || fail "the guard is not syntactically valid bash — it would refuse every Edit, Write and Bash call, including the one that fixes it. Check for an apostrophe or an unbalanced quote inside the single-quoted perl block."
sh -n "$LIVE_RULES" 2>/dev/null || fail "rules-lib.sh is not valid sh"
if grep -qvE "^[[:space:]]*(#|\$)|^[A-Za-z_][A-Za-z0-9_]*='[^']*'[[:space:]]*\$" "$LIVE_RULES"; then
  fail "rules-lib.sh contains a line that is not a plain assignment — it is dot-sourced into live hooks, so a command there runs on every write"
fi

# --- build the throwaway vault ----------------------------------------------
mkdir -p "$TMP/.claude/hooks" "$TMP/AIOS/Systems/hooks" "$TMP/AIOS/Maps" "$TMP/AIOS/History"
: > "$TMP/CLAUDE.md"
cp "$LIVE_GUARD" "$TMP/.claude/hooks/vault-write-guard.sh"
cp "$LIVE_RULES" "$TMP/AIOS/Systems/hooks/rules-lib.sh"
cmp -s "$LIVE_GUARD" "$TMP/.claude/hooks/vault-write-guard.sh" || fail "guard copy differs from the live guard"
HOOK="$TMP/.claude/hooks/vault-write-guard.sh"
chmod +x "$HOOK"

# Rule D ships OFF. Turn it on in the FIXTURE only, so the suite covers the code
# path without asserting a convention on vaults that never opt in.
printf "AIOS_NOTE_ID_GLOBS='work/projects/*|work/notes/*'\n" >> "$TMP/AIOS/Systems/hooks/rules-lib.sh"

# Two token-bearing scopes plus one with the wall off — the three shapes
# layers.tsv supports. `work` tolerates `public` one-way (column 5), which is
# what makes the asymmetry assertion below meaningful.
{
  printf '# fixture\n'
  printf 'public\tPublic\tpublic/*\tmyrealname|myblog\\.com\t-\n'
  printf 'pen\tPen\tpen/*\tpenname|pen\\.example\t-\n'
  printf 'work\tWork\twork/*\tacmecorp|projectfoxtrot\tpublic\n'
  printf 'open\tOpen\topen/*\t-\t-\n'
} > "$TMP/AIOS/Systems/layers.tsv"

mkdir -p "$TMP/public/notes" "$TMP/pen/notes" "$TMP/work/notes" "$TMP/work/projects" \
         "$TMP/work/sources" "$TMP/open/notes"
: > "$TMP/public/notes/x.md"; : > "$TMP/pen/notes/x.md"
: > "$TMP/work/projects/x.md"; : > "$TMP/open/notes/x.md"

run_write() { # $1=file_path $2=content -> exit code
  rc=0
  jq -n --arg p "$1" --arg c "$2" \
    '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
run_edit() { # $1=file_path $2=new_string -> exit code (Edit skips Rule B's new-file check)
  rc=0
  jq -n --arg p "$1" --arg s "$2" \
    '{tool_name:"Edit", tool_input:{file_path:$p, old_string:"old", new_string:$s}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}
run_bash() { # $1=command -> exit code
  rc=0
  jq -n --arg c "$1" --arg d "$TMP" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}' | "$HOOK" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# --- A: sources/ is immutable ------------------------------------------------
[ "$(run_edit "$TMP/work/sources/x.md" "anything")" = 2 ] \
  || fail "Rule A did not block a sources/ write"
[ "$(run_edit "$TMP/work/projects/x.md" "anything")" = 0 ] \
  || fail "Rule A over-matched: blocked an ordinary projects/ write"

# --- B: no NEW AI notes in notes/ --------------------------------------------
[ "$(run_write "$TMP/work/notes/NewOne.md" "anything")" = 2 ] \
  || fail "Rule B did not block a new notes/ note"
[ "$(run_edit "$TMP/public/notes/x.md" "an edit to an existing note")" = 0 ] \
  || fail "Rule B over-matched: blocked an EDIT to an existing note"

# --- C: cross-scope leak tripwire --------------------------------------------
[ "$(run_edit "$TMP/public/notes/x.md" "we deploy projectfoxtrot internally")" = 2 ] \
  || fail "Rule C did not block a work token in public content"
[ "$(run_edit "$TMP/pen/notes/x.md" "signed as myrealname")" = 2 ] \
  || fail "Rule C did not block a public token in pen content"
[ "$(run_edit "$TMP/public/notes/x.md" "penname posted today")" = 2 ] \
  || fail "Rule C did not block a pen token in public content"

# The wall is symmetric by default and one-way only where column 5 says so.
[ "$(run_edit "$TMP/work/projects/x.md" "reviewed by myrealname")" = 0 ] \
  || fail "Rule C ignored column 5: work tolerates public and must allow its tokens"
[ "$(run_edit "$TMP/public/notes/x.md" "acmecorp shipped it")" = 2 ] \
  || fail "Rule C made the allow-from exemption symmetric — it must be one-way"

# A scope with tokens '-' has the wall off and must never trigger on its own name.
[ "$(run_edit "$TMP/open/notes/x.md" "anything at all")" = 0 ] \
  || fail "Rule C fired for a scope whose tokens column is '-'"
# AIOS/ is scaffolding: it legitimately names every scope by design.
[ "$(run_write "$TMP/AIOS/Maps/Scratch.md" "acmecorp and penname and myrealname")" = 0 ] \
  || fail "Rule C guarded AIOS/ scaffolding, which must stay exempt"

# --- D: note identifier conventions (opt-in) ---------------------------------
[ "$(run_edit "$TMP/work/projects/x.md" "fixed in PR #1234")" = 2 ] \
  || fail "Rule D did not block a raw 'PR #NNNN' in a project note"
[ "$(run_edit "$TMP/work/projects/x.md" "reverted by #4521 last week")" = 2 ] \
  || fail "Rule D did not block a bare '#NNNN' in a project note"
[ "$(run_edit "$TMP/work/projects/x.md" "ACME-1508 landed on main")" = 0 ] \
  || fail "Rule D over-matched: blocked a bare ticket ID, the convention it exists to enforce"
[ "$(run_edit "$TMP/work/projects/x.md" "the accent is #1a2b3c")" = 0 ] \
  || fail "Rule D over-matched: a hex colour containing a letter must pass"
# A scope outside AIOS_NOTE_ID_GLOBS is not subject to the convention.
[ "$(run_edit "$TMP/open/notes/x.md" "fixed in PR #1234")" = 0 ] \
  || fail "Rule D fired outside AIOS_NOTE_ID_GLOBS"

# --- E: deliberate-edit files ------------------------------------------------
[ "$(run_edit "$TMP/AIOS/Systems/effort-table.md" "a clean, well-meant tweak")" = 2 ] \
  || fail "Rule E did not block an edit to a deliberate-edit file"
[ "$(run_edit "$TMP/AIOS/Systems/hooks/rules-lib.sh" "AIOS_GUARDED_SEG='x'")" = 2 ] \
  || fail "Rule E did not protect rules-lib.sh itself"

# --- F: Bash writes to guarded paths -----------------------------------------
[ "$(run_bash "echo hi >work/projects/x.md")" = 2 ] \
  || fail "Rule F did not refuse a redirection into a scope dir"
[ "$(run_bash "rm -rf work/")" = 2 ] \
  || fail "Rule F did not refuse a recursive delete of a scope dir"
[ "$(run_bash "sed -i 's/a/b/' work/projects/x.md")" = 2 ] \
  || fail "Rule F did not refuse an in-place sed on a scope file"
[ "$(run_bash "cat work/projects/x.md")" = 0 ] \
  || fail "Rule F refused a READ — it guards writes only"
[ "$(run_bash "echo hi >/tmp/aios-scratch-probe.md")" = 0 ] \
  || fail "Rule F refused a write outside the vault"

# --- G: orchestrator-only files ----------------------------------------------
rc=0
jq -n --arg p "$TMP/AIOS/History/Log.md" \
  '{tool_name:"Write", tool_input:{file_path:$p, content:"a line"}, agent_id:"sub-1"}' \
  | "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "Rule G let a SUBAGENT write an orchestrator-only file"
[ "$(run_write "$TMP/AIOS/History/Log.md" "a line")" = 0 ] \
  || fail "Rule G blocked the ORCHESTRATOR — it must only refuse payloads carrying an agent_id"

# --- FAIL CLOSED WHEN THE RULES CANNOT LOAD ----------------------------------
# A guard that cannot load its own rules and then permits the write is strictly
# worse than no guard: it looks like enforcement.
mv "$TMP/AIOS/Systems/hooks/rules-lib.sh" "$TMP/AIOS/Systems/hooks/rules-lib.off"
[ "$(run_edit "$TMP/work/projects/x.md" "anything")" = 2 ] \
  || fail "the guard ALLOWED a write with rules-lib.sh missing — it must fail closed"
# Bash is the deliberate exception: Rule F is a redirection aid, not a boundary,
# and refusing every Bash call would also block the repair.
[ "$(run_bash "git checkout -- AIOS/Systems/hooks/rules-lib.sh")" = 0 ] \
  || fail "the guard refused the Bash call that repairs it — Rule F must fail OPEN"
mv "$TMP/AIOS/Systems/hooks/rules-lib.off" "$TMP/AIOS/Systems/hooks/rules-lib.sh"

# A rules-lib carrying anything but assignments is treated as unloadable, BEFORE
# it is sourced — one blocking command substitution there hangs every tool call.
cp "$TMP/AIOS/Systems/hooks/rules-lib.sh" "$TMP/rules.bak"
printf 'echo hello\n' >> "$TMP/AIOS/Systems/hooks/rules-lib.sh"
[ "$(run_edit "$TMP/work/projects/x.md" "anything")" = 2 ] \
  || fail "a rules-lib.sh containing a COMMAND was sourced anyway"
cp "$TMP/rules.bak" "$TMP/AIOS/Systems/hooks/rules-lib.sh"

# --- HARNESS NORMALIZATION ---------------------------------------------------
# A harness that hands the tool input as the whole object, with a lowercase tool
# name, must hit the same rules rather than silently enforcing nothing.
rc=0
jq -n --arg p "$TMP/work/sources/x.md" '{file_path:$p, content:"x"}' \
  | JCODE_HOOK_TOOL_NAME=write JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "an alternate harness payload bypassed Rule A entirely"

rc=0
jq -n --arg c "echo hi >work/projects/x.md" --arg d "$TMP" '{command:$c, cwd:$d}' \
  | JCODE_HOOK_TOOL_NAME=bash JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a lowercase 'bash' tool name skipped Rule F's whole branch"

# --- DIFF-SHAPED TOOLS -------------------------------------------------------
# A patch tool names its targets inside the diff. No file_path means every path
# rule is skipped unless the targets are extracted.
diff_blocked=$(printf '%s\n' \
  '--- a/work/sources/x.md' '+++ b/work/sources/x.md' '@@ -1 +1 @@' '-old' '+new')
rc=0
jq -n --arg d "$diff_blocked" '{patch_text:$d}' \
  | JCODE_HOOK_TOOL_NAME=patch JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a unified diff targeting sources/ walked past every path rule"

# Only ADDED lines reach the content rules: a diff that DELETES a leak is a fix,
# and refusing it would pin the leak in place.
diff_removes=$(printf '%s\n' \
  '--- a/public/notes/x.md' '+++ b/public/notes/x.md' '@@ -1 +1 @@' '-acmecorp is our vendor' '+our vendor')
rc=0
jq -n --arg d "$diff_removes" '{patch_text:$d}' \
  | JCODE_HOOK_TOOL_NAME=patch JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "the guard refused a diff that REMOVES a leak — only '+' lines are content"

# A tool with no path and no diff is not a write and must not be refused.
rc=0
printf '%s' '{"intent":"just looking"}' \
  | JCODE_HOOK_TOOL_NAME=patch JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "refused a payload carrying neither a path nor a diff"

# --- UNKNOWN TOOL NAMES FAIL CLOSED ------------------------------------------
# Rule B dispatches on the tool name, so a CREATING tool spelled anything else
# walks past it. Unknown names default to Write; this pins that a future harness
# verb is covered on arrival rather than after an incident, and that read-only
# tools are NOT swept in by that default.
for t in patch apply_patch create_file new_file overwrite some_future_writer; do
  rc=0
  jq -n --arg p "$TMP/work/notes/Another.md" '{file_path:$p, content:"x"}' \
    | JCODE_HOOK_TOOL_NAME="$t" JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "unknown tool '$t' bypassed Rule B (the default must fail closed)"
done
for t in read grep glob ls webfetch; do
  rc=0
  jq -n --arg p "$TMP/work/notes/DoesNotExist.md" '{file_path:$p}' \
    | JCODE_HOOK_TOOL_NAME="$t" JCODE_HOOK_CWD="$TMP" "$HOOK" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] || fail "read-only tool '$t' was refused — the fail-closed default must not catch reads"
done

# --- NO MANIFEST = NO SCOPES -------------------------------------------------
# A fresh clone before bootstrap has nothing to guard. But a manifest that EXISTS
# and cannot be read is the fail-open shape this file argues against.
mv "$TMP/AIOS/Systems/layers.tsv" "$TMP/layers.bak"
[ "$(run_edit "$TMP/work/projects/x.md" "acmecorp and penname")" = 0 ] \
  || fail "the guard refused a write with NO manifest — undeclared scopes are not guarded scopes"
mv "$TMP/layers.bak" "$TMP/AIOS/Systems/layers.tsv"

echo "ALL PASS"
