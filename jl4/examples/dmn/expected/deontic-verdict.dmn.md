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
