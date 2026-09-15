% policy.pl
%
% covered(C): true exactly when a benefit is payable on claim C, per the
% CODEX INSURANCE LIMITED policy (inputs/chubb-policy.txt).
%
% This file defines covered/1 and its helper rules only. Claim facts
% (claim_*/2) are supplied by the caller (see queries.pl) and are not
% defined here.

% ---------------------------------------------------------------------
% Supporting predicates (verbatim from inputs/schema.md). Do not redefine.
% ---------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------
% Top-level rule.
% ---------------------------------------------------------------------

%! covered(?C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    valid_ground(C),
    policy_in_effect(C),
    \+ excluded(C),
    arbitration_ok(C),
    waiting_period_ok(C).

% 1.1: the hospitalization on which the claim is premised must be for
% sickness or accidental injury (as opposed to an event that is neither).
valid_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    memberchk(Ground, [sickness, accidental_injury]).

% ---------------------------------------------------------------------
% 1.1 / 1.2 / 1.3: the policy must be "in effect" at the time of the
% hospitalization.
% ---------------------------------------------------------------------

policy_in_effect(C) :-
    claim_agreement_signed(C, true),          % 1.1(1)
    premium_paid(C),                          % 1.1(2)
    condition_1_3_ok(C),                      % 1.1(3)
    \+ cancelling_conduct(C),                 % 1.1(4) / 1.2
    within_term(C).                           % 1.1(4) / 1.2 / 3.6

% 1.1(2) / 3.5.1: the applicable premium has been paid.
premium_paid(C) :-
    claim_premium_paid_month(C, M),
    number(M).

% 1.3: no later than the 7th month anniversary of the effective date,
% written confirmation of a wellness visit (a visit that itself occurred
% no later than the 6th month anniversary, with a qualified medical
% provider) must be supplied. Section 1.1(3) treats this condition as met,
% for purposes of the policy being "in effect", if it is either already
% satisfied, or still pending -- i.e. its 7-month deadline has not yet
% arrived as of the hospitalization being claimed on. (Judgement call:
% see NOTES.md.)
condition_1_3_ok(C) :-
    claim_hospitalization_month(C, HM),
    (   HM < 7
    ->  true
    ;   condition_1_3_satisfied(C)
    ).

condition_1_3_satisfied(C) :-
    claim_written_confirmation_month(C, ConfM),
    no_later_than(ConfM, 7),
    claim_wellness_visit_month(C, VisitM),
    no_later_than(VisitM, 6),
    claim_wellness_visit_provider_qualified(C, true).

% 1.2: cancelation is deemed to occur on fraud or misrepresentation. Only
% conduct at or before the hospitalization can have canceled the policy
% by the time of that hospitalization. (Judgement call: see NOTES.md.)
cancelling_conduct(C) :- fraud_by_hospitalization(C).
cancelling_conduct(C) :- misrepresentation_by_hospitalization(C).

fraud_by_hospitalization(C) :-
    claim_fraud_month(C, FraudM),
    claim_hospitalization_month(C, HM),
    no_later_than(FraudM, HM).

misrepresentation_by_hospitalization(C) :-
    claim_misrepresentation_month(C, MisrepM),
    claim_hospitalization_month(C, HM),
    no_later_than(MisrepM, HM).

% 1.2 / 3.6: the policy is automatically canceled at the end of its term.
within_term(C) :-
    claim_hospitalization_month(C, HM),
    claim_policy_term_months(C, TermM),
    no_later_than(HM, TermM).

% ---------------------------------------------------------------------
% 2.1: general exclusions.
% ---------------------------------------------------------------------

excluded(C) :-
    claim_causes(C, Causes),
    excluded_cause(Cause),
    arose_out_of(Causes, Cause).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

excluded_cause(skydiving).
excluded_cause(military_service).
excluded_cause(firefighting).
excluded_cause(police_service).

% ---------------------------------------------------------------------
% 3.2: arbitration.
% ---------------------------------------------------------------------

% If a dispute has arisen, arbitration must have been commenced within
% three months of the parties becoming unable to settle, and a valid
% arbitration award must have been issued, or the cause of action is
% extinguished and our liability is not established.
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    !,
    arbitration_commenced_on_time(C),
    claim_valid_arbitration_award_issued(C, true).
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).

arbitration_commenced_on_time(C) :-
    claim_unable_to_settle_month(C, UnableM),
    (   UnableM == none
    ->  true                              % the 3-month clock has not started yet
    ;   Limit is UnableM + 3,
        claim_arbitration_commenced_month(C, ArbM),
        no_later_than(ArbM, Limit)
    ).

% 3.2.1: in no case may recovery be sought before the expiration of sixty
% (60) days after written proof of claim has been submitted. The schema
% only offers month-granularity facts, so 60 days is approximated here as
% 2 months. (Judgement call: see NOTES.md.)
waiting_period_ok(C) :-
    claim_recovery_sought_month(C, RecoverM),
    (   RecoverM == none
    ->  true
    ;   claim_written_proof_of_claim_month(C, ProofM),
        number(ProofM),
        RecoverM >= ProofM + 2
    ).
