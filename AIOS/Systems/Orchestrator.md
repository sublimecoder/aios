---
tags: [aios, system]
related: ["[[Skill Map]]", "[[Vault Map]]"]
---
# 🎛️ Orchestrator

**Purpose:** the main session directs; subagents grind. Keeps the main context clean, the identity wall intact, and the expensive model doing only the work that needs it.

## Doctrine (model-agnostic)
- **The main session is the orchestrator.** It holds the identity/layer context, makes the judgment calls, and delegates bulk reads, scans, audits, and per-item mechanical work to subagents running in isolated contexts.
- **Subagents return conclusions, not file dumps.** Their read-noise stays in their own context.
- **One scope per subagent invocation.** Scopes in `AIOS/Systems/layers.tsv` carry down — never hand a subagent a cross-scope task. Keeps synthesis coherent; also carries the optional wall, if enabled.
- **Shared files are orchestrator-only.** `AIOS/History/Log.md` and `[[Knowledge Map]]` are written only by the main session; subagents return the exact lines to append. A subagent may write only files it exclusively owns for the task (e.g. one project note).
- **Portability:** definitions in `.claude/agents/` are thin harness adapters for Claude Code. Canonical behavior lives in `AIOS/` markdown (skills, this note), so the OS survives a change of AI tool.

## Model routing (the only place model names live)
| Work | Tier | Model |
|---|---|---|
| Orchestration, synthesis, judgment, anything touching the identity wall | Strongest durable | `<your strongest model>` |
| Mid-weight drafting/analysis in an isolated context | Mid | `<mid tier>` |
| Mechanical scans, greps, per-digest grunt work | Fast | `<fast tier>` |

Pin automated/unattended runs to the strongest **durable** model, not to whatever preview you have access to this month.

When models rename, update this table only — the doctrine above doesn't change.

## Agent roster (adapters in `.claude/agents/`)
- **wiki-lint-runner** — isolated wiki health-check; follows [[wiki-lint]]. Read-only.
- **layer-leak-auditor** — checks a note/file/diff for cross-layer identity leaks before any external action. Read-only.
- **ingest-worker** — processes ONE queued session digest per [[aios-ingest]] step 1; writes only its own project note, returns the KM + Log lines. Fan out one worker per digest; orchestrator applies shared writes, runs the leak gate, archives, commits.
- **wiki-query** — read-only wiki researcher for one layer: Knowledge Map → wikilink traversal → cited answer. Orchestrator files the answer as a note if it's worth keeping.

Add a new agent only when a job measurably bloats the main session; register it here and in [[Skill Map]].
