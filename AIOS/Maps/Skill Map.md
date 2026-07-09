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
- [[me-builder]] — interviews you and builds/updates your `me-<scope>` files.
- [[navigation-builder]] — builds the 1st half of the [[Vault Map]] (how AI navigates).
- [[creation-builder]] — builds the 2nd half of the [[Vault Map]] (how AI creates notes, templates, defaults).
- [[skill-builder]] — the format AI uses to create new skills and register them here.

### 🔱 Daily Trident — manage the day → [[Daily Trident]]
- [[daily-brief]] — pulls recent notes, active pipeline, focus into one working doc in `Calendar/Days/`.
- [[daily-log]] — scans the day's changes and writes timestamped entries to today's log.

### 🧭 Sherpa — map out a topic → [[Sherpa]]
- [[sherpa]] — asks universal questions about a topic, builds a starter MOC in your voice.
- [[style-guide-MOC]] — reference for what a well-shaped MOC looks like (used by sherpa).

### ♻️ Weekly Review — review the week → [[Weekly Review]]
- [[weekly-review]] — analyzes last week's review + this week's daily notes, fills a new review-preview in `Calendar/Reviews/`.

### 💥 Rock Tumbler — fast feedback on creative work → [[Rock Tumbler]]
- [[rock-tumbler]] — thinking partner; surfaces blind spots and tensions, never writes the final product.
- [[style-guide-writing-AI]] — AI trope blacklist; language to avoid in outputs.
- [[style-guide-writing-me]] — your lightweight personal style guide.

### 🪶 Chronicler — save conversations → [[Chronicler]]
- [[verbatim]] — save an AI conversation word-for-word to a note.
- [[summarizer]] — summarize a convo/meeting/transcript into a fixed structure.
- [[quick-append]] — append a chunk of an AI conversation to a note (defaults to today's daily note).

### 🧹 Janitor — maintain notes & assistant → [[Janitor]]
- [[cascade]] — propagate a name change across body, frontmatter, paths, scheduled tasks.
- [[harmonize]] — propagate a convention change across notes that share conventions.
- [[navigation-janitor]] — audits the 1st half of the Vault Map for alignment.
- [[creation-janitor]] — audits the 2nd half of the Vault Map for alignment.
- [[skills-janitor]] — audits skill files against the skill-builder schema, fixes drift.
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
