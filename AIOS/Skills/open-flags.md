---
tags: [aios, skill]
system: Janitor
trigger: "open flags" / a step in every [[aios-ingest]] run
---
# open-flags

**Purpose:** ⚠️/OPEN markers in project notes are commitments, not decorations. Each one names a fact that must be confirmed, reconciled, or acted on ("confirm with the user", "reconcile before trusting this bullet") — left unswept, they rot into permanent hedges nobody re-checks.

**Steps:**
1. Grep `*/projects/**/*.md` for the flag markers: `⚠️`, `OPEN —`, `OPEN:`.
2. Emit a register, one row per flag: the flag text (trimmed), note + section it lives in, first-seen date (derive from [[Log]] / the note's Source section where the flag's subject first appears — mark "unknown" if not derivable), and age in days.
3. **During ingest** ([[aios-ingest]] step): every flag touching the ingested project must be dispositioned — either *confirmed still open* (the new digest doesn't resolve it; leave it) or *resolved in the note* (the digest settles it; rewrite the flagged bullet to the settled fact and note the resolution in the Source section). No flag on a touched project passes an ingest unsighted.
4. Flags older than 30 days: escalate — append one dated line to [[Log]] proposing close-or-act, e.g. `- **YYYY-MM-DD** — **<scope>/<project>** — ⚠️ flag open 34d: <flag> — propose: <close|act>.` One escalation line per flag per run, not per day.
5. Report the register (open / resolved-this-run / escalated).

**Constraints:** read-only over the notes, with two exceptions: an ingest-driven resolution (step 3, only when the digest genuinely settles it) and the age-escalation Log line (step 4). Never silently delete a flag — a flag leaves a note only by being resolved into a settled fact, and the resolution is recorded. One scope at a time when run standalone.

**Dependencies:** the scopes’ `projects/` dirs, [[aios-ingest]] (calls this per touched project), [[Log]] (first-seen dates + escalations). **Output:** the flag register + any escalation Log lines; notes untouched except genuine resolutions.
