# `skills/` — portable global skills

A different class from `AIOS/Skills/`.

- **`AIOS/Skills/*.md`** are *in-session* skills. They fire on a trigger phrase while you work inside the vault, and they're registered in [[Skill Map]].
- **`skills/<name>/SKILL.md`** are *portable global* skills. They're symlinked into `~/.claude/skills/`, where Claude Code discovers them one level deep in **every** project. No trigger phrase — routing is by each skill's `description` frontmatter.

The vault stays canonical: the real files live here, version-controlled, and edits are live everywhere immediately.

## Install

```bash
sh skills/link-global.sh    # idempotent; re-run after adding a skill
```

It symlinks each `skills/<name>/` into `~/.claude/skills/<name>`. It never overwrites a real file already sitting at a target name — it skips and tells you.

Don't run `npx skills add` against this repo. That installer relocates skills into `.agents/` and serves them repo-locally only, which defeats the point.

## What ships

| Skill | What it does | Needs before use |
|---|---|---|
| `create-cli` | CLI design rubric: args, flags, output contract, exit codes, dry-run | nothing (pure guidance) |
| `github-deep-review` | Evidence-first PR/issue review: root cause, best fix, provenance | `gh`, `rg`, `git` |
| `markdown-converter` | PDF / Office / HTML / YouTube → Markdown | `uv`/`uvx` — `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `one-password` | tmux-safe `op` secret read/store/inject, service-account-first | `op` CLI + `tmux`; export `OP_SERVICE_ACCOUNT_TOKEN` scoped to a restricted automation vault; set your own vault/item names |
| `reminders` | Apple Reminders via the `rem` CLI | `brew install rem`; grant macOS Reminders permission |
| `video-transcript-downloader` | yt-dlp transcript / audio / subtitle puller | `brew install yt-dlp ffmpeg`; `npm ci` in the skill dir |

`one-password` ships with placeholder vault and item names. **Fill them in before first use** — it will otherwise reach for a vault that doesn't exist.

## Adding one

1. Write `skills/<name>/SKILL.md` with `name` and `description` frontmatter. The `description` is what routes to it, so make it specific about *when* to fire.
2. Run `sh skills/link-global.sh`.
3. Register a one-line entry in `AIOS/Maps/Skill Map.md` under "Portable global skills". A skill that isn't in the map is invisible to the vault's AI.

## Provenance

Ported and de-personalized from [steipete/agent-scripts](https://github.com/steipete/agent-scripts). Author-specific plumbing was removed: hardcoded home paths repointed, private tooling and author-identity branches stripped, non-Claude agent configs dropped. Skills that hard-depended on the author's private infrastructure were not ported.
