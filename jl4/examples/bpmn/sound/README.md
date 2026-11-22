# Deliberately sound BPMN

Diagrams that **must not be flagged**. They are the third pile the
self-test reads, alongside `../expected/` (exporter goldens, also required to be
sound) and `../unsound/` (required to be caught).

A gate is not only wrong when it misses a defect. It is also wrong when it
invents one, and that direction is much easier to ship: a checker that reports
UNSOUND looks like it is working. Nothing in `../expected/` covered it, because
the goldens only exercise shapes today's exporter actually emits — so a false
positive on a shape the exporter is *about* to emit would have gone unnoticed
until it blocked the change that introduced it.

| file                        | what it pins                                                     |
| --------------------------- | ---------------------------------------------------------------- |
| `joined-beside-breach.bpmn` | an error end event **terminates the instance**, discarding every remaining token |
| `mi-subprocess-fork.bpmn` | a multi-instance sub-process is **played by copy-expansion**, and its escalation fan-in is the one place copies are not independent |
| `terminate-upstream-of-split.bpmn` | that a run-stopping end event **upstream of a split discards nothing**, so the declaration rule must stay silent on it — see below |
| `mi-subprocess-two-ways-to-done.bpmn` | an instance is finished by **whichever** of its paths reaches an end, not by all of them |
| `mi-subprocess-throw-and-finish.bpmn` | an instance that **throws** is also **finished** — the escalation leaves, and the instance has no tokens left |
| `mi-subprocess-every-instance-throws.bpmn` | the same, in its strongest form — EVERY instance throws and the scope still completes; the one fixture with a **measured engine** answer |

## The declaration rule, and what these fixtures say about it

`etc/check-bpmn-soundness.mjs` gained a third class of finding on 2026-09-21: an
end event that stops the whole run and measurably throws away a token something
else was still holding must be declared in the fidelity report beside the file, or
the check FAILS. The rule is written up in `../README.md` under "A terminating end
beside concurrency owes a declaration".

**One fixture here is about the rule NOT firing.**
`terminate-upstream-of-split.bpmn` is a run-stopping error end whose only feeder is
a boundary event on the task BEFORE the split, so it can only ever fire while it
holds the last token in flight. The net peaks at two tokens, so the rule's first
version — which read peak concurrency — failed it, and nothing an author could
write would have fixed that: the exporter writes no `P-NOJOIN` when the join was
drawn, and there was no loss to declare anyway. Unlike its neighbours this file is
captured `l4 export` output rather than hand-written, because that is the
load-bearing half of the claim; the source it came from is quoted below. Its real
`.fidelity.txt` sidecar is checked in beside it, deliberately: the rule only reads
sidecars, so a file without one CANNOT BE JUDGED and would prove nothing.

**Two fixtures here really do discard siblings, and each carries a HAND-WRITTEN
sidecar that declares it.** `joined-beside-breach.bpmn` (1 token discarded) and
`mi-subprocess-fork.bpmn` (3 at two instances) are exactly the rule's shape — they
exist to pin the terminate reading, so of course they are. Being hand-written they
have no `.l4` source to run `l4 export --fidelity-report` over, so their
`.fidelity.txt` files were written by hand, in the format
`L4.Interchange.Fidelity.renderNote` emits. Each says so on its first lines.

**That is a correction, not a decoration.** Until 2026-09-21 both files had no
sidecar at all and so were CANNOT-JUDGE — the rule reads sidecars only, and a file
without one is not evaluated. They passed for that reason, which set a trap: adding
a sidecar is the obvious thing a later session does to bring this directory under
the rule, and doing it would have turned the self-test red. Now they pass because
the loss is declared, and there is nothing left here that a sidecar would break.

**The pair also covers both accepted elements**, which is the other reason to have
written them by hand rather than deleting the files:

| fixture | filed on | why that element |
| ------- | -------- | ---------------- |
| `joined-beside-breach.bpmn` | `Split_0` | the junction that made the two branches concurrent accounts for the whole loss |
| `mi-subprocess-fork.bpmn` | `End_3` | the junction is the scope's own multiplicity, so what is thrown away is another member's run — and no element in a BPMN file names one |

Each of the two also carries a `<bpmn:documentation>` on its breach end saying what
reaching it does, and that text is for a reader who opens the diagram in Camunda
Modeler and clicks the end event. **Nothing mechanical reads it.** It was briefly a
second channel of the rule, and that channel was removed on the day it was
reviewed: the exporter puts a COUNTERFACTUAL about error ends on exactly that
element, which the rule then accepted as a declaration. See
`../unsound/refork-counterfactual-documentation.bpmn`. Both files parse at **0
warnings** under `etc/validate-bpmn.mjs`, measured 2026-09-21 after the edit.

`mi-subprocess-fork.bpmn` needs one more sentence, and its sidecar carries it. Its
top-level error end is the **pre-`fcd7ecb2c`** shape, the one that cancelled the
members who had not breached, and the exporter stopped emitting it. **So why is the
defect shape in `sound/`?** Because the FIDELITY rule is not about the shape: a
diagram may throw sibling work away, and what it may not do is throw it away in
silence. Declared, the shape is sound — and this fixture's job is to pin how the
checker plays a multi-instance scope, which is a different question from how the
exporter draws one. The undeclared version of the same shape is red twice over, at
`../unsound/historical-fork-undeclared-sibling-loss.bpmn` and
`../unsound/refork-beside-party-cross-instance.bpmn`.

## `terminate-upstream-of-split.bpmn`

One ordinary obligation, then `consultation.l4`'s joinable `RAND` — the suite's
only positive join case — placed after it. `End_6 "Breach"` is an error end and so
terminates the instance; its only incoming flow comes from `Boundary_0`, attached
to `Task_0`, strictly upstream of `Split_1`.

Captured on 2026-09-21 from this source, with `JL4_LIBRARY_PATH` pointed at
`jl4-core/libraries`:

```
DECLARE Participant IS ONE OF Resident, Developer, Registrar

DECLARE Submission IS ONE OF
  `open the consultation`
  `file written comments`
  `file a response`
  `publish the record`

`the staged consultation` MEANS
  PARTY Registrar
  MUST `open the consultation`
  WITHIN 5
  HENCE     (PARTY Resident MAY `file written comments`
               HENCE PARTY Registrar MAY `publish the record`)
        RAND (PARTY Developer MAY `file a response`)
  LEST BREACH
```

```
l4 export bpmn p1.l4 --rule 'the staged consultation' -o p1.bpmn --fidelity-report
```

The `.bpmn` here is that emission with a comment header added and the XML
otherwise verbatim; the `.fidelity.txt` is that emission's report, unedited (seven
notes: `F1` x4, `P-DEADLINE-UNIT`, `F2`, `F5` — and no `P-NOJOIN`, because the join
WAS drawn).

**It is not a golden.** The source is not committed under `../` and no row in
`jl4/tests/BpmnExport.hs` regenerates it, because adding one would also need a row
in `etc/bpmn-kie-baseline.txt` — which is a measurement from the jBPM harness and
not something to invent. Re-capture it by hand if the exporter's output for this
shape changes.

## `joined-beside-breach.bpmn`

A `RAND` whose two branches are joined by a converging parallel gateway, where
one branch carries an interrupting boundary event routing to `BREACH`.

If the boundary fires, the sibling's token is already sitting on
`Flow_Task_A__Join_0` and no second token will ever arrive. So the verdict turns
entirely on what an error end event does:

- **as a plain one-token sink** — the reading `check-bpmn-soundness.mjs` shipped
  with — the sibling waits forever and the diagram **deadlocks**;
- **as a terminate** — BPMN's actual semantics for an uncaught top-level error —
  every remaining token is discarded and the instance ends.

The second is right, and three sources agree on it: the spec, the exporter's own
fidelity report (`P-NOJOIN` in `../expected/offering.fidelity.txt` says a branch
reaching `BREACH` "abandons its siblings rather than waiting for them"), and
jBPM, which ABORTS `offering.bpmn` the moment `BREACH` fires with three branches
still unrun.

Measured, on this file:

| checker                                         | verdict                                                       |
| ----------------------------------------------- | ------------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle)           | OK — 0 warnings, 8 flow nodes, 7 sequence flows, all drawn     |
| `etc/check-bpmn-soundness.mjs`                  | **SOUND**; reports 1 terminating end event and 2 markings that can complete only by terminating |
| `etc/check-bpmn-soundness.mjs` **before the fix** | **UNSOUND**, S1+S2 fail — a false positive                  |
| `etc/check-bpmn-kie.sh` (jBPM 7.74.1)           | COMPLETED (on the happy path; see below)                       |

jBPM's COMPLETED is weak corroboration and is labelled as such: work items
auto-complete, so the boundary timer never fires and the engine never explores
the branch that mattered. It confirms the file is executable, not that the
terminate reading is right.

## Why this is not in `../expected/`

It is hand-written, and `../expected/` is reproducible byte-for-byte by
`l4 export`. Today's exporter cannot emit this shape: `addJoin` declines to join
a branch that can breach, and reports `P-NOJOIN` instead. The fixture exists so
that relaxing that restriction is not blocked by a false positive in the gate —
the checker has to be right about the shape *before* the exporter starts emitting
it, or the first person to try will be told their correct diagram deadlocks.

## `mi-subprocess-two-ways-to-done.bpmn`

A fork over a **permission**. Each director MAY approve within `P30D`; one who
approves creates the chair's duty to publish, and one who lets the permission
lapse ends their own instance fulfilled. Both are ways of being finished, so
both flows meet at the one end event inside the scope.

That is the whole fixture, and it caught a real false positive.

The expansion turns every interior flow arriving at a normal end into a flow to
the scope's synthetic join — and the join is an AND. With two arrivals per copy
it therefore waited for **one token per (instance × arrival flow)** where the
semantics want **one per instance**. So the moment every director took the same
one of the two paths, the model deadlocked on flows out of a task nobody had
performed. The file was correct; the model was counting arrivals.

The fix is one XOR gateway per copy — "this instance is finished" — merging the
interior's normal ends before the join. XOR is right because a sub-process
instance completes when it has no tokens left, and these copies hold exactly
one: an interrupting boundary makes *performed* and *expired* exclusive. An
interior that really does run two tokens at once has to rejoin them at a
parallel gateway before its end, and if it does not, that is an uncontrolled
merge S4 reports on its own.

| checker                                           | verdict                                                    |
| ------------------------------------------------- | ---------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle)             | OK — 0 warnings, 7 flow nodes, 6 sequence flows, all drawn |
| `etc/check-bpmn-soundness.mjs`                    | **SOUND** at 0 and at 2 instances                          |
| `etc/check-bpmn-soundness.mjs` **before the fix** | **UNSOUND** at 2, S1+S2 fail, 4 deadlocked markings        |

That last row is the fixture's whole value, and it was measured by reverting the
fix rather than argued: a regression fixture nobody has watched fail is a
fixture that might be pinning nothing.

### Found by the exporter, not by this file

Worth recording, because it is the case this directory's opening paragraph is
about. The false positive was not found by inspection — it was found when the
BPMN exporter learned to emit fork scopes and its own `modals-may-fork` golden,
a permission under `UPON EACH`, came back UNSOUND. The checker looked like it
was working: it produced a deadlock witness, naming flows, in the shape a real
finding takes.

The exporter's goldens cannot serve as this fixture, for the reason the last
section gives: they move whenever the exporter does. This one is hand-written
and holds still.

## `mi-subprocess-throw-and-finish.bpmn`

The same fork, with the members allowed to disagree: one completes its act, the
other lets the deadline expire and throws. The scope's escalation boundary is
non-interrupting, and the top-level `Breach` end is a **plain** end event, so
nothing terminates anything.

A throwing end event is **two facts**, and a model needs both. It throws the
escalation, which the boundary catches; and it consumes that path's token, which
— since an instance holds exactly one — means the instance is **finished**. BPMN
completes a sub-process instance when it has no tokens left, and an escalation
end leaves none.

The expansion recorded only the first. A copy that threw never signalled its own
`done`, so the scope's join waited on it forever.

### Why this was invisible until the breach end stopped terminating

It is the more interesting half. While the top-level `Breach` end carried an
`errorEventDefinition`, reaching it **discarded every remaining token** — which
is exactly the stuck join. The file scored SOUND, and the gate said so in the
same breath without anyone reading it that way:

```
tenancy-fork.bpmn [receipts] @ 2 instance(s): SOUND
  info  1 terminating end event(s): End_3 "Breach" — reaching one discards every remaining token
  info  39 marking(s) can reach completion ONLY by terminating
```

Thirty-nine of sixty-seven markings could complete *only* by terminating. Those
are the deadlocks, rescued by the terminate. **A gate that passes for that reason
is not passing**, and the second `info` line was the tell, printed on every run.

The earlier workaround is worth naming too, because it is the shape of the
mistake: the expansion already had a rule for "if NO interior path ends normally,
nothing reaches the join, so drop the join". That handles the extreme case and
lets the general one through — some copies throw, some do not. A rule that covers
the boundary condition and not the middle is a sign the semantics are wrong, not
the boundary condition.

| checker                                           | verdict                                                    |
| ------------------------------------------------- | ---------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle)             | OK — 0 warnings, 10 flow nodes, 7 sequence flows, all drawn |
| `etc/check-bpmn-soundness.mjs`                    | **SOUND** at 0 and at 2 instances                          |
| `etc/check-bpmn-soundness.mjs` **before the fix** | **UNSOUND** at 2, S1+S2 fail, 2 deadlocked markings        |

Measured by reverting the fix, not argued.

## `mi-subprocess-every-instance-throws.bpmn`

`mi-subprocess-throw-and-finish.bpmn` has one instance throw and another complete
normally. This one has **every** instance throw, and it exists because that is
the case where an assumption became load-bearing in two places at once.

The emitter's `P-FORK-VERDICT` asserts that BPMN takes the sub-process's outgoing
flow when every instance has ended. The checker was taught, in the commit above,
that a throwing instance is a finished instance. Both follow from the spec — a
sub-process instance completes when it has no tokens left, and an escalation end
leaves none — and **neither had been measured on an engine.** Every row in
`etc/bpmn-kie-baseline.txt` is an unseeded empty cast, so nothing in it runs an
instance at all, and the seeded census recorded there has all three members
complying. So no committed run had ever thrown an escalation.

That is the dangerous shape: the exporter and the gate depending on the same
unmeasured fact, in the same direction. If jBPM did not complete an instance that
ended by escalation, the consequence would not be a wording problem — it would be
a hang on the scope, and the gate could no longer see it, because it had been
taught to assume otherwise.

### Measured, jbpm-bpmn2 7.74.1, three members, every one throwing

Seeded through a scratchpad copy of `etc/kie/KieBpmnCheck.java` patched only at
its `startProcess` line (the repo harness never seeds; the technique is in
PROCESS-TRACK.md §8.1):

```
   [fire census]
      1x  (unnamed) [StartNode]
      1x  each member [ForEachNode]
      3x  (unnamed) [StartNode]          <- one instance per member
      3x  MUST Pay ... [HumanTaskNode]
      3x  Breach [FaultNode]             <- every instance THROWS
      3x  Breach [EndNode]               <- the catch fires once per throw
      1x  every run has ended [EndNode]  <- AND THE SCOPE STILL COMPLETES
[PHASE 2 execute] COMPLETED
```

The last two lines are the answer. The scope completes with every instance
having ended by escalation, so a throwing instance is a finished instance on a
real engine and not only in the spec. The `3x` on the outer breach end is worth
noting too: the non-interrupting boundary really does fire once per breaching
member, which is what makes a member's breach visible without cancelling anyone.

| checker                                           | verdict                                                   |
| ------------------------------------------------- | --------------------------------------------------------- |
| `etc/validate-bpmn.mjs` (bpmn-moddle)             | OK — 0 warnings, 7 flow nodes, 5 sequence flows, all drawn |
| `etc/check-bpmn-soundness.mjs`                    | **SOUND** at 0 and at 2 instances                         |
| `etc/check-bpmn-soundness.mjs` **before the fix** | **UNSOUND** at 2                                          |
| `etc/kie/KieBpmnCheck.java`, seeded with 3        | **COMPLETED**, census above                               |

It is not in `../expected/` because the exporter cannot emit it: a fork whose
every path throws would need a rule with no fulfilling act at all. It is a probe
of the ENGINE, kept because the claim it settles is one two different pieces of
this repo now rest on.
