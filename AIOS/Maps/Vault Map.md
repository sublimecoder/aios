---
tags: [aios, map]
related: ["[[Skill Map]]", "[[Knowledge Map]]"]
---
# Vault Map

> AI's manual for how to navigate and create notes in this vault. Read this to know where things live and where new notes go.

## The core notes
- **scopes** → `AIOS/Systems/layers.tsv`. How this vault partitions context. Read first, always. One scope is a normal setup.
- **me** → `AIOS/me-<scope>.md`, one per scope. Read the one this task belongs to.
- **Vault Map** → this file. How to move through the vault.
- **Skill Map** → [[Skill Map]]. Every skill AI can run and when to trigger it.
- **Knowledge Map** → [[Knowledge Map]]. What the wiki knows, segmented by scope.

AI-specific core note: `CLAUDE.md` lives at the vault root (required there) and points here.

## Folder framework — LYT ACE + AIOS
Fast-scan view. Read this first to orient.

- `+/` — **Inbox.** Where raw captures land before processing. → [[Inbox]]
- `AIOS/` — **The AI Operating System.** `me-*` files, `Maps/`, `Skills/`, `Systems/`, `History/`, `Projects/`.
- `Atlas/` — **Timeless knowledge.** People, reference, domain notes. Hand-written; AI proposes, never creates here.
- `Calendar/` — **Time-based.** `Days/` (daily briefs + logs), `Reviews/` (weekly reviews).
- `Efforts/` — **Works & projects.** One subfolder per scope's active work.
- `x/` — **Xtras.** Templates, Attachments, System Docs (old design docs).
- `Sources/` — **Immutable curated inputs (read-only).** Raw source material the AI reads but never edits or deletes, partitioned by scope (`Sources/<scope>/`); the wiki summarizes it. Index [[_Sources]]; catalog [[Knowledge Map]].

## Where new notes go (defaults)
- A raw capture → `+/` (then process it).
- A timeless fact / reference / person note → `Atlas/...` (propose the edit; don't create).
- A daily brief or log → `Calendar/Days/`. A weekly review → `Calendar/Reviews/`.
- A project's accumulated knowledge → `AIOS/Projects/<scope>/<project>.md` (written by [[aios-ingest]]).
- An AI session log or memory decision → `AIOS/History/`.
- Anything AI generates goes in the AIOS/Calendar/Efforts buckets above — never intermixed into hand-written Atlas notes. The `vault-write-guard` hook enforces this.

## Conventions
- Tasks are `- [ ]` checkboxes inside notes.
- Link related notes with `[[wikilinks]]` (resolve by name, so moving a note never breaks them).
- Tags: keep the vocabulary small. Start with #idea #reference #inbox #memory #aios and grow only when a tag earns its keep.
- Every content note carries a `layer:` frontmatter field naming its scope.
- Privacy: never surface `Atlas/Life/` private items in summaries/dashboards unless explicitly asked. Ignore `x/System Docs/` when scanning for live tasks.

## Note formats
Obsidian handles more than plaintext: images, audio, PDFs, embeds. Store media in `x/Attachments/` and embed with `![[file]]`.
