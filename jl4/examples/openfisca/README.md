# L4 → OpenFisca examples

`l4 export openfisca FILE` compiles the **decision-rule subset** of an L4 file into a single, runnable [OpenFisca](https://openfisca.org) Python module.
An L4 `DECIDE`/`MEANS` over a _subject_ and a _period_ is structurally the same thing as an OpenFisca `Variable` with a `formula(entity, period)`, so the mapping is close to one-to-one.

The user-facing page is [`doc/exports/openfisca.md`](../../../doc/exports/openfisca.md): what the export compiles, what it refuses and why, which names it recognises, how L4 names become Python names, and how to run the output.
[`L4-OPENFISCA.md`](L4-OPENFISCA.md) walks the examples construct by construct.

## Files

| file                  | what it shows                                                                           |
| --------------------- | --------------------------------------------------------------------------------------- |
| `flat-tax.l4`         | the OpenFisca textbook example (`flat_tax_on_salary`)                                   |
| `benefit.l4`          | comparisons, `IF/THEN/ELSE`, a boolean decision, one decision calling another           |
| `household.l4`        | a group entity (`LIST OF Person`) and `sum` over its members                            |
| `roles.l4`            | two roles, `count` / `any` / `all`, and `members of`                                    |
| `housing.l4`          | an enum input and `CONSIDER`                                                            |
| `agecheck.l4`         | a member's own decision called inside an aggregation                                    |
| `dated.l4`            | dated formulas (`BRANCH IF period reaches …` → `formula_YYYY_MM`)                       |
| `incometax.l4`        | a scalar legislation parameter whose value changes by year                              |
| `scale.l4`            | a time-varying marginal-rate scale (`@desc scale`, `scale tax`)                         |
| `basic-income.l4`     | the country-template `basic_income`: dated formulas plus scalar parameters              |
| `not-ok/*.l4`         | one file per construct the export refuses; each says why in its header, and asserts what L4 computes |
| `expected/*.py`       | the committed golden output of each example                                             |
| `roundtrip_check.py`  | runs a generated module in real OpenFisca and checks it against numbers copied from the example's `#ASSERT`s |

## What checks them

`jl4/tests-cli/CliTest/OpenFisca.hs`, in `l4-cli-test`:

- each example's output must equal its golden in `expected/`;
- each `not-ok/` file must be refused, with a given fragment of its message;
- every `#ASSERT` in every example and `not-ok/` file must be satisfied under `l4 run`;
- with `L4_OPENFISCA_CHECK=1` and `L4_OPENFISCA_PYTHON` naming a Python that has openfisca-core and numpy, `roundtrip_check.py` runs over every example (otherwise those cases are pending).

The positive fixtures under `jl4/tests-cli/fixtures/openfisca/` are checked the same way.
This directory is in no `jl4-test` glob, so nothing else runs these files.

## Regenerate a golden

Run the export, then read the diff before committing it:

```sh
cabal run l4 -- export openfisca jl4/examples/openfisca/flat-tax.l4 -o jl4/examples/openfisca/expected/flat-tax.py
```

## Run an example in real OpenFisca

```sh
uv venv --python 3.12 /tmp/of-venv
uv pip install --python /tmp/of-venv/bin/python openfisca-core==45.0.4 numpy==2.1.3

cabal run l4 -- export openfisca jl4/examples/openfisca/benefit.l4 -o /tmp/benefit.py
/tmp/of-venv/bin/python jl4/examples/openfisca/roundtrip_check.py /tmp/benefit.py benefit
# eligible_for_benefit = 1.0, monthly_benefit = 700.0 / 0.0 — ROUND-TRIP OK
```
