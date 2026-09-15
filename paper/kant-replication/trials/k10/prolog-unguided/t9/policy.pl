% =====================================================================
%  CODEX INSURANCE LIMITED -- policy encoding
% =====================================================================
%
%  Rules only. No facts about any particular claim are asserted in
%  this file -- those belong in queries.pl, one set per claim.
%
%  Assumptions carried over from the task instructions (not modeled
%  below because we are told to simply assume them):
%    - The agreement has been signed (Section 1.1(1)).
%    - The premium has been paid on time (Section 1.1(2), Section 3.5).
%
%  Time convention: every date/time other than the claimant's age is
%  expressed as a number of months elapsed since the policy's
%  effective date (see Section 3.6, "the effective date"). So "the 6th
%  month anniversary", "the 7th month anniversary" and "one year"
%  below are just the constants 6, 7 and 12. No query ever needs the
%  interval between two absolute dates -- only a comparison between a
%  given relative time and one of these constants.
%
%  Vocabulary of per-claim facts that queries.pl may assert (declared
%  dynamic below so that a claim which never mentions one of them
%  simply fails that check, rather than raising an existence error --
%  see the note on "unrelated conditions" further down):
%
%    sickness(Claim).
%    accidental_injury(Claim).
%        What the hospitalization was for. Section 1.1 only pays
%        benefits for hospitalization "for sickness or accidental
%        injury", so at least one of these must hold for a claim to
%        stand any chance of being covered.
%
%    hospitalization_time(Claim, Months).
%        Hospitalization occurred Months months after the effective
%        date. Only needed to test the one-year policy term (Section
%        3.6); omit it and the claim is treated as falling safely
%        inside the term.
%
%    age_at_hospitalization(Claim, Age).
%        The claimant's age, in years, at the time of hospitalization
%        (Section 2.1(5)). This is the one figure the task tells us is
%        NOT relative to the effective date.
%
%    confirmation_time(Claim, Months).
%        The written confirmation of the Section 1.3 wellness visit
%        was supplied to the insurer Months months after the effective
%        date. Omit it if the claim has nothing to do with that
%        condition.
%
%    fraud(Claim).
%    misrepresentation(Claim).
%    material_withholding(Claim).
%        Grounds for cancelation under Section 1.2.
%
%    arises_out_of(Claim, Activity).
%        The sickness or accidental injury arose directly or
%        indirectly OUT OF Activity, where Activity is one of:
%          skydiving, military_service, firefighter_service,
%          police_service.
%        Section 2.1 excludes injuries CAUSED BY these activities. It
%        does not exclude injuries that merely happen while the
%        claimant holds one of these jobs, or is on duty, if the job
%        itself did not produce the injury. Only assert this fact when
%        the activity is what actually produced the sickness/injury --
%        not merely a fact about the claimant's occupation or status
%        at the time.
%
%  On "unrelated conditions": every rule below is written so that a
%  claim for which a given fact is never asserted is treated as not
%  triggering whatever that fact would have triggered (no exclusion,
%  no cancelation). Combined with the dynamic declarations, this means
%  queries.pl only has to state the facts a question is actually
%  about; everything else already defaults to "does not stand in the
%  way of coverage", per the task's instruction to hold all unrelated
%  conditions/exclusions at their policy-favorable setting.

:- dynamic sickness/1.
:- dynamic accidental_injury/1.
:- dynamic hospitalization_time/2.
:- dynamic age_at_hospitalization/2.
:- dynamic confirmation_time/2.
:- dynamic fraud/1.
:- dynamic misrepresentation/1.
:- dynamic material_withholding/1.
:- dynamic arises_out_of/2.

% ---------------------------------------------------------------------
% Section 1.1 (chapeau) -- top-level coverage question
% ---------------------------------------------------------------------
%
%  "The payment of any benefit under this policy is conditioned on the
%   policy being in effect at the time of the hospitalization for
%   sickness or accidental injury on which the claim for such benefit
%   is premised."
%
%  Note: Sections 3.2-3.5 (arbitration, governing law, currency of
%  payment, premium timing) are procedural/administrative terms. None
%  of them is capable of making a policy that would otherwise apply
%  fail to apply, so none of them is encoded as a coverage condition
%  here.

covered(Claim) :-
    hospitalization_event(Claim),
    policy_in_effect(Claim),
    \+ excluded(Claim).

hospitalization_event(Claim) :-
    sickness(Claim).
hospitalization_event(Claim) :-
    accidental_injury(Claim).

% ---------------------------------------------------------------------
% Sections 1.1(3)-(4) and 1.2 -- policy in effect / cancelation
% ---------------------------------------------------------------------
%
%  Section 1.1 lists four conditions for the policy to be "in effect":
%    1. signed                        -- assumed (see header)
%    2. premium paid                  -- assumed (see header)
%    3. Section 1.3 still pending, or satisfied in a timely fashion
%    4. the policy has not been canceled
%  Condition 3 is exactly the negation of the "Section 1.3 has not
%  been satisfied in a timely fashion" cancelation ground that Section
%  1.2 separately lists, so the two collapse into the single check
%  below: the policy is in effect exactly when nothing has canceled
%  it.

policy_in_effect(Claim) :-
    \+ canceled(Claim).

%  Section 1.2: grounds for cancelation.
canceled(Claim) :-
    fraud(Claim).
canceled(Claim) :-
    misrepresentation(Claim).
canceled(Claim) :-
    material_withholding(Claim).
canceled(Claim) :-
    wellness_condition_violated(Claim).
canceled(Claim) :-
    policy_term_expired(Claim).

%  Section 1.3: written confirmation of the wellness visit must reach
%  the insurer no later than the 7th month anniversary of the
%  effective date. (The underlying visit itself must separately occur
%  no later than the 6th month anniversary, but every query gives only
%  a single "confirmation/proof supplied" date and never a separate
%  visit date, so the one figure available is checked against the
%  operative deadline for supplying confirmation, which is 7 months --
%  see NOTES.md.)
wellness_condition_violated(Claim) :-
    confirmation_time(Claim, Months),
    Months > 7.

%  Section 3.6: the policy runs for one year (12 months) from the
%  effective date and is automatically canceled once that term ends.
policy_term_expired(Claim) :-
    hospitalization_time(Claim, Months),
    Months > 12.

% ---------------------------------------------------------------------
% Section 2.1 -- general exclusions
% ---------------------------------------------------------------------

excluded(Claim) :-
    arises_out_of(Claim, skydiving).
excluded(Claim) :-
    arises_out_of(Claim, military_service).
excluded(Claim) :-
    arises_out_of(Claim, firefighter_service).
excluded(Claim) :-
    arises_out_of(Claim, police_service).
excluded(Claim) :-
    age_at_hospitalization(Claim, Age),
    Age >= 80.
