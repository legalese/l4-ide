# Deliberately sound BPMN

Hand-written diagrams that **must not be flagged**. They are the third pile the
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
| both of the above | and, since 2026-09-21, that a diagram which discards its siblings **says so on the end event that does it** — see below |
| `mi-subprocess-two-ways-to-done.bpmn` | an instance is finished by **whichever** of its paths reaches an end, not by all of them |
| `mi-subprocess-throw-and-finish.bpmn` | an instance that **throws** is also **finished** — the escalation leaves, and the instance has no tokens left |
| `mi-subprocess-every-instance-throws.bpmn` | the same, in its strongest form — EVERY instance throws and the scope still completes; the one fixture with a **measured engine** answer |

## Two of these now carry a `<documentation>` on their breach end, and why

`etc/check-bpmn-soundness.mjs` gained a third class of finding on 2026-09-21:
a file with a terminating end event and more than one token live at once must
declare that reaching that end throws the others away, or it FAILS. The rule and
its two channels are written up in `../README.md` under "A terminating end beside
concurrency owes a declaration".

`joined-beside-breach.bpmn` (peak 2) and `mi-subprocess-fork.bpmn` (peak 4 at two
instances) are both exactly that shape — they exist to pin the terminate reading,
so of course they are — and neither has an exporter fidelity report beside it,
being hand-written. So each declares it on the end event itself, in the second
channel the rule allows: a `<bpmn:documentation>` on `End_Breach` and on `End_3`.

That is the better channel for these two anyway. A `.fidelity.txt` in this
directory would be a hand-written file in the exporter's own report format, which
is a thing a later reader could mistake for exporter output; a `<documentation>`
is what somebody who opens the diagram in Camunda Modeler and clicks the end
event actually reads. Both files still parse at **0 warnings** under
`etc/validate-bpmn.mjs` (measured 2026-09-21, after the edit).

`mi-subprocess-fork.bpmn`'s note says one more thing, because it has to: its
top-level error end is the **pre-`fcd7ecb2c`** shape, the one that cancelled the
members who had not breached, and the exporter stopped emitting it. The fixture
keeps it deliberately — what it pins is how the checker plays a scope, not how
the exporter draws one — and the note says so rather than leaving a reader to
infer that the current exporter would emit this.

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
