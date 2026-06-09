% Canonical PROLEG fixture: cancellation of a lease due to sublease.
% Source: Satoh et al., "PROLEG: An Implementation of the Presupposed Ultimate
% Fact Theory of Japanese Civil Code by PROLOG Technology", JURISIN 2010,
% Appendix A (rulebase + factbase). Japanese Civil Code Art. 612 + a Supreme
% Court case rule (1966.1.27, 20-1 Minsyu 136).
%
% Propositional (0-arity) dialect. Used as the Phase 2 anchor: PROLEG -> L4
% (Mode B) must produce an L4 program whose #EVAL agrees with this.

%=============================== rulebase ===============================

contract_end <= cancellation_due_to_sublease.
contract_end <= expiration_of_the_term_of_the_lease_contract.

cancellation_due_to_sublease <=
    agreement_of_lease_contract,
    handover_to_lessee,
    agreement_of_sublease_contract,
    handover_to_sublessee,
    using_leased_thing,
    manifestation_cancellation.

exception(cancellation_due_to_sublease, get_approval_of_sublease).
exception(cancellation_due_to_sublease, nonabuse_of_confidence).

get_approval_of_sublease <=
    approval_of_sublease,
    approval_before_cancellation.

nonabuse_of_confidence <= fact_of_nonabuse_of_confidence.

exception(nonabuse_of_confidence, abuse_of_confidence).
abuse_of_confidence <= fact_of_abuse_of_confidence.

expiration_of_the_term_of_the_lease_contract <=
    end_of_the_term_of_the_lease_contract,
    notice_of_renewal_refusal_between_12month_and_6month,
    justifiable_reason.

%=============================== factbase ===============================

admission(agreement_of_lease_contract, defendant).
admission(handover_to_lessee, defendant).
admission(agreement_of_sublease_contract, defendant).
admission(handover_to_sublessee, defendant).
admission(using_leased_thing, defendant).
admission(manifestation_cancellation, defendant).

allege(approval_of_sublease, defendant).
provide_evidence(approval_of_sublease, defendant).

allege(approval_before_cancellation, defendant).
provide_evidence(approval_before_cancellation, defendant).

allege(fact_of_nonabuse_of_confidence, defendant).
provide_evidence(fact_of_nonabuse_of_confidence, defendant).
plausible(fact_of_nonabuse_of_confidence).

allege(fact_of_abuse_of_confidence, plaintiff).
provide_evidence(fact_of_abuse_of_confidence, plaintiff).
plausible(fact_of_abuse_of_confidence).

% Expected judgement (from the paper's trace): plaintiff proves contract_end.
% The defendant's nonabuse_of_confidence defence is itself defeated by the
% plaintiff's abuse_of_confidence (exception-of-exception).
