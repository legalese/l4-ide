# EVERY

Binds an obligation, permission or prohibition to **every member of a group at once**, instead of to one named party. `EVERY Tenant t MUST sign` reads "every tenant, call them t, must sign": one obligation per tenant, all live at the same time, and one place to say what happens when they have acted.

**Status (2026-09-07): the front end is built; the run-time is not.** A rule written with `EVERY` is parsed, its names are checked, its types are checked, it is printed back, and it appears in the state graph. Running it, in a `#TRACE` or through a service, is _proposed, not landed_: the evaluator stops with a message saying so. The section [What runs today, and what does not](#what-runs-today-and-what-does-not) is the precise line. The design is `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md`.

## Syntax

```l4
EVERY Cast v                   -- every value built by the constructor Cast
EVERY v                        -- every value of the party type
EVERY Cast v WHO condition     -- only those for which the condition holds

EVERY Cast v [WHO condition]
    MUST/MAY/SHANT/DO action
    [WITHIN deadline]              -- bounds each act
    [ONCE ALL HAVE [WITHIN deadline]]   -- the barrier: once, when ALL of them have acted
     -- or --                           -- (pick one; the second WITHIN bounds the whole)
    [ONCE EACH HAS [WITHIN deadline]]   -- the fork: once PER member who acts
    [HENCE consequent]
    [LEST alternative]
```

The `ONCE` line is optional in the grammar and **required whenever the rule has a `HENCE` or a `LEST`** — that is a check, not a parse rule, so the error you get names both spellings.

Everything after the first line is the same as after [PARTY](PARTY.md): the same modals, the same `WITHIN`, `HENCE`, `LEST` and `PROVIDED`. The one new line is `ONCE`.

Write each clause indented past the `EVERY`, as the examples below do. What the compiler actually enforces is narrower than that convention: for `WITHIN`, `HENCE` and `LEST` it is the clause's **body** that must sit past the `EVERY`, not the keyword. The `ONCE` line is the exception, and every word of it is checked, because a bare `ONCE ALL HAVE` has no body to check and a misplaced one would otherwise attach silently to a different rule.

## The first line: who is in the group

**Example file:** [every-example.l4](every-example.l4)

The word after `EVERY` names the kind of party, and it is a **constructor** of the party type, not a type of its own. This is the value-actor encoding described in [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md): actors are values of one type, and the constructors of that type are the kinds of actor.

```l4
DECLARE Actor IS ONE OF
    Landlord HAS name IS A STRING
    Tenant   HAS name IS A STRING

DECLARE Action IS ONE OF
    Sign HAS signer IS AN Actor
```

With those declarations:

- `EVERY Tenant t` ranges over the tenants and not the landlord. `Tenant` selects the cast; `t` is the name each member goes by inside the rule.
- `EVERY a` with no kind word ranges over **every value of the party type**, landlord included. It is the unfiltered case.
- The variable is always last. `EVERY t Tenant` is a mistake, and it is reported as one: `t` would be read as the cast, and there is no constructor called `t`.
- Because the variable is last, **a single name after `EVERY` is always the variable, never a cast.** `EVERY Tenant` — the variable forgotten — is accepted, and it does not mean what it looks like: `Tenant` becomes the bound variable, the rule ranges over every value of the party type including landlords, and inside the rule the name `Tenant` is the member rather than the constructor. Write `EVERY Tenant t`. This is a known sharp edge, not a designed behaviour.

The variable has the party type, the one named in the rule's `GIVETH A DEONTIC Actor Action`, and it is in scope in the `WHO` condition, the action, the act's `WITHIN`, the `HENCE` and the `LEST`. It is **not** in scope in the `WITHIN` after `ONCE`: that deadline bounds the whole group, so it may not depend on which member you are looking at. Naming the variable there is rejected, but with a poorly worded message — see the limits below.

## WHO: only some of them

`WHO` takes a condition, a `BOOLEAN` expression in which the variable is in scope. It narrows the cast to the members for which the condition is true.

```l4
IMPORT prelude

tenants MEANS LIST (Tenant OF "Alice"), (Tenant OF "Bob"), (Tenant OF "Carol")

GIVETH A DEONTIC Actor Action
`the listed tenants sign` MEANS
    EVERY Tenant t
        WHO    elem t tenants
        MUST   Sign (EXACTLY t)
        WITHIN 14
```

The condition names the variable itself (`elem t tenants`, "t is one of the tenants"). `elem` comes from the prelude, hence the `IMPORT`. A condition that is not a `BOOLEAN` is a type error.

`WHO` is the only filter word. `WHERE` after a rule keeps its usual meaning, a block of local definitions, so this still works and means what it always meant:

```l4
GIVETH A DEONTIC Actor Action
`sign by the due date` MEANS
    EVERY Tenant t MUST Sign (EXACTLY t) WITHIN due
    WHERE
        due MEANS 14
```

## The action: write EXACTLY to mean the member

The action after `MUST` is a **pattern**, exactly as it is after `PARTY` (see [EXACTLY](README.md#exactly-exact-action-matching)). A bare name in a pattern is a _new_ name that matches anything. So `MUST Sign t` would not mean "t signs": it would introduce a second `t` that matches any signer at all, and a stranger's signature would discharge the tenant's duty.

The checker refuses that spelling and says what to write instead:

```l4
EVERY Tenant t MUST Sign t WITHIN 14            -- ERROR: rebinds t; write EXACTLY t
EVERY Tenant t MUST Sign (EXACTLY t) WITHIN 14  -- the member signs
```

Other arguments of the action may still be patterns. `MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount` pins the payer and the payee and binds `amount` to whatever was paid; `amount` is then in scope in `PROVIDED`, in `HENCE` and in `LEST`, as it is for a `PARTY` rule.

## ONCE: once, or once per member

This is the part `PARTY` cannot say, and the reason `EVERY` exists. Under an `EVERY`, a `HENCE` or a `LEST` needs a line saying **when it fires**, and there are two answers.

**`ONCE ALL HAVE`** is the **barrier**. The `HENCE` fires **once**, when the last member has acted. Three tenants must sign; the tenancy begins when the third signature arrives, not three times.

```l4
GIVETH A DEONTIC Actor Action
`all tenants sign` MEANS
    EVERY Tenant t
        MUST   Sign (EXACTLY t)
        WITHIN 14
        ONCE   ALL HAVE
        HENCE  `the tenancy begins`
        LEST   BREACH
```

**`ONCE EACH HAS`** is the **fork**. The `HENCE` fires **once per member** who acts, independently, and the member's variable is in scope inside it. Three tenants pay; three receipts follow, each after its own payment.

```l4
GIVETH A DEONTIC Actor Action
`each payment gets a receipt` MEANS
    EVERY Tenant t
        MUST   Pay (EXACTLY t) (EXACTLY theLandlord) amount
        WITHIN 7
        ONCE   EACH HAS
        HENCE  (PARTY theLandlord
                    MUST   Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)
                    WITHIN 5)
        LEST   BREACH BY t
```

The inner obligation is in parentheses, as every nested obligation is: it has no closing token, so its own optional `HENCE`/`LEST` would otherwise swallow the outer `LEST`. This is the same rule as for a `PARTY` rule nested in a `HENCE` (see [HENCE](README.md#hence-fulfillment-consequence)).

**There is no default.** An `EVERY` with a `HENCE` or a `LEST` and no `ONCE` line is a type error, and the message names both spellings. The two readings differ, and picking one silently would change a rule's meaning; in particular, a barrier default would reverse what a single party's `MAY … HENCE` means today. An `EVERY` with no `HENCE` and no `LEST` needs no `ONCE` line: it is one obligation per member and nothing waiting at the end, and the barrier and the fork are then the same thing.

An `ONCE` line under a `PARTY` rule is a type error: one party is not a group. `EACH` on its own is not a keyword. A program may still use it as a name.

**`WITHIN` after `ONCE`** is a deadline on the **whole**, not on any one act. `WITHIN 14` on the act says each tenant has fourteen days from the obligation arising; `ONCE ALL HAVE WITHIN 30` says the group has thirty days for all of them to be done, one clock that no single signature restarts.

```l4
GIVETH A DEONTIC Actor Action
`sign, and be done by day 30` MEANS
    EVERY Tenant t
        MUST   Sign (EXACTLY t)
        WITHIN 14
        ONCE   ALL HAVE WITHIN 30
        HENCE  FULFILLED
        LEST   BREACH
```

**`LEST`** fires when the group's obligation fails. Under the design, that is at the deadline, and the blame falls on exactly the members who did not act. See the limits below for what of this runs.

## Combining with RAND and ROR, and nesting

An `EVERY` may appear wherever a `PARTY` rule may: as an operand of `RAND` or `ROR`, and inside another rule's `HENCE` or `LEST`. Parenthesise each operand, as the corpus does for `PARTY` rules.

```l4
GIVETH A DEONTIC Actor Action
`sign and deliver` MEANS
    (EVERY Tenant t MUST Sign (EXACTLY t) WITHIN 14 ONCE ALL HAVE HENCE FULFILLED LEST BREACH)
    RAND
    (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) what WITHIN 14 HENCE FULFILLED LEST BREACH)
```

`RAND` asks for both sides: every tenant signs, and the landlord delivers. `ROR` asks for either. The `EVERY` on one side is a single operand, whatever its cast turns out to hold.

An inner `EVERY` may refer to an outer one's variable, which is how "every other partner" is written. This example has a cast of its own, so it brings its own declarations:

```l4
DECLARE Actor IS ONE OF
    Partner HAS name IS A STRING

DECLARE Action IS ONE OF
    Terminate HAS who IS AN Actor
    Settle    HAS who IS AN Actor, with IS AN Actor

GIVETH A DEONTIC Actor Action
`mutual termination` MEANS
    EVERY Partner x
        MAY    Terminate (EXACTLY x)
        WITHIN 365
        ONCE   EACH HAS
        HENCE  EVERY Partner y
                   WHO    NOT (y EQUALS x)
                   MUST   Settle (EXACTLY y) (EXACTLY x)
                   WITHIN 30
                   ONCE   ALL HAVE
                   HENCE  FULFILLED
```

## What runs today, and what does not

Verified 2026-09-07 against the compiler at the head of this branch.

**Runs:**

- Parsing of every form above, including `ONCE ALL HAVE`, `ONCE EACH HAS`, the `WITHIN` after `ONCE`, and `WHO`.
- Name checking: the variable is bound in the condition, the action, the act's `WITHIN`, `HENCE` and `LEST`; a name nothing binds is reported.
- Type checking: the variable has the party type; the cast must be a constructor of that type; the condition must be a `BOOLEAN`; both deadlines must be `NUMBER`s; a `HENCE` or `LEST` under `EVERY` without an `ONCE` line is rejected, naming the two spellings; an `ONCE` line under `PARTY` is rejected; an action that rebinds the variable is rejected.
- Printing: `l4 format` reproduces the source; the layout printer used by `l4 batch` re-emits a parseable, re-checkable rule.
- The state graph and the BPMN lowered from it show the quantified obligation as **one** element labelled with the quantifier — a single transition in the state graph, a single task in the BPMN. They do not draw one element per member, and they do not draw the `ONCE` line.

**Does not run, and says so:**

- Evaluation. A `#TRACE` or `#EVAL` of a rule containing `EVERY` stops with `EVERY is not yet evaluable`. The barrier and fork semantics, the blame set on failure, the deadline on the whole, and the clock for continuations (`HENCE` starts at the join's firing) are the next phase of the design.
- The prose export (`l4 render`) writes the subject as "every Tenant t who …" but does not mention the `ONCE` line.
- The WASM export refuses a rule containing `EVERY` rather than compile it wrongly.

**Sharp edges, all measured 2026-09-07.** Each of these is a case where the compiler does something defensible but says it badly, or accepts something it arguably should not. They are listed so you recognise them rather than debug them.

- **Naming the member in the `ONCE` deadline** is rejected, correctly, but the message is the generic `could not find a definition for the identifier t` — and it then prints the type it inferred for `t`, which reads as a contradiction. What it means is that a deadline on the whole group may not depend on one member.
- **Using the party _type_ as the cast** — `EVERY Actor a` where `Actor` is the type — gives `could not find a definition for the identifier Actor ... of type: Actor`, the same self-contradictory shape. The cast must be a constructor. Write `EVERY a` for the unfiltered case.
- **An `ONCE` line with no `HENCE` and no `LEST` is accepted** and does nothing. `ONCE ALL HAVE WITHIN 30` with nothing after it looks like a constraint and is not one; the deadline has no continuation to fire.
- **The check that an action may not rebind the quantifier's variable only looks at the innermost `EVERY`.** In a nested rule, an inner action writing a bare `x` where `x` is the _outer_ quantifier's variable is accepted, and binds a fresh name matching anyone. Write `EXACTLY x` for every quantifier variable you mean to refer to, at every depth.
- **An `ONCE` line under a `PARTY` rule reports two errors, not one** — that the `ONCE` needs an `EVERY`, and separately anything wrong inside the `ONCE` line. Only the first matters; fixing the second does not help, because the line has to go.

**Not yet decided** (2026-09-07): the **words** of the fork. `ONCE EACH HAS` is what parses today; `AS EACH HAS`, `EACH TIME ONE HAS` and `UPON EACH` are the alternatives under consideration, because "once each has signed" can be read as the barrier in English. The words live in one place in the compiler and will change without changing anything else on this page. Also still to come, and not on this page: `NO Tenant t MAY …` as the negative form, and the count and measure joins of the design (`ONCE SOME 2 HAVE`, `ONCE sum OF amount AT LEAST rent`).

## Related Keywords

- **[PARTY](PARTY.md)** - one named party
- **[MUST](MUST.md)**, **[MAY](MAY.md)**, **[SHANT](SHANT.md)** - the modals
- **[REGULATIVE](README.md)** - `WITHIN`, `HENCE`, `LEST`, `PROVIDED`, `EXACTLY`, `RAND`, `ROR`

## See Also

- **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** - why `Tenant` is a constructor, and what `EXACTLY` does
- **[Regulative Rules](../../concepts/legal-modeling/regulative-rules.md)** - the five slots of a rule
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` - the design, its rulings, and the parts still open
