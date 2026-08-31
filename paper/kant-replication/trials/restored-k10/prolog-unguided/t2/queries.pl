% queries.pl
%
% Nine claims, one per benchmark question, plus q1/0..q9/0, each succeeding
% exactly when the corresponding question's answer is "yes". Consulted
% after policy.pl.
%
% Per the standing preamble in inputs/queries-blind.md ("assuming all other
% conditions are met and no other exclusions apply ... where by 'other' I
% mean anything not referenced in the query"), every fact not raised by a
% given question is set to a value that lets the policy apply: an age well
% under 80, no excluded activity, hospitalization in a US hospital, no
% fraud/misrepresentation, and comfortably inside every Section 1.3/4.6
% deadline. Only the fact(s) each question actually raises are set to the
% value the question states, so only those can change the outcome.

% --- Q1: burns suffered while on duty as a firefighter ---------------------
hospitalization_cause(claim_1, accidental_injury).
injury_activity(claim_1, firefighter_service).
age_at_hospitalization(claim_1, 30).
hospitalization_location(claim_1, us).
hospitalization_month(claim_1, 1).
wellness_visit_month(claim_1, 1).
wellness_confirmation_month(claim_1, 2).
fraud_or_misrepresentation(claim_1, false).

q1 :- covered(claim_1).

% --- Q2: 78 years old at time of hospitalization ---------------------------
% Cause of hospitalization is not addressed by the question; set to a
% generic non-excluded cause (sickness) so only the age fact is live.
hospitalization_cause(claim_2, sickness).
injury_activity(claim_2, none).
age_at_hospitalization(claim_2, 78).
hospitalization_location(claim_2, us).
hospitalization_month(claim_2, 1).
wellness_visit_month(claim_2, 1).
wellness_confirmation_month(claim_2, 2).
fraud_or_misrepresentation(claim_2, false).

q2 :- covered(claim_2).

% --- Q3: pneumonia, hospitalized 5 months in, age 65 -----------------------
hospitalization_cause(claim_3, sickness).
injury_activity(claim_3, none).
age_at_hospitalization(claim_3, 65).
hospitalization_location(claim_3, us).
hospitalization_month(claim_3, 5).
wellness_visit_month(claim_3, 1).
wellness_confirmation_month(claim_3, 2).
fraud_or_misrepresentation(claim_3, false).

q3 :- covered(claim_3).

% --- Q4: fall while traveling abroad; wellness confirmation at 8 months ----
% Two independent grounds this fails on: confirmation is past the 7-month
% deadline (Sections 1.2/1.3), and the confinement is outside the US
% (Section 2.2). See NOTES.md.
hospitalization_cause(claim_4, accidental_injury).
injury_activity(claim_4, none).
age_at_hospitalization(claim_4, 30).
hospitalization_location(claim_4, abroad).
hospitalization_month(claim_4, 8).
wellness_visit_month(claim_4, 5).
wellness_confirmation_month(claim_4, 8).
fraud_or_misrepresentation(claim_4, false).

q4 :- covered(claim_4).

% --- Q5: punched own face to show off for friends --------------------------
% Judgment call: a deliberate act done on purpose is not an "accidental
% Injury" under 2.1, regardless of the Section 3 exclusions (none of which
% address self-inflicted injury at all). See NOTES.md.
hospitalization_cause(claim_5, intentional_self_inflicted_act).
injury_activity(claim_5, none).
age_at_hospitalization(claim_5, 30).
hospitalization_location(claim_5, us).
hospitalization_month(claim_5, 1).
wellness_visit_month(claim_5, 1).
wellness_confirmation_month(claim_5, 2).
fraud_or_misrepresentation(claim_5, false).

q5 :- covered(claim_5).

% --- Q6: skydiving injury, age 79, confirmation at 6.5 months --------------
hospitalization_cause(claim_6, accidental_injury).
injury_activity(claim_6, skydiving).
age_at_hospitalization(claim_6, 79).
hospitalization_location(claim_6, us).
hospitalization_month(claim_6, 6).
wellness_visit_month(claim_6, 6).
wellness_confirmation_month(claim_6, 6.5).
fraud_or_misrepresentation(claim_6, false).

q6 :- covered(claim_6).

% --- Q7: heart attack, confirmation at 2 months, age 75 --------------------
hospitalization_cause(claim_7, sickness).
injury_activity(claim_7, none).
age_at_hospitalization(claim_7, 75).
hospitalization_location(claim_7, us).
hospitalization_month(claim_7, 2).
wellness_visit_month(claim_7, 2).
wellness_confirmation_month(claim_7, 2).
fraud_or_misrepresentation(claim_7, false).

q7 :- covered(claim_7).

% --- Q8: injured in a military training exercise ---------------------------
hospitalization_cause(claim_8, accidental_injury).
injury_activity(claim_8, military_service).
age_at_hospitalization(claim_8, 30).
hospitalization_location(claim_8, us).
hospitalization_month(claim_8, 3).
wellness_visit_month(claim_8, 1).
wellness_confirmation_month(claim_8, 2).
fraud_or_misrepresentation(claim_8, false).

q8 :- covered(claim_8).

% --- Q9: bitten on the ankle by claimant's son; confirmation at 6 months; --
% --- serving as a police officer at the time of hospitalization -----------
% Judgment call: "serving as a police officer at the time of
% hospitalization" describes the claimant's occupation, not the cause of
% the injury. Section 3.1's exclusion requires the injury to arise
% "directly or indirectly out of ... service in the police" - an ordinary
% household accident has no causal connection to police duty, so the
% exclusion does not fire. See NOTES.md.
hospitalization_cause(claim_9, accidental_injury).
injury_activity(claim_9, none).
age_at_hospitalization(claim_9, 30).
hospitalization_location(claim_9, us).
hospitalization_month(claim_9, 6).
wellness_visit_month(claim_9, 6).
wellness_confirmation_month(claim_9, 6).
fraud_or_misrepresentation(claim_9, false).

q9 :- covered(claim_9).
