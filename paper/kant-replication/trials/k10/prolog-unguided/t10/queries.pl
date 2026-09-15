% =====================================================================
% queries.pl -- the nine benchmark questions, encoded as facts about
% claim_1 .. claim_9 plus one q1..q9 predicate per question.
%
% Per the task's Step 2 instructions, every fact not mentioned by a
% given question is simply left unasserted, relying on policy.pl's
% defaults: an unstated condition is treated as satisfied, and an
% unstated exclusion trigger is treated as not triggered. No absolute
% dates are used anywhere except the claimant's age.
% =====================================================================

% ---------------------------------------------------------------------
% Q1: hospitalized by burns suffered while doing my duty as a
% firefighter.
% The burns are an accidental injury, and they arise directly out of
% firefighter service (Section 2.1 item 3).
% ---------------------------------------------------------------------
hospitalization_ground(claim_1, accidental_injury).
caused_by_firefighter_service(claim_1).

q1 :- covered(claim_1).

% ---------------------------------------------------------------------
% Q2: 78 years old at the time of hospitalization.
% Below the Section 2.1 item 5 threshold of 80; nothing else about
% the hospitalization is stated.
% ---------------------------------------------------------------------
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ---------------------------------------------------------------------
% Q3: hospitalized for pneumonia 5 months after the effective date;
% age 65 at hospitalization.
% Pneumonia is a sickness. 5 months is before the Section 1.3
% 7-month deadline, so that condition is still pending.
% ---------------------------------------------------------------------
hospitalization_ground(claim_3, sickness).
hospitalization_time_months(claim_3, 5).
age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% ---------------------------------------------------------------------
% Q4: hospitalized due to a fall while traveling abroad; confirmation
% of the wellness visit was given 8 months after the effective date.
% A fall is an accidental injury. Worldwide coverage (Section 3.1.1)
% means traveling abroad adds no exclusion. 8 months is after the
% Section 1.3 7-month deadline for supplying confirmation, so the
% condition was not satisfied in a timely fashion.
% ---------------------------------------------------------------------
hospitalization_ground(claim_4, accidental_injury).
wellness_confirmation_months(claim_4, 8).

q4 :- covered(claim_4).

% ---------------------------------------------------------------------
% Q5: hospitalized for punching my own face to show off for friends;
% no fraud or misrepresentation was committed.
% Punching oneself to show off is a deliberate act, not a sickness or
% an accidental injury (Section 1.1) -- see NOTES.md for the judgment
% call this rests on. No fraud/misrepresentation fact is asserted,
% matching the question's own statement.
% ---------------------------------------------------------------------
hospitalization_ground(claim_5, intentional_self_inflicted).

q5 :- covered(claim_5).

% ---------------------------------------------------------------------
% Q6: hospitalized due to an injury sustained while skydiving; age 79
% at hospitalization; proof of the wellness visit provided 6.5 months
% after the effective date.
% The injury arises directly out of skydiving (Section 2.1 item 1).
% Age 79 is below the item-5 threshold of 80, and 6.5 months is
% within the Section 1.3 7-month confirmation deadline -- both are
% immaterial once the skydiving exclusion applies.
% ---------------------------------------------------------------------
hospitalization_ground(claim_6, accidental_injury).
caused_by_skydiving(claim_6).
age_at_hospitalization(claim_6, 79).
wellness_confirmation_months(claim_6, 6.5).

q6 :- covered(claim_6).

% ---------------------------------------------------------------------
% Q7: hospitalized for a heart attack; proof of the wellness visit
% submitted 2 months after the effective date; age 75 at
% hospitalization.
% A heart attack is a sickness. 2 months is well within the Section
% 1.3 deadline, and age 75 is below the item-5 threshold.
% ---------------------------------------------------------------------
hospitalization_ground(claim_7, sickness).
wellness_confirmation_months(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ---------------------------------------------------------------------
% Q8: hospitalized after being injured in a military training
% exercise; the hospitalization occurred within the policy term; no
% fraud was committed.
% The injury arises directly out of service in the military (Section
% 2.1 item 2). "Within the policy term" is encoded as an explicit
% time comfortably inside the 12-month term.
% ---------------------------------------------------------------------
hospitalization_ground(claim_8, accidental_injury).
caused_by_military_service(claim_8).
hospitalization_time_months(claim_8, 3).

q8 :- covered(claim_8).

% ---------------------------------------------------------------------
% Q9: hospitalized due to my son biting me in the ankle; proof of the
% wellness visit provided 6 months after the effective date; I was
% serving as a police officer at the time of hospitalization.
% Being on duty as a police officer at the time is a status, not a
% cause: the bite does not arise out of police service (Section 2.1
% item 4 requires the event to arise "directly or indirectly out of"
% that service), so caused_by_police_service/1 is deliberately left
% unasserted for this claim. 6 months is within the Section 1.3
% 7-month confirmation deadline.
% ---------------------------------------------------------------------
hospitalization_ground(claim_9, accidental_injury).
wellness_confirmation_months(claim_9, 6).

q9 :- covered(claim_9).
