# Actors, Actions, and Agreement

How L4 decides **who may perform which action** in a regulative rule — the
latest syntax and semantics, with worked examples of what type-checks (✅) and
what is rejected (❌).

This page extends [Regulative Rules](regulative-rules.md). Every example here is
checked against the current compiler. For the research background (thematic
roles, STIT logic, agency law) see
[`ACTOR-ACTIONS-THEORY.md`](ACTOR-ACTIONS-THEORY.md).

---

## Use value-actor (one style, by design)

There are, historically, two ways to attach an actor to an action. **Use
value-actor.** We single out one style not because the other is unsupported — it
works fine, and the check behind it is still live — but for a human reason: a
language is kinder when there is *one obvious way*. A rule author shouldn't have
to carry two competing forms in their head, and someone fluent in one style
shouldn't have to come to grips with the other just to read a colleague's
contract. So the older **type-indexed** style is **deprecated as a surface — do
not use it in new models**; it is kept *operational* only so existing contracts
keep type-checking.

- **Value-actor — use this.** The actor is a *value* the action carries
  (`DECLARE Actor IS ONE OF Eater, Drinker`; `eat MEANS Action OF Eater, …`).
  This page is about this style. It is also the more general encoding: it drives
  events natively and is the *only* one that supports duplex actions,
  parameterised actions, and higher-order procurement. Its actor check is
  value-level (see [boundaries](#7-what-is-not-checked-boundaries)).

- **Type-indexed — deprecated, don't use.** The actor is a phantom *type* index
  (`DECLARE Action who …`; `eat : Action Eater`; `DEONTIC Eater (Action Eater)`),
  with agreement as a type equality. The system still accepts it — and it has a
  niche strength, the check being *always* static, even across modules — but it
  is a *second form to learn*, more verbose, and cannot express duplex,
  parameterised, or procured actions. New models should not use it.

Reach for **value-actor** every time. The two are not desugarings of each
other — value-actor is the more general encoding, type-indexed the narrower
special case kept alive operationally — so there is, deliberately, one way to do
this.

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

## 3. One actor or several? (the performer canon)

An action may name **one** actor or **several** — and this is a modelling choice
you make when you `DECLARE` it.

- **One-actor action** — a single actor field (e.g. `eat`, below: `actor IS AN
  Actor`). That actor is the performer; the obligation falls on them, full stop.

  ```l4
  DECLARE Action HAS actor IS AN Actor, verb IS A STRING
  eat MEANS Action OF Eater, "eat"        -- Eater is the (only) performer
  ```

- **Multi-actor action** — several actor fields (e.g. `SendMessage`, with a
  `from` *and* a `to`). Exactly one of them is the **performer** — by canon, the
  **first actor in positional order** — and that is the only one the obligation
  binds. The other actor fields (recipient, object, …) are **participants**:
  recorded in the action as data, but *not themselves obligated*.

  ```l4
  DECLARE SendMessage HAS
    from IS AN Actor          -- first actor field = the performer
    to   IS AN Actor          -- a participant: recorded, but not obligated
    body IS A STRING
  ```

The first-actor rule mirrors English Subject–Verb–Object order: `PARTY Alice MUST
send Alice Bob` reads "Alice sends Bob". Being positional, it makes a multi-actor
action **duplex**: one type carries both directions, and whoever sits in the
first slot is the performer.

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

## 5. Who may perform: one actor, some actors, any actor

Three gradations, all expressed through the actor **type** and how an action
names its performer:

- **one specific actor** — *pin* it in the action (see *Pinned* below);
- **any actor** — leave the performer *open*, a parameter any member of the
  actor type can fill (see *Unpinned* below);
- **some actors** — declare an actor **type** that names exactly that cast (see
  *A named cast* below).

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

**A named cast (some actors).** To allow a *specific subset* of actors and no
others, declare an actor **type** that lists exactly them, and use it as the
DEONTIC's actor parameter. There is no subtyping — you choose the cast when you
declare the type — so a non-member is a plain type error.

```l4
DECLARE Tenant IS ONE OF Renter, Landlord       -- the cast: these two, nobody else
DECLARE TAction HAS actor IS A Tenant, verb IS A STRING
GIVEN who IS A Tenant
GIVETH A TAction
negotiate who MEANS TAction OF who, "negotiate"

GIVETH DEONTIC Tenant TAction
okR MEANS PARTY Renter   MUST EXACTLY negotiate Renter   WITHIN 5   -- ✓
okL MEANS PARTY Landlord MUST EXACTLY negotiate Landlord WITHIN 5   -- ✓
-- PARTY Court … is a type error: Court is not a Tenant.
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
