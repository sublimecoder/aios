#!/usr/bin/env bash
# PreToolUse guard for Edit|Write|Bash. Enforces the CLAUDE.md contracts
# mechanically:
#   A. <scope>/sources/ is immutable (read-only curated input) — block ALL writes.
#   B. <scope>/notes/ holds your own hand-written notes — block AI-CREATED new
#      notes there (AI notes belong in <scope>/projects|content/ or AIOS/History/).
#   C. Cross-scope leak tripwire — block the most flagrant literal leaks at write
#      time, driven entirely by AIOS/Systems/layers.tsv. A cheap grep, not a
#      substitute for layer-leak-auditor's inferred pass.
#   D. Note identifier conventions — OPT-IN, off unless rules-lib.sh sets a glob.
#   E. Deliberate-edit files — the ones whose blast radius is every future
#      session. Refused as a side effect; edit them as their own task.
#   F. Bash writes to any path A-E cover are refused outright — see the rule.
#   G. Orchestrator-only files. A payload carrying an agent_id is a subagent and
#      is refused. See the rule for why.
# Blocks by exiting 2 with a message on stderr (fed back to the agent).
# ponytail: deny-list, not allowlist — guards the named harms only, so legit
# drafts (content/ drafts, .claude/ infra) never false-positive. Add zones if a
# leak shows one.
#
# Requires: jq, perl. Config: AIOS/Systems/layers.tsv (scopes and their tokens)
# and AIOS/Systems/hooks/rules-lib.sh (everything a scope table cannot express).

set -uo pipefail

input=$(cat)

# --- HARNESS NORMALIZATION ---------------------------------------------------
# This guard was written against Claude Code's PreToolUse payload. Another
# harness with a different payload shape does not fail loudly here — it enforces
# NOTHING, silently, and an unenforced rule looks exactly like an obeyed one.
# Two independent shape differences are each sufficient on their own:
#   1. the tool input arrives as the WHOLE object rather than under
#      `.tool_input`, so `.tool_input.file_path` is empty and every path rule
#      simply does not run;
#   2. the tool name arrives lowercase, so a `case` on "Bash" never matches and
#      Rule F's whole branch is skipped.
#
# FAILING OPEN IS THE ONE OUTCOME THIS FILE ARGUES AGAINST EVERYWHERE ELSE. The
# Edit/Write branch refuses when it cannot load rules-lib.sh, on the stated
# grounds that "a guard that cannot load its own rules and then permits the write
# is strictly worse than no guard." An unrecognised harness is that same state,
# reached through the front door instead.
#
# NORMALIZE, DO NOT BRANCH. Everything below — all seven rules, the perl program,
# the tests — keeps reading the Claude shape, and a third harness is a case arm
# here rather than an edit to any rule. Rewriting the payload is what keeps this
# from becoming two divergent guards.
#
# NOTE on the jq below: a missing key inside object construction does not yield a
# null member — it collapses the ENTIRE object to no output. `{a:1, b:(.missing
# // empty)}` prints nothing at all, so `$input` would become the empty string
# and every rule below would read an empty path and allow the write: precisely
# the silent fail-open this block exists to fix, reintroduced by the fix. Hence
# `// null` rather than `// empty`. Rule G's test is `-n "$(jq -r '.agent_id //
# empty')"`, and a JSON null renders as the empty string under `-r`, so `null`
# reads identically there.
if [ -z "$(printf '%s' "$input" | jq -r '.tool_input // empty')" ] &&
   [ -n "${JCODE_HOOK_TOOL_NAME:-}" ]; then
  input=$(printf '%s' "$input" | jq -c \
    --arg t "$JCODE_HOOK_TOOL_NAME" --arg c "${JCODE_HOOK_CWD:-}" \
    '{tool_name: $t, tool_input: ., cwd: (.cwd // $c), agent_id: (.agent_id // null)}')
fi

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
repo="${CLAUDE_PROJECT_DIR:-${JCODE_HOOK_CWD:-$PWD}}"

# --- DIFF-SHAPED TOOLS -------------------------------------------------------
# A `patch` / `apply_patch` tool takes a unified diff and names its targets
# INSIDE it. No `file_path` means `$path` is empty, which walks straight into
# this file's own "no path -> allow" line — so Rules A, B, C, D and E are ALL
# skipped by a tool the guard never knew existed.
#
# Handled by extracting what the rules need — the target paths and the ADDED
# lines — rather than by teaching each rule about diffs. Only `+` lines are fed
# to the content rules: a `-` line is text being REMOVED, and feeding it to the
# leak tripwire would refuse a diff that DELETES a leak.
#
# MULTI-FILE DIFFS ARE CHECKED ONE TARGET AT A TIME by re-invoking this guard
# per path with a synthesized Write payload. That reuses every rule verbatim
# instead of duplicating their logic against a second input shape — the same
# "normalize, do not branch" discipline as the harness block above. A refusal on
# ANY target refuses the whole call: a patch applies atomically, so partial
# approval is not a thing that exists.
if [ -z "$path" ]; then
  patch_text=$(printf '%s' "$input" | jq -r '.tool_input.patch_text // .tool_input.patch // .tool_input.diff // empty')
  if [ -n "$patch_text" ]; then
    added=$(printf '%s' "$patch_text" | sed -n 's/^+\([^+].*\)$/\1/p; s/^+$//p')
    targets=$(printf '%s' "$patch_text" \
      | sed -n 's|^+++ [ab]/\(.*\)$|\1|p; s|^+++ \([^ab/].*\)$|\1|p' \
      | sed 's/[[:space:]].*$//' | grep -v '^/dev/null$' | sort -u)
    for t in $targets; do
      case "$t" in /*) abs="$t" ;; *) abs="$repo/$t" ;; esac
      sub=$(jq -n --arg p "$abs" --arg c "$added" \
              --arg a "$(printf '%s' "$input" | jq -r '.agent_id // empty')" \
              '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}
               + (if $a == "" then {} else {agent_id:$a} end)')
      if ! err=$(printf '%s' "$sub" | CLAUDE_PROJECT_DIR="$repo" "$0" 2>&1); then
        printf '%s\n' "$err" >&2
        echo "(refused via patch_text: this diff writes '$t'. A diff-shaped tool names its targets inside the patch instead of in file_path, so the guard resolves each one and applies the same rules.)" >&2
        exit 2
      fi
    done
  fi
fi

# Canonicalize the tool name to the three spellings the rules below dispatch on.
# Case-insensitive rather than a per-harness map: harnesses have shipped both
# casings, and the cost of guessing wrong is a rule that does not run. MultiEdit
# collapses to Edit — it is a content write with the same rules, and leaving it
# unmapped means Rules C/D never see its bytes.
case "$(printf '%s' "$tool" | tr '[:upper:]' '[:lower:]')" in
  bash|shell|run_command)      tool="Bash"  ;;
  edit|multiedit|str_replace)  tool="Edit"  ;;
  *)                           tool="Write" ;;
esac

# --- VAULT ANCHORING ---------------------------------------------------------
# $CLAUDE_PROJECT_DIR is whatever repo the session started in, which is NOT the
# vault when an agent edits the vault from another repo. Re-anchor to the vault
# this guard lives in whenever the write actually targets it, so `rel` below is
# vault-relative and the scope rules see the path they expect.
GUARD_VAULT="$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
if [ -n "$GUARD_VAULT" ] && [ -f "$GUARD_VAULT/CLAUDE.md" ] && [ -d "$GUARD_VAULT/AIOS" ]; then
  case "$path" in
    "$GUARD_VAULT"/*) repo="$GUARD_VAULT" ;;
  esac
  if [ "$tool" = "Bash" ]; then
    case "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" in
      *"$GUARD_VAULT"/*) repo="$GUARD_VAULT" ;;
    esac
  fi
fi

# --- LOAD THE RULE PATTERNS (fail CLOSED) ------------------------------------
# See rules-lib.sh's header for why a command in that file is a session-wide
# hazard, and why the grep below runs BEFORE the dot-source.
RULES_LIB="$GUARD_VAULT/AIOS/Systems/hooks/rules-lib.sh"
rules_ok=yes
if [ ! -r "$RULES_LIB" ] || ! sh -n "$RULES_LIB" 2>/dev/null ||
   grep -qvE "^[[:space:]]*(#|\$)|^[A-Za-z_][A-Za-z0-9_]*='[^']*'[[:space:]]*\$" "$RULES_LIB" ||
   ! . "$RULES_LIB" 2>/dev/null ||
   [ -z "${AIOS_GUARDED_SEG:-}" ] || [ -z "${AIOS_GUARDED_AIOS:-}" ]; then
  rules_ok=no
fi

# --- LOAD THE SCOPE MANIFEST -------------------------------------------------
# Missing manifest = no scopes declared yet (a fresh clone before bootstrap), so
# there is nothing to guard and the scope rules stand down. An EXISTING manifest
# that cannot be read is the fail-open shape this file argues against, and is
# treated like an unloadable rules-lib.
MANIFEST="$repo/AIOS/Systems/layers.tsv"
scopes=(); globs=(); tokens=(); allows=()
if [ -e "$MANIFEST" ]; then
  if [ ! -r "$MANIFEST" ]; then
    rules_ok=no
  else
    while IFS=$'\t' read -r l lbl g t a; do
      case "$l" in ''|'#'*) continue;; esac
      [ -z "${g:-}" ] && continue
      scopes+=("$l"); globs+=("$g"); tokens+=("${t:--}"); allows+=("${a:--}")
    done < "$MANIFEST"
  fi
fi

# Rule F's scope alternation is DERIVED from column 1, so adding a scope needs no
# edit to rules-lib.sh. An explicit AIOS_GUARDED_SCOPES overrides it.
if [ -z "${AIOS_GUARDED_SCOPES:-}" ]; then
  AIOS_GUARDED_SCOPES=$(IFS='|'; printf '%s' "${scopes[*]:-}")
fi

# --- Rule G: orchestrator-only files -----------------------------------------
# Subagents run in parallel and concurrent edits to a shared map or log corrupt
# them. A subagent RETURNS the line in its report; the orchestrator applies it.
if [ -n "$(printf '%s' "$input" | jq -r '.agent_id // empty')" ] &&
   [ -n "${AIOS_ORCHESTRATOR_ONLY:-}" ] && [ "$rules_ok" = yes ]; then
  _rel_g="${path#"$repo"/}"
  _oldifs=$IFS; IFS='|'
  for _oo in $AIOS_ORCHESTRATOR_ONLY; do
    if [ "$_rel_g" = "$_oo" ] || [ "$path" = "$_oo" ]; then
      IFS=$_oldifs
      echo "BLOCKED: '$_rel_g' is orchestrator-only. Subagents run in parallel and concurrent edits to the shared map/log corrupt them. RETURN the line in your report instead — the orchestrator applies it. (If you are an ingest-worker: this is the HARD RULE in your agent file, now enforced at the write.)" >&2
      exit 2
    fi
  done
  IFS=$_oldifs
fi

# --- Rule F: Bash writes ------------------------------------------------------
if [ "$tool" = "Bash" ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  [ -z "$cmd" ] && exit 0
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
  # Rule F fails OPEN, deliberately: it is a redirection aid, not a boundary, and
  # blocking every Bash call when the rules cannot load would also block the
  # `git checkout` that repairs them.
  [ "$rules_ok" = no ] && exit 0
  [ -z "$AIOS_GUARDED_SCOPES" ] && [ -z "$AIOS_GUARDED_AIOS" ] && exit 0
  hit=$(printf '%s' "$cmd" | REPO="$repo" CWD="${cwd:-$repo}" \
        GL="$AIOS_GUARDED_SCOPES" GS="$AIOS_GUARDED_SEG" GA="$AIOS_GUARDED_AIOS" \
        perl -0777 -ne '
    my $orig     = $_;
    my $stripped = $orig;
    $stripped =~ s/\Q$ENV{REPO}\E\///g;
    my $L = $ENV{GL};   # scope dirs, alternation
    my $S = $ENV{GS};   # one path segment
    my $A = $ENV{GA};   # the individually-protected AIOS files
    my $guarded = qr{(?<![A-Za-z0-9_/.+-])(?:\./)?(?:(?:$L)/$S(?:/$S)*|$A)}i;
    my $q    = qr/\\?["\x27]/;
    my $flag = qr/(?:(?:-\S+|[0-9]+)\s+)*/;
    my $mk = sub {
      my $t = shift;
      return qr{(?|
          (?<![-<=|>])>>?\s*$q?($t)
        | \btee\b\s+$flag$q?($t)
        | \bsed\s+(?:-i\S*|--in-place(?:=\S*)?)\s+[^;|&]*\s$q?($t)
        | \bperl\s+(?-i:(?:-[a-z0-9.]+\s+)*-[a-z0-9.]*i[a-z0-9.]*)\s[^;|&]*\s$q?($t)
        | \b(?:rm|truncate)\b\s+$flag$q?($t)
        | \bmv\b\s+$flag(?:$q?($t)|\S+\s+$q?($t))
        | \bcp\b\s+$flag\S+\s+$q?($t)
        | (?:Path|open|file)\s*\(\s*$q($t)$q[^)]*\)\s*(?:\.\s*write_(?:text|bytes)|\s*,\s*$q[wa])
        | (?:writeFileSync|writeFile|File\.write|File\.open)\s*\(\s*$q($t)
        | shutil\.(?:copy|copy2|move)\s*\([^)]*$q($t)
        | open\s*\(\s*$q($t)$q\s*,\s*$q[wa]
      )}xi;
    };
    my $write = $mk->($guarded);
    if ($stripped =~ /$write/) { print $+; exit 0 }
    my $litonly = qr{
        \bgit\s+(?:checkout|restore)\b(?:\s+-\S+)*\s+(?:--\s+)?$q?($guarded)
      | \brm\s+-\S*r\S*\s+$flag$q?((?:$L)(?:/\*)?)(?![A-Za-z0-9_/.+-])
    }xi;
    if ($stripped =~ /$litonly/) { print $+; exit 0 }
    my $cds = ($orig =~ /(?:\A|[;&|(]\s*)\s*(?:cd|pushd|popd)(?:\s|;|\z)/);
    my $home = defined $ENV{HOME} ? $ENV{HOME} : "";
    my $any  = $mk->(qr{[^\s;|&<>()"\x27]+});
    my @cands;
    while ($orig =~ /$any/g) { push @cands, grep { defined } map { ${$_} } 1 .. $#+ }
    my $gres = qr{(?:$L)(?:/$S)*|$A}i;
    for my $c (@cands) {
      my $p = $c;
      $p =~ s{\A~(?=/)}{$home};
      $p =~ s{\A\$\{?HOME\}?(?=/)}{$home};
      if ($p !~ m{\A/}) {
        next if $cds;
        next unless length $ENV{CWD};
        $p = "$ENV{CWD}/$p";
        my $par = $p; $par =~ s{/[^/]*\z}{};
        next unless -d $par;
        next unless -f $p
                 || $p =~ m{[^/]\.[0-9A-Za-z]+\z}
                 || $c =~ m{\A\.{1,2}(?:/|\z)|/\z};
      }
      my @o;
      for my $s (split m{/}, $p) {
        next if $s eq "" || $s eq ".";
        if ($s eq "..") { pop @o if @o; next }
        push @o, $s;
      }
      $p = "/" . join("/", @o);
      next unless $p =~ s{\A\Q$ENV{REPO}\E/}{};
      if ($p =~ /\A(?:$gres)\z/i) { print $p; last }
    }
  ')
  if [ -n "$hit" ]; then
    echo "REFUSED (Rule F — a redirection aid, not a boundary): this Bash command writes to '$hit'. Rule F matches the command STRING, so a variable, \$(...), eval, a glob, a symlink or a cd inside this same command all walk past it — it is not a wall and is not trying to be one. Its one job is to send an ordinary vault write back through Edit or Write, where the guard actually sees the write: the PATH rules (sources/ immutability, the personal notes/ rule, the deliberate-edit files) and the CONTENT rules (the cross-scope leak tripwire, the note conventions) both run there, and neither can run on a shell string. Do that instead. The checks that really hold are those content rules, git recoverability, AIOS/Systems/aios-check.sh, the layer-leak-auditor subagent and AIOS/Skills/sanitize.md — so a write that evades this one is USUALLY caught later. Not always: an untracked file git never saw is not recoverable, and a gitignored path is invisible to every one of them. Do not read that list as full cover. If you are only READING from that path, redirect somewhere outside the scope dirs." >&2
    exit 2
  fi
  exit 0
fi

# --- Edit / Write ------------------------------------------------------------
[ -z "$path" ] && exit 0
rel="${path#"$repo"/}"

if [ "$rules_ok" = no ]; then
  echo "BLOCKED: the write guard could not load its rule patterns from '$RULES_LIB' (missing, unreadable, unparseable, or incomplete) or could not read AIOS/Systems/layers.tsv, so the content rules cannot run. Refusing the write rather than allowing it unchecked — a guard that cannot load its own rules and then permits the write only looks like enforcement. Bash is deliberately still allowed (Rule F fails OPEN, it is a redirection aid, not a boundary), so restore the file and retry: git checkout -- AIOS/Systems/hooks/rules-lib.sh" >&2
  exit 2
fi

new_bytes=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty')

# Which scope does this path belong to? First glob match wins. Computed once and
# reused by Rules A, B and C — the scope dirs are exactly what layers.tsv
# column 3 declares, so none of them carries its own hardcoded list.
own_scope=""; own_idx=-1
for i in "${!scopes[@]}"; do
  IFS='|' read -ra pats <<< "${globs[$i]}"
  for p in "${pats[@]}"; do
    # shellcheck disable=SC2053  # intentional glob match, not string equality
    if [[ "$rel" == $p ]]; then own_scope="${scopes[$i]}"; own_idx=$i; break 2; fi
  done
done

# Rule A: <scope>/sources/ is immutable.
if [ -n "$own_scope" ]; then
  case "$rel" in
    */sources/*)
      echo "BLOCKED: sources/ is immutable (read-only curated input per CLAUDE.md). Never edit or delete it — wiki notes summarize it and point back via the 'sources' frontmatter field." >&2
      exit 2
      ;;
  esac
fi

# Rule B: don't create NEW AI notes inside <scope>/notes/ (only fires on Write to
# a path that doesn't exist yet; editing an existing note is left to judgment).
if [ "$tool" = "Write" ] && [ -n "$new_bytes" ] && [ ! -e "$path" ] && [ -n "$own_scope" ]; then
  case "$rel" in
    */notes/*)
      echo "BLOCKED: '$rel' is a NEW note in a notes/ dir (your personal, timeless notes). AI-generated notes default to AIOS/History/; drafts belong in the scope's content/ or projects/ — propose edits to personal notes, don't create them there." >&2
      exit 2
      ;;
  esac
fi

# Rule E: files that may only be edited as their own deliberate task. BEFORE the
# content rules: this refusal is about the act, not the bytes, so it must fire
# even on a change whose content is clean.
if [ -n "${AIOS_DELIBERATE_EDIT_PATHS:-}" ]; then
  _oldifs=$IFS; IFS='|'
  for _de in $AIOS_DELIBERATE_EDIT_PATHS; do
    if [ "$rel" = "$_de" ]; then
      IFS=$_oldifs
      echo "BLOCKED: '$rel' is a deliberate-edit file — it steers every future session rather than this one (see AIOS/Systems/hooks/rules-lib.sh, AIOS_DELIBERATE_EDIT_PATHS). A change here silently changes work you have not started yet. Edit it as its own task, not as a side effect of this one. If you meant to change a rule, say so explicitly and apply the edit yourself." >&2
      exit 2
    fi
  done
  IFS=$_oldifs
fi

if [ "$rel" = "AIOS/Systems/hooks/rules-lib.sh" ]; then
  echo "BLOCKED: '$rel' holds the write guard's own rule patterns — the protected-path set, the deliberate-edit list, the orchestrator-only list and the optional note conventions. Every write in every session is decided by it, and it is dot-sourced by live PreToolUse hooks, so a bad line here can block or unblock everything at once. Edit it deliberately as its own task, apply the edit yourself, then re-verify and re-stamp: sh .claude/hooks/test_vault_write_guard.sh && shasum .claude/hooks/vault-write-guard.sh AIOS/Systems/hooks/rules-lib.sh > AIOS/Systems/guard.sha" >&2
  exit 2
fi

# Path is scaffolding or unclaimed → not scope content, nothing left to check.
[ -z "$own_scope" ] && exit 0
[ -z "$new_bytes" ] && exit 0

# Rule C: cross-scope leak tripwire, driven by layers.tsv.
allowed="|${allows[$own_idx]}|"
for i in "${!scopes[@]}"; do
  [ "$i" -eq "$own_idx" ] && continue
  other="${scopes[$i]}"
  [ "${tokens[$i]}" = "-" ] && continue                 # scope declares no tokens
  [[ "$allowed" == *"|$other|"* ]] && continue          # explicitly tolerated

  if printf '%s' "$new_bytes" | grep -qiE "${tokens[$i]}"; then
    echo "BLOCKED: '$rel' is ${own_scope}-scope content but names the ${other} scope. Those scopes are walled off from each other per CLAUDE.md and AIOS/Systems/layers.tsv. If this is a legitimate meta-mention (e.g. documenting the wall itself), write it under AIOS/ instead — that is scaffolding and is not guarded." >&2
    exit 2
  fi
done

# Rule D: note identifier conventions. OPT-IN — inert unless rules-lib.sh sets
# AIOS_NOTE_ID_GLOBS. Archived history is exempt: it records what happened, and
# rewriting an identifier out of a past digest falsifies the record.
if [ -n "${AIOS_NOTE_ID_GLOBS:-}" ]; then
  base=${rel##*/}
  dirpart=${rel%/*}
  parent=${dirpart##*/}
  arch=no
  case "$base" in
    source-history-[0-9][0-9][0-9][0-9]-[0-9][0-9].md) arch=yes ;;
  esac
  case "$parent" in
    _history) arch=yes ;;
  esac
  if [ "$arch" = no ]; then
    IFS='|' read -ra id_globs <<< "$AIOS_NOTE_ID_GLOBS"
    for p in "${id_globs[@]}"; do
      # shellcheck disable=SC2053
      [[ "$rel" == $p ]] || continue
      if [ -n "${AIOS_NOTE_PR_PATTERN:-}" ] && printf '%s' "$new_bytes" | grep -qiE "$AIOS_NOTE_PR_PATTERN"; then
        echo "BLOCKED: '$rel' is a project note but the new content contains a raw PR number ('PR #NNNN'). Note convention (AIOS_NOTE_ID_GLOBS in rules-lib.sh): stable ticket IDs only — raw PR/commit numbers live in the archived digests, not the wiki. Rephrase without the PR number." >&2
        exit 2
      fi
      if [ -n "${AIOS_NOTE_BARE_ISSUE_PATTERN:-}" ] && printf '%s' "$new_bytes" | grep -qE "$AIOS_NOTE_BARE_ISSUE_PATTERN"; then
        echo "BLOCKED: '$rel' is a project note but the new content contains a bare '#NNNN' reference. Note convention: stable ticket IDs only. A hex colour CONTAINING A LETTER (#1a2b3c, #0f0) is allowed; an all-numeric hex (#003366) is indistinguishable from an issue reference and is refused — use a named colour or a letter-bearing equivalent. For an HTML numeric entity (&#8217;), write the literal character instead." >&2
        exit 2
      fi
      break
    done
  fi
fi

exit 0
