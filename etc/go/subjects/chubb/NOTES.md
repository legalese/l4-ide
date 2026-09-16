# chubb — subject idiosyncrasies

Free prose about **this subject**, for humans and for the skill. **No script reads this file.**
Machine-readable facts live in `subject.json`; the CLI-surface pin in `pins.json`; the (currently
empty) negative controls in `known-defects.json`. When a fact below stops being true, fix it here in
the same change that moved it — a stale idiosyncrasy note misleads the next encoder.

Written 2026-08-31, for someone arriving cold.

---

## 1. Read this first: the source is not law

Every other subject under `etc/go/subjects/` encodes a real instrument — a CFR part, four Singapore
Acts. **This one does not.** The source text is:

> Appendix A.1, _"Simplified Chubb Hospital Cash Benefit Policy"_, in Kant, Nabi, Kant, Scharrer, Ma
> & Nabi, **"Towards Robust Legal Reasoning: Harnessing Logical LLMs in Law"**, arXiv:2502.17638v1
> [cs.CY], 24 February 2025. <https://arxiv.org/abs/2502.17638>

That is a **synthetic fixture printed in a research paper**. Its own authors wrote it, abridging and
anonymising a Chubb hospital-cash form; the party named in the text is "CODEX INSURANCE LIMITED".
It was never issued to anybody, it is not in force, no regulator has seen it, and no court will ever
construe it. It is 54 lines and 3,573 bytes long — three sections, two flat enumerations, and no
definitions section at all.

**Nothing in this subject is a statement about any real insurer's real cover, and nothing produced
from it is advice.** If you find yourself about to cite a chubb run as though it said something
about insurance law, stop: it says something about _encoding_, which is the whole point.

### Why the subject exists

Kant et al. measured LLM accuracy at translating this fixture into Prolog, in three arms
(vanilla / unguided / guided), scored against a **nine-question answer key the same authors wrote**.
Reported accuracies run 0.78 (vanilla), 0.41–0.89 (unguided Prolog), 1.00 (guided Prolog). This
subject is the L4 replication of that measurement: same fixture, same nine queries, L4 in place of
Prolog.

So the interesting artifact here is not the encoding. It is the **comparison** — and, as §3 below
sets out, the audit of the answer key that the replication had to do before it could score anything.

---

## 2. Provenance of the judgements in this sidecar

A prior "foundation" phase produced, in one session:

- an adversarial audit of all nine gold labels;
- an audit of the fixture itself (20 defects, `runs/source-defects.md`, 652 lines);
- a capability probe of L4 against what this policy asks a language to express;
- **three independent L4 encodings** of the policy, in three house styles (inert, record, guarded),
  by three encoders who were **not shown the answer key** and did not read each other's work.

Its consolidated report is `runs/FOUNDATION.md` (69 KB). Section references below are to it.

> **The report lives in a session scratchpad**
> (`…/scratchpad/kant-repl/runs/FOUNDATION.md`) **under `/private/tmp`, and that directory will not
> survive.** Everything load-bearing is therefore restated here rather than pointed at. If you are
> reading this in a year and the path is gone, this file is the record; the section numbers are kept
> so that a copy recovered from a transcript can still be lined up against it.

The two arms this subject deposits:

| file                                                                      | style   | role                                 | foundation ranking                            |
| ------------------------------------------------------------------------- | ------- | ------------------------------------ | --------------------------------------------- |
| `jl4/examples/canon/us/chubb-hospital-cash/blind-inert/chubb.l4`          | inert   | committed encoding (`encoding.main`) | reference — best on both axes (§4.1)          |
| `jl4/examples/canon/us/chubb-hospital-cash/blind-guarded/chubb-denovo.l4` | guarded | `encodings.guarded-2026-08`          | acceptable; two confirmed logic errors (§4.1) |

They are two different files by two different authors, which is what makes the §8 acceptance diff a
real comparison rather than an identity. The third arm (record style) was not deposited.

---

## 3. The benchmark's own answer key is contested — on Q4 and Q5

**Do not treat the published key as ground truth without reading this section.** It is nine bare
labels: Appendix A.2 gives each query followed by `Answer: "Yes."` or `Answer: "No."` — **no clause
citation, no rationale, no record of any interpretive choice.** It is self-authored and self-scored
by the same team that wrote the policy and the queries, and by the paper's own footnote 3 an unknown
fraction of the reported Prolog accuracy is _"manually reasoned through"_ encodings that would not
run.

All three blind encodings answer **No/Yes/Yes/Yes/No/No/Yes/No/Yes** to Q1–Q9. That agrees with the
published key on **8 of 9**, and the three disagree with it unanimously on **Q4**.

### Q4 — under-determined, not wrong (FOUNDATION.md §1.3)

> Q4: _"will my policy apply if I was hospitalized due to a fall while traveling abroad and I had
> given confirmation of my wellness visit 8 months after the policy's effective date?"_ — published
> answer **"No."**

**The query never says when the hospitalization occurred, and clause 1.1 makes that the operative
moment.** 1.1 conditions payment on the policy being in effect _"at the time of the
hospitalization"_, and limb 1.1(3) is satisfied while the §1.3 wellness condition _"is still
pending"_. Before the month-7 deadline the condition is pending, the policy is in effect, and the
claim is good however late the confirmation eventually arrives. After month 7 it is not. So the
answer is a function of a fact the query omits.

Each encoder resolved it by applying **the benchmark's own stipulated preamble** — _"assuming all
other conditions are met and no other exclusions apply, where by 'other' I mean anything not
referenced in the query"_ — which says to set an unreferenced fact to the value that lets the policy
apply. That yields **Yes**.

The best case for the published "No" is grammatical: the query's pluperfect (_"I **was
hospitalized** … and I **had given** confirmation … 8 months after"_) sequences the confirmation
before the hospitalization, putting the hospitalization after month 8 and after cancellation. That
is a real argument, and it is why the label was rated defensible — **but it comes from the tense of
the question, not from the policy, and it points the opposite way to the benchmark's own preamble.**
A system that follows the stated instruction is penalised; a system that instead parses English
aspect is rewarded.

The guarded arm ships the counterfactual rather than arguing it: the same claim at month 7 answers
TRUE and at month 9 answers FALSE. The sensitivity is measured.

**Score Q4 both ways, or score it as under-determined. Do not silently adopt either label.**

### Q5 — the label the audit judged _not defensible_ (FOUNDATION.md §1.4)

> Q5: _"will my policy apply if I was hospitalized for punching my own face to show off for my
> friends and I did not commit fraud or misrepresentation?"_ — published answer **"No."**

After the preamble, exactly one thing can produce "No": a narrow reading of 1.1's phrase
_"hospitalization **for sickness or accidental injury**"_. And **§2.1 contains no
intentionally-self-inflicted-injury exclusion at all** — the drafter enumerated skydiving, military,
fire, police and age, and omitted self-harm. So the "No" has to come from construing an undefined
term in the coverage grant against the insured, in a document with **no definitions section
whatever** (`grep -iE 'means|defined|definition|shall mean'` finds nothing).

The counter-argument the auditor found stronger: §3.3.1 makes the policy governed by New York law,
and New York abandoned the accidental-means/accidental-result distinction — the test is whether the
resulting _injury_ was unintended from the insured's standpoint, not whether the act was voluntary.
A stunt punch is a deliberate act with an unintended fracture. _(The auditor cites Miller v.
Continental Ins. Co., 40 N.Y.2d 675 (1976). **That citation has not been verified in this tree and
must be checked before it appears in anything published.**)_

Worse for the benchmark: in every encoding, "neither sickness nor accidental injury" is a
**constructor value set in the fact record**, not something any rule derives. So on Q5 the benchmark
is scoring the marshalling step, not the encoding step. The paper reports its best model missing Q5
in 9 of 10 trials and diagnoses the term as _"addressed indirectly in the contract"_ — conceding
that it is not defined.

### Converging evidence that {Q4, Q5, Q9} are the hard ones

Three independent lines land on the same three items:

1. the adversarial label audit classed Q4 and Q5 as interpretive (7 of 9 mechanical);
2. the three blind encoders each, separately, marked **Q4, Q5 and Q9** as "required a judgement";
3. the paper's own error analysis says of its best vanilla model: _"errors mostly in Question 5, and
   it consistently failed to answer Questions 9 and 4."_

**A third of a nine-item key is beyond the mechanical.** Treat "accuracy against this key" as a
distance from one team's unrecorded reading, and say so wherever a number from it is reported.

---

## 4. The fixture is badly drafted: 20 recorded defects

These are defects in the **instrument**, found by reading it — as against defects in the pipeline's
projections of it, which is what `known-defects.json` is for and why it is empty. The four that
change answers:

- **D1 — there is no insuring clause.** Nothing says what benefit is payable, in what amount, or on
  what trigger; `grep -nE '\$|percent|%'` finds no monetary amount anywhere. §1.1 says only that
  payment is _"conditioned on"_ the policy being in effect; §2.1 says when it _"will not apply"_.
  **Every encoder must therefore invent the insuring clause** as `covered ⟺ in-effect ∧ ¬excluded`,
  and all four "Yes" golds rest on the _absence_ of a firing exclusion rather than on any grant.
  This is why both deposited modules answer a **necessary-conditions** question: TRUE means "nothing
  in the policy as supplied defeats this claim", **not** "the insurer owes $X". Both say so in their
  own headers; do not quote a TRUE as an entitlement.
- **D3 — 1.1(3) and 1.2 disagree during the pendency window.** 1.1(3) is satisfied by "still pending
  _or_ satisfied in a timely fashion"; 1.2 deems cancellation where the condition "has _not_ been
  satisfied in a timely fashion", with no pendency carve-out. At month 5 both fire. **Decides Q3.**
- **D4 — §2.1's fifth item does not fit its own chapeau.** The chapeau is causal ("any event causing
  sickness or accidental injury arising directly or indirectly out of:"), items 1–4 are bare noun
  phrases, and item 5 is a finite conditional ("If your age … is equal to or greater than 80"),
  which does not parse under it. Nothing in the text signals the switch. **Decides Q2 and Q9
  jointly** — Q9's gold needs the causal reading and Q2's needs the status reading.
- **D7 — cancellation has no effective moment.** §1.2 says cancellation "will be deemed to have
  occurred if…" and never says _when_; there is no notice, cure, refund or reinstatement provision.
  Since §1.1 fixes the test at the time of the hospitalization, the missing date is load-bearing.
  **Decides Q4** — the same gap §3 above reaches from the other side.

And, called out because the task of reading this file cold is exactly when it bites:

- **D2 — two live cross-references to a "Section 5" that does not exist.** §1.2 refers to _"the
  policy term described in Section 5 below"_ and §3.5.1 to _"the premium described in Section 5
  below"_. **The document's highest section is 3.** Both dangling references are the money-and-time
  clauses. All three encoders read §3.6 for the term (the alternative makes the policy perpetual)
  and treated the premium and benefit amounts as unrecoverable and not modelled. That reading is a
  repair, and it is recorded as one.

The remaining defects, in one line each: "in a timely fashion" names one deadline where §1.3 has two
(D5); four separate faults in the one fraud sentence (D6); a **Singapore** statute — "the
Arbitration Act (Cap. 10)" — cited in a policy governed by **New York** law, template residue the
anonymisation missed (D8); a rights-extinguishing arbitration clock running from an unascertainable
day (D9); "at the signing of the policy" where the document has two distinct signings (D10); an
unqualified grant of cover with no "subject to the terms" saver (D11); items 1–4 tested at the time
of the _event_ and item 5 at the time of the _hospitalization_, with no rule for the gap (D12); §3.6
being the only subsection with its heading run into its body, so **a chunker keyed on the pattern the
other five establish silently drops the clause that defines the effective date** (D13); 1.2 and 3.6
defining each other in a loop, one leg of which is D2's dangling reference (D14); no definitions
section (D15); and D16–D20, a doubled "and", unobserved defined-term casing, a cataphoric "the
medical provider in question", an unbounded "or someone else" payee, and the total absence of claim-
notice, proof-of-loss, payment-timing, cancellation-notice, cure, refund and renewal provisions.

**Five of the nine gold answers rest on a defect rather than on plain meaning** (Q3 on D3, Q4 on D7
and D5, Q5 on D15, Q6 on D5, Q9 on D4).

**The defects are deliberately NOT repaired.** A replication has to run against the fixture as
published or it is not a replication. A repaired-fixture arm would be a separate, clearly labelled
subject, and would need its own sidecar.

---

## 5. Why this is encodable at all: months, not dates

**The paper's prompt convention expresses every time as a number of months relative to the effective
date.** Month 0 is the effective date, month 6 is the 6th-month anniversary, month 12 is the first
anniversary. So the whole temporal apparatus of the policy — the 6-month visit deadline, the 7-month
confirmation deadline, the one-year term, the 3-month arbitration window, the 60-day suit bar — is
arithmetic on small integers. **No calendar arithmetic is done or needed anywhere in either module.**

Three consequences worth keeping straight:

1. **It is what makes the fixture encodable in a single sitting**, in any target language. Both
   modules take a claim record whose time fields are plain numbers, and neither imports a date
   library.
2. **It is why `min_dated_arms` is 0 for both encodings, honestly.** Neither module contains the
   string `RULES EFFECTIVE DATE` at all, so p3-check's matcher — which wants that string and a
   `Date <digit>` literal on the same physical line — has nothing to match. There is no
   rule-version axis to have: one instrument, one term, one point in legal time. A 0 floor makes the
   temporal-closure sub-check report **NOT CHECKED** rather than printing a vacuous "all 0 dated
   arm(s) carry an @ref". Raise it the day this subject gains a dated arm; never lower a floor to
   make a run pass.
3. **It is a threat to the measurement, not a point in L4's favour.** The one convention the
   benchmark imposes is precisely the convention that disarms L4's main advantage over Prolog here.
   Any writeup that leans on "L4 handles time better" has to say that this benchmark was built so
   that nothing has to.

The 60-day bar in §3.2.1 is the one genuine encoded shortcut, disclosed in every arm: **60 days is
read as 2 months** on a months-only clock. Its harm is currently nil because the rule consuming it
is deliberately not wired into the payability decision — the drafter used "condition precedent to
our liability" in the preceding sentence and not in that one, so folding it in would turn "not yet
enforceable" into "not covered" for every claim in its first two months.

---

## 6. The shared bug all three encoders wrote

Worth more than the ranking, and worth knowing before you trust any arm: **all three encodings
extinguish the claim under §3.2.1 while the three-month arbitration window is still open**, because
none gives the arbitration limb an "as at" moment — _even though all three built careful three-valued
pendency machinery for clause 1.3, whose logical shape is identical._

The difference between the two clauses is not logical, it is lexical: **§1.3 is reachable through
1.1(3), which uses the words "still pending", and §3.2.1 says only "If You fail to commence".** You
get a three-valued treatment where the source text names the third value and a two-valued one where
it does not. Three independent encoders, same omission, same cause.

**And the benchmark cannot see it.** No query mentions a dispute, so all three arms default the
arbitration facts to inert and all three still score 8/9. A nine-item benchmark scores an encoding
only on the clauses its items happen to exercise: of the 35 interpretive choices the foundation
phase catalogued, **29 are invisible to the nine questions entirely.**

---

## 7. Sidecar facts you will otherwise have to re-derive

### Floors

- **`checks.min_assertions` is the executed count**, measured with
  `node etc/go/lib/assert-report.mjs` over `l4 run --json` for `chubb.l4` — `assertions_total` out of
  `results[]`, **not** `grep -c '#ASSERT'`. Pin it to the executed figure; regcf's own note records
  the discrepancy that convention exists to avoid (a `#ASSERT` inside a comment).
- **`encodings.guarded-2026-08.checks.min_assertions` is 0, and 0 is the measured population.**
  `chubb-denovo.l4` carries no `#ASSERT` at all: the foundation phase kept the _rules_ and the
  _query applications_ in separate files (`ref-*.l4` and `apply-*.l4`) and only the rules were
  deposited. That is a real gap in the deposit, not a floor dodge — **p6-tests reports DEGRADED on a
  zero-assertion module set whatever the floor says**, by design, because "no failed assertion" over
  an empty `results[]` is vacuous and this stage's PASS claims that something ran and agreed. Pin the
  floor upward the moment that arm gains assertions.
- Floors travel **with** their encoding, structurally: the committed floor sits at
  `checks.min_assertions` and the deposit's inside `encodings.guarded-2026-08.checks`, so neither can
  ever be applied to the other.

### Legs

Declared: **p7-tnr** (real differential oracle — `l4 nlg` regenerates
`jl4/examples/canon/us/chubb-hospital-cash/blind-inert/tests/chubb.nlg.golden` and the leg diffs it), **p7-akn** (an EXTRA leg;
well-formedness is its only oracle, so it cannot raise the run verdict), **p7-mcp** (each module
carries exactly one `@export`, so there is a deployable surface; with no `JL4_GO_SERVICE_URL` the leg
SKIPs and still records the zip).

Not declared, and each for a stated reason:

- **p7-bpmn and p7-lts — the corpus is entirely constitutive.** It decides whether a claim survives
  every operative condition and exclusion; it obliges nobody to do anything. Neither module contains
  a `MUST`, `MAY` or `SHANT`, and `l4 export … --to bpmn` answers _"No regulative rules found in
  module"_ for both. There is no process to draw and no transition system to walk.
  (`sg-succession` declares `p7-lts` on the same facts and rides its permanent NOT-BUILT; this
  subject omits it instead, because a leg guaranteed to report a blocker on every run is noise
  rather than measurement. If §3.2.1's arbitration limb is ever re-encoded as a regulative rule — it
  is the one clause in the fixture that reads like one — declare both legs in the same change, and
  update `pins.json`'s empty `regulative_rules` in the same edit.)
- **p7-wizard** — there is no wizard module and the leg renders one.
- **p7-dmn, p7-dmn-md, p7-ladder** — each requires committed goldens or an npm demo entry this
  subject does not have.

### `known-defects.json` declares no group

Nothing has been measured. The only consumer is `p7-wizard`, which this subject does not declare.
An empty-but-present group would assert that some leg's controls are vacuous; no group is the honest
statement that no leg here consumes one.

### The NOT-precedence guard

`pins.json` lists `etc/check-not-precedence.mjs` under `checkers_that_must_exist`. It is a **standing
guard, not a stage dependency** — none of the three declared legs shells out to an `etc/` checker.
It is there because both modules lean hard on `NOT` (27 occurrences in `chubb.l4`, 19 in
`chubb-denovo.l4`) and **`NOT` binds looser than `AND` in this grammar**, a trap that produced a
wrong _legal_ answer in the sg-succession corpus rather than a type error. Measured 2026-08-31:
`node etc/check-not-precedence.mjs` over both modules reports `2 file(s) clean`.

### `--milestone` is retired

`etc/go/go.sh plan --milestone g1 --subject chubb` **exits 2 by design** (retired by
PIPELINE-ARTIFACT-MODEL-SPEC.md §3.9 — G0–G4 are capability milestones, not phases a body of law
passes through). The equivalents are:

```
etc/go/go.sh plan --subject chubb                             # the committed encoding
etc/go/go.sh plan --subject chubb --encoding guarded-2026-08  # the deposited arm
```

`node etc/go/lib/subject.mjs chubb --encodings` lists the declarable ids.

### Adding this subject changed `etc/go/selftest.mjs`, and why

`chubb` sorts before `regcf`, and the selftest's fixture subject was `SUBJECTS[0]` — the
alphabetically first sidecar. Its own comment claimed reading the resolver's `--list` kept the file
green "when a second subject lands"; it did, twice, by luck of sort order. This subject is the first
to sort ahead of `regcf`, and it is entirely constitutive: no `encoding.wizard`, no `explainer`, no
`p7-dmn` leg. The blocks that build cases by copying the fixture's descriptor and mutating one key
then went red describing keys their fixture did not have — **18 failures, and one TypeError that
crashed the run outright** rather than reporting `not ok`.

Two changes, both in `etc/go/selftest.mjs`, both stating the requirement instead of relying on sort
order:

1. `FIXTURE_SUBJECT` now selects the first sidecar declaring a wizard, an explainer directory and a
   `p7-dmn` leg, falling back to `SUBJECTS[0]`. Today that resolves to `regcf` — i.e. **exactly the
   value it had before this subject landed**, which is what makes the change a repair rather than a
   re-baselining.
2. The bad-golden refusal test injects its own `p7-dmn` leg instead of mutating one the fixture
   happens to declare. That check is about the resolver refusing a named-but-absent file, and needs
   no cooperation from the fixture at all.

Verified 2026-08-31 by removing this sidecar and reverting `selftest.mjs`: the baseline is
`selftest: 1 FAILED (1 skipped)`, and it is the same single failure
(`an UNDECLARED denovo assertion floor defaults to 0 with a toothless-guard note on the receipt`),
which is **pre-existing on this branch and unrelated to this subject**. With both changes in place
the count is identical.
