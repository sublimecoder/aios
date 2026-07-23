---
name: aios-ingest
description: Compound queued session digests from +/_sessions/ into the wiki — one layer at a time. Karpathy Ingest op, specialized for session digests. Always run in the vault.
---

Compound the queued session digests into the wiki. **Run only in the vault.**

## Preconditions
- cwd is the vault root, `$AIOS_VAULT` (has `AIOS/` + `CLAUDE.md`).
- There are non-empty files under `+/_sessions/<layer>/<project>.md`.

## Inputs (two kinds)
- **Digests** — `+/_sessions/<layer>/<project>.md`: git signal (branch/commits/diff-stat). Synthesize decision-level meaning.
- **Native-memory mirror** — `+/_sessions/.memory/<layer>/<project>/*.md`: an exact copy of the repo's Claude Code memory, refreshed every session by the Stop hook. These are **already durable prose facts** — merge them, don't infer. A digest's `memory: <files>` line names which mirror files changed that session. The mirror is living state, NOT a consumable queue: **never archive, edit, or delete it** (the Stop hook owns it; touching it just re-triggers on the next session).

## Rules
- **One layer at a time.** Process every project in one layer, then move to the
  next layer in `AIOS/Systems/layers.tsv`. Never synthesize across layers in a
  single note — the identity wall.
- **Digests are signal, not prose.** Each block is branch + commits + diff-stat.
  Synthesize the *decision-level* meaning (the breadcrumb), not raw diffs. If a
  digest implies nothing durable, skip it — do not invent.
- **Sources stay immutable.** Write only to `<layer>/projects/`, `AIOS/History/Log.md`,
  and `Knowledge Map`. Never edit `<layer>/sources/` or create new notes in `<layer>/notes/`.
- **Dates:** all vault dates derive from local `date +%F`, never from digest UTC
  stamps (late in the local day they disagree).
- **Dedupe:** collapse byte-identical digest blocks before synthesis (defense in
  depth; the hook dedupes at write time).

## Steps
For each layer with a non-empty queue (when the queue is large, fan step 1 out — one `ingest-worker` subagent per digest, per [[Orchestrator]]; workers write only their own project note and hand back the KM + Log lines for steps 1c–d):
1. For each `<project>.md` in `+/_sessions/<layer>/`:
   a. Read/create `<layer>/projects/<project>.md` (frontmatter `layer:`,
      `project:`; link `[[<layer>/me]]`).
   b. Synthesize the queued digests into durable facts; append/update the note.
      For any digest carrying a `memory:` line, read the named files in
      `+/_sessions/.memory/<layer>/<project>/` and reconcile their facts into the
      note (idempotent merge — they're the source of truth; don't duplicate what's
      already captured, and drop note content a retracted mirror file contradicts).
   c. Add/refresh the note's entry in `[[Knowledge Map]]` (correct layer segment).
   d. **Draft** one `layer/project`-tagged line for `AIOS/History/Log.md` (newest
      top) — content only, NO gate or lint verdicts yet: those exist only after
      steps 2 and 4 actually run (a pre-written "🟢" is a fabricated verdict).
   e. **Open flags:** run [[open-flags]] scoped to the ingested project — every
      ⚠️/OPEN marker in its note(s) gets confirmed-still-open or resolved this
      ingest; never silently dropped.
2. **Gate:** dispatch the `layer-leak-auditor` subagent on each touched note. If it
   flags a crossing, fix or revert that note before committing.
3. **Archive** consumed digests: move each processed `+/_sessions/<layer>/<project>.md`
   to `AIOS/History/_ingested/<layer>/<project>-<date>.md` so re-ingest never
   double-counts. Recreate the empty queue dir.
4. **Lint:** read and follow `AIOS/Skills/wiki-lint.md`, scoped to the touched notes' neighborhood.
5. Finalize the Log line with the **real** gate (step 2) + lint (step 4) verdicts —
   never pre-write them. Then commit + push the vault (Co-Authored-By trailer).
   Report per layer: projects touched, notes updated, anything the auditor flagged.
