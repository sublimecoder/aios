---
description: Roll older AIOS/History/Log.md entries into Log-YYYY-MM.md archives so the active Log stays small — entry text is moved verbatim, never rewritten or summarized.
---

Read and follow `AIOS/Skills/log-rollup.md`.

Arguments: `$ARGUMENTS` — an optional month to roll, or a target size. With no arguments,
roll whatever `aios-check.sh` reports as past its month.

The active Log is read every session (the SessionStart hook and the `/aios-log` wire both
read it directly), which is the whole reason it must stay small. Entries are the audit
trail: move them, split a month into `-b`/`-c` parts as it fills, and never edit entry
text on the way.
