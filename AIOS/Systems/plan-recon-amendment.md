# 🔍 Plan-recon amendment — a brief cites only what it has opened

**An extension to the superpowers `writing-plans` skill.** Kept in the vault (not
the plugin cache) so a plugin upgrade can't clobber it, and version-controlled here
like [[ponytail-amendment]] and [[effort-table]]. Import it from your global agent
config so it reaches every repo on the machine.

**Scope-neutral infra** — pure planning hygiene, no identity content, so the import
crosses no wall. Note the rule this file follows on itself: **a scope-neutral doc
that every session imports carries no wikilink and no path into a single scope's
files** — the link graph it makes is machine-wide, and the file it points at is
not. If you extend it, keep its citations generic for the same reason.

## Rules

### 1. Recon order: graph → grep → read → write

For any "where does X live / how does Y flow / what touches Z" question that will
feed a plan:

1. **`graphify-scout` first, and visibly** — a named agent dispatch, so it is
   obvious from the transcript that the graph was used. Falling back to
   Explore/grep is for when the graph misses or is stale, never the first move.
2. **Check the graph's freshness before trusting it.** Compare source mtimes
   against the graph manifest. If source is newer, say so and either rebuild
   (`/graphify`, or `--update`) or mark every graph-derived finding unverified.
   A point-in-time graph never reflects an unmerged branch.
3. **Verify every hit with grep + Read** before it enters a brief. The graph is a
   map, not ground truth — seed-matching latches onto plausible-but-wrong nodes:
   a recon query has surfaced a whole plausible neighbourhood while missing the
   one service file it was asking about.

Never grep-only for orientation — greps find strings, not structure, and an
import is not a call site. Never graph-only for assertion.

### 2. A brief cites only what it has opened

Every path, symbol, field name, line number and snippet in a plan brief is read
from source at authoring time — or carries an explicit `UNVERIFIED:` tag naming
what would settle it. An unmarked citation is a claim that the file was opened.

Highest risk, in order: **literal snippets an implementer will copy** (test
bodies, component source, regexes), then field names on objects the plan never
constructs, then line numbers.

**Opened is not live.** Reading a file proves it exists and says what you think; it
does not prove anything calls it. Before a file enters a brief as *the* reference
implementation, search for its importers and call sites with a suffix- and
specifier-tolerant grep (with and without the extension, re-exports, dynamic
imports). If that finds none, treat the file as probably dead and look for the live
behaviour elsewhere, often inlined in the callers rather than in the file named for
the feature. A grep that finds nothing is a signal, not proof. Then `git log`
whatever you land on: a fix usually lands in the live implementation first, so the
reference is its current behaviour, not the version a stale copy was built from.

### 3. Name the cross-task seams

For every pair of tasks sharing a file or an interface, write down what one
*produces* and the other *consumes*. A thing produced by one task and consumed by
none is a dead-code seam; a thing consumed but never produced is a silent no-op.

## Why

Distilled from a post-mortem on a 15-task implementation plan. The implementation
was never the slow part — the plan was, because it was written from greps and
inference instead of from the files.

- Nine of fifteen tasks needed a fix round; **every one traced to a plan defect,
  not implementer error.**
- Briefs were wrong in six places (Task 11), five (Task 12), four (Task 10). One
  re-introduced a bug an earlier task had already fixed.
- Three literal snippets were actively harmful: a prescribed negative test that
  could not fail, a field preference that was unimplementable, and a phone regex
  that concatenated an extension into a **different real number**. All three were
  caught by implementers, not reviewers.
- A field produced by five backend tasks was consumed by no UI, because two
  independent whitelists silently dropped it — a §3 seam nobody had written down.
- The repo's own knowledge graph existed and went unused for the entire session,
  against standing guidance to query it first.

## Changelog
- Added §2's *opened is not live* paragraph: a file read from source can still be
  dead code, so a reference implementation needs its importers checked first.
  Worded so an empty grep is a signal, not proof — a suffix-blind search once
  reported live files as unimported.
- Created; §1 makes graph-first recon executable at plan time rather than
  advisory, §2 and §3 come from the failure analysis above.
