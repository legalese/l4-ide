% ===========================================================================
% queries.pl
%
% Nine claims (c1..c9), one per benchmark question in inputs/queries-blind.md.
% Each qN/0 succeeds iff covered(cN) holds. Every claim defines all 21
% claim_* facts from inputs/schema.md. Facts not mentioned by the question
% are set to values that satisfy every condition and trigger no exclusion,
% per the standing preamble ("assuming all other conditions are met and no
% other exclusions apply") and the task's own instruction to do the same.
%
% Consult policy.pl alongside this file for covered/1.
% ===========================================================================

% Facts are grouped per claim (per the task's own example layout), not per
% predicate, so each claim_*/2 predicate's clauses are not contiguous in
% this file. Declared discontiguous to keep the load check silent; this
% changes no semantics.
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

% ---------------------------------------------------------------------------
% Q1: hospitalized by burns suffered while doing my duty as a firefighter.
% -> excluded cause: firefighting.
% ---------------------------------------------------------------------------
q1 :- covered(c1).

claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 3).
claim_hospitalization_ground(c1, accidental_injury).
claim_age_at_hospitalization(c1, 30).
claim_causes(c1, [firefighting]).
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 3).
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
claim_continuous_confinement_days(c1, 5).
claim_claim_made_setting_out_basis(c1, true).

% ---------------------------------------------------------------------------
% Q2: 78 years old at the time of hospitalization.
% -> age is below the 80-year exclusion threshold; no cause of interest.
% ---------------------------------------------------------------------------
q2 :- covered(c2).

claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 3).
claim_hospitalization_ground(c2, sickness).
claim_age_at_hospitalization(c2, 78).
claim_causes(c2, [other]).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 3).
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
claim_continuous_confinement_days(c2, 5).
claim_claim_made_setting_out_basis(c2, true).

% ---------------------------------------------------------------------------
% Q3: hospitalized for pneumonia 5 months after the effective date; age 65.
% -> sickness, no excluded cause, age below threshold.
% ---------------------------------------------------------------------------
q3 :- covered(c3).

claim_agreement_signed(c3, true).
claim_premium_paid_month(c3, 0).
claim_hospitalization_month(c3, 5).
claim_hospitalization_ground(c3, sickness).
claim_age_at_hospitalization(c3, 65).
claim_causes(c3, [other]).
claim_fraud_month(c3, none).
claim_misrepresentation_month(c3, none).
claim_wellness_visit_month(c3, 3).
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
claim_continuous_confinement_days(c3, 5).
claim_claim_made_setting_out_basis(c3, true).

% ---------------------------------------------------------------------------
% Q4: hospitalized due to a fall while traveling abroad; wellness visit
% confirmation given 8 months after the effective date.
% -> hospitalized abroad: fails Section 2.2's US-hospital requirement.
% -> confirmation at month 8 is later than the month-7 deadline in Section
%    1.3: a completed (not merely pending) breach, so it also fails
%    condition_1_3_ok/1 independently of when the hospitalization occurred.
%    The wellness visit itself is placed at month 5 (on time) so that only
%    the confirmation's lateness -- the fact the question actually gives --
%    is what fails Section 1.3, not an invented late visit.
% ---------------------------------------------------------------------------
q4 :- covered(c4).

claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 9).
claim_hospitalization_ground(c4, accidental_injury).
claim_age_at_hospitalization(c4, 40).
claim_causes(c4, [other]).
claim_fraud_month(c4, none).
claim_misrepresentation_month(c4, none).
claim_wellness_visit_month(c4, 5).
claim_wellness_visit_provider_qualified(c4, true).
claim_written_confirmation_month(c4, 8).
claim_dispute_arisen(c4, false).
claim_unable_to_settle_month(c4, none).
claim_arbitration_commenced_month(c4, none).
claim_valid_arbitration_award_issued(c4, false).
claim_written_proof_of_claim_month(c4, 1).
claim_recovery_sought_month(c4, none).
claim_policy_term_months(c4, 12).
claim_confined_in_us_hospital(c4, false).
claim_continuous_confinement_days(c4, 5).
claim_claim_made_setting_out_basis(c4, true).

% ---------------------------------------------------------------------------
% Q5: hospitalized for punching my own face to show off for my friends; no
% fraud or misrepresentation.
% -> self-inflicted but unintended harm; not among the listed exclusions.
% ---------------------------------------------------------------------------
q5 :- covered(c5).

claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 3).
claim_hospitalization_ground(c5, accidental_injury).
claim_age_at_hospitalization(c5, 25).
claim_causes(c5, [other]).
claim_fraud_month(c5, none).
claim_misrepresentation_month(c5, none).
claim_wellness_visit_month(c5, 3).
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
claim_continuous_confinement_days(c5, 5).
claim_claim_made_setting_out_basis(c5, true).

% ---------------------------------------------------------------------------
% Q6: injury sustained while skydiving; age 79 at hospitalization; wellness
% visit confirmation given 6.5 months after the effective date.
% -> excluded cause: skydiving. (Age 79 and the 6.5-month confirmation are
%    both individually fine -- under 80, and under the month-7 deadline,
%    with the underlying visit placed at month 6, also on time -- so the
%    only thing that fails this claim is the skydiving exclusion.)
% ---------------------------------------------------------------------------
q6 :- covered(c6).

claim_agreement_signed(c6, true).
claim_premium_paid_month(c6, 0).
claim_hospitalization_month(c6, 3).
claim_hospitalization_ground(c6, accidental_injury).
claim_age_at_hospitalization(c6, 79).
claim_causes(c6, [skydiving]).
claim_fraud_month(c6, none).
claim_misrepresentation_month(c6, none).
claim_wellness_visit_month(c6, 6).
claim_wellness_visit_provider_qualified(c6, true).
claim_written_confirmation_month(c6, 6.5).
claim_dispute_arisen(c6, false).
claim_unable_to_settle_month(c6, none).
claim_arbitration_commenced_month(c6, none).
claim_valid_arbitration_award_issued(c6, false).
claim_written_proof_of_claim_month(c6, 1).
claim_recovery_sought_month(c6, none).
claim_policy_term_months(c6, 12).
claim_confined_in_us_hospital(c6, true).
claim_continuous_confinement_days(c6, 5).
claim_claim_made_setting_out_basis(c6, true).

% ---------------------------------------------------------------------------
% Q7: hospitalized for a heart attack; wellness visit confirmation
% submitted 2 months after the effective date; age 75.
% -> sickness, no excluded cause, age below threshold, confirmation timely.
% ---------------------------------------------------------------------------
q7 :- covered(c7).

claim_agreement_signed(c7, true).
claim_premium_paid_month(c7, 0).
claim_hospitalization_month(c7, 3).
claim_hospitalization_ground(c7, sickness).
claim_age_at_hospitalization(c7, 75).
claim_causes(c7, [other]).
claim_fraud_month(c7, none).
claim_misrepresentation_month(c7, none).
claim_wellness_visit_month(c7, 1).
claim_wellness_visit_provider_qualified(c7, true).
claim_written_confirmation_month(c7, 2).
claim_dispute_arisen(c7, false).
claim_unable_to_settle_month(c7, none).
claim_arbitration_commenced_month(c7, none).
claim_valid_arbitration_award_issued(c7, false).
claim_written_proof_of_claim_month(c7, 1).
claim_recovery_sought_month(c7, none).
claim_policy_term_months(c7, 12).
claim_confined_in_us_hospital(c7, true).
claim_continuous_confinement_days(c7, 5).
claim_claim_made_setting_out_basis(c7, true).

% ---------------------------------------------------------------------------
% Q8: injured in a military training exercise; hospitalization occurred
% within the policy term; no fraud.
% -> excluded cause: military_service (training exercises are part of
%    "service in the military"; the exclusion carries no combat/duty
%    qualifier). Being within the policy term does not cure this.
% ---------------------------------------------------------------------------
q8 :- covered(c8).

claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 3).
claim_hospitalization_ground(c8, accidental_injury).
claim_age_at_hospitalization(c8, 30).
claim_causes(c8, [military_service]).
claim_fraud_month(c8, none).
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 3).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 3).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, 1).
claim_recovery_sought_month(c8, none).
claim_policy_term_months(c8, 12).
claim_confined_in_us_hospital(c8, true).
claim_continuous_confinement_days(c8, 5).
claim_claim_made_setting_out_basis(c8, true).

% ---------------------------------------------------------------------------
% Q9: hospitalized due to my son biting me in the ankle; wellness visit
% confirmation given 6 months after the effective date; serving as a
% police officer at the time of hospitalization.
% -> being a police officer at the time is not itself a listed cause; the
%    cause of the injury is the bite, which is not "service in the
%    police", so the police_service exclusion (arising "directly or
%    indirectly out of" that service) is not triggered. Confirmation at
%    month 6 is timely (the underlying visit is placed at month 6 too, the
%    latest moment that is still "no later than" the month-6 deadline).
% ---------------------------------------------------------------------------
q9 :- covered(c9).

claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 3).
claim_hospitalization_ground(c9, accidental_injury).
claim_age_at_hospitalization(c9, 35).
claim_causes(c9, [other]).
claim_fraud_month(c9, none).
claim_misrepresentation_month(c9, none).
claim_wellness_visit_month(c9, 6).
claim_wellness_visit_provider_qualified(c9, true).
claim_written_confirmation_month(c9, 6).
claim_dispute_arisen(c9, false).
claim_unable_to_settle_month(c9, none).
claim_arbitration_commenced_month(c9, none).
claim_valid_arbitration_award_issued(c9, false).
claim_written_proof_of_claim_month(c9, 1).
claim_recovery_sought_month(c9, none).
claim_policy_term_months(c9, 12).
claim_confined_in_us_hospital(c9, true).
claim_continuous_confinement_days(c9, 5).
claim_claim_made_setting_out_basis(c9, true).
