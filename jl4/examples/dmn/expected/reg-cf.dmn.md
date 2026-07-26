# Regulation Crowdfunding

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

## `is accredited investor`

| F | class : String | is accredited investor (out) : Boolean |
| --- | --- | --- |
| 1 | accredited | true |
| 2 | institutional | true |
| 3 | - | false |

## `financial statements required`

| F | offering amount : Number | first_time issuer : Boolean | financial statements required (out) : String |
| --- | --- | --- | --- |
| 1 | <= 107000 | - | certified by the principal executive officer |
| 2 | <= 535000 | - | reviewed by an independent public accountant |
| 3 | <= 1070000 | true | reviewed by an independent public accountant |
| 4 | - | - | audited by an independent public accountant |
