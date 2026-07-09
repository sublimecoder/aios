---
name: aios-log
description: Capture a fact/decision into the AIOS brain vault (layer auto-detected from cwd via repo-layers.tsv) and commit the vault.
---

Capture a durable fact or decision into the AIOS brain vault and persist it. Runs
from ANY directory but ONLY ever writes to the vault — never the invoking repo.

**Vault:** `$AIOS_VAULT` (default `~/code/aios`). Do all file work and git there.

## Rules
1. **Layer = manifest, not guess.** Resolve the invoking repo's `layer` +
   `project` from `$AIOS_VAULT/AIOS/Systems/repo-layers.tsv`
   (`basename "$PWD"` → row). If the repo is not listed, ask which layer before
   writing. Never mix layers in one note.
2. **Sanitize.** Record the *fact or decision*, not proprietary code, secrets,
   keys, customer data, or internal URLs. Work-layer internals are confidential —
   summarize at the decision level. When in doubt, apply `AIOS/Skills/sanitize.md`.
3. **Write two places:**
   - Append a dated line to `AIOS/History/Log.md` — newest at top, `date +%F`,
     led with a parseable `layer/project` tag, e.g.
     `- **2026-06-29** — **work/acme-api** — <what changed>.`
   - If durable, also add it under **Durable preferences** in the matching
     `me-<layer>.md`, and update any wiki note the fact belongs in. Link with
     `[[wikilinks]]`.
   - Do not rewrite prose elsewhere — only append/update these.
4. **Commit + push the vault** with a clear message + the Co-Authored-By trailer.
   Push without re-asking unless `git status` shows unrelated staged changes.

## Steps
1. Note the invoking repo dir for layer+project BEFORE `cd`. Then `cd "$AIOS_VAULT"`.
2. Resolve layer+project from the manifest (ask only if not listed).
3. Sanitize to a decision-level summary.
4. Append the tagged Log line; update `me-<layer>.md` + any relevant wiki note if durable.
5. Commit + push the vault.
6. Report: what was logged, layer/project, files changed, commit hash. Never touch the invoking repo.
