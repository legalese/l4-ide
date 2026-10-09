# Telling a rule what you know, and letting it presume the rest

**Status:** a draft of a future page under `doc/tutorials/`, written 2026-10-09 against a design that is not yet built.
It sits under `specs/todo/` until the behaviour it teaches lands; each section below says what runs today and what does not.
The design it teaches is `CONTRACT.md`, beside this file, and the measurements behind both are `../PRESUMPTION-SCENARIOS.md`.
Nothing on this page describes shipped behaviour unless the section says so.

---

## The law assumes things, until someone shows otherwise

Most of the time, when a rule talks about a person, it is talking about an adult who can make their own decisions.
The law does not stop to prove that every time.
It presumes it, and lets the presumption be knocked down: if it turns out the person is a child, or lacks capacity, different rules take over.

L4 has a word for that kind of assumption.
Here is a rule about who may sign a contract:

```l4
§ `Capacity`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

GIVEN `is adult` IS A BOOLEAN
GIVETH A BOOLEAN
`may contract` MEANS `is adult` AND `has capacity`
```

`has capacity` is a yes-or-no fact, and `TYPICALLY TRUE` says what to presume about it when nobody has said.
The rule still works if you tell it `has capacity` is false.
It just does not need to be told when the ordinary case holds.

**This runs today.** Ask the rule with only `is adult` and it answers `TRUE`, and tells you what the answer rests on:

```json
{ "result": { "value": true }, "presumed": ["has capacity"] }
```

That second line is the point.
An answer that rests on a presumption says so, naming the fact that was presumed.
A presumption the rule never needed is not listed: if `is adult` is false, the rule stops there, and `has capacity` was never consulted.

## Two ways to ask: presume for me, or tell me what you would need

Sometimes you want the answer, and you are happy to be told which assumptions it rests on.
Sometimes you want no assumptions at all, because a person is about to act on the answer, and you would rather be told what is still missing.

L4 calls these **soft** and **hard** presumption.
Soft is the default: presumptions apply, and the answer lists them.
Hard applies none: a fact that was left out, and has a presumed value, is treated as simply left out.

**This runs today**, as `l4 batch --presumption hard` and as `"presumption": "hard"` in a request to the decision service.
What hard mode does when it meets a presumed fact is changing, though.
Today it refuses the request as soon as it sees that a presumed fact was left out, whether or not the rule would ever have needed it (`../PRESUMPTION-SCENARIOS.md` §2.3 measures this: a rule with a presumption at the very end of its reasoning refuses every request, including ones whose answer never got that far).
The design this page teaches makes hard mode wait: it refuses only when the rule actually reaches the presumed fact, and then says which one it would have had to presume.
Until that lands, read a hard-mode refusal as "this rule has a presumption somewhere", not as "your answer would have rested on one".

## Door number two: answering without saying which

Here is a rule that wants to know your marital status, and a ladder picture of it.
The picture is `l4 render --format text`, exactly as the tool prints it today:

```l4
GIVEN married  IS A BOOLEAN
      single   IS A BOOLEAN
      divorced IS A BOOLEAN
      widowed  IS A BOOLEAN
GIVETH A BOOLEAN
`eligible` MEANS married OR `unmarried`
  WHERE
    `unmarried` MEANS single OR divorced OR widowed
```

```text
• Eligible holds if:
    any of the following is true:
    - married
    - unmarried
    where:
    - Unmarried means:
        any of the following is true:
        - single
        - divorced
        - widowed
```

Four facts are asked for.
But the rule has a named step in the middle, `unmarried`, and for the rule's purposes that step is all that matters.
Whether you are single, divorced or widowed is none of its business.

In the interactive ladder you can fold `unmarried` into one box and click that box to say "yes, this one", without touching the three facts under it.
The circuit closes through the folded box, and the three facts stay unknown.
That is door number two: you pick the door, and you do not say what is behind it.

**The ladder does this today.** Folding a group and giving it a value is built (`ladder-diagrams-2026/DESIGN.md` §19), and the folded box carries the value while its contents stay unknown.

**Asking the rule the same way is not built yet.** The design lets you say it in a request as well as in a picture.
Beside the facts you supply, you would name the step:

```json
{ "arguments": {}, "assertions": { "unmarried": true } }
```

and the answer would say what it rested on, in a list beside `presumed`:

```json
{ "result": { "value": true }, "asserted": ["unmarried"] }
```

Three things to know about this, once it lands.

First, an assertion is a fact you are giving, not a guess the rule is making.
So hard mode leaves it alone: hard withdraws presumptions, and an assertion is not one.

Second, an assertion wins.
If you assert `unmarried` and also say `single` is false, the rule takes your word for `unmarried` and does not consult `single`, exactly as the folded box in the picture does not consult what is under it.
The answer lists `unmarried` under `asserted` so nobody can miss that it was told, not worked out.

Third, only a step with a name can be asserted.
`single OR divorced OR widowed` written out in the middle of a rule has no door to point at; giving it the name `unmarried` is what makes it one.
If you want a step to be assertable, name it.

## Steps a rule must work out for itself

Some named steps are the rule's conclusion, or close to it, and it would be wrong to let anyone simply assert them.
A rule that decides whether a person is guilty must not accept "guilty: yes" as an input.

The design is open by default: any named step may be asserted unless the rule's author says otherwise.
The author says otherwise with one annotation on the step:

```l4
@nonassertable
`is guilty` MEANS `did the act` AND `had the intent` AND NOT `has a defence`
```

A request that asserts `is guilty` would then be refused by name, before the rule runs: this step is a conclusion, and can only be worked out.
The rule's own final answer can never be asserted, with or without the annotation.

**Not built yet.** Nothing today refuses an assertion, because nothing today accepts one.
The default-open choice, and this annotation as its opt-out, were ruled on 2026-10-09 (`../PRESUMPTION-SCENARIOS.md` §7).

Why open by default?
Because the ladder already works that way, and because it makes the author write down the one thing worth writing: that a step is a conclusion.
The risk of an author forgetting is real, and the `asserted` list is the answer to it: an assertion can never happen silently, since the answer always says what was asserted.

## The author's side: "typically, one of those three is true"

The two sections above are about the person asking.
The author of the rule may also want to presume something about a named step, not just about an input.
"Unless we hear otherwise, assume the person is unmarried" is a presumption about `unmarried` as a whole, not about any one of the three facts under it.

**What works today** is to make the presumption an input and read it only where the facts run out.
Here a person's birthdate may be missing, and the rule presumes adulthood only then:

```l4
GIVEN person IS A Person
      asat   IS A DATE
      `presumed adult` IS A BOOLEAN TYPICALLY TRUE
GIVETH A BOOLEAN
`adult` MEANS
  CONSIDER person's birthdate
    WHEN JUST b  THEN `age at` b asat AT LEAST 21
    WHEN NOTHING THEN `presumed adult`
```

With a known birthdate the presumption is never read and never listed.
With no birthdate the answer is `TRUE` and `presumed` names `presumed adult`.
`../PRESUMPTION-SCENARIOS.md` §2.2 shows the rows.

One trap is worth knowing.
If you write `WHEN NOTHING THEN TRUE` instead, you have made the same presumption, but the answer will not say so: `TRUE` written in a rule is a value, and nothing marks it as a presumption (§2.7 there measures it).
Name the presumption as an input, and it is reported.

**Proposed, not ruled**, is to write the presumption on the step itself:

```l4
`unmarried` MEANS single OR divorced OR widowed TYPICALLY TRUE
```

meaning: work it out from the three facts when they decide it, presume `TRUE` when they do not, and take an assertion over both.
This does not parse today, and a ruling from 2026-10-01 (T1 in the TYPICALLY spec) says a presumption on a `MEANS` is an error.
`CONTRACT.md` §7 sets out what it would mean if that ruling were amended.
Until then, the input form above is the way to say it.

## "I don't know" is not the same as "I didn't say"

One last distinction, because it decides what hard mode does with a missing fact.

Leaving a fact out of a request means you did not say.
Sending it as `null` means you are saying there is no value: the person has no recorded birthdate, say.
L4 treats the second as a fact and the first as a gap.
A gap may be filled by a presumption, under soft, and is refused under hard; a `null` is neither presumed nor refused, and the rule goes on with "no birthdate".

**This runs today**, and the rows in `../PRESUMPTION-SCENARIOS.md` §2.2 show both columns side by side.
Spreadsheet users take note: an empty cell in a CSV is a gap, not a `null`, so a CSV cannot say "I don't know" at all.

## Where each thing stands

| you want to                            | how                                            | status                                |
| -------------------------------------- | ---------------------------------------------- | ------------------------------------- |
| presume a fact when nobody supplies it | `TYPICALLY` on an input                        | built                                 |
| see what an answer rests on            | `presumed` in the answer                       | built                                 |
| ask with no presumptions               | `--presumption hard` / `"presumption": "hard"` | built; refuses too early, see §2      |
| pick door two in a picture             | fold the group, click the box                  | built                                 |
| pick door two in a request             | `assertions` beside `arguments`                | designed, ruled 2026-10-09, not built |
| see what was asserted                  | `asserted` in the answer                       | same                                  |
| keep a conclusion from being asserted  | `@nonassertable` on the step                   | same                                  |
| presume a named step                   | `TYPICALLY` on a `MEANS`                       | proposed, not ruled                   |
| say "I don't know"                     | send `null`                                    | built, except from CSV                |
