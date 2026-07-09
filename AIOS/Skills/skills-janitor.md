---
tags: [aios, skill]
system: Janitor
trigger: "audit my skills"
---
# skills-janitor

**Purpose:** audit skill files against the schema defined by [[skill-builder]] and fix drift.

**Steps:**
1. For each note in `AIOS/Skills/`, check it has the required parts: frontmatter (tags/system/trigger), Purpose, Steps, Dependencies, Output.
2. Check every skill is listed in [[Skill Map]] under the right system, and that Skill Map lists no skills that don't exist.
3. Report mismatches; fix on confirmation.

**Dependencies:** [[skill-builder]], [[Skill Map]]. **Output:** audit report + fixes.
