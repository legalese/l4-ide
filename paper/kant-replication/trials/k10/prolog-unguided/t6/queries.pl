% ============================================================================
% queries.pl -- the nine benchmark questions (Kant et al. 2025, App. A.2).
% ============================================================================
%
% Consulted after policy.pl. For each question this file asserts the
% per-claim facts the question gives us, then defines a zero-arity query
% predicate q1..q9 that succeeds exactly when the answer to that question
% is "yes" (i.e. "my policy will apply").
%
% Standing preamble applied to every question (per the benchmark and per
% the task brief): the agreement is signed and the premium paid on time;
% every condition for the policy to apply that is NOT mentioned in the
% question is satisfied; and no exclusion NOT mentioned in the question
% applies. Concretely:
%   - A fact that would trigger an exclusion or a cancelation
%     (arises_out_of/2, claimant_age/2 vs. 80, fraud_or_misrepresentation/1,
%     the two wellness-deadline facts vs. their thresholds,
%     hospitalization_month/2 vs. the 12-month term) is asserted below
%     ONLY when the question states it. policy.pl's rules are written so
%     that leaving such a fact unasserted never triggers the exclusion or
%     cancelation it belongs to -- that is what realises "unrelated
%     conditions/exclusions are satisfied" for all of these.
%   - hospitalization_type/2 is the one fact that works the other way
%     around (it must be affirmatively present for coverage to attach at
%     all -- see policy.pl), so it is asserted for every claim below,
%     including the ones where the question does not dwell on the medical
%     cause.
%
% See NOTES.md for the judgement calls flagged inline below (Q5 and Q9
% in particular).
% ----------------------------------------------------------------------

:- discontiguous hospitalization_type/2.
:- discontiguous claimant_age/2.
:- discontiguous arises_out_of/2.
:- discontiguous wellness_confirmation_month/2.

% ---- Q1 --------------------------------------------------------------
% "will my policy apply if I was hospitalized by burns suffered while
% doing my duty as a firefighter?"
% Burns are an accidental injury; they arose directly out of the
% claimant's service as a firefighter -> s.2.1(3) excludes it.
hospitalization_type(claim_1, accidental_injury).
arises_out_of(claim_1, firefighter_service).
q1 :- covered(claim_1).

% ---- Q2 --------------------------------------------------------------
% "will my policy apply if I am 78 years old at the time of
% hospitalization?"
% The question does not state a cause, so a neutral qualifying event is
% asserted (see the file header re: hospitalization_type/2). 78 is
% under the s.2.1(5) threshold of 80, so age does not exclude it.
hospitalization_type(claim_2, accidental_injury).
claimant_age(claim_2, 78).
q2 :- covered(claim_2).

% ---- Q3 --------------------------------------------------------------
% "will my policy apply if I was hospitalized for pneumonia 5 months
% after the policy's effective date, and my age at the time of
% hospitalization is 65?"
% Pneumonia is a sickness. Age 65 is under the s.2.1(5) threshold. 5
% months after the effective date is within the one-year policy term
% (s.3.6), and is also before either s.1.3 deadline, so nothing here
% causes a cancelation.
hospitalization_type(claim_3, sickness).
claimant_age(claim_3, 65).
hospitalization_month(claim_3, 5).
q3 :- covered(claim_3).

% ---- Q4 --------------------------------------------------------------
% "will my policy apply if I was hospitalized due to a fall while
% traveling abroad and I had given confirmation of my wellness visit 8
% months after the policy's effective date?"
% A fall is an accidental injury; traveling abroad is not a problem
% (s.3.1: worldwide coverage). But confirmation supplied at month 8 is
% later than the s.1.3 7-month deadline, so s.1.3 was not satisfied in a
% timely fashion and the policy is deemed canceled under s.1.2.
hospitalization_type(claim_4, accidental_injury).
wellness_confirmation_month(claim_4, 8).
q4 :- covered(claim_4).

% ---- Q5 --------------------------------------------------------------
% "will my policy apply if I was hospitalized for punching my own face
% to show off for my friends and I did not commit fraud or
% misrepresentation?"
% JUDGEMENT CALL (see NOTES.md): deliberately punching your own face to
% show off is a self-inflicted, intentional act, not "sickness" or an
% "accidental injury" -- so this hospitalization does not meet s.1.1's
% basic description of what the policy covers in the first place, quite
% apart from the s.2 exclusion list (which has no self-inflicted-injury
% item at all). The "no fraud or misrepresentation" clause in the
% question is there to foreclose the s.1.2/s.1.1(4) cancelation route;
% it is honoured here simply by NOT asserting
% fraud_or_misrepresentation(claim_5).
hospitalization_type(claim_5, intentional_self_inflicted_injury).
q5 :- covered(claim_5).

% ---- Q6 --------------------------------------------------------------
% "will my policy apply if I was hospitalized due to an injury sustained
% while skydiving, my age at the time of hospitalization was 79, and
% proof of my wellness visit was provided 6.5 months after the policy's
% effective date?"
% The injury arose directly out of skydiving -> s.2.1(1) excludes it,
% regardless of age (79 is under the s.2.1(5) threshold anyway) and
% regardless of the wellness-visit timing (6.5 months is within the
% 7-month s.1.3 deadline anyway).
hospitalization_type(claim_6, accidental_injury).
arises_out_of(claim_6, skydiving).
claimant_age(claim_6, 79).
wellness_confirmation_month(claim_6, 6.5).
q6 :- covered(claim_6).

% ---- Q7 --------------------------------------------------------------
% "will my policy apply if I was hospitalized for a heart attack, proof
% of the wellness visit was submitted 2 months after the policy's
% effective date, and my age at the time of hospitalization was 75?"
% A heart attack is a sickness. Confirmation at month 2 is well within
% the s.1.3 7-month deadline. Age 75 is under the s.2.1(5) threshold.
% Nothing excludes or cancels this claim.
hospitalization_type(claim_7, sickness).
claimant_age(claim_7, 75).
wellness_confirmation_month(claim_7, 2).
q7 :- covered(claim_7).

% ---- Q8 --------------------------------------------------------------
% "will my policy apply if I was hospitalized after being injured in a
% military training exercise, the hospitalization occurred within the
% policy term, and I did not commit fraud?"
% The injury arose directly out of service in the military (a training
% exercise is still "service in the military") -> s.2.1(2) excludes it.
% "Within the policy term" and "no fraud" are exactly the defaults
% policy.pl already applies when hospitalization_month/2 and
% fraud_or_misrepresentation/1 are left unasserted, so no explicit fact
% is needed for either -- they are red herrings against the military
% exclusion, which controls regardless.
hospitalization_type(claim_8, accidental_injury).
arises_out_of(claim_8, military_service).
q8 :- covered(claim_8).

% ---- Q9 --------------------------------------------------------------
% "will my policy apply if I was hospitalized due to my son biting me in
% the ankle, proof of my wellness visit was provided 6 months after the
% effective date, and I was serving as a police officer at the time of
% hospitalization?"
% JUDGEMENT CALL (see NOTES.md): being bitten on the ankle by one's own
% son is an accidental injury with no stated causal connection to the
% claimant's police duties. s.2.1(4) excludes injuries arising directly
% or indirectly OUT OF service in the police, not merely injuries that
% happen to occur while the claimant holds that job -- so
% arises_out_of(claim_9, police_service) is deliberately NOT asserted.
% Confirmation at month 6 is within the s.1.3 7-month deadline.
hospitalization_type(claim_9, accidental_injury).
wellness_confirmation_month(claim_9, 6).
q9 :- covered(claim_9).
