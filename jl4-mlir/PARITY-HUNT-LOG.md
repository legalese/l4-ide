# The parity hunt — session log & reviewer's guide

A narrative companion to the five `mlir-review` commits below. The commit messages
say _what_ each fix does; this says _why the bugs existed_, _how they were found_,
_what was tried and rejected_, and _what is still open_. Read this first, then the
commits.

| commit     | what                                                        |
| ---------- | ----------------------------------------------------------- |
| `7c61c21f` | the hunt: curated `cases.json` across the corpus            |
| `b2ac28f3` | Finding 2 — DATE-operand arithmetic crash (ABI split)       |
| `692e0f0b` | same-arity overload collision (`Weekday of`)                |
| `a68195f2` | call-graph diagnostic propagation → prelude `go` collision  |
| `8e33fbdc` | Finding 1 — bare-head param enrichment (fixes `factorial`)  |
| `62f5f909` | bundle-wide L4 type map (clears #6; `is-a-weekday` compiles) |

Findings + matrices: [`coverage-report/PARITY-COVERAGE.md`](./coverage-report/PARITY-COVERAGE.md).
Per-item fix tracker: [`../specs/todo/mlir-parity-fixes.md`](../specs/todo/mlir-parity-fixes.md).

---

## Status ledger — fixed vs. open

Three states, because two would blur the most important distinction in this branch.
**🟡 is not 🔴 and it is not ✅**: the silent wrong answer is gone (the backend now
_refuses_ and routes to the jl4-service fallback, so a caller still gets the **right
answer**), but the backend still can't compile the construct natively. A 🟡 is safe to
ship; a 🔴 is not.

- ✅ **FIXED** — the WASM backend now computes the correct answer.
- 🟡 **FAIL-LOUD** — silent-wrong eliminated; correctly refuses (`supported: false`) and
  routes to fallback. Capability gap still open.
- 🔴 **OPEN** — still silently wrong, or untested.

| #   | Bug                                                                       | State | Where                               | Guarded by                                          |
| --- | ------------------------------------------------------------------------- | ----- | ----------------------------------- | --------------------------------------------------- |
| 1   | **DATE operand in `PLUS`/`MINUS`** → wasm crash (ABI split)               | ✅    | `b2ac28f3` `lowerRatBinop`          | `datetime-probe.cases.json` — **CI Tier-2**         |
| 2   | **Same-arity top-level overloads** collapse → wrong body (`Weekday of`)   | ✅    | `692e0f0b` `symbolFor`              | Haskell `same-arity overloads → distinct symbols`   |
| 3   | **Lifted local helpers collapse** → `sum [2,3,4] == 3` **in the prelude** | ✅    | `a68195f2` `localSymbolFor`         | `list-probe.cases.json` — **CI Tier-2** (+ Haskell) |
| 4   | **`emittedBodies` false self-collision** (untraced + `$trace` re-emit)    | ✅    | `a68195f2`                          | Haskell (would spuriously refuse the corpus)        |
| 5   | **Unsupported helper never reached its caller** (diagnostics discarded)   | ✅    | `a68195f2` `propagateDiagnostics`   | Haskell `unsupported helper → caller unsupported`   |
| 6   | **`is-a-weekday`** — helper-result NUMBER comparison unclassifiable       | ✅    | `62f5f909` `funcL4Types`            | `datetime-probe.cases.json` — **CI Tier-2** (+ Haskell) |
| 7   | **`britishcitizen5`** — ordered comparison on STRING-typed dates          | ✅    | `__l4_str_cmp` + synonym unfolding  | `britishcitizen5.cases.json` (5 cells) + `str-ordering-probe` — **CI Tier-2 candidate** (+ Haskell + JS) |
| 8   | **`ceo-performance-award`** — deontic, refuses; now differentially tested  | 🟡    | refuses honestly (2 real gaps)      | harness (refused-unsupported) + `.cases.json.pending` + Haskell |
| 9   | **`factorial`** — bare-head param typed `{"type":"object"}` → returns `1` | ✅    | `enrichParamTypes` (Export.hs)      | `desc.cases.json` — **CI Tier-2** (+ Haskell)       |
| 10  | **`orchestrator` helpers** — `CONSIDER` ctor `RIGHT`/`LEFT` (EITHER) unresolved | ✅ | `either-consider` LEFT/RIGHT lowering | `either-probe.cases.json` — **CI Tier-2** (+ Haskell) |
| 11  | **`mixfix-garden-path::tax-on`** — _exported_ same-arity collision        | 🟡    | **by design** (see below)           | Haskell `overload collision → supported:false`      |

**There are no remaining 🔴s.** With #9 fixed, the extended corpus gate passed for the
first time (130 byte-identical, 6 honest refusals); with #6 fixed it stands at
**133 byte-identical, 0 differs, 0 wasm-error, 5 honest refusals**. With #10 fixed the
new `either-probe` fixture joins CI Tier-2, which is now **83 byte-identical, 0 refused**
(68 prior + 15 EITHER). The extended-corpus tally is unchanged — `orchestrator::evaluateClaim`
was and remains one of the 5 refusals, but for the legitimate IO reason (`POST`), not the
`CONSIDER` ctor gap, which is now closed. Every known divergence either computes correctly or refuses
honestly and routes to the fallback. (That claim is bounded by the corpus and the
curated cases — the thesis below explains why "no known reds" and "no reds" are
different statements.)

**#11 is deliberate, not a to-do.** An `@export`ed same-arity collision is genuinely
ambiguous at the JSON API (the caller cannot say which overload it meant), so it stays
`markUnsupported` on purpose. Disambiguating it would also desync `Schema.wasmSymbol`.

### The capability gaps behind the 🟡s

Each 🟡 refuses because of exactly one missing capability. None of them is a
correctness bug any more — they are unimplemented features that the backend now has the
good manners to admit to.

- ~~**Bundle-wide L4 return-type map** → clears #6.~~ **Done** (`62f5f909`): the
  typechecker's substituted `EntityInfo` is projected to `funcL4Types` (checked type per
  `Unique`, bundle-wide), and `classifyOperand` resolves any `App` operand through the
  callee's result type — guarded by `classifyGroundType`, which trusts only builtin
  scalar heads so a polymorphic return slot (a tyvar is syntactically a nullary `TyApp`)
  can never classify as a raw-f64 comparison key.
- **A string-ordering runtime builtin** → clears #7.
- **~~Event-shaped deontic `cases.json`~~ → #8 was BOTH a test gap and a code gap.**
  Investigated (see "Ledger #8 resolved" below): `ceo-performance-award`'s exported
  `Eligible Service Requirement` refuses for **two** real reasons, not a missing test.
  (a) call-graph propagation from helper `Musk In Eligible Service` (an enum-EQUALS on a
  record projection whose type the lowering can't resolve — ledger-#6 family), and,
  more fundamentally, (b) `extractDeonticContract` returns `Nothing` because
  `exprToGuard` can't represent an **IF guard that is a helper-call application**
  (`Forfeiture Applies award state`) and `deontonToContract` **silently drops the
  action's `PROVIDED` guard**. Interpreting it would risk a wrong answer, so it MUST
  keep refusing. The lane's fix makes that refusal **loud and structural** at
  schema-build time (a deontic function with a null contract is now `supported:false`),
  closing a latent `supported:true`-with-null-contract landmine; curated
  branch-crossing cases are validated against jl4-service and parked in
  `jl4/examples/legal/ceo-performance-award.cases.json.pending` to gate the future fix.
- ~~**`CONSIDER` constructor resolution for `RIGHT`/`LEFT`** → clears #10.~~ **Done**
  (branch `mlir-fix/either-consider`): `EITHER a b` is a payload-CARRYING builtin ADT
  (prelude: `x IS AN EITHER a b`), not a nullary enum, so `testPatternTy` refused its
  `RIGHT`/`LEFT` constructor patterns ("could not be resolved to an enum tag"). Fix
  represents `EITHER` exactly like `MAYBE` — a 2-slot `[tag, payload]` record, `LEFT`
  tagged `0.0`, `RIGHT` `1.0` — and wires `LEFT`/`RIGHT` through the three CONSIDER
  choke points: construction (`lowerExpr` App, mirroring `JUST`), tag test
  (`testPatternTy`, `RIGHT`≡`JUST`-tag, `LEFT`≡`NOTHING`-tag), and payload bind
  (`bindPatternTy`, slot 1). The arity-1 string dispatch fires **only** for the builtin:
  a user-declared `LEFT`/`RIGHT` constructor is caught earlier by `lookupRecordFields`/
  `lookupEnumTag`. `orchestrator`'s four helpers (`isViolation`, `getConfidence`,
  `getAllTests`, `extractText`) now compile cleanly; `evaluateClaim` **still refuses**,
  but its reason chain is now purely the legitimate IO one (`depends on
  'callClaudeWithKey' … POST (IO) not supported`) — the 18 `RIGHT`/`LEFT` enum-tag
  diagnostics are gone. Guarded by `either-probe.cases.json` (**15/15 byte-identical**,
  branch-crossing LEFT/RIGHT + payloads distinct from tags; NUMBER/STRING/BOOLEAN/LIST
  payloads + a nested CONSIDER mirroring `extractText`) and the Haskell test
  `EITHER CONSIDER → supported dispatch`.
- **#10 shadow hardening** (same branch, post-refutation): the original #10
  claimed the arity-1 `LEFT`/`RIGHT` string dispatch could fire only for the
  builtin because "a user-declared constructor would be caught earlier by
  `lookupRecordFields`/`lookupEnumTag`". That lookup-first ordering existed only
  in the CONSTRUCTION path (`lowerExpr`), **not** in `testPatternTy`/
  `bindPatternTy`, which checked the string name FIRST. So a user
  `DECLARE Rev IS ONE OF RIGHT HAS rv …; LEFT HAS lv …` destructured in a
  CONSIDER read the user's bare-tag value through the builtin `[tag, payload]`
  slot layout → **silent wrong at `supported:true`** (jl4-service
  `rev-dispatch(5)=1005`; buggy WASM `-995`). Fix: (1) `isUserConstructor`
  gives user records/enums priority over the builtin JUST/NOTHING/LEFT/RIGHT/
  EMPTY string cases in `testPatternTy` **and** `bindPatternTy`, mirroring
  construction; (2) because construction lowers an enum-with-data / record
  constructor to a **bare tag with no payload slot** (the `lookupEnumTag` arm
  discards its argument), destructuring one in a CONSIDER is fundamentally
  unsound, so any arity ≥ 1 user constructor pattern now **REFUSES**
  (`supported:false` → routes to the reference evaluator) rather than compute.
  Nullary user-enum patterns (arity 0) are untouched and still dispatch by tag.
  No existing fixture uses enum-with-data, so the full corpus is unchanged
  (**104 byte-identical, 0 differs**). Guarded by the Haskell test
  `user LEFT/RIGHT enum → supported:false` and the committed adversarial
  fixtures `either-shadow.l4` / `either-shadow2.l4` (kept out of the gated
  corpus — they refuse entirely, which is the correct outcome).

---

## The thesis

**Compile-coverage overstates readiness.** The sweep in `coverage-report/FINDINGS.md`
asks "does this file lower cleanly?" (`supported: true`). Drop-in replacement asks a
strictly stronger question: "does it return _jl4-service's answer_?" Every bug below
lived in a file the sweep rated **`clean`**. A function can lower cleanly, report
`supported: true`, and be wrong.

**The adversary is trivial-input masking.** The harness auto-generates arguments when
a file has no curated `cases.json` (number→`1`, bool→`true`, string→`"x"`, enum[0]).
Those defaults land _precisely_ on the values where broken code coincides with correct
code. This is not a coincidence — it is a selection effect, and it recurred in **every
single** bug:

| bug                  | what masked it                                                                                        |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `factorial`          | `factorial 0 == factorial 1 == 1`; the backend returns `1` for _all_ x                                |
| DATE arithmetic      | a date param generates to `"x"`, which jl4-service _also_ rejects → looked like a benign `both-error` |
| prelude `sum`        | `sum [1,1,1] == count [1,1,1] == 3` — the broken body agrees on 1s                                    |
| `is British citizen` | the one generated input happened to expect the FALSE the broken helper always returns                 |

**Methodological consequence:** a green parity matrix means nothing without
branch-crossing curated inputs. Every `cases.json` added in this branch deliberately
picks values that separate the branches — and `list-probe.cases.json` carries a comment
saying so, because the obvious "simplify the test data" cleanup would silently
re-hide the bug.

---

## Two root causes, four manifestations

The four bugs are not four independent defects. They collapse to **two** root causes.

### Root cause A — the f64 ABI erases types (Finding 2)

Everything crosses the wasm boundary as `f64`, but an `f64` means different things in
different subsystems: a NUMBER is a **rational-pool handle** (an _index_, not a value);
a DATE is a **raw day-serial** (a value). `lowerRatBinop` lowered `PLUS`/`MINUS` on
_any_ operands to the generic rational ops, which unbox their args — so a date serial
got used as a pool index. `ratPool.get(serial) → undefined → .num` → crash.

The fix bridges the two representations (`__l4_date_serial` / `__l4_date_from_serial`),
which is why it has to know that `date − date` is a NUMBER (a day count) while
`date + n` is a DATE. Comparison needed no fix: DATE → `arith.cmpf` on the raw serial
is already correct.

### Root cause B — symbols are mangled by **arity only** (Findings 3 + the overload bug)

`dedupAndSynthExterns` mangles a function to `name__$arity`. Two _different_ functions
that share a name and an arity therefore collapse onto **one wasm symbol**; the dedup
keeps the first body and silently drops the rest. This one root cause produced **three**
distinct manifestations, which is why it's worth naming:

1. **Top-level ad-hoc overloads** (`692e0f0b`). `daydate`'s `Weekday of` has NUMBER and
   DATE overloads, both arity 1. They collapsed; the NUMBER body (`days MOD 7`) ran on a
   raw-serial date → `is-a-weekday` crashed.
2. **Lambda-lifted local helpers** (`a68195f2`) — _by far the worst_. Local helper names
   are **scoped in L4 but flat once lifted** to a top-level `func.func`. The prelude
   defines **ten** separate recursive helpers named `go`. Every arity-2 one became the
   bare symbol `go`; `count`'s body won. So the **standard library's `sum` returned the
   list length** (`sum [2,3,4]` → `3`) and `product` returned length+1 — at
   `supported: true`.
3. **A false positive in the collision detector itself.** `emittedBodies` keyed on
   `(symbol, arity)`, but a lifted helper legitimately reaches `lowerDecide` _twice_
   (once for the untraced body, once for the `$trace` clone). It reported that benign
   re-emission as a collision _with itself_.

The unified fix: the typechecker already gives every definition a distinct `Unique`, and
a `Ref` shares its `Def`'s unique. So **disambiguate by `Unique`, not by name** —
`symbolFor` / `localSymbolFor` / `emittedBodies` all key on it, and definition + every
call site agree automatically.

---

## Finding 3 is really about a _broken feedback path_

Worth dwelling on, because it's the most transferable lesson.

The backend **already knew** about manifestations (2) and (3), and about
`britishcitizen5`. It raised the diagnostics. It then **threw them away**:
`markUnsupported` keys a diagnostic on the _enclosing_ function, but
`Schema.applyDiagnostics` only downgrades entries in `bundleExports`. A helper is not an
export — so the diagnostic was dropped, the exported caller stayed `supported: true`,
and the helper's fail-closed `0.0`/FALSE surfaced as a **wrong answer** instead of a
refusal.

That is worse than not detecting the bug at all: a refusal routes to the fallback and
the user still gets a correct answer, whereas a dropped diagnostic converts a caught
bug into a silent one. **A detector whose output is discarded is not a detector.** Any
future `markUnsupported`-style mechanism should be checked for a live path all the way
to something the user can observe.

---

## Things I tried that did **not** pan out (don't redo these)

- **Hypothesis: `ASSUME` / implicit-`ASSUME` params share the `factorial` bug.** I
  predicted the schema would mis-type them too. **Refuted** — 18/18 byte-identical at
  threshold-crossing inputs (`assume-as-given.cases.json`,
  `implicit-assume-test.cases.json`). `factorial` is specifically the **bare-head
  positional param** path (`DECIDE foo x IS` with no `GIVEN`), the only such example in
  the corpus. Its scope is narrow; don't go looking for an "untyped param" iceberg.
- **Design trap: suffixing symbols with the `Unique`'s `Int`.** Tempting, but
  `Unique.unique :: Int` is only unique _per module_ (there's a separate `moduleUri`
  field), so two modules could collide on the suffix. Used a **per-group index**
  (`__ov0`, `__ov1`) / a **monotonic counter** (`__loc0`, `__loc1`) instead.
- **Design trap: disambiguating exported overloads too.** `Schema.wasmSymbol` computes
  export symbols _independently_ and knows nothing about mangling — renaming an export
  would desync the schema from the wasm. Groups containing an `@export` member are
  therefore left colliding and stay `markUnsupported` (an exported same-arity collision
  is genuinely ambiguous at the JSON API anyway). This is also why the pre-existing
  `testOverloadCollisionUnsupported` still passes unchanged.
- **`d MODULO 7` on a DATE** is a jl4-core _type error_ — the library always bridges via
  `DATE_SERIAL`/`Day`. So the MODULO-boxing path in the date fix is unreachable from
  valid L4. Don't "fix" it.

---

## The one number that went _down_, on purpose

`byte-identical` **130 → 128**. Those two cells are `britishcitizen5::is-British-citizen`,
which now **refuses**. It stores dates as STRINGs and compares them with `GREATER THAN`
in a helper; there is no string-ordering builtin, so that helper was already flagged and
returning a hardcoded FALSE. The export shipped on top of it and was byte-identical only
because the single generated input happened to expect FALSE.

**A truthful refusal beats a lucky right answer** — a refusal routes to the fallback
evaluator and the user gets the right answer anyway. Do not read this as a regression,
and do not "recover" those two cells by reverting propagation.

---

## Still open — in priority order

See the status ledger at the top for the full picture; this is the recommended order of
attack.

1. ~~🔴 **`factorial`** (ledger #9)~~ — **✅ FIXED** by `enrichParamTypes` (L4.Export),
   the parameter-side sibling of `enrichReturnTypes`: a bare-head param with no GIVEN gets
   its type from the typechecker's inferred `Fun` type (positional zip against the leading
   given/head params; ASSUME-appended params are untouched; `InfVar`-containing types are
   left alone rather than baked into the schema as a differently-shaped lie). Schema now
   says `{"type":"number"}`, `marshalArg` builds a real rational handle, `factorial 5 =
120`. `desc.l4` is now in the **CI Tier-2 corpus**; its former-xfail `desc.cases.json`
   is 4/4 byte-identical. With this, **no known silent wrong answers remain**.
2. ~~🟡 **Bundle-wide L4 return-type map** (clears ledger #6)~~ — **✅ FIXED** by
   `funcL4Types` (`62f5f909`): the typechecker's substituted `EntityInfo`, projected to
   a `Map Unique (Type' Resolved)` covering every known term across the bundle.
   `classifyOperand` resolves an `App` operand through the callee's result type
   (`resultTypeAtArity`: saturated `Fun` → its return; partial application refuses),
   classified by `classifyGroundType` — a closed set of builtin scalar heads
   (NUMBER/STRING/BOOLEAN/DATE/TIME), because an entity's recorded type is the
   definition's _generic_ type and a type-variable return slot must not be trusted as a
   raw-f64 comparison key (that would be a silent wrong answer on `LIST OF a -> a`
   helpers at NUMBER instantiations; the rewritten Haskell test
   `tyvar-return cmp → supported:false` pins this). `is-a-weekday` now compiles
   natively: 3/3 byte-identical on branch-crossing dates (Mon/Sat/Sun) newly added to
   `datetime-probe.cases.json` (CI Tier-2). Tier-2 65+1 → **68+0**; extended corpus
   130+6 → **133 byte-identical, 5 refused**. Enum/record helper results still refuse
   (conservative) — widen `classifyGroundType` only with a way to tell a tyvar from a
   nullary type constructor.
3. ~~🟡 **String-ordering runtime builtin** (clears ledger #7)~~ — **✅ FIXED**.
   `__l4_str_cmp` (runtime, `jl4-runtime.mjs`) compares pooled strings
   lexicographically by Unicode **code point** — iterating `codePointAt`, NOT
   JS-native `<` (which orders UTF-16 code **units** and disagrees for
   astral-plane chars). Declared in `Runtime/Builtins.hs`; `lowerCmp`'s
   `CmpString` ordered arm now routes through it and re-applies the source
   predicate against `0.0`, exactly like `CmpNumber`/`__l4_rat_cmp`. The
   reference was pinned empirically first: jl4-service returns
   `"banana" > "apple" = true` even for a param typed `DECLARE Date IS A STRING`
   — i.e. it does **string** comparison and ignores the schema's `format:date`
   hint. The unicode trap (`"😀"` U+1F600 vs `""` U+E000 → code-point `+1`,
   code-unit `-1`) is pinned by both JS unit tests and the differential gate
   (`str-ordering-probe.cases.json`).

   Wiring `str_cmp` **exposed two latent bugs** that had been masked while
   `britishcitizen5` refused wholesale (a refusal routes to the fallback; a
   compiled export does not):
   - **Marshalling.** jl4-core's `typeToParameter` matches primitive type
     **names** (`date`) before consulting the declares table, so a userland
     `DECLARE Date IS A STRING` was schema'd `format:date` and the runtime's
     `marshalArg` parsed the input into a DATE **serial** — which `str_cmp`
     then read as a garbage pointer. Fixed WASM-side in `Schema.hs`
     (`unfoldSynonymType`): a `SynonymDecl` param is resolved to its underlying
     type **before** `typeToParameter` runs, so `Date` → `{"type":"string"}`
     and `marshalArg` writes a real string. Genuine builtin DATE is not a
     `SynonymDecl`, so it keeps `format:date` + serial marshalling
     (datetime-probe stays byte-identical).
   - **Classification.** The lowering **erases** synonym decls, so a comparison
     operand recovered from `bindingL4Types` arrived as an opaque `TyApp Place`
     head and `classifyL4Type` mis-read it as `CmpOther` → a raw `arith.cmpf`
     on string **pointers** (`"Gibraltar" == "Gibraltar"` → FALSE; also a
     latent handle-compare bug for NUMBER synonyms). Fixed with a
     `typeSynonyms` map on `LowerState` (`collectTypeSynonyms`) that
     `classifyOperand` unfolds through before classifying: `Place`/`Date`
     → STRING → `CmpString` → `__l4_str_eq`/`__l4_str_cmp`.

   Result: all **5** curated `britishcitizen5::is-British-citizen` cells (born
   before / **exactly on** / after each of the two date thresholds, UK and
   Gibraltar qualifying-territory paths) are byte-identical; Tier-2 stays 68+0.
4. ✅ **Ledger #8 investigated + honest-refusal fix landed** (see below) —
   `ceo-performance-award` is now differentially exercised by the harness (it refuses)
   and by a Haskell regression test; its two real gaps are documented and gated by
   `ceo-performance-award.cases.json.pending`.

### Ledger #8 resolved — `ceo-performance-award::Eligible Service Requirement`

**It was a code gap, not (only) a test gap.** The extended corpus flagged this export as
`refused-unsupported`, contradicting the coverage.json "clean". Root cause, established by
compiling the file and reading the emitted `.schema.json`:

1. **Incidental** — call-graph propagation from helper `Musk In Eligible Service`, which
   does `award state's Musk Service Status EQUALS Chief Executive Officer` (enum EQUALS on
   a record projection). `classifyOperand` can't resolve the projection's type, so
   `lowerCmp` refuses (ledger-#6 family, correct fail-closed). This is what currently
   downgrades the export.
2. **Fundamental** — `extractDeonticContract` (`Schema.hs`) returns `Nothing`, so the
   export has `isDeontic:true` but **no `deonticContract` tree**. Reasons: the top-level
   `IF` guard is a **helper-call application** (`Forfeiture Applies award state`) that
   `exprToGuard` doesn't represent (it handles only operators / projections / nullary
   vars → `Nothing`), and the maintain-service action carries a **`PROVIDED` guard** that
   `deontonToContract` **silently drops** (it never reads `action.provided`). Either would
   make an interpreted answer wrong.

Because interpreting this contract would risk a **silent wrong answer** (dropped `PROVIDED`
guard), the function MUST keep refusing — this is Outcome B under the refuse-vs-silent-wrong
bias. **The lane's change makes the refusal loud and structural** instead of an incidental,
maskable side-effect: `mkFunctionExport` now sets `supported:false` with a clear
DEONTIC-extraction reason whenever `isDeontic && deonticContract == Nothing`, and
`applyDiagnostics` **preserves** that reason (prepends it) rather than overwriting it with
the lowering diagnostics. This closes a latent landmine — had someone fixed gap (1) alone,
the export would otherwise have flipped to `supported:true` with a null contract and thrown
only at evaluate time.

Verification: `cabal test jl4-mlir` 34/34 (new: `deontic unextractable contract →
supported:false`). The 3 deontic fixtures (sale/seatbelt/breach) still extract non-null
contracts and stay `supported:true`. Harness (`--port 9931`) over
`ceo-performance-award + deontic-sale + deontic-seatbelt + deontic-breach`:
**8 byte-identical, 1 refused-unsupported, PARITY OK (0 parityFails).** Branch-crossing
cases (all three top-level branches: MUST-maintain / MAY-vest-immediately / MUST-forfeit)
were validated live against jl4-service and parked in
`jl4/examples/legal/ceo-performance-award.cases.json.pending` — **not** a live
`.cases.json`, because a curated cell for a refusing function would trip the harness's
partial-corpus-collapse guard. A full future fix (represent helper-call IF guards + carry
`PROVIDED`/`EXACTLY`) should additionally add fielded-action fulfilled/breach sequences —
but note those need a jl4-service events-codegen fix too: `CodeGen.hs:431`
(`fnLiteralToL4ExprWithType`) can't encode a sum-type-with-fields action
(`maintain eligible service status <Service Status>`), rendering it as the invalid
`Award Action WITH <ctor> IS …`.

## What a reviewer should actually check

- The propagation is **sound but conservative**: it flags an export that _transitively_
  reaches _any_ diagnosed function. It cannot know that a collided symbol happened to
  resolve to the _right_ body for _this_ caller. That's why fixing the collisions (which
  removes the diagnostics at the source) was a **prerequisite** for propagation — without
  it, `test.l4`'s `order-total` inherited a phantom refusal through the merged `go` node.
  Verify the ordering holds: no collision ⇒ no diagnostic ⇒ no refusal.
- `propagateDiagnostics` BFSes the **reversed** call graph with a visited set, so
  self-recursion and mutual recursion terminate. A function that is its own ancestor does
  not get a propagated copy of its own reason.
- The guard is real: `list-probe` is **12/12 byte-identical** here and **7/12 differs on
  the pre-fix build**. If you want to see the bug, `git stash` `Lower.hs` and re-run it.
