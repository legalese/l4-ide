# The instance ledger

A contract is more than its rules: once it is running it has a history, who did what and when.
The **instance ledger** is the part of the L4 decision service that keeps that history for one running contract.
It works out what the contract's rules make of each new act, with the history exactly as it stands at that instant, and it records the act together with the answer.
You want it when two parties can act at the same time and the order in which their acts are recorded decides who is in the right.

**Status (2026-10-26):** built, in the decision service (`jl4-service`).
Each behaviour below was read off the code, and each sentence that says "measured" was run against the service built from the code this page describes.
The Postgres store is the exception: it compiles, and it has never been run against a database server (see [Where the rows are kept](#where-the-rows-are-kept)).

## Why it exists: the dinner race

Alice and Bob each mean to buy dinner tonight, and neither wants to if the other already has.
Each checks whether dinner has been bought, finds that it has not, and buys.
If their checks and purchases interleave, two dinners are bought.
Neither rule is wrong.
The fault is that the check and the purchase are two steps, and the world moves between them.

The cure is to make them one step, taken by whoever holds the record.
Alice does not buy on what she last read.
She asks the ledger to buy, and the ledger looks at its own record at that instant and, in the same step, either records her purchase or does not.
That is the design in [`d3-atomic.l4`](../../../jl4/examples/explore/brief/d3-atomic.l4).
Its two neighbours in that folder, `d1-naive.l4` and `d2-reread.l4`, are the versions in which the race can happen, kept wrong on purpose.
The rest of this page uses the dinner contract as its example.

## Words used here

An **"instance"** is one running copy of a contract: this evening's dinner, with its own history.
An **"act"** is one thing a party does, such as `Alice buys dinner`.
A **"row"** is one entry in an instance's history, numbered from 1.
The rows in order are the instance's `#TRACE` (see [Testing with #TRACE](README.md#testing-with-trace)).
The **"head"** is the number of the last row, and says where the history stands.
A **"proposer"** is whoever asks for an act to be recorded: a person, a program, or an AI agent calling for Alice.
A running contract also keeps notes.
A party's own notes are written with `RECORD`, and the one shared **"official record"**, which every party is bound by, is written with `COMMIT`.
The dinner contract commits the status of the dinner (`opened`, then `taken`) and the dinners bought, and keeps Alice's belief and plan as her own notes.
A **"retry key"** is a label the proposer puts on a proposal so that sending it twice has the effect of sending it once; programmers call it an idempotency key, and the request field is `idempotencyKey`.

## The two call sites

The same rule is evaluated in two places, and the two do not carry the same weight.

**Asking.**
A proposer asks where the instance stands and what may be done now.
There are two ways to ask.
One is a web request (HTTP, the Hypertext Transfer Protocol) to `GET /deployments/{id}/instances/{instance}/position`.
The other is the ledger's tool for AI agents, `what-may-I-do-now`, offered over the Model Context Protocol (MCP) beside the service's decision tools.
Given a party and an act, the tool also says what the ledger would do with that act were it proposed now.
Either answer is **advisory**.
It names the head it was computed at, and by the time the proposer acts it may be out of date.
It appends nothing (measured: the head was the same before and after the tool previewed an act).

**Proposing.**
`POST /deployments/{id}/instances/{instance}/events` hands the ledger an act.
The ledger reads the instance's rows, replays the contract with the proposed act as its newest event, and appends the act as the next row only if the head is still the one it read.
If another proposal landed first, it starts again from the read, on the new history.
It retries a lost race up to 8 times, and then answers `unknown` and appends nothing.
This is the only evaluation that counts.
The ledger holds no lock while L4 evaluates; what makes the step safe is that the store refuses an append made against a stale head (see [Where the rows are kept](#where-the-rows-are-kept)).
So the step that records Bob's purchase and the step that handles Alice's buy can never both be decided against the same stale head.

A proposer that trusts an answer from the first call site and acts without going through the second is the race again.

The service's decision routes and decision tools are neither call site.
They evaluate what the caller sends in the request, keep nothing between calls, and neither read nor write the ledger.
A test calls a decision tool with no ledger, and with a ledger whose store cannot be opened, and it answers both times.

## The routes

`{id}` is the deployment's id.
The routes exist in the long form only, because a short `/{id}/instances` would read as a function name.

| Method | Path                                          | What it does                                                                                                                                      |
| ------ | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST` | `/deployments/{id}/instances`                 | Creates an instance. The body names the `instance` and the `contract`, the contract expression to run, as L4 source.                              |
| `POST` | `/deployments/{id}/instances/{name}/events`   | Proposes an act. The body has `party`, `action` and `idempotencyKey`, and optionally `decidedAgainst`, `strict`, `cells` and `claimedAt`.         |
| `GET`  | `/deployments/{id}/instances/{name}/position` | Says the head, whether the contract is finished, the next deadline, and what is owed, would discharge, or would breach, in the words of `l4 lts`. |

The tool `what-may-I-do-now` takes the `instance`, the `deployment` (left out on a deployment's own endpoint), and optionally a `party` and an `action` to try.
Given an act, the answer's `ifProposedNow` carries the `commits` the act would make, with `applied` `false`.
A request that carries `X-Include-Functions: false` or `X-Include-Evaluate: false` is not shown the tool (measured: it is absent from `tools/list` with the second header).
An instance name is letters, digits, hyphens and underscores, at most 128 of them.

The contract a deployment runs is its one `.l4` file that no other `.l4` file of the bundle imports; the others are its imports.
A bundle with two such files is refused with `422`, naming them.

An instance is created with the first of these, and only that way.
An append or a read on an instance the ledger does not hold is `404`, never a fresh instance.

```text
POST /deployments/dinner/instances
{"instance": "evening", "contract": "`the arrangement`"}

POST /deployments/dinner/instances/evening/events
{"party": "World", "action": "`Alice buys dinner` TRUE", "idempotencyKey": "evening-4"}
```

## Write tools over MCP

An agent can append over MCP, on a service started with `--ledger-mcp-write` (environment `JL4_LEDGER_MCP_WRITE`).
The flag is off by default, and it stays off until who the caller is (D-O2 of the operational spec) and who may call the ledger at all (D-O11) are decided.
With it off, no write tool is listed and a call to one is an unknown tool; a test lists and calls with the flag off, and finds nothing listed and nothing appended.

With it on, a deployment's own endpoint, `/deployments/{id}/.mcp`, lists one tool for each act the caller's party may perform.
The org-wide endpoint lists none.
The tool is called `act-` and the act's name with every character that is not a letter, digit, underscore or hyphen turned into a hyphen, so the act `Alice buys dinner` is `act-Alice-buys-dinner`.
It takes the `instance`, an `idempotencyKey` that is required and has no default, optionally `decidedAgainst`, and one argument for each field of the act, named the same way (the field `ledger answered` is the argument `ledger-answered`).
Only BOOLEAN, NUMBER and STRING fields are taken.
Each call is the same function as the events route, `appendIf`, on the true head, and its reply is the events route's reply: `appended`, `refused`, `conflict` or `unknown`, with the row, the head and the ticks, and for `appended` the `commits`.
The tool's description says what `appended` means, and a reader of the tool result should read `commits` before it concludes that the act took effect.
The tool result carries `isError` unless the act was appended.
Giving `decidedAgainst` makes the call strict against the whole head, so it is a `conflict` if anything has been appended since.

The party is not an argument.
It is the `X-L4-Party` request header, which a proxy or the client's own configuration sets beside `X-Include-Functions`.
It is a claim and not an authentication, like the `party` of the events route.
With no header there is no write tool, and a call to one is refused.

Which acts a party may perform is read from the deployment's source, once for each version of the source.
A clause that names its party and names an act, such as `PARTY Alice MUST` followed by the act `Alice quotes`, offers that act to Alice.
A clause that names its party and takes any act of the contract (`PARTY World MAY act`) offers every act of the contract's action type to that party.
A clause whose party is a variable (`EVERY`) offers nothing, because binding a party by a variable is the party binder, which is not built.
On the dinner fixtures every clause is `PARTY World MAY act`, so a caller who is `World` is offered all five acts and a caller who is `Alice` is offered none; the scoping separates parties only on a contract whose clauses name their actors, which `jl4/examples/explore/ledger/two-party.l4` does for the tests.

What the tests show, in `jl4-service-test` (`LedgerMcpSpec`), run in the ledger worktree before this branch was merged with the explorer:
Sequence B over MCP is the buy as row 3 committing the dinner, Bob's purchase as row 4, and a retry under the same key reading back row 3 with `replayed` false.
In Sequence A a strict buy decided against head 2 is a `conflict` with the head left at 3, and the same buy without `decidedAgainst` is row 4 and commits no dinner, as over HTTP.
A caller that is not the act's party, and a caller that names no party, are refused and nothing is appended.
A call with no key, a field of the wrong type, or an argument the tool does not take (a `party`, for one) is refused and nothing is appended.
An act with a NUMBER and a STRING field is appended as the source `(`Alice quotes` 12.5 "hello")`, a negative number is written in parentheses, and a string holding a quote is refused.

## A walk through the dinner

The service's tests drive the dinner contract with the ledger's clock set to the fixture's own times, where 18:00 is 64800.
The real clock is another matter, and [The clock](#the-clock) says why.
The party is `World`, as the fixture spells it, and every act goes in under a retry key of its own.

**Sequence A: Bob's purchase is recorded first.**

| Row | Time  | Act                                     | What to notice                                                                                                                  |
| --- | ----- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 1   | 18:00 | (the instance is created)               | The opening writes `COMMIT` of `dinner status record` as `opened`: dinner is unbought.                                          |
| 2   | 18:05 | `Alice checks whether dinner is bought` | Alice's check.                                                                                                                  |
| 3   | 18:06 | `ledger records Bob's purchase`         | The status record becomes `taken`.                                                                                              |
| 4   | 18:07 | `` `Alice buys dinner` TRUE ``          | The reply is `appended`, verdict `advancing`, and the step wrote only that Alice's belief is `taken` and her plan is `stopped`. |

Row 4 is appended, and no dinner is bought.
Alice's buy reached the ledger after Bob's purchase was recorded, and the rule's own step, reading the official record at that instant, found it and bought nothing.

**Sequence B: Alice's buy comes first.**

| Row | Time     | Act                             | What to notice                                                 |
| --- | -------- | ------------------------------- | -------------------------------------------------------------- |
| 3   | 18:05:30 | `` `Alice buys dinner` TRUE ``  | The step commits `dinners bought` as `dinner for two`.         |
| 4   | 18:06    | `ledger records Bob's purchase` | The status becomes `taken`, and no second dinner is committed. |

Rows 1 and 2 are as in A.
One dinner stands, and Alice's purchase is not undone by Bob's later one, because rows are only ever added.
When `Alice is done` is proposed at 75700, after the contract's `closing` of 75600, the ledger first appends a tick row, which records that a deadline passed with nobody acting (row 5, at 75601), and then the act (row 6), and the instance is fulfilled with one dinner.

Row 4 of sequence A comes back as HTTP `200`, `result` `appended`, verdict `advancing`.
Nothing in the status or the verdict says that no dinner was bought.
The `wrote` list does: it holds no `COMMIT` of `dinners bought`.
The position's `ledger` list, which has every entry at the head, tells the same story at any later time.

## Reading a reply

Every reply from these routes is JavaScript Object Notation (JSON), and every one says `applied`: `true` if it appended the proposed act, `false` if it did not.
A `false` can still follow tick rows that the same call appended; they are listed under `ticks`, and "Due ticks survive a refusal" under [Silent](#silent) says what to read.
Every reply also says which store answered (`store`), and the in-memory store adds a `warning`.

| HTTP status              | `result`                   | `applied` | What it means                                                                                                                  |
| ------------------------ | -------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `200` (`201` for create) | `appended`                 | `true`    | The act is now row `seq`. The row's `verdict` says what the rule made of it, and `commits` what it did to the official record. |
| `422`                    | `refused`                  | `false`   | The proposal cannot be an event of this contract, or is malformed. `because` says how.                                         |
| `422`                    | `not applied`              | `false`   | The deployment failed to compile, or has no single contract file to run.                                                       |
| `409`                    | `conflict`                 | `false`   | A `strict` proposal whose versioned cell moved since the head it decided against.                                              |
| `409`                    | `refused`                  | `false`   | Create only: the instance already exists.                                                                                      |
| `404`                    | `not found`                | `false`   | No such instance. A deployment that does not exist is also `404`, with the result `not applied`.                               |
| `503`                    | `unknown` or `not applied` | `false`   | The ledger could not decide, or a limit or a failure stopped the request. Nothing was applied, and `Retry-After: 1` is set.    |
| `400`                    | (an `error` text)          |           | The instance name is not one.                                                                                                  |

A row holds the act (`event`), the two times (`at` and `txTime`, see [The clock](#the-clock)), the `verdict`, the head the proposer says it decided against (`decidedAgainst`), the retry key, and the `ruleVersion`, which is the deployment version the row was appended under.
The `verdict` is one of four: `discharging` (the contract ended fulfilled), `breaching` (it ended in breach, naming the party), `advancing` (it moved to another position) and `passed over` (no obligation in force took the act, and `because` says why).
Every act that evaluates is appended with its verdict, a breach included, because the record of a breach is part of the history.
No per-deployment list of acts to refuse is built.

The reply to an append also has `wrote`, the entries the act's own step added to the contract's ledgers, in the words `l4 run` uses; `ticks`, the tick rows this call appended before the act, oldest first; and `steps`, how many rule steps the act caused.
A `refused`, `conflict` or `unknown` reply has `ticks` too, because the ticks are appended before the act is looked at: the list is empty when no deadline was due.
A reply that comes from a limit or a failure rather than from the ledger (`not applied`, `not found`) has none.

The reply to an append also has `commits`, the part of `wrote` that went to the official record, as a list of `cell` and `value`.
`appended` says the attempt was recorded as a row, and nothing more.
A late buy that the contract's own step blocks is `appended` too, with `applied` `true` and status `200`, and its `commits` is the empty list.
An agent that wants to know whether its act did what it meant reads `commits`, and not the status.
`commits` says what the step wrote to the official record, and cannot say whether that was what the agent was after, because a contract may commit a refusal as readily as an acceptance; the agent looks for the cell it wanted.
It covers the act's own step only: the tick rows under `ticks` are rows, and do not list what they wrote.
The reply that creates an instance has it too, and lists what the opening committed.
Measured over HTTP, over MCP and in the library on the dinner: Sequence A's late buy is row 4, `appended`, `commits` empty; Sequence B's buy lists the cells `dinners bought` and `open at acceptance`; the opening lists `dinner status record`.
In the library test alone, Bob's purchase lists `dinner status record` as well.

### Refused

An append is refused, and the act is not written, when the act or the party is not one the contract has, when either text cannot stand as one line of a `#TRACE`, or when the proposal has no retry key.
Creating an instance is refused in the same way when the contract expression is not one the deployment can run.
Texts with a line break, a tab, `--`, `{-`, `-}`, a `^`, an unbalanced parenthesis or an unterminated name are in the second group, because each would make the generated line say something else than what was sent.
A `strict` proposal is also refused if it names no head to decide against, or names one the instance never had.
Measured: proposing `` `Alice sings` `` to the dinner is `422`, and the reply is the type checker's own message about the identifier.

### Retries

The ledger looks the retry key up before it replays anything.
On a hit it returns the original row, with `replayed` set to `false` and the same `seq`, so a retry after a lost reply reads "done", never "forbidden" (measured, and measured again after a restart).
A retry is always safe to send.
If the first try wrote the row, the retry reads it back; if it did not, the retry appends it.
The reply to a retry that finds its key has no `commits` at all: its step is not replayed, so what it committed is not known, and an empty list would say that nothing was committed.
To learn what the first try committed, keep the first reply, or read the position.

### Strict proposals

By default the rule is the only guard: an act is appended if it evaluates, and `decidedAgainst` is kept as a record of what the proposer had seen.
A proposer can also ask for a version check on top.
Send `strict: true`, the head in `decidedAgainst`, and in `cells` the official-record cells whose version matters, such as `dinner status record`.
If any of those cells has been written to since that head, the answer is `conflict` and the act is not appended.
With no `cells`, any new row at all is a conflict (measured: a strict proposal against head 1 on an instance at head 3 is `409`, "the head moved from 1 to 3").
A cell's version is the number of entries recorded in it, not the number of different values, so a status that was recorded and then reversed has still moved.

## The clock

Each row carries two times.
`txTime` is the ledger's clock when the row was appended, and it never decreases along the rows.
`at` is when the act counts as having happened, and the contract's deadlines run from it.

For an act whose step writes to the official record with `COMMIT`, such as Alice's buy when it is accepted, `at` is `txTime`, whatever the proposer claims.
For an act a party reports having done in the world, the proposer may send `claimedAt`, and the ledger keeps it, clamped to no earlier than the previous row's `at` and no later than `txTime`.
A report therefore cannot be placed before what the ledger already holds.

A deadline that passes with nobody acting writes nothing by itself: nothing in the ledger watches the clock in the background.
The ledger appends the tick row that records the expiry at the start of the next proposal, ahead of the act, and lists it under `ticks` in the reply.
Until then the position shows the instance as it stood at its head, and says `deadlinePassed` once the clock is past `nextDeadline`.

The service's clock is whole seconds since the Unix epoch, 1 January 1970 UTC.
What one unit of a contract's time means, and where its start sits against wall time, is not decided.
A contract written for another unit or starting point runs with every deadline shifted, and nothing says so.
The dinner contract counts seconds from midnight, and closes at 75600.
Measured, on the real clock: creating a dinner instance stamped its opening at 1792969219, Alice's first check came back `appended` with verdict `discharging`, because 75600 was long past, and the position then read `fulfilled`.
That is why the tests set the clock themselves; the service has no setting for it.

## Where the rows are kept

The rows live in a store, which is a small interface of two operations: read an instance's rows in order, and append a row as number `n` only if the instance's head is `n - 1`.
Any store that can make that one conditional append qualifies.
If the append is refused because the head moved, the ledger's step starts again from the read.
Two proposals that saw the same head therefore cannot both become the next row, and no row is ever skipped.
In the two database stores that rule is one statement and the key `(deployment, instance, seq)`, so the database enforces it.

| `--ledger-store`   | What it is                                                                                | Use it                     |
| ------------------ | ----------------------------------------------------------------------------------------- | -------------------------- |
| `sqlite` (default) | A SQLite database, which lives in one file: `ledger.sqlite3` in the service's store path. | For one process.           |
| `postgres`         | A Postgres database server, reached by `--ledger-postgres-url`.                           | For more than one process. |
| `memory`           | The service's own memory.                                                                 | In tests only.             |

The same choices can be made with the environment variables `JL4_LEDGER_STORE`, `JL4_LEDGER_POSTGRES_URL` and `JL4_LEDGER_ALLOW_NONDURABLE`.

**SQLite, the default.**
It needs no configuration beyond the store path, `--store-path`, where the deployments already live.
The file is created by the first request that needs the ledger, not at start (measured: a service that has served only deployments has no `ledger.sqlite3`).
It lasts across restarts, as the deployments do (measured: after a restart the same instance was still at head 3).
It is for **one process**.
The lock that keeps an instance from being created while its deployment is being deleted is held in the process's memory, so a second process sharing the file would not take part in it.
The file must not sit on a network filesystem, where SQLite's own locking cannot be trusted.
The store tests race eight threads of one process against one file; no test runs two processes.
The default store path is `/tmp/jl4-store`, and many systems clear `/tmp` when they restart, so set `--store-path` to a directory that lasts.

**Postgres, for more than one process.**
A hosted deployment may run more than one process serving the same instances, and then every process must share one store: configure Postgres.
How many processes a particular host runs is not something this page can say.
Postgres is compiled in only when the service is built with the cabal flag `postgres` (`cabal build -f postgres jl4-service`), which needs the `libpq` library.
Without the flag, `--ledger-store postgres` stops the service at start, saying how to get the adapter (measured).
With the flag but no connection string it stops the service too.
The adapter runs the same statements as the SQLite store.
It has been run only against SQLite standing in for a server, and against a port with no server, where opening the store fails cleanly.
It has not been run against a Postgres server.
It holds one connection, with no pool and no reconnection, so a lost connection fails every call after it, loudly.

**Memory, for tests.**
`--ledger-store memory` is refused at start unless `--ledger-allow-nondurable` is given too (measured: the service exits with status 1).
Every instance is lost when the process ends, while the deployments reload from disk.
Every reply from it carries a `warning` saying so, and the log says so at start.
It is one process's memory, so two processes would each have their own ledger.

Redis, ZooKeeper and etcd could be built behind the same two operations, and none is built: naming one in `--ledger-store` is refused.

## What goes wrong, loud and silent

A failure is **loud** when the caller is told and nothing wrong is left behind.
It is **silent** when the reply looks like success, or when it is the caller's own reading of a reply that goes wrong.
The silent ones are the ones to build around.

### Loud

- **`refused` (`422`) and `conflict` (`409`).** The act is not appended, and the reply says why.
- **`not found` (`404`).** No instance is made up in its place.
- **`unknown` and `not applied` (`503`).** The act was not applied and the reply says so.
  The ledger gave no answer because the evaluator could not decide, because the request ran past `--eval-timeout` (60 seconds by default) or the ledger's memory limit, because every one of the ledger's evaluation slots was in use, or because the store failed or could not be opened.
- **A misconfigured store at start.** `memory` without `--ledger-allow-nondurable`, `postgres` on a binary built without the flag or with no connection string, and a name the service does not know, each stop the service before it listens (measured for the first two: exit status 1).
- **A tool error.** The MCP tool answers with `isError` for a deployment or instance that is not there, or a store that cannot be opened.
- **A refused write tool.** A write tool answers with `isError` and `applied` false when the connection names no party, when the act is not offered to its party, when an argument is missing, of the wrong type or not the tool's, or when the instance is not there; and the ledger's own `refused`, `conflict` and `unknown` come back as `isError` too.
- **A guarded deployment.** `DELETE` on a deployment that has held an instance, and an overwriting `POST` to it, are `409`, naming the instances (measured), and `503` when the store cannot say whether it holds any.

### Silent

- **An `appended` that is not a yes.** The ledger records every act that evaluates, so a blocked purchase, an act no obligation took (`passed over`), and a breach are all `200`.
  Read the verdict and the `wrote` list, not the status; `commits` is the part of `wrote` that went to the official record, empty for a blocked purchase.
  The MCP tool says `would be appended` in the same way.
  A write tool is the same: an act no live obligation takes is appended as `passed over`, with `isError` false.
  Measured: asked about `` `Alice buys dinner` TRUE `` on a finished instance, it said `would be appended`, with verdict `passed over` and nothing written.
- **A missing `commits` read as an empty one.** A retry that finds its key has no `commits`, and a reader that takes a missing list for an empty one reads a purchase that committed as a purchase that was blocked.
  Absent means not known; `[]` means the step ran and committed nothing.
  Tested over HTTP, over MCP and in the library: the retry of Sequence B's buy has no `commits`, and its first try has two.
- **A proposer that ignores `unknown` and acts anyway.** The ledger answered `503` and appended nothing, and a proposer that reads that as permission and buys outside the ledger has built the race again.
  The right reading is the one the dinner rule already has: pause, and check again.
  Resending the same proposal under the same retry key is safe.
- **A retry key used for a different act.** The ledger finds the key first and returns the row it already holds, without comparing the new act with it.
  Measured: sending `Alice is done` under the key already used for Alice's check returned `200`, `appended`, the check's row, and added nothing.
  A new act needs a new key.
- **The clock.** A contract written for another unit or starting point runs with its deadlines shifted, with no error (see [The clock](#the-clock)).
- **A `503` that hides a write.** If a time or memory limit fell after the row was written, the reply cannot tell.
  The reply says as much in `retry`, and a retry under the same key then reads the row back.
- **A deadline that passes unnoticed.** No tick row is written until the next proposal, so an instance whose deadline has passed still shows its obligations at its head.
  The position's `deadlinePassed` is the sign.
- **Due ticks survive a refusal.** The ledger appends the tick rows that are due before it looks at the act, so a proposal that is then `refused`, `conflict` or `unknown` can leave them behind, and the instance's head has moved.
  The reply lists them under `ticks`, as an `appended` reply does, and a `refused` or `conflict` reply's `head` is the head past them.
  `applied` stays false, because it means only that the proposed act was appended, so a proposer that reads `applied` or `result` alone does not see the rows; read `ticks`, or the position.
  A call that lost a race to append, and ran again, lists the ticks of every attempt, since by the retry they are rows and no longer due.
  Measured on 2026-10-26 on the service built at `420bb6258`, which did not list them: an instance at head 2 whose deadline had passed answered a proposal for an act the contract does not have with `422` `refused` and `head` 3, no `ticks`, and its position then read head 3 and terminal.
  The same proposal now lists the tick (seq 3, at 75601), tested over HTTP in `jl4-service-test` and in the library's `LedgerSpec`.
  A `strict` proposal against a whole-head version (no versioned cells) is a `conflict` whenever a tick came first, since the tick moves the head; the library tests that case, and the `conflict` reply lists the tick that caused it.
  No test makes a tick precede an `unknown`: the code lists them there too, and that is not tested.
  Option B, to write no tick when the act is refused, is not what the ledger does; it would change what a refused proposal writes and which head a strict proposal decides against.
- **An advisory answer that went stale.** It is not an error at all.
  It names the head it was computed at, so a proposer can see how far the instance has moved.
- **The rule changing under a live instance.** `PUT` to a deployment that holds instances is not refused, and the rows replay against whatever is deployed.
  Each row records its `ruleVersion`, and nothing compares it with the version now live.
- **An act with no write tool.** An act whose fields are not all BOOLEAN, NUMBER or STRING is missing from `tools/list`, with no word there.
  The read tool names every such act under `writeTools.notOffered`, with the reason, and says so when the deployment's acts could not be read, in which case no write tool is listed at all.
- **A party taken as sent.** The service checks no credentials, on these routes or any other.
  The MCP write tools take the party from the `X-L4-Party` header, which is no stronger.
  The ledger checks that the party is one the contract has, not that the caller is that party, so anyone who can reach the routes can propose as any party.
  Where a deployment has access control, it sits in front of the service, and this page cannot say how a particular arrangement protects these routes.
- **The wrong store for the job.** An in-memory ledger loses its instances at a restart while the deployments return, so an act the rule refused can be proposed again and accepted, and a retried key can be appended twice.
  An in-memory ledger behind more than one process forks, with each process holding its own history, and so does a SQLite ledger whose processes do not share one file.
  A SQLite file shared over a network filesystem cannot be trusted to lock.
  Nothing in the ledger detects any of these; the choice of store is the only protection.

## Limits and what is not here

- Each append replays the instance's whole history and type-checks the contract again, so the cost of an append grows with the number of rows.
  Creating a dinner instance already allocates more than the 256 MB a decision is allowed (measured: under that limit it is stopped, and the reply names the limit).
  The ledger therefore has its own limit, `--ledger-max-eval-memory-mb`, 8192 by default.
- No cap on the number of instances or rows is set.
- The ledger has its own small pool of evaluation slots, at most half of `--max-concurrent-requests`.
  A request that finds none free is answered at once with `503`, not queued.
- No route removes an instance, so a deployment that has held one cannot be deleted through the service.
  The overwrite guard looks when the `POST` arrives; an instance created while the new bundle compiles is not looked for again.
- The tool `what-may-I-do-now` appends nothing.
  An agent appends through the events route or, on a service started with `--ledger-mcp-write`, through a write tool (see [Write tools over MCP](#write-tools-over-mcp)).
- Two instances with two owners have no shared step, and no cross-instance transaction is offered.

## See also

- [What is owed now: `l4 lts`](lts-list.md), whose words the position uses.
- [Deadlines and consequences](consequences.md), for `WITHIN`, `HENCE` and `LEST`, which the deadlines and verdicts above come from.
- The routes, flags and limits as the service lists them: [jl4-service README, Instance Ledger](../../../jl4-service/README.md#instance-ledger).
- The reasons and the open questions behind the design: [OPERATIONAL-LOWERING-SPEC.md](../../../specs/proposals/OPERATIONAL-LOWERING-SPEC.md).
