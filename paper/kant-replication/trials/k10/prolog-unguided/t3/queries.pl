% =============================================================================
% queries.pl -- per-claim facts and the nine benchmark queries q1..q9.
%
% Consulted after policy.pl. Each question below is modeled as one claim
% atom (claim_1 .. claim_9) with only the facts the question text actually
% states. Per the standing instruction that accompanies every question
% ("assuming all other conditions are met and no other exclusions apply ...
% anything not referenced in the query"), everything the question does not
% mention is left unasserted on purpose, so that policy.pl's own defaults
% (a condition with no evidence against it holds; an exclusion with no
% evidence for it does not apply) take over. Each q_N/0 succeeds exactly
% when the claim is covered, i.e. exactly when the answer is "yes".
% =============================================================================

:- discontiguous hospitalization_event/1.
:- discontiguous hospitalization_cause/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous hospitalization_month/2.
:- discontiguous confirmation_supplied_month/2.

% --- Q1: hospitalized by burns suffered while doing my duty as a
%         firefighter ---------------------------------------------------
% Cause is firefighter service on its face -> Section 2.1 item 3 excludes
% it outright; no timing/age facts are mentioned so none are asserted.
hospitalization_event(claim_1).
hospitalization_cause(claim_1, firefighter_service).

q1 :- covered(claim_1).

% --- Q2: 78 years old at the time of hospitalization --------------------
% No cause is given (irrelevant to the question), so no exclusion other
% than age is even in play; 78 is below the Section 2.1 item 5 threshold
% of 80.
hospitalization_event(claim_2).
age_at_hospitalization(claim_2, 78).

q2 :- covered(claim_2).

% --- Q3: hospitalized for pneumonia 5 months after the effective date,
%         age 65 at the time of hospitalization -------------------------
% Pneumonia is a sickness not on the Section 2.1 list; age 65 is below 80;
% hospitalization at month 5 is before the Section 1.3 month-7 deadline,
% so that condition is still "pending" (Section 1.1 item 3) and does not
% defeat coverage.
hospitalization_event(claim_3).
hospitalization_cause(claim_3, pneumonia).
age_at_hospitalization(claim_3, 65).
hospitalization_month(claim_3, 5).

q3 :- covered(claim_3).

% --- Q4: hospitalized due to a fall while traveling abroad; confirmation
%         of the wellness visit given 8 months after the effective date -
% Traveling abroad does not matter (Section 3.1: worldwide cover). The
% confirmation was supplied at month 8, after the Section 1.3 month-7
% deadline, so Section 1.3 failed and the policy was canceled under
% Section 1.2 by the time of the claim.
hospitalization_event(claim_4).
hospitalization_cause(claim_4, fall).
confirmation_supplied_month(claim_4, 8).

q4 :- covered(claim_4).

% --- Q5: hospitalized for punching my own face to show off for my
%         friends; did not commit fraud or misrepresentation -----------
% No fraud/misrepresentation fact is asserted, matching "did not commit
% fraud or misrepresentation". Punching one's own face to show off is not
% any of the five Section 2.1 causes (it is not skydiving, military,
% firefighter or police service, and age is not mentioned), so no
% exclusion applies on the text as given -- see NOTES.md for the judgment
% call this rests on.
hospitalization_event(claim_5).
hospitalization_cause(claim_5, self_inflicted_horseplay).

q5 :- covered(claim_5).

% --- Q6: hospitalized due to an injury sustained while skydiving; age 79
%         at the time of hospitalization; wellness-visit proof provided
%         6.5 months after the effective date --------------------------
% Skydiving alone excludes the claim under Section 2.1 item 1, regardless
% of age (79 is under 80 anyway) or the wellness-visit timing (6.5 <= 7,
% timely anyway).
hospitalization_event(claim_6).
hospitalization_cause(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
confirmation_supplied_month(claim_6, 6.5).

q6 :- covered(claim_6).

% --- Q7: hospitalized for a heart attack; wellness-visit proof submitted
%         2 months after the effective date; age 75 ---------------------
% Heart attack (sickness) is not a Section 2.1 cause; age 75 is under 80;
% confirmation at month 2 is well inside the month-7 deadline.
hospitalization_event(claim_7).
hospitalization_cause(claim_7, heart_attack).
age_at_hospitalization(claim_7, 75).
confirmation_supplied_month(claim_7, 2).

q7 :- covered(claim_7).

% --- Q8: injured in a military training exercise; hospitalization
%         occurred within the policy term; did not commit fraud --------
% Military service is Section 2.1 item 2 and excludes the claim outright.
% "Within the policy term" is modeled directly as a hospitalization month
% comfortably inside the 12-month term (Section 3.6); no fraud fact is
% asserted, matching "did not commit fraud". Neither of those saves the
% claim from the military-service exclusion.
hospitalization_event(claim_8).
hospitalization_cause(claim_8, military_service).
hospitalization_month(claim_8, 1).

q8 :- covered(claim_8).

% --- Q9: hospitalized due to my son biting me in the ankle; wellness
%         proof provided 6 months after the effective date; I was
%         serving as a police officer at the time of hospitalization ---
% The cause of the hospitalization is a family incident (the claimant's
% son biting their ankle), not anything arising out of police service --
% see NOTES.md for the judgment call that being a police officer at the
% time, without more, does not itself trigger Section 2.1 item 4.
% Confirmation at month 6 is inside the month-7 deadline.
hospitalization_event(claim_9).
hospitalization_cause(claim_9, family_incident).
confirmation_supplied_month(claim_9, 6).

q9 :- covered(claim_9).
