# L4 ⇄ Blawx: expressive-domain overlap and transpiler spec

_Status: **rulings answered (R1–R14, Meng, 2026-08-18); implementation beginning.** Design
written 2026-08-16 (merged as PR #261); rulings recorded 2026-08-18. As of that date nothing
exists under `jl4-core/src/L4/Blawx/` or `jl4-core/src/L4/Relational/`; per R2 the shared
middle-end is built first, Blawx-driven, on branch `mengwong/l4-relational`, followed by the
`L4.Blawx.{IR,Lower,Emit}` triple plus the `l4 blawx` CLI verb mirroring the shipped OpenFisca
backend (`jl4-core/src/L4/OpenFisca/`), and later a `Parse`/`Lift` pair for import (R14).
Siblings: `CATALA-EXPORT-SPEC.md` (PR #260) is the house template this spec follows;
`specs/proposals/LOGIC-PROGRAMMING-BACKENDS-SPEC.md` (PR #258) proposes the shared relational
middle-end this spec consumes (§1.1, R2); the defeasibility prior-art evidence of §5.2 is
consolidated into `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` by PR #262, whose
`BACKEND-PORTFOLIO-SPEC.md` records this bridge as seam S2 of the backend portfolio._

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

### 4.7 Strings

`STRING` literals survive as atoms, usable for equality only (mangled per R3; collisions with
identifier atoms checked). All string _computation_ is OUT — the target has no string
operations at all.

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
- **The event layer** (`blawx_becomes` fluents): closest L4 relatives are the state ledger and
  the bitemporal axis, neither a semantic match today. Deferred, not refused.
- **Relational non-determinism**: a query with multiple answer substitutions lifts only under
  finite-domain enumeration (answers = filter over declared objects). RESTRICTED.

**Calibration against the shipped corpus**: of Blawx's 15 examples, 13 sit inside the liftable
fragment; `life_act.yaml` (event layer) and the `Residuals`-dependent corner of
`numerical_constraints.yaml` sit outside **[E]**. Ruled in R14; sequenced as P5; the
`.blawx`-side _parser_ half is shared with R13's tier-2 harness, which must read run results
anyway.

## 6. The v1 source fragment, precisely

`l4 blawx` accepts a type-checked module containing: `DECLARE` records and payload-free enums;
first-order, monomorphic `GIVEN`/`GIVETH`/`MEANS`/`DECIDE` decisions over
`BOOLEAN`/`NUMBER`/`DATE`/records/payload-free enums/`MAYBE`/lists, with ≤ 9 parameters;
`CONSIDER`/`BRANCH`/`IF`/`WHERE`/`UNLESS`; structural list recursion and the recognised
combinators; `STRING` literals in equality position; `ASSUME`d inputs;
`@export`/`@desc`/`@ref`/`@nlg` annotations; `#EVAL`/`#ASSERT`.

Everything else — string computation, payload enums, non-structural recursion, function-typed
parameters, `DEONTIC`/`PARTY`, `#TRACE`, ledger/effect keywords, temporal pins, `TYPICALLY`
(dropped with a note, not an error) — is rejected with a `LowerError` naming the construct and
its source range, all errors in one batch, following `Cli/OpenFisca.hs`'s "cannot compile these
decisions" presentation **[E]**.

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
inside the fragment **[E]**; `negation-as-failure.l4` as the three-valued landing zone **[E]**;
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
- **P4 — the showcase.** A statute corpus (BNA §1 or a Housing Act ground — both have
  `§`-anchored L4 encodings) emitted with full NLG; published on a Blawx instance; the
  scenario explorer runs an interview and every answer carries a justification tree with
  citations back to sections. Exit: a screen-recorded interview over transpiled L4.
- **P5 — import.** R14's `Parse`/`Lift`; `lift . emit = id` property on the v1 fragment;
  one genuine Blawx-authored example (e.g. `bird.yaml`, defeat and all) lifted to L4, its
  tests re-expressed as `#EVAL`s, and both engines agreeing on every query. Exit: the bird
  example round-trips Blawx → L4 → Blawx with the fixpoint intact.

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
Amount is 1000 + Bonus.

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
