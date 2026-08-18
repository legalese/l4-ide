# Record Update for L4 — `alice WITH age IS 31`

> **Status (2026-08-18): PROPOSED, NOT IMPLEMENTED.** No code in this repo implements record update;
> `alice WITH age IS 31` is a type error on `unstable` today (`IllegalAppNamed`, reproduced in §1.2).
> Every measurement below was taken on `origin/unstable` @ `afcef88f` using the installed
> `~/.local/bin/l4`, and every `file:line` was opened. Sections marked **MEASURED** are runs whose
> output is reproduced verbatim; sections marked **ARGUED** are design reasoning that the
> measurements constrain but do not settle.
>
> **One ruling is contested.** R2 (the surface syntax) is ruled for `alice WITH age IS 31`; the
> adversarial review's judge ruled the other way, for a distinct keyword. Both cases are set out at
> R2, and everything from R3.1 onward is written to hold either way.
>
> **Seed:** a user question — "in haskell if i want to update a record i give the name of the
> existing record and i give overrides in braces. in l4 is there a similar syntax?" The answer today
> is no, and `skills/writing-l4-rules/references/drafting-patterns.md:511` documents that as a
> **gotcha** with two workarounds. This spec asks whether the gotcha should become a feature.

---

## 0. The one-sentence proposal

Let the head of a `WITH` expression be a **value** of record type, not only a **type constructor**:

```l4
alice MEANS Person WITH name IS "Alice", age IS 30, email IS "a@x.com"   -- construction (today)
older MEANS alice  WITH age IS 31                                        -- update (proposed)
```

Construction stays **total** (every stored field, exactly once). Update is **partial** (a non-empty
subset; everything else carries through from the base).

---

## 1. What exists today — MEASURED

### 1.1 The parse already succeeds; the type checker is what refuses

This is the single most important structural fact about the proposal, and it is easy to get wrong.
`jl4-core/src/L4/Parser.hs:2100` (`namedApp`) parses `<name> WITH f IS v, …` into
`AppNamed Anno n [NamedExpr n] (Maybe [Int])` — and the head is a bare `name`, with no requirement
that it denote a type:

```haskell
namedApp = attachAnno $
  AppNamed emptyAnno
  <$> annoHole name
  <*> (annoLexeme (spacedKeyword_ TKWith) *> annoHole (lsepBy1 namedExpr (spacedSymbol_ TComma)))
  <*> pure Nothing
```

So `alice WITH age IS 31` **already parses**. The refusal happens later, in
`jl4-core/src/L4/TypeCheck.hs:2967-2974`:

```haskell
inferAppNamed r (Fun _ onts t) nes = do        -- a Fun: supply named args
  ornes <- supplyAppNamed r (zip [0 ..] onts) nes
  pure (ornes, t)
inferAppNamed r t _nes = do                    -- anything else: refuse
  addError (IllegalAppNamed r t)
```

Record construction works because a `DECLARE`d record's constructor is a `Fun` with named
arguments. `alice`'s type is `Person`, not a `Fun`, so it falls to the second clause.

**Consequence: this is a type-checker proposal, not a grammar proposal.** That fact drives R3 and
collapses most of the blast radius (§5).

### 1.2 The error today — MEASURED

```
$ l4 check recupd.l4
  Range:    8:13-8:33
  Message:
    You are trying to apply
      alice (defined at recupd.l4:6:1-6) of type Person
    (which is not a function) to (named) arguments here.
```

### 1.3 Construction is total; the completeness error is separate — MEASURED

```
$ l4 check partial.l4          # alice MEANS Person WITH name IS "Alice"   (age omitted)
    In the application of
      Person (defined at partial.l4:1:9-15)
    you forgot to supply the following arguments:
      age of type NUMBER
```

That is `IncompleteAppNamed`, raised by `supplyAppNamed` (`TypeCheck.hs:2978-2980`). Construction
and update **disagree about completeness**, and §4 (R4) has to say where that fork lives.

### 1.4 L4 already resolves same-named `WITH` heads by field-name set — MEASURED

This is the finding that makes the proposal tractable, and I did not expect it. A user function may
share a name with a record constructor, and resolution picks between them **on the supplied
argument names**:

```l4
DECLARE Person HAS name IS A STRING, age IS A NUMBER
GIVEN n IS A NUMBER
GIVETH A Person
Person MEANS Person WITH name IS "shadowed", age IS n    -- head resolves to the CONSTRUCTOR
#EVAL Person WITH n IS 7                                  -- head resolves to the FUNCTION
```

```
$ l4 run ns2.l4
Result:
  Person OF "shadowed", 7
```

Both `Person`s are in term scope simultaneously; the `{name, age}` field set selects the
constructor and the `{n}` field set selects the function. **The disambiguation channel the proposal
needs already exists and already works.** It also means update becomes one more candidate in that
fork, which is a cost — see §7.

### 1.5 Computed fields re-derive; the value stores only stored fields — MEASURED

```l4
DECLARE Person HAS
    `name` IS A STRING, `birth year` IS A NUMBER, `as at year` IS A NUMBER
    `age`   IS A NUMBER  MEANS `as at year` - `birth year`
    `adult` IS A BOOLEAN MEANS `age` >= 18
```

Respelling `alice` with `as at year IS 2030` (the long-hand update) gives:

| expression                | result                          |
| ------------------------- | ------------------------------- |
| `alice's age`             | `16`                            |
| `alice's adult`           | `FALSE`                         |
| `alice in 2030`'s `age`   | `20`                            |
| `alice in 2030`'s `adult` | `TRUE`                          |
| `#EVAL \`alice in 2030\`` | `Person OF "Alice", 2010, 2030` |

Two things follow. Computed fields **re-derive automatically** — nothing freezes. And the runtime
value carries **only the three stored fields**, so an update only ever has to rebuild the stored
tuple. R4 is therefore nearly free.

### 1.6 The head must be a bare name, and `WITH` does not chain — MEASURED

Both of these are **parse** errors today, and both remain so unless the grammar changes:

```
$ l4 check head.l4        # p1 MEANS pair's a WITH age IS 31
    13 | p1 MEANS pair's a WITH age IS 31
       |                   ^^^^
    unexpected WITH

$ l4 check head2.l4       # p2 MEANS alice WITH age IS 31 WITH name IS "B"
     5 | p2 MEANS alice WITH age IS 31 WITH name IS "B"
       |                               ^^^^
    unexpected WITH
```

The second is a direct consequence of the field list being **open-tailed** — see
`jl4-core/src/L4/Print.hs:835`, `AppNamed{} -> True  -- \`R WITH a IS 1\` — open field list`. A
trailing `WITH` cannot attach because the comma-separated field list keeps consuming. R5 must rule
on whether either is worth changing.

### 1.7 The directive `WITH` does not collide — MEASURED

`Parser.hs:613` uses `TKWith` in `#CONTRACT <expr> AT <expr> WITH <events>`. A parenthesised
`AppNamed` inside a `#TRACE` is unambiguous today:

```l4
#TRACE `deal` (Cfg WITH deadline IS 5) AT 0 WITH PARTY alice DOES pay AT 1
```

```
Result:
  FULFILLED
```

Unparenthesised it would be greedy — but that is **already true of construction**, so it is a
pre-existing condition and not a cost of this proposal. (Anti-drift note: do not let a later editor
re-file this as a new risk.)

---

## 2. Demand: how often does the corpus work around the absence? — MEASURED

The decisive question for R1. A feature that no one is working around is not earning a blast radius.

**Method.** Over all **749** `.l4` files in the tree, find `<name> WITH` blocks in which at least one
field is written `f IS <base>'s f` — the field name and the projected field name **identical**, same
base variable — and at least one other field differs. Trailing commas and `--` comments stripped.
That identity condition matters: it excludes _type conversions_, which look similar but which record
update could never help.

| tier                                 | file                                                   |  sites | field lines | pure boilerplate |
| ------------------------------------ | ------------------------------------------------------ | -----: | ----------: | ---------------: |
| shipped stdlib                       | `jl4-core/libraries/actus.l4`                          |      5 |          30 |               14 |
| shipped example                      | `jl4/examples/legal/promissory-note.l4`                |      6 |          14 |                6 |
| shipped backend corpus               | `jl4-proleg/l4/burden.l4`                              |      3 |           6 |                3 |
| **shipped subtotal**                 |                                                        | **14** |      **50** |     **23 (46%)** |
| experiments                          | `jl4/experiments/*` (7 files)                          |     23 |           — |                — |
| teaching material                    | `doc/courses/advanced/module-a3-contracts-examples.l4` |      3 |           8 |                3 |
| **false positive** (type conversion) | `jl4/examples/legal/regcf/regcf-wizard.l4:234`         |      1 |          11 |                1 |

**Whole-corpus total: 41 sites in 13 files — 127 field lines written, 58 of them (46%) pure
carry-through boilerplate. Under the proposal those 127 lines become 69.**

**Read on its own this looks modest — 13 files out of 749, 1.7% — and an earlier draft of this spec
stopped here and said so. That was wrong: §2.2 shows this scan measures only one of the two
workaround shapes and misses the larger one entirely.** The corrected figure is in §2.2; the
argument that actually decides R1 is in §2.3.

### 2.1 The archetype — `actus.l4`

The stdlib's ACTUS state-transition functions are the cleanest witnesses. `jl4-core/libraries/actus.l4:87-99`:

```l4
`STF_IP` MEANS
    `Contract State` WITH
        statusDate          IS eventDate,
        contractPerformance IS preState's contractPerformance,
        notionalPrincipal   IS preState's notionalPrincipal,
        accruedInterest     IS 0,
        nominalInterestRate IS preState's nominalInterestRate,
        feeAccrued          IS preState's feeAccrued
```

Six field lines, **four of them pure boilerplate**. Under the proposal:

```l4
`STF_IP` MEANS preState WITH statusDate IS eventDate, accruedInterest IS 0
```

And the file **already apologises for the absence in a comment** — `jl4-core/libraries/actus.l4:70`:

```l4
-- Note: L4 constructs new records rather than updating in place.
```

A shipped stdlib file carrying an apology for a missing language feature is good qualitative
evidence — but **discount it, and here is why.** `actus.l4` is the _umbrella_ module, and **nothing
imports it**: `grep -rn '^IMPORT actus'` across the corpus returns **zero** hits, and the only
occurrence of the string is inside a comment at `actus.l4:9` showing users how they _would_ import
it. Consumers (`jl4/examples/ok/actus-library-test.l4`) import the sub-modules — `actus-core`,
`actus-terms`, `actus-events`, `actus-state`, `actus-daycount`, `actus-schedule` — never the
umbrella.

So ACTUS is the cleanest _illustration_ of the update shape, and it is **not** evidence of live
demand. R1 does not rest on it; it rests on §2.2 and §2.3, whose sites are in `bna.l4`,
`regcf-denovo.l4` and the Jersey charities encodings, all of which are live.

### 2.2 ⚠️ CORRECTION — the first scan measured the wrong shape, and understated demand ~8x

**The scan in §2 is not wrong, but it is narrow, and on its own it is misleading.** It only counts
the identity-copy shape `f IS <base>'s f`. The corpus's _documented_ workaround is the other one —
a **GIVEN-parameterised constructor factory** that spells every field as a literal and takes the
varying ones as parameters (`skills/writing-l4-rules/references/drafting-patterns.md:511` names
exactly this manoeuvre). No `'s` projection appears, so the first regex is blind to all of it.

Rescanned for that shape — a `MEANS <Type> WITH` body under a `GIVEN`, ≥6 fields, fewer parameters
than fields:

|                            |                         |
| -------------------------- | ----------------------- |
| factories                  | **43**, in **23 files** |
| field lines spelled        | **588**                 |
| parameters actually varied | **154**                 |
| **frozen boilerplate**     | **434 lines (74%)**     |

and unlike the §2 sites, these are overwhelmingly in the **legal** corpus:

| file                                                             | factories | largest                                   |
| ---------------------------------------------------------------- | --------: | ----------------------------------------- |
| `jl4/examples/legal/bna/bna.l4`                                  |         7 | 19 fields spelled, 4 varied (`:660`)      |
| `jl4/examples/legal/regcf/denovo/regcf-denovo.l4`                |         6 | **38 fields spelled, 4 varied** (`:3164`) |
| `jl4/examples/legal/regcf/regcf.l4`                              |         5 |                                           |
| `paper/case-studies/charities-jersey-2014/part-7-information.l4` |         5 |                                           |
| `.../charities-cleanroom/charity-test.l4`                        |         1 | **26 fields spelled, 1 varied** (`:682`)  |
| `paper/case-studies/gco-jersey-covid/GCO-*.l4`                   |         3 |                                           |

**Combined honest total: ~84 workaround sites across ~30 files, carrying ~492 lines of pure
boilerplate.** That is roughly eight times the §2 figure, and it moves the demand from "experiments
and the stdlib" into the statutory encodings the project is actually judged on.

### 2.3 The decisive argument is not line count — it is that the workaround destroys named fields

`jl4/examples/legal/bna/bna.l4:660` spells a 19-field `PersonProfile` to vary 4, with field names
that are statutory prose:

```l4
GIVEN dob IS A DATE, `citizen parent` IS A BOOLEAN, `settled parent` IS A BOOLEAN, `forces parent` IS A BOOLEAN
GIVETH A PersonProfile
`a child born in the United Kingdom on` dob `citizen parent` `settled parent` `forces parent` MEANS PersonProfile WITH
    `born in the United Kingdom`                      IS TRUE
    `father or mother a British citizen at the time of the birth`   IS `citizen parent`
    `found abandoned as a new-born infant in the United Kingdom`    IS FALSE
    ... 16 more ...
```

Now look at what the **call sites** become. `paper/case-studies/charities-jersey-2014/part-8-appeals.l4:747`:

```l4
`the refused applicant` MEANS
    `an appeal` TRUE FALSE FALSE FALSE
                `a decision to refuse to register the applicant`
                `Victoria College Trust, but campaigning` `Victoria College Trust, but campaigning`
                FALSE FALSE FALSE
```

and `part-7-information.l4:983`:

```l4
`the document notice on the Cat Sanctuary` MEANS
    `an Article 26(1) notice` `the Jersey Cat Sanctuary, a registered charity` TRUE FALSE FALSE TRUE TRUE FALSE FALSE
```

**Seven anonymous positional booleans**, in a corpus that spends backticked statutory prose on every
single field name. The workaround does not merely cost lines — **it throws away the labelled-field
readability that is the whole reason L4 has named record fields**, and it does so precisely in the
scenario/fixture sections a lawyer is most likely to read.

Under the proposal the same scenario keeps its labels, and one canonical base replaces N factories:

```l4
`a UK-born child` MEANS PersonProfile WITH ...19 fields, once...

`the refused applicant` MEANS `an appeal` WITH
    `the appellant is the applicant`  IS TRUE
    `the decision appealed`           IS `a decision to refuse to register the applicant`
```

This — not the line count — is the argument R1 should turn on.

### 2.4 What survives on the other side: the demand is fixture-sited

The one finding of the legal-fitness review that survived its own refutation: of the 17 places the
corpus complains in comments about the missing operator, **15 sit under literal test/fixture
headings** (`§ Tests`, `§§ Scenarios`, `§§ Fixtures — constructors that vary one thing at a time`,
`§§ A claim constructor — so test cases vary only the fields they care about`), and the two whose
headings look operative are test material on inspection. **Recorded honestly: this is a
test-ergonomics feature.** §4.3 argues that is not the demotion it sounds like, because
scenarios-as-tests is a first-class part of what L4 sells — but the spec should not pretend the
demand is coming from operative rule text. It is not.

### 2.5 What even the corrected count does _not_ capture — ARGUED

The count measures **workarounds that were written**. It cannot measure uses that were never
attempted because the workaround deters them. The clearest such use is **scenario variation**:
"the same facts, but the claimant is one year older", "the same policy, but as at 2030". §1.5 shows
that respelling one field re-derives every computed determination downstream — which is exactly the
_what-if_ move that L4's pitch rests on (the negotiation-stage "each party defines a dozen scenarios
that become tests" idea). Today each such scenario costs a full record respelling, which is why the
corpus has GIVEN-parameterised constructor factories instead (`ground-4A.l4`) — and why it has
relatively few scenarios at all.

**This is an argument, not a measurement, and it is the one a reviewer should attack hardest.**
§8 states what would falsify it.

---

## 3. Blast radius — MEASURED (every module opened)

`AppNamed` is matched in **18 modules across three packages** (word-boundary `grep -rlw`). (An earlier
draft said 16, then 19; 16 grepped
only `jl4-core/src/L4/` and missed `jl4-mlir`; 19 wrongly counted `TypeCheck/Types.hs`, which
contains no bare `AppNamed` — only the _error_ constructors `IllegalAppNamed`/`IncompleteAppNamed`
at `:94-95`. Both slips are recorded rather than quietly fixed, because an undercounted blast radius
is exactly the drift CLAUDE.md warns about.)
The reason the radius is nonetheless small is §1.1: **the surface
syntax is byte-identical to construction**, so the lexer, the parser, and both printers need no
change whatsoever.

| module                                   | what it does with `AppNamed`                                      | effect of update                                       |
| ---------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------ |
| `Parser.hs:2100`                         | builds the node from `<name> WITH …`                              | **no change** — already parses                         |
| `Print.hs:666`                           | prints `printWithLayout n <+> "WITH" <+> …`                       | **no change** — same surface                           |
| `Print.hs:835`                           | `openTailed` guard, for bracketing                                | **no change** — same bracketing need                   |
| `ExactPrint` (`Rules.ExactPrint`)        | re-emits concrete tokens                                          | **no change** — tokens unchanged                       |
| `Syntax.hs:247`                          | the constructor                                                   | new flag or new node (R3)                              |
| `TypeCheck.hs:2771,2967`                 | `resolveTerm` → `inferAppNamed`                                   | **the whole change lives here**                        |
| `TypeCheck/Types.hs`, `…/Annotation.hs`  | error types, annotation                                           | one new error constructor                              |
| `Desugar.hs:62,351`                      | traverses fields; strips computed fields                          | traversal unchanged; see R4                            |
| `EvaluateLazy/Machine.hs:854-870`        | evaluates via the typechecker's `Just order` permutation          | needs a partial-rebuild path (R3)                      |
| `Dmn/Lower.hs:1980-1984`                 | three-way guard: head ∈ `neRecordCtors` ∧ arity ∧ exact field set | **fails all three → `verbatim`/Blocking — fails safe** |
| `Dmn/Analysis.hs:171`                    | `namedArgsPositional nes mOrder`                                  | needs partial-order handling                           |
| `Export/Document.hs:263-272`             | **fabricates** an `AppNamed` to render records                    | synthetic node must stay construction-flagged          |
| `Nlg.hs:209`                             | renders `<head> "where" <fields>`                                 | **reads correctly** — "alice where age is 31"          |
| `StateGraph.hs:474`                      | `Just (getUnique n)` — head as state identity                     | head is now a value, not a ctor — check                |
| `OpenFisca/Lower.hs:403`                 | diagnostic label only                                             | harmless                                               |
| `Docassemble/Lower.hs:1217`              | `LFFatal` on **all** named application, construction included     | **zero new cost** — already refused                    |
| `jl4-mlir/…/Lower.hs:1659,1709`          | reports the record's named type; uniform f64 ABI                  | slot layout assumes the full field set                 |
| `jl4-mlir/…/Schema.hs:609,668,1505,1754` | schema walk + `chainList` over the named-expr values              | positional over a **partial** list                     |
| `jl4/tests/DmnExport.hs`                 | test-side matching                                                | test update                                            |

Two of these deserve emphasis because they are the ones a reviewer will assume are blockers:

**DMN is not a blocker; it fails safe.** `jl4-core/src/L4/Dmn/Lower.hs:1980-1984` gates the
record-construction lowering on a three-way conjunction:

```haskell
AppNamed _ r nes _
  | Just fields <- Map.lookup (getUnique r) names.neRecordCtors   -- head is a record ctor
  , length nes == length fields                                    -- arity matches
  , Map.keysSet supplied == Set.fromList fields ->                 -- exact field set
```

An update head is not in `neRecordCtors` and its field list is partial, so it fails all three
independently and falls through to `verbatim e`, reported **Blocking**. It cannot silently emit a
context with missing entries — which the comment above that arm says was the whole point of the
guard ("a missing entry would answer null where L4 has a value"). R6 rules on whether to do better
than Blocking.

**Neither printer changes.** CLAUDE.md §3.2 warns that `L4.Print.prettyLayout` must re-parse and
re-type-check across ~300 files with **no exclusion list permitted**. Because update prints as
`<head> WITH <fields>` exactly like construction, the round-trip property holds by construction —
the printed text is the text that parsed. The evaluation differential of CLAUDE.md §3.2.1 should
still be run, but there is no expected delta.

---

## 4. Is this good for _law_? — ARGUED, on measured ground

The hostile question is not "can we build it" but "should a language for law have it". Two of the
three arguments usually offered for record update **do not survive contact with this repo**, and the
spec is better for saying so.

### 4.1 The amendment argument FAILS — the repo already answers it, better

The tempting case: legal texts amend by delta ("in section 5, for 'eight months' substitute
'twelve months'"), so a delta operator is natively legal. **This is wrong, and it is the argument a
careless spec would lead with.**

Amendment operates on **rules**. Record update operates on **values**. The repo's actual answer to
legislative amendment is **version-per-file plus the temporal rule-version axis**. See
`paper/case-studies/gco-jersey-covid/`, which encodes the Jersey COVID Gathering Control Order three
times over:

```
GCO-first-version.l4     -- as first enacted (R&O.166/2020)
GCO-as-at-20210115.l4    -- as amended by R&O.189/2020 + R&O.1/2021
GCO-as-repealed.l4       -- as last in force
```

with the file headers stating the technique outright: _"Parallel skeleton with GCO-first-version.l4
and GCO-as-repealed.l4 to make diffs easy to spot. DIFFS vs first enacted are called out with
`-- DIFF:` markers."_ That, plus `EVAL UNDER RULES EFFECTIVE AT` (`specs/todo/TEMPORAL-MASTER.md`),
is the amendment story. **Record update contributes nothing to it, and any spec claiming otherwise
is conflating rules with facts.**

Likewise `jl4/examples/.../ground-3-repealed.l4` handles a repealed provision with a labelled inert
stub, not a delta.

### 4.2 The mutation-optics objection is real but answered by the ledger's existence

L4 sells determinism and auditability. `WITH` on a value _looks_ like mutation to a non-programmer.
And L4 already owns the vocabulary of state change: `RECORD`, `COMMIT`, `ATTEST`, `RECALL` are all
reserved keywords (`jl4-core/src/L4/Lexer.hs:319-323`) belonging to STATE-AS-LEDGER
(`Syntax.hs:263-330`). There is a genuine risk a drafter reaches for `WITH` where the append-only
ledger is meant.

The answer is that the two are **not competitors**: the ledger records _that a change happened, by
whom, when_; record update names _a different value_. `older` is not `alice` mutated — it is a
second value that happens to agree with `alice` on two fields out of three. §6/R7 requires the
documentation to say this in one sentence at the point of introduction.

### 4.3 The argument that survives: scenario variation, and it is the one L4 is _for_

L4's pitch rests on scenarios-as-tests — each party naming the dozen situations it cares about, and
those becoming runnable tests across drafts. §1.5 measured what makes that cheap: changing one
**stored** field re-derives every **computed** field beneath it. `alice WITH \`as at year\` IS 2030`
is a counterfactual, evaluated, with the derivation intact.

Today each counterfactual costs a full record respelling, which is why the corpus reaches for
GIVEN-parameterised constructor factories (`ground-4A.l4`, whose own comment explains the manoeuvre)
and why it has relatively few counterfactuals at all. **The demand count in §2 measures workarounds
written, not scenarios abandoned** — and the second number is the one this feature is really about.

That is an argument, not a measurement. §8 states what would falsify it.

### 4.4 And the boring one: a shipped stdlib file apologises in a comment

`jl4-core/libraries/actus.l4:70` — `-- Note: L4 constructs new records rather than updating in
place.` Six field lines where two would do, five times over in one file (§2.1). This is small, real,
and not going away.

---

## 5. Risks — MEASURED (each reproduced by hand)

An adversarial review ran five hostile lenses over this proposal and then tried to refute its own
findings. The findings below are the ones **I reproduced myself** with `l4 check` on
`origin/unstable` @ `afcef88f`; each shows the actual output. §5.6 records the precedent that makes
the type-checker risk concrete.

### 5.1 ⚠️ THE BIG ONE — partiality deletes the check that catches a mis-parse

The `WITH` field list is **open-tailed** (`Print.hs:835`). A field value that is a bare **name**
followed by another `WITH` binds the inner `WITH` **to that name**, not to the outer head:

```l4
DECLARE Person HAS name IS A STRING, age IS A NUMBER
DECLARE Pair   HAS x IS A Person,    y IS A NUMBER
alice MEANS Person WITH name IS "A", age IS 1
p MEANS Pair WITH x IS alice WITH y IS 2          -- inner WITH attaches to `alice`
```

```
    In the application of
      Pair (defined at slurp.l4:2:9-13)
    you forgot to supply the following arguments:
      y of type NUMBER
```

**Today this mis-parse is caught — but only because the OUTER construction is total.**
`IncompleteAppNamed` is the sole diagnostic standing between the drafter and a silently swallowed
field.

**Predicted (not measured — update does not exist yet):** when the outer head is itself an _update_,
the field list is partial by design, so a slurped field is simply not updated and **nothing is
reported**. `claim WITH x IS alice WITH y IS 2` would silently drop the `y` update.

This is the strongest technical objection in the review and R2/R5 must answer it. Note precisely
what it does _not_ say: the hazard is not partiality alone and not slurping alone, it is **the two
composed**. Whatever is ruled must keep a total check somewhere on that path.

Note also the asymmetry (also measured): whether a following `WITH` attaches at all depends on
whether the preceding field value was a **literal** or a **name**. With a literal it is a clean
parse error (§1.6); with a name it silently re-binds.

### 5.2 A local binding shadows the constructor outright — and lands in the proposed branch

```l4
DECLARE Person HAS name IS A STRING, age IS A NUMBER
GIVEN Person IS A NUMBER
GIVETH A Person
g MEANS Person WITH name IS "x", age IS Person
```

```
    You are trying to apply
      Person (predefined) of type NUMBER
    (which is not a function) to (named) arguments here.
```

Construction becomes **unreachable**, and the failure lands in **exactly the `IllegalAppNamed`
branch this proposal repurposes**. Repurposing it silently converts this diagnostic into an attempt
to "update a NUMBER".

This corrects the optimistic reading in §1.4: **top-level** same-named definitions resolve fine by
field set (measured there), but a **`GIVEN`/local** binder shadows the constructor entirely
(measured here). Both are true; they are different scopes, and a spec that cites only the first is
sharpening a claim past its evidence.

### 5.3 Nullary enum constructors and sum-typed values also land in that branch

```l4
DECLARE Colour IS ONE OF red, green, blue
bad MEANS red WITH age IS 31
```

```
      red (defined at nullary.l4:1:26-29) of type Colour
    (which is not a function) to (named) arguments here.
```

```l4
DECLARE Payment IS ONE OF
    Paid HAS amount IS A NUMBER
    Owed HAS amount IS A NUMBER, since IS A NUMBER
p MEANS Paid WITH amount IS 40
q MEANS p WITH amount IS 50           -- p : Payment; WHICH ARM?
```

```
      p (defined at sumarm.l4:4:1-2) of type Payment
    (which is not a function) to (named) arguments here.
```

The sum case is genuinely undecidable at the type level: `p`'s static type is `Payment`, and `Paid`
and `Owed` disagree about the field set. R4 must restrict update heads to values of a
**single-constructor record type** and reject the rest by name.

### 5.4 The totality argument — raised as fatal, and it does NOT survive

The review's other **fatal** finding: `IncompleteAppNamed` makes a drafter answer every question the
statute asks, and partial `WITH` deletes that obligation on syntax indistinguishable from
construction. **An earlier draft of this spec accepted that. It is wrong on the code, and I checked.**

`inferAppNamed` (`TypeCheck.hs:2968`) reaches `supplyAppNamed` — and therefore
`IncompleteAppNamed` — **only when the head's type is `Fun _ onts t`**. A value head is never a
`Fun`. So every type-headed construction in the corpus keeps totality **in full**, unchanged; the
proposal only ever touches the `:2971` fallback that today emits `IllegalAppNamed`. **No existing
diagnostic is lost on any program that compiles today.**

What remains is the weaker, real claim: _a reader cannot tell whether a given `X WITH …` is total
without knowing whether `X` names a type or a value._ That is a legibility cost, not a lost check,
and it is what R2 weighs.

The associated "then it becomes ambiguous whenever a value shares a type's name" objection is
**empirically empty**. Measured over all 749 `.l4` files:

|                                                                          |                                                   |
| ------------------------------------------------------------------------ | ------------------------------------------------- |
| `DECLARE`d type names                                                    | **583** (368 are single-constructor record types) |
| top-level `MEANS` names                                                  | **2,749**                                         |
| names used as **both**                                                   | **6**                                             |
| …of which a **record type** sharing a name with a value **of that type** | **0**                                             |

The six are `EULER`, `TAN_EPSILON`, `Month`, `foo`, `baz` (none record types — the first two are the
`DECLARE X IS A NUMBER` type-signature idiom, the rest toy fixtures) and `Money`, where
`DECLARE Money HAS …` lives in `doc/courses/…/module-a3-contracts-examples.l4:10` while
`` `Money` MEANS `` in `jl4-core/libraries/currency.l4:148` is an unrelated **function**
(`GIVETH AN EITHER STRING STRING`) in a different module.

So the collision is a theoretical hazard at **measured frequency zero**, and the safe tweak costs
nothing: **keep today's ambiguity error whenever a name resolves to both a constructor and a value.**
That is the status quo, so nothing regresses and nothing is silently chosen.

### 5.5 The ledger collides on the pun, not on the semantics

`specs/done/STATE-AS-LEDGER-SPEC.md:52` says, verbatim:

> `RECORD`/`COMMIT` also name the append-only semantics honestly — you do not _update_ a record,
> you add to it (D2).

and Decision **D2** at `:92` is a **CONFIRMED, shipped** ruling. Taken at face value this reads as a
standing prohibition. It is not: D2 governs **ledger state cells**, and the _same sentence_ cites
`Foo WITH field IS value` **approvingly**, as the model for the ledger's own syntax. "Record" there
is the ledger sense (a record _of what happened_), not the data-type sense.

So the collision is **terminological, and therefore an optics risk rather than a design bar** — but
it is a real one, because the sentence a lawyer will read says "you do not update a record". Any
documentation must disambiguate the two senses at the point of introduction.

The stronger form of the objection — that the two would sit "one token apart in the same visual
slot" — is **false, and measured false**. The ledger write requires a _quoted cell name_:

```l4
#EVAL RECORD alice's age IS 31
```

```
    4 | #EVAL RECORD alice's age IS 31
      |                      ^^^
    unexpected age
    expecting String Literal, quoted cell name, or space token
```

`RECORD <party>'s "<cell>"` names a **party and a cell**; `<value> WITH <field> IS v` names a
**value and a field**. They are not substitutable, today or under the proposal.

### 5.6 ⚠️ Precedent: the last feature that touched this machinery was reverted

This is the risk with a track record. `specs/todo/TYPICALLY-DEFAULTS-SPEC.md:14-41`:

> An initial full implementation of TYPICALLY was attempted on branch `mengwong/635` but was
> **reverted due to a critical heisenbug in the type checker's name disambiguation logic.** … The bug
> was in `dedupByOrigin` / `allSameTermDescriptor` logic … Only actual `trace` output (with stderr
> I/O side effects) prevented the bug. … **Consider a simpler approach that doesn't require complex
> name disambiguation.**

Reverted commits `6fea6b8e`..`afba20a0`, bundled in `53f4e718`. Verified against the tree: both
functions are **gone** (`grep` finds neither in `jl4-core/src/`), but the machinery they perturbed is
very much alive — `forkWithLazyFallback` (`TypeCheck/Types.hs:1279`), `AmbiguousTermError`, and
`InternalAmbiguityError` (`TypeCheck.hs:5123`, whose text is literally _"I have encountered a name
ambiguity at a position where I did not expect this to be possible"_).

`forkWithLazyFallback preambleErr cands fallback kont` runs every candidate through the continuation
and, unless **exactly one** succeeds, appends the fallback. **Adding record update as a new
candidate would widen `cands` at every `WITH` site** — which is the shape of change that produced
the revert, and which the review's `appnamed-fork-blowup` finding independently flags against the
measured smucclaw#929 exponential (CLAUDE.md notes that history).

**§6/R3 rules against ever doing that**, and §1.4 plus `resolveTerm'` show why it is unnecessary.

### 5.7 The deontic subject is recovered from the fields written at the call site

`jl4-core/src/L4/TypeCheck.hs:1683`, inside `subjectOfActionExpr`:

```haskell
AppNamed _ _ nes _   -> subjectField partyT [ a | MkNamedExpr _ _ a <- nes ]
```

It strips the field **names** and hands `subjectField` the values. The review filed this as
"the deontic performer is erased by a partial update"; **measured, that overstates it for
construction** — writing the fields out of order still resolves the subject correctly, because
`subjectField` searches by _type_ (`partyT`), not by slot:

```l4
inOrder    MEANS Act WITH performer IS alice, what IS "pay"
outOfOrder MEANS Act WITH what IS "pay", performer IS alice
```

Both `#TRACE`s return `FULFILLED`.

The real hazard is narrower and survives: **this traversal only sees the fields written at the call
site.** A partial update that _omits_ the party field — the common case, since the party is exactly
the thing you would carry through unchanged — leaves no party-typed value in `nes` at all, and the
subject becomes unrecoverable. Any implementation must consult the base value's fields here, not
just the written ones. (Predicted, not measured: update does not exist yet.)

---

## 6. What the adversarial review actually returned

Five hostile lenses (grammar, type-checking, semantics, blast radius, legal fitness) produced **39
findings**; each lens's findings were then handed to a separate agent instructed to **refute** them,
defaulting to "refuted" under uncertainty. Every surviving finding below I re-reproduced myself — and
where a refutation was itself wrong, I say so (R6 is the clearest case).

|                                             | count |
| ------------------------------------------- | ----: |
| findings raised                             |    39 |
| raised as **fatal**                         |    12 |
| **fatal findings that survived refutation** | **0** |
| survived as **major**                       | **3** |
| survived as **minor**                       |     7 |

Ten distinct findings survived in all. The seven minors are `demand-is-100pct-test-fixtures`,
`computed-field-head-not-rewritten`, `parser-head-is-a-bare-name`,
`chaining-depends-on-literal-vs-name`, `infvar-head-undecidable`, `overload-two-successes` and
`sum-arm-unsound`; each is answered by a ruling in §7.

The three majors — and only these — are load-bearing for the design (`shadowed-ctor` was raised
independently by two different lenses):

| id                         | what it is                                                        | mitigation (all use machinery already in the tree) |
| -------------------------- | ----------------------------------------------------------------- | -------------------------------------------------- |
| `shadowed-ctor`            | a local binder of the same name deletes the constructor candidate | resolve the head under `LocalsSpareSelectors`      |
| `comma-slurp`              | a nested unbracketed `WITH` swallows the outer comma list         | bracketing rule; **zero corpus churn**             |
| `head-must-be-a-bare-name` | `AppNamed`'s head is a `Name` in the AST, not an `Expr`           | accept the limit in v1 (R5)                        |

Two headline objections were raised as **fatal** and did **not** survive; both are corrected in place
above, because a spec that quietly drops a refuted objection teaches nothing: the totality argument
(§5.4) and the ledger-collision argument (§5.5).

---

## 7. Rulings

> Numbering is `R<n>`. Each ruling states the measurement that drove it. Where a ruling reverses
> something written earlier in this document, it says so.

### R1 — SHIP. Ruled 2026-08-18.

The corrected demand (§2.2: 43 factories, 588 field lines spelled to vary 154, **74% frozen**,
concentrated in `bna.l4`/`regcf-denovo.l4`/the Jersey charities files) plus §2.3 (the workaround
**destroys named fields**, degrading call sites to `` `an appeal` TRUE FALSE FALSE FALSE ``) clears
the bar. The blast radius is unusually small (§3) because the surface is byte-identical to
construction, so neither printer nor the exact-printer changes at all.

**Ruled honestly against §2.4:** the demand is **fixture-sited**, not operative-rule-sited. This is a
test-and-scenario ergonomics feature. §4.3 argues that is squarely within what L4 sells; a reader who
rejects that should read R1 as "don't ship" and go to §8.

**Not a reason to ship:** legislative amendment (§4.1). That is answered by version-per-file plus the
temporal axis, and conflating rules with facts here would be an error.

### R2 — Surface: keep `<value> WITH <field> IS <v>`. Ruled 2026-08-18.

Adopt the proposal as written, i.e. upstream issue **smucclaw/l4-ide#438** as filed (2025-05-19).
Rejected alternatives: a distinct keyword and the no-new-syntax routes. (`EXCEPT` in particular is
**not** available — see the table.)

The case for a distinct keyword was the totality-legibility argument, and **§5.4 measured it away**:
no existing diagnostic is lost, and the ctor/value name collision that would force a reader to
disambiguate occurs **0 times** in 583 type names against 2,749 value names.

#### The alternatives that were weighed

Every candidate is free in the **lexer** table (`Lexer.hs:245-332`, checked individually):
`EXCEPT`, `SAVE`, `COPYING`, `AMENDED`, `LIKE`, `BUT`, `SUBSTITUTING`, `VARYING`, `OVERRIDE`,
`RESTATED`. Lexical availability is not the whole test, though — `EXCEPT` is free in the lexer and
still ruled out below, because another spec in this repo has already claimed it for a different
meaning.

| candidate                                | reads as                         | why not                                                                                                                                                                                                                                            |
| ---------------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `alice WITH age IS 31`                   | **chosen**                       | zero new tokens; identical to `#438` as filed; §5.4 removes the legibility objection's factual basis                                                                                                                                               |
| `alice EXCEPT age IS 31`                 | real legal idiom ("except that") | **ruled out on a collision**: `EXCEPT WHEN` is claimed by `specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md` (`:3`, `:475`, `:635`, `:691`) for **defeating a rule** — an adjacent, differently-typed meaning one token away from copying a **value** |
| `alice RESTATED WITH age IS 31`          | "amended and restated"           | **the named fallback** — free in the lexer, 1 corpus occurrence, and the idiom means exactly "re-issued with changes"; costs a new `Expr` constructor across 19 exhaustively-matched files                                                         |
| `alice SAVE THAT age IS 31`              | the most lawyerly option         | two tokens; `THAT` is not a keyword and adding it is a wider change than the feature                                                                                                                                                               |
| `alice AMENDED BY age IS 31`             | amendment framing                | **actively misleading** — §4.1: amendment is a rules-level operation answered by the temporal axis, and this name would invite exactly the rules/facts conflation the spec warns against                                                           |
| auto-derived per-field withers (desugar) | no new syntax                    | **the serious rival — see below**                                                                                                                                                                                                                  |
| documentation only                       | no change                        | rejected on §2.2/§2.3 — 43 factories, 74% frozen, and call sites that degrade to anonymous booleans                                                                                                                                                |

The distinct-keyword options are not _wrong_; they are unnecessary. **The named fallback is
`RESTATED WITH`** — `alice RESTATED WITH age IS 31` — not `EXCEPT`: `RESTATED` is free in the lexer
table, occurs once in the whole corpus, and "amended and restated" is real drafting idiom for
_re-issuing a document with changes_, which is exactly the semantics. Reach for it if §5.4's
collision count ever comes back non-zero, or if R3's resolution knobs prove unsafe.

The cost of that fallback is the honest one: a distinct keyword needs a new `Expr` constructor, and
`Expr` is matched exhaustively — with `-Wall -Werror` (`jl4-core/jl4-core.cabal:35`) and no `_ ->`
catch-all in e.g. `Desugar.rewriteFieldRefs` (`Desugar.hs:330-375`) — across **19 files**, including
three the `AppNamed` census in §3 does not reach: `jl4-core/src/L4/Viz/Ladder.hs`,
`jl4-lsp/src/LSP/L4/Viz/Ladder.hs`, `jl4-query-plan/src/L4/Decision/QueryPlan.hs`. That is precisely
why R3 rules for a **flag on `AppNamed`** rather than a new node.

#### ⚠️ Dissent — the review's judge ruled the other way, and this ruling is genuinely contested

**The synthesising judge ruled `DON'T SHIP` on the surface proposed here**, in favour of a distinct
reserved keyword — `alice RESTATED WITH age IS 31` — with a new `Restate` AST node. Its reasoning,
recorded because a spec that hides the strongest objection to its own ruling is not worth reading:

- The two surviving majors (`shadowed-ctor`, `comma-slurp`) are _the same two_ that the keyword kills
  **by construction** rather than by mitigation: one token of lookahead decides the reading in the
  **parser**, so no resolution fork exists to become ambiguous, and the update field list becomes a
  **different production** that can carry its own nesting rule without touching `namedApp`.
- Because a keyword's nesting rule is new-syntax-only, it **cannot** break an existing file. R6's
  bracketing rule modifies the existing `WITH` production; I measured its churn at zero, but zero
  measured is weaker than zero possible.
- `RESTATED` is free everywhere (`grep -rwn` over `.hs`/`.l4`/`.md` returns nothing), and
  "amended and restated" is the standard instrument idiom for _carry everything forward, state what
  changed_ — a total result from a partial diff, which is the semantics exactly.

**Why I have nonetheless kept `alice WITH age IS 31` as the ruling:** it is what smucclaw#438 asks
for and what this spec was commissioned to specify; §5.4 measured the collision that motivates the
keyword at frequency **zero**; and R3's three resolution knobs plus R6 answer both majors with
machinery that already exists. But the margin is thin, and the judge's case is the better one if
either of two things is true — R3's knobs regress anything (§8.2/§8.3), or a future corpus produces a
non-zero collision count.

**Meng's call, not mine.** If the answer is the keyword, R3.1, R4, R5 and R6 all carry over unchanged;
only the parser alternative and the AST node change. That is deliberate — the rest of this spec was
written to be surface-agnostic.

#### The rival that nearly won: auto-derived withers

The strongest alternative is a **desugar-only** change: for each `DECLARE`d record, generate one
total-construction updater per stored field. It has an exact precedent already shipping —
`desugarCFDeclare` (`Desugar.hs:233-243`) already expands one `DECLARE` into `[TopDecl]` via
`makeComputedDecide` (`:263-296`) and rewrites the original to `storedFields` only (`:237`). The
generated shape:

```l4
GIVEN `_self` IS A R, `_new` IS A <type of fi>
GIVETH A R
`R with fi` `_self` `_new` MEANS R WITH f1 IS `_self`'s f1, …, fi IS `_new`, …, fn IS `_self`'s fn
```

It was **hand-run and works today**, chaining included, with no grammar change; the `_self` hygiene
is sound because the lexer rejects a leading underscore at source while `quoteIfNeeded`
(`Print.hs:1185-1189`) round-trips it.

**Why it still loses.** Three costs, in increasing order of seriousness:

1. **Namespace**: ~693 new top-level names (one per stored field in the corpus) in LSP completion.
2. **Round-trip load**: desugaring runs _inside_ type-checking (`TypeCheck.hs:186`), and the
   round-trip test prints `prettyLayout (filterIdeDirectives tc.module')` (`jl4/tests/Main.hs:261`),
   so every generated wither must round-trip across all 300 files with **no exclusion list**
   (CLAUDE.md §3.2).
3. **The precedent already loses information downstream.** With the _existing_ computed-field
   desugar, `l4 render --format text` drops a computed field from the rendered record **and** does
   not show it as a provision, because `Export/Document.hs:210` maps every `Decide` to a unit and
   there is no synthetic/generated marker anywhere in the tree to filter on. Withers would multiply
   that unfixed interaction by ~693 across six consumers.

And decisively, it **reproduces the very problem §2.3 identifies**: `` `Person with age` alice 31 ``
re-positionalises the argument that record syntax had labelled. The whole reason to prefer update
over the constructor-factory workaround is that the factory's call sites decay into anonymous
positional arguments; a wither chain decays the same way.

**Held as a designed, demand-triggered fallback**: if R3's resolution knobs regress anything
(§8.2/§8.3), withers are the retreat, and this paragraph is the design.

Also ruled: **`#438`'s second ask, "support for colons please", is already shipped** —
`Parser.hs:689`, `separator = spacedKeyword_ TKIs <|> hidden (spacedSymbol_ TColon)`; verified,
`Person WITH name: "Alice", age: 30` evaluates. The issue should be updated to say so.

### R3 — Disambiguate at resolution, via knobs that already exist. Ruled 2026-08-18.

**Do not add a candidate to the overload fork.** §5.6's precedent is explicit: the last change to
named-argument disambiguation (`TYPICALLY`, `dedupByOrigin`/`allSameTermDescriptor`) was reverted for
a heisenbug, and its post-mortem says _"consider a simpler approach that doesn't require complex name
disambiguation."_

`resolveTermFilteredIn` (`TypeCheck/Types.hs:1131-1139`) **already** takes all three knobs needed, and
`resolveTerm'` (`:1039`) currently passes the identity for two of them:

```haskell
resolveTermFilteredIn :: LocalShadowing -> Bool -> (TermKind -> Bool) -> (Type' Resolved -> Bool) -> …
resolveTerm' p n = resolveTermFiltered False p (const True) n pure
--                 ^ LocalsShadowAll                ^ viab = unused
```

So the ruling is **three arguments at one call site**, not a redesign:

| knob                 | value at the `AppNamed` head                                                                                     | fixes                    |
| -------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `LocalShadowing`     | `LocalsSpareSelectors` (`Types.hs:1049`; already used by `resolveProjectionLabel` at `:1083`, filter at `:1167`) | `shadowed-ctor`          |
| `viab`               | keep `Fun`-typed candidates when any exists, else keep all — _the filter built for smucclaw#929_                 | `overload-two-successes` |
| `TermKind` predicate | `Constructor` ⇒ construct; `isValueBinding` ⇒ update                                                             | the dispatch itself      |

**AST: a flag on `AppNamed`, not a new node.** A new constructor would touch all 18 modules of §3; a
flag leaves every generic traversal correct and both printers untouched. `Export/Document.hs:263-272`
fabricates an `AppNamed` to render records — that synthetic node must be construction-flagged.

> **Contested.** The judge ruled the opposite — a new `Restate` node — precisely _because_ a flag
> compiles silently in all 18 consumers while a new constructor makes `-Wall -Werror` turn each into
> a forced question. That argument is strong, and it is weakened only by R3.1: if the node never
> reaches a consumer, there is little for the forced question to discover. Decide this together with
> R2, not separately.

#### R3.1 — Elaborate update away in the type checker. **This is the most important ruling here.**

Whatever the surface and whatever the node, **update must be erased before the checked module is
returned** — rewritten into an ordinary, _total_ `AppNamed` whose supplied-field set equals the
declaration's, with the carried fields spelled as projections. The elaboration target is exactly the
idiom the corpus already writes by hand:

```l4
older MEANS alice WITH age IS 31
-- elaborates to:
older MEANS Person WITH name IS alice's name, age IS 31, email IS alice's email
```

`inferExpr` already rebuilds and returns the node (`TypeCheck.hs:2771-2776`), and
`constructorsInScopeFromEntityInfo` (`TypeCheck.hs:1828-1839`) supplies the type→constructor lookup
whose `Fun _ onts t` is precisely the `[OptionallyNamedType Resolved]` that `supplyAppNamed`
consumes. So the elaboration has everything it needs and costs one function.

**What this buys — and it is most of the spec's cost:**

|                                                                             | without elaboration                            | with elaboration                                                   |
| --------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| `supplyAppNamed` / `IncompleteAppNamed`                                     | must learn a partial mode                      | **untouched** — the two completeness regimes never share a line    |
| DMN (`Dmn/Lower.hs:1980-1984`)                                              | fails the totality guard → `verbatim`/Blocking | guard satisfied **by construction**; lowers to a full FEEL context |
| `jl4-mlir` slot layout                                                      | fed a partial field list                       | fed the complete list it already assumes                           |
| `Export/Document`, `Nlg`, `StateGraph`, `OpenFisca`, `EvaluateLazy/Machine` | each needs a partial-aware arm                 | **unchanged — the shape they see is unchanged**                    |
| §5.7 deontic subject (`TypeCheck.hs:1683`)                                  | must consult the base value                    | **dissolved** — the party field is present after elaboration       |

This supersedes the "fail safe, then expand" framing in R7 and removes the §5.7 hazard outright. It
is the single change that turns this from an 18-module proposal into a 4-site one.

**Two obligations that come with it, both easy to miss:**

1. **Bind a non-trivial head before duplicating it.** The elaboration mentions the head once per
   carried field, so an _n_-field update of a computed head would evaluate that head _n_ times.
   If the head is not already a variable, bind it to a fresh hygienic name (`LET`/`WHERE`) first.
   Reuse the `_self` precedent around `Desugar.hs:268`: the lexer rejects a leading underscore at
   source, so the name is uncollidable, and `Print.hs`'s `quoteIfNeeded` (`:1185-1189`) backticks it
   so it re-parses.
2. **Duplicate field names are an explicit error.** Do _not_ let
   `findOptionallyNamedType`'s consume-the-`ont` behaviour (`TypeCheck.hs:2986-3005`) silently make
   `alice WITH age IS 1, age IS 2` mean "second wins".

**The `viab` knob is not hypothetical — here is the program it protects.** L4 permits one name to be
overloaded as **both** a record value and a named-argument function, and it runs today:

```l4
acme MEANS Person WITH name IS "Acme Person", age IS 1        -- acme : Person
GIVEN name IS A STRING, age IS A NUMBER
GIVETH A Company
acme MEANS Company WITH name IS name, age IS age              -- acme : STRING AND NUMBER -> Company

#EVAL acme WITH name IS "z", age IS 9
```

```
Result:
  Company OF "z", 9
```

Today the value branch is a type error, so resolution discards it and the answer is unambiguous.
**Naively adding update makes both branches type-check with different result types** (`Person` vs
`Company`), turning a working program into an ambiguity error — or, worse, silently flipping which
overload wins. Passing `viab` = _keep `Fun`-typed candidates when any exists_ drops the value branch
**before** the fork, so this program keeps printing `Company OF "z", 9`. This is the single most
important reason R3 is a resolution ruling and not an `inferAppNamed` ruling.

**Fail safe on `InfVar`.** When the head's type is still an inference variable, keep today's
`IllegalAppNamed`. This follows the convention already in the file — `isPrimitiveType` has
`InfVar{} -> False -- Unknown type, don't skip analysis` (`TypeCheck.hs:2933-2936`). Update fires only
on a concrete record type.

### R4 — Partial field lists; single-constructor record types only; computed fields re-derive. Ruled 2026-08-18.

- **Partial is the point.** A non-empty subset; unwritten stored fields carry through from the base.
- **Head type must have exactly one constructor.** `constructorsInScopeFromEntityInfo`
  (`TypeCheck.hs:1828-1839`, keyed by `resultTypeHeadUnique`, already consumed by `checkConsider`)
  answers this. Reject enum values (`red WITH …`, §5.3) and multi-arm sums (`p : Payment`, §5.3) at
  check time with a named diagnostic. Measured over the 749 tracked `.l4` files:
  **641 `DECLARE … HAS` against 425 `DECLARE … IS ONE OF`** — single-constructor records are the
  _more_ common idiom, so this restriction does not gut the feature. (The review reported 418/375;
  my own count differs on scanning window and on excluding the untracked `seqsim/` copy. The ratio,
  which is the load-bearing part, is the same either way.) It is also **stricter than Haskell**, which permits multi-constructor update and fails at
  runtime.
- **Computed fields re-derive, and may not be supplied.** §1.5 measured the re-derivation (`age`
  16→20, `adult` FALSE→TRUE) and the value carries only stored fields. The
  `SuppliedComputedField` diagnostic already exists and already fires clearly:
  _"The field `age` is a computed field and cannot be supplied in a record constructor."_ Reuse it
  verbatim, adjusting the wording for update.
- **A sibling computed field cannot be an update base.** `Desugar.hs:351-352` rewrites only `nes` and
  passes the head `n` through untouched, so `home WITH city IS "Zurich"` inside a computed-field body
  fails. It fails _loudly_ (twice), and it fails identically today, so this is a **documentation
  obligation**, not a defect — but the current message says "this is most likely an internal error",
  which should be replaced with a real explanation.

### R5 — Head is a bare name **or a parenthesised expression**. Ruled 2026-08-18.

`AppNamed`'s head is a `Name` in the AST (`Syntax.hs:248`), not merely in the grammar. Widening it to
`Expr` touches exact-printing, `prettyLayout`'s 300-file round-trip (CLAUDE.md §3.2, **no exclusion
list permitted**), the lazy machine, `Dmn/Lower` and `OpenFisca/Lower`.

**Accepted cost, stated plainly:** `alice's spouse WITH age IS 31` — the most common Haskell
record-update idiom — **cannot be written at all**, and this is the one surviving major with no
workaround. Verified: a parenthesised head does not rescue it either (`(alice) WITH age IS 2` is a
parse error). Building a list of variants _does_ work bracketed:
`LIST (bob WITH age IS 1), (bob WITH age IS 2)` parses.

**Revised after review: admit a parenthesised head.** The grammar becomes

```
update-head ::= name | '(' expr ')'
```

This costs one parser alternative and dissolves most of the finding. It matters for a second reason:
without it there is **no escape hatch** — an author who hits §5.2's constructor shadowing has no way
to spell which reading they meant, because `(alice) WITH age IS 2` is a parse error _today_
(reproduced independently by two lenses). With a parenthesised head, nested update becomes
expressible if verbose:

```l4
alice WITH addr IS ((alice's addr) WITH city IS "Zurich")
```

Still deferred: an unparenthesised general head (`alice's spouse WITH age IS 31`). And **chaining is
not supported in v1** — write one field list; the parenthesised form covers the rest.

### R6 — Bracketing rule for a nested `WITH` in field-value position. Ruled 2026-08-18.

This answers §5.1, the sharpest technical objection. Today `Pair WITH x IS alice WITH y IS 2` binds
the inner `WITH` to `alice` and is caught **only** because the outer construction is total; under
partial update both levels become legal and the diagnostic vanishes.

**Ruled: a `WITH` appearing in field-value position may not consume the enclosing comma list —
parenthesise it.** The correct meaning is already expressible today
(`Person WITH spouse IS (bob WITH age IS 9), name IS "a"` parses and the outer receives all fields).

**Measured cost of the rule: zero — but state the rule precisely, or it is not zero.** The review
reported "only two sites, neither affected". **That undercounts, and I checked.** Nested
unparenthesised `WITH` in field-value position is _common_: ~15 real sites, including
`jl4/experiments/purchase.l4:75`, `jl4/examples/legal/promissory-note.l4:40,53`,
`jl4/experiments/promissory-note-{amount,list,tracking}.l4`,
`doc/courses/advanced/module-a3-contracts-examples.l4:71`, and — with commas inside the nested
`WITH` — `jl4/examples/ok/json-encode-comprehensive.l4:40,56`:

```l4
DECIDE alice IS Person WITH
  name IS "Alice"
  age IS 30
  address IS Address WITH street IS "Elm St", city IS "Seattle"
```

So the rule **must not** be "a nested `WITH` may not consume commas" — that would break all of these,
because the inner `WITH` legitimately consumes _its own_ comma list. The outer list here is separated
by **layout**, not commas (`lsepBy1` = `someLines`, `Parser.hs:1226-1233`), so nothing is ambiguous.

**The rule bites only when the _enclosing_ field list is itself comma-separated.** Scanned for
exactly that — a nested unparenthesised `WITH` whose enclosing field list also uses commas:
**0 sites in 749 files.** The churn is genuinely zero, and now for a reason that will survive
someone re-checking it.

### R7 — Backends: nothing to do under R3.1. Ruled 2026-08-18.

> **Superseded in part by R3.1.** With elaboration in the type checker, **no backend sees an update
> at all**, and this whole ruling collapses to "nothing to do". What follows is the fallback if
> R3.1 is not adopted — and the gap between the two columns is the best argument for adopting it.

- **DMN**: the guard at `Dmn/Lower.hs:1980-1984` is a three-way conjunction (head ∈ `neRecordCtors` ∧
  arity ∧ exact field set). Without elaboration an update fails **all three independently** and falls
  to `verbatim` → **Blocking**: safe, but a `DEGRADED` export. **With R3.1 the guard is satisfied by
  construction and the node lowers to a full FEEL context** — which matters because FEEL has no
  context-merge operator, so there is no good direct lowering to reach for.
- **Docassemble**: `Lower.hs:1217` already `LFFatal`s **all** named application including
  construction. Zero new cost.
- **`jl4-mlir`**: 11 occurrences across `Lower.hs`/`Schema.hs`; the slot layout and `chainList` walk
  the named-expr values positionally. Must be given the expanded field set, not the written subset.
- **The deontic subject** (§5.7): `TypeCheck.hs:1683` recovers the party from the fields written at
  the call site. An update that omits the party field — the common case — must consult the **base
  value's** fields, not just the written ones. This is the one place where "carry through silently"
  is not safe.

---

## 8. Kill criteria — what would make this not worth building

Stated so the spec is falsifiable. If any of these turns out to hold, R1 flips to "don't ship".

1. **The scenario argument is the load-bearing one and it is an argument, not a measurement**
   (§2.5, §4.3). It says drafters would write more counterfactuals if each cost one line instead of
   twenty. **Falsified if:** a drafter given the feature keeps writing constructor factories anyway.
   **Measurement that settles it:** take the five `bna.l4` factories (`:660,687,717,746,776`), rewrite
   the scenario block against one canonical base, and have a knowledge engineer who did not write
   either version say which they would maintain. This is cheap and should be done **before** the
   implementation, not after.
2. **If the `LocalsSpareSelectors` switch at the `AppNamed` head turns out to regress anything.** R3
   asserts it cannot, because every `AppNamed` on a local head is an error today. **Falsified by:** a
   single golden that changes. The comment at `Types.hs:1152-1163` argues explicitly why that policy
   is _not_ used at ordinary occurrences — read it before touching this.
3. **If the `viab` pre-filter reintroduces the smucclaw#929 exponential** rather than damping it.
   #929 was a measured exponential from AND/OR overloads; the filter exists to cut candidates, so it
   should help — but **falsified by:** `jl4/examples/legal/charities-cleanroom/` type-check time
   regressing.
4. **If the bracketing rule (R6) turns out to cost corpus churn.** Measured at zero — but only under
   the _precise_ statement of the rule (it bites solely when the **enclosing** list is
   comma-separated; ~15 sites nest a `WITH` under a layout-separated list and must keep working).
   **Falsified by:** any site appearing where a nested unparenthesised `WITH` sits inside a
   comma-separated enclosing field list.
5. **If a `TYPICALLY`-style heisenbug reappears.** The tell from last time: behaviour that changes
   when `trace` statements are removed. If that recurs, **stop and revert** rather than debug — the
   December 2025 attempt lost more time to debugging than the feature was worth.

## 9. Implementation order

Deliberately staged so the risky thing is provable before anything irreversible happens.

| #   | step                                                                       | why here                                                      |
| --- | -------------------------------------------------------------------------- | ------------------------------------------------------------- |
| 0   | The §8.1 readability experiment on `bna.l4`                                | cheapest possible falsification of R1; do it first            |
| 1   | `viab` + `LocalsSpareSelectors` at the `AppNamed` head, **no feature**     | proves R3's knobs regress nothing, on their own, with goldens |
| 2   | The update node/flag + R4's single-constructor gate + **R3.1 elaboration** | the feature; elaboration is part of step 2, not a follow-up   |
| 3   | R3.1's head-binding and duplicate-field checks                             | correctness, not polish — see R3.1's two obligations          |
| 4   | R6 bracketing rule                                                         | independent; do after the semantics are settled               |
| 5   | R5 parenthesised head                                                      | one parser alternative; dissolves the third major             |

**No step for the evaluator, and no step for any backend.** That is R3.1's dividend: elaboration
happens before the checked module is returned, so `EvaluateLazy/Machine.hs`, `Dmn/Lower`, `jl4-mlir`,
`Export/Document`, `Nlg`, `StateGraph` and `OpenFisca` all see the total `AppNamed` they already
handle. If R3.1 is **not** adopted, add back: an evaluator partial-rebuild path, a `jl4-mlir`
expanded field set, DMN expansion-at-export, and the §5.7 deontic base-consultation.

Per CLAUDE.md §3.2.1, run the **evaluation differential** after step 2 even though §3 predicts no
printer delta — the property that matters is that a printed module still _means_ the same thing, and
that is exactly what a bad elaboration would break.

## 10. Prior art in-tree

- **smucclaw/l4-ide#438**, _"syntax for record updates (e.g. RecordInstance WITH)"_ — open since
  2025-05-19, labelled `enhancement, language design, ready-to-start`. **This spec is that issue.**
  Its example is `NewRecord MEANS OldRecord WITH bar IS 40`. `kosmikus` commented: _"We could make
  this simpler by disallowing type-changing updates."_ R4's single-constructor gate and R3's
  concrete-type requirement together implement that suggestion; a type-changing update is not
  expressible under either.
- **smucclaw/l4-ide#420**, _"default values for named arguments to make writing 'stateupdate'-like
  functions easier"_ — the rival design. Answered by `TYPICALLY`
  (`specs/todo/TYPICALLY-DEFAULTS-SPEC.md`, **PARTIALLY LANDED**: metadata-only since `27cd4770`, no
  presumptive evaluation). The two are complementary, not competing: defaults reduce what you must
  write at a _construction_; update reduces what you must write given an _existing value_. Neither
  subsumes the other, and #420's own status note says its `stateupdate` motivation is still blocked.
- `specs/done/STATE-AS-LEDGER-SPEC.md` D1/D2 — the append-only ledger. §5.5: terminological overlap
  only; D1 cites `Foo WITH field IS value` approvingly as the register to match.
- `skills/writing-l4-rules/references/drafting-patterns.md:511` — documents the absence as a gotcha
  with the two workarounds. **Update this in the same PR as any implementation** (CLAUDE.md §4).
- `jl4-core/libraries/actus.l4:70` — `-- Note: L4 constructs new records rather than updating in
place.` Delete this comment when the feature lands; it is the file's own apology for its absence.

## 11. Open questions

| #   | question                                                                                      | what would settle it                                                                                                                                                               |
| --- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | Should update be allowed to _widen_ to a supertype, or strictly preserve the head's type?     | kosmikus's #438 comment says disallow type-changing; R4 follows, but no one has tested whether a widening case exists in the corpus                                                |
| Q2  | Does the trace/provenance layer need an explicit node for carried-through fields?             | `inherited-fields-have-no-trace-node` was **refuted** (derived values have no ledger entry today either), but no one has looked at what `#EVALTRACE` _prints_ for a chained update |
| Q3  | Should `l4 batch`/the REPL print an update back as an update, or expand it to a construction? | §3 says the printer needs no change, which implies "as an update" — but that has not been round-tripped, because the feature does not exist                                        |
