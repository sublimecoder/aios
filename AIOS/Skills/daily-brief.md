---
tags: [aios, skill]
system: Daily Trident
trigger: "daily brief"
---
# daily-brief

**Purpose:** pull the day's reference points into one shared working doc between me and AI.

**Steps:**
1. Get today's date (`date +%F`).
2. Pull: recently modified notes, whatever this vault treats as an active pipeline, open `- [ ]` tasks, stale [[Inbox]] items.
3. Read the relevant me layer for context; do not surface `Atlas/Life/` private items unless asked.
4. Write `Calendar/Days/<date>.md` with: In flight, Open tasks, Focus first (top 1-3 with one-line reason).
5. If today's note exists, update it instead of duplicating.

**Dependencies:** none. **Output:** `Calendar/Days/<date>.md`.
