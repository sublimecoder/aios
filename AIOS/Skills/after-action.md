---
tags: [aios, skill]
system: Janitor
trigger: "after action" (Mode A, automatic in every [[aios-ingest]]) / "work the register" (Mode B, standalone)
---
# after-action

**Purpose:** an ingest compounds *facts*. This compounds *procedure*. After the
knowledge lands, run the after-action review — what was supposed to happen, what
happened, what changes — so a correction you made once becomes a rule the OS
holds forever, instead of a sentence in a project note nobody reads again.

The evidence is already shaped for it: every `feedback-*.md` in the memory mirror
carries a **Why** and a **How to apply**. Those are skill inputs that currently
stop at the project note.

**Two modes, and they are deliberately separate.** *Capture* runs inside every
ingest and is bounded by that run's evidence. *Application* is a standalone pass
over the standing register, and it does **not** run inside an ingest. Same
detect-then-act split as [[km-rotate]], [[log-rollup]] and [[open-flags]].

> **⚠️ (2026-09-10) CORRECTION — the sentence this paragraph used to carry was FALSE, and
> it is the sentence that made the problem look already-solved.** It read: *"those three
> each started draining the moment `aios-check.sh` grew a detection line for them, and this
> register got the detection line **without** the act half."* **Measured against the Log,
> none of the three drains.** `km-rotate` has run **twice, both on 2026-08-06** and not once
> since — while `aios-check` has been reporting five [[Knowledge Map]] lines at 1480–1496
> bytes and [[aios-ingest]] declined line 40 on four consecutive runs for want of space.
> `log-rollup`: **two runs.** `open-flags` Mode B: `AIOS/History/audits/flag-register.md`
> holds **two rows and had not been written since the vault's initial commit**, against 216
> flags aged 30d+. **The real difference was never detection — it was an invocation path.**
> All four skills had a detector; only this one had a `.claude/commands/` wrapper, because
> Mode B got one the day someone noticed it wasn't draining, and the diagnosis stopped at
> this file instead of generalizing. Wrappers were added for all four on 2026-09-10.
> *Kept as a correction rather than a rewrite because the false sentence is the mechanism:
> a plausible causal story about a sibling system, written from one system's own evidence,
> is how four dormant skills stayed invisible for five weeks.*

**Detection alone is a ratchet nobody pulls — and a detector with no invocation path is not
even a ratchet.** The register absorbs volume precisely because capture is cheap and
application is not; that asymmetry is real, and it is not unique to this file.

**Why Mode B exists at all (measured 2026-08-07).** Detection here is autonomous:
57 rows on 8 of the 9 days from 07-30 to 08-07, and the pass reliably catches its
own defects. Application has **never once run without a human asking**. `applied`
sat frozen at 14 from 08-04 through 08-07 — four days, zero closures — while `open`
climbed 13 → 35; the day it moved to 49 it moved in a single session, because you
asked. Two things the numbers settle. **Recurrence is a symptom of non-application,
not of bad fixes**: every repeat-instance row recurred while its own fix sat `open`,
and zero applied fixes were later re-broken. And **the missing piece is a trigger**,
which is what this mode is.

## Mode A — capture (inside every [[aios-ingest]], final step)

1. **Collect this ingest's evidence.** Three sources, this run only:
   - `feedback-*` files under `+/_sessions/.memory/<layer>/<project>/` that the
     digests' `memory:` lines named as changed;
   - correction language in the ingested digests and the drafted Log lines —
     `overrul`, `corrected`, `CORRECTION`, `instead`, `preference set`;
   - flags [[open-flags]] escalated this run whose cause is a missing procedure
     rather than a missing fact.
   *Done when:* every item in all three sources appears in step 2 or step 3.

2. **Mechanical drift — verify, then fix.** Run the command that settles all of
   these at once, then fix what it names:

   ```sh
   sh AIOS/Systems/aios-check.sh --verbose
   ```

   It reports, and exits non-zero on: a path named in a skill/system/agent that
   `test -e` says is gone; a `[[wikilink]]` in `AIOS/Skills/` or `AIOS/Systems/`
   resolving to no note; a skill file missing from [[Skill Map]]; a portable skill
   missing from `~/.claude/skills/` (fix with `sh skills/link-global.sh`, never a
   hand-made link); plus the thresholds that trigger the other janitor skills —
   oversized [[Knowledge Map]] lines ([[km-rotate]]), [[Log]] entries past their
   month ([[log-rollup]]), untouched flags and the flag register ([[open-flags]]),
   and the mechanical half of [[wiki-lint]]. Don't re-derive any of it by hand.
   *Done when:* `sh AIOS/Systems/aios-check.sh` exits 0, or every remaining line is
   a judgment call queued as a step-3 row.

3. **Fitness findings — open the target, then write the row.** For every remaining
   item, give one verdict: **project fact** (the knowledge layer already holds it —
   stop, no row) or **procedure change** (name the target file).

   **Read the target file before the row exists, and confirm the layer matches.**
   A `feedback-*` file describes a gap in the *repo* it came from; whether the
   *vault* skill has that gap is a separate fact, and the only way to know it is to
   open the skill and look — check the thing itself, never a proxy for it. On the
   founding run all three judgment rows were written from the mirror alone: two were
   already carried in the target (one in three places), and one named a skill from
   one scope for another scope's rule — a wall crossing that only the read caught.
   A row whose target you have not opened is a guess with a table around it.

   A procedure change gets one row in `AIOS/History/audits/after-action.md`:

   `| YYYY-MM-DD | <layer>/<project> | <source file:line or digest> | <observation, one line> | <target file> | <proposed change, one line> | open |`

   **A new rule governing PUBLISHED artifacts queues its own backward sweep, in the
   same pass.** A rule recorded as a gate is silently scoped to what comes next, and
   the backlog it implies is invisible because no flag was ever written for it. The
   employer-name-vs-internals line was recorded 2026-07-26 and gated every post after;
   three consecutive ingests escalated the one flagged post and not one asked what the
   new rule implied about what was already live — the higher-exposure artifact turned
   out to be a post published three weeks *earlier*, which nobody had flagged. **The
   rule's own effective date is the sweep's scope.** A forward gate with no backward
   sweep leaves the worst instance unexamined by construction.

   Row-worthy patterns, in the order they pay off:
   - a `feedback-*` rule whose How-to-apply belongs inside a named skill;
   - the same manual step performed in two or more ingests (the OS is training a workaround — the friction log's most valuable class);
   - an overrule of a plan the OS wrote (the plan came from a procedure; name it);
   - a gap no skill covers at all — propose the skill, and hand it to [[skill-builder]].

   Keep each row to its two one-line cells. The fix is a design decision made
   later; the row is the evidence, and it stops being recoverable the moment the
   friction stops being felt.
   *Done when:* every step-1 item is a row or an explicit project-fact verdict.

4. **Sweep the standing register.** Rows older than 30 days still `open`: append one
   dated line to [[Log]] proposing apply-or-decline. A row leaves `open` only by
   becoming `applied` (with the commit) or `declined` (with the reason) — rows are
   never deleted.

5. **Report** inside the ingest report: mechanical fixes applied, new rows queued,
   rows escalated.

## Mode B — apply-or-decline (standalone; trigger "work the register" / `/after-action-apply`)

**Never runs inside an ingest.** An ingest already carries a leak gate, a lint and
Mode A; bolting an apply pass onto it would let an unattended run rewrite the OS's
own procedure in the same commit that records the day's facts, with nobody reading
either. The register absorbs the volume; this mode drains it on purpose.

1. **Take the oldest N still-`open` rows, N defaulting to 5.** Oldest first because
   a row's value decays — it is evidence of friction that "stops being recoverable
   the moment the friction stops being felt" (Mode A step 3). Bounded because a
   single pass that rewrote forty procedure files would be indistinguishable from a
   bad one, and nothing downstream would catch it.

   ```sh
   grep -n '| open |' AIOS/History/audits/after-action.md
   ```

2. **Fan out `register-worker`, one agent per row, one row per context.** The
   expensive part of this pass is not deciding — it is *reading*, because a row is
   only trustworthy once its Target file has been opened, and each row names a
   different file. Same shape as `ingest-worker`. The worker is read-only and returns
   `APPLY` / `DECLINE` / `SUPERSEDED` / `ESCALATE` with the literal old and new text.
   **A verdict whose `READ:` heading is empty is a failed worker** — that is the
   founding run's own defect (three rows written from a proxy, two of them wrong)
   reproduced by an agent instead of a human. Re-dispatch it.

   **Brief every worker on what has changed in its Target since the row was written,
   and name any row EARLIER IN THIS SAME PASS that touches the same file.** A row
   describes a file as it stood on the row's date; rows here are routinely filed days
   apart against a file that keeps moving, and a batch pass moves it again mid-pass.
   Without the brief a worker reads its row as a description of the present, and the
   failure is silent in both directions — it re-proposes a change already applied, or
   it proposes one that contradicts what the same pass landed an hour earlier.
   - **This is not hypothetical; it is why the rule exists.** On 2026-08-16 row 81 was
     applied in the morning, ruling that a queue block with no `BLOCK` row "is not a
     skip" and sending the run to read its `memory:` line. Rows 111 and 117 — two more
     symptoms of the same one-line cause, filed on two later days — were dispatched
     that afternoon *with that edit named in the brief*. Row 111's worker came back
     with the contradiction: a bare-`HEAD` marker is also a block with no `BLOCK` row,
     it has no `memory:` line, and it **should** be skipped, so the morning's text
     would have sent a run hunting a line that does not exist. Same input, opposite
     correct answers, and the discriminator (the block's *body*) was in neither row.
     A worker briefed only on its own row had no way to see it.
   - **A class of rows is the dangerous shape**, because the sibling rows look like
     duplicates and the tempting move — apply one, decline the rest — is exactly what
     leaves the contradiction in place. Applying one row of a multi-symptom class can
     make a sibling's case *actively wrong*; only reading the sibling against the NEW
     text finds it.

3. **Apply, on confirmation, in the orchestrator.** Workers never write. Present the
   batch — one line per row, verdict and target — and apply only what you confirm.
   This is [[skill-builder]]'s job, and this mode is its caller; the standing rule
   that judgment waits for a human is not suspended by a batch being convenient.
   - `ESCALATE` verdicts and anything touching `.claude/hooks/`,
     `vault-write-guard.sh` or `rules-lib.sh` are **never** applied here. They are
     security-relevant and carry their own regression gate and checksum stamp.
   - A `WALL` verdict on the layer line is an automatic decline, whatever the rule's
     merit. The correct home goes in the reason.

4. **Write the Status cell — every row in the batch, including the declines.** A row
   leaves `open` only as `applied` (with the commit sha) or `declined` (with the
   reason). Rows are never deleted, and a row silently left `open` after a pass
   examined it is worse than one never examined: the next pass pays the reading cost
   again and reaches the same verdict.

5. **One [[Log]] line per pass, never one per row.** Rows applied / declined /
   escalated, plus the register's new open count. This is the same ruling
   [[open-flags]] Mode B makes and for the same reason: a nag channel and a decision
   record cannot be the same file, and `Log.md` is the one [[log-rollup]] exists to
   keep lean.

### `--draft` (unattended)

The weekly launchd pass runs `--draft`, which does steps 1, 2 and 4-as-annotation
**only**: it writes each worker's verdict and proposed change into the row's
*Proposed change* cell, leaves `Status` at `open`, and writes one Log line. It edits
no skill, no system and no agent file.

This is the whole point of the split. The expensive half of the pass — opening every
target and reaching a defensible verdict — is exactly the half that is safe to run
unattended, and the cheap half — saying yes — is the half that needs a human. A
scheduled job that applied its own verdicts would violate this skill's own standing
constraint on the run where nobody is watching, which is the only run where the
constraint matters.

## Constraints

- **Mechanical fixes apply themselves; judgment waits for you.** Mode A step 2
  edits files. Mode A step 3 only writes register rows. Mode B applies only what
  you confirm, and under `--draft` applies nothing at all. This holds on the
  unattended scheduled run, where nobody is watching.
- Proposals name a target file and a change; writing the change is [[skill-builder]]'s
  job on confirmation — Mode B step 3 is its caller, not an exception to it.
- One layer at a time, like the ingest that calls it. `.claude/agents/*.md` are valid
  step-2 and step-3 *targets* — this skill judges fitness, so the agent-schema
  exclusion in [[skills-janitor]] does not apply here.

**Dependencies:** [[aios-ingest]] (calls Mode A last), the memory mirror under
`+/_sessions/.memory/`, [[open-flags]], [[skill-builder]] (writes confirmed changes),
[[skills-janitor]] (form audits — this one is fitness), `register-worker` (Mode B's
per-row reader), `AIOS/Systems/aios-check.sh` (reports the open count that triggers
Mode B), [[Skill Map]], [[Log]].
**Output:** rows in `AIOS/History/audits/after-action.md`, any Mode A step-2 fixes
applied in the ingest commit, Mode B's applied changes and Status cells, one Log
line per Mode B pass, escalation lines in [[Log]].
