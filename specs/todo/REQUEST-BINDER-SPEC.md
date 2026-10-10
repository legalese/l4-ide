# Specification: one request binder for every evaluation surface

**Status:** proposed, 2026-10-11; nothing in this document is built.
It records a design review Meng asked for on 2026-10-11 ("a fresh pair of eyes on this whole thread of pending work could help simplify the architecture"), after reading bench card C1 and asking whether `l4 batch` and `jl4-service` share an evaluator component.
Word: BINDWEED (session `ternary-fable`, `b99c2a36-15fa-4c29-8b31-76bbb4fd3d83`), which superseded POTLUCK (session `ternary`).
Every claim about the tree was read on `unstable` at `f3e8de0ae`; line numbers drift, so each citation leads with the function's name.
Two things Meng said that day shape the costing: "seems like we'd want to fix that first", and "AFAIK nothing in production relies on `l4 batch`, so we have latitude to rework that if we want".

**Owning documents this touches.** `presumption-assertion/CONTRACT.md` (§5.4, §9, §13, §14; its §9 is rewritten by the revision that carries this document), `UNKNOWN-EVALUATION-SPEC.md` (§6 "the wrapper paths' root is a `MAYBE`", §8 step 6's two dependencies), `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` (T3, TU-wire-b's "lazy binding there is its own work item", W1), `UNKNOWNS-BACKEND-CONTRACT.md` (a description of the tree, to be re-measured after each slice).
It rules nothing: §10 lists what it assumes and what is Meng's, and §12 says where it stands against the open drafts.

---

## 1. The problem in one paragraph

The evaluator is shared: `L4.EvaluateLazy` is what `l4 batch` (`jl4/app/L4/Cli/Batch.hs`) and `jl4-service` (`jl4-service/src/Backend/Jl4.hs`) both call.
What is not shared is the layer that turns a request (a JSON object of inputs, a presumption switch, and soon a set of assertions) into an evaluation, and that layer exists three times, each binding the request to the module by a different mechanism.
Every open item in the presumption-and-assertion thread meets that layer: a left-out input as an unknown has to be built three times (bench card C1), the request's spellings are chosen per surface (C4), the assertion seam in CONTRACT §9 was pushed into `EvalConfig` and `evalDecide` because two of the three surfaces evaluate source text (CONTRACT §14, round two), and `l4 batch` inherits every bug in the pretty-printer because it re-prints the module to bind the row (smucclaw/l4-ide#932, #967, #1028).
This document proposes one binder, in `jl4-core`, made by promoting the service's direct path, and shows what each pending item becomes once it exists.

## 2. What the tree does today

### 2.1 Three binders

| binder                                                                                                                       | mechanism                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | reached by                                                                                                                                                                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `l4 batch`: `generateBatchWrapper` (`Batch.hs:926`), `processRow` (`:435`)                                                   | re-prints the checked module with `prettyLayout` (`batchCmd`, `:299`), appends generated L4 source (a `DECLARE InputArgs` with each input's `TYPICALLY`, `generateInputRecord` `:977`; `JSONDECODE`; one `MEANS` per read `ASSUME`, `generateAssumeBinding` `:961`; `#EVAL CONSIDER decodeArgs … WHEN RIGHT args THEN JUST (fn …)`), and runs a fresh one-shot Shake per row (`runOneshot`, `Common.hs:259`, through `Rules.EvaluateLazy`)                                                                                          | every batch row                                                                                                                                                                                                                                                                       |
| service wrapper: `generateEvalWrapper` and `generateDeonticEvalWrapper` (`Backend/CodeGen.hs`), `wrapperPlan` (`Jl4.hs:881`) | a second text generator over the same checked module: `BOOLEAN` and temporal inputs lifted to `MAYBE` (`generateInputRecordLifted`, `CodeGen.hs:335`), one `` ASSUME `x (not supplied)` `` per `BOOLEAN` (`placeholderAssumes`, `:98`; `notSuppliedTerm`, `:88`), `(input)` suffixes on field names, `WITH` for section `GIVEN`s, evaluated through Shake in the module's context (`evaluateWrapperInContext`, `Jl4.hs:1204`)                                                                                                       | a `{}` anywhere, or a `null` inside a record or list (`requiresWrapperEvaluation`, `Jl4.hs:716`); every DEONTIC call with events (`evaluateWithCompiledDeontic`, `:942`, from `DataPlane.hs:721`); `createFunction`'s fallback when `precompileModule` fails (`Jl4.hs:1415`, `:1438`) |
| service direct: `evaluateDirectAST` (`Jl4.hs:1003`)                                                                          | builds `Expr Resolved` arguments from the request (`rootInputExpr` `:527`, `fnLiteralToExprTyped` `:576`, over `buildModuleInfo` `:391`), fills each default the request may take as a 0-ary definition added to the module (`RootFill` `:464`, `rootFill` `:485`, `addRootFills` `:1096`), binds each read `ASSUME` by replacing it at its own address (`rewriteModuleAssumes`, `Export.hs:502`), and evaluates the compiled module in the shared import environment (`execEvalExprInContextOfModuleWith`, `EvaluateLazy.hs:1170`) | everything else on `/evaluation`, `/batch` (`DataPlane.hs:682`, through `RunFunction`) and MCP (`McpServer.hs:571`), all of which converge on `evaluateWithCompiled` (`Jl4.hs:806`)                                                                                                   |

A fourth binder, in JavaScript, answers the same wire for WASM (`jl4-mlir/runtime/jl4-runtime.mjs`, the `missing required parameter` refusal at `:503–513`); it reproduces the service's 422 on purpose and is out of scope here (§11).

### 2.2 What the three share

- The decision for one input or field, written once: `fillDecision` (`jl4-core/src/L4/Presumption.hs:64`), whose own header says that its three fill sites share "only the decision and the words for it", because their mechanisms differ.
- `unrecognisedMessage` and `nearestName` (`Presumption.hs`), `requestPresumed` (`EvaluateLazy.hs:1001`), `rewriteModuleAssumes` and `extractAssumeParamResolveds` (`Export.hs`), `honouredDefault` (`Export.hs`).
- The evaluator, its `presumed` log (`PresumedLog`, `Machine.hs:415`) and its reporting by forcing (`notePresumedForce`, from `evalRef`).

### 2.3 What differs, sorted silent first

- **Silent: `l4 batch` answers from a re-printed module.** Every `prettyLayout` defect that changes meaning is a batch defect with exit 0: re-associated connectives and `/` (smucclaw/l4-ide#932, fixed on `unstable` by #214 and `747dbff5f`, ported to `main` by #540), mixfix heads (#967, fixed by #440), string line breaks (#1028, PR #595).
  Repo `CLAUDE.md` §3.2.1 owes a by-hand evaluation differential to every change of `L4/Print.hs` for this reason.
  The service's wrapper path re-prints nothing: it appends the generated source to the original text after a text-based filter of the directives (`evaluateWrapperInContext`, `Jl4.hs:1211–1220`, whose comment says why: "prettyLayout can break indentation"), so it is exposed only to the printer's rendering of a `TYPICALLY` default (`wrapperPlan`'s `prettyLayout <$> Map.lookup n defaults`).
- **Silent until #556: the wrapper paths' root is a `MAYBE`.** Both text wrappers evaluate `#EVAL … JUST (call)`, so the directive's root is not the exported rule's result; `UNKNOWN-EVALUATION-SPEC.md` §6 ("The wrapper paths' root is a `MAYBE`") records what that costs the boundary decision and the bare-result rule, and the service unwraps a bare unknown inside the `JUST` by hand (`handleEvalResult`, `Jl4.hs:1340`).
- **Loud, three different ways: a left-out input.** Batch refuses it at decode (`missingFieldsMessage`, `Machine.hs:5147`: "Missing required field 'x' in JSON object"); the direct path refuses it in its own fills (`rootInputExpr`'s `RefuseMissing` arm: "Parameter 'x': missing required parameter"); the wrapper binds a `BOOLEAN` to a placeholder assumed term and lifts a `DATE`, `TIME` or `DATETIME` to `MAYBE`, which a left-out one makes `NOTHING` and the answer "Evaluation produced unknown value" (`wrapperPlan`'s comment).
  The placeholder's name reaches the report: "I needed to know the value of `has criminal record (not supplied)`" (UES §6, "two gaps between W1 as built and this spec").
- **Loud: `--validate-only` is a fourth implementation of the fill decision**, `validateRow` (`Batch.hs:575`), over the schema rather than the module, which is why it has its own message wording ("Missing required field: 'x'", `tests-cli/Main.hs:1558`) and why UES step 6's "warns without marking the row invalid" is a change to it rather than to a shared thing.
- **`presumed` is selected two ways.** The text wrappers decode the request into `requestRecordName` and the evaluator tags those fills `FromRequest` (`EvalConfig.requestRecord`, `EvaluateLazy.hs:108`); the direct path has no request decode (`requestEvalConfig … False`) and selects by the root fills it made (`requestPresumed soft id (functionInputs compiled)`).
- **Duplicated types.** `Presumption` is declared twice (`Batch.hs:131`, `Backend/Api.hs:128`); `FnLiteral`, the request's value type, lives in `jl4-service` (`Api.hs:37`); `CompiledModule` and `precompileModule` live in `jl4-service` (`Jl4.hs:59`, `:252`).
  `jl4` and `jl4-service` each depend only on `jl4-core`, so nothing in one can reach the other.

## 3. The binder

**Assumed, not ruled:** the module is `L4.Request` in `jl4-core`; the name is the least important thing here.

### 3.1 What it is

The service's direct path, moved to core and given one new arm.
Its input is a request:

```haskell
data Request = MkRequest
  { arguments   :: Map Text (Maybe FnLiteral)   -- absent key, null, or a value, as the direct path keeps it today
  , assertions  :: Map Text FnLiteral           -- CONTRACT §4.1; empty until the core build
  , presumption :: Presumption                  -- soft or hard (T4)
  }
```

Its output is a bound module, a call expression and the root fills, or every refusal at once (`attempt`, as `evaluateDirectAST` collects them today):

```haskell
data Bound = MkBound
  { boundModule :: Module Resolved     -- root fills and root assumes added, read ASSUMEs and asserted nodes replaced at their addresses
  , boundCall   :: Expr Resolved       -- the exported rule applied to its GIVEN arguments
  , boundFills  :: RootFills           -- for execEvalExprInContextOfModuleWith, and for selecting `presumed` and `asserted`
  }
```

The caller evaluates `boundCall` in `boundModule` with `execEvalExprInContextOfModuleWith` and the shared import environment, exactly as `evaluateDirectAST` does at `Jl4.hs:1077`.
A validation mode runs the binder and does not evaluate; that is `--validate-only` and the deploy-time check, from one implementation.

### 3.2 One table, one mechanism per outcome

`fillDecision` already names every outcome; the binder gives each one mechanism, at the top level and at a field or element position alike.

| `fillDecision` outcome                         | today, direct path                                                                                                                                        | binder                                                                                                                                                                    |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `UseValue`                                     | `fnLiteralToExprTyped`                                                                                                                                    | the same                                                                                                                                                                  |
| `UseDefault d`                                 | a root fill, origin `FromRootFill`                                                                                                                        | the same                                                                                                                                                                  |
| `UseNothing` (D7.3)                            | a root fill of `NOTHING`                                                                                                                                  | the same                                                                                                                                                                  |
| `NullIsNothing`                                | `NOTHING`                                                                                                                                                 | the same                                                                                                                                                                  |
| `RefuseMissing why`                            | refused by name                                                                                                                                           | **a root assume** once C1 is marked accept; refused by name until then                                                                                                    |
| `RefuseNull _ _` on a `BOOLEAN`                | refused by name on `/evaluation`; a lazy placeholder on the wrapper path (W1), which MCP and `/batch` reach for a top-level `null` (smucclaw/l4-ide#1021) | **a root assume**, at S3, with no ruling needed: W1's lazy binding is ruled (TU-wire-b) and built, and the binder applies it on every surface, which closes #1021's split |
| `RefuseNull _ _` on any other non-`MAYBE` type | refused by name on both paths (T3)                                                                                                                        | **a root assume** once C1 is marked accept, with `Declined` provenance when UES §4.8 lands; refused by name until then                                                    |

**The new arm, a root assume.**
An `ASSUME x IS A T` added to the module the way `addRootFills` adds a `DECIDE`, with a `Unique` minted under its own sort character (the list in `L4.Discharge.dischargeModule`), and referenced as `App ref []` wherever the input or field is read.
The evaluator makes it `ValAssumed` when it allocates the module (`evalAssume`, `Machine.hs:6873`), so it costs nothing unless the rule reads it, and when the rule does, the lifted evaluator of #556 carries it as a term and the directive is undetermined naming `x`, which is UES §8 step 6's outcome (row 55, U7b).
It is named by the input itself, or by the field path, so the report says `x` and not `` `x (not supplied)` ``, which closes UES §6's gap.
This is "lazy binding on the direct path" (TU-wire-b) and "W1's placeholders extended to every input that is not a `MAYBE`" (UES step 6) as one change, and it is why the wrapper path is no longer needed for an ordinary request: a `null` or `{}` inside a record is the same arm at a field position.

**One check before any of this is claimed** (§13): that a freshly minted module-level `ASSUME`, reached through `execEvalExprInContextOfModuleWith`, is reported as undetermined naming its own name, at the top level and at a field position, under soft and hard.
A pre-existing section `GIVEN` with no default already behaves so at `#EVAL` (`doc/concepts/legal-modeling/non-answers.md` §3); the minting is the only new part.

### 3.3 Reporting

`presumed` is `requestPresumed` over the root fills, as the direct path does today; the binder makes no request decode, so `EvalConfig.requestRecord` is `Nothing` on every surface and the `FromRequest` origin is reached only by a `JSONDECODE` the rules make.
An asserted node is a root fill with a new origin, `FromAssertion` (CONTRACT §9 wanted "one log with origin _asserted_, not two"), and `asserted` is the same selection by that origin.

### 3.4 Assertions, by the same pass

With every ordinary surface binding on the AST, the seam CONTRACT §14 round two overturned ("a pass over the compiled module", rejected because the Shake surfaces evaluate source text with `noRootFills`) is right again, and it is smaller than the `EvalConfig` seam that replaced it:

- `rewriteModuleAssumes` already replaces an `ASSUME` at its own address with a `DECIDE` of the supplied value, keeping its `Resolved` and `Unique` so that every reader in the module, helpers included, finds the value there.
  The binder generalises that replacement from `Assume` declarations to the nullary `DECIDE`/`MEANS` definitions CONTRACT §3 admits, replacing the body with a reference to the assertion's root fill and keeping the signature.
- Because the body is replaced at the definition and not at any call site, a discharged definition that takes section inputs as trailing parameters (`Discharge.hs`, `goDecide`) still checks and is pinned on every application, and a `WHERE` local re-allocated on every activation is pinned on every activation, which is what CONTRACT §3 promises.
- `rewriteModuleAssumes` today walks sections and their declarations only (`goDecl`, `Export.hs:520–527`); for `WHERE` and `LET … IN` locals the generalised pass descends into definition bodies.
  That is a traversal of `Expr Resolved`, of the shape `restoreMixfixPatterns` and `filterIdeDirectives` already have, not a new mechanism.
- Nothing in `evalDecide` changes, there is no `moduleUri` check (the pass runs over the main module only, by construction), and "declared without a `GIVEN`" is read from the module the binder holds, which is the pre-discharge one on the service (`CompiledModule.compiledModule`).
- The refusals of CONTRACT §5.3 (nonassertable, root, parameterised, imported, ambiguous, nearest name, `null` on a non-`MAYBE`) are the binder's, run once per module in validation mode and again per request.

So CONTRACT §1's "supplying an input is the leaf case of asserting" becomes literally true in the code: inputs and nodes are bound by one pass, and reported by one log.

### 3.5 What survives of the text generators

- **DEONTIC with events.** `generateDeonticEvalWrapper` emits `#EVALTRACE … WITH` a start time and an event list, and that is not an expression the direct path can build today; it stays, on the binder's decoded arguments, until someone builds the trace directive as AST.
  MCP and `/batch` already call a DEONTIC function without events through `evaluateWithCompiled`, so only the events path keeps the generator.
- **`createFunction`'s fallback** when `precompileModule` fails: kept until measured (§13).
  `precompileModule` fails when the module does not type-check or when the export is not found (`Jl4.hs:258–266`; what `buildImportEnvironment` does on a failure of its own is unread), and the fallback then type-checks the same source again per request, so it is likely dead; §13 lists the measurement.
- Everything else in `CodeGen.hs` that serves a non-deontic request (`generateEvalWrapper`, `generateInputRecordLifted`, `placeholderAssumes`, the `LET` nesting for `BOOLEAN` and temporal inputs) is retired by slice S3 of §8.

## 4. What moves from `jl4-service` to `jl4-core`

`FnLiteral` and its parser (`Backend/Api.hs:37`; `parseFnLiteral`), `Presumption` (one declaration, replacing `Api.hs:128` and `Batch.hs:131`), `CompiledModule`, `SharedModuleContext`, `precompileModule`, `buildSharedContext`, `buildCompiledFromShared`, `buildImportEnvironment` (`Jl4.hs:59–80`, `:252`), `ModuleInfo` and `buildModuleInfo` (`:391`), `RootFill`, `Fills`, `FillCtx`, `rootFill`, `rootInputExpr`, `fnLiteralToExprTyped`, `attempt`, `addRootFills`, `inputDefaults` (`:731`), `inputNames`, `functionInputs`, `refuseUnknownArguments` (`:751`), and the ISO date, time and datetime parsing `fnLiteralToExprTyped` uses.
`jl4` then depends on nothing new, and `jl4-service` keeps its HTTP types, `RunFunction`, the trace rendering and the two surviving generators.
This move is the bulk of slice S1 and most of the cost; it changes no behaviour.

## 5. Each surface, after

- **`l4 batch`.** Per row: build the `Request` from the row (JSON, YAML, or the CSV adapter that reads an empty cell as absent, T3c), bind it against the precompiled module, evaluate, and write the same envelope keys as today (`input`, `output`, `status`, `presumed`, `diagnostics`, with `asserted` and `report` beside them when the core build lands).
  No re-print, no per-row Shake, no `JSONDECODE` of a string literal; the module is parsed and checked once.
  `--validate-only` is the binder in validation mode: it names every refusal, and after C1 warns on a left-out input without marking the row invalid (UES step 6's recorded assumption).
  It may be stricter than `validateRow`, which "never rejects what it cannot judge" on a compound type, because the binder converts every field; S2's PR measures the difference over the batch fixtures, and Meng's latitude on batch covers it.
  `l4 batch` keeps its row statuses (`error`, `undetermined`, `refused`, `success`) and `finish`'s exit rule (`Batch.hs:339`).
- **`/evaluation`.** `evaluateWithCompiled` binds and evaluates; `requiresWrapperEvaluation` goes once S3 lands, and with it the wrapper path for an ordinary request.
- **`/batch` and MCP.** Unchanged in shape: each already builds the request's argument map and calls `runFunction`.
  Their reserved spellings for `assertions` are CONTRACT §4.1's (bench C4), each an adapter onto `Request.assertions`.
- **DEONTIC with events.** The binder decodes the arguments; `generateDeonticEvalWrapper` still emits the `#EVALTRACE`.
- **jl4-mlir.** Unchanged; its README's divergence list gains nothing until the core build (CONTRACT §9's jl4-mlir row).

## 6. What a consumer notices, sorted silent first

- **Silent, and gone: the re-print.** A batch answer can no longer differ from `l4 run` through `L4/Print.hs`; repo `CLAUDE.md` §3.2.1's differential still guards `l4 batch`'s own `prettyLayout` of a `TYPICALLY` default, and the REPL, and nothing else on this path.
- **Silent, for a few service requests: trace shape.** A request that took the wrapper path for a `{}` or a nested `null` answers through the direct path after S3, whose reasoning tree is the common one; jl4-mlir reproduces the service's trace shape on purpose (UES §8 step 2), and the parity harness is read by hand.
  `l4 batch` emits no trace, so it is unaffected.
- **Loud: one wording for a left-out or `null` input.** _Assumed, not ruled:_ the direct path's wording wins ("Parameter 'x': missing required parameter"; `ASSUME 'x': …` for a written `ASSUME`), because the service's consumers and the WASM runtime already pin it (`jl4-runtime.mjs:513`), and `l4 batch` adopts it, which Meng's latitude on batch allows.
  The JSON decoder's wording (`missingFieldsMessage`) stays for a `JSONDECODE` the rules make.
- **Loud: `--validate-only`'s wording** follows the same unification; its status and exit code change only with C1.
- **Loud, after C1 only:** the refusals the §7 tests pin become undetermined answers; that is C1's cost and is unchanged by this document.

## 7. Tests and pages that pin today's behaviour

Read at `f3e8de0ae`; each is re-pinned by the slice named.

- `jl4/tests-cli/Main.hs`: the batch refusals at `:1635`, `:1795`, `:1800`, `:1840` and the `--validate-only` wording at `:1558`, `:1642` (S2 re-pins the wording; C1 changes the outcome); the `--validate-only` statuses at `:1514` (a schema mismatch), `:1535` (a `MAYBE` primitive's type), `:1557` (an `ASSUME` read only by a helper, left out) and `:1601` (unchanged by S2, which may still reject a row `validateRow` passed, §8; only `:1557` changes with C1, since a type mismatch stays invalid when a left-out input becomes a warning).
- `jl4-service/test/IntegrationSpec.hs`: the direct-path refusals at `:563`, `:574`, `:609`, `:611`, `:699`, `:763`, `:765`, `:810`, `:3122` (unchanged until C1); the wrapper-path refusals at `:572`, `:585`, `:723`, `:860`, `:3121`, which pin the JSON decoder's wording and become the direct path's at S3.
- `doc/tutorials/section-given/what-a-section-needs-to-know.md:298`, `:410` (quoted batch output; S2 re-quotes, C1 re-measures); `jl4-service/README.md:215`, `:239` (the two-path description; S3 rewrites it); `jl4-mlir/README.md:62–63` and `jl4-runtime.test.mjs:892` (unchanged).
- Counts at the last full gate on this base: `l4-cli-test` 498 examples (84 pending), `jl4-service-test` 489.

## 8. Migration order

Each slice lands alone; S1 and S2 need no ruling.

- **S1. Move, no behaviour change.** §4's list moves to `jl4-core`; `jl4-service` imports it; every test green and unchanged; after lane C and #552, or carrying their hunks (§12).
  Its PR says which names moved and from where, and nothing else.
- **S2. `l4 batch` on the binder.** `processRow` builds a `Request` and calls the binder; `generateBatchWrapper`, `generateInputRecord`, `generateAssumeBinding`, `validateRow` and the per-row `runOneshot` go; the envelope keeps its keys; §7's batch tests are re-pinned to the unified wording; the tutorial page is re-quoted.
  Measured before merge: the §3.2.1 differential no longer applies to batch, and the batch examples in `doc/` give the answers they gave.
- **S3. The root assume.** `RefuseMissing` and `RefuseNull` become root assumes at every position (§3.2); `requiresWrapperEvaluation`, `generateEvalWrapper` and the non-deontic half of `CodeGen.hs` go; the wrapper-path tests of §7 move to the direct path's wording; `jl4-service/README.md` describes one path.
  **This slice is breaking where C1 is, and waits on C1's mark for those arms**: `RefuseMissing`, and `RefuseNull` on a type other than `BOOLEAN`.
  The `BOOLEAN` arm needs no ruling (§3.2) and may land first, with the wrapper retired for a request whose only not-known values are `BOOLEAN`s; a `{}` or `null` elsewhere keeps the wrapper path until C1, because refusing it on the direct path would turn today's decode-time refusal by name into `fnLiteralToExprTyped`'s "unknown value for a non-MAYBE parameter", which is a change for no gain.
- **S4. Assertions.** CONTRACT §9 as rewritten: `Request.assertions`, the generalised rewrite, `FromAssertion`, `asserted`, the §5.3 refusals, the schema key; waits on C4 and C6, as the bench's queue says.
- **S5. The fallback.** Measure whether `createFunction`'s slow path is ever reached (§13); remove it if not.

## 9. What this does to the bench and the contract

- **C1** stays a ruling: the cost of building step 6's two dependencies falls from three sites to one arm (§3.2), and the cost that remains is the breaking half, §7's sites and `--validate-only`'s status and exit code, which this document does not change.
- **C4** stands as printed, and is smaller: the structured `Request` is canonical, and each flat surface is one adapter with one reserved key.
- **C6** stands; §3.1's census is the binder's, run in validation mode.
- **C2, C3, C5** are language and exporter questions this document does not reach.
- **CONTRACT §9** is rewritten by the revision that carries this document: the jl4-core seam is the binder, not `EvalConfig.assertions`; §5.4's "how each surface gets there" points here; §13 and §14 record the change.
- **UES §6**'s "the wrapper paths' root is a `MAYBE`" describes a path that S3 retires for ordinary requests; it is marked so when S3 lands, and the deontic wrapper's `JUST` is then the one remaining case.
- **TY TU-wire-b**'s "lazy binding there is its own work item" is this document's §3.2.

## 10. Assumed, not ruled; and open for Meng

Assumed, each revertible alone:

- the module name `L4.Request` and the two record types of §3.1;
- the direct path's wording wins the unification (§6);
- a root assume for `RefuseNull` carries `Declined` provenance only when UES §4.8 lands, and until then is the same assumed term as a left-out input;
- the DEONTIC-with-events generator stays rather than being rebuilt as AST;
- S1 and S2 need no ruling, since they change no answer a consumer sees except the batch wording Meng has released.

Open for Meng, each a ruling and not a slice:

- **C1**, which gates S3, as the bench has it.
- **Nothing else new.** This document adds no card; its disagreements with the printed recommendations of C2 and C5 were given to Meng in chat on 2026-10-11 as input to his marks, and the cards stand as printed.

## 11. Non-goals

- The WASM runtime's own binder (`jl4-runtime.mjs`), which mirrors the service's wire by design and is held to it by `jl4-runtime.test.mjs`.
- The five schema builders CONTRACT §4.3 lists; one shared helper for `assertable` is CONTRACT's, and a single schema source is a separate, later simplification of the same kind.
- Exporters: nothing here changes a lowering.
- A per-request `EvalConfig` change: the binder adds nothing to `EvalConfig`; `presumeDefaults` and the limits stay where they are.

## 12. Lane C and #552 edit what §4 moves

Measured 2026-10-11 against the fetched refs `pr/558` (the head of the stacked drafts #551, #557, #558: W4, W5, W7, W10) and `pr/552` (W8, W11), neither in `unstable` at `f3e8de0ae`, by `git diff -U0 origin/unstable...<ref>` over the files §4 names, reading hunk context only and not the hunks' bodies.

- Lane C changes `wrapperPlan` and `evaluateWithCompiledDeontic` (`Jl4.hs`, +83), `requestPresumed`, `withDefaultsKnown`, `execEvalModuleWithDefaults` and `execEvalModuleWithJSON` (`EvaluateLazy.hs`, +48), `assumesReadBy`, `recordFieldDefaults` and `decideBodiesFromModule` (`Export.hs`, +85), and four lines of `Batch.hs`.
- #552 changes `rootFill`, `wrapperPresumed`, `evaluateWithWrapper` and `createFunction` (`Jl4.hs`, +62/-9), `requestPresumed`, `withDefaultsKnown` and `EvalDirectiveResult` (`EvaluateLazy.hs`), so that a default shows as a node in the reasoning tree on every path.
- Every one of those but the deontic wrapper is in §4's list or is what §4's list calls.

So slice S1, the move, lands **after** lane C and #552 or carries their hunks; landing it first would make four open drafts conflict in the files they most edit, on top of the conflicts they already have with `unstable` (TREADMILL's fourth pass is pending).
The order is Meng's; this document's recommendation is lane C and #552 first, then S1, because S1 is pure motion and rebases cheaply, and lane C's decisions (a default at a named call and at a construction; `presumed` listing such a fill under hard only; an event's record taking no default) are the binder's table rows once they are ruled, and are easier to carry in than to re-derive.
What lane C decides is pending Meng's review and none of it is recorded as ratified; §3.2's table takes its rows from `fillDecision` as it is on `unstable` today and gains lane C's rows when they land.

#606 (`@nonassertable`, head `d7f6d9be0`, queued) records the mark on the definition's `Anno`, read by `L4.Export.isNonassertableDecide`; §3.4's generalised rewrite is where the refusal of CONTRACT §5.3 reads it.

## 13. What this document did not verify

- That a freshly minted module-level `ASSUME` reached through `execEvalExprInContextOfModuleWith` is reported as undetermined naming it, at the top level and at a field position (§3.2); the first commit of S3 is that test, before any arm changes.
- Whether `createFunction`'s fallback is ever reached in a deployed service (§8 S5); the control plane's logs say whether a precompile has ever failed on a module that then served a request.
- Timing: no row of `l4 batch` was timed before or after; the claim is structural (one parse and check per module rather than per row), not measured.
- Whether any test outside §7 pins the wrapper path's trace shape for a `{}` request; `grep -rn '{}' jl4-service/test` before S3.
- Whether the direct path shares batch's `WITH`-override defect: `rewriteModuleAssumes` drops a replaced section binder from the section's `GIVEN` (`goSection`'s `filterGivenSigTo`), which is the mechanism behind smucclaw/l4-ide#1000 ("giving named inputs … not a function" in batch with every input supplied); S2 moves batch onto that function, so S2's PR probes an inner `WITH` over a bound section input on both surfaces first.
