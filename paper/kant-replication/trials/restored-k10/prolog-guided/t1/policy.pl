% policy.pl -- Codex Insurance Limited hospital-income policy, encoded as
% covered(C): true exactly when a benefit is payable on claim C.
%
% Helper predicates are named after the contract clause they implement, so
% the mapping back to the source text (fixtures/chubb-policy.txt) is
% traceable. No claim facts are defined in this file (see queries.pl).

% ---------------------------------------------------------------------
% Supporting predicates -- copied verbatim from bench/schema-prolog.md.
% Do not redefine; call them.
% ---------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------
% Section 1: Policy in effect and conditions.
% ---------------------------------------------------------------------

% 1.1(1): the agreement is signed.
agreement_signed(C) :-
    claim_agreement_signed(C, true).

% 1.1(2): the applicable premium has been paid, by the time of the
% hospitalization the claim is premised on.
premium_paid(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_premium_paid_month(C, PremiumMonth),
    no_later_than(PremiumMonth, HospMonth).

% 1.3: no later than the 6-month anniversary, a wellness visit with a
% qualified medical provider; no later than the 7-month anniversary,
% written confirmation of that visit.
wellness_visit_timely(C) :-
    claim_wellness_visit_month(C, VisitMonth),
    no_later_than(VisitMonth, 6),
    claim_wellness_visit_provider_qualified(C, true).

confirmation_timely(C) :-
    claim_written_confirmation_month(C, ConfirmMonth),
    no_later_than(ConfirmMonth, 7).

condition_1_3_satisfied(C) :-
    wellness_visit_timely(C),
    confirmation_timely(C).

% 1.1(3)'s "still pending": at the time of hospitalization, the 7-month
% deadline for written confirmation has not yet passed, so the condition
% cannot yet be said to have failed.
condition_1_3_pending(C) :-
    claim_hospitalization_month(C, HospMonth),
    no_later_than(HospMonth, 7).

condition_1_3_ok(C) :- condition_1_3_satisfied(C).
condition_1_3_ok(C) :- condition_1_3_pending(C).

% 1.2: fraud, or misrepresentation/material withholding of information, in
% connection with the policy, is a cancelation trigger. (The schema has no
% separate "withholding" fact; claim_misrepresentation_month stands in for
% both prongs of that disjunct.) Neither prong carries an explicit
% deadline in the text, so occurrence at any time suffices.
fraud_occurred(C) :-
    claim_fraud_month(C, M),
    number(M).

misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, M),
    number(M).

% 1.2 / 4.6: automatically canceled once the policy term has elapsed as of
% the hospitalization.
policy_term_expired(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_policy_term_months(C, TermMonths),
    HospMonth > TermMonths.

% 1.2: cancelation is deemed to have occurred whenever any one of these
% holds. This single definition serves both 1.1(3)'s "pending or satisfied"
% test and 1.2's "not satisfied in a timely fashion" trigger -- the two are
% logical mirror images of the same condition, so folding condition_1_3's
% failure in here (rather than also re-checking condition_1_3_ok as a
% separate top-level conjunct of policy_in_effect/1) avoids stating the
% same requirement twice.
canceled(C) :- fraud_occurred(C).
canceled(C) :- misrepresentation_occurred(C).
canceled(C) :- \+ condition_1_3_ok(C).
canceled(C) :- policy_term_expired(C).

% 1.1: the policy is in effect at the time of hospitalization iff the
% agreement is signed, the premium has been paid, and the policy has not
% been canceled.
policy_in_effect(C) :-
    agreement_signed(C),
    premium_paid(C),
    \+ canceled(C).

% ---------------------------------------------------------------------
% Section 2: Benefits.
% ---------------------------------------------------------------------

% 2.1: the hospitalization must actually be for sickness or accidental
% injury, as opposed to some other ground the policy does not reach.
ground_covered(C) :-
    claim_hospitalization_ground(C, Ground),
    memberchk(Ground, [sickness, accidental_injury]).

% 2.2: the benefit is payable only for continuous confinement in a
% hospital in the United States.
confinement_ok(C) :-
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    number(Days),
    Days > 0.

% 2.3: a claim must actually be made, setting out the basis for the claim
% and for there being no exclusion or cancellation.
claim_procedure_ok(C) :-
    claim_claim_made_setting_out_basis(C, true).

% ---------------------------------------------------------------------
% Section 3: General exclusions.
% ---------------------------------------------------------------------

excluded(C) :-
    claim_causes(C, Causes),
    arose_out_of(Causes, skydiving).
excluded(C) :-
    claim_causes(C, Causes),
    arose_out_of(Causes, military_service).
excluded(C) :-
    claim_causes(C, Causes),
    arose_out_of(Causes, firefighting).
excluded(C) :-
    claim_causes(C, Causes),
    arose_out_of(Causes, police_service).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    number(Age),
    Age >= 80.

% ---------------------------------------------------------------------
% Section 4.2: Arbitration.
% ---------------------------------------------------------------------

% 4.2.1: if a dispute has arisen, arbitration must be commenced within
% three months of the parties becoming unable to settle, and a valid
% arbitration award is a condition precedent to liability. Absent any
% dispute, this clause is vacuously satisfied.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, UnableMonth),
    number(UnableMonth),
    Limit is UnableMonth + 3,
    claim_arbitration_commenced_month(C, ArbMonth),
    no_later_than(ArbMonth, Limit),
    claim_valid_arbitration_award_issued(C, true).

% 4.2.1: in no case may recovery be sought before the expiration of sixty
% (60) days -- taken as two months, consistent with the month-denominated
% units used throughout this schema -- after written proof of claim has
% been submitted. Not yet having sought recovery is not itself a
% violation.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, none).
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, RecoveryMonth),
    number(RecoveryMonth),
    claim_written_proof_of_claim_month(C, ProofMonth),
    Limit is RecoveryMonth - 2,
    no_later_than(ProofMonth, Limit).

% ---------------------------------------------------------------------
% Top level.
% ---------------------------------------------------------------------

covered(C) :-
    policy_in_effect(C),
    ground_covered(C),
    \+ excluded(C),
    confinement_ok(C),
    claim_procedure_ok(C),
    arbitration_ok(C),
    recovery_timing_ok(C).
