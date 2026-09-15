% ==========================================================================
% queries.pl -- the nine benchmark questions, each encoded as a claim's
% facts plus a q<N>/0 predicate that succeeds iff the answer is "yes".
%
% Every claim is implicitly a hospitalization (that is the shared premise
% of all nine questions); only the facts relevant to determining coverage
% are asserted below. Per the task brief, any fact left unmentioned by a
% question is set so that it does NOT stand in the way of coverage. In
% this encoding that is achieved simply by omitting the corresponding
% dynamic fact wherever the question is silent, since every "bad" fact in
% policy.pl (an exclusion, a cancelation trigger, an out-of-country
% confinement) only fires when explicitly asserted, and every "good" fact
% required for the initial coverage grant (sickness/1, accidental_injury/1)
% is asserted explicitly below wherever the question's own stated cause of
% hospitalization warrants it.
% ==========================================================================

% --------------------------------------------------------------------------
% Q1. Hospitalized by burns suffered while doing my duty as a firefighter.
% Burns from an on-duty firefighting incident are an accidental injury
% (satisfying Section 2.1) that arises directly out of service as a fire
% fighter (Section 3.1, item 3) -- so the exclusion applies.
% --------------------------------------------------------------------------
accidental_injury(claim_1).
cause_of_injury(claim_1, firefighting_service).

q1 :- covered(claim_1).

% --------------------------------------------------------------------------
% Q2. 78 years old at the time of hospitalization.
% The question names no cause of hospitalization, so a generic sickness is
% asserted purely to satisfy Section 2.1's coverage grant (a condition
% unrelated to the query); the only fact actually under test is the age
% threshold in Section 3.1, item 5. Age 78 is below the "80 or older"
% exclusion threshold.
% --------------------------------------------------------------------------
sickness(claim_2).
claimant_age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% --------------------------------------------------------------------------
% Q3. Hospitalized for pneumonia 5 months after the effective date; age 65
% at the time of hospitalization.
% Pneumonia is a sickness. 5 months is within the Section 1.3 deadlines
% (6 months for the visit, 7 for confirmation), so that condition is still
% pending, not failed -- no wellness fact is asserted at all, which
% defaults to "not failed". Age 65 is below the exclusion threshold.
% --------------------------------------------------------------------------
sickness(claim_3).
hospitalization_month(claim_3, 5).
claimant_age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% --------------------------------------------------------------------------
% Q4. Hospitalized due to a fall while traveling abroad; confirmation of
% the wellness visit was given 8 months after the effective date.
% A fall is an accidental injury. "Traveling abroad" is read as meaning
% the confinement itself was in a hospital outside the United States, so
% Section 2.2's US-hospital condition on the payable benefit is not met.
% Independently, confirmation at 8 months is past the Section 1.3 7-month
% deadline, so that condition failed and the policy was canceled under
% Section 1.2. Either fact alone already defeats coverage; both are
% asserted here for a faithful record of everything the question states.
% --------------------------------------------------------------------------
accidental_injury(claim_4).
hospitalized_outside_us(claim_4).
wellness_confirmation_month(claim_4, 8).

q4 :- covered(claim_4).

% --------------------------------------------------------------------------
% Q5. Hospitalized for punching my own face to show off for my friends; no
% fraud or misrepresentation was committed.
% Deliberately punching oneself in the face is neither a sickness nor an
% ACCIDENTAL injury -- it is a self-inflicted, intentional act -- so it
% never satisfies the Section 2.1 coverage grant in the first place, quite
% apart from there being no fraud. Accordingly neither sickness/1 nor
% accidental_injury/1 is asserted for this claim, and no
% fraud_or_misrepresentation/1 fact is asserted either (matching the
% question's own statement). See NOTES.md for this judgement call.
% --------------------------------------------------------------------------

q5 :- covered(claim_5).

% --------------------------------------------------------------------------
% Q6. Hospitalized due to an injury sustained while skydiving; age 79 at
% the time of hospitalization; proof of the wellness visit was provided
% 6.5 months after the effective date.
% The skydiving exclusion (Section 3.1, item 1) applies outright,
% regardless of the age (79, under the age-80 threshold) and the wellness
% proof (6.5 months, inside the 7-month confirmation deadline) both being
% fine on their own terms.
% --------------------------------------------------------------------------
accidental_injury(claim_6).
cause_of_injury(claim_6, skydiving).
claimant_age_at_hospitalization(claim_6, 79).
wellness_confirmation_month(claim_6, 6.5).

q6 :- covered(claim_6).

% --------------------------------------------------------------------------
% Q7. Hospitalized for a heart attack; proof of the wellness visit was
% submitted 2 months after the effective date; age 75 at the time of
% hospitalization.
% A heart attack is a sickness. 2 months is well inside the 7-month
% confirmation deadline, and age 75 is below the exclusion threshold.
% --------------------------------------------------------------------------
sickness(claim_7).
wellness_confirmation_month(claim_7, 2).
claimant_age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% --------------------------------------------------------------------------
% Q8. Hospitalized after being injured in a military training exercise;
% the hospitalization occurred within the policy term; no fraud was
% committed.
% A training-exercise injury is an accidental injury that arises directly
% out of service in the military (Section 3.1, item 2), so the exclusion
% applies regardless of the policy term and the absence of fraud both
% being fine on their own terms. hospitalization_month is set well inside
% the one-year term to reflect the question's own "within the policy
% term" statement; no fraud_or_misrepresentation/1 fact is asserted,
% matching "I did not commit fraud".
% --------------------------------------------------------------------------
accidental_injury(claim_8).
cause_of_injury(claim_8, military_service).
hospitalization_month(claim_8, 1).

q8 :- covered(claim_8).

% --------------------------------------------------------------------------
% Q9. Hospitalized due to my son biting me in the ankle; proof of the
% wellness visit was provided 6 months after the effective date; I was
% serving as a police officer at the time of hospitalization.
% Being bitten by one's own son is an accidental injury with no connection
% to police service -- the Section 3.1, item 4 exclusion requires the
% injury to arise "directly or indirectly out of" service in the police,
% and the claimant's occupation being a police officer is not the same
% thing as the injury having arisen out of that service. Accordingly no
% cause_of_injury/2 fact is asserted for this claim. See NOTES.md. 6
% months is exactly at the Section 1.3 visit deadline and inside the
% 7-month confirmation deadline, so that condition is satisfied.
% --------------------------------------------------------------------------
accidental_injury(claim_9).
wellness_confirmation_month(claim_9, 6).

q9 :- covered(claim_9).
