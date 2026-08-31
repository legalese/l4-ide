# The shared fact schema, RESTORED-fixture variant — single source for both guided cells

**This file is the source for the restored arm. `schema-restored-prolog.md` and
`schema-restored-l4.md` are mechanical transliterations of it and must not add, drop, rename
or reinterpret a field.** It extends `schema.md` by exactly the fields the restored sections
require, under the same discipline; everything said there about R4 and provenance applies.

**Provenance discipline.** Fields 1–18 are `schema.md`'s, unchanged in name, type and order;
their clause citations are renumbered to the restored document (exclusions live at 3.1,
conditions at 4.x). Fields 19–21 are derived clause by clause from the RESTORED sections 2.2
and 2.3 (`fixtures/chubb-policy-restored.txt`), the same way the original eighteen were
derived from the modified text — from the policy, not from the nine queries. No query
exercises fields 19–21; as with the arbitration fields, that is the evidence the extension
was not reverse-engineered from the key.

Times are **months relative to the policy's effective date**; `none` means the event never
occurred.

| #   | field                               | type             | values                                                                     | clause          | required by                                                    |
| --- | ----------------------------------- | ---------------- | -------------------------------------------------------------------------- | --------------- | -------------------------------------------------------------- |
| 1   | `agreement_signed`                  | boolean          |                                                                            | 1.1(1)          | policy in effect                                               |
| 2   | `premium_paid_month`                | number or `none` |                                                                            | 1.1(2), 4.5.1   | policy in effect                                               |
| 3   | `hospitalization_month`             | number           |                                                                            | 1.1             | the operative moment for every test                            |
| 4   | `hospitalization_ground`            | enum             | `sickness`, `accidental_injury`, `neither`                                 | 1.1, 2.1, 2.2   | the insuring clause's trigger                                  |
| 5   | `age_at_hospitalization`            | number           | years                                                                      | 3.1(5)          | exclusion                                                      |
| 6   | `causes`                            | list of enum     | `skydiving`, `military_service`, `firefighting`, `police_service`, `other` | 3.1(1)–(4)      | exclusions; what the event arose directly or indirectly out of |
| 7   | `fraud_month`                       | number or `none` |                                                                            | 1.2             | deemed cancellation                                            |
| 8   | `misrepresentation_month`           | number or `none` |                                                                            | 1.2             | deemed cancellation; covers material withholding too           |
| 9   | `wellness_visit_month`              | number or `none` |                                                                            | 1.3             | the visit must occur by month 6                                |
| 10  | `wellness_visit_provider_qualified` | boolean          |                                                                            | 1.3             | "a qualified medical provider"                                 |
| 11  | `written_confirmation_month`        | number or `none` |                                                                            | 1.3             | confirmation due by month 7                                    |
| 12  | `dispute_arisen`                    | boolean          |                                                                            | 4.2.1           | arbitration gate                                               |
| 13  | `unable_to_settle_month`            | number or `none` |                                                                            | 4.2.1           | starts the 3-month arbitration clock                           |
| 14  | `arbitration_commenced_month`       | number or `none` |                                                                            | 4.2.1           | failure extinguishes the cause of action                       |
| 15  | `valid_arbitration_award_issued`    | boolean          |                                                                            | 4.2.1           | condition precedent to liability                               |
| 16  | `written_proof_of_claim_month`      | number or `none` |                                                                            | 4.2.1           | starts the 60-day bar                                          |
| 17  | `recovery_sought_month`             | number or `none` |                                                                            | 4.2.1           | the 60-day bar                                                 |
| 18  | `policy_term_months`                | number           | 12                                                                         | 4.6             | automatic cancellation at end of term                          |
| 19  | `confined_in_us_hospital`           | boolean          |                                                                            | 2.2             | the Daily Benefit is payable only for confinement in a hospital in the United States |
| 20  | `continuous_confinement_days`       | number or `none` |                                                                            | 2.2             | per-day benefit; capped at 365 days                            |
| 21  | `claim_made_setting_out_basis`      | boolean          |                                                                            | 2.3             | a claim must be made to trigger any benefit                    |

## Supporting helpers

Both transliterations expose exactly these two, and no others — identical to `schema.md`'s.

| helper                                  | meaning                                                                                       |
| --------------------------------------- | --------------------------------------------------------------------------------------------- |
| `no_later_than(EventMonth, LimitMonth)` | true when the event occurred and did so no later than the limit; false when it never occurred |
| `arose_out_of(Causes, Cause)`           | true when `Cause` is among the causes the event arose directly or indirectly out of           |

## What the schema deliberately does NOT decide

It supplies **facts, not conclusions**. There is no `policy_in_effect` field, no
`exclusion_applies` field, and no `covered` field.

It also does not resolve the interpretive knots, and must not. The T8 knot (whether 1.2's
"has not been satisfied in a timely fashion" cancels a policy whose 1.3 condition is merely
**still pending**) survives restoration untouched. The Q5 knot changes shape but does not
close: the insuring clause now exists, so the question is no longer *what follows when the
ground is `neither`* but *whether a deliberate self-inflicted injury is "accidental"* — the
classification of the ground is still the encoder's (or fact-marshaller's) judgement. And
restoration opens one new fork the modified text could not express: whether "will my policy
apply" means *applicability* (4.1.1 insures worldwide) or *benefit payability* (2.2 pays only
for US confinement). All of these are left to the encoder; disagreement about them is a
result, not a fault.
