% ============================================================
% CODEX INSURANCE LIMITED -- policy encoding (policy.pl)
% ============================================================
% Rules only. No claim-specific facts are asserted in this file;
% per-claim facts belong in queries.pl and are always keyed by a
% claim identifier (the first argument of every dynamic predicate
% below), so that several claims can be loaded into the same
% knowledge base at once without interfering with one another.
%
% Scoping assumptions taken directly from the task brief:
%   - the agreement is always taken to be signed, and the premium
%     is always taken to have been paid on time (Sec. 1.1 items
%     1-2 of the "policy in effect" test) -- not modelled, per
%     instructions.
%   - every date/time other than the claimant's age is supplied
%     as a number of months relative to the policy's effective
%     date, so no arithmetic between two absolute calendar dates
%     is ever required.
%   - a fact that is simply never asserted for a given claim is
%     treated, by construction of the rules below, the way the
%     task's "assume all other/unrelated conditions are met and
%     no other/unrelated exclusions apply" instruction requires:
%     conditions default to satisfied and exclusions default to
%     not-triggered when nothing says otherwise.
% ============================================================

% ---- dynamic per-claim fact predicates -------------------------
% Declaring these dynamic means an unasserted fact simply fails
% (rather than raising an existence error), which is both correct
% Prolog practice for facts supplied from another file and exactly
% the "unrelated conditions default to satisfied" behaviour above.

:- dynamic hospitalization_time_months/2.       % (Claim, MonthsAfterEffectiveDate)
:- dynamic age_at_hospitalization/2.            % (Claim, AgeInYears) -- absolute age, not relative to effective date
:- dynamic injury_arises_from/2.                % (Claim, Cause) with Cause one of:
                                                 %   skydiving, military_service,
                                                 %   firefighter_service, police_service
:- dynamic wellness_visit_time_months/2.        % (Claim, MonthsAfterEffectiveDate) -- when the Sec 1.3 wellness visit itself took place
:- dynamic wellness_confirmation_time_months/2. % (Claim, MonthsAfterEffectiveDate) -- when written confirmation of that visit was supplied to Us
:- dynamic fraud_committed/1.                   % (Claim)
:- dynamic misrepresentation_made/1.            % (Claim)
:- dynamic information_materially_withheld/1.   % (Claim)
:- dynamic dispute_exists/1.                    % (Claim) -- Sec 3.2: a dispute/disagreement concerning the policy has arisen
:- dynamic arbitration_commenced_in_time/1.     % (Claim) -- Sec 3.2: arbitration begun within 3 months of failing to settle the dispute
:- dynamic valid_arbitration_award_issued/1.    % (Claim) -- Sec 3.2
:- dynamic seeking_recovery_before_60_days/1.   % (Claim) -- Sec 3.2: trying to recover under the policy before 60 days after proof of claim

% ---- Sec 1: "Policy in effect and conditions" -------------------

% Sec 1.2: cancellation triggered by the insured's own conduct.
conduct_voids_policy(Claim) :- fraud_committed(Claim).
conduct_voids_policy(Claim) :- misrepresentation_made(Claim).
conduct_voids_policy(Claim) :- information_materially_withheld(Claim).

% Sec 1.3, read together with Sec 1.1 item 3 and Sec 1.2:
% "still pending" -- no compliance action has been reported for
%   this claim yet, but the 7-month deadline to report one has not
%   passed as of the hospitalization, so nothing has gone wrong
%   yet;
% "satisfied in a timely fashion" -- confirmation was supplied no
%   later than the 7th month anniversary of the effective date,
%   AND it attests to a wellness visit that itself occurred no
%   later than the 6th month anniversary;
% anything else -- the condition has not been satisfied in a
%   timely fashion, which Sec 1.2 makes a cancellation trigger.
wellness_condition_met(Claim) :-
    (   wellness_confirmation_time_months(Claim, ConfirmMonths)
    ->  ConfirmMonths =< 7,
        (   wellness_visit_time_months(Claim, VisitMonths)
        ->  VisitMonths =< 6
        ;   % No separately-reported visit date: the confirmation
            % date is the only evidence we have of when the visit
            % happened, so it is also judged against the 6-month
            % visit deadline. See NOTES.md.
            ConfirmMonths =< 6
        )
    ;   hospitalization_time_months(Claim, HospMonths)
    ->  HospMonths =< 7
    ;   true
    ).

% Sec 3.6: the policy term runs for one year from the effective
% date, and Sec 1.2 automatically cancels the policy at the end of
% that term.
within_policy_term(Claim) :-
    (   hospitalization_time_months(Claim, HospMonths)
    ->  HospMonths =< 12
    ;   true
    ).

% Sec 3.2: arbitration is a condition precedent to Our liability
% only once a dispute actually exists; absent a dispute, none of
% this bites. The 60-day post-proof-of-claim wait applies always.
arbitration_precondition_met(Claim) :-
    (   dispute_exists(Claim)
    ->  arbitration_commenced_in_time(Claim),
        valid_arbitration_award_issued(Claim)
    ;   true
    ),
    \+ seeking_recovery_before_60_days(Claim).

% Sec 1.1: the policy is "in effect" at the time of hospitalization.
policy_in_effect(Claim) :-
    \+ conduct_voids_policy(Claim),
    wellness_condition_met(Claim),
    within_policy_term(Claim).

% ---- Sec 2: "General exclusions" --------------------------------
% Each ground excludes a claim only when the sickness/injury being
% claimed for itself arises (directly or indirectly) out of the
% listed activity -- merely holding the listed occupation/status at
% the time of hospitalization, without the injury arising out of
% it, does not trigger these. See NOTES.md re: Q9-style claims.

excluded(Claim) :- injury_arises_from(Claim, skydiving).
excluded(Claim) :- injury_arises_from(Claim, military_service).
excluded(Claim) :- injury_arises_from(Claim, firefighter_service).
excluded(Claim) :- injury_arises_from(Claim, police_service).
excluded(Claim) :- age_at_hospitalization(Claim, Age), Age >= 80.

% ---- Sec 3.1, 3.3, 3.4, 3.5: reviewed, no coverage rule needed --
% 3.1 confirms worldwide, 24/7 coverage, i.e. there is no
%     territorial exclusion to encode.
% 3.3 (governing law), 3.4 (currency of payment) and 3.5 (premium
%     paid as a lump sum at signing) are administrative terms that
%     do not bear on whether a given claim is covered.

% ---- top-level ---------------------------------------------------

% covered(Claim) succeeds iff the policy is in effect at the time
% of the hospitalization underlying Claim, none of the Sec 2
% exclusions are triggered, and the Sec 3.2 preconditions to Our
% liability (if any dispute exists) are met.
covered(Claim) :-
    policy_in_effect(Claim),
    \+ excluded(Claim),
    arbitration_precondition_met(Claim).
