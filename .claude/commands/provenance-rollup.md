---
description: Rotate a project's source-history.md entries older than the current month into source-history-YYYY-MM.md archives, so each ingest's dedupe read stays cheap.
---

Read and follow `AIOS/Skills/provenance-rollup.md`.

Arguments: `$ARGUMENTS` — the project whose provenance shard to roll (e.g.
`work/my-api`, `personal/my-site`). One project, one scope at a time.

`/aios-ingest` reads the whole shard every run to dedupe, so the cheapest question in the
pipeline gets more expensive with every run.

**The end of the file belongs to this skill.** `provenance-rotate.py` strips the
`Older: [[source-history-YYYY-MM]]` pointer with a regex anchored to end-of-buffer — an
ingest entry appended below it makes the strip silently miss. Preserve the five entry
anchors so each entry survives rotation on its own rather than merging into a neighbour.
