#!/bin/sh
# AIOS hook shared lib — the manifest parser, plus the BSD/GNU shim.
# ponytail: POSIX sh, no bashisms; macOS /bin/sh is fine.
AIOS_VAULT="${AIOS_VAULT:-$HOME/code/aios}"
AIOS_MANIFEST="$AIOS_VAULT/AIOS/Systems/repo-layers.tsv"

# --- OS shim -----------------------------------------------------------------
# The vault runs on macOS and on Omarchy/Arch from ONE branch. The OS delta is
# small enough to name in full, so this is two functions and a `uname` rather
# than an abstraction layer: everything else here is already POSIX-disciplined
# (pure-awk date math, mkdir locks, $CLAUDE_PROJECT_DIR in settings.json).
#
# WHY `stat` NEEDS A SHIM AT ALL, and why the old code's fallback was not one.
# Every site read `stat -f %m "$f" 2>/dev/null || date +%s`, which looks like it
# degrades safely and does not. On GNU coreutils `-f` means FILESYSTEM status:
# it EXITS 0 and prints `Type: tmpfs / Block size: 16384 …`, so the `||` branch
# never runs and that block of text flows into $(( )) as an arithmetic syntax
# error. Measured 2026-09-05 — test_hooks.sh reported `a stranded (stale) lock
# was treated as a live run`, i.e. the stale-lock guard silently inverted.
# A fallback that cannot fire is worse than no fallback, because it reads as
# cover in review.
case "$(uname -s)" in
  Darwin) AIOS_OS=darwin; AIOS_STAT_FLAG=-f; AIOS_STAT_SIG='%z:%m:%N' ;;
  *)      AIOS_OS=linux;  AIOS_STAT_FLAG=-c; AIOS_STAT_SIG='%s:%Y:%n' ;;
esac

# mtime <file> — epoch seconds of last modification. Prints nothing and returns
# nonzero when the file is absent, so `$(mtime f) || date +%s` degrades for real.
mtime() {
  if [ "$AIOS_OS" = darwin ]; then stat -f %m "$1" 2>/dev/null
  else                            stat -c %Y "$1" 2>/dev/null
  fi
}

# AIOS_STAT_FLAG / AIOS_STAT_SIG — for the ONE caller that stats a whole subtree
# through `find -exec` (aios-write-observer's nonreg_sig), where a shell function
# cannot be used. Colon-separated on purpose: the old format was space-separated
# and an unquoted expansion would word-split it. The exact spelling is free —
# the value is only ever hashed and compared pre-vs-post within a single process
# on a single machine, never across the two.

# nosleep <cmd>... — run cmd while holding off idle sleep, where the OS has such
# a thing. On Darwin this is load-bearing: launchd DarkWakes the Mac to fire a
# job and macOS re-sleeps ~40s later, killing any multi-minute `claude -p`
# stream. On Linux systemd does not sleep underneath a running user unit, so the
# bare call IS the correct behaviour, not a stub.
#
# DO NOT DELETE THE DARWIN BRANCH AS DEAD CODE. It is the hinge of the
# rollback runbook you keep beside the scheduler — timers can
# move back to the Mac with a one-line commit, and they need caffeinate to work.
nosleep() {
  if [ "$AIOS_OS" = darwin ]; then caffeinate -i "$@"
  else                            "$@"
  fi
}

# aios_log_dir — where the SCHEDULED jobs write their own log, their .lastrun /
# .lastweek stamps and their per-run transcripts. Not the same thing as the
# job's stdout, which systemd sends to the journal and launchd sent to a file.
#
# THE FAILURE THIS FIXES WAS SILENT AND IT LOOKED LIKE SUCCESS. Both wrappers
# hardcoded $HOME/Library/Logs, which does not exist on Linux. On the first fire
# after the Omarchy cutover the heartbeat append failed, the queue was counted
# correctly, the lock was taken -- and then the redirect of the agent's output to
# a transcript under that missing directory failed too, so `claude -p` NEVER RAN.
# The wrapper carried on and exited 0, systemd logged "Finished", and the queue
# sat undrained. An unattended job that no-ops and reports success is strictly
# worse than one that dies, because nothing downstream has anything to notice.
# Caught 2026-09-05 only because the cutover fired the service by hand instead of
# trusting 08:00 -- which is exactly what plan Task 2.5 asks for.
#
# XDG_STATE_HOME is the right home for this on Linux: logs that persist between
# runs and are not caches. Created here so no caller has to remember to.
aios_log_dir() {
  if [ "$AIOS_OS" = darwin ]; then _ald="$HOME/Library/Logs"
  else                             _ald="${XDG_STATE_HOME:-$HOME/.local/state}/aios"
  fi
  mkdir -p "$_ald" 2>/dev/null
  printf '%s' "$_ald"
}

# aios_expand_home <path> — expand a leading `~/` to $HOME, pass anything else
# through untouched.
#
# WHY THE MANIFEST NEEDS THIS. repo-layers.tsv column 4 held absolute
# /Users/you paths, which pin the file to one machine; the vault now runs on
# macOS and Arch off one branch. The obvious fix — write the rows `~/code/...` —
# is a SILENT NO-OP without this function: the shell does not expand a tilde that
# arrives as data, so `git -C '~/code/my-repo'` fails on BOTH machines, and
# it fails as "not a git repository", which reads like an unclonned repo rather
# than a path bug. Blanking the column instead is not the escape hatch either:
# aios_lookup reads $4 under awk's DEFAULT splitting, so an empty field slides
# column 5's `local-only` flag into REPO_PATH -- which test-resolve-project.sh
# already pins with `a flags column does not leak into REPO_PATH`.
#
# Both column-4 consumers must call this: resolve-project.sh (the CLI edge) and
# aios-check.sh's untracked-wire report, which does not source this file and so
# carries the same two lines inline.
aios_expand_home() {
  case "$1" in
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# aios_lookup <repo-path>: prints "LAYER PROJECT REPO_PATH" and returns 0 on a
# manifest hit; returns 1 (no output) if the repo is not listed. Layer is
# NEVER guessed.
#
# Tolerates a 3-field (repo/layer/project) OR 4-field (+ repo-path) manifest
# row — a partially-migrated manifest must never break the digest hooks. On a
# 3-field row REPO_PATH prints as an empty trailing field; existing callers
# that only read $1/$2 of the result are unaffected either way.
#
# Resolve a linked worktree back to its MAIN checkout before matching. A session
# run in <repo>/.claude/worktrees/<name> has a basename that is in no manifest, so
# the lookup missed and the Stop hook silently no-op'd — on 2026-07-31 that
# swallowed a full day of merged commits from one repo while its main checkout's
# state pointer sat unmoved for nine hours. --git-common-dir points at the main repo's .git for
# a linked worktree and at the repo's own .git otherwise, so this is a no-op for
# ordinary sessions. Non-git dirs keep the plain basename.
# aios_lookup_project <layer> <project>: the REVERSE of aios_lookup. Same output
# contract ("LAYER PROJECT REPO_PATH", 0 on a hit, 1 and silence on a miss), keyed
# on the layer/project pair instead of the repo directory.
#
# WHY IT EXISTS. `aios_lookup` maps a DIRECTORY to a layer/project, and an ingest
# holds the opposite — it knows `work` and `my-api` and has no dir at all.
# aios-ingest step 1b-ship nonetheless told runs to resolve the repo path "via
# resolve-project.sh", which returned `UNKNOWN_REPO=work` and exit 1 for that input,
# so every run fell back to grepping the manifest's 4th field by hand. That
# workaround was re-derived FIVE times in six days (2026-08-12 → 08-15) and lived
# only in the after-action register.
#
# It lives HERE, beside aios_lookup, because the invariant that matters is one
# manifest PARSER, not one function: a reverse lookup written into the CLI would be
# the second awk copy of the format, which is exactly what the 2026-07-31 worktree
# fix already got wrong once.
aios_lookup_project() {
  [ -f "$AIOS_MANIFEST" ] || return 1
  awk -v l="$1" -v p="$2" '
    /^[[:space:]]*#/   { next }
    NF < 3             { next }
    $2 == l && $3 == p { print $2, $3, (NF >= 4 ? $4 : ""); found=1; exit }
    END                { if (!found) exit 1 }
  ' "$AIOS_MANIFEST"
}

aios_lookup() {
  base=$(basename "$1")
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common" ] && base=$(basename "$(dirname "$common")")
  [ -f "$AIOS_MANIFEST" ] || return 1
  awk -v r="$base" '
    /^[[:space:]]*#/ { next }
    NF < 3           { next }
    $1 == r          { print $2, $3, (NF >= 4 ? $4 : ""); found=1; exit }
    END              { if (!found) exit 1 }
  ' "$AIOS_MANIFEST"
}

# ---------------------------------------------------------------- native memory
# THE VAULT DIR IS THE MEMORY STORE. Each mapped repo's untracked
# .claude/settings.local.json sets `autoMemoryDirectory` to
# `+/_sessions/.memory/<layer>/<project>` (aios-install.sh writes it), so Claude
# Code on every machine reads and writes one git-tracked dir and git moves it.
#
# WHY NOT THE OLD MIRROR. The Stop hook used to `rsync --delete` each machine's
# OWN ~/.claude/projects/<mangled>/memory over the vault copy. With two machines
# that is two sources of truth fighting: 2026-09-06 one digest deleted 289 of a
# project’s memory files and the next re-added them, and a fact written only
# on the other machine would have been deleted for good. Nothing ever flowed back,
# so every other machine ran on a stale local index.

aios_memory_dir() { # <layer> <project>
  printf '%s/+/_sessions/.memory/%s/%s' "$AIOS_VAULT" "$1" "$2"
}

# aios_main_root <path> — the MAIN checkout of the repo containing <path>,
# physical path. Claude Code keys memory off the git repo, so every worktree of
# a repo shares the main root's memory dir; a hook that mangled the worktree
# path looked for a dir that never exists.
aios_main_root() {
  _c=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (CDPATH= cd "$(dirname "$_c")" 2>/dev/null && pwd -P)
}

# aios_default_memory_dir <repo> — where Claude Code keeps memory when
# autoMemoryDirectory is NOT set: every non-alphanumeric char of the root -> '-'.
aios_default_memory_dir() {
  _r=$(aios_main_root "$1") || return 1
  printf '%s/%s/memory' "${AIOS_MEMORY_BASE:-$HOME/.claude/projects}" \
    "$(printf '%s' "$_r" | sed 's#[^a-zA-Z0-9]#-#g')"
}

# aios_memory_relocated <repo> — true when the repo's local settings point
# Claude Code's memory somewhere (aios-install.sh writes the vault dir there).
aios_memory_relocated() {
  _r=$(aios_main_root "$1") || return 1
  grep -q '"autoMemoryDirectory"' "$_r/.claude/settings.local.json" 2>/dev/null
}

# aios_absorb_memory <src> <dst> — fold a machine-local memory dir into the vault
# dir WITHOUT deleting or overwriting anything: new files are copied, MEMORY.md
# lines missing from the vault index are appended, and a same-name file whose
# content differs is left where it is and counted. Prints that count.
# ponytail: a vault fact deleted on purpose can come back once from a stale local
# dir; the relocation moves the local dir aside, so it happens at most once.
aios_absorb_memory() {
  _kept=0
  mkdir -p "$2"
  for _f in "$1"/*.md; do
    [ -f "$_f" ] || continue
    _b=$(basename "$_f")
    if [ "$_b" = MEMORY.md ]; then
      touch "$2/MEMORY.md"
      grep -vxF -f "$2/MEMORY.md" "$_f" >> "$2/MEMORY.md" || true
    elif [ ! -e "$2/$_b" ]; then
      cp "$_f" "$2/$_b"
    elif ! cmp -s "$_f" "$2/$_b"; then
      _kept=$((_kept + 1))
    fi
  done
  echo "$_kept"
}

# aios_vault_sync — SessionStart: commit any pending memory writes, pull --rebase,
# push what is ahead. Prints ONE warning line on failure and nothing on success,
# because its stdout is session context. Never blocks: no remote / no upstream /
# lock held by a concurrent session all return quietly.
#
# MEMORY.md conflicts cannot stop it: .gitattributes marks it merge=union, so two
# machines appending index lines merge to both. A conflict on a FACT file (both
# machines edited the same memory) aborts the rebase, leaves the vault clean and
# says so -- a mid-rebase vault or conflict markers in memory are both worse.
# aios_reap_sync_lock <lockdir> — remove the vault sync lock when it is older than
# 120s. Its holders (digest commit+push, session-start sync) finish in seconds; a
# lock that old belongs to a hook the harness killed at its timeout (10s on
# SessionStart, and a slow network pull can reach it). Unreaped, every later
# digest waits out its 10s and exits WITHOUT committing -- memory and digests
# would silently stop reaching the vault on that machine.
aios_reap_sync_lock() {
  _m=$(mtime "$1") || return 0
  [ $(( $(date +%s) - _m )) -gt 120 ] && rmdir "$1" 2>/dev/null
  return 0
}

aios_vault_sync() {
  _v=$AIOS_VAULT
  git -C "$_v" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || return 0
  _lock="$_v/.aios-sync.lock"; _i=0
  aios_reap_sync_lock "$_lock"
  until mkdir "$_lock" 2>/dev/null; do
    sleep 0.2; _i=$((_i + 1)); [ "$_i" -gt 25 ] && return 0
  done
  _mem="+/_sessions/.memory"
  # BatchMode: an ssh passphrase prompt would hang SessionStart until its timeout.
  export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ConnectTimeout=3 -o BatchMode=yes}"
  if [ -n "$(git -C "$_v" status --porcelain -uall -- "$_mem" 2>/dev/null)" ]; then
    git -C "$_v" add -- "$_mem" 2>/dev/null
    git -C "$_v" -c commit.gpgsign=false commit -q -m "aios: memory flush @ session start" -- "$_mem" >/dev/null 2>&1
  fi
  if ! git -C "$_v" diff --quiet HEAD 2>/dev/null; then
    echo "AIOS vault sync SKIPPED: uncommitted non-memory changes in $_v — memory from other machines may be stale until they are committed."
  elif ! _err=$(git -C "$_v" -c commit.gpgsign=false pull --rebase -q 2>&1); then
    git -C "$_v" rebase --abort >/dev/null 2>&1
    echo "AIOS vault sync FAILED (pull --rebase): $(printf '%s' "$_err" | tail -1) — memory may be stale; resolve with: git -C $_v pull --rebase"
  elif [ "$(git -C "$_v" rev-list --count '@{u}..HEAD' 2>/dev/null)" != 0 ]; then
    git -C "$_v" push -q >/dev/null 2>&1 \
      || echo "AIOS vault sync: local vault commits not pushed (push failed) — other machines will not see them yet."
  fi
  rmdir "$_lock" 2>/dev/null
  return 0
}
