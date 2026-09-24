# DMN and BPMN

## What DMN and BPMN are

**DMN** — Decision Model and Notation — and **BPMN** — Business Process Model and Notation — are
OMG standards, the same standards body behind UML. They are the lingua franca of enterprise
business-rules work, and between them they cover the two halves of "what does the organisation
do?"

**DMN describes decisions.** Its central artifact is the decision table: a grid, readable and
editable in a spreadsheet-like UI, where each row is a rule and each column an input or output.
Business analysts author and review these directly, without a developer in the loop. Decision
tables compose into a decision requirements diagram showing which decisions feed which, and the
expressions inside cells are written in FEEL, DMN's own expression language. Engines that execute
DMN include Camunda and KIE/Drools.

**BPMN describes processes.** Its artifact is the process diagram: tasks, gateways, events,
timers, and pools for the different parties. It answers "who does what, in what order, and what
happens if they miss the deadline?"

The two are designed to work together — a BPMN process reaches a decision point and delegates to a
DMN decision through a business rule task.

## Why compile L4 to it

This is the export for handing your rules to an organisation rather than an individual.

- **Business stakeholders can read it without learning anything.** A decision table is the format
  in which enterprise rules are already discussed. Putting your L4 into it means the review
  conversation happens in the reviewer's notation.
- **It runs on engines companies already own.** DMN is executed by commercial and open-source
  engines that are already deployed, monitored, and integrated. The export lands in that world
  rather than asking for a new runtime.
- **The regulative layer becomes a picture that is actually true.** BPMN is generated from L4's
  deontic rules — `PARTY p MUST a WITHIN d HENCE … LEST …` — by extracting the state graph. That
  layer genuinely _is_ a transition system, so drawing it as one asserts nothing the source did
  not. (Predicates are a different matter and deliberately stay out of the diagram; see
  [logic, not flowcharts](../concepts/language-design/logic-not-flowcharts.md).)
- **Deadlines and breach become first-class.** A plain `WITHIN` becomes a timer boundary event and
  a `LEST` becomes the path taken when it fires — which is exactly how a process modeller would
  have drawn it by hand. (An anchored `WITHIN` is carried as a condition instead; see below.)

## The command

```
l4 export dmn FILE
l4 export bpmn FILE
```

| Flag                     | Effect                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------- |
| `--to NOTATION`          | `dmn` (DMN 1.3 XML) · `dmn-md` (dmnmd markdown) · `bpmn` (BPMN 2.0 XML)                |
| `--output FILE`          | write the document to `FILE` instead of stdout                                         |
| `--fidelity-report`      | also emit the full fidelity report; a one-line tally prints either way                 |
| `--fail-on SEVERITY`     | exit non-zero at `blocking`, `lossy` or `advisory`; default `none`                     |
| `--model-name NAME`      | DMN only: the `<definitions>` name and namespace seed                                  |
| `--flavor ENGINE`        | DMN only: `camunda` (default) or `kie`                                                 |
| `--include-tests`        | DMN only: also emit decisions that are test scaffolding — off by default               |
| `--rule NAME`            | BPMN only: which regulative rule to export, required when the file holds more than one |
| `--deadline-unit POLICY` | BPMN only: how to read a unitless `WITHIN` — `days` (default) or `refuse`              |

`--flavor` exists because the two major engines disagree on exactly one point: whether a
`<decisionService>` may be the target of a `<knowledgeRequirement>`. Camunda 8 rejects the entire
file at parse time if it is, so that shape is emitted only for `kie`. Choose the flavour matching
the engine you will actually run on.

`dmn-md` is worth knowing about: it emits decision tables as markdown rather than XML, which is far
easier to read in a diff or a pull request than DMN's XML.

## What they consume

They take **different layers of L4**, which is why they are one command with two very different
outputs:

- **DMN** takes the decision layer — `@export`ed decisions, lowered to decision tables and the
  requirement graph between them.
- **BPMN** takes the **regulative** layer — the deontic rules, via their state graph. A file with
  no regulative rules has no BPMN to emit.

By default DMN's population filter omits decisions that are only test scaffolding, referenced from
directive arguments with no real callers. Emitting a fixture as a `<decision>` would misdescribe
the rule set, so you must ask for it with `--include-tests`.

## What doesn't survive

Both emit a **fidelity report**, and reading it is not optional. `Blocking` notes here usually
describe the target notation's limits rather than a defect in your file — DMN and BPMN are
substantially less expressive than L4 — which is why `--fail-on` defaults to `none`. A clean exit
means the export ran, not that everything made it across.

The recurring case for BPMN is the unitless deadline: L4 permits a `WITHIN` with no unit, and BPMN
timers require one. `--deadline-unit days` assumes days and records a note saying it did; `refuse`
emits no timer and records that instead. Neither silently invents a unit.

The other deadline the export declines is the anchored one — `WITHIN 5 OF THE JOIN`,
`OF THE DEADLINE`, `OF THE ARMING`, `OF closingDate` (see
[WITHIN](../reference/regulative/README.md#within-temporal-deadline)). A BPMN timer runs from the
moment its activity starts, and the exporter does not work out whether the anchor is that moment,
so it draws no timer: the boundary event is a _conditional_ event carrying the text verbatim, and
the report says so with a blocking `P-DEADLINE` that names the anchor. An anchored `WITHIN` beside
an `AFTER` is not re-anchored by it, and the `P-WINDOW-OPENING` note on the task says which shape of
closing edge it met (see [AFTER](../reference/regulative/AFTER.md#what-the-exports-do-with-it)).

A rule written for a group — [`EVERY`](../reference/regulative/EVERY.md) — is drawn as a
**multi-instance** activity: one run per member of the group, all live at once, which most modelers
show as three small parallel bars. Who is in the group is only known when the rule runs, so the file
says "many, in parallel" and never says how many.

**Which activity is multi-instance depends on the join line, and the two are different diagrams.**

- `ONCE ALL HAVE` — a **barrier** — marks the _task_. A multi-instance task takes its outgoing flow
  once, after the last instance finishes, which is exactly what the barrier means. Everything after
  the task is drawn once, for the group, because that is what the rule says.
- `UPON EACH` — a **fork** — draws a **sub-process**: a box around the member's act, its deadline,
  and everything that follows it, with the multi-instance marker on the box. Each member gets their
  own copy of the whole thing. That is what makes "once per member" drawable at all; marked on a
  task, the continuation sits outside and can only fire once.

An empty group is worth knowing about, because the two answers differ and both are right. A
multi-instance activity over an empty list finishes immediately and its outgoing flow **is** taken.
For a barrier that is correct — "all zero of them have acted" is vacuously true, so what follows
happens. For a fork the continuation is inside the box, so with nobody in the group nothing runs,
and the rule simply ends. Before this export drew the sub-process, a fork with an empty group drew
an obligation that nobody owed.

**The group's list.** The activity loops over a process variable the file declares and names
`<rule>_<member>_cast`. An engine or a modeler has to put the actual members in it before the diagram can
run, and the `P-CAST` note says so. Read that note before you fill it in: **the list the rule draws
from is not the group.** `EVERY Tenant t IN everyone` means "every tenant among `everyone`", so if
`everyone` also holds the landlord, seeding the variable with `everyone` starts one run too many —
a run for somebody the rule does not bind. The variable is named for the rule rather than for the
list precisely so that it does not invite that.

The notes that go with a quantified rule:

- `P-CAST` (advisory): the file cannot say how many members there are, only that there are many.
  The note names the list the L4 draws from, and what narrows it — the group word, the `WHO`
  condition, or both.
- `P-FORK-JOIN` (lossy): a sub-process finishes when every member's run has finished, and only then
  is its outgoing flow taken. The rule has no such moment — under `UPON EACH` each member runs
  independently and the group never regroups. It makes no difference while each member's
  continuation ends inside their own copy, which is what this export draws; it starts to matter if
  a fork's continuation ever feeds flow shared with something outside the box.
- `P-FORK-LANES` (advisory): the parties inside the box are not drawn as lane bands, because a lane
  can only name the elements of the diagram it sits in and these are one level down. Each element
  inside still names its party in its own documentation.
- `P-JOIN-DEADLINE` (lossy): the join line had a `WITHIN` of its own beside the act's, and only the
  act's is drawn as a timer.
- `P-PROHIBITION-FIRST` (advisory): a `SHANT` **barrier** completes on the **first** member's act,
  since one act is the breach. Without that, "completes when every director has sublet" would
  exonerate the first one. It is not filed on a `SHANT` fork, whose activity is the box and which
  carries no such condition — each member offends severally, and completing the box on the first
  act would cancel the rest.
- `P-PROHIBITION-EMPTY` (lossy): the same condition inverts on an **empty** group. A multi-instance
  activity over an empty list completes at once, and for a prohibition that completion is the
  breach arm — so the diagram ends breached with nobody having done anything, where the rule says
  an empty group is fulfilled because nobody is bound. Reachable rather than theoretical: jBPM runs
  the file that way if you supply no list.
- `F6` (lossy): **the breach does not say who breached it.** A group obligation that fails under
  `ONCE ALL HAVE` fails once, for the group, and the run works out which members failed and lists
  them — one entry per failure, so a member who failed in two ways is named twice, each entry saying
  what that member owed and when it was due. The diagram has one end event for the whole group, and
  BPMN has nowhere to put a list of parties on an end event, so it records that the group breached
  and stops there. That end event looks the same whether one member fell short or all of them.
  Filed only where the group really can breach: a `MAY` group with a `HENCE` and no `LEST` has no
  breach of its own, and does not get the note. It is not filed on a fork either, where each
  member's breach is its own event — what a fork loses is which member reached it, and the boundary
  event it goes through says "a member breached" for exactly that reason.

  **And it says more when the end event is not only the group's** — naming the other arms, and whose
  lane each sits in, rather than saying so in general terms. A breach terminal is shared two ways. A
  group obligation beside another promise sends both breaches to one end event, and so does a group
  whose `HENCE` obliges somebody who can then breach in turn: `tenancy-barrier` is the second shape,
  where `End_3` is reached from the tenants' deadline and from the landlord's, and the note reads
  "`Boundary_1` (theLandlord) also ends at this very event". Its `lost:` line says what that costs,
  which is more than the note's first version admitted: not just which member fell short, but
  **whether a member fell short at all** rather than the landlord.

  Two group obligations can also converge on one end event, and then the note says it does not even
  say **which group** — naming both arms. That is one note, not two: it is filed once per end event,
  because an event two groups reach is one loss with two causes.

**A breach by one member does not end the others**, and getting that right takes two things, not
one. Inside the box a breach is an _escalation_ thrown out to a non-interrupting event on the
boundary, because BPMN's error events always interrupt and an error thrown inside one member's run
would cancel every other member's. And the end event that escalation reaches is a **plain** end,
not an error end — for the same reason one step further out. An error end event does not consume
one token and leave the rest running: it ends every active thread in the process, which includes
the members still going. So a breach that had correctly escaped one instance without interrupting
its siblings would have killed them one flow later, and a duty another member had already earned
would have vanished from the diagram. What the boundary cannot tell you is _which_ member
breached; it says only that one did.

The cost of that plain end is declared as `P-FORK-BREACH-UNMARKED` (advisory): the end is still
named Breach and is still reached only by a member's breach, but it no longer carries the
machine-readable error marking a single-party rule's breach does.

**The rule's own verdict is not drawn, and that is deliberate** (`P-FORK-VERDICT`, lossy). Each
member's run ends inside the box, at that member's own Fulfilled or Breach, and the rule is
fulfilled only if every member's is. BPMN can take the box's outgoing flow when every instance has
ended — which is what the file draws, and why that end event is named "every run has ended" rather
than "Fulfilled" — but it cannot make that terminal depend on _how_ they ended without a variable
this export does not invent. Declining to draw an aggregation it cannot compute is the same choice
made for `loopCardinality` and for an unprovable gateway.

**A permission's timer ends the rule fulfilled**, rather than leading into what follows: a
resolution that did not pass creates no duty to publish it, and under `UPON EACH` what follows
arises only from a member's act (measured 2026-09-16, `jl4/examples/ok/every/run-modals.l4` §7 —
nobody approves, the chair publishes late, and the run is `FULFILLED`). The same holds for a plain
`PARTY … MAY`: a permission with a `WITHIN` gets an ordinary boundary timer whose arm ends the rule
fulfilled. (Before 2026-09-17 the single-party case had no such arm in the state graph, and this
exporter synthesised one and sent it wherever `HENCE` went — which drew a duty on somebody else
arising from a permission nobody exercised. `jl4/examples/bpmn/option.l4` is the witness.)

Until 2026-09-15 the export could not tell the two join lines apart at all, and said nothing about
it; until 2026-09-19 it drew a fork as a marked task, reporting the difference as `P-FORK` and
`P-FORK-CANCEL` rather than drawing it. **If you have a `.bpmn` of a quantified rule from before
those dates, re-export it** — the newer file is a different diagram, not a relabelled one, and it
is the one an engine will accept.

A rule that hands over to another rule by name — ``HENCE `the receipt` `` — is drawn through into
that rule since 2026-09-16 (before, the flow stopped at a dangling end, and the report said
`P-DANGLING`). Two consequences to know about:

- `P-CYCLE` (lossy): a rule that renews itself, or two rules that hand over to each other, is a
  loop, and BPMN draws loops. What this export's layout cannot do is place a node on a loop by
  "how far along it is", so inside the loop left-to-right no longer means later. The diagram is
  still valid and still sound; only the reading of the horizontal axis is lost.
- Two branches of one `RAND` or `ROR` that both hand over to the **same** rule get a copy of
  that rule each, because the L4 runs two instances of it concurrently (`z RAND z` is two `z`s).
  A hand-over reached twice on one path — the `HENCE` and the `LEST` of one obligation, or a rule
  reached again from further down — lands on one node, which is how a loop comes out as a loop.
  (The first cut of this change, on the same day, landed the sibling branches on one node too,
  and `etc/check-bpmn-soundness.mjs` reported that as an unsafe net; that was a defect in the
  drawing, not a property of the rule, and no released export ever drew it.)

If you have a `.bpmn` of a rule that hands over by name from before 2026-09-16, re-export it.

## A terminating end beside concurrency has to be declared

One kind of loss is checked mechanically rather than left to the report, because it is the kind a
reader of the diagram cannot see and will not think to look for.

Some end events **stop the whole run**, not just the path that reached them. An uncaught error end
is one, and so is a terminate end. If the diagram also has more than one thing happening at once —
two branches of a `RAND`, or several members of an `EVERY` — then reaching that end throws away
whatever the others still had to do. A duty one party had already earned disappears from the
diagram, one flow after it was drawn.

So: **where an exported diagram has an end event that stops the run and really can throw away a
token somebody else was still holding, the fidelity report has to say so.** If it does not,
`etc/check-bpmn-soundness.mjs` fails the file — it is a `FIDELITY` finding, distinct from the four
liveness properties, and the four will all say PASS above it.

**"Really can" is measured, not assumed**, and the distinction is the whole difference between a
useful check and one nobody can satisfy. The checker plays the token game, and for each such end
event it asks: over every state in which this end event can fire, how many tokens were in flight
besides the one it consumed? If the answer is none, the end event forfeits nothing and nothing is
owed — a breach deadline hanging off a task that runs _before_ a split is exactly that case, and the
checker says so out loud rather than staying silent:

```
info  End_6 "Breach" can only fire while it holds the last token in flight, so it
      discards nothing and owes no declaration
```

An earlier version of this rule asked only whether the diagram was ever concurrent _anywhere_, which
failed that file with nothing its author could have written to fix it. The witness is committed as
`jl4/examples/bpmn/sound/terminate-upstream-of-split.bpmn`.

**What counts as saying so** is a `lossy` or `blocking` note in the `<name>.fidelity.txt` beside the
file, filed **on the end event itself, or on the junction that made the discarded tokens concurrent
with it** — the parallel split, or the multi-instance sub-process whose copies run side by side. Any
other element is refused, including ones the loss passes through.

That sounds like a technicality and is the opposite of one, because **a note about a neighbouring
loss is not a declaration of this one.** `tenancy-fork-beside-party` is the case that proves it. It
draws a cast of tenants inside one branch of a `RAND`, so its report carries a true `P-NOJOIN` on the
split: the two branches were not joined, and one of them reaching BREACH abandons the other. That note
declares the loss of _the other branch_, and it is accepted for exactly that. Give the cast's own
breach end an error marking, though, and a second loss appears which the split cannot see: one member
of the cast cancelling **another member**. The junction there is the sub-process's multiplicity, and
since no element in a BPMN file names one member's run, the only place that loss can be declared is
the end event. Two earlier versions of this rule accepted the `P-NOJOIN` for it and scored the file
sound — which is the very defect the rule exists to catch, so the file is committed as
`jl4/examples/bpmn/unsound/refork-beside-party-cross-instance.bpmn` and the gate now fails it.

The severity matters for a different reason: an `advisory` note is by definition one that forfeits
nothing, and the exporter has a note that is filed on precisely the right element, matches the
wording, and is advisory — `P-FORK-BREACH-UNMARKED`, which describes an error marking the end event
does _not_ carry.

What the check does not do, so that nobody has to find out the hard way: it does not judge whether a
note's prose is _about_ this loss. No text test can. It insists on the two things it can check — the
element and the severity — and then, as a courtesy filter, that the note states the loss in one of a
short list of recognised forms. That list is no longer what decides anything: with the element test
structural, removing the list entirely moves no verdict in the corpus.

**A diagram with no fidelity report beside it cannot be judged, and says so** — in those words, with
exit 0, because the rule was not run rather than passed. That is deliberate: `--fidelity-report` is
optional, so the same XML would otherwise be sound or unsound depending on whether somebody passed the
flag, and anyone checking a diagram they were handed — from Camunda Modeler, from a counterparty —
would get a failure about a missing file rather than about their diagram. Emitting with
`--fidelity-report` is what puts the file under the rule; for a hand-written diagram you can write the
sidecar by hand, which is what the two `jl4/examples/bpmn/sound/` fixtures with a real loss now do.

Today the report says it as `P-NOJOIN`, whose wording is the one the rule was written from: a branch
here can reach BREACH, "whose error end abandons its siblings rather than waiting for them", filed
against the split that forked the branches. Of the sixteen committed BPMN goldens, two are that
shape — `offering` (up to 3 tokens thrown away) and `tenancy-fork-beside-party` (up to 4, at two
members). Eight more have such an end event and measurably discard nothing; the remaining six run
several things at once and have no run-stopping end event at all.

Why this is a hard check and not another note: the gate had been **printing the evidence on every
run**, as `121 marking(s) can reach completion ONLY by terminating`, and scoring the file sound —
correctly, because terminating is a legitimate way to finish. The defect it was describing went
unnoticed for four days and was found by a reader, not by the gate. A number reported in a severity
class nobody triages is not a check.

## When a decision can refuse

[`REFUSE`](../reference/control-flow/REFUSE.md) is how an L4 rule says **"the model does not cover
this"** — a determinate outcome that is neither a value nor an error. A rule that reaches one stops,
with the author's sentence, and no other rule can catch it. It is what you write for the day before
a statute commenced, or for a case its drafters never addressed.

**DMN has no such outcome.** Its whole vocabulary for "no answer" is FEEL's single `null`, and that
same `null` also spells "there is none" and "the engine could not compute it". So the export has to
choose, and this is what it chose.

**A refusal becomes `null`, and the reason travels with it.** A refusing row keeps its place in the
table and answers `null`; the author's sentence goes on that row's `<description>`, reading
`OTHERWISE — REFUSE: no fee is prescribed before commencement on 1983-01-01`. A decision whose
_whole body_ refuses becomes a boxed `null`, and the sentence goes on the `<decision>`'s own
`<description>`. Nothing is deleted from the artifact: deleting the refusing row answers `null` too
— that was measured on both engines — and it would take the reason with it.

**The fidelity report names it, at a severity that depends on who reads the answer.** Every decision
that can refuse — because it contains a `REFUSE`, or because it calls something that does — gets a
`D-REFUSE` note carrying the reason:

| severity     | when                                                                                |
| ------------ | ----------------------------------------------------------------------------------- |
| **Lossy**    | every caller consumes it from an `IF`/`CONSIDER` arm, so a guard can fence the null |
| **Blocking** | some caller consumes it unconditionally, or nothing calls it at all                 |

The second row is the one to act on: nothing downstream can tell that `null` apart from an answer.
`--fail-on blocking` turns it into a non-zero exit.

**A refusing decision is evaluated even when nothing reaches it.** A DMN `<decision>` is a node in a
graph, not a branch of an expression, so an engine evaluates it whenever it evaluates the model. A
named refusal therefore comes back `null` in _every_ result, including the runs where no rule
reached it. That is not a defect in the export; it is what a decision requirements graph is.

**One shape needed a repair, and it is why this is measured rather than reasoned about.** When the
refusing decision returns an enum, its table declares the domain in `<outputValues>` — and `null` is
not in that list. The two engines disagreed about what that means: KIE 8.44.0.Final enforces the
list at run time and **fails the decision**, while Camunda 8.7.6 returns the `null` silently. One
file, two answers. So the export adds `null` to _that table's_ `<outputValues>`, which makes both
engines agree, and records a `D-OUTPUTVALUES-NULL` note saying it did. The enum type's own declared
domain is left exactly as L4 wrote it: only the table that can decline says that it can.

**Limits, stated plainly.**

- A DMN engine cannot tell you _which_ refusal it hit, only that the answer is `null`. The reason is
  in the artifact for a person to read, not in the result for a program to branch on.
- Refusal is order-dependent under lazy `AND`/`OR` in L4 (`FALSE AND x` answers, `x AND FALSE`
  refuses) and FEEL's logic is not, so a refusal buried inside a boolean can move.
- The **markdown carrier** (`export dmn-md`) cannot carry a refusal at all. dmnmd's cell grammar is a
  number, an integer range, or a bare token, with no `null`, so a refusing table is **omitted**. A
  bare `null` cell would be read back as the _string_ `"null"`, which is the one outcome worse than
  omitting the table. The omission is not silent: the markdown itself carries an
  `<!-- OMITTED: … -->` marker naming each dropped decision and why, and the fidelity report
  carries the located list with codes. Note that `export dmn-md` still **exits 0** — read the marker,
  or pass `--fail-on blocking`.
- `l4 verify` does not model refusals; see [REFUSE](../reference/control-flow/REFUSE.md).

The worked example is `jl4/examples/dmn/refuse.l4` — one of each position a refusal can occupy — and
`jl4/examples/dmn/refuse.cases.json` runs it through both engines in CI.

## Where to look

- **Worked examples:** `jl4/examples/dmn/` and `jl4/examples/bpmn/`, both with goldens and
  committed fidelity reports so you can see what a real report says.
- **Design and rulings:** `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` under `specs/`.
- **Evidence:** the DMN goldens are executed in CI against **two independent engines**, KIE and
  Camunda, and the BPMN output is checked for soundness — so the exports are validated against
  real implementations rather than against our reading of the standard.
