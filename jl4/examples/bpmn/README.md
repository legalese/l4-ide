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

Three directories of `.bpmn`, read by `etc/check-bpmn-soundness.selftest.mjs`:

| directory   | what it holds                    | required verdict                             |
| ----------- | -------------------------------- | -------------------------------------------- |
| `expected/` | exporter goldens, reproducible byte-for-byte by `l4 export` | SOUND       |
| `sound/`    | hand-written diagrams the gate must **not** flag            | SOUND       |
| `unsound/`  | hand-written and historical diagrams the gate **must** catch | UNSOUND, on a named property |

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
  (`P-NOJOIN`), or a shape the `StateGraph` types permit that BPMN has no honest
  drawing for at all (`P-MULTI-HENCE`, `P-JUNCTION-OBLIGATION`, `P-CYCLE`).
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

## Checking the diagram can actually finish

A parser cannot see a process that never completes, so there is a second and
independent check that plays the token game instead of reading the tags. Zero
install, zero dependencies, no network:

```sh
node etc/check-bpmn-soundness.mjs jl4/examples/bpmn/expected/*.bpmn
node etc/check-bpmn-soundness.selftest.mjs   # asserts both directions
```

It translates the process to a workflow net — places are sequence flows, plus
one "this activity is running" place per activity carrying a boundary event —
and explores every reachable marking. Four properties, in van der Aalst's
vocabulary: **S1** option to complete, **S2** no deadlock, **S3** no dead flow
node, **S4** safe. All three fixtures pass all four.

Two things it deliberately does not do. It does not use `bpmn-moddle`, so a
disagreement with `validate-bpmn.mjs` about what the graph even is shows up
rather than being inherited. And it does not demand *proper completion* in the
WF-net sense of one token in one sink: BPMN completes when every token has been
consumed, several end events may each consume one, and the fork-without-join
that `P-NOJOIN` describes is precisely that shape. Peak concurrent tokens is
reported as information instead — `offering.bpmn` peaks at four, by design.

S1 and S2 are the properties the deadlocking join violated, and
`unsound/` holds two reconstructions of that shape to prove the check fires on
it. `validate-bpmn.mjs` passes both at zero warnings; this one fails both with a
witness trace naming the flow whose token never arrives.

### The `incoming`/`outgoing` flavor axis

The exporter writes connectivity only as `sourceRef`/`targetRef` on
`<bpmn:sequenceFlow>`, and omits the optional `<bpmn:incoming>` /
`<bpmn:outgoing>` back-references BPMN also allows on a flow node. Both are
legal; the elements are `minOccurs="0"` in the XSD, and `bpmn-js` derives the
connections from the refs, which is why Camunda Modeler renders the fixtures
correctly and why K4 holds.

Not every consumer derives them. **`bpmnlint`, Camunda's own linter, reads the
back-references only**, and without them reports every node in every fixture —
including the sound ones — as `no-disconnected`, `no-implicit-start` and
`no-implicit-end`: 65 findings across three good files. Adding the
back-references drops that to 3, all of them `label-required` on the unnamed
start event.

So this is a fidelity note about the emitted XML rather than a defect in it, and
the fix is small if it is ever wanted. Recorded here for the same reason the DMN
flavor axis is recorded: a construct one conforming tool accepts and another
rejects is a property of the interchange, not of either tool.

(`bpmnlint` finds nothing else on the fixtures, and — once the noise is removed
— nothing at all on either deadlocking diagram. A linter is not an engine
either.)

## Asking an actual engine: the jBPM/KIE second opinion

Both checks above are ours. `etc/check-bpmn-kie.sh` runs somebody else's — jBPM
7.74.1.Final, a genuinely independent implementation that shares no code with
`bpmn-js` — and it **executes** the process rather than reading it.

```sh
etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn
```

It needs `mvn` and a JDK 11+, downloads ~44 MB of pinned jars into a cache
outside the repo on first run, and **exits 3 with a loud banner when that
toolchain is absent** — never a silent pass. Nothing is added to `package.json`
or the lockfile, and the Maven plugin is pinned as well as the dependencies.

"Absent toolchain" and "broken harness" are deliberately **different exit
codes**, because they have different owners and only one of them is ever
tolerable: 3 is absent (and `--allow-skip` turns it into 0), 4 is broken, and
`--allow-skip` does **not** silence a 4. A typo in the pinned pom, a compile
error in `etc/kie/KieBpmnCheck.java`, and a JVM that dies before printing a
verdict all exit 4. The verdict line itself is the sentinel: exit 1 is only
trusted if the checker actually printed a `RESULT:`, because an
`UnsupportedClassVersionError` also exits 1 and would otherwise be reported as a
defect in a diagram.

**It is not the gate, and it is not a replacement for either check above.**
Work items auto-complete, so it explores exactly one interleaving: it can prove
a deadlock exists but can never prove one absent. `check-bpmn-soundness.mjs`
exhausts every reachable marking, which is why that one is the gate. What KIE
adds is corroboration — when a foreign engine independently parks a token at the
same join our token game names, that is evidence our hand-written semantics are
right.

How much exporter output it actually exercises is worth measuring rather than
assuming, and the answer is: not much. Across the three goldens there is exactly
**one** `exclusiveGateway` (in `handover.bpmn`) and **zero**
`conditionExpression`s and **zero** `default` flows anywhere — so branching has
never been exercised on exporter output at all, and the single fixture that has a
real branch is the one jBPM rejects. Most of what the engine confirms, it
confirms on files written by hand for this purpose.

### It agrees, everywhere it can run

| fixture                                       | `validate-bpmn.mjs` | `check-bpmn-soundness.mjs` | jBPM execution                       |
| --------------------------------------------- | ------------------- | -------------------------- | ------------------------------------ |
| `consultation.bpmn`                           | OK, 0 warnings      | SOUND                      | COMPLETED                            |
| `offering.bpmn`                               | OK, 0 warnings      | SOUND                      | ABORTED via error end event `Breach` |
| `handover.bpmn`                               | OK, 0 warnings      | SOUND                      | **rejected, see A4**                 |
| `sound/joined-beside-breach.bpmn`             | OK, 0 warnings      | SOUND                      | COMPLETED                            |
| `unsound/historical-handover-edge-counted-join.bpmn` | OK, 0 warnings | UNSOUND (S2)           | **rejected, see A4**                 |
| `unsound/deadlock-boundary-in-rand.bpmn`      | OK, 0 warnings      | UNSOUND (S2)               | **DEADLOCK, token parked at `Join`** |
| `unsound/deadlock-ror-in-rand.bpmn`           | OK, 0 warnings      | UNSOUND (S2)               | **DEADLOCK, token parked at `Join`** |
| `unsound/unsafe-xor-join-after-rand.bpmn`     | OK, 0 warnings      | UNSOUND (S4)               | **DUPLICATION, `Fulfilled` fired 2x** |

Agreement on all six files jBPM can compile, in both directions — with the
`unsafe-xor-join` row carrying a caveat, because DUPLICATION is our firing-count
heuristic layered on top of jBPM rather than jBPM's own verdict (which is
COMPLETED). See `unsound/README.md`.

**The load-bearing detail: jBPM's _compile_ phase caught none of the defects.**
Once the missing guard below was supplied it passed all three compilable
fixtures at zero errors, and only execution found anything. A KIE gate that
merely compiled would have been parse-level agreement — nearly free, and worth
nearly nothing. That is why this harness runs the process.

**And the sharpest limit, stated plainly: the one fixture that is _real_ pre-fix
exporter output is one jBPM cannot read.** `historical-handover-edge-counted-join.bpmn`
is what the exporter actually emitted before `addJoin` was fixed, and it
genuinely deadlocks; jBPM rejects it at compile time for axis A4, an unrelated
expression-language problem. The soundness checker caught it. The engine could
not be asked. Two hand-written reconstructions of the *same class* of defect are
what jBPM does confirm.

An earlier version of this table said "full agreement in both directions". That
was overstated in two ways worth keeping on the record: `offering.bpmn` was
producing a spurious DUPLICATION finding whose appearance depended on how many
other files were on the command line (the firing census was keyed on node
**name**, and adaptation A2 clones end events while keeping their names — so two
distinct nodes firing once each were counted as one node firing twice); and the
two tools' agreement on `offering.bpmn` was over different behaviours, since the
soundness checker modelled its error end event as an ordinary sink while jBPM
terminated the instance. Both are fixed; the second is described under
`sound/joined-beside-breach.bpmn`.

### Flavor axes, recorded the way the DMN axis is

Every adaptation the harness applies is printed. **Not every printed line is a
flavor axis**, and an earlier version of this section said otherwise; the
printed labels now say which is which. A0, A1, A2 and A6 are engine-vs-modeller
differences and are **not** defects:

- **A0 `isExecutable="false"` → `true`.** Deliberate in the exporter (see
  `L4/Bpmn/Emit.hs`) so Camunda will not apply executable-process validation to
  a picture. Flipped in memory only; flipping it in the exporter would rewrite
  three goldens.
- **A1 abstract `<bpmn:task>` → `<bpmn:userTask>`.** jBPM needs an
  implementation binding; Camunda and `bpmn-moddle` accept the abstract form.
- **A2 end event with more than one incoming flow.** Spec-legal implicit merge,
  accepted by Camunda; jBPM's `EndNode`/`FaultNode` both reject it. Splitting it
  into N single-incoming copies is exactly equivalent, since each arriving token
  ends independently. This is the one **structural** rewrite the harness makes,
  and it is why "jBPM checks the emitted file" is not quite true: jBPM checks a
  document this harness produced from it.
- **A6 gateway with no `gatewayDirection`.** BPMN 2.0 makes the attribute
  optional and defaults it to `Unspecified`; Camunda accepts its absence; jBPM
  refuses outright with `Unknown gateway direction: null`. A genuine flavor axis
  that **exporter output never reaches**, since every emitted gateway sets it —
  so in practice this only ever fires on a hand-written file.

A5 is neither, and used to be filed with the gaps below by mistake:

- **A5 timer event definition with no `timeDuration`/`timeCycle`/`timeDate`.**
  Purely defensive. The exporter emits a body on **every** timer event
  definition, so this fires zero times across every fixture in this repository;
  the only file that ever triggered it was a hand-written one that has since been
  given the shape the exporter really emits. A binding the exporter never omits
  is not a gap in the exporter, and not a disagreement between tools either.

The remaining two are **real gaps in the emitted XML**, not tool disagreements:

- **A3 — a diverging `exclusiveGateway` with no guard at all.**
  `grep -c conditionExpression` over every fixture returns 0, and none sets
  `default` either. `ROR` ("one of") emits a bare XOR split, so **no** engine can
  decide the branch — this is not something Camunda accepts and jBPM rejects, it
  is something nothing can execute. This is precisely the **F4 seam**: those
  guards are what a referenced DMN decision would supply. The harness injects a
  deterministic stand-in purely so execution can proceed — **which means the
  single path jBPM explores is chosen by our own adaptation**, not by the file:
  every multi-way exclusive gateway takes its first outgoing flow in document
  order. Do not read the explored interleaving as representative.
- **A4 — `handover.bpmn`'s conditional boundary event is L4 source text labelled
  as a formal expression.** The body is
  `<bpmn:condition xsi:type="bpmn:tFormalExpression">` `` `grace period` ``
  `</bpmn:condition>` — a backticked L4 name, with no `language` attribute and no
  `expressionLanguage` on `<definitions>`. So the file asserts this is a formal
  expression in the default language while it is in fact an identifier. Camunda
  Modeler renders it happily; Drools takes the claim at face value, tries to
  parse it as DRL, and rejects the whole file with an ANTLR error. **This is the
  one fixture no engine can run**, and it is a fidelity defect rather than a
  flavor axis: the honest emission would set `language` to something naming L4,
  or drop the `tFormalExpression` type.

Also seen and deliberately ignored: non-fatal XSD chatter on stderr about
`bpmn:tFormalExpression` for `timeDuration`, which does not stop compilation.

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
