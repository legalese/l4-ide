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

## 5. The measurement: pilot run, k = 2

`FOUNDATION.md` §5.1 specifies a **2 × 3 factorial** — {Prolog, L4} × {vanilla, unguided, guided} —
with model family held fixed so that target language is the independent variable rather than model
identity. Five cells are distinct, since the vanilla condition involves no encoding and is shared.

**A k = 2 pilot ran on 2026-08-31**, one model family throughout, trials blind by construction
(`bench/setup-pilot.sh` stages a sandbox per trial; the key is never copied in). The full k = 10
run specified in §5.1 has **not** been run.

| cell            | n   | Key A            | mechanical | missed |
| --------------- | --- | ---------------- | ---------- | ------ |
| vanilla         | 2   | 0.889, 0.889     | 7/7        | Q5     |
| prolog-unguided | 2   | 0.889, 0.889     | 7/7        | Q5     |
| l4-unguided     | 2   | 0.889, 0.889     | 7/7        | Q5     |
| l4-guided       | 2   | **1.000, 1.000** | 7/7        | —      |
| prolog-guided   | 1   | 0.889            | 7/7        | Q5     |

Conformance was 9/9 on every finished trial: every encoding loaded, and every trial exposed the
nine queries in the required shape. That was the question the pilot existed to answer before
committing to k = 10.

**Every trial scored 7/7 on the mechanical items.** All variance in the entire run sits on the two
interpretive ones — which is what the graded key was built to expose, and it means the benchmark's
headline differences between methods are differences about two contested items, not about legal
reasoning.

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

### 5.1.1 What this does to the paper's RL proposal

Kant et al.'s §5 proposes reinforcement learning on a correctness reward. On a penumbral item the
reward is agreement with an annotator, so the gradient points at predicting that annotator's
discretion rather than at applying the law — and on this benchmark 2 of 9 items, 22% of the
available score, are of that kind.

### 5.2 A defect in this pilot: the two guided cells were NOT equivalently guided

`schema-l4.md` **did not compile** when it was shipped to the `l4-guided` trials. Multi-word record
fields need backticks, and the `arose out of` helper was written ``c `elem` cs`` when L4 has no
backtick-infix calling convention — it parses as applying `c` to two arguments, and `elem` was
never mixfix-registered in the prelude. Both trials found and repaired this independently and
recorded it in their `NOTES.md`. `schema-prolog.md` loaded cleanly.

So the L4 guided encoders had to debug the vocabulary before they could use it, and the Prolog ones
did not — **an R4 violation, in the one place a field-name comparison could not see it.** The bias
runs _against_ the L4 cell, so the 9/9 is not flattered by it; that does not make the run clean.
Both defects are fixed, and `bench/check-schema-parity.mjs` now **compiles both schemas** as well as
comparing their field sets and order, with a negative test. Any k = 10 run should re-stage from the
repaired schema, and its guided-L4 numbers are not poolable with this pilot's.

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
