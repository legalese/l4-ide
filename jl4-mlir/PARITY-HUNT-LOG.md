# The parity hunt — session log & reviewer's guide

A narrative companion to the four `mlir-review` commits below. The commit messages
say _what_ each fix does; this says _why the bugs existed_, _how they were found_,
_what was tried and rejected_, and _what is still open_. Read this first, then the
commits.

| commit     | what                                                       |
| ---------- | ---------------------------------------------------------- |
| `7c61c21f` | the hunt: curated `cases.json` across the corpus           |
| `b2ac28f3` | Finding 2 — DATE-operand arithmetic crash (ABI split)      |
| `692e0f0b` | same-arity overload collision (`Weekday of`)               |
| `a68195f2` | call-graph diagnostic propagation → prelude `go` collision |

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
| 6   | **`is-a-weekday`** — helper-result NUMBER comparison unclassifiable       | 🟡    | refuses; see open #2                | `datetime-probe` (excluded from cases)              |
| 7   | **`britishcitizen5`** — ordered comparison on STRING-typed dates          | 🟡    | refuses; no string-ordering builtin | corpus (2 cells now `refused`)                      |
| 8   | **`ceo-performance-award`** — deontic, refuses; never actually tested     | 🟡    | needs event `cases.json`            | — (this is the gap)                                 |
| 9   | **`factorial`** — bare-head param typed `{"type":"object"}` → returns `1` | ✅    | `enrichParamTypes` (Export.hs)      | `desc.cases.json` — **CI Tier-2** (+ Haskell)       |
| 10  | **`orchestrator::evaluateClaim`** — `CONSIDER` ctor `RIGHT` unresolved    | 🟡    | pre-existing refusal                | corpus                                              |
| 11  | **`mixfix-garden-path::tax-on`** — _exported_ same-arity collision        | 🟡    | **by design** (see below)           | Haskell `overload collision → supported:false`      |

**There are no remaining 🔴s.** With #9 fixed, the extended corpus gate passes for the
first time: **130 byte-identical, 0 differs, 0 wasm-error, 6 honest refusals**. Every
known divergence either computes correctly or refuses honestly and routes to the
fallback. (That claim is bounded by the corpus and the curated cases — the thesis below
explains why "no known reds" and "no reds" are different statements.)

**#11 is deliberate, not a to-do.** An `@export`ed same-arity collision is genuinely
ambiguous at the JSON API (the caller cannot say which overload it meant), so it stays
`markUnsupported` on purpose. Disambiguating it would also desync `Schema.wasmSymbol`.

### The capability gaps behind the 🟡s

Each 🟡 refuses because of exactly one missing capability. None of them is a
correctness bug any more — they are unimplemented features that the backend now has the
good manners to admit to.

- **Bundle-wide L4 return-type map** → clears #6. `funcSigs` stores only MLIR types (all
  `f64`), so a comparison on a _helper's result_ can't be classified.
- **A string-ordering runtime builtin** → clears #7.
- **Event-shaped deontic `cases.json`** → clears #8 (a test gap, not a code gap).
- **`CONSIDER` constructor resolution for `RIGHT`** → clears #10 (pre-existing; predates
  this branch).

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
2. 🟡 **Bundle-wide L4 return-type map** (clears ledger #6) — `funcSigs` stores only MLIR
   types (all `f64`), so `lowerCmp` cannot classify a comparison whose operand is a
   _helper's result_. It fails loud, which is correct, and is why `is-a-weekday` refuses
   rather than compiling. This is the last thing between `is-a-weekday` and native
   compilation.
3. 🟡 **String-ordering runtime builtin** (clears ledger #7) — would let
   `britishcitizen5` compile natively and recover the 2 cells that moved out of
   `byte-identical`.
4. 🟡 **Deontic event `cases.json`** (clears ledger #8) — `ceo-performance-award` refuses
   rather than being _tested_. A test gap, not a code gap.

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
