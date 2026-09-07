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
     -- or --                           -- (pick one; this WITHIN bounds the whole)
    [UPON EACH     [WITHIN deadline]]   -- the fork: once PER member who acts
    [HENCE consequent]
    [LEST alternative]
```

The join line is optional in the grammar and **required whenever the rule has a `HENCE` or a `LEST`** — that is a check, not a parse rule, so the error you get names both spellings.

Everything after the first line is the same as after [PARTY](PARTY.md): the same modals, the same `WITHIN`, `HENCE`, `LEST` and `PROVIDED`. The one new thing is the **join line**, `ONCE ALL HAVE` or `UPON EACH`.

Write each clause indented past the `EVERY`, as the examples below do. What the compiler actually enforces is narrower than that convention: for `WITHIN`, `HENCE` and `LEST` it is the clause's **body** that must sit past the `EVERY`, not the keyword. The join line is the exception, because a bare `ONCE ALL HAVE` or `UPON EACH` has no body to check and a misplaced one would otherwise attach silently to a different rule — so its head keyword and its marker words are themselves column-checked. Its `WITHIN` keyword is not; only that `WITHIN`'s body is, like every other clause.

## The first line: who is in the group

**Example file:** [every-example.l4](every-example.l4)

The word after `EVERY` names the kind of party, and it is a **constructor** of the party type, not a type of its own. This is the value-actor encoding described in [Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md): actors are values of one type, and the constructors of that type are the kinds of actor.

This is the cast every example on this page uses, and it is the preamble of [every-example.l4](every-example.l4). Read the later examples as sitting under it.

```l4
IMPORT prelude

DECLARE Actor IS ONE OF
    Landlord HAS name IS A STRING
    Tenant   HAS name IS A STRING

DECLARE Action IS ONE OF
    Sign    HAS signer IS AN Actor
    Deliver HAS who    IS AN Actor, what   IS A STRING
    Pay     HAS payer  IS AN Actor, payee  IS AN Actor, amount IS A NUMBER
    Receipt HAS issuer IS AN Actor, to     IS AN Actor, amount IS A NUMBER

theLandlord MEANS Landlord OF "Ms Ng"

GIVETH A DEONTIC Actor Action
`the tenancy begins` MEANS
    PARTY theLandlord MUST Deliver (EXACTLY theLandlord) what WITHIN 5
```

With those declarations:

- `EVERY Tenant t` ranges over the tenants and not the landlord. `Tenant` selects the cast; `t` is the name each member goes by inside the rule.
- `EVERY a` with no kind word ranges over **every value of the party type**, landlord included. It is the unfiltered case.
- The variable is always last. `EVERY t Tenant` is a mistake, and it is reported as one: `t` would be read as the cast, and there is no constructor called `t`.
- Because the variable is last, **a single name after `EVERY` is always the variable, never a cast.** `EVERY Tenant` — the variable forgotten — is accepted, and it does not mean what it looks like: `Tenant` becomes the bound variable and the rule ranges over every value of the party type, landlords included. The shadowing is partial: inside the rule a bare `Tenant` is the member, while `Tenant OF "Alice"` still resolves to the constructor, so the mistake can go unnoticed for a long time. Write `EVERY Tenant t`. This is a known sharp edge, not a designed behaviour.

The variable has the party type, the one named in the rule's `GIVETH A DEONTIC Actor Action`, and it is in scope in the `WHO` condition, the action, the act's `WITHIN`, the `HENCE` and the `LEST`. It is **not** in scope in the `WITHIN` on a join line, whether that line is `ONCE ALL HAVE` or `UPON EACH`: that deadline bounds the whole group, so it may not depend on which member you are looking at. Naming the variable there is rejected, but with a poorly worded message — see the limits below.

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

## The join line: once, or once per member

This is the part `PARTY` cannot say, and the reason `EVERY` exists. Under an `EVERY`, a `HENCE` or a `LEST` needs a line saying **when it fires**, and there are two answers. They use different keywords because they are triggered differently: a barrier waits for a condition to become true and then fires once, while a fork fires on each completion as it happens.

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

**`UPON EACH`** is the **fork**. The `HENCE` fires **once per member** who acts, independently, and the member's variable is in scope inside it. Three tenants pay; three receipts follow, each after its own payment.

```l4
GIVETH A DEONTIC Actor Action
`each payment gets a receipt` MEANS
    EVERY Tenant t
        MUST   Pay (EXACTLY t) (EXACTLY theLandlord) amount
        WITHIN 7
        UPON   EACH
        HENCE  (PARTY theLandlord
                    MUST   Receipt (EXACTLY theLandlord) (EXACTLY t) (EXACTLY amount)
                    WITHIN 5)
        LEST   BREACH BY t
```

The inner obligation is in parentheses, as every nested obligation is: it has no closing token, so its own optional `HENCE`/`LEST` would otherwise swallow the outer `LEST`. This is the same rule as for a `PARTY` rule nested in a `HENCE` (see [HENCE](README.md#hence-fulfillment-consequence)).

**There is no default.** An `EVERY` with a `HENCE` or a `LEST` and no join line is a type error, and the message names both spellings. The two readings differ, and picking one silently would change a rule's meaning; in particular, a barrier default would reverse what a single party's `MAY … HENCE` means today. An `EVERY` with no `HENCE` and no `LEST` needs no join line: it is one obligation per member and nothing waiting at the end, and the barrier and the fork are then the same thing.

A join line under a `PARTY` rule is a type error: one party is not a group. `EACH` on its own is not a keyword, so a program may still use it as a name — including as the quantifier's own variable, which type-checks and is very confusing to read. `UPON` **is** a reserved word everywhere, not only here; the join line is simply the only place the language uses it today. `UPON <event>` as a rule head is a separate, unbuilt design.

**`WITHIN` on a join line** is a deadline on the **whole**, not on any one act. `WITHIN 14` on the act says each tenant has fourteen days from the obligation arising; `ONCE ALL HAVE WITHIN 30` says the group has thirty days for all of them to be done, one clock that no single signature restarts. `UPON EACH WITHIN 30` says the same of the fork: each continuation fires on its own member's act, and the whole thing must be finished by day thirty.

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
        UPON   EACH
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

- Parsing of every form above, including `ONCE ALL HAVE`, `UPON EACH`, the `WITHIN` on either join line, and `WHO`.
- Name checking: the variable is bound in the condition, the action, the act's `WITHIN`, `HENCE` and `LEST`; a name nothing binds is reported.
- Type checking: the variable has the party type; the cast must be a constructor of that type; the condition must be a `BOOLEAN`; both deadlines must be `NUMBER`s; a `HENCE` or `LEST` under `EVERY` without a join line is rejected, naming the two spellings; a join line under `PARTY` is rejected; an action that rebinds the variable is rejected.
- Printing: `l4 format` reproduces the source; the layout printer used by `l4 batch` re-emits a parseable, re-checkable rule.
- The state graph and the BPMN lowered from it show the quantified obligation as **one** element labelled with the quantifier — a single transition in the state graph, a single task in the BPMN. They do not draw one element per member, and they do not draw the join line.

**Does not run, and says so:**

- Evaluation. A `#TRACE` or `#EVAL` of a rule containing `EVERY` stops with `EVERY is not yet evaluable`. The barrier and fork semantics, the blame set on failure, the deadline on the whole, and the clock for continuations (`HENCE` starts at the join's firing) are the next phase of the design.
- The prose export (`l4 render`) writes the subject as "every Tenant t who …" and drops the join line — except when the `EVERY` is an operand of `RAND` or `ROR`, where the whole rule falls back to the layout printer and the join line is re-emitted verbatim into the prose.
- The WASM export refuses a rule containing `EVERY` rather than compile it wrongly.
- **The BPMN export draws a barrier and a fork identically, and its fidelity report does not say so.**
  Measured 2026-09-07: the same rule with `ONCE ALL HAVE` and with `UPON EACH` produces
  **byte-identical** BPMN, and a **byte-identical** fidelity report — which lists the deontic
  modality, the bearer-versus-performer gap and the missing deadline units, and never mentions the
  join at all. The quantifier goes the same way: the whole family draws as one task, and the only
  trace of `EVERY` in the output is the lane's label. A fidelity report exists to say what the
  notation could not carry, so this is the one export gap you cannot discover from the export.
  Until it is fixed, do not read a BPMN diagram of a quantified rule as evidence of which join it
  has; read the `.l4`.

**Sharp edges, all measured 2026-09-07.** Each of these is a case where the compiler does something defensible but says it badly, or accepts something it arguably should not. They are listed so you recognise them rather than debug them.

- **Naming the member in a join line's `WITHIN`** is rejected, correctly, but the message is the generic `could not find a definition for the identifier t` — and it then prints the type it inferred for `t`, which reads as a contradiction. What it means is that a deadline on the whole group may not depend on one member. True of both `ONCE ALL HAVE` and `UPON EACH`.
- **Using the party _type_ as the cast** — `EVERY Actor a` where `Actor` is the type — gives `could not find a definition for the identifier Actor ... of type: Actor`, the same self-contradictory shape. The cast must be a constructor. Write `EVERY a` for the unfiltered case.
- **A join line with no `HENCE` and no `LEST` is accepted** and does nothing. `ONCE ALL HAVE WITHIN 30` with nothing after it looks like a constraint and is not one; the deadline has no continuation to fire.
- **The check that an action may not rebind the quantifier's variable only looks at the innermost `EVERY`.** In a nested rule, an inner action writing a bare `x` where `x` is the _outer_ quantifier's variable is accepted, and binds a fresh name matching anyone. Write `EXACTLY x` for every quantifier variable you mean to refer to, at every depth.
- **Clause order decides which `WITHIN` you wrote, silently.** A `WITHIN` before the join line bounds each act; the same `WITHIN` after it bounds the whole group. Both orders parse, both check, and `l4 format` prints either back unchanged, so nothing tells you which one you got. Write the act's `WITHIN` first, as every example here does.
- **A misplaced join line does not say "indentation".** If its head keyword (`ONCE` or `UPON`) is too far left, the join simply does not match, and the leftover keyword is reported against the expression that precedes it — a long `expecting %, &&, *, …` list. Only a misplaced _second_ word (`ALL`, `HAVE`, `EACH`) produces the `incorrect indentation` message. If you get operator soup after a rule that looks right, check the join line's column first.
- **A join line under a `PARTY` rule can report two errors** — that the join line needs an `EVERY`, and separately anything wrong inside the line itself, such as a non-`NUMBER` deadline. A plain `ONCE ALL HAVE` under a `PARTY` reports just the one. Where the second appears it is noise: fixing it does not help, because the line has to go.

**Decided 2026-09-07:** the fork is spelled `UPON EACH`. The candidate `ONCE EACH HAS` was dropped because "once each has signed" reads in ordinary English as the barrier — the very reading the line exists to exclude — and because a distinct keyword puts the trigger in the word: every `ONCE` form waits for a condition and fires once, the fork fires on each completion. `ONCE EACH HAS` no longer parses.

**Still to come, and not on this page:** `NO Tenant t MAY …` as the negative form, and the count and measure joins of the design (`ONCE SOME 2 OF … HAVE`, `ONCE sum OF amount AT LEAST rent`), which are all `ONCE` forms because they are all conditions waited on. `UPON ANY` is deliberately not a form: that case is `ONCE ANY HAS`.

## Related Keywords

- **[PARTY](PARTY.md)** - one named party
- **[MUST](MUST.md)**, **[MAY](MAY.md)**, **[SHANT](SHANT.md)** - the modals
- **[REGULATIVE](README.md)** - `WITHIN`, `HENCE`, `LEST`, `PROVIDED`, `EXACTLY`, `RAND`, `ROR`

## See Also

- **[Actors, Actions, and Agreement](../../concepts/legal-modeling/actors-and-actions.md)** - why `Tenant` is a constructor, and what `EXACTLY` does
- **[Regulative Rules](../../concepts/legal-modeling/regulative-rules.md)** - the five slots of a rule
- `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md` - the design, its rulings, and the parts still open
