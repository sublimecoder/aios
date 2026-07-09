---
tags: [aios, skill]
system: Courier
trigger: "sanitize this note" / "make a shareable version"
---
# sanitize

**Purpose:** duplicate a note and produce a shareable version with personal details abbreviated, flagged, or removed.

**Steps:**
1. Copy the note to a `-shareable` version; never edit the original.
2. **If the optional wall is enabled** (any `tokens` column set in `AIOS/Systems/layers.tsv`): determine the note's scope, then strip or flag anything naming or implying a walled scope. Skip this step entirely if no scope declares tokens.
3. Abbreviate or remove: legal name (where a pseudonym belongs), addresses, family members' names, private contacts, financials, secrets/keys, customer data, internal hostnames.
3b. If the note carries employer-proprietary detail, summarize at the decision level — never ship internal code, ticket IDs, or architecture verbatim outside the employer.
4. List every change so I can review before sharing.

**Dependencies:** none. **Output:** `<note>-shareable.md` + change list.
