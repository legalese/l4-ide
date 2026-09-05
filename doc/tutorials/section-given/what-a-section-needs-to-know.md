# What a Section Needs to Know

Say once, under the heading, which facts a whole run of rules is about — and every rule beneath it can then use those facts without repeating a word of them.

**Prerequisites:** [Your First L4 File](../getting-started/first-l4-file.md) — enough to read a rule written with `GIVEN`, `GIVETH` and `MEANS`, and to run a file with `l4 run`. No programming is assumed, and every rule this page uses is written out on this page.

**Complete example:** [what-a-section-needs-to-know.l4](what-a-section-needs-to-know.l4), which holds every example below that runs today.

---

## What You'll Build

Two questions out of Regulation Crowdfunding, the United States rules that let a company raise money from the public through a funding portal. They live at Part 227 of title 17 of the Code of Federal Regulations, made by the Securities and Exchange Commission:

- **How much may this investor put in over twelve months?** — Rule 100(a)(2)
- **May this company raise money through crowdfunding?** — Rule 100(b)

The investor on this page is called Alex. Alex earned $40,000 last year and has a net worth of $20,000.

The two questions are about entirely different things, so Alex should never be shown a box about business plans and a company should never be asked what Alex earns. Three ideas get you there, and they are the three parts of this tutorial:

1. **Say a fact once for a whole section**, instead of once inside every rule that needs it.
2. **Let one rule rely on another**, and watch L4 work out for itself which facts the whole question needs.
3. **Use one word in two sections for two different things**, the way statutes do, and know what happens when a rule can see both.

---

## Step 1: Given These Inputs, a Rule Gives an Output

A short recap first. Here is an ordinary L4 rule, answering one small question: which of two numbers is the larger?

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
`the greater of` a b MEANS IF a AT LEAST b THEN a ELSE b
```

A rule is told some facts about the case in front of it (its **"inputs"**, the names listed after `GIVEN`) and works out one answer from them (its **"output"**, whose kind of thing is named after `GIVETH` — or `GIVES`, the same word in a plainer spelling). Given these inputs, a rule gives an output.

This rule's inputs are `a` and `b`. `IS A NUMBER` says what kind of thing each one is: a number, not a date, not a yes-or-no fact. Its output is a number too, which is what `GIVETH A NUMBER` says. (`MEANS` and `DECIDE … IF` are interchangeable spellings of the same thing; this page uses `MEANS` throughout.)

To use a rule, write its name and then the facts to give it, in the order the rule listed them:

```l4
#EVAL `the greater of` 40000 20000
```

`#EVAL` is not a rule. It is an instruction to L4: "work this out and show me the answer". Run the file and this comes back:

```
Result:
  40000
```

40,000 filled `a`, 20,000 filled `b`. That last line is worth dwelling on, because it is the one piece of L4 punctuation a reader of legal text will not expect. **A rule's name followed by some values is that rule being used on those values.** There are no brackets, no commas and no joining word to mark them off. The values can sit along the line, as they do here, or be stacked underneath one below the other — either way they are the rule's inputs, in the order the rule declared them, and never extra conditions that also have to be true.

Its twin is written the same way, and the page uses it later:

```l4
GIVEN a IS A NUMBER
      b IS A NUMBER
GIVETH A NUMBER
`the lesser of` a b MEANS IF a AT MOST b THEN a ELSE b
```

Both of those `GIVEN` lines start at the left margin, in column 1. **A `GIVEN` at the left margin lists the inputs of the one rule written directly below it, and of nothing else.** That is the ordinary form, and this page calls it the **"rule GIVEN"**. The tutorial is about a second place the same word can go.

---

## Step 2: The Two Jobs the Word "Means" Does

Open a statute at its definitions section and you find sentences of two quite different kinds, both introduced by the word _means_.

The first kind **closes** a question:

> "the commencement date" means 16 May 2016.

After reading that sentence you know the commencement date. Nobody is ever going to ask you for it. It is settled, in the document, once, for everybody.

The second kind **opens** a question:

> In this Part, "the issuer" means the company offering the securities.

That does not tell you who the issuer is. It tells you that wherever the rest of the Part says _the issuer_, it means whoever fills that role in the case in front of you — and who that is comes from outside the document, case by case, from an application form, a register, a file, a client.

Drafters write both kinds with the same word and trust the reader to tell them apart. L4 makes you say which one you mean. A fact the document settles is written `MEANS`. Rule 100(a)(2) turns on three dollar figures the regulation settles for everybody — the figures in force after the inflation adjustment of 20 September 2022 — so all three are written that way, and nobody will ever be asked for one:

```l4
GIVETH A NUMBER
`the cut point` MEANS 124000

GIVETH A NUMBER
`the per-investor ceiling` MEANS 124000

GIVETH A NUMBER
`the minimum permitted investment` MEANS 2500
```

A fact the document deliberately leaves open is written `GIVEN`, which names the fact and says what kind of thing it is without saying what it is. Alex's income is such a fact: no amount of reading Part 227 will tell you what Alex earned.

```l4
GIVEN `annual income` IS A NUMBER
```

| You write                             | What it says                                              | Who supplies the value      |
| ------------------------------------- | --------------------------------------------------------- | --------------------------- |
| `` `the cut point` MEANS 124000 ``    | the value is settled here, in the document                | nobody; it is already here  |
| ``GIVEN `annual income` IS A NUMBER`` | there is a fact of this shape, and it varies case by case | whoever is asking, per case |

Here is the idea the rest of the page rests on. **Every rule is a question with blanks in it. `MEANS` fills a blank once for everybody. `GIVEN` names a blank and leaves it open.** As Step 5 shows, the blanks turn out to be exactly the boxes on the form.

---

## Step 3: Say It Once, Under the Heading

Rule 100(a)(2) caps what one investor may put into crowdfunded offerings over twelve months. It turns on two facts about the investor, annual income and net worth, and encoding it takes three rules: the larger of those two measures; whether both of them reach the cut point; and the limit itself, which is ten per cent of the larger measure for an investor above the cut point on both, capped at the ceiling, and otherwise five per cent, floored at the minimum.

Encode that the way almost everyone encodes it the first time — one rule at a time, each rule declaring what it needs — and you get this. Read it the way you would proofread a contract: not for the logic, for the typing.

```l4
§ `Rule 100(a)(2) as first drafted`

GIVEN `annual income` IS A NUMBER
      `net worth`     IS A NUMBER
GIVETH A NUMBER
`the larger measure (first draft)` MEANS
    `the greater of` `annual income` `net worth`

GIVEN `annual income` IS A NUMBER
      `net worth`     IS A NUMBER
GIVETH A BOOLEAN
`both measures reach the cut point (first draft)` MEANS
        `annual income` AT LEAST `the cut point`
    AND `net worth`     AT LEAST `the cut point`

GIVEN `annual income` IS A NUMBER
      `net worth`     IS A NUMBER
GIVETH A NUMBER
`the 12-month limit (first draft)` MEANS
    IF `both measures reach the cut point (first draft)` `annual income` `net worth`
    THEN `the lesser of`
             ((`the larger measure (first draft)` `annual income` `net worth`) TIMES 0.10)
             `the per-investor ceiling`
    ELSE `the greater of`
             ((`the larger measure (first draft)` `annual income` `net worth`) TIMES 0.05)
             `the minimum permitted investment`
```

L4 accepts that and it gives the right answers. It is also, line for line, mostly bookkeeping: the same two facts declared three times over, then handed across again at each of the three points where the last rule uses another rule. (Those trailing names are inputs being handed over, as Step 1 explained, not further conditions.)

Why must the last rule declare the two facts at all, when all it wants is the other rules' answers? Because a `GIVEN` at the left margin belongs to the one rule directly below it. The names in the first block are the first rule's own, and nothing else in the file can see them. Add a fact to the calculation later and you are editing every one of those blocks and every point where a fact is handed across — in a file where a rule that declares a fact and never uses it looks like ordinary drafting.

Drafters solved this centuries ago, with the sentence "In this Part, 'the issuer' means …". Say it once, at the top, for everything underneath. Move the two `GIVEN` lines up under the heading — **hoist** them, which is the word this page uses from here on for that move — indent them past the `§`, and delete the other copies:

```l4
§ `Rule 100(a)(2) — How much may this investor put in?`
    GIVEN `annual income` IS A NUMBER @desc The investor's income over the last 12 months
          `net worth`     IS A NUMBER @desc The investor's net worth

GIVETH A NUMBER
`the larger measure` MEANS `the greater of` `annual income` `net worth`

GIVETH A BOOLEAN
`both measures reach the cut point` MEANS
        `annual income` AT LEAST `the cut point`
    AND `net worth`     AT LEAST `the cut point`

@export How much may this investor invest across all offerings in 12 months?
GIVETH A NUMBER
`the investor's 12-month limit` MEANS
    IF `both measures reach the cut point`
    THEN `the lesser of` (`the larger measure` TIMES 0.10) `the per-investor ceiling`
    ELSE `the greater of` (`the larger measure` TIMES 0.05) `the minimum permitted investment`
```

**A `GIVEN` written under a section heading, indented past the `§`, declares a fact once for the whole section. That is a "section GIVEN"** — the subject of this tutorial, and the counterpart of the rule GIVEN from Step 1. Every rule beneath the heading may use it. No rule has to declare it, and no rule has to be handed it. The lines that say what the law means are unchanged; what went away was never saying anything about the law.

Three smaller things in that block: `@desc` is the sentence you want a person to read when they are asked for that fact, so write it for the person who has to answer it; `@export` marks a rule as a question the outside world may put, and the sentence after it is the wording that world sees (Step 5 says what both of those do); and `TIMES` is multiplication, so `` `the larger measure` TIMES 0.10 `` is ten per cent of it.

### Where a section ends, and which facts a rule can use

Two rules settle this, and between them they answer every question you will have about it.

**A section runs from its heading down to the next heading at the same level or a higher one.** The next `§` ends the previous `§`, exactly as a new section ends the last one in an Act. A deeper heading in between ends nothing; it opens a subsection inside, and the rules there are under both headings.

Headings go as deep as your source text does. `§` is the outermost division, `§§` one inside it, `§§§` one inside that, and so on, with no ceiling you are likely to meet: ten levels of nesting check cleanly, which is deeper than any Act goes. Depth costs a fact nothing: a fact declared under the outermost heading is available to every rule in every section beneath it, however far down. An Act with Parts, sections inside the Parts and subsections inside those can name the applicant once, at the top, and a rule three levels below will use it by name with nothing in between to carry it.

**A rule can use a section GIVEN declared under its own heading, or under any heading above it. If a rule could see two of the same name, L4 stops and names both.** Step 6 shows that happening, and what to do about it.

In the file above, the two facts are declared under `§ Rule 100(a)(2) …`; every rule that uses them sits below that heading and above the next `§`; so every one of them may.

(One further allowance exists: if a rule sits under no heading that declares the name it wants, and exactly one fact of that name exists anywhere in the file, L4 lets the rule use it. Do not lean on that — write a rule under the heading whose facts it uses, and the two rules above tell you everything.)

---

## Step 4: Get the Column Right

One feature of the page tells a section GIVEN from a rule GIVEN: **the column the word `GIVEN` starts in.**

| Spelling                                | Belongs to                                                        |
| --------------------------------------- | ----------------------------------------------------------------- |
| `GIVEN` indented past the heading's `§` | the whole section                                                 |
| `GIVEN` at the left margin (column 1)   | the one thing written directly below it — one rule, one `DECLARE` |

Get it wrong and you write this:

```l4
-- Wrong: at the left margin, so it belongs to the DECLARE below it
§ `Rule 100(a)(2) — How much may this investor put in?`

GIVEN `annual income` IS A NUMBER
DECLARE Investor
    HAS name IS A STRING
```

The wrong version does not slip past you. Run `l4 check` and among its errors this one tells you what to type:

```
This GIVEN starts at column 1, so it is the signature of the declaration
below it -- and that declaration never uses

  `annual income`

If `annual income` was meant as a binder for the whole of

  § `Rule 100(a)(2) — How much may this investor put in?`

indent the GIVEN so that it starts past the § of the heading:

  § <heading>
      GIVEN `annual income` IS A <type>
```

Two of that message's phrases are the tool's words rather than yours. `the signature of the declaration below it` means the list of inputs belonging to the one rule or `DECLARE` written underneath — a rule GIVEN. `a binder for the whole of § …` means a fact named once for that whole section — a section GIVEN.

That check fires where the mistake is unmistakable: a left-margin `GIVEN` stranded above a `DECLARE` or an `ASSUME` that makes no use of the name. It does **not** fire above an ordinary rule, because a rule that ignores one of its own inputs is a normal thing to write and looks identical on the page.

So know what the mistake does when it bites. The rule below the stray `GIVEN` stops being a plain yes-or-no fact: it becomes a rule that must be handed an income every time it is used. Any other rule in the section that uses it by name, expecting a plain yes or no, is told that what it got is the wrong kind of thing.

Two reading notes before that message, and they hold for every message shaped like it. Where it says `rules.l4:10:8-17` it is pointing at a place in a file: the file's name, then the line number, then the run of characters along that line. The file names, line numbers and character positions in these examples are made up — there is no `rules.l4` in this tutorial, and the message you see will name your own file at your own line. And where the message says _type_, read _kind of thing_, which is the phrase this page has used for that idea throughout: a number, a date, a yes-or-no fact.

```
The type of this definition must match its type signature at rules.l4:10:8-17, namely

  BOOLEAN

but is here of type

  FUNCTION FROM NUMBER TO BOOLEAN
```

`FUNCTION FROM NUMBER TO BOOLEAN` is the giveaway: "a rule that must first be given a number, and then answers yes or no". If you meant a plain yes-or-no fact and L4 reports that instead, look at the column of the nearest `GIVEN` above it. If no other rule uses the affected one, nothing complains at all and the fact simply belongs to that rule instead of to the section — so indent deliberately. (Reformatting a file never moves a `GIVEN` across the column boundary, so tidying cannot introduce the slip.)

---

## Step 5: Following the Chain of Rules

Look again at `the investor's 12-month limit` in the tidied section above. It does not mention Alex's income. It does not mention Alex's net worth. It relies on two other rules, and those rules use the facts. Before the hoist it had to be told both facts and hand both on at three separate points, purely so the rules it relies on could have them; that threading was bookkeeping, not law, and it is gone.

Which prompts the question a thoughtful reader asks next: **if the question does not name the facts, how does anybody know which facts to ask Alex for?**

L4 works it out, by following the chain of rules. Starting from the question you are asking, it looks at every rule that question relies on, and every rule those rules rely on, all the way down, and collects every section GIVEN any of them uses. Here the chain is short: the limit relies on `both measures reach the cut point` and `the larger measure`, and those two use `annual income` and `net worth`. The collected list is those two facts and nothing else — and because the question is marked `@export`, that list is published as what anyone asking it must send, each fact carrying its `@desc` sentence. You maintain none of it by hand.

### Answering it for Alex

Facts come from outside the file, from whoever is asking. The way to do that today is the command line — the place where you type instructions to your computer one line at a time, which is not the `.l4` file and not anywhere inside it. Write the cases in a second file, in the notation called JavaScript Object Notation (JSON): one case per pair of braces `{ }`, with an entry for every fact on the list. Alex comes first, then a wealthier investor for contrast (`investors.json`):

```json
[
  { "annual income": 40000, "net worth": 20000 },
  { "annual income": 300000, "net worth": 900000 }
]
```

Then name the question and the cases. `l4 batch` is the instruction that runs a whole batch of cases through one question in a single go, which is where its name comes from. `--entrypoint` is where you write the name of the rule you want answered, the way you would name the clause you are asking about; `--inputs` is the file of cases:

```bash
l4 batch what-a-section-needs-to-know.l4 \
  --entrypoint "the investor's 12-month limit" \
  --inputs investors.json
```

One line of answer comes back per case:

```
{"diagnostics":[],"input":{"annual income":40000,"net worth":20000},"output":[{"result":2500,"trace":null}],"status":"success"}
{"diagnostics":[],"input":{"annual income":300000,"net worth":900000},"output":[{"result":90000,"trace":null}],"status":"success"}
```

Six things are written on each of those lines, and only one of them is the answer. `input` repeats the case that was asked, so that what was asked and what was decided stay on one line. `result` is the answer. `status` says whether the case ran at all, and `success` means it did. `diagnostics` is the list of things that went wrong, and the empty pair of square brackets `[]` means that list is empty — nothing went wrong. `output` sits inside square brackets because the tool always writes it as a list, even where, as here, the list holds one answer. `trace` would hold a step-by-step working of how the answer was reached, which nobody asked for here; the word beside it is the tool's way of writing _there is none_ (**"null"**). Nothing on either line is a warning, and nothing is missing.

Alex is below the cut point on both measures, so five per cent applies: five per cent of $40,000 is $2,000, under the floor, so the floor of $2,500 governs. The second investor is above it on both, so ten per cent of the larger measure applies: $90,000, below the ceiling. Each line carries the case alongside the answer, so what was asked and what was decided is one line, not two files.

**Leave a fact out and you are told which one.** Send Alex's income with no net worth:

```
{"diagnostics":["Missing required field 'net worth' in JSON object"],"input":{"annual income":40000},"output":[{"result":{"error":"Missing required field 'net worth' in JSON object\n"},"trace":null}],"status":"error"}
```

`net worth` is required because the chain of rules reaches it. Nothing else is required, because nothing else is reached, and a fact you send that the question never reaches is ignored.

### Asking before the facts arrive

Put `#EVAL` on the question and run the file with no case at all, and the answer is not a number:

```
Result:
  I could not continue evaluating, because I needed to know the value of
    `annual income`
  but it is an assumed term.
```

That is easy to mistake for a complaint about your rule. It is not; the rule is fine. "An assumed term" is a fact the file names but does not settle — exactly what you wrote the `GIVEN` to say. The tool says _assumed_ of any fact left open, whichever keyword named it: a section `GIVEN` and an older `ASSUME` report in exactly these words, so meeting the word here is not a sign that your `GIVEN` was quietly treated as something else. L4 names the first blank it reached and stops, rather than guessing a value and handing you a number that looks like an answer. (That is why the `#EVAL` line is shown here and is not in the companion file: a run ending this way counts as a run that did not succeed, and every file in this documentation must succeed.)

What you _can_ do with no facts at all is ask what kind of answer a rule gives:

```l4
#CHECK `the investor's 12-month limit`
```

which reports `NUMBER`. Checking that the rules fit together needs no facts about anybody; producing an answer needs the facts.

Run the file whole, and among the tool's notes this comes back:

```
Evaluation[1] @ what-a-section-needs-to-know.l4:40:1-35

Result:
  40000


Trace:
  (no trace captured; add #EVALTRACE to the directive)
```

One block, because the file holds one `#EVAL`: the recap from Step 1. The two `#CHECK` lines answer `NUMBER` and `BOOLEAN`, and they report as information among the file's other messages rather than as blocks of their own; in an editor they appear against the line you wrote them on. The run ends successfully, which is the point of putting `#CHECK` in a file and keeping `#EVAL` out of one whose facts nobody has supplied.

What you cannot do today is keep worked cases against a section's facts — three or four applicants you re-run after every edit, as a standing check on your encoding — inside the `.l4` file. That is what the proposed spelling below is for. Until it is built, those cases live in a `.json` file next to the `.l4` file and run with `l4 batch`: the same discipline, kept in two files instead of one.

_Proposed, not landed (2026-09-04) — designed and written down, but not yet built: supplying a fact inside the file itself, by writing `WITH` after the rule's name and then the fact's name, `IS`, and the value — for example ``#EVAL `the investor's 12-month limit` WITH `annual income` IS 40000``, and the same spelling where one rule uses another. Write that line today and the file is rejected: L4 answers `(which is not a function) to (named) arguments here.`, meaning the rule takes no inputs of its own. It is not quietly ignored. Until it is built, facts come from outside the file: a web form, `l4 batch`, or the published service — the same rules put behind a web address, where other people and other programs can ask them._

### Two questions, two forms

The second question gets its own heading and its own six facts about the company, not one of them about income:

```l4
§ `Rule 100(b) — May this company raise money?`
    GIVEN `the company is organized under the law of a State` IS A BOOLEAN @desc Is the company organized under the law of a State or territory of the United States, or the District of Columbia?
          `the company reports under the Exchange Act` IS A BOOLEAN @desc Is the company required to file reports under section 13 or 15(d) of the Exchange Act?
          `the company is an investment company` IS A BOOLEAN @desc Is the company an investment company?
          `the company is disqualified under Rule 503(a)` IS A BOOLEAN @desc Is the company disqualified under Rule 503(a)?
          `the company has filed its two most recent annual reports` IS A BOOLEAN @desc Has the company filed the annual reports required by Rule 202 for the two most recent years?
          `the company has a specific business plan` IS A BOOLEAN @desc Does the company have a specific business plan, other than to merge with or acquire an unidentified company?

GIVETH A BOOLEAN
`the company is excluded by Rule 100(b)` MEANS
        NOT `the company is organized under the law of a State`
    OR      `the company reports under the Exchange Act`
    OR      `the company is an investment company`
    OR      `the company is disqualified under Rule 503(a)`
    OR  NOT `the company has filed its two most recent annual reports`
    OR  NOT `the company has a specific business plan`

@export May this company raise money through crowdfunding?
GIVETH A BOOLEAN
`the company may use the crowdfunding exemption` MEANS
    NOT `the company is excluded by Rule 100(b)`
```

Two headings, two published lists of facts, two forms. The sketches below show the shape a form takes rather than a screenshot, but the wording is real: every box is a fact the chain of rules reaches, and the sentence shown with it is the `@desc` you wrote for that fact. Where exactly the sentence sits — beside the box, or beneath it as help text — is the form's own business, and differs between the systems L4 generates forms for; what the file fixes is that your sentence, and not a name invented by a tool, is what the person reads.

```text
  How much may this investor invest across all offerings in 12 months?

    The investor's income over the last 12 months   [  40000 ]
    The investor's net worth                        [  20000 ]

                                                        [ Ask ]
```

```text
  May this company raise money through crowdfunding?

    [x] Is the company organized under the law of a State or territory
        of the United States, or the District of Columbia?
    [ ] Is the company required to file reports under section 13 or
        15(d) of the Exchange Act?
    [x] Does the company have a specific business plan, other than to
        merge with or acquire an unidentified company?
    ... and three more

                                                        [ Ask ]
```

Two boxes on one, six on the other, and no box on both. Nobody drew either form by hand, and nobody maintains a list of which question needs which boxes.

### Checking the list before you publish

Seeing that published list set out as a list, and turning it into a form, are both part of publishing the rules; [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) shows you how. Before you get that far there is a rough check you can make from the command line. Give `l4 batch` a case with nothing in it at all — a file holding `[{}]` — and it names a fact the question requires:

```
{"diagnostics":["Missing required field 'annual income' in JSON object"],"input":{},"output":[{"result":{"error":"Missing required field 'annual income' in JSON object\n"},"trace":null}],"status":"error"}
```

It names one fact, not the whole list, so it confirms rather than enumerates: fill that one in, run it again, and it names the next. For a section with two facts that is a quick way to satisfy yourself both came out right. For a section with twenty, it is the published list you want.

---

## Step 6: "For the Purposes of This Section"

Statutes reuse words and mean different things by them in different places, and no reader is confused, because each definition governs its own stretch of text.

They do it with letters too. Section 1 of the Bribery Act 2010 opens by introducing "a person ('P')", and so does section 6 — and the P of section 1, who offers an advantage to another person, is not the P of section 6, who bribes a foreign public official ('F'). A letter introduced once and used for the rest of a section is a section GIVEN in all but name, and L4 spells it almost as the Act does:

```l4
DECLARE Person
    HAS `offered an advantage`         IS A BOOLEAN
        `is a foreign public official` IS A BOOLEAN

§ `Bribery Act 2010`

§§ `1. Offences of bribing another person`
    GIVEN p IS A Person

GIVETH A BOOLEAN
`P offered an advantage` MEANS p's `offered an advantage`

§§ `6. Bribery of foreign public officials`
    GIVEN p IS A Person
          f IS A Person

GIVETH A BOOLEAN
`F is a foreign public official` MEANS f's `is a foreign public official`
```

(`§§` is a heading one level down from `§`, the way a subsection sits under a section. `p` and `f` are ordinary L4 names — a single letter is as good a name as `alex`, and here it is the name the statute itself chose. `DECLARE Person` says what kind of thing a person is in this encoding, and `` p's `offered an advantage` `` reads one of those facts off `p`, the way the apostrophe reads in English.)

Those are **two different `p`s**. `P offered an advantage` sits under section 1's heading, so the `p` it reads is section 1's; `F is a foreign public official` sits under section 6's heading, so the people it can reach are section 6's `p` and `f`. Neither rule reaches the other section's `p`: each finds the `p` its own heading declares.

The same happens with words. Two sections may each name a fact `the fee`:

```l4
§ `Fees`

§§ `2. Application fee`
    GIVEN `the fee` IS A NUMBER

GIVETH A NUMBER
`the application fee payable` MEANS `the fee`      -- section 2's fee

§§ `5. Renewal fee`
    GIVEN `the fee` IS A NUMBER

GIVETH A NUMBER
`the renewal fee payable` MEANS `the fee`          -- section 5's fee, a different fact
```

Run the two rules from Step 3 through that file and every line is settled. `§§ 2. Application fee` runs from its own line to the next heading at the same level, `§§ 5. Renewal fee`. So `the application fee payable` sits inside section 2, which is a heading above it that declares `the fee` — that is the fee it uses, and section 5's fee is not in its stretch of the file at all. `the renewal fee payable` is the mirror image. Neither rule had to say which fee it meant, and neither could have got the other.

### When a rule can see two

Put a rule in a third subsection, under neither of the other two, while both still say `the fee`:

```l4
§§ `7. Refunds`

GIVETH A NUMBER
`the refund` MEANS `the fee` TIMES 0.5
```

Section 7 declares no fee of its own, and both of the others are in view. L4 refuses to pick one, and names both by the section that declared each:

```
There are multiple definitions for the identifier

  `the fee`

and I do not have sufficient information to make a choice between them.
The options are:

  Fees.`5. Renewal fee`.`the fee` (defined at fees.l4:10:11-20) of type NUMBER
  Fees.`2. Application fee`.`the fee` (defined at fees.l4:4:11-20) of type NUMBER
```

("Identifier" is the tool's word for a name you wrote; here it is `the fee`. The last two lines name the two facts by the section that declared each, and give the place where each was written, in the file-then-line-then-characters form Step 4 explained. `fees.l4` is another made-up file name.)

That message asks a question about the source text, and answering it is a drafting decision. Each answer says something different about what the provision means:

| If                                                           | Then                                                                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| it is really one fee across the whole Part                   | **hoist** _(available today)_: move the `GIVEN` up to the `§ Fees` heading and delete both copies                        |
| they are really two fees                                     | **rename** _(available today)_: call them `the application fee` and `the renewal fee`, as a careful drafter would have   |
| section 7's fee is section 2's fee, for this one calculation | **bridge** _(proposed, not landed — see below)_: say at the point where section 7 borrows the fee which fee it is taking |

_Proposed, not landed (2026-09-04): the bridge spelling, `WITH` followed by the fact's name, `IS`, and the value to give it. It is the same proposed `WITH` as in Step 5, and today it is rejected in the same way. Until it is built, the two ways out are to hoist or to rename._

### When no heading sits above both

Two Parts of one Act may both be about the applicant, with no heading over the pair to hoist to. The answer is still the first row of that table, and it is a drafting act rather than a typing fix: give the two Parts a heading of their own — the Act itself, or the Chapter that holds both — and declare the fact there, once. A heading is a line you are free to write, and one that spans two Parts says something true about the source text. A fact declared at the top reaches every rule in every section beneath it, however deep the Parts and sections go, so nothing below has to be touched.

Do not instead lean on the allowance mentioned in Step 3, where a rule under no declaring heading may use a name of which exactly one exists anywhere in the file. That allowance holds only while exactly one exists. The day somebody writes a second section that names the same fact, every rule which leaned on it stops, with the message above.

---

## Migrating a File That Uses `ASSUME`

Older L4 files name their per-case facts with `ASSUME`, at the left margin, anywhere in the file. **Those files still work**: `ASSUME` reads, checks, publishes and runs exactly as it always has, and no warning is reported for it. It is deprecated for this job as of 2026-09-04, because the one keyword was doing three unrelated jobs at once and a reader could not tell from the keyword which was meant. To move one, put it under the heading of the section whose rules use it, indent it past the `§`, and change the word. Nothing else changes — not the fact's name, not the rule's name, not a line of any rule that uses it:

```l4
§ `Intermediaries, before migration`

ASSUME `the funding portal is registered` IS A BOOLEAN

GIVETH A BOOLEAN
`the intermediary requirement is met (before)` MEANS
    `the funding portal is registered`
```

```l4
§ `Intermediaries, after migration`
    GIVEN `the funding portal is registered` IS A BOOLEAN

GIVETH A BOOLEAN
`the intermediary requirement is met (after)` MEANS
    `the funding portal is registered`
```

(The two rule names differ only because the companion file keeps both versions side by side, and one file cannot have two rules of the same name. In a real migration you edit the `ASSUME` line in place and leave every other line alone.)

Behaviour in this release is identical: both wait to be supplied, and both appear in the published list of facts of any `@export`ed question that reaches them. What you gain is that the fact has a stated home, visible at a glance to a reader and to every tool that reads the file. There is no hurry; migrate when you are in the file for other reasons.

One `ASSUME` does not migrate this way. `ASSUME T IS A TYPE` does not name a fact about a case at all: it names a kind of thing, the way a statute says "an insurer" throughout without setting out what an insurer is made of. Write it as `DECLARE T`, a name with no stated contents. See [`ASSUME`](../../reference/types/ASSUME.md) for the keyword's other uses.

---

## What You Learned

- **Say it once.** A `GIVEN` written under a section heading, indented past the `§` — a section GIVEN — names a fact once for every rule in the section, instead of every rule declaring it and handing it on. That is the drafting convention "In this Part, 'the issuer' means …", made mechanical. The column decides which `GIVEN` you wrote: past the `§` it is the section's, at the left margin it is the next rule's own.
- **Let the rules rely on each other.** A question that names no facts of its own still knows which facts it needs, because L4 follows the chain of rules down from the question and collects what they use. That collected list is the published list of facts, the boxes on the form, and exactly what `l4 batch` requires: leave one out and it is named, send one the question never reaches and it is ignored.
- **Two sections, two meanings.** A section runs from its heading to the next heading at the same level or a higher one, and a rule uses a section GIVEN declared under its own heading or any heading above it. Statutes reuse a word — or a letter, as the Bribery Act reuses "P" — and so may you. A rule that can see two of the same name is an error naming both, and the ways out are drafting decisions: hoist if it is one thing, rename if it is two.
- Underneath all three: a definition can close a question or open one, and drafters write both with the word _means_. `MEANS` settles a value once for everybody; `GIVEN` names a blank and leaves it open for each case. `ASSUME` did that second job in older files, is deprecated for it, and still works.

---

## Next Steps

- [The section `GIVEN`](../../reference/syntax/section-given.md) — the reference page: headings inside headings, and what each tool does with a section's facts
- [Sections](../../reference/syntax/sections.md) — the full rule for which definition a name reaches when headings nest, side by side, or re-use a name, with every case in one table
- [`GIVEN`](../../reference/functions/GIVEN.md) — naming the inputs of a single rule
- [When a Rule Cannot Answer](../refuse/when-a-rule-cannot-answer.md) — which cases the model does not cover, and how to say so
- [Five Kinds of No Answer](../../concepts/legal-modeling/non-answers.md) — where a fact nobody has supplied sits among the other ways of having no answer
- [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) — putting these two questions behind a live address
- [Using the l4 command line](../getting-started/l4-cli.md) — `l4 batch` and the rest of the command line
- [Encoding Legislation](../getting-started/encoding-legislation.md) — turning a longer provision into rules
