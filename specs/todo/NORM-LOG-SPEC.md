# Specification: the norm log — letting a contract read its own deontic history

> **Status (2026-11-24): P1, the fates writer, is built (legalese/l4-ide#868). P2's first half is built and merged (legalese/l4-ide#870, merge commit `9d264217c`): the pure reader, `THE INSTANT` and the `NOW` warning (§6.4); no syntax reaches the reader on `unstable`. P2's second half, the read as written (§6.5), exists on the branch `feat/norm-log-read-syntax` and is not merged; it is a fallback for the spelling Meng has not ruled (card N4b). P3 onwards is proposed, not landed.**
> The text below P1 was checked 2026-11-22 against `origin/unstable` @ `a12991789`, by reading the code and the landed commits; P1's own claims (§6.2 and §6.3) were checked 2026-11-23, on `lhs`, by running `etc/verify-branch.sh`, `NormLogSpec` and `jl4-test` with the writer forced on, in the merge gate; §6.3 says what that did not cover.
> The measurements in §7 and in the notes of §6.1 were not re-run unless an entry says so.
> All twenty rulings are answered (§6.1): N1–N6 by Meng on 2026-09-27, N8 on 2026-09-28, N10 and N11 on 2026-10-11, N13 and N14 on 2026-10-14, and N7, N9, N12 (option D only), N15, N16 and N17–N20 on 2026-10-26; N20 amends N10.
> N12's contract instants are held, not ruled.
> N12 says they are re-posed in the PR that lands N10's goal A; that goal has landed for `RAND` only (next paragraph), so the re-posing is still owed.
> What `unstable` has of this: N10's goal A for a `RAND` and for the members of an `UPON EACH` fork, with a run-time refusal of a read that the operands' order would decide, and N19's check of two sides' records of one cell (legalese/l4-ide#827, merged 2026-11-13, for smucclaw/l4-ide#1069).
> It is not the whole of N10's A, N17–N19 or N20 (§6.1 N10 says what is left).
> Draft legalese/l4-ide#753 (head `57c285d1c`) is another implementation of the `RAND` slice; it is open, it was never merged, and its code is not what is on `unstable`.
> P1 adds the norm entries and the ledger that holds them, and nothing that reads them: it has no syntax, no CLI flag and no printed output unless `EvalConfig.normLog` is set, which only tests set (§6.3).
> Not built on `unstable`: the spelling of a read (N4b is open; §6.5 builds option A on an unmerged branch as a fallback), `EFFECTIVE` on a write (N15), the run note for a backdated write (N16), and the ledger read cache is still not keyed on the ledger's version (N12, option D; smucclaw/l4-ide#1034 is open).
> The build is planned in eight phases, each ending at a green gate and a review before the next (decided by Claude 2026-11-22, pending Meng's review): P1 the fates writer into its own ledger (N1–N3, N5–N8; N7's rule (3) waits for N12's instants), P2 the read side and the contract-clock name (N4), P3 N13's outstanding counts, N16's run note and N18's tagging (the tag has no setter until P5), P4 the how-to page and the waiver tutorial (N5's note, N9), then P5 N17's `ROR` and barrier members in step (it sets N18's tag), P6 N19's snapshot rule and N20's settle-first round with the backward-stamp note, P7 N15's `EFFECTIVE` as its own change, and P8 N12's option D (the cache; smucclaw/l4-ide#1034). P7 and P8 depend on nothing before them.
> §6.2 lists, ruling by ruling, what is built and where it is planned, and §6.3 says what P1's gate measured.
> The rulings are posed with evidence, recommendations and an independent skeptic's objection on a bench published 2026-09-26 (claude.ai artifact `VW7xe4F73mi5qLST8PB1CJ`, private to the account mengwong@gmail.com, marks in its db collection `norm-log-rulings`); a ruling is recorded here, not there.
> §7's measurements come from a throwaway probe on the local branch `probe/norm-log`, which projects the deontic step log into the ledger behind an environment variable; that branch exists to answer §6's questions and will never merge.
> Everything else in this document was cited to `unstable` @ `20e71b65d` and has been re-read at `a12991789`.
> A line number is a position at `a12991789`, and unstable moves it: find the site by its symbol, and where a site was rewritten the text says so.
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
Every citation below was re-read on 2026-11-22 at `a12991789`; the measurements were not re-run.

**The ledger is written by exactly one thing.**
`LedgerEvent` has one constructor, `Assign !Path !WHNF !Provenance` (`jl4-core/src/L4/Evaluate/Ledger.hs:97`), and the only append of it anywhere is in `runRecord` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:5030`, the append `tellEventRouted route (Assign [cell] val prov)` at `:5070`), the handler for `RECORD`/`COMMIT`/`ATTEST`/`NOTIFY`.
`tellEventRouted` (`:1548`) picks the destination from an `EventRoute` (`RouteOwn`, `RouteOfficial`, `RouteNotify`, in `Ledger.hs`) and marks the current force span as having written (`noteLedgerWrite`), so a thunk whose force wrote is cached as a plain value and never re-forced.
Every other module that names `Assign` (`Ledger/Replay.hs`, `Lts/Explore.hs`, `Lts/Explore/Check.hs`) reads entries and builds none.
Trace events, deontic transitions, breaches and fulfilments never reach the ledger.
A two-event trace with no `RECORD` and a guard ``PROVIDED RECALL `anything` EQUALS NOTHING`` is satisfied: the ledger really is empty after events have been played.

**The event stream is consumed.**
A `HENCE` continuation is handed only the tail of the stream.
There is no name in the language for "the events so far" and no builtin over them.

**Four things carry the past forward without a `RECORD`.**

1. _Values bound from a matched event._
   `MUST payment price` binds `price`, and the binding is unioned into the environment of the `PROVIDED`, the `HENCE` and the `LEST` (``env `Map.union` henceEnv``, in the `Contract9` and `Contract10` arms of `Machine.hs`, `:3397`, `:3463`, `:3493`), accumulating down the chain.
   Measured: `MUST refund (p MINUS q)`, with `q` bound by the first event and `p` by the second, is `FULFILLED` by `refund 7` after `delivery 3` and `payment 10`, and left outstanding by `refund 6`.
2. _The three lifecycle anchors_ `OF THE JOIN`, `OF THE DEADLINE`, `OF THE ARMING` (grammar at `jl4-core/src/L4/Parser.hs:3846`, the value forms at `:3914`; corpus `jl4/examples/ok/every/run-anchors.l4`).
   Measured: a join at 40 and `WITHIN 2 OF THE JOIN` reports a deadline of 42.
3. _The clock._ A `HENCE` continuation's clock is the stamp of the event that reached it (the `timeR` the `Contract10` arm allocates from the matched event's `time`, `Machine.hs:3484-3493`); a `LEST` continuation's is the deadline that was missed, no earlier than the obligation's own arming (`clockR`, `Machine.hs:3271-3275`, the floor ruled in SEESAW and N3's amendment below).
   The function `clockAt` that this item cited before 2026-11-22 no longer exists; the two sites above are what replaced it.
4. _The acting party_, which is what a bare `RECALL` reads and a bare `RECORD` writes.

**A history can be replayed from outside.**
`EVALTRACE` is an ordinary function (`jl4-core/src/L4/TypeCheck/Environment.hs:39`, typed by `evalContractInfo` at `:907` as `DEONTIC a b -> NUMBER -> LIST OF (EVENT a b) -> DEONTIC a b`) and `EVENT` is an ordinary constructor, so a rule can take `GIVEN h IS A LIST OF (EVENT Person Action)` and replay a contract over it.
Measured: it returns the residual.
A contract cannot, however, reach for the stream it is itself running inside.

**`RECORD` works across the branches of a compound.**
The ledger is per-directive (`withFreshLedger`, `jl4-core/src/L4/EvaluateLazy.hs:223`), not per-branch, so a `COMMIT` in one operand of a `RAND` is visible to a `RECALL` in the other.
Measured with a discriminating control: `EQUALS JUST 3` is satisfied and `EQUALS JUST 4` leaves the guarded obligation outstanding.

**`FULFILLED` carries nothing.**
`ValFulfilled` is the nullary constructor `ValConstructor TypeCheck.fulfilRef []` (`Machine.hs:7324`).
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
- **Reads are as-of the reader's own contract clock**, so an entry stamped later than the reading norm's clock is invisible to it. This does **not** remove the ordering problem between the operands of a `RAND`/`ROR`, because each operand runs over the whole trace before its sibling starts (N10).

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

## 6. Rulings — N1–N6 answered 2026-09-27, N8 answered 2026-09-28, N10 and N11 answered 2026-10-11, N13 and N14 answered 2026-10-14, N7, N9, N12 (in part), N15–N20 answered 2026-10-26

| id      | question                                                                   | notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **N1**  | **Which transitions become entries?**                                      | **ANSWERED 2026-09-27, see §6.1.** Log a norm's **fates**, not its looks at events. `PartyMismatch`, `ActionMismatch`, `GuardFailed` and `EarlyAct` are looks, O(events × norms); `Waiting` is written once per residual norm when the trace runs out (`Machine.hs:3046`). The vocabulary must cover all four modals, including `DO` (`DDo`, `Syntax.hs:822`), whose missed deadline is a failure as `MUST`'s is. Candidate fates: armed, performed, failed (to reparation / to breach), violated (a prohibition broken), kept (a prohibition's window closed), lapsed (a permission's window closed), breached, and the join outcomes. `Armed` is not a `StepOutcome` today.                                                                                                                                                                                                               |
| **N2**  | **How does a drafter name the norm being read about?**                     | **ANSWERED 2026-09-27, see §6.1.** The hardest question here. An inline obligation has no name: `PARTY B MUST payment p` inside a `HENCE` is anonymous, and a source range is meaningless to a drafter. Candidates: the enclosing rule's name plus a label; an explicit label on the obligation; addressing by bearer and action pattern. §7 measures three crude schemes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| **N3**  | **What is the time axis?**                                                 | **ANSWERED 2026-09-27, see §6.1.** Norm fates live on the contract clock (`dsClock`, a `Rational`). `Provenance` has `txTime :: UTCTime` (wall clock, one value per run) and `vtFrom :: Maybe Day` — neither is it, and `vtFrom` cannot be reused because the contract clock is not a `Day`. `LTS-VISUALISER.md` §4.2 already records the ledger as "the wrong axis" for this. A windowed count on the wrong axis is a wrong number, not an error.                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **N4**  | **Implicit write, explicit read — and in what surface?**                   | **ANSWERED 2026-09-27, see §6.1.** Proposed: the write implicit, the read explicit, as an extension of the anchor family (§5). An implicit read would make every expression potentially history-dependent, so a reader could not see which provisions depend on history. (Caching is not the obstacle: context reads are already fingerprinted, `TemporalContext.hs` (`CtxReads`, `validFor`). But ledger reads are re-served within a temporal scope — "the fingerprint does not track the ledger", `TemporalContext.hs:167-181` and `Machine.hs:2025-2033` — so a fate read's cache key must include the reader's contract clock.) Also decides whether a time window is written in the read (shape (b)) or built in, and must give a guard a name for its own contract-clock instant, which it lacks today: `NOW` exists and type-checks in a `PROVIDED`, but it is the wall clock (§7). |
| **N5**  | **How are machine-observed fates kept apart from drafter-asserted facts?** | **ANSWERED 2026-09-27, see §6.1.** A separate `LedgerEvent` constructor keeps them apart by construction; a reserved path prefix does not, because a drafter could `COMMIT` to it. `Provenance.source` already distinguishes `RECORD`/`COMMIT`/`NOTIFY`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **N6**  | **Does the step log stop being optional?**                                 | **ANSWERED 2026-09-27, see §6.1.** If a `PROVIDED` may read fates, whatever writes them must always run. That reopens `LTS-VISUALISER.md` ruling R5 (optional, off by default), which is owned there; this spec does not overturn it. An alternative is a second, always-on writer that shares only the vocabulary.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| **N7**  | **Force, or admit a partial answer?**                                      | **ANSWERED 2026-10-26 (option C, revised), see §6.1.** Reopened 2026-09-28, when its first mark was cleared. See §4. Forcing a party or a clock the machine had not forced changes evaluation. Not forcing makes counts silently short. A third option is a read that reports how many entries it could not place.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **N8**  | **Branch of origin: performance or reparation?**                           | **ANSWERED 2026-09-28, see §6.1.** The moralistic frame (§3.1 shapes a, b, d) and the penalty rule (§2 item 6) both need to know whether a norm was discharged by its primary act or through its `LEST`. That needs each norm's entry to carry the branch that armed it and a link to the norm whose failure armed it. Both are known at arming time and cannot be reconstructed afterwards. The branch alone is not enough: a `LEST BREACH` is a `LEST` too (§7).                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **N9**  | **Waiver, release and pardon.**                                            | "Continuing" means not remedied **or waived** (§2 item 1); pardon is the waiver of shape (c). Waiver is an act of the other party, not a transition of the failed norm, and L4 has no primitive for it; `HOMOICONICITY-SPEC.md` §§ at `:465-495` proposes one (`PARTY creditor MAY WAIVE (…)`, OPEN), and `SUBJECT-TO-NOTWITHSTANDING-SPEC.md:1173` classes waiver as a ledger-backed dispensation. A drafter who owns both texts can write it today with `RECORD`/`RECALL` (§3.2), provided each waiver names the default it answers and the guard reads every default with `RECALL ALL`; a waiver that names nothing clears every default (`norm-log-waiver-userspace-draft.md`, trap 4). What cannot be done is to read it from the norm log. **ANSWERED 2026-10-26 (option B, revised), see §6.1:** an idiom, not a primitive.                                                          |
| **N10** | **Operand order inside a compound.**                                       | **ANSWERED 2026-10-11, see §6.1.** A `RAND`/`ROR` handed its left operand the whole event list and ran the right operand afterwards (`Machine.hs:1549-1559` when this row was written), so a read in one operand saw the other's fates only if the other was on the left — whatever the timestamps. As-of reads do not help: the sibling's entry has not been written yet. That is still true of an `ROR` and of a barrier's members; a `RAND` now runs its operands in step (`startCompound`, `Machine.hs:1722`; §6.1 N10, status 2026-11-22). The tie-break on same-event breaches in `RAND`/`ROR` was SEESAW, ruled 2026-10-09 and landed in legalese/l4-ide#640. **Measured (§7), before legalese/l4-ide#827: swapping the operands of the library contract flips the answer, with one event and with two distinct events.**                                                            |
| **N11** | **How long does the log last?**                                            | **ANSWERED 2026-10-11, see §6.1.** The ledger is per-directive (`withFreshLedger`). A norm log is therefore a per-trace history, which is right for `#TRACE` and wrong for a deployed contract whose history outlives one evaluation. That seam is shared with `STATEFUL-CONTRACT-DEPLOYMENT.md`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| **N12** | **Black ink: which instant, and as of when?**                              | **ANSWERED 2026-10-26 in part (option D), see §6.1:** the read cache is keyed on the ledger's version; the instants are held and re-posed with N10's goal A. As posed 2026-10-09: give every `RECORD`/`COMMIT`/`NOTIFY` entry N3's two contract instants and make a `RECALL` inside a contract read the latest entry by (instant, log position) with `observed` at or before its own, extending N10's run-time check to black ink. Extends ratified A9 of `EVERY-EACH-QUANTIFIER-SPEC.md`, whose detail paragraph says the question "returns" once the contract clock is readable. Measured in §7 N10 and N12.                                                                                                                                                                                                                                                                              |
| **N13** | **What does "not satisfied" mean?**                                        | **ANSWERED 2026-10-14, see §6.1.** Outstanding: the norm is armed and neither its `HENCE` nor its `LEST` has fired. Distinct from failed (a `MUST`/`DO`'s `LEST` fired) and from failed and not cured (N8). Makes N1's `armed` entry load-bearing: an outstanding norm is visible only through it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **N14** | **May black ink be corrected at any valid time?**                          | **ANSWERED 2026-10-14, see §6.1.** Yes, at any valid time; by the notes accepted with it, by any party, with protection for an earlier reader a read-side matter. Answers the "who may correct?" question smucclaw/l4-ide#914 §6 deferred. The write side is shipped (`EVAL UNDER VALID TIME` around a `RECORD`); reads that return stamps, a finer transaction axis (N12), and a warning when a bare `RECALL` answers with a backdated entry (N16, ruled 2026-10-26) are not.                                                                                                                                                                                                                                                                                                                                                                                                              |
| **N15** | **A dated write that dates nothing else.**                                 | **ANSWERED 2026-10-26, see §6.1.** As posed 2026-10-14: `RECORD cell IS v EFFECTIVE d` (likewise `COMMIT`, `ATTEST`, recipient-qualified `RECORD`) stamps only its own entry `vt=d`; it sets no context, so reads, `RULES EFFECTIVE DATE` and the `HENCE` continuation are unchanged. Today's only form, `EVAL UNDER VALID TIME d` around the step, also stamps every later write and dates every read until the next obligation (measured 2026-10-14). The form `EFFECTIVE` on a trace event is deferred: it has the same scope and dates reads too. smucclaw/l4-ide#914 §2A proposed the sugar.                                                                                                                                                                                                                                                                                           |
| **N16** | **A bare `RECALL` after a backdated write.**                               | **ANSWERED 2026-10-26 (option C), see §6.1.** As posed 2026-10-14: a bare `RECALL` is the last visible append whatever its valid time (`Ledger.hs:183`), so after N14's backdating it can report a superseded value, exit 0 (measured: 1 at 10 Jan, 3 at 12 Jan, then 2 at 9 Jan; bare reads 2, a read at 20 Jan 3). Proposed: keep last-append, and print a run-time note when the returned entry has an earlier valid time than another visible entry for the cell. Reading "in force today" instead is deferred: a `#TRACE` has no day to read at, and a cell with only future-dated entries would read empty after its own write.                                                                                                                                                                                                                                                       |
| **N17** | **What an `ROR` does under lockstep.**                                     | **ANSWERED 2026-10-26 (option B), see §6.1.** Nothing commits on consumption; between events the driver merges alternatives that are the same obligation with the same environment and window. Posed for N10's goal A.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **N18** | **A losing `ROR` alternative's entries.**                                  | **ANSWERED 2026-10-26 (option D), see §6.1.** Keep and tag every entry; after the choice settles, plain reads and N13's counts skip a dropped alternative's entries, and reads made before it still see them. Posed for N10's goal A; answers N10's condition on a losing alternative's entries.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **N19** | **Reads within one event.**                                                | **ANSWERED 2026-10-26 (option B), see §6.1.** A match does not see a sibling operand's writes at that event's matching; its own chain's writes stay visible; different values written to one cell by siblings at one event are an error. Posed for N10's goal A.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| **N20** | **What is left of N10's check B.**                                         | **ANSWERED 2026-10-26 (option A), see §6.1, under N10, which it amends.** When goal A lands, B is unruled for streams whose stamps never go backwards, on two conditions; a backward stream keeps B and gets a run note.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

### 6.1 Answered rulings

Each was posed on the rulings bench (see the status header) with evidence, a recommendation and an independent skeptic's objection, and was marked **accept** there, except N10 and N11, which Meng accepted by typing their trigger words in chat on 2026-10-11 (their cards on the bench were unmarked).
An accept adopts the recommendation exactly as printed on the card, conditions included; the text below is that recommendation.
Meng's notes are quoted verbatim.
Nothing of the norm log is built on `unstable`; N10's goal A is built there for `RAND` and `UPON EACH` only (legalese/l4-ide#827; see N10's status and §6.2).
In the entries answered on 2026-10-26, "above" and "below" in the card's printed text point into the card's own evidence on the bench, and the options the card printed after its recommendation are marked as not taken.

**N1 — ANSWERED 2026-09-27: fates only, keyed on the modal.**
`MUST` and `DO`: armed, performed, failed (with N8's detail).
`SHANT`/`MUST NOT`: armed, violated, kept.
`MAY`: armed, exercised, lapsed.
Plus an explicit `BREACH`, and the join outcomes of a compound.
An `EVERY` member's fate is its own performance or failure, not its report to the barrier.
Looks — `PartyMismatch`, `ActionMismatch`, `GuardFailed`, `EarlyAct`, `Waiting` — are never logged.
Condition: the clock and blame a join outcome carries follow SEESAW (pending in session `every-each`) once it is ruled.
_Not part of the ruling — SEESAW concurrency review, 2026-09-29:_ most join outcomes are `FULFILLED`, which carries no time (`ValFulfilled` is nullary).
The proposed time for a fulfilment is the act's stamp for `MUST`/`DO` and the window's end for a kept `SHANT` or lapsed `MAY`; a `RAND` is fulfilled at the latest of its operands, an `ROR` at the earliest, a barrier at its last member.
That would be ruled inside SEESAW.
SEESAW was ruled on 2026-10-09 with this dual as "ruled, not built": `ValFulfilled` gets its time when its first reader is built, and that reader is this ruling's join outcomes (`EVERY-EACH-QUANTIFIER-SPEC.md` §6.1.2, landed on `unstable` in legalese/l4-ide#640, merge `c56278dd7`, 2026-10-13). With that, N1's condition on the clock and blame of a join outcome is met; the fulfilment dual itself is still unbuilt, and its first reader is this ruling's join outcomes.

**N2 — ANSWERED 2026-09-27: bearer, action pattern, modal and branch of origin, conditional on N8.**
A read names the bearer, an action pattern (the constructor, optionally with argument patterns), the modal, and whether the norm is primary or reached through a `LEST`.
An optional label on an obligation serves only to disambiguate.
The type checker warns when a read's pattern matches more than one syntactic site; it cannot see through a bearer supplied by a definition, so this is a lint, not a guarantee.
Without N8 this collapses into mandatory labels for a same-action cure (`repeat-default.l4:14,16`: `MUST payInterest` cured by `MUST payInterest`).

**N3 — ANSWERED 2026-09-27: two contract-clock instants per entry.**
`effective` is when the fate took effect — for a failure, the missed deadline.
`observed` is the stamp of the event on which the machine saw it.
Windows use `effective`; as-of reads use `observed`.
`txTime` is kept for audit only, and no read may window on `txTime` or `vtFrom`.
Conditions: a `RAND`/`ROR` compound breach takes its instant from SEESAW; `effective` is a `Maybe` until N7's rule supplies an explicit `BREACH`'s instant.
_Note 2026-10-09:_ N7 was reopened; the instant it would supply is in its proposed revision (§6.1, N7).
_Note 2026-10-26:_ N7 was answered with that revision (§6.1, N7).
_Not part of the ruling — SEESAW's direction, reported by session `every-each` on 2026-09-28 (since ruled, built and landed; see the amendment below):_ every failure would carry an effective and an observed time, and a compound would combine them along its operand tree (`RAND` the minimum of each, `ROR` the maximum, a barrier as `RAND`).
That is this ruling applied to compounds, so "a compound breach takes its instant from SEESAW" should be read as "its two instants"; nothing is built against the singular.
The review adds an invariant, effective ≤ observed, and one caution for as-of reads: under `RAND` a compound's blame can list entries whose effective instant is later than the compound's own, so an as-of read filters each entry by its **own** observed instant, not the compound's.
SEESAW also floors a failure's effective instant at the arming of the layer that failed, max(deadline, arming), which differs from this ruling for a norm armed after its own deadline.
_Settled 2026-11-23 (decided by the GM session, assumed, for Meng's review), after the review of P1:_ the two instants of an `armed` entry follow this ruling's own definitions.
A norm armed by a `HENCE` or a `LEST` is effective at the hand-off's clock and observed at the stamp of the event that revealed the hand-off, which for a `LEST` is later (a `LEST` norm armed at the missed deadline 3 on an event stamped 100 is `effective=3, observed=100`).
P1's first build wrote the hand-off clock in both fields, so `observed` went backwards in log position (0, 100, 3, 100) on a stream with a single stamp.
A root norm has no hand-off and is seen when it is armed.
The stamp belongs to the trace the hand-off happened in: a residual obligation, whose events ran out, that is traced again keeps its parent link but not the stamp, and is seen where it is armed (decided by Claude 2026-11-23, pending Meng's review, after the re-verification of P1 found a norm armed at 9 written as observed 5; `NormLogSpec` "W2b").
Three exceptions to "`observed` does not go backwards in log position" remain, and a reader that windows on time orders by (observed, log position): an `armed` entry is written when the machine first forces the clock the norm was armed at, which can be after another norm's fate with a later stamp; a compound's entry and a declared `BREACH`'s carry SEESAW's instants, the earliest moment the breach could be known; and an `ROR` runs its left operand over the whole trace before its right, because N17 is not built.
**Amended by SEESAW, ruled 2026-10-09:** a failure's `effective` is max(missed deadline, the failed obligation's own arming), not the missed deadline alone, and whenever that floor engages — an obligation entered after its own deadline — the run emits a note on the existing notes channel, a note and not an error because the deadline is a run-time value and an error would stop the trace before the drafter's own `LEST` ran; Meng's words with the ruling: "re N3, surely we should warn/error loudly about the impossible to satisfy obligation" (`EVERY-EACH-QUANTIFIER-SPEC.md` §6.1.2 rule 4 and card A2, built and landed on `unstable` in legalese/l4-ide#640, merge `c56278dd7`, 2026-10-13; the run-time note is `armedAfterDeadlineNote` in `Machine.hs`, and the witness is `jl4/examples/ok/breach-clocks.l4`, whose goldens show the note firing, re-run 2026-10-13 on an `l4` installed from `unstable` after #640).

**N4 — ANSWERED 2026-09-27: implicit write, explicit read, for legibility.**
A reader can see which provisions depend on history; windows are written in the read, not built in.
Precondition: a fate read's cache key includes the reader's contract clock.
The new name for the contract-clock instant must not be `NOW`, and a `NOW` inside a `PROVIDED` gets a warning that it means wall-clock time.
The concrete spelling is not chosen by this ruling; it returns as its own question once N1, N2, N8 and SEESAW are ruled.
Meng's note: _"perhaps we could consider the legal archaism "INSTANT" as in "Eo Instante"."_
_Answer to the note, 2026-11-22 (decided by Claude, pending Meng's review):_ `INSTANT` is a free word.
A search of the lexer, parser, type checker, prelude (`jl4-core/libraries`), `jl4/examples` and `doc` finds it only as lower-case prose in comments (`Parser.hs:3793-3814`, `TypeCheck.hs`) and as a word in one data file, never as a token.
It reads in the family of `THE JOIN`, `THE DEADLINE` and `THE ARMING`, which already name instants and parse as values (`Parser.hs:3914`), and N13's wording already writes `THE INSTANT`.
So P2 builds the contract-clock name as `THE INSTANT`: the contract-clock instant of the evaluation point, a `NUMBER` on the trace's own clock.
`NOW` keeps meaning the wall clock and gets the warning this ruling requires.
Changing the spelling later is one token, so this settles nothing the ruling reserved.
_Built in P2 (2026-11-23):_ `THE INSTANT` parses as the fourth lifecycle noun and reads the stamp of the event a `PROVIDED` guard is matched against, a `NUMBER` on the trace's clock.
It is available inside a guard and nowhere else (decided by Claude 2026-11-23, pending Meng's review: the ruling says "a guard" needs a name for its own clock, and the contract-clock instant of a continuation is a different question, because a `LEST`'s hand-off has two instants, effective and observed, and nothing here says which a continuation means).
Written elsewhere (at the top level, in a `WHERE` of the rule, in a `HENCE` or `LEST`, as an anchor after `OF`, in the body of a function) it is a check error naming the reason, which is the loud failure; a guard that calls a function passes it in as an argument.
It takes no address from the evaluation's supply, so a guard that does not mention it prints what it printed before.
A `NOW` inside a guard draws the warning the ruling requires (`lint/now-in-provided`); `NOW` is still the wall clock.
So do `TODAY` and `CURRENTTIME`, which read the same clock (decided by Claude 2026-11-24, pending Meng's review: the ruling names only `NOW`).
A wall-clock read reached through a top-level helper that the guard calls is not warned: only the guard's own expression is walked.
`INSTANT` is now a noun after `THE`, so a program that defines a value spelled `INSTANT` and writes `THE INSTANT` gets the lifecycle-noun-hides-name warning, and `jl4-service` refuses to deploy it, as it does for `JOIN`, `DEADLINE` and `ARMING`.
No `.l4` file under `jl4/examples` (the canon mirror included), `jl4-core/libraries` or `doc` uses `INSTANT` as a name (`grep -w`, case-sensitive, 2026-11-23), so nothing in the tree changes meaning; a program outside it that wrote `THE INSTANT` for its own value would, and the warning is its notice.
The spelling of the read itself, which this ruling says returns as its own question, is not built.

**N5 — ANSWERED 2026-09-27: a separate constructor, in a ledger of its own.**
Norm entries get a new `LedgerEvent` constructor and are kept in a ledger of their own, neither a party's nor the official record.
They print with their own verb, and with `bearer=` rather than `party=`.
`RECALL` / `RECALL ALL` do not see them; only N4's read family does.
The printer's `NOTIFY`→`RECORD` defect (`prettyLedgerEvent`, `EvaluateLazy.hs:703-712`: every source but `COMMIT` prints as `RECORD`; unchanged at `a12991789`) is fixed in the same change.
Cost accepted: about 20 modules match on `Assign` and need a new arm. Counted 2026-11-22 with `git grep -w Assign`: 16 files name the `LedgerEvent` constructor, 6 in `jl4-core/src` (`Evaluate/Ledger.hs`, `EvaluateLazy.hs`, `EvaluateLazy/Machine.hs`, `Ledger/Replay.hs`, `Lts/Explore.hs`, `Lts/Explore/Check.hs`) and 10 under `jl4-core/test`; the other three hits are a comment in `Syntax.hs` and the English word in `Bpmn/Lower.hs` and `Export/Document.hs`. Under `-Werror`, a `case` on a `LedgerEvent` without a wildcard fails to build until it has the new arm (`Ledger.hs:122` is one); a list comprehension that pattern-matches `Assign` skips the new constructor silently.
Meng's note: _"Together with N4, we need to try writing a tutorial/reference doc for this new behaviour, in the style of a "howto" -- with an L4 deontic chain of some form, how do we get out the information we need; if we have ledgers written in both red and black ink, how does the reader access both sides?"_
That draft is `norm-log-howto-draft.md`, beside this spec.
_Update, 2026-11-22 (decided by Claude, pending Meng's review):_ the how-to is P4's deliverable, rewritten once N4's name exists and the fates writer runs, so that every example in it is executed (`doc/test-docs.sh` type-checks the `.l4` files under `doc/`, `CLAUDE.md` §6).
It answers the note's two questions in this order: how a drafter gets a fate out (N4's read family, over the fates N1 lists), and how a reader reaches both inks (black ink by `RECALL` and `RECALL ALL`, red ink by N4's reads only, because `RECALL` is blind to norm entries by N5).
Each earlier phase that adds something a user can invoke carries a page section of its own that says what is built and what is not, so that a prerelease never ships an undocumented half-feature.

**N6 — ANSWERED 2026-09-27: `LTS-VISUALISER.md` R5 stands; a separate always-on fates writer.**
The writer keeps the activation counter, `EVERY` membership and bearer peek that fates need, since `armNormKey` returns none of them with the log off (`Machine.hs:928`; its log-off branch returns activation `0` and no bearer name).
Condition: its overhead is measured on `jl4-test`, counting all three, before it lands.
If it is material, the fallback is to switch it on when any module in the import closure contains a fate read.
R5's row in `LTS-VISUALISER.md` carries a note to this effect.

**N7 — ANSWERED 2026-10-26 (option C, revised): a declared breach is logged per reach, with SEESAW's instants and, on its log entry, the bearer its path supplies.**
Bench card N7 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option C, at 2026-10-26 06:37:18Z; Meng's note: _"when i say in the form "accept C" and the recommendation, revised, is "Accept option C, revised", does the form submission follow the revised recommendation "accept option C, revised" or do i need to mark for a Modify or Alternative answers."_.
**Accept option C, revised.**
(1) A declared breach is _logged_ each time a continuation reaches it; the shared-thunk probe is a required test.
(2) A declared `BREACH` takes SEESAW's two instants for the path that reached it (the table above).
A _bare_ `BREACH` reached on a `LEST` path of a single obligation gets, on its log entry only, the bearer of the obligation whose failure reached it, found through N8's parent link.
Under an `EVERY` barrier the entry names nobody and its parent link points to the join's failure, whose own entries name each failed member.
A bare `BREACH` on a `HENCE` path, or after a lapsed `MAY`, names nobody.
A `BREACH BY` keeps whom the drafter named.
The printed breach and the wire do not change.
(3) A party that was not forced is stored unevaluated, with its entry's `observed` instant, and forced only when a read filters by bearer, as of that instant, the same axis N12's reads use.
This needs N12; until N12 lands, rule (3) is not built and the entry carries the party's source name.
(4) "Nobody named" is distinguished from "not yet known".
A read that filters by bearer and meets "not yet known", or that windows on time and meets an entry with no instant, is an evaluation error naming the site; N3's `effective` stays a `Maybe` for that case.
Who builds what: SEESAW delivers the breach value's two instants.
The per-reach log write, the bearer on the log entry, and rules (3) and (4) are the norm-log build's, proved on the probe branch first.
The old condition "waits on SEESAW" discharges when SEESAW lands on `unstable`.
_Not part of the ruling — Meng's question, answered in chat through session GM on 2026-10-26:_ an accept binds the recommendation as printed, and the card printed the revised text, so this mark binds it with its conditions; no modify was needed (the rule is this subsection's opening paragraph).
_Checked 2026-11-22 against the card's source, not from memory:_ the card N7 on the published page carries `recommendation` text that opens "**Accept option C, revised.**" and then rules (1)–(4) and the "who builds what" paragraph, in the words recorded at the head of this entry.
The form's accept therefore bound that text; a Modify or Alternative answer was not needed, and none is owed.
_Not part of the ruling — rule (3)'s condition, 2026-10-26:_ N12 was answered the same day only in part (option D, the read cache); the instants rule (3) reads as of are held and re-posed with N10's goal A, so rule (3) stays unbuilt, and the entry carries the party's source name, until that re-posing is ruled.

_History, not the ruling:_ N7 was answered on 2026-09-27 with the text below, and the mark was cleared on the bench on 2026-09-28.
A revised recommendation, which changes only rule (2) and the SEESAW condition, follows the implementation notes and awaits a mark.
(1) A declared breach is logged each time a continuation reaches it, not once when its thunk is first built; the shared-thunk probe (§7 N7) is a required test.
(2) A bare `LEST BREACH` takes the bearer of the obligation whose failure reached it, and that failure's deadline as its instant.
(3) A party that was not forced is stored unevaluated and forced only when a read filters by bearer.
(4) "Nobody named" is distinguished from "not yet known"; only the second, when a read cannot resolve it, is an evaluation error naming the site.
Conditions: (1) to (3) are proved on the probe branch before anything lands, and a compound breach's clock waits on SEESAW.
_Not part of the ruling — implementation notes from session `every-each`, 2026-09-28, code read on `unstable`:_
every contract value, a `BREACH` included, meets its `[time, events]` at `App1`, where a breach is passed through with the time discarded (`Machine.hs:1592`), and `breachTime (ExplicitBreach _) = Nothing` (`:2843`).
Stamping there from `clockAt` (`:2194`) — fill-if-absent, so an outer application does not re-stamp — is the natural site for (1), because a shared `b MEANS BREACH` is cached once but applied once per reach.
The time must live on each failure entry, not on the compound's constructor, or it is lost when a compound concatenates blame; today neither has one (`DeclaredBreach (Maybe a) (Maybe a)` at `jl4-core/src/L4/Evaluate/ValueLazy.hs:122`, `ExplicitBreach (Blame a)` at `:156`).
_Re-read 2026-11-22 at `a12991789`: the line numbers in this paragraph are the 2026-09-28 tree's, and SEESAW (legalese/l4-ide#640) has since changed the sites.
`DeclaredBreach` now has a third field, `Maybe (Timing a)` (`jl4-core/src/L4/Evaluate/ValueLazy.hs:227`), `ExplicitBreach (Blame a)` is at `:293`, `failureTiming` (`:332`) and `fillDeclaredTiming` (`:355`) read and fill the instants, and `Machine.hs:829` fills a declared breach's timing as it is passed on.
`breachTime` and `clockAt` no longer exist.
The per-reach stamp this note proposes is built: where every contract value meets its time and events (`Machine.hs:2600-2612`), a breach with an untimed part is stamped on a fresh value by the `StampBreach` frame (`:3529`), so a `BREACH` shared by two continuations is stamped once per reach.
The per-reach log write of rule (1) is not built; that site is where it goes._
**Open gap in (2):** a `BREACH` in the `HENCE` of a kept `SHANT` gets the revealing event's stamp — an observed time with no effective counterpart; the code calls moving it "a separate decision, not taken here" (`:2104`).
Measured by SEESAW's concurrency review and re-run here on 2026-09-29: with `P SHANT x WITHIN 5 HENCE (R MUST z WITHIN 1)`, a trace of `WAIT UNTIL 10` leaves R's obligation pending, and `WAIT UNTIL 6` then `WAIT UNTIL 10` breaches it — an idle tick flips the verdict.
Rule (2)'s "the deadline of the failure that reached it" has no answer there, because no failure reached it; the review proposes the window's end (as the `EVERY` bench's ruling A3 does; A3 was built with SEESAW and landed on `unstable` in legalese/l4-ide#640, merge `c56278dd7`, 2026-10-13), and the same for a lapsed `MAY` routed to its `HENCE`.
Re-run 2026-10-13 on an `l4` installed from `unstable` after #640: both traces now breach R's `MUST z` at deadline 6, the window's end, and `jl4/examples/ok/breach-clocks.l4` (the kept-`SHANT` cases at its lines 127 and 141) holds the same cases both ways round.
It also measured that a bare `P MAY x WITHIN 5 LEST BREACH` names nobody today, so the bearer half of (2) is unbuilt, and that per-reach stamping (1) works only if the clock is forced and filled on a fresh value.

_Proposed revision, 2026-10-09, marked accept on 2026-10-26; the ruling at the head of this entry is the card's printed text of it._ Rule (1) is unchanged; (2), (3) and (4) become:
(2) A declared `BREACH` takes SEESAW's two instants for the path that reached it (`EVERY-EACH-QUANTIFIER-SPEC.md` §6.1.2, table under rule 1, on `unstable` since #640). A **bare** `BREACH` reached on the `LEST` path of a single obligation gets, on its log entry only, the bearer of the obligation whose failure reached it, found through N8's parent link; under an `EVERY` barrier the entry names nobody and links to the join's failure, whose entries name each failed member, which leaves §6.1.1's R-T3 (no injection into a bare `BREACH`) standing; a bare `BREACH` on a `HENCE` path, or after a lapsed `MAY`, names nobody; a `BREACH BY` keeps whom the drafter named. The printed breach and the wire do not change.
(3) A party that was not forced is stored unevaluated with its entry's `observed` instant, and forced only when a read filters by bearer, as of that instant (the axis N12's reads use) — which needs N12; until N12 lands, (3) is not built and the entry carries the party's source name. (Measured 2026-10-09: with `owner MEANS IF RECALL P's flag THEN Q ELSE R`, the flag recorded at 12 and `owner`'s deadline missed at 5, the breach names R if an unrelated earlier event forced `owner` and Q if nothing did.)
(4) "Nobody named" is distinguished from "not yet known". A read that filters by bearer and meets "not yet known", or that windows on time and meets an entry with no instant, is an evaluation error naming the site; N3's `effective` stays a `Maybe` for that case (SEESAW leaves a breach untimed when the hand-off clock is not a number, or outside a run).
Who builds what: SEESAW stamps the breach **value** per reach; the deontic step log is untouched by it (re-read 2026-10-13 on `unstable` @ `16f85f183`: `declareBreach`, `Machine.hs` ~917, still logs one `Breached` step at construction with `dsClock = Nothing` and no norm; re-read 2026-11-22 at `a12991789`: it is `declareBreach` at `Machine.hs:1047` and logs the same step), so the per-reach log write, the bearer on the log entry, and rules (3) and (4) are the norm-log build's, proved on the probe branch first. "Waits on SEESAW" is discharged: SEESAW landed on `unstable` on 2026-10-13 (#640). Re-run the same day on the installed `l4`, unchanged from the 2026-10-09 measurements: a shared `b MEANS BREACH` reached at two clocks keeps two instants; a bare `P MAY x WITHIN 5 LEST BREACH` prints just `BREACH`, and `BY (nobody named)` inside a compound; and a party left unforced is `Q` when nothing forced it earlier and `R` when an unrelated earlier event did.

**N8 — ANSWERED 2026-09-28: branch of origin, a parent link, and what "cured" means.**
Every entry records the branch that armed it — root, `HENCE`, `LEST`, or `ToBreach` (`DeonticStep.hs:352`) — and a link to its parent norm.
A duty's failure is "cured by reparation" when its whole `LEST` continuation reduced to `FULFILLED` and every performance in it was by the party that failed.
A lapsed `MAY` or a kept `SHANT` is never a failure (N1).
_Settled 2026-11-22 (decided by Claude, pending Meng's review), before the build starts; the three cases this ruling left open:_

- **Chained `LEST`s** (`MUST a LEST MUST b LEST MUST c`): each norm's parent is the norm whose `LEST` armed it, so a chain is a path. "Cured by reparation" for `a` is read over `a`'s whole `LEST` continuation: every norm reachable from `a` by parent links.
- **A compound inside a `LEST`** (`LEST (x RAND y)`): each operand's parent is the failed norm, with origin `LEST`, and the compound's join entry has the same parent. For a `RAND`, `a` is cured only if the whole compound is `FULFILLED` and every performance in it was by the failing party; for an `ROR`, only if the alternative that settled the choice was.
- **`EVERY` members:** a member's parent is whatever armed the `EVERY`. A member's own `HENCE` and `LEST` children have the member as parent. A barrier's shared continuation has the join's entry as parent, and the join's entry has the norm that armed the `EVERY`. This agrees with N7's rule (2): under a barrier a bare `BREACH` names nobody and links to the join's failure.
  Not settled by this: how a parent link is carried at run time which is an implementation question with a failing test to prove it, not a ruling (proposed: the `Lifecycle` record that a `HENCE` or `LEST` hand-off already rebinds).
  _Built in P1, and what the review of P1 found (2026-11-23):_ the link is carried as the `Lifecycle` record's fourth unique, a number that keys the log's own table of hand-offs.
  A compound's entry carries the same link as its operands (the `LEST (x RAND y)` case above), and an identity of its own: its site is the place of its first operand that is still an expression (the site the machine already keeps for the compound; none when both operands are values) and its activation counts the times that site was entered, so two compounds in one trace are told apart.
  A continuation defined in an imported module is shared between directives, and carries the key its first evaluation made; the key now carries the evaluation's epoch, and one made by another evaluation is dropped, not read against this evaluation's table (read as it was, it named an unrelated `LEST`'s norm as the parent of a `HENCE` norm).
  (Since smucclaw/l4-ide#1116 each directive of a file reads an imported module's rules over its own copy of the imports' heap, so a continuation defined in an imported module is no longer shared between the directives of one file; the sentence above and the next two describe the evaluator as it was when P1 was built.
  The epoch check stays, for any route that evaluates on a heap it keeps.)
  So a norm armed by a shared continuation in a later directive has no parent link.
  N11 rules the norm log per evaluation, like the ledger; the review's control run with the writer off found the same gap in the ledger (a second `#EVAL` of a shared imported residual prints no ledger), so it is inherited from import sharing, not added by the writer.
  The link is not recoverable across evaluations, and the entry says nothing rather than something wrong.
  Not built: a norm armed by a barrier's state-layer `LEST` (the `ONCE … WITHIN` deadline) has the state deadline as its observed instant, because the last completion that revealed the miss is two frames back.
  With N8 answered, N2's condition is met: a read can tell a same-action cure from the primary obligation by its branch.
  _Built in P2 (the reader, `L4.Evaluate.NormLog.Read`; decided by Claude 2026-11-24, pending Meng's review, after the review of P2's first half):_ a violated `SHANT` is repaired by its own `LEST` as a failed `MUST` is, so `a`'s failure is cured when the violation's `LEST` continuation was fulfilled by the party that failed; a violation with nothing armed after it is a breach and is not cured.
  An `ROR` in a reparation is settled by an alternative that was itself fulfilled: its norm performed (or kept, exercised or lapsed) and everything its own continuation armed fulfilled in turn, so an alternative whose `HENCE` reached a breach did not settle it, and neither did one whose continuation is still owed or failed (decided by Claude 2026-11-24, pending Meng's review; the first version took the alternative whose first norm came first, which the delta review of P2's first half showed to be wrong).
  The other alternative's miss does not count; the reader reads the cure from the alternative that settled it.
  With two alternatives fulfilled, the earliest by its own norm's instant settled it; if two share an instant and the cure answers differ, or one was fulfilled by a reparation and so cannot be placed by its own norm, or an alternative is itself a compound, or the log holds no fulfilling fate at all, the reader refuses by name, because a fulfilment carries no time.
  The machine as built never arms an `ROR`'s right alternative once its left was fulfilled (N17 is not built), so a log it wrote has one fulfilled alternative at most.
  A reparation that is a `MAY` nobody takes up lapses, which is `FULFILLED` with no performance, so the reader counts it as a cure: N8's wording read literally (decided by Claude 2026-11-24, pending Meng's review, as a meaning question, not a ruling); a `MAY` that lapses into a `BREACH` is not a cure, and a one-word change in `Read.hs` (`Lapsed`) would flip the first reading if Meng rules the other way.

**N9 — ANSWERED 2026-10-26 (option B, revised): waiver is an idiom, not a primitive.**
Bench card N9 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option B, at 2026-10-26 06:47:50Z; Meng's note: none.
**Accept option B, revised.**
No `WAIVE` primitive for the norm log.
Waiver is the other party's act: a `MAY` that `COMMIT`s which default it waives, kept apart from fates (N5), read by a guard that asks with `RECALL ALL` whether some default is still continuing.
It ships as an idiom page, with no prelude helper.
Condition: the page is published under `doc/` only once N4's contract-clock name and N12 have landed; until then the tutorial stays a draft that lists its traps, and a norm-log "continuing" read means "failed and not cured", with the doc page saying waiver is not covered.
The page says plainly that a reader written before its writers is an error until N10's lockstep option lands.
`HOMOICONICITY-SPEC`'s `WAIVE` stays OPEN there; this ruling decides only that the norm log does not wait for it.
_Not part of the ruling — the condition's "N12", 2026-10-26:_ N12 was answered the same day only in part (option D); its instants are re-posed with N10's goal A, and the page waits on that re-posing as ruled. If the re-posing is declined, this condition cannot be met as written and comes back to Meng.

**N10 — ANSWERED 2026-10-11 (word METRONOME): a run-time check now, lockstep operands as the goal.**
Bench card N10, option B now with A as the goal; Meng's note: none.
B is a run-time check. Each history read records what it asked, at which contract instant, and what it got.
If a sibling operand that runs later writes an entry that would have matched, observed at or before that instant, evaluation stops with an error naming both sites.
A static check is only a lint, as on N2.
Writer-before-reader order, including the library example, keeps working.
A runs a compound's operands in lockstep, one event at a time, interleaving the per-operand settle walk that already exists.
Before matching an event stamped t, every live norm whose deadline passed before t is settled, writing `effective` and `observed` as N3 says, in order of `effective` and then trace position.
That repeats until nothing changes, under the existing stall guard.
Conditions on A: rule whether a losing `ROR` alternative's entries are kept, since today a fulfilled left operand never runs its right one; A lands only after a corpus evaluation differential, and only after SEESAW is ruled.
B covers red ink only: a plain `RECALL` of black ink stays order-dependent until A, and the how-to and the N9 tutorial say so.
_Not part of the ruling — status and citations, checked 2026-10-11 against `origin/unstable` @ `def9a5e41`:_
SEESAW was ruled on 2026-10-09 and landed on `unstable` in legalese/l4-ide#640, merge `c56278dd7`, 2026-10-13, so A's condition "after SEESAW is ruled" is met and its corpus differential can now be run against `unstable`; it has not been run.
`EVERY-EACH-QUANTIFIER-SPEC.md` §6.1.2 called N10 "trigger word METRONOME, pending in session `ledger`" until legalese/l4-ide#665 (merged 2026-10-13, `d84dcb3d8`), made at Meng's word, corrected it to say N10 was ruled on 2026-10-11.
The line numbers printed on the bench card (`Machine.hs:1549-1559`, `:2135-2210`, `:2622-2633`) were taken at an older commit and no longer point at these sites.
On that tip, before legalese/l4-ide#827 rewrote these sites (the status paragraph below gives today's): `ValROp` pushes `RBinOp1` and runs the left operand over the full event list at `Machine.hs` ~1941, with the `RBinOp1` and `RBinOp2` arms at ~3100-3125; the `ROR` short-circuit, where a fulfilled left operand skips the right, is in the `RBinOp1` arm at ~3107; the stall guard is `maximumStalledReoffers` / `stalledChainRefusal` at ~1307-1322.

_Status 2026-11-22, not part of the ruling, read from the commits and from `doc/reference/regulative/consequences.md` at `a12991789`:_
goal A is built for a `RAND` and for an `EVERY` with `UPON EACH` or no join line, in legalese/l4-ide#827 (for smucclaw/l4-ide#1069), merged 2026-11-13.
`startCompound` (`Machine.hs:1722`) arms each operand with a gate in place of the event list; an operand that forces its gate is paused, and when every operand has paused or finished, the `Lockstep` frame (`Machine.hs:237`, `LockstepFrame` at `:324`) forces the next event and resumes each operand with it, left first; the existing `RBinOp2` arms then combine the two, so SEESAW's combination is untouched.
So a `RECALL` on one side sees every record the other side made at an earlier event and none it made at a later one, whichever side is written first.
Its corpus differential covered 199 files (`run`, `run --json`, `check` and `explore`, and `lts --steps` on the 68 with a `#TRACE`): three `explore` outputs and eighteen `lts --steps` outputs changed, and the commit message of `6ed6b067c` accounts for each.
A run-time check refuses what the order would still decide (`L4.EvaluateLazy.SiblingReads`): it logs every `RECORD`, `COMMIT`, `NOTIFY` and `RECALL` made inside a compound operand, and stops with an error naming the record, both operands, both instants and both lines.
`l4 check` warns beforehand where an `ROR`'s two sides can reach a read and a write of one record, through rules defined in the same file (`L4.Lint.SiblingReads`).
The check sees the black ink and nothing else, because no fate is written yet, so a fate read added by the build has to register with it (P2).
What is not built, against the rulings:

- An `ROR` and the members of a `ONCE ALL HAVE` barrier still run one side after the other (the `ROR`'s right side, and the group's members after the first, go over events the other side has already taken), and an `ROR` still stops running its right side once its left is fulfilled; N17 and N18 are not built, and `consequences.md` says what each case does today.
- N19's rule that a match does not see a sibling's writes at the same event is not built: where it would decide the answer, the run stops with the error above instead of answering, and two sides recording different values to one cell at one event, or a side recording an earlier instant after the other side recorded a later one, are stopped the same way (the commit titled "Check two sides' records of one cell").
- N20's settle-first round, and its run note for a stream whose stamps go backwards, are not built, so the refusal above is still N10's option B for what A does not yet order, and N20 does not yet unrule it.
- Not checked: N20's service-side sort of events by `at` (`jl4-service`), which the ruling requires.

**N20 — ANSWERED 2026-10-26 (option A): amends N10; check B is unruled for streams whose stamps never go backwards.**
Bench card N20 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option A, at 2026-10-26 07:08:33Z; Meng's note: none.
**Accept option A.**
When A lands, B is unruled for streams whose stamps never go backwards, on two conditions.
First, before settling an event, A evaluates every not-yet-evaluated deadline against the ledger as it stood before that event, so `r7.l4` is BREACHED at 1 in both orders (predicted; today `a RAND b` leaves Q due at 10).
Second, a read at an entry sees exactly the entries written at earlier entries and at its own (N19), equal stamps included.
A stream whose stamps go backwards is processed in listing order, as today, with a run note naming the first backward stamp; B stays ruled for that case, still unbuilt.
The service sorts its events by `at`, stably, as `#TRACE` does with literal stamps, so the core and the service agree, and a service caller cannot send a backward stream.
Record it as an amendment to N10 in `NORM-LOG-SPEC.md` §6.1.
_Options not taken, as the card printed them:_
**B:** sort every stream by stamp, `WAIT UNTIL` and computed stamps included, and unrule B outright; `nonmono.l4`'s first trace changes from BREACHED to FULFILLED, and a late report can no longer be written.
**C:** refuse a stream whose stamps go backwards, and unrule B outright; traces that run today are rejected.

**N11 — ANSWERED 2026-10-11 (word GOLDFISH): the norm log is per evaluation, and a resumable residual must carry the whole ledger.**
Bench card N11; Meng's note: none.
The norm log is per evaluation for now, like the ledger (`withFreshLedger`); under replay-per-request the whole event history is replayed each time, so a per-evaluation log is complete there too.
`STATEFUL-CONTRACT-DEPLOYMENT.md` §3.1 gains a requirement: a resumable residual must carry the ledger it was evaluated against, both the `RECORD`/`COMMIT` entries and the norm entries, and its replay-equivalence test must include a contract that `RECALL`s.
The requirement is added in the same change as this ruling; it is a requirement on a feature that is open there (§3.1 is a blocker), not a claim that anything is built.

**N12 — ANSWERED 2026-10-26 in part (option D): the read cache is keyed on the ledger's version; the contract instants are held.**
Bench card N12 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option D, at 2026-10-26 07:04:59Z; Meng's note: _"Does this interfere with our ability to deliver the laptop case associated with session buy-blocker?"_.
Revised 2026-10-26: **accept option D: rule the cache now, and hold the rest.**
A ledger read's cache entry is keyed on the ledger's version as well as the temporal axes, so a named helper answers as the same read written inline does.
That is the fix the cache code's own comment names ("a ledger version in the fingerprint", `TemporalContext.hs:167-181`), it needs no instants on entries, and it is independent of A.
It is recorded here and answers smucclaw/l4-ide#1034.
The rest of the card, (1)-(5) below, is held until A lands.
A answers its `RAND`-order half, (4)'s same-instant case is N19's, and (4)'s extension of N10's check follows N20.
I re-pose N12 in the PR that lands A, with only what is left: instants on entries, for a later rule asking what an earlier reader saw, and for late reports.
It comes back with a witness that fails without them, or with a recommendation to decline (option C).
_Not part of the ruling:_ the card went on to print its 2026-10-14 recommendation, (1)-(5), "kept so you can see what would change"; that text is held by this ruling, not adopted, and is not reproduced here (the table row above keeps the question as posed).
smucclaw/l4-ide#1034 is answered when the fix lands; nothing is built yet.
_Not part of the ruling — Meng's question, 2026-10-26, answered from the source and not run, since option D is not built:_ the agent-shopping laptop files (legalese/solutions, `Comply.4/agent-shopping/laptop-*.l4`) read the ledger only inside contract continuations or through a rule's inputs, never in a rule with no inputs, and `laptop-party-properties.l4:25-29` says that is deliberate because of this cache, so D cannot change their answers; that comment becomes out of date when D lands.
The one known dependant is the explorer: `0087ebbbb` on the explore branch reads "a ledger-reading rule's cached answer" into its state because the evaluator keeps it for the run, which D ends, so that part of its state and its new `LtsExploreSpec` case change when D is built (loudly: the case's expected graph fails).
_Re-checked 2026-11-22:_ `0087ebbbb` is on `unstable` now, so that dependant is in the tree: the explorer's state keeps "ledger-reading rules with no inputs whose answer has no literal" (`jl4-core/src/L4/Lts/Explore.hs:251`, `:391`, `:577`), and the case is `jl4-core/test/LtsExploreSpec.hs:406`, "a ledger-reading rule with no inputs keeps its first answer, and the state keeps it too".
D is not built, so this is a read of the code and not a run, and the case fails when D lands, as it says it will.
**What the laptop case is.** The case Meng's question names is the agent-shopping demo in `legalese/solutions`, `Comply.4/agent-shopping/`: an agent buys a laptop under a permission the service can revoke, modelled as optimistic locking, with the service's grant and revoke as acts.
Its commits run from 2026-10-24 to 2026-10-27 (solutions `81f5803` to `4041f63`); the files are `laptop-optimistic.l4`, `laptop-service-party.l4`, `laptop-party-reread.l4`, `laptop-party-properties.l4` and `laptop-revocation.l4`.
**Does this ruling interfere with delivering it? No**, on two grounds, both read from the files at solutions `4041f63`, neither run.
First, every `RECALL` in them sits in a contract continuation, in an `explore` property's `WHEN … THEN` row, or as an argument handed to a rule as an input (`(RECALL ALL OFFICIAL's …)`); none is in a rule with no inputs, which is the only shape D changes, and `laptop-party-properties.l4:25-29` says that is deliberate.
Second, the norm log writes into a ledger of its own that `RECALL` cannot see (N5), so no answer a `RECALL` gives these files can change when it lands.
What can change is their printed output: the new ledger is not printed unless the writer is on, and N5's printer fix changes the verb that a `NOTIFY` entry prints with (`RECORD` before it).
An `ATTEST` entry prints as `COMMIT` and still does: the write node carries one official-or-own flag, so nothing tells `ATTEST` from `COMMIT` (read 2026-11-23: the `ATTEST` line of `jl4/examples/ok/ledger/tests/record-flat.golden`, unchanged by P1).
An earlier version of this document, and the design note behind it, said the fix would also change `ATTEST`; that was wrong.
So each phase's gate compares `l4 run` over these five files, before and after, on a snapshot binary, and a difference in answers or exit codes, or in anything in the existing listing blocks except that verb, fails the phase.

**N13 — ANSWERED 2026-10-14 (in chat, word HINDSIGHT): "not satisfied" means outstanding, not failed.**
No bench card; Meng ruled in prose while discussing the two inks, which he defined in the same message: _"I understand black ink as userspace RECORD that is recallable in userspace. Red ink shows all the events that arise "by operation of law": the hence and the lests, fulfillments vs breaches of subcontracts. The red ink allows a contract to say "any reparation obligations not satisfied on this date" because we can interpret that as a filter for a "LEST … MUST … LEST" pattern."_
That is the reading `norm-log-howto-draft.md` already gives the two inks, so it stands.
Meng's ruling, verbatim: _"i guess "not satisfied" means the second LEST hasn't fired; indeed it means the corresponding HENCE hasn't fired. so it means outstanding, not failed."_
So a norm has three readable states, and the history expressions must spell them apart: **outstanding** (armed, and no fate yet: for any modal, none of performed, failed, violated, kept, exercised or lapsed), **failed** (a `MUST`/`DO`'s `LEST` fired; a `MAY`'s `LEST` on lapse and a `SHANT`'s on violation are N1's lapsed and violated, not failures, `DeonticStep.hs:308-311`), and **failed and not cured** (N8: failed, and the whole `LEST` continuation was not then done by the failing party).
"Satisfied" is already L4's word for an assertion that holds (`prettyAssertionOutcome`, `EvaluateLazy.hs:782`, "assertion satisfied"), so the predicate is not spelled `NOT SATISFIED`; `OUTSTANDING` is a placeholder like the how-to's other spellings, since N4 left the spelling open.
Consequences recorded with the ruling, none of them built.
_Corrected 2026-10-14, the same day, after a skeptic's check (re-run here): the first and fourth bullets missed compounds, the third named no axis, and the last misdated a fact; the corrections are marked._

- N1 already lists `armed` among the fates to log and notes that `Armed` is not a `StepOutcome` today; this ruling makes that entry load-bearing, because a norm that is armed and has no fate has no other entry, and "outstanding as at _d_" is read as an `armed` entry at an instant at or before _d_ with no fate entry for the same norm at or before _d_, **and no join of an enclosing compound decided at or before _d_** (corrected: an operand a compound has already decided is left "still waiting", which N1 never logs, so without this condition it reads as outstanding forever; measured 2026-10-14 with `l4 lts --steps` on an `l4` built from `unstable` after #640: in `(P MUST pay WITHIN 5) ROR (P MUST pay2 WITHIN 20)` with `pay2` at 3, the left operand's last step is "no more events; still waiting" under "either part: fulfilled"). A read that filters by bearer also inherits N2's naming and N7 rule (4)'s distinction between nobody named and not yet known.
- "On this date" needs an explicit instant on the read, not only `THE INSTANT`: evaluated after the fine was paid, "outstanding on 31 December" is still true of a fine armed before and paid after that date. The instant is compared with N3's `observed`, as every as-of read is (corrected: the first version named no axis). And a deadline that falls after the trace's last event is not observed until the clock runs to it: in `alice MUST borrow WITHIN 5 LEST alice MUST pay WITHIN 5` with the trace's last event at 2, `l4 lts` reports the borrow as owed with its deadline 5 still ahead, and the miss is logged only when a `WAIT UNTIL` 10 is added (skeptic's probe, re-run here 2026-10-14).
- A reparation that is armed and not yet due is outstanding, so a clause keyed to this fires before the deadline (the acceleration reading); the drafter who means overdue writes `FAILED`.
- In a single `LEST … MUST … LEST` chain the filter catches the frontier: once a reparation fails, it is failed, and the norm its `LEST` armed is what is outstanding; after a terminal `BREACH` nothing in that chain is outstanding, though nothing was paid, and that case is `FAILED AND NOT CURED`. In a compound the sibling of a breached operand is left armed with no fate, which the join condition in the first bullet covers (corrected: the first version said nothing was outstanding after a terminal `BREACH` without limiting it to one chain; a `RAND` whose left operand breaches leaves the right one "still waiting" under "both parts together: breached", re-run here).
- An operand of a compound reparation is a norm with its own key and fate, and the compound's join outcome is a further entry (N1), so a count of failures must say whether it ranges over the compound or its leaves, or `THE NUMBER OF` counts one fine twice (corrected: the first version said "after SEESAW"; operands had their own keys before #640, `armNormKey`). `OUTSTANDING` itself is unaffected, since a compound has no `armed` entry of its own.

_Built in P2, as a pure reader with no surface yet (`L4.Evaluate.NormLog.Read`; corrected 2026-11-24 after the review of P2's first half):_ a norm is outstanding as at `d` when its armed entry was observed at or before `d` and no fate was; a compound or an `EVERY ... ONCE` barrier that has decided at or before `d` leaves it `DecidedWithout`, which is the join condition above.
A member of a barrier carries the barrier in its `neEnclosing`, and a barrier's failure, expiry, release or stall counts as its decision, because a barrier that fails leaves the members whose deadline is later armed with no fate (the first version carried only the compounds that are `AND` or `OR`, and read those members as outstanding for ever).
A compound decided with a fulfilment has no instant, so the reader refuses by name (`CompoundNoInstant`) where it cannot place a read against it, with two exceptions it can answer: a `RAND` cannot have decided before its last direct operand's fate, so an earlier read is not refused; and a norm whose own fate is a performance is read as it is.
A miss or a violation under a compound that an `ROR` fulfilled is a refusal too, because the machine runs an `ROR`'s left operand over the whole trace and the log then holds a miss the contract never had, and a fulfilment cannot say whether the miss came first (N17 and N18 are not built; the ruled answer is that the dropped alternative's entries are skipped).
The cost of that refusal is stated here because it is easy to miss: the miss may be a real one, inside the alternative that won (`(Alice MUST deliver LEST Alice MUST pay 1) ROR (Bob MUST pay 2)`, where `deliver` failed and its reparation settled the `ROR`), and the reader cannot tell it from the loser's.
So a read whose pattern matches such a miss refuses at every instant, and `anyNorm` is one, including a read of the top level; a read whose pattern leaves the miss out (another action constructor, or another branch) answers.
It refuses from the instant that norm is armed, because from then on the reader cannot say whether the `ROR` had already decided, which is the same reason as for any norm armed inside an `ROR` that was fulfilled and has no fate yet.
A second limit of the same kind, found by the second delta review of P2's first half (X4) and pinned by an example: an `ROR` alternative that is fulfilled only through its own reparation (`pay 1 WITHIN 2 LEST pay 3`, with `pay 3` done at 8) makes a read before 8 refuse where "not cured yet" is knowable, because the reader looks for a fulfilling fate among the alternatives' own norms and not in their continuations; a read at or after 8 answers.
A fix would look through the continuations, and has not been built.
A bearer filter refuses on every norm whose party the machine never forced, whoever the filter names, and the party of an ordinary `PARTY name MUST ...` is known only as written while the norm is outstanding, so until N7's rule (3) is built a bearer pattern is usable on norms that have performed or failed and on the members of an `EVERY`, not on the norms still owed.

**N14 — ANSWERED 2026-10-14 (in chat, word HINDSIGHT): black-ink corrections may be written at any valid time.**
No bench card when ruled; recorded on the bench afterwards, with its mark written from these words.
Meng's ruling, verbatim: _"the standard examples that illustrate bitemporality allow events with arbitrary vt to appear in the input stream just to keep things spicy, so yes black-ink corrections may be written at any vt, and we get fascinating legal-temporality doctrines like the postal rule as a result."_
He was answering one question: whether a black-ink correction may be written at a valid time earlier than an entry another party has already read.
Two further notes were put to him in the turn that issued the word, and he accepted them by firing it: **any party** may make such a correction, and **protection** for whoever relied on the earlier state is a **read-side** matter (a bounded read), never a refused write.
On those notes it answers the "who may correct?" question that smucclaw/l4-ide#914 §6 (Non-goals) left to a later design pass: `COMMIT` and `ATTEST` already write one official record that every party appends to (`STATE-AS-LEDGER-SPEC.md` M4, ruling R1, ratified 2026-06-12), `RECORD` writes the actor's own ledger and `NOTIFY` another party's, and the transaction order shows who wrote what. It agrees with `IN-RELIANCE-ON-SPEC.md` §6 and its proposed R4: a correction is a same-valid-time, later-position append, never a destructive write.
Nothing is built for it, because the write side is shipped: `EVAL UNDER VALID TIME d (RECORD …)` stamps `vt=d`, and two entries at one valid time are a correction in which the later append wins (`Ledger.hs` `readCellBitemporal`; locked by `jl4/examples/ok/ledger/bitemporal-correction.l4`, which expects `LIST 1, 2, 2, 0`, and `jl4-core/test/BitemporalRecallSpec.hs`; measured again 2026-10-14 inside a `#TRACE`).
Consequences recorded with the ruling.
_Corrected 2026-10-14, the same day, after a skeptic's check (each re-run here): the first version said a correction could be written "at a later" valid time, that an earlier one "voids nothing", that no library could find a valid time, and that the ruling "makes N12 necessary"; all four were wrong or too strong, and the first is repeated in the #914 comment of 2026-10-14, which owes a correction._

- **Only a write at exactly the corrected entry's valid time corrects it.** A write at a later valid time supersedes from that day on and leaves the earlier span alone: with `y` = 1 at 10 Jan and 3 at 12 Jan, a read at 11 Jan is still 1. A write at an earlier valid time is ignored by any read at or after the next entry's valid time, **but it wins a bare `RECALL`**, which is the last append whatever its valid time: after 2 at 9 Jan is appended, a bare `RECALL` is 2 while reads at 10 and 20 Jan are 1 and 3 (`q.l4`, `LIST 1, 3, 1, 2, 2, 1, 3, 2`). A run-time note for that case is proposed as N16, unruled.
- **No read returns a stamp.** `RECALL ALL` returns values only (`readCellAllBitemporal :: … -> [WHNF]`). A library can recover the valid time at which a value changed by stepping days with `WHEN LAST` or `WHEN NEXT` against the day before (a skeptic's probe returned 10 Jan and 14 Jan, re-run here), or carry the date in the value; two entries at one valid time stay indistinguishable either way.
- **A valid-time clause around a step lasts until the step reaches its next obligation or terminal**, because the clause forces its expression to normal form before restoring the context (`startDeepPin`, smucclaw/l4-ide#934). So every write on the way is stamped (in the first probe the plain records after a dated step carried vt 14 Jan and 10 Jan), and **every read on the way is dated too**: the same `RECALL` answered "standing" undated and "no entry" inside the clause, exit 0 both times, and `RULES EFFECTIVE DATE` falls back to the same axis. A write that should be dated alone needs an obligation between it and anything that follows, or the write-only form proposed as N15.
- **It needs a transaction axis finer than one run.** Inside one run every entry shares one `txTime`, so `EVAL AS OF SYSTEM TIME` hides all of a trace's entries or none. A reader at the time is already bounded by log position (it sees what was appended before it), but a later rule asking what an earlier reader saw, or a reader in a `RAND` operand whose log order differs from contract time, needs more. N12, open, is the proposal for that axis.
- **Red ink is not corrected by it**: a backdated `RECORD` changes what a guard would have read, and a fate already written stands. Striking a fate out is a black-ink note plus a reader that honours it; release by the other party is a waiver act, N9. A party's own backdated "cured" note is neither a waiver nor N8's cure, and nothing yet says it has no effect; that is a gap in N9.
- **A cached reader never sees a correction**: a `RECALL` inside a definition with no inputs is re-served its first value (smucclaw/l4-ide#1034, with a second witness posted 2026-10-14), so a correction appended after its first use is invisible to it.
- A `#TRACE` event carries a `NUMBER` and nothing else, so an input event with its own valid time is written today as a scoped `RECORD` or carries its day in the action's payload. A write-only `EFFECTIVE` was ruled on 2026-10-26 as N15 (below), not built.
- `vtFrom` is a `Day`: two corrections on one day are ordered by log position only.

**N15 — ANSWERED 2026-10-26 (option A): a dated write that dates nothing else: `EFFECTIVE`.**
Bench card N15 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option A, at 2026-10-26 07:05:09Z; Meng's note: none.
**Accept option A.**
`RECORD cell IS v EFFECTIVE d`, likewise `COMMIT`, `ATTEST` and recipient-qualified `RECORD` (NOTIFY), where d is any `DATE` expression.
It stamps that one entry `vt=d` and nothing else: no context is set, so reads, `RULES EFFECTIVE DATE` and the `HENCE` continuation see what they would without it.
A write without `EFFECTIVE` is unchanged.
Condition: an explicit `EFFECTIVE` wins over an enclosing `EVAL UNDER VALID TIME` for that entry's stamp.
Condition: witnesses — p7 rewritten with `EFFECTIVE`, its plain records then carrying no valid time; an x1-style read after the write, unchanged; p9 rewritten with the date from the payload and no wrapper.
Condition: the PR carries a `doc/` page (the ledger tutorial's “Facts that change”), the `L4/Print.hs` evaluation differential (CLAUDE.md §3.2.1), and a corpus check that `EFFECTIVE` as a keyword breaks nothing; it is its own PR into `unstable`, after #499, and closes #914's §2A item when it lands.
Independent of N12 (contract instants) and N16 (bare reads).

**N16 — ANSWERED 2026-10-26 (option C): a bare `RECALL` keeps last-append, and notes a backdated answer.**
Bench card N16 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option C, at 2026-10-26 07:06:01Z; Meng's note: _"This technically is equivalent to a "latest" view in a bitemporal database, yeah?"_.
**Accept option C.**
A bare `RECALL` keeps meaning the last visible append, so no existing answer changes.
When the entry it returns has an earlier valid time than another visible entry for the same cell (a backdated append is answering), the run prints a note naming the cell, the returned entry's valid time, and the latest valid time it passed over, and suggests scoping the read with `EVAL UNDER VALID TIME` at an explicit date.
It does not suggest `TODAY`, which misses plain writes in timezones behind UTC for part of each day (above).
Condition: the note compares valid times among visible entries only; it needs no reader day, so it behaves the same inside and outside a `#TRACE`.
A forward-dated entry that is also the last append triggers nothing, and the ledger tutorial says so.
Condition: `RECALL ALL` is unchanged (whole history, append order).
Condition: the note covers `RECALL x`, `RECALL P's x` and `RECALL OFFICIAL's x` alike, and the skill's state-ledger reference (and the `l4-plugin` bundle, regenerated) gains a sentence on backdated writes and the note.
Condition: witnesses are the backdated-write probe (note fires) and a clause-free program (no note); recorded as N16 in `NORM-LOG-SPEC.md` §6, with a line on #914 that §2B stands but now warns.
B is deferred, not declined: revisit it when a trace has a day to read at.
_Not part of the ruling — Meng's question, "This technically is equivalent to a "latest" view in a bitemporal database, yeah?", answered in chat on 2026-10-26 and restated here with its qualification on 2026-11-22, from `readCellBitemporal` (`jl4-core/src/L4/Evaluate/Ledger.hs`):_
It is, if "latest" means the most recently recorded fact: a bare `RECALL` takes the last visible entry in log order and ignores valid time (`Nothing -> foldl' (\_ (_, v) -> Just v) Nothing visible`, `Ledger.hs:183`), which is the transaction-time view of a bitemporal table with no valid-time slice.
It is not what a bitemporal database calls its current state, which is the row valid now, or on a stated day, among the rows current in transaction time.
That is `RECALL` under `EVAL UNDER VALID TIME d`, which picks the entry with the greatest (valid-from, log position) among those with valid-from at or before `d`.
The two answers differ exactly when a backdated append is the last write, which is the case this ruling's note fires on; option B, deferred, would make the bare read the second kind.
The qualification: within one run every entry shares one `txTime` (`Provenance`, and the comment on `readCellBitemporal`), so "transaction order" here is log position, `EVAL AS OF SYSTEM TIME` cannot separate two entries of one trace, and log position depends on operand order wherever a compound does not run in step (N10, `ROR` and barriers).

**N17 — ANSWERED 2026-10-26 (option B): an `ROR` commits on nothing; identical alternatives merge.**
Bench card N17 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option B, at 2026-10-26 06:34:34Z; Meng's note: none.
**Accept option B.**
`ROR` follows the rule above, and nothing commits on consumption.
_(The rule, as the card's question states it: "Under goal A, every live `ROR` alternative steps on every event, a breached one is dropped, the first one fulfilled settles the choice, and nothing commits on consumption.")_
Between events the driver merges alternatives that are the same obligation with the same environment and window.
The menu redraft is documented on the regulative reference page and in NORM-LOG §7 beside the IL-hvac measurement.
The record of N10 says that CSL is precedent for verdicts only, and that the write rules are L4's.
Condition: if comparing residuals proves infeasible in the build, the PR falls back to A, says so in its description, and states the blow-up on the page.
_Options not taken, as the card printed them:_
**A:** the rule and the redraft, documented, with the blow-up stated and no merging.
**C:** A plus a loud run-time warning when one event advances two alternatives that re-enter the same recursive rule.
**D:** an election spelling (for example `ROR ELECTING`; the name is yours) in the same PR, committing at the first `MUST`/`MAY`/`DO` performance that only one alternative accepts (the first act unequivocally referable to it, per the research above), never at a shared prefix, a `SHANT` violation, an early act or a failed guard, and refusing a trace that would finish with part of the other alternative.
D needs a per-offer consumption signal and rollback of the losing branch's writes where alternatives share a prefix.
A ledger-only rollback is silently wrong, because a `RECORD` reached through a shared name fires once per run (`skeptic-design/write-once.l4`).
D is a larger PR, and A waits for it.
If a drafter means the law's election by conduct, D is the spelling for it.
_Not part of the ruling:_ the election research the card cites was done for Meng by session GM on 2026-10-26 and is kept outside this repository; it informs this ruling and does not change it. Its first finding: no authority it read treats merely beginning a prefix shared by both alternatives as electing one.

**N18 — ANSWERED 2026-10-26 (option D): a losing alternative's entries are kept, tagged, and skipped by later reads.**
Bench card N18 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option D, at 2026-10-26 07:06:13Z; Meng's note: none.
**Accept option D.**
Keep every entry: the log stays append-only.
Tag each entry with the `ROR` alternative that wrote it (a new field, set by the lockstep driver for red and black ink alike).
When the choice settles, record the alternatives it dropped and the log position at which it settled.
A plain `RECALL`, and every count of failures or outstanding norms (N13), skips a dropped alternative's entries for reads made after that position; a read made before it sees them, as it did at the time.
So asking later what a reader saw at an earlier moment still gives the answer it got, which is the as-of reading N3 rests on.
`RECALL ALL` and the audit print show every entry with its tag.
Condition: N8's "cured by reparation" and N13's "outstanding" are stated for dropped alternatives in the same PR, by the same skip rule.
_Options not taken, as the card printed them:_
**A:** keep everything, untagged, and every read sees it.
**B:** keep and tag for audit only; reads unchanged.
**C:** keep and tag, and hide dropped entries from every read once the choice settles, including reads re-asked about earlier moments.
C is not recommended: a guard that already read the entry has acted on it, and C makes a later re-asking about that moment answer differently.

**N19 — ANSWERED 2026-10-26 (option B): within one event, a match does not see a sibling's writes.**
Bench card N19 (https://claude.ai/artifact/VW7xe4F73mi5qLST8PB1CJ), marked accept, option B, at 2026-10-26 07:08:19Z; Meng's note: none.
**Accept option B.**
At one event, a match does not see the writes that sibling operands make at that event's matching; its own chain's writes stay visible.
Everything written at earlier events, and at this event's settling, is visible to all.
So `same.l4` fulfils both in either order, and `chain.l4` stays FULFILLED.
In a nested compound, "sibling" means any operand that is not on the reader's own path through the compound tree.
When two siblings write different values to one cell at one event, the run stops with an error naming the cell and both writers.
Equal values are not an error.
Writes always reach the append site, so this check is sound and the same in both orders.
The PR states A's rule and R-O1's as one rule: entries are ordered by arrival, and B fixes only what a match reads.
_Options not taken, as the card printed them:_
**A:** left then right, documented.
**C:** A plus a loud error when a read and a sibling's write overlap at one event, in either direction.

### 6.2 What is built, ruling by ruling (2026-11-22, `unstable` @ `a12991789`)

The phase column is the build plan of the status header (decided by Claude 2026-11-22, pending Meng's review).

| ruling  | on `unstable` today                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | phase                                              |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| **N1**  | built in P1: `Fate` entries for all four modals (`L4.Evaluate.NormLog`), projected from the step log's own sites (`L4.EvaluateLazy.Fates.fatesOfStep`) plus one new site for `armed` (`tellArmed`); the step log itself is unchanged and still off by default; not built: a fulfilled compound has no instants (`FULFILLED` carries no time, so there is nothing to date it by), nor does a barrier whose `MAY` member lapsed (`barrierFinish` keeps only a flag for the lapsed member)                                                                                                                                                              | P1 (built)                                         |
| **N2**  | built in P1: each entry carries the site and activation, the modal, the bearer, the action as printed, the `EVERY` membership and the parent link (N8); P2 adds the action's constructor to the entry (`neActionHead`, from the syntax) and a pure reader over bearer, constructor, modal and how the norm was armed (`L4.Evaluate.NormLog.Read`); not built: an argument pattern other than a wildcard (an entry holds the action as written, not as evaluated), the surface that names a pattern in a contract, and the lint for a pattern that matches more than one site                                                                         | P1 (the fields, built), P2 (the pattern read)      |
| **N3**  | built in P1: `neEffective` and `neObserved` on every entry; a failure's effective instant is the missed deadline floored at the arming, its observed instant the stamp of the revealing event; a norm armed by a `HENCE` or `LEST` is effective at the hand-off clock and observed at the event that revealed the hand-off (§6.1 N3, decided by the GM session 2026-11-23, assumed); a breached compound is dated by SEESAW's rule 2 (a `RAND` at the earlier effective instant, an `ROR` at the later), and a barrier's failure by its failing member's instants; `observed` does not go backwards in log position, with three exceptions (§6.1 N3) | P1 (built)                                         |
| **N4**  | built in P2: `THE INSTANT`, a fourth lifecycle noun, available inside a `PROVIDED` guard and nowhere else (assumed, not ruled: §6.1 N4), and a warning for `NOW` inside a guard; not built: the spelling of the read itself, which is its own question (§6.1 N4)                                                                                                                                                                                                                                                                                                                                                                                     | P2                                                 |
| **N5**  | built in P1: `LedgerEvent` has the constructor `Fate`, `LedgerStore` a `normLedger` that `RECALL` does not read, the listing a "Norm log:" block with its own verb, and a `NOTIFY` entry prints as `NOTIFY` (its own commit)                                                                                                                                                                                                                                                                                                                                                                                                                         | P1 (built)                                         |
| **N6**  | built in P1 as ruled: a separate always-available writer, off unless `EvalConfig.normLog`; what it costs is in §6.3, and whether that is material is not ruled; the fallback (on only when a module in the import closure has a fate read) is not built                                                                                                                                                                                                                                                                                                                                                                                              | P1 (built)                                         |
| **N7**  | built in P1: a declared breach is written once per reach (`tellBreached`, at the `StampBreach` frame), with the bearer of rules (2) and (4); rule (3) waits for N12's instants and an unforced party is stored as written                                                                                                                                                                                                                                                                                                                                                                                                                            | P1 (rules (1), (2), (4), built)                    |
| **N8**  | built in P1: each entry names the norm whose `HENCE` or `LEST` armed it, and which of the two (`NormOrigin`), carried as a fourth lifecycle unique, for a compound's entry as for its operands'; the three open cases are settled as the note under N8 says; a link made in another evaluation (a continuation shared from an imported module) is dropped; not built: the observed instant of a norm armed by a barrier's state-layer `LEST`                                                                                                                                                                                                         | P1 (built)                                         |
| **N9**  | the draft `norm-log-waiver-userspace-draft.md` and its experiment; no doc page                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | P4 (the page waits for N4's name and N12)          |
| **N10** | goal A for `RAND` and `UPON EACH`, and the run-time refusal of what order would still decide (legalese/l4-ide#827); not `ROR`, barriers or N20's settle-first round (§6.1 N10)                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | P5 (`ROR`, barriers), P6 (settle-first)            |
| **N11** | the requirement is recorded in `STATEFUL-CONTRACT-DEPLOYMENT.md` §3.1; nothing is built                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | none: it binds a later feature                     |
| **N12** | nothing: the read cache is not keyed on the ledger's version (smucclaw/l4-ide#1034 open); the contract instants are held                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | P8 (the cache); the instants are re-posed after P6 |
| **N13** | P2 builds the reader's states (`L4.Evaluate.NormLog.Read`: outstanding, performed, failed and the rest, as at an instant, with the join condition) and the field the join condition needs (`neEnclosing`); no surface reads it yet; the counts are P3                                                                                                                                                                                                                                                                                                                                                                                                | P2 (the read), P3 (the counts)                     |
| **N14** | the write side is shipped (`EVAL UNDER VALID TIME` around a `RECORD`); nothing is owed on the write side                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | none                                               |
| **N15** | nothing: `EFFECTIVE` is not a keyword of `RECORD`, `COMMIT`, `ATTEST` or `NOTIFY`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | P7 (its own change)                                |
| **N16** | nothing: no note fires for a backdated answer                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | P3                                                 |
| **N17** | nothing: an `ROR` still runs its left side over the whole trace first                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | P5                                                 |
| **N18** | nothing                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | P3 (the tag has no setter until P5)                |
| **N19** | the refusal of two sides' records of one cell, not the snapshot rule                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | P6                                                 |
| **N20** | nothing of the settle-first round or the backward-stamp run note                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | P6                                                 |

### 6.3 What P1's gate measured (2026-11-23, on `lhs`, after the review of P1)

Read from the run logs, not recalled.
The gate ran five times on `lhs`: on the first build, after the forcing mutant was added, after the review's fixes (the third gate), after the cost fix (the fourth gate), and after the merge with `unstable` @ `b33800df7` and the fix for the re-verification's finding (the merge gate).
The merge gate is the one that ran on the code in this change; a figure from an earlier gate says which.
A figure the reviewers measured says so, and says on which build.
The branch's own commits are not cited by hash; a figure says which gate it came from.

**What the writer is.**
It is off unless `EvalConfig.normLog` is set, and only tests set it (`NormLogSpec`, and `jl4-test` when `JL4_TEST_NORM_LOG` is in the environment).
No syntax, CLI flag or printed output of `l4 run` depends on it, which is why P1 has no `doc/` page: a user cannot invoke it (`CLAUDE.md` §6 applies from P2, which adds the read).

**The observer property (N6).**
`jl4-test` with `JL4_TEST_NORM_LOG=1` reproduces every golden once the "Norm log:" block is removed from the output: 5,077 examples, 0 failures at the merge gate (5,031 and 0 at the earlier gates, which ran before the merge).
The first such run found one real difference, in `ok/every/run-lifecycle-values.l4`: the carrier of N8's parent link took an address from the evaluation's supply, which moved the heap address that a ledger listing prints for a party with an unforced field.
The carrier now takes none, and `NormLogSpec` has the shape as a fixture.
Two deliberately wrong writers show that the differential can go red.
`JL4_TEST_NORM_LOG=mutant` also writes the official record, and fails 38 goldens (run in the first gate, not repeated since).
`JL4_TEST_NORM_LOG=mutant-force` evaluates a party at arming, which is the writer the ruling cares about.
It fails exactly one golden, `ok/every/run-lifecycle-values.l4` (run in the fourth gate, before the merge; repeated on the merged tree at the start of P2 and at P2's first-half head, §6.4): the heap address of the unforced party moves, from `&1436@` to `&1432@` in the reviewers' run.
No corpus file's answer changes when a party is evaluated early, so the differential catches that writer by one printed address and by nothing else.
An earlier version of this section said the golden differential alone would not catch it; the review of P1 showed that was wrong.
The fixture where the answer does change stays: `NormLogSpec` carries a party that cannot be evaluated (a trace with no events, so nothing needs it), where the forcing writer's printed result differs from the writer-off result and the real writer's does not.
Both mutants are values of a test-only field of `EvalConfig` (`normLogMutant`); nothing reads it outside a test, but it is a field of a production type.

**What the observer property does not cover.**
`jl4-test`'s goldens print the answer, the trace and the ledger listing.
They do not print a directive's list of `TYPICALLY` defaults it forced (`EvalState.presumed`, shown by `l4 batch` and `jl4-service`), so a writer that changed that list would not move a golden, and the differential did not run those two surfaces.
The step log and the norm log are not both on in any run made here: `NormLogSpec` never calls `captureDeonticSteps`, and whether the forced-on `jl4-test` reaches `execEvalModuleWithDeonticLog` was not checked.
The writer was not run through `jl4-service`, `l4 batch`, the REPL or the ledger replay (`L4.Ledger.Replay`), under an allocation limit, or with an exception escaping a directive.

**Overhead (N6).**
Wall time of `jl4-test` on `lhs`, one run each: writer off 1,301 s (an earlier draft of the branch, in a job that began 2026-11-22 at 23:42, +08:00); writer forced on 1,291 s, 1,312 s and 1,323 s in the first three gates.
At the merge gate the forced-on run took 1,380 s for 5,077 examples, with a load average of 0.20 at the start of the job and 1.00 at the end of the run; the writer-off run inside `etc/verify-branch.sh` prints no wall time, so the merge gate has no off-and-on pair, and the 1,380 s is not comparable with the 1,301 s (a different tree, 46 more examples).
The load average printed at the start of those jobs was between 0.02 and 0.42.
In the fourth gate the forced-on run took 1,721 s and the `mutant-force` run 1,746 s, in one job that shared `lhs` with a second job (load 1.08 at its start, 2.00 at its end).
Both runs are about 30 per cent slower than the earlier ones, and the cost fix removes work, so the difference is probably the load; that is an inference, because the writer-off suite was not run under that load.
The wall times of different jobs are not comparable, and the suite is dominated by parsing and type-checking, so the wall time over the corpus says little about the writer's cost on one long trace; the allocation figures below are the measure.

The cost on one long trace is the heap allocated by one `jl4-test` process on one file with `+RTS -s`, the writer on less the writer off, less the same difference for a twin of the same file size whose trace writes no fate (the twin's difference is under 0.2 MB).
The scripts that made them are not in the repository; the long traces are the reviewers' generator, and the `EVERY` is the one below.
The reviewers measured on their own machine and the other columns on `lhs`, so only the last two columns compare with each other.

An `EVERY` of N members traced with no events, so that every member is armed with its clock still a thunk (the worst case for the Armed rows that wait for a clock):

| members                        | reviewers' build                     | third gate                           | fourth gate                        |
| ------------------------------ | ------------------------------------ | ------------------------------------ | ---------------------------------- |
| 800                            | +346 MB                              | +447 MB (whole process 1.14 times)   | +191 MB (whole process 1.06 times) |
| 3,200                          | +3,903 MB (whole process 1.31 times) | +5,502 MB (whole process 1.44 times) | +776 MB (whole process 1.06 times) |
| growth for 4 times the members | 11.3                                 | 12.3                                 | 4.06                               |

The reviewers found it superlinear.
The first fix, holding the waiting rows newest first, did not remove it: at the third gate it was still superlinear, 12.3 for a step of 4.
The cause was that each member logs a `Waiting` step when its events run out and every logged step walked all the waiting rows; a step that writes no fate now skips the walk (`NormLogSpec` "S2/cost" compares the evaluation's allocation with the writer on and off at 400 members and at 1,600, and asks the excess to grow by less than 6 for a step of 4; it measured 16.5 before the fix).

The reviewers' long traces, at 400 and at 800 norms:

| trace   | 400: excess | 400: whole process | 800: excess | 800: whole process | growth for 2 times |
| ------- | ----------- | ------------------ | ----------- | ------------------ | ------------------ |
| chain   | +159 MB     | 1.11 times         | +320 MB     | 1.12 times         | 2.01               |
| lest    | +238 MB     | 1.17 times         | +480 MB     | 1.17 times         | 2.02               |
| fork    | +745 MB     | 1.11 times         | +2,160 MB   | 1.11 times         | 2.90               |
| barrier | +341 MB     | 1.10 times         | +1,067 MB   | 1.14 times         | 3.12               |

`chain` and `lest` are linear.
`fork` and `barrier` are not: the excess grows by about 2.9 and 3.1 for a doubling.
The evaluation's own allocation on those files grows by 2.7 and 2.2, so the writer's excess keeps pace with it on `fork` and outruns it on `barrier`, where the whole-process ratio rises from 1.10 to 1.14.
That is not fixed and its cause is not found: the next step would be to count what the writer does per member inside a barrier.
These excesses include rendering the "Norm log:" block, which `jl4-test` prints when the writer is on; that is not separated from the writer's own cost.
`chain` at 400 costs 159 MB for what the shape of its file makes 800 fates (400 norms, each armed and performed), about 0.2 MB each; the fates were not counted by running.
The reviewers also measured their purity probe `n6000` at 2.07 GB allocated with the writer off and 5.43 GB on, on their build.
It was not re-run, so it is the largest whole-process ratio in this section and has not been re-measured since the cost fix.

Whether that is material is N6's question and Meng's to answer, and it is owed before the writer is on for anything but a test.
N6's fallback (on only when a module in the import closure has a fate read) is the plan if it is material; P2 adds that reader.

**The laptop files.**
`l4 run` on the five agent-shopping laptop files and the `shopping-rules` module they import (`legalese/solutions` @ `4041f63`), with `JL4_FIXED_NOW` pinned, before (unstable @ `a12991789`) and after, on snapshot binaries: every run exits 0 on both, and the output differs only in the verb of a `NOTIFY` line, in two of the six files, `laptop-party-reread` (38 lines) and `laptop-service-party` (54 lines).
That verb is N5's printer fix (a `NOTIFY` entry used to print as `RECORD`, §6.1 N5).
The check normalises that verb in the new output and requires the rest to be byte-identical; it ran, and did not just find no difference, because each old output is between 178 and 530 lines.
It ran at the fourth gate and was not repeated at the merge gate.

**The gate.**
`etc/verify-branch.sh` passed on `lhs`: build, `jl4-test`, `l4-cli-test`, `jl4-core-test`, `jl4-service-test`, `check-corpus-goldens`, `check-canon-citations`, the canon mirror, `doc/test-docs.sh`, prettier and the commit trailers.
At the merge gate it ran with `--base` set to `unstable` @ `b33800df7`, on the head that carries the merge and the fix for the re-verification's finding, and counted 5,077 examples in `jl4-test`, 1,185 in `l4-cli-test` (141 pending), 2,338 in `jl4-core-test` (26 pending, `NormLogSpec` among them, with the `W3c` fixture) and 877 in `jl4-service-test` (1 pending), all with no failure.
Then `jl4-test` ran again with the writer forced on, which is the 5,077 above under "The observer property".
This section was edited after that run, in a commit that changes no code.
The cost measurements and the forcing mutant were not repeated at the merge gate, although the merge changed `Machine.hs`.
It did not run `jl4-lsp-test`, `jl4-mlir-test`, `jl4-websessions-test`, the proleg suites, the DMN harnesses, WASM or TypeScript, and a green run is not a green CI.
`lhs` builds with GHC 9.10.3 and CI pins 9.10.2.

**What an entry cannot say yet, and why.**
Each of these is "not built, because", not a gap nobody saw.

- A norm armed on a trace that never forces its clock (no events at all) has no instants: `neEffective` and `neObserved` are `Nothing` (`NormLogSpec` example 7).
  The writer never forces, and nothing has asked the clock.
- A compound's join outcome (`FateJoinedFulfilled`) carries no instants, because a `FULFILLED` value carries no time; N7's rule (4) makes a time-windowed read of one an error when the reader lands in P2.
  A barrier whose `MAY` member lapsed has none either (`barrierFinish` keeps only a flag for the lapsed member).
- A compound is named by the place of its first operand that is still an expression (`operandsSite`, which the machine also uses for the work and open-obligation limits of #1075): an operand that arrived as a value gives the other's place, and two values give none.
- A norm armed by a barrier's state-layer `LEST` has no observed instant of its own from the hand-off: `barrierStateLest` has no revealing event in hand, so its entry is observed at its arming clock.
  N17 moves barrier members into the step layer, and the instant arrives with it.
- `observed` goes backwards in log position under `ROR`, whose left side still runs over the whole trace first (§6.1 N3); N17 is the phase that ends it.
- A parent link made in another evaluation is dropped: a continuation shared from an imported module carries the link of the evaluation that made it, and N11 makes the norm log per evaluation (§6.1 N8).
  (Between the directives of one file this lapsed with smucclaw/l4-ide#1116: each directive makes an imported residual itself, and the link it carries is its own.)
- A party the machine never forced is stored as written (`WrittenBearer`), and N7's rule (3) waits for N12's instants.

**What the review of P1 changed (2026-11-23).**
Kept so that a later editor does not un-change a repair.

- M1: `NormLogSpec` evaluated no import, because `runIn` used an empty environment; it now evaluates them as `l4 run` does, and the extra-corpus control is per file.
- L1: a bearer that prints over several lines now prints one row per line, so the "Norm log:" block can be stripped by line.
- S1: the sentence on the forcing mutant above.
- S2: the figures above, which replace "allocations were not measured".
- L2: the `origin=` field of a row names the parent's line as well as its activation.
- S3 and S4: the N8 row of §6.2 and the invariant on `neNorm` in `L4.Evaluate.NormLog` now describe what is built.
- W1: a foreign parent link is dropped (the origin key carries the evaluation's epoch).
- W2: a norm armed by a `HENCE` or `LEST` is observed at the event that revealed the hand-off (§6.1 N3, decided by the GM session, assumed).
- W3: a compound's entry has its identity, its parent link and the two instants of the breach it reduced to; a barrier's entries name nobody.
- W4: a declared `BREACH` flushes the waiting Armed rows first, so the Armed row precedes it.
- Cost: the `Waiting` walk above.

**What the re-verification of P1 changed (2026-11-23).**

- W2b: a residual obligation armed by a `HENCE` or `LEST`, whose events ran out and which was traced again, carried the first trace's hand-off stamp into the second, so a norm armed at 9 was written `effective=9, observed=5`, which breaks N3's invariant, with a right answer and no error.
  The residual now keeps its parent link and drops the stamp (decided by Claude 2026-11-23, pending Meng's review: the lineage stays, because the residual still descends from the same hand-off).
- W2c: two identical directives over an imported residual armed the norm at different instants: the re-verifier saw observed 5 in the first directive and 0 in the second; the red run here saw the first (effective 0, observed 5) and stopped at that assertion.
  Both directives now write 0 and 0.
  (After smucclaw/l4-ide#1116 the second directive makes the residual itself, as the first does, and writes what the first writes (effective 3 and observed 5, then 0 and 0), which is also what the rules written in the file give; `NormLogSpec` W2c pins both.)
- M1b: the extra corpus's control did not reach a file whose only trace is an imported `#EVAL r`; it follows the import closure now, by text (`runsATrace`), so a file that mentions `TRACE` only in a comment would count as one that runs a trace.
- The N3 property of every entry covers every directive of a fixture, not only the first.
- The merge with `unstable` @ `b33800df7` (the work and open-obligation limits of #1075) kept one way to name a compound's place, `unstable`'s `rsite` and its `operandsSite`, and deleted the norm log's own `operandsSite`.
  A compound's entry is therefore named by the place of its first operand that is still an expression, not by the span of both operands (decided by Claude 2026-11-23, pending Meng's review: two ways to say where a compound is would drift, and the norm reference is found by `scope`, not by the site).

---

### 6.4 What P2's first half measured (2026-11-23, on `lhs`)

P2 is built in two halves (decided by Claude 2026-11-23, pending Meng's review), because the second half, the read's own syntax, waits for a ruling on its spelling.
The first half is the two new entry fields, the pure reader, `THE INSTANT` and the `NOW` warning.
Read from the run logs, on the head that carries them.

**What passed.**
`etc/verify-branch.sh` against the P1 head: `jl4-test` 5,077 examples, `l4-cli-test` 1,185, `jl4-core-test` 2,377, `jl4-service-test` 877, no failure; the corpus goldens (647 files), the canon checks, prettier and the trailers.
`jl4-test` with the writer forced on is 5,077 examples with no failure, in 1,356 s on a host with a load of 1.0.
The unchanged `jl4-test` count and goldens are the evidence that `THE INSTANT` took no address from the evaluation's supply: a guard that does not mention it prints what it printed before.

**What failed first, and what was done.**
The docs check (`doc/test-docs.sh`) failed once, on one orphaned file: the example file of the new docs section was named in the text and not linked.
It is linked now, and the check passes (1,821 links, 121 `.l4` files type-checked, 265 pages linked, none orphaned).
The parse-time probe (`etc/probe-parse-scaling.mjs`, which the gate runs when the parser changes) could not run on `lhs`, which has no `/usr/bin/time`.
It was run there with a shim that prints the same `-p` output, on the binary built at the head: 1,000 lines against 4,000 take 0.90 s and 3.53 s of CPU for distinct names (ratio 3.9) and 0.84 s and 3.44 s for one repeated name (ratio 4.1), where linear is 4 and the limit is 8.
That is the probe's own script with its one constant changed, not the unmodified probe.

**What was not run.**
Mutants of the reader (`NormLogReadSpec`: five, each caught) and of the guard binding (`THE INSTANT` left unbound: `I1` goes red) were run; the forcing mutant of P1 (`mutant-force`) and the allocation measurements were not repeated for this half, although the guard path of the machine changed.
The editor highlighter's word lists do not name the other three lifecycle nouns, so none was added for `THE INSTANT` (`ARMING` is in no file of `ts-shared` or the extension).
The suites listed under 6.3 as not run are still not run, except the three below.

**Suites the gate does not run, run by hand.**
A new lint code must also be in `jl4-lsp/DIAGNOSTIC-CODES.md`, and the test that enforces it is in `jl4-lsp-test`, which `etc/verify-branch.sh` does not run, so the gate was green with `lint/now-in-provided` missing from the list.
That was found after the gate, by a search for the lifecycle noun `ARMING`; the row was added, and `jl4-lsp-test` then ran on `lhs`: 336 examples, no failure.
`jl4-mlir-test` and `jl4-websessions-test` exited 0; their example counts were not read.

**The review of the first half, and the second gate (2026-11-24).**
An independent reviewer built the head in its own worktree and probed the reader and `THE INSTANT` on real traces with the writer on.
`THE INSTANT` and the `NOW` warning stood: in every guard path tried it read the stamp of the matched event, and it was refused everywhere else.
The reader did not, in four answers that were wrong with exit 0:

- **S0.** A member of an `EVERY ... ONCE` barrier, left armed when the barrier failed, read as outstanding for ever in a contract that was breached, whenever the members' deadlines differ (equal deadlines hide it, which is why the fixtures missed it). A barrier is not an `AND` or an `OR`, so no compound named it. A member now carries its barrier in `neEnclosing`, and a barrier's failure, expiry, release or stall counts as its decision.
- **S1.** The machine runs an `ROR`'s left operand over the whole trace, so a fulfilled contract had a failure in its log, and the reader reported it as a failure, where the first commit of the reader said it would refuse. It refuses now.
- **S2.** A failure cured through `LEST (x ROR y)` read as not cured when the losing alternative had failed first. The cure is read from the alternative fulfilled first.
- **S3.** A violated `SHANT` whose own `LEST` was performed by the failing party read as not cured, against N8's text. It is repaired by its continuation as a failed `MUST` is (§6.1 N8, decided by Claude 2026-11-24, pending Meng's review).

Each was reproduced as a failing example on a real trace before it was fixed: 11 of 268 examples were red.
Two written claims were false and are corrected: that a read of one bearer is not stopped by another's unknown party (it is, until N7's rule (3) is built), and that a settled `ROR` refused by name.
The reviewer's four mutants of the cure survived the first 32 examples of `NormLogReadSpec`; there are now eleven mutants of the reader, each caught: a kept or lapsed norm's continuation ignored, an exercised one's, a violated `SHANT` not recursed into and one recursed into when nothing followed it, a breached compound not counted, a miss under a fulfilled `ROR` not refused, a barrier's failure not a decision, the `RAND` bound ignored, the latest alternative taken as the one that settled an `ROR`, a nested alternative not refused, and an unknown settler guessed.
One of those survived once, because the nested alternative's own norm refused by another route; the example was changed so that the nested check is the only thing that refuses.

The second gate ran at the head that carries the fixes (`etc/verify-branch.sh` against the P1 head): `jl4-test` 5,077 examples, `l4-cli-test` 1,185, `jl4-core-test` 2,398, `jl4-service-test` 877, no failure, and every other step passes except the parse-time probe, which cannot run on `lhs` (no `/usr/bin/time`).
Run there with the shim described above it gives 0.94 s and 3.74 s of CPU for distinct names (ratio 4.0) and 0.88 s and 3.57 s for one repeated name (ratio 4.1).
`jl4-test` with the writer forced on is 5,077 examples with no failure, in 1,361 s at a load of 1.0.
`jl4-lsp-test` is 336 examples with no failure; `jl4-mlir-test` and `jl4-websessions-test` exited 0.
That a guard that does not mention `THE INSTANT` prints what it printed before rests on the unchanged goldens: the reviewer did not re-run them.

**The delta review (2026-11-24), and the third gate.**
The same reviewer built the head with the fixes and re-ran every probe.
S0 to S3, the `RAND` bound, the wall-clock lint and `THE INSTANT` all re-ran correctly on real traces.
It found one more silent wrong answer (D1) and one refusal that was true but unstated (D2).

- **D1.** The cure of a failure through `LEST (x ROR y)` took as the winner the alternative whose first norm was performed earliest, and never asked whether that alternative was itself fulfilled. `LEST ((Alice MUST pay 1 HENCE BREACH) ROR (Alice MUST pay 2))`, with Alice paying 1 and then 2, is `FULFILLED` to `l4`, and the reader said not cured. The winner is now an alternative that was itself fulfilled (§6.1 N8, decided by Claude 2026-11-24, pending Meng's review). Reproduced first: 5 of 276 examples red, then 279 green.
- **Found while fixing D1.** A norm armed by an alternative's own `HENCE` shares the alternative's compounds, so it was being read as another alternative of the `ROR`; norms are now grouped by the compounds new to them. The loser's continuation, failed or still owed (the reviewer's T1 and T2), used to refuse where the answer is definite, and answers now.
- **D2.** A real miss inside the alternative that won an `ROR` makes every read that matches it refuse, `anyNorm` and a top-level read among them, from the instant the norm is armed; a read that leaves it out answers. This was what §6.1 N13 said without its cost; the cost is stated there now, and a real-trace fixture pins both halves.

The reviewer's surviving mutants are caught: `settledByRor` reading only the innermost compound (a barrier member under an `ROR`), the `RAND` bound at its boundary, and the same-instant tie.
The mutation run over the new logic had 21 mutants of the reader: 16 were caught at once, 3 survived (a kept norm's continuation ignored, a lone settler read with compounds, an unplaceable settler guessed) and 2 did not compile (an unused binding under `-Werror`).
Each survivor has an example now. The 2 that did not compile were rewritten, and they were run again with the 3 survivors and with the lapsed half of the kept-or-lapsed mutant on its own, 6 runs in all after a green check: every one is caught.

The third gate ran at the head with these fixes (`etc/verify-branch.sh` against the P1 head, on `lhs`): `jl4-test` 5,077 examples, `l4-cli-test` 1,185, `jl4-core-test` 2,407, `jl4-service-test` 877, no failure, and every other step passes except the parse-time probe, which cannot run on `lhs` (no `/usr/bin/time`).
Run there with the same shim it gives ratios 4.0 and 4.0 (0.94 s and 3.72 s of CPU for distinct names, 0.89 s and 3.55 s for one repeated name).
`jl4-test` with the writer forced on is 5,077 examples with no failure, in 1,351 s at a load of 1.0.
`jl4-lsp-test` is 336 examples with no failure; `jl4-mlir-test` and `jl4-websessions-test` exited 0.
The reader's own suites are `NormLog` and `NormLogRead`, 279 examples with no failure.

**The runs P1's merge gate owed, made at P2's first-half head (2026-11-24, on `lhs`).**
P1's merge gate did not repeat the forcing mutant or the allocation measurements, and the first half of P2 changed the machine again (the guard path, the barrier member's `neEnclosing`), so both were run at the head.
`JL4_TEST_NORM_LOG=mutant-force` fails 5,077 examples with 1 failure, the same golden as before, `ok/every/run-lifecycle-values.l4`, whose heap address moves from `&1436@` to `&1432@`, in 1,323 s at a load of 1.0.
The same run was made on the merged P1 tree on 2026-11-23, with the same one failure.
The allocation figures are within one per cent of P1's, and the shapes do not change:

| trace                    | P1's fourth gate      | P2's first-half head  |
| ------------------------ | --------------------- | --------------------- |
| `EVERY` of 800 members   | +191 MB               | +191 MB               |
| `EVERY` of 3,200 members | +776 MB               | +778 MB               |
| chain, 400 and 800       | +159 MB and +320 MB   | +159 MB and +320 MB   |
| lest, 400 and 800        | +238 MB and +480 MB   | +238 MB and +480 MB   |
| fork, 400 and 800        | +745 MB and +2,160 MB | +750 MB and +2,181 MB |
| barrier, 400 and 800     | +341 MB and +1,067 MB | +344 MB and +1,077 MB |

`fork` and `barrier` are still superlinear, as in §6.3, and nothing was done about it here; the barrier's extra prepend per member costs about 1 per cent.
The whole-process ratios are within 0.002 of P1's: 1.06 on the `EVERY` files; at 400 norms 1.111, 1.165, 1.106 and 1.102 (chain, lest, fork, barrier); at 800, 1.115, 1.171, 1.115 and 1.143.

**What CI's WASM job found (2026-11-24), and what was done.**
The required "WASM Build & Test" job of the pull request was red on `Machine.hs`: `instantCarrier` took `negate (1099511627776 + hashUnique u)` as the address of the reference `THE INSTANT` reads, and an `Int` is 32 bits on the WASM target, so the literal is out of range (`-Woverflowed-literals`, fatal under `-Werror`).
Neither the native build nor `etc/verify-branch.sh` builds WASM, so no gate of the first half could have shown it; I did not build WASM myself, and CI's job is the check.
The defect was more than a literal: `hashUnique` is the value of a process-wide counter, so the address also depended on how many unique values the process had already made, and on a 32-bit `Int` a sum with it wraps to a positive address, which belongs to the supply of the evaluation.
The carrier addresses are now one plan in `L4.Evaluate.NormLog` (decided by Claude 2026-11-24, pending Meng's review): the negative 32-bit range is split in two halves of 2^30; the parent-link carriers of a directive's log are numbered from -1 down, and the instant carriers of an evaluation from -2^30 down, each from a counter of its own (the second is a field of the evaluation's state, not a global).
The numbers cannot meet, and a counter that reaches the end of its half stops the evaluation with a named error, never a wrapped address, which would be a silent wrong answer.
The limits are 2^30 - 1 parent-link carriers per directive and 2^30 instants read per evaluation; an evaluation that reads `THE INSTANT` once per guard would need a billion guards to reach the second.
Two properties are tests (`NormLogSpec`, "carrier addresses fit a 32-bit Int"): every address is within the range of a 32-bit `Int`, and the two halves are disjoint.
They were run first against the old address, as red: `NormLog` and `NormLogRead`, 282 examples, 2 failures (the address for the extreme hash is outside 32 bits, and a wrapped address is positive).
Then the gate was run again on `lhs` at the head that carries the fix (`etc/verify-branch.sh` against the P1 head, with `jl4-test` forced on): `jl4-test` 5,077 examples, `l4-cli-test` 1,185, `jl4-core-test` 2,412, `jl4-service-test` 877, no failure, and every other step passes except the parse-time probe, which cannot run on `lhs` and was run with the shim described above, ratios 3.9 and 4.1 (0.91 s and 3.57 s of CPU for distinct names, 0.86 s and 3.50 s for one repeated name).
`jl4-test` with the writer forced on is 5,077 examples with no failure, in 1,337 s; `jl4-lsp-test` is 336 examples with no failure; `jl4-mlir-test` and `jl4-websessions-test` exited 0.
A scan of the first half's Haskell diff for any other literal of nine or more digits found none (`originKey`'s 2^40 is a `Rational`).

### 6.5 What P2's second half builds: the read as written (N4b, option A as a fallback; decided by Claude 2026-11-24, pending Meng's review)

**Status, 2026-11-27: built on the branch `feat/norm-log-read-syntax`, a draft pull request (legalese/l4-ide#893); an independent review of it on 2026-11-26 found three blockers, six faults to fix and six nits, a second review of the pushed draft on 2026-11-27 found one blocker, five faults to fix and five nits, and the branch fixes or answers each (see "What the independent review of 2026-11-26 found" and "What the second review of 2026-11-27 found"), and a third read of the head after those fixes found no blocker and five small items, answered under "What the third review of 2026-11-27 found"; gated on `lhs` before the first review and again after it and after the second (the figures are under "What the gate measured", "What the gate measured again" and "What the gate measured the third time"); not landed.**
Nothing in this section is in `unstable`, and a sentence below that says what the read does describes what that branch does, not what a released `l4` does.
A claim below is checked by the test or command named beside it, or is listed as not checked.

N4's spelling is the one decision of P2 that is Meng's, and it is on the bench as card N4b ("Norm Log Read Spelling"), where option A takes the how-to draft's spellings and adds `AS OF`.
Meng has not marked the card.
GM asked for option A to be built as a fallback, on its own branch and in its own commits, so that the first half of P2 (§6.4) is not held and so that a ruling for another spelling replaces these commits and nothing under them.
Every decision in this section is therefore "decided by Claude 2026-11-24, pending Meng's review", and the same label is on the reference page.

**What option A is, with the five conditions of the card.**

```
OUTSTANDING          (PARTY patron MUST `return` _)
EVER FAILED          (PARTY patron MUST `return` _ UNDER LEST)
FAILED AND NOT CURED (PARTY patron MUST `return` _) AS OF deadline
CURED BY REPARATION  (PARTY _ MUST `pay` _ _ UNDER HENCE)
```

1. **`_` is a token only inside a read pattern.**
   The lexer makes a lone `_` a token (it was a lexical error before), and the parser accepts it only in a read pattern; anywhere else it says by name that a wildcard belongs in a read pattern.
   The editor's token list (`ts-shared/l4-highlight/src/tokens.ts`) and the exact printer change in the same commit as the lexer.
2. **A phrase is true when any matching norm is in that state.**
   A pattern may match more than one norm (every `MUST` of a constructor in the module); the read is true if one of them is.
   A pattern that matches no norm site is a check error, because the answer "no" would be a wrong answer with exit 0.
   A `MUST` pattern matches a norm written with `DO` as well, which the checker took it to do and the reader did not (review, B3, test R17).
   The check is exact only for an action constructor declared in the module being checked (test R9); a pattern that names a constructor declared in an imported module is not checked and answers "no" for every trace if it matches nothing (listed under "Not built").
   `UNDER LEST` and `UNDER HENCE` are not part of that check (review, S3): the check looks at the modal and the action only, so `UNDER LEST` on an action that no `LEST` of the module arms answers "no" on every trace and passes.
   The corpus file `jl4/examples/ok/norm-log/read-fates.l4` holds one, `under lest only`: its `deliver` is a root norm, and its golden shows the guard false (`tests/read-fates.golden`, the `FATE armed MUST pay fee` that is never performed).
3. **A bare pattern matches every branch.**
   `UNDER LEST` narrows it to the norms armed by a `LEST`, `UNDER HENCE` to those armed by a `HENCE`.
4. **Four phrases, and nothing else.**
   `OUTSTANDING`, `EVER FAILED`, `FAILED AND NOT CURED`, `CURED BY REPARATION`, each with an optional `AS OF <instant>`, and `THE INSTANT` (§6.4).
   `EVER FAILED` is §6.1 N13's "failed"; the counts and windows are P3's and are not built.
   An argument pattern other than `_` is not part of the grammar (the entry holds the action as written, not as evaluated, §6.4): it is a parse error at the argument, loud and not named (test R13), and the number of `_` that the constructor's fields need is checked by name (R5).
5. **`NOW` stays the wall clock**, with the warning inside a `PROVIDED` that §6.4 built.
   The words of the read are in one table in the source, so a ruling for other words changes that table and the tests that name them.

**What I decided myself (assumed, not ruled).**

- The read is an expression of type `BOOLEAN` with its own `Expr` constructor, `ReadNorm`, and not a desugaring, because a pattern is not an expression.
- The words are not reserved: `OUTSTANDING` and the others are read as a read only when what follows is `( PARTY`, a bearer (`_`, a name or a bracketed expression) and a modal, and in every other position the text parses as it does today, as a name (R6, R11).
  What was checked of "text that parses today parses as before": no golden that existed changed (the exact-print goldens among them, for every file in the goldened globs of `CLAUDE.md` §3.1), and `doc/test-docs.sh` type-checks every `.l4` of `doc/`.
  What was not checked: files outside those, such as `jl4/examples/docassemble/` and `jl4/examples/openfisca/`, which no golden covers; I did not parse the whole tree before and after, and an earlier draft of this paragraph said I would.
  One text is known to change meaning: a program's own function named like one of the phrases, applied to a bracketed regulative that has a modal, as in `OUTSTANDING (PARTY x MUST y)`, is now a read; the same function applied to a bracketed event (`PARTY x DOES y`) is still an application (R11).
  `CURED BY REPARATION` was never an application, because `BY` is a keyword.
- Where a read may stand: inside a `PROVIDED` (its instant is then `THE INSTANT`), or anywhere with an explicit `AS OF`.
  A read with neither has no instant, and is a check error saying so.
- An `AS OF` later than the contract's clock is refused when the read is reached, by name (review, B1; decided by Claude 2026-11-26, pending Meng's review; see below).
  A read made before any contract has run is refused the same way.
- A read inside an operand of a `RAND`, `ROR` or `EVERY` is a check error until the sibling check of N10, N19 and N20 is built (P5 and P6): the read could see a sibling's fate written before or after it, which is the order dependence those rulings forbid.
  It is the loud fallback of the P2 design, and it means the how-to's library example, which reads a fate beside `RAND` siblings, cannot be written yet.
  A read written in a rule that an operand uses is not seen by the checker: it is refused when it is reached, by name (review, S1, test R21).
- The bearer: `PARTY _` matches every norm; `PARTY name` is compared with the entry's party by the machine's own party key.
  An entry whose party the machine never forced refuses the read by name (N7 rule 4) until rule (3) is built, so `OUTSTANDING (PARTY x ...)` refuses on a norm that is still outstanding and has not been performed by anyone; this is the known cost of leaving rule (3) for its own step.
- A read is answered from the log as it stands when the read is reached, and two things make that true that were not at first (found by the shared-thunk probe, below): a thunk that holds a read is forced again at each use (`CtxReads` gains `crNormRead`, which vetoes `validFor`), and a read first writes what the writer holds back, forcing the arming clock of any entry still waiting for it (`readNormForcing`, one frame per clock; R14 needs the writing and R16 the forcing).
  The first is unlike a `RECALL`, whose value is kept per temporal scope on purpose (`TemporalContext.hs`, `crLedgerRead`): the norm log grows between two guards at one instant.
  The second makes a read the one place that forces an arming clock; the writer still never does.
- The writer is switched on when the module being run contains a read.
  A read in an imported module does not switch it on, and a read reached with the writer off is a run-time error that names the phrase ("ran with the norm log switched off"; test R10), never an answer from an empty log.
  The error does not name the site: `finishNormRead` takes the site and does not use it.
- Each contract run keeps its own record (review, B2, test R19).
  A run starts where a contract value is applied to its time and its events (`beginNormRun`, in the `App1` arm of the machine), and a read sees only the norms written since the run began; `EndNormRun` closes it.
  Two `EVALTRACE`s in one `#EVAL` therefore do not read each other's norms, though the directive has one ledger.
  The run bookkeeping (a frame, `EndNormRun`, and three references in `DeonticLog`: `dlHorizon`, `dlRunDepth`, `dlRunStart`) does nothing unless the writer is on, so a module with no read pays nothing; what it costs a module with a read is under "What the run boundary costs".

**What the shared-thunk probe found: two silent wrong answers, both fixed on this branch.**
The probe was written as a test of this step, and it was red twice.
It did not fail where I first expected, and I read the run's own output before saying why (`lhs` job 20261124T182904-norm-log-p2b-36965: four variants of one program under `l4 run`).

1. **R12, the cache.** A rule with no inputs that reads a fate (`pending MEANS OUTSTANDING (PARTY _ MUST deliver) AS OF 20`), named in two guards, was forced at the first, where the norm is outstanding, and its answer was served at the second, where it is not.
   Bob's payment, guarded by `NOT pending`, was refused, and the run printed the unmet norm with exit 0.
   The same program with the read written out in both guards, or `pending` used in only one, was fulfilled: that is what showed it was the sharing, and not the read.
   Cause: a thunk whose force recorded no temporal read is cached for good, and a read of the norm log recorded none.
   Fix: `crNormRead`, set by the read, vetoes `validFor` and merges as OR, so every thunk that consumed the read is forced again too.
2. **R14, the root norm reading itself.** A root norm's own guard, at its first event, reading `OUTSTANDING (PARTY _ MUST deliver)`, answered no, so the norm never matched its event.
   Cause: the writer never forces, a root norm's arming clock is forced at its first event, and until then its `Armed` entry waits in the writer (`dlPendingArmed`); the read saw a log without the norm.
   A norm armed by a `HENCE` or `LEST` has a forced clock and was not affected.
   Fix: a read writes what the writer holds back before it reads, and forces the arming clock of an entry still waiting for it.
   R14 needs only the writing, because a guard comes after the first event has forced the root norm's clock (`Contract3`); the forcing is for a read that runs before that, in the event's own time (R16, below).
   The same read with the party named is refused by name at that event (R15), because the log knows the bearer only as written (N7 rule 4; rule 3 is not built).

Each fix is its own commit, with its test red first: R12 expected 2 performed payments and got 1, and R14 expected 1 performed delivery and got 0, at the commit that added them, before either fix.
R14 was written first and I took it for the test of the forcing; the gate's mutant that removes the forcing survived it, and every other test, so R16 was written for it (below).
After the review (B1, below) R12 no longer uses a constant `AS OF 20`, which is a later instant than the contract's clock and is refused.
A rule cannot reach `THE INSTANT` (it is bound in a guard's environment, `Contract9`), so the shared read takes the instant as an input: `pending t MEANS ... AS OF t`, and each guard says `PROVIDED pending (THE INSTANT)`.
That rewrite left no thunk shared between R12's two guards, since each call has its own argument, and the mutant that makes the read not set `crNormRead` survived it (second review, finding 3); R12b restores the shared thunk with a rule that has no input and a constant `AS OF 2`, read in Alice's guard at 2 and in Bob's at 3.
The probe reaches a thunk that a guard names.
A read reached some other way, such as a function argument forced once and used twice, goes through the same `finishNormRead` and the same veto, and is not tested separately.

**What the gate measured (2026-11-24, on `lhs`, base `9d264217c`, the merge of #870).**
The gate is `etc/verify-branch.sh --base 9d264217c` and the runs it does not make, at the head whose subject is "Norm log, P2b: the crNormRead unit test did not compile (sysOnly is local to another block)" (`lhs` job 20261124T183918-norm-log-p2b-93468).
Three commits came after it, and the diff of `jl4-core/src` across them has no line that is not a comment: R15 (a test), R16 (a test, and the comment on `readNormForcing`), and a paragraph of the reference page.
A last run at the head of the code and the reference page (`lhs` job 20261124T210415-norm-log-p2b-56645) repeated the build, the two norm-log suites, `verify-branch.sh --quick` (everything but `jl4-test`) and the `crNormRead` mutant below; `jl4-test` was not run again, because nothing it reads changed (no golden, no line of code that is not a comment).
Its results: build exit 0; norm-log suites 306 examples, 0 failures; `TemporalContext` suite 23, 0 failures; `l4-cli-test` 1217, 0 failures, 141 pending; `jl4-core-test` 2740, 0 failures, 26 pending; `jl4-service-test` 877, 0 failures, 1 pending; parse-time ratio 4.1 and 3.9; every other step of `verify-branch.sh` passes except prettier, which is the install gap below.
The commit after that run changes this file and nothing else.

| what ran                                                                                                                            | result                                                                                                                                                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| build of all targets and of the test binaries                                                                                       | exit 0                                                                                                                                                                                                                                                               |
| `jl4-test` (corpus goldens, exact print, round trip)                                                                                | 5152 examples, 0 failures                                                                                                                                                                                                                                            |
| `jl4-test` with the writer forced on (`JL4_TEST_NORM_LOG=1`)                                                                        | 5152 examples, 0 failures                                                                                                                                                                                                                                            |
| `l4-cli-test`                                                                                                                       | 1217 examples, 0 failures, 141 pending                                                                                                                                                                                                                               |
| `jl4-core-test`                                                                                                                     | 2738 examples, 0 failures, 26 pending (the two norm-log suites among them: 304)                                                                                                                                                                                      |
| `jl4-service-test`                                                                                                                  | 877 examples, 0 failures, 1 pending                                                                                                                                                                                                                                  |
| `jl4-lsp-test`                                                                                                                      | 336 examples, 0 failures                                                                                                                                                                                                                                             |
| `jl4-mlir-test`, `jl4-websessions-test`                                                                                             | exit 0 (the counts were not read)                                                                                                                                                                                                                                    |
| parse time of `l4 check`, 1,000 against 4,000 lines (`verify-branch.sh` probe (a))                                                  | ratio 4.1 with distinct names, 3.9 with one name                                                                                                                                                                                                                     |
| `check-corpus-goldens`, `check-canon-citations`, `sync-canon --check` (each with its selftest), `doc/test-docs.sh`, commit trailers | pass                                                                                                                                                                                                                                                                 |
| prettier 3.4.2                                                                                                                      | the script fails on `lhs`: `@repo/prettier-config` is not installed there, the install gap of `CLAUDE.md` §3.0; run by hand with that config's options over the changed files it covers (the nine of this branch, this file and the reference page among them): pass |

No golden that existed was changed: the branch adds the four goldens of `read-fates.l4` and modifies none (`git diff --name-status` against the base).

The norm-log suites after the gate: 305 examples, 0 failures with R15 (job 20261124T184002-norm-log-p2b-98137), and 306 with R16 (job 20261124T210022-norm-log-p2b-34559).

**Mutants.**
Twelve changes to the source, each applied alone on `lhs` and run against the two norm-log suites, then taken out.
Eleven were killed in the gate; the twelfth survived it.

| the change                                          | killed by                                                                                                                                         |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `EVER FAILED` answers with `all` where it had `any` | R2, and the `answerRead` test of `EVER FAILED`                                                                                                    |
| `FAILED AND NOT CURED` loses its `not`              | R4, and the `answerRead` test of N8's cure                                                                                                        |
| `UNDER LEST` ignored                                | R2, and the `answerRead` test of `UNDER LEST` and `UNDER HENCE`                                                                                   |
| `AS OF` ignored                                     | R3, R10, R12                                                                                                                                      |
| a read with no instant not refused                  | R5                                                                                                                                                |
| a read in a compound's operand not refused          | R5                                                                                                                                                |
| a pattern that matches no site not refused          | R9                                                                                                                                                |
| the wildcard's message not named                    | R7                                                                                                                                                |
| a read does not switch the writer on                | R1, R2, R3, R4, R12, R14                                                                                                                          |
| the read does not set `crNormRead`                  | R12 and nothing else, until R12 took the instant as an input; R12b after (second review, below)                                                   |
| `validFor` does not veto `crNormRead`               | R12, then R12b among the norm-log suites; and the unit test "crNormRead vetoes" of `TemporalContextSpec`, which fails when this mutant is applied |
| `readNormForcing` does not force an arming clock    | survived: 304 examples, 0 failures. Killed after R16 was written: R16 expected 1 and got 0 (job 20261124T210022-norm-log-p2b-34559)               |

R11's red step: with the `readHead` change that makes a phrase applied to a bracketed event an application taken out, R11 fails (6 examples, 1 failure); with it put back, R11 passes (6 examples, 0 failures).

The mutants ran against the norm-log suites, not against the whole of `jl4-core-test`: a mutant these suites do not kill could be killed by another suite, and that was not asked.

**Cost.**
Test R8 passes: on a module of 400 tenants under an `EVERY`, the question `moduleReadsNormLog` asks allocates less than a twentieth of what evaluating the module allocates with the writer off.
Its own comment records what was measured when it was written: a walk over every expression of that module allocated 12.0 MB, the module's evaluation 10.7 MB, a walk through the names 0.6 MB, and the question 24 bytes; those figures were not re-measured at the gate.
A read walks the writer's list of `Armed` entries that still wait for a clock, once; that costs nothing for a module with no read, and its cost for a module with one was not measured.

**What fails loudly, and what could fail silently.**
Loud: a wildcard outside a read (named, R7), a read with no instant, a read inside a compound's operand, the wrong number of `_` (each named, R5), a pattern that matches no norm of the module (named, R9), an argument pattern other than `_` (a parse error, not named, R13), a bearer never forced, a fate with no instant when the read needs one (each a run-time error naming the refusal), a read with the writer off (a run-time error, R10), an `AS OF` later than the contract's clock and a read made before any contract has run (a run-time error naming the clock, R18), a read behind a rule that an operand uses (a run-time error when it is reached, R21).
Silent, and the reason the check for a pattern that matches no site is a rule and not a nicety: a pattern that names a constructor declared in an imported module and matches nothing (answers "no"); an `UNDER LEST` or `UNDER HENCE` that no norm of the module can satisfy (S3, above); a bearer compared by the wrong key; the one text that changes meaning (above); and the limits of the reader already listed in §6.1 N13 and N8 (a miss inside a winning `ROR` alternative, an alternative fulfilled only through its own reparation).

**Not built in this step, and why.**
The check for a pattern that matches no site among the norms of an imported module (it needs each checked module to export its norm sites).
Rule (3), forcing the bearer at the read (it needs the party's thunk in the entry, which `NormBearer` does not hold).
The sibling check: a read inside an operand is refused instead.
The check that an `UNDER LEST` or `UNDER HENCE` can be satisfied (S3): it would need, for each action of the module, which `LEST` and `HENCE` arm it, which is a walk over the names a norm refers to and not only over its own text; I judged that too large for a review fix, and did not measure it (decided by Claude 2026-11-26, pending Meng's review).
A read in an imported module switching the writer on.
A comparison of an action's arguments: a read matches on the constructor and the number of its fields, and `_` stands for each.
The read through the explorer (`l4 explore`, `l4 lts --steps`), `jl4-service`, `l4 batch` and the REPL: not run with a read in it, so what each does with one is not known; the reference page lists them as not run.
WASM: not built by me; CI's WASM job is the first test of it (§6.4 records the defect it found in the first half).
Any claim in this paragraph that a later commit makes false is corrected in that commit.

**What the independent review of 2026-11-26 found, and what the branch did.**
A reviewer (a fresh agent that read the branch at `6ba1ae809` against `9d264217c`, with no build) reported three blockers, six faults to fix and six nits.
Its report is not in the repository, so each finding is restated here with what happened to it.
The instruction was to reproduce each blocker and S2 before fixing.
The five tests R17 to R21 were written first and ran red against the code under review (`lhs` job 20261126T203527-norm-log-p2b-red-93541: 334 examples, 5 failures, and the five are R17 to R21), then green with the fixes in the working tree (job 20261126T205641-norm-log-p2b-26038: 334 examples, 0 failures).

- **B1, blocker: an `AS OF` later than the contract's clock was answered from the log written so far (R18).**
  The reference page says `AS OF` asks about the past or now, and §5's sketch says an entry later than the reader's clock is invisible to it; the code did neither.
  R16 as it stood read `OUTSTANDING (...) AS OF 5` where the delivery was performed at 2, and the final log said the norm was not outstanding as of 5.
  **Remedy, decided by Claude 2026-11-26, pending Meng's review, in its own commit (`088eea87a`): refuse.**
  The contract's clock is the later of the greatest observed instant among this run's entries and the stamp of the latest event a guard has been matched at (`dlHorizon`, set at `Contract9` before the guard).
  A read at a later instant stops with "the contract has only reached N", and with "no contract has run yet" before any run (the review's N6, which used to answer "no" from an empty log with exit 0).
  I chose refusing over answering at the clock because a refusal says what is wrong, and an answer at the clock would be a different question from the one written, answered with exit 0.
  The price: a rule cannot reach `THE INSTANT`, so a read shared by two guards either takes the instant as an input (R12) or holds a constant `AS OF`, which is refused wherever the contract has not yet reached that instant when the rule is read (R18); R12, R14, R15 and R16 were rewritten to ask at the event's own instant or earlier.
  The first version of this paragraph, and of the pull request's body, said a constant `AS OF` in a shared rule is refused; that is false, and the second review found it (finding 6).
  The branch as it stood before that commit (`8bff3a319`) builds and passes the two norm-log suites and the `TemporalContext` suite, 333 examples, 0 failures (`lhs` job 20261126T210127-norm-log-p2b-c2-76509).
  Reverted alone from the branch head (`242cee837`), the commit applies with no conflict, and the three suites pass on the reverted tree: 335 examples, 0 failures, one fewer than the head's 336 because the revert takes R18 out (`lhs` job 20261127T004251-norm-log-p2b-revert-33603).
  That revert is a local commit that was never pushed; it touches the reference page, three files under `jl4-core/src` and `NormLogSpec.hs`, no corpus file and no golden, and only those three suites were run on it, not `jl4-test` or `l4-cli-test`.
  That was at `242cee837`; it does not hold at `08d1e099b`: `git merge-tree --write-tree --merge-base=088eea87a HEAD 088eea87a^` reports one conflict, in the reference page, which the second review's fixes edited to label B1 as decided by Claude, and the code and test hunks apply; the reverted tree was not built, so whether R12b and R19b still pass on it is not known.
  Not examined: what the clock is under a `ROR`, whose operands the machine evaluates one after the other; `dlHorizon` is the latest stamp of the run, not one per operand.
- **B2, blocker: two contract runs in one directive shared one ledger (R19).**
  `#EVAL LIST (EVALTRACE c 0 ...), (EVALTRACE g 0 ...)`: the `NOT EVER FAILED` guard of `g` saw the failure written by `c`.
  Fix: a run is bounded (`beginNormRun` and `EndNormRun`, above), and a read sees the norms written since its run began.
  The first version of the fix was incomplete, and the second review found it (finding 1, below): a run that saw no event left its root norm waiting for a clock, and the next run's first read wrote it inside that run's window.
  A run that starts now first writes what the run before it left waiting (`flushArmedFinal`, as the end of a directive does).
  A run started inside another is not a run of its own: `dlRunDepth` is a flag, not a stack, so the inner run shares the outer's window and clock (finding 2); that is stated on the reference page and not changed.
- **B3, blocker: a `DO` norm could not be read although the checker said it could (R17).**
  `EVER FAILED (PARTY p MUST pay _)` against a norm written with `DO` was false on every trace, with exit 0.
  Fix: the reader's `modalMatches` takes `MUST` to match `DO`, as the checker did.
- **S1: the refusal of a read inside an operand was made only for a read written there (R21).**
  A read behind a rule an operand uses (R12's idiom) was answered by whichever sibling ran first.
  Fix: `finishNormRead` refuses by name when the sibling check says the evaluation is inside an operand.
- **S2: a run holding a read was run again at each use (R20).**
  `crNormRead` spread from the read to the thunk of the enclosing run, so `r MEANS EVALTRACE c 0 evs` used twice wrote every fate twice.
  Fix: `EndNormRun` puts the force span's `crNormRead` back as it was before the run, because the run's value does not depend on the log it read as it ran.
- **S3: not fixed (decided by Claude 2026-11-26, pending Meng's review).**
  The check that a pattern matches a norm site ignores `UNDER LEST` and `UNDER HENCE`.
  The corpus file's own `under lest only` is an instance (above).
  It is named in the reference page's silent list and in "Not built".
- **S4: it did not reproduce, and my first answer to it was wrong.**
  The review said `l4 batch` runs with the record off, citing `execEvalModuleWithJSON`.
  Nothing calls that function (the comment above `evalModuleAndDirectivesWithJSON` says so, searched 2026-11-26); `l4 batch` evaluates each row through `LSP.L4.Rules.evaluateOn`, which reaches `execEvalModuleWithDefaults`, and that starts the machine with `moduleReadsNormLog`.
  I wrote the review's sentence onto the reference page without reading that path, and the message of `8bff3a319` repeats it; `d9df7d248` withdraws the sentence.
  What `l4 batch` does with a read was not run, and the page still lists it among the places not run.
- **S5: R2 and `holds` could not fail.**
  R2's `PARTY Alice MAY deliver` line ran a module that fails R9's check and asserted nothing about the result; `holds` passed on an empty result.
  R2's line now asserts the refusal list, `[ReadMatchesNoSite deliver]`, and `holds` asserted one result.
  That was half of it (second review, finding 4): a read that is refused still gives one result, so every `holds ... shouldReturn False` passed on a refusal.
  `holds` now asserts that the directive came to a result (`eval/result`), and the sentence in its comment, that an error leaves no result, is gone because it was false.
  No test went red under it in that run, so none of the negative `holds` calls was a refusal: the instrument was weak, and no test that used it was vacuous.
- **S6: the evaluation differential of `CLAUDE.md` §3.2.1 was owed, because `L4/Print.hs` changed.**
  §6.5 did not record it, and I had not run it.
  It ran on 2026-11-27, after the fixes, and its result is under "The evaluation differential of `CLAUDE.md` §3.2.1 (S6)" below.
- **Nits.**
  N1, the printer left a bearer without brackets, so a bracketed bearer re-parsed wrongly: fixed (`Print.hs`).
  N2, `OUTSTANDING (...) AS STRING` failed at `OF`: fixed (the parser tries `AS OF` with backtracking).
  N1 and N2 were fixed with no test, and `242cee837` adds one each, R22 and R23.
  Against the code under review (`6ba1ae809` with the review's tests R17 to R21, and then R22 and R23, added in a tree that was never committed or pushed; the message of `242cee837` names a local commit for it that is not on the branch) the norm-log and `TemporalContext` suites ran 336 examples with 7 failures, R17 to R23.
  R22 fails at its `AS STRING` line, and R23 fails because the printed read is `OUTSTANDING (PARTY a PLUS b MUST pay _)`, with no brackets round the bearer (`lhs` job 20261127T004248-norm-log-p2b-red-33065).
  At `242cee837` the same suites ran 336 examples, 0 failures (job 20261127T004250-norm-log-p2b-33440).
  N3, a bearer is checked against a fresh type variable, so `PARTY 3` passes: not changed, because any type can be a party and a read is not tied to one contract's party type.
  N4, the `check/read-refused` row of `jl4-lsp/DIAGNOSTIC-CODES.md` did not say that a pattern matching no site is refused: fixed.
  N5, the global `HasSrcRange` instances for `Int` and `DeonticModal` return `Nothing`: not changed, because `Syntax.hs` has the same placeholder instances for its other plain fields (`Bool`, `RecallMode`, `LifecyclePoint`).
  N6, a read outside any run answered "no" from the empty log: resolved by B1, which refuses it (R18).

**What the second review of 2026-11-27 found, and what the branch did.**
A second fresh agent read the pushed draft at `57147fa97` against `unstable`, with no build, and reported one blocker, five faults to fix and five nits.
Its report is not in the repository, so each finding is restated.
The tests for findings 1, 3 and 4 were written first and ran red against the unchanged code (`lhs` job 20261127T040553-norm-log-p2b-27119 at `d596e3708`: 338 examples, 1 failure, and it is R19b, which expected one performed payment and got none, so g's guard had counted c's delivery; R12b and the stronger `holds` pass there, R12b because the code was right and the test restores what R12's rewrite lost, and its power is under "Mutants after the review").

- **Finding 1, blocker: a run that saw no event leaked its norm into the next run of the same directive (R19b).**
  `#EVAL LIST (EVALTRACE c 0 (LIST)), (EVALTRACE g 0 (LIST EVENT Bob (pay 1) 5))`, with `c` a `MUST deliver` and `g` guarded by `NOT OUTSTANDING (PARTY _ MUST deliver)`: `g` alone is fulfilled by Bob's payment, and after `c` it was skipped.
  A root norm's arming clock is forced at its first event and the writer never forces, so the root norm of a run with no event is still waiting for a clock when the run ends; `endNormRun` writes only the entries whose clock was forced, and the next run's first read forced the clock and wrote the old norm after that run's window had begun.
  Fix, in `beginNormRun`: a run that starts first writes what the run before it left waiting, as the end of a directive does (`flushArmedFinal`).
  I put it at the start of the next run and not at the end of this one, so that an entry whose clock is forced between the two still gets its instant, as it would have at the end of the directive.
  R19 could not see it, because its first run has an event.
  The last run of a directive has no next run to write its waiting rows, and GM asked what does: a read made after it (outside any run) forces the clock and writes the row inside that run's window, so it answers from the last run's norms (nit 8), and with no such read the end of the directive writes the row with no instant.
  Both were so before the fix and R19c pins them; it is not a red-first test, because the code already did this.
- **Finding 2: `dlRunDepth` is a flag, not a stack.**
  A contract run started inside another (`EVALTRACE` in a `LEST`, the form `Cycles.hs` uses) shares the outer run's window and clock.
  Not changed: a stack needs a decision about what the outer run's reads see of the inner run's norms, which I have not made; stated on the reference page.
- **Finding 3: R12 no longer shares a thunk, so the mutant "the read does not set `crNormRead`" survived.**
  R12b restores it (above, and the mutants table).
- **Finding 4: `holds` could not tell an answer from a refusal.**
  Above, under S5.
- **Finding 5: labels.**
  B1 and "`MUST` also matches `DO`" were not marked as decided by Claude, pending Meng's review, on the reference page, and S3 was marked only in the pull request.
  The page now marks all three, in its status line and where each is described, and S3 is marked in this section.
  The message of `8bff3a319`, which does not mark S3, is on a pushed branch and is not rewritten.
- **Finding 6: "a constant `AS OF` in a shared rule is refused" is false** (corrected under B1).
- **Nit 7, cost: each run start and each read walks the whole ledger, so the cost over k runs is k times the ledger.**
  Measured on `lhs` at `0c86a3daa` in two jobs (20261127T042443-norm-log-p2b-64424 and 20261127T064736-norm-log-p2b-42555): `l4 run` wall clock, one timing of each, of one `#EVAL` of one run of `c` and then N runs of `g`, as in "What the run boundary costs" below, with a read in `g`'s guard and with none.
  With a read: N = 1, 0.03 s; 300, 0.93 s (0.98 s in the other job); 3,000, 8.82 s (8.84 s); 10,000, 28.94 s (29.92 s); 30,000, 87.44 s.
  With none: 0.03, 0.89, 8.41, 28.12 and 83.15 s.
  The slope between successive points is 2.92, 2.87 and 2.93 ms a run with a read, and 2.79, 2.82 and 2.75 ms with none; what the read adds is 0.04, 0.41, 0.82 and 4.29 s at 300, 3,000, 10,000 and 30,000 runs, which is 0.13, 0.14, 0.08 and 0.14 ms a run.
  So the time is linear in the number of runs up to 30,000, and no growth of the cost of a run shows, with a read or without.
  Not measured: how large the ledger was at these counts (the listing a directive prints is cut off, and its last row says `activation=200` at every N, so it does not say); allocation, which the review suggested measuring with `getAllocationCounter`; and the noise, beyond the 0.05 s of the earlier measurement (the two timings of N = 300 differ by 0.05 s).
  A running count in `DeonticLog` instead of the walk is not built, because this gives no reason to.
- **Nit 8: the clock is a high-water mark for the whole run and after it,** so a read outside any run, after a run in the same directive, is answered from the last run's norms and clock.
  Stated on the reference page.
- **Nit 9: the message of the S1 refusal said "through a rule the operand uses", and it also fires for the time of an event an operand takes.**
  Reworded (R21 asserts the part of the message that did not change).
- **Nit 10: the commit `a9da941a7`, named above and in the message of `242cee837`, is local and was never pushed.**
  This file now says what it was, and the message is not rewritten.
- **Nit 11: `execEvalModuleWithJSON`, which nothing calls, started the machine with the writer off.**
  It passes `moduleReadsNormLog` now, as `execEvalModuleWithDefaults` does; nothing runs it, so nothing tests it.

**What the gate measured again (2026-11-26, on `lhs`, after the review's fixes).**
The gate is `etc/verify-branch.sh --base 90eed8e85` and the extra runs, at `8d0bf0f49`, the merge of `unstable` (at `90eed8e85`, with #886) into the branch after the fixes (`lhs` job 20261126T210138-norm-log-p2b-78686).
`lhs` has GHC 9.10.3, and CI uses 9.10.2.
Build exit 0; the two norm-log suites and `TemporalContext`: 334 examples, 0 failures; `jl4-test`: 5402 examples, 0 failures, and again with the writer forced on (`JL4_TEST_NORM_LOG=1`): 5402, 0; `jl4-core-test`: 2804, 0 failures, 26 pending; `jl4-service-test`: 983, 0 failures, 1 pending; `jl4-lsp-test`: 342, 0 failures; `jl4-mlir-test` and `jl4-websessions-test`: exit 0, the counts were not read; parse-time ratio 4.0 with distinct names and 3.9 with one; `check-corpus-goldens`, `check-canon-citations`, `sync-canon --check` (each with its selftest), `doc/test-docs.sh` and the commit trailers pass.
Two steps fail, and neither is the branch's.
`l4-cli-test` ran 1398 examples with 25 failures and 147 pending, and all 25 are in the group "l4 prove, a second solver (smucclaw/l4-ide#1098)": `lhs` has neither `z3` nor `cvc5`.
Run with that group skipped (`--skip "a second solver"`) at the same head, `l4-cli-test` ran 1362 examples, 0 failures, 141 pending (job 20261126T232339-norm-log-p2b-15720).
Plain `unstable` at `2d6af6955`, with no part of this branch, ran 1370 examples with the same 25 failures in the same group (job 20261126T191654-l4-ide-97820); CI has the solvers and decides.
The prettier step of the script fails for the install gap of `CLAUDE.md` §3.0 (`@repo/prettier-config` is not installed on `lhs`); the by-hand check is recorded below.
I ran prettier 3.4.2 with the options of `ts-shared/prettier-config/index.js` (print width 80, two-space indent, single quotes, no semicolons, trailing commas `es5`; its Svelte plugin does not apply to these files) over the nine `.md` and `.ts` files this branch changes, after the last edit to this file: pass.
The first attempt matched no file, because a newline-separated list was passed as one argument, and printed "All matched files use Prettier code style!"; the run that counts is fed the names by `xargs`, and a deliberately mis-formatted file fails the same command.

Three commits came after the gated head, and none touches `jl4-core/src` (`git diff --stat 8d0bf0f49 HEAD`, run before this commit): `d9df7d248` deletes one sentence of the reference page, `242cee837` adds R22 and R23 to `NormLogSpec.hs`, and this section is the third.
The gate was not run again on them; the norm-log and `TemporalContext` suites were, at `242cee837`: 336 examples, 0 failures (job 20261127T004250-norm-log-p2b-33440).
`doc/test-docs.sh` ran before `d9df7d248`, which deletes a sentence and no link.

**The branch with the `unstable` that came after.**
`unstable` has moved since the merge that was gated: #889 gives an operand of `RAND` or `ROR` its own frame, `App1Operand`, which `backward` turns into an `App1` before its `case`, and the run boundary hooks into that `App1` arm.
`git merge-tree` of the head against `unstable` at `1be4053cf` has no conflict, which is a statement about text.
I merged them in a separate tree (a local commit that was not pushed) and ran what runs fast: it builds, the norm-log and `TemporalContext` suites ran 336 examples, 0 failures, and the whole of `jl4-core-test` 2806 examples, 0 failures, 26 pending (`lhs` job 20261127T022945-norm-log-p2b-merge-20645).
`jl4-test` and `l4-cli-test` were not run on that merge, and CI runs the merge of the pull request.

**The evaluation differential of `CLAUDE.md` §3.2.1 (S6).**
Run on `lhs` with the binary of `242cee837` (job 20261127T022629-norm-log-p2b-935): `JL4_EVALDIFF=1` and the round-trip test print every file it covers next to its source, and `l4 run` of each original and of its printed form ran under `JL4_FIXED_NOW=2025-01-31T15:45:30Z`, each in its own directory, on a copy of the binary made first.
The output of the two runs is compared after the file name, every source position and every "(line N)" are blanked, because the printed module has other positions by construction.
The first two tries of this differential were wrong, and I record how, because both looked like results: the first compared no file (it looked for `<file>.l4.l4` and the harness writes `<file>.l4.evaldiff.l4`), and the second reported 408 of 529 files different because it left the end column of a position (`:12:3-29`) in the text.
Positive control: the first printed file against itself with one `#EVAL` added differs, as it must.
Counts: 529 files printed, 500 identical, 29 different, 0 silent (neither run printed anything), 0 with no original; 35 of the files exit non-zero in at least one of the two runs.

What the 29 are, read from the first twelve lines of each difference (the job kept no more):

- 24 differ only in diagnostics: a lint, parse or lexer warning that the original raises and the printed text does not (`lint/and-or-same-indentation`, `lint/empty-nlg`, the unknown and malformed annotations, the clause warnings, the fixity warnings and others), because the printer keeps neither the layout nor the annotations those depend on; and in `sections.l4` a deprecation warning that the printed text raises and the original does not.
- 2 differ in how a number is spelled in text the output echoes, `1.0` printed as `1`, `1.50` as `1.5` and `1_000` as `1000` (`consider-numbers-and-text.l4`, `pattern-matching-literal-clauses.l4`); both exit 1 on both sides.
- 3 exit 0 on the original and 1 on the printed text: `typically-import-use.l4`, `typically-named-site.l4` and `typically-payload-field.l4`.
  I did not read the error the printed text gives: the job kept ten lines of each difference and deleted the files.

None of the 29 is from this branch.
The same job at plain `unstable` (`1be4053cf`, job 20261127T025438-norm-log-p2b-62408) printed 534 files, 505 identical, the same 29 different, 0 silent, 0 with no original, the same three exit codes, and its positive control differs; the twelve-line differences it kept are identical, line for line, to this branch's.
The branch's change to `L4/Print.hs` is one arm, for a read (`git diff origin/unstable...HEAD -- jl4-core/src/L4/Print.hs`), and none of the 29 contains a read.
What this does not show: that the printed form of a file with a read evaluates as the original does, beyond R23 and the printed-and-parsed-again check of the round-trip test; the list of the files printed was not kept, so I did not see `read-fates.l4` named among the 500, and the rule of §3.2.1 is that the round trip covers every file the golden suite type-checks, which includes it.
The three `typically-*` files differ in exit code at plain `unstable` too; whether that is a defect of the printer or of how the harness names and places the printed file, I did not establish, and this branch neither causes it nor examined it.

**What the run boundary costs.**
Measured on `lhs` (job 20261126T233201-norm-log-p2b-85854): `6ba1ae809`, the branch before the review's fixes, against `088eea87a`, which has the run boundary and B1's refusal, both built on the same machine; each module run three times with `l4 run`, one `#EVAL` of one failing run of `c` and then 300 runs of `g`, each of which has a read in its guard (the module with a read) or `NOT FALSE` (the module with none).
A module with a read: 0.97, 0.95 and 1.01 s before, 0.97, 0.98 and 0.95 s after; the medians are equal, 0.97 s.
A module with no read: 0.89, 0.90 and 0.92 s before, 0.90, 0.87 and 0.90 s after, within noise, and its output is the same size (5265 bytes) in all six runs and byte-identical between the two builds (`cmp` on the first run of each).
The output of the module with a read differs between the two builds (77686 bytes before, 77642 after), as B2 predicts.
Of each output I read the first 600 characters: after the first run's `BREACHED`, the runs of the later build are `FULFILLED`, and the first run after it in the earlier build is a residual obligation with the guard `NOT EVER FAILED (PARTY _ MUST deliver)` still in it, which is what a guard that saw the first run's failure leaves; I did not read the rest of either output.
What this does not show: the timings of one module differ by about 0.05 s, so a cost per run below about 0.2 ms would not appear in 300 runs; the ledger was small, and a very large one was not tried (nit 7 under the second review, above, ran 30,000 runs); the head is the merge of `unstable` and docs and tests after `088eea87a`, and was not measured itself.
The first version of this paragraph said that about 0.9 s of each run is start-up.
That was wrong: the whole of one run of the same module takes 0.03 s (nit 7), so the 0.9 s is the 300 runs, at about 2.9 ms each; what 300 runs can resolve is still about 0.2 ms a run (0.05 s over 300).

**What the third gate found, and what the branch did (2026-11-27).**
The gate at `0c86a3daa` (below) was green except one step, `jl4-test` with the writer forced on (`JL4_TEST_NORM_LOG=1`), which failed on `ok/trace-exception-in-operand.l4`, the file #889 added.
The same step and the same test name fail at plain `unstable` (`513721995`), which reads like "not this branch", and the failure text says otherwise: it has two causes, one of them this branch's.

- **The branch's: the run boundary was a frame the trace saw.**
  `beginNormRun` pushed `EndNormRun` with `pushFrame`, which records a `Push` in the evaluation trace, and the pop and the exception loop record a `Pop` and an `Exit` for every frame, so a read-bearing module showed one more step between a compound and its operand.
  #889 pinned that file because an extra step there moves the first exception line.
  The expected side of the failure has seven lines of the form `│• ↯ …` (refused: not modelled, division by zero, non-exhaustive patterns, stuck) and the actual side has none of them: the leaf that stood for the operand was gone.
  It shows only when the writer is on, and `beginNormRun` runs only then, which is why `jl4-test` with the writer off passed.
  The second gate did not see it because it ran at `8d0bf0f49`, before #889, and the file did not exist there (`git log 8d0bf0f49 -- jl4/examples/ok/trace-exception-in-operand.l4` is empty).
  Fix, in `89b805fe9`: `pushFrameUntraced` pushes the frame without a `Push`, and `traceFrameExit` records every `Exit` and `Pop` of a frame that can be `EndNormRun`, and records nothing when the frame on top is `EndNormRun` (the one other `traceEval Pop`, in `forceIt`, takes off the `UpdateThunk` frame pushed on the line before it, which never is).
  It looks at the stack only when a trace is being recorded.
- **The harness's, at plain `unstable` too: `stripNormLogBlock` removed two blank lines.**
  The harness removes the `Norm log:` block, and the blank line before it, from the output of a forced run.
  Where a block follows an error's text and a trace's separator follows the block, the output without the block has a blank line there, and the stripper had removed it with the block: lines 43 and 54 of the golden, which were all the difference at `unstable` (job 20261127T064736-norm-log-p2b-42555).
  Fix, in its own commit (`08d1e099b`, test-only): the blank line stays when the first line after the block's rows is a separator.
  The first version of that commit did not compile (`after` shadows `Test.Hspec.after` under `-Wall -Werror`), which a build of `jl4-test` found before anything ran; the unpushed commit was amended, so no commit on the branch fails to build.
- **Red, then green.**
  `6a6b512bc` adds `ok/trace-exception-in-operand-with-read.l4` and its four goldens: #889's file with a rule that reads the norm log, so the writer is on in an ordinary CI run, and with its eight directives on the lines they had in the old file (64 to 71), so the first exception lines are the ones #889 pinned.
  Its golden is the old golden with the new file's name and nothing else but three `Norm log:` blocks, each a header and one row (`diff` of the two, run on `lhs` before the commit: three hunks).
  Against the code without the fix (job 20261127T073453-norm-log-p2b-8419, red step): 14 examples, 1 failure, "ok/trace-exception-in-operand-with-read.l4, parses and checks", and the failure text holds seven lines `│• ↯` on the expected side, the same seven.
  With the fix (`89b805fe9`) the file passes with the writer off and forced on, and so does the old one with the writer off.
  The cost of the fix is a test on the stack, and only while a trace is being recorded, so a run with no `#EVALTRACE` does not pay it.

**What the gate measured the third time (2026-11-27, on `lhs`, after the second review's fixes, with `unstable` at `513721995`).**
The gate is `etc/verify-branch.sh --base 513721995` and the extra runs; the branch contains `513721995` (#892) by a merge, `6e8b8aef0`.
`lhs` has GHC 9.10.3, and CI uses 9.10.2.
At `0c86a3daa`, the head the second review's fixes ended on (job 20261127T042443-norm-log-p2b-64424): build exit 0; the norm-log suites and `TemporalContext`: 339 examples, 0 failures; `jl4-test`: 5488, 0 failures, and with the writer forced on 5488 examples and 1 failure, the one above; `jl4-core-test` 2809, 0 failures, 26 pending; `jl4-service-test` 988, 0, 1 pending; `jl4-lsp-test` 342, 0; `l4-cli-test` 1443 examples, 25 failures, 161 pending, and 1407, 0 failures, 155 pending with the second-solver group skipped.
The three mutants below were run there and gave the same result as at `89b805fe9`.
At `89b805fe9`, the fix (job 20261127T073453-norm-log-p2b-8419, 8,320 s): build exit 0; the norm-log suites and `TemporalContext`: 339 examples, 0 failures; `jl4-test`: 5495 examples (5488 and the seven of the new file), 0 failures; `jl4-core-test` 2809, 0 failures, 26 pending; `jl4-service-test` 988, 0, 1 pending; `jl4-lsp-test` 342, 0; `jl4-mlir-test` and `jl4-websessions-test` exit 0, the counts not read; parse time 1,000 against 4,000 lines: ratio 4.0 with distinct names and 3.9 with one; `check-corpus-goldens` 706 files, each with its four goldens; the canon checks and `sync-canon --check` pass; `doc/test-docs.sh` 1950 links, 124 `.l4` files, 271 pages linked, 0 errors; the commit trailers.
Three things in that job are not green: the first is answered by the job after it, and the other two are the environment of `lhs`.

- `jl4-test` with the writer forced on: 5495 examples, 1 failure, the same test name, which is expected, because `89b805fe9` does not have the harness's fix.
  That job printed the name and not the text, so I did not read its text; the job below does.
- `l4-cli-test`: 1443 examples, 25 failures, 161 pending, all in "l4 prove, a second solver (smucclaw/l4-ide#1098)", because `lhs` has neither `z3` nor `cvc5`; with the group skipped, 1407 examples, 0 failures, 155 pending.
  The same 25 fail at plain `unstable` (above); CI has the solvers and decides.
- The prettier step of the script: `@repo/prettier-config` is not installed on `lhs`.
  By hand, with the options of `ts-shared/prettier-config/index.js` (as under the second gate), over the nine `.md` and `.ts` files this branch changes, fed through `xargs`, after the last edit to this file: pass; a mis-formatted file failed the same command in the same session, and the spec failed it before prettier reformatted a table in it (a width, not a sentence).

The script does not run `jl4-lsp-test`, `jl4-mlir-test` and `jl4-websessions-test`; the job ran them separately, with the results above.

At `08d1e099b`, the harness's fix (job 20261127T095459-norm-log-p2b-46633): build exit 0; the two trace files (`ok/trace-exception-in-operand.l4` and the new one), 14 examples, 0 failures with the writer off and 14, 0 with it forced on; the whole of `jl4-test`, 5495 examples, 0 failures with the writer off (1,533 s) and 5495, 0 with it forced on (1,547 s).
The only file that differs between `89b805fe9` and `08d1e099b` is `jl4/tests/Main.hs`, so the rest of the gate above stands for it.
The evaluation differential of `CLAUDE.md` §3.2.1 was not run again: `L4/Print.hs` has not changed since the binary it ran with (`git diff 242cee837 HEAD -- jl4-core/src/L4/Print.hs` is empty), and what changed since is the evaluator and a test file.
`unstable` has moved to `142aab0e0` (#894), which changes eight files, seven under `.github/` and `etc/` and one under `specs/todo/`, and none under `jl4-core/`, `jl4/` or `jl4-lsp/`; `git merge-tree --write-tree origin/unstable HEAD` has no conflict, and the gate was not run on that merge.

**What the third review of 2026-11-27 found, and what the branch did.**
A third read of the pushed head `85ca0f133` stood the second review's fixes and the nits against the code and found no blocker: the red-first order holds, the trace fix is right and no other consumer sees the run-boundary frame, the harness commit is test-only, R19c matches the pull request, the merge with `unstable` is clean and every new commit carries `Claude-Session`.
Its report is not in the repository, so its non-blocking items are restated, each fixed in a commit of its own.

- **A: R19c pinned the row and not the answer.**
  Both branches of `IF still THEN FULFILLED ELSE FULFILLED` were `FULFILLED`, so "answered from the last run's norms" (nit 8) was untested.
  `f4a33ae86`: the branches name different parties and R19c asserts which one the result holds; R19d asks outside any run, after a run that performed a delivery, as at an instant that needs the run's window kept; R19e asks as at an instant that only the event's own stamp makes reachable, which needs the clock kept (the run's guard was false, so no norm was recorded at that instant).
  Each of the three mutants below turns the tests red that it should (job 20261127T111144-norm-log-p2b-5452, which also ran the head: 4 examples, 0 failures).
- **B: two rules were stated in the present tense with no label.**
  The clock and the norms of a run are kept after it, and a contract run started inside another is part of it.
  Both are "decided by Claude 2026-11-27, pending Meng's review" on the reference page, in its status line and where each stands (`2ac24d342`), and in the pull request's list.
- **C: the S3 sentence on the page** said "left as it is by a decision of Claude" and now has the house form, so that a grep for it finds it.
- **D: four slips.**
  The comment on `pushFrameUntraced` said "second gate" (third; `1f57dcc90`, comment only).
  This section said `traceFrameExit` is "the one place" that records an `Exit` or a `Pop`; `forceIt` records a `Pop` too, for the `UpdateThunk` frame it pushed on the line before, which is never `EndNormRun`, and the sentence and the comment say so.
  B1's paragraph cited R12b for the refused half, and the refusal is R18.
  "Eight files under `.github/` and `etc/`" was seven there and one under `specs/todo/`; this file and the pull request say so.
- **E: a named run that reads, started inside an outer run, is run again at each use.**
  The review inferred it from where S2's restore of `crNormRead` sits (in `endNormRun`, which a run started inside another never reaches).
  Probed on lhs (job 20261127T110603-norm-log-p2b-67509): the inner run of a module with one `r MEANS EVALTRACE inner 0 …` used by an outer contract's `HENCE`, run by two outer runs of one directive, wrote its `deliver` norm twice (counts 1 and 2); a run named once and used twice at the top writes it once (R20).
  Two uses inside one outer run were not probed, because a read inside an operand is refused and I found no other form that uses a run twice in one run.
  R24 pins the counts as found, as a limit (`ad186ab2b`), and the reference page says so where it says a nested run belongs to its outer one.
  It is not fixed, and I have not worked out a fix: a stack of runs (finding 2 of the second review) needs a ruling first.

**Mutants after the review.**
Three were run, at `0c86a3daa` and again at `89b805fe9`, each applied to the source of the head, the norm-log and `TemporalContext` suites run, and the source restored: 317 examples each.
`cache-not-noted` (the read does not set `crNormRead`, `noteCtxRead noReads { crNormRead = True }` becomes `pure ()`): 1 failure, R12b, the test that finding 3 of the second review found missing.
`veto-dropped` (`validFor` no longer refuses a force that read the log): 2 failures, R12b and the `TemporalContext` test "validFor crNormRead vetoes".
`run-start-no-settle` (the `flushArmedFinal` at the start of a run is deleted): 1 failure, R19b.
R19c and the stronger `holds` were not mutated: R19c pins what the code already did, as said under finding 1, and I did not measure that the stronger `holds` fails on a refusal beyond reading its assertion.
Three more were run after the third review's item A, at the head of that round (job 20261127T111144-norm-log-p2b-5452, the norm-log suites, 259 examples each): the window of a run closed at the end of the run (`dlRunStart` set to the end of the ledger in `endNormRun`) turns R19d and R19e red, by value (the result holds Carol's contract and not Bob's); the clock reset at the end of a run (`dlHorizon` set to `Nothing` there) turns R19e red, the read being refused (`eval/user-error` where `eval/result` was expected); and a read that does not force the arming clock of a root norm turns R16, R18 and R19c red, R19c at its `eval/result` assertion.
For the code the first review added, the evidence that R17 to R23 test what they name is their red runs, above (R17 to R21: 334 examples, 5 failures; R17 to R23: 336 examples, 7 failures), and for B1 the revert above.

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
The same holds with two distinct events: return at 20, borrow at 21 — `borrowing RAND loan` fulfils the borrow and `loan RAND borrowing` leaves it pending (re-run 2026-09-26 on the snapshot binary).
The cause is that a compound runs its left operand over the whole trace before the right one starts (`Machine.hs:1549-1559`), so a shared instant is not what matters; which operand is on the left is.
Black ink is affected too, and in both orders (SEESAW's concurrency review, probe P3b, re-run here 2026-09-29): with `a` = `P MUST x WITHIN 5 HENCE RECORD waived` and `b` = `IF RECALL P's waived THEN FULFILLED ELSE Q MUST y WITHIN 3`, P acting at 4, `a RAND b` is `FULFILLED` — `b` decides at 0 on a record written at 4 — and `b RAND a` is `BREACHED`, which is right.
The writer-first order here reads the future, because `RECORD` carries the wall-clock transaction time, not the contract clock, so no as-of read can exclude it.
The same review measured that extending such a trace can turn `BREACHED` into `FULFILLED`: the verdict is not monotone in the trace.
SEESAW, ruled 2026-10-09 and landed 2026-10-13 (#640), makes a compound's breach report independent of operand order only for operands that make and miss deadlines, and its "what it does not promise" list names this case, an `ROR`'s unrun right operand, and the black-ink gap, which needs `RECORD` to carry the contract clock beside `at=` (`EVERY-EACH-QUANTIFIER-SPEC.md` §6.1.2; its card A9 keeps transaction time today).

Two further symptoms of the same cause, measured 2026-10-14 by session IL-hvac on an `l4` built from `unstable` after #640 and re-run here (`l4 lts --steps`):
In a loop `(PARTY I MAY a k … HENCE COMMIT seen IS k, loop) ROR (PARTY P MAY b k … HENCE COMMIT seen IS k, loop) ROR (PARTY T MAY done …)` with acts I 1, P 2, I 3, P 4, T 5, **P's act at 2 is lost**: the left operand passes over it, accepts I's act at 3 and recurses, and the `ROR` at that level never runs its right operand, so `seen` records 1, 3, 4 and nothing reports the missing 2.
In `I loop RAND P loop` with the same alternation, the official record is written 1, 3, 2, 4: operand-major, not time order.
Rule N10's run-time check B does not catch either, since neither is a history read; both are evidence for its goal A, lockstep operands.
_Status 2026-11-22, read from the commit message of `6ed6b067c` and from `consequences.md`, not re-run:_ the second symptom is what legalese/l4-ide#827 addresses, since a `RAND` now runs in step and its records are written event by event; the first is unchanged, because an `ROR` still runs its left side over the whole trace first.

**N12 — black ink picks the last write by position, and a named reader is cached.**
Measured 2026-10-09 on the installed `l4` (pre-SEESAW), from the N12 skeptic's probes; the last-write probe below re-run 2026-10-14 on an `l4` built after #640 gives the same two answers (commit order 1, 2 and R refused in `a RAND b RAND c`; 2, 1 and R fulfilled in `b RAND a RAND c`).
P commits `v` = 1 at 20, Q commits `v` = 2 at 3, and R's guard reads `v` at 25: `a RAND b RAND c` reads 2 and `b RAND a RAND c` reads 1, because the winner is the last visible entry by log position (`Ledger.hs` ~183) and under `RAND` the log is in operand order; both writes precede the reader, so an as-of filter alone would change nothing.
A named helper `gate` = `IF RECALL P's waived THEN FULFILLED ELSE Q MUST y WITHIN 3`, used at 0 and again after a `RECORD` at 4, re-serves the read from 0 at its second use and arms Q twice (due 3 and 7); written inline, the second read sees the record and only one Q is armed.
That second result happens today, independent of this spec, and follows a deliberate cache rule — a ledger read is re-served "per temporal scope" (`Machine.hs` ~1435 on `origin/unstable`, smucclaw#914 §2B), and the contract clock is not a scope — while `STATE-AS-LEDGER-SPEC.md` §4 defines a bare read as "the value as of this point in the deontic sequence".
No goldened file reads a `RECALL` inside a contract: the six under `ok/ledger/` that `RECALL` contain no contract at all.

**N3 — the window has to be on the contract clock, and the ledger's own clock cannot do it.**
Repeat default — "three or more late interest payments within 365 days" — gives the expected answer on all three traces: three late payments, termination allowed; two, refused; three but more than a year earlier, refused.
That works only because the probe stores each failure's contract-clock deadline (30, 65, 100) as the entry's value.
All 18 entries in the third trace share one transaction time (`at=…03:42:35Z`), so a window on transaction time would have counted all three failures and allowed the termination: a wrong answer, silently.

**N4 — a guard has no name for the contract-clock "now".**
`PROVIDED` could not say "within the last 365 days" because nothing in it names the current contract instant.
`NOW` exists and type-checks there, but it is the wall clock: `PROVIDED x EQUALS DATETIME_SERIAL NOW` compared an event at contract instant 5 against 740249.6… and silently did not match.
So the probe had to put the date in the action (`terminate 110`) and bind it.
A read surface for windows needs the reader's own clock, which the anchor family (`THE ARMING`, `THE JOIN`) does not supply.

**N7 — both holes are real.**
An explicit `BREACH` step is logged with no clock, no bearer and no site (`-1`, `?`, `?`), so it falls out of every windowed or per-party count.
An obligation whose party is a definition (`theDebtor MEANS borrower`) and which has no `LEST` is logged under the source name `theDebtor`, because the machine never forces the party, so "failures by `borrower`" silently misses it.
With a `LEST`, the same party is forced on the expiry path and is logged as `borrower`: whether a count is complete depends on the shape of the norm being counted.
A third hole, found in review on 2026-09-26: a named `b MEANS BREACH` shared by two `LEST`s breaches twice but writes **one** `norm breached` entry, because the breach is evaluated once and cached; the same contract with each `LEST BREACH` written inline writes two.
That entry is missing rather than unplaceable, so no "could not place" count would catch it.

**N8 — the branch alone does not say "reparation".**
`PARTY borrower MUST pay WITHIN 5 LEST BREACH` is logged as a failure **to `LEST`**, because a `LEST` whose body is a bare `BREACH` is still a `LEST`.
Telling a reparation from a breach needs what the `LEST` armed, not which branch was taken.

**N1 — fates must be modal-aware.**
The probe labels every `Matched ToHence` as "discharged", so an exercised **permission** (the borrow) is logged in the same cell as a performed **duty**.
That is the probe's shortcut, but it shows the vocabulary has to key on the modal: exercising a `MAY` is not discharging a `MUST`.

**N5 — the audit printout already misattributes machine entries.**
The ledger printer renders every source other than `COMMIT` as `RECORD` (`jl4-core/src/L4/EvaluateLazy.hs:703-712`, `prettyLedgerEvent`), so the probe's machine-observed entries print with the verb `RECORD` and `party=patron`, although the bracket does say `source=NORM`. The same default already prints every `NOTIFY` write as `RECORD`.
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
- The sketch claimed that as-of-contract-clock reads remove the ordering problem. They do not remove it between the operands of a compound, at the same instant or not (N10).
- The sketch cited three "penalty" authorities as one family. They are three doctrines, and only one supports N8 (§2 item 6).
- The sketch's example surface named `THE ARMING` as an expression. It is valid only after `OF` in a `WITHIN` or `AFTER`, and in that example it named the wrong instant. §5's examples are now marked illustrative and use no existing keyword in a new position.

A second review, on 2026-09-26, put each ruling in front of an independent skeptic before the rulings bench was published, and changed six more things.

- §1 item 3 said a continuation's clock is the stamp of the event that reached it; that is true of `HENCE` only, and a `LEST` runs on the missed deadline.
- N10 said the ordering problem was about two fates at one instant. It is about operand order, and holds for distinct instants too.
- N4 said a guard has no name for "now". `NOW` exists and means the wall clock; the missing name is the contract clock's. N4's caching argument was dropped: context reads are already fingerprinted.
- §7 N5 cited the printer two lines early, and did not say that the source was visible or that `NOTIFY` is misprinted the same way.
- §7 N7 gained the shared-breach hole.
- N1 gained `DO` and the correct classification of `Waiting`; N9 now cites the `WAIVE` already proposed in `HOMOICONICITY-SPEC.md`.

A third review, on 2026-11-22, brought the spec up to date before the build began, and changed these things.

- The status header said nothing was implemented and that N10's goal A was partly built in draft legalese/l4-ide#753. Goal A is built on `unstable` for `RAND` and `UPON EACH` by a different change, legalese/l4-ide#827 (merged 2026-11-13), and #753 is an open draft that was never merged.
- N10's status paragraphs, which described #753's behaviour, are replaced by what #827 does and does not do, read from its commits and from `doc/reference/regulative/consequences.md`.
- Every code citation was re-read at `a12991789`: most line numbers had moved by hundreds, `clockAt` and `breachTime` no longer exist, `DeclaredBreach` has a third field, and `0087ebbbb` and the explorer's dependence on the ledger cache are now on `unstable`.
  The `Assign` constructor, `DeonticStep.hs` and the printer defect are unchanged.
- Meng's notes on N4, N5, N7, N12 and N16 are answered where the notes are recorded, and §6.2 says what is built, ruling by ruling.
- Not re-run: the measurements of §7 and of the dated notes, which were made on binaries older than #827 and #640.

An independent review of P2b, on 2026-11-26, read the branch with no build and found three blockers, six faults to fix and six nits; each is restated, with what the branch did about it, in §6.5 under "What the independent review of 2026-11-26 found", and it changed these things.

- §6.5 said an `AS OF` could stand anywhere and was answered from the log as it stood; an `AS OF` later than the contract's clock is now refused, so a read shared between guards takes the instant as an input (B1, decided by Claude 2026-11-26, pending Meng's review).
- §6.5 did not say which norms a read sees, and the code let it see every norm the directive had written, including another contract run's; it sees the norms written since its own contract run began (B2).
- §6.5 said the check for a pattern that matches no site made a read exact; it does not look at `UNDER LEST` or `UNDER HENCE` (S3, not fixed: decided by Claude 2026-11-26, pending Meng's review), and a `MUST` pattern now matches a `DO` norm, as the checker said it did (B3).
- A sentence of the reference page said `l4 batch` runs with the record off; I took it from the review without reading the code it cited, it did not reproduce, and `d9df7d248` withdraws it (S4).

A second independent review of P2b, on 2026-11-27, read the pushed draft with no build and found one blocker, five faults to fix and five nits; each is restated, with what the branch did, in §6.5 under "What the second review of 2026-11-27 found", and it changed these things.

- §6.5 said a read sees only the norms written since its own run began; a run that saw no event left its norm waiting for a clock, and the next run's first read wrote it inside its own window.
  A run that starts now writes what the run before it left waiting (finding 1, R19b).
  What writes the waiting rows after the last run of a directive is a read outside any run, else the end of the directive, and R19c pins both.
- R12 had stopped sharing a thunk, so the mutant that makes a read not set `crNormRead` survived; R12b shares a thunk again (finding 3).
- The test helper `holds` could not tell an answer from a refusal; it asserts that the directive came to a result (finding 4).
- §6.5 said a constant `AS OF` in a shared rule is refused; it is refused only when it is later than the contract's clock (finding 6, B1).
- A contract run inside another shares the outer run's window and clock; stated, not changed (finding 2).
- The gate's forced-writer run of `jl4-test` exists to show that the writer changes nothing a golden prints except its own block.
  At the third gate it showed that the run boundary changed a trace, and `EndNormRun` is now a frame the trace does not see; the same run showed a harness defect older than the branch, in `stripNormLogBlock`, fixed in a commit of its own.
  What is new in the corpus is `ok/trace-exception-in-operand-with-read.l4`, so that an ordinary run, which switches the writer on only for a module that reads, covers the case (§6.5, "What the third gate found").

A third review of P2b, on 2026-11-27, read the head after those fixes, found no blocker, and asked for five small things; each is in §6.5 under "What the third review of 2026-11-27 found", and it changed these:

- R19c now asserts the answer, and R19d and R19e pin that a read outside any run, after a run, is answered from that run's norms and clock (nit 8 of the second review had no test).
- The clock after a run and the nesting of runs are marked on the reference page as decided by Claude 2026-11-27, pending Meng's review.
- A named run that reads and is started inside an outer run is run again by each outer run that uses it; probed, pinned as a limit by R24, stated on the page, not fixed.
