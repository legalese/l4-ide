#!/usr/bin/env python3
"""Quote a source text, and check that an encoding's quotations and `@ref` locators agree with it.

  python3 -I srcrefs.py quote RAW N [M]         print `-- src:N | <line N>` (through M), ready to paste
  python3 -I srcrefs.py quoteid RAW N [M]       the same, as `-- src:ID:N | ...`, ID being RAW's stem
  python3 -I srcrefs.py check [--refs | --strict] RAW FILE...
                                                verify the quotations (and with --refs the locators) in FILE...

RAW is a plain-text rendering of the source (for a PDF, `pdftotext -layout`).
`src:N` always means line N of RAW, counting from 1 and splitting on "\\n" only.
`quote` prints each line with its whitespace squeezed to single spaces and in NFC, and leaves out raw lines that are blank;
the line numbers it prints are still the raw file's own.

Vocabulary.

  quote line   `-- src:N | text`, `-- src:N-M | text`, `-- src:ID:N | text` or `-- src:ID:N-M | text`.
               ID is the stem of another raw file in RAW's own directory (ID.txt).
  locator      `src:N`, `src:N-M`, `src:ID:N` or `src:ID:N-M` (N <= M, ID matching [A-Za-z][\\w.-]*)
               written anywhere in the text of an `@ref` annotation, e.g. `@ref Dieu 35 (src:760-769)`.
               A locator anywhere else is ignored.
  @ref         what L4's lexer reads as one: `@ref` (not `@ref-src` or `@ref-map`) or `<<...>>`, outside a comment
               and outside a string. `@ref(src:1)` and `@reference src:1` are therefore `@ref`s too, as they are to L4.
  run          a maximal sequence of consecutive quote lines; blank lines do not break a run,
               any other line (an `@ref`, a plain comment, a declaration) does.
  block        the lines from one line of code to the next that are only quote lines, comments, blank lines and `@ref`s:
               what sits above a declaration. A block ends at the next line of code (a declaration, a `§` heading,
               a `#ASSERT`, ...) or at the end of the file.

What `check` enforces (exit 1 if any problem; each is printed as `file:line: reason`):

  R1  (always)      Every quote line is a verbatim slice of the raw lines it names, and says so about real lines:
                    1 <= N <= M <= the number of lines in the raw file, and there is some text in it.
                    Comparison: NFC, case-folded, punctuation and whitespace collapsed, and the quotation must start
                    and end at a word boundary of the raw lines (`1 ngay` is not a slice of `21 ngay`). A trailing
                    ellipsis (`…` or `...`) means the quotation was cut short: it may then stop inside a word.
                    An ID with no ID.txt beside RAW is a problem.
  R2  (with --refs) Every locator lies inside the quoted ranges of the same file: both N and M must be covered
                    by some quote line of the same ID in that file. Gaps inside the range are allowed. A locator with
                    N > M, a malformed `src:` token (also a range written with a dash that is not `-`, with `..`, or a
                    list with `,`), an ID with no ID.txt, or a line number past the end of the raw file is also a problem.
  R3  (with --refs) Every run of quote lines is overlapped by at least one locator in the same file with the same ID,
                    otherwise "orphan quotation". A run that mixes IDs needs one locator per ID it quotes.
                    A run whose block ends in a `§` heading, a `#` directive or the end of the file is exempt:
                    the convention puts no `@ref` before those.
  --strict          (implies --refs) For a row whose `@ref`s are generated, or kept to the convention by hand.
                    R2 and R3 then look only at the block: a locator must be covered by the runs above it in its own block
                    (an `@ref` with none, a later declaration citing the same run, is governed by the nearest run above
                    it), and a run needs an overlapping locator on an `@ref` in its own block below it. A wide locator
                    elsewhere in the file no longer covers it. Also, in every block that is not exempt, the `@ref`s
                    must reach exactly the lowest and the highest raw line that the block's runs quote, for each ID:
                    a locator narrowed or shifted by one line is a problem. A first `@ref` that is deliberately narrower
                    than its run is a problem too.

The summary line counts quote lines, runs, locators and problems. Without --refs, locators are counted
but not checked.

What it does not check: that a locator names the right provision (a wrong but covered range passes),
that the `@ref` sits above the right declaration, that a run quotes every raw line inside its locator,
or that the encoding is right.
"""
import bisect
import os
import re
import sys
import unicodedata

# R1's marker and normalisation are inherited from the single-purpose gate this tool generalises (vnsrc.py rule 1).
SRC_LINE = re.compile(r"--\s*src:(?:([A-Za-z][\w.-]*):)?(\d+)(?:-(\d+))?\s*\|\s*(.*)$")
ELLIPSIS = re.compile(r"(…|\.\.\.)\s*$")

# The annotation heralds, in the order L4's lexer tries them (jl4-core/src/L4/Lexer.hs, annotationsPayload).
# Each takes the rest of its line. Only `@ref` is a citation; `@ref-src` and `@ref-map` merely begin with it.
HERALD = re.compile(r"@(?:ref-src|ref-map|lang|desc|export|infixl|infixr|infix|nonexhaustive|nlg|ref)")
# What may follow a block that takes no `@ref` before it.
UNREFERENCED_TERMINATOR = re.compile(r"\s*(?:§|#[A-Za-z])")

# Every place a locator might have been meant: `src:` not glued to a preceding word character.
SRC_TOKEN = re.compile(r"(?<!\w)src:")
# One locator; it must not run on into a word character, or into `-` or `:` plus a word character.
LOCATOR = re.compile(r"src:(?:([A-Za-z][\w.-]*):)?([0-9]+)(?:-([0-9]+))?(?!\w|[-:]\w)")
# What a well-formed locator must not be followed by: the author meant a range or a list, and the grammar has neither.
# Without this, `src:1–5` (en dash), `src:1..5`, `src:1 - 5` and `src:1,5` would be read as the single line `src:1`.
RANGE_TRAILER = re.compile(r"\s*[–—‒―−]\s*(?=\d)|\.\.\s*(?=\d)|\s+-\s*(?=\d)|,(?=\d)")


def nfc(s):
    return unicodedata.normalize("NFC", s)


def norm(s):
    s = nfc(s).casefold()
    s = re.sub(r"[^\w]+", " ", s, flags=re.UNICODE)
    return re.sub(r"\s+", " ", s).strip()


def load(path):
    # newline="": a lone "\r" is not a line break here, whatever the platform; the docstring says "\n" only.
    with open(path, encoding="utf-8", newline="") as f:
        return f.read().split("\n")


def line_count(lines):
    """Lines in a file as `load` returns it: a final empty element is just the trailing newline."""
    return len(lines) - 1 if lines and lines[-1] == "" else len(lines)


def locators_in(text):
    """Return (locators, malformed) for the text of one `@ref`.

    Each locator is (id_or_None, n, m, matched_text); malformed is a list of the offending snippets.
    """
    found, malformed = [], []
    for tok in SRC_TOKEN.finditer(text):
        m = LOCATOR.match(text, tok.start())
        if m:
            trailer = RANGE_TRAILER.match(text, m.end())
            if trailer:
                digits = re.compile(r"[0-9]+").match(text, trailer.end())
                malformed.append(text[tok.start() : digits.end()])
                continue
            n = int(m.group(2))
            found.append((m.group(1), n, int(m.group(3)) if m.group(3) else n, m.group(0)))
            continue
        rest = text[tok.end():]
        # `src:5-x` and `src:x` were meant as locators; `src: 760` too; `src: lines` is prose.
        if rest and (not rest[0].isspace() or re.match(r"\s+[0-9]", rest)):
            malformed.append(re.match(r"src:\s*\S+", text[tok.start():]).group(0))
    return found, malformed


def scan_line(line, stack):
    """Read one line of an L4 file as far as this tool needs, the way L4's lexer would.

    `stack` holds the closers of the block comments (`{- -}`, `/* */`, which nest) still open at the start of the line;
    it is updated. Returns (code, refs): `code` is True if the line has anything that is not blank, not inside a comment
    and not an `@ref`; `refs` is the list of texts of the `@ref` / `<<...>>` annotations on the line.
    A comment, a string (`"..."`) and a backtick name hide everything inside them, an `@ref` included.
    """
    code, refs = False, []
    i, n = 0, len(line)
    while i < n:
        if stack:
            if line.startswith("{-", i):
                stack.append("-}")
                i += 2
            elif line.startswith("/*", i):
                stack.append("*/")
                i += 2
            elif line.startswith(stack[-1], i):
                stack.pop()
                i += 2
            else:
                i += 1
        elif line[i].isspace():
            i += 1
        elif line.startswith("--", i) or line.startswith("//", i):
            break
        elif line.startswith("{-", i):
            stack.append("-}")
            i += 2
        elif line.startswith("/*", i):
            stack.append("*/")
            i += 2
        elif line[i] == "@" and HERALD.match(line, i):
            if HERALD.match(line, i).group(0) == "@ref":
                refs.append(line[i:])
            else:
                code = True
            break
        elif line.startswith("<<", i):
            j = line.find(">>", i + 2)
            refs.append(line[i + 2 : j if j >= 0 else n])
            i = n if j < 0 else j + 2
        elif line[i] in "\"`":
            q, j = line[i], i + 1
            while j < n and line[j] != q:
                j += 2 if line[j] == "\\" and q == '"' else 1
            code = True
            i = j + 1
        else:
            code = True
            i += 1
    return code, refs


class Raws:
    """The raw files a check reads: RAW itself, and `ID.txt` beside it, loaded on first use."""

    def __init__(self, rawpath):
        self.here = os.path.dirname(os.path.abspath(rawpath))
        self.cache = {None: load(rawpath)}

    def get(self, ident):
        """The lines of the raw file for `ident` (None names RAW), or None if there is no such file."""
        if ident not in self.cache:
            cand = os.path.join(self.here, ident + ".txt")
            try:
                self.cache[ident] = load(cand) if os.path.isfile(cand) else None
            except (OSError, UnicodeDecodeError):
                self.cache[ident] = None
        return self.cache[ident]

    def window(self, ident, a, b):
        """The normalised text of lines a..b of the raw file, padded with a space on each side.

        There is no such text unless 1 <= a <= b (a negative start would otherwise count from the end).
        """
        lines = self.get(ident)[a - 1 : b] if 1 <= a <= b else []
        return " " + norm(" ".join(lines)) + " "


class Intervals:
    """The union of closed integer intervals, answering "is x inside one of them?"."""

    def __init__(self, spans):
        merged = []
        for a, b in sorted(spans):
            if merged and a <= merged[-1][1] + 1:
                merged[-1][1] = max(merged[-1][1], b)
            else:
                merged.append([a, b])
        self.starts = [a for a, _ in merged]
        self.ends = [b for _, b in merged]

    def covers(self, x):
        i = bisect.bisect_right(self.starts, x) - 1
        return i >= 0 and x <= self.ends[i]


class Scan:
    """What a file holds, as the gate sees it.

    quotes   [(line number, id, a, b, body)] for every quote line
    runs     [(indexes into quotes, block, last line number)] in file order
    refs     [(line number, text, block, on_code)] for every `@ref` annotation; on_code is True if code shares its line
    ends     ends[k] is the first line of the code that ends block k, or None for the end of the file
    """

    def __init__(self, lines):
        self.quotes, self.runs, self.refs, self.ends = [], [], [], []
        stack, block, in_run = [], 0, False
        for ln, line in enumerate(lines, 1):
            code, found = scan_line(line, stack)
            quote = None if found else SRC_LINE.search(line)
            if quote:
                if not in_run:
                    self.runs.append([[], block, ln])
                    in_run = True
                a = int(quote.group(2))
                self.runs[-1][0].append(len(self.quotes))
                self.runs[-1][2] = ln
                self.quotes.append((ln, quote.group(1), a, int(quote.group(3) or a), quote.group(4)))
                continue
            if found:
                in_run = False
                self.refs.extend((ln, text, block, code) for text in found)
            elif line.strip():
                in_run = False
            if code:
                self.ends.append(line.strip())
                block += 1
        self.ends.append(None)

    def exempt(self, block):
        """A block that takes no `@ref` before it: it ends in a `§` heading, a `#` directive or the end of the file."""
        end = self.ends[block]
        return end is None or bool(UNREFERENCED_TERMINATOR.match(end))


def check_file(path, raws, refs, strict=False):
    """Check one file. Returns (problems, quote_lines, runs, locators); problems are (line, reason)."""
    problems = []
    try:
        lines = load(path)
    except (OSError, UnicodeDecodeError) as e:
        return [(0, f"cannot read file: {e}")], 0, 0, 0
    scan = Scan(lines)

    for ln, ident, a, b, body in scan.quotes:
        tag = f"{ident}:" if ident else ""
        src = raws.get(ident)
        if src is None:
            problems.append((ln, f"src:{tag}{a} names no raw file {ident}.txt"))
            continue
        span = f"src:{tag}{a}-{b}"
        if a < 1:
            problems.append((ln, f"{span} line numbers start at 1"))
        elif a > b:
            problems.append((ln, f"{span} N > M"))
        elif b > line_count(src):
            where = f"{ident}.txt" if ident else "the raw file"
            problems.append((ln, f"{span} past the end of {where} ({line_count(src)} lines)"))
        else:
            cut = ELLIPSIS.search(body)
            nb = norm(ELLIPSIS.sub("", body))
            if not nb:
                problems.append((ln, f"{span} quotation has no text"))
            elif (" " + nb if cut else " " + nb + " ") not in raws.window(ident, a, b):
                problems.append((ln, f"{span} quotation is not a slice of those lines"))

    locs = []  # (line number, id, n, m, matched text, block, on_code) for every well-formed locator
    for ln, text, block, on_code in scan.refs:
        found, malformed = locators_in(text)
        locs.extend((ln, ident, n, m, matched, block, on_code) for ident, n, m, matched in found)
        if refs:
            problems.extend((ln, f"malformed locator {snippet!r}: write src:N, src:N-M, src:ID:N or src:ID:N-M")
                            for snippet in malformed)

    if refs:
        problems.extend(check_refs(scan, locs, raws, strict))
    problems.sort(key=lambda p: p[0])
    return problems, len(scan.quotes), len(scan.runs), len(locs)


def spans_of(scan, run):
    """The quoted raw-line spans of one run, by ID (spans with N > M are not quotations of anything)."""
    by_id = {}
    for qi in run[0]:
        _, ident, a, b, _ = scan.quotes[qi]
        if a <= b:
            by_id.setdefault(ident, []).append((a, b))
    return by_id


def check_refs(scan, locs, raws, strict=False):
    """R2 and R3 over one file; with `strict`, the block-local versions and the exactness rule."""
    problems = []
    run_spans = [spans_of(scan, run) for run in scan.runs]
    pooled = {}
    for spans in run_spans:
        for ident, sp in spans.items():
            pooled.setdefault(ident, []).extend(sp)
    covered = {ident: Intervals(sp) for ident, sp in pooled.items()}

    # R2. Strictly, a locator is checked against the runs that govern it: those above it in its own block, else the nearest above it.
    for ln, ident, n, m, text, block, on_code in locs:
        src = raws.get(ident)
        if n > m:
            problems.append((ln, f"{text}: N > M"))
        elif src is None:
            problems.append((ln, f"{text} names no raw file {ident}.txt"))
        elif n < 1:
            problems.append((ln, f"{text}: raw line numbers start at 1"))
        elif m > line_count(src):
            where = f"{ident}.txt" if ident else "the raw file"
            problems.append((ln, f"{text}: past the end of {where} ({line_count(src)} lines)"))
        else:
            if strict:
                above = [k for k, run in enumerate(scan.runs) if run[1] == block and run[2] < ln]
                if not above:
                    above = [k for k, run in enumerate(scan.runs) if run[2] < ln][-1:]
                cov = Intervals([sp for k in above for sp in run_spans[k].get(ident, ())])
                by = "the quote lines it follows"
            else:
                cov = covered.get(ident)
                by = "any quote line in this file"
            missing = [x for x in dict.fromkeys((n, m)) if not (cov and cov.covers(x))]
            if missing:
                which = " and ".join(str(x) for x in missing)
                problems.append((ln, f"{text}: line {which} not covered by {by}" + (f" with ID {ident}" if ident else "")))

    # R3. Strictly, the overlapping locator must be on an `@ref` in the run's own block below it. A run whose block takes no `@ref` is exempt.
    for k, run in enumerate(scan.runs):
        if scan.exempt(run[1]):
            continue
        for ident, spans in run_spans[k].items():
            if strict:
                mine = [(n, m) for ln, lid, n, m, _, block, on_code in locs
                        if block == run[1] and ln > run[2] and not on_code and lid == ident and n <= m]
            else:
                mine = [(n, m) for _, lid, n, m, _, _, _ in locs if lid == ident and n <= m]
            if not any(n <= b and m >= a for n, m in mine for a, b in spans):
                first_ln = next(scan.quotes[qi][0] for qi in run[0] if scan.quotes[qi][1] == ident)
                lo, hi = min(a for a, _ in spans), max(b for _, b in spans)
                tag = f"{ident}:" if ident else ""
                span = f"{lo}" if lo == hi else f"{lo}-{hi}"
                problems.append((first_ln, f"orphan quotation: no @ref locator overlaps src:{tag}{span}"))

    if strict:
        problems.extend(check_exact(scan, run_spans, locs))
    return problems


def check_exact(scan, run_spans, locs):
    """--strict: per block and ID, the `@ref`s of the block reach exactly the lowest and highest raw line its runs quote."""
    problems = []
    want = {}  # (block, id) -> [lowest, highest, first run]
    for k, run in enumerate(scan.runs):
        if scan.exempt(run[1]):
            continue
        for ident, spans in run_spans[k].items():
            lo, hi = min(a for a, _ in spans), max(b for _, b in spans)
            entry = want.setdefault((run[1], ident), [lo, hi, run])
            entry[0], entry[1] = min(entry[0], lo), max(entry[1], hi)
    for (block, ident), (lo, hi, first) in sorted(want.items(), key=lambda kv: kv[1][2][2]):
        mine = [(n, m) for ln, lid, n, m, _, b, on_code in locs
                if b == block and lid == ident and not on_code and n <= m and ln > first[2]]
        if not mine:
            continue  # R3 has already reported the orphan
        got_lo, got_hi = min(n for n, _ in mine), max(m for _, m in mine)
        if (got_lo, got_hi) != (lo, hi):
            first_ln = next(scan.quotes[qi][0] for qi in first[0] if scan.quotes[qi][1] == ident)
            tag = f"{ident}:" if ident else ""
            problems.append((first_ln, f"not exact: the run quotes src:{tag}{lo}-{hi} but its @ref locators reach src:{tag}{got_lo}-{got_hi}"))
    return problems


def cmd_check(args):
    strict = "--strict" in args
    refs = "--refs" in args or strict
    args = [a for a in args if a not in ("--refs", "--strict")]
    flags = [a for a in args if a.startswith("--")]
    if flags or len(args) < 2:
        print("srcrefs check: " + (f"unknown option {flags[0]}" if flags else "needs RAW and at least one FILE"), file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 2
    try:
        raws = Raws(args[0])
    except (OSError, UnicodeDecodeError) as e:
        print(f"srcrefs check: cannot read RAW {args[0]}: {e}", file=sys.stderr)
        return 2
    bad = nsrc = nruns = nlocs = 0
    for path in args[1:]:
        problems, s, r, l = check_file(path, raws, refs, strict)
        nsrc, nruns, nlocs = nsrc + s, nruns + r, nlocs + l
        for ln, why in problems:
            print(f"{path}:{ln}: {why}")
        bad += len(problems)
    print(f"srcrefs check: {nsrc} src: lines, {nruns} runs, {nlocs} locators, {bad} problems")
    return 1 if bad else 0


def cmd_quote(args, qualified=False):
    if len(args) not in (2, 3) or not all(re.fullmatch(r"[0-9]+", a) for a in args[1:]):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        raw = load(args[0])
    except (OSError, UnicodeDecodeError) as e:
        print(f"srcrefs: cannot read {args[0]}: {e}", file=sys.stderr)
        return 2
    n = int(args[1])
    m = int(args[2]) if len(args) > 2 else n
    if n < 1 or m < n or m > line_count(raw):
        print(f"srcrefs: lines {n}-{m} are not inside {args[0]} (lines 1-{line_count(raw)}, N <= M)", file=sys.stderr)
        return 1
    tag = os.path.splitext(os.path.basename(args[0]))[0] + ":" if qualified else ""
    for k in range(n, m + 1):
        t = re.sub(r"\s+", " ", nfc(raw[k - 1])).strip()
        if t:
            print(f"-- src:{tag}{k} | {t}")
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) < 2 or argv[0] not in ("quote", "quoteid", "check"):
        print(__doc__)
        return 2
    if argv[0] == "check":
        return cmd_check(argv[1:])
    return cmd_quote(argv[1:], qualified=argv[0] == "quoteid")


if __name__ == "__main__":
    sys.exit(main())
