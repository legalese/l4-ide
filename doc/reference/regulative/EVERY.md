# EVERY

Binds an obligation, permission or prohibition to **every member of a group at once**, instead of to one named party. `EVERY Tenant t MUST sign` reads "every tenant, call them t, must sign": one obligation per tenant, all live at the same time, and one place to say what happens when all of them have acted.

**Status (2026-09-07): the front end is built; the run-time is not.** A rule written with `EVERY` is parsed, its names are checked, its types are checked, it is printed back, and it appears in the state graph. Running it, in a `#TRACE` or through a service, is _proposed, not landed_: the evaluator stops with a message saying so. The section [What runs today, and what does not](#what-runs-today-and-what-does-not) is the precise line. The design is `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md`.

## Syntax

```l4
EVERY Cast v                   -- every value built by the constructor Cast
EVERY v                        -- every value of the party type
EVERY Cast v WHO condition     -- only those for which the condition holds

EVERY Cast v [WHO condition]
    MUST/MAY/SHANT/DO action
    [WITHIN deadline]
    [HENCE consequent]           -- once, when ALL of them have acted (the barrier)
    [HENCE FOR EACH consequent]  -- once PER member who acts (the fork)
    [LEST alternative]
```

Everything after the first line is the same as after [PARTY](PARTY.md): the same modals, the same `WITHIN`, `HENCE`, `LEST` and `PROVIDED`, with the same layout rule (each clause indented past the `EVERY`).

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
- The variable is always last. `EVERY t Tenant` is a mistake, and it is reported as one: `t` would be read as the cast.

The variable has the party type, the one named in the rule's `GIVETH A DEONTIC Actor Action`, and it is in scope in the `WHO` condition, the action, the deadline, the `HENCE` and the `LEST`.

## WHO: only some of them

`WHO` takes a condition, a `BOOLEAN` expression in which the variable is in scope. It narrows the cast to the members for which the condition is true.

```l4
tenants MEANS LIST (Tenant OF "Alice"), (Tenant OF "Bob"), (Tenant OF "Carol")

GIVETH A DEONTIC Actor Action
`the listed tenants sign` MEANS
    EVERY Tenant t
        WHO    elem t tenants
        MUST   Sign (EXACTLY t)
        WITHIN 14
```

The condition names the variable itself (`elem t tenants`, "t is one of the tenants"). The design document's shorter spelling, `WHO member_of tenants` with the variable understood as the first argument, is not built. A condition that is not a `BOOLEAN` is a type error.

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

## HENCE and HENCE FOR EACH: once, or once per member

This is the part `PARTY` cannot say, and the reason `EVERY` exists.

**`HENCE consequent`** is the **barrier**. The consequent fires **once**, when the last member has acted. Three tenants must sign; the tenancy begins when the third signature arrives, not three times.

```l4
GIVETH A DEONTIC Actor Action
`all tenants sign` MEANS
    EVERY Tenant t
        MUST   Sign (EXACTLY t)
        WITHIN 14
        HENCE  `the tenancy begins`
        LEST   BREACH
```

**`HENCE FOR EACH consequent`** is the **fork**. The consequent fires **once per member** who acts, independently, and the member's variable is in scope inside it. Three tenants pay; three receipts follow, each after its own payment.

```l4
GIVETH A DEONTIC Actor Action
`each payment gets a receipt` MEANS
    EVERY Tenant t
        MUST   Pay (EXACTLY t) (EXACTLY theLandlord) amount
        WITHIN 7
        HENCE FOR EACH
               (PARTY theLandlord
                    MUST   Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)
                    WITHIN 5)
        LEST   BREACH BY t
```

The inner obligation is in parentheses, as every nested obligation is: it has no closing token, so its own optional `HENCE`/`LEST` would otherwise swallow the outer `LEST`. This is the same rule as for a `PARTY` rule nested in a `HENCE` (see [HENCE](README.md#hence-fulfillment-consequence)).

`FOR EACH` is only meaningful after an `EVERY`; on a `PARTY` rule it is a type error, because one party is not a group to fork over. `EACH` on its own is not a keyword. A program may still use it as a name.

Without a `HENCE` or a `LEST`, the barrier and the fork are the same thing: one obligation per member and nothing waiting at the end.

**`LEST`** fires when the group's obligation fails. Under the design, that is at the deadline, and the blame falls on exactly the members who did not act. See the limits below for what of this runs.

## Nesting and combining

An `EVERY` may appear wherever a `PARTY` rule may: inside another rule's `HENCE` or `LEST`, and as an operand of `RAND` or `ROR`. An inner `EVERY` may refer to an outer one's variable, which is how "every other partner" is written:

```l4
GIVETH A DEONTIC Actor Action
`mutual termination` MEANS
    EVERY Partner x
        MAY    Terminate (EXACTLY x)
        WITHIN 365
        HENCE FOR EACH
               EVERY Partner y
                   WHO    NOT (y EQUALS x)
                   MUST   Settle (EXACTLY y) (EXACTLY x)
                   WITHIN 30
```

## What runs today, and what does not

Verified 2026-09-07 against the compiler at the head of this branch.

**Runs:**

- Parsing of every form above, including `HENCE FOR EACH` and `WHO`.
- Name checking: the variable is bound in the condition, the action, the deadline, `HENCE` and `LEST`; a name nothing binds is reported.
- Type checking: the variable has the party type; the cast must be a constructor of that type; the condition must be a `BOOLEAN`; `FOR EACH` under `PARTY` is rejected; an action that rebinds the variable is rejected.
- Printing: `l4 format` reproduces the source; the layout printer used by `l4 batch` re-emits a parseable, re-checkable rule.
- The state graph and the BPMN lowered from it show the quantified obligation as **one** node labelled with the quantifier. They do not draw one node per member.

**Does not run, and says so:**

- Evaluation. A `#TRACE` or `#EVAL` of a rule containing `EVERY` stops with `EVERY is not yet evaluable`. The barrier and fork semantics, the blame set on failure, and the clock for continuations (`HENCE` starts at the last completion) are the next phase of the design.
- The prose export (`l4 render`) writes the subject as "every Tenant t who …" but does not mention `FOR EACH`.
- The WASM export refuses a rule containing `EVERY` rather than compile it wrongly.

**Not yet decided** (on the designer's bench, 2026-09-07; each of these is a local change): whether the fork is spelled `HENCE FOR EACH` or with a second quantifier word; whether `NO Tenant t MAY …` is added as the negative form; whether the cast is fixed when the obligation is armed or follows later changes of membership. Until they are decided, the spellings on this page are the ones that parse.

## Related Keywords

- **[PARTY](PARTY.md)** - one named party
- **[MUST](MUST.md)**, **[MAY](MAY.md)**, **[SHANT](SHANT.md)** - the modals
- **[REGULATIVE](README.md)** - `WITHIN`, `HENCE`, `LEST`, `PROVIDED`, `EXACTLY`, `RAND`, `ROR`

## See Also

- **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** - why `Tenant` is a constructor, and what `EXACTLY` does
- **[Regulative Rules](../../concepts/legal-modeling/regulative-rules.md)** - the five slots of a rule
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` - the design, its rulings, and the parts still open
