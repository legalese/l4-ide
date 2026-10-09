# Presumptions at the end of a chain: what today's L4 can and cannot say

**Status:** a design note with measurements, written 2026-10-09 and revised the same day after an Opus adversarial review (§9 says what it changed); nothing here is built.
§7 records a ruling Meng made in chat; it is not yet written in its owning document, so by repo `CLAUDE.md` §4 it is not yet decided.
It answers Meng's question of 2026-10-09: write the Alice scenarios in plain L4 using only what the tree has, run them soft and hard, and report what the language cannot say, or says with a wrong or missing explanation.
It also measures the footgun Meng named the same day: a `MAYBE` and a `TYPICALLY` are two mechanisms for one idea, and `TYPICALLY NOTHING` sits where they meet.

**Binaries.** `l4 batch` and `l4 check` ran on the installed `~/.cabal/bin/l4`, installed 2026-10-09 02:46 (+08): after `unstable`'s head of that hour, `a3c5bed94` (2026-10-08 17:37Z), and before #553 and #554 merged (20:12Z and 20:53Z), which rewrote the decoder.
Line numbers below are at `c6d081622`, the head when this note was filed.
Which tree built it is not recorded (no `dist-newstyle/cache/plan.json` under `l4-ide` or `l4wt/*` names its unit id `6df1397b`).
Its batch behaviour is W2/W3's (#539): the TYPICALLY spec's §2 census, measured at `f9a504b77` before W2/W3, has `l4 batch` refusing a section default (p7) and a rule default (p8), which the rows below honour.
The one census row re-run here is p4, a `DECLARE` field default refused at construction, which still holds.
The construction probes also ran on a binary built from the `#551` branch (`feat/typically-w4w5`: W4 and W5, a default applied at a named call and at a record construction), copied 2026-10-09 05:19 and deleted after the probes.
`JL4_LIBRARY_PATH` was unset throughout, so each binary used its embedded prelude.
Every probe file is in Appendix A and every raw output in Appendix B, modulo trailing whitespace.

**Owning documents.** `specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md` (T1, T3, T4, T6; D7.3 as restated in its §1.1), `IMPLICIT-PROPS-DESIGN.md` §11.5 (R8), `SURFACE-SUGAR-CLUSTER-2026-09.md` (D7.3), `UNKNOWN-EVALUATION-SPEC.md`, and `UNKNOWNS-BACKEND-CONTRACT.md` (the newer per-backend survey of `TYPICALLY`).
A ruling that comes out of this note is recorded in one of those, not here (repo `CLAUDE.md` §4).

---

## 1. The chain, written four ways

`alice.l4` declares `Jurisdiction` (SG, US), `Purpose` (Voting, Beer), `Person` (`birthdate IS A MAYBE DATE`) and `Citizen` (the same plus `` `is adult` IS A BOOLEAN TYPICALLY TRUE ``).
`age at` compares year, month and day; `majority for` is SG: voting 21, beer 18; US: voting 18, beer 21, so the two jurisdictions cross.
The chain birthdate → as_at → age → jurisdiction → purpose → adult is then written four ways:

| route                          | spelling                                                                                    | the presumption lives in                    |
| ------------------------------ | ------------------------------------------------------------------------------------------- | ------------------------------------------- |
| 1 `adult derived`              | `GIVETH A MAYBE BOOLEAN`; `WHEN NOTHING THEN NOTHING`                                       | nowhere; unknown stays unknown              |
| 2 `adult presumed`             | a rule `GIVEN `presumed adult` IS A BOOLEAN TYPICALLY TRUE`, read only in the `NOTHING` arm | a rule input at the end of the chain        |
| 2b `adult presumed by section` | the same default as a section `GIVEN`                                                       | a section input                             |
| 3 `adult stored`               | `citizen's `is adult``                                                                      | a stored field (Meng's model of 2026-10-09) |
| 3c `stored agrees with chain`  | route 3 compared against the derivation                                                     | an author-written consistency check         |

`as_at` is an input, not `TODAY`, so no run depends on the clock.

## 2. Results

Rows that matter are shown; Appendix B has all of them.
"presumed" is the envelope's `presumed` list.

### 2.1 Known birthdates: the chain is right, and purpose matters

Routes 1, 2 and 2b agree on every known birthdate under soft, with `presumed` empty; under hard, routes 2 and 2b refuse every row (§2.3).
Route 3 takes a `Citizen` and no jurisdiction or purpose, so it has no chain to agree with, and was not run on these rows.

| person | born       | as at      | SG Voting | SG Beer | US Voting | US Beer |
| ------ | ---------- | ---------- | --------- | ------- | --------- | ------- |
| Alice  | 2000-05-01 | 2026-10-09 | TRUE      |         |           |         |
| Bob    | 2006-01-01 | 2026-10-09 | FALSE     | TRUE    | TRUE      | FALSE   |
| Carol  | 2005-10-10 | 2026-10-09 | FALSE     |         |           |         |
| Carol  | 2005-10-10 | 2026-10-10 | TRUE      |         |           |         |

Bob can drink in Singapore and vote in America, and neither the other way round.
Carol becomes an adult for Singapore voting on her 21st birthday and not the day before.

### 2.2 Alice with no birthdate, SG Voting

| route                 | `birthdate` absent, soft                                    | `birthdate: null`, soft                 | absent, hard                                                    | `null`, hard                        |
| --------------------- | ----------------------------------------------------------- | --------------------------------------- | --------------------------------------------------------------- | ----------------------------------- |
| 1 derived             | `null`; presumed `person.birthdate`                         | `null`; presumed none                   | refused: `person.birthdate` missing                             | `null`; presumed none               |
| 2 presumed (rule)     | TRUE; presumed `person.birthdate`, `presumed adult`         | TRUE; presumed `presumed adult`         | refused: `presumed adult` missing                               | refused: `presumed adult` missing   |
| 2b presumed (section) | TRUE; presumed `person.birthdate`, `section presumed adult` | TRUE; presumed `section presumed adult` | refused                                                         | refused                             |
| 3 stored              | TRUE; presumed `citizen.is adult`                           | TRUE; presumed `citizen.is adult`       | refused, naming both `citizen.birthdate` and `citizen.is adult` | refused: `citizen.is adult` missing |

Supplying `"presumed adult": false` rebuts route 2 in both modes: FALSE, presumed none.
Supplying `"presumed adult": null` is refused in both modes: "null … never takes the TYPICALLY default".

### 2.3 Hard mode refuses the whole function, not the presumption

Under `--presumption hard`, routes 2 and 2b refuse **every** row, Bob's and Carol's included, whose birthdates are known and whose evaluation never reaches the `NOTHING` arm.
The message is the same on each: "Missing required field 'presumed adult' … presumption is hard, so the default is not used".
The decoder refuses an absent defaulted input before evaluation starts (`Machine.hs:4903–4908`, the `missing` check), while soft mode reports a default only when it is forced (`registerPresumable`, T6).
So the two modes are not symmetric: soft says "the answer rests on X" only when it does, and hard says "X exists" whether or not it was needed.

Route 1 under hard accepts `null` and refuses absent, so in hard mode the only way to say "we have no birthdate" is `null`.

### 2.4 The stored presumption and the chain never meet

Route 3 on Dave, born 2010-01-01, as at 2026-10-09 (age 16), and one Alice row:

| row                                         | soft                              | hard                |
| ------------------------------------------- | --------------------------------- | ------------------- |
| `is adult: true` supplied                   | TRUE; presumed none               | TRUE; presumed none |
| `is adult` omitted                          | TRUE; presumed `citizen.is adult` | refused             |
| `is adult: null` (Alice, `birthdate: null`) | refused (never takes the default) | refused             |

Nothing notices that TRUE contradicts the birthdate.
Route 3c, the author-written check, returns FALSE for both Dave rows under soft, and under hard refuses the omitted row; that FALSE is a value, not a diagnostic, and the author had to think of writing it.
With `is adult` omitted the check's FALSE rests on the presumption and says so (`presumed: citizen.is adult`), which is the one place the two mechanisms touched.

### 2.5 Construction inside the rules

| file        | field omitted at `WITH`                       | installed binary      | #551 binary |
| ----------- | --------------------------------------------- | --------------------- | ----------- |
| construct-a | `` `is adult` IS A BOOLEAN TYPICALLY TRUE ``  | refused: not supplied | TRUE        |
| construct-b | `birthdate IS A MAYBE DATE TYPICALLY NOTHING` | refused               | NOTHING     |
| construct-c | `birthdate IS A MAYBE DATE`                   | refused               | refused     |

`l4 run` has no `--presumption` flag (`l4 run --help`), and `EvalConfig.requestRecord` is `Nothing` for `#EVAL` and `l4 run`.
T4b says the switch reaches only what a request can supply.
So Meng's "under hard evaluation the instantiation would error that `is_adult` is a required field" has no instrument on either binary: today's refuses the construction in every mode, because no field default is applied at a `WITH` at all, and #551's fills it in every mode.
Neither has a mode; #551's documentation says a `WITH` fill is listed under `presumed` when the mode is hard, so there it is reported, not withheld.

### 2.6 The footgun, measured: `tmtowtdi.l4`

Three spellings of "a birth year the caller may leave out", one rule each, same input rows.

| spelling                               | absent, soft                                                                                                      | absent, hard                                                                                | `null`, either mode                                                   | 1999  |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ----- |
| A `MAYBE NUMBER`                       | unknown; presumed `year`                                                                                          | refused "(a MAYBE left out is NOTHING only while presumption is soft)"                      | unknown; presumed none                                                | known |
| B `MAYBE NUMBER TYPICALLY NOTHING`     | unknown; presumed `year`                                                                                          | refused "(it has a TYPICALLY default, but presumption is hard, so the default is not used)" | unknown; presumed none                                                | known |
| C `NUMBER TYPICALLY 2000`              | 2000; presumed `year`                                                                                             | refused (same text as B)                                                                    | **refused** in both modes: "null … never takes the TYPICALLY default" | 1999  |
| D `MAYBE NUMBER TYPICALLY JUST 2000`   | **parse error**: `unexpected 2000`                                                                                |                                                                                             |                                                                       |       |
| E `MAYBE NUMBER TYPICALLY (JUST 2000)` | **check error**: "must be a literal: a number, a string, or a nullary constructor such as TRUE, FALSE or NOTHING" |                                                                                             |                                                                       |       |

A and B give the same answer and the same `presumed` list on every row; they differ in one refusal message.
D does not parse and E does not check (`isTypicallyLiteral`, `TypeCheck.hs:2044`), so `NOTHING` is the only default a `MAYBE` can carry, and a `MAYBE` already has it.
`TYPICALLY NOTHING` therefore changes no answer at the `l4 batch` wire, only a message.
That is because a left-out `MAYBE`'s `NOTHING` is already a presumption there (T1b: listed under `presumed`, withheld under hard; `doc/tutorials/getting-started/l4-cli.md:438`), and what `TYPICALLY NOTHING` adds is one bit, that the field may be left out at a `WITH` inside the rules; D7.3 ruled it opt-in with that asymmetry in view ("Encoders annotate; callers over the wire do not have to", `SURFACE-SUGAR-CLUSTER-2026-09.md:86–88`).
It does change behaviour elsewhere, measured after review: at `#EVAL`, a section `GIVEN year IS A MAYBE NUMBER` read by a `CONSIDER` is an assumed term and errors, where the same input with `TYPICALLY NOTHING` answers "unknown" (`sec-a.l4`, `sec-b.l4`); `l4 export docassemble` accepts the plain `MAYBE` rule and refuses the `TYPICALLY NOTHING` one ("unsupported TYPICALLY default"); and the published schema carries `"default": null` for it (`JsonSchema.hs:156–158`, `FunctionSchema.hs:359`).
At a `WITH` it is D7.3's omission permit (§2.5).

### 2.7 An author's own fallback is an invisible presumption: `fallback.l4`

`WHEN NOTHING THEN TRUE` on Alice with `birthdate: null` gives TRUE with `presumed` empty, soft and hard alike.
With `birthdate` absent, soft lists `person.birthdate` (the NOTHING fill) and not the TRUE the arm chose.
Only `UseDefault` and `UseNothing` register a presumable (`Machine.hs:4917–4926`); a value an arm picks is a value.

---

## 3. What an author can reach for, and where the spellings differ

Six ways to write "we may not know X; assume Y when we do not", as measured above.

| #   | spelling                                 | answer when unknown | reported in `presumed`                                        | hard mode                                      | at a `WITH` (#551) |
| --- | ---------------------------------------- | ------------------- | ------------------------------------------------------------- | ---------------------------------------------- | ------------------ |
| 1   | `MAYBE T` + `WHEN NOTHING THEN NOTHING`  | unknown             | the NOTHING fill, if absent                                   | refuses absent, accepts `null`                 | must be written    |
| 2   | `MAYBE T` + `WHEN NOTHING THEN y`        | y                   | the NOTHING fill if absent; **never** the value the arm chose | as 1                                           | must be written    |
| 3   | `MAYBE T TYPICALLY NOTHING`              | as 1 or 2           | as 1 or 2                                                     | as 1, other message                            | may be omitted     |
| 4   | rule `GIVEN x IS A T TYPICALLY y`        | y                   | yes, when forced                                              | refuses a request that omits it, forced or not | n/a                |
| 5   | section `GIVEN x IS A T TYPICALLY y`     | y                   | yes, when forced                                              | the same                                       | n/a                |
| 6   | field `x IS A T TYPICALLY y` on a record | y                   | yes, when forced                                              | the same                                       | filled             |

Rows identical except for a message: 1 and 3 at the wire; 4 and 5 at the `l4 batch` wire (the spec's §1 footgun is ironed out there).
Rows that differ in the answer with no difference in `presumed`: 1 and 2.
Rows where the keyword means two unrelated things: 3 (the wire's `NOTHING` presumption, extended to a `WITH`) against 4–6 (a presumption).
And on the client side, absent and `null` are two spellings of "no value" that differ in `presumed` and in hard mode (§2.2), which a client author has to learn.

## 4. Gaps, silent ones first

- **G1 (silent).** An author's fallback in a `CONSIDER` arm is a presumption the envelope never reports (§2.7).
  A rule author who writes `WHEN NOTHING THEN TRUE` has made exactly the presumption `TYPICALLY TRUE` makes, and a service client cannot tell.
- **G2 (silent).** A stored presumption and a derivation that could rebut it never meet unless the author writes a check, and the check's output is a value, not a diagnostic (§2.4).
- **G3 (silent).** `TYPICALLY NOTHING` reads as a second presumption and is the wire's own `NOTHING` presumption extended to construction sites inside the rules (D7.3): at the batch wire it changes only a message (§2.6); at a `WITH` it permits omission (§2.5); on a section input it makes `#EVAL` discharge rather than leave an assumed term; and docassemble refuses it, which is a missing `NOTHING` arm in `lowerDefaultLit` (`Docassemble/Lower.hs:1456–1464`), not a design consequence.
  A `MAYBE` can carry no other default (§2.6, D and E).
  Corrected 2026-10-09 after the bench skeptic for this question: the first version called it "a presumption that is not one".
- **G5 (silent).** There is no presumption mode inside the rules: today's binary refuses a `WITH` that omits a defaulted field, in every mode, and #551's fills it, in every mode (§2.5); #551 lists such a fill under `presumed`, and nothing withholds it.
  Only the flag's absence from `l4 run --help` is loud.
- **G4 (loud, wrong scope).** Hard mode on `l4 batch` and on the service's direct path refuses at decode, so a presumption at the end of a chain blocks every request that omits it, including those whose evaluation never reaches it (§2.3).
  The service's wrapper path is already lazy there (`UNKNOWNS-BACKEND-CONTRACT.md:128–130`, measured), and TU-wire-b names lazy binding on the direct path as its own work item (TYPICALLY spec `:290`); so the scope is known and the item exists, and this note adds the measurement that a presumption input shows it plainly.
  It cannot say "refused because the answer would have rested on a presumption"; it says "a presumption is declared here".

## 5. What falls out of a tweak, and what needs syntax

Given the measurements, the smallest changes that remove a spelling or make a silent gap loud, in the order I would take them.

1. **Refuse at force, which is TU-wire-b's open item (G4).** Make hard mode's refusal happen where soft mode's report happens: when the defaulted input is forced, not when the request is decoded.
   Then Bob's row succeeds under hard, Alice's is refused with "the answer would rest on `presumed adult`", and the two modes become the same event with two outcomes.
   `EvalConfig.presumeDefaults`'s own doc (`EvaluateLazy.hs:111–115`) already describes lazy withholding for a section `GIVEN` under hard: one that nothing supplies "is an assumed term", which costs nothing unless forced.
   Route 2b shows why `l4 batch` refused it anyway: the refusal is the decoder's "Missing required field 'section presumed adult' in JSON object", so the section input had been lifted into the request record and met the decode-time check before the assumed-term behaviour could apply.
   Moving the refusal to force time gives the request's own decode the behaviour the evaluator already has.
   No syntax.
2. **`TYPICALLY` on a `MAYBE` (G3): keep D7.3, and fix the exporter.** Either refuse it and let every `MAYBE` input or field be omitted at every supply site inside the rules (smucclaw#645 as filed, amending D7.3's "and only then" and "never inferred from the type", `SURFACE-SUGAR-CLUSTER-2026-09.md:71–74`, and R8 rule 3 for the `MAYBE` case, `IMPLICIT-PROPS-DESIGN.md:1096`), or keep D7.3 and say on the reference page that `TYPICALLY NOTHING` extends the wire's `NOTHING` presumption to construction sites.
   The first version of this note recommended the first; the bench skeptic showed its premise wrong (G3 above) and that D7.3 was ruled with the measured asymmetry in view, so the recommendation is now the second, with `lowerDefaultLit`'s missing `NOTHING` arm fixed under either.
   It is Meng's call (bench card C3).
3. **Name the presumption arm (G1).** The one gap whose fix is a check rather than a change of semantics: an arm's value is a value, and nothing short of inspecting the arm can call it a presumption.
   The gap is a way to mark an expression as presumed so the envelope lists it and hard mode withholds it.
   Smallest form: an arm under `NOTHING` that returns a literal other than `NOTHING` is linted as "an unreported presumption; name a `TYPICALLY` input instead", which is route 2 today.
   Route 2 is also the route hard mode refuses wholesale until item 1 lands, so the lint waits on it.
   A new keyword is the alternative and is not needed to make the behaviour visible.
4. **Let a stored presumption know its rebuttal (G2).** No tweak gives this.
   It needs either a declared precedence (supplied over derived over presumed, with a clash flagged), which is the open ruling from 2026-10-09, or the author's check as idiom, documented.
5. **G5 stays a gap** until presumption mode is a property of an evaluation rather than of a request; that is a larger design and belongs to `UNKNOWN-EVALUATION-SPEC.md`.

## 6. Open for Meng

- Does an explicit supply of `is adult` win over a contradicting birthdate, or is the clash an error? (G2; asked 2026-10-09, not yet ruled. §7 settles precedence within one node, asserted over derived; this is two nodes, a stored field and a derivation, that ought to agree, and §7 does not reach it.)
- Should `TYPICALLY` be refused on a `MAYBE`, amending D7.3? (G3.)
- Should hard mode refuse at force rather than at decode? (G4; a behaviour change to `l4 batch` and the service, so a service client would notice.)

## 7. Ruled in chat, 2026-10-09: node assertion is default-open, opted out by `@nonassertable`

Meng, 2026-10-09: _"How about we do V5, and flip V4 with a nonassertable annotation."_
Recorded here from chat.
Its owning document is `UNKNOWN-EVALUATION-SPEC.md` (node valuation), and until the ruling is written there it is not decided (repo `CLAUDE.md` §4); that recording is owed in the revision that follows this note.
The variants and guards the ruling names, from the same conversation: V0, the fold as a type (`v0-enum.l4`); V1, the node as a `MAYBE` input with the derivation as its fallback (`v1-node-input.l4`); V2, the node as a `TYPICALLY` input; V3, `TYPICALLY` on a conclusion, `unmarried MEANS single OR divorced OR widowed TYPICALLY TRUE` (`v3-typically-means.l4`: a parse error today; T1 rules only on a computed field of a record, so a `TYPICALLY` on a definition is unruled); V4, an annotation naming the assertable nodes; V5, every named node assertable with no syntax; V6, Governatori-style defeaters.
Guard 1 is the `asserted` list in the envelope; Guard 2 is that the exported function's own result cannot be asserted.

- Every named derived node (a `MEANS`) may be valued by a request, and an asserted value beats the derivation and any `TYPICALLY`.
- `@nonassertable` on a node (Meng's spelling) forbids it: the node's truth must come from its derivation.
  The annotation travels with the program; projected to an abductive engine such as s(CASP) it means the node is not abducible, so an explanation must descend to the leaves.
- In our evaluator runtimes the exported function's own result is nonassertable by construction.
  This is a property of our request decoder only (Meng, 2026-10-09): in an abductive projection the root is the goal, and another engine does the work.
- The envelope lists every asserted node the answer forced, as `asserted`, beside `presumed`.
- A node must be named to be addressable; a subexpression an author wants assertable gets a `WHERE` or sibling definition.
- Building it touches the ladder, the service and the envelope, so it goes on a bench, not in a slice.

Why default-open: it is what the ladder already does, where a value on a folded group overrides its children (`ts-shared/ladder-core/src/layout.ts:1033–1040`); for abduction it is a policy rather than a given, since abducibles are declared, and L4's Blawx export today declares only inputs abducible (`jl4-core/test/BlawxAssumeSpec.hs:159–168`), so default-open there means emitting `#abducible` for every named node not marked; and the opt-out makes the author state that a node is a conclusion.
Its silent failure, a conclusion left unmarked, is made visible by the `asserted` list.

## 8. How the design projects to each export (reasoned 2026-10-09; _census_ rows are from the TYPICALLY spec §2, measured 2026-10-01, or from `UNKNOWNS-BACKEND-CONTRACT.md` §6, 2026-10-08, as marked)

Elements projected: the four sources (supplied, asserted, derived, presumed); default-open assertion with `@nonassertable`; `TYPICALLY` on a conclusion with precedence asserted > derived > presumed (V3; T1, TYPICALLY spec `:275`, makes a `TYPICALLY` on a computed field of a record a check error and does not reach a definition, so V3 is unruled; proposed here, not ruled); the `asserted`/`presumed` disclosure.

| target                       | presumed conclusion                                                                                                                                                     | asserted node                                                                      | `@nonassertable`                         | lost, and how loudly                                                                                                                                                                                                                                           |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Catala                       | native: `definition` + `exception` (default calculus)                                                                                                                   | `context` variable (_census_: today's `TYPICALLY` lowering)                        | plain `definition`                       | nothing structural; check against `CATALA-EXPORT-SPEC` §4.4                                                                                                                                                                                                    |
| Blawx / s(CASP)              | default rule + defeater (`according_to`/`holds`/`blawx_defeated`)                                                                                                       | `#abducible` per named node                                                        | not abducible                            | _census_: a `GIVEN` default is dropped without a word today (TYPICALLY spec `:68`; the R-TYPICALLY note at `Relational/Lower.hs:2843` covers `ASSUME` only), and "dropped, disclosed" is `BLAWX-EXPORT-SPEC` §5.1's ruling, not yet the code; flips to lowered |
| OpenFisca                    | formula with the presumption as fallback                                                                                                                                | native, already default-open: an input suppresses the formula                      | **lost**: no read-only computed variable | silent, and OpenFisca has no fidelity report to say so (TYPICALLY spec `:68`); _census_: enum `TYPICALLY` already replaced by the first member, exit 0 (`OpenFisca/Lower.hs:735`)                                                                              |
| docassemble                  | `code` block placed earlier in the YAML than the derivation, since docassemble falls back to earlier blocks                                                             | `question` + `code` for one variable                                               | code-only                                | _census_: `TYPICALLY` pre-fills the question and the user submits the screen, so answered and pre-filled are **not** distinguished today (`Docassemble/Lower.hs:794–799`); the design needs them to be                                                         |
| DMN / dmn-md                 | catch-all row: last under FIRST, lowest output priority under PRIORITY                                                                                                  | optional input `x asserted` + first row (V1 as a table)                            | emit no such input                       | _census_: `TYPICALLY` dropped silently today; emit assertion inputs for named nodes only, listed in the report                                                                                                                                                 |
| BPMN                         | orthogonal                                                                                                                                                              | via the decision called                                                            | as DMN                                   | nothing new                                                                                                                                                                                                                                                    |
| yscript                      | no home; T5b rules that yscript refuses a module whose exported rule reads a defaulted input, built by #550 (TYPICALLY spec `:337`; `UNKNOWNS-BACKEND-CONTRACT.md:212`) | unmeasured                                                                         | unmeasured                               | today dropped silently (no `TYPICALLY` handling under `Yscript/`); loud once #550 lands; probe before claiming anything about assertion                                                                                                                        |
| jl4-service / batch / MCP    | the home: V3, refuse-at-force                                                                                                                                           | request keys for named nodes; `asserted` in envelope; nested `MAYBE` wire spelling | 4xx naming the node                      | nothing                                                                                                                                                                                                                                                        |
| jl4-mlir / WASM              | marshaller needs a second argument set                                                                                                                                  | same                                                                               | same                                     | _UBC §6.1_: already drops `TYPICALLY`, no `presumed`, zero-fills; divergence widens                                                                                                                                                                            |
| ladder (`render`)            | `effectiveValuation` lays defaults under answers                                                                                                                        | valuing a folded node (the origin)                                                 | greyed, unclickable                      | nothing; plan gains coarse-first order                                                                                                                                                                                                                         |
| NLG / Markdown               | "it is presumed that …"                                                                                                                                                 | "you told us that …"                                                               | "a conclusion, derived from …"           | nothing                                                                                                                                                                                                                                                        |
| verify / `l4 prove` (parked) | soft constraint, dropped first on unsat                                                                                                                                 | an assumption; the model's assignment is `asserted`                                | solver must derive it                    | nothing; abduction is this query                                                                                                                                                                                                                               |

Aspirations: PROLEG (exceptions are defeaters; best fit, and carries burden of proof), LegalRuleML (`Override` keeps the precedence), direct s(CASP) (Blawx's row without Blawx).

Four families: natively defeasible (Catala, Blawx, PROLEG) take the design as idiom; natively default-open (OpenFisca, docassemble) take assertion free and lose `@nonassertable`, OpenFisca silently, with yscript unmeasured; table/dataflow (DMN, WASM) need V1's desugaring and a report row; regulative/proof (BPMN, LTS, verify) are orthogonal or already abductive.
Obligations: every exporter with a fidelity report (DMN, dmn-md, BPMN, docassemble, Blawx) gains "assertable nodes" and "presumed conclusions" rows, emitted-as or dropped; OpenFisca and yscript have none, so their limits pages carry it; the OpenFisca enum default is a standing silent wrong answer independent of this design.
Guard 2 appears in no target column: it is ours alone.

## 9. What review changed (2026-10-09)

An Opus adversarial review of the first version found 28 problems, 7 of them overturning a sentence; each was re-verified against the tree at `c6d081622` or re-run on the installed binary before it was applied, and all held.
The overturned sentences: the installed binary "matches the census on every row" (it honours what the pre-W2/W3 census refused); "all four routes agree … soft and hard" (hard refuses routes 2 and 2b, and route 3 has no chain); `TYPICALLY NOTHING` "changes no answer" (it changes `#EVAL` on a section input, is refused by docassemble, and is published as `"default": null`); G5's "always fill" (true of #551, not of today's binary); §7 "decided when filed" (not decided until recorded in its owning document); Blawx "dropped, disclosed" (that is the ruling, not the code); and docassemble "answered/pre-filled already distinguished" (the exporter's own note says user-confirmed).
The rest: line numbers moved to the new base after #553/#554; four raw outputs were missing from Appendix B; two table cells understated a refusal; `fallback.l4`'s row 2 was misread in §3; G4's scope was generalised beyond `l4 batch` and the direct path, where `UNKNOWNS-BACKEND-CONTRACT` already records the wrapper path as lazy and TU-wire-b names the item; §5.2 ignored that option 1 amends D7.3 and R8 rule 3; §5.3's lint fired on the honest route; §6 Q1 and §7 were not related; V1–V6 and the guards were undefined; the abduction rationale assumed what abducibles are declared; V3 was not related to T1; docassemble falls back upward, not downward; the mlir row was mis-attributed; the yscript row ignored T5b; OpenFisca has no fidelity report; and PRIORITY's catch-all wins by priority, not position.

---

## Appendix A. Probe files

As run; `.json` files are `l4 batch --inputs` rows.

**`alice.l4`**

```text
-- The chain birthdate -> as_at -> age -> jurisdiction -> purpose -> adult,
-- written four ways with what the tree has today.

DECLARE Jurisdiction IS ONE OF SG, US
DECLARE Purpose      IS ONE OF Voting, Beer

DECLARE Person HAS
  name      IS A STRING
  birthdate IS A MAYBE DATE

-- Meng's model: a stored field carrying a literal presumption.
DECLARE Citizen HAS
  name       IS A STRING
  birthdate  IS A MAYBE DATE
  `is adult` IS A BOOLEAN TYPICALLY TRUE

GIVEN birth IS A DATE
      asat  IS A DATE
GIVETH A NUMBER
`age at` MEANS
  IF    DATE_MONTH asat GREATER THAN DATE_MONTH birth
     OR (DATE_MONTH asat EQUALS DATE_MONTH birth AND DATE_DAY asat AT LEAST DATE_DAY birth)
  THEN DATE_YEAR asat MINUS DATE_YEAR birth
  ELSE DATE_YEAR asat MINUS DATE_YEAR birth MINUS 1

GIVEN p IS A Purpose
GIVETH A NUMBER
`sg majority for` MEANS
  CONSIDER p
    WHEN Voting THEN 21
    WHEN Beer   THEN 18

GIVEN p IS A Purpose
GIVETH A NUMBER
`us majority for` MEANS
  CONSIDER p
    WHEN Voting THEN 18
    WHEN Beer   THEN 21

GIVEN j IS A Jurisdiction
      p IS A Purpose
GIVETH A NUMBER
`majority for` MEANS
  CONSIDER j
    WHEN SG THEN `sg majority for` p
    WHEN US THEN `us majority for` p

-- Route 1: derived; an unknown birthdate stays unknown.
@export Derived
GIVEN person IS A Person
      asat   IS A DATE
      j      IS A Jurisdiction
      p      IS A Purpose
GIVETH A MAYBE BOOLEAN
`adult derived` MEANS
  CONSIDER person's birthdate
    WHEN JUST b  THEN JUST (`age at` b asat AT LEAST `majority for` j p)
    WHEN NOTHING THEN NOTHING

-- Route 2: derived where it can be, presumed at the end where it cannot.
-- The presumption is a rule GIVEN with a literal default, read only in the NOTHING arm.
@export Presumed
GIVEN person IS A Person
      asat   IS A DATE
      j      IS A Jurisdiction
      p      IS A Purpose
      `presumed adult` IS A BOOLEAN TYPICALLY TRUE
GIVETH A BOOLEAN
`adult presumed` MEANS
  CONSIDER person's birthdate
    WHEN JUST b  THEN `age at` b asat AT LEAST `majority for` j p
    WHEN NOTHING THEN `presumed adult`

-- Route 3: Meng's model; the stored field answers, and the chain is not consulted.
@export Stored
GIVEN citizen IS A Citizen
GIVETH A BOOLEAN
`adult stored` MEANS citizen's `is adult`

-- Route 3 with a check: does the stored presumption agree with the chain?
@export StoredChecked
GIVEN citizen IS A Citizen
      asat    IS A DATE
      j       IS A Jurisdiction
      p       IS A Purpose
GIVETH A BOOLEAN
`stored agrees with chain` MEANS
  CONSIDER citizen's birthdate
    WHEN JUST b  THEN citizen's `is adult` EQUALS (`age at` b asat AT LEAST `majority for` j p)
    WHEN NOTHING THEN TRUE

-- Route 2b: the same presumption as a section GIVEN, which hard mode treats differently.
§ `Presumptions`
    GIVEN `section presumed adult` IS A BOOLEAN TYPICALLY TRUE

@export PresumedSection
GIVEN person IS A Person
      asat   IS A DATE
      j      IS A Jurisdiction
      p      IS A Purpose
GIVETH A BOOLEAN
`adult presumed by section` MEANS
  CONSIDER person's birthdate
    WHEN JUST b  THEN `age at` b asat AT LEAST `majority for` j p
    WHEN NOTHING THEN `section presumed adult`
```

**`chain.json`**

```text
[
 {"person":{"name":"Alice"},                              "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"person":{"name":"Alice","birthdate":null},             "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"person":{"name":"Alice","birthdate":"2000-05-01"},     "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"person":{"name":"Bob","birthdate":"2006-01-01"},       "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"person":{"name":"Bob","birthdate":"2006-01-01"},       "asat":"2026-10-09","j":"SG","p":"Beer"},
 {"person":{"name":"Bob","birthdate":"2006-01-01"},       "asat":"2026-10-09","j":"US","p":"Voting"},
 {"person":{"name":"Bob","birthdate":"2006-01-01"},       "asat":"2026-10-09","j":"US","p":"Beer"},
 {"person":{"name":"Carol","birthdate":"2005-10-10"},     "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"person":{"name":"Carol","birthdate":"2005-10-10"},     "asat":"2026-10-10","j":"SG","p":"Voting"}
]
```

**`construct-a.l4`**

```text
-- Construction inside the rules: omit a BOOLEAN field that has TYPICALLY TRUE.
DECLARE Citizen HAS
  name       IS A STRING
  birthdate  IS A MAYBE DATE
  `is adult` IS A BOOLEAN TYPICALLY TRUE

alice MEANS Citizen WITH
  name      IS "Alice"
  birthdate IS NOTHING

#EVAL alice's `is adult`
```

**`construct-b.l4`**

```text
-- Construction inside the rules: omit a MAYBE field declared TYPICALLY NOTHING (D7.3).
DECLARE Person HAS
  name      IS A STRING
  birthdate IS A MAYBE DATE TYPICALLY NOTHING

bob MEANS Person WITH
  name IS "Bob"

#EVAL bob's birthdate
```

**`construct-c.l4`**

```text
-- Construction inside the rules: omit a plain MAYBE field, no TYPICALLY.
DECLARE Person HAS
  name      IS A STRING
  birthdate IS A MAYBE DATE

carol MEANS Person WITH
  name IS "Carol"

#EVAL carol's birthdate
```

**`fallback.json`**

```text
[{"person":{"name":"Alice","birthdate":null},"asat":"2026-10-09"},{"person":{"name":"Alice"},"asat":"2026-10-09"}]
```

**`fallback.l4`**

```text
-- An author-written fallback in the NOTHING arm: is it reported as a presumption?
DECLARE Person HAS
  name      IS A STRING
  birthdate IS A MAYBE DATE

@export Fallback
GIVEN person IS A Person
      asat   IS A DATE
GIVETH A BOOLEAN
`adult fallback` MEANS
  CONSIDER person's birthdate
    WHEN JUST b  THEN DATE_YEAR asat MINUS DATE_YEAR b AT LEAST 21
    WHEN NOTHING THEN TRUE
```

**`nested.json`**

```text
[{"asat":"2026-10-09"},
 {"birthdate":null,"asat":"2026-10-09"},
 {"birthdate":"2000-05-01","asat":"2026-10-09"},
 {"birthdate":{"JUST":null},"asat":"2026-10-09"},
 {"birthdate":[null],"asat":"2026-10-09"}]
```

**`nested.l4`**

```text
-- As God intended: the two epistemic states in the type, not in a mode switch.
-- NOTHING = nobody said; JUST NOTHING = we asked, there is none; JUST (JUST d) = known.
@export Nested
GIVEN birthdate IS A MAYBE (MAYBE DATE)
      asat      IS A DATE
GIVETH A STRING
`adult nested` MEANS
  CONSIDER birthdate
    WHEN NOTHING          THEN "unsaid: presume adult"
    WHEN JUST NOTHING     THEN "known unknown: cannot say"
    WHEN JUST (JUST b)    THEN IF DATE_YEAR asat MINUS DATE_YEAR b AT LEAST 21 THEN "adult" ELSE "minor"
```

**`presumed-extra.json`**

```text
[
 {"person":{"name":"Alice","birthdate":null}, "asat":"2026-10-09","j":"SG","p":"Voting", "presumed adult": false},
 {"person":{"name":"Alice","birthdate":null}, "asat":"2026-10-09","j":"SG","p":"Voting", "presumed adult": null}
]
```

**`sec-a.l4`**

```text
-- A section GIVEN that is a plain MAYBE, read by a CONSIDER at #EVAL.
§ `Inputs`
    GIVEN year IS A MAYBE NUMBER

`a` MEANS
  CONSIDER year
    WHEN JUST y  THEN "known"
    WHEN NOTHING THEN "unknown"

#EVAL `a`
```

**`sec-b.l4`**

```text
-- A section GIVEN MAYBE with TYPICALLY NOTHING, read by a CONSIDER at #EVAL.
§ `Inputs`
    GIVEN year IS A MAYBE NUMBER TYPICALLY NOTHING

`a` MEANS
  CONSIDER year
    WHEN JUST y  THEN "known"
    WHEN NOTHING THEN "unknown"

#EVAL `a`
```

**`stored.json`**

```text
[
 {"citizen":{"name":"Alice","birthdate":null}},
 {"citizen":{"name":"Alice"}},
 {"citizen":{"name":"Alice","birthdate":null,"is adult":null}},
 {"citizen":{"name":"Dave","birthdate":"2010-01-01","is adult":true}},
 {"citizen":{"name":"Dave","birthdate":"2010-01-01"}}
]
```

**`storedchecked.json`**

```text
[
 {"citizen":{"name":"Dave","birthdate":"2010-01-01","is adult":true}, "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"citizen":{"name":"Dave","birthdate":"2010-01-01"},                 "asat":"2026-10-09","j":"SG","p":"Voting"},
 {"citizen":{"name":"Alice","birthdate":null},                        "asat":"2026-10-09","j":"SG","p":"Voting"}
]
```

**`tmtowtdi-just.l4`**

```text
-- A MAYBE with a non-NOTHING default: is JUST 2000 a literal?
@export D
GIVEN year IS A MAYBE NUMBER TYPICALLY JUST 2000
GIVETH A STRING
`d` MEANS
  CONSIDER year
    WHEN JUST y  THEN "known"
    WHEN NOTHING THEN "unknown"
```

**`tmtowtdi-just2.l4`**

```text
-- As tmtowtdi-just.l4, with the JUST parenthesised.
@export E
GIVEN year IS A MAYBE NUMBER TYPICALLY (JUST 2000)
GIVETH A STRING
`e` MEANS
  CONSIDER year
    WHEN JUST y  THEN "known"
    WHEN NOTHING THEN "unknown"
```

**`tmtowtdi.json`**

```text
[{}, {"year": null}, {"year": 1999}]
```

**`tmtowtdi.l4`**

```text
-- Three spellings of "a birth year the caller may leave out", one rule each.
-- The bodies are the same shape: each reports what it saw.

@export A
GIVEN year IS A MAYBE NUMBER
GIVETH A STRING
`a` MEANS
  CONSIDER year
    WHEN JUST y  THEN "known"
    WHEN NOTHING THEN "unknown"

@export B
GIVEN year IS A MAYBE NUMBER TYPICALLY NOTHING
GIVETH A STRING
`b` MEANS
  CONSIDER year
    WHEN JUST y  THEN "known"
    WHEN NOTHING THEN "unknown"

@export C
GIVEN year IS A NUMBER TYPICALLY 2000
GIVETH A NUMBER
`c` MEANS year
```

**`v0-enum.l4`**

```text
DECLARE UnmarriedKind IS ONE OF Single, Divorced, Widowed
DECLARE MaritalStatus IS ONE OF
  Married
  Unmarried HAS kind IS A MAYBE UnmarriedKind

GIVEN status IS A MaritalStatus
GIVETH A BOOLEAN
`eligible` MEANS
  CONSIDER status
    WHEN Married     THEN TRUE
    WHEN Unmarried k THEN TRUE

#EVAL `eligible` (Unmarried NOTHING)
#EVAL `eligible` (Unmarried (JUST Divorced))
```

**`v1-node-input.l4`**

```text
GIVEN married   IS A BOOLEAN
      single    IS A BOOLEAN
      divorced  IS A BOOLEAN
      widowed   IS A BOOLEAN
      unmarried IS A MAYBE BOOLEAN
GIVETH A BOOLEAN
`eligible` MEANS married OR `unmarried status`
  WHERE
    `unmarried status` MEANS
      CONSIDER unmarried
        WHEN JUST u  THEN u
        WHEN NOTHING THEN single OR divorced OR widowed

#EVAL `eligible` FALSE FALSE FALSE FALSE (JUST TRUE)
#EVAL `eligible` FALSE FALSE TRUE FALSE NOTHING
```

**`v3-typically-means.l4`**

```text
GIVEN single   IS A BOOLEAN
      divorced IS A BOOLEAN
      widowed  IS A BOOLEAN
GIVETH A BOOLEAN
`unmarried` MEANS single OR divorced OR widowed TYPICALLY TRUE
```

## Appendix B. Raw outputs

`<name>-<mode>.json` is `l4 batch ... --presumption <mode> -f json -c`; `*-check.txt` is `l4 check`; `*-run.txt` is `l4 run` on the installed binary; `construct-*-installed.txt` and `construct-*-551.txt` are `l4 run` on the two binaries; `tmtowtdi-docassemble.txt` is `l4 export docassemble`.

**`out/construct-a-551.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     construct-a.l4
  Hidden:   no
  Range:    11:1-11:25
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  TRUE
Evaluation[1] @ construct-a.l4:11:1-25

Result:
  TRUE


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

**`out/construct-a-installed.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     construct-a.l4
  Hidden:   no
  Range:    7:13-9:23
  Source:   check
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
    In this use of

      Citizen (defined at construct-a.l4:2:9-16)

    you have not supplied these inputs:

      `is adult` of type BOOLEAN
```

**`out/construct-b-551.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     construct-b.l4
  Hidden:   no
  Range:    9:1-9:22
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  NOTHING
Evaluation[1] @ construct-b.l4:9:1-22

Result:
  NOTHING


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

**`out/construct-b-installed.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     construct-b.l4
  Hidden:   no
  Range:    6:11-7:16
  Source:   check
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
    In this use of

      Person (defined at construct-b.l4:2:9-15)

    you have not supplied these inputs:

      birthdate of type MAYBE OF DATE
```

**`out/construct-c-551.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     construct-c.l4
  Hidden:   no
  Range:    6:13-7:18
  Source:   check
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
    In this use of

      Person (defined at construct-c.l4:2:9-15)

    you have not supplied these inputs:

      birthdate of type MAYBE OF DATE
```

**`out/construct-c-installed.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     construct-c.l4
  Hidden:   no
  Range:    6:13-7:18
  Source:   check
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
    In this use of

      Person (defined at construct-c.l4:2:9-15)

    you have not supplied these inputs:

      birthdate of type MAYBE OF DATE
```

**`out/derived-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'person.birthdate' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'person.birthdate' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":null,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2000-05-01","name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-10","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/derived-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"name":"Alice"}},"output":[{"result":null,"trace":null}],"presumed":["person.birthdate"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":null,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2000-05-01","name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-10","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/fallback-hard.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Missing required field 'person.birthdate' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)"],"input":{"asat":"2026-10-09","person":{"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'person.birthdate' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/fallback-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","person":{"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["person.birthdate"],"status":"success"}
]
```

**`out/nested-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'birthdate' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)"],"input":{"asat":"2026-10-09"},"output":[{"result":{"error":"Missing required field 'birthdate' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","birthdate":null},"output":[{"result":"unsaid: presume adult","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","birthdate":"2000-05-01"},"output":[{"result":"adult","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Expected JSON string for DATE for field 'birthdate' but got: Object (fromList [(\"JUST\",Null)])"],"input":{"asat":"2026-10-09","birthdate":{"JUST":null}},"output":[{"result":{"error":"Expected JSON string for DATE for field 'birthdate' but got: Object (fromList [(\"JUST\",Null)])\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Expected JSON string for DATE for field 'birthdate' but got: Array [Null]"],"input":{"asat":"2026-10-09","birthdate":[null]},"output":[{"result":{"error":"Expected JSON string for DATE for field 'birthdate' but got: Array [Null]\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/nested-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09"},"output":[{"result":"unsaid: presume adult","trace":null}],"presumed":["birthdate"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","birthdate":null},"output":[{"result":"unsaid: presume adult","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","birthdate":"2000-05-01"},"output":[{"result":"adult","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Expected JSON string for DATE for field 'birthdate' but got: Object (fromList [(\"JUST\",Null)])"],"input":{"asat":"2026-10-09","birthdate":{"JUST":null}},"output":[{"result":{"error":"Expected JSON string for DATE for field 'birthdate' but got: Object (fromList [(\"JUST\",Null)])\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Expected JSON string for DATE for field 'birthdate' but got: Array [Null]"],"input":{"asat":"2026-10-09","birthdate":[null]},"output":[{"result":{"error":"Expected JSON string for DATE for field 'birthdate' but got: Array [Null]\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/presumed-extra-hard.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"},"presumed adult":false},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Field 'presumed adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"},"presumed adult":null},"output":[{"result":{"error":"Field 'presumed adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/presumed-extra-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"},"presumed adult":false},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Field 'presumed adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"},"presumed adult":null},"output":[{"result":{"error":"Field 'presumed adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/presumed-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2000-05-01","name":"Alice"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"US","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"US","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-10","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":{"error":"Missing required field 'presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/presumed-section-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2000-05-01","name":"Alice"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"US","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"US","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-10","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":{"error":"Missing required field 'section presumed adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/presumed-section-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["person.birthdate","section presumed adult"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["section presumed adult"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2000-05-01","name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-10","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/presumed-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["person.birthdate","presumed adult"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":null,"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["presumed adult"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2000-05-01","name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Voting","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"US","p":"Beer","person":{"birthdate":"2006-01-01","name":"Bob"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-10","j":"SG","p":"Voting","person":{"birthdate":"2005-10-10","name":"Carol"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/sec-a-run.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     sec-a.l4
  Hidden:   no
  Range:    10:1-10:10
  Source:   eval
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
    The value
      year
    reached a CONSIDER that has no branch for it.
    Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
    The typechecker's exhaustiveness warning lists all missing branches.

Evaluation[1] @ sec-a.l4:10:1-10

Result:
  The value
    year
  reached a CONSIDER that has no branch for it.
  Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
  The typechecker's exhaustiveness warning lists all missing branches.


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

**`out/sec-b-run.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     sec-b.l4
  Hidden:   no
  Range:    10:1-10:10
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  "unknown"
Evaluation[1] @ sec-b.l4:10:1-10

Result:
  "unknown"


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

**`out/stored-checked-hard.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","citizen":{"birthdate":"2010-01-01","is adult":true,"name":"Dave"},"j":"SG","p":"Voting"},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","citizen":{"birthdate":"2010-01-01","name":"Dave"},"j":"SG","p":"Voting"},"output":[{"result":{"error":"Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"asat":"2026-10-09","citizen":{"birthdate":null,"name":"Alice"},"j":"SG","p":"Voting"},"output":[{"result":{"error":"Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/stored-checked-soft.json`**

```text
[
  {"diagnostics":[],"input":{"asat":"2026-10-09","citizen":{"birthdate":"2010-01-01","is adult":true,"name":"Dave"},"j":"SG","p":"Voting"},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","citizen":{"birthdate":"2010-01-01","name":"Dave"},"j":"SG","p":"Voting"},"output":[{"result":false,"trace":null}],"presumed":["citizen.is adult"],"status":"success"},
  {"diagnostics":[],"input":{"asat":"2026-10-09","citizen":{"birthdate":null,"name":"Alice"},"j":"SG","p":"Voting"},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/stored-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"citizen":{"birthdate":null,"name":"Alice"}},"output":[{"result":{"error":"Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Missing required fields 'citizen.birthdate' (a MAYBE left out is NOTHING only while presumption is soft), 'citizen.is adult' (it has a TYPICALLY default, but presumption is hard, so the default is not used) in JSON object"],"input":{"citizen":{"name":"Alice"}},"output":[{"result":{"error":"Missing required fields 'citizen.birthdate' (a MAYBE left out is NOTHING only while presumption is soft), 'citizen.is adult' (it has a TYPICALLY default, but presumption is hard, so the default is not used) in JSON object\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Field 'citizen.is adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"],"input":{"citizen":{"birthdate":null,"is adult":null,"name":"Alice"}},"output":[{"result":{"error":"Field 'citizen.is adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"citizen":{"birthdate":"2010-01-01","is adult":true,"name":"Dave"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":["Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{"citizen":{"birthdate":"2010-01-01","name":"Dave"}},"output":[{"result":{"error":"Missing required field 'citizen.is adult' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"}
]
```

**`out/stored-soft.json`**

```text
[
  {"diagnostics":[],"input":{"citizen":{"birthdate":null,"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["citizen.is adult"],"status":"success"},
  {"diagnostics":[],"input":{"citizen":{"name":"Alice"}},"output":[{"result":true,"trace":null}],"presumed":["citizen.is adult"],"status":"success"},
  {"diagnostics":["Field 'citizen.is adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"],"input":{"citizen":{"birthdate":null,"is adult":null,"name":"Alice"}},"output":[{"result":{"error":"Field 'citizen.is adult' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"citizen":{"birthdate":"2010-01-01","is adult":true,"name":"Dave"}},"output":[{"result":true,"trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"citizen":{"birthdate":"2010-01-01","name":"Dave"}},"output":[{"result":true,"trace":null}],"presumed":["citizen.is adult"],"status":"success"}
]
```

**`out/tmtowtdi-a-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'year' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)"],"input":{},"output":[{"result":{"error":"Missing required field 'year' in JSON object (a MAYBE left out is NOTHING only while presumption is soft)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"year":null},"output":[{"result":"unknown","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"year":1999},"output":[{"result":"known","trace":null}],"presumed":[],"status":"success"}
]
```

**`out/tmtowtdi-a-soft.json`**

```text
[
  {"diagnostics":[],"input":{},"output":[{"result":"unknown","trace":null}],"presumed":["year"],"status":"success"},
  {"diagnostics":[],"input":{"year":null},"output":[{"result":"unknown","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"year":1999},"output":[{"result":"known","trace":null}],"presumed":[],"status":"success"}
]
```

**`out/tmtowtdi-b-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'year' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{},"output":[{"result":{"error":"Missing required field 'year' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"year":null},"output":[{"result":"unknown","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"year":1999},"output":[{"result":"known","trace":null}],"presumed":[],"status":"success"}
]
```

**`out/tmtowtdi-b-soft.json`**

```text
[
  {"diagnostics":[],"input":{},"output":[{"result":"unknown","trace":null}],"presumed":["year"],"status":"success"},
  {"diagnostics":[],"input":{"year":null},"output":[{"result":"unknown","trace":null}],"presumed":[],"status":"success"},
  {"diagnostics":[],"input":{"year":1999},"output":[{"result":"known","trace":null}],"presumed":[],"status":"success"}
]
```

**`out/tmtowtdi-c-hard.json`**

```text
[
  {"diagnostics":["Missing required field 'year' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)"],"input":{},"output":[{"result":{"error":"Missing required field 'year' in JSON object (it has a TYPICALLY default, but presumption is hard, so the default is not used)\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":["Field 'year' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"],"input":{"year":null},"output":[{"result":{"error":"Field 'year' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"year":1999},"output":[{"result":1999,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/tmtowtdi-c-soft.json`**

```text
[
  {"diagnostics":[],"input":{},"output":[{"result":2000,"trace":null}],"presumed":["year"],"status":"success"},
  {"diagnostics":["Field 'year' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"],"input":{"year":null},"output":[{"result":{"error":"Field 'year' is null, which means the value is not known, and that never takes the TYPICALLY default: supply a value, or leave it out to use the default\n"},"trace":null}],"presumed":[],"status":"error"},
  {"diagnostics":[],"input":{"year":1999},"output":[{"result":1999,"trace":null}],"presumed":[],"status":"success"}
]
```

**`out/tmtowtdi-docassemble.txt`**

```text
l4 export docassemble: cannot compile this module to a docassemble interview:
  - in `b`: unsupported TYPICALLY default — v1 accepts literals and nullary enum constructors only
```

**`out/tmtowtdi-just-check.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     tmtowtdi-just.l4
  Hidden:   no
  Range:    3:45-3:49
  Source:   parser
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
      |
    3 | GIVEN year IS A MAYBE NUMBER TYPICALLY JUST 2000
      |                                             ^^^^
    unexpected 2000
    expecting ,, ASSUME, DECIDE, DECLARE, GIVES, GIVETH, identifier, or space token
```

**`out/tmtowtdi-just2-check.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     tmtowtdi-just2.l4
  Hidden:   no
  Range:    5:1-5:4
  Source:   check
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
    The TYPICALLY value for `year` must be a literal:
    a number, a string, or a nullary constructor such as TRUE, FALSE or NOTHING.
```

**`out/v0-enum-run.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     v0-enum.l4
  Hidden:   no
  Range:    13:1-13:37
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  TRUE
File:     v0-enum.l4
  Hidden:   no
  Range:    14:1-14:45
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  TRUE
Evaluation[1] @ v0-enum.l4:13:1-37

Result:
  TRUE


Trace:
  (no trace captured; add #EVALTRACE to the directive)


Evaluation[2] @ v0-enum.l4:14:1-45

Result:
  TRUE


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

**`out/v1-node-input-run.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     v1-node-input.l4
  Hidden:   no
  Range:    14:1-14:53
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  TRUE
File:     v1-node-input.l4
  Hidden:   no
  Range:    15:1-15:48
  Source:   eval
  Severity: DiagnosticSeverity_Information
  Code:     <none>
  Message:  TRUE
Evaluation[1] @ v1-node-input.l4:14:1-53

Result:
  TRUE


Trace:
  (no trace captured; add #EVALTRACE to the directive)


Evaluation[2] @ v1-node-input.l4:15:1-48

Result:
  TRUE


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

**`out/v3-typically-means-run.txt`**

```text
Info | updateFileDiagnostics published different from new diagnostics - file diagnostics:
File:     v3-typically-means.l4
  Hidden:   no
  Range:    5:49-5:58
  Source:   parser
  Severity: DiagnosticSeverity_Error
  Code:     <none>
  Message:
      |
    5 | `unmarried` MEANS single OR divorced OR widowed TYPICALLY TRUE
      |                                                 ^^^^^^^^^
    unexpected TYPICALLY
    expecting %, &&, (, *, +, -, .., ..., /, ;, <, <=, =, =>, >, >=, ABOVE, AND, AT, BELOW, DIVIDED, EQUALS, FOLLOWED, Float Literal, GREATER, IMPLIES, LESS, MINUS, MODULO, Numeric Literal, OF, OR, PLUS, RAND, ROR, String Literal, TIMES, UNLESS, WHERE, end of input, identifier, infix identifier, mixfix keyword, space token, ||, or •
```
