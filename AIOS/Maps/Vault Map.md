---
tags: [aios, map]
related: ["[[Skill Map]]", "[[Knowledge Map]]"]
---
# Vault Map

> AI's manual for how to navigate and create notes in this vault. Read this to know where things live and where new notes go.

## The core notes
- **scopes** → `AIOS/Systems/layers.tsv`. How this vault partitions context. Read first, always. One scope is a normal setup.
- **me** → `<scope>/me.md`, one per scope. Read the one this task belongs to.
- **Vault Map** → this file. How to move through the vault.
- **Skill Map** → [[Skill Map]]. Every skill AI can run and when to trigger it.
- **Knowledge Map** → [[Knowledge Map]]. What the wiki knows, segmented by scope.

AI-specific core note: `CLAUDE.md` lives at the vault root (required there) and points here.

## Folder framework — scope-first
Fast-scan view. Read this first to orient. The scope IS the filesystem: one top-level dir per scope in `AIOS/Systems/layers.tsv`; a path's first segment names its scope. That prefix is what the write guard, ingest, and leak audits key on.

- `+/` — **Inbox.** Where raw captures land before processing. → [[Inbox]]
- `AIOS/` — **The AI Operating System** (scope-neutral). `Maps/`, `Skills/`, `Systems/`, `History/` ([[Log]], `days/` daily briefs + logs, `reviews/` weekly reviews, `_ingested/` digest archives).
- `<scope>/` — **one dir per scope** (default: `main/`), fixed inner shape:
  - `me.md` — who you are in this context. Read first for any task here.
  - `notes/` — timeless knowledge: people, reference, domain notes. Hand-written; AI proposes, never creates here.
  - `content/` — drafts and works-in-progress.
  - `projects/` — AI-maintained project brains, one note per wired repo (written by [[aios-ingest]]).
  - `sources/` — **immutable curated inputs (read-only).** The AI reads, never edits or deletes; the wiki summarizes them. Index [[_Sources]]; catalog [[Knowledge Map]].
- `archive/` — **Xtras.** Templates, Attachments, System Docs (old design docs).

## Where new notes go (defaults)
- A raw capture → `+/` (then process it).
- A timeless fact / reference / person note → `<scope>/notes/...` (propose the edit; don't create).
- A daily brief or log → `AIOS/History/days/`. A weekly review → `AIOS/History/reviews/`.
- A draft or work-in-progress → `<scope>/content/`.
- A project's accumulated knowledge → `<scope>/projects/<project>.md` (written by [[aios-ingest]]).
- An AI session log or memory decision → `AIOS/History/`.
- Anything AI generates goes in `<scope>/content|projects/` or `AIOS/History/` — never intermixed into hand-written `notes/`. The `vault-write-guard` hook enforces this.

## Conventions
- Tasks are `- [ ]` checkboxes inside notes.
- Link related notes with `[[wikilinks]]` (resolve by name, so moving a note never breaks them).
- Tags: keep the vocabulary small. Start with #idea #reference #inbox #memory #aios and grow only when a tag earns its keep.
- Every content note carries a `layer:` frontmatter field naming its scope.
- Privacy: never surface private life items from a scope's `notes/` in summaries/dashboards unless explicitly asked. Ignore `archive/System Docs/` when scanning for live tasks.

## Note formats
Obsidian handles more than plaintext: images, audio, PDFs, embeds. Store media in `archive/Attachments/` and embed with `![[file]]`.
