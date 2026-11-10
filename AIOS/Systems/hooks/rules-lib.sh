#!/bin/sh
# AIOS hook rule patterns — the ONE place the guard's literal patterns live.
#
# SOURCED BY BOTH HALVES, on purpose:
#   .claude/hooks/vault-write-guard.sh          ENFORCES them at write time on
#                                               Edit/Write, by exiting 2.
#   (an optional after-the-fact observer)      RE-RUNS them against bytes that
#                                               landed via Bash, and only reports.
#                                               Not shipped here; the contract
#                                               below is what one must honour.
#
# WHY IT EXISTS. These were copy-pasted into both files, because the guard is a
# flat script with no sourceable functions. A copy drifts, and the two halves
# then disagree about what a violation is — the guard refuses a write the
# observer calls clean, or worse, the observer stays silent about bytes the
# guard would never have let through. Half-disabled reads exactly like working.
#
# WHAT LIVES HERE vs. IN layers.tsv. Your SCOPES and their leak tokens live in
# AIOS/Systems/layers.tsv, which both halves read directly — do not duplicate
# them here. This file carries only what a scope table cannot express: the
# individually-protected file list, the path shapes Rule F matches, and the
# optional note-identifier conventions.
#
# ONLY THE PATTERNS LIVE HERE. Each caller keeps its own control flow, its own
# wording, and its own failure direction — which are OPPOSITE, and both are
# deliberate. If this file is missing, unreadable or unparseable:
#   guard    — REFUSES the write (exit 2). A guard that cannot load its own rules
#              and then permits the write is strictly worse than no guard: it
#              looks like enforcement. It refuses Edit/Write only, never Bash, so
#              the `git checkout` that restores this file still runs.
#   observer — EXITS 0 and says so in its report. A detection hook that can halt
#              a session is worse than the hole it closes.
#
# ASSIGNMENTS ONLY — ENFORCED, not merely requested. This is dot-sourced into
# live PreToolUse hooks, so a command here runs on every write in every session.
# ONE blocking command substitution appended to this file is enough to hang the
# guard on Bash AND Write — a stall on every tool call, with no shell left to
# repair it. `sh -n` cannot see that; it is parse-only. The guard greps every
# line for `NAME=` (or blank/comment) BEFORE sourcing, and a violation routes to
# the already-handled unloadable path. Keep every line a plain assignment, and
# never add a pipeline, a substitution or a conditional.
#
# Values are single-quoted so backslashes and `$` stay literal. Most are EREs
# handed to `grep -E` / `grep -iE`; the AIOS_GUARDED_* trio below are perl
# fragments (noted there).
#
# Checksummed by AIOS/Systems/guard.sha, which stamps this file alongside the
# guard. Editing a pattern below therefore fails `aios-check.sh` until the pair
# is re-verified and re-stamped — the same deliberate-act shape Rule E gives the
# protected doctrine files. Re-stamp with:
#   sh .claude/hooks/test_vault_write_guard.sh &&
#     shasum .claude/hooks/vault-write-guard.sh AIOS/Systems/hooks/rules-lib.sh \
#       > AIOS/Systems/guard.sha

# --- Rule F: the guarded-path set --------------------------------------------
# THE ONE DEFINITION of what Rule F considers a guarded path, for the three
# consumers inside vault-write-guard.sh: the literal pattern, the bare scope-dir
# shape, and the anchored form the resolved-path pass tests against.
#
# NOT EREs, unlike everything below: these are fragments interpolated into perl
# patterns. They are written in the common subset (alternation, \., [ _]) so a
# `grep -E` consumer would also work, but perl is the only caller today.
#
# AIOS_GUARDED_SCOPES is DERIVED, not written here — the guard builds it from
# column 1 of AIOS/Systems/layers.tsv, so adding a scope needs no edit to this
# file. Set it to a literal alternation only if you deliberately want Rule F to
# cover a directory that is not a declared scope.
AIOS_GUARDED_SCOPES=''
AIOS_GUARDED_SEG='[A-Za-z0-9_.+-]+'

# Individually-protected files: paths Rule E refuses outright and Rule F treats
# as guarded. Extend it when a file starts steering more than the task editing
# it — a doctrine file your global agent config imports, a shared manifest.
AIOS_GUARDED_AIOS='AIOS/Systems/(effort-table|reasoning-doctrine|ponytail-amendment|plan-recon-amendment)\.md|AIOS/History/Log\.md|AIOS/Maps/Knowledge[ _]Map\.md'

# --- Rule E: files that may only be edited as their own deliberate task -------
# Shell-glob alternation, matched against the repo-relative path. These are the
# files whose blast radius is every future session rather than this one. Blank
# disables Rule E.
AIOS_DELIBERATE_EDIT_PATHS='AIOS/Systems/effort-table.md|AIOS/Systems/reasoning-doctrine.md|AIOS/Systems/ponytail-amendment.md|AIOS/Systems/plan-recon-amendment.md'

# --- Rule G: orchestrator-only files ------------------------------------------
# Shared files a subagent must never write: parallel subagents corrupt them with
# concurrent edits. A subagent returns the line in its report and the
# orchestrator applies it. Blank disables Rule G.
AIOS_ORCHESTRATOR_ONLY='AIOS/Maps/Knowledge Map.md|AIOS/History/Log.md'

# --- Rule D: note identifier conventions (OPT-IN, off by default) -------------
# Some vaults want project notes to carry only stable ticket IDs, keeping raw
# PR/issue numbers in the archived digests where they cannot rot. If that is you,
# set the scope glob and the patterns below; leaving AIOS_NOTE_ID_GLOBS blank
# disables Rule D entirely, which is the default.
#
# Example, for a vault whose `work` scope tracks ACME-#### tickets:
#   AIOS_NOTE_ID_GLOBS='work/projects/*|work/notes/*'
#   AIOS_NOTE_PR_PATTERN='PR ?#[0-9]+'
#   AIOS_NOTE_BARE_ISSUE_PATTERN='(^|[^A-Za-z0-9])#[0-9]+([^0-9A-Za-z]|$)'
AIOS_NOTE_ID_GLOBS=''
AIOS_NOTE_PR_PATTERN='PR ?#[0-9]+'
# Matched case-SENSITIVELY. A hex colour containing a letter (#1a2b3c, #0f0) is
# allowed; an all-numeric hex (#003366) is indistinguishable from an issue
# reference and is refused.
AIOS_NOTE_BARE_ISSUE_PATTERN='(^|[^A-Za-z0-9])#[0-9]+([^0-9A-Za-z]|$)'
