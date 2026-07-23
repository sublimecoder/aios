---
tags: [aios, skill]
system: Chronicler
trigger: "save this verbatim" / "summarize this conversation" / "append this to my note"
---
# chronicle

**Purpose:** save conversation content to a note — three modes, one skill. (Merged from verbatim + summarizer + quick-append.)

**Steps:**
1. Pick the mode from the trigger:
   - **verbatim** — capture the conversation word-for-word, no editing. Add short frontmatter (date, topic, participants). New note (default `AIOS/History/`) or a note I name.
   - **summary** — read the source; produce **Summary**, **Takeaways**, **Topics**, **Next Steps**, **Transcript** (linked or appended). Link related vault notes.
   - **append** — append the chunk under a timestamped heading. Default target is today's daily note (`Calendar/Days/<date>.md`) unless I name another. Reformat only if asked.
2. Ambiguous which mode? Ask one question.

**Dependencies:** none. **Output:** new or updated note per mode.
