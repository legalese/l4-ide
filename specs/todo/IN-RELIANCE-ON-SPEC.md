> **Status (audited 2026-08-09):** OPEN — analysis-only. Nothing proposed here is implemented, and
> no ruling below is decided; §9's rulings are all PROPOSED, awaiting a decision.
>
> - There is no reliance primitive anywhere in core: no keyword, no AST node, no evaluator or trace
>   record of "the rule an actor relied on". The evaluation trace records which expressions were
>   entered and exited (`jl4-core/src/L4/EvaluateLazy/Trace.hs:87-88`), which is _consultation_
>   evidence at best — see §3.
> - What DOES exist, and is load-bearing for the analysis: the event-sourced ledger with
>   `RECORD`/`COMMIT`/`ATTEST` writes and `RECALL`/`RECALL ALL` reads
>   (`jl4-core/src/L4/Evaluate/Ledger.hs`, `specs/done/STATE-AS-LEDGER-SPEC.md`); bitemporal
>   tx/vt provenance stamps (`Ledger.hs:65-90`); per-party + official ledgers (`Ledger.hs:234-262`);
>   and the temporal rule-version axis (`EVAL UNDER RULES EFFECTIVE AT`,
>   `jl4-core/src/L4/EvaluateLazy/Machine.hs:189-190`, `:829-832`).
> - `ATTEST` is today a pure synonym of `COMMIT` (`specs/done/STATE-AS-LEDGER-SPEC.md:50`); §4.2
>   argues reliance is the first job that would give it a semantics of its own.
> - The Reg CF corpus models reliance as **uninterpreted party-supplied inputs** — fields whose
>   names quote the phrase this spec is trying to define
>   (`jl4/examples/legal/regcf/denovo/regcf-denovo.l4:739`, `:751-752`, `:755`). §2.1 treats that as
>   the honest degraded mode, not the answer.
> - No build was run for this analysis (§9's sketch is checked against the grammar on paper, not
>   executed).
> - §7.1 (added 2026-08-09, same day) quotes 15 U.S.C. 77d(a)(6)(B)(i), which is **not in the
>   source bundle** — `source/` holds Part 227 plus two CFR reference files — so that quotation
>   is supplied, not tree-verified; §7.1's repo claims (the strict `max` encoding, the blocked
>   four-state model, the wizard's demand-driven policy) are cited to the tree.

# "IN RELIANCE ON": Provenance-of-Act Semantics for L4

**Status:** Draft — analysis and proposed rulings only
**Author:** Research compilation for L4 language design
**Date:** 2026-08-09
**Neighbour:** `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` (override semantics; this spec follows its
conventions and cites its taxonomy)
**Motivating corpus:** the Reg CF de novo encoding,
`jl4/examples/legal/regcf/denovo/regcf-denovo.l4`

---

## 1. Introduction

### 1.1 The motivating text

17 CFR 227.100(a)(1), verbatim
(`jl4/examples/legal/regcf/denovo/source/part227.txt:102`):

> The aggregate amount of securities sold to all investors by the issuer **in reliance on section
> 4(a)(6) of the Securities Act (15 U.S.C. 77d(a)(6))** during the 12-month period preceding the
> date of such offer or sale, including the securities offered in such transaction, shall not
> exceed $5,000,000

The phrase is not decoration. "in reliance on" occurs **51 times** in `part227.txt` and is the
predicate on which the whole Part pivots: it gates the exemption itself (`part227.txt:100`), both
aggregate caps (`:102`, `:104`), issuer eligibility (`:130`, `:132`), the disclosure and Form C
filing duties (`:158`, `:358`), the ongoing-report duty (`:328`), its termination (`:346`),
advertising limits (`:386`), and resale restrictions (`:569`). Whether an issuer may sell, what it
must file, what it must keep filing, and what its investors may resell all turn on which _past
acts_ were "in reliance on section 4(a)(6)".

### 1.2 The question

Meng's framing, which this spec exists to answer:

> Basically how do we know if a certain action was taken in reliance on some decision logic.

"The purchaser is over 18" is a predicate over the world: given the facts, a reasoner evaluates
it. "This sale was in reliance on section 4(a)(6)" is not that kind of predicate. Two sales of
identical securities, on identical terms, to identical purchasers, on the same day, can differ on
it — and nothing observable in either transaction distinguishes them. The predicate is about the
**provenance of the act**: which legal rule the actor was invoking when it acted.

Notice what follows for §227.100(a)(1). The $5,000,000 cap aggregates only over sales that were
"in reliance on" 4(a)(6), so an issuer's remaining headroom is a function of **its own past
intentions** — and a mis-answer flips the availability of the exemption. A sale wrongly counted
in deflates headroom and blocks a lawful offering; a sale wrongly counted out inflates headroom,
the cap is exceeded, the exemption fails, and every sale in the offering becomes an unregistered
sale. _(Reasoning from doctrine, not from the tree: an unregistered non-exempt sale violates
Securities Act §5 and carries a §12(a)(1) rescission right — strict liability. The exemption
claimant bears the burden of proving the exemption, per SEC v. Ralston Purina Co., 346 U.S. 119
(1953). Neither proposition is verified against any repo artifact.)_

### 1.3 The thesis in one paragraph

Reliance is a **declaration, not an assertion**. An assertion ("purchaser is over 18") has
word-to-world direction of fit: the reasoner checks the words against the world. A declaration
("I hereby rely on section 4(a)(6)") makes itself true by being properly performed in the right
institutional setting — Austin's performative, Searle's declaration, flagged here as reasoning
from the speech-act literature. A formal language can _evaluate_ assertions; it can only _record_
declarations. So "in reliance on" cannot be a derived fact in L4. It must be an **event on the
ledger**: a dated, party-attributed, rule-citing act. L4's ledger substrate
(`specs/done/STATE-AS-LEDGER-SPEC.md`) already has the machinery for exactly this — §4 does the
inventory — and §9 shows the whole design is expressible today as a schema convention over
`ATTEST` + `RECALL ALL`, with three identified gaps.

---

## 2. Candidate semantics: what kind of thing is reliance?

Five candidates, ordered from cheapest to most structured. The corpus currently implements the
first; this spec proposes the fourth, with the fifth as its institutional special case.

### 2.1 An uninterpreted fact supplied by the party (the status quo)

The Reg CF encoding punts the predicate into the fact schema. The issuer supplies:

```l4
`has sold securities in reliance on section 4(a)(6)`   IS A BOOLEAN     -- regcf-denovo.l4:739
`closings in reliance on section 4(a)(6)`              IS A LIST OF Closing  -- :751
`previously sold securities in reliance on section 4(a)(6)`  IS A BOOLEAN   -- :755
```

and the test fixtures fill them in by hand (`regcf-denovo.l4:3221-3229`). The aggregation then
computes over these inputs (`:1334-1342`).

**Why it is honest:** the epistemic situation is real — the model genuinely cannot observe the
issuer's invocation, so asking the issuer is not a hack, it is the truthful statement of where
the knowledge lives.

**Why it fails as a semantics:** the field _name quotes the phrase being defined_. Membership in
the $5M aggregate — the entire operative content of §227.100(a)(1) — is decided outside the
formalisation, by whoever fills in the form, with no definition of what they are being asked.
The model computes `sum` faithfully over a set whose membership criterion it never states. Every
downstream conclusion inherits an undefined predicate. This is the degraded mode a reliance
semantics must _explain_ (what question is the input answering?), not the answer.

### 2.2 Derived from applicability: "the rule was applicable"

Proposal: `relied(act, R)` iff `R`'s conditions were satisfied by `act`.

**Fails, twice over.** First, exemptions overlap: a private sale to one accredited investor may
simultaneously satisfy §4(a)(2), Regulation D, and (if run through a portal) §4(a)(6) —
applicability cannot pick which one the actor invoked. Second, it gets the counterfactual wrong:
a sale that satisfied every condition of 4(a)(6) but was conducted under an effective
registration statement was **not** in reliance on 4(a)(6), and must not consume 4(a)(6)
headroom. Applicability is necessary for reliance to _succeed_ (§2.6); it is not reliance.

### 2.3 Derived from consultation: "the rule was consulted"

Proposal: `relied(act, R)` iff the actor's reasoner evaluated `R` in reaching its decision — the
evaluation trace shows the rule fired.

L4 can very nearly deliver this: the trace records every expression entered and exited
(`jl4-core/src/L4/EvaluateLazy/Trace.hs:87-88`; emitted at
`jl4-core/src/L4/EvaluateLazy.hs:176`), and the corpus's `@ref` annotations
(`jl4-core/src/L4/Lexer.hs:404`; used throughout `regcf-denovo.l4`, e.g. `:1333`) tie every rule
to its CFR citation — so "which cited provisions were evaluated in this run" is a recoverable
projection.

**Still fails.** Consulting is not relying: an issuer's counsel can evaluate 4(a)(6), conclude
it is available, and advise registering anyway. Conversely an issuer can rely on a rule nobody
checked. And a trace is forgeable-by-omission — running the reasoner twice and keeping the
flattering trace is free. Consultation is _evidence_ about reliance (§2.6 shows it is
evidentially interesting in one quadrant), never the thing itself.

### 2.4 An attestation: a recorded act by a party that bears its consequences

Proposal: `relied(actor, R, act)` holds iff the actor **declared** it — a dated, signed,
rule-citing entry on the ledger, made by (or attributable to) the party who bears the
consequences of the declaration being wrong.

This is the adopted answer (Ruling R1, §9). It is the only candidate that matches the direction
of fit (§1.3): reliance comes into being by being declared, so the formal system's job is to
record the declaration with enough structure that everything downstream — aggregation (§5),
correction (§6), audit — is computable from the record. The party bears the consequences: an
attested reliance on an unavailable exemption is precisely the failed-exemption quadrant of §2.6,
and the attestation is what makes the failure _attributable_.

### 2.5 An election-by-filing: does Form C constitute reliance, or evidence it?

For 4(a)(6) specifically there is an institutional act ready-made: §227.203(a)(1) requires a
Form C **before the offering commences** (`part227.txt:358`), and the Form names the exemption.
Two readings:

- **Constitutive:** filing _is_ the reliance — the declaration of §2.4, performed with legal
  formality, on the Commission's own record. Sales under a filed Form C are in reliance on
  4(a)(6) _by virtue of the filing_.
- **Evidentiary:** filing merely evidences an underlying reliance that exists independently
  (and could exist without the filing, or fail to exist despite it).

The doctrine — flagged as reasoning from securities-law background, not verified against the
tree — cuts against a fully constitutive reading being _irrevocable_: in the neighbouring
Regulation D, attempted compliance with one rule "does not act as an exclusive election"
(17 CFR 230.500(c)), so an issuer may fall back on any other exemption that was in fact
available. The workable synthesis: **filing constitutes reliance defeasibly** — it creates the
reliance record, and that record is amendable under §6's bitemporal discipline, not immutable.
In ledger terms (§4): the private intention is a `RECORD`, the filing is the `COMMIT`/`ATTEST`
to the official record, and EDGAR is the `officialLedger`. The mapping is exact and is the
strongest argument that L4's existing substrate is the right home for this construct.

### 2.6 The three predicates come apart — which is why this spec exists

Distinguish, once and permanently:

| predicate               | kind                            | source of truth                                       |
| ----------------------- | ------------------------------- | ----------------------------------------------------- |
| `applicable(R, act)`    | derived fact                    | the model: `R`'s conditions evaluated against facts   |
| `consulted(R, act)`     | evidence                        | an evaluation trace (`Trace.hs:87-88`), if one exists |
| `relied(actor, R, act)` | recorded act (declaration §1.3) | the ledger — never derivable                          |

They are logically independent; the informative cells of the eight-way table:

| applicable | consulted | relied | legal reading                                                                                                                                                        |
| ---------- | --------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ✓          | ✓         | ✓      | the good case: informed, valid invocation                                                                                                                            |
| ✓          | ✗         | ✓      | valid but unexamined reliance — lawful; diligence duties (e.g. §227.503(b)'s reasonable care) live elsewhere                                                         |
| ✓          | ✓/✗       | ✗      | **unclaimed exemption** — the sale does _not_ join the 4(a)(6) aggregate; headroom preserved (the §2.2 counterfactual)                                               |
| ✗          | ✗         | ✓      | **failed exemption** — the dangerous quadrant: §5 exposure (§1.2)                                                                                                    |
| ✗          | ✓         | ✓      | failed exemption _with a trace showing the actor's own reasoner said no_ — the reliance is invalid as before, and the consultation record now bears on state of mind |

The asymmetry to hold on to: **`relied` alone determines aggregate membership** (§5);
`applicable` determines whether the reliance _succeeds_; `consulted` never changes either — it
only ever matters evidentially. A semantics that collapses any two of these (as §2.2 and §2.3
each do) gets a quadrant of the table wrong, and every quadrant is a real legal posture.

### 2.7 The formal shape: edge provenance, not state predicate

Reasoning, not report. In LTS terms — the frame the deontic layer already lives in — several
rules may license the _same observable action_: the same sale can be the exercise of the 4(a)(6)
permission, of a Reg D permission, or of the registered-offering path. A run of the system is a
sequence of transitions, and when two transitions carry the same action label from the same
state, they are still **different edges**, distinguished by which rule licenses them. "In
reliance on R" selects, among observationally identical actions, those whose _edge_ was R's.

That is why reliance cannot be a state predicate and cannot be recovered from the world: edge
identity is a property of the **run**, and the run is exactly what a ledger reifies and a state
snapshot forgets. The corpus's own device makes the same point at the fact level: the two
readings of the 12-month window are carried as _two separate inputs_ precisely because a single
merged number would "hide the fork inside a fact the user supplies"
(`regcf-denovo.l4:748-752`, `fork-register.json:88-111`). Reliance is that observation one level
up: not which reading of a rule, but **which rule at all** — and it must be carried, because it
cannot be recomputed.

---

## 3. Is it self-verifying?

Suppose the issuer's compliance system runs the L4 reasoner before every closing; the trace
shows `100(a)(1) — the aggregate amount does not exceed the cap` (`regcf-denovo.l4:1378`)
evaluated to TRUE, with `@ref § 227.100(a)(1)` in the citation set. Is that reliance?

No — three times no, in ascending order of importance:

1. **It shows the wrong predicate.** The trace establishes `consulted`, and the TRUE verdict
   establishes (modelled) `applicable`. §2.6: neither is `relied`, and the quadrant where they
   diverge — checked, available, and deliberately not invoked — is a routine business posture.
2. **Wrong direction of fit.** A trace is descriptive: it reports what a computation did. A
   reliance is performative (§1.3): it is _made_, not observed. No amount of descriptive record
   sums to a declaration; the actor must additionally _commit_ — which is an act, dated and
   attributable, i.e. a ledger event.
3. **Wrong custody.** A trace produced and retained by the issuer is self-serving evidence,
   selectable after the fact. The ledger design already solved this shape of problem: private
   working state is `RECORD`ed on the party's own ledger; what counts institutionally is the
   explicit promotion to the official record (`COMMIT`/`ATTEST` — R1, per-party ledgers with
   explicit commit points, `specs/done/STATE-AS-LEDGER-SPEC.md:166`; `Ledger.hs:234-247`). For
   4(a)(6) the official record has a name: EDGAR, written to by filing Form C (§2.5).

What the trace IS good for: attached to an attestation, it upgrades quadrant `✓✗✓` to `✓✓✓`
(reliance with contemporaneous verification) — the "audit-grade tool calling" story, where the
attestation carries its supporting evaluation as exhibit. Proposed posture (R2, §9): the
reasoner _derives_ `applicable`, _evidences_ `consulted`, and only ever _reads_ `relied` off a
ledger.

---

## 4. Inventory: what L4 already has

Everything in this section is shipped and cited; nothing is proposed.

### 4.1 The ledger substrate

- **Writes.** `RECORD <cell> IS <expr>` appends to the acting party's own ledger;
  `COMMIT`/`ATTEST` appends to the single shared official ledger
  (`specs/done/STATE-AS-LEDGER-SPEC.md:47-52`; routing at `Ledger.hs:262-275`). Writes can stand
  as steps in a deontic chain via the optional `HENCE`
  (`STATE-AS-LEDGER-SPEC.md` M5, `:220`), so "on closing the sale, record the reliance" is
  expressible in sequence with the obligation it accompanies.
- **Provenance.** Every entry carries `MkProvenance { party, source, txTime, vtFrom }`
  (`Ledger.hs:65-82`). `txTime` is stamped from the root clock and is **immune to
  `EVAL AS OF SYSTEM TIME`** (`Ledger.hs:69-75`) — you cannot backdate the transaction stamp.
  `vtFrom` carries an explicitly asserted fact-time when one is in scope (`Ledger.hs:76-81`).
- **Reads.** `RECALL <cell>` = latest visible value; `RECALL <party>'s <cell>` cross-party;
  `RECALL OFFICIAL's <cell>` the shared record; `RECALL ALL <cell>` = _every_ assignment to the
  cell, oldest-first, as a `LIST OF a`
  (`jl4-core/src/L4/Parser.hs:2281`, `jl4-core/src/L4/Syntax.hs:303`, `:346`;
  `Ledger.hs:147-148`).
- **Bitemporal projections.** `readCellBitemporal` reads through both lenses — a tx cutoff
  ("what did we know at _t_?") and a vt point ("what held at _t_?") — with positional valid
  intervals and the same-vt correction rule: a later append at the same valid time is a
  correction and wins (`Ledger.hs:154-202`, esp. `:169-173`, `:195-198`).
- **Survival across breach.** Pre-breach ledger entries survive a `ValBreached` (D5,
  `STATE-AS-LEDGER-SPEC.md:153-155`) — a reliance recorded before a deal collapses remains on
  the record, which is exactly what an auditor of a failed offering needs.
- **NOTIFY.** A recipient-qualified write: the acting party writes into a named recipient's own
  ledger (`RouteNotify`, `Ledger.hs:262`) — the shape of an issuer's notice _to the
  intermediary_, which §5.3 needs.

### 4.2 `ATTEST` is a synonym waiting for a semantics

Today `ATTEST` is "an accepted synonym for `COMMIT`" (`STATE-AS-LEDGER-SPEC.md:50`); the two
route identically. Reliance is the first construct that would give `ATTEST` a meaning of its
own: a **speech-act-typed** official write — one whose entry is a declaration by its party,
carrying a rule citation, presumptively self-attributing (the attester bears the consequences,
§2.4), and subject to the correction discipline of §6 rather than plain last-write-wins.
Whether that divergence should happen is R5 (§9); this spec's v0 sketch deliberately does _not_
require it.

### 4.3 The temporal rule-version axis

`EVAL UNDER RULES EFFECTIVE AT` scopes which version of the rules a subtree is evaluated under
(`Machine.hs:189-190`, `:829-832`), read by the `RULES EFFECTIVE DATE` reader (`:658-673`,
error path `:3782-3785`). The corpus uses it to date its constants: the $5,000,000 cap is a
rule-dated value with an explicit refusal floor for dates before the encoding's coverage
(`regcf-denovo.l4:222-226`, floor at `:211`). §5.4 shows why a reliance record must interact
with this axis.

### 4.4 Rule identity: `@ref`

`@ref` is a recognised source annotation (`Lexer.hs:404`) and the corpus discipline attaches a
CFR citation to every rule (`regcf-denovo.l4:1333` and throughout). So "section 4(a)(6)" — the
_object_ of reliance — has a stable, citable identity in the encoding. A reliance record can
name its rule the same way the rules name their sources.

### 4.5 The interpretation seam

The R4 fork pattern threads an `Interpretation` record through every forked reading
(`regcf-denovo.l4:1345-1352`). Reliance composes with it rather than replacing it: _which rule
was invoked_ (this spec) and _which reading of that rule the evaluator applies_ (R4) are
orthogonal axes, and §5's aggregation varies along both.

### 4.6 What is missing

Three gaps, and only three, between the substrate and the design of §9:

1. **`RECALL ALL` strips provenance.** It returns bare values — `[WHNF]`, no `Provenance`
   (`Ledger.hs:204-217`) — so a twelve-month window cannot be cut using the entries' own
   stamps; the date must travel _inside_ the recorded value. (The corpus's `Closing` record —
   date + amount, `regcf-denovo.l4:653-655` — is already this workaround.) A
   provenance-exposing or window-bounded read is future work; note the deliberate design
   position that valid-time _point_ filtering of a whole history is a category error
   (`Ledger.hs:207-209`), so the right shape is an interval query, not a point query.
2. **The flat-ledger typing gap.** `RECALL`/`RECALL ALL` are typed against a fresh type
   variable, unlinked to what was written (`STATE-AS-LEDGER-SPEC.md:205`) — a reliance schema
   is a convention, not yet a checked contract. The typed-schema refinement (R2 of that spec)
   is the fix; this spec adds one more customer for it.
3. **No applicability lint.** Nothing connects an attested reliance to the availability of the
   rule relied on — the `✗·✓` failed-exemption quadrant (§2.6) is exactly the kind of
   contradiction L4 exists to surface, and it is currently invisible. R3 (§9).

---

## 5. The aggregation consequence

The predicate is not merely per-act: §227.100(a)(1) makes it a **membership criterion for a
running, windowed sum over past acts**. What must the ledger deliver?

### 5.1 Per-issuer: the (a)(1) cap

The aggregate is over _the issuer's own_ sales-in-reliance — a fold over one party's record.
This is the friendly case: it is a projection over the issuer's own ledger, and the corpus's
reading B already computes precisely this fold, from a supplied list:
`sum (map amount (filter within-window closings))` (`regcf-denovo.l4:1334-1342`). Migrating it
from "supplied list" to "ledger projection" is a change of _source_, not of shape: each closing
becomes a reliance-tagged event; the aggregate becomes `sum` over `RECALL ALL` filtered by the
window — modulo gap §4.6(1), the date rides inside the recorded value.

Note what the window filter is anchored to is itself a registered fork (F-CAP-12MONTH-ANCHOR,
`fork-register.json:88-111`): rolling from each closing vs a single window from the offer date.
The ledger view is neutral between them — both are folds over the same events — which is as it
should be: the fork is interpretive (§4.5), the events are facts.

### 5.2 Per-investor, across all issuers: the (a)(2) cap — and why Instruction 3 exists

§227.100(a)(2) aggregates the _investor's_ purchases "across all issuers" (`part227.txt:104`).
No party in the model holds that total: it is a projection over the union of **every issuer's**
official records — or every intermediary's — and no single ledger, official or otherwise,
contains it. The model cannot compute it; it can only ask an oracle.

The regulation _agrees_. Instruction 3 to paragraph (a)(2) (`part227.txt:114`) lets the issuer
"rely on the efforts of an intermediary … to ensure that the aggregate amount … will not cause
the investor to exceed the limit", unless the issuer knows better. That is: the drafters hit the
same epistemic wall the formalisation hits, and licensed **second-order reliance** — reliance on
an intermediary's representation about a reliance-driven aggregate. The corpus encodes this
limb as the "intermediary-reliance safe harbour" (`regcf-denovo.l4:1494`). The formalisation
did not create the oracle problem; it _rediscovered from first principles why the safe harbour
is in the text_ — which is this spec's best evidence that the provenance-of-act reading is the
right one. In substrate terms the shape is already present: the intermediary's tracking is an
oracle input (cf. `STATE-AS-LEDGER-SPEC.md` §6), and issuer↔intermediary notices are
`RouteNotify` writes (§4.1).

### 5.3 The window crosses rule versions

A twelve-month aggregate can straddle a change in the rules. This is not hypothetical for
Reg CF: the encoding's own constants are rule-dated with a refusal floor
(`regcf-denovo.l4:222-226`, `:211`), and — doctrine flag, from history not the tree — the cap
was raised from $1.07M to $5M in March 2021, so every window opened within a year of that date
mixed sales made under two different caps. Two consequences for the record:

- A reliance names a rule **as of a date**: `relied(actor, R@version, act)`. The `@ref`
  citation (§4.4) plus the act's date is sufficient to reconstruct the version via the
  rule-version axis (§4.3); the record need not embed the version so long as it embeds the
  date — which gap §4.6(1) already requires it to.
- Aggregation logic must decide _under which rules_ the aggregate is judged — and
  `EVAL UNDER RULES EFFECTIVE AT` is exactly the scoping construct for saying so explicitly.

### 5.4 What the ledger must deliver — summarised

| requirement                                | status                                                                         |
| ------------------------------------------ | ------------------------------------------------------------------------------ |
| per-act reliance events, party-attributed  | expressible now: `ATTEST` + schema (§9 sketch)                                 |
| the act's date inside the event            | convention (the `Closing` pattern); forced by gap §4.6(1)                      |
| rule identity inside the event             | convention: the `@ref` citation string (§4.4)                                  |
| windowed aggregate over one party's events | expressible now: `sum`/`filter` over `RECALL ALL` (cf. `regcf-denovo.l4:1338`) |
| cross-party universal aggregate ((a)(2))   | **not derivable in-model**; oracle input, as Instruction 3 itself licenses     |
| judged under an explicit rule version      | expressible now: `EVAL UNDER RULES EFFECTIVE AT` (§4.3)                        |

---

## 6. Retroactivity and re-characterisation

A sale made "in reliance on" one exemption can later be argued to have been under another, or
under none. Doctrine (flagged, §2.5): reliance is not an exclusive election in the Reg D
neighbourhood (17 CFR 230.500(c)), and exemption availability is litigated after the fact with
the burden on the claimant. So re-characterisation is legally live, and the formal model must
support it **without ever supporting falsification**. The bitemporal substrate draws exactly
this line:

- **A reliance claim is a valid-time assertion.** "Sale S of 2026-03-01 was in reliance on
  4(a)(6)" has `vtFrom` at the sale date, whatever day it is recorded.
- **A correction is a new entry, not an edit.** Amending the characterisation of S appends at
  the same valid time with a later transaction position; the same-vt correction rule makes the
  later entry win the projection (`Ledger.hs:169-173`, `:195-198`) while the superseded claim
  remains in the log.
- **The two lenses answer the two litigation questions.** "What did the issuer's record say at
  the time of the later offering?" is a tx-cutoff read; "what do we now say was true then?" is
  a vt read at the sale date (`Ledger.hs:154-179`). A re-characterisation changes the second
  without erasing the first — which is precisely what distinguishes an amendment from a
  fabrication.
- **The audit floor is structural.** `txTime` is stamped from the root clock and is immune to
  `EVAL AS OF SYSTEM TIME` (`Ledger.hs:69-75`): the record of _when the story changed_ cannot
  be simulated away. Since headroom at every subsequent sale date is a function of the
  aggregate (§5), a re-characterisation retroactively rewrites headroom history — the tx stamps
  are what keep that rewriting visible, and visible rewriting is the audit defence against
  headroom laundering.

Proposed posture (R4, §9): corrections to reliance are bitemporal amendments, never destructive
writes; and a projection that _consumes_ reliance (any §5 aggregate) should be able to state
which lens it reads through.

---

## 7. Adjacent constructions

This spec sits beside the override taxonomy of `SUBJECT-TO-NOTWITHSTANDING-SPEC.md`; the same
discipline — one phrase, several distinct mechanisms — applies to the reliance family.

| phrase                  | mechanism                                                                | source of truth            | L4 home                                                          |
| ----------------------- | ------------------------------------------------------------------------ | -------------------------- | ---------------------------------------------------------------- |
| "in reliance on R"      | **invocation** — the actor elects R as the legal basis of an act         | a party's recorded act     | ledger event (this spec)                                         |
| "pursuant to R"         | **conformity** — the act is performed under and in accordance with R     | derivable, given the basis | applicability check against R's requirements                     |
| "under R"               | usually conformity; sometimes mere classification                        | derivable / editorial      | as above                                                         |
| "for the purposes of R" | **scoped definitional context** — an input filter on R's domain          | the rule itself            | domain restriction, `SUBJECT-TO-…-SPEC.md` §2.6 (`:195-223`)     |
| "deemed X"              | **constitutive fiction** — the rule makes it so, regardless of the world | the rule itself            | a declaration performed by the _rule_ rather than a party        |
| "as applicable"         | **evaluation-order directive** — licenses leaving a disjunct unexamined  | the rule itself            | lazy / short-circuit evaluation; the demand-driven wizard (§7.1) |

The instructive pair is the first two, because Part 227 uses them in one sentence: Instruction 3
speaks of securities purchased "in offerings **pursuant to** section 4(a)(6)" three lines after
"selling securities **in reliance on** section 4(a)(6)" (`part227.txt:114`), and §227.501 says
"exempt from registration **pursuant to** section 4(a)(6)" (`:569`). Reliance is the _election_;
pursuant-to is the _conformity of execution_ given the election. They usually coincide — which
is why drafters interchange them — and they come apart in exactly the failed-exemption quadrant
(§2.6): a sale in reliance on 4(a)(6) that violates its conditions was in-reliance-on but not
pursuant-to. A reliance semantics gets this pair right for free: `relied` is the event,
`pursuant-to` is `relied ∧ applicable`.

"Deemed" is the mirror image of reliance and confirms the direction-of-fit analysis (§1.3):
both are declarations, but reliance is performed by a _party_ and recorded on a ledger, while
deeming is performed by the _rule_ and needs no record — it is evaluable. That is why "deemed"
belongs in the constitutive layer and "in reliance on" cannot.

An adjacent-domain check (reasoning, not report): GDPR Article 6 has the same shape — a
controller must identify the lawful basis for processing, per-act, and regulator guidance
resists swapping bases retroactively. Legal-basis election as a recorded, correction-disciplined
act appears to be a recurring pattern, not a Reg CF quirk; this supports treating it as a
language-level concern rather than a corpus-level workaround.

### 7.1 "As applicable" as an evaluation-order directive (added 2026-08-09, from Meng)

The statutory investor cap, 15 U.S.C. 77d(a)(6)(B)(i), limits the sale by reference to "5
percent of the annual income or net worth of such investor, **as applicable**". _Evidence
status:_ the statute is **not in the source bundle** — `source/` holds Part 227 plus two CFR
refs (`ref-230.501.xml`, `ref-270.3a-9.xml`), and `part227.txt:88` cites 15 U.S.C. 77d only as
authority — so the quotation is as supplied by Meng, consistent with memory of the JOBS Act
text, not tree-verified.

**The reading.** "As applicable" is a **lazy-evaluation directive**. Requiring strict
evaluation of both measures forces the investor to gather paperwork substantiating both —
income _and_ net worth — only to discard one as unnecessary. "As applicable" licenses
short-circuit: evaluate one, and if it suffices, leave the other unexamined.

**Why it is not merely an analogy.** The cost being avoided is _evidentiary_, not
computational. A thunk here is a document you would otherwise have to obtain, and forcing it
has a real price: expense, delay, and disclosure of a figure that turns out to be irrelevant.
Laziness is a drafting device with a purpose, not a metaphor imported from programming
languages.

**Test vs computation — and a concession.** Review initially presented this clause to Meng as
a computation; Meng's correction — in the operative context, an investor deciding whether they
may invest $X, it is a **test** — is what makes the lazy structure visible:

```
qualifies = clears(income) || clears(net_worth)      -- statute, lazy, short-circuits
cap       = 5% * max(income, net_worth)              -- regulation, strict, forces both
```

You cannot evaluate `max` without both operands. So 17 CFR 227.100(a)(2)(i) — "5 percent of
**the greater of** the investor's annual income or net worth" (`part227.txt:106`, verbatim) —
**strictifies** what the statute left lazy, and the corpus faithfully encodes the strict form:
`max` over both measures (`regcf-denovo.l4:1426-1432`), forced again in both tiers of the
limit computation (`:1443-1451`).

Why the two agree wherever both figures exist (reasoning, checkable by inspection): for any
threshold, `max(a,b) ≥ t ⟺ a ≥ t ∨ b ≥ t` — the strict computation and the lazy test decide
the same question on every total assignment. The strictification changed **what must be
evidenced**, not what is true. One caveat from working the tiers (reasoned, not
machine-checked): the identity governs the within-tier test, but tier selection itself is not
fully lazy — establishing tier (ii) requires _both_ measures at or above the boundary
(`part227.txt:108`; `regcf-denovo.l4:1435-1441`), so near the boundary and the tier-(ii)
ceiling the unexamined measure can matter after all. _(Doctrine flag, from memory, verify
before citing outward: the same lazy statutory text has supported two different
strictifications — the 2016 rule read it as 5 percent of the **lesser** of the two measures,
and the 2020 amendments reversed this to "greater" — evidence that "as applicable"
under-determines the strict semantics, and the agency picked twice, differently.)_

**The divergence has no behavioural signature.** Lazy `||` and strict `max` agree
extensionally for any investor who has both figures; they differ only in what must be
evidenced — and, on _partial_ assignments, in whether they can answer at all (the lazy test
can decide from one figure while the strict computation is stuck). The acceptance machinery
cannot see this class of divergence: the §8 diff oracle "pairs decisions by declared
correspondence and diffs answers over a shared fact battery"
(`specs/todo/single-instruction-demo/SPEC.md:424-425`), and identical answers on every
complete battery row means a lazy encoding and a strict encoding of (a)(2)(i) diff clean.
`DENOVO-DIFF-ORACLE.md` already declares its blind spots — unpaired decisions, the unexercised
deontic layer (`DENOVO-DIFF-ORACLE.md:471-489`) — but those are blind by _omission_;
evidentiary-burden divergence is blind by _construction_, because it lives in intension (what
is demanded) while the oracle compares extension (what is answered). Ruling R7 proposes the
probe.

**Two kinds of NOTHING.** The lazy reading splits `MAYBE`: `NOTHING` as _unknown_ (the
investor has a net worth; nobody established it) versus `NOTHING` as _unexamined_
(deliberately not forced, because income already cleared). Only the second is the statute's
licensed silence. **Established from the tree: L4 cannot currently distinguish them.** The
prelude `MAYBE` has a single `NOTHING` constructor (`jl4-core/libraries/prelude.l4:356-380`
show its two-constructor pattern matches), and nothing in the evaluator tags _why_ a value is
absent. The design that would make the split — the four-state input model distinguishing
explicit-value / explicit-unknown / not-yet-asked / not-applicable, `Either (Maybe a) (Maybe
a)` — exists but is marked **BLOCKED** in its own status header
(`specs/todo/RUNTIME-INPUT-STATE-SPEC.md:3-11`). Today the distinction is representable only
operationally (next paragraph) or by convention.

**The convergence.** Checked against the spec rather than taken on trust: the question-ordering
wizard's stated scope is to "choose which unknown to ask next so the wizard terminates
quickly" (`specs/todo/QUESTION-ORDERING-SPEC.md` §1), its policy is model-count information
gain over the ROBDD (§3), and its own optimisation table names the objective as minimising
"the number of questions a user is actually asked" (`:206`). That is demand-driven evaluation
of a legal test with **evidentiary cost as the objective function**: when the wizard reaches a
terminal with questions unasked, the unasked questions _are_ the unexamined thunks — the
second kind of NOTHING, realised as policy. The observation: the drafter reached for lazy
evaluation in prose ("as applicable"), and this programme built demand-driven evaluation as a
wizard without noticing the correspondence.

**Placement in the taxonomy.** Where "in reliance on" and "pursuant to" are about the
provenance of an act — whose act, invoking which rule — "as applicable" is a third device
about **evaluation order and evidentiary burden**: how much of the world the rule licenses you
not to look at.

---

## 8. What a drafter should do instead

The honest question: is "in reliance on" a concept to model faithfully, or a drafting defect
that formalisation exposes?

Split the verdict. The _concept_ — acts carry a legal basis that cannot be recovered from the
world — is sound and load-bearing (§2.7); a formal language for law must be able to say it.
The _drafting_ — hanging a $5,000,000 strict-liability cliff on an undefined mental-state
predicate — is a defect, and the fix is one legislative sentence: **define reliance
procedurally**. "Securities sold in an offering for which the issuer has filed a Form C under
§227.203" is computable from the public record; "securities sold in reliance on section
4(a)(6)" is not. Tax drafting learned this long ago — elections are defined by the act of
filing them ("an election under this section is made by…") — and §2.5 shows the SEC's regime
already operates this way in practice; the text just never says so.

For the L4 pipeline the recommendation is therefore double-headed:

1. **Encoding existing law:** model reliance as the attested act (§9), and register the
   constitutive-vs-evidentiary question of §2.5 as an interpretive fork where the text leaves
   it open — it is fork-register material, same discipline as F-CAP-12MONTH-ANCHOR.
2. **Drafting new rules (the rules-as-code seat):** advise the procedural definition, and let
   the diff between "what the text says" and "what the encoding had to add to make it
   computable" be the drafting feedback. The gap between §2.1's uninterpreted input and §9's
   attested event _is the measurement_ of what the current text under-specifies.

---

## 9. Proposed rulings

All PROPOSED 2026-08-09; none decided. Each names the evidence that drove it.

> **R1 — Reliance is a recorded party act, not a derived fact.** `relied(actor, R, act)` enters
> the model only as a ledger event: party-attributed, dated (valid time = the act's date), and
> naming its rule by citation (`@ref` string, §4.4). Candidates §2.1–2.3 are rejected for the
> reasons given there; §2.5's filing is the institutional performance of the same act.
> _Driven by:_ the direction-of-fit argument (§1.3) and the quadrant analysis (§2.6).

> **R2 — Three predicates, never collapsed.** The reasoner _derives_ `applicable`, _evidences_ > `consulted` (from traces, when they exist), and only _reads_ `relied` from a ledger. No L4
> construct may silently convert one into another. _Driven by:_ every quadrant of §2.6 being a
> real legal posture.

> **R3 — The applicability lint.** Where an attested reliance and the model's applicability
> verdict disagree (`relied ∧ ¬applicable`), the toolchain should surface a diagnostic — this is
> the failed-exemption quadrant, the single most consequential state the model can detect.
> Detection, not resolution: whether the reliance is cured, re-characterised (§6), or litigated
> is not the checker's call. _Driven by:_ §1.2's stakes; the detect≠resolve seam already ruled
> elsewhere in this programme.

> **R4 — Corrections are bitemporal amendments.** Re-characterisation of a past reliance is an
> append at the same valid time (`Ledger.hs:169-173`); destructive rewriting of reliance history
> is never expressible. Aggregates that consume reliance state which lens they read through.
> _Driven by:_ §6; the tx-stamp audit invariant (`Ledger.hs:69-75`).

> **R5 — No new keyword in v0.** The v0 design is a **schema convention over shipped syntax**,
> not a language change: a declared record type for the reliance event, written with
> `ATTEST … IS …` (officially) or `RECORD … IS …` (privately), aggregated with
> `RECALL ALL` + `sum`/`filter`. Divergence of `ATTEST` from `COMMIT` (§4.2) is deferred until
> the convention has been exercised on the Reg CF corpus and found wanting. _Driven by:_ §4.6 —
> the gaps are a missing read primitive, a typing refinement, and a lint, none of which a new
> keyword would close.

> **R6 — "As applicable" is an evaluation-order directive, and strictification is a recordable
> divergence.** (PROPOSED 2026-08-09.) Read "the annual income or net worth of such investor,
> as applicable" as licensing short-circuit evaluation: a measure left unexamined is the
> statute's licensed silence, not missing evidence. Where a downstream authority strictifies a
> lazy formulation — the statute's disjunctive test vs §227.100(a)(2)(i)'s "the greater of"
> (`part227.txt:106`) — an encoding should be able to record the strictification as a
> divergence _between authorities along the evaluation-order axis_, under the same
> register-the-fork discipline as a divergence of meaning. _Driven by:_ §7.1; the cost of
> forcing being evidentiary, not computational — and (doctrine flag) the same lazy text having
> historically supported two opposite strictifications.

> **R7 — Evidentiary-burden divergence needs its own acceptance probe.** (PROPOSED 2026-08-09.)
> Two encodings that agree on every total fact assignment can still differ in what they demand
> evidenced — lazy `||` vs strict `max` (§7.1). The diff oracle compares answers over a shared
> fact battery (`specs/todo/single-instruction-demo/SPEC.md:424-425`) and is therefore blind to
> this whole class **by construction**, not by omission. Proposed probes: (a) battery rows with
> _partial_ assignments — an unknown operand separates the encodings by definedness (the lazy
> test answers; the strict computation is stuck); (b) comparing _demanded-variable sets_ (the
> wizard's ask-set / the ROBDD path support at each terminal) rather than answers alone. Either
> way, the class belongs on `DENOVO-DIFF-ORACLE.md`'s declared blind-spot list
> (`:471-489`), which currently does not name it. _Driven by:_ §7.1's no-behavioural-signature
> argument.

### 9.1 The v0 sketch (paper-checked against shipped syntax; **not executed** — no build was run)

```l4
-- The reliance event. Every field is data the aggregation or the lint needs;
-- the date rides inside the value because RECALL ALL strips provenance (§4.6(1)).
DECLARE Reliance HAS
    `the provision relied on`   IS A STRING    -- the @ref citation, e.g. "15 U.S.C. 77d(a)(6)"
    `the date of the sale`      IS A DATE
    `amount sold`               IS A NUMBER

-- At each closing, the attestation is a step in the deontic chain (M5 HENCE):
--   PARTY Issuer
--     MUST `close the sale` ...
--     HENCE ATTEST `sales in reliance on section 4(a)(6)`
--           IS Reliance WITH `the provision relied on` IS "15 U.S.C. 77d(a)(6)",
--                            `the date of the sale`    IS ...,
--                            `amount sold`             IS ...

-- The (a)(1) aggregate becomes a fold over the attested events — the same fold
-- the corpus already runs over its supplied list (regcf-denovo.l4:1338):
--   sum (map amount (filter withinWindow (RECALL ALL `sales in reliance on section 4(a)(6)`)))
```

Known caveats, restated from §4.6: the `RECALL ALL` result is typed against a fresh variable
(the flat-ledger gap), so the schema is honour-system until the typed-schema refinement lands;
and the applicability lint (R3) does not exist. Both are tracked there; neither blocks
exercising the convention on the corpus.

---

## 10. Open questions

1. **Who may attest?** Reg CF reliance is the issuer's, but filings are made by agents and
   the intermediary attests adjacent facts. Does an attestation-by-agent need the
   actor-indexed-action machinery (performer checks, procurement — see
   `doc/reference/regulative/PARTY.md:95-108`), or is party-attribution via the deontic
   context (the M4 `currentParty` threading) sufficient?
2. **Is reliance a set?** Belt-and-braces drafting invokes multiple bases at once ("in
   reliance on 4(a)(6) and/or Regulation D"). One event with a set of citations, or one event
   per basis? The aggregation consequences differ (a dual-basis sale would join two
   aggregates).
3. **Revocation vs amendment.** §6 handles re-characterisation; is _withdrawal_ (reliance on
   nothing — the sale was registered after all) the same operation with an empty basis, or a
   distinct event kind?
4. **Acceptance semantics for the official record.** EDGAR _accepts_ filings; L4's `COMMIT`
   is unilateral. Does the official-record write need a counterparty acceptance step (an
   obligation on the recipient), or is unilateral-append-plus-correction (§6) faithful enough?
5. **Does the attestation pin the rule version?** §5.3 concluded date-in-event suffices to
   reconstruct the version; is there a case — e.g. transitional provisions offering an
   election between old and new rules — where the version electing must be explicit in the
   event?
6. **The windowed read.** What is the right primitive shape for §4.6(1): a
   provenance-exposing `RECALL ALL` (entries with stamps), an interval-bounded read, or
   nothing (dates stay in values by convention)? The category-error note at
   `Ledger.hs:207-209` constrains but does not decide this.
7. **Fork registration.** Should the constitutive-vs-evidentiary question (§2.5) be registered
   now as an interpretive fork on the Reg CF corpus, ahead of any implementation? (§8 says
   yes; recorded here as open because the corpus, not this spec, owns its fork register.)
8. **The runtime representation of the two NOTHINGs.** `MAYBE` cannot carry
   unknown-vs-unexamined (§7.1), and the four-state design that could is blocked
   (`RUNTIME-INPUT-STATE-SPEC.md:3-11`). Does the split need a runtime representation in the
   object language at all — or is "unexamined" always a _policy-level_ fact (the wizard's
   unasked set) that belongs to the interaction layer, never to the evaluator?

---

## 11. What review changed

Written so a later editor does not silently un-learn what checking the tree taught:

- **The primitive already exists; the spec became a schema-and-gaps document.** The initial
  framing assumed reliance needed new syntax. Reading `Ledger.hs` and the ledger spec showed
  `ATTEST`, per-party/official routing, bitemporal stamps, and `RECALL ALL` already cover the
  event model; the deliverable shrank to a convention (§9.1) plus three named gaps (§4.6).
- **`RECALL ALL` strips provenance** (`Ledger.hs:204-217`) — discovered during review, and it
  forces the date-inside-the-value convention. The corpus's `Closing` record
  (`regcf-denovo.l4:653-655`) turned out to already _be_ that convention, independently
  arrived at; the convergence was found, not designed.
- **The corpus's status quo is §2.1, quotably.** Before reading the encoding, the "uninterpreted
  input" candidate was hypothetical; the tree shows it shipping, with the defining phrase
  embedded in the field names (`regcf-denovo.l4:739`, `:751-755`) — which sharpened the
  circularity objection from abstract to literal.
- **Instruction 3 reversed a weakness into evidence.** The cross-issuer aggregate (§5.2) first
  looked like a fatal in-model gap; reading `part227.txt:114` showed the regulation licenses an
  oracle at exactly that point. The argument was rewritten from "the model cannot do this" to
  "the model predicts why the safe harbour exists".
- **An earlier draft of §5.3 said the corpus's window straddles the 2021 cap change.** The tree
  does not support that: the encoding's floor is 2022-09-20 (`regcf-denovo.l4:211`), after the
  change. The claim was demoted to flagged doctrine and the corpus is cited only for the
  mechanism (rule-dated constants with a refusal floor).
- **§7.1 was corrected from computation to test, and the correction was Meng's.** Review
  initially presented 77d(a)(6)(B)(i) as a computation; in the operative context — may this
  investor invest $X? — it is a test, and only the test framing exposes the lazy structure
  (`||` short-circuits; `max` cannot). Recorded so the concession survives: the lazy reading
  is Meng's, and it is what made §7.1 worth writing.
- **The statute is not in the bundle.** `source/` holds Part 227 plus two CFR reference files
  only (verified by listing); the 15 U.S.C. 77d(a)(6)(B)(i) quotation in §7.1 is flagged as
  supplied, not tree-verified. The wizard-convergence and blocked-four-state claims in §7.1,
  by contrast, were verified against `QUESTION-ORDERING-SPEC.md` and
  `RUNTIME-INPUT-STATE-SPEC.md` rather than taken from the briefing.

---

## References

### Source texts

- 17 CFR Part 227 (Regulation Crowdfunding), as captured at
  `jl4/examples/legal/regcf/denovo/source/part227.txt` — esp. `:100-118` (§227.100(a),
  including `:106-108` the strictified investor limits), `:130-132` (§227.100(b)(4)-(5)),
  `:358` (§227.203(a)(1)), `:569` (§227.501).
- Securities Act of 1933 §§ 4(a)(6), 4A, 5, 12(a)(1) — incl. 15 U.S.C. 77d(a)(6)(B)(i), the
  "as applicable" clause of §7.1 _(doctrine context; not in the bundle — see the status
  header)_.
- 17 CFR 230.500(c) (Regulation D, non-exclusive election) _(doctrine, from memory — verify
  before citing outward)_.
- SEC v. Ralston Purina Co., 346 U.S. 119 (1953) _(burden on the exemption claimant; doctrine,
  from memory)_.

### Repo artifacts

- `specs/done/STATE-AS-LEDGER-SPEC.md` — D1 (`:47-52`), D2 (`:92`), D5 (`:153-155`),
  R1 per-party model (`:166`), M5 sequencing (`:220`), flat-ledger gap (`:205`).
- `jl4-core/src/L4/Evaluate/Ledger.hs` — Provenance (`:65-90`), bitemporal reads
  (`:154-217`), store and routing (`:234-279`).
- `jl4-core/src/L4/EvaluateLazy/Machine.hs` — rule-version axis (`:189-190`, `:658-673`,
  `:829-832`).
- `jl4-core/src/L4/EvaluateLazy/Trace.hs:87-88` — the consultation record.
- `jl4/examples/legal/regcf/denovo/regcf-denovo.l4` and `fork-register.json` — the status-quo
  encoding and the fork discipline.
- `specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md` — the neighbouring taxonomy, esp. §2.6.
- `specs/todo/QUESTION-ORDERING-SPEC.md` — the demand-driven question policy (§1 scope, §3
  info-gain over the ROBDD): the operational home of §7.1's "unexamined".
- `specs/todo/RUNTIME-INPUT-STATE-SPEC.md` — the blocked four-state input model
  (explicit-unknown vs not-yet-asked), §7.1's missing runtime split.
- `specs/todo/single-instruction-demo/SPEC.md` §8 and
  `specs/todo/single-instruction-demo/DENOVO-DIFF-ORACLE.md` — the diff oracle and its
  declared blind spots (R7's target).

### Speech acts and direction of fit _(reasoning support, not repo evidence)_

- Austin, J.L. _How to Do Things with Words_ (1962) — performatives.
- Searle, J. "A Taxonomy of Illocutionary Acts" (1975) — declarations; direction of fit.
- Anscombe, G.E.M. _Intention_ (1957) — the original direction-of-fit contrast.
