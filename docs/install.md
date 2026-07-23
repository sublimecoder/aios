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
   <scope>/projects/<project>.md  +  Knowledge Map  +  Log
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

It does exactly three things, all idempotent:

1. **Adds a row** to `AIOS/Systems/repo-layers.tsv` — `<repo-dir><TAB><scope><TAB><project-slug>`.
   Column 1 is the directory **basename**, not the git remote name.
2. **Merges two hooks** into the repo's `.claude/settings.json`:
   - `SessionStart` → `aios-context.sh`
   - `Stop` → `aios-digest.sh`
3. **Writes `CLAUDE.local.md`** in the repo and makes sure it's git-ignored. See below.

It refuses to invent a scope: the scope must already exist in `AIOS/Systems/layers.tsv`, with its `<scope>/me.md`, `<scope>/sources/`, and `<scope>/projects/`. It also refuses to remap a repo that's already mapped elsewhere, because `aios_lookup` takes the **first** matching row — a second row would sit there losing silently.

An existing `settings.json` is merged, never replaced. Invalid JSON is refused rather than overwritten. An existing `CLAUDE.local.md` is never touched.

Pass `--no-claude-md` to wire only the hooks and the manifest.

### Check it

```bash
scripts/aios-wire-repo.sh --check ~/code/acme-api
```

```
repo:     /Users/you/code/acme-api
manifest: acme-api work acme-api
context:  wired
digest:   wired
local-md: present, git-ignored
```

Then start a session in the repo. `SessionStart` should print:

```
=== AIOS brain (work/acme-api) — auto-loaded from vault ===
```

**If it prints nothing**, the manifest row didn't match. The separators must be real tabs, and column 1 must be exactly the directory basename.

### Should `.claude/settings.json` be committed?

Commit it if your team shares the wiring. Keep it in `.git/info/exclude` if the vault is yours alone — the hook paths are absolute and point into *your* home directory.

---

## 2b. `CLAUDE.local.md` — the durable pointer

The `SessionStart` hook injects the brain into every **interactive** session. That covers most of the time, and it's why `CLAUDE.local.md` deliberately does *not* duplicate that content.

What the hook doesn't cover: subagents, `claude -p` runs, other editors and tools, and any session where the hook isn't wired yet. In those contexts nothing tells the agent that a vault exists. `CLAUDE.local.md` does.

Claude Code loads memory files in a fixed order and **concatenates** them — enterprise policy, then `~/.claude/CLAUDE.md`, then the project's `CLAUDE.md`, then `CLAUDE.local.md`. Local instructions are the last thing read at each level, and they don't override the shared `CLAUDE.md`; both are in context. That's exactly the property you want here: the repo's own committed instructions stay authoritative, and your pointer at the vault rides alongside them.

The generated file records three things:

- **Which scope and project this repo maps to**, so the agent knows which `<scope>/me.md` governs it.
- **Where the brain, the identity file, and the log live** — as paths, plus an instruction not to re-read them if the hook already injected them.
- **That the vault is written through `/aios-log`, never by hand**, and that nothing gets copied between repo and vault manually.

It also carries a commented-out confidentiality block. Fill it in for any scope with proprietary or private material; delete it otherwise. Silence reads as "unknown."

### Why a prose pointer, not an `@` import

Claude Code supports `@path/to/file` imports in memory files: relative, absolute, and `~/`-relative paths all work, nesting up to four levels, and a `@path` inside backticks or a fenced code block is not treated as an import.

The template shows an import line but leaves it inert, in backticks. Two reasons:

1. **The hook already loads that content.** Importing `<scope>/me.md` on top of it is a second copy in context, for nothing.
2. **The behavior of an import pointing at a missing file is not documented.** A teammate who clones the repo without the vault — or keeps it at a different path — hits an unspecified failure. Prose degrades to a dead path in a comment. An import might not.

If you want the scope's rules loaded verbatim anyway, strip the backticks from that line. It's your machine.

### Keeping it out of git

The installer never edits a tracked `.gitignore`. If the file isn't already ignored, it appends `CLAUDE.local.md` to `.git/info/exclude`, which is local to your clone.

That's the right default when you're the only one using AIOS. If the whole team is, put `CLAUDE.local.md` in the shared `.gitignore` instead — the installer detects an existing ignore rule and won't add a duplicate.

Either way, `--check` will tell you if the file exists but is *not* ignored, which is the one state that gets someone's private notes committed.

> A global git `init.templateDir` can seed `.git/info/exclude` for every repo you create. If yours already ignores `CLAUDE.local.md`, the installer's ignore step correctly does nothing.

---

## 3. Capture a fact mid-session

From inside any wired repo:

```
/aios-log the Postgres pool caps at 20; raising it starves pgbouncer
```

Auto-detects scope and project from the working directory, appends a dated `scope/project`-tagged line to `AIOS/History/Log.md`, updates `<scope>/me.md` if the fact is durable, and commits the vault. **It never touches the invoking repo.**

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
bash scripts/test_aios_wire_repo.sh               # 25 passed, 0 failed
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
