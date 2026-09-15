# Fact schema, RESTORED-fixture variant — Prolog transliteration

**Mechanically derived from `schema-restored.md`. Do not edit independently.**
Rule: neutral field `x` becomes `claim_x(C, Value)`. Enum values become atoms unchanged.
`none` becomes the atom `none`. Lists become Prolog lists of atoms.

## Claim facts

These will be defined for the claim `C` in any query. Use ALL OF, and ONLY, these.

```prolog
claim_agreement_signed(C, Value).                 % true | false
claim_premium_paid_month(C, Value).               % number | none
claim_hospitalization_month(C, Value).            % number
claim_hospitalization_ground(C, Value).           % sickness | accidental_injury | neither
claim_age_at_hospitalization(C, Value).           % number, years
claim_causes(C, Value).                           % list of: skydiving, military_service,
                                                  %          firefighting, police_service, other
claim_fraud_month(C, Value).                      % number | none
claim_misrepresentation_month(C, Value).          % number | none
claim_wellness_visit_month(C, Value).             % number | none
claim_wellness_visit_provider_qualified(C, Value).% true | false
claim_written_confirmation_month(C, Value).       % number | none
claim_dispute_arisen(C, Value).                   % true | false
claim_unable_to_settle_month(C, Value).           % number | none
claim_arbitration_commenced_month(C, Value).      % number | none
claim_valid_arbitration_award_issued(C, Value).   % true | false
claim_written_proof_of_claim_month(C, Value).     % number | none
claim_recovery_sought_month(C, Value).            % number | none
claim_policy_term_months(C, Value).               % number
claim_confined_in_us_hospital(C, Value).          % true | false
claim_continuous_confinement_days(C, Value).      % number | none
claim_claim_made_setting_out_basis(C, Value).     % true | false
```

## Supporting predicates (pre-defined — call them, do not redefine them)

```prolog
%! no_later_than(+EventMonth, +LimitMonth) is semidet.
%  True when EventMonth is a number =< LimitMonth. False when EventMonth is none.
no_later_than(none, _) :- !, fail.
no_later_than(M, Limit) :- number(M), M =< Limit.

%! arose_out_of(+Causes, +Cause) is semidet.
%  True when Cause is among the causes the event arose directly or indirectly out of.
arose_out_of(Causes, Cause) :- memberchk(Cause, Causes).
```

Write `covered(C)`, true exactly when a benefit is payable on claim `C`.
