# When a Rule Cannot Answer

Teaching a rule to decline — and telling a declined answer apart from the four things that look like one.

**Prerequisites:** the [Foundation Course](../../courses/foundation/README.md), or at the least [Your First L4 File](../getting-started/first-l4-file.md); and [Testing Your Rules](../getting-started/testing-your-rules.md), which is where `#ASSERT` is introduced. Step 8 of this page picks `#ASSERT` up again and assumes you have met it once.

**Companion file:** [when-a-rule-cannot-answer.l4](when-a-rule-cannot-answer.l4). Every example on this page that runs today is in that file, the refusals included, and running it produces the screens in Step 3 — the thing this page is about, on your own machine, rather than on trust. Two short italic notes further down mark additions that are proposed and have not landed. One screen, in Step 4, no companion can run; that step says so at the point it arises, and says why.

**How to run it.** Save the companion file, open a terminal in the folder that holds it, and type one line:

```bash
l4 run when-a-rule-cannot-answer.l4
```

Every screen quoted on this page came out of that command. Where a page below says "run the file", that is the line it means. If you have not yet installed the `l4` command-line interface (CLI), [Using the l4 CLI](../getting-started/l4-cli.md) says how to get it; in the editor extension you can instead hover over any `#EVAL` line and read the same answer where it sits.

---

## Before you start: the words this page builds on

A rule in L4 is a question with blanks in it. It is told some facts about the case in front of it — those facts are the rule's **"inputs"**, and they are the names listed after `GIVEN` — and from them it works out one answer, the rule's **"output"**, whose kind of thing is named after `GIVETH`. Given these inputs, a rule gives an output. (Some files spell `GIVETH` as `GIVES`. They are the same word.)

Here is one, with a person in it. A law-school problem gives its hypothetical person a name, and so does this page: meet Alex.

```l4
DECLARE Person
    HAS name IS A STRING
        age IS A NUMBER

GIVEN alex IS A Person
GIVETH A BOOLEAN
`is over 18` alex MEANS alex's age AT LEAST 18

`Alex, aged 17` MEANS Person WITH name IS "Alex", age IS 17

#EVAL `is over 18` `Alex, aged 17`
```

`DECLARE` says what kind of thing a `Person` is: a record with two named fields, a name that is text and an age that is a number. The rule's one input is `alex`, a whole person. Its output is a yes-or-no answer. `#EVAL` is an instruction to L4 — "work this out and print the answer" — and is not part of any rule. Run the file and that instruction prints:

```
Result:
  FALSE
```

Three more pieces you will meet below, which you can take on trust as you go: `MEANS` gives a rule its body; `BRANCH` tries each `IF` in turn and takes the first one that holds, falling through to `OTHERWISE` if none does; and `#ASSERT` is an instruction saying that something must hold, so that running the file checks it and reports.

---

## What You'll Build

One real dollar figure from one real regulation, encoded so that it answers for the dates the rule reaches and visibly declines for the dates it does not — then four look-alike cases, side by side, so that you can say which kind of no-answer you are looking at.

---

## Step 1: A question with no answer

Alex is a paralegal, reconstructing a company's fundraising history, and needs one figure. On 1 January 2016, how much could that company have raised from the public under Regulation Crowdfunding over the twelve months that followed?

Regulation Crowdfunding — part 227 of title 17 of the Code of Federal Regulations (CFR), the Securities and Exchange Commission (SEC) rules that let a company sell securities to ordinary members of the public over the internet — commenced on **16 May 2016**. On 1 January 2016 it did not exist, so there was no offering limit. Anyone reconstructing a past transaction asks questions with past dates in them, so a system that takes a rule date as one of its inputs will be asked Alex's question sooner or later, and it has to do something.

Three names from that regulation turn up in the examples below, so here they are once. The company raising the money is the **"issuer"**. It is not allowed to raise directly from the public: it must go through a funding portal or a broker, and the regulation calls that firm the **"intermediary"**. The offering statement the issuer files with the SEC before it raises is **"Form C"**. Keep those three in mind and the examples read as the regulation reads.

Here is what a careless encoding does. The offering limit has had three regimes — $1,000,000 as adopted, $1,070,000 after the 2017 inflation adjustment, $5,000,000 after the 2021 amendments — and the oldest is used for every earlier date as well:

```l4
@ref 17 CFR 227.100(a)(1) — the offering maximum, encoded without a floor
GIVEN `rule date` IS A DATE
GIVETH A NUMBER
`unfloored offering maximum` MEANS
    BRANCH
       IF `rule date` AT LEAST Date 15 3 2021 THEN 5000000
       IF `rule date` AT LEAST Date 12 4 2017 THEN 1070000
       OTHERWISE 1000000

#EVAL `unfloored offering maximum` (Date 1 1 2016)
```

The rule's one input is the rule date; its output is a number. Four smaller pieces, in case they are new. `@ref` is the citation line: it attaches a source to the rule beneath it and does not change what the rule works out. `Date 15 3 2021` is 15 March 2021 — day, month, year — and `AT LEAST` compares two dates. Both come from the `daydate` library, which the companion file brings in alongside the prelude. The **prelude** is the small set of definitions almost every L4 file starts with, brought in by writing `IMPORT prelude` at the top of the file.

Run it and the machine is perfectly confident:

```
Result:
  1000000
```

That is a real figure from the real rule. It is not the figure for that day, because there is no figure for that day.

Three answers are available to a system that will not admit this, each wrong in its own way:

| The answer                    | Where it comes from                               | What goes wrong                                                                                                                                                             |
| ----------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **0**                         | a numeric default, or an empty database column    | Arithmetic carries on. A $600,000 raising now exceeds the limit, so the report says the offering was not permitted — a legal conclusion about a rule that did not exist.    |
| **"unknown, please tell me"** | treating the figure as a fact awaiting supply     | The web form asks Alex for the Regulation Crowdfunding offering limit on 1 January 2016. Nobody can supply it. It is not a fact about this case; it is a hole in the model. |
| **$1,000,000**                | the oldest encoded regime, used for earlier dates | The most dangerous of the three, because it looks right. A confident, sourced, wrong number is the one that reaches a client.                                               |

The honest answer is a fourth one: **there is no answer, and here is the sentence saying why.** That is what `REFUSE` is for.

---

## Step 2: Say so, in the file

Write the refusal once, as a definition of its own, and let the definition's name be the sentence you want the reader to see:

```l4
@ref 80 FR 71388 (Rel. 33-9974) — 17 CFR part 227 commences on 2016-05-16
GIVETH A NUMBER
`no Regulation Crowdfunding figure exists before commencement on 2016-05-16` MEANS
    REFUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"
```

`REFUSE` takes a message in quotation marks. The message has to be written out in full — it cannot be built up out of the case's own values — so the sentences an encoding can produce are fixed when it is drafted, and can be read off the page by anyone reviewing the file.

The citation line above it says where the commencement date comes from. `80 FR 71388` is volume 80, page 71388 of the Federal Register (FR), the daily journal in which the United States government publishes its rules; `Rel. 33-9974` is the SEC's own number for the release that adopted this one. A reader who doubts the date has enough there to go and check it, which is the whole job of an `@ref`.

Now the rule itself, with a floor under its oldest arm:

```l4
@ref 17 CFR 227.100(a)(1) — offering maximum in a 12-month period
GIVEN `rule date` IS A DATE
GIVETH A NUMBER
`offering maximum in a 12-month period` MEANS
    BRANCH
       IF `rule date` AT LEAST Date 15 3 2021 THEN 5000000
       IF `rule date` AT LEAST Date 12 4 2017 THEN 1070000
       IF `rule date` AT LEAST Date 16 5 2016 THEN 1000000
       OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

Four arms: three figures and a refusal. The refusal sits where a number would go, and it can, because `REFUSE` stands wherever a value stands, whatever kind of thing the rule answers with.

That sentence is about the word `REFUSE` itself, and it is worth being exact about what it does not say. A refusal you have _named_, as this one is, takes the single kind of thing its own `GIVETH` line gives it: this one says `GIVETH A NUMBER`, so this name can be used by rules that answer with a number, and not by a rule that answers yes-or-no. Writing one name that serves rules of both kinds is possible, but it is spelled differently, and it is the last section of this page.

That is the house style, and it is what makes refusals readable months later:

- **one named definition per refusal**, rather than a bare `REFUSE` buried inside an arm;
- **the name is the message**, so the `OTHERWISE` line reads as a sentence and not as a puzzle;
- **an `@ref` above it** saying why the encoding stops here — not what the refusal says, but on what authority you are entitled to say it;
- **every rule that needs it uses the name**, so a refusal appearing in six places is one thing to review, and changing what it says changes it in all six.

Those four are what to look for when you open somebody else's file and want to know whether its refusals were written with care.

---

## Step 3: What you see when you run it

Ask for 1 June 2016, a date the rule reaches, and you get `1000000`. Ask for 1 January 2016, the date Alex actually needs, and the result is not a number, not a zero, and not a blank:

```
Result:
  The model refuses to answer:
    no Regulation Crowdfunding figure exists before commencement on 2016-05-16
```

That is the fifth screen the companion file produces. Run it and you will see this one and its `1000000` neighbour one after the other.

The same thing reaches a program in a shape a program can act on. When L4 is asked for its results as JavaScript Object Notation (JSON) — the text format programs use to hand each other structured data — that instruction comes back as:

```json
{
  "kind": "refused",
  "range": "when-a-rule-cannot-answer.l4:73:1-62",
  "reason": "no Regulation Crowdfunding figure exists before commencement on 2016-05-16",
  "value": null
}
```

Four lines, and each says something. `"kind": "refused"` is the outcome, and it is its own outcome, neither a value nor a mistake. `"reason"` is the sentence the author wrote. `"range"` says where in the file the question was asked — the file's name, then the line, then the columns that instruction runs across; line 73 of the companion file is the `#EVAL` that asks for 1 January 2016. And `"value": null` is the important part: `null` is what this format writes when there is nothing there, so the program on the other end is handed no figure at all rather than a plausible-looking substitute for one.

Every place a refusal can surface is what this page calls **the boundary**: the outside edge where a person or another program meets the rules. That includes the screen, the web form, the command line (the terminal window where you ran `l4 run` at the top of this page), an instruction such as `#EVAL`, and the rules published as a service that people and programs can ask. Inside the rules, nothing sees a refusal at all. Step 6 shows why that matters so much.

That screen is an answer, not a breakdown. The rule ran, reached a point its author had marked, and stopped there deliberately. Nor is it a value: not zero, not `FALSE`, not "unknown", not an empty box. If it were zero, Alex would be entitled to act on zero; Alex is not entitled to act on this at all. Take the sentence at face value, and either ask a different question or ask a person.

### Telling it apart from a rule that is broken

A refusal is a correct outcome of a correct file. A mistake in the rules is not, and the two arrive on the same screen, so it is worth seeing one of each. Here is a mistake: the `OTHERWISE` arm of that same rule was written to use a name the file never defines — a typo, or a rule somebody meant to write and did not.

```l4
`offering maximum in a 12-month period` MEANS
    BRANCH
       IF `rule date` AT LEAST Date 15 3 2021 THEN 5000000
       OTHERWISE `the offering maximum before 2021`
```

That one is deliberately wrong, and so it is not in the companion file: a companion that would not run is a poor advertisement. Running it prints, instead of any result:

```
  Severity: DiagnosticSeverity_Error
  Message:
    I could not find a definition for the identifier

      `the offering maximum before 2021`

    which I have inferred to be of type:

      NUMBER
```

Set the two side by side and they are plainly different things, in three ways you can check without knowing anything about the rule in question.

| A refusal                                                                                      | A mistake in the rules                                                 |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| begins `The model refuses to answer:`, then the author's own sentence                          | says something else entirely, in L4's words rather than the author's   |
| marked as a warning; the run finishes, and every other answer in the file is reported as usual | marked `DiagnosticSeverity_Error`, and the run counts as having failed |
| the file is right; the case is outside it                                                      | the file is wrong, and somebody has to change it                       |

The first line is the reliable one. Anything that does not begin `The model refuses to answer:` is not a refusal, whatever else it says and however much it looks like a sentence somebody wrote. A refusal is to be recorded and passed on; a mistake is to be reported to whoever maintains the file, and the further it travels as though it were a considered boundary, the longer the actual defect goes unfixed.

**When you meet a `REFUSE` in a file,** the author is telling you where this model stops. That is a claim about the encoding, not about the law: it does not say the law is silent, only that this file will not be what tells you.

**When you meet a refusal in a result,** you have not been told "no", and you have not been told "not known yet". The system declined. What happens next is outside the system: either the question is malformed, or the model needs extending.

If one of these reaches a member of the public in the course of your work, the sentence after the colon is the one to record and to pass on, word for word — it was written by a person in advance, and it is the only account there is of why the rules stopped. Do not fill the gap by hand out of the same model; it has told you it has nothing to say on the point. Whether the case gets answered another way is a judgement for whoever owns the file and the matter. The rules have not decided it.

The distinction reaches the generated form and the published service too. **A refusal never appears as a question on the form, and no program can be asked to supply one, because there is nothing to supply.** The form asks only for facts about the case, and a refusal is not a fact about the case.

That leaves the fair question of what a member of the public sees instead, and today the honest answer has two halves. At the command line, and in the block of JSON above, the refusal arrives with its sentence intact and nothing standing in for the missing figure — that much you can run for yourself. A form built by turning these rules into some other system's format is the other half, and today that turning stops rather than produce a form at all, saying so and naming `REFUSE`; Step 8 comes back to it. So what a member of the public should be shown when a refusal reaches them is still a design decision, for whoever builds the service that sits in front of the rules. What the rules guarantee is the input to that decision: the author's sentence arrives unaltered, and no number arrives in its place.

---

## Step 4: Four things that are not refusals

Most no-answers are not refusals. Reaching for `REFUSE` when one of these four fits is how an encoding becomes unusable — every path ending in a wall that the person asking cannot get past.

Here are the four, and this step walks through the first three of them one at a time, in the same setting. The fourth is large enough to have a step of its own, and it is Step 5.

| What is going on                                     | Written as                                                                                  | Who deals with it                                | Can a later rule act on it?                             |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------- |
| **One.** a value that may be absent                  | `MAYBE`                                                                                     | the rule itself, by taking the two cases apart   | yes, as a value                                         |
| **Two.** an expected failure with a reason           | `EITHER`                                                                                    | the rule, or the rule that relies on it          | yes, as a value                                         |
| **Three.** a fact nobody has supplied yet            | a `GIVEN`; under a heading, a **"section GIVEN"**                                           | the boundary asks for it                         | nothing to act on yet — it is a question, not an answer |
| **Four.** the law does not apply, or is not in force | an ordinary value; or a yes-or-no rule the other rules check before they run (a **"gate"**) | savings and transitional provisions can reach it | yes                                                     |

And, for contrast, the thing this page is about, which is none of the four:

| What is going on                  | Written as   | Who deals with it                       | Can a later rule act on it? |
| --------------------------------- | ------------ | --------------------------------------- | --------------------------- |
| **the model does not cover this** | **`REFUSE`** | **the boundary, and nothing before it** | **no**                      |

### One — a value that may be absent (`MAYBE`)

Foundry Labs is a first-time issuer and has raised nothing in the previous twelve months. That absence is a fact about Foundry Labs, and the rule knows what to do with it. `MAYBE NUMBER` is a number that may be absent: `NOTHING` is the absence, `JUST 400000` the presence. `CONSIDER … WHEN … THEN …` takes the two cases apart, one arm each.

```l4
DECLARE Issuer
    HAS name IS A STRING
        `amount raised in the previous 12 months` IS A MAYBE NUMBER

GIVEN issuer IS AN Issuer
GIVETH A NUMBER
`prior raises counted against the limit` issuer MEANS
    CONSIDER issuer's `amount raised in the previous 12 months`
    WHEN NOTHING THEN 0
    WHEN JUST amount THEN amount
```

`Result: 0` for Foundry Labs — right, and right because the rule decided it, not because a default leaked in from somewhere.

### Two — a failure with a reason (`EITHER`)

A Form C offering statement can be rejected, and the ground of rejection is what the intermediary — the funding portal — quotes back to the issuer, the company that filed it. `EITHER STRING BOOLEAN` carries one of two things: a `LEFT`, here the text of the reason the filing failed, or a `RIGHT`, the ordinary yes-or-no result.

`LEFT` and `RIGHT` mean no more than "the first one" and "the second one", and the order is the order you wrote: in `EITHER STRING BOOLEAN`, `STRING` is named first, so `STRING` — text — is what a `LEFT` carries, and `BOOLEAN` — a yes-or-no fact — is what a `RIGHT` carries. L4 files put the failure on the left by convention, so that the successful case is the right-hand one in both senses of the word.

```l4
@ref 17 CFR 227.203(a)(1) — the Form C and what it must include
GIVEN filing IS A `Form C filing`
GIVETH AN EITHER STRING BOOLEAN
`the filing is accepted` filing MEANS
    BRANCH
       IF NOT filing's `has the required financial statements`
           THEN LEFT "rejected: the required financial statements are missing"
       IF NOT filing's `is signed`
           THEN LEFT "rejected: the filing is not signed"
       OTHERWISE RIGHT TRUE
```

Another rule reads that with `CONSIDER … WHEN LEFT … WHEN RIGHT …` and carries on with the answer it finds. The companion's `what the intermediary tells the issuer` does exactly that, and for Foundry Labs' unsigned filing it prints:

```
Result:
  "rejected: the filing is not signed"
```

That message looks like a refusal message. It is not one: it is a value, and the rule that produced it expects to be answered.

### Three — a fact nobody has supplied yet (a `GIVEN`)

The issuer's annual revenue is a real fact about a real case that nobody has entered yet. Every rule is a question with blanks in it, and `GIVEN` names the blanks. (A "smaller reporting company" is one of the size categories the SEC's rules turn on; what it is exactly does not matter here. What matters is that the rule below cannot answer until somebody types in a revenue figure.)

Written on a rule, as in the recap above, a `GIVEN` names that rule's own inputs. Written under a section heading and indented past the `§`, one `GIVEN` names a fact that every rule in that section shares — a **"section GIVEN"**:

```l4
§ `A fact nobody has supplied yet`
    GIVEN `the issuer's annual revenue` IS A NUMBER

@ref 17 CFR 229.10(f)(1) — the smaller reporting company revenue test
GIVETH A BOOLEAN
`the issuer is a smaller reporting company` MEANS
    `the issuer's annual revenue` LESS THAN 100000000
```

Ask that rule before anyone has supplied the revenue, and the tool says what it is waiting for:

```
I could not continue evaluating, because I needed to know the value of
  `the issuer's annual revenue`
but it is an assumed term.
```

"Assumed term" is the tool's own phrase for precisely this situation: a fact the file names but does not fix, standing there waiting to be supplied.

This is not a refusal and must never be written as one. It is a question with an addressee: the web form asks for it, and the published service requires it. Supply the value and the rule answers.

The field test, and the most portable sentence on this page: **name the person who could supply the missing thing.** If you can name them, it is a fact nobody has supplied yet. If nobody could — because the fact does not exist — then it is not a fact about the case at all, and you are looking at a refusal.

The section `GIVEN` has a tutorial of its own, [What a Section Needs to Know](../section-given/what-a-section-needs-to-know.md), which explains that screen; no companion runs it, because such a run counts as failed. The reference page is [the section `GIVEN`](../../reference/syntax/section-given.md).

The field test also sorts out an `ASSUME`, which you will meet in older files. `ASSUME` is deprecated — it still works, and it is still how a good deal of existing L4 is written, but it is no longer the way to write new rules — and it was used for both jobs at once. Apply the same test to one you find. If a person could supply the value, the `ASSUME` was standing in for a fact nobody has supplied yet, and it becomes a `GIVEN` under the section heading. If nobody could, it was standing in for a refusal, and it becomes a `REFUSE`. See [`ASSUME`](../../reference/types/ASSUME.md).

_Proposed, not landed (2026-09-04): supplying such a fact at the point where a rule is used, by writing `WITH`, as in `` `the issuer is a smaller reporting company` WITH `the issuer's annual revenue` IS 4000000 ``. It lands with the change that lets a rule be handed its facts from inside the file; until then, values are supplied from outside the file — the web form, the `l4 batch` command, which runs a file over a list of cases you have prepared in advance, or the rules published as a service._

### Two more you may meet, which are not absences at all

`LEST` is how an obligation says what follows if it is not met: the duty and the consequence of breach are written down together, and the consequence is an ordinary part of the rule. It is not a no-answer; it is an answer of a particular shape, and the obligation's own branch deals with it.

The other is one rule giving way to another — the drafting device a statute writes as "subject to section 12". That overrides a conclusion the first rule reached, so it too acts on an answer rather than on the absence of one. A refusal has no conclusion for it to act on, which is why neither `LEST` nor an override can reach one.

_Proposed, not landed (2026-09-04): a `SUBJECT TO` construct in the language for overriding rules. Today an override is written into the rules by hand._

---

## Step 5: "Not in force" is a value, not a refusal

The fourth look-alike is the one this page's own example sits closest to. Ask a different question about 1 January 2016: **was Regulation Crowdfunding in force?** That has an answer on every date there has ever been:

```l4
@ref 80 FR 71388 (Rel. 33-9974) — part 227 is in force from 2016-05-16
GIVEN `rule date` IS A DATE
GIVETH A BOOLEAN
`Regulation Crowdfunding is in force on` `rule date` MEANS
    `rule date` AT LEAST Date 16 5 2016
```

`FALSE` on 1 January 2016, `TRUE` on 1 June 2016. Determinate, and useful: another rule can read it, a savings provision can override it, a report can print it. That is not an accident of this encoding. Law provides for its own commencement and repeal, and the provisions that do so — savings and transitional provisions — are ordinary law that other rules can reach.

That rule is what the table in Step 4 called a gate: a yes-or-no rule the other rules consult before they apply themselves. Nothing more is needed to write one. It is an ordinary rule; it is a gate because of the use the rules around it make of it.

The principle is not peculiar to United States law, so this paragraph changes country for a moment. Singapore's Interpretation Act 1965, s 16(1)(b)–(c), says that a repeal does not affect anything previously done under the repealed law, nor any right accrued under it. Take an invented example, to keep it short — no part of what follows is Regulation Crowdfunding, and none of it is real. A licensing regime is repealed on 1 January 2024, and an application Alex filed in November 2023 is therefore still decided under the old Act. That is a rule you can write down:

```l4
DECLARE Application
    HAS `filed on` IS A DATE

GIVETH A DATE
`the repeal took effect` MEANS Date 1 1 2024

GIVEN application IS AN Application
GIVETH A BOOLEAN
`is decided under the old Act` application MEANS
    NOT (application's `filed on` AT LEAST `the repeal took effect`)
```

`TRUE` for Alex's application, and other provisions can read that answer. Make it a refusal and you have put it beyond the reach of the very provisions written to handle it.

So why does the offering **figure** refuse, when the in-force **question** answers? Because they ask for different things. "Is it in force?" asks for a yes or a no, and both of those exist on every date. "What is the limit?" asks for a quantity that the law supplies only while it is in force, and on 1 January 2016 it supplies none.

One further distinction hides inside that one, and it is the one an encoder is most likely to get wrong, so it is worth slowing down over. **"The law supplies no quantity" and "the law supplies the quantity nil" are different things, and only the first is a refusal.** Suppose a tax commences on 1 April 2027 and somebody asks what is due for March. If the scheme's own text says that no tax is due before commencement — that the amount for March is nil — then nil is an answer the law gives, and you write it as an ordinary value, `0`, exactly as you would write any other figure the law fixes. If the text says nothing at all about March, because the scheme did not exist, then any figure you print is one you invented, and that is the case for a refusal.

The way to tell which you are in is to go back to the provision and look for words that fix the amount. Words that fix it at zero are still words that fix it. Only when there are no such words, and no others that reach the date either, do you have nothing to give.

The test to carry away: **ask what would have to be true for an answer to exist.** If the answer exists and someone has merely not supplied it, that is a fact nobody has supplied yet. If the answer exists and is "no", that is a value. If there is no answer for the encoder to give, that is a refusal.

A statute avoids the whole situation by changing what is asked, never by dealing with a refusal afterwards. That is what a deeming provision does: it rewrites the facts before the rule runs, so that the question the rule receives is one it can answer.

---

## Step 6: Nothing downstream can turn a refusal into an answer

Try to soften the refusal. Wrap it in a `MAYBE`, then default the absent case to zero — the ordinary pattern from Step 4.

```l4
GIVETH A MAYBE NUMBER
`the figure, if the model has one` MEANS
    JUST `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`

GIVETH A NUMBER
`an attempt to default the refusal` MEANS
    CONSIDER `the figure, if the model has one`
    WHEN JUST amount THEN amount
    WHEN NOTHING THEN 0
```

```
Result:
  The model refuses to answer:
    no Regulation Crowdfunding figure exists before commencement on 2016-05-16
```

Neither arm runs. To choose between them, the `CONSIDER` has to look at what it is examining, and looking is the thing that refuses. Nothing deals with a refusal on the way out — not `CONSIDER`, not a `MAYBE` or `EITHER` match, not `IF`, not `AND` or `OR`, and not `WHERE` or `LET`, which are the two ways a rule gives a name to a piece of its own working before using it. Only the boundary sees it.

That asymmetry is the whole point. A `NOTHING` is a value, so a later rule can quietly turn it into zero — sometimes rightly, as in Step 4, and sometimes because somebody needed the arithmetic to keep going. A refusal cannot be laundered that way. The only way to make a refusing case answerable is to go back to the encoding and write the rule.

The image is a judge who recuses. The case is not decided; no party may treat the recusal as a judgment in their favour; and the matter goes to another bench.

---

## Step 7: Order matters, a little

A refusal only happens if the rule gets that far, and `AND` and `OR` are read left to right, stopping as soon as the answer is settled.

The two lines below are `#ASSERT`s — instructions to L4 saying "this must hold", which Step 8 comes back to. Read them here as two questions being asked. The word `REFUSED` in front of the second one means "I expect this one to decline", so that the line holds when the question refuses rather than when it answers; Step 8 has the detail. The refusal they are asked about names a foreign private issuer: broadly, a company not organised under the laws of a State of the United States, and part 227's exemption is not open to one.

```l4
@ref 17 CFR 227.100(b)(1) — foreign private issuers are outside part 227
GIVETH A BOOLEAN
`the model does not cover offerings by foreign private issuers` MEANS
    REFUSE "the model does not cover offerings by foreign private issuers"

#ASSERT NOT (FALSE AND `the model does not cover offerings by foreign private issuers`)
#ASSERT REFUSED (`the model does not cover offerings by foreign private issuers` AND FALSE)
```

The `AND` inside the first assertion answers `FALSE`: once the left side is `FALSE` the whole `AND` is settled, and the right side is never looked at. So the first assertion holds. The `AND` inside the second one refuses, because there the refusal is on the left and is reached first — and a refusal anywhere inside an assertion comes straight out to the boundary, which is what the second line is written to expect.

Put the cheap, decisive test first, and a rule that would otherwise stop on a case it does not cover may answer instead — the drafting discipline of writing "if the applicant is under 18 and …" rather than the other way round. Do not lean on the ordering to keep a case out, though: if a case is one the model does not cover, say so with a condition that says it, and let the ordering be a convenience rather than the load-bearing part.

(One kind of file behaves differently here, in case you meet one. A file about obligations — who must do what, and by when — joins them with `RAND` and `ROR` rather than with `AND` and `OR`. Those two fix no left-to-right order, so nothing in this step tells you which side is looked at first. Ordinary `AND` and `OR`, the ones joining yes-or-no facts, do.)

---

## Step 8: Test that a case refuses, and mark what you have not written

`#ASSERT` is an instruction to L4 saying that something must hold; it is how a file checks itself, and running the file reports on each one. Testing refusals keeps them honest: a boundary you never exercise is a boundary that quietly moves.

```l4
#ASSERT REFUSED (`offering maximum in a 12-month period` (Date 1 1 2016))
#ASSERT REFUSED (`offering maximum in a 12-month period` (Date 1 1 2016)) BECAUSE "no Regulation Crowdfunding figure exists before commencement on 2016-05-16"
```

The first passes when the rule refuses at all. The second also requires the message to be the one you named. Use `BECAUSE` for any refusal a reader will actually meet, so that rewording the message breaks a test rather than silently changing what somebody is told.

The outcomes you will see, printed where that instruction's result goes:

| You wrote                       | What happened             | What it reports                                                             |
| ------------------------------- | ------------------------- | --------------------------------------------------------------------------- |
| `#ASSERT REFUSED e`             | the rule refused          | `assertion satisfied`                                                       |
| `#ASSERT REFUSED e`             | the rule produced a value | `assertion failed: expected a refusal, but the expression produced a value` |
| `#ASSERT REFUSED e BECAUSE "x"` | the rule refused with "y" | `assertion failed: expected the refusal "x", got "y"`                       |
| `#ASSERT e` or `#ASSERT NOT e`  | the rule refused          | `assertion refused:` followed by the refusal's own two lines                |

That last row holds whether or not you wrote `NOT`: `NOT` has to look at what it is negating, so negation cannot convert a refusal into a verdict either. A **failed** assertion says your rule disagrees with your expectation. A **refused** assertion says the question never got as far as an answer — a different problem, with a different fix, and sometimes exactly what you wanted.

Last, the drafting placeholder. When a rule is not written yet, say so rather than guess:

```l4
@ref 17 CFR 227.202 — ongoing reporting requirements, not yet encoded
GIVETH A BOOLEAN
`the issuer's ongoing reporting obligations are satisfied` MEANS TBD
```

`TBD` is the ordinary drafting abbreviation "to be determined". It comes from the prelude — the small set of definitions a file gets by writing `IMPORT prelude` — and it is a refusal like any other, except that its message is one the prelude supplies rather than one you wrote. Ask the rule above and you see:

```
Result:
  The model refuses to answer:
    TBD: this rule has not been written yet
```

That sentence is worth knowing by sight, because it is the only sign on the screen that a gap is unfinished drafting rather than a boundary somebody drew on purpose. `TBD` works whatever kind of thing the rule answers with — the yes-or-no rule above, a rule answering with a figure, any of them — so a half-finished file gives an honest non-answer instead of a placeholder `TRUE` that somebody later mistakes for a conclusion. Write `TBD` for a provision you have not read yet, and a named refusal for one you have read and decided not to encode.

_Proposed, not landed (2026-09-04): reporting a `TBD` differently from a hand-written `REFUSE`, so that unfinished drafting can be listed apart from the boundaries an author drew on purpose._ So today nothing in the report marks a `TBD` as a different kind of thing, and the only clue is the wording above. That clue is a weak one: nothing stops an author writing much the same sentence by hand, and no tool can count the unfinished provisions in a file for you. To be sure which you are looking at, open the file — a `TBD` is the unwritten one — or ask whoever maintains it.

_Proposed, not landed (2026-09-04): a listing of the refusals a rule may reach, offered as you hover over it and in the list of facts a published rule asks for._ Today, when a rule containing a refusal is converted for another system — L4 can turn a file into the formats that other rule tools and question-asking systems read — most conversions stop rather than emit anything, saying so and naming `REFUSE`; the ones that do not stop write out a file that cannot be used. None turns the refusal into something a person or another program could be asked to supply.

---

## One last convenience: a refusal that works wherever it is used

You do not need this to write good rules, and nothing above depends on it.

Step 2 left this open, so here it is closed. A refusal you have named takes the kind of thing its own `GIVETH` line gives it, and can be used only by rules that answer with that kind. So if one refusal has to serve rules that answer with different kinds of thing — a number in one place, a yes-or-no in another — the plain way is to write the same refusal out twice, once for each kind, with two names that say the same sentence. That works, and for two places it is not a hardship.

It can be written once instead, in a form that works wherever it is used, whatever the rule using it answers with. `TBD` is exactly that, which is why Step 8's `TBD` sits happily in a yes-or-no rule and would sit just as happily in one answering with a figure. When you find yourself wanting the same for a refusal of your own, the spelling is on the [`REFUSE` reference page](../../reference/control-flow/REFUSE.md).

---

## What You Learned

- A question can presuppose something that is not there, and the honest response is to decline, with a sentence.
- `REFUSE "message"` declines whatever kind of thing the rule was meant to answer with, and the message is written out in quotation marks. House style: one named definition per refusal, the name is the message, an `@ref` above it, and every rule that needs it uses the name. A refusal you have named takes the kind of thing its own `GIVETH` line gives it, so one name serves the rules that answer with that kind; the last section says what to do when you want one name for several kinds.
- Four no-answers are not refusals: a value that may be absent (`MAYBE`), a failure with a reason (`EITHER`), a fact nobody has supplied yet (named by a `GIVEN`, and under a heading by a section `GIVEN`), and a law that is not in force or does not apply (an ordinary value, or a gate other provisions can reach).
- The test: ask what would have to be true for an answer to exist. Not supplied yet is a fact awaiting a person; "no" is a value; and so is nil, where the law's own words fix the amount at nil. No answer for the encoder to give is a refusal.
- A refusal is not a mistake in the rules. On screen it begins `The model refuses to answer:` and the run finishes; a mistake says something else, is marked `DiagnosticSeverity_Error`, and the run counts as having failed. Pass a refusal on; report a mistake to whoever maintains the file.
- Nothing inside the rules can deal with a refusal or convert it into a value. Only the boundary sees it.
- `AND` and `OR` are read left to right, so `FALSE AND r` answers while `r AND FALSE` refuses.
- `#ASSERT REFUSED e`, with `BECAUSE "…"` when the message matters. A plain `#ASSERT` over a refusing rule reports _refused_, not _failed_. `TBD` is the placeholder for a rule you have not written yet.

---

## Next Steps

- [`REFUSE`](../../reference/control-flow/REFUSE.md) — the reference page, with what each surface prints and what the conversions to other systems do today
- [Five Kinds of No Answer](../../concepts/legal-modeling/non-answers.md) — the same sorting problem taken further, as a piece of critical thinking
- [What a Section Needs to Know](../section-given/what-a-section-needs-to-know.md) — naming the facts a whole run of rules needs, once, under the heading
- [Encoding Legislation](../getting-started/encoding-legislation.md) — turning statutory text into rules
