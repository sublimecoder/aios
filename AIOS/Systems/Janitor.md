---
tags: [aios, system]
related: ["[[Skill Map]]"]
---
# 🧹 Janitor

**Purpose:** maintain the vault and the assistant — propagate changes and fix drift.

**Skills:** [[propagate]] · [[vault-map]] · [[skill-builder]] · [[skills-janitor]] · [[after-action]] · [[wiki-lint]] · [[log-rollup]] · [[km-rotate]] · [[open-flags]]

**Detection is a command, not a memory.** `AIOS/Systems/aios-check.sh` runs every check in this system that a shell can settle (thresholds for km-rotate / log-rollup / open-flags, plus after-action step 2 and the mechanical half of wiki-lint). It fires on SessionStart and inside each ingest, so a threshold crossing surfaces the same day instead of waiting for someone to notice — which is how a Knowledge Map line reached 34× its rotation threshold.

**Use when:** renaming something or changing a convention (propagate), keeping the Vault Map true (vault-map), creating/auditing skills (skill-builder, skills-janitor), compounding what each ingest taught back into the skills (after-action — runs automatically), or health-checking the wiki layer (wiki-lint, log-rollup, km-rotate, open-flags).
