# Fidelity Notes: `Blocking` Is Two Different Facts

_Status: **ruling, not yet implemented.** Written 2026-07-27 on branch
`docs/fidelity-severity-axis`, against `3b9bfc6e`; **revised 2026-07-27 after adversarial review**
(three lenses: independent re-execution, attack-the-ruling, consumer/house-style enumeration).
Resolves smucclaw/l4-ide#928, which raised the question and explicitly declined to answer it.
Nothing in `jl4-core/src/L4/Interchange/Fidelity.hs` has been changed by this document._

> **The review changed the substance, not just the wording.** Thirty-five distinct findings, all
> dispositioned in **[§9](#9-review-findings-and-their-disposition)**, which is the index to read
> first if you have seen the previous draft. Four changed the ruling: the enum gained a **fifth**
> value (`Malformed`), `Sound` was renamed **`Faithful`**, the claim that the cheapest option was
> _impossible_ was **false and is withdrawn**, and the work item that makes the gate true was
> re-specified into a **three-line change that ships alone**. Two notes were reclassified
> (`D-SCOPE`, `P-CYCLE`). Three findings were **rejected on measurement**, and the measurements are
> in §9. One new external oracle was run for the revision (`bpmnlint`, §1.8) and found a defect no
> fidelity note reports.

**Author:** Meng Wong, with measurement and analysis from Claude
**Component:** `jl4-core/src/L4/Interchange/Fidelity.hs`; the three backends that construct notes
(`L4/Dmn/Lower.hs`, `L4/Dmn/Markdown.hs`, `L4/Bpmn/Lower.hs`); `jl4/app/L4/Cli/Export.hs`
(`--fail-on`, the exit code)
**Related:** legalese/l4-ide#154 (`l4 export`, which forced the question);
`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` (§7 queues 7 new codes and 1 repurpose, and must be
re-ruled against §5 below — with the conflict in §3.4 #19 resolved first);
`specs/todo/lexipedia-superset/SPEC.md` (K4, and **K8**, which commits to two engines and a DMN
flavour per ecosystem — see §3.1 and W12); `specs/todo/lexipedia-superset/PROCESS-TRACK.md` §5
(defines F1–F5); `specs/todo/lexipedia-superset/CORPUS-TRACK.md` (the review-disposition convention
this document follows)
**Classification:** Tier-2 — interchange/DX, small blast radius today, large one once the service
surface (track S2) ships.

**One-line ruling.** Add a second, **orthogonal** field to `FidelityNote` — not "whose fault" but
**what the emitted document now is** — with five values
`Faithful | Unevaluable | Malformed | Incomplete | Misstated`, deriving no `Ord`, carried **per note
instance** and answered by the producer under `-Werror`; and give the CLI a second flag,
`--fail-on-effect`, whose useful member is `--fail-on-effect=broken`. `FidelitySeverity` is not
touched. The default exit behaviour stays 0.

**The finding that moves the ruling** is not the one the issue leads with. The issue says `Blocking`
is unusable because it fires on every export. It does — 98.6% of DMN exports, measured below. But the
larger fact is that **the information a CI gate needs is not in the report at all, under any code.**
Handed to a real FEEL engine, 73.6% of the DMN artifacts this repo produces contain at least one
expression that engine cannot evaluate; the two note codes whose own message text says "NO DMN engine
can evaluate it" find **15.8% of them**. So this is not only a vocabulary problem. It is
approximately one-sixth vocabulary and five-sixths missing computation, and a ruling that only
renames severities would ship a gate that lies.

**What the ruling does _not_ claim** (the first draft did, and was wrong — §9 F-A4): that the
cheapest option, "let consumers filter by note code", is impossible. It is not. Measured today,
`D-NONFEELOUTPUT ∨ D-NONFEELINPUT ∨ D-SCOPE` is a **more precise** predicate than the shipped
`--fail-on=blocking` (90.5% vs 74.6%), and after the three-line fix in §3.3 a code list converges on
what the new field would compute — because both read the same `FeelFragment`. The new field wins on
**who is forced to answer when a code is added**, not on accuracy. That is a weaker argument than the
first draft made, and it is the one that survives measurement.

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

> That grep is itself a **consumer of the rendered format**, and W7 breaks it: once `renderNote`
> prints the effect word, `] blocking — ` no longer matches and the counts silently go to zero.
> This is recorded as a migration item rather than left as a trap — §3.4 #1, and §9 F-A7.

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

**2080 export attempts → 1186 artifacts** (dmn 505, dmn-md 505, bpmn 176). The other **894** attempts
produced no artifact, and they partition exactly — the first draft's decomposition summed to 924 and
mislabelled its largest bucket (§9 F-C2):

```bash
python3 scratchpad/repair/nonartifacts.py scratchpad/ruling/mycorpus.jsonl
```

| why no artifact                                | bpmn | dmn | dmn-md | total   |
| ---------------------------------------------- | ---- | --- | ------ | ------- |
| module has no regulative rule (BPMN only)      | 510  | —   | —      | 510     |
| typecheck / other export error                 | 79   | 79  | 79     | 237     |
| module has no decisions (DMN targets only)     | —    | 45  | 45     | 90      |
| >1 regulative rule and no `--rule` disambiguat | 27   | —   | —      | 27      |
| timeout at 180 s                               | 10   | 10  | 10     | 30      |
| **total**                                      | 626  | 134 | 134    | **894** |

The 30 timeouts are inside those columns, not additional to them. They are ten files × three targets;
see §8 for which files, and for the load-dependence of that set.

> **Measured before 2026-07-30.** Three codes postdate this census — `D-RULEDATE`,
> `D-RULEDATE-UNBOUND` and `D-DATEDCHAIN` (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15) — and have no row
> here; no EXPORTS/FILES/INSTANCES figures are invented for them. The "never fired" list below is a
> claim about the **31 codes that existed when the census was taken**, not about the code set today.

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
character. Counted over all **507** retained DMN artifacts — including the one dotfile artifact a
plain `ls art/*.dmn` skips, which is why the first draft's counts were one file short (§9 F-C1):

```bash
python3 scratchpad/repair/elements.py scratchpad/ruling/index.jsonl
# decision 4590  literalExpression 4348  decisionTable 242  inputData 3381
```

- **`D-LITERALEXPR` 4253 instances, and 94.7% of decisions are boxed literal expressions.** 4590
  `<decision>`, 4348 `<literalExpression>`, 242 `<decisionTable>`. The DMN backend produces decision
  _tables_ for one decision in twenty.
- **`D-MD-NOLITERAL` 4269 instances against those 4590 decisions — ~93% of decisions are omitted from
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
gate. As information: the `--fail-on=blocking` indicator on the DMN target carries
**H = 0.105 bits**, against a maximum of 1.

### 1.4 The external oracle — the measurement this ruling turns on

The previous sections measure what the exporter _says_. This one measures what the artifact _is_,
using something that is not ours.

**Why FEEL is the right oracle, and why the artifact is on the hook for it.** DMN 1.3 §7.3.5
(OMG **`formal/2021-01-01`**, March 2021 — read from the OMG PDF via `pdftotext -layout`, document
number at line 10 and §7.3.5 at lines 3009–3021 of the extracted text):

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
needed, it is flagged. **`feelin` is a proxy, not one of the two engines K8 commits to** — see §3.1
and W12.)

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
Library.Country Codes _ ISO 3166_1.Sweden`. It is also not inflated by unbindable inputs: there are
**zero** self-closing `<inputData/>` elements across the 507 artifacts, so every model-defined name
the oracle could bind, it bound.

**Where the 373 broken expressions sit, which is what makes §3.3 shippable.** Bucketing the broken
expressions by the element they came from:

```bash
python3 scratchpad/repair/bykind.py scratchpad/ruling/oracle.jsonl
```

| element kind                | broken expressions | broken artifacts reachable from it alone |
| --------------------------- | ------------------ | ---------------------------------------- |
| boxed `<literalExpression>` | 3140               | **364 of 373 — 97.6%**                   |
| `<outputEntry>`             | 262                | +2 → 366 (98.1%)                         |
| `<inputExpression>`         | 198                | +7 → 373 (100%)                          |
| `<inputEntry>`              | 0                  | —                                        |

**Only 9 broken artifacts (1.8%) have no broken boxed literal at all.** That is the number §3.3 needs
and the first draft did not have.

### 1.5 What the current report predicts, against that oracle

This is the table the ruling rests on. Each row is a predicate a consumer could write today; scored
against `SYNTAX ∪ UNBOUND` as ground truth, over the 507 DMN exports.

```bash
python3 scratchpad/repair/verify.py scratchpad/ruling/oracle.jsonl
```

| predicate available today                              | fires       | precision | recall    |
| ------------------------------------------------------ | ----------- | --------- | --------- |
| `--fail-on=blocking` (≥1 blocking note)                | 500 (98.6%) | 74.6%     | 100.0%    |
| `--fail-on=advisory` (≥1 note at all)                  | 504 (99.4%) | 74.0%     | 100.0%    |
| code ∈ {`D-NONFEELOUTPUT`, `D-NONFEELINPUT`}           | 65 (12.8%)  | 90.8%     | **15.8%** |
| code = `D-LITERALEXPR`                                 | 494 (97.4%) | **75.1%** | 99.5%     |
| code = `D-SCOPE`                                       | 185 (36.5%) | 91.4%     | 45.3%     |
| **code ∈ {`D-NONFEEL*`} ∪ {`D-SCOPE`}** — best by code | 201 (39.6%) | **90.5%** | 48.8%     |

Four readings, all load-bearing:

1. **The severity axis carries no actionable information.** `--fail-on=blocking` has perfect recall
   and fires on 98.6% of exports; it is the predicate `True` with extra steps. A severity that is
   always at its maximum is equivalent to no severity — the issue's words, now with a number, and
   with an entropy: 0.105 bits.
2. **The codes that _claim_ to mark unevaluable output find one in six of them.** 314 of the 373
   broken artifacts (84.2%) carry no `D-NONFEEL*` note at all; 189 of those carry `D-LITERALEXPR`
   alone.
3. **`D-LITERALEXPR` is right three times in four, and that is the whole problem in one code.** It
   fires on 494 exports; on **123** of them the artifact is perfectly evaluable. Its own message says
   what it means — _"is not a guarded chain (IF / BRANCH / CONSIDER), so it has no rows, so it is
   emitted as a boxed literal expression rather than a decision table"_, lost: _"every
   decision-table analysis"_. That is a statement about **analysability**, and it is being asked to
   stand in for **executability**.
4. **The best predicate available by code today is already better than the shipped gate** — 90.5%
   precision against 74.6%. This is the row that killed the first draft's "direction 3 is
   impossible" (§2.2, §9 F-A4). What the code-based predicate lacks is _recall_, and recall is not
   a vocabulary problem: it is the missing raise site in §3.3.

The single `Blocking` note in the shipped `reg-cf` golden is exactly this: `D-LITERALEXPR` on
`decision_combined_resources`, whose artifact is
`<literalExpression id="decision_combined_resources_literal"><text>annual income + net worth</text></literalExpression>`
— valid FEEL, and one of the 32 expressions the oracle scored `OK`. **The project's flagship
`Blocking` note is on a document a DMN engine runs correctly.**

The codebase already knows this distinction, and states it in prose **four** times — the first draft
said twice, and undercounted (§9 F-C6). `Dmn/Lower.hs:1418-1421`, on the exclusion between
`D-COMPUTEDOUTPUT` and `D-NONFEELOUTPUT`:

```haskell
-- MUTUALLY EXCLUSIVE with D-NONFEELOUTPUT. An L4Verbatim entry satisfies
-- `not . isConstantText` too, and used to be reported by this Advisory
-- note alone -- a note about ANALYSABILITY standing in for a failure of
-- EXECUTABILITY. That is the defect this split fixes.
```

and `Dmn/Lower.hs:793-794`, on why record construction is not lowered:

> Each of those turns an honest Blocking note into a silently wrong answer reported Advisory, which
> is strictly worse than not lowering at all.

and `Bpmn/Lower.hs:490-491`, on why `P-NOJOIN` is not demoted:

> `P-NOJOIN` at `Lossy` is safe in every case; an Advisory that misfires is the one note a reader
> stops reading after.

and `jl4/tests/BpmnExport.hs:1103`, which is the issue with the serial number filed off:

> every F1 is Blocking, so severity cannot be what marks a prohibition

Every one of those four is the effect axis, written in severity vocabulary because no effect axis
existed. The `D-NONFEELOUTPUT` split was applied at `Dmn/Lower.hs:1430` (table path) and `:1664`
(select-idiom path). It was **not** applied at `literalFallback` (`:1681-1692`), which is the path
94.7% of decisions take. That omission, not the vocabulary, is what §3.3 fixes.

Reproducible in one command on the clean binary:

```bash
l4 export --to=dmn doc/reference/functions/let-example.l4 -o /tmp/x.dmn --fidelity-report
```

reports 10 × `D-LITERALEXPR` and 1 × `D-NONFEELOUTPUT`; the `D-NONFEELOUTPUT` is on
`decision_factorial_of` (the table path), while `decision_shifted_point_example` — the one carrying
raw L4 into a `<text>` element — is reported **only** as `D-LITERALEXPR`.

### 1.6 `D-SCOPE`: the note that makes the artifact invalid, not merely wrong

The first draft classified this note `Misstated` on the strength of a sentence it had not measured —
_"the model parses, loads, runs, and answers using whichever binding the engine picked"_. That
sentence is **withdrawn** (§9 F-A1). No oracle in this document can support it: `feelin` binds each
name once, so a duplicate is invisible to it, and nothing here ran a DMN engine over a model with
duplicate names. What can be measured is the artifact, and what can be quoted is the spec.

**What the spec says.** DMN 1.3 §7.3.4, _InformationItem metamodel_, `dmn13.txt:2971`:

> The name of an `InformationItem` element **SHALL** be unique within its scope.

and §6.3, on the FEEL mapping of DRG elements, `dmn13.txt:2654-2656`:

> To avoid name collisions and ambiguity, the name of a variable must be unique within its scope.
> When DRG elements are mapped to FEEL, the name of a variable is the same as the (possibly
> qualified) name of its associated input data or decision, **which guarantees its uniqueness.**

The exporter breaks the construction the spec names as the guarantee.

**What the artifacts do.**

```bash
python3 scratchpad/repair/scope.py scratchpad/ruling/index.jsonl
```

- **185 of 507 artifacts emit a duplicate `inputData/@name`; `D-SCOPE` fires on exactly those 185.
  TP=185, FP=0, FN=0.** 3381 `<inputData>` elements over the corpus.
- **All 185 also carry a duplicate `<variable>/@name`** — the emitter writes a `<variable>` child per
  `inputData` (`Dmn/Emit.hs:135-145`), so the collision is in the FEEL name space, not merely in a
  label.
- **In 184 of the 185, at least one of the duplicated names appears inside a `<text>` expression** —
  the ambiguity is live, not latent. The single exception is `jl4/examples/ok/tdnr.l4`, where the
  duplicated name (`Type-directed name resolution.foo`) is defined twice and referenced nowhere.

**The ruling.** An artifact that violates a normative `SHALL` of its own target notation is not
"running and answering wrongly" — it is a document about whose behaviour the notation declines to
say anything. Neither `Unevaluable` (the _text_ is fine FEEL) nor `Misstated` (which asserts the
artifact evaluates) describes it. That is why the enum gains **`Malformed`** (§3.1), whose third-party
check is schema plus normative-constraint validation rather than evaluation — a check that is
cheaper than an engine, applies to BPMN as well as DMN, and would have caught this without anyone
arguing about engines.

`D-SCOPE` is also the counter-example that kills **"gate on severity"**: a consumer filtering
`severity == Blocking` today gets 4269 dmnmd omission notes it may not care about **and misses every
artifact whose FEEL names are ambiguous.** (The first draft aimed that sentence at "filter by code",
where it does not land — by code, `D-SCOPE` is a flawless predicate. §9 F-A4.)

### 1.7 BPMN: no note is `Unevaluable`, and that is our attribute's doing, not BPMN's

```bash
grep -n 'isExecutable' jl4-core/src/L4/Bpmn/Emit.hs
#   12:-- * @isExecutable=\"false\"@. This is a description of a rule, not a deployable
#   98:      , ("isExecutable", "false")
grep -o 'isExecutable="[a-z]*"' jl4/examples/bpmn/expected/*.bpmn   # → false, false, false
```

`isExecutable="false"` is a literal at `Emit.hs:98`. Every BPMN document this exporter has ever
produced declares itself non-executable, in BPMN's own vocabulary. BPMN 2.0's conformance chapter
distinguishes the sub-classes at `bpmn20.txt:1263` (in §2.1's introduction, before §2.1.2 begins at
:1269): _"Common Executable focuses on what is needed for executable process models."_ The sentence
_"This conformance sub-class is intended for modeling tools that can emit executable models."_ is at
`bpmn20.txt:1456`, under the sub-heading **Common Executable Conformance Sub-Class** inside §2.1.2 —
**not** §2.1.4, which is "Structural Conformance" (:1594). The first draft mis-cited both (§9 F-C2).

Table 10.1, on `isExecutable` (`bpmn20.txt:7455` heading, text at :7464-7468) — the **complete**
sentence, which the first draft truncated at a page break that does not exist (§9 F-C3):

> A non-executable Process is a private Process that has been modeled for the purpose of documenting
> Process behavior at a modeler-defined level of detail. Thus, information needed for execution, such
> as formal condition expressions are **typically** not included in a non-executable Process.

**"Typically."** BPMN does not forbid evaluating a non-executable process; it observes a habit. So
the honest statement is narrower than the first draft's:

> **No BPMN note is `Unevaluable`, because our exporter hardcodes `isExecutable="false"`** — not
> because BPMN says a non-executable process cannot be evaluated.

This matters because `lexipedia-superset/SPEC.md` K4 says _"BPMN export targets Camunda import.
Their authoring flow is already Camunda Modeler → paste XML"_, and a Camunda user's next action is
to flip that attribute. **The assertion and this cross-reference belong at `Emit.hs:98`** (W6), or
the BPMN column of §5.1 becomes silently wrong the day someone adds `--executable`.

Notes whose `lost` text is about machine-evaluability — `P-DEADLINE`'s _"the trigger as something an
engine could evaluate"_ — are describing a capability the artifact does not currently offer; those
texts should be reworded (§7, W6).

Element-level check on the shipped goldens:

```bash
for b in jl4/examples/bpmn/expected/*.bpmn; do f=${b%.bpmn}.fidelity.txt;
  printf '%s tasks=%s F1=%s\n' "$(basename $b)" \
    "$(grep -oc '<bpmn:task\|<bpmn:userTask' $b)" "$(grep -c '^  \[F1\]' $f)"; done
# consultation tasks=3 F1=3 / handover tasks=5 F1=5 / offering tasks=5 F1=5
```

`F1` fires once per task, exactly — **3, 5 and 5**, thirteen across the three goldens, not thirteen
in one of them (§9 F-C4). The issue's characterisation is correct and the note is correct; it is the
severity that is wrong to gate on.

### 1.8 A BPMN oracle, run for this revision — and what it found

The first draft classified all 13 BPMN notes by reading their raise sites, with no external check. A
reviewer called that out. `bpmnlint` — the linter `bpmn-js`, and therefore Camunda Modeler, is built
around — installs and runs:

```bash
npm install bpmnlint@11.12.1 bpmn-moddle          # scratchpad/repair/bl/
echo '{ "extends": "bpmnlint:recommended" }' > .bpmnlintrc
npx bpmnlint jl4/examples/bpmn/expected/*.bpmn
```

| golden       | problems as shipped | after adding `<incoming>`/`<outgoing>` |
| ------------ | ------------------- | -------------------------------------- |
| consultation | 20 errors           | 1 error                                |
| handover     | 36 errors           | 1 error, 1 warning                     |
| offering     | 35 errors           | 1 error, 2 warnings                    |

**91 errors across the three shipped exhibits, and 88 of them have one cause that no fidelity note
reports.** The exporter emits `<bpmn:sequenceFlow sourceRef=… targetRef=…>` but never
the reciprocal `<bpmn:incoming>` / `<bpmn:outgoing>` reference children on flow nodes. Every tool
that navigates by those references — `bpmn-moddle`, hence `bpmn-js`, hence Camunda Modeler — sees a
graph with no edges, and reports every node `no-disconnected` / `no-implicit-start` /
`no-implicit-end`. Adding exactly those references and nothing else (14, 30 and 30 of them,
via `bpmn-moddle`, `scratchpad/repair/bl/patch3.mjs`) collapses the counts to 1, 2 and 3.

**Is that a spec violation?** No — and it is important to say so rather than assume. BPMN 2.0
Table 8.52 (`bpmn20.txt:5533-5535`) gives `incoming: Sequence Flow [0..*]` and
`outgoing: Sequence Flow [0..*]`, and Table 8.57's XSD (`bpmn20.txt:5603-5610`) declares both with
`minOccurs="0"`. Omitting them is schema-legal. So this is **not** a `Malformed` instance; it is an
interop defect against the exporter's own stated target, invisible to every gate this document
proposes, because no note reports it. It is filed as W13 and it is the reason §5.1 is marked
_classified by reading, corroborated where the linter overlaps_.

**Where the linter does overlap, it agrees with us.** The residue after the patch is:

- `label-required` on `Start_0`, once per file — a lint style opinion, no fidelity note owed;
- **`fake-join` — _"Incoming flows do not join"_ — on `End_3` (handover) and `End_3`/`End_4`
  (offering).** That is `P-NOJOIN` seen from the other end: the linter names the node where the
  unjoined flows converge, the note names the `Split_1` whose conjunction was never closed. It
  fires on **exactly** the two goldens the note fires on
  (`grep -n 'P-NOJOIN' jl4/examples/*/expected/*.fidelity.txt` → `offering.fidelity.txt:32`,
  `handover.fidelity.txt:32`; `consultation` has neither), found by a tool that has never read our
  source. One external confirmation of one BPMN classification is not thirteen, but it is the one
  that carries the whole 8.0% BPMN gate (§4.4).

### 1.9 Where the measurement contradicts the issue

| the issue says                                                               | the measurement says                                                                                                                                                                                                                                           |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "`Blocking` fires on 100% of exports"                                        | 98.6% of DMN, and 5/5 shipped goldens. The exceptions are degenerate modules. Substantively right, literally wrong; a gate on it is unusable.                                                                                                                  |
| the second axis is **whose fault** (target / exporter / artifact)            | fault is not what CI can act on, no comparable tool ships it, and the corpus needs **four** fault values, not three. Declined — see §2.2.                                                                                                                      |
| direction 3, "let consumers filter by note code", is merely cheap-but-untidy | **the issue is right and the first draft of this spec was wrong.** By code, `D-NONFEEL* ∨ D-SCOPE` reaches 90.5% precision today — better than the shipped gate. Direction 3 loses on maintainability, not on accuracy (§2.2).                                 |
| the missing thing is a severity                                              | the missing thing is a **raise site**. `D-NONFEELOUTPUT` is absent from the path 94.7% of decisions take; adding it there is reachable to **97.6%** of the broken artifacts (§1.4). Every vocabulary in this document is downstream of that three-line change. |

---

## 2. The ruling

### 2.1 What is adopted

**A fourth direction, closest in shape to the issue's direction 1 but different in two ways that the
measurement forces.**

Add one field to `FidelityNote`, orthogonal to `severity`:

- it classifies **what the emitted document now is**, not whose fault it is;
- it is **carried per note instance and answered by the producer**, with `-Werror` doing the asking.

`severity` is left exactly as it is — same three constructors, same `Ord`, same assignments. Its job
shrinks: it says how much a _reader_ lost, which is what `Fidelity.hs`'s module header always said it
was for ( _"the losses it names are properties of the target notation, and naming them precisely is
the deliverable"_ ). It stops being asked to do gate work it was never shaped for.

The new field does the gate work, and a second CLI flag names it (§4).

**On "computed per instance", honestly.** The first draft made this the design's centrepiece. After
§3.3 is re-specified the way the surrounding code already does it twice, **every one of the 31 codes
has a constant effect**, and a lookup table would work. That is a contingent fact about today's
vocabulary, not a guarantee: `D-LITERALEXPR` was non-constant until the fix, and
`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7 already queues two codes (`D-PARTIAL`, `D-RENAME`) whose value
varies by call site. So the field stays a **field**, not a table — the type must not foreclose
per-instance variation — but the ruling no longer rests on it.

### 2.2 Why the other three lose

**Direction 3 — leave the vocabulary, let consumers filter by code — loses on maintainability, at
zero measured accuracy cost.** The first draft called it "impossible". That was wrong and is
withdrawn (§9 F-A4). Measured (§1.5): `D-NONFEELOUTPUT ∨ D-NONFEELINPUT ∨ D-SCOPE` fires on 39.6% of
DMN exports at **90.5% precision**, against `--fail-on=blocking`'s 74.6%; and after §3.3 the code
list and the effect field compute the same predicate from the same `FeelFragment`, because §3.3 is
"raise the existing code in the third place it belongs". What direction 3 actually loses on:

- **A new code ships unclassified.** Nothing forces a consumer's list to be updated;
  `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7 queues 7 new codes today. A mandatory record field plus
  `-Wall -Werror -Wmissing-fields` makes the producer answer at compile time (§3.3); a code list
  makes nobody answer, ever.
- **There are at least four consumers coming** — `l4 export`, the service surface (S2), the markdown
  carrier, and K8's two-engine checker — and each would re-derive the list, differently. That is the
  failure mode the `FidelityReport` type exists to prevent.

Two supporting arguments the first draft offered are **also withdrawn**, because they do not survive
inspection: `P-DEADLINE`'s two raise sites were cited as evidence that codes are too coarse, but §5.1
gives both arms the same effect, so the new axis does not distinguish them either; and §1.6 was
offered as a code-filtering counter-example when its argument is about severity.

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
document broken", which are independent — measured in §5.4, where 5 `Blocking` codes are `Faithful`
(including `F1`, which fires on every task in every BPMN export) and 1 `Lossy` code is `Malformed`
(`D-SCOPE`, 461 instances, absent from the goldens only because the flagship exhibit is
`ASSUME`-style).

**Direction 1 as worded — an orthogonal "whose fault" flag — loses on three counts.** (a) It is not
what a gate can act on: "this is our exporter's fault" and "this is BPMN's fault" are equally
un-actionable in CI, where the only question is whether the artifact is fit to ship. (b) The corpus
does not fit three values. Reading the raise sites yields at least four addressees: the target
notation (`F1`), this exporter (`P-NOJOIN` — _"a real limitation of what this exporter draws today"_,
`jl4/examples/bpmn/README.md:42-43`), the **L4 source language** (`P-DEADLINE-UNIT` — _"nothing in L4
fixes one — WITHIN is typed as a bare NUMBER"_), and this particular module (`P-MULTI-HENCE`).
(c) The comparable tools I could read ship a **defect** axis, never a **blame** axis:

| tool                  | axis                                                                                                                                                                     | read from                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| SARIF v2.1.0-errata01 | `kind` = `pass\|open\|informational\|notApplicable\|review\|fail`; §3.27.10 makes `level` subordinate — _"the concept of 'severity' does not apply … other than `fail`"_ | §3.27.9/§3.27.10, `scratchpad/sarif.txt:10072`, `:10223`   |
| ESLint                | `meta.type` = `"problem" \| "suggestion" \| "layout"` — _"identifying code that either will cause an error or may cause a confusing behavior"_                           | `docs/src/extend/custom-rules.md:44-47`, fetched and saved |
| pandoc                | `Verbosity = ERROR \| WARNING \| INFO`, with `SkippedContent{}`, `InlineNotRendered{}`, `BlockNotRendered{}` all mapped to `INFO`                                        | `Text/Pandoc/Logging.hs:40`, `:450`, `:465-466`, fetched   |
| bpmnlint 11.12.1      | `error` / `warning` per rule, plus a rule name; no fault field                                                                                                           | run in §1.8                                                |

(The first draft's sweep also named `clang` and `rustc`. I did not read their sources for this
document and those two are withdrawn — §9 F-C-E1.)

Fault is not lost — it is already in every note's `message` and `lost` prose, which is where it
belongs, because it is advice to a human and not a predicate. §6 records what would change that.

### 2.3 The strongest arguments against this ruling

**(i) It does not make the gate un-saturated on every target, and on one target it barely helps.**
For dmnmd, `Incomplete` fires on essentially every export — because the carrier genuinely drops most
decisions (§1.3). As information, per target:

| gate                                  | fires | H (bits)  |
| ------------------------------------- | ----- | --------- |
| `--fail-on=blocking`, dmn (today)     | 98.6% | 0.105     |
| `--fail-on-effect=broken`, bpmn       | 8.0%  | 0.401     |
| `--fail-on-effect=broken`, dmn (§3.3) | 76.7% | 0.783     |
| `--fail-on-effect=broken`, dmn-md     | 98.2% | **0.129** |

**On dmn-md the new gate carries 0.129 bits against the old 0.105 — by this document's own standard,
"a severity always at its maximum is equivalent to no severity", the dmn-md gate is at its maximum
too.** That is not a rhetorical concession; it is the reason §4.3 keeps the default at 0 and §4.4
adds a **ratchet** (W11), which is usable at 98.2% where a threshold is not.

Three answers, in decreasing order of comfort. First, the numbers differ where it matters: on DMN the
gate goes from 98.6%-and-uninformative to 76.7%-and-true, and on BPMN from 96.6% to **8.0%** — a 7.4×
and 3.8× gain in bits respectively. Second, `Incomplete` at 98% on dmnmd is a **true report about a
bad carrier**, and having it stated in a gateable form is the first step to fixing the carrier rather
than the first step to ignoring it. Third, and least comfortable: the honest consequence is that
`--fail-on-effect=broken` is per-target advice, and the documentation must say so (§4.3).

**(ii) On BPMN, the celebrated 8.0% is one code.** Measured: every BPMN export whose effect is not
`Faithful` is one that carries `P-NOJOIN`; `P-CYCLE`, `P-DEADLINE-UNDRAWN`, `P-MULTI-HENCE` and
`P-JUNCTION-OBLIGATION` have never fired. So on the one target where this document's gate is sharp,
the predicate `code == "P-NOJOIN"` is exactly equivalent today, at zero cost. The gate earns its keep
only when the never-fired shapes start firing and when W13's structural findings acquire notes.

**(iii) Keeping `Blocking` unchanged leaves a loaded gun on the table.** `--fail-on=blocking` will
still be the first flag anyone reaches for, and it will still be useless. Pandoc's answer to the same
problem was to grade target-cannot-express at its _lowest_ level (`SkippedContent`,
`InlineNotRendered`, `BlockNotRendered` → `INFO`), below its `--fail-if-warnings` gate. Adopting that
would mean demoting `F1`/`D-LITERALEXPR`/`D-MD-NODRG` to `Advisory`, which contradicts
`Fidelity.hs`'s stated purpose and re-blesses 5 goldens and breaks 3 test assertions that name those
codes by hand (`BpmnExport.hs:1091`, `:1117`, `DmnExport.hs:867` — the first draft said 29, which is
the count of _all_ severity assertions, §9 F-C9). The ruling keeps severity and pays for it with
documentation (§4.3, `--fail-on=blocking` marked "almost always true"). If in six months people are
still reaching for `--fail-on=blocking` and being misled, the pandoc demotion is the correct
follow-up and this paragraph is the record that it was considered.

---

## 3. The Haskell shape

### 3.1 The type

In `jl4-core/src/L4/Interchange/Fidelity.hs`, add to the export list and define:

```haskell
-- | What defect, if any, THIS NOTE says the emitted artifact carries.
--
-- Orthogonal to 'FidelitySeverity'. Severity says how much the READER lost;
-- effect says what standing the DOCUMENT has. Both off-diagonals occur: @F1@
-- is 'Blocking' and 'Faithful' (BPMN cannot mark a prohibition, but the diagram
-- is a correct diagram); @D-SCOPE@ is 'Lossy' and 'Malformed' (the model is
-- schema-valid and violates a normative SHALL).
--
-- Scope: this value is a property of THIS NOTE, not of the whole report. A
-- report with nineteen 'Faithful' notes and one 'Unevaluable' one describes a
-- document that cannot be run; each 'Faithful' note is still correct, because
-- each says only "I am not the reason".
--
-- Each value is defined by a check a third party can run on the artifact
-- alone, without reading the L4 source and without trusting this report:
data FidelityEffect
  = Faithful
    -- ^ this note names no defect in the artifact. What it reports lost is a
    -- capability the TARGET does not have. Third-party check: none needed —
    -- the artifact is not accused.
  | Unevaluable
    -- ^ the artifact contains text a conforming engine cannot evaluate: it
    -- errors, or it answers @null@ on a name the model never defines.
    -- Third-party check: hand the expressions to an engine. RELATIVE TO A
    -- PROFILE: for DMN today that is Conformance Level 3 (full FEEL), which is
    -- the level the artifact implicitly claims by omitting @expressionLanguage@
    -- (DMN 1.3 §7.3.5). See W12: once the exporter emits a flavour per
    -- ecosystem (lexipedia SPEC.md K8), the profile must be named in the report.
  | Malformed
    -- ^ the artifact violates a normative constraint of the target notation
    -- itself, so no engine behaviour is defined for it. Third-party check:
    -- schema validation plus the notation's own SHALL/MUST clauses. This is
    -- NOT 'Unevaluable': the text may be perfectly good FEEL.
  | Incomplete
    -- ^ a rule the source states has no counterpart in the artifact at all.
    -- Third-party check: counting.
  | Misstated
    -- ^ every counterpart is present and the artifact is well-formed, but a
    -- consumer applying the TARGET NOTATION'S OWN semantics draws a conclusion
    -- the source does not license. Third-party check: differential evaluation
    -- where the target is executable (DMN); reading the artifact under the
    -- target's execution semantics where it is not (BPMN, Chapter 14).
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

**Why `Faithful` and not `Sound`.** "Sound" is taken, in the same files the value gets written into:

```bash
grep -nic '\bsound' jl4-core/src/L4/Dmn/Lower.hs   # → 7
```

and those seven hits carry at least two distinct senses — the decision-table analysis sense
(`:604` _"Sound but incomplete: a 'False' costs only …"_, `:1288` _"the NONFEEL/valid-FEEL split is a
soundness boundary"_) and the meaning-preservation sense (`:57`, `:65`, `:676`). Renaming costs
nothing now and is expensive after S2 fixes a wire spelling (§6, Q6).

**`FidelityEffect` deliberately does not derive `Ord`.** There is no ordering under which "a rule is
missing" is more or less serious than "the answer is wrong"; a consumer that wants several must name
them. This is the design decision that stops the new axis degenerating into the old one. See §3.2.

`Enum, Bounded` **are** derived, and should be added to `FidelitySeverity` too, so that the tally in
`Export.hs` can be written `[minBound .. maxBound]` instead of a hand-written list of three. That
hand-written list is the mechanism by which direction 2 would have failed silently; it should not
survive this change regardless of which direction is taken.

### 3.2 The `Ord` instance, and the one invariant that ties the axes together

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

**The axes are independent where the gate looks, and dependent where it does not.** Over the 31
classified codes (`scratchpad/repair/final.py`):

```
H(effect) = 1.573   H(severity) = 1.565   MI = 0.391 bits  (25% of H(effect))
H(effect | Blocking) = 1.888    H(effect | Lossy) = 1.750    H(effect | Advisory) = 0.000
```

That last zero is not noise, it is an **invariant**: `FidelitySeverity`'s own haddock defines
`Advisory` as "expressed faithfully", which entails not-`Incomplete`, not-`Misstated`,
not-`Malformed` and not-`Unevaluable`. So:

> **`severity == Advisory` ⟹ `effect == Faithful`.** State it in the haddock and assert it as a
> property test over §5's table (W7). Without it, a future editor tags an `Advisory` note
> `Incomplete` and contradicts severity's own documentation with no compile error.

Nothing constrains the Blocking or Lossy rows, which is where the gate reads.

### 3.3 The missing raise site — the part that is not a rename, and ships alone

This is where the 84.2% lives, and it is **three lines**.

`nonFeelOutput` (`Dmn/Lower.hs:1315-1327`) is already a shared helper, and its haddock already states
the intent:

```haskell
-- | The one Blocking note for an output position whose text is L4, not FEEL.
--
-- Shared by the decision-table path and the boxed-literal select-idiom path,
-- because the failure is the same in both and a reader must not have to know
-- which shape the exporter chose.
```

The select-idiom path calls it beside its other notes (`:1664-1666`):

```haskell
<> [ nonFeelOutput did (bestRange body) rendered
   | rendered.feFragment == L4Verbatim
   ]
```

**`literalFallback` (`:1681-1692`) is the third shape and simply omits those three lines**, although
`rendered` is in scope right there (`:1691`). The fix is to add them:

```haskell
    literalFallback loss =
      ( LogicLiteral rendered
      , [ dmnNote "D-LITERALEXPR" Blocking Faithful did (bestRange body) … ]
          <> [ nonFeelOutput did (bestRange body) rendered
             | rendered.feFragment == L4Verbatim
             ]
      )
```

**This is W3, it depends on nothing, and it is the only work item in this document that moves any
number.** Three reasons to sequence it first:

1. **Reach.** §1.4 measured that 364 of the 373 broken artifacts (**97.6%**) carry at least one
   broken _boxed literal_ expression. Adding the note on that path is the only path that matters.
2. **It fixes the report a human reads**, not merely a field a gate reads. Today
   `decision_shifted_point_example` is reported as "not a guarded chain"; after W3 it is also
   reported as _"NO DMN engine can evaluate it"_, which is the sentence the reader needed.
3. **It makes the code a reliable predicate again**, which is what makes the honest version of §2.2
   possible: after W3, `D-NONFEEL*` and the `effect` field compute the same thing from the same
   `FeelFragment`, and the argument for the field is maintainability rather than reach.

With W3 in place, `D-LITERALEXPR`'s effect is the constant `Faithful` (§5.2) and every code's effect
is constant. The alternative — leave `literalFallback` alone and compute `D-LITERALEXPR`'s effect
from `rendered.feFragment` — was the first draft's plan; it reaches the same gate but leaves the
human-readable report saying only "not a guarded chain" while a hidden field says the document cannot
run. That is the same substitution `Dmn/Lower.hs:1418-1421` already condemns.

**Rule B — the helpers take the effect positionally, never by default.** `dmnNote`
(`Dmn/Lower.hs:1299`), `note` (`Markdown.hs:314-316`) and `boundaryTrigger`'s local `note`
(`Bpmn/Lower.hs:1059-1068`) funnel most of the 32 construction sites through 3 helpers. If the helpers
default the field, the compiler classifies nothing and every DMN code silently lands on one value.
Each helper gains a `FidelityEffect` argument in the same position as `FidelitySeverity`, so that
every call site is forced to answer.

The compiler will enforce this at the record-construction sites that do not use a helper. Verified:

```bash
$ cat W.hs
module W where
data R = MkR { a :: Int, b :: Bool }
mk :: R
mk = MkR { a = 1 }
$ ghc -Wall -Werror -fno-code W.hs
W.hs:4:6: error: [GHC-20125] [-Wmissing-fields, Werror=missing-fields]
    • Fields of ‘MkR’ not initialised:
        b :: Bool
```

`-Wmissing-fields` is in `-Wall`; `jl4-core.cabal:21` and `jl4.cabal:9` both set `-Wall -Werror`. So
the 12 record-style sites in `Bpmn/Lower.hs` fail to compile until answered. (Note the limit:
`jl4-core` does **not** set `-Wincomplete-record-updates`; only `jl4-service` does
(`jl4-service.cabal:19`). Do not rely on record _update_ warnings here.)

### 3.4 Migration, consumer by consumer

Every consumer of `FidelitySeverity` in the tree, and what this change does to it. "Compile error"
means `-Werror` stops the build; "silent" means it builds and does the wrong thing, which is what the
migration has to catch by hand.

| #   | Consumer                                                           | Anchor                                                                                                                                                                                                           | Effect of this change                                                                                                                                                                                                                                                                            | Action                                                                                                                                                                                                             |
| --- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `renderNote` — the only rendering, and the format of all 5 goldens | `Fidelity.hs:70-81` (the `case` at `:77-80`)                                                                                                                                                                     | none (no `case` on the new field until one is written)                                                                                                                                                                                                                                           | print the effect word in parens **always**, not only when ≠ `Faithful`: `[F1] blocking (faithful) — Task_0`. See the note below — printing it conditionally makes a lazy port produce a **zero-line golden diff**. |
| 2   | stderr tally                                                       | `Export.hs:365-375`                                                                                                                                                                                              | none, but the hand-written 3-list is the silent-failure mechanism identified in §2.2                                                                                                                                                                                                             | rewrite as `[minBound .. maxBound]` over `FidelitySeverity`; add a second line counting effects ≠ `Faithful`                                                                                                       |
| 3   | "blocking codes" stderr line                                       | `Export.hs:376`, printed `:384-387`                                                                                                                                                                              | none; but its parenthetical _"(the notation has no form for it; a fallback was emitted)"_ is now provably false for `D-SCOPE`-class notes                                                                                                                                                        | reword; add a `broken codes:` line listing the distinct codes whose `effect` is not `Faithful`                                                                                                                     |
| 4   | **`tripsGate` — the gate and the exit code**                       | `Export.hs:406-415`, consumed `:236`                                                                                                                                                                             | rewritten (§4.1). The severity branch is byte-for-byte the current behaviour.                                                                                                                                                                                                                    | see §4.1                                                                                                                                                                                                           |
| 5   | `FidelityGate` + `--fail-on` reader + its metavar                  | `Export.hs:101-106`, `139-150`, `199-208`; `metavar "SEVERITY"` at `:201`                                                                                                                                        | type changes from an enum to a record; the reader's `other ->` catch-all stays; `--fail-on` keeps its vocabulary exactly, so the metavar stays correct                                                                                                                                           | §4.1, §4.2; add the second option `--fail-on-effect` with `metavar "EFFECT"`                                                                                                                                       |
| 6   | module haddock stating the design rationale                        | `Export.hs:30-52`                                                                                                                                                                                                | stale — it says the tool _"deliberately does not exit non-zero on a `Blocking` note"_ and explains why                                                                                                                                                                                           | rewrite: the reason is now "because `Blocking` is not the executability signal; `--fail-on-effect=broken` is"                                                                                                      |
| 7   | **Producer** — DMN XML                                             | `Dmn/Lower.hs:1265-1298` (vocab haddock), 13 `dmnNote` calls (`:1299`), one of which is the `nonFeelOutput` wrapper (`:1315-1327`, called from `:1430` and `:1664`); prose at `:444`, `:793-794`                 | **compile error** at the helper; then 12 decisions                                                                                                                                                                                                                                               | §5; W3 first, then Rule B. `:793-794`'s prose becomes redundant once the axis exists and should point at it.                                                                                                       |
| 8   | **Producer** — dmnmd                                               | `Markdown.hs:242-316`, 7 sites via `note` (`:314-316`)                                                                                                                                                           | compile error at the helper; 6 decisions                                                                                                                                                                                                                                                         | §5                                                                                                                                                                                                                 |
| 9   | **Producer** — BPMN                                                | `Bpmn/Lower.hs`, 12 `MkFidelityNote` records (`:277,303,602,721,753,782,816,833,1060,1144,1180,1195`; `:1060` is `boundaryTrigger`'s local helper, serving `P-DEADLINE`×2 and `P-DEADLINE-UNIT`)                 | **compile error at all 12** via `-Wmissing-fields`; 13 decisions                                                                                                                                                                                                                                 | §5; note §1.7 — none is `Unevaluable`, **because of our own attribute**. Module haddock at `:40-60` and prose at `:490-491` are stale too.                                                                         |
| 10  | `BpmnExport { bxFidelity }`                                        | `Bpmn/IR.hs:200`                                                                                                                                                                                                 | none                                                                                                                                                                                                                                                                                             | —                                                                                                                                                                                                                  |
| 11  | `dmnReport` / `drgNotesAll` / `dtNotes`                            | `Dmn/IR.hs:354`, `:416`, `:483-495`                                                                                                                                                                              | none (severity-blind folds)                                                                                                                                                                                                                                                                      | —                                                                                                                                                                                                                  |
| 12  | `FidelityLoss` — a separate DMN-local enum                         | `Dmn/IR.hs:447-467`                                                                                                                                                                                              | none. Worth knowing it is already a partial "why" axis for the decision side (`NotAGuardedChain`, `RowsElided`, …)                                                                                                                                                                               | leave; §6 asks whether it should fold in                                                                                                                                                                           |
| 13  | Test — DMN export, 18 severity assertions                          | `jl4/tests/DmnExport.hs:777,830,845,859,867,913,926,933,944,961,969,986,1007,1050,1089,1114,1119,1126`                                                                                                           | compiles; **still passes**, since no severity moves                                                                                                                                                                                                                                              | add effect assertions beside them; the `describe` at `:905-947` ( _"L4 source in a `<text>` element is Blocking, not Advisory"_ ) is this ruling's ancestor and should gain `effect == Unevaluable`                |
| 14  | Test — BPMN export, 11 severity assertions                         | `jl4/tests/BpmnExport.hs:759,913,1053,1054,1091,1111,1112,1144,1166,1186,1222`                                                                                                                                   | compiles; still passes                                                                                                                                                                                                                                                                           | `:1103`'s comment — _"every F1 is Blocking, so severity cannot be what marks a prohibition"_ — is the issue, written down. Add `effect == Faithful` there.                                                         |
| 14b | Test — BPMN `renderReport` substring assertions                    | `jl4/tests/BpmnExport.hs:1114-1120`                                                                                                                                                                              | **fails** under #1's always-print rendering: it matches the literals `"[F1] blocking — Task_0"` and `"[F5] advisory — Process_chain"`                                                                                                                                                            | update both literals. Under a print-only-when-broken rendering it would have survived **by luck**, which is one reason #1 rules the other way.                                                                     |
| 15  | Golden `.fidelity.txt` fixtures **and their harnesses**            | `jl4/examples/{bpmn,dmn}/expected/*.fidelity.txt` (5 files); `BpmnExport.hs:1460-1476` (`goldenCase`), `DmnExport.hs:1191-1205` (`mkGolden`, `goldenMarkdownFidelity`)                                           | **byte-exact comparison breaks on every note line** under #1                                                                                                                                                                                                                                     | re-bless all 5. Under a conditional rendering only 5 lines would change — 3 in `reg-cf.md.fidelity.txt`, plus `P-NOJOIN` at `offering.fidelity.txt:32` and `handover.fidelity.txt:32`.                             |
| 16  | CLI test — `--fail-on` threshold matrix                            | `jl4/tests-cli/Main.hs:942-1002`                                                                                                                                                                                 | **passes unchanged** — severity thresholds keep their exact semantics, on their own flag. This is the strongest argument for not touching severity.                                                                                                                                              | add a parallel `--fail-on-effect` block, with fixtures that are `Unevaluable`-only and `Incomplete`-only                                                                                                           |
| 17  | CLI test — sidecar/stderr routing                                  | `jl4/tests-cli/Main.hs:896-940`                                                                                                                                                                                  | `:934-939` asserts the substring `"blocking"`, which survives #1                                                                                                                                                                                                                                 | check after #1                                                                                                                                                                                                     |
| 18  | User-facing and **agent-facing** docs                              | `jl4/examples/dmn/README.md:147-151`, `jl4/examples/bpmn/README.md:141`, `Dmn/Lower.hs:1265-1298`, `Fidelity.hs:1-10`, `.claude/skills/writing-l4-rules/SKILL.md:225-230`, `references/drafting-patterns.md:207` | stale. `SKILL.md` documents `--fidelity-report` and the `.fidelity.txt` sidecar and never mentions `--fail-on` at all; `drafting-patterns.md:207` uses the vocabulary in prose (_"a single verbatim default entry (`Blocking`, and `null` under `SUCCEEDED`)"_) — a textbook `Unevaluable` case. | rewrite all six                                                                                                                                                                                                    |
| 19  | Forward-looking spec — 7 new codes + 1 repurpose                   | `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md:1065-1077`, and its rulings at `:625-626`, `:709-712`, `:1195-1198`, `:1220-1221`                                                                                   | must be re-ruled, **and it conflicts with §1.6.** Its `D-SCOPE` row says today's predicate is _"universal under GIVEN style, so pure noise"_ and replaces it with a type-conflict test. §1.6 rests on that predicate being TP=185/FP=0.                                                          | see the reconciliation below. Also: **two** of its unbuilt codes already carry two severities each (`D-PARTIAL`, `D-RENAME`) — that is this axis, smuggled into severity twice before it had a name.               |
| 20  | Name collision                                                     | `jl4/app/L4/Cli/Common.hs:215-219` `hasBlockingError`                                                                                                                                                            | unrelated (LSP `DiagnosticSeverity_Error`)                                                                                                                                                                                                                                                       | do not let the new vocabulary reuse the word "blocking"                                                                                                                                                            |

**#19, reconciled.** Both documents are right about different objects, and W9 executed as the other
spec writes it would delete the predicate this document's cleanest evidence depends on.

- The other spec judges the **L4-side** predicate ("two Uniques, one FEEL name") and calls it noise.
- This document measures the **artifact**, and 36.5% is not "universal": `D-SCOPE` fires on 183 of
  505 corpus DMN exports and 185 of 507 in the DMN-only sweep, with TP=185/FP=0/FN=0 against
  duplicate `inputData/@name`, and 184/185 of those duplicates live in a `<text>` (§1.6).

Ruling for W9: **the type-conflict test may be added as a new, narrower code; today's `D-SCOPE`
predicate must not be deleted until something else reports duplicate `inputData/@name`,** because
that is the only `Malformed` detector in the tree.

**Not consumers**, verified negative:

```bash
grep -rni 'fidelity' jl4-service/src jl4-lsp/src ts-apps ts-shared .github   # → no L4.Interchange.Fidelity hits
grep -rn 'ToJSON\|FromJSON' jl4-core/src/L4/Interchange                      # → no output
```

There is **no** JSON instance, no TypeScript consumer, and no OpenAPI schema.

Three qualifications the first draft skipped (§9 F-C4, F-C5, F-A7):

- **There _is_ a CI job.** `.github/workflows/pr-checks.yml:209` runs `cabal test all` under a
  Haskell paths filter, so the 5 goldens and the `--fail-on` matrix are CI-gated. Landing W1/W2
  without W7 turns CI red.
- **`L4.Interchange.Fidelity` is an `exposed-module`** (`jl4-core.cabal:166`, under `exposed-modules:`
  at `:90`). A mandatory field is a public library API break, not merely an internal one. The blast
  radius is small **in-tree**.
- **`.fidelity.txt` is a wire format already**, documented at `SKILL.md:225-230` and matched by
  substring in two tests and by `grep` in §1.2 of this document. #1's change breaks it, deliberately
  and once, rather than leaving a field that is sometimes absent.

`jl4/examples/dmn/README.md:151` says the service surface (track S2) is still to come — after it
ships, this change acquires a JSON wire format and a compatibility story (§6, Q6).

---

## 4. The CLI surface

### 4.1 The gate type

```haskell
-- | What makes @l4 export@ exit non-zero. Two independent questions, on two
-- independent flags, because the report answers two independent questions.
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

### 4.2 The command-line vocabulary — two flags, not one

`jl4/tests-cli/Main.hs:963-967` states the current model in the suite itself:

> `--fail-on` is a THRESHOLD ("a note this severe or worse"), over a lattice ordered
> Blocking < Lossy < Advisory.

Adding effect selectors to that flag would make its own test-suite comment false, and — worse —
`--fail-on=broken` **reads as a rung above `blocking`**, which is direction 2's mental model, the one
this document rejects. Meanwhile the flag's most-severe-sounding value (`blocking`) is already its
_least_ inclusive setting, so the trap is real. So: **a second flag, each with one vocabulary.** They
OR.

| flag               | value                                     | trips when                                | status                                        |
| ------------------ | ----------------------------------------- | ----------------------------------------- | --------------------------------------------- |
| `--fail-on`        | `none` / `never`                          | never                                     | unchanged; **remains the default**            |
| `--fail-on`        | `blocking` / `lossy` / `advisory` / `any` | severity threshold                        | unchanged; documented as "almost always true" |
| `--fail-on-effect` | `none`                                    | never                                     | new; the default                              |
| `--fail-on-effect` | `unevaluable`                             | any note with `effect = Unevaluable`      | new                                           |
| `--fail-on-effect` | `malformed`                               | any note with `effect = Malformed`        | new                                           |
| `--fail-on-effect` | `incomplete`                              | any note with `effect = Incomplete`       | new                                           |
| `--fail-on-effect` | `misstated`                               | any note with `effect = Misstated`        | new                                           |
| `--fail-on-effect` | **`broken`**                              | any note whose `effect` is not `Faithful` | new; **this is the CI gate**                  |
| `--fail-on-effect` | `unevaluable,malformed`                   | union of the named selectors              | new                                           |

Both readers split on `,`, fold each token into the record, and keep an `other ->` error branch so
unknown selectors stay a usage error rather than a silent no-op.

### 4.3 The default, and why it does not change

**`l4 export` keeps exiting 0 by default.** Three reasons, in order of weight:

1. **The measured failure rate is too high to flip.** Under `--fail-on-effect=broken`, 76.7% of DMN
   exports in this repo's own corpus would fail after W3 (§4.4), and dmnmd would fail on 98.2% of
   them. A default-on gate would turn every existing invocation into a build break on upgrade, for
   defects that predate the flag.
2. `l4 export` is a rendering command as much as a checking command — it is how documentation
   examples and the paper's figures are produced. Renderers exit 0.
3. The gate's value is that it is _available_, not that it is _on_. The issue's complaint was never
   "the default is wrong"; it was "the useful gate does not exist".

**When to revisit.** When `--fail-on-effect=broken` fires on under 5% of the corpus, flipping the
default should be reconsidered, and this paragraph is the trigger condition. Getting there is tracked
as W3–W5 in §7. Until then, the ratchet (W11) is what a project actually leaves on.

### 4.4 What fraction of the corpus fails under the new gate

Stated honestly, because there are two numbers and only one of them is reachable by a vocabulary
change alone.

**(a) With `effect` assigned per §5 and W3 _not yet done_** — i.e. W1+W2 alone. `D-LITERALEXPR` is
`Faithful` (§5.2), which the first draft left implicit and which is the difference between this table
and a catastrophe: read `D-LITERALEXPR` as `Unevaluable` instead and dmn `broken` is 98.6%, exactly
the saturation this document exists to remove (§9 F-C-extra). Computed from the corpus run:

```bash
python3 scratchpad/repair/final.py
```

| selector                       | dmn             | dmn-md          | bpmn          | ALL                  |
| ------------------------------ | --------------- | --------------- | ------------- | -------------------- |
| `--fail-on-effect=unevaluable` | 64/505 (12.7%)  | 0/505 (0%)      | 0/176 (0%)    | **64/1186 (5.4%)**   |
| `--fail-on-effect=malformed`   | 183/505 (36.2%) | 0/505 (0%)      | 0/176 (0%)    | **183/1186 (15.4%)** |
| `--fail-on-effect=incomplete`  | 0/505 (0%)      | 496/505 (98.2%) | 14/176 (8.0%) | **510/1186 (43.0%)** |
| `--fail-on-effect=misstated`   | 0/505 (0%)      | 0/505 (0%)      | 0/176 (0%)    | **0/1186 (0%)**      |
| **`--fail-on-effect=broken`**  | 199/505 (39.4%) | 496/505 (98.2%) | 14/176 (8.0%) | **709/1186 (59.8%)** |

`Misstated` fires nowhere on this corpus: all three of its codes (`P-CYCLE`, `P-MULTI-HENCE`,
`P-JUNCTION-OBLIGATION`) are among the six that have never fired (§1.3). That is a true and
uncomfortable fact about the value, recorded rather than hidden.

**(b) Once W3 lands**, measured against the engine oracle over its own 507-artifact run. (The two
runs have slightly different DMN denominators — 505 vs 507 — because the full three-target sweep lost
`charities-jersey-2014/part-1-interpretation.l4` and `part-6-use-of-terms.l4` to the 180 s timeout,
while the DMN-only sweep at 300 s exported both. Every figure is quoted against the denominator it
was measured over; the 0.4% difference moves nothing.)

| selector                                      | dmn                 |
| --------------------------------------------- | ------------------- |
| `--fail-on-effect=unevaluable` (engine truth) | **373/507 (73.6%)** |
| `--fail-on-effect=malformed` (`D-SCOPE`)      | 185/507 (36.5%)     |
| **`--fail-on-effect=broken`** (their union)   | **389/507 (76.7%)** |

Read those two tables together and the ruling's central claim is a number: **on the DMN target the
gate goes from 12.7% to a measured ceiling of 73.6% by adding three lines at one raise site** (§3.3),
without adding a single note code and without the vocabulary change. The vocabulary change is what
makes the gate _nameable_ and _maintainable_; W3 is what makes it _true_.

Three further readings worth stating plainly:

- **BPMN gets a sharp gate: 8.0%** — but see §2.3(ii): on this corpus that is exactly the predicate
  `code == "P-NOJOIN"`.
- **DMN's 76.7% is high, and that is a true statement about the artifacts.** At 76.7% nobody leaves
  the gate on, so `--fail-on-effect=broken` is a **diagnostic** on DMN until W3's successors bring
  the number down. What is usable on all three targets today is the ratchet, W11.
- **dmnmd's 98.2% is the axis's weakest showing**, at 0.129 bits — §2.3(i).

**Acceptance criterion for the implementation** — and the reason the oracle script should be
committed rather than thrown away: after W3, `--fail-on-effect=broken` on the DMN target must agree
with `scratchpad/ruling/feeloracle.mjs` on the corpus to **≥95% precision and ≥95% recall**. §1.4
measured the ceiling at 97.6% recall, so the criterion is reachable; if the implemented gate lands at
15.8%, it has reproduced the current defect under a new name and the test will say so. **W12
re-pins this criterion to a K8 engine** once one is wired; `feelin` is a third implementation and is
used here as a proxy.

---

## 5. Every note code, classified

No code is left unassigned. `severity` is unchanged throughout — this table adds a column, it does
not move one. Line numbers are raise sites at `3b9bfc6e`.

### 5.1 BPMN — `jl4-core/src/L4/Bpmn/Lower.hs`

_Classified by reading the raise sites. `P-NOJOIN` is corroborated by `bpmnlint`'s independent
`fake-join` finding (§1.8); the other twelve are not externally checked, and W13 is the work item
that would fix that._

| code                    | line       | severity | **effect**   | why, from the raise site                                                                                                                                                                                                                                                                                           |
| ----------------------- | ---------- | -------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `F1`                    | 1145       | Blocking | `Faithful`   | _"MUST, MAY and SHANT all draw as a task"_. The diagram is a correct diagram; BPMN has no deontic marking.                                                                                                                                                                                                         |
| `F2`                    | 817        | Lossy    | `Faithful`   | lane ≠ bearer. A property of BPMN's swimlanes.                                                                                                                                                                                                                                                                     |
| `F3`                    | 1196       | Blocking | `Faithful`   | _"BPMN has only one kind of 'did not happen'"_. Nothing is absent or wrong; a distinction is unrepresentable.                                                                                                                                                                                                      |
| `F4`                    | 1181       | Lossy    | `Faithful`   | the guard **is** drawn, as an opaque `conditionExpression`; what is lost is _"whatever decision structure backed **the guard** — DMN would be its right home"_ (`:1191`).                                                                                                                                          |
| `F5`                    | 834        | Advisory | `Faithful`   | no as-of date in BPMN.                                                                                                                                                                                                                                                                                             |
| `P-DEADLINE`            | 1012, 1046 | Blocking | `Faithful`   | both arms. The boundary event exists and carries the source's own text; in a document that declares `isExecutable="false"` (§1.7) "not a machine-checkable timer" is a capability loss, exactly like `F1`.                                                                                                         |
| `P-DEADLINE-UNIT`       | 1025       | Advisory | `Faithful`   | **closest call in the table.** BPMN's timer has no unit-free form, so any drawing must choose; the note says it chose and `--deadline-unit=refuse` refuses instead. Choosing and saying so is not a misstatement.                                                                                                  |
| `P-DANGLING`            | 304        | Advisory | `Faithful`   | its own `lost` field: _"nothing the source said; this is an artefact of extraction"_. **Dissent recorded — §6, Q7:** the drawn End event asserts a termination the source never states, which is over-assertion.                                                                                                   |
| `P-NOJOIN`              | 603        | Lossy    | `Incomplete` | no converging gateway is drawn — the conjunction has no counterpart element. The note argues drawing one would deadlock, i.e. `Misstated` would be worse. Corroborated externally (§1.8).                                                                                                                          |
| `P-DEADLINE-UNDRAWN`    | 278        | Lossy    | `Incomplete` | _"is not drawn anywhere … there is no boundary event to carry it"_; `lost: the deadline as a drawn constraint`.                                                                                                                                                                                                    |
| `P-CYCLE`               | 783        | Lossy    | `Misstated`  | **reclassified from `Incomplete`** (§9 F-C7). The loop **is** drawn; the message says so. What breaks is that _"this layout places a node by its longest path from the start and a node on a cycle has none"_, and `lost` is _"the reading that left-to-right is time"_. Nothing is absent; the positions mislead. |
| `P-MULTI-HENCE`         | 722        | Blocking | `Misstated`  | >1 `HENCE` off one state; _"BPMN reads several unconditional outgoing flows as an implicit parallel split"_, so the diagram says every continuation happens where the source offered a choice.                                                                                                                     |
| `P-JUNCTION-OBLIGATION` | 754        | Blocking | `Misstated`  | both a junction and an obligation; _"neither is what the source says"_.                                                                                                                                                                                                                                            |

**No BPMN note is `Unevaluable`, and that is our `isExecutable="false"` doing** — §1.7, and W6 puts
the assertion at `Emit.hs:98` so the day someone adds `--executable` this column is revisited rather
than silently wrong. `--fail-on-effect=broken` on BPMN therefore means "`P-NOJOIN`,
`P-DEADLINE-UNDRAWN`, `P-CYCLE`, `P-MULTI-HENCE` or `P-JUNCTION-OBLIGATION`", of which only the first
has ever fired.

### 5.2 DMN 1.3 XML — `jl4-core/src/L4/Dmn/Lower.hs`

| code                 | line                                            | severity         | **effect**    | why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| -------------------- | ----------------------------------------------- | ---------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D-NONFEELOUTPUT`    | 1317 (helper), called 1430, 1664                | Blocking         | `Unevaluable` | already gated on `feFragment == L4Verbatim`; its own message says _"NO DMN engine can evaluate it"_. **W3 adds a third call site** (`literalFallback`), which is what lifts its recall from 15.8%.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `D-NONFEELINPUT`     | 1364                                            | Blocking         | `Unevaluable` | same gate, input side.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `D-LITERALEXPR`      | 1683                                            | Blocking         | `Faithful`    | **after W3.** The note is about analysability, and analysability loss is not a defect in the document. Where the same decision is also unevaluable, `D-NONFEELOUTPUT` says so beside it (§3.3).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `D-SCOPE`            | 1599                                            | Lossy            | `Malformed`   | 185/507 artifacts, TP=185 FP=0 FN=0 against duplicate `inputData/@name`; duplicate `<variable>/@name` in 185/185; the duplicated name is live in a `<text>` in 184/185. Violates DMN §7.3.4's `SHALL` (§1.6).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `D-NONFEEL`          | 1375                                            | Advisory         | `Faithful`    | valid FEEL outside S-FEEL. Level-3 conforming, which is the profile the artifact claims (§3.1 — under an S-FEEL-only consumer this would be `Unevaluable`; W12).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `D-COMPUTEDOUTPUT`   | 1411                                            | Advisory         | `Faithful`    | explicitly mutually exclusive with `D-NONFEELOUTPUT` (`:1418-1421`); what is lost is analysis.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `D-ORDERDEPENDENT`   | 1395                                            | Advisory         | `Faithful`    | hit policy `F`; DMN 1.3 §8.2.10 permits it and warns it is "hard to validate manually".                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `D-HITPOLICY`        | 1389                                            | Advisory         | `Faithful`    | the guards **are** disjoint; only the columns cannot witness it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `D-UNDECOMPOSABLE`   | 1343                                            | Advisory         | `Faithful`    | boolean column; the table still answers. If the guard is also L4 text, `D-NONFEELINPUT` fires alongside.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `D-INLINEDLOCAL`     | 1439                                            | Advisory         | `Faithful`    | the value is inlined, so the answer is unchanged; the drafter's **name** is lost.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `D-FLATTENCAP`       | 1448                                            | Advisory         | `Faithful`    | the nested chain stays in the output expression; the rows, not the logic, are lost.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `D-LIFTEDTHRESHOLD`  | 1456, 1653                                      | Advisory         | `Faithful`    | threshold moves inside `min`/`max`; same answer, worse for a compliance reader.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `D-COMPUTEDFIELD`    | added 2026-07-31                                | Advisory         | `Faithful`    | a hydrated `itemDefinition`'s derived components are not marked derived; DMN's `tItemDefinition` has no such flag. **Nothing an engine needs is missing** — hydration means no caller ever supplies one — so what is lost is legibility of the type, not correctness of the model. `Faithful` is forced by §3.2's invariant and is also the right answer independently.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `D-PARAMTYPE`        | added 2026-07-31 (Phase 4)                      | Blocking         | `Faithful`    | W9's "new, narrower code": ≥2 same-L4-named parameters at different declared types, the Phase 4 merge **refused**. The emitted artifact is well-formed and evaluable — the claimants stay distinct, `uniquifyIn`-renamed elements — so nothing is misstated. The severity is the attention floor for the near-miss: merging measured `null [SUCCEEDED]` with zero messages on both engines (GCO). Fires live: Charities ×5, GCO ×3.                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `D-PARAM-AS-INPUT`   | added 2026-07-31 (Phase 4)                      | Advisory         | `Faithful`    | un-lifting's cost, named per merged group ≥2: the decisions read one shared global where L4 bound per call site. Same answers wherever the L4 applied them to the same subject — which tier 1 certifies is everywhere.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `D-PARTIAL`          | added 2026-07-31 (Phase 4)                      | Blocking / Lossy | `Misstated`   | **the §7-header two-severity smuggle, live in the tree**: severity keys off the call site (any strict consumer, or root ⇒ Blocking; all-lazy ⇒ Lossy) and collapses to one severity + this effect when W1/W2 lands. `Misstated` by definition: on an input outside the source function's domain, FEEL answers `null`, the first boolean consumer reads `false`, and the consumer draws a conclusion the source does not license (the source raises). Third-party check: differential evaluation.                                                                                                                                                                                                                                                                                                                                                                           |
| `D-FIXTURE`          | added 2026-07-31 (Phase 4)                      | Advisory         | `Incomplete`  | a source decide has no counterpart — the mechanical counting check flags it — but by classification it is test scaffolding, not a rule of the rule set. Advisory + `Incomplete` is the two-axis point, not a contradiction: the omission needs no attention _because_ the note says exactly what was omitted and `--include-tests` restores it. The unverified-conjunct-(d) form is KEPT + report-only.                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `D-INERT`            | added 2026-07-31 (Phase 4)                      | Advisory         | `Faithful`    | kept, flagged: the body forces no reference and no input, so the "decision" is a prose carrier answering a constant. Nothing dropped, nothing misstated — the note stops a reader mistaking a tautology for a rule.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `D-REGULATIVE`       | added 2026-07-31 (Phase 4)                      | Lossy            | `Incomplete`  | an uncalled regulative body is not emitted — the obligation genuinely has no counterpart in the DMN artifact, and the note routes the reader to BPMN. Drops to Advisory once PR #141 gives it a target. A module-called regulative body stays (still emitting raw L4, `D-LITERALEXPR`'s problem).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `D-BKM`              | added 2026-07-31 (Phase 4)                      | Advisory         | `Faithful`    | report-only tier-2 classification; behaviour unchanged in Phase 4 (the `<decision>` and its verbatim call sites remain, already noted). Phase 5's BKM emission re-rules this row.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `D-RULEDATE-UNBOUND` | added 2026-08-02 (R12, DMN spec §15.12)         | Lossy            | `Incomplete`  | a rule-date-rebinding decide (`EVAL UNDER RULES EFFECTIVE AT`) is not emitted — the pinned-regime scenario genuinely has no counterpart in the DMN artifact, `D-REGULATIVE`'s shape exactly. ONE severity: before R12 the code was Blocking on an emitted raw-L4 decision; R12 removes the emission, and with it the thing that was broken.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `D-SVCEMPTY`         | added 2026-08-02 (R12's companion, DMN spec §7) | Advisory         | `Faithful`    | no `<decisionService>` for a §, said out loud. `Advisory ⟹ Faithful` (§3.2) is discharged: arm (i)'s per-decision loss is already carried by each member's own note (`D-RULEDATE-UNBOUND`/`D-REGULATIVE` Lossy, `D-FIXTURE` Advisory — the arm covers every `DropReason` since the 2026-08-02 widening, not only rebinds); arm (ii)'s KEPT member decisions are all emitted — only the grouping shell is not — and its lost-line SAYS when the § also had population-dropped members instead of claiming "all emitted" of them (**repaired 2026-08-02**: an earlier revision of this row generalised the all-emitted claim to arm (ii) as such, which the corpus's three mixed §s falsified); an uninvoked grouping service is inert on both engines (probe D1, `D-FLAVOR-NOSERVICE`'s grouping-arm precedent). One severity, two message forms (`D-FIXTURE`'s precedent). |
| `D-VERDICT`          | added 2026-08-02 (R13, DMN spec §16)            | Lossy            | `Incomplete`  | a deontic guarded chain lowered to a verdict decision table over its guards; the obligation-as-state (PARTY/WITHIN/HENCE/LEST) genuinely has no counterpart in THIS artifact — it is routed to the BPMN projection, `D-REGULATIVE`'s shape with a better ending: the guards execute here and the lifecycle executes there.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

### 5.3 dmnmd markdown — `jl4-core/src/L4/Dmn/Markdown.hs`

| code                  | line             | severity | **effect**   | why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| --------------------- | ---------------- | -------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `D-MD-NOLITERAL`      | 260              | Blocking | `Incomplete` | its own `lost`: _"the decision itself; it is omitted from the markdown"_. `renderDecision` returns `Nothing` (`Markdown.hs:79-84`).                                                                                                                                                                                                                                                                                                                                                                                                  |
| `D-MD-NONIDENTCOLUMN` | 269              | Blocking | `Incomplete` | _"so this table is omitted"_ / `lost: the whole table`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `D-MD-CELLSYNTAX`     | 279              | Blocking | `Incomplete` | same. **Widened 2026-07-31** to the `<defaultOutputEntry>`, not only the rules: R8-d′ made FEEL `null` a catch-all this backend emits, `mdOutput` refuses it, and without this the table rendered a `-` in the OUTPUT column — dmnmd's "any" token, read back as "output unspecified". Same code because the loss is the same one: a cell the grammar cannot say.                                                                                                                                                                    |
| `D-MD-NODRG`          | 248              | Blocking | `Faithful`   | **the other close call.** Every decision survives; only the graph picture is absent, and which decision feeds which is recoverable from the column names. Dissent recorded in §6, Q2.                                                                                                                                                                                                                                                                                                                                                |
| `D-MD-NODEFAULT`      | 286              | Lossy    | `Faithful`   | `OTHERWISE` becomes a final catch-all row and `U` demotes to `F`; the answers are preserved, _"the order-free reading"_ is not. **The "answers are preserved" clause is load-bearing and was briefly FALSE (2026-07-31, repaired same day):** while `expressible` ignored the `<defaultOutputEntry>`, this note fired on tables whose catch-all had rendered as `-`, i.e. whose answers were _not_ preserved. It now cannot: an unsayable default routes the table to `D-MD-CELLSYNTAX` Blocking and this note does not fire at all. |
| `D-MD-TYPE`           | 295, 304         | Lossy    | `Faithful`   | a declared domain narrows to String/Number/Boolean/List. Valid inputs still answer the same.                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `D-MD-NOCONTEXT`      | added 2026-07-31 | Blocking | `Incomplete` | a hydrator is a boxed **context**, and dmnmd has no boxed-context form, so the decision is omitted. `Incomplete` matches its `D-MD-*` siblings, and the omission is larger than a literal's: downstream tables read derived components _through_ the missing decision.                                                                                                                                                                                                                                                               |

### 5.3.1 What this section is short by, and what its line numbers mean (dated 2026-07-31)

Three honesty obligations come with touching this file at all, and they are discharged here rather
than quietly worked around.

1. **This document is still a ruling, not an implementation.** Its status header says so, and it is
   still true: `FidelityEffect` does not exist in `jl4-core/src/L4/Interchange/Fidelity.hs`. The two
   rows added on 2026-07-31 (`D-COMPUTEDFIELD`, `D-MD-NOCONTEXT`) are therefore **documentation
   against an unimplemented ruling**, exactly like every row above them — an effect assignment
   nothing in the code reads yet.
2. **§5.2's table is short by more than the three codes the blockquote at the top of §5 admits.**
   It acknowledges `D-RULEDATE`, `D-RULEDATE-UNBOUND` and `D-DATEDCHAIN`. It does **not**
   acknowledge `D-SUMTYPE`, `D-MAYBE-NULL`, `D-ITEMDEF`, `D-FEELNAME` or `D-RENAME`, all of which
   exist in `Lower.hs` today and have no row here. Adding two rows does not make the table complete
   and this line exists so that a reader does not conclude it is.
3. **The line numbers in §5.2 are pinned to `3b9bfc6e` and no longer resolve.** They were accurate
   when the census was taken and are now approximate at best; the two rows added in 2026-07-31 say
   "added 2026-07-31" instead of inventing a line number that would be wrong on the same day it was
   written.

### 5.4 Summary

| effect        | codes  | of which Blocking | of which Lossy | of which Advisory |
| ------------- | ------ | ----------------- | -------------- | ----------------- |
| `Faithful`    | 20     | 5                 | 4              | 11                |
| `Unevaluable` | 2      | 2                 | 0              | 0                 |
| `Malformed`   | 1      | 0                 | 1              | 0                 |
| `Incomplete`  | 5      | 3                 | 2              | 0                 |
| `Misstated`   | 3      | 2                 | 1              | 0                 |
| **total**     | **31** | **12**            | **8**          | **11**            |

**SCOPE OF THESE FIGURES (2026-07-31).** The counts and the derived statistics below are **as of the
31-code census** and have deliberately **not** been recomputed for the codes added since. The reason
is not laziness: they were produced by `scratchpad/repair/final.py`, which **is not in this repo**, so
a recomputed number would be one nobody could re-derive or check — strictly worse than a number that
says which population it describes. Read the table as "the 31 codes that existed when the census was
taken", the same scoping the blockquote in §5 already applies to the never-fired list. Restoring the
script, or replacing it with one that lives in the tree, is what would let these be updated honestly.

The off-diagonal cells are the evidence that the axes are independent where the gate reads: 5
`Blocking`+`Faithful` codes (including `F1`, the most frequent note in the BPMN corpus) and 1
`Lossy`+`Malformed` code (`D-SCOPE`, 461 instances). If severity determined effect, this table would
be diagonal, and the issue would have no subject.

The `Advisory` column is a **structural zero on every row but the first**, and that is the invariant
in §3.2, not a coincidence. Mutual information over the 31 codes is **0.391 bits**, 25% of
`H(effect) = 1.573`: knowing the severity removes a quarter of the uncertainty about the effect, all
of it in the `Advisory` row.

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

**Q2 — is `D-MD-NODRG` really `Faithful`?** §5.3 rules `Faithful` on the ground that the requirements
are recoverable from column names; the note's own text says the opposite (_"which decision feeds
which is invisible"_). **What would decide it:** take a multi-decision module, export dmnmd, and try
to reconstruct the DRG from the markdown alone. If the reconstruction is ambiguous, it is
`Incomplete`, and dmnmd's `broken` rate goes from 98.2% to ~100%, which changes nothing
operationally — which is why the ruling does not wait for the answer.

**Q3 — how close does W3 get to the engine? — now partly answered.** §1.4 measured the **ceiling**:
364 of the 373 broken artifacts (97.6%) carry a broken boxed literal, so the raise site reaches
almost all of them. What is _not_ measured is the other half of the implication — whether
`feFragment == L4Verbatim` fires on exactly those expressions. Two known risks: (a) 34 artifacts
(6.7%) are `UNBOUND` with no `SYNTAX` error, and sampling them returns things like
`GIVEN x IS x30 y IS y32 YIELD x`, `Pair WITH px IS 3 py IS 5`, `CONSIDER e WHEN EVENT p a n THEN p`,
`JSONDECODE OF s` — raw L4 that happens to _parse_ as FEEL, and so should be `L4Verbatim`; but also
`TIMEZONE` and `Eligibility Rules.age >= 18`, which may render as `FullFeel` and be missed; (b) the
first draft quoted an instrumented figure of 351/507 = 69.2% from an earlier pass in this session —
**that number is withdrawn from the argument**, since it was never reproduced. **What would decide
it:** implement W3, run `feeloracle.mjs`, compare. That is §4.4's acceptance criterion.

**Q4 — does an `UNBOUND` name deserve its own code?** The oracle found 637 expressions referencing
names the model never defines. Some are raw L4 that the fragment flag will catch; some are genuine
name-resolution failures the exporter does not currently notice at all (`TIMEZONE`, `Jurisdiction
Library.Country Codes _ ISO 3166_1.Sweden`). If W3 leaves recall short of 95%, the fix is a new code —
call it `D-UNRESOLVED` — computed by checking each emitted expression's free names against the
model's own `inputData`/decision names, which is a static check the exporter can do in one pass.
**What would decide it:** Q3's number.

**Q5 — should the severity thresholds be deprecated outright?** §4.2 keeps them, on their own flag,
and documents `blocking` as "almost always true". The pandoc precedent (§2.3(iii)) argues for
demoting the target-cannot-express notes instead, which would make `--fail-on=blocking` meaningful
again. **What would decide it:** whether anyone reaches for `--fail-on=blocking`, is misled, and says
so. That is a usage question and cannot be settled from the corpus.

**Q6 — what happens when the report gets a wire format?** There is no `ToJSON` today (§3.4). When
track S2 ships one, `effect` needs a stable spelling, and the SARIF mapping is close enough to be
worth taking: `effect = Faithful` → `kind: "informational"` with `level: "none"`, everything else →
`kind: "fail"` with `level` from severity. SARIF also ships `kind: "open"` — _"the tool concluded
that there was insufficient information to decide whether a problem exists"_ (§3.27.9,
`sarif.txt:10072`) — which `FidelityEffect` has no counterpart for. **That was proposed in review and
is declined for now** (§9 F-A3): all 31 codes have an argued value, so an `Unknown` constructor would
be uninhabited, and an uninhabited escape hatch is exactly how "answer `Faithful` and move on" creeps
back in. **What would change it:** the first code whose effect genuinely cannot be determined at the
raise site. Recording the mapping here so it is not re-derived.

**Q7 — is `P-DANGLING` really `Faithful`?** Raised in review (§9 F-A5) and it is a fair question the
first draft answered by accident: the note is `Advisory`, and the first draft reasoned from
"nothing was lost" to "the document is sound" — which is the severity question answering the effect
question, inside the classification table. On the merits: the drawn End event **asserts a termination
the source never states**, which is structurally the same species as `P-MULTI-HENCE`. It survives as
`Faithful` on one ground only — the invariant in §3.2 (`Advisory ⟹ Faithful`) — and if the dissent
wins, the honest fix is to raise its severity, not to break the invariant. **What would decide it:**
whether a BPMN reader, given the diagram alone, would conclude the process ends there. That is a
question `bpmnlint` cannot answer and a human can; 39 corpus exports carry it. **Note also that none
of the five effect values names _over-assertion_** — the artifact containing more than the source —
which is the general form of this question.

**Q8 — how many engines is `Unevaluable` relative to?** Today, one profile: DMN Level 3, implied by
the omitted `expressionLanguage`. `lexipedia-superset/SPEC.md` K8 (locked the same day as this
ruling) commits to **two** ecosystems and a DMN flavour per ecosystem. Under per-flavour export the
same module yields two artifacts whose expressions differ in evaluability, and `FidelityEffect`
records one value with nothing naming which engine it is true of. **What would decide it:** the first
flavoured export. The cheap answer is already in the type — `FidelityReport` carries
`target :: Text`; make it carry the profile. Tracked as W12.

**Explicitly out of scope.** Setting `expressionLanguage` on non-FEEL literal expressions so the
artifact stops claiming to be FEEL (§1.4) is a real fix and a good one — it would make the emitted
model honestly Level-1 rather than dishonestly Level-3 — but it is an exporter change, not a
vocabulary change, and it belongs with the DMN program-model work.

---

## 7. Work items

In dependency order. **W3 is first, and it is the only one that moves a number.** W1–W2 are the
vocabulary; everything else follows from them.

| id  | work                                                                                                                                                                                                                                                        | where                                                                                  |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| W3  | **Raise `D-NONFEELOUTPUT` at `literalFallback`** — three lines, no type change, closes the 84.2% recall gap; ships and is useful alone                                                                                                                      | `Dmn/Lower.hs:1681-1692`                                                               |
| W1  | `FidelityEffect` + the `effect` field + `Enum`/`Bounded` on both enums; move the `Ord` comment onto the type; state `Advisory ⟹ Faithful`                                                                                                                   | `Fidelity.hs`                                                                          |
| W2  | thread the field through the 3 helpers positionally; answer all 32 sites per §5                                                                                                                                                                             | `Dmn/Lower.hs`, `Dmn/Markdown.hs`, `Bpmn/Lower.hs`                                     |
| W4  | `FidelityGate` record, `--fail-on-effect` option + reader, `broken` alias, `tripsGate`                                                                                                                                                                      | `Export.hs:101-106`, `139-150`, `199-208`, `406-415`                                   |
| W5  | tally + "broken codes" stderr line; `[minBound..maxBound]`                                                                                                                                                                                                  | `Export.hs:365-387`                                                                    |
| W6  | reword the notes whose `lost` text promises engine-evaluability, **and assert `isExecutable="false"` at its source with a §1.7 pointer**                                                                                                                    | `Bpmn/Lower.hs:1012-1056`, `Bpmn/Emit.hs:98`                                           |
| W7  | re-bless 5 goldens + 2 substring tests; add effect assertions beside the 29 severity ones; add an exhaustive §5 table test; add `--fail-on-effect` CLI rows                                                                                                 | `jl4/examples/**/expected/*`, `jl4/tests/{Dmn,Bpmn}Export.hs`, `jl4/tests-cli/Main.hs` |
| W8  | commit `feeloracle.mjs` as a corpus-level acceptance test and wire §4.4's ≥95%/≥95% criterion                                                                                                                                                               | new, under `jl4/tests-cli/` or `scripts/`                                              |
| W9  | re-rule `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7's 7 new codes + 1 repurpose; **do not delete `D-SCOPE`'s predicate** (§3.4 #19); collapse the `D-PARTIAL`/`D-RENAME` two-severity hacks                                                                       | `specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md:1065-1077`                                |
| W10 | docs: `Fidelity.hs` header, `Export.hs` haddock, both example READMEs, `SKILL.md`, `drafting-patterns.md`                                                                                                                                                   | as listed in §3.4 #18                                                                  |
| W11 | **the ratchet** — `--fail-on-effect=regression`: fail if the count of non-`Faithful` notes exceeds a checked-in baseline. SARIF ships this as `baselineState` (§3.27.24). Usable on all three targets at today's rates, which a threshold is not (§2.3(i)). | `Export.hs`, plus a baseline file format                                               |
| W12 | name the conformance profile in `FidelityReport`; re-pin W8's oracle to a K8 engine (Camunda or KIE) with `feelin` justified as a proxy                                                                                                                     | `Fidelity.hs`, `Export.hs`, `lexipedia-superset/SPEC.md` K8                            |
| W13 | **emit `<bpmn:incoming>`/`<bpmn:outgoing>`** and wire `bpmnlint` as the BPMN oracle; 91 errors across 3 shipped goldens today, no note reports them (§1.8)                                                                                                  | `Bpmn/Emit.hs`, new test                                                               |

---

## 8. Provenance

Scripts and data for every number above, under
`/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/`:

| file                                       | what it produced                                                                                                                                                                                   |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run_corpus.py`                            | `ruling/mycorpus.jsonl` — the full sweep behind §1.3                                                                                                                                               |
| `ruling/analyse.py`                        | the frequency and gate tables in §1.3                                                                                                                                                              |
| `ruling/sweep_dmn.py`                      | `ruling/art/` — 507 retained DMN artifacts + sidecars, `ruling/index.jsonl`                                                                                                                        |
| `ruling/feeloracle.mjs`                    | `ruling/oracle.jsonl` — the FEEL verdicts in §1.4, and the controls                                                                                                                                |
| `repair/nonartifacts.py`                   | §1.3's 894-attempt partition                                                                                                                                                                       |
| `repair/elements.py`                       | §1.3's element counts over all 507 artifacts (4590/4348/242, 94.7%)                                                                                                                                |
| `repair/bykind.py`                         | §1.4's broken-expression-by-element-kind table, incl. the 97.6% ceiling                                                                                                                            |
| `repair/verify.py`                         | §1.5's precision/recall table, incl. the `D-NONFEEL* ∨ D-SCOPE` row                                                                                                                                |
| `repair/scope.py`                          | §1.6 — 185 duplicates, 185 duplicate `<variable>`, 184 live references                                                                                                                             |
| `repair/final.py`                          | §3.2's mutual information, §4.4(a)'s selector table, §5.4's cross-tab, §2.3's entropies                                                                                                            |
| `repair/bl/` (`patch3.mjs`, `.bpmnlintrc`) | §1.8 — `bpmnlint` 11.12.1 + `bpmn-moddle`, before/after counts                                                                                                                                     |
| `feel/node_modules/feelin`                 | 7.0.1, `github.com/nikku/feelin`                                                                                                                                                                   |
| `dmn13.txt`                                | `pdftotext -layout` of OMG DMN 1.3 (**`formal/2021-01-01`**, March 2021); §7.3.4 `SHALL` at line 2971, §6.3 at 2654-2656, §7.3.5 at 3009-3021                                                      |
| `bpmn20.txt`                               | `pdftotext -layout` of OMG BPMN 2.0; §2.1 conformance at 1263, Common Executable sub-class at 1456, §2.1.4 Structural at 1594, Table 8.52 at 5533, Table 8.57 XSD at 5603, Table 10.1 at 7455-7468 |
| `sarif.txt`                                | tag-stripped OASIS SARIF v2.1.0 errata01; `kind` §3.27.9 at 10072/10223, `level` §3.27.10, `baselineState` §3.27.24 at 11100                                                                       |
| `Logging.hs`                               | pandoc `Text.Pandoc.Logging`, fetched; `Verbosity` at :40, the three `-> INFO` at :450, :465-466                                                                                                   |
| `repair/eslint-custom-rules.md`            | ESLint `docs/src/extend/custom-rules.md`, fetched; `meta.type` at lines 44-47                                                                                                                      |

**Every number in §1 was produced by a command run for this document or this revision**, against a
clean tree, with the command shown. One exception, flagged where it appears:

- the claim in `jl4/tests/DmnExport.hs:900-904` that these shapes were verified against Drools/KIE
  8.44.0.Final — _"loudly for an input expression or a firing rule, SILENTLY (null, status SUCCEEDED)
  for a defaultOutputEntry"_. That is a test comment written by someone else. It corroborates the
  FEEL oracle with a second, JVM engine, and it independently supports the `Unevaluable` /
  `Misstated` distinction (loud vs silent), but it is not my measurement.

The first draft carried a second exception — an instrumented `L4Verbatim` count of 351/507 = 69.2%,
quoted in §6 Q3 as corroboration and explicitly not vouched for. **It has been removed from the
argument entirely** and replaced by the reproduced 97.6% ceiling in §1.4.

**Known limit of the corpus figures.** Ten files — `jl4/experiments/jerseyCharities.l4` and the nine
under `paper/case-studies/charities-jersey-2014/` — exceeded the 180 s export timeout and are
excluded from §1.3, not measured. (Two do appear in §1.4's DMN-only sweep, which ran at 300 s.)
**That set is load-dependent, not a property of the files:** an independent re-run of the same driver
on the same tree timed out on only two of the ten, and `part-1-interpretation.l4` completed with 22
`D-LITERALEXPR` + 2 `D-SCOPE` (dmn) and 22 `D-MD-NOLITERAL` + 1 `D-MD-NODRG` (dmn-md). They are the
largest statutes in the corpus, so the direction of the bias is fixed — the DMN and dmnmd rates are
**understated, never overstated**. Raising the timeout and re-running is cheap and would close this.

**Reproducibility of the corpus run.** An independent re-execution of `run_corpus.py` agreed on the
note-code multiset for **2034 of the 2036** `(file, target, rule)` keys the two runs share; the two
that differ are exactly the two lost to a timeout in one run and not the other. Gate percentages
agree to 0.1 pp.

---

## 9. Review findings and their disposition

Adversarial review, 2026-07-27, three lenses: **(A)** attack the ruling, 11 findings;
**(B)** independent re-execution of every number, 13; **(C)** consumer enumeration and house style, 14. Thirty-eight raw, **thirty-five distinct** — three were raised by two lenses each (the `offering`
F1 count, the 894-attempt arithmetic, and the BPMN page-break quote). **None dropped.** Four changed
the ruling; three were **rejected on measurement**; the remaining twenty-eight were accepted and
repaired in place, grouped into the nineteen rows below.

Lens B reproduced every load-bearing number to the digit — the 31/32 code counts, all 25 frequency
rows, 8608 expression verdicts, 373/507 = 73.6%, both controls, all five precision/recall rows,
`D-SCOPE` TP=185/FP=0/FN=0, and all four §4.4(a) gate fractions — from a byte-identical re-run of the
oracle. Nothing in §1.4 or §1.5 was falsified. What was falsified were two arithmetic asides, several
citations, and one classification.

### Changed the ruling

| #         | Finding                                                                                                                                                                                                                                                                                            | Disposition                                                                                                                                                                                                                                                                                                                                                                                                       | Where                              |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| **F-A1**  | `D-SCOPE = Misstated` rests on an **unmeasured engine claim** — _"the model parses, loads, runs, and answers using whichever binding the engine picked"_. `feelin` cannot have measured it. The artifact violates DMN §7.3.4's normative `SHALL`, so no engine behaviour is defined.               | **ACCEPTED, and the enum gained a fifth value.** The sentence is deleted. `Malformed` added, with schema+`SHALL` validation as its third-party check. Two new measurements support it: **185/185** artifacts also carry duplicate `<variable>/@name`, and **184/185** have the duplicated name live inside a `<text>`. The §7.3.4 and §6.3 quotes are now in the document.                                        | §1.6, §3.1, §5.2, §4.4             |
| **F-A2**  | `Misstated`'s stated check (_"differential evaluation"_) is inapplicable to all three of its codes: one is DMN (removed by F-A1) and two are BPMN, which §1.7 rules never evaluates.                                                                                                               | **ACCEPTED, redefined.** `Misstated` is now _"a consumer applying the target notation's own semantics draws a conclusion the source does not license"_, with differential evaluation named as the DMN instance and reading-under-Chapter-14 as the BPMN one. That makes `P-MULTI-HENCE` fit properly and makes Q7 decidable.                                                                                      | §3.1, §5.1                         |
| **F-A4**  | The refutation of direction 3 — _"impossible"_, _"cannot be a lookup table … that is the design's whole point"_ — is **false**. `nonFeelOutput` is already a shared helper; `literalFallback` merely omits the three lines the select-idiom path has. After that fix, effect is constant per code. | **ACCEPTED; the pillar is withdrawn and the argument rebuilt on maintainability.** Measured: `D-NONFEEL* ∨ D-SCOPE` is **90.5%** precise today against the shipped gate's 74.6%. W3 is re-specified as "raise the existing code at the third site", **sequenced first**, and shown to be shippable alone at a 97.6% recall ceiling. Two supporting arguments (`P-DEADLINE`, §1.6-as-code-example) also withdrawn. | Ruling intro, §2.1, §2.2, §3.3, §7 |
| **F-A11** | `Sound` is document-scoped in its haddock and note-scoped in the type; and "sound" is already taken in `Dmn/Lower.hs` in ≥2 senses.                                                                                                                                                                | **ACCEPTED, renamed to `Faithful`.** Measured: `grep -nic '\bsound' jl4-core/src/L4/Dmn/Lower.hs` → **7** hits spanning the decision-table-analysis sense and the meaning-preservation sense. All five haddocks re-scoped to the note.                                                                                                                                                                            | §3.1, §5 throughout                |

### Rejected, on measurement

| #         | Finding                                                                                                                                                             | Why it does not land                                                                                                                                                                                                                                                                                                                                                                                         | Where          |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------- |
| **F-A3b** | Add a SARIF-style `Unknown`/`open` value, so a lazy porter has an honest escape hatch instead of answering `Faithful`.                                              | **DECLINED, with the trigger recorded.** All **31/31** codes have an argued value in §5 and the two dissents (Q2, Q7) have deciding experiments, so the constructor would be uninhabited on day one — and an uninhabited escape hatch is the mechanism by which "answer `Faithful` and move on" returns. The SARIF §3.27.9 text and the mapping are recorded in Q6 so the wire format does not foreclose it. | §6 Q6          |
| **F-A6b** | The empty `Unevaluable` cell for BPMN is unsafe because BPMN 2.0 only says execution information is _"typically"_ absent from a non-executable process.             | **ACCEPTED as a correction, REJECTED as a change to the classification.** The word "typically" is real and §1.7 now quotes the complete sentence and withdraws the appeal to BPMN. But the cell is empty for a **measured** reason that stands on its own: `("isExecutable", "false")` is a **literal** at `Bpmn/Emit.hs:98`, present in 3/3 goldens. The assertion moves to the source (W6).                | §1.7, §5.1, W6 |
| **F-C12** | `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` calls today's `D-SCOPE` predicate _"universal under GIVEN style, so pure noise"_, which contradicts this document resting on it. | **REJECTED as a contradiction, ACCEPTED as an unstated tension.** Measured: `D-SCOPE` fires on **36.5%** of DMN exports, not universally, and TP=185/FP=0/FN=0 against the artifact-level predicate. The two documents judge different objects. **But W9 executed as the other spec writes it would delete this document's only `Malformed` detector**, so §3.4 #19 now rules on the ordering explicitly.    | §3.4 #19, W9   |

### Accepted and repaired

| #                   | Finding                                                                                                                                                | Repair                                                                                                                                                                                                                                                                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **F-C7**            | `P-CYCLE = Incomplete` is contradicted by its own raise site; the quoted sentence does not exist. The loop **is** drawn.                               | Reclassified to **`Misstated`**, with the real message and `lost` quoted. Moves no number: `P-CYCLE` fires 0/1186.                                                                                                                                                                                 |
| **F-A1b / F-A5**    | The axes are not orthogonal: all 11 `Advisory` codes are `Faithful`, a definitional zero. `P-DANGLING` is `Faithful` only because it is `Advisory`.    | `Advisory ⟹ Faithful` is now a stated **invariant** with a required test (§3.2, W7); MI computed at **0.391 bits**; `P-DANGLING` dissent promoted to **Q7**, including the observation that no value names over-assertion.                                                                         |
| **F-A3 / F-A8**     | `Unevaluable` is engine-relative and K8 commits to two engines the same day; `--fail-on` would carry two vocabularies on one flag.                     | Profile caveat written into the `Unevaluable` haddock and into `D-NONFEEL`'s row; **W12** added. `--fail-on-effect` split out as a **second flag** (§4.2), quoting the test suite's own "threshold over a lattice" comment.                                                                        |
| **F-A7**            | `.fidelity.txt` is a wire format; printing the effect only when ≠ `Faithful` yields a **zero-line golden diff** for a lazy port.                       | #1 now prints the effect **always**; the format break is stated; §1.2's own grep is flagged as a casualty; an exhaustive §5 table test added to W7.                                                                                                                                                |
| **F-A9**            | The gate is sharp on 1 target of 3; dmn-md's `broken` is as saturated as the thing it replaces; a ratchet is what CI wants.                            | Entropy table added to §2.3 (**0.129 vs 0.105 bits** on dmn-md, stated as a genuine loss); **W11** (baseline ratchet, SARIF §3.27.24) added; §2.3(ii) records that BPMN's 8.0% is one code.                                                                                                        |
| **F-A10**           | The BPMN half has no external oracle; `bpmnlint` was never run.                                                                                        | **`bpmnlint` 11.12.1 installed and run** — new §1.8. 91 errors across 3 goldens, root cause isolated to missing `<incoming>`/`<outgoing>` (schema-legal, so not `Malformed`), **W13** added, and `P-NOJOIN` corroborated by an independent `fake-join` finding. §5.1 marked classified-by-reading. |
| **F-C1**            | Element counts skipped a dotfile artifact; 94.8% should be 94.7%.                                                                                      | Recounted over all 507: **4590 / 4348 / 242 → 94.7%**, corrected in §1.3, §1.5, §3.3.                                                                                                                                                                                                              |
| **F-C2**            | §1.3's non-artifact decomposition sums to 924 against 894, and mislabels its largest bucket.                                                           | Replaced with a partition table that sums to 894, with the command; the 30 timeouts are shown to be inside the columns, not additional.                                                                                                                                                            |
| **F-C3 / F-C2b**    | The Table 10.1 quote does not continue past a page break; §2.1.4 and §2.1 are the wrong section numbers; OMG doc number is wrong.                      | Complete sentence quoted; sub-class heading located inside §2.1.2 with §2.1.4 identified as "Structural Conformance"; DMN doc number corrected to **`formal/2021-01-01`**.                                                                                                                         |
| **F-C4 / F-C9**     | "13 times in one shipped golden (`F1` in `offering`)" — it is 5. "29 test assertions" — only **3** name those codes.                                   | Both corrected in §2.2 and §2.3(iii), against the document's own §1.7.                                                                                                                                                                                                                             |
| **F-C6**            | The codebase states this distinction ≥4 times, not twice; the producer prose is unlisted.                                                              | All four quoted in §1.5; `Dmn/Lower.hs:793-794`, `Bpmn/Lower.hs:490-491`, `:40-60` and `Dmn/Lower.hs:444` added to §3.4 #7 and #9.                                                                                                                                                                 |
| **F-C-M1/M2/M3**    | `BpmnExport.hs:1114-1120` unlisted; #15's golden diff omits 2 `P-NOJOIN` lines; golden harnesses unlisted.                                             | New row **#14b**; #15 rewritten with the harnesses and both diff sizes (all 5 under always-print; 5 lines under conditional).                                                                                                                                                                      |
| **F-C-M4/M5/M7/M8** | "no CI job" is wrong; `Fidelity` is an `exposed-module`; `metavar "SEVERITY"`; agent-facing docs unlisted.                                             | All four written into §3.4 — `pr-checks.yml:209`, `jl4-core.cabal:166`, `Export.hs:201`, `SKILL.md:225-230` + `drafting-patterns.md:207`.                                                                                                                                                          |
| **F-C-M9**          | Sibling specs unlisted and one is stale; #19 anchored too narrowly.                                                                                    | **Related** expanded (K4/K8, PROCESS-TRACK §5, CORPUS-TRACK); `lexipedia SPEC.md:294`'s _"schema-valid output that no engine could execute, reported as advisory"_ is the same conflation and is now cited as the parent-spec statement of it; #19's other four anchors added.                     |
| **F-C-D8/D10/D11**  | `F4`'s `lost` misquoted; five line-number drifts; "8 unbuilt codes" is 7 new + 1 repurpose.                                                            | All corrected: `Fidelity.hs:70-81`, `Markdown.hs:314-316`, `README.md:151`, `jl4-service.cabal:19`, the GHC transcript's two-line output.                                                                                                                                                          |
| **F-C-E1**          | ESLint/clang/rustc/bpmnlint asserted with no artifact; §8 omits pandoc's `Logging.hs`.                                                                 | ESLint **fetched and quoted** with line numbers; pandoc added to §8; `bpmnlint` now run (§1.8); **clang and rustc withdrawn** rather than asserted.                                                                                                                                                |
| **F-C-D13**         | §8's ten-timeout set is load-dependent, contradicting the blanket "every number" claim.                                                                | §8 now states the load-dependence, the independent re-run's two-file result, and the fixed direction of the bias.                                                                                                                                                                                  |
| **F-C-extra**       | §4.4(a) was computed with `D-LITERALEXPR` ⇒ `Faithful` while §5 said "computed" — the W1→W3 interim was ambiguous, and the wrong reading yields 98.6%. | §5.2 now states `D-LITERALEXPR = Faithful` outright (a consequence of the re-specified W3), and §4.4(a) names the alternative reading and its number.                                                                                                                                              |
| **F-C-H1**          | No review-disposition section, no revision line, no cross-references.                                                                                  | This section; the revision line and blockquote in the header; a pointer added to `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §7 and a Tier-2 row in `TIER1-WIP-INDEX.md`.                                                                                                                                   |
