# Deontic model of a credit agreement: achievement vs. maintenance obligations, the frame problem, and defeasible override

**Status:** DESIGN / ANALYSIS only. No source or test changes. Grounded in
`jl4-core/src/L4/Syntax.hs`, `jl4-core/src/L4/EvaluateLazy/Machine.hs`,
`jl4-core/src/L4/Evaluate/ValueLazy.hs`, `jl4-core/src/L4/StateGraph.hs`.

---

## 0. Executive frame

A loan/credit agreement is the textbook case where the two faces of deontic
obligation collide:

- **Achievement obligations** (Governatori's term; CSL's "punctual"
  obligations): _borrower MUST pay interest each period_, _MUST deliver audited
  financials annually_. These are **liveness** — `∃` an event before a deadline.
  They are **one-shot** (this period) or **renewing** (every period). They drive
  the contract forward through a sequence of states. In jl4 they are exactly a
  `Deonton` with `modal = DMust` and a `due` deadline, whose `hence` is the next
  obligation in the cascade.

- **Maintenance obligations** (the negative covenants): _MUSTNOT let leverage
  exceed 3.0×_, _MUSTNOT sell collateral_, _MUSTNOT pay dividends while a
  covenant is breached_. These are **safety** — `∀` instants in an interval,
  nothing bad ever happens. They are **continuous** and **standing**: they must
  hold _across every state the achievement obligations move the contract
  through_. This is the classical **frame problem**: when a `MUST pay interest`
  fires its `HENCE` and the contract steps to the next period, the standing
  prohibitions must be _carried over_ to the new state, not silently dropped.

"Good standing" (Flood & Goodenough, _Contract as Automaton_) is the
**conjunction of all in-force maintenance obligations ∧ no payment default**,
**framed** (re-asserted) across every transition the achievement obligations
cause. The performing state is exactly: good standing holds.

The headline finding (Section 3): **jl4 today can express a maintenance
obligation only as a `SHANT ... WITHIN d` that watches the event stream until
_its own_ deadline `d` and then FULFILLS and disappears** (Machine.hs:977–986).
It does **not** persist across a sibling achievement obligation's `HENCE`
cascade unless you manually re-`RAnd` it into every successor — there is no
frame rule. That is the single most important gap.

---

## 1. Formal model

I choose **event calculus + a fragment of linear/branching temporal deontic
logic**, because:

- jl4's machine is _literally_ an event machine over a **linear event trace**
  (`ScrutinizeEvents`/`ScrutinizeEvent`, Machine.hs:934–947): events
  `EVENT party action time` are consumed in order. Event calculus
  (initiates/terminates/holdsAt over a timeline of happenings) is the closest
  match to what the code does.
- Achievement = liveness and maintenance = safety are most crisply stated in
  LTL/CTL, and the double-bind property needs a branching ("no _reachable_
  state") quantifier, so CTL is the right specification logic.
- The RAnd/ROr product is a CSL-style synchronous product (Hvitved); I use that
  vocabulary for the composition, automata vocabulary for "good standing."

### 1.1 Domain

```
Parties      P            = { Borrower B, Lender L }
Fluents      f            : ratios/flags that hold over intervals
                            leverage : ℝ            (a time-varying quantity)
                            inDefault : Bool        (a flag fluent)
                            covenantBreached : Bool
Events (happenings) at integer times t:
   pay(B, interest, t)
   deliver(B, financials, t)
   pay(B, dividend, t)
   sell(B, collateral, t)
   observe(leverage = r, t)        -- a measured covenant test
```

`HoldsAt(f, t)` and the inertia axiom (a fluent keeps its value until an event
terminates it) are _exactly_ the frame axioms we will need; jl4 has no built-in
notion of a fluent that persists, which is the gap.

### 1.2 The two obligation kinds (worked)

**Achievement (recurring), interest:** for every period `k` with start `s_k`,
end `s_k + 30`:

```
Ach_interest(k) ≜  F[s_k, s_k+30] pay(B, interest, ·)
                   "eventually within the window, the interest is paid"
```

LTL/MTL: `□ ( startPeriod_k → ◇_{≤30} pay(B,interest) )`. Liveness, bounded.
Renewal: `Ach_interest(k).hence = Ach_interest(k+1)` — the HENCE cascade _is_ the
period transition. Annual financials: same shape, window 365.

**Maintenance (standing), leverage covenant** over the whole life `[0, T]`:

```
Mnt_leverage ≜  □_{[0,T]}  ( leverage ≤ 3.0 )
```

i.e. `G ¬(leverage > 3.0)` — safety, `∀`-interval, no deadline of its own.
`Mnt_collateral ≜ G ¬ sell(B, collateral, ·)`.

### 1.3 "Good standing" as the **framed invariant**

```
GoodStanding(t) ≜  HoldsAt(leverage ≤ 3.0, t)
                 ∧ ¬HoldsAt(soldCollateral, t)
                 ∧ ¬HoldsAt(inDefault, t)
Performing       ≜  □ GoodStanding          (the safety hull of the contract)
```

The contract automaton's state is `(period k, GoodStanding flags)`. The
achievement cascade supplies the **transition relation** on `k`; the maintenance
set supplies the **invariant** that every state must satisfy.

**Carrying the invariant across each payment-period transition (the frame
rule), explicitly:**

```
state σ_k  = ( k , flags_k )                      flags = (leverage, sold, default)
event  pay(B,interest,t)  in window  →  HENCE step:
state σ_{k+1} = ( k+1 , frame(flags_k, event) )

frame axiom (inertia):  flags_{k+1} = flags_k     for every flag NOT changed by `event`
                        i.e. leverage, soldCollateral, inDefault PERSIST by default
property to preserve:   GoodStanding(σ_k) ⇒ checked again at σ_{k+1}
```

In words: paying interest advances the period but **does not absolve** the
borrower of the leverage and collateral covenants — those flags are _framed
forward unchanged_ and re-checked in the new state. This is precisely what jl4
does **not** do automatically: its `SHANT` lives in its own `WITHIN` window and
is gone by `σ_{k+1}`.

### 1.4 The override as a priority / defeasibility relation

Two concrete override shapes; both are **defeasible deontic logic**
(Governatori): a more specific/prior rule _defeats_ a general one.

**(a) Dividend-stopper / cash-sweep:** the dividend covenant is _conditional_ on
good standing — it is itself a maintenance obligation guarded by a fluent:

```
Mnt_dividend ≜  G ( covenantBreached  →  ¬ pay(B, dividend, ·) )
```

**(b) AT1-style coupon defeater** — the prohibition defeats the obligation:

```
r1 (general)  :  O pay(B, coupon)                       -- MUST pay coupon
r2 (specific) :  breachesBuffer(pay coupon) ⇒ F pay(B, coupon)   -- then MUSTNOT
priority      :  r2 ≻ r1
```

Defeasible reading: `O pay(coupon)` holds **unless** `r2` is triggered, in which
case `F pay(coupon)` overrides and the failure to pay is _not_ a breach. The
defeater converts what would be an achievement breach into a _permitted
omission_. Formally this is a priority order `≻` over rules with the standard
defeasible-logic proof condition: `r1` is defeated iff an applicable `r2 ≻ r1`
fires.

---

## 2. Properties to model-check

Let the model be the product automaton of {achievement cascade} ⊗ {maintenance
monitors} over all event traces.

### Safety

1. **No deontic double-bind (the headline property).** No reachable state in
   which an action _forced_ by a live achievement obligation _necessarily_
   violates a live standing prohibition:

   ```
   ¬ EF ( state s :  Obliged(B, α, s)  ∧  Forbidden(B, α, s)
                     ∧  noPermittedAlternative(B, s) )
   ```

   CTL `¬EF`: _no path reaches_ a bind. Note the `noPermittedAlternative`
   conjunct — under defeasible logic, if a defeater (Section 1.4b) downgrades
   the obligation or a HENCE offers an escape, it is _not_ a true bind. This is
   exactly the NZ-legislation race-condition class, lifted to loans.

2. **Good-standing invariant is preserved by every transition.**
   `□ ( GoodStanding ∧ achievementStep → GoodStanding' )` — the frame rule is
   sound: stepping a period never _silently_ clears a covenant. (Today this
   property is _violated by construction_ in jl4 because the SHANT is dropped.)

3. **Dividend safety.** `G ( covenantBreached → ¬ pay(dividend) )` holds on all
   traces.

### Liveness

4. **Achievement progress.** `□ ( startPeriod_k → ◇_{≤30} (pay(interest) ∨
declaredBreach) )` — every period either pays or breaches; no period hangs
   forever (jl4's deadline machinery, Machine.hs:977, guarantees the disjunct).

5. **Deadline-vs-precondition deadlock (a temporal property, NOT a safety one).**
   A `MUST α WITHIN d PROVIDED g` where `g` can only become true _after_ `d` is a
   guaranteed breach — a one-party deadlock:

   ```
   EF ( Obliged(B, α, deadline=d, guard=g)
        ∧  ¬ EF_{≤d} g )           -- g unreachable within the window ⇒ forced breach
   ```

   This is the loan analogue of "regulator MUST approve in 30 days but MAY NOT
   approve until an assessment with no deadline completes." It is checkable as
   reachability of the guard within the deadline horizon. jl4 will _detect_ the
   breach at runtime (the deadline fires, PROVIDED never matched, Machine.hs:990)
   but cannot _statically warn_ that the guard is unsatisfiable in-window.

### What model-checks against what

| Property                  | Logic             | Tool style        |
| ------------------------- | ----------------- | ----------------- |
| double-bind (1)           | CTL `¬EF`         | NuSMV / branching |
| frame preservation (2)    | LTL `□(...→...')` | SPIN/TLA+         |
| dividend safety (3)       | LTL `G(...)`      | SPIN              |
| achievement progress (4)  | MTL `◇_{≤d}`      | UPPAAL (timed)    |
| deadline/precondition (5) | CTL reachability  | NuSMV             |

---

## 3. Mapping to jl4's EXISTING constructs (grounded in the code)

### 3.1 Expressible TODAY

- **Achievement obligation, one-shot:** `PARTY B MUST pay interest WITHIN 30`.
  `Deonton{ modal = DMust, due = Just 30 }` (Syntax.hs:270–289). Deadline
  handling at Machine.hs:977–996: match-in-window → `HENCE`; deadline passes →
  `BREACH`/`LEST`.
- **Recurring achievement (renewal):** encode the next period as the `HENCE`,
  i.e. `... HENCE (PARTY B MUST pay interest WITHIN 30 HENCE ...)`. The cascade
  _is_ the period sequence. (`continueWithFollowup`, Machine.hs:1147.)
- **Sequential reparation:** `LEST` is the breach handler; `HENCE`/`LEST` run on
  the _remaining_ events (Machine.hs:986, 996, 1040, 1053) — a genuine
  sequential cascade.
- **Bounded prohibition:** `PARTY B SHANT sell collateral WITHIN d`.
  `modal = DMustNot`. Machine.hs:1038–1051: prohibited act seen in window →
  `LEST` or immediate `BREACH`; deadline passes with no act → `HENCE`/FULFILLED
  (Machine.hs:983–986). **This is real and implemented**, contrary to the stale
  comment in `examples/ok/prohibition.l4:84`.
- **Guarded action:** `PROVIDED g` on the `RAction` (Syntax.hs:296) is evaluated
  at `ScrutinizeEnvironment`/`ScrutinizeActions` (Machine.hs:1024–1054) — the
  action only "matches" if the guard holds. This is how leverage tests / "while
  a covenant is breached" conditions attach to an action.
- **Synchronous concurrency / conjunction & choice:** `RAnd`, `ROr`
  (Syntax.hs:206–207; Machine.hs:1060–1138). Both run over the **same (time,
  events)** stream — a CSL synchronous product. `RAnd` fails fast on the first
  breach and blames the **earlier-timed** one (Machine.hs:1080–1097, 1109–1121);
  `ROr` succeeds on the first fulfilment (1066, 1124–1131); an irreducible pair
  parks as a `ValROp` residual (`ValROp env op …`, ValueLazy.hs:58;
  Machine.hs:1137) and keeps watching later events.
- **AT1-style override, _partially_:** `ROr` of "MUST pay coupon" with a guarded
  permission gives you _a_ form of choice, and `PROVIDED` lets the coupon
  obligation itself be conditioned on `NOT breachesBuffer`. So a _hand-wired_
  defeater is expressible.
- **Visualization of the achievement skeleton:** `StateGraph.hs` already
  extracts states/transitions from the `HENCE`/`LEST` chains
  (StateGraph.hs:269–370), rendering FULFILLED/BREACH terminals — i.e. the
  Flood-&-Goodenough automaton of the _achievement_ part.

### 3.2 MISSING (the gaps, in priority order)

1. **A first-class standing / ambient maintenance obligation (the frame rule).**
   A `SHANT` is scoped to its own `WITHIN` window and is _consumed_ once that
   window closes (Machine.hs:983–986: deadline passed ⇒ FULFILLED ⇒ gone).
   There is **no construct that says "this prohibition holds for the whole life
   of the contract, across every HENCE step of every sibling obligation."** To
   get standing behaviour today you must manually `RAnd` the covenant into the
   contract _and_ re-inject it into every successor of every cascade — there is
   no automatic framing. `StateGraph.hs` confirms the omission structurally: it
   treats `RAnd` as two _independent_ sub-graphs (StateGraph.hs:240–248), so a
   covenant is never drawn as an invariant on the achievement states.

2. **A priority / override / defeasibility operator.** `RAnd` is symmetric
   conjunction; `ROr` is symmetric disjunction. There is **no asymmetric
   "r2 defeats r1" operator**. The "prohibition defeats obligation" relation can
   only be _simulated_ by threading a `PROVIDED NOT breachesBuffer` guard onto
   the obligation by hand; the defeasible _priority order_ itself is not a
   language construct, so it cannot be reasoned about or visualized.

3. **A frame axiom over fluents.** jl4 events are discrete `EVENT party action
time` happenings; there is no `HoldsAt`/inertia for time-varying _fluents_
   like `leverage`. A covenant on a continuously-varying quantity must be
   re-tested via a `PROVIDED`/observation event; there is no persistence
   semantics. (No fluent type in `Value`, ValueLazy.hs:48–70.)

4. **Static conflict detection (the double-bind, ahead of runtime).** The
   machine detects a _runtime_ breach when a deadline fires (Machine.hs:990–995),
   but there is no analyzer that, before any event stream, proves "no reachable
   state forces an action a standing prohibition forbids" — i.e. property (1)/(5)
   of Section 2 is not model-checked. This is the highest-value verification
   feature and the one the NZ and insurance pilots most directly motivate.

---

## 4. L4 syntax sketch (current syntax + clearly-marked PROPOSED)

### 4.1 What works today (current syntax)

```l4
DECLARE Party  IS ONE OF Borrower, Lender
DECLARE Action IS ONE OF
  payInterest   HAS amount   IS A NUMBER
  payDividend   HAS amount   IS A NUMBER
  deliverFinancials
  sellCollateral
  observeLeverage HAS ratio  IS A NUMBER

-- Achievement, recurring: interest each 30-day period, chained via HENCE
interestObligation MEANS
  PARTY Borrower
  MUST payInterest amt PROVIDED amt >= couponDue
  WITHIN 30
  HENCE interestObligation          -- renewal: next period is the HENCE
  LEST  BREACH BY Borrower BECAUSE "missed interest payment"

-- Bounded prohibition (REAL today): no collateral sale this window
noCollateralSale MEANS
  PARTY Borrower
  SHANT sellCollateral
  WITHIN 365
  LEST  BREACH BY Borrower BECAUSE "sold pledged collateral"

-- Dividend stopper, simulated with PROVIDED-guard (hand-wired defeater)
dividendGate MEANS
  PARTY Borrower
  MAY payDividend amt PROVIDED NOT covenantBreached
  WITHIN 30

-- Hand-wired "good standing" = covenant AND covenant AND obligation, synchronous
loanGoodStanding MEANS
  interestObligation RAND noCollateralSale RAND dividendGate
```

This _runs_, but `noCollateralSale` and `dividendGate` only watch until their own
`WITHIN`, and each `HENCE` renewal of `interestObligation` does **not** re-attach
them. So the "good standing" is only as long-lived as the shortest `WITHIN`.

### 4.2 PROPOSED minimal additions

**(P1) `ALWAYS` / standing-prohibition modifier (the frame rule).** A covenant
that is _automatically_ re-asserted across every HENCE step of every sibling for
the contract's life:

```l4
-- PROPOSED
leverageCovenant MEANS
  PARTY Borrower
  ALWAYS SHANT observeLeverage r PROVIDED r > 3.0
  -- no WITHIN: lives for the whole contract; framed across all transitions
```

Semantics (PROPOSED): an `ALWAYS SHANT C` desugars to a monitor that is
`RAnd`-composed with the _whole_ contract **and** automatically re-injected into
the `HENCE` and `LEST` of every `Deonton` reachable from it — i.e. an automatic
frame rule. Operationally: a standing `ValObligation` that is **not** retired
when an unrelated deadline passes; only an explicit release event clears it.

**(P2) Priority / defeater operator `DEFEATS` (override).**

```l4
-- PROPOSED  (AT1-style coupon)
couponRule MEANS PARTY Borrower MUST payCoupon WITHIN 30
bufferRule MEANS PARTY Borrower SHANT payCoupon PROVIDED wouldBreachBuffer

at1Coupon MEANS  bufferRule DEFEATS couponRule
-- reading: if bufferRule is applicable, couponRule's breach is suppressed
-- (failure to pay coupon is a PERMITTED omission, not a BREACH)
```

Semantics (PROPOSED): asymmetric — when the higher-priority rule's guard holds,
the lower rule's obligation is downgraded to permission and cannot produce a
`ValBreached`. This is the language-level realization of the `≻` order.

**(P3) Static `CHECK` directive for the double-bind / deadlock.**

```l4
-- PROPOSED, analysis-time (no event stream)
#CONFLICT loanGoodStanding
  -- ask the analyzer: ∃ reachable state where a MUST-forced action is
  -- SHANT-forbidden with no permitted alternative? report trace if so.
```

---

## 5. Lineage

- **Compositional / synchronous contracts.** Hvitved, _Contract Specification
  Language (CSL)_ and _A Trace-Based Model for Multiparty Contracts_ — the
  RAnd/ROr synchronous product, blame on the earlier-timed breach, and the
  irreducible-pair residual are CSL idioms (Machine.hs:1077–1138).
- **Achievement vs. maintenance obligations; defeasible deontic logic.**
  Governatori (and Governatori, Rotolo, Sartor) — the achievement/maintenance
  distinction, conditional/standing obligations, and the priority order `≻` that
  grounds `DEFEATS` (P2). Defeasible Logic / Formal Contract Logic.
- **Event calculus.** Kowalski & Sergot; Kowalski & Sadri — fluents,
  `HoldsAt`, and the **inertia/frame axiom** that the standing-covenant gap
  (Section 3.2 #1, #3) is missing.
- **Temporal & branching-time deontic logic.** LTL/MTL for bounded liveness
  (achievement), CTL `¬EF`/reachability for the double-bind and
  deadline-vs-precondition deadlock (Section 2); deontic O/P/F over a temporal
  base (von Wright lineage, normative-systems tradition).
- **Contract as automaton / "good standing."** Flood & Goodenough, _Contract as
  Automaton_ — the performing state as the conjunction of in-force maintenance
  obligations framed across transitions; already cited in `StateGraph.hs:9`.

---

## 6. Single strongest recommendation

**Add a first-class standing/ambient maintenance obligation with an automatic
frame rule (P1) — a covenant that persists across the entire HENCE/LEST cascade
without manual re-`RAnd`ing — and treat it as the semantic primitive from which
"good standing" and the static double-bind check are derived.** Everything else
(the `DEFEATS` override, the `#CONFLICT` analyzer) builds cleanly on top of it,
and it closes the one gap that is _unsound today_: jl4 silently drops a negative
covenant the moment its `WITHIN` window passes, so an agreement can model-check
as performing while a leverage or collateral covenant has, in fact, lapsed.
