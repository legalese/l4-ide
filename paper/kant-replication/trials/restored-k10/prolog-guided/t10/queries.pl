% queries.pl -- the nine benchmark questions (inputs/queries-blind.md), each encoded
% as a claim against covered/1 (policy.pl). Every claim defines all 21 claim_* facts.
% Facts drawn directly from a question's text are marked "given"; all other facts are
% set to values chosen to favor coverage and to not trigger any exclusion, per the
% standing preamble ("assuming all other conditions are met... where by 'other' I mean
% anything not referenced in the query"), and per the standing assumption that the
% agreement is signed and the premium paid on time. See NOTES.md for judgement calls,
% in particular for c4 and c9.

:- discontiguous claim_agreement_signed/2.
:- discontiguous claim_premium_paid_month/2.
:- discontiguous claim_hospitalization_month/2.
:- discontiguous claim_hospitalization_ground/2.
:- discontiguous claim_age_at_hospitalization/2.
:- discontiguous claim_causes/2.
:- discontiguous claim_fraud_month/2.
:- discontiguous claim_misrepresentation_month/2.
:- discontiguous claim_wellness_visit_month/2.
:- discontiguous claim_wellness_visit_provider_qualified/2.
:- discontiguous claim_written_confirmation_month/2.
:- discontiguous claim_dispute_arisen/2.
:- discontiguous claim_unable_to_settle_month/2.
:- discontiguous claim_arbitration_commenced_month/2.
:- discontiguous claim_valid_arbitration_award_issued/2.
:- discontiguous claim_written_proof_of_claim_month/2.
:- discontiguous claim_recovery_sought_month/2.
:- discontiguous claim_policy_term_months/2.
:- discontiguous claim_confined_in_us_hospital/2.
:- discontiguous claim_continuous_confinement_days/2.
:- discontiguous claim_claim_made_setting_out_basis/2.

q1 :- covered(c1).
q2 :- covered(c2).
q3 :- covered(c3).
q4 :- covered(c4).
q5 :- covered(c5).
q6 :- covered(c6).
q7 :- covered(c7).
q8 :- covered(c8).
q9 :- covered(c9).

% ---------------------------------------------------------------------------
% c1 -- Q1: hospitalized by burns suffered while doing my duty as a firefighter.
% ---------------------------------------------------------------------------
claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 3).
claim_hospitalization_ground(c1, accidental_injury).       % given: burns
claim_age_at_hospitalization(c1, 40).
claim_causes(c1, [firefighting]).                          % given: duty as a firefighter
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 2).
claim_wellness_visit_provider_qualified(c1, true).
claim_written_confirmation_month(c1, 3).
claim_dispute_arisen(c1, false).
claim_unable_to_settle_month(c1, none).
claim_arbitration_commenced_month(c1, none).
claim_valid_arbitration_award_issued(c1, false).
claim_written_proof_of_claim_month(c1, 1).
claim_recovery_sought_month(c1, none).
claim_policy_term_months(c1, 12).
claim_confined_in_us_hospital(c1, true).
claim_continuous_confinement_days(c1, 3).
claim_claim_made_setting_out_basis(c1, true).

% ---------------------------------------------------------------------------
% c2 -- Q2: I am 78 years old at the time of hospitalization.
% ---------------------------------------------------------------------------
claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 3).
claim_hospitalization_ground(c2, sickness).                % not referenced by the question
claim_age_at_hospitalization(c2, 78).                       % given
claim_causes(c2, []).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 2).
claim_wellness_visit_provider_qualified(c2, true).
claim_written_confirmation_month(c2, 3).
claim_dispute_arisen(c2, false).
claim_unable_to_settle_month(c2, none).
claim_arbitration_commenced_month(c2, none).
claim_valid_arbitration_award_issued(c2, false).
claim_written_proof_of_claim_month(c2, 1).
claim_recovery_sought_month(c2, none).
claim_policy_term_months(c2, 12).
claim_confined_in_us_hospital(c2, true).
claim_continuous_confinement_days(c2, 3).
claim_claim_made_setting_out_basis(c2, true).

% ---------------------------------------------------------------------------
% c3 -- Q3: hospitalized for pneumonia 5 months after the effective date, age 65.
% ---------------------------------------------------------------------------
claim_agreement_signed(c3, true).
claim_premium_paid_month(c3, 0).
claim_hospitalization_month(c3, 5).                         % given
claim_hospitalization_ground(c3, sickness).                 % given: pneumonia
claim_age_at_hospitalization(c3, 65).                       % given
claim_causes(c3, []).
claim_fraud_month(c3, none).
claim_misrepresentation_month(c3, none).
claim_wellness_visit_month(c3, 2).
claim_wellness_visit_provider_qualified(c3, true).
claim_written_confirmation_month(c3, 3).
claim_dispute_arisen(c3, false).
claim_unable_to_settle_month(c3, none).
claim_arbitration_commenced_month(c3, none).
claim_valid_arbitration_award_issued(c3, false).
claim_written_proof_of_claim_month(c3, 1).
claim_recovery_sought_month(c3, none).
claim_policy_term_months(c3, 12).
claim_confined_in_us_hospital(c3, true).
claim_continuous_confinement_days(c3, 3).
claim_claim_made_setting_out_basis(c3, true).

% ---------------------------------------------------------------------------
% c4 -- Q4: hospitalized due to a fall while traveling abroad; confirmation of the
% wellness visit given 8 months after the effective date. See NOTES.md: the
% hospitalization month is not stated, and is set here (8) at/after the S1.3
% confirmation deadline (7) so that the late-confirmation fact the question turns
% on is actually tested, rather than defaulted into the "still pending" branch.
% Confinement is treated as abroad, i.e. not in a US hospital (S2.2).
% ---------------------------------------------------------------------------
claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 8).                         % judgement call, see above
claim_hospitalization_ground(c4, accidental_injury).        % given: a fall
claim_age_at_hospitalization(c4, 40).
claim_causes(c4, [other]).
claim_fraud_month(c4, none).
claim_misrepresentation_month(c4, none).
claim_wellness_visit_month(c4, 5).                          % not referenced; set as timely
claim_wellness_visit_provider_qualified(c4, true).
claim_written_confirmation_month(c4, 8).                    % given: 8 months after effective date
claim_dispute_arisen(c4, false).
claim_unable_to_settle_month(c4, none).
claim_arbitration_commenced_month(c4, none).
claim_valid_arbitration_award_issued(c4, false).
claim_written_proof_of_claim_month(c4, 1).
claim_recovery_sought_month(c4, none).
claim_policy_term_months(c4, 12).
claim_confined_in_us_hospital(c4, false).                   % given: traveling abroad
claim_continuous_confinement_days(c4, 3).
claim_claim_made_setting_out_basis(c4, true).

% ---------------------------------------------------------------------------
% c5 -- Q5: hospitalized for punching my own face to show off for my friends;
% no fraud or misrepresentation. See NOTES.md: this deliberate, non-accidental,
% non-illness act is encoded as hospitalization_ground = neither.
% ---------------------------------------------------------------------------
claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 3).
claim_hospitalization_ground(c5, neither).                  % judgement call, see above
claim_age_at_hospitalization(c5, 40).
claim_causes(c5, []).
claim_fraud_month(c5, none).                                % given: did not commit fraud
claim_misrepresentation_month(c5, none).                    % given: did not misrepresent
claim_wellness_visit_month(c5, 2).
claim_wellness_visit_provider_qualified(c5, true).
claim_written_confirmation_month(c5, 3).
claim_dispute_arisen(c5, false).
claim_unable_to_settle_month(c5, none).
claim_arbitration_commenced_month(c5, none).
claim_valid_arbitration_award_issued(c5, false).
claim_written_proof_of_claim_month(c5, 1).
claim_recovery_sought_month(c5, none).
claim_policy_term_months(c5, 12).
claim_confined_in_us_hospital(c5, true).
claim_continuous_confinement_days(c5, 3).
claim_claim_made_setting_out_basis(c5, true).

% ---------------------------------------------------------------------------
% c6 -- Q6: hospitalized due to an injury sustained while skydiving; age 79;
% proof of wellness visit provided 6.5 months after the effective date.
% ---------------------------------------------------------------------------
claim_agreement_signed(c6, true).
claim_premium_paid_month(c6, 0).
claim_hospitalization_month(c6, 7).
claim_hospitalization_ground(c6, accidental_injury).        % given: an injury
claim_age_at_hospitalization(c6, 79).                       % given
claim_causes(c6, [skydiving]).                              % given
claim_fraud_month(c6, none).
claim_misrepresentation_month(c6, none).
claim_wellness_visit_month(c6, 5).                          % not referenced; set as timely
claim_wellness_visit_provider_qualified(c6, true).
claim_written_confirmation_month(c6, 6.5).                  % given: proof provided at 6.5 months
claim_dispute_arisen(c6, false).
claim_unable_to_settle_month(c6, none).
claim_arbitration_commenced_month(c6, none).
claim_valid_arbitration_award_issued(c6, false).
claim_written_proof_of_claim_month(c6, 1).
claim_recovery_sought_month(c6, none).
claim_policy_term_months(c6, 12).
claim_confined_in_us_hospital(c6, true).
claim_continuous_confinement_days(c6, 3).
claim_claim_made_setting_out_basis(c6, true).

% ---------------------------------------------------------------------------
% c7 -- Q7: hospitalized for a heart attack; proof of wellness visit submitted 2
% months after the effective date; age 75.
% ---------------------------------------------------------------------------
claim_agreement_signed(c7, true).
claim_premium_paid_month(c7, 0).
claim_hospitalization_month(c7, 2).
claim_hospitalization_ground(c7, sickness).                 % given: a heart attack
claim_age_at_hospitalization(c7, 75).                       % given
claim_causes(c7, []).
claim_fraud_month(c7, none).
claim_misrepresentation_month(c7, none).
claim_wellness_visit_month(c7, 1).                          % not referenced; set as timely
claim_wellness_visit_provider_qualified(c7, true).
claim_written_confirmation_month(c7, 2).                    % given: submitted at 2 months
claim_dispute_arisen(c7, false).
claim_unable_to_settle_month(c7, none).
claim_arbitration_commenced_month(c7, none).
claim_valid_arbitration_award_issued(c7, false).
claim_written_proof_of_claim_month(c7, 1).
claim_recovery_sought_month(c7, none).
claim_policy_term_months(c7, 12).
claim_confined_in_us_hospital(c7, true).
claim_continuous_confinement_days(c7, 3).
claim_claim_made_setting_out_basis(c7, true).

% ---------------------------------------------------------------------------
% c8 -- Q8: hospitalized after being injured in a military training exercise;
% hospitalization occurred within the policy term; did not commit fraud.
% ---------------------------------------------------------------------------
claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 6).                         % given: within the policy term
claim_hospitalization_ground(c8, accidental_injury).        % given: injured
claim_age_at_hospitalization(c8, 40).
claim_causes(c8, [military_service]).                       % given: military training exercise
claim_fraud_month(c8, none).                                % given: did not commit fraud
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 2).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 3).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, 1).
claim_recovery_sought_month(c8, none).
claim_policy_term_months(c8, 12).                           % given (implicitly): term is 1 year
claim_confined_in_us_hospital(c8, true).
claim_continuous_confinement_days(c8, 3).
claim_claim_made_setting_out_basis(c8, true).

% ---------------------------------------------------------------------------
% c9 -- Q9: hospitalized due to my son biting me in the ankle; proof of wellness
% visit provided 6 months after the effective date; serving as a police officer
% at the time of hospitalization. See NOTES.md: being a police officer at the
% time is not the same as the injury arising out of police service, so
% police_service is not included among the causes.
% ---------------------------------------------------------------------------
claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 6).
claim_hospitalization_ground(c9, accidental_injury).        % given: a bite
claim_age_at_hospitalization(c9, 40).
claim_causes(c9, [other]).                                  % judgement call, see above
claim_fraud_month(c9, none).
claim_misrepresentation_month(c9, none).
claim_wellness_visit_month(c9, 4).                          % not referenced; set as timely
claim_wellness_visit_provider_qualified(c9, true).
claim_written_confirmation_month(c9, 6).                    % given: provided at 6 months
claim_dispute_arisen(c9, false).
claim_unable_to_settle_month(c9, none).
claim_arbitration_commenced_month(c9, none).
claim_valid_arbitration_award_issued(c9, false).
claim_written_proof_of_claim_month(c9, 1).
claim_recovery_sought_month(c9, none).
claim_policy_term_months(c9, 12).
claim_confined_in_us_hospital(c9, true).
claim_continuous_confinement_days(c9, 3).
claim_claim_made_setting_out_basis(c9, true).
