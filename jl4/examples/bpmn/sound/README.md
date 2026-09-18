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
| `mi-subprocess-two-ways-to-done.bpmn` | an instance is finished by **whichever** of its paths reaches an end, not by all of them |
| `mi-subprocess-throw-and-finish.bpmn` | an instance that **throws** is also **finished** — the escalation leaves, and the instance has no tokens left |

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
