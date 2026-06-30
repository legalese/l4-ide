# Actors, Actions, and Agreement

How L4 decides **who may perform which action** in a regulative rule — the
latest syntax and semantics, with worked examples of what type-checks (✅) and
what is rejected (❌).

This page extends [Regulative Rules](regulative-rules.md). Every example here is
checked against the current compiler. For the research background (thematic
roles, STIT logic, agency law) see
[`ACTOR-ACTIONS-THEORY.md`](ACTOR-ACTIONS-THEORY.md).

---

## Two encodings — and which to use

There are two ways to attach an actor to an action. **Value-actor is the
recommended default; reach for type-indexed only in the unusual cases noted
below.**

- **Value-actor (preferred)** — the actor is a *value* the action carries
  (`DECLARE Actor IS ONE OF Eater, Drinker`; `eat MEANS Action OF Eater, …`).
  This page is about this style. It is the more expressive one: it drives events
  natively and is the *only* encoding that supports duplex actions, parameterised
  actions, and higher-order procurement. Its actor check is value-level (see
  [boundaries](#7-what-is-not-checked-boundaries)).

- **Type-indexed (for unusual scenarios)** — the actor is a phantom *type* index
  (`DECLARE Action who …`; `eat : Action Eater`; contract `DEONTIC Eater (Action
  Eater)`), and agreement is an ordinary type equality. Its one advantage is that
  the check is *always* static — it holds across module boundaries and for
  actions whose actor would otherwise be computed, because the actor lives in the
  type. Reach for it only when you specifically need that guarantee, or when an
  action has **no runtime actor data** (a purely compile-time distinction). It
  cannot express duplex, parameterised, or procured actions.

| | **value-actor** (preferred) | **type-indexed** (unusual) |
|---|---|---|
| Actor lives in | a record *value* | the *type* (phantom index) |
| Agreement check | value-level | type-level (HM) |
| Always static / cross-module | no (skips computed & cross-module) | **yes** |
| Duplex / parameterised / procurement | **yes** | no |
| Event-driving across actors | **yes** | no |
| Ergonomics | one `DECLARE`, `PARTY Eater` | a type + a value per actor |

**If you are not sure, use value-actor.** The two are not desugarings of each
other: value-actor is the more general encoding, and type-indexed is the
narrower, stronger-guarantee special case kept for the situations that need it.

---

## 1. Actors are values; actions carry them

A contract has type `DEONTIC <PartyType> <ActionType>`. The modern, recommended
encoding makes **actors ordinary values** of one type, and **actions records
that carry their actor(s)**:

```l4
DECLARE Actor IS ONE OF Eater, Drinker        -- actors are VALUES

DECLARE Action HAS
  actor IS AN Actor
  verb  IS A STRING

eat   MEANS Action OF Eater,   "eat"           -- positional construction
drink MEANS Action OF Drinker, "drink"

GIVETH DEONTIC Actor Action                    -- monomorphic head: ONE party type, ONE action type
```

Because the head `DEONTIC Actor Action` names one real type, the contract
**drives mixed-actor events natively** — no special machinery is required for
the ball to pass between actors. The cost is that "who may do what" becomes a
value-level rule, described next.

> **Older style still works.** A flat union with no actor field
> (`DECLARE Action IS ONE OF payRent, evict`) remains valid; it simply carries
> no actor, so the agreement rule below does not apply to it.

---

## 2. The rule: a party may only perform its own actions

> **A `PARTY p MUST a` obligation — and a `PARTY p DOES a` event — requires `p`
> to be the action `a`'s _performer_.**

The performer is the **first actor-typed field, in positional order** (the
"subject-first" canon — see §3).

✅ **Works** — each actor is obligated to its own action:

```l4
GIVETH DEONTIC Actor Action
`eater eats`     MEANS PARTY Eater   MUST eat   WITHIN 30
`drinker drinks` MEANS PARTY Drinker MUST drink WITHIN 10
```

❌ **Rejected** — a Drinker obligated to an Eater action:

```l4
GIVETH DEONTIC Actor Action
bad MEANS PARTY Drinker MUST eat WITHIN 30
```

```
An actor may only perform its own actions.

  `eat` is performed by `Eater`, not by `Drinker`.
```

The same check fires on **events**, which is what makes cross-actor *driving*
correct:

❌ **Rejected** — a Drinker doing an Eater action in a trace:

```l4
GIVETH DEONTIC Actor Action
contract MEANS PARTY Eater MUST eat WITHIN 30
#TRACE contract AT 0 WITH
  PARTY Drinker DOES eat AT 5        -- `eat` is performed by `Eater`, not by `Drinker`
```

✅ **Works & drives** — the legitimate ping-pong runs to `FULFILLED`:

```l4
GIVETH DEONTIC Actor Action
pingpong MEANS
  PARTY Eater    MUST eat    WITHIN 30
  HENCE PARTY Drinker MUST drink WITHIN 10 HENCE FULFILLED LEST FULFILLED
  LEST  FULFILLED

#TRACE pingpong AT 0 WITH
  PARTY Eater   DOES eat   AT 5
  PARTY Drinker DOES drink AT 8        -- Result: FULFILLED
```

---

## 3. The performer canon: subject-first, positional, duplex

When an action has **one** actor field, the performer is unambiguous. When it
has **several** — a `SendMessage` with both a sender and a recipient — the
performer is, **by canon, the first actor in positional order**. This mirrors
English Subject–Verb–Object order: `PARTY Alice MUST send Alice Bob` reads
"Alice sends Bob".

This is deliberately positional, which makes an action **duplex**: one type
carries both directions, and whoever sits in the first slot is the performer.

```l4
DECLARE Actor IS ONE OF Alice, Bob
DECLARE SendMessage HAS
  from IS AN Actor          -- first actor field = the performer
  to   IS AN Actor
  body IS A STRING

aliceToBob MEANS SendMessage OF Alice, Bob, "hi"
bobToAlice MEANS SendMessage OF Bob, Alice, "yo"
```

✅ **Works** — each direction binds its first-slot actor:

```l4
GIVETH DEONTIC Actor SendMessage
fwd MEANS PARTY Alice MUST aliceToBob WITHIN 10    -- performer Alice ✓
rev MEANS PARTY Bob   MUST bobToAlice WITHIN 10    -- performer Bob   ✓ (duplex)
```

❌ **Rejected** — wrong direction; `aliceToBob` is performed by Alice:

```l4
wrong MEANS PARTY Bob MUST aliceToBob WITHIN 10
```

```
  `aliceToBob` is performed by `Alice`, not by `Bob`.
```

> **Canon, not bug.** The order-dependence *is* the convention — like the
> last-antecedent rule in statutory interpretation. To make Bob the performer,
> construct the message with Bob first. The diagnostic always names the
> performer, so the rule is visible exactly where you'd trip on it.

---

## 4. Two construction styles: positional `OF` and prepositional `WITH`

The same performer is selected whether you build the action positionally or with
named parameters. Read the named fields aloud and they are prepositions —
*from*, *to*, *by* — the markers of thematic roles.

✅ Both **work** and select `from`/first-slot as the performer:

```l4
positional   MEANS SendMessage OF Alice, Bob, "hi"
prepositional MEANS SendMessage WITH from IS Alice, to IS Bob, body IS "hi"

GIVETH DEONTIC Actor SendMessage
p1 MEANS PARTY Alice MUST positional   WITHIN 10    -- ✓
p2 MEANS PARTY Alice MUST prepositional WITHIN 10   -- ✓
```

> **Note (current limitation).** With named `WITH` construction the performer is
> currently read in *source* order. Positional `OF` is the canonical form and is
> always correct; keying the performer to a role name (e.g. always `from`) is a
> planned refinement. See the theory note, §3.

---

## 5. Pinned vs. unpinned (parameterised) actions

An action can **pin** specific actors, or leave them open and take them as
arguments (overloading / "duplex by parameter").

**Pinned** — actors fixed in the definition (as above):

```l4
aliceToBob MEANS SendMessage OF Alice, Bob, "hi"
```

**Unpinned** — a function over actors, supplied at the use site. Note the
`EXACTLY` keyword: an applied action is an *expression*, not a pattern, so it
must be introduced with `EXACTLY`.

```l4
GIVEN from IS AN Actor
      to   IS AN Actor
GIVETH A SendMessage
send from to MEANS SendMessage OF from, to, "hi"
```

✅ **Works** — performer read from the call-site arguments:

```l4
GIVETH DEONTIC Actor SendMessage
okFwd MEANS PARTY Alice MUST EXACTLY send Alice Bob WITHIN 10   -- performer Alice ✓
okRev MEANS PARTY Bob   MUST EXACTLY send Bob Alice WITHIN 10   -- performer Bob   ✓ (duplex)
```

❌ **Rejected** — wrong performer at the call site:

```l4
bad MEANS PARTY Bob MUST EXACTLY send Alice Bob WITHIN 10
```

```
  `send` is performed by `Alice`, not by `Bob`.
```

⚠️ **Gotcha** — the *bare* applied form does **not** parse as an action (the
action slot is a pattern):

```l4
oops MEANS PARTY Alice MUST send Alice Bob WITHIN 10   -- ERROR: use EXACTLY
```

---

## 6. Procurement: higher-order actions and the principal/agent line

Law routinely says "X undertakes to **procure** that Y performs action_Y". That
is a *higher-order* action — one action wrapping another — modelled as a
recursive action type:

```l4
DECLARE Actor IS ONE OF X, Y, Z

DECLARE Action IS ONE OF
  Perform HAS who      IS AN Actor, verb  IS A STRING
  Procure HAS procurer IS AN Actor, inner IS AN Action     -- wraps an Action

shipByY       MEANS Perform OF Y, "ship"
xProcuresShip MEANS Procure OF X, shipByY                  -- X procures that Y ships
```

The outer obligation binds the **procurer**; the inner action keeps its own
performer. So the principal/agent distinction is type-checked:

✅ **Works** — X bears the procurement obligation:

```l4
GIVETH DEONTIC Actor Action
goodProcure MEANS PARTY X MUST EXACTLY xProcuresShip WITHIN 10   -- performer X ✓
```

❌ **Rejected** — a stranger cannot procure *this* instance:

```l4
strangerProcure MEANS PARTY Z MUST EXACTLY xProcuresShip WITHIN 10
```

```
  `xProcuresShip` is performed by `X`, not by `Z`.
```

❌ **Rejected** — X cannot directly *perform* Y's action, only *procure* it:

```l4
xCannotPerform MEANS PARTY X MUST EXACTLY shipByY WITHIN 10
```

```
  `shipByY` is performed by `Y`, not by `X`.
```

Procurement nests (`procure_X(procure_Y(...))` — a delegation chain). To model a
**non-delegable duty**, require a bare `Perform` (no `Procure` wrapper) in that
obligation slot: the party must do it personally.

---

## 7. What is *not* checked (boundaries)

The check is conservative — it only ever *rejects*, and only when it can decide
statically. It is silent (the obligation is left to runtime) when:

- **the actor is computed**, not a statically-known constructor;
- **the action has no actor field** (flat-union / legacy actions): nothing to
  check, so older contracts are untouched;
- **the action reference crosses a module import** (constant bodies are not yet
  threaded through imports).

It selects the performer by *value* and compares it to the party by *value*; it
is a complement to, not a replacement for, the type-level
`checkPartyActionAgreement` used by type-indexed (`Action Eater`) actions.

---

## See also

- [Regulative Rules](regulative-rules.md) — the five slots, events, outcomes
- [Regulative keyword reference](../../reference/regulative/README.md) —
  `PARTY`, `MUST`, `MAY`, `SHANT`, `WITHIN`, `HENCE`, `LEST`, `PROVIDED`,
  `EXACTLY`
- [`specs/todo/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md`](../../../specs/todo/DEONTIC-PARTY-ACTION-AGREEMENT-SPEC.md)
  — the implementation spec
- [`ACTOR-ACTIONS-THEORY.md`](ACTOR-ACTIONS-THEORY.md)
  — theory & bibliography (thematic roles, STIT, agency law)
