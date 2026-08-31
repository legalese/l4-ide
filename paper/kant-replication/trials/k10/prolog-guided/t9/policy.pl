% policy.pl
%
% covered(C) is true exactly when a benefit is payable on claim C, under the
% CODEX INSURANCE LIMITED policy in inputs/chubb-policy.txt.
%
% Claim facts (claim_*/2) are supplied by the caller (see queries.pl); this
% file defines only covered/1 and its helper rules, plus the two supporting
% predicates from the schema, included verbatim so this file is
% self-contained.

% ---------------------------------------------------------------------
% Supporting predicates (from inputs/schema.md, verbatim)
% ---------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------
% Top-level rule
% ---------------------------------------------------------------------

%! covered(+C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    qualifying_hospitalization(C),   % 1.1 preamble: for sickness or accidental injury
    policy_in_effect(C),             % 1.1(1)-(4), via 1.2
    \+ excluded(C),                  % 2.1
    arbitration_ok(C),               % 3.2.1
    recovery_timing_ok(C).           % 3.2.1, last sentence

% 1.1 preamble: a hospitalization that is neither sickness nor accidental
% injury is outside the scope of the policy altogether, regardless of
% anything else.
qualifying_hospitalization(C) :-
    claim_hospitalization_ground(C, Ground),
    Ground \= neither.

% ---------------------------------------------------------------------
% Section 1: policy in effect
% ---------------------------------------------------------------------

%! policy_in_effect(+C) is semidet.
%  The policy is in effect at the time of the hospitalization on claim C
%  (1.1: signed, premium paid, condition 1.3 pending-or-satisfied, and not
%  canceled).
policy_in_effect(C) :-
    claim_agreement_signed(C, true),   % 1.1(1)
    premium_paid(C),                   % 1.1(2)
    \+ canceled(C).                    % 1.1(3)+(4), via 1.2

% 1.1(2): the applicable premium has been paid, at or before the
% hospitalization it is meant to cover.
premium_paid(C) :-
    claim_premium_paid_month(C, PaidMonth),
    claim_hospitalization_month(C, HospMonth),
    no_later_than(PaidMonth, HospMonth).

% 1.2: cancelation. Any of these, current as of the time of the
% hospitalization, means the policy is not in effect.
canceled(C) :- canceled_by_fraud(C).
canceled(C) :- canceled_by_misrepresentation(C).
canceled(C) :- canceled_by_condition_1_3(C).
canceled(C) :- canceled_by_term_expiry(C).

% Fraud, at or before the hospitalization it would taint.
canceled_by_fraud(C) :-
    claim_fraud_month(C, FraudMonth),
    claim_hospitalization_month(C, HospMonth),
    no_later_than(FraudMonth, HospMonth).

% Misrepresentation (also standing in for "material withholding of any
% information", which has no separate claim fact in the schema), at or
% before the hospitalization it would taint.
canceled_by_misrepresentation(C) :-
    claim_misrepresentation_month(C, MisrepMonth),
    claim_hospitalization_month(C, HospMonth),
    no_later_than(MisrepMonth, HospMonth).

% 1.3's own deadline is the 7-month anniversary of the effective date.
% Before that instant 1.1(3) treats the condition as merely "pending", so
% it cannot yet be a reason for cancelation; only once the deadline has
% passed does an unsatisfied condition 1.3 cancel the policy.
canceled_by_condition_1_3(C) :-
    claim_hospitalization_month(C, HospMonth),
    HospMonth > 7,
    \+ condition_1_3_satisfied(C).

% 1.3 is satisfied in a timely fashion when written confirmation of a
% qualifying wellness visit is supplied by the 7-month anniversary, and the
% visit it confirms itself occurred by the 6-month anniversary with a
% qualified medical provider.
condition_1_3_satisfied(C) :-
    claim_written_confirmation_month(C, ConfirmMonth),
    no_later_than(ConfirmMonth, 7),
    claim_wellness_visit_month(C, VisitMonth),
    no_later_than(VisitMonth, 6),
    claim_wellness_visit_provider_qualified(C, true).

% 1.2, last sentence: automatic cancelation at the end of the policy term.
canceled_by_term_expiry(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_policy_term_months(C, TermMonths),
    HospMonth > TermMonths.

% ---------------------------------------------------------------------
% Section 2: general exclusions
% ---------------------------------------------------------------------

%! excluded(+C) is semidet.
excluded(C) :- excluded_by_cause(C).
excluded(C) :- excluded_by_age(C).

% 2.1(1)-(4): sickness or accidental injury arising directly or indirectly
% out of skydiving, military service, firefighting, or police service.
excluded_by_cause(C) :-
    claim_causes(C, Causes),
    member(Cause, [skydiving, military_service, firefighting, police_service]),
    arose_out_of(Causes, Cause).

% 2.1(5): age at the time of the hospitalization is >= 80. (Drafted as if
% continuing the "arising out of" list, but an age threshold cannot arise
% out of anything; treated as its own, cause-independent exclusion.)
excluded_by_age(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% ---------------------------------------------------------------------
% Section 3.2: arbitration
% ---------------------------------------------------------------------

%! arbitration_ok(+C) is semidet.
%  Only bites when a dispute has arisen at all; otherwise this condition
%  precedent never comes into play.
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    !,
    arbitration_ok_given_dispute(C).
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).

% Once a dispute exists, the arbitration/award requirements only bind once
% the parties are unable to settle (by analogy to how 1.1(3) treats
% condition 1.3 as "pending" before its own deadline); until then there is
% no settlement-impasse date to measure the 3-month clock from.
arbitration_ok_given_dispute(C) :-
    claim_unable_to_settle_month(C, none),
    !.
arbitration_ok_given_dispute(C) :-
    claim_unable_to_settle_month(C, UnableMonth),
    number(UnableMonth),
    ArbitrationLimit is UnableMonth + 3,
    claim_arbitration_commenced_month(C, ArbitrationMonth),
    no_later_than(ArbitrationMonth, ArbitrationLimit),
    claim_valid_arbitration_award_issued(C, true).

% ---------------------------------------------------------------------
% Section 3.2.1, last sentence: 60-day proof-of-claim delay
% ---------------------------------------------------------------------

%! recovery_timing_ok(+C) is semidet.
%  Only bites once recovery has actually been sought; a claim that has not
%  yet sought recovery cannot have sought it prematurely.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, none),
    !.
recovery_timing_ok(C) :-
    claim_recovery_sought_month(C, RecoveryMonth),
    number(RecoveryMonth),
    claim_written_proof_of_claim_month(C, ProofMonth),
    number(ProofMonth),
    EarliestRecoveryMonth is ProofMonth + 2,   % 60 days ~= 2 months
    no_later_than(EarliestRecoveryMonth, RecoveryMonth).
