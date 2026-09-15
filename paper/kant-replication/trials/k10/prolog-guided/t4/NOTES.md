# Notes

## Load check

Ran, as permitted:

```
swipl -q -g halt policy.pl queries.pl
```

Output: none (silent). Exit code: 0. Did not call q1..q9 or otherwise evaluate the
encoding against the nine questions.

## Judgment calls

1. **"Still pending or has been satisfied in a timely fashion" (1.1(3)/1.3).** Modeled
   "still pending" as: the hospitalization itself occurs no later than the 7th month
   anniversary (`no_later_than(HospMonth, 7)`). Rationale: 1.1 ties "in effect" to the
   state of the policy "at the time of the hospitalization," and the only clock 1.3 sets
   is the 7-month deadline for supplying confirmation; if the hospitalization happens
   before that deadline, the condition cannot yet have been failed, so it is still
   pending. If the hospitalization happens after month 7, the condition must actually
   have been satisfied: confirmation given by month 7, of a visit that itself occurred
   by month 6, with a qualified provider.

2. **Fraud and misrepresentation are fatal at any month.** `claim_fraud_month` and
   `claim_misrepresentation_month` are read as "did this ever happen" (any number means
   yes) rather than being compared against the hospitalization month. Unlike the 1.3
   deadlines, section 1.2 does not tie fraud/misrepresentation cancellation to a time
   window ("cancelation will be deemed to have occurred if there is fraud, or any
   misrepresentation..."), so no month comparison was invented for it.

3. **"Material withholding of any information" (1.2) has no separate claim fact.** Folded
   into `claim_misrepresentation_month`, since the schema provides only one fact for that
   part of 1.2 and the two grounds are stated disjunctively in the same clause.

4. **Policy term.** Section 5 (which 1.1/1.2 cross-reference for the term) is not present
   in the supplied contract text; 3.6 says the term is one year. Rather than hardcoding
   12, `covered/1` compares the hospitalization month against `claim_policy_term_months`
   directly, since it is supplied as a per-claim numeric fact.

5. **The 60-day recovery bar (3.2.1, last sentence) is unconditional**, i.e. it applies
   whether or not a dispute has arisen — unlike the rest of 3.2.1, that sentence is not
   phrased as contingent on a dispute ("In no case shall You seek to recover..."). Sixty
   days was converted to 2 (30-day) months to compare against the schema's
   month-denominated facts (`claim_written_proof_of_claim_month`,
   `claim_recovery_sought_month`), since the schema gives no separate day-granularity
   fact.

6. **Valid arbitration award as a condition precedent** is read as applying whenever
   `claim_dispute_arisen` is true, independent of whether the separate 3-month
   arbitration-commencement clock has even started (`claim_unable_to_settle_month` may
   still be `none`). This is the most literal reading of "Where there is a dispute or
   disagreement, the issuance of a valid arbitration award shall also be a condition
   precedent to our liability."

7. **Q9 (son biting me in the ankle, while "serving as a police officer").** Treated
   "serving as a police officer" as background/occupational status, not as a cause of the
   injury. Exclusion 2.1.4 requires the injury to arise "directly or indirectly out of...
   service in the police," and a bite from one's own son has no causal connection to
   police duty, so `claim_causes(c9, [other])` rather than including `police_service`.

8. **Q4 (fall while traveling abroad; confirmation of the wellness visit given 8 months
   after the effective date).** The question does not state the hospitalization month
   directly. Read "I had given confirmation ... 8 months after..." (past perfect) as
   preceding the hospitalization, and set `claim_hospitalization_month(c4, 10)`
   (after month 8, and past the month-7 "still pending" cutoff), so the encoding is
   judged on actual satisfaction of 1.3 rather than on the pending escape. The visit's
   own date (as opposed to when confirmation of it was given) is not stated, so
   `claim_wellness_visit_month(c4, 1)` was chosen as a favorable filler, per the
   preamble, since the confirmation month alone (8, > 7) already determines the 1.3
   outcome for this claim regardless of the visit's own date.

9. **Q5 (punching my own face to show off) classified as `accidental_injury`**, not
   `neither`. The policy has no exclusion for intentional self-harm or foolish conduct;
   "accidental injury" is read here as the physical-trauma counterpart to "sickness"
   (illness), not as requiring the injuring act itself to have been unintended.

10. **Premium payment** is modeled as "paid" (`claim_premium_paid_month` is a number,
    checked with `number/1`) with no deadline comparison against the hospitalization
    month, since the contract's only timing language for the premium is "paid in one
    lump sum at the signing of the policy" (3.5.1), not a rule relating it to the
    hospitalization date. All nine claims set it to month 0 (paid at signing), per the
    standing instruction that the premium has been paid on time.

11. **Facts not referenced by a question** (e.g. age when the question does not turn on
    age, causes when the question names no excluded activity, the entire arbitration/
    proof-of-claim/recovery block for all nine questions, since none of them mention a
    dispute) were set to values that satisfy every condition and trigger no exclusion,
    per the standing preamble. In particular `claim_dispute_arisen` is `false` for all
    nine claims, and `claim_written_proof_of_claim_month`/`claim_recovery_sought_month`
    are set 3 months apart (comfortably clearing the 2-month/60-day bar) for all nine.
