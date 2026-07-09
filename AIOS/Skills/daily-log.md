---
tags: [aios, skill]
system: Daily Trident
trigger: "log my day" / "daily log"
---
# daily-log

**Purpose:** auto-scan the day's changes and write timestamped entries to today's log.

**Steps:**
1. Get today's date and time.
2. Scan recent file changes in the vault and notable actions from this session.
3. Append timestamped bullet entries to today's log section in `Calendar/Days/<date>.md` (create if missing).
4. Keep entries factual and short.

**Dependencies:** none. **Output:** `Calendar/Days/<date>.md` (log section).
