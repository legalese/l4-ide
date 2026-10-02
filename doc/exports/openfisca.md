# OpenFisca

## What OpenFisca is

[OpenFisca](https://openfisca.org) is an open-source **microsimulation engine** for tax and benefit
systems. You describe a country's rules as a collection of _variables_ — `income_tax`,
`housing_benefit`, `is_eligible` — each with a formula that computes it for an entity over a
period, and OpenFisca works out the dependencies and runs them.

It is not a toy. National and regional teams maintain OpenFisca models of real tax-benefit systems
(France's is the original and largest), and policy analysts use them to answer questions no single
case worker can: if this threshold moved by £500, who gains, who loses, and by how much across the
whole population?

Two features shape everything about it. **Periods**: every value is computed _for a month or a
year_, and the rules themselves are dated, so you can ask what the law said in 2019 and what it
says now. **Entities**: values attach to a person, or to a group like a household, and OpenFisca
knows how to aggregate a person-level value up to its household.

## Why compile L4 to it

An L4 `DECIDE` over a subject and a period is structurally the same object as an OpenFisca
`Variable` with a `formula(entity, period)` — so the mapping is close to isomorphic rather than an
encoding. Compiling to it means:

- **Your rules join an ecosystem built for policy questions.** Once the rules are OpenFisca
  variables, the analysis tooling around OpenFisca applies to them: population simulation,
  reform comparison, marginal-rate analysis.
- **A team already running OpenFisca can adopt your rules without adopting L4.** They receive an
  ordinary Python module that behaves the way their existing ones do.
- **Dated law works properly.** OpenFisca is the one export that consumes L4's temporal layer:
  year-guarded rules lower to OpenFisca's dated `formula_YYYY_MM` overrides, so "the rate before
  April 2023" is expressed the way OpenFisca already expresses it.
- **Household structure survives.** A record with a `LIST OF Person` field becomes an OpenFisca
  group entity with roles, so per-person values can be aggregated across the household.

## The command

```
l4 export openfisca FILE
```

Compiles the decision-rule subset of `FILE` to a single runnable OpenFisca Python module, printed
to standard output.

| Flag            | Effect                                                 |
| --------------- | ------------------------------------------------------ |
| `--output FILE` | write the generated Python to `FILE` instead of stdout |

## What it consumes

The **decision-rule subset**, mapped as follows:

| L4                                           | OpenFisca                                              |
| -------------------------------------------- | ------------------------------------------------------ |
| `@export` `DECIDE`/`MEANS` returning a value | a `Variable` with a `formula`                          |
| subject parameter `GIVEN p IS A <Record>`    | the entity — the subject's record type _is_ the entity |
| a conventional `period` parameter            | the formula's `period` argument                        |
| stored record fields, free scalar parameters | input `Variable`s, with no formula                     |
| a call to another `@export` decision         | `entity('other_var', period)`                          |
| a record with `LIST OF Person` fields        | a group entity, each list field becoming a role        |

## What `TYPICALLY` becomes

OpenFisca gives every variable a default of its own when a simulation leaves it out: `0.0` for a
number, `False` for a boolean, `''` for a string. An enum has none of its own, so the export has
always written the first member. A rule that says an input is _typically_ 3 must not be turned into
one that says it is 0, so **this export maps every default**: a `TYPICALLY` on a record field or on
a rule's own `GIVEN` becomes that input variable's `default_value`.

```l4
DECLARE Claimant HAS
    income        IS A NUMBER
    `hours a week` IS A NUMBER TYPICALLY 40

GIVEN c IS A Claimant
      rate IS A NUMBER TYPICALLY 3
```

```python
class hours_a_week(Variable):
    value_type = float
    default_value = 40.0
    …
class rate(Variable):
    value_type = float
    default_value = 3.0
    …
```

An enum default is the member you wrote (`TYPICALLY married` gives `default_value = Status.married`),
not the first one declared. A simulation that supplies the input overrides the default, as it should.

What it refuses, loudly, because OpenFisca has no value to give it:

- **`NOTHING`.** Every OpenFisca variable has a value; there is no "no value". The export refuses
  it even for a field that no decision reads, because every stored field of the subject becomes an
  input variable whether or not a formula uses it.
- **A default on the subject or on `period`.** Those come from the simulation, not from an input
  variable, so there is nothing for a default to attach to.
- **A default on a `LIST OF` field, other than `EMPTY`.** A role has no default list, so any other
  default would be lost. `EMPTY` says what a role nobody fills already is, so it is accepted and
  changes nothing in the output.
- **Two exported decisions that give one input different defaults.** OpenFisca has one variable of
  that name and so one default; the export names both and stops rather than pick one. "Different"
  means different in OpenFisca, where a decision that writes no `TYPICALLY` gets OpenFisca's own
  default for the type: `TYPICALLY 3` against none is refused (taking it would change what the
  undefaulted decision answers), while `TYPICALLY 0` against none, `FALSE` against none, or an
  enum's first member against none is not, because the variable is the same either way.

(An expression default is not accepted by the checker yet. When it is, the export turns it into a
`formula` on the input variable, which OpenFisca computes only for a period left without an input
value, and refuses one that the formula lowering cannot express. A default that names another input
is an expression like any other, and becomes a formula too.)

A `TYPICALLY` on a section `GIVEN` or an `ASSUME` never reaches this point: the export reads neither,
and refuses a rule that does (`unbound reference`).

## What doesn't survive

OpenFisca does not emit a fidelity report; these are the caveats the bridge's own review recorded,
and they are worth reading before you trust a number.

- **Exact rationals become float32.** OpenFisca stores `value_type = float` as numpy **float32**,
  while L4 `NUMBER` is an exact rational. Results diverge past roughly seven significant digits —
  `16777217` comes back as `16777216.0` — and decimal round-off accumulates. For money in cents,
  large aggregates or high-precision rates, treat OpenFisca output as float32-approximate.
- **An omitted enum input with no `TYPICALLY` defaults to the first declared member.** OpenFisca
  answers with that member when the input is absent, so order your `DECLARE … IS ONE OF` such that
  the first listed value is the safe one. This is a convention the bridge relies on, not something
  it checks. An input that _does_ carry a `TYPICALLY` is different, and is covered next.

## Where to look

- **Worked examples:** `jl4/examples/openfisca/`
- **The bridge's own reference:** `jl4/examples/openfisca/L4-OPENFISCA.md`, which carries the full
  mapping table and the caveats above in §6.
