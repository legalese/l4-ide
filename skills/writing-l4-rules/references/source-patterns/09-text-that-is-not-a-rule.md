# 9. Text that is not a rule

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

**The question that settles every entry here.** Of each passage, ask: _does it gate any decision, or
compute any value?_ If no, it is inert. Do not force it into a `DECIDE` and do not make it an input —
there is no proposition to decide and no fact anyone can be asked. Do not drop it either, or the
encoding stops being checkable line by line against the source. Carry it.

**Two places inert text can live, and they are not interchangeable.**

- **Text attached to a rule** — a chapeau, a paragraph label, a note on a limb — rides _inside_ the
  rule, as a string literal joined to its limb by the `...` continuation token. Entries 9.5 and 9.6.
- **Text attached to nothing** — the recital block a contract opens with, headed **"WHEREAS"**; a
  purpose clause; a prose Schedule; the boilerplate at the back — lives in its own definition,
  outside every rule. Entries 9.2, 9.3, 9.7, 9.8. For anything with numbered sub-paragraphs, that
  means the `hierarchy` library's outlines.

The distinction has a measured edge. A **string literal** written in place is inert in a boolean
chain: the parser accepts it and it contributes nothing (`AND` sees `TRUE`, `OR` sees `FALSE`). A
**name bound to a string** is not: it is a `STRING`, and using it as a limb is a type error. Entry
9.3 quotes it.

**`IMPORT hierarchy` — the library this area runs on, and the one the index leaves out.** Outlines
come from a library called `hierarchy`, and every snippet below that builds one opens with
`IMPORT hierarchy`. It is **not listed** in the library table in [builtins.md](../builtins.md), and
it is not in the parenthetical list of libraries in `SKILL.md`; both are short by it, and a reader
who trusts either will write a numbered recital as a flat string. It ships, in
`jl4-core/libraries/hierarchy.l4`, and these are the names it gives you:

| name                                                                          | what it is                                                                                     |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `item "text"`                                                                 | one node. Children follow as `•`-led `item`s, or as an explicit `LIST` for wide fan-out        |
| `labeled "2b" "text"`, `numbered "2b" "text"`                                 | pin an irregular marker — `labeled` without disturbing the siblings' count, `numbered` with it |
| `restartAt 7 "text"`                                                          | resume auto-numbering from a chosen value                                                      |
| `Decimal`, `UpperAlpha`, `LowerAlpha`, `UpperRoman`, `LowerRoman`, `Bulleted` | the six `NumberStyle` constructors — the whole set                                             |
| `` `default scheme` ``                                                        | the conventional legal cascade, `LIST Decimal, UpperAlpha, LowerRoman, LowerAlpha`             |
| `` `render outline` scheme root ``                                            | the whole document as a `LIST OF STRING`, one `"<dotted path>\t<text>"` per node               |
| `` `marker for` style n ``, `` `count nodes` t ``, `depth t`, `flatten t`     | the pieces, for a projection that needs them separately                                        |

`hierarchy` opens with its own `IMPORT prelude`, so a file that imports it gets `LIST`, `map`,
`elem` and the rest as well. A file that imports **nothing** does not: `sum` in a bare file is
`I could not find a definition for the identifier / sum` (probe `r5b-no-prelude-import.l4`, exit 1),
so write `IMPORT prelude` whenever you use a prelude name and no other library has pulled it in.

<a id="e9-1"></a>

## 9.1 "[Repealed]" — a section number with nothing under it

**If the source says** a gap in the numbering in the version in force.

**It is doing** nothing at all — which is the difficulty. "A reader who finds s 33 and then s 35
cannot otherwise tell whether s 34 was overlooked or is not there to be encoded"
(`jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2242-2246`).

**Write** a labelled stub carrying the repeal note as inert prose, with **no operative outcome** —
nothing calls it.

```l4
`ss 34 and 36 — repealed, and therefore not encoded` MEANS
        "34. [Repealed by Act 27 of 2014]"
    ... "36. [Repealed by Act 27 of 2014]"
```

**Not** a refusal. There is no question it declines to answer, because no rule reaches it — this is
documentation with a section number.

**See** [drafting-patterns.md](../drafting-patterns.md), "Repealed / omitted provision → a labelled
stub".

<a id="e9-2"></a>

## 9.2 "WHEREAS:", "The parties wish to record" — recitals

**If the source says**

> Recitals, preambles, "WHEREAS" clauses, purpose statements, statements of principle — the
> throat-clearing at the start of a chapter — gate no decision and compute nothing.
>
> — the user manual's own statement of the problem, at
> `doc/tutorials/getting-started/encoding-legislation.md:394-396` ("Carry Inert Text"). The
> fictional consultancy recitals it then encodes are at `:410-417`, under an `item "RECITALS"`
> root; the six `item` strings in the snippet below are its `:412-417` verbatim. No instrument
> under `jl4/examples/legal/` opens with recitals, so the "WHEREAS:" heading below is drafted,
> not quoted.

**It is doing** setting the scene. Recitals state why the parties are contracting and what they
believed at signature. They can bear on construction if the operative clauses turn out ambiguous,
but they confer nothing and require nothing, and no rule reads them.

**Write** a `hierarchy` outline. `item "…"` wraps one paragraph; `•` children nest under it to any
depth with no `LIST` literal and no parentheses; you choose a numbering style per level and the
renderer assigns the markers.

```l4
IMPORT hierarchy

@ref Consultancy Agreement, recitals A to C
`the recitals` MEANS
  item "WHEREAS:"
    • item "the Company is engaged in the business of software development;"
    • item "the Consultant has expertise in legal engineering; and"
    • item "the parties wish to record the terms of their engagement, namely"
      • item "the scope of services;"
      • item "the fees payable; and"
      • item "the term and termination."

`recital scheme` MEANS LIST UpperAlpha, LowerRoman

#EVAL `render outline` `recital scheme` `the recitals`
```

`render outline` gives one string per node, each `"<dotted path>\t<text>"`; the root's text is the
unnumbered heading. Here that is `"WHEREAS:"`, then `"A\tthe Company is engaged…"`, `"B\t…"`,
`"C\t…"`, `"C.i\tthe scope of services;"`, `"C.ii\t…"`, `"C.iii\t…"` — the lettering and the
`C.i` nesting are derived from the tree, not typed in. (Probe `i1-recitals.l4`, exit 0.)

**That bullet is a literal `•`, U+2022, and nothing else will do.** It is the language's own
list-element marker, not decoration, and the ASCII (American Standard Code for Information
Interchange) characters a model reaches for instead are all valid L4 meaning something else. An
ASCII hyphen is the subtraction operator, so the outline
type-checks as arithmetic and fails with a message about numbers and sets that says nothing about
bullets or about `hierarchy` (probe `r2-bullet-ascii.l4`, exit 1):

```
There are multiple definitions for the identifier

  `__MINUS__`

and I do not have sufficient information to make a choice between them.
The options are:

  `__MINUS__` (predefined) of type FUNCTION FROM NUMBER AND NUMBER TO NUMBER
  `__MINUS__` (defined at prelude.l4:1289:1-12) of type FOR ALL a FUNCTION FROM SET OF a AND SET OF a TO SET OF a
```

Note the asymmetry with the neighbouring rule you have probably already read:
[drafting-patterns.md](../drafting-patterns.md) warns loudly that `…` is not a token and you must
type three ASCII dots. Here it is the other way round — the exotic character is the required one.

**The scheme is positional, one style per depth, top level first, and there are six styles.**
`LIST UpperAlpha, LowerRoman` above means "letters at the top level, lower-case roman one level in".
The full set is `Decimal`, `UpperAlpha`, `LowerAlpha`, `UpperRoman`, `LowerRoman` and `Bulleted`;
`` `default scheme` `` is `LIST Decimal, UpperAlpha, LowerRoman, LowerAlpha`, the conventional legal
1 / A / i / a cascade. **Nesting deeper than the scheme is not an error** — the renderer falls back
to `Decimal` for every level past the end of the list, so a three-deep outline rendered with
`LIST UpperAlpha` gives `"A"`, `"A.1"`, `"A.1.1"` (probe `r3-numbering-styles.l4`, exit 0, eight
assertions satisfied). Pass a scheme at least as long as the outline is deep, or accept decimals
under your letters.

**Not** an input. A recital is not a fact anyone can supply, and making it one turns a sentence
nobody disputes into a question your web form asks the public:

```l4
§ `Consultancy Agreement`
    GIVEN `the parties wish to record the terms of their engagement` IS A BOOLEAN
```

The rule that reads it stops dead the moment anything forces it (probe `i2-recital-as-input.l4`,
exit 1):

```
I could not continue evaluating, because I needed to know the value of
  `the parties wish to record the terms of their engagement`
but it is an assumed term.
```

**Not** a limb of the operative rule either, even a harmless-looking one. A recital that sits in an
`AND` chain is a recital you can accidentally make load-bearing later.

**See** the user manual page `doc/tutorials/getting-started/encoding-legislation.md`, "Carry Inert
Text", for the `labeled` / `numbered` / `restartAt` escapes when drafting numbers
irregularly (an inserted "2A", a restart).

<a id="e9-3"></a>

## 9.3 "The purpose of this Act is …" — long titles, preambles, purpose clauses

**If the source says**

> "An Act to make provision for the regulation of charitable fundraising, and for connected
> purposes."

— the long title form; or a numbered purpose section, "The purpose of this Act is— (a) to promote
public confidence in charitable fundraising; …".

**It is doing** declaring the mischief. A purpose clause is read alongside the operative provisions
when one of them is ambiguous. It is a canon of construction, not a condition: nothing is
lawful or unlawful because of it.

**Write** a plain named string when it is one sentence, and an outline when it has limbs. Pin both
with `@ref`.

```l4
IMPORT hierarchy

@ref Charitable Fundraising Act, long title
`the long title` MEANS
    "An Act to make provision for the regulation of charitable fundraising, and for connected purposes."

@ref Charitable Fundraising Act s 2
`section 2 — purpose` MEANS
  item "The purpose of this Act is—"
    • item "to promote public confidence in charitable fundraising;"
    • item "to ensure that funds solicited from the public are applied to the purposes for which they were solicited; and"
    • item "to provide for the registration of fundraising appeals."

#EVAL `the long title`
#EVAL `render outline` (LIST LowerAlpha) `section 2 — purpose`
```

(Probe `i3-purpose.l4`, exit 0.)

**Not** a decision. `DECIDE` needs a proposition, and a purpose is not one — declaring the return
type says so (probe `i8-string-as-decide.l4`, exit 1):

```
The type of this definition must match its type signature at i8-string-as-decide.l4:3:8-17, namely

  BOOLEAN

but is here of type

  STRING
```

**Not** a gate on the rules it introduces. This is the trap the string-literal idiom sets: a string
_literal_ is inert inside a boolean chain, so a model that has seen the idiom assumes a _name_ bound
to a string is too. It is not (probe `i8b-purpose-as-gate.l4`, exit 1):

```
The first argument of function

  `__AND__` (predefined)

is expected to be of type

  BOOLEAN

but is here of type

  STRING
```

Which is the right answer for the wrong-looking reason. Even if it had checked, the purpose is not a
limb: every rule in the Act would have acquired a condition the Act does not impose.

**See** [drafting-patterns.md](../drafting-patterns.md), "Inert never shadows active", for the
literal form and where it is allowed.

<a id="e9-4"></a>

## 9.4 Headings, part titles and marginal notes

**If the source says** "Part 2 — Registration of fundraising appeals", or a marginal note
("_Cancellation of registration._") beside a section.

**It is doing** navigation. In most jurisdictions a heading is part of the enacted text and may be
used in construction, while a marginal note historically was not; either way it decides nothing.

**Write** the `§` heading structure, and nothing else. Headings nest with `§`, `§§`, `§§§` and carry
the source's own words, so the shape of the Act is the shape of the file. The corpus goes six deep
where the source does (`jl4/examples/legal/ny-environmental-7.3.l4:4-16`, with the second `@ref`
line at `:15` elided):

```l4
§ `New York Codes, Rules and Regulations`

§§ `Title 16 - DEPARTMENT OF PUBLIC SERVICE`

§§§ `Chapter I - RULES OF PROCEDURE`

§§§§ `Subchapter A - GENERAL`

§§§§§ `Part 7 - Implementation Of State Environmental Quality Review Act`

§§§§§§ `Section 7.3 - Environmental review procedures`
@ref 16 NY Comp Codes Rules and Regs § 7.3
```

A heading is also the scope boundary for everything under it — a definition or a section `GIVEN`
written beneath one is visible to that subtree. That is the whole of what a heading does in L4.

**Not** a value. A heading is structure, not a definition, and its text is not in scope as a name
(probe `i7-heading-not-a-value.l4`, exit 1):

```
I could not find a definition for the identifier

  `Part 2 — Registration of fundraising appeals`
```

If a projection needs the heading text as data — a table of contents, a wizard's page titles — put
it in an outline as well (entry 9.2). Carrying it twice is correct; the heading is for the reader of
the file, the outline is for the application.

**See** [01-definitions-and-scope.md](01-definitions-and-scope.md#e1-4) for what else a `§` heading
scopes.

<a id="e9-5"></a>

## 9.5 "Note:", "for information only", explanatory notes

**If the source says**

> `... "for the avoidance of doubt"` in the middle of a limb chain
>
> — `jl4/examples/ok/inert/basic.l4:36`, the corpus's own test of a mid-chain inert string

or a note in the source itself: "_Note to paragraph (2): approval under this paragraph is given by
the Regional Office, not by the Registrar._"

**It is doing** telling the reader something true that the provision does not turn on. A note names
a decision-maker, points at another Act, or restates the obvious. It changes no outcome.

**Write** it as a string literal riding on the limb it annotates, joined by `...`, so it belongs to
that limb rather than becoming a limb of its own.

```l4
@ref Charitable Fundraising Act s 7(2) and note
GIVEN ap IS AN Appeal
GIVETH A BOOLEAN
DECIDE `the appeal is a regional appeal` ap IF
        ap's `conducted wholly within one Region`
    AND "(2)" ... "Note: approval is given by the Regional Office." ... ap's `the Region has given approval`
```

(Probe `i9-note.l4`, exit 0, the assertion satisfied.) The `...` join matters: two `..` rungs would
make the note its own operand and draw it as a separate box in a ladder diagram.

**Not** a verbatim re-quotation of the limb beside it. An inert string that restates the words of the
active node next to it prints the same sentence twice — once as law, once as code — and a reader has
to diff them by eye to learn they agree. Keep the label, drop the restatement.

**Not** a note detached from its rule when it belongs to one. A note in its own definition is a note
nobody reading the rule will see.

**See** [drafting-patterns.md](../drafting-patterns.md), "Inert never shadows active", for the full
ruling, the three ways to get the join wrong, and the two kinds of string that do stay whole.

<a id="e9-6"></a>

## 9.6 "Without prejudice to section 12, …"

**If the source says** "Without prejudice to section 12, the Registrar may cancel a registration if
the appeal has ceased."

**It is doing** a **non-derogation** marker. It tells you that the provision it opens does **not**
cut down the one it names — both powers stand, and neither is the exclusive route. It is the
draftsman heading off an _expressio unius_ argument, and there is nothing in it to compute.

Read it before you believe that, though. The same words do a different job in "the remedies in this
clause are without prejudice to any other remedy available at law", which preserves a cumulative
right the clause would otherwise be read to have excluded. That reading _is_ operative, and it
belongs in area 10 — see [10.4](10-for-the-avoidance-of-doubt.md#e10-4).

**Write** the power, with the opening words carried as the limb's label. Encode the named provision
as its own rule; the two coexist, which is exactly what the phrase asserts.

```l4
@ref Charitable Fundraising Act s 18(1)
GIVEN r IS A Registration
GIVETH A BOOLEAN
DECIDE `the Registrar may cancel under section 18` r IF
        "Without prejudice to section 12," ... r's `the appeal has ceased`

@ref Charitable Fundraising Act s 12(1)
GIVEN r IS A Registration
GIVETH A BOOLEAN
DECIDE `the Registrar may cancel under section 12` r IF
    r's `the registration was obtained by deception`

#ASSERT NOT `the Registrar may cancel under section 18` `the deceptive registration`
#ASSERT     `the Registrar may cancel under section 12` `the deceptive registration`
```

(Probe `i6-without-prejudice.l4`, exit 0, both assertions satisfied.) The two assertions are the
phrase, written as a test: s 18 does not reach the deceptive registration, and s 12 still does.

**Not** an exclusion. The commonest misreading is "without prejudice to section 12" as "only where
section 12 does not apply", which inverts it:

```l4
DECIDE `the Registrar may cancel under section 18` r IF
        NOT `the Registrar may cancel under section 12` r
    AND r's `the appeal has ceased`
```

This is the dangerous kind of wrong: it type-checks and it runs clean. Probe
`i6b-without-prejudice-as-gate.l4` exits 0 with no diagnostic and answers

```
Result:
  FALSE
```

for a registration that both ceased _and_ was obtained by deception — where the Act gives the
Registrar the power twice over. No error told you; only the assertions in the correct version would
have.

**See** [02-conditions-and-logic.md](02-conditions-and-logic.md#e2-2) for "subject to" and
"notwithstanding", which really do reorder provisions and are a different problem.

<a id="e9-7"></a>

## 9.7 Governing law, entire agreement, notices — the back-of-the-contract boilerplate

**If the source says**

> `` `Governing Law` MEANS "The laws of The Republic of Singapore" ``
>
> — `jl4/examples/legal/promissory-note.l4:27`

**It is doing** work, but not work this encoding does. A governing-law clause chooses the legal
system whose rules apply; an entire-agreement clause excludes prior representations; a notices
clause fixes service. Each is operative in a dispute and none of it is computed by the rules you are
encoding — the encoding _is_ the chosen law's answer, already.

**Write** them as named inert text: a string for a one-liner, an outline where the clause has limbs.
Name each for the clause, so a reader can see at a glance that it was read and parked rather than
missed.

```l4
IMPORT hierarchy

@ref Consultancy Agreement cl 14.1 (Governing law)
`Governing Law` MEANS "The laws of the Republic of Singapore"

@ref Consultancy Agreement cl 14.2 (Entire agreement)
`Entire Agreement` MEANS
  item "14.2 Entire agreement."
    • item "This Agreement constitutes the entire agreement between the parties and supersedes all prior negotiations, representations and understandings."
    • item "Nothing in this clause limits liability for fraudulent misrepresentation."
```

(Probe `i4-boilerplate.l4`, exit 0.)

**Not** a type or a record you never read. A `DECLARE Jurisdiction` with no rule consuming it is
scaffolding pretending to be a model; the string carries the same information and does not invite a
later reader to wire it up.

The promissory note's own comment is the honest note to leave beside it: "ideally this would be an
`IMPORT` statement … so you can hard reference the terms and definitions of Singapore law"
(`jl4/examples/legal/promissory-note.l4:27-29`). The clause points at a body of law nobody has
encoded. Say so; do not model it.

<a id="e9-8"></a>

## 9.8 A Schedule that is prose

**If the source says** a Schedule whose paragraphs are directions in words rather than a table —
"1. The funeral, testamentary and administration expenses shall have priority."

**It is doing** ordering something, in language too open to compute: the Probate and Administration
Act's First Schedule routes an insolvent estate into the whole of bankruptcy law by one
cross-reference. What an encoding can honestly say is _which_ Schedule governs and what its
paragraphs say, not what they produce.

**Write** a record per paragraph carrying the Schedule's own words in a field **nothing reads**, and
gather them into a list. The corpus states the reason in a comment: "One numbered paragraph of the
First or Second Schedule, carrying the Schedule's own words. The app shows these; nothing in this
module reads `text`, which is why it can be verbatim"
(`jl4/examples/legal/sg-succession/sg-paa.l4:187-189`).

```l4
DECLARE `Rule of application`
    HAS `paragraph` IS A NUMBER
        `text`      IS A STRING

@ref PAA 1934 First Schedule, paragraph 1
GIVETH A `Rule of application`
`First Schedule paragraph 1` MEANS
    `Rule of application` WITH `paragraph` IS 1
                             , `text`      IS "The funeral, testamentary and administration expenses shall have priority."

GIVETH A LIST OF `Rule of application`
`the First Schedule` MEANS LIST `First Schedule paragraph 1`
```

(Probe `i5-schedule-prose.l4`, exit 0. The corpus original is
`jl4/examples/legal/sg-succession/sg-paa.l4:1461-1490`.)

Prefer this to a bare outline when a rule elsewhere has to _select_ the Schedule — the record is
addressable, so `the application of assets in` can branch on solvency and hand back the right list.
Use an outline (entry 9.2) when nothing selects anything and the Schedule is pure text.

**Not** a `DECIDE` per paragraph. "The same rules shall prevail … as may be in force for the time
being under the law of bankruptcy" is not a proposition with a truth value in this encoding, and a
predicate named for it would be a promise the file cannot keep.

**Not** dropped because it is not computable. A user who reaches the insolvent branch needs to be
told which Schedule governs and that funeral and administration expenses come first — that answer is
worth more than a gap.

<a id="e9-9"></a>

## 9.9 Whatever you carried — pin it

**If the source says** anything at all that you copied into a string.

**It is doing** standing in for the source. The moment prose is inside the file, a reader stops
consulting the source and starts trusting you.

**Write** an `@ref` above every inert definition naming the instrument, the provision, and — where
the wording is version-sensitive — the amendment that produced the reading you carried. Every
snippet in this area does it; that is not decoration.

```l4
IMPORT hierarchy

@ref Charitable Fundraising Act s 2
`section 2 — purpose` MEANS
  item "The purpose of this Act is—"
    • item "to promote public confidence in charitable fundraising;"
```

Two habits that matter more for inert text than for rules:

- **Resolve amendments to the in-force reading**, and keep the words that were removed as inert
  prose beside them, marked as removed. An unresolved textual-amendment marker in a quotation is a
  quotation of something that is not the law.
- **Quote, do not paraphrase.** A paraphrase in a `MEANS "…"` reads exactly like a quotation and
  cannot be checked against the source without opening it. If you must summarise, say you did.

**See** [drafting-patterns.md](../drafting-patterns.md), "Provenance — pin every inert string;
resolve amendments to the in-force reading", for the two-way pin (a header comment plus an inline
note at the amendment site) and a worked example.
