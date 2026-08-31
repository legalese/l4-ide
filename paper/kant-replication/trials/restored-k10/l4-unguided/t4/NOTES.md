# Notes on this encoding

## Checks run

- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check policy.l4` → **`Check succeeded.`**
- `JL4_LIBRARY_PATH=.../jl4-core/libraries l4 check apply.l4` → **`Check succeeded.`**

`l4 check` type-checks only; it does not evaluate `#EVAL` directives, so no
result of any `#EVAL` (q1–q9) was seen while producing this trial. No other
`l4` subcommand (`run`, `trace`, etc.) was invoked on `policy.l4` or
`apply.l4`.

Before writing the real files, I also ran `l4 check` and `l4 run` twice on
throwaway syntax probes in my scratchpad (outside the trial directory),
using placeholder names (`Thing`, `` `flag a` ``, `` `flag b` ``) with no
connection to the insurance policy, purely to confirm two syntax questions:
(1) whether a `DECIDE name IF …` boolean shortcut can omit repeating its
`GIVEN` parameter's name, and (2) the exact `CONSIDER … WHEN JUST x THEN …
WHEN NOTHING THEN …` shape for a `MAYBE NUMBER` record field. Both probes
typechecked and evaluated as expected; this did not exercise the policy
encoding or the nine questions in any way.

## Judgement calls

1. **§1.3 has two independent deadlines; only one is ever given by a
   query.** The clause requires (a) the wellness visit itself to occur no
   later than the 6-month anniversary, and (b) written confirmation of that
   visit to be supplied no later than the 7-month anniversary. Every query
   that mentions this at all phrases it as "confirmation of my wellness
   visit" or "proof of the wellness visit was provided/submitted" N months
   after the effective date — i.e. it always gives the *confirmation*
   deadline (b), never the visit's own date (a) separately. I modelled both
   as distinct fields (`wellness visit confirmation month`, a `MAYBE
   NUMBER`, and `wellness visit occurred in time`, a `BOOLEAN`), but since
   no query ever supplies (a) independently, `wellness visit occurred in
   time` is set to `TRUE` in all nine queries, per the instruction to treat
   facts a query doesn't mention as satisfied.

2. **"Still pending" (§1.1(3)) needs a notion of time-of-hospitalization
   vs. time-of-confirmation.** When no confirmation has been supplied as of
   the hospitalization being assessed, I treat §1.1(3) as satisfied (via
   "still pending") exactly when the hospitalization occurs at or before
   the 7-month mark, and as failed otherwise. This is the branch exercised
   by Q3 (hospitalized at month 5, no confirmation mentioned) and is why Q3
   does not fail on the wellness condition despite no confirmation being
   given.

3. **The four §3.1 activity exclusions require causation, not mere
   status.** "Arising directly or indirectly out of" skydiving / military
   service / firefighting service / police service is read as requiring the
   sickness or injury to actually stem from that activity — being a police
   officer (or firefighter, etc.) at the time of an unrelated injury does
   not, by itself, trigger the exclusion. This is decisive for Q9 (bitten by
   one's own son while "serving as a police officer at the time" — no
   causal link, so `caused by police service` is `FALSE`), in contrast to
   Q1, Q6, and Q8 where the named activity is the direct cause of the
   injury.

4. **No exclusion in this contract reaches self-inflicted or reckless
   injury generally.** For Q5 (hospitalized for punching one's own face to
   "show off"), none of the five §3.1 grounds apply (it is not skydiving,
   military, firefighting, police service, or an age-80+ claimant), and the
   query itself rules out the only other cancellation ground the contract
   supplies (§1.2 fraud/misrepresentation). I did not read in an unstated
   general exclusion for intentional or reckless self-harm, since the text
   does not contain one.

5. **Q4's "traveling abroad" is about where the accident happened, not
   where the claimant was hospitalized.** §2.2 restricts the *benefit* to
   confinement "in a hospital in the United States," while §4.1 confirms
   the *risk* itself is covered "twenty-four (24) hours a day anywhere in
   the world." Since Q4 states only that the fall occurred while traveling
   abroad and says nothing about the hospital's location, I treated
   `hospital in United States` as unrelated to the query and set it to
   `TRUE` (satisfied) by default, so that Q4's answer turns solely on the
   late (8-month, i.e. past the 7-month §1.3 deadline) wellness
   confirmation. A reader who instead took "traveling abroad" to mean the
   hospitalization itself was abroad would fail Q4 on a second, independent
   ground — but the two readings do not disagree about the bottom-line
   answer to Q4.

6. **Fraud, misrepresentation, and material withholding (§1.2) are one
   combined field.** The contract lists them as three alternative triggers
   for the same cancellation consequence, and no query ever distinguishes
   between them (Q5 and Q8 only ever assert "did not commit fraud [or
   misrepresentation]"), so they share a single boolean,
   `fraud or misrepresentation or material withholding`.

7. **Out of scope for a yes/no "does the policy apply" determination:**
   §1.1(1)–(2) (signature, premium paid — assumed per the task brief),
   §2.3 (mechanics of making a claim), §4.2 (arbitration), §4.3 (governing
   law), §4.4 (currency), and §4.5 (premium mechanics). These are
   procedural/administrative and none of the nine questions turn on them.
   §4.6's substantive content (one-year term) is folded into
   `policy has been cancelled`, since §1.2 itself frames running past the
   end of the term as a form of cancellation.

8. **Filler values for facts a query doesn't mention:** age 30 (well under
   the §3.1(5) cutoff of 80) and hospitalization month 0 (well inside every
   deadline in §1) are used as neutral defaults wherever a query is silent
   on them, per the instruction to satisfy every condition/exclusion
   unrelated to the query being encoded.
