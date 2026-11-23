# Rules that start themselves again

A regulative rule can say what happens next.
Its `HENCE` says what follows when the duty is done, and its `LEST` says what follows when it is not.
When what follows is the same rule again, the rule **starts itself again**.

That is often exactly what the law or the contract means.
Rent falls due every month, and a reminder goes out until the bill is paid.
The examples on this page share two declarations:

```l4
DECLARE Person IS ONE OF Alex, Sam
DECLARE Action IS ONE OF `pay rent`, `sign the lease`
```

Here is a rule that starts itself again:

```l4
GIVETH A DEONTIC Person Action
`monthly rent` MEANS
    PARTY Alex
    MUST `pay rent`
    WITHIN 30
    HENCE `monthly rent`
    LEST BREACH
```

When Alex pays, `monthly rent` starts again, and Alex has another 30 days.

A rule like this has to come to an end in one sense: when L4 runs it over a list of events, as `#TRACE` does, the run has to reach an answer.
`monthly rent` always does, because each new copy of the duty waits, either for Alex to pay or for 30 more days to pass, so the run always moves on to the next event.

L4 checks every rule whose `HENCE` or `LEST` leads back to itself, directly or through other rules.
It gives one of three warnings when it finds something wrong, or cannot tell:

- **"I could not check that this comes to an end"**: L4 cannot see that each copy waits.
  This is a question for you, and you can answer it with `@ends-because`.
- **"starts itself again with no time passing"**: L4 can see that no copy waits at all.
- **"starts 2 copies of itself at once"**: L4 can see that each time round, the number of copies open grows.

L4 is sure of the last two, so `@ends-because` does not silence them.
A warning never stops the file: it still checks, and its `#EVAL` and `#TRACE` lines still run.

## "I could not check that this comes to an end"

This rule sends Alex a reminder, and each reminder gives half as long as the one before:

```l4
GIVEN days IS A NUMBER
GIVETH A DEONTIC Person Action
`reminder` days MEANS
    PARTY Alex
    MUST `pay rent`
    WITHIN days
    LEST `reminder` (days DIVIDED BY 2)
```

L4 says:

```
`reminder` can start itself again: a HENCE or LEST in it leads back to `reminder`.
I could not check that this comes to an end, because the time one of its duties allows (its WITHIN) is not a number written out, and I read only a number written out there, so I cannot tell how long that time is, or whether it is more than 0 each time round.

If it does come to an end, say why on a line of its own above `reminder`, like this:

  @ends-because <your reason>

A reader can then check your reason, and L4 stops warning about it.
```

Here the warning is right to worry.
Starting with 30 days, the deadlines fall at day 30, then 45, then 52½, and so on, closer and closer together, and never past day 60.
There is always one more reminder before day 60, so nothing on or after day 60, a payment or anything else, is ever reached.

What L4 looks for is a wait it can be sure of: a deadline written as a number above 0, such as `WITHIN 7`, or as a name the same file gives to such a number (`` `grace period` MEANS 7 ``), or an event that someone has to do.
When the wait is anything else, the warning says which, and why that may not be a wait at all:

| what the rule has                                           | why L4 cannot count on it                                                |
| ----------------------------------------------------------- | ------------------------------------------------------------------------ |
| a `WITHIN` worked out from something, such as `WITHIN days` | L4 reads only a number written out, so it cannot tell how long it is     |
| a deadline counted from a fixed moment, `WITHIN … OF …`     | once that moment is past, each new copy is already late                  |
| a date, `BEFORE …`                                          | once that date is past, each new copy is already late                    |
| a window that opens `AFTER` something not written out       | it may open at a fixed moment already past                               |
| a window that opens `AFTER … OF …`, counted from a moment   | its deadline is fixed too, and once past, each new copy is already late  |
| another duty's deadline, `OF THE DEADLINE`                  | it is taken when that duty hands on, and may already be past             |
| `OF THE JOIN`                                               | L4 cannot tell when that is                                              |
| the `HENCE` after a `RECORD`                                | it goes on straight away                                                 |
| `EVERY … ONCE ALL HAVE` over a list that may be empty       | over an empty list it goes on straight away                              |
| the file may run a contract with `EVALTRACE`                | on a trace that starts again, no wait limits how many times it can start |

It can also say that a rule on the loop uses itself directly, with no duty in between, in a way it cannot check, and it names that rule, which need not be the one the warning is shown on.
Then the doubt is about that direct use, not about a `HENCE` or `LEST`, and the warning says so; `@ends-because` answers it as it answers any other "could not check".
Or it can say that the rule uses another rule passed in as an input or kept in a record, which it cannot follow.

If the rule should not go on like this, change it so that each copy waits: here, `WITHIN 7` instead of `WITHIN days`.
If it does come to an end, say why with `@ends-because`.

## Saying why it comes to an end: `@ends-because`

This rule sends Alex at most a few final reminders, each one a week shorter than the one before:

```l4
@ends-because tries drops by one at every reminder, and at 0 there are no more reminders
GIVEN tries IS A NUMBER
GIVETH A DEONTIC Person Action
`final reminders` tries MEANS
    IF tries AT MOST 0
    THEN BREACH
    ELSE PARTY Alex
         MUST `pay rent`
         WITHIN tries TIMES 7
         LEST `final reminders` (tries MINUS 1)
```

Without the first line, L4 gives the "could not check" warning, because `WITHIN tries TIMES 7` is not a number written out.
It does come to an end, and the first line says why.
With it, the warning is gone, and L4 gives an information message in its place, carrying the reason:

```
`final reminders` can start itself again: a HENCE or LEST in it leads back to `final reminders`, and I could not check that this comes to an end, because the time one of its duties allows (its WITHIN) is not a number written out, and I read only a number written out there, so I cannot tell how long that time is, or whether it is more than 0 each time round.
Its author says why it does, with the @ends-because above `final reminders`:

  tries drops by one at every reminder, and at 0 there are no more reminders

So L4 does not warn about it. That reason is what a reader should check.
```

L4 does not read the reason or check it.
The mark is your word that the rule comes to an end, and the reason is what lets someone else check your word.
That is why a reason is required, and why the message shows it.

Where to write it:

- On a line of its own above the rule: above its `GIVEN`, or directly above the line that names it.
  The [syntax reference](../syntax/README.md#ends-because) has the details.
- On the rule the warning is shown on.
  When several rules lead back to each other, the "could not check" warning is shown on the first of them in the file, and the mark goes there.
  A mark above one of the others does not count, and the warning says so and names the rule it should be on.

What it does and does not do:

- It silences "I could not check that this comes to an end" on that rule, and nothing else.
- It does not change how the rule runs.
- It does not silence the other two warnings: if one of the rules that lead back to each other carries a mark, those warnings say that it does not silence them.
- On a rule L4 can already see comes to an end, or on a rule that uses itself only directly, with no `HENCE` or `LEST` that leads back to it (a countdown, a total over a list), it changes nothing.
- On a rule L4 finds no way back to itself from, L4 sees nothing for it to explain, and warns about it.
  L4 cannot see a loop that goes through a rule kept in a record or passed in as an input, so the warning says that the mark may still be right there.

```l4
@ends-because it is only arithmetic
GIVEN rent IS A NUMBER
GIVETH A NUMBER
`late fee` rent MEANS rent TIMES 0.05
```

```
@ends-because is above `late fee`, but I find no way for `late fee` to lead back to itself, so I see nothing for the mark to explain.
The mark goes above a rule that uses itself again, directly or through other rules, or whose HENCE or LEST starts it again.
I cannot see a loop that goes through a rule kept in a record or passed in as an input: if `late fee` leads back to itself that way, the mark is where it belongs, and if not, move it to the rule it explains.
```

Every `@ends-because` gets one information message, at the mark, carrying its reason and saying what the mark did, whether or not it silenced anything.
So a reader can find every reason in a file, and see which ones L4 relied on.
On the `countdown` in the [syntax reference](../syntax/README.md#ends-because), for example, it says:

```
The @ends-because above `countdown` says why it comes to an end:

  each step moves one day nearer the end date, and the end date is fixed

`countdown` uses itself again, directly or through other rules, but not through a HENCE or LEST, and L4 gives no warning about whether a rule like that comes to an end.
So the mark changes nothing. That reason is what a reader should check.
```

A file with an error gets none of these messages until the error is fixed.

## "starts itself again with no time passing"

```l4
GIVETH A DEONTIC Person Action
`pay at once` MEANS
    PARTY Alex
    MUST `pay rent`
    WITHIN 0
    LEST `pay at once`
```

L4 says:

```
`pay at once` starts itself again with no time passing: its deadline falls at the very moment each copy starts.
So the time of each copy is up the moment it starts, and the next copy starts straight away.
Waiting does not help, because no time passes between one copy and the next, so it does not stop by itself.

To give each copy time, make its deadline fall after the moment it starts.
```

Each copy is already late when it starts, so its `LEST` starts the next one at the same moment, and so on.
No time ever passes, so nothing Alex does, at any time, is ever reached.
Here, `WITHIN 1` instead of `WITHIN 0` gives each copy a day.
L4 says the same of a permission (`MAY`) whose time runs out the moment it starts.

## "starts 2 copies of itself at once"

```l4
GIVETH A DEONTIC Person Action
`chaser` MEANS
    PARTY Alex
    MUST `pay rent`
    WITHIN 7
    LEST (`chaser` RAND `chaser`)
```

L4 says:

```
`chaser` starts 2 copies of itself at once: its LEST joins them with RAND.
So every time a deadline is missed, the number of copies open doubles.
Nothing written limits how many times round it goes.

If one copy is what you meant, start it once.
```

Each week Alex does not pay, every open duty becomes two: 2, then 4, 8, 16, and after ten missed weeks 1,024 duties are open at once, all for the same rent.

When the rule counts down to a stop, L4 says that too, and says how far the doubling can go:

```l4
GIVEN n IS A NUMBER
GIVETH A DEONTIC Person Action
`spreading chaser` n MEANS
    IF n EQUALS 0
    THEN FULFILLED
    ELSE PARTY Alex
         MUST `pay rent`
         WITHIN 7
         LEST (`spreading chaser` (n MINUS 1) RAND `spreading chaser` (n MINUS 1))
```

```
`spreading chaser` starts 2 copies of itself at once: its LEST joins them with RAND.
So every time a deadline is missed, the number of copies open doubles.
Each copy is given `n` less 1, so if `n` reaches a stop, this comes to an end, but only after the number open has doubled at every step down: as many as 2 to the power of `n`.

If one copy is what you meant, start it once.
```

L4 reads that countdown as written: it does not check that `n` really reaches 0.
When `n` drops by 2 at each step, it says "as many as 2 to the power of (`n` divided by 2)".

When the copies are of several rules that lead back to each other, the warning is shown on the rule whose `HENCE` or `LEST` starts them, and it names the rules on a line of its own.

## Limits

- These checks look only at rules whose `HENCE` or `LEST` leads back to themselves.
  A rule that uses itself only directly, such as a countdown or a total over a list, draws none of these warnings, whether or not it stops.
  See [Infinite loop detected](../errors/README.md#infinite-loop-detected) for what happens when one does not stop.
- A rule that uses itself directly and also has a `HENCE` or `LEST` that leads back to itself is checked, and its direct uses count too: L4 may say that it could not check that it comes to an end.
- L4 cannot see a loop that goes through a rule kept in a record or passed in as an input.
  An obligation that leads back to itself that way draws no warning.
- A warning does not stop a run, and a rule L4 warns about may not give an answer when you run it.
  A run that cannot go on is stopped with an error, but not always soon.
  `pay at once` is stopped straight away, and `chaser` once more than 10,000 duties are open at once (see [More obligations were open at once than the limit](../errors/README.md#more-obligations-were-open-at-once-than-the-limit)).
  `reminder` above, run with `#TRACE`, slows down as it goes, and can run for longer than you will want to wait before L4 stops it at 10,000,000 steps (see [It took more than so many steps](../errors/README.md#it-took-more-than-so-many-steps)); `--max-steps 20000` stops it in about a second.
- L4 reads the rule as written, not as it will be run.
  A `WITHIN` worked out from an input counts as "not a number written out" even if every input you will ever give it is positive.
  That is what `@ends-because` is for.
- "starts 2 copies at once" is said only when the copies are written side by side in the `HENCE` or `LEST`, joined with `RAND` or `ROR`.
  A rule that hands itself to another rule, which then uses it twice, can double in the same way and draws no warning.
- When a rule has more than one `HENCE` or `LEST` that starts copies at once, the warning names only the first of them.
- A file with an error draws none of these warnings, and none of the information messages, until the error is fixed.
