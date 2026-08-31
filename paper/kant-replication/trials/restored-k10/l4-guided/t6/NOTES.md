# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` — **Check succeeded.**
  (First attempt failed with "I could not find a definition for the identifier `elem`"
  at the `arose out of` helper; fixed by adding `IMPORT prelude` as the first line.
  The `writing-l4-rules` skill's cheat sheet says the prelude is auto-imported, but
  several example `.l4` files under `jl4-core`/`jl4/examples` explicitly `IMPORT prelude`
  too, and the compiler's own error was decisive, so I added the explicit import.)
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` — **Check succeeded.**
- I did **not** run `l4 run` or otherwise evaluate any `#EVAL` directive, and did not
  look at the nine answers. `l4 check` only typechecks, per the skill's own
  documentation ("Fast path — typecheck only, no evaluation").

## Judgement calls in `policy.l4` (the `covered` logic)

1. **§1.1(3)/§1.2 "condition ... still pending or ... satisfied in a timely fashion."**
   Modeled as: the §1.3 wellness/confirmation obligation is due by month 7 (the
   confirmation deadline); before that (`hospitalization month LESS THAN 7`) it is
   "still pending" and cannot yet have failed; at or after month 7 it must already be
   `satisfied` (visit ≤ month 6 by a qualified provider, confirmation ≤ month 7) or the
   policy is treated as canceled under §1.2. I anchored "pending" to the hospitalization
   month specifically because §1.1's opening sentence frames the whole "in effect" test
   as evaluated "at the time of the hospitalization," and no other time reference exists
   in the schema.
2. **`fraud month` / `misrepresentation month` as presence checks, not deadline checks.**
   Unlike the wellness-visit fields, §1.2 cancels the policy "if there is fraud, or any
   misrepresentation," with no stated timing. I wrote a small `has occurred` helper
   (MAYBE NUMBER → BOOLEAN, true iff `JUST`) for these two fields plus `premium paid
   month`, rather than stretching the given `no later than` helper (which is a deadline
   comparison, not a presence test) to do a job it isn't shaped for.
3. **`continuous confinement days` and the 365-day cap (§2.2).** I treat presence of
   `continuous confinement days` (any `JUST` value) plus `confined in us hospital` as
   what makes a benefit payable at all. The 365-day cap governs how many days are paid,
   not whether any benefit is payable, so `covered` does not test it — a claimant
   confined for more than 365 days is still "covered" for the first 365.
4. **Sixty days → two months (§4.2, the recovery-timing clause).** The schema gives
   `written proof of claim month` and `recovery sought month` in the same month unit as
   everything else, so I read "sixty (60) days" as two of those months (60/30) rather
   than importing a day-granular date library for one clause. `recovery sought month`
   must be at least `written proof of claim month` + 2 when both are present.
5. **`Ground = Neither`.** Read as covering hospitalizations that are neither a sickness
   nor an accidental injury — e.g. a deliberate, self-inflicted act (see Q5 in
   `apply.l4`) — per §2.1's "as a result of sickness or accidental Injury."

## Judgement calls in `apply.l4` (per-query fact construction)

- **Causal language is what puts a `Cause` into the `causes` list.** Q1 ("while doing
  my duty as a firefighter"), Q6 ("while skydiving"), and Q8 ("injured in a military
  training exercise") each state the excluded activity as the direct mechanism of
  injury, so I set `causes` to the corresponding `Cause`. Q9 ("son biting me in the
  ankle ... I was serving as a police officer at the time of hospitalization") states
  the claimant's occupation only as a contemporaneous fact, with no causal link between
  police service and the bite — so I left `causes` empty for Q9. This is the one place
  the nine queries seem to deliberately probe the same distinction from both sides.
- **Q4's "traveling abroad."** The query gives two facts: a fall while traveling
  abroad, and a wellness-visit confirmation given at month 8 (after the §1.3 deadline
  of month 7). I read "traveling abroad" as describing where the fall/injury happened,
  which §4.1 ("insures You ... anywhere in the world") makes irrelevant to whether the
  peril is covered, and left `confined in us hospital` at its satisfied default (`TRUE`)
  since the query never states where the claimant was actually confined for treatment.
  Under this reading, Q4's only operative fact is the late confirmation. The opposite
  reading (traveling abroad ⇒ confined outside the US) is defensible from the bare text
  of §2.2 alone; I did not adopt it because §4.1's worldwide-coverage clause reads as
  deliberately addressing exactly this kind of concern, and the query's specific,
  numeric "8 months" detail otherwise has no work to do.
- **Q4's `hospitalization month` (set to 9, after the failed month-7 deadline).** Because
  of judgement call 1 above (pending vs. failed is evaluated as of the hospitalization),
  I placed Q4's hospitalization after month 7 so the claim is tested at a point when the
  §1.3 condition has already failed, rather than while it was still pending — otherwise
  the late confirmation would never come into play and the query's central fact would be
  inert. Q6's and Q9's confirmation months are within deadline regardless of this choice,
  so their hospitalization months are not load-bearing in the same way.
- **A heart attack (Q7) is a sickness, not an accidental injury.**
- **Unrelated fields.** Per the standing preamble, every field a query does not mention
  is set to whatever value satisfies coverage on its own: agreement signed, premium paid
  at month 0, no fraud/misrepresentation, a qualified wellness visit at month 3 and
  confirmation at month 4 (or another value below the two deadlines) where the query is
  silent on them, no dispute, a 12-month policy term, confinement in a US hospital for a
  few days, and a claim made setting out its basis.
