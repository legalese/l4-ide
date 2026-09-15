% ============================================================================
% policy.pl
%
% Prolog encoding of the CODEX INSURANCE LIMITED policy (fixtures/chubb-policy.txt).
%
% This file contains RULES ONLY. No claim-specific facts are asserted here;
% every fact about a particular claim (its date relative to the effective
% date, the claimant's age, what caused the hospitalization, etc.) is
% supplied by queries.pl, keyed by a claim identifier such as claim_1.
%
% Per the task instructions:
%   - the agreement is assumed signed and the premium assumed paid on time
%     (Sec. 1.1 items 1-2), so no predicate models those two conditions;
%   - every date/time fact (other than the claimant's age) is expressed in
%     months elapsed since the policy's effective date, and is only ever
%     compared against a FIXED deadline drawn from the contract (6, 7 or 12
%     months) -- never against another date/time fact, so no elapsed-time
%     arithmetic between two dates is required anywhere below.
%
% All claim-level fact predicates are declared dynamic so that (a) a
% predicate that happens to have zero facts asserted for any claim (e.g.
% nobody in this benchmark ever commits fraud) fails cleanly instead of
% raising an "unknown procedure" error, and (b) queries.pl may add facts
% for these predicates, grouped by claim, without discontiguous-clause
% warnings.
% ============================================================================

:- dynamic hospitalization_cause/2.        % hospitalization_cause(Claim, sickness | accidental_injury | <other>)
:- dynamic hospitalization_time/2.         % hospitalization_time(Claim, MonthsSinceEffectiveDate)
:- dynamic age_at_hospitalization/2.       % age_at_hospitalization(Claim, Age)
:- dynamic activity/2.                     % activity(Claim, skydiving | military_service | firefighting | police_service)
:- dynamic wellness_visit_occurred/2.      % wellness_visit_occurred(Claim, MonthsSinceEffectiveDate)
:- dynamic wellness_confirmation_submitted/2. % wellness_confirmation_submitted(Claim, MonthsSinceEffectiveDate)
:- dynamic fraud_or_misrepresentation/1.   % fraud_or_misrepresentation(Claim)
:- dynamic dispute_exists/1.               % dispute_exists(Claim)
:- dynamic valid_arbitration_award/1.      % valid_arbitration_award(Claim)
:- dynamic arbitration_commenced_in_time/1. % arbitration_commenced_in_time(Claim)

% ----------------------------------------------------------------------------
% Top level: is a benefit payable under the policy for this claim?
% ----------------------------------------------------------------------------
% Sec. 1.1: "The payment of any benefit under this policy is conditioned on
% the policy being in effect at the time of the hospitalization for sickness
% or accidental injury on which the claim for such benefit is premised."
covered(Claim) :-
    policy_in_effect(Claim),
    qualifying_hospitalization(Claim),
    \+ excluded(Claim),
    arbitration_condition_satisfied(Claim).

% ----------------------------------------------------------------------------
% Section 1: Policy in effect and conditions
% ----------------------------------------------------------------------------
% Sec. 1.1: the policy is in effect if the agreement is signed (assumed),
% the premium is paid (assumed), the Sec. 1.3 condition is still pending or
% was satisfied in a timely fashion, and the policy has not been cancelled.
policy_in_effect(Claim) :-
    condition_1_3_ok(Claim),
    \+ cancelled(Claim).

% Sec. 1.2: cancellation occurs for cause (fraud/misrepresentation/material
% withholding), for failing to satisfy the Sec. 1.3 condition in time, or
% automatically at the end of the one-year policy term (Sec. 3.6).
cancelled(Claim) :-
    fraud_or_misrepresentation(Claim).
cancelled(Claim) :-
    \+ condition_1_3_ok(Claim).
cancelled(Claim) :-
    \+ within_policy_term(Claim).

% Sec. 1.3: no later than the 7-month anniversary of the effective date, the
% insured must supply written confirmation of a wellness visit that itself
% occurred no later than the 6-month anniversary. Both thresholds are fixed
% constants of the contract, so each is checked independently against the
% single relevant fact -- no comparison between two dates is needed.
section_1_3_satisfied_timely(Claim) :-
    wellness_visit_occurred(Claim, VisitMonths),
    VisitMonths =< 6,
    wellness_confirmation_submitted(Claim, ConfirmMonths),
    ConfirmMonths =< 7.

% If a claim's facts say nothing at all about the wellness-visit condition,
% that condition is unrelated to the query; per the benchmark's own
% instruction we then assume it is not an obstacle to coverage (whether
% because it is genuinely still pending, or otherwise not in issue).
condition_1_3_ok(Claim) :-
    \+ wellness_confirmation_submitted(Claim, _),
    \+ wellness_visit_occurred(Claim, _).
condition_1_3_ok(Claim) :-
    section_1_3_satisfied_timely(Claim).

% Sec. 3.6: the policy term is one year (12 months) from the effective date;
% Sec. 1.2 automatically cancels the policy once the term ends. If a claim's
% facts say nothing about when the hospitalization occurred, that timing is
% unrelated to the query and is assumed to fall within the term.
within_policy_term(Claim) :-
    \+ hospitalization_time(Claim, _).
within_policy_term(Claim) :-
    hospitalization_time(Claim, HospMonths),
    HospMonths =< 12.

% ----------------------------------------------------------------------------
% Qualifying hospitalization (Sec. 1.1)
% ----------------------------------------------------------------------------
% The benefit is only payable for a hospitalization "for sickness or
% accidental injury". A deliberate, self-inflicted act is neither a sickness
% nor an accident, so a claim premised on one does not reach this predicate
% (see NOTES.md).
qualifying_hospitalization(Claim) :-
    hospitalization_cause(Claim, sickness).
qualifying_hospitalization(Claim) :-
    hospitalization_cause(Claim, accidental_injury).

% ----------------------------------------------------------------------------
% Section 2.1: General Exclusions
% ----------------------------------------------------------------------------
% The policy does not apply to, and no benefit is paid for, any sickness or
% accidental injury arising directly or indirectly out of skydiving,
% military service, firefighting or police service, nor at all if the
% claimant's age at the time of hospitalization is 80 or older.
excluded(Claim) :-
    arises_out_of_excluded_activity(Claim).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.

arises_out_of_excluded_activity(Claim) :-
    activity(Claim, skydiving).
arises_out_of_excluded_activity(Claim) :-
    activity(Claim, military_service).
arises_out_of_excluded_activity(Claim) :-
    activity(Claim, firefighting).
arises_out_of_excluded_activity(Claim) :-
    activity(Claim, police_service).

% ----------------------------------------------------------------------------
% Section 3.1: Worldwide, 24-hour cover
% ----------------------------------------------------------------------------
% "Your Policy insures You twenty-four (24) hours a day anywhere in the
% world." There is no territorial or time-of-day exclusion, so no rule is
% written that could ever exclude a claim merely for occurring abroad or at
% a particular hour -- that silence is the correct translation of Sec. 3.1.

% ----------------------------------------------------------------------------
% Section 3.2: Arbitration as a condition precedent to liability
% ----------------------------------------------------------------------------
% Where a dispute or disagreement exists, a valid arbitration award (timely
% commenced) is a condition precedent to the Company's liability. If a
% claim's facts say nothing about a dispute, this is unrelated to the query
% and does not bar liability.
arbitration_condition_satisfied(Claim) :-
    \+ dispute_exists(Claim).
arbitration_condition_satisfied(Claim) :-
    dispute_exists(Claim),
    valid_arbitration_award(Claim),
    arbitration_commenced_in_time(Claim).

% ----------------------------------------------------------------------------
% Sections 3.3-3.5 (governing law, currency of payment, timing of the lump-
% sum premium payment) are administrative/procedural terms that do not bear
% on whether a given hospitalization is a covered event, so no predicate is
% derived from them. See NOTES.md.
% ----------------------------------------------------------------------------
