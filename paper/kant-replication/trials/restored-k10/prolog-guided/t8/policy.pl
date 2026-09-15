% policy.pl
%
% covered(C): true exactly when a benefit is payable on claim C, under the
% Codex Insurance Limited hospital indemnity policy (inputs/chubb-policy.txt).
%
% Uses ONLY the claim_* facts and supporting predicates listed in
% inputs/schema.md. This file defines no claim facts; those are supplied by
% the caller (see queries.pl).

% ---------------------------------------------------------------------------
% Supporting predicates -- copied verbatim from inputs/schema.md.
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top-level rule.
% ---------------------------------------------------------------------------

%! covered(+C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    policy_in_effect(C),           % S1: policy must be in effect at time of hospitalization
    benefit_triggered(C),          % S2.1/2.2: qualifying hospitalization, in a US hospital
    \+ excluded(C),                % S3.1: general exclusions
    claim_made_properly(C),        % S2.3: claim made to the Company setting out the basis
    arbitration_ok(C),             % S4.2.1: dispute / arbitration condition precedent
    recovery_timing_ok(C).         % S4.2.1: 60-day post-proof-of-claim waiting period

% ---------------------------------------------------------------------------
% S1 Policy in effect and conditions.
% ---------------------------------------------------------------------------

%! policy_in_effect(+C) is semidet.
policy_in_effect(C) :-
    claim_agreement_signed(C, true),                  % S1.1(1)
    claim_premium_paid_month(C, PaidMonth),
    number(PaidMonth),                                % S1.1(2): the premium has been paid
    claim_hospitalization_month(C, HospMonth),
    section_1_3_ok(C, HospMonth),                     % S1.1(3) / S1.3
    \+ cancelled_for_fraud_or_misrepresentation(C),   % S1.2
    claim_policy_term_months(C, TermMonths),
    no_later_than(HospMonth, TermMonths).             % S1.2 / S4.6: within the policy term

%! section_1_3_ok(+C, +HospMonth) is semidet.
%  The S1.3 wellness-visit / written-confirmation condition is either "still
%  pending" (the 7-month deadline has not yet arrived, as of the
%  hospitalization) or "has been satisfied in a timely fashion" (S1.1(3)).
section_1_3_ok(_C, HospMonth) :-
    HospMonth =< 7, !.                                % still pending: deadline not yet due
section_1_3_ok(C, _HospMonth) :-
    claim_written_confirmation_month(C, ConfMonth),
    no_later_than(ConfMonth, 7),                      % confirmation supplied by month 7
    claim_wellness_visit_month(C, VisitMonth),
    no_later_than(VisitMonth, 6),                     % the visit itself occurred by month 6
    claim_wellness_visit_provider_qualified(C, true). % ... with a qualified medical provider

%! cancelled_for_fraud_or_misrepresentation(+C) is semidet.
%  S1.2: cancelation is deemed to occur if there is fraud, or any
%  misrepresentation or material withholding of information, at any point in
%  connection with the policy -- the clause carries no timing qualifier.
cancelled_for_fraud_or_misrepresentation(C) :-
    claim_fraud_month(C, FraudMonth), number(FraudMonth).
cancelled_for_fraud_or_misrepresentation(C) :-
    claim_misrepresentation_month(C, MisrepMonth), number(MisrepMonth).

% ---------------------------------------------------------------------------
% S2 Benefits.
% ---------------------------------------------------------------------------

%! benefit_triggered(+C) is semidet.
benefit_triggered(C) :-
    claim_hospitalization_ground(C, Ground),
    memberchk(Ground, [sickness, accidental_injury]),  % S2.1
    claim_confined_in_us_hospital(C, true),             % S2.2: hospital in the United States
    claim_continuous_confinement_days(C, Days),
    number(Days), Days =< 365.                          % S2.2: 365-day cap

%! claim_made_properly(+C) is semidet.
claim_made_properly(C) :-
    claim_claim_made_setting_out_basis(C, true).        % S2.3

% ---------------------------------------------------------------------------
% S3 General exclusions.
% ---------------------------------------------------------------------------

%! excluded(+C) is semidet.
excluded(C) :-
    claim_causes(C, Causes),
    member(Cause, [skydiving, military_service, firefighting, police_service]),
    arose_out_of(Causes, Cause), !.                     % S3.1(1)-(4)
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.                                          % S3.1(5)

% ---------------------------------------------------------------------------
% S4.2 Arbitration.
% ---------------------------------------------------------------------------

%! arbitration_ok(+C) is semidet.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false), !.
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, UnableMonth),
    (   UnableMonth == none
    ->  true                                  % dispute exists but no impasse yet: still pending
    ;   number(UnableMonth),
        Deadline is UnableMonth + 3,
        claim_arbitration_commenced_month(C, CommencedMonth),
        no_later_than(CommencedMonth, Deadline),        % commenced within 3 months
        claim_valid_arbitration_award_issued(C, true)   % award is a condition precedent
    ).

%! recovery_timing_ok(+C) is semidet.
%  S4.2.1's 60-day post-proof-of-claim waiting period. The schema gives this
%  in whole months rather than days; 60 days is approximated as 2 months
%  (see NOTES.md).
recovery_timing_ok(C) :-
    claim_written_proof_of_claim_month(C, ProofMonth),
    number(ProofMonth),
    claim_recovery_sought_month(C, SoughtMonth),
    number(SoughtMonth),
    Deadline is ProofMonth + 2,
    SoughtMonth >= Deadline.
