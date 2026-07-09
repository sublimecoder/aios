---
tags: [aios, skill]
system: AI OS Autobuilder
trigger: "build my me" / "update me file"
---
# me-builder

**Purpose:** interview me and build or update my `me-*` files.

**Steps:**
1. Read `AIOS/Systems/layers.tsv` and ask which layer this is for. Never mix layers.
2. Ask short, universal questions: who I am in this layer, how I want to be addressed, tone, working rules, current goals, non-negotiables.
3. Draft/update the chosen me file: identity, how I work, working preferences (the contract), core references, durable preferences.
4. Show me the diff; do not overwrite without confirmation.
5. Log a dated line in [[Log]].

**Dependencies:** `AIOS/Systems/layers.tsv`. **Output:** `AIOS/me-<layer>.md`.
