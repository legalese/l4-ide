% =====================================================================
%  policy.pl
%
%  Prolog encoding of the CODEX INSURANCE LIMITED hospital-indemnity
%  policy (fixtures/chubb-policy.txt). Rules only -- no claim facts;
%  claim facts belong in queries.pl.
%
%  Every predicate whose truth depends on the particulars of a claim
%  (the "leaf" predicates declared dynamic below) is left to be
%  supplied, per claim, by queries.pl. Declaring them dynamic here
%  means that if a particular claim simply never mentions one of
%  them, calling it fails cleanly instead of raising a "procedure
%  does not exist" error -- i.e. Prolog's closed-world assumption
%  does exactly what the task's instructions ask for ("set any
%  fact/rule/parameter unrelated to the query such that it is
%  satisfied / no unrelated exclusion applies") automatically,
%  provided queries.pl asserts only the facts actually in play for
%  each question.
%
%  All dates/times below are expressed in months elapsed since the
%  policy's effective date -- the contract itself uses "Nth month
%  anniversary" language, and the benchmark questions phrase timing
%  the same way. Age is the one absolute (non-relative) quantity, per
%  the task brief.
% =====================================================================

:- dynamic fraud_or_misrepresentation/1.
:- dynamic wellness_visit_month/2.
:- dynamic confirmation_month/2.
:- dynamic hospitalization_month/2.
:- dynamic sickness/1.
:- dynamic accidental_injury/1.
:- dynamic confined_in_hospital/1.
:- dynamic hospital_in_us/1.
:- dynamic confinement_days/2.
:- dynamic arose_from_skydiving/1.
:- dynamic arose_from_military_service/1.
:- dynamic arose_from_firefighter_service/1.
:- dynamic arose_from_police_service/1.
:- dynamic age_at_hospitalization/2.
:- dynamic claim_made/1.

% ---------------------------------------------------------------------
% Section 1 -- POLICY IN EFFECT AND CONDITIONS
% ---------------------------------------------------------------------

% 1.1: any benefit is conditioned on the policy being in effect at the
% time of the hospitalization. Items 1-2 of 1.1 (the agreement is
% signed; the premium has been paid) are assumed true throughout, per
% the task brief, and are deliberately not encoded.
policy_in_effect(Claim) :-
    condition_1_3_pending_or_satisfied(Claim),
    \+ policy_canceled(Claim).

% 1.2: cancelation is deemed to occur on any of three independent
% grounds.
policy_canceled(Claim) :- fraud_or_misrepresentation(Claim).
policy_canceled(Claim) :- condition_1_3_failed(Claim).
policy_canceled(Claim) :- policy_term_expired(Claim).

% 1.3 sets two distinct deadlines, both measured from the effective
% date: (a) the wellness visit itself must occur no later than the
% 6-month anniversary; (b) written confirmation of that visit must
% reach the Company no later than the 7-month anniversary.
%
% confirmation_month/2 records when (if ever) confirmation was
% actually supplied for a claim. When a claim also separately records
% when the underlying visit happened (wellness_visit_month/2), that
% date is checked as well; absent such a fact, a timely confirmation
% is taken as adequate evidence that the visit it confirms was itself
% timely -- the text gives no basis for assuming a claimant supplied
% confirmation of a visit that never happened, or happened late.
condition_1_3_satisfied_timely(Claim) :-
    confirmation_month(Claim, CM),
    CM =< 7,
    visit_month_ok(Claim, CM).

visit_month_ok(Claim, ConfirmationMonth) :-
    wellness_visit_month(Claim, VM),
    !,
    VM =< 6,
    VM =< ConfirmationMonth.
visit_month_ok(_Claim, _ConfirmationMonth).

% 1.1(3) also lets the condition be merely "still pending": if the
% 7-month confirmation deadline has not yet arrived as of the
% hospitalization, a not-yet-supplied confirmation is not (yet) a
% breach.
condition_1_3_still_pending(Claim) :-
    \+ confirmation_month(Claim, _),
    hospitalization_month(Claim, HM),
    HM < 7.

condition_1_3_pending_or_satisfied(Claim) :-
    condition_1_3_still_pending(Claim).
condition_1_3_pending_or_satisfied(Claim) :-
    condition_1_3_satisfied_timely(Claim).

% "Not satisfied in a timely fashion" (1.2's cancelation trigger) is
% the complement of the above: confirmation arrived too late,
% confirmation arrived on time but for a visit that itself wasn't, or
% confirmation never arrived and the deadline has now passed.
condition_1_3_failed(Claim) :-
    confirmation_month(Claim, CM),
    CM > 7.
condition_1_3_failed(Claim) :-
    confirmation_month(Claim, CM),
    CM =< 7,
    \+ visit_month_ok(Claim, CM).
condition_1_3_failed(Claim) :-
    \+ confirmation_month(Claim, _),
    hospitalization_month(Claim, HM),
    HM >= 7.

% 1.2 / 4.6: the policy term is one year (12 months); the policy lapses
% automatically at its end.
policy_term_expired(Claim) :-
    hospitalization_month(Claim, HM),
    HM > 12.

% ---------------------------------------------------------------------
% Section 2 -- BENEFITS
% ---------------------------------------------------------------------

% 2.1/2.2/2.3 together: the Daily Hospital Income Benefit -- and hence
% "the policy applying" to a claim, in the sense the benchmark
% questions ask about -- requires the policy to be in effect,
% hospitalization qualifying under 2.2, a sickness- or injury-based
% cause, no applicable exclusion, and a claim actually made.
covered(Claim) :-
    policy_in_effect(Claim),
    hospitalized(Claim),
    caused_by_sickness_or_injury(Claim),
    \+ excluded(Claim),
    claim_made(Claim).

caused_by_sickness_or_injury(Claim) :- sickness(Claim).
caused_by_sickness_or_injury(Claim) :- accidental_injury(Claim).

% 2.2: payable for each day of confinement in a hospital *in the
% United States*, from the first day, for up to 365 days of such
% confinement. Clause 4.1.1 separately confirms there is no
% territorial restriction on where the underlying sickness/injury-
% causing event itself may occur ("Your Policy insures You ... anywhere
% in the world"). Read together the two clauses need not conflict: the
% insured *peril* is covered worldwide, but the *hospital confinement*
% that triggers the daily payment must specifically be in a U.S.
% hospital. (This is a judgement call about an internal tension in the
% source text -- see NOTES.md.)
hospitalized(Claim) :-
    confined_in_hospital(Claim),
    hospital_in_us(Claim),
    confinement_days(Claim, Days),
    Days > 0.

% The 365-day cap in 2.2 bounds how many days are *payable*; it is not
% an all-or-nothing gate on whether the claim is covered at all (a
% confinement of, say, 400 days is still covered for its first 365).
% No benchmark question turns on confinement length; this predicate is
% included for completeness and does not gate covered/1.
payable_days(Claim, PayableDays) :-
    confinement_days(Claim, Days),
    PayableDays is min(Days, 365).

% ---------------------------------------------------------------------
% Section 3 -- GENERAL EXCLUSIONS
% ---------------------------------------------------------------------

% 3.1: each exclusion requires the sickness/injury to arise, directly
% or indirectly, OUT OF the listed activity or status ("any event
% causing sickness or accidental injury arising directly or indirectly
% out of: ..."). Merely being a skydiver / service member / firefighter
% / police officer -- or even being on duty as one -- at the moment of
% hospitalization is not, by itself, enough; the hospitalization must
% be causally connected to that activity or status. (E.g. a firefighter
% injured while fighting a fire is excluded; a firefighter hospitalized
% for a cause unconnected to firefighting is not, merely because they
% happen to be a firefighter.)
excluded(Claim) :- arose_from_skydiving(Claim).
excluded(Claim) :- arose_from_military_service(Claim).
excluded(Claim) :- arose_from_firefighter_service(Claim).
excluded(Claim) :- arose_from_police_service(Claim).
excluded(Claim) :- age_exclusion(Claim).

% 3.1.5: excluded if age at the time of hospitalization is 80 or older.
age_exclusion(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.

% ---------------------------------------------------------------------
% Section 4 -- GENERAL CONDITIONS
% ---------------------------------------------------------------------
%
% 4.1.1 is already relied on above (see the comment on hospitalized/1).
% 4.2 (arbitration, and the 60-day pre-suit wait), 4.3 (governing law),
% 4.4 (currency of payment) and 4.5 (premium timing) are procedural or
% remedial provisions governing *how* a dispute or payment is carried
% out, not *whether* the policy applies to a given claim in the first
% place, so they are not modeled as coverage-gating predicates here;
% none of the nine benchmark questions turn on them. 4.6 (the one-year
% term) is encoded above as policy_term_expired/1.
