---
tags: [aios, skill]
system: Janitor
trigger: "audit creation rules" / "check the vault map (creation)"
---
# creation-janitor

**Purpose:** the other side of [[creation-builder]] — audit the 2nd half of the [[Vault Map]] and ensure note-creation rules, templates, and defaults are in alignment.

**Steps:**
1. Compare the creation sections of [[Vault Map]] to actual templates in `x/Templates/` and where notes are really landing.
2. Flag drift: missing templates, wrong default locations, stale frontmatter standards.
3. Propose fixes; apply on confirmation.

**Dependencies:** [[Vault Map]], `x/Templates/`. **Output:** alignment report + fixes.
