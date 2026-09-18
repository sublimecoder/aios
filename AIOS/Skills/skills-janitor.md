---
tags: [aios, skill]
system: Janitor
trigger: "audit my skills"
---
# skills-janitor

**Purpose:** audit skills against [[skill-builder]] — both the schema and the six failure modes — and propose fixes.

**This skill proposes. It never rewrites.** Report, then fix only what I confirm.

**Scope line vs [[after-action]]:** this skill judges a skill's **form** — schema, the six
failure modes, context load — on demand. [[after-action]] judges a skill's **fitness** —
did it hold up in real work — automatically, at the end of every [[aios-ingest]]. One
trigger each; they never audit the same thing.

## Step 1 — Classify before you judge

For every candidate file, run:

```sh
sh AIOS/Systems/classify-skill.sh <path>
```

Never decide ownership yourself. It returns `KIND`, `OWNERSHIP`, `INVOCATION`, `DESC_TOKENS`.

- `OWNERSHIP=vault` → auditable **and** fixable (on confirmation).
- `OWNERSHIP=upstream` → **report only.** These live under `~/.claude/plugins/**` or are gstack/third-party installs; the next update overwrites any edit. For these the only real lever is recommending what to **disable**, never what to rewrite.

Candidates: `skills/*/SKILL.md`, `AIOS/Skills/*.md`, `.claude/skills/*/SKILL.md`. Add `~/.claude/skills/*/SKILL.md` and `~/.claude/plugins/**/SKILL.md` only when asked for a whole-system sweep — they are large and mostly upstream.

Subagents (`.claude/agents/*.md`) are **out of scope**. They carry a description that loads into the system prompt, so they do cost context — but they are a different artifact with a different schema, and `classify-skill.sh` returns `KIND=unknown` for them. Auditing their schema is a separate job, not a silent extension of this one; their *fitness* is [[after-action]]'s, which does take them in scope.

## Step 2 — Schema, per format

- `KIND=vault-note` — frontmatter (`tags`/`system`/`trigger`), and the four sections **Purpose**, **Steps**, **Dependencies**, **Output**.
- `KIND=portable` — YAML `name` + `description`. A description that restates the skill's identity instead of its **triggers** is a defect.
- `KIND=unknown` — report it; do not guess.

## Step 3 — Registration drift

Every skill appears in [[Skill Map]] under the right heading; [[Skill Map]] lists no skill that does not exist. Portable skills additionally appear in `~/.claude/skills/` as a symlink into the vault — if one is missing, the fix is `sh skills/link-global.sh`, never a hand-made link.

## Step 4 — The six failure modes

Ordered by how mechanically checkable they are. Only the first two are mechanical — a grep and a line count. The rest need a model reading the file, and everything from **Premature completion** down yields a **hypothesis**, not a fact. Rank a hypothesis below a mechanical finding, and say which is which in the report.

1. **Negation** *(grep)* — `don't` / `never` / `avoid`. Propose a positive rephrasing. Keep only hard guardrails you cannot phrase positively, and pair each with what to do instead.
2. **Sprawl** *(line count)* — length, absolute and against sibling skills. Report the outliers.
3. **Premature completion** *(read)* — a step whose completion criterion is missing or uncheckable. Quote the step and say what would make it checkable.
4. **Duplication** *(read)* — the same meaning in two places, within a skill or across two. Quote both.
5. **No-op** *(read)* — a line the model already obeys by default. **Settle a dispute by running the skill, not by debating it** (see Step 6).
6. **Sediment** *(read + `git log`)* — content no step references, unchanged across many commits.

## Step 5 — The two loads

For every `INVOCATION=model` skill, ask the question `skill-builder` asks: *must the agent reach this on its own, or must another skill reach it?* If neither, it is taxing every context window for nothing, and should become `disable-model-invocation: true`.

Rank the report by `DESC_TOKENS` reclaimed. Then report the **duplication clusters** — several skills competing for one trigger cost more than tokens: they contend, and the agent picks unpredictably.

## Step 6 — Contested findings

A no-op is model-relative: what one model already obeys, another does not. When I dispute a no-op or duplication finding, do not argue. Use the `skill-creator` plugin's eval/benchmark tooling to run the skill with and without the line and compare behaviour. Evidence, not debate.

## Step 7 — Report

Emit a stoplight report, ranked by tokens reclaimed and by duplication cluster. Separate **fixable** (`OWNERSHIP=vault`) from **report-only** (`OWNERSHIP=upstream`), and never mix a proposal to edit with a proposal to disable. Then stop, and fix only what I confirm.

**Dependencies:** [[skill-builder]], [[Skill Map]], `AIOS/Systems/classify-skill.sh`, `skill-creator` (for Step 6 only).
**Output:** an audit report. No edits without confirmation.
