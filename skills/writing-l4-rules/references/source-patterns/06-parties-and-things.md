# 6. Parties and things

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

Every snippet below was run on the current binary before it went in. The **Not** blocks were run
too: where one produces a diagnostic, the diagnostic is quoted; where one compiles and quietly gives
a wrong answer, that is said, because a shape that type-checks is the more dangerous of the two.

<a id="e6-1"></a>

## 6.1 "the Company shall pay the Contractor" — two parties, one act

**If the source says**

> `` PARTY   `The Borrower` ``, `` MUST    `pay monthly installment to` ``, `` EXACTLY `The Lender` ``
>
> — `jl4/examples/legal/promissory-note.l4:90-92`, the borrower's payment obligation. The comment
> beside it: "This function/action is defined in the prelude and expects an object of type Lender
> and a Money".

**It is doing** naming a **performer** and a **recipient**. English puts the performer first
("the Company shall pay the Contractor") and L4 keeps that order: an action record's **first
actor-typed field is the performer**, and the obligation binds that party alone. The other actor
fields are participants — recorded as data, not obligated.

**Write** the cast as one type, the act as a record that carries who does it to whom, and the
obligation over both.

```l4
DECLARE Party IS ONE OF
    `the Company`
    `the Contractor`

DECLARE Act HAS
    by      IS A Party        -- first actor field: the performer
    to      IS A Party        -- a participant, recorded but not obligated
    amount  IS A NUMBER

`pay the monthly fee` MEANS Act OF `the Company`, `the Contractor`, 8000

GIVETH A DEONTIC Party Act
`clause 4.1 -- the Company shall pay the Contractor` MEANS
    PARTY  `the Company`
    MUST   `pay the monthly fee`
    WITHIN 30
```

`#TRACE` it against an event stream to see whether the obligation was discharged:

```l4
#TRACE `clause 4.1 -- the Company shall pay the Contractor` AT 0 WITH
    PARTY `the Company` DOES `pay the monthly fee` AT 12
```

→ `FULFILLED`.

**Not** the obligation hung on the party the sentence mentions second.
`` PARTY `the Contractor` MUST `pay the monthly fee` `` is rejected, and the diagnostic names the
performer for you:

```
An actor may only perform its own actions.

  `pay the monthly fee` is performed by `the Company`, not by `the Contractor`.
```

To make the Contractor the performer, build a second act with the Contractor in the first slot —
one action type carries both directions.

**See** [`doc/concepts/legal-modeling/actors-and-actions.md`](../../../../doc/concepts/legal-modeling/actors-and-actions.md)
for the whole of the performer canon, including the two construction styles and what the actor check
does not catch; [regulative.md](../regulative.md) for `WITHIN`, `HENCE`/`LEST` and `#TRACE`; and
entry [5.1](05-duties-powers-consequences.md#e5-1) before you reach for a deontic at all, because a
passive "may be granted" is a boolean, not a permission.

<a id="e6-2"></a>

## 6.2 "the notice must contain the following particulars" — a record, one field per limb

**If the source says**

> `DECLARE Constitution HAS` … `` `express permission for the entity's activities to be directed or otherwise controlled by a Minister` IS A BOOLEAN -- 5(2), limb (a), direction mode ``
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:146-154`, where Article 5(2)'s "three
> listed persons x two modes of involvement" becomes six fields, each tagged with the limb it came
> from.

**It is doing** listing what a document, an application or a notice has to carry. Each limb is a
separate thing that can be present or missing, and the rule that consumes them has to be able to say
**which one** is missing.

**Write** one field per limb, in the source's order, with the limb letter in a trailing comment. Use
`MAYBE` where the particular can be absent, and test with `isJust`.

```l4
-- "A notice under subsection (1) must contain the following particulars --
--  (a) the name of the licensee; (b) the address of the premises;
--  (c) the date of the change; (d) the reason for the change."
DECLARE Notice HAS
    `the name of the licensee`      IS A MAYBE STRING    -- (a)
    `the address of the premises`   IS A MAYBE STRING    -- (b)
    `the date of the change`        IS A MAYBE NUMBER    -- (c)
    `the reason for the change`     IS A MAYBE STRING    -- (d)

GIVEN n IS A Notice
GIVETH A BOOLEAN
DECIDE `the notice contains the particulars subsection (2) requires` n IF
        isJust (n's `the name of the licensee`)
    AND isJust (n's `the address of the premises`)
    AND isJust (n's `the date of the change`)
    AND isJust (n's `the reason for the change`)
```

The parentheses around `n's …` are not optional: `` isJust n's `f` `` is a parse error
(`unexpected 's`). A projection under a function application is always bracketed.

**Building one of these records has two spellings, and both are correct.** You will meet each of
them in this skill — the entries here and in area 9 lead later fields with a comma; the record
construction in [drafting-patterns.md](../drafting-patterns.md) and in `SKILL.md` uses no commas at
all. They are alternatives, not a version difference and not a latent bug:

```l4
-- Spelling A: every field on its own line, no commas.
`the January note` MEANS `Fee note` WITH
    hours IS 40
    rate  IS 120

-- Spelling B: the first field on the WITH line, later fields led by a comma
-- indented past the column where the expression starts.
`the February note` MEANS `Fee note` WITH hours IS 50
                                        , rate  IS 150
```

_(Probe `r1-record-two-spellings.l4`, exit 0, no errors, both records readable.)_ Spelling B is what
a long field name wants, because it keeps the construction inside one visual block; spelling A is
what a wide record wants. Pick one per file. The comma in spelling B must sit **right of the column
the expression starts at** — pull it back and the parser reports `unexpected WITH` against the line
**above**, which points at the wrong line entirely (entry
[7.7](07-presumptions-and-defaults.md#e7-7) records the same failure on a `LIST`).

**Not** a single `LIST OF STRING` of "the particulars". It type-checks, and the completeness test
degenerates into a count:

```l4
DECIDE `the notice contains the particulars subsection (2) requires` n IF
    count (n's particulars) AT LEAST 4
```

Run against a notice that gives the address twice and omits the reason, that prints
`assertion satisfied` — four strings, so four particulars. Nothing in the type says which limb a
string belongs to, so nothing can report the gap, and no form generated from the type can ask the
right four questions.

**See** [drafting-patterns.md](../drafting-patterns.md), "Checkbox relation-on-an-entity", for the
same shape where the limbs are booleans rather than optional values, and "Statutory tables as `DATA`"
for the case where the limbs are rows rather than fields.

<a id="e6-3"></a>

## 6.3 "a person", "a body corporate" — one type with alternatives, not two flags

**If the source says**

> `DECLARE Borrower IS ONE OF`, then `` `Individual Borrower` HAS Individual IS A `Natural Person` ``
> and `` `Commercial Borrower` HAS Entity IS A Company ``
>
> — `jl4/examples/legal/promissory-note.l4:248-252`, with the comment "IS ONE OF can be useful to
> define types that are alike sometimes, but differ in some detailed terms later".

**It is doing** dividing the persons the provision reaches into kinds that carry **different facts**.
A natural person has an age; a body corporate has a registration number and no age at all. An
interpretation section that says "'person' includes a body corporate" is telling you the kinds are
alternatives, not overlapping labels.

**Write** one type whose constructors are the kinds, each carrying its own record, and take the kinds
apart with `CONSIDER`.

```l4
DECLARE `Natural Person` HAS
    `name`                IS A STRING
    `age in years`        IS A NUMBER

DECLARE `Body Corporate` HAS
    `name`                IS A STRING
    `registration number` IS A STRING

DECLARE Person IS ONE OF
    `an individual`    HAS `the individual` IS A `Natural Person`
    `a body corporate` HAS `the body`       IS A `Body Corporate`

GIVEN p IS A Person
GIVETH A BOOLEAN
`s 6(1) -- old enough for a licence` p MEANS
    CONSIDER p
    WHEN `an individual` i    THEN i's `age in years` AT LEAST 18
    WHEN `a body corporate` b THEN TRUE
```

**Not** two independent booleans on one flat record. The corpus itself carries an early example of
this shape — ``ASSUME `the person is a body corporate` IS BOOLEAN``
(`jl4/examples/legal/imaginary-alcohol-act.l4:33`) — and it lets you build a person who is both, or
neither, and give a company an age:

```l4
DECLARE Person HAS
    `the person is a body corporate` IS A BOOLEAN
    `the person is an individual`    IS A BOOLEAN
    `age in years`                   IS A NUMBER

GIVEN p IS A Person
GIVETH A BOOLEAN
`s 6(1) -- old enough for a licence` p MEANS
    IF   p's `the person is a body corporate`
    THEN TRUE
    ELSE p's `age in years` AT LEAST 18

`the impossible applicant` MEANS Person OF TRUE, TRUE, 4
#ASSERT `s 6(1) -- old enough for a licence` `the impossible applicant`
```

That is a whole alternative module, not something to paste after the block above — two `DECLARE
Person`s in one file give you `There are multiple definitions for the identifier Person`. On its own
it runs clean and prints `assertion satisfied`. A four-year-old body corporate got its licence, and
nothing complained. `IS ONE OF` makes the impossible record unwritable.

**See** [drafting-patterns.md](../drafting-patterns.md), "Enumerated cases (Case A / B / C)", and
entry [1.2](01-definitions-and-scope.md#e1-2) for the different question of a **role** the case
fills.

<a id="e6-4"></a>

## 6.4 "each of", "every", "all of the following persons" — `all` over a list

**If the source says**

> `-- "13.--(1) Where -- (a) no executor is appointed by a will; (b) the executor or all the executors appointed by will are legally incapable of acting as such, or have renounced the right to act as such; ..."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:472-474`, Probate and Administration Act 1934
> s 13(1). Limb (b) is encoded at `:498` as
> ``all (GIVEN p YIELD p's `legally incapable of acting as such` OR p's `has renounced the right to such grant`) executors``.

**It is doing** quantifying over a collection whose size the drafter does not know: every executor,
each of the governors, all of its purposes.

**Write** `all` with the test as a lambda **first** and the list second.

```l4
DECLARE Executor HAS
    `name`                                  IS A STRING
    `has renounced the right to such grant` IS A BOOLEAN

GIVEN executors IS A LIST OF Executor
GIVETH A BOOLEAN
`s 13(1)(b) -- every executor appointed by the will has renounced` executors MEANS
    all (GIVEN p YIELD p's `has renounced the right to such grant`) executors
```

**Know what the empty list does.** A universal over nothing is `TRUE`:

```l4
#ASSERT `s 13(1)(b) -- every executor appointed by the will has renounced` EMPTY
```

passes. That is the standard reading of a universal, and it is the reading `all` implements — but it
is a reading, and where it matters the corpus records the choice rather than letting it happen
silently: `jl4/examples/legal/charities-cleanroom/charity-test.l4:554-567` registers it as an
ambiguity, Article 5(1)(a) applied to an entity with no purposes at all, and pins the behaviour with
a scenario so a later change to `all` is caught. Do the same: if "all of its purposes are
charitable" ought to fail for an entity with no purposes, say so and add the guard.

**Not** the arguments the other way round. `all executors (GIVEN p YIELD …)` reads naturally and is
rejected:

```
The second argument of function

  all (defined at prelude.l4:243:1-4)

is expected to be of type

  LIST OF a7

but is here of type

  FUNCTION FROM Executor TO BOOLEAN
```

**See** [drafting-patterns.md](../drafting-patterns.md), "Statutory tables as `DATA`", which uses the
same lambda shape for membership tests, and [sets.md](../sets.md) when the collection is a set
rather than a list.

<a id="e6-5"></a>

## 6.5 "any of", "one or more of", "at least one" — `any` over a list

**If the source says**

> ``OR any (GIVEN q YIELD `a survivor stands in the line of` q) (p's `issue`)``
>
> — `jl4/examples/legal/sg-succession/sg-isa.l4:149`, the recursive test for whether any descendant
> of a person survived the intestate.

**It is doing** the existential half of the same job: the rule fires if the property holds of at
least one member.

**Write**

```l4
DECLARE Person HAS
    `the reference for this person` IS A STRING
    `survived the deceased`         IS A BOOLEAN

GIVEN people IS A LIST OF Person
GIVETH A BOOLEAN
`any of the issue survived the intestate` people MEANS
    any (GIVEN p YIELD p's `survived the deceased`) people
```

An existential over the empty list is `FALSE`, which is the mirror image of 6.4 and needs no note:
``#ASSERT NOT `any of the issue survived the intestate` EMPTY`` passes.

**Not** `OR` written out over a fixed number of members. It is right only until an estate has three
children, and it cannot recur — the corpus example above is recursive precisely because "issue"
reaches to the remotest degree.

**See** [drafting-patterns.md](../drafting-patterns.md), "Statutory tables as `DATA` — a record per
row + enums + membership via `any`".

<a id="e6-6"></a>

## 6.6 "the same person" — identity is a field you compare, never the whole record

**If the source says**

```
--   (2) `Person` carries `the reference for this person`, and EQUALITY OF
--       THAT FIELD IS IDENTITY. Records are values in L4, so without it the
--       same human embedded in two places is two unrelated copies that can
--       silently disagree — and the four Acts join across records constantly
```

> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/family-domain.l4:54-57`, with the three
> provisions that force the point: a Wills Act section that must know the witness's spouse is the
> donee, a Guardianship of Infants Act section that must know two appointees are guardians of the
> same infant, a Probate and Administration Act section that must know the executor who died is one
> of the grantees.

**It is doing** joining two provisions that talk about one human from different angles. "The same
person", "such person", "that beneficiary" — all of them are cross-references, and a record on its
own has nothing to cross-reference with.

**Write** an explicit identifying field, and compare that.

```l4
DECLARE Person HAS
    `the reference for this person`   IS A STRING   -- equality of THIS field is identity
    `is a beneficiary under the will` IS A BOOLEAN

GIVEN a IS A Person
      b IS A Person
GIVETH A BOOLEAN
`the same person as` a b MEANS
    a's `the reference for this person` EQUALS b's `the reference for this person`
```

The convention that goes with it: a record that **embeds** a whole person is that person's primary
home, and a field named `the reference for …` is a pointer to a person whose facts live elsewhere.

**Not** `EQUALS` between the two records. It compiles, and it is structural:

```l4
`the witness, as the attestation records him`      MEANS Person OF "carl", FALSE
`the same Carl, as the residue clause records him` MEANS Person OF "carl", TRUE

#ASSERT `the witness, as the attestation records him` EQUALS `the same Carl, as the residue clause records him`
```

prints `assertion failed` — one human, read as two people, because two provisions recorded different
facts about him. Note also that `l4 run` **exits 0** on that file: the failure is at
`DiagnosticSeverity_Error` in the diagnostics, not in the exit code.

**See** [gotchas.md](../gotchas.md), "No implicit coercion", and — where the collection is a set —
[sets.md](../sets.md) gotcha 4, which is the same trap one level up: records holding sets compare
structurally even when the sets are extensionally equal.

<a id="e6-7"></a>

## 6.7 "the following persons in the following order" — rank, then filter to the best rank

**If the source says**

> `-- "(2) A prior right to a grant under subsection (1) shall belong to the following persons in the following order: (a) a universal or residuary legatee; ... (e) a creditor of the deceased."`
>
> — `jl4/examples/legal/sg-succession/sg-paa.l4:541-547`, Probate and Administration Act 1934
> s 13(2), encoded at `:557` as `` `the section 13(2) rank of` p `` and at `:573` as
> `` `those with a prior right under section 13(2) in` a ``.

**It is doing** stating a **total order over classes**, not a list of qualifying conditions. Being
in class (e) is not the same as being in class (a); it means you take only if nobody in (a) to (d)
is there.

**Write** a rank function with `BRANCH` — first matching arm wins, which is what "in the following
order" means — and then keep everyone who shares the best rank anyone achieved. Give the unranked
residue its own number rather than treating it as an error.

```l4
GIVEN p IS AN Applicant
GIVETH A NUMBER
`the section 13(2) rank of` p MEANS
  BRANCH
    IF p's `a universal or residuary legatee`       THEN 1
    IF p's `a legatee having a beneficial interest` THEN 4
    IF p's `a creditor of the deceased`             THEN 5
    OTHERWISE 6                                     -- unranked: no prior right, not a bar

GIVEN candidates IS A LIST OF Applicant
GIVETH A LIST OF Applicant
`those with a prior right under section 13(2) among` candidates MEANS
    filter (GIVEN p YIELD `the section 13(2) rank of` p EQUALS best) candidates
    WHERE
      best MEANS minimum1 6 (map (GIVEN p YIELD `the section 13(2) rank of` p) candidates)
```

`minimum1` is seeded with the residue rank rather than `minimum`, because `minimum` is
`@nonexhaustive` and stops on an empty list.

**Not** a disjunction of the five classes. This compiles and is wrong in a way no type will catch:

```l4
`has a prior right under section 13(2)` p MEANS
        p's `a universal or residuary legatee`
    OR  p's `a legatee having a beneficial interest`
    OR  p's `a creditor of the deceased`
```

Run against a creditor, it prints `assertion satisfied` — the last-ranked class is reported as having
the prior right, whoever else has applied. The order is the whole content of the subsection; a
disjunction throws it away.

**Not**, either, a `REFUSE` for the person in none of the five classes. Being unranked is the absence
of a prior right, not a gap in the encoding; the section that permits a grant to "such person as the
court considers the fittest" is still there to reach it.

<a id="e6-8"></a>

## 6.8 "residents of New York and New Jersey may apply" — the "and" that is a union

**If the source says**

> "residents of New York **and** New Jersey may apply"
>
> — the worked pair in [`doc/tutorials/set-operators/sets-and-the-two-ands.md`](../../../../doc/tutorials/set-operators/sets-and-the-two-ands.md),
> beside "cruel **and** unusual punishments". The tutorial cites the Singapore Court of Appeal (SGCA)
> reading the same word as union in _Nam Hong Construction_ [2016] SGCA 42 and as conjunction in
> _Sit Kwong Lam_ [2018] SGCA 14.

**It is doing** joining two **groups of people** into a bigger group. The other "and" joins two
**conditions about one thing**. Same word, two operations, and only the context decides which.

**Write** `UNION` for the group reading, and keep `AND` for the condition reading.

```l4
`residents of New York`   MEANS SET OF "alice", "bob"
`residents of New Jersey` MEANS setFromList (LIST "carol")

`persons who may apply` MEANS `residents of New York` UNION `residents of New Jersey`

#EVAL setSize `persons who may apply`                 -- 3
#ASSERT "carol" `is in` `persons who may apply`
```

**Not** the statute's word transcribed between the two sets. That is a type error, and the error is
the feature — it fires at exactly the token where a human had to choose a reading:

```
The second argument of function

  `__AND__` (predefined)

is expected to be of type

  BOOLEAN

but is here of type

  SET OF STRING
```

**See** [sets.md](../sets.md) for the whole vocabulary and its seven gotchas — in particular that
`SET OF` needs two or more elements (a singleton is `setFromList (LIST x)`), that `` `LESS` ``
must be backticked, and that bare `EQUALS` between sets is a deliberate ambiguity error.

<a id="e6-9"></a>

## 6.9 "the Registrar", "the Minister", "the court" — an office is a party, a name is not

**If the source says**

> `DECLARE Actor IS ONE OF` / `Issuer` / `Intermediary` / `Investor` / `Purchaser`
>
> — `jl4/examples/legal/regcf/regcf.l4:89-93`. Not one human is named; the cast is the roles the
> Code of Federal Regulations part creates.

**It is doing** conferring a power on an **office**. Who holds it today is irrelevant to the rule and
will change; "the registrar" in a 1934 Act has had many occupants and the section has not moved.

**Write** the offices as the constructors of the actor type, and let the person filling the office be
a fact recorded elsewhere if any rule actually needs it.

```l4
DECLARE Actor IS ONE OF
    `the court`
    `the registrar`
    `the applicant`

DECLARE Action IS ONE OF
    `make the grant`
    `require security for the due administration of the estate`

DECLARE Matter HAS
    `the matter is uncontested` IS A BOOLEAN

-- "69. ... the registrar may exercise ... in uncontested matters ... all or
--  any of the powers conferred upon the court ..."
GIVEN m IS A Matter
GIVETH A DEONTIC Actor Action
`s 69 -- the registrar may exercise the court's powers in` m MEANS
    IF   m's `the matter is uncontested`
    THEN PARTY `the registrar` MAY `make the grant` WITHIN 30
    ELSE PARTY `the court`     MAY `make the grant` WITHIN 30
```

→ ``PARTY `the registrar` MAY `make the grant` WITHIN 30 HENCE FULFILLED``. The `HENCE FULFILLED`
is supplied by the default and is not in the source; see [regulative.md](../regulative.md) for the
default table.

**Not** a `STRING` in the party position. `GIVETH A DEONTIC STRING Action` type-checks, and then two
spellings of one office are two different parties:

```l4
    THEN PARTY "the registrar" MAY `make the grant` WITHIN 30
    ELSE PARTY "the Registrar" MAY `make the grant` WITHIN 30
```

runs clean and prints `PARTY "the Registrar" …`. Nothing checks that the second office exists, and a
`#TRACE` event spelled the other way will never match.

**See** [`doc/concepts/legal-modeling/actors-and-actions.md`](../../../../doc/concepts/legal-modeling/actors-and-actions.md),
"Who may perform: one actor, some actors, any actor", for declaring a cast that is exactly the
office-holders a Part names; entry [8.5](08-judgement-and-discretion.md#e8-5) for what to do when the
office-holder's choice within that cast is a discretion.

<a id="e6-10"></a>

## 6.10 The named case, and the helper that builds one — mixfix segments may open with punctuation

**If the source says** nothing — this is a drafting habit, and it is the one that decides whether an
area's assertions are readable. Every `#ASSERT` in this phrasebook is applied to a **named case**
rather than to a record built in place, because [a directive must fit on one
line](10-for-the-avoidance-of-doubt.md#e10-2) and a record literal will not.

**It is doing** giving a fact pattern a name a reader of the assertion can check against the source.
``#ASSERT `the fee for the month` `a 50 hour month` EQUALS 6300`` says what it tests; the same
line with the record inlined says only that some arithmetic came out at 6300.

**Write** a mixfix constructor whose segments read as a sentence. **A backticked segment may begin
with punctuation** — a comma, a bracket, a semicolon, a colon — which is what lets the call read as
one clause of English instead of a run of unlabelled arguments:

```l4
DECLARE Expense HAS
    amount                IS A NUMBER
    `reasonably incurred` IS A BOOLEAN
    `approved in advance` IS A BOOLEAN

GIVEN n IS A NUMBER
      r IS A BOOLEAN
      a IS A BOOLEAN
GIVETH AN Expense
`an expense of` n `, reasonably incurred being` r `, and approved in advance being` a MEANS
    Expense WITH amount IS n
               , `reasonably incurred` IS r
               , `approved in advance` IS a

GIVEN n IS A NUMBER
      m IS A NUMBER
GIVETH A NUMBER
`the fee for` n `hours (at the first band); and` m `hours (at the second band)` MEANS
    (n TIMES 120) PLUS (m TIMES 150)
```

_(Probe `r7-mixfix-punctuation.l4`, exit 0, no errors. ``(`an expense of` 600 `, reasonably
incurred being` TRUE `, and approved in advance being` TRUE)'s amount`` is 600, and the banded fee
for 40 and 10 hours is 6300.)_ A comma, a semicolon, a colon and an opening bracket were each
measured at the head of a segment and all four check (probe `r7c-segment-openers.l4`, exit 0, two
assertions satisfied). The parameters must appear in the order of the `GIVEN` —
[4.10](04-dates-and-periods.md#e4-10) records the same constraint.

**Not** a segment containing `--`. That is the comment marker, and backticks do not protect it: the
definition silently ends at the segment before it, so the head is defined at the wrong arity and the
rest becomes a free identifier (probe `r7b-mixfix-comment-marker.l4`, exit 1):

```
The function

  `clause 5(1): the expense of` (predefined)

expects 1 argument,
but you are applying it to 2 arguments here.
```

followed by `I could not find a definition for the identifier / `-- reimbursable?``. Two errors, and
neither says "comment".

**Not** a case value whose name describes the expected answer rather than the facts. `` `the
expensive month` `` tells a reviewer nothing to check; `` `a 50 hour month` `` tells them the
number to look for in clause 4.

**Not** the record inlined into the directive to save a definition. `#ASSERT` does not wrap onto a
second line, so the alternative to a name is a line hundreds of columns wide that no reviewer reads.

**See** [gotchas.md](../gotchas.md), "Backtick identifiers and mixfix", entry
[6.2](#e6-2) for the record the helper builds, and entry
[1.13](01-definitions-and-scope.md#e1-13) for where in the file the named cases go.
