# Deliberately unsound BPMN

Four diagrams that are **wrong in a way no parser can see**, kept so that
`etc/check-bpmn-soundness.mjs` can be shown to fail. They are the negative half
of `etc/check-bpmn-soundness.selftest.mjs`; the positive halves are
`../expected/` (exporter goldens) and `../sound/` (hand-written diagrams that
must NOT be flagged).

Each one exists to make **one named property** fail, and the self-test asserts
that specific property rather than accepting any failure — a typo'd id would
make almost any file unsound and would otherwise look like proof. The mapping
lives in `EXERCISES` in the self-test, which refuses to pass on a fixture that
is not listed there **and** on an `EXERCISES` entry whose fixture has gone
missing, so the properties cannot silently drift out of coverage in either
direction.

| file                                            | property it exercises   | the defect                                   | provenance                     |
| ----------------------------------------------- | ----------------------- | -------------------------------------------- | ------------------------------ |
| `historical-handover-edge-counted-join.bpmn`    | **S2** no deadlock      | join starves behind lapse timers             | **real pre-fix exporter output** |
| `deadlock-boundary-in-rand.bpmn`                | **S2** no deadlock      | join starves behind an interrupting boundary | hand-written                   |
| `deadlock-ror-in-rand.bpmn`                     | **S2** no deadlock      | join starves behind an `ROR`                 | hand-written                   |
| `unsafe-xor-join-after-rand.bpmn`               | **S4** safe (1-bounded) | XOR gateway used to merge a `RAND`           | hand-written                   |

**Today's exporter cannot emit any of these shapes** — declining to is exactly
the fix that `addJoin` in `jl4-core/src/L4/Bpmn/Lower.hs` implements. Three of
the four are hand-written and must never be treated as goldens. The first is
different, and is the reason to believe the rest.

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

## The three hand-written ones

The two deadlock fixtures are reconstructions of the same class of defect, built
to the description `addJoin` gives of the code it replaced:

> An earlier version counted rewired edges and required two or more, which
> passes happily for a branch containing an interrupting boundary event
> (`cancelActivity="true"` makes its two arms mutually exclusive: two edges, one
> token), a `ROR` (an exclusive gateway: n edges, one token), or a lapse timer
> (same shape again). Each of those emits a join that waits forever for a token
> nothing will ever send.

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
all: the check the repo already had passes **all four** files at zero warnings.

```sh
npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs jl4/examples/bpmn/unsound/*.bpmn
node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/unsound/*.bpmn
etc/check-bpmn-kie.sh jl4/examples/bpmn/unsound/*.bpmn
```

| Checker                                               | `historical-handover`   | `boundary-in-rand`      | `ror-in-rand`           | `unsafe-xor-join`     |
| ----------------------------------------------------- | ----------------------- | ----------------------- | ----------------------- | --------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser)        | **OK, 0 warnings**      | **OK, 0 warnings**      | **OK, 0 warnings**      | **OK, 0 warnings**    |
| `bpmnlint` (Camunda's linter)                          | not run                 | **0 findings**\*        | **0 findings**\*        | not run               |
| `pm4py` + Woflan (Petri-net soundness)                 | not run                 | **reports SOUND**       | reports unsound         | not run               |
| `etc/check-bpmn-soundness.mjs`                         | UNSOUND, S1+S2+S3 fail  | UNSOUND, S1+S2+S3 fail  | UNSOUND, S1+S2+S3 fail  | UNSOUND, **S4** fails |
| jBPM 7.74.1 **compile** (`check-bpmn-kie.sh` phase 1)  | **rejected** (axis A4)  | passes, 0 errors\*\*    | passes, 0 errors\*\*    | passes, 0 errors      |
| jBPM 7.74.1 **execute** (phase 2)                      | never reached           | **DEADLOCK**, token parked at `Join` | **DEADLOCK**, token parked at `Join` | **DUPLICATION**, `Fulfilled` fired 2x |

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
2. **The single explored path is chosen by our own code.** Because the exporter
   emits no branch guards at all (A3), the harness supplies them, and every
   multi-way exclusive gateway takes its **first outgoing flow in document
   order**. That interleaving is an artifact, not a representative run.
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
