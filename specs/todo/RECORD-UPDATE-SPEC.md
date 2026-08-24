# Record Update for L4 — `alice BUT WITH age IS 31`

> **Status (2026-08-18): PROPOSED, NOT IMPLEMENTED.** No code in this repo implements record update;
> `alice WITH age IS 31` is a type error on `unstable` today (`IllegalAppNamed`, reproduced in §1.2).
> Every measurement below was taken on `origin/unstable` @ `afcef88f` using the installed
> `~/.local/bin/l4`, and every `file:line` was opened. Sections marked **MEASURED** are runs whose
> output is reproduced verbatim; sections marked **ARGUED** are design reasoning that the
> measurements constrain but do not settle.
>
> **R2 was reversed on 2026-08-19.** The spec first ruled for the bare `alice WITH age IS 31` of
> smucclaw#438; the adversarial review's judge dissented for a distinct keyword; the keyword half of
> that dissent was conceded and the word itself re-argued, landing on **`alice BUT WITH age IS 31`**.
> The reasoning and the reversal are recorded at R2/R2.1/R2.2 rather than rewritten away, because the
> road not taken is what makes R3's simplification legible.
>
> **Reviewed 2026-08-20, second-head pass.** Every load-bearing citation was re-verified against the
> tree and nine defects corrected in place, each with a dated note at the point of correction. The
> two substantive ones: R3.1's obligations block still carried the superseded bare-`WITH` design's
> obligations in place of the real ones (now R3.1 obligations 1–3, with the bare-`WITH` material
> reframed as R3.2), and `elaborateUpdates` must fill the evaluator's argument-order slot — the
> machine crashes on `Nothing` (`EvaluateLazy/Machine.hs:856-858`).
>
> **Seed:** a user question — "in haskell if i want to update a record i give the name of the
> existing record and i give overrides in braces. in l4 is there a similar syntax?" The answer today
> is no, and `skills/writing-l4-rules/references/drafting-patterns.md:511` documents that as a
> **gotcha** with two workarounds. This spec asks whether the gotcha should become a feature.

---

## 0. The one-sentence proposal

Give L4 an update form whose head is a **value** of record type, spelled with a reserved `BUT`:

```l4
alice MEANS Person WITH name IS "Alice", age IS 30, email IS "a@x.com"   -- construction (today)
older MEANS alice BUT WITH age IS 31                                     -- update (proposed)
```

The seed request (smucclaw#438) was for the bare `alice WITH age IS 31`. R2 rules against that and
for `BUT WITH`, on grounds that only became visible after the adversarial review; §R2.1 is why a
keyword, §R2.2 is why this keyword.

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
namedApp :: Parser (Expr Name)
namedApp = do
  attachAnno $
    AppNamed emptyAnno
    <$> annoHole name
    <*> (   annoLexeme (spacedKeyword_ TKWith) *> annoHole (lsepBy1 namedExpr (spacedSymbol_ TComma))
        )
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

**Consequence:** the bare-`WITH` reading of this proposal would have been a _type-checker_ change
with no grammar change at all — which is what made it tempting, and what R2 ultimately ruled against
(the same absence of a grammatical discriminator is why `shadowed-ctor` and `comma-slurp` bite). Under
the ruled `BUT WITH` a grammar change is exactly what buys the safety. Either way, the fact that
`inferAppNamed`'s second clause is the _only_ thing standing between today and update is what makes
the semantic core small.

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
| experiments                          | `jl4/experiments/*` (8 files)                          |     23 |           — |                — |
| teaching material                    | `doc/courses/advanced/module-a3-contracts-examples.l4` |      3 |           8 |                3 |
| **false positive** (type conversion) | `jl4/examples/legal/regcf/regcf-wizard.l4:234`         |      1 |          11 |                1 |

**Whole-corpus total, false positive excluded: 40 sites in 12 files — 116 field lines written, 57
of them (49%) pure carry-through boilerplate. Under the proposal those 116 lines become 59.**
_(Corrected 2026-08-20: the headline previously read "41 sites in 13 files — 127/58/69", which
counted the false-positive row into its own total — the method statement above excludes type
conversions — and the experiments row undercounted its files at 7. An independent re-scan
reproduced the `actus.l4` and `burden.l4` rows exactly and enumerated 8 experiment files.)_

**Read on its own this looks modest — 12 files out of 749, 1.6% — and an earlier draft of this spec
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
`STF_IP` MEANS preState BUT WITH statusDate IS eventDate, accruedInterest IS 0
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
| `jl4/examples/legal/charities-cleanroom/charity-test.l4`         |         1 | **26 fields spelled, 1 varied** (`:682`)  |
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
is exactly the drift CLAUDE.md warns about.) (A third slip, caught in the 2026-08-20 review: the
table below listed `TypeCheck/Types.hs` and `ExactPrint` — neither matches the grep — and omitted
`Parser/ResolveAnnotation.hs`, which matches at `:477` and `:1276` and is exactly where the new
production's annotation resolution lands. The table now agrees with the census; the count 18 was
right throughout.)

> **Read this table as the census of what _could_ be affected, not of what R2/R3 actually touch.**
> It was written for the superseded bare-`WITH` surface, whose selling point was that the syntax is
> byte-identical to construction. Under the ruled `BUT WITH` the lexer and parser **do** change (one
> keyword, one production), and a new `Update` constructor forces an arm in each row. But under
> **R3.1** that node is elaborated by a _late_ pass, so every row below except `Print.hs` and
> `TypeCheck.hs` (which checks `Update` itself and hosts §5.7's `subjectOfActionExpr` arm) still
> only ever _sees_ the total `AppNamed` it already handles. The arms are one-liners; the
> behaviour is unchanged. The rightmost column is kept in the bare-`WITH` framing because that is the
> analysis that produced R3.1, and R3.1 is the reason the radius collapses — except two cells
> corrected 2026-08-20 (`Nlg`, `Export/Document`) where the bare-`WITH` claim would actively mislead
> under R3.1.

| module                                                                                     | what it does with `AppNamed`                                      | effect of update                                                                             |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `Parser.hs:2100`                                                                           | builds the node from `<name> WITH …`                              | **no change** — already parses                                                               |
| `Parser/ResolveAnnotation.hs:477,1276`                                                     | attaches annos and refs to the parsed node (two traversals)       | new production needs arms in both                                                            |
| `Print.hs:666`                                                                             | prints `printWithLayout n <+> "WITH" <+> …`                       | **no change** — same surface                                                                 |
| `Print.hs:835`                                                                             | `openTailed` guard, for bracketing                                | **no change** — same bracketing need                                                         |
| `ExactPrint.hs` _(not a census match — generic over `Anno`; listed for the printer story)_ | re-emits concrete tokens                                          | **no change** — tokens unchanged                                                             |
| `Syntax.hs:248`                                                                            | the constructor                                                   | new flag or new node (R3)                                                                    |
| `TypeCheck.hs:2771,2967`                                                                   | `resolveTerm` → `inferAppNamed`                                   | **the whole change lives here**                                                              |
| `TypeCheck/Annotation.hs`                                                                  | annotation traversal                                              | one new arm (the error constructors live in `TypeCheck/Types.hs:94-95`, not a census member) |
| `Desugar.hs:62,351`                                                                        | traverses fields; strips computed fields                          | traversal unchanged; see R4                                                                  |
| `EvaluateLazy/Machine.hs:854-870`                                                          | evaluates via the typechecker's `Just order` permutation          | needs a partial-rebuild path (R3)                                                            |
| `Dmn/Lower.hs:1980-1984`                                                                   | three-way guard: head ∈ `neRecordCtors` ∧ arity ∧ exact field set | **fails all three → `verbatim`/Blocking — fails safe**                                       |
| `Dmn/Analysis.hs:171`                                                                      | `namedArgsPositional nes mOrder`                                  | needs partial-order handling                                                                 |
| `Export/Document.hs:263-272`                                                               | **fabricates** an `AppNamed` to render records                    | fabricated node is a construction — unaffected; but renders the elaboration (R3.1 cost 3)    |
| `Nlg.hs:209`                                                                               | renders `<head> "where" <fields>`                                 | read correctly under bare-`WITH` only; under R3.1 verbalizes the elaboration — R3.1 cost 3   |
| `StateGraph.hs:474`                                                                        | `Just (getUnique n)` — head as state identity                     | head is now a value, not a ctor — check                                                      |
| `OpenFisca/Lower.hs:403`                                                                   | diagnostic label only                                             | harmless                                                                                     |
| `Docassemble/Lower.hs:1217`                                                                | `LFFatal` on **all** named application, construction included     | **zero new cost** — already refused                                                          |
| `jl4-mlir/…/Lower.hs:1659,1709`                                                            | reports the record's named type; uniform f64 ABI                  | slot layout assumes the full field set                                                       |
| `jl4-mlir/…/Schema.hs:609,668,1505,1754`                                                   | schema walk + `chainList` over the named-expr values              | positional over a **partial** list                                                           |
| `jl4/tests/DmnExport.hs`                                                                   | test-side matching                                                | test update                                                                                  |

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
and not going away. And it is not alone: the live legal corpus carries the same apology —
`jl4/examples/legal/charities-cleanroom/charity-test.l4:678`, _"Full record literals: L4 has no
record-update operator, so each scenario spells every field."_ (Found 2026-08-20 while verifying
§2.2's citation of that file.)

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

**Disposition (2026-08-19): survives R2, and is answered by R6.** A keyword does not stop the slurp —
`x IS y BUT WITH f IS v, z IS 3` still lets the inner list eat the comma — but because `BUT WITH` is a
new production, R6's bracketing rule cannot break an existing file. Note precisely
what this finding does _not_ say: the hazard is not partiality alone and not slurping alone, it is **the two
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

**Disposition (2026-08-19): DISSOLVED by R2.** Under `BUT WITH` the parser has already decided, so
`Person BUT WITH …` is unambiguously an update of the local and construction is spelled
`Person WITH …`. The finding is retained because it is the single sharpest argument for the keyword
and would return immediately if the bare-`WITH` surface were revived.

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

(The two probes above are spelled in _today's_ syntax, because that is what produced the output
quoted. Under R2 they read `red BUT WITH …` and `p BUT WITH …`, and the keyword does **not** help
here — this is the one major hazard a keyword leaves entirely untouched, which is why R4's
single-constructor gate is load-bearing rather than belt-and-braces.)

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
without knowing whether `X` names a type or a value._ That is a legibility cost, not a lost check.
**R2 dissolved it on 2026-08-19**: under `BUT WITH`, total and partial are visibly different syntax,
so the reader never has to resolve a name to know which rules apply.

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

**Disposition (2026-08-19): OPEN, and re-opened deliberately.** The first R3.1 dissolved this by
elaborating inside the checker, so this traversal only ever saw a total `AppNamed`. The re-ruled
R3.1 elaborates **late**, and `subjectOfActionExpr` runs **during** checking — so it will see
`Update` and must consult the base's declaration itself. That is the price of printer and LSP
fidelity, and it is one function.

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

| id                         | what it is                                                        | disposition under R2's `BUT WITH`                                                                              |
| -------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `shadowed-ctor`            | a local binder of the same name deletes the constructor candidate | **dissolved** — the parser decides, so the head is never resolved through a construct/update fork (R2.1)       |
| `comma-slurp`              | a nested unbracketed update swallows the outer comma list         | **survives**; answered by R6, whose rule now attaches to a new production and so cannot break an existing file |
| `head-must-be-a-bare-name` | `AppNamed`'s head is a `Name` in the AST, not an `Expr`           | **mostly dissolved** — R5 admits a parenthesised head, which a keyword makes cheap                             |

Two of the three majors are answered by the **surface** ruling rather than by mitigation. That is the
substance of R2.1, and it is why the 2026-08-18 ruling was reversed.

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
the bar. The blast radius is small (§3): 18 modules match `AppNamed`, and under R2+R3.1 all but two
need only one-line `-Werror` arms. _(Corrected 2026-08-20: this sentence originally said the surface
was "byte-identical to construction, so neither printer nor the exact-printer changes at all" — true
of the superseded bare-`WITH` surface only. Under R2 the lexer, the parser and `prettyLayout` all
change, deliberately — §9 calls the printer arm "the point".)_

**Ruled honestly against §2.4:** the demand is **fixture-sited**, not operative-rule-sited. This is a
test-and-scenario ergonomics feature. §4.3 argues that is squarely within what L4 sells; a reader who
rejects that should read R1 as "don't ship" and go to §8.

**Not a reason to ship:** legislative amendment (§4.1). That is answered by version-per-file plus the
temporal axis, and conflating rules with facts here would be an error.

### R2 — Surface: `<value> BUT WITH <field> IS <v>`. Ruled 2026-08-19, reversing the 2026-08-18 ruling.

```l4
alice MEANS Person WITH name IS "Alice", age IS 30, email IS "a@x.com"   -- construction
older MEANS alice BUT WITH age IS 31                                     -- update
```

`BUT` becomes a reserved keyword; `BUT WITH` is a distinct production from `namedApp`.

**This reverses the first ruling**, which kept the bare `alice WITH age IS 31` of
smucclaw/l4-ide#438. The reversal has two halves, decided separately:

- **A distinct keyword beats overloading `WITH`.** Conceded to the review's judge — its argument is
  in §R2.1 and it is right. The two surviving majors are killed _by construction_ rather than by
  mitigation.
- **But the keyword is `BUT WITH`, not the judge's `RESTATED WITH`.** Reasons in §R2.2. In short:
  `RESTATED` is amendment vocabulary, and §4.1 rules that amendment is **not** what this feature is
  for.

#### R2.1 — Why a keyword wins (conceded to the review's judge)

One token of lookahead decides the reading **in the parser**, before any name resolution or type
information is consulted. That is not a smaller version of the bare-`WITH` design; it is a different
one, and it dissolves rather than mitigates:

| finding                         | under bare `WITH`                                                | under `BUT WITH`                                                                                                              |
| ------------------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `shadowed-ctor` (§5.2)          | needs `LocalsSpareSelectors` at the head                         | **dissolved** — `Person BUT WITH …` is unambiguously an update of the local; construction is spelled `Person WITH …`          |
| `overload-two-successes`        | needs the `viab` filter to avoid a two-success fork              | **dissolved** — there is no fork; the parser has already decided                                                              |
| `comma-slurp` (§5.1)            | R6's rule modifies the **existing** `WITH` production            | R6's rule applies to a **new** production, so it _cannot_ break an existing file — structurally zero churn, not measured-zero |
| §5.4's residual legibility cost | a reader must resolve the head to know whether the list is total | **dissolved** — total and partial are visibly different syntax                                                                |

The last row is worth pausing on, because §5.4 spent a lot of effort measuring the collision
frequency at zero in order to argue the legibility cost away. A keyword makes the argument
unnecessary: you can see which one you are reading.

#### R2.2 — Why `BUT WITH` and not `RESTATED WITH`

**The register has to match the ruled use case, and `RESTATED`'s does not.** §4.1 rules that
legislative and contract amendment are **not** a reason to ship this — that is answered by
version-per-file plus the temporal axis, and treating a delta over _rules_ and a delta over _facts_
as the same operation is precisely the conflation this spec warns against. On that basis `AMENDED BY`
was rejected in the table below as "actively misleading".

"Amended and restated" is _the_ instrument-amendment idiom. `RESTATED WITH` therefore commits the
same category error as `AMENDED BY`, one step removed — and the judge chose it **for** that instrument
register. But §2.4 rules the demand is **fixture- and scenario-sited**: variation over _facts_. What
the 43 constructor factories of §2.2 simulate is "the same claimant, but with a later date of birth".
That sentence is `BUT WITH`.

**Verified safe to reserve** (all on `origin/unstable` @ `afcef88f`):

| check                                                 | result                                                                                                                                                                                                                                                        |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BUT` in the lexer keyword table (`Lexer.hs:245-332`) | **free**                                                                                                                                                                                                                                                      |
| uppercase `BUT` in the 749 `.l4` files                | 10 occurrences — **all** inside `--` comments or backticked `§§` titles                                                                                                                                                                                       |
| `BUT` as a **bare token** anywhere in the corpus      | **0**                                                                                                                                                                                                                                                         |
| `<expr> BUT WITH …` today                             | **already a parse error** — and the error lands on `WITH`, with `BUT` consumed as an identifier                                                                                                                                                               |
| claimed by any sibling spec                           | **no** — `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` enumerates `SUBJECT TO`, `NOTWITHSTANDING`, `DESPITE`, `EXCEPT WHEN`, `WITHOUT AFFECTING`, `QUALIFIED BY`, `PROVIDED`, `UNLESS`; `BUT` appears nowhere, and its §512 moves _away_ from more connective keywords |

The fourth row is the one that matters for compatibility: because any program containing
`<expr> BUT WITH` **already fails to parse**, reserving `BUT` cannot silently change the meaning of
a program that compiles today. It can only break a bare-token use of `BUT` as an identifier, and
there are none.

**House style fits.** L4 already builds multi-word constructs from individually reserved words —
`GREATER`+`THAN`, `AT`+`LEAST`/`MOST`, `FOLLOWED`+`BY` (`Lexer.hs:301-311`). `BUT`+`WITH` is that
shape. And keeping `WITH` visible means the field list reads identically in construction and update:
a reader sees `WITH f IS v` and knows what it is, with `BUT` as a one-word marker on an otherwise
unchanged production.

**The one real objection, recorded because it is not silly.** In statutory prose a bare "but" usually
signals a **proviso** — "…but this shall not apply where…" — so a lawyer may read _restriction_ where
variation is meant. The rebuttal, accepted 2026-08-19: English "but **with** X" is unambiguously
variation, unlike bare "but", and the following `WITH` is doing that disambiguating work in the
surface syntax as well as in the grammar. If field evidence ever contradicts this, `RESTATED WITH` is
the fallback and R2.1 carries over unchanged.

#### The alternatives that were weighed

Every candidate is free in the **lexer** table (`Lexer.hs:245-332`, checked individually):
`EXCEPT`, `SAVE`, `COPYING`, `AMENDED`, `LIKE`, `BUT`, `SUBSTITUTING`, `VARYING`, `OVERRIDE`,
`RESTATED`. Lexical availability is not the whole test — `EXCEPT` is free in the lexer and still
ruled out, because another spec has claimed it for a different meaning.

| candidate                                | reads as                            | verdict                                                                                                                                                                                                                  |
| ---------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `alice BUT WITH age IS 31`               | "the same, but with X"              | **CHOSEN** (R2.2) — register matches the ruled use case; safe to reserve; keeps the `WITH` field list visible                                                                                                            |
| `alice RESTATED WITH age IS 31`          | "amended and restated"              | **the named fallback.** Structurally equivalent (R2.1 carries over), but the idiom points at _instrument amendment_ — the use case §4.1 rules OUT                                                                        |
| `alice WITH age IS 31`                   | the bare overload, as #438 filed it | **ruled out 2026-08-19** — needs R3's resolution knobs to mitigate two majors that a keyword dissolves outright                                                                                                          |
| `alice EXCEPT age IS 31`                 | "except that"                       | **collision**: `EXCEPT WHEN` is claimed by `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` (`:3`, `:475`, `:635`, `:691`) for **defeating a rule** — an adjacent, differently-typed meaning one token away from copying a **value** |
| `alice AMENDED BY age IS 31`             | amendment framing                   | **actively misleading** — §4.1; the same objection that demotes `RESTATED`                                                                                                                                               |
| `alice SAVE THAT age IS 31`              | the most lawyerly option            | `THAT` is not a keyword; adding it is a wider change than the feature, and "save that" is exception vocabulary, not variation vocabulary                                                                                 |
| auto-derived per-field withers (desugar) | no new syntax                       | **the serious rival — see below**                                                                                                                                                                                        |
| documentation only                       | no change                           | rejected on §2.2/§2.3 — 43 factories, 74% frozen, call sites that decay to anonymous booleans                                                                                                                            |

**The cost of the keyword route, stated plainly.** A distinct keyword needs a new `Expr` constructor,
and `Expr` is matched exhaustively — `-Wall -Werror` (`jl4-core/jl4-core.cabal:35`), no `_ ->`
catch-all in e.g. `Desugar.rewriteFieldRefs` (`Desugar.hs:330-375`) — across **19 files**, three of
which the `AppNamed` census in §3 does not reach: `jl4-core/src/L4/Viz/Ladder.hs`,
`jl4-lsp/src/LSP/L4/Viz/Ladder.hs`, `jl4-query-plan/src/L4/Decision/QueryPlan.hs`.

That is the honest price, and R2.1 is the argument that it is worth paying. Under R3.1 seventeen of
those 19 arms are trivial — the node is elaborated away before anything downstream can see it — so
the cost is 17 one-line cases, two real arms (`Print.hs`; `TypeCheck.hs`, per R3.1), and a forced
read of each consumer, not 19 real ports.

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

### R3 — Disambiguation lives in the PARSER. New AST node, elaborated LATE. Ruled 2026-08-19.

**Superseded the 2026-08-18 ruling**, which put the decision in name resolution and reused
`AppNamed` with a flag. That design existed to defend the bare-`WITH` surface; R2 having ruled for
`BUT WITH`, it is no longer the cheapest correct thing.

- **Parser.** A new alternative beside `namedApp` (`Parser.hs:1846`). The `BUT` token decides;
  **no type information and no name resolution are consulted.** This is the whole point of R2.1.
- **AST.** A new constructor — `Update Anno (Expr n) [NamedExpr n]` — beside `AppNamed`
  (`Syntax.hs:248`). **Not a flag.** A flag would compile silently in all 18 consumers of §3; a new
  constructor makes `-Wall -Werror` turn each into a forced question. The sharpest instance is
  `Dmn/Lower.hs:1980-1984`, whose record→FEEL guard is a totality conjunction: a partial `AppNamed`
  fails it silently and emits pretty-printed L4 inside a FEEL literal, and no test catches that. _(Naming ruled
  2026-08-24: earlier drafts called the node `Restate` — the judge's rejected keyword imported into
  the compiler. R2.2's register argument applies internally too: constructor names leak into `Show`
  output, diagnostics and contributor vocabulary, and `RESTATED WITH` is the named fallback surface,
  which the node must not pre-commit to. `Update` matches `elaborateUpdates`, this spec's own title,
  and #438's language. `RecordUpdate` — GHC's `RecordUpd` precedent notwithstanding — was rejected
  because `RECORD` already carries the ledger sense in L4 and appears in traces (§5.5); a third
  sense of "record" would compound the pun.)_
- **Type checker.** `Update` gets a real `inferExpr` case — it has to, for R4's gates — and
  **survives into the returned module**. It is elaborated by a later pass; see R3.1, which was
  re-ruled on 2026-08-19 and is the ruling that pays for everything else.
- **Head resolution.** The head resolves as an ordinary term, then must be a **value binding of
  single-constructor record type** (R4). A `TermKind`/type filter is still wanted here, and
  `resolveTermFilteredIn` (`TypeCheck/Types.hs:1131-1139`) already takes both a `TermKind` predicate
  and a `viab` type filter. **But note the difference from the superseded design:** there, the
  filters had to be tuned so as not to regress programs that compile today; here they cannot regress
  anything, because **no existing program uses this syntax**. That removes §8's second and third kill
  criteria outright. R3.2 holds the measured witness for why the filter is wanted, and the `InfVar`
  fail-safe.

**What this ruling no longer needs.** The 2026-08-18 design turned on three knobs at the `AppNamed`
head — `LocalsSpareSelectors`, the smucclaw#929 `viab` filter, and the `TermKind` predicate — chosen
specifically to avoid widening the overload fork, because the last change to that machinery
(`TYPICALLY`, §5.6) was reverted for a heisenbug. **Under `BUT WITH` there is no fork to widen**, so
the precedent in §5.6 stops being a live risk rather than being mitigated. The knobs are recorded
here as the road not taken, and because they are exactly what a future bare-`WITH` revival would
need.

#### R3.1 — Elaborate update LATE, not in the checker. Re-ruled 2026-08-19.

> **This reverses the first R3.1**, which elaborated inside `checkProgram` so that
> `CheckResult.program` contained no `Update` at all. That was wrong in a way the earlier draft did
> not notice, and the whole of Q3 was a symptom of it.

**The ruling.** `Update` **survives into `CheckResult.program`**. A dedicated pass —
`elaborateUpdates :: Module Resolved -> Module Resolved` — produces a _second_ projection, and the
evaluator and every backend consume **that**. The elaboration itself is unchanged: `Update` becomes
an ordinary, _total_ `AppNamed` whose supplied-field set equals the declaration's, with carried
fields spelled as projections — exactly the idiom the corpus already writes by hand:

```l4
older MEANS alice BUT WITH age IS 31
-- elaborates to:
older MEANS Person WITH name IS alice's name, age IS 31, email IS alice's email
```

`constructorsInScopeFromEntityInfo` (`TypeCheck.hs:1828-1839`) supplies the type→constructor lookup
whose `Fun _ onts t` is precisely the `[OptionallyNamedType Resolved]` the construction needs, so the
pass has everything it requires and costs one function.

**Why late and not early.** Elaborating in the checker would have mirrored `desugarComputedFields`,
which `TypeCheck.hs:186` applies as `checkProgram (desugarComputedFields program)`. **Copying that
placement copies its known defect.** `CheckResult` has a single `program` field
(`TypeCheck/Types.hs:582`), and the LSP takes it verbatim — `module' = result.program`
(`jl4-lsp/src/LSP/L4/Rules.hs:713`). So early elaboration does not merely change `l4 batch` output:

| consumer                                        | under early elaboration                                             | under late elaboration                   |
| ----------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------- |
| `prettyLayout` (`l4 batch`, REPL, DMN fallback) | prints the elaborated **construction**                              | prints `BUT WITH`, as written            |
| LSP hover / semantic tokens                     | resolve against the construction — **hovering `BUT` finds nothing** | resolve against what the author typed    |
| `exactprint` / `l4 format`                      | unaffected either way (generic over the `Anno`)                     | unaffected                               |
| evaluator + all backends                        | see the total `AppNamed`                                            | see the total `AppNamed` — **unchanged** |

The LSP row is the one that decides it, and the earlier draft missed it entirely. The precedent is
not hypothetical either: the computed-field desugar runs at that placement and is **why**
`l4 render --format text` drops a computed field from the rendered record — measured, not predicted.

**What late elaboration still buys — the whole point of R3.1, undamaged:**

|                                                                             | without elaboration                            | with late elaboration                                              |
| --------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| `supplyAppNamed` / `IncompleteAppNamed`                                     | must learn a partial mode                      | **untouched** — the two completeness regimes never share a line    |
| DMN (`Dmn/Lower.hs:1980-1984`)                                              | fails the totality guard → `verbatim`/Blocking | guard satisfied **by construction**; lowers to a full FEEL context |
| `jl4-mlir` slot layout                                                      | fed a partial field list                       | fed the complete list it already assumes                           |
| `Export/Document`, `Nlg`, `StateGraph`, `OpenFisca`, `EvaluateLazy/Machine` | each needs a partial-aware arm                 | **unchanged — the shape they see is unchanged**                    |

Of §3's 18 `AppNamed` consumers, exactly **two** get real `Update` arms: `Print.hs`, and
`TypeCheck.hs` — which by R3's own terms checks `Update` (`inferExpr`) and hosts §5.7's
`subjectOfActionExpr` arm. _(Corrected 2026-08-20: an earlier draft said "exactly one — `Print.hs`",
contradicting R3 and §5.7 a few paragraphs apart.)_ The other 16 consume the elaborated projection,
where `Update` cannot occur, so their forced `-Werror` arms are one-liners.

**And it makes Q3 disappear rather than solving it.** The alternative was a printer-side
_caramelisation_: recover `BUT WITH` by detecting, in a construction, a common base whose identity
projections `f IS b's f` can be elided. That is a real and well-precedented option —
`carameliseNode` (`Desugar.hs:152`), applied by the printer at `Print.hs:603`, already turns
`__PLUS__ 2 3` back into `2 PLUS 3`, and its own comment names the technique. But it is a **lossy
inverse** and it needs three decisions by fiat (which base wins when fields project from several, as
in ACTUS `STF_IED`; field order; a threshold), plus idempotence and the CLAUDE.md §3.2.1 evaluation
differential as a hard gate. Late elaboration needs none of that, because nothing is ever lost.

**The one case that killed caramelisation as the primary answer:** a head that is not a variable.
Obligation 1 below forces a `LET`-binding there, so `(spouseOf bob) BUT WITH age IS 31` elaborates to
a `LET`, and recovering the surface needs a fragile two-level match. Under late elaboration the
question never arises — the printer prints the `Update` it was given.

Caramelisation remains worth building **later, for a different payoff**: it would re-sugar the **40
hand-written identity-copy sites** already in the corpus (§2), so `l4 batch` on `actus.l4` would emit
`BUT WITH` for code written before the feature existed. That is decoupled from correctness, and it is
filed as such.

**The cost, stated plainly.** Three things get worse than under early elaboration:

1. **A second projection on `CheckResult`, and the discipline to use the right one.** Make that a
   type error rather than a convention — a newtype around the elaborated module, produced only by
   `elaborateUpdates`, and demanded by the evaluator and backend entry points.
2. **§5.7 re-opens.** `subjectOfActionExpr` (`TypeCheck.hs:1683`) recovers the deontic party from the
   fields written at the call site, and it runs **during** checking — before any elaboration. So it
   needs a real `Update` arm that consults the base's declaration when the party field is carried
   rather than written. Early elaboration would have dissolved this; late elaboration does not, and
   pretending otherwise is exactly the drift CLAUDE.md §1 warns about.
3. **Human-facing backends verbalize the elaboration, not the delta** _(added 2026-08-20)_. `Nlg`
   renders `AppNamed` as `<head> "where" <fields>` (`Nlg.hs:209`), so the bare-`WITH` design would
   have read "alice where age is 31". Under R3.1, `Nlg` and `Export/Document` consume the elaborated
   projection, so the same update verbalizes as "Person where name is alice's name, and age is 31,
   and email is alice's email" — the author's delta framing is lost precisely in the renderings
   meant for lawyers. **Accepted for v1.** If it grates in practice, feed those two consumers the
   unelaborated projection instead; the price is a real `Update` arm in each, and nothing else
   changes.

**Three obligations on the check and the elaboration, all easy to miss** _(rewritten 2026-08-20: an
earlier draft listed two obligations here that belonged to the superseded bare-`WITH` design — the
`viab` fork-protection example and an instruction to keep `IllegalAppNamed` on `InfVar` heads —
while the obligations this section's own cross-references point at were missing entirely. The
bare-`WITH` material now lives, reframed, in R3.2)_:

1. **Bind a non-variable head once.** The carried fields are spelled as projections of the base, so
   a head that is not a variable must be `LET`-bound before projection —
   `(spouseOf bob) BUT WITH age IS 31` elaborates to
   `LET b = spouseOf bob IN Person WITH name IS b's name, age IS 31, …` — or the head expression is
   duplicated once per carried field. This is the obligation the caramelisation paragraph above
   leans on.
2. **Re-implement the field-list checks that `supplyAppNamed` gave construction for free.**
   Construction catches a duplicate field, an unknown field name, and a supplied computed field
   because `supplyAppNamed`/`findOptionallyNamedType` consume the declaration's argument list as
   they match (`TypeCheck.hs:2976-2986`). `Update`'s own `inferExpr` case never calls that
   machinery, so it must make the same three rejections itself: `alice BUT WITH age IS 1, age IS 2`
   (duplicate), `alice BUT WITH nosuchfield IS 1` (unknown), and R4's computed-field gate.
3. **Fill the evaluator's argument-order slot.** The machine evaluates
   `AppNamed _ _ nes (Just order)` by permuting `nes` — and `AppNamed _ _ _ Nothing` is an
   `internalException RuntimeTypeError` (`EvaluateLazy/Machine.hs:856-858`, measured 2026-08-19).
   Today the checker fills the slot in `inferAppNamed`; a construction synthesized _after_ checking
   gets no such help, so `elaborateUpdates` must compute the permutation itself — trivially
   `Just [0..n-1]` if it spells fields in declaration order, but forgetting it is a crash on the
   first evaluated update, not a type error.

#### R3.2 — Head resolution: the two-bindings witness, and the `InfVar` fail-safe. Added 2026-08-20.

_(This material stood in R3.1 as "two obligations that come with the elaboration", framed for the
superseded bare-`WITH` design — where update was a new candidate inside the `WITH` overload fork
and the `viab` filter existed to protect construction. Under R2 there is no fork and construction
is untouched; what survives is a head-resolution question on the new production, so it is re-ruled
here in that frame.)_

**The witness.** L4 permits one name to be bound as **both** a record value and a named-argument
function, and it runs today:

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

Under R2 that `#EVAL` is construction syntax and never considers update — the program above is not
at risk, which is precisely R2.1's point. The live question is the head of `acme BUT WITH age IS
31`: **two `acme` bindings are in scope, and the head must resolve to the Person value, not the
Company function.** That is what R3's `TermKind`/type filter at the head is for —
`resolveTermFilteredIn`'s `viab` knob, aimed the opposite way from construction's (keep value-typed
candidates, not `Fun`-typed ones) — and R4's single-constructor gate then applies to the type it
selects. Because no existing program parses as `BUT WITH`, no tuning of this filter can regress a
program that compiles today.

**Fail safe on `InfVar`.** When the head's type is still an inference variable at the `Update`
check, reject with the new named diagnostic ("cannot update a value whose type is not yet known —
annotate the head") rather than guessing a constructor. This follows the convention already in the
file — `isPrimitiveType` has `InfVar{} -> False -- Unknown type, don't skip analysis`
(`TypeCheck.hs:2933-2936`). Update fires only on a concrete record type. _(The earlier draft said
"keep today's `IllegalAppNamed`" here — a bare-`WITH`-ism: that error's text, "you are trying to
apply … (which is not a function) to (named) arguments", is nonsense on a production that is
unambiguously an update.)_

### R4 — Partial field lists; single-constructor record types only; computed fields re-derive. Ruled 2026-08-18.

- **Partial is the point.** A non-empty subset; unwritten stored fields carry through from the base.
- **Head type must have exactly one constructor.** `constructorsInScopeFromEntityInfo`
  (`TypeCheck.hs:1828-1839`, keyed by `resultTypeHeadUnique`, already consumed by `checkConsider`)
  answers this. Reject enum values (`red WITH …`, §5.3) and multi-arm sums (`p : Payment`, §5.3) at
  check time with a named diagnostic. Measured over the 749 tracked `.l4` files:
  **640 `DECLARE … HAS` against 417 `DECLARE … IS ONE OF`** — single-constructor records are the
  _more_ common idiom, so this restriction does not gut the feature. (Method, stated because this
  census now has a history: classify each `DECLARE`'s indented block, comments stripped, as a sum
  if it contains `IS ONE OF`, else a record if it contains `HAS`. Layout puts `HAS` on the line
  _after_ `DECLARE`, so single-line greps undercount by a third — which is what produced the review
  agents' 418/375 and a 2026-08-19 check's 423/381; an earlier draft printed 641/425 without its
  method. Re-measured 2026-08-20; the ratio, the load-bearing part, holds under every count.) It is
  also **stricter than Haskell**, which permits multi-constructor update and fails at
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

### R5 — Head is a bare name **or a parenthesised expression**. Ruled 2026-08-18; rationale re-argued 2026-08-20.

**The original rationale is superseded, though the ruling stands.** As first argued, the cost of a
general head was AST-shaped: `AppNamed`'s head is a `Name` (`Syntax.hs:248`), and widening it to
`Expr` would have touched exact-printing, `prettyLayout`'s 300-file round-trip (CLAUDE.md §3.2,
**no exclusion list permitted**), the lazy machine, `Dmn/Lower` and `OpenFisca/Lower`. R3 dissolved
all of that: `Update`'s head is **already `Expr n`**, and R3.1 keeps the node out of every one of
those consumers. What actually remains is a **grammar** question — an unparenthesised general head
(`alice's spouse BUT WITH age IS 31`) needs a precedence ruling for `'s` against `BUT WITH`, and
nobody has designed or measured one. The restriction is therefore kept for v1 on grammar grounds,
not AST grounds; loosening it later is Q4.

**Accepted cost, stated plainly:** `alice's spouse BUT WITH age IS 31` — the most common Haskell
record-update idiom — cannot be written **unparenthesised**; the workaround is
`(alice's spouse) BUT WITH age IS 31`, which the revision below admits. _(Corrected 2026-08-20: an
earlier draft said "cannot be written at all … no workaround", two paragraphs above the revision
that provides one.)_ The measurements against today's grammar stand: `(alice) WITH age IS 2` is a
parse error, and building a list of variants works bracketed —
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
alice BUT WITH addr IS ((alice's addr) BUT WITH city IS "Zurich")
```

Still deferred: an unparenthesised general head (`alice's spouse BUT WITH age IS 31`). And
**chaining is not supported in v1** — write one field list; the parenthesised form covers the rest.

### R6 — Bracketing rule for a nested update in field-value position. Ruled 2026-08-18, strengthened 2026-08-19.

This answers §5.1, the sharpest technical objection. Today `Pair WITH x IS alice WITH y IS 2` binds
the inner `WITH` to `alice` and is caught **only** because the outer construction is total; under
partial update both levels become legal and the diagnostic vanishes.

**Ruled: a `BUT WITH` appearing in field-value position may not consume the enclosing comma list —
parenthesise it.** Under R2 this rule attaches to the **new** production only, so unlike the
superseded bare-`WITH` design it **cannot break an existing file at all** — the churn is structurally
zero, not measured-zero. The measurement below is retained because it is what a bare-`WITH` revival
would have to re-establish. The correct meaning is already expressible today
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

> **Superseded in part by R3.1.** Backends consume the _elaborated projection_, so **no backend sees
> an update at all**, and this whole ruling collapses to "nothing to do". What follows is the fallback if
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
  the call site, and it runs **during** checking, ahead of `elaborateUpdates`. So it needs a real
  `Update` arm that consults the **base value's** fields. This is the one consumer that late
  elaboration does _not_ spare, and the one place where "carry through silently" is not safe.

---

## 8. Kill criteria — what would make this not worth building

Stated so the spec is falsifiable. If any of these turns out to hold, R1 flips to "don't ship".

1. **The scenario argument is the load-bearing one and it is an argument, not a measurement**
   (§2.5, §4.3). It says drafters would write more counterfactuals if each cost one line instead of
   twenty. **Falsified if:** a drafter given the feature keeps writing constructor factories anyway.
   **Measurement that settles it:** take the five `PersonProfile` factories in `bna.l4`
   (`:660,687,717,746,776`; the file's other two factories build `AdoptionCase`), rewrite
   the scenario block against one canonical base, and have a knowledge engineer who did not write
   either version say which they would maintain. This is cheap and should be done **before** the
   implementation, not after.
2. ~~**If the `LocalsSpareSelectors` switch at the `AppNamed` head regresses anything.**~~
   **RETIRED 2026-08-19 by R2.** The switch was needed only to disambiguate an overloaded `WITH`;
   `BUT WITH` has no fork to disambiguate. Reinstate this criterion if the bare-`WITH` surface is
   ever revived.
3. ~~**If the `viab` pre-filter reintroduces the smucclaw#929 exponential.**~~ **RETIRED 2026-08-19
   by R2**, for the same reason. Note what this buys: the §5.6 `TYPICALLY` precedent — the reverted
   name-disambiguation heisenbug — stops being a live risk rather than a mitigated one, because
   nothing in this design touches overload resolution.
4. ~~**If the bracketing rule (R6) costs corpus churn.**~~ **RETIRED 2026-08-19 by R2**: the rule
   attaches to a new production, so no existing file can be affected. The §R6 measurement is kept as
   what a bare-`WITH` revival would have to re-establish.
5. **If a `TYPICALLY`-style heisenbug reappears.** The tell from last time: behaviour that changes
   when `trace` statements are removed. If that recurs, **stop and revert** rather than debug — the
   December 2025 attempt lost more time to debugging than the feature was worth.

## 9. Implementation order

Deliberately staged so the risky thing is provable before anything irreversible happens.

| #   | step                                                                              | why here                                                                 |
| --- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 0   | The §8.1 readability experiment on `bna.l4`                                       | cheapest possible falsification of R1; do it first                       |
| 1   | Lexer: reserve `BUT`; parser: the `BUT WITH` alternative beside `namedApp`        | R2/R3 — the discriminator, before any semantics                          |
| 2   | `Update` AST node + the 19 forced `Expr` arms; real `inferExpr` case + R4's gates | `-Werror` turns each consumer into a read; 17 of the arms are one-liners |
| 3   | `elaborateUpdates` + the newtype'd second `CheckResult` projection                | R3.1 — late, so the printer and LSP keep the written form                |
| 4   | `Update` arm in `subjectOfActionExpr` (§5.7)                                      | runs during checking, so late elaboration does not cover it              |
| 5   | R3.1's obligations 1–3: head `LET`-binding, field-list checks, order slot         | correctness, not polish — see R3.1's obligations                         |
| 6   | R6 bracketing rule; R5 parenthesised head                                         | both attach to the new production only                                   |

**No step for the evaluator, and no step for any backend.** That is R3.1's dividend: elaboration
happens before the checked module is returned, so `EvaluateLazy/Machine.hs`, `Dmn/Lower`, `jl4-mlir`,
`Export/Document`, `Nlg`, `StateGraph` and `OpenFisca` all see the total `AppNamed` they already
handle. If R3.1 is **not** adopted, add back: an evaluator partial-rebuild path, a `jl4-mlir`
expanded field set, DMN expansion-at-export, and the §5.7 deontic base-consultation.

**One step for the printer, and it is the point.** `prettyLayout` gets a real `Update` arm, so
`l4 batch` and the REPL re-emit `BUT WITH` as written; CLAUDE.md §3.2's 300-file round-trip then
holds naturally, because the printed text is the text that parsed. `ExactPrint` is generic over the
`Anno` (`ExactPrint.hs`, 42 lines, no per-constructor case), so `l4 format` needs no change at all.

**Optional, and deliberately not on this list:** the printer-side _caramelisation_ described in
R3.1. It buys nothing for correctness now that elaboration is late; its payoff is re-sugaring the 40
hand-written identity-copy sites already in the corpus. If it is ever built, CLAUDE.md §3.2.1's
evaluation differential is a **hard gate**, not a nicety — that section exists because a printer-side
rewrite once rendered two different expressions as the same string.

Per CLAUDE.md §3.2.1, run the **evaluation differential** after step 3 even though no printer delta
is expected — the property that matters is that a printed module still _means_ the same thing, and
that is exactly what a bad elaboration would break.

## 10. Prior art in-tree

- **smucclaw/l4-ide#438**, _"syntax for record updates (e.g. RecordInstance WITH)"_ — open since
  2025-05-19, labelled `enhancement, language design, ready-to-start`. **This spec is that issue.**
  Its example is `NewRecord MEANS OldRecord WITH bar IS 40` — i.e. the **bare** form. **R2 rules
  against the issue as filed**, for `NewRecord MEANS OldRecord BUT WITH bar IS 40`; when this lands,
  update the issue with §R2.1/§R2.2 rather than closing it as asked-and-delivered. `kosmikus`
  commented: _"We could make this simpler by disallowing type-changing updates."_ R4's
  single-constructor gate and R3's concrete-type requirement together implement that suggestion; a
  type-changing update is not expressible under either.
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

| #   | question                                                                                          | what would settle it                                                                                                                                                                                                                                                                        |
| --- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | Should update be allowed to _widen_ to a supertype, or strictly preserve the head's type?         | kosmikus's #438 comment says disallow type-changing; R4 follows, but no one has tested whether a widening case exists in the corpus                                                                                                                                                         |
| Q2  | Does the trace/provenance layer need an explicit node for carried-through fields?                 | `inherited-fields-have-no-trace-node` was **refuted** (derived values have no ledger entry today either), but no one has looked at what `#EVALTRACE` _prints_ for a chained update                                                                                                          |
| Q3  | Should `l4 batch`/the REPL print an update back as `BUT WITH`, or as its elaborated construction? | **RESOLVED 2026-08-19 by the re-ruled R3.1.** As `BUT WITH`: elaboration is late, so the printer is handed the `Update` the author wrote. The alternative — a printer-side caramelisation recovering the surface from a construction — is described in R3.1 and deferred as optional sugar. |
| Q4  | Should an unparenthesised projection head (`alice's spouse BUT WITH …`) be admitted later?        | Added 2026-08-20 (review). The AST already permits it — `Update`'s head is `Expr n` — so this is purely a precedence ruling for `'s` against `BUT WITH`; a designed precedence plus the §5.1 slurp analysis re-run against it would settle it. R5 holds the v1 restriction.                 |
