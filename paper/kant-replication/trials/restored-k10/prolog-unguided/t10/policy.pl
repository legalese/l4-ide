% ===========================================================================
% policy.pl -- Prolog encoding of the CODEX INSURANCE LIMITED hospital
% indemnity policy (inputs/chubb-policy.txt).
%
% This file contains ONLY general rules describing how the policy operates.
% It defines no facts about any particular claim -- those belong in
% queries.pl, which is consulted after this file and supplies, per claim,
% the facts needed to drive the rules below.
%
% Every fact predicate the rules below depend on is declared `dynamic`, so
% that a claim which simply has no fact for a given predicate causes that
% predicate to fail (closed-world "not proven") rather than raise an
% existence_error. That is deliberate: per the task instructions, any
% condition or exclusion not mentioned by a given query is to be treated
% as satisfied / not triggered, and negation-as-failure over an empty set
% of clauses is exactly that default.
%
% Each is also declared `discontiguous`, because queries.pl groups facts
% by claim (all of claim_1's facts together, then claim_2's, and so on)
% rather than by predicate, so clauses of the same predicate are not
% contiguous in that file.
% ===========================================================================

:- dynamic confined_in_hospital/1.
:- dynamic hospital_in_us/1.
:- dynamic caused_by_sickness/1.
:- dynamic caused_by_accidental_injury/1.
:- dynamic caused_by_skydiving/1.
:- dynamic caused_by_military_service/1.
:- dynamic caused_by_firefighting_service/1.
:- dynamic caused_by_police_service/1.
:- dynamic age_at_hospitalization/2.
:- dynamic fraud_or_misrepresentation/1.
:- dynamic wellness_visit_occurred_month/2.
:- dynamic confirmation_supplied_month/2.
:- dynamic hospitalization_month/2.
:- dynamic claim_made/1.

:- discontiguous confined_in_hospital/1.
:- discontiguous hospital_in_us/1.
:- discontiguous caused_by_sickness/1.
:- discontiguous caused_by_accidental_injury/1.
:- discontiguous caused_by_skydiving/1.
:- discontiguous caused_by_military_service/1.
:- discontiguous caused_by_firefighting_service/1.
:- discontiguous caused_by_police_service/1.
:- discontiguous age_at_hospitalization/2.
:- discontiguous fraud_or_misrepresentation/1.
:- discontiguous wellness_visit_occurred_month/2.
:- discontiguous confirmation_supplied_month/2.
:- discontiguous hospitalization_month/2.
:- discontiguous claim_made/1.

%% ---------------------------------------------------------------------
%% Top level: does the policy pay a benefit on this claim?
%% ---------------------------------------------------------------------
%% Sec 2.3: a claim must be made, setting out the basis for the claim and
%% for there being no exclusion or cancellation.
%% Sec 1.1: the policy must be in effect at the time of hospitalization.
%% Sec 2.1/2.2: the hospitalization must be of the kind the policy pays
%% for.
%% Sec 3.1: no general exclusion may apply.
covered(Claim) :-
    claim_made(Claim),
    policy_in_effect(Claim),
    benefit_applies(Claim),
    \+ excluded(Claim).

%% ---------------------------------------------------------------------
%% Sec 1.1-1.3: policy in effect / cancelation
%% ---------------------------------------------------------------------
%% Sec 1.1 lists four requirements for the policy to be in effect: signed,
%% premium paid, Sec 1.3 pending-or-timely-satisfied, and not canceled.
%% Per the task instructions, signing and timely premium payment are
%% always assumed true and are not encoded here. The Sec 1.3 requirement
%% and "not canceled" collapse into each other, because Sec 1.2 makes an
%% untimely Sec 1.3 outcome itself a ground for cancelation -- so a claim
%% for which no cancelation ground is proven is, by construction, one for
%% which Sec 1.3 is still "pending or ... satisfied in a timely fashion".
policy_in_effect(Claim) :-
    \+ canceled(Claim).

%% Sec 1.2: three independent grounds for cancelation.
canceled(Claim) :-
    fraud_or_misrepresentation(Claim).
canceled(Claim) :-
    condition_1_3_failed(Claim).
canceled(Claim) :-
    term_expired(Claim).

%% Sec 1.3: no later than the 7th month anniversary of the effective
%% date, written confirmation must be supplied of a wellness visit
%% occurring no later than the 6th month anniversary. Either the visit
%% occurring late, or the confirmation being supplied late, defeats
%% Sec 1.3.
condition_1_3_failed(Claim) :-
    wellness_visit_occurred_month(Claim, VisitMonth),
    VisitMonth > 6.
condition_1_3_failed(Claim) :-
    confirmation_supplied_month(Claim, ConfirmMonth),
    ConfirmMonth > 7.

%% Sec 4.6: the policy term is one year from the effective date;
%% hospitalization after month 12 falls outside the term, and the
%% policy has, by then, automatically canceled.
term_expired(Claim) :-
    hospitalization_month(Claim, HospMonth),
    HospMonth > 12.

%% ---------------------------------------------------------------------
%% Sec 2.1-2.2: the benefit trigger
%% ---------------------------------------------------------------------
%% Confinement in a hospital, as a result of sickness or accidental
%% injury, in a hospital in the United States (Sec 2.2).
benefit_applies(Claim) :-
    confined_in_hospital(Claim),
    caused_by_sickness_or_injury(Claim),
    hospital_in_us(Claim).

caused_by_sickness_or_injury(Claim) :-
    caused_by_sickness(Claim).
caused_by_sickness_or_injury(Claim) :-
    caused_by_accidental_injury(Claim).

%% ---------------------------------------------------------------------
%% Sec 3.1: general exclusions
%% ---------------------------------------------------------------------
%% Each exclusion requires the sickness/injury to arise (directly or
%% indirectly) out of the named activity -- not merely that the claimant
%% happens to hold the corresponding occupation/status at the time of
%% hospitalization.
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
