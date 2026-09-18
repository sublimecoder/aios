# 🧠 AIOS brain — read before acting

**Canonical text `@import`ed by every project repo's `CLAUDE.md`.** Edit here; all
repos inherit. Layer-neutral — it names no identity, only the mechanism — so it is
safe in creator, professional, and employer repos alike.

---

This repo is backed by the **AIOS vault** (`~/code/aios`), the durable
cross-project memory. A `SessionStart` hook injects this repo's layer context at
the top of every session, under the header `=== AIOS brain (<layer>/<project>) ===`:

- `<layer>/me.md` — durable facts about who you are in this scope
- `<layer>/projects/<project>.md` — the project brain: decisions, architecture, gotchas
- `<layer>/playbook.md` — do/don't work practice, when that layer has one

**Consult that injected context before any non-trivial task.** It records what the
code cannot: why a thing was built this way, what was already tried and failed, and
the corrections you have already been given. Re-deriving it from the repo wastes a
session and repeats a solved mistake.

**Write back.** A fact worth keeping past this session — a decision, a preference,
a gotcha, a correction — goes into the vault, not into this repo's docs:

- `/aios-log` — captures the fact into the right layer note plus the memory log, then commits the vault. Never touches this repo.
- A `Stop` hook queues a session digest automatically; `/aios-ingest` in the vault compounds it into the wiki. Nothing to do by hand.

**Identity wall.** The injected header names this session's layer. Stay in it —
never pull another layer's vault content into this repo's output, and never carry
employer-proprietary detail into a public-brand repo.

**No header injected?** The hook did not fire (missing `SessionStart` entry in
`.claude/settings.json`, or this repo is absent from
`~/code/aios/AIOS/Systems/repo-layers.tsv`). Say so instead of proceeding
brainless — an unwired vault looks exactly like an empty one.

## Changelog
- 2026-08-13 — created; found 5 of 7 project repos referencing the vault nowhere in `CLAUDE.md`, so the injected brain had no instruction attached to it. One block, `@import`ed, replaces 7 drifting copies.
