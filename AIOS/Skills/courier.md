---
tags: [aios, skill]
system: Courier
trigger: "send this note to <other vault>"
---
# courier

**Purpose:** duplicate a note from this vault to another vault (e.g., a shared/team vault) for sharing.

**Steps:**
1. Confirm the destination vault/path and the note.
2. Run [[sanitize]] first if the destination is shared with others.
3. Copy the note (and any required attachments) to the destination, preserving frontmatter.
4. Report what was sent and where.

**Dependencies:** [[sanitize]]. **Output:** copied note in the destination vault.
