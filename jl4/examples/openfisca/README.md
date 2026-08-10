# L4 → OpenFisca bridge (v1)

`l4 openfisca FILE` compiles the **decision-rule subset** of an L4 file into a
single, runnable [OpenFisca](https://openfisca.org) Python module. An L4
`DECIDE`/`MEANS` over a *subject* and a *period* is structurally the same thing
as an OpenFisca `Variable` with a `formula(entity, period)`, so the mapping is
near-isomorphic:

| L4 | OpenFisca |
|---|---|
| `@export` `DECIDE`/`MEANS` returning a value | a `Variable` with a `formula` |
| subject param `GIVEN p IS A <Record>` | the entity (single `Person`-style entity in v1) |
| conventional `period` param | the formula's `period` argument; `definition_period = MONTH` |
| stored record fields / free scalar params | input `Variable`s (no formula) |
| `p's field` | `entity('field', period)` |
| call to another `@export` decision | `entity('that_decision', period)` |
| `+ - * / <  > AND OR NOT`, `IF/THEN/ELSE` | numpy ops / `&` `|` `~` / `np.where` |

Out of scope in v1 (next milestones): group entities + aggregation
(`household.members`/`sum`/roles), legislation `parameters()` trees, period
arithmetic, recursion, and general function application.

## Files

- `flat-tax.l4` — the OpenFisca textbook example (`flat_tax_on_salary`).
- `benefit.l4` — a means-tested benefit: comparisons, `IF/THEN/ELSE`, a boolean
  decision, and one decision calling another.
- `expected/*.py` — committed golden output (pinned by the `l4 openfisca`
  cases in `jl4/tests-cli/Main.hs`).
- `roundtrip_check.py` — runs the generated module in real OpenFisca and asserts
  the results equal the L4 `#EVAL` values.

## Regenerate the golden output

```sh
cabal run l4 -- openfisca jl4/examples/openfisca/flat-tax.l4 -o jl4/examples/openfisca/expected/flat-tax.py
cabal run l4 -- openfisca jl4/examples/openfisca/benefit.l4  -o jl4/examples/openfisca/expected/benefit.py
```

## Prove it runs in real OpenFisca (defensibility)

OpenFisca needs Python ≤ 3.13; pin numpy to dodge a 2.5 regression:

```sh
uv venv --python 3.12 /tmp/of-venv
uv pip install --python /tmp/of-venv/bin/python openfisca-core "numpy==2.1.3"

cabal run l4 -- openfisca jl4/examples/openfisca/flat-tax.l4 -o /tmp/flat_tax.py
/tmp/of-venv/bin/python jl4/examples/openfisca/roundtrip_check.py /tmp/flat_tax.py flat-tax
# flat_tax_on_salary(2026-01) = 500.0  (L4 expected 500.0)  OK

cabal run l4 -- openfisca jl4/examples/openfisca/benefit.l4 -o /tmp/benefit.py
/tmp/of-venv/bin/python jl4/examples/openfisca/roundtrip_check.py /tmp/benefit.py benefit
# eligible_for_benefit = 1.0, monthly_benefit = 700.0 / 0.0  — all OK
```
