---
tags: [aios, skill]
system: AI OS Autobuilder
trigger: "create a skill" / "build a new skill"
---
# skill-builder

**Purpose:** the playbook AI uses to create a skill that behaves the *same way* every run, and to register it where it will be found.

A skill exists to wrangle determinism out of a stochastic system. **Predictability** — the agent taking the same *process* every run, not producing the same output — is the root virtue. A brainstorming skill should *predictably* diverge: its tokens vary, its behaviour does not.

## Step 1 — Which format?

Two live in this vault. They are not interchangeable.

- **Portable skill** → `skills/<name>/SKILL.md`. Cross-agent format (YAML `name` + `description`, optional `disable-model-invocation`). Symlinked into `~/.claude/skills/` by `skills/link-global.sh`, so it works in **every** project. Choose this when the skill is useful outside the vault.
- **Vault note** → `AIOS/Skills/<name>.md`. Frontmatter `tags: [aios, skill]`, `system`, `trigger`; body of **Purpose**, **Steps**, **Dependencies**, **Output**. In-session only; never symlinked. Choose this when the skill only makes sense with the vault open.

If unsure, ask. A vault note that wanted to be portable is invisible from every other repo.

## Step 2 — Portable skills only: choose the invocation mode

This is a trade between two loads.

- **Model-invoked** (omit `disable-model-invocation`) — the agent can fire it autonomously, *and other skills can reach it*. Costs **context load**: its `description` sits in the window on every single turn, forever.
- **User-invoked** (`disable-model-invocation: true`) — zero context load. Costs **cognitive load**: *you* become the index that must remember it exists. No other skill can reach it, because it exposes no description.

**Pick model-invocation only when the agent must reach the skill on its own, or another skill must.** Everything else is user-invoked.

A user-invoked skill may invoke model-invoked skills. It may **never** invoke another user-invoked one — nothing but the human can reach those. It may only *hint* that you run them.

## Step 3 — Give every step a completion criterion

Two independent axes:

- **Clarity** — can the agent tell done from not-done? A checkable criterion resists **premature completion**, where attention slips to *being done* before the step genuinely is.
- **Demand** — "every modified model accounted for" is demanding; "produce a change list" is not. Demand drives legwork.

A flat reference page with no steps still needs one: *every rule applied*.

## Step 4 — Choose a leading word

A **leading word** is a compact concept already living in the model's pretraining, which the agent thinks *with* while running the skill — *tracer bullet*, *fog of war*, *red*, *relentless*. It anchors a whole region of behaviour in the fewest tokens by recruiting priors the model already holds.

Grade it with the no-op test: if the model already behaves that way by default, the word buys nothing. *Be thorough*, when the agent is already thorough-ish, is a no-op; the fix is a stronger word (*relentless*), not a different technique.

Coined words work, but recruit no priors — you pay in definition tokens what a pretrained word gives free.

## Step 5 — Write it, avoiding the six failure modes

1. **Premature completion** — ending a step before it is genuinely done. Sharpen the criterion first; only split the skill if the criterion is irreducibly fuzzy *and* you have observed the rush.
2. **Duplication** — the same meaning in more than one place. It inflates a meaning's prominence past its real rank. (The accidental inverse of a leading word, which repeats a *token* on purpose, never the meaning.)
3. **Sediment** — stale layers that settle because adding feels safe and removing feels risky. The default fate of any skill without a pruning discipline.
4. **Sprawl** — length itself, even when every line is live and unique.
5. **No-op** — a line the model already obeys by default, so you pay load to say nothing. Settle a dispute by *running the skill*, not by debating it.
6. **Negation** — steering by prohibition backfires; *don't think of an elephant* names the elephant. Prompt the **positive**. Keep a prohibition only as a hard guardrail you cannot phrase positively, and even then pair it with what to do instead.

Write the description to carry **triggers, not identity**. Front-load the skill's leading word. One trigger per branch — synonyms that rename a single branch are duplication.

## Step 6 — Register it, or it does not exist

- **Portable:** run `sh skills/link-global.sh` (`--dry-run` first). Add a line to [[Skill Map]] under *Portable global skills*.
- **Vault note:** add a line to [[Skill Map]] under its system.
- Both: append a dated line to [[Log]].

An unregistered skill is one nobody — including the next session — will find.

## Completion

Done when: the format is chosen deliberately; a portable skill's invocation mode is justified by the two-loads test in one sentence; every step has a checkable, demanding criterion; a leading word has been chosen and survives the no-op test; the file survives a read-through against all six failure modes; and the skill appears in [[Skill Map]] and [[Log]].

**Dependencies:** [[Skill Map]], [[Log]], `skills/link-global.sh`.
**Output:** `skills/<name>/SKILL.md` or `AIOS/Skills/<name>.md`, plus a Skill Map entry and a Log line.
