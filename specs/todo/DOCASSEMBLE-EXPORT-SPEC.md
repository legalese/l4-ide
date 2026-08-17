# L4 → Docassemble: interview export and transpiler spec

_Status: **M1, M2 and M4 implemented; M1 review-repaired. M3 (the embedded plan) is not
implemented.** Designed 2026-08-16 on branch
`mengwong/docassemble-bridge`; M1 (the static core, §10) landed the same day on branch
`mengwong/docassemble-backend`: the `L4.Docassemble.{IR,Lower,Emit}` module triple in jl4-core
plus the `l4 docassemble` CLI verb in jl4, mirroring the shipped OpenFisca backend. A same-day
review pass repaired five executed-and-confirmed defects (DAObject-namespace attribute
shadowing; ASSUME/seam-guard reference collection missing inlined-function bodies; the dead
computed-field pathway; `WHEN JUST TRUE` mis-read as a binder; non-self-triggering Mako
escapes) — the repair notes live in the §8 sections they belong to. Verified by the golden +
refusal tests under `describe "l4 docassemble"` in `jl4/tests-cli/Main.hs`, and by the R10
headless round-trip: all sixteen fixture cases of the six examples under
`jl4/examples/docassemble/` ran green against `docassemble.base` 1.10.7 (checkout `1b6678384`)
in-process._

_**M2 landed 2026-08-17** on branch `mengwong/docassemble-m2`, test-first: the acceptance tests
were written red first (commit `178b4946`, 15 failing cases) and the implementation made them
pass. It ships `--package DIR` (the PEP 420 tree, R11), `data/sources` provenance as a byte
copy, the generated runtime module loaded via `modules:`, `@ref` citations carried through
`explain()`/`logic_explanation()` onto verdict screens, and the `auto terms:` glossary. It also
carries one language repair the glossary needed: a `@desc` on a `WHERE`/`LET` binding used to be
dropped silently (§3). Verified by 33 cases under the three `describe "l4 docassemble…"` blocks
and by the R10 harness run on all seven examples, each driven from BOTH the bare YAML and a real
`--package` tree with the per-case `(goal, verdict, citations)` triple asserted equal — see
`jl4/examples/docassemble/README.md` for the transcript. The `--package` clobber policy, the
fidelity report's placement in the tree, and the reversal of R4's `clear_explanations()`
sentence are recorded as implementation notes in §8.11, §8.11 and §8.4. **M3 (embedded plan) and
M4 (breadth) remain unimplemented.**_

_**M4 landed 2026-08-17** on branch `mengwong/docassemble-m4`, test-first: the acceptance tests
were written red first (commit `ec9850f6`, 15 failing CLI cases and 7 of 7 examples not
round-tripping) and the implementation made them pass. It ships §10's whole M4 bullet —
`LIST OF <record>` gathered as a `DAList`, constructor payloads as `show if` follow-ups,
`MAYBE NUMBER`/`MAYBE DATE` as paired is-known questions, the R12 date surface, a `review:`
compliance checklist on every interview, and the document-assembly demo — plus the repair of the
inherited §8.4 staleness defect, whose named owner M4 was. Verified by 57 cases under the four
`describe "l4 docassemble…"` blocks (including thirteen byte goldens and their fidelity
sidecars) and by `m4_acceptance.sh`, which drives all seven examples in real `docassemble.base`
1.10.7 from BOTH artifact shapes and reports **0 of 7 not round-tripping**, with the per-case
`(goal, verdict, citations)` triple asserted equal across shapes. Two scope rulings the milestone
had to make rather than drift into are recorded where they belong — the payload-value match
(§8.8) and the date surface (§8.12, R12) — each with the implementation note that discharges it.
**M3 (the embedded plan) remains unimplemented; `DAPackage.pkgPlan` is still `Nothing`.**_

**One-line summary.** Docassemble discovers evaluation order at runtime by backchaining on
undefined variables — the same "what do we still need to ask?" question L4's query planner
answers at compile time — so a transpiler emits _definitions, not sequence_, which is exactly the
shape of an L4 module: every `@export`ed `DECIDE`, every `WHERE` binding, every record field, and
every `@desc` survives as a named, independently seekable docassemble variable with its L4 name
as its label; the layers that cannot survive (deontic, temporal, ledger) are declared loudly
through the house `L4.Interchange.Fidelity` vocabulary rather than silently dropped. Where the
OpenFisca backend compiles L4 to a _computational_ engine (vectorised formulas, no user in the
loop) and the unmerged Catala spec targets a _semantic_ peer, this backend compiles L4 to an
_elicitation_ engine: the citizen-facing, question-at-a-time interview layer that
`specs/todo/housing-act-citizen-wizard-demo.md` records as the honest gap in our own stack — the
shipped housing wizard renders every field at once and never calls the query-plan endpoint
(`ts-apps/housing-wizard/src/lib/schema/classify.ts:18`; no hit for `queryPlan` in its `src/`).

**Evidence legend.** **[E]** = read out of the named file at the named commit by this session or
its read-only survey agents, or executed here. **[R]** = carried from the companion review
`l4-docassemble-report` (session "docassemble", 2026-08-16), not independently re-read here.
**[U]** = believed, not verified. L4 facts were read at `8af7d332` (`unstable`); docassemble
facts at `/Volumes/transcend/src/jhpyle/docassemble`, commit `1b6678384` (2026-08-03), version
**1.10.7**, `requires-python >= 3.12` (`docassemble_base/pyproject.toml:6,14`) **[E]**.
Executed in this session: `docassemble_base` installed from that checkout into a plain
Python 3.12 venv and a three-block interview **parsed, assembled, answered, and completed
headlessly** — no server, no Redis, no Flask (§8.10, Appendix B) — so the R10 harness question
is settled by experiment, not belief. The worked YAML in Appendix A remains **[U]** until M1's
golden pins it.

---

## 0. Ruling status

| ruling | state                   | detail                                                                                   |
| ------ | ----------------------- | ---------------------------------------------------------------------------------------- |
| R1     | **ANSWERED** 2026-08-16 | CLI surface: own verb; package placement; plan lives above core, §8.1                    |
| R2     | **ANSWERED** 2026-08-16 | records → DAObject subclasses, one question per _field_, §8.2                            |
| R3     | **ANSWERED** 2026-08-16 | survival: every reachable `DECIDE`/`WHERE` binding → one `code:` block, §8.3             |
| R4     | **ANSWERED** 2026-08-16 | the verdict seam: scope-first driver, six-valued verdict, §8.4                           |
| R5     | **ANSWERED** 2026-08-16 | question order: native backchaining v1, embedded plan M3, §8.5                           |
| R6     | **ANSWERED** 2026-08-16 | datatype map; enums as string-valued radios; floats, §8.6                                |
| R7     | **ANSWERED** 2026-08-16 | `TYPICALLY` → `default:`, Advisory divergence, §8.7                                      |
| R8     | **ANSWERED** 2026-08-16 | `MAYBE` erased to optionality, as both schema paths do, §8.8                             |
| R9     | **ANSWERED** 2026-08-16 | emission hygiene: Mako escaping, `sets:`, `id:`, `depends on:`, self-validation, §8.9    |
| R10    | **ANSWERED** 2026-08-16 | validation harness: headless docassemble.base, proven by probe, never a build dep, §8.10 |
| R11    | **ANSWERED** 2026-08-16 | artifact shape: bare YAML v1, installable package M2, §8.11                              |
| R12    | **ANSWERED** 2026-08-17 | the M4 date surface: what lowers, what refuses by name, which idiom, §8.12               |

R12 was ANSWERED 2026-08-17 by the M4 RED phase, on the measurement recorded in §8.12; it did
not exist on 2026-08-16 because §10's M4 bullet named an idiom without bounding a surface.

All eleven ANSWERED 2026-08-16: signed off by Meng in session `xpile-docassemble` after a
quiz-card review of the full roster; none contested. Each §8 section retains its evidence, its
cost, and its original closure condition — where that condition names an implementation
artifact (a golden, a harness transcript), the ruling is decided but the artifact is still
owed, and M1/M2 deliver it. (State vocabulary follows the bridge-family convention set by
`CATALA-EXPORT-SPEC.md`.)

## 1. Purpose, direction, precedent

Direction is **L4 → docassemble** only. The reverse direction is a non-goal (§11): docassemble
interviews embed arbitrary Python and Mako, so the reverse problem is decompilation, not
transpilation.

The OpenFisca backend fixes the architectural shape **[E]**:
`lowerModule :: Module Resolved -> Either [LowerError] OFPackage`
(`jl4-core/src/L4/OpenFisca/Lower.hs:61`) starting from `getExportedFunctions`
(`Lower.hs:63`), per-function results combined with `partitionEithers` so all errors surface at
once (`Lower.hs:76-81`), every unsupported `Expr` constructor refused with a named phrase
(`constructorName`, `Lower.hs:387-405`), name sanitisation total and collision-checked
(`pyIdent` `Lower.hs:754`, `checkCollisions` `Lower.hs:814`), and an emitter that builds
`[Text]` rather than a pretty-printer `Doc` "so indentation is exact and golden-stable"
(`Emit.hs:5-6`) — doubly binding for YAML, an indentation-sensitive format.

The DMN/BPMN backends fix the loss-reporting shape **[E]**: `L4.Interchange.Fidelity` with
severities `Blocking | Lossy | Advisory` (`jl4-core/src/L4/Interchange/Fidelity.hs:25-30`), a
sibling `.fidelity.txt` next to `--output` or stderr otherwise, no non-zero exit on Blocking
unless `--fail-on` asks for it (`jl4/app/L4/Cli/Export.hs:18-52`). OpenFisca predates this layer
and does not use it; docassemble, which _will_ lose the deontic, temporal, and ledger layers,
adopts it from day one.

What docassemble buys that no existing backend does:

1. **An elicitation runtime.** Docassemble's assembly loop evaluates `mandatory` blocks and, on
   an undefined variable, catches the exception, recovers the name, and backchains to whichever
   `question:` or `code:` block defines it, indexed most-specific-first
   (`parse.py:8539` loop, `:8781` handler, `:9059` `askfor`, `:4738` variable index; candidate
   ordering at `:9092`) **[E via survey]**. That is L4's `queryDecision` support-set computed
   lazily at runtime.
   One L4 source therefore becomes a _conversation_, not a form.
2. **Document assembly on the same dependency engine.** `attachment` blocks (DOCX/Jinja2,
   fillable PDF) participate in the same variable-seeking loop — an attachment with
   `variable name:` registers as seekable like any block (`parse.py:5002`, sought at
   `:9514-9530`) **[E via survey]** — so a verdict screen that
   also assembles the notice or the demand letter is a capability neither OpenFisca nor Catala
   nor our own housing wizard offers.
3. **A deployed install base in exactly our adjacent market** — legal aid, court self-help,
   clinic intake — reachable as a compile target rather than a rewrite.

## 2. Docassemble's execution model, as reviewed

A capsule of the target, at commit `1b6678384` (v1.10.7). All paths below are under
`docassemble_base/docassemble/base/` unless noted; the traps here are restated as emission rules
in §7 and rulings in §8.

- **Backward chaining by exception.** `Interview.assemble()` (`parse.py:8539` **[E]**) re-runs
  mandatory blocks from the top on every pass; an undefined variable raises
  `NameError`/`DAAttributeError`/`DAIndexError`; the handler recovers the variable name from
  the exception and `askfor()` finds the defining block, most-specific candidate first
  (the four-key sort at `parse.py:9092`) **[E via survey]**.
  Demonstrated end-to-end headlessly in this session: a `mandatory` verdict screen pulled a
  `code:` block which pulled a `yesno` question, unprompted (Appendix B) **[E]**. Two
  consequences bind the emitter: driver code must be **idempotent** (pure references and
  conditionals), and generated Python must **never wrap or rephrase** these exceptions.
- **Python short-circuit is the pruner.** `a and b` in a `code:` block never seeks `b` when `a`
  is `False` — so _operand order in emitted expressions is question order_, which aligns with
  `specs/todo/QUESTION-ORDERING-SPEC.md`'s declaration-order-is-sacred baseline **[E]** and is
  exactly what the L4 evaluator's short-circuit does.
- **Stale by default.** A derived variable, once computed, persists even when its inputs later
  change; recomputation happens only for blocks declaring `depends on:` (`parse.py:3507`,
  `invalidate_dependencies` `parse.py:8014`) **[E]**. L4 semantics are pure recomputation, so
  every emitted derived block carries `depends on:` over its direct inputs.
- **No endpoint, no interview.** Assembly that completes without a terminal `mandatory`
  question raises `DAErrorNoEndpoint` (`parse.py:9034`) **[E]**; the package must end in a
  verdict screen (§8.4).
- **Silent acceptance.** Unrecognised top-level YAML keys are _logged only when
  `interview.debug`_ and otherwise ignored — the recognised-key whitelist is the ~180-entry
  tuple at `parse.py:1947` **[E]**, which is exactly the table R9 vendors. An unrecognised
  field modifier silently becomes the field's _label_ (`parse.py:4318-4321`) **[E]**. A typo in
  the emitter therefore produces a block or modifier that does nothing, with no error anywhere.
- **Mako everywhere.** Question text compiles as Mako with `strict_undefined=True`
  (`parse.py:1394`) **[E]**; a stray `${` in legal prose imported from `@desc` becomes an
  accidental dependency or a hard error — hence escaping in R9.
- **Objects.** `objects:` blocks instantiate `DAObject`/`DAList`/`Individual` trees; every
  attribute is independently seekable via `DAObject.__getattr__` (`util.py:1211` — note the
  object system lives in `util.py`; `core.py` is a shim) **[E]**, and `generic object`
  questions (`parse.py:2736-2739`) define attributes for _any_ instance of a class
  (`x.attribute`) **[E]**. This is the record story, R2.
- **The pluggy seam (new in 1.10.0).** Every server service behind `docassemble.base` is a
  pluggy hook (`hookspecs.py`, `plugin_manager.py` — the manager registers hookspecs and _no_
  implementations; the webapp registers its own at
  `docassemble_webapp/docassemble/webapp/app_initialize.py:68-95`) **[E]**. Consequence,
  proven by the Appendix B probe: a ~13-method `HeadlessPlugin` makes `docassemble.base`
  parse _and assemble_ interviews in-process with no server at all. Thread state is
  contextvar-scoped: enter `global_context(empty_globals())` from `thread_context.py` **[E]**.
- **Headless drive, three altitudes.** (a) `docassemble.base` + `HeadlessPlugin` — proven
  here, the R10 harness **[E]**; (b) `docassemble.webapp.testing.TestContext` — imports the
  full Flask app and login machinery (`docassemble_webapp/docassemble/webapp/testing.py:1-35`
  imports `flask_app`, `login_as_admin`) **[E]**, so it is an in-container tool, not a venv
  tool; (c) a real server over `/api/session/*`, with `GET /api/interview_data` as the
  vocabulary check **[R]** — the demo path, not the test path.
- **Eager/lazy edges of the pruner.** Generator forms short-circuit; list forms do not:
  `all(...)`/`any(...)` over a generator stops at the first decisive element, while
  `all([...])`, list comprehensions, and f-strings evaluate everything. In generated code this
  is a semantic difference, not style (R9). Two escape hatches run eagerly by design: `need:`
  (evaluated before question text renders) and Mako in question prose (lazy, top-to-bottom,
  `strict_undefined`).
- **A built-in explanation seam.** `explain(text, category=…)` appends-if-absent to
  `_internal['explanations']`, read back by `logic_explanation(category)`
  (`util.py:13227-13270`) **[E via survey]**; the canonical pattern is
  `docassemble_demo/.../examples/explain.yml`. Because of short-circuit evaluation, calls
  placed in rule blocks record _exactly the rules that fired, in execution order_ — an
  audit-grade "why" trace for free. Separately, the engine's own seeking trace
  (`InterviewStatus.get_history()`, `parse.py:597-650`) records which block fired for which
  variable, but only under `debug` — a developer/harness oracle, not a user-facing one.
- **Interview-scale guards.** `loop limit` and `recursion limit` both default 500
  (`parse.py:7942-7943`), raised via `features:` — a large generated rule graph should emit
  these scaled to its size.
- **Version floor.** `requires-python >= 3.12` (`docassemble_base/pyproject.toml:14`) **[E]**;
  playground packages require `pyproject.toml` with a valid SPDX license expression as of
  1.8.0 **[R]** — both bind M2's package emission.

## 3. The L4 export surface consumed

All **[E]**. The selection layer is `L4.Export`:

- `getExportedFunctions :: Module Resolved -> [ExportedFunction]` (`Export.hs:125`); only
  explicit `@export` counts (`Export.hs:131-132`); topmost is promoted to default when none is
  marked (`Export.hs:133-136`).
- `ExportedFunction` carries name, description, params, return type, and the `Decide Resolved`
  itself (`Export.hs:44-51`). `ExportedParam` carries `paramDescription` (falling back from the
  parameter's `@desc` to the _type's_ `@desc` via `buildTypeDescMap`, `Export.hs:270` — free
  prose on a record `DECLARE` reaches every question generated from that record),
  `paramRequired = not . isMaybeType` (`Export.hs:258`), and `paramDefault` from `TYPICALLY`.
- Structured `@desc` payloads follow the `descKeyword` convention
  (`L4/OpenFisca/Lower.hs:446-455`): first word is the tag, remainder is payload. This backend
  reserves the tag `docassemble` for per-declaration overrides (§8.6) rather than inventing new
  annotation syntax.
- **`@ref` reaches `Module Resolved`, but on the node above the one you expect.** A `@ref`
  written above a top-level definition attaches to the **TopDecl** `Decide ann d` node, not to
  the inner `MkDecide`; above a `WHERE` binding it attaches to `LocalDecide ann d`
  (`l4 ast` on `citations.l4`, three `LocalDecide` annos each carrying a `MkRef`) **[E]**. A
  node's `Anno` holds at most one ref and the nearest preceding one wins, every other becoming a
  `RefNotAttached` warning (`attachRef`, `ResolveAnnotation.hs:1162-1172`) **[E]** — which is why each block's
  citation must be read from its _own_ node. The payload text **includes the herald**: `getRef`
  hands back `"@ref X"` verbatim (unlike `getDesc`, which strips), and the inline form hands back
  `"<<X>>"`, delimiters and all **[E]**. `@ref-src` and `@ref-map` are dead in the AST
  (`Parser.hs:246-252` maps `refAdditionalP` to `Just ()`); the LSP hover reads `@ref-map` off the
  raw token stream instead **[E]**.
- **A `@desc` on a `WHERE`/`LET` binding used to be dropped silently — repaired 2026-08-17.**
  `instance HasDesc (Expr n)` was `pure`, so the desc pass never descended into an expression,
  and a `WHERE` binding lives inside `Where Anno (Expr n) [LocalDecl n]`. The _ref_ pass already
  descended there, so the two disagreed: the `@ref` above a binding attached, the `@desc` on the
  next line reached no node at all and raised no warning (`l4 ast citations.l4 | grep -c 'desc =
Just'` ⇒ 6, none of them the three annotated `MEANS` bindings; `l4 check` ⇒ "Check succeeded")
  **[E]**. `ResolveAnnotation.hs` now traverses into `LocalDecl`, in source order. Behaviour
  change worth knowing: such a desc used to stay pending and could be claimed by a _later_
  top-level declaration (`descPrecedesNode` admits any preceding desc within 8 columns of slack);
  it is now claimed by the binding it was written above. The `auto terms:` glossary is the first
  consumer that needs a binding's own gloss.

  **Corrected by the review pass (2026-08-17).** The first repair handled only `Where` and `LetIn`
  and ended `other -> pure other`, so a `LET` nested inside any other expression — an `IF` arm, a
  `CONSIDER` branch, an operand — still dropped its binding's `@desc` silently, with `l4 check`
  reporting success (`l4 ast … | grep -c 'desc = Just'` ⇒ 0 for a `LET` under `IF TRUE THEN … ELSE`,
  1 for the byte-identical `LET` at the top of the body) **[E]**. `instance HasDesc (Expr n)` is now a
  structural, exhaustive descent mirroring `HasRef (Expr n)`, with sibling instances for
  `GuardedExpr`/`Branch`/`BranchLhs`/`Pattern`/`NamedExpr`/`Deonton`/`RAction`/`Event`;
  exhaustiveness is enforced by `-Wincomplete-patterns` rather than by a fallthrough. Nothing below
  an `Expr` calls `attachLeadingDesc` except the declarations reached through `LocalDecl`, so the
  wider recursion consumes no desc it did not consume before. Measured blast radius: `cabal test
  jl4-test` ⇒ 2568 examples, 0 failures, and `git status` clean — no corpus golden moves **[E]**.

  That measurement is honest but uninformative on its own, which is the other half of what the
  review found: across the 367 corpus files `jl4-test` globs there is not one `@desc` inside a
  `WHERE`/`LET` region (re-measured this session) **[E]**, so the suite could not have moved
  whichever way either change went, and the original commit shipped no test at all. The oracle now
  lives at `jl4/tests-cli/fixtures/desc-attachment.l4` with two assertions in
  `describe "@desc attachment to WHERE/LET bindings"`, because **no jl4-test golden can express
  this property** — none of evaluation, exactprint, nlg or schema shows which node owns a desc.
  Ownership is read off the `auto terms:` glossary, which keys every entry by the name of the
  definition that owns the gloss; the nested case, which `collectGlossary` cannot reach, is read
  off `l4 ast`, where "owned" is exactly "the payload occurs somewhere other than inside a raw
  `TDesc` token".

  Both assertions were demonstrated falsifiable rather than assumed to be: reverting
  `instance HasDesc (Expr n)` to `pure` and rebuilding turns both red, and the failure the fixture
  reports is the concrete mis-attachment rather than a bare absence — the glossary comes back as
  `"claim window in days": "BINDINGGLOSS the title is free of encumbrance"`, the gloss claimed by
  the _next top-level declaration_, which carries no `@desc` of its own precisely so that this shows
  up **[E]**. The nested payload's owned-occurrence count goes 1 → 0 over the same revert, and
  `citations.l4`'s glossary collapses from four entries to one.

- Post-resolution expressions arrive with infix operators desugared to builtin applications
  (`__PLUS__`, `__AND__`, …; `L4/Desugar.hs:145-147`); `IfThenElse`/`MultiWayIf`/`Consider`/
  `Proj`/`Lit`/`Percent`/`Where`/`LetIn` survive as constructors; a bare variable is a nullary
  `App` (`Syntax.hs:350-351`); booleans arrive as names, not literals (`Lower.hs:328-331`).
- `WHERE` is `Where Anno (Expr n) [LocalDecl n]`, `LocalDecl = LocalDecide … | LocalAssume …`
  (`Syntax.hs:257,452-454`) — every binding is a full `Decide`, possibly with its own `GIVEN`s.
- Record fields: `MkTypedName` 4th field is the `TYPICALLY` default, 5th distinguishes stored
  (`Nothing`) from computed/`MEANS` (`Just expr`) fields (`Syntax.hs:129-131`); stored fields
  become questions, computed fields become `code:` blocks, mirroring `Lower.hs:620`.
- `TYPICALLY` today: lexes and parses (`Lexer.hs:331`, `Parser.hs:655,1244,1253`), reaches
  `FunctionSchema.parameterDefault` (`FunctionSchema.hs:46,245-247`), feeds query-plan priors,
  and is **ignored by the evaluator** (`EvaluateLazy/Machine.hs:3374` binds and drops it). The
  status header of `TYPICALLY-DEFAULTS-SPEC.md` ("BACKED OUT") predates this re-landing as
  metadata and is stale on that point.
- The question-ordering machinery is a pure library, `jl4-query-plan` (deps: base, aeson,
  containers, jl4-core, text): `compileDecisionQuery`/`queryDecision`
  (`BooleanDecisionQuery.hs:369,437`), six-valued `Verdict` (`:210-224`), seam-aware support
  (`supportIdxOf`, `:259-269`), UUIDv5 atom ids and field-path-level asks
  (`QueryPlan.hs:204-210, :38-86`). It sits _above_ jl4-core in the dependency order, which forces the
  placement decision in R1. Its input is the ladder-pass `BoolExpr`, not `Expr Resolved`, and
  the ~30-line glue is currently duplicated in jl4-lsp and jl4-wasm — a third copy is refused;
  see §8.5.

## 4. The mapping, construct by construct

The organising principle, per the commissioning instruction: **as much as possible of an L4
encoding survives, by name and by structure.** An L4 reader and a docassemble reader should
recognise the same program.

| L4 construct                                             | docassemble target                                                                                                                                                                                          | survival                             |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `@export` `DECIDE`/`MEANS` (boolean or numeric goal)     | goal variable defined by a `code:` block; the default function drives the single `mandatory` block                                                                                                          | clean                                |
| `GIVEN p IS A <Record>`                                  | `objects:` instance of a generated `DAObject` subclass                                                                                                                                                      | clean, R2                            |
| stored record field                                      | one `question:` block per field (`generic object` style), label = backticked L4 name, help = `@desc`                                                                                                        | clean, R2                            |
| computed (`MEANS`) record field                          | inlined at each projection site — desugar strips `MEANS` fields pre-typecheck into synthesized selector decides, so there is no field left to hang an attribute `code:` block on (M2 may restore one), §8.2 | clean (inlined), R2                  |
| `WHERE`/`LET` binding, zero-`GIVEN`                      | one namespaced `code:` block each                                                                                                                                                                           | clean, R3                            |
| `WHERE` binding with `GIVEN`s (local function)           | Python function in the generated module, called from `code:` blocks                                                                                                                                         | clean, R3                            |
| non-exported top-level `DECIDE` reachable from an export | `code:` block (no `@export` needed for helpers, unlike OpenFisca's cross-entity contract)                                                                                                                   | clean, R3                            |
| `AND`/`OR`/`NOT`, comparisons, arithmetic                | Python operators, fully parenthesised; operand order preserved = question order                                                                                                                             | clean                                |
| `IF…THEN…ELSE`, `BRANCH`, `CONSIDER` over enums          | Python conditionals / `if…elif…else` chains in `code:` blocks                                                                                                                                               | clean                                |
| top-level `IMPLIES` in an exported decision (the seam)   | scope and requirement as separate variables; scope-first driver; six-valued verdict                                                                                                                         | R4 — the landmine                    |
| `DECLARE … IS ONE OF` (nullary constructors)             | `datatype: radio` + `choices:`, values = constructor names as strings                                                                                                                                       | clean, R6                            |
| constructors with payloads                               | deferred: `show if` follow-up fields                                                                                                                                                                        | M4                                   |
| `STRING`                                                 | `datatype: text` — docassemble has strings (Catala does not)                                                                                                                                                | clean                                |
| `NUMBER` (exact `Rational`)                              | `datatype: number` (Python float) — same class of divergence as OpenFisca's float32, Advisory note                                                                                                          | R6                                   |
| `DATE`, date comparisons                                 | `datatype: date` → tz-aware `DADateTime`; comparisons safe among docassemble-produced values; every emitted literal routed through `as_datetime()`                                                          | clean for comparisons; arithmetic M4 |
| `MAYBE OF T`                                             | optional field, erased as in `FunctionSchema.hs:147-148`                                                                                                                                                    | R8, Advisory                         |
| `TYPICALLY`                                              | `default:` prefill                                                                                                                                                                                          | R7, Advisory                         |
| `@desc` on decide/param/type                             | `question:` text, field `help:`                                                                                                                                                                             | clean                                |
| `@ref` on a `DECIDE` or `WHERE` binding                  | `explain()` in that rule's own `code:` block; `logic_explanation()` on every verdict screen                                                                                                                 | clean, M2 (shipped)                  |
| `@ref` on an expression                                  | nothing — an expression is not a `code:` block, so there is nothing to hang the call on                                                                                                                     | **Advisory** `DA-REF-EXPR`           |
| plain `@desc` on a `DECLARE` or a named definition       | one `auto terms:` glossary entry, keyed on the L4 term                                                                                                                                                      | clean, M2 (shipped)                  |
| `#EVAL`/`#ASSERT` fixtures                               | round-trip oracle inputs (R10); **not emitted** into the interview, per the DMN R0 precedent                                                                                                                | n/a                                  |
| `LIST OF`                                                | `DAList` gathering: `object_type` plus either `there_are_any`+`there_is_another` or `ask_number`+`target_number`; `complete_attribute` orders, it does not prune (see §10, corr. 1)                         | M4                                   |
| deontic (`PARTY MUST … HENCE/LEST`)                      | none; docassemble multi-user roles/actions are a plausible future mapping, not attempted                                                                                                                    | **Blocking** note                    |
| temporal (`EVAL … UNDER RULES EFFECTIVE AT`, four pins)  | none                                                                                                                                                                                                        | **Lossy** note                       |
| ledger (`RECORD`/`FETCH`/`ATTEST`)                       | none (docassemble's `DAWeb` exists for outbound HTTP, unused)                                                                                                                                               | **Blocking** note                    |
| `Inert` prose scaffolding                                | Markdown in `subquestion`/section headers where attached; else dropped with Advisory note                                                                                                                   | partial                              |

## 5. What does not map, and how loss is declared

The refusal table is `constructorName`-shaped (`OpenFisca/Lower.hs:387-405`): `Regulative{}`,
`Event{}`, `Fetch{}`, `Record{}`, `ReadCell{}`, `Post{}`, `Breach{}` each refuse with a named
diagnostic **and** a `FidelityNote`. Severity assignment follows
`specs/todo/FIDELITY-SEVERITY-AXIS-SPEC.md`: `Blocking` when the function cannot be emitted at
all (deontic body, ledger effects), `Lossy` when it is emitted minus meaning (temporal pins
ignored, and — M2 — an `auto terms:` entry docassemble's key space cannot carry, `DA-GLOSS-REGEX`
/ `DA-GLOSS-COLLIDE`, §8.9 item 4), `Advisory` when meaning is preserved but semantics differ in a
way a reviewer should see (float for Rational, `default:` for `TYPICALLY`, erased `MAYBE`, and a
`@ref` on an expression, `DA-REF-EXPR`). The report placement and `--fail-on` gate copy
`jl4/app/L4/Cli/Export.hs:18-52` verbatim.

## 6. The v1 source fragment, precisely

v1 accepts exactly: `@export`-annotated `DECIDE`/`MEANS` whose parameters are records of
primitives (BOOLEAN, NUMBER, STRING, DATE, nullary-constructor enums, nested records) and bare
primitives; bodies drawn from the constitutive expression layer — builtin applications,
`IfThenElse`/`MultiWayIf`/`Consider` (nullary patterns + mandatory `OTHERWISE`), `Proj`, `Lit`,
`Percent`, `Where`/`LetIn`, calls to other in-module decisions, local and top-level function
application. Goal type: BOOLEAN, NUMBER, STRING, or enum (the planner is boolean-only —
`translateDecide` rejects non-boolean **[E]** via `Ladder.hs` — but _emission_ is not: a numeric
goal simply forgoes seam/verdict treatment and M3 ordering).

Everything else is refused by name. This fragment is a strict superset of OpenFisca v1's (which
refuses `Where`) and matches the shape of the existing eligibility corpus: the Housing Act
grounds, Reg CF gates, `rodentsAndVermin.l4` (whose `WHERE`-heavy body is the first golden —
note it carries no `@export` today **[E]** `jl4/examples/ok/rodentsAndVermin.l4`, so the example
directory gets an annotated copy, as the OpenFisca examples did).

## 7. Architecture

```
                 jl4-core                                jl4 (executable)
  ┌────────────────────────────────────────┐   ┌───────────────────────────────┐
  │ L4.Docassemble.IR      target-shaped   │   │ L4/Cli/Docassemble.hs         │
  │ L4.Docassemble.Lower   Module Resolved │──▶│  option parsing, typecheck,   │
  │   -> Either [LowerError]               │   │  lowerModule, renderPackage,  │
  │        (DAPackage, FidelityReport)     │   │  fidelity placement, --fail-on│
  │ L4.Docassemble.Emit    DAPackage->Text │   │  (M3: + jl4-query-plan to     │
  └────────────────────────────────────────┘   │   embed the compiled plan)    │
                                               └───────────────────────────────┘
```

- **IR.** `DAPackage` = interview metadata + `[DABlock]` where
  `DABlock = DAQuestion | DACode | DAObjectsBlock | DAEventScreen | …`, plus `DAExpr`, a small
  Python expression IR (the OpenFisca `OFExpr` at the same altitude, minus numpy). All types
  `deriving stock (Eq, Show, Generic)`, strict fields, no Aeson.
- **Lower.** From `getExportedFunctions` + module scans (enums, records, reachable helper
  decides). Emits `LowerError` per function, `partitionEithers`, `checkCollisions` for the
  sanitised-name map. Produces the `FidelityReport` alongside the package, as DMN's lower does.
- **Emit.** `renderPackage :: DAPackage -> Text`, `[Text]`-and-`unlines`, YAML by construction:
  every scalar that could contain L4-derived prose is emitted through one quoting/escaping
  function (R9). Provenance header comments name the source file and the pinned docassemble
  version the output was validated against.
- **CLI.** `l4 docassemble FILE [-o OUT] [--fail-on=…]`, body copied in shape from
  `OpenFisca.hs:46-74`; five registration edits (`Main.hs:37,58,101-103,172`; `jl4.cabal:60`);
  jl4-core.cabal gains the three modules beside `:151-153`. The verb-vs-`l4 export` question is
  R1. The new verb name cannot collide with a plausible filename because of the bare-filepath
  fallthrough to `l4 run` (`Main.hs:61-67`) — "docassemble" is safe.
- **Tests.** `jl4/examples/docassemble/{*.l4, expected/*.yml, not-ok/, README.md,
roundtrip_check.py}`, hand-registered `expectGolden` blocks appended after
  the `describe "l4 openfisca"` block at
  `jl4/tests-cli/Main.hs:2331`, byte-exact, each failure printing its regeneration command
  (`Main.hs:345` precedent).

## 8. Open rulings

### 8.1 R1 — CLI surface and package placement

**Evidence.** The repo splits its backends: DMN/BPMN live under `l4 export --to=…` as "foreign
interchange notations"; OpenFisca got its own verb as "a compiler to a runnable artifact"
(`jl4/app/L4/Cli/Export.hs:1-11` vs `L4/Cli/OpenFisca.hs:1-7`) **[E]**. `jl4-query-plan` depends
on jl4-core, not vice versa; today the `l4` executable does not depend on jl4-query-plan (only
jl4-lsp, jl4-repl, jl4-service, jl4-wasm do) **[E]**.

**Proposal.** Own verb `l4 docassemble` (runnable artifact), Fidelity discipline adopted from
the `l4 export` side anyway. Backend triple in jl4-core. The M3 plan-embedding step composes in
`jl4/app`, which then adds a jl4-query-plan dependency, following the jl4-wasm precedent of
depending only on jl4-core + jl4-query-plan; the `vizExprToBoolExpr` glue gets _lifted into
jl4-query-plan_ rather than duplicated a fourth time (it exists twice today:
`jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs:150`, `jl4-wasm/app/QueryPlanWasm.hs:82`) **[E]**.

**Cost.** The IR must anticipate M3 (a slot for an optional embedded plan) so M3 does not
rework Emit. **What would close it:** sign-off, plus a one-line check that `cabal build exe:l4`
stays clean when jl4-query-plan is added in M3.

### 8.2 R2 — records become DAObject subclasses; questions are per _field_, not per record

**Evidence.** Docassemble's unit of asking is the variable, and every `DAObject` attribute is
independently seekable (`util.py:1211`); `generic object` questions cover any instance
(`parse.py:2736-2739`) **[E]**. The shipped
housing wizard renders whole-record forms at once and is recorded as the gap this backend
closes **[E]** (`housing-act-citizen-wizard-demo.md`). One-screen-per-record would reproduce
that flat form inside docassemble and forfeit pruning: a screen's fields are all demanded
together, so unneeded inputs get asked.

**Proposal.** Per L4 record type: a generated `DAObject` subclass (in the package's Python
module) whose class name is the sanitised L4 type name; `objects:` instantiates each
record-typed parameter; each stored field yields one `generic object` question block on
`x.<field>`, label = the backticked L4 field name verbatim, help = field/type `@desc`; each
computed field yields a `code:` block. Nested records nest as attribute objects. Field-name
sanitisation is `pyIdent`-shaped, total, collision-checked; the original name always survives
as the label, so the user-facing interview speaks L4's vocabulary even where Python cannot.

The engine's candidate ordering makes the generic layer sound: `askfor` expands a sought name
into abstract variants and sorts candidates non-generic-first, then more-dots-first, then
more-brackets-first (the four-key sort at `parse.py:9092`; class matching walks the MRO,
`parse.py:7770-7775`) **[E via survey]** — so generic-object questions are a _fallback layer_
and any concrete hand-written override in a customised package beats them without
coordination. Emit questions under the wildcard language `'*'`. Two mechanical contracts:
every generated variable name must be a valid Python expression path (the missing-name string
is regex-recovered and fed back to `eval`), and generated object constructions always pass
`instanceName` explicitly — docassemble otherwise sniffs the caller's bytecode to recover it,
which machine-generated call shapes will defeat.

**Cost.** Multi-field single-screen grouping (a genuine UX preference sometimes) is deferred; a
later `@desc docassemble screen …` grouping override can restore it. **What would close it:**
the R10 harness demonstrating that a two-record, six-field example asks only the fields the
goal's evaluation actually demands.

**Implementation note (2026-08-16, M1).** M1 narrows this ruling: record-typed parameters are
instantiated as plain `DAObject` (no generated subclass yet — a subclass needs the generated
Python module, which arrives with M2's `--package`), and every stored field yields a
_specific-instance_ question on the concrete attribute path (`i.field`), not a `generic object`
fallback layer; nested record fields are instantiated by `code:` blocks passing `instanceName`
explicitly, honouring the bytecode-sniffing contract above. The closure artifact is delivered in
narrowed form: the R10 harness shows per-field demand-driven asking — the `defaults` example's
promo-code question is never asked on the short-circuited path, and the seam example's
requirement questions are never asked on the NotApplicable path.

**Implementation note (2026-08-17, M2): the `generic object` layer is DEFERRED to M4, and this
is measured, not assumed.** M2 was asked to settle by experiment whether the generic layer is
safe to adopt now. Two things were executed against `docassemble.base` 1.10.7 in the R10 harness:

1. **Adding it changes nothing.** A `generic object: DAObject` question defining
   `x.amount_raised_in_12_months` was appended to the emitted `citations.yml`, beside the
   specific-instance question that already defines `o.amount_raised_in_12_months`, and the
   interview was driven from both. The same three questions fire, by the same block ids, in the
   same order, to the same goal — `askfor`'s candidate sort is non-generic-first
   (`parse.py:9092`), so the specific question wins every time. The probe is
   `probe_generic_object.py`, run by hand like the rest of the R10 harness.
2. **It has nothing to fall back _for_.** A generic question is a fallback for _other instances_
   of the class, and a v1 interview has none: every emitted interview instantiates at most one
   object (`objects:` blocks in the seven committed goldens hold 1, 1, 1, 1, 1, 1 and 0 entries).

So adopting it _in addition_ is provably inert, and adopting it _instead_ would rewrite all six
M1 byte goldens for no behavioural gain. It becomes meaningful at M4, when `LIST OF` → `DAList`
gathering creates the second instance; that is where it belongs. Until then R2's "each stored
field yields one `generic object` question block" stays narrowed to the specific-instance form
M1 landed.

**Repair notes (2026-08-16 review pass).** Two more mechanical contracts, both found by
executed probes:

1. **Generated attribute names must stay out of the `DAObject` namespace.** An attribute whose
   sanitised name matches a DAObject method or `__init__`-set instance attribute is _never
   sought_: normal lookup finds the pre-existing (truthy) member, `__getattr__` never raises,
   docassemble never backchains to the emitted question, and the bound method rides into the
   boolean expression as `True` — a silent wrong verdict, executed with a field named
   `alternative` (live legal vocabulary: suitable alternative accommodation). The lowering
   suffixes such names (`alternative` → `alternative_`; label unchanged) against a vendored
   83-name set, `dir(DAObject) ∪ vars(DAObject('x'))` probed at the 1.10.7 pin
   (`daObjectReserved`, `Lower.hs`). `pyReserved` guards only top-level names; attribute
   positions need this set.
2. **Computed (`MEANS`) fields lower by inlining, not by attribute `code:` blocks.** The
   desugarer (`Desugar.hs` `desugarComputedFields`) strips `MEANS` fields out of the
   `RecordDecl` _before_ type checking and synthesizes a top-level selector decide
   (`f _self MEANS …`) per field, so in a `Module Resolved` the record has no computed fields
   left — the originally-planned per-field `code:` block pathway was dead code, and a
   projection onto a computed field refused with the false diagnostic "record has no field".
   The repair inlines the synthesized selector at each projection site (it is a parameterized
   top decide, so the R3 inlining machinery applies, recursion guard included). The proposal's
   "each computed field yields a `code:` block" is narrowed accordingly for M1; M2's module
   emission is the natural point to revisit a named attribute block.

### 8.3 R3 — survival: every reachable decision becomes a named `code:` block

**Evidence.** `Where` bindings are full `Decide`s (`Syntax.hs:257,452-454`) **[E]**. OpenFisca
refuses `Where{}` ("later milestone", `Lower.hs:387-405`) and requires cross-referenced
decisions to be `@export`ed; neither restriction is forced here, because docassemble variables
are free and backchaining resolves references in any order **[E/R]**.
`rodentsAndVermin.l4` is the existence proof: its five `WHERE` bindings _are_ the legal
structure ("loss or damage by animals", "exclusion apply"…), and flattening them away would
destroy exactly the isomorphism the commissioning instruction asks to preserve.

**Proposal.** Every zero-`GIVEN` `LocalDecide` and every reachable top-level `DECIDE` (exported
or not) lowers to one `code:` block defining one variable named `<owner>_<binding>` (sanitised;
top-level names unprefixed), with `depends on:` over its direct free variables. Function-valued
`LocalDecide`s (e.g. the eta-expanded `not covered if MEANS GIVEN x YIELD x`) lower to pure
Python functions in the generated module, applied inline — they are not seekable and need no
block. Intermediate variables are inspectable in docassemble's variable browser and citable on
the verdict screen: the L4 structure survives at runtime, not just in the source.

**Cost.** Name length; a prefix scheme that must stay deterministic across recompiles (ties
into R9's `id:` stability). **What would close it:** the rodents golden showing five `code:`
blocks whose names and labels round-trip the five `WHERE` bindings.

**Repair note (2026-08-16 review pass).** Reachability must be computed over the closure of
_all_ reachable top-level bodies — including parameterized decides, which survive by inlining
rather than as blocks of their own. M1 as first landed collected references from export bodies
plus zero-parameter helper bodies only, with two executed consequences: an `ASSUME` referenced
only through an inlined function got no question block (the emitted code referenced `base_rate`,
nothing defined it, and assembly raised `DAErrorMissingVariable` at runtime with no
compile-time diagnostic), and the R4 dangling-seam-goal guard (§8.4) missed a reference that
travelled through an inlined function, emitting the exact dangle it exists to refuse. One fix
serves both: `allRefs` is now the union over export bodies plus every reachable top-decide
body (`Lower.hs` `reachBodies`), and reference collection also walks projection heads so
computed-field selectors (§8.2) count as callees. Pinned by `assume-via-fn.l4` (golden +
round-trip) and `not-ok/seam-ref-via-fn.l4`.

### 8.4 R4 — the verdict seam: never emit `NOT scope OR requirement` as the driver

**Evidence.** The planner holds the top-level implication of an exported decision as three BDD
roots and reads a six-valued verdict — `Undetermined / Holds / Fails / Complies / InBreach /
NotApplicable` — refusing the classical short-circuit precisely because "the rule never reached
you" and "you complied" are both `True` (`BooleanDecisionQuery.hs:210-269`; seam support taken
from the _sides_, `:254-269`) **[E]**. Nested implications read classically **[E]** (Ladder
seam handling). A naive transpile would tell a user they "complied" with a rule that never
applied — the one semantic landmine the companion review flags, and it is real.

**Proposal.** When an exported boolean decision's body is a top-level `Implies scope req`
(post-resolution: `App __IMPLIES__ [scope, req]`), emit `scope` and `requirement` as separate
seekable variables and a driver of the shape

```python
if <scope>:
    verdict = 'Complies' if <requirement> else 'InBreach'
else:
    verdict = 'NotApplicable'
```

so docassemble's own control flow forces scope resolution before requirement questions — the
seam semantics fall out of block structure with no BDD at runtime. The driver opens with
`clear_explanations()` and every emitted rule block contributes `explain()` lines carrying its
rule's `@ref`/`@desc` text (M2), so the verdict screen's reasoning list is exactly the rules
that fired, in order, deduplicated — the `explain.yml` pattern (§2). Non-seam boolean goals get
`Holds`/`Fails`; every verdict value gets its own terminal `event:` screen carrying the goal's
`@desc` and (M2) `@ref` citations. `Undetermined` cannot be reached in v1 (docassemble asks
until defined); it becomes reachable in M3/M4 when "I don't know" answers arrive (the
four-state input model of `RUNTIME-INPUT-STATE-SPEC.md`, itself blocked on TYPICALLY evaluator
semantics — noted, not depended on).

**Cost.** Verdict vocabulary is fixed by the planner's `Verdict` type; renaming later breaks
goldens. **What would close it:** an R10 transcript of a seam example where answering the
requirement questions first is impossible because scope is asked first, and a NotApplicable
run that never asks a requirement question.

**Implementation note (2026-08-17, M2). The `clear_explanations()` sentence above is REVERSED:
the driver must not call it.** The proposal copied that from docassemble's own exhibit
(`docassemble_demo/…/examples/explain.yml`), where every `explain()` call lives _inside_ the
mandatory block and so re-runs on every pass. Here they live in separate `code:` blocks, which
docassemble caches once their variable is defined, while the mandatory driver re-runs on every
assemble pass — so the clear wipes what the rule blocks recorded and never lets them run again.

Executed: adding exactly that one line to the emitted `citations.yml` and re-running the R10
harness gives

```
[exempt (all three rules fire)] offering_exempt = True; verdict-screen citations are [],
expected exactly ['17 CFR 227.100(a)(1) — offering maximum', ...]  *** MISMATCH ***
```

with the rendered screen carrying the "Why this answer" heading and nothing under it. Without
the line the same harness run is green, on both cases and both artifact shapes. So M2 emits no
`clear_explanations()`, and `explain()` dedupes by string (`util.py:13239`) so a re-run block
cannot double-cite.

**Correction (2026-08-17, review pass). The sentence "session-scoped accumulation is the correct
behaviour here" was too strong and is withdrawn.** What the measurement above establishes is
narrower: on a forward drive, accumulation is correct _and_ `clear_explanations()` is wrong. It
does not establish that accumulation is right in general, and it is not:

- `explain()` appends to `_internal['explanations']` (`util.py:13235-13240`) and nothing in an
  emitted interview ever clears it, while `invalidate_dependencies` (`parse.py:8014-8060` at
  `1b6678384`) deletes the invalidated _variables_ and never touches that history. So a flow that
  re-defines an already-answered variable re-decides the goal correctly and leaves the verdict
  screen citing rules that were short-circuited away — the exact failure `citations.l4` exists to
  catch. Measured live against 1.10.7 through `POST /api/session` with `delete_variables`
  (`helpers.py:638-645` execs a plain `del`): goal flips to `False`, citations stay at all three
  **[E]**.
- Two exported decisions driven in one session share one list, with no API involved: driving a
  second export's action recorded `['s 10(1) — time limit', 's 22(4) — fee']` on one screen **[E]**.

Two suspected triggers were counter-probed and are **clear**: the plain back button calls
`fetch_previous_user_dict`, which restores a whole prior `user_dict` snapshot with
`_internal['explanations']` inside it, and the API's plain `set_session_variables` never invalidates
at all, because `helpers.py` writes the value before capturing `old_values`, so
`parse.py:8028`'s `if current_value == old_values[field_name]: return` fires **[E]**.

**Ruled: narrow M2 rather than patch it, and say so.** No emitter-side fix survives docassemble's
block caching. Clearing in the driver is the measurement above. Re-deriving the list in the driver
would mean re-encoding the whole rule graph's short-circuit structure in the mandatory block, which
duplicates every rule and abandons "the rules that actually fired" for "the rules a second
implementation thinks fired". Scoping `explain(cite, <goal>)` by category (the signature supports it,
`util.py:13227`) fixes the two-export half but silently breaks the shared-helper case: a helper
`code:` block is module-level (`lowerHelperTop`, `Lower.hs`), reachable from more than one export,
and can only name one category — trading an extra citation for a missing one, which is worse.

So M2's claim is hereby bounded to the forward drive, which is the only flow it emits UI for, and
the boundary is recorded here, in `jl4/examples/docassemble/README.md`, and in the `citations.l4`
header. **M4 owns the repair**, because M4 is already specced (§10) to ship a `review:` block —
the surface that makes re-answering ordinary, and therefore the first release in which this is a
plain-browser bug rather than an API-only one.

**M4 RED phase, 2026-08-17: the defect is WORSE than bounded here, and no single flag repairs
it.** Re-measured against the shape the backend actually emits — one `code:` block per rule, each
with its own `explain()`, plus `depends on:`/`sets:` (`expected/citations.yml:42-84`) — with the
answer changed the way a review-block Edit changes it (`undefine()` then re-ask):

- **the VERDICT goes stale, not merely the citations.** With `amount` corrected from 9,000,000 to
  1,000 the goal stays `False` and the citations stay unchanged (**executed**). The bound above
  says "re-decides the goal correctly and leaves the verdict screen citing rules that were
  short-circuited away"; that was measured through the API's `delete_variables` path, and it does
  not hold on the undefine-and-re-ask path. `depends on:` did not rescue it.
- **`reconsider: True` alone is actively worse than nothing**: it fixes the verdict but makes the
  citations ACCUMULATE contradictory rules — "maximum EXCEEDED" and "maximum satisfied" together
  (**executed**). `initial: True` + `clear_explanations()` alone empties the list to `[]`. Both
  together give the right verdict and no citations at all.
- **What does work — two designs, both verified (**executed**), and M4 picks neither here.** The
  explaining must be ATOMIC IN ONE BLOCK. Either (A) move every `explain()` into the mandatory
  driver with `clear_explanations()` as its first statement, `reconsider: True` on the driver and
  the rule blocks; or (B) drop `explain()` and derive `cite_*` variables. Both yield the right
  verdict and exactly the rules that fired, before and after a changed answer.

The acceptance test states this as a CLAIM and not as a design: `roundtrip_check.py`'s
`citations` example carries a `change_answer` case asserting that after the edit the goal, the
verdict and the citations are what they would have been had the new answer been given first. It
is RED today with all three wrong. Note that adopting either design changes M2's emission shape,
which is byte-golden-pinned; that is ruled IN as M4's owned repair by the paragraph above, and
the goldens are re-blessed consciously in the GREEN phase.

**REPAIRED 2026-08-17 (M4 GREEN), by a third design the RED phase did not find.** The
`change_answer` case is green: after correcting 9,000,000 to 1,000 the goal is `True` and the
citations are exactly the four rules that now fire, in order — the same list the interview
produces when 1,000 is given first.

The repair keeps `explain()` where M2 put it (in each rule's own block, AFTER the assignment, so
a rule that raised on a missing input records nothing) and adds two things:

1. **`reconsider: True` on every derived block.** Those variables are deleted at the top of
   `Interview.assemble` (`parse.py:8590-8596`) — once per assemble pass, NOT once per iteration
   of the logic loop — so every rule is recomputed from the current answers. This is what fixes
   the verdict. It is emitted on rules, on `WHERE` bindings, on the goal and on the driver, and
   NEVER on an instantiation block: re-running one would replace the `DAObject` or `DAList` and
   discard everything gathered into it.
2. **A citation-reset sentinel**, `l4_citations_fresh`, emitted only when the module cites
   anything. Its block calls `clear_explanations()` and is itself `reconsider`ed, so it runs
   once per pass; and the mandatory driver REFERENCES IT BEFORE THE GOAL.

Reference-before-goal is the whole mechanism, and it is why this works where the RED phase's
candidates did not. Docassemble seeks the sentinel, runs its block (emptying the list), and only
then reaches the goal, which pulls the rules that explain into the list just emptied. A clear
placed at the top of the DRIVER instead would run again on the driver's second iteration —
after the rules have already explained — and wipe them; that is exactly the `initial: True` +
`clear_explanations()` result the RED phase measured as "empty citations". The sentinel converts
"clear at the start of the pass" from a thing the emitter hopes about block ordering into a data
dependency docassemble is obliged to honour.

Design (A) was declined for a reason worth recording: moving every `explain()` into the driver
requires the driver to re-encode the rule graph's short-circuit structure, which is the same
objection §8.4 already sustained against re-deriving the list ("the rules a second implementation
thinks fired"), and it is incompatible with a per-rule `@ref` — the citation lives on the
definition, so the block that decides must be the block that cites. The CLI test asserting the
assignment precedes `explain()` in each block still passes unchanged.

Cost, stated: every module's goldens gained a `reconsider: True` line per derived block, and a
citing module gained one block and one reference in its driver. Every rule now re-runs on every
assemble pass; nothing re-ASKS, because answers are questions' variables and are never
reconsidered. `explain()`'s string dedupe still holds, so a rule that runs twice within one pass
cites once.

**Implementation note (2026-08-17, M2): where a seam export's own `@ref` goes.** A seam lowers
to two `code:` blocks and the citation must not be duplicated across them. It rides on the
**scope** block: the rule fired — it was decided whether it applies — as soon as scope is known,
and on the `NotApplicable` path the requirement block never runs at all, so a citation placed
there would go unrecorded on the very path where the rule most needs to explain itself.

### 8.5 R5 — question order: native backchaining v1; embedded compiled plan M3

**Evidence.** Docassemble's order = block/operand order — a `code:` block is plain `exec`
(`parse.py:3706`, `exec_with_trap` `:10175`), so CPython short-circuit is the pruner
**[E via survey]**; L4's default =
declaration order, deliberately (`QUESTION-ORDERING-SPEC.md`) **[E]**; the info-gain ranker
exists as a pure library with a ~190-line TypeScript port proving the evaluator is trivially
portable (`ts-shared/boolean-analysis/src/robdd.ts`, `decision-query.ts:134`) **[E]**. The
IDE's guided interview uses it; no deployable surface does **[E]** (§6.2 of the survey:
housing wizard never calls query-plan).

**Proposal.** v1: emit operands in L4 source order and let docassemble backchain — this is
already correct (matches L4 short-circuit semantics) and already prunes. M3: `l4 docassemble
--plan` additionally emits `_plan.py` — the serialised `CompiledDecisionQuery` (plain data:
node array + roots + atom→field-path map with UUIDv5 ids) plus a ported `queryDecision`/
`verdictOf` — and a driver variant that seeks `next_unknown` instead of evaluating the goal
directly, giving the interview exact-support pruning and information-gain ordering, with
`TYPICALLY` priors, identical to the IDE's. The port target is Python 3.12, stdlib only.

**Cost.** M3 drags the ladder pass + glue into `jl4/app` (R1 covers the packaging); the plan
and the static blocks must agree on atom identity — the UUIDv5 scheme (`QueryPlan.hs:204`) is
the shared key, also emitted as each block's `id:`. **What would close it:** v1 sign-off now;
M3 gated on a measured demo where plan-driven ordering asks strictly fewer questions than
declaration order on the Reg CF or Housing corpus.

### 8.6 R6 — datatypes; enums ride as constructor-name strings

**Proposal.**
BOOLEAN → per-question `yesno`-style boolean field (radio form, so "None of the above" isn't
implied by an unchecked box); NUMBER → `datatype: number`, with the Rational→float divergence
recorded once as an Advisory note per module (the OpenFisca float32 precedent,
`L4-OPENFISCA.md` §6 **[E]**); STRING → `datatype: text`; DATE → `datatype: date`, comparisons
via docassemble's date objects; `IS ONE OF` with nullary constructors → `datatype: radio` with
`choices:` label/value pairs, value = the constructor's L4 name as a string, `CONSIDER` arms
compiling to `==` string comparisons (OpenFisca's enum-class approach is heavier than needed —
strings keep the YAML human-legible, and the L4 constructor names survive verbatim). Constructor
payloads: refused in v1 by name, M4 via `show if` follow-ups. A `@desc docassemble …` override
tag is reserved for per-field datatype/UI refinement (e.g. `currency`, `dropdown`) without new
grammar, per the `descKeyword` convention **[E]**.

Three server-side coercion facts bound this ruling (all **[E via survey]**, in
`docassemble_webapp/.../interview/views.py:1334-1470`): `currency` coerces through `float()` —
never emit it for exact-decimal money semantics; an _empty_ integer submits as `0` and an empty
number as `0.0`, never `None`; an empty date submits as `''`. Choice keys are parsed into
`TextObject`s (`parse.py:7661-7713`) and **Mako-rendered at assemble time**
(`parse.py:6213/6230`, `item['key'].text(user_dict)`); the value the browser posts — and the
interview stores — is the _rendered_ key. (A 2026-08-16 correction: this spec originally said
choice keys "arrive as the verbatim strings written", reading the parse-time site only; the
render site governs the stored value. Consequence: `escapeL4`-escaped choice values and the
raw-constructor-name `==` comparisons in emitted code agree by construction, because every
escape renders back to the verbatim text — probed end-to-end with a `${`-bearing constructor
name, whose rendered choice value came back as the raw name and drove the right `CONSIDER`
arm.) A choice list whose keys' _original texts_ are all YAML booleans is silently retyped
boolean (`parse.py:7725-7756`, testing `original_text`) — emit type-homogeneous string
choices. And a `default:` without `datatype:` infers the field's type from the default's
Python type (`parse.py:4107-4108`) — always emit both together; `default:` values are
`TextObject`s too (`parse.py:4096-4098`), so the same escape-then-render round-trip keeps
them equal to the rendered choice values.

**What would close it:** the enum golden plus an R10 run where a `CONSIDER` over a 3-way enum
asks one radio question and takes the right arm.

**M4 addendum, 2026-08-17 (RED phase): what "payloads via `show if`" does and does not reach.**
A census of the whole `.l4` corpus found 134 `IS ONE OF` declarations carrying 104 payload
constructors, arity 1 dominating (77 single-field), with 56 SCALAR payload fields (32 `NUMBER`,
24 `STRING`) against 31 non-scalar (records or enums), and zero `BOOLEAN` and zero `DATE`
payloads. Most payload enums in the corpus are deontic action types (`Action`,
`Contract Action`, `Loan Action`, …) which are Fidelity-Blocked as `DA-DEONTIC` and can never
reach an interview at all. The real non-deontic targets are two idioms: the ESCAPE HATCH
(`other purpose HAS the description IS A STRING`, `Suspended HAS the reason IS A STRING`) and
SUM-OF-RECORDS (`Legal Entity`: `Individual HAS the person IS A Person` |
`Corporation HAS the company IS A Company`).

`show if` serves the SCALAR case exactly — one extra field per payload, gated on the radio — and
`payload-enum.l4` is that case. It does **not** cleanly serve sum-of-records, because
`objects:` instantiates unconditionally (`DAObjectsBlock` is a flat list of (variable, class)
pairs, `IR.hs`/`Emit.hs`), so every constructor's record sub-tree would be instantiated and only
the shown branch asked. **That is left OPEN, and deliberately not ruled here**: it is a design
decision, not a mechanical extension of the scalar case, and the M4 corpus does not force it.
The RED phase's `payload-enum.l4` carries only scalar payloads, so a green M4 that refuses
sum-of-records payloads BY NAME satisfies these tests — and that refusal, if taken, has to name
the record, not recite a list.

**Implementation note, 2026-08-17 (M4 GREEN): how payloads landed, and one thing that had to
change with them.** The enum still rides as ONE radio over constructor names, payload-bearing
constructors among the choices, exactly as the nullary case does — the payload is not a
different question, it is an EXTRA one. Each payload FIELD becomes its own question at the
sibling attribute (`d.the_outcome`'s payload lands at `d.the_number_of_conditions`, so a fixture
or an API caller can name it without knowing which constructor it belongs to), carrying
`show if:` with a `code:` sub-key testing the radio. It must be its own block: a `show if`
reading a variable that a field in the SAME question defines is a fatal `DASourceError: Infinite
loop` (probed).

`CONSIDER` arms bind payload patterns to those variables. **What had to change with them:** an
EXHAUSTIVE `CONSIDER` over an enum now compiles without an `OTHERWISE`, taking its last arm as
the if/elif chain's `else`. M1 required an `OTHERWISE` unconditionally, which is right when the
match is partial and wrong when it is total — `payload-enum.l4` has no `OTHERWISE` because every
constructor is covered and there is nothing left for one to mean. A non-exhaustive `CONSIDER`
without an `OTHERWISE` is still refused, and now says which of the two conditions it failed.

Refused BY NAME, each naming what it refuses: a sum-of-records payload (naming the record,
per the addendum above), a `LIST OF` payload, a `MAYBE` payload, and the CONSTRUCTION of a
payload constructor as a value — M4 asks a payload constructor as an INPUT; producing one is a
different thing and is still out.

**`LIST OF <record>` → a gathered `DAList` — ANSWERED 2026-08-17 (M4).** R6 is the ruling that
owns "how does a type get asked", so the list decisions are recorded here.

The list becomes `DAList('<path>', object_type=DAObject)` plus a question per element attribute
written over docassemble's iterator (`<list>[i].<attr>`), and `all`/`any` over it lower to a
Python GENERATOR — `all(<pred> for _t in h.tenants)`, never `all([...])`. Four shape decisions,
each measured against 1.10.7 rather than assumed:

1. `object_type` is REQUIRED: a `DAList` without one fails on the first element access.
2. Both control questions are emitted (`there_are_any` and `there_is_another`); dropping either
   raises `DAErrorMissingVariable`. The `ask_number:` + `target_number` shape works too and
   costs one question instead of 1+N, but it needs the count known in advance.
3. `there_are_any` is NOT preset. Presetting it makes the EMPTY list unreachable, and an empty
   list is an answer — in `tenant-list.l4` it is also a real drafting bug in the rule (`all` over
   nothing is vacuously TRUE), which the zero-element `#EVAL` pins so the gather cannot paper
   over it.
4. `complete_attribute` is NOT set — see §10's correction 1. It orders the gather; it does not
   prune it; and setting it would force every element's named attribute to be asked, which is
   precisely the per-element short-circuit this backend exists to preserve.

The generator is load-bearing for the same reason: `all` stops at the first false element, so a
household whose first tenant is under age is never asked whether that tenant signed, and is
never asked anything about the second tenant at all (driven headless, `tenant-list` case 2).
`complete_elements()` is never reached for — it iterates `self.elements` with no
`_trigger_gather` (`util.py:3256-3274`) and returns EMPTY on an ungathered list, a silent zero.

The predicate may be a lambda written out at the call site OR the NAME of a one-parameter
decision (`any \`the purpose is a charitable purpose\` (entity's purposes)`), which is how the
corpus actually writes it; the eta-reduced form inlines the same way, with the generator variable
standing in for the argument. Nested quantifiers get distinct generator variables: Python scopes
one to its own comprehension, so two binders sanitising onto one name would make the outer
element unreachable from the inner body.

Refused by name: `LIST OF <scalar>` (a different DAList shape, gathering values rather than
objects), a record or a list INSIDE a gathered element, and a computed list value (`LIST`
literals and `FOLLOWED BY` cons) — M4 gathers a list INPUT; it does not produce list values.

**Measured against the two corpus files that motivated this, 2026-08-17.**
`jl4/examples/legal/charities-cleanroom/charity-test.l4` — 700 lines of the Jersey charities
encoding, whose `Entity.purposes` is a `LIST OF Purpose` — **now compiles**, and a CLI test pins
it, because one `LIST OF` field anywhere in a reachable record used to refuse the whole module
regardless of whether the goal read it. `jl4/examples/legal/regcf/denovo/regcf-denovo.l4` still
does not, and its blocker is not lists: it is `RULES EFFECTIVE DATE`, the temporal rule-version
axis, which no milestone of this backend has claimed.

### 8.7 R7 — `TYPICALLY` → `default:`, Advisory

**Evidence.** `TYPICALLY` is metadata today: parsed, schema'd, planner-prior'd, evaluator-inert
(§3) **[E]**. A docassemble `default:` prefills the widget; the user still submits the screen,
so the value that enters computation is a user-confirmed answer, not a silent presumption —
weaker divergence than it first appears, but a divergence: L4's evaluator would have _asked_.

**Proposal.** Emit `default:`; one Advisory note per module listing the prefilled fields. When
L4 grows presumptive evaluation (`PEVAL`), revisit whether defaults should instead become M3
plan priors only. **What would close it:** sign-off; it is reversible by flag later.

### 8.8 R8 — `MAYBE` erased to optionality

**Evidence.** Both shipped schema consumers erase `MAYBE OF T` to `T` + not-required
(`FunctionSchema.hs:147-148`, `Export.hs:258`) **[E]**; docassemble optionality is
per-datatype-shaped — see the R6 coercion facts (`views.py:1334-1470`) **[E via survey]**.

**Proposal, revised against the coercion facts in R6.** Blanket erasure is unsound for
numerics and dates: an unanswered number submits as `0`/`0.0` and an unanswered date as `''`
(`views.py:1397-1398,1413-1414,1374` **[E via survey]**; **cite repaired 2026-08-17** — the
number coercion is at 1413-1414, of which 1412 is the comma strip, and the integer coercion at
1397-1398. R6's stated range `1334-1470` also MISSES a second coercion site at
`views.py:1581-1587`), so "absent" is indistinguishable from a real
answer. v1 therefore splits by type: `MAYBE BOOLEAN` → `yesnomaybe` (three-state; `None` _is_
`NOTHING`, exact, no loss); `MAYBE STRING` → `required: False` with `''` read as `NOTHING`
(Advisory note — a deliberately empty answer is conflated); `MAYBE NUMBER`/`MAYBE DATE` →
refused by name in v1, pending an M4 paired is-known question design. `MAYBE`-consuming
expressions lower only where the source pattern-matches on presence; else refused by name.
**What would close it:** goldens for the boolean and string cases exercising present and
absent paths under R10, and one not-ok fixture for `MAYBE NUMBER`.

**Repair note (2026-08-16 review pass).** The presence match accepts a `JUST` payload pattern
only when it is a _binder_. Post-typecheck a binder is always `PatVar` (the scope checker
rewrites out-of-scope nullary `PatApp`s to `PatVar`, `TypeCheck.hs` `inferPattern`), so a
nullary `PatApp` payload can only be a genuine constructor pattern — `WHEN JUST TRUE` — which
is a match on the payload _value_ that presence erasure cannot express. M1 as first landed
matched `PatApp _ v []` as if it were a binder, silently degrading `WHEN JUST TRUE` to a mere
presence test (`is None`), reporting TRUE for `JUST FALSE`. Refused by name at M1; ruled IN at
M4 (immediately below), and `not-ok/just-payload-pattern.l4` accordingly retired into
`maybe-scalars.l4`, where the same shape is now a supported case.

**Scope ruling, ANSWERED 2026-08-17 (M4). A match on a `MAYBE`'s payload VALUE — `WHEN JUST
TRUE`, `WHEN JUST FALSE`, `WHEN JUST 0` — is IN M4, under R8.** §10's M4 bullet named neither it
nor its opposite: it lists "payload constructors via `show if`" and "`MAYBE NUMBER`/`DATE` via
paired is-known questions", and a payload-value match is adjacent to both and named by neither.
The milestone had to rule rather than drift.

_Why in._ Three reasons, in increasing weight. (i) It is nearly free at both ends of the M4
work: under the shipped `MAYBE BOOLEAN` representation the interview already stores exactly
`True`/`False`/`None` (`datatype: yesnomaybe`, `expected/defaults.yml:26`) and the emitter
already writes `is None`, so the value match is one more comparison; and under the paired
is-known design it falls out as `known and value == v`. (ii) Refusing it while shipping the
representation that makes it trivial would leave the tool refusing something it can plainly do,
which is a worse diagnostic than refusing something it cannot. (iii) It is exactly the case that
caught M1's real defect — the pre-repair emitter answered `JUST FALSE` as TRUE — so keeping it
out of the corpus would remove the regression test for the one M1 bug that changed an answer.

_What that costs._ `WHEN JUST <value>` must NOT compile to a presence test. The pinning case is
`maybe-scalars.l4` #EVAL 6 against #EVAL 7: the declaration positively disclaimed (`JUST FALSE`,
referable) against the declaration never answered (`NOTHING`, not referable). A presence
lowering answers both TRUE.

_What is still out._ `MAYBE <enum>` and `MAYBE <record>`, refused by name and pinned by
`not-ok/maybe-enum.l4`. The paired is-known design does not reach them: the value question for an
enum is itself a radio, so its absent path is not the widget's empty submission but a fourth
choice, and a record explodes into several questions all of which the absence would have to gate.
That fixture also guards the DIAGNOSTIC: M1's catch-all recites "v1: MAYBE BOOLEAN and MAYBE
STRING only", which becomes a false claim in user-facing prose the moment NUMBER and DATE land,
so the refusal is required to name the type it is refusing instead.

**Implementation note, 2026-08-17 (M4 GREEN).** Both halves landed as ruled.

_The pair._ One `MAYBE NUMBER`/`MAYBE DATE` field becomes two questions: `<var>_known`
(`yesnoradio`) and `<var>` itself, carrying `show if: {code: <var>_known}`. The flag is emitted
FIRST so a backchaining interview asks "is there an answer?" before "what is it?", and the guard
is what makes absence absence: on the absent path the value variable is never defined at all —
not `0.0`, not `''` — which the harness asserts directly (`undefined_after`), and a second
consumer that reached for the value would raise rather than receive a fabricated zero. A
`CONSIDER` over such a field tests the FLAG (`if (not c.declared_income_known):`), so the value
is not read on the path where it does not exist.

_The value match._ `WHEN JUST FALSE` compiles to `(c.declaration_confirmed is False)` — IDENTITY,
not equality, and this matters twice: `None == False` is False in Python (so equality would
happen to work for `yesnomaybe`) but `0 == False` is True (so equality is wrong the moment a
numeric zero can reach the comparison). For a paired `MAYBE NUMBER`/`DATE` the flag is consulted
first: `(known and (value == v))`. The pinning pair passes: `maybe-scalars.l4` #EVAL 6
(`JUST FALSE`, referable) and #EVAL 7 (`NOTHING`, not referable) now disagree in the interview
exactly as they disagree in L4.

The M1 two-arm shape (`WHEN JUST x` + `WHEN NOTHING`) is emitted byte for byte as before —
absence tested first, presence as the `else` — so `defaults.yml`'s golden did not move on this
account. The general arm chain is used only where the M1 shape does not fit.

_Still refused, each naming its own type:_ `MAYBE <enum>` and `MAYBE <record>` (pinned by
`not-ok/maybe-enum.l4`), `MAYBE` of a `LIST OF`, `MAYBE` of a `MAYBE`, and a `MAYBE` payload
inside a constructor.

### 8.9 R9 — emission hygiene (the silent-YAML defence)

Bundled because they are all "docassemble will not tell you" facts, each verified at the
cited line:

1. **Mako escaping.** Every L4-derived string (names, `@desc`, `@ref`) passes through one
   escape function neutralising `${`, `%` at line start, and YAML-significant leaders.
2. **Explicit `sets:`** on code blocks whose definitions docassemble's AST scan might misread;
   never rely on inference for generated code.
3. **`depends on:`** on every derived block (stale-value trap, §2).
4. **`id:`** on every block, deterministic from the sanitised variable name in v1 — the
   variable name rides into the id _verbatim_ (dots included; docassemble ids are free-form
   strings), so distinct variables can never collide on id — switching to the UUIDv5 atom
   identity in M3 so ids are stable across recompiles _and_ joinable to the plan. One
   documented exception (2026-08-16, proven by the round-trip harness): a `metadata:` block
   admits ONLY `metadata` and `comment` keys — any other key, `id:` included, is a hard
   `DASourceError` ("A metadata directive cannot be mixed with other directives",
   `parse.py:2748-2751`) — so the metadata block alone carries no id. Objects and features
   blocks do.
5. **Self-validation:** Emit only from a fixed whitelist of block keys and field modifiers,
   vendored as a table in `Emit.hs` with the docassemble version it was read from; a golden
   test asserts the emitter's key vocabulary is a subset of the vendored list. No runtime
   dependency on the docassemble source tree (the 1.2 rule: local evidence, never a build dep).
6. **Idempotent drivers; never wrap exceptions** (§2).
7. **Never an unindented `---` in generated prose.** Interview files are split into blocks by a
   _regex on whole lines_ (`parse.py:138`, applied `:8330`) before YAML parsing — a bare `---`
   inside a `subquestion: |` scalar silently cuts the interview in half. Indent every generated
   prose line at least one space; tabs are rewritten to spaces and a trailing `...` line is
   stripped (`:8332-8333`).
8. **Respect the parser's few hard errors**: exactly one directive per `question:` block and no
   directive without `question:` (`parse.py:1938-1944`); `mandatory:` and `initial:` are
   mutually exclusive and `mandatory:` is legal only on question/code/objects/attachment/data
   blocks (`:2366-2371`). Top-level keys are lower-cased on entry (`:1871-1873`) — emit
   lower-case only.
9. **Generator forms only** for emitted `any`/`all` (§2): `all(...)` short-circuits and prunes;
   `all([...])` eagerly demands every variable. List comprehensions and f-strings are likewise
   eager — never route a lazily-needed variable through them.
10. **Emit `features: loop limit` / `recursion limit`** scaled to the module when the emitted
    graph could plausibly approach the 500 defaults (`parse.py:7942-7943`).

**What would close it:** review of the whitelist against the pinned docassemble version in the
R10 harness, plus one not-ok fixture per hygiene rule where feasible.

**Implementation note (2026-08-16, M1; corrected same day by the review pass).** Mechanism
facts probed the hard way against the vendored `docassemble_mako` at the 1.10.7 pin:
**backslash is not a Mako escape** — `\${ x }` still evaluates `x` (and renders a stray `\`).
And the governing invariant, which M1's first escape missed: **docassemble only Mako-compiles
a string when `match_mako` fires** (`parse.py:135`: `<%|\${|% if|% for|% while|##`), so an
escape sequence is only an escape when the string gets compiled — every escape must therefore
be _self-triggering_ and render back to exactly the original text. The original `%` → `%%`
doubling violated this: `%%` renders as `%` only when something _else_ in the string triggers
compilation, and otherwise reaches the user verbatim as `%%` (the shipped `defaults.yml` case
rendered correctly only because its `@desc` also contains `${`). Likewise unescaped `<%` was
worse than a prose bug: an unclosed `<%` in any `@desc` fails the _whole interview_ at parse
time (`SyntaxException`), and a closed `<%x%>` span is silently deleted from the prose.
`escapeL4` now rewrites every Mako-significant span to the Mako expression that prints it —
`${` → `${'${'}`, `<%` → `${'<%'}`, `</%` → `${'</%'}`, line-leading `[ \t]*%` → `${'%'}`
(the vendored control-line regex admits leading blanks), line-leading `##` → `${'##'}` (a
compiled line-leading `##` is a Mako comment and the line would vanish) — each of which
contains `${` and so triggers compilation of any string it appears in; a bare `%>` with no
opening tag renders as plain text and needs no escape. All probed against the vendored
`docassemble_mako`, and pinned by the `defaults.l4` golden + round-trip.

**Implementation note (2026-08-17, M2): three additions to the hygiene rules, one caveat.**

1. **The emitter's declared vocabulary gains `modules` and `auto terms`** (R9.5). Both were
   already in the vendored `daRecognisedKeys` whitelist, so `emitterVocabularyViolations` would
   have kept returning `[]` while silently ceasing to describe what the emitter writes; a test
   now asserts both are declared, not merely permitted.

   **Corrected by the review pass (2026-08-17): the vocabulary is now two lists, not one.**
   `emitterKeyVocabulary` mixed top-level block keys with per-field modifiers and checked the whole
   thing against `daRecognisedKeys` — which is `parse.py:1947`, the whitelist docassemble applies to
   **block keys only**: `parse.py:1946-1948` is `if self.interview.debug: for key in data: … "Ignoring
unknown dictionary key"`, an iteration over the block dict that never reaches `data['fields'][i]`.
   The list is neither sound nor complete as a modifier oracle — it contains `mandatory` and
   `subquestion`, which as field modifiers raise `DASourceError: Syntax error: field label
'mandatory' overwrites previous label` (measured against 1.10.7), and it lacks real modifiers
   (`show if`, `note`, `min`, `max`, `maxlength`, `address autocomplete`). Docassemble has **no**
   field-modifier whitelist to vendor (`grep -n 'Ignoring unknown' parse.py` ⇒ one hit, the block-key
   line), so `emitterFieldModifiers` is a declaration rather than a checked subset, and
   `emitterVocabularyViolations` now covers `emitterBlockKeys` alone. What actually guards the
   modifiers is stronger and already runs on every artifact: the emitter always writes the bare
   `"LABEL": var` pair first, so any stray key hits `parse.py:4318-4320`'s
   `if 'label' in field_info: raise DASourceError` — a loud parse-time failure both the byte goldens
   and the R10 harness hit immediately. The old comment's claim that an unknown modifier is
   "silently turned into the field's label" was false for the shape this emitter writes, and is gone.

2. **`id:` is legal on both new blocks, and both carry one** (R9.4). The `metadata:` exception
   is metadata-specific: `parse.py:2748-2751` rejects a foreign key only inside the `metadata`
   branch, while `id` is handled generically at `:2555-2561`. Proven by construction — the R10
   harness parses the emitted interview, and an illegal key is a hard `DASourceError`.
3. **Citations are escaped by _position_, not by one rule.** A citation inside a `code:` block is
   a Python string literal and gets Python escaping, because `code:` is compiled and exec'd
   (`parse.py:3706`) and never Mako-rendered — so the deliberately hostile third citation in
   `citations.l4`, which begins with `%` and carries a literal `${ … }`, needs no Mako escape
   there. On the verdict screen it is not in the text at all: it is _interpolated at render time_
   through `${ citation }` inside a `% for` over `logic_explanation()`, and Mako does not re-read
   its own output. That is why the round-trip harness asserts the escaping claim on the
   **rendered** screen — an assertion on the emitted YAML cannot tell "escaped" from
   "interpolated later".

   The `auto terms:` glossary is the one place a `@desc` still goes through `escapeL4`: both
   halves of every entry are handed to a `TextObject` at parse time (the term at `parse.py:2906`,
   the definition at `:2907`), so an unclosed `<%` would fail the whole interview before any
   question is asked. Caveat, stated because it is a real infidelity: docassemble stores the
   **raw** YAML value as the definition (`parse.py:2908`) and shows it in a tooltip without Mako,
   so a hostile `@desc` reaches that tooltip in its escaped spelling (`${'${'}` rather than `${`).
   No corpus `@desc` is affected today; the alternative is a parse-time crash.

4. **An `auto terms:` key is a regular expression, not text — two shapes of L4 name are therefore
   dropped, with a fidelity note each** (review pass, 2026-08-17). Docassemble interpolates the key
   straight into a pattern with `%`-formatting and **no `re.escape`** —
   `re.compile(r"(?i){?\b(%s)\b}?" % re.sub(r'\s', r'\\s+', lower_term))`, `parse.py:2908` at
   `1b6678384`; `re.escape` appears nowhere in that file — and the compiled pattern is applied to
   prose at `filter/html.py:552`.

   - A metacharacter in the term is therefore live syntax. An unbalanced `(` raises `re.error`
     while the `Interview` is being constructed, so the emitted artifact **cannot be loaded at
     all**, while `l4 check` says "Check succeeded", `l4 docassemble` exits 0 and the report said
     "(nothing lost)" (measured: `` `s 12(1` `` ⇒ `LOAD FAILED: missing ), unterminated subpattern`)
     **[E]**. A _balanced_ `(…)` compiles to a capture group, so the pattern no longer matches the
     term that named it: the entry is dead and the phrase it does match occurs nowhere. Statutory
     names are exactly this shape (`a British citizen by virtue of subsection (1) or (2)`).
   - Escaping the key is **not** the repair, and this was checked before the drop was chosen:
     docassemble stores the key verbatim as the dictionary key and looks the definition back up by
     the **matched** text (`add_terms`, `filter/html.py:686-703`), so an escaped key renders the
     literal `[[term]]` marker into the prose instead of a tooltip — worse than a dead entry.

   **M4 addendum, 2026-08-17: the vocabulary is now THREE lists.** Attachment sub-keys are read
   by `process_attachment` (`parse.py:4914-5230` at `1b6678384`), a third place entirely, and
   `daRecognisedKeys` is the wrong oracle for them in both directions: `name`, `filename`,
   `docx template file` and `valid formats` are not block keys at all, while `variable name` and
   `content` ARE block keys meaning something else at block level. So `emitterAttachmentKeys` is a
   declaration like `emitterFieldModifiers`, kept OUT of `emitterKeyVocabulary` (which stays
   exactly "block keys plus field modifiers", the R9.5 split), and checked by a test in both
   directions: every declared key is one `process_attachment` reads, and every sub-key the emitter
   actually writes is declared. The failure mode it guards is the same one the block-key list
   guards — an unrecognised attachment sub-key is ignored in silence.

   `emitterBlockKeys` gains `attachment`, `reconsider` and `review`; `emitterFieldModifiers`
   gains `show if` and `note`. All three block keys are in the vendored whitelist.

   So `partitionRegexSafe` drops such an entry and `glossNotes` raises `DA-GLOSS-REGEX`. The
   companion note `DA-GLOSS-COLLIDE` covers the other drop: `dedupOnTerm` folds keys the way
   docassemble does (`re.sub(r'\s+', ' ', term.lower())`, `parse.py:2905`) and keeps the first
   spelling, which is unavoidable — one of the two must go in either ordering, and the compiled
   pattern is `IGNORECASE` anyway — but what the loser costs is its **whole definition**, not merely
   its spelling, and that was reported as `(nothing lost)`. Both are `Lossy` on the §5 axis: the
   interview is emitted and decides the same way, but a `@desc` the source wrote is gone from the
   artifact. Fixture: `jl4/tests-cli/fixtures/docassemble-glossary-losses.l4`.

**Known cosmetic consequence — measured 2026-08-17, and it is not the one this paragraph used to
describe.** The earlier text claimed that "an emitted question's label IS the L4 term name, so a
glossary keyed on that name will auto-link a question's own label to its own definition". That
cannot happen. Glossary keys come only from `DECLARE`d type names and named definitions;
questions are emitted only for record fields and `GIVEN`/`ASSUME` parameters; and `collectGlossary`
(`Lower.hs`) excludes exactly those, with its own comment saying why ("their `@desc` already lands
on the question that asks them, as `help:`"). The two sets are disjoint by construction. Measured
by applying docassemble's own compiled regexes (`interview.autoterms[lang][term]['re']`, built at
`parse.py:2908`) to every question block of `expected/citations.yml`: **no `q_*` block matches any
glossary term** **[E]**. The equivocation was on "name" — the label is an L4 name, just a _field_
name, and the glossary is not keyed on field names.

What the same measurement _did_ find is linking on the **verdict screen**: four matches, all of the
term `offering` (from `DECLARE Offering`), two per screen — the screen title (`offering exempt:
Holds` / `… Fails`) and the goal's `@desc` subquestion ("Whether this offering qualifies…")
**[E]**. Only the first of each pair is a mis-link: there `offering` is part of the decision's
_name_, so a reader hovering the verdict title gets the record type's definition for a word that
was not referring to it. In the subquestion, "this offering" really does mean the `Offering`, and
the tooltip is right. Still a display nuisance and not a semantic one — but a different one, in a
different place, and a later reader is no longer sent hunting for a bug that cannot occur.

### 8.10 R10 — validation harness: headless `docassemble.base`, proven by probe, never a dependency

**Evidence — executed, this session.** `docassemble_base` from the checkout installs clean into
a plain `uv venv --python 3.12`; with a ~60-line bootstrap, a three-block interview (yesno
question, `code:` block, mandatory Mako verdict screen) **parsed, backchained to the right
question, accepted an answer, and rendered the computed verdict** entirely in-process
(Appendix B) **[E]**. Altitude (b), `TestContext`, is _not_ venv-viable: it imports the full
Flask webapp (§2) **[E]**. OpenFisca's posture carries over **[E]**: goldens are
regression-only; the round-trip script is run by hand in a documented venv, never referenced by
CI (`jl4/examples/openfisca/roundtrip_check.py:1-5`; no workflow hit).

The bootstrap's five non-obvious ingredients, each found the hard way (Appendix B has the
runnable probe):

1. stub `pyzbar` before importing `docassemble.base.util` (or `brew install zbar`);
2. `config.load(filename=…)` against a two-line local `config.yml` (the default path is
   `/usr/share/docassemble/...` and its absence is fatal); first load fetches nltk corpora over
   the network, cached thereafter;
3. register a `HeadlessPlugin` of ~13 `pluggy` hookimpls (`get_configuration`,
   `get_default_language/dialect/locale/voice/timezone/country`, `get_debug_status`,
   `get_hostname`, `get_main_page_parts`, table classes, `url_finder`, `absolute_filename`) —
   the 1.10.0 seam that replaces the old server monkey-patching;
4. run inside `global_context(empty_globals())` (contextvar thread state);
5. build `InterviewStatus(current_info=…)` where `current_info` **omits the `action` key
   entirely** — `process_action` tests `'action' not in current_info`
   (`functions.py:3540`) **[E]**, so `action: None` force-asks a `None` variable and crashes
   assemble; `user` needs `session_uid` and `device_id`.

**Proposal.** `jl4/examples/docassemble/roundtrip_check.py` is the probe grown up: emit → parse
→ loop (read `status.question`, write the fixture's answer for that variable into `user_dict`,
re-assemble) → assert the verdict screen equals L4's `#EVAL` oracle. Pinned
(`docassemble.base==1.10.*`), documented in the example README, absent from CI and from
build-depends, per the topology rule that external checkouts are local evidence only. Altitude
(c) (`dainstall --playground` + `/api/session/*`) is the demo recipe, not the test gate.
Refinements from the survey: `config.load` is skippable entirely — the `get_configuration`
hookimpl can serve the dict directly, parameterised `{'debug': True}` in the harness (the
seeking trace only records under debug) and `False` in production-shaped runs; never touch
`interview_cache` (its `get_index` hits `get_server_redis` unconditionally); question text is
rendered by the vendored `docassemble_mako`, not upstream Mako; and
`docassemble_demo/.../random_test.py` is prior art for walking a question's fields and
synthesising answers by datatype.

**What would close it:** rodents round-trip green: emit → load → answer per fixture → verdict
equals `#EVAL`. The probe closes the _feasibility_ half already; what remains is running it
against emitted rather than hand-written YAML.

**Implementation note (2026-08-17, M4): three things the harness had to learn, and one it had
been getting wrong since M1.**

1. **`user_dict_context` is entered around every `assemble`** (added by the RED phase). Only
   `docassemble_webapp` enters it; without it `get_current_user_dict()` is `None` and
   `functions.py:4232-4234` makes `defined()`, `value()` and `showifdef()` return False for
   EVERY variable, including defined ones. Any review-block assertion would have passed or failed
   for the wrong reason. All seven M1/M2 examples re-ran green after the change.
2. **A `D("YYYY-MM-DD")` fixture is written through `as_datetime()`**, reproducing what
   `interview/views.py:1372` stores, because a plain string compared against a `DADateTime`
   raises `TypeError` — a failure with nothing to do with the lowering.
3. **The ITERATOR is resolved before a fixture is matched** (M4 GREEN). A question over a list
   element is written across docassemble's iterator (`h.tenants[i].age`) and that is the spelling
   `field.saveas` carries for EVERY element; the concrete index lives in the `user_dict`, as `i`,
   at the moment the question is asked. So the raw saveas cannot tell element 0 from element 1,
   and the per-element pruning claim — the one the whole `tenant-list` fixture table is indexed
   for — could not be tested from it. The harness now calls docassemble's own
   `substitute_vars_from_user_dict` (`parse.py:9921-9927`), which is the function docassemble
   uses to name an attachment variable inside a generic block (`parse.py:7064`), so the harness
   reports the variable docassemble would report rather than re-deriving the substitution.

### 8.11 R11 — artifact shape: bare interview YAML v1, installable package M2

**Evidence.** Every existing backend's golden contract is one deterministic text artifact
**[E]** (`expectGolden`, byte-exact). A real deployment wants the namespaced package
(`docassemble.<pkg>` with `pyproject.toml`/SPDX, `data/questions/`, the generated module,
`data/sources/`) **[E via survey]** (§8.11).

**Proposal.** v1: `l4 docassemble FILE -o interview.yml` emits a single self-contained YAML
(functions module inlined via docassemble's ability to carry code in the interview file, or the
module emitted as a second `-o`-adjacent file when unavoidable — measured during
implementation). M2: `--package DIR` writes the installable tree, embedding the original `.l4`
under `data/sources/` so the encoding travels with its compilation — survival extended to
provenance. Goldens stay on the YAML; the package tree gets a shape test, not byte goldens.

The M2 tree targets the **modern PEP 420 shape**, exemplar `docassemble_demo/pyproject.toml`
**[E via survey]**: `pyproject.toml` only (`name = "docassemble.l4<slug>"`, SPDX license,
`requires-python >= 3.12`, `[tool.setuptools.packages.find] where = ["."]`), `MANIFEST.in`
with `graft docassemble/l4<slug>/data`, **no** `docassemble/__init__.py` (setuptools'
pyproject path defaults to PEP420 namespace finding; only the legacy `setup.py` +
`find_packages()` shape needs the namespace `__init__.py` — and `dacreate` emits an
inconsistent hybrid of the two, so its `setup.py` is not copied). The generated runtime module
is a _sibling_ of `data/`, loaded via `modules: [.l4runtime]` — the leading dot is package-name
concatenation, one level only, and `modules:` does `import *`, which is exactly how a shared
L4 helper library reaches every `code:` block. Every emitted `data/` subdirectory carries at
least one real file (empty directories survive neither git nor zip). Deploy loop: `dainstall
--watch --playground` for iteration (YAML-only redeploys skip the server restart; any `.py`
change forces one); Playground project names must not start with a digit.

**What would close it:** v1 sign-off; M2 gated on the R10 harness existing to consume it.

**Implementation note (2026-08-17, M2): `--package DIR` landed, with six decisions this ruling
did not make.** The tree is exactly the shape proposed above; the harness now drives a real
`--package` tree and agrees with the bare YAML case by case, which closes the gate. What follows
is what implementation had to decide.

1. **`--package` refuses `--output`, by name.** They are two artifact shapes, a directory and a
   file, and `-o` is already overloaded house-wide (FILE in eight verbs, DIR in `l4 trace`), so
   honouring one and silently ignoring the other is the failure mode with no precedent to lean
   on. The refusal happens before the file is read, so neither artifact appears. Message:
   `--package cannot be combined with --output`.
2. **Clobber: regenerate freely, overwrite nothing else.** An existing tree that this command
   wrote is overwritten without ceremony — regenerating in place is the normal workflow — but a
   directory holding anything else is refused with a named diagnostic and nothing is written.
   "A tree this command wrote" is decided by the generator marker on the first line of
   `pyproject.toml`, which nothing else in this repo emits. The reason to refuse at all: a
   docassemble package is a thing people edit and `dainstall --watch`, so silently overwriting a
   hand-written `pyproject.toml` is a data loss no golden can see.

   **Corrected by the review pass (2026-08-17): regeneration now REPLACES rather than accumulates.**
   The known limitation this bullet used to record — "regeneration writes but never deletes, so a
   file left by an earlier layout survives; `rm -rf` the directory when the generated shape itself
   changes" — understated its own blast radius and misnamed its trigger. The trigger is not a
   change of generated shape but **renaming the `.l4`**, which is the designed behaviour of decision
   3 below: the slug follows the source basename, so the whole inner package moves. What survived
   was therefore not "a file" but a complete importable package. `[tool.setuptools.packages.find]
where = ["."]` then found both, and a wheel built from that tree — declaring itself
   `docassemble.l4beta` — shipped `docassemble/l4alpha/{__init__.py,l4runtime.py}`, a namespace the
   distribution does not own and removes on uninstall, with `alpha.l4` absent so the stale
   `l4_source_text()` raises `FileNotFoundError`. Measured end to end with setuptools 83.0.0 **[E]**,
   while the command reported full success and exit 0. `writePackageTree` now calls `prunePrevious`
   once `guardClobber` has established the tree is ours: it removes the `docassemble/` subtree
   (wholly generated, and rewritten in full by this run) and any root-level `*.fidelity.txt`, and
   names on stderr what it replaced. Anything else the user put in their own package directory — a
   README, a LICENSE, a `tests/` — is left alone, because `guardClobber` establishes that we wrote
   this tree, not that we own every file in it. Both halves are pinned by tests.

3. **The package name is `l4<slug>`, `<slug>` lowercase ASCII alphanumerics of the source file's
   own basename.** Both obvious sources are unusable and both were measured: `pkgSource` is a
   percent-encoded URI segment (`2024 Café Rules v2.1.l4` arrives as
   `2024%20Caf%C3%A9%20Rules%20v2.1.l4`) and `pyIdent` keeps non-ASCII letters (`café münze 2024`
   sanitises to `café_münze_2024`). The slug is total (an all-punctuation stem yields `module`)
   and capped at 48 characters. The interview and the embedded source are renamed to
   `<slug>.yml` / `<slug>.l4` for the same reason.

   **Corrected by the review pass (2026-08-17): "the author's spelling survives in the generated
   file headers" was false for three of the five generated files, and is replaced by this list.**
   Run against this ruling's own hostile example, `2024 Café Rules v2.1.l4` **[E]**:

   | where                                             | carries                                           |
   | ------------------------------------------------- | ------------------------------------------------- |
   | `pyproject.toml` header comment and `description` | `2024 Café Rules v2.1.l4` — the author's spelling |
   | `l4runtime.L4_SOURCE_NAME`                        | `2024 Café Rules v2.1.l4` — the author's spelling |
   | the interview's own header comment                | `2024%20Caf%C3%A9%20Rules%20v2.1.l4`              |
   | the interview's `metadata: title:`                | `2024%20Caf%C3%A9%20Rules%20v2.1`                 |
   | `<slug>.fidelity.txt`'s `element` field           | `2024%20Caf%C3%A9%20Rules%20v2.1.l4`              |

   The last three carry `pkgSource`, which is `moduleSource`'s percent-encoded URI segment — the
   very string this bullet calls unusable six lines above. The user-facing interview **title** is
   therefore percent-encoded mojibake for any filename with a space or a non-ASCII character. That
   is M1 behaviour, not M2's (`moduleSource`/`moduleTitleOf` predate `--package`, and no corpus
   file has such a name, so no golden shows it), and decoding it is a change to the bare artifact
   that this review pass deliberately did not make. Recorded here so the sentence above stops
   promising otherwise; percent-decoding `pkgSource`/`pkgTitle` belongs with M4's breadth work.

   One related repair the review pass **did** make: `srcBase` reached the `pyproject.toml` header
   comment unescaped, the one position where it was not. Every other consumer was escaped by
   position (`tomlStr` for `description`, `pyStr` for `L4_SOURCE_NAME`, percent-encoding for the
   interview header), so a POSIX filename containing a newline — `$'a\n[project]\nb.l4'` — broke out
   of the comment and emitted a bare `[project]` table on its own line, leaving a `pyproject.toml`
   no build backend can read while `l4 docassemble --package` reported success and exit 0 **[E]**.
   `tomlComment` maps control characters to spaces, which keeps the comment on one line and still
   shows that something unusual was there.

4. **The fidelity report goes to `<slug>.fidelity.txt` at the package root**, under the same-stem
   convention `-o FILE` already uses, and `MANIFEST.in` `include`s it so it ships. Not inside
   `data/`: `data/sources` holds the encoding, and the report is documentation _of_ the
   compilation, not interview data.
5. **`license = "LicenseRef-UNSPECIFIED"`.** PEP 639 wants an SPDX expression and docassemble has
   required one of Playground packages since 1.8.0, but the package carries the _user's_ rules,
   whose licence this compiler cannot know. A `LicenseRef-` custom identifier is valid SPDX and
   unmistakably a placeholder; the emitted comment says to replace it.
6. **`l4runtime.py` deliberately defines nothing the interview calls.** The bare and packaged
   artifacts must _mean_ the same thing — the harness asserts exactly that, per case — so
   anything the interview needed would have to work bare too. What it carries instead is
   provenance the interview can show about itself (`L4_SOURCE_NAME`, `l4_source_text()`, …) under
   an explicit `__all__`.

   **Corrected by the review pass (2026-08-17): the clause that used to end that sentence — "so
   `modules:`' `import *` cannot collide with an interview variable" — was false, and the collision
   changed the answer.** `__all__` bounds _which_ names the star-import brings in; it does nothing
   to stop an interview variable from **being** one of them, and the import wins. Docassemble execs
   `from <pkg>.l4runtime import *` into the interview dict on every assemble pass
   (`parse.py:8572` at `1b6678384`), so an `@export` spelled `L4 source text` — which `pyIdent`
   lower-cases to `l4_source_text` — had its goal variable overwritten with the imported function
   object, which is truthy: the **packaged** artifact asked no question at all and rendered
   "evaluates TRUE" where the bare artifact and the L4 `#EVAL` oracle both say FALSE, with the
   fidelity report reading "(nothing lost)" **[E]**. That is precisely the invariant this decision
   rests on, and the R10 `--also=` harness exists to assert. `runtimeExports` now lives in
   `L4.Docassemble.IR` so the emitter's `__all__` and the lowerer's reserved-name set cannot drift;
   `pyReserved` takes the entries `pyIdent` can actually produce (the lower-case ones — Python is
   case-sensitive, so no L4 name can land on `L4_SOURCE_NAME`) and suffixes them with `_`. The
   reservation applies to the **bare** artifact too, deliberately: the two shapes must not disagree
   about a variable's name either. Fixture:
   `jl4/tests-cli/fixtures/docassemble-runtime-collision.l4`.

   M3's compiled plan is what fills the module. Correspondingly the `modules:` block is emitted into the
   **packaged** interview only: a bare YAML has no package for `.l4runtime` to resolve against,
   and `from … import *` of a missing module aborts assembly. The list holds exactly one relative
   name — naming `docassemble.base.util` or `docassemble.base.legal` sets `imports_util`
   (`parse.py:2765-2767`) and suppresses the automatic `from docassemble.base.util import *` at
   `:8523`, which would take `explain`, `DAObject` and every other builtin with it.

### 8.12 R12 — the M4 date surface: what lowers, what refuses, and which idiom

**ANSWERED 2026-08-17 (M4 RED phase).** §10's M4 bullet names an idiom ("never
`date_difference().years` … use calendar-exact `.plus()`/`.minus()`") but bounds no surface, and
L4's date surface is far larger than the target's: six libraries (`datetime.l4`, `daydate.l4`,
`date-compat.l4`, `excel-date.l4`, `time.l4`, `timezone.l4`) on top of a `DATE` builtin, with
`Date` five-way overloaded and `Day` three-way. Carrying that is not the job. The job is to lower
what the corpus needs and refuse the rest **by name**.

**What lowers (the minimum the M4 corpus establishes).** A date LITERAL; a date COMPARISON; and
"the same day-and-month, _n_ years later". That is the whole of `statutory-age.l4`, and it is the
whole of what a statutory-age or limitation-period rule needs.

**What is already sound and needed no ruling.** A comparison between two question-supplied dates
works at M1: the webapp coerces every submitted `datatype: date` through `as_datetime()` before
it enters the interview dict (`interview/views.py:1372` at `1b6678384` **[E]**), so both sides
are `DADateTime`. The RED phase's premise that M1's date path was unsound is wrong and is
corrected here; what is true is that **no M1 example exercised DATE at all** — zero `DATE` in
`jl4/examples/docassemble/*.l4` before `statutory-age.l4` and `maybe-scalars.l4` — so the path
had no golden, no harness coverage and no fidelity note.

**The literal is the real gap, and it fails loudly.** `as_datetime('2016-05-16') >= '2015-01-01'`
raises `TypeError` (**executed**). So a naive string literal is a crash, not a wrong answer —
lower risk than feared, but a certainty the moment anyone writes a date literal.

**Which idiom, measured — and §10's answer is wrong.** L4's `Date d m y` is the LENIENT,
ROLLING constructor: `Date 29 2 2022` evaluates to `DATE OF 1, 3, 2022` (**executed**).
`dateutil`'s `relativedelta`, which is what `DADateTime.plus`/`.minus` use, CLAMPS instead.
Swept over every birth date from 1970-01-01 to 2006-12-31, each tested on the L4 majority date
and the day before — 13,514 birth dates, 27,028 comparisons (**executed**):

| Python idiom                       | disagreements with the L4 oracle | where                          |
| ---------------------------------- | -------------------------------- | ------------------------------ |
| `date_difference(…).years >= 18`   | 6,629 (24.5%)                    | on the birthday itself         |
| `born.plus(years=18) <= assessed`  | 9 (0.03%)                        | leap-day births, tested 28 Feb |
| `born <= assessed.minus(years=18)` | **0**                            | —                              |

`date_difference(…).years` is `(delta.days + delta.seconds/86400.0) / 365.2425`
(`dates.py:482` at `1b6678384` **[E]**) — elapsed days over the mean Gregorian year, as a float.
It reports **17.99900** on the applicant's own eighteenth birthday, which is the one day the
question is asked. §10 is right to forbid it.

§10 is **wrong** to offer `.plus()` and `.minus()` as interchangeable. They are not: they differ
on exactly the leap-day births, because `.plus()` clamps 2004-02-29 + 18y to 2022-02-28 while L4
rolls it forward to 2022-03-01. Measured against L4 as the oracle — which is what the R10 harness
compares against, and what the lawyer actually read — the BACKWARD form is the correct one and the
forward form is wrong on 9 of 27,028. A prior recon pass recommended the forward form; it had
assumed the clamping convention as ground truth rather than measuring against L4. **Ruling: emit
the backward form**, `born <= assessed.minus(years=n)`, or any lowering that agrees with L4's
`Date` on leap days; and if the implementer prefers the forward form, the leap-day case in
`statutory-age.l4` (#EVAL 3, L4 answers FALSE) is what must be made to pass, not to be excluded.

**What refuses by name, with a later-milestone marker.** `years after` (fractional years — the
corpus has `n = 7.5` in `ceo-performance-award.l4`), `the week after`, `the date that many years
earlier`, `DATETIME`/`TIME`/`TIMEZONE` and everything in `excel-date.l4`, `time.l4` and
`timezone.l4`. Also refused, and separately: recursive cons-pattern functions over `LIST OF DATE`
(they are gated by the existing recursion refusal, not by anything M4 changes).

**Implementation note, not a ruling.** Recognise the small named entry set plus the builtins
(`DATE_YEAR`/`DATE_MONTH`/`DATE_DAY`, `DATE_SERIAL`, `DATE_FROM_SERIAL`); do NOT try to inline
`daydate.l4`. `Date` has five overloads bottoming out in `DATE_SERIAL`/`DATE_FROM_SERIAL`/
`DATE_FROM_DMY`/`DATEVALUE`/`TODATETIME` plus an `ASSUME` bottom, and `YMD` is a bounds-checked
wrapper whose refusal path is itself an `ASSUME`. Note also that the three constructors have
three different out-of-range behaviours, which a lowering must not silently flatten:
`Date 29 2 2022` rolls to 1 March, `DATE_FROM_DMY 29 2 2022` refuses ("produced an invalid date"),
`YMD 2022 2 29` refuses through its `ASSUME` (**all three executed**).

**What would close it:** `statutory-age.l4` green under the R10 harness on all six cases,
including the two where `date_difference` disagrees and the one where `.plus()` disagrees.

**CLOSED 2026-08-17 (M4 GREEN): all six cases green, and the idiom that carries them.**

The anniversary is emitted as a shift from the FIRST of the month:

```python
a.date_of_birth.minus(days=(a.date_of_birth.day - 1)).plus(years=18).plus(days=(a.date_of_birth.day - 1))
```

This is the ruling's own escape clause — "or any lowering that agrees with L4's `Date` on leap
days" — taken rather than the literal backward form, and the reason is that the backward form is
not a lowering of what the source SAYS. `statutory-age.l4` computes a date (`the eighteenth
birthday`) and then compares it; under R3 that binding is its own `code:` block with its own
name, and rewriting `birthday <= assessed` into `born <= assessed.minus(years=18)` would dissolve
a named rule the lawyer wrote into an inequality it does not appear in. The month-start shift
keeps the block, and is exact for the same reason the backward form is: no year is short of a
first-of-the-month, so no clamp can fire, and adding the day back rolls into the next month
exactly as L4's `Date` rolls. 2004-02-29 + 18y ⇒ 2004-02-01 → 2022-02-01 → **2022-03-01**, which
is L4's answer and not `relativedelta`'s 2022-02-28.

`YMD` literals are bounds-checked at lower time, so `YMD 2023 2 29` is refused with a diagnostic
rather than silently rolled — matching `daydate.l4`'s ASSUME bottom, and keeping the strict and
lenient constructors distinguishable in the target as they are in the source. An all-literal
`Date d m y` IS rolled, here, at compile time.

`DATE_YEAR`/`DATE_MONTH`/`DATE_DAY` lower to `.year`/`.month`/`.day`. Everything else in the six
date libraries refuses by name, and the name is the L4 spelling the author typed (`Day`,
`Date to days`, `years after`, `the week after`, `the date that many years earlier`,
`DATETIME`/`TIME`/`TIMEZONE`, `DATE_SERIAL`, `DATE_FROM_SERIAL`, `DATE_FROM_DMY`, `DATEVALUE`,
`TODAY`). Date recognition is by NAME and is tried only after in-module bindings, so a module
that defines its own `Date` or `all` shadows the builtin surface rather than colliding with it.

`date_difference` and `365.2425` appear nowhere in any emitted interview, and a CLI test asserts
their absence.

## 9. Verification plan

1. **Goldens** (regression only, stated as such): `expectGolden` blocks per example;
   `not-ok/` fixtures for each refusal class (deontic body, payload constructor, `MAYBE`
   pattern beyond R8, name collision, Mako-hostile `@desc`).
2. **Round-trip** (the consistency proof): R10 harness, `#EVAL` as oracle, per-example fixture
   dicts, verdict + numeric equality (float tolerance stated honestly, as the OpenFisca §6
   discipline requires).
3. **Vocabulary check** (the drift alarm): emitted variable inventory equals the lowered atom
   inventory; on a live server, `GET /api/interview_data` equals both.
4. **Pruning/seam transcripts**: scripted sessions demonstrating R2 (unneeded fields never
   asked) and R4 (scope-first, NotApplicable reachable) — these are the claims that make this
   backend worth having, so they are tested as claims, not assumed.
5. **Seeking-trace oracle**: with debug on, `InterviewStatus.get_history()` names which block
   fired for which variable in which order — the harness compares that against the L4
   evaluation trace, catching "right answer via the wrong rule", which answer-comparison alone
   cannot. Attachment blocks get an explicit post-condition check.

   **Correction, 2026-08-17 (M4 RED phase).** The reason this clause used to give — "because a
   failed attachment eval is swallowed into a log line (`parse.py:9523-9526`)" — was mis-cited,
   too broad, and named the wrong hazard.

   The cite is `parse.py:9521-9526` (`try:` at 9521, `eval(missing_var, user_dict)` at 9522,
   `except BaseException as err:` at 9524, `logmessage("Problem with attachments block: "…)` at
   9525, `continue` at 9526); 9523 is a comment. The swallow is real at that site, but no
   realistic defect could be made to take it: a raising body propagates `ZeroDivisionError` and
   an unaskable reference propagates `DAErrorMissingVariable`, on BOTH the question-attached and
   the standalone attachment paths (**executed**).

   The hazard that IS silent is different and worse, and it is not an exception at all: a
   **successful empty render**. The interview completes, the variable is a healthy
   `DAFileCollection`, and the letter is blank. Nothing raises and nothing is logged. So the
   post-condition must assert on the assembled CONTENT (`<var>.html.content` non-empty and
   carrying the expected text), and `variable name:` is mandatory not for tidiness but because
   without it docassemble files the document under `_internal['docvar'][n]`
   (`parse.py:4997-5003`) where there is nothing left to assert about. Pinned by the two
   `notice-letter.l4` harness cases.

   **Green 2026-08-17.** Both cases pass: `notice_letter.html.content` is non-empty and carries
   the tenant's name, the property address and the branch-correct verdict sentence, on the valid
   and the short-notice paths alike — the second existing because a citizen who is told "no" is
   exactly the citizen who needs the document explaining why.

## 10. Sequencing

- **M1 — static core.** IR/Lower/Emit + CLI verb + fidelity + goldens: booleans, numbers,
  strings, dates-as-comparisons, nullary enums, records (nested), `WHERE` survival, seam
  verdict. First examples: `rodents-and-vermin.l4` (annotated copy), one seam example, one enum
  example.
- **M2 — the loop closed. SHIPPED 2026-08-17.** `--package` (PEP 420 shape, R11), `data/sources`
  provenance, R10 harness green on all seven examples from both artifact shapes, `@ref` citations
  via `explain()`/`logic_explanation()` on verdict screens plus `auto terms:` glossary entries
  for L4 defined terms, push recipe (`dainstall`/API) in the README. Deferred out of M2 and named
  where they belong: the `generic object` question layer (§8.2, to M4, measured inert in v1) and
  the embedded plan (M3, `DAPackage.pkgPlan` still `Nothing`).

  **Review pass, same day.** Five adversarial lenses, each finding re-checked by an independent
  skeptic. Repaired: the runtime-module name collision (§8.11 decision 6 — the only defect that
  changed an answer), the two silent glossary losses (§8.9 item 4), the exhaustive `@desc` descent
  and its first real oracle (§3), regeneration replacing rather than accumulating (§8.11 decision
  2), the unescaped `pyproject.toml` comment (§8.11 decision 3), the block-key/field-modifier
  vocabulary split (§8.9 item 1), and, in the tests, the `--package` assertions that checked
  existence without checking content. Corrected as false claims: §8.9's "known cosmetic
  consequence" (the mechanism it named cannot occur), §8.11 decision 3's "the author's spelling
  survives in the generated file headers", §8.4's "session-scoped accumulation is the correct
  behaviour here", §3's `ResolveAnnotation.hs` line cite, two `parse.py` line cites, and the
  README's `pip install docassemble-cli` (the distribution is `docassemblecli`). Narrowed rather
  than fixed, with the boundary recorded in three places: the session-scoped explanation list
  (§8.4). Deliberately not fixed and recorded as an M1 wart: the percent-encoded interview title
  (§8.11 decision 3).

- **M3 — the differentiator.** `--plan`: embedded `CompiledDecisionQuery` + Python port of
  `queryDecision`/`verdictOf`, UUIDv5 `id:`s, info-gain ordering, measured against declaration
  order on a real corpus. Requires the R1 packaging move and the `vizExprToBoolExpr` lift.
- **M4 — breadth. SHIPPED 2026-08-17.** `LIST OF` via
  `DAList` gathering; payload constructors via `show if`; `MAYBE NUMBER`/`DATE` via paired
  is-known questions; date arithmetic (routing every literal through `as_datetime()`; never
  `date_difference().years`, whose mean-Gregorian-year float is unsound for statutory age); a
  `review:` block as a compliance-checklist view; and the document-assembly demo (a verdict
  screen that also assembles the letter, `variable name:` on every attachment) — the capability
  that justifies the backend to the outside world.

  **Three corrections to this bullet, each measured by the RED phase against docassemble
  1.10.7.** They are corrections, not re-scopings: every deliverable above stands.

  1. _`complete_attribute` is not "the per-element pivot"._ It controls gather ORDERING, not
     pruning. With it, gathering is element-major (finish element 0, then ask "another?");
     without it, every `there_is_another` comes first and the attributes follow. Final values are
     identical and per-element short-circuit pruning holds in BOTH (**executed**). Pruning is the
     property worth having and it does not depend on this key. Separately, `object_type` IS
     load-bearing — a `DAList.using(complete_attribute=…)` with no `object_type` fails on the
     first element access — and so is having either both control questions
     (`there_are_any` + `there_is_another`, dropping either raises `DAErrorMissingVariable`) or
     `ask_number: True` + `target_number`, which replaces both with one count question.
  2. _`skip undefined: False` does not make a checklist._ It makes the review block FORCE-ASK
     every undefined variable it lists: with the flag, the row's eval is no longer wrapped in
     try/except (`parse.py:5876-5904` at `1b6678384`), and the probe landed on a field screen for
     the never-asked variable instead of on a review screen (**executed**). The default (flag
     absent) is the opposite failure — an undefined row is SILENTLY DROPPED into a debug log line.
     Neither is a compliance checklist; one interrogates the user about questions the law never
     reached, the other hides them. The recipe that works is `note:` rows carrying
     `showifdef('<var>', '<not asked>')`, which have no `saveas` to evaluate and therefore always
     render, paired with `Edit:` rows gated on `show if: defined('<var>')` (**executed**). M4 is
     accordingly required NOT to emit `skip undefined: False`, and `review-checklist.l4` pins it.
  3. _`.plus()` and `.minus()` are not interchangeable, and `.plus()` is the wrong one._ See R12
     (§8.12) for the measurement: against the L4 oracle, `.plus(years=n)` disagrees on every
     leap-day birth and `.minus(years=n)` on none of 27,028 comparisons.

  One thing this bullet did not say and should: `show if:` must be emitted in its `{code: …}`
  spelling. The `{variable:, is:}` spelling is browser-side JavaScript only
  (`parse.py:3998-4002` sets `show_if_var`/`show_if_val` and no `showif_code`), so the engine
  shows every field and an API or headless drive DEFINES them all — it cannot encode a
  constructor payload at all (**executed**). Only the code form leaves a hidden field genuinely
  undefined (`parse.py:6316-6325` evals `showif_code` and sets `extras['ok'][n] = False` at 6320/6324). And `show if` is FIELD-level only:
  it is not among the 169 block keys at `parse.py:1947`, and an unknown block key is silently
  ignored — `logmessage` only, and only under debug (`parse.py:1945-1948`) — so a block-level
  `show if` does nothing AND says nothing.

  **Two things the RED phase deliberately did NOT rule, ANSWERED 2026-08-17 by the GREEN phase.**

  - _What triggers an attachment: **a sibling `<stem>.letter.md`**._ Nothing in L4 says "assemble
    this letter", and the candidates were a filename convention, a CLI flag, or a
    `@desc docassemble …` tag (the channel R6 reserves). The convention wins on two grounds: a
    flag would make the ARTIFACT depend on how the compiler was invoked, and R11 decision 6
    requires the two artifact shapes to mean the same thing; and a tag would add L4 grammar for a
    view. The template has to exist as a file either way — the `--package` tree ships it under
    `data/templates` — so the convention costs nothing that was not already on disk. Only
    `notice-letter.l4` has one, so no other golden moved. `jl4-core` does no IO (R1), so the CLI
    reads the file and hands it in as a side input (`DASideInputs`), and says on stderr that it
    did.

    The template is embedded INLINE as the attachment's `content:`, not referenced with
    `content file:` — heeding the RED phase's warning, which was right: `content file` resolves
    through `package_template_filename` and raises `DASourceError` at PARSE time when the file is
    absent, which would leave the bare single-file artifact unloadable while the packaged one
    worked. The attachment is its own standalone block carrying `variable name:`, sought when the
    verdict screen renders `${ <var> }`; `valid formats:` is `[html]` only, because there is no
    LibreOffice and a PDF format fails at assemble time. Its sub-keys are a THIRD emitter
    vocabulary (`emitterAttachmentKeys`, §8.9 item 5).

    The template body is the one string the emitter does NOT escape: it is the author's own Mako,
    written to be rendered, and R9.1 exists to stop L4-DERIVED prose being read as Mako. That is
    declared per module as `DA-ATTACH-MAKO` rather than left implicit.

  - _Whether the `review:` block is emitted for every module: **every module**._ Nothing in an L4
    source asks for a checklist, so the alternatives were the same flag-or-grammar pair, and they
    lose for the same reasons. Every interview now carries one, reachable only by firing its event
    and inert otherwise. This rewrote all seven M1/M2 byte goldens, consciously, and they were
    read before being re-blessed.

    Rows are `note:` + `showifdef()` and there is no `skip undefined:` key, per correction 2
    above. Gathered LIST ELEMENTS get no row — their variable carries docassemble's iterator
    (`<list>[i].<attr>`) and there is no element to name until the list is gathered — and that
    omission is declared as `DA-REVIEW-LIST` rather than left silent.

  **What M4 did NOT do, and why it is not a gap in this bullet.** The review block's `Edit:` rows
  and the purpose-built `recompute:`/`invalidate:` row directives (`parse.py:4507`) are not
  emitted: the checklist is a VIEW, and the answer-changing path it exists to make ordinary is
  tested through `undefine()` + re-ask, which is what §8.4's repair was measured against. Emitting
  edit affordances is a UI decision with its own probes owing, and it is not what makes the
  verdict stale.

## 11. Non-goals (v1)

Deontics, temporal pins, ledger effects (Fidelity-declared, §5); the reverse direction;
multi-user/multi-party interviews; docassemble's e-signature, translation, and background-action
machinery; emitting `#EVAL` fixtures into the interview (they are the oracle, not the product);
any LLM integration; any dependency of this repo on the docassemble checkout.

## Appendix A — worked example **[U]**

`jl4/examples/docassemble/rodents-and-vermin.l4` is `jl4/examples/ok/rodentsAndVermin.l4` plus
`@export insurance coverage decision` on the `DECIDE`. Emission sketch (abridged; final shape is
what M1's golden pins):

```yaml
# Generated by `l4 docassemble` from rodents-and-vermin.l4.
# Validated against docassemble 1.10.7 block vocabulary.
---
modules:
  - .rodents_and_vermin
---
objects:
  - i: Inputs
---
generic object: Inputs
question: |
  Loss or Damage.caused by rodents
fields:
  - "Was the loss or damage caused by rodents?": x.loss_or_damage_caused_by_rodents
    datatype: yesnoradio
id: q_loss_or_damage_caused_by_rodents
---
code: |
  # L4: `loss or damage by animals` MEANS ...
  insurance_covered_loss_or_damage_by_animals = (
      i.loss_or_damage_caused_by_rodents
      or i.loss_or_damage_caused_by_insects
      or i.loss_or_damage_caused_by_vermin
      or i.loss_or_damage_caused_by_birds)
depends on:
  - i.loss_or_damage_caused_by_rodents
  - i.loss_or_damage_caused_by_insects
  - i.loss_or_damage_caused_by_vermin
  - i.loss_or_damage_caused_by_birds
sets:
  - insurance_covered_loss_or_damage_by_animals
id: c_insurance_covered_loss_or_damage_by_animals
---
mandatory: True
code: |
  interview_goal = insurance_covered
---
event: final_screen_holds
question: |
  Coverage decision
subquestion: |
  The policy **does not cover** this loss.   # 'insurance covered' = not-covered-if …
```

Each of the five `WHERE` bindings appears as its own `code:` block; the ten stored fields as
ten single-field questions; docassemble asks, at most, the questions Python short-circuit
demands, in L4 source order. The exact YAML — including how the boolean goal presents without a
seam, and whether the module rides inline — is settled by M1's first golden, not by this sketch.

## Appendix B — the headless probe **[E]**

Executed 2026-08-16 against the checkout at `1b6678384` (v1.10.7), in a plain
`uv venv --python 3.12` with only `docassemble_base` (from the checkout path) and its pip
dependencies installed. The runnable script is committed beside this spec at
`specs/todo/docassemble-export/probe_headless.py`; its transcript:

```
config.load: OK
import parse: OK
get_interview: OK, 3 blocks
assemble pass 1: question is yesno -> 'Question_0'
assemble pass 2: question type: deadend
verdict screen text: Verdict / Covered: False
covered = False
```

(The probe answered `caused_by_rodents = True`; the `code:` block computed
`covered = not caused_by_rodents = False`; the Mako `${ covered }` rendered it.)

What it proves: `docassemble.base` 1.10.x, given the ~13-hookimpl `HeadlessPlugin` and a
contextvar scope, runs the complete interview lifecycle in-process — parse
(`InterviewSourceString(content=…, path=…, package=…)` → `Interview(source=…)`), backchain
(`mandatory` screen → `code:` block → `yesno` question), answer (write into `user_dict`,
re-`assemble`), finish (`deadend` screen with Mako-rendered computed value). The five
bootstrap ingredients and their failure modes are itemised in §8.10. This is the R10
round-trip harness in embryo; `roundtrip_check.py` replaces the hand-written YAML with
`l4 docassemble` output and the hand-written answer with `#EVAL` fixture values.
