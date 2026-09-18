---
tags: [aios, skill]
system: Janitor
trigger: "update the vault map" / "audit the vault map"
---
# vault-map

**Purpose:** keep [[Vault Map]] true — build or audit either half (navigation: how AI moves through the vault; creation: where new notes go, templates, frontmatter). (Merged 2026-07-22 from navigation-builder + creation-builder + navigation-janitor + creation-janitor.)

**Steps:**
1. Pick the mode from the trigger: **build** (write/refresh sections) or **audit** (compare to reality, propose fixes).
2. Navigation half: scan the folder tree (+, AIOS, Atlas, Calendar, Efforts, x, Sources) → one line per top-level folder, plus conventions (tags, wikilinks, privacy, publishing).
3. Creation half: default location per note type, templates in `archive/Templates/`, frontmatter and naming standards — checked against where notes actually land.
4. Audit mode flags drift both ways (undocumented folders, documented-but-missing, broken links, stale defaults); apply fixes on confirmation only.

**Dependencies:** [[Vault Map]], `archive/Templates/`. **Output:** updated `AIOS/Maps/Vault Map.md` or an alignment report.
