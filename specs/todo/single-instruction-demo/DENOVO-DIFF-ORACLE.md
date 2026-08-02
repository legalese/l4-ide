# The de novo diff oracle — SPEC.md §8's acceptance comparator

**Status (2026-08-02): BUILT, not yet exercised by a real G2 run.** `etc/go/lib/denovo-diff.mjs`
runs today and both of its self-tests are measured below (§7). What it has never seen is a second
encoding: every measurement here is the committed Reg CF corpus against itself, or against a
scratch copy of itself with one constant moved. **No pipeline stage calls it.** `p3-encode` and
`p4-forks` stopped refusing on 2026-08-03 (`ORCHESTRATOR.md` §5.2), but what they do is VALIDATE a
deposit an agent produced — they still do not produce the de novo module this oracle exists to
compare, and invoking the oracle stays the agent's act (SKILL.md's G2 runbook). Where this document disagrees with the tree, the tree wins.

What that means for SPEC.md §6's milestone list: G2's entry condition was "R4 ruled" (satisfied
2026-08-02) and its acceptance is "the §8 diff oracle". The oracle now exists, and the P1–P5
stages now have an acceptance condition each — but nothing in the pipeline WRITES a de novo
encoding, so the oracle still has nothing of its own to compare.

---

## 1. What §8 asks for, and what a script can honestly do about it

SPEC.md §8, in full:

> The de novo run (G2) re-derives Reg CF from source **without reading the existing corpus**, then
> diffs its encoding against `jl4/examples/legal/regcf/regcf.l4`:
>
> - **Agreements** validate both encodings.
> - **Disagreements** are triaged: encoding error (fix), genuine ambiguity (both readings join the
>   fork register), or improvement over the hand corpus (backport).
> - The triage table goes into the conversion report. A de novo run that merely reproduces the
>   corpus is a pass; one that finds a defect in it is a better pass.

Split along the boundary in `ORCHESTRATOR.md` §2.1 — scripts own facts, the skill owns judgement —
that is two jobs, and only one of them is mechanisable:

| §8 clause                   | who                                                                                                            |
| --------------------------- | -------------------------------------------------------------------------------------------------------------- |
| find the agreements         | **the script.** An agreement is a measured equality of two answers over one fact pattern                       |
| find the disagreements      | **the script**, with a minimised witness for each                                                              |
| triage each one, three ways | **the skill / the reviewer.** "Encoding error" vs "genuine ambiguity" vs "improvement" is a reading of the law |
| put the table in the report | the script emits the table; every disposition reads `UNTRIAGED` until a human or the skill writes one          |

So `denovo-diff.mjs` **never triages**, and the selftest asserts that the three SPEC §8 disposition
strings never appear as values the comparator writes. A script that guessed "this one is a genuine
ambiguity" would be doing the exact thing this orchestrator was built not to do.

---

## 2. Behavioural first, textual second

The obvious implementation — diff the two `.l4` files — answers a question nobody asked. Two
encodings of one statute, written months apart by different agents under an inert-style brief,
share almost no identifiers, no record shapes, no section ordering, and (per R4) not even the same
parameter lists: the de novo side threads an `Interpretation` record that the corpus does not have.
A textual diff over that is 100% different and 0% informative.

What they must share, if they are both encodings of the same law, is **what they answer**. So the
comparator's spine is:

```
declared pairing  →  shared fact battery  →  pairwise evaluation  →  answer comparison
  (surface map)       (cases + mutations)      (generated probes)      (+ minimisation)
```

Textual comparison is not attempted at all. The one place structure is read is the surface
enumeration (§3), and it is read out of the CLI, not out of the source text.

---

## 3. Surface enumeration: what the CLI will tell you, and what it will not

Following `lib/discover.mjs`'s stance — pins are discovery calls, not transcribed lists — every
fact the oracle knows about a module is read back from the `l4` binary.

**What works.** `l4 render FILE --format json --include-unused` reports, for every non-imported
declaration, its `kind` (`rule` / `type`), its `heading`, and for record types the labels of its
fields. That gives two things at once: the **decision surface** (every rule heading a pair may
name — 100 of them for `regcf.l4`) and the **type dictionary** the battery adapter needs (§4).
A `call` in the surface map that is not in that list is a hard error naming the nearest matches;
it cannot be a silent no-op.

**What does not.** There is no CLI route that _enumerates_ `@export` entrypoints. `l4 batch` with
an unknown `-e` answers `no @export function named '…' found` without listing the alternatives, and
the render JSON does not mark exportedness at all. So the oracle probes exportedness one name at a
time (`l4 batch … --validate-only` against an empty row; entrypoint resolution happens strictly
before row validation, so the answer is unambiguous) and reports the count in the "Surfaces" table
as **advisory**. It never licenses or withholds an agreement — a de novo encoding is not less
comparable for having no deployable façade. `regcf.l4` has zero `@export`; the wizard façade has
six.

### 3.1 The declared correspondence

The pairing itself is not inferrable and is not inferred. It is a file — schema at
`specs/todo/single-instruction-demo/schemas/surface-map.schema.json`, the sibling of the three
deposit-contract schemas P1/P2/P4 write into — that the G2 run deposits. Three moving parts:

- **`sides`** — two modules, each with the IANA timezone the probe must declare (`TIMEZONE` is
  per-document and is _not_ inherited through `IMPORT`, so an unpinned `RULES EFFECTIVE DATE` read
  inside the module dies at evaluation without one).
- **`slots`** — the shared fact vocabulary. A slot is one argument's worth of facts, named once and
  referenced by both sides. It carries each side's L4 **type name** for that argument and, on the
  de novo side, a `rename` map from the battery's field names to that module's. This is the whole
  answer to "how do you compare two encodings that name nothing the same way": you declare the
  correspondence, and the oracle's job is to disagree with your declaration behaviourally.
- **`pairs`** — one entry per compared decision: each side's call name, its argument slots in
  order, an optional `field` to project out of a record-shaped result, an optional `rule_date`,
  an optional `citation`, and an optional `fork` id cross-linking a fork-register entry.

Arity may differ between the sides. That is deliberate: R4's `Interpretation` parameter exists on
one side only, and the two encodings are still required to agree on the answer.

The schema is `additionalProperties: false` throughout, matching `lib/subject.mjs` and the register
schemas. The validator (`validateAgainstSchema`, exported from `denovo-diff.mjs`) reads the schema
file rather than re-stating it, and refuses outright — exit 4 — a schema using a keyword it does
not implement, because a keyword that is parsed and not enforced is a constraint that silently does
not exist. That is the same enforcement contract `register-validate.mjs` states in its own §3; the
two validators are separate because surface-map needs `oneOf`, `minProperties` and schema-valued
`additionalProperties` (its `slots` object is a map), which that validator's closed subset does not
have. Converging them is the obvious follow-up and is not done here.

---

## 4. The battery

SPEC.md §P6 asks for scenario tests that discriminate; §8 needs a fact set both encodings can be
run over. The oracle takes the subject's existing cases file as seed and generates the rest.

**Seeds.** `battery.cases` names a cases file with `{name, context}` entries — the intended value
is the subject sidecar's `legs['p7-dmn'].cases`, which for `regcf` is
`jl4/examples/dmn/regcf-corpus.cases.json`: 16 cases, the base world plus 15 relocation cases
carrying the rule-version boundaries (PR #194, DMN ruling R-C). That is already a boundary-biased,
human-curated seed set, and re-using it means the diff oracle and the DMN engine harness are
answering over the same worlds.

Its context keys are DMN-sanitised, so they must be mapped back onto L4 field labels. The oracle
does **not** invert the sanitiser (it is not invertible). It sanitises the _declared_ labels from
the type dictionary and matches forward; a case key with no match, or two labels colliding onto one
key, is a hard error. The rule — every run of non-alphanumerics becomes one underscore, ends
trimmed — was verified 2026-08-02 to map all nine record-shaped context entries of that file onto
declared corpus types with zero unmatched keys, and is pinned in the selftest against two of the
longest labels.

**Perturbations.** For each seed, one field at a time, boundary-biased:

- booleans flip;
- numbers get `±1` (a statutory threshold is crossed by one dollar, not by an order of magnitude),
  the multipliers `0 / ½ / 2`, and `-1`;
- ISO dates get `±1 day`;
- **cross-pollination**: every value that same leaf takes in some _other_ seed case, plus `±1`
  around each. The seed cases are where a human already wrote the regime boundaries down; this
  tries each of them everywhere rather than only where it was written;
- `slots.<n>.thresholds` is the manual escape hatch for a statutory boundary that appears in no
  case at all.

For `regcf` that is 16 seeds → 2,928 perturbations → 2,944 rows.

**One field at a time is not a convenience, it is the minimality argument.** A perturbation row
differs from its seed in exactly one leaf, so when the seed agreed and the perturbation diverges,
the witness _is_ minimal: there is no smaller change that reaches it. The selftest checks that
property structurally rather than trusting this paragraph.

**Relevance pruning.** A perturbation moves one slot; a pair that does not take that slot as an
argument cannot see it, because an L4 decision is a function of its arguments. Those evaluations
are provably equal to the seed's and are skipped — they would contribute agreement rows that mean
nothing and inflate the agreement rate. Seed rows are never pruned: every seed is evaluated against
every pair, so the baseline is complete. For `regcf` this takes 2,944 × 13 = 38,272 down to 6,800
evaluations per side, and the report states both numbers.

---

## 5. Evaluation: why not `l4 batch`, and the probe module

`l4 batch` is the obvious carrier and it does not work here, for two independent reasons, both
measured 2026-08-02 with the prebuilt binary:

1. **It requires `@export`.** `jl4/examples/legal/regcf/regcf.l4` declares none — deliberately;
   `regcf-wizard.l4`'s own header gives three reasons why the authoritative text should carry no
   presentation annotations. A comparator that could only compare exported surfaces could not
   compare the corpus at all.
2. **It re-emits the module and the re-emission does not re-parse.** `L4.Cli.Batch` runs
   `prettyLayout` over the directive-filtered AST (`jl4/app/L4/Cli/Batch.hs:206-207`) and appends
   its wrapper to _that_ text. On the Reg CF façade the result is
   `incorrect indentation (got 75, should be greater than 180)` at a line of the module it was
   handed — reported as a diagnostic about the user's own file. `l4 format` on the same file DOES
   round-trip (`l4 check` on the formatted output exits 0), so this is batch's pretty-layout path,
   not the formatter. Filed here as an observation; fixing it needs `cabal`, which this
   orchestrator never runs.

So the oracle borrows batch's _wrapper_ idea and drops its re-emission. Each side is staged into
its own scratch directory (the module plus every `.l4` beside it, so importer-relative resolution
works and the two sides cannot collide on a basename — a de novo Reg CF encoding is very likely
also called `regcf.l4`; `JL4_LIBRARY_PATH` is a single directory, not a list, so it stays pointed
at the stdlib). Into that directory the oracle writes a probe that **IMPORTs** the module under
test:

```
IMPORT prelude
IMPORT daydate
IMPORT regcf

TIMEZONE IS "America/New_York"

DECLARE `GoArgs 0` HAS
    a0 IS AN Offering

GIVEN jsn IS A STRING
GIVETH AN EITHER STRING `GoArgs 0`
`go decode 0` jsn MEANS JSONDECODE jsn

`go row 0` MEANS
    CONSIDER `go decode 0` "{\"a0\":{…}}"
        WHEN RIGHT args THEN JUST (`EVAL UNDER RULES EFFECTIVE AT` (Date 1 9 2016)
                                     (`offering is within the offering limit` (args's a0)))
        WHEN LEFT  e    THEN NOTHING

#EVAL `go row 0`
```

The module under test is copied, never rewritten, never formatted, never even opened by the script.
`l4 run --json` answers a whole chunk (400 rows by default) in one process; each result is mapped
back to its job by the line number in its `range`, so a directive that produces no result is a
missing answer rather than a silent off-by-one.

Three things in that shape are load-bearing and each was learned the hard way.

**The explicit `GIVETH AN EITHER STRING …` is not decoration.** `JSONDECODE` is driven by the
declared result type (`jl4-core/src/L4/EvaluateLazy/Machine.hs:2519`). Written without it —
decoding straight into the application site and letting inference pick the type — the decode
returns `NOTHING` at runtime and every answer silently becomes "no answer". This is also why the
surface map has to carry the L4 **type name** of each argument: it cannot be inferred, and it
cannot be read off the CLI. A wrong type name is loud (the probe fails `l4 check`, naming file and
line), which is the trade this design accepts.

**Where the rule-date wrapper goes decides whether it applies at all.** `EVAL UNDER RULES EFFECTIVE
AT` is dynamically scoped over evaluation, and a lazily-constructed value carries its payload out
of that scope. Written the natural way —

```
`EVAL UNDER RULES EFFECTIVE AT` (Date 1 9 2016)
    (CONSIDER … WHEN RIGHT args THEN JUST (f (args's a0)) …)
```

— the `JUST` is built inside the scope but `f (args's a0)` is a thunk forced after it closes, so
**the rule date is ignored and the answer is the one for the unpinned clock**. Nothing warns. This
was live in the first working build of the oracle, and it was caught only because self-test B's
divergences appeared at rule dates (2016-09-01, 2017-04-11, 2019-06-01) at which the moved 2021
constant cannot possibly be selected. Measured directly afterwards: over a $3,000,000 offering,
`offering is within the offering limit` under the 2016 regime answers `TRUE` in the broken shape
(the 2021 $5,000,000 limit) where the 2016 $1,000,000 limit makes it `FALSE`. So the wrapper goes
**inside** the `WHEN RIGHT` arm, around the application only — the shape `regcf.l4`'s own fixtures
use at lines 1137-1144 — and a selftest tripwire asserts the generated text still has it there. It
is worth flagging upstream in its own right: a dynamically-scoped evaluation modifier that a lazy
constructor can escape is a foot-gun for anyone writing `EVAL UNDER RULES EFFECTIVE AT` around a
`CONSIDER` or a record literal.

**Answers are compared as the compiler's own rendering.** `l4 run --json` renders values as text;
the probe's `JUST OF ` wrapper is stripped, an `error` result becomes a comparable `ERROR: …`
answer, and a bare `NOTHING` becomes `«row did not decode»` — which is a harness fact and is never
allowed to read as an answer.

---

## 6. What the oracle emits

Into `--out`: `denovo-diff.json` (the machine record), `denovo-diff.rows.json` (every evaluation),
and `denovo-diff.md` — the SPEC §8 triage table, ready to paste into the P9 conversion report:

- **Surfaces** — rules declared / paired / `@export` per side, i.e. the coverage the map achieved.
- **Battery** — seeds, perturbations, rows, and the pruned evaluation count with its justification.
- **Agreement** — per pair: evaluated / agreed / diverged, with the pair's statutory citation, and
  the two sensitivity columns below.
- **Sensitivity** — every (pair, fact leaf) the battery perturbed **without ever moving an answer**.
- **Triage table** — one row per minimised witness: the pair, the witness (mutated leaf, from → to,
  and the seed it hangs off), what each side said, how many other rows show the same divergence,
  the cross-linked fork id if any, and `UNTRIAGED`.
- **Limits** — §8 below, printed in every report, because a comparison that does not state its
  blind spots reads as a clean bill of health.

### 6.1 Sensitivity, and the false green that produced it

Added 2026-08-02 after an adversarial re-measure, and it is worth stating as a defect found rather
than a feature designed.

`total assets threshold` (`regcf.l4:213`) was moved 10,000,000 → 20,000,000 in a scratch copy. That
is a real change to the law on a live decision path — `ongoing reporting obligation may terminate`
reads it at line 671 — and the first build of the comparator answered:

```
denovo-diff: 6800 evaluation(s) over 2944 row(s) × 13 pair(s)
             6800 agreed · 0 diverged · 0 minimised witness(es)
$ echo $?
0
```

with the report printing "the de novo run reproduced the corpus over this battery". Every word of
that was true and the impression it left was false. The cause is in the rows: `status.total assets`
was perturbed **128 times** against that pair and not one perturbation moved either side's answer,
because every value the generator reaches (0, 2·5M, 5M±1, 10M, −5M — the seed's only value is
5,000,000) sits below both the old threshold and the new one. **Agreement over an input a decision
never responded to is an absence of measurement, not evidence**, and a report that does not
separate the two reads as a clean bill of health.

So the comparator now computes, per (pair, fact leaf), how many perturbations were evaluated and
how many moved an answer away from the seed's — counting a move on **either** side, which is the
conservative direction. A leaf with zero moves is **inert** for that pair over this battery. On the
same perturbed corpus the repaired oracle says:

```
             6800 agreed · 0 diverged · 0 minimised witness(es)
             25 of 64 (pair, fact) leaves inert — perturbed, never moved an answer
```

and the Sensitivity table names `reporting-may-terminate · status.total assets · 128 · 0` — the
exact surface where the moved constant lived. The identity run reports the same 25 inert leaves,
which is the point: inertness is a property of the battery, not of a difference between the sides.

Three deliberate non-decisions. It **does not touch the exit code** — §8's semantics are
agreement/divergence and an inert leaf is neither. It is **not a defect in either encoding** — the
four `transfer.is to …` carve-outs are inert because the only transfer seed sits outside the
restricted period, which makes them unreachable, which is a fact about the cases file. And it is
**not triage**: it says where a reader may not draw a conclusion, not what conclusion to draw. The
remedy when it fires is a seed case or a `slots.<n>.thresholds` entry at the boundary.

**Minimisation** groups divergences by (pair, mutated leaf, both answers) and elects one
representative — the one whose mutation moves the value least, so a threshold defect reports the row
closest to the threshold. A witness derived from an agreeing seed is labelled
`one-field-from-agreeing-seed`; a seed row that diverges on its own is labelled `whole-seed-row`
and is **not** claimed to be minimal, because there is no agreeing neighbour to shrink towards.

Exit codes: `0` total agreement · `1` at least one divergence — a **finding**, which under §8 is
the better outcome, not a failure · `2` usage or an invalid map · `4` BROKEN (a probe that will not
typecheck, a cases key that will not un-sanitise, an `l4 run` that answered nothing) — never a
finding about either encoding.

---

## 7. The self-tests, verbatim

Run 2026-08-02 in `l4wt/denovo-foundations` with the prebuilt binary at
`l4wt/go-orchestrator/dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4`,
`JL4_LIBRARY_PATH=<repo>/jl4-core/libraries`, clock pinned to the orchestrator's default
`2025-01-31T00:00:00Z`. **A and B were re-run from scratch by a second agent, and D and E are that
agent's own independent cases**; every block below is the current build's output, and the agreement
figures in A and B are identical to the ones the first build produced.

### A — identity: the corpus against itself

```
$ node etc/go/lib/denovo-diff.mjs run \
    --map specs/todo/single-instruction-demo/schemas/fixtures/regcf-identity.surface-map.json \
    --out /tmp/dd-idB
denovo-diff: 6800 evaluation(s) over 2944 row(s) × 13 pair(s)
             6800 agreed · 0 diverged · 0 minimised witness(es)
             25 of 64 (pair, fact) leaves inert — perturbed, never moved an answer
             /tmp/dd-idB/denovo-diff.json
             /tmp/dd-idB/denovo-diff.md
$ echo $?
0
```

### B — one threshold moved

`jl4/examples/legal/regcf/*.l4` copied to `/tmp/dd-perturbed-src/`, and in the copy exactly one
line changed — `regcf.l4:139`, the 2021 arm of `offering maximum in a 12-month period`:

```
-    BRANCH IF `the rules in force include` `the 2021 amendments`           THEN 5000000
+    BRANCH IF `the rules in force include` `the 2021 amendments`           THEN 4000000
```

The map is the identity map with `sides.right.module` repointed at the copy.

```
$ node etc/go/lib/denovo-diff.mjs run --map /tmp/adv/map-b.json --out /tmp/dd-bB
denovo-diff: 6800 evaluation(s) over 2944 row(s) × 13 pair(s)
             6779 agreed · 21 diverged · 2 minimised witness(es)
             25 of 64 (pair, fact) leaves inert — perturbed, never moved an answer
             /tmp/dd-bB/denovo-diff.json
             /tmp/dd-bB/denovo-diff.md
  DIVERGE offering-within-limit  offering.maximum offering amount the issuer will accept 3000000→4999999
          corpus: TRUE
          perturbed corpus: FALSE
  DIVERGE offering-within-limit  offering.aggregate amount sold in reliance on section 4(a)(6) during the preceding 12 months 0→1234999
          corpus: TRUE
          perturbed corpus: FALSE
$ echo $?
1
```

The acceptance bar was "catch it, with a minimised witness naming the divergent decision and both
values, and report divergence nowhere else". All three hold, and two further properties are worth
recording because they are what makes the result more than a coincidence:

- **Exactly one of the thirteen pairs diverges** — `offering-within-limit`, 21 of its 823
  evaluations. The other twelve are 0/0/0, including `aggregate-offering-amount`, which reads the
  same `offering` slot and the same two fields but not the moved constant.
- **Only at rule dates in the moved regime.** Every one of the 21 divergences carries a rule date
  of 2021-06-01, 2022-06-01 or 2023-06-01 — on or after the 2021-03-15 amendment. The 2016, 2017
  and 2019 relocation cases agree, which is the positive evidence that `EVAL UNDER RULES EFFECTIVE
AT` is reaching the module (before the §5 fix, those dates diverged too, and that is how the
  defect was found).
- **Every witness value lands in the interval the edit opened** — `(4,000,000, 5,000,000]` once the
  seed's own prior sales are added in.

### C — the selftest block

`node etc/go/selftest.mjs` gains **30** checks in a marked block. They cover the schema validator's
redness (five refusals, each naming its rule), the sanitiser pin, the perturbation generator, the
one-field minimality property, relevance pruning, the rule-date tripwire, answer canonicalisation,
witness grouping, the never-triages property, the sensitivity accounting of §6.1, and a small
end-to-end identity run gated on `$L4` (skipped with a named reason when absent). All 30 pass; the
rule-date tripwire was separately shown to go red against a deliberately-broken generator.

### D — a second, independently chosen constant

A different reviewer, a different edit: `regcf.l4:238`,
`` `days in the resale restricted period` MEANS 365 `` → `200`, which two pairs read
(`transfer is within the one-year restricted period` at line 736, and `transfer is permitted`
through it).

```
$ node etc/go/lib/denovo-diff.mjs run --map /tmp/adv/map-p1.json --out /tmp/dd-p1b
denovo-diff: 6800 evaluation(s) over 2944 row(s) × 13 pair(s)
             6704 agreed · 96 diverged · 2 minimised witness(es)
             25 of 64 (pair, fact) leaves inert — perturbed, never moved an answer
             /tmp/dd-p1b/denovo-diff.json
             /tmp/dd-p1b/denovo-diff.md
  DIVERGE restricted-period  transfer.days since the securities were issued 400→364
          corpus: TRUE
          perturbed p1: FALSE
  DIVERGE transfer-permitted  transfer.days since the securities were issued 400→364
          corpus: FALSE
          perturbed p1: TRUE
$ echo $?
1
```

Three things this adds to B. The witness is in the interval the edit opened (`[200, 365)`) and is
the **closest** such value to the seed's 400 that the generator reaches, so minimisation is electing
what it claims to. The two divergent pairs are exactly the two that read the constant, and the
other eleven are 0/0/0 — localisation reproduced on a different edit. And the two answers are
**opposite** (`TRUE`/`FALSE` on one pair, `FALSE`/`TRUE` on the other), which is right: shortening
the restricted period makes a transfer at 364 days no longer restricted and therefore permitted.

### E — the false green, before and after §6.1

The adversarial case that produced the sensitivity accounting: `regcf.l4:213`,
`` `total assets threshold` MEANS 10000000 `` → `20000000`, which `reporting-may-terminate` reads at
line 671. Before §6.1 this answered `6800 agreed · 0 diverged`, exit 0, with no qualification.
After:

```
$ node etc/go/lib/denovo-diff.mjs run --map /tmp/adv/map-p2.json --out /tmp/dd-p2b
denovo-diff: 6800 evaluation(s) over 2944 row(s) × 13 pair(s)
             6800 agreed · 0 diverged · 0 minimised witness(es)
             25 of 64 (pair, fact) leaves inert — perturbed, never moved an answer
$ echo $?
0
```

The exit code is unchanged and should be: nothing diverged. What changed is that the report's
Sensitivity table now carries the row `reporting-may-terminate · status.total assets · 128 · 0`,
and the triage paragraph says in so many words that on 25 of 64 leaves "the battery measured
nothing and the agreement is silence rather than evidence". The 25/64 figure is identical in A, B
and E — inertness is a property of the battery, not of a difference between the sides, which is the
check that it is measuring what it says.

---

## 8. Limits — stated here and printed in every report

- **Only the pairs the map declares.** The Reg CF identity fixture pairs 13 of the corpus's 100
  declared rules. A decision present in one encoding and absent from the other is invisible unless
  somebody writes the pair down.
- **Decisions only. The deontic layer is not exercised.** This is the largest blind spot and it is
  structural, not an oversight: the battery evaluates `DECIDE`/`MEANS` functions, and a regulative
  rule has no answer this comparator reads. Two encodings could differ on who owes what, by when,
  and with what consequence on breach — `regcf.l4`'s three `DEONTIC Actor Action` rules —
  and every row would still agree. The BPMN and LTS legs are where that divergence would show;
  wiring them into the diff is not built and is the natural next piece of work.
- **Answer equality is equality of the compiler's rendering.** Two answers that mean the same thing
  but render differently read as a divergence, and a human triages them away. The `field`
  projection exists to narrow the comparison when that noise dominates.
- **Both sides erroring identically counts as agreement.** Right for a curated refusal (Reg CF
  pre-commencement dates), wrong if both encodings are broken the same way.
- **Perturbation is single-field.** Interaction defects needing two fields to move together are out
  of reach. This is a search of a neighbourhood around the seed cases, not of the input space.
- **A leaf the battery never made a decision respond to is visited, not compared.** The generator
  reaches only the values it can derive from the seed cases; a statutory boundary outside all of
  them is never crossed, and both encodings then answer identically on the near side whatever they
  say on the far side. This is §6.1, and the Sensitivity table is that blind spot enumerated rather
  than described — 25 of 64 (pair, fact) leaves on the Reg CF identity fixture.
- **List-valued facts are not perturbed**, and **enum-typed input fields cannot be fed at all**:
  `JSONDECODE` delivers a constructor name as a string, so a `CONSIDER` over it raises
  `NonExhaustivePatterns` — identically on both sides, which reads as agreement on an error and
  measures nothing. The identity fixture drops the `FormCFiling` slot and the
  `disclosure requirements are met` pair for exactly this reason. `l4 batch` has the same limit.
- **No `#ASSERT` in either module is consulted.** This is a differential oracle between two
  encodings and says nothing about whether either agrees with the statute. That question is HG1's
  and P5's.
- **Nothing here is `PASS`-worthy on its own terms yet.** If this becomes a pipeline stage, its
  oracle class is `differential` in the `verdict.mjs` sense — it proves two artifacts agree, not
  that either is right — and its evidence is the two probe corpora plus the journal-recorded
  digests of both modules.

---

## 9. What this change records elsewhere

Per `CLAUDE.md` §4 — a decision is recorded in its owning document in the same PR, or it is not
decided. **All four landed in the same change as this file** (verified 2026-08-02 by reading each
file, not by remembering the edit):

- **`ORCHESTRATOR.md` §8** ("Deliberately not built") listed "the de novo path and the §8 diff
  oracle" as unbuilt. The oracle is no longer in that table's row: the row now says the comparator
  is built, self-tested and unexercised, and that the de novo path it serves is still unbuilt.
- **`ORCHESTRATOR.md` §1** said "Milestone G2 is unbuilt … The §8 diff oracle does not exist
  either". The second clause was repaired in place, and the bullet says in so many words that the
  earlier version was true when written and is not now.
- **`SPEC.md` §6, G2** — "acceptance = the §8 diff oracle. … The P1–P6 tooling itself remains to be
  built" is still true, and now carries the pointer here plus the fact that the comparator does
  exist and has never seen a second encoding.
- **`schemas/README.md`** gained a fourth row and the sentence distinguishing a deposit contract
  (a stage writes it during a run) from the surface map (an input the G2 run writes as its pairing
  declaration).

(An earlier version of this section said all four were "not yet done at this writing". That was
true for about an hour and then was not; it is the exact drift the user-level `CLAUDE.md` rule 1
names, caught by an adversarial re-measure rather than by the author.)
