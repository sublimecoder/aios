# Install — wiring repos, and the nightly loop

`/aios-bootstrap` builds the vault. This document covers the two things that make it *compound*: connecting your code repos, and scheduling the ingest.

Nothing here writes to a repo except `aios-wire-repo.sh`, and it only ever touches that repo's `.claude/settings.json`. The hooks it installs write **only to the vault**.

---

## 1. The loop

```
   code session in any repo
            │
            │  SessionStart → aios-context.sh
            │  loads that project's accumulated brain into the session
            ▼
        you work
            │
            │  Stop → aios-digest.sh
            │  appends a signal-only digest (branch, commits, diff-stat,
            │  changed native-memory files) to a queue in the vault
            ▼
     +/_sessions/<scope>/<project>.md
            │
            │  /aios-ingest  (nightly, or by hand)
            │  synthesizes the queue into durable facts
            ▼
   AIOS/Projects/<scope>/<project>.md  +  Knowledge Map  +  Log
            │
            └──────────► next session starts here, knowing more
```

The digest is **signal, not prose**. Meaning gets synthesized at ingest time, by a model that can see the whole queue at once — not scraped at commit time by one that can't.

A repo that isn't in the manifest is a **silent no-op**: no context loaded, no digest written. The scope is never guessed.

---

## 2. Wire a repo

```bash
scripts/aios-wire-repo.sh <repo-path> <scope> [project-slug]
```

For example:

```bash
scripts/aios-wire-repo.sh ~/code/acme-api work
scripts/aios-wire-repo.sh ~/code/side-thing personal my-side-thing
```

It does exactly two things, both idempotent:

1. **Adds a row** to `AIOS/Systems/repo-layers.tsv` — `<repo-dir><TAB><scope><TAB><project-slug>`.
   Column 1 is the directory **basename**, not the git remote name.
2. **Merges two hooks** into the repo's `.claude/settings.json`:
   - `SessionStart` → `aios-context.sh`
   - `Stop` → `aios-digest.sh`

It refuses to invent a scope: the scope must already exist in `AIOS/Systems/layers.tsv`, with its `me-<scope>.md`, `Sources/<scope>/`, and `AIOS/Projects/<scope>/`. It also refuses to remap a repo that's already mapped elsewhere, because `aios_lookup` takes the **first** matching row — a second row would sit there losing silently.

An existing `settings.json` is merged, never replaced. Invalid JSON is refused rather than overwritten.

### Check it

```bash
scripts/aios-wire-repo.sh --check ~/code/acme-api
```

```
repo:     /Users/you/code/acme-api
manifest: acme-api work acme-api
context:  wired
digest:   wired
```

Then start a session in the repo. `SessionStart` should print:

```
=== AIOS brain (work/acme-api) — auto-loaded from vault ===
```

**If it prints nothing**, the manifest row didn't match. The separators must be real tabs, and column 1 must be exactly the directory basename.

### Should `.claude/settings.json` be committed?

Commit it if your team shares the wiring. Keep it in `.git/info/exclude` if the vault is yours alone — the hook paths are absolute and point into *your* home directory.

---

## 3. Capture a fact mid-session

From inside any wired repo:

```
/aios-log the Postgres pool caps at 20; raising it starves pgbouncer
```

Auto-detects scope and project from the working directory, appends a dated `scope/project`-tagged line to `AIOS/History/Log.md`, updates `me-<scope>.md` if the fact is durable, and commits the vault. **It never touches the invoking repo.**

Use it when you learn something you'd otherwise re-learn in three weeks. The nightly ingest catches what you don't.

---

## 4. The nightly loop

Digests pile up in `+/_sessions/` and do nothing until they're ingested. Schedule it:

```bash
scripts/aios-install-nightly.sh           # 03:00 local
scripts/aios-install-nightly.sh 04:30     # or pick a time
```

macOS gets a launchd `LaunchAgent`; everything else gets a crontab line. Idempotent either way.

```bash
scripts/aios-install-nightly.sh --dry-run    # run the ingest once, right now
scripts/aios-install-nightly.sh --status     # scheduled? targeting which vault? last run?
scripts/aios-install-nightly.sh --uninstall
```

**A dry run on a clean vault logs `queue empty, skipping` and exits 0. That is a pass**, not a failure — the job is a no-op when there's nothing queued.

### What it actually runs

`claude -p "/aios-ingest"` unattended, with a scoped tool allowlist rather than `--dangerously-skip-permissions`:

```
--allowedTools "Read,Write,Edit,Grep,Glob,Bash,Task,TodoWrite"
```

Network and browser tools are denied by omission, so an unattended agent has no exfiltration surface. The `vault-write-guard` PreToolUse hook still constrains *where* writes land. It commits the vault; it never pushes.

`claude -p` exits 0 even when it dies on a session limit, so the exit code proves nothing. The script checks what actually matters — did the queue drain, and is the tree committed — and logs `FAILED` or `INCOMPLETE` when not.

### One schedule per machine

The launchd label (`com.aios.nightly-ingest`) and the crontab line are **global**. Two vaults on one machine cannot both hold the schedule: the second install would silently disable the first.

The installer therefore **fails closed**. If a job already exists and targets a different vault — or if it exists and the target can't be determined at all, as with an install predating the `AIOS_VAULT` env var — it refuses and tells you what's there. Override deliberately:

```bash
AIOS_FORCE=1 scripts/aios-install-nightly.sh 03:00
```

Logs land in `~/Library/Logs/` on macOS, else `$XDG_STATE_HOME/aios` (default `~/.local/state/aios`). Override with `AIOS_LOG_DIR`.

---

## 5. Run it by hand

Nothing here requires the scheduler. From the vault:

| Command | What |
|---|---|
| `/aios-ingest` | Compound the queued digests into project notes, Knowledge Map, and Log. |
| `/wiki-lint` | Health-check the wiki: schema, staleness, gaps, drift, orphans, duplicates, contradictions. Proposes; never edits. |
| `/aios-log <fact>` | Capture a fact. Works from the vault or any wired repo. |

`/aios-ingest` fans out one `ingest-worker` subagent per queued digest, so a backlog stays cheap. Shared files — `Knowledge Map`, `Log.md` — are written only by the orchestrator; parallel workers editing them would corrupt them.

---

## 6. Verify the whole loop end to end

```bash
# 1. Vault invariants hold.
bash .claude/hooks/test_vault_write_guard.sh      # 21 passed, 0 failed
bash scripts/test_aios_wire_repo.sh               # 14 passed, 0 failed
bash scripts/test_aios_install_nightly.sh         # 15 passed, 0 failed

# 2. A wired repo resolves.
scripts/aios-wire-repo.sh --check ~/code/<repo>

# 3. Work in that repo, exit the session, then confirm a digest queued:
ls -l "$AIOS_VAULT/+/_sessions/<scope>/<project>.md"

# 4. Drain it.
scripts/aios-install-nightly.sh --dry-run

# 5. The brain grew.
git -C "$AIOS_VAULT" log --oneline -3
```

If step 3 produces nothing, the `Stop` hook didn't fire or the repo isn't in the manifest — `--check` will say which.
