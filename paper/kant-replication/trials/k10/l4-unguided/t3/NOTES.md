# NOTES

## Checks run

- `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check policy.l4` -> `Check succeeded.`
- `JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check apply.l4` -> `Check succeeded.`

Both are typecheck-only (`l4 check`, not `l4 run`). I did **not** run `l4 run`, `l4
batch`, or evaluate any `#EVAL` directive, and did not otherwise test the encoding
against the nine questions, per the task rules.

## Judgement calls

1. **Time representation.** Every date/time fact other than age is encoded as a plain
   `NUMBER` counting months elapsed since the effective date (fractional values like
   `6.5` work directly), never as a calendar `DATE`. This follows the task brief's
   instruction that no elapsed-time-between-two-dates computation is ever needed, and
   it sidesteps the `daydate` month-arithmetic footgun entirely since no `Date`/`YMD`
   arithmetic is used anywhere.

2. **Section 1.3 has two separate deadlines, kept separate.** The clause reads: "No
   later than the 7th month anniversary ... you will supply us with written
   confirmation ... of a wellness visit ... occurring no later than the 6th month
   anniversary." That is two facts -- (a) the confirmation must be _submitted_ by
   month 7, and (b) the underlying visit must have _occurred_ by month 6 -- so
   `Hospitalization` carries two independent `MAYBE NUMBER` fields rather than one.
   Every question that mentions this condition (Q4, Q6, Q7, Q9) phrases it as
   "confirmation/proof of my wellness visit was provided/submitted N months after the
   effective date" -- grammatically about the act of _submitting_, matching clause
   (a). None of the nine questions separately states when the underlying visit itself
   took place, so I bound the given figure only to the submission field and left the
   visit-occurrence field `NOTHING` (read as "not known to be late", which is
   non-blocking), rather than assuming the two events are simultaneous.

   **This is the single biggest interpretive fork in the encoding**, and it only
   changes the outcome for one question: Q6's figure of 6.5 months falls strictly
   between the two thresholds (6 and 7). Under my reading, 6.5 <= 7 satisfies the
   submission deadline and the (unstated) visit date is treated as not shown to be
   late, so Section 1.3 does not, by itself, block Q6. Under the alternative reading
   -- treating "proof provided at 6.5 months" as fixing the visit's own occurrence
   date too -- 6.5 > 6 would fail the visit deadline. I went with the more literal,
   textually-separated reading and did not special-case Q6 to hit any assumed answer;
   the same submission-only rule is applied uniformly to Q4/Q6/Q7/Q9.

3. **"Still pending" does not key off hospitalization time.** Section 1.1's "the
   condition set out in Section 1.3 is still pending or has been satisfied in a
   timely fashion" is modeled purely by whether each Section-1.3 fact is known: if a
   field is `NOTHING`, that requirement reads as still pending (`TRUE`, non-blocking);
   if given (`JUST t`), it is checked against the fixed deadline. Hospitalization time
   is never compared against the confirmation/visit timings -- only against the
   12-month policy-term constant (see next point). This keeps every temporal check a
   direct comparison against a fixed number from the text, consistent with the task
   brief, and is also why most per-question hospitalization-month values below are
   arbitrary small placeholders: that field is otherwise inert.

4. **Policy term / auto-cancelation (1.2, 3.6).** Section 1.2 cross-references "the
   policy term described in Section 5 below", but the supplied extract has no Section
   5 -- the term is actually defined in 3.6 ("a period of one year from that date").
   I used 3.6's one-year (12-month) figure for the auto-cancelation check, since no
   Section 5 exists in this document to consult instead.

5. **Exclusions are causal, not occupational.** Section 2.1's skydiving/military/
   firefighter/police exclusions require the hospitalization to "arise directly or
   indirectly out of" the named activity. `Hospitalization`'s four flags are phrased
   as `caused by ...`, not "claimant is a ...". This matters for Q9: the claimant "was
   serving as a police officer at the time of hospitalization", but the stated cause
   of the hospitalization is an unrelated domestic incident (their son biting their
   ankle) -- merely being on duty when an unrelated injury occurs does not mean the
   injury arises out of that service, so `caused by police service` is `FALSE` for
   q9, and this is called out again inline in apply.l4.

6. **No exclusion invented for Q5.** Q5 (hospitalized for punching one's own face "to
   show off for my friends") describes conduct that a real-world accident policy
   might well exclude as self-inflicted or intentional, but the contract text as
   supplied lists exactly five exclusions in Section 2.1 (skydiving, military, fire
   fighting, police, age >= 80) and none of them covers self-inflicted or intentional
   injury. I did not add such an exclusion; q5 sets all four "caused by" flags to
   `FALSE`.

7. **Sections 3.2-3.5 are out of scope for `covered`.** Arbitration and the 60-day
   pre-suit waiting period (3.2), governing law (3.3), currency of payment (3.4), and
   the timing of the lump-sum premium (3.5, already assumed satisfied per the task
   brief) all govern dispute resolution or payment mechanics, not whether a given
   hospitalization falls within the scope of coverage. They are documented in
   policy.l4 but not wired into `covered`. Section 3.1 (worldwide, 24/7 coverage) is
   kept as an explicit always-`TRUE` fact for traceability against the source text,
   even though it can never block a claim.

8. **Defaults for facts a question does not mention**, per the task's instruction to
   satisfy unrelated conditions and avoid triggering unrelated exclusions: age 40
   (well under the 80 threshold), hospitalization at 1 month after the effective date
   (3 months for Q8, which explicitly says "within the policy term" -- either value is
   far from the 12-month boundary), no fraud/misrepresentation/withheld information,
   no excluded-activity flags, and `NOTHING` for wellness-visit fields not mentioned.
