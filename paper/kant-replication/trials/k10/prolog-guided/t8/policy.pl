% policy.pl
%
% covered(C) succeeds exactly when a benefit is payable on claim C, under the Codex
% Insurance Limited policy (inputs/chubb-policy.txt). This file defines covered/1 and its
% helper predicates only. It defines NO claim_* facts -- those are supplied per-claim by
% queries.pl (or any other caller) -- and no claim identifier is hard-coded here.
%
% The two supporting predicates below are reproduced VERBATIM from inputs/schema.md so
% this file is self-contained.

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------------
% covered(C) -- top-level rule
% ---------------------------------------------------------------------------------
%
% A benefit is payable on claim C iff:
%   (a) the policy was in effect at the time of the hospitalization [S1.1, S1.2, S1.3],
%   (b) the hospitalization is premised on sickness or accidental injury [S1.1],
%   (c) none of the general exclusions apply [S2.1],
%   (d) if a dispute has arisen, the arbitration condition precedent is met [S3.2.1], and
%   (e) recovery is not being sought prematurely [S3.2.1, last sentence].

covered(C) :-
    policy_in_effect(C),
    valid_claim_ground(C),
    \+ generally_excluded(C),
    arbitration_condition_met(C),
    proof_of_claim_wait_met(C).

% --- S1.1 / S1.2 / S1.3 / S3.6: was the policy in effect at the time of hospitalization? ---

policy_in_effect(C) :-
    claim_agreement_signed(C, true),                       % S1.1(1)
    claim_hospitalization_month(C, HospMonth),
    claim_premium_paid_month(C, PremiumMonth),
    no_later_than(PremiumMonth, HospMonth),                % S1.1(2): premium paid by then
    condition_1_3_ok(C, HospMonth),                        % S1.1(3) / S1.3
    not_cancelled_for_dishonesty(C),                       % S1.2: fraud/misrepresentation
    within_policy_term(C, HospMonth).                      % S1.2 last sentence / S3.6

% S1.3 itself carries a single operative deadline: no later than the 7th-month
% anniversary, you supply written confirmation of a wellness visit (with a qualified
% medical provider) that itself occurred no later than the 6th-month anniversary.
% Per S1.1(3) the policy stays in effect while that condition is "still pending" (its own
% deadline has not yet arrived as of the hospitalization) OR once it has actually "been
% satisfied in a timely fashion". Once the 7-month deadline has passed, only actual,
% timely satisfaction of both parts keeps the policy in effect.
condition_1_3_ok(C, HospMonth) :-
    (   HospMonth < 7
    ->  true
    ;   claim_written_confirmation_month(C, ConfMonth),
        no_later_than(ConfMonth, 7),
        claim_wellness_visit_month(C, VisitMonth),
        no_later_than(VisitMonth, 6),
        claim_wellness_visit_provider_qualified(C, true)
    ).

% S1.2: cancellation on fraud, misrepresentation, or material withholding of information,
% at any point in connection with the policy (not conditioned on timing relative to the
% hospitalization -- the clause carries no such qualifier, unlike S1.3).
not_cancelled_for_dishonesty(C) :-
    claim_fraud_month(C, none),
    claim_misrepresentation_month(C, none).

% S1.2 last sentence / S3.6: the policy is automatically canceled at the end of its term,
% so the hospitalization must fall on or before the last day of the term.
within_policy_term(C, HospMonth) :-
    claim_policy_term_months(C, TermMonths),
    no_later_than(HospMonth, TermMonths).

% --- S1.1: the claim must be premised on hospitalization for sickness or accidental injury ---

valid_claim_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ).

% --- S2.1: general exclusions ---

generally_excluded(C) :-
    claim_causes(C, Causes),
    (   arose_out_of(Causes, skydiving)
    ;   arose_out_of(Causes, military_service)
    ;   arose_out_of(Causes, firefighting)
    ;   arose_out_of(Causes, police_service)
    ).
generally_excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% --- S3.2.1: once a dispute has arisen, arbitration is a condition precedent ---

arbitration_condition_met(C) :-
    claim_dispute_arisen(C, Disputed),
    (   Disputed == false
    ->  true
    ;   claim_unable_to_settle_month(C, UnableMonth),
        claim_arbitration_commenced_month(C, ArbMonth),
        number(UnableMonth),
        number(ArbMonth),
        ArbMonth =< UnableMonth + 3,
        claim_valid_arbitration_award_issued(C, true)
    ).

% --- S3.2.1, last sentence: no recovery within 60 days (taken as 2 months) of written
%     proof of claim being submitted. This is not scoped to "where there is a dispute" in
%     the text, so it is checked unconditionally, not just when a dispute has arisen. ---

proof_of_claim_wait_met(C) :-
    claim_written_proof_of_claim_month(C, ProofMonth),
    claim_recovery_sought_month(C, RecoveryMonth),
    (   (ProofMonth == none ; RecoveryMonth == none)
    ->  true
    ;   RecoveryMonth >= ProofMonth + 2
    ).
