# Deliberately unsound BPMN

Three diagrams that are **wrong in a way no parser can see**, kept so that
`etc/check-bpmn-soundness.mjs` can be shown to fail. They are the negative half
of `etc/check-bpmn-soundness.selftest.mjs`; the positive half is
`../expected/`.

Each one exists to make **one named property** fail, and the self-test asserts
that specific property rather than accepting any failure — a typo'd id would
make almost any file unsound and would otherwise look like proof. The mapping
lives in `EXERCISES` in the self-test, which also refuses to pass on a fixture
that is not listed there, so the properties cannot silently drift out of
coverage.

| file                              | property it exercises  | the defect                                    |
| --------------------------------- | ---------------------- | --------------------------------------------- |
| `deadlock-boundary-in-rand.bpmn`  | **S2** no deadlock     | join starves behind an interrupting boundary   |
| `deadlock-ror-in-rand.bpmn`       | **S2** no deadlock     | join starves behind an `ROR`                   |
| `unsafe-xor-join-after-rand.bpmn` | **S4** safe (1-bounded)| XOR gateway used to merge a `RAND`             |

They are not exporter output and must never be treated as goldens. **Today's
exporter cannot emit any of these shapes** — declining to is exactly the fix
that `addJoin` in `jl4-core/src/L4/Bpmn/Lower.hs` implements. The first two are
hand-written reconstructions of what the exporter emitted *before* that fix,
built to the description `addJoin` gives of the code it replaced:

> An earlier version counted rewired edges and required two or more, which
> passes happily for a branch containing an interrupting boundary event
> (`cancelActivity="true"` makes its two arms mutually exclusive: two edges, one
> token), a `ROR` (an exclusive gateway: n edges, one token), or a lapse timer
> (same shape again). Each of those emits a join that waits forever for a token
> nothing will ever send.

One file per shape named in that paragraph. All three are
`../expected/consultation.bpmn` — the one fixture that legitimately draws a
converging parallel gateway — with a single change made to it.

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
all: the check the repo already had passes all three files at zero warnings.

```sh
npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs jl4/examples/bpmn/unsound/*.bpmn
node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/unsound/*.bpmn
etc/check-bpmn-kie.sh jl4/examples/bpmn/unsound/*.bpmn
```

| Checker                                        | `boundary-in-rand`    | `ror-in-rand`         | `unsafe-xor-join`     |
| ---------------------------------------------- | --------------------- | --------------------- | --------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser) | **OK, 0 warnings**    | **OK, 0 warnings**    | **OK, 0 warnings**    |
| `bpmnlint` (Camunda's linter)                   | **0 findings**\*      | **0 findings**\*      | not run               |
| `pm4py` + Woflan (Petri-net soundness)          | **reports SOUND**     | reports unsound       | not run               |
| `etc/check-bpmn-soundness.mjs`                  | UNSOUND, S1+S2+S3 fail | UNSOUND, S1+S2+S3 fail | UNSOUND, **S4** fails |
| jBPM 7.74.1 **compile** (`check-bpmn-kie.sh` phase 1) | passes, 0 errors\*\* | passes, 0 errors\*\* | passes, 0 errors      |
| jBPM 7.74.1 **execute** (phase 2)               | **DEADLOCK**, token parked at `Join` | **DEADLOCK**, token parked at `Join` | **DUPLICATION**, `Fulfilled` fired 2x |

\*\* only after the harness supplies the bindings jBPM demands — a
`timeDuration` on the timer, a `conditionExpression` on the unguarded `ROR`.
Without them jBPM rejects both files during compilation, **for reasons that have
nothing to do with the deadlock**, and never reaches the execution that finds
it. That is the single most important measurement here: a KIE gate that only
compiled would have caught none of these three, and would have *looked* like it
was working while doing so.

The `unsafe-xor-join` row is the one where the two engines part company on their
own terms. jBPM reports COMPLETED — reaching an end state is all its process
instance state can express — and the duplication is only visible because the
harness additionally counts how many times each node fires. A checker that asked
jBPM the obvious question would have missed it.

\* after adding the optional `<bpmn:incoming>`/`<bpmn:outgoing>`
back-references the exporter omits; without them bpmnlint calls every node in
every fixture disconnected, including the sound ones. See "the
`incoming`/`outgoing` flavor axis" in `../README.md`.

Woflan reporting the first file **sound** is the sharpest reason not to reach
for the off-the-shelf tool: `pm4py`'s BPMN importer drops boundary events
entirely, so it deletes the construct that causes the deadlock and then
pronounces what is left healthy. Its verdict on the second file is "some places
are not covered by an s-component" — the same words it produces for the
*correct* `offering.bpmn`, so the verdict does not distinguish a deadlock from a
`RAND` the exporter deliberately left unjoined.

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

The disagreements are informative in the same way, and neither is a defect in
the diagrams:

- **jBPM cannot check `../expected/handover.bpmn` at all** (axis A4 in
  `../README.md`): the conditional boundary event's body is L4 source text
  declared as a formal expression, so Drools tries to parse `` `grace period` ``
  as DRL and rejects the file. Our checker never looks inside an expression, so
  it is untroubled.
- **jBPM misses `unsafe-xor-join-after-rand.bpmn` on its own terms**, as noted
  above. Exhaustive marking exploration catches it directly; a single execution
  does not.

Which is the honest summary of the whole exercise: the soundness check is the
gate because it is exhaustive, portable and needs nothing installed, and the
engine is the corroboration because it is independent. Neither one subsumes the
other.
