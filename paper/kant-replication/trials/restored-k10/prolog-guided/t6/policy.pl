% policy.pl - Codex Insurance Limited hospital income policy, encoded as covered(C).
%
% covered(C) is true exactly when a benefit is payable on claim C. The rule
% structure mirrors the policy's own section numbering:
%
%   1.1-1.3  the policy must be in effect at the time of the hospitalization
%            (signed, premium paid, not canceled)
%   2.1-2.3  the benefit itself: a qualifying hospitalization, continuously
%            confined in a US hospital, with a claim made setting out its basis
%   3.1      general exclusions: enumerated causes, and age >= 80
%   4.2      arbitration, which only engages once a dispute has in fact arisen
%   4.2.1    the 60-day wait, after written proof of claim, before recovery
%            may be sought
%
% See NOTES.md for the judgement calls made while transliterating the prose.

% ---------------------------------------------------------------------------
% Supporting predicates (verbatim from inputs/schema.md - do not redefine)
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top level
% ---------------------------------------------------------------------------

covered(C) :-
    policy_in_effect(C),
    hospitalization_qualifies(C),
    \+ excluded(C),
    claim_made_ok(C),
    arbitration_ok(C),
    recovery_timing_ok(C).

% ---------------------------------------------------------------------------
% 1.1 / 1.2 / 1.3 - the policy must be in effect at the time of hospitalization
% ---------------------------------------------------------------------------

% 1.1: in effect when signed, the premium paid, and not canceled under 1.2.
% (1.1's own third limb -- the section-1.3 condition is "still pending or has
% been satisfied" -- is exactly the negation of the 1.3-failure cancellation
% ground in 1.2, so it is captured once, inside canceled/1, rather than twice.)
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    \+ canceled(C).

premium_paid(C) :-
    claim_premium_paid_month(C, M),
    number(M).

% 1.2: grounds for cancelation.
canceled(C) :- fraud_committed(C).
canceled(C) :- misrepresentation_made(C).
canceled(C) :- \+ section_1_3_ok(C).
canceled(C) :- term_expired(C).

fraud_committed(C) :-
    claim_fraud_month(C, M),
    number(M).

misrepresentation_made(C) :-
    claim_misrepresentation_month(C, M),
    number(M).

% The policy also automatically cancels at the end of the policy term (1.2,
% 4.6): a hospitalization falling after the term has run is not covered.
term_expired(C) :-
    claim_hospitalization_month(C, HM),
    claim_policy_term_months(C, Term),
    HM > Term.

% 1.3: no later than month 7, you must supply written confirmation -- from a
% qualified medical provider -- of a wellness visit that itself occurred no
% later than month 6. Before month 7 has elapsed (measured against the
% hospitalization, our only available clock) the condition is merely "still
% pending" under 1.1(3): it cannot yet have "not been satisfied in a timely
% fashion" under 1.2, so it only tells against the policy once the
% hospitalization falls after month 7 and the condition was in fact never
% properly met by then.
section_1_3_ok(C) :-
    claim_hospitalization_month(C, HM),
    HM =< 7.
section_1_3_ok(C) :-
    section_1_3_satisfied(C).

section_1_3_satisfied(C) :-
    claim_written_confirmation_month(C, WC),
    no_later_than(WC, 7),
    claim_wellness_visit_month(C, WV),
    no_later_than(WV, 6),
    claim_wellness_visit_provider_qualified(C, true).

% ---------------------------------------------------------------------------
% 2.1 / 2.2 - the benefit itself: a qualifying hospitalization
% ---------------------------------------------------------------------------

hospitalization_qualifies(C) :-
    qualifying_ground(C),
    claim_confined_in_us_hospital(C, true),
    claim_continuous_confinement_days(C, Days),
    number(Days),
    Days > 0.

qualifying_ground(C) :- claim_hospitalization_ground(C, sickness).
qualifying_ground(C) :- claim_hospitalization_ground(C, accidental_injury).

% ---------------------------------------------------------------------------
% 2.3 - a claim must be made setting out the basis for it
% ---------------------------------------------------------------------------

claim_made_ok(C) :-
    claim_claim_made_setting_out_basis(C, true).

% ---------------------------------------------------------------------------
% 3.1 - general exclusions
% ---------------------------------------------------------------------------

excluded(C) :-
    claim_causes(C, Causes),
    excluded_cause(Causes).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

excluded_cause(Causes) :- arose_out_of(Causes, skydiving).
excluded_cause(Causes) :- arose_out_of(Causes, military_service).
excluded_cause(Causes) :- arose_out_of(Causes, firefighting).
excluded_cause(Causes) :- arose_out_of(Causes, police_service).

% ---------------------------------------------------------------------------
% 4.2 - arbitration (only engages once a dispute has in fact arisen)
% ---------------------------------------------------------------------------

% No dispute at all, or a dispute that never reached an impasse (the parties
% settled it themselves), never triggers the arbitration machinery.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, none).
% Once the parties are unable to settle, arbitration must be commenced within
% three months of that date, and -- 4.2.1's final sentence -- a valid
% arbitration award is a condition precedent to Our liability.
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, UM),
    number(UM),
    Limit is UM + 3,
    claim_arbitration_commenced_month(C, AM),
    no_later_than(AM, Limit),
    claim_valid_arbitration_award_issued(C, true).

% ---------------------------------------------------------------------------
% 4.2.1 - the 60-day wait before recovery may be sought
% ---------------------------------------------------------------------------

% "In no case shall You seek to recover on this Policy before the expiration
% of sixty (60) days after written proof of claim has been submitted." Every
% other month-denominated fact in this schema is measured on the same axis,
% so the 60-day wait is taken as two (30-day) months.
recovery_timing_ok(C) :-
    claim_written_proof_of_claim_month(C, PM),
    number(PM),
    claim_recovery_sought_month(C, RM),
    number(RM),
    RM >= PM + 2.
