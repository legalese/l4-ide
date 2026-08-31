# Notes

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> **Check succeeded.**
  (First attempt failed: `elem`/`isNothing` were "not in scope" because `prelude` is
  not actually auto-imported in this toolchain despite the reference docs saying so.
  Fixed by adding an explicit `IMPORT prelude`; second attempt succeeded.)
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> **Check succeeded.**
- I did **not** run `l4 run` on either file, and did not evaluate any `#EVAL`
  directive, per the rules.

## Judgement calls

- **Section 1.3 ("still pending or has been satisfied in a timely fashion")**
  is encoded as a flat deadline check — wellness visit no later than month 6
  (with a qualified provider) AND written confirmation no later than month 7 —
  using the given `no later than` helper, which itself treats a `NOTHING`
  event as failing the deadline. I did not separately model "still pending"
  as a function of how the hospitalization month relates to the two
  deadlines: a `Claim` records completed historical facts (a month or
  `NOTHING`), not a live, evolving status, so there is nothing left "pending"
  once the fields are fixed. This means a claim's `covered` value here does
  not depend on how `hospitalization month` relates to 6 or 7 — only on
  whether the visit/confirmation eventually happened by those deadlines.

- **`premium paid month`** is checked with the given `no later than` helper
  against `hospitalization month` (i.e. "paid no later than the
  hospitalization"), not merely "paid at some point." Section 1.1(2)'s
  present-perfect phrasing ("has been paid") reads naturally as as-of-the-
  relevant-time, and this reuses the given helper rather than writing a new
  presence-only check.

- **Section 4.2.1's 60-day wait** ("You shall [not] seek to recover ...
  before the expiration of sixty (60) days after written proof of claim")
  is approximated as **2 months**, since the `Claim` schema only carries
  month granularity (including fractional months, e.g. 6.5) and has no
  day-level field. `recovery sought month` is required to be at least
  `written proof of claim month` + 2.

- **Section 2.2's 365-day cap** ("for a period not exceeding three hundred
  and sixty-five (365) days") is **not** encoded as an all-or-nothing gate.
  `covered` is defined as "true exactly when a benefit is payable," and even
  a confinement longer than 365 days still leaves a benefit payable for the
  days within the cap — it only limits how much is paid, not whether
  anything is payable. `covered` only requires at least one day of
  continuous confinement (`continuous confinement days` is `JUST d` with
  `d AT LEAST 1`) plus `confined in us hospital`, per section 2.2's explicit
  "in a hospital in the United States" language (read as a real, separate
  condition from section 4.1's worldwide-24/7 language, which I read as
  going to where the *triggering event* may occur, not where the benefit-
  paying confinement itself must be).

- **Q4** ("hospitalized due to a fall while traveling abroad and I had given
  confirmation of my wellness visit 8 months after the policy's effective
  date"): "traveling abroad" is taken to mean the hospitalization did not
  occur in a US hospital, so `confined in us hospital = FALSE` for this
  claim — this alone is enough to fail `covered` under my reading of
  section 2.2, independent of the confirmation timing. "confirmation of my
  wellness visit was given at month 8" is mapped to the
  `written confirmation month` field (8 > 7, so that also fails on its own).
  `wellness visit month` itself is not stated, so it is defaulted to an
  early, on-time value.

- **Q5** ("hospitalized for punching my own face to show off for my friends
  and I did not commit fraud or misrepresentation"): I classified this as
  `hospitalization ground = \`Accidental injury\`` rather than `Neither`.
  Reasoning: the punching motion was voluntary, but the resulting injury
  (serious enough to require hospitalization) was not the intended or
  expected outcome, and conventional accident & health insurance doctrine
  treats "accidental" as asking whether the *harm* was intended, not
  whether the antecedent *act* was voluntary (the classic "horseplay" case).
  The explicit disclaimer of fraud/misrepresentation in the question reads
  as ruling out the wrong objection, pointing at this Ground classification
  as the intended question. This is genuinely arguable — a reading that
  treats a deliberate, voluntary act as taking the injury out of "accidental"
  entirely (making it `Neither`) is also defensible on the plain word
  "accidental," and would flip this claim to not-covered on that ground
  alone. I went with the coverage-favorable reading above.

- **Q6/Q7/Q9** ("proof of the wellness visit was provided/submitted X
  months after the effective date"): mapped consistently to the
  `written confirmation month` field (i.e. as the section-1.3 written
  confirmation from the medical provider, of which the claimant supplies
  written "proof"/confirmation), not to `wellness visit month` (the date of
  the physical visit itself, which none of these questions separately
  state and which I defaulted to an early, on-time value). Q4 uses the
  parallel phrase "confirmation of my wellness visit was given," treated
  the same way, for consistency across all four questions that mention this
  fact.

- **Q9** ("I was serving as a police officer at the time of
  hospitalization," hospitalized because "my son bit me in the ankle"):
  `causes` does **not** include `\`Police service\``. Section 3.1 excludes
  an injury "arising directly or indirectly out of ... service in the
  police" — a causal test — and merely being employed as a police officer
  at the moment of an unrelated domestic incident does not satisfy it. This
  is the one place in the schema where "unrelated to the question" and
  "mentioned in the question" pull in different directions: the fact *is*
  mentioned, but on my reading it does not populate `causes`, precisely
  because the question is testing whether contemporaneous employment gets
  mistaken for a causal exclusion.

All other fields not discussed above, for all nine claims, are set to
values chosen to keep every other condition satisfied and no other
exclusion triggered, per the standing preamble (agreement signed, premium
paid at month 0, no fraud/misrepresentation, wellness visit and
confirmation both early/on time unless a question states otherwise, no
dispute, a 12-month policy term, confinement in a US hospital for 3 days,
proof of claim and recovery sought in order, and a properly made claim).
