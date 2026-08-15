# L4 → Docassemble: interview export and transpiler spec

_Status: **design, not yet implemented.** Written 2026-08-16 on branch `mengwong/docassemble-bridge`.
Nothing exists under `jl4-core/src/L4/Docassemble/`; there is no `docassemble` subcommand in
`jl4/app/Main.hs`; the only occurrences of the word "docassemble" anywhere in the tree are two
hyperlinks in `tmp/aswathy-briefing.html:532,640`. What would make the present tense true: an
`L4.Docassemble.{IR,Lower,Emit}` module triple in jl4-core plus a CLI verb in jl4, mirroring the
shipped OpenFisca backend (`jl4-core/src/L4/OpenFisca/`, `jl4/app/L4/Cli/OpenFisca.hs`), emitting
a docassemble interview that a stock docassemble server runs unmodified._

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

| ruling | state        | detail                                                                                   |
| ------ | ------------ | ---------------------------------------------------------------------------------------- |
| R1     | **PROPOSED** | CLI surface: own verb; package placement; plan lives above core, §8.1                    |
| R2     | **PROPOSED** | records → DAObject subclasses, one question per _field_, §8.2                            |
| R3     | **PROPOSED** | survival: every reachable `DECIDE`/`WHERE` binding → one `code:` block, §8.3             |
| R4     | **PROPOSED** | the verdict seam: scope-first driver, six-valued verdict, §8.4                           |
| R5     | **PROPOSED** | question order: native backchaining v1, embedded plan M3, §8.5                           |
| R6     | **PROPOSED** | datatype map; enums as string-valued radios; floats, §8.6                                |
| R7     | **PROPOSED** | `TYPICALLY` → `default:`, Advisory divergence, §8.7                                      |
| R8     | **PROPOSED** | `MAYBE` erased to optionality, as both schema paths do, §8.8                             |
| R9     | **PROPOSED** | emission hygiene: Mako escaping, `sets:`, `id:`, `depends on:`, self-validation, §8.9    |
| R10    | **PROPOSED** | validation harness: headless docassemble.base, proven by probe, never a build dep, §8.10 |
| R11    | **PROPOSED** | artifact shape: bare YAML v1, installable package M2, §8.11                              |

No ruling is ANSWERED yet; all await sign-off. Each states in §8 what evidence exists, what is
proposed, what it costs, and what would close it. (State vocabulary follows the bridge-family
convention set by `CATALA-EXPORT-SPEC.md`; the DMN spec's OPEN/ANSWERED is the same ladder with
PROPOSED as the pre-sign-off rung.)

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
(`pyIdent` `Lower.hs:758-773`, `checkCollisions` `Lower.hs:806-826`), and an emitter that builds
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
   (`docassemble_base/docassemble/base/parse.py`: assembly loop, exception handler, `askfor`,
   variable index) **[R]**. That is L4's `queryDecision` support-set computed lazily at runtime.
   One L4 source therefore becomes a _conversation_, not a form.
2. **Document assembly on the same dependency engine.** `attachment` blocks (DOCX/Jinja2,
   fillable PDF) participate in the same variable-seeking loop **[R]** — a verdict screen that
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
  the exception and `askfor()` finds the defining block, most-specific candidate first **[R]**.
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
- **Version floor.** `requires-python >= 3.12` (`docassemble_base/pyproject.toml:14`) **[E]**;
  playground packages require `pyproject.toml` with a valid SPDX license expression as of
  1.8.0 **[R]** — both bind M2's package emission.

## 3. The L4 export surface consumed

All **[E]**. The selection layer is `L4.Export`:

- `getExportedFunctions :: Module Resolved -> [ExportedFunction]` (`Export.hs:115`); only
  explicit `@export` counts (`Export.hs:120-122`); topmost is promoted to default when none is
  marked (`Export.hs:124-127`).
- `ExportedFunction` carries name, description, params, return type, and the `Decide Resolved`
  itself (`Export.hs:42-49`). `ExportedParam` carries `paramDescription` (falling back from the
  parameter's `@desc` to the _type's_ `@desc` via `buildTypeDescMap`, `Export.hs:213-226` — free
  prose on a record `DECLARE` reaches every question generated from that record),
  `paramRequired = not . isMaybeType` (`Export.hs:201`), and `paramDefault` from `TYPICALLY`.
- Structured `@desc` payloads follow the `descKeyword` convention
  (`L4/OpenFisca/Lower.hs:446-455`): first word is the tag, remainder is payload. This backend
  reserves the tag `docassemble` for per-declaration overrides (§8.6) rather than inventing new
  annotation syntax.
- Post-resolution expressions arrive with infix operators desugared to builtin applications
  (`__PLUS__`, `__AND__`, …; `L4/Desugar.hs:145-147`); `IfThenElse`/`MultiWayIf`/`Consider`/
  `Proj`/`Lit`/`Percent`/`Where`/`LetIn` survive as constructors; a bare variable is a nullary
  `App` (`Syntax.hs:347-348`); booleans arrive as names, not literals (`Lower.hs:328-331`).
- `WHERE` is `Where Anno (Expr n) [LocalDecl n]`, `LocalDecl = LocalDecide … | LocalAssume …`
  (`Syntax.hs:254,449-451`) — every binding is a full `Decide`, possibly with its own `GIVEN`s.
- Record fields: `MkTypedName` 4th field is the `TYPICALLY` default, 5th distinguishes stored
  (`Nothing`) from computed/`MEANS` (`Just expr`) fields (`Syntax.hs:125-134`); stored fields
  become questions, computed fields become `code:` blocks, mirroring `Lower.hs:620`.
- `TYPICALLY` today: lexes and parses (`Lexer.hs:330`, `Parser.hs:654,1221,1230`), reaches
  `FunctionSchema.parameterDefault` (`FunctionSchema.hs:46,242-244`), feeds query-plan priors,
  and is **ignored by the evaluator** (`EvaluateLazy/Machine.hs:3186` binds and drops it). The
  status header of `TYPICALLY-DEFAULTS-SPEC.md` ("BACKED OUT") predates this re-landing as
  metadata and is stale on that point.
- The question-ordering machinery is a pure library, `jl4-query-plan` (deps: base, aeson,
  containers, jl4-core, text): `compileDecisionQuery`/`queryDecision`
  (`BooleanDecisionQuery.hs:369,437`), six-valued `Verdict` (`:210-224`), seam-aware support
  (`supportIdxOf`, `:259-269`), UUIDv5 atom ids and field-path-level asks
  (`QueryPlan.hs:204,38-84`). It sits _above_ jl4-core in the dependency order, which forces the
  placement decision in R1. Its input is the ladder-pass `BoolExpr`, not `Expr Resolved`, and
  the ~30-line glue is currently duplicated in jl4-lsp and jl4-wasm — a third copy is refused;
  see §8.5.

## 4. The mapping, construct by construct

The organising principle, per the commissioning instruction: **as much as possible of an L4
encoding survives, by name and by structure.** An L4 reader and a docassemble reader should
recognise the same program.

| L4 construct                                             | docassemble target                                                                                   | survival                             |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `@export` `DECIDE`/`MEANS` (boolean or numeric goal)     | goal variable defined by a `code:` block; the default function drives the single `mandatory` block   | clean                                |
| `GIVEN p IS A <Record>`                                  | `objects:` instance of a generated `DAObject` subclass                                               | clean, R2                            |
| stored record field                                      | one `question:` block per field (`generic object` style), label = backticked L4 name, help = `@desc` | clean, R2                            |
| computed (`MEANS`) record field                          | `code:` block on the attribute                                                                       | clean                                |
| `WHERE`/`LET` binding, zero-`GIVEN`                      | one namespaced `code:` block each                                                                    | clean, R3                            |
| `WHERE` binding with `GIVEN`s (local function)           | Python function in the generated module, called from `code:` blocks                                  | clean, R3                            |
| non-exported top-level `DECIDE` reachable from an export | `code:` block (no `@export` needed for helpers, unlike OpenFisca's cross-entity contract)            | clean, R3                            |
| `AND`/`OR`/`NOT`, comparisons, arithmetic                | Python operators, fully parenthesised; operand order preserved = question order                      | clean                                |
| `IF…THEN…ELSE`, `BRANCH`, `CONSIDER` over enums          | Python conditionals / `if…elif…else` chains in `code:` blocks                                        | clean                                |
| top-level `IMPLIES` in an exported decision (the seam)   | scope and requirement as separate variables; scope-first driver; six-valued verdict                  | R4 — the landmine                    |
| `DECLARE … IS ONE OF` (nullary constructors)             | `datatype: radio` + `choices:`, values = constructor names as strings                                | clean, R6                            |
| constructors with payloads                               | deferred: `show if` follow-up fields                                                                 | M4                                   |
| `STRING`                                                 | `datatype: text` — docassemble has strings (Catala does not)                                         | clean                                |
| `NUMBER` (exact `Rational`)                              | `datatype: number` (Python float) — same class of divergence as OpenFisca's float32, Advisory note   | R6                                   |
| `DATE`, date comparisons                                 | `datatype: date`, `DADateTime` comparisons                                                           | clean for comparisons; arithmetic M4 |
| `MAYBE OF T`                                             | optional field, erased as in `FunctionSchema.hs:147-148`                                             | R8, Advisory                         |
| `TYPICALLY`                                              | `default:` prefill                                                                                   | R7, Advisory                         |
| `@desc` on decide/param/type                             | `question:` text, field `help:`                                                                      | clean                                |
| `@ref` citations                                         | verdict-screen citations and YAML comments (M2); `under:` text                                       | Lossy-none, M2                       |
| `#EVAL`/`#ASSERT` fixtures                               | round-trip oracle inputs (R10); **not emitted** into the interview, per the DMN R0 precedent         | n/a                                  |
| `LIST OF`                                                | `DAList` gathering (`.gather()`, `there_is_another`)                                                 | M4                                   |
| deontic (`PARTY MUST … HENCE/LEST`)                      | none; docassemble multi-user roles/actions are a plausible future mapping, not attempted             | **Blocking** note                    |
| temporal (`EVAL … UNDER RULES EFFECTIVE AT`, four pins)  | none                                                                                                 | **Lossy** note                       |
| ledger (`RECORD`/`FETCH`/`ATTEST`)                       | none (docassemble's `DAWeb` exists for outbound HTTP, unused)                                        | **Blocking** note                    |
| `Inert` prose scaffolding                                | Markdown in `subquestion`/section headers where attached; else dropped with Advisory note            | partial                              |

## 5. What does not map, and how loss is declared

The refusal table is `constructorName`-shaped (`OpenFisca/Lower.hs:387-405`): `Regulative{}`,
`Event{}`, `Fetch{}`, `Record{}`, `ReadCell{}`, `Post{}`, `Breach{}` each refuse with a named
diagnostic **and** a `FidelityNote`. Severity assignment follows
`specs/todo/FIDELITY-SEVERITY-AXIS-SPEC.md`: `Blocking` when the function cannot be emitted at
all (deontic body, ledger effects), `Lossy` when it is emitted minus meaning (temporal pins
ignored), `Advisory` when meaning is preserved but semantics differ in a way a reviewer should
see (float for Rational, `default:` for `TYPICALLY`, erased `MAYBE`). The report placement and
`--fail-on` gate copy `jl4/app/L4/Cli/Export.hs:18-52` verbatim.

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
  `OpenFisca.hs:46-74`; five registration edits (`Main.hs:34,54,91-93,136`; `jl4.cabal:56`);
  jl4-core.cabal gains the three modules beside `:149-151`. The verb-vs-`l4 export` question is
  R1. The new verb name cannot collide with a plausible filename because of the bare-filepath
  fallthrough to `l4 run` (`Main.hs:57-61`) — "docassemble" is safe.
- **Tests.** `jl4/examples/docassemble/{*.l4, expected/*.yml, not-ok/, README.md,
roundtrip_check.py}`, hand-registered `expectGolden` blocks appended after
  `jl4/tests-cli/Main.hs:1327`, byte-exact, each failure printing its regeneration command
  (`Main.hs:288-304` precedent).

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
`jl4-lsp/src/LSP/L4/Viz/QueryPlan.hs:111-152`, `jl4-wasm/app/QueryPlanWasm.hs:82-109`) **[E]**.

**Cost.** The IR must anticipate M3 (a slot for an optional embedded plan) so M3 does not
rework Emit. **What would close it:** sign-off, plus a one-line check that `cabal build exe:l4`
stays clean when jl4-query-plan is added in M3.

### 8.2 R2 — records become DAObject subclasses; questions are per _field_, not per record

**Evidence.** Docassemble's unit of asking is the variable, and every `DAObject` attribute is
independently seekable; `generic object` questions cover any instance **[R]**. The shipped
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

**Cost.** Multi-field single-screen grouping (a genuine UX preference sometimes) is deferred; a
later `@desc docassemble screen …` grouping override can restore it. **What would close it:**
the R10 harness demonstrating that a two-record, six-field example asks only the fields the
goal's evaluation actually demands.

### 8.3 R3 — survival: every reachable decision becomes a named `code:` block

**Evidence.** `Where` bindings are full `Decide`s (`Syntax.hs:254,449-451`) **[E]**. OpenFisca
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
seam semantics fall out of block structure with no BDD at runtime. Non-seam boolean goals get
`Holds`/`Fails`; every verdict value gets its own terminal `event:` screen carrying the goal's
`@desc` and (M2) `@ref` citations. `Undetermined` cannot be reached in v1 (docassemble asks
until defined); it becomes reachable in M3/M4 when "I don't know" answers arrive (the
four-state input model of `RUNTIME-INPUT-STATE-SPEC.md`, itself blocked on TYPICALLY evaluator
semantics — noted, not depended on).

**Cost.** Verdict vocabulary is fixed by the planner's `Verdict` type; renaming later breaks
goldens. **What would close it:** an R10 transcript of a seam example where answering the
requirement questions first is impossible because scope is asked first, and a NotApplicable
run that never asks a requirement question.

### 8.5 R5 — question order: native backchaining v1; embedded compiled plan M3

**Evidence.** Docassemble's order = block/operand order (short-circuit) **[R]**; L4's default =
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

**What would close it:** the enum golden plus an R10 run where a `CONSIDER` over a 3-way enum
asks one radio question and takes the right arm.

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
(`FunctionSchema.hs:147-148`, `Export.hs:201`) **[E]**; docassemble optionality is
per-datatype-shaped (empty string vs `None`) **[R]**.

**Proposal.** Follow the house erasure; `required: False`; lowering of `MAYBE`-consuming
expressions treats absent as the L4 `NOTHING` branch only where the source pattern-matches on
it, else refuses by name. Advisory note per erased field. **What would close it:** one golden
with a `MAYBE STRING` field exercising both present and absent paths under R10.

### 8.9 R9 — emission hygiene (the silent-YAML defence)

Bundled because they are all "docassemble will not tell you" facts **[R]**:

1. **Mako escaping.** Every L4-derived string (names, `@desc`, `@ref`) passes through one
   escape function neutralising `${`, `%` at line start, and YAML-significant leaders.
2. **Explicit `sets:`** on code blocks whose definitions docassemble's AST scan might misread;
   never rely on inference for generated code.
3. **`depends on:`** on every derived block (stale-value trap, §2).
4. **`id:`** on every block, deterministic from the sanitised variable name in v1, switching to
   the UUIDv5 atom identity in M3 so ids are stable across recompiles _and_ joinable to the
   plan.
5. **Self-validation:** Emit only from a fixed whitelist of block keys and field modifiers,
   vendored as a table in `Emit.hs` with the docassemble version it was read from; a golden
   test asserts the emitter's key vocabulary is a subset of the vendored list. No runtime
   dependency on the docassemble source tree (the 1.2 rule: local evidence, never a build dep).
6. **Idempotent drivers; never wrap exceptions** (§2).

**What would close it:** review of the whitelist against the pinned docassemble version in the
R10 harness, plus one not-ok fixture per hygiene rule where feasible.

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

**What would close it:** rodents round-trip green: emit → load → answer per fixture → verdict
equals `#EVAL`. The probe closes the _feasibility_ half already; what remains is running it
against emitted rather than hand-written YAML.

### 8.11 R11 — artifact shape: bare interview YAML v1, installable package M2

**Evidence.** Every existing backend's golden contract is one deterministic text artifact
**[E]** (`expectGolden`, byte-exact). A real deployment wants the namespaced package
(`docassemble.<pkg>` with `pyproject.toml`/SPDX, `data/questions/`, the generated module,
`data/sources/`) **[R]**.

**Proposal.** v1: `l4 docassemble FILE -o interview.yml` emits a single self-contained YAML
(functions module inlined via docassemble's ability to carry code in the interview file, or the
module emitted as a second `-o`-adjacent file when unavoidable — measured during
implementation). M2: `--package DIR` writes the installable tree, embedding the original `.l4`
under `data/sources/` so the encoding travels with its compilation — survival extended to
provenance. Goldens stay on the YAML; the package tree gets a shape test, not byte goldens.

**What would close it:** v1 sign-off; M2 gated on the R10 harness existing to consume it.

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

## 10. Sequencing

- **M1 — static core.** IR/Lower/Emit + CLI verb + fidelity + goldens: booleans, numbers,
  strings, dates-as-comparisons, nullary enums, records (nested), `WHERE` survival, seam
  verdict. First examples: `rodents-and-vermin.l4` (annotated copy), one seam example, one enum
  example.
- **M2 — the loop closed.** `--package`, `data/sources` provenance, R10 harness green,
  `@ref` citations on verdict screens, push recipe (`dainstall`/API) in the README.
- **M3 — the differentiator.** `--plan`: embedded `CompiledDecisionQuery` + Python port of
  `queryDecision`/`verdictOf`, UUIDv5 `id:`s, info-gain ordering, measured against declaration
  order on a real corpus. Requires the R1 packaging move and the `vizExprToBoolExpr` lift.
- **M4 — breadth.** `LIST OF` via `DAList` gathering; payload constructors via `show if`; date
  arithmetic; the document-assembly demo (verdict screen that also assembles the letter) — the
  capability that justifies the backend to the outside world.

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
