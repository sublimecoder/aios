---
tags: [aios, skill]
system: AIOS Wire
trigger: "/aios-ingest"
---

Compound the queued session digests into the wiki. **Run only in the vault.**

## Preconditions
- cwd is the vault root (has `AIOS/` + `CLAUDE.md`).
- There are non-empty files under `+/_sessions/<layer>/<project>.md` — **counted now,
  in step 0, not remembered.** The SessionStart banner is a session-start snapshot and
  the scheduled fires drain the queue underneath it; a run that trusts the banner
  reports draining more than it drained.

## Inputs (two kinds)
- **Digests** — `+/_sessions/<layer>/<project>.md`: git signal (branch/commits/diff-stat). Synthesize decision-level meaning.
- **Native memory** — `+/_sessions/.memory/<layer>/<project>/*.md`: the repo's Claude Code memory itself, not a copy — since 2026-09-14 every machine's `autoMemoryDirectory` points here (`aios-install.sh`), so Claude Code writes these files directly and git carries them between machines. The Stop hook commits them and absorbs any leftover machine-local memory dir without deleting anything. These are **already durable prose facts** — merge them, don't infer. A digest's `memory: <files>` line names which mirror files changed that session. The mirror is living state, NOT a consumable queue: **never archive, edit, or delete it** (the Stop hook owns it; touching it just re-triggers on the next session).
  - **`memory-source:` means the mirror was NEVER OFFERED, not that it was empty.** The mirror is fed by Claude Code's native memory store; a jcode session has no such store, so the digest hook writes `memory-source: jcode session — …` on those blocks. Without that line the two cases are identical on the page: a Claude session that recorded nothing durable, and a session whose durable half does not exist in this system at all. Treat a `memory-source:` block as **git signal only** — synthesize from the commits and diffstat as usual, and do NOT read the absent mirror as evidence that the session produced no durable facts. It is missing input, not a negative finding.
  - **"Merge, don't infer" covers the mirror's FACT. It does NOT cover ship state.** A mirror is written *at authoring time, from inside the working session*, so its present tense means "true on this branch", not "true on main" — and a repo session writes it while the branch is still open. **Any mirror claim about merge state gets the same forge check a digest block's `commits:` line gets — in EITHER direction**, and is recorded as ⚠️ (YYYY-MM-DD) BRANCH STATE until the forge says otherwise. **The answer takes the same three-way mapping as step 1b-ship — and "otherwise" means LANDED or OPEN, not merely that an answer came back:** `LANDED <evidence>` → record it as fact and resolve any open `⚠️ BRANCH STATE` for that branch with the evidence; `OPEN` → note the in-flight state and write no flag (a confirmed OPEN is a known state, not an unknown one); `UNKNOWN` → the ⚠️ (YYYY-MM-DD) BRANCH STATE stamp stands. Step 1b-ship fires once per `branch:` this run's queue named, and a mirror is not a block — a PR a mirror names and no digest block carries reaches that mapping only through this line. On 2026-08-10 a mirror named two PRs in the present tense, the forge answered OPEN for both, and the mapping had to be borrowed by analogy mid-run. **Held / blocked / not-yet-merged is not the safe direction.** A claim that something is *unshipped* reads as conservative, so it gets recorded verbatim while only live-claims get checked — and it is exactly as perishable, failing the more damaging way: the wiki records as held work that already landed, and no flag is written because nothing looked uncertain. Re-derive every merge-state claim against `origin/<default-branch>` whichever way it points — unlike the PATH check below, which reads the working tree. One mirror's `Held:` list named two changes already on the default branch when it was read, and four more landed before the ingest ran. The entire ship-state discipline — ask the forge, squash-merge one-directionality, a merge commit resolves the parent not the shipped-ness — lives in *Reading a digest block* below, and a mirror is not a block, which is exactly how it slipped: two features would have been recorded as shipped in one run had the forge not been asked, and nothing in the queue or the mirror distinguished them from merged work.
  - **It does not cover the mirror's PATHS either.** A mirror asserts concrete repo paths, plugin names, script names and config keys, and every one of those is `test -e`-checkable in seconds against a repo the ingest can already resolve — `AIOS/Systems/resolve-project.sh` (`REPO_PATH=`), the same wire step 1b-ship uses. **Check each one against the repo working tree before it enters a note** — the working tree, not the default branch: a mirror is authored mid-branch, so a genuinely new file is absent from `main` and present here. **That rationale holds only while the checkout is AHEAD of or level with origin, and a mirror authored ON the default branch against a stale checkout inverts it:** the working tree is then an *older* snapshot, not a newer one, so a path "verified" against it can be verified against code the team has already replaced. **When the queue's newest `HEAD:` is BEHIND `origin/<default-branch>`, the working tree alone is not sufficient** — that is the same `git fetch` + `origin/<default-branch>` comparison *The queue is not a complete record of the repo* below already requires, so run it here if it has not run yet — then `git diff --stat <HEAD>..origin/<default-branch>` over the cited files, and verify against origin any that moved. Both conditions stand together: new-and-unpushed still argues for the working tree, stale-and-behind argues for origin, and only the comparison says which you are in. On 2026-08-17 a memory-only block sat on the default branch at a sha pulled less than a day earlier and already 13 commits behind origin, and every `path:line` its mirror cited was checked against that tree; the diff happened to be empty over those files, which is luck, not verification. A forge-driven checkout is behind by construction (see the forge-merge corollary below), so this is the common case, not the corner. A path that does not resolve is recorded as `⚠️ (YYYY-MM-DD) UNVERIFIED PATH — <the path as the mirror wrote it>`, never as fact. **A wrong path is worse than a missing one:** it reads as verified *because* it is specific, and it sends the next reader looking for a file that is not there. The 2026-08-05 mirror named a config plugin `mobile/plugins/withIosDeploymentTargetFloor.js`; it was merged verbatim into the project note and no file has ever carried that name. It survived three days and two ingests, and was caught only because a later run happened to open that directory for an unrelated reason. **A mirror does not cite files, it cites `path:line`, and `test -e` never reads the line half.** Where a citation carries an offset, resolve the SYMBOL at it — `grep -n` the function, const, route or message the claim names — not just the file. Two shapes recur, both `test -e`-clean: a declaration whose cited line is the closing `*/` of its own doc comment, and a message whose cited line is the `// Invariant` comment above it. **The offset is the half an implementer copies**, so a corrected one enters the note with the correction visible — `path:<verified>` plus what the mirror wrote — never silently, since the mirror is never edited and will re-offer the wrong offset on the next run; an offset whose symbol is nowhere in the file is recorded as `⚠️ (YYYY-MM-DD) UNVERIFIED LINE — <the citation as the mirror wrote it>`, kept separate from the file's existence, which is not evidence for it. On 2026-08-17 three offsets in one mirror were wrong this way while a checked neighbour resolved exactly — the same matching-endpoint effect the NUMBERS bullet below names, one level finer.
  - **It does not cover the mirror's NUMBERS, and those fail the same way the paths do.** A mirror asserts line counts, file counts, test totals and before/after ratios, and a headline ratio is exactly the figure a session measures **mid-flight** — when the running total is the only total it has — and then reports as the whole. **Re-derive BOTH endpoints before the figure enters a note, and key each one to a named sha** (`git show <sha>:<path> | wc -l` for a size, `git diff --stat <base>..<head>` for a delta). **Unlike the PATH check above, the working tree is not the reference here** — a path either exists or does not, but a number is only true at a commit, and the tree moves under it: in the 2026-08-16 case the *after* figures were already a few lines off when the same two files were re-read the next day. An endpoint that cannot be reproduced is recorded as `⚠️ (YYYY-MM-DD) UNVERIFIED FIGURE — <the figure as the mirror wrote it>`, never as fact; a corrected one is recorded **with the correction visible**, because the ratio is the part that travels and a silently fixed number cannot be told from an unchecked one. **A matching endpoint is what makes the other one invisible:** on 2026-08-16 a refactor mirror's before-figures were real, specific numbers anchored two waves into the sequence rather than at its start, while its after-figures matched the repo exactly — so the pair read as verified, and the mirror understated its own result. **The correction lives in the note, never in the mirror,** which is never edited: the same wrong figure will be re-offered on the next run, so write it where the fourth dedupe width's re-read will hit it.
  - **A mirror whose subject is AIOS/vault tooling is layer-neutral — route it to the AIOS layer, never drop it.** The mirror is the one input whose layer the ingest does not choose: it inherits whichever repo the session ran in, so a lesson about the vault's own hooks, skills or scripts arrives through `work/` or `creator/`. None of the write targets in *Rules* is a legal home for it — filing it in `<scope>/projects/` puts OS-tooling content in a project shard that is not about the OS. Record it as **a dated [[Log]] line plus a row in `AIOS/History/audits/after-action.md` scoped `AIOS`**, naming the vault artifact it bears on, and cite the mechanism, never the incident: the mirror was authored inside a layer session, so strip its layer-specific identifiers on the way out. **Logging it in step 1g as "deliberately NOT recorded" is not the answer** — a fact with no destination is silently dropped by a step that looks like it succeeded; the provenance instead names the AIOS-layer row it was routed to. In one run, two of six reconciled mirrors were vault-infra facts and both were dropped this way; one of them was the digest hook committing to whatever branch is checked out — a live corruption hazard for the ingest's own queue.

## Rules
- **Every flag authored from now on carries its own birth date inline: `⚠️ (YYYY-MM-DD) <claim>`.** Date from local `date +%F`, never from a digest's UTC stamp. Flag age is otherwise computed from `git blame`, which an in-place shard rewrite silently resets — the stamp is the only anchor that survives one. Do **not** retro-stamp existing flags: a bulk rewrite resets blame on every line it touches, which destroys the very signal this convention exists to preserve. Legacy unstamped flags age out on blame and decay naturally. `+/_sessions/.memory/` is never edited by the vault, so a mirror flag acquires its stamp when it is merged in step 1b — making that a merge date, not an authoring date.
- **One scope at a time.** Process every queue file in one scope, then the next,
  etc. Never synthesize across layers in a single note — the identity wall.
- **Digests are signal, not prose.** Each block is branch + commits + diff-stat.
  Synthesize the *decision-level* meaning (the breadcrumb), not raw diffs. If a
  digest implies nothing durable, skip it — do not invent.

### Reading a digest block

A block is `git log` and `git diff --stat` output, not a history. Every line below
is a wrong reading that already reached a note; none of them is recoverable by
reading the block harder, because the block does not carry the missing fact.

- **`commits:` means "reachable since the last digest", not "authored on this branch".**
  The hook walks `git log $LAST..HEAD`, so a branch that merged the default branch
  lists everything it absorbed. Attribute by checking which entries are already on
  the default branch; the rest are the branch's own.
  **The same walk means the block's timestamp dates the WALK, never the payload.** When a
  pull absorbs a backlog — the closing move of the forge-caused gap below — the whole
  backlog arrives as ONE block under one `HEAD:` and one stamp, and that stamp is the
  **pull**. A commit count far larger than the block's session span implies is the tell: on
  2026-08-17 one block carried 46 commits under a single 00:31Z stamp for work spanning
  2026-08-11..16. **Take each synthesized fact's date from its own commit** —
  `git log -1 --format=%cI <sha>`, converted to local — never from the block header, and
  say in step 1g's provenance that the block's stamp is a pull date. **This is not an
  exception to *Dates* below:** that rule settles the RUN's own dates (`updated:`, the
  archive suffix, the Log line), and its "content keeps the date of the work it describes
  (the queue's own day)" gloss holds only while the queue's day IS the work's day — which
  is precisely what a pull block breaks.
- **A merge commit resolves a branch's PARENT, not its shipped-ness.** In a stacked
  epic "merged" can mean one rung up a ladder whose bottom rung is unshipped. Check
  ancestry against the **default** branch before closing any branch-state marker, and
  record the merge target when it isn't the default branch.
- **Merged-ness: a `yes` proves merged, a `no` proves nothing.** This repo squash-merges
  by default, so a branch's commits never become ancestors — `git branch --contains`
  and `merge-base --is-ancestor` return false for work that demonstrably shipped. But
  merge style is per-PR (some bot PRs land as true merge commits), so the test is
  one-directional. Ask the forge, or match the squash commit's subject on the default
  branch. Never build a merged-ness sweep on a `no`. **`AIOS/Systems/ship-state.sh` is
  this discipline, pinned once** (forge first, subject-match fallback, ancestry
  confirms-only) — step 1b-ship below runs it; don't re-derive the query order by hand
  here.
- **Ship state scopes the FACT, not just the branch marker.** A commit body is an
  assertion about its branch at that instant, and the next commit on that same branch can
  reverse it — merged-ness discipline answers *did this land*, never *is this still true*.
  So when `ship-state.sh` (step 1b-ship) answers `OPEN` or `UNKNOWN` for a branch, every
  *fix* or *decision* synthesized from its commits is written branch-scoped: name the
  branch and the originating sha in the bullet itself, so a later reader can tell it from
  a fact about the default branch. **This is not the `⚠️ BRANCH STATE` flag** — 1b-ship
  writes that on `UNKNOWN` only and never on a confirmed `OPEN`; this is provenance inside
  the claim's own sentence, and it is owed on `OPEN` precisely because a confirmed-open
  branch is the one still free to retract itself. **A later queue naming the same
  still-open branch re-reads the bullets the prior run wrote from it before appending** —
  a review train's own corrections are exactly the class that arrives late, and the note is
  the only ledger holding them, since the archive indexes shas and not claims. When one is
  retracted, keep the superseded bullet, mark it superseded, and let the standing rule it
  teaches survive its dead gate expression. On 2026-08-14 a 12:00 ingest read a mid-branch
  commit body announcing a tightened authorization gate and recorded it as a closed review
  finding; the 16:00 queue on the same branch showed that gate was itself the bug and had
  already been replaced — four hours, one branch, one fact reversed.
- **A claim about what will be done NEXT, or about what was deliberately NOT done, is a
  dated proposal — never a standing fact.** Merge state has `ship-state.sh` and enabled
  state has a runtime to interrogate; intent has no oracle at all, and it decays faster
  than either, because the session that writes it is usually the one that then acts. So a
  synthesized claim of the form *named next lanes / planned follow-up / flagged-not-deleted
  / deliberately deferred* carries its own `as of (YYYY-MM-DD)` and never the bare present
  tense, which is the only thing making it read as standing. **This stamp is not a `⚠️`
  flag** — nothing is unverified, the claim was true when written — so it must not be
  spelled as one, or the register count and the 30-day aging report absorb every routine
  plan. **And the re-read obligation is PROJECT-scoped, not branch-scoped:** the
  still-open-branch clause above fires only where `ship-state.sh` answered `OPEN`/`UNKNOWN`
  for a named branch, while an intent claim decays with no branch involved at all — so the
  next run naming the same *project* re-reads the prior run's intent bullets before
  appending and settles every one this queue's commits can settle, the way a retraction is
  settled: keep the stale bullet, mark it superseded with the date, keep its shape. On
  2026-08-16 one 16:00 run produced two in a single pass, one per layer — a "pre-existing,
  so flagged not deleted" bullet whose CSS was deleted in that same pass, and a four-item
  "next lanes" list of which three closed that evening. Both were correct when written and
  false within hours; both had to be retracted by hand by the next run, which then wrote a
  fresh unstamped one of its own in the section immediately below.
- **A commit that adds a CAPABILITY proves the code EXISTS, never that the capability is
  LIVE.** Merged-ness has `ship-state.sh`; enabled-ness has nothing, and today both get
  recorded in the same sentence. A CI job, a workflow, a scheduled task, a hook or a
  flag-gated feature is inert until the runtime that would execute it is switched on, and
  the source is self-confirming evidence: the config says what it will do and is silent
  about whether it does it. So before closing or narrowing a standing flag on such a
  commit, check the runtime itself — `gh workflow list` / `gh run list` for Actions, the
  flag's default, the harness's own hook table for a hook, and — the simplest case, the
  one under all the others — whether the commit was ever PUSHED
  (`git rev-list origin/<default-branch>..HEAD`): an unpushed commit's runtime never
  receives the code at all, and where the deploy trigger IS the push, that is the entire
  difference between merged-looking and live. Record enabled-state
  **separately** from merged-state. **This does not soften `LANDED`** (step 1b-ship): the
  merge is still fact; liveness is a second fact the merge does not carry, and only the
  second one retires a "this path is dead" flag. On 2026-08-15 a block added a real deploy
  job to a workflow file, verified present on `origin/<default-branch>` and triggered
  `on: push`, and read as capability delivered — while the workflow itself was
  `disabled_manually` at the forge, last run two months earlier and every run before it
  skipped or failed. The shard's standing dead-deploy bullet was right; the block looked
  exactly like the evidence that retired it. The vault has been bitten by the same shape
  from the other side — a hook wired in a config its harness never reads.
- **`uncommitted:` is `git diff --stat`, so it lists TRACKED files only.** A brand-new
  file is invisible in it. When a block's edits all look like *adoption* of something
  (new import, call sites swapped to a helper), the helper is a new file the stat
  cannot show — read the working tree.
- **Only the LAST block is a claim about now.** Every earlier block is history; the tip
  block's stat was a snapshot at hook-fire time and is the one most likely to be stale.
  Read the live working tree for it rather than trusting its stat.
- **The queue is not a complete record of the repo.** A hook that failed, or a session
  in a checkout the manifest doesn't resolve, leaves no trace at all — the queue still
  looks healthy. For a git-backed project, `git fetch` first, then compare the queue's
  newest HEAD against `origin/<default-branch>` — **never the local branch** — and
  ingest (or flag) the gap **before** archiving; flagging here means writing
  `⚠️ (YYYY-MM-DD) <the gap>`.
  **The comparison runs both ways and the two directions mean opposite things.** Origin
  ahead of the queue's newest `HEAD:` is a COVERAGE gap — work the queue never saw, which
  is what gets ingested or flagged. Queue `HEAD:` ahead of `origin/<default-branch>` is
  the inverse: nothing is missing, the commits are **committed locally and never pushed**.
  That is a not-live state, not a coverage flag — record it as fact in the note
  (`<sha> committed, not on origin as of YYYY-MM-DD`), and where a push to the default
  branch IS the deploy, say plainly that the change is not deployed. **"Never the local
  branch" bars the local tip as the REFERENCE, not as the subject** —
  `origin/<default-branch>` is still the thing compared against; here the local tip is
  what is being measured. On 2026-08-16 a queue's newest `HEAD:` sat ahead of
  `origin/<default-branch>` on the default branch itself in a deploy-on-push repo, and a
  run of merged-looking UI commits read as shipped while not one of them was live.
  **A local `main` only moves when someone pulls, so comparing against it is
  self-confirming.** On 2026-08-09 the queue's newest `HEAD:` equalled the local `main`
  exactly and read as "no gap", while `origin/main` was 13 commits ahead and held both
  of that run's payload commits. Queue HEAD == local tip is not evidence of coverage;
  it is the expected reading of a stale clone.
  **Forge-merge corollary: repeated blocks at one identical `HEAD:` across a long
  session is itself the signal to run this check, not a quiet queue.** A merge train
  run server-side (`gh pr merge --squash --admin`) never advances the local checkout,
  and the digest hook reads `git log`, so that session is invisible to it by
  construction — the queue fills with blocks frozen at one sha while the remote moves
  well ahead.
  **A forge-caused gap does not self-heal, so it is dispositioned on the run that finds
  it.** The local checkout advances only on an explicit pull, and a session working
  entirely through the forge never has a reason to perform one — so the gap is
  **monotonic**: it grows by every commit the team lands and shrinks only when a human
  happens to pull for unrelated reasons. Ingest it, or defer it explicitly with a dated
  reason; **"expect the next digest to absorb it" is not a disposition**, it is this
  failure mode restated as a remedy, and it reads as handled while going stale.
  **A re-check finding the same `HEAD:` unmoved means the gap WIDENED, never that it is
  unchanged** — re-derive the count against `origin/<default-branch>` and UPDATE the
  prior flag with the new number and the newly-uncovered commits, since
  *confirmed-still-open* (step 1e) understates a gap that has grown, and an unmoved
  `HEAD:` is the one case where a commit-free queue still has something to re-derive
  against. On 2026-08-16 a gap flagged at 27 commits with "expect the next digest to
  absorb the tail once someone pulls" stood at 44 eight hours later at the same unmoved
  sha, fifteen of them covered by nothing; it closed only when someone pulled for
  unrelated reasons, three fires late.
  **A ✅ on a queue-completeness flag names what changed in the WIRE, or it is a reset
  and not a repair.** The closing move is a human pulling for unrelated reasons, and that
  changes nothing about why the gap forms — so unless the disposition names a change in
  the digest hook, the checkout, or the pull discipline, record the close as *reset, not
  repaired*, and the next run naming that project **re-derives the count against
  `origin/<default-branch>` instead of inheriting the ✅ as settled.** Nothing else will:
  a resolved flag leaves step 1e's sweep, which dispositions open flags only. **Same decay
  as the intent-proposal bullet above — a closure is a claim about the future — but a
  closure is none of that bullet's four forms, so nothing there fires on it.** On
  2026-08-17 a 44-commit gap closed at 08:00 on exactly such a pull, and by 16:00 the same
  now-unmoved `HEAD:` was 13 behind again with twelve covered by nothing: the counter had
  restarted from zero inside one working day.

- **Dedupe, in three widths.** Collapse byte-identical blocks (the hook dedupes at
  write time; this is defense in depth). Then collapse by *shape*: successive
  `uncommitted:` blocks on one branch whose file sets nest are **one in-flight change**,
  not three events — synthesize once and record it as working-tree state, not as
  shipped. Then collapse past the queue boundary: drop commits already present in
  `AIOS/History/_ingested/<layer>/` before synthesizing. **The archive is the dedupe
  ledger, not just evidence storage** — a fresh session on a new branch re-lists every
  commit back to its own marker, so a block whose entire commit list is already archived
  yields no synthesis and is recorded as already-ingested. **This third width is scripted,
  not hand-grepped:** `sh AIOS/Systems/archive-ledger.sh dedupe AIOS/History/_ingested/<layer>/*.md
  +/_sessions/<layer>/<project>.md` — **archive glob first, queue file LAST.** The
  script's survivor is always the first-seen occurrence in argument order, so this
  order is what makes "duplicates AIOS/History/_ingested/…" mean "already archived";
  queue-first inverts every direction and the check silently finds nothing, every time.
  Read the `BLOCK` lines, not the raw `DUP` lines: each names one queue block as
  `n/m already-elsewhere` — `n==m` means every commit in that block is already
  archived, skip synthesizing it. **Only commit-bearing blocks get a `BLOCK` line** —
  the script registers a block where it parses a `commits:` entry, so an
  `uncommitted:`-only block emits none while its `HEAD:` sha still pools into the sha
  namespace. The `BLOCK`-line count is therefore a **floor** on the block count and
  never equal to it: reconcile block *counts* with `archive-ledger.sh count`, the way
  steps 0 and 3 already do, and never by counting `BLOCK` lines.
  The script pools `commits:` and `HEAD:` shas in one
  namespace and prefix-collapses variable abbrev lengths without false transitivity —
  do not re-derive any of that by hand per digest.
- **Sources stay immutable.** Write only to `<layer>/projects/`, `AIOS/History/Log.md`,
  and `Knowledge Map`. Never edit `<layer>/sources/` or create new notes in `<layer>/notes/` / `life/`.
- **Every note write goes through `Edit`/`Write` — never a shell redirect, heredoc,
  `tee`, or a script handed the note path as an argument.** The content rules (Rule C
  cross-layer leak, Rule D work identifiers) live in `vault-write-guard.sh` as a
  PreToolUse hook that greps the tool's *content*, and a Bash command has no content
  until it runs — so on a shell write those rules cannot fire at all. Rule F refuses the
  ordinary `>> <guarded path>` spellings, but it is a redirection aid, not a boundary:
  a `cd` inside the command, a variable-built path or a committed script slips past it,
  and then the only coverage is an after-the-fact observer, which speaks *after* the bytes
  are on disk and cannot revert them. On 2026-08-09 a heredoc append put ~7 shard
  bullets into a work-layer note ungated, while the same run's `Edit` on another note in
  the same project was correctly BLOCKED for a bare PR number — same run, same layer,
  same rule, and only the tool choice differed. (Step 3's archive `mv` and step 6's git
  commands are not note writes and are unaffected.)
- **Dates:** **On a run that crosses local midnight `date +%F` has two answers and the
  run needs both: content keeps the date of the work it describes (the queue's own day),
  while metadata written after the roll — `updated:`, step 3's `<date>-<HHMM>` archive
  suffix, the Log line, step 1g's provenance heading — takes the new date.** Flags are
  settled by the first bullet and are not an exception to re-derive here: the stamp is
  taken when the flag is authored and is never retro-stamped, so a flag written at 23:40
  keeps the old date. Otherwise, all vault dates derive from local `date +%F`, never from digest UTC
  stamps (past ~17:00 PT they disagree).
- **Work-layer identifiers:** bare `EC-####` ticket IDs only. No raw PR or issue
  numbers (`PR #1814`, bare `#1814`) — the archived digest keeps those, the wiki note
  does not. `vault-write-guard.sh` enforces this on write, so an ingest that doesn't
  know the rule learns it by getting blocked mid-write; it is stated here so that
  stops happening. Customer, counterparty and colleague names ARE permitted in the
  work layer (settled 2026-08-07) — see the hub note's sanitization clause.
- **Dedupe:** see *Reading a digest block* above — three widths, not one.
- **Folding a peer vault (`~/code/ec-aios`) — the contract pass runs BEFORE the fold
  lands, not after.** The peer stream does not enforce this vault's identifier rule, so
  a fold imports its numbering habit wholesale, and because it lands as one large diff
  the per-write guard sees a bulk move rather than each token. That is how eleven raw PR
  numbers sat unflagged across seven shards for three weeks after the 2026-08-01 fold.
  Normalize the incoming text **in the extractor**, in the same pass that moves it —
  this is the one moment the whole block can be corrected in a single edit, because the
  fold blocks are deliberately kept verbatim and un-deduped afterwards, so a later
  per-line rewrite is a judgment call against that rule. Three more properties of a fold,
  each learned by getting one wrong:
  - **The unit is whatever the streams append.** Both now append one dated `## ` section
    per ingest, so the unit is the H2 section, not the bullet — bullet-level extraction
    severs a section's ⚠️ preamble from the bullets it governs, and a bullet sitting
    directly above a heading swallows the heading and everything under it.
  - **Test for round-trip contamination before anything lands:** grep the inbound set for
    a string you know you sent outbound in an earlier fold. The peer's copy of your own
    prior fold is not new knowledge.
  - **Both directions, same pass.** The two vaults are peers, never source-and-copy — see
    the hub note.
  - **`git fetch` the peer FIRST, and diff against `origin/main`, never the local
    checkout.** This is the step whose absence wasted a whole fold on 2026-08-28: the
    local `~/code/ec-aios` was **97 commits stale**, so the extractor computed "what the
    peer lacks" against a four-week-old snapshot and produced 3,400 lines that the peer's
    own live stream had already ingested independently. It surfaced only at `git push`,
    after the work was done and committed. **A silent local checkout is not a silent
    peer** — the peer's stream was running daily the whole time, wired to a machine that
    is not this one. Before extracting: `git -C <peer> fetch && git -C <peer> rev-list
    --count main..origin/main`. Non-zero means the local tree is not the peer's brain.
  - **Check the DISTILLED layer separately from the raw one.** The same 08-28 run found
    the peer's shards four weeks ahead but its `ec-*` runbooks byte-identical to a
    month-old copy: ingests keep shards current and silently leave the distilled layer
    stale, and the distilled layer is what a session actually reads at start. A fold that
    finds the raw layer redundant may still owe the distilled one everything.

## Steps

0. **Re-count the queue, and reconcile any prior partial run.** Two cheap reads before
   synthesizing anything.
   - **Count the queue now.** The SessionStart banner is a snapshot from session start
     and the scheduled fires (08:00/12:00/16:00) drain it mid-session — never act on a
     remembered number.
   - **Walk back every `aios: partial ingest` commit** newer than the queue's oldest
     block, back to the last clean ingest — plural, not just the most recent; one queue
     has produced two consecutive partial commits. Read their diffs before writing, or
     the same facts get recorded twice. **Re-stamp `updated:` on every note they
     touched:** a dead run leaves the notes it wrote carrying the *previous* run's date,
     so freshness metadata says nothing about whether an ingest finished.
   - **Record the newest block's timestamp and the block COUNT per queue file.** Step 3
     compares against these after the move. Write them down now; neither is recoverable
     afterwards. (Step 3 archives the whole file — there is no partial-archive mechanism
     and this step must not imply one.)
     **The count that BINDS is the one taken when synthesis starts, not at first read.**
     Step 0 is several reads long and the queue fills underneath it — on 2026-08-14 a
     work queue counted 19 blocks and held 20 before step 0's reads finished, block 20
     arriving before any note was written. Re-count immediately before step 1 opens the
     file, make that the baseline, and where it differs from the first read record both
     and name the growth in step 1g's provenance. A first-read baseline is stale by
     construction: it yields the same phantom excess named below, by time rather than by
     anchor, and step 3 then cannot tell a block that shipped **ungated** from one step 1
     had already synthesized — it orders a step-2 re-run for both.
     **Count with the same script step 3 counts with — `sh AIOS/Systems/archive-ledger.sh
     count +/_sessions/<layer>/<project>.md`, its per-file number** — never by hand. Two
     counts from two anchors do not compare: the original spec's anchor carried a
     `— local: ` segment and matched 550 of 1,057 blocks. A mismatched pair yields either
     a phantom excess (a needless step-2 re-run) or, worse, hides a real one — and a real
     one means a block ships **ungated**, which is the single failure step 3 exists to catch.

For each layer with a non-empty queue (**fan step 1 out only at 3+ non-empty project queues in ONE layer; at 1–2, do them inline.** "When the queue is large" was the old wording and named no threshold anywhere, so two-project queues went both ways — and the one that fanned out produced three failures structurally impossible inline: concurrent Knowledge Map/Log writes, an orphaned flag sweep holding a flag already 2 days overdue, and a dated clause appended to a map line. Fan-out parallelises *projects*, not block volume — a worker gets the whole queue file either way — and per-layer project counts are 1–3, so this threshold means fan-out rarely fires. That is the intended outcome, not a side effect. One `ingest-worker` subagent per digest, per [[Orchestrator]]; workers write only their own project note and hand back the KM + Log lines for steps 1c–d. **Steps 1e, 1f and 1g stay with the orchestrator** — workers cover a–b and b-ship only, so the flag sweep, the fan-in guard and the provenance write each have a named owner instead of falling between the two halves. **Re-check this list whenever a lettered step is added**: 1e was orphaned for weeks by exactly this gap, and 1g was added on 2026-08-07 and orphaned the same way within the hour, by the same session that had just fixed 1e; 1b-ship is named here for the same reason, the day it was added. **Sharded projects are never fanned out** — the worker refuses them by contract, because for a sharded project the hub is an index and its "write only your project note" rule points at the wrong file. Today that is exactly one project, the largest and most wall-sensitive; the orchestrator does it directly):
1. For each `<project>.md` in `+/_sessions/<layer>/`:
   a. Read/create `<layer>/projects/<project>.md` (frontmatter `layer:`,
      `project:`; link `[[me-<layer>]]`).
   b. **Read the previous run's provenance entry for this project before synthesizing** —
      the newest `## ` entry in the project's `source-history.md` (or the Source section
      of an unsharded note), and back through any entry newer than this queue's oldest
      block, the way step 0 walks back partial-ingest commits. **If one records a
      queue/repo gap it ingested — a `**⚠️ OUT-OF-BAND`-anchored entry per step 1g, or,
      in entries written before that anchor was required, a bullet naming commits it read
      out of the repo — the ledger is known-blind to exactly those shas.** They entered
      no archive, so `archive-ledger.sh` reports them `0/n already-elsewhere` and all
      three dedupe widths pass them through as new. Dedupe those blocks by SUBJECT and
      ticket id against the shards instead, before synthesizing them. **The warning alone
      is not the fix:** on 2026-08-09 the entry named its four out-of-band shas exactly as
      step 1g now requires, and the next run still drafted three duplicate shard entries —
      caught only because the shards were already open for another reason. 1g writes that
      record; until now nothing read it.
      **A repo gap is not the only blind spot — `0/n` means NOT ARCHIVED, never NEW.**
      The archive holds only what the queue carried, so any fact a prior run recorded from
      outside the queue reads `0/n already-elsewhere` on the next one — including a step
      1b-ship forge confirmation (`LANDED <evidence>`), which leaves no `⚠️ OUT-OF-BAND`
      anchor and names no shas read out of the repo, so the trigger above never fires for
      it. A block whose `HEAD:` predates the note's `updated:` is a late echo: dedupe it by
      SUBJECT and ticket id against the Source section before synthesizing. On 2026-08-11
      both queue blocks read `0/n` and both were already fully recorded — one gap-ingested
      from `git log` at 08:00, one via a forge confirmation — twice in one run.
      **Before synthesizing, run the third dedupe width** (*Rules* above):
      `sh AIOS/Systems/archive-ledger.sh dedupe AIOS/History/_ingested/<layer>/*.md
      +/_sessions/<layer>/<project>.md` — **archive glob first, queue file LAST**
      (reversing this reverses which side reads as "already archived"; see *Rules*).
      Any queue block whose `BLOCK` line reads `n/m` with `n==m` is already-ingested
      — skip it. **Read only the `BLOCK` lines whose second field is the queue file**
      (`+/_sessions/<layer>/<project>.md`): the command is handed the archive glob too,
      so it emits a `BLOCK` line per *archived* block as well — the large majority of the
      output, scaling with the archive rather than the queue. An archived block is
      already-ingested by definition, so `n==m` there is trivially true and says nothing
      about the queue; only the queue file's own rows are a skip decision.
      **A queue block with NO `BLOCK` row at all is not automatically a skip.** `archive-ledger.sh`
      registers a block only where it parses a `commits:` entry, so a memory-only
      session — one that never moved HEAD and lists no commits — produces no row, and
      its lone `HEAD:` sha collapses into a `DUP` against an earlier archive. `n==m` is
      then *absent* rather than false, and absence reads exactly like nothing to do.
      **The ledger is a sha index; its silence is about shas, never about content.**
      For every such block that CARRIES a `memory:` line, read it and diff the
      named `+/_sessions/.memory/<layer>/<project>/` files against what the note already
      carries as of the last ingest commit, then reconcile the difference — a `memory:`
      line is a synthesis obligation no sha can represent. On 2026-08-09 two blocks went
      unrowed this way and one carried that run's entire payload: an epic landing that
      closed 7 ⚠️ BRANCH STATE flags across six shards. The more purely a session is
      knowledge work rather than commits, the more invisible it is to the ledger.
      **With no `BLOCK` row the skip decision moves from the ledger to the block's own
      body**, and only an empty body ends in a skip: a bare `HEAD:` marker with no
      `commits:`, no `uncommitted:` and no `memory:` line has nothing to reconcile, and
      its `DUP` row is the evidence — the queue file's `HEAD:` sha duplicating an
      occurrence whose file field (after `duplicates`) is an `AIOS/History/_ingested/`
      path.
      Synthesize the queued digests into durable facts; append/update the note.
      Any flag written here carries the Rules-section stamp: `⚠️ (YYYY-MM-DD) <claim>`.
      For any digest carrying a `memory:` line, read the named files in
      `+/_sessions/.memory/<layer>/<project>/` and reconcile their facts into the
      note (idempotent merge — they're the source of truth; don't duplicate what's
      already captured, and drop note content a retracted mirror file contradicts).
      **A retraction is a whole-note sweep, not a single-bullet edit.** After dropping
      the contradicted content, grep the destination note for the retracted claim's key
      terms and disposition EVERY hit — a long-lived note usually carries the same claim
      in more than one place. An ordinary section is corrected in place. A section
      carried verbatim by [[km-rotate]] (a rotated map line, an activity trail) is
      **never** rewritten: add a dated pointer to that section's preamble instead,
      carrying the Rules-section stamp — `⚠️ (YYYY-MM-DD) **The rotated text below still
      asserts "<stale claim>" — that claim was RETRACTED on <date>; read <corrected
      section> above instead.**` — plus one line stating that the clause is not corrected
      in place because a rewrite would destroy the record of what the map line actually
      said. The pointer is the correction. On 2026-08-16 a standing-state bullet was
      retracted correctly and the identical claim survived inside the same note's rotated
      archive, where any grep for the topic still hits it; `wiki-lint-runner` caught it,
      the ingest did not. (Distinct from the outbound half below, which is vault→repo —
      this is one note contradicting itself.)
      **Fourth dedupe width — the destination note IS the mirror's ledger.** Run the
      same diff the no-`BLOCK`-row clause above requires, for EVERY `memory:` line and
      not only for ledger-silent blocks: a mirror is living state, rewritten in place
      and never archived, so nothing in `AIOS/History/_ingested/` covers it and a
      re-listed mirror re-offers its whole already-consumed body. Diff it against what
      the note carries as of the last ingest commit, synthesize only the difference,
      and name in step 1g's provenance which portion was new. On 2026-08-10 a mirror
      named by a `memory:` line for the second consecutive run was ~90% already
      ingested; only its new tail was durable, and the hand-diff that caught it is
      exactly the check that gets skipped on a large file mid-run.
      **Outbound half — two triggers, one section.** (1) A reconciled mirror file
      *retracts* a claim and the repo-side file that still carries it is named.
      (2) **Any vault-side claim that CONSTRAINS a repo action** — a flag reading *do
      not merge / do not deploy / do not bump until X* — whoever wrote it, mirror or
      this run's own synthesis. In both cases the vault cannot reach the repo; it can
      only write into itself. Record it under **`## Outbound to the repo`** in
      the project note (create the section on first use): the repo path or artifact,
      the claim (wrong-vs-corrected for a retraction; the unmet condition and what
      would settle it for a hold), and the date. Without this the correction lands in the
      vault and the agent reading that repo file on the next deploy still acts on the
      stale claim, with nothing anywhere connecting the two. **The hold is the half
      that looks handled and is not:** on 2026-08-10 a dependency major-bump flag read
      HELD pending a version check on the managed service behind it, the hold lived
      only in a vault shard, nothing held the PR, and it merged unverified — from
      inside the repo, a correctly-recorded hold and no hold are indistinguishable.
   b-ship. **Ship state** — once per distinct `branch:` this run's queue named for the
      project (skip the project's own default branch — it's shipped by definition,
      **unless the queue's newest `HEAD:` on it is ahead of `origin/<default-branch>`**:
      then it is committed locally and never pushed, and "shipped by definition" is
      simply false. Do **not** send it to `ship-state.sh` — the forge cannot confirm a
      sha it never received, so it answers `UNKNOWN` and raises a `⚠️ BRANCH STATE` flag
      for a state that is already fully known; the `git fetch` comparison IS the answer.
      Record the not-live fact per *The queue is not a complete record of the repo*
      above).
      **A literal `branch: HEAD` is a detached checkout, not a branch name** — so
      neither clause above fires: there is no name to match the default branch against
      and no name to group a "latest `HEAD:`" under. Give such a block its own
      ship-state call keyed on its own `HEAD:` sha, which is the only identity it has;
      `ship-state.sh` takes a ref, so a bare sha is a valid subject. Never fold it into
      a named branch, and never drop it as "not a real branch" — on 2026-08-15 the
      `HEAD` block held the feature's own squash-merge commit and returned LANDED by
      subject match, so the skip would have lost the landing. (Distinct from the
      bare-`HEAD:` marker in step 1b above, which IS a skip: that is a block with an
      empty *body*, this is a block with a full body and no branch *name*.)
      Take the LATEST `HEAD:` recorded for each named branch (per *Reading a digest block*
      below), resolve the repo's path with the **reverse** lookup — literally
      `sh AIOS/Systems/resolve-project.sh --project <layer> <project>`, reading
      `REPO_PATH=` off the output — and run
      `AIOS/Systems/ship-state.sh <repo-path> <HEAD-sha>` — the
      one place the forge gets asked, replacing a hand-rolled check per digest.
      **`--project` is not optional shorthand — the bare form does not accept what
      an ingest holds.** `resolve-project.sh <dir>` maps a DIRECTORY to a
      layer/project; an ingest has the pair and no dir, so
      `resolve-project.sh <scope> <project>` reads the scope as a directory name and
      answers `UNKNOWN_REPO=work`, exit 1. Five runs between 2026-08-12 and 08-15
      hit that and each fell back to grepping `repo-layers.tsv`'s 4th field by hand.
      **A miss names which kind it is:** `UNKNOWN_PROJECT=<layer>/<project>` means
      the pair is not in the manifest; `UNKNOWN_REPO=<name>` means a directory
      isn't. Either one, on a project the manifest plainly lists, means **the
      argument was wrong, not the manifest** — check the call before editing the
      manifest:
      - `LANDED <evidence>` — record it as fact in the note; if an earlier
        `⚠️ BRANCH STATE` flag for this branch is still open, resolve it with the
        evidence rather than leaving it dangling.
      - `OPEN` — the forge confirmed a PR still in flight; note it, no flag — a
        confirmed OPEN is a known state, not an unknown one.
      - `UNKNOWN` — neither confirmed nor denied. Write
        `⚠️ (YYYY-MM-DD) BRANCH STATE — <branch> not confirmed shipped` inline in the
        note (the Batch 1 stamp shape; date from local `date +%F`). Picked up by
        open-flags Mode A/B like any other flag.
   c. Add/refresh the note's entry in `[[Knowledge Map]]` (correct layer segment).
      **The refreshed line must come in under 1500 BYTES — measure it, do not eyeball it:**

      ```bash
      sh AIOS/Systems/km-measure.sh            # every over-limit line; silent + exit 0 when clean
      sh AIOS/Systems/km-measure.sh -n <line>  # one line's length
      ```

      **BYTES, not characters, and the distinction is not pedantic.** `aios-check`
      gates on `awk length`, which counts bytes; a map line is dense with em dashes,
      arrows and `⚠️` at 3–6 bytes each, so it runs 1–2% longer in bytes than in
      characters. A run that measured with Python `len` shipped a line at 1488
      "chars" and the gate failed it at 1504. `km-measure.sh` prints the number that
      actually binds — that is the whole reason it exists.

      **Budget the rotation BEFORE writing the clause, not after measuring the result.**
      Three consecutive runs hand-iterated against this threshold (1499 kept then
      trimmed, 1505 overshoot then trimmed again), because each wrote first and
      measured second. Check the current length, subtract, then write what fits.

      Anything that would exceed it gets rotated into the note's own
      activity-trail section as part of the *same* edit. [[km-rotate]] owns the
      threshold but only runs after the fact, so an ingest that appends a standing-state
      correction leaves the line over-threshold for a later pass to find: that line was
      rotated three times in two days, and once reached 50,787 chars — 34× the threshold —
      in the file the retrieval policy says to read first. A map line is a standing
      summary; if the fact is dated, it belongs in the note, not here.

      **Before a clause leaves the map, confirm it has a STANDING home — the trail is
      not one.** This is [[km-rotate]] step 4's gate (*"A clause that exists ONLY on the
      KM line gets written into the note before the map line shrinks — never drop
      it"*), and an ingest-time rotation owes it just the same. Grep the note, and for a
      sharded project its shards, for the clause's substance. A dated activity clause is
      satisfied by the trail. A standing-state clause (a ruling, a settled decision, a
      current rule) is NOT: the trail is archive that no skill reads for state, so
      trailing it deletes it from standing state while looking like preservation. Where
      nothing but the map line carries it, file it under the owning shard's heading in
      the *same* edit, then rotate. On 2026-08-21 a run rotated a line's most resolved
      clause, a ruling, into the trail; a pre-rotation grep found no shard carried it.

      **The destination is a NAMED HEADING, never the file tail.** Read the trail
      file's headings and append under the one that declares itself the target for new
      rotations — it may sit mid-file. A trail extracted by `provenance-rotate.py
      --extract` keeps whatever sections it was handed, so the last section is
      whichever one happened to end up last, not the intended one. On 2026-08-14 a
      tail-append landed inside a closed, dated `## Stragglers relocated from the hub`
      set whose own prose counts its four members — and the target heading already read
      *"Append new rotations here, not into the Stragglers section below"*. The
      instruction existed and lost anyway, because appending at EOF is the default
      motion. Appending under the named heading also keeps the tail free for the
      rotator (step 1g).
   d. **Draft** one `layer/project`-tagged line for `AIOS/History/Log.md` (newest
      top) — content only, NO gate or lint verdicts yet: those exist only after
      steps 2 and 4 actually run (a pre-written "🟢" caused a real incident).
   e. **Open flags:** run [[open-flags]] **Mode A** scoped to the ingested project —
      flags whose TOPIC this run's own evidence bears on (its commits, mirrors,
      synthesis) are dispositioned individually, resolved or confirmed-still-open; the
      remainder is carried en bloc in ONE line, never silently dropped. Mode A step 2
      owns that method — do not re-derive it here, and do not restate the retired
      *no flag passes unsighted* contract, which no unattended run can meet at 19
      shards. **State the scope and the unswept remainder in step 1g's provenance
      entry**, not only in the run report: a scheduled run's report reaches nobody, so
      an undeclared scope is indistinguishable from a skipped sweep — and on a
      commit-free queue there is nothing to re-derive an old marker against, so a
      sweep that re-asserts it manufactures false freshness. **Escalation is not an ingest
      step** — Mode B is a standalone sweep writing to `AIOS/History/audits/flag-register.md`,
      because one Log line per aged flag per run would refill, inside unattended
      runs, the file [[log-rollup]] exists to keep lean.
   f. **Fan-in guard** (only when step 1 was fanned out to workers): count the
      workers dispatched against the reports that came back carrying the full
      five-heading block (`NOTE`/`CHANGED`/`KM`/`LOG`/`FLAGS` — see the
      `ingest-worker` agent), and `test -e` every project note a report names.
      A worker reporting `KM: none` / `LOG: none` is alive and produced nothing
      durable — that counts. A worker returning no block, or naming a note that
      doesn't exist, is dead: name its digest in the run report and re-dispatch.
      Never proceed to step 2 on a partial set — a dead worker returns nothing, so
      an ingest covering 5 of 7 projects otherwise reports as complete.
   g. **Provenance:** write this run's entry in the project's Source section (its
      `source-history` shard, or the Source section of an unsharded note) — blocks
      consumed, mirror files reconciled, what was recorded where, and **what was
      deliberately not recorded**. **Newest-first, always — insert directly under the
      section's preamble, above the previous run's entry; never append at the end of
      the file.** Matching the note's existing direction is not a rule an unattended
      run can execute: the sections can disagree (one project newest-first,
      another oldest-first, a third flipping
      mid-file), so the direction is pinned once here rather than guessed per note.
      **The end of the file belongs to the rotator.** [[provenance-rollup]] leaves an
      `Older: [[source-history-YYYY-MM]]` pointer at EOF and `provenance-rotate.py`
      strips it with a regex anchored to end-of-buffer — one entry appended below it
      and the strip silently misses, so the pointer falls inside the last entry's span
      and the next rotation either duplicates it into the live shard or files it into
      an archive as if it were provenance. Both conserve bytes and both are wrong.
      **Forward-only — never reorder existing entries to match.** Entry order is audit
      trail, and a bulk rewrite resets the `git blame` that dates every unstamped
      legacy flag it touches (*Rules*, first bullet).
      **When this run ingested a queue/repo gap
      (*Reading a digest block*, last bullet), the entry names those out-of-band
      shas explicitly and says they will re-list as new — the next run recognizes
      them by SUBJECT and ticket id, not by sha.** Ingesting a gap opens a dedupe
      hole by construction: the archive is the sha ledger and only ever holds what
      the queue carried, so a commit taken from the repo instead of the queue enters
      no archive, and the following digest lists it with the ledger reporting
      `0/n already-elsewhere`. On 2026-08-09 four shas were ingested that way and the
      next run drafted three duplicate shard entries before a by-ticket-id grep
      caught them. Open such an entry with the `**⚠️ OUT-OF-BAND` anchor — one of the
      five [[provenance-rollup]] entry anchors, so the record survives rotation as its
      own entry rather than merging into a neighbour.
      This is a step, not a convention: it was carried
      by imitation for weeks and the first thin run skipped it silently, leaving that
      run's facts in the shards and the Log with no recorded digest-of-origin. No
      other step failed, because no other step depended on it.
2. **Gate:** dispatch the `layer-leak-auditor` subagent on **this run's diff**, one
   dispatch per layer (the wall: never hand one auditor two layers). Write the diff
   to a file first — `git diff -U3 -- <that layer's touched paths> > /tmp/aios-ingest-<layer>-<date>.diff`
   — and give the agent that path plus the list of touched notes for context.
   **The shared cross-layer files never enter that pathspec.** `AIOS/Maps/Knowledge Map.md`
   carries every layer's lines in one file (`AIOS/History/Log.md` is the same shape), so a
   whole-file diff hands one scope's auditor another scope's map line and the gate crosses
   the wall it exists to enforce. Leave them out of `<that layer's touched paths>`, then
   append this run's own lines for that layer to the diff file by hand — a file header and
   `+` lines, and **no `@@` hunk header**:

       --- a/AIOS/Maps/Knowledge Map.md
       +++ b/AIOS/Maps/Knowledge Map.md
       + <the line step 1c wrote for this layer>

   **Step 1c wrote those lines, so the run already holds them — never re-derive them by
   grepping the map for the layer's tokens.** Both obvious readings of the old wording are
   wrong in opposite directions. Passing the whole file leaks every other layer. A
   hand-rolled token split emitted a bodyless `@@ -40 +40 @@` into one scope's diff on
   2026-08-10 and the auditor correctly refused to certify the run — and the same filter
   drops any map line that carries no layer path, which fails silently: the gate returns
   WALL CLEAN for a line it was never shown. (Step 6's commit pathspec is a different
   list — the map and the Log are committed as usual.)
   **Not each whole note.** A leak can only enter through a line this run wrote, and
   whole-note dispatch re-reads every previously-gated line: on 2026-08-04 that cost
   205k subagent tokens on a 234-line diff and died on an API error, taking the run
   with it. Diff in, same verdict, ~1% of the tokens.
   If it flags a crossing, fix or revert that note before committing. If the auditor
   dies, retry it once; if it dies again, record the gate as **NOT-RUN** in the Log
   line and continue to step 3 — never stall, never ask, never skip the commit.
3. **Archive** consumed digests: move each processed `+/_sessions/<layer>/<project>.md`
   to `AIOS/History/_ingested/<layer>/<project>-<date>-<HHMM>.md` so re-ingest never
   double-counts. Recreate the empty queue dir. **Both paths are vault-root-relative —
   `cd` to the vault root first, or write them absolute.** A worker whose cwd sat in
   `<layer>/projects/<project>/` once created a whole stray `AIOS/History/_ingested/`
   tree there; it was empty, so git never showed it and nothing failed loudly.
   - **Verify AFTER the move, not before. A pre-archive count does not close the race —
     the window IS the `mv`.** The Stop hook appends and commits on every session end,
     so blocks arrive *during* an ingest. A run that counted 7 blocks, checked, then
     archived, found 8 in the archived file: one slipped in behind the check, four
     minutes later. Two earlier instances were caught by the same pre-check and read as
     "the check works" — it does not, it only narrows the gap. **Every pre-hoc check has
     a window; a post-hoc one has none.** So: archive, then **count the archived file's
     blocks against the count step 0 recorded for this queue file before synthesizing**,
     and read any excess before the run proceeds. Count with the script, not by hand:
     `sh AIOS/Systems/archive-ledger.sh count AIOS/History/_ingested/<layer>/<project>-<date>-<HHMM>.md`
     — its per-file number is the one to compare. A block archived unread leaves no
     trace anywhere — the queue reads as correctly drained
     and the Log says so.
   - **An excess block invalidates the step-2 gate, not just the read.** This is the
     sharper half and it leaves no marker at all: note text produced from a block that
     arrived after the gate ran ships **ungated**, while the Log carries the WALL CLEAN
     verdict the gate returned for a smaller diff. **A gate verdict is scoped to the diff
     it was handed and expires the moment the queue grows.** If the post-hoc count finds
     excess: synthesize it, then **re-run step 2 on the new diff** before committing —
     do not let the earlier verdict stand for text it never saw.
   - **Compare the project SET too, not only each file's block count.** Every check above
     is per archived file, so a queue file that did not exist when step 0 counted — a
     brand-new project's first digest — is invisible to all of them: each archived count
     matches exactly and the run reads as cleanly drained. After archiving, re-list
     `+/_sessions/*/` and diff the files present against the ones step 0 counted. On
     one run, a new queue file in another scope (1 block) appeared after step 0's
     count and after the step-2 gate diff was cut, and was caught only because the
     post-archive `ls` happened to show it. **A new file is an excess block by another
     route** — either ingest it now (step 1 for that project, then re-run step 2 on the new
     diff per the bullet above) or defer it to the next fire, and **state which, where an
     unattended run leaves a trace**: an ingest-now gets its own step 1g provenance entry as
     usual; a deferral is named in the run's [[Log]] line, since a deferred project has no
     note and no provenance entry to carry it. A file still in the queue is not lost, which
     is what makes deferring legitimate and silence not.
   - **`<HHMM>` is not decoration.** Multi-run days are the norm now, so a bare
     `<date>` collides and a plain `mv` silently clobbers the earlier queue's evidence.
     Three runs in one day had their suffixes (`-b`, `-c`, `-afternoon`) invented per
     run by pattern-matching whatever was already there; the timestamp ends that.
4. **Lint:** dispatch the `wiki-lint-runner` subagent, scoped to the touched notes'
   neighborhood (which includes the digests archived in step 3 — that edge is real,
   so 4 comes after 3). **That scope is the diff plus named line ranges, not whole
   notes** — the treatment step 2 already gives the gate. Hand the runner step 2's
   diff file for this layer (`/tmp/aios-ingest-<layer>-<date>.diff`, which by the
   pathspec rule above already carries this layer's Knowledge Map line and no other
   layer's) plus one explicit `<path>:<first>-<last>` range per touched note, and
   state that the ranges are the lint target. An ingest appends to the TAIL of a
   shard, and `aios-check --verbose` names the work-layer shards over 100KB, so
   whole-note dispatch re-reads hundreds of kilobytes to check thirty lines: on
   2026-08-14 the runner made no progress for 600s and failed outright, and a
   narrowed retry naming explicit line ranges returned a verdict.
   **Three checks legitimately read past the ranges** — schema (the note's
   frontmatter), Knowledge Map drift, and contradictions, where a line this run wrote
   can conflict with an old one elsewhere in the same shard. Name those three as
   permitted wider reads in the dispatch, or the range reads as a ceiling and the
   contradiction check quietly stops working on exactly the shards this rule exists
   for. **Findings cite the NOTE's `file:line`, never the diff file's** — the expiry
   rule below re-reads the live file at every location a finding names, and a
   diff-relative line number resolves to nothing.
   **Dispatch it; do not run the skill inline.** A checker
   sharing the context that wrote the notes is grading its own homework — it needs
   a context that has not seen the work. The agent returns proposed fixes only.
   **Steps 4 and 5 have no edge between them:** lint reads the touched notes,
   after-action reads this run's corrections and `feedback-*` mirrors, and neither
   consumes the other's output. Dispatch 4, then run 5 while it works; both land
   before step 6. **A lint verdict expires the same way a gate verdict does.** Step 3
   already says a gate verdict "is scoped to the diff it was handed"; a lint finding is
   scoped to the file state the runner read, and that state keeps moving — step 5 runs
   concurrently by design and the vault is a shared working tree with other writers.
   **Re-read the live file at every `file:line` a finding names before acting on it**,
   and name in the Log line which findings arrived already-closed. On 2026-08-09 a 🔴
   contradiction cited another scope's project note at a line this run had rewritten
   while the linter was mid-run: acting on it would have "resolved" the finding by
   editing text that was already correct.
5. **After-action:** read and follow `AIOS/Skills/after-action.md` — the run's
   corrections and changed `feedback-*` mirror files become procedure fixes
   (applied) or register rows (queued). Facts compounded above; this compounds the
   skills. This one stays in the orchestrator: it *writes* fixes and needs the
   identity wall, which a subagent doesn't hold.
6. Finalize the Log line with the **real** gate (step 2) + lint (step 4) verdicts —
   never pre-write them. Then commit + push the vault (Co-Authored-By trailer).
   **Commit by explicit pathspec** — name the notes this run wrote plus the digests
   archived in step 3, `git commit <path> <path> …`; never `-a`, never a bare
   `git add .`. The vault is a shared working tree and an ingest is not its only
   writer: on 2026-08-09 a concurrent session was mid-TDD in the same tree (building
   `AIOS/Systems/ship-state.sh` and adding the `1b-ship` step to *this* skill, so the
   version executed was not the version on disk at the end), and `-a` would have
   shipped that half-finished tool under an `aios: ingest` message. That run scoped
   its commit by hand because nothing here told it to. **If `git status` shows
   modified or untracked files this run did not write, name them in the run report —
   do not commit them, do not revert them.** They belong to whoever is holding them.
   **The inverse fires more often, and an empty or short `git status` is never evidence
   that there is nothing to commit.** The pathspec rule above binds the ingest's own
   commit and cannot bind another writer: a concurrent session reaching for `-a` or
   `git add .` takes this run's synthesis, its Knowledge Map edit, its register rows and
   its archived digests under an unrelated message, and nothing fails loudly — the queue
   is drained, the notes are correct, and the only symptom is modified files that are no
   longer modified. So **verify this run's own paths are actually uncommitted before
   committing**; for any that are missing, check `git log` for the commit that already
   absorbed them. Do **not** rewrite or amend that commit — it holds another writer's
   work too. Commit whatever artifacts remain under the ingest message, and **name the
   absorbing sha in the Log line** — step 0's walk-back only recognises commits the
   ingest itself titled `aios: partial ingest`, so a concurrent session's unrelated
   message is invisible to the next run too, and the Log line is the only place it can
   be found. On 2026-08-16 a 2-line commit titled for its own change carried six of a
   concurrent ingest's files; a run reading that empty status as "nothing to do" would
   have skipped this step entirely and reported success, and the Log line — written
   last, and the one artifact naming the run — would never have existed.
   **On a scheduled headless run, commit with `--no-gpg-sign`.** The vault is
   configured `commit.gpgsign=true` + `gpg.format=ssh`, and the SSH signer waits for
   an interactive approval a headless run can never give: on 2026-08-11 `git commit`
   hung twice, 2 then 5 minutes, and only went through on a `--no-gpg-sign` retry the
   run had to diagnose for itself. A hang here lands on the exact step this skill
   calls the single worst outcome — undrained queue, uncommitted synthesis — so the
   flag is stated inline rather than rediscovered.
   Report per layer: projects touched, notes updated, anything the auditor flagged,
   plus the after-action tally (fixes applied / rows queued).
