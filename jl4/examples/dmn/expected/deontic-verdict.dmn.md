# deontic verdict

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

## `reporting duty`

| F | may_terminate : Boolean | cycles : Number | notice_window_open : Boolean | escalated : Boolean | reporting_duty (out) : String |
| --- | --- | --- | --- | --- | --- |
| 1 | true | - | - | - | file the termination report |
| 2 | - | <= 0 | - | - | fulfilled |
| 3 | - | - | true | - | may publish a notice |
| 4 | - | - | - | true | must not advertise the offering |
| 5 | - | - | - | - | file the annual report and continue |

<!-- OMITTED: `joint duty` — a formula (IF trigger THEN ((PARTY Issuer MUST `file jointly` WITHIN 5) RAND (PARTY Issuer MUST `notify investors` WITHIN 5)) ELSE FULFILLED), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `invoked joint duty` — a formula (joint_duty), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `bare duty` — a formula (PARTY Issuer MUST `notify investors` WITHIN 10), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->

<!-- OMITTED: `invoked bare duty` — a formula (bare_duty), and dmnmd has no boxed-expression form. Located, with its code, in the fidelity report. -->
