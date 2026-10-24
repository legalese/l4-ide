# DEONTIC

`DEONTIC` is the type of regulative rules: obligations, permissions and prohibitions.
It takes two type parameters, the type of the parties and the type of the actions.

## Syntax

```text
GIVETH A DEONTIC PartyType ActionType
```

**Example file:** [deontic-example.l4](deontic-example.l4)

## Example

```l4
DECLARE Actor IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF
  `deliver goods`
  `pay invoice` HAS amount IS A NUMBER

GIVETH A DEONTIC Actor Action
`delivery obligation` MEANS
    PARTY Seller
    MUST `deliver goods`
    WITHIN 14
    HENCE FULFILLED
    LEST BREACH
```

Every `PARTY` in the rule must be an `Actor`, and every action an `Action`.

## Values

A value of type `DEONTIC Party Action` is one of:

- a rule, `PARTY … MUST/MAY/SHANT …` (see [PARTY, MUST, MAY, SHANT](PARTY.md));
- `FULFILLED`: nothing more is owed;
- `BREACH`, optionally `BREACH BY party BECAUSE reason`: a party failed;
- two rules combined with `RAND` or `ROR` (see [Deadlines and consequences](consequences.md#rand-and-ror)).

Like any other value, a `DEONTIC` value can be the result of a function with `GIVEN` inputs, or of an `IF` or a `CONSIDER`:

```l4
DECLARE Actor IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `deliver goods`

GIVEN `is urgent` IS A BOOLEAN
GIVETH A DEONTIC Actor Action
`delivery` `is urgent` MEANS
    IF `is urgent`
    THEN PARTY Seller MUST `deliver goods` WITHIN 3
    ELSE PARTY Seller MUST `deliver goods` WITHIN 14
```

## Evaluation

A rule decides nothing on its own. It is evaluated from a start time against a list of events, each saying which party did what, and when (see [EVENT](EVENT.md)).
The result is a `DEONTIC` value again:

- `FULFILLED`, when every duty was discharged;
- `BREACH`, with who missed which deadline, when a duty failed and nothing absorbed the failure;
- the rule still waiting, when the events run out before either happens. This value can be given more events later.

`#TRACE` evaluates a rule in a file:

```text
#TRACE rule AT start-time WITH
  PARTY party DOES action AT time
  ...
```

`EVALTRACE` is the same evaluation as a function:

```text
EVALTRACE : DEONTIC party action → NUMBER → LIST OF EVENT party action → DEONTIC party action
```

```l4
DECLARE Actor IS ONE OF Buyer, Seller
DECLARE Action IS ONE OF `deliver goods`

GIVETH A DEONTIC Actor Action
`delivery obligation` MEANS
    PARTY Seller
    MUST `deliver goods`
    WITHIN 14

#TRACE `delivery obligation` AT 0 WITH
    PARTY Seller DOES `deliver goods` AT 10

#EVAL EVALTRACE `delivery obligation` 0 (LIST EVENT Seller `deliver goods` 10)
```

Both give `FULFILLED`. With no events at all, both give the rule still waiting, not `BREACH`: to let a deadline pass without anyone acting, add a `WAITUNTIL` event.

`l4 state-graph` draws a rule's possible paths as a state diagram; see [Using the l4 CLI](../../tutorials/getting-started/l4-cli.md).

## An exported rule cannot take a DEONTIC input

A rule marked `@export` is published as a service, so that other software and people can ask it questions over the web.
The software or person that asks is the **caller**.
The caller sends the rule's inputs in a request, written in JavaScript Object Notation (JSON), a plain-text format for numbers, text, yes-or-no values, lists and records (JSON calls a record an `object`).

A `DEONTIC` value is a duty, a permission or a prohibition, with its deadline and what follows from it, or the outcome of one: `FULFILLED` or `BREACH`.
Below, **duty** means any of these.
The service turns each part of a request into the value the input asks for, but it cannot turn anything in a request into a duty, so a caller cannot supply one.

> **A `DEONTIC` input is for use inside L4 only.**
>
> **Never give a rule marked `@export` a `DEONTIC` input.**
>
> **It may give a `DEONTIC` value as its answer.**
>
> The ban covers an input that holds a duty: a `LIST OF DEONTIC Person Action`, a `MAYBE (DEONTIC Person Action)`, a record with a `DEONTIC` field, an input with no written type that the rule uses as a duty, or an `ASSUME` of such a type that the rule's own body reads, whether the file or a file that it imports declares the `ASSUME`.

The command `l4 check`, which checks a file for errors, refuses such a rule; [What happens if you do it anyway](#what-happens-if-you-do-it-anyway) shows the error.
An `EVENT` input is refused in the same way; see [An exported rule cannot take an event](EVENT.md#an-exported-rule-cannot-take-an-event).

### What to write instead

Let the caller give the plain facts that the duty is made from, and build the duty inside the rule.
A rule that is not exported may take a duty and a list of events as freely as any other input.

**Example file:** [deontic-export-example.l4](deontic-export-example.l4)

```l4
-- A DEONTIC input is for use inside L4 only.
-- Never give a rule marked @export a DEONTIC input.
-- It may give a DEONTIC value as its answer.

DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF `deliver goods`, `pay invoice`

-- Not exported: an exported rule cannot take a DEONTIC value or a list of events as an input.
-- EVALTRACE runs the duty against the events, counting from the start time 0.
GIVEN duty IS A DEONTIC Person Action
      events IS A LIST OF EVENT Person Action
GIVETH A BOOLEAN
`is fulfilled by` duty events MEANS
  CONSIDER EVALTRACE duty 0 events
  WHEN FULFILLED THEN TRUE
  OTHERWISE FALSE

-- Exported: plain facts in, a yes-or-no answer out.
-- The duty and the event are built inside, and handed to `is fulfilled by`.
@export Is the duty fulfilled when the party takes the action on a given day
GIVEN who IS A Person @desc The party who must act
      what IS AN Action @desc The action the party must take
      deadline IS A NUMBER @desc The deadline, in days from the start
      `day taken` IS A NUMBER @desc The day, in days from the start, on which the party took the action
GIVETH A BOOLEAN
`duty fulfilled on day` who what deadline `day taken` MEANS
  `is fulfilled by` (`the duty` who what deadline) (LIST EVENT who what `day taken`)

-- Exported: it gives the duty itself as its answer.
-- The caller adds a start time and the events to the request.
@export The duty of a party to take an action by a deadline
GIVEN who IS A Person @desc The party who must act
      what IS AN Action @desc The action the party must take
      deadline IS A NUMBER @desc The deadline, in days from the start
GIVETH A DEONTIC Person Action
`the duty` who what deadline MEANS
  PARTY who
  MUST EXACTLY what
  WITHIN deadline
  HENCE FULFILLED
  LEST BREACH BY who BECAUSE "the deadline passed without the action"

#EVAL `duty fulfilled on day` Seller `deliver goods` 14 10
#EVAL `duty fulfilled on day` Seller `deliver goods` 14 20
```

`is fulfilled by` has no `@export`, so only other rules in L4 use it, and that is where such inputs belong.
`duty fulfilled on day` and `the duty` are exported, and each builds its duty inside from plain facts.
`MUST EXACTLY what` compares the action with the input `what`.
Without `EXACTLY`, `what` would be a new name that matches any action; see [EXACTLY](consequences.md#exactly).
Each plain input needs a type that a request can carry, such as a type declared with `ONE OF`, or a `NUMBER`.

A request to `duty fulfilled on day` names its four inputs: `who` as `Seller`, `what` as `deliver goods`, `deadline` as `14` and `day taken` as `10`.
The answer is `true`, and with `20` for `day taken` it is `false`.

A rule that gives a duty, such as `the duty`, is run against events, so its request must also carry `startTime`, the time to start from, and `events`, a list in which each event names a party, an action and a time.
Both are required: without one, the service refuses the request with a Hypertext Transfer Protocol (HTTP) status of 400, for example `startTime is required for functions returning DEONTIC`.
To ask before anything has happened, send `"events": []`.

```json
{
  "arguments": { "who": "Seller", "what": "deliver goods", "deadline": 14 },
  "startTime": 0,
  "events": [{ "party": "Seller", "action": "deliver goods", "at": 10 }]
}
```

The answer is `FULFILLED`.
With `20` for `at` it is `{"BREACH": {"detail": "the deadline passed without the action", "party": "Seller", "reason": "explicit"}}`.
With `"events": []` it is `{"OBLIGATION": {"action": "EXACTLY what", "deadline": "deadline", "modal": "MUST", "party": "who"}}`, the duty itself, not yet met and not yet missed.
Its `party`, `action` and `deadline` hold the names of the inputs (`who`, `EXACTLY what`, `deadline`), not the values sent (`Seller`, `deliver goods`, `14`).
With events that do not settle the duty, such as the buyer paying an invoice at `5`, `party` becomes `Seller`, but `action` stays `EXACTLY what`.
`deadline` becomes the time left after the last event: `9` after an event at `5`, `6` after events at `5` and `8`, and not the `14` sent in the request.
A program should not read the fields of a waiting duty as values; use `duty fulfilled on day` for a yes-or-no answer.

### What happens if you do it anyway

Do not write this:

```l4
-- ✘ Do not write this: no request can supply a DEONTIC input
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF `deliver goods`, `pay invoice`

@export Is a duty already fulfilled
GIVEN duty IS A DEONTIC Person Action
GIVETH A BOOLEAN
`already fulfilled` duty MEANS
  CONSIDER duty
  WHEN FULFILLED THEN TRUE
  OTHERWISE FALSE
```

`l4 check` fails, and reports this error at the rule's name, with the name of the input in it:

```text
DEONTIC inputs are not supported for @export.
The input `duty` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC.
Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it.
```

The editor shows the same error on the rule.
Nothing is published: `l4 deploy` refuses the file before it uploads anything, `jl4-service` refuses to deploy it, and the **Deploy** button in the VS Code sidebar stays off until the error is gone.
To publish the rule, write what [What to write instead](#what-to-write-instead) shows.

### Leaving the type off, or declaring the `ASSUME` in another file, gives the same error

An input does not need a written type.
When the rule leaves it off, L4 works the type out from how the rule uses the input, and the check goes by that type.
Here `the duty` has no written type, and `already fulfilled` takes a `DEONTIC`, so `the duty` is one:

```l4
-- ✘ Do not write this: `the duty` has no written type, but it is a DEONTIC all the same
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF `deliver goods`, `pay invoice`

GIVEN duty IS A DEONTIC Person Action
GIVETH A BOOLEAN
`already fulfilled` duty MEANS
  CONSIDER duty
  WHEN FULFILLED THEN TRUE
  OTHERWISE FALSE

@export Is a duty already fulfilled
GIVEN `the duty`
GIVETH A BOOLEAN
`is it fulfilled` `the duty` MEANS `already fulfilled` `the duty`
```

`l4 check` reports the error above, with `the duty` in it.
An input whose type L4 cannot work out from the rule, or works out to be a `NUMBER`, is not refused.

An `ASSUME` that the rule's own body reads counts in the same way when another file declares it.
With ``ASSUME `the assumed duty` IS A DEONTIC Person Action`` in a file called `facts.l4`, a file that has `IMPORT facts` and an exported rule that reads `the assumed duty` in its own body gets the same error, with `the assumed duty` in it.
The service publishes the `ASSUME`s of the file that holds the rule and no others, so a request could not set an imported one in any case.
A duty that a rule defines, with `MEANS` and a body, is not an `ASSUME` and not an input, and an exported rule may read it.

### The one shape the check does not catch

The check looks only at the exported rule's own inputs and at the `ASSUME`s that its own body reads.
It does not look inside a rule that the exported rule calls.
So if a rule that an exported rule calls reads an `ASSUME` of type `DEONTIC`, `l4 check` passes, the exported rule is published without that input, and no request can supply it.
When the `CONSIDER` that reads the `ASSUME` ends in `OTHERWISE`, every request gets the answer of that branch, with no error, and a value sent for the `ASSUME` is ignored.
Here every request gets `false`:

```l4
-- ✘ Do not write this: `l4 check` passes, and every request gets `false`
DECLARE Person IS ONE OF Seller, Buyer
DECLARE Action IS ONE OF `deliver goods`, `pay invoice`

ASSUME `the assumed duty` IS A DEONTIC Person Action

GIVETH A BOOLEAN
`assumed duty fulfilled` MEANS
  CONSIDER `the assumed duty`
  WHEN FULFILLED THEN TRUE
  OTHERWISE FALSE

@export Is the duty fulfilled, as the helper reads it
GIVETH A BOOLEAN
`via helper` MEANS `assumed duty fulfilled`
```

Never let a rule that an exported rule calls read an `ASSUME` of type `DEONTIC`.
Give it the `DEONTIC` as an input, as `is fulfilled by` does above.
The same holds for an `ASSUME` of type `EVENT`.
When the `CONSIDER` has no `OTHERWISE`, every request fails instead, with the HTTP status 422 and a message that says the value `reached a CONSIDER that has no branch for it`.

## Related pages

- [Regulative rules](README.md)
- [PARTY, MUST, MAY, SHANT](PARTY.md)
- [Deadlines and consequences](consequences.md)
- [EVENT](EVENT.md)
- [Foundation module 6: Regulative rules](../../courses/foundation/module-6-regulative.md): a step-by-step introduction
- [How obligations unfold](../../concepts/legal-modeling/regulative-rules.md): the model behind regulative rules
- [Tom Hvitved's PhD thesis](https://di.ku.dk/english/research/phd/phd-theses/2011/hvitved12phd.pdf): the theory L4's contract model is based on
