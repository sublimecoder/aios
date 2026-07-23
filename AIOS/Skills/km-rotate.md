---
tags: [aios, skill]
system: Janitor
trigger: "rotate the knowledge map" / when a [[Knowledge Map]] line exceeds ~1500 chars
---
# km-rotate

**Purpose:** keep [[Knowledge Map]] lines as one-line *summaries*, not logs. Ingest appends dated activity clauses to a note's KM line until it balloons; the current state belongs on the map, the running history belongs in the note.

**Steps:**
1. Find oversized lines: any KM entry line over ~1500 chars (`awk '{ print length, NR }'` on the map). Work one scope segment at a time.
2. For each oversized line, split its content into (a) the current-state summary and (b) the dated activity clauses (`2026-07-13/14 — …`, `+ MM-DD …` style trailers).
3. Move each activity clause into the target note's Source/changelog section (the dated ingest-provenance section at the bottom of `<scope>/projects/<project>.md` or the matching wiki note). **Dedupe first** — usually every clause is already there, since ingests write both the note and the KM line; only append a clause the note genuinely lacks.
4. **Verify before deleting:** for every clause about to leave the map, confirm the fact exists in the note (same date, same substance). A clause that exists ONLY on the KM line gets written into the note before the map line shrinks — never drop it.
5. Rewrite the KM line as: current-state summary (≤500 chars) + a trailing pointer: `recent activity → the note's Source section`. Keep the line's `[[wikilink]]`, `(kind)` tag, and `→ path` shape intact.
6. Commit the vault (Co-Authored-By trailer). Log a dated line in [[Log]]: `- **YYYY-MM-DD** — **aios/km-rotate** — rotated N KM lines (<scope>).`

**Constraints:** NEVER drop a fact that exists only in the KM line — step 4 is the gate, every clause verified in the note before it leaves the map. One scope at a time (same rule as ingest). Edits touch only [[Knowledge Map]] and the target notes' Source/changelog sections; never rewrite a note's body prose. `<scope>/sources/` stays immutable.

**Dependencies:** [[Knowledge Map]], `<scope>/projects/` notes, [[aios-ingest]] (the writer that grows the lines), [[Log]]. **Output:** KM lines back to summary length, all history preserved in the notes.
