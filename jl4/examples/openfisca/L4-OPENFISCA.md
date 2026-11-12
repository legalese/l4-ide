# From legislation to OpenFisca, via L4

**A readable, type-checked source layer that compiles to OpenFisca — so the
policy owner can validate the rules by eye, and the engine still runs in
OpenFisca.**

This document outlines the construct-by-construct correspondence between
[OpenFisca](https://openfisca.org) and [L4](https://github.com/legalese/l4-ide),
argues where the L4 *isomorphism* advances the state of the art, and walks a
toolchain that starts from legislation, passes through human-readable L4, and
transpiles to runnable OpenFisca — with the validating test outputs shown
end-to-end.

---

## 1. The toolchain

```
   ┌──────────────┐   isomorphic    ┌──────────────┐   l4 export openfisca   ┌──────────────┐
   │ legislation  │  formalisation  │      L4      │  (this bridge)   │  OpenFisca   │
   │ / regulation │ ──────────────▶ │  .l4 source │ ───────────────▶ │   Python     │
   └──────────────┘                 └──────────────┘                  └──────────────┘
                                       │      ▲                          │
                            #EVAL /    │      │  human review            │  openfisca
                            #ASSERT     ▼      │  (no Python needed)      ▼  test / API
                                    ┌─────────────────┐            ┌─────────────────┐
                                    │  same numbers   │  ◀────────▶│  same numbers   │
                                    └─────────────────┘ conformance└─────────────────┘
```

The pivot is the middle column. Today, encoding legislation as OpenFisca means
writing **vectorised NumPy** directly — `condition * amount`, `where(...)`,
`household.sum(household.members(...))`. That is the right *execution* model, but
it is not something a policy owner, a lawyer, or a legislative drafter can read,
let alone validate against the statute they are responsible for.

L4 is designed to be that readable layer. The L4 source mirrors the **structure
of the legislation** (its conditions, thresholds, definitions, and cross-
references) using real Booleans, `IF/THEN/ELSE`, typed records, and named
helpers. The OpenFisca Python is then a *compilation artifact* — generated, not
hand-maintained.
Generation keeps the two in step only as far as the compiler is faithful.
The export refuses whatever it cannot compile faithfully rather than guessing, and §5 lists what checks the two against each other; outside the shapes those checks cover, agreement is a property of the compiler, not something a test has observed.

**Why the policy owner cares:** they review the L4, not the Python. The L4 says
`IF (p's age >= 18) AND (p's salary EQUALS 0) THEN 600 ELSE 0`; the OpenFisca
says `np.where((person('age', period) >= 18) & (person('salary', period) == 0),
600, 0)`. Both compute the same thing; only one is reviewable by a non-
programmer.

---

## 2. Correspondence: OpenFisca ↔ L4

| OpenFisca | L4 | Notes |
|---|---|---|
| `class X(Variable)` with a `formula` | `@export` … `GIVEN subject period … MEANS …` | a named computation over named inputs |
| `entity = Person` | the subject parameter's record type | subject's type *is* the entity |
| `definition_period = MONTH` | a conventional `period` parameter | threaded to the formula's `period` |
| `value_type = float / bool / str / int` | `GIVETH A NUMBER / BOOLEAN / STRING` | mapped by L4's type |
| input variable (no formula) | a stored record field / free scalar param | set by the caller |
| `person('salary', period)` | `p's salary` | field projection on the subject |
| `entity('other_var', period)` | a call to another `@export` decision | decisions reference each other |
| `+ - * /`, `< <= > >= ==` | same operators | vectorised numpy on the Python side |
| `&` / `\|` / `np.logical_not` (numpy boolean) | `AND` / `OR` / `NOT` | L4 keeps real Booleans; `~` would invert a Python bool to -1 or -2, both true |
| `np.where(cond, t, e)` | `IF cond THEN t ELSE e` | the readable form of the "vectorial if" |
| **group entity** `build_entity(..., roles=[...])` | a record with `LIST OF Person` fields | each list field → a role |
| `household.members('x', period)` | `m's x` inside `map (GIVEN m YIELD …)` | member-array read |
| `household.sum(household.members('salary', period))` | `sum (map (GIVEN m YIELD m's salary) (h's members))` | aggregate over members |
| `household.nb_persons()`, `household.any(…)`, `household.all(…)` | `count (h's members)`, `any (GIVEN m YIELD …) …`, `all (GIVEN m YIELD …) …` | `role=` when the group has several roles |
| `class X(Enum)` and `np.where(v == X.a, …)` | `DECLARE X IS ONE OF a, b` and `CONSIDER … WHEN a THEN …` | constructors without fields; `OTHERWISE` last |
| `parameters(period).taxes.rate` | a value annotated `@desc parameter taxes.rate` | a number, or year-guarded numbers newest first |
| `parameters(period).taxes.scale.calc(income)` | `scale tax OF income, brackets`, `brackets` annotated `@desc scale taxes.scale` | marginal-rate brackets, by year |
| `formula_2016_12` and friends | a decision body `BRANCH IF period reaches OF period, 2016, 12 THEN …` | every arm guarded that way, newest first |

What the bridge refuses, and why, is listed in [`doc/exports/openfisca.md`](../../../doc/exports/openfisca.md), with at least one file in `not-ok/` for each kind of refusal.

---

## 3. How the L4 isomorphism advances the state of the art

OpenFisca is excellent at *executing* tax-benefit logic at population scale. The
gap it leaves — and that L4 fills — is everything *upstream* of execution:

1. **Readability for the rule owner.** OpenFisca formulas are branch-free
   vectorised arithmetic by necessity. L4 keeps the legislative shape: real
   conditionals, named conditions (`is single`, `has child under 8`), typed
   records. The person accountable for the policy can read and sign off on the
   L4. The `condition * amount` idiom becomes a *lowering artifact* they never
   have to see.

2. **One source, validated two ways.** The same L4 file carries executable
   tests (`#EVAL`, `#ASSERT`). The bridge compiles it to OpenFisca, where the
   *same* scenarios run through `openfisca test` / the calculation API. When both
   produce the same numbers, the translation itself is validated — not assumed.
   (Every example below shows this round-trip.)

3. **Types and totality.** L4 is type-checked. A `salary` that should be a
   number, a `Household` that must have members, a decision that must return a
   Boolean — these are checked before anything runs, catching a class of errors
   that surface late (or never) in loosely-typed Python.

4. **Compile target, not lock-in.** Because the L4 is the source of truth and
   OpenFisca is a backend, the *same* L4 can target other backends (a consumer-
   facing web wizard, a documentation renderer, a formal-methods checker). The
   bridge makes OpenFisca one first-class destination among several, rather than
   the place the logic is trapped.

5. **Isomorphic to the statute.** L4's design goal is that the formal text lines
   up clause-for-clause with the legislation, so a reviewer can check the
   encoding against the source law. OpenFisca's structure is organised around the
   engine, not the statute; L4 lets you keep the statute's structure and *derive*
   the engine's.

None of this competes with OpenFisca — it complements it. OpenFisca remains the
runtime and the ecosystem (country packages, YAML tests, the web API). L4 becomes
the human-facing, type-checked, statute-aligned source that feeds it.

---

## 4. Worked examples (with validating outputs)

Each example is a real `.l4` file in this directory. `l4 export openfisca FILE` emits
the OpenFisca module; the numbers below are produced by **running that emitted
module in OpenFisca** and confirming they match the L4 `#ASSERT` values.

### 4.1 `flat-tax.l4` — the OpenFisca textbook example

L4:
```l4
GIVEN p IS A Person, period IS A STRING
GIVETH A NUMBER
`flat tax on salary` p period MEANS (p's salary) * 0.25
```
emits a `flat_tax_on_salary(Variable)` whose formula is
`person('salary', period) * 0.25`.

Round-trip: `salary = 2000 → flat_tax_on_salary = 500.0` ✓ (L4 `#ASSERT`: 500).

### 4.2 `benefit.l4` — conditionals, Booleans, cross-decision calls

```l4
`eligible for benefit` h period MEANS
  (h's income) < 2000 AND (h's dependents) > 0

`monthly benefit` h period MEANS
  IF `eligible for benefit` h period
  THEN 500 + (h's dependents) * 100
  ELSE 0
```
`AND` → `&`, `< / >` → comparisons (fully parenthesised so numpy's operator
precedence is correct), `IF/THEN/ELSE` → `np.where`, and one decision reads
another via `household('eligible_for_benefit', period)`.

Round-trip: `eligible → True`, `monthly_benefit → 700.0` (income 1500, 2
dependents) and `0.0` (income 3000) ✓ — matching the L4 `#ASSERT`s.

### 4.3 `household.l4` — group entity + `LIST OF` aggregation

```l4
DECLARE Household HAS members IS A LIST OF Person

`household income` h period MEANS
  sum (map (GIVEN m YIELD m's salary) (h's members))
```
`LIST OF Person` makes `Household` an OpenFisca **group entity** (with a member
role); the `sum (map …)` becomes
`household.sum(household.members('salary', period))`.

Round-trip: members earning 1000 and 1500 → `household_income = 2500.0` ✓
(L4 `#ASSERT`: 2500).

---

## 5. Reproduce it

```sh
# emit
cabal run l4 -- export openfisca jl4/examples/openfisca/household.l4 -o /tmp/household.py

# run it in real OpenFisca and check the numbers match the L4 #ASSERTs
uv venv --python 3.12 /tmp/of && uv pip install --python /tmp/of/bin/python openfisca-core==45.0.4 numpy==2.1.3
/tmp/of/bin/python jl4/examples/openfisca/roundtrip_check.py /tmp/household.py household
```

The golden output of every example is pinned in `expected/` and checked by the
`l4 export openfisca` cases in `jl4/tests-cli/CliTest/OpenFisca.hs`.
The same module checks every refusal in `not-ok/`, runs every `#ASSERT`, and, with `L4_OPENFISCA_CHECK=1`, runs the round-trip below over every example.

---

## 6. Caveats — and what the tests actually prove

This bridge has been through an adversarial review. Be precise about its limits.

### Numeric model
OpenFisca stores `value_type = float` as **numpy float32**, whereas L4 `NUMBER`
is an exact rational. So results can diverge once values exceed ~7 significant
digits or ~16.7 million (e.g. `16777217 → 16777216.0`), or accumulate decimal
round-off beyond the round-trip's `1e-6 tolerance` (`10000.001 → 10000.0009765625`).
For money in cents, large aggregates, or high-precision rates, treat the
OpenFisca output as float32-approximate, not exact.

### Defaults and conventions
- **Enum `default_value` is the first declared member** (must hold, not checked).
  When an enum input is omitted from a situation, OpenFisca answers with that member.
  Order your `DECLARE … IS ONE OF` so the first listed value is the safe/natural default.
- **Some names are recognised** (checked).
  `members of` must return every `LIST OF` field of the group; `period reaches` and `scale tax` must match their canonical definitions; `sum`, `map`, `count`, `any`, `all`, `max` and `min` must be the prelude's.
  A definition that differs is refused, naming the difference, rather than silently replaced by OpenFisca's meaning.
- **Dated-formula, scale and parameter BRANCH arms must be written newest-first** (checked).
  Each of the three is refused otherwise, with a message saying so; a caller of a refused parameter is refused with a message pointing at it.

### What "round-trip passes" means
The verification has two tiers, and a green check means different things:

- **Golden tests** (`tests-cli`, run in CI) are **regression-only** — they pin
  that `l4 export openfisca` keeps emitting the same `.py`. They prove nothing about
  semantics.
- **Refusals** (`tests-cli`, run in CI) pin that each construct in `not-ok/` is refused with a message naming the problem.
- **Assertions** (`tests-cli`, run in CI) run every `#ASSERT` in the examples and in `not-ok/`, so the L4 side of each comparison is itself checked.
- **Round-trips** (`roundtrip_check.py`; in `tests-cli` only with `L4_OPENFISCA_CHECK=1`, so not in CI) genuinely execute the emitted module in real OpenFisca.
  The expected numbers are copied by hand from the examples' `#ASSERT`s, not read from L4.
  So a pass shows **L4 and OpenFisca agree on those scenarios** — *not* that either matches the real-world law.

In short: on the shapes in these examples, the emitted OpenFisca computes what the L4 computes, and the shapes the export cannot compile faithfully are refused.
No test in this tree checks these numbers against a statute or against an independent OpenFisca model; `basic-income` is modelled on the OpenFisca `country-template` variable of that name, but nothing here compares the two.
