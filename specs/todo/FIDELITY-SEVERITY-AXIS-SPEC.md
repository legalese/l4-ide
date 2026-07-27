# Fidelity Notes: `Blocking` Is Two Different Facts

_Status: **ruling, not yet implemented.** Written 2026-07-27 on branch
`docs/fidelity-severity-axis`, against `3b9bfc6e`. Resolves smucclaw/l4-ide#928, which raised the
question and explicitly declined to answer it. Nothing in `jl4-core/src/L4/Interchange/Fidelity.hs`
has been changed by this document._

**Author:** Meng Wong, with measurement and analysis from Claude
**Component:** `jl4-core/src/L4/Interchange/Fidelity.hs`; the three backends that construct notes
(`L4/Dmn/Lower.hs`, `L4/Dmn/Markdown.hs`, `L4/Bpmn/Lower.hs`); `jl4/app/L4/Cli/Export.hs`
(`--fail-on`, the exit code)
**Related:** legalese/l4-ide#154 (`l4 export`, which forced the question),
`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` (§7 assigns severities to 8 unbuilt codes and must be
re-ruled against §5 below)
**Classification:** Tier-2 — interchange/DX, small blast radius today, large one once the service
surface (track S2) ships.

**One-line ruling.** Add a second, **orthogonal, computed** field to `FidelityNote` — not "whose
fault" but **what the emitted document now is** — with four values `Sound | Unevaluable | Incomplete
| Misstated`, no `Ord`, computed per note **instance** rather than assigned per note **code**; and
give `--fail-on` an effect-selector vocabulary whose useful member is `--fail-on=broken`. The
default exit behaviour stays 0.

**The finding that moves the ruling** is not the one the issue leads with. The issue says `Blocking`
is unusable because it fires on every export. It does — 98.6% of DMN exports, measured below. But the
larger fact is that **the information a CI gate needs is not in the report at all, under any code.**
Handed to a real FEEL engine, 73.6% of the DMN artifacts this repo produces contain at least one
expression that engine cannot evaluate; the two note codes whose own message text says "NO DMN engine
can evaluate it" find **15.8% of them**. So this is not only a vocabulary problem. It is
approximately one-sixth vocabulary and five-sixths missing computation, and a ruling that only
renames severities would ship a gate that lies.

---

## 1. What was measured

Everything in this section was executed against `3b9bfc6e` in the worktree
`/Users/mengwong/src/legalese/l4wt/fidelity-severity-axis`, with the binary at
`dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4` built from a clean tree
(`git status --short` empty). Scripts and data are listed in §8. Where a number comes from an earlier
pass in this session rather than from a command run for this document, it is labelled so.

### 1.1 The note vocabulary as it stands

```bash
grep -rn 'code *= *"' jl4-core/src/L4/{Bpmn/Lower.hs,Dmn/Lower.hs,Dmn/Markdown.hs}
grep -n 'dmnNote "' jl4-core/src/L4/Dmn/Lower.hs
grep -n 'note "'    jl4-core/src/L4/Dmn/Markdown.hs jl4-core/src/L4/Bpmn/Lower.hs
```

**31 distinct codes across 32 note-construction sites in 3 backends** — 12 `Blocking`, 8 `Lossy`,
11 `Advisory`. (12 `MkFidelityNote` records in `Bpmn/Lower.hs`, 13 `dmnNote` calls in
`Dmn/Lower.hs`, 7 `note` calls in `Markdown.hs`.)
The full list, with the new classification, is §5. Two codes are raised twice from different
conditions: `P-DEADLINE` (`Bpmn/Lower.hs:1012` and `:1046`) and `D-MD-TYPE`
(`Markdown.hs:295`, `:304`). `D-LIFTEDTHRESHOLD` likewise (`Dmn/Lower.hs:1456`, `:1653`).

### 1.2 The shipped exhibits

```bash
for f in jl4/examples/{bpmn,dmn}/expected/*.fidelity.txt; do
  printf '%-56s blocking=%s lossy=%s advisory=%s\n' "$f" \
    "$(grep -cE '^  \[[^]]+\] blocking — ' $f)" \
    "$(grep -cE '^  \[[^]]+\] lossy — ' $f)" \
    "$(grep -cE '^  \[[^]]+\] advisory — ' $f)"
done
```

| golden                  | blocking | lossy | advisory |
| ----------------------- | -------- | ----- | -------- |
| `consultation.fidelity` | 3        | 1     | 1        |
| `handover.fidelity`     | 6        | 2     | 5        |
| `offering.fidelity`     | 5        | 2     | 6        |
| `reg-cf.fidelity`       | 1        | 0     | 6        |
| `reg-cf.md.fidelity`    | 4        | 1     | 0        |

**5 of 5 shipped exhibits carry at least one `Blocking` note.** `--fail-on=blocking` fails every
example this project ships as a demonstration of the feature working.

### 1.3 The corpus sweep

Every `.l4` file in the repo, all three targets, BPMN re-run once per regulative rule where the
module holds more than one. Re-executed for this document; the driver is the same one an earlier
measurement pass in this session used, so the two runs are comparable and agree to within a
percentage point everywhere.

```bash
python3 scratchpad/run_corpus.py \
    dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4 \
    scratchpad/ruling/mycorpus.jsonl
python3 scratchpad/ruling/analyse.py scratchpad/ruling/mycorpus.jsonl
```

**2080 export attempts → 1186 artifacts** (dmn 505, dmn-md 505, bpmn 176). Non-artifact attempts:
626 BPMN "no regulative rules", 134×2 typecheck/no-decision failures, and **30 timeouts at 180 s** — ten
files × three targets, namely `jl4/experiments/jerseyCharities.l4` and the nine under
`paper/case-studies/charities-jersey-2014/`. Excluded, not measured.

| CODE                  | SEV      | TARGET | EXPORTS | FILES | INSTANCES |
| --------------------- | -------- | ------ | ------- | ----- | --------- |
| `D-MD-NOLITERAL`      | blocking | dmn-md | 492     | 492   | 4269      |
| `D-LITERALEXPR`       | blocking | dmn    | 492     | 492   | 4253      |
| `D-MD-NODRG`          | blocking | dmn-md | 380     | 380   | 380       |
| `D-NONFEELOUTPUT`     | blocking | dmn    | 48      | 48    | 279       |
| `F1`                  | blocking | bpmn   | 170     | 51    | 273       |
| `D-MD-CELLSYNTAX`     | blocking | dmn-md | 43      | 43    | 264       |
| `D-MD-NONIDENTCOLUMN` | blocking | dmn-md | 60      | 60    | 242       |
| `D-NONFEELINPUT`      | blocking | dmn    | 28      | 28    | 64        |
| `P-DEADLINE`          | blocking | bpmn   | 35      | 11    | 43        |
| `F3`                  | blocking | bpmn   | 9       | 6     | 10        |
| `D-SCOPE`             | lossy    | dmn    | 183     | 183   | 461       |
| `F2`                  | lossy    | bpmn   | 170     | 51    | 170       |
| `D-MD-NODEFAULT`      | lossy    | dmn-md | 42      | 42    | 67        |
| `D-MD-TYPE`           | lossy    | dmn-md | 9       | 9     | 15        |
| `P-NOJOIN`            | lossy    | bpmn   | 14      | 12    | 14        |
| `F4`                  | lossy    | bpmn   | 9       | 6     | 10        |
| `P-DEADLINE-UNIT`     | advisory | bpmn   | 139     | 49    | 213       |
| `F5`                  | advisory | bpmn   | 176     | 51    | 176       |
| `D-UNDECOMPOSABLE`    | advisory | dmn    | 40      | 40    | 182       |
| `D-COMPUTEDOUTPUT`    | advisory | dmn    | 39      | 39    | 85        |
| `D-ORDERDEPENDENT`    | advisory | dmn    | 46      | 46    | 68        |
| `P-DANGLING`          | advisory | bpmn   | 39      | 21    | 47        |
| `D-INLINEDLOCAL`      | advisory | dmn    | 8       | 8     | 26        |
| `D-LIFTEDTHRESHOLD`   | advisory | dmn    | 2       | 2     | 3         |
| `D-NONFEEL`           | advisory | dmn    | 1       | 1     | 1         |

**25 of 31 codes fired.** Never fired on the whole corpus: `P-CYCLE`, `P-DEADLINE-UNDRAWN`,
`P-JUNCTION-OBLIGATION`, `P-MULTI-HENCE`, `D-FLATTENCAP`, `D-HITPOLICY`.

Two instance counts in that table are worth reading twice, because they are the two targets' whole
character:

- **`D-LITERALEXPR` 4253 instances, and 94.8% of decisions are boxed literal expressions.** Counting
  elements over the 506 retained DMN artifacts: 4587 `<decision>`, 4347 `<literalExpression>`,
  240 `<decisionTable>`. The DMN backend produces decision _tables_ for one decision in twenty.
- **`D-MD-NOLITERAL` 4269 instances against those 4587 decisions — ~93% of decisions are omitted from
  the markdown outright**, before `D-MD-NONIDENTCOLUMN` (242) and `D-MD-CELLSYNTAX` (264) drop whole
  tables on top. dmnmd is not lossy; for this corpus it is mostly empty.

Now the three gates that exist today, per target:

| gate                 | dmn             | dmn-md         | bpmn            | ALL                   |
| -------------------- | --------------- | -------------- | --------------- | --------------------- |
| `--fail-on=blocking` | 498/505 (98.6%) | 505/505 (100%) | 170/176 (96.6%) | **1173/1186 (98.9%)** |
| `--fail-on=lossy`    | 498/505 (98.6%) | 505/505 (100%) | 175/176 (99.4%) | **1178/1186 (99.3%)** |
| `--fail-on=advisory` | 502/505 (99.4%) | 505/505 (100%) | 176/176 (100%)  | **1183/1186 (99.7%)** |
| zero notes at all    | 3/505 (0.6%)    | 0/505 (0%)     | 0/176 (0%)      | **3/1186 (0.3%)**     |

`--fail-on` is a threshold over `Blocking < Lossy < Advisory`, so the three levels are almost the
same predicate: **they differ by 0.8 percentage points across 1186 exports.** Three gate values, one
gate.

### 1.4 The external oracle — the measurement this ruling turns on

The previous sections measure what the exporter _says_. This one measures what the artifact _is_,
using something that is not ours.

**Why FEEL is the right oracle, and why the artifact is on the hook for it.** DMN 1.3 §7.3.5
(OMG `formal/20-06-01`, read from the OMG PDF via `pdftotext -layout`, lines 3009–3021 of the
extracted text):

> An instance of `LiteralExpression` has an optional `text`, which is a String, and an optional
> `expressionLanguage`, which is a String that identifies the expression language of the text. If no
> `expressionLanguage` is specified, the expression language of the text is the `expressionLanguage`
> that is associated with the containing instance of `Definitions`. … **The default expression
> language is FEEL.**
>
> … **The semantics of DMN 1.3 decision models as described in this specification applies only if
> the text of all the instances of `LiteralExpression` in the model are valid expressions in their
> associated expression language.**

```bash
grep -n 'expressionLanguage' jl4-core/src/L4/Dmn/Emit.hs   # → no output
```

The exporter emits no `expressionLanguage` anywhere. So **every `<text>` in every DMN artifact this
repo produces claims, by the spec's own default rule, to be FEEL** — and where it is not, DMN's
normative sentence says the specification's semantics does not apply to the model. That is a
binary, externally-defined, checkable predicate. It is exactly what a CI gate wants, and it is not
ours to argue with.

**The probe.** Re-export every DMN-exportable file, retaining the artifact; then hand every
`<literalExpression>/<text>`, `<inputExpression>/<text>`, `<inputEntry>/<text>` and
`<outputEntry>/<text>` to `feelin` 7.0.1 — package description _"A FEEL parser and interpreter"_,
repository `github.com/nikku/feelin`, both read out of its own `package.json` — binding every name
the model itself defines (`inputData`, decision output variables) to a dummy typed from the model's
own `typeRef`. (`feelin` is one FEEL implementation, not the normative one; the `SYNTAX` verdict is
about the FEEL grammar, which the spec defines, and the `UNBOUND` verdict is about name resolution
inside the model, which no implementation can differ on. Where an engine-specific judgement was
needed, it is flagged.)

```bash
python3 scratchpad/ruling/sweep_dmn.py \
    dist-newstyle/.../l4 scratchpad/fsa/dmnfiles.json scratchpad/ruling/art scratchpad/ruling/index.jsonl
# → attempted 507  artifacts 507  timeouts 0
node scratchpad/ruling/feeloracle.mjs scratchpad/ruling/index.jsonl scratchpad/ruling/oracle.jsonl
```

Verdicts, per expression and per artifact:

| verdict   | meaning                                                                      | expressions | artifacts with ≥1 |
| --------- | ---------------------------------------------------------------------------- | ----------- | ----------------- |
| `OK`      | parsed and produced a value                                                  | 4816        | —                 |
| `SYNTAX`  | the FEEL parser produced error nodes — not FEEL at all                       | 2963        | **339 (66.9%)**   |
| `UNBOUND` | parses, but a free name in it is defined nowhere in the model; engine → null | 637         | **183 (36.1%)**   |
| `WARN`    | other engine warning (type)                                                  | 191         | 73 (14.4%)        |
| `THROW`   | probe threw                                                                  | 1           | 1 (0.2%)          |
| **total** |                                                                              | **8608**    |                   |

> **`SYNTAX ∪ UNBOUND`: 373 of 507 DMN exports = 73.6%.** Fully clean: 128 = 25.2%.

**Controls.** The oracle does not manufacture failures and does not miss the known one.

- _Positive._ The shipped golden `jl4/examples/dmn/expected/reg-cf.dmn`: **32 expressions, 32 `OK`.**
- _Negative._ `l4 export --to=dmn doc/reference/functions/let-example.l4`: **13 expressions, exactly
  1 `SYNTAX`**, and it is precisely the raw-L4 payload
  `Point WITH x IS ((Point WITH x IS 0 y IS 0)'s x) PLUS 10 y IS ((Point WITH x IS 0 y IS 0)'s y) PLUS 20`.

The `UNBOUND` bucket is not a probe artefact; sampling it returns raw L4 that happens to parse
because FEEL names may contain spaces — `RIGHT OF 42`, `b OF a`, `JSONENCODE OF colorList`,
`PARTY S MUST delivery WITHIN 3`, `GIVEN x IS x30 y IS y32 YIELD x` — plus module-qualified
references the model never defines, e.g. `Eligibility Rules.age >= 18`, `Jurisdiction
Library.Country Codes _ ISO 3166_1.Sweden`.

### 1.5 What the current report predicts, against that oracle

This is the table the ruling rests on. Each row is a predicate a consumer could write today; scored
against `SYNTAX ∪ UNBOUND` as ground truth, over the 507 DMN exports.

| predicate available today                    | fires       | precision | recall    |
| -------------------------------------------- | ----------- | --------- | --------- |
| `--fail-on=blocking` (≥1 blocking note)      | 500 (98.6%) | 74.6%     | 100.0%    |
| `--fail-on=advisory` (≥1 note at all)        | 504 (99.4%) | 74.0%     | 100.0%    |
| code ∈ {`D-NONFEELOUTPUT`, `D-NONFEELINPUT`} | 65 (12.8%)  | 90.8%     | **15.8%** |
| code = `D-LITERALEXPR`                       | 494 (97.4%) | **75.1%** | 99.5%     |
| code = `D-SCOPE`                             | 185 (36.5%) | 91.4%     | 45.3%     |

Three readings, all load-bearing:

1. **The severity axis carries no actionable information.** `--fail-on=blocking` has perfect recall
   and fires on 98.6% of exports; it is the predicate `True` with extra steps. A severity that is
   always at its maximum is equivalent to no severity — the issue's words, now with a number.
2. **The codes that _claim_ to mark unevaluable output find one in six of them.** 314 of the 373
   broken artifacts (84.2%) carry no `D-NONFEEL*` note at all; 189 of those carry `D-LITERALEXPR`
   alone. Whatever vocabulary is adopted, if `Unevaluable` is assigned per code it inherits that
   15.8% recall.
3. **`D-LITERALEXPR` is right three times in four, and that is the whole problem in one code.** It
   fires on 494 exports; on **123** of them the artifact is perfectly evaluable. Its own message says
   what it means — _"is not a guarded chain (IF / BRANCH / CONSIDER), so it has no rows, so it is
   emitted as a boxed literal expression rather than a decision table"_, lost: _"every
   decision-table analysis"_. That is a statement about **analysability**, and it is being asked to
   stand in for **executability**. Those are different properties of the same note, and no code-based
   filter can separate them, because the same code covers both cases.

The single `Blocking` note in the shipped `reg-cf` golden is exactly this: `D-LITERALEXPR` on
`decision_combined_resources`, whose artifact is
`<literalExpression id="decision_combined_resources_literal"><text>annual income + net worth</text></literalExpression>`
— valid FEEL, and one of the 32 expressions the oracle scored `OK`. **The project's flagship
`Blocking` note is on a document a DMN engine runs correctly.**

The codebase already knows this distinction and already fixed it — twice. `Dmn/Lower.hs:1418-1421`,
on the exclusion between `D-COMPUTEDOUTPUT` and `D-NONFEELOUTPUT`:

```haskell
-- MUTUALLY EXCLUSIVE with D-NONFEELOUTPUT. An L4Verbatim entry satisfies
-- `not . isConstantText` too, and used to be reported by this Advisory
-- note alone -- a note about ANALYSABILITY standing in for a failure of
-- EXECUTABILITY. That is the defect this split fixes.
```

The split was applied at `:1430` (table path) and `:1664` (select-idiom path). It was **not** applied
at `literalFallback` (`:1681-1692`), which is the path 94.8% of decisions take (§1.3).
`D-LITERALEXPR` is the third instance of a defect this file has already diagnosed and named.

Reproducible in one command on the clean binary:

```bash
l4 export --to=dmn doc/reference/functions/let-example.l4 -o /tmp/x.dmn --fidelity-report
```

reports 10 × `D-LITERALEXPR` and 1 × `D-NONFEELOUTPUT`; the `D-NONFEELOUTPUT` is on
`decision_factorial_of` (the table path), while `decision_shifted_point_example` — the one carrying
raw L4 into a `<text>` element — is reported **only** as `D-LITERALEXPR`.

### 1.6 `D-SCOPE`: the Lossy note that breaks the artifact

```python
# for every retained artifact: do two <inputData> elements share a @name?
for r in rows:                                    # rows = scratchpad/ruling/index.jsonl
    names = re.findall(r'<inputData\b[^>]*\bname="([^"]*)"', open(r['artifact']).read())
    dup   = len(names) != len(set(names))
    note  = any(n['code'] == 'D-SCOPE' for n in r['notes'])
```

**185 of 507 artifacts emit a duplicate `inputData/@name`; `D-SCOPE` fires on exactly those 185.
TP=185, FP=0, FN=0.** 3381 `<inputData>` elements over the corpus. The note is `Lossy`, one rung
below `Blocking`, and its own text says what happens: _"DMN's inputData is global, so the emitted
model has two elements a FEEL expression cannot tell apart."_ The model parses, loads, runs, and
answers using whichever binding the engine picked.

`D-SCOPE` is the counter-example that kills "let consumers filter by code": a consumer filtering
`severity == Blocking` today gets 4269 dmnmd omission notes it may not care about **and misses every
artifact whose FEEL names are ambiguous.**

### 1.7 BPMN: the executability axis is constant by construction

```bash
grep -n 'isExecutable' jl4-core/src/L4/Bpmn/Emit.hs
#   12:-- * @isExecutable=\"false\"@. This is a description of a rule, not a deployable
#   98:      , ("isExecutable", "false")
grep -o 'isExecutable="[a-z]*"' jl4/examples/bpmn/expected/*.bpmn   # → false, false, false
```

`isExecutable="false"` is a literal at `Emit.hs:98`. Every BPMN document this exporter has ever
produced declares itself non-executable, in BPMN's own vocabulary — and BPMN 2.0 defines what that
means. §2.1: _"Common Executable focuses on what is needed for executable process models."_ §2.1.4:
_"This conformance sub-class is intended for modeling tools that can emit executable models."_
Table 10.1, on `isExecutable`: _"A non-executable Process is a private Process that has been modeled
for the purpose of documenting Process behavior at a modeler-defined level of detail. Thus,
information needed for execution, such as formal …"_ — the sentence continues past the page break;
what matters is that the spec expects a non-executable Process to be missing execution information.
These artifacts do not claim `Common Executable` and do not need to.

Consequence, and it is a ruling not a footnote: **no BPMN note can be `Unevaluable`.** Notes whose
`lost` text is about machine-evaluability — `P-DEADLINE`'s _"the trigger as something an engine could
evaluate"_ — are describing a capability the artifact never offered. Those texts should be reworded
(§7, W6). What remains for BPMN is `Incomplete` and `Misstated`, which is a rare and therefore useful
gate.

Element-level check on the shipped goldens:

```bash
for b in jl4/examples/bpmn/expected/*.bpmn; do f=${b%.bpmn}.fidelity.txt;
  printf '%s tasks=%s F1=%s\n' "$(basename $b)" \
    "$(grep -oc '<bpmn:task\|<bpmn:userTask' $b)" "$(grep -c '^  \[F1\]' $f)"; done
# consultation tasks=3 F1=3 / handover tasks=5 F1=5 / offering tasks=5 F1=5
```

`F1` fires once per task, exactly. The issue's characterisation is correct and the note is correct;
it is the severity that is wrong to gate on.

### 1.8 Where the measurement contradicts the issue

| the issue says                                                               | the measurement says                                                                                                                                                      |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "`Blocking` fires on 100% of exports"                                        | 98.6% of DMN, and 5/5 shipped goldens. The exceptions are degenerate modules. Substantively right, literally wrong; a gate on it is unusable.                             |
| the second axis is **whose fault** (target / exporter / artifact)            | fault is not what CI can act on, no comparable tool ships it, and the corpus needs **four** fault values, not three. Declined — see §2.2.                                 |
| direction 3, "let consumers filter by note code", is merely cheap-but-untidy | it is **impossible**. The predicate is not a function of the code: `D-LITERALEXPR` covers both evaluable and unevaluable instances (75.1%).                               |
| the missing thing is a severity                                              | the missing thing is a **computation**. Re-tagging codes gets `Unevaluable` to 15.8% recall; the other 84.2% needs the exporter to consult a value it already has (§3.3). |

---

## 2. The ruling

### 2.1 What is adopted

**A fourth direction, closest in shape to the issue's direction 1 but different in two ways that the
measurement forces.**

Add one field to `FidelityNote`, orthogonal to `severity`:

- it classifies **what the emitted document now is**, not whose fault it is;
- it is **computed per note instance**, not assigned per note code.

`severity` is left exactly as it is — same three constructors, same `Ord`, same assignments, same
five goldens. Its job shrinks: it says how much a _reader_ lost, which is what
`Fidelity.hs`'s module header always said it was for ( _"the losses it names are properties of the
target notation, and naming them precisely is the deliverable"_ ). It stops being asked to do gate
work it was never shaped for.

The new field does the gate work, and `--fail-on` grows the vocabulary to name it (§4).

### 2.2 Why the other three lose

**Direction 3 — leave the vocabulary, let consumers filter by code — loses on a measurement, not on
taste.** The distinction a CI check needs is not a function of the note code. `D-LITERALEXPR` has
75.1% precision against a real engine; 123 of the 494 exports it fires on are perfectly evaluable.
No consumer, however careful, can recover from a code what the code does not distinguish. `P-DEADLINE`
makes the same point structurally: one code, two raise sites (`Bpmn/Lower.hs:1012` and `:1046`), two
different conditions. A code-based filter would have to split the code — which is the work direction
3 claims to avoid — and the split still would not reach `D-LITERALEXPR`, whose two cases are
distinguished only at run time by the rendered fragment. Direction 3 additionally invites every
consumer to re-derive the classification differently, which is the failure mode the whole
`FidelityReport` type exists to prevent; every comparable tool (clang, rustc, ESLint, pandoc,
bpmnlint, SARIF) puts this classification in the producer.

**Direction 2 — a severity above `Blocking` — loses on the `Ord` instance and on silence.** The
threshold is `any (\n -> n.severity <= t) ns` (`Export.hs:409`), the only `Ord` use in the tree.
Insert `Broken` before `Blocking` and: `--fail-on=blocking` starts tripping on `Broken`, which is
wanted; but `Broken` is nameable by **no** `--fail-on` value until `FidelityGate` gains a
constructor, and nothing in the compiler asks for that, because `fidelityGateReader`
(`Export.hs:139-150`) ends in a catch-all `other ->` and `tripsGate`'s `case` is over `FidelityGate`,
not over severity. Meanwhile the stderr tally (`Export.hs:366-375`) is a hand-written list of three
pairs, and `blockingCodes` (`:376`) uses `==`, not `<=` — so the two lines a human actually reads
would silently stop mentioning the very notes the change exists to surface. The single compile error
you would get is `renderNote`'s `case` (`Fidelity.hs:77-80`). One loud failure, four quiet ones.
And it is conceptually wrong regardless: severity would then mix "how much was lost" with "is the
document broken", which are independent — measured, §1.5 and §1.6: `Blocking`+runs occurs 13 times
in one shipped golden (`F1` in `offering`) and once in another (`D-LITERALEXPR` in `reg-cf`), and
`Lossy`+broken occurs on 183 corpus exports (`D-SCOPE`, absent from the goldens only because the
flagship exhibit is `ASSUME`-style).

**Direction 1 as worded — an orthogonal "whose fault" flag — loses on three counts.** (a) It is not
what a gate can act on: "this is our exporter's fault" and "this is BPMN's fault" are equally
un-actionable in CI, where the only question is whether the artifact is fit to ship. (b) The corpus
does not fit three values. Reading the raise sites yields at least four addressees: the target
notation (`F1`), this exporter (`P-NOJOIN` — _"a real limitation of what this exporter draws today"_,
`jl4/examples/bpmn/README.md`), the **L4 source language** (`P-DEADLINE-UNIT` — _"nothing in L4 fixes
one — WITHIN is typed as a bare NUMBER"_), and this particular module (`P-MULTI-HENCE`). (c) No
comparable tool ships a fault enum. SARIF v2.1.0 §3.27.9 ships `kind`
(`pass|open|informational|notApplicable|review|fail`) and §3.27.10 makes `level` subordinate to it —
_"the concept of 'severity' does not apply to this result because the `kind` property has a value
other than `fail`"_. ESLint's `meta.type` is `problem|suggestion|layout`. Both ask **"is this a
defect?"**, never **"who is to blame?"**. The adopted design is that question, sharpened for a
document rather than for a source file.

Fault is not lost — it is already in every note's `message` and `lost` prose, which is where it
belongs, because it is advice to a human and not a predicate. §6 records what would change that.

### 2.3 The strongest argument against this ruling

**It does not make the gate un-saturated on every target, and on one target it barely helps.**

For dmnmd, `Incomplete` will fire on essentially every export — because the carrier genuinely drops
most decisions (§1.3). Swapping a 100%-saturated `Blocking` gate for a ~98%-saturated `Incomplete`
gate is not obviously progress, and someone will reasonably say the effect axis has just relocated
the problem.

Three answers, in decreasing order of comfort. First, the numbers differ where it matters: on DMN the
gate goes from 98.6%-and-uninformative to 76.7%-and-true, and on BPMN from 96.6% to **8.0%**
(14 of 176 exports — see §4.4). Second,
`Incomplete` at 98% on dmnmd is not a defect of the axis, it is a **true report about a bad carrier**,
and having it stated in a gateable form is the first step to fixing the carrier rather than the
first step to ignoring it — which is what the current vocabulary invites, since a reader who learns
that `Blocking` is normal learns to ignore all of it. Third, and least comfortable: the honest
consequence is that `--fail-on=broken` is per-target advice, not a universal one, and the
documentation must say so instead of pretending otherwise (§4.3).

A second objection, which I think is right and am accepting anyway: **keeping `Blocking` unchanged
leaves a loaded gun on the table.** `--fail-on=blocking` will still be the first flag anyone reaches
for, and it will still be useless. Pandoc's answer to the same problem was to grade
target-cannot-express at its _lowest_ level (`SkippedContent`, `InlineNotRendered`,
`BlockNotRendered` → `INFO`), below its `--fail-if-warnings` gate. Adopting that would mean demoting
`F1`/`D-LITERALEXPR`/`D-MD-NODRG` to `Advisory`, which contradicts `Fidelity.hs`'s stated purpose and
churns 5 goldens and 29 test assertions for a benefit the effect axis already delivers. The ruling
therefore keeps severity and pays for it with documentation (§4.3, `--fail-on=blocking` marked
"almost always true"). If in six months people are still reaching for `--fail-on=blocking` and being
misled, the pandoc demotion is the correct follow-up and this paragraph is the record that it was
considered.

---

## 3. The Haskell shape

### 3.1 The type

In `jl4-core/src/L4/Interchange/Fidelity.hs`, add to the export list and define:

```haskell
-- | What the emitted artifact now IS, as a consequence of this note.
--
-- Orthogonal to 'FidelitySeverity'. Severity says how much the READER lost;
-- effect says what standing the DOCUMENT has. Both off-diagonals occur: @F1@
-- is 'Blocking' and 'Sound' (BPMN cannot mark a prohibition, but the diagram
-- is a correct diagram); @D-SCOPE@ is 'Lossy' and 'Misstated' (the model runs,
-- and answers using the wrong variable).
--
-- Each value is defined by a check a third party can run on the artifact
-- alone, without reading the L4 source and without trusting this report:
data FidelityEffect
  = Sound
    -- ^ a conforming engine runs the artifact, every rule the source states has
    -- a counterpart in it, and evaluating it agrees with the source. What was
    -- lost is a capability the TARGET does not have.
  | Unevaluable
    -- ^ the artifact contains text a conforming engine cannot evaluate: it
    -- errors, or it answers @null@ on a name the model never defines. For DMN
    -- "conforming" means Conformance Level 3 (full FEEL), which is the level
    -- the artifact implicitly claims by omitting @expressionLanguage@
    -- (DMN 1.3 §7.3.5).
  | Incomplete
    -- ^ a rule the source states has no counterpart in the artifact at all.
    -- Checkable by counting.
  | Misstated
    -- ^ every counterpart is present and the artifact evaluates, but it
    -- evaluates to something the source does not say. Checkable by
    -- differential evaluation.
  deriving stock (Eq, Show, Generic, Enum, Bounded)
  deriving anyclass (NFData)

data FidelityNote = MkFidelityNote
  { code     :: Text
  , severity :: FidelitySeverity
  , effect   :: FidelityEffect   -- NEW, mandatory, no default
  , element  :: Text
  , range    :: Maybe SrcRange
  , message  :: Text
  , lost     :: Text
  }
```

**`FidelityEffect` deliberately does not derive `Ord`.** There is no ordering under which "a rule is
missing" is more or less serious than "the answer is wrong"; a consumer that wants both must name
both. This is not a stylistic preference — it is the design decision that stops the new axis
degenerating into the old one. See §3.2.

`Enum, Bounded` **are** derived, and should be added to `FidelitySeverity` too, so that the tally in
`Export.hs` can be written `[minBound .. maxBound]` instead of a hand-written list of three. That
hand-written list is the mechanism by which direction 2 would have failed silently; it should not
survive this change regardless of which direction is taken.

### 3.2 The `Ord` instance and who depends on it

```bash
grep -rn '\.severity' --include='*.hs' jl4-core/src/L4 jl4/app jl4/tests jl4/tests-cli
```

**Exactly one site uses the ordering, and it is the exit code**: `tripsGate`, `Export.hs:406-415`,
`any (\n -> n.severity <= t) ns`. Every other occurrence is `==` (`Export.hs:366`, `:376`;
`BpmnExport.hs:1223`) or `shouldBe` against a literal. `FidelitySeverity` derives neither `Enum` nor
`Bounded`, so nothing enumerates it.

Ruling:

- **`FidelitySeverity` keeps `Ord`**, unchanged, and the comment that documents the order dependence
  moves from `Export.hs:404-405` to the `deriving` clause at `Fidelity.hs:32`, where a future editor
  reordering the constructors will actually see it.
- **`FidelityEffect` gets no `Ord`, and the gate type is shaped so that none is needed** — the gate
  holds a _list_ of effects and tests with `elem`, not a `Set` and `member`, precisely so that no one
  adds `Ord` to make a `Set` work (§4.1).

### 3.3 How `effect` is computed — the part that is not a rename

This is where the 84.2% lives. Two rules.

**Rule A — `Unevaluable` is read off the rendered fragment, at every site that renders one.**
`L4.Dmn.IR` already carries the fact: `FeelFragment = SFeel | FullFeel | L4Verbatim`
(`Dmn/IR.hs:146-158`), with `L4Verbatim` documented _"not executable by a DMN engine"_. Add one
helper next to it and use it everywhere a `FeelExpr` is emitted:

```haskell
effectOfFragment :: FeelFragment -> FidelityEffect
effectOfFragment L4Verbatim = Unevaluable
effectOfFragment _          = Sound
```

The two sites that already gate on `L4Verbatim` (`nonFeelOutput`, called from `Dmn/Lower.hs:1430`
and `:1664`) keep their behaviour. The site that does not — `literalFallback`, `Dmn/Lower.hs:1681-1692`
— must consult `rendered.feFragment` exactly as they do. Concretely, `D-LITERALEXPR` becomes

```haskell
, [ dmnNote "D-LITERALEXPR" Blocking (effectOfFragment rendered.feFragment) did (bestRange body) … ]
```

so that one note code carries two different effects depending on the instance. **That is the design's
whole point**, and it is why the field cannot be a lookup table keyed on the code.

**Rule B — the helpers take the effect positionally, never by default.** `dmnNote`
(`Dmn/Lower.hs:1299`), `note` (`Markdown.hs:315-317`) and `boundaryTrigger`'s local `note`
(`Bpmn/Lower.hs:1059-1068`) funnel most of the 32 construction sites through 3 helpers. If the helpers default the
field, the compiler classifies nothing and every DMN code silently lands on one value. Each helper
gains a `FidelityEffect` argument in the same position as `FidelitySeverity`, so that every call site
is forced to answer.

The compiler will enforce this at the record-construction sites that do not use a helper. Verified:

```bash
$ cat W.hs
module W where
data R = MkR { a :: Int, b :: Bool }
mk :: R
mk = MkR { a = 1 }
$ ghc -Wall -Werror -fno-code W.hs
W.hs:4:6: error: [GHC-20125] [-Wmissing-fields, Werror=missing-fields]
    • Fields of ‘MkR’ not initialised: b :: Bool
```

`-Wmissing-fields` is in `-Wall`; `jl4-core.cabal:21` and `jl4.cabal:9` both set `-Wall -Werror`. So
the 12 record-style sites in `Bpmn/Lower.hs` fail to compile until answered. (Note the limit:
`jl4-core` does **not** set `-Wincomplete-record-updates`; only `jl4-service` does
(`jl4-service.cabal:15-19`). Do not rely on record _update_ warnings here.)

### 3.4 Migration, consumer by consumer

Every consumer of `FidelitySeverity` in the tree, and what this change does to it. "Compile error"
means `-Werror` stops the build; "silent" means it builds and does the wrong thing, which is what the
migration has to catch by hand.

| #   | Consumer                                                           | Anchor                                                                                                                                                                                           | Effect of this change                                                                                                                                                                                                                                                                           | Action                                                                                                                                                                                              |
| --- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `renderNote` — the only rendering, and the format of all 5 goldens | `Fidelity.hs:69-80`                                                                                                                                                                              | none (no `case` on the new field until one is written)                                                                                                                                                                                                                                          | print the effect word in parens **only when ≠ `Sound`**: `[D-SCOPE] lossy (misstated) — …`. Goldens then diff exactly where the classification is non-trivial — the diff _is_ the review.           |
| 2   | stderr tally                                                       | `Export.hs:365-375`                                                                                                                                                                              | none, but the hand-written 3-list is the silent-failure mechanism identified in §2.2                                                                                                                                                                                                            | rewrite as `[minBound .. maxBound]` over `FidelitySeverity`; add a second line counting effects ≠ `Sound`                                                                                           |
| 3   | "blocking codes" stderr line                                       | `Export.hs:376`, printed `:384-387`                                                                                                                                                              | none; but its parenthetical _"(the notation has no form for it; a fallback was emitted)"_ is now provably false for `D-SCOPE`-class notes                                                                                                                                                       | reword; add a `broken codes:` line listing the distinct codes whose `effect` is not `Sound`                                                                                                         |
| 4   | **`tripsGate` — the gate and the exit code**                       | `Export.hs:406-415`, consumed `:236`                                                                                                                                                             | rewritten (§4.1). The severity branch is byte-for-byte the current behaviour.                                                                                                                                                                                                                   | see §4.1                                                                                                                                                                                            |
| 5   | `FidelityGate` + `--fail-on` reader                                | `Export.hs:101-106`, `139-150`, `199-208`                                                                                                                                                        | type changes from an enum to a record; the reader's `other ->` catch-all stays                                                                                                                                                                                                                  | §4.1, §4.2                                                                                                                                                                                          |
| 6   | module haddock stating the design rationale                        | `Export.hs:30-52`                                                                                                                                                                                | stale — it says the tool _"deliberately does not exit non-zero on a `Blocking` note"_ and explains why                                                                                                                                                                                          | rewrite: the reason is now "because `Blocking` is not the executability signal; `--fail-on=broken` is"                                                                                              |
| 7   | **Producer** — DMN XML                                             | `Dmn/Lower.hs:1265-1298` (vocab haddock), 13 `dmnNote` calls (`:1299`), one of which is the `nonFeelOutput` wrapper (`:1315-1317`, called from `:1430` and `:1664`)                              | **compile error** at the helper; then 12 decisions, of which `D-LITERALEXPR` is computed and the rest are constants                                                                                                                                                                             | §5; Rule A + Rule B                                                                                                                                                                                 |
| 8   | **Producer** — dmnmd                                               | `Markdown.hs:242-317`, 7 sites via `note` (`:315`)                                                                                                                                               | compile error at the helper; 6 decisions                                                                                                                                                                                                                                                        | §5                                                                                                                                                                                                  |
| 9   | **Producer** — BPMN                                                | `Bpmn/Lower.hs`, 12 `MkFidelityNote` records (`:277,303,602,721,753,782,816,833,1060,1144,1180,1195`; `:1060` is `boundaryTrigger`'s local helper, serving `P-DEADLINE`×2 and `P-DEADLINE-UNIT`) | **compile error at all 12** via `-Wmissing-fields`; 13 decisions                                                                                                                                                                                                                                | §5; note §1.7 — none of them is `Unevaluable`                                                                                                                                                       |
| 10  | `BpmnExport { bxFidelity }`                                        | `Bpmn/IR.hs:200`                                                                                                                                                                                 | none                                                                                                                                                                                                                                                                                            | —                                                                                                                                                                                                   |
| 11  | `dmnReport` / `drgNotesAll` / `dtNotes`                            | `Dmn/IR.hs:354`, `:416`, `:483-495`                                                                                                                                                              | none (severity-blind folds)                                                                                                                                                                                                                                                                     | —                                                                                                                                                                                                   |
| 12  | `FidelityLoss` — a separate DMN-local enum                         | `Dmn/IR.hs:447-467`                                                                                                                                                                              | none. Worth knowing it is already a partial "why" axis for the decision side (`NotAGuardedChain`, `RowsElided`, …)                                                                                                                                                                              | leave; §6 asks whether it should fold in                                                                                                                                                            |
| 13  | Test — DMN export, 18 severity assertions                          | `jl4/tests/DmnExport.hs:777,830,845,859,867,913,926,933,944,961,969,986,1007,1050,1089,1114,1119,1126`                                                                                           | compiles; **still passes**, since no severity moves                                                                                                                                                                                                                                             | add effect assertions beside them; the `describe` at `:905-947` ( _"L4 source in a `<text>` element is Blocking, not Advisory"_ ) is this ruling's ancestor and should gain `effect == Unevaluable` |
| 14  | Test — BPMN export, 11 severity assertions                         | `jl4/tests/BpmnExport.hs:759,913,1053,1054,1091,1111,1112,1144,1166,1186,1222`                                                                                                                   | compiles; still passes                                                                                                                                                                                                                                                                          | `:1091`'s comment — _"every F1 is Blocking, so severity cannot be what marks a prohibition"_ — is the issue, written down. Add `effect == Sound` there.                                             |
| 15  | Golden `.fidelity.txt` fixtures                                    | `jl4/examples/{bpmn,dmn}/expected/*.fidelity.txt` (5 files)                                                                                                                                      | **byte-exact comparison breaks** wherever a note is not `Sound`                                                                                                                                                                                                                                 | re-bless; expected diff is small and reviewable: `D-MD-*` in `reg-cf.md`, `P-DEADLINE`/`F*` unchanged, `reg-cf.dmn`'s single `D-LITERALEXPR` **unchanged** (its fragment is FEEL)                   |
| 16  | CLI test — `--fail-on` threshold matrix                            | `jl4/tests-cli/Main.hs:942-1002`                                                                                                                                                                 | **passes unchanged** — severity thresholds keep their exact semantics. This is the strongest argument for not touching severity.                                                                                                                                                                | add rows for the effect selectors, with fixtures that are `Unevaluable`-only and `Incomplete`-only                                                                                                  |
| 17  | CLI test — sidecar/stderr routing                                  | `jl4/tests-cli/Main.hs:896-940`                                                                                                                                                                  | passes unless #1's rendering changes a line these match on (`:934-939` asserts the substring `"blocking"`)                                                                                                                                                                                      | check after #1                                                                                                                                                                                      |
| 18  | User-facing docs                                                   | `jl4/examples/dmn/README.md:147-149`, `jl4/examples/bpmn/README.md:141`, `Dmn/Lower.hs:1265-1298`, `Fidelity.hs:1-10`                                                                            | stale                                                                                                                                                                                                                                                                                           | rewrite                                                                                                                                                                                             |
| 19  | Forward-looking spec assigning severities to 8 unbuilt codes       | `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md:1065-1077`                                                                                                                                          | must be re-ruled. **two** of its unbuilt codes already carry two severities each — `D-PARTIAL` _"keyed off the call site and not off the node kind"_, `D-RENAME` _"benign mangle = Advisory … collision suffix = Lossy"_. That is this axis, smuggled into severity twice before it had a name. | re-rule against §5; both two-severity hacks become one severity plus a computed effect                                                                                                              |
| 20  | Name collision                                                     | `jl4/app/L4/Cli/Common.hs:215-219` `hasBlockingError`                                                                                                                                            | unrelated (LSP `DiagnosticSeverity_Error`)                                                                                                                                                                                                                                                      | do not let the new vocabulary reuse the word "blocking"                                                                                                                                             |

**Not consumers**, verified negative — so the blast radius today is small, and this is the cheap
moment to do it:

```bash
grep -rni 'fidelity' jl4-service/src jl4-lsp/src ts-apps ts-shared .github   # → no L4.Interchange.Fidelity hits
grep -rn 'ToJSON\|FromJSON' jl4-core/src/L4/Interchange                      # → no output
```

There is **no** JSON instance, no TypeScript consumer, no OpenAPI schema, no CI job. The only
serialisation is `renderReport`'s plain text. `jl4/examples/dmn/README.md:150` says the service
surface (track S2) is still to come — after it ships, this change acquires a wire format and a
compatibility story.

---

## 4. The `--fail-on` surface

### 4.1 The gate type

```haskell
-- | What makes @l4 export@ exit non-zero. Two independent questions, because
-- the report answers two independent questions.
data FidelityGate = MkFidelityGate
  { gateSeverity :: Maybe FidelitySeverity  -- ^ threshold; 'Nothing' = never
  , gateEffects  :: [FidelityEffect]        -- ^ trip if any note has one of these
  }                                          --   a LIST, not a Set: see §3.2
  deriving stock (Eq, Show)

neverGate :: FidelityGate
neverGate = MkFidelityGate Nothing []

tripsGate :: FidelityGate -> [FidelityNote] -> Bool
tripsGate g ns =
  any (\n -> maybe False (n.severity <=) g.gateSeverity) ns
    || any (\n -> n.effect `elem` g.gateEffects) ns
```

The severity branch is exactly today's predicate; `jl4/tests-cli/Main.hs:942-1002` passes unchanged,
which is the point of not touching severity.

### 4.2 The command-line vocabulary

`--fail-on` accepts a comma-separated list; every current spelling keeps its current meaning.

| value                                     | trips when                                                               | status                                        |
| ----------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------- |
| `none` / `never`                          | never                                                                    | unchanged; **remains the default**            |
| `blocking` / `lossy` / `advisory` / `any` | severity threshold, `Blocking < Lossy < Advisory`                        | unchanged; documented as "almost always true" |
| `unevaluable`                             | any note with `effect = Unevaluable`                                     | new                                           |
| `incomplete`                              | any note with `effect = Incomplete`                                      | new                                           |
| `misstated`                               | any note with `effect = Misstated`                                       | new                                           |
| **`broken`**                              | `unevaluable,incomplete,misstated` — i.e. any note with `effect ≠ Sound` | new; **this is the CI gate**                  |
| `unevaluable,misstated`                   | union of the named selectors                                             | new                                           |

`fidelityGateReader` splits on `,`, folds each token into the record, and keeps its `other ->` error
branch so unknown selectors stay a usage error rather than a silent no-op.

### 4.3 The default, and why it does not change

**`l4 export` keeps exiting 0 by default.** Three reasons, in order of weight:

1. **The measured failure rate is too high to flip.** Under `--fail-on=broken`, 76.7% of DMN exports
   in this repo's own corpus would fail today (§4.4), and dmnmd would fail on 98.2% of them. A default-on gate would turn every existing invocation into a build break on upgrade, for
   defects that predate the flag.
2. `l4 export` is a rendering command as much as a checking command — it is how documentation
   examples and the paper's figures are produced. Renderers exit 0.
3. The gate's value is that it is _available_, not that it is _on_. The issue's complaint was never
   "the default is wrong"; it was "the useful gate does not exist".

**When to revisit.** When `--fail-on=broken` fires on under 5% of the corpus, flipping the default to
`broken` should be reconsidered, and this paragraph is the trigger condition. Getting there is
tracked as W3–W5 in §7.

### 4.4 What fraction of the corpus fails under the new gate

Stated honestly, because there are two numbers and only one of them is reachable by a vocabulary
change alone.

**(a) What the gate catches if `effect` is assigned per code and nothing else changes** — i.e. W1+W2
without W3. Computed from my own corpus run by mapping each note code through §5:

| selector                | dmn             | dmn-md          | bpmn          | ALL                  |
| ----------------------- | --------------- | --------------- | ------------- | -------------------- |
| `--fail-on=unevaluable` | 64/505 (12.7%)  | 0/505 (0%)      | 0/176 (0%)    | **64/1186 (5.4%)**   |
| `--fail-on=incomplete`  | 0/505 (0%)      | 496/505 (98.2%) | 14/176 (8.0%) | **510/1186 (43.0%)** |
| `--fail-on=misstated`   | 183/505 (36.2%) | 0/505 (0%)      | 0/176 (0%)    | **183/1186 (15.4%)** |
| **`--fail-on=broken`**  | 199/505 (39.4%) | 496/505 (98.2%) | 14/176 (8.0%) | **709/1186 (59.8%)** |

**(b) What the gate catches once `Unevaluable` is computed (W3)**, measured against the engine
oracle over its own 507-artifact run. (The two runs have slightly different DMN denominators — 505 vs
507 — because the full three-target sweep lost `charities-jersey-2014/part-1-interpretation.l4` and
`part-6-use-of-terms.l4` to the 180 s timeout, while the DMN-only sweep at 300 s exported both.
Every figure is quoted against the denominator it was measured over; the 0.4% difference moves
nothing.)

| selector                               | dmn                 |
| -------------------------------------- | ------------------- |
| `--fail-on=unevaluable` (engine truth) | **373/507 (73.6%)** |
| `--fail-on=misstated` (`D-SCOPE`)      | 185/507 (36.5%)     |
| **`--fail-on=broken`** (their union)   | **389/507 (76.7%)** |

Read those two tables together and the ruling's central claim is a number: **on the DMN target the
gate goes from 12.7% to 73.6% purely by computing a value the IR already holds** (`FeelFragment`),
without adding a single note code. The vocabulary change is what makes the gate _nameable_; W3 is
what makes it _true_.

Three further readings worth stating plainly:

- **BPMN gets a genuinely sharp gate: 8.0%.** `--fail-on=broken` there means `P-NOJOIN` and the four
  never-yet-fired shape notes. That is the shape of a gate someone would actually leave on in CI.
- **DMN's 76.7% is high, and that is a true statement about the artifacts**, not an artefact of the
  design. It is also the number that has to come down before §4.3's default flip can be
  reconsidered — which is exactly the pressure the current vocabulary removes by reporting the same
  98.9% for everything.
- **dmnmd's 98.2% is the axis's weakest showing**, for the reason argued in §2.3.

**Acceptance criterion for the implementation** — and the reason the oracle script should be
committed rather than thrown away: after W3, `--fail-on=broken` on the DMN target must agree with
`scratchpad/ruling/feeloracle.mjs` on the corpus to **≥95% precision and ≥95% recall**. If the
implemented gate lands at 15.8% recall, it has reproduced the current defect under a new name, and
the test will say so.

---

## 5. Every note code, classified

No code is left unassigned. `severity` is unchanged throughout — this table adds a column, it does
not move one. Line numbers are raise sites at `3b9bfc6e`. "computed" means the value is derived per
instance (§3.3, Rule A), not fixed by the code.

### 5.1 BPMN — `jl4-core/src/L4/Bpmn/Lower.hs`

| code                    | line       | severity | **effect**   | why, from the raise site                                                                                                                                                                                          |
| ----------------------- | ---------- | -------- | ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `F1`                    | 1145       | Blocking | `Sound`      | _"MUST, MAY and SHANT all draw as a task"_. The diagram is a correct diagram; BPMN has no deontic marking.                                                                                                        |
| `F2`                    | 817        | Lossy    | `Sound`      | lane ≠ bearer. A property of BPMN's swimlanes.                                                                                                                                                                    |
| `F3`                    | 1196       | Blocking | `Sound`      | _"BPMN has only one kind of 'did not happen'"_. Nothing is absent or wrong; a distinction is unrepresentable.                                                                                                     |
| `F4`                    | 1181       | Lossy    | `Sound`      | the guard **is** drawn, as an opaque `conditionExpression`; what is lost is _"whatever decision structure backed it"_.                                                                                            |
| `F5`                    | 834        | Advisory | `Sound`      | no as-of date in BPMN.                                                                                                                                                                                            |
| `P-DEADLINE`            | 1012, 1046 | Blocking | `Sound`      | both arms. The boundary event exists and carries the source's own text; in a document that declares `isExecutable="false"` (§1.7) "not a machine-checkable timer" is a capability loss, exactly like `F1`.        |
| `P-DEADLINE-UNIT`       | 1025       | Advisory | `Sound`      | **closest call in the table.** BPMN's timer has no unit-free form, so any drawing must choose; the note says it chose and `--deadline-unit=refuse` refuses instead. Choosing and saying so is not a misstatement. |
| `P-DANGLING`            | 304        | Advisory | `Sound`      | its own `lost` field: _"nothing the source said; this is an artefact of extraction"_.                                                                                                                             |
| `P-NOJOIN`              | 603        | Lossy    | `Incomplete` | no converging gateway is drawn — the conjunction has no counterpart element. The note argues drawing one would deadlock, i.e. `Misstated` would be worse.                                                         |
| `P-CYCLE`               | 783        | Lossy    | `Incomplete` | _"BPMN can draw a loop, but this LAYOUT does not"_ — the back edge has no counterpart.                                                                                                                            |
| `P-DEADLINE-UNDRAWN`    | 278        | Lossy    | `Incomplete` | a `WITHIN` with no inferable expiry target is not drawn at all.                                                                                                                                                   |
| `P-MULTI-HENCE`         | 722        | Blocking | `Misstated`  | >1 `HENCE` off one state; the drawn shape is not the source's.                                                                                                                                                    |
| `P-JUNCTION-OBLIGATION` | 754        | Blocking | `Misstated`  | both a junction and an obligation; _"neither is what the source says"_.                                                                                                                                           |

**No BPMN note is `Unevaluable`** — see §1.7. `--fail-on=broken` on BPMN therefore means
"`P-NOJOIN`, `P-CYCLE`, `P-DEADLINE-UNDRAWN`, `P-MULTI-HENCE` or `P-JUNCTION-OBLIGATION`", which is
rare and actionable.

### 5.2 DMN 1.3 XML — `jl4-core/src/L4/Dmn/Lower.hs`

| code                | line                             | severity | **effect**                                                                         | why                                                                                                                                                         |
| ------------------- | -------------------------------- | -------- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D-NONFEELOUTPUT`   | 1317 (helper), called 1430, 1664 | Blocking | `Unevaluable` (computed)                                                           | already gated on `feFragment == L4Verbatim`; its own message says _"NO DMN engine can evaluate it"_.                                                        |
| `D-NONFEELINPUT`    | 1364                             | Blocking | `Unevaluable` (computed)                                                           | same gate, input side.                                                                                                                                      |
| `D-LITERALEXPR`     | 1683                             | Blocking | **computed** — `Unevaluable` iff `rendered.feFragment == L4Verbatim`, else `Sound` | the ruling's load-bearing case. 494 exports, 75.1% precision against the engine (§1.5); the note is about analysability, the effect is about executability. |
| `D-SCOPE`           | 1599                             | Lossy    | `Misstated`                                                                        | 185/507 artifacts, TP=185 FP=0 FN=0 against duplicate `inputData/@name` (§1.6). The model runs and reads the wrong variable.                                |
| `D-NONFEEL`         | 1375                             | Advisory | `Sound`                                                                            | valid FEEL outside S-FEEL. Level-3 conforming, which is the level the artifact claims.                                                                      |
| `D-COMPUTEDOUTPUT`  | 1411                             | Advisory | `Sound`                                                                            | explicitly mutually exclusive with `D-NONFEELOUTPUT` (`:1418-1421`); what is lost is analysis.                                                              |
| `D-ORDERDEPENDENT`  | 1395                             | Advisory | `Sound`                                                                            | hit policy `F`; DMN 1.3 §8.2.10 permits it and warns about manual validation.                                                                               |
| `D-HITPOLICY`       | 1389                             | Advisory | `Sound`                                                                            | the guards **are** disjoint; only the columns cannot witness it.                                                                                            |
| `D-UNDECOMPOSABLE`  | 1343                             | Advisory | `Sound`                                                                            | boolean column; the table still answers. If the guard is also L4 text, `D-NONFEELINPUT` fires alongside.                                                    |
| `D-INLINEDLOCAL`    | 1439                             | Advisory | `Sound`                                                                            | the value is inlined, so the answer is unchanged; the drafter's **name** is lost.                                                                           |
| `D-FLATTENCAP`      | 1448                             | Advisory | `Sound`                                                                            | the nested chain stays in the output expression; the rows, not the logic, are lost.                                                                         |
| `D-LIFTEDTHRESHOLD` | 1456, 1653                       | Advisory | `Sound`                                                                            | threshold moves inside `min`/`max`; same answer, worse for a compliance reader.                                                                             |

### 5.3 dmnmd markdown — `jl4-core/src/L4/Dmn/Markdown.hs`

| code                  | line     | severity | **effect**   | why                                                                                                                                                                                   |
| --------------------- | -------- | -------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D-MD-NOLITERAL`      | 260      | Blocking | `Incomplete` | its own `lost`: _"the decision itself; it is omitted from the markdown"_. `renderDecision` returns `Nothing` (`Markdown.hs:79-84`).                                                   |
| `D-MD-NONIDENTCOLUMN` | 269      | Blocking | `Incomplete` | _"so this table is omitted"_ / `lost: the whole table`.                                                                                                                               |
| `D-MD-CELLSYNTAX`     | 279      | Blocking | `Incomplete` | same.                                                                                                                                                                                 |
| `D-MD-NODRG`          | 248      | Blocking | `Sound`      | **the other close call.** Every decision survives; only the graph picture is absent, and which decision feeds which is recoverable from the column names. Dissent recorded in §6, Q2. |
| `D-MD-NODEFAULT`      | 286      | Lossy    | `Sound`      | `OTHERWISE` becomes a final catch-all row and `U` demotes to `F`; the answers are preserved, _"the order-free reading"_ is not.                                                       |
| `D-MD-TYPE`           | 295, 304 | Lossy    | `Sound`      | a declared domain narrows to String/Number/Boolean/List. Valid inputs still answer the same.                                                                                          |

### 5.4 Summary

| effect                                           | codes               | of which Blocking | of which Lossy | of which Advisory |
| ------------------------------------------------ | ------------------- | ----------------- | -------------- | ----------------- |
| `Sound`                                          | 19                  | 4                 | 4              | 11                |
| `Unevaluable`                                    | 2                   | 2                 | 0              | 0                 |
| `Incomplete`                                     | 6                   | 3                 | 3              | 0                 |
| `Misstated`                                      | 3                   | 2                 | 1              | 0                 |
| computed — `Sound` or `Unevaluable` per instance | 1 (`D-LITERALEXPR`) | 1                 | 0              | 0                 |
| **total**                                        | **31**              | **12**            | **8**          | **11**            |

The off-diagonal cells are the evidence that the axes are independent: 4 `Blocking`+`Sound` codes
(including `F1`, the most frequent note in the BPMN corpus) and 1 `Lossy`+`Misstated` code
(`D-SCOPE`, 461 instances). If severity determined effect, this table would be diagonal, and the
issue would have no subject.

---

## 6. Not decided

**Q1 — should the fault axis exist at all, later?** Declined here for the reasons in §2.2, but the
need is real: a reader wants to know whether to file a bug against `l4` or edit their `.l4`. **What
would decide it:** a consumer that actually routes notes to different addressees — the service
surface (track S2) opening issues automatically, or an LSP code action offering a fix. Until such a
consumer exists, the fault distinction lives in the `message` prose, where it already is. If it is
built, note that the corpus needs four values (target / this exporter / the L4 language /
this module), not the issue's three, and that `Dmn/IR.hs:447-467`'s `FidelityLoss` is already a
partial fourth-value carrier for the decision side.

**Q2 — is `D-MD-NODRG` really `Sound`?** §5.3 rules `Sound` on the ground that the requirements are
recoverable from column names; the note's own text says the opposite (_"which decision feeds which
is invisible"_). **What would decide it:** take a multi-decision module, export dmnmd, and try to
reconstruct the DRG from the markdown alone. If the reconstruction is ambiguous, it is `Incomplete`,
and dmnmd's `broken` rate goes from ~98% to ~100%, which changes nothing operationally — which is
why the ruling does not wait for the answer.

**Q3 — how close does the computed effect get to the engine?** §1.4's oracle says 73.6% of DMN
exports are broken. Rule A computes `Unevaluable` from `feFragment == L4Verbatim`, and I did **not**
instrument the exporter to measure how much of the 73.6% that flag reaches. Two known gaps: (a) 34
artifacts (6.7%) have `UNBOUND` but no `SYNTAX` error, several of which are module-qualified
references such as `Eligibility Rules.age >= 18` that may well render as `FullFeel`; (b) an
earlier instrumented pass in this session reported 351/507 = 69.2% of exports carrying ≥1
`L4Verbatim` boxed literal — **a number I did not reproduce and do not vouch for**. **What would
decide it:** implement Rule A, run `feeloracle.mjs`, and compare. That comparison is the acceptance
criterion in §4.4, so the question is scheduled rather than open.

**Q4 — does an `UNBOUND` name deserve its own code?** The oracle found 637 expressions referencing
names the model never defines. Some are raw L4 that the fragment flag will catch; some are genuine
name-resolution failures the exporter does not currently notice at all (`TIMEZONE`, `Jurisdiction
Library.Country Codes _ ISO 3166_1.Sweden`). If Rule A leaves recall short, the fix is a new code —
call it `D-UNRESOLVED` — computed by checking each emitted expression's free names against the
model's own `inputData`/decision names, which is a static check the exporter can do in one pass.
**What would decide it:** Q3's number.

**Q5 — should the severity thresholds be deprecated outright?** §4.2 keeps them and documents
`blocking` as "almost always true". The pandoc precedent (§2.3) argues for demoting the
target-cannot-express notes instead, which would make `--fail-on=blocking` meaningful again.
**What would decide it:** whether anyone reaches for `--fail-on=blocking`, is misled, and says so.
That is a usage question and cannot be settled from the corpus.

**Q6 — what happens when the report gets a wire format?** There is no `ToJSON` today (§3.4). When
track S2 ships one, `effect` needs a stable spelling, and the SARIF mapping is close enough to be
worth taking: `effect = Sound` → `kind: "informational"` with `level: "none"`, everything else →
`kind: "fail"` with `level` from severity. **What would decide it:** whoever specifies the service
endpoint. Recording the mapping here so it is not re-derived.

**Explicitly out of scope.** Setting `expressionLanguage` on non-FEEL literal expressions so the
artifact stops claiming to be FEEL (§1.4) is a real fix and a good one — it would make the emitted
model honestly Level-1 rather than dishonestly Level-3 — but it is an exporter change, not a
vocabulary change, and it belongs with the DMN program-model work.

---

## 7. Work items

In dependency order. W1–W2 are the vocabulary; W3 is the part without which the gate lies.

| id  | work                                                                                                                        | where                                                                                  |
| --- | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| W1  | `FidelityEffect` + the `effect` field + `Enum`/`Bounded` on both enums; move the `Ord` comment onto the type                | `Fidelity.hs`                                                                          |
| W2  | thread the field through the 3 helpers positionally; answer all 32 sites per §5                                             | `Dmn/Lower.hs`, `Dmn/Markdown.hs`, `Bpmn/Lower.hs`                                     |
| W3  | **Rule A at `literalFallback`** — the 84.2% recall gap                                                                      | `Dmn/Lower.hs:1681-1692`                                                               |
| W4  | `FidelityGate` record, comma-list reader, `broken` alias, `tripsGate`                                                       | `Export.hs:101-106`, `139-150`, `406-415`                                              |
| W5  | tally + "broken codes" stderr line; `[minBound..maxBound]`                                                                  | `Export.hs:365-387`                                                                    |
| W6  | reword the notes whose `lost` text promises engine-evaluability on a document that declares `isExecutable="false"`          | `Bpmn/Lower.hs:1012-1056`                                                              |
| W7  | re-bless 5 goldens; add effect assertions beside the 29 severity ones; add `--fail-on=broken` CLI rows                      | `jl4/examples/**/expected/*`, `jl4/tests/{Dmn,Bpmn}Export.hs`, `jl4/tests-cli/Main.hs` |
| W8  | commit `feeloracle.mjs` as a corpus-level acceptance test and wire §4.4's ≥95%/≥95% criterion                               | new, under `jl4/tests-cli/` or `scripts/`                                              |
| W9  | re-rule `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7's 8 unbuilt codes; collapse the `D-PARTIAL` and `D-RENAME` two-severity hacks | `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md:1065-1077`                                |
| W10 | docs: `Fidelity.hs` header, `Export.hs` haddock, both example READMEs                                                       | as listed in §3.4 #18                                                                  |

---

## 8. Provenance

Scripts and data for every number above, under
`/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/`:

| file                       | what it produced                                                                  |
| -------------------------- | --------------------------------------------------------------------------------- |
| `run_corpus.py`            | `ruling/mycorpus.jsonl` — the full sweep behind §1.3                              |
| `ruling/analyse.py`        | the frequency and gate tables in §1.3                                             |
| `ruling/sweep_dmn.py`      | `ruling/art/` — 507 retained DMN artifacts + sidecars                             |
| `ruling/feeloracle.mjs`    | `ruling/oracle.jsonl` — the FEEL verdicts in §1.4, and the controls               |
| `feel/node_modules/feelin` | 7.0.1, `github.com/nikku/feelin`                                                  |
| `dmn13.txt`                | `pdftotext -layout` of OMG DMN 1.3 (`formal/20-06-01`); §7.3.5 at lines 3009–3021 |
| `bpmn20.txt`               | `pdftotext -layout` of OMG BPMN 2.0; §2.1 conformance sub-classes                 |
| `sarif.txt`                | tag-stripped OASIS SARIF v2.1.0 errata01; `kind` at §3.27.9, `level` at §3.27.10  |

**Every number in §1 was produced by a command run for this document**, against a clean tree, with
the command shown. Two exceptions, both flagged where they appear:

- the instrumented `L4Verbatim` count (351/507 = 69.2%) quoted in §6 Q3 — measured by an earlier pass
  in this session, **not reproduced here, and not vouched for**; it appears only as corroboration for
  a question that is explicitly left open;
- the claim in `jl4/tests/DmnExport.hs:900-904` that these shapes were verified against Drools/KIE
  8.44.0.Final — _"loudly for an input expression or a firing rule, SILENTLY (null, status SUCCEEDED)
  for a defaultOutputEntry"_. That is a test comment written by someone else. It corroborates the
  FEEL oracle with a second, JVM engine, and it independently supports the `Unevaluable` /
  `Misstated` distinction (loud vs silent), but it is not my measurement.

**Known limit of the corpus figures.** Ten files — `jl4/experiments/jerseyCharities.l4` and the nine
under `paper/case-studies/charities-jersey-2014/` — exceed a 180 s export timeout and are excluded
from §1.3, not measured. (Two of them do appear in §1.4's DMN-only sweep, which ran at 300 s.) They are the largest statutes in the corpus, so if their exports
are unusually broken the DMN and dmnmd rates are understated. Raising the timeout and re-running is
cheap and would close this.
