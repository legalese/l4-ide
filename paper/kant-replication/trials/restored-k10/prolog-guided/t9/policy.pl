% policy.pl
%
% CODEX INSURANCE LIMITED hospital indemnity policy, encoded as a Prolog rule
% covered(C), true exactly when a benefit is payable on claim C.
%
% Section references (SS1-SS5) are to fixtures/chubb-policy.txt.
% This file contains no claim facts; those are supplied by whatever file
% defines claim_*/2 for the claim(s) in question (see queries.pl).

%% ---------------------------------------------------------------------
%% Supporting predicates (verbatim from bench/schema-prolog.md)
%% ---------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

%% ---------------------------------------------------------------------
%% Top-level rule
%% ---------------------------------------------------------------------

% SS2.1-2.3: a benefit is payable on claim C iff the policy is in effect at the
% time of hospitalization, the hospitalization was for sickness or accidental
% injury, no SS3 exclusion applies, the confinement was in a US hospital for at
% least one continuous day, a claim was properly made, and (SS4.2) any dispute
% was properly taken through arbitration and recovery was not sought too early.
covered(C) :-
    policy_in_effect(C),
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ),
    \+ excluded(C),
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    number(Days), Days > 0,
    claim_claim_made_setting_out_basis(C, true),
    dispute_resolution_ok(C).

%% ---------------------------------------------------------------------
%% SS1: Policy in effect and conditions
%% ---------------------------------------------------------------------

% SS1.1: the policy is in effect at the time of hospitalization iff the
% agreement is signed, the premium has been paid, and the policy has not
% been canceled. (Item 3 of SS1.1 -- the SS1.3 condition being "still
% pending or ... satisfied in a timely fashion" -- is the negation of one
% of the SS1.2 cancelation triggers, so it is folded into canceled/1 below
% rather than checked twice.)
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    claim_premium_paid_month(C, PaidMonth),
    PaidMonth \= none,
    \+ canceled(C).

% SS1.2: cancelation triggers.
canceled(C) :-
    claim_fraud_month(C, FraudMonth),
    FraudMonth \= none.
canceled(C) :-
    claim_misrepresentation_month(C, MisrepMonth),
    MisrepMonth \= none.
canceled(C) :-
    \+ condition_1_3_ok(C).
canceled(C) :-
    term_expired(C).

% SS1.2 last sentence, read with SS4.6: the policy automatically cancels at
% the end of the (one-year) policy term, so a hospitalization after that
% month falls outside the term.
term_expired(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_policy_term_months(C, TermMonths),
    \+ no_later_than(HospMonth, TermMonths).

% SS1.3: no later than month 7, written confirmation of a wellness visit
% (with a qualified medical provider) that itself occurred no later than
% month 6. SS1.1 item 3 allows this to be either already satisfied, or
% "still pending" as of the hospitalization month -- i.e. the relevant
% deadline has not yet passed, so the condition cannot yet be said to have
% failed. A visit or confirmation that already happened, but late, cannot
% be rescued by "pending": lateness is a fact, not a matter of the clock
% not having run out yet.
condition_1_3_ok(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_wellness_visit_month(C, VisitMonth),
    visit_ok_or_pending(C, VisitMonth, HospMonth),
    claim_written_confirmation_month(C, ConfMonth),
    confirmation_ok_or_pending(ConfMonth, HospMonth).

visit_ok_or_pending(_, none, HospMonth) :-
    !,
    no_later_than(HospMonth, 6).
visit_ok_or_pending(C, VisitMonth, _HospMonth) :-
    no_later_than(VisitMonth, 6),
    claim_wellness_visit_provider_qualified(C, true).

confirmation_ok_or_pending(none, HospMonth) :-
    !,
    no_later_than(HospMonth, 7).
confirmation_ok_or_pending(ConfMonth, _HospMonth) :-
    no_later_than(ConfMonth, 7).

%% ---------------------------------------------------------------------
%% SS3: General exclusions
%% ---------------------------------------------------------------------

% SS3.1 items 1-4: causal exclusions -- the hospitalization must have arisen
% (directly or indirectly) out of one of these activities, not merely have
% occurred while the claimant happened to hold some status (e.g. being a
% police officer generally, as opposed to the injury arising out of police
% service specifically).
excluded(C) :-
    claim_causes(C, Causes),
    ( arose_out_of(Causes, skydiving)
    ; arose_out_of(Causes, military_service)
    ; arose_out_of(Causes, firefighting)
    ; arose_out_of(Causes, police_service)
    ).
% SS3.1 item 5: age exclusion.
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

%% ---------------------------------------------------------------------
%% SS4.2: Arbitration / dispute resolution
%% ---------------------------------------------------------------------

% SS4.2.1: if a dispute has arisen, a valid arbitration award is a condition
% precedent to liability, and arbitration must have been commenced within
% three months of the parties becoming unable to settle (once that has
% happened; the three-month clock has not yet started if it has not).
dispute_resolution_ok(C) :-
    claim_dispute_arisen(C, Dispute),
    ( Dispute == true
    -> claim_valid_arbitration_award_issued(C, true),
       arbitration_timely(C)
    ;  true
    ),
    recovery_not_premature(C).

arbitration_timely(C) :-
    claim_unable_to_settle_month(C, UnableMonth),
    ( UnableMonth == none
    -> true
    ;  claim_arbitration_commenced_month(C, CommencedMonth),
       Limit is UnableMonth + 3,
       no_later_than(CommencedMonth, Limit)
    ).

% SS4.2.1 last sentence: in no case may recovery be sought before the
% expiration of sixty (60) days -- taken here as two months, consistent
% with the month-anniversary granularity used throughout the policy -- after
% written proof of claim was submitted.
recovery_not_premature(C) :-
    claim_recovery_sought_month(C, RecoveryMonth),
    ( RecoveryMonth == none
    -> true
    ;  claim_written_proof_of_claim_month(C, ProofMonth),
       ProofMonth \= none,
       RecoveryMonth >= ProofMonth + 2
    ).
