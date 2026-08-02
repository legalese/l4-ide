# Three-way comparison — the cleanroom encoding, our corpus, and `lexipedia.xyz`

Written 2026-08-03 against the tree at `corpus/charities-cleanroom`. Everything below was measured;
where a claim rests on a judgement rather than a measurement it says so, and where a measurement
cannot decide a question it says that too.

| the three things compared    | what it is                                                                                                                                                        |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **the cleanroom**            | `jl4/examples/legal/charities-cleanroom/charity-test.l4` — Art 5–7 encoded 2026-08-02 from `jerseylaw.je` without sight of the corpus. 1 472 lines, 90 rules.      |
| **the corpus**               | `paper/case-studies/charities-jersey-2014/part-3-charity-test.l4` — the same articles inside a 12-file, 12 762-line encoding of the whole Law. 719 lines, 33 rules. |
| **`je:charities-2014`**      | 16 pages under `process:je:charities-2014` on `www.lexipedia.xyz`, read-only, 2026-08-02/03. BPMN 2.0 + DMN 1.3 embedded in DokuWiki page text.                     |

---

## 1. Section A — the cleanroom against our corpus

### 1.1 This is the §8 diff oracle's first run on two genuinely independent encodings

`etc/go/lib/denovo-diff.mjs` was built for exactly this and has, until now, only ever been run
against a fixture that pairs a module with itself. The map, the generator that writes it, and the
oracle's own report are committed next to this file:

| artifact                                        | what it is                                                                       |
| ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| `comparison/make-surface-map.py`                | generates the map by reading both modules' `DECLARE`s — no field name is typed twice |
| `comparison/charity-test.surface-map.json`      | the declared pairing: 2 slots, 17 pairs, 45 seed rows                             |
| `comparison/denovo-diff.md` / `.json`           | the oracle's own output, unedited                                                 |

Reproduce with (the oracle lives on PR #193's branch; `unstable` has not absorbed it yet):

```
L4=…/feel-dates/…/l4  JL4_LIBRARY_PATH=…/charities-cleanroom/jl4-core/libraries \
node …/denovo-foundations/etc/go/lib/denovo-diff.mjs run \
  --map comparison/charity-test.surface-map.json --root .
```

with `jl4/examples/legal/charities-cleanroom/charity-test.l4` copied into the `denovo-foundations`
worktree, which is where the schema and the harness live. Run time 4 min; exit 1 (= ran, found
divergences — a finding, not a failure).

**Two facts about the map, because they bound everything after.** First, the `purpose` slot's two
vocabularies are in bijection except for one field, so it is perturbed freely. Second, the `charity`
slot's are **not** in bijection — the corpus flattens Art 5(2) and Art 7 into eight booleans on
`CandidateCharity` where the cleanroom nests them in `Constitution` and `PublicBenefitFinding`
records — and the oracle's `rename` only reaches a slot's top level. The map therefore carries
**both vocabularies in one object, held in sync by the generator**, and declares the slot
`perturb: false`: a single-field mutation would move one side's copy of a fact and not the other,
and every such row would read as a divergence that is an artefact of the map. That is why the
entity-level pairs are exercised by 24 hand-written seeds and no perturbations.

### 1.2 Headline

**21 221 of 21 420 evaluations agreed — 99.07 %.** 199 diverged, minimising to **60 witnesses**,
which reduce to **four root causes**. (Totals exclude one deliberately mispaired control pair; §1.5.)

| pair                      | citation             | evaluated | agreed | diverged | leaves perturbed | inert |
| ------------------------- | -------------------- | --------: | -----: | -------: | ---------------: | ----: |
| `head-d`                  | art 6(1)(d), 6(2)(a) |     2 115 |  2 115 |        0 |               27 |    25 |
| `head-f`                  | art 6(1)(f), 6(2)(b) |     2 115 |  2 115 |        0 |               27 |    24 |
| `head-h`                  | art 6(1)(h), 6(2)(c) |     2 115 |  2 115 |        0 |               27 |    25 |
| `head-i`                  | art 6(1)(i), 6(2)(d) |     2 115 |  2 115 |        0 |               27 |    24 |
| `head-p`                  | art 6(1)(p), 6(2)(f) |     2 115 |  2 115 |        0 |               27 |    25 |
| `head-n`                  | art 6(1)(n), 6(2)(e) |     2 115 |  2 027 |   **88** |               27 |    25 |
| `within-6-1`              | art 6(1)             |     2 115 |  2 081 |   **34** |               27 |     3 |
| `charitable-purpose`      | art 6(1), 6(5)       |     2 115 |  2 084 |   **31** |               27 |     2 |
| `ancillary`               | art 5(1)(a)(ii)      |     2 115 |  2 108 |    **7** |               27 |    25 |
| `charitable-or-ancillary` | art 5(1)(a)          |     2 115 |  2 086 |   **29** |               27 |     1 |
| `5-1-a`                   | art 5(1)(a)          |        45 |     42 |    **3** |                0 |     0 |
| `5-1-b`                   | art 5(1)(b), 7(3)(b) |        45 |     44 |    **1** |                0 |     0 |
| `7-3-b`                   | art 7(3)(b)          |        45 |     45 |        0 |                0 |     0 |
| `5-2`                     | art 5(2)             |        45 |     45 |        0 |                0 |     0 |
| `5-2-bites`               | art 5(2), 5(3)       |        45 |     44 |    **1** |                0 |     0 |
| `charity-test`            | art 5                |        45 |     40 |    **5** |                0 |     0 |
| **total (excl. control)** |                      |    21 420 | 21 221 |      199 |              270 |   179 |

Five of the six Art 6 head predicates agree on every one of 2 115 fact patterns, as do Art 7(3)(b)
and the Art 5(2) permission test. Two encodings written months apart, sharing no identifier, agree
on the entire charity test except at four points.

### 1.3 The four divergences, with witnesses and triage

The oracle never triages. What follows is judgement, and is labelled as such.

---

**D1 — Art 6(2)(e): does providing accommodation or care, alone, engage head (n)?**
_56 of the 60 witnesses. Minimal witness: `(2)(e)` `false → true` on the agreeing seed
`purpose:poverty`, `head-n` — corpus `TRUE`, cleanroom `FALSE`; also seen on 42 further rows._

The corpus reads 6(2)(e) as **widening** head (n): `head (n) as extended by Article 6(2)(e)` is
`(n) .. (2)(e)`, so the operand alone suffices. The cleanroom reads it as **declaratory** — "(1)(n)
_includes_ relief given by the provision of accommodation or care" takes the word "relief" from
(1)(n), which supplies that relief's object — and therefore gives 6(2)(e) **no operand at all**
(README ambiguity **A2**). The observable consequence is stated in the cleanroom's own register: on
the corpus's reading a commercial care home is charitable.

The disagreement is sharpened by what the two encodings do agree on. Both give 6(2)(a) and 6(2)(b)
extra operands that widen heads (d) and (f) — `head-d` and `head-f` agree 2 115/2 115. It is only at
(2)(e) that they part. The corpus took the widening reading at all three; the cleanroom took it at
two and refused it at the third, on the ground that (2)(a) and (2)(b) introduce new subject matter
while (2)(e) re-describes the mode of a relief the head already defines.

**Triage: GENUINE AMBIGUITY, registered on one side only.** Neither reading is unavailable on the
text. The finding is not that the corpus is wrong; it is that the corpus made this choice **without
recording that a choice was made**, and a reader of the corpus cannot tell that Art 6(2)(e) was
contested. That is the single most useful thing this whole exercise produced, and the remedy is a
note in the corpus, not a code change.

---

**D2 — Art 5(1)(a)(ii): "purely ancillary … to any of _its charitable purposes_" when it has none.**
_1 witness, minimal by construction. Seed `entity:the gift shop with nothing behind it`, one field
moved (`is purely ancillary…` `false → true`) — corpus `TRUE`, cleanroom `FALSE`._

The cleanroom reads "its charitable purposes" **referentially**: the limb presupposes a charitable
purpose for the ancillary one to attach to, so an entity whose every purpose is merely ancillary
fails 5(1)(a) (README **A9**; the gate is the `the entity has at least one charitable purpose`
decision, which is why the cleanroom's version of this predicate takes the entity as a second
argument and the corpus's does not). The corpus takes the characterisation as a given flag and lets
it through.

**Triage: GENUINE AMBIGUITY, registered on one side only.** The corpus's reading admits an entity
that is incidental to nothing. The cleanroom's reading is the stricter one and is registered with
its counter-case. Again: a note owed to the corpus.

---

**D3 — Art 5(2)'s trailing "acting in that capacity".**
_2 witnesses: `5-2-bites` (corpus `TRUE`, cleanroom `FALSE`) and `charity-test` (corpus `FALSE`,
cleanroom `TRUE`), both on `entity:the trust with a Minister in a private capacity`._

The cleanroom gives the trailing qualifier its own operand on `Constitution` and conjoins it into
the disqualification. The corpus folds it into the **name of the chapeau field** — the field is
literally called `…a person of the following description, acting in that capacity` — and then adds
a bare inert string `AND "acting in that capacity."` that carries no operand.

**Triage: GRANULARITY GAP, surfaced by the pairing; neither encoding is wrong.** Read carefully, the
corpus asks one composite question where the cleanroom asks two atomic ones, and a fact-finder who
understood the corpus's field would answer it `FALSE` for a Minister admitted privately — at which
point the two agree. The divergence is real in the sense that **no assignment to the corpus's
vocabulary distinguishes the case**, and the shared battery had to pick one; it is not a semantic
disagreement about the statute. Worth recording because the corpus's decorative
`AND "acting in that capacity."` reads, at a glance, like an operand and is not one.

---

**D4 — Art 5(1)(b): "provides (or, in the case of an applicant, provides or intends to provide)".**
_1 witness. Seed `entity:the applicant not yet operating` — corpus `FALSE`, cleanroom `TRUE`._

Same shape as D3, and the weakest of the four. The corpus has **one** boolean where the cleanroom
has **three** (`provided`, `intended`, `an applicant`), and derives the disjunction that the corpus
asks its user to perform mentally. The cleanroom's register (**A11**) turns on exactly the
distinction the corpus's single bit cannot hold.

**Triage: GRANULARITY GAP, surfaced by the pairing.** The witness's polarity is the map's choice and
is flagged as such; the underlying non-bijection is not a choice and is what made the choice
necessary.

---

### 1.4 Where agreement is not evidence

179 of 270 perturbed `(pair, fact)` leaves were **inert** — the battery moved them and neither side's
answer moved. Most are trivially so and correctly so (perturbing `(o) animal welfare` under `head-d`
should do nothing). But two are worth naming:

- **`charitable-purpose` × `is purely ancillary…` — 45 perturbations, 0 moved an answer.** Correct on
  both sides: the ancillary flag has no business in the 5(1)(a)(i) limb. Agreement here is agreement.
- **`ancillary` × every head field — 24 leaves × 45, all inert.** _Not_ evidence. The A9 gate means
  the cleanroom's answer depends on the **entity's** purposes, and the entity slot was frozen
  (`perturb: false`, §1.1). A difference in how the two sides read the gate across varying entities
  is invisible to this battery. D2 was caught only because a hand-written seed put the entity in the
  one state that exposes it.

### 1.5 The control pair, and why it is in the map

A seventeenth pair, `political`, deliberately mispairs the corpus's `is a charitable purpose`
(a positive test) with the cleanroom's `(5) — the purpose is excluded as political` (an exclusion).
It diverged **1 967 of 2 115** and produced 56 witnesses. It is excluded from every total above and
retained in the map because it demonstrates that the oracle reports a bad declaration loudly rather
than absorbing it — the failure mode a declaration-driven comparator is most exposed to.

### 1.6 Structural comparison, where behaviour cannot reach

| dimension                     | corpus (part 3)                                                    | cleanroom                                                          |
| ----------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------- |
| lines / rules declared        | 719 / 33                                                           | 1 472 / 90                                                          |
| `@ref` citations              | 0 (statute quoted inline as inert operands, 38 lines)              | 45 (plus 69 inert-quote lines)                                      |
| `#ASSERT` / `#TRACE`          | 35 / 4                                                             | 102 / 0                                                             |
| `@export`                     | none                                                               | 1 (`the entity meets the charity test`)                             |
| regulative layer              | **yes** — Art 5(4)–(8), 7(2), 7(3)(a) as `MUST`/`SHANT` (17 lines) | **none** — declared out of scope; the file says the cluster is wholly constitutive |
| Art 7(2)/7(3)(a)              | inert strings **and** duties on the Commissioner                   | procedural fields feeding `the public benefit determination was properly made`, deliberately non-truth-conditional (A8) |
| Art 5(2) decomposition        | chapeau + three person limbs                                       | six limbs (3 persons × 2 modes) + capacity operand (A12)            |
| Art 2 ontology                | full `Entity` from `part-1-interpretation.l4` (18 fields), shared across the statute | `Article 2(4)/(6)/(7)` carried inert; a local `Entity` with 6 fields |
| ambiguity register            | choices argued in prose comments, not enumerated                   | 12 numbered entries, each with both readings, the reading taken, and the scenario that exercises it |
| breadth                       | the **whole Law** — 12 files, 12 762 lines, Parts 1–9 + Schedules  | Art 5–7 only                                                        |

The two are not competitors. The corpus is a whole-statute encoding with a deontic layer; the
cleanroom is a deeper, narrower, more self-documenting cut of one cluster. The interesting result is
that their **decision surfaces coincide** — every corpus decision in Art 5–7 has a cleanroom
counterpart and vice versa, which is what made the 17-pair map writable at all.

---

## 2. Section B — the cleanroom's export against `je:charities-2014`'s DMN and BPMN

All lexipedia figures below are from read-only fetches on 2026-08-02/03 (`do=export_raw`,
`do=revisions`), and corroborate the counts already in `specs/todo/lexipedia-superset/LEXIPEDIA-PROBE.md` §2.5.

### 2.1 Same three decision points

| their decision                    | their name                              | the cleanroom's counterpart                                    |
| --------------------------------- | --------------------------------------- | ---------------------------------------------------------------- |
| `Decision_PurposeClassification`  | "Classify a purpose (Art 6)"            | `the_purpose_falls_within_paragraph_1` + 16 per-head decisions   |
| `Decision_PublicBenefit`          | "Public benefit (Art 7)"                | `_5_1_b_public_benefit`, `_7_3_b_…identified_natural_persons`   |
| `Decision_CharityTest`            | "Charity test (Art 5)"                  | `the_entity_meets_the_charity_test` (the `@export`ed root)      |

Their BPMN (`Process_CharityTest`, `isExecutable="false"`) sequences three `businessRuleTask`s
`r_class` → `r_pb` → `r_test` into an XOR gateway `g_result` with flows
`meetsCharityTest == True` / `== False`. `r_class` is marked "[multi-instance]" — the same
per-purpose-then-aggregate shape the cleanroom gets from `all` over `entity's purposes`.

### 2.2 The shapes are opposites

| measure                | `je:charities-2014` `dmn-charity-test`                              | cleanroom `projections/charity-test.dmn`               |
| ---------------------- | --------------------------------------------------------------------- | -------------------------------------------------------- |
| `<decision>`           | 3                                                                     | **40**                                                   |
| `<decisionTable>`      | **3** (28 rules total, `hitPolicy="FIRST"` throughout)                | **0**                                                    |
| boxed literal exprs    | 0                                                                     | 40                                                       |
| `<inputData>`          | **0**                                                                 | 2 (`entity`, `purpose`)                                  |
| `<itemDefinition>`     | 0                                                                     | 4                                                        |
| BKM                    | 0                                                                     | 1                                                        |
| identifiers            | camelCase (`meetsCharityTest`, `purposeCategory`)                     | sanitised statutory prose (`_5_1_b_public_benefit`)      |
| executes?              | not measured here — has no `inputData`, so nothing declares its inputs | **no** — both engines refuse; two L4 list quantifiers have no FEEL lowering (`PROJECTIONS.md` §4) |

Neither artifact is currently an executable exhibit, for opposite reasons. Theirs is a set of
tables with no declared data inputs and a BPMN→DMN link that is **prose inside `<documentation>`,
not a `decisionRef` attribute** — a human can follow it, an engine cannot. Ours has a full
requirements graph, two `inputData` and four `itemDefinition`s, and is rejected by KIE and Camunda
alike because `any`/`all` over a list emits raw L4 into a `<text>` body.

### 2.3 What each modelled that the other did not

**They modelled and we did not:**

- **Art 7(2)(a) and 7(2)(b) as defeaters.** Two of their four `Decision_PublicBenefit` rules fail the
  test outright — `netPublicBenefitPositive = false → false`, `conditionsNotUndulyRestrictive =
false → false`. The cleanroom's **A7** considered precisely this and took the other reading: 7(2)
  says "must have regard to" where 7(3) says "must not", and collapsing the two erases a distinction
  the drafter made in adjacent paragraphs. Our corpus also declines to make 7(2) truth-conditional.
  **This is a live legal disagreement between three independent encodings, two against one**, and it
  is the reading the cleanroom's register itself flags as "the choice most likely to be wrong".
- **A named `head` output.** Their classification table returns the article number that carried the
  purpose (`"Art 6(1)(a)"`, `"Art 6(2)(f) — analogous to Art 6(1)(c)"`). The cleanroom returns a
  boolean and leaves the reason to the ladder trace. Their form is better for a caseworker's file
  note; ours is better for verification.
- **Per-rule `reason` strings** on every outcome, in both entity-level tables.
- **Namespace breadth.** Their 16 pages cover registration, deregistration, enforcement, appeal,
  name-check, governor fitness, ongoing compliance and the restricted section. The cleanroom covers
  Art 5–7 only. (Our corpus covers all of those and more, in L4.)

**We modelled and they did not:**

- **Every Art 6(2) qualification except (2)(f).** They have no health widening (2)(a), no citizenship
  widening (2)(b), no sport gate (2)(c), no recreational-facilities gate (2)(d), no accommodation
  limb (2)(e). Their `"public_participation_sport"` category returns `true` unconditionally — so a
  chess club is charitable on their model and is not on either of ours.
- **Art 5(1)(a)(ii) per purpose.** They take `allPurposesCharitableOrAncillary` as a single input
  already aggregated "in BPMN" (their own `<description>` says so). Neither the ancillary test nor
  the A9 question exists on their model.
- **Art 5(2)'s internal structure.** One boolean, `constitutionAllowsGovtControl`, against the
  corpus's four fields and the cleanroom's seven.
- **Any entity or purpose ontology.** Zero `inputData`, zero `itemDefinition`.
- **Art 2 definitions** — "entity", "constitution", "purpose", "governor" — which both of ours carry.
- **The Art 5(4)–(8) guidance machinery**, which our corpus has as deontic rules.

**Both modelled, same answer:** the three-way split of the test; per-purpose classification then
aggregation; Art 6(5) as an override that defeats an otherwise-qualifying purpose; Art 5(2) defeated
in turn by an Art 5(3) Order; Art 7(3)(b) as a bar on treating identified individuals as a section
of the public; Art 6(2)(f) reaching head (p) by analogy to (1)(c).

---

## 3. Section C — the provenance fingerprint

**What this section is.** `LEXIPEDIA-PROBE.md` §2.5 recorded that a namespace on a third-party wiki
encodes the same statute as one of our case studies, and recorded — correctly — that read-only
access cannot determine who wrote it or from what. This section does not revisit that. It asks a
narrower, answerable question:

> Does the convergence sit where **any** competent encoder of this public statute would land, or does
> it sit on our corpus's **unforced idiosyncrasies**?

The cleanroom is what makes the question answerable. It is a third encoding of the same articles,
written without sight of the corpus, by an author with no access to the wiki. It therefore acts as a
control: anything the cleanroom independently reproduces is, by demonstration, forced by the statute
rather than distinctive to us.

**Report patterns only.** Nothing here asserts an origin, and nothing here should be read as
asserting one.

### 3.1 The fingerprint table

`forced` = the statute or the notation leaves essentially no alternative. `free` = a competent
encoder could reasonably have done otherwise, so a match carries information.

| #   | feature                                    | ours (corpus)                                                   | cleanroom (independent control)                                | `je:charities-2014`                                                | forced / free | what the pattern shows                        |
| --- | ------------------------------------------ | ----------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------- | ------------- | ----------------------------------------------- |
| 1   | three decision points (Art 6 / Art 7 / Art 5) | yes                                                            | yes                                                             | yes                                                                  | **forced**    | all three converge; the statute has three articles |
| 2   | the two overrides identified                | 6(5) political, 5(2)–(3) government control                     | same two                                                        | same two                                                             | **forced**    | they are the only override provisions in the cluster |
| 3   | classify per purpose, then aggregate        | `all` over the purpose list                                     | `all` over the purpose list                                     | `r_class` "[multi-instance]", aggregated in BPMN                     | **forced**    | Art 5(1)(a) says "all of its purposes"          |
| 4   | 5(3) Order as a negative limb on 5(2)       | yes                                                             | yes                                                             | `govtControlDisapplied`                                              | **forced**    | 5(3) does nothing else                          |
| 5   | 7(3)(b) as a bar on public benefit          | lifted, operative                                               | lifted, operative (A6)                                          | first rule of `Decision_PublicBenefit`                               | **forced**    | the provision's closing words                   |
| 6   | word used for the two overrides             | **"knock-out"** — 14 uses in `part-3-charity-test.l4`, 0 of "carve-out" | **"carve-out"** — 9 uses in `charity-test.l4`, 0 of "knock-out" (17 across the cleanroom's four files) | **"carve-out"**                                                      | **free**      | matches the **independent control**, not us     |
| 7   | identifier style                            | backticked statutory prose                                      | backticked statutory prose                                      | camelCase (`meetsCharityTest`)                                       | **free**      | matches neither of ours                         |
| 8   | Art 6(1) heads as booleans vs one enum      | 16 independent booleans; comment argues an enum "would force a false exclusivity" | 16 independent booleans; comment argues the same | **one string enum**, `purposeCategory`, 19 values, `hitPolicy FIRST` | **free**      | matches neither; takes the option **both** of ours argue against in writing |
| 9   | Art 6(2)(a)–(e) modelled                    | all five (widen / gate / widen)                                 | four of five ((2)(e) refused, A2)                               | **none**                                                             | **free**      | matches neither                                 |
| 10  | order of 6(1)(p) vs 6(2)(f)                 | (p) then (2)(f)                                                 | (p) then (2)(f)                                                 | **(2)(f) then (p)** (`r_15`, `r_16`)                                 | **free**      | matches neither                                 |
| 11  | is Art 7(2) truth-conditional?              | **no** — inert, plus duties on the determiner                   | **no** — procedural fields only (A7, A8)                        | **yes** — two of four public-benefit rules fail the test on 7(2)     | **free**      | matches neither; two-against-one legal disagreement |
| 12  | Art 7(3)(a) treatment                       | `SHANT` deontic rule                                            | non-truth-conditional procedural field                          | prose in a `<description>`, no operand                               | **free**      | three different answers                         |
| 13  | Art 5(2) decomposition                      | chapeau + 3 person limbs                                        | 6 limbs + capacity operand (A12)                                | **one boolean**                                                      | **free**      | matches neither; coarser than both              |
| 14  | entity / purpose ontology                   | Art 2 `Entity`, 18 fields, shared statute-wide                  | `Entity` / `Constitution` / `PublicBenefitFinding` / `Purpose` | **none** — 0 `inputData`, 0 `itemDefinition`                         | **free**      | matches neither                                 |
| 15  | verbatim statute inline as inert operands   | 38 lines                                                        | 69 lines                                                        | **none** — paraphrased `reason` strings                              | **free**      | matches neither; this is the most recognisable single trait of our house style |
| 16  | citation form                               | quoted statute text in the code                                 | 45 `@ref` lines                                                 | `"Art 6(1)(a)"` in output cells                                      | **free**      | matches neither                                 |
| 17  | regulative / deontic layer                  | 17 `PARTY … MUST/SHANT` lines, 4 `#TRACE`                       | none (declared out of scope)                                    | none (BPMN `isExecutable="false"`, no duties)                        | **free**      | cleanroom and theirs agree by omission          |
| 18  | decomposition granularity (their scope)     | 33 rules over Art 5–7                                           | 90 rules / 40 DMN decisions                                     | 3 decisions, 28 rules                                                | **free**      | an order of magnitude apart from both           |

### 3.2 What the table shows

**Every row on which the three converge is a `forced` row, and every `free` row on which our
corpus makes an unforced choice is a row where `je:charities-2014` does something else.**

Rows 1–5 are the convergence. All three land there — and the cleanroom's landing there, having
never seen the corpus, is a demonstration rather than an argument that this shape is what the
statute imposes. An encoder reading Art 5–7 has three articles, one of which is a two-limb
conjunction defeated by exactly two provisions; there is no other place to arrive.

Rows 6–18 are thirteen unforced choices. On twelve of them, `je:charities-2014` matches neither of
our encodings — and on several it takes an option our comments explicitly argue against (row 8), or
a legal reading both of ours reject (row 11), or a level of detail an order of magnitude coarser
(rows 9, 13, 18). Row 6 is the only free row with a match, and the match is with the **cleanroom** —
the encoding that provably could not have influenced it — which is what a shared professional
vocabulary looks like rather than a shared source.

Rows 15 and 7 deserve separate mention. Verbatim statute text carried inline as inert operands, and
backticked natural-language identifiers, are the two traits by which an L4 file is recognisable
across a room. Both of our encodings are saturated with them. Neither appears anywhere in
`je:charities-2014`.

**Verdict, stated as a strength of evidence and not as a conclusion about origin.** On the pattern
measured, the convergence is **convergence-by-necessity**. The hypothesis that the namespace's shape
is derived from our corpus's distinctive choices is not supported by any of the eighteen features
examined; the hypothesis that a competent encoder working from the published statute would land on
the shared shape is directly evidenced by the cleanroom having done so.

### 3.3 Limits — what this cannot decide, stated plainly

1. **Read-only access cannot distinguish import from independent encoding.** It never could, and
   this section does not claim to. It measures which hypothesis the convergence pattern favours, and
   how strongly. Nothing more.
2. **Absence of a fingerprint is not proof of absence of influence.** A person who read our corpus
   and then modelled the statute in DMN in their own idiom would leave exactly the trace we observe:
   the forced rows matching, the free rows not. What can be said is narrower — **no positive trace of
   our unforced choices survives in the artifact**.
3. **The wiki's timestamps decide nothing.** Both charities pages carry
   `Last modified: 2026/07/27 by 127.0.0.1` and **`do=revisions` lists zero older revisions**, so the
   only observable write is a single one. Our corpus file was committed to `origin/unstable` on
   2026-07-18 (`b93b36dc`). Ordering of two dates does not establish direction, `127.0.0.1` is what
   DokuWiki records for any filesystem-level write (an import script, a maintenance job and a manual
   edit are indistinguishable), and a single stored revision means the page's own history holds no
   further evidence either way.
4. **Only the pages fetched were examined** — `start`, `charity-test`, `dmn-charity-test`, and the two
   revision listings. The other eleven pages in the namespace were not fetched for this comparison.
   The probe's finding that the namespace contains no occurrence of `L4`, `legalese`, `jl4`,
   `smucclaw` or a GitHub URL was re-confirmed on `start` and is otherwise carried from
   `LEXIPEDIA-PROBE.md` §2.5, unverified here for the pages it did not cover.
5. **Their content is CC BY-SA 4.0** (wiki-wide footer); ours is Apache-2.0. This section makes no
   licensing claim and no claim about anyone's conduct.

---

## 4. What is owed

Findings that belong to documents other than this one. None is applied here.

1. **The corpus should register Art 6(2)(e) as a contested reading** (D1) and say which reading it
   took and why. Today the choice is invisible to a reader.
2. **The corpus should register Art 5(1)(a)(ii)'s referential question** (D2), same reason.
3. **The corpus's `AND "acting in that capacity."` reads like an operand and is not one** (D3).
   Either give it one or say in a comment that the chapeau field carries it.
4. **Art 7(2)'s modality is a genuine three-way disagreement in the wild** (§2.3, fingerprint row
   11) and is worth a paragraph in whichever paper covers the determinacy frontier — two independent
   encodings read "must have regard to" as non-defeating and a third reads it as defeating.
5. **The oracle's `rename` cannot reach nested records** (§1.1). Every entity-level pair in this run
   is unperturbed because of it. A `rename` that descends, or a per-slot projection, would have made
   D2's neighbourhood searchable instead of hand-seeded.
