# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` -> **Check succeeded.**
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` -> **Check succeeded.**

Both were typecheck-only (`l4 check`), as permitted. I did **not** run `l4 run` and did not
evaluate any `#EVAL` directive or otherwise observe the output of the nine queries. The only
verification beyond typechecking was tracing the rule tree by hand, on paper, against my own
reading of the contract text (not against any external key, which I did not have and did not
look for), to confirm the encoding was internally self-consistent.

## Judgement calls

1. **Exclusions require a causal link, not just status.** Sec. 3.1 excludes injury/sickness
   "arising directly or indirectly out of" skydiving, military service, firefighting, or police
   service. I modeled each of these as a fact about the *event's causation*
   (`` `event arose from service in the police` ``, etc.), not about the claimant's occupation in
   general. This matters for Q9 (hospitalized after being bitten by the claimant's own son, while
   "serving as a police officer at the time"): holding the job at the time of injury is not the
   same as the injury arising out of that service, so I set that flag to FALSE for Q9. The same
   reading, applied the other way, is what makes Q1 (burns "while doing my duty as a firefighter")
   and Q8 (injury "in a military training exercise") excluded.

2. **"Accidental injury" excludes deliberate self-infliction.** Sec. 2.1 only pays a benefit for
   confinement "as a result of sickness or accidental Injury." I read "accidental" in its ordinary
   sense (unintended, fortuitous), so Q5 (hospitalized for punching one's own face on purpose "to
   show off") is neither a sickness nor an accidental injury, and fails this gate regardless of the
   fact -- stated in the query -- that no fraud or misrepresentation occurred. This is a genuine
   interpretive call: the policy has no explicit "self-inflicted injury" exclusion, so the result
   turns entirely on how "accidental" is read.

3. **The wellness-visit numbers in the queries describe the *confirmation* event, not the visit
   itself.** Sec. 1.3 actually sets two deadlines: the visit must occur by the 6th month
   anniversary, and written confirmation of it must reach the Company by the 7th month
   anniversary. Every query that gives a number here phrases it as confirmation/proof being
   "given," "provided," or "submitted" (Q4, Q6, Q7, Q9) -- language that tracks the *supply*
   half of Sec. 1.3, not the visit's own date, which none of the queries state. I therefore fed
   that number into `` `wellness visit confirmation month` `` (tested against the 7-month
   deadline) and left `` `wellness visit month` `` as NOTHING, i.e. assumed the visit itself
   happened on time, since it is not "referenced in the query" under the standing preamble. Q6's
   6.5-month figure is the one place this choice is live (6.5 <= 7, so it does not by itself
   fail Sec. 1.3 under my reading) -- it doesn't change the answer either way there, since Q6's
   skydiving fact independently excludes it.

4. **"Still pending" is a real third state, not a synonym for "satisfied."** Sec. 1.1(3) keeps the
   policy in effect if Sec. 1.3 "is still pending or has been satisfied" -- i.e. an unfulfilled
   wellness-visit condition should *not* cancel the policy before its deadlines have actually
   passed. I modeled this with `` `hospitalization month` `` as the fallback clock: if a
   claim gives no concrete wellness-visit/confirmation fact, the corresponding deadline is only
   treated as "missed" once the hospitalization itself is already past month 6 / month 7. This is
   what lets Q3 (hospitalized at month 5, wellness visit not otherwise mentioned) resolve to "not
   canceled" rather than incorrectly failing for want of a wellness visit that isn't due yet.

5. **Sec. 2.2's "hospital in the United States" is a separate gate from Sec. 4.1.1's worldwide
   coverage.** 4.1.1 says the claimant is insured anywhere in the world around the clock; 2.2 says
   the Daily Hospital Income Benefit is only payable for confinement "in a hospital in the United
   States." I treated these as compatible, not contradictory: the insured event can happen
   anywhere, but I gated the benefit itself on US hospitalization. Q4 ("hospitalized ... while
   traveling abroad") is the only claim where I set this flag to FALSE. It does not change Q4's
   answer, which is independently determined by the late (8-month) wellness confirmation.

6. **Not modeled as coverage gates, only as comments in `policy.l4`:** Sec. 2.2's 365-day cap on
   the number of days paid (a payment-duration limit, not an on/off switch), Sec. 2.3's
   claim-filing formality (assumed satisfied whenever a claim is being evaluated at all, exactly
   like the signature/premium assumptions the task brief already directs), and Secs. 4.2-4.5
   (arbitration, governing law, currency, premium logistics), none of which bear on whether a
   given hospitalization is covered.

7. Per the task brief, Sec. 1.1(1) ("this agreement is signed") and Sec. 1.1(2) ("the premium ...
   has been paid") are assumed always TRUE and are not represented as fields anywhere.
