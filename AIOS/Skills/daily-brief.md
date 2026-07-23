---
tags: [aios, skill]
system: Daily Trident
trigger: "daily brief" / "morning brief" / "daily log" / "log my day"
---
# daily-brief

**Purpose:** one skill, two modes, one file. Morning mode writes the day's brief (tasks/pipeline scan); evening mode logs what happened. Both write `Calendar/Days/<date>.md`. On-demand — [[Log]] is the primary time-based record; `Calendar/Days/` is the human-facing view. (Absorbed the former daily-log skill.)

**Mode pick:** "morning brief" / "daily brief" → morning mode. "daily log" / "log my day" → evening mode.

**Steps (morning mode — the brief):**
1. Get today's date (`date +%F`).
2. Read the relevant me file for context; do not surface `Atlas/Life/` private items unless asked.
3. Open tasks: search `- [ ]` across the vault, excluding `x/System Docs/`.
4. Pull: recently modified notes, whatever this vault treats as an active pipeline, stale [[Inbox]] items.
5. Write `Calendar/Days/<date>.md` with: In flight, Open tasks, Focus first (top 1-3 with one-line reason). If today's note exists, update it — never duplicate.

**Steps (evening mode — the log):**
1. Get today's date and time.
2. Scan the day's file changes in the vault and notable actions from this session.
3. Append timestamped bullet entries to a log section in `Calendar/Days/<date>.md` (create the note if missing). Keep entries factual and short.

**Dependencies:** none. **Output:** `Calendar/Days/<date>.md`.
