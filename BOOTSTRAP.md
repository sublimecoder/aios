# AIOS Bootstrap

**Paste this whole file into a fresh Claude Code session started inside your new AIOS vault.** (Or run `/aios-bootstrap`, which just reads this file.)

It interviews you, fills in the template, and leaves you with a working vault. Takes about ten minutes, most of it you answering questions.

---

You are bootstrapping a new AIOS vault — an AI Operating System stored as plain markdown. The template is already checked out in the current directory. Your job is to interview the user and turn the template into *their* vault.

## Rules for you, the agent

- **Interview first, write second.** Do not create a single file until you have the answers to Phase 1. Ask questions in small batches (2–4 at a time), not as one giant wall.
- **Default to less.** One scope, no wall, no optional subsystems. Add complexity only when the user's answers demand it. A vault they understand beats a vault that impresses them.
- **Never invent biography.** If you don't know something about the user, ask. A `me.md` with plausible-but-wrong facts is worse than an empty one.
- **Show, then apply.** Before writing `me.md` files, show the user a draft and let them correct it.
- **Placeholders are load-bearing.** Every `<angle-bracket>` and `<!-- BOOTSTRAP: ... -->` comment in the template must be either filled in or deleted. A shipped vault contains zero of them. Grep for both at the end.

## Phase 1 — Interview

### 1a. Scopes

A **scope** is a bucket of context — a job, a side project, a client, a life area. Its job is routing: it keeps one project's accumulated memory out of an unrelated one, and tells the AI which `me.md` file to read.

Ask:
- "What are the distinct contexts you want this vault to keep track of? For a lot of people that's just one. Common splits are work vs. personal, or one scope per client."
- For each: a short slug (`work`, `personal`, `acme`), a human label, and a one-line description of what it covers.

**One scope is the right answer for most people.** Do not talk them into more. If they hesitate, start with one — adding a scope later is a two-line edit to `AIOS/Systems/layers.tsv`.

### 1b. Strict separation (usually: skip this)

Only ask if they named two or more scopes:

> "Do any two of these need to be *kept secret from each other* — not just tidy, but genuinely never appearing in the same file? The usual reasons are a pen name that can't be linked to a legal name, employer code that can't reach a public portfolio or a job application, or one client's internals that can't surface in another's repo."

**If no** (the common case): leave every `tokens` column in `layers.tsv` as `-`. Delete the "Strict separation" section from `CLAUDE.md` and the commented block from `archive/Templates/me.template.md`. The write guard stays installed — Rules A and B (immutable `<scope>/sources/`, no AI-authored `<scope>/notes/` notes) are useful regardless — but its cross-scope check stays inert. Say plainly: "Wall left off. You can turn it on later by filling in the tokens column."

**If yes**, for each walled scope collect:
- The **identifying tokens**: names, brands, domains, codenames — the literal strings that give that scope away. These become a case-insensitive regex in column 4.
- Whether the wall is **symmetric** or **one-way**. One-way is common: a `work` scope may mention the person's real name (same legal person) while the `professional` scope must never mention the employer. That's `allow-from` in column 5.
- **The hardest crossing, in one sentence**, and why it matters. This goes verbatim into `CLAUDE.md`.

Then write those bullets into `CLAUDE.md`'s "Strict separation" section and each scope's `me.md`.

### 1c. Identity, per scope

For each scope, ask enough to write an honest `<scope>/me.md`:
- Who they are here (name or pseudonym, role, audience).
- What this scope covers, and what it explicitly does *not*.
- How they work: standards, non-negotiables, what good output looks like, what you must never do without asking.
- What's confidential by default. If nothing, say so — silence reads as "unknown".

### 1d. Repos

Ask which code repositories should feed knowledge back into this vault, and which scope each belongs to. For each: the directory basename (not the remote name), the scope slug, and a project slug.

Skip this entirely if they aren't wiring up repos yet. It's additive.

## Phase 2 — Write

Do these in order. Verify each before moving on.

1. **`AIOS/Systems/layers.tsv`** — one row per scope. Keep the comment header. Delete the example rows. `tokens` and `allow-from` are `-` unless 1b said otherwise.

2. **`<scope>/me.md`** — one per scope, from `archive/Templates/me.template.md` (the shipped `main/me.md` is that template with the `main` slug pre-filled — rename or copy the `main/` dir per scope). Fill every placeholder. Delete the "Strict separation" comment block if the wall is off. Show each draft to the user before writing.

3. **`CLAUDE.md`** — fill or delete the `<!-- BOOTSTRAP -->` blocks. If the wall is off, remove the "Strict separation" section entirely.

4. **`AIOS/Maps/Knowledge Map.md`** — one `##` heading per scope, each empty. Delete the BOOTSTRAP comment.

5. **`AIOS/Skills/style-guide-writing-me.md`** — their voice, in their words. If they don't have opinions yet, write "TBD" rather than inventing a style.

6. **Folders** — one top-level dir per scope, fixed shape: `<scope>/me.md` + `notes/` + `content/` + `projects/` + `sources/`, each dir with a `.gitkeep`. The shipped `main/` is the model; rename it for the first scope, copy the shape for the rest. **The `<slug>/*` globs in `layers.tsv` and the real dirs must agree** — a glob pointing at a dir that doesn't exist means the guard silently never matches that scope.

7. **`AIOS/Systems/repo-layers.tsv`** — one row per repo from 1d. Keep the header comment.

8. **`Home.md`** — a dashboard linking each `<scope>/me.md`, the three Maps, and the Log. Keep it short; it loads into context on every session start.

9. **Wire the cross-repo hooks** (skip if 1d was skipped). Do **not** hand-edit JSON — run the installer once per repo:

   ```bash
   scripts/aios-wire-repo.sh <repo-path> <scope> [project-slug]
   ```

   It adds the manifest row (real tabs), merges the `SessionStart` → `aios-context.sh` and `Stop` → `aios-digest.sh` hooks into that repo's `.claude/settings.json` preserving anything already there, and writes a git-ignored `CLAUDE.local.md` naming the scope and pointing at the vault. Idempotent. It refuses an unknown scope, a non-git directory, and a conflicting remap, and never overwrites an existing `CLAUDE.local.md`.

   The hook covers interactive sessions; `CLAUDE.local.md` covers the rest (subagents, `claude -p`, other editors). Fill in — or delete — its commented confidentiality block for each scope; leaving it blank reads as "unknown". Pass `--no-claude-md` to skip it.

   Both hooks write **only** to the vault, never to the invoking repo. Tell the user to set `AIOS_VAULT` in their shell rc if the vault isn't at `~/code/aios`.

   Note step 7 already wrote `repo-layers.tsv` rows by hand — running the installer afterward is still correct, it detects the existing row and only wires the settings. If you'd rather, skip step 7 and let the installer write both.

10. **Schedule the ingest**, so the queue drains and the vault compounds without anyone remembering to run it. Install ONE of the two — both draining one queue is the failure they exist to prevent:

   ```bash
   # default: launchd / systemd user timers, two jobs, one owning machine
   sh AIOS/Systems/aios-scheduler.sh claim      # then commit the marker
   sh AIOS/Systems/aios-scheduler.sh install
   sh AIOS/Systems/aios-scheduler.sh            # status; reads only

   # fallback, for a Linux box with no systemd user session: cron
   scripts/aios-install-nightly.sh              # 03:00 local
   scripts/aios-install-nightly.sh --status
   ```

   Ask before installing — it writes a LaunchAgent or a crontab line. If the user already runs a nightly ingest for a *different* vault on this machine, the installer refuses: the schedule name is global and installing would silently disable that one. Do not pass `AIOS_FORCE=1` on the user's behalf.

## Phase 3 — Verify

Run these. Do not report success until they pass. Paste the actual output.

```bash
# 1. The guard and the installers work.
bash .claude/hooks/test_vault_write_guard.sh
bash scripts/test_aios_wire_repo.sh
bash scripts/test_aios_install_nightly.sh

# 2. No placeholders survive.
grep -rn '<!-- BOOTSTRAP' . --exclude-dir=.git ; \
grep -rnE '<[a-z-]+>' CLAUDE.md */me.md AIOS/Maps/ 2>/dev/null

# 3. Every scope in layers.tsv has its dir with the fixed shape.
awk -F'\t' '!/^#/ && NF>=3 {print $1}' AIOS/Systems/layers.tsv | while read -r s; do
  [ -f "$s/me.md" ]        || echo "MISSING $s/me.md"
  for d in notes content projects sources; do
    [ -d "$s/$d" ]         || echo "MISSING $s/$d/"
  done
done

# 4. Every content-glob in layers.tsv points at a real folder.
awk -F'\t' '!/^#/ && NF>=3 {print $3}' AIOS/Systems/layers.tsv | tr '|' '\n' | sed 's#/\*$##' \
  | while read -r d; do [ -d "$d" ] || echo "GLOB has no folder: $d"; done

# 5. The template's own example rows are gone.
grep -nE '^(main|professional|pen|work)\b' AIOS/Systems/layers.tsv
```

Checks 2, 3, 4 must print nothing. Check 5 must print only the user's real scopes. Check 1 must end `N passed, 0 failed` for all three suites.

If repos were wired, also confirm each resolves:

```bash
awk -F'\t' '!/^#/ && NF>=3 {print $1}' AIOS/Systems/repo-layers.tsv | while read -r r; do
  scripts/aios-wire-repo.sh --check "$HOME/code/$r" 2>/dev/null | grep -q MISSING \
    && echo "UNWIRED: $r"
done
```

Then, if and only if the wall is on, dispatch the `layer-leak-auditor` subagent on `CLAUDE.md` and each `<scope>/me.md` and paste its verdict.

## Phase 4 — Commit and hand off

```bash
git add -A && git commit -m "aios: bootstrap vault"
```

Do **not** push. Do not create a remote. Tell the user:

> If any scope is private, keep this repo private. Git history is forever — a commit that exposed something can't be un-shared by a later fix.

Then give them a five-line "what now":
- `/aios-log <fact>` from any wired repo — captures a decision into the vault immediately.
- `/aios-ingest` from the vault — compounds queued session digests into project notes. The nightly job does this for you.
- `/wiki-lint` — periodic health check.
- `scripts/aios-wire-repo.sh <repo> <scope>` — connect another repo later.
- Drop a source file into `<scope>/sources/` and ask the AI to ingest it.
- Ask a question and watch it read `Knowledge Map` first.

Full wiring reference: `docs/install.md`.

---

## What you just installed

| Piece | What it does |
|---|---|
| `CLAUDE.md` | Entry point. The AI reads this first, every session. |
| `AIOS/Systems/layers.tsv` | Scopes. Drives routing, and the optional wall. |
| `<scope>/me.md` | Who you are in each context, and how you want to be worked with. |
| `AIOS/Maps/` | Vault Map (navigation) · Skill Map (what the AI can do) · Knowledge Map (what it knows). |
| `AIOS/Skills/` | Plain-markdown skills. Portable — not locked to any one AI tool. |
| `AIOS/Systems/hooks/` | The cross-repo wire: sessions in other repos feed this vault, never the reverse. |
| `.claude/agents/` | Subagents that keep read-heavy work out of your main context. |
| `.claude/hooks/vault-write-guard.sh` | Mechanically enforces: `<scope>/sources/` immutable, no AI-authored `<scope>/notes/` notes, and (optionally) the scope wall. |
| `scripts/aios-wire-repo.sh` | Connects a code repo to the vault, idempotently. Also writes its `CLAUDE.local.md`. |
| `AIOS/Systems/aios-scheduler.sh` | Default scheduler: two jobs, and only the machine named in `scheduler-host` may install them. |
| `scripts/aios-install-nightly.sh` | Cron fallback scheduler, for hosts without a systemd user session. |

The design bet: **a hand-curated `Knowledge Map` read first beats vector search** until you're well into the hundreds of notes. Embeddings are the last resort, not the default.
