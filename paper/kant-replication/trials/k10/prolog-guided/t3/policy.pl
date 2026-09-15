% policy.pl
%
% covered(C) — true exactly when a benefit is payable on claim C, per the
% CODEX INSURANCE LIMITED policy (inputs/chubb-policy.txt).

% ---------------------------------------------------------------------------
% Supporting predicates, reproduced verbatim from inputs/schema.md.
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% covered(C)
% ---------------------------------------------------------------------------

%! covered(+C) is semidet.
%  True exactly when a benefit is payable on claim C: the policy was in
%  effect at the time of the hospitalization (Sections 1.1-1.3), the
%  hospitalization is not caught by a general exclusion (Section 2.1), and
%  the procedural preconditions to Our liability under Section 3.2.1
%  (arbitration, and the wait before recovery may be sought) are met.
covered(C) :-
    policy_in_effect(C),
    covered_ground(C),
    not_excluded(C),
    arbitration_ok(C),
    recovery_ok(C).

% ---------------------------------------------------------------------------
% Sections 1.1-1.3 — the policy being "in effect"
% ---------------------------------------------------------------------------

%! policy_in_effect(+C) is semidet.
%  Section 1.1: the policy is in effect if it has been signed, the premium
%  has been paid, the Section 1.3 condition is pending or has been satisfied
%  in time, and the policy has not been canceled (Section 1.2: fraud,
%  misrepresentation, failure of Section 1.3, or expiry of the term).
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    section_1_3_ok(C),
    not_canceled_for_fraud(C),
    not_canceled_for_misrepresentation(C),
    within_policy_term(C).

%! premium_paid(+C) is semidet.
premium_paid(C) :-
    claim_premium_paid_month(C, Month),
    Month \== none.

%! not_canceled_for_fraud(+C) is semidet.
%  Section 1.2: cancelation is deemed to occur if there is fraud, at all.
not_canceled_for_fraud(C) :-
    claim_fraud_month(C, none).

%! not_canceled_for_misrepresentation(+C) is semidet.
%  Section 1.2: cancelation is deemed to occur if there is any
%  misrepresentation or material withholding, at all.
not_canceled_for_misrepresentation(C) :-
    claim_misrepresentation_month(C, none).

%! within_policy_term(+C) is semidet.
%  Sections 1.2 / 3.6: the policy is automatically canceled at the end of
%  the policy term, so the hospitalization must occur no later than that.
within_policy_term(C) :-
    claim_hospitalization_month(C, HospitalizationMonth),
    claim_policy_term_months(C, TermMonths),
    no_later_than(HospitalizationMonth, TermMonths).

%! section_1_3_ok(+C) is semidet.
%  Section 1.1(3): in effect if the Section 1.3 condition has either already
%  been satisfied in a timely fashion, or is "still pending" — i.e., as of
%  the hospitalization, its 7-month deadline has not yet passed. This mirrors
%  (and is the negation of) the Section 1.2 cancelation trigger "the
%  condition set out in Section 1.3 has not been satisfied in a timely
%  fashion".
section_1_3_ok(C) :-
    ( section_1_3_satisfied(C)
    ; section_1_3_pending(C)
    ).

%! section_1_3_satisfied(+C) is semidet.
%  Section 1.3: written confirmation, from a qualified medical provider, of
%  a wellness visit that itself occurred no later than the 6-month
%  anniversary, supplied no later than the 7-month anniversary of the
%  effective date.
section_1_3_satisfied(C) :-
    claim_wellness_visit_month(C, VisitMonth),
    claim_written_confirmation_month(C, ConfirmationMonth),
    claim_wellness_visit_provider_qualified(C, true),
    no_later_than(VisitMonth, 6),
    no_later_than(ConfirmationMonth, 7).

%! section_1_3_pending(+C) is semidet.
%  As of the hospitalization, the 7-month deadline for Section 1.3 has not
%  yet passed, so the condition is "still pending" rather than failed.
section_1_3_pending(C) :-
    claim_hospitalization_month(C, HospitalizationMonth),
    no_later_than(HospitalizationMonth, 7).

% ---------------------------------------------------------------------------
% Section 1.1 — hospitalization for sickness or accidental injury
% ---------------------------------------------------------------------------

%! covered_ground(+C) is semidet.
%  Section 1.1: payment is conditioned on the hospitalization being for
%  sickness or accidental injury. "neither" — e.g. a deliberate act that is
%  not itself a sickness — falls outside the insured event entirely.
covered_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ).

% ---------------------------------------------------------------------------
% Section 2.1 — general exclusions
% ---------------------------------------------------------------------------

%! not_excluded(+C) is semidet.
%  Section 2.1: the hospitalization must not arise directly or indirectly
%  out of skydiving, military service, firefighting, or police service, and
%  the claimant's age at hospitalization must be under 80.
not_excluded(C) :-
    claim_causes(C, Causes),
    \+ arose_out_of(Causes, skydiving),
    \+ arose_out_of(Causes, military_service),
    \+ arose_out_of(Causes, firefighting),
    \+ arose_out_of(Causes, police_service),
    claim_age_at_hospitalization(C, Age),
    Age < 80.

% ---------------------------------------------------------------------------
% Section 3.2.1 — arbitration as a condition precedent to liability
% ---------------------------------------------------------------------------

%! arbitration_ok(+C) is semidet.
%  Section 3.2.1: where a dispute or disagreement has arisen, arbitration
%  must be commenced within 3 months of the parties becoming unable to
%  settle (if that point has not yet been reached, the 3-month clock has not
%  started), and the issuance of a valid arbitration award is itself a
%  condition precedent to Our liability.
arbitration_ok(C) :-
    claim_dispute_arisen(C, Disputed),
    ( Disputed == true
    -> claim_valid_arbitration_award_issued(C, true),
       claim_unable_to_settle_month(C, UnableToSettleMonth),
       claim_arbitration_commenced_month(C, ArbitrationCommencedMonth),
       arbitration_timely(UnableToSettleMonth, ArbitrationCommencedMonth)
    ;  true
    ).

%! arbitration_timely(+UnableToSettleMonth, +ArbitrationCommencedMonth) is semidet.
arbitration_timely(none, _) :- !.
arbitration_timely(UnableToSettleMonth, ArbitrationCommencedMonth) :-
    number(UnableToSettleMonth),
    Limit is UnableToSettleMonth + 3,
    no_later_than(ArbitrationCommencedMonth, Limit).

% ---------------------------------------------------------------------------
% Section 3.2.1 — 60-day wait before recovery may be sought
% ---------------------------------------------------------------------------

%! recovery_ok(+C) is semidet.
%  Section 3.2.1: recovery may not be sought before the expiration of 60
%  days (taken here as 2 months, consistent with this schema's month-level
%  granularity) after written proof of claim has been submitted. If recovery
%  has not been sought at all, this bar is not in play.
recovery_ok(C) :-
    claim_recovery_sought_month(C, RecoverySoughtMonth),
    ( RecoverySoughtMonth == none
    -> true
    ;  claim_written_proof_of_claim_month(C, ProofOfClaimMonth),
       number(ProofOfClaimMonth),
       Limit is ProofOfClaimMonth + 2,
       RecoverySoughtMonth >= Limit
    ).
