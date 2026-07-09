---
tags: [aios, skill]
system: Janitor
trigger: "rename X to Y everywhere"
---
# cascade

**Purpose:** propagate a name change across body text, frontmatter, paths, and scheduled tasks.

**Steps:**
1. Confirm old name and new name.
2. Find every occurrence: note body, `[[wikilinks]]`, frontmatter fields, file/folder names, scheduled tasks.
3. Show the planned changes; apply on confirmation.
4. Skip `AIOS/History/` and `Calendar/` history files (preserve the record).
5. Log a dated line in [[Log]].

**Dependencies:** none. **Output:** updated notes + rename report.
