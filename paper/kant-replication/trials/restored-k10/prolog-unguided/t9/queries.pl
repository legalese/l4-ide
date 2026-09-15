% =============================================================================
% queries.pl -- the nine benchmark questions, each encoded as a distinct
% claim_N with its own facts, plus a q1..q9 predicate that succeeds iff the
% answer to that question is "yes" and fails iff it is "no".
%
% Per the task brief, for each question every fact/rule/parameter that is
% not the subject of that question is left unasserted, relying on
% policy.pl's default (favourable to coverage / non-exclusion) reading of
% an unasserted fact. Only facts directly referenced by a question's own
% wording are asserted for its claim.
%
% These predicates are declared dynamic in policy.pl (consulted first);
% dynamic does not by itself suppress the discontiguous-clauses warning
% for facts added in a *different* file, so the four predicates that
% recur across non-adjacent claim_N blocks below are also declared
% discontiguous here.
% =============================================================================

:- discontiguous hospitalized_due_to/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous injury_caused_by/2.
:- discontiguous wellness_confirmation_month/2.

% ---- Q1: hospitalized by burns suffered while doing duty as a firefighter.
% Burns are an accidental injury; they arose directly out of service as a
% firefighter, so the Section 3.1 firefighter exclusion applies.
hospitalized_due_to(claim_1, injury).
injury_caused_by(claim_1, firefighter_service).

q1 :- covered(claim_1).

% ---- Q2: 78 years old at the time of hospitalization.
% The cause of hospitalization is not the subject of this question, so a
% generic qualifying sickness is asserted to satisfy the (unrelated)
% Section 2.1 cause condition. Age 78 is below the Section 3.1 age-80
% exclusion threshold.
hospitalized_due_to(claim_2, sickness).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% ---- Q3: hospitalized for pneumonia 5 months after the effective date;
% age 65 at hospitalization.
% Pneumonia is a sickness. At 5 months, the Section 1.3 wellness-visit
% condition is still pending (short of the 7-month confirmation
% deadline), so it has not been breached. Age 65 is below the exclusion
% threshold.
hospitalized_due_to(claim_3, sickness).
hospitalization_month(claim_3, 5).
age_at_hospitalization(claim_3, 65).

q3 :- covered(claim_3).

% ---- Q4: hospitalized due to a fall while traveling abroad; confirmation
% of the wellness visit given 8 months after the effective date.
% A fall is an accidental injury. Confirmation at month 8 is later than
% the Section 1.3/1.2 7-month deadline, so the policy has been canceled
% for failing to satisfy that condition in a timely fashion. Independently
% -- see NOTES.md for the judgement call -- hospitalization while
% traveling abroad is read as confinement outside the United States, so
% Section 2.2 also bars the benefit; either ground alone is dispositive.
hospitalized_due_to(claim_4, injury).
wellness_confirmation_month(claim_4, 8).
confined_outside_us(claim_4).

q4 :- covered(claim_4).

% ---- Q5: hospitalized for punching my own face to show off for my
% friends; I did not commit fraud or misrepresentation.
% Fraud/misrepresentation is expressly disclaimed and is not asserted
% here. The deliberate act of punching oneself in the face is treated as
% intentional self-harm, so the resulting injury is not "accidental"
% within the meaning of Section 2.1 (judgement call -- see NOTES.md).
hospitalized_due_to(claim_5, injury).
intentional_self_harm(claim_5).

q5 :- covered(claim_5).

% ---- Q6: hospitalized due to an injury sustained while skydiving; age 79
% at hospitalization; wellness-visit proof provided 6.5 months after the
% effective date.
% The Section 3.1 skydiving exclusion applies regardless of the other two
% facts (age 79 is below the age-exclusion threshold, and 6.5 months is
% within the 7-month confirmation deadline).
hospitalized_due_to(claim_6, injury).
injury_caused_by(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
wellness_confirmation_month(claim_6, 6.5).

q6 :- covered(claim_6).

% ---- Q7: hospitalized for a heart attack; wellness-visit proof submitted
% 2 months after the effective date; age 75 at hospitalization.
% A heart attack is a sickness. 2 months is comfortably within the
% 7-month confirmation deadline, and age 75 is below the exclusion
% threshold.
hospitalized_due_to(claim_7, sickness).
wellness_confirmation_month(claim_7, 2).
age_at_hospitalization(claim_7, 75).

q7 :- covered(claim_7).

% ---- Q8: hospitalized after being injured in a military training
% exercise; the hospitalization occurred within the policy term; I did
% not commit fraud.
% The injury arose directly out of service in the military, so the
% Section 3.1 military exclusion applies regardless of the term/fraud
% facts, which merely rule out two *other* possible reasons for
% non-coverage and so are left unasserted (both favourable to the claim,
% consistent with them not being the subject of this question).
hospitalized_due_to(claim_8, injury).
injury_caused_by(claim_8, military_service).

q8 :- covered(claim_8).

% ---- Q9: hospitalized due to my son biting me in the ankle; wellness
% visit proof provided 6 months after the effective date; serving as a
% police officer at the time of hospitalization.
% Being bitten by one's son is an accidental injury with no causal
% connection to police service, so the Section 3.1 police exclusion is
% not triggered by mere status as a serving police officer at the time
% (judgement call -- see NOTES.md). 6 months is within the 7-month
% confirmation deadline.
hospitalized_due_to(claim_9, injury).
wellness_confirmation_month(claim_9, 6).

q9 :- covered(claim_9).
