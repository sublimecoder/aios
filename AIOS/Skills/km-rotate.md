---
tags: [aios, skill]
system: Janitor
trigger: "rotate the knowledge map" / when a [[Knowledge Map]] line exceeds ~1500 chars
---
# km-rotate

**Purpose:** keep [[Knowledge Map]] lines as one-line *summaries*, not logs. Ingest appends dated activity clauses to a note's KM line until it balloons (a project line has hit 21k chars); the current state belongs on the map, the running history belongs in the note.

**Steps:**
1. Find oversized lines: any KM entry line over ~1500 chars (`awk '{ print length, NR }'` on the map). Work one layer segment at a time.
2. For each oversized line, split its content into (a) the current-state summary and (b) the dated activity clauses (`2026-07-13/14 — …`, `+ MM-DD …` style trailers).
3. Move each activity clause into the target note's activity-trail / Source-changelog section — **a named heading, never the file tail.** A sharded project keeps the trail in its own file (`<scope>/projects/<project>/_history/km-activity-trail.md`); an unsharded note keeps it in the dated ingest-provenance section of `<scope>/projects/<project>.md` or the matching Atlas note. Read the destination's headings and append under the one that declares itself the target for new rotations, **even when a different section is last** — appending at EOF is the default motion, and on 2026-08-14 it put a rotation inside `## Stragglers relocated from the hub — 2026-08-13`, a closed dated set of four whose own prose counts them. **Dedupe first** — usually every clause is already there, since ingests write both the note and the KM line; only append a clause the note genuinely lacks.
4. **Verify before deleting:** for every clause about to leave the map, confirm the fact exists in the note (same date, same substance). A clause that exists ONLY on the KM line gets written into the note before the map line shrinks — never drop it.
5. Rewrite the KM line as: current-state summary (≤500 chars) + a trailing pointer **naming the destination step 3 actually appended to** — the trail file's path for a sharded project, the heading for an unsharded note: `recent activity → <that destination>`. Never a generic "the note's Source section": step 3 owns where the trail lives and this step only quotes its answer, so the two cannot drift apart again. Keep the line's `[[wikilink]]`, `(kind)` tag, and `→ path` shape intact.
6. Commit the vault (Co-Authored-By trailer). Log a dated line in [[Log]]: `- **YYYY-MM-DD** — **aios/km-rotate** — rotated N KM lines (<layer>).`

**Constraints:** NEVER drop a fact that exists only in the KM line — step 4 is the gate, every clause verified in the note before it leaves the map. One layer at a time (the identity wall — same rule as ingest). Edits touch only [[Knowledge Map]] and the target notes' Source/changelog sections; never rewrite a note's body prose. `<layer>/sources/` stays immutable.

**Dependencies:** [[Knowledge Map]], `<layer>/projects/` notes, [[aios-ingest]] (the writer that grows the lines), [[Log]]. **Output:** KM lines back to summary length, all history preserved in the notes.
