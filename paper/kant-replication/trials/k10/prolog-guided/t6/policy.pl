% policy.pl -- CODEX INSURANCE LIMITED policy, encoded as covered(C).
%
% covered(C) succeeds exactly when a benefit is payable on claim C, i.e. when
% every requirement of Section 1 (policy in effect), Section 2 (general
% exclusions) and Section 3 (general conditions) is met, using only the
% claim_* facts that will be supplied for C and the two supporting
% predicates below.
%
% No claim facts are defined in this file (see queries.pl for those).

% ---------------------------------------------------------------------------
% Supporting predicates (copied verbatim from bench/schema-prolog.md).
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Section 1.1 / 1.2 / 1.3 -- policy in effect at the time of hospitalization.
% ---------------------------------------------------------------------------

%! premium_paid(+C) is semidet.
%  1.1(2): the applicable premium has been paid (a month value is on record).
premium_paid(C) :-
    claim_premium_paid_month(C, M),
    number(M).

%! valid_hospitalization_ground(+C) is semidet.
%  1.1: the claim must be premised on hospitalization for sickness or
%  accidental injury; "neither" is not a valid basis for a claim at all.
valid_hospitalization_ground(C) :- claim_hospitalization_ground(C, sickness).
valid_hospitalization_ground(C) :- claim_hospitalization_ground(C, accidental_injury).

%! wellness_condition_ok(+C) is semidet.
%  1.1(3) together with 1.3: the policy is in effect (as far as this
%  condition is concerned) if, as of the hospitalization, the condition in
%  1.3 is "still pending" -- the 7th-month-anniversary deadline has not yet
%  arrived, so nothing has yet failed and an earlier, validly-covered
%  hospitalization cannot be retroactively un-covered by a later lapse --
%  or if it "has been satisfied in a timely fashion": written confirmation
%  of a wellness visit with a qualified medical provider, the visit itself
%  having occurred no later than the 6th month anniversary and the
%  confirmation having been supplied no later than the 7th.
wellness_condition_ok(C) :-
    claim_hospitalization_month(C, HospM),
    no_later_than(HospM, 7).
wellness_condition_ok(C) :-
    claim_written_confirmation_month(C, ConfirmM),
    no_later_than(ConfirmM, 7),
    claim_wellness_visit_month(C, VisitM),
    no_later_than(VisitM, 6),
    claim_wellness_visit_provider_qualified(C, true).

%! within_policy_term(+C) is semidet.
%  1.2: the policy "will also be automatically canceled at midnight ... on
%  the last day of the policy term described in Section 5" -- so the
%  hospitalization must occur no later than the last month of the term.
within_policy_term(C) :-
    claim_hospitalization_month(C, HospM),
    claim_policy_term_months(C, TermM),
    no_later_than(HospM, TermM).

%! fraud_occurred(+C) is semidet.
%  1.2: cancelation is deemed to occur "if there is fraud" -- any recorded
%  month value (as opposed to none) means fraud occurred.
fraud_occurred(C) :-
    claim_fraud_month(C, M),
    number(M).

%! misrepresentation_occurred(+C) is semidet.
%  1.2: cancelation is likewise deemed to occur for "any misrepresentation
%  or material withholding of any information".
misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, M),
    number(M).

% ---------------------------------------------------------------------------
% Section 2.1 -- general exclusions.
% ---------------------------------------------------------------------------

%! excluded_by_cause(+C) is semidet.
%  2.1(1)-(4): no benefit is paid for sickness or injury arising directly or
%  indirectly out of skydiving, military service, firefighting or police
%  service.
excluded_by_cause(C) :- claim_causes(C, Causes), arose_out_of(Causes, skydiving).
excluded_by_cause(C) :- claim_causes(C, Causes), arose_out_of(Causes, military_service).
excluded_by_cause(C) :- claim_causes(C, Causes), arose_out_of(Causes, firefighting).
excluded_by_cause(C) :- claim_causes(C, Causes), arose_out_of(Causes, police_service).

%! excluded_by_age(+C) is semidet.
%  2.1(5): excluded if age at the time of hospitalization is >= 80.
excluded_by_age(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% ---------------------------------------------------------------------------
% Section 3.2 -- arbitration and proof-of-claim conditions.
% ---------------------------------------------------------------------------

%! arbitration_ok(+C) is semidet.
%  3.2.1: where a dispute has arisen, arbitration must be commenced within
%  three months of the parties becoming unable to settle it (on pain of the
%  claim being "extinguished completely"), and the issuance of a valid
%  arbitration award is "a condition precedent to our liability". Where no
%  dispute has arisen, none of this machinery is triggered.
arbitration_ok(C) :-
    claim_dispute_arisen(C, false).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_valid_arbitration_award_issued(C, true),
    claim_unable_to_settle_month(C, none).
arbitration_ok(C) :-
    claim_dispute_arisen(C, true),
    claim_valid_arbitration_award_issued(C, true),
    claim_unable_to_settle_month(C, UnableM),
    number(UnableM),
    claim_arbitration_commenced_month(C, ArbM),
    Limit is UnableM + 3,
    no_later_than(ArbM, Limit).

%! no_premature_recovery(+C) is semidet.
%  3.2.1: "In no case shall You seek to recover on this Policy before the
%  expiration of sixty (60) days after written proof of claim has been
%  submitted" -- modeled here as two months, since the fact schema only
%  supplies month-granularity facts.
no_premature_recovery(C) :-
    claim_recovery_sought_month(C, none).
no_premature_recovery(C) :-
    claim_recovery_sought_month(C, RecoverM),
    number(RecoverM),
    claim_written_proof_of_claim_month(C, ProofM),
    number(ProofM),
    Limit is ProofM + 2,
    RecoverM >= Limit.

% ---------------------------------------------------------------------------
% Top-level rule.
% ---------------------------------------------------------------------------

%! covered(?C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    claim_agreement_signed(C, true),
    premium_paid(C),
    valid_hospitalization_ground(C),
    \+ excluded_by_cause(C),
    \+ excluded_by_age(C),
    \+ fraud_occurred(C),
    \+ misrepresentation_occurred(C),
    wellness_condition_ok(C),
    within_policy_term(C),
    arbitration_ok(C),
    no_premature_recovery(C).
