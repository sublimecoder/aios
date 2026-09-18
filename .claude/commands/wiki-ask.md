---
description: Answer a question from the knowledge wiki for ONE identity layer — Knowledge Map first, then wikilink traversal, returning a cited answer. Read-only.
argument-hint: <question> [layer: creator|professional|work]
---

Dispatch the `wiki-query` subagent (`.claude/agents/wiki-query.md`) with: $ARGUMENTS
(If empty, ask what to look up — and which layer — then proceed.)
