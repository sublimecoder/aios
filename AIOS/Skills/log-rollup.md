---
tags: [aios, skill]
system: Janitor
trigger: "roll up the log" / monthly, when [[Log]] carries more than the current month
---
# log-rollup

**Purpose:** keep `AIOS/History/Log.md` lean. The active Log is read every session (the `/aios-log` wire and the SessionStart hook read it directly), so it must stay small — but entries are the audit trail and are never lost, only rotated into monthly archive files.

**Steps:**
1. Count all `- **YYYY-MM-DD**` entry bullets in `AIOS/History/Log.md` — this is the before-count.
2. For each month older than the current month with entries still in Log.md, move those entries into `AIOS/History/Log-YYYY-MM.md`. Create the archive if absent: frontmatter `tags: [memory, log, archive]`, title `# Memory Log — YYYY-MM (archived by log rotation)`, a line noting the rotation date, then the entries. Keep newest-first order within each file; when appending to an existing archive, merge so the whole file stays newest-first.
3. Never alter entry text — not a character. Entries are the audit trail; rotation moves them, it does not edit them.
4. Leave `Log.md` with: frontmatter + header, the current month's entries (newest at top), any standing format-blessing prose, and a pointer line at the bottom listing the archives newest-first: `Older: [[Log-2026-06]] · [[Log-2026-05]] …`. Update the pointer to include every archive file that exists.
5. **Verify:** re-count entry bullets across `Log.md` + all `Log-YYYY-MM.md` files. after-count must equal before-count. If it doesn't, stop and reconcile before committing — a lost Log line is a lost fact.
6. Commit the vault (Co-Authored-By trailer). Log a dated line in [[Log]]: `- **YYYY-MM-DD** — **aios/log-rollup** — rotated N entries into Log-YYYY-MM.md.`

**Constraints:** the `/aios-log` wire and the SessionStart hook read `Log.md` only — rotation must always leave the newest entries there; never rotate the current month. Entry text is immutable. Never delete an archive file. `AIOS/History/Log-YYYY-MM.md` is the only new-file destination.

**Dependencies:** [[Log]], `AIOS/History/Log-YYYY-MM.md` archives, [[aios-log]] (the wire that appends to Log.md). **Output:** a leaner Log.md + monthly archive files, entry count preserved exactly.
