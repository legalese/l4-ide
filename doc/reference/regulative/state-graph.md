# `l4 state-graph` — the shape of a contract, and what has to happen

A regulative rule — `PARTY … MUST … HENCE … LEST …` — describes a sequence of events: someone has
to act by a deadline, and what happens next depends on whether they did. Written out, a contract of
any size is hard to hold in your head. `l4 state-graph` draws it, and can also answer one question
about it directly: **which acts have to happen, no matter what, for the contract to end a given
way?**

**Example file:** [state-graph-example.l4](state-graph-example.l4) — every picture and every answer
on this page was produced from it.

## Drawing the contract

```bash
l4 state-graph state-graph-example.l4 > sale.dot
dot -Tsvg sale.dot > sale.svg      # needs Graphviz installed
```

The command prints one drawing per rule, in the Graphviz `dot` format — a plain-text description
of boxes and arrows that the free [Graphviz](https://graphviz.org/) tools turn into a picture.
Take the first rule in the example file:

```l4
GIVETH DEONTIC Person Action
`the sale` MEANS
  PARTY `The Seller`
  MUST  `deliver the goods`
  WITHIN 10
  HENCE (PARTY `The Buyer`
         MUST  `pay the price`
         WITHIN 30
         HENCE FULFILLED
         LEST (PARTY `The Buyer`
               MUST  `pay the late fee`
               WITHIN 7))
```

Its drawing has five **states** — where the contract can be — and six **transitions** between
them, each an act or a deadline passing:

| from                         | to                           | on                                    |
| ---------------------------- | ---------------------------- | ------------------------------------- |
| initial                      | The Buyer must pay the price | The Seller MUST deliver the goods, 10 |
| initial                      | Breach                       | timeout                               |
| The Buyer must pay the price | Fulfilled                    | The Buyer MUST pay the price, 30      |
| The Buyer must pay the price | The Buyer must pay the fee   | timeout                               |
| The Buyer must pay the fee   | Fulfilled                    | The Buyer MUST pay the late fee, 7    |
| The Buyer must pay the fee   | Breach                       | timeout                               |

Two states are special. **Fulfilled** and **Breach** are where the contract ends, and they are
drawn as double circles: green for fulfilled, red for breach. Every other state is a point where
someone owes something.

A rule built from `RAND` ("both of these") or `ROR` ("one of these") draws a diamond where the
branches split, labelled `ALL OF` or `ONE OF` so that the two are not confused. A rule that says
`EVERY member …` draws one arrow for the whole group, with its join line — `ONCE ALL HAVE` or
`UPON EACH` — written under the obligation; see [EVERY](EVERY.md#seen-as-a-diagram) for those
pictures.

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

An act that appears in the answer is one the contract **cannot do without** for that ending. This
is what a planner would call a landmark, and what graph theory calls a **"dominator"**: a point
every route from the start to a destination has to pass. The flag is named for it.

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
  Every path to BREACH passes through: nothing in particular (there is more than one route).
```

Under `RAND` both acts are required, so both are listed. Under `ROR` either act suffices, so
neither is — and nothing dominates breach in either case, because either obligation can be the one
that fails.

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

The start state answers "nothing has to happen to be there". A state no route reaches at all — the
drawing can contain one if a rule's arms refer to other named rules — answers "No path reaches …".

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
three ways. Each makes the list of required acts trustworthy in one direction only: an act that is
listed really is on every drawn route, but a route that is drawn is not necessarily one that can
actually be taken.

1. **Conditions are drawn, not decided.** A `PROVIDED` guard that could never be true still draws
   its arrow, so a route through it counts as a route.
2. **One act, one arrow.** `pay 100` and `pay 5` are the same arrow in the drawing (`pay ...`),
   though the running contract tells them apart.
3. **Deadlines are labels.** Whether a deadline can be met given the ones before it is not worked
   out; the picture shows `WITHIN 30` as text.

So "nothing in particular" means the drawing shows more than one route, not that every route is
live. To know what a particular sequence of events actually does, run it: a `#TRACE` directive
(see [the regulative reference](README.md)) plays events into the contract and reports where it
ends. The two answer different questions — the trace says what _did_ happen on one path, the
dominators say what _must_ happen on all of them.

## Limits of the drawing

- `HENCE` back into the rule's own name draws an arrow back to the start, so a renewing duty is a
  loop. `HENCE` to a _different_ named rule draws a dead-end state with that rule's name; the other
  rule gets its own drawing.
- A bare `MAY` whose `HENCE` leads to another obligation draws only the `HENCE` arrow; the route by
  which the permission lapses to `FULFILLED` is not drawn.
- The drawing does not show that the branches of an `RAND` wait for one another before the
  contract is fulfilled; each branch's arrow simply lands on the shared `Fulfilled` circle.
  `--dominators` knows this and counts every branch of an `RAND` as required, as shown above, but
  a reader of the picture alone has to supply it.

## See also

- **[Regulative rules](README.md)** — `PARTY`, `MUST`, `HENCE`, `LEST`, `RAND`, `ROR`
- **[EVERY](EVERY.md#seen-as-a-diagram)** — what a rule over a group looks like drawn
- **[DMN and BPMN](../../exports/dmn-bpmn.md)** — the same drawing exported to a process-modelling
  standard
- **[The `l4` command line](../../tutorials/getting-started/l4-cli.md)** — the other verbs
