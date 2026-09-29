# OpenFisca

## What OpenFisca is

[OpenFisca](https://openfisca.org) is an open-source **microsimulation engine** for tax and benefit systems.
You describe a country's rules as a collection of _variables_ — `income_tax`, `housing_benefit`, `is_eligible` — each with a formula that computes it for an entity over a period, and OpenFisca works out the dependencies and runs them.

It is not a toy.
National and regional teams maintain OpenFisca models of real tax-benefit systems (France's is the original and largest), and policy analysts use them to answer questions no single case worker can: if this threshold moved by £500, who gains, who loses, and by how much across the whole population?

Two features shape everything about it.
**Periods**: every value is computed _for a month or a year_, and the rules themselves are dated, so you can ask what the law said in 2019 and what it says now.
**Entities**: values attach to a person, or to a group like a household, and OpenFisca knows how to aggregate a person-level value up to its household.

## Why compile L4 to it

An L4 decision over a subject and a period is structurally the same object as an OpenFisca `Variable` with a `formula(entity, period)`, so the mapping is close to one-to-one rather than an encoding.
Compiling to it means:

- **Your rules join an ecosystem built for policy questions.**
  Once the rules are OpenFisca variables, the analysis tooling around OpenFisca applies to them: population simulation, reform comparison, marginal-rate analysis.
- **A team already running OpenFisca can adopt your rules without adopting L4.**
  They receive an ordinary Python module that behaves the way their existing ones do.
- **Dated law can be expressed the way OpenFisca expresses it.**
  A decision whose body is a `BRANCH` guarded by `period reaches` becomes a set of dated formulas (`formula_2016_12`, …), and a legislation parameter whose value changes by year becomes an OpenFisca parameter with dated values.
  Other year conditions are ordinary comparisons: `IF period's year AT LEAST 2015 …` in a decision body compiles to a comparison on the period's start year, not to a dated formula.
- **Household structure survives.**
  A record with a `LIST OF Person` field becomes an OpenFisca group entity with roles, so per-person values can be aggregated across the household.

## The command

```
l4 export openfisca FILE
```

Compiles the decision-rule subset of `FILE` to a single runnable OpenFisca Python module, printed to standard output.

| Flag                  | Effect                                                 |
| --------------------- | ------------------------------------------------------ |
| `-o`, `--output FILE` | write the generated Python to `FILE` instead of stdout |

The command exits 0 when it has written the module.
It exits 1 when the file does not typecheck, and when any part of the file is outside the subset below.
In the second case it writes nothing and lists every refusal on standard error, one line per problem, naming the decision or parameter concerned where there is one, and saying what to do instead.

**The export never guesses.**
Anything it does not fully understand is refused rather than approximated, because an approximation here compiles cleanly and then returns a different number from L4.
`jl4/examples/openfisca/not-ok/` holds one small file for each refusal, and those files are the most precise statement of the limits.

## What it compiles

| L4                                                                                 | OpenFisca                                                                       |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| an `@export` decision                                                              | a `Variable` with a `formula`                                                   |
| the decision's first input whose type is a record of this file (its _subject_)     | the entity the variable belongs to                                              |
| an input named `period`                                                            | the formula's `period`; the variable is computed per `MONTH`                    |
| no input named `period`                                                            | `definition_period = ETERNITY`                                                  |
| the subject record's stored fields, and the decision's other inputs                | input variables, with no formula                                                |
| `p's field`                                                                        | `person('field', period)`                                                       |
| `period's year`, `period's month`                                                  | `period.start.year`, `period.start.month`                                       |
| `+ - * /`, `MODULO`, `25%`, comparisons, `AND OR NOT IMPLIES`                      | numpy arithmetic, `&` `\|` `~`                                                  |
| `IF … THEN … ELSE`, `BRANCH IF … OTHERWISE`                                        | `np.where`                                                                      |
| `max`, `min` from the prelude                                                      | `np.maximum`, `np.minimum`                                                      |
| `CONSIDER x WHEN A THEN … OTHERWISE …` over an enum of this file                   | `np.where` over the enum's members                                              |
| a call to another `@export` decision, passing the subject and `period` as they are | `entity('other_decision', period)`                                              |
| a record with `LIST OF` fields of one member record                                | a group entity; each list field is a role                                       |
| `sum (map (GIVEN m YIELD …) (h's members))`                                        | `household.sum(…)`, restricted to the role when there are several               |
| `count (h's members)`, `any (GIVEN m YIELD …) …`, `all (GIVEN m YIELD …) …`        | `household.nb_persons(…)`, `household.any(…)`, `household.all(…)`               |
| a value annotated `@desc parameter taxes.rate`                                     | an OpenFisca parameter at `taxes.rate`, read as `parameters(period).taxes.rate` |
| a value annotated `@desc scale taxes.contribution`, used with `scale tax`          | a marginal-rate scale, applied with `.calc(…)`                                  |
| a decision body `BRANCH IF period reaches OF period, 2016, 12 THEN … OTHERWISE …`  | dated formulas `formula_2016_12`, …, and an undated `formula`                   |

A **legislation parameter** is written as a value whose body is a number, `IF y AT LEAST 2015 THEN 200 ELSE 100`, or a `BRANCH` of such arms written newest year first, where `y` is the value's own single input.
`y GREATER THAN 2015` is also accepted, and means the value changes on 1 January 2016.
A decision reads it as `rate` (no input) or `rate OF period's year`.

A **marginal-rate scale** is a `LIST` of brackets `(band OF threshold, rate)` in increasing threshold order, or a `BRANCH` of such lists by year, newest first, each list at least as long as the ones before it.

## What it refuses, and why

Most of these used to compile and then either give a different answer from L4 or fail inside OpenFisca.

| Refused                                                                                                                                                  | Why                                                                                  | Instead                                                                |
| -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| a field, input or result of type `DATE`, `MAYBE …`, a record, a `LIST` of anything but a record of this file                                             | OpenFisca has no value type for it here                                              | a field of a supported type, e.g. a year as a `NUMBER`                 |
| an enum whose constructors carry fields, or a decision that returns an enum                                                                              | an OpenFisca `Enum` carries no fields, and this export compiles enums only as inputs | one `BOOLEAN` or `NUMBER` decision per case                            |
| a call to a helper that is not `@export`                                                                                                                 | an OpenFisca formula takes no arguments; the export does not inline helpers          | mark the helper `@export`, or write its body out                       |
| a call to an `@export` decision with any argument other than the subject (or member) and `period`, unchanged                                             | OpenFisca always reads a variable for the same entity and period                     | give the other value its own input, or compute it in the same decision |
| a call to a decision that lives on another entity, outside an aggregation                                                                                | OpenFisca reads a person's variable from a household only through an aggregation     | `sum`, `count`, `any` or `all` over the members                        |
| inside an aggregation: a field or input of the group, a nested aggregation, or an expression that never reads the member                                 | OpenFisca aggregates one value per member                                            | compute the group value in its own decision                            |
| a computed (`MEANS`) field                                                                                                                               | the export does not inline it                                                        | make it an `@export` decision                                          |
| `CONSIDER` with an arm that is not a bare constructor, or with `OTHERWISE` anywhere but last                                                             | such arms used to be dropped, or compiled although L4 never reaches them             | bare constructors, one final `OTHERWISE`                               |
| a parameter guard whose left side is not the year input, whose year is not a whole number, or arms oldest first                                          | the guard used to be read as a date regardless, or in the wrong order                | `y AT LEAST <year>`, newest first                                      |
| a parameter called with anything but its own period's year                                                                                               | OpenFisca reads a parameter at the formula's period                                  |                                                                        |
| two parameters at one path, a path that is not an identifier path, or brackets out of order                                                              | the parameter tree would be wrong, or the path would run as Python                   |                                                                        |
| `period's` fields other than `year` and `month`                                                                                                          | they have no OpenFisca meaning                                                       |                                                                        |
| more than one person entity, a record that is both a group and the person entity, a group of groups, or a group whose list fields name different records | OpenFisca needs exactly one person entity, and one member entity per group           | export them from separate files                                        |
| two roles with the same key, a role named like a variable, or two definitions with the same Python name                                                  | the emitted module would not load, or a situation could not tell them apart          | rename one                                                             |
| a name that is not ASCII after conversion (e.g. `area m²`)                                                                                               | Python would reject it                                                               | rename it                                                              |
| deontic rules (`PARTY … MUST`), `EVENT`, `WHERE` / `LET`, lambdas outside aggregations, list literals, recursion                                         | none of these is an OpenFisca variable                                               |                                                                        |

## What it recognises by name

A few names are compiled to OpenFisca's own operations rather than to formulas.
Each is checked, so a definition of your own under one of these names is refused rather than silently replaced:

- **`sum`, `map`, `count`, `any`, `all`, `max`, `min`** are compiled only when they are the prelude's.
  A file that defines its own `sum` gets a refusal naming where its `sum` came from.
- **`period reaches`** and **`scale tax`** are written in your own file, and accepted only when the definition is the canonical one, up to the names of its inputs.
  The refusal prints the canonical definition; the `basic-income` and `scale` examples carry it too.
- **`members of`** must return every `LIST OF` field of the group.
- **The bracket builder** (`band` in the examples, any name) must put its first input in `threshold` and its second in `rate`.
- **An input named `period`** is the period, and a decision without one is not per-period.

## Names in the generated module

OpenFisca names are Python identifiers, so every L4 name is converted, and the conversion is the one you use when you write an OpenFisca _situation_ (the JSON or Python dictionary that says who is in the simulation and what their inputs are):

- **Variables** are the L4 name in `snake_case`: `flat tax on salary` becomes `flat_tax_on_salary`, and a field `salary` stays `salary`.
  Letters are lower-cased, runs of spaces and punctuation become one `_`, a leading digit gets `v_`, and a name that is a Python keyword, or `period`, `parameters`, `entity`, `formula`, `np` or `build_entity`, gets a trailing `_`.
- **Enum members** are converted the same way, and a situation must use the converted name: `'employed'`, not `'Employed'`, and `'self_employed'` for `Self Employed`.
  OpenFisca's own error lists the valid names if you get one wrong.
- **Entities** keep the record's name as the Python class (`Household`); the situation key is the lower-cased name plus `s` (`households`, `persons`, and `companys` for `Company`).
  A decision with no record subject belongs to a default `Person` entity.
- **Roles** are the `LIST OF` field names: a situation lists members under the field name (`"adults": ["alice", "bob"]`).
  The role's key drops one trailing `s` (`adults` becomes `adult`) unless the name ends in `ss`, `us` or `is` (`status` stays `status`).

## What doesn't survive

- **Exact rationals become float32.**
  OpenFisca stores `value_type = float` as numpy **float32**, while L4 `NUMBER` is an exact rational.
  Results diverge past roughly seven significant digits — `16777217` comes back as `16777216.0` — and decimal round-off accumulates.
  For money in cents, large aggregates or high-precision rates, treat OpenFisca output as float32-approximate.
- **An omitted enum input defaults to the first declared member.**
  OpenFisca answers with that member when the input is absent, so order your `DECLARE … IS ONE OF` such that the first listed value is the safe one.
  This is a convention the export relies on, not something it checks.
- **`np.where` evaluates both branches.**
  A division guarded by an `IF` can print a numpy division-by-zero warning for the rows the guard excludes; the result is still the guarded one.

## Running the output

The generated module needs Python with `openfisca-core` and `numpy`.
The examples are checked with Python 3.12, openfisca-core 45.0.4 and numpy 2.1.3:

```sh
uv venv --python 3.12 ~/of-venv
uv pip install --python ~/of-venv/bin/python openfisca-core==45.0.4 numpy==2.1.3
```

To check that OpenFisca computes what L4 computes for one of the examples, export it and run the round-trip script, which prints `ROUND-TRIP OK` only after every check has passed:

```sh
l4 export openfisca jl4/examples/openfisca/household.l4 -o /tmp/household.py
~/of-venv/bin/python jl4/examples/openfisca/roundtrip_check.py /tmp/household.py household
```

The script's expected numbers are copied from each example's `#ASSERT`s.
A pass shows that L4 and OpenFisca agree, not that either matches the law.

To run the round-trip over every example from the test suite, set `L4_OPENFISCA_CHECK=1` and point `L4_OPENFISCA_PYTHON` at that interpreter when running `l4-cli-test`.
Without them, those cases are reported as pending rather than passed.

## Where to look

- **Worked examples:** `jl4/examples/openfisca/`, with one refused file per limit in `not-ok/`.
- **The bridge's own reference:** `jl4/examples/openfisca/L4-OPENFISCA.md`, which walks the examples and records what the tests prove.
