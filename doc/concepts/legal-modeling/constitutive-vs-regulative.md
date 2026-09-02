# Constitutive vs Regulative Rules

The most important structural distinction in legal drafting — and how L4 makes it a distinction in the type system.

---

## The Distinction

Legal theory divides rules into two kinds:

- **Constitutive rules** define and classify. They say what things _are_: what counts as a "small business", when a payment is "overdue", who qualifies as a "dependant". They create the legal vocabulary that the rest of the law is written in.
- **Regulative rules** oblige, permit, and prohibit. They say what parties _must, may, or must not do_: deliver the goods, file the return, refrain from disclosure.

Statutes are organised around this split. A typical act opens with an interpretation section ("In this Act, 'worker' means…") — constitutive — and then states operative provisions ("An employer must not deduct…") — regulative. Contracts do the same: a definitions clause, followed by the parties' obligations.

The two kinds of rule behave differently:

|                   | Constitutive                                         | Regulative                                                 |
| ----------------- | ---------------------------------------------------- | ---------------------------------------------------------- |
| Answers           | "Is X a Y?" / "What is the value of Z?"              | "What must/may/mustn't a party do now?"                    |
| Involves a party? | No — it classifies facts                             | Yes — a `PARTY` bears the duty                             |
| Involves time?    | No — it is evaluated against a snapshot of facts     | Yes — deadlines, event order, elapsed time                 |
| Can be breached?  | No — a definition is just true or false of the facts | Yes — `BREACH` is a possible outcome                       |
| Result            | A value (`BOOLEAN`, `NUMBER`, …)                     | A verdict: `FULFILLED`, `BREACH`, or a residual obligation |

---

## Constitutive Rules in L4: DECLARE, DECIDE, MEANS

Constitutive rules are L4's declarations and functions. `DECLARE` creates the categories; `DECIDE` and `MEANS` define terms over them:

```l4
DECLARE Business
    HAS `annual turnover` IS A NUMBER
        `employee count` IS A NUMBER

GIVEN business IS A Business
GIVETH A BOOLEAN
DECIDE `is a small business` IF
        business's `annual turnover` LESS THAN 10000000
    AND business's `employee count` AT MOST 200
```

This is the L4 form of an interpretation clause. It names no party, sets no deadline, and cannot be breached — it simply classifies. Constitutive rules can also compute values rather than booleans:

```l4
GIVEN business IS A Business
GIVETH A NUMBER
`applicable fee` MEANS
    IF `is a small business` business
    THEN 100
    ELSE 500
```

`DECIDE … IF …` and `… MEANS …` are two spellings of the same thing: a definition. Evaluating a constitutive rule against the same facts always yields the same answer — there is no timeline, no event stream, no state.

---

## Regulative Rules in L4: PARTY, MUST, MAY, SHANT

Regulative rules are built from a different vocabulary — `PARTY`, a deontic modal (`MUST`, `MAY`, `SHANT`, or `MUST NOT` as a synonym of `SHANT`), a deadline (`WITHIN`), and consequence branches (`HENCE`, `LEST`) — and they have a different type: `DEONTIC`.

```l4
DECLARE Actor IS ONE OF `The Company`, `The Regulator`
DECLARE Act IS ONE OF
    `file annual return`
    `pay filing fee` HAS amount IS A NUMBER

GIVEN business IS A Business
GIVETH A DEONTIC Actor Act
`filing obligation` MEANS
    PARTY `The Company`
    MUST  `pay filing fee` amount PROVIDED amount AT LEAST `applicable fee` business
    WITHIN 30
    HENCE FULFILLED
    LEST  BREACH BY `The Company`
```

A `DEONTIC` value does not evaluate to true or false. It lies dormant until fed a start time and a stream of events, and then advances to one of three outcomes: `FULFILLED`, `BREACH`, or a residual obligation still awaiting events. That machinery — timelines, event matching, reparation chains — is the subject of [Regulative Rules](regulative-rules.md).

---

## The Separation Is Type-Level

L4 does not merely _recommend_ keeping definitions and obligations apart; the type system enforces it. A constitutive rule has an ordinary type like `BOOLEAN` or `NUMBER`. A regulative rule has type `DEONTIC actor action`. You cannot accidentally use an obligation where a definition is expected, or vice versa — the type checker rejects it.

The two layers connect in exactly one direction: **constitutive rules feed regulative rules**. Definitions appear inside obligations as conditions (`IF`, `PROVIDED`) and computed values (deadlines, amounts):

- `` `is a small business` business `` decides _whether_ a duty applies
- `` `applicable fee` business `` decides _how much_ the duty demands
- the `PARTY … MUST …` particle decides _what happens over time_

In the example above, the constitutive layer answers "what fee does this business owe?" and the regulative layer answers "who must pay it, by when, and what if they don't?".

---

## Why the Distinction Matters for Encoding Statutes

### It mirrors the source text

Statutes and contracts are already factored this way. If the interpretation section becomes `DECLARE`/`DECIDE` and the operative provisions become `PARTY`/`MUST`, the encoding is _isomorphic_ to the text: each provision has one home in the code, and a reviewer can check them clause by clause. (This is L4's [legal isomorphism principle](../language-design/principles.md).)

### It prevents two common encoding mistakes

**Flattening an obligation into a boolean.** Encoding "the seller must deliver within 14 days" as a predicate `` `seller is compliant` `` loses the party, the deadline, the ability to say _who_ breached and _why_, and the possibility of a partially-performed contract. A boolean can only say yes or no about a snapshot; an obligation unfolds over time.

**Inflating a definition into an obligation.** Encoding "'small business' means a business with turnover under $10m" as some kind of duty ("the business must have turnover under $10m") invents a deontic force the text does not have. Nobody breaches by being a large business — they simply fall outside a category.

### It keeps the reusable part reusable

Constitutive definitions are pure functions: they can be tested with `#EVAL`, reused across many obligations, and exposed as decision services on their own. Regulative rules are tested differently — with `#TRACE` against event sequences. Keeping the layers separate means each can be validated with the right tool.

---

## Rule of Thumb

When encoding a provision, ask: **can this be breached, by someone, over time?**

- If no — it classifies or computes — write it as `DECIDE`/`MEANS` returning an ordinary value.
- If yes — someone must, may, or must not act — write it as a `PARTY` particle returning a `DEONTIC`.

---

## Further Reading

- [Regulative Rules](regulative-rules.md) — The full regulative system: events, timelines, verdicts
- [Default Reasoning and Exceptions](default-reasoning.md) — Structuring the constitutive layer's general rules and exceptions
- [Regulative Keywords Reference](../../reference/regulative/README.md) — `PARTY`, `MUST`, `MAY`, `SHANT` and friends
- [Functions Reference](../../reference/functions/README.md) — `DECIDE`, `MEANS`, `GIVEN`, `GIVETH`
