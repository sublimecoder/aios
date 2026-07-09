# AIOS — an AI Operating System in plain markdown

A vault your coding agent reads at the start of every session, writes back to at the end of every session, and gets smarter from over time.

No plugins, no database, no lock-in. Every file is markdown you can read, edit, and grep. It works with Claude Code today; it'll work with whatever replaces it, because the whole thing is prose and shell scripts.

## The idea

Coding agents forget everything between sessions. The usual fixes — a bigger context window, a vector store, a `CLAUDE.md` that grows until nobody reads it — all treat memory as a retrieval problem.

AIOS treats it as an **editorial** problem. Sessions produce raw signal (commits, diffs, decisions). A periodic ingest pass compounds that signal into durable, hand-shaped project notes. A read-first index — the `Knowledge Map` — points at them, one line each, cheap enough to load whole.

That inverts the usual retrieval order:

1. **Direct-load the core.** `CLAUDE.md`, your `me-*` file, the three Maps. Always in context.
2. **Graph-traverse the meaningful.** Read the `Knowledge Map`, follow `[[wikilinks]]`.
3. **RAG the tail.** Only when the first two miss.

A curated map read first beats vector search well into the hundreds of notes. Embeddings are the last resort, not the default.

## Quickstart

```bash
git clone <this-repo> ~/code/aios && cd ~/code/aios
rm -rf .git && git init          # start your own history; this vault will hold private things
claude
```

Then, in the session:

```
/aios-bootstrap
```

It interviews you for ten minutes and writes your vault: your scopes, your `me-*` files, your maps, your repo wiring. Everything after that is you using it.

If you'd rather see what it's going to ask before you commit to anything, read [`BOOTSTRAP.md`](BOOTSTRAP.md) — that file *is* the prompt.

## What's in the box

| Piece | What it does |
|---|---|
| `CLAUDE.md` | Entry point. Read first, every session. |
| `AIOS/Systems/layers.tsv` | **Scopes** — how the vault partitions context. One scope is normal. |
| `AIOS/me-<scope>.md` | Who you are in each context, and how you want to be worked with. |
| `AIOS/Maps/Vault Map.md` | Navigation: where things live, where new notes go. |
| `AIOS/Maps/Skill Map.md` | Every skill the AI can run, and its trigger phrase. |
| `AIOS/Maps/Knowledge Map.md` | The read-first index of what the wiki knows. |
| `AIOS/Skills/*.md` | ~25 plain-markdown skills. Portable across tools. |
| `AIOS/Systems/hooks/` | The cross-repo wire (below). |
| `.claude/agents/` | Subagents that keep read-heavy work out of your main context. |
| `.claude/hooks/vault-write-guard.sh` | Mechanically enforces the vault's invariants. |

## The cross-repo wire

The part that makes it compound.

Register a code repo in `AIOS/Systems/repo-layers.tsv`, then add two hooks to *that repo's* `.claude/settings.json`:

- **SessionStart** → `aios-context.sh` loads that project's accumulated brain into the session, so the agent starts knowing what it learned last time.
- **Stop** → `aios-digest.sh` appends a signal-only digest (branch, commits, diff-stat, any native memory that changed) to a queue in the vault.

Both scripts write **only to the vault**, never to the invoking repo. A repo that isn't in the manifest is a silent no-op — the scope is never guessed.

Later, from the vault, `/aios-ingest` compounds the queue into `AIOS/Projects/<scope>/<project>.md` and updates the `Knowledge Map`. Fan it out one subagent per digest and it stays cheap.

The loop: **code → digest → ingest → brain → next session's context.**

## Scopes, and the optional wall

A **scope** is a bucket of context — a job, a side project, a client. It routes notes, sources, and project memory, so an unrelated project's history never pollutes the one you're in.

**One scope is a completely normal setup.** Most people should start there.

Some people need more than routing: two contexts that must never appear in the same file. A pen name that can't be tied to a legal name. Employer code that can't reach a public portfolio or a job application. One client's internals that can't surface in another's repo.

For them, `layers.tsv` has a `tokens` column. Fill it in and two mechanisms come alive:

- **Write time** — a `PreToolUse` hook blocks a write that drops one scope's tokens into another scope's folders. Cheap grep, near-zero false positives.
- **Publish time** — the `layer-leak-auditor` subagent catches the inferred crossings a grep can't: a codename, a URL, two individually-safe facts that are jointly identifying.

Leave `tokens` as `-` (the default) and both stay inert. The guard's other two rules — `Sources/` is immutable, the AI never authors new `Atlas/` notes — apply either way.

```bash
bash .claude/hooks/test_vault_write_guard.sh   # 21 passed, 0 failed
```

## Folder framework

LYT's ACE, plus `AIOS/`:

```
+/         Inbox — raw captures land here
AIOS/      The AI OS: me-* files, Maps, Skills, Systems, History, Projects
Atlas/     Timeless knowledge. Hand-written; the AI proposes, never creates
Calendar/  Days/ and Reviews/
Efforts/   Works & projects
Sources/   Immutable curated inputs, partitioned by scope. Read-only, enforced
x/         Templates, attachments, old design docs
```

## Design notes

- **Markdown or nothing.** Skills, systems, identity, memory — all prose. `.claude/agents/*.md` are thin adapters for one harness; the canonical behavior lives in `AIOS/`. Swap the tool, keep the OS.
- **The manifest is never guessed.** An unlisted repo produces no context and no digest. Silent no-op beats a wrong guess.
- **Subagents return conclusions, not file dumps.** Their read-noise stays in their own context. Shared files (`Knowledge Map`, `Log.md`) are orchestrator-only — parallel workers editing them corrupt them.
- **Digests are signal, not prose.** Branch, commits, diff-stat. Meaning is synthesized at ingest time by a model that can see the whole queue, not scraped at commit time.
- **If any scope is private, keep the repo private.** Git history is forever.

## Optional extensions we use but don't ship

- **Nightly ingest** — `AIOS/Systems/hooks/aios-nightly-ingest.sh` runs `/aios-ingest` headless under launchd with a scoped tool allowlist. Wire it to a `launchd` plist if you want the queue drained while you sleep.
- **Structural graph cross-check** — running a knowledge-graph extractor over the vault and reading its "surprising connections" report alongside `wiki-lint` catches links a hand-curated map missed. Not shipped: it needs an external extractor and per-vault tuning.

## License

MIT. See [LICENSE](LICENSE).
