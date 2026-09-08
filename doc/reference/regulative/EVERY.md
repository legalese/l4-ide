# EVERY

Binds an obligation, permission or prohibition to **every member of a group at once**, instead of to one named party. `EVERY Tenant t MUST sign` reads "every tenant, call them t, must sign": one obligation per tenant, all live at the same time, and one place to say what happens when they have acted.

**Status (2026-09-08): `EVERY` runs, and the group is written with `IN`.** A rule written with `EVERY` is parsed, its names and types are checked, it is printed back, it appears in the state graph, and — new on this date — it can be **run** against a stream of events with `#TRACE`, exactly as a `PARTY` rule can. The barrier fires once at the last act, the fork fires once per act, and a failure produces a breach. Also new on this date: `IN` says which group the rule is about — `EVERY Tenant t IN tenants` — replacing an older spelling that had to smuggle the same list into the `WHO` condition. The older spelling still works and nothing already written needs changing.

Two things about running it are worth knowing before you write one, and both have sections of their own below: the group has to be given as a **list**, which is what `IN` is for — `EVERY Tenant t IN tenants` ([Where the group comes from](#where-the-group-comes-from-the-roll)) — and a few parts of the design are still not built
([What runs today, and what does not](#what-runs-today-and-what-does-not)). The design, its rulings and the parts still open are in `specs/todo/EVERY-EACH-QUANTIFIER-SPEC.md`.

## Syntax

```l4
EVERY Cast v                   -- every value built by the constructor Cast
EVERY v                        -- every value of the party type
EVERY Cast v IN list           -- only those on the list (see "Where the group comes from")
EVERY Cast v WHO condition     -- only those for which the condition holds

EVERY Cast v [IN list] [WHO condition]
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

`IN` comes before `WHO`, in the order you would say them: _every tenant t in tenants who is not Carol_. A rule you intend to **run** has to be given the group as a list somewhere, and `IN` is where to give it; see [Where the group comes from](#where-the-group-comes-from-the-roll), which also covers the older spelling that put the same list inside the `WHO` condition.

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

The variable has the party type, the one named in the rule's `GIVETH A DEONTIC Actor Action`, and it is in scope in the `WHO` condition, the action, the act's `WITHIN`, and — under a fork — the `HENCE` and the `LEST`. Under a barrier the continuation belongs to the join rather than to any member, so naming the variable there is refused when the rule is run; see [the join line](#the-join-line-once-or-once-per-member).

There are two places it is **not** in scope, and they are the same kind of place: what is read **once, for the whole group**, before there is any member to speak of. Those are the `IN` list — see [Where the group comes from](#where-the-group-comes-from-the-roll) — and the `WITHIN` on a join line, whether that line is `ONCE ALL HAVE` or `UPON EACH`. Neither may depend on which member you are looking at: a group's list cannot be worked out from a member of it, and a deadline on the whole group is not a deadline if it is different for each person. Naming the variable in either is rejected, but with a poorly worded message, and with one sharp edge if some _other_ thing in your file happens to have the same name — both described in the roll section.

## WHO: only some of them

`WHO` takes a condition, a `BOOLEAN` expression in which the variable is in scope. It narrows the cast to the members for which the condition is true.

```l4
IMPORT prelude

tenants MEANS LIST (Tenant OF "Alice"), (Tenant OF "Bob"), (Tenant OF "Carol")

GIVETH A DEONTIC Actor Action
`the tenants who are not Carol sign` MEANS
    EVERY Tenant t IN tenants
        WHO    NOT (t EQUALS (Tenant OF "Carol"))
        MUST   Sign (EXACTLY t)
        WITHIN 14
```

The condition names the variable itself — `t` is in scope inside `WHO`, which is the whole point of it. A condition that is not a `BOOLEAN` is a type error.

`IN tenants`, on the first line, is doing something different: it says where the group comes from in the first place, and `WHO` then narrows what it produced. The next section but one is about that.

`WHO` is the only filter word. `WHERE` after a rule keeps its usual meaning, a block of local definitions, so this still works and means what it always meant:

```l4
GIVETH A DEONTIC Actor Action
`sign by the due date` MEANS
    EVERY Tenant t MUST Sign (EXACTLY t) WITHIN due
    WHERE
        due MEANS 14
```

There is one more thing to say about `WHO` before leaving it: in rules written before `IN` existed, the `WHO` condition also carried the list the group is drawn from, and you will still meet those. That is the next section.

## Where the group comes from: the roll

Read this before writing a rule you intend to run.

`EVERY Tenant t` says the rule is about tenants. It does not say **which** tenants, and the computer has no way to work that out on its own. `Tenant HAS name IS A STRING` says a tenant is anything with a name, and there is no end to the names one could write down — `Tenant OF "Alice"`, `Tenant OF "Alice "`, `Tenant OF "Aloysius"`, forever. There is no list of all tenants to go through, so there is no way to know when "all of them have signed".

So you have to hand the rule a list. The list is called the **"roll"**, in the sense of a roll of members that gets called out at a meeting, and you write it with `IN`:

```l4
IMPORT prelude

tenants MEANS LIST (Tenant OF "Alice"), (Tenant OF "Bob"), (Tenant OF "Carol")

GIVETH A DEONTIC Actor Action
`all tenants sign` MEANS
    EVERY Tenant t IN tenants      -- the roll: these three, and nobody else
        MUST   Sign (EXACTLY t)
        WITHIN 14
        ONCE   ALL HAVE
        HENCE  FULFILLED
        LEST   BREACH
```

Read it aloud and it says what it does: _every tenant t in tenants must sign, within fourteen days; once all of them have, the rule is fulfilled, and otherwise it is breached._

`IN` may also go on a line of its own, like the other clauses, when the list is long enough that the first line gets crowded:

```l4
EVERY Tenant t
    IN     tenants
    WHO    NOT (t EQUALS (Tenant OF "Carol"))
    MUST   Sign (EXACTLY t)
    WITHIN 14
```

The `WHO` condition still narrows the group as you would expect, and so does the kind word after `EVERY`. All three work together, in this order:

1. the **roll** — the list after `IN` — gives the starting list;
2. the kind word (`Tenant`) drops anyone not of that kind, so a roll that also names the landlord still produces a group of tenants only;
3. the `WHO` condition drops anyone it says `FALSE` for.

```l4
EVERY Tenant t IN tenants
    WHO NOT (t EQUALS (Tenant OF "Carol"))
```

reads the roll of three, keeps the tenants, and drops Carol: a group of two.

**Without a roll, a rule with `EVERY` will not run.** It still parses and type-checks — writing one is not an error — but running it stops with a message that says what to add:

> EVERY has nothing to draw its cast from. Running a quantified obligation needs a list of the parties it ranges over, because a party type is normally open… Name the list with IN, as `EVERY Tenant t IN tenants MUST ...`, with `tenants` a LIST of the party type.

This is the same habit the language has elsewhere: where two readings are possible and neither is obviously right, it declines to guess and tells you which words to write.

Four details worth knowing:

- **The roll is read once**, when the rule meets its event stream, and the group is fixed from then on. Somebody who joins the list later does not join a group that is already running, and somebody who leaves it is still counted and still blamed. That is deliberate: a group that quietly changed size would quietly change what the rule means. (The design calls this "the cast is evaluated once at arming"; changing a running group is meant to need an explicit act, which is not built.)
- **An empty roll means an empty group**, and an empty group has nothing outstanding. A barrier over nobody is achieved immediately and its `HENCE` fires at once, because "all of them have acted" is true when there are none of them. If that is not what you want, guard the rule with an `IF`. One trap follows from it: an empty group whose `HENCE` leads back to the same rule never consumes an event, so it goes round forever and the run ends with a recursion-depth message rather than an answer.
- **The roll cannot mention the member.** `EVERY Tenant t IN (peersOf t)` asks the list to know its own answer: the list is read once, before there is anybody to be a member, so there is no `t` for it to mean yet. The checker rejects it, and — because the member's name is simply not in scope there — the message you get is the general one, _"I could not find a definition for the identifier t"_. That wording is poorer than the mistake deserves and we know it; the same is true of a join line's `WITHIN`, for the same reason, and the two are meant to get a better message together. To narrow the group by something about each member, put that in the `WHO` condition, where the member **is** in scope: `EVERY Tenant t IN tenants WHO isAdult t`.

  **One sharp edge in that, worth knowing.** What the checker actually rejects is a name it cannot find. If your file happens to define something _else_ called `t` at the top level, then the `t` inside `IN` quietly means **that** one, and nothing is reported — so the same letter would mean the top-level thing in the roll and the member everywhere else. This is the ordinary rule that an inner name only hides an outer one where the inner name is in scope, and the join line's deadline has the same edge. The way to stay clear of it is the way you would anyway: give the member a name nothing else in the file uses.

- **A name listed twice is counted twice.** A roll of `LIST alice, alice, bob` produces three obligations, two of them Alice's. Under a barrier one signature from Alice settles both and nothing worse happens than the group not being the size it looks. Under a fork it is worse: the continuation fires once per copy, so a single payment earns two receipts. Keep the roll free of repeats.

### The older spelling: a roll read out of the WHO condition

Before `IN` existed, the roll had to be smuggled into the `WHO` condition using `elem`, which asks "is this one of those?":

```l4
EVERY Tenant t
    WHO elem t tenants          -- the older spelling: still works, still means the same thing
```

**This still runs, and nothing you have already written needs changing.** When a rule writes no `IN`, the machine looks through the `WHO` condition for a condition of the form `elem t <some list>` and takes that list as the roll. You will meet this spelling in older examples; [every-example.l4](every-example.l4) shows one beside its `IN` equivalent, and `jl4/examples/ok/every/run-roll.l4` in the corpus is the file devoted to it (its first rule is the deliberate exception, with no roll at all — that is the one that shows the refusal).

Prefer `IN` in anything new. Saying the roll outright is clearer to read, and it also avoids three rough edges that the older spelling cannot avoid:

- **It is found by the word `elem`, not by meaning.** A two-argument function of your own called `elem` would be taken for it. In practice `elem` is the one from the standard library, which is why examples using this spelling start `IMPORT prelude`.
- **It has to sit in a plain chain of `AND`s.** `WHO elem t tenants AND …` works, at any depth of `AND`. `WHO elem t tenants OR elem t others` does not, and neither does `WHO NOT (elem t tenants)`: the first offers two lists and the second names who is _out_ rather than who is in, and the search simply does not look inside an `OR` or a `NOT`. What you get in both cases is the same message as for no roll at all — "EVERY has nothing to draw its cast from" — which is accurate but does not point at the `OR`. If you want the members of two lists, join the lists first: `IN (append tenants others)`.
- **A circular roll is caught later.** `WHO elem t (peersOf t)` is only refused when the rule is run, not when it is checked, because the member genuinely is in scope inside a `WHO` condition — that is what a condition is for. `IN` has no such difficulty and the same mistake is caught at check time.

**If you write both**, the `IN` list is the roll and the `elem` condition goes on doing what any other condition does: narrowing. So

```l4
EVERY Tenant t IN tenants
    WHO elem t (LIST alice, bob)
```

draws the three from `tenants`, then keeps the two the condition allows. Nothing is ambiguous and nothing is silently dropped. Worked examples of both spellings side by side are in `jl4/examples/ok/every/run-in.l4`.

## The action: write EXACTLY to mean the member

The action after `MUST` is a **pattern**, exactly as it is after `PARTY` (see [EXACTLY](README.md#exactly-exact-action-matching)). A bare name in a pattern is a _new_ name that matches anything. So `MUST Sign t` would not mean "t signs": it would introduce a second `t` that matches any signer at all, and a stranger's signature would discharge the tenant's duty.

The checker refuses that spelling and says what to write instead:

```l4
EVERY Tenant t MUST Sign t WITHIN 14            -- ERROR: rebinds t; write EXACTLY t
EVERY Tenant t MUST Sign (EXACTLY t) WITHIN 14  -- the member signs
```

Other arguments of the action may still be patterns. `MUST Pay (EXACTLY t) (EXACTLY theLandlord) amount` pins the payer and the payee and binds `amount` to whatever was paid; `amount` is then in scope in `PROVIDED`, in `HENCE` and in `LEST`, as it is for a `PARTY` rule.

## The join line: once, or once per member

This is the part `PARTY` cannot say, and the reason `EVERY` exists. (The rules in this section leave out the `IN …` list, to keep the join in view; add one before running them, as [every-run-example.l4](every-run-example.l4) does.)
Under an `EVERY`, a `HENCE` or a `LEST` needs a line saying **when it fires**, and there are two answers. They use different keywords because they are triggered differently: a barrier waits for a condition to become true and then fires once, while a fork fires on each completion as it happens.

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

**`WITHIN` on a join line** is a deadline on the **whole**. `WITHIN 14` on the act says each tenant has fourteen days from the obligation arising; `ONCE ALL HAVE WITHIN 30` says the group has thirty days for all of them to be done, one clock that no single signature restarts. `UPON EACH WITHIN 30` says the same of the fork: each continuation fires on its own member's act, and the whole thing must be finished by day thirty.

When it is the **only** deadline in the rule it also becomes each member's, because otherwise nothing would ever expire and the rule could never fail. When both are written, the act's is each member's, and a barrier additionally fails if the last act lands after the join's.

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

**A barrier's `HENCE` and `LEST` cannot name the member.** They belong to the join, which fires once after everybody has acted, so there is nobody for the variable to stand for — the design writes them "shared". Under a fork they can and routinely do, because each member has a copy of its own. Writing `EVERY Tenant t … ONCE ALL HAVE … LEST BREACH BY t` is accepted by the type checker and refused when the rule is run, with a message that says to drop the name or to use the fork. (The type checker keeping the variable in scope there is a rough edge, not a design: see the limits below.)

**`LEST`** fires when the group's obligation fails: under a barrier, when the group can no longer all be done in time; under a fork, when the member it belongs to fails. Under the design the blame falls on exactly the members who did not act; what a run actually names today is one of them. See [What runs today](#what-runs-today-and-what-does-not).

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

## Running one

**Example file:** [every-run-example.l4](every-run-example.l4)

A rule with `EVERY` is run the same way a `PARTY` rule is: `#TRACE` it against a list of events. Each member of the group gets an obligation of their own, all of them live at the same time, and every member sees the whole event stream — so the acts may arrive in any order.

```l4
#TRACE `all tenants sign` AT 0 WITH
  PARTY (Tenant OF "Bob")   DOES Sign (Tenant OF "Bob")   AT 2
  PARTY (Tenant OF "Alice") DOES Sign (Tenant OF "Alice") AT 5
  PARTY (Tenant OF "Carol") DOES Sign (Tenant OF "Carol") AT 9
```

**Under a barrier**, the `HENCE` fires once, when the last member has acted — here at day 9 — and two consequences follow that a drafter has to have in mind:

- **The clock starts at the join.** If the `HENCE` is itself an obligation with a `WITHIN 5`, the five days run from day 9, not from day 0. So the landlord's delivery is due on day 14.
- **The `HENCE` only sees what happened after the join.** A delivery on day 3 does not discharge an obligation that only arose on day 9. This is the same rule as for a `PARTY` rule's `HENCE`, and it is what stops a rule from being satisfied by an act that came too early to count.

**Under a fork**, the `HENCE` fires once per member as that member acts, and the member's variable is bound to that member inside it — so three payments produce three receipt obligations, each with its own clock and each naming its own tenant. A `LEST` under a fork blames the member it belongs to, so `LEST BREACH BY t` names exactly the tenant who did not pay.

**When the stream runs out** with the group's work unfinished, what comes back is the work that is left: the obligations of the members who have not yet acted. Nothing is breached — the deadline has not been reached, only the list of events has.

Worked traces for all of this are in the corpus: `jl4/examples/ok/every/run-in.l4` (the `IN` roll, eleven worked cases), `run-barrier.l4`, `run-fork.l4`, `run-roll.l4` (the older `WHO elem` spelling) and `run-modals.l4`.

### What each modal means under a join

- **`MUST`** and **`DO`**: a member who has not acted by the deadline fails, so the group fails.
- **`SHANT`**: a member keeps the prohibition by **not** acting, so a member is counted as done when their deadline passes with nothing prohibited having happened. The barrier is achieved at the deadline.
- **`MAY`**: nobody owes the act, so a member who never exercises the permission has broken nothing. Under a barrier with no `LEST`, that member simply never joins the count, the join never fires, and the run comes back with the single word `FULFILLED` — the same word a barrier that completed produces. This is right for the pattern it is meant for ("the resolution simply does not pass"), but it means **`FULFILLED` is not evidence that the `HENCE` fired**. Put a `LEST` on the join if you need to tell the two apart; with one, a member whose permission lapses does make the group fail, and you get a breach.

## What runs today, and what does not

Verified 2026-09-08 against the compiler at the head of this branch.

**Runs:**

- Parsing of every form above, including `ONCE ALL HAVE`, `UPON EACH`, the `WITHIN` on either join line, and `WHO`.
- Name checking: the variable is bound in the condition, the action, the act's `WITHIN`, `HENCE` and `LEST`; a name nothing binds is reported. (Being bound in a barrier's `HENCE`/`LEST` is a rough edge, not a capability — see below.)
- Type checking: the variable has the party type; the cast must be a constructor of that type; the condition must be a `BOOLEAN`; both deadlines must be `NUMBER`s; a `HENCE` or `LEST` under `EVERY` without a join line is rejected, naming the two spellings; a join line under `PARTY` is rejected; an action that rebinds the variable is rejected.
- Printing: `l4 format` reproduces the source; the layout printer used by `l4 batch` re-emits a parseable, re-checkable rule.
- **Running**, as described above: the roll call, the barrier, the fork, the plain distributive form with no join line, all four modals, the deadline on the act and the deadline on the join line, and nesting one quantified rule inside another's `HENCE`.
- The state graph and the BPMN lowered from it show the quantified obligation as **one** element labelled with the quantifier — a single transition in the state graph, a single task in the BPMN. They do not draw one element per member, and they do not draw the join line.

**Does not run, and says so:**

- A rule with no roll (above) refuses, naming what to write. The message names `IN` first, and says the older `WHO elem` spelling still works.

- The prose export (`l4 render`) writes the subject as "every Tenant t in tenants who …" and drops the join line
  — except when the `EVERY` is an operand of `RAND` or `ROR`, where the whole rule falls back to the layout printer and the join line is re-emitted verbatim into the prose.

**Runs, but not yet as the design says.** These are the places where a run gives an answer and the answer is coarser than the design calls for. Most are a detail of the verdict rather than the verdict itself; the one exception is the same-instant case, marked below, which can make an act count twice.

- **A failed barrier blames one member, not all of them.** The design says the blame is exactly the set of members who did not act. A breach record holds one party, so what you get is the first non-actor in the order the roll named them. If two tenants fail to sign, only one is named. The design calls the set-valued breach R-T3, and it is not built.
- **The clock on a failed barrier is today's, not the design's.** When a `LEST` is itself an obligation, its deadline is counted from the event that revealed the miss, not from the deadline that was missed. That is what a `PARTY` rule does today, and `EVERY` was made to match rather than to diverge; the design (§5.2) changes both together, and that change is not built.
- **A residual barrier loses its join.** If the events run out mid-way, what comes back is the outstanding members' obligations, with their deadlines correctly counted down. Their `HENCE` and `LEST` print as `` `the join` `` and `` `the join fails` `` — the machine's own markers for "report back to the group", not anything you wrote. What the residual does not carry is the join line, so feeding it more events would run the members and not the join. Run the whole stream at once.
- **A join line's `WITHIN` bounds each act; only a barrier also checks it on the whole.** Written alone, on either kind of join line, it is each member's deadline — otherwise nothing would ever expire. Written alongside an act `WITHIN`, the act's is each member's deadline, and a barrier additionally fails if the last act lands after the join's; a fork has no join to check, so there the act's is the only one enforced. Write the tighter of the two on the act.
- **When two members act at the very same instant, the continuation can see one of their acts.** The join's time is right either way, but the stream handed to the continuation is the one belonging to whichever of the two the roll named first, so an event stamped exactly at the join may still reach it. It only bites if the continuation's action could be matched by a member's own act at that instant. A prohibition (`SHANT`) barrier ties by construction and is not affected, because every member finishes on the same event.
- **The type checker is looser than the run time in two places**, and both refuse rather than answer: a barrier continuation that names the member, and a roll — in the older `WHO elem` spelling only — that names the member. Both are described above. An `IN` roll that names the member is caught earlier, at check time.

- **Nothing checks that the action names the member.** `MUST Sign (EXACTLY t)` ties the act to the member; `MUST Sign someoneElse` does not, and is accepted. What the run does check is that the **event's** party is the member. Write `EXACTLY t`.
- **The count and measure joins are not built at all** — `ONCE SOME 2 OF … HAVE`, `ONCE sum OF amount AT LEAST rent`. Only `ONCE ALL HAVE` and `UPON EACH` parse.
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
- **A join line with no `HENCE` and no `LEST` is accepted**, and since 2026-09-08 its `WITHIN` is not idle: a deadline written only on the join line bounds each act, because otherwise nothing would ever expire and the rule could never fail. What is still true is that there is no continuation for it to fire, so what you get at the deadline is a breach rather than anything you wrote.
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
