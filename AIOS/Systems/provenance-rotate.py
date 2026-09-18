#!/usr/bin/env python3
"""Rotate a project's source-history.md entries older than the current month
into source-history-YYYY-MM.md. Implements AIOS/Skills/provenance-rollup.md.

    python3 AIOS/Systems/provenance-rotate.py <scope>/projects/<Proj>/source-history.md [--apply]

Second mode -- relocate ONE named section out of the shard into a standalone note:

    python3 AIOS/Systems/provenance-rotate.py <shard> --extract '## Heading prefix' <dest.md> [--apply]

Both modes are dry-run by default: they print the full conservation proof and
write nothing. --apply performs the move.

WHY --extract LIVES HERE AND IS NOT ITS OWN SCRIPT. Rule F's second-ceiling note
says plainly that a committed writer under work/ does NOT generalise and that "if
they multiply, the fix is to check the content in the tools themselves, not to
widen Rule F." A second script would be exactly that multiplication. This is the
same operation class against the same file under the same three conditions that
made the trade acceptable (carved-out destination, already-committed bytes being
relocated, sha256 conservation proved before anything is truncated), so it stays
one reviewable writer with two modes rather than two writers.

WHY THIS IS A SCRIPT AND NOT A MODEL DOING EDITS. Two reasons, both hard:
  1. vault-write-guard Rule F refuses ad-hoc shell writes under work/, which
     leaves the Write tool -- and the live shard contains a single 45,364-char
     line plus 213 unicode-bearing lines. Byte-exact reproduction by hand is not
     a real operation, and one wrong character silently corrupts the audit trail.
  2. The conservation proof has to be deterministic. Assertion 3 exists because
     equal byte totals do NOT prove equal bytes; a hash computed by the same pass
     that moved the bytes is worth more than one recomputed by hand afterwards.
Invoking this with the shard path as a plain argument is guard-legal: the path is
fully visible (nothing is hidden in a variable) and the command contains no write
shape, so Rule F's string check is satisfied honestly rather than dodged. The
write logic lives here, committed and reviewable BEFORE it runs -- which is the
property Rule F is protecting ("a shell command has no content until it executes").

Order of operations is load-bearing: archive written and verified FIRST, live
shard truncated only after all three assertions pass. A partial archive write
must never find the live shard already truncated.
"""
import sys, re, os, glob, hashlib, subprocess, datetime

# The ONE anchor definition. An entry is one anchor line plus everything up to
# the next anchor (or EOF). Bytes before the first anchor are the preamble.
ANCHOR = re.compile(
    rb'^(## |From the |Also from the |Synthesized from the |\*\*\xe2\x9a\xa0\xef\xb8\x8f OUT-OF-BAND)',
    re.M)
ING = re.compile(rb'ingested (\d{4}-\d{2}-\d{2})')
DATE = re.compile(rb'\d{4}-\d{2}-\d{2}')
# A pointer block previously written by this tool, anchored to EOF.
OLD_POINTER = re.compile(
    rb'\nOlder: \[\[source-history-\d{4}-\d{2}\]\]'
    rb'(?: \xc2\xb7 \[\[source-history-\d{4}-\d{2}\]\])*\n\Z')   # \xc2\xb7 = ' · '


def rel_in_scope(shard):
    """Repo-relative path of `shard`, or exit if it is outside Rule D's scope.

    THE PATH CONSTRAINT FOR BOTH MODES. This lived inside extract() and so gated
    only --extract; main() took sys.argv[1] and went straight to open(). Rotation
    TRUNCATES its target, so the unconstrained reachable set was every git-clean
    anchor-bearing .md in the vault -- including any scope's sources/ and
    work/sources/ (Rule A: immutable, block ALL writes) and life/ (Rule B).
    Rule F never fires on any of it: the shard arrives as a plain argument, which
    is precisely the reviewability-for-enforcement trade this script was granted.
    That grant is written down in vault-write-guard.sh as conditional on "the
    destination is a Rule D carve-out anyway" -- a claim the code has to hold up,
    not merely restate.

    realpath, NOT abspath: abspath is string arithmetic and does not resolve
    symlinks, so a symlinked path satisfied the comparison while the write landed
    elsewhere. Rule F's verb list has no `ln`, so planting that link is unguarded.

    FAILS CLOSED WHEN GIT FAILS. This read `subprocess.run(...).stdout.strip()`
    with no returncode check, so outside a repo `git rev-parse` errored, stdout
    came back empty, and `os.path.realpath("")` silently yielded THE CURRENT
    DIRECTORY as the repository root. Any directory merely SHAPED like
    `<scope>/projects/<X>/source-history.md` then passed the scope check and was
    rotated -- reproduced end-to-end, archive written and shard truncated, in a
    plain temp dir. Rotation's other net does not help: `git status --porcelain`
    also returns empty on failure, so the clean-tree precondition passed
    vacuously too (fixed at its own call site). A guard that reads "could not
    check" as "check passed" is worse than no guard, and a destructive tool that
    cannot locate its own boundary has no business writing anything.
    """
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(f"cannot establish a git repository root for {shard} "
                 f"(git rev-parse --show-toplevel failed: "
                 f"{r.stderr.strip() or 'no output'}). Refusing: this tool WRITES "
                 f"and TRUNCATES, its scope gate is defined relative to the repo "
                 f"root, and without that root there is no boundary to enforce. "
                 f"There is no cwd fallback on purpose -- inferring the root would "
                 f"make any directory shaped like <scope>/projects/<X>/ rotatable.")
    root = os.path.realpath(r.stdout.strip())
    rel = os.path.relpath(os.path.realpath(shard), root)
    # THE GATE IS DERIVED, NOT WRITTEN HERE. Scopes come from layers.tsv column 1,
    # so adding a scope needs no edit to this file -- and a directory that is not a
    # declared scope is out of reach by construction. `<scope>/sources/` (immutable,
    # Rule A) and every path outside a scope's projects/ or notes/ stay unreachable
    # for the same reason: this tool WRITES and (in rotation mode) TRUNCATES its
    # target, the guard's rules never see these bytes, so the argument IS the
    # security surface. Widening this is a guard change, not a flag.
    scopes = read_scopes(root)
    allowed = tuple("%s/%s/" % (sc, sub) for sc in scopes
                    for sub in ("projects", "notes"))
    if not allowed:
        sys.exit("refusing %s: no scopes are declared in AIOS/Systems/layers.tsv, "
                 "so this tool has no sanctioned write target at all. Declare a "
                 "scope before rotating anything." % rel)
    if not rel.startswith(allowed):
        sys.exit("refusing %s: scope is <scope>/projects/ or <scope>/notes/ for a "
                 "scope declared in AIOS/Systems/layers.tsv. Declared scopes: %s."
                 % (rel, ", ".join(scopes)))
    return rel


def declare_scopes(repo, *slugs):
    """Write a minimal layers.tsv so the derived scope gate has scopes to read.
    Fixtures used to rely on a hardcoded scope name; with the gate reading the
    manifest, a fixture that declares nothing is indistinguishable from a vault
    with no scopes -- and every rotation would refuse for the wrong reason."""
    d = os.path.join(repo, "AIOS", "Systems")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "layers.tsv"), "w", encoding="utf-8") as fh:
        for sc in slugs:
            fh.write("%s\t%s\t%s/*\t-\t-\n" % (sc, sc.title(), sc))


def read_scopes(root):
    """Scope slugs from column 1 of AIOS/Systems/layers.tsv. Empty list if absent."""
    manifest = os.path.join(root, "AIOS", "Systems", "layers.tsv")
    out = []
    try:
        with open(manifest, encoding="utf-8") as fh:
            for line in fh:
                if line.lstrip().startswith("#"):
                    continue
                cols = line.rstrip("\n").split("\t")
                if len(cols) >= 3 and cols[0].strip():
                    out.append(cols[0].strip())
    except OSError:
        return []
    return out


def entry_date(raw, start, end):
    """Content date, scoped to the ANCHOR LINE only.

    The slice stops at the first newline so an `ingested` date in the entry BODY
    is unreachable by construction rather than filtered out afterwards. Two
    Observed entries carry their only `ingested` match in the body as a
    cross-reference to an earlier ingest; a first-match-in-entry regex reads that
    date instead. Both name an in-month date today, so a body-scoped bug would
    stay dormant and first misfile an entry at a month boundary.
    """
    nl = raw.find(b'\n', start)
    line = raw[start:nl if nl != -1 else end]
    m = ING.search(line)                      # `ingested YYYY-MM-DD` wins...
    if m:
        return m.group(1).decode()
    m = DATE.search(line)                     # ...else first date on the line
    return m.group(0).decode() if m else ""


def split(raw, cur_month):
    starts = [m.start() for m in ANCHOR.finditer(raw)]
    if not starts:
        sys.exit("no anchors found -- wrong file?")
    spans = list(zip(starts, starts[1:] + [len(raw)]))
    rot, stay = [], []
    for s, e in spans:
        d = entry_date(raw, s, e)
        if not d:
            sys.exit(f"entry at byte {s} has no date on its anchor line; refusing to guess")
        # Entries are NOT in date order -- the rotate and stay sets interleave.
        # Select by date, never by position; each set keeps its original order.
        (rot if d[:7] < cur_month else stay).append((s, e))
    return starts[0], rot, stay


def measure(buf):
    s = [m.start() for m in ANCHOR.finditer(buf)]
    return (len(s), s[0] if s else 0, len(buf) - s[0] if s else 0)


def pick(raw, prefix):
    """Span of the ONE entry whose anchor line starts with `prefix`.

    Exactly one, or exit. A prefix matching two sections would silently relocate
    the first and leave the second, which conserves no bytes and reads as success;
    a prefix matching none is a typo the operator must see, not a no-op.
    """
    starts = [m.start() for m in ANCHOR.finditer(raw)]
    if not starts:
        sys.exit("no anchors found -- wrong file?")
    spans = list(zip(starts, starts[1:] + [len(raw)]))
    hits = [(s, e) for s, e in spans if raw[s:s + len(prefix)] == prefix]
    if len(hits) != 1:
        sys.exit(f"{len(hits)} sections match {prefix!r}; need exactly 1")
    return starts[0], len(spans), hits[0]


def extract(shard, prefix, dest, apply_):
    """Relocate one named section out of the shard into a standalone note.

    Sibling of the monthly rotation: the section this was built for
    (`## Knowledge Map activity trail`) is not provenance at all -- it is itself
    the output of a prior km-rotate run -- yet it stays under both date rules
    forever, so the rotation can never reach it while the ingest re-reads it whole
    every run.

    Three conservation assertions, and the third is the one that matters. Equal
    spans and equal sha256 both fail loudly if bytes go missing; but the section
    holds a SINGLE 45,364-byte line, and a reflow would be invisible to a human
    reading the diff while corrupting the audit trail. Longest-line equality is
    the only check that catches it, which is also why this is a script and not a
    Write call -- byte-exact reproduction of that line by hand is not a real
    operation.
    """
    today = datetime.date.today().isoformat()
    raw = open(shard, 'rb').read()
    pb = prefix.encode()
    preamble, n_spans, (s, e) = pick(raw, pb)
    section = raw[s:e]

    # The pre-move fingerprint must come from git, not from the file we are about
    # to rewrite -- comparing a buffer against itself proves nothing once --apply
    # has run. `raw == head` is asserted too, so the comparison is honest rather
    # than merely available.
    # realpath throughout (inside rel_in_scope): git may report a toplevel through
    # one symlink chain and the caller name it through another (macOS /tmp ->
    # /private/tmp is the common one), which yields a bogus relative path and an
    # empty `git show`. rel_in_scope also enforces the shard constraint, so calling
    # it here rather than trusting main() keeps extract() safe when called directly
    # -- which selftest_extract() does.
    rel = rel_in_scope(shard)
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], capture_output=True).stdout
    if raw != head:
        sys.exit(f"{shard} differs from git HEAD; commit or stash first so the "
                 f"pre-move hash is well defined and the move stays recoverable")
    _hp, _hn, (hs, he) = pick(head, pb)
    head_section = head[hs:he]

    if os.path.exists(dest):
        sys.exit(f"{dest} already exists; refusing to overwrite")

    # PATH CONSTRAINT -- a guard boundary, not a convenience check. The rotation
    # mode DERIVES its archive path (source-history-<month>.md beside the shard);
    # --extract takes one as an argument. Rule D never sees these bytes (Python
    # open(...,'wb') bypasses the tool path entirely), so the guard cannot be the
    # backstop here and the argument handling IS the security surface -- this is
    # the vault's only sanctioned writer under work/.
    #
    # TWO constraints, because one was not enough:
    #
    # 1. THE SHARD, not just the destination -- enforced above by rel_in_scope(),
    #    which main() now calls for BOTH modes. The destination is anchored
    #    relative to the shard, so an unconstrained shard makes the reachable set
    #    `<dir of any anchor-bearing .md>/_history/<new>.md` REPO-WIDE -- and the
    #    "subset of Rule D's carve-out" claim below is only true where Rule D's
    #    scope gate applies (<scope>/projects, <scope>/notes). Anchoring the shard makes
    #    the claim true instead of merely stated.
    # 2. realpath, NOT abspath. abspath is pure string arithmetic -- it does not
    #    resolve symlinks -- so a symlinked `_history` satisfied the comparison
    #    and the write landed outside the repo entirely. Rule F's verb list has no
    #    `ln`, so planting that symlink is itself unguarded. Reach was bounded
    #    (new files only, os.path.exists refuses overwrite, bytes already
    #    committed) but "bounded" is not "absent".
    want = os.path.join(os.path.dirname(os.path.realpath(shard)), "_history")
    if os.path.dirname(os.path.realpath(dest)) != want:
        sys.exit(f"destination must sit in {want}/ (Rule D's carve-out); "
                 f"got {dest}. Widening this is a guard change, not a flag.")

    # Destination preamble: the shard's own frontmatter fields, with `updated`
    # stamped today because this is a NEW note created today (the monthly archive
    # inherits its date instead -- it is a snapshot of an older month). `parent:`
    # is asserted present, not hoped for: without it the Knowledge Map coverage
    # check counts this as an unmapped note and aios-check exits non-zero.
    fm = raw[:preamble].decode()
    fields = {k: v for k, v in
              (l.split(": ", 1) for l in fm.splitlines() if ": " in l)}
    fields["updated"] = today
    heading = re.sub(r'^#+\s*', '', section.split(b'\n', 1)[0].decode())
    pre = ("---\n" + "".join(
        f"{k}: {fields[k]}\n" for k in
        ("tags", "type", "layer", "project", "parent", "updated") if k in fields)
        + "---\n"
        + f"# {heading.split(' (')[0]}\n\n"
        + f"Relocated whole from `{os.path.basename(shard)}` on {today}; the "
          f"section below is byte-identical to the original.\n\n"
    ).encode()
    if ANCHOR.search(pre):
        sys.exit("destination preamble contains an anchor-matching line")
    if not re.search(rb'^parent:', pre, re.M):
        sys.exit("destination preamble carries no `parent:` -- Knowledge Map "
                 "coverage would flag it and aios-check would exit non-zero")
    N = len(pre)
    note = pre + section

    # Pointer left where the section was. Deliberately NOT anchor-shaped: it is a
    # breadcrumb, not an entry, and an anchor here would hold the shard's count at
    # its old value and hide that a section left. Its byte cost is a DECLARED
    # delta, printed below, never absorbed into the section accounting.
    pointer = (f"Moved: the {heading.split(' (')[0]} section now lives in "
               f"[[{os.path.basename(dest)[:-3]}]] "
               f"(`{os.path.relpath(dest, os.path.dirname(shard))}`), "
               f"relocated {today}.\n\n").encode()
    if ANCHOR.search(pointer):
        sys.exit("pointer line would parse as an anchor; it must not")
    live = raw[:s] + pointer + raw[e:]

    # BOTH SIDES MEASURE THE SECTION. Measuring the whole note compares the moved
    # bytes against the GENERATED PREAMBLE's longest line (~110-160 bytes: the
    # `parent:` field and the "Relocated whole from ..." sentence), so any section
    # whose longest line is shorter than its own preamble -- i.e. every normal
    # prose section -- aborts as a phantom reflow. This passed on the activity
    # trail only because 45,364 happens to exceed the preamble; it worked by luck,
    # not by construction, and selftest_extract() now pins the short-line case.
    long_src = max(len(l) for l in section.split(b'\n'))
    long_dst = max(len(l) for l in note[N:].split(b'\n'))
    a1 = (len(note) - N) == (e - s)
    a2 = hashlib.sha256(note[N:]).hexdigest() == hashlib.sha256(head_section).hexdigest()
    a3 = long_dst == long_src
    # The shard keeps every byte that was not the section: the two surviving
    # halves must be bit-identical, not merely the right length.
    a4 = live[:s] == raw[:s] and live[s + len(pointer):] == raw[e:]
    a5 = len(live) == len(raw) - (e - s) + len(pointer)
    a6 = measure(live)[0] == n_spans - 1

    print(f"shard            : {shard}")
    print(f"destination      : {dest}")
    print(f"section span     : [{s}, {e})  = {e - s} bytes  (anchor {n_spans} spans)")
    print(f"dest preamble    : N = {N} (parent: present -> True)")
    print(f"pointer line     : {len(pointer)} bytes  {pointer!r}")
    print()
    print(f"shard  : {len(raw)} -> {len(live)} bytes")
    print(f"dest   : {len(note)} bytes = {N} preamble + {len(note) - N} section")
    print()
    print("=== ASSERTION 1 - SPAN ===")
    print(f"  dest minus preamble = {len(note) - N}, source span = {e - s}"
          f"  -> {'PASS' if a1 else 'FAIL'}")
    print("=== ASSERTION 2 - CONTENT (sha256 vs git HEAD) ===")
    print(f"  git HEAD span      = {hashlib.sha256(head_section).hexdigest()}")
    print(f"  dest minus preamble= {hashlib.sha256(note[N:]).hexdigest()}")
    print(f"  -> {'PASS' if a2 else 'FAIL'}")
    print("=== ASSERTION 3 - LONGEST LINE (no reflow) ===")
    print(f"  source = {long_src}, destination = {long_dst}"
          f"  -> {'PASS' if a3 else 'FAIL'}")
    print("=== shard remainder ===")
    print(f"  surviving halves byte-identical -> {'PASS' if a4 else 'FAIL'}")
    print(f"  length {len(raw)} - {e - s} + {len(pointer)} = {len(live)}"
          f"  -> {'PASS' if a5 else 'FAIL'}")
    print(f"  anchors {n_spans} -> {measure(live)[0]} (want {n_spans - 1})"
          f"  -> {'PASS' if a6 else 'FAIL'}")

    if not (a1 and a2 and a3 and a4 and a5 and a6):
        sys.exit("\nCONSERVATION FAILED -- nothing written.")
    if not apply_:
        print("\ndry run; pass --apply to perform the move.")
        return

    # Destination FIRST, re-read and verified from disk, and only then the shard.
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, 'wb') as f:
        f.write(note)
    back = open(dest, 'rb').read()
    if back != note or hashlib.sha256(back[N:]).hexdigest() != \
            hashlib.sha256(head_section).hexdigest() or \
            max(len(l) for l in back[N:].split(b'\n')) != long_src:   # section, not note
        os.unlink(dest)
        sys.exit("destination failed verification after write; removed it, shard untouched")
    print(f"\ndestination written and verified from disk: {dest}")

    with open(shard, 'wb') as f:
        f.write(live)
    print(f"shard rewritten: {shard} -> {len(live)} bytes")


def selftest():
    """Pins the one subtle rule: the date comes from the ANCHOR LINE only.

    This is the bug that would otherwise lie dormant -- a body-scoped extractor
    reads a cross-reference date, and because those references name in-month
    dates today, nothing misfiles until a month boundary.
    """
    body_ref = (b"## 2026-08-07 ingest -- 11 blocks\n"
                b"- the commit was already ingested 2026-07-06; see there\n")
    assert entry_date(body_ref, 0, len(body_ref)) == "2026-08-07", "body date leaked in"

    on_line = b"From the 2026-08-01T02:30Z queue, ingested 2026-07-31 evening\n- x\n"
    assert entry_date(on_line, 0, len(on_line)) == "2026-07-31", "`ingested` must beat the UTC stamp"

    plain = b"Also from the 2026-07-09 git digest (HEAD 26212677)\n- x\n"
    assert entry_date(plain, 0, len(plain)) == "2026-07-09", "first date on the line"

    # Interleaving: entries are NOT in date order, so selection must be by date.
    raw = (b"From the 2026-08-08 queue\n- a\n"
           b"From the 2026-07-31 queue\n- b\n"
           b"From the 2026-08-05 queue\n- c\n")
    pre, rot, stay = split(raw, "2026-08")
    assert len(rot) == 1 and len(stay) == 2, "interleaved split wrong"
    assert raw[rot[0][0]:rot[0][1]] == b"From the 2026-07-31 queue\n- b\n"

    # A '##' archive title would be counted as an entry; the real one uses '#'.
    assert ANCHOR.search(b"## Source - 2026-07\n")
    assert not ANCHOR.search(b"# Source - 2026-07\n")

    # A pointer from a PREVIOUS run must be stripped, or run 2 duplicates it /
    # rotates it as if it were provenance -- both conserve bytes and both are wrong.
    one = b"From the 2026-08-08 queue\n- a\n\nOlder: [[source-history-2026-07]]\n"
    assert OLD_POINTER.search(one), "single-archive pointer not recognised"
    assert OLD_POINTER.sub(b"", one) == b"From the 2026-08-08 queue\n- a\n"
    two = "x\n\nOlder: [[source-history-2026-07]] · [[source-history-2026-06]]\n".encode()
    assert OLD_POINTER.search(two), "multi-archive pointer not recognised"
    # ...but prose that merely mentions Older: mid-file is not a pointer.
    assert not OLD_POINTER.search(b"\nOlder: [[source-history-2026-07]]\nmore text\n")

    # An empty staying set is legitimate; entry_bytes must be 0, never negative.
    raw2 = b"From the 2026-07-31 queue\n- only old\n"
    _pre, r2, s2 = split(raw2, "2026-08")
    assert len(r2) == 1 and s2 == [], "everything should rotate"
    assert measure(b"---\nx\n---\n\nOlder: [[source-history-2026-07]]\n") == (0, 0, 0)

    # --- --extract mode ---------------------------------------------------
    raw3 = (b"---\nparent: x\n---\n"
            b"## Alpha trail (rotated 2026-08-06)\n- a\n\n"
            b"## Beta\n- b\n")
    pre3, n3, (s3, e3) = pick(raw3, b"## Alpha trail")
    assert (pre3, n3) == (18, 2)
    assert raw3[s3:e3] == b"## Alpha trail (rotated 2026-08-06)\n- a\n\n", "wrong span"
    # A middle section leaving must drop the anchor count by exactly one, so the
    # pointer that replaces it must NOT be anchor-shaped. `## Moved: ...` would
    # hold the count at 2 and hide that a section left.
    ptr = b"Moved: the Alpha trail section now lives in [[t]] (`_history/t.md`).\n\n"
    assert not ANCHOR.search(ptr), "pointer must not parse as an anchor"
    live3 = raw3[:s3] + ptr + raw3[e3:]
    assert measure(live3)[0] == n3 - 1, "anchor count must drop by one"
    assert live3[:s3] == raw3[:s3] and live3[s3 + len(ptr):] == raw3[e3:]
    # The reflow check must be able to FAIL -- a longest-line test that only ever
    # sees equal inputs is decoration.
    sec3 = raw3[s3:e3]
    assert max(len(l) for l in sec3.split(b'\n')) == 35
    reflowed = sec3.replace(b" (rotated 2026-08-06)", b"\n  (rotated 2026-08-06)")
    assert max(len(l) for l in reflowed.split(b'\n')) != 35, "reflow must change the longest line"
    # Ambiguity and typos exit rather than guessing.
    for bad in (b"## ", b"## Nope"):
        try:
            pick(raw3, bad)
        except SystemExit:
            pass
        else:
            assert False, f"pick({bad!r}) should have exited"

    print("selftest: helpers (anchor, dates, split, pointer) OK")
    # Each end-to-end suite announces itself. A lone "all assertions pass" is the
    # exact shape this batch kept getting wrong -- it reports that a run finished,
    # not which subjects were actually executed, and both real modes were invisible
    # in it (rotation because it had no suite at all).
    selftest_extract()
    print("selftest: --extract mode run end-to-end against a real git repo OK")
    selftest_rotate()
    print("selftest: rotation mode run end-to-end with --apply, plus its path refusals OK")
    print("selftest: all assertions pass")


def selftest_extract():
    """Actually RUNS extract(), against a throwaway git repo.

    The inline-expression assertions above could not have caught the longest-line
    bug -- they re-implemented the arithmetic instead of calling the function, so
    they agreed with themselves while extract() aborted every normal section as a
    phantom reflow. That is the third time in this batch a test that never
    exercised its subject hid a defect, so this one pays the cost of a real repo.
    """
    import tempfile, io, contextlib, shutil
    SEC = ("## Knowledge Map activity trail (rotated 2026-01-01)\n"
           "- a short line\n\n")
    tmp = tempfile.mkdtemp()
    cwd = os.getcwd()
    try:
        repo = os.path.join(tmp, "vault")
        proj = os.path.join(repo, "work", "projects", "Demo")
        os.makedirs(proj)
        shard = os.path.join(proj, "source-history.md")
        with open(shard, 'w') as f:
            f.write('---\ntags: [work]\ntype: synthesis\nlayer: work\n'
                    'project: Demo\nparent: "[[hub]]"\nupdated: 2026-01-01\n---\n'
                    '# Source\n\n'
                    '## 2026-01-02 ingest\n- stays\n\n' + SEC)
        declare_scopes(repo, "work")
        os.chdir(repo)
        for c in (["git", "init", "-q", "."], ["git", "config", "user.email", "t@t"],
                  ["git", "config", "user.name", "t"], ["git", "add", "-A"],
                  ["git", "commit", "-qm", "fixture"]):
            subprocess.run(c, check=True, capture_output=True)

        def run_ex(dest):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                extract(shard, "## Knowledge Map activity trail", dest, False)
            return buf.getvalue()

        def refused(label, dest):
            try:
                run_ex(dest)
            except SystemExit:
                return
            raise AssertionError(f"{label} was NOT refused")

        # (a) A NORMAL PROSE SECTION must pass. Its longest line is ~51 bytes while
        # the generated preamble is ~150, which is exactly the geometry that used
        # to abort -- and the assert below PROVES the fixture has that geometry,
        # so it cannot silently stop exercising the bug.
        out = run_ex(os.path.join(proj, "_history", "km-activity-trail.md"))
        n = int(re.search(r'N = (\d+)', out).group(1))
        longest = max(len(l) for l in SEC.encode().split(b'\n'))
        assert n > longest, f"fixture does not exercise the bug: N={n} <= {longest}"
        assert "FAIL" not in out, out
        assert f"source = {longest}, destination = {longest}" in out, out

        # (b) A SYMLINKED _history must be refused. abspath is string arithmetic
        # and does not resolve symlinks, so this landed OUTSIDE the repo entirely;
        # Rule F's verb list has no `ln`, so planting the link is unguarded.
        outside = os.path.join(tmp, "outside")
        os.makedirs(outside)
        os.symlink(outside, os.path.join(proj, "_history"))
        refused("symlinked _history", os.path.join(proj, "_history", "km.md"))
        os.unlink(os.path.join(proj, "_history"))

        # (c) traversal and absolute escapes
        refused("`..` traversal", os.path.join(proj, "_history", "..", "..", "evil.md"))
        refused("absolute path outside", os.path.join(tmp, "evil.md"))
        refused("sibling dir, not _history", os.path.join(proj, "evil.md"))

        # (d) THE SHARD is constrained too, not only the destination. The
        # destination is anchored relative to the shard, so an unconstrained shard
        # made the reachable set repo-wide and the "subset of Rule D's carve-out"
        # claim false outside work/.
        other = os.path.join(repo, "undeclared", "projects", "Demo")
        os.makedirs(other)
        oshard = os.path.join(other, "source-history.md")
        shutil.copy(shard, oshard)
        subprocess.run(["git", "add", "-A"], check=True, capture_output=True)
        subprocess.run(["git", "commit", "-qm", "other"], check=True, capture_output=True)
        try:
            extract(oshard, "## Knowledge Map activity trail",
                    os.path.join(other, "_history", "km.md"), False)
        except SystemExit:
            pass
        else:
            raise AssertionError("an undeclared scope shard was NOT refused")
    finally:
        os.chdir(cwd)
        shutil.rmtree(tmp, ignore_errors=True)


def selftest_rotate():
    """Actually RUNS the rotation mode, with --apply, against throwaway git repos.

    The mode that moved 145 KB of audit trail was the one mode never executed
    end-to-end: --selftest ran helpers in isolation plus selftest_extract(). So the
    main()-level path constraint would have shipped untested, which is how the
    missing constraint shipped in the first place -- form verified, effect not.

    Byte conservation is asserted against the fixture constants, NOT by reading the
    script's own printout. A tool that grades its own arithmetic and a test that
    reads the grade agree with each other and with nothing else.
    """
    import tempfile, io, contextlib, shutil
    today = datetime.date.today().isoformat()
    FM = ('---\ntags: [work]\ntype: synthesis\nlayer: work\n'
          'project: Demo\nparent: "[[hub]]"\nupdated: 2026-01-01\n---\n'
          '# Source\n\n')
    # A FIXED old month, never "last month": a relative fixture stops exercising
    # the split the moment the test runs on the 1st.
    OLD = b"## 2020-01-02 ingest\n- old entry\n\n"
    STAY = f"## {today} ingest\n- stays\n\n".encode()
    POINTER = b"\nOlder: [[source-history-2020-01]]\n"

    tmp = tempfile.mkdtemp()
    cwd = os.getcwd()

    def fixture(repo, layer_dir, body, git=True):
        declare_scopes(repo, "work")
        proj = os.path.join(repo, *layer_dir)
        os.makedirs(proj)
        shard = os.path.join(proj, "source-history.md")
        with open(shard, 'wb') as f:
            f.write(FM.encode() + body)
        os.chdir(repo)
        # git=False is not a convenience: EVERY fixture here used to git init, which
        # is exactly why the not-a-repo bypass survived the suite. The one situation
        # where the guard collapsed was the one situation no test constructed.
        if git:
            for c in (["git", "init", "-q", "."], ["git", "config", "user.email", "t@t"],
                      ["git", "config", "user.name", "t"], ["git", "add", "-A"],
                      ["git", "commit", "-qm", "fixture"]):
                subprocess.run(c, check=True, capture_output=True)
        return shard

    def refuse_unchanged(label, shard, want_msg=None):
        """Assert refusal AND that nothing on disk moved. Exiting is not enough --
        the bug being pinned wrote an archive and truncated the shard."""
        before = open(shard, 'rb').read()
        try:
            run_main(shard, "--apply")
        except SystemExit as e:
            # Pin WHY it refused. Without this the not-a-repo case could pass for an
            # incidental reason (a stray parent repo making rel fall outside scope)
            # and stop testing the fail-closed path it exists for.
            if want_msg:
                assert want_msg in str(e), f"{label} refused for the wrong reason: {e}"
        else:
            raise AssertionError(f"{label} was NOT refused")
        assert open(shard, 'rb').read() == before, f"{label}: shard bytes changed"
        assert not glob.glob(os.path.join(os.path.dirname(shard),
                                          "source-history-????-??.md")), \
            f"{label}: an archive was written despite refusal"

    def run_main(*argv):
        buf = io.StringIO()
        saved = sys.argv
        sys.argv = ["provenance-rotate.py", *argv]
        try:
            with contextlib.redirect_stdout(buf):
                main()
        finally:
            sys.argv = saved
        return buf.getvalue()

    try:
        # (a) A REAL ROTATION, --apply, end to end.
        r1 = os.path.join(tmp, "v1")
        shard = fixture(r1, ("work", "projects", "Demo"), OLD + STAY)
        out = run_main(shard, "--apply")
        for a in ("=== ASSERTION 1 - COUNT ===", "=== ASSERTION 2 - BYTES ===",
                  "=== ASSERTION 3 - CONTENT (sha256) ==="):
            assert a in out, f"{a} never ran:\n{out}"
        assert "FAIL" not in out, out
        assert "live shard truncated" in out, out
        archive = os.path.join(os.path.dirname(shard), "source-history-2020-01.md")
        arch = open(archive, 'rb').read()
        live = open(shard, 'rb').read()
        # Conservation, byte-exact and independent of the script's own printout.
        assert arch[arch.index(b"## "):] == OLD, "archive is not the rotated bytes"
        assert live == FM.encode() + STAY + POINTER, "live shard is not preamble+stay+pointer"
        assert OLD not in live and STAY not in arch, "entry landed on both sides"

        # (b) THE EMPTY STAYING SET, which until now had only a manual trace: every
        # entry rotates, measure() finds no anchors, and entry_bytes must be 0 --
        # the branch that once went NEGATIVE and cried byte loss on the one alarm
        # the skill says to stop and `git checkout` for.
        r2 = os.path.join(tmp, "v2")
        shard2 = fixture(r2, ("work", "notes", "Demo"), OLD)
        out2 = run_main(shard2, "--apply")
        assert "FAIL" not in out2, out2
        assert "entry_bytes=0" in out2, out2
        assert open(shard2, 'rb').read() == FM.encode() + POINTER, "empty-stay shard wrong"

        # (c) THE PATH CONSTRAINT, in ROTATION mode. This is the one that had no
        # test and no check: rotation truncates, and every git-clean anchor-bearing
        # .md in the vault was reachable -- including the Rule A sources trees the
        # write guard declares immutable.
        for layer in (("work", "sources", "Demo"), ("undeclared", "projects", "Demo"),
                      ("private", "Demo"), ("work", "content", "Demo")):
            rn = os.path.join(tmp, "x-" + "-".join(layer))
            refuse_unchanged("/".join(layer),
                             fixture(rn, layer, OLD + STAY),
                             "scope is <scope>/projects/ or <scope>/notes/")

        # (d) NOT A GIT REPO AT ALL. `git rev-parse` errors, stdout is empty, and
        # realpath("") used to hand back the CURRENT DIRECTORY as the repo root --
        # so a plain temp dir merely SHAPED like work/projects/<X>/ passed the scope
        # check and was rotated for real. The path is in scope by name here, which
        # is the point: only the fail-closed root check can refuse it.
        refuse_unchanged("not a git repo",
                         fixture(os.path.join(tmp, "nogit"), ("work", "projects", "Demo"),
                                 OLD + STAY, git=False),
                         "cannot establish a git repository root")
    finally:
        os.chdir(cwd)
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--selftest":
        return selftest()
    shard = sys.argv[1]
    apply_ = "--apply" in sys.argv[2:]
    # BEFORE EITHER MODE OPENS THE FILE. Rotation used to reach any git-clean
    # anchor-bearing .md in the vault and truncate it; see rel_in_scope().
    rel_in_scope(shard)
    if "--extract" in sys.argv:
        i = sys.argv.index("--extract")
        if len(sys.argv) < i + 3:
            sys.exit("--extract needs a heading prefix and a destination path")
        return extract(shard, sys.argv[i + 1], sys.argv[i + 2], apply_)
    root = os.path.dirname(shard)
    today = datetime.date.today().isoformat()
    cur_month = today[:7]

    disk = open(shard, 'rb').read()

    # STRIP ANY EXISTING POINTER FIRST. The `Older:` line sits at the end of the
    # file, which is inside the LAST entry's span -- so on a second run it counts
    # as entry bytes and gets duplicated in the live shard, or rotated into an
    # archive as if it were provenance. Both conserve bytes perfectly and both are
    # wrong, which is why this is stripped rather than checked for. The skill's
    # monthly trigger guarantees a second run.
    m = OLD_POINTER.search(disk)
    prev_pointer = m.group(0) if m else b""
    raw = disk[:m.start()] if m else disk

    preamble, rot, stay = split(raw, cur_month)
    before_anchors = len(rot) + len(stay)
    before_bytes = len(raw) - preamble

    if not rot:
        print("nothing older than the current month; nothing to do.")
        return

    # One archive per run. Rotate the OLDEST old month and leave the rest in
    # place; re-running drains them one at a time. Refusing outright used to be
    # the behaviour, but it told the operator to "rotate the oldest month first"
    # with no flag to do that -- an instruction the tool did not implement.
    months = sorted({entry_date(raw, s, e)[:7] for s, e in rot})
    month = months[0]
    if len(months) > 1:
        keep = [se for se in rot if entry_date(raw, *se)[:7] != month]
        rot = [se for se in rot if entry_date(raw, *se)[:7] == month]
        stay = sorted(stay + keep)
        print(f"note: {len(months)} old months present {months}; rotating {month} only. "
              f"Re-run to drain the next one.")

    rot_bytes = b"".join(raw[s:e] for s, e in rot)
    stay_bytes = b"".join(raw[s:e] for s, e in stay)
    sha_rot = hashlib.sha256(rot_bytes).hexdigest()
    archive_path = os.path.join(root, f"source-history-{month}.md")
    if os.path.exists(archive_path):
        sys.exit(f"{archive_path} already exists; refusing to overwrite an archive")

    # Archive preamble: the parent's six frontmatter fields VERBATIM plus a
    # title carrying the rotation date. Single '#' deliberately -- '## ' is an
    # anchor prefix, and a '##' title would inflate the archive's anchor count.
    fm = raw[:preamble].decode()
    fields = {k: v for k, v in
              (l.split(": ", 1) for l in fm.splitlines() if ": " in l)}
    arch_preamble = ("---\n" + "".join(
        f"{k}: {fields[k]}\n" for k in
        ("tags", "type", "layer", "project", "parent", "updated") if k in fields)
        + "---\n"
        + f"# Source — {month} (archived by provenance rotation {today})\n\n"
    ).encode()
    if ANCHOR.search(arch_preamble):
        sys.exit("archive preamble contains an anchor-matching line; would corrupt the count")
    N = len(arch_preamble)
    archive = arch_preamble + rot_bytes

    # Live shard: preamble + staying entries BYTE-IDENTICAL, then the pointer.
    # The pointer is a DECLARED byte delta -- it is deliberately excluded from
    # the entry-body accounting below, never silently absorbed into it.
    existing = sorted(glob.glob(os.path.join(root, "source-history-????-??.md")) + [archive_path],
                      reverse=True)
    pointer = ("\nOlder: " + " · ".join(
        f"[[{os.path.basename(p)[:-3]}]]" for p in existing) + "\n").encode()
    live = raw[:preamble] + stay_bytes + pointer

    # ---- the three-part conservation proof --------------------------------
    la, lp, lb = measure(live)
    aa, ap, ab = measure(archive)
    # An EMPTY staying set is legitimate (a month with no ingests yet, or a run
    # on the 1st): every entry rotates and the live shard becomes preamble +
    # pointer. measure() then finds no anchors and returns zeros, and blindly
    # subtracting the pointer drove entry_bytes NEGATIVE -- reporting byte loss
    # that had not happened, on the one alarm the skill says to stop and
    # `git checkout` for. A false conservation failure is worse than no check:
    # it teaches the operator to distrust the real one.
    if la:
        lb -= len(pointer)                    # pointer sits inside the last span
    else:
        lp, lb = preamble, 0                  # nothing left but preamble + pointer
    a1 = (la + aa) == before_anchors
    a2 = (lb + ab) == before_bytes
    a3 = hashlib.sha256(archive[ap:]).hexdigest() == sha_rot
    a2b = hashlib.sha256(live[lp:len(live) - len(pointer)]).hexdigest() == \
        hashlib.sha256(stay_bytes).hexdigest()

    print(f"shard            : {shard}")
    print(f"archive          : {archive_path}")
    print(f"archive preamble : N = {N} (first anchor at {ap} -> {N == ap})")
    print(f"pointer line     : {len(pointer)} bytes  {pointer!r}")
    print(f"pointer stripped : {len(prev_pointer)} bytes "
          f"{'(none -- first rotation)' if not prev_pointer else repr(prev_pointer)}")
    print()
    print(f"live    : anchors={la} preamble={lp} entry_bytes={lb} (+{len(pointer)} pointer) file={len(live)}")
    print(f"archive : anchors={aa} preamble={ap} entry_bytes={ab} file={len(archive)}")
    print()
    print("=== ASSERTION 1 - COUNT ===")
    print(f"  {la} + {aa} = {la+aa} (want {before_anchors})  -> {'PASS' if a1 else 'FAIL'}")
    print("=== ASSERTION 2 - BYTES ===")
    print(f"  {lb} + {ab} = {lb+ab} (want {before_bytes})  delta={lb+ab-before_bytes}"
          f"  -> {'PASS' if a2 else 'FAIL'}")
    print(f"  live file = {len(live)} = {lp+lb} + {len(pointer)} pointer"
          f"  -> {'PASS' if a2b else 'FAIL'} (staying bytes identical)")
    print("=== ASSERTION 3 - CONTENT (sha256) ===")
    print(f"  rotated spans, pre-move    = {sha_rot}")
    print(f"  archive minus its preamble = {hashlib.sha256(archive[ap:]).hexdigest()}")
    print(f"  -> {'PASS' if a3 else 'FAIL'}")

    if not (a1 and a2 and a3 and a2b):
        sys.exit("\nCONSERVATION FAILED -- nothing written.")
    print(f"\nall assertions pass: {len(rot)} entries / {len(rot_bytes)} bytes rotate, "
          f"{len(stay)} / {len(stay_bytes)} stay")
    if not apply_:
        print("dry run; pass --apply to perform the move.")
        return

    # Same fail-closed rule as rel_in_scope(): an empty stdout from a git command
    # that ERRORED is not a clean tree, it is an unanswered question. Untested this
    # reads as "nothing dirty" and the truncation proceeds -- the recoverability
    # this precondition exists to guarantee (`git checkout` gets the bytes back)
    # would not exist. rel_in_scope() already refuses outside a repo, so this is
    # defence in depth rather than the only net; it is still the correct shape.
    st = subprocess.run(["git", "status", "--porcelain", "--", shard],
                        capture_output=True, text=True)
    if st.returncode != 0:
        sys.exit(f"cannot determine whether {shard} is clean "
                 f"(git status failed: {st.stderr.strip() or 'no output'}). "
                 f"Refusing rather than assuming clean: this precondition is what "
                 f"makes the truncation recoverable with git checkout.")
    if st.stdout.strip():
        sys.exit(f"{shard} has uncommitted changes; commit or stash first so the "
                 f"move stays recoverable with git checkout")

    # Archive FIRST, re-read and verify from disk, and only then truncate.
    with open(archive_path, 'wb') as f:
        f.write(archive)
    back = open(archive_path, 'rb').read()
    if back != archive or hashlib.sha256(back[N:]).hexdigest() != sha_rot:
        os.unlink(archive_path)
        sys.exit("archive failed verification after write; removed it, live shard untouched")
    print(f"archive written and verified from disk: {archive_path}")

    with open(shard, 'wb') as f:
        f.write(live)
    print(f"live shard truncated: {shard} -> {len(live)} bytes")


if __name__ == "__main__":
    main()
