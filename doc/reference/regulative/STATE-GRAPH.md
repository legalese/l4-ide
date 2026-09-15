# The state graph: a map of a regulative rule

A regulative rule — `PARTY Alice MUST pay WITHIN 30 HENCE … LEST …` — describes a small journey.
It starts somewhere, an action or a missed deadline moves it somewhere else, and eventually it
arrives at `FULFILLED` or `BREACH`. The **state graph** is a map of that journey: every place the
rule can be, drawn as a circle, and every action or missed deadline that moves it, drawn as an
arrow.

This page is about how to get that map, from the editor and from the command line, and — just as
important — what the map does and does not tell you.

**Example files:** [every-run-example.l4](every-run-example.l4) for the map below, and
[state-graph-example.l4](state-graph-example.l4) for every `--dominators` answer on this page.

## Getting the map in the editor

Open any `.l4` file that has a regulative rule in it. Just above the rule, in small grey text, the
editor offers **Show state graph**. It is built for the L4 extension for Visual Studio Code and
for the web editor alike; the web editor gets it from the release that carries this change, so if
you do not see it there yet, that release has not shipped.

```l4
GIVETH A DEONTIC Actor Action              -- ← "Show state graph" appears above this line
`the tenancy` MEANS
    EVERY Tenant t IN tenants
        MUST   Sign (EXACTLY t)
        WITHIN 14
        ONCE   ALL HAVE
        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) WITHIN 5)
        LEST   BREACH
```

Click it and a pane opens beside the editor with the map for that one rule.

You may already know the editor's other small grey offer, **Show decision graph**, which draws a
yes-or-no rule as a ladder. The two never appear on the same rule: a rule is either a yes-or-no
question or a set of obligations, and each offer knows which it is for. If you see neither above a
rule, the rule is one the tools cannot yet draw — see the limits below.

**What the pane shows today is the map's source, not the picture.** The map is written in a small
text language called DOT, the input format of a widely used drawing tool called GraphViz. The pane
shows that text, with a **Copy DOT** button. Paste it into any GraphViz renderer — the `dot`
program, if you have GraphViz installed, or one of the many online viewers — to see the picture.
Drawing the picture inside the editor is the next step, and it has not been built; until it is,
the pane is honest about being the source.

The pane is a snapshot. It does not redraw itself as you edit; click **Show state graph** again to
see the map for the rule as it now stands. In the web editor the pane is also shared with the
decision graph, which _does_ redraw on every edit — so if a decision graph has already been shown
for this file, your next keystroke hands the pane back to it, and the map is gone until you click
again. In Visual Studio Code the map has a pane of its own and stays put, stale, until you click
again.

## Getting the map from the command line

```bash
l4 state-graph mycontract.l4
```

prints the map of **every** regulative rule in the file, one after another, in the same DOT text.
Pipe it into GraphViz to get a picture:

```bash
l4 state-graph mycontract.l4 | dot -Tsvg -o mycontract.svg
```

The editor's offer and the command line produce the same map for the same rule.

## Reading the map

Take `the tenancy` above. Its map has four places and four arrows:

- **initial**, where the rule starts;
- an arrow out of it labelled `EVERY Tenant t IN tenants MUST Sign ... [14]` and, on a second line,
  `ONCE ALL HAVE` — the tenants signing, all of them, within 14 days — leading to
- a place labelled **theLandlord must Deliver ...**, the landlord's turn, with an arrow labelled
  `theLandlord MUST Deliver ... [5]` leading to
- **Fulfilled**, drawn with a double border, and from both of the earlier places a red dashed
  arrow labelled `timeout` leading to
- **Breach**, also double-bordered.

So the conventions are:

| you see                       | it means                                                                                                                                                                                     |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a circle                      | a place the rule can be: somebody owes something, or it is over                                                                                                                              |
| a double-bordered circle      | it is over — `Fulfilled` (green) or `Breach` (red)                                                                                                                                           |
| a solid green arrow           | the action was taken, and this is where the `HENCE` goes                                                                                                                                     |
| a red dashed arrow            | the `LEST` path, captioned by what reaches it: `timeout` for a `MUST` whose deadline passed, `violation` for a `SHANT` whose forbidden thing was done, `lapses` for a `MAY` nobody exercised |
| `[14]` on an arrow            | the `WITHIN` deadline                                                                                                                                                                        |
| `ONCE ALL HAVE` / `UPON EACH` | for an `EVERY` rule, whether the next step waits for the whole group or fires for each member                                                                                                |
| a diamond                     | a fork, captioned `ALL OF` for a `RAND` (every branch runs) or `ONE OF` for an `ROR` (exactly one does) or an `IF` choosing between rules                                                    |
| a circle named after a rule   | a `HENCE` or `LEST` handed over to another rule in the same file; that rule's own places and arrows follow, drawn once, however many arrows lead into it                                     |
| an arrow back to `initial`    | the rule renews itself, or hands over to a rule that hands back: a loop                                                                                                                      |
| a heavy arrow                 | only with `--dominators --dot`: an act on every path to `FULFILLED` or to `BREACH`, and its caption says which — see [the picture, marked](#the-picture-marked---dominators---dot)           |

## Asking what has to happen: `--dominators`

```bash
l4 state-graph --dominators state-graph-example.l4
```

Instead of a drawing, this prints an answer per rule, for each of its two end states:

```
the sale
  Every path to FULFILLED passes through:
    - PARTY The Seller deliver the goods (MUST, WITHIN 10)
  Every path to BREACH passes through: nothing in particular (there is more than one route).
```

Read it as: _whatever else happens, the sale cannot end fulfilled unless the seller delivers._ The
buyer's payment is **not** on the list, and that is correct: if the buyer misses the payment
deadline and pays the late fee instead, the contract still ends fulfilled — so paying the price is
one route to a good ending, not the only one. Breach, on the other hand, can be reached from the
very first deadline, so there is no single act that every path to breach shares.

An act that appears in the answer is one the contract **cannot do without** for that ending — with
one exception, a lapsing `MAY`, described under [What the answer does not know](#what-the-answer-does-not-know).
This is what a planner would call a landmark, and what graph theory calls a **"dominator"**: a
point every route from the start to a destination has to pass. The flag is named for it.

### Both, or one of

The difference between `RAND` and `ROR` shows up exactly here. The second rule in the example says
the seller delivers **and** the buyer pays; the third says the seller delivers **or** the buyer
collects:

```
delivery and payment
  Every path to FULFILLED passes through:
    - PARTY The Seller deliver the goods (MUST, WITHIN 10)
    - PARTY The Buyer pay the price (MUST, WITHIN 30)
  Every path to BREACH passes through: nothing in particular (there is more than one route).
delivery or collection
  Every path to FULFILLED passes through: nothing in particular (there is more than one route).
  Every path to BREACH passes through:
    - the deadline passing on PARTY The Seller deliver the goods (MUST, WITHIN 10)
    - the deadline passing on PARTY The Buyer collect the goods (MUST, WITHIN 10)
```

Under `RAND` both acts are required to fulfil, so both are listed; and either deadline passing
breaches the whole, so nothing dominates breach. Under `ROR` it is the other way round: either act
suffices to fulfil, so neither is listed; but the contract is breached only when **both**
alternatives have been lost, so both deadlines are on every path to breach. (A single missed
deadline under `ROR` leaves the other alternative open. `l4 run` on a `#TRACE` at that moment prints
the lost alternative's breach `OR` the remaining obligation — the contract as a whole is not
breached; `l4 lts` says so directly, `Standing: in progress`, and marks the lost alternative as no
longer available.)

### Every state, not only the ends

```bash
l4 state-graph --dominators --all-states state-graph-example.l4
```

adds an answer for each intermediate state: what has to have happened for the contract to be
_there_. For the sale:

```
  Every path to "The Buyer must pay the late fee" passes through:
    - PARTY The Seller deliver the goods (MUST, WITHIN 10)
    - the deadline passing on PARTY The Buyer pay the price (MUST, WITHIN 30)
```

The start state answers "nothing has to happen to be there". A rule whose arms are only other
named rules has no `FULFILLED` or `BREACH` state of its own, and the answer says so: `(this graph
has no FULFILLED or BREACH state to reach)`. (The answer "No path reaches …" exists for a state
nothing points at; a drawing made from an `.l4` file never contains one.)

### The picture, marked: `--dominators --dot`

```bash
l4 state-graph --dominators --dot state-graph-example.l4 | dot -Tsvg -o sale.svg
```

is the same answer drawn onto the map instead of printed as a list. Every arrow the list would
name is drawn heavy, and its caption gains a line — `on every path to FULFILLED`, `on every path
to BREACH`, or `on every path to FULFILLED and to BREACH` for an act neither ending can avoid.
Nothing else about the drawing changes: an arrow the list would not name is drawn exactly as it
is without the flag, so a diagram you already have can be regenerated with the marks and compared.

`--dot` needs `--dominators` (on its own the ordinary output is already DOT, and the flag would
have nothing to add), and it does not combine with `--all-states`: the map marks the two endings
only, because a mark for every intermediate place would put several captions on most arrows.

### How the acts are worded

- An obligation is written as its party, its act, and in brackets the modal, the `WITHIN`
  deadline, the `PROVIDED` condition and, for an `EVERY`, the join line — for example
  `PARTY The Buyer pay the price (MUST, WITHIN 30, PROVIDED price AT LEAST 20)`.
- A prohibition's good arm is worded as **refraining** — for example
  `PARTY The Tenant refraining from sublet (SHANT, WITHIN 365)` — because that arm is taken by the
  deadline passing with the act _not_ done.
- A `LEST` arm is named by what takes it and whose obligation it is: `the deadline passing on …`
  for `MUST` and `DO`, `the prohibited act being done: …` for `SHANT`, `the permission lapsing: …`
  for `MAY`.
- An `IF` between regulative arms names the arm taken: `the arm IF price EQUALS 20`.

## What the answer does not know

The answer is read off the **drawing**, and the drawing is simpler than the running contract in
four ways. The first three make the list of required acts trustworthy in one direction only: an act
that is listed really is on every drawn route, but a route that is drawn is not necessarily one
that can actually be taken. The fourth runs the other way.

1. **Conditions are drawn, not decided.** A `PROVIDED` guard that could never be true still draws
   its arrow, so a route through it counts as a route.
2. **One act, one arrow.** `pay 100` and `pay 5` are the same arrow in the drawing (`pay ...`),
   though the running contract tells them apart.
3. **Deadlines are labels.** Whether a deadline can be met given the ones before it is not worked
   out; the picture shows `WITHIN 30` as text.
4. **A lapsing `MAY` is not drawn.** When a bare `MAY` (no `LEST`) has a `HENCE` that leads on to
   another obligation, the running contract ends `FULFILLED` if the permission simply expires — but
   the drawing shows only the `HENCE` route, so the acts beyond it are listed as required when they
   can in fact be bypassed. This is the one case where an act on the list is not truly necessary;
   it is a gap in the drawing (noted in the extractor's source, `StateGraph.hs`, at the `DMay` case
   of `extractDeonton`) rather than in the question.

So "nothing in particular" means the drawing shows more than one route, not that every route is
live. To know what a particular sequence of events actually does, run it: a `#TRACE` directive
(see [the regulative reference](README.md#testing-with-trace)) plays events into the contract and reports where it
ends. The two answer different questions — the trace says what _did_ happen on one path, the
dominators say what _must_ happen on all of them.

## What the map does not say

The map is deliberately narrow, and the narrowness is easy to miss because the picture looks
complete.

**It shows where the rule can go, not where it is.** Nothing on the map says which place the rule
is in _now_, for a particular contract on a particular day, or who is currently on the hook. That
question — "given what has happened so far, what is outstanding, and for whom?" — is answered by
running the rule with `#TRACE` (see [the regulative reference](README.md#testing-with-trace)) or,
read out as a list, by `l4 lts` (see [What is owed now](lts-list.md)), not by the map. A map with
every road on it is not a map with a "you are here" dot, and this one has no dot.

**It follows a hand-over to another rule in the same file, and stops at the file's edge.** A
`HENCE` or `LEST` that names another regulative rule — ``HENCE `a receipt to` Alice amount`` —
draws an arrow into a place named after that rule, and that rule's own places and arrows follow
from there, so the map of `rent, receipt for the amount paid` shows the receipt being issued. The
named rule is drawn once: a second arrow into the same rule lands on the same place, which is how
two rules that hand over to each other come out as a loop rather than as an endless chain. (The
named rule still has a map of its own, printed separately.) What the arrow carries is only the
hand-over, not the arguments: a rule called with `amount` and the same rule called with
`amount - 1` are the same place. A hand-over the map cannot follow — a rule from an `IMPORT`ed
file, a `RECORD` step, or anything else that is not a rule of this file — is drawn as an arrow
into a place labelled `next` (for `HENCE`) or `failure` (for `LEST`), and stops there.

**A `MAY` with no `LEST` has no red arrow.** A permission nobody exercises simply ends, so the
default there is `FULFILLED`, and the map draws only the green arrow. If such a `MAY` has a
`HENCE` that leads on to another obligation, the lapse route to `FULFILLED` is not drawn at all —
the map shows only the `HENCE` path, and a rule that can in fact end quietly looks as if it cannot.
A `MAY` with an explicit `LEST` gets a red arrow captioned `lapses`.

**An `EVERY` is one arrow, not one per member.** `EVERY Tenant t IN tenants MUST Sign` is drawn as
a single arrow labelled with the quantifier, because who the tenants are is only known when the
rule runs. The `ONCE ALL HAVE` or `UPON EACH` line on the arrow says whether the next step waits
for all of them or fires for each, which is the difference that matters; it does not draw three
tenants.

**Conditions are labels, not logic.** A `PROVIDED` guard, or the `IF` that chooses between two
rules, appears as text on an arrow. The map does not work out when the condition holds.

**Some rules have no map yet.** A rule whose body is not a `PARTY … MUST/MAY/SHANT …`,
`EVERY … MUST …`, `RAND`, `ROR`, or an `IF` choosing between those — for instance one that only
refers to another rule by name — is not drawn, and the editor offers nothing above it.

**A rule that renews itself is a loop.** `HENCE` back into the rule's own name draws an arrow back
to the start, so a renewing duty is drawn as a cycle rather than a dead end; so is a rule that
hands over to a second rule which hands back. A loop has no `Fulfilled` of its own if nothing in
it ever ends well — the map then shows only the ways out to `Breach`. (The BPMN export of a loop
is still a diagram, but its fidelity report will say `P-CYCLE`: its left-to-right layout means
"later" only off the loop. See [DMN and BPMN](../../exports/dmn-bpmn.md).)

**The branches of an `RAND` wait for each other, and the map does not show it.** Each branch's
arrow simply lands on the shared `Fulfilled` circle, and each `ROR` alternative's failure on the
shared `Breach` circle — the map does not say that fulfilment needs _every_ `RAND` branch, nor
that breach needs _every_ `ROR` alternative to be lost. `--dominators` knows this (it counts every
`RAND` branch as required for `FULFILLED` and every `ROR` alternative as required for `BREACH`, as
shown above); a reader of the picture alone has to supply it.

## Related pages

- [Regulative Rule Keywords](README.md) — `HENCE`, `LEST`, `WITHIN`, `RAND`, `ROR`, and `#TRACE`
- [EVERY](EVERY.md) — obligations on every member of a group, and the `ONCE … HAVE` / `UPON EACH`
  join the map labels
- [DMN and BPMN](../../exports/dmn-bpmn.md) — the same state graph, exported as a BPMN process
  diagram for tools that read that format
- [What is owed now: `l4 lts`](lts-list.md) — what a `#TRACE` leaves outstanding, as a list, and
  what would discharge or breach it: the position this map does not mark (it is not drawn onto the
  map; see that page's Limits)
- [`l4` command line](../../tutorials/getting-started/l4-cli.md) — the `state-graph` verb among
  the others
