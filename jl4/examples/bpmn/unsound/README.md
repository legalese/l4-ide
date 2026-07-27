# Deliberately unsound BPMN

Two diagrams that **cannot ever finish**, kept so that
`etc/check-bpmn-soundness.mjs` can be shown to fail. They are the negative half
of `etc/check-bpmn-soundness.selftest.mjs`; the positive half is
`../expected/`.

They are not exporter output and must never be treated as goldens. **Today's
exporter cannot emit either shape** — declining to is exactly the fix that
`addJoin` in `jl4-core/src/L4/Bpmn/Lower.hs` implements. They are hand-written
reconstructions of what the exporter emitted *before* that fix, built to the
description `addJoin` gives of the code it replaced:

> An earlier version counted rewired edges and required two or more, which
> passes happily for a branch containing an interrupting boundary event
> (`cancelActivity="true"` makes its two arms mutually exclusive: two edges, one
> token), a `ROR` (an exclusive gateway: n edges, one token), or a lapse timer
> (same shape again). Each of those emits a join that waits forever for a token
> nothing will ever send.

One file per shape named in that paragraph. Both are `../expected/consultation.bpmn`
— the one fixture that legitimately draws a converging parallel gateway — with a
single construct added inside one branch of its `RAND`.

| File                            | The added construct                                                                        | Why the join starves                                                       |
| ------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `deadlock-boundary-in-rand.bpmn` | interrupting boundary `Lapse_2` on `Task_2`, its arm rewired to `Join_0` alongside `Task_2`'s | `Join_0` has three incoming flows; `Task_2` and `Lapse_2` are mutually exclusive, so two tokens arrive |
| `deadlock-ror-in-rand.bpmn`      | exclusive gateway `Split_5` in one branch, both its arms rewired to `Join_0`                 | `Join_0` has three incoming flows; the `ROR` delivers one token down one arm, so two tokens arrive |

## What each checker says about them

Run from the repo root. This is the evidence for adding a soundness check at
all: the check the repo already had passes both files at zero warnings.

```sh
npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs jl4/examples/bpmn/unsound/*.bpmn
node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/unsound/*.bpmn
```

| Checker                                        | `boundary-in-rand`    | `ror-in-rand`         |
| ---------------------------------------------- | --------------------- | --------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle, a parser) | **OK, 0 warnings**    | **OK, 0 warnings**    |
| `bpmnlint` (Camunda's linter)                   | **0 findings**\*      | **0 findings**\*      |
| `pm4py` + Woflan (Petri-net soundness)          | **reports SOUND**     | reports unsound       |
| `etc/check-bpmn-soundness.mjs`                  | UNSOUND, S1+S2+S3 fail | UNSOUND, S1+S2+S3 fail |

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
