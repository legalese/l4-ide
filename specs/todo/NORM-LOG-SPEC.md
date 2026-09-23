# Specification: the norm log — letting a contract read its own deontic history

> **Status (2026-09-23): PROPOSED, not landed.**
> Nothing in this spec is implemented on `unstable`.
> Every ruling in §6 is OPEN and is Meng's.
> §7's measurements come from a throwaway probe on the local branch `probe/norm-log`, which projects the deontic step log into the ledger behind an environment variable; that branch exists to answer §6's questions and will never merge.
> Everything else in this document is cited to `unstable` @ `20e71b65d`.
>
> **Companion documents:** > `specs/done/STATE-AS-LEDGER-SPEC.md` (the ledger, `RECORD`/`COMMIT`/`RECALL`, ruling D1);
> `specs/todo/lexipedia-superset/LTS-VISUALISER.md` (the deontic step log, its ruling R5, and §4.2's "the ledger is the wrong axis");
> `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` (the lifecycle anchors `OF THE JOIN` / `OF THE DEADLINE` / `OF THE ARMING`, R-Q7B);
> `specs/todo/IN-RELIANCE-ON-SPEC.md` (reliance, which needs the same history);
> `paper/bounded-deontics/notes/moral-taint.md` (the jurisprudential side of §3).

---

## 0. The one-paragraph thesis

A great many legal provisions make a later obligation or permission depend on what happened to an earlier one: whether it was performed, whether it was breached, whether a breach is "continuing", how many times it has been breached in a period, and whether a breach was cured by performance or merely paid for.
L4 today cannot express any of these without the drafter of the **earlier** provision hand-writing a `RECORD` in every branch, which fails whenever the two provisions have different authors, and fails silently whenever one branch is forgotten.
The machine already decides every one of these facts, and the deontic step log already writes most of them down, but only as an observer that nothing may consult.
This spec proposes that the machine **write** a norm's fate into the ledger implicitly, and that a drafter **read** it explicitly, through a family of expressions that generalises the three lifecycle anchors L4 already has.
The difficult parts are not the write; they are naming the norm being read about (§6 N2), the laziness holes in the existing log (N7), and distinguishing discharge by performance from discharge by reparation (N8).

---

## 1. What exists today (measured)

Measured 2026-09-21 and re-measured 2026-09-23 on the installed `l4` with its embedded prelude.

**The ledger is written by exactly one thing.**
`LedgerEvent` has one constructor, `Assign !Path !WHNF !Provenance` (`jl4-core/src/L4/Evaluate/Ledger.hs:97`), and the only append of it anywhere is in `runRecord` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:3819`, the append at `:3850`), the handler for `RECORD`/`COMMIT`/`ATTEST`.
Trace events, deontic transitions, breaches and fulfilments never reach the ledger.
A two-event trace with no `RECORD` and a guard ``PROVIDED RECALL `anything` EQUALS NOTHING`` is satisfied: the ledger really is empty after events have been played.

**The event stream is consumed.**
A `HENCE` continuation is handed only the tail of the stream.
There is no name in the language for "the events so far" and no builtin over them.

**Four things carry the past forward without a `RECORD`.**

1. _Values bound from a matched event._
   `MUST payment price` binds `price`, and the binding is unioned into the environment of the `PROVIDED`, the `HENCE` and the `LEST` (``env `Map.union` henceEnv``, `Machine.hs`), accumulating down the chain.
   Measured: `MUST refund (p MINUS q)`, with `q` bound by the first event and `p` by the second, is `FULFILLED` by `refund 7` after `delivery 3` and `payment 10`, and left outstanding by `refund 6`.
2. _The three lifecycle anchors_ `OF THE JOIN`, `OF THE DEADLINE`, `OF THE ARMING` (`jl4-core/src/L4/Parser.hs:2901`; corpus `jl4/examples/ok/every/run-anchors.l4`).
   Measured: a join at 40 and `WITHIN 2 OF THE JOIN` reports a deadline of 42.
3. _The clock._ A continuation's clock is the stamp of the event that reached it.
4. _The acting party_, which is what a bare `RECALL` reads and a bare `RECORD` writes.

**A history can be replayed from outside.**
`EVALTRACE` is an ordinary function (`jl4-core/src/L4/TypeCheck/Environment.hs:38`, typed at `:895` as `DEONTIC a b -> NUMBER -> LIST OF (EVENT a b) -> DEONTIC a b`) and `EVENT` is an ordinary constructor, so a rule can take `GIVEN h IS A LIST OF (EVENT Person Action)` and replay a contract over it.
Measured: it returns the residual.
A contract cannot, however, reach for the stream it is itself running inside.

**`RECORD` works across the branches of a compound.**
The ledger is per-directive (`withFreshLedger`, `jl4-core/src/L4/EvaluateLazy.hs`), not per-branch, so a `COMMIT` in one operand of a `RAND` is visible to a `RECALL` in the other.
Measured with a discriminating control: `EQUALS JUST 3` is satisfied and `EQUALS JUST 4` leaves the guarded obligation outstanding.

**`FULFILLED` carries nothing.**
`ValFulfilled` is the nullary constructor `ValConstructor TypeCheck.fulfilRef []` (`Machine.hs:5280-5283`).
A reparation path that ends in `FULFILLED` and a performance path that ends in `FULFILLED` are the same value, so after the fact nothing can tell them apart.
This is the functionalist reading of §3 built into the runtime, and it is the fact the moralistic frame collides with.

---

## 2. Legal idioms that read deontic history

These recur across contract and statute.
They are recorded here because each one determines what the norm log has to contain; confidence is stated where the wording is recalled rather than checked.

1. **"Which is continuing."**
   _"Upon the occurrence of an Event of Default which is continuing …"_.
   In Loan Market Association drafting an Event of Default is "continuing" if it has not been **remedied or waived**.
   It needs the set of failures that have neither been cured nor waived — and waiver is an act by the **other** party (§6 N9).
2. **Notice and cure.**
   _"… and such failure continues for thirty days after written notice thereof."_
   Needs the instant of the failure, the instant of the notice, and the elapsed time.
3. **Persistent, repeated or habitual default.**
   A count over a window.
   Commercial leases: _"if Landlord shall have served three or more notices of default within any twelve-month period …"_.
   The UK points-based late-submission penalty regime introduced by the Finance Act 2021 (the mechanism is recalled with confidence, the schedule number is not) awards a point per missed filing obligation, charges a fixed penalty at a threshold, and expires points after a period of compliance: a legislated counter over failures, with a window and an expiry.
   **Housing Act 1988, Sch. 2, Ground 11 is NOT this family, although it reads like it.**
   Its encoding in this repository keeps "persistently" as a single judgement input, because a course of conduct is "a matter of degree left to the court's appraisal" (`jl4/experiments/housing-act-ground-11.l4:36-39`).
   A norm log can supply the evidence of the late payments; it must not be used to compute the finding.
4. **Accrued rights survive termination.**
   _"Termination shall be without prejudice to any rights or obligations which have accrued prior to the date of termination."_
   A quantification over past transitions: of everything that became due before the termination instant, which was discharged and which was not.
5. **Accrual for limitation.**
   _"No action may be brought more than six years after the cause of action accrued."_
   The accrual instant is the failure instant.
6. **Where a sum came from.**
   Three different doctrines, which must not be merged:
   - the penalty rule applies only to **secondary** obligations triggered by breach (_Cavendish Square Holding BV v Makdessi_ [2015] UKSC 67) — this one maps onto L4's own structure, a `LEST`-reached obligation against a `HENCE`-reached one;
   - fines and penalties are subordinated in a Chapter 7 distribution to the extent they are not compensation for actual pecuniary loss (11 U.S.C. §726(a)(4)) — this turns on the character of the sum, not the branch;
   - amounts paid to a government for the violation of a law are not deductible (26 U.S.C. §162(f)) — this turns on the payee.
     Only the first is evidence for logging the branch of origin (N8).
7. **Waiver and course of dealing.**
   _"No failure or delay in exercising any right shall operate as a waiver thereof."_
   The clause exists because the default rule reads the history of non-exercise.
8. **Reinstatement.**
   _"Upon cure of all Events of Default, the Commitments shall be reinstated."_
   Needs the set of open failures to be empty.
9. **The moralistic frame**, which has its own section.

This repository already contains the degraded form of families 3 and 4.
`jl4/examples/legal/regcf/denovo/regcf-denovo.l4` models history as uninterpreted booleans supplied by a party — `previously sold securities in reliance on section 4(a)(6)` (`:758`) and `previously failed to comply with the ongoing reporting requirements of § 227.202` (`:774`) — and carries an `AMBIGUITY` note at `:1782-1783` asking whether "previously" means ever or within the twelve-month period, a windowing question.

---

## 3. The moralistic frame: a fine is a price, except when it is not

_Raised by Meng, 2026-09-23._

Gneezy and Rustichini's day-care study ("A Fine Is a Price", _Journal of Legal Studies_ 29(1), 2000) showed that introducing a fine for late pick-up **increased** lateness: the parents read the fine as the price of lateness.
The bounded-deontics programme takes that functionalist view seriously, and L4's runtime embodies it: a `LEST` is an alternative path, and a `LEST` that reaches `FULFILLED` is indistinguishable from performance (§1).

Some rules refuse that reading.
They treat any failure — even one the rule itself offers a reparation for — as leaving the party in a state that must be put right before certain **other** acts are allowed.
Meng's example: a library patron with an overdue book cannot borrow another.
The book's own obligation has a perfectly good reparation path (return it late, pay the fine or the replacement cost); the block sits on a **different** norm, the permission to borrow, and reads the first norm's history.

It is not a curiosity.
Recalled from general knowledge, with the confidence noted:

| rule                                                                                                                                                                                          | what it blocks            | how the block lifts                                | confidence                       |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | -------------------------------------------------- | -------------------------------- |
| library circulation: overdue items (or fines over a threshold) block borrowing                                                                                                                | new loans                 | return / pay                                       | high as a pattern                |
| LMA-style drawstop: no utilisation while a Default is continuing — and a "Default" includes an event that is not yet an Event of Default because a grace period has not run                   | new advances              | cure or waiver                                     | high                             |
| US passport denial for child-support arrears above a threshold (42 U.S.C. §652(k))                                                                                                            | a passport                | payment below the threshold                        | high                             |
| driving-licence renewal held for unpaid parking fines or failure to appear                                                                                                                    | a licence                 | payment                                            | medium — varies by US state      |
| university registration or transcript holds for unpaid fees                                                                                                                                   | registration, transcripts | payment                                            | high as a pattern                |
| unlawful-presence bars: 3 or 10 years, triggered on **departure** (INA §212(a)(9)(B))                                                                                                         | re-admission              | lapse of time counted from the cure                | high                             |
| spent convictions (UK Rehabilitation of Offenders Act 1974)                                                                                                                                   | disclosure consequences   | lapse of a rehabilitation period                   | high                             |
| clean hands: a claimant's misconduct in the matter bars equitable relief                                                                                                                      | equitable remedies        | does not lift for that claim                       | high                             |
| a party cannot take advantage of its own breach (_Alghussein Establishment v Eton College_ [1988] 1 WLR 587)                                                                                  | rights arising from it    | does not lift                                      | high                             |
| grave sin bars reception of communion without prior sacramental confession (Code of Canon Law c. 916) — the literal source of the "repent before you may" shape, and repentance ≠ restitution | a sacrament               | a distinct act of repentance, not a reparation     | high                             |
| fine-free libraries: overdue fines abolished, but borrowing still blocked while items are long overdue                                                                                        | new loans                 | return, or the replacement is billed and then paid | medium — describes a common move |

The last row is the instructive one: removing the **price** did not remove the **block**, which shows the two are separate provisions with separate subjects.

### 3.1 How the block lifts — four shapes

The shapes differ in exactly what they need from a log, which is why they are separated here.

| shape                    | example                                           | reads                                                                 |
| ------------------------ | ------------------------------------------------- | --------------------------------------------------------------------- |
| **(a) while continuing** | library, drawstop, passport, licence              | the set of failures not yet cured (or waived) **now**                 |
| **(b) for a period**     | unlawful-presence bars, spent convictions, points | failure and cure instants, and a window over them                     |
| **(c) ever**             | clean hands, "has ever been convicted"            | existence of a failure                                                |
| **(d) by repentance**    | c. 916; reinstatement on application              | a named failure, and a **later, distinct** act that refers back to it |

Shape (d) is the strongest requirement: the act that lifts the block is not the reparation the failed norm offered, so it has to be able to name the failure it answers.
Shapes (a), (b) and (d) all need to know whether a failure was cured by performance or discharged by reparation, which is exactly the distinction `FULFILLED` erases (§1, N8).
Shape (c) in a **pardon** form — a failure that is excused rather than cured — is the same missing act as waiver (N9).

### 3.2 What the frame is, in bounded-deontic terms

Under the functionalist reading, the reparation path is one more path to the goal and the violation marker is transient: taking the `LEST` clears it.
Under the moralistic reading the marker is **sticky**: it survives the reparation, and only performance, repentance, lapse of time or a pardon clears it.
The difference is whether the violation is part of the **state** that later norms see, and the norm log is what would make it so.
In the dominator terms of the bounded-deontics paper, the block does not add an act — the book comes back either way — it **reorders** acts: the cure must precede whatever the party wants next.
The paper's treatment is in `paper/bounded-deontics/notes/moral-taint.md`.

**This frame is already expressible, if you own the upstream text.**
A drafter who writes ``LEST RECORD `overdue` IS TRUE HENCE …`` in the loan obligation, and ``PROVIDED RECALL `overdue` EQUALS NOTHING`` on the borrow permission, gets shape (c) today.
What the norm log adds is that the downstream provision no longer depends on the upstream author having remembered — and, in the library, the loan rules and the borrowing rules are routinely written by different people at different times.

---

## 4. What the machine already computes — and why that is not enough

The deontic step log (`jl4-core/src/L4/EvaluateLazy/DeonticStep.hs`, P2b of `LTS-VISUALISER.md`) records one entry per look by one obligation at one event.
Its outcome type, `StepOutcome`, has 13 constructors: `Waiting`, `PartyMismatch`, `ActionMismatch`, `GuardFailed`, `EarlyAct`, `Matched`, `Expired`, `Breached`, `Joined`, `JoinReleased`, `JoinExpired`, `JoinFailed`, `JoinStalled`.
Its key, `NormKey`, carries the source site of the obligation, an activation ordinal, the bearer (three renderings), the modal, and any `EVERY` membership.
So most of the vocabulary this spec needs is already being decided and written down.

**It was built never to be read, and three of its gaps follow directly from that.**
Its header says so: _"Nothing here is consulted by the machine"_ (`DeonticStep.hs:9`), and it is off by default (`:11`, ruling R5).

1. **It never forces a value.**
   _"The log PEEKS and never forces"_ (`:154`).
   A step's bearer is `Nothing` whenever the party expression had not yet been evaluated; the source rendering `nkBearerSource` covers most of those cases but is a name, not a resolved party.
2. **Some steps have no clock.**
   `dsClock :: Maybe Rational` (`:111`); an explicit `BREACH` step is logged by the expression arm, which _"holds no clock and no event either"_ (`:316`).
3. **The activation ordinal is always 0 when the log is off** (`:147`).

As an observer those are honest omissions.
As an input to a `PROVIDED`, each is a **silent** failure: a count of breaches in a window would leave out every clockless breach, and a count by bearer would leave out every unforced one, and in both cases the answer is a number with exit code 0.
There are only two ways out, and they pull in opposite directions: force what the log reads (which changes what the machine evaluates, and can change whether it terminates), or make the read say that its answer is partial.
That is ruling N7.

---

## 5. Design sketch — not ruled

- **The write is implicit.** At each point where the machine decides a norm's fate, it appends a norm entry to the ledger. No drafter writes it.
- **The entry is a new `LedgerEvent` constructor**, not an `Assign` to a reserved path: the sum type was left open for exactly this (_"so that later milestones can add @Obliged@, @Breach@, etc."_, `Ledger.hs:95`), and a separate constructor keeps machine-observed facts apart from drafter-asserted ones (N5).
- **The read is explicit**, and it is phrased as a generalisation of the lifecycle anchors. `OF THE JOIN`, `OF THE DEADLINE` and `OF THE ARMING` are already implicit process state read through explicit syntax, and nobody writes a `RECORD` to make them work. This proposal extends that family from **instants** to **fates**.
- **Reads are as-of the reader's own contract clock**, so an entry stamped later than the reading norm's clock is invisible to it. This removes most, but not all, of the ordering problem (N10).

The surface below is **illustrative only**; nothing like it parses today, and choosing it is N4.

```text
-- illustrative, not L4: the library block, shape (a)
PARTY patron MAY borrow b
PROVIDED NO FAILURE OF `return the book` BY patron IS CONTINUING

-- illustrative, not L4: a repeat-default termination right, shape (b) with a count
PARTY Lender MAY terminate
PROVIDED THE NUMBER OF FAILURES OF `pay interest` WITHIN THE LAST 365 IS AT LEAST 3
```

---

## 6. Rulings — all OPEN

| id      | question                                                                   | notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **N1**  | **Which transitions become entries?**                                      | Log a norm's **fates**, not its looks at events. `PartyMismatch`, `ActionMismatch`, `GuardFailed` and `Waiting` are looks, O(events × norms). Candidate fates: armed, performed, failed (to reparation / to breach), violated (a prohibition broken), kept (a prohibition's window closed), lapsed (a permission's window closed), breached, and the join outcomes. `Armed` is not a `StepOutcome` today.                                                                                    |
| **N2**  | **How does a drafter name the norm being read about?**                     | The hardest question here. An inline obligation has no name: `PARTY B MUST payment p` inside a `HENCE` is anonymous, and a source range is meaningless to a drafter. Candidates: the enclosing rule's name plus a label; an explicit label on the obligation; addressing by bearer and action pattern. §7 measures three crude schemes.                                                                                                                                                      |
| **N3**  | **What is the time axis?**                                                 | Norm fates live on the contract clock (`dsClock`, a `Rational`). `Provenance` has `txTime :: UTCTime` (wall clock, one value per run) and `vtFrom :: Maybe Day` — neither is it, and `vtFrom` cannot be reused because the contract clock is not a `Day`. `LTS-VISUALISER.md` §4.2 already records the ledger as "the wrong axis" for this. A windowed count on the wrong axis is a wrong number, not an error.                                                                              |
| **N4**  | **Implicit write, explicit read — and in what surface?**                   | Proposed: the write implicit, the read explicit, as an extension of the anchor family (§5). An implicit read would make every expression potentially history-dependent, which the evaluator's caching assumes is rare. Also decides whether a time window is written in the read (shape (b)) or built in, and must give a guard a name for its own current instant, which it lacks today (§7).                                                                                               |
| **N5**  | **How are machine-observed fates kept apart from drafter-asserted facts?** | A separate `LedgerEvent` constructor keeps them apart by construction; a reserved path prefix does not, because a drafter could `COMMIT` to it. `Provenance.source` already distinguishes `RECORD`/`COMMIT`/`NOTIFY`.                                                                                                                                                                                                                                                                        |
| **N6**  | **Does the step log stop being optional?**                                 | If a `PROVIDED` may read fates, whatever writes them must always run. That reopens `LTS-VISUALISER.md` ruling R5 (optional, off by default), which is owned there; this spec does not overturn it. An alternative is a second, always-on writer that shares only the vocabulary.                                                                                                                                                                                                             |
| **N7**  | **Force, or admit a partial answer?**                                      | See §4. Forcing a party or a clock the machine had not forced changes evaluation. Not forcing makes counts silently short. A third option is a read that reports how many entries it could not place.                                                                                                                                                                                                                                                                                        |
| **N8**  | **Branch of origin: performance or reparation?**                           | The moralistic frame (§3.1 shapes a, b, d) and the penalty rule (§2 item 6) both need to know whether a norm was discharged by its primary act or through its `LEST`. That needs each norm's entry to carry the branch that armed it and a link to the norm whose failure armed it. Both are known at arming time and cannot be reconstructed afterwards. The branch alone is not enough: a `LEST BREACH` is a `LEST` too (§7).                                                              |
| **N9**  | **Waiver, release and pardon.**                                            | "Continuing" means not remedied **or waived** (§2 item 1); pardon is the waiver of shape (c). Waiver is an act of the other party, not a transition of the failed norm, and L4 has no primitive for it. Without one, the most common idiom in §2 cannot be written.                                                                                                                                                                                                                          |
| **N10** | **Two fates at the same instant.**                                         | As-of reads order entries by contract clock, but not entries with the same stamp — for example a borrow event that is also the event revealing that a return deadline passed. Which fate a reader sees then depends on which operand of a compound scrutinised the event first. Related to the pending tie-break ruling on same-event breaches in `RAND`/`ROR` (trigger word SEESAW, in another session). **Measured (§7): swapping the operands of the library contract flips the answer.** |
| **N11** | **How long does the log last?**                                            | The ledger is per-directive (`withFreshLedger`). A norm log is therefore a per-trace history, which is right for `#TRACE` and wrong for a deployed contract whose history outlives one evaluation. That seam is shared with `STATEFUL-CONTRACT-DEPLOYMENT.md`.                                                                                                                                                                                                                               |

---

## 7. Probe — what a crude projection shows

Measured 2026-09-23 on the local branch `probe/norm-log` @ `65fb65201` (never pushed, never merges), built from `unstable` @ `20e71b65d`.
With `JL4_NORM_LOG=1`, every `#TRACE` runs with the step log on, and each routing step is also appended to the official ledger under three addresses — the bare fate (`norm failed`), the fate by bearer (`norm failed by patron`), and the fate by source line (`norm failed at line 12`) — valued at the step's contract clock, or `-1` where the step has none.
The probe contracts are on that branch under `jl4/experiments/norm-log/`: `library.l4`, `repeat-default.l4`, `holes.l4`.
The labels are the probe's own crude vocabulary, not a proposal.

**Positive control.** The library probe writes 0 norm entries with the variable unset and 54 with it set.

**The library block, shape (a), works — but only when addressed by source line.**
"Good standing" was written as: the number of the patron's failures-to-reparation equals the number of discharges at the reparation's line.

| trace                                            | expected | got     |
| ------------------------------------------------ | -------- | ------- |
| T1 returned on time, then borrows                | allowed  | allowed |
| T2 returned late, fine unpaid, borrows           | blocked  | blocked |
| T3 returned late, fine paid, borrows             | allowed  | allowed |
| T5 the hand-written `RECORD` alternative of §3.2 | blocked  | blocked |

**N2 — addressing by bearer cannot tell a reparation from performance.**
`norm discharged by patron` is written by three different norms: the loan returned on time (T1, line 12), the fine paid after a late return (T3, line 14), and the exercised borrowing permission (T1 and T3, line 26).
Only the source line separates them, and no drafter can be asked to write one.

**N10 — operand order decides the answer, and nothing reports it.**
T4 has one event: the patron borrows at 20, with the book (due 14) never returned; that borrow is also the event that reveals the loan's failure.
`loan RAND borrowing` blocks the borrow; `borrowing RAND loan` allows it.
Same contract, same trace, opposite answers, exit code 0 both times.

**N3 — the window has to be on the contract clock, and the ledger's own clock cannot do it.**
Repeat default — "three or more late interest payments within 365 days" — gives the expected answer on all three traces: three late payments, termination allowed; two, refused; three but more than a year earlier, refused.
That works only because the probe stores each failure's contract-clock deadline (30, 65, 100) as the entry's value.
All 18 entries in the third trace share one transaction time (`at=…03:42:35Z`), so a window on transaction time would have counted all three failures and allowed the termination: a wrong answer, silently.

**N4 — a guard has no name for "now".**
`PROVIDED` could not say "within the last 365 days" because nothing in it names the current contract instant; the probe had to put the date in the action (`terminate 110`) and bind it.
A read surface for windows needs the reader's own clock, which the anchor family (`THE ARMING`, `THE JOIN`) does not supply.

**N7 — both holes are real.**
An explicit `BREACH` step is logged with no clock, no bearer and no site (`-1`, `?`, `?`), so it falls out of every windowed or per-party count.
An obligation whose party is a definition (`theDebtor MEANS borrower`) and which has no `LEST` is logged under the source name `theDebtor`, because the machine never forces the party, so "failures by `borrower`" silently misses it.
With a `LEST`, the same party is forced on the expiry path and is logged as `borrower`: whether a count is complete depends on the shape of the norm being counted.

**N8 — the branch alone does not say "reparation".**
`PARTY borrower MUST pay WITHIN 5 LEST BREACH` is logged as a failure **to `LEST`**, because a `LEST` whose body is a bare `BREACH` is still a `LEST`.
Telling a reparation from a breach needs what the `LEST` armed, not which branch was taken.

**N1 — fates must be modal-aware.**
The probe labels every `Matched ToHence` as "discharged", so an exercised **permission** (the borrow) is logged in the same cell as a performed **duty**.
That is the probe's shortcut, but it shows the vocabulary has to key on the modal: exercising a `MAY` is not discharging a `MUST`.

**N5 — the audit printout already misattributes machine entries.**
The ledger printer renders every source other than `COMMIT` as `RECORD` (`jl4-core/src/L4/EvaluateLazy.hs:492-493`), so the probe's machine-observed entries print as though the patron had written them.
A separate constructor would have to be printed separately, or an audit trail would show a party asserting facts it never asserted.

**Not a finding, but a trap for anyone writing these rules.**
A `LEST`'s `WITHIN` counts from the missed deadline, not from the event that revealed the miss, so in the library the fine was due at 21 and a payment at 22 breached the whole compound — which then never evaluated the borrow at all.
The first draft of the probe got this wrong.

---

## 8. What review changed

The first sketch of this design was written in conversation on 2026-09-22 and reviewed on 2026-09-23.
The review changed six things; they are recorded so that a later editor does not silently undo them.

- The sketch called the work "a projection, not instrumentation". That was too strong: the step log's laziness holes (§4) mean a projection gives silently short answers. N7 exists because of this.
- The sketch proposed Housing Act Ground 11 as the first witness. The repository's own encoding treats "persistently" as a judgement (§2 item 3), so the witness was changed to commercial repeat-default and the library block.
- The sketch listed "continuing" without waiver. N9 was added.
- The sketch claimed that as-of-contract-clock reads remove the ordering problem. They do not, for entries at the same instant. N10 was narrowed accordingly.
- The sketch cited three "penalty" authorities as one family. They are three doctrines, and only one supports N8 (§2 item 6).
- The sketch's example surface named `THE ARMING` as an expression. It is valid only after `OF` in a `WITHIN` or `AFTER`, and in that example it named the wrong instant. §5's examples are now marked illustrative and use no existing keyword in a new position.
