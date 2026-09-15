% policy.pl
%
% covered(C) succeeds exactly when a benefit is payable on claim C, per the
% CODEX INSURANCE LIMITED policy terms and conditions (fixtures/chubb-policy.txt).
%
% Self-contained: includes the two supporting predicates from the schema
% verbatim. Defines no claim_*/2 facts -- those are supplied by the caller
% (see queries.pl).

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top level
% ---------------------------------------------------------------------------

covered(C) :-
    policy_in_effect(C),
    hospitalization_ground_ok(C),
    \+ excluded(C),
    arbitration_ok(C),
    waiting_period_ok(C).

% ---------------------------------------------------------------------------
% Section 1.1 / 1.2 / 1.3 -- policy in effect
% ---------------------------------------------------------------------------

% 1.1: the policy is in effect (at the time of the hospitalization) if the
% agreement is signed, the applicable premium has been paid, the Section 1.3
% condition is still pending or has been satisfied in a timely fashion, and
% the policy has not been canceled.
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    premium_paid_timely(C),
    not_canceled(C).

% "Paid" is read as paid by the time of the hospitalization it must cover.
premium_paid_timely(C) :-
    claim_premium_paid_month(C, PM),
    number(PM),
    claim_hospitalization_month(C, H),
    PM =< H.

% 1.2: cancelation is deemed to occur on fraud, on misrepresentation/material
% withholding, on failure to timely-satisfy Section 1.3, or on the natural
% expiration of the one-year policy term (Section 3.6). Fraud and
% misrepresentation void the policy whenever they occur, without regard to
% whether the act preceded or followed the hospitalization in question.
not_canceled(C) :-
    \+ fraud_occurred(C),
    \+ misrepresentation_occurred(C),
    section_1_3_ok(C),
    term_active(C).

fraud_occurred(C) :-
    claim_fraud_month(C, M),
    number(M).

misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, M),
    number(M).

% 1.3: no later than the 7th month anniversary, written confirmation of a
% wellness visit -- with a qualified medical provider, occurring no later
% than the 6th month anniversary -- must be supplied. These are two distinct
% deadlines (visit by month 6; confirmation of it by month 7).
%
% Per 1.1(3), the condition is "ok" if it has genuinely been satisfied in
% time, OR if it is merely still pending: the hospitalization falls before
% month 7, so the deadline has not yet come and gone, and non-satisfaction
% cannot yet be held against the claim.
section_1_3_ok(C) :-
    section_1_3_satisfied(C), !.
section_1_3_ok(C) :-
    section_1_3_pending(C).

section_1_3_satisfied(C) :-
    claim_wellness_visit_month(C, V),
    no_later_than(V, 6),
    claim_wellness_visit_provider_qualified(C, true),
    claim_written_confirmation_month(C, W),
    no_later_than(W, 7).

section_1_3_pending(C) :-
    claim_hospitalization_month(C, H),
    H < 7.

% 3.6 / 1.2: the policy runs for claim_policy_term_months and is then
% automatically canceled; a hospitalization at or before the last day of the
% term (inclusive) falls within an in-effect policy.
term_active(C) :-
    claim_hospitalization_month(C, H),
    claim_policy_term_months(C, T),
    H =< T.

% ---------------------------------------------------------------------------
% Section 1.1 -- the claim must be premised on sickness or accidental injury
% ---------------------------------------------------------------------------

hospitalization_ground_ok(C) :- claim_hospitalization_ground(C, sickness).
hospitalization_ground_ok(C) :- claim_hospitalization_ground(C, accidental_injury).

% ---------------------------------------------------------------------------
% Section 2.1 -- general exclusions
% ---------------------------------------------------------------------------

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
    Age >= 80.

% ---------------------------------------------------------------------------
% Section 3.2.1 -- arbitration
% ---------------------------------------------------------------------------

% No dispute: arbitration is simply not in play. A dispute: the claimant's
% right survives only if arbitration was (or, pending an impasse, still
% could be) commenced within three months of the parties becoming unable to
% settle, AND a valid arbitration award has issued -- a condition precedent
% to our liability whenever a dispute exists.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false), !.
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    arbitration_not_extinguished(C),
    claim_valid_arbitration_award_issued(C, true).

arbitration_not_extinguished(C) :-
    claim_unable_to_settle_month(C, none), !.
arbitration_not_extinguished(C) :-
    claim_unable_to_settle_month(C, U),
    number(U),
    claim_arbitration_commenced_month(C, A),
    number(A),
    A =< U + 3.

% ---------------------------------------------------------------------------
% Section 3.2.1 -- sixty-day post-proof-of-claim waiting period
% ---------------------------------------------------------------------------

% Sixty days is read as two months, matching the month-granularity of the
% rest of the fact schema. If recovery has not yet been sought, this
% condition precedent is not yet in play.
waiting_period_ok(C) :-
    claim_recovery_sought_month(C, none), !.
waiting_period_ok(C) :-
    claim_recovery_sought_month(C, R),
    number(R),
    claim_written_proof_of_claim_month(C, P),
    number(P),
    R >= P + 2.
