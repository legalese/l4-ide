# Operational lowering: an L4 contract instance as an event ledger with conditional append

Status: proposed, 2026-10-25. On this branch the work packages WPO0 to WPO5 of §9 are built and committed, and the companion's WP0 to WP6 beside them, and none of it has landed.
This tree is the local branch `mengwong/lowering-integ`: the merge of `mengwong/lowering-explore` (`2418f2f75`) and `mengwong/lowering-ledger` (`21e03a4bd`) onto `unstable` (`63254397f`, fetched 2026-10-26), with nothing pushed and no pull request.
The checks quoted below ran on those two branches at the commits named, before the merge; none has been run on this tree yet.
Checked 2026-10-26 on `mengwong/lowering-ledger` at `420bb6258`: `jl4-core-test` 1578 examples, 0 failures (13 pending); `l4-cli-test` 628 examples, 0 failures (83 pending); `jl4-service-test` 717 examples, 0 failures; and the nine fixtures under `jl4/examples/explore/` (`brief/` and `ledger/`) each exit 0 under `l4 run`.
Also run, against the service built at that commit: an HTTP probe of create, append, position, restart and the refusal of a delete.
The code of `5af3d0d9b` differs from `420bb6258` only in two comments, which compile, so the suites were not run again; `doc/test-docs.sh` was run at `5af3d0d9b` and has 0 errors.
On `mengwong/lowering-ledger` the tick-listing change was checked on `fcd265faf` with the change applied, before it was committed (it is the next commit on this branch): `jl4-core-test` 1581 examples, 0 failures (13 pending); `jl4-service-test` 719 examples, 0 failures; `l4-cli-test` 628 examples, 0 failures (83 pending); and `doc/test-docs.sh` 0 errors.
It adds five tests, and four of them (the refusal and lost-race tests in the library, the HTTP test and the MCP test) were each shown to fail when the code they test is made to drop the ticks again; the strict-conflict test was not.
The HTTP probe above was not repeated after the change.
Not run: `jl4-test` (the goldens, about 12 minutes), the suites and harnesses that `etc/verify-branch.sh` does not run (`jl4-lsp-test`, `jl4-mlir-test`, `jl4-websessions-test`, `jl4-proleg-burden`, `jl4-proleg-roundtrip`, the DMN harnesses, the go selftest, WASM, TypeScript), the Nix build and CI on this branch.
On `mengwong/lowering-ledger`, after merging the pushed formatting fix `d8cda38fa` (draft PR #746 passed CI at that commit, Repo-Wide Invariants and TypeScript Checks included, 2026-10-26), `etc/verify-branch.sh --quick` passed at `86b890407`: `cabal build all`, `l4-cli-test` 628 examples, `jl4-core-test` 1581, `jl4-service-test` 719, the service restart probe, the corpus-golden and canon checks, `doc/test-docs.sh --no-l4`, prettier 3.4.2 and the commit trailers.
A pass of that script is not a green CI.
Not run: the Postgres adapter against a server (this machine has no `postgres` binary and no container runtime answering), and §8's item on the checkers' counterexamples proposed to a ledger: the explorer and the ledger are both in this tree now, but no work package claims the item and nothing runs it.
Not built: the Redis, Zookeeper and etcd adapters, which `jl4-service/src/Ledger/Store/Config.hs` refuses by name.
The ledger had a silent failure, reproduced on the running service on 2026-10-26: a `refused`, `conflict` or `unknown` reply could follow tick rows that it did not list.
On this branch each of those replies now lists them under `ticks`; the rows are still written before the act is looked at, and `applied` still means only that the proposed act was appended; §12 describes it.
It becomes true when the work packages of §9 are merged and the acceptance items of §8 are green.
Companion to `REGULATIVE-LOWERING-SPEC.md` (the verification lowering), which it depends on at one point (§4) and shares its fixtures with (§7).
Written one sentence per line.

## 0. Why now

The verification lowering answers "is this protocol safe over every ordering of events".
This document answers the question that follows: once the model checkers say only the atomic check-and-accept design is safe, what runs in production so that the running system _is_ that design, and not a hand translation of it.
The scenario is a classic race condition: Alice and Bob each mean to buy dinner tonight, but not if the other already has, and if each checks whether dinner has been bought, finds it has not and buys, with the checks and purchases interleaved, two dinners are bought.
The formal model checks one side, Alice's, with Bob's purchase as the environment's act; Bob's side is the same model by renaming.
Measurements below were taken on the original private example and the probes' hand models; the dinner fixtures of §7 are specified, not yet built or run.
Names and times in quoted measurements are given in the dinner skin; the map from the original names is in the private record.
Meng's framing on 2026-10-25 was the classic one: this is a check-then-act race, the fix is the atomic design in which the shared dinner ledger checks and accepts in one step, and the architecture is presumably an ACID store behind a middleware tier that fronts MCP.
This spec takes that framing, keeps what is right about it, and corrects it in two places.
First, in L4's own model the atomic design and optimistic concurrency are one operation, a conditional append to the contract's event log, guarded by a semantic re-check rather than a version number.
Second, the locus of synchronization is a store behind one two-function interface, embedded in the service with sqlite at its existing store path as the default and adapters for Postgres, Redis or Zookeeper by configuration, an in-memory store behind a flag for tests, and the service's decision tools stay stateless whichever store is plugged in (Meng, 2026-10-25: both the embedded option and the pluggable external one; the first draft's in-memory default was overturned on the bench, R-O5).

## 1. What exists today, checked

Every claim in this section was checked against the tree on 2026-10-25 at the line cited, except the last, which was checked on the original private worked example.

- **The decision service is stateless by design.** `jl4-service/src/McpServer.hs:84-86`: "This handler is fully stateless across requests: any two interleaved calls observe identical state."
  The only mutable state in the module is the deployment registry and the async task table (`McpServer.hs:27`, `:121`, `:624`), neither of which is per-contract.
- **The service already evaluates a contract against a trace supplied at call time.** A function returning `DEONTIC` is detected by its `startTime` and `events` parameters (`jl4-service/src/DataPlane.hs:246-247`), both are required (`DataPlane.hs:266`, `:268`), and the call is dispatched to the deontic evaluator (`DataPlane.hs:271`, defined at `:718`).
  The MCP tool schema describes `events` as "Events for contract simulation (each: {party, action, at})" (`McpServer.hs:293-299`), and the wire type is `TraceEvent {party, action, at}` (`jl4-service/src/Backend/Api.hs:173-178`).
- **Runtime events reach the evaluator as generated source.** `Backend/Jl4.hs:998-1028` wraps the function in generated L4 with an `EVALTRACE` and runs that; no `Trace` value is built from JSON directly.
- **Ledgers are append-only, per party, and projections.** `specs/done/STATE-AS-LEDGER-SPEC.md` shipped as PR #31 (merged 2026-07-07): `RECORD` appends to the acting party's own ledger, `COMMIT`/`ATTEST` to one official record (R1, ratified), and a read is a snapshot projection over the append-only log, never a store (D2, line 92).
  Its §8 already names the consequence this spec and its companion now take up: once parties write a shared cell, "interleaved `RECORD`s/`COMMIT`s introduce a _data_ race on top of the deontic one", and "the checker must explore interleavings".
- **Ledgers do not persist.** The ledger store is created fresh per directive by `withFreshLedger` (STATE-AS-LEDGER M4, line 211) and discarded when the directive ends (M2, line 207).
  Nothing in the tree keeps a contract instance's state between two service calls.
- **The one-step relation exists and is computed by replay.** `jl4-core/src/L4/Lts/WhatIf.hs`: `position` replays a `#TRACE` to a `Position` carrying the residual, the marking and the contract clock (`:161-178`); `candidatesOf` reads the enabled acts and ticks off that position (`:322`); `whatIf` appends a hypothetical event and re-runs (`:505-509`); `tryCandidate` classifies the result with the five-constructor `Verdict` (`:468-480`): discharging, breaching, advancing, passed over (the replay reduced but every step was a pass-over, `confirmAct` `:580-583`) or untried (`:523-530`); `enabledSet` does all of it for every candidate (`:740-752`).
  A candidate's hypothetical takes the engine's own witness for any binder and the stamp of the last event (`:341`, `:524-527`), so `tryCandidate` does not replay a wire-supplied act as sent; §3.2 replays the act itself instead.
  A `Trace` there is a `#TRACE` directive from a module (`:138-145`), so runtime events have to become source before this code can see them, which is the technique the service already uses.
- **The original private worked example takes the authority's record as an input, not as events.** It declares that record as a `GIVEN` list of status events (in the dinner skin, `` GIVEN `ledger record` IS A LIST OF `Status event` ``), so the environment's act never happens _in_ the trace, and no ledger could serialize it.
  The companion spec's §4.3 re-encodes the ledger and the message channel as parties whose acts are events; this spec depends on that re-encoding (§4).

## 2. The thesis

An L4 contract instance is its trace: an append-only sequence of events, each `PARTY p DOES a AT t`, plus whatever `RECORD` and `COMMIT` wrote along the way, which D2 makes a function of that sequence.
That is an event-sourced aggregate, and the standard concurrency primitive for one is conditional append: "append this event if the log is still as I saw it".

Three disciplines are usually offered for a check-then-act race.
In L4 they are not three implementation choices; they are three different deals, and each is visible as a clause.

| discipline                            | what it is in L4                                                                                                     | who pays                                                  | the dinner case                                                                                             |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| atomic check-and-act (the brief's D3) | the authority replays the rule on the true head and appends or refuses in one step                                   | nobody waits; a refused proposer retries                  | the only design all six checkers passed                                                                     |
| optimistic                            | the proposer names the head it decided against; the authority appends only if the rule still permits the act         | the proposer, in retries and in "pause and check again"   | the same operation as D3 once the guard is semantic (§3.2)                                                  |
| pessimistic                           | a reservation act that defers Bob's purchase for a lease: `MAY buy WITHIN n OF reservation`, `LEST` the lease lapses | Bob, who gives up the freedom to buy while the lease runs | excluded by a premise of the scenario: we assume that checking whether dinner is bought does not reserve it |

The claim is that the first two rows are one row.
A version-number guard ("append only if the head is still `v`") over-refuses: a delivered message, a decision-log entry, any irrelevant append bumps the head and the proposer retries for nothing.
A semantic guard, "replay the rule on the true head and ask whether this act is permitted now", refuses exactly the appends the contract refuses, and that is `tryCandidate` on the current position.
So the authority's accepting step is: read the head, replay, try the proposed act as a candidate, append if the verdict is discharging or advancing, refuse otherwise, all inside one critical section per instance.
The head the proposer decided against is still recorded, as provenance of what the proposer knew, not as the guard.
Which of the two is authoritative is R-O4 (§10); this spec builds the semantic guard.

Two consequences fall out, and both were findings of the probes rather than design choices here.
"Bought" means the moment the authority appends the acceptance, not the moment Alice sends (the probes' summary, legalese/solutions#1): the accepted purchase is the authority's act, as the companion's D3 fixture already draws it.
And the same-second tie the original private worked example had to assume (the other's purchase wins, labelled there "assumed, not ruled") stops mattering between events: two appends in the same second are ordered by sequence number, the evaluator keeps authored order for equal stamps (a stable sort by `AT`, `jl4-core/src/L4/EvaluateLazy/Machine.hs:6959-6962`), and the hand rule governs only a query made after both are recorded.
The mCRL2 probe did not model the tie (same-second steps are ordered nondeterministically) and left it open (its report, legalese/solutions#1); it did not decide it, and the first draft of this sentence said otherwise.
One answer flips: Alice's buy appended before Bob's same-second purchase is **permitted**, where the `GIVEN`-list encoding blocked it; that is a condition of R-O1.
Conventional optimistic locking versions the **resource**, not the whole log; here that is the `COMMIT`ted `dinner status record` cell alone, whose length only another `Status event` changes, so a per-cell version over-refuses only when the status changed in a way the rule did not care about (buy-blocker, 2026-10-25).
The private optimistic-concurrency fixture (legalese/solutions#1, commit 60d926c), buy-blocker's probe and not the WP0 re-encoding (the record is still a `GIVEN`), writes both guards in one buy step: `version at` counts the status events recorded up to a moment, `check whether dinner is bought` `RECORD`s `version read` to Alice's own ledger, and the buy's one `HENCE` validates in the order no answer → pause, dinner not open → do not buy, strict and `version read` below current → pause and read again, otherwise buy; its §§§ R pair is the trace where a second `opened` status event between read and buy pauses under strict and buys otherwise, six traces `FULFILLED`, thirteen assertions.
That is the fixture R-O4 asks for: (a) is authoritative and (b), the per-cell version, only adds "stale but still permitted, read again", which is the opt-in `strict` of §3.2.

## 3. The components

### 3.1 The instance ledger

One ledger per contract instance, owned by one appender.
A row is `(deployment, instance, seq, party, action, at, txTime, verdict, decidedAgainst, idempotencyKey, ruleVersion)`: the key is `(deployment, instance, seq)`, because the routes are per deployment, a deployment `POST` overwrites ungated (jl4-service/README.md:125) and `DELETE` removes one (ControlPlane.hs:355), so an instance keyed without its deployment could replay old rows against a different contract or collide with another deployment's instance of the same name (skeptic O5, 2026-10-25); `ruleVersion` is the deployment version the row was appended under (`smDeploymentVersion`, BundleStore.hs:60), and a deployment with live instances is neither deleted nor overwritten silently; `seq` is the order; `at` is the act's contract time and `txTime` the ledger clock at the append, two columns because L4's own ledger already keeps transaction time apart from asserted valid time (`jl4-core/src/L4/Evaluate/Ledger.hs:65-80`; §3.4 says how `at` is set); `verdict` is what the evaluator said of the act when it was appended; `decidedAgainst` is the head the proposer saw (nullable); `idempotencyKey` is the proposer's retry key (§11).
The row is the persisted form of one `PARTY party DOES action AT at` line of a `#TRACE`, and the instance's rows in `seq` order _are_ its `#TRACE`.
Nothing else persists.
Every ledger that `RECORD` or `COMMIT` writes is recomputed by replaying the rows (D2); the companion spec's §4.1 projects the write-only ones away for state identity for the same reason.

### 3.2 Append-if

The one operation the ledger offers:

```
appendIf : Instance -> Proposed -> IO Result

Proposed = { party, action, decidedAgainst :: Maybe Seq, idempotencyKey :: Text, strict :: Bool }

Result
  = Appended { seq, at, verdict, steps } -- the act is now event number seq; verdict says what the rule made of it
  | Refused  { because, head }           -- a malformed act, an unknown party, or an act on the owner's refuse-list (R-O2)
  | Conflict { head }                    -- strict = True and decidedAgainst /= head; nothing appended
  | Unknown  { because }                 -- the evaluator could not decide (a refused binder, a timeout); nothing appended
```

The instance's step is a compare-and-append loop, not a held lock: the store is never locked while L4 evaluates (§3.7), and "inside the step" below means between one `readRows` and the `appendRow` that depends on it, re-run from the read if the append loses. Instances are created explicitly, and an append or a position read on an instance the store does not hold returns not-found, never a fresh instance, so a wiped or missing store cannot make a refused act look new (skeptic O5). In order: look up `idempotencyKey` first, and on a hit return the original `Appended` with its `seq`, because a retry after a lost acknowledgement must read "done", never "forbidden" (skeptic O4, 2026-10-25); read the rows; set the act's `at` and `txTime` per §3.4, appending any tick that is due first; generate a module whose `#TRACE` is those rows followed by the proposed act **itself** (the `EVALTRACE` technique of `Backend/Jl4.hs:998-1028`, applied to a `#TRACE`) and replay it, classifying as `whatIf` does (`WhatIf.hs:505-509`, `classify` `:729`), because `tryCandidate` replays a candidate's own hypothetical with the engine's witness and the last event's stamp (`:341`, `:524-527`), not the act as sent, and matching a wire act to a candidate's `cdShape` (a pattern with binders as variables, `:247`) has no implementation; on `Discharging`, `Advancing`, `Breaching` or `PassedOver` insert the row with `seq = head + 1` and the verdict on it, because the act happened and the rule's own branch has already decided what, if anything, it `COMMIT`ted; on `Untried` return `Unknown` and append nothing.
Alice's `buy dinner` **is** the proposed act: its step re-reads the official record and `COMMIT`s the dinner in one `HENCE`, which is D3 by construction and how the original private worked example already reads (buy-blocker, 2026-10-25); a blocked buy is appended as a row whose step `COMMIT`ted nothing, so the attempt is auditable, and there is no separate acceptance act of the authority.
The first draft had the authority accept as a separate act and refused a no-match; both are withdrawn.
`Refused` is therefore rare: an act that is not a constructor of the contract's action type, a party the instance does not know, or, when the owner has opted in (R-O2), a `Breaching` act on its refuse-list.
Both `record Bob's purchase` and `buy dinner` go through `appendIf`, so they are serialized by construction, which is D3.
`strict = True` gives a caller the version-number discipline when it wants it (per cell, §2); the default is the semantic guard alone.

### 3.3 Knowledge time: what may I do now

A proposer asks the ledger for the instance's position and enabled set, which is `enabledSet` (`WhatIf.hs:740`) over the rows: the acts that would discharge, the acts that would breach, the acts that advance, and the next deadline (for a bound pattern it still answers with one witness, as the companion's R-L4 covers only the explorer).
That answer is advisory, stamped with the head it was computed at, and it is what "pause and check again" is the rule-level name for when the answer cannot be had.
It is the same step relation as §3.2 run without the critical section, so a proposer and the authority never disagree about what the rule says; they can only disagree about which head is current, and the append settles that.

### 3.4 Time

The contract clock is discrete (T2), and the ledger owns it.
Every row's `txTime` is the ledger's clock at the append, and `txTime` never decreases along `seq`: it is the larger of the clock and the previous row's `txTime`, because the evaluator re-sorts a trace by `AT` (a stable sort, `jl4-core/src/L4/EvaluateLazy/Machine.hs:6959-6962`) and a clock that stepped back would make the replay reorder the rows and disagree with the ledger, with no error (skeptic O1, 2026-10-25).
The act's `at` is bitemporal, after L4's own ledger (`Ledger.hs:65-80`: transaction time stamped from the root clock, asserted valid time beside it).
For an act whose step decides something on the proposer's behalf (Alice's `buy dinner`), `at = txTime`, never the claimed time, which is the Maude finding made structural (the probes' summary, legalese/solutions#1; Maude's timed variant only, silence bound 120 s, 30 s grid).
For an act a party reports having done in the world (a payment made on the deadline day and reported the next), `at` is the claimed time **clamped** to `[previous row's at, txTime]`, so a report can never be placed before what the ledger already holds, and deadlines run from the act, not from the report.
Which acts take `txTime` as `at` is declared per deployment, default: every act whose step `COMMIT`s to the official record; this is R-O1 (§10), and the first draft, record time for every row, is withdrawn.
With `at` clamped and `txTime` monotone, replay order equals `seq` order, so the ledger's verdict and `l4 run`'s agree.
What one unit of `at` is, and where the instance's `AT` start sits against wall time, this spec does not yet say: `startTime` arrives per call today (`DataPlane.hs:266`), and a ledger counting seconds under a contract written in days would shift every deadline silently; that is D-O8.
A `WITHIN` deadline is read off the position's marking (`WhatIf.hs:404`, `deadlineOf`), and when the clock passes it the ledger appends the tick through `appendIf` like any other event, so a tick and an act can never race: either the act's row precedes the tick's or it does not.
A tick row has no party, its `at` is the deadline it passes, and how it is persisted and re-lifted into a `#TRACE` line is D-O3 (§11); `WhatIf` builds a tick's hypothetical today (`:210-228`, `TickPast` at `:231-236`), and the row has to round-trip to the same thing.

### 3.5 The lease, as a term, unrun

For completeness, the pessimistic discipline in L4, written against the companion spec's parties.
This snippet has not been run; it is the shape, not a fixture.

```l4
-- unrun sketch: a reservation that defers Bob's purchase for sixty seconds
`the reservation` MEANS
    PARTY Alice
    MAY   reserve
    WITHIN 0 OF closing
    HENCE COMMIT `lease until` IS ((THE JOIN) PLUS 60)
          HENCE `the evening` ...
    LEST  FULFILLED
```

with the authority's acceptance rule reading `` RECALL ALL OFFICIAL's `lease until` `` and treating Bob's purchase recorded inside a live lease as effective at the lease's end.
Bob's freedom to buy is suspended for sixty seconds, and that is a clause Bob has to agree to.
This scenario assumes he has not: we assume that checking whether dinner is bought does not reserve it.
The point of writing it down is that the discipline is expressible and checkable with the same two lowerings, and that choosing it is a negotiation, not a deployment setting.

### 3.6 One instance, one serialization point

The ledger serializes one instance, and an instance is one contract expression evaluated as one `#TRACE`: under the companion's §4.3 option C that is one chain whose acts name the actor, and under option A (once D-L8 lands) a `RAND` composition; either way it is **one** instance, which is what makes D3 possible, since the step recording Bob's purchase and the step accepting Alice's buy then share one serialization point.
In the dinner case the authority that runs the dinner ledger is its owner and **Alice** proposes to it (§3.2, §6); the first draft named a different proposer here than elsewhere (skeptic O3, 2026-10-25), and no probe or encoding has that party.
Ownership by a party to the deal is a trust assumption, open until D-O2 (authentication) is resolved; STATE-AS-LEDGER's Variation C (line 449) puts the only shared write with a decider rather than a party, and that is the alternative.
Across two instances with two owners there is no single critical section, and this spec offers no cross-instance transaction; two-phase commit is rejected because its prepare phase holds the instance against Bob's purchase, which is the pessimistic lease of §3.5 that a premise of the scenario excludes (we assume that checking whether dinner is bought does not reserve it).
A compensating-act protocol (another premise of the scenario: we assume that cancelling a purchase is a separate action) is the shape a cross-owner deal would take, but no fixture, work package or acceptance item here exercises it, the original private worked example declares no cancel act, and no lowering checks two instances; it is registered as D-O7 and not claimed.
This is R-O3 (§10).

### 3.7 The store, behind one interface

The ledger logic of §3.2 is one module.
The synchronization store behind it is an interface with two operations and nothing else:

```haskell
-- proposed, not in the tree
data LedgerStore = MkLedgerStore
  { readRows  :: Instance -> IO [Row]
    -- ^ the history, in seq order
  , appendRow :: Instance -> Seq -> Row -> IO (Either Seq ())
    -- ^ append as seq iff the current head is seq - 1; Left is the actual head
  }
```

`appendIf` is then `readRows`, evaluate (§3.2), `appendRow` at head plus one; a `Left` means another appender won, and the whole step re-runs from `readRows`.
The evaluator runs between the read and the conditional write, so no store ever holds a lock while L4 is evaluating, and any store that can do a compare-and-append per instance qualifies.

| backend                                                                                                                                                                                                                               | how `appendRow` is conditional                                               | durable                                                                  | nodes                                                                                                             | use                                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| sqlite, a file under the service's store path (`--store-path`, default `/tmp/jl4-store`, Options.hs:77-81; created at every start, BundleStore.hs:71-74; `sqlite-simple` is already a workspace dependency, jl4-websessions.cabal:36) | `PRIMARY KEY (deployment, instance, seq)` insert; a key conflict is `Left`   | yes, across restarts, as deployments already are (README.md:8-9)         | **one process**; the file must not sit on a network filesystem, and the hosted service is not one process (D-O12) | **the default** for a single process; a demo remembers earlier runs                                                                                           |
| in-memory, `TVar (Map (Deployment, Instance) [Row])`                                                                                                                                                                                  | one `atomically` block                                                       | no; every instance is lost on restart while deployments reload from disk | one process                                                                                                       | tests only, behind a flag; every reply from it says the store is non-durable                                                                                  |
| Postgres                                                                                                                                                                                                                              | the same key and the same insert                                             | yes                                                                      | many                                                                                                              | production                                                                                                                                                    |
| Redis                                                                                                                                                                                                                                 | a Lua script: `LLEN key == seq - 1` then `RPUSH`, atomic because scripts are | configurable                                                             | many                                                                                                              | admitted by the interface, required by nothing, built only when a deployment asks (card O3's note, 2026-10-25: "I think we’re requiring SQLite or Postgres.") |
| Zookeeper, etcd                                                                                                                                                                                                                       | `setData` or `Txn` with expected version `seq - 1`                           | yes                                                                      | many                                                                                                              | as Redis                                                                                                                                                      |

A lock-based backend (Redis `SET NX`, a Zookeeper lock) can implement `appendRow` by taking the lock around read, check and write, but the interface does not require locks, and the compare-and-append form is preferred because the evaluator never runs under the store's lock.
The default is sqlite at the store path, and the first draft's in-memory default is withdrawn: a restart would reload every deployment from disk and empty every instance, so a refused act could be accepted and a retried key appended twice, with HTTP 200, and a startup log line reaches the operator, not the proposer (skeptic O5, 2026-10-25). The others are adapters behind the same two functions, chosen by configuration (R-O5). The sketch DDL above uses `JSONB`, which sqlite accepts only as a type name with numeric affinity, so one DDL runs on both engines without meaning the same thing; the adapters carry their own DDL.

The relational schema, unrun:

```sql
-- unrun sketch
CREATE TABLE ledger (
  instance        TEXT    NOT NULL,
  seq             INTEGER NOT NULL,
  party           TEXT    NOT NULL,
  action          JSONB   NOT NULL,
  at              NUMERIC NOT NULL,
  decided_against INTEGER,
  idempotency_key TEXT,
  PRIMARY KEY (instance, seq),
  UNIQUE (instance, idempotency_key)
);
```

The invariant is the key, not the engine: whichever backend is configured, correctness rests on `appendRow` refusing a stale head, and the randomized test of §8 runs against every built adapter.
Leader election per instance is not needed for correctness in any row of the table, because every row's conditional append is itself the serialization; it would enter only to spread appenders across nodes for throughput.
The ledger module lives in `jl4-service` beside the decision tools, reached by its own routes (§9, WPO3), and the MCP decision handler (`mcpHandler`, `McpServer.hs:87`) neither reads nor writes the store.
It calls the evaluator as a library (`L4.Lts.WhatIf` and the evaluator proper), generating the `#TRACE` module the way `Backend/Jl4.hs:998-1028` generates its `EVALTRACE` wrapper.
Where the module lives and which store is the default is R-O5 (§10).

### 3.8 Which writes are `COMMIT`

L4 already has two ledgers per run (STATE-AS-LEDGER R1): `RECORD` appends to the acting party's own, `COMMIT` (or `ATTEST`) to the one official record, read with `RECALL OFFICIAL's` or `RECALL ALL OFFICIAL's` (`recallExpr`, `jl4-core/src/L4/Parser.hs:3032-3050`, documented at `:3001-3023`; the golden corpus covers the form without `ALL` at `jl4/examples/ok/ledger/recall-flat.l4:10`; `jl4/experiments/recall-all-usages.l4:27-36` exercises `RECALL ALL OFFICIAL's`, and run on 2026-10-25 under the installed `l4` (symlink dated 2026-09-28, binary built 2026-10-21, `--version` prints `dev`) it returned the file's expected `LIST 100, 105, 110, 3, 315, 110`, nine evaluations, no error; that file never reads across a `RAND` inside a deontic trace, which is the §4.3 mechanism and has its own preconditions, companion §1 finding 10).
The instance ledger of §3.1 is the substrate of the official record: the facts every party is bound by are the ones the authority's appends `COMMIT`, and the rules that decide an acceptance read them from there.
So the re-encoded scenario writes the `dinner status record` and `dinners bought` with `COMMIT`, and reads them with `RECALL ALL OFFICIAL's`; Alice's decision log stays a `RECORD`, because it is her own account and binds nobody (Meng, 2026-10-25).
The split is also the operational one.
An official write is a fact the ledger has serialized, and a `RECALL OFFICIAL's` in a rule is a read of the true head; a party's `RECORD` is that party's knowledge, which is exactly what the race shows cannot be trusted at the moment of buying.
Writing the rule with the right keyword therefore makes the knowledge-time versus record-time distinction of §5 visible in the source, where a reader of the contract can see which facts the acceptance turns on.
The companion spec's §4.3 snippet is written this way.

## 4. One source, two lowerings

Both lowerings read the same L4 file, re-encoded as the companion's §4.3 says: the ledger's and the message channel's acts are events (option C today: acts of one chain naming the actor; option A once D-L8 lands: parties with `MAY`), and the rules read their `COMMIT`s with `RECALL ALL OFFICIAL's` in event order.
That re-encoding is what the companion's WP0 builds as the dinner brief fixtures (`brief/d1-naive.l4`, `d2-reread.l4`, `d3-atomic.l4`, option C), and this spec cannot start before them: the original private worked example supplies the environment's act as a `GIVEN`, which cannot be appended, and the private optimistic-concurrency fixture (§2) keeps the record a `GIVEN` too, so it is the R-O4 fixture and not WP0.

|                  | verification lowering                                                                     | operational lowering                                                            |
| ---------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| reads            | the explicit LTS: every reachable position, by BFS over `candidatesOf` and `tryCandidate` | one path through it: the instance's rows, extended one `tryCandidate` at a time |
| a state          | a canonical position                                                                      | the head                                                                        |
| an edge          | a candidate tried                                                                         | an `appendIf`                                                                   |
| a counterexample | a `#TRACE` the explorer prints (companion §5.4)                                           | a history the ledger must refuse at some row                                    |
| time             | regions over every event time and deadline (companion §4.5)                               | the ledger's clock, discrete, stamped at append                                 |

The explicit LTS is the set of histories the ledger can ever hold; every row sequence the ledger accepts is a path in it.
So the model checker's safety verdict on the D3 fixture is a statement about this ledger's algorithm, provided the ledger's step is the same function the explorer's step is, which §3.2 arranges by construction and §8 measures.

## 5. The two call sites of one rule

The same rule is evaluated in two places with different standing.

- **Alice**, or an agent calling for her over MCP, with what she knows: knowledge time, advisory.
  The existing MCP decision tools are this call site today, and they do not change.
- **The authority**, inside `appendIf`, with the true head in its compare-and-append step: record time, and the only evaluation that counts.

A proposer that trusts its own evaluation and buys without the authority's append is design D1, and the checkers have already said what happens to it.

## 6. The protocol, end to end, for the dinner case

1. The arrangement's opening is row 1 (`PARTY Ledger DOES `record opening``), appended by the dinner ledger at 18:00: dinner is unbought.
2. Alice asks for the position at 18:05 and sees the open gate enabled; she proposes `check whether dinner is bought`; the ledger appends it as row 2, verdict advancing.
3. At 18:06 Bob buys dinner; the authority (party `Ledger`) proposes `record Bob's purchase`; row 3, status `taken`.
4. At 18:07 Alice proposes `buy dinner`; the ledger replays rows 1 to 3 with it appended, stamped `at = txTime` = 18:07; the step reads the official record, finds Bob's purchase, logs "blocked, nothing bought" and `COMMIT`s no dinner: row 4, verdict advancing, `dinners bought` empty (it holds Alice's purchases; Bob's is the status event of row 3). Sequence A is blocked inside the append.
5. In Sequence B the proposal arrives at 18:05:30, before row 3 exists; Alice's buy is row 3, its step `COMMIT`s the dinner, Bob's later purchase, the environment's act, which this one-sided model does not gate (§0), is row 4; Alice's dinner stands, and the rule's "a later purchase by Bob does not undo Alice's" is the ledger's append-only property.
6. If the evaluator cannot answer within the ledger's time bound, the result is `Unknown`, Alice's rule says "pause and check again", and no row was written.

## 7. Fixtures

The companion's `jl4/examples/explore/brief/d3-atomic.l4` is the ledger's conformance fixture: it is the design the ledger implements, in the dinner skin, with the alphabet the probes agreed on, relabelled.
No third encoding of the scenario is introduced.
The original private worked example, re-encoded, stays in the private probes repository (legalese/solutions#1) as the property-level example (companion R-L5), and §6 above is its protocol in the dinner skin.

## 8. Acceptance, executable later

- Sequence A, driven through `appendIf` with the scenario's times (§6), appends four rows and `COMMIT`s no dinner; the fourth row's step logs the block.
- Sequence B ends with Alice's buy at `seq` 3, one dinner `COMMIT`ted, and Bob's purchase at `seq` 4; the rows replayed under `l4 run` are `FULFILLED` **and** `dinners bought` holds one dinner, because the `FULFILLED` line alone cannot tell B from A (companion §4.3).
- **Bitemporal.** A reported act with a claimed time earlier than the previous row's `at` is stored at that row's `at`; one with a claimed time later than `txTime` is stored at `txTime`; `txTime` never decreases along `seq`.
- **Two oracles.** Every history the ledger accepts, each accepted prefix dumped as its own `#TRACE`, replays under `l4 run` to the verdict the ledger returned when it appended that prefix's last row; a divergence is a bug in the ledger, never in the evaluator.
- **The checkers' counterexamples do not get a dinner through.** Each `#TRACE` the companion's explorer prints as a violation of P1 on `d1-naive.l4` and `d2-reread.l4`, proposed row by row to a ledger running `d3-atomic.l4`, appends every row and `COMMIT`s no dinner by any row after the row recording Bob's purchase.
- **Concurrency.** A randomized test proposes `record Bob's purchase` and `buy dinner` concurrently against one instance for many rounds; no history has a dinner `COMMIT`ted by a row after a row recording Bob's purchase, and every run ends with at most one dinner in `dinners bought`.
- **Idempotency.** The same `Proposed` with the same `idempotencyKey` submitted twice yields one row and two `Appended` results naming the same `seq`, and the lookup happens before the replay (§3.2, §11).
- **Decision tools still stateless.** The decision branches of `handleMethod` (`McpServer.hs:142` `tools/list`, `:147` `tools/call`) and the code they call are unchanged by every work package here; `mcpHandler` itself (`:87-94`) is an eight-line dispatcher, so a condition on it alone would be vacuous (skeptic O5). The ledger's own MCP tool (WPO4) is registered in a wrapper before dispatch, and a test that calls a decision tool with the store absent still answers.
- **Store independence.** The concurrency and idempotency items pass against every built adapter, sqlite first, then Postgres, then the in-memory test store.
- **Restart.** With the sqlite default, a restart reloads deployments and every instance; an append to an instance the store does not hold is not-found, never a new instance.

## 9. Work packages

Each row names its oracle; a package without one is not finished.

| package               | does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | where                                                                         | acceptance                                                                                                                                            | oracle                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| **WPO0 ledger, pure** | the `LedgerStore` interface (§3.7) and its in-memory implementation; `appendIf` and the position query over it; row to `#TRACE` line and back; the proposed act replayed as sent and the five verdicts mapped (§3.2); the idempotency lookup first; `Refused`/`Conflict`/`Unknown` distinguished; depends on the companion's WP0 (the dinner brief fixtures in option C shape) and on card B1 or the payload-time variant (companion §4.3)                                                                                                                                                                         | `jl4-core/src/L4/Ledger/*.hs`                                                 | §8 items 1 to 4 on `brief/d3-atomic.l4`                                                                                                               | `l4 run` on the dumped `#TRACE`       |
| **WPO1 time**         | the ledger clock; ticks appended through `appendIf` from the marking's next deadline; round-trip of a tick row                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | same                                                                          | a deadline that expires with no act yields a tick row, and the replay shows `Expired`                                                                 | `WhatIf`'s `confirmTick` discipline   |
| **WPO2 stores**       | the sqlite adapter at the store path as the default (the key `(deployment, instance, seq)` as the conditional append, retry on conflict, its own DDL), the Postgres adapter by the same key, the in-memory adapter behind a test flag; store selection by configuration; Redis and Zookeeper adapters specified by the table of §3.7 and built only when a deployment asks                                                                                                                                                                                                                                         | `jl4-service/src/Ledger/Store/*.hs`                                           | §8 concurrency, idempotency and restart items pass against sqlite and Postgres, and the concurrency and idempotency items against the in-memory store | the randomized test, once per adapter |
| **WPO3 endpoints**    | `POST /deployments/{id}/instances` (create), `POST /deployments/{id}/instances/{inst}/events` (append-if), `GET /deployments/{id}/instances/{inst}/position` (head, residual, enabled set), new routes beside the decision routes; not-found for an unknown instance; a deployment with live instances refuses silent `DELETE` and ungated `POST` overwrite; `appendIf` runs under `withEvalLimits` (EvalLimits.hs:60) with a retry cap and its own slot pool, since the app-wide limiter (Application.hs:203, 20 slots, plain 503 before the handler) would otherwise turn a long append into an undocumented 503 | `jl4-service/src/Ledger.hs`, `DataPlane.hs` and `ControlPlane.hs` routes only | the dinner protocol of §6 driven over HTTP against the sqlite default with no configuration beyond the store path                                     | §8 items 1 and 2                      |
| **WPO4 agent tool**   | one MCP tool, "what may I do now and what would it do", reading the position query                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | the ledger's own tool registration, separate from the decision tools'         | an agent following the tool's answers reproduces Sequence B and is refused in Sequence A                                                              | §6                                    |
| **WPO5 docs**         | `doc/reference/regulative/ledger.md`, one sentence per line: the two call sites, the loud and silent failures sorted (CLAUDE.md rule 7: `Refused` and `Conflict` are loud; a proposer that ignores `Unknown` and acts is the silent one)                                                                                                                                                                                                                                                                                                                                                                           | `doc/`                                                                        | `doc/test-docs.sh` green                                                                                                                              |                                       |

WPO0 depends on the companion's WP0 (the dinner brief fixtures) and nothing else here depends on the companion's WP1 to WP6, so the two lowerings can proceed in parallel after WP0.

## 10. Rulings (ruled 2026-10-25 on the Lowering Rulings bench)

Meng marked every card on 2026-10-25 between 14:32 and 14:41 UTC on the bench's version 4 (legalese.com account, https://claude.ai/artifact/91v4P8RffWfqxrP7Ba5u96); the marks were copied verbatim the same evening into the regenerated bench, https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye, cited below; the bench page itself narrates the original case and is not to be made public without the same re-skin.
The text above each ruling is the proposal as it stood when marked, re-skinned after the marks under card L5 (companion §9); the marked text is in the private record.

- **R-O1 Record-time stamping, bitemporal.** Every row carries `txTime` (the ledger clock, never decreasing along `seq`); `at` is `txTime` for acts whose step decides on the proposer's behalf (default: every act that `COMMIT`s to the official record), and the claimed time clamped to `[previous at, txTime]` for acts a party reports having done. A same-second pair is decided by arrival order, so Alice's buy appended before Bob's same-second purchase is permitted, where the `GIVEN`-list encoding blocked it. Recommendation: accept; the first draft, record time for every row, judged a payment made on the deadline day and reported the next as late, with no error, and is withdrawn.
  **Ruled 2026-10-25, card O1: accept, option A** (bitemporal, as printed: `txTime` monotone, `at` clamped for reported acts, same-second pairs by arrival); no note. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#O1.
- **R-O2 Breaching acts are appended.** Every act that evaluates (`Discharging`, `Advancing`, `Breaching`, `PassedOver`) is appended with its verdict on the row; the rule's own `LEST` is the record of the breach, as `specs/todo/STATEFUL-CONTRACT-DEPLOYMENT.md` §8.3's hot path also appends unconditionally; ticks (no party) and the authority's own `record …` acts are acts like any other. An owner may opt in to a per-deployment refuse-list of acts it will not append when `Breaching`. Recommendation: accept the default with no refuse-list for the dinner fixture. The first draft recommended a performed-versus-witnessed split by `PARTY`; it misroutes ticks and the authority's `record Bob's purchase`, and the original private worked example reaches no `Breaching` verdict at all (one `LEST FULFILLED`, no `MUST`, `SHANT` or `BREACH`), so nothing in the scenario decides this (skeptic O2, 2026-10-25).
  **Ruled 2026-10-25, card O2: accept, option A** (append every evaluated act with its verdict; the refuse-list is opt-in and none is set for the fixture); no note. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#O2.
- **R-O3 One instance, one serialization point.** An instance is one contract expression evaluated as one `#TRACE`, so a `RAND` composition is one instance; no cross-instance transaction is offered, and two-phase commit is rejected because its prepare phase is the lease a premise of the scenario excludes. Recommendation: accept; the compensating-act protocol for two owners is D-O7 and no part of this ruling, and ownership by a party is a trust assumption open under D-O2.
  **Ruled 2026-10-25, card O3: accept.** Meng's note, verbatim: "I think we’re requiring SQLite or Postgres." Read with O5: the serialization point is a real store, sqlite for one process and Postgres for many; the in-memory store is for tests only, and the Redis and Zookeeper rows of §3.7 are admitted by the interface but required by nothing and built only when a deployment asks (WPO2 already says so). Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#O3.
- **R-O4 The semantic guard is authoritative.** The proposed act itself is replayed on the true head with the ledger's stamp; `decidedAgainst` is provenance; `strict` (a per-cell version, §2) is opt-in; the idempotency key is checked before the guard. Recommendation: accept; the first draft's mechanism (`tryCandidate` on a matched `cdShape`) replayed the engine's witness rather than the act, and matching a wire act to a pattern has no implementation (`WhatIf.hs:247`), so the mechanism is replaced and the principle kept (skeptic O4, 2026-10-25).
  **Ruled 2026-10-25, card O4: accept** (the act itself replayed on the true head; idempotency checked first; `strict` opt-in); no note. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#O4.
- **R-O5 Where the ledger lives, and the default store.** A ledger module embedded in the service (core in `jl4-core`, routes in `jl4-service`) behind its own routes, with the store as the two-function interface of §3.7: **sqlite at the service's existing store path by default**, in-memory behind a flag for tests, Postgres, Redis or Zookeeper by configuration. Recommendation: accept; this is the bench's option C. The first draft recommended an in-memory default "so a demo needs no configuration"; its skeptic overturned that on 2026-10-25: the service already creates and writes its store directory at every start (BundleStore.hs:71-74), sqlite is already a workspace dependency, and an in-memory store loses every instance across a restart while deployments reload, so a refused act could be accepted and a retried key appended twice with HTTP 200. Conditions: the row key carries the deployment id and the deployment version; instances are created explicitly and an unknown instance is not-found; a deployment with live instances refuses silent delete or overwrite; the decision branches of `handleMethod` and the code they call are unchanged, and the ledger's MCP tool is added in a wrapper before dispatch; `appendIf` runs under the evaluation limits with its own slot pool and a retry cap; sqlite and the in-memory store are declared single-process, and a hosted deployment, where the auth proxy reaps an org's process after four idle hours and runs several processes or hosts with no sticky sessions (jl4-auth-proxy ARCHITECTURE.md:420-428, runbooks/scaling.md:44-46), configures Postgres, because an in-memory or sqlite ledger behind several processes forks silently; the proxy gains a route type and permission for the ledger paths before hosted use, since today `/deployments/{id}/instances/…` would be classed as a deployments route and a `POST` would demand `l4:deploy` (jl4-auth-proxy src/auth/middleware.ts:59-61); and this spec's rows table supersedes the Postgres `events` table that `STATEFUL-CONTRACT-DEPLOYMENT.md` §8.2 proposed (status OPEN), which stays the reference for the hosted Postgres topology (§8.1) and nothing else. Meng's 2026-10-25 ask, both an embedded option and a pluggable external one, is satisfied by C as by A. The alternative, a separate process, is the same module behind its own HTTP and stays available.
  **Ruled 2026-10-25, card O5: accept, option C**, with every condition listed above (row key with deployment id and version; explicit instance creation; refusal of silent delete or overwrite with live instances; `handleMethod` unchanged and the tool added in a wrapper; `appendIf` under the evaluation limits with its own slot pool and retry cap; sqlite and in-memory declared single-process; hosted deployments configure Postgres; the proxy gains a route type and permission before hosted use; this spec's rows table supersedes STATEFUL-CONTRACT-DEPLOYMENT §8.2's events table); no note. Bench: https://claude.ai/artifact/CwGXLC6dCAzUfFGZQ2VDye#O5.

## 11. Register of deferred obligations

- **D-O1 Idempotency keys.** P2, "at most one dinner in `dinners bought`", holds by construction in the model and fails in operation on a retried proposal after a lost acknowledgement; the key is in the schema (§3.7) and the acceptance item (§8), and the policy for a reused key with a different payload is open.
- **D-O2 Who may append as which `PARTY`.** Authentication and authorization of proposers are out of scope here and are not assumed solved; until they are, every `Proposed` is trusted as to its `party`, and the spec says so rather than letting it pass silently.
- **D-O3 Tick persistence.** The row form of a tick, and its round-trip to the hypothetical `WhatIf` builds, are undecided (§3.4).
- **D-O4 Replay cost.** `appendIf` replays the whole history per append, O(history); fine for instances of hundreds of events, and snapshotting of positions is parked until a measurement says otherwise.
- **D-O5 The lease.** §3.5's sketch is unrun; if a deployment ever wants the pessimistic deal, it becomes a `brief/` fixture with its own properties first.
- **D-O6 The `GIVEN` route.** An instance whose contract still takes the environment as a `GIVEN` cannot be ledgered; whether to refuse such a contract loudly at instance creation, or to require the §4.3 shape by a check, is open.
- **D-O7 Two owners.** A compensating-act protocol across two instances with two owners (§3.6) has no fixture, no work package and no acceptance item; it waits for a two-owner fixture, and the original private worked example declares no cancel act to build one from.
- **D-O8 Unit and epoch.** What one unit of `at` is, and where an instance's `AT` start sits against wall time, are unstated (§3.4); the first deployment whose contract is written in days decides it.
- **D-O10 Limits and caps.** Instance and row caps per deployment (precedent: the upload caps at ControlPlane.hs:186), the retry cap on the compare-and-append loop, and the ledger's own slot pool under `withEvalLimits` are sized by the first deployment; a 503 from the app-wide limiter is documented as "not applied", never as refused.
- **D-O11 Who may call the ledger routes.** The service's routes carry no authentication today (Application.hs:181 serves the default), so the ledger's routes would be live on upgrade for anyone who can reach the service; behind the hosted auth proxy, `/deployments/{id}/instances/…` is classed as a deployments route and `POST` requires `l4:deploy` (jl4-auth-proxy src/routing/parse.ts, src/auth/middleware.ts:59-61), so the proxy needs a route type and a permission for the ledger paths; D-O2's party authentication and this route authorization are one problem, and the first deployment outside a demo decides it.
- **D-O12 Production topology.** The hosted service is not one long-lived process: the auth proxy reaps an org's process after four idle hours (SIGTERM, then SIGKILL; jl4-auth-proxy ARCHITECTURE.md:420-428) and can run several processes or hosts per org with no sticky sessions (runbooks/scaling.md:44-46), so in-memory and sqlite ledgers are single-process only and hosted use configures Postgres; the number of replicas per store is otherwise not in the tree (flake.nix:43-45 sizes one image; BundleStore.hs:77 handles NFS leftovers).
- **D-O9 Rule version.** A row is not pinned to the rule version that evaluated it, so a redeploy changes the rule under a live instance silently; `STATEFUL-CONTRACT-DEPLOYMENT.md` §4 pins a `version_hash` per instance and is the design to adopt or reject; that unratified spec's §8.3 hot path (lock, evaluate, append, CAS the snapshot) is also the nearest prior design to this one and was not cited by the first draft.
- **D-O13 Append over MCP.** Unspecified.
  The WPO4 row said "no append over MCP" until 2026-10-26, when Meng removed it (verbatim: _let's unspec the "no append over mcp" line_).
  This spec now neither requires nor forbids an MCP tool that appends; whether an agent may append over MCP, and how such a tool would bind its party, its idempotency key and the open items D-O1, D-O2 and D-O11, is open.

## 12. What this spec does not claim

- On this branch WPO0 to WPO5 are built, with the companion's WP0 to WP6 beside them, and no line of the rest of it describes the tree in the present tense except §1.
- A `Refused`, `Conflict` or `Unknown` reply can follow tick rows that the same call appended, and on this branch it lists them under `ticks`.
  `appendIf` appends every due tick (`dueTicks` in `jl4-core/src/L4/Ledger/Append.hs`) before it looks at the act, so when a deadline has passed and the proposal is then refused, the instance's head has moved.
  The reply says `applied` false, which means only that the proposed act was not appended, and lists the tick rows; a `refused` or `conflict` reply's `head` is the head past them.
  A caller that reads only `applied` or `result` still does not learn that the head moved; `doc/reference/regulative/ledger.md` lists it under Silent, with the measurement of 2026-10-26 and what the same proposal now returns.
  Tested: a refusal over HTTP and in the library, the MCP preview of a refused act, a strict `conflict` that the tick itself causes (whole head versioned), and a call that lost a race to append and ran again.
  Not tested: an `unknown` that follows a tick, though the code lists the ticks there too.
  Not changed: the rows are still written when the act is refused (option B, writing none, would change what a refused proposal writes and which head a strict proposal decides against), and a strict whole-head proposal is a `conflict` whenever a tick came first.
- It does not claim the ledger scales past one appender per instance, or that replay-per-append is fast; D-O4 holds the measurement.
- It does not claim the MCP decision tools become transactional; the ledger routes beside them do, and only they touch the store (R-O5).
- It does not claim the in-memory store is fit for anything but tests: it loses every instance on restart while deployments reload, and the table of §3.7 says so; it is no longer the default.
- The §4.3 re-encoding this spec depends on, the companion's dinner brief fixtures, is committed in `jl4/examples/explore/brief/` of this branch as the companion's WP0: option C is written there, and option A does not run on today's evaluator (companion §1 finding 10).
- Nine of this spec's claims were corrected on 2026-10-25 by the skeptics of the Lowering Rulings bench; each correction is marked where it lands (§1, §2, §3.1, §3.2, §3.4, §3.6, §3.8, §10, §11), and the first drafts are in the session record, not in this branch.
- It does not claim the scenario's two sequences are enough: §8's two-oracle and concurrency items are the test, and the companion's explorer is where the other orderings come from.
- The probes are cited by pull request and commit, not by path: they are in the private probes repository, draft PR legalese/solutions#1 (head `60d926c` when checked with `gh pr view` on 2026-10-25), and resolve for the team only.
