# Projections of the Reg CF corpus

Everything on this page is **cut from `regcf.l4`**, the 1,236-line formalisation of 17 CFR Part 227.
Nothing here is transcribed. If a threshold changes in the corpus, it changes in every artifact
below on the next run, because no artifact below holds a second copy of it.

That is the entire competitive claim, so it is worth saying what it is a claim _against_: the
Lexipedia `reg_cf_exemptions` page carries prose and one hand-drawn BPMN diagram pasted out of
Camunda Modeler, with nothing connecting the two. The investor threshold appears twice on that
page and is stale in both places. A projection cannot do that. A projection can be **wrong** in
other ways, and the point of the last column of every table here is to say exactly how.

`README.md` is the authority on scope, on the nine places the mirrored page is wrong (§3), and on
what the corpus deliberately does not model (§5). This page is only about what comes _out_.

---

## 0. Everything, at a glance

| # | Artifact                                       | Files | Regenerate with                                    | Verified by                     |
| - | ---------------------------------------------- | ----- | -------------------------------------------------- | ------------------------------- |
| 1 | DMN 1.3 decision model                         | 2     | `l4 export … --to dmn`                              | `cabal test jl4:jl4-test`       |
| 2 | dmnmd markdown                                 | 2     | `l4 export … --to dmn-md`                           | `cabal test jl4:jl4-test`       |
| 3 | BPMN 2.0 processes (3 rules)                   | 6     | `l4 export … --to bpmn --rule …`                    | `cabal test jl4:jl4-test`       |
| 4 | Ladder figures (6 decisions × 4 carriers)      | 24    | `npm run demo:regcf` in `ts-shared/ladder-svg`      | `turbo run test` (drift guard)  |
| 5 | Deployable API / MCP surface                   | 1 `.l4` | `POST /deployments` to `jl4-service`              | `cabal test jl4:jl4-test`       |

Every one of 1–3 reproduces **byte for byte from the command line with no flags** other than
`--rule` (which selects _which_ process, since a BPMN document holds exactly one). That was not
true before 2026-07-27: the model name was hand-typed in the golden test, so the corpus's DMN model
had three different names at once. It now comes from the corpus's own outermost `§` heading.

Pin `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries` for every command on this page.

---

## 1. DMN 1.3 — `jl4/examples/dmn/expected/regcf-corpus.{dmn,fidelity.txt}`

```
l4 export jl4/examples/legal/regcf/regcf.l4 --to dmn \
   -o jl4/examples/dmn/expected/regcf-corpus.dmn --fidelity-report
```

**Measured 2026-08-02 on the shipped goldens (R12 + R13,
`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12/§16).** 67 `<decision>` elements — 9 decision
tables, 57 boxed literal expressions, 1 boxed context — plus 10 `businessKnowledgeModel`s (3 more
tables live inside them) and 7 `decisionService`s; 15 `<inputData>`, 149 `<informationRequirement>`
edges, 31 `<knowledgeRequirement>`s, one diagram. Loads clean in `dmn-moddle` — and **evaluates**,
over the 20 cases in `jl4/examples/dmn/regcf-corpus.cases.json` (the base world, 15 dated
relocation cases carrying the dropped rule-date fixtures' truths — ruling R-C, spec §15.12.1 —
and 4 seed cases added 2026-08-03): KIE 8.44.0.Final answers 1340/1340 decisions, 1340/1340
values as expected (280/280 decision-service output values); Camunda 8.7.6 (zeebe-dmn) parses and
answers 1340/1340. The
verbatim verdict lines live in
`jl4/examples/dmn/README.md` and are CI-gated (`.github/workflows/pr-checks.yml`, dmn-engines).

**A note on the neighbour.** `jl4/examples/dmn/reg-cf.l4` is a 101-line **toy** — five decisions
chosen so the goldens exhibit every outcome the exporter has. It is not this corpus and its own
header says its figures are illustrative. Both are kept, and both are labelled, because the toy is
a shape exhibit and this is the real thing. `expected/reg-cf.*` is the toy; `expected/regcf-corpus.*`
is the corpus.

### Fidelity: 0 blocking, 21 lossy, 125 advisory (measured 2026-08-02)

Re-derive every number in this section — the heading AND every row of the table — with
`node etc/go/lib/fidelity-counts.mjs jl4/examples/dmn/expected/regcf-corpus.fidelity.txt --json`,
whose `codes` object is exactly the × column below. The table is the whole emitted set: its three
severity columns sum to the heading, which is the arithmetic that catches a stale row.

| Code                 | ×   | Severity | What it means here                                                                                                             |
| -------------------- | --- | -------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `D-LITERALEXPR`      | 64  | advisory | not a guarded chain, so a boxed literal expression, not a table — the expression is FEEL and an engine evaluates it              |
| `D-RULEDATE-UNBOUND` | 15  | lossy    | `EVAL UNDER RULES EFFECTIVE AT`: a sub-graph under its OWN rule date, which a DRG cannot express — the decide is **not emitted** |
| `D-PARAM-AS-INPUT`   | 10  | advisory | un-lifting's cost: the decisions read one shared global where L4 bound per call site                                             |
| `D-COMPUTEDOUTPUT`   | 10  | advisory | the output entry is an expression, not a constant                                                                                |
| `D-BKM`              | 10  | advisory | a tier-2 callee emitted as a `businessKnowledgeModel`; call sites render as FEEL invocations                                     |
| `D-SVCEMPTY`         | 8   | advisory | a § for which no `decisionService` is emitted, named — the all-dropped arm and the shapeless arm                                  |
| `D-FLAVOR-NOSERVICE` | 7   | advisory | an emitted service is GROUPING only: no call site invokes it                                                                     |
| `D-FIXTURE`          | 7   | advisory | test scaffolding, not emitted; `--include-tests` restores it                                                                     |
| `D-INERT`            | 4   | advisory | statutory prose carrier with no operative logic, kept and flagged                                                                |
| `D-REGULATIVE`       | 2   | lossy    | an uncalled regulative body belongs to BPMN, not to a fake decision                                                              |
| `D-VERDICT`          | 1   | lossy    | the deontic reporting spine lowered to a verdict decision table; the obligation lifecycle is BPMN's                              |
| `D-UNDECOMPOSABLE`   | 1   | advisory | guard has no constant endpoint, so no interval analysis                                                                          |
| `D-SCOPE`            | 1   | lossy    | two differently-scoped `status` terms fold to one FEEL name; emitted as distinct globals                                          |
| `D-RULEDATE`         | 1   | advisory | the model is temporally parameterised; bind `RULES_EFFECTIVE_DATE` or every dated decision answers null                          |
| `D-RENAME`           | 1   | lossy    | the second `status` claimant is emitted as `status_2`                                                                            |
| `D-PARTIAL`          | 1   | lossy    | a partial source function consumed strictly; outside its domain FEEL answers null                                                |
| `D-ORDERDEPENDENT`   | 1   | advisory | `First` hit policy — DMN §8.2.10's own "has to be used with care"                                                                |
| `D-COMPUTEDFIELD`    | 1   | advisory | a hydrated itemDefinition's derived components carry no derived flag                                                             |
| `D-BKM-CONSUMERS`    | 1   | advisory | which decisions read each BKM, recorded                                                                                          |

`D-FEELNAME` is **zero by construction**: colliding FEEL names are renamed apart rather than
collapsed (`D-RENAME`). `D-NONFEELINPUT`/`D-NONFEELOUTPUT`, 89 `D-LITERALEXPR` **blocking**, 37
`D-RENAME` and 9 `D-SCOPE` — the 2026-07-31 census this table used to carry — are gone or shrunk
because Phase 5's BKM emission + un-lifting retired the verbatim `f(x)` family, and R12/R13
(`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12/§16) removed the two families that still
refused: the 15 law-time-rebinding scenarios (dropped, Lossy-noted) and the raw-L4 deontic spine
(now the verdict table). Ten of the twelve tables are rule-date interval tables carrying
`hitPolicy="UNIQUE"`; the movement arithmetic is in that spec's §15.7 and §16.3.

### What this projection **cannot** say

- **It executes — this bullet used to say "nearly inert", and stopped being true on 2026-08-02.**
  Phase 5's BKM emission retired the unevaluable `f(x)` family (tier-1 calls read shared inputs
  after un-lifting; tier-2 calls invoke `businessKnowledgeModel`s), and R12/R13 removed the last
  two refusing families. Both engines now answer all 67 decisions with every value as expected.
  What is still true: a DMN decision is a 0-ary variable, and the price of making the corpus fit
  that program model is itemised in the fidelity table above (the un-lift's shared globals, the
  dropped scenarios, the verdict split).
- **It cannot scope a name — but it no longer pretends otherwise.** L4 scopes a `GIVEN` to its own
  decision; DMN's `inputData` is global. Hydration shrank the flat namespace to 15 inputs, and the
  one surviving collision — two differently-scoped `status` terms — is renamed apart
  (`status`/`status_2`, `D-RENAME` ×1) rather than collapsed, which is why `D-FEELNAME` is zero.
  `D-SCOPE` still names the underlying collision; renaming makes the artifact loadable, not the
  scoping faithful.
- **It CAN say when a rule took effect — this bullet used to say the opposite.** The dated
  thresholds in `README.md` §2 lower to `hitPolicy="UNIQUE"` tables over a `RULES_EFFECTIVE_DATE`
  input, with half-open FEEL date-interval cells and an annotation column carrying each regime's
  name and its `@ref` citation (spec §15). What it still cannot say is a rule date **scoped to one
  decision**: the 15 `EVAL UNDER RULES EFFECTIVE AT` scenarios rebind law time locally, DMN has one
  global input and no scoped rebinding — so since R12 those decides are **not emitted at all**, and
  `D-RULEDATE-UNBOUND` ×15 (lossy) is the artifact saying so.
- **Its deontic content is verdicts, not obligations.** Groups 6, 7 and 8 are duties and
  prohibitions. Since R13 the reporting spine's guards ARE here — `ongoing reporting obligation` is
  a real `FIRST` decision table answering `"file a Form C-TR …"`/`"fulfilled"`/`"file a Form C-AR …
  and continue"` — but the obligation lifecycle (PARTY/MUST/WITHIN/HENCE/LEST) is BPMN's content
  (§3), consumed there by a gateway over the verdict strings; `D-VERDICT` records the split. The
  two uncalled regulative rules (`advertising restriction`, `resale restriction`) still have no DMN
  counterpart at all (`D-REGULATIVE` ×2).

_Fixed on the way here, so no longer in the loss list:_ 22 decisions used to emit FEEL that named a
value through the section heading it was declared under —
`investor._3. Investor investment limits _ Rule 100_a__2_.annual income`. `.` separates scopes in
L4 and traverses a value in FEEL, so that text parsed as a path and could never resolve; because it
_looked_ structured it never reached the verbatim fallback, so it was **silently** unevaluable
rather than loudly so. Section qualification is now dropped for export
(`L4.Syntax.unqualifiedNameToText`), which also un-prefixed every enum value in the corpus's one
clean decision table.

---

## 2. dmnmd markdown — `jl4/examples/dmn/expected/regcf-corpus.{dmn.md,md.fidelity.txt}`

```
l4 export jl4/examples/legal/regcf/regcf.l4 --to dmn-md \
   -o jl4/examples/dmn/expected/regcf-corpus.dmn.md --fidelity-report
```

**Measured 2026-08-02: 1,236 lines of law become ONE markdown table** — the R13 verdict table, as
it happens — and 301 lines of loss report. This is the most honest artifact in the set and the
least useful one, which is why it ships.

| Code                  | ×   | What it costs                                                       |
| --------------------- | --- | ------------------------------------------------------------------- |
| `D-MD-NOLITERAL`      | 57  | dmnmd has no boxed-expression form; the decision is **omitted**      |
| `D-MD-CELLSYNTAX`     | 31  | a cell dmnmd cannot read; the **whole table** is omitted             |
| `D-MD-NOBKM`          | 10  | dmnmd has no businessKnowledgeModel form; the BKM is omitted         |
| `D-MD-NOCONTEXT`      | 1   | a hydrator is a boxed context; dmnmd cannot say it                   |
| `D-MD-NODRG`          | 1   | 149 information requirements have no markdown form                   |

All 31 `D-MD-CELLSYNTAX` instances name a **date** cell: the rule-date interval tables are the one
thing the XML target gained and the markdown target cannot hold at all, because dmnmd's cell
grammar has no date datatype. (`D-MD-NONIDENTCOLUMN`, ×7 in the 2026-07-31 census, is zero on the
shipped goldens.) That is the two-target thesis doing its job on a real corpus.

### What this projection cannot say

Everything the DMN loses, plus: it is a table format, not a graph, so **which decision feeds which
is invisible**. The 149 edges that make the DRG single-sourced are exactly what does not survive.

---

## 3. BPMN 2.0 — `jl4/examples/bpmn/expected/regcf-{reporting,advertising,resale}.{bpmn,fidelity.txt}`

```
l4 export jl4/examples/legal/regcf/regcf.l4 --to bpmn \
   --rule "ongoing reporting obligation" \
   -o jl4/examples/bpmn/expected/regcf-reporting.bpmn --fidelity-report
# likewise --rule "advertising restriction" / "resale restriction"
```

All six goldens load in `bpmn-moddle` with **0 warnings**, every node drawn.

**This used to be the dishonest one, and it is worth saying how.** Until 2026-07-27 the corpus could
not be exported to BPMN at all — `l4 export --to=bpmn` exited 1 with "No regulative rules found in
module" — because `L4.StateGraph.findRegulativeExpr` peeled only `Where` and `LetIn` on its way to a
deontic head, and all three corpus duties are `IF`-headed. The CFR writes its guard _outside_ the
duty ("An issuer must continue to comply … **until** one of the following occurs", "**unless** such
securities are transferred: …"), so an isomorphic formalisation does too. A hand-written
`jl4/examples/bpmn/regcf.l4` stood in for the corpus, and it re-declared three deadline constants,
renamed four predicates, dropped the statutory chapeau, invented two `LEST` breach clauses the CFR
does not contain, and — because a `ROR` arm needs an obligation to hang a `PROVIDED` on — **silently
dropped the annual cycle's base case**, so the shipped diagram asserted a duty the corpus discharges.
That file is deleted. The extractor now reads `IF`/`ELSE` chains directly
(`L4.StateGraph.guardedIfBranches`) and none of those five divergences is expressible any more.

### What the diagrams now show that they could not before

- **The base case.** `Split_0 → End_2` carries
  `NOT (…may terminate…) AND \`annual cycles\` AT MOST 0`, the arm that imposes no duty at all.
- **The renewal loop.** `Task_4 → Split_0`. `HENCE <this rule> <state> (<cycles> MINUS 1)` is an
  application _with arguments_; it used to fall through to "unknown target" and produce a state
  literally named `next` with no successor, so the loop was reported as a dangling path and
  `P-CYCLE` could never fire. It now fires.

  The edge lands on the **gateway**, not on `Start_0`, and that is load-bearing rather than
  cosmetic: a `<startEvent>` is instance creation and BPMN gives it no incoming sequence flow. An
  earlier revision of this file drew `Task_4 → Start_0`, and two independent engines refused it —
  `etc/check-bpmn-soundness.mjs` with _"no start event to put a token on"_, and jBPM with
  _"A start node [Start_0, null] may not have an incoming connection!"_. Landing on the gateway is
  also what the rule says: the renewal re-tests the guards, it does not re-start the process.
- **Conditioned gateways.** Every branch flow out of an exclusive gateway carries a
  `conditionExpression`. They were emitted unconditioned, so the diagram read: pick an arm at
  random, do the work, _then_ test the condition that decided which arm applied.

### Fidelity

| File               | blocking | lossy | advisory | notes                                            |
| ------------------ | -------- | ----- | -------- | ------------------------------------------------ |
| `regcf-reporting`  | 4        | 3     | 1        | 2× `F1`, 2× `P-DEADLINE`, `P-BRANCHGUARD`, `P-CYCLE`, `F2`, `F5` |
| `regcf-advertising`| 2        | 2     | 1        | `F1`, `P-DEADLINE`, `P-BRANCHGUARD`, `F2`, `F5`  |
| `regcf-resale`     | 2        | 2     | 1        | `F1`, `P-DEADLINE`, `P-BRANCHGUARD`, `F2`, `F5`  |

### What this projection cannot say

- **A prohibition is not a shape.** `F1`, verbatim, on both `SHANT` rules: _"A prohibition is not an
  activity at all and BPMN has no negative shape for one, so read literally this diagram instructs
  the reader to perform the very act the rule forbids."_ `MUST`, `MAY` and `SHANT` all draw as a
  task. This is the single most important sentence on the page, because the wiki's hand-drawn BPMN
  has the same defect and no note.
- **No deadline is a timer.** `P-DEADLINE` fires on **every** boundary event. The corpus binds each
  period once (`regcf.l4:227-250`) and every consumer reads the binding, so a deadline is a _name_,
  and BPMN cannot make a timer out of a name. Inlining `5` and `120` would draw prettier diagrams by
  reintroducing exactly the duplication the corpus exists to remove. **The single-sourcing that
  makes the L4 good is what costs the timer.**
- **The gateway is not known to be exhaustive.** `P-BRANCHGUARD`: the conditions are opaque text in
  a `conditionExpression`, and BPMN has no way to say that the arms exhaust the cases and cannot
  overlap — which is precisely what the `IF`/`ELSE` chain they came from _does_ say.
- **Left-to-right stops meaning time.** `P-CYCLE` on the reporting process: this layout ranks a node
  by its longest path from the start, and a node on a loop has none.
- **A loop makes the gateway mixed, and not every engine has that shape.** With the renewal edge
  drawn, `Split_0` has two incoming flows (`Start_0` and `Task_4`) and three outgoing, so its
  `gatewayDirection` is `Mixed`. BPMN 2.0 permits that — §10.5.2 allows a gateway to be mixed —
  and `bpmn-moddle` reports 0 warnings. jBPM does not implement it: `Unknown gateway direction:
  Mixed`.

  The shipped file used to say `Diverging` here, which was simply false — §10.5.1 Table 10.100 says
  `Diverging` MUST NOT have multiple incoming — and neither script looked at the attribute, so it
  passed. `withGatewayDirections` now derives it from the edges, and
  `etc/check-bpmn-soundness.mjs` fails a file whose declared direction contradicts its own edge
  counts. Fixture: `jl4/examples/bpmn/unsound/mislabelled-gateway-direction.bpmn`.

  **jBPM's objection is to the shape, not to the word, and the earlier note here read the wrong
  constraint off its message.** The same three-node fixture, run three times with only
  `gatewayDirection` changed (`etc/check-bpmn-kie.sh`, jbpm-bpmn2 7.74.1.Final, JDK 17.0.20):

  | declared     | jBPM says                                                                            |
  | ------------ | ------------------------------------------------------------------------------------ |
  | `Diverging`  | `This type of node [Split_0, one of] cannot have more than one incoming connection!`  |
  | `Converging` | `This type of node [Split_0, one of] cannot have more than one outgoing connection!`  |
  | `Mixed`      | `Unknown gateway direction: Mixed`                                                    |

  So jBPM builds a `Split` or a `Join` from this attribute and enforces that node type's arity
  invariant; the `Diverging` message is about **incoming arity**, and quoting it as "jBPM refuses
  mixed gateways" attributes the rejection to the wrong thing. No value of the attribute makes jBPM
  accept a gateway with multiple of both.

  Drawing an explicit converging gateway before the split would satisfy it; it would also put a
  node in the diagram that the state graph does not have, so it is recorded here rather than done
  silently. `etc/check-bpmn-kie.sh` reports the rejection, and the `expected/` leg of that gate is
  tolerated at exit 1 in CI, as `handover.bpmn` already is for an unrelated reason.
- **A lane is not a bearer.** `F2`: a lane says who _performs_; L4's `PARTY` says who _owes_. They
  come apart whenever an agent acts for a principal.
- **There is no as-of date.** `F5`. Any number that _does_ appear is a value someone must remember
  to edit.

---

## 4. Ladder figures — `figures/*.{svg,txt,mmd,sentences}`

```
cd ts-shared/ladder-svg && npm run demo:regcf     # needs jl4-lsp; set JL4_LSP_CMD
```

Six decisions, four carriers each, all projected through the LSP from the corpus. See
`figures/README.md` for the subject list and why each was chosen.

|                                | dims        | leaves | sentences |
| ------------------------------ | ----------- | ------ | --------- |
| `regcf-exemption` (the root)   | 3027 × 185  | 61 ch  | 1         |
| `regcf-rule-100b`              | 912 × 571   | 78 ch  | 6         |
| `regcf-reporting-terminates`   | 1006 × 505  | 90 ch  | 5         |
| `regcf-resale-exceptions`      | 2683 × 444  | 304 ch | 4         |
| `regcf-transfer-permitted`     | 846 × 269   | 63 ch  | 2         |
| `regcf-intermediary`           | 2054 × 180  | 75 ch  | 1         |

### What this projection cannot say

- **Three of the six are not usable as page assets, untrimmed.** These are measured, not estimated,
  and unlike `demo/charities-a3.ts` — whose header admits its labels are "trimmed for the page" —
  nothing here is trimmed, because trimming is transcription.
- **AND is a ribbon.** In ladder logic a conjunction is a series circuit, so it lays out
  left-to-right with no wrap. The root decision — Rule 100(a)'s five conditions, plus a 118-char
  chapeau riding the wire — is a strip **16× wider than tall**. That is the picture a reader most
  wants and the one the notation handles worst.
- **Leaf labels never wrap.** Rule 501(a)(4)'s field name is 288 characters _because it is the
  CFR's own sentence_; it prints at 301 and occupies 2387.8 px in a single box. (291/304 before the
  clitic ruling dropped its leading `is `; the box figure read "≈2380 px" and was measured at 2411.4
  when re-derived on 2026-08-03, so it is now the number the SVG actually carries.)
- **A leading run of inert prose merges into one heading.** The mechanism is unchanged, but this
  corpus stopped tripping it on 2026-08-03: under the enumeration-label ruling each caption is
  truncated to its label and rides its own node (`.. "(1)" ... transfer's \`to the issuer …\``), so in
  `regcf-resale-exceptions` the heading is now the chapeau alone and all four labels sit on the wires
  into their rungs. Before the ruling the chapeau and caption **(1)** were one text element and a
  reader took "(1) To the issuer of the securities" for preamble.
- **The four carriers are not interchangeable.** `toMermaidRailroad` deliberately drops medial inert
  glue inside an `OR` (a railroad `choice` branch is a live path, and prose-as-branch would make the
  disjunction trivially satisfiable — correct, and documented in `mermaid.ts`). That discard is still
  there and still bites any rule that puts prose between two live `..` rungs; it no longer bites this
  one, because the labels are now inside their branches and the `.mmd` carries all four. **Do not
  treat one carrier as a stand-in for another.**

### The prose carrier, and its own limit

`*.sentences` is new, and it exists because the page this exhibit is measured against is _prose_,
while every other artifact here is a diagram, an XML model or a loss report. `expandSentences`
enumerates one sentence per way a rule can be satisfied — the surplusage view a compliance reader
actually reads — and it is a projection, so it cannot drift the way README commentary can.

It is a **disjunction** view, and it degrades on conjunctions. `regcf-rule-100b.sentences` is six
clean numbered limbs. `regcf-exemption.sentences` is _one_ sentence with all five conjuncts run
together with no connective, because an `And` cross-joins into a single product. Use the sentences
for OR-rooted rules and the ladder for AND-rooted ones.

### Drift

`figures/README.md` claimed "Nothing is retyped, so nothing can drift." True of the **generator**
and, until 2026-07-27, false of the committed **files**: `demo:regcf` needs a running `jl4-lsp`, so
CI never ran it and a corpus rename would have left the figures stale indefinitely — unlike the DMN
and BPMN goldens, which `cabal test` re-derives every run.
`ts-shared/ladder-svg/test/regcf-figures.test.ts` now closes the realistic half of that hole without
needing the LSP: every boxed leaf label in every `.txt`, and every `.sentences` title, must still be
findable in `regcf.l4`. It is **one-directional** — a leaf _added_ to the L4 and absent from a
figure still passes. Run `demo:regcf` for the real thing.

---

## 5. The deployable surface — `regcf-wizard.l4`

The corpus carries **zero** `@export` annotations by design, and
`tests/regcf.schema.golden` still reads `No @export annotations found in file`. A façade
(`regcf-wizard.l4`, `IMPORT regcf`) carries the deployment surface: six `@export`s, plain-English
field names, and prose fields that splice their figures out of corpus constants rather than
restating them. §7 of `README.md` covers it in full.

```
cd jl4/examples/legal/regcf && zip -r /tmp/regcf.zip regcf.l4 regcf-wizard.l4
curl -X POST http://HOST/deployments -F id=regcf -F sources=@/tmp/regcf.zip
```

### What this projection cannot say

- **`/state-graphs` returns `{"graphs":[]}` on every export.** The `IF`-headed-rule blindness that
  caused this is fixed — `l4 state-graph regcf.l4` now yields **3** graphs — but
  `l4 state-graph regcf-wizard.l4` still yields **0**, because `extractStateGraphs` walks the
  deployed module's own section tree and does not follow `IMPORT`. A façade cannot work around it:
  a wrapper calling an imported rule is an `App`, not a `Regulative`. Unfixed; whether an importing
  module "owns" an imported rule for extraction purposes is a design question of its own.
- **The atom ids do not line up, and the disagreement is internal to one response.** In a single
  `/query-plan` payload, `impact[…].support[].atomId` and the embedded `ladder` field's node ids
  have an **empty intersection** (measured: 2 ids each, 0 shared). The embedded ladder does agree
  with the standalone `/ladder` endpoint. So a client cannot join "what would change if this were
  false" onto the picture it is drawing.
- **A properly single-sourced façade has a boring ladder.** `asks: []`, `inputs: []`, two leaves —
  because both leaves are `App`s over records that the ladder cannot see through. Making the ladder
  interesting would mean restating the statutory connectives in the façade, i.e. reintroducing the
  duplication the exercise exists to remove. The six-limb Rule 100(b) picture already exists, cut
  from the corpus, at `figures/regcf-rule-100b.svg`.
- **`evaluation/batch` did not return a result.** With `outcomes` set, the response was
  `{"cases":[], "summary":{"casesRead":1,"casesIgnored":1,"casesProcessed":0}}`. Reproduced; not
  diagnosed.
- **`GET /webmcp.js` is 404** where `jl4-service/README.md` promises a 301.
  `/.well-known/{mcp,mcp/manifest,webmcp}` and `/.webmcp/embed.js` are all 200.

### Measured live (own service, own store, port 21877, torn down)

**This block predates the sixth `@export`.** `investment-limit-under-the-rules-effective-on` — the
law-time control — is absent from it, so the counts below are nine and five where a service run
against the current façade reports ten and six. Re-measured 2026-08-03 by `etc/go/phases/p7-mcp.sh`,
which records the count and the tool names on its receipt. The dated measurement is left as it was
taken rather than rewritten.

```
tools/list on /regcf/.mcp  → 9 tools
  can-this-company-raise  investment-limit-check  raise-check
  reporting-exit-check    resale-check
  list_files  read_file  search_identifier  search_text
openapi.json → 33 paths
```

Tool names are **bare**, not `regcf/raise-check`; a `-<prefix>` suffix appears only on collision
across deployments (`McpServer.hs:403-423`). `jl4-service/README.md` says otherwise and is wrong.

Sanitisation round-trips in all four combinations — spaced or hyphenated in the **path**, spaced or
hyphenated in the **keys** — all returning `10000`. It survives because all 49 façade fields
sanitise to ≤ 43 characters with no within-record collision. Exporting the **corpus** directly would
have broken it: 23 of its 41 field names exceed the 60-character cap (longest 285), and `227.503(a)`
and `227.201` both truncate to `section-227`.

---

## 6. Triage: findings closed here, and findings left open

### Fixed

| Finding                                                            | Where                                                    |
| ------------------------------------------------------------------ | -------------------------------------------------------- |
| Corpus could not be exported to BPMN at all                         | `L4.StateGraph.findRegulativeExpr`, `guardedIfBranches`   |
| Recursive `HENCE` drew a dangling `next` state; `P-CYCLE` unfirable | `L4.StateGraph.classifyTarget` → `TargetSelf`             |
| Exclusive gateway flows emitted with no condition                   | `L4.Bpmn.Lower` `branches`                                |
| Guard loss at a gateway went unreported                             | new `P-BRANCHGUARD` note                                  |
| BPMN fixture dropped the recursion base case (asserted a duty the corpus discharges) | hand-copy `jl4/examples/bpmn/regcf.l4` **deleted** |
| …invented two `LEST` clauses, re-declared 3 constants, renamed 4 predicates, dropped the chapeau | same deletion |
| Section headings spliced into FEEL as path steps (22 decisions)     | `L4.Syntax.unqualifiedNameToText`                         |
| …and in front of every enum value in the one clean table            | same                                                      |
| Section headings on every BPMN task and state-graph node            | `L4.StateGraph.resolvedToText`                            |
| `D-SCOPE` hardcoded "two" for an 8-way collision                    | `L4.Dmn.Lower` `englishCount`                             |
| DMN model name hand-typed; three names for one model                | `L4.Dmn.Lower.moduleTitle`, CLI default, test column removed |
| Façade told an accredited investor their limit was $10,000          | `regcf-wizard.l4` — `MAYBE NUMBER`, `NOTHING` when no limit |
| Service returned enum values backticked, violating its own declared schema | `Backend.Jl4.constructorText`                     |
| `NOTHING` serialised as the string `"NOTHING"`; `JUST x` not unwrapped | same site                                              |
| Every `@desc` carried a leading space into schemas and hovers        | `L4.Syntax.getDesc`                                       |
| Duplicate-content `POST /deployments` returned another deployment's id, created nothing | `ControlPlane.hs` — match on id as well as hash |
| Ladder figures had no CI coverage of any kind                        | `ts-shared/ladder-svg/test/regcf-figures.test.ts`         |

### Not a defect

- **"The DMN goldens are not CLI-reproducible."** They were, via the documented `--model-name`
  flag; the measurement that produced the claim used a bare invocation. The real defect underneath
  was the duplicated title, which is fixed — and the goldens now reproduce with **no flag at all**.
- **`D-SCOPE`'s parenthetical "does not match the list."** The parenthetical lists _decisions_, not
  terms, so it was never inconsistent. The genuine defect was the hardcoded count, above.
- **`P-DANGLING` "lost: nothing the source said".** That note was accurate about the state it named;
  what was wrong was that the state existed at all. Fixed upstream of the note.

### Open, and deliberately not fixed here

- `/state-graphs` does not follow `IMPORT` (§5).
- Query-plan atom ids and ladder node ids are disjoint (§5).
- `evaluation/batch` with `outcomes` (§5).
- `GET /webmcp.js` 404 vs the documented 301 (§5).
- `jl4-service/README.md` documents org-wide MCP tool names that do not match the implementation
  (§5).
- The ladder's AND ribbon, non-wrapping leaves and merged leading inerts (§4) are notation and
  layout work, not projection bugs.
