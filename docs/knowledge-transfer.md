# Transferring a project brain to a teammate

Once a project note in `<scope>/projects/<project>.md` has accumulated a few months of ingested sessions, it is the single most valuable file in your vault. It is also the one your teammates would benefit from most — and the one most likely to leak something if you hand it over carelessly.

This is the recipe. It is deliberately manual. There is no `/aios-share` command, because the decision of what may leave is not one an agent should make unsupervised.

## What you're actually transferring

Three things, in descending order of value:

1. **The project note** — `<scope>/projects/<project>.md`. Decision-level synthesis: architecture calls, conventions, recurring bug classes, gotchas that cost someone a day.
2. **The native-memory mirror** — `+/_sessions/.memory/<scope>/<project>/*.md`. One durable fact per file, written by the agent as it worked. Higher resolution than the note, and where most of the note came from.
3. **The effort hub** — whatever note holds the stack and product overview. Cheap to re-derive; include it for orientation.

Do **not** transfer `+/_sessions/<scope>/<project>.md` (the raw digest queue) or `AIOS/History/_ingested/`. Those are unsynthesized git signal. They add noise and carry branch names, commit messages, and diff-stats you haven't reviewed.

## The recipe

### 1. Establish who may receive it

Ask this out loud, and get a real answer:

> Is the recipient inside the same trust boundary as the material?

For employer-proprietary content that means: are they employed by the same employer, on this codebase, with existing access to the repo? If the answer is anything other than an unambiguous yes, the transfer is a **disclosure**, not a handoff, and the rest of this document does not apply.

This gate is not paranoia. A project brain is a distilled, indexed, high-signal summary of internals that would take an outsider months to reconstruct. It is more sensitive than the code, not less.

### 2. Assemble the bundle out-of-tree

Copy the three artifacts into a scratch directory. Never build the bundle inside the vault — a stray `git add -A` is all it takes.

```bash
BUNDLE=$(mktemp -d)/project-brain
mkdir -p "$BUNDLE"/{<scope>/projects,memory}
cp "<scope>/projects/<project>.md"          "$BUNDLE/<scope>/projects/"
cp  +/_sessions/.memory/<scope>/<project>/*.md   "$BUNDLE/memory/"
```

### 3. Strip the sending vault's identity

The project note is about the project. The files around it are about *you*. Remove:

- `[[wikilinks]]` pointing at `me.md` files or notes that only exist in your vault. They render as broken links in theirs and name scopes the recipient has no business knowing exist.
- Any frontmatter `related:` entry pointing outside the bundle.
- Personal framing — "my day job", "<your name>'s notes", the private worktree path you keep on your laptop.
- Sentences whose subject is you rather than the project.

Run `AIOS/Skills/sanitize.md` over each file. Then, if your vault has the wall enabled, dispatch `layer-leak-auditor` at the whole bundle and read its verdict. A `SOFT` finding is not automatically fatal — but you must be the one who decides that, not the agent.

### 4. Check for the things sanitize doesn't catch

Read the bundle yourself, once, end to end. Look specifically for:

- **Secrets and credentials.** Key prefixes, token formats, merchant IDs, internal hostnames, staging URLs.
- **Customer and vendor data.** Real company names in examples. A shared mailbox address. Anything that identifies a third party.
- **Ticket and PR numbers.** Fine within an employer; a leak outside one. Decide once and apply consistently.
- **Anything you wrote when tired.** Project brains accumulate frank assessments of code and, sometimes, of people.

### 5. Deliver privately

Put the bundle where the material already lives: a private repo the recipient already has access to, or the project repo itself under `docs/`. Do not attach it to a public issue, a gist, or a shared drive whose ACL you have not personally read.

If you use a repo, commit it as a **new** repo or a new directory — never by pushing a branch of your vault. Vault git history contains every scope you have ever had.

### 6. Tell them how to install it

The recipient runs `/aios-bootstrap` first, creating their own vault with their own scopes. Then:

```bash
cp -r project-brain/<scope>/projects/<project>.md  ~/code/aios/<scope>/projects/
cp -r project-brain/memory/*.md  ~/code/aios/+/_sessions/.memory/<scope>/<project>/
```

Then add a line for the project to their `AIOS/Maps/Knowledge Map.md`, and a row to `AIOS/Systems/repo-layers.tsv` mapping the repo to their scope. From then on their own sessions digest into the same note and it keeps compounding — from your starting point instead of from zero.

## Why the memory mirror matters most

The project note is a summary, and summaries lose the *shape* of a mistake. The mirror keeps it. A file named `project_tenant_escape_gate_multiline_blindspot.md` tells a new engineer that the gate exists, that it has a blind spot, exactly what the blind spot is, and — crucially — that someone already lost time to it.

That is the thing you cannot get from reading the code. Transfer it.

## What not to build

Do not write an automated exporter. Every version of that tool eventually gets run by someone in a hurry against the wrong scope. The whole value of this document is that a human read the bundle before it left.
