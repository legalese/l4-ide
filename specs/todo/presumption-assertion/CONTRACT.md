# Presumption and assertion: the contract for evaluators and exporters

**Status:** proposed, 2026-10-09, revised the same day after four rounds of Opus adversarial review (§14 says what each changed); nothing in this document is built.
It is the normative statement of a design whose measurements are in `../PRESUMPTION-SCENARIOS.md` and whose one ruling so far is §7 there (Meng, 2026-10-09, in chat): named derived nodes may be asserted by a request, default-open, opted out by `@nonassertable`, with an `asserted` list in the answer.
That ruling is recorded in `UNKNOWN-EVALUATION-SPEC.md` §5 (2026-10-09, the revision that carries this document), so by repo `CLAUDE.md` §4 it is decided; what it decides, and what it leaves assumed or proposed, is stated there.
Every other choice here is **assumed, not ruled**, is marked so, and is made so that it can be reverted alone.
Where a sentence describes what the tree does today it says _today_ and cites a line at `c6d081622`.

**Who this is for.** Anyone implementing an evaluator that answers requests (jl4-core, jl4-service, `l4 batch`, jl4-mlir, the ladder) or an exporter that projects L4 into another system.
The ladder diagram is the reference **model** for what an assertion and a presumption are: §2 maps every concept here onto the ladder's own, and says which parts of the ladder are semantics and which are only drawing.
The ladder is not the authority on **values**: U10b (`UNKNOWN-EVALUATION-SPEC.md:1260`) holds the ladder's `nodeValue` to the Haskell evaluator and lists where they diverge, and this document keeps that.

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
  Known gap, today's and inherited: a reader that peeks at a thunk without `evalRef` (`peekWHNF`, `peekNF`, the deontic machinery's reads of a party) sees a filled value without reporting it (`Machine.hs:376–379`), and an asserted value bound as a value has the same gap.
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
- **A withheld presumption is an unknown, not a refusal, and on the connectives the two agree once the lift lands.** T4 rules an absent input with a withheld default "absent with none (stuck in decide mode, unknown in explore mode)" (TYPICALLY spec `:331`); `UNKNOWN-EVALUATION-SPEC.md` §4.8's `Presumed v` provenance for it is design, not built.
  Under U1 a term `AND FALSE` is FALSE whatever the order (UES `:369`, row 1 at `:688`), as in the ladder (`layout.ts:239–241`); order matters only for errors and ⊥ (U1b), and U10b lists the remaining divergences and holds the ladder to the evaluator (`:1260`).
  At `c6d081622` the lift is not built: `q AND FALSE` is stuck on `q` (`Machine.hs:7310`, `stuckOnAssumed`; the installed binary says "needed to know the value of q"); #556, open, builds it.

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

- is declared **with no `GIVEN` of its own**: a `WHERE` or `LET … IN` local at any depth (both are allocated the same way, `Machine.hs:1582–1589`), in the exported rule or in a helper it relies on, or a section- or module-level definition without parameters;
- is defined in the **main module**, not in an `IMPORT` (imported modules are evaluated once at deploy into a shared environment, `jl4-service/src/Compiler.hs:68`, `:332`, `Backend/Jl4.hs:1070`);
- and has a **name that is unique** among the nullary definitions of the main module (§3.1).

A definition with its own `GIVEN` is applied, possibly several times with different arguments; the ladder draws each application as a call panel keyed by position (DESIGN §27; `WHERE-INLINING-SPEC.md` §10.1), and asserting one application needs an argument-indexed address this version does not define (§13).
Such an assertion is refused: "`is creditworthy` takes inputs of its own; an application of it cannot be asserted by name".

**What "no `GIVEN` of its own" does not exclude, and what it means.**
Discharge gives a definition that reads section inputs those inputs as trailing parameters (`Discharge.hs:272–279`), and a `WITH` may apply it with other values in the same evaluation; a `WHERE` local is allocated afresh on every activation of its rule (`Machine.hs:1582–1585`), so a recursive rule has many.
In both cases **an assertion pins every application and every activation** to the asserted value, because the assertion is applied where the definition is allocated (§9), and the document says so rather than pretending the definition is evaluated once.

### 3.1 Addressing

A name in `assertions` is the definition's name as written, backticks removed, and it is matched against every nullary definition of the main module, wherever that definition sits: a helper's local, or one nested in an arm, is not in scope at the exported rule's body (a `Where`'s names are visible only in its own body, `Machine.hs:1582–1585`; the rule's own `WHERE` wraps that body, `Parser.hs:1635`, `:1643`), so scope is not the addressing rule, the name is.
Two nullary definitions with the same name anywhere in the main module (two arms of one rule, or two helpers each with a local `bonus`, the case `Relational/Lower.hs:1309` names) make the name ambiguous, and an assertion of it is refused naming both sites.
An **input** counts in that census too: a section `GIVEN` becomes a nullary definition of its own name at evaluation (discharge keeps the name, `Discharge.hs:300–303`; the direct path's `ReplaceAssume`, `Jl4.hs:1042`; batch's generated binding, `Batch.hs:909`), and a `WHERE` local may legally share its name (the review's probe checks and runs), so a name that is both a local and an input is ambiguous and refused, or an assertion would pin the input with no error.
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

| surface                                                                                                                                                                                                                                                                                                                                    | spelling                                                                                                                                  | reserved against                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| service `/evaluation`                                                                                                                                                                                                                                                                                                                      | `assertions` beside `arguments`                                                                                                           | nothing: the request is structured                            |
| service `/batch`                                                                                                                                                                                                                                                                                                                           | `@assertions` on a case, beside its flat inputs, as `@id` is (`Types.hs:497–498` reserves `@id` only today)                               | an input named `@assertions`                                  |
| MCP tools (flat top-level arguments for a decision function, `McpServer.hs:301`, `:506–510`, with no `presumption`, `:571`; a `DEONTIC` tool nests its inputs under `arguments` with a hand-built schema, `:283–299`; property names are sanitized to `^[a-zA-Z0-9_-]{1,64}$`, `Shared.hs:156–164`, so `@assertions` cannot be advertised) | `assertions`, declared as an object argument, beside `arguments` on a `DEONTIC` tool; the flat path's excluded-key list (`:510`) gains it | an input named `assertions`, or any name that sanitizes to it |
| `l4 batch` JSON or YAML rows                                                                                                                                                                                                                                                                                                               | `@assertions`                                                                                                                             | the same                                                      |
| `l4 batch` CSV                                                                                                                                                                                                                                                                                                                             | a column `@assert:<name>`                                                                                                                 | an input named `@assert:<name>`                               |

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
There is no single schema builder today: the service and MCP build `Parameters` in `Compiler.hs:508–510` (`parametersFromExport`), the CLI builds a JSON Schema through `L4.JsonSchema.generateJsonSchema` (`jl4/app/Schema.hs:23`, `:85`), `L4.FunctionSchema`'s builder is used only by the query plan (`DecisionQueryPlan.hs:264`), the LSP inspector builds a fourth `Parameters` for the deploy sidebar's breaking-change diff (`jl4-lsp/src/LSP/L4/Inspector.hs:419–428`), and jl4-mlir builds a fifth that promises the service's format (`jl4-mlir/src/L4/MLIR/Schema.hs:10–14`, `:1880–1890`).
The key is added at the first four, from one shared helper that lists a module's assertable nodes (**assumed**); jl4-mlir leaves it out while it refuses assertions (§8), and its README says so.
The CLI's schema is goldened per corpus file (`jl4/tests/Main.hs:541–556`), so adding the key re-blesses the `.schema.golden` files that carry a schema, 41 of 566 at `c6d081622`.
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

### 5.4 A left-out input is an unknown, and what that stacks on

Door number two depends on this: an asserted node's inputs are never reached, so they must be allowed to be left out, and today `l4 batch` and the service's direct path refuse them at decode (the review's probe: `{"married": true}` alone is refused naming `single`, `divorced` and `widowed`).

**What exists at `c6d081622`.** No undetermined outcome: `ReducedUndetermined` is not in the tree and `l4 batch`'s row statuses are `error`, `refused` and `success` (`Batch.hs:443–469`).
#556, open, builds both, as `UNKNOWN-EVALUATION-SPEC.md` §8 step 3: a `Stuck` that reaches the directive boundary becomes the undetermined outcome on every surface, with U7b's default report, "I needed to know the value of …", and in `l4 batch` a row status `"undetermined"` that never trips stop-on-error (UES `:585`, row 55 at `:742`).
**This contract stacks on #556.**

**What this document asks for, and where it is already written.** An input of the request that is left out and that nothing fills is bound to an **unknown**, so that evaluation proceeds under U1 and an answer that rests on it is undetermined, naming it, instead of a decode-time refusal.
Under soft, "nothing fills" means no default and not a `MAYBE`; under hard it also means a default withheld (T4) and a `MAYBE` not taken as `NOTHING` (T1b).
UES §8 step 6 already lists exactly this as its two dependencies, "W1's placeholders extended to every input that is not a `MAYBE`, and lazy binding on the direct path, neither of which has a W number" (`:1136`), and row 55 already rules the batch outcome (U7b).
Steps 4 to 7 are parked under MOTHBALL (`:977`), so **the open item is un-parking those two dependencies**, which is Meng's (§13); nothing here is new scope or a new choice.

**How each surface gets there.** There is no expression that stands for an unknown (`Machine.hs:6329–6330`), so the placeholder is a generated `ASSUME`:

- the wrapper path and `l4 batch` already generate `` ASSUME `x (not supplied)` `` for a left-out `BOOLEAN` (`CodeGen.hs:88–100`, W1); the dependency extends it to every type that is not a `MAYBE` (today a left-out `DATE`, `TIME` or `DATETIME` is refused by `wrapperDeclined`, `Jl4.hs:1333`, `:1344`);
- the direct path has no request decode and refuses inside jl4-service's own fills (`Jl4.hs:543`, `:595`, `:678`; `requestRecord = Nothing` there, `:792`), so it synthesizes the same `ASSUME`, or falls back to the wrapper path, for a left-out input;
- MCP is the flat path of the service and follows it.

`Machine.hs:4899–4908` (`missingFieldsMessage`) is reached only by a decode, which on the request side is the wrapper's `InputArgs`; a `JSONDECODE` the rules make keeps today's refusal.

**What this keeps and what it changes.**

- `--validate-only` follows UES step 6's recorded assumption: it warns on an absent or `null` input without marking the row invalid (`:1150`), and still names every such input in one run.
- A batch row that rests on a gap has `status: "undetermined"` rather than `"error"`; the service answers with #556's undetermined response and its `report`.
- Every test that pins the eager "Missing required field" or "missing required parameter" text for an input the rule reads changes: `tests-cli/Main.hs:1573`, `:1730`, `:1735–1739`, `:1778`; `IntegrationSpec.hs:553`, `:562`, `:564`, `:575`, `:599`, `:601`, `:689`, `:713`, `:750–755`, `:800`, `:840–851`, `:3025`, `:3026`; the `--validate-only` ones (`:1496`, `:1580`) change only in wording.
- Two tutorial pages quote the eager batch output and are the changer's to fix in the same PR (repo `CLAUDE.md` §7): `doc/tutorials/section-given/what-a-section-needs-to-know.md:298`, `:409`.

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

| target          | assertable node                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `@nonassertable`                                 | report                                                                                                                  |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Catala          | a `context` marking is on a **scope variable** (`Catala/Lower.hs:1293–1296`), so an assertable node becomes a `context` variable of the exported rule's scope, defined from the node's body; a `WHERE` local lowers to `let … in` today (`:1745–1750`) and is lifted into the scope instead; a node inside a non-exported helper, or a module-level node that such a helper reads (a helper lowers to a toplevel, which can read no scope variable, `:18–23`, `:1356–1359`), and a local nested in a `CONSIDER` arm that reads the arm's pattern variable (the review's probe `WHEN JUST b THEN doubled WHERE doubled MEANS b TIMES 2`), are not assertable in Catala | lowered as today                                 | fidelity notes name each lift and each node left unassertable                                                           |
| Blawx / s(CASP) | `WHERE` locals are already lifted into predicates (`Relational/Lower.hs:1302–1314`; `Blawx/Lower.hs:1997–2016`); `#abducible` for each assertable node beside the inputs                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | not abducible                                    | the `.blawx` fidelity notes; `BLAWX-EXPORT-SPEC` §5.1's "dropped, disclosed" for `TYPICALLY` stays a ruling until built |
| OpenFisca       | **refuses `WHERE` outright** today (`OpenFisca/Lower.hs:384`, `:397`), so a `WHERE`-local node cannot be lowered at all; a module-level node is native: an input set on a variable suppresses its formula                                                                                                                                                                                                                                                                                                                                                                                                                                                             | **cannot be expressed**; the limits page says so | OpenFisca has no fidelity report (TYPICALLY spec `:68`); `doc/exports/openfisca.md` carries both limits                 |
| docassemble     | each zero-`GIVEN` `WHERE` local already gets a `code` block (`Docassemble/Lower.hs:16–17`); an assertable node adds a `question` for the same variable                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `code` only                                      | `DA-TYPICALLY`'s sibling note (`:794–799`)                                                                              |
| DMN / dmn-md    | DMN **inlines** `WHERE` locals (`Dmn/Lower.hs:697–699`; `Relational/Lower.hs:1306`), so an assertable local has no table of its own; one that reads only inputs is lifted into its own decision (**assumed**), with an input `<name> asserted` that callers who do not assert send as `null` (a missing top-level input is a model error on KIE and skips the decision, `UNKNOWNS-BACKEND-CONTRACT.md:216`), and a rule row taking it when present, the other rows guarded on `null` so UNIQUE still holds (of the 39 tables in the tracked `.dmn` fixtures 29 are UNIQUE and 10 FIRST); a local nested in an arm cannot be lifted and is not assertable in DMN       | no lift, no input                                | the fidelity report lists every lift, every assertion input, and every node left unassertable                           |
| BPMN            | through the decision it calls                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | as DMN                                           | as DMN                                                                                                                  |
| yscript         | unmeasured; T5b makes yscript refuse a module whose exported rule reads a defaulted input (#550); probe before deciding                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | unmeasured                                       | none exists; the limits page                                                                                            |
| jl4-mlir        | refuse a request carrying `assertions` with a clear error until the marshaller carries them                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | n/a until then                                   | `jl4-mlir/README.md`'s divergence list                                                                                  |

**Three rows must not be silent.** OpenFisca loses `@nonassertable` and `WHERE`-local nodes and has no report; DMN lifts locals and gains inputs the author did not write; Catala lifts locals into the scope and leaves helper and arm-nested nodes unassertable.
Each is written on the exporter's limits page in `doc/exports/` in the same change that lowers it.

## 9. The evaluators, seam by seam

- **jl4-core: the seam is `EvalConfig`, not a module rewrite.** The wrapper path and `l4 batch` evaluate generated **source text** through Shake (`Backend/Jl4.hs:1199–1203`; `Batch.hs:433–439`; `Rules.hs:1117` calls `execEvalModuleWithEnvAndImports` with `noRootFills`), so no pass over the compiled module reaches them; what reaches every path is the `EvalConfig` each run builds (`Batch.hs:316`, `:436` through `runOneshot`, `Common.hs:274`, `Oneshot.hs:77`, to `Rules.hs:831`, `:1117`).
  `EvalConfig` gains `assertions`, a map from node name to the **JSON** the request sent, decoded during the run at the node's result type (on the Shake paths each batch row is checked under its own URI and constructors match by `Unique` including `moduleUri`, `Machine.hs:5956–5958`, `Batch.hs:435`, so nothing can be decoded ahead), and the **main module's URI**, which on batch is that row's virtual path (`Batch.hs:434`), so that only definitions of the main module match (the Shake paths evaluate every import with the same config, `Rules.hs:1103`; `Syntax.hs:43`).
  `evalDecide` consults it in **both** clauses.
  The closure clause (`Machine.hs:6352–6355`) has the definition's name but no mark saying it was declared without a `GIVEN`, because discharge appends section inputs as trailing parameters in both modes and the checker records nothing (`Discharge.hs:252–255`, `:276–279`); the fact is recovered from the pre-discharge module (`EvaluateLazy.hs:778`, `:1032`), or by every trailing argument being a section binder's own `Resolved`.
  On a hit the asserted value is bound through a fresh name in the closure's environment, as `evalConDecl`'s selectors are (`:5960`), since `ValClosure` takes an `Expr`; in the nullary clause it is bound directly.
  The match is by `rawNameToText (rawName (getActual n))`, as `EvaluateLazy.hs:843` does; every `WHERE` or `LET … IN` local reaches it on every activation (`Machine.hs:1582–1589`, `:6122–6128`, `:6319`).
  It registers at §5.2's second site with origin _asserted_, in the one `presumed` log (`tellPresumed`, `registerPresumable`, `Machine.hs:442–455`), so that `evalRef` reports it on first force (`:472–483`, `:6010–6014`); `requestPresumed` gains a sibling `requestAsserted` that selects by origin (`EvaluateLazy.hs:890`, `:898–899`), and the catch-all excludes that origin.
  Nothing is rewritten and root fills are unchanged.
  The checks that need the module (§5.3's nonassertable, root, parameterised, imported, ambiguous and nearest-name refusals, the input census of §3.1, and each node's result type) run once per module against the checked module: at deploy, at `--validate-only`, and before the first row of a batch.
- **jl4-service.** `assertions` parsed on every path and put on the `EvalConfig`: the direct path builds it at `Jl4.hs:1056` and the wrapper path inside `evaluateModule` (`:1877`), both through `requestEvalConfig`, which like `evaluateWrapperInContext` takes only a `Presumption` today (`:777–794`, `:1187–1203`) and gains the map as a parameter; `asserted` in `ResponseWithReason` beside `presumed` (`Api.hs:229`); `@asserted` on batch cases, in `Types.hs:550–560` and in the batch response schema at `Schema.hs:406`; the OpenAPI document's request schemas, which publish `presumption` (`OpenApiDoc.hs:348–349`, `:407`; `Schema.hs:373`), publish `assertions`, and its response schema requires `@asserted` beside `@presumed` (`:448`); `parametersFromExport` (`Compiler.hs:508–510`) and the inspector's copy (`Inspector.hs:419–428`) carry `assertable`; the README's envelope section.
- **`l4 batch`.** `@assertions` row key and `@assert:` CSV column (§4.1), read in `processRow` (`Batch.hs:422`; `:316` is its partial application) and **stripped from the row** before the wrapper decodes it into `InputArgs` (`:433`, `:530`), since the decoder refuses an unrecognised field wherever a default is taken (`Machine.hs:4895–4898`) and `--validate-only` would flag it; set on that row's `EvalConfig` before its `runOneshot` (`:436`), since each row gets a fresh Shake; `asserted` in the envelope; `--validate-only` names the §5.3 refusals and warns on left-out inputs (§5.4).
- **jl4-mlir.** Refuses `assertions` until the marshaller carries a second argument set; the README's divergence list gains the row.
- **Ladder.** `asserted` set in `ViewSpec` (§2); palette entry; `l4 render --format plan` lists assertable nodes.
- **Docs.** `doc/reference/types/TYPICALLY.md` is current after W2/W3, bar one drift: it says a `null` is always refused, where a `null` on a `MAYBE` fact is `NOTHING` (PRESUMPTION-SCENARIOS §2.6), fixed in the revision step; a new reference page for `@nonassertable`; the service README; the batch page; the pages that quote a `presumed` envelope; and the tutorial's final home under `doc/tutorials/`.

## 10. Tests that prove it

- jl4-core: an asserted `WHERE` local is not derived (its definition's body would error if evaluated); `asserted` lists it only when forced; `@nonassertable` refused by name; the root refused; a parameterised, an imported and an ambiguous definition refused; `null` on a non-`MAYBE` node refused and on a `MAYBE` node asserts `NOTHING`; precedence over a `TYPICALLY` on an input the node reads; a recursive rule's local pinned on every activation; a helper's local asserted by name.
- jl4-service: the same over HTTP on direct and wrapper paths; `presumption: hard` plus an assertion succeeds; `/batch` cases carry `@asserted`; MCP `@assertions`; schema carries `assertable`; a 422 for each §5.3 refusal; a module with an input named `@assertions` refused at deploy for the surfaces that reserve it.
- `l4 batch`: `@assertions` row and `@assert:` column; a row asserting a nonassertable node is `status: error` and the others proceed under `-c`; `--validate-only` still names every left-out input.
- The unknown binding, once #556 has landed, on `../PRESUMPTION-SCENARIOS.md`'s `alice.l4` with `chain.json`, `-e "adult presumed"` (the file's default export is `adult derived`, `Export.hs:180`), under hard: Bob's and Carol's rows answer; Alice with `birthdate` left out is undetermined naming `person.birthdate` (a `CONSIDER` on a term is stuck naming its inputs until step 5, UES `:361`, which needs the decoder's unknown to carry its path); Alice with `birthdate: null` is undetermined naming `presumed adult`; Alice with a known birthdate answers `true`.
  And the tests §5.4 lists rewritten to the undetermined status and report.
- Exporters: one fixture per row of §8 with a fidelity note asserting what was emitted, and the DMN lift.
- Ladder: a node with an entry in `asserted` renders as told.

## 11. Impact assessment, first cut (measured 2026-10-09 at `c6d081622`; corrected after two reviews)

| surface                             | change                                                                                                                                                                                                                                                                                                                                                                     | additive or breaking                                                                                                                           | what proves it                                              |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| L4 source corpus                    | none required: of ~5,000 `MEANS` definitions in `ok/`, `legal/`, `canon/`, roughly 2,900 are unparameterised and become addressable with no edit, roughly 1,600 are parameterised and out of scope (§3), and about 490 are indented locals (an `awk` heuristic, not a parse); `@nonassertable` is opt-in                                                                   | additive                                                                                                                                       | `jl4-test` unchanged, except the schema goldens (next rows) |
| `TYPICALLY` uses                    | 11 files / 50 lines in `ok/`, 3 / 9 in `canon/`, 0 in `legal/` and `libraries/`; `TYPICALLY NOTHING` appears in **no `.l4` file** and twice in `jl4-service/test/TestData.hs:855`, `:878`, so retiring it (§13) upgrades two test fixtures                                                                                                                                 | additive                                                                                                                                       | the grep                                                    |
| `not-ok` sources and goldens        | 9 `.l4` sources / 24 lines and 12 golden files / 34 lines mention `TYPICALLY`; untouched unless §7 is ruled and adds a new error                                                                                                                                                                                                                                           | additive unless §7                                                                                                                             | `jl4-test`                                                  |
| `presumed` producers and publishers | `DataPlane.hs`, `Types.hs`, `Backend/Api.hs`, `Backend/Jl4.hs`, `OpenApiDoc.hs:428`, `:448` (which requires `@presumed`), `Schema.hs:406` (which lists it), `Batch.hs`, `IntegrationSpec.hs`, `tests-cli/Main.hs`; no corpus golden captures a `presumed` envelope (`grep -rl '"presumed"' jl4/examples` is empty), and the pages that quote one in `doc/` are re-measured | additive: a new sibling key; old clients ignore it                                                                                             | the quoted envelopes re-run                                 |
| request decoding                    | new optional `assertions` key, with one reserved spelling per surface (§4.1); refusals of §5.3                                                                                                                                                                                                                                                                             | additive, except that a module with an input named like a reserved spelling is refused on that surface                                         | service and batch tests                                     |
| the unknown binding (§5.4)          | decode-time refusal of a left-out request input becomes an unknown, in both modes, on batch, both service paths and MCP; an answer that rests on it is undetermined; stacks on #556 and un-parks UES step 6's two dependencies                                                                                                                                             | **breaking** for a client that relied on an eager refusal, for the test sites §5.4 lists, and for two tutorial pages that quote the eager text | the §10 rows                                                |
| OpenAPI / schema                    | `assertable` key at four of the five `Parameters` builders (jl4-mlir leaves it out); `assertions` in the request schemas beside `presumption` (`OpenApiDoc.hs:348–349`, `:407`; `Schema.hs:373`); `@asserted` required beside `@presumed` in `OpenApiDoc.hs:448` and listed in `Schema.hs:406`                                                                             | additive; re-blesses the 41 corpus `.schema.golden` files that carry a schema                                                                  | `jl4-service` schema tests and `jl4-test`                   |
| exporters                           | §8 lowerings and report rows; OpenFisca, DMN and Catala limits pages                                                                                                                                                                                                                                                                                                       | additive; DMN lifts locals and emits inputs the author did not write, disclosed; Catala lifts locals into the scope                            | fixtures per row                                            |
| jl4-mlir                            | one refusal and a README row                                                                                                                                                                                                                                                                                                                                               | additive                                                                                                                                       | its test                                                    |
| the `TYPICALLY` reference page      | one drift (`null` on a `MAYBE`), fixed in the revision step; the four sources added when built                                                                                                                                                                                                                                                                             | docs                                                                                                                                           | `doc/test-docs.sh`                                          |

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

- **§5.4, un-parking UES §8 step 6's two dependencies** (placeholders for every non-`MAYBE` input, lazy binding on the direct path), which MOTHBALL parked: already ruled in substance (U7b, row 55), breaking per §11, and stacked on #556.
- **§3's narrowing** of the ruling's "every named derived node" to nullary, main-module, uniquely named nodes for the first version.
- **§7**: a presumption on a named step; no ruling reaches it.
- **`TYPICALLY` on a `MAYBE`**: keep D7.3 (recommended after the bench skeptic corrected the premise: `TYPICALLY NOTHING` is the wire's `NOTHING` presumption extended to a `WITH`), or retire it as smucclaw#645 asks, amending D7.3 and R8 rule 3; under either, `lowerDefaultLit` gains a `NOTHING` arm (PRESUMPTION-SCENARIOS §5.2, bench card C3).
- **The reserved spellings** of §4.1 and `assertable` of §4.3.
- **DMN lifting an assertable `WHERE` local into its own decision** (§8), against leaving such nodes unassertable there.

## 14. What review changed (2026-10-09)

**Round one** found 28 problems, 7 overturning a sentence; each was re-verified against the tree before it was applied.
The overturned: "the picture decides" (U10b holds the ladder to the Haskell evaluator); "section `GIVEN`s do not make a definition parameterised" (discharge adds them as trailing parameters; the assertion now pins every application); the trace "records" a presumed event; the ladder's evaluators "already honour" a group override (neither does; U10b retires `eval.ts`); §7 "amends T1" (T1 is about a computed field; §7 is unruled); `fillInDefault` as the seam (it never enters a `WHERE`); and the lazy-binding test's expected rows.
The rest: line numbers at the new base; `energize` over-counts; `provenance` is a declaration-site mark, so the ladder gains an `asserted` set; a 0-ary `WHERE` local is drawn as a leaf; locals are re-allocated per activation; imported definitions are out of reach; `null` on a `MAYBE` node asserts `NOTHING`; MCP's flat arguments and the `/batch` endpoint's `@` keys; service refusals are 422; #551 lists a `WITH` fill under hard only; `@nonassertable` must be its own token; OpenFisca refuses `WHERE`, Catala lowers it to `let`; `presumed` consumer list corrected; `TYPICALLY NOTHING` has two test-fixture uses; `not-ok` golden counts; the inverted test is `:1730`.

**Round two** found 20 problems, 4 overturning a sentence, and confirmed six of the seven round-one overturns resolved; the seventh (the trace sentence) is now resolved in §4.2.
The overturned: the `@` spellings "avoid a collision" (L4 accepts `@assertions` as a name; §4.1 now reserves per surface and refuses the collision); "one schema source" (three builders, §4.3); the seam as a pass over the compiled module (the Shake surfaces evaluate source text with `noRootFills`, so the seam is `EvalConfig`, §9); and Catala's "module-level `context` variable" (`context` marks a scope variable; helper nodes are unassertable there, §8).
The rest: hard mode versus the ladder was restated (and restated again in round four); addressing is by unique name, not by the exported rule's scope; W8's event is a list beside the trace; registration is at allocation and reporting at first force, three sites; the force-time refusal is a new message, not "the same text"; TU-wire-b covers the direct path only, and four tests pin one-run naming; DMN inlines locals and has 39 tables, 29 UNIQUE; `Schema.hs:406` lists `@presumed` and only `OpenApiDoc.hs` requires it; the lazy-binding test needs `-e "adult presumed"`; and `doc/reference/types/TYPICALLY.md` is current bar the `null`-on-`MAYBE` sentence.

**Round three** found 30 problems, 4 overturning a sentence, on the sentences round two had changed.
The overturned: `q AND p` "refuses whatever `p` is" (U1 evaluates the right operand and U7b retired "decide mode"; §2 now states the ordering difference and §5.4 the undetermined answer); `evalDecide`'s nullary clause "reaches every module-level definition" (a discharged definition that reads a section input takes the closure clause; §9 now consults both); a forced left-out input "refused with a new message" (U7b makes it an undetermined row that never trips stop-on-error, and TU-wire-b binds an assumed term; §5.4 is rewritten around the unknowns stack); and "four tests" (the sites §5.4 lists pin the eager text).
The rest: `LET … IN` locals; the rule's own `WHERE` is in scope; MCP property names are sanitized, so its spelling is `assertions`; more schema builders; the OpenAPI request schemas; per-row `EvalConfig` in `processRow`; imports share the Shake config, so the `moduleUri` check; JSON decoded during the run; a separate `asserted` log; the peek gap; a local nested in an arm is unassertable in Catala and DMN; §13 now lists §3's narrowing.

**Round four** found 25 problems, 5 overturning a sentence, on the sentences round three had changed.
The overturned: `q AND FALSE` "undetermined on `q`" (under U1 it is FALSE whatever the order; the evaluator and the ladder agree there once #556 lands, and the installed binary and `c6d081622` are both stuck on it today); "the undetermined machinery of #553 and #554" (it is #556's, open; this contract stacks on it); "only the request's decode changes" (the direct path has no decode and refuses in its own fills; the placeholder is a generated `ASSUME`); "new scope" and "this document's choice" (UES §8 step 6 already lists both dependencies, parked under MOTHBALL, and row 55 rules the outcome; the open item is un-parking); and "four builders" (five, and the CLI's schema is goldened, so 41 files re-bless).
The rest: `Presumed v` is unbuilt provenance; an input counts in §3.1's census, since a local may share a section input's name; `DEONTIC` MCP tools nest `arguments`; the full list of test sites and two tutorial pages that quote the eager text; `--validate-only` warns per UES `:1150`; a module-level node a helper reads is unassertable in Catala; DMN callers send `null`; the closure clause recovers "declared without a `GIVEN`" from the pre-discharge module and binds through a fresh name; one log with origin _asserted_, not two; `@asserted` in `Schema.hs:406`; `@assertions` stripped before the wrapper decodes a row; the main module's URI on the config; the hit-policy sentences removed here and in `UNKNOWNS-BACKEND-CONTRACT.md` §6.3.
