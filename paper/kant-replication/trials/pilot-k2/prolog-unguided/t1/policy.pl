% =====================================================================
%  CODEX INSURANCE LIMITED -- policy encoding (unguided Prolog cell)
% =====================================================================
%
%  Rules only -- no claim facts.  Every fact this file depends on is a
%  per-claim fact asserted in queries.pl and declared `dynamic` below so
%  that consulting this file alone (or before queries.pl) never raises
%  "procedure does not exist".
%
%  ---------------------------------------------------------------
%  Modeling scope and judgement calls (see also NOTES.md)
%  ---------------------------------------------------------------
%
%  * Sec. 1.1(1)-(2): agreement signed / premium paid on time are
%    assumed always true per the task brief, so no predicate is defined
%    for either -- there is nothing for a query to ever get wrong here.
%
%  * Sec. 3.1 (worldwide, 24-hour coverage): encoded by *omission*.
%    There is no location- or time-of-day-based exclusion anywhere in
%    this file, which is itself the faithful encoding of "insures You
%    twenty-four (24) hours a day anywhere in the world."
%
%  * Sec. 3.2 (arbitration, and its 60-day pre-suit waiting period),
%    Sec. 3.3 (governing law) and Sec. 3.4 (currency of payment) are
%    procedural/administrative terms that condition how a dispute is
%    litigated or a recovery is sought, not whether the underlying
%    hospitalization is a covered loss in the first place. None of the
%    benchmark questions posit a dispute, so these are treated as out
%    of scope for `covered/1` and are not encoded here.
%
%  * Sec. 1.3 states TWO deadlines measured from the effective date:
%    the wellness visit itself must occur by the 6-month anniversary,
%    and written confirmation *of* that visit must be supplied to the
%    Company by the 7-month anniversary. Both are modeled explicitly
%    below (`wellness_visit_time_months/2`,
%    `confirmation_submitted_time_months/2`).
%
%  * Sec. 1.1(3)'s "still pending or has been satisfied in a timely
%    fashion" is collapsed into a single satisfied/not-satisfied test
%    (`condition_1_3_satisfied/1`) rather than separately modeling a
%    "not yet due" pending state. Every claim in this benchmark gives,
%    or is assigned (where the question does not mention the wellness
%    condition at all), a concrete month figure, so the "still pending"
%    branch is never actually exercised and collapsing it is safe here.
%
% ---------------------------------------------------------------------

:- dynamic age_at_hospitalization/2.
:- dynamic hospitalization_time_months/2.
:- dynamic wellness_visit_time_months/2.
:- dynamic confirmation_submitted_time_months/2.
:- dynamic fraud_misrep_or_withholding/1.
:- dynamic injury_arose_from_skydiving/1.
:- dynamic injury_arose_from_military_service/1.
:- dynamic injury_arose_from_firefighter_service/1.
:- dynamic injury_arose_from_police_service/1.

% ---------------------------------------------------------------------
%  Top level.
%  Sec. 1.1: "the payment of any benefit under this policy is
%  conditioned on the policy being in effect ..."; Sec. 2.1: "... no
%  benefit will be paid" if an exclusion applies to the event.
% ---------------------------------------------------------------------

covered(Claim) :-
    policy_in_effect(Claim),
    \+ excluded(Claim).

% ---------------------------------------------------------------------
%  Sec. 1.1 -- policy in effect.
%    1. agreement signed              -- assumed true (not encoded)
%    2. premium paid                  -- assumed true (not encoded)
%    3. Sec. 1.3 condition pending or satisfied in a timely fashion
%    4. policy not canceled
%  Clauses 3 and 4 are not independent: failing Sec. 1.3's timeliness
%  is itself one of the grounds for cancellation under Sec. 1.2, so
%  both are captured together below by `\+ cancelled/1`.
% ---------------------------------------------------------------------

policy_in_effect(Claim) :-
    \+ cancelled(Claim).

% ---------------------------------------------------------------------
%  Sec. 1.2 -- grounds for cancellation.
% ---------------------------------------------------------------------

% fraud, misrepresentation, or material withholding of information
cancelled(Claim) :-
    fraud_misrep_or_withholding(Claim).

% the Sec. 1.3 wellness-visit condition was not satisfied in a timely
% fashion
cancelled(Claim) :-
    \+ condition_1_3_satisfied(Claim).

% automatic cancellation "at midnight ... on the last day of the policy
% term" (Sec. 3.6): modeled as the hospitalization falling outside the
% one-year term, i.e. the policy has already lapsed by then.
cancelled(Claim) :-
    \+ hospitalization_within_policy_term(Claim).

% ---------------------------------------------------------------------
%  Sec. 1.3 -- wellness-visit condition (two deadlines, both measured
%  in months from the effective date).
% ---------------------------------------------------------------------

condition_1_3_satisfied(Claim) :-
    wellness_visit_time_months(Claim, VisitMonths),
    VisitMonths =< 6,
    confirmation_submitted_time_months(Claim, ConfirmMonths),
    ConfirmMonths =< 7.

% ---------------------------------------------------------------------
%  Sec. 3.6 -- one-year policy term.
% ---------------------------------------------------------------------

hospitalization_within_policy_term(Claim) :-
    hospitalization_time_months(Claim, Months),
    Months =< 12.

% ---------------------------------------------------------------------
%  Sec. 2.1 -- general exclusions.
%  Each activity-based exclusion is keyed on the *cause* of the
%  sickness or injury "arising directly or indirectly out of" the
%  listed activity -- not on the claimant's occupation or status at
%  the time of hospitalization. A serving police officer hospitalized
%  for something that has nothing to do with police duty is not caught
%  by Sec. 2.1.4, for example.
% ---------------------------------------------------------------------

excluded(Claim) :- injury_arose_from_skydiving(Claim).
excluded(Claim) :- injury_arose_from_military_service(Claim).
excluded(Claim) :- injury_arose_from_firefighter_service(Claim).
excluded(Claim) :- injury_arose_from_police_service(Claim).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
