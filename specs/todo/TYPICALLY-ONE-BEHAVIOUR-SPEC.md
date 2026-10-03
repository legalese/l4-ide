# `TYPICALLY`: one behaviour

**Status:** proposed; W1 built 2026-10-01 in legalese/l4-ide#530; W2 and W3 built 2026-10-02 in `feat/typically-w2w3` (legalese/l4-ide#539, merged 2026-10-06), with the minimum of W8 they need and the checking half of W5 (§4.1); W4 and W5 built 2026-10-03 in this branch (`feat/typically-w4w5`, on top of #539), with the `MEANS` check of T1 and W8's event at their fill sites (§4.2); W6 deferred by Meng's word (§4); the findings of two rounds of adversarial review of W4 and W5 fixed or recorded on 2026-10-03 (§4.2, "Review fixes"); W7 built 2026-10-03 in `feat/typically-w7`, on top of `feat/typically-w4w5`, and the findings of the review of its first build fixed or recorded the same day, and those of a second review of its rebuild fixed, disputed or recorded in the night of 2026-10-03 (§4.3); W10 built 2026-10-04 in `feat/typically-w10`, on top of `feat/typically-w7`, documentation and records only (§4.4); the rest not built.
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

The props work package shipped on 2026-09-05 with R8 half-built, and its "Deferred" list (`IMPLICIT-PROPS-DESIGN.md`, "Deferred, each with why") said so on 2026-10-01.
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
  **Fixed by W7** (§4.3): a default is any expression over what the module declares on a section `GIVEN`, and over definitions and constructors on a rule's `GIVEN` and a record field, where it may not read a section `GIVEN`.
- **An enum constructor is refused on a `DECLARE` field and accepted on a `GIVEN`.** `colour IS A Colour TYPICALLY Red` checks on a rule `GIVEN` (p12) and a section `GIVEN` (p13), and on a record field fails twice: "must be a literal" and "I could not find a definition for the identifier Red" (p10). The second error is the real one: the field's default is checked where the enum's constructors are not in scope. The first is misleading, because `isTypicallyLiteral` (`TypeCheck.hs:1737`) accepts a nullary constructor and the message itself names nullary constructors as allowed.
- **The service's published schema carries no default.** **Fixed by W2** (#539): p15's `has capacity` is out of `required` and carries `"default": true` (§4.1). Before: it listed both probes' defaulted inputs under `required` with no `default` key (p14, p15). `L4.FunctionSchema` does attach one (`FunctionSchema.hs:255`, `:280`, `:291`), but the service builds its schema through `paramToParameter` (`jl4-service/src/Compiler.hs:509-518`), which ignores the `paramDefault` its `ExportedParam` carries (`Export.hs:72`). So `TYPICALLY.md`'s statement that the published list of facts carries the JSON Schema `default` keyword holds in `jl4-core` and not over the wire.
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
  **Fixed by W1** (#530, smucclaw/l4-ide#992): p31 now stops with "I needed to know the value of `has criminal record (not supplied)`", and p14's `{}` stops naming `has capacity (not supplied)`.
- **S2. The `ASSUME` deprecation advice changes the answer, and says it does not.** The warning on p6 says "Nothing is broken: the file still checks, runs and exports as before" and recommends a section `GIVEN`, and `doc/reference/errors/README.md:571` calls that rewrite "safe to take". `doc/reference/types/TYPICALLY.md:150-155` says the opposite, correctly. On an `ASSUME` with a `TYPICALLY`, that move switches the default on: p6 evaluates to the bare name, and the same declaration as a section `GIVEN` (p7) evaluates to `TRUE`.
- **S3. Canon keeps each default twice, and nothing checks the two agree.**
  **Made avoidable by W5, not closed** (§4.2): a construction may now leave a defaulted field out, so a restated constant is no longer needed to override one field. S3's own defect, that nothing checks the two agree, is the check-time warning T4b rules for a construction that restates a field's default, and that is not built (§4.2, "Not built here"). Removing the restated constants is a canon change, not this repo's, and the two all-defaults constants stay until T1's spelling for "every field defaulted" is ruled. Because a field default does nothing, encoders restate it as a named constant that call sites pass. In `legalese/canon`, `subjects/sg/succession/encodings/legalese/sg-succession-domain.l4:188-200` declares `TYPICALLY TRUE` on two `Interpretation` fields and then builds `the orthodox reading` with both set by hand. `subjects/sg/child-support/encodings/legalese/sg-child-support-domain.l4:91-106` does the same with `the live reading`, and says why: _"It restates the TYPICALLY defaults so that call sites and #ASSERTs have a value to pass; the defaults above remain the normative statement of the readings."_ Edit one and the encoding silently runs on the other. `subjects/us/regcf/encodings/cleanroom-2026-08/regcf-denovo.l4:134-140` gave up on the field default altogether, because of the enum defect in §2.
- **S4. The ladder shows an answer the evaluator cannot give** (§2, last bullet). It is drawn as tentative, which is honest about provenance, but no evaluator path reproduces it.
  **Closed by W4** (§4.2): `#EVAL` of the rule with the other inputs by name now takes the default the ladder presumed, so there is a path that reproduces it. The ladder itself is unchanged.
- **S5. The service's wrapper path never delivered a section `GIVEN`'s value** (found while building W1, fixed by it in #530). It bound the name with a `LET` around the call, which does not reach the rules that read a section `GIVEN`: they saw its `TYPICALLY` default, or an assumed term. L6 hid this whenever the request had a boolean. Without it, `has capacity: false` (declared `TYPICALLY TRUE`) with a `{}` on an unread input answered `true`. W1 supplies section `GIVEN`s with `WITH`, the language's way of supplying them at a root.

**Loud — the tool refuses:**

- **L1.** A rule's own defaulted `GIVEN` cannot be omitted at a named site (p2).
  **Fixed by W4** (this branch, §4.2): p2's `#EVAL scaled WITH base IS 10` is `30`.
- **L2.** `l4 batch` and the service refuse an omitted section default that `#EVAL` honours (p7, p15).
  **Fixed by W3** (#539): both fill it, and list it in `presumed` (§4.1).
- **L3.** A defaulted record field cannot be omitted at construction (p4).
  **Fixed by W5** (this branch, §4.2): p4's `c's timeout` is `30`.
- **L4.** An enum default on a record field fails with a misleading message (p10).
  **Fixed in #539** (the checking half of W5, which W3 needs, §4.1): p10 checks clean, and a record built from it evaluates (`DECIDE p IS Paint Red 2`, then `#EVAL p's colour`, gives `Red`).
  **The message, fixed by W5** (§4.2): a default naming something that is not in scope is reported once, as that; the second error, "must be a literal", is no longer raised for it, on a field or on a rule's input (`not-ok/tc/typically-unresolved.l4`).
- **L5.** An expression default is refused (p5).
  **Fixed by W7** (§4.3): p5's `beta TYPICALLY phi` checks, and `#EVAL doubled` is `16`.
- **L6.** For a section `GIVEN` boolean sent as `{}`, the generated wrapper calls `fromMaybe` without importing the prelude, and the request fails with "could not find a definition for the identifier fromMaybe" (p15). It is not the obvious cause: `hasBooleans` counts booleans among both the rule's own and the section's inputs (`CodeGen.hs:131-133`), so the `IMPORT prelude` line is emitted.
  **Cause traced 2026-10-01:** the wrapper is appended after the source, so it lands inside the source's last `§` section, and an `IMPORT` inside a section does not resolve (`§` heading, then `IMPORT prelude`, then `fromMaybe` fails the same way in a plain `l4 run`).
  W1 removes the import, so the failure is gone; an `IMPORT` silently not resolving after a heading is a language question this spec does not take up.
- **L7. On the wrapper path a genuine `ASSUME` is still not delivered** (found while building W1; open). `ASSUME age IS A NUMBER` with `age: 30` and a `{}` elsewhere stops with "I needed to know the value of age". `WITH` cannot supply an `ASSUME`, so this needs the module-level rewrite the direct path uses (`rewriteModuleAssumes`); it bears on W6.

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

| #   | item                                                                                                                                                                                                                                                                                                                                                                                                                                                     | closes       | where                                                                                                                                                        |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| W1  | The service stops making `{}` and `null` FALSE. Under T3 both become an assumed term for a non-`MAYBE` input: stuck if the rule needs it, harmless if it short-circuits away. Under `UNKNOWN-EVALUATION-SPEC.md` they later become Unknown.                                                                                                                                                                                                              | S1, L6, S5   | **Built in #530.** `Backend/CodeGen.hs` (placeholder assumed terms; section `GIVEN`s by `WITH`); `Backend/Jl4.hs` `splitAssumeParams`                        |
| W2  | The service's schema carries `default` and leaves a defaulted input out of `required`.                                                                                                                                                                                                                                                                                                                                                                   | R8 surface   | **Built in this branch** (§4.1). `Compiler.hs` `parametersFromExport`; `L4.Export.isRequiredInput`, `honouredDefault`                                        |
| W3  | `l4 batch` and the service fill an absent defaulted input with its default, at the root. In `l4 batch` this covers JSON, YAML and CSV input, and an empty CSV cell is absent (T3c).                                                                                                                                                                                                                                                                      | L2           | **Built in this branch** (§4.1). `L4/Cli/Batch.hs`; `Backend/Jl4.hs` root fills; the JSON decoder in `Machine.hs`                                            |
| W4  | A rule's own defaulted `GIVEN` may be omitted at a named site. R8's unbuilt half: thread the callee's `FunTypeSig` defaults to `supplyAppNamed` (`IMPLICIT-PROPS-DESIGN.md`, "Deferred, each with why"). Positional sites stay as they are (R8 rule 1). **Built in this branch** (§4.2).                                                                                                                                                                 | L1, S4       | `TypeCheck.hs` named-application supply; `Discharge.hs`                                                                                                      |
| W5  | Record fields: a defaulted field may be omitted at construction (D7.3, widened by T1); fix the field-default scoping defect and its message. **Built in this branch** (§4.2), with T1's `MEANS` check.                                                                                                                                                                                                                                                   | L3, L4       | `TypeCheck.hs` `supplyAppNamed` (raises `IncompleteAppNamed`; D7.3's `:3146` has since moved), `inferSelector`'s `checkTypically`                            |
| W6  | `ASSUME … TYPICALLY` per T2. **Deferred, not built.** Meng, 2026-10-02: _"I'd be ok with skipping or deferring W6 as ASSUME is being deprecated."_ T2 stays ruled; `ASSUME … TYPICALLY` is still ignored by `#EVAL` and stays in `required`, and S2 stays open.                                                                                                                                                                                          | S2           | `Discharge.hs` `fillInDefault` (`:281-295`), the deprecation message                                                                                         |
| W7  | Expression defaults with the cycle check (R8 rule 3). **Built in this branch** (§4.3); a rule's or a field's default may not read a section `GIVEN`.                                                                                                                                                                                                                                                                                                     | L5           | `TypeCheck.hs` `checkTypically`, `checkPendingDefaults`; `Discharge.hs` `defaultCycles`, `readSetsAll`; `FunctionSchema.typicallyToJson` carries source text |
| W8  | The trace records "took its default", with the declaration line (R8 surface).                                                                                                                                                                                                                                                                                                                                                                            | —            | **The event is built in this branch** (§4.1, and raised by W4 and W5's fills, §4.2), not its trace rendering. `L4.EvaluateLazy.Trace`                        |
| W9  | Every exporter either maps the default to the target's own mechanism or emits a fidelity note (T5).                                                                                                                                                                                                                                                                                                                                                      | §2 exporters | `Dmn/`, `OpenFisca/`, `Blawx/` lowerings                                                                                                                     |
| W10 | Documentation and stale records: `doc/reference/types/TYPICALLY.md` (one behaviour; delete the "everywhere else: metadata only" half), `typically-example.l4`, the header comment of `ok/typically-basic.l4`, the status headers of `TYPICALLY-DEFAULTS-SPEC.md` and `RUNTIME-INPUT-STATE-SPEC.md`, the deferred list in `IMPLICIT-PROPS-DESIGN.md`. Canon's restated constants (S3) is a canon change, not this repo's. **Built in this branch** (§4.4) | —            | —                                                                                                                                                            |

### 4.1 W2 and W3, as built (2026-10-02)

Built in #539 on top of #530 (W1).
Everything below was measured on the branch's own `l4` and `jl4-service`; the CLI tests in `jl4/tests-cli/Main.hs` ("l4 batch: TYPICALLY defaults (W3)") and the service tests in `jl4-service/test/IntegrationSpec.hs` ("TYPICALLY defaults (W2, W3 …)") pin it.

**One mechanism for every fill site: the event is raised where the default is forced.**
T6 lists only defaults "actually forced", so the fill sites do not raise the event themselves; they mark the place the default lives, and the evaluator raises W8's event the first time that place is forced (`L4.EvaluateLazy.Machine.Presumed`, `notePresumedForce`, called from `evalRef`).
There are three such places:

- a section binder's default, which discharge already turns into a 0-ary definition (`Discharge.hs` `fillInDefault`); `evalDecide` registers it;
- a record field the JSON decoder filled from its `DECLARE` (`jsonValueToWHNFTyped`); the decoder registers it;
- a default the service's direct path filled at the root, which it adds to the module as a 0-ary definition (`Backend/Jl4.hs` `RootFill`) and hands to the evaluator (`execEvalExprInContextOfModuleWith`'s `RootFills`).

So T6b's "every other fill site emits W8's event itself" is met in substance, with one deviation of form: the fill site marks, and the force reports.
The alternative, reporting at the fill site, lists a default the rule never read, which T6 rules out; measured, `is adult` FALSE leaves `has capacity` unread and `presumed` empty, on every path.
Each event carries the path it landed at, the `SrcRange` of the `TYPICALLY` that supplied it, and which fill site made it (`PresumedOrigin`), and is reported once per directive (`EvalDirectiveResult.presumed`).

**Where each tool fills.**

- `l4 batch` decodes each row into a generated `InputArgs` record with one field per input, so a defaulted input is a field carrying its `TYPICALLY`, and the decoder fills it: one fill site for rule `GIVEN`s, section `GIVEN`s and record fields alike, and it survives the re-print (R6), because the wrapper is source text.
  A section binder is therefore filled by the decoder in batch, not by discharge (batch drops the binder's `ASSUME` and rebinds it from the row, as before).
- The service's direct path fills a rule `GIVEN` and a record field by root fill, and leaves a section `GIVEN` absent so that discharge fills it (T6b).
- The service's wrapper path declares a defaulted rule `GIVEN` as an `InputArgs` field of its own type carrying the `TYPICALLY` (not lifted to `MAYBE`), and leaves a defaulted section `GIVEN` out of its `WITH`, for discharge.
  It also sends `null` for every input the request left out that is not being defaulted, because on that path absent and `null` were always the same (W1) and the hard switch below would otherwise refuse the wrapper's own lifted `MAYBE`s.
  The exception is an input the author declared `MAYBE`: it stays absent, so that the decoder fills its `NOTHING` and reports it under soft, and refuses it under hard (T1b), as the direct path does.

**T1b's decoder half.** All three decoders read a field's default from its `DECLARE`: the `Machine.hs` decoder from the evaluated module's records and, through `GetLazyEvaluationDependencies`, its transitive imports' (`execEvalModuleWithEnvAndImports`); the service's direct path from `compiledAllDeclares`; the wrapper through the first.
A declared default wins over D7.3's `MAYBE` fallback, and with presumption off neither fires.
A field left out that nothing fills is refused with every such field of the object named in one message ("Missing required fields 'a', 'b' in JSON object"; one field keeps the old wording); the direct path names every failing input, one per line.
`FunctionSchema.hs` and `JsonSchema.hs` drop a field with a `TYPICALLY` from `required`.
Not covered: a field of an enum constructor that carries data (`JsonSchema.hs:333` still lists it as required, and no decoder fills it, because none decodes such a constructor from JSON); a record built inside L4 (W4/W5).

**T3, and null kept apart from absent from the wire inward.** On the service, `"x": null` arrives as a key present with no value and an absent key as no key (`Backend/Api.hs` `FnArguments`); the direct path reads the three cells from the request map before anything collapses them (`Backend/Jl4.hs` `suppliedIn`, `Supplied`), and the wrapper path fills only keys that are absent (`wrapperPlan`). Tests send `null` and absent on both paths ("keeps null apart from absent on the wrapper path", "never takes a default for null").
`null` on any input or field that is not a `MAYBE` is refused, naming it, whether or not it has a default ("Field 'x' is null, which means the value is not known: supply a value"; with a default, "…, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"); `{}` likewise, being `null` (T3), and the message spells it as sent.
Whether a field is a `MAYBE` is decided on its type with synonyms expanded, so a synonym for `MAYBE` keeps D7.3's fallback (`jsonValueToWHNFTyped` via `expandTypeSynonyms`; the direct path via `miSynonyms`).
Following T3 (review: the report's item 5): an enum input with no default sent as `null` used to decode to `NOTHING`, so the case answered with status success.
The decoder now names the field in every primitive mismatch (`Expected JSON boolean for field 'x' but got: Null`), where it used to name only the JSON kind.

**T3c.** An empty CSV cell is dropped from the row (`Batch.hs` `parseBatchInput`), so it is absent exactly as a missing column is.
Batch reads CSV with its own row loop over cassava's `header` and `record` parsers (`csvRows`), because `Csv.decodeByName` drops every record that parses to one empty field, and a line holding only `""` parses to that as a blank line does: a one-column file lost that row, two rows in and one out, exit 0.
Assumed, not ruled: a cell of spaces is empty, so absent; a quoted `""` in a one-column file is a row whose cell is absent; an unquoted blank line is not a row.
The two shapes after this paragraph, a short or long record and a line of spaces, are under "Decided by Claude overnight" below.
A leading UTF-8 byte-order mark is not part of the header (review B1): Excel's "CSV UTF-8" export writes one, and it renamed the first column, so that input took its default on every row.
Its `MAYBE` paragraph measured both ways: an empty cell for `GIVEN premium IS A MAYBE NUMBER` gives `NOTHING` under soft and "Missing required field 'premium'" under hard.

**T4, and the names chosen for it** (assumptions, not rulings; Meng's soft and hard of T3c):

- `l4 batch --presumption soft|hard`, default `soft`.
- The service: `"presumption": "soft" | "hard"` in the request body, beside `arguments`, and on the batch endpoint's body for all its cases; absent means `soft`.
- In the core: `EvalConfig.presumeDefaults`, read by discharge (`dischargeModuleWith`) and by the decoder.
- T4b: the switch reaches only the request's decode, following the ruling (review code #1, silent M3).
  The decoder treats a decode at `EvalConfig.requestRecord` (`L4.Presumption.requestRecordName`, set by batch and the service wrapper) as the request's, through `DecodeAt.isRequest`, and its nested fields inherit that.
  A decode the rules make of their own fills its defaults in both modes; under hard they are listed in `presumed` as `JSONDECODE <type>: <field>`, which is T4b's "rests on presumed x", and under soft T6b's filter keeps them out (`L4.EvaluateLazy.requestPresumed`).
  Before this, hard mode withdrew a rule's own decode's defaults too, and the failure escaped the `EITHER`, so the rule's own `WHEN LEFT` never ran.
  `#EVAL`, which no request reaches, takes `presumeDefaults` as on.

**T6, and the shape chosen for `presumed`** (assumptions):

- A list of strings: an input's name, or the path to a field below it, dot-joined, with a list element as its index (`people[0].age`).
- `l4 batch`: a top-level `presumed` array on every evaluated row, in every format, an error row included (whatever was forced before it stopped, so the envelope keeps one shape). With `--format csv` a `presumed` column holding the same list as compact JSON, `[]` when empty: a name may contain `,` or `;` (`` `of sound mind; sober` `` checks), so no separator could be read back. A `--validate-only` row evaluates nothing and has none. Assumed, not ruled.
- The service: `presumed` beside `result` on every answer, always present; `@presumed` on each case of the batch endpoint. A refusal is an answer, so `EvaluatorRefused` carries its own `presumed` beside the reason, and a refused case of the batch endpoint carries `@refused` and `@presumed` (review M5). Any other error body has none, since nothing was answered; an errored case of the batch endpoint carries `@error` instead of vanishing into `casesIgnored` (review m5). The MCP tools take no `presumption` and evaluate soft; their result is the same JSON, `presumed` included. Assumed, not ruled.
- Only events belonging to the request count (T6b): a section binder's, a root fill's, or one from the request's decode (origin `FromRequest`), and only for an input the function takes. A `JSONDECODE` the rules make of their own is not the request's. One function decides this for both tools (`requestPresumed`), and the origin is set where the decode starts, not by comparing printed type names (review code #6).
- **D7.3's `NOTHING` for a left-out `MAYBE` with no `TYPICALLY` is listed**, like a default. T1b puts that fallback under the presumption switch, so it is a presumption, and leaving it out would let a soft run and a hard run differ with `presumed` saying nothing. _Decided by Claude overnight 2026-10-02, pending Meng's review._ Its event carries no declaration range, since no `TYPICALLY` supplied it. A `null` on a `MAYBE` is a value and is not listed.
- **A section default counts as forced on the first READ of its value, not when discharge binds it at the root.** A default that is declared, left out and never read does not appear. _Decided by Claude overnight 2026-10-02, pending Meng's review._ This is the likeliest silent over-report, so it is tested as `FALSE AND <defaulted input>` on batch and on both service paths ("lists only a default the evaluation actually read", "lists a section default only when the rule reads it, on both paths").

**Other open shapes, assumed, not ruled:**

- `{}` as a value: see "Decided by Claude overnight" below.
- Presumption off makes a defaulted input behave exactly like an absent input with no default in the same tool: batch refuses it naming it, the direct path refuses it naming it, the wrapper path treats it as not supplied, exactly as W1 left that path. Never a third behaviour; the messages only add why the default was not used.
  So in batch and on the direct path the refusal is eager: a left-out defaulted input the rule would never have read is refused too (`{"is adult": false}` under hard names `has capacity`), as an input with no default always was. The batch page says so.
- `ASSUME … TYPICALLY` stays in `required` until W6, and is neither published nor filled.

**W2.** `isRequiredInput` (`L4.Export`): with presumption on, an input is required unless it is a `MAYBE` or has a default a request may omit.
`honouredDefault` withholds a written `ASSUME`'s `TYPICALLY`: `#EVAL` does not honour it (W6), so neither the schema nor either tool does yet, which keeps R1's parity for it.
`typicallyToJson` now publishes an enum default as its constructor's name and `NOTHING` as `null`.

**The checking half of W5** (p10), which batch needs, because its `InputArgs` carries an input's `TYPICALLY` verbatim.
Phase 1 checked a `DECLARE` while only type names were in scope, so `colour IS A Colour TYPICALLY Red` could not resolve `Red`; a field's default is now checked in phase 4 (`TypeCheck.hs` `checkFieldDefaults`).
Omitting a defaulted field at a construction (L3) is still W5.

**R1, parity with `#EVAL`.** Holds for section `GIVEN` defaults: batch, the service and `#EVAL` give the same answer with the binder omitted (`jl4/tests-cli/fixtures/batch-typically-section.l4`: ``#EVAL `can contract` TRUE`` is `TRUE`, and so is the batch row `{"is adult": true}`).
It cannot yet hold for a rule `GIVEN` or a record field, because `#EVAL` refuses those omissions (p2, p4) until W4/W5; batch and the service fill them at the root, as W3 rules.
**That gap is accepted, and stated on the batch documentation page** (`doc/tutorials/getting-started/l4-cli.md`). _Decided by Claude overnight 2026-10-02, pending Meng's review._

**Not fixed, and outside W3: a section input overridden by an inner `WITH` does not run under `l4 batch`.**
`outer MEANS inner PLUS (inner WITH r IS 100)`, with `r` a section `GIVEN`, gives `206` and, `WITH r IS 5`, `210` under `#EVAL`, and under `l4 batch` fails to type-check with every input supplied: "You are giving named inputs to inner … but it is not a function, so it takes none."
Batch drops each read binder's `ASSUME` and redefines it as a plain value bound from the row (`Batch.hs` `unbindRead`, `rewriteModuleAssumes`), so the binder a `WITH` names no longer exists.
It fails the same way on the 2026-09-28 `l4`, so it predates #539.
The likely fix is the service wrapper's: keep the binder and supply it at the root with `WITH`, leaving a defaulted one to discharge as T6b says. For batch that would probably also mean renaming the `InputArgs` fields, which share the inputs' names (the service suffixes them ` (input)`), and so changing the "Missing required field" messages batch prints. It is not done here, and the batch page states the limit.

**Also fixed on the way.** Batch's `InputArgs` printed one field per line with a leading `, `, and a field after one whose type is an application (`MAYBE NUMBER`) failed to parse ("incorrect indentation"), so an export with a `MAYBE` input before another input failed every row; it now prints the fields without separators.
The service wrapper had the same layout, and under hard it failed to compile a module soft ran (review m4, code #13); `generateInputRecordLifted` now prints the same way.
legalese/l4-ide#531 cured the same symptom from the other end, by lifting the printer's `MAYBE OF X` to `MAYBE X`; the two fixes are independent, and both are in.
On the wrapper path a missing `DATE`, `TIME` or `DATETIME` with no default still fails as "Evaluation produced unknown value", naming nothing: `wrapperPlan` keeps W1's lifting for them, because the wrapper converts them from strings (since #532 all three, as `MAYBE STRING`). Measured on the rebased service, 2026-10-02; the README lists it.

**Review fixes (2026-10-02).** After the code-quality and silent-failure reviews, beyond those recorded above:

- One fill decision (review code #4): `L4.Presumption.fillDecision` decides absent / `null` / value against default / `MAYBE` / neither and soft / hard, and supplies the words; the decoder, the direct path's root and nested fills, and their messages all use it. The mechanisms stay separate, because they differ (a decoder, AST root fills, discharge). The direct path's nested refusal now names the field's path.
- One wrapper plan (review code #5): `Backend.Jl4.wrapperPlan` decides each input's field for all three wrapper builders (plain, deontic, and the `createFunction` slow path). On it, a defaulted non-`BOOLEAN` input sent as `null` keeps its own type, so the decoder refuses it by name (review m8); it used to fail as "Evaluation produced unknown value". The slow path has no test of its own: it runs only when `precompileModule` fails and `typecheckModule` then succeeds, which no test fixture reaches.
- Wrapper messages drop the wrapper's own ` (input)` suffix (review m6), and a section `GIVEN` is a `Parameter` in the direct path's messages, not an `ASSUME` (review code nit 22).
- An exact default reaches the evaluator exactly (review m1): the printer writes a `NumericLit` from its `Rational` (`prettyRatioExact`), so `0.10000000000000000001` no longer goes through a `Double` in batch's re-print or the service wrapper.
- The schema publishes an enum default as the constructor's own name, unqualified (review m2), and the query plan's schema (`parametersFromDecideWithErrors`) now agrees with the service's on `required` and on a written `ASSUME`'s default (review code #7).
- The registry of defaults is per evaluation, keyed by address number in an `IntMap` and confirmed by the reference's own pointer, and `snapshotRef` re-registers the copy it makes (review code #2, #3). No cross-request leak: every request builds its own `EvalState`, and a concurrent test asserts each response's own `presumed`. Measured on `fib 30` with one section default never read, so the registry is non-empty throughout: 3.28 s before, 3.30 s after, 3.10 s on a 2026-09-28 `l4` without W3 (median of five, interleaved). So a module with any outstanding default pays about 6% on a force-heavy run, which this change did not reduce; marking the thunk instead, as the review suggests, is the way to remove it. Not covered: a reader that peeks without `evalRef` (the deontic machinery's reads of a party) does not report a default.
- Residue: the schema still lists an input typed by a synonym for `MAYBE` as `required` (`L4.Export.isMaybeType` does not expand synonyms, and an imported synonym is not visible there). That errs loud: a client following the schema sends the input.
- Not changed, and operational notes for the pull request: the redeploy compatibility gate ignores a changed default (review m3), and every stored `bundle.cbor` is recompiled once after upgrade, logging "Corrupt bundle.cbor" (review code #11; the text is quoted in `EVERY-EACH-QUANTIFIER-SPEC.md`, so it is left as is).

**Decided by Claude overnight 2026-10-02, pending Meng's review.** Three shapes W3 had made quiet that were loud before it; the lead's rule was to restore the loudness exactly there. Each is in its own commit, so that it can be reverted alone, and each names the alternative.

- **An unknown key, where a default was filled (review M1).** Before W3, a misspelled key on a non-`MAYBE` input was loud, because the input it misspelled was then missing; once that input has a default, ignoring the key let the misspelling take the default, with status success and only `presumed` to show it. So in any object where a default was filled (the request's top level, a record inside it, a CSV row, which takes its keys from the header), a key that matches nothing is refused, naming it and the nearest declared name (`Unknown field 'has capasity' (did you mean 'has capacity'?)`; on the service's top level, `Unknown parameter …`). Postel's law still holds in an object where no default was filled, so nothing that worked before W3 starts failing. "Filled a default" means a `TYPICALLY`; D7.3's `NOTHING` for a left-out `MAYBE` does not count, because it predates W3, and counting it would break requests that worked. The decoder applies it to every decode, a rule's own `JSONDECODE` included, since there too the object would have failed before W3; the service checks its top level once for every path (`refuseUnknownArguments`), and `--validate-only` agrees, records and lists included (`validateRow`, `unknownIn`). Consequence to weigh: a CSV with a column that is not an input, such as an `id` kept for joining output to input, now fails on every row that takes a default. _Alternative:_ no refusal; an `unrecognised` list beside `presumed`, with `presumed` declared in the per-deployment OpenAPI so that a generated client keeps both.
- **`{}` as a value means `null`, on every path, records included (review M2).** T3: "`{}` means `null` until it is retired". So `{}` on a record input or field never takes a default and is refused, naming it (`Field 'cfg' is {}, which means the value is not known: supply a value`), and on a `MAYBE` record it is `NOTHING`. The same holds for `{}` as a list element. The service now sends an uncertain value to its wrapper as `{}` rather than `null`, so that a refusal spells what the request sent; the decoder treats the two alike. A whole batch row `{}`, or a rule's own `JSONDECODE` of `"{}"`, is the object being decoded rather than a value inside one, and still supplies nothing, so every default applies. How to spell "a record with every field defaulted" stays open, as T1 left it; the batch page says so. _Alternative:_ `{}` on a record input means "a record with nothing supplied", on both paths (the service would then have to stop reading `{}` as uncertain for a record).
- **A CSV record whose cell count is not the header's is refused, naming its line (review M4).** A short record used to take the defaults of its missing cells, and a long one lost its extra cells, both with status success. Such a record is now an error row (`Line 3 has 1 cell, but the header has 2, …`), counted against `--continue-on-error` like any other, with the cells it had as its `input`. Line numbers count physical lines, so a quoted cell holding a line end moves the next record's number. An unquoted line holding only spaces or tabs is blank and skipped, in a one-column file too; a quoted `""` or `"   "` is a row whose cell is absent (T3c). _Alternative:_ an unquoted whitespace-only line in a one-column file is a row, whose cell is absent.

W4 and W5 share a mechanism: a named supply site that can see the callee's defaults (§4.2).
W7 changes what the schema can carry, so it should land after W2.

### 4.2 W4 and W5, as built (2026-10-03)

Built in this branch on top of #539 (W2 and W3).
Everything below was measured on the branch's own `l4` and `jl4-service`; the corpus files `ok/typically-named-site.l4`, `ok/typically-record-construction.l4`, `ok/typically-import-def.l4` and `ok/typically-import-use.l4`, the not-ok files `not-ok/tc/typically-named-site.l4`, `typically-computed-field.l4` and `typically-unresolved.l4`, the semantic-token file `lsp/semantic-tokens/typically-fill.l4`, the CLI tests ("l4 batch: TYPICALLY at a named site (W4, W5)") and the service test ("lists a default a named site inside the rules took, …") pin it.

**One mechanism for both: a named application that leaves a defaulted input or field out checks as a COMPLETE application.**
`supplyAppNamed` used to report every input still unsupplied when it ran out of written arguments (`IncompleteAppNamed`).
It now asks the callee's table of defaults (`CheckEnv.visibleInputDefaults`) first, adds the default as one more named argument, and reports only the inputs that have none.
Only a named site reaches that function, so R8 rule 1 holds without being checked: a positional site never gets there and keeps its arity error.

- **The tables.**
  A rule's come from its own checked signature (`functionInputDefaults`, added by `withDecides`; for a `WHERE` rule `withExtraInputDefaults` carries them over the body they scope over; the same is wired for `LET`, whose bindings cannot take a `GIVEN`, so it is unreachable and untested).
  A record's come from `withCheckedFieldDefaults`, which checks every `DECLARE`'s field defaults once, before the first body, and replaces the in-order `checkFieldDefaults` call in `inferDeclare`: a construction that comes BEFORE its `DECLARE` in the file needs the default, and checking at the declaration would not have it yet (`ok/typically-record-construction.l4`, `a brick`).
  Both are keyed by the callee's `Unique` and then by the input's, so an `AKA` and a section-qualified spelling find the same entry (measured: `rescaled WITH base IS 10`, `` `Pricing`.scaled WITH base IS 10 `` and `pricing.scaled WITH base IS 10`, all `30`); a mixfix canonical alias shares the `Unique` as well, which is not tested.
  Across an `IMPORT` they travel like `implicitReaders`: `CheckResult.inputDefaults`, merged by `unionImportedCheckEnv` and carried through `tcdInputDefaults` and the LSP's `TypeCheckResult`, so a chain of imports carries them to the end (`ok/typically-import-use.l4`; a rule reached only through a second import works too, measured).
  The recorded type of each node of a default is resolved with the exporting module's substitution on the way out, and dropped only if an inference variable is still left in it (W7, §4.3, advisor D2; W4 and W5 dropped every one, which was harmless for a literal and not for `JSONDECODE`, which reads the type off its node).
- **The added argument.**
  `defaultNamedExpr` builds it from the checked default with every annotation empty, so no token of the declaration it was written in is read again at the call site, and with the shapes the generic traversals expect (two holes on the `NamedExpr`, one on a `Lit`, two on a nullary `App`).
  `DefaultFill` on the value's `Extension` says it was added, and which rule or record and which input or field it fills.
  The semantic-token golden `lsp/semantic-tokens/typically-fill.l4` is the proof that the Check phase still has tokens and none at the declaration's position.
- **Why a complete application, and not a gap.**
  Every consumer of the checked tree then sees every argument: the evaluator, discharge (which turns a named site that reads a section `GIVEN` into a positional one), DMN's record guard (`length nes == length fields`), MLIR's `lowerRecordConstruction` (which allocates a slot per field and stores only the fields it is given), Relational's `queryArg`, Catala, and the document renderer (`l4 render` shows the whole construction, `colour is Red, …`).
  None of them has to know defaults exist, with one measured exception that is fixed: DMN's rule rows tell a constructor from a variable by the name's resolved info, and a default copied into a call site had lost it, so an enum default exported bare (`colour: Green`), which Camunda reads as a variable that does not exist (`null`, status success); the name now keeps its resolved info (`defaultValueAt`; the DMN export spec builds the same module with the field left out and written out and asserts the two agree).
  The alternative, leaving the argument out of the list and carrying the default in the node's annotation, would have been incomplete in each of those that was not taught: by reading the code (not measured), MLIR's `lowerRecordConstruction` would leave an unwritten slot, and Relational's flattened query input would lose a fact the evaluator had.
- **The printer leaves it out** (`isDefaultFill`, `L4.Print`): `l4 batch` re-emits its module, and a printed default is an explicit value, which takes no default and so reports none.
  The §3.2.1 evaluation differential was owed for that edit, and was run on 2026-10-03 over 433 corpus files: 272 give identical `Result:` blocks, 158 have none on either side, and three differ.
  `ok/every/run-blame.l4` differs only in the file name and line a refusal message embeds, the same on the W2+W3 binary.
  The other two are this branch's `ok/typically-named-site.l4` and `ok/typically-import-use.l4`, whose printed copy does not parse back, because an `#ASSERT (f WITH a IS 1, b IS 2) EQUALS n` prints its second named argument on a new line inside the parentheses; that is the printer's layout of an explicit multi-argument `WITH` in a directive, which this branch did not change (it is not seen by `l4 batch`, which filters directives before it prints).
  With those directives rewritten as `#EVAL`s the printed copies agree with the originals, 15 of 15 and 6 of 6 results, and the printed text leaves the default out.
- **The event.**
  When `App` allocates an argument that carries a `DefaultFill` it registers it with W8's registry (`registerPresumable`, origin `FromNamedApp rule`), so the event is raised the first time the value is forced and not before: an input the rule never reads is not listed (T6; `use` FALSE in the batch and service tests lists nothing).
  The path is the one input or field; the origin carries the rule or record.
  A default that is a bare constructor (`TRUE`, `FALSE`, `NOTHING`, an enum value) is given a cell of its own when the argument is allocated (`allocateArgument`): a bare constructor is a `Var`, and a `Var` argument is normally the one cell every use of that name shares, so registering it would have reported the default whenever the same constructor was evaluated anywhere later in the run, and would have let two defaults of one constructor take one registry slot between them.
  The check `App` now makes on each argument is one constructor test (`exprDefaultFill`).
  Measured on `fib 27` (`l4 run`, five interleaved runs each): 1.15 to 1.24 s on this branch, 1.16 to 1.23 s (and one 1.49) on the W2+W3 binary, so no cost shows.

**What it does, by ruling.**

- **R8 rule 1 / W4.** `scaled WITH base IS 10` takes `rate TYPICALLY 3` (p2: `30`; `WITH base IS 10, rate IS 2`: `20`); `scaled 10` is still "expects 2 inputs, but here it is given 1"; `scaled WITH rate IS 1` still reports `base` unsupplied; and an unknown name is still an error of its own, so a misspelt `rate` is not read as a default taken (`not-ok/tc/typically-named-site.l4`).
  The one misspelling this cannot catch is a name that is itself another input the callee reads, a section `GIVEN` the site may override: `scaled2 WITH base IS 10, ratee IS 2`, where the author meant `rate` and the rule reads a section input `ratee`, is a valid override of `ratee`, and `rate` takes its default (`32`, exit 0, measured on the review's `typo-binder.l4`).
  Before W4 the required `rate` caught it; that is the price of R8 rule 1 and a name check cannot tell the two apart.
  A misspelling that matches nothing the callee reads is still caught, and so is a supplied binder the callee does not read ("This call supplies `ratee` but `scaled` does not read it", measured).
  It holds for a rule in the same file, one declared in a `WHERE`, a recursive call, and one in an imported file; and together with a section `GIVEN` the rule reads, in any order of the written arguments (`ok/typically-named-site.l4`, last section: `130`, `31`, `51`).
- **T1, T1b and D7.3 / W5.** `Paint WITH coats IS 2` takes every other field's declared default (p4: `c's timeout` is `30`), a number, a string, a boolean, an enum constructor (p10) and `NOTHING` for `MAYBE … TYPICALLY NOTHING` alike; the order of the written fields is free; a field with no default is still required, and a positional construction still gives every field.
  Only a record's fields: an enum constructor that carries data keeps requiring its fields, and a `TYPICALLY` on one of those fields is accepted and does nothing (a bench card is owed; see "Not built here").
  How to write a construction in which EVERY field is defaulted is still open (T1); no spelling is invented, and the documentation page says so.
- **T1's check error.** A `TYPICALLY` on a field with a `MEANS` clause is now a check error, `TypicallyOnComputedField`, at the field (`not-ok/tc/typically-computed-field.l4`).
  Read off the parsed module (`detectTypicallyOnComputedFields`), because `desugarComputedFields` moves the field out of its record, and its `TYPICALLY` with it.
  One file in this repository did it, `ok/typically-basic.l4` (`taxed`), under a comment calling the `TYPICALLY` "inert metadata"; the field and the comments are changed without moving a line, because `QueryPlanSpec` pins that file's ladder atom ids (unmoved: `jl4-service-test` below).
  It reaches a record's fields only: on an enum constructor that carries data a `MEANS` is not desugared and is ignored outright (measured on the W2+W3 binary and on `unstable`: `area IS A NUMBER TYPICALLY 4 MEANS w TIMES w` is a stored field, and `Rect 2 5` gives `area` 5, with no diagnostic), so a `TYPICALLY` beside it raises nothing.
  That is settled with the payload-field card below, which has to say what a `MEANS` there means first.
  None in `doc/`, `jl4-core/libraries` or `skills/`; none in `legalese/canon` (searched 2026-10-03 at `6b6476d`, its own checkout; `l4 check` of its three files that carry a `TYPICALLY` gives no diagnostic on this branch, as on the W2+W3 binary).
- **p10's message (L4).** A default naming something that is not in scope is reported once, as that: `checkTypically` no longer raises "must be a literal" for an `OutOfScope` reference, on a field or on a rule's input (`not-ok/tc/typically-unresolved.l4`).
- **T4 and T4b.** A default taken at a named site or a construction is inside the rules, where no request can supply the value, so presumption does not withdraw it: `--presumption hard` and `"presumption": "hard"` take it as soft does, and under hard the answer says it rests on it (below).
- **T6 and T6b.** Each default taken at a named site or a construction raises W8's event itself.
  Under hard it is listed in `presumed` as `WITH rule: input` (`WITH scaled: rate`) or, for a record, `WITH Config: timeout`, with the rule or record named as its declaration writes it (not an `AKA` alias, not section-qualified, a mixfix rule by its declared name), only if it was forced, on `l4 batch` and on the service's direct and wrapper path; under soft it is not listed, as T6b's filter says (below).
  The request's own input of the same spelling is never listed for it (the batch and service fixtures name the exported rule's input `rate` on purpose).
  `#EVAL` lists nothing, as it never did for a default taken at the root: the trace rendering is W8's and is not built.

**Decided by Claude overnight 2026-10-03, pending Meng's review.**

- **A default taken at a named site or construction is listed in `presumed` under hard, and not under soft.** In its own commit, so that it can be reverted alone.
  T6b names these sites ("W4's named sites and constructions emit W8's event themselves. The trace shows every event; `presumed` keeps only those whose binder or JSON path is part of the request"), and the binder of `rate` in `scaled WITH base IS 10` is part of no request; T4b's "elsewhere the result says 'rests on presumed x'" is about the off switch.
  Read together: listed under hard, filtered under soft, which is how a rule's own `JSONDECODE` is treated (`JSONDECODE T: field`, under hard only).
  Under soft every entry in `presumed` is then a name a client could have sent, as it was in #539.
  _Alternatives:_ (b) list it in both modes, which reads T4b's first sentence ("every default that took effect, wherever filled") alone, and is a one-line change (drop the guard on the `FromNamedApp` case of `requestPresumed`, `L4.EvaluateLazy`); (c) never list it, trace only, which reads T6b's filter alone and loses "rests on presumed x" under hard.
  The reconciliation of T4b and T6b is also noted under T6 in §5.

- **A default crosses an `IMPORT`.** In its own commit, so that it can be reverted alone.
  R8 says nothing about imports, and a default that stopped at the file boundary would be a third behaviour: the same line of source, a loud error in one file and a default in the next.
  The tables travel as `implicitReaders` does (`CheckResult.inputDefaults`, `unionImportedCheckEnv`, `tcdInputDefaults`, the LSP's `TypeCheckResult`).
  _Alternative:_ stop at the boundary, where an imported rule's omitted default stays the "you have not supplied these inputs" error.

- **A named site whose callee is an overload takes no default.** In its own commit.
  R8 does not rule on overloads. With `scaled(rate TYPICALLY 3, base)` and `scaled(base, factor)` in scope, `scaled WITH base IS 10` was ambiguous before W4, and became the first `scaled` run on a presumed rate, with exit 0; it stays ambiguous (`not-ok/tc/typically-overloaded-site.l4`).
  The checker records, on each branch of its search, the callee it chose when more than one candidate survives, with the types of the others (`CheckState.overloadedCallees`); the named site reads it straight after its name resolves, from a mark cleared just before, so it describes that site and no other.
  A `WHERE`-local rule that shadows a global one is not an overload (shadowing leaves one candidate) and still takes its default.
  _Alternative:_ take the default when exactly one overload becomes complete by it.
  _Over-reach found in review and fixed (silent N2 and N3, rulings R2-1)._
  The mark used to persist for the rest of the module, so one site that had to choose among overloads took the default away from every later site of the chosen rule, a section-qualified one included, and whether a default was taken depended on the order of the declarations (`#EVAL scaled WITH base IS 10, rate IS 2` above ``#EVAL `Pricing`.scaled WITH base IS 10`` failed; the other order checked).
  And every other survivor counted as a rival whatever it was, so a rule that shares its name with a record field (`amount`, `discount`, `rate`: an ordinary pattern) lost W4 at every named site and reported a false ambiguity between the rule and a field that takes no named inputs, while `l4 batch` took the default for the same rule.
  A rival now counts only if it could take the inputs the site names (`couldTakeNamedSite`): a function with a named parameter, a bare definition only when every name the site gives is a section binder, a type still being inferred (to stay loud), and a record field selector never.
  Still ambiguous, as ruled: two rules, or a rule and a function of the same name, that could each take the site's inputs (`ok/typically-site-names.l4` pins what is no longer an overload; `not-ok/tc/typically-overloaded-site.l4` what still is).

- **An event's party or action record in the service takes no default: a field it leaves out is refused, in both modes.** In its own commit.
  This is built differently from T1, and is a stop-gap, not a question for Meng: T1's "absent in JSON, taking its default" answers it (soft takes, hard refuses), and the faithful reading is owed (below).
  The deontic wrapper builds each event record as source, which since W5 would fill an omitted field from its `TYPICALLY`, under hard as well, and list it as a default no request could supply; the filled default changed which party the event matched.
  Soft cannot simply take it yet, because the deontic machinery reads a party without forcing it (§4.1), so a default taken there would be used and never listed in `presumed`: silent, where T6 asks for listed.
  The service therefore refuses the request before building the wrapper, naming `events[0].party.licence`, as it was loud before W5.
  The arguments' own records are decoded from JSON and keep the switch.
  A record NESTED in an event's record is generated as source too, and the first version of the refusal looked only at the top level, so a nested record's left-out field was filled in both modes and the event stopped matching its party, with status success (review rulings R2-2: `{"zhome":{"Address":{"zip":5}}}`, `floor` 1 against the argument's 2).
  The refusal now walks the shapes the code generator turns into `Con WITH field IS …`, a constructor-keyed object, an array, or a constructor applied to one argument, and names the path the request wrote it at: `events[0].party.zhome.Address.floor` (`jl4-service-test`, "refuses an event whose nested record leaves out a defaulted field, in both modes").
  _Follow-up owed, T1's reading:_ decode the event records as the arguments are, so that soft takes the default and lists it as `events[0].party.licence` and hard refuses it; it needs the wrapper to carry the events through the request decoder, and a party read that counts as a force.

- **`l4 render` and `l4 nlg` mark a value the checker added: "`rate` is 3 by default".** In its own commit.
  A rendered document is read by someone who never sees the source, and "`rate` is 3" is what a module that writes `rate IS 3` renders to, so the text now says the value is a default.
  A value the author wrote is unchanged.
  The Hebrew phrasebook has a draft entry for the phrase.
  _Alternative:_ show the added argument as a plain one, or hide it.

- **The owner in a `presumed` entry is the rule's or record's own name as its declaration writes it, not section-qualified.**
  `WITH Pricing.scaled: rate` and `WITH rescaled: rate` (an `AKA` alias) both leaked from the callee's resolved name; the entry now carries the owner with the default (`InputDefault.owner`), so it does not depend on how a site spelled the callee, or on an `IMPORT`.
  _Alternative:_ section-qualified, `WITH Pricing.scaled: rate`, which tells two same-named rules in different sections apart.
  _Two limits, for the card on the `presumed` surface (review rulings R2-3, advisor D4)._
  Two rules or records of one name in different sections give one entry: rows taking `` `A`.scaled ``'s `rate` (3), `` `B`.scaled ``'s (5) and both (8) all list `WITH scaled: rate` under hard, so a row that rests on two defaults lists one and nothing says which default either was.
  And `presumed` now has three string shapes, `rate`, `JSONDECODE T: path` and `WITH scaled: rate`, which a client tells apart by prefix; T4b asks for the mark "with its declaration line", and a structured entry (origin, owner, path, declaration line) would carry it, but is a change of the wire.
  Neither is changed overnight.

**Assumed, not ruled** (no one outside the code would notice, or the text is new):

- The shape of the entry: `WITH callee: input`, after `JSONDECODE T: field`; `WITH Config: timeout` for a record's field.
- The missing-input message now lists only the inputs that have no default ("you have not supplied these inputs: base"); it used to list every one left out.
- The error text for `TypicallyOnComputedField`, and that it points at the field.
- A written `ASSUME`'s inputs take no default at a named site, in the file that declares the `ASSUME` and in a file that imports it alike (`not-ok/tc/typically-assume-input.l4`), which is what W6's deferral leaves; before this, the same site checked in the declaring file and failed across an `IMPORT`.

**Not built here, and why.**

- W6 (`ASSUME … TYPICALLY`): deferred, by Meng's word (§4).
- A construction that leaves out every field: T1 leaves its spelling for a later card.
- An enum constructor's payload fields: a field of `Rect HAS width IS A NUMBER, height IS A NUMBER TYPICALLY 1` still has to be given at `Rect WITH width IS 2`, and its `TYPICALLY` does nothing.
  T1 as printed ("any field declared `TYPICALLY` may be omitted at construction") does not say records only, so this is a ruling for Meng and not an assumption.
  Recommended: open them, with the same table keyed by the constructor (`recordInputDefaults`); additive, since no `DECLARE … IS ONE OF` block in `jl4/examples`, `doc/`, `skills/`, `jl4-core/libraries` or `legalese/canon` (at `6b6476d`) has a `TYPICALLY` (scanned 2026-10-03, by block, not by grep for the keyword), and every such omission is an error today.
  If declined, make a `TYPICALLY` on such a field a check error, so that the annotation is never inert; that would also settle a `MEANS` there (above).
- **T4b's check-time warning on a construction that restates a field's `TYPICALLY` literally.**
  Not built, so S3 is made avoidable and not closed (§3).
  The warning would fire in two files of the vendored canon mirror, `canon/sg/succession/sg-succession-domain.l4` (`the orthodox reading`, `the per capita reading`) and `canon/sg/child-support/sg-child-support-domain.l4` (`the live reading`), and add diagnostics to their goldens, which this repository may not edit; and the two all-defaults constants cannot stop restating until T1's spelling for "every field defaulted" is ruled, so there would be nothing to change them to.
  It can land once canon has dropped the restated constants it can drop, has re-blessed, and the pin is bumped, with a construction that restates every default of its record exempt, or the spelling ruled.
- The trace rendering of the event (W8's second half) and `#EVAL`'s listing of it.
- `l4 batch` re-declares an exported rule's input types at the END of the module, so an export whose input is an enum or record type fails when a later section declares a type of the same name (silent X1: `agree-enum.l4`, where `#EVAL f WITH k IS 1` answers `101` and `l4 batch` reports "expected `Colour` (…:3) but is here of type `Colour` (…:17)").
  It does not depend on a default (re-measured: the same file without the `TYPICALLY`, and with the field sent, fails the same way), and the review measured the same failure on the W2+W3 binary (not re-run), so it is the wrapper's, not W4's or W5's; it is not fixed here.
- A reader that peeks at a thunk without `evalRef` (the deontic machinery's reads of a party) does not report a default; unchanged from §4.1.
- W7 (expression defaults): built since, in §4.3. `defaultValueAt` learnt the new shapes there, the cycle check runs in the checker's whole-module pass, and the type a default carries across an `IMPORT` is kept when it is closed (the advisor's D2 above, revisited together with `defaultValueAt` as asked).

**Review fixes (2026-10-03).**
After the two adversarial reviews (one for silent failures, one for fidelity to the rulings), beyond what is recorded above.
Each code fix has its own commit and a test that failed before it.

- A default that is a bare constructor is reported only if read (`allocateArgument`; four batch cases and a service case, which run under hard because that is where `presumed` lists such a default).
- An enum default exports to DMN quoted, as the field written out does (`defaultValueAt`; Camunda 8.7.6 on JDK 21: 2/2 values as expected, where it was `colour=null`, 1/2 FAILED).
- The owner in a `presumed` entry is the declaration's own name (above).
- A written `ASSUME`'s input default is not honoured at a named site, in either file (above).
- `doc/reference/types/TYPICALLY.md`'s stale sentences are removed (the section `GIVEN` as "the one place a default changes what a rule works out", and the `ASSUME` default "as everywhere outside a section `GIVEN`"), and the three pages that say what `presumed` lists now say hard only.
- The W5 row of §4 cites `supplyAppNamed` by name and not by a line number that had moved.

**Review fixes, second round (2026-10-03).**
After a second pair of reviews, of `13c3d00ae` (the first round's fixes included).
Each code fix has its own commit and a test that failed before it (the previous binary is the control in each commit message).

- **The performer of an action is read in declared order** (silent N1, `typecheck: the performer of an action is read in declared order`).
  `subjectOfActionExpr` took the first party-typed argument of a named application in the order the arguments were written, and a default the checker adds comes last, so an action whose subject field was left out to a `TYPICALLY` was performed by the next party and `PARTY Bob MUST hello` was accepted for a `hello` that Alice performs (a loud refusal before W5).
  It now reads the callee's order list, as `Dmn.Analysis.namedArgsPositional` does, and leaves out a section binder the site overrides.
  Labelled overnight because it also changes a verdict that is older than this branch: a named construction that WRITES its party fields out of declared order was accepted before (the writer's first one decided) and is now rejected, as the subject-first canon says.
  _Alternative:_ sort only when the checker added an argument.
  `ok/typically-actor-default.l4` and `not-ok/tc/typically-actor-default.l4`.
- **The overload mark is read at its own site and a record field is no rival** (silent N2 and N3, rulings R2-1; above, under the overload decision).
  `ok/typically-site-names.l4`.
- **A record nested in an event's record is refused too** (rulings R2-2; above, under the event decision).
  `jl4-service-test`, "refuses an event whose nested record leaves out a defaulted field, in both modes".
- **Text that claimed more than the behaviour** (silent N4, N5, rulings R2-4): "a misspelt `rate` is never read as a default taken" (above, under R8 rule 1, now with the one case it cannot catch); two sentences that said `presumed` lists a default taken inside the rules, which under soft it does not (`jl4-service/README.md`, the skill's entry 7.4); the line under T6 in §5, which said T4b's mark "is the trace's" and now names the conflict between T4b and T6b and what soft gives up; and, found by searching for the same claim in the other pages, `doc/courses/advanced/module-a4-production.md`, which said a default on a field or a rule's input "is metadata only" inside a file.
- **Recorded, not changed:** the two limits on `presumed` entries (R2-3, above); an event's record under soft is built differently from T1, and the faithful reading is owed (R2-5, above), so it is not a question for Meng; T4b's check-time warning stays unbuilt (R2-6, "Not built here"); and the tutorial's "The file and the boundary agree" is now "A call inside the file may leave out the same things", because `l4 batch` cannot run an export whose input is an enum or record type when a later section declares a type of the same name (silent X1, "Not built here").

**What does not change.**
Positional calls (R8 rule 1).
`WITH` as the one override (R9).
The JSON boundary's treatment of an absent `MAYBE` field as `NOTHING` (D7.3).
The query plan's use of a boolean default as a soft prior (`VizExpr.hs`, `typicallyTrueWeight`).
That prior orders questions and never answers one, which is already the one behaviour applied to elicitation.

### 4.3 W7, as built (2026-10-03)

Built in `feat/typically-w7`, on top of `feat/typically-w4w5` (at `fb447543d`).
It was built twice.
The first build was seven commits (kept as `backup/typically-w7-round1`) and was reviewed on 2026-10-03, once for fidelity to the rulings and once for silent failures.
This is that build rebased onto the W4+W5 branch as it now stands, then one decision commit and five fix commits for what the reviews found (see "Review of the first build", below).
Everything below was measured on this branch's own `l4` and `jl4-service`.
The corpus files `ok/typically-expression.l4`, `-sites.l4`, `-supplied.l4`, `-multiarg.l4`, `-import-def.l4` and `-import-use.l4`, the not-ok files `not-ok/tc/typically-cycle.l4`, `typically-non-literal.l4`, `typically-expression-places.l4`, `typically-default-reads-input.l4` and `typically-with-on-input.l4`, `not-ok/import/default-refused.l4`, and the semantic-token file `lsp/semantic-tokens/typically-expression-fill.l4` pin it, with the CLI tests ("l4 batch: a section input's TYPICALLY that is an expression (W7)" and "l4 batch: a rule's input and a record's field take an expression too (W7)", over `batch-typically-expression*.l4`, `-reads-input.l4` and `-multiarg.l4`), the service tests ("…(W7)", over `expressionDefaultJL4`, `expressionAllDefaultJL4`, `expressionSiteDefaultJL4` and `expressionMultiargJL4`), the "export read-set through a TYPICALLY default" block of `ExportReadSetSpec`, and `CatalaLowerSpec`.

**The ruling, clause by clause.**

| clause of R8 rule 3                                                            | what it does now                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | where                                                                                                                    |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| "a default is a module-scope expression"                                       | `checkTypically` no longer asks for a literal. The parser needed nothing: it already takes an atom or a parenthesised expression after `TYPICALLY` (`atomicExpr'`), so `TYPICALLY (list price DIVIDED BY 10)` parses today and a bare name or a literal needs no brackets. On a **section `GIVEN`** it may read other section inputs. On a **rule's `GIVEN`** and a **record field** it may name definitions and constructors and **may not read a section input**, directly or through a definition: that is a check error (decision 1). It may not name, by spelling, another input of its own rule or another field of its own record (decision 5), and a field's is looked up in the section its `DECLARE` is in, as a rule input's is (decision 6). A rule's default is checked once every signature has been scanned (`PendingDefault`, `checkPendingDefaults`), because at scan time no definition is in scope yet, which is what made `rate TYPICALLY phi` fail as "could not find a definition" (p4 of the W7 probes). A plain literal is still checked at once, so every error a literal raised stays where it was.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | `TypeCheck.hs` `checkTypically`, `scanTypicallyOpt`, `withScanTypeAndSigEnvironment`; `Discharge.hs` `inputDefaultReads` |
| "may name another binder or a definition"                                      | `beta TYPICALLY phi` (p5: `#EVAL doubled` is `16`, with `beta IS 5` `10`); `discount TYPICALLY (list price DIVIDED BY 10)`, a chain of three, and a default that calls a definition that reads a binder all evaluate (`ok/typically-expression.l4`, 19 directives, 14 of them assertions).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `Discharge.hs`                                                                                                           |
| "is evaluated lazily at the root"                                              | **Section `GIVEN`.** The binder is still the module-level 0-ary definition of its default, a shared thunk worked out once. A default that reads other binders also gets a function of what it reads (`defaultFunctionDecl`, one per such binder, `defaultThunkUnique`), and a ROOT, which is a directive and so also the service's and `l4 batch`'s call, passes that function applied to its own values: `#EVAL final price WITH list price IS 200` gives `180`, not the `90` the module-level definition would, because `discount` is a tenth of the 200. A root is a matter of where a call is WRITTEN: everything written inside a directive is at the root, a lambda included, and nothing written inside a rule is (`implicitSupplySitesAt`; second review, silent S5). So `#EVAL final price WITH list price IS 1000` is `900`, the same call written as a rule is `990`, and an `#ASSERT` that compares the two fails. Whether a root should be where an evaluation starts instead is Meng's (Open for Meng 4). An inner `WITH` still does not reach a default the root already worked out: `` `priced as if dearer` MEANS `final price` WITH `list price` IS 1000 `` is `990`, from the root's 100. **Rule `GIVEN` and record field.** The default is copied to the site that leaves it out (`defaultValueAt`, every source annotation of the copy cleared, `DefaultFill` on its root). It reads only definitions and constructors, so it has the one value wherever it is worked out and "at the root" and "at the site" are the same thing. The JSON decoder, which has no site, evaluates a field's default in the module's environment (`allocateFieldDefault`, `EvalState.globalEnv`). | `Discharge.hs` `flowedAt`; `TypeCheck.hs` `defaultValueAt`; `Machine.hs`                                                 |
| "a cycle `b ∈ R*(default(b))` is a check error"                                | `TypicallyCycle`, one error per circle, naming the section `GIVEN`s on it and reported at the first (`not-ok/tc/typically-cycle.l4`: itself, a pair, through a definition, three round). `b TYPICALLY (g WITH b IS 1)` is no circle: the `WITH` supplies what the default would read, and neither is a pair of defaults one of which supplies what the other reads (`ok/typically-expression-supplied.l4`). Only section `GIVEN`s are nodes, as R8 writes `b`; see "Not built" for a rule's own default.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | `Discharge.hs` `defaultCycles`; `TypeCheck.hs` post-pass                                                                 |
| "the default's read-set joining the requirement of every root that may use it" | A defaulted section binder is a node of the call graph under its own `Unique` (`decideBodiesFromModule`), so whatever reads it is charged with what its default reads, and so is whatever takes it as a parameter. The pass computes what each definition reads itself first, with a call site's `WITH` subtracted, and then closes each set under the defaults of the binders in it (`readSetsAll`): the subtraction acts on the first and the closure is what a root is asked for. Consequences measured: a `WITH` for an input only a default reads is accepted at a root (`price with handling WITH list price IS 200` is `187`) and refused when it is written inside a rule, as it was before defaults could read inputs, because it would go nowhere (second review, silent S4); a rule that overrides that input for part of its own work still takes it from its root (`priced as if dearer WITH list price IS 200` is `980`); and an export's inputs include it. `readSets` leaves the binders themselves out of its result, which is how the hazard that deferred this rule (§11.5 of `IMPLICIT-PROPS-DESIGN.md`: a reference to the binder rewritten into an application) is avoided.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | `Discharge.hs` `readSetsAll`; `Export.hs`                                                                                |
| "the JSON schema gives the default as source text when it is an expression"    | `typicallyToJson` returns the default's source text, printed by `prettyLayout`, as a JSON string: `"default": "`list price` DIVIDED BY 10"`, on the service's schema, the LSP's, and the query plan's. A call that names several inputs is on one line, comma-separated (`"combine WITH a IS 2, b IS 3"`). A literal and a bare constructor are as they were. `typicallyIsExpression` tells the two apart.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `FunctionSchema.hs`; `Print.hs`                                                                                          |

**How the tests were shown to fail before.**
`l4 check`, errors counted, on the W4+W5 binary (`wseries/w4w5/snap/l4`, the base of this branch), on the first build of W7 (`wseries/w7/snap/l4` before this build overwrote it) and on this build:

| file                                               | W4+W5                  | first build                  | now                                                                                |
| -------------------------------------------------- | ---------------------- | ---------------------------- | ---------------------------------------------------------------------------------- |
| `ok/typically-expression.l4`                       | 10                     | 0                            | 0                                                                                  |
| `ok/typically-expression-sites.l4`                 | 9                      | 0                            | 0                                                                                  |
| `ok/typically-expression-import-use.l4`            | 10                     | 0                            | 0                                                                                  |
| `ok/typically-expression-multiarg.l4`              | 5                      | 0                            | 0                                                                                  |
| `ok/typically-expression-supplied.l4`              | 5                      | 1, the false cycle           | 0                                                                                  |
| `lsp/semantic-tokens/typically-expression-fill.l4` | 3                      | 0                            | 0                                                                                  |
| `not-ok/tc/typically-cycle.l4`                     | 8, "must be a literal" | 4 cycle errors               | 4 cycle errors                                                                     |
| `not-ok/tc/typically-expression-places.l4`         | 4                      | 2                            | 2                                                                                  |
| `not-ok/tc/typically-non-literal.l4`               | 1                      | 1                            | 1, a pin: it is now an `ASSUME`, and fails if an `ASSUME` ever takes an expression |
| `not-ok/tc/typically-default-reads-input.l4`       | 12                     | 0, nothing refused           | 3, one at each marked default, and two controls raise none                         |
| `not-ok/tc/typically-with-on-input.l4`             | 2                      | 1, reason "does not read it" | 1, reason "an input and not a rule"                                                |
| `not-ok/import/default-refused.l4`                 | 1                      | 0, and a run-time crash      | 1, the cross-`IMPORT` refusal                                                      |

The W4+W5 checker refuses the module of `batch-typically-expression-all.l4`, which has the shapes `expressionAllDefaultJL4` has, with "The TYPICALLY value for … must be a literal" for `discount`, `rate` and `timeout`; the service deploys through the same checker.
The "before" of the behaviours the second build changed was measured on the first build's binary and service: batch fails both rows of `batch-typically-multiarg.l4` at the second argument, the service's generated-module path fails likewise ("unexpected b"), the schema's text carries a newline and column padding, `JSONDECODE` in a default across an `IMPORT` gives `RIGHT OF NOTHING`, and the three silent disagreements of decision 1 below give 1025 against 25025, 5020 against 5050, and 60 against 30.

**Closes L5** (§3), and p5. p4 of the W7 probes, `GIVEN rate TYPICALLY (phi PLUS 1)`, was the same defect on a rule's input, and stays closed for a default that names a definition.

**Cost.** `fib 27`, `l4 run`, five interleaved runs each on a machine that was loaded by other builds (load average about 5.6): 0.80 to 1.03 s on the W4+W5 binary and 0.85 to 1.02 s on this branch.
The first build of the change measured about twice that, 1.55 to 1.88 s: `exprDefaultFill`, which `App` reads on every argument it allocates, had become the generic `getAnno`.
It is a plain case again, exhaustive on purpose, so that a constructor added to `Expr` is a compile error there until it says where its annotation is.

**The §3.2.1 evaluation differential** (owed: `L4/Print.hs` changed twice, once to bracket a default that is not an atom and once to print several `WITH` arguments on one line). Run on 2026-10-03 on the final binary (the copy at `wseries/w7/snap/l4`) over 441 printed copies (`JL4_EVALDIFF=1 … -m "prettyLayout round-trip"`), comparing the `Result:` blocks of `l4 run --fixed-now 2026-01-01T00:00:00Z` on each original and its printed copy: 280 identical, 160 with no `Result:` block on either side, and 1 differs.
`ok/every/run-blame.l4` differs only in the file name and line a refusal message embeds (`run-blame.l4:161:16-47` against `run-blame.l4.evaldiff.l4:92:59-96`).
The first build had six differences.
The other five (`ok/typically-named-site.l4`, `ok/typically-import-use.l4` and the three new `ok/typically-expression*.l4`) were one printer defect, a multi-argument `WITH` inside brackets, which printed its second argument on a new line and could not be re-parsed; the printer commit fixes it.
A positive control, an extra `#EVAL` on the printed side of one pair, reads DIFF (5 results against 6), so the harness can fail.
The printed copies were deleted afterwards.

**What the surfaces do with an expression default (T5, "map or say").**

| surface                                      | W7                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | why               |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| `#EVAL` / `l4 run`                           | worked out, as above                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | R8                |
| `l4 batch`                                   | worked out from the row: a section input's default through the wrapper's `InputArgs`, whose field carries the default as source text (`prettyTypicallyOperand`, which brackets anything but an atom and prints several `WITH` arguments flat, so it re-parses), a rule input's the same, a field's by the decoder. `presumed` lists each. Under `--presumption hard` none is taken, as for a literal. **Limits:** the text is put after the last section of the module batch generates and read again there. A name two or more sections define is read there as the last section's, when that section defines it, with no message (measured 2026-10-04: 16 at `#EVAL` and the service, 18 through `l4 batch`, for a section input's default; §4.4), and when the last section does not define it the rows are refused, naming a file batch generated. A name defined in a section and also at the top level would mean the file's there with no error (measured on the head: `99` at `#EVAL`, `11011` through batch), so an exported rule's default may not name one (decision 7). Written with its section (`` `Rates`.phi ``) it is neither. A default that supplies a section input the export also reads, and any inner `WITH` on a section input in an exported rule's body, make `l4 batch` refuse every row (older than W7, measured on the base). | W3                |
| service, direct and wrapper path             | the direct path adds each as a root fill, which discharge sees like any definition, so it reads the request's values and has no scope limit. The generated-module path (a request that sends `{}` for any input) writes each default it does not fill at the root as text and has the limits of batch (measured on the head with `phi`, above: `10019` against `99` for a request that sent `{}` for a boolean; and for a name two sections define, an exported rule's input default reads the last section's through it, §4.4). It used to refuse a request that supplied a section input whose default reads another, or that sent `hard`, with a message about a record the author never wrote (second review, silent S3), and answers it now.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | W3                |
| service schema `default`                     | source text, a string (above). **A client must not fill from it** (`doc/reference/types/TYPICALLY.md` says so), and for an input of type text cannot tell it from a literal; a marker key was not added (open for Meng 2)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | ruling            |
| Catala                                       | **mapped**: `context rate` with `definition rate equals (phi + 1.0)`, and `phi` carried with the scope. The helper collection read only bodies, so it said `phi` "was not collected as a helper; that is a lowering bug" on the first expression default that reached it; `bodyRefs` now reads each input's default. A **section** `GIVEN`'s default, literal or expression, is `input discount` with no note, as on the base (review F9, measured): that is W9's                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | R10               |
| docassemble                                  | **refused**, as before: "unsupported TYPICALLY default — v1 accepts literals and nullary enum constructors only"                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `lowerDefaultLit` |
| ladder, query plan                           | an input with an expression default carries `typically: null` in the ladder and lends no presumption weight to the plan, as an input with no default does; a literal's is `true` or `false`. **The plan does not ask for a fact that only a default reads, while the schema requires it**: for `is adult TYPICALLY (age AT LEAST 18)` it asks `is adult`, `is resident` and `has capacity`, and answering all three is refused for lacking `age` (second review, silent S10, re-measured on this build). Not said by the surface; recorded here (Open for Meng 5)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | T5                |
| `l4 trace`                                   | the function a root applies to work out a section input's default is shown under the name `default of <input>`, which no source declares (second review, silent S11). Said here                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | T5                |
| DMN, dmn-md, BPMN, OpenFisca, Blawx, yscript | not carried, and not said, **exactly as a literal default is not** on this branch: T5's note, and OpenFisca's mapping, are W9's (`feat/typically-w9`, whose `classifyDefault` has a `DefComputed` arm for the first expression default to arrive). See "Open for Meng" 3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | W9                |

**Decided by Claude overnight 2026-10-03, pending Meng's review.**

1. **A rule's input and a record's field may take an expression over definitions and constructors, but not one that reads a section input** (`typecheck: a rule's input or a record's field may not take a default that reads a section input`, commit `d9fc7635e`; `TypicallyReadsInput`, `Discharge.inputDefaultReads`).
   The first build let such a default read a section input and worked it out where the call or construction is.
   The review measured the same default giving different answers, with exit 0 and no diagnostic: `both WITH list price IS 4` is `1025` at an `#EVAL` root and `25025` through `l4 batch` for `rate TYPICALLY (100 DIVIDED BY list price)` on the export's own input; a field default reading `alpha` is `5020` against `5050` for the same inputs; and under an inner `WITH alpha IS 5` a rule input's default saw the 5 (`60`) while a section input's saw the root's 2 (`30`).
   R8's first sentence says a defaulted `GIVEN`, "section or function", is "filled in once per evaluation at the root", and its rule 1 says a function's own may be omitted only at a named site.
   For an expression that reads a section input those two give different answers (from the root's values, or from the site's), and R8 does not say which wins, so the conservative choice is the loud one: refuse the default that would depend on it.
   An earlier version of this paragraph said R8 "does not say where these are worked out"; it does speak to a function's `GIVEN`, and it speaks in two voices (second review, rulings D1).
   A default that supplies the input it would read (`` `double it` WITH alpha IS 1 ``) reads none and is fine.
   _Alternative:_ take the default at the call, as the first build did (that build is `backup/typically-w7-round1`), or work it out from the root, as a section's is, which threads the root's supplies into every site that takes a default and is the larger build.
2. **A written `ASSUME`'s `TYPICALLY` and a lambda's `GIVEN`'s stay literals.**
   An `ASSUME`'s default is ignored until W6, and an expression there would be a default that quietly does nothing; a literal already is.
   The old message stands (`typically-non-literal.l4` is now an `ASSUME`).
   _Alternative:_ accept an expression and ignore it, until W6.
3. **A section input that only another default reads is an input of the export, and `required`.**
   `PROPS-REDTEAM-2026-09-03.md` §2.5 rule 3 rules the requirement ("required unless `alpha` defaults too"); the first build recorded it as assumed, and the review found it was ruled.
   What is assumed is that the schema does not change with the mode: under `--presumption hard`, where no default is used, such an input is still asked for (review F5, measured on the CLI and on the service).
   _Alternative:_ drop it from the requirement under hard, which needs a requirement that knows which inputs only a default reads.

4. **A call that names several inputs prints on one line, comma-separated, wherever the printer prints one** (`print: several WITH arguments print on one line, comma-separated`, commit `83a678398`; review F3).
   It is a defect fix, and it carries the label because a reader of an output can see it: `prettyLayout` is also what `l4 batch` and the REPL re-emit a module through and what the DMN exporter falls back to, and the old form, one argument to a line, did not re-parse inside brackets.
   No existing golden moves (`jl4-test`, 3859 examples).
   _Alternative:_ flat only in a default's text, leaving a multi-argument `WITH` elsewhere on lines of its own.

5. **A default on a rule's input or a record's field may not name another input of its own rule, or another field of its own record, by spelling** (`typecheck: a default may not name another input of its own rule or record, by spelling`, commit `3faa82d62`; `TypicallyNamesSibling`, `Discharge.defaultNameCaptures`, asked of each default where it is checked; second review, silent S1, a blocker).
   A default is worked out where the rule's inputs and the record's fields are not in scope, so a name spelled like one of them means whatever else is called that.
   Where nothing is, it was reported as not in scope, as the documentation says.
   Where something is, it was accepted and the answer used it: `bonus TYPICALLY (salary DIVIDED BY 10)` beside the input `salary` and a definition `salary MEANS 50000` gave `6000` for a `salary` of 1000, through `#EVAL`, `l4 batch` and the service, while the schema printed the text that says the opposite.
   A name the author wrote with its section, a name the default binds itself, a section input's default (which may read the section's other inputs) and the record the service generates for a request are exempt.
   _Alternative:_ resolve such a name to the sibling input, which would make the default read an input of its own call.

6. **A record field's default is looked up in the section its `DECLARE` is in** (`typecheck: a record field's default is looked up in the section its DECLARE is in`, commit `a71b64f14`; second review, silent S2).
   It was looked up from the top of the file, so an author writing in a section got the file's definition of a name the section also defines (`2000`, and `2001` through an export where the same text on a rule's input was `16`), and a field's default went round decision 1 whenever a definition at the top had the spelling of a section input (`70`, no error).
   _Alternative:_ keep looking names up from the top of the file, or refuse a field default whose name resolves differently in the two places.

7. **An exported rule's input default, and a section input default that an export reads, may not name a definition that is in a section and is also defined at the top level** (`typecheck: an exported rule's default may not name a section's definition that the top level also defines`, commit `4d07a4572`; `TypicallyResolvedElsewhere`, `Discharge.defaultsMeaningElsewhere`; second review, silent S6 and rulings S1, a blocker).
   `l4 batch` and the service's generated-module path write each default into a module of their own and read it again at the top level, so such a name means the section's at `#EVAL` and the file's there: `99` against `11011` through batch, `10019` through the service, exit 0.
   When two or more sections define the name, nothing refuses it either: an exported rule's input default reads the last section's, through `l4 batch` and through the service's generated-module path, and a section input's does through `l4 batch` (§4.4).
   Written with its section (`` `Rates`.phi ``) the name is exempt, and every surface gives the same answer.
   _Alternative:_ print each such name qualified, as it resolved, where batch and the service write the text, so the default works as written and the F4 limit goes with it; the section paths are the data `sectionQualifiedWith` uses for diagnostics, and the service's `CompiledModule` would have to carry them.
   Or have both surfaces evaluate the checked expression, as the service's direct path does.

**Review of the first build.**
The review of the first build was two adversarial reviews, one of the rulings and one for silent failures, plus the advisor's note on W4 and W5 (D2).
What each finding became:

- **F1 (silent, blocker) and F2 (silent, major): a rule input's or a field's default reading a section input.** Decision 1.
- **F3 (loud, major): a `WITH` with several arguments in a default broke `l4 batch` on every row, the service's generated-module path, and the schema's text.** Fixed in `print: several WITH arguments print on one line, comma-separated`: `L4.Print` printed each argument on a line of its own, which parses only where the text starts a line, and a default is spliced after a prefix in three places. Several arguments now print flat, with a bracket round a value that has an open tail. One argument prints as before.
- **F4 (major): `l4 batch` and the service's generated-module path resolve a default's text in the module they generate.** Not changed. It is a limit, recorded in the surfaces table and in `doc/reference/types/TYPICALLY.md`, with the spelling that avoids it, and for a name that two or more sections define, when the last of them defines it too, it is silent (§4.4).
- **F5 (loud, minor): under hard, an input only a default reads is still required.** Not changed; decision 3.
- **F6 (loud, minor): a false cycle** (`a TYPICALLY (h WITH b IS 1)`, `b TYPICALLY (a PLUS 1)`). Fixed in `discharge: a default that supplies the input it would read is no circle`.
- **F7 (loud, minor): an export's own input default reaching an imported reader got past the cross-`IMPORT` refusal.** Fixed in `export: an export's input default that reaches an imported reader is refused like a body that does`. The crash underneath is older than W7 (an importer's call of an imported reader crashes the same way on the base and on unstable) and is not touched.
- **F8 (loud, minor): `discount WITH list price IS 200` was refused with a false reason.** Fixed in `typecheck: a WITH given to a section input says so, not that the input is unread`: it is its own error now. Giving `discount WITH …` a meaning (work its default out from these) was considered and not done; nobody has ruled it.
- **F9 (silent, minor): exporters drop an expression default without a word.** W9's; "Open for Meng" 3.
- **F10 (drift): spec and doc sentences that said more than the behaviour.** Fixed; the direct self-call of a default is a check error and only the indirect one overflows the stack.
- **D2 (advisor, W4 and W5): the type a default loses at an `IMPORT`.** Revisited with `defaultValueAt`, as the base asked. It matters: `JSONDECODE` takes the type to decode into from the node it sits on, so a record field's default `JSONDECODE raw` gave `RIGHT OF NOTHING` through an `IMPORT` and `RIGHT OF (Person OF "Bob", 25)` in the declaring module, with exit 0. Fixed in `typecheck: a default keeps its closed types across an IMPORT`: each node's type is resolved with the module's final substitution and kept when nothing open is left in it (`ok/typically-expression-import-def.l4` and `-use.l4`). `TODATE`, the other type-directed builtin in that frame, decodes the same either way.

**Second review of the rebuild (the night of 2026-10-03).**
Two reviewers, one for fidelity to the rulings and one for silent failures, read the head `98fcd3bfb` against the base, and an advisor read the decisions.
The first build's silent review had four findings that the rebuild neither fixed nor recorded (B1, M1, M4, m3); they are S1, S2, S5 and S9 below.
"S" is the silent review's number and "R" the rulings review's.
Each was re-measured on a fresh build before anything was changed.

- **S1 (silent, blocker): a default that names a sibling input binds to a definition with the same spelling.** True; decision 5 (`3faa82d62`).
- **S2 (silent, major): a field's default looks names up from the top of the file, and so went round decision 1.** True; decision 6 (`a71b64f14`).
- **S3 and R-S2 (loud, major): the service's generated-module path refused a request that supplied an input a default reads, and every one under hard.** True, and caused by decision 1 (`inputDefaultReads` scanned the record the service generates). Fixed: `bfd8e2de2`; the service test "answers a request on the generated-module path that supplies an input a default reads, or that reads one (W7)".
- **S4 (silent, major): a `WITH` inside a rule that reaches its callee only through a default was accepted and did nothing.** True, and a regression against the base. Fixed: `00ad4437e`, by testing a supply written below a root against what the callee reads itself (`readSetStages`).
- **S5 (silent, major, needs a ruling): "root" is where a call is written, so the same call is `900` in a directive and `990` in a rule.** True. Not changed, because what a root is belongs to Meng (Open for Meng 4); the documentation and the clause table now say what it is today, in those words.
- **S6 and R-S1 (silent, blocker): `l4 batch` and the service's generated-module path read a default's text again and pick the top-level definition of a name the section also defines.** True. Decision 7 (`4d07a4572`). The F4 limit, two sections defining the name, stays and is silent when the last section defines it too (§4.4).
- **S7 (loud, minor): a default that supplies the input it would read was refused for what that input's own default reads.** True. Fixed: `316465b37`.
- **S8 and R-S5 (loud, minor): a record field's default that reaches an imported reader, on a record an export takes, deployed and crashed every request.** True. Fixed for the records this module declares, nested ones included: `51761d66a`. A record declared in an imported module is not walked: its default can only reach that module's own readers, which no request of the importer can supply either way.
- **S9 (loud, minor): a default could not call a rule and leave out an input whose default is an expression.** True, and a function of the order defaults were checked in. Fixed: `aa6aca7a7` checks each owner after the owners its defaults call, for rules and for records.
- **S10 (loud, minor): the query plan never asks for a fact that only an expression default reads, and the schema requires it.** True, re-measured. Decision 3's cost, and not W7's to remove (Open for Meng 5). Recorded in the surfaces table and in `TYPICALLY.md`.
- **S11 (minor): published text and traces that say something other than the source.** A mixfix default is published by its leading words and `l4 batch` refuses it loudly; `l4 trace` shows `default of <input>`; the ladder shows `typically: null` for an expression default. Said, in the surfaces table and in `TYPICALLY.md`, not changed.
- **S12 (silent, minor): exporters drop an expression default.** W9's, as F9. `catala.md` overstated what is carried and is corrected: only a rule's own `GIVEN` default is.
- **R-S3 (loud, minor): the remedy the documentation gives for both new errors, a default that supplies the input it would read, makes `l4 batch` refuse every row when the export also reads that input.** True, and older than W7 (an inner `WITH` on a section input in an exported rule's body does the same on the base). Not fixed; the limit is stated where the remedy is given.
- **R-S4 (loud, minor): a written `ASSUME` that an export's own input's default reads could never be used.** True. Fixed: `04830d32b`. That fix, as first written, also made a section input an input of the export when the default supplies it, and `l4 batch` then refused every row of such an export; I found it by re-running the reviewer's `supplied.l4` after the commit, and `20ad85a73` restricts the closure to written `ASSUME`s.
- **R-S6 (drift): four sentences in the documentation and the spec said more than the behaviour.** Fixed.
- **R-D1: decision 1's premise, that R8 does not say where a function's default is worked out, was wrong.** The decision stands and its premise is corrected (above).
- **The advisor's eight notes** (W7-D1 to W7-D8) all agreed with the choices.
  Adopted: the four repairs to decision 1's implementation (the request record, the written-`ASSUME` closure, the field's section, the `WITH` subtracted before the closure); the reframing of Open for Meng 4; the cost of decision 3 recorded; the printer change kept; the `WITH`-to-an-input sentence softened (`993ea7dfd`); the cross-`IMPORT` refusal extended to field defaults.
  Recorded, not changed: the type residue of W7-D6, below.
- **W7-D6, the residue of the closed-type fix across an `IMPORT`.** A default node whose type still holds an inference variable after the final substitution is dropped as before, so `JSONDECODE` in such a default across an `IMPORT` would still decode to `NOTHING` silently. It needs a polymorphic record field's default, which is rare, and a refusal at that point would be better than the drop when someone gets to it.

**Tests the second review's fixes added, and how each was shown to fail before.**
`l4 run`, errors counted, on the snapshot of the head `98fcd3bfb` and on this build; the hspec, service and CLI cases are named after the table.

| file                                                  | head `98fcd3bfb`                                        | now                              |
| ----------------------------------------------------- | ------------------------------------------------------- | -------------------------------- |
| `not-ok/tc/typically-names-sibling.l4`                | 0 errors                                                | 2, and three controls raise none |
| `ok/typically-expression-field-scope.l4`              | 1: the field's default gives `2000` where `16` is meant | 0                                |
| `not-ok/tc/typically-field-reads-input-in-section.l4` | 1, the rule input's                                     | 2, the field's too               |
| `not-ok/tc/typically-with-through-default.l4`         | 0                                                       | 1, and the controls raise none   |
| `ok/typically-expression-supplied-chain.l4`           | 1: refused for reading `r`                              | 0                                |
| `ok/typically-expression-default-calls-default.l4`    | 2: "you have not supplied these inputs"                 | 0                                |
| `not-ok/tc/typically-default-resolved-elsewhere.l4`   | 0                                                       | 2, and a control raises none     |
| `not-ok/import/field-default-refused.l4`              | 0                                                       | 1                                |

`jl4-service-test` "answers a request on the generated-module path that supplies an input a default reads, or that reads one (W7)": the head's service refuses the three requests that supply `discount` and the answer is `195` or `99` now.
`l4-cli-test` "runs an export whose input's default supplies a section input": `200` and `300` on the head, refused on the build between (the closure of `04830d32b`), `200` and `300` now.
`ExportReadSetSpec`: the written `ASSUME` is listed, the supplied section input is not, and the imported-reader refusal covers a field, a nested record and an export input's default, each with a control.
I did not run the hspec cases against a pre-fix build of the suites, only the programs they use against the head's binaries.

**Found while probing, older than W7, not changed.**
On the service's direct path, a request's value for a section `GIVEN` overrides an inner `WITH` that the rules give it.
`priced as if dearer MEANS final price WITH list price IS 1000` answers `990` with no request value and `190` for `{"list price": 200}`; the same `WITH` at an `#EVAL` root is refused ("does not read it").
Measured on this build (the reviewer measured it on the W4+W5 build); it does not depend on a default.
The example of an inner `WITH` in `ok/typically-expression.l4` (`priced as if dearer`) runs into it on the service.
`l4 batch` refuses an export whose body has an inner `WITH` on a section input ("You are giving named inputs to `final price` … not a function"; review b05, b06, not re-run), and `l4 batch` re-declares an exported rule's input types at the end of the module (§4.2 "Not built here", silent X1).

**Assumed, not ruled** (no one outside the code would notice, or the text is new):

- The names `TypicallyNamesSibling`, `TypicallyResolvedElsewhere`, `defaultNameCaptures`, `defaultsMeaningElsewhere`, `readSetStages`, `implicitSupplySitesAt`, `dependencyFirst`, `authoredFieldGroups` (second review), and the text of their two messages, beside the names `TypicallyCycle`, `TypicallyReadsInput`, `ImplicitSupplyToInput`, `defaultCycles`, `inputDefaultReads`, `implicitSuppliesToInputs`, `defaultFunctionDecl`, `defaultThunkUnique` (sort char `q`), `allowsExpressionDefault`, `PendingDefault`, `prettyTypicallyOperand`, `typicallyIsExpression`, and the text of the three messages.
- A name inside a default that the checker recorded as something other than a constructor is an expression, so `typicallyLiteralValue` leaves it to the environment; one it recorded nothing about is read as the constructor it was before W7 (the schema) or evaluated (the decoder).
- A default's source text is `prettyLayout` of the checked expression, so it is the unqualified, backticked form, not the author's own spelling.
- `RequestField`, the record `l4 batch` and the service decode a request into, always allows an expression: it is not the author's, and the decoder works its default out at the root, as a section's is.

**Not built, and why.**

- **A check for a default that calls the rule or record it belongs to through another rule.** R8's `b ∈ R*(default(b))` is about section binders. `GIVEN x TYPICALLY (f 1)` where `f` calls the rule unconditionally runs out of stack at run time ("Recursion depth of 1000000 exceeded", measured), like any recursion, and a check error would also refuse the programs where `f` never forces `x`.
- **A rule's default that reads a section input, worked out from the root** (decision 1).
- **A marker beside the schema's `default`** that says it is an expression (open for Meng 2).
- **The exporters' notes for DMN, dmn-md, BPMN, OpenFisca, Blawx and yscript**: W9. This is the one place the brief's "a note or refusal is better than silence" is not met on this branch alone.
- **`l4 batch` and the generated-module path writing a name with its section**, which would remove the limit of F4 and the refusal of decision 7. The checker's section paths (`sectionQualifiedWith`) are the data, and the service's `CompiledModule` does not carry them.
- **Under hard, dropping the input only a default reads** (decision 3).
- **W6**, and so **T2b's "inputs-taking `ASSUME`s are reopened when W7 lands"**: that is a question for Meng (open for Meng 1), and W6 is deferred.

**Open for Meng.**

1. **T2b: does W7 landing reopen `ASSUME … TYPICALLY` for an `ASSUME` that takes inputs?** T2b says T2 covers module-level 0-ary `ASSUME`s "until W7 lands, when inputs-taking ones are reopened". Not built; W6 is deferred by your word and `ASSUME` is being deprecated. If W6 is ever built, say whether an `ASSUME` with inputs and an expression default is in it.
2. **The schema's `default` as source text is a string whatever the input's type.** A client that fills missing inputs from `default` (JSON Schema tooling does, with an option) will send the text. For an input of type text it cannot be told from a literal. The ruling says "as source text", so that is what is published, and the documentation tells clients not to fill from it. A marker key (`x-l4-default-expression: true`) on the property would let a client tell; it needs a field on `Parameter`, which ten construction sites would carry, so it was not added unasked. Say if you want it.
3. **The note for an exporter that cannot carry an expression default, and the order W7 and W9 land in.** The note is W9's. The prerelease shelf ships off `unstable`, so a W7 that merges before W9 lets six exporters drop every default, an expression one included, with nothing said, on the next cut. Either W7 merges with or after W9, or its pull request says in one line that those exporters are silent until W9. Which is yours.
4. **What a root is, and where a rule's or a field's default that reads a section input is worked out.** Decision 1 refuses such a default. R8 says it is "filled in once per evaluation at the root" and that a function's own may be omitted only at a named site; for an expression that reads a section input those differ, so say which should win: from the root's values, or from the site's. Both need "root" defined, and today it is syntactic: a call written in a directive is at the root, a lambda there included, and a call written in a rule is not, so `#EVAL final price WITH list price IS 1000` is `900`, the same call written as a rule is `990`, and an `#ASSERT` comparing them fails. Say whether a root is where a call is written, as it is now, or where an evaluation starts.
5. **The query plan and the requirement disagree for a fact that only an expression default reads.** The plan never asks for `age` where `is adult TYPICALLY (age AT LEAST 18)`, and the schema requires it, so a client that answers everything the plan asks is refused for lacking `age`. W7 did not cause it (decision 3 rules the requirement, and TU-wire-b parked the lazy binding on the direct path that would remove it), but it is W7 that makes defaults read inputs. The ways out are the lazy binding, or a schema that can say "needed only if `is adult` is left out" (`anyOf`). Which, if either, is yours.
6. **Canon's `regcf-denovo.l4` still carries a comment** (lines 134 to 135, at the canon commit `6b6476d`) saying the checker requires a `TYPICALLY` value to be a literal, which W7 makes stale. It is in `legalese/canon`, which this repository may not edit, so it is not touched here.

### 4.4 W10, as built (2026-10-04)

Built in `feat/typically-w10`, on top of `feat/typically-w7` (at `07b62714d`).
It is documentation and records: it changes no Haskell, TypeScript, corpus file or golden (`git diff --stat 07b62714d..HEAD` lists only files under `doc/` and `specs/todo/`).
The behaviour claims written or kept in the page, its example, the query planner's page and the `ASSUME` pages were checked on 2026-10-04 against `l4` and `jl4-service` built from this branch (the corpus files and CLI fixtures named below, and probes of my own: two scripts of 148 checks over the page's claims, the example, the planner's page, the `ASSUME` pages and the skill's worked examples, run on this branch's `l4` and `jl4-service`, all passing; six of them pin the two limits under "Found while checking" and will fail when a limit is fixed; the first script's "before" block passes 6 of 6 on `unstable`'s `l4` (`7768812fa`) and 1 of 6 on this build, so the checks tell the two apart; the scripts and their output are in the build report's directory, not in the tree).
Four statements kept from the earlier builds were read against the code and tests and not probed by hand: that a section default is "filled in once per evaluation"; that an event's record in the service takes no default (`jl4-service-test`, "refuses an event whose nested record leaves out a defaulted field, in both modes"); that the service's generated-module path writes a default as text (`jl4-service-test`, "answers a request on the generated-module path that supplies an input a default reads, or that reads one (W7)"); and that `l4 batch` refuses a default naming one of two operators that share their leading words.

**What each of W10's items became.**

- **`doc/reference/types/TYPICALLY.md`.**
  The one behaviour is stated once, at the top: `TYPICALLY d` on a name means that when nothing supplies a value for the name, at the point where a value has to come from outside the rule, the rule uses `d`.
  Three things hold wherever it is written (a supplied value wins; "not known" is not "left out"; inside a file a call or a construction by position gives everything), and a table says how a name comes to be left out for each place it is written.
  The "everywhere else: metadata only" half had already gone with W4, W5 and W7.
  What was left of it is the `ASSUME`, now said plainly in a section of its own ("On an `ASSUME`: checked and recorded, not used", with what each tool does), beside the two other places that accept a `TYPICALLY` and never use it (a lambda's own `GIVEN`, and a field of an enum constructor that carries data).
  The "Landed in stages" note, a status line in a reference page, is gone; "What changed" says what the page used to say, as R8's own note asks (`IMPLICIT-PROPS-DESIGN.md` §11.5).
  Three sentences the checks found wrong are corrected: "Three limits … at the boundary" listed five; the last of them called an expression default that supplies an input the export also reads "fine … in the service"; and a name that two sections define was said to be refused, which it is not (findings 1 and 2 of "Found while checking", below).
- **`typically-example.l4`.**
  Holds each example the page quotes, and an `#ASSERT` for every answer the page gives.
  `doc/test-docs.sh` runs it, and a false `#ASSERT` is a `DiagnosticSeverity_Error`, which that script rejects (shown by making two of them false).
- **`ok/typically-basic.l4`.**
  Its header is left as it is, as the brief for this run says.
  It no longer asserts a metadata-only reading: W5 (`b4763a69f`) replaced "metadata-only default values … no runtime behaviour" with a pointer to the page and to the corpus files that exercise a default, and that is true on this branch.
- **`TYPICALLY-DEFAULTS-SPEC.md` and `RUNTIME-INPUT-STATE-SPEC.md`.**
  Status headers say what is built and where, and that the body below each is the December 2025 design.
  The second's "BLOCKED - depends on TYPICALLY" is gone: what exists of its four cells is `L4.Presumption.fillDecision`, and the types and the API it sketches are not built (searched; one unrelated `SessionState` in `ts-shared/legalese-agent`).
- **`IMPLICIT-PROPS-DESIGN.md`.**
  The trace-event item in the deferred list now says what exists (the event, not a trace line) and what a trace shows today (measured), and three items are added that the one-behaviour work leaves open: `ASSUME … TYPICALLY` (W6, deferred), a construction that leaves out every field with an enum constructor's payload fields, and T5 (W9, not on this branch).
  §11.5's "says so when R8 lands" is brought up to date.

**Stale records found on the way**, each a claim a reader would believe:

- `doc/reference/query-planning/README.md` said the shipped planner is "determinability-first", that information gain with `TYPICALLY` priors is "the planned direction", and that "no consumer reads them for ordering yet".
  `BooleanDecisionQuery.hs` and `decision-query.ts` both rank by information gain, `QueryPlanSpec` pins the priors end to end, and the service's `/query-plan` asks `a`, `b`, `presumed` for `presumed OR a OR b` when `presumed` is `TYPICALLY FALSE`, and `presumed`, `a`, `b` when it has no `TYPICALLY`.
  The section is rewritten to say that, with that example; `doc/reference/README.md`'s one-line description of the page follows.
- S2's documentation half: `errors/README.md` called the `ASSUME` to `GIVEN` rewrite "safe to take", and `ASSUME.md` said a default on an `ASSUME` is applied "nowhere".
  Both now say what is true; `GLOSSARY.md`'s row agrees. _Decided overnight; below._
- Six citations by line number into the two spec files whose headers grew (`TYPICALLY-DEFAULTS-SPEC.md:420-428` twice and `:14-41`, `RUNTIME-INPUT-STATE-SPEC.md:3-11` twice and `:62-72`) are now by section name, and `UNKNOWN-EVALUATION-SPEC.md` §3.6, which called the second header stale, says what the header now says.

**Found while checking, not fixed** (W10 changes no code):

1. **The decision service stops with an internal error on a request that supplies an input that an expression default supplies, when the default's own input is left out.**
   The page said such a default is "fine at `#EVAL` and in the service", and §4.3 recorded only the `l4 batch` half of the limit (R-S3).
   Take

   ```l4
   § `Supplied`
       GIVEN base IS A NUMBER TYPICALLY 4
             `base doubled` IS A NUMBER TYPICALLY (`double it` WITH base IS 10)

   GIVETH A NUMBER
   `double it` MEANS base TIMES 2

   @export default Total
   GIVETH A NUMBER
   total MEANS `base doubled` PLUS base
   ```

   and the request `{"arguments":{"base":1}}`.
   The answer is `Internal error: I encountered a type error during evaluation: named application supplying an implicit input reached the evaluator undischarged: ... (1 implicit argument(s)). This is a compiler bug: L4.Discharge.dischargeModule must run before evaluation.`
   `{}` answers 24, `{"base doubled":3}` answers 7, and `#EVAL total WITH base IS 1` is 21.
   The same happens when the default is on the export's own input, `rate`, in place of a section input, with an export that reads `base` and the request `{"base":1}`.
   It is on `07b62714d`, W7's head (the snapshot of that head gives the same), so it is W7's, in the direct path's root fills; `l4 batch` refuses the same files at check time, which is the limit R-S3 recorded.
   The page now says what the service does.

2. **A name that two or more sections define is read as the last section's, with no message, when the last section defines it too: through `l4 batch` for any default, and through the service's generated-module path for a default on an exported rule's own input.**
   F4 recorded the limit as a refusal ("the rows are refused, naming both"), and the comment above `defaultsMeaningElsewhere` in `Discharge.hs` says "A name two sections define is ambiguous there and is refused by those surfaces".
   Take

   ```l4
   § `Rates`
       GIVEN beta IS A NUMBER TYPICALLY phi

   GIVETH A NUMBER
   phi MEANS 8

   @export default Doubled
   GIVETH A NUMBER
   doubled MEANS beta TIMES 2

   § `Other`
   GIVETH A NUMBER
   phi MEANS 9
   ```

   `#EVAL doubled` is 16 and the service answers 16 on both its paths; `l4 batch` over `[{}]` with `-e doubled` answers 18, status success, with nothing in `diagnostics`.
   With a third section defining `phi` as 10, batch answers 20.
   With `§ Other` first, so that the default's own section is the last to define `phi`, batch agrees (16).
   Writing the name with its section, `` `Rates`.phi ``, gives 16 everywhere.
   A default on the export's own input reaches the service too.
   With `phi MEANS 8` in `§ Rates` and `phi MEANS 9` in a later `§ Other`, `GIVEN rate IS A NUMBER TYPICALLY (phi PLUS 1)` and `flag IS A BOOLEAN` on the exported rule in `§ Rates`, and a rule that reads `rate`: `#EVAL` is 9; the service's direct path (`{"flag":true}`) answers 9; its generated-module path (`{"flag":{}}`) answers 10, with `presumed: ["rate"]`; `l4 batch` answers 10.
   With a third section defining `phi` as 10 the four are 9, 9, 11 and 11, and with `§ Other` first all four are 9.
   The service half was found by the review of this branch (its F1); this build's own probes give the same numbers.
   The cause is where the generated text sits: `l4 batch` appends the wrapper's `InputArgs` record after the file's last section (`generateBatchWrapper`), and since decision 6 a field's default is checked in the section its `DECLARE` is in, so the default's names are read in the last section's scope.
   A last section that defines the name gets its own.
   A last section that does not leaves two candidates and batch refuses the file with "multiple definitions for the identifier `phi`", naming a file it generated (a trailing `§ Third` with no `phi`, measured): loud, and not the case above.
   The first build refused this shape: the review of the first build measured `s02-scope` (the default's own section `Rates`, a last section `Omega` that also defines `phi`) as "multiple definitions for the identifier phi", and the rebuild does not.
   Decision 6 of the rebuild moved a field's default from the top of the file to the section its `DECLARE` is in, which is the likeliest cause; it was not tested against the first build.
   It is a wrong answer with exit 0, and it is W7's: a default can name a definition only since W7, and batch re-reads the text in a generated module.
   The page says what each path does, and §4.3's four statements that it is refused are corrected (the surfaces table, decision 7, F4, S6).
   The comment in `Discharge.hs` is not, because this commit changes no code.

3. **S4 stays open for an `ASSUME`.**
   The ladder carries an `ASSUME`'s boolean default as the atom's presumed value (`typically: true`), and the query plan uses it as a prior, while no evaluation uses it.
   W4 closed S4 for a rule's `GIVEN` and W6, which would close it here, is deferred.
   The page says so, under "On an `ASSUME`" (decision 2, below).

**Decided by Claude overnight 2026-10-03, pending Meng's review.**
Each in its own commit, so that it can be reverted alone.

1. **The documentation half of S2 is done, although W6 is deferred.**
   T2 names `errors/README.md` and `ASSUME.md` as part of W6; the pages said the `ASSUME` to `GIVEN` rewrite is "safe to take" and that an `ASSUME`'s default is applied "nowhere", and the first is false for an `ASSUME` that carries a `TYPICALLY` (probed: the same rule gives the bare name before and `TRUE` after).
   Prefer loud over silent.
   The deprecation warning's own text ("Nothing is broken: the file still checks, runs and exports as before") is the compiler's, not changed here, and is still silent on the point.
   _Alternative:_ leave both pages until W6 rewords the warning and them together.
2. **The page says that the ladder and the query plan read an `ASSUME`'s default.**
   A reader who moves a fact to an `ASSUME` to keep it out of the rules will find the wizard still presumes it; the page says so rather than leave "metadata only" to suggest otherwise.
   _Alternative:_ say nothing about the wizard on the `ASSUME` section until W6 lands or the ladder stops drawing a presumed value for an `ASSUME`.

**Assumed, not ruled** (no one outside the code would notice, or the text is new):

- The shape of the page's top: a rule, three things that hold, a table, three places that accept and do not use a default.
- "Being retired" beside "deprecated (ruled 2026-09-04)": the compiler's warning says "being retired", and the ruling says deprecated.
- The planner section of `query-planning/README.md` is rewritten although it is outside the brief, because it contradicted the code and `reviewing-encoded-law.md` already described the shipped behaviour.
  _Alternative:_ list it here and leave it.
- The six citations are by section name, not by new line number, so they do not move again.

**Not done, and why.**

- Canon: S3's restated constants and the comment in `regcf-denovo.l4` (Open for Meng 6) are a canon change.
- The exporters' pages (W9's: `feat/typically-w9` rewrites `doc/exports/*` and `l4-to-blawx.md`).
  The page links to the exports and names only the three pages that say anything about a default on this branch.
- The trace and the directive's `NOTE:` line (W8 and W11, on `feat/typically-w8`).
  That branch adds two sections to the page at the place where "Landed in stages" stood; they merge by keeping its sections and dropping the note.
  Two sentences become false when it lands: the skill's §7.4 "`#EVAL` does not list the defaults it took", and the deferred-list item above.
- `skills/`: the three entries that describe `TYPICALLY` (`source-patterns.md`, `01-definitions-and-scope.md`, `07-presumptions-and-defaults.md` §7.4) were read against the probes, and the two worked examples of §7.4 were run (28; 14 and 30); none is false on this branch, so none is changed.

---

## 5. Rulings this needs

R8 does not reach these.
Each is also a card on the bench "Unknowns and Defaults" (claude.ai artifact `XQk522h6PN2xv8YFPhogJc`, db collection `l4-unknowns-defaults-1001`), where an independent skeptic's objection revised it; each ruling is recorded here when it is made, as the card printed it. T3 and T4 share cards with `UNKNOWN-EVALUATION-SPEC.md` U9 and U8.

**T1. Every defaulted record field may be omitted, not only `MAYBE … TYPICALLY NOTHING`.**
**RULED 2026-10-01.** Meng marked `accept` on bench card T1 at 09:50:46Z, with no note. The ruling, as printed on the card: Any field declared `TYPICALLY` may be omitted at construction _and_ may be absent in JSON (batch, service), taking its default. A `TYPICALLY` on a `MEANS` field becomes a check error. Lands with W4/W5 of #525, after R8's named-site half and after the enum-default scoping fix (p10). How to write a construction with every field defaulted is left open, for a later card.
**Scope note, 2026-10-09.** This ruling reaches a computed field of a record (`f IS A T MEANS expr` inside a `DECLARE`, `Desugar.hs:265-267`), which is what "a `MEANS` field" names; a `TYPICALLY` on a definition is a parse error today and is ruled neither way, see `presumption-assertion/CONTRACT.md` §7 (proposed, not ruled).
**AMENDED 2026-10-01**, by bench card T1b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: All three decoders (`Machine.hs:4387-4391`, `Backend/Jl4.hs:436-441`, the wrapper at `CodeGen.hs:431`) read each field's default from its `DECLARE`; a declared default wins. With presumption on, an absent `MAYBE` field with no `TYPICALLY` still becomes `NOTHING` (D7.3). With presumption off (CHUTZPAH), that fallback does not fire: the field is absent like any other. A field with a `TYPICALLY` leaves `required` in `FunctionSchema.hs:219-223` and `JsonSchema.hs:264`, `:333`, landing with or after the decoder change. Spec `:46` and `:144` are brought into line.
D7.3 ruled the `MAYBE` case and was silent on `timeout IS A NUMBER TYPICALLY 30`.
Its principle, "the default is written where the field is declared, never inferred from the type", holds just as well for a literal.
It is additive (p4: every such omission is a check error today). It shortens canon's readings that override one field; the two all-defaults constants of S3 stay until a spelling for "every field defaulted" is ruled.

**T2. `ASSUME … TYPICALLY` is honoured.**
**RULED 2026-10-01.** Meng marked `accept` on bench card T2 at 09:52:12Z, with no note. The ruling, as printed on the card: An `ASSUME … TYPICALLY d` takes `d` when unsupplied, filled at the root without turning the `ASSUME` into a definition the ladder or schema can see. Pass condition: `QueryPlanSpec`'s atomIds and `viz-adapter.real-module.test.ts` unchanged. In the same change: reword the deprecation warning and `errors/README.md:571`, and update `TYPICALLY.md:150-155` and `ASSUME.md:267`.
**AMENDED 2026-10-01**, by bench card T2b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: T2 covers module-level 0-ary `ASSUME`s, until W7 lands, when inputs-taking ones are reopened. For an `ASSUME` with inputs, the warning says its default is dropped. For a `WHERE`-local one, the warning's rewrite either drops the `TYPICALLY` or says plainly that it switches the default on. Pass condition, by name: `jl4-service/test/QueryPlanSpec.hs:878-891` and `ts-shared/ladder-core/test/viz-adapter.real-module.test.ts` unchanged; at the schema boundary an `ASSUME … TYPICALLY` behaves as a section `GIVEN` once W2 lands, and W6 names W2 as a dependency for that half.
No golden answer moves: no directive in the three sites' files reads them (§2.1).
It makes the warning's "nothing is broken" true of the migration it recommends.
`ok/typically-basic.l4` stays on `ASSUME` because `jl4-service/test/QueryPlanSpec.hs:878-891` and a TypeScript fixture pin its ladder atomIds; those must not move. Its header, which asserts the metadata-only reading, changes.

**T3. Absent, `null` and `{}` on the wire are three different things.**
**RULED 2026-10-01.** Meng marked `accept`, option B on bench card TU-wire at 09:53:17Z, with no note. The ruling, as printed on the card: Remove `fromMaybe FALSE` at all three sites (`CodeGen.hs:239, 335, 603`), so absent or `null` on the wrapper path is refused or an assumed term, exactly as on the direct path. `{}` means `null` and never takes a default. Retire `{}` after instrumenting the service to see who sends it, since its log does not record argument shapes. (Card TU-wire is shared with `UNKNOWN-EVALUATION-SPEC.md` U9.)
**AMENDED 2026-10-01**, by bench card TU-wire-b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Ship the removal of `fromMaybe FALSE` now, binding a missing boolean on the wrapper path to a placeholder assumed term, so it stays lazy (stuck only if read, naming the input), which W1 already specifies. Eager refusal stays only on the direct path (`Jl4.hs:448`), and lazy binding there is its own work item. W2 lands with or before W3 (and so before CHUTZPAH's switch). The `{}` retirement is announced on its own schedule, after instrumentation.
**Pointer, 2026-10-09.** The lazy-binding item named here, for the direct path, is stated as a contract in `presumption-assertion/CONTRACT.md` §5.4, which also extends it to `l4 batch` and every wrapper-path type; that extension is new scope and is open for Meng there (§13).
They are the four-cell model of `RUNTIME-INPUT-STATE-SPEC.md` ("The Four-State Model"):

| wire    | cell             | meaning                  | proposed                                                         |
| ------- | ---------------- | ------------------------ | ---------------------------------------------------------------- |
| absent  | `Left (Just d)`  | not asked, has a default | the default                                                      |
| absent  | `Left Nothing`   | not asked, no default    | an assumed term: stuck only if the rule needs it                 |
| `null`  | `Right Nothing`  | "I don't know"           | an assumed term, **never** the default                           |
| `{}`    | (`FnUncertain`)  | "uncertain"              | as `null`, until a ruling gives "uncertain" a meaning of its own |
| a value | `Right (Just v)` | answered                 | the value                                                        |

Today absent and `null` are both refused on the direct path, and FALSE on the wrapper path, which one `{}` anywhere in a request reaches (S1).
The assumed-term row is how a section `GIVEN` with no default already behaves at `#EVAL` (`doc/concepts/legal-modeling/non-answers.md` §3).
It also keeps the reason the wrapper used `fromMaybe FALSE` at all (`CodeGen.hs:93-94`): an input the rule never reads costs nothing.
`UNKNOWN-EVALUATION-SPEC.md` then changes "stuck" to "unknown" without touching this table.

**T3c. In `l4 batch` CSV input, an empty cell is absent, not `null`.**
**RULED 2026-10-02 (SOFTBOILED, in chat).** Raised by session `batch`, whose requirement R2 found that under T3 a CSV user can get a default only by dropping the whole column, so one file cannot let one row take the default while another supplies a value.
Meng's note, verbatim: _"you know, in the original Default design, we had "soft" and "hard" modes of evaluation: in "hard", TYPICALLY defaults were not used; in "soft", they were. that would be a way to resolve the question about how to deal with empties."_
The ruling, as stated when the word was fired:

- In `l4 batch` CSV input an empty cell reads as absent, not `null`.
- Whether an absent input takes its default is T4's presumption switch: soft (on, the default) takes it and lists it in T6's `presumed`; hard (off) uses no default, and the row is an error naming the input.
- JSON and YAML `null` keep T3: it never takes a default.
- There is no per-row CSV spelling of `null`; one is added only when a user needs "don't know, don't presume" on one row of a file that presumes on the others.
- The batch documentation page says so. It is built with W3.

**What was measured.** On the installed `l4` (built 2026-09-28), with probe `secdefault.l4` (section `has capacity … TYPICALLY TRUE`, and an export reading `is adult AND has capacity`): `#EVAL` gives `TRUE`; `l4 batch` with the CSV row `true,` (empty `has capacity`) gives `Expected JSON boolean but got: Null`; with the column omitted it gives `Missing required field 'has capacity' in JSON object`.
The empty cell becomes `null` in `inferCsvCell` (`jl4/app/L4/Cli/Batch.hs:515-516`).

**Soft and hard are T4's switch, under their original names.** The December 2025 design spelled them as directives, `#PEVAL`/`#PASSERT` (soft) beside `#EVAL`/`#ASSERT`, replacing `#EVALSTRICT`/`#ASSERTSTRICT` (`a249d8b41`).
U7 (`UNKNOWN-EVALUATION-SPEC.md` §9) ruled out a new directive, so the choice is the caller's switch, not the module's.

**`MAYBE` inputs.** Today an empty cell for a `MAYBE` input is `NOTHING` (`Batch.hs:497`; `specs/done/BATCH-PROCESSING-SPEC.md:195`; measured: a `MAYBE NUMBER` input with an empty cell took the `WHEN NOTHING` arm).
Under T3c it is absent, and T1b decides it: with presumption on, an absent `MAYBE` with no `TYPICALLY` still becomes `NOTHING`, so nothing changes; with presumption off, T1b's fallback does not fire.
A `MAYBE` input with its own `TYPICALLY` takes that default instead of `NOTHING`, since a declared default wins (T1b).
T1b states these rules for record fields; reading them for a batch input as well is this record's reading, and W3 tests it both ways.

**T4. An exploration mode may switch defaults off.**
**RULED 2026-10-01.** Meng marked `accept` on bench card TU-presume at 09:54:00Z, with no note. The ruling, as printed on the card: One switch on every evaluation, decide mode included, on by default, landing with W3/W4, not with explore mode. Off: an absent input with a default is treated as absent with none (stuck in decide mode, unknown in explore mode). `null` never takes a default either way. The "presuming _x_" mark is ALIBI's `presumed` list. With presumption off, only boolean defaults become planner priors. (Card TU-presume is shared with `UNKNOWN-EVALUATION-SPEC.md` U8.)
**AMENDED 2026-10-01**, by bench card TU-presume-b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: ALIBI's mark covers every default that took effect, wherever filled, with its declaration line. The off switch withdraws a default only where a request can supply its value; elsewhere the result says "rests on presumed _x_" and does not go stuck. A per-binder override on the wire is left to a later card. Investigator mode is not claimed for a subject until PREFAB, the all-defaults-spelling card and a canon change have landed. A check-time warning flags a construction that restates a field's `TYPICALLY` value literally, which also answers S3's "nothing checks the two agree".
An investigator, or anyone asking what is _established_ rather than what is _presumed_, needs to see `Left (Just d)` as unsettled.
The ladder already has that switch (`respectDefaults`).
Without it, honouring defaults everywhere (W3, W4) strengthens the conversation's original worry instead of answering it.

**T5. Exporters: map or say.**
**RULED 2026-10-01.** Meng marked `accept` on bench card T5 at 09:52:35Z, with no note. The ruling, as printed on the card: Each exporter maps a default only where the target's mechanism means what T1–T4 rule `TYPICALLY` means, and otherwise emits a fidelity note. Where the target always has a default (OpenFisca), mapping is mandatory: writing the first member is asserting a different presumption. Survey all eight `l4 export` formats. Blawx keeps its §5.1 ruling.
**AMENDED 2026-10-01**, by bench card T5b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Blawx gets the note channel §5.1 promises, in the emitted header or on stderr, firing for rule `GIVEN`s and record fields as well as section inputs; the two stale doc promises are made true or corrected. yscript refuses a module whose exported rule reads an input with a `TYPICALLY` default, as R5 requires; it gets no channel. OpenFisca maps every default: a literal to `default_value`, an expression to a formula that a supplied input overrides; it refuses only what it cannot map.
The evidence is §2: OpenFisca replaces a default with the first enum member, and DMN and Blawx drop a `GIVEN` default without a word.

**T6. Where the "took its default" event shows.**
**RULED 2026-10-01.** Meng marked `accept` on bench card T6 at 09:52:52Z, with no note. The ruling, as printed on the card: A top-level `presumed` field on every service response and every `l4 batch` row, listing only the defaulted inputs _actually forced_ during that evaluation. Built from W8's event, after it lands. Specified once, shared with #526 §5 / TU-presume.
**AMENDED 2026-10-01**, by bench card T6b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: Section binders (and T2's `ASSUME … TYPICALLY`) are left absent and filled by discharge. Every other fill site, the service direct path (`Jl4.hs:448`, including via `:501`), batch's JSON decoder, W4's named sites and constructions, emits W8's event itself. The trace shows every event; `presumed` keeps only those whose binder or JSON path is part of the request. Tests omit a section binder, a rule `GIVEN` and a record field on both batch and service, and check each appears in `presumed`. #526 §5's wording is reconciled to "actually forced".
**Extended (proposed, not built), 2026-10-09.** A request may also assert a named derived node, and the answer lists the nodes whose asserted value was forced under `asserted`, beside `presumed`, by the same forcing rule; see `presumption-assertion/CONTRACT.md` §4.2 and `PRESUMPTION-SCENARIOS.md` §7 for the ruling behind it.
R8 already asks for it in every directive and trace output (`PROPS-REDTEAM-2026-09-03.md:367`); the service response's `reasoning` is sent only when a trace is requested (`Backend/Api.hs:210-214`), so the list is a field of its own.
_Reading used for W4 and W5 (decided by Claude overnight 2026-10-03, pending Meng's review, §4.2):_ T4b and T6b conflict for a default the rules take themselves, at a named site or a construction.
T4 says the "presuming _x_" mark is ALIBI's `presumed` list, and T4b says the mark "covers every default that took effect, wherever filled", which reads as listing it everywhere; T6b says `presumed` "keeps only those whose binder or JSON path is part of the request", and names W4's sites among the fill sites, which reads as leaving it out.
The branch follows T4b under hard, where `presumed` is the only place the result can say it "rests on presumed _x_", and T6b under soft, where every entry in `presumed` is something a request could have supplied.
What soft gives up, measured on the review's probes: a soft answer that took `rate TYPICALLY 3` inside the rules lists nothing for it (`presumed: []`), and a soft batch row answering `60` lists `cfg.timeout` although `30` of the 60 is a construction's default; the trace is the only place that shows it, and its rendering is not built (W8).
Which reading governs under soft is Meng's: listing it is one line in `requestPresumed` (the guard on the `FromNamedApp` case, `L4.EvaluateLazy`).

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
