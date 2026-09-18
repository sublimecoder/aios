# AIOS — an AI Operating System in plain markdown

A vault your coding agent reads at the start of every session, writes back to at the end of every session, and gets smarter from over time.

No plugins, no database, no lock-in. Every file is markdown you can read, edit, and grep. It works with Claude Code today; it'll work with whatever replaces it, because the whole thing is prose and shell scripts.

## The idea

Coding agents forget everything between sessions. The usual fixes — a bigger context window, a vector store, a `CLAUDE.md` that grows until nobody reads it — all treat memory as a retrieval problem.

AIOS treats it as an **editorial** problem. Sessions produce raw signal (commits, diffs, decisions). A periodic ingest pass compounds that signal into durable, hand-shaped project notes. A read-first index — the `Knowledge Map` — points at them, one line each, cheap enough to load whole.

That inverts the usual retrieval order:

1. **Direct-load the core.** `CLAUDE.md`, your `me.md`, the three Maps. Always in context.
2. **Graph-traverse the meaningful.** Read the `Knowledge Map`, follow `[[wikilinks]]`.
3. **RAG the tail.** Only when the first two miss.

A curated map read first beats vector search well into the hundreds of notes. Embeddings are the last resort, not the default.

## Quickstart

```bash
git clone https://github.com/sublimecoder/aios ~/code/aios && cd ~/code/aios
rm -rf .git && git init          # start your own history; this vault will hold private things
claude
```

Then, in the session:

```
/aios-bootstrap
```

It interviews you for ten minutes and writes your vault: your scopes, your `me.md` files, your maps, your repo wiring. Everything after that is you using it.

If you'd rather see what it's going to ask before you commit to anything, read [`BOOTSTRAP.md`](BOOTSTRAP.md) — that file *is* the prompt.

## What's in the box

| Piece | What it does |
|---|---|
| `CLAUDE.md` | Entry point. Read first, every session. |
| `AIOS/Systems/layers.tsv` | **Scopes** — how the vault partitions context. One scope is normal. |
| `<scope>/me.md` | Who you are in each context, and how you want to be worked with. |
| `AIOS/Maps/Vault Map.md` | Navigation: where things live, where new notes go. |
| `AIOS/Maps/Skill Map.md` | Every skill the AI can run, and its trigger phrase. |
| `AIOS/Maps/Knowledge Map.md` | The read-first index of what the wiki knows. |
| `AIOS/Skills/*.md` | ~25 plain-markdown skills. Portable across tools. |
| `AIOS/Systems/hooks/` | The cross-repo wire (below). |
| `AIOS/Systems/templates/` | `CLAUDE.local.md` scaffold dropped into each wired repo. |
| `.claude/agents/` | Subagents that keep read-heavy work out of your main context. |
| `.claude/hooks/vault-write-guard.sh` | Mechanically enforces the vault's invariants at write time (Rules A–G). |
| `AIOS/Systems/hooks/rules-lib.sh` | The one place the guard's literal patterns live. Assignments only. |
| `AIOS/Systems/aios-check.sh` | Health check. Prints only failures, exits 1 if any. Hang it off SessionStart. |
| `AIOS/Systems/aios-install.sh` | Wires **this machine** to the vault. Idempotent, dry-run by default. |
| `AIOS/Systems/aios-scheduler.sh` | Installs/moves the scheduled-ingest timers. Exactly one machine may own them. |
| `AIOS/Systems/effort-table.md` | Task type → model. The one place model names live. |
| `AIOS/Systems/reasoning-doctrine.md` | Standing cognitive procedures, written as orders, not advice. |
| `scripts/aios-wire-repo.sh` | Connects a code repo to the vault. Idempotent; the only thing here that writes to a repo. |
| `scripts/aios-install-nightly.sh` | Older launchd/cron scheduler, superseded by `aios-scheduler.sh`. |

## Is it actually wired?

The rules above are enforced by hooks, and **each agent harness has its own hook
table.** Claude Code reads `.claude/settings.json`, which is committed here, so
cloning the repo wires it. Another harness reads a config that lives outside the
repo — so a fresh machine can get a vault whose guard never runs, silently,
because *an unenforced rule looks exactly like an obeyed one.*

Two commands, both idempotent:

```bash
sh AIOS/Systems/aios-install.sh          # show what would change
sh AIOS/Systems/aios-install.sh --apply  # wire it
sh AIOS/Systems/aios-check.sh            # quiet when clean, exit 1 when not
```

`aios-check.sh` is the one to hang off SessionStart. It is detection only —
nothing it reports does it fix — and every finding names the skill that does.

## The cross-repo wire

The part that makes it compound. Full detail: [`docs/install.md`](docs/install.md).

```bash
scripts/aios-wire-repo.sh ~/code/acme-api work    # one command per repo
scripts/aios-install-nightly.sh                   # drain the queue at 03:00
```

Wiring a repo adds a row to `AIOS/Systems/repo-layers.tsv`, merges two hooks into *that repo's* `.claude/settings.json`, and drops a git-ignored `CLAUDE.local.md` pointing back at the vault:

- **SessionStart** → `aios-context.sh` loads that project's accumulated brain into the session, so the agent starts knowing what it learned last time.
- **Stop** → `aios-digest.sh` appends a signal-only digest (branch, commits, diff-stat, any native memory that changed) to a queue in the vault.
- **`CLAUDE.local.md`** names the scope, points at the brain, and states the rule that the vault is written through `/aios-log` and never by hand. It's the durable layer for the contexts a hook doesn't reach — subagents, `claude -p`, other editors.

Both hooks write **only to the vault**, never to the invoking repo. A repo that isn't in the manifest is a silent no-op — the scope is never guessed.

Nightly, `/aios-ingest` compounds the queue into `<scope>/projects/<project>.md` and updates the `Knowledge Map`, fanning out one subagent per digest. Mid-session, `/aios-log <fact>` captures a decision immediately.

The loop: **code → digest → ingest → brain → next session's context.**

Verify any of it:

```bash
scripts/aios-wire-repo.sh --check ~/code/acme-api
scripts/aios-install-nightly.sh --status
scripts/aios-install-nightly.sh --dry-run
```

## Scopes, and the optional wall

A **scope** is a bucket of context — a job, a side project, a client. It routes notes, sources, and project memory, so an unrelated project's history never pollutes the one you're in.

**One scope is a completely normal setup.** Most people should start there.

Some people need more than routing: two contexts that must never appear in the same file. A pen name that can't be tied to a legal name. Employer code that can't reach a public portfolio or a job application. One client's internals that can't surface in another's repo.

For them, `layers.tsv` has a `tokens` column. Fill it in and two mechanisms come alive:

- **Write time** — a `PreToolUse` hook blocks a write that drops one scope's tokens into another scope's folders. Cheap grep, near-zero false positives.
- **Publish time** — the `layer-leak-auditor` subagent catches the inferred crossings a grep can't: a codename, a URL, two individually-safe facts that are jointly identifying.

Leave `tokens` as `-` (the default) and both stay inert. The guard's other two rules — `<scope>/sources/` is immutable, the AI never authors new `<scope>/notes/` notes — apply either way.

## Verify

Every moving part has a self-check. None of them touch your real vault, LaunchAgents, or crontab.

```bash
bash .claude/hooks/test_vault_write_guard.sh   # 23 passed, 0 failed
bash scripts/test_aios_wire_repo.sh            # 25 passed, 0 failed
bash scripts/test_aios_install_nightly.sh      # 15 passed, 0 failed
```

## Folder framework

Scope-first — the scope IS the filesystem:

```
+/           Inbox — raw captures land here
AIOS/        The AI OS (scope-neutral): Maps, Skills, Systems, History
<scope>/     One dir per scope in layers.tsv (default: main/)
  me.md        Who you are in this context — read first
  notes/       Timeless knowledge. Hand-written; the AI proposes, never creates
  content/     Drafts and works-in-progress
  projects/    AI-maintained project brains, one per wired repo
  sources/     Immutable curated inputs. Read-only, enforced
archive/     Templates, attachments, old design docs
```

A path's first segment names its scope — the one prefix the write guard, ingest, and leak audits all key on. (v1 of this template used LYT's ACE folders; `docs/structure-evolution.md` records the evolution and why we'd start scope-first today.)

## Design notes

- **Markdown or nothing.** Skills, systems, identity, memory — all prose. `.claude/agents/*.md` are thin adapters for one harness; the canonical behavior lives in `AIOS/`. Swap the tool, keep the OS.
- **The manifest is never guessed.** An unlisted repo produces no context and no digest. Silent no-op beats a wrong guess.
- **Subagents return conclusions, not file dumps.** Their read-noise stays in their own context. Shared files (`Knowledge Map`, `Log.md`) are orchestrator-only — parallel workers editing them corrupt them.
- **Digests are signal, not prose.** Branch, commits, diff-stat. Meaning is synthesized at ingest time by a model that can see the whole queue, not scraped at commit time.
- **If any scope is private, keep the repo private.** Git history is forever.

## Optional extensions we use but don't ship

- **Structural graph cross-check** — running a knowledge-graph extractor over the vault and reading its "surprising connections" report alongside `wiki-lint` catches links a hand-curated map missed. Not shipped: it needs an external extractor and per-vault tuning.

## License

MIT. See [LICENSE](LICENSE).
