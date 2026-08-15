# L4 → Catala: expressive-domain overlap and transpiler spec

_Status: **design, not yet implemented.** Written 2026-08-16 on branch `mengwong/catala-bridge`.
Nothing exists under `jl4-core/src/L4/Catala/`; there is no `catala` subcommand in `jl4/app/Main.hs`.
What would make the present tense true: an `L4.Catala.{IR,Lower,Emit}` module triple plus a CLI verb,
mirroring the shipped OpenFisca backend (`jl4-core/src/L4/OpenFisca/`, `jl4/app/L4/Cli/OpenFisca.hs`)._

_Review round, 2026-08-16 (same day, second session). What review changed: (a) a working
`catala`/`clerk` 1.2.1 toolchain now exists on this machine, built from the cited checkout commit,
so Appendix A and the Mode B fragment are **executed**, not believed — the worked example
round-trips (L4 `1000` = Catala `1,000.0`) and a 7-point Mode A/B agreement grid passes; (b) six
citation repairs from an independent re-verification of all 18 [E] claims (none refuted in
substance); (c) new facts from a full-repo sweep — the implicitly-imported stdlib, the attribute
inventory, the JSON test mode — which amend R7, strengthen R3/R8, and add R11; (d) corpus
fragment-fit measurements (§10.1). No ruling flipped from the first draft; all remain PROPOSED._

**One-line summary.** Just as an `@export`-annotated `DECIDE`/`MEANS` over a subject record is
exactly an OpenFisca variable, it is exactly a Catala scope; L4's helper functions are exactly
Catala's toplevel `declaration … depends on … equals` definitions — and because Catala's
non-default fragment is a total, first-order, recursion-free functional language over exact
rationals, the constitutive layer of L4 lands in it with **less** numeric distortion than it lands
in OpenFisca, while L4's regulative, temporal, and effect layers do not land in Catala at all.

**Evidence legend.** **[E]** = read out of the named file at the named commit, or executed.
**[U]** = believed true, not executed here. Catala facts were read from the checkout at
`/Volumes/transcend/src/catala`, commit `d37aca74` (2026-08-16, current upstream HEAD). L4 facts
were read from `l4-ide` at `8af7d332` (`unstable`). R9's first deliverable is **done**: `catala`
and `clerk` 1.2.1 are built from that same commit via opam (OCaml 5.2.1 switch named `catala`;
binaries at `~/.opam/catala/bin`; recipe in §8.9) — so Appendix A and the Mode B fragment are now
**[E]**: `catala typecheck` green, `clerk test` green, values recorded below. The z3-backed
`catala-proof` plugin is a separate opam package (`catala-proof.opam`) and is installed the same
way when P4 needs it.

---

## 0. Ruling status

| ruling | state        | detail                                               |
| ------ | ------------ | ---------------------------------------------------- |
| R1     | **PROPOSED** | unit of emission: scopes vs toplevels, §8.1          |
| R2     | **PROPOSED** | `NUMBER` → `integer`/`decimal`/`money`, §8.2         |
| R3     | **PROPOSED** | date arithmetic: `YMD` vs lenient `Date`, §8.3       |
| R4     | **PROPOSED** | Mode A (boolean) vs Mode B (exceptions), §8.4        |
| R5     | **PROPOSED** | higher-order fragment = combinator absorption §8.5   |
| R6     | **PROPOSED** | recursion: reject, do not synthesise folds, §8.6     |
| R7     | **PROPOSED** | test emission and the round-trip oracle, §8.7        |
| R8     | **PROPOSED** | literate envelope from inert style, §8.8             |
| R9     | **PROPOSED** | validation harness, never a build dep, §8.9          |
| R10    | **PROPOSED** | `TYPICALLY` → `context`, §8.10                       |
| R11    | **PROPOSED** | opaque strings tolerated, computed strings out §8.11 |

No ruling is ANSWERED yet; all eleven await sign-off. Each carries its evidence, its cost, and the
case against it in §8, per house style. (R9's first _deliverable_ — a pinned local toolchain — is
done, but the ruling it serves, harness-never-a-build-dep, still wants sign-off.)

## 1. Purpose, direction, precedent

Direction for v1 is **L4 → Catala** only, the same direction as the OpenFisca bridge. The reverse
direction (Catala → L4) is analysed in §5.2 because the overlap is asymmetric in an instructive
way, but it is a non-goal (§9).

The OpenFisca precedent fixes the shape: `lowerModule :: Module Resolved -> Either [LowerError] …`
consuming the `@export`-annotated `DECIDE`/`MEANS` subset over a subject record, rejecting
everything else **with a named diagnostic** rather than silently narrowing
(`jl4-core/src/L4/OpenFisca/Lower.hs:1-9,61` **[E]**). Its documentation discipline also carries
over: golden tests prove regression-stability only; a "round-trip" is an execution of the emitted
artifact in the real target toolchain against values L4's own evaluator produced
(`jl4/examples/openfisca/L4-OPENFISCA.md` §6 **[E]**).

What Catala buys that OpenFisca did not:

1. **A semantics-first target.** Catala's kernel is a formalised default calculus
   (`doc/formalization/Catala.DefaultCalculus.fst` **[E]**) with exact-rational arithmetic —
   `decimal` is `Q.t`, `money` is integer cents (`runtimes/ocaml/catala_runtime.mli:25-31` **[E]**)
   — so the float32 divergence caveat that caps OpenFisca round-trip fidelity
   (`L4-OPENFISCA.md` §6 **[E]**) simply does not arise. Numeric round-trips can demand equality,
   not tolerance.
2. **Its toolchain runs on our output.** Emitted Catala is admitted to `catala html/latex`
   (literate weave), the `explain` plugin (formula-graph "why" output), `json_schema` (form
   generation), `api_web` (JS bindings), and the Z3 `proof` plugin
   (`compiler/plugins/`, `compiler/verification/conditions.mli` **[E]**) — five Catala-side
   analogues of L4's own weave, ladder, wizard, service, and `#CHECK` stories (§4.12).
3. **Ecosystem reach.** Catala compiles to OCaml, Python, C, and Java with maintained runtimes
   (`runtimes/` **[E]**); one L4 source reaches four more host languages through a
   peer-reviewed compiler rather than through our own emitters.

## 2. Catala's expressive domain, as verified

A capsule of what the transpiler is aiming at; every claim **[E]** at `d37aca74` unless marked.

- **Kernel.** One construct beyond simply-typed lambda calculus: the default term
  `⟨ exceptions | justification :- consequence ⟩`. Evaluation reduces all exceptions; zero
  survivors → test the justification (true → consequence, false → _empty_); one survivor → its
  value; two or more → **Conflict** error (`Catala.DefaultCalculus.fst:186-224`). Emptiness that
  reaches an output raises **NoValue** at runtime; conflict raises **Conflict**
  (`runtimes/ocaml/catala_runtime.mli:68-77`). Exceptions are evaluated eagerly, so a
  `DivisionByZero` in a _losing_ exception branch still traps
  (`compiler/shared_ast/interpreter.ml:977-999`).
- **Scopes.** A scope is a record-to-record function whose variables carry IO qualifiers:
  `input` (caller-supplied, not definable in-scope), `internal`, `output`, and `context`
  (**reentrant**: the scope defines it, the caller may override, and the caller's value takes
  priority as an exception over the scope's own rules —
  `compiler/dcalc/from_scopelang.ml:100-129`). Sibling `definition`s at one priority level are
  exceptions to _each other_ (simultaneous truth = Conflict); `label`/`exception` chains build an
  arbitrary-depth priority DAG (`compiler/scopelang/from_desugared.ml:360-488`).
  `condition`-typed variables carry an implicit `false` base case and so can never raise NoValue
  (`from_desugared.ml:521-527`). Variables may chain sequential `state`s. Scopes call subscopes
  (with per-argument exception trees) or are invoked in expressions:
  `output of S with { -- x: … }`.
- **Types.** `boolean`, `integer` (ℤ), `decimal` (exact ℚ), `money` (integer cents; ×/÷ round to
  the cent, half-away-from-zero — `catala_runtime.ml:1101-1125`), `date`, `duration`,
  `code_location`, structs, enums (with payloads), `list of`, `optional of` (`Present`/`Absent`),
  tuples, `anything of type t` prenex type variables, abstract `external` types. **There is no
  string base type** — `typ_lit = TUnit | TBool | TInt | TMoney | TRat | TDate | TDuration | TPos`
  (`compiler/shared_ast/definitions.ml:244`); text exists only via the
  `declaration type Text: external` escape hatch with hand-written per-target runtimes
  (`tests/modules/good/text.catala_en`).
- **Restrictions.** No recursion of any kind — self-referencing scope variables
  (`compiler/desugared/dependency.ml:200-206`), self-referencing toplevel definitions and
  self-calling scopes (`compiler/scopelang/dependency.ml:151-153,169-170`), and recursive _types_
  (`dependency.ml:300-301,322-323`) are all rejected (`tests/func/bad/recursive.catala_en`). No
  anonymous lambdas in the surface _syntax_ (a `Lambda` node exists in the surface AST,
  `ast.mli:187`, but only the parser's list-combinator desugarings construct it — there is no
  lambda token). Effectively first-order: declared function _arguments_ are
  data-only (`compiler/surface/ast.mli:59-62`), and dcalc invariants forbid functions returning
  functions and partial application (`compiler/dcalc/invariants.mli:30-41`). Function-typed struct
  fields and closures do exist. Iteration happens exclusively through built-in list combinators
  (`map each`, `list of … such that`, `exists`/`for all`, `combine all … initially`, `sort`,
  `content of … such that … is minimum`, `number of`, `Integer.sum`, …).
- **Dates.** `date ± duration` where the duration has month/year components is **ambiguous by
  default and fatal** (`AbortOnRound`, `compiler/shared_ast/operator.ml:429`): Jan 31 + 1 month
  aborts unless a `date round down` (clamp: Feb 28/29) or `date round up` (overflow to Mar 1)
  declaration is in force — and that declaration is a **scope-use item** (per `scope X:` block,
  `ast.mli:220-224`), never global. The rounding itself lives in the vendored
  `runtimes/ocaml/dates_calc/dates_calc.ml:137-143` (`prev_valid_date`/`next_valid_date`).
  Duration literal units are exactly year/month/day — no week or sub-day units (`ast.mli:138`).
- **Envelope.** Source is a Markdown-shaped literate file; law text is prose, code lives in
  ` ```catala ` fences, module interfaces in ` ```catala-metadata ` fences, recorded CLI tests in
  ` ```catala-test-cli ` fences (`compiler/surface/lexer.cppo.ml:902-983`). A module file must
  declare `> Module Foo` where `Foo` matches the capitalised file basename
  (`compiler/surface/parser_driver.ml:521-537`); dialect is fixed by extension (`.catala_en`).
  `#[test]`-attributed scopes are the runnable test population.
- **Verification.** The `proof` plugin generates exactly two verification-condition kinds per
  variable: **NoEmptyError** (some rule always applies) and **NoOverlappingExceptions** (at most
  one exception fires), discharging them with Z3; user `assertion`s are _hypotheses_, not goals
  (`compiler/verification/conditions.mli:23-29`; hypothesis role at
  `verification/solver.ml:34-38`). Invocation: `catala proof --plugin-dir=… \
--disable-counterexamples` (`tests-extra/proof/good/assert.catala_en:36-41`).

### 2.1 Stdlib, attributes, and toolchain facts (review round) — all **[E]**

Facts surfaced by the full-repo sweep that the first draft missed; each changes a design point.

- **The stdlib is implicitly imported into every module** (`parser_driver.ml:748-763`; disable
  with `--no-stdlib`): `Stdlib_en` re-exports `Date`, `Duration`, `MonthYear`, `Period`, `Money`,
  `Integer`, `Decimal`, `List` (`stdlib/stdlib_en.catala_en:23-30`). Consequences for us:
  `Decimal.sum` exists (`stdlib/decimal_en.catala_en:116`) and is what L4 `sum` lowers to under R2
  (the first draft said `Integer.sum`, which was wrong for decimal-typed lists); the surface
  `sum <type> of` form is **deprecated** (`ast.mli:118`) and must never be emitted;
  `List.nth_element` and friends return `optional of`, so L4 index access survives Maybe-shaped
  (`stdlib/list_en.catala_en:25`); `Date` carries `add_round_down/up`, `of_year_month_day`,
  `first/last_day_of_month/year`, a `Month` enum, and rounding-explicit age predicates
  (`is_old_enough_rounding_down` etc.) — prime targets for `daydate.l4` alignment (§4.6); and a
  whole `Period` interval-algebra module exists (`stdlib/period_en.catala_en` — `overlaps`,
  `covers`, `intersection`, `split_by_month/year`), relevant to any future period-typed mapping.
- **Attribute inventory** (`compiler/desugared/name_resolution.ml:155-318`): `#[test]`,
  `#[error.message = "s"]` (on `assertion`/`impossible` only), `#[doc = "s"]` (or `##` docstring
  lines), `#[description = "s"]` and `#[label = "s"]` (on any declaration — landed 2026-06-16),
  `#[debug.print]`, `#[json = "s"]` (external values), `#[implicit_position_argument]`; plugins
  may register more. `@desc`/`@ref` now have native landing spots (§4.9).
- **`impossible`** is a first-class fatal expression, legal as a match arm or whole body, with
  `#[error.message]` for the message (`tests/enum/good/impossible.catala_en:14-16`) — the natural
  target for L4 refusal values (R3).
- **Expression forms missed in the first draft**: `xor`; `but replace { -- f: v }` functional
  record update; 1-based tuple projection `t.2`; inline `assertion e in e'`; pattern _test_ with
  binding and guard (`x with pattern C content y and y >= 2`); `lst contains e`; `l1 ++ l2`;
  `maximum/minimum of l or if list empty then d`; zip-map `map each (x, y) among (l1, l2)`;
  multi-key `sort all x among l in increasing order of k1 and then k2`; typed operator suffixes
  (`+$`, `>=@`, …) on all arithmetic _and comparison_ operators.
- **Visibility is positional, not keyword**: declarations inside a ` ```catala-metadata ` fence
  are public, inside a ` ```catala ` fence private (`ast.mli:322-328`;
  `tests/modules/bad/mod_use.catala_en`). This is the mechanism behind R1's public/private split —
  exported scopes' declarations go in the metadata fence, helpers stay in code fences.
- **Modules**: `> Using Foo as F` with dotted access; `> Include: file.catala_en` textual
  inclusion (with `@ p.NN` page refs rendered by the LaTeX backend); emitted files may therefore
  import a shared helper module (R1's dedup question is _feasible_, still not decided). Module
  name matching is on a normalised `String.to_id`, not byte-exact (`string.ml:42`).
- **Numeric literal surface**: integers take **no** thousands separator (the cheat-sheet's
  `65,536` is wrong — `lexer.cppo.ml:820-823`); money literals max two fraction digits; date
  literals are `|YYYY-MM-DD|`; percent literals are decimals.
- **Test/CLI machinery**: `catala typecheck` exists; `test-scope` is not a catala verb — clerk
  rewrites it to `interpret --scope=…` (`clerk_runtest.ml:96-99`); `#[test]` scopes must have
  **no `input` variables** (`context` is fine — filled with ∅; `shared_ast/scope.ml:150-153`);
  `catala test-scope S --input '{"x": …}'` supplies inputs as JSON and `-F json` renders outputs
  as JSON (`tests/json/good/dates.catala_en:19`) — which dissolves R7's output-canonicalisation
  problem (§8.7); `--autotest` bakes interpreter results into compiled artifacts as assertions;
  `json-schema -s S` emits `[input schema, output schema]`. Working in a directory requires
  `clerk start` once (stages the stdlib into `_build/libcatala`); bare `catala` errors without it,
  and `clerk` shells out to `ocamlc`, so the opam switch must be on `PATH` (`opam exec --`).
- **Versioning near-misses, confirming §5.1**: an `[archive]` law-heading marker is lexed and then
  **never consumed** by any backend (`lexer_common.ml:34-43`; zero non-parser references), and
  `## Title | LEGIARTI…` heading IDs only emit Légifrance hyperlinks in the French HTML weave.
  Time-dependent law is hand-encoded as `input current_date` plus date-conditioned
  definitions/exceptions (`tests-extra/proof/good/assert.catala_en:5-22`).
- **Release policy** (`doc/RELEASE.md:11-15`): syntax break ⇒ major version bump, stdlib break ⇒
  minor — which tells R9 what a version pin protects against. In-repo tutorial/reference does not
  exist; the book lives at book.catala-lang.org.

## 3. L4's expressive domain, by layer

Keyword ground truth: `jl4-core/src/L4/Lexer.hs:244-330` **[E]**.

1. **Constitutive / decision layer.** `DECLARE` records and enums-with-payloads;
   `GIVEN`/`GIVETH`/`DECIDE`/`MEANS` functions (higher-order, polymorphic, recursive, mixfix
   names); `CONSIDER`/`WHEN` pattern matching with a landed exhaustiveness oracle; `BRANCH`
   first-match cascades; `IF`/`THEN`/`ELSE`; `WHERE` local helpers; `LIST`, `MAYBE`, `SET OF`
   (prelude); `UNLESS` — **pure sugar for `AND NOT`**, precedence 1
   (`jl4-core/src/L4/Parser.hs:1669-1683` **[E]**); `ASSUME` for uninterpreted inputs.
2. **Regulative layer.** `DEONTIC` contracts: `PARTY p MUST|MAY|SHANT action WITHIN d HENCE …
LEST …` (`Parser.hs:2374-2414` **[E]**), `FULFILLED`/`BREACH`, `RAND`/`ROR` parallel
   composition, `#TRACE` residuation against timestamped event streams.
3. **Temporal layer.** `EVAL … UNDER RULES EFFECTIVE AT <date>` and the four DATE-valued EVAL pins
   (`jl4-core/src/L4/TemporalContext.hs` **[E]**; commit `c57ca4df`-era work, Phase 1 merged).
4. **Effect / ledger layer.** `FETCH`/`POST`/`ENV`, `RECORD`/`COMMIT`/`ATTEST`/`RECALL`
   (`Parser.hs:2100-2238` **[E]**).
5. **Annotation layer.** `@export` (deployment surface), `@desc` (parameter/scale conventions the
   OpenFisca lowering keys on), `@ref`/`@ref-src`/`@ref-map` (provenance), `@nlg`, and
   `TYPICALLY` — reintroduced 2026 as **metadata-only** literal defaults, type-checked but not
   operational (`jl4-core/src/L4/TypeCheck.hs:1268-1306`, commit `27cd4770` **[E]**; the status
   header of `TYPICALLY-DEFAULTS-SPEC.md` predates this and is corrected in this branch).

The overlap with Catala is: **all of layer 1 minus strings, general recursion, and general
higher-order functions; layer 5 partially (and profitably); layers 2, 3, 4 not at all** (§5.1).

## 4. The overlap, construct by construct

Verdicts: **CLEAN** (structure-preserving), **RESTRICTED** (maps under a side condition),
**EMULATED** (maps through emitted helper code), **OUT** (rejected with a diagnostic).

| L4 construct                                              | Catala construct                                                                          | verdict    | ref   |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------- | ----- |
| `DECLARE X HAS …` (record)                                | `declaration structure X: data …`                                                         | CLEAN      | §4.1  |
| `DECLARE X IS ONE OF …` (± payloads)                      | `declaration enumeration X: -- C content T`                                               | CLEAN      | §4.1  |
| `MAYBE` / `JUST v` / `NOTHING`                            | `optional of` / `Present content v` / `Absent`                                            | CLEAN      | §4.1  |
| `LIST OF T`, list literals                                | `list of T`, `[ a; b; c ]`                                                                | CLEAN      | §4.1  |
| `STRING` computation (12 string builtins)                 | — (no string base type)                                                                   | OUT        | §4.8  |
| `STRING` fields/params never inspected                    | dropped with a warning (R11)                                                              | RESTRICTED | §4.8  |
| `NUMBER`                                                  | `decimal` (default) / `integer` (forced contexts)                                         | RESTRICTED | §4.5  |
| `BOOLEAN`, `DATE`                                         | `boolean`, `date`                                                                         | CLEAN      | §4.6  |
| record construction `WITH` / access `'s`                  | `X { -- f: v }` / `x.f`                                                                   | CLEAN      | §4.1  |
| `GIVEN…GIVETH…MEANS` (first-order, total)                 | `declaration f content T depends on … equals e`                                           | CLEAN      | §4.2  |
| `@export` decision over a subject record                  | `declaration scope` (inputs = params, one `output`)                                       | CLEAN      | §4.2  |
| `WHERE` helpers                                           | `let … in` / private toplevel declarations                                                | CLEAN      | §4.2  |
| `ASSUME`d inputs                                          | scope `input` variables                                                                   | CLEAN      | §4.2  |
| higher-order arguments (beyond combinators)               | — (data-only function arguments)                                                          | OUT        | §4.2  |
| recursion (incl. `FOLLOWED BY` structural)                | — (all recursion rejected)                                                                | OUT        | §4.2  |
| polymorphic helpers                                       | `anything of type t` toplevels; else monomorphise                                         | RESTRICTED | §4.2  |
| `IF`/`THEN`/`ELSE`, `AND`/`OR`/`NOT`                      | `if…then…else`, `and`/`or`/`not`                                                          | CLEAN      | §4.3  |
| `IMPLIES`                                                 | `(not a) or b` (no native implies)                                                        | EMULATED   | §4.3  |
| `UNLESS`                                                  | `and not …` (Mode A) or `exception` (Mode B)                                              | CLEAN      | §4.4  |
| `CONSIDER`/`WHEN` on enums (+ `OTHERWISE`)                | `match … with pattern -- C content x : …` (+ `anything`)                                  | CLEAN      | §4.3  |
| `CONSIDER` on literals (`WHEN 0 THEN …`)                  | `if`/`else` chain (constructor-only patterns)                                             | EMULATED   | §4.3  |
| `BRANCH` first-match cascade                              | `if`/`else` chain (Mode A) or exception ladder (Mode B)                                   | EMULATED   | §4.4  |
| `map`/`filter`/`fold`/`any`/`all`/`sum`/`length`          | `map each`/`list of…such that`/`combine all`/`exists`/`for all`/`Decimal.sum`/`number of` | CLEAN      | §4.7  |
| `SET OF` + `UNION`/`INTERSECT`/`` `LESS` ``               | sorted-dedup `list of` + emitted helper functions                                         | EMULATED   | §4.7  |
| `#EVAL` / `#ASSERT`                                       | `#[test]` scope + ` ```catala-test-cli ` expected block                                   | CLEAN      | §4.10 |
| `TYPICALLY` metadata on a decision's `GIVEN`              | `context` variable (caller-overridable default)                                           | CLEAN      | §4.4  |
| `@desc` on an exported decision                           | `#[description = "…"]` on the scope declaration                                           | CLEAN      | §4.9  |
| inert-style scaffolding, `§` headers, `@ref`              | literate law text + Markdown headings                                                     | CLEAN      | §4.9  |
| `PARTY MUST`/`HENCE`/`LEST`, `RAND`/`ROR`, `#TRACE`       | —                                                                                         | OUT        | §5.1  |
| `RECORD`/`COMMIT`/`ATTEST`/`RECALL`, `FETCH`/`POST`/`ENV` | —                                                                                         | OUT        | §5.1  |
| `EVAL … UNDER RULES EFFECTIVE AT`                         | — (per-version emission workaround only)                                                  | OUT        | §5.1  |

### 4.1 Types

Records, enums with payloads, `MAYBE`, and lists are isomorphic — Catala's `optional of` with
`Present`/`Absent` landed 2025-07 (`00c4daa5`, #839) and matches `MAYBE`
constructor-for-constructor. L4 names are
mangled to Catala's lexical classes (lowercase snake_case idents; capitalised struct/enum/scope
names; the module name must equal the capitalised emitted-file basename,
`parser_driver.ml:521-537` **[E]**), folding Unicode per the precedent of DMN ruling R3.

### 4.2 Functions, scopes, application

The load-bearing discovery of this study: **Catala's toplevel `declaration … depends on … equals`
fragment is a plain, default-free, total functional language** (**[E]**, re-verified in the
review round with a sharper citation: `process_topdef`, `compiler/desugared/from_surface.ml:
1760-1804`, builds toplevel bodies with plain `translate_expr` — and `from_surface.ml` contains
zero occurrences of `EDefault`/`edefault`, so _no_ surface expression form produces a default
term; every `EDefault` originates in `scopelang/from_desugared.ml`'s rule-tree pass, which runs
only on scope definitions). L4's
constitutive decision functions do not need to touch Catala's default machinery at all. The
emission split (R1): every `@export` decision becomes a _scope_ — because scopes are what Catala's
tooling (interpreter `-s`, `json_schema`, `api_web`, `explain`, proof VCs) operates on — and every
non-exported helper becomes a toplevel declaration, called with `f of a, b`.

Side conditions: arguments must be data (no function-typed parameters — reject, R5); no recursion
(reject, R6); polymorphic helpers survive as `anything of type t` toplevels when first-order,
otherwise are monomorphised per instantiation. `ASSUME`d module-level inputs — the "ASSUME-shaped"
style the DMN exporter already consumes — map directly onto scope `input` variables, which is a
cleaner landing than DMN's, since Catala scopes natively separate input/internal/output.

### 4.3 Branching and pattern matching

`CONSIDER` over enum constructors maps to `match … with pattern` one-for-one, including payload
binders (`-- Case1 content x :`) and `OTHERWISE` → `anything`. Both languages statically require
exhaustiveness (L4: the landed oracle; Catala: `compiler/dcalc/from_scopelang.ml:222-236` **[E]**
— "The constructor %a of enum %a is missing from this pattern matching"), so
exhaustiveness _transfers_ rather than being re-derived. Catala's `-- anything :` wildcard arm
receives `OTHERWISE`, and `impossible` (optionally `#[error.message = "…"]`-annotated) is the arm
for cases L4 proves unreachable. Catala patterns are constructor-only:
`CONSIDER` over numeric or string literals and `BRANCH` cascades become `if`/`else` chains
(Mode A) — semantically exact, since both are first-match — or exception ladders (Mode B, R4).
Catala has no list patterns; `WHEN EMPTY / WHEN x FOLLOWED BY xs` is subsumed by the recursion
rejection (R6) except where it is a disguised combinator (§4.7).

### 4.4 Defeasibility: the asymmetric hole, and two profitable mappings

The headline asymmetry: **Catala's signature feature has no landed L4 counterpart.** L4's
`TYPICALLY` is metadata-only (`TypeCheck.hs:1268` **[E]**), `SUBJECT TO`/`NOTWITHSTANDING` is an
analysis-only spec, and `UNLESS` is monotone sugar (`Parser.hs:1669` **[E]**). Landed L4 is a
_total_ language: every exception is already compiled into explicit Boolean structure by the human
author. Consequently the forward transpiler never _needs_ default terms — a degenerate
unconditional `definition` collapses to a plain expression (`from_desugared` emits
`⟨⟨|true :- e⟩ | false :- ∅⟩` which the optimiser folds **[E]**).

But two L4 features map _onto_ the default machinery profitably:

1. **`TYPICALLY` → `context`** (R10). A `TYPICALLY`-annotated parameter of an exported decision
   becomes a `context` variable: the scope defines the default, the caller may override, and
   Catala's `merge_defaults` gives the caller's value exception-priority
   (`dcalc/from_scopelang.ml:72-129` **[E]** — `Expr.edefault ~excepts:[caller] … ~cons:callee`). This _operationalises_ in Catala what is only
   metadata in L4 — the strongest single argument that the two languages' domains overlap
   mid-feature rather than merely at the STLC core.
2. **`UNLESS` → `exception`** (R4, Mode B). `DECIDE p IF c UNLESS d` denotes `c AND NOT d`. The
   Mode B emission — `label base rule p under condition c consequence fulfilled` plus
   `exception base rule p under condition d consequence not fulfilled` — has the same truth table
   (d → false; else c → true; else the `condition` implicit-false base), reads like the statute's
   proviso in the weave, and gives the Z3 proof plugin something real to verify
   (NoOverlappingExceptions/NoEmptyError, §4.11). Truth-table equivalence must be machine-checked
   per construct before Mode B ships. A first executed instance of that check exists **[E]**: an
   emitted module carrying the Appendix A rule in both renderings plus an `AgreeAt` comparison
   scope typechecks, and a 7-point boundary grid (both sides of the age-65, income-100000, and
   veteran thresholds) reports `all_agree = true` under `clerk test`. The production gate is the
   same harness generalised: enumeration for boolean domains, Z3 elsewhere.

### 4.5 Numbers and money

L4 `NUMBER` is one exact-rational type; Catala splits `integer`/`decimal`/`money` and rejects
cross-type arithmetic without explicit conversion. Policy (R2): lower `NUMBER` to `decimal`
uniformly — Catala `decimal` is exact `Q.t` **[E]**, so unlike the OpenFisca float32 story there
is no precision cliff — inserting `integer of`/`decimal of` coercions at the finitely many
structurally-integer positions (list indices, `number of` counts). Never infer `money` in v1:
Catala money multiplication rounds to the cent half-away-from-zero (`catala_runtime.ml:1101-1125`
**[E]**), which silently changes results relative to L4's exact arithmetic; money is opt-in via a
future annotation, alongside any alignment with `jl4-core/libraries/currency.l4`.

### 4.6 Dates and durations

L4 `DATE` ↔ Catala `date` cleanly. But month/year arithmetic diverges three ways and no global
setting reconciles it (R3):

- L4 `YMD` **refuses** an out-of-range date (`daydate.l4:104-117` **[E]**) — matches Catala's
  default `AbortOnRound` (both fail; failure modes differ: refusal-value vs runtime `DateError`).
- L4's lenient `Date day month year` is serial arithmetic that **rolls overflow forward**
  (`daydate.l4:49-56` **[E]**: Feb 31 → Mar 3) — this equals _neither_ Catala `date round down`
  (Feb 28) _nor_ `date round up` (Mar 1) **[E]** (`dates_calc.ml:145-158`). It is nonetheless
  _expressible_: day-granular arithmetic (`date + n day`) is never ambiguous, so the transpiler
  emits a `daydate`-equivalent helper computing month offsets in days, exactly as `daydate.l4`
  itself does.
- L4 has no duration type (daydate uses `NUMBER`s of days); Catala durations are first-class.
  Emitted arithmetic uses literal `n day` durations, sidestepping the ambiguous month/year forms
  entirely, so emitted scopes need no `date round` declaration.

The review round found the stdlib already carries most of what the R3 helper would hand-write
**[E]**: `Date.of_year_month_day` / `to_year_month_day` / `get_year|month|day`,
`add_round_down`/`add_round_up` (functional equivalents of the scope-level `date round`
declarations), `first/last_day_of_month|year`, a `Month` enum, and rounding-explicit age
predicates (`Date.is_old_enough_rounding_down` — `stdlib/date_en.catala_en`). The emitted
daydate-equivalent helper should be written _against_ these rather than from scratch; only the
roll-forward overflow rule (Feb 31 → Mar 3) remains genuinely ours to emit. `YMD` refusal values
land on `#[error.message = "…"] impossible` (§2.1), which resolves R3's previously-undecided
sub-question — proposed answer recorded there.

### 4.7 Lists, sets, quantifiers

The combinator inventories align almost name-for-name: `map`/`filter`/`fold`/`any`/`all`/`sum`/
`length` map to `map each`/`list of … such that`/`combine all … in acc initially …`/`exists …
such that`/`for all … we have`/`Decimal.sum of`/`number of` **[E]** (syntax file lines 215-273;
the sum is the stdlib fold matching R2's `decimal` lowering — the first draft said `Integer.sum`,
and the surface `sum <type> of` form is deprecated and must not be emitted, `ast.mli:118`).
Beyond the draft's list, Catala also has `contains`, `++`, `maximum`/`minimum … or if list empty
then d`, zip-map over paired lists, multi-key `sort`, and `optional`-returning index access
(`List.nth_element`) — so L4's `elem`, append, bounded max/min, zips, and safe indexing survive
too (§2.1).
The lambda that L4 passes to a combinator is absorbed into Catala's binder syntax — this is the
only place lambdas survive (R5). L4's argmin/argmax-style patterns even have direct forms
(`content of x among l such that e is minimum or if list empty then d`). `SET OF` has no Catala
counterpart; v1 emulates sets as canonically-sorted deduplicated lists with emitted
`union`/`intersect`/`difference` helpers, accepting the same one-level-quotient caveat the L4
prelude already documents.

### 4.8 Strings

`STRING` _computation_ — any of the twelve string builtins — is **OUT**, rejected with a
diagnostic naming the offending expression, per the OpenFisca `LowerError` discipline. The only
Catala escape hatch is an `external` Text module requiring hand-written runtime code per target
(§2), which would violate the self-contained-output principle; revisit only if a concrete corpus
demands it. But measurement (§10.1) shows the corpora's strings are almost never computation:
they are opaque identity fields (`name IS A STRING` — BNA, roles.l4) and the OpenFisca `period IS
A STRING` plumbing convention. R11 therefore tolerates **uninspected** strings — dropped from the
emitted artifact with a per-site warning — instead of rejecting whole modules for them. Corpus
note: inert-style _scaffolding_ strings are not `STRING`-typed computation and are unaffected
(§4.9); wizard label strings (54 in `regcf-wizard.l4`) are UI content whose Catala counterpart is
the `json_schema`/`#[description]` path, not string values.

### 4.9 The literate envelope: L4's isomorphism becomes Catala's weave

Both languages stake their identity on isomorphism with the legal source. L4 carries verbatim
statute text inline as inert scaffolding and `§` section headers; Catala carries it as Markdown
prose around code fences, and its `html`/`latex` backends weave the two. The mapping (R8): `§`
headers → Markdown headings; inert scaffolding and `@ref` citations → law text preceding the
scope/definition they annotate. The emitted file is then a _legible literate document_, and
`catala latex --wrap` renders L4-authored law side-by-side with its formalisation for free —
a rendering path L4 does not currently own.

The review round adds _structured_ landing spots beyond prose **[E]** (§2.1): `@desc` →
`#[description = "…"]` on the declaration (2026-06-16 feature, consumed by `json_schema`-style
tooling); short doc comments → `##` docstring lines (sugar for `#[doc]`); `@ref-src` with a page
reference → the `> Include: file.pdf @ p.NN` form the LaTeX weave renders — which answers R8's
previously-undecided `@ref-src` sub-question in the affirmative.

### 4.10 Tests

Every `#EVAL`/`#ASSERT` in the source module becomes a `#[test]` scope whose inputs are the
literal arguments and whose expected output is recorded in a ` ```catala-test-cli ` block (R7).
The oracle is L4's own evaluator, exactly as `roundtrip_check.py` does for OpenFisca: `clerk test`
passing proves L4↔Catala agreement on those points — not law-conformance, and the spec keeps the
OpenFisca doc's three-tier honesty (golden / executed round-trip / law-validated).

Two operational facts from the review round shape the emission **[E]**: a `#[test]` scope may
have no `input` variables (`shared_ast/scope.ml:150-153`), so the test scope always _wraps_ the
scope under test with literal arguments (as Appendix A does); and the expected block should use
the JSON forms — `$ catala test-scope T -F json`, optionally `--input '{…}'` — because Catala's
human rendering writes `1,000.0` where L4 writes `1000`, and JSON output
(`{"result":"1000"}`-style exact rationals) removes that canonicalisation problem instead of
solving it (amends R7, §8.7). The first executed round-trip exists: Appendix A's `#EVAL` yields
`1000` in L4 and its emitted `#[test]` scope yields `1,000.0`/`clerk test` green in Catala.

### 4.11 Verification

Catala's proof plugin checks only NoEmptyError and NoOverlappingExceptions **[E]**
(`conditions.mli`), which are trivially satisfied by Mode A output (no defaults, `condition`
implicit-false). This is an argument _for_ Mode B (R4): exception-ladder emission gives the VCs
content, and a Z3-discharged "no two provisos overlap" is a new verification product for L4
corpora. The pipeline is executed **[E]**: `catala-proof` installs from the same opam pin (z3
via opam), and `catala proof` over the Mode B module reports "No errors found during the proof
mode run" — with the honesty note that on the seed example both VCs are near-trivial (single
exception; `condition` base), so this validates the toolchain path, not yet an interesting
proposition. P4's exit remains a corpus with genuinely overlapping-looking provisos. Conversely L4-side verification (exhaustiveness oracle, `#CHECK`, ROBDD tooling) runs
_before_ emission and transfers its guarantees into the total fragment.

### 4.12 Tooling mirrors

Independently evolved, near-isomorphic pairs — evidence that the two projects occupy the same
niche: Catala `explain` ↔ L4 ladder/`#EVALTRACE`; `json_schema` ↔ jl4-service schema export;
`api_web` ↔ L4 web-app generation; `clerk` inline expected-output tests ↔ L4 golden files;
`#[test]` scopes ↔ `#EVAL` directives; literate weave ↔ inert style. The transpiler makes each
Catala tool a consumer of L4 sources.

## 5. What does not map

### 5.1 Forward losses (L4 → Catala): the layer boundary

Layers 2-4 are rejected with diagnostics, not silently dropped:

- **Regulative.** Catala has no deontic, event, party, or trace notion; nothing in
  `surface/ast.mli` **[E]** models obligation or time-bounded action. A `DEONTIC`-typed
  declaration or `PARTY` block is OUT. (Encoding an LTS as scope-per-step data would be a
  simulation, not a mapping; explicitly out of scope.)
- **Temporal.** No rule-version axis exists in Catala; applicability-over-time is encoded manually
  as `date` conditions (canonical pattern: `input current_date` + date-guarded definitions,
  `tests-extra/proof/good/assert.catala_en:5-22` **[E]**). The sweep confirmed the absence is
  real, not an oversight: an `[archive]` law-heading marker is lexed and never consumed by any
  backend (§2.1). Workaround, not v1: emit one module per version snapshot, pinning
  `EVAL … UNDER RULES EFFECTIVE AT d` at emission time. A richer future mapping — L4 rule
  versions → date-guarded exception ladders on Catala's own idiom — would be a Mode B extension
  and inherits Mode B's machine-checked-equivalence gate.
- **Effects/ledger.** `FETCH`/`POST`/`ENV`/`RECORD`/`COMMIT`/`ATTEST`/`RECALL` — Catala is pure;
  OUT.
- **Strings** (§4.8), **general recursion** (R6), **general higher-order code** (R5), and
  `@nlg`/`@ref-map` annotation semantics beyond prose emission (§4.9).

### 5.2 Reverse losses (Catala → L4), recorded for the future

The mirror-image hole: Catala **exception trees, `context` reentrancy, variable `state` chains,
`scope … under condition`, and `date round` policies** have no landed L4 counterparts. A reverse
transpiler need not wait for L4 defeasibility, though: Catala's own compiler flattens all default
terms into option-typed total code at lcalc (`handle_exceptions`,
`runtimes/ocaml/catala_runtime.mli` **[E]**), so Catala→L4 can piggyback that pass and emit total
L4 — at the cost of the priority _structure_, which is precisely what
`SUBJECT-TO-NOTWITHSTANDING-SPEC.md` would need to receive it. That spec's §6 acquires a concrete
foreign customer here: Catala's `label`/`exception` DAG is an existence proof of the semantics L4
would adopt, formalised and battle-tested.

## 6. The v1 source fragment, precisely

`l4 catala` accepts a type-checked module containing: `DECLARE` records/enums; first-order,
non-recursive, monomorphic-or-prenex `GIVEN`/`GIVETH`/`MEANS`/`DECIDE` functions over
`BOOLEAN`/`NUMBER`/`DATE`/records/enums/`MAYBE`/lists; `CONSIDER`/`BRANCH`/`IF`/`WHERE`;
prelude list combinators with literal lambda arguments; `SET OF` under the §4.7 emulation;
uninspected `STRING` fields/params under R11's elision; `ASSUME`d inputs;
`@export`/`@desc`/`@ref`/`TYPICALLY` annotations; `#EVAL`/`#ASSERT`.

Everything else — `STRING` computation, recursion, function-typed parameters, `DEONTIC`/`PARTY`,
`#TRACE`, ledger/effect keywords, temporal pins — is rejected with a `LowerError` naming the
construct and its source range, in one batch (all errors reported, not first-error-wins),
following `OpenFisca.hs`'s "cannot compile these decisions" presentation **[E]**.

## 7. Architecture

Mirror the OpenFisca triple under `jl4-core/src/L4/Catala/`:

- **`IR.hs`** — a Catala _surface_ IR: module, struct/enum decls, scope decls (name, inputs,
  outputs, context vars), toplevel declarations, expressions, `#[test]` scopes, literate segments
  (law-text blocks interleaved with fenced code). The IR models the concrete `.catala_en` file,
  not dcalc — we emit source, and `catala typecheck` is the downstream gate.
- **`Lower.hs`** — `lowerModule :: Module Resolved -> Either [LowerError] CatalaModule`, keyed on
  `@export` via `L4.Export.getExportedFunctions` like OpenFisca.
- **`Emit.hs`** — renders one literate `.catala_en` whose basename matches the emitted
  `> Module` name; ` ```catala-metadata ` fence for declarations, ` ```catala ` fences for scope
  bodies, law text from §4.9, ` ```catala-test-cli ` stubs for R7.
- **CLI** — `l4 catala FILE [-o FILE]` in `jl4/app/L4/Cli/Catala.hs`, registered beside
  `openfisca` in `jl4/app/Main.hs`.

Validation (R9): an `etc/validate-catala.mjs`-style harness that runs `catala typecheck` and
`clerk test` on emitted files **when a catala binary is present, skipping silently otherwise** —
the same never-a-build-dependency posture `etc/validate-dmn.mjs` takes toward dmnmd, which is a
standing repo rule. Operational facts the harness must honour **[E]**: the working directory
needs a one-time `clerk start` (stages the stdlib into `_build/libcatala`; bare `catala` errors
without it); `clerk` shells out to `ocamlc`, so invoke via `opam exec --switch=catala --` or with
the switch's bin on `PATH`; and expected-output comparison should use the `-F json` form (§4.10).

## 8. Open rulings

Each follows house template: evidence → proposal → cost → the case against → what it does not
decide.

### 8.1 R1 — unit of emission: scopes for `@export`, toplevels for helpers

**Evidence.** Catala tooling (interpret `-s`, `json_schema`, `api_web`, `explain`, proof) is
scope-keyed **[E]** (§2); toplevel declarations are default-free plain functions **[E]** (§4.2).
**Proposal.** One scope per `@export` decision (inputs = subject-record fields flattened one
level, or the record itself as a single `input` — sub-ruling below), one `output`; every
non-exported reachable helper becomes a private toplevel declaration; unreachable code is not
emitted. Sub-ruling R1a: pass the subject record _whole_ as one `input` variable (no flattening),
because L4 house style already threads one record (`l4-house-style-given-records`), and Catala
struct inputs are first-class. **Cost.** Scope-call expressions at every inter-decision reference
(`(output of S with {…}).v`) are noisier than function calls. **Against.** Emitting _everything_
as toplevels would be simpler and more uniform; but it would make the output invisible to every
scope-keyed Catala tool, forfeiting §1's reason-2. **Not decided.** Whether helpers shared across
emitted modules deduplicate into a common emitted module.

### 8.2 R2 — `NUMBER` lowers to `decimal`; `integer` only where forced; `money` never inferred

**Evidence.** §4.5 **[E]**. **Proposal.** As titled; coercions inserted at integer-demanding
positions; emit a lowering _note_ (comment) at each coercion. **Cost.** Emitted arithmetic reads
`decimal`-heavy; counts surface as `decimal of (number of …)`. **Against.** Type-inferring an
integer/decimal split from usage would read better, but risks silent semantic drift at division
(`integer / integer → decimal` in Catala, but L4 `NUMBER` division was already rational — the
drift is real only if we _chose_ integer). Money inference is rejected because cent-rounding
changes values (§4.5). **Not decided.** The future money-annotation surface and its relation to
`@desc` conventions and `currency.l4`.

### 8.3 R3 — dates: native ops for `YMD`-style code, emitted day-arithmetic for lenient `Date`

**Evidence.** The three-way divergence measured in §4.6 **[E]**: Feb 31 ↦ refusal (`YMD`) /
Mar 3 (`Date`) / abort-or-Feb 28-or-Mar 1 (Catala). **Proposal.** Map `YMD`-constructed
arithmetic to native Catala date ops under the default `AbortOnRound`; compile uses of lenient
`Date` to an emitted helper reproducing daydate's serial semantics in day-granular (unambiguous)
Catala; never emit `date round up/down` on the transpiler's own initiative. **Cost.** The helper
is ~20 lines of emitted Catala per module that needs it. **Against.** Choosing `date round down`
globally would be idiomatic Catala and _usually_ agree — but "usually" is precisely the class of
silent divergence a law-to-law bridge cannot carry; the Feb-31→Mar 3 vs Feb 28 disagreement is a
concrete counterexample. **Sub-question resolved by review evidence** (folded into the
proposal, still awaiting the same sign-off): refusal-values map to `#[error.message = "…"]
impossible` — it is first-class, message-carrying, and legal exactly where refusals occur (match
arms, whole bodies; §2.1) — not to an `optional` result, which would infect every downstream
type. The stdlib `Date` module supplies most of the helper surface §4.6 describes.

### 8.4 R4 — Mode A default; Mode B (`--idiomatic-exceptions`) behind a flag, gated on proof

**Evidence.** §4.4's truth-table argument; §4.11's VC-content argument **[E]**. **Proposal.**
v1 ships Mode A (pure boolean/if-else emission — always total, semantics-identical by
construction). Mode B — `UNLESS` → `exception`, `BRANCH` → label ladder — ships behind a flag
only once each rewrite carries a machine-checked equivalence (truth-table enumeration for
booleans; Z3 VCs for the emitted form). The check's shape is now executed once **[E]**: an
emitted `AgreeAt` scope comparing both renderings, driven over the rule's decision boundaries,
`all_agree = true` under `clerk test` (§4.4). **Cost.** Mode A output is less idiomatic Catala and
gives the proof plugin nothing to do. **Against.** Shipping Mode B first would maximise the demo
value (provisos that _look_ like provisos, VCs that prove non-overlap) — but an unverified
semantic rewrite in a legal transpiler is the one bug class this project exists to prevent.
**Not decided.** Whether Mode B extends to `CONSIDER` arms (ordered-match → priority ladder).

### 8.5 R5 — higher-order code survives only by combinator absorption

**Evidence.** Catala function arguments are data-only; no lambdas **[E]** (§2); every L4 prelude
combinator has a Catala binder-form counterpart **[E]** (§4.7). **Proposal.** Recognise
applications of the known prelude combinators with literal-lambda (`GIVEN … YIELD`) or
named-function arguments and emit the binder form; reject every other higher-order use.
**Cost.** A helper that abstracts over a predicate dies even when all its call sites are
concrete. **Against.** Defunctionalisation could rescue more programs, but produces enum-dispatch
Catala no lawyer should read; the OpenFisca precedent (reject general application) held up.
**Not decided.** Whether named top-level functions may be passed into scope-call `context`
overrides (Catala supports it **[E]**; no L4 corpus demands it yet).

### 8.6 R6 — recursion is rejected; no automatic fold synthesis

**Evidence.** Catala rejects all recursion and recursive types **[E]** (§2). **Proposal.**
Reject, with a diagnostic that names the cycle and suggests the fold/combinator rewrite; do not
attempt automatic synthesis. **Cost.** The `CONSIDER … FOLLOWED BY`-style recursive idiom in
existing corpora must be hand-rewritten to combinators before it can export. **Against.**
Catamorphism synthesis for the structural-recursion subset is a known technique and would widen
the fragment — but it moves the transpiler from "structure-preserving" to "program-synthesising",
a trust boundary this spec declines to cross in v1. **Not decided.** A lint ("this recursion is
fold-shaped") that could ship earlier than any rewrite.

### 8.7 R7 — tests: one `#[test]` scope per `#EVAL`/`#ASSERT`, L4 evaluator as oracle

**Evidence.** Catala's test population is `#[test]`-keyed; expected outputs live in
` ```catala-test-cli ` blocks maintained by `clerk test --reset` **[E]** (§2); OpenFisca's
round-trip tiers **[E]** (§1). **Proposal.** As titled; the harness populates expected blocks
from L4 `#EVAL` results (not from `--reset`, so the _oracle is L4_, and a mismatch fails rather
than self-accepts); document the three-tier claim ladder verbatim from the OpenFisca doc.
**Amended by review:** expected blocks use `$ catala test-scope T -F json` (JSON output;
optionally `--input` for JSON inputs), because human rendering diverges (`1,000.0` vs `1000`
**[E]**) while JSON carries exact rationals — the canonicalisation pass shrinks to JSON value
comparison. **Cost.** JSON expected blocks are less human-legible than the pretty renderer's;
mitigate by emitting a human-format block _alongside_ as documentation, excluded from the oracle
comparison. **Against.** Using `clerk --reset` then diffing
against L4 would be less code but inverts the oracle. **Not decided.** Whether `#ASSERT`
failures should also emit as Catala `assertion`s inside the test scope (runtime-checked both
sides).

### 8.8 R8 — the literate envelope is emitted from inert scaffolding and `§` structure

**Evidence.** §4.9 **[E]**. **Proposal.** `§`/`§§` → `#`/`##` headings; inert scaffolding lines
and `@ref` citations → law-text prose immediately preceding the corresponding fence; modules
lacking any scaffolding emit minimal headings only. **Cost.** Emitted prose duplicates content
that lives in L4 comments — a drift surface if the L4 source evolves (mitigated: emission is
regenerable, never hand-edited). **Against.** Emitting bare code would be simpler and
loss-free computationally; but it forfeits the weave — the single most demo-legible artifact
this bridge produces. **Not decided.** `@ref-src` URL → Catala heading `@p.NN` page-reference
syntax alignment.

### 8.9 R9 — validation harness: optional-when-present, never a dependency

**Evidence.** The repo's standing rule that optional external evidence must not become a build
dependency (the `validate-dmn.mjs` posture toward dmnmd); no OCaml toolchain exists on the
reference machine **[E]** (checked 2026-08-16). **Proposal.** `etc/validate-catala.mjs`: locate
`catala`/`clerk` on PATH or via `CATALA_EXE`; run `typecheck` + `clerk test` over emitted goldens;
skip silently when absent; CI job optional and non-required. First deliverable — **done
2026-08-16**: a local toolchain built from the cited commit. Recipe (macOS arm64, ~15 min; the
published release binaries are Linux amd64 `.deb` only): `brew install opam; opam init --bare -n;
opam switch create catala 5.2.1; opam install /path/to/catala-checkout/catala.opam -y
--confirm-level=unsafe-yes` (the flag lets opam brew gmp and friends); optionally
`opam install …/catala-proof.opam` the same way for z3 proof support. Binaries land in
`~/.opam/catala/bin`; invoke via `opam exec --switch=catala --`. Upstream's release policy makes
the pin meaningful: syntax breaks only on major versions (§2.1). **Cost.** Local
runs without the binary prove less; reviewers must know the tier they're seeing. **Against.**
Vendoring a catala binary in CI as _required_ would catch more — and would couple our merge
queue to a foreign toolchain's availability, which §1.2-style precedent forbids. **Not
decided.** Whether the golden corpus stores emitted `.catala_en` files (reviewable diffs) or
regenerates them per-run (no drift); proposal leans stored-goldens, matching `l4 openfisca`
golden practice.

### 8.10 R10 — `TYPICALLY` on an exported decision's parameter becomes `context`

**Evidence.** `TYPICALLY` is landed metadata: literal-only, type-checked
(`TypeCheck.hs:1268-1306`, `27cd4770` **[E]**); Catala `context` gives caller-overridable
defaults with exception priority **[E]** (§4.4). **Proposal.** A `TYPICALLY v` on a `GIVEN`
parameter of an `@export` decision lowers that parameter to `context` (in-scope `definition` =
`v`) instead of `input`; non-exported helpers ignore `TYPICALLY` (Catala toplevels have no
default slot). **Cost.** Divergence in _caller-omission_ behaviour: an L4 caller must still
supply the argument (metadata is inert), while a Catala caller may omit it — the emitted artifact
is more permissive than its source. This is disclosed in the emitted doc header. **Against.**
Emitting `input` everywhere keeps the two artifacts' call surfaces identical; but it discards the
one place L4 metadata could become executable semantics, and wizard-style consumers of the
emitted `json_schema` _want_ the defaults. **Not decided.** Whether L4's own semantics should
follow (that is `TYPICALLY-DEFAULTS-SPEC.md`'s question, not this spec's).

### 8.11 R11 — uninspected strings are dropped with a warning; string computation is rejected

**Evidence.** Corpus measurement (§10.1) **[E]**: the seed corpus's STRING population is the
OpenFisca `period IS A STRING` plumbing convention (5 of 10 files) plus opaque identity fields
(`name IS A STRING` in `roles.l4` and in BNA's `PersonProfile`); zero string _computation_
anywhere in the measured corpora. Catala has no string type at all (§2). **Proposal.** A
string-typed field or parameter whose every use is storage or pass-through (never an argument to
a string builtin, never compared, never scrutinised) is **elided** from the emitted artifact,
with a per-site warning naming what was dropped; the OpenFisca `period` parameter is the
canonical instance and is recognised as such. Any _inspected_ string use stays a hard
`LowerError` per §4.8. **Cost.** Emitted records are narrower than their L4 sources — a shape
divergence the emitted doc header must disclose (same disclosure slot as R10's). Equality-compared
strings are NOT rescued (a closed-world enum synthesis was considered and rejected: the string
domain is open). **Against.** Rejecting all strings is simpler and shape-preserving; but
measurement shows it would reject half the seed corpus and the BNA statute for fields that carry
no semantics, which fails this spec's "as much as possible survives" brief. **Not decided.**
Whether the elision list should be emitted machine-readably (a manifest) for round-trip tooling
that wants to reconstruct the full record shape.

## 9. Non-goals (v1)

Reverse-direction transpilation (§5.2); deontic, temporal, effect/ledger layers (§5.1); money
inference (R2); string support (§4.8); French/Polish dialects (`.catala_en` only — dialect is a
pure lexer skin **[E]**, so this costs nothing semantically); external Text modules;
fold synthesis (R6); Mode B beyond its flag (R4); any change to L4 language semantics.

## 10. Acceptance and sequencing

- **P1 — emit + typecheck.** `IR`/`Lower`/`Emit` + CLI; goldens for a seed corpus (the OpenFisca
  example trio ports under R11's period-elision: flat-tax, benefit, household); `catala
typecheck` green under R9 harness. Exit: every emitted golden typechecks. De-risked by review:
  the target syntax for the whole worked example is executed (Appendix A), and the toolchain
  exists (R9).
- **P2 — round-trip.** R7 test emission; `clerk test` green with L4-oracle expected blocks. Exit:
  agreement on the seed corpus's full `#EVAL` population.
- **P3 — literate weave.** R8 envelope on an inert-style statute (British Nationality Act or
  Housing Act grounds are the natural corpus candidates); `catala latex --wrap` renders. Exit: a
  woven PDF whose prose is the statute and whose code is the transpiled L4.
- **P4 — proof demo.** Mode B behind its flag on one corpus with genuine provisos; Z3 discharges
  NoEmptyError/NoOverlappingExceptions. Exit: a machine-checked no-conflicting-provisos claim.
  De-risked by review: the plugin path runs (§4.11); what remains is the corpus and the
  equivalence gate.

### 10.1 Corpus fragment-fit, measured 2026-08-16 **[E]**

Greps over the tree (worktrees at their noted branches), counting OUT-fragment constructs:

| corpus                      | lines     | STRING                       | deontic | recursion       | temporal | verdict                                             |
| --------------------------- | --------- | ---------------------------- | ------- | --------------- | -------- | --------------------------------------------------- |
| `bna.l4` (corpus/bna-smoke) | 998       | 1 (opaque)                   | 0       | 0               | 0        | ~100% under R11; 39 `YMD` uses map per R3           |
| OpenFisca trio + 7 more     | ~10 files | 5 files, all `period`/`name` | 0       | `scale.l4` only | 0        | ports under R11; `scale.l4` needs fold rewrite (R6) |
| `regcf.l4` (unstable)       | 1241      | 2                            | 14      | 0               | 17       | constitutive core ports; layers 2-3 OUT (§5.1)      |
| `regcf-wizard.l4`           | 779       | 54 (UI)                      | 0       | 0               | 1        | not a Catala target; §4.8 wizard note               |

The P3 literate-weave candidate is therefore **BNA**: near-total fragment fit, statute prose
already inline, and its `YMD` usage exercises R3's native-ops path rather than the emitted
helper. `scale.l4`'s structural recursion is the one seed-corpus casualty of R6 — its rewrite
target is `combine all … initially` over the bracket list, which is also the cleaner L4.

## Appendix A — worked example **[E]** (executed 2026-08-16)

Both halves run: the L4 below evaluates to `1000` (`l4 run`, binary of 2026-08-04); the emitted
Catala typechecks and its test scope passes under `clerk test` against catala 1.2.1 built from
`d37aca74`, printing `result = 1,000.0` (same value; rendering divergence per R7's JSON
amendment). The `UNLESS` sits at a shallower indent than the `OR` — at equal indent L4's linter
correctly flags mixed AND/OR precedence (UNLESS desugars to `AND NOT`).

L4 source (v1 fragment):

```l4
DECLARE Applicant HAS
    age       IS A NUMBER
    income    IS A NUMBER
    isVeteran IS A BOOLEAN

GIVEN a IS AN Applicant
GIVETH A BOOLEAN
@export
DECIDE `eligible for benefit` IF
       a's age AT LEAST 65
    OR a's isVeteran
  UNLESS a's income GREATER THAN 100000

GIVEN a IS AN Applicant
GIVETH A NUMBER
@export
`benefit amount` a MEANS
    IF `eligible for benefit` a THEN 1000 PLUS bonus ELSE 0
    WHERE bonus MEANS IF a's isVeteran THEN 250 ELSE 0

#EVAL `benefit amount` (Applicant WITH age IS 70, income IS 50000, isVeteran IS FALSE)
```

Emitted `benefit.catala_en` (Mode A; law-text prose elided):

````markdown
> Module Benefit

```catala-metadata
declaration structure Applicant:
  data age content decimal
  data income content decimal
  data is_veteran content boolean

declaration scope EligibleForBenefit:
  input applicant content Applicant
  output eligible condition

declaration scope BenefitAmount:
  input applicant content Applicant
  output amount content decimal
```

```catala
declaration bonus content decimal depends on a content Applicant
  equals if a.is_veteran then 250.0 else 0.0

scope EligibleForBenefit:
  rule eligible under condition
    (applicant.age >= 65.0 or applicant.is_veteran)
    and not (applicant.income > 100000.0)
  consequence fulfilled

scope BenefitAmount:
  definition amount equals
    if (output of EligibleForBenefit with { -- applicant: applicant }).eligible
    then 1000.0 + bonus of applicant
    else 0.0

#[test] declaration scope Test1:
  output result content decimal

scope Test1:
  definition result equals
    (output of BenefitAmount with
       { -- applicant: Applicant { -- age: 70.0 -- income: 50000.0 -- is_veteran: false } }).amount
```

```catala-test-cli
$ catala test-scope Test1
┌─[RESULT]─ Test1 ─
│ result = 1,000.0
└─
```
````

(The block above is the human-format rendering as `clerk test --reset` records it, shown for
legibility; the production harness emits the `-F json` form per R7.)

Mode B rendering of the `UNLESS` proviso (R4, flag-gated), for comparison — this fragment also
typechecks, agrees with Mode A on a 7-point boundary grid, and passes `catala proof` (§4.4,
§4.11):

```catala
scope EligibleForBenefit:
  label base rule eligible under condition
    applicant.age >= 65.0 or applicant.is_veteran
  consequence fulfilled

  exception base rule eligible under condition
    applicant.income > 100000.0
  consequence not fulfilled
```

## Appendix B — the Mode A/B equivalence grid **[E]** (executed 2026-08-16)

The R4 gate's shape, run end to end: one module, both renderings, an `AgreeAt` comparison scope,
a boundary grid, and a Z3 pass. `catala typecheck` green; `clerk test` records the block shown;
`catala proof` reports "No errors found during the proof mode run" (§4.11's triviality caveat
applies). File `equivalence.catala_en`:

````markdown
> Module Equivalence

```catala-metadata
declaration structure Applicant:
  data age content decimal
  data income content decimal
  data is_veteran content boolean

declaration scope EligibleModeA:
  input applicant content Applicant
  output eligible condition

declaration scope EligibleModeB:
  input applicant content Applicant
  output eligible condition

declaration scope AgreeAt:
  input applicant content Applicant
  output agree content boolean

#[test] declaration scope TestGrid:
  output all_agree content boolean
```

```catala
scope EligibleModeA:
  rule eligible under condition
    (applicant.age >= 65.0 or applicant.is_veteran)
    and not (applicant.income > 100000.0)
  consequence fulfilled

scope EligibleModeB:
  label base rule eligible under condition
    applicant.age >= 65.0 or applicant.is_veteran
  consequence fulfilled

  exception base rule eligible under condition
    applicant.income > 100000.0
  consequence not fulfilled

scope AgreeAt:
  definition agree equals
    (output of EligibleModeA with { -- applicant: applicant }).eligible
    = (output of EligibleModeB with { -- applicant: applicant }).eligible

scope TestGrid:
  definition all_agree equals
    for all a among [
      Applicant { -- age: 70.0 -- income: 50000.0 -- is_veteran: false };
      Applicant { -- age: 70.0 -- income: 200000.0 -- is_veteran: false };
      Applicant { -- age: 30.0 -- income: 50000.0 -- is_veteran: true };
      Applicant { -- age: 30.0 -- income: 200000.0 -- is_veteran: true };
      Applicant { -- age: 30.0 -- income: 50000.0 -- is_veteran: false };
      Applicant { -- age: 64.0 -- income: 100000.0 -- is_veteran: false };
      Applicant { -- age: 65.0 -- income: 100000.0 -- is_veteran: false }
    ] we have (output of AgreeAt with { -- applicant: a }).agree
```

```catala-test-cli
$ catala test-scope TestGrid
┌─[RESULT]─ TestGrid ─
│ all_agree = true
└─
```
````
