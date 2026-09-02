# L4 ⇄ Blawx: expressive-domain overlap and transpiler spec

_Status: **shipped and merged; this file is retained as the ruling record.** Design written
2026-08-16 (merged as PR #261); rulings R1–R14 answered by Meng 2026-08-18; all five phases of
§10 built and merged over 2026-08-18…08-19 — the shared relational middle-end
`L4.Relational.{IR,Lower,Debug}` first, Blawx-driven per R2 (PR #272), then
`L4.Blawx.{IR,Lower,Emit}` plus the `l4 blawx` CLI verb mirroring the OpenFisca backend
(#273), `EmitXml` and the re-save fixpoint (#277), the P4 showcase ladder (#278), and the
`Parse`/`Lift` pair for import behind `l4 blawx --import`, R14 (#279). Per-phase evidence is
recorded inline in §10; reader-facing documentation landed as PR #280
(`doc/concepts/neighbours/blawx-and-scasp.md`, `doc/tutorials/blawx/l4-to-blawx.md`).
**Verified against `origin/unstable` on 2026-08-28**: eight modules under
`jl4-core/src/L4/Blawx/`, three under `jl4-core/src/L4/Relational/`, and the corpus under
`jl4/examples/blawx/` — nineteen `.l4` files as re-counted on 2026-09-02 (twelve emitting seeds
each with a golden in `expected/`, six `not-ok/` refusal fixtures, one `imported/`; it read
"sixteen … eleven … five" for the 2026-08-28 tree, and the §11 work moves it, so re-derive with
`ls jl4/examples/blawx/*.l4 jl4/examples/blawx/not-ok/*.l4` rather than trusting the number) —
and the verb
wired at `jl4/app/Main.hs:110` →
`jl4/app/L4/Cli/Blawx.hs`. What remains open: R10's fork fixes wait in
`legalese/blawx` (#1–#5, filed 2026-08-20, see §8.10) until upstreaming to Lexpedite is
warranted — and, since 2026-09-02, the **measured worklist of §11**, which \_is_ code: an
exporter defect (W1), an ontology gap (W2), the import fragment's distance from Blawx's own
running examples (W5), and the build pins the fork now carries (W8). (This header read "implementation beginning … nothing exists under
`jl4-core/src/L4/Blawx/` or `jl4-core/src/L4/Relational/`" until 2026-08-28. That was true the
day it was written and false the day after; it survived because §10's per-phase EXECUTED notes
were appended without re-reading the top of the file. Do not restore it.) Siblings:
`CATALA-EXPORT-SPEC.md` (PR #260) is the house template this spec follows;
`specs/proposals/LOGIC-PROGRAMMING-BACKENDS-SPEC.md` (PR #258) specified the shared relational
middle-end this spec consumes (§1.1, R2) — built as `L4.Relational` by #272, to the
implementation brief in `RELATIONAL-M1-BRIEF.md`; the defeasibility prior-art evidence of §5.2 is
consolidated into `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` by PR #262, whose
`BACKEND-PORTFOLIO-SPEC.md` records this bridge as seam S2 of the backend portfolio.\_

**One-line summary.** Where OpenFisca receives L4's `@export` decisions as Python formulas and
Catala would receive them as scopes, Blawx receives them as **s(CASP) logic programs**: the
transpiler's core move is _relationalization_ — results become arguments, expression trees become
goal conjunctions — and in exchange Blawx returns four things L4 does not currently own: a
natural-language justification tree for every answer, an interview-driving scenario explorer,
hypothetical (abductive) reasoning over unknown facts, and a per-rule REST API. Because Blawx's
wire format is a Django fixture YAML pairing Blockly XML with s(CASP) per _statutory section_,
L4's isomorphism discipline transfers structurally — and the same block-level IR that drives
export can drive **import**, which this spec assesses as feasible for the fragment Blawx's own
example corpus inhabits (§5.2, R14).

**Evidence legend.** **[E]** = read out of the named file at the named commit, or executed, by
this design pass. **[U]** = believed true, not executed here. Blawx facts were read from the
checkout at `/Volumes/transcend/src/blawx`, commit `02eded1` (2026-08-16; `BLAWX_VERSION =
"v1.6.22-alpha"`, `blawx/settings.py:16`). L4 facts were read from `l4-ide` at `8af7d332`
(`origin/unstable`, the base of this branch). No Blawx instance was running when this spec was
first written, so emitted-code examples begin life **[U]**; standing up the Docker instance and
promoting them is R13's first deliverable. During this pass the s(CASP) pack was installed
into the local SWI-Prolog 9.2.9 and a tier-1 harness prototype executed Appendix A's rules
and test successfully **[E]** (see the appendix header); the Docker leg (colima, VM data on
`/Volumes/transcend` per environment constraint) was provisioned for tier 2.

> **A warning about the reference corpus, discovered the hard way.** Most of Blawx's shipped
> examples carry _stale_ generator output. `mortality.yaml` — the obvious "minimal reference
> pair" — is several generator versions old: it lacks `:- dynamic`, the 11 temporal `#pred`
> lines, and all 20 frame axioms that the current generator emits per declaration **[E]**.
> **`life_act.yaml` is the only shipped example whose `scasp_encoding` byte-matches the current
> generator** (diffed line-by-line against `scasp_generator.js` by this pass **[E]**). Every
> byte-exactness claim below is calibrated against `life_act.yaml` and the generator source, not
> against `mortality.yaml`.

---

## 0. Ruling status

| ruling | state                   | detail                                                             |
| ------ | ----------------------- | ------------------------------------------------------------------ |
| R1     | **ANSWERED 2026-08-18** | `.blawx` YAML primary; raw `.pl` dumped alongside, §8.1            |
| R2     | **ANSWERED 2026-08-18** | Blawx _drives_ `L4.Relational`; findall/DNF middle-end first, §8.2 |
| R3     | **ANSWERED 2026-08-18** | no `@desc` name side-channel in v1, §8.3                           |
| R4     | **ANSWERED 2026-08-18** | flat numbered CLEAN sections for v1, §8.4                          |
| R5     | **ANSWERED 2026-08-18** | as proposed; CWA bridges yes-later on corpus need, §8.5            |
| R6     | **ANSWERED 2026-08-18** | Mode A first; Mode B gate = bounded truth tables, revisit, §8.6    |
| R7     | **ANSWERED 2026-08-18** | as proposed; money = cents as integers, §8.7                       |
| R8     | **ANSWERED 2026-08-18** | as proposed; date-library requirements ledger opened, §8.8         |
| R9     | **ANSWERED 2026-08-18** | share recognisers for now; free to break loose later, §8.9         |
| R10    | **ANSWERED 2026-08-18** | byte-exact incl. quirks; quirk-fix PR goes to our fork, §8.10      |
| R11    | **ANSWERED 2026-08-18** | as proposed; `#ASSERT` also emits `false :-`, §8.11                |
| R12    | **ANSWERED 2026-08-18** | delegated; proposal stands as written, §8.12                       |
| R13    | **ANSWERED 2026-08-18** | no checksum pin; loud provenance comment instead, §8.13            |
| R14    | **ANSWERED 2026-08-18** | CLI = `l4 blawx --import`; Blawx may drive SUBJECT-TO, §8.14       |

All fourteen rulings were answered by Meng on 2026-08-18; each §8 entry carries the ruling
beneath its original evidence/cost/case-against, per house style. Consequences now in motion:
`L4.Relational` is implemented under this programme with the Blawx session coordinating (R2);
the date-library requirements ledger exists at `specs/todo/DATE-LIBRARY-SPEC.md` (R8); the
Lexpedite quirk-fix path goes through our fork of Blawx (R10).

## 1. Purpose, direction, precedent

Direction is **two-way by directive** (Meng, 2026-08-16): L4 → Blawx ships first, in the same
sequence as the OpenFisca bridge; Blawx → L4 is assessed for feasibility in §5.2, ruled in R14,
and sequenced as P5 in §10 — a planned phase, not a non-goal.

The OpenFisca precedent fixes the forward shape: `lowerModule :: Module Resolved -> Either
[LowerError] …` consuming the `@export`-annotated `DECIDE`/`MEANS` subset, rejecting everything
else with a named diagnostic, errors accumulated not short-circuited
(`jl4-core/src/L4/OpenFisca/Lower.hs:31-79` **[E]**). Its documentation discipline also carries
over: golden tests prove regression-stability only; a "round-trip" is an execution of the emitted
artifact in the real target toolchain against values L4's own evaluator produced
(`jl4/examples/openfisca/L4-OPENFISCA.md` §6 **[E]**).

What Blawx buys that OpenFisca and Catala do not:

1. **Explanations for free.** Blawx wraps every query in `blawxrun/4`, which extracts an s(CASP)
   justification tree and renders it through the `#pred` NLG annotations into plain-language
   "why" output (`blawx/reasoner.py:534-585` **[E]**). If the transpiler emits proper
   declarations and `#pred` strings (R10), every transpiled decision explains itself — a
   left-brain complement to the ladder/`#EVALTRACE` story, produced by someone else's engine.
2. **The interview loop.** The `interview` endpoint mines abducible assumptions out of the
   justification tree to compute "Relevant Statements" — which facts would change the answer —
   and the scenario editor drives a question-asking UI off it (`reasoner.py:1350-1353` **[E]**).
   This is a working analogue of L4's question-ordering wizard, keyed off three-valued logic
   rather than model counting.
3. **Hypothetical reasoning.** `#abducible` declarations let Blawx answer "under what
   assumptions could this succeed?" — no L4 surface currently does abduction.
4. **A REST API per encoded rule** (`urls.py:31-33` **[E]**), session- or published-anonymous
   auth, JSON answers with bindings, models, and NLG trees — a deployment story the bridge
   inherits without building anything.

Two further reasons specific to this neighbour. Blawx is the reference _logic-programming_
rules-as-code tool — the tradition (Kowalski, Sergot, Governatori, Morris) that L4's own
related-work reading engages most directly, and the bridge meets that community in its own
format. And Blawx's **defeasibility machinery** (`according_to`/`holds`/`blawx_defeated`,
`overrules`) is a live, shipped implementation of the semantics that
`specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md` contemplates for L4 — like Catala's exception
DAG, it is prior art; unlike Catala's, we can _target_ it incrementally (R6 Mode B).

### 1.1 Position among the logic-programming backends (PR #258)

`specs/proposals/LOGIC-PROGRAMMING-BACKENDS-SPEC.md` (open PR #258) argues that swipl, ASP,
Logical English and PROLEG are **one missing middle-end** — `L4.Relational`: A-normal-form
flattening with an output argument, materialised guard prefixes, a stratification check,
defunctionalised prelude combinators — plus comparatively thin emitters. **Blawx is a fifth
consumer of that middle-end, not a fifth lowering.** Its reasoner is s(CASP) — the exact
dialect #258 names for justification trees and CLP(Q) (its §5.2) — and everything in this
spec that concerns _lowering_ (relationalization, guard-prefix materialisation, negation
soundness) is delegated to `L4.Relational` when it exists (contingency in R2). What is
genuinely Blawx-specific is the **emitter, which is thick where the other four are thin**: a
wire format embedding two representations, 44-line ontology declaration blocks, `#pred` NLG,
section anchoring, test emission, and the Blockly XML pairing.

On #258's preservation lattice (truth condition / multiplicity / burden of proof / NL
surface), Blawx lands strikingly high for a single target: truth condition ✓ (stratified
fragment); multiplicity ✓ (stable-model semantics, goal-directed, no grounding); NL surface ✓
(`#pred`-rendered justification trees — the Logical English column's virtue by different
means); burden ✗ — but **override structure survives as data**: `overrules`/`blawx_defeated`
name _which section defeats which_, which is PROLEG's `exception/2` insight minus the burden
attribution. No single #258 target preserves that combination, which is the case for Blawx as
a target in its own right rather than a styling of the swipl leg.

One natural4 lesson from #258's post-mortem binds directly here: its old Prolog emitter
flattened `Not` and `Any` into decorative `neg`/`or` pseudo-atoms — output that parses and
means nothing. Blawx's rule bodies are conjunction-only, so the temptation recurs; the
DNF-split of §4.3 (real disjunction = multiple rules sharing a conclusion, the target's own
idiom) exists precisely to keep that named failure mode inexpressible.

The distinctive risk, stated up front: **Blawx's code generation happens only in the browser.**
`static/blawx/scasp_generator.js` is the authoritative block→s(CASP) mapping; the server stores
both representations verbatim and never derives one from the other (`views.py:384` **[E]**,
generator `scasp_generator.js:10` **[E]**). A transpiler must therefore _reimplement the JS
generator byte-for-byte_ — two-space `statementToCode` indents, `% BLAWX CHECK DUPLICATES`
marker placement, trailing-newline conventions and all — because the fidelity contract is a
**re-save fixpoint**: open the imported project in the Blawx editor, save, and the server-stored
`scasp_encoding` must be byte-identical to what we shipped (R12). Neither OpenFisca nor Catala
posed a wire-format challenge of this kind.

## 2. Blawx's expressive domain, as verified

Every claim **[E]** at `02eded1` unless marked. Architecture: a single Django project storing
`RuleDoc` (legal source text in CLEAN markup) → `Workspace` per statutory section (paired
`xml_content` Blockly XML + `scasp_encoding`) → `BlawxTest` (a workspace plus a query plus an
optional JSON fact scenario), executed by SWI-Prolog s(CASP) via `swiplserver` MQI
(`models.py:12-62`, `reasoner.py:534-585`).

- **Ontology declarations are load-bearing.** Categories (unary), attributes (binary, declared
  against a category, with a value type ∈ `boolean|number|date|time|datetime|duration|list|`
  category-name), relationships (arity 3–10). Each declaration emits a fixed **44-line block**:
  3 header lines (`blawx_category/1` or `blawx_attribute/3` or `blawx_relationship/N+1` fact +
  `*_nlg` fact + `:- dynamic p/N.`), exactly **21 `#pred` NLG annotations**, and exactly **20
  temporal frame axioms** (8 `blawx_not_interrupted`, 4 `blawx_as_of`, 8 `blawx_during`)
  deriving time-indexed truth from `blawx_initially`/`blawx_ultimately`/`blawx_becomes` events
  with `bot`/`eot` sentinels (`scasp_generator.js:927-1156` **[E]**, cross-checked byte-for-byte
  against `life_act.yaml`). Undeclared predicates lack NLG, scenario-editor visibility, and
  temporal reasoning. **Boolean attributes are unary predicates** (`alive(X)`, not
  `alive(X,true)`).
- **Rules.** The `attributed_rule` block emits a defeasibility triple with the conclusion
  _flattened_ — predicate name becomes an argument (`deconstruct_term`,
  `scasp_generator.js:1542-1555`):

  ```prolog
  according_to(sec_1_section,mortal,A) :- human(A).
  % BLAWX CHECK DUPLICATES
  holds(sec_1_section,mortal,A) :- according_to(sec_1_section,mortal,A).
  % BLAWX CHECK DUPLICATES
    mortal(A) :- holds(sec_1_section,mortal,A).
  ```

  The third rule's two-space indent is the generator's `statementToCode` indent leaking through;
  it is part of the byte-exactness contract. With the rule's _defeasible_ checkbox, the second
  rule gains `, not blawx_defeated(Section,Concl…)`. The marker line must be exactly
  `% BLAWX CHECK DUPLICATES` with no surrounding whitespace — the reasoner string-compares it
  and dedups the _next_ line across workspaces (`reasoner.py:496-516` **[E]**), which is how the
  bridge rules of same-conclusion rules in one section avoid double assertion.

- **Defeat.** `overrules` emits `blawx_defeated(Weaker,C…) :- holds(Stronger,C…)`; `opposes/2`
  declares conflicting conclusions. (The often-repeated claim that boolean attributes auto-emit
  an `opposes` pair is true only of the _legacy_ `attribute_declaration` block; the current
  `new_attribute_declaration` emits none — booleans are unary, so there is nothing to oppose
  (`scasp_generator.js:449-452` vs `:1012-1032` **[E]**).) Negative conclusions use classical
  negation `-p(…)`. Constraints are `false :- ….`; assumptions are `#abducible p.`; queries
  exist only in tests, as the **last** line starting `?- ` (the reasoner's scan has no `break`,
  and blindly chops the final character — the line must end in exactly one `.`;
  `reasoner.py:544-547` **[E]**).
- **Three-valued.** s(CASP) distinguishes provably-true / provably-false (`-p`) / unknown
  (`not p` = negation-as-failure). There are no `known`/`unknown` blocks — three-valuedness
  surfaces only through `-`, `not`, `#abducible`, and the fact-scenario translator's
  `"unknown"` type, which emits the abduction pair `p :- not -p.` / `-p :- not p.`
  (`reasoner.py:89-165` **[E]**).
- **Terms.** Variables are capitalised; objects/categories/attributes must match
  `^[a-z]\w*$` and not end `_\d+` — since v1.6.17 the blocks _validate and auto-rewrite_
  nonconforming names (`blawx-blocks.js:5215-5250` **[E]**), so the transpiler must emit
  already-conforming atoms or the UI will silently rewrite them (R3). Equality `X = Y`,
  disequality `blawx_diseq(X,Y)`; arithmetic `Var is Expr` (`+ - * /`); comparisons
  `blawx_comparison(X,Op,Y)` with `Op ∈ eq|neq|gt|gte|lt|lte`, implemented over the CLP
  constraint operators `#=`/`#>`/… (`passthrough.py:13-18` **[E]**) so they work on unbound
  constrained variables.
- **Dates** are functor-wrapped POSIX numbers: `date(Ts)`, `datetime(Ts)`, `time(SecsSinceMidnight)`,
  `duration(Seconds)`. Working subset: `date_compare/3`, `duration_compare/3`, `date_add/3`,
  server-stamped `blawx_now`/`blawx_today`. A substantial _broken_ family generates calls to
  predicates defined nowhere (`days_between_datetimes`, `datetime_diff_duration`,
  `datetime_add_days`, `datetime_to_posix_timestamp`, `posix_timestamp_to_datetime`) or emits
  multi-argument forms (`date(Y,M,D)`) the libraries never match (`scasp_generator.js:584-825`
  **[E]**) — the transpiler must avoid the whole family (R8). Three timestamp landmines:
  browser-side literals are integers in the _browser's_ timezone; the fact-scenario translator
  emits **floats** (`str(datetime.timestamp())` → `date(946684800.0)`) in the _container's_
  timezone; and floats do not structurally unify with integers in `date_compare`'s `eq`
  (`reasoner.py:304-340`, executed by this pass **[E]**). R8 and R11 route around all three.
- **Lists.** `[]`, `[H|T]`, `findall/3` (`collect_list`), then
  `count_blawx_list`/`sum_blawx_list`/`average_blawx_list`/`min_blawx_list`/`max_blawx_list`,
  emitted with a literal `' , '` separator (`scasp_generator.js:861-907` **[E]**). Recursion is
  native Prolog — `aggregates.py` itself is written in `[H|T]` style.
- **The wire format.** A `.blawx` file is three concatenated Django `dumpdata` YAML
  serializations, in order: exactly one `blawx.ruledoc`, then `blawx.workspace` rows, then
  `blawx.blawxtest` rows (`views.py:102-122` **[E]**). `POST /import/` remaps every pk and the
  owner, and reassigns each subsequent object's `ruledoc` FK to the newly-saved RuleDoc — pks in
  the file are placeholders, but the **ruledoc must be first** (`views.py:124-155` **[E]**).
  `akoma_ntoso`, `navtree`, `rule_slug` may be omitted: a `pre_save` signal recomputes all three
  from `rule_text` on every save via the `clean-law` package (CLEAN markup → Akoma Ntoso;
  `models.py:35-39` **[E]**). Workspace names must be `<AKN eId>_section` (e.g. `sec_1_section`,
  `sec_34__subsec_1__para_b_section`) or `root_section`, because the UI's per-section canvases
  key on eIds derived from `rule_text` (`parse_an.py:45-65` **[E]**). `xml_content` is never
  validated or executed server-side; `scasp_encoding` is never displayed. s(CASP)-only output
  runs headlessly but shows empty canvases _and is destroyed by any UI save_; XML-only output
  displays but does not run (`buttons.js:18-36`, `reasoner.py:493-545` **[E]** — hence R12).
- **The run endpoint.** `POST /<user>/<rule_slug>/test/<test_name>/run/` with `{}` runs a test
  headlessly; response `{"Answers": [{"Variables": {...}, "Models": [...]}], "Transcript": ...}`
  (`reasoner.py:470-634` **[E]**). Session auth, or anonymous against a `published` RuleDoc.
  This is the P2 round-trip surface.

## 3. L4's expressive domain, by layer

Keyword ground truth: `jl4-core/src/L4/Lexer.hs` **[E]** at `8af7d332`; the layer inventory
below was independently verified against the same tree for the Catala study and re-checked here
where load-bearing.

1. **Constitutive / decision layer.** `DECLARE` records and enums-with-payloads;
   `GIVEN`/`GIVETH`/`DECIDE`/`MEANS` functions (higher-order, polymorphic, recursive, mixfix
   names); `CONSIDER`/`WHEN` pattern matching (exhaustiveness-checked); `BRANCH` first-match
   cascades; `IF`/`THEN`/`ELSE`; `WHERE` helpers; `LIST`, `MAYBE`, `SET OF`; `UNLESS` — pure
   sugar for `AND NOT` (`jl4-core/src/L4/Parser.hs:1669` **[E]**); `ASSUME` for uninterpreted
   inputs. After resolution, infix operators arrive as `App` of builtins (`__PLUS__`,
   `__AND__`, …), not dedicated constructors (`OpenFisca/Lower.hs:357-373` **[E]**) — any new
   `Lower` must handle both forms.
2. **Regulative layer.** `Regulative`/`Deonton` (`PARTY … MUST|MAY|SHANT … WITHIN … HENCE …
LEST`), `Breach`, `RAnd`/`ROr`, `#TRACE` (`Syntax.hs:227-228,248,323,361-388` **[E]**).
3. **Temporal layer.** `EVAL … UNDER RULES EFFECTIVE AT` (builtin term + `L4.TemporalContext`).
4. **Effect / ledger layer.** `FETCH`/`POST`/`ENV`, `Record`/`ReadCell`
   (`Syntax.hs:260-320` **[E]**).
5. **Annotation layer.** `@export`/`@desc` (selection surface: `L4.Export.getExportedFunctions`,
   `Export.hs:115` **[E]**), `@ref`/`@ref-src`/`@ref-map`, `@nlg`, `TYPICALLY`
   (metadata-only literal defaults).

The overlap with Blawx: **all of layer 1 except strings-as-computation, general higher-order
code, and payload-carrying enums (emulated); layer 5 profitably (`@ref` → section anchoring,
`@nlg` → `#pred`); layers 2–4 not at all** — though Blawx's event layer is the nearest foreign
relative of layer 3, and its defeat machinery awaits a future L4 defeasibility surface (§5).

## 4. The overlap, construct by construct

Verdicts: **CLEAN** (structure-preserving), **RESTRICTED** (maps under a side condition),
**EMULATED** (maps through a compilation scheme), **OUT** (rejected with a diagnostic).

| L4 construct                                             | Blawx construct                                                  | verdict                                    | ref   |
| -------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------ | ----- | ---- |
| `DECLARE X HAS …` (record)                               | category + typed attributes                                      | CLEAN                                      | §4.1  |
| `DECLARE X IS ONE OF …` (no payloads)                    | category + object declarations per constructor                   | CLEAN                                      | §4.1  |
| enums with payloads                                      | — (no ADT blocks)                                                | OUT (v1)                                   | §4.1  |
| `MAYBE` field                                            | attribute optionality (absent fact)                              | EMULATED                                   | §4.1  |
| boolean `@export` decision over subject record           | boolean (unary) attribute + attributed rules                     | CLEAN                                      | §4.2  |
| value-returning decision                                 | binary attribute, result as last argument                        | CLEAN                                      | §4.2  |
| multi-`GIVEN` decision                                   | relationship (arity ≤ 10 incl. result)                           | RESTRICTED                                 | §4.2  |
| `WHERE` helpers                                          | auxiliary predicates in the same section                         | CLEAN                                      | §4.2  |
| nested expressions                                       | ANF-flattened goal conjunctions, fresh variables                 | EMULATED                                   | §4.2  |
| `AND` in rule bodies                                     | goal conjunction (condition stack)                               | CLEAN                                      | §4.3  |
| `OR` in rule bodies                                      | multiple rules with one conclusion (DNF split / aux predicates)  | EMULATED                                   | §4.3  |
| `NOT` (inputs / computed / comparisons)                  | `-p` / `not p` / complementary operator                          | RESTRICTED                                 | §4.3  |
| `UNLESS`                                                 | `AND NOT` (Mode A) or defeasible + `overrules` (Mode B)          | CLEAN                                      | §4.3  |
| `IF`/`THEN`/`ELSE` in value position                     | guarded rule pair (guard / negated guard)                        | EMULATED                                   | §4.4  |
| `CONSIDER` on enums                                      | equality-discrimination goals per arm                            | CLEAN                                      | §4.4  |
| `BRANCH` first-match cascade                             | guard chain: arm _i_ carries negations of guards 1.._i−1_        | EMULATED                                   | §4.4  |
| `NUMBER`                                                 | CLP-constrained numbers; `is` arithmetic                         | RESTRICTED                                 | §4.5  |
| `BOOLEAN`                                                | unary predicate truth                                            | CLEAN                                      | §4.5  |
| `DATE`                                                   | `date(posix)`; `date_compare`/`date_add`, day-granular           | RESTRICTED                                 | §4.6  |
| `STRING` literals (equality only)                        | atoms                                                            | RESTRICTED                                 | §4.7  |
| string builtins                                          | — (no string operations in the target)                           | OUT                                        | §4.7  |
| `sum`/`length`/`min`/`max`/average patterns              | `findall` + `*_blawx_list` aggregates                            | CLEAN                                      | §4.8  |
| `map`/`filter` (general)                                 | emitted auxiliary recursive predicates                           | EMULATED                                   | §4.8  |
| structural recursion over lists                          | `[H                                                              | T]` rules — **admitted** (contrast Catala) | CLEAN | §4.8 |
| general recursion (non-structural)                       | — (termination unassured under s(CASP))                          | OUT (v1)                                   | §4.8  |
| higher-order arguments                                   | —                                                                | OUT                                        | §4.8  |
| `§` headers, inert scaffolding, `@ref`                   | CLEAN `rule_text` + section-anchored workspaces + `according_to` | CLEAN                                      | §4.9  |
| `@nlg` / mixfix decision names                           | `#pred` NLG strings                                              | CLEAN                                      | §4.9  |
| `#EVAL` / `#ASSERT`                                      | BlawxTest (facts + query)                                        | CLEAN                                      | §4.10 |
| `ASSUME`d inputs                                         | declared predicates; `#abducible` in the interview test          | CLEAN                                      | §4.10 |
| `TYPICALLY`                                              | — (no default machinery; dropped, disclosed)                     | OUT                                        | §5.1  |
| `PARTY MUST`/`HENCE`/`LEST`, `#TRACE`, ledger, EVAL pins | —                                                                | OUT                                        | §5.1  |

### 4.1 Ontology: records, enums, MAYBE

The subject record type of an exported decision becomes a **category**; each scalar stored field
becomes an **attribute** with the corresponding Blawx value type (`BOOLEAN` → `boolean` unary,
`NUMBER` → `number`, `DATE` → `date`, `LIST OF …` → `list`, record-typed field → attribute whose
value type is the field's category). Payload-free enums become a category plus one declared
object per constructor. Enums _with_ payloads have no block-representable counterpart — s(CASP)
compound terms would run but could not be drawn or edited, violating R12 — so they are OUT in
v1 with a named diagnostic. A `MAYBE T` field maps to attribute _optionality_: `NOTHING` = no
fact asserted, `JUST v` = the fact — with the §4.3 caveat that "absent" and "unknown" are
different states in Blawx's three-valued world; the lowering must pick per R5.

**Records project as categories, but record _identity_ does not project at all, and since
2026-09-02 comparing two records is refused.** An L4 record is a value and `EQUALS` on it is
structural; a Blawx object is an atom and `=` on it is identity of the name. The two coincide only
if every distinct record value gets exactly one object, and R11's query flattening does not do that
— it emits one object per _occurrence_ (§8.11).

**What `L4.Blawx.Lower.recordIdentity` refuses, exactly**: an `REq` or `RNeq` either of whose
operands is a variable whose recovered sort _contains_ a **declared** (`DECLARE … HAS`) record sort
— directly, or under any nesting of `LIST OF` and `MAYBE` — with the named diagnostic
`record identity (Blawx)`. Directly covers a record-typed parameter, an object-valued field read
and a record-returning call; the container cases are what the first cut of this check missed, and
they are not hypothetical: measured 2026-09-02, `a's members EQUALS b's members` over a
`LIST OF Player` field lowered clean and emitted
`members(A,Members), members(B,Members2), Members = Members2.`, which is the same by-value /
by-atom divergence with a green exit code. A _bare_ `MAYBE Player` field never reaches this check —
`blawxValueType` refuses it first, "sort with no Blawx value type" — so `LIST OF MAYBE Player` is
the only reachable way a `MAYBE` gets under it, which is why the fixture carries one.

**What it does not refuse, deliberately.** An operand whose category is an `ASSUME T IS A TYPE`
still unifies, and must: `RSRecord` carries an abstract category as well as a declared record
(`L4.Relational.IR` says so, and says the discriminator is a lookup among the declared records),
but an abstract category has no fields for L4 to compare structurally. Its values are atoms on both
sides, `=` on atoms is the faithful image, and refusing it would delete an emission that works —
`a EQUALS b` over two `ASSUME`d `Person`s emits `A = B.` — while recommending an edit, compare a
field, that has no field to name. Nor is a record-sorted operand detected whose sort did not
survive into `varSorts` as a sort at all (an `RSOpaque`): there is nothing left in the sort to
test. No such case is known to be reachable in the M1 fragment and none was constructed.

The diagnostic names both the divergence and the two edits that avoid it (state the rule once per
slot; or compare an enum- or number-valued field, whose sorts _are_ atoms and do survive the
flattening), and it names the operand's own sort, because "of record type `Player`" would be a
false description of a `LIST OF Player` operand. The refusal is in the Blawx leg and not in
`L4.Relational.Lower` because it is the Blawx-side flattening that breaks the correspondence: the
shared IR's `REq` is generic equality whose meaning each emitter dispatches (§8.2), and a backend
that gives one object per distinct value would need no such rejection. Fixtures:
`jl4/examples/blawx/not-ok/record-identity.l4` (bare records) and
`jl4/examples/blawx/not-ok/record-identity-list.l4` (`LIST OF`, `LIST OF MAYBE`); tests in
`jl4-core/test/BlawxAssumeSpec.hs` (four refusals and three positive controls) and
`jl4/tests-cli/Main.hs` (two); the measurement that forced it is §11 W1. This is a v1 refusal, not
the final answer — hash-consing structurally-equal record arguments in `skolemise` would make
identity and value agree and let the refusal lift. That is **not implemented**; §11 W1 records it
as the next step.

### 4.2 Decisions become relations

The load-bearing move, opposite in direction to Catala's: **L4 is functional, Blawx is
relational.** Every `@export` decision `f : Subject -> T` becomes a predicate:

- `T = BOOLEAN` → a unary boolean attribute on the subject's category (`eligible(A)`), matching
  Blawx's boolean special case;
- otherwise → a binary attribute `f(A, Result)` with the result as final argument;
- multi-`GIVEN` decisions → a relationship of arity #params (+1 for a non-boolean result),
  rejected above Blawx's arity-10 ceiling (house style already threads one record, so the
  ceiling should bite rarely).

Bodies are flattened **ANF-style**: every field projection `a's age` becomes a goal
`age(A, Age)` binding a fresh variable; every call to another decision becomes a goal with a
fresh result variable; comparisons become `blawx_comparison/3` goals; arithmetic becomes
`Result is Expr` goals over already-bound variables, ordered so that every variable is bound
before use (Blawx's own list-demo section works exactly this way **[E]**). `WHERE` helpers
lower to auxiliary predicates in the same section's workspace.

Because a function must stay a function after relationalization, the lowering _may_ emit a
**functionality constraint** per value-returning decision —
`false :- f(A,V1), f(A,V2), blawx_diseq(V1,V2).` — turning L4's function discipline into an
s(CASP)-checkable integrity invariant (flag-gated; R2).

### 4.3 Booleans, negation, UNLESS

`AND` is the condition stack. `OR` has **no block** — Blawx expresses disjunction as multiple
rules sharing a conclusion (`wills.yaml` **[E]**) — so bodies are normalised: DNF-split into one
`attributed_rule` per disjunct when small, else factored through auxiliary predicates to avoid
exponential blowup (threshold in R2). The shared bridge rules deduplicate via the
`% BLAWX CHECK DUPLICATES` mechanism, so multiple rules per conclusion are idiomatic, not
wasteful.

`NOT` is the semantic crux (R5). L4 is two-valued and total; s(CASP) is three-valued. Policy:

- `NOT` over a **comparison** → the complementary operator (`gt` ↔ `lte`, `eq` ↔ `neq`):
  provably-correct, never touches negation semantics.
- `NOT` over an **input** boolean attribute → classical `-p(A)`: falsity must be _provable_
  (asserted or derived), so an accidentally-absent input fails loudly (no model) instead of
  silently reading as false, and scenario-editor `false`/`unknown` states behave correctly
  (the fact-scenario translator asserts `-p` for false and the abduction pair for unknown
  **[E]**).
- `NOT` over a **computed** decision → negation-as-failure `not p(A)`: the decision's rules are
  a total definition, so failure-to-prove coincides with L4 falsity whenever inputs are
  complete.

`UNLESS d` denotes `AND NOT d` (Mode A, default — semantics-identical by construction). Mode B
(R6, flag-gated) emits the Blawx-idiomatic form instead: the main rule marked _defeasible_, the
proviso as its own section's rule concluding the negation, and an `overrules` defeat clause —
which reads like the statute, exercises Blawx's signature machinery, and gives justification
trees the "…unless…" shape lawyers expect. Same equivalence-gate discipline as the Catala
study's Mode B: machine-checked truth-table agreement before it ships.

### 4.4 Conditionals and matches in value position

`IF c THEN e1 ELSE e2 : NUMBER` becomes a guarded rule pair — one rule with goal-form `c`, one
with its R5-negation — and similarly `BRANCH` first-match cascades become guard chains where arm
_i_ conjoins the negations of guards 1.._i−1_ (first-match semantics made explicit; the guards
must use the provable-complement forms of R5, not bare NAF, when they range over inputs).
`CONSIDER` over a payload-free enum scrutinee becomes equality-discrimination goals
(`X = constructor_atom`) per arm; exhaustiveness transfers from L4's oracle, so no `OTHERWISE`
synthesis is needed.

### 4.5 Numbers

`blawx_comparison/3` runs over the s(CASP) constraint operators, which the s(CASP) port
implements over rational arithmetic — in principle the same no-float32-cliff story as Catala.
But Blawx's _arithmetic_ goes through Prolog `Var is Expr`, where SWI division of integers
yields floats unless rational mode is active. Whether emitted arithmetic stays exact is a
**measurement, not an assumption**: R7 gates any exactness claim on a P1 experiment (divide 1
by 3 both ways, round-trip against L4's exact rational). Until then: integral literals emit as
integers **[E]**-safe; non-integral literals and division-bearing expressions are
measurement-gated.

### 4.6 Dates and durations

L4 `DATE` → `date(N)` with **N an integer POSIX timestamp at UTC midnight** — integers because
the float forms from the fact-scenario path do not structurally unify with block-emitted
integers **[E]**; UTC because every other party to the timestamp (browser TZ, container TZ)
disagrees with the others and the transpiler must pick one and document it. Comparisons via
`date_compare/3`; day-granular offsets via `date_add/3` with `duration(days*86400)`.
Calendar-month/year arithmetic, and the entire broken block family of §2, are OUT in v1 with
diagnostics. Durations are day/hour/minute/second-granular seconds counts; no calendar
components exist in the target.

### 4.7 Strings — literals in rule bodies only, never a typed field

**Narrowed 2026-09-02 (§11 W2), and corrected the same day after review. This section previously
read "`STRING` literals survive as atoms, usable for equality only", which is true and was being
read as though it covered string-typed _fields_ as well. It does not, and it cannot: Blawx v1.6
has no string attribute value type.**

**The ceiling is in the target, and it is a closed list [E].** A declaration block picks its
attribute's value type from a dropdown, and on the stock checkout
(`/Volumes/transcend/src/blawx-stock`, `origin/main` at `6a717b1`) that dropdown is written out
literally as `[["true / false","boolean"], ["number","number"], ["date","date"],
["time","time"], ["datetime","datetime"], ["duration","duration"], ['list','list']]`
(`blawx-blocks.js:5376`). It is re-populated as categories are declared from
`attributeOptions = [["true / false","boolean"]].concat(allTypes)` (`:5583`, applied to every
attribute block at `:5596`), where `allTypes` is the literal six-entry `datatypeOptions` array of
`:5577` concatenated with the declared category names (`:5579`, or `:5581` when there are none).
The relationship block's per-argument dropdowns are re-populated from that same `allTypes`
(`:5603`); they are _first built_ from a second literal six-entry array at `:5262` and `:5314`,
and an earlier draft of this section mis-cited those two lines as the `allTypes` draw. Both
arrays are string-free, so the conclusion is unchanged and the citation is now the right one.
`scasp_generator.js` adds nothing: R3's value-type evidence at `:927-1156` has exactly two
branches, `boolean` and not-`boolean`, and otherwise passes the dropdown value straight through
into `blawx_attribute(Cat,Name,Type)` (`:927`). So there is no string option to select, and no
per-type branch that could emit one.

The word `string` does occur in those two files — nine times, `grep -c string blawx-blocks.js
scasp_generator.js` → `4` and `5` — but never as a value type: four `JSON.stringify` calls
(`blawx-blocks.js:5280`, `:5428`, `:5430`, `:5494`), and `Blockly.utils.string.wrap`
(`scasp_generator.js:47`), `function text2math(string)` (`:69`), `switch (string)` (`:70`), the
message `"Expecting string from statement block "` (`:104`) and `typeof code == "string"`
(`:107`). It is only the quoted-token form that has a single hit: `grep -cE "'string'|\"string\""`
→ `0` and `1`, that one being `:107` [E]. An earlier draft of this section stated the loose form
("the only occurrence of the word `string`") and was false as written.

**What that means, in two halves.**

- **Refused — a `STRING` sort anywhere in a lowered predicate's signature: field, parameter _or_
  result.** `blawxValueType` (`L4.Blawx.Lower`) has a named `RSString` arm, and `classifyPred`
  runs the signature's `STRING` sorts through it as a pre-pass _before_ classifying, so all three
  positions give the same named diagnostic. The pre-pass is the load-bearing half: `valueType` is
  otherwise reached only from the two arms that build a **declaration block** (the attribute arm,
  and the relationship arm at total arity ≥ 3), and a predicate of total arity ≤ 2 that is not
  attribute-shaped is `PCUndeclared` — rules only, no block, no value types asked for. Measured
  before the pre-pass landed: a two-place derived predicate over a `Player` and a `STRING`
  (``DECIDE `throws named` p s IF s EQUALS "zebra"``) exported at **exit 0**, emitting
  `according_to(sec_1_section,throws_named,P,S) :- player(P), S = zebra.` with no
  `blawx_attribute`/`blawx_relationship` line for it at all, while its arity-3 spelling was
  refused — which is what kept the hole out of sight [E]. The message says what to write instead:
  an enum (`DECLARE … IS ONE OF …`) for a fixed vocabulary, or a category for identity. Measured
  2026-09-02 on `jl4/examples/blawx/not-ok/string-field.l4` and
  `jl4/examples/blawx/not-ok/string-param.l4` (`l4 blawx` on each, **exit 1**; `l4 check` on each,
  **Check succeeded** — the refusal is the Blawx leg's, not L4's): _"in `name`: STRING-sorted
  field or argument (Blawx): `name` has a STRING-sorted field, parameter or result, and Blawx's
  ontology has no string attribute type — a declaration block offers boolean, number, date, time,
  datetime, duration, list and the declared categories, and nothing else…"_. The enum remedy was
  executed, not assumed: the same module with `name IS A PlayerName` emits
  `blawx_category(player_name).` and `blawx_attribute(player,name,player_name).` [E]. (Do not
  name the enum `Name`: `Name` and `name` both mangle to `name` and R3's injectivity check then
  refuses the module for an unrelated-looking reason [E].)
- **Admitted — a `STRING` literal inside a rule body, where no signature is `STRING`-sorted.** It
  mangles to an atom through the program-global string-atom table (`stringAtomTable`, R3
  mangling, collisions with declared names and with other literals both refused by name), and is
  usable for equality only. The probe is now a `LIST OF STRING` field, because that is what a
  surviving literal looks like once the three signature positions are closed: `RSList` returns
  Blawx's untyped `list` value type without inspecting its element sort, so
  `DECLARE Player HAS aliases IS A LIST OF STRING` with
  ``DECIDE `known as zebra` p IF p's aliases EQUALS LIST "zebra"``
  exports at exit 0 with `blawx_attribute(player,aliases,list).` and
  `Aliases = [zebra | []].`, and re-saves clean under the R12 harness —
  `blawx-fixpoint-harness: 3 checked, 0 failed` [E]. It is pinned as a unit test
  (`BlawxAssumeSpec`, "still admits a string LITERAL in a rule body, as an atom"), not as a
  corpus seed, because there is no _legal_ text in it. **The element sort of a list is not
  checked**, and this section does not claim it is: `LIST OF STRING` is the one place a `STRING`
  still reaches the ontology, under the `list` type.
- **Open, and measured rather than fixed:** the literal renders in the Blockly XML as
  `<block type="object_selector" … objectname="zebra">` with **zero** `object_declaration` blocks
  in the same document (`grep -c object_declaration` on the probe's `.blawx` → `0`) [E]. It
  fixpoints clean and reaches s(CASP) correctly, so nothing measurable from here is broken; what
  is untested is how a live Blawx instance's UI treats an object selector naming an undeclared
  object. Tracked as §11 **W2-followup**.

All string _computation_ is OUT, as before — the target has no string operations at all.

### 4.8 Lists, aggregates, recursion

The headline contrast with the Catala study: **recursion is admitted.** s(CASP) is a logic
programming language; `[H|T]` rules are its native idiom, and Blawx's own injected libraries
recurse (`aggregates.py` **[E]**). Policy (R9): structural recursion over lists — L4's
`CONSIDER … WHEN EMPTY … WHEN x FOLLOWED BY xs` — lowers to a two-clause `[H|T]` predicate
definition. The aggregation combinators (`sum`/`length`/`min`/`max`/average patterns over a
projection) are _recognised_ and lowered to the more idiomatic `findall` + `*_blawx_list`
goals, which also keeps them visible to Blawx's block palette. General `map`/`filter` with
literal lambdas lower to emitted auxiliary recursive predicates. Non-structural recursion
(no argument strictly decreasing on list structure) is OUT in v1 — s(CASP) is goal-directed
with loop detection but arithmetic-driven recursion can still diverge; widening this is a
measured follow-up, not a default. Higher-order arguments beyond recognised combinator
positions are OUT, as in both sibling bridges.

### 4.9 The envelope: L4's isomorphism becomes Blawx's section anchoring

Both languages stake their identity on isomorphism with the legal source, and here the
correspondence is _structural_, not just stylistic: Blawx's unit of encoding **is the statutory
section** — every rule carries `according_to(<section>, …)` attribution, and the UI renders one
canvas per section of the source text. The mapping (R4): L4 `§`/`§§` headers and inert
scaffolding synthesise the CLEAN `rule_text` (title line, numbered sections, indented
sub-provisions); each `@ref`-annotated L4 decision lands its rules in the workspace named after
the corresponding section eId; unanchored declarations land in `root_section`. `@nlg`
annotations — and, absent those, L4's already-sentence-like mixfix names (`` `eligible for
benefit` `` → postfix `"is eligible for benefit"`) — populate the `#pred` prefix/infix/postfix
NLG slots, which is what makes the justification trees and the scenario editor read as English
(R10). The result: the same provision-anchored discipline L4 enforces at authoring time arrives
in Blawx as per-section canvases with per-section attributions — the isomorphism _transfers_
rather than being re-derived.

### 4.10 Tests

Every `#EVAL`/`#ASSERT` over an exported decision becomes a `BlawxTest`: the record-literal
argument flattens into category/attribute facts in the test workspace (facts, **not** the
`fact_scenario` JSON channel — no shipped example uses `fact_scenario`, and its translator
carries the float/timezone/duration-crash landmines of §2 **[E]**); the query is
`?- f(subject, Result).` on its own last line. The harness (R11) compares the run endpoint's
`Answers[].Variables` against L4's own evaluator — the oracle is L4, exactly as
`roundtrip_check.py` does for OpenFisca. Separately, one **interview test** per module declares
the exported decision's input predicates `#abducible`, which is what powers Blawx's hypothetical
reasoning and "Relevant Statements" — L4's `ASSUME`d inputs land there naturally.

### 4.11 Tooling mirrors

Independently evolved pairs, evidence the two projects occupy one niche: justification trees ↔
ladder/`#EVALTRACE`; scenario explorer/interview ↔ question-ordering wizard; per-rule REST API ↔
`jl4-service`; `#abducible` ↔ (no L4 counterpart — a genuine gap Blawx exposes); CLEAN/AKN
section structure ↔ `§`/`@ref` provenance; `false :-` constraints ↔ `#CHECK`. The transpiler
makes each Blawx tool a consumer of L4 sources — and each mirror is a candidate future L4
feature with working prior art.

## 5. What does not map

### 5.1 Forward losses (L4 → Blawx)

Rejected with named diagnostics, per the OpenFisca `LowerError` discipline (all errors
accumulated, `Lower.hs:76-79` **[E]**):

- **Regulative layer.** No obligation lifecycle, party, breach, or residuation exists in the
  target. The nearest machinery — `blawx_becomes`/`blawx_as_of` fluents — models truth changing
  over time, not obligations discharging; encoding deontics as fluent predicates would be a
  simulation, not a mapping. OUT, with one earmark: a future _deontic-verdict_ projection
  (which party breached, when) could land as ordinary Blawx predicates if a corpus demands it.
- **Temporal pins.** `EVAL … UNDER RULES EFFECTIVE AT` has no counterpart; Blawx's event layer
  is _fact_-time, not _rule_-version-time. Workaround as in the Catala study: emit one RuleDoc
  per version snapshot. OUT in v1.
- **Effects/ledger.** `FETCH`/`POST`/`ENV`/`Record`/`ReadCell` — the target is pure. OUT.
- **`TYPICALLY`.** Blawx has no caller-overridable default machinery (contrast Catala's
  `context`, which operationalised it). Dropped with a lowering note in the emitted header.
- **Strings-as-computation** (§4.7), **payload enums** (§4.1), **higher-order and
  non-structural recursion** (§4.8).

### 5.2 Reverse direction (Blawx → L4): feasibility assessment

Requested as a goal, not a footnote (Meng, 2026-08-16). Verdict: **feasible for a substantial,
well-delimited fragment — roughly the fragment Blawx's own shipped corpus inhabits** — with the
block-level IR of R12 doing double duty as the pivot. Assessed construct by construct:

**What lifts cleanly.**

- **Ontology → `DECLARE`.** Categories with their typed attributes reassemble into L4 records
  (category → record type; attributes → fields; boolean attributes → `BOOLEAN` fields;
  category-typed attributes → record-typed fields). Declared objects → record values.
  Relationships → `ASSUME`d predicates or list-of-record fact tables.
- **Rules → decisions.** A stratified, ground-queried Blawx predicate defined by _n_ rules
  lifts to one L4 decision whose body is the _n_-way `OR` of the rule bodies (the inverse of
  §4.3's DNF split); goal conjunctions become `AND`; `blawx_comparison` becomes the L4
  comparison; `Var is Expr` inverts ANF back into nested expressions. The defeasibility triple
  is _mechanical wrapping_ and unwinds mechanically.
- **Defeat → explicit booleans.** `overrules`/`blawx_defeated` compiles away by unfolding: a
  rule defeated by stronger sections becomes `… AND NOT (<defeating bodies>)` — the same
  flattening Catala's own compiler performs on default terms, and the Blawx triple is _already_
  defeat-as-NAF, so the unfolding is syntactic. The priority _structure_ is lost as structure —
  it lands as a `@ref`-annotated comment trail until `SUBJECT-TO-NOTWITHSTANDING` gives L4 a
  native receiving surface (that spec gains a second concrete foreign customer here, after
  Catala's exception DAG).
- **Three-valuedness → `MAYBE BOOLEAN`.** The landing zone already exists:
  `jl4-core/libraries/negation-as-failure.l4` models exactly Blawx's three states
  (`JUST TRUE`/`JUST FALSE`/`NOTHING`) with `holds`/`naf`/`presumed` combinators **[E]** —
  `not p` lifts to `naf`, `-p` to `holds`-of-the-negative, `#abducible` to `NOTHING`-valued
  inputs surfaced as wizard questions.
- **CLEAN → the literate envelope.** `rule_text` parses (it is a _format_, with a published
  grammar) into `§` headers and inert scaffolding; `according_to` attributions become `@ref`.
  The isomorphism survives the round trip in both directions — the strongest structural
  argument that this bridge, uniquely among our backends, can be two-way.

**What does not lift.**

- **CLP constraint reasoning over unbound variables** (answers with `Residuals`): L4 evaluates;
  it does not solve. Queries requiring constraint answers are OUT; ground-query programs are
  unaffected.
- **Unstratified negation / multiple stable models**: L4 is deterministic. Programs whose
  meaning depends on model choice are OUT (none of the 15 shipped examples do this **[E]**).
  The check is `L4.Blawx.Lift`'s `blawx-lift/unstratified`, and it runs over the program the
  lift **emits**, not over the rules it read — _every_ negation in the output is introduced by
  the unfolding (`AND NOT <defeated>`, the applicability `naf`), so a scan over
  `attributed_rule` bodies alone cannot see it and was measurably inert on bird
  (2026-08-19; §8.14's REVIEWED block, finding 1). Adding a second `overrules` to bird so two
  sections defeat each other is refused by name.
- **The event layer** (`blawx_becomes` fluents): closest L4 relatives are the state ledger and
  the bitemporal axis, neither a semantic match today. Deferred, not refused.
- **Relational non-determinism**: a query with multiple answer substitutions lifts only under
  finite-domain enumeration (answers = filter over declared objects). RESTRICTED.
- **Unsatisfiability as the expected result**: `logical_constraints.yaml`'s tests pass when the
  program has _no_ stable model, which a `false :- …` constraint is written to force. L4
  evaluation is total and has no "no model" answer, so a workspace-level constraint is OUT.
  (Found at design time by the P5 scout, confirmed by measurement 2026-08-19 — the document
  parses and classifies cleanly, so this is a lift-time refusal, not a parse-time one.)

**Calibration against the shipped corpus — MEASURED 2026-08-19, and the earlier count was
wrong in both directions.** The claim retired here read "of Blawx's 15 examples, 13 sit inside
the liftable fragment; `life_act.yaml` … and the `Residuals`-dependent corner of
`numerical_constraints.yaml` sit outside". Three separate numbers were being conflated, and the
measurement separates them (full table: `p5-design/census-results.md`):

| layer                                         | count | which                                                                                                |
| --------------------------------------------- | ----: | ---------------------------------------------------------------------------------------------------- |
| examples with any blocks at all               | 14/15 | `wills_tutorial`'s only non-root workspace is the 61-char empty document                             |
| parse to a **block tree** (`L4.Blawx.Blocks`) | 14/14 | total over all 47 block types the corpus uses                                                        |
| classify to a **`BlawxDoc`** (`…Parse`)       | 10/15 | out: `covid_test` `life_act` `net30` `oasa` (date/event layer, ruling P5-1) and `r34` (three shapes) |
| **lift to L4** (`…Lift`, v1 fragment)         |  2/15 | `bird` (the defeat-layer target) and `wills_tutorial` (title + `§§`s, no decisions)                  |

The last row is the one that matters and it is much narrower than "roughly the fragment Blawx's
own shipped corpus inhabits". P5's lift models **one flat universe of objects under unary
predicates** — which is what the defeat layer needs and what `bird` is — so a document using
binary attributes (`age(A,Age)`), n-ary relations, arithmetic, or a query whose free variable is
value-sorted rather than object-sorted is refused **by name**, one diagnostic per construct.
Widening it is ordinary work (each refusal code is a to-do list entry), not a re-architecture;
the assessment above stands as a statement about the _approach_, not about what P5 shipped.
Ruled in R14; sequenced as P5; the `.blawx`-side _parser_ half is shared with R13's tier-2
harness, which must read run results anyway.

## 6. The v1 source fragment, precisely

`l4 blawx` accepts a type-checked module containing: `DECLARE` records and payload-free enums;
first-order, monomorphic `GIVEN`/`GIVETH`/`MEANS`/`DECIDE` decisions over
`BOOLEAN`/`NUMBER`/`DATE`/records/payload-free enums/`MAYBE`/lists, with ≤ 9 parameters;
`CONSIDER`/`BRANCH`/`IF`/`WHERE`/`UNLESS`; structural list recursion and the recognised
combinators; `STRING` literals in equality position; top-level `ASSUME`d inputs, subject to the
arity/category condition of §6.1; `@export`/`@desc`/`@ref`/`@nlg` annotations; `#EVAL`/`#ASSERT`.

Everything else — string computation, payload enums, non-structural recursion, function-typed
parameters, `DEONTIC`/`PARTY`, `#TRACE`, ledger/effect keywords, temporal pins, `TYPICALLY`
(dropped with a note, not an error) — is rejected with a `LowerError` naming the construct and
its source range, all errors in one batch, following `Cli/OpenFisca.hs`'s "cannot compile these
decisions" presentation **[E]**.

### 6.1 `ASSUME`d inputs: which ones, and in which spelling

Landed 2026-08-19; measured on this tree, not proposed.

A top-level `ASSUME` becomes an input predicate (`RPredKind`'s `RInput`, the second source
beside a stored record field) when a lowered clause references it. Four qualifications the
sentence above is too short to carry:

- **At total arity ≤ 2 it must be attribute-shaped** — exactly one parameter, category-sorted (a
  `DECLARE`d record, a payload-free enum, or an `ASSUME`d `TYPE`), plus at most a result. At that
  end Blawx's ontology is category-centric: a declaration block hangs off a subject, so neither a
  bare proposition nor a two-place input has an attribute block, a scenario-editor row or an XML
  image, which is precisely the R12 blank-row loss. Both of these are refused:

  ```
  ASSUME `the person is a body corporate` IS BOOLEAN              -- total arity 0

  GIVEN c IS A Consequence
        n IS A NUMBER
  ASSUME `severity exceeds` c n IS A BOOLEAN                      -- total arity 2
  ```

  The refusal is **by this leg**, under `input predicate with no category subject (Blawx)`, and
  _not_ by the relational middle end, which lowers them to ordinary `input …/n` predicates a
  swipl, ASP or Logical English leg can emit (#258 §2.5 — the middle end records, each leg
  rejects). Witnesses: `jl4/examples/relational/expected/assumed-nullary`,
  `jl4/examples/blawx/not-ok/zero-arity.l4`, `jl4/examples/blawx/not-ok/arity-two.l4`.

- **At total arity 3–10 there is no category condition at all**, and the diagnostic's name
  notwithstanding, none is applied. The input is declared as a **relationship**, whose arguments
  `blawxValueType` types one by one and does not require to be categories. MEASURED on this tree,
  an `ASSUME` of `scaled by` over two `NUMBER` parameters returning a `NUMBER` is accepted, emits
  `blawx_relationship(scaled_by,number,number,number).` with its full NLG and `:- dynamic` stack,
  and reaches the interview as `#abducible scaled_by(A,B,C).` with non-empty `xml_content` on
  every row. Above total arity 10 the relationship block ceiling refuses it by name (`LEArity`).
  So the rule is a floor with a hole in it: `classifyPred`
  (`jl4-core/src/L4/Blawx/Lower.hs`) tests `categoryOf` only in its two arity-1 arms. Pinned by
  `jl4-core/test/BlawxAssumeSpec.hs` ("an arity-3 input needs no category at all").

- **A _local_ `ASSUME` stays out** (`local ASSUME`): it is scoped to one definition, so there is
  no module-level name to declare and nothing for an interview to abduce.
- **Spelling matters, for a reason outside this leg.** The arrow form (an `ASSUME` whose declared
  type is a `FUNCTION FROM … TO …`) lowers correctly, but a module that `@export`s a `DECIDE`
  referencing it does not type-check at all: `L4.Export.validateExportInputs` raises
  `ExportFunctionTypeInput`, because `@export` appends referenced `ASSUME`s to the web app's
  parameter list and a function cannot cross a JSON boundary. Lowering is export-rooted, so such
  a module has no root. A corpus for this leg must therefore use the binder form instead, whose
  declared type is `BOOLEAN`:

  ```
  GIVEN p IS A Person
  ASSUME `is authorised` p IS A BOOLEAN
  ```

  Both forms are admitted by the lowering, so nothing moves if that export rule is later
  relaxed. This is why `jl4/examples/legal/anti-social.l4` — written entirely in the arrow form
  — cannot be used as a Blawx seed as written.

## 7. Architecture

Mirror the OpenFisca triple under `jl4-core/src/L4/Blawx/` (registered in
`jl4-core.cabal` `exposed-modules`, as `L4.OpenFisca.*` are at `jl4-core.cabal:151-153` **[E]**):

- **`IR.hs`** — a **block-level** IR: `BlawxDoc` (ruledoc name, CLEAN text, workspaces, tests);
  a workspace is a list of block trees mirroring Blawx's block inventory
  (`BDeclareCategory`, `BDeclareAttribute`, `BAttributedRule`, `BFact`, `BQuery`,
  `BAbducible`, goal nodes…). The IR models _blocks_, not s(CASP), because blocks are the
  only representation from which **both** wire formats derive (R12) — and the only pivot the
  import direction can share (R14).
- **`Lower.hs`** — thin by design: `L4.Relational.Lower` (#258 R0) produces the `RelProgram`;
  `L4.Blawx.Lower` classifies it into a `BlawxDoc` (R2), keyed on
  `L4.Export.getExportedFunctions` (`Export.hs:115` **[E]**), reusing the OpenFisca error
  shape, `Unique`-keyed environment, and collision-checking discipline
  (`Lower.hs:187-197,754-827` **[E]**). Under the R2 contingency (#258 unlanded), the minimal
  ANF/guard-prefix subset lives here temporarily, shaped for extraction.
- **`Emit.hs`** — two renderers off one IR: `renderScasp` (byte-exact per R10/R12 against
  `scasp_generator.js`) and `renderXml` (P3); plus `renderBlawxYaml` assembling the
  import-shaped fixture stream (R1). Line-oriented `Text`, not a pretty-printer, for
  golden-stability — the OpenFisca emit's stated rationale (`Emit.hs:1-6` **[E]**).
- **CLI** — `l4 blawx FILE [-o FILE] [--scasp]` in `jl4/app/L4/Cli/Blawx.hs`; `--scasp` emits
  the raw concatenated s(CASP) (headless debugging; tier-1 harness input). Four registration
  touch points in `jl4/app/Main.hs`, exactly as OpenFisca's (`Main.hs:34,54,91-93,136` **[E]**).
  Two coordination notes: the verb shape ultimately belongs to #258's LP-R11 (one
  `l4 relational --target` verb vs per-target verbs; natural4's ~30-mode sprawl is the
  cautionary precedent) — this spec proposes `l4 blawx` in the manner of the existing
  exporters and defers to that ruling. And three bridge efforts (Blawx, Catala, docassemble)
  will each touch `Main.hs` and the cabal module lists: spec PRs stay docs-only
  (conflict-free); implementation PRs sequence through the merge queue.
- **Tests** — `describe "l4 blawx"` in `jl4/tests-cli/Main.hs` beside the OpenFisca block
  (`Main.hs:2331` **[E]**): one `expectGolden` per example under `jl4/examples/blawx/` with
  goldens in `expected/`, `expectFail` fixtures under `not-ok/`, one structural smoke test, one
  typecheck-failure case, one `--help` listing assertion.
- **Import (P5)** — `L4.Blawx.Parse` (`.blawx` YAML + Blockly XML → the same IR) and
  `L4.Blawx.Lift` (IR → L4 source text), surfaced as `l4 blawx --import FILE` (ruled, R14).

## 8. Rulings

House template: evidence → proposal → cost → the case against → what it does not decide.

### 8.1 R1 — primary artifact: the `.blawx` fixture YAML, import-shaped

**Evidence.** Export/import format and pk/owner remapping verified at `views.py:102-155`
**[E]**; `loaddata` does _not_ remap and is collision-prone (INSTALL.md **[E]**); derived
fields recomputed on save (`models.py:35-39` **[E]**). **Proposal.** Emit one `.blawx` file:
one `blawx.ruledoc` first (placeholder pk, `rule_text` per R4, `owner` placeholder — remapped
on import), then workspaces, then tests; omit `akoma_ntoso`/`navtree`/`rule_slug`; `\n`
newlines; no trailing newline in encodings (matches stored values **[E]**). Target `/import/`,
never `loaddata`. `--scasp` secondary output for headless work. **Cost.** YAML string-encoding
of two embedded languages (XML + Prolog) is fiddly; goldens are large. **Against.** Emitting
raw s(CASP) only would be far simpler — but it dies on first UI save, is invisible on canvas,
and forfeits the entire editor/community story; the YAML _is_ the product. **Not decided.**
Whether to also emit a per-workspace `.pl` debug dump alongside the golden.

**ANSWERED 2026-08-18 (Meng).** As proposed. The open item is decided: emit the raw concatenated s(CASP) as a `.pl` file alongside each `.blawx`.

### 8.2 R2 — relationalization is the shared middle-end's job; the Blawx `Lower` classifies

**Evidence.** PR #258's `L4.Relational` design (ANF + output argument, materialised guard
prefixes because clause order is not semantics, stratification check, defunctionalised
prelude combinators); this spec's §4.2–4.4 arrived at the same scheme independently before
#258 was known to it — convergence that is evidence for the scheme, and a warning against
building it twice. Blawx's own idiom for computed values is exactly this shape
(`list_demo.yaml` **[E]**); conclusion flattening and bridge-rule dedup make multi-rule
conclusions cheap (`scasp_generator.js:1168-1241`, `reasoner.py:496-516` **[E]**).
**Proposal.** The lowering half of this bridge is `L4.Relational.Lower` (#258 R0):
`Module Resolved → RelProgram`. `L4.Blawx.Lower` consumes the `RelProgram` and _classifies_:
predicates over the subject record → boolean/unary or value/binary attributes or
relationships (≤ 10 arguments); record types → **ontology declarations, deliberately
diverging from #258 §2.3's functor-term record encoding** — functor terms would execute but
be invisible to the scenario editor, ontology API and NLG, forfeiting §1's reasons 1–3; the
Blawx target _definitionally_ wants the predicate-per-field representation; clauses →
`attributed_rule` triples in their R4 sections; aggregate-shaped auxiliary predicates → the
`findall` + `*_blawx_list` peephole (target idiom, palette visibility); `WHERE` → auxiliary
predicates; DNF split for `OR` up to a fixed threshold, else auxiliary predicates; optional
`--check-functional` emits the functionality constraint per value decision. **Contingency:**
if this bridge ships before #258's R0 lands, `L4.Blawx.Lower` implements the minimal
ANF/guard-prefix subset privately but _shaped for extraction_ — same IR boundary — so the
refactor onto `L4.Relational` is mechanical, and #258's census gains the Blawx fragment as a
second consumer requirement. **Cost.** Cross-spec coordination, and a dependency on a spec
that is itself unlanded. **Against.** A private, self-contained lowering ships without
waiting — and re-derives ANF, stratification and guard-prefix semantics that three sibling
backends then re-derive again; natural4's five independent LP transpilers with no shared
middle-end are the documented wreck (#258 §8.3). **Not decided.** Whether the `findall`
peephole and the DNF threshold live in the middle-end (both are target-agnostic) or the
Blawx emitter; whether functionality constraints default on.

**ANSWERED 2026-08-18 (Meng).** The Blawx work _drives_ the middle-end: `L4.Relational` is implemented now, under this programme, with this session coordinating — the contingency inverts (no private-then-extract). `findall`/aggregate recognition and DNF normalisation are attempted in the middle-end first, and move into the Blawx emitter only on demonstrated failure.

### 8.3 R3 — ontology projection and naming

**Evidence.** Value types and declaration shapes (`scasp_generator.js:927-1156` **[E]**); name
validation `^[a-z]\w*$`, not ending `_\d+`, silently auto-rewritten by the UI since v1.6.17
(`blawx-blocks.js:5215-5250` **[E]**); OpenFisca's injective-mangling precedent
(`pyIdent`/`checkCollisions`, `Lower.hs:754-827` **[E]**). **Proposal.** Subject records →
categories; fields → attributes per §4.1; payload-free enums → category + objects; mangle L4
names (mixfix, backticks, Unicode) to conforming snake*case atoms with an injectivity check
that rejects collisions, reserving Blawx's library predicate names
(`holds`, `according_to`, `blawx**`, `date_compare`, …) and Prolog keywords. **Cost.** Mangled
names lose L4's mixfix elegance in the *predicate\* position (recovered in the NLG position,
R10). **Against.** Quoted atoms would preserve names exactly — but the blocks do no quoting and
the UI validator would rewrite them on first edit, breaking the fixpoint. **Not decided.**
Whether `@desc` grows a `blawx name:` override side-channel (the `descKeyword` extension point,
`Lower.hs:446-455` **[E]**).

**ANSWERED 2026-08-18 (Meng).** No `@desc` name side-channel in v1 — it would confuse the other projections; revisit only if a consumer warrants it.

### 8.4 R4 — section anchoring: CLEAN `rule_text` synthesised from `§` structure and `@ref`

**Evidence.** Workspace names must equal AKN eIds + `_section` (`parse_an.py:45-65` **[E]**);
CLEAN grammar (title/sections/subsections/paragraphs/spans) from the in-app docs **[E]**;
`doc_selector` reads `section_reference` from its _mutation_ (`scasp_generator.js:264` **[E]**).
**Proposal.** Synthesise `rule_text` from the L4 module: title from the module/first `§`
header; one numbered CLEAN section per `§`-anchored decision cluster, section body = inert
scaffolding lines (or the `@ref` citation, or a stub); declarations → `root_section`; each
decision's rules → its section's workspace, attributed accordingly. Modules with no `§`
structure get one synthetic section per exported decision. eId prediction must match
`clean-law`'s parse — verified in the P2 round-trip, since `pre_save` re-derives eIds from our
`rule_text` and mismatched workspace names simply orphan the canvas. **Cost.** A second
CLEAN-shaped rendering of scaffolding text that already lives in L4 — regenerable, never
hand-edited, same mitigation as the Catala literate envelope. **Against.** Dumping everything
in `root_section` would sidestep eId prediction entirely — and forfeit the per-section
canvases and `according_to` attributions that make the output legible and defeat-addressable,
i.e. the isomorphism transfer of §4.9. **Not decided.** How `@ref` hierarchical citations map
to CLEAN sub-provision nesting (flat numbered sections may suffice for v1).

**ANSWERED 2026-08-18 (Meng).** Flat numbered sections for v1.

### 8.5 R5 — negation: complementary operators / classical `-p` on inputs / NAF on computed

**Evidence.** The three-valued semantics and scenario-translator behaviour (§2, §4.3 **[E]**);
the false-by-absence hazard of bare NAF on inputs. **Proposal.** As §4.3: comparisons negate by
operator complement; inputs by classical `-p`; computed decisions by `not p`. Disclose in the
emitted header: an input that is neither asserted, denied, nor abducible yields _no model_
(loud), never a silent false. **Cost.** Emitted negations are heterogeneous — three forms for
one L4 operator. **Against.** Uniform NAF everywhere would be simpler and matches L4's
closed-world reading under complete inputs — but "complete inputs" is exactly what the scenario
editor does not promise; its whole point is partial knowledge, and uniform NAF silently converts
"unanswered" into "no". Uniform `-p` everywhere fails the other way: computed predicates have no
negative rules, so every `NOT decision` would need emitted complement rules (see not-decided).
**Not decided.** Whether to emit per-decision CWA bridges (`-p(A) :- subject(A), not p(A).`)
so _negative queries_ about computed decisions answer classically; leaning yes-later, driven by
a corpus need.

_Cross-reference._ This ruling is the Blawx-emitter refinement of #258's negation column for
the s(CASP) leg and of its LP-R3 (eliminator-directed `MAYBE BOOLEAN` erasure): `holds`/`naf`/
`presumed` eliminators erase into `p` / `not p` per that table, and the input/computed split
above is additional, Blawx-specific epistemics driven by the scenario editor. The middle-end's
signed dependency graph and stratification check (its §2.5) is the soundness gate for every
`not` this ruling emits; non-stratified programs are rejected on this leg in v1 — s(CASP)
tolerates them, but the L4-oracle determinism obligation does not.

**ANSWERED 2026-08-18 (Meng).** As proposed; CWA bridges are yes-later, driven by a corpus need.

### 8.6 R6 — defeasibility: Mode A default; Mode B (`--idiomatic-defeat`) flag-gated

**Evidence.** Landed L4 is total — `UNLESS` is `AND NOT` sugar (`Parser.hs:1669` **[E]**);
Blawx's defeat machinery verified §2 **[E]**; the Catala study's Mode A/B discipline as
precedent. **Proposal.** v1 emits Mode A: plain rules, defeasible checkbox FALSE (the guard
would be vacuous — no defeat rules exist — and FALSE states the truth). Mode B, behind
`--idiomatic-defeat`: `UNLESS`-provisos and (when it lands) `SUBJECT TO`/`NOTWITHSTANDING`
structure emit as defeasible rules + negative-conclusion proviso rules + `overrules`, gated on
machine-checked equivalence per construct. **Cost.** Mode A output under-uses the target's
signature feature; justification trees say "and not (income > 100000)" rather than "…was
defeated by section 2". **Against.** Shipping Mode B first maximises demo value — and risks an
unverified semantic rewrite in a legal transpiler, the one bug class this project exists to
prevent. Same verdict as the Catala study, independently re-derived. **Not decided.** Whether
Mode B's equivalence check is truth-table enumeration (bounded inputs) or a query-diff harness
over the P2 corpus.

**ANSWERED 2026-08-18 (Meng).** Mode A ships first. Recorded plan: Mode B's equivalence gate is truth-table enumeration over bounded inputs — a decision to be revisited at the implementation juncture before Mode B work begins.

### 8.7 R7 — numbers: CLP comparisons; exactness is a measurement, not an assumption

**Evidence.** `blawx_comparison` over `#=`-family constraints (`passthrough.py:13-18` **[E]**);
arithmetic through Prolog `is` (`scasp_generator.js:550-557` **[E]**). First measurement,
2026-08-16 **[E]**: under SWI-Prolog 9.2.9 + the current s(CASP) pack on the reference
machine, `X is 1 / 3` inside a `scasp/2` goal binds `X = 1r3` — an exact rational, not a
float — so the feared float-division cliff does not appear on this toolchain; the P1
experiment must repeat this _inside Blawx's Docker image_ (its pinned SWI/scasp may differ)
before the exactness claim generalises. **Proposal.** Comparisons → `blawx_comparison`;
arithmetic → `is` goals; integral literals as integers; ship P1 with a numeric-fidelity
experiment (division, large integers, rational round-trip vs L4's exact evaluator) whose
results are recorded in the bridge doc _before_ any exactness claim is written — the
OpenFisca float32 lesson applied prospectively. Non-integral literals emit as decimals only if
the experiment shows exact behaviour; else rejected with a diagnostic. **Cost.** v1 may reject
some numeric programs OpenFisca accepts (with float caveats). **Against.** Assuming CLP(Q)
exactness from the s(CASP) literature would unblock more programs now — and is precisely the
kind of borrowed, unexecuted claim the house rules forbid writing down. **Not decided.**
Whether money-typed corpora get a cents-as-integers convention. Also noted: #258's s(CASP)
precedent (via natural4) maps arithmetic to constraint form (`IS → #=`), while Blawx's own
calculation block emits Prolog `is` — the P1 experiment measures both, and byte-fidelity to
the block idiom (R12) wins for emission unless the measurement shows `is` is lossy, in which
case the finding goes upstream to Lexpedite rather than into a divergent encoding.

**ANSWERED 2026-08-18 (Meng).** As proposed; the money convention is decided: cents as integers.

_P1 re-measurement (2026-08-18, L4.Blawx P1 build, recorded from
`p1-design/r7-stageC-rerun.txt` in the implementation worktree) **[E]**: `X is 1 / 3` inside
a `scasp/2` goal again binds `X = 1r3` — the exact-rational result reproduces on the local
toolchain (SWI-Prolog 9.2.9 + scasp pack). The crash also reproduces: a SECOND sequential
`scasp/2` call in the same process fails with an internal
`scasp_solve:stack_parents/3` error, so the tier-1 harness runs ONE query per swipl process
by design. The Docker-image repetition (Blawx's pinned SWI/scasp) remains outstanding and
still gates generalising the exactness claim — it is a P2 obligation._

_P2 discharge (2026-08-19) **[E]**: executed inside the running `blawx` container —
SWI-Prolog 9.1.14 x86_64-linux, the same engine `reasoner.py` drives via `swiplserver` —
`X is 1 / 3` inside a `scasp/2` goal binds `X = 1r3`. The exact-rational result holds on
both toolchains (local 9.2.9 arm64 and the container's pinned 9.1.14 amd64), so the
exactness claim now generalises to the deployment target. The gate is closed._

**Evidence.** The three timestamp landmines and the broken-block inventory, §2 **[E]**
(float-vs-integer non-unification executed by this pass). **Proposal.** As §4.6; never emit
via `fact_scenario`; never emit the broken predicate families; `blawx_now`/`blawx_today`
accepted as inputs (with the caveat that the server stamps them at _import time_ of the Django
module, `dates.py:3-6` **[E]**). Month/year arithmetic OUT in v1 (revisit with an emitted
day-arithmetic helper à la `daydate` if a corpus demands it). **Cost.** Corpora leaning on
L4's calendar arithmetic shrink to their day-granular subset. **Against.** Emitting a
serial-date helper library now would widen coverage — but Blawx's date story is the least
stable part of its target surface (a whole block family is broken at HEAD), and building on
the stable subset first is the OpenFisca sequencing lesson. **Not decided.** A timezone
annotation for corpora that need civil-time semantics.

**ANSWERED 2026-08-18 (Meng).** As proposed — and a dedicated requirements ledger is opened at `specs/todo/DATE-LIBRARY-SPEC.md`, recording the requirements this bridge emanates alongside the other backends', toward an eventual shared date library.

### 8.9 R9 — recursion: structural admitted, aggregates via `findall`, the rest deferred

**Evidence.** §4.8 **[E]**. **Proposal.** As titled; recognised combinator applications
(`sum`/`length`/`min`/`max`/average over projections) → `findall` + `*_blawx_list`;
`map`/`filter` with literal lambdas → auxiliary `[H|T]` predicates; structural `CONSIDER`
recursion → two-clause definitions; everything else self-referential → diagnostic naming the
cycle. **Cost.** The v1 boundary ("structural") needs a real check in `Lower`, not a vibe.
**Against.** Admitting all recursion and trusting s(CASP)'s loop detection would be more
generous — and turns nontermination into a runtime property of someone else's evaluator; the
conservative boundary keeps the promise "emitted programs terminate" checkable. **Not
decided.** Whether the aggregate recognisers and the OpenFisca `aggregation` recogniser share
an extraction (they pattern-match the same L4 idioms, `Lower.hs:240-263` **[E]**).

_Cross-reference._ #258's v1 fragment admits recursion natively and defers termination policy
to its LP-R7 (tabling / well-founded semantics); this spec's structural-only boundary is
deliberately narrower and should widen in step with LP-R7's ruling rather than independently.

**ANSWERED 2026-08-18 (Meng).** Share the recognisers with OpenFisca for now; the sharing is not load-bearing — later divergence may break loose without gymnastics to force continued sharing.

### 8.10 R10 — declaration emission is byte-exact against the current generator, quirks included

**Evidence.** The 44-line block anatomy (3 header + 21 `#pred` + 20 axioms), verified
byte-for-byte between `scasp_generator.js:927-1156` and `life_act.yaml` **[E]**; the stale
shipped examples (§ evidence-legend warning **[E]**); two generator asymmetry quirks in the
frame axioms (`scasp_generator.js:997-1006` and parallels **[E]**); `'` → `\'` escaping in
`#pred` strings only **[E]**. **Proposal.** Reproduce the current generator's output exactly —
including the two quirks and the indent leaks — with `life_act.yaml` + the generator source as
the normative pair; NLG strings from `@nlg`, else prettified mixfix names; emit the full
temporal axiom set even though v1 never asserts events, because the editor emits it on re-save
and the fixpoint (R12) fails otherwise. **Cost.** ~44 lines of boilerplate per declared
predicate; reproducing known-imperfect axioms feels wrong. **Against.** Emitting cleaner
axioms would repair the quirks — in _our_ output only, which the first UI re-save would then
"correct" back, making the fixpoint test permanently red and the diff noise permanent. Fidelity
to the target's actual conventions beats local aesthetics; upstream the fix to Blawx instead.
**Not decided.** Whether to PR the axiom quirks upstream to Lexpedite (independent of this
bridge; MIT-licensed, friendly project).

**ANSWERED 2026-08-18 (Meng).** As proposed, byte-exact quirks included. The upstream question is decided: fork Blawx under our org (via `gh`), construct the quirk-fix PR against the fork first, and send upstream only after the interop story has demonstrated value.

_Executed (2026-08-19): the quirk-fix PR is open as **legalese/blawx#1** (branch off pristine
upstream `main`, eight sites). Building it sharpened the diagnosis: the "Neither" frame
axioms' `blawx_becomes` goal contradicts their own `initially`/`ultimately`/uninterrupted
premises, so `blawx_during(bot, F, eot)` is underivable for exactly the fluent it
describes; the negative variant's missing sign-flip marks it a copy artifact. P1 also found
a **third** quirk beyond the two pinned here — the negative `blawx_defeated` `#pred` omits
"it is not the case that" in attribute/relationship variants but not the category variant —
byte-reproduced in our emitter, candidate for a second fork PR. The reference checkout
stays on the quirky branch so byte-comparisons remain against what upstream actually
generates._

_P3 found a **fourth** quirk, this one a data-corrupting UI race rather than an NLG
asymmetry: on the test editor page the workspace auto-load (an async XHR issued at script
evaluation) races `window.onload` populating `knownCategories`, so
`updateLocalCategories`'s `updateDropDownOptions` (blawx-blocks.js:5586-5615) validates
every `new_object_category` dropdown against an empty category list and snaps it to the
first option — twice: value → `none` → the first declared category. Measured in the tier-2
UI drive: a test asserting `basket(b1)` re-saved as `student(b1)`. Any Blawx user whose
test workspace asserts membership in a non-first-declared category silently loses data on
open-and-save. Our emitter is immune by construction — category-membership facts emit as
`object_category` + `category_selector` (a serialisable label, no dropdown; byte-identical
generated code) — and the race is a candidate for a third fork PR._

_Executed (2026-08-20): every remaining fork-PR candidate above and below is now an open PR
on the fork, each built and adversarially verified in fresh containers against pristine
upstream `main`: the `holds`→`-blawx_applies` bridge (§8.14 finding 1) as **legalese/blawx#2**
(one clause in `ldap.py` — the generator turned out to have no per-workspace standard block,
so the server-side home avoids any stored-workspace migration and leaves this emitter's
byte-fidelity contract untouched); the interview endpoint's `find_assumptions` crash (§10 P4)
as **legalese/blawx#3**; the category-dropdown race (quirk #4, above) as **legalese/blawx#4**;
and the negative `blawx_defeated` NLG asymmetry (quirk #3, above) as **legalese/blawx#5**.
Per R10, all four wait on the fork beside #1 until upstreaming to Lexpedite is warranted._

**Which generator (ruled 2026-09-02, §11 W9).** "The current generator" means the STOCK
`scasp_generator.js` of Lexpedite/blawx v1.6.22 (`origin/main` 6a717b1). The fork's generator
fixes (#1, #5) are not the target and are not carried by our instance; a fixpoint run must point
`BLAWX_CHECKOUT` at a stock-generator checkout.

### 8.11 R11 — tests: one BlawxTest per `#EVAL`/`#ASSERT`; the oracle is L4

**Evidence.** Test anatomy and query conventions §2 **[E]**; run-endpoint payload/response
shapes (`reasoner.py:470-634` **[E]**); `fact_scenario` landmines §2 **[E]**; OpenFisca
round-trip tiers **[E]**. **Proposal.** As §4.10; test names slugified to `[-a-zA-Z0-9_]+`
(URL-matched by Django's `slug` converter **[E]**); expected values live in the _harness_
(computed from L4 `#EVAL` at emission time), not in the `.blawx`; plus one `#abducible`
interview test per module. Document the three-tier claim ladder (golden / executed round-trip /
law-validated) verbatim from the OpenFisca doc. **Cost.** Numeric comparison must normalise
s(CASP)'s answer rendering against L4's before equality-checking. **Against.** Embedding
expected values in the `.blawx` as constraints would make tests self-contained in Blawx — but
then a bridge bug that shifts both actual and expected passes silently; keeping the oracle
outside the artifact preserves independence. **Not decided.** Whether `#ASSERT` failures also
emit as `false :-` constraints (runtime-checked both sides).

**ANSWERED 2026-08-18 (Meng).** As proposed — and yes: `#ASSERT`s additionally emit as `false :-` constraints, runtime-checked on both sides.

**Amended 2026-09-02 (§11 W1): the flattening is one object per _occurrence_, and that is now a
stated limit rather than an unstated one.** `skolemise` mints a constant per `(rqId, rvId)` — per
_place_ a record value appears in the query's arguments — so a `#EVAL` that passes the same
structural value twice emits two objects. Measured this session on
`jl4/examples/blawx/not-ok/record-identity.l4`: the query's Player becomes `p1` with
`throws(p1,rock)` while the game's first-player slot becomes `p2` with `throws(p2,rock)`; L4
evaluates the directive to `TRUE`, the tier-1 harness returns **no model** (`0/1 queries passed`,
`python3 etc/blawx-tier1-harness.py`). Keeping the oracle outside the artifact is what exposed it,
which is the "Against" paragraph above earning its keep. Two consequences, both landed with this
note: the emitter now refuses `EQUALS`/disequality whenever an operand's recovered sort contains a
declared record — bare, or under any nesting of `LIST OF` and `MAYBE` (§4.1) — so those particular
comparisons stop instead of answering differently, while an `ASSUME`d abstract category, whose
values are atoms on both sides, still unifies; and the honest fix — **hash-consing
structurally-equal record arguments so one distinct value mints one object** — is scoped and _not
built_, tracked at §11 W1. The refusal is a sort test, so it is only as wide as sort recovery: a
record-typed operand whose sort reaches the emitter as `RSOpaque` would still lower, and no such
case was constructed. Nothing about `#ASSERT`-as-constraint or the interview test changes.

### 8.12 R12 — dual representation from one block-level IR; the re-save fixpoint is the gate

**Evidence.** Code generation is browser-only; the server stores both representations verbatim
(`views.py:384`, `buttons.js:18-36` **[E]**); s(CASP)-only output is destroyed by the first UI
save; `xml_content` feeds the toolbox drawers and category dropdowns
(`drawers.js`, `blawx-blocks.js:5521-5535` **[E]**); the generator reads predicate names from
_mutation-restored properties_, not fields (`scasp_generator.js:264,683-699` **[E]**).
**Proposal.** One block-level IR; `renderScasp` in P1 (semantic core, headlessly testable);
`renderXml` in P3, emitting the verified conventions (namespace, mutation-before-field order,
`xmlns="http://www.w3.org/1999/xhtml"` on mutations, `<next>` chaining, unique ids, x/y
layout, mutations carrying predicate names; menu-cache attributes like `category_list` omitted
— the restorers synthesise them **[E]**). Acceptance for P3 is the **re-save fixpoint**: import,
open each workspace, save, and the server-stored `scasp_encoding` must equal ours
byte-for-byte. **Cost.** The XML renderer is a second full renderer, and layout (x/y) needs a
simple auto-placement scheme. **Against.** Shipping s(CASP)-only (skip XML forever) halves the
work — and produces artifacts that are un-editable, un-explorable in the toolbox, and
one-UI-save from data loss; "editable by the Blawx community" is the point of choosing this
target. **Not decided.** Auto-layout policy (single column suffices?); whether P1 goldens
already embed placeholder XML or empty strings.

**ANSWERED 2026-08-18 (Meng, delegated).** Delegated to the implementing session; the proposal stands as written — block-level IR, `renderScasp` in P1, `renderXml` in P3, re-save fixpoint as the gate. The delegated sub-decisions: single-column auto-layout; P1 goldens carry empty `xml_content` (consistent with the executed tier-2 smoke).

_R12 sub-decision — arithmetic image (2026-08-19, delegated, decided in the P3 build) **[E]**:
**adopt the generator's image.** P1 shipped one documented deviation — `renderScasp`
parenthesised minimally (`Tmp is 1000 + Bonus`) — because no shipped example exercises a
calculation line and either form runs. P3 pairs Blockly XML with every workspace, so the re-save
fixpoint now decides it. Read at Blawx `02eded1` (identical at HEAD `e36ac8f`, a CLAUDE.md-only
commit): `sCASP['math_operation']` (`scasp_generator.js:557-563`) emits
`"( " + left + " " + text2math(op) + " " + right + " )"` — **spaces immediately inside both
parens** — with operators `+ - * /` from `text2math` (`:69-82`); `sCASP['calculation']`
(`:550-555`) emits `variable + " is " + calculation`; `sCASP['number_value']` (`:512-516`) emits
the `field_number`'s JS number text (`blawx-blocks.js:924-938`: no `min`, no `precision`, so
negatives and decimals are admissible and integers carry no decimal point). Both operand sites
and the `is` wrapper call `valueToCode` with `ORDER_ATOMIC`, `math_operation` returns
`ORDER_ATOMIC`, and `ORDER_OVERRIDES` is empty (`:12-15`), so Blockly's ATOMIC-ATOMIC carve-out
suppresses wrapper parens: **exactly one paren layer per binary node**, e.g.
`Tmp is ( 1000 + Bonus )` and `X is ( ( A + B ) * C )`. `BANeg` has no block image — the
complete `output: "Number"` inventory is `number_value`, `math_operation` and the two
unimplemented `*_element` stubs that emit `'...'` and are commented out of the toolbox
(`toolbox.html:47,59`), and `math_operation`'s dropdown is `add`/`sub`/`mul`/`div` only
(`blawx-blocks.js:1102-1121`) — so a negated literal folds into a signed `number_value` field and
every other negation emits as `( 0 - e )`. Non-integral literals stay R7-gated in `Lower`; their
only block image would be `( num / den )`, never `num/den`, and the emitter's arithmetic path now
renders them that way (`Emit.renderArithNum`) while term position keeps `renderRational`'s
`num/den`, which has no block image at all and so is the thing lifting the gate must answer for
first. Three golden is-goals move (`sumlist.pl:96,130`, `benefit.pl:339`, and their `.blawx`
mirrors); the tier-1 harness re-runs 16/16 **[E]**, showing parenthesization is semantically
inert. Two findings for Lexpedite, recorded in `p3-design/arith-plan.md`:
`X is <bare variable>` is unrepresentable (`calculation`'s `calculation` input is
`check: "Number"`; all variable blocks are `output: "VARIABLE"`), and the `calculation` block is
absent from the toolbox in both editors, so a human cannot create one from the drawer even though
it deserialises and regenerates correctly._

Nothing in §8.7 (R7) changes: the cents-as-integers convention and the two executed
exact-rational measurements stand unaltered by this ruling.

_R12 sub-decision — what the XML renderer does when a slot has no structural image (2026-08-19,
delegated, decided in the P3 build) **[E]**. Four rulings, all forced by measurement against the
real restorers and the real generator:_

_**(1) The blank line goes between block RUNS, not between `bwStacks` entries.** Only the
declaration and fact blocks carry a `previousStatement`; `unattributed_constraint`, `assume`,
`attributed_rule` and `query` do not (`blawx-blocks.js:565-581, 1907-1923, 3107-3146, 235-250`),
so they can only be canvas roots, and `Generator.workspaceToCode` joins top-block outputs with
`'\n'` while each root's code already ends in one — every run boundary is a blank line.
`Lower.convertQuery` puts an `#ASSERT` constraint in the same stack as the scenario facts, so
`renderScasp` was emitting one blank line too few for `benefit blawxtest/q2` and `/q3` (measured:
stored 130 B / 7 lines vs regenerated 131 B / 8 lines). Fixed by moving the partition into
`L4.Blawx.IR.blockRuns` and having **both** renderers read it, so they cannot disagree again; the
latent cases (`BAbducible`, `BAttributedRule`, `BQuery` in a mixed stack) are closed by
construction. This is a change to `renderScasp` output — the only one outside arithmetic — and it
is the fixpoint correcting P1, not a new policy: two `.blawx` test rows gain one blank line each,
the four `.pl` dumps are byte-unchanged (no workspace stack mixes kinds), and the tier-1 harness
re-runs **16/16 [E]**._

_**(2) `attributes.js` is part of the load path, and an empty `attributetype` is not "no check".**
`setAttributeType` (`attributes.js:1-21`) is registered on `demoWorkspace` by both editor
templates (`blawx.html:168`, `test.html:164`) and fires on every `BLOCK_CREATE` with **no
`if (attributeType)` guard** — unlike `ATTRIBUTE_SELECTOR_MUTATOR_MIXIN.domToMutation`
(`mutators.js:165`), which is the only place the P3 design had looked. Since
`blawxTypeToBlocklyType("")` returns `'OBJECT'` (`mutators.js:18-20`) and `Connection.setCheck`
unplugs an already-connected incompatible child, the `attributetype=""` we were emitting tore the
`empty_list` / `head_tail` / `number_value` operands off **six** golden rows
(`scores/sec_5_section`, `sumlist/{sec_1_section, sec_3_section, q1, q2, q5}`), which then
regenerated `[X | Rest].` as a naked top-level statement and `running_total(,)` for the clause
that had lost both arguments **[E]**. Ruling: `attributetype` is now **derived from the operand
actually in the value slot** (declared type when it admits that operand, else `list`/`number`/
`object` by the term's Blockly output), and is never empty and never absent._

_**(3) A slot pinned to `[OBJECT,VARIABLE]` takes an `object_selector` surrogate, not a gap.**
Three inputs cannot be widened from XML at all: `attribute_selector`'s object slot (ruling 2 —
and `attributes.js` pins the mirror input the same way under `vo`, so swapping the argument order
does not help), `unary_attribute_selector`'s `first_element` (`blawx-blocks.js:3041-3048`, mutator
never calls `setCheck`, `mutators.js:181-195`) and `new_object_category`'s `object`. A list in one
of those — `running_total([],0)`, `all_positive([X|Rest])` — therefore has **no structural image
anywhere in the 127-block inventory** (`relationship_selector` starts at arity 3). The P3 build
had been shipping those rows with an empty `xml_content`, which is not a neutral omission: Blawx
draws a workspace only `if (output_object.xml_content)` (`buttons.js:441-447`) and Save writes
`sCASP.workspaceToCode(demoWorkspace)` straight back (`:22-24`), so **opening such a row and
saving deletes the rule** — the sharpest possible violation of the R12 exit criterion. Ruling:
emit an `object_selector` whose `object_name` label is the term's own s(CASP) text. Its output is
`OBJECT` so it survives every pin; its field is a `field_label_serializable` with no validator so
it round-trips verbatim; and its generator arm is `this.getFieldValue('object_name')`
(`scasp_generator.js:471-474`) so the regenerated bytes are exactly ours. What is lost is
editability of that subterm in the UI, and only that — a strictly better failure than a blank
canvas, and fail-safe, because a label is not editable and so cannot be silently corrupted. The
surrogate is used **only** where the structural image would be torn off: a list in a value slot
still gets real `head_tail` blocks._

_**(4) A blanked row is a compile-time diagnostic, and no golden may contain one.** What the
surrogate cannot rescue still yields an `XmlGap`, but the reason is no longer discarded:
`L4.Blawx.Emit.blawxXmlGaps` carries it out and `l4 blawx` prints one `WARNING no Blockly image`
line per gap to stderr, and `jl4/tests-cli` asserts for all four seeds that no row pairs an empty
`xml_content` with a non-empty `scasp_encoding` (and that the warning is absent). **After rulings
2 and 3 the corpus has zero gaps**: all 35 rows — 13 workspaces and 22 tests — carry XML.
Shape note: the renderer the brief names as the P3 deliverable, `renderXml :: BlawxDoc -> Text`,
is not what shipped and has been removed; the row-level values the YAML stores can only come from
a per-row renderer, so the module's surface is `renderDocXml :: BlawxDoc -> BlawxXml` (workspaces,
tests, gaps), and `L4.Blawx.IR`'s two-renderer contract now names it._

_**Status.** The headless fixpoint harness (`etc/blawx-fixpoint-harness.mjs`) is green on all four
goldens — **35 checked, 0 failed**, and again under `BLAWX_FIXPOINT_ISOLATE=1` (a fresh jsdom
realm per row) **[E]**. It was itself repaired in this build: it had omitted `attributes.js` and
the two listeners the templates register (`onCategoryChange`,
`updateRelationshipDeclaration` — `blawx.html:100-101`, `test.html:149-150`) on the false premise
that the UI-only files "contribute nothing to the generator", and Blockly drains its event queue
on a macrotask, so nothing fired inside a synchronous `domToWorkspace(); workspaceToCode()`. It
now boots the page globals, models `getAllWorkspaces` with the file's own workspace rows (what
the server would return) and awaits the queue. Headless remains the fast 99%, not the authority:
**the coordinator's tier-2 browser pass is still what marks §10 P3 EXECUTED**, and it must run in
the same timezone the harness pins (`TZ=UTC`), because date and datetime blocks encode through the
local-time `Date` constructor (`scasp_generator.js:528-535`, `:790-800`) — latent for this corpus,
which has no numeric date literals, and live for the next one that does._

**Instance for the re-save gate (ruled 2026-09-02, §11 W9).** The gate is run on an instance whose
generator is stock; since 2026-09-02 that is `legalese/blawx:edge` built from the fork's
`mengwong/main` with the generator fixes reverted (see W8 for the build pins).

### 8.13 R13 — validation harness: two tiers, optional-when-present, never a build dependency

**Evidence.** The repo's standing `validate-dmn.mjs` posture; SWI-Prolog 9.2.9 present locally,
s(CASP) pack absent **[E]**; Docker absent until 2026-08-16 (colima being provisioned to
`/Volumes/transcend` per Meng's constraint); Blawx is MIT-licensed **[E]**, so its injected
Prolog libraries (`passthrough.py`, `dates.py`, `aggregates.py`, `events.py` string content)
may be vendored into a test fixture with attribution. **Tier 1** (local, lightweight): `swipl`

- `pack_install(scasp)`; a harness that reassembles the `reasoner.py` load order — harness
  predicates, vendored libraries, our emitted `scasp_encoding`s, the test's, the dedup pass —
  and runs each test query, comparing bindings to L4-oracle values. **Tier 2** (Docker): run
  `lexpedite/blawx` (or an image built from the checkout), `POST /import/` the `.blawx`, hit the
  run endpoint per test, compare `Answers`. Both skip silently when their toolchain is absent;
  CI job optional and non-required. **Cost.** Tier 1 re-implements the reasoner's assembly and
  can drift from it; tier 2 needs Docker plumbing (session/CSRF or a published RuleDoc).
  **Against.** Requiring tier 2 in CI would catch wire-format regressions on every merge — and
  couple the merge queue to a foreign Docker image, which repo precedent forbids. **Not
  decided.** Whether tier-1 vendored libraries are pinned by checksum against the Blawx checkout
  to detect upstream drift.

**ANSWERED 2026-08-18 (Meng).** As proposed, minus the checksum pin: vendored libraries are not pinned in code — a loud provenance comment names the source file, the Blawx commit, and the drift risk instead.

### 8.14 R14 — import: the block IR is the pivot; lift the stratified ground fragment

**Evidence.** §5.2's construct-by-construct assessment **[E]**; 13 of 15 shipped examples
inside the fragment **[E]** — _as believed at proposal time; measured 2026-08-19 as 14/15 with
blocks, 10/15 classifying and **2/15 lifting**, see §5.2's calibration table, which retires the
count in both directions. Kept rather than deleted because the point of an Evidence block is to
record what the ruling was made on_; `negation-as-failure.l4` as the three-valued landing zone **[E]**;
XML is the canonical parse source (typed block trees) with `scasp_encoding` as a
cross-check — regenerate s(CASP) from parsed XML and diff against the stored encoding, reusing
R12's fidelity machinery in reverse to _detect_ stale or hand-edited encodings before lifting.
**Proposal.** P5 ships `L4.Blawx.Parse` + `L4.Blawx.Lift` for the fragment: ontology →
`DECLARE`; stratified ground rules → decisions (`OR`-of-bodies); defeat unfolded to explicit
booleans with `@ref` provenance comments; `not`/`-`/`#abducible` → `negation-as-failure`
combinators over `MAYBE BOOLEAN`; CLEAN → `§` + inert scaffolding + `@ref`; tests → `#EVAL`
with the _Blawx run result_ as the recorded expectation (each side oracles the other).
Round-trip property: `lift . emit = id` (modulo formatting) on the v1 export fragment —
testable from day one of P5 with no foreign toolchain at all. **Cost.** A parser for two
embedded formats; the lift must refuse gracefully on the OUT list (CLP residuals, unstratified
programs, event layer). **Against.** Parsing the s(CASP) directly (skip XML) looks simpler —
but s(CASP) has lost the block typing (which goals were attribute references vs. raw
predicates), is stale in real corpora (§ evidence-legend warning), and would duplicate exactly
the structure the XML already carries. **Not decided.** CLI surface (`l4 blawx --import` vs an
`l4 import` family); whether lifted defeat structure waits for
`SUBJECT-TO-NOTWITHSTANDING` to land as structure rather than comments.

**ANSWERED 2026-08-18 (Meng).** CLI surface: `l4 blawx --import`. And the dependency direction is settled: where lifted defeat structure needs a landed `SUBJECT TO`/`NOTWITHSTANDING`, the Blawx project drives that work incrementally rather than waiting on it.

**EXECUTED 2026-08-19 — both directions of the bird cross-check are green.**
`L4.Blawx.Xml` → `L4.Blawx.Blocks` → `L4.Blawx.Parse` → `L4.Blawx.Lift`, with the CLI surface
`l4 blawx --import FILE [-o out.l4]` as ruled, plus three additive flags: `--parse-only` (parse
and report, one `CENSUS` line to stdout), `--reemit` (write the `.blawx` regenerated from the
parsed blocks instead of the lifted L4) and, on the export path, `--roundtrip` (emit, parse
back, assert the IR and the bytes are unchanged).

- **`lift . emit = id`, parse half**: `--roundtrip` over all four P1/P3 seeds — structural IR
  equality modulo provenance and the stack/run distinction, _and_ byte-identical re-emission.
  Also over a hand-built document exercising every P5-1 extension constructor
  (`jl4-core-test/BlawxParseSpec`), because `L4.Blawx.Lower` constructs none of them.
- **bird, the L4 engine leg**: `jl4/examples/blawx/imported/bird.l4`, produced by the pipeline
  from upstream's own `bird.yaml` (109 blocks, 17 types, 8 workspaces, 4 tests; the stale-encoding
  warning of P5-2 fires on 8 of its 10 rows, as expected). `l4 check` clean; its four `#EVAL`s
  answer `LIST "pingu"`, `TRUE`, `TRUE`, `TRUE`.
- **bird, the Blawx engine leg**: `bird.blawx`, whose `scasp_encoding` `renderScasp` regenerated
  from the same parsed blocks, driven through `etc/blawx-tier1-harness.py` (one query per
  `swipl` process). **20/20** — the 16 export queries plus bird's 4 — so both engines agree on
  every bird query.
- **the re-save fixpoint on the re-emission**: `etc/blawx-fixpoint-harness.mjs` **10/10** rows
  byte-identical (2 empty workspaces skipped), through the real Blockly 10.1.3 restorers and the
  real generator. Every P1/P3 golden is unchanged by the IR extension (35/35 still green).

Two findings the execution produced, both recorded where they belong:

1. **The `holds` block is inert for `blawx_applies` in the shipped generator** — an upstream
   defect, not ours, and it is why the s(CASP) leg runs against a bridged program. bird's span
   workspace asserts `holds(sec_5__span_pingu_section,-blawx_applies,sec_5_section,pingu).` and
   **nothing consumes it**: `ldap.py` declares `#pred` NLG for `holds/4` and stops, the generator
   emits an `L(X) :- holds(S,L,X).` bridge only from an `attributed_rule`'s third clause and only
   for that rule's own section, and `reasoner.py` contains no occurrence of `holds` at all. So
   `-blawx_applies(sec_5_section,pingu)` is never derivable, the closed-world default succeeds,
   NBA 5 applies to pingu after all, and `pingu_with_jetpack_cant_fly` answers **no model** —
   contradicting its own pinned comment and s.5's own carve-out. The single missing clause is
   `-blawx_applies(S,X) :- holds(_Z,-blawx_applies,S,X).`; the harness adds it, names the finding
   in one place, and a control run without it reproduces the failure exactly (3/4, the fourth
   FAIL). The lift implements the intended semantics. File upstream beside `legalese/blawx#1`.
   _(Filed 2026-08-20 as legalese/blawx#2 — see the executed note in §8.10.)_
2. **The recorded expectation is the L4 engine's own answer, written by the pipeline** (`-- L4
oracle ==> …`, spliced after each `#EVAL` by re-running the module through the evaluator), and
   the design's second herald `-- Blawx <test> ==>` is deliberately **not** emitted: the lift
   cannot know what s(CASP) answered, and a line it cannot check is prose that drifts. The
   cross-engine claim lives in the harness, which is the R11 posture — the oracle stays outside
   the artifact and the comparison is made by something that ran both sides.

**REVIEWED 2026-08-19 — nine findings dispositioned; four changed the answer the bridge gives.**
The bird artifact was regenerated and every gate above re-run
(`jl4-core-test` 368, `l4-cli-test` 276, `jl4-test` 2 581, all suites green; tier-1 **20/20**;
fixpoint **45/45**, see below; census unchanged). What moved:

1. **The stratification guard was inert on bird, the document it was written for.** It scanned
   `attributed_rule` bodies only, and _every negation the lift emits is introduced by the lift_ —
   the `AND NOT <defeated>` conjunct and the applicability `naf` appear in no rule body. Measured:
   bird's edge set was six edges, all positive, so the guard was structurally incapable of firing.
   The scan now runs over the program the lift **emits** (`according_to`/`holds`/`blawx_defeated`/
   `blawx_applies` are nodes; every paragraph builder contributes its edges), and the goal walk is
   total rather than falling through a catch-all that silently dropped `BGApplies`, `BGHolds` and
   `BGAccordingTo` — the three constructors ruling P5-1 added. Witness: bird plus one mirror
   `overrules` is refused `blawx-lift/unstratified` naming `holds(sec_3_section,-flies)` and
   `holds(sec_4_section,flies)`; before, it emitted a module that type-checks and diverges. Pinned
   in `jl4-core-test/BlawxLiftSpec`, both the even loop and the odd one.
2. **Test canvases were never vetted.** `testPara` consumes a positive unary ground fact and a
   query; everything else on the canvas was dropped with no diagnostic, while workspace canvases
   got a full refusal pass. Not hypothetical: 11 tests across 8 shipped examples declare their own
   objects, 3 carry `assume`, and **2 assert a negative scenario fact** — which would have made the
   `#EVAL` answer a question the Blawx test did not ask. Now refused by name
   (`test-block`, `scenario-undeclared`).
3. **Two halves of the lift disagreed about who exists.** `membersOf` counted atoms introduced by
   ground facts; `all objects` did not, so an existential `#EVAL` — the exact shape
   `?- p(A).` lifts to — ranged over a strictly smaller universe than s(CASP) enumerates. The
   universe is now the union, as the code comment claiming exactness already asserted.
4. **The fact-channel asymmetry was unsound, not merely undocumented.** A concluded _category_ got
   no `<p> fact` field while a concluded _attribute_ did; a scenario asserting `bird(x).` therefore
   had nowhere to land and `recordFields` dropped it silently. Every declared predicate now gets a
   channel, which is what Blawx's own `:- dynamic p/1.` means.
5. **Ruling P5-4 was honoured for tests only.** 6 of the corpus's 18 `<comment>` elements sit on
   `blawx.workspace` rows (`oasa` ×3, `r34` ×3) and were computed and thrown away at the
   `MkBWorkspace` call site. `BWorkspace` gained `bwComment`, import-only and imaged by neither
   renderer exactly as `btComment` is; the lift places it under its section's `§§` (root under
   `§§ Ontology`) and **warns** where a workspace path has no `§`. A blank line inside a comment
   now renders as a bare `--` rather than `"-- "` with trailing whitespace.
6. **The tier-1 harness inspected only s(CASP)'s first model** — an if-then-else around `scasp/2`
   — so a `LIST` oracle could pass while the engines disagreed. It now enumerates
   (`findall` + `sort`) and compares sets. That change immediately produced **upstream finding 3**
   below.
7. **The fixpoint harness's default input list was `expected/` only**, so a bare run reported
   "35 checked, 0 failed" without ever touching the import half. It now defaults to `expected/`
   **and** `imported/`: **45/45**, 2 empty workspaces skipped.
8. **bird.l4 now carries its own disclosure of finding 1 above**, emitted from `appliesParas` so
   it cannot drift out of the artifact: a reader who takes the file to the shipped Blawx and runs
   the same query gets a different answer, and until now only the harness said so.

**Upstream finding 3 (s(CASP) itself, not Blawx and not our emitter).** Enumeration found one
query on which s(CASP) reports an answer L4 does not: `benefit/q1` asks `benefit_amount(a1,X)` and
gets both `1000` (right) and `0`. It is not our clause: put that clause's own body to the same
program as a query and s(CASP) refuses it —
`?- applicant(a1), not eligible_for_benefit(a1).` has **0** models while
`?- according_to(sec_2_section,benefit_amount,a1,0).`, whose body is exactly that conjunction, has
**1**. The model it returns says why: it contains `age(a1,70)` and `not age(a1,_)` together, and
`-is_veteran(a1)` beside `not -is_veteran(_)` — the dual of a body with a free variable over an
unbounded domain, satisfied by an unbound witness rather than checked over the ground instances.
The harness keeps the agreement claim (the L4 oracle must be among s(CASP)'s answers) and **pins
the surplus** in one named table (`KNOWN_SURPLUS`), so a divergence that grows, shrinks or wanders
fails the run; a control run with the pin removed reproduces the FAIL exactly.

## 9. Non-goals (v1)

Deontic, temporal-pin, and effect/ledger layers (§5.1); payload enums; string computation;
calendar-month date arithmetic; `TYPICALLY` operationalisation (no target machinery); the
event/fluent layer in either direction; Mode B beyond its flag (R6); import beyond the R14
fragment; any change to L4 language semantics; upstreaming fixes to Blawx (tracked as an
earmark in R10, not a deliverable).

## 10. Acceptance and sequencing

- **P1 — emit + execute.** `IR`/`Lower`/`Emit(renderScasp, renderBlawxYaml)` + CLI (lowering
  via #258's R0 middle-end, or the R2 contingency shaped for extraction); seed corpus
  (the worked example of Appendix A; a mortality-parity minimal case; an aggregation case; a
  structural-recursion case — the construct Catala must reject); goldens wired in `tests-cli`;
  tier-1 harness green (raw s(CASP) queries answer L4-oracle values); the R7 numeric-fidelity
  experiment run and recorded. Exit: every emitted golden executes correctly under tier 1.

  _**EXECUTED 2026-08-18** (legalese/l4-ide#273, on the #272 middle-end): tier-1 harness
  16/16 queries answer their L4-oracle values; declaration blocks byte-identical to
  `life_act.yaml` after name/NLG substitution; a third generator quirk (negative
  `blawx_defeated` `#pred` NLG asymmetry between category and attribute/relationship
  variants) found and byte-reproduced alongside the two R10 pinned; every synthesized
  `rule_text` validated through `clean-law`'s actual parser, which caught that
  lowercase-initial titles are unimportable (titles are recased). One documented deviation:
  minimal-paren arithmetic vs the generator's always-parenthesized image — ruled at P3,
  where `renderXml` makes UI re-saves possible._

- **P2 — Blawx round-trip.** Docker instance up (images on `/Volumes/transcend` per
  environment constraint); `/import/` accepts every golden; run endpoint agrees with L4 on the
  full `#EVAL` population; eId prediction verified against `clean-law` (R4). Exit: tier-2 green
  on the seed corpus. _A single-example smoke of this whole phase was already executed during
  the design pass (Appendix A): import 302, answer `Amount = 1000` with justification tree,
  eIds as predicted — so P2's risk is volume, not mechanism._

  _**EXECUTED 2026-08-19, GREEN AT VOLUME**: all four P1 goldens accepted by `/import/`
  (HTTP 302); run endpoint **16/16** on the full `#EVAL`/`#ASSERT` population — every
  binding (1000, 1250, 240, 90, 80, 35, 6, 0, 7, 16) and every model/no-model verdict
  matches the L4 oracle; server-regenerated Akoma Ntoso carries exactly the predicted eIds
  for all **12** sections across the four modules, each matching its emitted workspace name.
  Interview tests confirm the abductive path (benefit 2 answers, mortality 1); the scores
  interview times out at 120 s — an open abductive query over an aggregate is an unbounded
  search, a property of the query shape, not a bridge defect. The R7 in-container
  measurement also ran (see §8.7). Driver: `p2-roundtrip.py`, session scratchpad._

- **P3 — editability.** `renderXml`; re-save fixpoint holds for every seed workspace (R12).
  Exit: byte-identical `scasp_encoding` after UI open-and-save of every workspace.

  _**EXECUTED 2026-08-19, FIXPOINT HOLDS AT FULL WIDTH**: `L4.Blawx.EmitXml` pairs every
  row — all **35** workspaces and tests across the four seeds carry Blockly XML, zero
  gaps (a tests-cli assertion now forbids empty `xml_content` beside non-empty
  `scasp_encoding`, and `l4 blawx` warns on stderr if a construct ever gaps again). The
  arithmetic image adopted the generator's `( l op r )` form (§8.12 sub-decision) and the
  stack→canvas-root partition moved into the IR (`BRun`) so both renderers read one
  boundary. Verified on four independent instruments: tier-1 harness **16/16** oracle
  answers; the headless fixpoint harness (`etc/blawx-fixpoint-harness.mjs` — real vendored
  Blockly 10.1.3 + restorers + generator under jsdom, attributes.js loaded, event queue
  drained) **35/35** byte-identical; the authoritative tier-2 drive — import into the
  container, then every row opened and saved through the REAL editor pages in Chrome
  (puppeteer calling the pages' own `load_section_workspace`/`updateWorkspace`/
  `updateBlawxTest`) — **35/35** byte-identical stored encodings; and the run endpoint
  re-answering **16/16** on the post-save state. The UI drive caught what headless could
  not: quirk #4 (§8.10), the test-page category-dropdown race, fixed on our side by the
  `object_category` + `category_selector` image. Drivers: `drive-saves.mjs` +
  `compare.py`, session scratchpad (`tier2-fixpoint/`)._

- **P4 — the showcase.** A statute corpus (BNA §1 or a Housing Act ground — both have
  `§`-anchored L4 encodings) emitted with full NLG; published on a Blawx instance; the
  scenario explorer runs an interview and every answer carries a justification tree with
  citations back to sections. Exit: a screen-recorded interview over transpiled L4.

  _**EXECUTED 2026-08-19 (engineering exit; recording owed)**, as a three-rung ladder per
  Meng's steer (start with the cases the jl4-web deployment ships by default): **P4a**
  `rodents.l4` (the classic isomorphism demo, citations lifted verbatim from the policy
  sentence at `jl4/experiments/classic/vermin_and_rodent.l4:14`); **P4b** the
  ASSUME→RInput widening — top-level `ASSUME`d names lower as input predicates, measured
  additive (every pre-existing relational and Blawx golden byte-stable, full suites
  green) — unlocking `antisocial.l4` and `alcohol.l4`, each oracle-anchored by a
  GIVEN-record semantic twin that emits **byte-identical s(CASP)** (only the provenance
  comment differs), and discharging P1's `#abducible`-interview earmark (a module with
  zero `DECLARE`s now gets an interview; abduction confirmed live in the container: 2 and
  3 answers); **P4c** `housing-grounds.l4` — Housing Act 1988 Sch 2 grounds 8, 13, 15
  and 17 inlined into one 727-line module (an earlier draft of this note said 695;
  `wc -l` on the committed file says 727 and always has), 14 `@export` citations, 49 directives all
  oracle-verified against `l4 run` (0 mismatches). The BNA was declined for P4: its three
  `DATE` fields are fatal in v1 and pre-resolving them would delete the statute's actual
  legal content (the commencement boundary). Verification at full width: tier-1
  **150/150**; headless fixpoint **181/181** rows; the authoritative tier-2 UI drive over
  all six new modules — every one of their **146** workspaces and tests opened and saved
  through the real editor pages — **146/146 byte-identical**; run-endpoint and interview
  spot checks green. Found en route: CLEAN's title grammar rejects an **em dash in the
  act title** (`ParseException` in `generate_akn` during `RuleDoc.save()` → import 500;
  hyphens/commas/parens fine, body text unaffected) — the emitter's title channel now
  maps em/en dashes to a hyphen, beside P1's recasing guard — and a second, subtler
  member of the same family: CLEAN gives a **mid-body em dash structural meaning**
  (legislative sub-paragraph introduction), so a section text containing one silently
  swallowed every following section — the housing AKN carried ONLY `sec_1` and every
  later citation link (`/rule/sec_N/`) 500'd. The section-text channel now maps dashes
  too; re-measured: AKN eIds ↔ workspace names agree **6/6 modules** (housing
  `sec_1`…`sec_14`). The **screen-recorded run is delivered**: Ground 8's q6 (the
  three-months boundary, monthly rent 800, arrears 2400/3200) driven through the real
  test editor — transpiled blocks on the canvas, Run, and the justification tree citing
  section 1 and section 4 with "2400 is greater than or equal to 2400" as the threshold
  step (`housing-q6-run.webm`, session scratchpad). Two upstream limits found while
  aiming for the scenario-explorer page and worth fork PRs: the interview endpoint's
  `find_assumptions` crashes on classical negation in the answer tree
  (`reasoner.py:1457`, `TypeError` on a string node — fires for our R5 `-p` encodings
  and for `type:"false"` scenario facts), and the same endpoint's abductive search
  grows unusable when input predicates are left unpinned (measured: rodents 2 pinned
  facts >180 s vs 3 pruning facts 11.8 s; housing grounded >200 s). The test editor's
  `run/` path — which the recording uses — is unaffected._

- **P5 — import.** R14's `Parse`/`Lift`; `lift . emit = id` property on the v1 fragment;
  one genuine Blawx-authored example (e.g. `bird.yaml`, defeat and all) lifted to L4, its
  tests re-expressed as `#EVAL`s, and both engines agreeing on every query. Exit: the bird
  example round-trips Blawx → L4 → Blawx with the fixpoint intact.

  _**EXECUTED 2026-08-19.** The IR extension (P5-1: overrules, applies/holds/according_to,
  `brInapplicable`, path section refs, goal-list queries, object declarations, test
  comments) landed with **every P1/P3 golden byte-stable** and both renderer images per
  constructor, unit-pinned against bird.yaml's own stored bytes. `L4.Blawx.{Xml,Blocks,
Parse}` + `L4.Blawx.Lift` + `l4 blawx --import/--parse-only/--reemit`; the emit→parse
  round-trip holds over the four seeds; the 15-example census matches the corrected
  §5.2 fragment count. **bird**: the single-command pipeline reproduces the committed
  `jl4/examples/blawx/imported/bird.l4` byte-for-byte (stale-encoding WARNING firing as
  ruled, P5-2); dual-engine agreement **4/4** (L4 `LIST "pingu"`, TRUE, TRUE, TRUE; the
  s(CASP) leg through the tier-1 harness's one-clause `holds`→`-blawx_applies` bridge,
  with a negative-control run proving the bridge is load-bearing); the re-emitted
  `bird.blawx` imported into the container and **12/12 rows byte-identical after
  real-UI open-and-save**. The container's own reasoner answers bird's tests **3/4** —
  `pingu_with_jetpack_cant_fly` has no model upstream because no shipped consumer
  bridges a `holds` block naming `blawx_applies` — a live reproduction of the gap, and
  the second fork-PR candidate beside legalese/blawx#1. The build also surfaced and
  pinned an upstream s(CASP) engine inconsistency (benefit/q1 admits a surplus model
  whose own body has none; `KNOWN_SURPLUS` table with control run) and rewrote the
  lift's stratification guard over the program the lift actually EMITS (witness: bird
  plus one mirrored `overrules` is refused `blawx-lift/unstratified` by name)._

## 11. Worklist after the Blawx v3 webinar (2026-09-02)

_Added 2026-09-02. **Per-item status lives on the item**: an item that has landed carries a dated
`DISCHARGED` / `PARTIAL` / `BLOCKED` note of its own, and an item with no such note has not
landed. (The file header's summary of what remains open is not re-cut per item; read the notes
below.) Everything here was **measured that day** on
`origin/unstable` at `f4ae3d5e` with an `l4` built from `31af0995` (the Blawx modules are
unchanged since #279), against the checkout at `/Volumes/transcend/src/blawx` and the R13
harnesses. Items are numbered **W1–W9** so later notes can cite them. Each says what was
measured, what it implies, and which section it amends; the section it amends is **not**
rewritten here — a W-item is discharged by editing that section and marking the item done._

**The target froze while the product moved.** `Lexpedite/blawx` on GitHub has had no commit
since 2024-11-01 (v1.6.22-alpha), which is what every byte-exactness claim in R10/R12 is about.
`Lexpedite/blawx_mcp`'s README (read 2026-09-02) opens _"THIS REPOSITORY IS DEPRECATED AS OF
BLAWX v2.2.3, June 20, 2026 — OFFICIAL MCP SUPPORT FOR BLAWX IS NOW VIA REMOTE MCP — SEE
DOCUMENTATION AT HTTPS://APP.BLAWX.DEV"_; that site's landing page footer reads _"Blawx v3.0.5"_
(fetched 2026-09-02), and `/api/`, `/api/deployments/` and `/docs/` all answer 404 to an
unauthenticated fetch. At the webinar Jason Morris showed a deployments endpoint
(`app.blawx.dev/api/deployments/`) and remote MCP; whether v2/v3 still generates the v1.6
s(CASP) dialect is unknowable from outside. Consequence for this bridge: the `--scasp` leg is
the part that survives a front-end rewrite; `EmitXml`/`Parse` survive only while Blawx keeps
Blockly's XML serialisation (v1.6 calls `Blockly.Xml.domToWorkspace` throughout and never
`Blockly.serialization` **[E]**), and the interview/abductive leg follows whatever the hosted
reasoner exposes.

**Two new seeds** (worktree `blawx-rps`, not yet a PR): `rps.l4` — Jason Morris's Rock Paper
Scissors Act, his running example, from `blawx/static/blawx/examples/rps.yaml` — and `beard.l4`
— his Beard Tax Act s.1, from `beard_tax.yaml`. Both are written in record style (Meng,
2026-09-02: GIVEN-with-records over ASSUME for Blawx seeds unless the ASSUME shape is measurably
more isomorphic); both `--roundtrip` "IR and bytes unchanged"; fixpoint 8/8 and 9/9 canvases
byte-identical under the real Blockly 10.1.3 generator; tier-1 4/4 and 4/4 in swipl. An
ASSUME-style twin of RPS also compiles, and its `throw` lowers to the arity-3 relationship Jason
declares, where the record version lowers it to an attribute of a per-game Player; neither
reproduces his multi-valued `player(Game, Player)` attribute, because a two-player game in a
functional language is two named slots.

### W1 — record identity does not survive flattening (exporter defect, silent)

**Measured.** The first RPS encoding took a Player and a Game and asked whether that player
wins, finding "the other player" by `EQUALS` on Player records. L4 said `TRUE` for Jane; the
tier-1 harness said **no model**. The R11 flattening emits the `#EVAL`'s argument as object `p1`
and the game's first player as `p2`, two objects for one structurally-equal value, so
`P = Firstplayer` fails. Re-encoding s.4 once per seat (`first player wins` / `second player
wins`) needs no identity and passes 4/4. **Implies.** L4 compares records by value, Blawx
compares objects by atom; any rule with `EQUALS`/disequality on record-typed operands emits
source that parses, checks, and _answers differently_ — the §3.2.1 failure class, caught here
only because R11 keeps the oracle outside the artifact. **Do.** For v1, refuse
`REq`/`RNeq` whose operands are record-typed with a named `LowerError` (loud), and keep the first
RPS encoding as a `not-ok/` fixture; later, hash-cons structurally-equal record arguments in the
query flattening (one object per distinct value) and lift the refusal. Amends §4.1, §8.11.

**DISCHARGED (v1 half) 2026-09-02.** The refusal is built and both fixtures are in the tree; the
hash-consing is **not** built and remains the next step (see below). What was measured this
session, on this branch, with `l4` built from this worktree:

- _the defect, reproduced before the fix_: `l4 blawx not-ok/record-identity.l4` exited **0** and
  emitted `P = Firstplayer` / `blawx_diseq(P,Firstplayer2)` beside test facts `throws(p1,rock)`,
  `first_player(g1,p2)`, `throws(p2,rock)` — two objects for one value. `l4 run` on the same file
  answers `TRUE`; staged as a temporary seed, `python3 etc/blawx-tier1-harness.py` reported
  **0/1 queries passed — expected a model; got NO model**. The staged seed and its golden were
  deleted; the file lives only under `not-ok/`.
- _the refusal_: `L4.Blawx.Lower.recordIdentity`, kind `LEUnsupported "record identity (Blawx)"`,
  fired from the `RCmp` arm for `REq` and `RNeq` alike once either operand's recovered sort
  _contains_ a **declared** record sort — directly, or under any nesting of `LIST OF` and `MAYBE`
  (`recordInSort`). It is in the **Blawx** leg, not `L4.Relational.Lower`: the shared IR defines
  `REq` as generic equality that each emitter dispatches (§8.2), and it is Blawx's own
  occurrence-keyed flattening that breaks the correspondence. `l4 blawx` on the fixture now exits
  **1** with two diagnostics (one per DNF clause of the `IF`/`ELSE`, matching the house precedent
  for per-occurrence errors).
- _the two boundary cases, both measured after review_. The check's first cut tested the operand's
  sort for `RSRecord` at the **top** only and tested nothing else, which was wrong in both
  directions. **Under-fire**: a `LIST OF Player` field compared with `EQUALS` exited **0** and
  emitted `members(A,Members), members(B,Members2), Members = Members2.` — the same divergence,
  still silent. The sort search now descends `RSList` and `RSMaybe`; the second fixture
  `not-ok/record-identity-list.l4` carries both a `LIST OF Player` and a `LIST OF MAYBE Player`
  rule and `l4 blawx` exits **1** with one diagnostic each, naming the operand's own sort
  (``type `LIST OF Player`, which contains the record type `Player` ``). `LIST OF MAYBE` is the
  only reachable route to the `MAYBE` arm: a bare `MAYBE Player` field is refused first by
  `blawxValueType` (measured — "sort with no Blawx value type: … RSMaybe (RSRecord …)"), because
  that function types any `RSList` as `BVList` without looking inside but has no `RSMaybe` arm.
  **Over-fire**: `ASSUME Person IS A TYPE` with `a EQUALS b` was refused, telling the author that
  an abstract category is a "record type" and recommending a FIELD comparison that cannot exist —
  and removing an emission the parent commit had. `RSRecord` carries both a declared record and an
  `ASSUME`d type ("L4.Relational.IR"); the discriminator is a lookup among the declared records,
  which `Env.envDeclRecords` now is. That module emits again, ending in `A = B.`, and so does a
  `LIST OF Person` over the same `ASSUME`d category.
- _no collateral_: all **12** emitting seeds re-lowered and their `expected/*.blawx` **and**
  `expected/*.pl` are byte-identical — `lowered=12 identical=24 differing=0` by `cmp` against
  the goldens, so no golden was regenerated and none needed to be.
- _harnesses_: fixpoint **18 checked, 0 failed, 0 empty-skipped** over `rps.blawx` and
  `beard.blawx` together (`BLAWX_CHECKOUT=…/blawx-stock`, blockly 10.1.3, jsdomErrors 0, per W9);
  tier-1 over the whole corpus **154/154 queries passed** (119 distinct + 35 twin replays,
  `python3 etc/blawx-tier1-harness.py`).
- _tests_: `cabal test jl4-core-test` **428 examples, 0 failures**; the
  `what the Blawx leg refuses` block is **11 examples, 0 failures**, of which seven are W1's —
  four refusals (bare `EQUALS`, its disequality half, `LIST OF`, `LIST OF MAYBE`) and three
  positive controls (an enum-valued FIELD, two `ASSUME`d abstract operands, a `LIST OF` an
  `ASSUME`d category). `cabal test l4-cli-test -m blawx` **47 examples, 0 failures**; the case
  added here runs `l4 blawx` over `not-ok/record-identity-list.l4` and asserts exit 1 plus both
  container spellings.

**Still open — the hash-consing.** One object per _distinct value_ instead of per occurrence, in
`skolemise`, after which `recordIdentity` lifts and both `not-ok/record-identity.l4` and
`not-ok/record-identity-list.l4` move to the emitting corpus with tier-1 oracles of their own.
Deliberately not attempted here: it changes the object names in every existing test canvas, so it
is a golden-regenerating change and wants its own measurement (fixpoint and tier-1 across all 12
seeds) rather than riding a refusal. **Also still open, and smaller**: the check is a sort test, so
its reach is sort recovery's reach — an operand whose record type arrived as `RSOpaque` would carry
no record name to find. No such case was constructed and none is known reachable in the M1
fragment; it is written down here rather than claimed away.

**Not W1's to fix**: this section's own status header still counts the corpus as "sixteen `.l4`
files … (eleven emitting seeds, five `not-ok/` refusal fixtures)". Measured 2026-09-02 with
`ls jl4/examples/blawx/*.l4 | wc -l` → **12** emitting seeds and
`ls jl4/examples/blawx/not-ok/*.l4 | wc -l` → **7** `not-ok/` fixtures (six, plus
`record-identity-list.l4` added here), so the header is stale by one in each direction and this
item widens the second gap. The header is edited once at integration, by whoever merges the
W-branches, because every W-item would otherwise rewrite the same paragraph.

### W2 — `STRING` fields have no ontology image

**Measured.** `name IS A STRING` on Player: _"sort with no Blawx value type: `name` involves
the sort RSString, which Blawx's ontology cannot declare"_. **Implies.** §4.7's "literals
survive as atoms, usable for equality" is true only in rule bodies; a string-typed _field_ has no
attribute value type to be declared under. **Do.** Verify against `scasp_generator.js:927-1156`
(R3's value-type evidence) whether v1.6 has any string-valued attribute type; if not, narrow §4.7
to say so and make the diagnostic say "use an enum or a category for identity"; if it does, give
`classifyPred` the image. Amends §4.7.

**DISCHARGED 2026-09-02** (corrected the same day after review — the first cut both overstated
what the code did and mis-cited two of its measurements). Measured: **there is no string-valued
attribute type in v1.6**, so the narrowing branch is the one taken and no image was built. The
attribute-type dropdown is written out as a literal seven-entry array (`blawx-blocks.js:5376`)
and re-populated from `attributeOptions = [["true / false","boolean"]].concat(allTypes)` (`:5583`,
applied at `:5596`), where `allTypes` is the literal six-entry `datatypeOptions` of `:5577` plus
the declared categories (`:5579`/`:5581`); the relationship block's per-argument dropdowns are
re-populated from that `allTypes` at `:5603`, and are first built from a second literal six-entry
array at `:5262`/`:5314`. R3's cited generator range has two branches, `boolean` and
not-`boolean`, and otherwise passes the dropdown value through unexamined into
`blawx_attribute(Cat,Name,Type)` (`scasp_generator.js:927`). The word `string` occurs nine times
across the two files (`grep -c string blawx-blocks.js scasp_generator.js` → 4 and 5), never as a
value type; only the quoted-token form `grep -cE "'string'|\"string\""` has a single hit,
`scasp_generator.js:107`. §4.7 is
rewritten to split the admitted half (a literal in a rule body) from the refused half (a `STRING`
sort in a signature), with those citations.

**What review changed.** The first cut put the refusal in `blawxValueType` only, and wrote
"refused — a `STRING`-sorted field, parameter or result" in §4.7 and in `doc/exports/blawx.md`.
That sentence stated more than the code did: `valueType` is reached only from the two arms of
`classifyPred` that build a declaration block, so a predicate of total arity ≤ 2 that is not
attribute-shaped (`PCUndeclared`, rules only) skipped the check — a `STRING` **parameter** there
exported at exit 0, emitting `according_to(sec_1_section,throws_named,P,S) :- player(P), S =
zebra.` with no declaration line at all, and re-saving clean through Blawx's own generator; and a
`STRING` **result** on a nullary constant was likewise admitted — indeed the section's own
"Admitted" bullet was an instance of it, contradicting the bullet above it. `classifyPred` now
runs a `STRING` pre-pass over the whole signature before classifying, so field, parameter and
result all give the same named diagnostic. The `STRING`-literal probe was re-cut around a
`LIST OF STRING` field, since the old probe (a nullary `GIVETH A STRING`) is now correctly
refused.

`blawxValueType`'s `RSString` arm names the value types that do exist and prescribes the enum or
the category; the enum remedy was executed rather than asserted (`name IS A PlayerName` →
`blawx_category(player_name).` + `blawx_attribute(player,name,player_name).`). Two fixtures,
`jl4/examples/blawx/not-ok/string-field.l4` and `.../string-param.l4` (each `l4 blawx` **exit 1**,
each `l4 check` **Check succeeded**), and five `BlawxAssumeSpec` cases — the field refusal and its
advice, the enum that replaces it, the parameter, the result, and the surviving literal.
Evidence: `cabal test jl4-core-test` **426 examples, 0 failures**; `cabal test l4-cli-test
--test-options="-m blawx"` **45 examples, 0 failures**; all twelve `expected/*.blawx` regenerated
byte-identical (`git status --porcelain jl4/examples/blawx/expected/` empty); fixpoint on `rps`
and `beard` **18 checked, 0 failed**; tier-1 on both **8/8**; `node etc/check-corpus-goldens.mjs`
**368 corpus files, all four goldens present**. Not done, and not asked for: no positive corpus
seed carries a string literal — the probe lives in the unit test, because a string literal with no
legal text around it is not a seed.

**Two edits this item deliberately did not make**, both in the file's top status paragraph, which
is one paragraph every §11 item would otherwise rewrite. (a) That paragraph still lists "an
ontology gap (W2)" among what remains open, in the same tree that marks W2 discharged. (b) Its
corpus count reads "nineteen `.l4` files … six `not-ok/` refusal fixtures"; `string-param.l4`
makes it **twenty (twelve seeds, seven `not-ok/`, one `imported/`)**, re-counted 2026-09-02 with
`ls jl4/examples/blawx/*.l4 jl4/examples/blawx/not-ok/*.l4 jl4/examples/blawx/imported/*.l4`. The
sentence already tells the reader to re-derive with `ls`, so it is stale-but-self-flagging rather
than merely false. Both are one-clause fixes for whoever re-cuts that paragraph once §11 drains.

### W2-followup — a string literal renders as an object selector nothing declares

**Measured 2026-09-02**, while probing the surviving half of §4.7. The literal in
`p's aliases EQUALS LIST "zebra"` reaches the Blockly XML as
`<block type="object_selector" …><mutation … objectname="zebra"></mutation><field
name="object_name">zebra</field></block>`, and the same document contains **zero**
`object_declaration` blocks (`grep -c object_declaration` on the emitted `.blawx` → `0`). **Do
not read this as a defect yet.** It re-saves clean through Blawx's own generator
(`blawx-fixpoint-harness: 3 checked, 0 failed`) and the s(CASP) it regenerates carries
`Aliases = [zebra | []].`, so every oracle available offline agrees. What is untested is a live
instance's UI: whether an object selector naming an object no declaration block declares renders
as a usable dropdown, an empty one, or an error. **Do.** Settle it at tier 2, against a running
Blawx, on the instance §11 W8 rebuilt; if the UI cannot show it,
either emit an `object_declaration` for each literal in the string-atom table or fall back to a
plain text field. Amends §4.7.

### W3 — section numbers follow `§` order, not the source's

**Measured.** R4 ruled flat numbered sections for v1. On `rps`, Jason's `sec_4_section` (s.4,
the winner) is our `sec_1_section` because the headline decision exports first; his paragraph
canvases `sec_2__para_a_section` … `sec_3__para_c_section` have no image at all. The same shape
blocks the reverse direction: the lift rejects _"the rule is attributed to sec_1\_\_para_a_section,
which is not a flat numbered section"_ on both fixtures. **Do.** (a) Let a numbered `§` header
(`§ 4. …`) or an `@ref … s 4` pin the CLEAN section number, so attributions read
`according_to(sec_4_section, …)` and the synthesised `rule_text` numbers match the source; (b)
paragraph eIds are the question R4 left open and stay open. Amends R4, §4.9.

### W4 — NLG for object-valued attributes

**Measured.** Ours synthesises `"has beats of"` / `"has first player of"`; Jason's hand NLG reads
`"beats"`. R3/R10 leave `@nlg` as the override and no seed uses it yet. **Do.** Put `@nlg` on the
two new seeds; consider a default that treats a verb-shaped attribute name as the infix (`ov`)
form. Amends §4.9, R10.

### W5 — the import fragment against Blawx's own running examples: 0 of 2

**Measured.** `--import` on `rps.yaml` and `beard_tax.yaml` refuses both. By diagnostic:
`blawx-lift/attribute-type` (number- and object-valued attributes), `blawx-lift/relationship`
(`throw/3`), `blawx-lift/goal-shape` (`blawx_comparison(L,gte,5)`, binary attribute goals,
`blawx_diseq`), `blawx-lift/rule-section` (paragraph sections, see W3),
`blawx-lift/test-block` (`object_declaration`, `assume`/abducibles in test canvases),
`blawx-lift/query-shape` and `unbound-query` (free-variable goals such as
`?- winner(Game, Player)`). R14's "stratified ground fragment" is exactly the `bird` shape
(2/15 fixtures, §5.2). **Do.** Size the next lift increment on these two fixtures: number and
object-valued attributes plus comparisons buy `beard_tax`; relationships, disequality, object
declarations in tests and open queries buy `rps`. Amends R14, §5.2.

### W6 — stale fixtures, witnessed twice more

**Measured.** Both fixtures store the old-form frame axioms (`not blawx_becomes`: 80 and 20
lines; `blawx_not_interrupted`: 0). `blawx-parse/stale-encoding` fired per section and the XML
was taken as canonical, per R14. **Do.** Nothing — recorded as the third and fourth witness for
the header's warning about the reference corpus.

### W7 — dates block the British Nationality Act

**Measured.** One `@export` added to `jl4/examples/legal/bna/bna.l4` (it is annotated with `@ref`
throughout and has no `@export`, so the exporter saw nothing to lower) stops at `commencement` and
`the appointed day`: _"date-valued parameters and results are M2 (see
specs/todo/DATE-LIBRARY-SPEC.md)"_. Jason presented a Claude-assisted Blawx encoding of the BNA
at the webinar; ours cannot be compared with it until the M2 date leg lands. **Do.** Nothing new
here — §4.6 already scopes it; this is evidence for its priority, and the reason the
`legal/bna` corpus is the first thing to try when M2 lands.

### W8 — the instance was not what the measurements said, and the fork now pins the build

**Measured.** The container that ran the R12/R13 measurements was Docker Hub
`lexpedite/blawx:latest`, built 2023-09-22 from `826315b` (v1.6.21-alpha), **amd64 under
emulation**, with none of the five fork fixes. Rebuilding from source on 2026-09-02 exposed
three moving targets in upstream's Dockerfile, each now pinned by a commit on `legalese/blawx`
`mengwong/main` (which also carries #1–#5 merged): a bare `npm install blockly` (pinned to
10.1.3, what the old image ships and what the fixpoint harness measures); a hard-coded
`bin/x86_64-linux/swipl` symlink (the s(CASP) pack step died with `swipl: not found` on arm64;
now a glob); and an unpinned Django (5.x rejects `TIME_ZONE = 'MST'` on a base with no tz
database; now `Django<5` plus `tzdata`). Still unpinned there: `swipl:latest`, s(CASP) from
`master.zip`, and `storage.js` from Blockly's `develop` branch. **Do.** Add these build commits to
§8.10's fork list when they are PR'd; re-run the R12 fixpoint and the tier-2 bird tests on the
rebuilt image and record the numbers beside the 2023-image numbers in §10.

**Tier 2 on the rebuilt image, measured 2026-09-02 (same day, later).** Container
`legalese/blawx:edge` (v1.6.22-alpha + fork fixes #1–#5, Django 4.2.30, native arm64
SWI-Prolog 10.1.14, s(CASP) 1.1.4 from master, Blockly 10.1.3). One more missing runtime found
only by running a test: the copied swipl tree lacks `libossp-uuid.so.16`, which
`mqi_start` needs, so every run answered _"Blawx could not load the reasoner."_ until
`libossp-uuid16` was installed (now in the Dockerfile). Then, through
`POST /<owner>/<slug>/test/<name>/run/` with the docs published and `blawx.run` granted to
the anonymous user: Jason's own `rps.yaml` — `bobjane` → `Winner = jane`, `who_wins` → 0
answers (no facts, no abducibles), `hypothetical` → 3 abductive answers; **our** `rps.blawx`
— q1 model, q2 no model, q3 no model, q4 model, matching the L4 oracle **4/4**, `interview` →
3 abductive answers; **our** `beard.blawx` — model / no / model / no, matching **4/4**,
`interview` → 3. Headless loading needs the fixture's owner pk to exist and the `.blawx`
pks renumbered away from anything already loaded (our fixtures carry no `rule_slug`; the app
derives it on save, so two copies of one Act under one owner collide on the unique
constraint).

### W9 — R10's "current generator" now has two candidates, and they disagree

**Measured.** The fixpoint harness regenerates s(CASP) with the generator in `BLAWX_CHECKOUT`.
With the checkout on `mengwong/main` (upstream plus fork fixes #1–#5 merged, 2026-09-02)
`rps.blawx` fixpoints **8/9**: `root_section` differs, because fix #1 rewrites the eight
"Neither" frame axioms that R10 reproduces quirk-for-quirk. With a stock checkout
(`/Volumes/transcend/src/blawx-stock`, `origin/main` at `6a717b1`) it fixpoints **9/9**.
**Implies.** The emitter is byte-exact against stock v1.6.22, and the instance rebuilt on
2026-09-02 (W8) runs the fixed generator — so on our own instance an open-and-save of
`root_section` will now show a diff, which is the R12 gate failing by construction. Until ruled,
the harness must run with `BLAWX_CHECKOUT=/Volumes/transcend/src/blawx-stock`. **Do (ruling
needed, Meng).** Name the target: (a) stock — keep emitting the quirks, treat the fork's
instance as non-reference for R12, and run the fixpoint against `blawx-stock`; or (b) the
fork — teach the emitter the fixed axiom forms behind a flag or unconditionally, regenerate
every `expected/*.blawx`, and make `blawx-stock` the non-reference. (b) is the honest one if
the fixes are right and upstreaming (R10) is not coming; (a) is the only one under which the
published `lexipedite/blawx` image re-saves cleanly. Amends R10, R12, R13.

**ANSWERED 2026-09-02 (Meng): (a), stock — with the instance re-cut.** The stock v1.6.22 generator
stays R10's byte-exact target, because it is what the published `lexipedite/blawx` image, any
third-party instance, and (as far as anyone outside can tell) app.blawx.dev regenerate with. Our
instance is rebuilt from the fork with only the server-side fixes (#2 `ldap.py`, #3 `reasoner.py`,
#4 `blawx-blocks.js` dropdown race — none of which changes generated s(CASP)) and WITHOUT #1 and #5,
which are reverted on `legalese/blawx` `mengwong/main` and stay open as upstream PRs. So one instance
serves tier 2 and the R12 re-save gate. The harness default `BLAWX_CHECKOUT=/Volumes/transcend/src/blawx`
is that branch; `blawx-stock` remains as an independent witness.

_Related, outside this spec: SARA (Holzenberger, Blair-Stanek & Van Durme 2020 — nine IRC
sections with a Prolog reference encoding) is nominated on `legalese/canon`
`subjects/LONGLIST.md` as a differential target for this leg and the Prolog leg._

## Appendix A — worked example **[E — executed at both tiers; Blockly XML remains U]**

The same source module as the Catala study's Appendix A, for cross-bridge comparability.
_Executed 2026-08-16, twice. **Tier 1**: the `sec_1_section`/`sec_2_section` rules below plus
the test facts, assembled in `reasoner.py` load order over a `blawx_comparison` library
subset and run under SWI-Prolog 9.2.9 + the s(CASP) pack, answer
`?- benefit_amount(a1,Amount).` with `Amount = 1000` — the L4-oracle value. **Tier 2**: a
hand-authored `.blawx` of this example (minimal declarations, empty `xml_content`) was
accepted by `POST /import/` on a running `lexpedite/blawx:latest` container (linux/amd64
under emulation on the arm64 reference machine), and
`POST /admin/benefit-act/test/benefit_amount_1/run/` returned
`{"Answers":[{"Variables":{"Amount":1000},…` **with an English justification tree** —
"…because 70 is greater than or equal to 65, and 50000 is less than or equal to 100000 …
1000 + 0 is 1000" — even before `#pred` emission. The imported ruledoc's regenerated Akoma
Ntoso carries exactly the predicted eIds `sec_1`/`sec_2` and slug `benefit-act`, verifying
R4's eId-prediction mechanism, and the duplicated bridge lines deduplicated correctly under
the `% BLAWX CHECK DUPLICATES` pass. Only the Blockly XML pairing (P3) remains **[U]**._

_Correction (2026-08-18, from the L4.Relational M1 build): both `@export` annotations moved
**above** their `GIVEN`. The appendix originally wrote them between `GIVETH` and the
definition head; measured on the tree at `afcef88f`, that placement does not reliably
attach — `L4.Export.getExportedFunctions` returned only ONE of the two decisions, so half
the program was unreachable from any entry point. Every `@export` in the in-tree corpus
sits above `GIVEN`. The seed derived from this appendix
(`jl4/examples/relational/benefit.l4`) records the same finding in its header._

```l4
DECLARE Applicant HAS
    age       IS A NUMBER
    income    IS A NUMBER
    isVeteran IS A BOOLEAN

@export
GIVEN a IS AN Applicant
GIVETH A BOOLEAN
DECIDE `eligible for benefit` IF
       a's age AT LEAST 65
    OR a's isVeteran
    UNLESS a's income GREATER THAN 100000

@export
GIVEN a IS AN Applicant
GIVETH A NUMBER
`benefit amount` a MEANS
    IF `eligible for benefit` a THEN 1000 PLUS bonus ELSE 0
    WHERE bonus MEANS IF a's isVeteran THEN 250 ELSE 0

#EVAL `benefit amount` (Applicant WITH age IS 70, income IS 50000, isVeteran IS FALSE)
```

Emitted `rule_text` (CLEAN):

```
Benefit Act

1. An applicant is eligible for benefit if at least 65 years old or a veteran,
unless their income exceeds 100,000.
2. The benefit amount is 1,000 plus a veteran's bonus of 250; zero if ineligible.
```

`root_section` carries the declarations — `blawx_category(applicant)` and the four attributes
(`age`/`income` number, `is_veteran` boolean, plus the two decision predicates
`eligible_for_benefit` boolean and `benefit_amount` number), each as its full 44-line block
(R10; elided here). `sec_1_section` (Mode A; `OR` split into two rules, `UNLESS` as the
complementary comparison per R5; bridge triples deduplicated at load):

```prolog
according_to(sec_1_section,eligible_for_benefit,A) :- applicant(A),
age(A,Age),
blawx_comparison(Age,gte,65),
income(A,Income),
blawx_comparison(Income,lte,100000).

% BLAWX CHECK DUPLICATES
holds(sec_1_section,eligible_for_benefit,A) :- according_to(sec_1_section,eligible_for_benefit,A).

% BLAWX CHECK DUPLICATES
  eligible_for_benefit(A) :- holds(sec_1_section,eligible_for_benefit,A).

according_to(sec_1_section,eligible_for_benefit,A) :- applicant(A),
is_veteran(A),
income(A,Income),
blawx_comparison(Income,lte,100000).
```

`sec_2_section` (the `WHERE` helper as an auxiliary predicate; `NOT` on the input via `-`, on
the computed decision via `not`, per R5; triples elided):

```prolog
according_to(sec_2_section,veteran_bonus,A,250) :- applicant(A),
is_veteran(A).

according_to(sec_2_section,veteran_bonus,A,0) :- applicant(A),
-is_veteran(A).

according_to(sec_2_section,benefit_amount,A,Amount) :- applicant(A),
eligible_for_benefit(A),
veteran_bonus(A,Bonus),
Amount is ( 1000 + Bonus ).

according_to(sec_2_section,benefit_amount,A,0) :- applicant(A),
not eligible_for_benefit(A).
```

The `#EVAL` becomes BlawxTest `benefit_amount_1`:

```prolog
applicant(a1).
age(a1,70).
income(a1,50000).
-is_veteran(a1).

?- benefit_amount(a1,Amount).
```

Harness expectation (L4 oracle): one answer, `Amount = 1000`, whose justification tree reads —
via the R10 NLG strings — "a1 has a benefit amount of 1000, because a1 is eligible for benefit,
because a1's age of 70 is greater than or equal to 65 and a1's income of 50000 is less than or
equal to 100000…". The Mode B variant (R6) would instead attribute the income cap to its own
proviso section defeating section 1 — the statute's shape, machine-checked before it ships.
