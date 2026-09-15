% =====================================================================
% queries.pl -- the nine benchmark questions against policy.pl
%
% Each claim_N is given a full set of facts. Facts that the question
% text does not mention are set to values that satisfy that condition
% (per the task's Step-2 instructions 6 and 7: unrelated conditions
% for the policy to apply are satisfied, and unrelated exclusions do
% not fire), so that each query isolates the fact(s) the question is
% actually about.
%
% Standing preamble (applies to every question): "Assuming all other
% conditions are met and no other exclusions apply", and the agreement
% has been signed and the premium paid on time (already assumed inside
% policy.pl itself, so not repeated here).
% =====================================================================

% The facts below are grouped by claim (one block per question) rather
% than by predicate, for readability against the question text. All
% five per-claim fact predicates are therefore declared discontiguous.
:- discontiguous age_at_hospitalization/2.
:- discontiguous hospitalization_cause/2.
:- discontiguous hospitalization_time/2.
:- discontiguous wellness_visit_time/2.
:- discontiguous wellness_confirmation_time/2.

% ---------------------------------------------------------------------
% Q1: hospitalized by burns suffered while doing my duty as a
% firefighter.
%
% The cause is squarely "service as a fire fighter" -- Section 2.1
% item 3. Everything else is set to a safe, unrelated-condition value.
% ---------------------------------------------------------------------
hospitalization_cause(claim_1, firefighting_service).
age_at_hospitalization(claim_1, 40).
hospitalization_time(claim_1, 1).
wellness_visit_time(claim_1, 1).
wellness_confirmation_time(claim_1, 1).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
% Q2: 78 years old at the time of hospitalization.
%
% 78 is below the "equal to or greater than 80" threshold in Section
% 2.1 item 5, so the age exclusion does not fire. The cause of
% hospitalization is not in question, so it is set to an ordinary,
% non-excluded illness.
% ---------------------------------------------------------------------
age_at_hospitalization(claim_2, 78).
hospitalization_cause(claim_2, illness).
hospitalization_time(claim_2, 1).
wellness_visit_time(claim_2, 1).
wellness_confirmation_time(claim_2, 1).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
% Q3: hospitalized for pneumonia 5 months after the effective date,
% age 65 at the time of hospitalization.
%
% Pneumonia is an ordinary illness, not one of the enumerated causes.
% 5 months is comfortably inside the 12-month policy term. Age 65 is
% below the Section 2.1 item 5 threshold.
% ---------------------------------------------------------------------
hospitalization_time(claim_3, 5).
age_at_hospitalization(claim_3, 65).
hospitalization_cause(claim_3, pneumonia).
wellness_visit_time(claim_3, 1).
wellness_confirmation_time(claim_3, 1).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
% Q4: hospitalized due to a fall while traveling abroad, and
% confirmation of the wellness visit was given 8 months after the
% effective date.
%
% Being abroad is not an exclusion -- Section 3.1.1 affirmatively
% covers the policyholder "twenty-four (24) hours a day anywhere in
% the world", so no location fact is modeled at all. The tested fact
% is the confirmation time: 8 months is past the Section 1.3 deadline
% of the 7th month anniversary, so the condition was not satisfied in
% a timely fashion and the policy is deemed canceled under Section
% 1.2, regardless of when the fall itself occurred.
% ---------------------------------------------------------------------
hospitalization_cause(claim_4, accidental_fall).
age_at_hospitalization(claim_4, 40).
hospitalization_time(claim_4, 1).
wellness_visit_time(claim_4, 1).
wellness_confirmation_time(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
% Q5: hospitalized for punching my own face to show off for my
% friends, and no fraud or misrepresentation was committed.
%
% Self-inflicted horseplay is not among the Section 2.1 exclusions,
% and none of policy.pl's fraud/1, misrepresentation/1 or
% material_withholding/1 facts are asserted here, consistent with the
% question's own stipulation that none occurred.
% ---------------------------------------------------------------------
hospitalization_cause(claim_5, self_inflicted_horseplay).
age_at_hospitalization(claim_5, 40).
hospitalization_time(claim_5, 1).
wellness_visit_time(claim_5, 1).
wellness_confirmation_time(claim_5, 1).

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
% Q6: hospitalized due to an injury sustained while skydiving, age 79
% at the time of hospitalization, wellness-visit proof provided 6.5
% months after the effective date.
%
% Skydiving is excluded outright by Section 2.1 item 1, independent of
% age or of the (here timely) wellness confirmation -- both of the
% latter are red herrings relative to that exclusion. Age 79 is still
% below the item-5 threshold of 80, so it does not independently
% exclude the claim either; skydiving alone decides this question.
% ---------------------------------------------------------------------
hospitalization_cause(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
hospitalization_time(claim_6, 1).
wellness_visit_time(claim_6, 1).
wellness_confirmation_time(claim_6, 6.5).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
% Q7: hospitalized for a heart attack, wellness-visit proof submitted
% 2 months after the effective date, age 75 at the time of
% hospitalization.
%
% A heart attack is an ordinary illness, not an enumerated cause. 2
% months is well inside the 7-month confirmation deadline (and the
% 6-month visit deadline, taken as satisfied here since it is not
% independently tested). Age 75 is below the item-5 threshold.
% ---------------------------------------------------------------------
hospitalization_cause(claim_7, heart_attack).
age_at_hospitalization(claim_7, 75).
hospitalization_time(claim_7, 1).
wellness_visit_time(claim_7, 1).
wellness_confirmation_time(claim_7, 2).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
% Q8: hospitalized after being injured in a military training
% exercise, hospitalization occurred within the policy term, no fraud
% was committed.
%
% A military training exercise is squarely "service in the military"
% under Section 2.1 item 2, so this is excluded regardless of the
% claim otherwise being timely and fraud-free.
% ---------------------------------------------------------------------
hospitalization_cause(claim_8, military_service).
hospitalization_time(claim_8, 1).
age_at_hospitalization(claim_8, 40).
wellness_visit_time(claim_8, 1).
wellness_confirmation_time(claim_8, 1).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
% Q9: hospitalized due to my son biting me in the ankle,
% wellness-visit proof provided 6 months after the effective date, and
% I was serving as a police officer at the time of hospitalization.
%
% Judgement call (see NOTES.md): the Section 2.1 exclusions exclude an
% event by its CAUSE ("arising directly or indirectly out of" the
% listed activities), not by the claimant's occupation at the moment
% of injury. The cause here is a domestic bite from the claimant's own
% son, which has no causal connection to police service, so item 4
% does not apply merely because the claimant happens to be a serving
% police officer. 6 months is within both the 6-month visit deadline
% and the 7-month confirmation deadline.
% ---------------------------------------------------------------------
hospitalization_cause(claim_9, bitten_by_family_member).
age_at_hospitalization(claim_9, 40).
hospitalization_time(claim_9, 1).
wellness_visit_time(claim_9, 6).
wellness_confirmation_time(claim_9, 6).

q9 :- covered(claim_9).
