# Make rules read like law

Write rules whose calls read like sentences, and whose rendered document reads like legal drafting.

**Before you start:** [Install L4 and write your first rule](../getting-started/first-l4-file.md).

This page has two parts:

1. **Infix, postfix and mixfix functions**: put a rule's name and its inputs in natural word order, so `` `the applicant` `is eligible for` `the programme` `` is valid L4.
2. **Rendering**: L4 can turn your rules back into a document. Names, the shape of the code, and `@nlg` annotations decide how well it reads.

---

## Infix, postfix and mixfix functions

Most programming languages put the function name first: `isEligible(person, programme)`. In L4 the inputs can go before, between or after the words of the name:

| Pattern | Definition                                         | Call                          |
| ------- | -------------------------------------------------- | ----------------------------- |
| Prefix  | `` `plus` a b MEANS ... ``                         | `` `plus` 3 5 ``              |
| Infix   | ``a `plus` b MEANS ...``                           | ``3 `plus` 5``                |
| Postfix | ``amount `percent` MEANS ...``                     | ``50 `percent` ``             |
| Mixfix  | ``value `is between` lower `and` upper MEANS ...`` | ``5 `is between` 0 `and` 10`` |

The inputs are the names declared with `GIVEN`; every other word in the definition is part of the function's name. A call uses the same word order as the definition.

**Complete example:** [natural-language-example.l4](natural-language-example.l4)

### Infix: one input on each side

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
a `plus` b MEANS a + b

#EVAL 3 `plus` 5
#EVAL `plus` 3 5
```

Both calls return `8`: a function defined in infix form can also be called in prefix form.

Names in backticks can contain spaces, so the name can be a whole phrase:

```l4
DECLARE Person
    HAS `name`   IS A STRING
        `age`    IS A NUMBER
        `income` IS A NUMBER

GIVEN `the person` IS A Person
      `the threshold` IS A NUMBER
GIVETH A BOOLEAN
`the person` `has income above` `the threshold` MEANS
    `the person`'s `income` > `the threshold`

`Alice` MEANS Person WITH
    `name`   IS "Alice"
    `age`    IS 30
    `income` IS 50000

#EVAL `Alice` `has income above` 40000
```

### Postfix: the input before the name

```l4
GIVEN `the person` IS A Person
GIVETH A BOOLEAN
`the person` `is an adult` MEANS `the person`'s `age` >= 18

#EVAL `Alice` `is an adult`
```

For a one-word name, the backticks are optional at the call site: with ``n `squared` MEANS n * n``, both `5 squared` and ``5 `squared` `` work.

### Mixfix: words and inputs interleaved

A mixfix name has several words, with inputs between them:

```l4
GIVEN value IS A NUMBER
      lower IS A NUMBER
      upper IS A NUMBER
GIVETH A BOOLEAN
value `is between` lower `and` upper MEANS
    lower <= value AND value <= upper

#EVAL 5 `is between` 0 `and` 10

GIVEN principal IS A NUMBER
      rate      IS A NUMBER
      term      IS A NUMBER
GIVETH A NUMBER
`simple interest on` principal `at` rate `percent for` term `years` MEANS
    principal * rate / 100 * term

#EVAL `simple interest on` 1000 `at` 5 `percent for` 3 `years`
```

The calls return `TRUE` and `150`. There is no limit on the number of inputs.

### Points to watch

- **List the inputs in `GIVEN` in the order they appear in the definition.** For ``value `is between` lower `and` upper``, the `GIVEN` must list `value`, `lower`, `upper`, in that order.
- **An input cannot share a name with a word of the function name.** `` `percent for` years `years` `` is an error; call the input `term`.
- **Use parentheses** when an argument is itself an expression: ``(1 + 2) `plus` (3 + 4)``.
- **Define local helpers in `WHERE`.** A `WHERE` block can hold a full `GIVEN ... MEANS` definition, mixfix ones included; the complete example shows one.

For the exact rules of how L4 matches mixfix calls, see [Mixfix functions](../../reference/functions/README.md#mixfix-functions).

---

## Render your rules as a document

L4 can render your rules as formatted prose, in the VS Code **Render** tab or with `l4 render file.l4 --format text`. The renderer is deterministic: it walks your code and turns each construct into a sentence or an outline. It is also language-agnostic: it prints the words you wrote, so a file written in English reads as English and one written in Hebrew reads as Hebrew. Nothing in the renderer knows the difference. This page is in English because its examples are. So the quality of the prose is mostly in your hands. Well-named, well-shaped rules read almost like professional drafting with no extra effort; badly named ones read like a transcript of an algorithm.

Three levers, from the cheapest to the most precise:

1. **Names**: backticked identifiers and input names.
2. **Shape**: mixfix word order, control flow, arithmetic and section headings.
3. **`@nlg`**: a sentence you write that replaces the generated one.

Two more sections follow the levers: [One encoding, two documents](#one-encoding-two-documents) renders the same rules in more than one language, and [Literal recitals](#literal-recitals--carrying-prose-that-isnt-computed) carries prose that is not computed.

---

## Names do most of the work

The renderer prints names as you wrote them. Good names are the most effective thing you can do.

**Name rules as the phrase you want to read.** A backticked name can contain spaces:

```l4
`monthly property tax` MEANS 250
mpt MEANS 250
```

The first renders as "Monthly property tax means 250."; the second as "Mpt means 250."

**Name inputs as nouns, not letters.** Inputs appear in the prose and in every `@nlg` slot:

```l4
GIVEN `the purchase price` IS A NUMBER
      `the deposit paid`   IS A NUMBER
GIVETH A NUMBER
`the balance due` MEANS `the purchase price` MINUS `the deposit paid`

GIVEN p IS A NUMBER
      d IS A NUMBER
GIVETH A NUMBER
`balance` MEANS p MINUS d
```

The first renders as "The balance due equals the purchase price − the deposit paid."; the second as "Balance equals p − d."

Legal writing sometimes uses letters on purpose, as in "A person (A) discriminates against another (B) if …" (Equality Act 2010, s.13). There, single letters are the right choice.

When an input has a record type, the renderer refers to it by the type's name: with `` GIVEN claim IS A `Payment Claim` ``, `` claim's `amount` `` renders as "the payment claim's amount". This works well when only one input has that type; two inputs of the same type would share the same phrase.

**Name record fields readably.** A field renders as "X's field", so field names go straight into the prose:

```l4
DECLARE `Property Details`
    HAS `market value`         IS A NUMBER
        `monthly property tax` IS A NUMBER
```

---

## Shape the code so it reads in order

**Use mixfix so calls read as sentences.** Put the words and the inputs where they belong in the sentence:

```l4
DECLARE Person    HAS `age`           IS A NUMBER
DECLARE Programme HAS `minimum age`   IS A NUMBER

GIVEN `the applicant` IS A Person
      `the programme` IS A Programme
GIVETH A BOOLEAN
DECIDE `the applicant` `is eligible for` `the programme` IF
    `the applicant`'s `age` AT LEAST `the programme`'s `minimum age`
```

**End helper names with a preposition.** When a function's name ends in a word such as `of`, `for`, `to` or `between`, its arguments are joined naturally:

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`the later of` x y MEANS IF x >= y THEN x ELSE y

`start date` MEANS 3
`end date`   MEANS 7
`the deadline` MEANS `the later of` `start date` `end date`
```

The call renders as "the later of start date and end date". The same function named `` `maximum` `` renders as "maximum with start date and end date".

**Let control flow stay structured.** `CONSIDER`, `IF`/`THEN`/`ELSE` and `AND`/`OR` render as indented outlines, not run-on sentences, so keep the operative logic where the renderer can see it:

```l4
DECLARE Status IS ONE OF Paid, Overdue
DECLARE Claim HAS `status` IS A Status

GIVEN claim IS A Claim
GIVETH A STRING
`the reminder` MEANS
    CONSIDER claim's `status`
    WHEN Paid    THEN "none"
    WHEN Overdue THEN "send a reminder"
```

renders as

```
• The reminder is determined by:
    depending on the claim's status:
    - if it is Paid: none
    - if it is Overdue: send a reminder
```

**Keep arithmetic as arithmetic.** Numeric expressions render as formulas, with `+ − × ÷` and parentheses, not as "the sum of the product of …":

```l4
`base rent`      MEANS 1000
`service charge` MEANS 100
`months`         MEANS 12
`deposit`        MEANS 2000

`the total payable` MEANS (`base rent` PLUS `service charge`) TIMES `months` PLUS `deposit`
```

renders as "The total payable equals (base rent + service charge) × months + deposit."

**Group rules into titled sections.** `` § `Name` `` starts a section and `` §§ `Name` `` a subsection (`§§§` goes deeper). Every declaration after a marker belongs to that section until the next marker. Sections become headings in the rendered document and entries in its table of contents:

```l4
DECLARE Person HAS `age` IS A NUMBER

§ `Eligibility`

GIVEN `the applicant` IS A Person
GIVETH A BOOLEAN
DECIDE `the applicant` `qualifies` IF
    `the applicant` `is of working age`

§§ `Age requirements`

GIVEN `the applicant` IS A Person
GIVETH A BOOLEAN
DECIDE `the applicant` `is of working age` IF
    `the applicant`'s `age` AT LEAST 18
```

With **Number sections** turned on in the Render tab (or `--number-sections` on the command line), the headings are numbered: `§ 2  Eligibility`, then `2.1  Age requirements`. A file with no section markers is still grouped into automatic **Definitions** and **Provisions** sections, but your own markers let you name and order the parts the way a reader of the contract or statute expects.

---

## `@nlg` annotations

When names and shape are not enough (a recursive helper, a term of art, a formula you would rather state in words), add an `@nlg` annotation. It is the natural-language form of the definition and replaces the generated sentence.

Write `@nlg` at the end of the definition's line, after the name and inputs, with the body on the next line. Inside the sentence, `%name%` is a slot for an input; an input whose name has spaces keeps its backticks: ``%`the principal`%``.

```l4
GIVEN x IS A NUMBER
      y IS A NUMBER
GIVETH A NUMBER
`bigger` x y @nlg whichever is larger of %x% and %y%
  MEANS IF x >= y THEN x ELSE y

`start date` MEANS 3
`end date`   MEANS 7
`the deadline` MEANS `bigger` `start date` `end date`
```

Each slot is filled with the input's name in the definition itself, and with the actual argument at each call:

```
• Bigger means whichever is larger of x and y.
• The deadline means whichever is larger of start date and end date.
```

A slot is **tight**: `%amount%`, with no spaces inside the delimiters. That is
what keeps a written-out percentage from being mistaken for one. In

```l4
@nlg a 5% levy on %amount%
```

the `%` after `5` is ordinary text, because `% levy on %` has spaces inside it
and so is not a slot; `%amount%` still is one. Where a percent sign would end up
flush against a word — `5%levy` — wrap it in backticks (`` `5%` ``) or spell it
out ("5 percent"), either of which puts it beyond doubt.

**It replaces the body.** A function with `@nlg` renders as its sentence, not as its implementation. That is what makes recursive library functions readable; the prelude's `filter` has `@nlg the items of %list% for which %f% holds`, so a call reads as a sentence instead of exposing the recursion.

| Situation                                            | Why `@nlg` helps                                   |
| ---------------------------------------------------- | -------------------------------------------------- |
| Recursive or higher-order helpers                    | Describes the result, hides the implementation     |
| A formula better said in words                       | "the pro-rated premium" instead of the arithmetic  |
| Terms of art                                         | Matches the exact statutory or contractual wording |
| A name that cannot be both valid code and good prose | Separates the two                                  |

Tips:

- Use only the function's own inputs as slots, and write the sentence so that it reads well with each slot as a noun phrase.
- Try names and shape first. An `@nlg` sentence can drift away from the logic it describes, so use it where it pays off.
- One sentence per definition. For branching prose, let `CONSIDER` or `IF` render as an outline instead.

---

## One encoding, two documents

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
That is about direction only — the document is _labelled_ `he-IL` just when the module actually carries `@nlg:he-IL` renderings, since (above) a tag nothing renders does not relabel; `--lang he-IL` on a module whose heralds are tagged `he` gives you `lang="he"` and says so.

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
An empty value, one with anything in it but letters, digits and `-`, and one whose `-`-separated parts are not each one to eight characters (`he-`, `he--IL`) are refused with a message instead of being pasted into the attribute.
That is a check on the shape of a tag rather than a check against the register of real ones: `xx-Qrst` is shaped like a language tag and is accepted.

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

Before, with short names and no annotation:

```l4
GIVEN p IS A NUMBER
      r IS A NUMBER
      n IS A NUMBER
GIVETH A NUMBER
pmt p r n MEANS p TIMES r DIVIDED BY (1 MINUS EXPONENT (1 PLUS r) (0 MINUS n))
```

This renders as "Pmt equals p × r ÷ (1 − EXPONENT with the sum of 1 and r and the difference between n and 0)."

After, with descriptive names and one `@nlg`:

```l4
GIVEN `the principal`      IS A NUMBER
      `the monthly rate`   IS A NUMBER
      `the term in months` IS A NUMBER
GIVETH A NUMBER
`the monthly repayment` `the principal` `the monthly rate` `the term in months` @nlg the level monthly repayment on %`the principal`% at %`the monthly rate`% over %`the term in months`%
  MEANS     `the principal` TIMES `the monthly rate`
        DIVIDED BY (1 MINUS EXPONENT (1 PLUS `the monthly rate`) (0 MINUS `the term in months`))

`the loan`          MEANS 10000
`the interest rate` MEANS 0.01
`the term`          MEANS 12
`the repayment`     MEANS `the monthly repayment` `the loan` `the interest rate` `the term`
```

Now the call renders as "The repayment means the level monthly repayment on the loan at the interest rate over the term.", a sentence a lawyer can check.

---

## Refine the style with Legalese AI

The renderer gives a faithful, deterministic baseline: the same input always gives the same prose, and it never adds facts. House style, tone and jurisdiction conventions are editorial choices that deterministic rules should not make.

Once the rendered output is accurate, Legalese AI can apply **drafting policies** to it: reusable style rules such as "use plain English", "prefer the active voice", "expand defined terms on first use", or a firm's house style. It rewrites the rendered prose to match, while staying anchored to the deterministic output so the meaning is kept.

Names, shape and `@nlg` get the content right; drafting policies get the style right. See [Draft rules with Legalese AI](../llm-integration/composing-l4-with-ai.md) for how Legalese AI fits into writing rules.
