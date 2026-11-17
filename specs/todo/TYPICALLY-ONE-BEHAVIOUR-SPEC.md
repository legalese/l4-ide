# `TYPICALLY`: one behaviour

**Status:** proposed; W1 built 2026-10-01 in legalese/l4-ide#530; W2 and W3 built 2026-10-02 in `feat/typically-w2w3` (legalese/l4-ide#539, merged 2026-10-06), with the minimum of W8 they need and the checking half of W5 (§4.1); W4, W5, `T WITHAL` and the payload fields of an enum constructor built 2026-11-17 on `feat/typically-in-file`, not merged, re-carved from two earlier drafts (§4.2 and §4.3 name the checks it ran; a local run is not a CI run); W7 withdrawn by HAIRCUT (2026-10-12, §4); W6, the trace rendering of W8 and W9's exporter work not built; the bench of 2026-11-17 ruled U1 to U4 (§4.2), of which only U1's arity-error condition is built here.
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

- **Only literals are accepted** (p5): `TYPICALLY phi` is "must be a literal". R8 rule 3 is withdrawn (HAIRCUT, ruled 2026-10-12, §4).
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
- **S3. Canon keeps each default twice, and nothing checks the two agree.** Because a field default does nothing, encoders restate it as a named constant that call sites pass. In `legalese/canon`, `subjects/sg/succession/encodings/legalese/sg-succession-domain.l4:188-200` declares `TYPICALLY TRUE` on two `Interpretation` fields and then builds `the orthodox reading` with both set by hand. `subjects/sg/child-support/encodings/legalese/sg-child-support-domain.l4:91-106` does the same with `the live reading`, and says why: _"It restates the TYPICALLY defaults so that call sites and #ASSERTs have a value to pass; the defaults above remain the normative statement of the readings."_ Edit one and the encoding silently runs on the other. `subjects/us/regcf/encodings/cleanroom-2026-08/regcf-denovo.l4:134-140` gave up on the field default altogether, because of the enum defect in §2.
- **S4. The ladder shows an answer the evaluator cannot give** (§2, last bullet). It is drawn as tentative, which is honest about provenance, but no evaluator path reproduces it.
- **S5. The service's wrapper path never delivered a section `GIVEN`'s value** (found while building W1, fixed by it in #530). It bound the name with a `LET` around the call, which does not reach the rules that read a section `GIVEN`: they saw its `TYPICALLY` default, or an assumed term. L6 hid this whenever the request had a boolean. Without it, `has capacity: false` (declared `TYPICALLY TRUE`) with a `{}` on an unread input answered `true`. W1 supplies section `GIVEN`s with `WITH`, the language's way of supplying them at a root.

**Loud — the tool refuses:**

- **L1.** A rule's own defaulted `GIVEN` cannot be omitted at a named site (p2).
- **L2.** `l4 batch` and the service refuse an omitted section default that `#EVAL` honours (p7, p15).
  **Fixed by W3** (#539): both fill it, and list it in `presumed` (§4.1).
- **L3.** A defaulted record field cannot be omitted at construction (p4).
- **L4.** An enum default on a record field fails with a misleading message (p10).
  **Fixed in #539** (the checking half of W5, which W3 needs, §4.1): p10 checks clean, and a record built from it evaluates (`DECIDE p IS Paint Red 2`, then `#EVAL p's colour`, gives `Red`).
- **L5.** An expression default is refused (p5).
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

| #   | item                                                                                                                                                                                                                                                                                                                                                                                                                                                     | closes       | where                                                                                                                                 |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| W1  | The service stops making `{}` and `null` FALSE. Under T3 both become an assumed term for a non-`MAYBE` input: stuck if the rule needs it, harmless if it short-circuits away. Under `UNKNOWN-EVALUATION-SPEC.md` they later become Unknown.                                                                                                                                                                                                              | S1, L6, S5   | **Built in #530.** `Backend/CodeGen.hs` (placeholder assumed terms; section `GIVEN`s by `WITH`); `Backend/Jl4.hs` `splitAssumeParams` |
| W2  | The service's schema carries `default` and leaves a defaulted input out of `required`.                                                                                                                                                                                                                                                                                                                                                                   | R8 surface   | **Built in #539** (§4.1). `Compiler.hs` `parametersFromExport`; `L4.Export.isRequiredInput`, `honouredDefault`                        |
| W3  | `l4 batch` and the service fill an absent defaulted input with its default, at the root. In `l4 batch` this covers JSON, YAML and CSV input, and an empty CSV cell is absent (T3c).                                                                                                                                                                                                                                                                      | L2           | **Built in #539** (§4.1). `L4/Cli/Batch.hs`; `Backend/Jl4.hs` root fills; the JSON decoder in `Machine.hs`                            |
| W4  | A rule's own defaulted `GIVEN` may be omitted at a named site. R8's other half: thread the callee's `FunTypeSig` defaults to `supplyAppNamed` (`IMPLICIT-PROPS-DESIGN.md:2421`). Positional sites stay as they are (R8 rule 1).                                                                                                                                                                                                                          | L1, S4       | **Built 2026-11-17** (§4.2): `TypeCheck.hs` `supplyAppNamed`, `functionInputDefaults`                                                 |
| W5  | Record fields: a defaulted field may be omitted at construction (D7.3, widened by T1); fix the field-default scoping defect and its message.                                                                                                                                                                                                                                                                                                             | L3, L4, S3   | **Built 2026-11-17** (§4.2): `TypeCheck.hs` `supplyAppNamed`, `withCheckedFieldDefaults`                                              |
| W6  | `ASSUME … TYPICALLY` per T2.                                                                                                                                                                                                                                                                                                                                                                                                                             | S2           | `Discharge.hs` `fillInDefault` (`:281-295`), the deprecation message                                                                  |
| W7  | Expression defaults with the cycle check (R8 rule 3). **Withdrawn** by HAIRCUT (ruled 2026-10-12): a default is a literal, so there is no cycle to check.                                                                                                                                                                                                                                                                                                | L5           | `TypeCheck.hs:1724-1745`; `FunctionSchema.typicallyToJson` must then carry source text                                                |
| W8  | The trace records "took its default", with the declaration line (R8 surface).                                                                                                                                                                                                                                                                                                                                                                            | —            | **The event is built in #539** (§4.1), not its trace rendering. `L4.EvaluateLazy.Trace`                                               |
| W9  | Every exporter either maps the default to the target's own mechanism or emits a fidelity note (T5).                                                                                                                                                                                                                                                                                                                                                      | §2 exporters | `Dmn/`, `OpenFisca/`, `Blawx/` lowerings                                                                                              |
| W10 | Documentation and stale records: `doc/reference/types/TYPICALLY.md` (one behaviour; delete the "everywhere else: metadata only" half), `typically-example.l4`, the header comment of `ok/typically-basic.l4`, the status headers of `TYPICALLY-DEFAULTS-SPEC.md` and `RUNTIME-INPUT-STATE-SPEC.md`, the deferred list in `IMPLICIT-PROPS-DESIGN.md:2391`. Canon's restated constants (S3) can go once W5 lands; that is a canon change, not this repo's. | —            | —                                                                                                                                     |

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
Not covered here: a field of an enum constructor that carries data was listed as required (and its default printed) and no decoder fills it, because none decodes such a constructor from JSON; the schema stops listing a defaulted payload field as required since L7 (§4.2, "Payload fields"). A record built inside L4 is W4/W5 (§4.2).

**T3, and null kept apart from absent from the wire inward.** On the service, `"x": null` arrives as a key present with no value and an absent key as no key (`Backend/Api.hs` `FnArguments`); the direct path reads the three cells from the request map before anything collapses them (`Backend/Jl4.hs` `suppliedIn`, `Supplied`), and the wrapper path fills only keys that are absent (`wrapperPlan`). Tests send `null` and absent on both paths ("keeps null apart from absent on the wrapper path", "never takes a default for null").
`null` on any input or field that is not a `MAYBE` is refused, naming it, whether or not it has a default ("Field 'x' is null, which means the value is not known: supply a value"; with a default, "…, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"); `{}` likewise, being `null` (T3), and the message spells it as sent.
Whether a field is a `MAYBE` is decided on its type with synonyms expanded, so a synonym for `MAYBE` keeps D7.3's fallback (`jsonValueToWHNFTyped` via `expandTypeSynonyms`; the direct path via `miSynonyms`).
Following T3 (review: the report's item 5): an enum input with no default sent as `null` used to decode to `NOTHING`, so the case answered with status success.
The decoder now names the field in every primitive mismatch (`Expected JSON boolean for field 'x' but got: Null`), where it used to name only the JSON kind.

**T3c.** An empty CSV cell is dropped from the row (`Batch.hs` `parseBatchInput`), so it is absent exactly as a missing column is.
Batch reads CSV with its own row loop over cassava's `header` and `record` parsers (`csvRows`), because `Csv.decodeByName` drops every record that parses to one empty field, and a line holding only `""` parses to that as a blank line does: a one-column file lost that row, two rows in and one out, exit 0.
**RULED 2026-10-12.** Meng marked `accept`, option A on bench card R4 of "Main Wave Rulings" (<https://claude.ai/artifact/Lpj7TuD6CMHQ5v63yxSGnb>) at 23:54:41Z, with no note.
The ruling, as printed on the card: in `l4 batch` CSV a blank cell is absent whether it is empty, spaces only or a quoted `""`.
Conditions: FLOTILLA 14 takes unstable's CSV row reader (`csvRows`), so `main` and unstable agree on one-column files, with Scalpel saying whether the ragged-record refusal and BOM handling come with it; `doc/tutorials/getting-started/l4-cli.md` gains one sentence: to pass an empty or all-space text, use JSON or YAML.
Still assumed, not ruled: an unquoted blank line is not a row.
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
- The service: `presumed` beside `result` on every answer, always present; `@presumed` on each case of the batch endpoint. A refusal is an answer, so `EvaluatorRefused` carries its own `presumed` beside the reason, and a refused case of the batch endpoint carries `@refused` and `@presumed` (review M5). Any other error body has none, since nothing was answered; an errored case of the batch endpoint carries `@error` instead of vanishing into `casesIgnored` (review m5). The MCP tools take no `presumption` and evaluate soft; their result is the same JSON, `presumed` included. Assumed, not ruled. (U3, ruled 2026-11-17, replaces this with a reserved `presumption` argument; it is not built on this branch, see §4.2.)
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
Omitting a defaulted field at a construction (L3) is W5 (§4.2).

**R1, parity with `#EVAL`.** Holds for section `GIVEN` defaults: batch, the service and `#EVAL` give the same answer with the binder omitted (`jl4/tests-cli/fixtures/batch-typically-section.l4`: ``#EVAL `can contract` TRUE`` is `TRUE`, and so is the batch row `{"is adult": true}`).
It holds for a rule `GIVEN` and a record field too since W4 and W5 (§4.2): `#EVAL` took those omissions as an error (p2, p4) before, while batch and the service filled them at the root, as W3 rules.
**That gap was accepted while it lasted, and the batch documentation page (`doc/tutorials/getting-started/l4-cli.md`) said so; it says now that a call inside the file may leave out the same things.** _Decided by Claude overnight 2026-10-02, pending review._

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
- Not changed, and operational notes for the pull request: the redeploy compatibility gate ignores a changed default (review m3; U2, ruled 2026-11-17, makes a changed default a reported notice and not a rejection, see §4.2, and is not built on this branch), and every stored `bundle.cbor` is recompiled once after upgrade, logging "Corrupt bundle.cbor" (review code #11; the text is quoted in `EVERY-EACH-QUANTIFIER-SPEC.md`, so it is left as is).

**Decided by Claude overnight 2026-10-02, pending Meng's review.** Three shapes W3 had made quiet that were loud before it; the lead's rule was to restore the loudness exactly there. Each is in its own commit, so that it can be reverted alone, and each names the alternative.

- **An unknown key, where a default was filled (review M1).** Before W3, a misspelled key on a non-`MAYBE` input was loud, because the input it misspelled was then missing; once that input has a default, ignoring the key let the misspelling take the default, with status success and only `presumed` to show it. So in any object where a default was filled (the request's top level, a record inside it, a CSV row, which takes its keys from the header), a key that matches nothing is refused, naming it and the nearest declared name (`Unknown field 'has capasity' (did you mean 'has capacity'?)`; on the service's top level, `Unknown parameter …`). Postel's law still holds in an object where no default was filled, so nothing that worked before W3 starts failing. "Filled a default" means a `TYPICALLY`; D7.3's `NOTHING` for a left-out `MAYBE` does not count, because it predates W3, and counting it would break requests that worked. The decoder applies it to every decode, a rule's own `JSONDECODE` included, since there too the object would have failed before W3; the service checks its top level once for every path (`refuseUnknownArguments`), and `--validate-only` agrees, records and lists included (`validateRow`, `unknownIn`). Consequence to weigh: a CSV with a column that is not an input, such as an `id` kept for joining output to input, now fails on every row that takes a default. _Alternative:_ no refusal; an `unrecognised` list beside `presumed`, with `presumed` declared in the per-deployment OpenAPI so that a generated client keeps both.
- **`{}` as a value means `null`, on every path, records included (review M2).** T3: "`{}` means `null` until it is retired". So `{}` on a record input or field never takes a default and is refused, naming it (`Field 'cfg' is {}, which means the value is not known: supply a value`), and on a `MAYBE` record it is `NOTHING`. The same holds for `{}` as a list element. The service now sends an uncertain value to its wrapper as `{}` rather than `null`, so that a refusal spells what the request sent; the decoder treats the two alike. A whole batch row `{}`, or a rule's own `JSONDECODE` of `"{}"`, is the object being decoded rather than a value inside one, and still supplies nothing, so every default applies. How to spell "a record with every field defaulted" stays open, as T1 left it; the batch page says so. _Alternative:_ `{}` on a record input means "a record with nothing supplied", on both paths (the service would then have to stop reading `{}` as uncertain for a record).
- **A CSV record whose cell count is not the header's is refused, naming its line (review M4).** A short record used to take the defaults of its missing cells, and a long one lost its extra cells, both with status success. Such a record is now an error row (`Line 3 has 1 cell, but the header has 2, …`), counted against `--continue-on-error` like any other, with the cells it had as its `input`. Line numbers count physical lines, so a quoted cell holding a line end moves the next record's number. An unquoted line holding only spaces or tabs is blank and skipped, in a one-column file too; a quoted `""` or `"   "` is a row whose cell is absent (T3c). _Alternative:_ an unquoted whitespace-only line in a one-column file is a row, whose cell is absent.
  - **RULED 2026-10-13 (RAGAMUFFIN).** Meng confirmed the refusal as built, by trigger word in GM's window at 11:33:40Z: `l4 batch` refuses a CSV record with fewer or more cells than the header, naming its line. No conditions; no note.
  - **RULED 2026-10-13 (BLANKSLATE).** Meng confirmed the blank line as built, by trigger word in GM's window at 11:33:40Z: in a one-column CSV file an unquoted line of only spaces or tabs is a blank line and not a case; to give an empty value, write `""`, which per R4 is a case whose cell is absent. The alternative above is not taken. No conditions; no note.

W4 and W5 share a mechanism: a named supply site that can see the callee's defaults (§4.2).
W7 is withdrawn (HAIRCUT, ruled 2026-10-12): a default is a literal or a nullary constructor, which is what lets the checker copy it into a call site and carry its type with it.
The expression-default text of R8 rule 3 is kept in `IMPLICIT-PROPS-DESIGN.md` §11.5 as the record of what was ruled on 2026-09-04, with the reversal written beside it.

**What does not change.**
Positional calls (R8 rule 1).
`WITH` as the one override (R9).
The JSON boundary's treatment of an absent `MAYBE` field as `NOTHING` (D7.3).
The query plan's use of a boolean default as a soft prior (`VizExpr.hs`, `typicallyTrueWeight`).
That prior orders questions and never answers one, which is already the one behaviour applied to elicitation.

### 4.2 W4 and W5, as built (2026-11-17)

**Status.** Built on `feat/typically-in-file`, not merged. It was carved from two earlier drafts (a W4 and W5 branch, and an enum-payload branch) onto the `unstable` of 2026-11-17, not rebased. What ran, and what did not, is in the commit messages of the branch and in the pull request that carries it.

**One mechanism for both: a named application that leaves a defaulted input or field out checks as a COMPLETE application.**
`supplyAppNamed` asks the callee's table of defaults (`CheckEnv.visibleInputDefaults`) before it reports an input missing, and adds the default as one more named argument that carries a `DefaultFill` mark (`L4.Syntax`).
Only a named site reaches it, so R8 rule 1 holds without being checked: a positional site keeps its arity error.

- **The tables.**
  A rule's come from its checked signature (`functionInputDefaults`; a `WHERE` rule's through `withExtraInputDefaults`), a record's from `withCheckedFieldDefaults`, which checks every `DECLARE`'s field defaults once before the first body, so that a construction before its `DECLARE` in the file sees them.
  Both are keyed by the callee's `Unique`, so an `AKA` and a section-qualified spelling find the same entry.
- **Across an `IMPORT`** (O2).
  The tables travel as `implicitReaders` do: `CheckResult.inputDefaults`, `unionImportedCheckEnv`, `tcdInputDefaults`, the language server's `TypeCheckResult`.
  The recorded type of a default is dropped on the way out, because it was inferred in the exporting module; a literal carries its type with it, so nothing reads it.
- **Why a complete application and not a gap.**
  Every consumer of the checked tree then sees every argument: the evaluator, discharge, the exporters, the MLIR lowering and the document renderer, and none has to know defaults exist.
  The one exception found, and fixed, is DMN: its rule rows tell a constructor from a variable by the name's resolved info, so the added name keeps it (`jl4/tests/DmnExport.hs`).
- **The printer leaves an added argument out** (`isDefaultFill`, `L4.Print`), so `l4 batch`, which prints a module and runs it again, re-checks to the same fill.
- **The event.**
  An application registers an added argument with the presumption registry (`FromNamedApp`), so it is reported the first time it is forced and not before.
  A default that is a bare constructor gets a cell of its own (`allocateArgument`), because a bare constructor is normally the one cell every use of that name shares.
- **The atomIds do not move.**
  A new `Extension` field would have moved every atomId, which is the hash of `show` of a term with its annotations emptied (`L4.Viz.AtomKey`); `Show Extension` is written by hand and prints `defaultFill` only when it is set. `QueryPlanSpec`'s pinned ids pass unchanged.

**What it does, by ruling.**

- **R8 rule 1 / W4.** `` `scaled` WITH base IS 10 `` takes `rate`'s default; `scaled 10` still says "expects 2 inputs, but here it is given 1"; an input with no default is still asked for; a misspelt name is still an error of its own (`not-ok/tc/typically-named-site.l4`).
  One misspelling cannot be caught: a name that is itself another input the callee reads, a section `GIVEN` the call may override.
- **T1, D7.3 / W5.** `Paint WITH coats IS 2` takes every other field's default (a number, a string, a boolean, an enum constructor, `NOTHING`), in any order of the written fields.
  A field with no default is still required, and a positional construction still gives every field.
- **T1's check error.** A `TYPICALLY` on a field with a `MEANS` clause is `TypicallyOnComputedField`, read off the parsed module because `desugarComputedFields` moves the field out of its record, and its default with it.
- **p10.** A default naming something not in scope is reported once, as that.
- **T4, T4b, T6, T6b: O1, ruled 2026-10-11, option B.**
  A default a named site or a construction took is inside the rules, where no request can supply it, so `presumed` lists it in both presumption modes, as `WITH rule: input` (`WITH Config: timeout` for a record), only if the answer read it.
  A rule's own `JSONDECODE` follows, listed as `JSONDECODE T: path` in both modes (condition 3, DECODERRING, ruled 2026-10-11).
  `presumed` has three string shapes, told apart by prefix: an input's name or path, `WITH ...` and `JSONDECODE ...`.
  The published description of `presumed` says so (OpenAPI text, the service README, the batch page).
- **O2, ruled 2026-10-11, option A.** A default crosses an `IMPORT`; the reference page says an imported default follows its file, and that writing the input at the call pins it.
- **O3, ruled 2026-10-11: the narrower rule.**
  A named site whose callee has an overload takes a default unless another rule of the name FITS what the site writes, so a default never decides which rule an under-specified site means (`siteTakesNoDefault`, `rivalFitsSite`).
  The checker records, on each branch of its search, the callee it chose among several candidates and the types of the others (`CheckState.overloadedCallees`); the site reads it straight after its name resolves, from a mark cleared just before.
  `mergeAlike`'s outcome merge does not look at it, and the read comes before any merge; `ok/typically-overload-*.l4` pin this.
- **O4, ruled 2026-10-11.** Listing a default of an event's party or action record, soft taking it and hard refusing it, is the target; until it is built the service refuses an event's record that leaves a defaulted field out, in both modes (`refuseEventRecordGaps`), a nested record included.
  The card's condition 3, that the published schema stops promising the default for an event's record, is its own change on the branch that owns the event schema, and is not here: it is a precondition on landing this branch (U4, constraint 3, below), and until it lands the schema still promises a default that the service refuses to take. It is moot if O4 B is built.
- **O5, ruled 2026-10-11, option A.** `l4 nlg` and `l4 render` mark a value the checker added: "`rate` is 3 by default" in a sentence, "red (by default)" in a field list or a table cell.
  The mark does not cover a default taken at the root of a section `GIVEN`; the `presumed` list is the account there.
- **O6, ruled 2026-10-11, option B.** The owner in a `presumed` entry is the rule's or record's declared name behind the headings it is declared under (`WITH Pricing.scaled: rate`), not an `AKA` alias and not a mixfix rule's canonical pattern.
- **HAIRCUT, ruled 2026-10-12.** A default is a literal (§4); the error that refuses another says to put the logic in an `OTHERWISE` branch with a `MAYBE` input.

**Payload fields (Lane C L7, ruled 2026-10-12, option B).**
A `TYPICALLY` on a payload field of an enum constructor works as on a record field: `Rect WITH height IS 5` takes `width`'s default, and `Circle WITHAL` takes `radius`'s.
The ruling's words: our treatment of plain records, the products, should carry across to the records inside enums, the sums of products.
Its six conditions, as built:

1. A `MEANS` on any payload field is a check error of its own (`MeansOnAlternativeField`).
2. The schema stops listing a defaulted payload field as required (`JsonSchema`, `enumWithPayloads`).
3. The reference page says so, and that `l4 batch` cannot be given an alternative that carries data (`{"tag":"Circle","radius":2}` is not read as a `Circle`), so the default applies where the alternative is built in the rules.
4. docassemble pre-fills the payload field's follow-up question, and the `DA-TYPICALLY` note lists it.
5. `T WITHAL` reaches alternatives that carry data (`recordInputDefaults` has an `EnumDecl` case).
6. This section records it, with `IMPLICIT-PROPS-DESIGN.md` (R8's T1 copy) and the skill's entry 7.4; the l4-plugin bundle is not regenerated here.

**Rulings of the bench of 2026-11-17** (bench `https://claude.ai/artifact/2LFadmbWc6NMJ7z1fNdyum`, db collection `typically-rulings-1117`; each line carries the card, the option and every condition).

- **U1, ruled 2026-11-17: declined; R8 rule 1 stays.** A rule's own defaulted input and a record field may be left out only at a named call; a positional call or construction gives all of them; a section input flows, or takes its default, at either kind of call.
  Conditions: (1) the docs say it in one sentence about a rule's own inputs and record fields, and the five-runtime test (a file, `l4 batch`, `/evaluation`, `/evaluation/batch`, MCP) is the acceptance check; (2) the arity error of a rule with a defaulted last input names the `WITH` form, assumed, not ruled, in its own commit (built: "typecheck: the arity error of a call by position names the WITH form"); (3) positional omission is posed again once the named half is in use, with a count of its uses.
  The one sentence is in the Behavior list of `doc/reference/types/TYPICALLY.md`.
- **U2, ruled 2026-11-17: accepted, option B** (the card recommended A; the mark is B), note verbatim: "Let’s be lax now; we can be stricter later."
  A redeploy that changes a published default is accepted and reported, not rejected.
  Assumed, not ruled: the sidebar's deploy review lists each changed default (rule, input, old, new) as a notice that does not block, before the deploy is applied; the job result carries the same list; `l4 deploy` and `l4 redeploy` print it; one test case file is shared by the service and the sidebar checks; the pages that list what is breaking say a changed default is reported, not blocked; the BREAKING counter does not move.
  It closes the gap recorded at "review m3" (§4.1).
  Not built on this branch.
- **U3, ruled 2026-11-17: accepted, option A.** MCP gets a reserved `presumption` argument, `soft` or `hard`, with the name and values it has over HTTP and in `l4 batch`; it is read on every function tool and advertised in every function tool's `inputSchema`; on a deontic tool it sits beside the other arguments; a flat tool that has an input of that name, tested on the sanitized name, is refused when the tools are listed; WebMCP gets the same key in the same change; the reference page and a legalese-cloud MCP page say that MCP can set `hard`; `hard` means what it means after this in-file port.
  It replaces "The MCP tools take no `presumption` and evaluate soft" (§4.1).
  Not built on this branch.
- **U4, ruled 2026-11-17: accepted, option C: no fixed order for the work after the in-file piece,** with three constraints: (1) the sidebar's two halves go to one builder; (2) the five-runtime test is measured again before any port to `main`; (3) the schema change of O4's condition 3 is settled before the in-file piece lands, and is moot if O4 B is built.
- **2026-11-17: `TYPICALLY` reaches `main` as one topic pull request once the four requirements of smucclaw/l4-ide#1072 are met.**
- **2026-11-17: the VS Code sidebar work and the four gaps (smucclaw/l4-ide#1021, smucclaw/l4-ide#1000, O4 B and WebMCP) are in this wave.**
  This branch closes none of them: #1000 still reproduces under `l4 batch` on it, as the page says.

**Assumed, not ruled.** Each is in a commit of its own on the branch, except the first two, so that it can be reverted alone.

- A written `ASSUME`'s input default is not honoured at a named site, in the file that declares it or in one that imports it, which is what W6's deferral leaves (`not-ok/tc/typically-assume-input.l4`).
- The performer of an action is read in the callee's declared order, not in the order the arguments were written, so that a field left out to a default is not skipped (`bodyRead`, `declaredOrderArgs`).
  It also changes a verdict older than the defaults: a named construction that writes its party fields out of declared order was read by the writer's first one and is read by the declared one now.
- How an owner is quoted: each part that L4 would write in backticks has them, so an entry splits back into headings and rule (`presumedOwner`).
- A decode names its record behind its heading, as the `WITH` entry does (`recordOwners`), for the evaluated module only; a record under a heading in an imported file is still named bare, because the headings of an imported module do not reach the evaluator and carrying them changes the format of `bundle.cbor`.
- The how-to lines of the literal-default error.
- The arity error's paragraph that names the `WITH` form (U1 condition 2): its wording, that it is shown for a record constructor too, and `<value>` as its placeholder.
- The wording of `TypicallyOnComputedField`, and that the missing-input message lists only the inputs that have no default.
- The bounds of O3's check, all on the loud side: a rival whose type is still being inferred, or a bare definition at a site that supplies only section binders, counts as fitting; a rival that lacks a name the site writes is not ruled out; and a written value that itself contains a named call, a record construction included, is not checked against a rival, which keeps nested calls linear.
- `Show Extension` by hand, which keeps the atomIds where they were. Alternative: derive it and restamp the four ids in `QueryPlanSpec` and in the TypeScript fixture another repository pins.
- `IncompleteWithal` still says "record" for an alternative.

**Limits that stay, stated on the pages.**
Two declarations with the same name under the same sections give one `presumed` entry: the same name in two imported files, a `WHERE` or `LET` local, which is named bare, and two rules of one name in one section, each with its own default.
A decode into a record declared under a heading in an imported file is named bare.
`presumed` has three string shapes where a structured entry would carry the origin, the owner, the path and the declaration line; that is a change of the wire, not made here.
`#EVAL` lists no default, and the trace prints the value used and does not say it was a default (W8's rendering).

**Not built here.**

- W6 (`ASSUME ... TYPICALLY`), deferred (§4).
- T4b's check-time warning on a construction that restates a field's `TYPICALLY` literally.
  It would add diagnostics to files in the vendored canon mirror, which this repository may not edit; it can land once canon has dropped the restated constants it can drop and the pin is bumped.
- The trace rendering of the event (W8's second half), and a default read by the deontic machinery's peek at a party, which is not reported.
- Decoding an event's record as an argument is decoded (O4).

### 4.3 `T WITHAL`, T1's open spelling, as built (2026-11-17)

**ANSWERED 2026-10-09 (ARCHAISM).**
`T WITHAL` is a construction that takes every field's default and writes none.
It is a new keyword, lexed beside `WITH`.
It stands alone, so one construction does not get two spellings: an override is `T WITH a IS v`, and `T WITHAL a IS v` is a parse error.
A field of `T` with no default is a check error that names it (`IncompleteWithal`).
Bare `T` stays the constructor.
`T WITHAL` and a decode of `{}` agree where every field has a `TYPICALLY`.
The doc page says that `WITH(AL)?` finds both spellings in a search.

How it is built.
The parser reads it as the node a `WITH` already parses to, `AppNamed`, with an empty list and the same three annotation slots, so exactprint round-trips it and `Extension` is untouched.
`inferWithal` fills it through `fillDefaults`, which a `WITH` that runs out of written arguments also uses, so the checked tree is a `WITH` that omitted every field, each argument carrying its `DefaultFill`.
Every consumer therefore sees what it already sees for a `WITH` that omitted fields, and both presumption modes list each default as `WITH T: field`.
`L4.Print` prints a named application with nothing written as `T WITHAL`; it printed bare `T` before, a different expression.
A constructor with fields is told from a nullary alternative and from a rule by its declaration: this module's own from `declareDeclarations`, one from an `IMPORT` from the table `recordInputDefaults` builds, which has an entry for every record constructor and every enum constructor that carries data, empty when no field has a default.

`WITHAL` is a reserved word: a name spelled exactly so needs backticks, and `withal` stays a name, because keywords are matched by their capitals.
No tracked file of `jl4/`, `jl4-core/libraries/`, `doc/`, `skills/`, `specs/`, `etc/` or `ts-shared/` used the word at `origin/unstable` on 2026-11-17 (`git grep -i withal`); other repositories were not searched on that date.

**Assumed, not ruled** (each is easy to loosen and none is easy to tighten later).

- It reaches records and alternatives that carry data (L7). A rule, a field and an alternative that carries nothing are refused, with a message of their own for the last.
- A record with no fields takes `T WITHAL` and is that record.
- It is not accepted in a pattern.
- A name after it is read as a function applied to the record, so `Paint WITHAL coats` is `coats (Paint WITHAL)`; no warning is given for it.
- Inside an outer `WITH`, a comma after it is accepted and what follows belongs to the OUTER call; no diagnostic is added.
- At an overload (a rule that shares the record's name) the site is the ordinary "multiple definitions" error.
  The explicit `WithalOverloaded` refusal behind it is what keeps a record with no field from resolving by elimination.

**`T WITHAL` and a decode of `{}`.**
They are the same value for a record every field of which declares a `TYPICALLY`.
They differ for a field declared `MAYBE` with no `TYPICALLY`: the decode fills it `NOTHING` (D7.3), and `T WITHAL` is a check error naming the field.
`{}` as the VALUE of a record input is `null` and never takes a default (T3).
`ok/withal-decode.l4` and `not-ok/tc/withal-maybe-field.l4` pin both halves.

**Tests.**
`ok/withal.l4`, `withal-decode.l4`, `withal-import-def.l4` and `withal-import-use.l4`; `not-ok/tc/withal-*.l4` (a missing default, not a record, overloaded, inside a default, a `MAYBE` field, then an override); `lsp/semantic-tokens/withal.l4`; `l4-cli-test` (batch under soft and hard, a record from an `IMPORT`, the name of a type, an empty record rendered); `jl4-service-test`.
`prettyLayout round-trip`, `exactprint identity` and the parser memo check run over every `ok/` file, so over these.
`L4/Print.hs` is in the diff of the branch, so the evaluation differential of `CLAUDE.md` §3.2.1 is owed on the final binary.

---

## 5. Rulings this needs

R8 does not reach these.
Each is also a card on the bench "Unknowns and Defaults" (claude.ai artifact `XQk522h6PN2xv8YFPhogJc`, db collection `l4-unknowns-defaults-1001`), where an independent skeptic's objection revised it; each ruling is recorded here when it is made, as the card printed it. T3 and T4 share cards with `UNKNOWN-EVALUATION-SPEC.md` U9 and U8.

**T1. Every defaulted record field may be omitted, not only `MAYBE … TYPICALLY NOTHING`.**
**RULED 2026-10-01.** Meng marked `accept` on bench card T1 at 09:50:46Z, with no note. The ruling, as printed on the card: Any field declared `TYPICALLY` may be omitted at construction _and_ may be absent in JSON (batch, service), taking its default. A `TYPICALLY` on a `MEANS` field becomes a check error. Lands with W4/W5 of #525, after R8's named-site half and after the enum-default scoping fix (p10). How to write a construction with every field defaulted is left open, for a later card.
**Answered since:** how to write a construction with every field defaulted is `T WITHAL` (ARCHAISM, ruled 2026-10-09; §4.3), and payload fields of an enum constructor are L7 (ruled 2026-10-12; §4.2).
**Scope note, 2026-10-09.** This ruling reaches a computed field of a record (`f IS A T MEANS expr` inside a `DECLARE`, `Desugar.hs:265-267`), which is what "a `MEANS` field" names; a `TYPICALLY` on a definition is a parse error today and is ruled neither way, see `presumption-assertion/CONTRACT.md` §7 (proposed, not ruled).
**AMENDED 2026-10-01**, by bench card T1b, which an independent skeptic reviewed before it was folded in. Meng ruled in chat at 10:20Z: _"These are my rulings prior to SEQUEL. Please fold in any additional recommendations due to SEQUEL."_ The amendment, as the card printed it: All three decoders (`Machine.hs:4387-4391`, `Backend/Jl4.hs:436-441`, the wrapper at `CodeGen.hs:431`) read each field's default from its `DECLARE`; a declared default wins. With presumption on, an absent `MAYBE` field with no `TYPICALLY` still becomes `NOTHING` (D7.3). With presumption off (CHUTZPAH), that fallback does not fire: the field is absent like any other. A field with a `TYPICALLY` leaves `required` in `FunctionSchema.hs:219-223` and `JsonSchema.hs:264`, `:333`, landing with or after the decoder change. Spec `:46` and `:144` are brought into line.
D7.3 ruled the `MAYBE` case and was silent on `timeout IS A NUMBER TYPICALLY 30`.
Its principle, "the default is written where the field is declared, never inferred from the type", holds just as well for a literal.
It is additive (p4: every such omission is a check error today). It shortens canon's readings that override one field; the two all-defaults constants of S3 stay until a spelling for "every field defaulted" is ruled; it is ruled now (`T WITHAL`, §4.3), and dropping the constants is a canon change.

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
