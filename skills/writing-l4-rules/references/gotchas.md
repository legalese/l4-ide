# L4 Gotchas

Things that will trip up a general-purpose large language model because they are not in any other language and are not visible in a naïve reading of the syntax.

**Canonical references:**

- Full keyword glossary: <https://legalese.com/l4/reference/GLOSSARY.md>
- Syntax overview: <https://legalese.com/l4/reference/syntax.md>

---

## Contents

- [`DECIDE`: IS vs MEANS vs IF](#decide-is-vs-means-vs-if)
- [The ditto operator `^`](#the-ditto-operator-)
- [Asyndetic operators `...` and `..`](#asyndetic-operators--and-)
- [Section markers `§` and `§§`](#section-markers--and-)
- [Computed fields in records](#computed-fields-in-records)
- [Backtick identifiers and mixfix](#backtick-identifiers-and-mixfix)
- [Layout sensitivity](#layout-sensitivity)
- [No implicit coercion](#no-implicit-coercion)
- [The `daydate` month-subtraction footgun](#the-daydate-month-subtraction-footgun)
- [Genitive field access with `'s`](#genitive-field-access-with-s)
- [`AKA` aliases](#aka-aliases)
- [`LET … IN` vs `WHERE`](#let--in-vs-where)
- [`@export` placement](#export-placement)
- [Annotation fence](#annotation-fence)
- [A library's own example definitions are visible to importers](#a-librarys-own-example-definitions-are-visible-to-importers)
- [NLG and reference annotations](#nlg-and-reference-annotations)
- [`EVERY … WHO elem` is deprecated and nothing tells you](#every--who-elem-is-deprecated-and-nothing-tells-you)
- [Four errors that do not point at the fix](#four-errors-that-do-not-point-at-the-fix)

---

## `DECIDE`: IS vs MEANS vs IF

L4 has three decision-defining forms. All are valid; pick the one that reads best for the rule you are writing.

```l4
-- Value or computed expression — use IS or MEANS
GIVEN x IS A NUMBER
DECIDE double x IS x TIMES 2

GIVEN n IS A NUMBER
DECIDE factorial n MEANS
    IF n EQUALS 0 THEN 1 ELSE n TIMES factorial (n MINUS 1)

-- Boolean-returning rule — use IF
GIVEN age IS A NUMBER
      income IS A NUMBER
DECIDE `is eligible` IF
    age AT LEAST 18 AND income GREATER THAN 30000

-- DECIDE is optional when using MEANS
GIVEN x IS A NUMBER
double x MEANS x TIMES 2
```

Rule of thumb: **`IF` for booleans, `IS` for values and records, `MEANS` when omitting `DECIDE` entirely.**

Reference: <https://legalese.com/l4/reference/functions/DECIDE.md>

---

## The ditto operator `^`

`^` copies the corresponding token from the line above, column-for-column. It is used to flatten repeated chained comparisons without repeating the subject.

```l4
GIVEN phase IS A STRING
sky_is_romantic phase MEANS
       phase EQUALS "full moon"
   OR  ^     ^       "new moon"
   OR  ^     ^       "new"
   OR  ^     ^       "full"
```

Each `^` stands for the token at the same column on the previous line. Without ditto you would repeat `phase EQUALS` four times. This is a legal-drafting affordance, not a general-purpose operator.

**What ditto does and does not buy.** It does **not** shorten a line: a `^` is padded out to exactly the width of the token it replaces, so the column layout — and therefore the line length — is unchanged by construction. Measured on a real 36×9 salary table, converting a row to ditto saved _one_ character, and that was a rounding artefact. What it buys is data/ink: the repeated tokens become whitespace, so the eye lands only on what varies. Reach for it to make a table readable, never to make it fit. The lever that actually narrows a wide row is positional `OF` construction (320 characters → 184 on that same row).

**The traps, all verified against the `l4` binary. Sort them by whether they are loud or silent — that asymmetry is the whole risk profile of this operator.**

Loud, so cheap:

- **`^` copies one token.** `AT MOST` is two, so a single caret beneath it copies `AT` and the parser then rejects the caret outright. Write two-word operators out in full on every row.
- **"The line above" means the previous _token-bearing_ line.** Blank lines and comment-only lines are skipped, so you may separate the rows with either — `jl4/examples/ok/ditto.l4` does exactly that and says so. But any line carrying real tokens becomes the new reference line, and a type signature is the one that catches people: putting `GIVETH A NUMBER` between two rules makes the caret beneath it resolve against `GIVETH A NUMBER`. This is the first thing a model hand-writing two adjacent rules will hit.

Silent, so expensive — these are the ones to design against:

- **A backtick name dittoes whole, which quietly answers with the wrong field.** `` `at rank 2` `` cannot ditto down from `` `at rank 1` ``; there is no sub-token to copy, so the caret copies the earlier field name _entire_ and the rule reads the wrong column:

```l4
`amount` `the row` `the rank` MEANS
    BRANCH IF `the rank` AT MOST 1 THEN `the row`'s `at rank 1`
           OTHERWISE                    ^        ^  ^
```

The `OTHERWISE` arm answers with rank 1 for every rank there is — zero errors, exit 0, and on a salary table it is the wrong money. Whole names ditto; parts of names never do.

- **Column position is semantics, so editing a line silently rebinds every caret below it.** Nothing warns you:

```l4
small MEANS 10
big   MEANS 90
c1 MEANS small AT LEAST 5
c2 MEANS ^     AT MOST  50   -- copies `small`; c2 is TRUE
```

Change line 3's subject to `big` — leaving the caret alone — and `c2` becomes FALSE, with no error and no warning, because the caret still resolves, just to a different token. If a caret's column lands on _nothing_, you get a loud `unexpected ^`; if it lands on the _wrong_ token you may get nothing at all. **So generate aligned tables from a script rather than hand-typing them**, and after editing any line in a dittoed block, re-check every caret beneath it.

`l4 format` is not a threat to this style: measured on a real 36×9 dittoed file, its output is byte-identical, 79 carets in and 79 out.

---

## Asyndetic operators `...` and `..`

The ellipsis operators are implicit conjunction/disjunction — they let you write a list of conditions without repeating `AND` / `OR` on every line.

- `...` (three dots) — implicit **AND**
- `..` (two dots) — implicit **OR**

```l4
DECIDE `eligible for discount` IF
    `existing customer`
    ...
    `has clean payment history`
    ...
    `spent at least 1000 this year`
-- equivalent to: cond1 AND cond2 AND cond3
```

Use them when a clause list should read as a bulleted list rather than a prose "A and B and C".

---

## Section markers `§` and `§§`

`§` and `§§` are **structural section markers**, not comments. They are how you preserve the hierarchy of the source legislation or contract in the L4 file:

```l4
§ `Part I — Eligibility`

§§ `1.1 Definitions`

DECLARE Applicant HAS
    ...

§§ `1.2 Conditions for coverage`

GIVEN applicant IS An Applicant
DECIDE `coverage applies` IF
    ...
```

They compile away but show up in the IDE outline and in generated documentation. Use them whenever the source text has sections — it is how the isomorphic-encoding principle is expressed.

---

## Computed fields in records

A record's `HAS` block can include fields whose value is **computed** from other fields via `MEANS`. These are like derived attributes / methods / computed properties in other languages.

```l4
DECLARE Employee HAS
    -- stored fields
    `name`          IS A STRING
    `date of birth` IS A NUMBER
    `current year`  IS A NUMBER
    -- computed fields
    `age`           IS A NUMBER
        MEANS `current year` - `date of birth`
    `adult`         IS A BOOLEAN
        MEANS `age` AT LEAST 18
```

**Rules:**

- Computed fields are accessed with `'s` just like stored fields: `` employee's `age` ``.
- They are **pure** — they may only reference sibling fields of the same record. You cannot add `GIVEN` parameters to a computed field.
- When constructing with `WITH`, you supply **only the stored fields**; computed fields are derived automatically.
- Cycle detection is automatic; the compiler rejects any dependency cycle between computed fields.

Reference: <https://legalese.com/l4/reference/types/DECLARE.md>

---

## Backtick identifiers and mixfix

Any identifier containing spaces or punctuation must be backtick-quoted:

```l4
`the applicant`
`valid identification`
`the person must not sell alcohol`
```

**Mixfix notation** lets the function name intersperse with its arguments. The argument positions are the backtick-quoted parameter names:

```l4
GIVEN employee IS AN Employee
      employer IS A Company
GIVETH A BOOLEAN
`employee` `works for` `employer` MEANS ...

-- Called as: `Alice` `works for` `Acme Corp`
```

Mixfix is the reason L4 code can read like legal prose. Use it for binary-ish relations. Use normal prefix-style function names for everything else.

**A backticked segment may begin with punctuation** — a comma, a semicolon, a colon, an opening
bracket — which is what lets a call read as one clause of English rather than a run of unlabelled
arguments. All four were measured at the head of a segment and all four check (probe
`g12-mixfix-punctuation.l4`, exit 0, four assertions satisfied):

```l4
`an expense of` n `, reasonably incurred being` r
`the total of` a `, and` b `; and` c `: and` d
`the fee for` n `hours (at the first band); and` m `hours (at the second band)`
`clause 9: the cap on` n
```

Two limits on what a segment can be:

- **No segment may contain `--`.** That is the comment marker and backticks do not protect it: the
  definition silently ends at the segment before it, so the head is defined at the wrong arity and
  the rest of the line becomes a free identifier. You get two errors and neither says "comment"
  (probe `g12b-mixfix-comment-marker.l4`, exit 1).
- **A pattern with exactly ONE argument may not end with a keyword segment.**
  `` `the sum of` n `rounded down` `` registers `` `the sum of` `` at arity 1 and leaves
  `` `rounded down` `` undefined; the call site then reports `expects 1 argument, but you are
applying it to 2 arguments here` (probe `g12c-mixfix-one-arg-trailing.l4`, exit 1). A trailing
  segment is fine once there are two or more arguments —
  `` `the sum of` n `and` m `rounded down` `` checks (probe `g12d`, exit 0). With one argument,
  either drop the trailing segment or move its words into the head.

Entry 6.10 of the phrasebook,
[source-patterns/06-parties-and-things.md](source-patterns/06-parties-and-things.md#e6-10), shows
what these punctuated segments buy you: a named fact pattern an `#ASSERT` can be applied to on one
line.

---

## Layout sensitivity

L4 is layout-sensitive like Python and Haskell. **Indentation determines block structure.** There are no braces or semicolons.

```l4
GIVEN x IS A NUMBER
GIVETH A STRING
classify x MEANS
    IF x GREATER THAN 0
    THEN "positive"
    ELSE IF x EQUALS 0
        THEN "zero"
        ELSE "negative"
```

The `THEN`/`ELSE` alignment and the indentation of the inner `IF` matter. If you see a "parse error: unexpected token", check indentation first.

---

## No implicit coercion

L4 never silently converts between types. `"42" + 1` is a type error. Use the explicit coercions (`TOSTRING`, `TONUMBER`, `TODATE`, `TOTIME`, `TODATETIME`, `TRUNC`) from [builtins.md](builtins.md). `TONUMBER`/`TODATE`/etc. return `MAYBE` — you must pattern-match with `CONSIDER` to extract the value.

---

## The `daydate` month-subtraction footgun

After `IMPORT daydate`, you build calendar dates with `YMD year month day` (recommended for new code, BOUNDS-CHECKED) or the little-endian `Date day month year` (lenient). **This footgun is `Date`-specific**: `YMD` refuses an out-of-range month instead of clamping — `YMD 2025 (3 MINUS 6) 1` stops on `` `YMD refused an out-of-range month or day` `` where `Date 1 (3 MINUS 6) 2025` silently clamps to January 2025. Use `Date` when you _want_ rolling month arithmetic; use `YMD` for literals.

The constructor does **not** normalise a non-positive month by rolling back a year — it **clamps a month `≤ 0` to January of the same year**. So `Date 1 (3 MINUS 6) 2025` is **January 2025**, _not_ September 2024. Month **overflow** past 12, by contrast, _does_ roll forward correctly: `month PLUS 6` on a December date lands in the next year.

```l4
-- ✘ WRONG — "6 months before March 2025" by subtracting months:
Date 1 (3 MINUS 6) 2025          -- clamps to January 2025, NOT September 2024

-- ✔ RIGHT — compute "N months before X" by ADDING to the EARLIER date,
--           then comparing, so the subtraction never happens:
`became landlord no more than 6 months before proceedings` MEANS
        Day `proceedings commenced date`
    AT MOST Day `six months after became-landlord date`
    WHERE
        `six months after became-landlord date` MEANS
            Date (DATE_DAY   `became-landlord date`)
                 (DATE_MONTH `became-landlord date` PLUS 6)   -- overflow rolls forward, correctly
                 (DATE_YEAR  `became-landlord date`)

-- ✔ RIGHT — to go backward a whole year, decrement the YEAR
--           (this can never produce month ≤ 0, so the clamp never fires):
Date (DATE_DAY x) (DATE_MONTH x) (DATE_YEAR x MINUS 1)
```

**Rule of thumb:** never compute "N months before X" by subtracting months from `X`. Either **add** N months to the earlier date (`DATE_MONTH earlier PLUS N`) and compare, or step back a whole year via `DATE_YEAR … MINUS 1`. The "≤ 6 months before proceedings" tests in the Housing Act corpus (`ground-2ZC.l4`, `ground-2ZD.l4`) do exactly this.

---

## Genitive field access with `'s`

Field access uses the English genitive, not a dot:

```l4
person's age
company's ceo's name          -- chaining
application's employee's nationality
```

This is the ONLY form of field access. No `.field`, no `->`, no `[]`.

---

## `AKA` aliases

`AKA` gives an existing name an alternate name. Both can be used interchangeably:

```l4
GIVEN p IS A Person
DECIDE `is of legal age` p IS p's age AT LEAST 18
    AKA `has reached majority`

-- both of these now work:
#ASSERT `is of legal age`    `Alice`
#ASSERT `has reached majority` `Alice`
```

Use it when the source text uses two names for the same concept and you want both to be searchable.

Reference: <https://legalese.com/l4/reference/functions/AKA.md>

---

## `LET … IN` vs `WHERE`

Both introduce local bindings. Pick by position:

- **`WHERE`** — trailing. Use for helper definitions read _after_ the main expression.
- **`LET … IN`** — leading. Use for a single binding consumed immediately.

```l4
-- WHERE: trailing helpers
circleArea radius IS pi TIMES radius TIMES radius
WHERE
    pi MEANS 3.14159

-- LET ... IN: inline
LET taxRate MEANS 0.08 IN
    price TIMES (1 PLUS taxRate)
```

---

## `@export` placement

`@export` goes **directly above** the function (before `GIVEN` or the bare function name). Not between `GIVETH` and `DECIDE`.

```l4
-- ✘ Wrong — @export in the middle
GIVEN x IS A NUMBER
GIVETH A NUMBER
@export Square a number
squared x MEANS x TIMES x

-- ✔ Right — @export at the top
@export Square a number
GIVEN x IS A NUMBER
GIVETH A NUMBER
squared x MEANS x TIMES x
```

---

## Annotation fence

All annotations begin with `@`.
On its own line, an annotation applies to the **following** definition; trailing a line, it applies to what is on that line.
`@nlg` follows that rule with two twists — a rule takes it only on the line above, and inside a field list or a `GIVEN` list an own-line annotation describes the field or input **above** it — which the next section measures.
Read it before writing one:

| Annotation | Purpose                                                            |
| ---------- | ------------------------------------------------------------------ |
| `@desc`    | Human-readable description (internal unless paired with `@export`) |
| `@export`  | Mark function for deployment via `jl4-service`                     |
| `@nlg`     | Natural-language-generation hint (for rendering the rule as prose) |
| `@ref`     | Cross-reference to a legal source                                  |
| `@ref-src` | Accepted and ignored (the CSV loading it did was removed)          |
| `@ref-map` | Mapping table for references                                       |

`@ref` and `@ref-map` are the "link this rule to §3.2 of the statute" annotations — use them whenever the source document has stable citations.
An `@ref` on its own line binds to the next syntax node, whatever it is, so it goes above the rule it cites.
Measured with `l4 check` and `l4 ast`: one written under its rule attached to the next rule, with no message; one above a `§` heading attached to the heading.
Two above one rule leave the nearer attached and report the other as unattached, and so does one at the end of a file; both are warnings, and `l4 check` still exits 0.
`@ref-src` is accepted and ignored.
The lexer still reads it and the parser stores nothing from it (`refAdditionalP` in `jl4-core/src/L4/Parser.hs`); the CSV loading it did was removed, as `specs/done/REF-ANNOTATION-SPEC.md` records.
Measured: `@ref-src this-file-does-not-exist.csv` passes `l4 check` with `Check succeeded` and no diagnostic.
To tie an `@ref` to lines of a raw source text with `src:` locators that a script can check, see [source-locators.md](../../encoding-a-subject/references/source-locators.md) in the `encoding-a-subject` skill.

### `@nlg` placement: a rule takes it on the line above, a name takes it trailing — and one leak

Fuller treatment of what to put IN a herald — `%param%` slots, when a sentence replaces the
implementation, and the three levers before you reach for one — is in
[`doc/tutorials/natural-language-functions/optimising-natural-language-generation.md`](../../../doc/tutorials/natural-language-functions/optimising-natural-language-generation.md).
This section is only about WHERE it goes and what it will not do. Every claim below was measured
on 2026-09-21 on a build of `unstable` at `debf44d34`, which carries both `legalese/l4-ide#433`
(attachment) and `#435` (field lists); the one-file probe is the measurement, not the merge log.
The exception is the `GIVEN`-list paragraphs below, which were measured on 2026-10-02 at `e0366fd7f`.

**A rule's herald goes on its own line, immediately above the definition.** That is the only
placement that reaches a rule:

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
@nlg:he שורה משלה
DECIDE `כפול` n IS n TIMES 2
```

`l4 nlg --lang he` prints `שורה משלה עם 21`.

**Trailing the definition line does NOT reach the rule**, and this is the trap, because it looks
like it should. `DECIDE f n IS n TIMES 2 @nlg …`, the same with `MEANS`, and the head-line form
with the body on the next line all render the rule as its bare name. What happens to the herald
depends on what comes next, and only one of the two outcomes is loud:

- nothing annotatable follows → `Not attached to any valid syntax node`, a parser diagnostic
  pointing at the herald. Loud, and correct.
- a `DECLARE` follows → the herald silently becomes THAT type's herald. Measured: a rule's
  trailing `@nlg SHOULD-BE-ON-RULE` rendered as `SHOULD-BE-ON-RULE where `x` is 1` on the
  record declared beneath it, with a clean typecheck and no diagnostic. This is the silent one.

**"Immediately above the definition" means after `GIVETH`, not above `GIVEN` — and the trap here
is silent, not loud.** `GIVEN`/`GIVETH` read like part of the rule, so `@nlg` above `GIVEN` looks
right and is the mistake to expect from anyone (a person or a model) who hasn't hit this before.
It does not attach to the rule, and it usually does not warn either:

```l4
DECLARE Teacher HAS
    name IS A STRING

-- WRONG: above GIVEN, not above the definition
@nlg the only one
GIVEN t IS A Teacher
GIVETH A NUMBER
`f of` t MEANS 1
```

`l4 check` is clean here — no diagnostic at all.
On an `l4` older than the fix for smucclaw/l4-ide#997, `l4 nlg` on ``#EVAL `f of` (Teacher WITH name IS "Alice")`` printed `` `f of` with `Teacher` where the only one is Alice ``: the rule is its bare name, and "the only one" has been captured BACKWARD by the record's last field, `name`, which it now labels (confirmed with `l4 ast`).
A newer `l4` gives the record's last field a column test (below), so this exact case is now reported (`Not attached to any valid syntax node`) and `name` renders as itself.
The capture is still silent when what precedes the herald is something else that ends in a name: an `IMPORT`, an enum, a type synonym, an opaque type, or a rule whose body ends in a name; it reaches as far back as the `IMPORT` when nothing closer does.
After a rule whose body ends in a literal it warns "Not attached".
It only failed loudly in the rarer case where nothing at all preceded it to capture — which is why one real encoding shipped ~230 heralds with twelve of them silently dead and only found out via a `check`-clean corpus, because the loud case never fired for eleven of the twelve (smucclaw/l4-ide#976).
Move the herald to after `GIVETH`, and it attaches correctly regardless of what precedes it — after a `DECLARE`, after another bare rule, or first in the file.

**So do not trust `l4 check`'s silence as evidence a herald attached.** The only real check is `l4
nlg` (or `l4 ast`) on a case that exercises the rule, confirming the herald's own text — not the
bare fallback — comes out the other end.

**A parameter's herald trails its own line.** `GIVEN n IS A NUMBER @nlg the count` describes `n`
(`#433`; before it, the `NUMBER`). It describes the parameter, not the rule — a rule whose only
herald is on a parameter line still renders as a bare name.

**Or it goes on its own line BELOW the parameter** (ruled 2026-10-02: a `GIVEN` list is a column, like a field list).
Under a parameter that has another after it, any column works, because the next parameter bounds it.
Under the LAST parameter, with no `GIVETH` before the rule, the same line is also the line above the rule, so the column decides.
Indented further than the `GIVEN` keyword, it is the parameter's.
At the keyword's column or left of it, it describes what follows: the rule's sentence, or, with a `GIVETH` next, nothing at all, with a "Not attached" warning.

```l4
GIVEN floor  IS A NUMBER
      amount IS A NUMBER
      @nlg the sum of money
@nlg the claim of %amount% is over %floor%
DECIDE `is large` IF amount GREATER THAN floor
```

`l4 nlg` writes ``#EVAL `is large` WITH floor IS 100, amount IS 200`` as ``the claim of `amount` is over `floor` where `floor` is 100 and the sum of money is 200``: the first annotation is `amount`'s, the second the rule's.
The column is the `GIVEN` keyword's, not column 1, so a section `GIVEN` indented under its heading, or a `GIVEN` inside a `WHERE`, reads the same way.
A `DECIDE`, `ASSUME`, `DECLARE` or `YIELD` written on a line of its own ends the list, so an annotation under one of those is not the parameter's.

The column is all it reads, and three consequences are silent:

- A rule's sentence indented even one space past `GIVEN`, under the last parameter, becomes that parameter's gloss, and every projection changes with it: `l4 nlg`, `l4 render` and the Blawx export.
- A `DECIDE` indented past its own `GIVEN`, with its herald lined up above it, gives that herald to the last parameter.
- When the head repeats the inputs (`` `is large` amount MEANS … ``), the head is where the input is bound and a gloss on the `GIVEN` name is rendered nowhere, so an annotation indented under the last parameter vanishes (smucclaw/l4-ide#995).
  Write the rule's sentence at the `GIVEN` keyword's column, or between `GIVETH` and the head at any indentation; above the head but indented past `GIVEN`, with no `GIVETH`, it is still the last parameter's.

A trailing gloss and an own-line one on the same parameter, in the same language, collide: L4 warns and drops both.
A `TYPICALLY` default takes no annotation, so a gloss trailing it describes the parameter whatever the default is.
An `l4` older than smucclaw/l4-ide#994 let a default that is a name such as `FALSE`, `EMPTY` or `NOTHING` take the gloss, silently; against one of those, put the gloss on the line below.
One shape is reported rather than read: a gloss at the `GIVEN` column written between a parameter's type and a `TYPICALLY` on the next line is inside the parameter, so it warns "Not attached" instead of becoming the rule's sentence.
An `ASSUME` has the same column test: an `@nlg` indented under it, or trailing it or its `TYPICALLY` default, is its own, and one at the margin is the next declaration's.
An `l4` older than smucclaw/l4-ide#994 let an `ASSUME` with no default take a herald at the margin below it, and lose a gloss trailing a default that is a name.
In a rule whose head has a pattern argument (`DECIDE fib 0 IS 0` — one clause is enough), no `@nlg` attaches anywhere, in the `GIVEN`, on the head or above it; each one warns "Not attached" (smucclaw/l4-ide#996).

Before the ruling, an annotation under the last parameter was dropped with a warning when a `GIVETH` followed, and became the rule's sentence when none did (colliding, with a warning, if the rule had a sentence of its own).
One under an earlier parameter with a `TYPICALLY` default landed on the next parameter, or on the default when that was a name such as `TRUE`, and a gloss trailing a number or a string default went past its parameter too.

**A record field's herald goes on its own line BELOW the field** (`#435`, ruled 2026-09-21: inside a field list an annotation on its own line describes the field above it, an exception to "own line describes what follows", because a field list is a column).
Trailing the field's line reaches the TYPE, not the field, and that is deliberate — a field and its type can be glossed separately on one line, and letting the field claim the whole line makes the two collide:

```l4
DECLARE Payslip
    HAS base  IS A NUMBER   @nlg the basic salary
        bonus IS A NUMBER
        @nlg the bonus
```

`l4 nlg` prints ``where `base` is 100 and the bonus is 5``: the first annotation describes `NUMBER`, so `base` renders bare, and the second describes `bonus`.
Never end an `@nlg` line with a `--` comment: the annotation runs to the end of the line, and the comment becomes part of the prose.

**The last field takes a herald from a line below only when it is indented past where the `DECLARE` starts**, as the last input of a `GIVEN` list does.
One at that column or to its left is the NEXT declaration's, as it is anywhere else in a file, and a field before the last is bounded by the field after it.
So indent the fields: a field written at the margin, or on the `DECLARE`'s own line, takes no herald from a line below.
It holds for the last field of the last constructor of an enum too.
An `l4` older than the fix for smucclaw/l4-ide#997 had no such test: a record's last field took an `@nlg` between it and the next rule at any column, silently, whenever no `GIVEN` or `GIVETH` sat between them — including a herald written above the rule's own `GIVEN`, as in the `Teacher` example above (smucclaw/l4-ide#976).
A last field with a literal `TYPICALLY` default escaped that only because its default cut its name off.

A field with a `TYPICALLY` default is a field like any other: the default takes no annotation, so a herald below it describes the field and one trailing the line reaches its type (smucclaw/l4-ide#997).
Before that fix the herald went to the next field, or was dropped silently when the default was a name such as `TRUE` or an enum constructor; an `l4` older than it still does that, so a `BOOLEAN TYPICALLY TRUE` field glossed on the line below renders bare there.

**A constructor that has fields takes its own herald BETWEEN its name and `HAS`.**
The field list is a column (above), so a herald below the last field is that field's, not the constructor's, and a herald above the constructor name is the previous constructor's.
Put `HAS` on a continuation line to make room:

```l4
DECLARE Penalty IS ONE OF
    NoPenalty
    Custodial
        @nlg a custodial penalty
        HAS years IS A NUMBER
        @nlg the term in years
```

A herald written below `years` alone describes `years`, and both below it collide on `years` with a warning.

> **A corpus written before 2026-09-19 will not reflect any of this.** Until `#433` merged, an
> own-line herald under a `GIVEN` was captured by the signature and the rule rendered as a bare
> name — silently, with a clean typecheck. Three independent Hebrew encodings written days before
> it produced 334 heralds, 289 of them own-line, one of which rendered; and until `#435` the same
> encodings' 100 below-the-field heralds rendered nothing either. If an older encoding's renderings
> look absent, re-run it on a current binary before touching a placement.

### `@nlg:xx` and `@lang` — several renderings, selected by language

A herald takes a language subtag, and **a name may carry more than one**:

```l4
@lang he
GIVEN n IS A NUMBER
@nlg:he שורה משלה
@nlg:en the doubling rule
DECIDE `כפול` n IS n TIMES 2
```

- `l4 nlg FILE --lang he` → `שורה משלה עם 21`
- `l4 nlg FILE --lang en` → `the doubling rule with 21`

`l4 render` takes `--lang` too, which is the flag that produces a bilingual set of **documents**
rather than linearized prose. `@lang he` at module level declares what an **untagged** `@nlg` in
that module means, so an existing monolingual file gets labelled without touching every herald.

**One thing a tag does not buy, and it surprises people.**
A tag names the _rendering_; **it does not localise the words L4 puts around it**, and `@lang` does not either.
Those words — `with`, "is equal to" — follow `l4 nlg --lang` instead: the module above prints `עם` with `--lang he`, and `שורה משלה with 21` with no `--lang` at all.
`l4 render` does not localise them yet, so a right-to-left document still has English scaffolding (`means`) between its Hebrew renderings.

**Non-Latin identifiers need no annotation at all.** L4 takes Hebrew — and by the same rule any
`Lo`-category script — in every name position: bare and backticked names, types, constructors,
record fields, mixfix operators, `§` titles. The genitive `'s` works after one, and `l4 format`
round-trips byte-identically. Two limits:

- **Bidi control characters are a lex error inside backticks** (U+200E, U+200F, U+202A–U+202E,
  U+2066–U+2069). A right-to-left file relies on the viewer's bidi algorithm, so mixed-direction
  lines that look wrong in an editor are usually right in the file. Never "fix" one with a mark.
- **Keep combining marks out of identifiers.** They are legal, but L4 counts source columns in
  codepoints, so niqqud makes a column count disagree with a table formatter's — and the symptom
  is a mis-aligned ditto caret, which is the silent kind.

---

---

## NLG and reference annotations

In addition to the `@`-prefixed annotations above, L4 recognises two **inline** annotation bracket forms inside identifiers and expressions:

- `[...]` — NLG inline annotations (hints for rendering the rule as natural language)
- `<<...>>` — reference annotations (inline citations)
- `%...%` — NLG delimiter (wraps a phrase for the NLG renderer)

These are rare in hand-written rules but appear in machine-generated or NLG-bidirectional files. If you see them in existing code, leave them alone — they are meaningful.

---

## A library's own example definitions are visible to importers

A library file may carry fixtures for its own tests, and `IMPORT` brings those names in with the
rest. A file that imports `hierarchy` and defines its own `amended` fails with
`There are multiple definitions for the identifier` naming `hierarchy.l4:298`, one of the
library's own examples (measured 2026-09-05). If a plain name collides with something you did not
define, look in the library you imported, and rename yours.

---

## `EVERY … WHO elem` is deprecated and nothing tells you

This one belongs here rather than only in the regulative reference, because it is the shape a model
trained on older L4 will reach for by default and **no part of the toolchain objects**: it parses,
type-checks, runs, and produces the right answer.

```l4
EVERY Tenant t
    WHO elem t tenants          -- DEPRECATED 2026-09-08. Silent. Do not write it.
```

Before the `IN` clause existed, the group a quantified obligation ranges over — its **roll** — had to
be smuggled into the `WHO` condition as an `elem` test, and the evaluator would pick the list back
out. Since 2026-09-08 the roll is said outright, and the older spelling is deprecated: still
running, not scheduled for removal, and **with no warning of any kind** — no diagnostic, no note in
the trace, no editor mark. Documentation is the only thing that will tell you, which is why it is
written down twice.

The rewrite is mechanical: `WHO elem t xs` becomes `IN xs`, and `WHO elem t xs AND p` becomes
`IN xs WHO p`.

An `elem` condition **beside** an `IN` roll is not this trap — it is an ordinary narrowing
condition and is fine. Only an `elem` standing in for a missing roll is the deprecated form.

See [regulative.md](regulative.md#do-not-write-the-deprecated-who-elem-roll) for why it was
deprecated and what else `EVERY` needs.

---

## Four errors that do not point at the fix

Each of these fails loudly, but the message names a symptom somewhere other than the fix, so the usual response is to edit the wrong thing.
Measured 2026-09-26 on a 23 September 2026 build of `unstable`; the 7 September 2026 prerelease gives the same messages.

**A `LIST OF` parameter in a comma-separated `GIVEN`.**
`GIVEN xs IS A LIST OF NUMBER, n IS A NUMBER` fails with `unexpected IS`, pointing at the parameter _after_ the list: the comma is read as continuing the list type.
Put each parameter on its own line under one `GIVEN`, with no commas — that layout is always safe:

```l4
GIVEN xs IS A LIST OF NUMBER
      n  IS A NUMBER
```

**There is no `++`.**
`LIST 1 ++ LIST 2` fails with `expecting operator char`.
Join two lists with `append xs ys`, which comes from `IMPORT prelude` — without the import the message is `I could not find a definition for the identifier append`.
To put one element in front of a list, `x FOLLOWED BY xs`.

**`WHEN JUST _` does not parse.**
It fails with `unexpected '_'`: there is no wildcard after `JUST`.
Name the value even if you do not use it — `WHEN JUST x THEN TRUE` checks cleanly.

**No partial application.**
``map (`add` 1) xs``, where `` `add` `` takes two inputs, fails with a message about `map`'s first input having the wrong type (a `NUMBER` where a `FUNCTION` was expected), or, outside `map`, that `` `add` `` "expects 2 inputs, but here it is given 1 input".
Write the function out:

```l4
map (GIVEN x YIELD `add` 1 x) xs
```

Two older traps from the same family now explain themselves, so they are not listed above: a `GIVEN` whose names are in a different order from the definition's parameters, and `NOT` swallowing the rest of a line (`NOT FALSE AND FALSE`) — both now fail with a message that explains the problem.

---

## See also

- <https://legalese.com/l4/reference/GLOSSARY.md> — complete keyword list
- <https://legalese.com/l4/reference/syntax.md> — layout rules, comments, identifiers
- <https://legalese.com/l4/reference/cheat-sheet.md> — translation from other languages
