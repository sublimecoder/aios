# CLAUDE — AI OS entry point

This vault is an **AI Operating System** (plain markdown, no plugins, portable across AI tools). Everything the AI needs lives in `AIOS/`.

> **New vault?** Run `/aios-bootstrap` (or paste `BOOTSTRAP.md` into your agent) once. It interviews you, fills in the `<placeholders>` below, and rewrites this file.

## Start here, every session
1. Read `AIOS/Systems/layers.tsv` — the scopes this vault partitions knowledge into. A single-scope vault is normal; if there's one row, skip the ceremony.
2. Read the **me** file for the scope this task belongs to: `<scope>/me.md`.
3. Read `AIOS/Maps/Vault Map.md` — how to navigate and where new notes go.
4. Read `AIOS/Maps/Skill Map.md` — every skill/system and its trigger. Skills live in `AIOS/Skills/`, systems in `AIOS/Systems/`.

## Scopes
A **scope** is a bucket of context — a job, a side project, a client, a life area. Its job is *routing*: it keeps one project's accumulated memory out of an unrelated one, and tells the AI which `me.md` file to read.

- **The scope is the filesystem:** each scope is one top-level directory named by its slug — `<scope>/me.md`, `<scope>/notes/`, `<scope>/content/`, `<scope>/projects/`, `<scope>/sources/`. A path's first segment names its scope; that prefix is what the write guard, ingest, and leak audits key on.
- Every content note also carries a `layer:` frontmatter field naming its scope.
- Ingest, query, and lint each work **one scope at a time**, so a synthesis note never blends two unrelated contexts. This is about keeping knowledge coherent, not about secrecy.

## Strict separation (optional — off by default)
Most vaults do not need this. Skip the whole section unless it applies to you.

Some people keep scopes that must never appear in the same file — a pen name that can't be linked to a legal name, employer-proprietary code that can't reach a public portfolio or a job application, one client's internals that can't surface in another's repo. If that's you, enable the wall by filling in the `tokens` column of `AIOS/Systems/layers.tsv`.

<!-- BOOTSTRAP: if the wall is OFF, delete this block and the two bullets below it.
     If ON, replace with one bullet per walled scope naming the hardest crossing and why. -->
- `<scope>` — `<who you are here>`. Hardest wall: `<which other scope, and what must never connect them>`.

Two mechanisms enforce it, and both are inert while `tokens` is `-`:
- **Write time:** `.claude/hooks/vault-write-guard.sh` (a PreToolUse hook) blocks a write that drops one scope's tokens into another scope's content folder. Cheap grep, near-zero false positives.
- **Publish time:** the `layer-leak-auditor` subagent catches the inferred crossings a grep can't — a codename, a URL, a biographical detail, two individually-safe facts that are jointly identifying.

If the wall is on: treat anything a scope's `me.md` marks confidential as confidential **by default**, not on request. Run `AIOS/Skills/sanitize.md` before anything leaves the vault.

## Global rules (the contract)
- Ask before any external action (publishing, posting, sending, applying).
- AI-generated notes default to `<scope>/content|projects/` or `AIOS/History/` — never intermixed into hand-written `<scope>/notes/`.
- Do not rewrite the user inside their own notes; propose edits and let them apply.
- Privacy: never surface private life items from a scope's `notes/` in summaries/dashboards unless explicitly asked. Ignore `archive/System Docs/` when scanning for live tasks.

## Memory
- When you learn a durable fact (preference, person, goal, decision), update the right file (`<scope>/me.md`, or the matching `<scope>/notes/` note — propose, don't rewrite) AND append a dated line to `AIOS/History/Log.md` (newest at top, `YYYY-MM-DD`).
- **From outside the vault** (a session in some other repo), the write-back wire is the `/aios-log` command: it auto-detects scope + project from cwd via `AIOS/Systems/repo-layers.tsv`, writes the Log line (led with a parseable `scope/project` tag) + the matching `<scope>/me.md` / wiki note, and commits the vault — never touching the invoking repo. Log entries carry that tag, so per-project history is a `grep`, not a separate file.

## Wiki operations (the knowledge layer)
This vault is also an LLM-maintained knowledge wiki. Three operations, one contract:
- **Ingest** — when a source lands in `<scope>/sources/`, read it, then update the relevant entity/concept notes **and** [[Knowledge Map]] **and** a dated line in [[Log]]. One source usually touches several notes. Propose edits to the user's own notes — don't rewrite them silently.
- **Query** — answer from the wiki: read [[Knowledge Map]] first, traverse `[[wikilinks]]`, synthesize a cited answer. An answer worth keeping gets filed as a new note and added to [[Knowledge Map]].
- **Lint** — run [[wiki-lint]] (trigger "lint the wiki") for a periodic health-check. It proposes; it never deletes or edits content pages.

**Sources are immutable.** Everything under `<scope>/sources/` is read-only curated input — read it, never edit or delete it. It is the source of truth; wiki notes are summaries that point back via the `sources` frontmatter field. See [[_Sources]]. The write guard enforces this mechanically.

**Retrieval policy (three tiers):** *direct-load the core* (`CLAUDE.md`, the right `me.md`, the Maps) · *graph-traverse the meaningful* (`[[wikilinks]]` + frontmatter; read [[Knowledge Map]] first) · *RAG the tail* only as a last resort. The read-first Knowledge Map pushes the search threshold out to hundreds of notes; embeddings are the last resort, not the default.

## Orchestration
The main session is the **orchestrator** — it runs on the strongest available model and delegates read-heavy scans, audits, per-digest grunt work, and wiki queries to the subagents in `.claude/agents/`, one scope per invocation. Doctrine, model routing, and the agent roster: `AIOS/Systems/Orchestrator.md`.

## Folder framework — scope-first
`+/` Inbox · `AIOS/` the AI OS (scope-neutral: Maps, Skills, Systems, History) · `<scope>/` one dir per scope with `me.md` + `notes/` + `content/` + `projects/` + `sources/` (sources read-only) · `archive/` xtras. Full detail in `AIOS/Maps/Vault Map.md`; the structure's history in `docs/structure-evolution.md`.

## Version control
- After meaningful changes, commit with a clear message and (when asked) `git push`.
- **If any scope is private, keep this repo private.** Git history is forever: a commit that exposed something cannot be un-shared by a later fix.
