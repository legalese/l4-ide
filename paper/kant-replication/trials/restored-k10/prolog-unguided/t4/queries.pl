%% ============================================================================
%% Per-claim facts and top-level queries q1..q9 for the nine benchmark
%% questions (inputs/queries-blind.md).
%%
%% Consulted after policy.pl. Every fact predicate used below is declared
%% dynamic in policy.pl, so this file only ever ADDS clauses to already-known
%% predicates.
%%
%% For every claim, only the facts the question text actually puts in issue
%% are asserted at their given value; every other fact needed to reach a
%% determinate answer is set to a benign value that keeps every condition
%% NOT referenced by the question satisfied and every exclusion NOT
%% referenced by the question inapplicable, per the standing preamble in
%% queries-blind.md ("Assuming all other conditions are met and no other
%% exclusions apply ... anything not referenced in the query").
%%
%% All times are months elapsed since the policy's effective date (per
%% policy.pl's time convention); no absolute date/time is encoded anywhere
%% below, other than the claimant's age where a question gives one.
%% ============================================================================

%% Facts are grouped by question below (not by predicate), for readability;
%% these declarations silence the resulting "clauses not together" warnings.
:- discontiguous(hospitalized/1).
:- discontiguous(cause_type/2).
:- discontiguous(activity_cause/2).
:- discontiguous(claimant_age/2).
:- discontiguous(hospitalization_time_months/2).
:- discontiguous(wellness_confirmation_provided_months/2).
:- discontiguous(hospital_location/2).
:- discontiguous(self_inflicted_intentional/1).

%% -------------------------------------------------------------------------
%% Q1. "will my policy apply if I was hospitalized by burns suffered while
%%      doing my duty as a firefighter?"
%% Burns are an accidental injury; "doing my duty as a firefighter" is a
%% direct causal link to the firefighter exclusion (3.1.3).
%% -------------------------------------------------------------------------
hospitalized(claim_1).
cause_type(claim_1, accidental_injury).
activity_cause(claim_1, firefighter).
hospitalization_time_months(claim_1, 1).
wellness_confirmation_provided_months(claim_1, 1).
hospital_location(claim_1, us).

q1 :- covered(claim_1).

%% -------------------------------------------------------------------------
%% Q2. "will my policy apply if I am 78 years old at the time of
%%      hospitalization?"
%% Only the age is put in issue; 78 < 80 so the age exclusion (3.1.5) does
%% not apply. Cause of hospitalization is unreferenced, so a generic
%% qualifying sickness is assumed.
%% -------------------------------------------------------------------------
hospitalized(claim_2).
cause_type(claim_2, sickness).
claimant_age(claim_2, 78).
hospitalization_time_months(claim_2, 1).
wellness_confirmation_provided_months(claim_2, 1).
hospital_location(claim_2, us).

q2 :- covered(claim_2).

%% -------------------------------------------------------------------------
%% Q3. "will my policy apply if I was hospitalized for pneumonia 5 months
%%      after the policy's effective date, and my age at the time of
%%      hospitalization is 65?"
%% Pneumonia is a sickness. 5 months is within the 12-month policy term.
%% Age 65 < 80.
%% -------------------------------------------------------------------------
hospitalized(claim_3).
cause_type(claim_3, sickness).
claimant_age(claim_3, 65).
hospitalization_time_months(claim_3, 5).
wellness_confirmation_provided_months(claim_3, 1).
hospital_location(claim_3, us).

q3 :- covered(claim_3).

%% -------------------------------------------------------------------------
%% Q4. "will my policy apply if I was hospitalized due to a fall while
%%      traveling abroad and I had given confirmation of my wellness visit
%%      8 months after the policy's effective date?"
%% A fall is an accidental injury. Confirmation at month 8 is later than the
%% 7-month deadline in 1.3, so the policy has been canceled under 1.2 for
%% that reason alone. Independently, "abroad" fails the 2.2 requirement that
%% confinement be in a hospital in the United States (see the judgement call
%% in policy.pl's confined_in_us/1 and in NOTES.md). Both routes yield "no".
%% -------------------------------------------------------------------------
hospitalized(claim_4).
cause_type(claim_4, accidental_injury).
hospitalization_time_months(claim_4, 1).
wellness_confirmation_provided_months(claim_4, 8).
hospital_location(claim_4, abroad).

q4 :- covered(claim_4).

%% -------------------------------------------------------------------------
%% Q5. "will my policy apply if I was hospitalized for punching my own face
%%      to show off for my friends and I did not commit fraud or
%%      misrepresentation?"
%% JUDGEMENT CALL -- see NOTES.md. Deliberately punching oneself is treated
%% as a self-inflicted, intentional act, so the resulting injury does not
%% qualify as an "accidental Injury" under 2.1 -- the claim fails at the
%% definitional level, not via any of the enumerated 3.1 exclusions. Fraud
%% is explicitly disclaimed by the question and is not asserted.
%% -------------------------------------------------------------------------
hospitalized(claim_5).
cause_type(claim_5, accidental_injury).
self_inflicted_intentional(claim_5).
hospitalization_time_months(claim_5, 1).
wellness_confirmation_provided_months(claim_5, 1).
hospital_location(claim_5, us).

q5 :- covered(claim_5).

%% -------------------------------------------------------------------------
%% Q6. "will my policy apply if I was hospitalized due to an injury
%%      sustained while skydiving, my age at the time of hospitalization was
%%      79, and proof of my wellness visit was provided 6.5 months after the
%%      policy's effective date?"
%% Skydiving is a direct causal link to the 3.1.1 exclusion, which is
%% decisive on its own. Age 79 < 80 does not independently exclude. 6.5
%% months is within the 7-month confirmation deadline, so 1.3 is otherwise
%% satisfied (immaterial here, since skydiving alone already excludes).
%% -------------------------------------------------------------------------
hospitalized(claim_6).
cause_type(claim_6, accidental_injury).
activity_cause(claim_6, skydiving).
claimant_age(claim_6, 79).
hospitalization_time_months(claim_6, 1).
wellness_confirmation_provided_months(claim_6, 6.5).
hospital_location(claim_6, us).

q6 :- covered(claim_6).

%% -------------------------------------------------------------------------
%% Q7. "will my policy apply if I was hospitalized for a heart attack, proof
%%      of the wellness visit was submitted 2 months after the policy's
%%      effective date, and my age at the time of hospitalization was 75?"
%% A heart attack is a sickness. 2 months is well within the 7-month
%% confirmation deadline. Age 75 < 80.
%% -------------------------------------------------------------------------
hospitalized(claim_7).
cause_type(claim_7, sickness).
claimant_age(claim_7, 75).
hospitalization_time_months(claim_7, 1).
wellness_confirmation_provided_months(claim_7, 2).
hospital_location(claim_7, us).

q7 :- covered(claim_7).

%% -------------------------------------------------------------------------
%% Q8. "will my policy apply if I was hospitalized after being injured in a
%%      military training exercise, the hospitalization occurred within the
%%      policy term, and I did not commit fraud?"
%% A training exercise undertaken as part of military service is a direct
%% causal link to the 3.1.2 exclusion. "Within the policy term" is encoded
%% as a compliant month value; fraud is explicitly disclaimed and not
%% asserted.
%% -------------------------------------------------------------------------
hospitalized(claim_8).
cause_type(claim_8, accidental_injury).
activity_cause(claim_8, military).
hospitalization_time_months(claim_8, 3).
wellness_confirmation_provided_months(claim_8, 1).
hospital_location(claim_8, us).

q8 :- covered(claim_8).

%% -------------------------------------------------------------------------
%% Q9. "will my policy apply if I was hospitalized due to my son biting me
%%      in the ankle, proof of my wellness visit was provided 6 months after
%%      the effective date, and I was serving as a police officer at the
%%      time of hospitalization?"
%% JUDGEMENT CALL -- see NOTES.md. The claimant's status as an on-duty
%% police officer is asserted, but the bite is from the claimant's own son
%% and has no causal connection to police service, so activity_cause(
%% claim_9, police) is deliberately NOT asserted: 3.1's exclusion requires
%% the injury to "arise ... out of" the excluded activity, not merely to
%% coincide with the claimant's occupation. 6 months is within the 7-month
%% confirmation deadline.
%% -------------------------------------------------------------------------
hospitalized(claim_9).
cause_type(claim_9, accidental_injury).
hospitalization_time_months(claim_9, 1).
wellness_confirmation_provided_months(claim_9, 6).
hospital_location(claim_9, us).

q9 :- covered(claim_9).
