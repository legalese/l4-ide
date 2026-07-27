# BPMN export fixtures

Golden inputs for the BPMN 2.0 exporter (`L4.Bpmn.IR` / `L4.Bpmn.Lower` /
`L4.Bpmn.Emit`), exercised by `jl4/tests/BpmnExport.hs`.

The exporter runs over the **regulative** layer only — `PARTY p MUST a WITHIN d
HENCE … LEST …`, extracted to a state graph by `L4.StateGraph`. That layer
genuinely _is_ a transition system, so drawing it as one says nothing the source
did not. Predicates are a different matter, and belong to the ladder; see
`doc/concepts/language-design/logic-not-flowcharts.md`.

| Fixture           | Covers                                                                                                                                       |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `offering.l4`     | Three parties, a four-way `RAND` (concurrent obligations with different bearers), two `SHANT`s, timer boundary events, a breach terminal      |
| `handover.l4`     | A deadline that is a _name_ (no timer, no invented duration), a `RAND` and a `ROR`, and permissions whose deadlines are drawn as lapse timers |
| `consultation.l4` | The only one that draws a converging parallel gateway: a `RAND` of deadline-free permissions, one branch of which is a chain                  |
| `../legal/regcf/regcf.l4` | The real 981-line Reg CF corpus — **three** rules, so three golden pairs (`regcf-reporting`, `regcf-advertising`, `regcf-resale`): a renewing obligation drawn as a loop, `IF`-headed duties with guarded gateway arms, named deadlines, two prohibitions. Read from `examples/legal/`, not copied here — see below |

## The Reg CF goldens are cut from the corpus itself

The three `regcf-*` golden pairs are exported from
`jl4/examples/legal/regcf/regcf.l4` — the real 981-line formalisation of 17 CFR
Part 227 — not from a fixture beside it:

```
$ l4 export jl4/examples/legal/regcf/regcf.l4 --to bpmn \
     --rule "ongoing reporting obligation" --fidelity-report
```

Until 2026-07-27 that command failed with "No regulative rules found in module",
because `L4.StateGraph.findRegulativeExpr` descended through `Where` and `LetIn`
but not `IfThenElse`, and all three of the corpus's duties are `IF`-headed — the
CFR writes its guard outside the duty ("**unless** such securities are
transferred: …"). A hand-written `regcf.l4` lived here as the workaround, with the
guard hoisted into `PROVIDED` and the reporting spine rewritten as a `ROR`.

**That file is deleted.** It was a second source, and it had drifted from the
corpus on its first commit: it re-declared three deadline constants, renamed four
predicates, dropped the statutory chapeau, invented two `LEST` breach clauses the
CFR does not contain, and — because a `ROR` arm needs an obligation to hang a
`PROVIDED` on — silently dropped the annual cycle's base case, so the shipped
diagram asserted a duty the corpus discharges. Citation is not a drift control;
projection is.

Three things the extractor learned in the process, all visible in the goldens:

- **`IF`/`ELSE` over regulative arms is a guarded `OneOf` junction.**
  `guardedIfBranches` peels the chain, conjoining each arm's condition with the
  negation of every condition above it, so the branch set stays exhaustive and
  mutually exclusive by construction. `regcf-reporting.bpmn` has **three** arms,
  including the one that imposes no duty at all.
- **A `HENCE` back into the rule being extracted is a loop.** It is an `App` with
  arguments, which used to fall through to "unknown target" and produce a dead-end
  state named `next`; `P-CYCLE` could not fire because there was no cycle in the
  graph to detect. `TargetSelf` now edges back to the initial state, and `P-CYCLE`
  fires.
- **A junction's branch edges carry their guards.** `Lower.hs`'s `branches` passed
  `Nothing`, so an exclusive gateway drew a free choice and the condition landed on
  the flow *out of the task* — the diagram read "pick an arm, do the work, then test
  what decided it". The guards are now `conditionExpression`s on the branch flows,
  and the new `P-BRANCHGUARD` note records what BPMN still cannot say about them:
  that they exhaust the cases and cannot overlap.

## What can be joined, and why so little of it

`consultation.l4` exists because the other two decline, for two different and
correct reasons — and without a positive case, a regression that stopped this
exporter drawing joins **at all** would leave every golden byte-identical.

Two independent conditions have to hold before a converging parallel gateway is
drawn, and between them they rule out most of what anyone would actually write.
The full enumeration is `"the boundary of what can be joined"` in
`BpmnExport.hs`; the summary is:

- **Every branch must stop at the same single state.** L4 gives every `MUST` a
  `LEST` to `BREACH` whether the drafter writes one or not, so **an obligation
  branch never joins** — it stops in two places and its siblings do not share
  the second. This is why `offering.l4` gets a split and no join.
- **Every branch must arrive exactly once, unconditionally.** A `WITHIN` on a
  permission becomes a lapse timer, which is a second and mutually exclusive
  arrival; an explicit `LEST` that rejoins the happy path is another; a
  `PROVIDED` guard makes the arrival conditional, which on an incoming flow of a
  parallel gateway is a spec violation outright. This is why `handover.l4` gets
  a split and no join.

So in practice **a joinable `RAND` is a `RAND` of deadline-free permissions**,
and any regulative model with deadlines in it — which is to say any realistic
one — is drawn as a fork without a join, with `P-NOJOIN` saying so. That is a
real limitation of what this exporter draws today and it is stated here rather
than left for a reader to infer from two goldens that both decline. Whether it
can be relaxed is an open question recorded in the PR, not a settled one.

## From the CLI

Track **S0** is wired, and "exactly as `l4` would write it" below is now literal
rather than aspirational — both goldens for each fixture are reproducible
byte-for-byte through `l4 export`, from a repo checkout with `jl4/` as the working
directory:

```sh
l4 export --to=bpmn offering.l4 -o /tmp/offering.bpmn --fidelity-report
diff /tmp/offering.bpmn          expected/offering.bpmn
diff /tmp/offering.fidelity.txt  expected/offering.fidelity.txt

# the Reg CF trio, from the corpus in examples/legal/ rather than from here
l4 export ../legal/regcf/regcf.l4 --to bpmn --rule "ongoing reporting obligation" \
   -o /tmp/regcf-reporting.bpmn --fidelity-report
diff /tmp/regcf-reporting.bpmn         expected/regcf-reporting.bpmn
diff /tmp/regcf-reporting.fidelity.txt expected/regcf-reporting.fidelity.txt
```

Without `-o` the XML goes to stdout and the report to stderr, so a redirected
document stays a document. A one-line tally of the losses goes to stderr whether or
not `--fidelity-report` was passed.

Two flags are specific to this side:

- `--rule NAME` picks which regulative rule to draw. A BPMN document holds exactly
  one process and `renderBpmn` writes its own XML prolog, so a file with more than
  one rule is refused rather than concatenated; the refusal names the candidates.
- `--deadline-unit=days|refuse` is the `DeadlineUnitPolicy` knob. `days` (the
  default) reads a bare `WITHIN 30` as `P30D` and records `P-DEADLINE-UNIT`;
  `refuse` emits no timer at all and records `P-DEADLINE`.

Each fixture produces two goldens under `expected/`:

- `<name>.bpmn` — the XML, exactly as `l4` would write it. Openable in Camunda
  Modeler as-is.
- `<name>.fidelity.txt` — what BPMN could not carry, naming the specific element
  that lost it. The report type is `L4.Interchange.Fidelity`, shared with every
  other interchange backend so the CLI has one shape to render rather than one
  per target. Codes `F1`–`F5` are losses of the notation and cannot be fixed by
  writing more Haskell; codes `P-…` are this exporter's own doing — an
  approximation it made (`P-DEADLINE-UNIT`), a gateway it declined to invent
  (`P-NOJOIN`), a guard it could only write as opaque text (`P-BRANCHGUARD`), or a
  shape the `StateGraph` types permit that BPMN has no honest drawing for at all
  (`P-MULTI-HENCE`, `P-JUNCTION-OBLIGATION`, `P-CYCLE`).
  (DMN uses `D-…`, so a combined report never confuses the two.)

## Checking the XML is really importable

`bpmn-moddle` is the library `bpmn-js`, and therefore Camunda Modeler, reads
BPMN with. Nothing is added to `package.json`:

```sh
npx --yes --package=bpmn-moddle@10 node etc/validate-bpmn.mjs \
  jl4/examples/bpmn/expected/offering.bpmn \
  jl4/examples/bpmn/expected/handover.bpmn \
  jl4/examples/bpmn/expected/consultation.bpmn
```

It reports parse errors, moddle warnings, unresolved references, boundary events
without a trigger, and any flow node or sequence flow missing its diagram
interchange. All three fixtures parse with zero warnings.

**It is not evidence that the diagram is right, and must never be cited as
such.** It checks well-formedness, and well-formedness is exactly what a wrong
diagram has: it passed an inverted prohibition, a converging gateway that
deadlocked, four dropped `WITHIN` windows, and twelve edges drawn straight
through unrelated nodes, all at zero warnings, while the Haskell suite was green
at 1581 examples. Run it to catch a regression in the XML; read
`BpmnExport.hs` for whether the XML says what the rule says.

## How the defects in here were actually found

Worth recording, because the two methods are different and neither would have
found the other's.

Six defects came from an **adversarial review**: running the exporter on inputs
nobody had tried — an interrupting boundary inside a `RAND` branch, a `PROVIDED`
guard on a joined branch — and doing arithmetic on the emitted coordinates
rather than looking at the picture. That is how the inverted prohibition, the
deadlocking join, the dropped `WITHIN` windows and the crossing geometry
surfaced.

Three more came from **reading the fixes' own diff and asking what each did not
cover**: `raceArms` settled where a prohibition's arms go but not what the
boundary is *called*; the lapse timers of one fix silently invalidated a
fixture's stated purpose in another; and the channel offsets stopped separating
flows past the point where they fit in the gutter. None of the three is
reachable from the inputs the review tried.

The common thread, and the reason both methods were needed: **every defect
produced plausible, well-formed, green output.** None of them looked like a bug
from anywhere except a test that asked what the diagram *means*.

One note was also **removed** rather than fixed. `P-JOIN-FOLDED` said a join had
been folded into an enclosing gateway and nothing was lost. It made sense under
the edge-counting join it was written for, and cannot fire under the token proof
that replaced it: folding needs an enclosing junction to have drawn its join
while sharing this one's join target, and sharing the target is exactly what
gives the enclosing branch two arrivals and makes its own proof fail first. See
`addJoin` in `Lower.hs` for the argument in full. A failed proof now has one
outcome, `P-NOJOIN` at `Lossy`, which is safe whether or not anything was really
lost.

## Regenerating

Delete the golden and re-run the suite twice (the first run writes it and fails
by design, the second confirms it is stable):

```sh
rm jl4/examples/bpmn/expected/offering.bpmn
cabal test jl4:jl4-test --test-options='--match "bpmn export"'
```
