# Presumption and assertion: the contract for evaluators and exporters

**Status:** proposed, 2026-10-09, revised the same day after two rounds of Opus adversarial review (§14 says what each changed); nothing in this document is built.
It is the normative statement of a design whose measurements are in `../PRESUMPTION-SCENARIOS.md` and whose one ruling so far is §7 there (Meng, 2026-10-09, in chat): named derived nodes may be asserted by a request, default-open, opted out by `@nonassertable`, with an `asserted` list in the answer.
That ruling is recorded in `UNKNOWN-EVALUATION-SPEC.md` §5 (2026-10-09, the revision that carries this document), so by repo `CLAUDE.md` §4 it is decided; what it decides, and what it leaves assumed or proposed, is stated there.
Every other choice here is **assumed, not ruled**, is marked so, and is made so that it can be reverted alone.
Where a sentence describes what the tree does today it says _today_ and cites a line at `c6d081622`.

**Who this is for.** Anyone implementing an evaluator that answers requests (jl4-core, jl4-service, `l4 batch`, jl4-mlir, the ladder) or an exporter that projects L4 into another system.
The ladder diagram is the reference **model** for what an assertion and a presumption are: §2 maps every concept here onto the ladder's own, and says which parts of the ladder are semantics and which are only drawing.
The ladder is not the authority on **values**: U10b (`UNKNOWN-EVALUATION-SPEC.md:1243`) holds the ladder's `nodeValue` to the Haskell evaluator and lists where they diverge, and this document keeps that.

**Owning documents this touches.** `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` (T1, T3, T4, T6, TU-wire-b), `IMPLICIT-PROPS-DESIGN.md` §11.5 (R8), `SURFACE-SUGAR-CLUSTER-2026-09.md` (D7.3), `UNKNOWN-EVALUATION-SPEC.md` (§5, U8, U9, U10), `UNKNOWNS-BACKEND-CONTRACT.md` (a description of the tree), `RUNTIME-INPUT-STATE-SPEC.md`, `ladder-diagrams-2026/DESIGN.md` (§19, §22, §26, §27), `WHERE-INLINING-SPEC.md` (§7, §10).
§12 lists which of their sentences this document supersedes.

---

## 1. Vocabulary

- **Input.** A fact the exported rule is `GIVEN`, a section `GIVEN` it reads, or a field of a record among those.
- **Named step**, or **node.** A definition with a name that the exported rule relies on: a `WHERE` local, or a definition at section or module level.
  In the ladder a node is a box (a leaf) or a group (a fold); a nullary `WHERE` local is drawn as a leaf (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs:431–437`, `:507–522`, `:665–687`), and its definition is reached by the expand gesture (`WHERE-INLINING-SPEC.md` §7).
- **The root.** The exported rule's own result.
- **Source** of a value, one of four:
  - **supplied**: the request gave the input a value;
  - **asserted**: the request gave a named step a value (§4); supplying an input is the leaf case of asserting, and this document uses _asserted_ for named steps only;
  - **derived**: worked out from the node's definition;
  - **presumed**: taken from a `TYPICALLY` because nothing supplied or asserted it (R8, T1).
- **Forced.** A value is forced when the evaluation reads it.
  Reporting is by forcing (T6, today: `notePresumedForce`, `Machine.hs:472–483`, called from `evalRef`, `:6010–6014`): a presumption or assertion the evaluation never read is not listed.
- **Soft / hard.** The presumption switch (T4, TU-presume; today: `--presumption`, `"presumption"`).
  Hard withholds presumptions; it never withholds supplied values or assertions.
- **Absent / `null`.** T3's two absences on the wire, today: a key left out is a gap; `null` is "not known", a value on a `MAYBE` and a refusal elsewhere.
  This document does not change T3.

## 2. The ladder as reference model

The ladder core already models every concept above, positionally.
Implementers copy the first table and not the second.

**Semantics (copy these).**

| concept                   | ladder                                                                                                                           | where                                                                                 |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| a node                    | `NodeId`, a box or a group                                                                                                       | `types.ts:236–241`                                                                    |
| supplied / asserted       | an entry in `ViewSpec.valuation`; on a group it is an **override**: the group takes the value and its children are not consulted | DESIGN §19 (`:734`); `types.ts:236–241`; `nodeValue`, `layout.ts:239–244`             |
| presumed                  | an entry in `ViewSpec.defaults`, laid _under_ `valuation`; `valuation` wins where both have an entry                             | DESIGN §26.3 (`:1620`); `types.ts:247–262`; `effectiveValuation`, `layout.ts:321–326` |
| derived                   | a group with no entry of its own derives from its operative children, three-valued                                               | DESIGN §6, §19                                                                        |
| soft / hard, as a display | `ViewSpec.respectDefaults`: true lays the defaults under, false withdraws them                                                   | DESIGN §26.3; `layout.ts:308–322`, `:428–433`                                         |
| provenance                | `ViewSpec.provenance` marks a **declaration site** ("this leaf has a TYPICALLY clause"), not the source of the current value     | DESIGN §26.3 (`:1620–1625`); `types.ts:266–267`                                       |
| the root                  | the diagram's output, which carries no entry of its own (this document's reading; DESIGN §19 does not say it)                    | —                                                                                     |

Two places where the ladder and the evaluator differ, stated so that nobody copies the wrong one:

- **What an answer rests on** is defined by **forcing in the evaluator** (§5.2), not by the ladder's `energize`, which still energizes an overridden group's children for their own entries and every branch of an OR (`layout.ts:469–470`, `:496`) and so over-counts.
- **Hard mode in decide mode is not `respectDefaults: false`.** T4 makes a withheld default "stuck in decide mode, unknown in explore mode" (TYPICALLY spec `:329`); the ladder's withdrawal is the explore-mode reading, a three-valued unknown that still lets an `AND` read FALSE when another child is FALSE (`layout.ts:239–241`).
  In decide mode the evaluator refuses when the withheld value is forced (§5.4), under left-sequential evaluation (U1): `q AND p` with `q` withheld refuses, whatever `p` is, where the ladder reads unknown or FALSE.

**Drawing (do not copy these into an evaluator).**

| rule                                                                                | why it is UI only                                                         | where                               |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ----------------------------------- |
| an override on a call panel holds only while the panel is folded (`dropOpenPanels`) | it keeps an open drawing honest; an evaluator has no open or folded state | DESIGN §27.1; `layout.ts:1033–1050` |
| one click sets the value on every box with the same `atomId` (`spreadValue`)        | a gesture; the wire names a node once                                     | DESIGN §27.1; `viz-adapter.ts`      |
| click cycles U → T → F → U                                                          | a gesture                                                                 | DESIGN §19                          |
| `types.ts:38`: "a group's value derives; it is never presumed"                      | true today; §7, if ruled, would give `defaults` group entries             | `types.ts:38`                       |

**What the ladder gains (assumed).** A `ViewSpec.asserted: ReadonlySet<NodeId>` beside `provenance`, so an asserted node, leaf or group, can be drawn as told rather than worked out; it is not a provenance, because provenance marks declaration sites (`types.ts:266–267`).

One consequence of taking the ladder as the model: **an assertion on a group subsumes conflicting children** (DESIGN §19's "override, without a witness").
The contradiction-detecting alternative is deferred there and deferred here (§13).

## 3. Which named steps may be asserted, in this version

**Assumed, not ruled.** A request may assert a definition that

- is declared **with no `GIVEN` of its own**: a `WHERE` local at any depth, in the exported rule or in a helper it relies on, or a section- or module-level definition without parameters;
- is defined in the **main module**, not in an `IMPORT` (imported modules are evaluated once at deploy into a shared environment, `jl4-service/src/Compiler.hs:68`, `:332`, `Backend/Jl4.hs:1070`);
- and has a **name that is unique** among the nullary definitions of the main module (§3.1).

A definition with its own `GIVEN` is applied, possibly several times with different arguments; the ladder draws each application as a call panel keyed by position (DESIGN §27; `WHERE-INLINING-SPEC.md` §10.1), and asserting one application needs an argument-indexed address this version does not define (§13).
Such an assertion is refused: "`is creditworthy` takes inputs of its own; an application of it cannot be asserted by name".

**What "no `GIVEN` of its own" does not exclude, and what it means.**
Discharge gives a definition that reads section inputs those inputs as trailing parameters (`Discharge.hs:272–279`), and a `WITH` may apply it with other values in the same evaluation; a `WHERE` local is allocated afresh on every activation of its rule (`Machine.hs:1582–1585`), so a recursive rule has many.
In both cases **an assertion pins every application and every activation** to the asserted value, because the assertion is applied where the definition is allocated (§9), and the document says so rather than pretending the definition is evaluated once.

### 3.1 Addressing

A name in `assertions` is the definition's name as written, backticks removed, and it is matched against every nullary definition of the main module, wherever that definition sits: a `WHERE` local is not in scope at the exported rule's body (a `Where`'s names are visible only in its own body, `Machine.hs:1582–1585`), so scope is not the addressing rule, the name is.
Two nullary definitions with the same name anywhere in the main module (two arms of one rule, or two helpers each with a local `bonus`, the case `Relational/Lower.hs:1309` names) make the name ambiguous, and an assertion of it is refused naming both sites.
A name that matches nothing is refused with the nearest declared name, as `unrecognisedMessage` does for inputs today (`Presumption.hs`).

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

- A value is decoded exactly as an input of the node's result type is decoded today (`fillDecision`, `Presumption.hs:65–75`): on a `MAYBE`-typed node `null` asserts `NOTHING`, and `JUST NOTHING` cannot be written (PRESUMPTION-SCENARIOS §2.6); on any other type `null` is refused as "not known".
  A node whose type the author did not write is assertable at the type the checker inferred; a node whose type has no JSON decoding is not assertable, and the schema (§4.3) leaves it out.
- A name that is `@nonassertable`, is the root, is parameterised, is imported, or is ambiguous (§3) is refused before evaluation, naming the node and the reason (§5.3).
- A name that matches no node is refused with the nearest name.
- `assertions` is independent of `presumption`: hard mode leaves assertions alone.

**Spellings per surface, and the collision each reserves.** L4 accepts any text as a name, `@assertions` and `@assert:x` included (the review's probe checked and ran both), so no spelling avoids a collision with a possible input; each surface reserves its spelling and refuses the collision loudly.

| surface                                                                                | spelling                                                                                                    | reserved against                   |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| service `/evaluation`                                                                  | `assertions` beside `arguments`                                                                             | nothing: the request is structured |
| service `/batch`                                                                       | `@assertions` on a case, beside its flat inputs, as `@id` is (`Types.hs:497–498` reserves `@id` only today) | an input named `@assertions`       |
| MCP tools (flat top-level arguments, no `presumption`, `McpServer.hs:301`, `:506–510`) | `@assertions`                                                                                               | an input named `@assertions`       |
| `l4 batch` JSON or YAML rows                                                           | `@assertions`                                                                                               | the same                           |
| `l4 batch` CSV                                                                         | a column `@assert:<name>`                                                                                   | an input named `@assert:<name>`    |

A module whose exported rule has an input named like a reserved spelling cannot be served on that surface; `--validate-only`, the deploy-time schema check and the MCP tool listing refuse it, naming the input.

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
- The `/batch` endpoint puts `@asserted` beside `@presumed` on every case, errored ones included, where it is empty (`Types.hs:550–560`; `DataPlane.hs:365–368`).
- `l4 batch` envelopes carry `asserted` beside `presumed` in every case (`Batch.hs`).
- The evaluation result carries the asserted events as a list beside the presumed ones: today `EvalDirectiveResult` has `presumed :: [Presumed]` as a sibling of `trace` (`EvaluateLazy.hs:423`, `:438`), filled at every trace level and rendered by no printer (`:439–443`; TYPICALLY spec `:140`); `asserted` is a second such list.
  Neither is an `EvalTrace` event, and rendering either is a separate item (§13).

### 4.3 Schema

The published schema of a function lists its assertable nodes under a new key beside the inputs (**assumed** name: `assertable`, an array of `{name, type}`); nonassertable nodes, the root, parameterised and imported definitions, ambiguous names, and nodes without a JSON-decodable type are left out.
There is no single schema builder today: the service and MCP build `Parameters` in `Compiler.hs:508–510` (`parametersFromExport`), the CLI builds a JSON Schema through `L4.JsonSchema.generateJsonSchema` (`jl4/app/Schema.hs:23`, `:85`), and `L4.FunctionSchema`'s builder is used only by the query plan (`DecisionQueryPlan.hs:264`).
The key is added at all three, from one shared helper that lists a module's assertable nodes (**assumed**).
Today the CLI schema publishes inputs with `required` and `default` (`JsonSchema.hs:156–158`); this changes nothing already published.

## 5. Evaluation

### 5.1 Precedence

Within one node: **asserted > derived > presumed.**
Supplied is the leaf case of asserted.
An asserted node is not derived at all: its definition's body is not evaluated, and nothing under it is forced on its account, exactly as a group with a value does not consult its children.

### 5.2 Reporting

A presumption is listed under `presumed`, and an assertion under `asserted`, when and only when it is forced.
Today this is three sites: the decoder's fill sites register a filled input when they allocate it (`Machine.hs:4917–4926`); `evalDecide`'s nullary clause registers a definition listed in `presumableDefs` when it allocates it (`Machine.hs:6342–6351`), which a `WHERE` local reaches through `evalRecLocalDecls` and `evalLocalDecl` (`:6122–6128`, `:6319`); and `evalRef` reports a registered value on its first force (`notePresumedForce`, `:472–483`, `:6010–6014`).
An assertion registers at the second site, with origin _asserted_, and is reported at the third (§9).

### 5.3 Refusals, before evaluation

Refused by name, naming every offender in one message as `missingFieldsMessage` does today (`Machine.hs:4899–4908`):

- an assertion on a `@nonassertable` node: "`offence made out` is a conclusion: it cannot be asserted, only worked out";
- an assertion on the root: the same words;
- an assertion on a parameterised, imported or ambiguous definition (§3);
- an assertion whose name matches nothing;
- an assertion sent as `null` on a node whose type is not a `MAYBE`.

In the service these are **422**, as a missing, `null` or unknown input is today (`DataPlane.hs:764–776`; `UNKNOWNS-BACKEND-CONTRACT.md:108`, `:121`); in `l4 batch` they are row errors with `status: error`; `--validate-only` reports them without evaluating.

### 5.4 Lazy binding of what is left out, and where hard refuses

Door number two depends on this: an asserted node's inputs are never reached, so they must be allowed to be left out, and today they are refused at decode (the review's probe: `{"married": true}` alone is refused naming `single`, `divorced` and `widowed`).

**Assumed; open for Meng (§13).** An input the request leaves out, that nothing fills, is bound to an **absent-with-none** value in both modes: a thunk that refuses when forced, naming the input.
Under soft, "nothing fills" means no default and not a `MAYBE`; under hard it also means a default withheld (T4: "an absent input with a default is treated as absent with none") and a `MAYBE` not taken as `NOTHING` (T1b).
So:

- a request that never forces the gap succeeds, and under soft lists what it did force in `presumed`;
- a request that forces it is refused when it does, with a new message naming the input and, under hard, why: "the answer would rest on `presumed adult`, which was left out and is not presumed under hard" (today's text is the decoder's "Missing required field … in JSON object", and it changes).

**How much of this is TU-wire-b's item.** TU-wire-b says "eager refusal stays only on the direct path, and lazy binding there is its own work item" (TYPICALLY spec `:290`; `UNKNOWNS-BACKEND-CONTRACT.md:102`): the direct path.
`l4 batch` is eager for every input, and the wrapper path is lazy only for `BOOLEAN` (`UNKNOWNS-BACKEND-CONTRACT.md:107`, `:109–111`); extending lazy binding to both is **new scope**, stated here and listed open.

What this keeps and what it changes:

- It keeps `--validate-only`'s job: that mode still names every left-out input at once, eagerly (`tests-cli/Main.hs:1576`); the eager decode refusal becomes validate-only's behaviour rather than every run's.
- It keeps the envelope shapes: a batch row refused at force is `status: error`; the service answers 422 with the body it uses today.
- It changes `l4 batch` and the service's direct path (`Backend/Jl4.hs:543`, `:678`), and makes the wrapper path lazy for every type.
- It changes four tests that pin eager, one-run naming: `tests-cli/Main.hs:1730` ("hard refuses a left-out default the rule would not read") inverts, and `:1735–1739`, `IntegrationSpec.hs:750–755` and `:840–851` ("names every defaulted input left out") become "names the first one forced", since a run names the first gap it forces, as an error does, and only `--validate-only` names them all.

### 5.5 Inside the rules

Presumption mode is a property of a request, and a construction inside the rules has no request (T4b).
Today a `WITH` that omits a defaulted field is refused in every mode on `unstable`, and filled in every mode on #551 (`../PRESUMPTION-SCENARIOS.md` §2.5).
This document does not change that; it notes that #551 lists such a fill under `presumed` as `WITH Record: field` **under hard only**, which is the right disclosure.

### 5.6 The ladder's evaluators and the query planner

Neither evaluator over the ladder tree honours a value on a group today: `eval.ts` reads its assignment only at a `UBoolVar` (`l4-ladder-visualizer/src/lib/eval/eval.ts:99`) and evaluates every `And`/`Or` child (`:165`, `:190`), and the query planner's `BoolExpr` has only variable atoms (`UNKNOWN-EVALUATION-SPEC.md:205`).
U10b replaces `eval.ts` with a call to the Haskell evaluator, so this document asks nothing of it.
An assertion reaches the ladder as a `valuation` entry on the node, which `ladder-core`'s `nodeValue` already treats as an override (`layout.ts:239–244`), plus the `asserted` set of §2 for drawing.
For the planner an asserted node is an atom with a fixed value; that is future work and not specified here.

## 6. The annotation

```l4
@nonassertable
`offence made out` MEANS `did the act` AND `had the intent` AND NOT `has a defence`
```

- **Placement.** On a definition: a module- or section-level `MEANS`/`DECIDE`, or a `WHERE` local (which parses today, per the review's probe).
  On anything else (a `DECLARE`, a `GIVEN`, an `ASSUME`, a directive) it is a check error: "`@nonassertable` marks a named step; `x` is an input".
- **Lexing and parsing.** Its **own** token and its own field on the definition's annotation.
  It must not be modelled on `@nonexhaustive`, which the parser folds into the `@desc` text and `Export.isNonexhaustiveDecide` recognises by its leading word (`Parser.hs:189–198`; `Export.hs:165–166`); copying that would let `@desc nonassertable …` mark a node silently (the review measured the same with `@desc nonexhaustive`, and `@desc nonassertable` on a `WHERE` local checks today).
  Exactprint round-trips it.
- **Checking.** The placement check above, and the schema omission (§4.3); the refusal (§5.3) is the request decoder's.
- **The root** is nonassertable by construction in our evaluators; the annotation on it is permitted and redundant, not an error.
- **Projection.** The annotation travels with the program.
  To s(CASP) and Blawx it means the node is not `#abducible`; today only inputs are declared abducible (`BlawxAssumeSpec.hs:159–168`), and §8 says what default-open does there.
- **Spelling.** `@nonassertable` is Meng's word (2026-10-09); `@conclusion` was offered and not taken.

## 7. Proposed, not ruled: a presumption on a named step

Everything above is ruled or follows from the ruling.
This section is not, and gets no implementation until ruled.
It is here because Meng's own ask includes "we might want to write an L4 program that says typically one of those three is true".

```l4
`unmarried` MEANS single OR divorced OR widowed TYPICALLY TRUE
```

**No existing ruling covers it.** T1's "a `TYPICALLY` on a `MEANS` field becomes a check error" (TYPICALLY spec `:275`) is about a computed field of a record, `f IS A T MEANS expr` inside a `DECLARE`, which desugars to a synthetic definition (`Desugar.hs:265–267`), and #551's error names exactly that case.
A `TYPICALLY` on a definition is a parse error today (`../PRESUMPTION-SCENARIOS.md`, `v3-typically-means.l4`) and is ruled neither way.

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
`../PRESUMPTION-SCENARIOS.md` §8 has the per-target reasoning; this is the obligation, corrected against each exporter's source.

| target          | assertable node                                                                                                                                                                                                                                                                                                                                                                                                                                              | `@nonassertable`                                 | report                                                                                                                  |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Catala          | a `context` marking is on a **scope variable** (`Catala/Lower.hs:1293–1296`), so an assertable node becomes a `context` variable of the exported rule's scope, defined from the node's body; a `WHERE` local lowers to `let … in` today (`:1745–1750`) and is lifted into the scope instead; a node inside a non-exported helper, which lowers to a toplevel with no scope (`:18–23`, `:1359`), is not assertable in Catala                                  | lowered as today                                 | fidelity notes name each lift and each node left unassertable                                                           |
| Blawx / s(CASP) | `WHERE` locals are already lifted into predicates (`Relational/Lower.hs:1302–1314`; `Blawx/Lower.hs:1997–2016`); `#abducible` for each assertable node beside the inputs                                                                                                                                                                                                                                                                                     | not abducible                                    | the `.blawx` fidelity notes; `BLAWX-EXPORT-SPEC` §5.1's "dropped, disclosed" for `TYPICALLY` stays a ruling until built |
| OpenFisca       | **refuses `WHERE` outright** today (`OpenFisca/Lower.hs:384`, `:397`), so a `WHERE`-local node cannot be lowered at all; a module-level node is native: an input set on a variable suppresses its formula                                                                                                                                                                                                                                                    | **cannot be expressed**; the limits page says so | OpenFisca has no fidelity report (TYPICALLY spec `:68`); `doc/exports/openfisca.md` carries both limits                 |
| docassemble     | each zero-`GIVEN` `WHERE` local already gets a `code` block (`Docassemble/Lower.hs:16–17`); an assertable node adds a `question` for the same variable                                                                                                                                                                                                                                                                                                       | `code` only                                      | `DA-TYPICALLY`'s sibling note (`:794–799`)                                                                              |
| DMN / dmn-md    | DMN **inlines** `WHERE` locals (`Dmn/Lower.hs:698`; `Relational/Lower.hs:1306`), so an assertable local has no table of its own; it is lifted into its own decision (**assumed**), with an optional input `<name> asserted` and a first rule row taking it when present; that row needs hit policy **FIRST**, and of the 39 tables in the tracked `.dmn` fixtures 29 are UNIQUE and 10 FIRST, so the exporter switches a table's policy when it adds the row | no lift, no input                                | the fidelity report lists every lift, assertion input and policy switch                                                 |
| BPMN            | through the decision it calls                                                                                                                                                                                                                                                                                                                                                                                                                                | as DMN                                           | as DMN                                                                                                                  |
| yscript         | unmeasured; T5b makes yscript refuse a module whose exported rule reads a defaulted input (#550); probe before deciding                                                                                                                                                                                                                                                                                                                                      | unmeasured                                       | none exists; the limits page                                                                                            |
| jl4-mlir        | refuse a request carrying `assertions` with a clear error until the marshaller carries them                                                                                                                                                                                                                                                                                                                                                                  | n/a until then                                   | `jl4-mlir/README.md`'s divergence list                                                                                  |

**Three rows must not be silent.** OpenFisca loses `@nonassertable` and `WHERE`-local nodes and has no report; DMN lifts locals, gains inputs the author did not write and may change a hit policy; Catala lifts locals into the scope and leaves helper nodes unassertable.
Each is written on the exporter's limits page in `doc/exports/` in the same change that lowers it.

## 9. The evaluators, seam by seam

- **jl4-core: the seam is `EvalConfig`, not a module rewrite.** The wrapper path and `l4 batch` evaluate generated **source text** through Shake (`Backend/Jl4.hs:1199–1203`; `Batch.hs:433–439`; `Rules.hs:1117` calls `execEvalModuleWithEnvAndImports` with `noRootFills`), so no pass over the compiled module reaches them; what reaches every path is the `EvalConfig` each builds (`Batch.hs:226–233`, which already carries `presumeDefaults`).
  `EvalConfig` gains `assertions`: a map from node name to a value decoded at the node's result type at request time (the type from the checked module's entity info).
  `evalDecide`'s nullary clause (`Machine.hs:6342–6351`), which every module-level definition and every `WHERE` local reaches, consults it by the definition's name: on a hit it binds the asserted value instead of the body and registers it as presumable with origin _asserted_, so `evalRef` reports it on first force (`:472–483`, `:6010–6014`).
  Nothing is rewritten, root fills are unchanged, and the one check that needs the module is the ambiguity count (§3.1), done once per module at deploy or validate time.
  `requestPresumed` gains a sibling `requestAsserted` (`EvaluateLazy.hs:890`).
  Lazy binding (§5.4) replaces the decode-time `missing` refusal (`Machine.hs:4899–4908`) with an absent-with-none thunk for every run that is not `--validate-only`.
- **jl4-service.** `assertions` parsed on every path and put on the `EvalConfig` (direct path beside `addRootFills`, `Jl4.hs:1043–1044`; wrapper path beside `presumption` at `:1203`); `asserted` in `ResponseWithReason` beside `presumed` (`Api.hs:229`); `@asserted` on batch cases; `OpenApiDoc.hs:428`, `:448` (which requires `@presumed`) and `Schema.hs:406` (which lists it) carry `@asserted` the same way; `parametersFromExport` carries `assertable`; the README's envelope section.
- **`l4 batch`.** `@assertions` row key and `@assert:` CSV column (§4.1) onto the `EvalConfig`; `asserted` in the envelope; `--validate-only` names the §5.3 refusals and stays eager for left-out inputs.
- **jl4-mlir.** Refuses `assertions` until the marshaller carries a second argument set; the README's divergence list gains the row.
- **Ladder.** `asserted` set in `ViewSpec` (§2); palette entry; `l4 render --format plan` lists assertable nodes.
- **Docs.** `doc/reference/types/TYPICALLY.md` is current after W2/W3, bar one drift: it says a `null` is always refused, where a `null` on a `MAYBE` fact is `NOTHING` (PRESUMPTION-SCENARIOS §2.6), fixed in the revision step; a new reference page for `@nonassertable`; the service README; the batch page; the pages that quote a `presumed` envelope; and the tutorial's final home under `doc/tutorials/`.

## 10. Tests that prove it

- jl4-core: an asserted `WHERE` local is not derived (its definition's body would error if evaluated); `asserted` lists it only when forced; `@nonassertable` refused by name; the root refused; a parameterised, an imported and an ambiguous definition refused; `null` on a non-`MAYBE` node refused and on a `MAYBE` node asserts `NOTHING`; precedence over a `TYPICALLY` on an input the node reads; a recursive rule's local pinned on every activation; a helper's local asserted by name.
- jl4-service: the same over HTTP on direct and wrapper paths; `presumption: hard` plus an assertion succeeds; `/batch` cases carry `@asserted`; MCP `@assertions`; schema carries `assertable`; a 422 for each §5.3 refusal; a module with an input named `@assertions` refused at deploy for the surfaces that reserve it.
- `l4 batch`: `@assertions` row and `@assert:` column; a row asserting a nonassertable node is `status: error` and the others proceed under `-c`; `--validate-only` still names every left-out input.
- Lazy binding, on `../PRESUMPTION-SCENARIOS.md`'s `alice.l4` with `chain.json`, `-e "adult presumed"` (the file's default export is `adult derived`, `Export.hs:180`), under hard: Bob's and Carol's rows answer; Alice with `birthdate` left out is refused naming `person.birthdate` (the `CONSIDER` forces the withheld `MAYBE`); Alice with `birthdate: null` is refused naming `presumed adult`; Alice with a known birthdate answers `true`.
  And the four tests of §5.4 rewritten.
- Exporters: one fixture per row of §8 with a fidelity note asserting what was emitted, and the DMN lift and policy switch.
- Ladder: a node with an entry in `asserted` renders as told.

## 11. Impact assessment, first cut (measured 2026-10-09 at `c6d081622`; corrected after two reviews)

| surface                             | change                                                                                                                                                                                                                                                                                                                                                                     | additive or breaking                                                                                                                                                                  | what proves it              |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| L4 source corpus                    | none required: of ~5,000 `MEANS` definitions in `ok/`, `legal/`, `canon/`, roughly 2,900 are unparameterised and become addressable with no edit, roughly 1,600 are parameterised and out of scope (§3), and about 490 are indented locals (an `awk` heuristic, not a parse); `@nonassertable` is opt-in                                                                   | additive                                                                                                                                                                              | `jl4-test` unchanged        |
| `TYPICALLY` uses                    | 11 files / 50 lines in `ok/`, 3 / 9 in `canon/`, 0 in `legal/` and `libraries/`; `TYPICALLY NOTHING` appears in **no `.l4` file** and twice in `jl4-service/test/TestData.hs:855`, `:878`, so retiring it (§13) upgrades two test fixtures                                                                                                                                 | additive                                                                                                                                                                              | the grep                    |
| `not-ok` sources and goldens        | 9 `.l4` sources / 24 lines and 12 golden files / 34 lines mention `TYPICALLY`; untouched unless §7 is ruled and adds a new error                                                                                                                                                                                                                                           | additive unless §7                                                                                                                                                                    | `jl4-test`                  |
| `presumed` producers and publishers | `DataPlane.hs`, `Types.hs`, `Backend/Api.hs`, `Backend/Jl4.hs`, `OpenApiDoc.hs:428`, `:448` (which requires `@presumed`), `Schema.hs:406` (which lists it), `Batch.hs`, `IntegrationSpec.hs`, `tests-cli/Main.hs`; no corpus golden captures a `presumed` envelope (`grep -rl '"presumed"' jl4/examples` is empty), and the pages that quote one in `doc/` are re-measured | additive: a new sibling key; old clients ignore it                                                                                                                                    | the quoted envelopes re-run |
| request decoding                    | new optional `assertions` key, with one reserved spelling per surface (§4.1); refusals of §5.3                                                                                                                                                                                                                                                                             | additive, except that a module with an input named like a reserved spelling is refused on that surface                                                                                | service and batch tests     |
| lazy binding (§5.4)                 | decode-time refusal of a left-out input becomes a refusal at force, in both modes, on batch and both service paths                                                                                                                                                                                                                                                         | **breaking** for a client that relied on an eager refusal of an unforced input, and for four tests (`tests-cli/Main.hs:1730`, `:1735–1739`; `IntegrationSpec.hs:750–755`, `:840–851`) | the §10 rows                |
| OpenAPI / schema                    | `assertable` key at three builders; `@asserted` required beside `@presumed` in `OpenApiDoc.hs`                                                                                                                                                                                                                                                                             | additive                                                                                                                                                                              | `jl4-service` schema tests  |
| exporters                           | §8 lowerings and report rows; OpenFisca, DMN and Catala limits pages                                                                                                                                                                                                                                                                                                       | additive; DMN lifts locals, emits inputs the author did not write and may switch a hit policy, disclosed                                                                              | fixtures per row            |
| jl4-mlir                            | one refusal and a README row                                                                                                                                                                                                                                                                                                                                               | additive                                                                                                                                                                              | its test                    |
| the `TYPICALLY` reference page      | one drift (`null` on a `MAYBE`), fixed in the revision step; the four sources added when built                                                                                                                                                                                                                                                                             | docs                                                                                                                                                                                  | `doc/test-docs.sh`          |

## 12. What this document supersedes, once recorded

Per repo `CLAUDE.md` §4, nothing is decided until the owning document says so; the revision that carries this document made these edits, and this list records what they were.

- `TYPICALLY-ONE-BEHAVIOUR-SPEC.md`: T6's "every service response" gains the sentence that `asserted` is listed by the same rule; TU-wire-b's "lazy binding there is its own work item" is pointed at §5.4 here, with the note that §5.4 extends it beyond the direct path; T1 is unchanged, and §7 here is recorded as a question T1 does not reach.
- `UNKNOWN-EVALUATION-SPEC.md`: §5 carries the §7 ruling of PRESUMPTION-SCENARIOS as a ruling with its date and Meng's words (done); §5's "a presumption is a question not yet asked" (`:871`) is joined by "an assertion is an answer given"; U9's three absences are unchanged; U10 notes the `asserted` set.
- `UNKNOWNS-BACKEND-CONTRACT.md`: its §6 gains a subsection "after the presumption-assertion design" from §8 here; it rules nothing and is not rewritten.
- `RUNTIME-INPUT-STATE-SPEC.md`: marked superseded by this document and `UNKNOWN-EVALUATION-SPEC.md` §5; its four cells are DESIGN §22's and are kept as the reference for the interview layer.
- `ladder-diagrams-2026/DESIGN.md`: §19 gains "an override from a request is an assertion (CONTRACT §2)"; §26.3 gains the `asserted` set; `types.ts:38` is cited as true until §7.
- `SURFACE-SUGAR-CLUSTER-2026-09.md` D7.3 and `IMPLICIT-PROPS-DESIGN.md` R8: unchanged by this document; §13 names the amendment that would touch them.

## 13. Non-goals and open rulings

Non-goals of this version:

- asserting an application of a parameterised definition (§3); the ladder's positional `atomId` is the obvious future address;
- asserting a definition in an imported module (§3);
- a wire spelling for a nested `MAYBE` (`JUST NOTHING` cannot be sent today; PRESUMPTION-SCENARIOS §2.6 measured it); the interview-state distinction stays as T3's absent/`null`;
- an abductive query mode: that is another engine's work, reached by export (§8);
- a contradiction detector between an assertion and the children it subsumes (DESIGN §19 defers it too);
- rendering the presumed and asserted event lists in a trace (§4.2).

Open for Meng, each a ruling and not a slice:

- **§5.4, lazy binding in both modes, on batch and both service paths**: TU-wire-b named the direct-path half; the rest is new scope, and §11 calls it breaking.
- **§7**: a presumption on a named step; no ruling reaches it.
- **Retiring `TYPICALLY` on a `MAYBE`**, amending D7.3 and R8 rule 3 (PRESUMPTION-SCENARIOS §5.2); no corpus uses, two service test fixtures, one refused docassemble export.
- **The reserved spellings** of §4.1 and `assertable` of §4.3.
- **DMN lifting an assertable `WHERE` local into its own decision** (§8), against leaving such nodes unassertable there.

## 14. What review changed (2026-10-09)

**Round one** found 28 problems, 7 overturning a sentence; each was re-verified against the tree before it was applied.
The overturned: "the picture decides" (U10b holds the ladder to the Haskell evaluator); "section `GIVEN`s do not make a definition parameterised" (discharge adds them as trailing parameters; the assertion now pins every application); the trace "records" a presumed event; the ladder's evaluators "already honour" a group override (neither does; U10b retires `eval.ts`); §7 "amends T1" (T1 is about a computed field; §7 is unruled); `fillInDefault` as the seam (it never enters a `WHERE`); and the lazy-binding test's expected rows.
The rest: line numbers at the new base; `energize` over-counts; `provenance` is a declaration-site mark, so the ladder gains an `asserted` set; a 0-ary `WHERE` local is drawn as a leaf; locals are re-allocated per activation; imported definitions are out of reach; `null` on a `MAYBE` node asserts `NOTHING`; MCP's flat arguments and the `/batch` endpoint's `@` keys; service refusals are 422; #551 lists a `WITH` fill under hard only; `@nonassertable` must be its own token; OpenFisca refuses `WHERE`, Catala lowers it to `let`; `presumed` consumer list corrected; `TYPICALLY NOTHING` has two test-fixture uses; `not-ok` golden counts; the inverted test is `:1730`.

**Round two** found 20 problems, 4 overturning a sentence, and confirmed six of the seven round-one overturns resolved; the seventh (the trace sentence) is now resolved in §4.2.
The overturned: the `@` spellings "avoid a collision" (L4 accepts `@assertions` as a name; §4.1 now reserves per surface and refuses the collision); "one schema source" (three builders, §4.3); the seam as a pass over the compiled module (the Shake surfaces evaluate source text with `noRootFills`, so the seam is `EvalConfig`, §9); and Catala's "module-level `context` variable" (`context` marks a scope variable; helper nodes are unassertable there, §8).
The rest: hard mode versus the ladder is a decide-mode statement, and an `AND` with a FALSE child reads FALSE; addressing is by unique name, not by the exported rule's scope; W8's event is a list beside the trace; registration is at allocation and reporting at first force, three sites; the force-time refusal is a new message, not "the same text"; TU-wire-b covers the direct path only, and four tests pin one-run naming; DMN inlines locals and has 39 tables, 29 UNIQUE; `Schema.hs:406` lists `@presumed` and only `OpenApiDoc.hs` requires it; the lazy-binding test needs `-e "adult presumed"`; and `doc/reference/types/TYPICALLY.md` is current bar the `null`-on-`MAYBE` sentence.
