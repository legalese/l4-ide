# Telling a rule what you know, and letting it presume the rest

**Status:** a draft of a future page under `doc/tutorials/`, written 2026-10-09 and revised the same day after two adversarial reviews, against a design that is not yet built.
It sits under `specs/todo/` until the behaviour it teaches lands; each section below says what runs today and what does not.
The design it teaches is `CONTRACT.md`, beside this file, and the measurements behind both are `../PRESUMPTION-SCENARIOS.md`.
Nothing on this page describes shipped behaviour unless the section says so.
For reviewers: the mentions of rulings, dates and specification files are here so the page can be checked against the design, and they come out when the page moves to `doc/`, where the reader has never heard of them.
This page assumes you have read [Your First L4 File](../../../doc/tutorials/getting-started/first-l4-file.md) and nothing else.

---

## The law presumes things, until someone shows otherwise

When the law deals with an adult, it starts from the position that the person can decide things for themselves.
It does not stop to prove that every time.
It presumes it, and lets the presumption be knocked down: if it is shown that an impairment of the mind leaves the person unable to understand, retain, weigh or communicate the decision, different rules take over.
(The Mental Capacity Acts of England and Wales and of Singapore both open with that presumption.)

L4 has a word for that kind of assumption.
Here is a small rule a form might use to decide whether Alex can answer for himself or whether it should ask a guardian instead:

```l4
§ `Capacity`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

@export
GIVEN `is adult` IS A BOOLEAN
GIVETH A BOOLEAN
`can decide alone` MEANS `is adult` AND `has capacity`
```

Two kinds of line need a word.
The line starting `§` is a section heading, and a fact written under it with `GIVEN` is one that every rule in the section may use without each rule asking for it again; [What a Section Needs to Know](../../../doc/tutorials/section-given/what-a-section-needs-to-know.md) is the page about that.
`@export` marks the rule as one that can be published for people and programs to ask.

`has capacity` is a yes-or-no fact, what programming language theory calls a **"Boolean"**, and `TYPICALLY TRUE` says what to presume about it when nobody has said.
`is adult` is a fact the rule is given with no presumption, because whether Alex is an adult is something the form will know.
The rule still works if you tell it `has capacity` is false.
It just does not need to be told when the ordinary case holds.

**This runs today.** The `l4 batch` tool asks a rule many questions at once, one per row of a file.
Each question is written in JavaScript Object Notation (**JSON**), the plain text format that web programs exchange: the name on the left of each colon is called a **key**, and the value is on the right.
Asked with only `is adult`, the rule answers `true` and tells you what the answer rests on.
This is what it prints, one line per question, with the question repeated under `input` (the line is shown here folded for width):

```json
{
  "diagnostics": [],
  "input": { "is adult": true },
  "output": [{ "result": true, "trace": null }],
  "presumed": ["has capacity"],
  "status": "success"
}
```

That `presumed` list is the point.
An answer that rests on a presumption says so, naming the fact that was presumed.
A presumption the rule never needed is not listed: asked with `is adult` false, the rule stops there, answers `false`, and `presumed` is empty, because `has capacity` was never consulted.

The same rule can be published as a service that people and programs can ask over the network; L4 calls that the decision service, and one question put to it is a **request**.
Its answers carry the same `presumed` list.

## Two ways to ask: presume for me, or tell me what you would need

Sometimes you want the answer, and you are happy to be told which assumptions it rests on.
Sometimes you want no assumptions at all, because a person is about to act on the answer, and you would rather be told what is still missing.

L4 calls these **soft** and **hard** presumption.
Soft is the default: presumptions apply, and the answer lists them.
Hard applies none: a fact that was left out, and has a presumed value, is treated as simply left out.

**This runs today**, as `l4 batch --presumption hard` and as `"presumption": "hard"` in a request to the decision service.
What hard mode does when it meets a presumed fact is still being decided.
Today, `l4 batch` and most requests to the service refuse as soon as they see that a presumed fact was left out, whether or not the rule would ever have needed it; the row above with `is adult` false is refused under hard, naming `has capacity`, although the rule never reaches it (`../PRESUMPTION-SCENARIOS.md` §2.3 measures this on a longer rule).
The change this page assumes, proposed and not yet ruled, makes a left-out fact wait: the rule is refused only when it actually reaches the fact, and the refusal then names it.
Until that is settled and built, read a hard-mode refusal as "this rule has a presumption somewhere", not as "your answer would have rested on one".

## Door number two: answering without saying which

L4 can draw a rule as a **ladder diagram**, the picture electricians use for control circuits.
Each yes-or-no fact is a switch, facts that must all hold sit in a row, facts of which any one will do sit in parallel, and the rule's answer is whether current can get from one side of the picture to the other.
The L4 editor shows it as the rule's decision graph.
The `l4 render` tool can print the same rule as a text outline instead, and that is what is quoted below, since a page cannot carry the live picture.

Here is a rule that wants to know Alex's marital status.
The `WHERE` at the end lets a rule name a step of its own working, for use inside that rule only:

```l4
@export
GIVEN married  IS A BOOLEAN
      single   IS A BOOLEAN
      divorced IS A BOOLEAN
      widowed  IS A BOOLEAN
GIVETH A BOOLEAN
`eligible` MEANS married OR `unmarried`
  WHERE
    `unmarried` MEANS single OR divorced OR widowed
```

and, with the rule saved as `doors.l4`, the whole of what `l4 render doors.l4 --format text` prints for it today (the title is the file's name):

```text
Doors
=====


Provisions

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
Whether Alex is single, divorced or widowed is none of its business.

In the editor's ladder, `unmarried` is drawn as one box, because it is a step with a name.
You can click that box to say "yes, this one", and current flows through it while the three facts under it stay unknown; you can also open the box to see the three facts, if you want to answer at that level instead.
That is door number two: you pick the door, and you do not say what is behind it.

**The ladder does this today.** Giving a value to a named step drawn as one box is built, and so is opening it (`ladder-diagrams-2026/DESIGN.md` §19, `WHERE-INLINING-SPEC.md` §7).

**Asking the rule the same way is not built yet.** The design lets a request say it as well as a picture.
Beside the facts you supply, you would name the step.
The key `assertions` is the spelling the design assumes; it is not yet ruled:

```json
{ "arguments": { "married": false }, "assertions": { "unmarried": true } }
```

and the answer would say what it rested on, in a list beside `presumed`:

```json
{ "result": { "value": true }, "presumed": [], "asserted": ["unmarried"] }
```

Three things to know about this, once it lands.

First, an assertion is a fact you are giving, not a guess the rule is making.
So the design has hard mode leave it alone: hard withdraws presumptions, and an assertion is not one.

Second, an assertion wins.
Suppose you say all three of `single`, `divorced` and `widowed` are false, and also assert `unmarried` is true.
The rule takes your word for `unmarried` and does not consult the three, exactly as the box in the picture, once you have given it a value, does not consult what is under it.
The answer lists `unmarried` under `asserted`, so nobody can miss that it was told, not worked out.
(Whether the rule should instead complain about the contradiction is a question the design puts off, as the ladder's design did before it.)

Third, only a step with a name can be asserted.
`single OR divorced OR widowed` written out in the middle of a rule has no door to point at; giving it the name `unmarried` is what makes one.
The design assumes, and has not yet had ruled, that in this first version the step must also take no inputs of its own, be written in the same file as the rule, and be the only step of that name in the file.
If you want a step to be assertable, name it, once.

One more thing the example above quietly depends on.
Today, in `l4 batch` and most requests to the service, a fact left out of a request with no presumed value is refused before the rule runs, so the three facts under `unmarried` would have to be sent even though the rule never reaches them.
The design changes that too, in soft and hard mode alike: a fact left out is refused only when the rule reaches it.
That change is proposed and not yet ruled, and without it door number two cannot be kept shut.

## Steps a rule must work out for itself

Some named steps are the rule's conclusion, or close to it, and it would be wrong to let whoever is asking simply assert them.
A rule that works out whether an offence is made out should not take "made out: yes" from the person asking.
(In a courtroom the law does let one person say exactly that, by pleading guilty, and surrounds it with safeguards: who may say it, and that what they admit really amounts to the offence.
The first is a question of who is asking, which is for the people running the service to control; the second is the contradiction check this design puts off.)

The design is open by default: a named step may be asserted unless the rule's author says otherwise.
The author says otherwise with one annotation on the step:

```l4
@nonassertable
`offence made out` MEANS `did the act` AND `had the intent` AND NOT `has a defence`
```

A request that asserts `offence made out` would then be refused by name, before the rule runs: this step is a conclusion, and can only be worked out.
The rule's own final answer can never be asserted in L4's own evaluators, with or without the annotation.

**Not built yet.** Nothing today refuses an assertion, because nothing today accepts one.
Open by default, with this annotation as the opt-out, is what Meng ruled in chat on 2026-10-09 (`../PRESUMPTION-SCENARIOS.md` §7); it is recorded in the specification that owns it (`UNKNOWN-EVALUATION-SPEC.md` §5), so by this repository's rules it is decided.

Why open by default?
Because the ladder already works that way, and because it makes the author write down the one thing worth writing: that a step is a conclusion.
The risk of an author forgetting is real, and the `asserted` list is the answer to it: once built, an assertion the rule relied on is always named in the answer, so it cannot pass unnoticed.

## The author's side: "typically, one of those three is true"

The two sections above are about the person asking.
The author of the rule may also want to presume something about a named step, not just about a fact.
"Unless we hear otherwise, treat the person as an adult" is a presumption about adulthood as a whole, and the facts that would settle it may be missing.

**What works today** is to make the presumption a fact of its own, and read it only where the other facts run out.
Here Alex's date of birth may be missing.
`MAYBE DATE` says so: the field holds either a date, written `JUST` the date, or no date at all, written `NOTHING`.
`CONSIDER` looks at which of the two it is and takes the matching branch.
`DATE_YEAR` picks the year out of a date, and `MINUS` and `AT LEAST` read as they sound, so the rule counts age in whole years; the exact-birthday version is in the measurements file, and gives the same answers for Alex:

```l4
DECLARE Person HAS
  name      IS A STRING
  birthdate IS A MAYBE DATE

@export
GIVEN alex IS A Person
      asat IS A DATE
      `presumed adult` IS A BOOLEAN TYPICALLY TRUE
GIVETH A BOOLEAN
`adult` MEANS
  CONSIDER alex's birthdate
    WHEN JUST b  THEN DATE_YEAR asat MINUS DATE_YEAR b AT LEAST 21
    WHEN NOTHING THEN `presumed adult`
```

With a known birthdate the presumption is never read and never listed.
With the birthdate sent as no date, the answer is `true` and `presumed` names `presumed adult`.
With the birthdate left out altogether, `presumed` names both `alex.birthdate`, because treating a left-out date as no date is itself a presumption, and `presumed adult`.
`../PRESUMPTION-SCENARIOS.md` §2.2 shows the same rows on a longer version of this rule.

One trap is worth knowing.
If you write `WHEN NOTHING THEN TRUE` instead, you have made the same presumption, but the answer will not say so: `TRUE` written in a rule is a value, and nothing marks it as a presumption (§2.7 there measures it).
Name the presumption as a fact, and it is reported.

**Proposed, not ruled**, is to write the presumption on the step itself:

```l4
`unmarried` MEANS single OR divorced OR widowed TYPICALLY TRUE
```

meaning: work it out from the three facts when they decide it, presume `TRUE` when they do not, and take an assertion over both.
This does not parse today, and no ruling covers it either way (the nearest, T1 in the TYPICALLY specification, is about a field of a record that has a `MEANS` of its own).
`CONTRACT.md` §7 sets out what it would mean.
Until then, the form above is the way to say it.

## "No value" is not the same as "I didn't say"

One last distinction, because it decides what a rule does with a missing fact.

Leaving a fact out of a request means you did not say.
Sending it as no value at all, which JSON spells [**`null`**](https://en.wikipedia.org/wiki/JSON), means you are saying the value is not known.
L4 treats the two differently.
A fact left out is a gap: under soft it may be filled by a presumption, and under hard it is refused.
A fact sent as `null` is a statement.
On a fact that is allowed to have no value, a `MAYBE` like Alex's birthdate, the rule goes on with "no date": the date itself is not presumed, and whatever the rule presumes next, such as `presumed adult`, is listed as usual.
On any other fact, in `l4 batch` and in a single request to the service, `null` is refused by name, because the rule needs a value and you have said you do not have one; `l4 batch` prints `Field 'is adult' is null, which means the value is not known: supply a value`.
(Two other ways of asking the service do not refuse it yet, and that difference is a known defect, smucclaw/l4-ide#1021.)

**This runs today**, and the rows in `../PRESUMPTION-SCENARIOS.md` §2.2 and §2.6 show the columns side by side.
Spreadsheet users take note: in a comma-separated values (CSV) file an empty cell is a gap, not a `null`, so a CSV cannot say "the value is not known" at all.

## Where each thing stands

| you want to                                                                | how                                            | status                                                                                                |
| -------------------------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| presume a fact when nobody supplies it                                     | `TYPICALLY` on a fact                          | built                                                                                                 |
| see what an answer rests on                                                | `presumed` in the answer                       | built                                                                                                 |
| ask with no presumptions                                                   | `--presumption hard` / `"presumption": "hard"` | built; in `l4 batch` and most service requests it refuses before the rule runs, see "Two ways to ask" |
| have a left-out fact refused only when the rule reaches it, in either mode | the design's lazy treatment of gaps            | proposed, not ruled                                                                                   |
| pick door two in a picture                                                 | click the named step's box                     | built                                                                                                 |
| pick door two in a request                                                 | `assertions` beside `arguments`                | ruled 2026-10-09; the key's spelling and the limits on which steps qualify are assumed; not built     |
| see what was asserted                                                      | `asserted` in the answer                       | ruled 2026-10-09; not built                                                                           |
| keep a conclusion from being asserted                                      | `@nonassertable` on the step                   | ruled 2026-10-09; not built                                                                           |
| presume a named step                                                       | `TYPICALLY` on a `MEANS`                       | proposed, not ruled                                                                                   |
| say "the value is not known"                                               | send `null`                                    | built in `l4 batch` and single service requests, except from CSV                                      |
