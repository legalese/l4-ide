% ============================================================================
% policy.pl -- Codex Insurance Limited policy, encoded as Prolog rules.
% ============================================================================
%
% Scope and conventions
% ----------------------------------------------------------------------
% - This file defines RULES only. No claim-specific facts are asserted
%   here; those belong in queries.pl, which is consulted after this file.
% - A "claim" is an opaque identifier (an atom, e.g. claim_1) standing for
%   one hypothetical hospitalization scenario. All per-claim facts are
%   keyed on that identifier.
% - Per the task brief, every date/time other than the claimant's age is
%   expressed RELATIVE TO THE POLICY'S EFFECTIVE DATE, as a number of
%   months elapsed since that date (fractional months, e.g. 6.5, are
%   allowed). We never compare two such relative dates against each
%   other -- each is compared only against a fixed deadline drawn from
%   the contract (6 months, 7 months, 12 months). Age is in ordinary
%   years, since the task exempts age from the "relative date" rule.
% - Per the task brief we also assume throughout that the agreement has
%   been signed and the premium has been paid on time (contract s.1.1(1)
%   and s.1.1(2), s.3.5); no rules or facts are needed for those two
%   sub-conditions.
%
% Top-level predicate
% ----------------------------------------------------------------------
%   covered(Claim)  -- succeeds iff the policy applies to Claim: the
%                      policy is in effect, the hospitalization is of a
%                      kind the policy covers at all, no s.2 exclusion
%                      applies, and the (vacuous) territorial condition
%                      is met.
%
% Per-claim facts this file expects queries.pl to supply (all declared
% dynamic below, so an absent fact simply fails rather than erroring):
%
%   hospitalization_type(Claim, Type)
%       Type is one of: sickness | accidental_injury |
%       intentional_self_inflicted_injury.
%   claimant_age(Claim, AgeYears)
%       The claimant's age, in whole years, at the time of the
%       hospitalization.
%   hospitalization_month(Claim, Months)
%       When the hospitalization occurred, in months after the
%       effective date.
%   wellness_visit_month(Claim, Months)
%       When the wellness-visit medical appointment itself (s.1.3)
%       occurred, in months after the effective date.
%   wellness_confirmation_month(Claim, Months)
%       When written confirmation of that visit was supplied to the
%       Company (s.1.3), in months after the effective date.
%   fraud_or_misrepresentation(Claim)
%       Holds if the claimant committed fraud, misrepresentation, or
%       material withholding of information (s.1.2).
%   arises_out_of(Claim, Activity)
%       Holds if the sickness or accidental injury being claimed on
%       arose directly or indirectly out of Activity. Activity is one
%       of: skydiving | military_service | firefighter_service |
%       police_service (s.2.1(1)-(4)).
%
% Design note on defaults (see NOTES.md for the full discussion): the
% exclusion/cancellation predicates below are all written so that an
% UNASSERTED fact never triggers an exclusion or a cancellation -- that
% is how "assume every condition/exclusion not mentioned in the query is
% resolved in the policyholder's favour" is realised for all of them
% *except* hospitalization_type/2, where the opposite default would
% apply (silently omitting it would default to NOT covered). That is
% why queries.pl asserts a hospitalization_type/2 fact for every claim,
% even the ones where the question does not turn on the medical cause.
% ============================================================================

:- dynamic hospitalization_type/2.
:- dynamic claimant_age/2.
:- dynamic hospitalization_month/2.
:- dynamic wellness_visit_month/2.
:- dynamic wellness_confirmation_month/2.
:- dynamic fraud_or_misrepresentation/1.
:- dynamic arises_out_of/2.

% ----------------------------------------------------------------------
% Top-level coverage predicate.
% ----------------------------------------------------------------------

covered(Claim) :-
    policy_in_effect(Claim),
    hospitalization_covered_event(Claim),
    \+ excluded(Claim),
    territorial_scope_ok(Claim).

% ----------------------------------------------------------------------
% s.1.1 -- what kind of hospitalization the policy covers at all.
%
% "The payment of any benefit under this policy is conditioned on the
% policy being in effect at the time of the hospitalization for sickness
% or accidental injury on which the claim ... is premised."
%
% A hospitalization brought about by the claimant's own intentional act
% (as opposed to sickness, or an injury that is accidental from the
% claimant's point of view) is not "for sickness or accidental injury"
% at all, and so never reaches the s.2 exclusion analysis -- it simply
% is not the kind of event this policy insures against. See NOTES.md.
% ----------------------------------------------------------------------

hospitalization_covered_event(Claim) :-
    hospitalization_type(Claim, sickness).
hospitalization_covered_event(Claim) :-
    hospitalization_type(Claim, accidental_injury).

% ----------------------------------------------------------------------
% s.1.1/s.1.2 -- the policy being "in effect" / cancelation.
%
% s.1.1 lists four sub-conditions for the policy to be in effect:
% signed (assumed true throughout, per the task brief), premium paid
% (assumed true throughout), s.1.3's condition still pending or
% satisfied in a timely fashion, and the policy not having been
% canceled. s.1.2 then defines cancelation to include exactly the case
% where s.1.3 "has not been satisfied in a timely fashion" -- so
% "s.1.3 pending-or-satisfied" and "not canceled on account of s.1.3"
% are two sides of the same coin, and are collapsed here into the
% single "not canceled" check to avoid encoding the same rule twice.
% ----------------------------------------------------------------------

policy_in_effect(Claim) :-
    \+ cancelled(Claim).

% s.1.2: cancelation is deemed to occur on any of three grounds.
cancelled(Claim) :-
    fraud_or_misrepresentation(Claim).
cancelled(Claim) :-
    condition_1_3_failed(Claim).
cancelled(Claim) :-
    policy_term_expired(Claim).

% s.1.3: two independent deadlines, each measured from the effective
% date and each checked on its own (never against each other, and
% never against the hospitalization date -- see the file header and
% NOTES.md for why the "still pending" language in s.1.1(3) does not
% need its own separate representation under this task's rules).
%   (a) the wellness visit itself must occur no later than the 6th
%       month anniversary of the effective date;
%   (b) written confirmation of it must be supplied no later than the
%       7th month anniversary.
condition_1_3_failed(Claim) :-
    wellness_visit_month(Claim, VisitMonths),
    VisitMonths > 6.
condition_1_3_failed(Claim) :-
    wellness_confirmation_month(Claim, ConfirmMonths),
    ConfirmMonths > 7.

% s.1.2/s.3.6: the policy term is one year from the effective date;
% the policy is automatically canceled once that term has elapsed.
policy_term_expired(Claim) :-
    hospitalization_month(Claim, Months),
    Months > 12.

% ----------------------------------------------------------------------
% s.2.1 -- General Exclusions.
%
% Grounds (1)-(4) are causal: the sickness or accidental injury must
% arise "directly or indirectly out of" the named activity -- merely
% holding the named role at the time of hospitalization, with no causal
% connection to the injury, is not enough (see NOTES.md re: Q9). Ground
% (5) is a bare status/threshold check with no causal element.
% ----------------------------------------------------------------------

excluded(Claim) :- arises_out_of(Claim, skydiving).
excluded(Claim) :- arises_out_of(Claim, military_service).
excluded(Claim) :- arises_out_of(Claim, firefighter_service).
excluded(Claim) :- arises_out_of(Claim, police_service).
excluded(Claim) :-
    claimant_age(Claim, Age),
    Age >= 80.

% ----------------------------------------------------------------------
% s.3.1 -- territorial scope.
%
% "Your Policy insures You twenty-four (24) hours a day anywhere in the
% world." There is no territorial limitation to check; this predicate
% is included, and consulted from covered/1, purely so that s.3.1 is
% faithfully represented rather than silently skipped.
% ----------------------------------------------------------------------

territorial_scope_ok(_Claim) :- true.

% ----------------------------------------------------------------------
% s.3.2 -- Arbitration / dispute-resolution mechanics.
%
% These provisions condition a policyholder's right to litigate or
% recover on a claim that is actually IN DISPUTE: a 3-month time limit
% to commence arbitration (on pain of the claim being "extinguished
% completely"), a valid arbitration award as a condition precedent to
% liability wherever there is a dispute, and a 60-day moratorium on
% suing after written proof of claim is submitted. These are procedural
% conditions on enforcement of a claim, analytically separate from
% whether the underlying event is substantively covered/excluded under
% s.1-s.2, which is the only thing any of "will my policy apply if ..."
% the nine benchmark questions ask about. None of the nine puts a
% dispute in issue, so these are defined here for completeness (per the
% task's "fully define all predicates" instruction) but are deliberately
% NOT consulted by covered/1. See NOTES.md.
% ----------------------------------------------------------------------

:- dynamic dispute_exists/1.
:- dynamic arbitration_commenced_in_time/1.
:- dynamic valid_arbitration_award_issued/1.

% The claim is extinguished completely if a dispute arose and
% arbitration was not commenced within three months of the parties'
% being unable to settle it.
claim_extinguished_for_late_arbitration(Claim) :-
    dispute_exists(Claim),
    \+ arbitration_commenced_in_time(Claim).

% A valid arbitration award is a condition precedent to the Company's
% liability only where there is a dispute in the first place.
arbitration_condition_precedent_met(Claim) :-
    \+ dispute_exists(Claim).
arbitration_condition_precedent_met(Claim) :-
    dispute_exists(Claim),
    valid_arbitration_award_issued(Claim).

% Note: s.3.3 (governing law: New York), s.3.4 (payments in US
% currency), and s.3.5 (premium paid as a lump sum at signing, already
% assumed true throughout) impose no condition that bears on whether a
% given hospitalization is covered, so no predicate is defined for
% them.
