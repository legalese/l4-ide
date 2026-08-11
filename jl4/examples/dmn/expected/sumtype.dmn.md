# Sum types and the data model

<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->

## `is a sale`

| F | d : String | is_a_sale (out) : Boolean |
| --- | --- | --- |
| 1 | sell | true |
| 2 | assign | false |
| 3 | - | false |

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
