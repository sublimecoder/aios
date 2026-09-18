---
tags: [aios, skill]
system: Janitor
trigger: "roll up the log" / when `wc -c AIOS/History/Log.md` exceeds 200000, or any `Log-*.md` exceeds 100000
---
# log-rollup

**Purpose:** keep `AIOS/History/Log.md` readable in one pass. The active Log is read every session (the `/aios-log` wire and the SessionStart hook read it directly), so it must stay small — but entries are the audit trail and are never lost, only rotated into archive files.

**The gate is BYTES, not the calendar.** Rotation used to fire only on months older than the current one, which silently stopped tracking the volume: by 2026-08-14 the Log held **166 entries, every one dated 2026-08** — 289KB that no month boundary would touch for another 17 days, while `Log-2026-07.md` had already reached **319KB**, larger than the live Log and past what an agent reads in one call. A calendar bucket sized for the June rate (~27KB/month) does nothing at the August rate (~20KB/day). Measure with `wc -c`, which reports the same unit the gate uses — the [[km-rotate]] gate needed a whole script (`AIOS/Systems/km-measure.sh`) because *its* unit was ambiguous between bytes and characters; this one is not, so no script is owed.

**Thresholds — three numbers, because the live Log and its archives answer different questions.**

| | Value | What it governs |
|---|---|---|
| `LOG_MAX` | **200,000 bytes** | `Log.md` trips here |
| `LOG_FLOOR` | **100,000 bytes** | a run rotates down to at least this |
| `ARCHIVE_MAX` | **100,000 bytes** | an archive splits into a new part here |

The floor is the point of the pair: rotating down to just-under-the-trip re-trips on the next entry and turns the gate into a daily nag, so a run rotates the oldest entries until the file is at or under the floor — at the 2026-08 rate (~20KB/day) that is roughly one rotation every five days.

**The archive cap is deliberately lower than the live trip.** `Log.md` is read often but almost always by tail (the SessionStart hook takes the newest handful), so its size is a cadence question. An archive is read rarely and, when it is read, is read *whole* by something hunting old context — so its size is a readability question, and 100,000 keeps every part inside one agent read with margin. `ARCHIVE_MAX` also matches `SHARD_MAX` in `AIOS/Systems/aios-check.sh`, which is the same readability question about project shards.

**Steps:**
1. Measure and count: `wc -c AIOS/History/Log.md`, and count all `- **YYYY-MM-DD**` entry bullets across `Log.md` and every `Log-*.md` archive — this is the before-count. Under `LOG_MAX` with no entry predating the current month, stop here and say so.
2. Choose what moves: walk entries oldest-first and select them until `Log.md` would sit at or under `LOG_FLOOR`. Entries predating the current month always move regardless of the byte math. **Always leave the newest entries in place** — the `/aios-log` wire and the SessionStart hook read `Log.md` only.
3. Move each selected entry into the archive for **its own month**, `AIOS/History/Log-YYYY-MM.md`. Create an absent archive matching the existing pattern: frontmatter `tags: [memory, log, archive]`, title `# Memory Log — YYYY-MM (archived by log rotation)`, a line noting the rotation date, then the entries. Keep newest-first order within each file; when appending to an existing archive, merge so the whole file stays newest-first.
4. Split an archive that reaches `ARCHIVE_MAX`: continue into `Log-YYYY-MM-b.md`, then `-c.md`, and so on, newest month-part first. **The first part keeps the plain `Log-YYYY-MM.md` name** — renaming it would break every wikilink already pointing at it. Each part carries the same frontmatter plus a line naming its date span.
5. Never alter entry text — not a character. Entries are the audit trail; rotation moves them, it does not edit them.
6. Leave `Log.md` with: frontmatter + header, the newest entries (newest at top), any standing format-blessing prose, and a pointer line at the bottom listing the archives newest-first: `Older: [[Log-2026-08]] · [[Log-2026-07]] …`. Update the pointer to include every archive file that exists, split parts included.
7. **Verify, by measurement:** re-run `wc -c` on `Log.md` (at or under `LOG_FLOOR`) and on every archive (each at or under `ARCHIVE_MAX`), and re-count entry bullets across all of them. After-count must equal before-count. If it doesn't, stop and reconcile before committing — a lost Log line is a lost fact.
8. Commit the vault (Co-Authored-By trailer). Log a dated line in [[Log]]: `- **YYYY-MM-DD** — **aios/log-rollup** — rotated N entries into <files>; Log.md NkB → MkB.`

**Constraints:** rotation always leaves the newest entries in `Log.md`. Entry text is immutable. Never delete an archive file, and never rename one that already exists. `AIOS/History/Log-YYYY-MM.md` and its `-b`/`-c` parts are the only new-file destinations.

**Dependencies:** [[Log]], `AIOS/History/Log-YYYY-MM.md` archives, [[aios-log]] (the wire that appends to Log.md), `AIOS/Systems/aios-check.sh` (echoes when `Log.md` is over `LOG_MAX` or an archive is over `ARCHIVE_MAX`). **Output:** a Log.md at or under the floor + archives each readable in one pass, entry count preserved exactly.
