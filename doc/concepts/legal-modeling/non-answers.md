# Five Kinds of No Answer

"There is no answer" is five different sentences. Telling them apart is most of the work of encoding a rule.

---

## Five silences in one afternoon

A caseworker sits down with Alex Tan's benefit file and asks it five questions. Each time the answer is, in some sense, "there is no answer". Each time it means something entirely different.

1. **What is the spouse's income?** Alex has no spouse. The question has no subject, and the rule knows what to do about that.
2. **Is 13 a month?** No — a finding, not a mishap. Alex's form was filled in wrong, and the reason goes in the letter back.
3. **Is Alex of pensionable age?** Nobody has said how old Alex is. Ask.
4. **Does the 2016 scheme govern Alex's 2014 transaction?** No: it was not in force then. The law says so itself, and says what governs instead.
5. **Does the scheme cover Alex's transaction on a ship registered abroad?** The Act may well say. The file in front of the caseworker does not: whoever encoded these rules never reached ships. Nobody wrote _that_ part down.

On paper all five look the same: a blank. Confusing them is expensive, because the first four have answers and only the fifth does not. A file that treats a missing spouse the way it treats an unwritten rule will quietly compute a benefit no law authorises.

L4 gives each of the five its own way of being written down, so the difference survives into the code, into the web form, and into the result the caseworker reads.

### Two words used throughout, and how to run the examples

A rule is told some facts about the case in front of it (its **"inputs"**, the names listed after `GIVEN`) and works out one answer from them (its **"output"**, whose kind of thing is named after `GIVETH` — or `GIVES`, the same word in a plainer spelling). Given these inputs, a rule gives an output. Everything below is about what happens when a rule cannot give one.

**Example files.** Every piece of code on this page is in one of two files you can run for yourself:

- [non-answers-example.l4](non-answers-example.l4) — sections 1, 2, 4, 5 and 6. Run it by typing `l4 run non-answers-example.l4`.
- [non-answers-not-yet-known.l4](non-answers-not-yet-known.l4) — section 3, which needs a feature the other file does not use. Run it by typing `l4 run non-answers-not-yet-known.l4`.

**Where you type that.** Not in the L4 editor window: in a terminal window — the plain window where you type one line of instruction, press Enter, and the computer prints its reply back underneath (the **"command line"**). If you have not used one before, [The L4 Command-Line Tool](../../tutorials/getting-started/l4-cli.md) is the page that sets it up: it covers getting `l4` onto your machine so that the word `l4` means something when you type it, and what each instruction does. Everything below shows you what appears in that window.

The numbered sections in both files match the numbered sections below. The lines beginning with `#` are instructions to L4 rather than rules: `#EVAL` says "work this out and show me the answer", `#CHECK` says "tell me what kind of answer this would give, without working it out", and `#ASSERT` says "this had better come out the way I say, and tell me if it does not".

---

## 1. There is no spouse — a value that may be absent

The person says: **"That does not apply to this case."**

An income test asks for the spouse's income. Some households have no spouse. The absence is a fact about the household, as solid as any number, and the drafter provided for it: assessed income is the applicant's income plus the spouse's, if any.

`MAYBE NUMBER` is L4's way of writing "a number, or nothing at all". A value of that kind arrives in one of exactly two shapes: `JUST OF 12000` when there is a number, and `NOTHING` when there is not. `CONSIDER` looks at which shape arrived and takes the matching line, so the rule cannot forget either one:

```l4
DECLARE Household
    HAS `income of the applicant` IS A NUMBER
        `income of the spouse` IS A MAYBE NUMBER

GIVEN household IS A Household
GIVETH A NUMBER
`assessed income of` household MEANS
    household's `income of the applicant`
    PLUS
    CONSIDER household's `income of the spouse`
    WHEN JUST OF income THEN income
    WHEN NOTHING THEN 0
```

Alex Tan's household, with no spouse, assesses at 30000. Bina Lim's, with a spouse earning 12000, assesses at 42000. Nothing failed in either case; the absence was one of the two ordinary things that could happen. See [MAYBE](../../reference/types/README.md#maybe-and-nullability).

---

## 2. Thirteen is not a month — an expected failure with a reason

The person says: **"What you gave me is not usable, and here is why."**

Every intake process has this: a month outside 1 to 12, an identification number that fails its check digit, a date of birth after today. The rule sees it coming, and the reason is something a human is entitled to be told.

`EITHER STRING NUMBER` says the answer is one of two kinds of thing. `STRING` is L4's word for text; `NUMBER` is a number. **The failure kind is written first and the success kind second**, and the two ways of building the value line up with that order in the same way: `LEFT OF` builds the first, the failure, and `RIGHT OF` builds the second, the success. So `EITHER STRING NUMBER` here means "either text saying what went wrong, or the number this gives when it worked", and reading `LEFT` as the left-hand kind in the pair, `RIGHT` as the right-hand kind, will keep you straight. Both halves are ordinary values, so a later rule can act on either. One more word appears in the second rule below: `CONCAT` joins two pieces of text end to end, so `CONCAT "returned for correction: ", reason` is the fixed opening followed by whatever the reason turned out to be.

```l4
GIVEN month IS A NUMBER
GIVETH AN EITHER STRING NUMBER
`checked month` month MEANS
    IF   month AT LEAST 1 AND month AT MOST 12
    THEN RIGHT OF month
    ELSE LEFT OF "a month must be between 1 and 12"

GIVEN month IS A NUMBER
GIVETH A STRING
`what the clerk tells Alex about` month MEANS
    CONSIDER `checked month` month
    WHEN RIGHT OF m      THEN "accepted"
    WHEN LEFT  OF reason THEN CONCAT "returned for correction: ", reason
```

Running that second rule on 13 prints:

```
Result:
  "returned for correction: a month must be between 1 and 12"
```

The failure travelled as a value from the rule that detected it to the rule that had to say something about it. The test for this row: **can a later rule act on the reason?** See [EITHER](../../reference/types/README.md#either-for-errors).

---

## 3. Nobody has told me Alex's age — a fact not yet known

The person says: **"I cannot answer until you tell me something."**

Every rule is a question with blanks in it. A pensionable-age test has one blank: the applicant's age. The file does not know it and is not supposed to — that is the case's contribution, not the law's.

A `GIVEN` written under a section heading, indented past the `§`, names a blank once for every rule in that section (a **"section GIVEN"**). This page calls that name a **blank**; the message further down calls it an _assumed term_. Two words, one idea: a name the file declares and the case fills in.

```l4
§ `3. A fact nobody has supplied yet -- a section GIVEN`
    GIVEN `the applicant's age in years` IS A NUMBER @desc Age at the date of the claim

GIVETH A BOOLEAN
`is of pensionable age` MEANS
    `the applicant's age in years` AT LEAST 65
```

`BOOLEAN` is L4's word for a yes-or-no fact. `@desc` is a note attached to the blank; the web form shows it to whoever has to fill the blank in, which is why it is written for them and not for the encoder.

L4 accepts this rule whether or not anyone has filled the blank in. Ask for the answer too early, and what comes back names the blank:

```
Result:
  I could not continue evaluating, because I needed to know the value of
    `the applicant's age in years`
  but it is an assumed term.
```

That is not a defect. It is the point where the case meets the file (the **"boundary"**) being told exactly which question to put to Alex. The boundary is wherever a real case reaches the rules: most often a web form somebody fills in, but equally a run over many cases at once, or another computer system asking L4 a question and reading the answer back.

**Tell this row from row 1**, because on paper both are "there is nothing in that box", and the two are the pair most often confused. The test is whether the case has been asked yet:

- A `MAYBE` is a fact the case **has** told the file, and the answer was "none". The household's record has a spouse-income box, the box has been filled in, and what was filled in was "no spouse". The absence arrived with the case.
- A blank is a fact the case has **not** told the file. Nobody has said how old Alex is. Nothing has arrived, and until it does there is no answer to look at.

So: a will that names no executor is a `MAYBE`. The will is the case's own record, it has been read, and "no executor named" is one of the two answers reading it can produce — an answer the law then provides for. It would be a blank only if nobody had yet handed the file the will.

See [What a Section Needs to Know](../../tutorials/section-given/what-a-section-needs-to-know.md) and the [section GIVEN](../../reference/syntax/section-given.md) reference.

---

## 4. The Act was not in force then — the law does not apply

The person says: **"This case is outside the law, and the law says where it stops."**

This row is the one most often mistaken for the last. A scheme that commences on a date does not govern earlier transactions; a provision applying to companies does not apply to partnerships. Both are determinate legal conclusions, written down deliberately.

Legislatures also write down what happens instead. That is what savings and transitional provisions are for: under the Singapore Interpretation Act 1965 s 16(1)(b)–(c), repealing an Act does not affect anything previously done under it or any right already accrued. The repealed law keeps governing the transactions that ripened under it.

**A later provision has to reach this conclusion and build on it.** So it must be written as an ordinary value, or as a **"gate"**: a plain yes-or-no test sitting in the file like any other rule, which a later rule can read and carry on from. Never as something that stops the calculation:

```l4
DECLARE Claim
    HAS `year of the transaction` IS A NUMBER
        `right accrued under the repealed Act` IS A BOOLEAN

GIVEN year IS A NUMBER
GIVETH A BOOLEAN
`the 2016 scheme is in force in` year MEANS
    year AT LEAST 2016

GIVEN claim IS A Claim
GIVETH A STRING
`the scheme that governs` claim MEANS
    IF   `the 2016 scheme is in force in` (claim's `year of the transaction`)
    THEN "the 2016 scheme"
    ELSE IF   claim's `right accrued under the repealed Act`
         THEN "the repealed Act, preserved by the savings provision"
         ELSE "no scheme applies to this transaction"
```

Alex's 2014 transaction, with an accrued right, answers `"the repealed Act, preserved by the savings provision"`. The commencement date is an ordinary fact in the file, and the savings provision reads past it. Nothing here is out of the ordinary.

---

## 5. Nobody wrote that part down — the model does not cover this

The person says: **"I decline to answer this one."**

Back to the ship, and this time all the way through. The scheme charges a levy when a vessel changes hands. Alex's file works out the levy for vessels on the local register. Whether the scheme reaches a vessel registered abroad is a question about the Act, and the Act may well answer it — but this file cannot, because whoever wrote it never got to foreign registration. What the file should say is exactly that, in the encoder's own words, at the point where its coverage stops.

Here is the whole of it. `REFUSE` is followed by the sentence the encoder wants the caseworker to read:

```l4
@ref The Act may well reach foreign-registered vessels. This file does not.
GIVETH A NUMBER
`this file does not cover vessels registered outside Singapore` MEANS
    REFUSE "this file does not cover vessels registered outside Singapore"

DECLARE Transfer
    HAS `price in dollars` IS A NUMBER
        `the vessel is registered abroad` IS A BOOLEAN

GIVEN transfer IS A Transfer
GIVETH A NUMBER
`the levy on` transfer MEANS
    IF   transfer's `the vessel is registered abroad`
    THEN `this file does not cover vessels registered outside Singapore`
    ELSE transfer's `price in dollars` TIMES 0.002
```

Three things in that are worth a word.

`@ref` is a note recording the source the refusal is about, or — as here — what the encoder is declining and why. It changes nothing about what the file works out; it is there so that the next person to open the file learns something the code alone cannot tell them.

`GIVETH A NUMBER` on the refusal is not decoration. The rule below it works out a levy, which is a number, so the refusal is written as a rule that would give a number if it gave anything. Write each refusal to fit the place it is used. (One refusal can be written so that it fits rules giving different kinds of answer; the [REFUSE reference](../../reference/control-flow/REFUSE.md) shows how, and you do not need it to write your first one.)

The rest is house style: **one named definition per refusal, and the name says the same thing as the message.** Every rule that needs the refusal uses that name. Saying it twice, once as the name and once as the message, looks wasteful and is not: the line that reaches the refusal then reads like the provision it encodes (`THEN this file does not cover vessels registered outside Singapore`), and anyone searching the file for what is missing finds it by name.

There is also a ready-made refusal for the commonest case of all. L4 ships with a small collection of definitions other files can borrow, called the prelude; writing `IMPORT prelude` on a line at the top of your file makes those definitions usable in it, and changes nothing else about the file. One of them is `TBD` — the drafter's own margin note, _to be decided_ — a refusal carrying a message the prelude supplies. You write `TBD` instead of a rule's answer, not alongside a `REFUSE`: use `TBD` for a provision you have not written yet, and a named refusal like the one above for a provision you have read and decided not to encode.

Run the two sales in the example file and you get an ordinary number for the local vessel and this for the foreign one:

```
Result:
  800
```

```
Result:
  The model refuses to answer:
    this file does not cover vessels registered outside Singapore
```

That is neither zero nor false nor unknown. It is a distinct outcome carrying the encoder's own sentence.

Real encodings show the cost of not having this. The Regulation Crowdfunding rules that ship with L4 encode part 227 of title 17 of the United States Code of Federal Regulations, which commenced on 16 May 2016. They are asked for a dollar figure "as at" a rule date. For a date before commencement there is no figure to give, because the rules did not yet exist — and to this day that gap is written there as a blank, so the web form asks whoever is using the rules to supply a figure nobody has. Rewriting it as the refusal `no Regulation Crowdfunding figure exists before commencement on 2016-05-16` is drafted, and waiting on one export format that cannot carry a refusal yet.

Compare rows 4 and 5 closely, because they are one sentence apart. **Row 4 is a claim about the law: this transaction is outside it. Row 5 is a claim about the file: the encoder did not go there.** The first is legal knowledge, the second an admission. A refusal is a judge recusing herself — the case is not decided, no party may treat the recusal as a win, and the matter goes to another bench.

### What the caseworker sees, and what you have to write to make that happen

Nothing. A refusal travels to the boundary on its own.

In the terminal window it prints the block above. Asked of L4 running as a service — over an application programming interface (an **"API"**), the way another system would ask — the reply comes back written in the notation programs use to exchange data with one another, JavaScript Object Notation (JSON). It says its kind is `refused` and carries the sentence as the reason:

```json
{
  "kind": "refused",
  "reason": "this file does not cover vessels registered outside Singapore",
  "value": null
}
```

The real reply also records where in the file the refusal happened. What matters for encoding is that the refusal is its own kind of result, distinct from a value, so whatever is on the other side — a screen, a letter, another system — can tell the caseworker that the file declined rather than showing a figure.

### Nothing downstream can turn a refusal into an answer

Look again at row 1: a later rule quietly turned `NOTHING` into `0`, and that was correct — the drafter said so. The same move on a refusal would be a forgery: a rule three layers away deciding, on its own authority, that "nobody encoded this" means "zero".

So no later rule can deal with a refusal or turn it into an answer. `CONSIDER` cannot match on one, `IF` cannot test it, and `AND` and `OR` cannot see it. Those three are not a list of the ways in, with a fourth waiting to be discovered: **there is nothing anywhere in L4 that takes a refusal and hands back a value.** It travels intact to the boundary — the instruction you gave, the terminal window, the service's reply, the form — and whoever reads the result sees the sentence the encoder wrote. An absent value can be given a stand-in; a refusal cannot be laundered.

One subtlety follows from ordinary left-to-right reading, and it does not weaken that promise. Let `r` be a piece of a rule that refuses. Then:

- `FALSE AND r` answers `FALSE`. L4 stops reading as soon as it knows the answer, and after `FALSE AND` it knows. The right-hand half was never worked out at all, so no refusal ever happened and nothing observed one.
- `r AND FALSE` refuses, because the refusal came first and there is nothing that could set it aside.

In neither case did any rule get hold of a refusal and do something with it. What this does mean is that the order in which you write two conditions is a drafting decision with consequences: put the cheap, decisive test on the left, and a rule will answer in the cases where the law does not need the part you have not encoded.

### Testing that a case refuses

To check that a case refuses, assert it. These are two alternatives, not two steps — write whichever one you want. The first checks only that the answer was a refusal; the second also pins the sentence, so a later edit that changes the wording is reported:

```l4
#ASSERT REFUSED `the levy on` `the Lim sale`
```

```l4
#ASSERT REFUSED `the levy on` `the Lim sale`
        BECAUSE "this file does not cover vessels registered outside Singapore"
```

Either way, a passing check prints `assertion satisfied`.

A plain `#ASSERT` — one that says what the answer should be, rather than that there should be no answer — reports something else again when the case refuses. It does not say _failed_, and it does not say _could not be evaluated_:

```
Result:
  assertion refused:
  The model refuses to answer:
    this file does not cover vessels registered outside Singapore
```

A test suite therefore never records a refusal as a wrong answer. It records it as the file declining, which is what happened.

---

## 6 and 7. Two answers that look like non-answers

Two more rows belong in the table below. Both are traps in the other direction: they feel like silences and are fully specified outcomes. Each has its own page; what follows is only enough to tell them apart from the five above.

**6. A breach.** A deadline passes and the report is not filed. That is not the absence of an answer; it is the answer, written in the obligation's own `LEST` branch:

```l4
GIVETH A DEONTIC Actor Act
`the reporting obligation` MEANS
    PARTY  `the issuer`
    MUST   `file the annual report`
    WITHIN 120
    HENCE  FULFILLED
    LEST   BREACH BY `the issuer`
```

Those words read the way the obligation does: `PARTY` who is bound, `MUST` what they have to do, `WITHIN` the time they have, `HENCE` what follows if they do it, `LEST` what follows if they do not. Both outcomes are written down; neither is a silence. [Regulative Rules](regulative-rules.md) teaches this properly, including what `DEONTIC` means.

**7. An overridden conclusion.** "Subject to section 9" does not mean section 9 leaves a hole. A rule reached a conclusion and another rule displaced it — a structured outcome, with a named rule that did the displacing. [Default Reasoning and Exceptions](default-reasoning.md) teaches this properly.

Drafting marks that relationship from either end, and the two markings point opposite ways. "Section 4 is subject to section 9" means section 9 wins. "Section 4 applies notwithstanding section 9" means section 4 wins. Same relationship, two ends of it: the rule that is _subject to_ another is the one that gives way, and the rule that applies _notwithstanding_ another is the one that prevails. **The marking goes on the rule that gives way.** So a section 4 which says "notwithstanding section 3" is encoded by writing the displacement into the encoding of section 3 — section 3's rule holds unless section 4's condition is met — and section 4 itself is written as an ordinary rule. Today that is written with `UNLESS`, and the page just linked shows the shape.

_Proposed, not landed (2026-09-04): a `SUBJECT TO` construct in the language, so that an override can be written at the end the drafting writes it at, rather than turned round by hand._

An override, however it is spelled, overrides a _conclusion_. It cannot override a refusal, because a refusal is not a conclusion — there is nothing to override. A statute that wants to avoid a row-5 gap does not write a rule to handle it afterwards; it writes a deeming provision that changes the facts before the rule runs.

---

## The whole taxonomy

| what "no answer" means here                | how it is written                     | who deals with it                                | can a later rule in the file act on it? |
| ------------------------------------------ | ------------------------------------- | ------------------------------------------------ | --------------------------------------- |
| a value that may be absent                 | `MAYBE`                               | the rule, by matching on both shapes             | yes, as a value                         |
| an expected failure with a reason          | `EITHER`                              | the rule, or a later rule that uses it           | yes, as a value                         |
| a fact nobody has supplied yet             | a blank, written as a section `GIVEN` | the boundary, by asking for it                   | the question does not arise — see below |
| the law does not apply, or is not in force | an ordinary value, or a gate          | savings and transitional provisions can reach it | yes                                     |
| the model does not cover this              | `REFUSE`                              | the boundary, and nothing before it              | no                                      |
| a breach                                   | `LEST`                                | the obligation's own branch                      | yes — it is an outcome, not a silence   |
| an overridden conclusion                   | `UNLESS` in the rule that gives way   | the overriding rule                              | yes — it is an outcome, not a silence   |

Read the last column first, because it is the one that matters at the point of encoding: **who is allowed to do something about this?** A refusal is the only row where the answer is nobody.

The blank's entry needs its own sentence. The question does not arise there because a blank is filled before any rule runs at all: the boundary asks, the case answers, and by the time the rules are working the blank is an ordinary fact. There is never an unanswered blank sitting inside a running file for a later rule to act on.

That is also what separates the blank from the first row, the pair easiest to confuse: a `MAYBE` is an absence the case has already reported, and a blank is a question the case has not been asked yet. Section 3 above works the test through.

---

## Classify these yourself

Decide the row before reading on.

**(a)** An Act is repealed in 2020. A claim brought in 2024 concerns conduct in 2018, and the repealing Act saves rights accrued before the repeal.

> **The law does not apply, or is not in force — an ordinary value or a gate.** The repealed Act governs, because the savings provision says it does. That is a legal answer, and it must stay reachable: the rule deciding which Act governs has to read the gate and carry on from it. A refusal would stop the calculation at exactly the point the legislature provided for.

**(b)** Alex enters a national identification number whose check digit does not match.

> **An expected failure with a reason — `EITHER`.** The rule detects it, Alex is entitled to hear why, and the rule that uses it acts on the failure by returning the form. Compare (d): here the encoder anticipated the case and wrote down what to do about it.

**(c)** A supply contract says the unit price is "as agreed between the parties from time to time". No schedule of agreed prices exists.

> **A fact nobody has supplied yet — a blank.** The contract leaves the price to be supplied per transaction; the encoding leaves a blank named `` `the agreed unit price` `` and the boundary asks for it. It becomes a refusal only if the contract does contain a mechanism for determining the price and the encoder has not encoded that mechanism — which is a fact about the file, not about the contract.

**(d)** A tax rule has one formula for residents and one for non-residents. The source text has a third category, "deemed residents", which the encoder skipped.

> **The model does not cover this — `REFUSE`.** The law has an answer; the file does not. Anything else is a lie about coverage: giving the non-resident figure invents a legal position, and giving zero invents a stronger one. Write the refusal, name it after what is missing, and let it reach the caseworker.

**(e)** A will has been lodged with the file and names no executor. The law says who administers an estate when the will names nobody.

> **A value that may be absent — `MAYBE`.** The will is the case's own record. It has been read, and "names no executor" is one of the two answers reading it can produce, not a question still outstanding — so the rule matches on both shapes and takes the second, exactly as the income test takes the household with no spouse. Compare (c), where nothing has told the file the price at all and the boundary still has to ask. The test between these two is always the same one: has the case already answered? An absence the case reported is a `MAYBE`; a question not yet put is a blank.

---

## Further Reading

- [When a Rule Cannot Answer](../../tutorials/refuse/when-a-rule-cannot-answer.md) — the `REFUSE` tutorial
- [What a Section Needs to Know](../../tutorials/section-given/what-a-section-needs-to-know.md) — naming the blanks a rule leaves open
- [REFUSE Reference](../../reference/control-flow/REFUSE.md) — how to write it and how it behaves
- [Types Reference](../../reference/types/README.md#maybe-and-nullability) — `MAYBE` and [`EITHER`](../../reference/types/README.md#either-for-errors)
- [Default Reasoning and Exceptions](default-reasoning.md) — overriding a conclusion
- [Regulative Rules](regulative-rules.md) — `LEST`, breach, and the three outcomes of an obligation
- [Constitutive vs Regulative Rules](constitutive-vs-regulative.md) — which layer a non-answer comes from
