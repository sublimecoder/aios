---
tags: [aios, skill]
system: Janitor
trigger: "rename X to Y everywhere" / "harmonize this convention"
---
# propagate

**Purpose:** sweep one change across every note that carries it — a rename or a convention. (Merged 2026-07-22 from cascade + harmonize.)

**Steps:**
1. Confirm the change:
   - **rename** — old name → new name. Scope: note bodies, `[[wikilinks]]`, frontmatter fields, file/folder names, scheduled tasks.
   - **convention** — old form → new form (rules, formatting, headings, labels, structures). Touch only the convention, never content meaning.
2. Find every occurrence in scope.
3. Show the planned changes; apply on confirmation.
4. Skip `AIOS/History/` (preserve the record).
5. Log a dated line in [[Log]].

**Dependencies:** none. **Output:** updated notes + change report.
