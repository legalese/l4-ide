# `TYPICALLY`: one behaviour

**Status:** proposed, not built (2026-10-01).
This spec is an implementation plan, not a new design.
The design was ruled on 2026-09-04 as **R8** (`IMPLICIT-PROPS-DESIGN.md` §11.5) and extended on 2026-09-06 by **D7.3** (`SURFACE-SUGAR-CLUSTER-2026-09.md`).
R8 is the owning ruling, and anything this spec settles is recorded back there (repo `CLAUDE.md` §4).
This file adds three things: a measured census of where the behaviours still disagree (§2), the work to make them agree (§4), and six rulings R8 does not reach (§5).
Every behaviour quoted below was measured on 2026-10-01 against `unstable` at `f9a504b77`, with `l4` and `jl4-service` built from that commit; the probe files are in Appendix A.

**Related:** `TYPICALLY-DEFAULTS-SPEC.md` (the original design; its status header, dated 2026-08-16, still says `TYPICALLY` is "not operational", which stopped being true for section `GIVEN`s on 2026-09-05), `RUNTIME-INPUT-STATE-SPEC.md` (the four-cell `WithDefault` model; its header still says "BLOCKED on TYPICALLY"), `UNKNOWN-EVALUATION-SPEC.md` (drafted in parallel on `spec/unknown-evaluation`; three-valued evaluation), `doc/reference/types/TYPICALLY.md`.

---

## 1. The footgun

Meng, 2026-10-01: _"The different treatment of TYPICALLY in section given vs function given needs to be ironed out. This is a footgun."_

The same line of source means different things depending on where it sits:

```l4
§ `Rates`
    GIVEN rate IS A NUMBER TYPICALLY 3      -- omit it: the rule uses 3

GIVEN rate IS A NUMBER TYPICALLY 3          -- omit it: check error
      base IS A NUMBER
```

The split is wider than section versus rule.
It also runs between tools: `#EVAL` honours a section default that `l4 batch` and `jl4-service` refuse, the ladder presumes a rule default that `#EVAL` will not use, and Catala, docassemble and DMN each do something different again.

The props work package shipped on 2026-09-05 with R8 half-built, and its "Deferred" list (`IMPLICIT-PROPS-DESIGN.md:2391`) says so.
Its text there reads: _"`TYPICALLY` therefore has two behaviours today, not the one R8 asks for — but they are two, down from three."_
Measured across every tool, there are more than two.

### 1.1 What R8 already rules

From `PROPS-REDTEAM-2026-09-03.md` §2.5, agreed by Meng on 2026-09-04:

- A defaulted `GIVEN`, section or rule, may be omitted at a supply site, and the evaluator honours the default.
- The default is filled in once per evaluation, at the root; an inner `WITH` overrides it for that subtree.
- **Rule 1.** Positional sites omit nothing explicit; a rule's own defaulted `GIVEN` may be omitted only at a named (`WITH`) site.
- **Rule 2.** One declaration owns the default.
- **Rule 3.** A default is a module-scope expression, may name another binder or a definition, is evaluated lazily at the root, and a cycle is a check error.
- **Surfaces.** The trace records a defaulted binder as its own event; the JSON schema lists a `TYPICALLY` parameter as optional, never in `required`, with its default and description.

D7.3 adds: a `MAYBE`-typed record field declared `TYPICALLY NOTHING` may be omitted at construction, and only then; the JSON boundary keeps defaulting an absent `MAYBE` field to `NOTHING` regardless.

---

## 2. Census: where `TYPICALLY` is honoured today

Rows are where the `TYPICALLY` is written; columns are what reads it.
"Honoured" means an omitted value takes the default.

| written on                | `#EVAL` / `l4 run`                                       | `l4 batch`                             | `jl4-service`, absent or `null`             | `jl4-service`, `{}`                            | ladder              | query plan |
| ------------------------- | -------------------------------------------------------- | -------------------------------------- | ------------------------------------------- | ---------------------------------------------- | ------------------- | ---------- |
| section `GIVEN`           | **honoured** (p1: `6`; `WITH … IS 5`: `10`)              | refused: "Missing required field" (p7) | refused: "missing required parameter" (p15) | **check error in the generated wrapper** (p15) | presumed, tentative | soft prior |
| rule `GIVEN`, by name     | refused: "you have not supplied these inputs: rate" (p2) | refused (p8)                           | refused (p14)                               | **FALSE, status success** (p14)                | presumed, tentative | soft prior |
| rule `GIVEN`, by position | arity error (p3) — correct under R8 rule 1               | —                                      | —                                           | —                                              | —                   | —          |
| `DECLARE` field           | refused at construction (p4)                             | —                                      | —                                           | —                                              | —                   | —          |
| `ASSUME` (deprecated)     | **ignored**: the result is the bare name (p6)            | —                                      | —                                           | —                                              | —                   | —          |

And independently of the row:

- **Only literals are accepted** (p5): `TYPICALLY phi` is "must be a literal". R8 rule 3 is not built.
- **An enum constructor is refused on a `DECLARE` field and accepted on a `GIVEN`.** `colour IS A Colour TYPICALLY Red` checks on a rule `GIVEN` (p12) and a section `GIVEN` (p13), and on a record field fails twice: "must be a literal" and "I could not find a definition for the identifier Red" (p10). The second error is the real one: the field's default is checked where the enum's constructors are not in scope. The first is misleading, because `isTypicallyLiteral` (`TypeCheck.hs:1737`) accepts a nullary constructor and the message itself names nullary constructors as allowed.
- **The service's published schema carries no default.** It lists both probes' defaulted inputs under `required` with no `default` key (p14, p15). `L4.FunctionSchema` does attach one (`FunctionSchema.hs:255`, `:280`, `:291`), but the service builds its schema through `paramToParameter` (`jl4-service/src/Compiler.hs:509-518`), which ignores the `paramDefault` its `ExportedParam` carries (`Export.hs:72`). So `TYPICALLY.md`'s statement that the published list of facts carries the JSON Schema `default` keyword holds in `jl4-core` and not over the wire.
- **Exporters disagree.** Catala lowers a default to a caller-overridable `context` variable (`Catala/Lower.hs:1295-1296`, R10 of `CATALA-EXPORT-SPEC.md`). Docassemble pre-fills the question with it (`Docassemble/IR.hs:130`, `default:`), so the user still answers. OpenFisca replaces the default with its own: `GIVEN status IS A Status TYPICALLY married` exports as `default_value = Status.single`, the first enum member, exit 0, no note (`OpenFisca/Emit.hs:95`, `OpenFisca/Lower.hs:735`). Blawx lowers through `Relational/Lower.hs`, whose `R-TYPICALLY` fidelity note (`:2843-2855`) covers `ASSUME` only, and `BLAWX-EXPORT-SPEC.md` §5.1 rules Blawx's default "dropped, disclosed". For `GIVEN rate … TYPICALLY 3`, the DMN fidelity report, OpenFisca (which has no fidelity report) and Blawx all drop the default without a word. dmn-md, bpmn and yscript were not surveyed.
- **The ladder presumes a rule default the evaluator will not use.** `ladder-core` lifts each atom's wire `typically` into `ViewSpec.defaults` (`ts-shared/ladder-core/src/viz-adapter.ts:212-222`) and lays it under the user's answers, with `respectDefaults` true unless the caller says otherwise (`layout.ts:412`). For a rule `GIVEN` that is an answer `#EVAL` cannot produce.

### 2.1 How much source this touches

Counted 2026-10-01 by a heuristic that classifies each `TYPICALLY` by its enclosing declaration, skipping comments:

| tree                                    | section `GIVEN` | rule `GIVEN`  | `DECLARE` field | `ASSUME`     |
| --------------------------------------- | --------------- | ------------- | --------------- | ------------ |
| `jl4/examples` (incl. the canon mirror) | 13 in 11 files  | 14 in 6 files | 18 in 6 files   | 3 in 2 files |
| `doc/`                                  | 3 in 2 files    | 2 in 1 file   | 3 in 1 file     | 0            |
| `jl4-core/libraries`                    | 0               | 0             | 0               | 0            |
| `legalese/canon` (its own checkout)     | 0               | 0             | 4 in 2 files    | 0            |
| `pc-encode/deposit` (SG Penal Code)     | 0               | 0             | 0               | 0            |

Making an omitted default work is additive everywhere except `ASSUME`: today every omission is an error, so no file that checks today changes its answer.
The `ASSUME` sites are `ok/typically-basic.l4:32-33` and `ok/assume-heads-and-roles.l4:42`.

---

## 3. Sorted: loud and silent

Readers ration attention, so the silent failures come first (user `CLAUDE.md` rule 7).

**Silent — a wrong answer with exit 0:**

- **S1. The service turns "uncertain", and with it every missing boolean, into FALSE.** `{}` is the wire format's uncertain value (`FnUncertain`, `Backend/Api.hs:74`). One `{}` on any input forces the whole request onto the wrapper path (`Backend/Jl4.hs:527-535`, `:564`), whose code generator binds every boolean as `fromMaybe FALSE` (`Backend/CodeGen.hs:239`, `:335`, `:603`), so on that path an absent or `null` boolean is FALSE as well. Probe p31: `` eligible MEANS `is resident` AND NOT `has criminal record` ``, with `has criminal record` absent and an unused input sent as `{}`, returns `true` with no diagnostic: a missing criminal record reads as none. Deontic functions always take the wrapper path. On p14, `has capacity: {}` returns `{"result":{"value":false}}` with no diagnostic, although the input is declared `TYPICALLY TRUE`; `is adult: {}` does the same. This is the case an investigating officer hits when a fact is unsettled: "uncertain" comes back as "no".
- **S2. The `ASSUME` deprecation advice changes the answer, and says it does not.** The warning on p6 says "Nothing is broken: the file still checks, runs and exports as before" and recommends a section `GIVEN`, and `doc/reference/errors/README.md:571` calls that rewrite "safe to take". `doc/reference/types/TYPICALLY.md:150-155` says the opposite, correctly. On an `ASSUME` with a `TYPICALLY`, that move switches the default on: p6 evaluates to the bare name, and the same declaration as a section `GIVEN` (p7) evaluates to `TRUE`.
- **S3. Canon keeps each default twice, and nothing checks the two agree.** Because a field default does nothing, encoders restate it as a named constant that call sites pass. In `legalese/canon`, `subjects/sg/succession/encodings/legalese/sg-succession-domain.l4:188-200` declares `TYPICALLY TRUE` on two `Interpretation` fields and then builds `the orthodox reading` with both set by hand. `subjects/sg/child-support/encodings/legalese/sg-child-support-domain.l4:91-106` does the same with `the live reading`, and says why: _"It restates the TYPICALLY defaults so that call sites and #ASSERTs have a value to pass; the defaults above remain the normative statement of the readings."_ Edit one and the encoding silently runs on the other. `subjects/us/regcf/encodings/cleanroom-2026-08/regcf-denovo.l4:134-140` gave up on the field default altogether, because of the enum defect in §2.
- **S4. The ladder shows an answer the evaluator cannot give** (§2, last bullet). It is drawn as tentative, which is honest about provenance, but no evaluator path reproduces it.

**Loud — the tool refuses:**

- **L1.** A rule's own defaulted `GIVEN` cannot be omitted at a named site (p2).
- **L2.** `l4 batch` and the service refuse an omitted section default that `#EVAL` honours (p7, p15).
- **L3.** A defaulted record field cannot be omitted at construction (p4).
- **L4.** An enum default on a record field fails with a misleading message (p10).
- **L5.** An expression default is refused (p5).
- **L6.** For a section `GIVEN` boolean sent as `{}`, the generated wrapper calls `fromMaybe` without importing the prelude, and the request fails with "could not find a definition for the identifier fromMaybe" (p15). The cause is not yet traced. It is not the obvious one: `hasBooleans` counts booleans among both the rule's own and the section's inputs (`CodeGen.hs:131-133`), so the `IMPORT prelude` line should be emitted.

Every loud item is a place where a user learns the rule.
The silent ones are why this is a footgun.

---

## 4. The resolution

**One behaviour, stated once.**
`TYPICALLY d` on a name means: when nothing supplies this name at the point where a value must come from outside, use `d`.
That holds wherever the name is declared and whichever tool evaluates it.
A supplied value always wins, and "I don't know" is not an omission (§5, T3).
A tool that cannot honour the default says so; none may quietly substitute something else.

The work items, ordered silent-first.
Each is independently landable unless it names a dependency.

| #   | item                                                                                                                                                                                                                                                                                                                                                                                                                                                     | closes       | where                                                                                                                                  |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| W1  | The service stops making `{}` and `null` FALSE. Under T3 both become an assumed term for a non-`MAYBE` input: stuck if the rule needs it, harmless if it short-circuits away. Under `UNKNOWN-EVALUATION-SPEC.md` they later become Unknown.                                                                                                                                                                                                              | S1, L6       | `Backend/CodeGen.hs:239,335,603`; the missing-`fromMaybe` failure, cause untraced                                                      |
| W2  | The service's schema carries `default` and leaves a defaulted input out of `required`.                                                                                                                                                                                                                                                                                                                                                                   | R8 surface   | `jl4-service/src/Compiler.hs:509-518`; `parametersFromExport`'s `required` at `:505`                                                   |
| W3  | `l4 batch` and the service fill an absent defaulted input with its default, at the root.                                                                                                                                                                                                                                                                                                                                                                 | L2           | batch decoder; `Backend/Jl4.hs:448` (`missing required parameter`), and the direct-AST path's `assumeExprs`                            |
| W4  | A rule's own defaulted `GIVEN` may be omitted at a named site. R8's unbuilt half: thread the callee's `FunTypeSig` defaults to `supplyAppNamed` (`IMPLICIT-PROPS-DESIGN.md:2421`). Positional sites stay as they are (R8 rule 1).                                                                                                                                                                                                                        | L1, S4       | `TypeCheck.hs` named-application supply; `Discharge.hs`                                                                                |
| W5  | Record fields: a defaulted field may be omitted at construction (D7.3, widened by T1); fix the field-default scoping defect and its message.                                                                                                                                                                                                                                                                                                             | L3, L4, S3   | `TypeCheck.hs` `IncompleteAppNamed` (raised at `:4279`; D7.3 cites `:3146`, which has since moved), `inferSelector`'s `checkTypically` |
| W6  | `ASSUME … TYPICALLY` per T2.                                                                                                                                                                                                                                                                                                                                                                                                                             | S2           | `Discharge.hs` `fillInDefault` (`:281-295`), the deprecation message                                                                   |
| W7  | Expression defaults with the cycle check (R8 rule 3).                                                                                                                                                                                                                                                                                                                                                                                                    | L5           | `TypeCheck.hs:1724-1745`; `FunctionSchema.typicallyToJson` must then carry source text                                                 |
| W8  | The trace records "took its default", with the declaration line (R8 surface).                                                                                                                                                                                                                                                                                                                                                                            | —            | `L4.EvaluateLazy.Trace`                                                                                                                |
| W9  | Every exporter either maps the default to the target's own mechanism or emits a fidelity note (T5).                                                                                                                                                                                                                                                                                                                                                      | §2 exporters | `Dmn/`, `OpenFisca/`, `Blawx/` lowerings                                                                                               |
| W10 | Documentation and stale records: `doc/reference/types/TYPICALLY.md` (one behaviour; delete the "everywhere else: metadata only" half), `typically-example.l4`, the header comment of `ok/typically-basic.l4`, the status headers of `TYPICALLY-DEFAULTS-SPEC.md` and `RUNTIME-INPUT-STATE-SPEC.md`, the deferred list in `IMPLICIT-PROPS-DESIGN.md:2391`. Canon's restated constants (S3) can go once W5 lands; that is a canon change, not this repo's. | —            | —                                                                                                                                      |

W4 and W5 share a mechanism: a named supply site that can see the callee's defaults.
W5's D7.3 half is recorded as blocked on W4, and should land with it or after it.
W7 changes what the schema can carry, so it should land after W2.

**What does not change.**
Positional calls (R8 rule 1).
`WITH` as the one override (R9).
The JSON boundary's treatment of an absent `MAYBE` field as `NOTHING` (D7.3).
The query plan's use of a boolean default as a soft prior (`VizExpr.hs`, `typicallyTrueWeight`).
That prior orders questions and never answers one, which is already the one behaviour applied to elicitation.

---

## 5. Rulings this needs

R8 does not reach these.
Each has a recommendation.
Each is also a card on the bench "Unknowns and Defaults" (claude.ai artifact `XQk522h6PN2xv8YFPhogJc`, db collection `l4-unknowns-defaults-1001`), where an independent skeptic's objection revised it; where the card and this text differ, the card is current until the ruling is recorded here. T3 and T4 share cards with `UNKNOWN-EVALUATION-SPEC.md` U9 and U8.

**T1. Every defaulted record field may be omitted, not only `MAYBE … TYPICALLY NOTHING`.**
D7.3 ruled the `MAYBE` case and was silent on `timeout IS A NUMBER TYPICALLY 30`.
Its principle, "the default is written where the field is declared, never inferred from the type", holds just as well for a literal.
_Recommend: yes._ It is additive (p4: every such omission is a check error today), and it is what retires S3.

**T2. `ASSUME … TYPICALLY` is honoured.**
The alternative is to leave it ignored and make the deprecation warning say that moving the declaration switches its default on.
_Recommend: honour it,_ at the root, without rewriting the `ASSUME` into a definition the ladder or schema can see. It is one behaviour, and `ASSUME` is being retired anyway. No golden answer moves: no directive in the three sites' files reads them (§2.1).
It also makes the warning's "nothing is broken" true of the migration it recommends.
`ok/typically-basic.l4` stays on `ASSUME` because `jl4-service/test/QueryPlanSpec.hs:878-891` and a TypeScript fixture pin its ladder atomIds; those must not move. Its header, which asserts the metadata-only reading, changes.

**T3. Absent, `null` and `{}` on the wire are three different things.**
They are the four-cell model of `RUNTIME-INPUT-STATE-SPEC.md` ("The Four-State Model"):

| wire    | cell             | meaning                  | proposed                                                         |
| ------- | ---------------- | ------------------------ | ---------------------------------------------------------------- |
| absent  | `Left (Just d)`  | not asked, has a default | the default                                                      |
| absent  | `Left Nothing`   | not asked, no default    | an assumed term: stuck only if the rule needs it                 |
| `null`  | `Right Nothing`  | "I don't know"           | an assumed term, **never** the default                           |
| `{}`    | (`FnUncertain`)  | "uncertain"              | as `null`, until a ruling gives "uncertain" a meaning of its own |
| a value | `Right (Just v)` | answered                 | the value                                                        |

Today absent and `null` are both refused on the direct path, and `{}` is silently FALSE (S1).
_Recommend: as the table._
The assumed-term row is how a section `GIVEN` with no default already behaves at `#EVAL` (`doc/concepts/legal-modeling/non-answers.md` §3).
It also keeps the reason the wrapper used `fromMaybe FALSE` at all (`CodeGen.hs:93-94`): an input the rule never reads costs nothing.
`UNKNOWN-EVALUATION-SPEC.md` then changes "stuck" to "unknown" without touching this table.

**T4. An exploration mode may switch defaults off.**
An investigator, or anyone asking what is _established_ rather than what is _presumed_, needs to see `Left (Just d)` as unsettled.
The ladder already has that switch (`respectDefaults`).
_Recommend:_ the evaluator and the service get the same switch, defaulting to on, and `UNKNOWN-EVALUATION-SPEC.md` owns its spelling.
Without it, honouring defaults everywhere (W3, W4) strengthens the conversation's original worry instead of answering it.

**T5. Exporters: map or say.**
_Recommend:_ each exporter maps a default to its target's own mechanism where one exists, and otherwise emits a fidelity note naming the dropped default.
OpenFisca's `Variable` has a `default_value`; that is recalled, not checked here.
DMN, OpenFisca and Blawx are the three to survey (§2).

**T6. Where the "took its default" event shows.**
R8 asks for it in every directive and trace output (`PROPS-REDTEAM-2026-09-03.md:367`).
_Recommend:_ also as a top-level `presumed` field in the service response and in `l4 batch`'s NDJSON, listing only the defaults actually forced, built from W8's event (the response's `reasoning` is sent only when a trace is requested, `Backend/Api.hs:210-214`), since T4's question, "which answers rested on a presumption?", is one that service and batch callers ask without wanting a whole trace.

---

## 6. What this spec does not do

It does not redesign `TYPICALLY`; R8 did that.
It does not specify three-valued evaluation; `UNKNOWN-EVALUATION-SPEC.md` does, and §5 T3–T4 are the seam between the two.
It does not touch the canon encodings; S3 is reported to canon, not fixed here.

---

## Appendix A. Probes

Run on 2026-10-01 with `l4` and `jl4-service` built from `f9a504b77` in `~/src/legalese/l4wt/typically-unify` and copied before use.
The service ran locally on port 18731 with an empty store, and each probe was deployed as its own bundle.
p1–p7 were first run on the 2026-09-28 installed `l4` and gave the same results.

| probe | source (abridged)                                                                                                                                   | call                                                                                                                                                | result                                                                                                                            |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| p1    | section `GIVEN rate TYPICALLY 3`; `doubled MEANS rate TIMES 2`                                                                                      | `#EVAL doubled`; `#EVAL doubled WITH rate IS 5`                                                                                                     | `6`; `10`                                                                                                                         |
| p2    | `GIVEN rate IS A NUMBER TYPICALLY 3, base IS A NUMBER`                                                                                              | `#EVAL scaled WITH base IS 10`                                                                                                                      | "you have not supplied these inputs: rate of type NUMBER"                                                                         |
| p3    | same, `rate` last                                                                                                                                   | `#EVAL scaled 10`                                                                                                                                   | "expects 2 inputs, but here it is given 1 input"                                                                                  |
| p4    | `DECLARE Config HAS timeout … TYPICALLY 30, retries …`                                                                                              | `Config WITH retries IS 2`                                                                                                                          | "you have not supplied these inputs: timeout of type NUMBER"                                                                      |
| p5    | section `GIVEN beta … TYPICALLY phi`, `phi MEANS 8`                                                                                                 | `l4 run`                                                                                                                                            | "The TYPICALLY value for `beta` must be a literal"                                                                                |
| p6    | `ASSUME person has capacity IS A BOOLEAN TYPICALLY TRUE`                                                                                            | `#EVAL ok`                                                                                                                                          | `` `person has capacity` `` (unevaluated), plus the deprecation warning                                                           |
| p7    | section `GIVEN has capacity … TYPICALLY TRUE`, exported                                                                                             | `#EVAL`; `l4 batch` with an empty row `[{}]`; with `false`                                                                                          | `TRUE`; "Missing required field 'has capacity'"; `false`                                                                          |
| p8    | rule `GIVEN has capacity … TYPICALLY TRUE, is adult`, exported                                                                                      | `l4 batch` with `{"is adult": true}`; `--validate-only`                                                                                             | "Missing required field"; `"status":"invalid"`                                                                                    |
| p10   | `DECLARE Colour IS ONE OF Red, Green`; field `colour IS A Colour TYPICALLY Red`                                                                     | `l4 check`                                                                                                                                          | "must be a literal" at the field, and "could not find a definition for the identifier Red"                                        |
| p12   | the same default on a rule `GIVEN`                                                                                                                  | `l4 check`                                                                                                                                          | clean                                                                                                                             |
| p13   | the same default on a section `GIVEN`                                                                                                               | `#EVAL isRed`                                                                                                                                       | `TRUE`                                                                                                                            |
| p14   | p8 as a service bundle                                                                                                                              | `POST …/evaluation` with `has capacity` absent; `null`; `{}`; `true`                                                                                | "missing required parameter"; the same; **`false`, SimpleResponse**; `true`                                                       |
| p14   |                                                                                                                                                     | `GET …/functions/may contract`                                                                                                                      | `"required": ["has capacity", "is adult"]`, no `default` key                                                                      |
| p15   | p7 plus a rule `GIVEN is adult`, as a service bundle                                                                                                | absent; `null`; `{}`; `true`                                                                                                                        | "ASSUME 'has capacity': missing required parameter"; the same; "could not find a definition for the identifier fromMaybe"; `true` |
| p31   | booleans `has criminal record`, `is resident`, `unused flag`; `` eligible MEANS `is resident` AND NOT `has criminal record` ``, as a service bundle | `is resident: true`, `has criminal record` absent, `unused flag: false`; the same with `unused flag: {}`; the same with `has criminal record: null` | "missing required parameter"; **`true`**; **`true`**                                                                              |

The heuristic behind §2.1 skips comment text, then assigns each `TYPICALLY` to the nearest preceding column-1 `ASSUME`, `DECLARE` or `GIVEN`, or to a section `GIVEN` when the `GIVEN` is indented on the line after a `§` heading.
It found no `TYPICALLY` it could not assign.
