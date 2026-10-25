# PARTY-BINDER-SPEC: a party bound by the event

**Status:** proposed, not ruled; nothing built; nothing of this spec is on `unstable`.
**Branch:** `mengwong/regulative-lowering-spec`, third commit, scoped at the word WHODUNIT (2026-10-25).
**Owner of the gap:** REGULATIVE-LOWERING-SPEC.md §1 finding 10 and §4.3 option C; register row D-L9 there points here.
**Scenario:** the companion specs' dinner race, per card L5 (ruled 2026-10-25, recorded in REGULATIVE-LOWERING-SPEC §9); the probes of §1 are written in it.
**Measured against:** the worktree at `origin/unstable` plus the two lowering-spec commits, and the installed `l4` of 2026-10-21 (`--version` prints `dev`), on 2026-10-25.
Every `file:line` below was read on that tree; a later tree may have moved them.

## 0. The one-paragraph thesis

L4 has two ways to say who an obligation falls on: `PARTY e`, an expression that must already have a value, and `EVERY v`, a variable that ranges over a group and makes one obligation per member.
Neither says *whoever acts*: one obligation, consumed once, whose bearer is the party of the event that matched it, with that party then in scope for the consequence.
The action slot has had exactly this since R1: `MAY act` with `act` unbound is a fresh binder that the matching event fills.
The subject slot does not, and the gap is one frame in the machine and one constructor in the parser.
It is the construct the regulative lowering's option C is working around by writing one `World` party and the actor into the action's constructor name, and it is the construct that would let the operational ledger's `party` column hold the real actor.
It needs nothing from NORM-LOG-SPEC N10 for an all-`MAY` chain, and it does not touch option C's silent `MUST` limit, which still needs N10's goal A.

## 1. The gap, measured

The probes below use the companion specs' scenario (REGULATIVE-LOWERING-SPEC §0): Alice and Bob each mean to buy dinner tonight unless the other already has, so a check and a purchase by each can interleave.
The four probes of this section were run in that scenario on the installed `l4`.
The claims about the original private worked example (§1.3, §2.1, §4.3) and about the verification probes' hand models (REGULATIVE-LOWERING-SPEC §1; here §4.1, §4.3) were read on those, not on dinner files; the dinner fixtures of REGULATIVE-LOWERING-SPEC §7 are specified, not yet built or run.

### 1.1 Where it fails

`PARTY` takes an expression: `subject` parses `PARTY` then `indentedExpr` (`jl4-core/src/L4/Parser.hs:3263-3269`).
The name then reaches the resolver as a reference, and an unbound `p` fails there with the message buy-blocker's probe reported.
This probe, `party-binder.l4`, reproduces it:

```l4
IMPORT prelude

DECLARE Party IS ONE OF Alice, Bob
DECLARE Act IS ONE OF
    `checks whether dinner is bought`
    `buys dinner`

closing MEANS 75600

GIVETH A DEONTIC Party Act
`the evening` MEANS
    PARTY p
    MAY   act
    WITHIN 0 OF closing
    HENCE `the evening`

#TRACE `the evening` AT 64800 WITH
    PARTY Alice DOES `checks whether dinner is bought` AT 65100
```

`l4 run party-binder.l4`, re-run 2026-10-25 on the installed `l4`, reports at `12:11-12:12`, the `p` of `PARTY p`:

```
I could not find a definition for the identifier

  p

which I have inferred to be of type:

  Party
```

The regulative spec's §1 finding 10 quotes the same message.
The rule that turns an unbound name into a binder, R1's `ReadsAsBinder` (`jl4-core/src/L4/TypeCheck.hs:5316-5330`, `actionNameReading`), runs only inside a regulative action pattern; `NotInActionPattern` falls through to the pre-R1 behaviour, and the subject is not an action pattern.
So the finding-10 sentence, "name resolution fails on `p`", is right and incomplete: the resolver is doing what the parser told it to, and the parser has no binder position in the subject.

### 1.2 What `EVERY` gives, and what it does not

`EVERY v` binds a variable of the party type and makes one obligation per member of the roll (`EVERY.md:14-23`); under the fork, `UPON EACH`, the member is in scope in the `HENCE` and `LEST` (`EVERY.md:71`, `:323`); under the barrier, `ONCE ALL HAVE`, the continuation belongs to the join and cannot name the member (`EVERY.md:435`).
The threshold-one barrier that would fire once on the first act, `ANY OF`, is in the EVERY-EACH table as "no quantifier today" (`specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md:713`), and a barrier's continuation would lose the actor anyway.

The fork was the one candidate, so it was run, 2026-10-25, on the installed `l4`.
A bare `EVERY p` is refused at run time, when its `#TRACE` is evaluated; `every-bare.l4`:

```l4
IMPORT prelude

DECLARE Party IS ONE OF Alice, Bob
DECLARE Act IS ONE OF
    `checks whether dinner is bought`
    `buys dinner`

closing MEANS 75600

GIVETH A DEONTIC Party Act
`the evening` MEANS
    EVERY p
        MAY    act
        WITHIN 0 OF closing
        UPON   EACH
        HENCE  FULFILLED

#TRACE `the evening` AT 64800 WITH
    PARTY Alice DOES `checks whether dinner is bought` AT 65100
```

```
EVERY has nothing to draw its cast from. Running a quantified obligation needs a list of the parties it ranges over, because a party type is normally open: `Tenant HAS name IS A STRING` has infinitely many values. Name the list with IN, as `EVERY Tenant t IN tenants MUST ...`, with `tenants` a LIST of the party type. (The older `EVERY Tenant t WHO elem t tenants` spelling is DEPRECATED and still runs, but IN says the roll outright and is checked earlier.) (EVERY-EACH-QUANTIFIER-SPEC sections 11.0.2 and 2.2.7.5 point 5; doc/reference/regulative/EVERY.md.)
```

So the fork names its roll with `IN parties`, in `every-fork.l4`:

```l4
IMPORT prelude

DECLARE Party IS ONE OF Alice, Bob
DECLARE Act IS ONE OF
    `checks whether dinner is bought`
    `buys dinner`
    `says dinner is bought`

parties MEANS LIST Alice, Bob
closing MEANS 75600

-- Does a fork over MAY give "whoever acts" with the actor in scope, on a recursive chain?
GIVETH A DEONTIC Party Act
`the evening` MEANS
    EVERY p IN parties
        MAY    act
        WITHIN 0 OF closing
        UPON   EACH
        HENCE  CONSIDER p
               WHEN Bob THEN FULFILLED
               OTHERWISE `the evening`

#TRACE `the evening` AT 64800 WITH
    PARTY Alice DOES `checks whether dinner is bought` AT 65100
    PARTY Bob DOES `buys dinner` AT 65160
    PARTY Alice DOES `buys dinner` AT 65220

#TRACE `the evening` AT 64800 WITH
    PARTY Alice DOES `checks whether dinner is bought` AT 65100
    PARTY Alice DOES `buys dinner` AT 65220
```

The first trace's result:

```
PARTY Alice
  MAY act
  WITHIN 0 OF closing
  HENCE (CONSIDER p
           WHEN Bob THEN FULFILLED
           OTHERWISE `the evening`) AND PARTY Bob
                                          MAY act
                                          WITHIN 0 OF closing
                                          HENCE (CONSIDER p
                                                   WHEN Bob THEN FULFILLED
                                                   OTHERWISE `the evening`) AND FULFILLED AND FULFILLED
```

Two things were read off the result.
The variable **is** readable in the consequence: `CONSIDER p` chose the `Bob` branch and printed `FULFILLED`.
But the chain **does not close**: the result is a residual, `PARTY Alice MAY act … AND PARTY Bob MAY act … AND FULFILLED AND FULFILLED`.
Each act's `HENCE` re-arms a fresh `EVERY` over both members while the other member's original `MAY` is still live, so Bob's purchase at 65160 matched two live `Bob` `MAY`s and fulfilled both, and after three events two `MAY`s were still pending.
The second trace, Alice's check and purchase with no purchase by Bob, leaves four live `MAY`s, one Alice's and three Bob's (its result is in `every-fork.out`).
A fork over a recursive `MAY` is a multiplying group, not one obligation that moves.
That is a measurement of the fork doing what `EVERY.md:323` says it does, not a defect in it.

The remaining existing construct is `ROR` across the parties, each alternative recursing in its `HENCE`.
The every-each session ran it on the same installed `l4` against the original-skin counterpart of the trace above; restated in this scenario as `ror-parties.l4`, it was re-run here 2026-10-25:

```l4
IMPORT prelude

DECLARE Party IS ONE OF Alice, Bob
DECLARE Act IS ONE OF
    `checks whether dinner is bought`
    `buys dinner`
    `says dinner is bought`

closing MEANS 75600

-- Existing constructs only: ROR across the parties, recursion in HENCE.
GIVETH A DEONTIC Party Act
`the evening` MEANS
        PARTY Alice
        MAY   act
        WITHIN 0 OF closing
        HENCE `the evening`
    ROR
        PARTY Bob
        MAY   act
        WITHIN 0 OF closing
        HENCE `the evening`

#TRACE `the evening` AT 64800 WITH
    PARTY Alice DOES `checks whether dinner is bought` AT 65100
    PARTY Bob DOES `buys dinner` AT 65160
    PARTY Alice DOES `buys dinner` AT 65220

#TRACE `the evening` AT 64800 WITH
    PARTY Bob DOES `buys dinner` AT 65100
    PARTY Alice DOES `checks whether dinner is bought` AT 65160
```

Its two results, in trace order:

```
PARTY Alice MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Alice MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 10380 HENCE `the evening` OR PARTY Alice MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 10380 HENCE `the evening`
```

```
PARTY Alice MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Alice MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 0 OF closing HENCE `the evening` OR PARTY Bob MAY act WITHIN 10440 HENCE `the evening`
```

`ROR` is non-committal, neither alternative is dropped when the other acts, and after the three events the residual holds eight live alternatives (five after two events on the Bob-then-Alice trace).
So the two composition operators the language has, the fork and `ROR`, both multiply the live `MAY`s on a recursive chain, and neither consumes the choice.

So the gap is sharper than finding 10 states it.
It is not "two parties on one chain", which the fork and `ROR` can spell; it is **one obligation whose bearer is whoever acts, consumed once, with the actor in scope afterwards.**
EVERY-EACH `:713` recorded the nearest gap as a count join at threshold one, which fires once but belongs to the join and so loses the actor; the subject-head form proposed here was never specified there, so "the gap was known" is true of the count form only.

### 1.3 How option C works around it

REGULATIVE-LOWERING-SPEC §4.3 option C writes one party, `World`, and puts the actor into the action's constructor name (`` `ledger records Bob's purchase` ``), then dispatches on the action with `CONSIDER act`; the original private worked example does the same with a single party's `MAY act HENCE CONSIDER act`.
The cost §4.3 records is that `PARTY` stops being the actor: who did what is a constructor name, every event's `party` field is the same constant, and jl4-service's `events[].party` (`jl4-service/src/Compiler.hs:385`) carries no information.
§4.3 assigns the recovery of `PARTY` as the actor to D-L8, the N10 lockstep.
This spec takes that assignment back for the all-`MAY` case: a party binder recovers it without lockstep, because one chain has no cross-operand read (§4 below).

## 2. What the binder is, against three things Meng named

### 2.1 The performer rule

DEONTIC.md §"Actors, actions, and the performer rule" and ACTOR-ACTIONS-THEORY.md §1-§2 make actors values of one type and actions records that carry their actors, with the performer the first actor positionally.
The agreement check, `checkRegulativeActorAgreement` (`TypeCheck.hs:3319-3327`), is static and fires only when both the party and the action's performer are known constructors (`:3316-3318`); for a computed party it is silent, and the EVERY checker's own comment admits that nothing enforces performer agreement for a bound variable at run time either (`:2865-2872`: the machine checks that the event's party is the member, which is a different question from whether the action's actor field names the performer).
A party binder is a computed party, so it inherits that silence.
It can also close it: at the match, `p` is a value and the action is a value, so `p = performer(act)` is a run-time check the machine can make where `act` carries an actor field (§3.4).
Where the action carries no actor, as in the probes of §1, the original private worked example and the brief's fixtures, the check is vacuous and the binder is the only way `PARTY` names the actor at all.
This is the converse the performer rule leaves open: the rule derives the party from a known action, and the binder lets the event fill the party and then checks the action against it.

### 2.2 The actor-specialised action typing jl4-service reads

jl4-service publishes `deonticPartyType` and `deonticActionType` per exported function (`jl4-service/src/Compiler.hs:416-417`, read at `jl4-service/src/DataPlane.hs:272`) from the contract head `DEONTIC Party Act`.
The binder lives in the deonton's subject, not in the head, so the head stays monomorphic and jl4-service's surface is untouched.
That matters because `specs/done/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md` §3 (`:526-534`) rejected an actor-agnostic head, `DEONTIC SOME who`, on arity and on the event type having no concrete party to feed it.
The rejection does not reach here: the event type is still `event Party Act`, and the binder is a pattern over its first field.
The type-indexed encoding there (`Action Eater` as a phantom index) is the other thing Meng's phrase "dependent types of acts specialized by actor" could mean; ACTOR-ACTIONS-THEORY.md §1 records why value-actors are recommended over it, and both still exist in the checker, `checkPartyActionAgreement` for the indexed form and the value check beside it (`TypeCheck.hs:3300-3318`, "complements rather than duplicates").
The binder is well typed under both: a type-indexed head has one actor type in its party slot, so agreement there is static and the binder ranges over that type's values; under value-actors the §3.4 run-time check is the agreement.

### 2.3 Card B1, lifecycle values

Card B1 (EVERY-EACH-QUANTIFIER-SPEC `:1435`, ruled not built, branch `lang/lifecycle-values` at 5279313a8) makes `THE JOIN`, `THE DEADLINE` and `THE ARMING` lexically scoped values a deonton introduces at a point in its lifecycle, through a `Lifecycle` expression constructor.
A party bound by the event is the same kind of thing one step earlier in the lifecycle: the deonton introduces it at the **match**, as `THE JOIN` is introduced at the join.
The scope rule follows the same shape `EVERY.md:71-73` already uses: in scope where there is a matched event to speak of, out of scope in what is read once before any event, which for a single deonton is the window's edges (§3.3).
B1 is not a dependency.
The binder can be built on today's `Subject`, and if B1's `Lifecycle` constructor lands first the bound party could be spelled through it as well (`THE ACTOR`, say); §6 lists that as a spelling question, not a design one.

## 3. Proposal

### 3.1 Syntax, three options, one recommendation (proposed, not ruled: R-P1)

**A, recommended: a third subject head, `ANY`.**

```l4
ANY [Cast] p [IN roll] [WHO condition]
    MAY/SHANT action
    [WITHIN deadline [OF anchor]]
    [HENCE consequent]
    [LEST alternative]
```

It parallels `EVERY [Cast] v [IN roll] [WHO condition]` (`Parser.hs:3270-3279`) in every field, so the cast, roll and filter machinery is reused, and it differs in one word that already carries the meaning: EVERY-EACH §2.2.7.3 reserves `ANY OF` as "count at least one" (`:713`), and `ANY` is not a lexer keyword today (`jl4-core/src/L4/Lexer.hs`, `keywords` table from `:288`; grep for `"ANY"` finds nothing), so it is free.
Read aloud, `ANY Tenant t WHO is current MAY terminate HENCE … t …` says what it does.
One new keyword is the cost, and it is a keyword EVERY-EACH's count-join grammar already plans to introduce in another position (`'ANY' 'HAS'` on the join line, `:738`), so the two uses share one lexer entry and cannot collide, one being a subject head and the other following `ONCE`; the parent spec's R-V3 count of fifteen compiler-enforced sites was for a directive, and a subject keyword touches the lexer, the parser's `subject`, `L4.Syntax.Subject`, exactprint and the printer.
Parser.hs:3258-3262 warns that holes are zipped positionally against the `Subject` constructor's fields and a mismatch does not fail to compile; a third constructor must carry its own hole order and a test that round-trips it.

**B: bare `PARTY p`, by extending R1 to the subject.**
It is what Meng wrote and what buy-blocker tried, it needs no keyword, and it has R1's own precedent: an unbound action name is already a binder.
Its footgun is the one R1 exists to manage, now in a worse place: `PARTY Alcie MAY act` would silently match every party, where today it is a resolver error, and R1's notice machinery (`ReadsAsOuterReference`, `TypeCheck.hs:3462-3470`) would have to be duplicated for the subject.
It also leaves no room for a cast or a roll without further syntax.

**C: `SOME p`.**
`SOME` is lexed (`Lexer.hs:275`, `:382`) and unused, but Meng ruled on 2026-09-06 that `SOME m OF` means *at least m* (EVERY-EACH `:777-782`), so `SOME p MAY act` reads as a count and invites the misreading the ruling was written to prevent.
Not recommended.

### 3.2 Semantics, in one frame

Today the machine forces the party, then compares it with the event's party at `Contract7 PartyEqual` and branches on the boolean at `Contract8 ScrutinizeParty` (`jl4-core/src/L4/EvaluateLazy/Machine.hs:2800-2820`): `True` goes on to match the action pattern, `False` logs `PartyMismatch` and tries the next event.
For an `ANY` subject the compare becomes a bind: the event's party is tested against the cast (its head constructor), the roll (membership, as the EVERY roll is tested) and the `WHO` filter, and on success `p` is bound to it in the environment the action pattern, `HENCE` and `LEST` are evaluated in.
Everything downstream of `Contract8` is unchanged: the action pattern is matched as now, with `p` resolvable inside it under R1 as a lexical reference (`TypeCheck.hs:2874-2879` gives the same rule for the EVERY variable, so `MAY Sign p` ties the action to the bearer).
One event matches one `ANY` once; there is no roll to multiply over, which is the difference from the fork measured in §1.2.
`ANY` with no cast, no roll and no filter matches any party of the type, which is the all-`MAY` chain's case.

### 3.3 Scope (proposed: R-P4)

The fork's rule, variable in scope in `HENCE` and `LEST`, does not carry over, because an `EVERY` member exists before anyone acts and a bound party exists only if someone did.
A `MAY`'s `LEST` runs on lapse, when nobody acted, and a kept `SHANT`'s `HENCE` runs at the end of its window, when nobody did the act (`doc/reference/regulative/consequences.md:73`, `:120`); in both, `p` has no value.
So `p` is in scope in a **`MAY`'s `HENCE`** and a **`SHANT`'s `LEST`**, the two continuations that an act reached, and in the action pattern (as a reference) and the `WHO` filter.
It is out of scope in a `MAY`'s `LEST` and a `SHANT`'s `HENCE`, and naming it there is a type error, not a run-time refusal, since the modal is known statically; `BREACH BY p` therefore belongs only in a `SHANT`'s `LEST`.
It is out of scope in the `WITHIN`, `AFTER` and `BEFORE` edges and their `OF` anchors, because the window must be known when the obligation is armed to decide lapse, and the party is not known until an event matches; this is the same reason `EVERY.md:73` gives for the roll and the join `WITHIN`.
The first draft copied the fork's rule and left `BREACH BY p` unbound in a `SHANT`'s `HENCE`; the every-each session found it (2026-10-25).

### 3.4 The run-time performer check (proposed: R-P3)

At the match, if the matched action is a record with an actor-typed field, the machine compares the bound `p` with the action's performer under the positional canon `subjectOfActionExpr` already implements statically (`TypeCheck.hs:3343-3353`), and a mismatch is a `PartyMismatch` for that event, not a type error, so the event is tried against the next norm as any non-matching event is.
If the action carries no actor field the check is vacuous.
The same check would close the hole `TypeCheck.hs:2865-2872` admits for `EVERY`, where today `EVERY Tenant t MUST Sign u` is accepted for any `u`; whether to extend it there is a separate decision and this spec only notes it.

### 3.5 Modals (proposed: R-P2)

`MAY` and `SHANT` only.
`ANY p MAY act` is the all-`MAY` chain's construct.
`ANY p SHANT act` is well defined: whoever does the act is the violator, and `p` is bound at the violation for `BREACH BY p` in the `LEST`; its `HENCE`, which runs when the prohibition was kept, has no `p` (§3.3).
`ANY p MUST act` is not proposed: on lapse nobody acted, so there is no bearer to blame, and the norm log's N7 question (nobody named against not yet known, NORM-LOG-SPEC §6 N7, reopened) is exactly the one it raises; it is deferred, not refused.
A `MUST` whose bearer is a group is `EVERY` with a barrier, which exists.

### 3.6 The norm log

The log's key learns the bearer at `Contract8` (`Machine.hs:2806-2810`, `naming party norm`); for an `ANY` the bearer is unknown from arming to match, which N7's "not yet known" category already names.
Nothing new is logged; the `armed` entry carries no bearer and the `exercised` or `violated` entry carries the bound one.

## 4. Composition with the regulative lowering

### 4.1 Option C, rewritten

§4.3's option C sketch becomes:

```l4
-- unrun sketch
DECLARE Party IS ONE OF Alice, Ledger, Messages
DECLARE Act IS ONE OF
    `checks whether dinner is bought`
    `buys dinner`          HAS `ledger answered` IS A BOOLEAN
    `records opening`
    `records Bob's purchase`
    `delivers the message`

`the evening` MEANS
    ANY p
    MAY act
    WITHIN 0 OF closing
    HENCE CONSIDER act
          WHEN `records Bob's purchase` THEN COMMIT `dinner status record` IS … HENCE `the evening`
          …
```

What it gains: `PARTY` is the actor again, so the event's `party` field is true, the operational ledger's `party` column (OPERATIONAL-LOWERING-SPEC §3.1) holds the real actor rather than `World`, jl4-service's `events[].party` means what its schema says, and the emitted labels for Bob's purchase, the message and the bought-check map to (party, act) pairs rather than to constructor names, which is how the hand models already label them.
One condition is load-bearing.
Under option C the constructor names are what tell the explorer that only the ledger records Bob's purchase; the sketch above drops them, so without more the candidate space under `ANY p` is every (party, act) pair, `Alice` recording Bob's purchase included, and the hand models have no such edge, so §6.2's bisimulation would fail rather than hold.
So the fixture's acts must carry an actor field (`` `records Bob's purchase` HAS by IS A Party ``) and R-P3 must prune the pairs at the match, which is the performer rule doing its job, or the explorer must refuse an actor-free action type under `ANY`; one or the other is a precondition of the rewrite, and §4.3 below is conditioned on it.

What it does not fix: §4.3's **silent** limit stands.
While a `MUST` or `SHANT` is pending in the chain, an event of another party still goes nowhere, because the obligation waits for its one action and a non-matching event is passed over.
`ANY` changes who may fill the subject of one norm; it does not make a chain accept events for norms that are not armed.
A fixture with a real obligation and environment acts arriving during it still needs option A under N10's goal A (D-L8), and the explorer and the operational ledger's refusal of a C-shaped chain holding a `MUST` or `SHANT` over other parties' acts stands unchanged.

### 4.2 What it needs from N10

For an all-`MAY` chain, nothing.
One chain has one strand, so a `COMMIT` is read by the next step in event order (buy-blocker's control, §4.3), there is no cross-operand `RECALL`, and neither N10's option B check nor its goal A is engaged.
This is the route to `PARTY` as the actor on option C without waiting for lockstep, which §4.3 currently assigns to D-L8; the edit to that section says so.
For a chain that composes `ANY` deontons with `RAND`, N10 applies exactly as it does to `PARTY` deontons, and nothing here changes it.

### 4.3 The explorer and the emitters

REGULATIVE-LOWERING-SPEC §4.2 enumerates binders finitely and refuses what it cannot (R-L4).
A party binder is one more binder, with a domain the explorer can usually read off: the constructors of the party type when it is an enumeration, which the brief's fixtures, the probes of §1 and the original private worked example have; the `IN` roll when one is written; the cast when one is written.
A party type with an open field (`Tenant HAS name IS A STRING`) and no roll is refused per constructor as §4.2 refuses an unbounded `NUMBER`, with the author-declared domain of D-L7 as the way out.
Each emitter then gets one labelled transition per (party, act) pair the binder admits; with §4.1's condition met, actor fields on the acts and R-P3 pruning, those pairs are the labels the TLA+, mCRL2 and Petri hand models already use, so §6.2's bisimulation holds and §6.1's fairness per labelled action is unchanged; without it the graph gains edges the hand models lack and §6.2 fails.
The `WhatIf` candidate generator (`jl4-core/src/L4/Lts/WhatIf.hs`, `candidatesOf` from `:322`) today reads the party back from the armed norm (`roParty`, `:329`) and varies only the action pattern (`:330-341`); under `ANY` it varies both, and the whole-action binder's type recovery §4.2 relies on applies to the party the same way.

## 5. What this does not claim

It does not claim the fork is wrong; §1.2 measured it doing what its page says.
It does not claim `ANY` closes option C's silent `MUST` limit; §4.1 says it does not.
It does not propose `ANY p MUST`; §3.5 defers it to N7.
It does not touch the contract head, jl4-service's schema or the event type.
It does not propose B1's `Lifecycle` constructor as a dependency; §2.3 says the binder can be built on today's `Subject`.
It changes no file but this one and the regulative spec's §1, §4.3 and §10, and builds nothing.

## 6. Rulings proposed (not ruled)

- **R-P1 Spelling.** A: `ANY [Cast] p [IN roll] [WHO condition]` as a third subject head, one new keyword, every EVERY field reused; B: bare `PARTY p` as a binder by extending R1 to the subject, no keyword, the typo footgun in the subject; C: `SOME p`, rejected here for colliding with the ruled "at least" reading. Recommendation: A. If B1's `Lifecycle` constructor lands first, whether the bound party is also reachable as a lifecycle noun is a spelling question for that spec.
- **R-P2 Modals.** `MAY` and `SHANT`; `MUST` deferred to N7. Recommendation: as stated.
- **R-P3 Run-time performer check.** At the match, bound `p` against the action's positional performer where the action carries an actor field; mismatch is a `PartyMismatch`, not an error. Recommendation: build it with the binder; extending it to `EVERY` is a separate decision.
- **R-P4 Scope of the bound party.** A: `p` in scope only in the continuation an act reached, a `MAY`'s `HENCE` and a `SHANT`'s `LEST`, plus the action pattern and the `WHO` filter, with a type error elsewhere; B: the fork's rule, `p` in scope in both continuations, with a run-time refusal where it has no value, as the barrier refuses its member today (`EVERY.md:435`). Recommendation: A, because the modal is known statically and a refusal that waits for the run is the rough edge `EVERY.md:435` already apologises for.

## 7. Register

| id | deferred | trigger | owed by |
|---|---|---|---|
| **D-P1** | `ANY p MUST act`: who is blamed on lapse | NORM-LOG-SPEC N7 being re-ruled | §3.5 |
| **D-P2** | the §3.4 check extended to `EVERY`, closing `TypeCheck.hs:2865-2872`'s admitted hole | the first corpus file where `EVERY v MUST Act u` with `u ≠ v` is found to be a mistake rather than a procurement | §3.4 |
| **D-P3** | spelling the bound party as a lifecycle noun through B1's `Lifecycle` constructor | B1 landing on `unstable` | §2.3, R-P1 |

## 8. Evidence

- `party-binder.l4`, `every-bare.l4`, `every-fork.l4`: probes written and run 2026-10-25 on the installed `l4` (`dev`, built 2026-10-21), restated in the dinner scenario and re-run the same day, in the pitch-Oct session's scratchpad under `whodunit/dinner/`, each beside its `.out`; §1.1 inlines the first and quotes its error, §1.2 inlines the second and quotes its "EVERY has nothing to draw its cast from" refusal, which is why the third carries `IN parties`, and inlines the third and quotes its first result.
- `ror-parties.l4`: the every-each session's probe (its scratchpad, `whodunit-recheck/`), written in the original skin, restated in the dinner skin beside the three above and re-run here 2026-10-25; §1.2 inlines it and quotes its eight-alternative and five-alternative residuals.
- Review: the every-each session read the first draft on 2026-10-25 and supplied the `ROR` probe, the §3.3 scope hole and the `:713` qualification; all three are folded in above.
- Line citations: `Parser.hs:3237-3279` (subject), `TypeCheck.hs:2855-2882` (EVERY check), `:3300-3359` (agreement and performer), `:3452-3470` and `:5316-5330` (R1), `Machine.hs:1788-1800` (subject evaluation), `:2796-2822` (party match frames), `Compiler.hs:360-421` (jl4-service schema), `DataPlane.hs:272`, `Lexer.hs:275`, `:288-382`, `EVERY.md:14-23`, `:71-73`, `:323`, `:435`, `EVERY-EACH-QUANTIFIER-SPEC.md:713`, `:777-782`, `:1435`, `DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md:526-534`.
