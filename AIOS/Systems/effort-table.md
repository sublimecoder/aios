---
tags: [aios, system, infra]
related: ["[[Orchestrator]]"]
---
# ⚙️ Effort table — task type → model

**The one place model names live.** Scope-neutral infra: pure model routing, no
identity content from any scope — so it is safe to load into *every* session
without crossing a wall.

**Wiring:** this file is the canonical source. Point your global agent config at
it (Claude Code: an `@import` in `~/.claude/CLAUDE.md`) so it reaches every repo
on the machine. The vault `CLAUDE.md` and [[Orchestrator]] point here. Tracked in
the vault → git history + grows over time.

| Task type | Effort | Model | ID |
|---|---|---|---|
| **Default — everything not routed elsewhere** | high | **Opus 5** | `claude-opus-5` |
| Hardest judgment calls: irreversible, published, security- or money-critical, cross-layer | xhigh | Fable 5 | `claude-fable-5` |
| Mid-weight drafting / analysis / bulk edits in a subagent | medium | Sonnet 5 | `claude-sonnet-5` |
| Mechanical scans, greps, per-item grunt work | low | Haiku 4.5 | `claude-haiku-4-5-20251001` |

*Effort* = reasoning-effort dial (low/medium/high/xhigh/max) to set per Agent/Workflow dispatch.

**Default is set once, globally.** Set `model` and `effortLevel` in
`~/.claude/settings.json`, and pin a model in NO repo's `.claude/settings.json` —
they all inherit. Escalations and downgrades are per-dispatch decisions off this
table, not per-repo config.

Bindings: `.claude/agents/*.md` frontmatter carries `model:` + `effort:` per this table (family aliases `opus`/`sonnet`/`haiku` resolve to the latest of that family); portable `skills/*/SKILL.md` may carry `effort:` (published-output skills pin `high`); commands and vault-note skills stay unpinned — they inherit the orchestrator session model.

**Editing rules**
- Change a model or tier here only — every consumer inherits it.
- Changing the default means editing `~/.claude/settings.json` `model` **and** the default row here. Do not re-introduce per-repo `model` pins.
- A repo may override a row in its own `CLAUDE.md`.
- Keep this file layer-neutral. No identity content ever, or the import breaches the wall.

## Changelog
- Created; table lifted from [[Orchestrator]] model-routing, wired as a global import.

<!-- Replace the model IDs above with whatever is current. This table is the one
     place they live; every agent file and skill inherits from it. -->
