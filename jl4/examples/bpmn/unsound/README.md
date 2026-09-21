# Deliberately unsound BPMN

Nine diagrams that are **wrong in a way no parser can see**, kept so that
`etc/check-bpmn-soundness.mjs` can be shown to fail. They are the negative half
of `etc/check-bpmn-soundness.selftest.mjs`; the positive halves are
`../expected/` (exporter goldens) and `../sound/` (hand-written diagrams that
must NOT be flagged).

Each one exists to provoke **one named complaint**, and the self-test asserts
that specific line rather than accepting any failure — a typo'd id would make
almost any file unsound and would otherwise look like proof. The mapping lives
in `EXERCISES` in the self-test, which refuses to pass on a fixture that is not
listed there **and** on an `EXERCISES` entry whose fixture has gone missing, so
coverage cannot silently drift in either direction.

Three kinds of complaint live here, and the `EXERCISES` entries carry the marker
so they cannot be confused: `FAIL Sn` is a **token-game** property the diagram
violates, `STRUCTURE` is a **well-formedness** rule it breaks while playing
perfectly well, and `FIDELITY` is a loss the diagram really has and does not
declare — every `S` passes, the file is well formed, and it is still not one a
reader should be handed. See "A terminating end beside concurrency owes a
declaration" in `../README.md`.

| file                                            | complaint it provokes         | the defect                                   | provenance                     |
| ----------------------------------------------- | ----------------------------- | -------------------------------------------- | ------------------------------ |
| `historical-handover-edge-counted-join.bpmn`    | **S2** no deadlock            | join starves behind lapse timers             | **real pre-fix exporter output** |
| `deadlock-boundary-in-rand.bpmn`                | **S2** no deadlock            | join starves behind an interrupting boundary | hand-written                   |
| `deadlock-ror-in-rand.bpmn`                     | **S2** no deadlock            | join starves behind an `ROR`                 | hand-written                   |
| `unsafe-xor-join-after-rand.bpmn`               | **S4** safe (1-bounded)       | XOR gateway used to merge a `RAND`           | hand-written                   |
| `mislabelled-gateway-direction.bpmn`            | **STRUCTURE** gatewayDirection | gateway declares `Diverging` with 2 incoming | **shape of real exporter output** |
| `deadlock-inside-mi-subprocess.bpmn`            | **S2** no deadlock            | a join inside one member's instance starves; invisible at 0 instances | hand-written                   |
| `historical-fork-undeclared-sibling-loss.bpmn`  | **FIDELITY** undeclared loss  | a member's escalation meets a top-level ERROR end, cancelling the members who did not breach — and nothing says so | **real pre-fix exporter output** |
| `refork-counterfactual-documentation.bpmn`      | **FIDELITY** undeclared loss  | the same defect as a REGRESSION: today's fork golden with one `errorEventDefinition` put back | **real exporter output, one attribute added** |
| `refork-beside-party-cross-instance.bpmn`       | **FIDELITY** undeclared loss  | the same regression on the one fork that sits inside an unjoined `RAND`, where a TRUE note about the `RAND` used to exempt it | **real exporter output, one element added** |

**Today's exporter cannot emit any of these shapes** — for the four join
defects, declining to is exactly the fix that `addJoin` in
`jl4-core/src/L4/Bpmn/Lower.hs` implements; for the gateway one it is
`withGatewayDirections`, which computes the attribute from the edges instead of
guessing it a pass too early; and for the undeclared loss it is `addForkScope`,
which mints the fork its own plain `EndBreach_<n>` rather than routing an
escalation into a shared error end. Four of the nine are hand-written and must
never be treated as goldens. Four are real exporter output — two byte-for-byte, and
`refork-counterfactual-documentation.bpmn` and `refork-beside-party-cross-instance.bpmn`
with exactly one element added each — and they are the reason to believe the rest;
the gateway one is a hand-written minimum of a contradiction that really did ship in
`../expected/regcf-reporting.bpmn`.

## `mislabelled-gateway-direction.bpmn` — the one that plays perfectly

Every token-game property **passes** on this file. `S1`, `S2`, `S3` and `S4` are
all green, the process completes, and nothing is stranded. What is wrong is that
the file contradicts itself: `Split_0` declares `gatewayDirection="Diverging"`
while carrying two incoming sequence flows, and BPMN 2.0 §10.5.1 Table 10.100
says `Diverging` MUST NOT have multiple incoming — with multiple of both, the
direction is `Mixed`.

The attribute is a plain enumeration in the XSD, so this is schema-valid and
`bpmn-moddle` reports **0 warnings**. That combination — behaviourally sound,
structurally a lie, invisible to the parser — is exactly why the check had to go
somewhere that already knows each node's real in/out arity, and why it is
reported as `STRUCTURE` rather than as one of S1–S4.

It shipped. `../expected/regcf-reporting.bpmn` carried this contradiction
because the exporter chose the direction in a pass that ran before any edge
existed, and the `HENCE <this rule>` renewal loop then handed that gateway a
second arrival. Both scripts were green over it, which is the whole argument for
the fixture.

## `historical-fork-undeclared-sibling-loss.bpmn` — sound, well formed, and silent

Byte-for-byte `../expected/tenancy-fork.bpmn` as the exporter emitted it at
`fcd7ecb2c^`, with the fidelity report it emitted alongside, renamed to this
stem so the checker finds the pair. No comment header, for the same reason
`historical-handover-edge-counted-join.bpmn` has none: the bytes are the point.

The defect is the one `fcd7ecb2c` fixed. A member's breach escalates out of that
member's own instance — correctly, and without interrupting the siblings — and
then reaches the **top-level error end**. An error end event does not consume one
token and leave the rest running; it ends every active thread in the process,
instances included. So a duty another member had already earned vanished one flow
later, and the file's own `<documentation>` asserted the opposite.

**Every token-game property passes on this file, and it is well formed.** S1, S2,
S3 and S4 are green at 0 instances and at 2, `gatewayDirection` is honest
everywhere, bpmn-moddle reports zero warnings. What it fails is the rule added on
2026-09-21: at two instances `End_3 "Breach"` can fire in markings where it throws
away **up to three** tokens still in flight, and not one of the **nine** notes in
its report is a `lossy` or `blocking` one, filed on that end event or on any other
element the loss touches, saying what becomes of them.

Measured here, on this file:

| checker                                         | verdict                                                                       |
| ----------------------------------------------- | ----------------------------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser) | **OK — 0 warnings**, 11 flow nodes, 8 sequence flows, all drawn                |
| `etc/check-bpmn-soundness.mjs`                  | SOUND at 0 instances; at 2, **UNSOUND on `FIDELITY`** with S1–S4 all **PASS** |
| `etc/check-bpmn-kie.sh` (jBPM 7.74.1)           | not run here — the baseline covers `../expected/` only                         |

That second row is the whole fixture. It is the only file in this directory whose
complaint is not about what the diagram *does*, and the only one where reading
the `PASS` lines and stopping there would tell you it was fine.

Why it belongs in `unsound/` rather than `sound/`: the piles are named for the
**verdict the gate must return**, not for the kind of defect. `../README.md`'s
table says so, and the self-test reads it that way.

## `refork-counterfactual-documentation.bpmn` — the same defect, arriving as a regression

`../expected/tenancy-fork.bpmn` exactly as the exporter emits it today, with one
`<bpmn:errorEventDefinition>` put back on `EndBreach_0` and a `<bpmn:error>`
declaration added so the reference resolves. Its `.fidelity.txt` is today's real
eleven-note report, unedited. That is the whole diff: the pre-`fcd7ecb2c` defect
re-introduced on a current file.

Its sibling above is the historical record; this one is the **regression test**,
and it exists because the declaration rule as first written did not catch it. The
rule also accepted a `<documentation>` on the terminating end event, and the
exporter puts one there reading:

> a member breached. A plain end and not an error end: an error end event ends
> every active thread in the process, so it would cancel the instances of the
> members who did not breach. See P-FORK-BREACH-UNMARKED.

That sentence exists to say this end is **not** an error end. It matched the rule's
phrase list, so re-marking the end event produced a file with 160 reachable
markings, peak 4, 26 net transitions — the same net as the historical fixture — and
a verdict of **SOUND**, declared by a sentence saying the opposite. Found in review
on 2026-09-21; the `<documentation>` channel was removed rather than taught to
recognise counterfactual prose.

The documentation is still in this file, unedited, which is the point: the channel
is gone, not the text.

| checker                                         | verdict                                                                       |
| ----------------------------------------------- | ----------------------------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser) | **OK — 0 warnings**, 11 flow nodes, 8 sequence flows, all drawn                |
| `etc/check-bpmn-soundness.mjs`                  | SOUND at 0 instances; at 2, **UNSOUND on `FIDELITY`** with S1–S4 all **PASS** |
| `etc/check-bpmn-kie.sh` (jBPM 7.74.1)           | not run here — the baseline covers `../expected/` only                         |

## `refork-beside-party-cross-instance.bpmn` — the acceptance test, where a TRUE note is not a declaration

`../expected/tenancy-fork-beside-party.bpmn` exactly as the exporter emits it today,
with one `<bpmn:errorEventDefinition>` put back on `EndBreach_1`. Its
`.fidelity.txt` is today's real twelve-note report, unedited. Same one-element diff
as its sibling above; the difference is the file it is applied to.

**Why a third fixture of the same defect.** This is the only fork golden that sits
inside an unjoined `RAND`, so its report carries `[P-NOJOIN] lossy — Split_0` — a
note that is TRUE, admits a loss, is filed on a real junction of this net, and
matches the phrase list. The rule accepted it for `EndBreach_1` and scored this file
**SOUND** in both of its first two versions, where the four plain forks were caught
by the second:

| re-marked fixture | rule `9a7e6be2c` | rule `0d79f3b40` | now |
| ----------------- | ---------------- | ---------------- | --- |
| the four plain forks | exit 0 | exit 1 | exit 1 |
| this one | exit 0 | **exit 0** | exit 1 |

**What the note is actually about.** `P-NOJOIN` on `Split_0` says the top-level
`RAND`'s two branches were not joined, so one branch reaching BREACH abandons the
other. That is a real loss and it IS declared — the file's other terminating end,
`End_3`, is accepted on exactly that note. What `EndBreach_1` now does is different:
one member of the cast cancels **another member**, on one side of that split, where
the split cannot see it. The junction is the sub-process's own multiplicity, and no
element in a BPMN file names one member's run, so the only element that can carry
that declaration is `EndBreach_1` itself. Nothing in the report is filed there but
`P-FORK-BREACH-UNMARKED`, which is `advisory`.

So this fixture is the one place in the tree where the **wording does no work at
all**: measured 2026-09-21, replacing the phrase matcher with one that always
succeeds leaves it red. Its positive control lives in
`etc/check-bpmn-soundness.selftest.mjs`, which appends one `lossy` note on
`EndBreach_1` to a copy of this report and asserts the same diagram then passes.

| checker                                         | verdict                                                                       |
| ----------------------------------------------- | ----------------------------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser) | **OK — 0 warnings**, 14 flow nodes, 10 sequence flows, all drawn               |
| `etc/check-bpmn-soundness.mjs`                  | SOUND at 0 instances (21 markings, peak 2); at 2, **UNSOUND on `FIDELITY`** (486 markings, peak 5, 24 net transitions) with S1–S4 all **PASS** |
| `etc/check-bpmn-kie.sh` (jBPM 7.74.1)           | not run here — the baseline covers `../expected/` only                         |

## `historical-handover-edge-counted-join.bpmn` — the measurement, not the argument

This file is **byte-for-byte what the exporter really emitted before the fix**,
produced by reverting `addJoin`'s token proof to the edge-counting predicate it
replaced and running the exporter over the committed `../handover.l4`. Nothing
about it is reconstructed.

An earlier version of this README argued the soundness check "would have caught"
the historical defect, on the strength of two hand-written reconstructions. That
was an argument, not evidence, and the pre-fix code was sitting in git the whole
time. To reproduce:

```sh
# the edge-counting predicate, as it stood at 8df9205d:
#   if length (filter fst marked) >= 2 then <draw the join> else <decline>
# expressed as a minimal revert of today's tokenProof in
# jl4-core/src/L4/Bpmn/Lower.hs:
#
#   tokenProof r tgt =
#     let arrivals = concatMap (arrivalsOf r tgt) branches
#      in if length arrivals >= 2 then Right arrivals else Left "..."
#
cabal build jl4:l4
cd jl4 && l4 export --to=bpmn examples/bpmn/handover.l4 -o /tmp/handover.bpmn
```

What the three checkers say about that file:

| checker                                        | verdict                                                              |
| ---------------------------------------------- | -------------------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser) | **OK — 0 warnings**, 15 flow nodes, 16 sequence flows, all drawn      |
| `etc/check-bpmn-soundness.mjs`                  | **UNSOUND**, S1+S2+S3 fail; `Join_1` starved on `Flow_Lapse_2__Join_1`, `Flow_Lapse_4__Join_1` |
| `etc/check-bpmn-kie.sh` (jBPM 7.74.1)           | **cannot check it** — rejected at compile for axis A4, see `../README.md` |

So the historical defect is now a measured catch rather than a claimed one — and
the same measurement shows the limit of the engine route honestly, because the
one file that proves the point is the one file jBPM cannot read.

`consultation.bpmn` and `offering.bpmn` come out **byte-identical** under the
pre-fix exporter: only `handover.l4` had a `RAND` whose branches carried lapse
timers, which is the shape the edge-counting predicate got wrong. A regression
suite of those two goldens would have shown nothing at all.

### What jBPM makes of the four directions

Worth recording, because it was the reason the corrected golden was *still*
rejected and the reason the correction is still right. The same fixture, run
with only `gatewayDirection` changed (`etc/check-bpmn-kie.sh`, jbpm-bpmn2
7.74.1.Final, JDK 17.0.20):

| declared      | jBPM says                                                                        |
| ------------- | -------------------------------------------------------------------------------- |
| `Diverging`   | `This type of node [Split_0, one of] cannot have more than one incoming connection!` |
| `Converging`  | `This type of node [Split_0, one of] cannot have more than one outgoing connection!` |
| `Mixed`       | `Unknown gateway direction: Mixed`                                                |
| `Unspecified` | `Unknown gateway direction: Unspecified`                                          |

The `Unspecified` row was measured 2026-08-01, on
`../expected/regcf-reporting.bpmn` **as it then stood** (2 incoming, 3 outgoing)
rather than on this fixture; the same run reproduced the `Diverging` and
`Converging` refusals verbatim on the real file, so the table holds for both
shapes.

> **That golden no longer has a 2-in gateway** — measured 2026-08-02. The
> BPMN→DMN wiring (`specs/todo/lexipedia-superset/PROCESS-TRACK.md` §8.3) put a
> `businessRuleTask` in front of it, which absorbed both arrivals, so `Split_0`
> there is now a plain 1-in/3-out `Diverging` and jBPM has stopped complaining
> about it. The table above is unaffected — it is a fact about jBPM, not about
> that file — and `mislabelled-gateway-direction.bpmn` is unaffected, being
> hand-written and still carrying the contradiction it exists to carry. What
> changed is only that jBPM's objection to `regcf-reporting.bpmn` moved one node
> upstream (`Decide_0`, same "more than one incoming connection"), which
> `PROCESS-TRACK.md` §8.1 records as class (a′). It was
measured because an attribute-level fix for the golden's rejection — emit
`Unspecified` where `Mixed` is computed, on the theory that the XSD default
would pass where the unimplemented value did not — had been planned, and the
measurement killed it: jBPM's parser accepts exactly the two values it has
node types for.

So jBPM really does model a gateway as **either** a split **or** a join, and it
picks which from this attribute: declare `Diverging` and you get a `Split` whose
invariant is at most one incoming, declare `Converging` and you get a `Join`
whose invariant is at most one outgoing. `Mixed` and `Unspecified` are not
values it implements at all — the former BPMN 2.0 §10.5.2 permits, the latter
is the spec's own default, and jBPM takes neither.

Two things follow. The message quoted from a `Diverging` run is about **incoming
arity**, not about mixedness, and citing it as "jBPM refuses mixed gateways"
reads the wrong constraint off it. And no value of this attribute — now all
four are measured — makes jBPM accept a gateway with multiple of both: the
shape is what it will not have, and saying so accurately is all the attribute
can do.

## The three hand-written join defects

The two deadlock fixtures are reconstructions of the same class of defect, built
to the description `addJoin` gives of the code it replaced:

> An earlier version counted rewired edges and required two or more, which
> passes happily for a branch containing an interrupting boundary event
> (`cancelActivity="true"` makes its two arms mutually exclusive: two edges, one
> token) or a `ROR` (an exclusive gateway: n edges, one token). Each of those
> emits a join that waits forever for a token nothing will ever send.

(The comment listed a third case, "a lapse timer (same shape again)", until
2026-09-17. It was the same shape because it _was_ a boundary event — one the
exporter synthesised for itself. A permission's expiry is now drawn as an
ordinary interrupting boundary event on the first of those two, so the third
entry named no distinct case and was dropped.)

All three hand-written files are `../expected/consultation.bpmn` — the one
fixture that legitimately draws a converging parallel gateway — with a single
change made to it. They cover two of the three shapes named in that paragraph
plus a separate defect class; the lapse-timer shape is covered by the real
pre-fix output above.

| File                            | The change                                                                        | Why it is wrong                                                       |
| ------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `deadlock-boundary-in-rand.bpmn` | interrupting boundary `Lapse_2` on `Task_2`, its arm rewired to `Join_0` alongside `Task_2`'s | `Join_0` has three incoming flows; `Task_2` and `Lapse_2` are mutually exclusive, so two tokens arrive |
| `deadlock-ror-in-rand.bpmn`      | exclusive gateway `Split_5` in one branch, both its arms rewired to `Join_0`                 | `Join_0` has three incoming flows; the `ROR` delivers one token down one arm, so two tokens arrive |
| `unsafe-xor-join-after-rand.bpmn` | `Join_0` changed from `parallelGateway` to `exclusiveGateway`, nothing else                  | an XOR gateway does not synchronise: each of the `RAND`'s two tokens passes straight through, so `End_3` and everything before it happens **twice** |

The third is a different defect class from the first two, and it was added
because **S4 had no failing fixture at all** — a property that has never been
observed failing is a property nobody has tested. It is also the more insidious
shape in practice: a deadlock is at least obvious when it happens, whereas an
`ROR`-style merge placed after a `RAND` *completes normally* while silently
discharging every downstream obligation twice. jBPM's own "did it reach an end
state?" verdict says COMPLETED and sees nothing wrong.

## What each checker says about them

Run from the repo root. This is the evidence for adding a soundness check at
all: the check the repo already had passes **all five** files at zero warnings.

**The table below is the original five, and is left at that scope rather than
widened by guesswork.** Four fixtures have been added since. Three of them —
`historical-fork-undeclared-sibling-loss.bpmn`,
`refork-counterfactual-documentation.bpmn` and
`refork-beside-party-cross-instance.bpmn` — have their own measured tables in the
sections of those names. `deadlock-inside-mi-subprocess.bpmn` has never had a
section here and its provenance is the comment header inside the file. Measured
2026-09-21, it is **UNSOUND, S1+S2+S3 fail** at 2 instances with four deadlocked
markings (and SOUND at 0, which is the point of reading the verdict across the
counts), and bpmn-moddle reports **16 problems on it, every one of them "has no
diagram interchange"** — it is a minimal fixture with no `BPMNDiagram` at all,
which is a fact about the fixture and not about the defect it carries. Neither
has a jBPM row, because `etc/bpmn-kie-baseline.txt` covers `../expected/` only.

```sh
npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs jl4/examples/bpmn/unsound/*.bpmn
node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/unsound/*.bpmn
etc/check-bpmn-kie.sh jl4/examples/bpmn/unsound/*.bpmn
```

| Checker                                               | `historical-handover`   | `boundary-in-rand`      | `ror-in-rand`           | `unsafe-xor-join`     | `mislabelled-gateway-direction` |
| ----------------------------------------------------- | ----------------------- | ----------------------- | ----------------------- | --------------------- | ------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser)        | **OK, 0 warnings**      | **OK, 0 warnings**      | **OK, 0 warnings**      | **OK, 0 warnings**    | **OK, 0 warnings**              |
| `bpmnlint` (Camunda's linter)                          | not run                 | **0 findings**\*        | **0 findings**\*        | not run               | not run                         |
| `pm4py` + Woflan (Petri-net soundness)                 | not run                 | **reports SOUND**       | reports unsound         | not run               | not run                         |
| `etc/check-bpmn-soundness.mjs`                         | UNSOUND, S1+S2+S3 fail  | UNSOUND, S1+S2+S3 fail  | UNSOUND, S1+S2+S3 fail  | UNSOUND, **S4** fails | UNSOUND, **STRUCTURE**; S1–S4 all pass |
| jBPM 7.74.1 **compile** (`check-bpmn-kie.sh` phase 1)  | **rejected** (axis A4)  | passes, 0 errors\*\*    | passes, 0 errors\*\*    | passes, 0 errors      | **rejected**, >1 incoming on a `Split` |
| jBPM 7.74.1 **execute** (phase 2)                      | never reached           | **DEADLOCK**, token parked at `Join` | **DEADLOCK**, token parked at `Join` | **DUPLICATION**, `Fulfilled` fired 2x | never reached          |

The last column is the one where jBPM and the soundness checker agree on the
verdict for **different reasons**, and it is not corroboration. jBPM rejects the
file because it cannot build a node with two incoming flows and two outgoing
ones at all; the checker plays that very shape happily and objects only to the
*attribute*. Read as one measurement each, not as two opinions on one question.

\*\* only after the harness supplies a `conditionExpression` for the unguarded
`ROR` — axis A3, a real gap in the emitted XML. Without it jBPM rejects the file
during compilation **for a reason that has nothing to do with the deadlock**,
and never reaches the execution that finds it. That is the single most important
measurement here: a KIE gate that only compiled would have caught none of these,
and would have *looked* like it was working while doing so.

(An earlier version of this note also credited a missing `timeDuration` on the
timer. That was wrong, and the direction of the error matters: the exporter emits
a `timeDuration` on **every** timer event definition — grep `timerEventDefinition`
over `../expected/` — so only the hand-written fixture was missing one. It has
since been given the shape the exporter really emits, and adaptation A5 now fires
zero times on every file in this repository. A binding the exporter never omits
is not a gap in the exporter.)

The `unsafe-xor-join` row is the one where the two engines part company on their
own terms, and it deserves a caveat. jBPM reports COMPLETED — reaching an end
state is all its process instance state can express — so **DUPLICATION is not
jBPM's verdict**. It comes from our listener counting node firings, plus a
hand-tuned exclusion of `Join` nodes (jBPM triggers a converging gateway once per
arriving token, so a *correct* join is triggered n times and fires once). Treat
that row as one tool plus our heuristic, not as an independent second opinion.
Run with `--census` to see the raw firing counts the rule is derived from.

\* after adding the optional `<bpmn:incoming>`/`<bpmn:outgoing>`
back-references the exporter omits; without them bpmnlint calls every node in
every fixture disconnected, including the sound ones. See "the
`incoming`/`outgoing` flavor axis" in `../README.md`.

Woflan reporting `deadlock-boundary-in-rand.bpmn` **sound** is the sharpest
reason not to reach for the off-the-shelf tool: `pm4py`'s BPMN importer drops
boundary events entirely, so it deletes the construct that causes the deadlock
and then pronounces what is left healthy. Its verdict on
`deadlock-ror-in-rand.bpmn` is "some places are not covered by an s-component" —
the same words it produces for the *correct* `offering.bpmn`, so the verdict does
not distinguish a deadlock from a `RAND` the exporter deliberately left unjoined.

The witness `check-bpmn-soundness.mjs` prints names the starved flow:

```
    stuck here, nothing is enabled:
      token on flow:Flow_Task_2__Join_0
          blocks Join_0 — still waiting on flow:Flow_Lapse_2__Join_0
      token on flow:Flow_Task_4__Join_0
          blocks Join_0 — still waiting on flow:Flow_Lapse_2__Join_0
```

## Why the agreement matters more than either verdict

`check-bpmn-soundness.mjs` implements *our* reading of BPMN's token semantics.
That is its weakness as evidence: a hand-written checker encodes the same
assumptions as the exporter it is checking, and if both are wrong in the same
way, both stay quiet. Two of the defects above were originally emitted by an
exporter whose author also believed the diagram was fine.

jBPM shares no code, no author and no assumptions with either. It parks a token
at exactly the join our witness names, on both deadlock fixtures, having reached
that conclusion by running the process rather than by analysing it. That
agreement is the reason to believe the token game is modelling BPMN and not
merely modelling our idea of it — and it is worth more than either tool's
verdict taken alone.

Three things keep that agreement from being worth more than it is, and they are
recorded here rather than left for the next reader to discover:

1. **jBPM never sees the file as emitted.** `KieBpmnCheck.adapt` rewrites it
   first, and A2 is a structural rewrite (end events are cloned and sequence
   flows re-targeted). The engine is independent; the document it reads is ours.
2. **The single explored path is chosen by our own code.** Where a multi-way
   exclusive gateway carries no guards (A3) — the exporter DOES emit
   `conditionExpression`s where the L4 has a guard to draw from, as
   deliberately opaque L4 text; among the goldens only `../handover.l4`'s ROR
   has none — the harness supplies them, and that gateway takes its **first
   outgoing flow in document order**. That interleaving is an artifact, not a
   representative run.
3. **The mechanism on `deadlock-boundary-in-rand.bpmn` is degenerate.** Work
   items auto-complete, so the interrupting boundary timer never fires; what
   jBPM observed is "the join wants 3 arrivals and got 2 because the timer never
   went off", not "the two arms are mutually exclusive". The conclusion coincides
   — either way 2 of 3 arrive — but this harness structurally cannot reach the
   case where the deadlock requires the boundary to *fire*.

The disagreements are informative in the same way, and neither is a defect in
the diagrams:

- **jBPM cannot check `../expected/handover.bpmn`, or the historical fixture
  derived from it, at all** (axis A4 in `../README.md`): the conditional boundary
  event's body is L4 source text declared as a formal expression, so Drools tries
  to parse `` `grace period` `` as DRL and rejects the file. Our checker never
  looks inside an expression, so it is untroubled. This is the sharpest limit on
  the engine route: the one fixture that is *real* pre-fix exporter output is the
  one jBPM cannot read.
- **jBPM misses `unsafe-xor-join-after-rand.bpmn` on its own terms**, as noted
  above. Exhaustive marking exploration catches it directly; a single execution
  does not.

Which is the honest summary of the whole exercise: the soundness check is the
gate because it is exhaustive, portable and needs nothing installed, and the
engine is the corroboration because it is independent. Neither one subsumes the
other, and the engine corroborates less than a first reading of the table
suggests.
