---
tags: [aios, skill]
system: Janitor
trigger: "lint the wiki" / "wiki lint"
---
# wiki-lint

**Purpose:** health-check the knowledge wiki (the `Sources/` inputs, the entity/concept/synthesis notes, [[Knowledge Map]], [[Log]]) and emit a 🟢/🟡/🔴 report. Proposes fixes only — it never deletes a file and never edits a content page (that's ingest's job).

**Steps (run the checks in this order; stop-light each one):**
1. **Schema integrity** — every wiki note has the required frontmatter (`type`, `layer`, `updated`, `sources`); `layer` is exactly one of the scopes declared in `AIOS/Systems/layers.tsv`; no note mixes scopes.
2. **Staleness** — flag notes whose `updated` predates the source they summarize, or that are past a staleness window. List them; don't touch them.
3. **Coverage gaps** — sources in `Sources/<scope>/` with no note summarizing them, and notes/links referenced but never created.
4. **Overview drift** — [[Knowledge Map]] and any synthesis/MOC notes out of sync with the notes that actually exist (missing entries, dead entries).
5. **Orphans** — notes with no inbound `[[wikilinks]]` and absent from [[Knowledge Map]].
6. **Duplicates** — two or more notes covering the same subject/entity. Blessed exemption: historical [[Log]] entries keep their original link text — never flag or repoint bare links inside dated Log entries; the path+alias convention applies to live pages only.
7. **Contradictions** — notes making conflicting claims; surface both sides, never auto-resolve.
8. Emit the report: one 🟢/🟡/🔴 line per check above, then a numbered list of proposed fixes. Apply only on my confirmation, and only via the ingest path — this skill never edits content pages itself.
9. Log a dated line in [[Log]] using the standard bullet format: `- **YYYY-MM-DD** — **lint** — <scope> + stoplight summary` (newest at top, same as every other entry).

**Scoped run (the common case):** when invoked from an ingest ([[aios-ingest]] step 4), the inputs are the ingest's touched notes. Run the same dimensions above over just that neighborhood — the touched notes, their [[Knowledge Map]] lines, and the new [[Log]] entries — and emit the same 🟢/🟡/🔴 report, marked **"scoped"**. A full-vault sweep is the periodic exception, not the default.

**Constraints:** read-only on `Sources/` (immutable) and on every content page. Never delete a file. Lint one scope at a time unless I ask for every scope in `AIOS/Systems/layers.tsv` — a synthesis that spans scopes is the thing this vault exists to avoid.

**Dependencies:** [[Knowledge Map]], [[Log]], [[skill-builder]] (frontmatter schema), [[_Sources]]. **Output:** stoplight audit report + proposed fixes (no auto-apply).

**Isolated run:** the `wiki-lint-runner` subagent (`.claude/agents/wiki-lint-runner.md`) executes these exact steps read-only (`Read`/`Grep`/`Glob` only) in its own context, so the file-reading noise of a full scan doesn't fill the main conversation — it hands back the stoplight report + proposed fixes for you to apply (via ingest) or log yourself.
