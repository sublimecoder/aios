---
tags: [aios, skill]
system: Janitor
trigger: "audit navigation" / "check the vault map (navigation)"
---
# navigation-janitor

**Purpose:** the other side of [[navigation-builder]] — audit the 1st half of the [[Vault Map]] and ensure text, notes, links, and instructions are in alignment with reality.

**Steps:**
1. Compare the navigation sections of [[Vault Map]] to the actual folder tree.
2. Flag drift: folders that exist but aren't documented, documented folders that don't exist, broken links.
3. Propose fixes; apply on confirmation.

**Dependencies:** [[Vault Map]]. **Output:** alignment report + fixes.
