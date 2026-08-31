% policy.pl
%
% Encoding of the CODEX INSURANCE LIMITED accident/health policy
% (inputs/chubb-policy.txt). covered(C) succeeds exactly when a benefit
% is payable on claim C. No claim facts are defined in this file; it is
% loaded together with a file (e.g. queries.pl) that supplies all 18
% claim_* facts for each claim it names.

% ---------------------------------------------------------------------
% Supporting predicates, copied verbatim from bench/schema-prolog.md.
% Do not redefine or call anything else in their place.
% ---------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------
% Top-level rule.
% ---------------------------------------------------------------------

%! covered(?C) is semidet.
%  True when a benefit is payable on claim C: the claim is premised on a
%  covered hospitalization (Sec. 1.1), the policy is in effect at the
%  time of that hospitalization (Sec. 1.1-1.3), no general exclusion
%  applies (Sec. 2.1), and the arbitration/recovery-timing preconditions
%  to liability are met (Sec. 3.2).
covered(C) :-
    has_insurable_ground(C),
    policy_in_effect(C),
    \+ excluded(C),
    arbitration_ok(C),
    recovery_timing_ok(C).

% Sec. 1.1: "the payment of any benefit under this policy is conditioned
% on the policy being in effect at the time of the hospitalization for
% sickness or accidental injury on which the claim ... is premised."
% A hospitalization whose ground is neither sickness nor accidental
% injury has no basis for a benefit at all, independent of everything
% else.
has_insurable_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness ; Ground == accidental_injury ).

% ---------------------------------------------------------------------
% Sec. 1.1-1.3: the policy must be "in effect" at the time of the
% hospitalization.
% ---------------------------------------------------------------------

%  Sec. 1.1 lists four cumulative requirements for the policy to be in
%  effect: (1) the agreement is signed, (2) the premium has been paid,
%  (3) the Sec. 1.3 wellness-visit condition is still pending or has
%  been satisfied in a timely fashion, and (4) the policy has not been
%  canceled. Cancelation (Sec. 1.2) happens on fraud/misrepresentation
%  or at the end of the policy term; both are checked here as of the
%  hospitalization date, consistent with "in effect at the time of the
%  hospitalization".
policy_in_effect(C) :-
    claim_agreement_signed(C, true),
    claim_premium_paid_month(C, PremiumMonth),
    PremiumMonth \== none,
    condition_1_3_ok(C),
    \+ fraud_or_misrepresentation_before_hospitalization(C),
    within_policy_term(C).

%  Sec. 1.3's own condition is compound: written confirmation of a
%  wellness visit, supplied no later than the 7th month anniversary, of
%  a visit (with a qualified provider) occurring no later than the 6th
%  month anniversary. Sec. 1.1(3) allows the claim through either when
%  that compound condition has actually been satisfied in a timely
%  fashion, or when it is merely "still pending" -- i.e. the 7-month
%  deadline has not yet arrived as of the hospitalization date. See
%  NOTES.md for the exact boundary chosen.
condition_1_3_ok(C) :-
    condition_1_3_satisfied(C).
condition_1_3_ok(C) :-
    \+ condition_1_3_satisfied(C),
    claim_hospitalization_month(C, HospMonth),
    HospMonth < 7.

condition_1_3_satisfied(C) :-
    claim_written_confirmation_month(C, ConfirmMonth),
    no_later_than(ConfirmMonth, 7),
    claim_wellness_visit_month(C, VisitMonth),
    no_later_than(VisitMonth, 6),
    claim_wellness_visit_provider_qualified(C, true).

%  Sec. 1.2: cancelation is deemed to occur on fraud, misrepresentation,
%  or material withholding of information (the schema gives no separate
%  fact for "material withholding"; it is treated as covered by
%  claim_misrepresentation_month -- see NOTES.md). Only fraud or
%  misrepresentation occurring at or before the hospitalization can have
%  canceled the policy by the time of that hospitalization.
fraud_or_misrepresentation_before_hospitalization(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_fraud_month(C, FraudMonth),
    no_later_than(FraudMonth, HospMonth).
fraud_or_misrepresentation_before_hospitalization(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_misrepresentation_month(C, MisrepMonth),
    no_later_than(MisrepMonth, HospMonth).

%  Sec. 1.2 last sentence / Sec. 3.6: the policy is automatically
%  canceled at the end of the policy term, so the hospitalization must
%  fall no later than that many months in.
within_policy_term(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_policy_term_months(C, TermMonths),
    no_later_than(HospMonth, TermMonths).

% ---------------------------------------------------------------------
% Sec. 2.1: general exclusions.
% ---------------------------------------------------------------------

%  "Your policy will not apply to ... any event ... arising directly or
%  indirectly out of" one of four listed causes, or if the claimant's
%  age at the time of hospitalization is 80 or older.
excluded(C) :-
    claim_causes(C, Causes),
    excluded_cause(Cause),
    arose_out_of(Causes, Cause).
excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

excluded_cause(skydiving).
excluded_cause(military_service).
excluded_cause(firefighting).
excluded_cause(police_service).

% ---------------------------------------------------------------------
% Sec. 3.2: arbitration.
% ---------------------------------------------------------------------

%  If no dispute has arisen, the arbitration clause imposes no further
%  precondition. If a dispute has arisen, arbitration must have been
%  commenced within three months of the parties becoming unable to
%  settle, and the issuance of a valid arbitration award is "a
%  condition precedent to our liability under this Policy".
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_unable_to_settle_month(C, UnableToSettleMonth),
    number(UnableToSettleMonth),
    claim_arbitration_commenced_month(C, ArbitrationMonth),
    no_later_than(ArbitrationMonth, UnableToSettleMonth + 3),
    claim_valid_arbitration_award_issued(C, true).

% ---------------------------------------------------------------------
% Sec. 3.2 final sentence: "In no case shall You seek to recover on this
% Policy before the expiration of sixty (60) days after written proof of
% claim has been submitted." 60 days is treated as 2 months (see
% NOTES.md for the unit judgement call).
% ---------------------------------------------------------------------

recovery_timing_ok(C) :-
    claim_written_proof_of_claim_month(C, ProofMonth),
    number(ProofMonth),
    claim_recovery_sought_month(C, RecoveryMonth),
    number(RecoveryMonth),
    RecoveryMonth >= ProofMonth + 2.
