# Props red team (2026-09-03): the reduced position

_Status: **a red-teamed design position, not a ruling and not implemented.** It records a
conversation held on 2026-09-02/03 between Meng and session `dynamic-scoping`
(`fd385a3f-be5b-4213-921c-9e8c0e47cee0`), and the reports of four adversarial subagents that
session ran against the design. Meng has further questions not yet put; nothing in §9 is decided
until `IMPLICIT-PROPS-DESIGN.md` says so. Every count below is as measured by the named team on
that day; re-verify before relying. The `l4` binary used for probes is `~/.local/bin/l4` dated
2026-08-27 and may lag `unstable`._

Supersedes, in part, `PROPS-SCOPE-HANDOFF.md`: its §2 "third reading" (the `§` hierarchy is the
scope tree) is refuted in §2 below. Its prior-art survey (§3) and boundaries (§7) stand.

---

## 0. How this came about

`PROPS-SCOPE-HANDOFF.md` asked for a scoping ruling. A first sketch (2026-09-02) answered it
with three constructs: `§`-scoped `ASSUME` as declaration, `ASSUMING` as both initial supply and
Reader `local`, an optional authored `TAKING` clause, a compiler-enforced no-shadowing rule
("earmuff"), and five lints. Meng's reaction, verbatim:

> "something about this still doesn't feel right. it feels like too many mechanisms overlapping.
> can we reduce the surfaces to be more principled and concise? this last example with ASSUMING
> feels like parametric modules from ocaml. perhaps an adversarial redteam on the design could
> offer more thoughts?"

Four subagents were run in parallel from one shared brief, each with a different adversarial
angle: PL theory, legal isomorphism, backends, and minimalism. Their reports are in Appendix A,
verbatim. Their probe files and observed outputs are in Appendix B.

Meng later added the history that explains the keyword: _"when we first wrote ASSUME we were very
early in the project and just wanted to satisfy the type checker. Everybody assumed we would
deprecate it in favour of more regular given-parameterized functions with purity."_

## 1. What the red team killed, and the witness for each

All four teams agreed on every item here.

1. **`ASSUMING` as Reader `local` (dynamic binding as machine state).** The one ambient field
   today, the rule date, is machine state (`Machine.hs` ~837-841, ~1100-1106); making it correct
   under laziness needed a two-pass deep force plus snapshot (~2991-3040) and a per-axis cache
   fingerprint (`TemporalContext.hs` ~140-224), and `ok/temporal-pin-deep.l4` cases I/J/K still
   answer the unpinned value through closures by design. N user fields multiply all three costs.
   Demand: all 19 legal-corpus uses of `EVAL UNDER RULES EFFECTIVE AT` (17 in `regcf.l4`
   fixtures, `regcf-wizard.l4:630`, one in denovo) sit at the outermost position of a directive
   or export body; zero inside a rule, quantifier or lambda. This is Yang 2020 exactly: dynamic
   scoping is an effect and does not survive call-by-need; implicit parameters are a coeffect and
   do.
2. **`§`-subtree scoping of `ASSUME`.** Statutes declare reach by words ("in this Part", "for
   the purposes of this section") and put interpretation sections as siblings, often last (BNA
   1981 s 50 of 53; CA 2006 Part 38). The corpus does the same: `british-citizen-act.l4:3-12`
   declares 7 in `§§ Assumptions` and consumes them in sibling sections (:81-155);
   `promissory-note.l4:226-228` declares in an end-of-file appendix, consumed at :15 and :302;
   `regcf.l4:143` → `:409`. Legal team: 9 of 39 unique declarations go dark; PL team: 7 files
   break. Every one of the 26 legal files opens with a `§` title, so "module-wide if before any
   `§`" would mean above the document title. And nearest-ancestor section shadowing **already
   ships** (`Types.hs:877-899`; `TypeCheck.hs:596-599`; `specs/done/SECTION-LEXICAL-SCOPING-SPEC.md`,
   smucclaw#50; fixtures `not-ok/tc/section-scoping-ambiguous.l4`), so the §4.2 wish for
   _visibility_ was already granted.
3. **The enforced earmuff.** It reverses a shipped ruling (FIX A,
   `ok/section-scoping-param-not-shadowed.l4`: a `GIVEN` parameter beats a same-named section
   binding; probe t3 confirms `GIVEN x` silently shadows `ASSUME x`), contradicts Coq, Lean and
   GHC, and guards a hazard (capture) that cannot occur once names resolve statically by
   `Unique`. Legal prior art: UK/SG statutes mark nothing and publish an index of defined
   expressions (CA 2006 Sch 8); Australia's ITAA 1997 asterisk convention exempts basic terms.
4. **Authored `TAKING`.** Inference is a displayed compiler fact, never written.
5. **The DMN "literal → specialise, computed → drop" rules.** Specialisation is ladder rung 2,
   which `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §15.12.1 (ruling R-C) stops at rung 0; and "computed
   → drop" would delete the Reg CF wizard's rebind, whose value is the export's own `GIVEN`
   `rule date` and is therefore trivially lowerable. Right criterion: a field lowers iff it is
   single-valued per evaluation.

## 2. What survived, and what it is called

The inference rule from the sketch is correct:

```
R(f)                 = reads(f) ∪ ⋃ { R(g) | g referenced in f }      -- least fixpoint over call-graph SCCs
R(LET x = v IN e)    = (R(e) \ {x}) ∪ R(v)                              -- context subtraction
```

Its name is **Coq `Section`/`Variable` discharge**: each definition is abstracted over exactly
the section variables it transitively uses, recursive groups discharged as a block. Not an OCaml
functor (uniform, generative, explicitly applied). What smelled functor-like in the sketch was
the dedicated supply keyword; prior art has none because supply is application. Also: Lewis,
Launchbury, Meijer, Shields, "Implicit Parameters: Dynamic Scoping with Static Types" (POPL 2000)
under its dictionary-passing translation; Petricek, Orchard, Mycroft, "Coeffects" (ICFP 2014),
flat coeffects; Agda parameterised modules; Isabelle `locale … fixes`; Lean 4 `variable`.

**The read-set must be one compiler fact.** As of this snapshot it exists twice, in
`Catala/Lower.hs:969-985` (fixpoint) and `Docassemble/Lower.hs:541-557`, and is missing where it
bites: the HTTP schema (`FunctionSchema.hs:276-300`), the direct evaluator (`Backend/Jl4.hs:558`)
and the WASM ABI (`jl4-mlir/.../Lower.hs:677`) all use `collectReferencedUniques`
(`Export.hs:354-358`), which is one body deep. **By code reading, not by run:** an `@export`
whose helper reads an `ASSUME` publishes a schema without that field and evaluation goes
`Stuck` (`Machine.hs:457`). The only test is a direct read (`jl4-service/test/TestData.hs:224-234`).
This is the first test to write, and fixing it is a bug fix with no language change.

Meng's history (§0) confirms the direction: "deprecate `ASSUME` in favour of
`GIVEN`-parameterised pure functions" is exactly what discharge does, with the compiler writing
the threading that authors were expected to write by hand. The minimalist team measured what the
hand-written version cost: **506 of 1,112 record-typed `GIVEN` slots in the legal corpus are pure
pass-through** (never `'s`-accessed in their own body; e.g. `probate-administration-act.l4`
87/183, `intestate-succession-act.l4` 82/122).

## 3. The one fork, and its resolution

Two teams (PL, backends) want per-field discharge into implicit parameters. The minimalist wants
the environment to be a `DECLARE`d record whose rules are computed fields, `WITH` to construct,
and `BUT WITH` (`RECORD-UPDATE-SPEC.md`, proposed) as `local`; zero new keywords. These are the
same design at two granularities: per-field is Coq, one-record is dictionary passing, and the
compiler can hold the per-field read-set while passing one record at runtime.

The surface question is what the author writes, and the evidence favours the implicit-parameter
form: only 4 computed fields exist in the whole legal corpus, so the record-as-Act form is
unmeasured at scale; the drilling is real (506/1,112); and `Docassemble/Lower.hs:941` refuses a
record-typed `ASSUME`, so every flat backend is per-field anyway.

The record team's durable contribution is different: the statutory rebinding device is
**deeming** ("treated as … for the purposes of subsection (1)", BNA s 1(2), `bna.l4:263-276`),
and it rebinds the **subject**, not the world. That is a record update on a `GIVEN`, which is why
`BUT WITH` is wanted independently (smucclaw#438) and should not be conscripted as the
environment's `local`.

## 4. The reduced design

Two sentences. **`ASSUME` is an implicit parameter, module-visible under the existing section
rule. Supply is application.** No new keyword. Everything else is a compiler fact or tooling.

Syntax verified on the 2026-08-27 binary (Appendix B): named application
`f WITH b IS 1, a IS 3` evaluates today; `LET x = 41 IN f` does **not** reach the callee today
(lookup is by `Unique`, `Machine.hs:3204-3212`); `TYPICALLY 41` on an `ASSUME` is discarded at
evaluation today. The design changes the second and third.

### 4.1 Drilling gone (real case, `regcf/denovo/regcf-denovo.l4:1364-1372` as of this snapshot)

Today the headroom rule takes `interp` and the offer date only to forward them:

```l4
GIVEN interp   IS AN Interpretation
      issuer   IS AN IssuerProfile
      offering IS AN OfferingProfile
      `the date of the offer or sale` IS A DATE
GIVETH A NUMBER
`the issuer's headroom under the twelve month cap` interp issuer offering `the date of the offer or sale` MEANS
          `the aggregate offering cap`
    MINUS `the amount already sold in the twelve month window` interp issuer `the date of the offer or sale`
```

Under the design, the two world values are declared once, anywhere in the module, and vanish
from every signature and call site on the chain; the callee that consults the interpretation
still writes `interp's `twelve month window anchor``, bare, as it does now:

```l4
§ `Interpretation`
ASSUME interp IS AN Interpretation TYPICALLY `the staff reading`
ASSUME `the date of the offer or sale` IS A DATE

GIVEN issuer   IS AN IssuerProfile
      offering IS AN OfferingProfile
GIVETH A NUMBER
`the issuer's headroom under the twelve month cap` issuer offering MEANS
          `the aggregate offering cap`
    MINUS `the amount already sold in the twelve month window` issuer
```

### 4.2 Supply is application (existing `WITH`)

```l4
#EVAL `the issuer's headroom under the twelve month cap` acme `acme's offering`
  WITH `the date of the offer or sale` IS Date 1 7 2026
```

`interp` takes its `TYPICALLY`. Omit the date too and the `#EVAL` fails at check time, naming the
field and the chain of calls that needs it. On an `@export` nothing fails: unsupplied fields
become request parameters, grouped by tier (`GIVEN` = subject, `ASSUME` = world). The wizard asks
the world once and the subject per instance; nothing provides that today (`BatchRequest`,
`jl4-service/src/Types.hs:376-405`, repeats the world in every case; OpenFisca's entity-vs-
`parameters(period)` split is the prior art).

### 4.3 Hypothetical evaluation (existing `LET`, made to reach callees)

```l4
#EVAL LET interp = `the strict reading`
      IN `100(a)(1) — the aggregate amount does not exceed the cap` acme `acme's offering`
```

Reads as "under the strict interpretation". Deeming a fact about the subject stays a record
update on the `GIVEN` (§3).

### 4.4 What the reader sees

No sigil. Hover shows the inferred clause the sketch wanted authored:

```
`the issuer's headroom under the twelve month cap`
  GIVEN   issuer, offering
  reads   interp                           via `the amount already sold …`
          `the date of the offer or sale`  via `the amount already sold …`
  pure    no
```

The read-sets also print as an index of defined expressions at the end of a rendered document.
A rule with an empty read-set gets the pure badge with no annotation. `imaginary-alcohol-act.l4`
migrates with zero changes to rule text and gains its first `#EVAL`.

## 5. Compiler plan (proposed order)

1. **Read-set pass** (`R(f)` over `Unique`s, transitive over SCCs, closed at lambdas), one
   module, replacing the Catala and Docassemble private copies and the shallow collector. Write
   the helper-reads-an-`ASSUME` export test first; it is expected to fail today.
2. **Preconditions.** Own keyword for uninterpreted types (`ASSUME T IS A TYPE`, 101 uses, 6 in
   legal): a type-dependent `ASSUME` makes discharge an ordered telescope, not a set
   (`anti-social.l4:11-18`, `british-citizen-act.l4:5-12`; polymorphic `prelude.l4:757-761`
   `TBD`). Non-suppliable refusal form (`REFUSE` or a marker) for `regcf.l4:143,486`,
   `daydate.l4:104`, prelude `TBD`: discharge plus `IMPORT` would otherwise make them request
   parameters (`assumesFromModule` is current-module-only today, `Export.hs:293-307`; the service
   already promotes referenced `ASSUME`s, `Backend/Jl4.hs:556-560`).
3. **Elaboration = discharge.** Every definition with non-empty `R(f)` gains those fields as
   leading implicit parameters; every reference passes them through; `LET`/`WITH` binding a
   field at a site whose read-set contains it becomes application. After elaboration the program
   is plain L4 with `GIVEN`s: no environment, no pin, no fingerprint axis; the assumed-term path
   shrinks to "unsupplied at root".
4. **Runtime shape** is a compiler choice: per-field (Coq-exact) or one per-module record
   (preserves sharing of 0-ary dated constants, e.g. the 10 readers of `the rules in force
include` in `regcf.l4`; cost unmeasured). Backends project per-field from `R(f)` either way.
5. **`TYPICALLY` as the default of an implicit parameter** (Lean `optParam`); today the schema
   exposes it and the evaluator discards it (`Machine.hs:3514-3520`).
6. **Consumers:** hover/CodeLens; `@export` schema with tiers; DMN (`ASSUME` → `inputData`,
   `R(f)` → information requirements, `GIVEN` functions → BKM; a `LET` at a non-root site is the
   exporter's existing tier-2 case, no new drop class); trace needs nothing new (a supplied field
   is an ordinary bound argument).
7. **Temporal**, last: `RULES EFFECTIVE DATE` as a prelude-declared field, `EVAL UNDER RULES
EFFECTIVE AT d e` as `LET`, once sharing is measured. The per-day interval iterators rebind
   per iteration by construction (`Machine.hs:1253-1302`) and need a rank-2 implicit; not
   designed.

## 6. Scorecard against `IMPLICIT-PROPS-DESIGN.md`

| wish                                 | reduced design                                                                       |
| ------------------------------------ | ------------------------------------------------------------------------------------ |
| §4.1 every function gets typed props | every `ASSUME` is an implicit parameter of every function that transitively reads it |
| §4.2 `§`-scoped establishment        | dropped: visibility already ships; reach is stated by placement, anywhere            |
| §4.3 purity discovered               | `R(f) = ∅` ⇒ untouched by discharge ⇒ badge for free                                 |
| §4.4 `local`                         | `LET` reaching callees for the world; `BUT WITH` for subject deeming                 |
| §4.5 provenance                      | supplied field is an ordinary traced argument; declaration and supply sites static   |
| §5.1 structural subtyping            | unnecessary: declared field types; requirement = set inclusion                       |
| §5.2 inference                       | `R(f)`, one pass, transitive                                                         |
| §6 `TAKING`                          | hover and schema only, never authored                                                |
| §10.5 DMN isomorphism                | `ASSUME` → `inputData`, `R(f)` → info requirements, `GIVEN` fns → BKM                |

## 7. Defects found incidentally (pre-existing, stand regardless)

- A parent section's own reference goes ambiguous ("multiple definitions") whenever any
  descendant section rebinds the name (PL probes v3/v4), contradicting the documented
  nearest-ancestor rule.
- `TYPICALLY` on `ASSUME`: advertised in the schema, discarded by the evaluator (probe t4).
- `collectReferencedUniques` is one body deep (§2); helper-read `ASSUME`s are unsuppliable and
  unlisted via the service. Code reading; unrun.
- `LocalAssume` is in the grammar (`Syntax.hs:454`, `Parser.hs:502`), 0 legal-corpus uses,
  refused by Docassemble.
- Function-typed `ASSUME` (`anti-social.l4:12-28`) is refused by every backend; it is a
  `DECLARE` record in disguise (design §10.6 b).

## 8. Open questions

Meng has stated he has further questions; none recorded yet. Known unresolved on our side:
whether the keyword `ASSUME` survives for the term role or is renamed (cosmetic; corpus
migration is zero either way); the runtime shape (§5 item 4) and its sharing cost; whether
`LET`-reaching-callees should be promoted in docs before there is in-body demand; whether
`ASSUME` visibility crosses `IMPORT` (not verified by any team).

## 9. Proposed rulings (NOT yet ruled; record in `IMPLICIT-PROPS-DESIGN.md` when decided)

1. `ASSUME` (term role) is an implicit parameter with compiler discharge; supply is application.
2. No `ASSUMING`, no authored `TAKING`, no earmuff rule, no `§`-scoping beyond what ships.
3. `BUT WITH` is subject deeming, not environment rebinding.
4. Preconditions land first: own keyword for uninterpreted types; non-suppliable refusal form.
5. The read-set is one compiler fact consumed by every backend.

---

## Appendix A. The four red-team reports, verbatim

Each was written from a read-only survey of this worktree; none built or edited it. Their
"not verified" sections are kept.

### A.1 Legal isomorphism (`redteam-legal`)

Red team (legal isomorphism) verdict: "the § tree is the scope tree of the law" is false for every corpus file and for statutes generally. Drafting has two scoping devices, and L4 already has both. Read-only; nothing built or run.

FINDINGS, most damaging first

1. Statutory reach is declared by words, not position. "In this Act", "in this Part", "for the purposes of this section" state reach explicitly and position-independently. Interpretation sections are siblings of operative sections, often at the end: BNA 1981 s 50 (of 53), Companies Act 2006 Part 38, Reg CF §227.100(d) inside the Part's first section. The corpus already does this: british-citizen-act.l4:3-12 declares 7 ASSUMEs under `§§ Assumptions` and consumes them in sibling sections (:104-155); promissory-note.l4:226,228 declares in an end-of-file `§ Promissory Appendix` and consumes at :15 and :302; bna.l4:71 `§§ Interpretation` is a sibling of `§§ Subsection (1)` (:178). Under "binds that § subtree", 9 of 39 unique corpus declarations (23%) go dark. "Module-wide if before any §" is worse: all 26 legal files open with a § title, so module-wide means above the document title.

2. Headers track the statute half the time, never wholly. Of 511 headers: 271 statute-numbered (53%), 99 encoder-organisational (Types/Tests/Fixtures/Helpers), 141 descriptive. Six older files score 0 (ceo, bca, directive, promissory, alcohol, anti-social). The cleanroom scores 48/72 (ISA), 41/64 (GIA), 32/44 (PAA), but interleaves `Fixtures`, `The ontology`, `The person` as siblings of `Subsection (3)`. A scope tree read off § mixes statute and encoder taste in every file.

3. The statutory `local` rebinds the SUBJECT, not the world. Drafting's one rebinding device is deeming/modification: "deemed for the purposes of subsection (1)" (BNA s 1(2), bna.l4:263-276), "applies as if". It rebinds fields of the GIVEN record, which ASSUMING cannot reach (no record update). World-level rebinding has exactly 19 corpus uses (`EVAL UNDER RULES EFFECTIVE AT`: regcf.l4 x17, regcf-wizard.l4:630, denovo x1), every one at the outermost position of a #EVAL or @export body; zero inside a rule, quantifier or lambda. The ASSUMING expression form, its two lints, and DMN's specialise/drop split serve a case with no instances.

4. ASSUMING collides with ASSUME on epistemic status and mis-describes the worked example. ASSUME means "unknown, uninterpreted"; regcf.l4:143 is a curated refusal that must never be supplied (ruling R2). ASSUMING means "take as known". Making every ASSUME suppliable lets a caller bind the refusal and get a confident wrong answer below commencement. jl4-service already does this: Backend/Jl4.hs:556-560 promotes referenced ASSUMEs to request parameters, and regcf-denovo.l4:3035-3036 records the refusal being asked of every caller. In legal English "assuming" is advocacy's hypothetical (arguendo). The wizard's use (regcf-wizard.l4:626-632) is not hypothetical: it is the law actually in force on the investment date. A drafter writes "under the rules in force on [date]".

5. World/subject flips at seams, not by nature. Rule date: ambient at regcf.l4:133,:491, a GIVEN at regcf-wizard.l4:626. The issuer: subject of Rule 100(b) (regcf.l4:280-332) and a boolean field of three other subjects (Offering :342, IntermediaryArrangement :564, ReportingStatus :652). `survived the deceased` bakes the world fact `date of death` (sg-succession-domain.l4:78) into each subject Person (:53-58). `the relevant day` is scoped by s 1(9) to two subsections but bound module-wide (bna.l4:88-96). The corpus never makes a world constant an ASSUME; world constants are dated MEANS. What actually gets drilled is interpretive choice: `interp IS AN Interpretation` (regcf-denovo.l4:142-160) is threaded through 26 functions and read by 7, so 19 are pure pass-throughs. That is the props use case, and the "called twice per evaluation?" rule of thumb classifies it correctly.

6. Context-displacement and cross-Act borrowing are beyond any static scope. GIA s 3 "any court" displaces s 2 inside its own reach (guardianship-of-infants-act.l4:456-470; encoder widened the type). "court" is Act-wide in PAA/GIA and section-only in WA s 28(7), deliberately unified into one shared type (family-domain.l4:168-215). PAA restates ISA's "child" rather than importing (probate-administration-act.l4:400-410). Interpretation Acts: zero corpus references.

7. Sigil. GIVEN names are 716 bare vs 341 backticked, and ambient names are backticked phrases, so a de facto distinction exists but is unreliable. Prior art splits: contracts capitalise Defined Terms; UK/SG statutes mark nothing and publish an index of defined expressions (CA 2006 Sch 8); Australia's ITAA 1997 ss 2-10/2-15 asterisks defined terms and then exempts basic terms. A sigil earns its keep only at dictionary scale and prunes itself. So: no source sigil; the read-set is a generated index (hover/printer), never authored or checked.

SMALLEST DESIGN A DRAFTER RECOGNISES

(a) Declaration with stated reach = ASSUME, module-wide, position-independent. The module is the Act or Part; "has the same meaning as in the X Act" is IMPORT (the cleanroom already splits Acts plus a shared domain module). Drop § scoping: 0/39 declarations want it, 9/39 break under it. Narrower reach is not an environment: "for the purposes of this section" definitions are functions of the subject (sg-paa.l4:308 puts the section number in the name; sg-wills.l4:626 makes it a data-entry field). Split the refusal role into non-suppliable REFUSE (design §10.6d) so suppliability is total over what remains.

(b) Supply only at the boundary: #EVAL/#ASSERT arguments, the @export request schema (extractAssumeParamResolveds already does this), and IMPORT. `EVAL UNDER RULES EFFECTIVE AT` becomes a directive form; the wizard surfaces `RULES EFFECTIVE DATE` as a request parameter via the generated read-set. No ASSUMING expression means no lambda/quantifier lint, no dead-rebind lint, no DMN drop class: every ASSUME is inputData, every supply an input. Keep the sketch's R(f) inference, displayed not written.

(c) If an in-expression rebind is ever needed, spell it as the deeming device, `e TREATING x AS v` (UK OPC prefers "is to be treated as" over "deemed"), and let it reach subject fields, since that is the statutory case. Do not build it now: zero demand inside rule bodies.

Prior art: Interpretation Act 1978 s 5, Sch 1, s 11; SG Interpretation Act 1965 s 2(1); 1 U.S.C. §1; BNA 1981 s 50(1); ITAA 1997 ss 2-10, 2-15, 995-1; CA 2006 Sch 8; Thornton, Legislative Drafting (definitions chapter); Dickerson, Fundamentals of Legal Drafting; UK OPC Drafting Guidance.

NOT VERIFIED: whether ASSUME visibility crosses IMPORT; Export.hs:488 extractImplicitAssumeParams keys on OutOfScopeError, so which of two promotion paths the service takes for regcf's refusal; the 15-dropped-decisions figure comes from the handoff, not re-measured.

### A.2 Backends (`redteam-backends`)

Backends red-team report on the props/ASSUME sketch (brief §B). Read-only survey; nothing built or run.

RANKED FINDINGS

1. `ASSUMING` as runtime `local` is smucclaw#934's deep-pin trap, generalised. The one ambient field today is machine state, not a binding: `EVAL UNDER RULES EFFECTIVE AT` pushes a frame and calls `putTemporalContext` (jl4-core/src/L4/EvaluateLazy/Machine.hs:837-840, 1100-1106). Under laziness that answered wrongly until the two-pass deep force + snapshot landed (Machine.hs:2991-3040); closures stay opaque ("a pin cannot follow a value into a scope it does not dominate"); and cache validity needs one `CtxReads` axis per field (jl4-core/src/L4/TemporalContext.hs:140-224). N user fields = N fingerprint axes, each deep-pinned. The lexical alternative, LetIn shadowing the ASSUME's own Unique, which jl4-service already does (jl4-service/src/Backend/Jl4.hs:639-665), is closure-correct for free but reaches only the inlined body: every top-level decide closes over the module env where the field is `ValAssumed` (Machine.hs:3531-3536, 3516-3520). So Reader `local` in this evaluator is either dynamic-and-deep-pinned or lexical-and-shallow. Only compile-time discharge (callees take the field as a parameter) is both correct and cheap.

2. R(f) already exists twice and is missing where it bites; a live bug. Catala (jl4-core/src/L4/Catala/Lower.hs:969-985, fixpoint) and Docassemble (jl4-core/src/L4/Docassemble/Lower.hs:541-557) compute the transitive requirement. The HTTP schema (jl4-core/src/L4/FunctionSchema.hs:276-300), the direct evaluator (Backend/Jl4.hs:558) and the WASM ABI (jl4-mlir/src/L4/MLIR/Lower.hs:677) all use `collectReferencedUniques` (jl4-core/src/L4/Export.hs:354-358), which is one body deep. By code reading: an `@export` whose helper reads an ASSUME publishes a schema without that field and evaluation goes `Stuck` (Machine.hs:457). The only test is a direct read (jl4-service/test/TestData.hs:224-234). Whatever lands, R(f) must be one compiler fact, not five backend re-derivations.

3. The sketch's DMN rules contradict ruling R-C and misclassify the one production `local`. "Literal → specialise subgraph" is rung 2 of the ladder that specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md §15.12.1 (lines 5766-5830) ruled to stop at rung 0 ("the model owns the law under a date; the harness owns the dates"), rejected on legibility (doubles the requirement cone) and sufficiency (finite regimes; 20 harness cases, 1340/1340 on both engines). "Computed → drop" would drop `investment limit under the rules effective on` in jl4/examples/legal/regcf/regcf-wizard.l4, the only `EVAL UNDER` outside fixtures, whose value is the export's own GIVEN `rule date`: the trivially lowerable case, because that GIVEN _is_ the inputData. Right criterion: a field lowers iff it is single-valued per evaluation. Rebinding at an export root is boundary discharge (free); rebinding anywhere else is a second value, unlowerable whatever v is. Missing from the sketch's unlowerable list: rebinding inside a recursive function, inside a hydrated computed field (§4.4), and the per-day interval iterators (Machine.hs:1253-1302), which rebind per iteration by construction. Counts: 19 uses in the legal corpus, 17 of them regcf.l4 fixtures; 15 decisions dropped (16 `D-RULEDATE-UNBOUND` lines in jl4/examples/dmn/expected/regcf-corpus.fidelity.txt).

4. §-scoped fields recreate the N-inputData-per-name defect Phase 4 un-lifted. FEEL has one flat variable scope (jl4-core/src/L4/Dmn/Lower.hs:4740-4760, `uniquifyIn`), a same-name type conflict is Blocking (spec §2.5.3), and a § is a `decisionService` over global inputData (§2.3). Two sibling §§ each declaring `jurisdiction` at different types is legal in the sketch and unlowerable. Let § govern visibility of a module-global name; never mint a second identity.

5. Nothing provides "world once, subject per instance". `BatchRequest` is `{outcomes, cases:[{id, attributes}]}` (jl4-service/src/Types.hs:376-405): every case repeats the world. OpenFisca is the prior art and is natively two-tier: entity inputs vs `parameters(period)` (jl4-core/src/L4/OpenFisca/Lower.hs:251-252, 272), and its world tier is keyed by date, so the rule-date axis _is_ a world field. Reader and discharge yield the same flattened schema; grouping by § names the tier (`x-l4-type`, FunctionSchema.hs:44).

6. Provenance. The trace records reads as Enter/Exit of a term (jl4-core/src/L4/EvaluateLazy/Trace.hs:87-94); ambient observations go to the cache fingerprint (Machine.hs:654-687), not the trace, and the binder is invisible. Under discharge the binding is an ordinary parameter/LetIn allocation already traced, and "established at §3.2" is the declaration site. Reader adds nothing without a new trace event.

7. Two dead surfaces to retire, not extend. `LocalAssume` is in the grammar (jl4-core/src/L4/Syntax.hs:454, Parser.hs:502), 0 legal-corpus uses, refused by Docassemble (Lower.hs:1508). `ASSUME f IS A FUNCTION …` (jl4/examples/legal/anti-social.l4:12-28) is refused by every backend (Export.hs `validateExportInputs`; Machine.hs:3517-3520 TODO) and is a DECLARE record in disguise (props §10.6b). Reusing `ASSUME` as the field spelling keeps both ambiguities alive.

MINIMAL DESIGN, FROM THE BACKENDS' SIDE: section parameters, discharged.

One mechanism. `ASSUME x IS A T` (keep the spelling, or `CONTEXT`) declares that its enclosing § (the module, if before any §) is parameterised by x. The compiler computes R(f) transitively over call-graph SCCs and rewrites every f with R(f) ≠ ∅ to take those fields as leading implicit parameters, passed unchanged at every call. This is Coq `Section`/`Variable` with discharge at `End` (only the variables actually used, transitively), Agda parameterised modules, Isabelle `locale … fixes`; formally the dictionary-passing translation of implicit parameters (Lewis, Launchbury, Meijer, Shields 2000), i.e. flat coeffects made explicit.

- No new supply form. Supply is application. The export boundary gets R(f) as schema properties (what FunctionSchema does today, made transitive). Hypothetical evaluation is Agda's named implicit argument: `f ASSUMING x IS v` supplies x at that application; lexical, closure-correct, no machine state, no deep pin, no per-field fingerprint. `EVAL UNDER RULES EFFECTIVE AT d e` becomes `e ASSUMING RULES EFFECTIVE DATE IS d`, the date being a prelude-declared field. Meng's "OCaml functor" smell is accurate and is the honest name: Coq sections are functor application with the arguments discharged. Three overlapping mechanisms become one, named.
- DMN needs no new concept. Discharged arguments are "the same argument at every call site", tier 1 (spec §2.1), un-lifted to inputData by the existing analysis; `ASSUMING` at a non-root site is tier 2 (a real λ → BKM, or R-C's drop+harness). The sketch's three DMN rules and the "would I call this twice?" rule of thumb collapse into the exporter's existing tier census (96% tier 1, §2.2); the lint _is_ `D-BKM`. Un-lambda-lifting and discharge are inverses, and §2 already says so.
- Every other backend gets its native view. Catala: scope `input`s, with `TYPICALLY` → `context` (R10, Catala/Lower.hs:1136-1153). Docassemble: one question per field. OpenFisca: fields → `parameters`/entity inputs. jl4-service and MLIR: what they do today, made correct. Discharge per field (Coq-exact), not one record per §: every flat backend is per-field, and Docassemble refuses record-typed ASSUME (Lower.hs:941). Group by § only in the schema, for the two-tier API.
- Lints reduce to two: unresolved name → "declare a field in the nearest §"; a GIVEN/WHERE binder shadowing a visible field → error. No dead-ASSUMING lint, no quantifier lint: those are backend fidelity notes.

NOT VERIFIED. Finding 2 is code reading, not a run. Discharging `RULES EFFECTIVE DATE` turns 0-ary dated constants (10 readers of `the rules in force include` in regcf.l4) into 1-ary functions and loses sharing unless memoised per date; unmeasured. Word-greps for any/all (1347/644) include prose; the brief's ~150 is the careful figure. Blawx/s(CASP) with a twice-valued field not examined.

### A.3 PL theory (`redteam-pl`)

Red team (PL theory) verdict: the sketch's inference rule R(f) is right (it is Coq section discharge), but its evaluation model (Reader `local` as machine state) and its §-subtree visibility are both wrong, and two of its three surfaces are redundant with syntax L4 already has.

Probes ran on a prebuilt `l4` (l4wt/blawx-integrated @2e8317d1; v1–v4 cross-checked on the Aug-7 reference binary), no build in this worktree. Files: scratchpad/{t1-let,t3-shadow,t4-typically,t7-named,v1..v4}.l4, xsec.py.

#### Ranked findings

**F1. `ASSUMING` as Reader `local` is dynamic binding as machine state, and L4 already shows it fails under laziness.** The one instance today, `EVAL UNDER RULES EFFECTIVE AT`, mutates `TemporalContext` for a frame's extent (Machine.hs:837-841, 363). Thunks escape the extent, so #934 added deep-force + snapshot (Machine.hs ~2985-3040), which changes strictness and still leaks through closures, record fields and obligations: `ok/temporal-pin-deep.l4` cases I/J/K answer 9/900 for a pinned computation, by design. T6 then fingerprints every cached thunk on the axes it read. N fields multiply all three costs. This is Yang 2020 exactly: dynamic scoping is an effect and does not survive call-by-need; implicit parameters are a coeffect and do. Under static discharge the rebound `e` is an application; the escaped closure carries the value; I/J/K give 7/700 with no forcing, snapshot or fingerprints.

**F2. §-subtree visibility breaks the definitions-section idiom (HANDOFF §5's own domain argument) and is unnecessary.** Measured (xsec.py): 151 files have ≥2 § headers, 16 contain ASSUME, 7 use one outside its declaring subtree. Legal: `british-citizen-act.l4` declares 7 in `§§ Assumptions` (l.3-12), used in four sibling §§ (l.81-155); `promissory-note.l4` 2 (l.226-228 → l.15, 302); `regcf.l4:143` → `:409`, a different top-level §; plus `experiments/britishcitizen.l4`, `dogs.l4`, and two scoping fixtures whose diagnostics change. ASSUME would become the only top-level form with subtree visibility (DECIDE stays module-wide: v2 → 1). What §4.2 wants already exists: nearest-ancestor shadowing (Types.hs:877-899, commits 29ace1c8/a6ac3e7a): v1 child rebinds x, child ref → 2; v2 sibling ref, ancestor def → 1. Live defect: a parent's own reference is ambiguous whenever any descendant rebinds the name (v3, v4: "multiple definitions" at 3:9), contradicting the documented rule. Fix regardless.

**F3. Supply must be elaboration, not env rebinding.** Lookup is by Unique only (Machine.hs:3204-3212): with `f MEANS x PLUS 1`, `LET x = 41 IN f` is stuck on assumed x (t1) while `LET x = 41 IN x PLUS 1` is 42. The service works only by inlining the exported body into a `LetIn` reusing the ASSUME's own Resolved (Jl4.hs:640-665), and the schema collects direct body refs only (Export.hs:354-358): an @export whose helper reads an ASSUME is unsuppliable and unlisted today. R(f) fixes that, but only via dictionary-passing, at which point "initial supply" and `local` are one construct: application.

**F4. "Sets not rows" is unsound for two ASSUME populations.** Type-dependent: `anti-social.l4:11-18` (`Person IS A TYPE`, `is authorised IS A FUNCTION FROM Person TO BOOLEAN`), `british-citizen-act.l4:5-12`: discharge is an ordered dependent telescope (Coq), not a set. Polymorphic: `prelude.l4:757-761` `ASSUME TBD` under `GIVEN a IS A TYPE` has no monomorphic type to supply (cf. Export.hs:464). Sets are sound only after §10.4 item 3 lands; it is a precondition.

**F5. IMPORT turns refusal bottoms into inputs.** `daydate.l4:104` is a refusal ASSUME; discharge makes it a parameter of every importer calling YMD, and a DMN inputData. It is hidden today only because `assumesFromModule` is current-module-only (Export.hs:293-307). `REFUSE` must land first (also regcf.l4:143).

**F6. Three surfaces where prior art has one, plus a rule prior art rejects.** Coq: `Variable` + application. GHC: `?x` + `let ?x`. Scala: `using` + `given`. Sketch: ASSUME + ASSUMING + TAKING + earmuff. The earmuff rule contradicts Coq, Lean, GHC and current L4 (t3: `GIVEN x` silently shadows `ASSUME x`, `g 1` = 2; `ok/section-scoping-param-not-shadowed.l4`). Capture is a dynamic-scoping hazard; with Unique-resolved static discharge it cannot occur.

**F7. The OCaml diagnosis is half right.** Not a functor (uniform, module-level, generative, explicit). R(f) with least fixpoint is Coq section discharge: each constant abstracted over exactly the variables it transitively uses; SCCs discharged as a block. That granularity is correct. What smells functor-like is a dedicated supply keyword. Coq's supply is application, which L4 has: `f WITH b IS 1, a IS 3` = 2 (t7).

**F8. TYPICALLY is half-built.** Schema exposes defaults (FunctionSchema.hs:276-292); the evaluator discards them (Machine.hs:3514-3520; t4 stuck). Under implicit parameters it is Lean's `optParam`.

**F9 (§D).** "Parameters cannot be dropped" is right and sharper: props are parameters, distinguished only by being named and inferred. "Called twice per evaluation" = "bound under a lambda in a quantifier body", the same criterion the DMN lint needs. Visual distinctness needs no syntax: Unique-resolved reads, coloured.

#### Minimal design: ASSUME is an implicit parameter

1. Declare: `ASSUME n IS T`, unchanged, module-visible under the existing proximity rule. Zero corpus migration.
2. Infer: R(f) over Uniques, transitive, closed at lambdas (definition-site discharge). Flat coeffects, Petricek–Orchard–Mycroft ICFP 2014; the LET rule is their context subtraction. Shown on hover and by `l4 check`; drop TAKING.
3. Supply with existing syntax only: `LET x = v IN e` / `WHERE` (Lewis–Launchbury–Meijer–Shields POPL 2000, `let ?x`) and `f WITH x IS v`. Drop ASSUMING. `EVAL UNDER RULES EFFECTIVE AT d e` becomes `LET \`RULES EFFECTIVE DATE\` = d IN e` once that builtin is a prelude ASSUME. Rule: local bindings never generalise over requirements, which removes the GHC monomorphism pathology.
4. Boundary: unsupplied R(entry) = inputs (#EVAL error, @export schema, DMN inputData); TYPICALLY = default.
5. Semantics: elaborate to explicit parameters and run the ordinary lazy machine. Sharing recovered by memoising on implicit arguments (T6 generalised).
6. Preconditions: own keyword for TYPE-ASSUME; REFUSE for daydate, regcf, TBD.
7. DMN: discharged decisions → BKM parameters; supply → invocation bindings; literal LET → invocation with a literal.

#### Not verified

- Interval builtins rebind per stepped day (Machine.hs:2960-2985); under discharge they need a rank-2 implicit (`((?d) => BOOL) -> …`), one elaborator special form. Not designed.
- Item 7 against the exporter.
- The cause of v3; only measured.
- Service behaviour for helper-read ASSUMEs: read from code, not run.

### A.4 Minimalist (`redteam-minimal`)

Minimalist red-team verdict: the sketch in brief §B adds a second Reader beside one L4 already has; the goal in §A is met today by DECLARE + computed fields, verified on the installed l4 binary, with zero new keywords and one already-specced addition (BUT WITH).

RANKED FINDINGS (most damaging first)

F1. ASSUMING duplicates an existing mechanism. jl4-core/src/L4/TemporalContext.hs:33-57 is already an 8-axis implicit environment (5 axes latent, no reader), with `EVAL UNDER …` as its `local` (Machine.hs:2975-2981 applyEvalClauses + pushFrame) and T6 read-fingerprinting for memo correctness (Machine.hs:671-675). Generalising it to user axes inherits the DMN problem wholesale: Analysis.hs:775-790 drops every rule-date rebind (DroppedRuleDateRebind) because a DRG has no scoped rebinding. A record-VALUED environment sidesteps it: `f (env BUT WITH x IS v)` is a BKM invocation (FEEL 1.3 `context put`), lowerable where ASSUMING is not.

F2. "§-scoped ASSUME" already exists. jl4/examples/not-ok/tc/section-scoping-ambiguous.l4 declares `ASSUME x` in §§ b and §§ c and resolves them lexically; TypeCheck.hs:596-599 pushes the section stack for exactly this (specs/done/SECTION-LEXICAL-SCOPING-SPEC.md, DONE, smucclaw#50). The DECLARE half of §B is a no-op.

F3. The "enforced earmuff" lint reverses a shipped ruling. FIX A (jl4/examples/ok/section-scoping-param-not-shadowed.l4): a GIVEN parameter takes absolute priority over a same-named enclosing section binding. §B would make `GIVEN foo` an error when `ASSUME foo` is visible. The shipped rule is Python's; keep it.

F4. Drilling is real, but the fix is already in the language. Measured over the 25 legal-corpus files: 1,112 record-typed GIVEN slots, of which 506 (45%) are pure pass-through (never `'s`-accessed in their own body; e.g. probate-administration-act.l4 87/183, intestate-succession-act.l4 82/122). Computed fields remove pass-through by construction: sibling fields and sibling computed fields are in scope bare (COMPUTED-FIELDS-SPEC line 80; chained deps in jl4/examples/ok/computed-fields.l4 §2). Scratch witness, run with ~/.local/bin/l4 (scratchpad/env-as-record.l4): `DECLARE Estate HAS \`adult age\`, jurisdiction, beneficiaries, \`is adult\` IS A FUNCTION FROM Beneficiary TO BOOLEAN MEANS GIVEN b YIELD b's age AT LEAST \`adult age\`, \`all adults\` MEANS all \`is adult\` beneficiaries, distributable MEANS \`all adults\` AND jurisdiction EQUALS "SG"`→ TRUE, TRUE,`map (e's \`is adult\`) [c aged 3]`→ LIST FALSE, and a second`Estate WITH \`adult age\` IS 26 …`→ FALSE. That last line is`local`; the function-typed field is a parameterised rule reading the environment bare and applied per element, which answers §D's "call twice with different X" objection without a second tier.

F5. Inference is tooling, not language (H6 accepted). Desugar.hs:450 `exprFieldRefs` already computes which sibling fields a computed field reads; TAKING is its transitive closure over chained fields, displayed in hover. COMPUTED-FIELDS-SPEC line 511 already anticipates "derivable from stored fields, need not be supplied as input".

F6. Production `local` is already a parameter (H3 accepted). jl4-service takes only `arguments` (Backend/Api.hs:121-132; no evalClause channel); regcf-wizard.l4:627-631 takes `rule date` as a GIVEN and pins inside. 17 of the 18 legal-corpus `EVAL UNDER` sites are test fixtures (regcf.l4:1338-1433). Generalising `local` serves fixtures, not exports.

F7. ASSUME (H4, refined: shrink, don't delete). 39 unique legal declarations: (a) 14 alcohol-act booleans → one DECLARE with computed-field DECIDEs, the flagship; (b) 21 anti-social/BNA function-typed → records (already ruled §10.6); (c) 2 sentinels → constants; (d) refusals: regcf.l4:143,486, daydate.l4:104, and prelude.l4:758-761 `GIVEN a IS A TYPE GIVETH AN a ASSUME TBD`, a polymorphic bottom that shows refusal is already a library idiom. Experiments: 418 lines, 13 files, 284 function-typed, 88 types, where "uninterpreted symbol" is the right construct. Ruling: ASSUME keeps two jobs, uninterpreted sort and typed bottom; it stops being a supply channel. No REFUSE keyword needed unless a message string is wanted.

F8. §-scoped environments are unneeded (H5 accepted). 23 of 25 legal files are multi-§, but sections are document structure; the corpus threads records (1,112 record vs 526 scalar params) and the only ambient reads are the builtin law-time axis at 3 sites (regcf.l4:133, 491-492; regcf-denovo.l4:220). Nesting = nested records (computed-fields.l4 §4 Policy→Driver: `driver's adult`).

H2 refined: WHERE is the intra-definition closure (125 blocks, 2 nested; sg-paa.l4:327-341 read the GIVEN `a`), never inter-rule, so it does not touch drilling. H1 refined: `open`-record alone still forwards through intermediates; computed fields are `open` plus no forwarding.

MINIMAL PROPOSAL: "the environment is a record; a rule is a field of it."

- Declare/consume/supply: DECLARE World HAS <inputs> + computed fields for rules; construct with WITH; call `w's rule`. 0 keywords.
- local: `w BUT WITH x IS v` (RECORD-UPDATE-SPEC, PROPOSED, independently motivated by smucclaw#438). The one addition.
- Temporal: leave `EVAL UNDER RULES EFFECTIVE AT` as the closed builtin Reader; do not open a user tier.
- Lints: none of the five; total construction already catches a missing input.
- DMN: stored fields → inputData, computed fields → decisions (exporter already models them, Lower.hs:164-247 hydrators), function-typed fields → BKMs, BUT WITH → BKM invocation or drop+report.
- Prior art: Catala scopes (record-to-record function, caller-overridable `context` vars; CATALA-EXPORT-SPEC lines 138-142), the closest legal DSL; Smalltalk/Java implicit `this` for methods; Pascal `with` / Haskell RecordWildCards for bare access; ReaderT `local (\r -> r{x=v})` for update-as-local. In React terms the record IS the props and the computed fields are the component, matching §1's own vocabulary.

NOT VERIFIED: DMN lowering of function-typed computed fields; trace output form for computed-field evaluation; scale (only 4 computed fields exist in the legal corpus, so a regcf-size rewrite is unmeasured); transitive exprFieldRefs is not built; the l4 binary used is dated 2026-08-27 and may lag unstable. No cabal, no edits to the worktree.

## Appendix B. Probes and observed outputs

Run by session `dynamic-scoping` on 2026-09-03 with `~/.local/bin/l4 run` (binary dated
2026-08-27). Kept as snippets, not as `.l4` files, so they cannot fall into a golden glob.

```l4
-- t7-named: named application already exists
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
f a b MEANS a MINUS b
#EVAL f WITH b IS 1, a IS 3          -- observed: 2
```

```l4
-- t1-let: LET does not reach the callee today (lookup by Unique)
ASSUME x IS A NUMBER
f MEANS x PLUS 1
#EVAL LET x = 41 IN f                -- observed: "needed to know the value of x but it is an assumed term"
#EVAL LET x = 41 IN x PLUS 1         -- observed (PL team): 42
```

```l4
-- t3-shadow: GIVEN silently shadows ASSUME (FIX A)
ASSUME x IS A NUMBER
GIVEN x IS A NUMBER
GIVETH A NUMBER
g x MEANS x PLUS 1
h MEANS x PLUS 1
#EVAL g 1                            -- observed: 2
#EVAL h                              -- observed: assumed-term error
```

```l4
-- t4-typically: the evaluator discards the default
ASSUME x IS A NUMBER TYPICALLY 41
f MEANS x PLUS 1
#EVAL f                              -- observed: assumed-term error
```

```l4
-- t8-with-assume: WITH cannot supply an ASSUME today (f takes no parameters)
ASSUME x IS A NUMBER
f MEANS x PLUS 1
#EVAL f WITH x IS 41                 -- observed: check error at 3:7-3:21
```

The minimalist team's `env-as-record.l4` (a `DECLARE Estate` with three computed fields, one
function-typed) reported TRUE, TRUE, `LIST FALSE`, FALSE for its four `#EVAL`s; not re-run here.

---

## 10. Refinements after the checkpoint (minuted 2026-09-03/04; not ruled)

Everything in this section post-dates commit `c51e9e8f` and was worked out in conversation with
Meng. Each item is a **candidate**, recorded so it is not lost; none is a ruling until
`IMPLICIT-PROPS-DESIGN.md` says so.

### 10.1 The convention: `GIVEN`s flow to callees by name

Meng's extensible-record framing (a `ReaderT (Record xs)` with `Lookup xs "issuer" IssuerProfile`
constraints and an `extendEnv` for sub-computations) adds one rule to the §4 position: **every
`GIVEN` binding is also an implicit binding of the same name for the callee.** Application is
`extendEnv` with the caller's argument names; `LET x = v IN e` is the one explicit extension. This
is generation-one dynamic binding of parameters (LISP 1.5, Emacs Lisp) made static: inferred,
elaborated by discharge, reported at the root. Its hazard is accidental capture; the argument that
it is benign here is that parameter names are legal vocabulary.

Measured (2026-09-03, 1,774 `GIVEN` slots, 559 distinct names in the legal corpus): 17 names bound
at more than one type corpus-wide, 9 within a single file, all of them one-letter conveniences
(`a`, `b`, `f`, `p`, `w`) or a `DATE` vs `MAYBE DATE` lifting. **Rule adopted as a candidate: one
name, one type, per module**, checked only when a name is read implicitly. Requirements therefore
stay sets; no row polymorphism.

Resolution order for a free name: the function's own `GIVEN`, then the nearest enclosing section
`GIVEN` (10.2), then the caller chain, then an error at the root. Lexical beats call-site. Nothing
implicit crosses `IMPORT` (discharge at the module boundary).

Environments as tiers, by binder: application (prelude/config: `TIMEZONE`, `RULES EFFECTIVE DATE`,
jurisdiction, request id; supplied by the deployment; already the eight axes of the temporal
context), world (module/section `GIVEN`s; supplied by the request), call (function `GIVEN`s;
supplied by callers). The exporter's existing tier census classifies by call-site variation, so
world-vs-subject is measured, not declared.

### 10.2 Section-level `GIVEN` replaces `ASSUME`'s term role

**A section is a function of its `GIVEN`s. The module is the outermost section (the title `§`,
which all 26 legal files have). A function's `GIVEN`s flow to its callees.** Coq
`Section`/`Variable` exactly; `ASSUME`'s term job was "section `GIVEN`" without types you can
supply. Rules: visibility is the shipped nearest-ancestor section rule (its parent-ambiguity
defect, §7, fixed first); extension only — a child section may add names, never re-declare an
ancestor's; rebinding is `LET` at a site.

Motivation measured (2026-09-04, 1,860 `GIVEN` parameter slots, 26 files): **889 (48%) repeat an
identical name and type declared earlier in the same section; 1,177 (63%) repeat earlier in the
same file.** `regcf.l4:280-330` opens eight consecutive functions with `GIVEN issuer IS AN
IssuerProfile`. This is the feature Meng had long wanted: factoring the common `GIVEN`s of a run of
functions. Trade: per-function `@desc` on a shared parameter (five different `issuer` descriptions
in `regcf-denovo.l4`) collapses to one per section.

`ASSUME` deprecation path, fully spelled: term `ASSUME` → section `GIVEN` under the nearest header
(the 9 of 39 declared-in-a-sibling-section cases hoist to the title `§`); type `ASSUME` → an empty
`DECLARE T`, which already parses (`ok/set-operators-nested.l4:36`, `ok/consider-simple.l4:3`);
refusal `ASSUME` → a `REFUSE "…"` builtin at any type (`regcf.l4:143,486`, `daydate.l4:104`,
prelude `TBD`). Counts: legal 54, ok 97, not-ok 20, experiments 418, doc 71, libraries 2, tests-cli 2
lines; 113 type-role; 105 files. Order: `REFUSE` → read-set fact + export-schema test → field
opening + discharge → DMN exporter consumes read-sets → legal corpus → deprecation warning →
fixtures/experiments/docs → remove keyword.

### 10.3 Disambiguating a section `GIVEN` from the next function's

Today every top-level declaration is parsed **signature-first** (`Parser.hs` `topdecl` =
`withTypeSig (declare | decide | assume)`), so a `GIVEN` is by construction the prefix of the next
declaration; `MkSection` has no parameter slot. Probes on the 2026-08-27 binary: a `GIVEN` whose
name the head does not bind still makes the definition a function of it (`GIVEN a IS A NUMBER` /
`f MEANS a PLUS 1` / `#EVAL f WITH a IS 41` → 42); an indented `GIVEN` and a header-line `§ S GIVEN
a …` both parse today and attach to the next function.

**Candidate rule (layout): a `GIVEN` belongs to the section iff its keyword sits at a column
greater than the header's `§`** — on the header line, or indented beneath it. Column-1 `GIVEN`
stays the next declaration's signature. Measured: "adjacency" (the `GIVEN` right after a header is
the section's) would reinterpret **160** sites in the legal corpus where a section's first function
opens with a `GIVEN`; indentation collides with **zero** existing lines (no indented `GIVEN` in the
corpus). Implementation: `MkSection` gains `Maybe (GivenSig n)`; `section n` gets
`optional (indented givens headerColumn)`; both guarded printers (§3.2 of `CLAUDE.md`) emit the
indented form. The anonymous top-of-file section has no header and cannot carry one.

### 10.4 Candidate keyword for the section binder: `WHEREAS`

Minuted at Meng's request (2026-09-04) as the fallback to 10.3 — Coq's answer, a distinct keyword
for the section binder (`Variable` vs a definition's binders; Isabelle `fixes`) — and, if taken,
the successor spelling of `ASSUME`'s term role:

```l4
§§ `Rule 100(b) — issuer eligibility`
WHEREAS issuer IS AN IssuerProfile
```

- **Fit.** In contracts `WHEREAS` opens the recitals: the premises stated before the operative
  terms. "Given these facts, the following applies" is exactly a section parameter. Older Acts use
  the same preambular register ("Whereas it is expedient …").
- **Risk.** In contract-drafting convention recitals are _non-operative_; a lawyer may read
  `WHEREAS` as background narrative, whereas a section parameter is fully operative. Worth testing
  on a drafter before ruling.
- **Mechanics.** With a keyword, no layout rule is needed: it can sit at column 1, and, like
  today's `ASSUME`, anywhere in its section, order-independent, binding the whole section. Lexer:
  keywords are a whole-token `Map Text TKeywords` (`Lexer.hs:246`), so no prefix clash with
  `WHERE`; the token `WHEREAS` is unused anywhere in `jl4/`, `jl4-core/`, `doc/` (20 lowercase
  prose occurrences only).
- **Cost.** One new keyword, which §4 was trying to avoid; ExactPrint/prettyLayout support as for
  10.3.

Decision pending: 10.3 (layout, no keyword) first, 10.4 in reserve; or 10.4 outright if the
non-operative reading of recitals is judged confusing enough to forbid the layout form.

#### 10.4.1 Sibling candidate: `WHEREIN` (minuted 2026-09-04)

```l4
§§ `Rule 100(b) — issuer eligibility`
WHEREIN issuer IS AN IssuerProfile
```

- **Fit.** "In which": the section, in which the issuer is an `IssuerProfile`. Patent-claim
  drafting uses `wherein` clauses to characterise an element already introduced, and they are
  operative (limiting), which removes `WHEREAS`'s non-operative-recital risk. Grammatically it
  suits a **typed declaration** (characterising an entity) better than `WHEREAS`, which suits a
  **stated premise** (a proposition). A section `GIVEN` is the former.
- **Risk.** Proximity to the existing `WHERE` keyword, which introduces a rule's local
  definitions (125 blocks in the legal corpus). Both mean "in which"; the pair would have to be
  taught together — `WHERE` binds definitions below a rule, `WHEREIN` binds parameters below a
  heading — or the similarity becomes a source of confusion. Also archaic; rare in modern
  statutes.
- **Mechanics.** As for `WHEREAS`: whole-token keyword lookup, no prefix clash; the token is
  unused anywhere in `jl4/`, `jl4-core/`, `doc/`, and the word does not even occur in prose there.
- **Cost.** As for `WHEREAS`.
