% ============================================================
% policy.pl
%
% Encoding of the CODEX INSURANCE LIMITED daily hospital income
% policy into Prolog rules.
%
% This file defines RULES ONLY -- no claim-specific facts live
% here. Every fact about a particular claim (the claimant's age,
% the timing of hospitalization, the timing of the Section 1.3
% wellness-visit confirmation, the cause of the sickness or
% injury, whether fraud occurred, etc.) is asserted in
% queries.pl, one set of facts per question.
%
% Per the task brief:
%   - All timing facts are expressed as a number of months
%     elapsed since the policy's effective date, never as an
%     absolute date. The one exception is the claimant's age,
%     which is an absolute fact about the claimant, not a date
%     relative to the effective date.
%   - The agreement is always taken to be signed and the premium
%     always taken to be paid on time, so Section 1.1's
%     conditions (1) and (2) are not modelled as variable facts;
%     they are simply assumed true throughout.
% ============================================================

% ------------------------------------------------------------
% Declarations.
%
% Every predicate below represents a fact that queries.pl may or
% may not supply for a given claim, depending on whether that
% fact is mentioned in the question being encoded. Declaring
% them dynamic means that a claim for which the fact is not
% supplied simply fails that lookup (as intended -- the fact
% "isn't true of that claim" as far as this encoding knows)
% instead of raising a "procedure does not exist" error.
% ------------------------------------------------------------

:- dynamic(hospitalized/1).
:- dynamic(age_at_hospitalization/2).
:- dynamic(hospitalization_month/2).
:- dynamic(wellness_confirmation_month/2).
:- dynamic(fraud_or_misrepresentation/1).
:- dynamic(caused_by_skydiving/1).
:- dynamic(caused_by_military_service/1).
:- dynamic(caused_by_firefighting_service/1).
:- dynamic(caused_by_police_service/1).

% ------------------------------------------------------------
% Input facts expected from queries.pl (documented here, defined
% there):
%
%   hospitalized(Claim).
%       The claimant was confined in a hospital as a result of
%       sickness or accidental injury (Section 2.1). Required for
%       every claim.
%
%   age_at_hospitalization(Claim, Age).
%       The claimant's age, in years, at the time of the
%       hospitalization. This is an absolute fact about the
%       claimant, not a date relative to the effective date.
%       Omit if the question does not turn on age.
%
%   hospitalization_month(Claim, Months).
%       How many months after the policy's effective date the
%       hospitalization occurred. Omit if the question does not
%       state it.
%
%   wellness_confirmation_month(Claim, Months).
%       How many months after the policy's effective date the
%       claimant supplied the Company with written confirmation,
%       from the medical provider, of a wellness visit (Section
%       1.3). Omit if the question does not say a confirmation
%       was ever supplied.
%
%   fraud_or_misrepresentation(Claim).
%       The claimant committed fraud, misrepresentation, or
%       material withholding of information in connection with
%       the policy (Section 1.2). Omit unless the question says
%       this happened.
%
%   caused_by_skydiving(Claim).
%   caused_by_military_service(Claim).
%   caused_by_firefighting_service(Claim).
%   caused_by_police_service(Claim).
%       The sickness or accidental injury arose directly or
%       indirectly out of the named activity (Section 3.1). Omit
%       unless the question establishes that causal link -- merely
%       holding the status (e.g. being employed as a police
%       officer) at the time of hospitalization, with no causal
%       connection between that service and the injury, does NOT
%       warrant asserting the corresponding fact.
% ------------------------------------------------------------

% ------------------------------------------------------------
% Top level: does the policy apply to (i.e. cover) this claim?
% ------------------------------------------------------------

covered(Claim) :-
    hospitalized(Claim),
    policy_in_effect(Claim),
    \+ excluded(Claim).

% ------------------------------------------------------------
% Section 1 -- POLICY IN EFFECT AND CONDITIONS
% ------------------------------------------------------------

% 1.1: the policy is in effect at the time of the hospitalization
% as long as it has not been canceled. Conditions (1) (signed)
% and (2) (premium paid) are stipulated to always hold; condition
% (3) (Section 1.3's wellness-visit condition, "still pending or
% ... satisfied in a timely fashion") is folded into canceled/1
% below, via the matching cancellation trigger in Section 1.2;
% condition (4) is exactly "not canceled".
policy_in_effect(Claim) :-
    \+ canceled(Claim).

% 1.2: what causes the policy to be canceled.
canceled(Claim) :-
    fraud_or_misrepresentation(Claim).
canceled(Claim) :-
    \+ condition_1_3_ok(Claim).
canceled(Claim) :-
    policy_term_expired(Claim).

% 1.3: no later than the 7th month anniversary of the effective
% date, the claimant must supply written confirmation of a
% wellness visit that itself occurred no later than the 6th month
% anniversary. Read together with 1.1(3), this condition does not
% cause cancellation so long as it is either "still pending" (its
% month-7 deadline has not yet arrived) or has already been
% satisfied on time.
%
%   - If we know exactly when confirmation was supplied, that is
%     decisive: on time iff supplied by month 7.
%   - Otherwise, if we at least know when the hospitalization
%     occurred, the condition is still "pending" (hence fine) as
%     long as the month-7 deadline had not yet passed as of that
%     hospitalization.
%   - If neither timing fact is known, the question does not turn
%     on Section 1.3 at all, and it defaults to fine.
condition_1_3_ok(Claim) :-
    (   wellness_confirmation_month(Claim, M)
    ->  M =< 7
    ;   hospitalization_month(Claim, H)
    ->  H =< 7
    ;   true
    ).

% 1.2 (second sentence) / 4.6: the policy term is one year from
% the effective date; the policy is automatically canceled once
% that term has elapsed.
policy_term_expired(Claim) :-
    hospitalization_month(Claim, H),
    H > 12.

% ------------------------------------------------------------
% Section 3 -- GENERAL EXCLUSIONS
%
% The policy does not apply to, and no benefit is paid for, any
% sickness or accidental injury arising directly or indirectly
% out of skydiving, military service, firefighting service, or
% police service, nor if the claimant's age at the time of the
% hospitalization is 80 years or older.
% ------------------------------------------------------------

excluded(Claim) :-
    caused_by_skydiving(Claim).
excluded(Claim) :-
    caused_by_military_service(Claim).
excluded(Claim) :-
    caused_by_firefighting_service(Claim).
excluded(Claim) :-
    caused_by_police_service(Claim).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.

% ------------------------------------------------------------
% Section 4.1: territorial scope is deliberately unrestricted --
% the policy insures the claimant twenty-four hours a day,
% anywhere in the world -- so, correctly, no rule above restricts
% covered/1 by location.
% ------------------------------------------------------------
