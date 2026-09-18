---
name: ai-tells
description: Scan prose for the tells that mark it as machine-written — copulative dodges ("serves as"), negative parallelisms ("not X, but Y"), significance inflation, participial fake-analysis, vague attribution, rule-of-three, synonym-churn, plus formatting habits and model junk markers. Use before publishing or reviewing human-voiced prose (blog post, page copy, README, email), and when asked to make writing sound human, de-slop a draft, or audit for voice drift.
effort: high
---

# AI tells

A **tell** is an involuntary giveaway. Not a rule violation, a habit that
leaks the writer's nature. You are hunting tells, not scoring "AI-ness":
detectors are unreliable, humans score near chance on this task, and **no
single tell is proof**. Density is the signal. Three tells in a paragraph
is a rewrite. One em dash is nothing.

Distilled from [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
(read 2026-07-24), filtered to what applies to first-person prose. Its
wikitext, DOI/ISBN, category, template, and edit-summary sections are
Wikipedia-specific and deliberately dropped.

## Run order

1. **Grep pass** — mechanical, catches the lexical tells.
2. **Read pass** — the structural tells no grep sees (§ Read pass).
3. **Rewrite, then re-grep.** Fixing one tell routinely plants another:
   killing repetition invites synonym-churn, killing "serves as" invites
   "functions as".

**Done when:** grep is clean or every surviving hit is a named deliberate
keep, every Read-pass item has been walked one at a time, and the prose
still sounds like its author rather than like nobody.

## Grep pass

Two passes, because hard-wrapped prose splits multi-word phrases across
newlines — in a file wrapped at ~70 characters, `rather than` is invisible
to a line-based grep about half the time. Run pass B whenever the target is
wrapped; skip it only when the file is one paragraph per line.

```bash
F=path/to/draft.md   # set to the file under audit

# A1. Model junk markers. Any hit is unconditional deletion.
grep -noE 'contentReference|oai_?citation|oaicite|turn[0-9]+(search|view|image)|attributableIndex|\[cite: |grok_(card|render)|ppl-ai-file-upload|attached_file|:::writing' "$F"

# A2. Lexical tells, as a frequency table. Read the counts, not the list.
grep -nioE '\b(serves? as|stands? as|functions? as|operates? as|boasts?|underscor(es?|ing)|showcas(es?|ing)|emphasiz(es?|ing)|highlight(s|ing)|foster(s|ing)|enhanc(es?|ing)|leverag(es?|ing)|pivotal|crucial|vital role|testament|tapestry|delve|intricate|meticulous|vibrant|robust|seamless(ly)?|enduring|realm of|landscape|navigat(e|ing|ion))\b' "$F" \
  | cut -d: -f2- | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn

# A3. Vague attribution. Collides with fact-grounding; treat every hit as a sourcing bug.
grep -niE '\b(experts? (say|argue|agree|note)|industry reports?|observers have|some critics|studies show|research shows|widely (held|regarded|considered))\b' "$F"

# A4. Typography. Count em dashes against the deliberate keeps below.
printf 'em dashes: %s\n' "$(grep -o '—' "$F" | wc -l | tr -d ' ')"
grep -nE $'[‘’“”]' "$F"   # curly quotes/apostrophes: match the file's own convention

# B. De-wrapped phrase pass. No line numbers, so it answers "is it in here",
#    then you locate it by searching the phrase.
tr '\n' ' ' < "$F" | grep -oiE \
  "not (only|just|merely|simply)[^.]{0,60}\bbut\b|\b(it|this|that)(.s not|( i)?sn.t) [^.]{0,40}[.,] +it.s|\bnot a [^.]{0,40}, not a\b|\brather than\b|despite (its|the|this)[^.]{0,80}(challenge|obstacle|hurdle)|faces (several|numerous|various)|\bnavigate the landscape\b|in today.s [^.]{0,20}world|it.s worth noting|in conclusion" \
  | sort | uniq -c | sort -rn
```

**Vocabulary ages.** The 2023-era set (`delve`, `tapestry`, `testament`,
`meticulous`, `intricate`) now flags *old-model* output specifically.
Post-mid-2025 the tell narrows to four survivors: `emphasizing`,
`enhance`, `highlighting`, `showcasing`. Weight a hit on those four
heaviest; they are what current models still overproduce.

## Tells, ordered by how often they bite

**1. Copulative dodge.** `is` and `are` replaced by marketing verbs:
serves as, stands as, functions as, boasts, features, offers, marks.
Highest-frequency tell in the corpus. → Write `is`. It is not a weaker
verb, it is the correct one.

**2. Negative parallelism**, three shapes, all tells:
`not only X but also Y` · `not X, it's Y` / `not X. It's Y` · **`X rather than Y`**. The
third is the one people never notice and models never stop writing. All
three fake a misconception the reader never held. → State the positive
claim alone. If the contrast is real, give the rejected option its own
sentence.

**3. Significance inflation.** Mundane subject wrapped in importance:
underscores, reflects a broader, pivotal/crucial/vital role, setting the
stage, symbolizing, enduring legacy, testament to. → Cut the significance
sentence entirely. If the thing matters, the specifics already said so.

**4. Participial fake-analysis.** Trailing `-ing` clause that asserts
analysis without doing any: "…, highlighting the importance of trust",
"…, fostering community", "…, contributing to growth". → Either explain
the mechanism in its own sentence or delete the clause. It carries no
information in either case.

**5. Vague attribution.** experts argue, industry reports, observers have
noted, some critics, studies show, widely held. → Name the source, or
make it a first-person claim from a seat you actually hold, or cut it.
This one is also a fact-grounding failure, not only a style tell.

**6. Formula conclusion.** "Despite its [positives], X faces several
challenges, including A, B, and C" closing on vague optimism. Also the
headings that host it: "Challenges and Legacy", "Future Outlook". → End
on the most specific thing you know, or on what you would do next.

**7. Rule of three.** Triplet adjectives and exactly-three-item lists,
everywhere, regardless of how many things there are. Ungreppable, so it
survives every mechanical pass. → Count the items honestly. Two is two,
five is five. A triplet you'd have written anyway is fine; a triplet per
section is a tic.

**8. Synonym-churn** (elegant variation). The same noun renamed on every
mention to dodge repetition — "artistic constraints", "non-conformist
artists", "their creativity" all pointing at one subject in one
paragraph. → Repeat the word. Repetition reads human; churn reads
generated.

**9. Promotional register.** vibrant, rich, profound, boasts, nestled,
groundbreaking, renowned, diverse array, breathtaking. Travel-brochure
tone in a first-person piece. → Say the concrete thing the adjective was
standing in for.

**10. Formatting habits.** Title Case headings where the catalogue uses
sentence case · bolding every key term on every appearance · bullet lists
shaped `**Header:** description` · emoji as visual structure · tables for
what is really prose · thematic breaks (`---`) above headings · em-dash
pileups. → Match the neighbors in the same directory. The tell is
divergence from the corpus, not the mark itself.

## Deliberate keeps

Every corpus has marks that look like tells and are not. **Get the keeps
before the read pass** — from the caller, from the skill that mandates the
format, or from the neighbouring files. Name them up front so they stop
being findings on every run.

Three recur in almost any first-person corpus:

- **Em dashes are not banned.** A mandated signoff line and a disclaimer
  cadence are voice, not tells. Judge em dashes by **rate**, never by
  presence: a couple per piece plus the signoff is voice, six in three
  paragraphs is a tell.
- **Curly quotes** are correct wherever the surrounding corpus uses them.
  They are a tell in wikitext, not in Markdown prose. Match the file.
- **First-person "I"** is a conversational-AI tell only where the format
  forbids it. Where the voice is mandated first-person, it is the voice.

**Declared keeps for a specific corpus live in `references/corpus-<name>.md`.**
Read the one matching the file under audit, if it exists — it names that
corpus's signoff, quote convention, and any format the caller mandates that
would otherwise read as a tell. No reference file means ask the caller.

## The GEO tension, resolved

A caller optimizing for AI search will prescribe question-shaped H2s with a
self-contained, conclusion-first lead answer in the first 40-75 words. That
skeleton is structurally the "outline-like, formulaic section" tell, and it
is kept on purpose: AI search engines extract at the passage level.

Resolution: **keep the skeleton, forbid the filler.** Every lead answer must
carry a number, a stake, a lived detail, or a counter-take. A lead answer
that neutrally restates the heading is the tell arriving through the front
door. Where a corpus reference declares such a skeleton, it is a keep; the
filler inside it never is.

## Not this skill's job

No AI-likelihood score, no percentage, no detector. Those are the things
the source page documents as unreliable. Output is a located list of tells
and their rewrites, or "clean".
