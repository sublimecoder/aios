---
tags: [aios, map]
related: ["[[Vault Map]]", "[[Skill Map]]", "[[_Sources]]"]
---
# Knowledge Map

> Read-first catalog of what the wiki *knows* — entity, concept, and synthesis notes, grouped by scope, one line each. Distinct from [[Vault Map]] (navigation) and [[Skill Map]] (skills). Every query starts here before traversing links or reaching for search.

## How to use
At query time, read this first. Find the relevant scope and note, then follow its `[[wikilinks]]`. If the answer isn't here and isn't reachable by links, only then fall back to search. A good new answer worth keeping gets a note **and** a one-line entry added here. Raw inputs these notes summarize live in [[_Sources]] (immutable).

**This file is orchestrator-only.** Subagents return the exact line to add; the main session writes it. Parallel workers editing this file corrupt it.

## Why read-first beats search
Each line below is a compressed pointer: enough for the AI to decide *whether* to open the note, cheap enough that the whole map fits in context. That pushes the "now we need embeddings" threshold out to hundreds of notes. Keep each entry to one line — a map that no longer fits in context has stopped being a map.

Entry format:

```
- [[Note Name]] (kind) — the compressed claim: what this note actually knows, in enough
  detail to answer "is my answer in here?" without opening it. → `path/to/note.md`
```

`kind` is one of `person` · `entity` · `concept` · `operational` · `synthesis`.

---

<!-- BOOTSTRAP: one `## <Scope label>` heading per row in AIOS/Systems/layers.tsv.
     A single-scope vault has exactly one heading — that's normal. Keep each note's
     entry under the scope that owns it; an entry that spans two scopes is a smell. -->

## `<Scope label>`
_(empty — [[aios-ingest]] fills this as projects accumulate knowledge)_

---
_Maintained by [[aios-ingest]] and audited by [[wiki-lint]]. Sources: [[_Sources]]._
