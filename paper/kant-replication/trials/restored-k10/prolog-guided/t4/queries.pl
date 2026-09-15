% queries.pl
%
% Nine claims (c1..c9), one per question in inputs/queries-blind.md, each
% transcribing that question's stated facts into the claim_* vocabulary from
% inputs/schema.md. Every fact not mentioned by the question is set to a
% value that does not by itself trigger an exclusion or break a condition,
% per the standing preamble ("Assuming all other conditions are met and no
% other exclusions apply") and the instruction in inputs/TASK.md to set such
% facts so that "all conditions for coverage are satisfied and no exclusions
% are triggered."
%
% Common non-triggering defaults used across claims unless the question says
% otherwise: agreement signed and premium paid (per the standing preamble);
% no fraud/misrepresentation; a qualified wellness visit and its written
% confirmation both comfortably inside their 6-/7-month deadlines; no
% dispute (so the arbitration machinery is moot); proof of claim submitted
% well before recovery is sought; a full 12-month policy term; confinement
% in a US hospital for a handful of continuous days; and a claim made
% setting out its basis.
%
% Facts are grouped by claim (one block per question) rather than by
% predicate, so every claim_*/2 predicate's clauses are scattered across the
% file; declared discontiguous accordingly.

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
% Q1. Hospitalized by burns suffered while doing my duty as a firefighter.
% ---------------------------------------------------------------------------
q1 :- covered(c1).

claim_agreement_signed(c1, true).
claim_premium_paid_month(c1, 0).
claim_hospitalization_month(c1, 3).
claim_hospitalization_ground(c1, accidental_injury).
claim_age_at_hospitalization(c1, 40).
claim_causes(c1, [firefighting]).
claim_fraud_month(c1, none).
claim_misrepresentation_month(c1, none).
claim_wellness_visit_month(c1, 2).
claim_wellness_visit_provider_qualified(c1, true).
claim_written_confirmation_month(c1, 4).
claim_dispute_arisen(c1, false).
claim_unable_to_settle_month(c1, none).
claim_arbitration_commenced_month(c1, none).
claim_valid_arbitration_award_issued(c1, false).
claim_written_proof_of_claim_month(c1, 1).
claim_recovery_sought_month(c1, 4).
claim_policy_term_months(c1, 12).
claim_confined_in_us_hospital(c1, true).
claim_continuous_confinement_days(c1, 3).
claim_claim_made_setting_out_basis(c1, true).

% ---------------------------------------------------------------------------
% Q2. I am 78 years old at the time of hospitalization.
% ---------------------------------------------------------------------------
q2 :- covered(c2).

claim_agreement_signed(c2, true).
claim_premium_paid_month(c2, 0).
claim_hospitalization_month(c2, 3).
claim_hospitalization_ground(c2, sickness).
claim_age_at_hospitalization(c2, 78).
claim_causes(c2, []).
claim_fraud_month(c2, none).
claim_misrepresentation_month(c2, none).
claim_wellness_visit_month(c2, 2).
claim_wellness_visit_provider_qualified(c2, true).
claim_written_confirmation_month(c2, 4).
claim_dispute_arisen(c2, false).
claim_unable_to_settle_month(c2, none).
claim_arbitration_commenced_month(c2, none).
claim_valid_arbitration_award_issued(c2, false).
claim_written_proof_of_claim_month(c2, 1).
claim_recovery_sought_month(c2, 4).
claim_policy_term_months(c2, 12).
claim_confined_in_us_hospital(c2, true).
claim_continuous_confinement_days(c2, 3).
claim_claim_made_setting_out_basis(c2, true).

% ---------------------------------------------------------------------------
% Q3. Hospitalized for pneumonia 5 months after the policy's effective date;
% age at hospitalization is 65.
% ---------------------------------------------------------------------------
q3 :- covered(c3).

claim_agreement_signed(c3, true).
claim_premium_paid_month(c3, 0).
claim_hospitalization_month(c3, 5).
claim_hospitalization_ground(c3, sickness).
claim_age_at_hospitalization(c3, 65).
claim_causes(c3, []).
claim_fraud_month(c3, none).
claim_misrepresentation_month(c3, none).
claim_wellness_visit_month(c3, 2).
claim_wellness_visit_provider_qualified(c3, true).
claim_written_confirmation_month(c3, 4).
claim_dispute_arisen(c3, false).
claim_unable_to_settle_month(c3, none).
claim_arbitration_commenced_month(c3, none).
claim_valid_arbitration_award_issued(c3, false).
claim_written_proof_of_claim_month(c3, 1).
claim_recovery_sought_month(c3, 4).
claim_policy_term_months(c3, 12).
claim_confined_in_us_hospital(c3, true).
claim_continuous_confinement_days(c3, 3).
claim_claim_made_setting_out_basis(c3, true).

% ---------------------------------------------------------------------------
% Q4. Hospitalized due to a fall while traveling abroad; had given
% confirmation of the wellness visit 8 months after the effective date.
% (Location is not a fact in the schema: §4.1.1 covers the insured anywhere
% in the world, so "traveling abroad" needs no encoding. The confirmation
% month is taken from "confirmation of my wellness visit ... 8 months
% after"; the underlying visit's own month is not stated, so it is set to a
% value comfortably inside its own 6-month deadline. "I had given
% confirmation" (past perfect) is read as: the confirmation was already
% given by the time of the hospitalization, so the hospitalization month is
% set after both the confirmation month and the 7-month deadline.)
% ---------------------------------------------------------------------------
q4 :- covered(c4).

claim_agreement_signed(c4, true).
claim_premium_paid_month(c4, 0).
claim_hospitalization_month(c4, 9).
claim_hospitalization_ground(c4, accidental_injury).
claim_age_at_hospitalization(c4, 40).
claim_causes(c4, []).
claim_fraud_month(c4, none).
claim_misrepresentation_month(c4, none).
claim_wellness_visit_month(c4, 3).
claim_wellness_visit_provider_qualified(c4, true).
claim_written_confirmation_month(c4, 8).
claim_dispute_arisen(c4, false).
claim_unable_to_settle_month(c4, none).
claim_arbitration_commenced_month(c4, none).
claim_valid_arbitration_award_issued(c4, false).
claim_written_proof_of_claim_month(c4, 1).
claim_recovery_sought_month(c4, 4).
claim_policy_term_months(c4, 12).
claim_confined_in_us_hospital(c4, true).
claim_continuous_confinement_days(c4, 3).
claim_claim_made_setting_out_basis(c4, true).

% ---------------------------------------------------------------------------
% Q5. Hospitalized for punching my own face to show off for my friends; did
% not commit fraud or misrepresentation.
% (A deliberate, non-medical act is neither a sickness nor an accidental
% injury, so the hospitalization ground is "neither".)
% ---------------------------------------------------------------------------
q5 :- covered(c5).

claim_agreement_signed(c5, true).
claim_premium_paid_month(c5, 0).
claim_hospitalization_month(c5, 3).
claim_hospitalization_ground(c5, neither).
claim_age_at_hospitalization(c5, 40).
claim_causes(c5, [other]).
claim_fraud_month(c5, none).
claim_misrepresentation_month(c5, none).
claim_wellness_visit_month(c5, 2).
claim_wellness_visit_provider_qualified(c5, true).
claim_written_confirmation_month(c5, 4).
claim_dispute_arisen(c5, false).
claim_unable_to_settle_month(c5, none).
claim_arbitration_commenced_month(c5, none).
claim_valid_arbitration_award_issued(c5, false).
claim_written_proof_of_claim_month(c5, 1).
claim_recovery_sought_month(c5, 4).
claim_policy_term_months(c5, 12).
claim_confined_in_us_hospital(c5, true).
claim_continuous_confinement_days(c5, 3).
claim_claim_made_setting_out_basis(c5, true).

% ---------------------------------------------------------------------------
% Q6. Hospitalized due to an injury sustained while skydiving; age at
% hospitalization 79; proof of the wellness visit was provided 6.5 months
% after the effective date.
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
claim_wellness_visit_month(c6, 3).
claim_wellness_visit_provider_qualified(c6, true).
claim_written_confirmation_month(c6, 6.5).
claim_dispute_arisen(c6, false).
claim_unable_to_settle_month(c6, none).
claim_arbitration_commenced_month(c6, none).
claim_valid_arbitration_award_issued(c6, false).
claim_written_proof_of_claim_month(c6, 1).
claim_recovery_sought_month(c6, 4).
claim_policy_term_months(c6, 12).
claim_confined_in_us_hospital(c6, true).
claim_continuous_confinement_days(c6, 3).
claim_claim_made_setting_out_basis(c6, true).

% ---------------------------------------------------------------------------
% Q7. Hospitalized for a heart attack; proof of the wellness visit was
% submitted 2 months after the effective date; age at hospitalization 75.
% (A heart attack is an internal medical event, classified here as sickness
% rather than accidental injury.)
% ---------------------------------------------------------------------------
q7 :- covered(c7).

claim_agreement_signed(c7, true).
claim_premium_paid_month(c7, 0).
claim_hospitalization_month(c7, 3).
claim_hospitalization_ground(c7, sickness).
claim_age_at_hospitalization(c7, 75).
claim_causes(c7, []).
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
claim_recovery_sought_month(c7, 4).
claim_policy_term_months(c7, 12).
claim_confined_in_us_hospital(c7, true).
claim_continuous_confinement_days(c7, 3).
claim_claim_made_setting_out_basis(c7, true).

% ---------------------------------------------------------------------------
% Q8. Hospitalized after being injured in a military training exercise; the
% hospitalization occurred within the policy term; did not commit fraud.
% ---------------------------------------------------------------------------
q8 :- covered(c8).

claim_agreement_signed(c8, true).
claim_premium_paid_month(c8, 0).
claim_hospitalization_month(c8, 3).
claim_hospitalization_ground(c8, accidental_injury).
claim_age_at_hospitalization(c8, 40).
claim_causes(c8, [military_service]).
claim_fraud_month(c8, none).
claim_misrepresentation_month(c8, none).
claim_wellness_visit_month(c8, 2).
claim_wellness_visit_provider_qualified(c8, true).
claim_written_confirmation_month(c8, 4).
claim_dispute_arisen(c8, false).
claim_unable_to_settle_month(c8, none).
claim_arbitration_commenced_month(c8, none).
claim_valid_arbitration_award_issued(c8, false).
claim_written_proof_of_claim_month(c8, 1).
claim_recovery_sought_month(c8, 4).
claim_policy_term_months(c8, 12).
claim_confined_in_us_hospital(c8, true).
claim_continuous_confinement_days(c8, 3).
claim_claim_made_setting_out_basis(c8, true).

% ---------------------------------------------------------------------------
% Q9. Hospitalized due to my son biting me in the ankle; proof of the
% wellness visit was provided 6 months after the effective date; I was
% serving as a police officer at the time of hospitalization.
% (Serving as a police officer is a status, not a cause: the injury arose
% from a family member's bite, not from anything done in the course of
% police service, so the police-service exclusion is not triggered.)
% ---------------------------------------------------------------------------
q9 :- covered(c9).

claim_agreement_signed(c9, true).
claim_premium_paid_month(c9, 0).
claim_hospitalization_month(c9, 3).
claim_hospitalization_ground(c9, accidental_injury).
claim_age_at_hospitalization(c9, 40).
claim_causes(c9, [other]).
claim_fraud_month(c9, none).
claim_misrepresentation_month(c9, none).
claim_wellness_visit_month(c9, 3).
claim_wellness_visit_provider_qualified(c9, true).
claim_written_confirmation_month(c9, 6).
claim_dispute_arisen(c9, false).
claim_unable_to_settle_month(c9, none).
claim_arbitration_commenced_month(c9, none).
claim_valid_arbitration_award_issued(c9, false).
claim_written_proof_of_claim_month(c9, 1).
claim_recovery_sought_month(c9, 4).
claim_policy_term_months(c9, 12).
claim_confined_in_us_hospital(c9, true).
claim_continuous_confinement_days(c9, 3).
claim_claim_made_setting_out_basis(c9, true).
