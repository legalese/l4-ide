# Regulative Lowering: an explicit transition system from the evaluator, then the backends

**Status:** Proposal, written 2026-10-25. **On this branch only WP0 of §8, the dinner fixtures, is built; none of it has landed.**
The branch is `mengwong/lowering-ledger`, which lives on one machine: nothing of it is pushed or in a pull request, and `unstable` (`047311f36`, fetched 2026-10-26) holds none of its files.
No explorer, no emitter and no harness is in this tree; WP1 to WP6 are built on the other local branch, `mengwong/lowering-explore`, which is not this one.
Checked 2026-10-26 at `420bb6258`: the seven fixtures of `jl4/examples/explore/brief/` (`properties.l4`, the three designs, the two mutants and `refused-number.l4`) each exit 0 under `l4 run` with an `l4` built from this tree.
Their state counts and property verdicts are checked only on the explore branch, by the harness of WP4.
**Author:** Meng Wong, drafted by session pitch-Oct from the five verification probes of 2026-10-25.
**Parent:** [VERIFICATION-BACKEND-LOWERING-SPEC.md](VERIFICATION-BACKEND-LOWERING-SPEC.md), whose Phase 0 and Phases 2 to 4 this document narrows to one fragment and one fixture.
**Related:** [BOUNDED-DEONTICS-SPEC.md](../todo/BOUNDED-DEONTICS-SPEC.md) (object and assertion levels; contract time ruled discrete, T2, 2026-09-09), `specs/todo/lexipedia-superset/LTS-VISUALISER.md` §2.4 (counterfactuals come from running the evaluator, never from a second semantics), `doc/reference/regulative/lts-list.md`, `doc/reference/regulative/STATE-GRAPH.md`.

## 0. Why now: D1 has fired

The parent spec's register of deferred obligations says Phase 0 is owed on **"the first deontic, timed or defeasible property anyone wants to check"**, and records Meng's worry that Phase 1 ships and Phase 0 never starts.
A property of that kind was posed on 2026-10-24; the 2022 PDPA race (§7, D-L5) and LTS-VISUALISER's "can red be lit?" question came earlier, but neither was taken from L4 source to a checker, so the trigger fires here.
The scenario is a classic race condition, and this spec explores how L4 deals with it: Alice and Bob each mean to buy dinner tonight, neither wants to buy it if the other already has, so each checks whether dinner has been bought, finds it has not, and buys, and if their checks and purchases interleave, two dinners are bought.
The formal model checks one side, Alice's, with Bob's purchase as the environment's act; Bob's side is the same model by renaming.
The fix L4 offers is the atomic design (D3 in §1): the shared dinner ledger checks and accepts in one step.
In the model, Alice may buy dinner for both while dinner is unbought, and the arrangement opens at 18:00 with dinner unbought.
In **Sequence A** Alice checks at 18:05 and finds dinner unbought, Bob's purchase is recorded at 18:06, Alice tries to buy at 18:07 (a correct design blocks it), and the message "I bought it" reaches her at 18:08; in **Sequence B** Alice buys at 18:05:30 and the purchase is permitted.
The property checked is a safety property over every ordering of those events: **a dinner is bought only if the ledger's record said _open_ (nobody else had bought) at the instant the purchase took effect.**
That is deontic (a permission in force), temporal (record time against knowledge time) and, so far, not defeasible.

Measurements below were taken on the original private example and the probes' hand models; the dinner fixtures of §7 are specified, not yet built or run.
Names and times in quoted measurements are given in the dinner skin; the map from the original names is kept in the private record.
The original private example is encoded in L4 in the private probes repository (draft PR legalese/solutions#1, commit `b0de111`), with four hand-picked `#TRACE`s.
Four traces prove nothing about the other orderings, so on 2026-10-25 five probes modelled the same system by hand in six tools (Spin and NuSMV shared a probe) and checked it over every interleaving.
This document turns what the probes learned into the first lowering.

This is the narrowed Phase 0 the register asks for, not a way round it.
The D1 row in the parent spec is not edited; it gains a pointer here (§11), and its defeasibility half stays owed.

## 1. What the probes established

The shared brief (`BRIEF.md`) and the reports (`{tla,mcrl2,petri,maude,spin-smv}/REPORT.md`) are in the verification directory of the private `legalese/solutions` repo, pushed 2026-10-25 as draft PR legalese/solutions#1, commit `b0de111`.
Every number below is quoted from those reports.

One tool-neutral model, six state variables (`ledger`, `message`, `belief`, `alice`, `dinners`, `okAtBuy`), three designs for the purchase step, six properties tagged by logic class.

| design                | the purchase step                                         | P1 (safety)  | states / transitions (mCRL2; TLC and Maude agree) |
| --------------------- | --------------------------------------------------------- | ------------ | ------------------------------------------------- |
| D1, naive             | trust the bought-check's read                             | **violated** | 12 / 21                                           |
| D2, re-read then send | re-read the ledger, then buy as a second step             | **violated** | 15 / 30                                           |
| D3, atomic            | the ledger (the authority) checks and accepts in one step | holds        | 10 / 21                                           |

Findings that bind this spec:

1. **Unanimity.** TLC (and Apalache, inductively), mCRL2, TAPAAL `verifypn`, Maude, Spin and NuSMV agree on every P1 cell.
   Every D1 counterexample is Sequence A (§0); D2's is re-read, Bob's purchase, buy.
2. **The exhaustive check earns its keep on D2.** A timed replay of Sequence A _passes_ D2, because the 18:07 re-read sees Bob's purchase; only the search over all timings finds the window between a re-read just before 18:06 and a buy just after (TLA+ report, its timed module).
   Hand-picked traces, including the four in the original private example, cannot find it.
3. **The original private example is D3, but it is not the brief's model.** Its next-step function refuses a read older than the purchase, and its contract asks the ledger at the moment of purchase (Maude report §5; Spin report §5), so the example is right, and D1 and D2 have to be _written_ as fixtures to be found wrong.
   But the brief abstracts the scenario, not the example's L4, and the two differ in nine places (buy-blocker, 2026-10-25, checked against the example): Bob's purchase is a `GIVEN` parameter in L4 and a transition in the brief; L4 has no belief or message state; the message does not stop L4's Alice; a blocked purchase leaves L4's Alice in `the evening` (the contract) with her menu picks, where the brief's goes to `Stopped`; the bought-check is optional and repeatable in L4, once and required in the brief; after a purchase L4 continues with no menu picks left, the brief terminates; L4 has a closing deadline, the brief has none; `okAtBuy` has no L4 counterpart; the buy act carries its `ledger answered` payload, where the brief has a separate `NoAnswer` action.
   **So no bisimulation can hold between the original private example and the probes' models, with or without relabelling**, and §6.2 and §7 are written accordingly.
4. **The environment is not in the L4 source.** Every report had to hand-write `BobBuys`, `Deliver` and `NoAnswer`: in the original private example the ledger's record is a _parameter_ per `#TRACE`, so no explorer can vary it (TLA+ report §5, "must come from outside the L4 source").
5. **Data is the hard part, in every tool.** Strings (every `because`) do not travel; `NUMBER` becomes a bounded integer; lists and ledgers must be bounded or abstracted; `permission at`'s `filter`/`maximum` (the original private example's permission check) has to be unrolled or replaced by the booleans the properties read (all four reports §5).
6. **The tools already disagree on one fixture.** D1 satisfies P5/P6 without fairness in mCRL2, Maude, Spin and NuSMV, and violates them in TLC, because TLA+ lets the whole system stutter forever by default (TLA+ report §2; mCRL2 report §3 finding 1).
   This is the parent spec's named failure mode, "N backends each quietly encoding a slightly different notion", on the first fixture.
7. **Traps.** Spin's global fairness switch made P6 vacuous (caught by checking that a run in which Bob never buys exists); TAPAAL's LTL engine printed a counterexample with an impossible last step (caught by replaying it on the net); P2 and P4 hold by construction and needed mutants to show the checks can fail.
8. **Licences.** UPPAAL and nuXmv were not installed: academic or non-commercial terms, and UPPAAL needs registration; Legalese is a company.
   Dense time has exactly one usable home in this portfolio: TAPAAL's continuous-time engine `verifytapn` 1.3.3 ran P7 and found D1 failing P1 precisely when the attempt falls in [360, 480] s, between Bob's purchase and the message, with the counterexample's delays 300, 60, 60 being Sequence A's timing, offsets 300, 360, 420 from the opening (cross-checked 70/70 against an independent event-order enumerator).
   Its discrete-time engine `verifydtapn` segfaults, Real-Time Maude does not run on Maude 3.5.1, mCRL2's real-valued time is unusable in the macOS release.
   Integer clocks worked in TLC, Spin, mCRL2 and Maude, which is what T2 (discrete contract time) already asks for.
   Two TAPAAL traps for any later use: transition priorities are ignored, so the same-second tie rule cannot be expressed there, and the mCRL2 probe did not model it either (same-second steps are ordered nondeterministically); and **a default optimisation gave a wrong answer on the probe's encoding**: with the coloured engine's default colour partitioning, `EF is-fireable(Send_ledgerTaken)` on D2 returned FALSE, TRUE with `--disable-partitioning` or `-C`, and the unfolded net does fire it; the probe did not find whether the fault is in `verifypn` or in an unusual feature of its encoding, so this is not a claim of a soundness bug in TAPAAL, and two further silent encoding errors of the probe's own changed state counts (Petri report §3.5 for the coloured nets, §6 for the timed run).
9. **Scores** (installation / generation from L4 / headless pictures / timed / teaching, out of 5): TLA+ 5/4/3/3/3; Spin 5/4/3/2/3; NuSMV 3/4/3/2/4; mCRL2 4/3/4/2/2; TAPAAL 4/3/3/4/3 (revised after its timed track finished); Maude 5/3/3/2/3.
10. **The §4.3 shape does not run on `unstable` yet** (skeptic L2 on the bench of 2026-10-25, re-verified by the author the same day).
    `(THE JOIN)` as a value needs card B1 of EVERY-EACH-QUANTIFIER-SPEC §2.6, which lives on branch `lang/lifecycle-values`; the installed `l4` (built 2026-10-21, `--version` prints `dev`) rejects the original private example with `unexpected (`.
    With `the evening RAND the ledger` in that operand order Alice's rules read **zero** official rows, because each `RAND` operand runs over the whole trace before the next starts (consequences.md:417), so two of the example's four traces, Sequence B among them, block a legitimate purchase and still print `FULFILLED`; swapping the operands restores all four outcomes.
    The snippet as first printed also lacked a `record opening` act, without which every purchase is blocked.
    buy-blocker then measured the composition itself (2026-10-25, two builds: `lang/lifecycle-values` at 5279313a8 and the `unstable` binary of 2026-10-21, identical results): **neither operand order reads the record in event order**.
    After the left operand of a `RAND` reaches WHNF the right operand receives the whole event list (`jl4-core/src/L4/EvaluateLazy/Machine.hs:3223-3229`, `RBinOp1`), so with the ledger first Alice at 65100 reads two status events, including Bob's purchase at 65160 from her future, and with Alice first she reads none; a same-strand `COMMIT` then `RECALL` reads correctly.
    The failure exits 0, and the visible symptom is a breach blamed on the wrong party.
    This behaviour is **already ruled, not new** (buy-blocker's correction, 2026-10-25): NORM-LOG-SPEC card N10 (draft legalese/l4-ide#499, branch `spec/norm-log`, head 727b40aee) was measured 2026-09-26 and ruled 2026-10-11 by METRONOME: option B now, a run-time check on red-ink (history) reads that errors naming both sites when a later-running sibling writes a matching entry; option A as the goal, lockstep operands one event at a time with the settle walk interleaved, conditioned on a corpus evaluation differential and a ruling on a losing `ROR` alternative's entries; nothing of N10 is built.
    B covers red ink only; a plain `RECALL` of black ink, which a `COMMIT` read is, "stays order-dependent until A", and card N12 (open) proposes extending the check to black ink.
    `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md:3606` ("What it does not promise", on `unstable` since #640) gives the same `a RAND b` / `b RAND a` example and cites N10.
    STATE-AS-LEDGER-SPEC.md:161-163 and :239 are the earlier statement that the shared official record "needs ratification and a formal interleaving semantics".
    buy-blocker's measurement adds one data point to N10's §7 evidence: with a `COMMIT` read across operands, neither order reads the right value.
    A single chain over two parties (`PARTY p MAY act` with `p` bound by the event) is not expressible either ("could not find a definition for the identifier p"); the gap is scoped in `specs/todo/PARTY-BINDER-SPEC.md` (D-L9), which measured that `EVERY p … UPON EACH` puts the actor in scope but multiplies the live `MAY`s on a recursive chain, so the missing construct is one obligation whose bearer is whoever acts.
    So §4.3's option A has no working evaluator form today and waits on N10's goal A; §4.3 adds option C, which does run, and R-L2 is re-posed.
11. **`WF_vars(Next)` is the wrong fairness even over real steps.** With every edge a real step (§4.6's `lastAct`/`beat`), pausing forever satisfies `WF_vars(Next)`, so TLC reports P5 and P6 **violated** on D3 with a counterexample ending in repeated `Pause` steps, while weak fairness per labelled action (`WF_vars(Check) /\ WF_vars(BuyChecked)`) makes both hold, which is the probes' table (skeptic L7's stand-in `WfTest.tla`, 22 distinct states; re-run by the author 2026-10-25 with the same two results).
    §4.6 and §6.1 are written accordingly, and R-L6 is reversed.

## 2. The route: an explicit transition system from the evaluator

Each probe's §5 says the same thing in different words: the data half of a generator is easy and the hard half is **extracting finitely many control states with a guard and an effect per event from an L4 contract** (mCRL2 report §5), and then choosing how `PARTY`, `MUST`, `SHANT`, `ROR` and the ledger are read by a tool that has no notion of any of them.
Every one of those choices is a place for the lowering to diverge from the evaluator.

The tree already has the step relation, computed the only way LTS-VISUALISER §2.4 permits: by running the evaluator.
`L4.Lts.WhatIf` reads the **candidates** off a position's residual (`candidatesOf`: for every obligation in force, its own `(party, action)` act; for every distinct live deadline, a tick to just past it) and replays each one on the trace (`tryCandidate`), classifying what came back.
`l4 lts` renders one step of that.
**Iterating it to a fixpoint is the explicit labelled transition system of the contract, and it is faithful by construction, because the evaluator is the semantics.**

So this spec does not lower L4's regulative constructs to any tool.
It lowers the **explicit graph**, which every finite-state tool reads as a table.
The compiled, symbolic lowering (parties as processes, obligations as records, clocks as variables) that the probes mapped is deferred, with a register entry (§10), to be built when the explicit route hits a state space it cannot enumerate.

```
 .l4 contract + environment party + bounds
          │  l4 explore         (replay-driven BFS over positions; L4.Lts.WhatIf iterated)
          ▼
 explicit LTS: states = canonical positions, edges = acts and ticks, labels = boolean decisions
          ├──→ in-process: safety, reachability, counterexample as a #TRACE      (no external tool)
          ├──→ .aut (Aldebaran)   → mCRL2 ltscompare against the probe's hand model (bisimulation)
          ├──→ .tla + .cfg        → TLC (safety, liveness, fairness); Apalache (inductive)
          ├──→ .smv               → NuSMV (CTL and LTL, shortest witnesses)
          └──→ .pnml, .dot        → pictures (the visualiser, the teaching page)
```

What this buys: one semantics; counterexamples that are already L4 (§5.4); a harness whose oracle exists (§6).
What it costs: explicit state, so bounds (§4.4) and, eventually, the symbolic route.

## 3. The narrowed Phase 0, proposed for ruling

The parent spec's Phase 0 has four items.
For this fragment they resolve as follows; each is **proposed, not ruled** (R-L1 in §9).
Resolving is not discharging: the explicit route never lowers L4's constructs to any tool (§2), so items 1 and 2 are answered **for this route only** and reopen for the symbolic lowering (D-L1); what R-L1 asks is that Phase 0 does not gate the explicit route.
The graph of record is the explicit LTS of §4, not the structural graph `l4 state-graph` draws from every rule, which LTS-VISUALISER G9 says is unsound for reachability.

| Phase 0 item               | here                                                                                                                                                                                                                         |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Define the IR              | the explicit LTS of §4: positions, acts, ticks, labels. No new IR; `Position`, `Candidate` and `Verdict` in `L4.Lts.WhatIf` are the types                                                                                    |
| Pin a reference semantics  | the jl4 evaluator's replay, as LTS-VISUALISER §2.4 already rules; Maude stays a _backend_, not the host (Joe Watt's 2023 semantics does not load on Maude 3.5.1 and has no state or guards, Maude report §5b)                |
| Defeasibility strategy     | **not exercised by this fragment**: the dinner race has no priorities, exceptions or contrary-to-duty chains. Stated, not solved; D1's defeasibility half stays in the parent register                                       |
| Assertion-language surface | **deferred**. Properties are boolean decisions over the position (§5), which needs no syntax. The surface syntax (parent Phase 3) is owed when the first property cannot be written that way; liveness is the likely trigger |

## 4. The explorer: `l4 explore`

### 4.1 Position and state identity

A **position** is what `L4.Lts.WhatIf.position` computes: the residual contract, the ledger (`RECORD`ed values), the clock, the marking.
Two positions are **the same state** when their canonical forms are equal.
The canonical form is: the residual after `reifyExpr` with source ranges erased and binders renamed in order of occurrence; a **projection** of the ledger; the clock **dropped** unless a live deadline reads it (§4.5).
The projection keeps every ledger that some rule or property `RECALL`s, in recorded order (since `RECALL ALL` reads order), and drops every ledger that is only ever written.
That is decided statically from the `RECALL` sites of the module and the property file, so it is not a ruling; on the original private example it is what makes exploration terminate at all, because the contract appends a time-stamped string to `decision log` on **every** act, and no two paths would ever merge if the log were in the state (buy-blocker, 2026-10-25).
A write-only ledger is audit output, and the coverage line names each one dropped.
Without a canonical form a contract like `the evening`, which recurses through `HENCE` with changing menu picks, never terminates (TLA+ report §5: "the set of reachable residual contracts must be finite").
The canonicalisation is **assumed, not ruled**, and it is the one place a faithfulness bug can hide silently: two positions the evaluator would treat differently, merged.
The harness's bisimulation check (§6.2) is the guard against it.

### 4.2 Candidates, and the finite enumeration of binders

Candidates are `candidatesOf`'s, unchanged: every obligation in force contributes its act, whatever its modal (`MUST`, `MAY` and `SHANT` alike, checked against `candidatesOf`'s body on 2026-10-25, which case-splits on nothing but the residual), and every distinct live deadline contributes one tick to just past it.

One change is needed.
An action pattern that **binds** a variable names a set of acts; `WhatIf` answers for the set by replaying **one** witness (`BoundAct`, WhatIf.hs:263-315; `witnessFor`, :898-915, by three routes: the other side of a `PROVIDED` comparison, else `simplestOfType` (:1057, `0` for a `NUMBER`, `""` for a `STRING`), else, for a binder that is the whole action, the act the `#TRACE` itself wrote).
Exhaustive exploration cannot do that.
`l4 explore` enumerates the set when the binder's type is **finite**: `BOOLEAN`, or a `DECLARE … IS ONE OF` or a record whose every field is finite by the same rule; it **refuses, naming the binder, its type and the offending constructor**, when a field is `NUMBER`, `STRING` or `LIST OF …`, and still explores the finite constructors beside it.
A binder that is the whole action (`PARTY Alice MAY act` in the original private example) has no recorded type today (WhatIf.hs:985), so the explorer recovers it from the obligation's action type; under this rule the example's `Act`, three constructors with one `BOOLEAN` field, is finite: four acts (skeptic L4, 2026-10-25; the first draft said the example had one `BOOLEAN` binder, which was wrong).
The refusal is loud, ends in the coverage line (§4.4), and `l4 explore` **exits non-zero** on any refusal or `unknown` verdict, so a CI job cannot read a refused run as green; house style elsewhere exits 0 on a deferral, and this is the exception.
A tool-chosen sample is never offered.
An **author-declared** finite domain per binder, with the bound printed and the verdict reported as "holds within <domain>", is the route every probe took for `NUMBER` (spin-smv report :282, mcrl2 :134, tla :298) and is registered as D-L7, not built here.

### 4.3 The environment is a party

Finding 4 of §1 is the first thing the fixtures have to fix: a timing fact the execution system supplies has to be an **event**, or no explorer can vary it.
In L4 that is one more party with a `MAY`:

```l4
GIVETH A DEONTIC Party Act
`the ledger` MEANS
    PARTY Ledger
    MAY   `record Bob's purchase`
    WITHIN 0 OF closing
    HENCE COMMIT `dinner status record` IS (`Status event` (THE JOIN) taken)
          HENCE FULFILLED
    LEST  FULFILLED
```

composed with Alice's contract by `RAND`, with a sibling `` `record opening` `` act of the same shape (without it every purchase is blocked), and read by the rules through `` RECALL ALL OFFICIAL's `dinner status record` ``.
This is **option A**, and on the current evaluator it does not work (§1 finding 10): a `RAND` runs each operand over the whole trace before the next (consequences.md:417, Machine.hs:3223-3229), so a cross-operand `RECALL` reads either nothing or the future, in neither order the record as it stood; and `(THE JOIN)` as a value needs card B1 (`lang/lifecycle-values`), not on `unstable`.
Option A therefore waits on NORM-LOG-SPEC N10's goal A, lockstep operands (ruled 2026-10-11, METRONOME; §1 finding 10), with N10's own conditions; D-L8 points at it rather than registering anything new; until then the explorer and the ledger **refuse** a `RAND` whose operands read each other's records, loudly, which is N10's option B extended to black ink (N12, open).
**Option C**, which runs today, is one chain and one party whose closed action type names the actor inside the act.
The snippet below is a sketch with elisions, not a fixture; buy-blocker ran a probe of this shape (buy-blocker's option C probe, in that session's scratchpad), not this text:

```l4
-- unrun sketch
DECLARE Act IS ONE OF
    `Alice checks whether dinner is bought`
    `Alice buys dinner`               HAS `ledger answered` IS A BOOLEAN
    `ledger records opening`
    `ledger records Bob's purchase`
    `Messages delivers the message`

`the evening` MEANS
    PARTY World
    MAY   act
    WITHIN 0 OF closing
    HENCE CONSIDER act
          WHEN `ledger records Bob's purchase` THEN COMMIT `dinner status record` IS … HENCE `the evening`
          …
```

Every act is an event the explorer can vary and the ledger can serialize, a same-strand `COMMIT` is read by the next step in event order (buy-blocker's control), and the probes' labels (`BobBuys`, `Deliver`, `CheckBought`, …) map one for one, so the §6.2 bisimulation is unaffected.
What C loses is `PARTY` as the actor: who did what is a constructor name, not a party, until D-L8 lands and the fixtures can be rewritten as A with no change to their graphs.
A party binder in the subject (`ANY p MAY act`, proposed in `specs/todo/PARTY-BINDER-SPEC.md`, D-L9) would recover `PARTY` as the actor on C itself for an all-`MAY` chain, without waiting for D-L8, because one chain has no cross-operand read; it does not lift the silent limit in the next paragraph.
C has a second, **silent** limit, measured by buy-blocker on 2026-10-25 (the 2026-10-21 `unstable` binary, no B1 needed): while any `MUST` or `SHANT` is pending in the chain, events of the other parties are dropped, because the obligation waits for its one action and a non-matching event goes nowhere; Bob's purchase arriving during `PARTY Alice MUST Alice pays WITHIN …` was never `COMMIT`ted, the official record stayed empty, a later read saw 0 and breached with the blame on Alice, exit 0.
So C is sound only for a contract whose chain is a `MAY` over every act at every point, which the original private example and the brief's three designs are; a fixture with a real obligation and environment acts arriving during it needs A (D-L8), or has to encode the deadline as data inside a `World` `MAY`, which flattens the regulative layer and is not called L4's encoding here.
The explorer and the ledger therefore **refuse** a C-shaped contract whose chain contains a `MUST` or `SHANT` with other parties' acts in its action type, loudly, until D-L8.
Positive control for C's reads: with the opening at 64800 and Bob's purchase at 65160, Alice reads one status event at 65100 and two at 65220, and a trace expecting two at 65100 breaches (buy-blocker's option C probe).
One trap for fixture authors: `WITHIN 75600` on a recursive `MAY` re-arms from each act, so `WAIT UNTIL 75601` leaves the chain pending; use the anchored `WITHIN 0 OF closing`, as the original private example does.
WP0 builds C; its acceptance compares the dinners-bought ledger and not the `FULFILLED` line, since every trace prints `FULFILLED` under a wrong read.
`COMMIT` rather than `RECORD` because the ledger's record binds every party, so it belongs to the official record (STATE-AS-LEDGER R1), and the parser accepts `RECALL ALL OFFICIAL's` (`jl4-core/src/L4/Parser.hs:3023`); Alice's own decision log stays a `RECORD` (Meng, 2026-10-25; the operational spec's §3.8 gives the reason).
Delivery of the message "I bought it" is the same shape (`PARTY Messages MAY deliver`).
No new syntax: R-V3 measured a new directive at fifteen compiler-enforced sites plus two that fail silently, and nothing here needs one.
Whether the environment is written into the contract (this) or supplied as an alphabet beside it is **R-L2** (§9); this spec builds the former.

### 4.4 Bounds and the coverage line

One full replay per candidate (`WhatIf` header, "Cost"), so the explorer is bounded three ways, each a flag with a default: depth of events, number of states, and the clock (a `WITHIN 0 OF closing` on every party bounds it from inside the contract, which is the preferred form).
Every run ends with a **coverage line** in the manner of R-V8: states and transitions explored; whether the frontier was exhausted or which bound stopped it; every binder refused and why; every candidate `WhatIf` listed as _untried_ and why.
"A run that explored nothing proves nothing, and a checker that never started can look exactly like one that found no violation" (BRIEF.md); the positive control of §6.3 is the other half of that sentence.

### 4.5 Time

Contract time is discrete (T2).
`candidatesOf` already offers, per distinct live deadline, a tick to **just past it** (`tickPast`), and that is half of a region abstraction.
The other half is new: every act in a `#TRACE` carries a `NUMBER` time, so the explorer has to **choose** the instant at which a candidate act fires.
The representatives are **regions**: every recorded event time and every live deadline **exactly**, plus one interior instant in each open interval between consecutive ones, plus one instant after the last.
The boundaries are not optional: the fixture's tie rule (Bob's purchase recorded at _t_ blocks Alice's purchase at _t_) lives at exactly _t_ = 360, TAPAAL's D1 window is the closed interval [360, 480], and both mCRL2 and TAPAAL found the same-second ordering question at 360; a scheme that fires acts only at `clock + 1` never visits _t_ = _r_ and would miss all three (buy-blocker, 2026-10-25; the Petri probe's `explicit_timed.py` enumerated exactly these regions, cross-checked 70/70).
This is sound when guards compare times only against recorded event times and deadlines, as `permission at` does.
A fixed grid (`--grid n`) is the fallback for a guard that reads the clock arithmetically (an interest accrual), on the stated condition that every event time and deadline in the fixture is a multiple of _n_: the example's times happen to be multiples of 30, which is the only reason two probes' 30-second grids hit its boundaries.
The coverage line says which scheme was used.
**Assumed, not ruled.**
The explorer therefore keeps the clock out of the state (§4.1) except where a live deadline reads it, and treats "Alice waits" as the tick candidate.
A **dense** clock is out of scope (T2), and so, by licence, is UPPAAL; the timed cross-validator is TLC or mCRL2 over the integer clock the probes already ran (§1 finding 8).
Same-instant ordering is **not** something clock models give for free (the mCRL2 probe did not model the tie, so same-second steps are ordered nondeterministically and the question is left open, mcrl2/REPORT.md:173 and :185; the probes' README lists it among its traps).
The fixture's hand rule, Bob's recorded purchase beats Alice's purchase in the same second, lives in the original private example's `permission at`, labelled there "assumed, not ruled", and under the §4.3 re-encoding it governs only a query made after both events are recorded; between two **events** in the same second the evaluator keeps authored order (a stable sort by `AT`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:6959-6962`), so the explorer and the ledger both decide the tie by event order, and a purchase by Alice recorded before Bob's same-second purchase is permitted, where the `GIVEN`-list encoding blocked it.
That is a visible change of answer and is on the bench as R-O1 (operational spec); emitted models are not asked to re-derive any tie rule.

### 4.6 Stuttering, decided

Finding 6 of §1 has to be settled before any backend is called L4's.
In L4's explicit graph a **pause is an act**: `buy dinner FALSE` is a real event whose replay leaves the canonical state unchanged, so it is a self-loop labelled with that act.
There is no implicit stutter: a state with no candidate is terminal, and the explorer gives terminal states a self-loop labelled `terminal` so that no tool reports them as deadlocks.
Consequence: D1, which has no pause act, **satisfies** "eventually buys or stops" without fairness, which is the mCRL2, Maude, Spin and NuSMV reading.
The TLA+ emitter (§6.1) has to make TLC agree, and the obvious way is wrong: in TLA+ a step that changes no variable _is_ a stutter, `⟨Next⟩_vars` requires `vars' ≠ vars`, so a self-loop emitted as `UNCHANGED vars` is invisible to `WF_vars(Next)`, and since `BobBuys` stays enabled in the paused and bought states and does change `vars`, `WF_vars(Next)` would **force Bob to buy eventually** and make "if Bob never buys, Alice eventually buys" pass vacuously, the trap Spin's `pan -f` fell into (buy-blocker, 2026-10-25; spin-smv report §3.3).
So the emitter gives every edge a real step: each transition also writes `lastAct' = "<label>"` and flips a bit `beat' = 1 - beat`, so a self-loop changes `vars` and a pause is a step TLC can see.
That alone is not enough, and the first draft of this section got it wrong: with every edge a step, pausing forever satisfies `WF_vars(Next)`, and TLC then reports P5 and P6 **violated** on D3 with a counterexample ending in repeated `Pause` steps (§1 finding 11).
So fairness is stated **per labelled action**, as the TLA+ probe did by hand (tla/REPORT.md:66-70): weak fairness on each of Alice's non-pause acts and on the ledger's answering acts, none on the pause, none on the environment's acts (`BobBuys`, `Deliver`), none on `terminal`; under that `FairSpec` P5 and P6 hold on D3, and the non-vacuity control of §6.3 is still violated, as it must be.
The emitter derives the list from the graph: every label whose actor is Alice, or the ledger answering her, and whose edge is not a self-loop; the ledger's recording of Bob's purchase is the environment's act and gets none.
**Assumed, not ruled** for the step encoding (a rule author never sees it); the per-action list is R-L6, reversed from the first draft, and guarded by the non-vacuity control of §6.3.

## 5. Properties

### 5.1 Properties are boolean decisions over the position

A property is an ordinary L4 `DECIDE` of type `BOOLEAN` whose inputs are what the position holds: the ledger (`RECALL ALL …`) and the contract's standing (`FULFILLED`, `BREACH BY p`, in progress).
P1 of the brief, in L4:

```l4
GIVEN dinners IS A LIST OF Dinner
      checks  IS A LIST OF `Acceptance check`     -- COMMITted by the accepting step: was the record open at that instant?
GIVETH A BOOLEAN
`every dinner was accepted while open` MEANS
    all (GIVEN c YIELD c's `open at acceptance`) checks
```

The explorer evaluates every property at every state and **labels** the state.
No new syntax, no new directive, no property language: the assertion surface of parent Phase 3 is deferred (§3), and R-V3's cost argument applies.

### 5.2 What is checked in-process

On a finite explicit graph two classes need no external tool:

- **Safety / invariant** (`AG p`, `□ p`): no reachable state is labelled `¬p`.
- **Reachability** (`EF p`): some reachable state is labelled `p`.
- **Safety over steps** (`□(p ⇒ □p)`, P4): no edge from a `p` state to a `¬p` state.

`l4 explore --check` reports each in R-V8's three verdicts: `holds`, `violated` with a counterexample (§5.4), `unknown` with the bound or refusal that stopped it.

### 5.3 What goes to a backend

**Liveness** (`◇ p`, `□ q ⇒ ◇ p`) and **fairness** need cycle detection under a fairness assumption, and their counterexamples are lassos, not paths.
They go to the emitted TLA+ (TLC, `WF_vars` on Alice's acts and on the ledger answering, as BRIEF.md specified) and NuSMV (`JUSTICE`), and the in-process checker reports them `unknown (liveness: run the emitted model)` rather than guessing.
Both tools' readings are then compared (§6.3).

### 5.4 Counterexamples are `#TRACE`s

Every explored state is reached by a path of acts and ticks from the contract's `AT t`, and that path **is** a `#TRACE`.
The explorer prints a violated safety property's counterexample as runnable L4 source:

```l4
-- `every dinner was accepted while open` violated after 3 events (l4 explore, D1 fixture)
#TRACE (`the evening` `the arrangement` (LIST `Dinner for two`)) RAND `the ledger` AT 64800 WITH
    PARTY Alice  DOES `check whether dinner is bought`  AT 65100
    PARTY Ledger DOES `record Bob's purchase`           AT 65160
    PARTY Alice  DOES (`buy dinner` TRUE)               AT 65220
```

Pasted into the fixture file it reproduces the violation under `l4 run`, which is the two-oracle discipline of R-V5 for paths: the evaluator confirms what the explorer found.
This closes the parent spec's open question on witness translation for this route (§11).
A lasso from TLC or NuSMV is lifted the same way, as a `#TRACE` for the stem and a note naming the repeated acts.

## 6. Emitters and the cross-validation harness

### 6.1 Emitters

All three read the explicit graph; none interprets L4.

| target             | form                                                                                                                                                                              | why                                                                                                                                                                                                                                                                                                                                                                                                                                                               | licence         |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `.aut` (Aldebaran) | one line per edge, `(from, "label", to)`                                                                                                                                          | mCRL2 and CADP read it directly; it is what `pbessolve`'s evidence already comes out as (mCRL2 report §3)                                                                                                                                                                                                                                                                                                                                                         | mCRL2: Boost    |
| `.tla` + `.cfg`    | `VARIABLE s`, `Init == s = 0`, `Next == \/ (s = i /\ s' = j) …`, labels as `DEFINE`d predicates, `INVARIANT`/`PROPERTY`, `FairSpec` with weak fairness per labelled action (§4.6) | best install (one 2.2 MB MIT jar), Apalache for inductive proofs, `-dump dot` for pictures; the probe's own recommendation                                                                                                                                                                                                                                                                                                                                        | MIT; Apache-2.0 |
| `.smv`             | `VAR s : 0..n`, `TRANS`, `DEFINE` labels, `SPEC`/`LTLSPEC`, `JUSTICE`                                                                                                             | the easiest encoding to generate (Spin report §5), CTL beside LTL, shortest counterexamples, `AG`/`EF` as the teaching door                                                                                                                                                                                                                                                                                                                                       | LGPL            |
| `.pnml`, `.dot`    | the graph as a one-safe net / as GraphViz                                                                                                                                         | the visualiser and the teaching page, as a **picture target**; TAPAAL reads PNML for untimed checks (run with `--disable-partitioning`, every verdict replayed, a zero-state "holds" treated as no run: README.md:81-86), but its dense-time engine reads hand-built timed-arc nets with ticket places (petri/REPORT.md:405-419) that an untimed explicit graph cannot supply, and T2 rules contract time discrete, so PNML is not a door to a timed check (D-L6) | TAPAAL: GPL     |

The comparison's own order ("Recommendation (not ruled)", `verification/README.md` in legalese/solutions#1) is TLA+ first, PNML second, NuSMV third.
This spec amends it (skeptic L7, 2026-10-25): **TLA+ and NuSMV are built together as the first pair**, because §6.3 quotes no liveness verdict until TLC and NuSMV agree, so NuSMV cannot be third; **PNML comes last**, as a picture target (above).
`.aut` is not a target in that sense: it is the form the §6.2 bisimulation reads, and it comes first in the build only because the harness needs it before any verdict is trusted; it makes mCRL2 (119 MB, Boost licence) a required harness tool through `ltscompare`.
That order is R-L7 below, because the probes left it unruled.
Spin is not a first target: its edge, parties as processes and messages as channels, is an edge for a _symbolic_ lowering, and its global fairness switch is a trap (§1 finding 7).
Maude is not a first target: Joe Watt's semantic embedding needs a Full Maude port (register, §10).

### 6.2 Faithfulness is measured, not argued: bisimulation against the hand models

The probes left five hand-built models of **one** system with state counts 12/21, 15/30 and 10/21.
The acceptance test for the explorer is that **its graph for an L4 encoding of that same system is bisimilar to the probe's mCRL2 model**, modulo hiding and relabelling: emit `.aut`, run `ltscompare -ebisim` (or `-ebranching-bisim`) against the probe's data-free `dN-viz` LTS, and fail on inequivalence.
Two consequences of §1 finding 3:

- The L4 under test is **not** the original private example; it is `brief/d1.l4`, `brief/d2.l4`, `brief/d3.l4` (§7), which encode the brief's six variables and transitions one for one, with Bob's purchase and the message's delivery as acts (of one `World` party naming the actor in the act, §4.3 option C, until D-L8), belief as recorded state, and `Stopped` as termination.
  Then the test is about the lowering and not about two different models.
- The reference LTSs are **vendored** into l4-ide as text `.aut`, because they come from the private `legalese/solutions` repo and l4-ide's CI must not depend on it (l4-ide's CLAUDE.md §1.2, the dmnmd reasoning).
  They do not exist in solutions yet: `run.sh` writes no `-viz` LTS, only the tracked sources `verification/mcrl2/build/d{1,2,3}-viz.mcrl2` are there (skeptic L5, 2026-10-25).
  From those sources, `mcrl22lps dN-viz.mcrl2 dN.lps` then `lps2lts dN.lps dN-viz.aut` under mCRL2 202607.0, run by the author on 2026-10-25, gave `des (0,21,12)`, `des (0,30,15)` and `des (0,21,10)`, with labels of the form `step(t)`.
  Those files carry the original action names and are not the vendored ones: WP0 regenerates the reference `.aut` files from relabelled mCRL2 sources, structure-preserving (the same state and transition counts, labels in the dinner skin), and the public harness vendors only the relabelled files; the label map from the original action names to the dinner names is kept in the private record.
  Beside each vendored file the harness records the two commands, the mCRL2 version, the SHA-256 of its relabelled source and of the `.aut` when built, and the solutions commit of the source it was relabelled from, so a changed brief cannot leave the bisimulation green against a stale oracle.
  Compare against the `-viz` build, whose labels are `step(t)`; the plain `dN.lts` labels carry the whole post-state.

A generated model and a hand model agreeing up to bisimulation is the executable faithfulness the parent spec asks for, and the strongest guard on §4.1's canonicalisation.
Where they are not bisimilar the harness prints the distinguishing trace, which is itself a `#TRACE` (§5.4) and so a bug report that runs.

### 6.3 Verdict agreement, positive controls, mutants

- Every property on every fixture: in-process verdict, TLC verdict, NuSMV verdict must agree; disagreement is a harness failure with no tolerated kind, because §4.6's per-action fairness is what makes TLC agree, and a disagreement is a bug in an emitter, not a reading to average.
- A tool that is not installed makes its cells **unknown**, never **holds**, and the release gate fails on any unknown liveness cell; NuSMV is in neither Homebrew nor conda (spin-smv/REPORT.md:48), so CI pins its archive and SHA-256.
- **Positive control:** D1 must violate P1 and the counterexample must be Sequence A. "If D1 passes P1 in your tool, suspect your encoding before you believe it" (BRIEF.md).
- **Mutants:** P2 and P4 hold by construction (§1 finding 7); the fixtures ship one mutant each (a cancel act; a double buy) under which they fail, so a green run is known to be able to go red.
- **Replay every counterexample** on the evaluator before printing it (TAPAAL trap b).
- **Non-vacuity of fairness.** Under every fairness assumption the harness uses, the claim "the environment eventually acts" (`<>(ledger = Taken)` in the brief's terms) must be **violated**: a fair run in which Bob never buys must exist, or "if Bob never buys, Alice eventually buys" has passed on an empty set (Spin's `pan -f` trap; TLA+ report §2's two controls).
  This is an acceptance item, not advice.

## 7. Fixtures

**`jl4/examples/explore/brief/`: the lowering test.** The brief's model, encoded one for one in L4, in the dinner skin of §0, as R-L5 ruled for the public tree: Alice, who may buy dinner for both while it is unbought; the dinner ledger, the authority that records each purchase and answers each attempt; Bob's purchase as the environment's act; the message "I bought it", delivered after it.
The fixtures are specified here, not yet built or run:

| file                | design                                                                                                              | expected                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `d1-naive.l4`       | Alice buys on the belief her check left                                                                             | P1 violated, the three-step counterexample; bisimilar to `d1-viz.aut`; 12 / 21                                                   |
| `d2-reread.l4`      | re-read as one act, buy as another                                                                                  | P1 violated, re-read, Bob's purchase, buy; bisimilar to `d2-viz.aut`; 15 / 30                                                    |
| `d3-atomic.l4`      | the ledger checks and accepts in one act                                                                            | P1, P2, P4 hold; P3 reachable; bisimilar to `d3-viz.aut`; 10 / 21                                                                |
| `properties.l4`     | P1 to P6 as boolean decisions over the ledger and standing                                                          |                                                                                                                                  |
| `mutants/`          | `d3-cancel.l4` (P4 must fail), `d3-double.l4` (P2 must fail)                                                        |                                                                                                                                  |
| `refused-number.l4` | a permission whose act carries a `NUMBER` payload                                                                   | refused, naming the binder, its type and the constructor; exit non-zero; the finite constructors beside it still explored (§4.2) |
| `reference/*.aut`   | the probes' `-viz` LTSs, relabelled to the dinner skin (§6.2) and vendored as text, with the mCRL2 version recorded |                                                                                                                                  |

D1 and D2 are **wrong on purpose** and live beside a README that says so, so that nobody fixes them.

The original private example (§0) is kept in the private probes repository (legalese/solutions#1); no fixture, work package or acceptance item of this spec depends on it.

Owed, not promised: the 2022 PDPA breach-notification race (parent Phase 3, "reproduce the regulatory race condition as a regression fixture") has a hand-built UPPAAL model and no L4 encoding on record; it is listed in §10, not here.

## 8. Work packages

Sized for a Workflow of at most ten agents.
WP0 gates everything; WP2 and WP3 run in parallel after WP1; WP4 after both.
Each agent's final message states what it did **not** attempt.

| WP                         | does                                                                                                                                                                                                                                                                                                                                                                                         | files                                                                    | acceptance                                                                                                                                                                                                                                                                                                                              | oracle                                             |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| **WP0 fixtures**           | encode the brief's model as §7's three dinner-skin contracts plus properties and mutants; regenerate the three `-viz` `.aut` references from relabelled mCRL2 sources and vendor them with their commands, mCRL2 version and SHA-256 (§6.2); re-encoding the original private example is tracked privately, with its own preconditions, and is not a work package of this spec               | `jl4/examples/explore/brief/*`                                           | `l4 run` green on all; hand-written `#TRACE`s of the three-step D1 path on `brief/d1.l4` show the bad purchase; each fixture's dinners-bought ledger compared trace by trace, not its `FULFILLED` line, since every trace prints `FULFILLED` under a wrong read (§4.3); the relabelled `.aut` files keep the counts 12/21, 15/30, 10/21 | BRIEF.md's transitions, read one for one           |
| **WP1 explorer**           | `l4 explore`: BFS over positions via `L4.Lts.WhatIf`; canonical state (§4.1); finite-binder enumeration and loud refusal (§4.2); bounds and coverage line (§4.4); terminal self-loops (§4.6); `--json` and `--dot`                                                                                                                                                                           | `jl4-core/src/L4/Lts/Explore.hs`, `jl4/app/L4/Cli/Explore.hs`, `Main.hs` | state and transition counts 12/21, 15/30, 10/21 on the three fixtures; terminates; coverage line names the refused binder on a fixture with a `NUMBER` payload                                                                                                                                                                          | the probes' counts (BRIEF.md and the five reports) |
| **WP2 in-process checker** | `--check`: label states with the boolean decisions; safety, reachability, step-safety; three verdicts; counterexample as a `#TRACE` that `l4 run` reproduces                                                                                                                                                                                                                                 | `L4/Lts/Explore/Check.hs`                                                | D1 and D2 violate P1 with the expected paths; D3 holds; P3 reachable everywhere; mutants fail P2/P4; every printed counterexample replays red                                                                                                                                                                                           | BRIEF.md's P1 to P4 table                          |
| **WP3 emitters**           | `.aut` first (the oracle), then `.tla`+`.cfg` and `.smv` together, then `.dot`, then `.pnml` last (§6.1 order); fairness per labelled action, §4.6 and §5.3                                                                                                                                                                                                                                  | `L4/Lts/Explore/Emit/*.hs`, `l4 explore --emit`                          | files load in mCRL2 (`ltsconvert`), TLC and NuSMV without edits, where installed                                                                                                                                                                                                                                                        | each tool's own parser                             |
| **WP4 harness**            | bisimulation against the vendored `reference/*.aut` (§6.2); verdict agreement across in-process, TLC, NuSMV incl. P5/P6 under fairness; positive control; non-vacuity of fairness; mutant checks; one `make`/`cabal` target that marks any tool not installed as **unknown**, loudly, fails the release gate on an unknown liveness cell (§6.3), and never reaches into `legalese/solutions` | `jl4/examples/explore/harness/`, CI job                                  | all of §6.3 green on the three `brief/` fixtures; `<>(environment acted)` violated under every fairness used                                                                                                                                                                                                                            | the vendored `.aut` files                          |
| **WP5 docs**               | `doc/reference/regulative/explore.md` one sentence per line: what the graph is, what the coverage line means, loud and silent failures sorted (CLAUDE.md rule 7); update `lts-list.md`'s "picture may follow" note                                                                                                                                                                           | `doc/`                                                                   | `doc/test-docs.sh` green                                                                                                                                                                                                                                                                                                                |                                                    |
| **WP6 parent edits**       | §11's four edits to `VERIFICATION-BACKEND-LOWERING-SPEC.md`                                                                                                                                                                                                                                                                                                                                  | that file                                                                | diff is four hunks                                                                                                                                                                                                                                                                                                                      |                                                    |

Not in any package, by design: a symbolic lowering; a property syntax; dense time; UPPAAL; the PDPA fixture; Maude.

## 9. Rulings (ruled 2026-10-25 on the Lowering Rulings bench)

Meng marked every card on the bench on 2026-10-25 between 14:32 and 14:41 UTC, on its version 4, under the legalese.com account (https://claude.ai/artifact/91v4P8RffWfqxrP7Ba5u96); the marks were copied verbatim the same evening into the bench's regenerated copy under the gmail account, https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye, which is the link cited below; the bench page itself narrates the original case and is not to be made public without the same re-skin.
Each ruling is recorded on its line; the text above each ruling is the proposal as it stood when marked, re-skinned after the mark under L5 into the scenario of §0, and the marked text is in the private record.

These are visible to a rule author or a reader of the output, so they are Meng's; everything else in this document is assumed and labelled.

- **R-L1 Phase 0 and the explicit route.** Rule that parent Phase 0 does not gate the explicit route: §3's table answers items 1 and 2 (IR, reference semantics) for this route only, and they reopen for the symbolic lowering (D-L1); defeasibility (D-L3) and the assertion surface (D-L2) stay in the parent register with their triggers. This is the first ruling that makes the jl4 evaluator the reference semantics for deontic verification (BACKEND-PORTFOLIO's I2 has ruling P1 still proposed; LTS-VISUALISER §2.4 is scoped to P2 and declines the fan-out), so it is a ruling, not a confirmation, and the bisimulation of §6.2 is the only oracle independent of the evaluator. Recommendation: accept; the alternative is a Phase 0 that blocks on a property nobody has yet asked.
  **Ruled 2026-10-25, card L1: accept**, with the card's three conditions (D-L1 reopens parent items 1 and 2 for the symbolic route; D-L2 and D-L3 stay in the parent register with their triggers; WP6's four edits); Meng's note: "Agree with the three conditions." Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#L1.
- **R-L2 Where the environment lives.** A: in the contract, as parties with `MAY` composed by `RAND` (§4.3), which needs NORM-LOG-SPEC N10's goal A (lockstep operands, ruled 2026-10-11, not built; D-L8 points at it) and card B1 before it runs; B: as an alphabet of external events supplied beside the source, a new input surface; C: in the contract, as acts of one chain whose closed action type names the actor (§4.3), which runs on today's evaluator for a chain that is a `MAY` at every point, and **silently drops other parties' events while a `MUST` or `SHANT` is pending** (§4.3, measured). Recommendation: C now, for WP0 and the operational lowering, whose fixtures are all-`MAY` chains, with the explorer and the ledger refusing a C-shaped chain that holds a `MUST` or `SHANT` over other parties' acts; A registered as D-L8 and the fixtures rewritten as A when it lands, their graphs unchanged; B is not built. The first draft recommended A as "existing syntax"; buy-blocker's measurement of 2026-10-25 (§1 finding 10) showed it reads the record wrongly in both operand orders.
  **Ruled 2026-10-25, card L2: accept, option C**, as printed: C now for WP0 and the operational lowering, the explorer and the ledger refusing a C-shaped chain that holds a `MUST` or `SHANT` over other parties' acts, A registered as D-L8, B not built; no note. Recorded after the mark: D-L9 (`specs/todo/PARTY-BINDER-SPEC.md`, scoped the same day) offers C a route to `PARTY` as the actor without D-L8; it is a proposal and changes nothing in this ruling. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#L2.
- **R-L3** is folded into R-L7: TLC and NuSMV are built together and must agree on liveness; a disagreement blocks, a missing tool yields unknown (§6.3).
- **R-L4 Refusal over sampling for unbounded binders** (§4.2). Recommendation: refuse, loudly and with a non-zero exit, per constructor; an author-declared finite domain is the third option, registered as D-L7, and no tool-chosen sample is ever offered. The first draft cited the parent's R-V8 Bedrock figures as precedent; they describe an over-refusing sound tool and cut the other way, so they are withdrawn here.
  **Ruled 2026-10-25, card L4: accept, option A**: refuse per constructor, loudly, non-zero exit; D-L7 stays registered; no tool-chosen sample; no note. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#L4.
- **R-L5 What enters the public tree.** The brief's model goes into l4-ide in a neutral skin (§7), and the original private example stays in the private `solutions` repo. The branch is unpushed, so the ruling covers the specs on it too. A: the fixture split as stated, with the specs in the same skin before the push; B: push the specs as they stood; C: keep everything private. Recommendation: A; it keeps CI free of the private repo.
  **Ruled 2026-10-25, card L5: modify, option A.** The scenario of the specs and fixtures is Alice and Bob each wanting to buy dinner unless the other already has, a classic race condition, and how L4 deals with it; the specs name no external case. Meng's note is held in the private record. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#L5.
- **R-L6 TLA+ fairness, reversed.** The first draft recommended `WF_vars(Next)` over real steps and rejected a per-action list as one more place to diverge; TLC showed `WF_vars(Next)` violates P5 and P6 on D3 (§1 finding 11). Recommendation: weak fairness per labelled action, derived from the graph by the emitter (§4.6), with the `lastAct`/`beat` step encoding kept so a pause is a visible step; a reader of an emitted `.tla` sees the list.
- **R-L7 Target order.** The comparison in legalese/solutions#1 recommends TLA+ first, PNML second, NuSMV third, Spin as the alternative; it marks this "not ruled". Recommendation: TLA+ and NuSMV together as the first pair (the harness needs both for liveness), PNML last as a picture target (not a dense-time door: T2, petri/REPORT.md:405-419), Spin kept as the alternative, Maude and UPPAAL out; `.aut` built first as the harness oracle, which makes mCRL2 a required harness tool. The parent's phase order (Z3, Alloy, UPPAAL/TAPAAL, TLA+) is reordered by this for the explicit route, and WP6 says so.
  **Ruled 2026-10-25, card L7: accept, option A**: TLA+ and NuSMV as the first pair, PNML last as a picture target, Spin the alternative, Maude and UPPAAL out, `.aut` first as the harness oracle with mCRL2 a required harness tool, fairness per labelled action (R-L6 folded in); no note. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#L7.

## 10. Register of deferred obligations

| id       | deferred                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | trigger                                                                                                            | owed by             |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------- |
| **D-L1** | the symbolic lowering (parties as processes, obligations as records, clocks as variables), as each probe's §5 mapped it; it **reopens parent Phase 0 items 1 and 2** (IR, reference semantics), which §3 answers for the explicit route only                                                                                                                                                                                                                                                        | the first fixture whose explicit graph exceeds the explorer's bounds with the frontier not exhausted               | §2, §3              |
| **D-L2** | the assertion-language surface syntax (parent Phase 3)                                                                                                                                                                                                                                                                                                                                                                                                                                              | the first property that cannot be written as a boolean decision over the position; liveness is the likely one      | §3, §5.1            |
| **D-L3** | defeasibility (parent D1's other half)                                                                                                                                                                                                                                                                                                                                                                                                                                                              | the first fixture with a priority, an exception or a contrary-to-duty chain                                        | §3                  |
| **D-L4** | porting Joe Watt's 2023 Maude semantics from Full Maude to plain `mod`, and adding state and guards (Maude report §5b, about 25 lines sketched)                                                                                                                                                                                                                                                                                                                                                     | a decision to make Maude the reference _host_ rather than a backend                                                | §3                  |
| **D-L5** | the PDPA breach-notification race as an L4 fixture                                                                                                                                                                                                                                                                                                                                                                                                                                                  | the pilot's L4 encoding being located or rewritten; the 2022 model is UPPAAL only                                  | §7                  |
| **D-L6** | dense time as a _checked_ property (UPPAAL is out on licence; TAPAAL `verifytapn` is the one engine that ran, with the traps of §1 finding 8, and it needs hand-built timed-arc nets, not PNML from the explicit graph)                                                                                                                                                                                                                                                                             | T2 being revisited, or a timed property the integer-clock cross-validators of §4.5 cannot state                    | §4.5, §6.1          |
| **D-L8** | **not a new obligation**: a pointer to NORM-LOG-SPEC N10's goal A, lockstep `RAND`/`ROR` operands one event at a time (ruled 2026-10-11 by METRONOME, draft legalese/l4-ide#499; today each operand runs over the whole trace before the next, Machine.hs:3223-3229), with N10's conditions (a corpus evaluation differential; a ruling on a losing `ROR` alternative's entries) and N12 for black-ink reads; when it lands, §4.3 option A replaces option C with no change to the fixtures' graphs | N10's own trigger; this spec adds the first fixture whose parties act on one official record as a reason           | §4.3                |
| **D-L9** | a party bound by the matching event, `ANY [Cast] p [IN roll] [WHO …] MAY/SHANT act`, one obligation consumed once with the actor in scope in the continuation an act reached, a `MAY`'s `HENCE` or a `SHANT`'s `LEST` (`specs/todo/PARTY-BINDER-SPEC.md`, proposed 2026-10-25 at WHODUNIT, reviewed by the every-each session the same day, nothing built); it gives option C `PARTY` as the actor for all-`MAY` chains without D-L8, and leaves C's silent `MUST`/`SHANT` limit to D-L8            | a ruling on that spec's R-P1; the first fixture whose ledger `party` column must hold the real actor is the reason | §1 finding 10, §4.3 |
| **D-L7** | an author-declared finite domain per unbounded binder, with the bound printed and the verdict "holds within <domain>" (every probe's route for `NUMBER`; the parent's open question "checked up to scope N", VERIFICATION-BACKEND-LOWERING-SPEC.md:512)                                                                                                                                                                                                                                             | the first fixture with a money payload                                                                             | §4.2                |

## 11. Edits to the parent spec (WP6)

1. In §"Deferred obligations", row **D1** (the parent register's D1, not the probes' design D1 nor UNKNOWN-EVALUATION-SPEC §9's D1), append: _"Triggered 2026-10-24 by the safety property of a check-then-act race. [REGULATIVE-LOWERING-SPEC.md](REGULATIVE-LOWERING-SPEC.md) §3 answers the IR and reference-semantics items for the explicit-LTS route only (its R-L1); they reopen for the symbolic lowering (its D-L1). Defeasibility is still owed (its D-L3, trigger: a priority, an exception or a contrary-to-duty chain); the assertion surface is still owed (its D-L2, trigger: the first property not writable as a boolean decision)."_ and qualify "Phase 2 cannot start without it" with "except the explicit-LTS route".
   The row is not otherwise changed.
2. In §"Open Questions", **Witness translation**, append: _"Answered for the explicit-LTS route by REGULATIVE-LOWERING-SPEC §5.4: a state is a path of events, so a counterexample is a `#TRACE`."_
3. At :148, "portfolio invariant I1" names the architecture pattern; the evaluator-as-oracle invariant is BACKEND-PORTFOLIO-SPEC I2 (:239). Correct the number (skeptic L1, 2026-10-25).
4. After the phase order (:161-187), add one line: _"For the explicit-LTS route, REGULATIVE-LOWERING-SPEC R-L7 orders the emitters TLA+ with NuSMV, then PNML as a picture; Z3 and Alloy are untouched by it."_

## 12. What this spec does not claim

- On this branch only the dinner fixtures of §7 are built, and no explorer is in this tree, so the state counts quoted are the probes' hand models, not an explorer's output.
  The explorer that reproduces them is on `mengwong/lowering-explore`, not here.
- The probes ran on 10 to 25 untimed states; nothing here says the explicit route scales to a whole contract, and D-L1 exists because it may not.
- The probes' models were written by Sonnet agents from one brief and spot-checked against their logs by the parent session; the bisimulation check of §6.2 is what would make them an oracle rather than a reference.
- The probe reports cited here are in the private `legalese/solutions` repo, pushed 2026-10-25 as draft PR legalese/solutions#1 (commit `b0de111`), so they resolve for the team and for nobody else.
- Neither §4.3 option has been run end to end by this spec's author; skeptic L2's run (Alice-first operand order reads zero official rows) and buy-blocker's measurement (neither order reads the record in event order, both builds) are the evidence for A's failure, recorded in §1 finding 10, and buy-blocker's same-strand control is the evidence that C's reads work.
- Ten of this spec's claims were corrected on 2026-10-25 by the skeptics of the Lowering Rulings bench, and each correction is marked where it lands (§1 findings 10 and 11, §4.2, §4.3, §4.5, §4.6, §6.1, §6.2, §9); the first drafts are in the session record, not in this branch.
