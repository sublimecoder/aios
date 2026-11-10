---
tags: [aios, audit, register]
system: Janitor
related: ["[[open-flags]]", "[[aios-ingest]]"]
updated: 1970-01-01
---
# Flag register

> Standing register of ⚠️/OPEN markers that have aged past 30 days, appended by
> [[open-flags]] **Mode B** — the standalone sweep, never by an ingest. Ingests
> disposition flags on the project they touch (Mode A) and escalate nothing.
>
> This file exists so escalation volume never reaches [[Log]]. One Log line per
> flag per run would refill, inside unattended runs, the file [[log-rollup]]
> exists to keep lean. A nag channel and a decision record cannot be the same file.
>
> A row leaves `open` only as `resolved` (the flag became a settled fact in its
> note, with the commit) or `declined` (the flag stays, with the reason it is
> acceptable standing state). Rows are never deleted.
>
> **`Date source` is `stamp` or `blame`.** `stamp` — the flag carried an inline
> `⚠️ (YYYY-MM-DD)` birth date; that date is the age, no fallback needed. `blame` —
> no stamp existed, so age came from `git blame` on the flag's own line, and that
> is a **lower bound**: an ingest that rewrites a shard in place resets blame on
> its lines (`source-history.md` is rewritten every run, so its flags read as
> permanently fresh). Where blame is untrustworthy, first-seen falls back to
> [[Log]] or the note's Source section, and "unknown" is an honest last resort.

| First swept | Scope/project | Note | Flag (trimmed) | Age at sweep | Date source | Proposal | Status |
|---|---|---|---|---|---|---|---|

_No rows yet — the first sweep is due once flags begin crossing 30 days.
`AIOS/Systems/aios-check.sh` reports the aging count._
