# Regulation Crowdfunding

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

## `is accredited investor`

| F | class : String | is_accredited_investor (out) : Boolean |
| --- | --- | --- |
| 1 | accredited | true |
| 2 | institutional | true |
| 3 | - | false |

<!-- OMITTED: `combined resources` — a formula (annual_income + net_worth), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `annual limit basis` — a formula (min(annual_income, net_worth)), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

## `financial statements required`

| F | offering_amount : Number | first_time_issuer : Boolean | financial_statements_required (out) : String |
| --- | --- | --- | --- |
| 1 | <= 107000 | - | certified by the principal executive officer |
| 2 | <= 535000 | - | reviewed by an independent public accountant |
| 3 | <= 1070000 | true | reviewed by an independent public accountant |
| 4 | - | - | audited by an independent public accountant |

<!-- OMITTED: `investor limit` — a cell outside dmnmd's grammar. Located, with its code, in the fidelity report. -->
