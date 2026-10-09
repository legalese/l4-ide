# Presumption and assertion: the contract for evaluators and exporters

**Status:** proposed, 2026-10-09; nothing in this document is built.
It is the normative statement of a design whose measurements are in `../PRESUMPTION-SCENARIOS.md` and whose one ruling so far is §7 there (Meng, 2026-10-09, in chat): named derived nodes may be asserted by a request, default-open, opted out by `@nonassertable`, with an `asserted` list in the answer.
Every other choice here is **assumed, not ruled**, is marked so, and is made so that it can be reverted alone.
Where a sentence describes what the tree does today it says _today_ and cites a line at `c6d081622`.

**Who this is for.** Anyone implementing an evaluator that answers requests (jl4-core, jl4-service, `l4 batch`, jl4-mlir, the ladder's TypeScript evaluator) or an exporter that projects L4 into another system.
The ladder diagram is the reference semantics: where a sentence here is unclear, the picture decides, and §2 says which parts of the picture are semantics and which are only drawing.

**Owning documents this touches.** `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` (T1, T3, T4, T6, TU-wire-b), `IMPLICIT-PROPS-DESIGN.md` §11.5 (R8), `SURFACE-SUGAR-CLUSTER-2026-09.md` (D7.3), `UNKNOWN-EVALUATION-SPEC.md` (§5, U8, U9, U10), `UNKNOWNS-BACKEND-CONTRACT.md` (a description of the tree), `RUNTIME-INPUT-STATE-SPEC.md`, `ladder-diagrams-2026/DESIGN.md` (§19, §22, §26, §27).
§12 lists which of their sentences this document supersedes.

---

## 1. Vocabulary

- **Input.** A fact the exported rule is `GIVEN`, a section `GIVEN` it reads, or a field of a record among those.
- **Named step**, or **node.** A definition with a name that the exported rule relies on: a `WHERE` local of the rule, or a definition at section or module level.
  In the ladder a node is a box (a leaf) or a group (a fold).
- **The root.** The exported rule's own result.
- **Source** of a value, one of four:
  - **supplied**: the request gave the input a value;
  - **asserted**: the request gave a named step a value (§4); supplying an input is the leaf case of asserting, and this document uses _asserted_ for named steps only;
  - **derived**: worked out from the node's definition;
  - **presumed**: taken from a `TYPICALLY` because nothing supplied or asserted it (R8, T1).
- **Forced.** A value is forced when the evaluation reads it.
  Reporting is by forcing (T6, today): a presumption or assertion the evaluation never read is not listed.
- **Soft / hard.** The presumption switch (T4, TU-presume; today: `--presumption`, `"presumption"`).
  Hard withholds presumptions; it never withholds supplied values or assertions.
- **Absent / `null`.** T3's two absences on the wire, today: a key left out is a gap; `null` is "not known", a value on a `MAYBE` and a refusal elsewhere.
  This document does not change T3.

## 2. The ladder as reference semantics

The ladder core already models every concept above, positionally.
Implementers should read the following as the definition and copy the first table, not the second.

**Semantics (copy these).**

| concept                  | ladder                                                                                                                           | where                                                                          |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| a node                   | `NodeId`, a box or a group                                                                                                       | `types.ts:236–241`                                                             |
| supplied / asserted      | an entry in `ViewSpec.valuation`; on a group it is an **override**: the group takes the value and its children are not consulted | DESIGN §19 (`:734`); `types.ts:236–241`                                        |
| presumed                 | an entry in `ViewSpec.defaults`, laid _under_ `valuation`; `valuation` wins where both have an entry                             | DESIGN §22 (`:873`); `types.ts:247–262`; `effectiveValuation`, `layout.ts:321` |
| derived                  | a group with no entry of its own derives from its operative children, three-valued                                               | DESIGN §6, §19                                                                 |
| soft / hard              | `ViewSpec.respectDefaults`: true lays the defaults under, false withdraws them                                                   | DESIGN §26.3; `layout.ts:308–322`, `:428–433`                                  |
| provenance               | `ViewSpec.provenance`: `given` or `default` per node; this design adds `asserted` for a group carrying an override (§5.4)        | DESIGN §22; `types.ts:30–40`                                                   |
| what the answer rests on | the overrides and defaults the current actually flowed through                                                                   | `energize`, `layout.ts:462–514`                                                |
| the root                 | the diagram's output; it carries no entry of its own                                                                             | DESIGN §19                                                                     |

**Drawing (do not copy these into an evaluator).**

| rule                                                                                | why it is UI only                                                                                | where                               |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------- |
| an override on a call panel holds only while the panel is folded (`dropOpenPanels`) | it keeps an open drawing honest; an evaluator has no open or folded state                        | DESIGN §27.1; `layout.ts:1033–1042` |
| one click sets the value on every box with the same `atomId` (`spreadValue`)        | a gesture, not a semantics; the wire names a node once                                           | DESIGN §27.1; `viz-adapter.ts`      |
| click cycles U → T → F → U                                                          | a gesture                                                                                        | DESIGN §19                          |
| `types.ts:38`: "a group's value derives; it is never presumed"                      | true today; §7 proposes a presumption on a named step, which would give `defaults` group entries | `types.ts:38`                       |

One consequence of taking the picture as the definition: **an assertion on a group subsumes conflicting children** (DESIGN §19's "override, without a witness").
The contradiction-detecting alternative is deferred there and deferred here (§13).

## 3. Scope of a named step in this version

**Assumed, not ruled.** A request may assert a definition that is **nullary in the evaluation**: a `WHERE` local of the exported rule, or a section- or module-level definition that takes no `GIVEN` of its own.
Section `GIVEN`s it reads are fixed for the evaluation and do not make it parameterised.

A definition with its own `GIVEN` is applied, possibly several times with different arguments, and the ladder draws each application as a call panel keyed by position (DESIGN §27; `WHERE-INLINING-SPEC.md` §10.1).
Asserting one application needs an argument-indexed address, and this version does not define one (§13).
An assertion naming such a definition is refused: "`is creditworthy` takes inputs of its own; an application of it cannot be asserted by name".

**Why this scope.** It is exactly the set of nodes the evaluator already treats as 0-ary definitions, which is the seam `RootFills` uses today for filled defaults (`EvaluateLazy.hs:756–760`; `Jl4.hs:463–475`, `:1081–1091`), and it covers the door-number-two case, which is a `WHERE` group.

**Name resolution.** A name in `assertions` is resolved as L4 resolves it in the exported rule's body: a `WHERE` local shadows a module-level definition of the same name.
A name that resolves to nothing is refused with the nearest declared name, as `unrecognisedMessage` does for inputs today (`Presumption.hs`).

## 4. The wire

### 4.1 Request

**Assumed, not ruled.** Beside `arguments`, a request may carry `assertions`, an object from node name to value:

```json
{
  "arguments": { "married": false },
  "assertions": { "unmarried": true },
  "presumption": "soft"
}
```

- A value is decoded at the node's declared result type, with the same decoder as an input of that type.
- `null` is refused: an assertion is a fact, and "not known" is not one ("`unmarried` is null: an assertion carries a value; to withdraw it, leave it out").
- A name that is `@nonassertable`, is the root, or is parameterised (§3) is refused before evaluation, naming the node and the reason (§5.3).
- A name that matches no node is refused with the nearest name.
- `assertions` is independent of `presumption`: hard mode leaves assertions alone.

`l4 batch` rows: a JSON or YAML row may carry an `assertions` object under that key; a CSV column `assert:<name>` asserts `<name>`.
**Assumed:** the row key `assertions` is reserved, so an input literally named `assertions` cannot be supplied by batch; the schema check names the collision.
MCP tools take `assertions` as an optional object argument.

### 4.2 Answer

Beside `presumed`, every answer that carries a result carries `asserted`: the names of the nodes whose asserted value the evaluation forced, each once, in forcing order.

```json
{
  "tag": "SimpleResponse",
  "contents": {
    "result": { "value": true },
    "presumed": [],
    "asserted": ["unmarried"]
  }
}
```

- An assertion the evaluation never read is not listed (T6's rule, applied to assertions).
- A refusal the rule reached (`EvaluatorRefused`) carries `asserted` as it carries `presumed` today (`Api.hs:332–337`).
- Any other error carries neither.
- The trace records an asserted node as its own event, as it records a presumed one (W8).
- Batch envelopes carry `asserted` beside `presumed` in every case (`Batch.hs`).

### 4.3 Schema

The published schema of a function lists its assertable nodes, each with its type and whether it is nonassertable, under a new key beside the inputs (**assumed** name: `assertable`, an array of `{name, type}`; nonassertable nodes are omitted, and the root is never listed).
Today the schema publishes inputs with `required` and `default` (`JsonSchema.hs:156–158`); this adds a sibling key and changes nothing already published.

## 5. Evaluation

### 5.1 Precedence

Within one node: **asserted > derived > presumed.**
Supplied is the leaf case of asserted.
An asserted node is not derived at all: its definition is not evaluated, and nothing under it is forced on its account, exactly as a folded group with a value does not consult its children.

### 5.2 Reporting

A presumption is listed under `presumed`, and an assertion under `asserted`, when and only when it is forced.
The mechanism today for presumptions is `registerPresumable` at the fill sites (`Machine.hs:4917–4926`); an assertion registers the same way with origin _asserted_.

### 5.3 Refusals, before evaluation

Refused by name, naming every offender in one message as `missingFieldsMessage` does today (`Machine.hs:4903–4908`):

- an assertion on a `@nonassertable` node: "`is guilty` is a conclusion: it cannot be asserted, only worked out";
- an assertion on the root: the same words;
- an assertion on a parameterised definition (§3);
- an assertion whose name matches nothing;
- an assertion sent as `null`.

In the service these are 400s on every path; in `l4 batch` they are row errors with `status: error`.

### 5.4 Hard mode, and where it refuses

Hard withholds presumptions and nothing else.
**Where** it refuses is TU-wire-b's open item (TYPICALLY spec `:290`), measured in `../PRESUMPTION-SCENARIOS.md` §2.3: today `l4 batch` and the service's direct path refuse at decode, so a presumed input refuses every request that omits it, forced or not, while the service's wrapper path is already lazy (`UNKNOWNS-BACKEND-CONTRACT.md:128–130`).
This document takes the lazy behaviour as the contract: **under hard, an omitted presumed input is an absent-with-none value, and the refusal happens when it is forced, naming it**: "the answer would rest on `presumed adult`, which was left out and is not presumed under hard".
A request that never forces it succeeds.
Soft lists it; hard refuses it; same event, two outcomes.

### 5.5 Inside the rules

Presumption mode is a property of a request, and a construction inside the rules has no request (T4b).
Today a `WITH` that omits a defaulted field is refused in every mode on `unstable`, and filled in every mode on #551 (`../PRESUMPTION-SCENARIOS.md` §2.5).
This document does not change that; it notes that #551 lists such a fill under `presumed` as `WITH Record: field`, which is the right disclosure.

### 5.6 The ladder's own evaluator and the query planner

`ts-shared/l4-ladder-visualizer/src/lib/eval/eval.ts` and `jl4-query-plan` evaluate over the ladder tree (`UNKNOWN-EVALUATION-SPEC.md` §3.4, U10).
For them an assertion is a valuation entry on a group, which they already honour as an override; the only addition is provenance `asserted`, so the picture can draw an asserted group differently from a derived one (**assumed**: solid box with an `asserted` tag, by analogy with `typically`).

## 6. The annotation

```l4
@nonassertable
`is guilty` MEANS `did the act` AND `had the intent` AND NOT `has a defence`
```

- **Placement.** On a definition: a module- or section-level `MEANS`/`DECIDE`, or a `WHERE` local.
  On anything else (a `DECLARE`, a `GIVEN`, an `ASSUME`, a directive) it is a check error: "`@nonassertable` marks a named step; `x` is an input" (inputs are supplied, and the request decides that).
- **Lexing and parsing.** One more annotation token beside `@export`, `@desc`, `@nlg`, `@nonexhaustive` and the fixity annotations (`Lexer.hs:88–97`); exactprint round-trips it as `Parser.hs:194` does `@nonexhaustive`.
- **Checking.** Recorded on the definition's `Anno`, as `@nonexhaustive` is read through `Export.isNonexhaustiveDecide` (`TypeCheck.hs:1131–1168`); no other check.
- **The root** is nonassertable by construction in our evaluators; the annotation on it is permitted and redundant, not an error.
- **Projection.** The annotation travels with the program.
  To s(CASP) and Blawx it means the node is not `#abducible`; today only inputs are declared abducible (`BlawxAssumeSpec.hs:159–168`), and §8 says what default-open does there.
- **Spelling.** `@nonassertable` is Meng's word (2026-10-09); `@conclusion` was offered and not taken.

## 7. Proposed, not ruled: a presumption on a named step

Everything above is ruled or follows from the ruling.
This section is not: it amends T1 (TYPICALLY spec `:275`: "a `TYPICALLY` on a `MEANS` field becomes a check error", which #551 builds), and it is here because Meng's own ask includes "we might want to write an L4 program that says typically one of those three is true".
It gets no implementation until ruled.

```l4
`unmarried` MEANS single OR divorced OR widowed TYPICALLY TRUE
```

**Semantics if ruled.**
Derive when the definition decides; when the derivation is unknown (its inputs absent-with-none under hard, or three-valued unknown under `UNKNOWN-EVALUATION-SPEC` §4), take the presumed value under soft and refuse-at-force under hard; an assertion beats both.
Listed under `presumed` when forced, by the node's name.
Only a literal of the node's result type (`isTypicallyLiteral`, `TypeCheck.hs:2044`).
The ladder's `defaults` map gains group entries, and `types.ts:38` is amended.

**What works today instead** is route 2 of `../PRESUMPTION-SCENARIOS.md` §1: a `TYPICALLY` input read only in the `NOTHING` arm.
**What is wrong today** is G1 there: an author's `WHEN NOTHING THEN TRUE` is the same presumption, unreported.
If §7 is declined, the recommendation is a lint on an arm under `NOTHING` that returns a literal other than `NOTHING` (PRESUMPTION-SCENARIOS §5.3).

## 8. Exporters

Each exporter does three things: lowers assertable nodes, lowers `@nonassertable`, and says in its fidelity report what it did.
`../PRESUMPTION-SCENARIOS.md` §8 has the per-target reasoning; this is the obligation.

| target          | assertable node                                                                                                         | `@nonassertable`                                 | report                                                                                                                  |
| --------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Catala          | a `context` variable the caller may override, as `TYPICALLY` lowers today (`Catala/Lower.hs:1295`)                      | a plain `definition`                             | `CATALA-EXPORT-SPEC` fidelity notes                                                                                     |
| Blawx / s(CASP) | `#abducible` for every assertable node, beside the inputs (`BlawxAssumeSpec.hs:159–168` today)                          | not abducible                                    | the `.blawx` fidelity notes; `BLAWX-EXPORT-SPEC` §5.1's "dropped, disclosed" for `TYPICALLY` stays a ruling until built |
| OpenFisca       | native: an input set on a variable suppresses its formula                                                               | **cannot be expressed**; the limits page says so | OpenFisca has no fidelity report (TYPICALLY spec `:68`); `doc/exports/openfisca.md` carries the limit                   |
| docassemble     | a `question` and a `code` block for one variable                                                                        | `code` only                                      | `DA-TYPICALLY`'s sibling note (`Docassemble/Lower.hs:794–799`)                                                          |
| DMN / dmn-md    | an optional input `<name> asserted` and a first rule row taking it when present                                         | no such input                                    | the fidelity report lists every assertion input emitted                                                                 |
| BPMN            | through the decision it calls                                                                                           | as DMN                                           | as DMN                                                                                                                  |
| yscript         | unmeasured; T5b makes yscript refuse a module whose exported rule reads a defaulted input (#550); probe before deciding | unmeasured                                       | none exists; the limits page                                                                                            |
| jl4-mlir        | refuse a request carrying `assertions` with a clear error until the marshaller carries them                             | n/a until then                                   | `jl4-mlir/README.md`'s divergence list                                                                                  |

**Two rows must not be silent.** OpenFisca loses `@nonassertable` and has no report; DMN gains inputs the author did not write.
Both are written on the exporter's limits page in `doc/exports/` in the same change that lowers them.

## 9. The evaluators, seam by seam

- **jl4-core.** An assertion on a nullary definition becomes a rewrite of that definition's body to the asserted literal before evaluation, in the pass that fills section defaults today (`Discharge.hs`, `fillInDefault`, per `TYPICALLY-DEFAULTS-SPEC`), registered as presumable-with-origin-asserted so forcing reports it; `requestPresumed` gains a sibling `requestAsserted` (`EvaluateLazy.hs:884`).
  The presumption fill sites (`Machine.hs:4917–4926`) are unchanged.
  Refuse-at-force (§5.4) moves the `missing` refusal (`Machine.hs:4903–4908`) from decode to a thunk that refuses when forced, for hard mode only.
- **jl4-service.** `assertions` on every path; the direct path adds them through `addRootFills`'s mechanism (`Jl4.hs:1081`), the wrapper path through the decoder; `asserted` in `ResponseWithReason` beside `presumed` (`Api.hs:229`); the OpenAPI document and the README's envelope section.
- **`l4 batch`.** Row key and CSV column (§4.1); `asserted` in the envelope; `--validate-only` names the §5.3 refusals.
- **jl4-mlir.** Refuses `assertions` until the marshaller carries a second argument set; the README's divergence list gains the row.
- **Ladder.** Provenance `asserted` on a group with an override; palette entry; `l4 render --format plan` lists assertable nodes.
- **Docs.** `doc/reference/types/TYPICALLY.md` (whose "metadata only" is already stale after W2/W3), a new reference page for `@nonassertable`, the service README, the batch page, the six pages that quote a `presumed` envelope, and this tutorial's final home under `doc/tutorials/`.

## 10. Tests that prove it

- jl4-core: an asserted `WHERE` local is not derived (its definition's body would error if evaluated); `asserted` lists it only when forced; `@nonassertable` refused by name; the root refused; a parameterised definition refused; `null` refused; precedence over a `TYPICALLY` on an input the node reads.
- jl4-service: the same over HTTP on direct and wrapper paths; `presumption: hard` plus an assertion succeeds; schema carries `assertable`.
- `l4 batch`: JSON row and CSV column; a row asserting a nonassertable node is `status: error` and the others proceed under `-c`.
- Refuse-at-force: `../PRESUMPTION-SCENARIOS.md`'s `alice.l4` with `chain.json` under hard answers Bob's and Carol's rows and refuses Alice's, naming `presumed adult`.
- Exporters: one fixture per row of §8 with a fidelity note asserting what was emitted.
- Ladder: a folded group with an override renders provenance `asserted`.

## 11. Impact assessment, first cut (measured 2026-10-09 at `c6d081622`)

| surface                        | change                                                                                                                                                                                                                          | additive or breaking                                                                      | what proves it                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| L4 source corpus               | none required: ~4,996 `MEANS` definitions in `ok/`, `legal/`, `canon/` become addressable by default with no edit; `@nonassertable` is opt-in                                                                                   | additive                                                                                  | `jl4-test` unchanged                                                |
| `TYPICALLY` uses               | 11 files / 50 lines in `ok/`, 3 / 9 in `canon/`, 0 in `legal/` and `libraries/`; **0 uses of `TYPICALLY NOTHING` anywhere**, so retiring `TYPICALLY` on a `MAYBE` (§13) would upgrade nothing                                   | additive                                                                                  | the grep                                                            |
| `not-ok` goldens               | 9 files / 24 lines mention `TYPICALLY`; untouched unless §7 lands and amends T1's error                                                                                                                                         | additive unless §7                                                                        | `jl4-test`                                                          |
| `presumed` consumers           | `DataPlane.hs`, `Types.hs`, `Backend/Api.hs`, `Backend/Jl4.hs`, `Batch.hs`, `IntegrationSpec.hs`, `QueryPlanSpec.hs`, `tests-cli/Main.hs`, `ladder-core/types.ts`, `ladder-svg/palette.ts`, and 6 doc pages quoting an envelope | additive: a new sibling key; old clients ignore it                                        | the quoted envelopes in those 6 pages are re-measured               |
| request decoding               | new optional `assertions` key; refusals of §5.3                                                                                                                                                                                 | additive                                                                                  | service and batch tests                                             |
| hard mode                      | refuse-at-force (§5.4)                                                                                                                                                                                                          | **breaking** for a client that relied on a decode-time refusal of an unforced presumption | `tests-cli/Main.hs:1741–1754`'s hard-mode expectations, re-measured |
| OpenAPI / schema               | `assertable` key                                                                                                                                                                                                                | additive                                                                                  | `jl4-service` schema tests                                          |
| exporters                      | §8 lowerings and report rows; OpenFisca and DMN limits pages                                                                                                                                                                    | additive; DMN emits inputs the author did not write, disclosed                            | fixtures per row                                                    |
| jl4-mlir                       | one refusal and a README row                                                                                                                                                                                                    | additive                                                                                  | its test                                                            |
| the `TYPICALLY` reference page | already drifted ("metadata only"); rewritten to the four sources                                                                                                                                                                | docs                                                                                      | `doc/test-docs.sh`                                                  |

Not measured yet: the goldens that capture a batch or service envelope byte for byte (`grep -rl '"presumed"' jl4/examples jl4-service/test`), which decide how many expected outputs gain an `"asserted": []`.
**Assumed:** `asserted` is emitted always, as `presumed` is, so those goldens change once, mechanically.

## 12. What this document supersedes, once recorded

Per repo `CLAUDE.md` §4, nothing below is decided until the owning document says so; the revision that follows this draft makes these edits.

- `TYPICALLY-ONE-BEHAVIOUR-SPEC.md`: T6's "every service response" gains the sentence that `asserted` is listed by the same rule; TU-wire-b's "lazy binding there is its own work item" is pointed at §5.4 here; T1 is unchanged unless §7 is ruled.
- `UNKNOWN-EVALUATION-SPEC.md`: §5 gains the §7 ruling of PRESUMPTION-SCENARIOS as a ruling with its date and Meng's words; U8's "a presumption is a question not yet asked" is joined by "an assertion is an answer given"; U9's three absences are unchanged; U10 notes provenance `asserted`.
- `UNKNOWNS-BACKEND-CONTRACT.md`: its §6 table gains an "after this design" column from §8 here; it rules nothing and is not rewritten.
- `RUNTIME-INPUT-STATE-SPEC.md`: marked superseded by this document and `UNKNOWN-EVALUATION-SPEC.md` §5; its four cells are DESIGN §22's and are kept as the reference for the interview layer.
- `ladder-diagrams-2026/DESIGN.md`: §19 gains "an override from a request is an assertion (CONTRACT §2)"; `types.ts:38` is cited as true until §7.
- `SURFACE-SUGAR-CLUSTER-2026-09.md` D7.3 and `IMPLICIT-PROPS-DESIGN.md` R8: unchanged by this document; §13 names the amendment that would touch them.

## 13. Non-goals and open rulings

Non-goals of this version:

- asserting an application of a parameterised definition (§3); the ladder's positional `atomId` is the obvious future address;
- a wire spelling for a nested `MAYBE` (`JUST NOTHING` cannot be sent today; PRESUMPTION-SCENARIOS §2.6 measured it); the interview-state distinction stays as T3's absent/`null`;
- an abductive query mode: that is another engine's work, reached by export (§8);
- a contradiction detector between an assertion and the children it subsumes (DESIGN §19 defers it too).

Open for Meng, each a ruling and not a slice:

- **§7**: a presumption on a named step, amending T1.
- **Retiring `TYPICALLY` on a `MAYBE`**, amending D7.3 and R8 rule 3 (PRESUMPTION-SCENARIOS §5.2); zero corpus uses, one refused docassemble export.
- **Reserving `assertions` as a batch row key** (§4.1), or choosing another spelling.
