# Optimising for Natural Language Document Generation with `@nlg`

**Prerequisites:** Basic L4 functions ([Your First L4 File](../getting-started/first-l4-file.md)) and [Infix, Postfix, and Mixfix Functions](natural-language-functions.md) — the calling-syntax foundation this tutorial builds on

---

L4 can render your rules back into formatted prose — in the VS Code
**Render** tab, or with `l4 render`. The renderer is **deterministic**: it walks
your code and turns each construct into a sentence or an outline. It is also
**language-agnostic**: it prints the words you wrote, so a file written in
English reads as English and one written in Hebrew reads as Hebrew. Nothing in
the renderer knows the difference. This tutorial is in English because its
examples are. That means the
quality of the generated prose is mostly in your hands. Well-named, well-shaped
rules read almost like professionally drafted legal writing with no extra effort; awkward ones read like a
transcript of an algorithm.

This tutorial shows how to get transparent prose out of the renderer, using three increasingly powerful levers:

1. **Names** — backticked identifiers and parameter names.
2. **Shape** — mixfix word order, control flow, section titles, and arithmetic.
3. **`@nlg`** — an authored sentence that overrides the structural rendering.

It finishes with how **Legalese AI** can then apply drafting policies to refine
the result further.

## Lever 1 — Names do most of the work

The renderer prints identifiers and parameter names **verbatim**. Good names are
the single highest-leverage thing you can do.

### Name rules as the phrase you want to read

A backticked identifier can contain spaces, so name a rule as the noun phrase or
clause it represents:

```l4
-- Renders: "Monthly property tax means ..."
`monthly property tax` MEANS ...

-- Renders: "Mpt means ..."
mpt MEANS ...
```

> [!NOTE]
> Beginner programmers are routinely and pointedly reminded to use the first form whenever they reach for the latter.

### Name parameters as nouns, not letters

Parameters appear in the rendered prose and in every `@nlg` slot. Name them the
way they should read:

```l4
-- Renders: "... the buyer ... the seller ..."
GIVEN `the buyer` IS A Person
      `the seller` IS A Person

-- Renders: "... p ... q ..."
GIVEN p IS A Person
      q IS A Person
```

Sometimes existing legal writing will deliberately adopt this form: "A person (A) discriminates against another (B) if ..." (Equality Act 2010, s.13). In that situation the renderer will aim to obey the "legislative variable" style.

If a parameter has a record type, the renderer promotes the type name into a noun phrase: ``GIVEN claim IS A `Payment Claim` `` renders as "the payment claim". This works cleanly only when one parameter has that type — two `Payment Claim` parameters would collide on the same phrase.

### Name record fields readably

Projections render as `X's field`, so field names carry straight into the prose:

```l4
DECLARE `Property Details` HAS
    `market value`         IS A NUMBER
    `monthly property tax` IS A NUMBER
-- "the property's market value", "the property's monthly property tax"
```

---

## Lever 2 — Shape the code so it reads in order

### Use mixfix so calls read as sentences

Put the words and the argument holes where they belong in the sentence. (See the
[mixfix tutorial](natural-language-functions.md) for the full mechanics.)

```l4
GIVEN `the applicant` IS A Person
      `the programme` IS A Programme
      `application date` IS A DATE
GIVETH A BOOLEAN
DECIDE `as at an` `application date` `the applicant` `is eligible for` `the programme` IF ...

```

In a conventional programming language, this would be a function taking three arguments: `eligibility(applicant, programme, date)`.

In L4, it is also a function taking three arguments, but the arguments are intermingled across the function name for the sake of readability.

### End helper names in a preposition

A function whose name ends in a preposition (`of`, `for`, `to`, `between`, …)
gets its arguments joined naturally, without a stray "with":

```l4
`the later of` x y MEANS IF x >= y THEN x ELSE y
-- "the later of the start date and the end date"
```

### Let control flow stay structured

`CONSIDER`, `IF`/`THEN`/`ELSE`, and `AND`/`OR` render as indented outlines, not
run-on sentences. Keep operative logic where the renderer can see it as
structure rather than burying it inside an unrelated expression:

```l4
CONSIDER claim's status
WHEN Paid    THEN ...
WHEN Overdue THEN ...
```

renders as

```
depending on the claim's status:
- if it is Paid: ...
- if it is Overdue: ...
```

### Keep arithmetic as arithmetic

Numeric expressions render in **formula mode** — with `+ − × ÷` and parentheses —
not as nested "the sum of the product of …". Write the maths directly instead of
wrapping it in prose helpers:

```l4
(`base rent` PLUS `service charge`) TIMES `months` PLUS `deposit`
-- "(base rent + service charge) × months + deposit"
```

### Group rules into titled sections

Section markers organise a document into titled, numbered sections — they become
headings in the rendered output and entries in the table of contents.

- `` § `Section Name` `` starts a top-level section.
- `` §§ `Subsection Name` `` nests one level deeper (`§§§` deeper still).

The name is backtick-quoted, so it can be a full phrase. Every declaration after
a marker belongs to that section until the next marker:

```l4
§ `Eligibility`

GIVEN `the applicant` IS A Person
`the applicant` `qualifies for EP` IF ...

§§ `Age requirements`

GIVEN `the applicant` IS A Person
`the applicant` `is of working age` IF ...
```

renders as

```
§ 1  Eligibility
    • The applicant qualifies for EP if ...
    1.1  Age requirements
        • The applicant is of working age if ...
```

The `§` numbers appear when **Number sections** is enabled in the Render tab
(or `--number-sections` on the CLI); the headings and table-of-contents entries
appear either way.

A flat file with no markers still gets sensible structure — its type
definitions and rules are grouped into automatic **Definitions** and
**Provisions** sections — but explicit `§`/`§§` markers let you name and order
the parts the way a reader of the contract or statute would expect. Imported
modules that carry their own section titles keep them, rendering under their own
heading rather than a generic one.

---

## Lever 3 — `@nlg`: author the exact sentence

When structure and naming aren't enough — a recursive helper, domain jargon, or
a formula you'd rather state in words — attach an `@nlg` annotation. It is the
authoritative natural-language form of that definition.

### Where it goes: end of the line

Write `@nlg` at the **end of the construct's line**, trailing the signature, with
the body on the next line:

```l4
GIVEN x IS A NUMBER, y IS A NUMBER
GIVETH A NUMBER
`the greater of` x y @nlg the greater of %x% and %y%
  MEANS IF x >= y THEN x ELSE y
```

### `%param%` slots

Inside the sentence, `%name%` refers to a parameter. The renderer fills each slot
with:

- the **parameter name** when it shows the definition itself, and
- the **actual argument** at each call site.

So the rule above renders as _"The greater of means the greater of x and y"_ in
its own definition, and a call `` `the greater of` `start date` `end date` ``
renders as _"the greater of the start date and the end date"_.

A slot is **tight**: `%amount%`, with no spaces inside the delimiters. That is
what keeps a written-out percentage from being mistaken for one. In

```l4
@nlg a 5% levy on %amount%
```

the `%` after `5` is ordinary text, because `% levy on %` has spaces inside it
and so is not a slot; `%amount%` still is one. Where a percent sign would end up
flush against a word — `5%levy` — wrap it in backticks (`` `5%` ``) or spell it
out ("5 percent"), either of which puts it beyond doubt.

### It replaces the implementation

A function with an `@nlg` renders **as its sentence**, not as its body. This is
what makes recursive library functions readable — for example `filter` ships
with:

```l4
filter f list @nlg the items of %list% for which %f% holds
  MEANS ...
```

so ``filter `is eligible` applicants`` reads _"the items of applicants for
which is eligible holds"_ instead of exposing the recursion.

### When to reach for it

| Situation                                             | Why `@nlg` helps                                 |
| ----------------------------------------------------- | ------------------------------------------------ |
| Recursive / higher-order helpers                      | Hide the implementation behind a description     |
| Math you'd rather phrase in words                     | "the pro-rated premium" instead of the formula   |
| Domain terms of art                                   | Match the exact statutory or contractual wording |
| A name that can't be both valid code _and_ good prose | Decouple the two                                 |

### Tips

- Keep slots to the function's own parameters; the sentence should make sense
  with each slot read as a noun phrase.
- Prefer **naming and shape first**, `@nlg` second — an `@nlg` is a maintenance
  cost (it can drift from the logic), so reserve it for where it earns its keep.
- One sentence per definition. If you need branching prose, let the structure
  (`CONSIDER`/`IF`) render and annotate the leaves.

---

## Lever 4 — one encoding, two documents

Everything above produces _a_ document. The same machinery produces a **set** of
them, one per language, from a single encoding — because a rule can carry more
than one rendering, and each says which language it is in.

### Write both renderings

A language subtag goes straight after the herald, and the second rendering goes
on the continuation line under the first:

```l4
GIVEN amount IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is large` @nlg:en the claim of %amount% exceeds the threshold
                  @nlg:he %amount% עולה על הסף
  IF amount GREATER THAN 100
```

Only the wording is duplicated. There is one rule, one set of tests, one thing
to get right; the second language cannot drift away from the logic, because
there is no second logic for it to drift from. That is the whole argument for
doing it this way rather than maintaining two documents.

### Say the language once, not on every rule

A whole module in one language does not need a tag per rule. Declare it:

```l4
@lang he
```

Every untagged `@nlg` below then means Hebrew — the declaration is exactly
equivalent to writing `:he` on each herald, so you can still tag individual
rules where you want a second language. A module that declares nothing means
English, which is why everything above this section worked without one.

### Ask for each one

```console
$ l4 nlg --lang en contract.l4  > contract.en.txt
$ l4 nlg --lang he contract.l4  > contract.he.txt
```

Two runs, one argument apart. That is the bilingual set.

`l4 render` takes the same flag, and that is the one you want for a document
somebody reads — the prose above is the linearizer's output, while `render`
produces the formatted article:

```console
$ l4 render --format html --lang en contract.l4 -o contract.en.html
$ l4 render --format html --lang he contract.l4 -o contract.he.html
```

Every format `render` supports — `text`, `html`, `akn`, `json`, `plan` —
follows the flag, because the language is chosen before the document is built
rather than inside each writer.

### The HTML document says which language it is in

The `html` format labels the document itself, not just its sentences.

```
<html lang="he" dir="rtl">
```

`lang` is the language the document was rendered in: the `--lang` you asked for, or the module's own `@lang` when you asked for nothing, or `en` when the module declares nothing either.
It is what a screen reader picks a voice from, what a browser hyphenates and spell-checks by, and what a translation tool decides to leave alone.

**A language nothing in the module renders does not relabel the document.**
`--lang he` on an encoding with no Hebrew in it at all would otherwise produce a document labelled Hebrew in which every sentence is the English fallback — and, worse, laid out right to left.
So when no rule in the module or its imports has a rendering in the language you asked for, the document keeps the language it declares, and `render` says so on stderr:

```console
$ l4 render --format html --lang he english-only.l4 > out.html
l4 render: no renderings in "he"; document labelled "en" instead.
```

A **partial** translation is different, and still labels the document by what you asked for: `--lang he` on a module with two Hebrew rules out of ten gives you `lang="he"` and eight English paragraphs, which is the same partial-translation story as the section above, told in the wrapper.
The line between the two is whether the module renders _anything_ in that language.

The label follows the request in the other direction too.
`--lang en` on a module that declares `@lang he` gives you `lang="en"`, and the clauses that have an English rendering in English — but a clause with only a Hebrew herald still renders in Hebrew, because that is the fallback.
That document is genuinely mixed, and `lang` records what was asked for rather than a measurement of what came out.

`dir="rtl"` appears only for a right-to-left language — Hebrew, Arabic, Persian, Dari, Urdu, Yiddish, Pashto, Central Kurdish, Sindhi, Uyghur, Kashmiri, Divehi, Aramaic, Syriac, N'Ko.
For everything else there is no `dir` at all, because left-to-right is already HTML's default and the attribute appearing is the signal.

**The script subtag wins when the tag has one**, because the script is the part of a language tag that actually decides direction.
`--lang he-Latn` is Hebrew romanised in Latin letters and gets no `dir`; `--lang az-Arab` is Azerbaijani written in Arabic script and gets `dir="rtl"`, even though neither `he-Latn` nor `az-Arab` could be read off its first subtag.
A region or a case difference is not a direction: `he-IL`, `HE` and `he` are one answer.

**What `dir` does, exactly**, because it is easy to expect too much of it.
It sets the document's _base_ direction, and the base direction decides where the neutral characters at the edges of a line go and in which order whole runs of the other direction sit.
It is not a per-line guess, and without it a browser does not make one either: HTML's default base is left-to-right, full stop.
So for a clause whose prose is Hebrew, `dir="rtl"` is the difference between a full stop at the end of the sentence and one stranded at the start of it.
Reproduce it on any Hebrew line with `fribidi`, which resolves the same algorithm a browser does — `fribidi --ltr line.txt` against `fribidi --rtl line.txt`:

```
base ltr:  ⟨Hebrew clause, laid out right to left⟩ .   <- the full stop at the right-hand end: wrong
base rtl: . ⟨Hebrew clause, laid out right to left⟩    <- at the left-hand end, where a right-to-left line ends
```

(The Hebrew is stood in for here because `fribidi` prints _visual_ order, and a visual-order line pasted into a page is re-ordered again by the browser rendering it.)

The corollary is that a line which _begins_ in the other direction is laid out as a line of the base direction containing a foreign run.
An L4 clause heading is the rule's own name, which is usually an English identifier, so in a Hebrew document `Is large holds if amount עולה על הסף.` is a right-to-left line whose Latin run and full stop sit on the left.
That is correct for a Hebrew document and looks wrong if you read the line as an English sentence; judging each element on its own characters is what `dir="auto"` is for, and L4 does not emit it on individual clauses today.

The stylesheet mirrors along with `dir`: clause numbers, indents and table alignment move to the other side, because every rule that has a side is written in terms of the start and end of a line rather than of left and right.

**`--lang` is validated before it reaches the markup.**
Surrounding whitespace is trimmed and the primary subtag is lowercased, so `--lang 'he '` and `--lang HE` are the tag you meant — the first of those used to label the document `he ` and then silently lose `dir="rtl"`.
An empty value, or one with anything in it but letters, digits and `-`, is refused with a message instead of being pasted into the attribute.

### The Akoma Ntoso document says the same thing, in FRBR

`--format akn` identifies what it emits the way Akoma Ntoso does, as a Work, an Expression of that work in one language, and a Manifestation of that expression as a file:

```xml
<FRBRExpression><FRBRthis value="/akn/doc/main/heb@"/><FRBRuri value="/akn/doc/heb@"/>…
```

The `heb` is the document's language — the same choice `<html lang>` reports, translated from the BCP 47 subtag you write (`he`) to the ISO 639-2 code AKN's URIs use (`heb`).
Where ISO 639-2 has two codes for a language, this is the terminological one: `deu`, not `ger`.
A subtag with no entry in that table is passed through as it stands, which is honest about which language was meant even though it is not a valid ISO 639-2 code.

### Translate incrementally

A rule with no rendering in the language you asked for falls back to its default
one. A half-translated encoding therefore produces a **whole** document with
some paragraphs still in the original language — which is what you want while
the translation is in progress, and is very different from a document with
holes in it. You can ship after the first pass and keep going.

### Then there is the case where you do nothing

Now read the same rule with the tags taken off:

```l4
DECIDE `is large` @nlg the claim of %amount% exceeds the threshold
  IF amount GREATER THAN 100
```

Ask for no language, and you get that sentence. Ask for `--lang he`, and you
get that sentence too, because there is no Hebrew rendering to prefer and the
fallback is the default.

**So "L4 documents come out in English" is not a rule — it is the degenerate
case of the rule above.** What you actually get is _the default rendering_: the
untagged annotation if there is one, otherwise the first in the file. Our corpus
is written in English, so its default renderings are English sentences, and the
output looks like a language setting nobody configured. It is not one. A corpus
whose annotations are written in Hebrew has always produced Hebrew documents,
with no tags and no flag, and did so before tags existed at all — see
[Multilingual L4](../../reference/syntax/README.md#labelling-the-language-nlghe).

The practical consequence: **you never have to start tagging.** Tags earn their
keep at the moment a second language appears, and not before. An encoding with
one language wants no tags at all, and adding them changes nothing about what it
prints.

### One clash to know about

Two renderings in the _same_ language on one rule — two `@nlg:he`, or two
untagged — is an ambiguity, not a choice. L4 warns and attaches neither, because
silently keeping one would discard a sentence you wrote. A clash in one language
leaves the others alone.

---

## Literal recitals — carrying prose that isn't computed

The levers above get _computed_ logic to read as prose. But parts of a legal
document aren't logic at all — recitals, the preamble, the WHEREAS clauses.
Their job is to be carried verbatim and numbered, not evaluated. For these,
reach for the `hierarchy` library: a recital outline is a tree of **strings**
(`item "…"`), authored as a bullet list and rendered with automatic numbering.

Each item is just text — never evaluated — so a recital may say anything,
including wording that would not be valid L4 logic. Mark each item with a **`•`**
bullet and nest by indenting deeper (see [Bullet lists](#bullet-lists) below).

```l4
IMPORT hierarchy

`recital scheme` MEANS LIST UpperAlpha, Decimal, LowerRoman

`recitals` MEANS
  item "RECITALS"
    • item "the Company is engaged in the business of software development;"
    • item "the Consultant has expertise in legal engineering; and"
    • item "the parties wish to record the terms of their engagement, namely"
      • item "the scope of services;"
      • item "the fees payable; and"
      • item "the term and termination."

#EVAL `render outline` `recital scheme` `recitals`
```

renders the heading verbatim and numbers the rest by depth — `A`, `B`,
`C`, then `C.1`, `C.2`, …:

```
RECITALS
A      the Company is engaged in the business of software development;
B      the Consultant has expertise in legal engineering; and
C      the parties wish to record the terms of their engagement, namely
C.1    the scope of services;
C.2    the fees payable; and
C.3    the term and termination.
```

You pick the numbering _style_ per depth (`recital scheme` above is upper-alpha,
then decimal, then lower-roman); the renderer assigns the actual markers. When
drafting needs an irregular sequence — an inserted "2A", a restart — `labeled`,
`numbered`, and `restartAt` pin or reset a marker without disturbing its
neighbours.

The contrast with the rest of this guide is the point: `@nlg` renders prose
_from_ logic; recitals are prose that simply _is_. Use names + shape + `@nlg`
for the operative clauses, and `hierarchy` outlines for the narrative scaffolding
around them.

### Bullet lists

A `•` followed by a space and a same-line body opens a list element; a block
of `•` items aligned at a common column desugars to an ordinary `LIST`
(conventionally written at the start of a line, though that's a style
convention, not an enforced rule):

```l4
DECIDE xs IS
  • 1
  • 2
  • 3          -- == LIST 1, 2, 3
```

`•` was chosen deliberately: it has no other meaning in L4 (unlike `-`, which is
subtraction), so it is unambiguous everywhere — including in **argument
position**. That is what lets bullet children nest under a constructor with no
`LIST` and no parentheses: `• item "a"` under `item "Parent"` makes `"a"` a
_child_ of the parent (feeding the arity-overloaded `item txt kids`
constructor), to any depth. The element itself is any expression, so every
outline constructor — `item`, `labeled`, `numbered`, `restartAt` — works per
line.

**Indentation.** A child bullet lines up directly under its parent's content —
the `item` word, which the `• ` marker sits two columns to the left of:

```l4
item "Parent"
  • item "Sub"
    • item "child"     -- the child '•' sits under the parent's `item`
```

Any deeper indent works too; under the parent's text is the natural choice (and
matches how a sub-list reads in Markdown).

(Yes, `•` is awkward to type; bind it to a snippet or keyboard shortcut in your
editor. The unambiguity is worth it.)

---

## Putting it together

Before — terse names, no annotations:

```l4
GIVEN p IS A NUMBER, r IS A NUMBER, n IS A NUMBER
GIVETH A NUMBER
pmt p r n MEANS p TIMES r DIVIDED BY (1 MINUS (1 PLUS r) EXPONENT (0 MINUS n))
```

renders as a bare formula with opaque single letters.

After — descriptive names plus one `@nlg`:

```l4
GIVEN `the principal` IS A NUMBER
      `the monthly rate` IS A NUMBER
      `the term in months` IS A NUMBER
GIVETH A NUMBER
`the monthly repayment on` `the principal`
    `at` `the monthly rate` `over` `the term in months`
    @nlg the level monthly repayment on %the principal% at %the monthly rate% over %the term in months%
  MEANS ...
```

Now both the definition and every call site read as a sentence a lawyer can check.

---

## Refining further with Legalese AI

The renderer gives you a faithful, deterministic baseline — the same input always
produces the same prose, and it never invents facts. That baseline is the right
foundation, but house style, tone, and jurisdiction conventions are editorial
choices that go beyond what deterministic rules should decide.

That is where **Legalese AI** comes in. Once your rendered output is accurate,
you can apply **drafting policies** — reusable style and language rules such as
"use plain English", "prefer active voice", "expand defined terms on first use",
or a firm's house style — and Legalese AI rewrites the rendered prose to match,
while staying anchored to the deterministic output so the meaning is preserved.

In other words: **names, shape, and `@nlg` get the content right; drafting
policies get the _style_ right.** See
[Composing L4 with AI](../llm-integration/composing-l4-with-ai.md) for how
Legalese AI fits into the authoring loop.
