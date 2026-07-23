# Structure evolution — how this template got its shape

This template has had two structures. The git history keeps both on purpose:
v1 is still visible in early commits, v2 is what ships today. This note records
what changed and why, so you can see the reasoning instead of just the result —
and so you can decide deliberately if you ever want to deviate.

**TL;DR: start with v2, the scope-first tree that ships today.** It is what we
would build first if we were starting over.

## v1 — LYT ACE + AIOS (where we started)

The first shape borrowed Nick Milo's ACE folders (Atlas/Calendar/Efforts) and
bolted the AI OS beside them:

```
+/         Inbox
AIOS/      me-* files, Maps, Skills, Systems, History, Projects/<scope>/
Atlas/     Timeless knowledge (hand-written)
Calendar/  Days/, Reviews/
Efforts/   Works & projects
Sources/   Sources/<scope>/ — immutable curated inputs
x/         Templates, attachments, old docs
```

ACE answers "*what kind* of note is this?" — timeless, time-based, or effort.
That is a good question for a human browsing a personal vault, and for a
single-scope vault it works fine.

## What broke at scale

Once a vault holds more than one scope (work + personal, a client per scope, a
pen name), the machine's question is different: "*whose* note is this?" In v1
that answer was smeared across four folder families:

- A scope's identity lived in `AIOS/me-<scope>.md`, its raw inputs in
  `Sources/<scope>/`, its project brains in `AIOS/Projects/<scope>/`, and its
  actual content anywhere under `Atlas/` and `Efforts/` that the scope's
  `layers.tsv` globs happened to name.
- Every mechanism that cared about scope — the write guard, ingest, wiki-lint,
  leak audits, graph builds — had to re-derive membership from those globs.
  Each one was a chance for the globs and the real folders to disagree, and a
  glob that points at a folder that doesn't exist fails silently.
- Adding a scope meant touching four places and keeping them in agreement.

The live vault this template is distilled from hit all three problems in
practice, and restructured. This template follows.

## v2 — scope-first (what ships today)

One idea: **the scope is the filesystem.**

```
+/           Inbox
AIOS/        The OS core, scope-neutral: Maps, Skills, Systems,
             History (Log, days/, reviews/, _ingested/)
<scope>/     One top-level dir per layers.tsv row (default: main/)
  me.md        who you are here — read first for any task in this scope
  notes/       timeless, hand-written (AI proposes, never creates)
  content/     drafts and works-in-progress
  projects/    AI-maintained project brains, one per wired repo
  sources/     immutable curated inputs (read-only, guard-enforced)
archive/     Templates, attachments, old design docs
```

A path's first segment names its scope. Consequences:

- **The guard gets trivial.** "Does this write cross a scope wall?" is a prefix
  check plus a token grep. Rules A and B ("sources are immutable", "AI never
  authors into notes/") become shape rules — `*/sources/*`, `*/notes/*` — that
  hold for every scope ever added, with no per-scope configuration.
- **Adding a scope is one `mkdir` and one tsv row**, and the row's glob is
  always just `<slug>/*`. The globs can no longer drift from the folders.
- **Everything that partitions by scope** — ingest, wiki queries, leak audits,
  knowledge-graph splits — keys on the same prefix instead of each keeping its
  own map of what belongs where.
- **ACE didn't die; it moved inside the scope.** `notes/` is Atlas, `content/`
  + `projects/` are Efforts, and the time-based Calendar notes turned out to be
  the AI's memory surface, so they live with the rest of its memory in
  `AIOS/History/`. The kind-of-note question is still answered — one level
  down, after the whose-note question.

## What we'd tell someone starting today

1. **Start scope-first, even with one scope.** A single `main/` costs nothing
   extra, and the day you add a second context you inherit the wall, the
   routing, and the graph split for free instead of restructuring.
2. **Keep `AIOS/` scope-neutral.** The OS describes every scope; the moment it
   contains one scope's content, the prefix rule has an exception and every
   mechanism needs to know about it.
3. **Let the tree carry the invariant, not conventions.** Anything a hook can
   check by path shape (`*/sources/*` is immutable) will survive; anything that
   relies on people remembering a rule will not.

The migration itself, if you're on v1: it's a stage of `git mv`s (content into
`<scope>/`), then pointing the machinery at the new paths, then the docs. This
template's history does it in exactly those commits — `restructure v2:` — if
you want the worked example.
