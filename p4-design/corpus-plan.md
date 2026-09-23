# P4 corpus authoring plan — rodents, the ASSUME widening, the Housing grounds

_Design pass for `specs/todo/BLAWX-P4-BRIEF.md`, written 2026-08-19. Read-only pass: nothing in
`jl4/`, `jl4-core/` or `etc/` was edited to produce it._

**Everything labelled MEASURED below was run through a prebuilt `l4` at the same commit as this
worktree** — `~/src/legalese/l4wt/blawx-p3/dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4`,
whose `Relational/Lower.hs`, `Blawx/Lower.hs` and `Relational/IR.hs` are byte-identical to this
tree's (`shasum` checked; both worktrees sit on `13086fa3`). No `cabal` was invoked. The builder
should still re-run every measurement after the P4b source change, because the widening moves the
middle end under all of it.

---

## 0. Five measured facts that change the brief

These are corrections, not colour. Each was produced by running `l4`, and each invalidates an
instruction in the brief or the scout report.

### 0.1 `@desc` does NOT reach `rule_text`. `@export <prose>` does.

The brief and the scout both say the citation goes in a `@desc` line above `GIVEN`. **Measured:
it is silently dropped.** `Relational/Lower.hs:464-477` reads ONE annotation — `getAnno d ^.
annDesc` — and `stripKeywords` strips a leading `export`/`default`/`nonexhaustive` token from it.
So `@export` and `@desc` are the same slot, and writing both loses one of them.

Probe (`probe3.l4`), three spellings on three decisions in one file, then `l4 blawx`:

| form                         | `rule_text` section                                                         |
| ---------------------------- | --------------------------------------------------------------------------- |
| `@export` ⏎ `@desc <prose>`  | `Definition of form one.` — **prose lost**                                  |
| `@desc <prose>` ⏎ `@export`  | `Definition of form two.` — **prose lost**                                  |
| `@export <prose>` (one line) | `FORM3 export-with-prose, punctuation: Sch 2 Ground 15 -- "ill-treatment"…` |

So: **every citation in P4a and P4c rides on the `@export` line itself.** The existing corpus
already writes it that way (`jl4/examples/openfisca/basic-income.l4:22`,
`@export Basic income payable to a person for a period`) — the blawx seeds simply have no prose
today, which is why nobody noticed.

Punctuation is safe: em dash, `"`, `'`, `:`, `;`, `,`, `.`, `(` `)`, `§` and a 250-character line
all survived verbatim into `rule_text` (MEASURED, `probe4`/`probe6`). `squash` collapses runs of
whitespace and nothing else.

**Report as a finding**: a standalone `@desc` beside an `@export` silently discards the prose. It
should either merge or diagnose. This is the same failure class as the `@export` placement note in
`benefit.l4`'s header, and belongs beside it.

### 0.2 `#ASSERT NOT …` and named scenario constants are silently dropped as queries

`lowerQuery` (`Relational/Lower.hs:2070-2130`) matches `App _ r args` only, and `queryArg` accepts
only a record literal (`AppNamed`/`App` over a `recordOf`), a list of them, or a ground literal.
Consequences, both MEASURED on `probe4.l4`:

- An `#ASSERT NOT` over a ground-13 decision applied to an inlined record literal: `callExpr` is a
  `Not`, which no branch matches, so it hits `bailIn "directive shape"` and is dropped.
- An `#ASSERT` over the same decision applied to a **named scenario constant** (the Housing corpus's
  own idiom): `queryArg` falls through to `anfTerm`, which yields goals, so it hits
  `bailIn "computed query input"` and is dropped.

`l4 blawx` **exits 0 with empty stderr** in both cases; the fidelity notes are not printed. Of
three directives, one test (`q3`) was emitted, and the test names carry the directive index, so the
survivors were numbered with gaps.

The tier-1 harness catches the _count_ mismatch (`len(oracles) != len(tests)` → "cannot pair") but
not a silent partial loss that happens to balance. **Every directive in P4c must therefore be
rewritten** into a supported shape:

- `#ASSERT NOT f x` → `#EVAL f x` with oracle `FALSE`.
- named scenario constant → the record literal inlined at the directive.

Two follow-ups worth filing (NOT in P4 scope): fold a nullary record-valued constant in `queryArg`;
and surface the `R-DIRECTIVE` advisory notes on stderr so the loss is loud.

### 0.3 Ground 8 does not compile today: `RentPeriod` vs `rent period`

MEASURED, `probe5.l4`:

```
l4 blawx: cannot compile these decisions to Blawx:
  - in `RentPeriod`: name collision (Blawx): distinct L4 definitions `rent period` and
    `RentPeriod` both mangle to the Blawx atom `rent_period` — rename one
```

The enum type and the `Ground8Claim` field collide. `l4 check` is happy; only the Blawx leg's
injectivity check (`Blawx/Lower.hs:320-327`) sees it. Renaming the **field** to
`the basis on which rent is payable` clears it and reads better in the synthesised NLG
(`has the basis on which rent is payable of`, MEASURED). See §3.3.

### 0.4 The same L4 name in two records is legal L4 and a hard Blawx error

MEASURED, `coll.l4`: two records each declaring `` `shared field` `` → `Check succeeded.`, then
`l4 blawx` errors twice with `name collision (Blawx)`. Two decisions sharing a name (overloaded on
parameter type) likewise `Check succeeded`. **Grounds 13 and 15 share two field names and one
decision name verbatim** — see the collision table in §3.2. This is the load-bearing reason the
inlined module cannot be a copy-paste.

### 0.5 The interview test queries the FIRST `@export` in the file

MEASURED: in `probe2.l4` the interview goal was `?- loss_or_damage_by_animals(X).` (first export);
moving `insurance covered` to the top of the file (`probe7.l4`) changed it to
`?- insurance_covered(X).`, with every `#EVAL` value unchanged. Forward references are fine — L4 is
order-independent at the top level (MEASURED).

**So export order is authoring, not layout.** Put the headline decision first in every seed. One
interview test is emitted per file, so a four-ground module gets one interview; the other three
grounds are driven by hand in the container (coordinator's tier-2 work).

---

## 1. P4a — `jl4/examples/blawx/rodents.l4`

### 1.1 What the source actually means (MEASURED, and it is not obvious)

`jl4/examples/ok/rodentsAndVermin.l4:17-22` is layout-grouped, and the grouping is the whole point
of the example. Two readings are available to a human eye:

- **P1** `animals AND NOT (contentsBirds OR (ensuing AND NOT exclusion))`
- **P2** `animals AND ((NOT contentsBirds) OR (ensuing AND NOT exclusion))`

They differ on exactly one region: `animals AND ensuing AND NOT exclusion`, where P1 says FALSE and
P2 says TRUE. A disambiguating scenario is therefore **rodents = TRUE, ensuing covered loss = TRUE,
everything else FALSE**.

MEASURED, by copying the untouched original into a scratch file and appending eight `#EVAL`s
(`probe.l4`; the original in `examples/ok/` was not modified):

| #   | scenario                                 | P1 predicts | P2 predicts | `l4 run`  |
| --- | ---------------------------------------- | ----------- | ----------- | --------- |
| 0   | all FALSE (the file's own `#EVAL`)       | FALSE       | FALSE       | FALSE     |
| 4   | rodents + ensuing                        | **FALSE**   | **TRUE**    | **FALSE** |
| 1   | rodents only                             | TRUE        | TRUE        | TRUE      |
| 2   | birds + contents                         | FALSE       | FALSE       | FALSE     |
| 5   | rodents + ensuing + swimming pool        | TRUE        | TRUE        | TRUE      |
| 6   | insects + contents, no birds             | TRUE        | TRUE        | TRUE      |
| 7   | no animal cause, other exclusion applies | FALSE       | FALSE       | FALSE     |
| 8   | birds + contents + ensuing               | **FALSE**   | **TRUE**    | **FALSE** |

**The parse is P1** — the `NOT` scopes over the whole indented `OR` block, which is the legally
intended reading of the policy. Good news for the demo, and the two disambiguating rows are worth
keeping in the seed precisely because they pin it.

**Polarity wart, preserved deliberately.** `insurance covered` returns TRUE when the exclusion
_bites_, i.e. when the loss is **not** covered — `not covered if` is `GIVEN x YIELD x`, so the
decision is the exclusion, not the coverage. The seed keeps the name (isomorphism with the original
is the demo) and states the polarity in its `@export` prose. A `covered` wrapper was considered and
rejected: `covered = NOT insurance covered` is an interpretive step the policy text does not take,
and inventing it in a fidelity showcase is exactly the wrong move.

### 1.2 Three deviations from the original, and why

1. **The four `WHERE` helpers are lifted to top-level decisions.** A `WHERE` helper is
   lambda-lifted to an `RAuxiliary`; lifted to the top and `@export`ed it becomes a section with its
   own citation, its own scenario-editor image, and its own tier-1 query. This is the "helpers worth
   an interview" the brief asks for, and it is what turns one section into five.
2. **`not covered if` is dropped.** It is `GIVEN x YIELD x` — a higher-order identity whose only
   role is to make the source sentence read "not covered if …". Lowered it would become an arity-2
   auxiliary with **no declaration block** (`Blawx/Lower.hs:45-48`), i.e. pure noise in the emitted
   program. Removing it is semantics-free — MEASURED, §1.3.
3. **The grouping is written with parentheses.** With `not covered if` gone the layout that produced
   the P1 grouping is gone too, so the seed states it explicitly. This is the one place where
   "isomorphic" and "unambiguous" pull apart, and the resolution is recorded in the file header with
   the measurement that justifies it.

`exclusion apply` is renamed to `an exclusion applies`. Blawx synthesises the NLG postfix from the
mangled atom, so the ungrammatical original would read "⟨object⟩ exclusion apply" in the scenario
editor. Recorded as a deviation in the header.

### 1.3 The restyle is semantics-preserving (MEASURED)

`probe2.l4` is the seed body below, run against the same eight scenarios as `probe.l4`:

```
original (probe.l4):  FALSE FALSE TRUE FALSE TRUE TRUE FALSE FALSE
seed     (probe2.l4): FALSE FALSE TRUE FALSE TRUE TRUE FALSE FALSE
```

Identical on all eight. `probe7.l4` (same content, `insurance covered` moved to the top) gives the
same eight again. **The builder should reproduce this differential before trusting any oracle
comment**: copy `examples/ok/rodentsAndVermin.l4` to `p4-design/scratch/`, append the eight `#EVAL`s,
and diff the `Result:` blocks against the seed's.

### 1.4 The seed, in full

> **SUPERSEDED 2026-08-19, in one respect: the five `@export` citations below are WRONG and were
> replaced before the seed shipped.** They label every citation `Exclusion 5(b)` — a clause number
> that appears in no source in this tree — and they quote two spans that are not policy text:
> `"nor to any ensuing covered loss"` occurs nowhere, and the proviso is glossed as loss or damage
> _to_ a household appliance / swimming pool / plumbing system when the policy's condition is
> "where an animal causes water _to escape from_" them. The real prose was in the tree all along,
> at `jl4/experiments/classic/vermin_and_rodent.l4:14`. What actually shipped is in
> `jl4/examples/blawx/rodents.l4`; the reasoning is in `seeds-as-built.md` §3.3 and
> `fix-dispositions.md` F1. Read the logic, the grouping analysis and the test population below —
> those were right and are unchanged — but do NOT copy the `@export` lines.

`jl4/examples/blawx/rodents.l4` — every `-- L4 oracle ==>` value below is MEASURED, not derived.

```l4
-- The isomorphism seed: an insurance exclusion, restyled from
-- `jl4/examples/ok/rodentsAndVermin.l4` (which is NOT modified) into the seed
-- conventions — `@export`-with-prose on every decision, the WHERE helpers
-- lifted so each carries its own policy language, and an oracle comment on
-- every directive.
--
-- THREE DEVIATIONS FROM THE ORIGINAL, all measured:
--
--   * the four WHERE helpers are lifted to top-level decisions, so each gets a
--     rule_text section, a scenario-editor image and a tier-1 query;
--   * `not covered if` (which is `GIVEN x YIELD x`, an identity whose only job
--     is to make the source sentence scan) is dropped — lowered it would be an
--     arity-2 auxiliary with no declaration block, i.e. noise;
--   * the grouping is written with parentheses rather than by layout.
--
-- The third one needs its measurement recorded, because the original's layout
-- admits two readings and they disagree:
--
--     P1  animals AND NOT (contentsBirds OR (ensuing AND NOT exclusion))
--     P2  animals AND ((NOT contentsBirds) OR (ensuing AND NOT exclusion))
--
-- They differ exactly where `animals AND ensuing AND NOT exclusion` holds. Run
-- against the untouched original, `rodents + ensuing covered loss, all else
-- FALSE` evaluates to FALSE, and `birds + contents + ensuing` likewise — so the
-- original parses as P1, which is also the reading the policy wording intends.
-- Both rows are kept below as regression pins. Every other scenario in this
-- file agrees under both readings and so proves nothing about the grouping;
-- these two are the ones that do.
--
-- POLARITY: `insurance covered` is TRUE when the exclusion BITES — when the
-- loss is NOT covered. The name is the original's and is kept for isomorphism;
-- a `covered` wrapper would be an interpretive step the policy text does not
-- take.
--
-- Each directive carries its L4-oracle value on the line after it, per
-- BLAWX-EXPORT-SPEC R11: one copy, outside the emitted artifact.

DECLARE Inputs
  HAS
    `Loss or Damage.caused by rodents` IS A BOOLEAN
    `Loss or Damage.caused by insects` IS A BOOLEAN
    `Loss or Damage.caused by vermin` IS A BOOLEAN
    `Loss or Damage.caused by birds` IS A BOOLEAN
    `Loss or Damage.to Contents` IS A BOOLEAN
    `any other exclusion applies` IS A BOOLEAN
    `a household appliance` IS A BOOLEAN
    `a swimming pool` IS A BOOLEAN
    `a plumbing, heating, or air conditioning system` IS A BOOLEAN
    `Loss or Damage.ensuing covered loss` IS A BOOLEAN

@export Exclusion 5(b): we do not cover loss or damage caused by rodents, insects, vermin or birds, unless the loss or damage is to Contents and was caused by birds, or is an ensuing covered loss and no other exclusion applies. TRUE here means the exclusion BITES — the loss is NOT covered.
GIVEN i IS AN Inputs
GIVETH A BOOLEAN
DECIDE `insurance covered` IF
         `loss or damage by animals` i
     AND NOT (       `damage to contents and caused by birds` i
                 OR (`ensuing covered loss` i AND NOT `an exclusion applies` i))

@export Exclusion 5(b), the trigger: "loss or damage caused by rodents, insects, vermin or birds".
GIVEN i IS AN Inputs
GIVETH A BOOLEAN
DECIDE `loss or damage by animals` IF
        i's `Loss or Damage.caused by rodents`
     OR i's `Loss or Damage.caused by insects`
     OR i's `Loss or Damage.caused by vermin`
     OR i's `Loss or Damage.caused by birds`

@export Exclusion 5(b), carve-out (a): "this exclusion does not apply to loss or damage to Contents caused by birds". Both limbs must hold — contents damage by anything else, or damage by birds to anything else, is still excluded.
GIVEN i IS AN Inputs
GIVETH A BOOLEAN
DECIDE `damage to contents and caused by birds` IF
        i's `Loss or Damage.to Contents`
    AND i's `Loss or Damage.caused by birds`

@export Exclusion 5(b), carve-out (b), first limb: "nor to any ensuing covered loss".
GIVEN i IS AN Inputs
GIVETH A BOOLEAN
DECIDE `ensuing covered loss` IF
    i's `Loss or Damage.ensuing covered loss`

@export Exclusion 5(b), carve-out (b), proviso: "unless any other exclusion applies" — including loss or damage to a household appliance, a swimming pool, or a plumbing, heating, or air conditioning system.
GIVEN i IS AN Inputs
GIVETH A BOOLEAN
DECIDE `an exclusion applies` IF
        i's `any other exclusion applies`
     OR i's `a household appliance`
     OR i's `a swimming pool`
     OR i's `a plumbing, heating, or air conditioning system`
```

### 1.5 The test population

Scenario constants are NOT used — §0.2 shows they are silently dropped. Every directive inlines its
record literal in the `WITH` form (self-documenting, and `queryArg`'s `AppNamed` branch handles it;
MEASURED). All ten fields must be supplied: `queryArg` does not check completeness for the `WITH`
form, and a missing field becomes a missing fact, which under R5 epistemics yields NO MODEL rather
than a silent false.

For brevity the table gives the field vector in declaration order
(rodents, insects, vermin, birds, contents, other-exclusion, appliance, pool, plumbing, ensuing).
The seed writes each one out as `Inputs WITH …`.

| directive                                      | vector          | oracle              | what it pins                                           |
| ---------------------------------------------- | --------------- | ------------------- | ------------------------------------------------------ |
| `#EVAL insurance covered`                      | `FFFF F FFFF F` | FALSE               | the original file's own `#EVAL`, carried over          |
| `#EVAL insurance covered`                      | `TFFF F FFFF F` | TRUE                | rats in the loft: the bare exclusion                   |
| `#EVAL insurance covered`                      | `FFFT T FFFF F` | FALSE               | carve-out (a): contents damage by birds                |
| `#EVAL insurance covered`                      | `FFFT F FFFF F` | TRUE                | (a) needs BOTH limbs — birds, but not to contents      |
| `#EVAL insurance covered`                      | `FTFF T FFFF F` | TRUE                | (a) needs BOTH limbs — contents, but not by birds      |
| `#EVAL insurance covered`                      | `TFFF F FFFF T` | FALSE               | **grouping pin**: carve-out (b) with no exclusion      |
| `#EVAL insurance covered`                      | `FFFT T FFFF T` | FALSE               | **grouping pin**: (a) and (b) together                 |
| `#EVAL insurance covered`                      | `TFFF F FFTF T` | TRUE                | (b)'s proviso: the swimming-pool exclusion revives it  |
| `#EVAL insurance covered`                      | `FFFF F TFFF F` | FALSE               | no animal cause: the exclusion list alone does nothing |
| `#EVAL loss or damage by animals`              | `FTFF T FFFF F` | TRUE                | helper: insects count                                  |
| `#EVAL damage to contents and caused by birds` | `FTFF T FFFF F` | FALSE               | helper: contents without birds                         |
| `#EVAL an exclusion applies`                   | `TFFF F FFTF T` | TRUE                | helper: the pool limb                                  |
| `#EVAL ensuing covered loss`                   | `TFFF F FFTF T` | TRUE                | helper: the field read                                 |
| `#ASSERT insurance covered`                    | `TFFF F FFFF F` | assertion satisfied | the `#ASSERT` path (boolean shape)                     |
| `#ASSERT an exclusion applies`                 | `FFFF F TFFF F` | assertion satisfied | a second `#ASSERT`, on a helper                        |

Rows 1–13 are MEASURED (`probe2.l4` / `probe7.l4` cover rows 1–3, 6–13 exactly; rows 4 and 5 are
derived from the same P1 formula and must be measured by the builder before the oracle comment is
written). Rows 14–15 are the `#ASSERT` shape, which `l4 run` prints as `assertion satisfied` and the
tier-1 harness maps to "a model exists" — MEASURED on `probe4.l4`.

**Do not use `#ASSERT NOT`.** It is dropped (§0.2). A FALSE expectation is an `#EVAL` with an oracle
of `FALSE`, which the harness compares against "no model".

### 1.6 Emission, registration, harnesses

1. `l4 blawx examples/blawx/rodents.l4 > examples/blawx/expected/rodents.blawx` and
   `--scasp > expected/rodents.pl`. MEASURED on the probe: exit 0, five `rule_text` sections
   carrying the prose, an `inputs` category with ten boolean attributes, five decision attributes,
   and an `interview` test abducing `inputs(X)` plus all ten fields with goal
   `?- insurance_covered(X).`
2. `jl4/tests-cli/Main.hs`: two `it` blocks at `Main.hs:2687-2693`'s pattern, after the sumlist
   pair.
3. `etc/blawx-tier1-harness.py`: add `"rodents"` to `SEEDS` (line 56). Fifteen directives → fifteen
   tests → fifteen swipl runs; the harness excludes `interview` from the pairing already.
4. `etc/blawx-fixpoint-harness.mjs` globs `expected/*.blawx` (line 380-385) and needs no edit —
   but confirm it picks the file up, since a silent non-discovery is indistinguishable from a pass.

---

## 2. P4b — the ASSUME widening and its two seeds

### 2.1 The widening is smaller than the brief thinks, and the reason is in `L4.Export`

MEASURED, three probes:

| probe      | shape                                                        | result                                                                                 |
| ---------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `alc.l4`   | `ASSUME x IS BOOLEAN`, referenced from an `@export`ed DECIDE | `l4 check` OK; `l4 blawx` → the relational refusal, `top-level ASSUME: … is ASSUMEd …` |
| `anti2.l4` | `ASSUME Person IS A TYPE` used as a `GIVEN` parameter type   | **`Check succeeded.`** — `L4.Export` accepts it                                        |
| `anti3.l4` | `ASSUME f IS A FUNCTION FROM Person TO BOOLEAN`, called      | **`l4 check` FAILS**: "Function type inputs are not supported for @export."            |

`anti3` fails whether the domain is an `ASSUME`d type or a `DECLARE`d record — the rejection is in
`L4.Export.buildExportedFunction`, which appends ASSUME-derived parameters to `exportParams` (the
mechanism `Relational/Lower.hs:564` documents) and refuses a function-typed one. **The relational
middle end never sees it.**

`jl4/examples/legal/anti-social.l4` is built entirely out of function-typed ASSUMEs. Its own
comment at `:30-33` already says it is deliberately not `@export`ed. **So the brief's claim that the
widening "unlocks `anti-social.l4`" is wrong**: unlocking it needs a change in `L4.Export`, which is
the shared surface behind jl4-service tool schemas, the DMN leg, openfisca and docassemble. That is
not a Blawx-leg change and should not ride on one.

**Recommended scope for P4b:**

- **In:** value-typed top-level `ASSUME` (`IS BOOLEAN`, `IS A NUMBER`, …) → `RInput` predicates,
  parameters from the signature, zero clauses. This is the whole of `imaginary-alcohol-act.l4`.
- **In, second sub-item:** `ASSUME T IS A TYPE` → an opaque category (an `RRecord` with no fields),
  so a `GIVEN p IS A T` parameter has a sort `blawxValueType` can name. Without it, `entType` yields
  `RSOpaque "Person"` and `Blawx/Lower.hs:594-613` refuses with "sort with no Blawx value type".
  Cheap, and it is what makes an ASSUME-only module have a _subject_ at all.
- **Out, reported:** function-typed `ASSUME`. File it against `L4.Export` with the `anti3.l4`
  transcript. Say plainly in the module haddock that the widening stops here and why.

**Reachability is the byte-stability rule.** Only ASSUMEd names reachable from an `@export` may
become `RInput` predicates. An unreferenced `ASSUME` must add nothing, or a module that merely
carries one gains a predicate and some other backend's golden moves. Existing goldens are safe today
only because every reachable ASSUME is currently a hard error — that is not a property to lean on
once the error goes away.

### 2.2 The oracle problem, and the twin that solves it

`ASSUME` is uninterpreted, so `l4 run` cannot answer for an ASSUME-side decision and the tier-1
harness would pair zero oracles against zero tests — a **vacuous green**, which is worse than a
failure because it looks like coverage.

**Chosen discipline: a sibling GIVEN-record semantic twin, with the atom names deliberately equal.**

For each ASSUME seed `X.l4` there is a twin `X-facts.l4` in the same directory:

- the twin `DECLARE`s one record whose **field names are the ASSUME'd names, character for
  character**;
- the twin's decisions carry the **same names** as the ASSUME side's;
- the twin is a first-class seed: `@export`-with-prose, `#EVAL`s, oracle comments from `l4 run`,
  its own goldens, its own tier-1 and fixpoint rows.

Because the two files are separate modules, L4 sees no duplicate names and the Blawx injectivity
check sees two separate programs — but **the mangled atoms coincide**, differing only in arity. That
is what makes the cross-check mechanical rather than hand-written:

```
alcohol-facts.blawx   q3:  alcohol_facts(a1).
                           the_person_is_a_body_corporate(a1).
                           -the_person_is_a_public_house(a1).
                           ?- the_person_must_not_sell_alcohol(a1).      oracle: TRUE

alcohol.blawx        (no tests — no evaluable directive)
harness-derived:           the_person_is_a_body_corporate.
                           -the_person_is_a_public_house.
                           ?- the_person_must_not_sell_alcohol.          SAME oracle
```

The harness rewrite is: drop the category fact, drop the single object argument from every remaining
fact and from the query, keep the `-` prefix. Ten lines of regex in
`etc/blawx-tier1-harness.py`, driven by a `TWINS = {"alcohol": "alcohol-facts"}` table. **No
expectation is authored twice** — the twin's `l4 run` value is the only expectation, used on both
sides — and the harness must print the provenance, e.g.
`blawx-tier1: PASS alcohol/twin-q3 [twin oracle alcohol-facts/q3: TRUE]`.

Why not the alternatives:

- _Same-file twin._ The two spellings would need different L4 names (a record field and a top-level
  ASSUME sharing a name is exactly the §0.4 hard collision), so the atom correspondence would have
  to be hand-maintained — the thing this design exists to avoid.
- _Hand-derived expectations._ The brief's last resort. Not needed, and it would have to be labelled
  as unanchored in the harness output forever.

**One honest limit to state in the seed header and the harness notice**: a 0-ary proposition gets
**no declaration block** in Blawx (`Blawx/Lower.hs:45-48`: relationships start at arity 3, attributes
need a record/enum-sorted parameter). So `alcohol.l4` will have rules and an `#abducible` interview
but **no scenario-editor image at all**. That is the true shape of the P1 `#abducible` earmark for a
module with no record inputs: raw s(CASP) can answer it, the Blawx UI cannot draw it. Do not paper
over it — it is the argument for the twin's record spelling, and for a future "synthesise a
singleton subject category for ASSUME-only modules" design (name it; do not build it in P4).

### 2.3 `jl4/examples/blawx/alcohol.l4` (ASSUME side) + `alcohol-facts.l4` (twin)

Adapted from `jl4/examples/legal/imaginary-alcohol-act.l4`, which is left untouched. All three
provisions carry over unchanged in logic; the only edits are `@export`-with-prose lines and the
export ordering.

Exports, in file order (first is the interview goal):

| #   | decision                                                                    | `@export` prose                                                                                                                                                                                                                                                                                      |
| --- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `the person must not sell alcohol`                                          | Imaginary Alcohol Act ss (1)–(2): a body corporate engaging in business for profit, other than a public house or a hotel, must not sell alcohol if it has an unspent conviction for fraud or for providing misleading information in relation to a licence application, or an alcohol banning order. |
| 2   | `the enforcement officer may issue a warning to the proprietor of premises` | Imaginary Alcohol Act s (3): where a price list for alcohol is displayed on premises registered as a hotel and the enforcement officer believes the list is misleading to customers, the officer may issue a warning to the proprietor.                                                              |
| 3   | `the enforcement officer may cancel the registration of the hotel`          | Imaginary Alcohol Act s (4): where a warning has been issued and the proprietor has not corrected the price list, to the officer's satisfaction, within 5 days of the warning, the officer may cancel the hotel's registration.                                                                      |

Provision (4) is the interesting one for the bridge: its `NOT ( … AND … AND … )` is a negated
conjunction over three ASSUMEd inputs, so under R5 each becomes a classical `-p` rather than `not p`
— the exact distinction `RInput` exists to record, now exercised on ASSUME-derived inputs.

The twin `alcohol-facts.l4` declares:

```l4
DECLARE AlcoholFacts HAS
    `the person is a body corporate` IS A BOOLEAN
    `the person engages in business for profit` IS A BOOLEAN
    `the person is a public house` IS A BOOLEAN
    `the person is a hotel` IS A BOOLEAN
    `the person has an unspent conviction for fraud` IS A BOOLEAN
    `the person has an unspent conviction for providing misleading information in relation to an application for a licence under an enactment` IS A BOOLEAN
    `the person has an alcohol banning order` IS A BOOLEAN
    `a price list for alcohol is displayed on the premises` IS A BOOLEAN
    `the premises are registered as a hotel` IS A BOOLEAN
    `the enforcement officer believes that the price list is misleading to customers` IS A BOOLEAN
    `the enforcement officer has issued a warning to the proprietor of premises` IS A BOOLEAN
    `the proprietor corrects the price list` IS A BOOLEAN
    `the proprietor does so to the satisfaction of the enforcement officer` IS A BOOLEAN
    `the proprietor does so within 5 days after the warning was issued` IS A BOOLEAN
```

with the same three decisions taking `f IS AN AlcoholFacts` and reading `f's <field>` where the
ASSUME side reads the bare name. Same `@export` prose, so the two `rule_text`s agree too.

Twin test population (all values derived from the boolean structure; **the builder measures each
with `l4 run` before writing the oracle comment**):

| #   | directive                          | facts                                                                    | oracle |
| --- | ---------------------------------- | ------------------------------------------------------------------------ | ------ |
| 1   | `the person must not sell alcohol` | body corporate T, for profit T, public house F, hotel F, fraud T, rest F | TRUE   |
| 2   | `the person must not sell alcohol` | as (1) but hotel T                                                       | FALSE  |
| 3   | `the person must not sell alcohol` | as (1) but fraud F, misleading-information T                             | TRUE   |
| 4   | `the person must not sell alcohol` | as (1) but fraud F, banning order T                                      | TRUE   |
| 5   | `the person must not sell alcohol` | as (1) but all three conviction/order limbs F                            | FALSE  |
| 6   | `…may issue a warning…`            | price list T, registered as hotel T, officer believes misleading T       | TRUE   |
| 7   | `…may issue a warning…`            | as (6) but registered as hotel F                                         | FALSE  |
| 8   | `…may cancel the registration…`    | warning issued T, corrects F, satisfaction F, within 5 days F            | TRUE   |
| 9   | `…may cancel the registration…`    | warning issued T, corrects T, satisfaction T, within 5 days T            | FALSE  |
| 10  | `…may cancel the registration…`    | warning issued T, corrects T, satisfaction T, within 5 days **F**        | TRUE   |
| 11  | `…may cancel the registration…`    | warning issued F, corrects F, satisfaction F, within 5 days F            | FALSE  |

Rows 9–10 are the negated-conjunction pin: a proprietor who does everything right but late is still
exposed. Row 11 pins that the warning is a precondition. Every row supplies **all fourteen fields**
(see §1.5).

### 2.4 `jl4/examples/blawx/antisocial.l4` — record-shaped, and say why

Since function-typed `ASSUME` is out (§2.1), `anti-social.l4` cannot ship as an ASSUME seed. It
still belongs in the corpus — it is one of the default-shipped `legal/` examples and it exercises a
shape none of the other seeds have: **a chain of value attributes whose values are other
categories** (`conduct : Receiver → Conduct`, `effect : Conduct → Effect`). Ship it as a
GIVEN-record seed:

```l4
DECLARE Effect HAS
    `is detrimental` IS A BOOLEAN
    `is of a persistent or continuing nature` IS A BOOLEAN
    `affects the quality of life of those in the locality` IS A BOOLEAN

DECLARE Conduct HAS
    effect IS AN Effect
    `is unreasonable` IS A BOOLEAN

DECLARE Receiver HAS
    `is an individual aged 16 or over` IS A BOOLEAN
    `is a body` IS A BOOLEAN
    conduct IS A Conduct

DECLARE Person HAS
    `is authorised` IS A BOOLEAN
```

`@export` prose for the single headline decision:

> `@export Anti-social Behaviour, Crime and Policing Act 2014 s.43: an authorised person may issue a
community protection notice to an individual aged 16 or over, or to a body, if satisfied on
reasonable grounds that (a) the conduct of the individual or body is having a detrimental effect,
of a persistent or continuing nature, on the quality of life of those in the locality, and (b) the
conduct is unreasonable.`

Two helpers are worth lifting and exporting for their own sections and interview images:
`the conduct is having a detrimental effect of a persistent or continuing nature on the quality of
life of those in the locality` (limb a) and `the recipient is a person to whom a notice may be
given` (the `individual aged 16 or over OR body` disjunction).

Header must record: the original is ASSUME-and-function-typed, `L4.Export` rejects function-typed
parameters (quote the diagnostic), the record spelling is the faithful re-spelling, and the original
file is untouched.

Test population — the shape to pin is the operator precedence in the original's body, which mixes
`AND` and `OR` across four lines with the same "read the layout" hazard as rodents. **The builder
must measure the original's grouping first** (copy to scratch, add `#EVAL`s over a record twin of
it, compare) rather than assume `authorised AND (individual OR body) AND (a) AND (b)`. Candidate
rows once the grouping is known: all-true → TRUE; not authorised → FALSE; neither individual-16+ nor
body → FALSE; each of the three limb-(a) conjuncts falsified in turn → FALSE ×3; conduct reasonable
→ FALSE; body rather than individual → TRUE.

### 2.5 Middle-end work items

1. `Relational/Lower.hs:278-279` (`ctxAssumes`) — stop being a rejection set for value-typed
   ASSUMEs; keep the rejection at `:1189-1191` for function-typed ones with a message that names
   `L4.Export` as the blocker.
2. `Relational/IR.hs:473-482` — the `RInput` haddock currently says "**In M1 this is exactly a
   stored record field**" and explains at length why a top-level `ASSUME` is _not_ one. That
   paragraph becomes false the moment the widening lands. Rewrite it to name **both** sources and to
   carry the oracle discipline (§2.2) as the answer to the objection it currently raises.
3. `Blawx/Lower.hs` — ASSUME-derived `RInput`s classify exactly as record fields do (category vs
   attribute by sort), and appear in the interview's `#abducible` list. A 0-ary one gets no
   declaration block; say so in the module haddock beside the existing arity note at `:45-48`.
4. New relational seed `jl4/examples/relational/assumed.l4` + Debug golden; new not-ok fixture for
   the function-typed case (it fails at `l4 check`, so the fixture belongs wherever a check-time
   refusal is pinned, not in `examples/relational/not-ok/` if that directory expects a lowering
   error — the builder should check which).
5. Prove byte-stability: every existing golden under `jl4/examples/relational/expected/` and the
   catala / docassemble / openfisca goldens unchanged.

---

## 3. P4c — `jl4/examples/blawx/housing-grounds.l4`

### 3.1 Where it lives, and why not `legal/`

The brief says `jl4/examples/blawx/`; the scout suggested `jl4/examples/legal/`. **Follow the
brief.** `jl4/tests/Main.hs:81` globs `ok/**` and `legal/**` only, so a file under `examples/blawx/`
carries no four-golden obligation and cannot trip `etc/check-corpus-goldens.mjs`
(CLAUDE.md §3.1). None of the four existing blawx seeds has a `tests/` directory, which is the
existing evidence for this reading. Moving the Housing corpus under CI is separately worth doing and
is explicitly out of P4 scope.

### 3.2 Collision inventory — the reason inlining is not copy-paste

`buildCtx` is module-scoped (`Relational/Lower.hs:590`), so the four grounds must be one file; and
one file means one Blawx atom namespace, where a duplicate is a **hard error** (§0.4). Full
inventory across grounds 8, 13, 15 and 17:

| #   | colliding L4 names                                                                                                                                     | kind         | verdict                                                                                                                                                            |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `RentPeriod` (enum) vs `rent period` (Ground8Claim field)                                                                                              | type × field | **MEASURED hard error.** Rename the field → `the basis on which rent is payable`                                                                                   |
| 2   | `lodger or sub-tenant removal proviso` — grounds 13 and 15                                                                                             | decision × 2 | Rename: ground 13 → `lodger or sub-tenant removal proviso (waste, neglect or default)`; ground 15 → `lodger or sub-tenant removal proviso (ill-treatment)`         |
| 3   | `the responsible actor is a person lodging with the tenant or a sub-tenant of his` — Ground13Claim & Ground15Claim                                     | field × 2    | Ground 15's → `the person ill-treating the furniture is a person lodging with the tenant or a sub-tenant of his`                                                   |
| 4   | `the tenant has not taken such steps as he ought reasonably to have taken for the removal of the lodger or sub-tenant` — Ground13Claim & Ground15Claim | field × 2    | Ground 15's → `the tenant has not taken such steps as he ought reasonably to have taken for the removal of the lodger or sub-tenant who ill-treated the furniture` |
| 5   | `claim — no deterioration` — scenario constants in 13 and 15                                                                                           | constant × 2 | Moot: scenario constants are dropped entirely (§0.2, §3.5)                                                                                                         |

Checked clean: `Ground{8,13,15,17}Claim` (camelSplit puts a break before the trailing `Claim`, so
`ground13_claim` — no digit-final wart); `Ground N made out` → `ground_n_made_out`; all four
Ground17Claim fields; all four Ground8Claim fields after fix #1; `deterioration owing to waste,
neglect or default` vs `furniture deteriorated owing to ill-treatment`. No name mangles to a
reserved atom, and none ends `_\d+` (which would gain the `x` trap suffix).

Ground 15's renames are not cosmetic tidying — they are the statute's own words. Ground 15 says "in
the case of ill-treatment by a person lodging with the tenant", ground 13 says "in the case of an
act of waste by … a person lodging with the tenant". Making the two fields distinct restores a
distinction the shared name had erased.

### 3.3 Record and predicate inventory

Four records, one enum, thirteen decisions after the deontic tails are dropped.

**`Ground8Claim`** (Part I, mandatory) — `the basis on which rent is payable IS A RentPeriod`,
`rent for one period IS A NUMBER`, `rent unpaid at the date of service of the section 8 notice IS A
NUMBER`, `rent unpaid at the date of the hearing IS A NUMBER`.
**`RentPeriod IS ONE OF`** `weekly or fortnightly`, `monthly`, `other`.

**`Ground13Claim`** — three booleans, unchanged from the experiments file.

**`Ground15Claim`** — three booleans, two of them renamed per §3.2.

**`Ground17Claim`** — four booleans, unchanged.

Decisions and their export status:

| decision                                                             | `@export`?  | arity → Blawx image                                     |
| -------------------------------------------------------------------- | ----------- | ------------------------------------------------------- |
| `Ground 8 made out`                                                  | yes (1st)   | attribute of `ground8_claim`, boolean                   |
| `required arrears for the period`                                    | yes         | attribute of `ground8_claim`, number (MEASURED)         |
| `an in-force threshold applies to this rent period`                  | yes         | attribute of `ground8_claim`, boolean (MEASURED)        |
| `per-period threshold met` (claim, arrears)                          | yes         | **arity 2 → NO declaration block** — caveat site, §3.6  |
| `threshold met for arrears` (claim, arrears)                         | no          | folded into `per-period threshold met`; see §3.6        |
| `definition — rent means rent lawfully due from the tenant`          | **no**      | inert-only; prose moves to a neighbour's `@export`      |
| `rule — universal credit housing amount not yet received is ignored` | **no**      | inert-only; prose moves to a neighbour's `@export`      |
| `Ground 13 made out`                                                 | yes         | attribute of `ground13_claim`, boolean                  |
| `deterioration owing to waste, neglect or default`                   | yes         | attribute, boolean                                      |
| `lodger or sub-tenant removal proviso (waste, neglect or default)`   | yes         | attribute, boolean                                      |
| `Ground 15 made out`                                                 | yes         | attribute of `ground15_claim`, boolean                  |
| `furniture deteriorated owing to ill-treatment`                      | yes         | attribute, boolean                                      |
| `lodger or sub-tenant removal proviso (ill-treatment)`               | yes         | attribute, boolean                                      |
| `Ground 17 made out`                                                 | yes         | attribute of `ground17_claim`, boolean                  |
| `tenant is a grantee of the tenancy`                                 | yes         | attribute, boolean                                      |
| `landlord induced by a false statement`                              | yes         | attribute, boolean                                      |
| `statement made by the tenant or at the tenant's instigation`        | yes         | attribute, boolean                                      |
| `ground {8,13,15,17} possession order`                               | **deleted** | deontic tails; the `housing-act-common` import goes too |

Imports: **none.** `prelude`, `housing-act-common` and `daydate` are all dropped. `AT LEAST`,
`TIMES`, `AND`/`OR`/`NOT` and `CONSIDER` need no import (`benefit.l4` and MEASURED `probe6.l4`
prove it), and the file must be self-contained. Dropping `daydate` also removes any chance of a
DATE-sorted field reaching `declarations` (`Blawx/Lower.hs:608` is not reachability-filtered).

Module title: a `§` heading reading _Housing Act 1988 — Schedule 2 — Grounds 8, 13, 15 and 17_. MEASURED: it
reaches `ruledoc_name`verbatim, em dashes intact, and satisfies CLEAN's uppercase-first-word rule
without`capitalizeFirst`having to rewrite it. Keep the per-ground`§§` subsections.

**Export order matters** (§0.5): `Ground 8 made out` first, so the interview asks the mandatory
ground's question. Note in the header that only one interview test is emitted per file and that the
other three grounds' interviews are driven by hand in the container.

### 3.4 The `@export` prose, lifted from the inert prose with its citation

Verbatim statutory words in `"…"`; the citation prefix is editorial. Each is one line in the file.

**Ground 8**

- `Ground 8 made out` — Sch 2 Ground 8 (Part I — the court MUST order possession): "Both at the date
  of the service of the notice under section 8 of this Act relating to the proceedings for
  possession and at the date of the hearing—" the per-period threshold must be met. When calculating
  how much rent is unpaid, an amount unpaid only because the tenant had not yet received the housing
  element of an award of universal credit under Part 1 of the Welfare Reform Act 2012 is to be
  ignored (inserted by the Renters' Rights Act 2025 (c. 26), Sch. 1 para. 24(d), in force 1.5.2026).
  _(carries the `rule — universal credit …` prose)_
- `required arrears for the period` — Sch 2 Ground 8, thresholds as amended by the Renters' Rights
  Act 2025 (c. 26), Sch. 1 para. 24 (in force 1.5.2026, S.I. 2026/421, reg. 2(b)): thirteen weeks'
  rent for a tenancy whose rent is payable weekly or fortnightly, three months' rent for one payable
  monthly.
- `an in-force threshold applies to this rent period` — Sch 2 Ground 8: the quarterly and yearly
  limbs were omitted by the Renters' Rights Act 2025, Sch. 1 para. 24(c), so no in-force threshold
  engages for rent payable on any other basis, however large the arrears.
- `per-period threshold met` — Sch 2 Ground 8 (a) and (b): "(a) if rent is payable weekly or
  fortnightly, at least thirteen weeks' rent is unpaid; (b) if rent is payable monthly, at least
  three months' rent is unpaid". For the purpose of this ground "rent" means rent lawfully due from
  the tenant. _(carries the `definition — rent means …` prose)_

**Ground 13**

- `Ground 13 made out` — Sch 2 Ground 13 (Part II — the court MAY order possession) is made out when
  the deterioration limb and the lodger-or-sub-tenant removal proviso are both satisfied. For the
  purposes of this ground "common parts" means any part of a building comprising the dwelling-house
  and any other premises which the tenant is entitled under the terms of the tenancy to use in
  common with the occupiers of other dwelling-houses in which the landlord has an estate or interest.
- `deterioration owing to waste, neglect or default` — Sch 2 Ground 13: "The condition of the
  dwelling-house or any of the common parts has deteriorated owing to acts of waste by, or the
  neglect or default of, the tenant or any other person residing in the dwelling-house".
- `lodger or sub-tenant removal proviso (waste, neglect or default)` — Sch 2 Ground 13, proviso:
  "and, in the case of an act of waste by, or the neglect or default of, a person lodging with the
  tenant or a sub-tenant of his, the tenant has not taken such steps as he ought reasonably to have
  taken for the removal of the lodger or sub-tenant". Read as an implication, so it is vacuously
  satisfied where the responsible person is not a lodger or sub-tenant.

**Ground 15**

- `Ground 15 made out` — Sch 2 Ground 15 (Part II — the court MAY order possession) is made out when
  the furniture-deterioration limb and the removal proviso are both satisfied. "In the opinion of
  the court" qualifies the standard of proof on the deterioration finding; it is not an independent
  condition.
- `furniture deteriorated owing to ill-treatment` — Sch 2 Ground 15: "The condition of any furniture
  provided for use under the tenancy has, in the opinion of the court, deteriorated owing to
  ill-treatment by the tenant or any other person residing in the dwelling-house".
- `lodger or sub-tenant removal proviso (ill-treatment)` — Sch 2 Ground 15, proviso: "and, in the
  case of ill-treatment by a person lodging with the tenant or by a sub-tenant of his, the tenant
  has not taken such steps as he ought reasonably to have taken for the removal of the lodger or
  sub-tenant". Read as an implication, vacuously satisfied where the person ill-treating the
  furniture is not a lodger or sub-tenant.

**Ground 17**

- `Ground 17 made out` — Sch 2 Ground 17 (Part II — the court MAY order possession; inserted by the
  Housing Act 1996 (c. 52), s. 102, in force 28.2.1997, S.I. 1997/225, art. 2) is made out when the
  tenant is a grantee, the landlord was induced by a false statement made knowingly or recklessly,
  and that statement was made by the tenant or at the tenant's instigation.
- `tenant is a grantee of the tenancy` — Sch 2 Ground 17: "The tenant is the person, or one of the
  persons, to whom the tenancy was granted".
- `landlord induced by a false statement` — Sch 2 Ground 17: "and the landlord was induced to grant
  the tenancy by a false statement made knowingly or recklessly".
- `statement made by the tenant or at the tenant's instigation` — Sch 2 Ground 17, limbs (a) and
  (b): the false statement was made "by— (a) the tenant, or (b) a person acting at the tenant's
  instigation."

The inert-prose bodies (`"…" ... claim's field`) stay in the decisions exactly as written. They are
erased by `Relational/Lower.hs:789-792` and reach nothing, but they are what makes the L4 source
readable as law, and the `@export` line is where the same words survive into the artifact.

### 3.5 Which `#ASSERT`s carry over, and the new `#EVAL`s

**None of the existing directives survives as written**: all thirty-odd use a named scenario
constant, and roughly half are `#ASSERT NOT`. Both are dropped (§0.2). Every one is rewritten as an
`#EVAL` over an inlined record literal, with the scenario's descriptive name moved to a `--` comment
above it and an oracle comment below.

Ground 13 (`D` deterioration, `L` responsible actor is a lodger/sub-tenant, `N` tenant has NOT taken
removal steps; `proviso = (NOT L) OR N`, `made out = D AND proviso`):

| scenario (comment)                          | D   | L   | N   | `deterioration` | `proviso` | `made out` |
| ------------------------------------------- | --- | --- | --- | --------------- | --------- | ---------- |
| tenant's own neglect                        | T   | F   | F   | TRUE            | TRUE      | TRUE       |
| lodger, not removed                         | T   | T   | T   | TRUE            | TRUE      | TRUE       |
| lodger, but removed                         | T   | T   | F   | TRUE            | FALSE     | FALSE      |
| no deterioration                            | F   | F   | F   | FALSE           | TRUE      | FALSE      |
| **new:** no deterioration, lodger unremoved | F   | T   | T   | FALSE           | TRUE      | FALSE      |

The new row pins that the proviso alone carries nothing — it is a filter on the deterioration limb,
not an independent ground.

Ground 15 has the identical shape over its own three (renamed) fields; the same five rows, same
values.

Ground 17 (`G` grantee, `I` induced, `Ma` made by tenant, `Mb` at instigation;
`maker = Ma OR Mb`, `made out = G AND I AND maker`):

| scenario                             | G   | I   | Ma  | Mb  | `grantee` | `induced` | `maker` | `made out` |
| ------------------------------------ | --- | --- | --- | --- | --------- | --------- | ------- | ---------- |
| statement by the tenant (limb a)     | T   | T   | T   | F   | TRUE      | TRUE      | TRUE    | TRUE       |
| at the tenant's instigation (limb b) | T   | T   | F   | T   | TRUE      | TRUE      | TRUE    | TRUE       |
| not a grantee                        | F   | T   | T   | F   | FALSE     | TRUE      | TRUE    | FALSE      |
| no inducement                        | T   | F   | T   | F   | TRUE      | FALSE     | TRUE    | FALSE      |
| unconnected third party              | T   | T   | F   | F   | TRUE      | TRUE      | FALSE   | FALSE      |
| **new:** both (a) and (b)            | T   | T   | T   | T   | TRUE      | TRUE      | TRUE    | TRUE       |

The new row pins the inclusive `OR` — a statement made by the tenant _and_ one made at his
instigation does not double-count or cancel.

Ground 8 — MEASURED end to end on `probe6.l4` (the inlined shape with the §3.2 rename), values
straight from `l4 run`:

| scenario                               | basis   | period rent | at service | at hearing | directive                         | oracle |
| -------------------------------------- | ------- | ----------- | ---------- | ---------- | --------------------------------- | ------ |
| weekly, exactly 13 weeks at both dates | weekly  | 100         | 1300       | 1400       | `per-period threshold met … 1300` | TRUE   |
| weekly, exactly 13 weeks at both dates | weekly  | 100         | 1300       | 1400       | `Ground 8 made out`               | TRUE   |
| weekly, short at the hearing           | weekly  | 100         | 1300       | 1200       | `Ground 8 made out`               | FALSE  |
| monthly, three months                  | monthly | 800         | 2400       | 3200       | `required arrears for the period` | 2400   |
| a period with no in-force threshold    | other   | 5000        | 100000     | 100000     | `Ground 8 made out`               | FALSE  |

Plus, carried from the experiments file and to be measured the same way: monthly all-met → TRUE;
monthly short at service (1600 / 2400) → FALSE; and `an in-force threshold applies to this rent
period` on `other` → FALSE.

**New interview-shaped boundary rows** (the brief asks for the 13-week boundary from both sides).
Required arrears weekly = 13 × 100 = 1300, and `AT LEAST` is `≥`:

| basis  | period rent | at service | at hearing | directive                         | derivation             | oracle |
| ------ | ----------- | ---------- | ---------- | --------------------------------- | ---------------------- | ------ |
| weekly | 100         | 1300       | 1300       | `Ground 8 made out`               | 1300 ≥ 1300 both dates | TRUE   |
| weekly | 100         | 1299       | 1400       | `Ground 8 made out`               | 1299 < 1300 at service | FALSE  |
| weekly | 100         | 1299       | 1400       | `per-period threshold met … 1299` | one pound short        | FALSE  |
| weekly | 100         | 1300       | 1400       | `required arrears for the period` | 13 × 100               | 1300   |

### 3.6 Ground 8's arity-2 caveat sites — named, with the evidence

The two computed predicates the scout flagged are `threshold met for arrears` and `per-period
threshold met`, both `(Ground8Claim, NUMBER) → BOOLEAN`. Total arity 2 with the boolean output
dropped, and the second parameter is not record- or enum-sorted, so neither is attribute-shaped and
neither reaches arity 3 — **no declaration block** (`Blawx/Lower.hs:45-48`).

MEASURED on `probe6.l4`, where `threshold met for arrears` was folded into `per-period threshold met`
to leave exactly one such site:

- `blawx_attribute(…)` is emitted for `required_arrears_for_the_period`,
  `an_in_force_threshold_applies_to_this_rent_period` and `ground_8_made_out`, and for the four
  stored fields — **but not for `per_period_threshold_met`**, as predicted.
- Its rules DO emit, and the `q1` test carries a query block. That block is where the gap shows:

  ```xml
  <block type="attribute_selector" attributename="per_period_threshold_met"
         attributetype="number" attributeorder="ov">
    <field name="infix">per_period_threshold_met</field>
  ```

  It is imaged as a **value attribute of `ground8_claim` whose value is a number**, when it is
  really a boolean relation on (claim, arrears); and its `infix` is the raw mangled atom rather than
  a prettified phrase, because there is no `blawx_attribute_nlg` fact to draw one from.

That undeclared `attributename` is the concrete fixpoint hazard: on re-save the editor has no
declaration to resolve the mutation against. **Measure it before deciding**: emit the golden, run
`etc/blawx-fixpoint-harness.mjs` on it, and read the result.

- If the row round-trips, keep the shape. It is the brief's "confirm, report, don't suppress", and
  the wart is now evidenced rather than asserted.
- If it gaps, the fallback is to keep `per-period threshold met` unexported as the verbatim (a)/(b)
  carrier and add two arity-1 wrappers, `threshold met at the date of service` and `threshold met at
the date of the hearing`, as the exported decisions. Semantically identical, entirely arity-1, and
  every predicate regains a declaration block and a scenario-editor image. Record which branch was
  taken and the measurement that chose it.

Either way, report the mis-imaging (number-typed value attribute, raw-atom infix) as a P3 follow-up
with the XML above as the witness.

### 3.7 Emission, registration, harnesses

Same four steps as §1.6, with `"housing-grounds"` added to `SEEDS`. Expect roughly 25 tests, i.e. 25
swipl invocations — the tier-1 harness runs one `swipl` per query by design (the R7 finding), so
budget the wall-clock. Read the interview test before committing: with four records in one module it
abduces every category and every field, which is correct but noisy, and it is worth knowing whether
it terminates in reasonable time under abduction.

---

## 4. The `rpDesc <|> rpRef` one-liner

`Blawx/Lower.hs:219` becomes `bsText = squash (fromMaybe (stubSection p) (p.rpDesc <|> p.rpRef))`.

Regression case, MEASURED as currently failing: `probe4.l4`'s second decision carries
`@ref https://www.legislation.gov.uk/ukpga/1988/50/schedule/2` and a bare `@export`, and its
`rule_text` section came out as the stub `Definition of lodger or sub-tenant removal proviso.` With
the change it should carry the URL.

Where to put the case: a decision in `jl4/examples/blawx/mortality.l4` would perturb the smallest
golden, so prefer a new small fixture or an added decision in `rodents.l4` that carries `@ref` and
no prose — and say in the header that it is there to pin the fallback, not because the corpus wants
a bare `@ref`.

Note while doing it that `@ref` reaching `rpRef` was **not** independently confirmed in this pass —
only that the current output is the stub. Confirm `rpRef` is populated (`Relational/Lower.hs:1649`,
`Debug.hs:278`) before concluding the one-liner is sufficient.

---

## 5. Order of work, and what each rung ships alone

1. **P4a rodents** — no source change at all. Ships a five-section showcase with real policy
   language in `rule_text` and fifteen measured oracles. Do this first and completely; it also
   proves the `@export`-with-prose finding in the corpus rather than in a probe.
2. **P4c housing-grounds** — no source change either, once §3.2's renames and §3.5's directive
   rewrite are done. It is independent of P4b and, per §0.1–0.4, is entirely an authoring job. If
   P4b runs long, P4c still ships.
3. **P4b widening** — the only rung that touches the shared middle end, and the only one that can
   destabilise another backend. Doing it last means a failure there costs no shipped value.

The `rpDesc <|> rpRef` one-liner rides with whichever rung is in flight when it is convenient; it is
independent of all three.

---

## 6. Probes kept

All under
`/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/4638d7ee-14b9-4ef5-8061-36a8c1ced864/scratchpad/p4c/`
— outside the worktree, so nothing here is at risk of being committed:

| file                                        | what it measured                                                              |
| ------------------------------------------- | ----------------------------------------------------------------------------- |
| `probe.l4`                                  | the original rodents grouping, eight scenarios → the P1 reading               |
| `probe2.l4`                                 | the restyled seed, same eight → identical, plus four helper probes            |
| `probe3.l4`                                 | `@desc`/`@export` annotation forms → only `@export <prose>` reaches rule_text |
| `probe4.l4`                                 | `#ASSERT NOT` and named-constant directives → both silently dropped; `@ref`   |
| `probe5.l4`                                 | ground 8 as written → `RentPeriod` / `rent period` hard collision             |
| `probe6.l4`                                 | ground 8 after the rename → clean, five tests, arity-2 image inspected        |
| `probe7.l4`                                 | export ordering → the interview goal follows the first `@export`              |
| `alc.l4`, `anti.l4`, `anti2.l4`, `anti3.l4` | where each ASSUME shape is refused, and by which pass                         |
| `coll.l4`, `coll2.l4`, `c3.l4`              | duplicate field/decision names; the `§` title path                            |
