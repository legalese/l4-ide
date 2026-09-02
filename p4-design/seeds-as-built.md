# P4a / P4b seeds — as built

_Written by the implementing agent on 2026-08-19, against the tree as it stands. Everything marked
MEASURED was produced by running the `l4` built in this worktree at this commit; nothing here is
carried over from `corpus-plan.md` or `widening-plan.md` without being re-run. Where those documents
and the tree disagree, this file records the tree._

Scope: `jl4/examples/blawx/rodents.l4` (P4a) and `antisocial{,-twin}.l4` + `alcohol{,-twin}.l4` +
`not-ok/zero-arity.l4` (P4b), their goldens, their `tests-cli` registration, and the tier-1
harness's twin discipline. P4c (the Housing grounds module) is NOT in this batch.

---

## 1. What shipped

| file                                      | shape                | directives              | goldens             |
| ----------------------------------------- | -------------------- | ----------------------- | ------------------- |
| `jl4/examples/blawx/rodents.l4`           | `GIVEN` record       | 13 `#EVAL`, 2 `#ASSERT` | `.blawx` + `.pl`    |
| `jl4/examples/blawx/antisocial.l4`        | top-level `ASSUME`   | none (by design)        | `.blawx` + `.pl`    |
| `jl4/examples/blawx/antisocial-twin.l4`   | `GIVEN` record       | 16 `#EVAL`, 1 `#ASSERT` | `.blawx` + `.pl`    |
| `jl4/examples/blawx/alcohol.l4`           | top-level `ASSUME`   | none (by design)        | `.blawx` + `.pl`    |
| `jl4/examples/blawx/alcohol-twin.l4`      | `GIVEN` record       | 16 `#EVAL`, 2 `#ASSERT` | `.blawx` + `.pl`    |
| `jl4/examples/blawx/not-ok/zero-arity.l4` | subjectless `ASSUME` | —                       | none (`expectFail`) |

Originals left untouched, as the brief requires: `jl4/examples/ok/rodentsAndVermin.l4`,
`jl4/examples/legal/anti-social.l4`, `jl4/examples/legal/imaginary-alcohol-act.l4`.

Runs, **as measured when this batch landed** — i.e. before P4c (`housing-grounds.l4`) and before the
review fixes recorded in `fix-dispositions.md`. They are kept as the record of that batch and are
NOT the current tree's numbers; for those see `housing-grounds-as-built.md` §1 and
`fix-dispositions.md` §"final run".

- `cabal build all --enable-tests` clean under `-Werror`.
- `l4-cli-test` **278 examples, 0 failures** (was 264; +14).
- `jl4-test` **2585 / 0**, `jl4-core-test` **301 / 0** — unchanged, so nothing the seeds touch moved
  an existing golden.
- `etc/check-corpus-goldens.mjs`: 355 corpus files, all four goldens present.
- `etc/blawx-tier1-harness.py` over the FULL population: **101 / 101 passed** (16 pre-existing + 15
  rodents + 17 antisocial-replay + 17 antisocial-twin + 18 alcohol-replay + 18 alcohol-twin).
  CORRECTED on review: 35 of those 101 rows are twin replays of a program byte-identical to the
  twin's own, so the DISTINCT population was 66, not 101. The harness now prints the split itself
  (`etc/blawx-tier1-harness.py`, summary line) precisely so that number cannot be over-quoted
  again.
- `etc/blawx-fixpoint-harness.mjs`: **116 rows checked, 0 failed, 0 empty-skipped** (up from 35).
  Per file: benefit 7, mortality 5, scores 12, sumlist 11, rodents 22, antisocial 7,
  antisocial-twin 24, alcohol 5, alcohol-twin 23.

---

## 2. The P4b oracle discipline, and why it came out stronger than planned

The brief's problem: `ASSUME` is uninterpreted, so `l4 run` cannot answer for an ASSUME-shaped
module; and `lowerQuery` builds a test scenario only out of a record-literal query argument, so an
`#EVAL` in such a module lowers to a query with **no facts at all**. An ASSUME seed therefore has
zero evaluable directives, its `.blawx` carries only the `interview` test, and the tier-1 harness's
`len(oracles) != len(tests)` guard passes at `0 == 0` — **a vacuous green**, which is worse than a
failure because it reads as coverage.

**Chosen discipline: a sibling record-spelled semantic twin, with the names deliberately equal.**
For each ASSUME seed `X.l4` there is `X-twin.l4` whose records are named exactly as `X.l4`'s
`ASSUME`d TYPEs and whose fields are named exactly as its `ASSUME`s — character for character, in
the same order. The twin's `#EVAL`s DO run under `l4 run`, and `etc/blawx-tier1-harness.py` uses the
twin's measured value as the **single** expectation for both programs: the twin is exercised
normally, then the twin's fact rows are replayed against the ASSUME seed's own workspaces.

`widening-plan.md` §7 hoped the two `.pl` streams might be comparable "modulo a declared atom-
renaming table", with byte identity as the best case it could not promise. **MEASURED: byte
identity holds, on both pairs, on the first try.**

```
$ diff <(tail -n +2 expected/antisocial.pl) <(tail -n +2 expected/antisocial-twin.pl) && echo same
same
$ diff <(tail -n +2 expected/alcohol.pl)    <(tail -n +2 expected/alcohol-twin.pl)    && echo same
same
```

Only line 1 differs — the generator's provenance comment, which names the source file. So "one
logic, two spellings" is a measurement, not a claim, and the fallback ladder in `widening-plan.md`
§7 (compare rule stacks only / compare modulo renaming / hand-derive) was **not descended at all**.
Hand-derived expectations do not appear anywhere in this batch.

Why it worked: a boolean record field reaches this leg as `RProj` + `RUnify TRUE` and is collapsed
by the boolean-projection peephole to the same signed unary goal an `ASSUME`d input gives; a value
field and an `ASSUME`d accessor both give the same binary goal; `attributeBlock` is shared between
the field path and the classifier path; and `Blawx/Emit.hs` reads no provenance, so the differing
source ranges never reach the text.

That identity is now **asserted in two places**, because it is load-bearing rather than decorative:

- `jl4/tests-cli/Main.hs` — `twinsAgree`, run on both pairs. A field renamed "for readability" in a
  twin fails here, loudly, instead of quietly degrading the tier-1 run into a comparison of two
  unrelated programs.
- `etc/blawx-tier1-harness.py` — `twin_preflight`, re-measured on every run and **printed**.
  CORRECTED on review (`fix-dispositions.md` F5/F7): a divergence used to be a printed note that the
  run continued past, on the reading that the replay was then "a weaker cross-check". It is not — a
  divergence in a predicate only the FALSE rows touch would leave every one of them finding no model
  and passing having executed nothing. A divergence is now **fatal**, and the preflight compares the
  `.blawx` workspace encodings as well as the `.pl`, because the workspaces are what the replay
  loads. With identity holding, the replay is a **re-execution**, not a second independent check, and
  the summary line now says so and counts it separately.

Two more guards went in beside them, both aimed at the vacuity the discipline exists to prevent:

- an ASSUME seed that grows a directive of its own is a **failure**, not a merge of two sources;
- any seed whose golden yields no executable test at all is a **failure** ("a vacuous pass, refusing
  to count it"), which would previously have been an unremarkable `0 == 0`.

---

## 3. P4a — `rodents.l4`

### 3.1 The grouping, measured against the untouched original

`ok/rodentsAndVermin.l4` is layout-grouped and admits two readings:

```
P1  animals AND NOT (contentsBirds OR (ensuing AND NOT exclusion))
P2  animals AND ((NOT contentsBirds) OR (ensuing AND NOT exclusion))
```

They differ exactly where `animals AND ensuing AND NOT exclusion` holds. MEASURED by copying the
original into `p4-design/scratch/probe-orig.l4` (the original itself was not modified) and appending
nine `#EVAL`s:

| scenario                                 | P1        | P2       | `l4 run`  |
| ---------------------------------------- | --------- | -------- | --------- |
| all FALSE                                | FALSE     | FALSE    | FALSE     |
| rodents only                             | TRUE      | TRUE     | TRUE      |
| birds + contents                         | FALSE     | FALSE    | FALSE     |
| birds, not to contents                   | TRUE      | TRUE     | TRUE      |
| insects + contents, no birds             | TRUE      | TRUE     | TRUE      |
| **rodents + ensuing**                    | **FALSE** | **TRUE** | **FALSE** |
| rodents + ensuing + swimming pool        | TRUE      | TRUE     | TRUE      |
| no animal cause, other exclusion applies | FALSE     | FALSE    | FALSE     |
| **birds + contents + ensuing**           | **FALSE** | **TRUE** | **FALSE** |

**The parse is P1**, which is also the reading the policy wording intends. The seed writes it with
parentheses and keeps both discriminating rows as marked grouping pins; the emitted rule stack is
the P1 DNF split, two clauses:

```
animals ∧ ¬contentsBirds ∧ ¬ensuing
animals ∧ ¬contentsBirds ∧  exclusion
```

The seed reproduces the original on all nine shared scenarios.

### 3.2 Deviations from the original, and why

1. **The four `WHERE` helpers are lifted to top-level `@export`ed decisions.** One section becomes
   five: each gets its own `rule_text` citation, its own scenario-editor image, and its own tier-1
   query.
2. **`not covered if` is dropped.** It is `GIVEN x YIELD x`; lowered it would be an arity-2
   auxiliary with no declaration block (see §5.3), i.e. noise in the ontology. Semantics-free —
   proved by the nine-scenario differential above.
3. **The grouping is parenthesised** rather than laid out, since the layout that produced it went
   with `not covered if`.
4. **`exclusion apply` → `an exclusion applies`.** Blawx synthesises a boolean attribute's NLG
   postfix from the mangled atom, so the original would read "⟨object⟩ exclusion apply" in the
   scenario editor.
5. **A `§` title is added.** The original has none, so `ruledoc_name` came out as `Rodents` — the
   filename. It reaches the top of the Blawx document and the first line of `rule_text`, so the seed
   names the instrument: _Home insurance policy — the rodents, insects, vermin and birds exclusion_.
   MEASURED: it reaches `ruledoc_name` verbatim, em dash intact. (CORRECTED on review: this title
   read _… — Exclusion 5(b): …_ until 2026-08-19. No source in this tree carries a clause number
   for this policy, so the number was invented; it is gone from the title and from all five
   citations. Downstream, `doc_part_name` in the emitted XML went from `HE 1` to `H 1`, since it is
   abbreviated from the title's capitals.)
6. **Polarity kept.** `insurance covered` is TRUE when the exclusion BITES. The name is the
   original's and the `@export` prose says so; a `covered = NOT insurance covered` wrapper is an
   interpretive step the policy text does not take, and inventing one in a fidelity showcase is
   exactly the wrong move.

### 3.3 Which prose became which citation

**REWRITTEN 2026-08-19 on review.** The first version of this section, and the five `@export` lines
it described, were wrong in a way worth recording rather than quietly fixing: they authored a clause
number (`Exclusion 5(b)`) that appears in **no** source in this tree, and they put quotation marks
around paraphrases. Two of those paraphrases said something the policy does not — `"nor to any
ensuing covered loss"` is not a string that occurs anywhere, and the proviso was glossed as
"loss or damage **to** a household appliance, a swimming pool, or a plumbing, heating, or air
conditioning system" when the policy's condition is "where an animal causes water **to escape
from**" those items. Those are different conditions, and `rule_text` is the only NL channel a Blawx
reader sees.

The prose was there to be lifted. `ok/rodentsAndVermin.l4` (the logic source) has none, but the
tree's other copy of the same rule — `jl4/experiments/classic/vermin_and_rodent.l4:14` — carries it
in full over the identical `Inputs` record:

> We do not cover any loss or damage caused by rodents, insects, vermin, or birds. However, this
> exclusion does not apply to: (a) loss or damage to your contents caused by birds; or (b) ensuing
> covered loss unless any other exclusion applies or where an animal causes water to escape from a
> household appliance, swimming pool or plumbing, heating or air conditioning system.

Five `@export` lines now split that sentence at its own clause boundaries. Everything inside `"…"`
is a **contiguous substring** of the quotation above — machine-checked, not eyeballed; everything
outside the quotes is the seed's own gloss and reads as one.

| decision                                 | quoted span (contiguous substring of the policy)                                                                                                                         |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `insurance covered`                      | the whole sentence, verbatim, + the polarity warning as gloss                                                                                                            |
| `loss or damage by animals`              | "We do not cover any loss or damage caused by rodents, insects, vermin, or birds."                                                                                       |
| `damage to contents and caused by birds` | "this exclusion does not apply to: (a) loss or damage to your contents caused by birds" + the both-limbs note as gloss                                                   |
| `ensuing covered loss`                   | "(b) ensuing covered loss"                                                                                                                                               |
| `an exclusion applies`                   | "unless any other exclusion applies or where an animal causes water to escape from a household appliance, swimming pool or plumbing, heating or air conditioning system" |

All five reach `rule_text` intact (quotes, parentheses and the em dash in the title survive).
Note what the last row settles about the encoding: the three appliance/pool/plumbing inputs are
_escape-of-water_ conditions, and the L4 `OR` in `an exclusion applies` is the policy's own
"unless … or where …". The logic was always right; only the citation was wrong.

---

## 4. P4b — the two ASSUME seeds

### 4.1 `antisocial.l4`

The showcase: **a module with no `DECLARE` at all**. Five `ASSUME`d TYPEs, nine `ASSUME`d
predicates, five exported decisions, and an `interview` test with twelve `#abducible` lines and the
goal `?- may_issue_a_community_protection_notice(X,Y).` That interview is the discharge of P1's
deferred earmark ("interview tests for modules with no record inputs"), now in the corpus rather
than only in `BlawxAssumeSpec`.

Three deviations from `legal/anti-social.l4`, all forced and all documented in the file header:

1. **Spelling.** The original writes every input as
   `ASSUME `is authorised` IS A FUNCTION FROM Person TO BOOLEAN`. `L4.Export.validateExportInputs`
   makes it a **type error** for an `@export`ed decision to reference a function-typed `ASSUME`, and
   lowering is export-rooted, so that spelling never reaches the middle end. The seed uses
   `GIVEN p IS A Person` + `ASSUME `is authorised` p IS A BOOLEAN`, whose declared type is `BOOLEAN`.
   The original's own comment (`:30-33`) records the same wall from the other side.
2. **Two TYPE renames**, forced by a hard Blawx error — see §5.1. `Conduct` → `Behaviour`,
   `Effect` → `Consequence`. The **accessors keep the Act's words** (`conduct`, `effect`), because
   that is where they read as the statute and because a value attribute's synthesised NLG is
   "has ⟨name⟩ of".
3. **Limb (a) is factored through the effect** rather than written inline three times — see §5.4.
   This is the one place the encoding differs in meaning from a naive transcription, and it differs
   in the direction of the statute.

`EffectTarget` is carried over **unreferenced on purpose**: it is the corpus witness for the
reachability gate. MEASURED: `effect_target` appears nowhere in either golden, and `tests-cli`
asserts its absence.

The grouping of the original's four-level AND/OR body was measured the same way rodents' was, on a
record twin carrying the original's exact AND/OR columns (`p4-design/scratch/anti-probe-eval.l4`,
eleven scenarios). It is

```
authorised AND (individual-16-or-over OR body) AND (detrimental AND persistent AND affects-quality) AND unreasonable
```

The two discriminating rows — "not authorised but a body, everything else true" and "authorised
individual with none of the conduct limbs" — both evaluate FALSE, ruling out every reading that lets
the `OR` escape its conjunct. They survive as q10 and q11 in the twin.

**`rule_text` fallback witnesses.** The corpus previously exercised only the stub arm. This file
carries both new arms, adjacent in the ordering so a reordering cannot swap them silently:

- **arm A** — `may issue a community protection notice` has `@export <prose>` AND `@ref <url>`;
  section 1 shows the prose.
- **arm B** — `the conduct is unreasonable` has a bare `@export` and only `@ref`; section 5 shows
  the citation, not `Definition of the conduct is unreasonable.`

Both are asserted structurally in `tests-cli` as well as pinned in the golden.

### 4.2 `alcohol.l4`

`widening-plan.md` §0.2 ruled this file out as a seed, on the ground that its nullary decisions would
gap in `EmitXml` and blank the row. That reasoning was right about the ontology and wrong about the
conclusion: the Blawx leg now **refuses** a subjectless input by name rather than blanking it, and
the Act itself names its subjects in every sentence. So the seed gives the Act the two subjects its
prose already has — the PERSON of provisions (1)–(2) and the PREMISES of (3) and (4) — and every
`ASSUME` becomes a one-place predicate of one of them. Nothing else changed; all three provisions
carry over with their logic untouched.

The nullary spelling is preserved as `not-ok/zero-arity.l4`, with the measured diagnostic, so the
refusal is pinned rather than merely described. MEASURED on the untouched original with only an
`@export` added:

```
in `the person is a body corporate`: input predicate with no category subject (Blawx):
… is an input of total arity 0, which Blawx has no declaration block for. At total
arity 2 or below an input must be ATTRIBUTE-shaped — exactly one parameter,
category-sorted (an ASSUMEd TYPE, a record or an enum), plus at most a result —
because a fact is stated in Blawx by hanging an attribute off its subject.
Relationship blocks, whose arguments need not be categories, start at total arity 3
```

REWORDED on review (`fix-dispositions.md` F2/F6). The message quoted here until 2026-08-19 said
"… whose first parameter is not a category … an ASSUME must take the thing it is about … as its
first parameter", which is not the rule `classifyPred` implements: the refused band is total arity
≤ 2 that is not attribute-shaped, so an arity-2 input **with** a category first parameter is refused
too (`not-ok/arity-two.l4`), and an arity-3 input with **no** category anywhere is accepted.

**Provision (4) is the seed's point.** Its `NOT ( … AND … AND … )` over three `ASSUME`d inputs is
where R5's epistemics show: De Morgan gives three clauses, each carrying a **classical** `-p` rather
than `not p`, so a proprietor about whom nothing has been said yields NO MODEL — loudly — instead of
silently counting as one who failed to correct the list. MEASURED and asserted in `tests-cli`:

```prolog
according_to(sec_3_section,…may_cancel…,Pr) :- premises(Pr),
the_enforcement_officer_has_issued_a_warning_to_the_proprietor_of_premises(Pr),
-the_proprietor_corrects_the_price_list(Pr).
```

The twin's q14 (corrected, to the officer's satisfaction, but LATE → TRUE) and q15 (corrected in
time but not to satisfaction → TRUE) are the negated-conjunction pins; q16 (no warning → FALSE) pins
the precondition.

---

## 5. Findings — measured on this tree, for the coordinator

### 5.1 An `ASSUME`d TYPE and an `ASSUME`d accessor collide on mangling

New instance of the `RentPeriod` / `rent period` class in `corpus-plan.md` §0.3, but between a TYPE
and a **function**, which the corpus had not hit. MEASURED (`p4-design/scratch/coll-probe.l4`):
`l4 check` succeeds, `l4 blawx` refuses —

```
in `conduct`: name collision (Blawx): distinct L4 definitions `Conduct` and `conduct`
both mangle to the Blawx atom `conduct` — rename one
```

The diagnostic is good (names both definitions, says what to do). Worth noting only because
`Type` / `accessorOfThatType` is an extremely natural way to write an ontology, so this will be hit
again by anyone porting an ASSUME-shaped module. A `l4 check`-time warning would find it earlier.

### 5.2 `@desc` beside `@export` still silently discards the prose

Re-measured in **this** tree (`p4-design/scratch/desc-probe.l4`), not carried over from
`corpus-plan.md` §0.1:

| form                        | `rule_text` section              |
| --------------------------- | -------------------------------- |
| `@export` ⏎ `@desc <prose>` | `Definition of form one.` — lost |
| `@desc <prose>` ⏎ `@export` | `Definition of form two.` — lost |
| `@export <prose>`           | `FORM3 export-with-prose`        |

`@export` and `@desc` are one annotation slot. Every citation in all five seeds is therefore written
on the `@export` line. **Report:** this should merge or diagnose, not vanish. It is the same failure
class as the `@export`-placement note in `benefit.l4`'s header and belongs beside it.

### 5.3 An arity-2 boolean decision has no declaration block — and round-trips anyway

`may issue a community protection notice` takes `(Person, Receiver)`, so `classifyPred` gives
`PCUndeclared`: Blawx relationship blocks start at arity 3, and the pair is not attribute-shaped.
`corpus-plan.md` §3.6 said to measure before deciding. MEASURED:

- no `blawx_attribute(…, may_issue_a_community_protection_notice, …)` is emitted;
- the rules DO emit, and the interview's query block images it as a **value attribute whose value is
  an object**, with the raw mangled atom as its `infix` because there is no `blawx_attribute_nlg`
  fact to draw a phrase from:

  ```xml
  <block type="attribute_selector"><mutation attributename="may_issue_a_community_protection_notice"
         attributetype="object" attributeorder="ov">
  <field name="infix">may_issue_a_community_protection_notice</field>
  ```

- **the row round-trips**: `etc/blawx-fixpoint-harness.mjs` regenerates `antisocial.blawx`'s
  interview byte-for-byte through the real Blawx restorers and generator (494 bytes, 27 lines, `ok`).

So the shape is **kept** and the mis-imaging is **reported**, per the brief's "confirm, report, don't
suppress". The wart is cosmetic in the scenario editor (an unnamed, object-typed selector) and not a
data-loss condition. The two arity-1 limb helpers beside it do get proper images, so the interview is
still drivable.

### 5.4 An `ASSUME`d value function is single-valued in L4 and multi-valued in s(CASP)

Writing limb (a) as three conjuncts over `effect (conduct r)` inline gives ANF a fresh variable per
occurrence:

```prolog
conduct(R,Conduct), effect(Conduct,Effect),   is_detrimental(Effect),
conduct(R,Conduct2), effect(Conduct2,Effect2), is_of_a_persistent_or_continuing_nature(Effect2),
conduct(R,Conduct3), effect(Conduct3,Effect3), affects_the_quality_of_life_of_those_in_the_locality(Effect3).
```

Under a stated scenario (one effect per conduct) that agrees with L4. Under the interview's
abduction it does not: a model can satisfy each limb with a **different** effect, which is not what
s.43(1)(a) says. Nothing in the lowering constrains an `ASSUME`d function to be functional.

The seed sidesteps it by making limb (a) a decision **over the `Consequence`**, so the chain is
walked once and one variable carries all three properties — which also buys a proper arity-1
attribute block. The general problem stands and is reported: either the middle end should emit a
functionality constraint for an `ASSUME`d value predicate, or the interview should, or the fragment
should say plainly that it does not.

### 5.5 Two smaller notes

- **`#ASSERT` needs a deeper continuation indent than `#EVAL`.** `#EVAL ` is six characters, so an
  argument block at column 9 is fine; `#ASSERT ` is eight, and the same block fails with
  `incorrect indentation (got 9, should be greater than 9)`. Purely mechanical, but it cost a cycle
  and the corpus plan's directive tables do not mention it.
- **The fixpoint harness needed `npm install --prefix etc/blawx-fixpoint-harness.deps` first**; it
  skips silently otherwise, and a silent skip is indistinguishable from a pass. The run recorded in
  §1 is a real run, with `blockly 10.1.3`, checkout `/Volumes/transcend/src/blawx`, `jsdomErrors 0`.

---

## 6. Not in this batch

- **P4c**, the Housing grounds module — untouched. `corpus-plan.md` §3 stands as its plan; note that
  its §3.6 question is partly answered by §5.3 above (an undeclared arity-2 predicate round-trips),
  which points at "keep the shape, report the mis-imaging" rather than the arity-1-wrapper fallback.
- **The `rpDesc <|> rpRef` one-liner** — already landed with the widening
  (`Blawx/Lower.hs:245`), with `BlawxAssumeSpec` covering all three arms. This batch adds the
  **corpus** witnesses for arms A and B, which no committed golden had.
- **Publishing to the container, the scenario-explorer interview, the screen recording** — the
  coordinator's tier-2 work.
- Nothing was committed, and no file outside `jl4/examples/blawx/`, `jl4/tests-cli/Main.hs`, `etc/`
  and `p4-design/` was touched by this agent.
