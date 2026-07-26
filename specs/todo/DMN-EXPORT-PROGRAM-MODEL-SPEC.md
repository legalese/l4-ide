# DMN Export — Program Model

_Status: **design, not yet implemented.** Supersedes the program model currently in
`jl4-core/src/L4/Dmn/{IR,Lower,Emit,Markdown}.hs`. Written 2026-07-26 on branch
`mengwong/dmn-export`._

**One-line summary.** The exporter today models an L4 module as _global scalars plus decisions
over them_ — the shape a module written with top-level `ASSUME` has. Idiomatic L4 is _functions
over threaded records_. This spec replaces the program model rather than patching the symptoms,
and does so from a single analysis: **un-lambda-lifting**.

Everything asserted here as "verified" was executed, validated or read out of a normative
document during the research pass; everything else is marked. §11 lists what is still open.

---

## 1. Why the current model is wrong

Verified empirically (harness positive-controlled against the committed `reg-cf` goldens,
byte-identical output):

| #   | Symptom                                                                                                                                                                                                        | Anchor                           |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| 1   | Free terms are keyed by `Unique`. Each decision's `GIVEN` is a separate `def`, so N decisions sharing a parameter name yield N `<inputData>` elements.                                                         | `Lower.hs:1201`                  |
| 2   | `assignIds` dedups the **id**; `idName = nm` does **not** dedup the **name**, and neither does the inner `<variable name=…>`. A probe emitted 9 `<inputData>`, three named `annual income`, two named `class`. | `Lower.hs:1359`, `Lower.hs:1219` |
| 3   | That output is **XSD-valid** — `DMN13.xsd` constrains `id` as `xsd:ID` but `name` as bare `xsd:string`, with zero `xsd:unique`/`key`/`keyref`. Validation catches nothing.                                     | `DMN13.xsd:29-40`                |
| 4   | A real engine **silently collapses** the duplicates. `@hbtgmbh/dmn-eval-js` 1.5.0 parses the model and evaluates every decision against the single context entry. Not a rejection — a wrong answer.            | executed                         |
| 5   | `D-SCOPE` fires once per colliding FEEL name. Zero notes under `ASSUME`; three in a GIVEN-style probe. A note written as a rare diagnostic is the normal case.                                                 | `Lower.hs:1245-1258`             |
| 6   | Record types erase to `Any` — `dmnTypeOf` sends a non-enum `TyApp` through `builtinType`, and `Emit.hs` has zero `itemDefinition` support.                                                                     | `Lower.hs:972`, `Emit.hs`        |
| 7   | Enum **domains** are discarded. `IS ONE OF` becomes bare `string`; no `<inputValues>` is ever emitted.                                                                                                         | `Lower.hs:973`, `Emit.hs:198`    |

The flagship exhibit `jl4/examples/dmn/reg-cf.l4` is itself `ASSUME`-style (5 top-level
`ASSUME`s, 0 `GIVEN`s), which is the only reason the goldens look clean. See the ASSUME→GIVEN
migration entry in `TIER1-WIP-INDEX.md` and PR #142.

---

## 2. The frame: DMN's DRG is a let-block

A DMN model is:

```
let inputData₁ = ⟨supplied⟩
    inputData₂ = ⟨supplied⟩
    decisionA  = expr over inputs
    decisionB  = expr over inputs and decisionA
in  ⟨whatever is asked for⟩
```

Single-assignment, non-recursive, all bindings at one scope level. `informationRequirement` is
not a call graph — it is "this binding's RHS mentions that binding".

An L4 module in house style is the **same let-block, lambda-lifted**: every binding has had the
ambient parameter pushed into its own signature.

```l4
GIVEN investor IS AN InvestorProfile
`greater of annual income or net worth` investor MEANS …

GIVEN investor IS AN InvestorProfile
`within the investment limit`           investor MEANS … `greater of …` investor …
```

So the translation is **un-lambda-lifting**, and DMN's answer to "where did the arity go?" is
_the model itself is the lambda_ — you invoke a DMN model by supplying its `inputData`. Arity
moves from each decision up to the model, where DMN puts it.

### 2.1 The analysis, stated once

For each top-level `DECIDE` `d` with parameters `p₁…pₙ`:

- **Un-lifts (tier 1)** if every reference to `d` within the scope unit applies it to the same
  argument expressions. Then `d` becomes a `<decision>`; each `pᵢ` becomes an `<inputData>`
  shared with every other decision that names it; and references to `d` are bare names carrying
  an `<informationRequirement><requiredDecision>` edge. Nothing is lost.
- **Does not un-lift (tier 2)** if `d` is applied to two or more distinct argument expressions.
  It is a real λ. DMN's word for a real λ is `businessKnowledgeModel` (§6).

This is one analysis producing the whole design. It also retires the "key by FEEL name instead
of `Unique`" idea as a standalone rule: **name-keying is the inverse of lambda lifting**, and
it is correct exactly when the un-lifting side-condition holds, not unconditionally.

### 2.2 The census says the frame is load-bearing

Measured across the three real corpora (Reg CF `regcf.l4`, `paper/case-studies/
charities-jersey-2014/`, `jl4/experiments/housing-act-*.l4`):

- **tier 2 is 2.7% / 4.0% / 4.3%** of parameterised decisions. It is a handful, not pervasive.
- **tier 2 correlates ≈100% with cross-module reuse** — 7/7 in Housing, 4/5 in Charities. The
  six `Ground N made out` roll-ups are tier 1 _inside their own file_ and become functions only
  when an aggregator imports them.
- **Arity is essentially always 1.** Every arity ≥3 decision in all three corpora turned out to
  be a test-fixture builder.
- **No decision is ever applied to a constructed record or a conditional.** The complete
  argument grammar to lower is: bare variable | projection chain of depth ≤2 | application of
  another decision or arithmetic | numeric literal. The hard cases occur only in fixtures.

The second bullet is the frame paying rent: within a module parameters unify, across modules
they cannot, because **each module is its own λ**. Which makes §11-R1 (scope unit) and "where
do we draw the lambda" literally the same question.

### 2.3 The λ boundary is the `§`, and DMN's word for it is `decisionService`

**Ruled 2026-07-26.** One `<definitions>` per L4 module; one `<decisionService>` per `§` section.
`tInvocable` is a `drgElement` (`DMN13.xsd:143`), so many services live in one model — the
"several models" fan-out was never forced.

The corpus draws the seam already. `part-3-charity-test.l4` has thirteen sections, and **every one
is homogeneous in its parameter** — `§§ Article 6(1) and 6(2)` and `§§ Article 6(5)` are
`p IS A CharitablePurpose`; `§§ Article 7`, `§§ Article 5(1)`, `§§ Article 5(2) and 5(3)` and
`§§ Article 5` are `c IS A CandidateCharity`. The section boundary is exactly where the parameter
changes. The author drew those boundaries by following the Act's Article structure and landed on
the λ boundaries. (The last section is labelled _"(the regulative layer)"_ — so `§` also seams the
DMN side from the BPMN side.)

**Why a service and not N BKMs.** A plain `<decision>` is a value, not a function; it cannot be
applied per list element. Only `decisionService` and `businessKnowledgeModel` yield a FEEL
function, and a BKM holds exactly one `encapsulatedLogic` — a `§` with ten `GIVEN p` decisions
would need ten BKMs with duplicated internal wiring. One service covers the section.

**Verified by execution** (Drools/KIE 8.44.0.Final, XSD-valid under Xerces, KIE validator clean),
on the real corpus shape — a service `Article 6` with six output decisions over one
`CharitablePurpose` input, invoked from the Article 5(1) side:

```feel
every q in c.purposes satisfies Article 6(q).meets the Article 6 test
```

→ `true` on a conforming charity, `false` when one purpose is a casino. Also verified: invocation
from a `literalExpression`; from a decision table's `inputExpression`, `outputEntry` **and**
`inputEntry`; inside `some` and `for`; from five distinct callers with different arguments; and
one level of service nesting. `for q in c.purposes return Article 6(q)` returns a list of
contexts, one per purpose, each carrying all six named sub-conclusions — **a free per-element
audit trace**, which is worth having for the explainability story.

Spec basis, not vendor behaviour: §10.4 — _"A decision service is semantically equivalent to a
FEEL function whose parameters are the decision service inputs"_; §10.3.2.13.2 — _"Invocable
elements (Business Knowledge Models or Decision Services) are invoked using the same syntax as
other functions"_. Quantifier bodies therefore get invocation for free.

This also resolves the higher-order worry. `all f (c's purposes)` passes a decision as a _value_,
which DMN cannot do — but η-expanding to `every p in … satisfies f(p)` never passes the function,
only applies it. `all`/`any` over a decision lower to FEEL quantifiers.

#### 2.3.1 Emission requirements

- **`<knowledgeRequirement><requiredKnowledge>` on every caller is mandatory.** The spec never
  says `SHALL`, but §10.3.2.11.2 puts the service's name in scope _only_ via that edge. Verified:
  removing it leaves the model XSD-valid and fails with `Unknown variable 'purposeTest'`.
- **Parameter order is `inputData` first, then `inputDecision`** (§10.4) — the **reverse** of the
  XSD child order (`outputDecision, encapsulatedDecision, inputDecision, inputData`,
  `DMN13.xsd:516-519`). Verified: `orderProbe(1, 2)` → `102`. **Emit named parameters at every
  call site.** Named binding is verified working, costs nothing, and sidesteps a portability
  detail engines are likely to get wrong.
- **Prefer one output decision per service.** A multi-output service returns a _context_, so
  callers must project a field — and that is where FEEL naming bites (below). A single-output
  service returns a bare value needing no projection. Cost: more services.
- **XSD is insufficient here.** The spec says `outputDecisions: Decision [1..*]` but
  `DMN13.xsd:516` declares `minOccurs="0"`, so Xerces passes a service with no outputs. KIE's
  _model_ validator catches it; schema validation alone does not.

#### 2.3.2 The hazard that constrains granularity: services can manufacture cycles

**Section granularity can create a cycle where the decisions have none.** With decision-level
dependencies `xf → yh → xg` — acyclic — putting `xf` and `xg` in one service because they share a
`§` makes `sectX → sectY → sectX`.

Spec §6.3.9-analogue: _"a DecisionService element SHALL not require itself, directly or
indirectly"_, its requirement subgraph being the union of its members'. So this is **ill-formed**.
But measured:

| check         | result                                     |
| ------------- | ------------------------------------------ |
| Xerces XSD    | **valid** — structural only, cannot see it |
| KIE validator | **clean** — does not detect it             |
| KIE runtime   | `top = null`, reported as **`SUCCEEDED`**  |

**A silent null under a SUCCEEDED status is the worst available failure mode for a legal
reasoner**, and nothing downstream catches it. The prohibition is spec-mandated; the detection gap
is KIE's.

**Therefore `§` is the _proposed_ seam, not the emitted one.** The exporter must run its own SCC
check over the **service-level** graph and, where a section would close a cycle, split it into
finer services until the graph is acyclic. Verified: the same decisions with the offending section
split into two single-output services evaluate correctly. Emit a note recording any split, since
the artifact then departs from the source's own sectioning.

#### 2.3.3 Two further hazards

- **Multi-output projection collides with FEEL naming**, and it upgrades §5 from a portability
  concern to a correctness one. `Article 6(q).is charitable or purely ancillary or incidental to a
charitable purpose` fails — FEEL parses the embedded `or` as the infix operator
  (`Unknown variable name 'purely ancillary'`) — and an output named `satisfies the Article 6 test`
  fails differently, because `satisfies` terminates the quantifier header. Both are FEEL
  name-vs-keyword problems in _projection_ position, and both disappear under §5.2's mangling.
  Note this does not contradict §5.1-3: a keyword as a name _part_ is fine for a declared name; it
  is the projection position after a call that breaks.
- **Argument types are not enforced at the call site.** Passing a `tCharity` where a `tPurpose` is
  declared returned `false` — no XSD error, no validator message, no runtime message, unchanged
  under `-Dorg.kie.dmn.runtime.typecheck=true`. §10.3.2.13 says a non-conforming argument list
  yields **null**, so KIE diverges, and the divergence is a silent wrong answer. L4 is typed
  upstream so the exporter can guarantee conformance itself — but do not expect DMN to catch an
  exporter bug.

#### 2.3.4 Encapsulation is a view, not a partition

All verified: an encapsulated decision may still be referenced from outside its service; two
services may share an encapsulated decision; one service's output decision may be another's
encapsulated decision; and services may nest, with the inner service needing no declaration on the
outer. That last one is what makes `§` inside `§` work directly.

One operational note: because a service's parameters must be top-level `<inputData>` elements,
`evaluateAll` also tries to evaluate the encapsulated decisions standalone with that input unbound,
emitting `Required dependency not found` errors and `[SKIPPED]` results alongside the correct
answers. `evaluateByName` and `evaluateDecisionService` both report zero messages. Cosmetic, but it
will confuse anyone driving the export from a test harness.

---

## 3. Decision-table columns are the typed bindings

This is the part the current design most underweights, and it reorders the work.

```
tInputClause  = inputExpression : tLiteralExpression   -- carries typeRef
              + inputValues?    : tUnaryTests          -- carries the domain
tOutputClause = outputValues?   : tUnaryTests
              + defaultOutputEntry? : tLiteralExpression
              @ name, @typeRef
```

(`DMN13.xsd:316-337`.) That is `let x : τ ∈ D = e`. Because `inputExpression` is a full literal
expression rather than a name, a projection `investor.annual_income` **is** a binding, typed at
its point of use. The columns materialise from what the decision reads; nothing declares them
globally.

**Consequence: columns come first, `itemDefinition` second.** A table is well-typed and
analysable from its columns alone. `itemDefinition` is needed only to type the `<inputData>`
element — the λ's parameter — which is a smaller, separable job (§4.3).

### 3.1 `inputValues` is what makes DMN's analysis mean anything

DMN 1.3 §8.2.4, normative:

> "It is important to model these expected input values, because a decision table will be
> considered complete if its rules cover all combinations of expected input values for all
> input expressions."

Completeness is assessed **against `inputValues`**, not against the type. §8.2.7 adds that they
validate the cells: _"The input entries in a unary test SHOULD be '-' or a subset of the input
values specified."_

Today the enum table in our own golden emits:

```xml
<inputExpression id="…_i1_expr" typeRef="string"><text>class</text></inputExpression>
```

— no `<inputValues>`, two rules, and a `<defaultOutputEntry>`. The domain
`{accredited, retail, institutional}` is nowhere, though `Lower.hs` computes `constructorNames`
and the `enums` set already. An analyser therefore sees an unbounded string column and cannot
assess completeness **at all**.

This means `reg-cf.l4`'s claim about that table — _"this table is INSIDE the fragment DMN's own
analysis is defined over"_ — is currently unearned. Not wrong about the fragment; the artifact
just hands the analyser nothing.

**Required:** emit `<inputValues>` for every column whose L4 type has a known finite domain.

```xml
<input id="…_i1" label="class">
  <inputExpression id="…_i1_expr" typeRef="string"><text>class</text></inputExpression>
  <inputValues><text>"accredited","institutional","retail"</text></inputValues>
</input>
```

### 3.2 `outputValues` unlocks two hit policies

`Emit.hs:198-199` declines outputValues because "we only know the values a table happens to
mention". True for a computed output; **false** for a boolean or enum-typed one. DMN 1.3 §8.2.5:

> "If provided, it is a list restricting output entries to the given list of values. … the
> ordering of the list of output values is used to specify the (decreasing) priority. The
> ordering … is also used when the hit policy is output order."

So `outputValues` is the precondition for hit policies **`P` (Priority)** and **`O` (Output
Order)**, neither of which the exporter can currently express. An L4 `CONSIDER` over an
enum-typed output supplies exactly the ordered list.

**Required:** emit `<outputValues>` when the output type has a known finite domain. Whether to
_use_ `P`/`O` is a later question; emitting the values is unconditional.

### 3.3 `OTHERWISE` stays a default — ruled 2026-07-26

With a finite domain in hand, `OTHERWISE` _could_ be expanded into explicit rules, making the
table literally complete rather than defaulted. **We do not do this.** Export stays isomorphic
to the L4; a consumer wanting completeness-by-enumeration performs the expansion itself, which
is a semantics-preserving normalisation derivable from `inputValues` + the default.

This is the rule the exporter already follows for negated prefixes (`DmnExport.hs` module
header): hit policy `FIRST` _is_ the "no earlier guard fired" quantifier, so restating it in
cells would produce a different, worse artifact.

Note the composition: **preserving `OTHERWISE` makes §3.1 load-bearing rather than optional.**
The default form says only "everything else", and "everything else" is computable only against
a declared domain. Isomorphic export is analysable precisely because the domain ships with it.

No change to the two spellings, both already correct: `<defaultOutputEntry>` under `UNIQUE` (a
catch-all row would overlap everything and make a `UNIQUE` table illegal), a final all-`-` rule
under `FIRST`.

#### 3.3.1 A defaulted table _is_ an incomplete table — and that is the point

Two normative statements settle what a default means, and they are stronger than "the default
covers the rest":

- Table 34, `defaultOutputEntry`: _"**In an Incomplete table**, this attribute lists an instance
  of Expression that is selected when no rules match."_
- Execution semantics: _"A decision table may have no rule hit for a set of input values. In this
  case, the result is given by the default output value, or null if no default output value is
  specified. **A complete decision table SHALL NOT specify a default output value.**"_

So a default does not close a gap — it **declares** one, and supplies the value taken in it.
Verified downstream: KIE/Drools 8.44 `ANALYZE_DECISION_TABLE` reports `DECISION_TABLE_GAP` on a
table with `inputValues` red/green/blue, rules for red and green, **and** a
`<defaultOutputEntry>` — `Gap detected: [ "blue" ]`. Mechanism confirmed at bytecode level:
`DMNDTAnalyser` never calls `getDefaultOutputEntry`. **That is not a KIE defect; it is the spec.**

This _strengthens_ the ruling above rather than threatening it. `OTHERWISE` in the L4 says
exactly "the enumerated rules do not cover everything, and here is what happens otherwise". The
defaulted DMN table says the same thing, and a gap report is that statement being read back
correctly. Expanding would _erase_ an assertion the source makes.

Two consequences to hold onto:

1. **The two spellings differ in completeness semantics, not just syntax.** `UNIQUE` + default is
   a declaredly incomplete table; `FIRST` + a final all-`-` rule is a **complete** one, since that
   row covers the remaining space. The exporter already emits both, so its `FIRST` tables are
   already analysably complete while its `UNIQUE` tables are declaredly not.
2. **Invariant, and it is a `SHALL`:** never emit a `defaultOutputEntry` on a table whose rules
   already cover the declared input space. Worth an assertion in the emitter.

Expect gap reports from any third-party analyser on `UNIQUE`-plus-default tables, and do not
treat them as noise to be suppressed — they are the artifact working.

---

## 4. Data model

### 4.1 Records ↔ itemDefinitions

`DECLARE T HAS f IS A τ` ↔ `<itemDefinition name="T"><itemComponent name="f" typeRef="τ">`.
Fields ↔ components, nesting ↔ nesting, projection ↔ FEEL path. **FEEL contexts are records**;
this is the tightest correspondence in the exercise.

### 4.2 Enums

`IS ONE OF` over nullary constructors ↔ `<typeRef>string</typeRef>` +
`<allowedValues><text>"A","B","C"</text></allowedValues>` on the itemDefinition, **and**
`<inputValues>` on every column that scrutinises it (§3.1).

**Both channels, because they are different scopes with different normative meanings.**
§7.3.3 (ItemDefinition metamodel): _"If an ItemDefinition element contains one or more allowedValues, the
allowedValues specifies the complete range of values that this ItemDefinition represents"_ —
that is the **type's** domain. `inputValues` is the **column's** expected values, and §8.2.4
ties completeness specifically to those. §8.2.4 also says _"Regardless of how the expected input
values are modeled"_, acknowledging that an analyser may derive a column's domain from the type
— so this is belt-and-braces rather than strictly redundant, and `inputValues` is the only
statement that is column-local. A column may legitimately be narrower than its type; L4 cannot
express that yet, but the emission shape should not foreclose it.

An enum with **non-nullary** constructors is a tagged union. FEEL has no sum type. Emit `Any`
plus a `Blocking` note; do not invent an encoding (see §11-R4).

### 4.3 Placement, and the validator trap

`itemDefinition` elements are **the first children of `<definitions>`** — before every
`<inputData>` and `<decision>`. `Emit.hs:118-131` currently builds
`map nodeXml drg.drgNodes <> [dmndiXml drg]`; item definitions must be **prepended**.

> **Do not trust `xmllint` as the gate.** libxml2 silently accepts `itemDefinition` placed
> _after_ `inputData`; Xerces rejects it with `cvc-complex-type.2.4.a`. A misordered emitter
> passes CI and then fails in Drools/Kogito and every other JAXP-based engine. See §9.

**Scalars get no itemDefinition.** Keep `typeRef="number"` for `GIVEN income IS A NUMBER`; an
alias adds no information and degrades for any consumer that does not resolve typeRefs. Mint one
for a scalar only when L4 supplies a domain.

---

## 5. Naming

### 5.1 What is actually broken

The research overturned the motivating worry. **Spaces work.** DMN 1.3 §10.3.1.4 "Tokens, Names
and White space" is normative (OMG issue DMN12-58 was resolved in 1.2 and the resolution
shipped); space-bearing names were verified evaluating in feelin 7.0.1, `@hbtgmbh/dmn-eval-js`
1.5.0 **and** Drools/KIE 8.44. **Hyphens work** too: `a-b` resolves to the joint name whenever
the joint name is declared, which an exporter always does.

So mangling is a **portability decision about Camunda** (whose engine does forbid whitespace in
names), not a correctness fix. What _is_ broken today is narrower and worse:

1. **`feelIdentText` passes dots through** — `keep c | c elem " _."` (`IR.hs:260-270`). An L4
   name containing `.` injects a FEEL path expression and silently shadows a genuine projection,
   with no warning. This is the E7 silent-misreading class, in our own code. **Fix this first;
   it is a defect independent of the whole redesign.**
2. **The same function is used for type names**, where a dot is DMN's import-prefix separator.
   Needs a separate `feelTypeNameText`.
3. **Keyword-_initial_ names** are the genuine hazard. §10.3.1.4: a name start SHALL NOT be a
   literal terminal symbol; a name _part_ MAY be. Keyword-inner is fine, which retires the worry
   about legal English being full of `in`, `for`, `between`.

### 5.2 The policy

`@name` carries a FEEL-safe identifier; `@label` carries the verbatim L4 name. `label` is an
attribute of `tDMNElement` (`DMN13.xsd:30`), xmllint-verified as available on every element type
this exporter emits. Round-trippability becomes a property of the sidecar, so mangling costs
nothing in readability.

**Stage 1 — `feelBase : Text -> Text`**, pure, deterministic, total:

1. Normalise to NFC.
2. Collapse every maximal run of Unicode whitespace to a single `' '` — engines normalise
   whitespace runs, so without this two distinct L4 names silently become one.
3. Map each character: keep FEEL name-start / name-part characters; otherwise `'_'`. **Space and
   `.` must now become `'_'`.** Map `?` to `_` as well: it is a legal name-start char but is
   S-FEEL's input-value placeholder in unary tests.
4. Collapse runs of `_`; strip leading and trailing `_`.
5. Empty → `"_"`. Leading digit → prefix `"_"`.
6. Reserved word → append `"_"` (list: `true false null and or not if then else for in return
some every satisfies instance of between function external date time duration list context`).

**Stage 2 — `uniquifyIn : Scope -> [Text] -> [Text]`** over a stable source-order traversal:
first claimant keeps the base, the nth gets `base_<n>` for the least free `n ≥ 2`. Two
independent scopes: (i) the DRG's FEEL variable namespace — all `inputData` variables and all
decision variables together, since they share one evaluation scope; (ii) each itemDefinition's
`itemComponent` list.

Stage 1 is deliberately non-injective; stage 2 makes the composite injective **within each
scope** by construction. Every rename — benign mangle and collision suffix alike — is a fidelity
entry, at **different severities**: a benign mangle preserves information in `@label`, a
collision suffix means the FEEL text no longer resembles the L4 name.

Net effect: `investor's \`annual income\``exports as`investor.annual_income`, with
`label="annual income"`on the variable, the component and the column. A mangled dotted path is
exactly S-FEEL's`qualified name`, so `Proj` (`Lower.hs:651`) stays classified `SFeel` — which
is what keeps record-reading columns inside the analysable fragment.

---

## 6. Call sites and BKMs

### 6.1 What is already right

`Lower.hs:678` — `App _ r args -> call e (feelIdent r) args`, rendering `f(x)` — **is correct**.
A FEEL invocation resolves against a BKM and evaluates, verified on Drools/KIE 8.44 in a
`<literalExpression>` and inside a decision table's `inputExpression` **and** `outputEntry`
cells. The bug is entirely on the **callee** side: the callee is emitted as a `<decision>` when
it should be a `<businessKnowledgeModel>`, and the `<knowledgeRequirement>` edge is missing.

The un-lifting analysis therefore decides **what kind of node the callee is**, not how the call
site is spelled.

### 6.2 BKM emission

Build it in v1. `encapsulatedLogic`'s body is `<xsd:element ref="expression"/>` and
`decisionTable` is in that substitution group, so **a parameterised guarded chain stays a
table** — no degradation to a literal expression. KIE's gap analyser fires on a table inside a
BKM identically to one in a plain decision, so this costs nothing in analysability.

Requirements:

- Child order (`xsd:sequence`, inherited first): `description?`, `extensionElements?`,
  `variable?`, `encapsulatedLogic?`, `knowledgeRequirement*`, `authorityRequirement*`.
  `formalParameter` is **not** a BKM child — it belongs to `encapsulatedLogic`
  (`tFunctionDefinition`).
- Emit `<knowledgeRequirement><requiredKnowledge href="#bkm_id"/></knowledgeRequirement>` on
  every calling decision. **Load-bearing and unenforced by the XSD** — omit it and KIE errors at
  both compile and eval time.
- Invariant: BKM `@name` == `variable/@name`. KIE's validator raises ERROR otherwise, and the
  two are resolved in different phases (compile-time name resolution vs runtime context
  binding).
- Formal parameters take the (mangled) L4 `GIVEN` names. DMN binds by **name**, L4 by
  **position**; emit bindings position→name at the seam.

Boxed `<invocation>` is an optional second form for a decision whose whole logic is exactly one
saturated call. It buys better modeller rendering plus a validator check ("Unknown parameter
'X'"), at the cost of not composing with a table body. Not v1.

**Why v1 and not deferred**, against the census's own recommendation: `meets the charity test`
is tier 2 with six call sites across four modules, and registration, deregistration,
required-steps notices and appeals all route through it. A v1 that refuses it exports a Charities
model **missing the statute's constitutive test**. Given BKM turns out to be cheap, refusing buys
nothing.

### 6.3 Refuse loudly — three cases, not BKMs in general

1. **Recursion.** DMN §6.3.9 (Business Knowledge Model metamodel): "a BusinessKnowledgeModel
   element SHALL not require itself, directly or indirectly". KIE
   evaluates recursive BKMs anyway (`fact(5)=120`) but emits a spurious eval-time ERROR and the
   behaviour is explicitly vendor-dependent. L4 permits recursion (`rent spine`, `ror together`
   in Housing). Needs a cycle check with its own `Blocking` note — see §11-R5 for where it lives.
2. **Partial application / higher-order.** A BKM is a first-order named function only.
3. **Non-KIE target engines.** `@hbtgmbh/dmn-eval-js` has no BKM support and fails **silently**:
   an unresolvable callee in a cell logs `resolved to undefined` and the table falls through to
   the next rule, returning a plausible wrong answer. If the exporter claims a target engine,
   gate BKM emission on it.

---

## 7. Fidelity notes

| Code               | Change                                                                                                                                                                                                                                        | Rationale                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `D-SCOPE`          | **Repurpose.** Today it fires on "two Uniques, one FEEL name" (`Lower.hs:1245-1258`) — universal under GIVEN style, so pure noise. Replace the predicate with a **type conflict** test: two same-named terms with _different_ declared types. | `freeTermTypes` is a plain `Map.fromList` (`Lower.hs:1228`), i.e. **last-wins** — that is the genuine defect currently hidden behind the false positives. Also fix: the message hardcodes "two different terms" for 3+, anchors only to the first element's id, and its `lost:` text ("L4's lexical scoping of GIVEN parameters") is false when two global `ASSUME`s collide. |
| `D-PARAM-AS-INPUT` | **New**, `Advisory`. A tier-1 decision's parameters became model inputs; the decision can no longer be applied twice to different subjects within this model.                                                                                 | Names what un-lifting costs, without pretending it is free.                                                                                                                                                                                                                                                                                                                   |
| `D-BKM`            | **New**, `Advisory`. A tier-2 decision became a BKM, with the differing call sites listed.                                                                                                                                                    | The reader should know which decisions are functions.                                                                                                                                                                                                                                                                                                                         |
| `D-RECURSIVE`      | **New**, `Blocking`. §6.3 case 1.                                                                                                                                                                                                             |                                                                                                                                                                                                                                                                                                                                                                               |
| `D-SUMTYPE`        | **New**, `Blocking`. §4.2, tagged union.                                                                                                                                                                                                      |                                                                                                                                                                                                                                                                                                                                                                               |
| `D-RENAME`         | **New**, two severities. Benign mangle = `Advisory` (recoverable from `@label`); collision suffix = `Lossy`.                                                                                                                                  | §5.2.                                                                                                                                                                                                                                                                                                                                                                         |
| `D-MD-FLATRECORD`  | **New**, `Lossy`, markdown carrier only. §8.                                                                                                                                                                                                  |                                                                                                                                                                                                                                                                                                                                                                               |

---

## 8. The markdown carrier

**Under record threading the markdown emitter currently produces _nothing_** — not a degraded
table, zero tables. Verified by running it: every table dies on `D-MD-NONIDENTCOLUMN` because
`Lower` renders a projection as a FEEL qualified name and dmnmd's `parseVarname` admits no `.`;
`dmnmd -f md` over the result then prints `** parser failure in grepMarkdown`, because a
table-free file is not a case its fallback handles.

So this is not a nice-to-have. **Day-one behaviour: flatten, keeping the thread variable as a
prefix.** `i.annual_income` → column `i annual income : Number`, one column per projected _path
actually used_, one `D-MD-FLATRECORD` note per table. Verified end to end: the flattened
markdown parses and `dmnmd -t l4` returns well-formed L4.

It is the least-lying option because the lie is confined to the **type** level — cells, rules,
hit policy and outputs are bit-identical to the scalar form, so the table decides exactly what
the record version decides. What is lost is that `i annual income` and `i net worth` came from
one object. Keeping the prefix is not cosmetic: it is what makes the flattening injective when
two records share a field name.

State the round-trip property in the contract as **L4 → md → L4′ equal modulo record
flattening**, rather than letting a golden discover it.

Three consequences for `~/src/smucclaw/dmnmd/BUILD-SPEC-dmnmd-extensions.md`, to be handed over
as an addendum (l4-ide still never depends on that repo):

1. **E1 is specified against the program shape being replaced.** Under threading, a reference to
   another decision is `annual limit basis(i)`, not `annual limit basis`, so E1's
   output-column-name matching resolves **zero** edges in the new corpus. Rewrite before anyone
   builds it.
2. **Enum domains want a home in the markdown grammar** — E8's existing subject. Note for the
   dmnmd session, not a constraint on this spec: at time of writing dmnmd parses
   `itemDefinition` and ignores it, so an XML→md→L4 differential would not today observe a
   domain carried only on the type. That is a snapshot of a component under active redesign and
   should not drive our emission; §3.1/§4.2 justify both channels from the DMN spec alone.
3. A new item — record types have no home in a pipe table — for the flattening above.

**dmnmd's current behaviour is not a design input.** It is under substantial redesign; this
spec's obligations to it are limited to the standing contract (emit strictly within the grammar
of the day, record every gap as a `D-MD-*` note, never depend on the repo). Where dmnmd's
present state is mentioned above it is reportage for the dmnmd session's benefit, and any of it
may be obsolete by the time either side ships.

---

## 9. Verification plan

- **Schema: Xerces, not libxml2.** Add a JAXP-based check to the export suite (~20 lines, system
  JDK only). Without it a misordered emitter passes CI and fails in every real engine (§4.3).
- **A negative golden** `M1-itemdef-after-inputdata.dmn`, precisely because it is the case the
  obvious validator misses.
- **Execution, not just validation.** Drive emitted models through Drools/KIE 8.44 (TCK
  reference implementation). Schema validity is not engine acceptance — the duplicate-name bug
  validated cleanly and produced wrong answers.
- **Fix the test harness's own hole first.** `drgNamed` (`jl4/tests/DmnExport.hs:808`) matches
  only `Left` from `checkWithImports`; **type errors come back inside `Right` as `tcdErrors` /
  `tcdSuccess=False`** (`Resolution.hs:265-279`) and are ignored, so the whole DMN suite
  currently accepts ill-typed L4. Same defect class as `jl4-service/src/Compiler.hs:68` — two
  occurrences make it worth a lint rather than two fixes.
- **Re-cut the exhibit** from the real 981-line GIVEN-style Reg CF corpus
  (`../l4wt/regcf-corpus/jl4/examples/legal/regcf/regcf.l4`) rather than the 5-`ASSUME` toy.
- **Open empirical question, answerable not arguable:** does KIE's gap analyser perform the
  `OTHERWISE`-expansion given `inputValues` + a `defaultOutputEntry`? A KIE 8.44 classpath
  exists in the session scratchpad; run it, with a genuinely-gapped table as positive control.

  **Phrase the resulting claim carefully.** Two different things get called "DMN's analysis":
  1. the **analysable fragment** — a mathematical property (Calvanese et al.), vendor-independent
     and true of the artifact whether or not anyone runs a checker;
  2. an **implementation** of completeness/overlap checking, which appears to vary by vendor and
     is believed _not_ to be part of DMN conformance testing (the TCK looks to be runtime
     evaluation only — being verified).

  The defensible claim is therefore about (1) plus artifact adequacy: _this table lies inside the
  fragment for which completeness and overlap are decidable, and the emitted artifact carries the
  domain information such a checker requires._ That is true regardless of vendor uptake. "DMN
  validates this" is the claim to avoid, and it is the one §3.1 says we have not even earned in
  the weaker form, because we ship no domain at all.

---

## 10. Sequencing

Each phase is independently shippable and independently useful.

| Phase | Content                                                                                                            | Depends on |
| ----- | ------------------------------------------------------------------------------------------------------------------ | ---------- |
| **0** | Kill the dot passthrough in `feelIdentText` (§5.1-1). Fix `drgNamed`'s type-error hole (§9). Add the Xerces check. | —          |
| **1** | Columns: `typeRef` + `<inputValues>` / `<outputValues>` from L4's known domains (§3).                              | 0          |
| **2** | Naming policy: `feelBase` + `uniquifyIn`, `@label` everywhere, `feelTypeNameText` (§5.2).                          | 0          |
| **3** | `itemDefinition` emission and placement; records and enums at the data level (§4).                                 | 2          |
| **4** | The un-lifting analysis; `D-SCOPE` repurposed; `D-PARAM-AS-INPUT` (§2.1, §7).                                      | 3          |
| **5** | BKM emission, `knowledgeRequirement`, the three refusals (§6).                                                     | 4          |
| **6** | Markdown carrier: flattening + `D-MD-FLATRECORD`; dmnmd addendum (§8).                                             | 3          |

Phase 1 alone makes the existing exhibit's analysability claim true, which is worth shipping on
its own.

---

## 11. Open rulings

- **R1 — Scope unit. ANSWERED 2026-07-26, see §2.3.** Not module-vs-closure: one `<definitions>`
  per module, one `<decisionService>` per `§`. The "several models" fan-out was never forced —
  `tInvocable` is a `drgElement`, so many services live in one model. The residual sub-ruling is
  §2.3's **service granularity**, which is a constraint to satisfy rather than a preference to
  choose.
- **R2 — Strictness.** DMN computes every _required_ decision; L4 forces lazily. Un-lifting
  widens the input set a shared node is evaluated under, so it makes this worse, not better. A
  decision undefined or divergent for some inputs will surface in DMN on paths L4 never forces.
  Proposed: a strictness side-condition on un-lifting, refusing to merge a parameter whose
  decision is not total. **Not settled — flagged deliberately rather than assumed benign.**
- **R3 — Unicode in `feelBase`.** Keep FEEL-legal non-ASCII name characters (spec-legal;
  `feelin` evaluates `revenu année` natively) or ASCII-fold? Today's `feelIdentText` destroys
  them (`année` → `ann_e`). Leaning keep, with a fold behind a flag.
- **R4 — Tagged unions.** `Blocking` refusal, or a context with a discriminant plus optional
  payload fields and a `Lossy` note? Leaning refusal for v1; the corpora do not need it.
- **R5 — Where the acyclicity check lives.** In `Lower`, or as a pre-emission well-formedness
  pass? L4's one-pass scope checker does not currently admit forward references among top-level
  `DECIDE`s, so no module can produce a cycle **today** — but §6.3-1 recursion is reachable
  through local recursion. `Lower.hs:1339-1349` already documents this as a deliberate gap.
- **R6 — The uncalled population.** 44% of Charities decisions and 18% of Housing are never
  called. They are DRG roots; a parameterised uncalled decision has no supplied input. Becomes a
  decision with `inputData` synthesised from its `GIVEN`, or dropped?
- **R7 — Target engine.** Is Camunda a target? If nobody will open these files in Camunda
  Modeler, §5's mangling collapses to "just stop emitting dots", since spaces work everywhere
  else. If it is, the full policy applies — and BKM emission needs gating (§6.3-3).

---

## 12. Non-goals

- **`legalese/l4-ide` never depends on `smucclaw/dmnmd`.** dmnmd is local differential
  validation. Gaps go into its extension spec as an addendum; the exporter degrades honestly
  with `D-MD-*` notes until they land. Neither side waits on the other.
- Not a general DMN implementation. No decision services, no DMNDI layout beyond what is already
  emitted, no FEEL evaluation.
- Not the process side. `Regulative`/`Deonton` targets BPMN 2.0 (PR #141) and has no markdown
  carrier.
