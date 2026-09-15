% policy.pl
%
% Encodes the CODEX INSURANCE LIMITED policy (POLICY IN EFFECT AND CONDITIONS /
% GENERAL EXCLUSIONS / GENERAL CONDITIONS) as covered(C): true exactly when a
% benefit is payable on claim C.
%
% This file defines no claim facts of its own. It expects claim_*/2 facts for
% the claim(s) in question to be supplied elsewhere (see queries.pl), using the
% vocabulary in schema.md. Section numbers in comments refer to chubb-policy.txt.

% ---------------------------------------------------------------------------
% Supporting predicates, reproduced verbatim from schema.md.
% ---------------------------------------------------------------------------

%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).

% ---------------------------------------------------------------------------
% Top-level rule.
% ---------------------------------------------------------------------------

%! covered(+C) is semidet.
%  True exactly when a benefit is payable on claim C.
covered(C) :-
    in_effect(C),
    valid_hospitalization_ground(C),
    \+ excluded_cause(C),
    \+ age_excluded(C),
    arbitration_condition_met(C),
    recovery_timing_ok(C).

% ---------------------------------------------------------------------------
% 1.1 / 1.2 / 1.3 - the policy being "in effect" at the time of hospitalization.
% ---------------------------------------------------------------------------

%  1.1: the policy is in effect if (1) the agreement is signed, (2) the premium
%  has been paid, (3) the 1.3 wellness-visit condition is still pending or has
%  been satisfied in a timely fashion, and (4) the policy has not been canceled.
%  1.2 defines cancelation as arising from fraud, misrepresentation or material
%  withholding, failure to satisfy 1.3 in time, or the policy term (Section 5 /
%  3.6) having ended. Failure of 1.3 is already checked directly as requirement
%  (3) below, so not_canceled_other/1 only re-checks the remaining grounds
%  (fraud, misrepresentation, term end) rather than encoding 1.3 a second time.
in_effect(C) :-
    agreement_signed(C),
    premium_paid(C),
    wellness_visit_condition_ok(C),
    not_canceled_other(C).

agreement_signed(C) :-
    claim_agreement_signed(C, true).

premium_paid(C) :-
    claim_premium_paid_month(C, PaidMonth),
    number(PaidMonth).

%  1.3: no later than the 7th month anniversary of the effective date, you
%  supply written confirmation (from the medical provider) of a wellness visit
%  with a qualified medical provider, that visit itself having occurred no
%  later than the 6th month anniversary. 1.1(3) allows this to instead be
%  "still pending": if the hospitalization itself happens no later than the
%  7th month anniversary, the deadline for supplying confirmation has not yet
%  passed, so the condition has not yet been failed either.
wellness_visit_condition_ok(C) :-
    claim_hospitalization_month(C, HospMonth),
    ( no_later_than(HospMonth, 7)
    -> true
    ;   claim_written_confirmation_month(C, ConfirmMonth),
        no_later_than(ConfirmMonth, 7),
        claim_wellness_visit_month(C, VisitMonth),
        no_later_than(VisitMonth, 6),
        claim_wellness_visit_provider_qualified(C, true)
    ).

not_canceled_other(C) :-
    \+ fraud_occurred(C),
    \+ misrepresentation_occurred(C),
    within_policy_term(C).

%  1.2: cancelation on fraud "in connection with any communication or
%  information relating to this policy" is not itself limited to a time
%  window (unlike the 1.3 deadlines above), so any fraud, at any month, is
%  treated as fatal to coverage.
fraud_occurred(C) :-
    claim_fraud_month(C, FraudMonth),
    number(FraudMonth).

%  Likewise for misrepresentation or material withholding of information;
%  the schema gives no separate fact for "material withholding", so
%  claim_misrepresentation_month is read as covering both grounds.
misrepresentation_occurred(C) :-
    claim_misrepresentation_month(C, MisrepMonth),
    number(MisrepMonth).

%  1.2 / 3.6: "automatically canceled at midnight ... on the last day of the
%  policy term", the term itself running for claim_policy_term_months(C, _)
%  months from the effective date (Section 5 / 3.6).
within_policy_term(C) :-
    claim_hospitalization_month(C, HospMonth),
    claim_policy_term_months(C, TermMonths),
    no_later_than(HospMonth, TermMonths).

% ---------------------------------------------------------------------------
% 1.1 preamble - the hospitalization must actually be for sickness or
% accidental injury; a hospitalization for neither is not the kind of event
% this policy pays a benefit on at all.
% ---------------------------------------------------------------------------

valid_hospitalization_ground(C) :-
    claim_hospitalization_ground(C, Ground),
    ( Ground == sickness
    ; Ground == accidental_injury
    ).

% ---------------------------------------------------------------------------
% 2.1 - General exclusions.
% ---------------------------------------------------------------------------

%  Items 1-4: no benefit for sickness or accidental injury arising directly or
%  indirectly out of skydiving, military service, firefighting, or police
%  service.
excluded_cause(C) :-
    claim_causes(C, Causes),
    ( arose_out_of(Causes, skydiving)
    ; arose_out_of(Causes, military_service)
    ; arose_out_of(Causes, firefighting)
    ; arose_out_of(Causes, police_service)
    ).

%  Item 5: age at the time of hospitalization equal to or greater than 80.
age_excluded(C) :-
    claim_age_at_hospitalization(C, Age),
    Age >= 80.

% ---------------------------------------------------------------------------
% 3.2.1 - Arbitration.
% ---------------------------------------------------------------------------

%  If a dispute or disagreement has arisen: arbitration must be (or must
%  remain timely to be) commenced, and the issuance of a valid arbitration
%  award is a condition precedent to Our liability. Where no dispute has
%  arisen, this clause imposes nothing.
arbitration_condition_met(C) :-
    claim_dispute_arisen(C, Disputed),
    ( Disputed == true
    -> arbitration_timely(C),
       claim_valid_arbitration_award_issued(C, true)
    ;   true
    ).

%  Arbitration must be commenced within three months of the day the parties
%  became unable to settle the dispute. If that day has not yet arrived
%  (claim_unable_to_settle_month is none), the three-month clock has not
%  started, so nothing has yet been forfeited under this clause.
arbitration_timely(C) :-
    claim_unable_to_settle_month(C, UnableMonth),
    ( UnableMonth == none
    -> true
    ;   claim_arbitration_commenced_month(C, CommencedMonth),
        Deadline is UnableMonth + 3,
        no_later_than(CommencedMonth, Deadline)
    ).

%  "In no case shall You seek to recover on this Policy before the expiration
%  of sixty (60) days after written proof of claim has been submitted to Us"
%  - unconditional, unlike the rest of 3.2.1 (it is not phrased as contingent
%  on a dispute having arisen). Sixty days is treated as two 30-day months,
%  the unit every other date in this schema is already expressed in.
recovery_timing_ok(C) :-
    claim_written_proof_of_claim_month(C, ProofMonth),
    claim_recovery_sought_month(C, RecoveryMonth),
    number(ProofMonth),
    number(RecoveryMonth),
    RecoveryMonth >= ProofMonth + 2.
