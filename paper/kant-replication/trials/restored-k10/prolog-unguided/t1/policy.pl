% =====================================================================
%  policy.pl -- Prolog encoding of the CODEX INSURANCE LIMITED policy
% =====================================================================
%
%  This file contains ONLY rules, no claim-specific facts (per the
%  task instructions). Per-claim facts are supplied by queries.pl,
%  which is consulted immediately after this file and populates the
%  fact vocabulary declared dynamic below.
%
%  DATES: every timing fact in this encoding is a number of months
%  elapsed since the policy's effective date (Sec. 4.6). No absolute
%  calendar dates appear anywhere, per the instruction that all
%  query-supplied dates/times (other than the claimant's age) are
%  given relative to the effective date, and that no elapsed-time
%  arithmetic between two dates is ever required.
%
%  The top-level predicate is covered/1: covered(Claim) succeeds iff
%  the policy applies to (i.e. a benefit is payable for) the
%  hospitalization described by the facts attached to Claim, an
%  opaque claim identifier such as claim_1 chosen by queries.pl.
%
%  Signature of the agreement and timely payment of the premium
%  (Sec. 1.1(1)-(2), Sec. 4.5) are, per the task instructions, always
%  satisfied and are therefore not modelled at all -- no predicate,
%  no fact. The requirement that a claim actually be made to the
%  Company (Sec. 2.3) is likewise not modelled as a gate: every
%  question this encoding answers is itself framed as a hypothetical
%  claim ("will my policy apply if..."), so the making of a claim is
%  assumed throughout. See NOTES.md for this and the other judgement
%  calls behind this encoding.
% ---------------------------------------------------------------------

% ---------------------------------------------------------------------
%  Fact vocabulary supplied by queries.pl.  Every predicate a claim
%  might need is declared dynamic here so that a claim which simply
%  does not mention a given circumstance -- and so never asserts the
%  corresponding fact -- makes the relevant rule fail cleanly instead
%  of raising an existence error ("procedure does not exist").
% ---------------------------------------------------------------------
:- dynamic sickness/1.                     % sickness(Claim)
:- dynamic injury/1.                       % injury(Claim)
:- dynamic self_inflicted_intentionally/1. % self_inflicted_intentionally(Claim)
:- dynamic injury_arises_from/2.           % injury_arises_from(Claim, Activity)
:- dynamic age_at_hospitalization/2.       % age_at_hospitalization(Claim, Years)
:- dynamic wellness_confirmation_month/2.  % wellness_confirmation_month(Claim, Months)
:- dynamic hospitalization_month/2.        % hospitalization_month(Claim, Months)
:- dynamic hospitalized_outside_us/1.      % hospitalized_outside_us(Claim)
:- dynamic fraud_or_misrepresentation/1.   % fraud_or_misrepresentation(Claim)

% ---------------------------------------------------------------------
%  TOP LEVEL  (Secs. 1.1, 2.1, 2.2, 3.1)
% ---------------------------------------------------------------------
%  The policy applies to a hospitalization iff: the policy is in
%  effect (Sec. 1), the hospitalization is for a covered peril
%  (Sec. 2.1), the confinement is in a US hospital (Sec. 2.2), and no
%  exclusion (Sec. 3.1) applies.
covered(Claim) :-
    policy_in_effect(Claim),
    covered_peril(Claim),
    \+ hospitalized_outside_us(Claim),
    \+ excluded(Claim).

% ---------------------------------------------------------------------
%  POLICY IN EFFECT  (Section 1)
% ---------------------------------------------------------------------
%  Sec. 1.1 lists four conditions for the policy to be in effect:
%  signed, premium paid, Sec. 1.3 pending-or-satisfied-timely, and not
%  cancelled. The first two are stipulated as always true (see above
%  and NOTES.md) and so drop out. The third is in fact subsumed by the
%  fourth: Sec. 1.2 defines cancellation to include the case where
%  Sec. 1.3 was not satisfied in a timely fashion, so within this
%  encoding "not cancelled" already entails "Sec. 1.3 pending or
%  satisfied timely" (see the cancelled/1 clause that calls
%  section_1_3_ok/1 below). Policy-in-effect therefore reduces to
%  "not cancelled".
policy_in_effect(Claim) :-
    \+ cancelled(Claim).

%  Sec. 1.2: cancellation is triggered by any of:
%    (a) fraud, misrepresentation, or material withholding of
%        information provided to the Company;
%    (b) failure to satisfy Sec. 1.3 (the wellness-visit confirmation
%        requirement) in a timely fashion;
%    (c) the policy having reached the end of its one-year term
%        (Sec. 4.6) without prior cancellation.
cancelled(Claim) :- fraud_or_misrepresentation(Claim).
cancelled(Claim) :- \+ section_1_3_ok(Claim).
cancelled(Claim) :- policy_term_expired(Claim).

%  Sec. 1.3: written confirmation of a wellness visit must reach the
%  Company no later than the 7-month anniversary of the effective
%  date (the underlying visit itself must occur no later than the
%  6-month anniversary; see NOTES.md on why confirmation timing alone
%  is treated as dispositive here).
%
%  If no confirmation has been supplied at all, Sec. 1.1(3)'s "still
%  pending" language keeps this condition satisfied as long as the
%  7-month mark has not yet passed by the time of hospitalization;
%  that lapse is only checked when hospitalization timing is actually
%  on record, so a claim silent on both facts defaults to "pending,
%  fine" (per the instruction to satisfy conditions unrelated to the
%  query).
section_1_3_ok(Claim) :-
    wellness_confirmation_month(Claim, Months),
    Months =< 7.
section_1_3_ok(Claim) :-
    \+ wellness_confirmation_month(Claim, _),
    \+ overdue_without_confirmation(Claim).

overdue_without_confirmation(Claim) :-
    hospitalization_month(Claim, Months),
    Months > 7.

%  Sec. 4.6: the policy term is one year from the effective date.
policy_term_expired(Claim) :-
    hospitalization_month(Claim, Months),
    Months > 12.

% ---------------------------------------------------------------------
%  COVERED PERIL  (Section 2.1)
% ---------------------------------------------------------------------
%  A benefit is only ever payable for hospitalization due to sickness
%  or accidental injury.
covered_peril(Claim) :- sickness(Claim).
covered_peril(Claim) :- accidental_injury(Claim).

%  "Accidental" is given its ordinary meaning: the injury itself must
%  be unintended. An injury that is the direct, intended physical
%  consequence of the claimant's own deliberate act against
%  themselves is not "accidental", even though the broader activity
%  that gave rise to it (e.g. skydiving) may have been undertaken
%  voluntarily. This is the highest-stakes judgement call in this
%  encoding; see NOTES.md.
accidental_injury(Claim) :-
    injury(Claim),
    \+ self_inflicted_intentionally(Claim).

% ---------------------------------------------------------------------
%  GENERAL EXCLUSIONS  (Section 3.1)
% ---------------------------------------------------------------------
%  Each of these requires that the sickness or injury actually arose,
%  directly or indirectly, out of the named activity -- not merely
%  that the claimant holds that occupation or status. (E.g. a police
%  officer's off-duty, unrelated injury does not fall within
%  "[a]rising ... out of ... [s]ervice in the police".) See NOTES.md.
excluded(Claim) :- injury_arises_from(Claim, skydiving).
excluded(Claim) :- injury_arises_from(Claim, military_service).
excluded(Claim) :- injury_arises_from(Claim, firefighting).
excluded(Claim) :- injury_arises_from(Claim, police_service).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.

% ---------------------------------------------------------------------
%  PROVISIONS DELIBERATELY NOT MODELLED AS COVERAGE GATES
% ---------------------------------------------------------------------
%  - Sec. 2.2's 365-day cap limits how many days of confinement are
%    paid; it does not gate whether the policy applies at all, and no
%    benchmark question turns on the length of confinement.
%  - Sec. 4.1 ("insures You ... anywhere in the world") is read as
%    worldwide scope for the insured EVENT (no exclusion for
%    sickness/injury occurring abroad); it is the hospital
%    CONFINEMENT itself, per Sec. 2.2, that must be in the US -- see
%    hospitalized_outside_us/1 above.
%  - Sec. 4.2 (arbitration) is a dispute-resolution mechanism that
%    only bites once a dispute exists; no benchmark question posits
%    one.
%  - Secs. 4.3-4.5 (governing law, currency, premium mechanics) and
%    Sec. 5 (dollar amounts) are not coverage conditions.
