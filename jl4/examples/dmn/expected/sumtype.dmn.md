# Sum types and the data model

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

## `is a sale`

| F | d : String | is_a_sale (out) : Boolean |
| --- | --- | --- |
| 1 | sell | true |
| 2 | assign | false |
| 3 | - | false |

<!-- OMITTED: `stated term` — a formula (disposal.term_in_years), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `claim amount` — a formula (c.amount), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `capped at ten` — a rule of it answers `null` (the decision can REFUSE), and dmnmd's cell grammar has no null. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `grade is settled` — a formula (q != null), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `grade is settled, spelled longhand` — a formula (if p != null then true else false), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `claim payout` — a formula (cl_hydrated.doubled_amount), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `deep` — a formula (true), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

## `grade for`

| U | g : String | grade_for (out) : Number |
| --- | --- | --- |
| 1 | high | 2 |
| 2 | low | 1 |

## `is alpha`

| U | k : String | is_alpha (out) : Boolean |
| --- | --- | --- |
| 1 | alpha | true |
| 2 | beta | false |

<!-- OMITTED: `cl` — a boxed context (a hydrated record), which dmnmd cannot express. Located, with its code, in the fidelity report. -->
