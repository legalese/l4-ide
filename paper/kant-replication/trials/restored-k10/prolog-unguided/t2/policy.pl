% policy.pl
%
% Prolog encoding of the CODEX INSURANCE LIMITED hospital-indemnity policy
% (see inputs/chubb-policy.txt for the source text). Rules only: no
% claim-specific facts are asserted here. Per-claim facts belong in
% queries.pl, which is consulted after this file.
%
% Modeling assumptions carried over from the task brief:
%   - the agreement is signed and the premium has been paid, on time
%     (Section 1.1 items 1-2 are assumed true and are not encoded);
%   - every date/time fact (other than the claimant's age) is expressed as a
%     number of months elapsed since the policy's effective date, so no rule
%     here ever computes an interval between two dates - it only ever
%     compares a given relative-month figure against a fixed contractual
%     deadline (6, 7, or 12 months).

% ---------------------------------------------------------------------------
% Fact predicates supplied per-claim by queries.pl. Declared dynamic here
% because policy.pl itself contributes no clauses for them - only
% queries.pl does, from a separate file consulted afterwards, and without
% this declaration that second consult would raise a permission error
% against redefining a (would-be) static procedure.
% ---------------------------------------------------------------------------

:- dynamic hospitalization_cause/2.
% Claim, one of: sickness | accidental_injury | intentional_self_inflicted_act

:- dynamic injury_activity/2.
% Claim, one of: skydiving | military_service | firefighter_service
%              | police_service | none

:- dynamic age_at_hospitalization/2.
% Claim, Age in years (absolute - the one fact the task brief exempts from
% "relative to the effective date")

:- dynamic hospitalization_location/2.
% Claim, one of: us | abroad

:- dynamic hospitalization_month/2.
% Claim, Month (number of months after the effective date the
% hospitalization occurred)

:- dynamic wellness_visit_month/2.
% Claim, Month (number of months after the effective date the Section 1.3
% wellness visit itself occurred)

:- dynamic wellness_confirmation_month/2.
% Claim, Month (number of months after the effective date written
% confirmation of that visit was supplied to the Company)

:- dynamic fraud_or_misrepresentation/2.
% Claim, one of: true | false - stands in for all three grounds named in
% Section 1.2: fraud, misrepresentation, or material withholding of
% information

% queries.pl groups each claim's facts together (one claim per benchmark
% question) rather than grouping clauses by predicate, so every fact
% predicate above is declared discontiguous as well as dynamic, to keep the
% load silent.
:- discontiguous hospitalization_cause/2.
:- discontiguous injury_activity/2.
:- discontiguous age_at_hospitalization/2.
:- discontiguous hospitalization_location/2.
:- discontiguous hospitalization_month/2.
:- discontiguous wellness_visit_month/2.
:- discontiguous wellness_confirmation_month/2.
:- discontiguous fraud_or_misrepresentation/2.

% ---------------------------------------------------------------------------
% Top level
% ---------------------------------------------------------------------------

% covered(Claim) succeeds iff the policy applies to Claim: the policy is in
% effect, the hospitalization is a qualifying event, the daily benefit is
% payable for it, and no general exclusion applies.
covered(Claim) :-
    policy_in_effect(Claim),
    qualifying_event(Claim),
    benefit_payable(Claim),
    \+ excluded(Claim).

% ---------------------------------------------------------------------------
% Section 1: Policy in effect and conditions
% ---------------------------------------------------------------------------

% 1.1: the policy is in effect as long as it has not been canceled. (Items 1
% and 2 of 1.1 - the agreement being signed and the premium having been
% paid - are assumed true throughout per the task brief, so they are not
% encoded as conditions here.)
policy_in_effect(Claim) :-
    \+ cancelled(Claim).

% 1.2: cancellation occurs on fraud/misrepresentation/material withholding,
% on Section 1.3's wellness-visit condition not being satisfied in a timely
% fashion, or on the policy term (Section 4.6) having lapsed by the time of
% the hospitalization.
cancelled(Claim) :-
    fraud_or_misrepresentation(Claim, true).
cancelled(Claim) :-
    \+ condition_1_3_ok(Claim).
cancelled(Claim) :-
    \+ within_policy_term(Claim).

% 1.3: no later than the 7-month anniversary of the effective date, written
% confirmation must be supplied of a wellness visit that itself occurred no
% later than the 6-month anniversary of the effective date. The two halves
% of the condition carry different deadlines and are both checked.
condition_1_3_ok(Claim) :-
    wellness_visit_month(Claim, VisitMonth),
    VisitMonth =< 6,
    wellness_confirmation_month(Claim, ConfirmMonth),
    ConfirmMonth =< 7.

% 4.6, read with 1.2's last sentence: the policy term is one year from the
% effective date, after which the policy lapses automatically.
within_policy_term(Claim) :-
    hospitalization_month(Claim, Month),
    Month =< 12.

% ---------------------------------------------------------------------------
% Section 2: Benefits
% ---------------------------------------------------------------------------

% 2.1: a qualifying event is hospitalization resulting from sickness or
% accidental injury. A deliberate, intentional act is neither "sickness"
% nor an "accidental" injury, so it does not qualify on these terms alone -
% independently of Section 3's exclusions, none of which mention
% self-inflicted injury at all.
qualifying_event(Claim) :-
    hospitalization_cause(Claim, sickness).
qualifying_event(Claim) :-
    hospitalization_cause(Claim, accidental_injury).

% 2.2: the Daily Hospital Income Benefit is payable only for confinement in
% a hospital in the United States. (This sits in tension with 4.1.1's
% worldwide-coverage language - see NOTES.md for the judgment call.)
benefit_payable(Claim) :-
    hospitalization_location(Claim, us).

% ---------------------------------------------------------------------------
% Section 3: General exclusions
% ---------------------------------------------------------------------------

% 3.1: the policy does not apply to sickness or injury arising directly or
% indirectly out of any of the following activities, or where the claimant
% is 80 years of age or older at the time of hospitalization.
excluded(Claim) :-
    injury_activity(Claim, skydiving).
excluded(Claim) :-
    injury_activity(Claim, military_service).
excluded(Claim) :-
    injury_activity(Claim, firefighter_service).
excluded(Claim) :-
    injury_activity(Claim, police_service).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
