# Replicating Kant et al. 2025 with L4 as the target language

**Status as at 2026-08-31: foundation phase complete; the measurement is DESIGNED BUT NOT RUN.**
Everything below distinguishes what has been measured from what has only been specified. No claim
that L4 does better or worse than Prolog is made here, and §3 explains why the numbers we have
cannot support one yet.

Manuj Kant, Sareh Nabi, Manav Kant, Roland Scharrer, Megan Ma & Marzieh Nabi, _"Towards Robust Legal
Reasoning: Harnessing Logical LLMs in Law"_, arXiv:2502.17638 (2025) measured how accurately LLMs
translate a synthetic insurance policy into Prolog, scoring answers to nine claim queries against a
key the authors wrote themselves. This directory replicates that with **L4** as the target language,
and audits the benchmark while doing it.

---

## 1. What has actually been measured

Three L4 encodings of the policy were produced **blind**: three agents, three house styles, each
shown only the policy text — not the nine queries, not the answer key, not each other's work. The
queries were mapped onto each encoding afterwards by a different agent, also blind to the key.

```
$ node bench/bench.mjs aggregate out/ref-inert.json out/ref-record.json out/ref-guarded.json

| arm | n | Q1  | Q2  | Q3  | Q4  | Q5  | Q6  | Q7  | Q8  | Q9  |
|-----|---|-----|-----|-----|-----|-----|-----|-----|-----|-----|
| l4  | 3 | 3/3 | 3/3 | 3/3 | 0/3 | 3/3 | 3/3 | 3/3 | 3/3 | 3/3 |

Key A (paper verbatim) 0.889, sd 0 · Key B mechanical 7/7 · conformance 9/9
```

**8 of 9, unanimous across all three styles, with the sole disagreement on Q4.** For comparison,
the figures the paper reports:

| condition                               | score       |
| --------------------------------------- | ----------- |
| vanilla LLM (5 models, flat)            | 0.78        |
| vanilla, DeepSeek-R1 / o1-preview       | 0.81 / 0.88 |
| unguided Prolog, best (o1-preview)      | 0.89 ± 0.02 |
| unguided Prolog, worst (Llama-3.1-405B) | 0.41 ± 0.04 |
| guided Prolog (GPT-4o, o1, o3-mini)     | 1.00        |

So: level with their best unguided cell, above every other model they report, below their guided
cell. **This is a dead heat, and §3 is the reason it cannot be read as more than that.**

## 2. What the original's methodology will not support

Four defects, each verifiable against the paper itself:

1. **No Chubb Prolog encoding is published anywhere.** Appendix A.3 gives prompts; the only Prolog
   code in the paper (A.4.1, A.4.2) is a fragment from the _other_ experiment, the ART/FSH coverage.
   Every §3.2 number — the whole 0.41-to-0.89 range — therefore rests on artifacts no reader can
   execute, re-score or check.
2. **Some of it was not executed by the authors either.** Their footnote 3: _"The generated encodings
   often failed to run on SWISH due to its ambiguity. In such cases, we manually reasoned through the
   policy encodings and evaluated the claims."_
3. **Only aggregates are reported.** "0.78, consistently" across five models cannot be resolved into
   _which two items_ moved.
4. **The best model's residual error is an artifact of the authors' own edit to the fixture.**
   o1-preview scores 0.89 and misses **Q5 in 9 of 10 trials**. The paper attributes this to failing
   to identify _"whether it was sickness or accidental injury, which are addressed indirectly in the
   contract."_ It is not indirect. In the unmodified Goodenough & Carlson original (PMC10894687,
   Appendix A), §2.1 is the operative insuring clause and says it outright: _"If you have been
   confined in a hospital as a result of sickness or accidental Injury, we will pay you the Daily
   Hospital Income Benefit…"_. **Kant et al. deleted §2** and then scored models down for not finding
   it. That one item is 11 accuracy points, and it is most of the gap their §5 reinforcement-learning
   proposal exists to close.

`source-defects.md` carries the full twenty-item defect register, with the five that change gold
answers identified.

## 3. Why our 0.889 is not yet a result

- **n = 1 trial per style.** They ran 10 trials per model. We have three styles × one trial. Our
  zero spread is across _styles_, not across resamples of one prompt, so it is not comparable to
  their SEM and must not be presented as if it were.
- **Three variables moved at once** — target language, encoder, and protocol. Nothing in the
  difference is attributable to L4.
- **Nine binary items resolve to ±11 points.** Their own reported SEM reaches ±0.18, a confidence
  interval nearly three items wide. Parity measured on a ruler this coarse is not a finding.

`FOUNDATION.md` §5.2 carries the eight named threats to validity (T1–T8), including one — T8 — that
two of our own auditors still disagree about, recorded unresolved.

## 4. The harness (this is what is new here)

`bench/bench.mjs` scores a trial in either language. It exists because of six requirements in
`FOUNDATION.md` §5.1; three of them are things the original did not do:

- **R1 — per-item, per-trial output.** The agreement matrix above is the primary artifact; aggregates
  are secondary. This is what lets "0.78, consistently" be resolved into _which items_.
- **R2 — dual scoring, always both.** _Key A_ is the paper's key verbatim, for comparability.
  _Key B_ separates the **7 mechanical items** from the **2 interpretive** ones (Q4 is
  under-determined by its own query; Q5's gold turns on the deleted §2), and reports the interpretive
  figure as **agreement with an annotator, not correctness**. Reporting B alone would be marking our
  own homework; reporting A alone is the inverted-objective problem of `FOUNDATION.md` §1.5.
- **R5 — both arms execute, and non-conformance is data.** A trial whose encoding does not load, or
  does not expose the nine queries, scores as failure. It is never hand-read into a better result.

Two implementation points that are load-bearing rather than incidental:

- **Questions are located by label, not by position.** `apply-guarded.l4` interleaves sensitivity
  probes `Q4b`, `Q5b`, `Q9b` between the numbered items, so "the first nine results" are _not_
  q1–q9. The regex `/\bq(\d+)\b/i` matches `Q4` and rejects `Q4b` and `S4` on the word boundary. A
  positional harness would silently mis-attribute three answers — the exact error class the original
  could not have caught, since it never published which item moved.
- **SWI-Prolog's `consult/1` is permissive.** A syntax error skips the offending clause, prints to
  stderr, and loading continues — so a half-parsed encoding will cheerfully answer some queries. The
  harness treats any consult diagnostic as a failed trial. This is precisely the situation the
  original's footnote 3 resolves by hand-reading; we resolve it by failing the trial, because
  scoring it would measure our charity rather than the model.

`bench/selftest/` holds three Prolog fixtures — clean, partial, and non-loading — that exercise those
paths. They are **harness fixtures, not results**; never aggregate them into a reported table.

```bash
node bench/bench.mjs trial --arm l4 --dir artifacts/encodings --apply apply-inert.l4 \
     --label ref-inert --lib "$PWD/../../jl4-core/libraries" --out out/ref-inert.json
node bench/bench.mjs trial --arm prolog --dir <trialdir>            # expects policy.pl + queries.pl
node bench/bench.mjs aggregate out/*.json
```

Both interpreters are present on the development machine (`l4`; SWI-Prolog 9.2.9), so R5 is
satisfiable — which is what removes the original's worst methodological flaw rather than inheriting
it.

## 5. The measurement: k = 10 per cell, pooled with the pilot

`FOUNDATION.md` §5.1 specifies a **2 × 3 factorial** — {Prolog, L4} × {vanilla, unguided, guided} —
with model family held fixed so that target language is the independent variable rather than model
identity. Five cells are distinct, since the vanilla condition involves no encoding and is shared.

**The full run completed on 2026-09-01**: n = 10 per cell, matching the original paper's ten
trials per configuration. Trials t1/t2 are the 2026-08-31 k = 2 pilot; t3–t10 are the top-up
(`bench/setup-k10.sh`), pooled per §5.2 — the only staged input that changed between the two was
the syntactic schema repair. All trials blind by construction (no sandbox contains the key), all
scored by re-executing artifacts (`bench/score-k10.sh`), which also re-verified the pilot numbers
from scratch. One harness repair is on the record: two prolog-guided encoder agents (t3, t6 of
the top-up wave) died on API timeouts having written **zero bytes**, and were relaunched into
their pristine sandboxes under identical conditions. An agent crash with no partial output is an
infrastructure failure, not a measurement, so this is a repair, not a resample.

| cell            | n   | Key A mean | sd    | min   | max   | Q5    | Q4    | mechanical  |
| --------------- | --- | ---------- | ----- | ----- | ----- | ----- | ----- | ----------- |
| vanilla         | 10  | 0.900      | 0.035 | 0.889 | 1.000 | 1/10  | 10/10 | 70/70       |
| prolog-unguided | 10  | 0.922      | 0.054 | 0.889 | 1.000 | 3/10  | 10/10 | 70/70       |
| prolog-guided   | 10  | 0.945      | 0.059 | 0.889 | 1.000 | 6/10  | 9/10  | 70/70       |
| l4-unguided     | 10  | 0.911      | 0.047 | 0.889 | 1.000 | 2/10  | 10/10 | 70/70       |
| l4-guided       | 10  | **0.967**  | 0.054 | 0.889 | 1.000 | 7/10  | 10/10 | 70/70       |

**450 of 450 mechanical items correct, across all fifty trials.** Every point of variance in the
whole arm sits on the two pre-registered interpretive items: Q5 (49 of the 50 trials' misses) and
one Q4 miss. Conformance: every encoding loaded or typechecked, every trial exposed nine queries;
the single dent is `vanilla/t10` answering "I do not know" on Q5 — a permitted, principled
abstention ("the contract never defines accidental Injury and no exclusion covers self-inflicted
acts"), scored as a miss under Key A and reported as what it is.

Three readings, in decreasing order of what the data supports:

1. **The guided/unguided/vanilla ordering is real and monotone in both languages** (guided
   0.945/0.967 > unguided 0.922/0.911 > vanilla 0.900), and it is carried entirely by Q5:
   the schema roughly triples Q5 gold-agreement (13/20 guided vs 5/20 unguided vs 1/10 vanilla).
   What the schema buys is a **place to put the judgement** — a typed `Ground` field — not the
   judgement itself: even guided, 7 of 20 trials marshalled the self-punch as `Accidental injury`
   and missed.
2. **The one Q4 miss is the under-determination doing exactly what §T8-style analysis predicts.**
   `prolog-guided/t5` pinned Q4's unstated hospitalization month at 3 "to isolate the late
   confirmation as the only operative fact"; its still-pending logic then, correctly on its own
   reading, answered Yes. Ten other trials pinned the month late (pluperfect reading) and matched
   the key. The key's own entry calls Q4 under-determined; the variance agrees.
3. **No language claim.** l4-guided 0.967 versus prolog-guided 0.945 is one trial's Q5
   marshalling flip at sd ≈ 0.05; treating it as "L4 beats Prolog" would be exactly the
   over-reading this study exists to refuse. The honest sentence is: on this benchmark, with this
   model family, the two languages are indistinguishable, the treatment that moves the number is
   the **schema**, and the number it moves is one open-textured item.

Against the original's own figures (vanilla 0.78 flat across five vendors; unguided Prolog
0.41–0.89; guided Prolog 1.00 for three models): our vanilla beats their best vanilla by 12
points, our unguided cells sit above their unguided ceiling, and our guided cells do **not**
reach their 1.00 — because we score marshalling honestly instead of hand-reading near-miss
encodings as correct (their footnote 3), and because Q5's gold is not derivable from the fixture
they shipped (`source-defects.md`; the repaired-benchmark arm in `bench/PREREGISTRATION-restored.md`
measures what happens when it is).

One further limitation discovered mid-run and held constant across the whole arm:
`FOUNDATION.md` **T9** — the orchestration harness's own memory index carried result-adjacent
content into nominally blind sandboxes until it was sanitized after the last as-published launch.
Two trials disclosed seeing it; both answered against its direction; the unguided cells split on
Q5 rather than converging. It is a limitation to report, not an invalidation, and the restored
arm runs without it.

### 5.1 Why Q5 moves — and what two successive n=1 corrections taught

All ten trials, per item (`.` = agrees with the key, `X` = does not):

```
l4-guided/t1         .........  1.000      prolog-guided/t1     .........  1.000
l4-guided/t2         .........  1.000      prolog-guided/t2     ....X....  0.889
l4-unguided/t1,t2    ....X....  0.889      prolog-unguided/t1,t2 ....X.... 0.889
vanilla/t1,t2        ....X....  0.889
```

guided: n=4, mean 0.972 · everything else: n=6, all exactly 0.889 · **every trial 7/7 mechanical**.

The whole run turns on **one fact-supply decision**, and the rules are not where it lives:

| trial                | ground field in the encoding?   | q5 marshalled as    | Q5  |
| -------------------- | ------------------------------- | ------------------- | --- |
| `l4-guided/t1`, `t2` | yes                             | `Neither`           | ✓   |
| `prolog-guided/t1`   | yes                             | `neither`           | ✓   |
| `prolog-guided/t2`   | yes — a conjunct of `covered/1` | `accidental_injury` | ✗   |
| all four unguided    | **no such field at all**        | —                   | ✗   |

So: the guided vocabulary is **necessary** — 6 of 6 non-guided trials fail Q5, and not one of them
even builds the field — and **not sufficient**: `prolog-guided/t2` had the field, made it a genuine
coverage condition, and classified the self-punch the other way. The split is _within_ the
guided-Prolog cell, not between the languages.

**This section was rewritten twice from n=1 evidence, and that is the pilot's own lesson.** The
first reading said the guided cells reach 1.000 _because_ of the vocabulary; `prolog-guided/t2`
arrived and looked like a refutation; `prolog-guided/t1` arrived and made the refutation itself an
over-read. At k=2 a single trial is 50% of a cell. Nothing here is a result — it is a conformance
check that happened to expose a mechanism.

**The mechanism is open texture, relocated rather than removed.** Q5 asks whether "punching my own
face to show off for my friends" is an _accidental injury_. That is the penumbra of a term with a
real doctrinal split — accidental **means** versus accidental **results**, litigated at least since
_Landress v. Phoenix Mutual_ (1934). The `vanilla/t1` trial reached for exactly that distinction
unprompted and blind: _"the usual insurance-law reading that looks at whether the result (getting
hurt) was intended, not just whether the underlying act (throwing the punch) was voluntary."_

Formalising does not settle it. A typed field `hospitalization_ground: sickness |
accidental_injury | neither` converts an open-textured judgement into an _input_. What that buys is
not determinacy but **localisation** — the discretion becomes a line you can point at:

```prolog
prolog-guided/t2:  claim_hospitalization_ground(c5, accidental_injury).
prolog-guided/t1:  claim_hospitalization_ground(c5, neither).
```

One line, one judgement, one score point, two encoders with identical information. In prose the
judgement is not locatable at all — which is how a paper can delete the clause that framed it and
then score models down for failing to find it.

Two things must stay separated here. The excision of §2 is a **defect** of the fixture and is
repairable. The open texture in "accidental injury" is **not**: restore §2 and Q5 is still
penumbral, merely penumbral with a clause to hang the judgement on. The deletion does not create
the indeterminacy; it removes the text that would have framed it.

Note also the classification was **pre-registered** — all nine items were marked mechanical or
interpretive in `bench/keys.json` before any trial ran. The data then separated along that line
exactly: 7/7 core for every method in both languages, all variance on the two penumbral items.

### 5.1.1 Localisation is not awareness — the caveat that matters most

`prolog-guided/t1` scored 1.000. Its `NOTES.md` documents **nine** judgement calls — §1.3's timing
anchor, the premium deadline, the age exclusion being free-standing rather than a fifth "arising out
of" cause, Q9's occupation-versus-causation split, Q4's unstated hospitalization month, the
60-day rule, the wellness-visit/confirmation mapping. It does **not mention Q5 at all.** The one
call that took it from 8/9 to 9/9 — classifying a deliberate self-punch as `neither` — went
unrecorded, while eight less consequential decisions were written up.

Mentions of that judgement across the four guided trials: `prolog-guided/t1` **0**,
`prolog-guided/t2` 1, `l4-guided/t1` 2, `l4-guided/t2` 5. (Four trials: an observation, not a
trend, and certainly not a correlation with score.)

So the localisation claim above needs narrowing, and it is the narrowing that matters. Formalisation
makes the discretion **locatable in the artifact** — `claim_hospitalization_ground(c5, neither)` is
right there, greppable, diffable against another trial's `accidental_injury`. It does **not** make
the encoder aware they exercised discretion, and it does not capture their reasons. The line is
there to be pointed at; the argument for it may never have existed.

That is a direct warning about the explainable-AI pitch that motivates this whole line of work. An
execution trace shows _what_ was decided and _which rule fired_. It does not show that anyone
noticed a decision was being made, still less why. On a penumbral term those are the questions, and
a trace answers neither. Recovering them needs something the trace does not carry — which is
precisely the argument for a fork register, and for HG1 being a human reading the encoding against
the source rather than a machine checking it against a key.

### 5.1.1 What this does to the paper's RL proposal

Kant et al.'s §5 proposes reinforcement learning on a correctness reward. On a penumbral item the
reward is agreement with an annotator, so the gradient points at predicting that annotator's
discretion rather than at applying the law — and on this benchmark 2 of 9 items, 22% of the
available score, are of that kind.

### 5.2 A harness bug in the L4 schema, and why it does not qualify the result

`schema-l4.md` **did not compile** when it was shipped to the `l4-guided` trials. Multi-word record
fields need backticks, and the `arose out of` helper was written ``c `elem` cs`` when L4 has no
backtick-infix calling convention — it parses as applying `c` to two arguments, and `elem` was never
mixfix-registered in the prelude. Both trials found and repaired it independently and said so in
their `NOTES.md`. `schema-prolog.md` loaded cleanly.

**This is a bug in our scaffolding, not a confound in the experiment**, for three reasons, and the
section is kept only so a later reader does not have to re-derive them:

1. **The bias runs against L4, and L4 hit the ceiling anyway.** Both `l4-guided` trials scored
   1.000 after paying a repair cost the Prolog cell did not. A handicap the handicapped arm
   overcomes is not an alternative explanation for its score. Had `l4-guided` come in _below_
   `prolog-guided`, this would be a live confound and the cell would need re-running.
2. **The surviving finding lives entirely inside the Prolog guided cell.** §5.1's conclusion — the
   guided vocabulary is necessary and not sufficient — rests on `prolog-guided/t2` marshalling
   `accidental_injury` where `t1` marshalled `neither`. Both had a clean schema. The bug touches
   neither side of the comparison that carries the result.
3. **The repair was syntactic, not semantic.** Same eighteen fields, same order, same helper
   meanings; backticks and one helper body. A k = 10 run on the repaired schema is measuring the
   same treatment, so these two trials pool with it — with a footnote that they did strictly more
   work for the same score, not less.

An earlier draft of this section called it an R4 violation and said the guided-L4 numbers were not
poolable. Both were over-stated and are withdrawn here rather than silently edited away.

What the episode _does_ justify is the fix already made: `bench/check-schema-parity.mjs` now
**compiles both schemas** — `l4 check` on the L4 blocks, `swipl` on the Prolog helpers — as well as
comparing field set and order, with a negative test. Comparing names passed and was useless. And
there is a modest point in the toolchain's favour buried in it: the type checker rejected our
mistake immediately and said what was wrong, which is why two encoders working blind both recovered
without ever asking anyone.

## 6. What would make this worth publishing

Explicitly **not** "L4 scored higher than Prolog on nine questions" — T1 and T2 make that number
close to meaningless, and the write-up should say so rather than let a reader infer it. The
defensible contributions are an **audited answer key** (nine labels with their competing readings and
the clause each turns on), a **defect inventory for a fixture other people are already citing**,
**clause coverage as a metric alongside accuracy** — motivated by a demonstrated case where three
independent encodings share a confirmed bug that the benchmark scores as 8/9 — and a concrete account
of what the target language buys, **with its honest counterweight** that the benchmark's own
relative-time convention removes the type safety producing one of those wins.

## 7. Artifacts

| path                        | what it is                                                                                                                               |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `FOUNDATION.md`             | the foundation-phase report: gold-standard provenance, the Q4/Q5 audits, what L4 can and cannot express here, the design and its threats |
| `source-defects.md`         | the twenty-item defect register for the fixture                                                                                          |
| `l4-probe.md`               | language probes run while encoding                                                                                                       |
| `fixtures/chubb-policy.txt` | the policy text as printed at arXiv:2502.17638 A.1                                                                                       |
| `fixtures/queries.json`     | the nine queries, the paper's key, and the paper's reported results                                                                      |
| `bench/`                    | the scoring harness, its dual key, and its self-test fixtures                                                                            |
| `artifacts/encodings/`      | **frozen** as-produced blind artifacts — see the note below                                                                              |
| `artifacts/A3*.txt`         | the paper's own prompts, transcribed from Appendix A.3                                                                                   |

**`artifacts/encodings/` is an experimental record and is deliberately frozen.** `ref-inert.l4` is
the ancestor of the maintained corpus module at `jl4/examples/legal/chubb/chubb.l4`, and
`ref-guarded.l4` of `jl4/examples/legal/chubb/denovo/chubb-denovo.l4`. **Those corpus copies are
canonical and are the ones `jl4-test` defends**; these are kept unchanged because a blind artifact
that gets maintained is no longer a blind artifact. `ref-record.l4` has no corpus copy — the
third-ranked arm was not deposited.

The policy text originates in Goodenough & Carlson (2024), PMC10894687, **CC BY 4.0** — attribution
is a licence condition. See `subjects/us/chubb-hospital-cash/` in `legalese/canon` and that repo's
`NOTICE`.
