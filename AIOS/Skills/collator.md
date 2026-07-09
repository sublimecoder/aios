---
tags: [aios, skill]
system: Courier
trigger: "collate this note"
---
# collator

**Purpose:** read a note, find every wiki-link, and append summaries of each linked note — producing one self-contained file that makes sense to someone without my vault.

**Steps:**
1. Read the source note and collect every `[[wikilink]]`.
2. For each linked note, write a short summary.
3. Append them under a "Linked context" section in a new self-contained copy.
4. Consider running [[sanitize]] after if it's going outside my vaults.

**Dependencies:** [[sanitize]] (optional). **Output:** `<note>-collated.md`.
