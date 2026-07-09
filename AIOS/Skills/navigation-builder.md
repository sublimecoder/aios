---
tags: [aios, skill]
system: AI OS Autobuilder
trigger: "build navigation" / "update the vault map (navigation)"
---
# navigation-builder

**Purpose:** build the 1st half of the [[Vault Map]] — how AI should navigate the vault.

**Steps:**
1. Scan the folder tree (+, AIOS, Atlas, Calendar, Efforts, x).
2. Write a fast-scan overview: one line per top-level folder describing what lives there.
3. Capture conventions: tags, wikilink rules, privacy rules, publishing rules.
4. Update the navigation sections of [[Vault Map]] only; leave creation sections to [[creation-builder]].

**Dependencies:** none. **Output:** `AIOS/Maps/Vault Map.md`.
