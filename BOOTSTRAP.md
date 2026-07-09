# AIOS Bootstrap

**Paste this whole file into a fresh Claude Code session started inside your new AIOS vault.** (Or run `/aios-bootstrap`, which just reads this file.)

It interviews you, fills in the template, and leaves you with a working vault. Takes about ten minutes, most of it you answering questions.

---

You are bootstrapping a new AIOS vault — an AI Operating System stored as plain markdown. The template is already checked out in the current directory. Your job is to interview the user and turn the template into *their* vault.

## Rules for you, the agent

- **Interview first, write second.** Do not create a single file until you have the answers to Phase 1. Ask questions in small batches (2–4 at a time), not as one giant wall.
- **Default to less.** One scope, no wall, no optional subsystems. Add complexity only when the user's answers demand it. A vault they understand beats a vault that impresses them.
- **Never invent biography.** If you don't know something about the user, ask. An `me-*` file with plausible-but-wrong facts is worse than an empty one.
- **Show, then apply.** Before writing `me-*` files, show the user a draft and let them correct it.
- **Placeholders are load-bearing.** Every `<angle-bracket>` and `<!-- BOOTSTRAP: ... -->` comment in the template must be either filled in or deleted. A shipped vault contains zero of them. Grep for both at the end.

## Phase 1 — Interview

### 1a. Scopes

A **scope** is a bucket of context — a job, a side project, a client, a life area. Its job is routing: it keeps one project's accumulated memory out of an unrelated one, and tells the AI which `me-*` file to read.

Ask:
- "What are the distinct contexts you want this vault to keep track of? For a lot of people that's just one. Common splits are work vs. personal, or one scope per client."
- For each: a short slug (`work`, `personal`, `acme`), a human label, and a one-line description of what it covers.

**One scope is the right answer for most people.** Do not talk them into more. If they hesitate, start with one — adding a scope later is a two-line edit to `AIOS/Systems/layers.tsv`.

### 1b. Strict separation (usually: skip this)

Only ask if they named two or more scopes:

> "Do any two of these need to be *kept secret from each other* — not just tidy, but genuinely never appearing in the same file? The usual reasons are a pen name that can't be linked to a legal name, employer code that can't reach a public portfolio or a job application, or one client's internals that can't surface in another's repo."

**If no** (the common case): leave every `tokens` column in `layers.tsv` as `-`. Delete the "Strict separation" section from `CLAUDE.md` and the commented block from `me-LAYER.template.md`. The write guard stays installed — Rules A and B (immutable `Sources/`, no AI-authored `Atlas/` notes) are useful regardless — but its cross-scope check stays inert. Say plainly: "Wall left off. You can turn it on later by filling in the tokens column."

**If yes**, for each walled scope collect:
- The **identifying tokens**: names, brands, domains, codenames — the literal strings that give that scope away. These become a case-insensitive regex in column 4.
- Whether the wall is **symmetric** or **one-way**. One-way is common: a `work` scope may mention the person's real name (same legal person) while the `professional` scope must never mention the employer. That's `allow-from` in column 5.
- **The hardest crossing, in one sentence**, and why it matters. This goes verbatim into `CLAUDE.md`.

Then write those bullets into `CLAUDE.md`'s "Strict separation" section and each scope's `me-*` file.

### 1c. Identity, per scope

For each scope, ask enough to write an honest `me-<scope>.md`:
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

2. **`AIOS/me-<scope>.md`** — one per scope, from `AIOS/me-LAYER.template.md`. Fill every placeholder. Delete the "Strict separation" comment block if the wall is off. Show each draft to the user before writing. Then delete the template file itself.

3. **`CLAUDE.md`** — fill or delete the `<!-- BOOTSTRAP -->` blocks. If the wall is off, remove the "Strict separation" section entirely.

4. **`AIOS/Maps/Knowledge Map.md`** — one `##` heading per scope, each empty. Delete the BOOTSTRAP comment.

5. **`AIOS/Skills/style-guide-writing-me.md`** — their voice, in their words. If they don't have opinions yet, write "TBD" rather than inventing a style.

6. **Folders** — create `Sources/<scope>/` and `AIOS/Projects/<scope>/` per scope, each with a `.gitkeep`. Create `Efforts/` subfolders matching the content-globs you wrote into `layers.tsv`. **The globs and the real folders must agree** — a glob pointing at a folder that doesn't exist means the guard silently never matches that scope.

7. **`AIOS/Systems/repo-layers.tsv`** — one row per repo from 1d. Keep the header comment.

8. **`Home.md`** — a dashboard linking the `me-*` files, the three Maps, and the Log. Keep it short; it loads into context on every session start.

9. **Wire the cross-repo hooks** (skip if 1d was skipped). For each repo in `repo-layers.tsv`, add to that repo's `.claude/settings.json`:
   - `SessionStart` → `$AIOS_VAULT/AIOS/Systems/hooks/aios-context.sh` (loads that project's accumulated brain into the session)
   - `Stop` → `$AIOS_VAULT/AIOS/Systems/hooks/aios-digest.sh` (appends a session digest to the vault queue)

   Both scripts write **only** to the vault, never to the invoking repo. Tell the user to set `AIOS_VAULT` in their shell rc if the vault isn't at `~/code/aios`.

## Phase 3 — Verify

Run these. Do not report success until they pass. Paste the actual output.

```bash
# 1. The write guard works.
bash .claude/hooks/test_vault_write_guard.sh

# 2. No placeholders survive.
grep -rn '<!-- BOOTSTRAP' . --exclude-dir=.git ; \
grep -rnE '<[a-z-]+>' CLAUDE.md AIOS/me-*.md AIOS/Maps/ 2>/dev/null

# 3. Every scope in layers.tsv has its me-file, Sources dir, and Projects dir.
awk -F'\t' '!/^#/ && NF>=3 {print $1}' AIOS/Systems/layers.tsv | while read -r s; do
  [ -f "AIOS/me-$s.md" ]      || echo "MISSING AIOS/me-$s.md"
  [ -d "Sources/$s" ]         || echo "MISSING Sources/$s/"
  [ -d "AIOS/Projects/$s" ]   || echo "MISSING AIOS/Projects/$s/"
done

# 4. Every content-glob in layers.tsv points at a real folder.
awk -F'\t' '!/^#/ && NF>=3 {print $3}' AIOS/Systems/layers.tsv | tr '|' '\n' | sed 's#/\*$##' \
  | while read -r d; do [ -d "$d" ] || echo "GLOB has no folder: $d"; done

# 5. The template's own example rows are gone.
grep -nE '^(main|professional|pen|work)\b' AIOS/Systems/layers.tsv
```

Checks 2, 3, 4 must print nothing. Check 5 must print only the user's real scopes. Check 1 must end `N passed, 0 failed`.

Then, if and only if the wall is on, dispatch the `layer-leak-auditor` subagent on `CLAUDE.md` and each `me-*.md` and paste its verdict.

## Phase 4 — Commit and hand off

```bash
git add -A && git commit -m "aios: bootstrap vault"
```

Do **not** push. Do not create a remote. Tell the user:

> If any scope is private, keep this repo private. Git history is forever — a commit that exposed something can't be un-shared by a later fix.

Then give them a five-line "what now":
- `/aios-log <fact>` from any wired repo — captures a decision into the vault.
- `/aios-ingest` from the vault — compounds queued session digests into project notes.
- `/wiki-lint` — periodic health check.
- Drop a source file into `Sources/<scope>/` and ask the AI to ingest it.
- Ask a question and watch it read `Knowledge Map` first.

---

## What you just installed

| Piece | What it does |
|---|---|
| `CLAUDE.md` | Entry point. The AI reads this first, every session. |
| `AIOS/Systems/layers.tsv` | Scopes. Drives routing, and the optional wall. |
| `AIOS/me-<scope>.md` | Who you are in each context, and how you want to be worked with. |
| `AIOS/Maps/` | Vault Map (navigation) · Skill Map (what the AI can do) · Knowledge Map (what it knows). |
| `AIOS/Skills/` | Plain-markdown skills. Portable — not locked to any one AI tool. |
| `AIOS/Systems/hooks/` | The cross-repo wire: sessions in other repos feed this vault, never the reverse. |
| `.claude/agents/` | Subagents that keep read-heavy work out of your main context. |
| `.claude/hooks/vault-write-guard.sh` | Mechanically enforces: `Sources/` immutable, no AI-authored `Atlas/` notes, and (optionally) the scope wall. |

The design bet: **a hand-curated `Knowledge Map` read first beats vector search** until you're well into the hundreds of notes. Embeddings are the last resort, not the default.
