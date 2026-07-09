---
tags: [aios, skill]
system: AI OS Autobuilder
trigger: "create a skill" / "build a new skill"
---
# skill-builder

**Purpose:** the playbook AI uses to create new skills in a consistent format and register them.

**Skill format (use this for every new skill):**
- Frontmatter: `tags: [aios, skill]`, `system`, `trigger`.
- **Purpose:** one sentence — what it does.
- **Steps:** numbered, concrete.
- **Dependencies:** MCPs, APIs, tools, or other notes.
- **Output:** where the result goes.

**Steps:**
1. Confirm purpose, trigger phrase, and which system it belongs to.
2. Write the note to `AIOS/Skills/<name>.md` in the format above.
3. Register it in [[Skill Map]] under its system, with the one-line description.
4. Log a dated line in [[Log]].

**Dependencies:** [[Skill Map]]. **Output:** `AIOS/Skills/<name>.md` + Skill Map entry.
