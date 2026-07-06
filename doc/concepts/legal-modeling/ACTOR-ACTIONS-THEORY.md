# Actors, Actions, and Agency in L4 — Theory & Bibliography

A research-facing companion to the implementation spec
([DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md](../../../specs/todo/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md)).
It records the theoretical threads that surfaced while building value-level
actor agreement, so a paper can be extracted later. Citations are collected as
BibTeX in [`actor-actions.bib`](actor-actions.bib); keys are given inline as
`[@key]`.

The running example throughout: a contract `DEONTIC Actor Action`, actors
declared as values (`DECLARE Actor IS ONE OF Eater, Drinker`), actions as
records carrying their actor(s). The governing rule we implement: **a party may
only perform an action whose performer is itself**, where the performer is the
*first actor in positional order* (the "SVO subject-first canon").

---

## 1. The encoding choice: value-actors, and why it dissolved a subtyping wall

L4's regulative layer types contracts as `DEONTIC <PartyType> <ActionType>`
and reduces them against an event stream (a contract is a state machine;
HENCE/LEST are residuals; subject reduction requires each residual to keep the
contract's type). Two encodings of "who may do what" were on the table:

- **type-indexed actors** — an actor is a *type* (`Eater`), actions carry it as
  a phantom index (`Action Eater`), and agreement is a Hindley–Milner type
  equality [@MilnerPolymorphism; @PierceTAPL]. Clean, *but*: to let one contract
  route the ball between actors **and** ingest their events, the contract head
  must name one type while specific actions (`Action Eater`) inhabit a union
  slot (`Action Actor`) — which is covariant subtyping, and L4 deliberately has
  none. Reaching for existentials/GADTs [@XiGADT; @EisenbergDH] or refinement
  types [@VazouRefinement] is the "climbing the lambda cube" move, and the
  decade-long slow burn of *Dependent Haskell* / *LiquidHaskell* is the standing
  warning about its cost.

- **value-actors** — an actor is a *value* (a constructor of one `Actor` type),
  actions carry actors as ordinary record fields, and the contract head
  `DEONTIC Actor Action` is **monomorphic**. The head names one real type, so it
  drives mixed-actor events *natively* (the same machinery as a plain
  multi-party union contract). The subtyping wall simply isn't there.

The price of value-actors is that "a Drinker may not eat" is now a constraint on
*data*, not types, so it is a dedicated value-level well-formedness check rather
than a by-product of unification. **The contribution to claim is that this trade
is favourable**: a ~120-line value check buys what an XL type-system extension
was being contemplated for, and it composes with higher-order action operators
(§4) that an indexed encoding fights. The DX instinct ("just write
`PARTY Eater`") and the cheap implementation turned out to be the same insight.

---

## 2. The SVO subject-first canon, and "footguns as canon"

With actors as data, *which* field is the performer? When an action has one
actor field the answer is forced; when it has several — `SendMessage(from, to)`
— it is genuinely ambiguous. We resolve it by **convention**: the performer is
the **first actor in positional order**. This is deliberately order-dependent,
and that is the point — it makes `SendMessage` *duplex* (one type, both
directions; whoever sits in the first slot is the agent).

Two observations make this more than a hack:

1. **It mirrors word order.** `PARTY Alice MUST send Alice Bob` reads
   Subject–Verb–Object — "Alice sends Bob". Putting the agent first aligns the
   formal rule with the dominant English constituent order, so the rule is
   *predictable from the surface* rather than memorised. SVO and subject-first
   word-order are the cross-linguistic default [@GreenbergUniversals]. This is
   the same "the keyword *is* its meaning" win L4 gets from `OF` (application)
   and `'s` (possession).

2. **Canonising an ambiguity is what legal interpretation does.** Statutory
   construction is a catalogue of conventions that fix otherwise-ambiguous
   readings by fiat — the *last-antecedent rule* (a positional canon: a modifier
   binds the nearest noun), *ejusdem generis*, *expressio unius*
   [@ScaliaGarnerReadingLaw]. Each trades "learn the convention" for "the text
   is now determinate". The subject-first canon sits squarely in that tradition,
   with the advantage that it *matches* natural word order rather than fighting
   it. Discoverability is what converts a footgun into a canon: the diagnostic
   names the performer ("`eat` is performed by `Eater`, not by `Drinker`"), so
   the rule is taught exactly where it would be violated.

**Claim:** a positional agent-selection canon, grounded in SVO order and modelled
on legal interpretive canons, gives unambiguous, duplex-friendly agent
identification without any type-system machinery.

---

## 3. Prepositional logic: named parameters as thematic roles

L4 also constructs actions with *named* parameters
(`SendMessage WITH from IS Alice, to IS Bob, by IS Courier, under IS Seal`).
Read the field names aloud and they are **prepositions** — and prepositions are
the surface markers of **thematic roles** (agent, source, goal, instrument,
circumstance) in case grammar [@FillmoreCaseForCase; @DowtyProtoRoles;
@GruberStudies]. The pun ("prepositional" ← propositional/predicate logic)
names something real on two levels:

- **Each preposition is a binary predicate**: `from(e,Alice)`, `to(e,Bob)`,
  `by(e,Courier)`.
- **The named-parameter record is an event frame.** This is precisely
  **neo-Davidsonian event semantics** [@DavidsonActionSentences;
  @CastanedaComments; @ParsonsEvents]: a verb introduces an event variable and
  the participants attach as thematic-role predicates,
  `∃e. Send(e) ∧ from(e,Alice) ∧ to(e,Bob) ∧ by(e,Courier) ∧ under(e,Seal)`.

Positional (`OF`) and prepositional (`WITH`) construction are then **dual**
surface realisations of the same role assignment — exactly as English uses word
order for core arguments (subject/object) and prepositions for obliques.

A wrinkle the prepositions expose is pure law. In `from=Alice, by=Courier`,
linguistically "by" is the *agent* marker (passive: "sent **by** the courier"),
yet deontically Alice is the obligated principal and the courier her delegate.
So a role-keyed (rather than positional) performer rule would have to take a
stance on **principal vs. agent** — which is the bridge to §4.

**Claim (design direction, not yet implemented):** keying the performer to a
*role name* (`from`/subject for the principal, `by` reserved for the
instrument) generalises the positional canon to the prepositional surface, with
Fillmore's case roles as the justification rather than fiat.

---

## 4. Procurement: higher-order actions and the principal–agent distinction

Legal drafting routinely says "X undertakes to **procure** that Y performs
action_Y". This composes as `procure_X(action_Y)`: **procure is a higher-order
operator on actions** — `Action → Action`. We model it as a recursive action
type:

```l4
DECLARE Action IS ONE OF
  Perform HAS who      IS AN Actor, verb  IS A STRING
  Procure HAS procurer IS AN Actor, inner IS AN Action   -- wraps an Action
```

The SVO canon then binds the right party at each level **for free**: the outer
obligation `PARTY X MUST procure(action_Y)` binds the procurer X (the first
actor of `Procure`), while the inner action keeps its own performer Y shielded
as data. The result, type-checked:

- X may **procure** Y's act — accepted;
- a stranger Z may not procure *this* instance — rejected;
- X may not directly **perform** Y's act — rejected (only procure it).

This is the **principal/agent** distinction made structural, and it is the
formal counterpart of well-studied agency operators:

- **STIT logic** ("sees to it that") [@BelnapFacingFuture; @HortyAgency;
  @BelnapPerloffSeeing]: `procure_X(a) ≈ [X cstit][Y cstit] a` — nested agency.
- **"Bringing it about" / normative positions** [@PornActionTheory;
  @ElgesemAgency; @LindahlPositionChange; @KangerRights; @SergotNormative]:
  Kanger–Lindahl combine deontic and action (Do) operators precisely to type "X
  sees to it that Y sees to it that p".
- **Agency law** [@RestatementAgency]: the doctrine of when a principal is bound
  by an agent's acts. The sharp edge is **non-delegable duties** — obligations
  that *cannot* be discharged by procuring (personal service, certain fiduciary
  and statutory duties). These are encodable as a type stance: an obligation
  slot that admits a `Procure`-wrapped discharge is delegable; one that demands a
  bare `Perform` is non-delegable. The type system can say *"you must do this
  yourself."*

Procurement nests (`procure_X(procure_Y(act_Z))` — a delegation chain), and it
is composable **only because** value-actors make actions first-class values that
can be arguments to `Procure` — tying §4 back to §1.

**Claim:** higher-order action operators give a typed account of procurement /
delegation / non-delegable duties that is standard in agency logic but, to our
knowledge, novel as a *typed regulative-language* construct that falls out of
the value-actor encoding without bespoke modal machinery.

---

## 5. Deontic and contracts-as-code context

This work sits inside L4's broader deontic layer (obligation/permission/
prohibition with deadlines and residuation), whose lineage runs from von Wright
[@vonWrightDeontic] through the reduction/dynamic-logic treatments
[@AndersonReduction; @MeyerDynamic] that also ground the separate *bounded
deontics* work ([BOUNDED-DEONTICS-SPEC.md](../../../specs/todo/BOUNDED-DEONTICS-SPEC.md)). As a
programming language for contracts it is kin to the formal-contract-language
tradition [@LeeElectronic; @AndersenCompositional; @HvitvedContracts;
@PrisacariuSchneiderCL; @GovernatoriContracts], but distinguished by being a
typed CNL whose *type checker* — not a separate logic — enforces who-may-do-what.

---

## 6. Paper-extractable contributions (draft)

1. **Value-actor encoding** dissolves the subtyping/existential wall that an
   actor-correct, event-driving, multi-actor regulative contract appears to
   require — a favourable trade of one value-level check for an XL type feature.
2. **SVO subject-first canon** for positional agent identification: unambiguous,
   duplex-enabling, grounded in word-order universals and legal interpretive
   canons; "footgun as canon" with discoverability as the converting condition.
3. **Positional ⊕ prepositional duality**: action construction as
   neo-Davidsonian event frames; named parameters as thematic-role predicates.
4. **Higher-order procurement**: a typed account of principal/agent, delegation
   chains, and non-delegable duties as ordinary recursive actions — free under
   the value-actor encoding.

Target venues per the L4 papers series: ICAIL (intro/tooling), JURIX (the
agency/procurement theory), a CNL workshop (the prepositional/SVO surface, with
Adam Wyner). Cross-reference the Poh Yuan Nie worked example for the
"detect ≠ resolve" framing where relevant.
