---
description: Rotate ballooned Knowledge Map lines — move each line's dated activity clauses into the target note's activity-trail section, leaving the map as one-line summaries.
---

Read and follow `AIOS/Skills/km-rotate.md`.

Arguments: `$ARGUMENTS` — an optional layer (`creator` / `professional` / `work`) or
specific map line numbers. With no arguments, work every line `aios-check.sh` reports,
one layer segment at a time.

Measure with `sh AIOS/Systems/km-measure.sh` (bytes, not characters — that is the number
the gate uses). `aios-check.sh` warns at **1350 bytes** so rotation happens while it is
cheap; the skill's own frontmatter still says "exceeds ~1500", which is the failure
threshold rather than the pressure threshold — prefer the 1350 warning as the trigger.

Step 4 is the gate: a clause that exists ONLY on the map line gets written into the note
before the map line shrinks. Never drop a fact.
