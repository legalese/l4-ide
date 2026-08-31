%% ============================================================================
%% CODEX INSURANCE LIMITED -- Hospital Income Policy
%% Prolog encoding of the policy contract (inputs/chubb-policy.txt).
%%
%% RULES ONLY. No claim-specific facts appear in this file -- those belong in
%% queries.pl, which is consulted after this file.
%%
%% TIME CONVENTION: every date/time-valued fact (other than the claimant's
%% age) is expressed as a number of months elapsed SINCE THE POLICY'S
%% EFFECTIVE DATE, per the task instructions. There is never a need to
%% compare two absolute dates, and no absolute date/time is encoded anywhere
%% below.
%% ============================================================================

%% ---- dynamic declarations for every claim-level fact ----------------------
%% Declaring these dynamic (before queries.pl is consulted) guarantees that
%% each predicate below is a *known* predicate even for a claim that supplies
%% no fact for it, so a missing fact makes a goal FAIL, and never throws
%% existence_error(procedure, .../N).
:- dynamic(hospitalized/1).
:- dynamic(cause_type/2).                              % sickness | accidental_injury
:- dynamic(self_inflicted_intentional/1).
:- dynamic(activity_cause/2).                          % skydiving | military | firefighter | police
:- dynamic(claimant_age/2).                            % age in years -- the one absolute figure permitted
:- dynamic(hospitalization_time_months/2).             % months after the effective date
:- dynamic(wellness_confirmation_provided_months/2).   % months after the effective date
:- dynamic(confinement_duration_days/2).
:- dynamic(hospital_location/2).                       % us | abroad
:- dynamic(fraud_or_misrepresentation/1).
:- dynamic(dispute_raised/1).
:- dynamic(arbitration_commenced_timely/1).
:- dynamic(arbitration_award_issued/1).

%% ============================================================================
%% Section 1 -- Policy in effect and conditions
%% ============================================================================
%% 1.1: the policy is in effect if the agreement is signed, the premium is
%% paid, condition 1.3 is pending-or-satisfied, and the policy has not been
%% canceled. Per the task instructions, "signed" and "premium paid" are to be
%% assumed true throughout and are deliberately NOT modeled here.

policy_in_effect(Claim) :-
    condition_1_3_pending_or_satisfied(Claim),
    \+ canceled(Claim),
    within_policy_term(Claim).

%% 1.3: no later than the 7-month anniversary of the effective date, the
%% insured must supply written confirmation of a wellness visit that itself
%% took place no later than the 6-month anniversary.
%%
%% JUDGEMENT CALL -- see NOTES.md. The only fact any query gives us is *when
%% confirmation was supplied*, never the date of the underlying visit. The
%% 7-month confirmation deadline is treated as the operative, checkable
%% constraint; consistent with the standing instruction that any condition
%% not referenced by a query is to be assumed satisfied, the visit itself is
%% assumed to have occurred in time whenever a query does not say otherwise.
condition_1_3_pending_or_satisfied(Claim) :-
    wellness_confirmation_provided_months(Claim, Months),
    Months =< 7.

%% 1.2 Cancelation.
canceled(Claim) :-
    fraud_or_misrepresentation(Claim).
canceled(Claim) :-
    \+ condition_1_3_pending_or_satisfied(Claim).

%% 4.6: the policy term is one year (12 months) from the effective date; the
%% policy is automatically canceled at its end. A claim's hospitalization
%% must therefore fall within the first 12 months.
within_policy_term(Claim) :-
    hospitalization_time_months(Claim, Months),
    Months =< 12.

%% ============================================================================
%% Section 2 -- Benefits
%% ============================================================================
%% 2.1: the benefit is paid for hospital confinement caused by sickness or
%% accidental injury.
covered_cause(Claim) :-
    cause_type(Claim, sickness).
covered_cause(Claim) :-
    cause_type(Claim, accidental_injury),
    \+ self_inflicted_intentional(Claim).

qualifying_event(Claim) :-
    hospitalized(Claim),
    covered_cause(Claim).

%% 2.2: the benefit is payable only for confinement (a) in a hospital in the
%% United States, and (b) not exceeding 365 days.
%%
%% JUDGEMENT CALL -- see NOTES.md. Section 4.1.1 says the policy "insures
%% You ... anywhere in the world", read here as fixing the territorial scope
%% of what may TRIGGER cover (the sickness/injury-causing event may happen
%% anywhere), while section 2.2's "in a hospital in the United States" is the
%% more specific rule that actually gates payment of the one benefit this
%% policy provides. Confinement outside the US is therefore read as not
%% payable, notwithstanding 4.1.1.
confined_in_us(Claim) :-
    (   hospital_location(Claim, Location)
    ->  Location = us
    ;   true    % location not put in issue by the claim -> assume it is the US
    ).

within_confinement_cap(Claim) :-
    (   confinement_duration_days(Claim, Days)
    ->  Days =< 365
    ;   true    % duration not put in issue by the claim -> assume within cap
    ).

%% ============================================================================
%% Section 3 -- General exclusions
%% ============================================================================
%% 3.1's chapeau excludes an event "arising directly or indirectly out of"
%% one of five listed causes. That wording requires a causal link between the
%% excluded activity and the sickness/injury -- merely holding a status
%% (e.g. being employed as a police officer) at the moment of an otherwise
%% unrelated injury does not, on its own, satisfy "arising ... out of" that
%% status. See NOTES.md for the case this was written to resolve.
excluded(Claim) :-
    activity_cause(Claim, skydiving).
excluded(Claim) :-
    activity_cause(Claim, military).
excluded(Claim) :-
    activity_cause(Claim, firefighter).
excluded(Claim) :-
    activity_cause(Claim, police).
excluded(Claim) :-
    claimant_age(Claim, Age),
    Age >= 80.

%% ============================================================================
%% Section 4 -- General conditions
%% ============================================================================
%% 4.2 Arbitration: a valid arbitration award is a condition precedent to
%% liability, but only once a dispute actually exists. No dispute on record
%% for a claim -> the condition is trivially satisfied.
arbitration_condition_satisfied(Claim) :-
    \+ dispute_raised(Claim).
arbitration_condition_satisfied(Claim) :-
    dispute_raised(Claim),
    arbitration_commenced_timely(Claim),
    arbitration_award_issued(Claim).

%% ============================================================================
%% Top level
%% ============================================================================
covered(Claim) :-
    policy_in_effect(Claim),
    qualifying_event(Claim),
    within_confinement_cap(Claim),
    confined_in_us(Claim),
    \+ excluded(Claim),
    arbitration_condition_satisfied(Claim).
