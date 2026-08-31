# The shared fact schema — single source for both guided cells

**This file is the source. `schema-prolog.md` and `schema-l4.md` are mechanical
transliterations of it and must not add, drop, rename or reinterpret a field.**

`FOUNDATION.md` R4 is why: if we author a Prolog vocabulary and an L4 vocabulary
independently, differences between the _schemas_ — not the languages — drive the result, and
the guided cells silently measure whichever schema disambiguated better. The guided cells
measure **schema plus language**, never language alone, and the write-up must say so.

**Provenance discipline.** These fields were derived clause by clause from the policy text,
not from the nine benchmark queries. Every field below cites the clause that requires it.
Five fields (12–17) are required by clause 3.2.1 and are **not exercised by any query** —
their presence is the evidence that the schema was not reverse-engineered from the key.

Times are **months relative to the policy's effective date**, per the benchmark's own
convention (see `FOUNDATION.md` T3 for what that convention costs). `none` means the
event never occurred.

| #   | field                               | type             | values                                                                     | clause        | required by                                                    |
| --- | ----------------------------------- | ---------------- | -------------------------------------------------------------------------- | ------------- | -------------------------------------------------------------- |
| 1   | `agreement_signed`                  | boolean          |                                                                            | 1.1(1)        | policy in effect                                               |
| 2   | `premium_paid_month`                | number or `none` |                                                                            | 1.1(2), 3.5.1 | policy in effect                                               |
| 3   | `hospitalization_month`             | number           |                                                                            | 1.1           | the operative moment for every test                            |
| 4   | `hospitalization_ground`            | enum             | `sickness`, `accidental_injury`, `neither`                                 | 1.1           | the claim must be premised on one of the two                   |
| 5   | `age_at_hospitalization`            | number           | years                                                                      | 2.1(5)        | exclusion                                                      |
| 6   | `causes`                            | list of enum     | `skydiving`, `military_service`, `firefighting`, `police_service`, `other` | 2.1(1)–(4)    | exclusions; what the event arose directly or indirectly out of |
| 7   | `fraud_month`                       | number or `none` |                                                                            | 1.2           | deemed cancellation                                            |
| 8   | `misrepresentation_month`           | number or `none` |                                                                            | 1.2           | deemed cancellation; covers material withholding too           |
| 9   | `wellness_visit_month`              | number or `none` |                                                                            | 1.3           | the visit must occur by month 6                                |
| 10  | `wellness_visit_provider_qualified` | boolean          |                                                                            | 1.3           | "a qualified medical provider"                                 |
| 11  | `written_confirmation_month`        | number or `none` |                                                                            | 1.3           | confirmation due by month 7                                    |
| 12  | `dispute_arisen`                    | boolean          |                                                                            | 3.2.1         | arbitration gate                                               |
| 13  | `unable_to_settle_month`            | number or `none` |                                                                            | 3.2.1         | starts the 3-month arbitration clock                           |
| 14  | `arbitration_commenced_month`       | number or `none` |                                                                            | 3.2.1         | failure extinguishes the cause of action                       |
| 15  | `valid_arbitration_award_issued`    | boolean          |                                                                            | 3.2.1         | condition precedent to liability                               |
| 16  | `written_proof_of_claim_month`      | number or `none` |                                                                            | 3.2.1         | starts the 60-day bar                                          |
| 17  | `recovery_sought_month`             | number or `none` |                                                                            | 3.2.1         | the 60-day bar                                                 |
| 18  | `policy_term_months`                | number           | 12                                                                         | 3.6           | automatic cancellation at end of term                          |

## Supporting helpers

Both transliterations expose exactly these two, and no others.

| helper                                  | meaning                                                                                       |
| --------------------------------------- | --------------------------------------------------------------------------------------------- |
| `no_later_than(EventMonth, LimitMonth)` | true when the event occurred and did so no later than the limit; false when it never occurred |
| `arose_out_of(Causes, Cause)`           | true when `Cause` is among the causes the event arose directly or indirectly out of           |

## What the schema deliberately does NOT decide

It supplies **facts, not conclusions**. There is no `policy_in_effect` field, no
`exclusion_applies` field, and no `covered` field. Every such judgement is the encoder's work,
which is the thing being measured.

It also does not resolve the two known interpretive knots, and must not: whether clause 1.2's
"has not been satisfied in a timely fashion" cancels a policy whose 1.3 condition is merely
**still pending** (`FOUNDATION.md` T8), and what follows when the ground is `neither` — which
turns on the operative insuring clause that **Kant et al. deleted from the fixture**
(`source-defects.md`). Both are left to the encoder, and disagreement about them is a result,
not a fault.
