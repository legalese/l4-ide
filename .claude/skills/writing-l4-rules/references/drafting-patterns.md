# L4 Drafting Patterns — Idioms from Formalizing Statute

Hard-won idioms from formalizing 43 statutory grounds for possession (UK Housing Act 1988, Schedule 2,
as amended by the Renters' Rights Act 2025). Each pattern is **"when the statute says…" → the L4 shape →
a real example file**. Pair with [regulative.md](regulative.md) (the deontic outcome) and
[state-ledger.md](state-ledger.md) (recording facts over the trace). Cited example paths are basenames under
the housing-act corpus (`…/jl4/experiments/housing-act-<name>.l4`); where a pattern is drawn from another
corpus, the path is given in full from the repo root.

A cross-cutting surface note: across the constitutive limbs below, **`...` is AND-sugar and `..` is OR-sugar**
(asyndetic con/disjunction; see the "Asyndetic operators `...` and `..`" section of
[gotchas.md](gotchas.md)). A string literal in boolean context is **inert** — it carries the verbatim
statutory prose but evaluates to the identity of its context (`TRUE` under `AND`, `FALSE` under `OR`), so it
never changes the result. A limb that reads `NOT P .. Q` _is_ `(NOT P) OR Q` — the `..` is the OR, with the
verbatim statutory prose riding inert between the operands.

---

## Constitutive limbs (the predicate tree)

### Conditional / proviso limb — `(NOT X) OR Y`

**Statute:** "if X, then Y" — a limb that only _bites_ when its antecedent X holds.
**Shape:** material implication `(NOT X) OR Y`, vacuously satisfied (TRUE) when X is false.

Spelled-out form (`ground-4.l4`, limb (c), succession notice):

```l4
`(c) — succession notice condition` claim MEANS
        "(c) if the tenancy arose by succession as mentioned in section 39(5), notice was given ..."
    ...     NOT claim's `tenancy arose by succession as mentioned in section 39(5)`
        OR  claim's `notice given to previous tenant under Case 14 of Sch.15 Rent Act 1977`
```

OR-sugar form, where the prose interleaves the two operands (`ground-13.l4` / `ground-15.l4`, the
lodger-or-sub-tenant removal proviso):

```l4
`lodger or sub-tenant removal proviso` claim MEANS
        "and, in the case of an act of waste by ... a person lodging with the tenant or a sub-tenant of his,"
    ..  NOT claim's `the responsible actor is a person lodging with the tenant or a sub-tenant of his`
    ..  "the tenant has not taken such steps as he ought reasonably to have taken for the removal ..."
    ..  claim's `the tenant has not taken such steps as he ought reasonably to have taken for the removal of the lodger or sub-tenant`
```

The `ground-4.l4` (explicit `OR`) vs `ground-13/15.l4` (`..`) pair is a clean before/after of the two surface
forms for the _same_ `(NOT P) OR Q` logic.

### Negative limb — `NOT atom`, and the negated disjunction

**Statute:** "the tenancy is **not** an assured agricultural occupancy"; or "**not** granted via any of (i)/(ii)/(iii)".
**Shape:** a single positive atom wrapped in `NOT` for the simple case; a **negated disjunction**
`NOT (i OR ii OR iii)` (De Morgan) for "not via any of …".

Simple (`ground-4.l4`, limb (d)):

```l4
`(d) — not an assured agricultural occupancy` claim MEANS
        "(d) the tenancy is not an assured agricultural occupancy ... by virtue of paragraph 3 of Schedule 3."
    ... NOT claim's `tenancy is an assured agricultural occupancy (agric. worker condition fulfilled, Sch.3 para.3)`
```

Negated disjunction (`ground-5H.l4`, limb (e)) — build the three routes as one named disjunction, then negate
it (more readable than `NOT(i) AND NOT(ii) AND NOT(iii)`, and keeps each route with its verbatim text):

```l4
`tenancy was granted via an excluded route` claim MEANS
        "(i) pursuant to a nomination as mentioned in section 159(2)(c) of the Housing Act 1996,"
    ..  claim's `tenancy was granted pursuant to a nomination under s.159(2)(c) Housing Act 1996`
    ..  "(ii) as a tenancy of supported accommodation, or"
    ..  claim's `tenancy was granted as a tenancy of supported accommodation`
    ..  "(iii) in pursuance of a local housing authority's duty under section 193 ..."
    ..  claim's `tenancy was granted in pursuance of a local housing authority's s.193 duty`

`(e) — tenancy was not granted via an excluded route` claim MEANS
        "(e) the tenancy was not granted—"
    ... NOT `tenancy was granted via an excluded route` claim
```

### "Only in a case where X applies" gate — `(NOT gate) OR condition`

**Statute:** "the … condition, **but only in a case where** section 7(5ZA) applies".
**Shape:** an implication `(NOT gate) OR condition` — vacuous (TRUE) when the gate is off; the gate is itself a
named predicate (possibly a conjunction). Same machinery as the proviso limb, but the antecedent is a
jurisdictional gate rather than a fact.

`ground-6.l4`, limbs (b) and (c):

```l4
`(b) landlord's acquisition condition, only where s.7(5ZA) applies` claim MEANS
        "(b) the landlord's acquisition condition, but only in a case where section 7(5ZA) applies ..."
    ..  NOT `section 7(5ZA) case applies` claim
    ..  `landlord's acquisition condition` claim

`(c) additional RSL condition, only where landlord is RSL and redeveloper` claim MEANS
        "(c) the additional RSL condition, but only in a case where the landlord seeking possession is— ..."
    ..  NOT `additional-RSL case applies` claim     -- gate is itself (i) AND (ii)
    ..  `additional RSL condition` claim
```

### Enumerated cases (Case A / B / C) — a disjunction of predicates

**Statute:** "is a qualifying X **in case A or B**" / "met **in case A, case B or case C**".
**Shape:** an OR over named per-case predicates; each Case is its own `GIVEN claim … MEANS` predicate, so the
disjunction reads like the statute.

`ground-5A.l4` (qualifying agricultural worker) / `ground-6.l4` (additional RSL condition):

```l4
`is a qualifying agricultural worker` claim MEANS
        "For the purpose of this ground a person is a \"qualifying agricultural worker\" in case A or B."
    ..  `Case A` claim
    ..  `Case B` claim
```

### Checkbox relation-on-an-entity — independent BOOLEAN flags + a disjunction

**Statute:** a kinship / category list — "(a) the landlord; (b) the landlord's spouse …; (c) the landlord's
parent/grandparent/sibling/child/grandchild; (d) …".
**Shape:** independent BOOLEAN flags on the entity record + a disjunction over them — **not an enum**. This is
input-layer-friendly (each limb is a checkbox, not a mutually-exclusive radio button), and you include one
catch-all "other" flag that is **deliberately omitted from the disjunction** so an off-list occupier yields
FALSE.

`ground-1-amended-2025.l4` (family occupier (a)–(d)):

```l4
DECLARE Occupier HAS
    name                                                  IS A STRING
    `the landlord`                                        IS A BOOLEAN   -- (a)
    `the landlord's spouse, civil partner or cohabitant`     IS A BOOLEAN -- (b)
    `the landlord's parent`                               IS A BOOLEAN   -- (c)(i)
    -- ... grandparent / sibling / child / grandchild ...
    `a child or grandchild of the landlord's partner`     IS A BOOLEAN   -- (d)
    `is other`                                            IS A BOOLEAN   -- none of (a)-(d); NOT in the disjunction

`is a qualifying occupier` occupier MEANS
        "(a) the landlord;"                  ... occupier's `the landlord`
    ..  "(b) the landlord's spouse ..."      ... occupier's `the landlord's spouse, civil partner or cohabitant`
    ..  "(c) the landlord's— (i) parent;"    ... occupier's `the landlord's parent`
    ..  -- ... limbs (ii)-(v) ...
    ..  "(d) a child or grandchild ..."      ... occupier's `a child or grandchild of the landlord's partner`
    -- `is other` is deliberately NOT a disjunct: an off-list occupier is FALSE.
```

### Statutory tables as DATA — a record per row + enums + membership via `any`

**Statute:** a table (e.g. landlord-type × tenancy-type × redeveloper).
**Shape:** an enum per column's cell-type, a `TableRow` record (cells, with list-valued cells as `LIST OF` the
enum), one `… WITH …` literal per row, and membership tested structurally with `any` + a local equality
predicate.

`ground-6.l4`:

```l4
DECLARE RedeveloperType IS ONE OF `the landlord who is seeking possession`, `a superior landlord`, `the commonhold association`
DECLARE LandlordColumnType IS ONE OF `col1 a relevant social landlord`, ...
DECLARE TableRow HAS
    `first column — landlord seeking possession`       IS A LandlordColumnType
    `second column — tenancy`                          IS A TenancyColumnType
    `third column — landlords intending to redevelop`  IS A LIST OF RedeveloperType

`redeveloper is in the third column of the row` MEANS
    any (`equals the redeveloper`) (`row`'s `third column — landlords intending to redevelop`)
    WHERE
        `equals the redeveloper` x MEANS x EQUALS `redeveloper`
```

---

## Decision results (the return type)

### Total enum over `MAYBE` — where the source names the absent case

**Statute:** a provision whose outcomes include a named "nothing follows" case — "no issuance", "no
liability", "the application is refused".
**Shape:** one nullary `IS ONE OF` covering _every_ outcome, the absent one included, returned as
`GIVETH A <Enum>` — **not** `GIVETH A MAYBE <Enum>` with the absent case folded into `NOTHING`.

`jl4/examples/legal/ny-environmental-7.3.l4` (6 NYCRR 624 §7.3(b)(2), issuance of the final EIS)
already does this, and does it while keeping `MAYBE` exactly where `MAYBE` belongs:

```l4
DECLARE `Final EIS Issuance` IS ONE OF
    `No issuance`                                           -- the absent case, NAMED
    `Issued within 45 days of the close of the record`
    `Issued extended beyond 45 days of the close of the record`

GIVEN `The decision`        IS A `Tentative or recommended decision`
      `Cause for extension` IS A MAYBE `Final EIS Issuance Extension Cause`   -- input: stays MAYBE
GIVETH A `Final EIS Issuance`                                                 -- result: total
`Determining issuance for final EIS` MEANS
    IF    NOT `Tentative or recommended decision will contain a final EIS` `The decision`
    THEN  `No issuance`
    ELSE  CONSIDER `Cause for extension`
              WHEN NOTHING    THEN `Issued within 45 days of the close of the record`
              WHEN JUST cause THEN `Issued extended beyond 45 days of the close of the record`
```

The asymmetry _is_ the rule, and it fits in one function: **`MAYBE` inbound for a fact you may not
have been given; a total enum outbound for a result you always have.** The surviving `MAYBE` on
`Cause for extension` is correct and must not be swept up.

> **Read this example for reasons 1 and 2 only.** Reason 3 does not fire on it, in either form, and
> saying otherwise would be a wrong claim about a real corpus file. `WHEN JUST cause` is a
> **binding** pattern, and a binding arm has no guard the exporter can write down; the whole
> `CONSIDER` therefore collapses to a single verbatim default entry (`Blocking`, and `null` under
> `SUCCEEDED`) whether the arms return `` `Issued extended…` `` or `` JUST `Issued extended…` ``.
> The MAYBE-first counterfactual below collapses identically. There is a second-order drafting
> lesson in that — **a `CONSIDER` arm that binds a payload is itself a DMN-hostile shape**, for the
> same reason `JUST x` is — but it is not the lesson this section is about, and folding the return
> type does not fix it.

The same provision written the other way — the shape to avoid:

```l4
-- NOT the corpus code. The same rule, drafted MAYBE-first, for contrast.
DECLARE `Final EIS Issuance` IS ONE OF
    `Issued within 45 days of the close of the record`
    `Issued extended beyond 45 days of the close of the record`
    -- "no issuance" has no name here; it lives in the wrapper

GIVETH A MAYBE `Final EIS Issuance`
`Determining issuance for final EIS` MEANS
    IF    NOT `Tentative or recommended decision will contain a final EIS` `The decision`
    THEN  NOTHING
    ELSE  CONSIDER `Cause for extension`
              WHEN NOTHING    THEN JUST `Issued within 45 days of the close of the record`
              WHEN JUST cause THEN JUST `Issued extended beyond 45 days of the close of the record`
```

Three reasons to prefer the first:

1. **Fidelity to the source.** Legislation usually _names_ the null outcome rather than leaving a
   gap, and the name carries the citation. `NOTHING` cannot hold `"No issuance"`; an enum member
   can, and it reads back in the statute's own words. Under `MAYBE` the domain also silently
   shrinks — the declared enum above goes from three outcomes to two.
2. **A finite declared domain, which is what static analysis needs.** A nullary `IS ONE OF` is the
   one L4 type with a faithful image in FEEL/DMN, because its values serialise as strings; it
   lowers to `typeRef="string"`. `MAYBE T` is a type _applied to an argument_, so it does not match
   the exporter's nullary-enum test and the output column erases to `Any` — the exporter's type
   lowering maps a **nullary** type constructor to a FEEL type and everything else to `Any`, so
   `GIVETH A MAYBE T` contributes no declared type at all. (Do not over-generalise this to
   "`GIVETH` is authoritative". It is authoritative only when it lowers to something other than
   `Any`; when it lowers to `Any` — which is exactly the `MAYBE` case — the exporter falls back to
   inferring the type from the cells, and the column ends up `Any` because the `JUST x` cells are
   unrenderable, not because the declared `MAYBE` won.) Emitting the domain itself as DMN
   `<outputValues>` — the precondition for the `P` and `O` hit policies — is pending
   (smucclaw/l4-ide#923); the `typeRef` difference is present behaviour.
3. **No null wrapper in the export target.** `NOTHING` is nullary and survives as the string
   `"NOTHING"`, but `JUST x` is an _applied_ constructor, which the DMN exporter cannot render as
   executable FEEL: it emits it verbatim and reports **Blocking**, because a real engine
   (Drools/KIE 8.44) answers `Unknown variable 'JUST'` and the whole decision evaluates to **null**
   — reported as `SUCCEEDED`.

   **And FEEL's null is not a failure signal — it reads as `FALSE`.** This is the opposite of what
   you would expect from an undefined value, and it is why the failure is silent. Verified in
   `feelin` 7.0.1: `1 / 0`, `{a: 1}.b` and friends all yield `null`; `null` then _propagates_
   through arithmetic and comparison (`100 / 0 > 10` → `null`) but is **coerced to `false` at the
   first boolean consumer** — `if null then 1 else 2` → `2`, a unary test against a `null` input
   silently does not match, `every p in [2, null] satisfies p > 1` → `false`. Nothing downstream
   ever sees an error. A silent `false` under `SUCCEEDED` is the worst available failure mode for a
   legal reasoner.

   **Where this bites is a flat guarded chain**, where the `JUST x` sits in a cell the exporter
   renders — `IF … THEN JUST X ELSE NOTHING`, which
   `paper/case-studies/charities-jersey-2014/part-6-use-of-terms.l4` emits four times. It does
   **not** bite on the worked example above; see the note under it.

> **PROVENANCE — reasons 2 and 3 describe a backend you cannot run from this checkout.** Reason 1
> stands on the L4 source alone. Reasons 2 and 3 rest on the DMN/FEEL exporter, which lives on the
> `mengwong/dmn-export` line and is **not** on `unstable`: there is no `jl4-core/src/L4/Dmn/`, no
> `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md`, and `l4 --help` has no `dmn` subcommand here. So
> take them as reported behaviour of another branch, not as something to verify in situ, and
> **re-check them against `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §2.4 and §3 once that line
> merges** — two earlier versions of this section stated the FEEL null semantics backwards and
> over-generalised the `GIVETH` rule, and both survived review precisely because nothing here could
> falsify them. Independently of the exporter, reason 1 and the `MAYBE`-is-usually-right section
> below are the load-bearing guidance.

> **SCOPE — this is a drafting default, not a sweep.** Across the repo there are 62
> `GIVETH … MAYBE` signatures in 17 files, and **only 4 of them are in a real legal corpus**. The
> rest are standard-library partiality (`minimum`, `lookup`, `ln`, date parsing), JSON-decode and
> MLIR fixtures, and teaching examples — all of which are _correct_ and none of which this rule
> touches. Apply the rule when drafting a new decision; do not go hunting.

**And the fold is not always a rename.** The four real-corpus occurrences —
`the entity's/person's liability under Article 21/23` in
`paper/case-studies/charities-jersey-2014/part-6-use-of-terms.l4` — return
`MAYBE Part6Penalty`, and `Part6Penalty` is a four-field **RECORD**, not a nullary enum. Its fields
are load-bearing: `is the same penalty as` and `is a heavier penalty than` read them, and they feed
the file's flagship assertion,
`` #ASSERT `the penalty tracks the mens rea, not the paragraph number` ``.
Flattening the penalties into nullary enum members would delete that assertion's subject matter.
The available fold is a **sentinel record** — add a fifth constant (`the absence of a penalty`,
imprisonment `0`, `liable to a fine IS FALSE`) and return `GIVETH A Part6Penalty` — which costs 4
signatures, 4 `ELSE` arms and 12 `#ASSERT` edits (9 lose a `JUST`, 3 lose a `NOTHING`). Note what
it does and does not buy: it clears the four Blocking `JUST` sites (reason 3), but the column stays
`Any`, because reason 2 is gated on nullary-enum-ness and the payload is a record. It is also a
_modelling_ claim — it makes "no offence" and "an offence with a nil penalty" the same value.
**Do not present a fold like that as cosmetic.** Retrofitting a total enum onto a record-valued
result is a modelling decision and belongs in review, not in a tidy-up. This is bucket 5 of the next
section, and it is the case the "does the source name this outcome?" test gets wrong on its own: the
statute plainly names the absence, so that question says fold, and it is still not a tidy-up.

Related: a non-nullary `IS ONE OF` (a tagged union, e.g.
`` `no liability` | `liable` HAS `the penalty` IS A Part6Penalty ``) buys nothing **downstream in
DMN** — FEEL has no sum type, so it lowers to `Any` too. That is an export-fidelity fact and not a
drafting verdict: upstream, in L4 itself, the tagged union is the only shape that both names the
absent outcome and keeps the payload typed, which is what bucket 5 below is about. Do not read this
line as a reason to prefer `MAYBE`.

### Where `MAYBE` is right — and it usually is

Guidance that only says "prefer the enum" gets over-applied. The test is **two** questions, asked in
this order:

1. **Does the source name this outcome?** If the absence is _your_ bookkeeping, a fact you were not
   given, or a proof you do not have, it is a `MAYBE` and folding it is a category error.
2. **If the source does name it: does the _present_ outcome carry a payload?** If it does not, fold
   to a nullary `IS ONE OF` — that is the rule at the top of this section. If it does, a nullary
   enum is simply unavailable (there is nowhere to put the `NUMBER`, the `Money`, the `DATE`), and
   the choice is between a sentinel value in the payload type and a tagged union. Both are
   **modelling** decisions; see bucket 5.

Question 1 alone gives the wrong answer for payload-carrying results — it says "fold" for the
Charities penalties, whose absence the statute plainly names, while the paragraph above correctly
says that fold "belongs in review, not in a tidy-up". Five buckets, all with real examples:

Note before the list which of them are even in scope. This section is titled "decision results (the
return type)", and **only buckets 2 and 5 are return positions.** Buckets 1, 3 and 4 are parameters
and record fields — they are here because they are what the rule gets mistakenly applied to, not
because they are cases it decides.

**1. An input you may not have been given** — parameter position. `Cause for extension` in the
worked example above. This is by far the biggest population: 119 `IS A[N] MAYBE` occurrences in
field/parameter position repo-wide, against 62 in return position. The rule does not touch any of
them.

**2. A lookup or a parse that can genuinely miss** — return position, and the one bucket in this
list that is a genuine counter-case to the rule at the top. `lookup` / `dictLookup`
(`jl4-core/libraries/prelude.l4`) is the canonical case — a key that is not there is not an
_outcome_. Likewise `Date` from a `STRING` (`jl4-core/libraries/daydate.l4`), `minimum`/`maximum`
over a possibly-empty list, and the domain-restricted `ln`/`sqrt`/`asin` in
`jl4-core/libraries/math.l4`.

**3. An optional record field** — field position, not a return type.
`jl4/examples/legal/ceo-performance-award.l4`:

```l4
DECLARE `Tranche Status` HAS
    `Tranche Number`        IS A NUMBER
    `Is Earned`             IS A BOOLEAN
    `Earn Date`             IS A MAYBE DATE                 -- unearned tranche has no earn date
    `Vesting Category`      IS A MAYBE `Vesting Category`   -- ... and no category yet
```

`Vesting Category` is a genuine two-member legal taxonomy
(`Seven And Half Year Earned Shares` / `Ten Year Earned Shares`). Inventing a third member
`` `not yet earned` `` to make the field total would pollute the statute's classification with a
bookkeeping state the source never contemplated — the opposite of fidelity.

**4. `MAYBE BOOLEAN` as _undecided_** — the epistemic third state, not an outcome. Note that here
too the `MAYBE` is in **parameter** position; every function in the library returns
`GIVETH A BOOLEAN`. `jl4-core/libraries/negation-as-failure.l4` is built on it:

```l4
-- JUST TRUE   proven true
-- JUST FALSE  proven false
-- NOTHING     no proof either way (the open question / the default)
GIVEN p IS A MAYBE BOOLEAN
GIVETH A BOOLEAN
holds p MEANS fromMaybe FALSE p      -- closed-world: absence of proof is FALSE
```

Here `NOTHING` means "not yet settled", and the closed- vs open-world default (`holds` vs
`presumed`) is the whole point of the library. Folding it into an enum would collapse the
distinction the library exists to draw.

**5. The source names the absent outcome _and_ the present outcome carries a payload** — return
position, and the case question 1 alone gets wrong. `MAYBE Part6Penalty`, `MAYBE Money`,
`MAYBE DATE`: the statute names "no offence" / "no award" / "no deadline", so question 1 says fold,
but a nullary `IS ONE OF` has nowhere to put the penalty, the amount or the date. Three shapes, none
of them a tidy-up:

- **Leave the `MAYBE`.** Honest, costs nothing today, and is what all four Charities occurrences do.
  The default when nobody is asking for the export.
- **A sentinel value in the payload type** — `` `the absence of a penalty` `` with imprisonment `0`.
  Cheapest to write, but it asserts that "no offence" and "an offence with a nil penalty" are the
  same value, which is a claim about the statute. Costed in detail above for Part 6.
- **A tagged union** — `` `no liability` | `liable` HAS `the penalty` IS A Part6Penalty ``. The only
  shape that both names the absence and keeps the payload typed, and the one to reach for when the
  distinction matters. It does not improve the DMN export (FEEL has no sum type), so choose it for
  the L4-side modelling, not for the exporter.

Whichever you pick, it is a **modelling** decision and goes through review.

One more that looks like a decision result but is not: `MAYBE` as a **selection** predicate feeding
`mapMaybe` — `IF pg's snd THEN JUST (pg's fst) ELSE NOTHING`, the `satisfied grounds` idiom under
"Provenance, repeal, aggregation" below. That is a filter, not an outcome.

---

## Dates

### Leap-safe date windows — build from the actual dates, never hardcode 365

**Statute:** "within 12 months" / "at least 1 year", inclusive of both endpoints.
**Shape:** `IMPORT daydate`; build the window endpoint from the actual date's components, incrementing the
**year** (`DATE_YEAR … PLUS 1`), and compare via inclusive day-spans (`(Day b MINUS Day a) PLUS 1`). The
calendar handles leap years; a magic `365` does not.

`ground-1-amended-2025.l4` ("at least 1 year") / `ground-2ZA.l4` ("within 12 months beginning with …"):

```l4
`one year after tenancy start` c MEANS
    Date (DATE_DAY   (c's `tenancy began`))
         (DATE_MONTH (c's `tenancy began`))
         (DATE_YEAR  (c's `tenancy began`) PLUS 1)   -- leap-safe: increment the YEAR
-- inclusive span: (Day (one year after) MINUS Day (tenancy began)) PLUS 1
```

### ⚠️ The `daydate` month-subtraction FOOTGUN

> **`Date day month year` does NOT roll a month `≤ 0` back into the previous year.** > `Date 1 (3 MINUS 6) 2025` clamps to **January 2025**, _not_ September 2024. Month **overflow** past 12 _does_
> roll forward correctly (`month PLUS 6` on a December date lands in the next year).
>
> So to compute "**N months before** X", never subtract months from X. Instead:
>
> - **ADD** N months to the _earlier_ date (`DATE_MONTH earlier PLUS N`) and compare, or
> - go back a whole year via `DATE_YEAR … MINUS 1` (which can never produce `month ≤ 0`, so the clamp never fires).
>
> **`YMD year month day` does NOT inherit this — it refuses instead.** `YMD 2025 (3 MINUS 6) 1` stops on the refusal binding rather than clamping. So this footgun, and the ADD-to-the-earlier-date workaround below, are about `Date` — which remains the right constructor when you _want_ rolling month arithmetic. Use `YMD` for literals.
>
> (Same footgun is catalogued in [gotchas.md](gotchas.md) under "The `daydate` month-subtraction footgun".)

"≤ 6 months before proceedings" done safely by **adding** to the earlier date (`ground-2ZC.l4` / `ground-2ZD.l4`):

```l4
-- proceedings <= became-landlord + 6 months. We ADD to the earlier date rather than
-- subtracting from the later one, because the Date constructor does not roll a
-- month <= 0 back into the previous year.
`became landlord no more than 6 months before proceedings` MEANS
        Day `proceedings commenced date`
    AT MOST Day `six months after became-landlord date`
    WHERE
        `six months after became-landlord date` MEANS
            Date (DATE_DAY   `became-landlord date`)
                 (DATE_MONTH `became-landlord date` PLUS 6)   -- overflow rolls forward, correctly
                 (DATE_YEAR  `became-landlord date`)
```

The clamp-immune way to go _backward_ — decrement the YEAR (`ground-2ZD.l4`, "12 months ending with …"):

```l4
`twelve months before would-have-expired date` MEANS
    Date (DATE_DAY   `would-have-expired date`)
         (DATE_MONTH `would-have-expired date`)
         (DATE_YEAR  `would-have-expired date` MINUS 1)   -- safe: never yields month <= 0
```

---

## The deontic outcome

### Mandatory vs discretionary — `MUST` vs `MAY` (+ reasonableness)

**Statute:** Part I grounds are **mandatory** ("the court … shall … make an order"); Part II grounds are
**discretionary** ("the court may … if it considers it reasonable").
**Shape:** Part I → `PARTY Court MUST \`order possession\``; Part II → `PARTY Court MAY \`order possession\``(with a reasonableness conjunct). This rides the MUST/MAY default semantics: **MUST** — omission ⇒`BREACH`;
**MAY** — benign omission ⇒ `FULFILLED` (no breach), which is exactly what makes the ground *discretionary*.
The deadline keyword is **`WITHIN <number>` only** (`BEFORE` is not valid). See [regulative.md](regulative.md)
for the full HENCE/LEST default table.

```l4
-- Part I (ground-6.l4): mandatory
`ground 6 possession order` claim MEANS
    IF   `Ground 6 made out` claim
    THEN PARTY Court MUST `order possession` WITHIN 30
    ELSE FULFILLED

-- Part II (ground-9.l4): discretionary
`ground 9 possession order` claim MEANS
    IF   `Ground 9 made out` claim
    THEN PARTY Court MAY `order possession` WITHIN 30
    ELSE FULFILLED
```

### Exercising a DEONTIC — `#ASSERT` the boolean, `#TRACE` the deontic

**Gotcha:** a `DEONTIC` value **cannot** be `EQUALS`-compared in `#ASSERT`. So land your `#ASSERT`s on the
`\`<x> made out\`` BOOLEAN, and *exercise* the guarded deontic via **`#TRACE`\*\* (which residuates it against an
event stream and prints what is left standing).

`ground-9.l4` (a MAY ground):

```l4
#ASSERT `Ground 9 made out`     `claim all-met (deemed suitable, available now)`
#ASSERT NOT `Ground 9 made out` `claim — suitable but unavailable`

-- The court exercises the permission: orders within the deadline.
#TRACE `ground 9 possession order` `claim all-met ...` AT 0 WITH
    PARTY Court DOES `order possession` AT 10
-- The court declines (never orders): MAY's benign omission -> residual FULFILLED, no breach.
```

The residual tells the story: a Part I case residuates to `Court MUST … HENCE FULFILLED`; a benign MAY case
left unexercised stays a standing permission and collapses to `FULFILLED`; a claim where nothing is made out
is `FULFILLED` outright.

---

## Provenance, repeal, aggregation

### No record-update operator — full literals or a `GIVEN`-parameterised constructor

**Gotcha:** `existingValue WITH field IS v` works **only on a TYPE CONSTRUCTOR** (`MyType WITH …`), never on an
_existing_ record value — applied to a value it parses as function application and errors. There is no in-place
record update.
**Fix:** spell full record literals per scenario, or expose a `GIVEN`-parameterised constructor and partially
apply it, varying just the operative field.

`ground-4A.l4` (the constructor approach):

```l4
-- This L4 builds records only from a type name (`Ground4AClaim WITH ...`); there is no
-- in-place record-update operator. So we expose a GIVEN-parameterised constructor; each
-- test below supplies all fields, varying just the operative one.
GIVEN `is HMO` IS A BOOLEAN  ... `re-let intent` IS A BOOLEAN
GIVETH A Ground4AClaim
`mk claim` MEANS Ground4AClaim WITH
  `dwelling-house is in an HMO or is an HMO` IS `is HMO`
  -- ... all other fields ...
-- then: `probe (e)` MEANS `mk claim` TRUE (LIST `student now`) TRUE TRUE ... varying one field
```

(`ground-6.l4` takes the other road: it spells a FULLY-SPELLED `Ground6Claim WITH …` literal per scenario.)

### Repealed / omitted provision → a labelled stub

**Statute:** a ground that has been repealed/omitted (so the in-order corpus would otherwise have a silent gap).
**Shape:** a `§§`-labelled stub carrying the former text as **inert prose** + the repeal provenance, with **no
operative outcome** (no `DECIDE`/deontic). Keeps the corpus gap-free and auditable.

`ground-3-repealed.l4` (and `part-4-repealed.l4` at Part level):

```l4
§ `Housing Act 1988 — Schedule 2 — Part I — Ground 3 (REPEALED / OMITTED by Renters' Rights Act 2025)`
-- Provenance (Textual Amendment F9):
--   "Sch. 2 Ground 3 omitted (1.5.2026 ...) by virtue of Renters' Rights Act 2025 (c. 26),
--    s. 145(1)(8), Sch. 1 para. 8 ...; S.I. 2026/421, reg. 2(b)"
-- Deliberate STUB so the in-order corpus has no silent gap. NO operative logic, NO outcome.
`former Ground 3 text (REPEALED)` MEANS
        "The tenancy is a fixed term tenancy for a term not exceeding eight months and—"
    ... "(a) ... the landlord gave notice ... that possession might be recovered on this ground; and"
    ... "(b) ... the dwelling-house was occupied under a right to occupy it for a holiday."
#EVAL `former Ground 3 text (REPEALED)`
```

### Provenance — pin every inert string; resolve amendments to the in-force reading

**Practice:** pin every inert string to authoritative text. Resolve textual-amendment markers
(omit / insert / renumber) to the **in-force reading**, and carry the amendment provenance as inert prose. Pin it
two ways: a header comment citing the amending Act / section / commencement, and inline inert prose at the
amendment site recording the _omitted_ words plus how the in-force reading was derived.

Header pin + an _omit_ resolved to the in-force text, omitted words kept inert for audit
(`ground-1-amended-2025.l4` / `ground-9.l4`):

```l4
§ `Housing Act 1988 — Schedule 2 — Part I — Ground 1 (amended; Renters' Rights Act 2025)`
-- The amended Ground 1, as substituted by the Renters' Rights Act 2025 (c. 26)
-- (commencement 1.5.2026 for specified purposes). ...

-- F75 (RRA 2025, 1.5.2026) OMITTED the para-2(a) exclusions; carried inert for audit:
    ... "[omitted 1.5.2026: other than— (i) a tenancy in respect of which notice is given ...]"
```

For "ordered on Grounds 1 and 8" explainability, build a **`satisfied grounds`** LIST by `mapMaybe` over
labelled booleans (`possession-decision.l4`):

```l4
`satisfied grounds` cf MEANS
  mapMaybe `label if satisfied` (`pleaded grounds` cf)   -- pleaded grounds :: LIST OF PAIR STRING BOOLEAN
  WHERE
    `label if satisfied` pg MEANS IF pg's snd THEN JUST (pg's fst) ELSE NOTHING
```

### Top-level aggregation (entry point) — two complementary forms

The runnable PoC is `possession-decision.l4`. Two ways to express "what now?":

**Form A — the COURT's decision as a two-tier guarded deontic.** Test the mandatory tier first; else the
discretionary tier (gated on reasonableness); else `FULFILLED`. Do **not** collapse into a flat
`MUST IF (g1 OR … OR g14)` — that would wrongly make discretionary grounds mandatory and drop the reasonableness gate.

```l4
`court possession decision` cf MEANS
    IF   `any Part I ground made out` cf                       -- s.7(3): a mandatory ground
    THEN PARTY Court MUST `order possession` WITHIN 30
    ELSE IF (    `any Part II ground made out` cf               -- s.7(4): a discretionary ground
             AND cf's `it is reasonable to make the order`)    --        AND reasonable
         THEN PARTY Court MAY `order possession` WITHIN 30
         ELSE FULFILLED                                        -- no ground stands
```

**Form B — the obligated/electing party's choice via `ROR`.** Models a genuine election among the _available_
grounds.

> **ROR GOTCHA — the else-FULFILLED trap.** A branch shaped `IF made out THEN MUST … ELSE FULFILLED` is **poison**
> under `ROR`: ROR ("any one fulfils") treats the `FULFILLED` arm as success, so a not-made-out branch makes the
> whole choice fire _trivially_. And `foldr ROR FULFILLED` re-introduces it from the other side —
> `dutyA ROR (dutyB ROR FULFILLED)` collapses to `FULFILLED` immediately.
>
> **Fix:** ROR-fold only the _available_ branches as **UNGUARDED** duties (no `ELSE FULFILLED` short-circuit),
> with a **one-element base case** (the single branch itself) — `FULFILLED` appears **only** in the empty-list case.

```l4
`ror together` branches MEANS
  CONSIDER branches
  WHEN EMPTY               THEN FULFILLED     -- no available ground: nothing to elect
  WHEN d FOLLOWED BY EMPTY THEN d             -- exactly one: that duty, NO FULFILLED tail
  WHEN d FOLLOWED BY rest  THEN d ROR `ror together` rest
-- branches = map `court duty for ground` (`satisfied grounds` cf)  -- only the available grounds
```

---

## Reference files (housing-act corpus)

All under `…/jl4/experiments/housing-act-<name>.l4` (43 files). By pattern:

- Proviso / negative / gate limbs: `ground-4.l4`, `ground-13.l4`, `ground-15.l4`, `ground-5H.l4`, `ground-6.l4`
- Cases / checkbox / tables: `ground-5A.l4`, `ground-1-amended-2025.l4`, `ground-6.l4`
- Dates (+ the footgun): `ground-1-amended-2025.l4`, `ground-2ZA.l4`, `ground-2ZC.l4`, `ground-2ZD.l4`
- Deontic outcome / `#TRACE`: `ground-6.l4`, `ground-9.l4`, `ground-1.l4`
- No record-update: `ground-4A.l4`, `ground-6.l4`
- Repeal / provenance: `ground-3-repealed.l4`, `part-4-repealed.l4`, `ground-1-amended-2025.l4`, `ground-9.l4`
- Aggregation entry point: `possession-decision.l4` (the runnable PoC)
