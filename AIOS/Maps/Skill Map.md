---
tags: [aios, map]
related: ["[[Vault Map]]", "[[Knowledge Map]]"]
---
# Skill Map

> AI's playbook of every skill and system it can run, what each does, and the trigger phrase. In-session skills live in `AIOS/Skills/`; systems in `AIOS/Systems/`. Skills are plain markdown so they're portable across AI tools — never lock them inside an app.

## How to use a skill
When a message matches a trigger, open the matching note in `AIOS/Skills/`, follow its steps, respect its output location. If unsure which skill fits, ask.

## Skills grouped by System

### 🛠️ AI OS Autobuilder — build & maintain your AI assistant → [[AI OS Autobuilder]]
- [[me-builder]] — interviews you and builds/updates your `<scope>/me.md` files.
- [[vault-map]] (build mode) — writes/refreshes both halves of the [[Vault Map]] (navigation + creation rules).
- [[skill-builder]] — the playbook for creating a skill that behaves the same way every run (format choice, invocation mode, completion criteria, leading word, six failure modes) and registering it here.

### 🔱 Daily Trident — manage the day → [[Daily Trident]]
- [[daily-brief]] — one skill, two modes, one file (`AIOS/History/days/<date>.md`): morning mode = the day's brief (tasks/pipeline scan), evening mode = the day's log (what happened). Trigger aliases: "morning brief" / "daily brief" / "daily log" / "log my day". (Absorbed the former daily-log skill.)

### 🧭 Sherpa — map out a topic → [[Sherpa]]
- [[sherpa]] — asks universal questions about a topic, builds a starter MOC in your voice.
- [[style-guide-MOC]] — reference for what a well-shaped MOC looks like (used by sherpa).

### ♻️ Weekly Review — review the week → [[Weekly Review]]
- [[weekly-review]] — analyzes last week's review + this week's daily notes, fills a new review-preview in `AIOS/History/reviews/`.

### 💥 Rock Tumbler — fast feedback on creative work → [[Rock Tumbler]]
- [[rock-tumbler]] — thinking partner; surfaces blind spots and tensions, never writes the final product.
- [[style-guide-writing-AI]] — AI trope blacklist; language to avoid in outputs.
- [[style-guide-writing-me]] — your lightweight personal style guide.

### 🪶 Chronicler — save conversations → [[Chronicler]]
- [[chronicle]] — save conversation content to a note, three modes: verbatim (word-for-word), summary (fixed structure), append (chunk into today's daily note). (Merged verbatim + summarizer + quick-append.)

### 🧹 Janitor — maintain notes & assistant → [[Janitor]]
- [[propagate]] — sweep one change across every note that carries it: a rename or a convention. (Merged cascade + harmonize.)
- [[vault-map]] (audit mode) — compares both halves of the Vault Map to reality, proposes fixes. (Merged the -builder and -janitor vault-map skills.)
- [[skills-janitor]] — audits skills against [[skill-builder]] (schema + six failure modes + invocation cost via `AIOS/Systems/classify-skill.sh`); proposes, never rewrites.
- [[log-rollup]] — rotates months older than the current one out of [[Log]] into `Log-YYYY-MM.md` archives; entry text immutable, count verified.
- [[km-rotate]] — shrinks ballooned [[Knowledge Map]] lines back to one-line summaries, moving dated activity clauses into the notes; never drops a fact.
- [[open-flags]] — registers every ⚠️/OPEN marker in project notes, forces a disposition during ingest, escalates flags older than 30 days.
- [[wiki-lint]] — health-checks the knowledge wiki (schema → staleness → gaps → drift → orphans → dupes → contradictions), emits a 🟢/🟡/🔴 report, proposes fixes only. Trigger: "lint the wiki". Also `/wiki-lint`; isolated run via the `wiki-lint-runner` subagent.

### 📦 Courier — share notes between vaults & people → [[Courier]]
- [[sanitize]] — duplicate a note and produce a shareable version with personal details removed/flagged. **Use before sharing anything outside this vault.**
- [[collator]] — read a note, append summaries of every linked note into one self-contained shareable file.
- [[courier]] — duplicate a note from this vault to another vault for sharing.

### 🎛️ Orchestrator — delegate heavy work to subagents → [[Orchestrator]]
Doctrine + model routing live in [[Orchestrator]]. These are **agents**, not skills — thin Claude Code adapters in `.claude/agents/`, registered here so the brain knows they exist:
- `wiki-lint-runner` — isolated run of [[wiki-lint]] (read-only).
- `layer-leak-auditor` — cross-scope leak check before any external action (read-only). Only useful if you enabled the optional wall in `layers.tsv`.
- `ingest-worker` — one queued digest → its project note; fan out during [[aios-ingest]].
- `wiki-query` — cited answer from one scope's wiki (read-only Query op).
- `graphify-scout` — graph-first codebase recon: `graphify-out/` query, grep-verified `file:line` map. Dispatch before Explore/grep for "where does X live" questions.
- `publish-verify` — post-publish check of a live URL/repo push: cross-scope token grep + first-person claim trace (unsourced = fabrication-risk). Read-only.

### 🔌 AIOS Wire — cross-repo knowledge sync
The mechanism that lets a coding session in *any* repo feed this vault without ever writing to that repo. See `AIOS/Systems/hooks/`.
- [[aios-log]] — capture a fact/decision into the vault (scope auto-detected from cwd). Trigger: `/aios-log`.
- [[aios-ingest]] — compound queued session digests into the wiki (run in the vault). Trigger: `/aios-ingest`.

## 🧰 Portable global skills (`skills/`, all projects)
A different class from everything above. `skills/<name>/SKILL.md` files are symlinked into `~/.claude/skills/` by `skills/link-global.sh`, so Claude Code **auto-discovers** them in every project — no vault trigger phrase, routing is by each skill's `description`. Setup and provenance: `skills/README.md`.

- `create-cli` — CLI design rubric: args, flags, output contract, exit codes. Ready now.
- `github-deep-review` — evidence-first PR/issue review: root cause, best fix, provenance. Needs `gh`.
- `markdown-converter` — PDF/Office/HTML/YouTube → Markdown. Needs `uvx`.
- `one-password` — tmux-safe `op` secret read/store/inject, service-account-first. Needs `op`; set your vault/item names first.
- `reminders` — Apple Reminders via the `rem` CLI. Needs `rem` + macOS permission.
- `video-transcript-downloader` — yt-dlp transcript/audio/subtitle puller. Needs `yt-dlp`; `npm ci` in the skill dir.

New portable skill: add `skills/<name>/SKILL.md`, run `sh skills/link-global.sh`, register the line here.

## Adding a skill
Write `AIOS/Skills/<name>.md` per [[skill-builder]]'s schema, then register the one-line description here under its system. A skill that isn't in this map does not exist, as far as the AI is concerned.
