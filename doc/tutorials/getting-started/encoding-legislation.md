# Encoding Legislation

Turn a legal provision into L4 rules.

**Prerequisites:** [Your First L4 File](first-l4-file.md)

---

## The words this page uses

Two words do most of the work on this page, so they are worth fixing before
anything else.

A rule is told some facts about the case in front of it — the names listed
after `GIVEN` (its **"inputs"**) — and works out one answer from them (its
**"output"**, whose kind of thing is named after `GIVETH`, or `GIVES`, which is
the same word in a plainer spelling). Given these inputs, a rule gives an
output.

An input can be written in either of two places, and this page uses both:

- a **"rule GIVEN"** is the ordinary form, written immediately above one rule.
  It lists that rule's own inputs, and no other rule can read them.
- a **"section GIVEN"** is written once under a section heading, indented past
  the `§`. It lists a fact that every rule in that section may read, without any
  of them repeating it.

Legal drafters already have the second device. "In this Part, 'the issuer'
means …" declares a name once, at the top of a stretch of provisions, and every
provision below is entitled to use it. A section `GIVEN` is that sentence, made
machine-readable.

---

## What You'll Build

You will encode this provision from an imaginary Alcohol Act:

> **Section 3.** A person must not sell alcohol if:
> (a) the person is a body corporate;
> (b) the person engages in business for profit;
> (c) the person is not a public house or hotel; and
> (d) any of the following applies:
> (i) the person has an unspent conviction for fraud;
> (ii) the person has an unspent conviction for providing misleading information; or
> (iii) the person has an alcohol banning order.

Two things about the drafting are worth noticing before you start.

First, the Act says "the person" and never gives that person a name. That is
deliberate on the drafter's part: the provision is meant to apply to whoever
turns up. Where this page quotes the Act, it keeps the Act's own word, "the
person". Where this page invents a scenario to test the rule against, the
subject of that scenario gets a name, because a worked example that says "the
person" three times over is a worked example nobody can follow.

Second, in this Act — as in most — "person" includes a company. Limb (a) asks
whether the person is a body corporate, which would be a strange question to
ask about a human being. So the named examples further down are companies:
Blue Anchor Ltd, Riverside Drinks Ltd, Meridian Wines Ltd.

**Complete example:** [encoding-legislation-example.l4](encoding-legislation-example.l4)

---

## Step 1: Analyze the Structure

Before writing anything in L4, read the provision for its shape. Three
questions get you there:

1. **What is the outcome?** "must not sell alcohol".
2. **What are the conditions?** (a), (b), (c) and (d) — the word "and" at the
   end of (c) tells you all four must hold.
3. **Are there sub-conditions?** (d)(i), (d)(ii) and (d)(iii) — the word "or"
   at the end of (ii) tells you any one of the three is enough.

Written out, the shape is:

```
(a) AND (b) AND (c) AND ((d)(i) OR (d)(ii) OR (d)(iii))
```

Getting this on paper first is worth the two minutes. Almost every mistake in
an encoding is a mistake in this line, not in the L4 below it.

---

## Step 2: Name the Blanks

Section 3 is not a statement of fact. It is a question with blanks in it: _is
this person a body corporate? does this person trade for profit?_ Fill the
blanks and the answer follows. Leave one blank and there is no answer yet — not
because the law is unclear, but because nobody has said which person is being
asked about.

So the first job is to name the blanks. Section 3 has seven:

```l4
§ `Imaginary Alcohol Act - Section 3`
    GIVEN `the person is a body corporate` IS A BOOLEAN
          `the person engages in business for profit` IS A BOOLEAN
          `the person is a public house` IS A BOOLEAN
          `the person is a hotel` IS A BOOLEAN
          `the person has an unspent conviction for fraud` IS A BOOLEAN
          `the person has an unspent conviction for providing misleading information` IS A BOOLEAN
          `the person has an alcohol banning order` IS A BOOLEAN
```

`IS A BOOLEAN` says what kind of thing each blank holds: a yes-or-no fact, so
the only two things that can go in it are `TRUE` and `FALSE`.

A name can carry one more thing: `@desc`, the plain question a member of the
public will be shown when this blank has to be filled in.

```l4
    GIVEN `the person is a body corporate` IS A BOOLEAN @desc Is the person a body corporate?
```

The name is what the rules below say; the `@desc` is what the form asks. The
downloadable file for this page carries a `@desc` on all seven names, and it is
worth writing them once you know what the seven names are.

`GIVEN` names a fact the document leaves open, to be supplied one case at a
time. It is the opposite of `MEANS`, which fixes a fact once and for all. A
statutory definition — "'body corporate' means a company registered under Part
2" — is a `MEANS`, because it says the same thing in every case. "The person"
is a `GIVEN`, because it is a different person every time the section is
applied.

That distinction is the one to hold on to. Ask of each fact: _does the document
settle this, or does the document leave it to be filled in?_ Settled facts are
`MEANS`. Facts left open are `GIVEN`.

To **"supply"** a fact is to hand in its answer for one particular case. These
seven are the seven answers somebody has to hand in before section 3 can be
worked out at all; step 4 shows who hands them in, and how.

### Why declare them under the heading?

The seven names above are written as a section `GIVEN` — one `GIVEN`, indented
under the section heading, belonging to the whole of section 3. Every rule
beneath the heading can read those seven names, and no rule has to repeat them.

That matters more than it looks. Section 3 is really three or four questions —
is this a commercial enterprise, is it exempt, is it disqualified — and each one
needs the same handful of facts about the same person. Written as a rule
`GIVEN` on each of them, the seven names would be written out three or four
times over, and a mistyped name in the fourth copy is one fact silently split
into two: L4 will happily treat `the person is a hotel` and `the person is an
hotel` as different facts, and the form will ask about both. Written once under
the heading, there is one place to read, one place to edit, and one list for the
tools to work from.

### The column rule

The indentation is not decoration. **A `GIVEN` belongs to the section when its
keyword starts to the right of the heading's `§`.** A `GIVEN` at column 1 means
what it has always meant: it is the rule `GIVEN` of the one declaration
immediately below it.

```l4
-- ✅ Right: a section GIVEN, for the whole of section 3
§ `Imaginary Alcohol Act - Section 3`
    GIVEN `the person is a body corporate` IS A BOOLEAN

-- ❌ Wrong: a rule GIVEN, for the next rule only
§ `Imaginary Alcohol Act - Section 3`

GIVEN `the person is a body corporate` IS A BOOLEAN
```

Get it wrong and the first rule below quietly takes the names as its own. The
rule that then goes wrong is the _next_ one, which can no longer see them:

```
I could not find a definition for the identifier

  `the person is a public house`

which I have inferred to be of type:
...
```

An **"identifier"** is L4's word for a name, and the "type" it goes on to
mention is the kind of thing that name holds. So the message says: _this name
is used here, and I cannot see anywhere it was declared._

If you meet that error and the name is right there at the top of the section,
check the column before you check anything else. It is the likeliest cause and
the quickest to rule out.

### Migrating an existing `ASSUME`

Older L4 wrote these facts as `ASSUME`s at the left margin. Files you have
already written go on working exactly as before: L4 still accepts them, still
checks them, and still publishes their rules as services. Nothing you have
written will break — but for a fact the rules of a section share, the section
`GIVEN` is now the form to reach for.

To migrate `ASSUME x IS A T`, move the line under the heading of the section
whose rules read it, indent it past the `§`, and write `GIVEN x IS A T`. The
two behave identically in the version of L4 you have: both name a fact nobody
has supplied yet, and both are asked for in the same way when someone supplies
a case.

### Two sections, the same name

Two sections may declare the same name for different things, exactly as
statutes do ("for the purposes of sections 1 and 2, 'proceeds' means …; for the
purposes of section 3, 'proceeds' means …"). Each section's rules read their
own. A rule placed where it can see two same-named section `GIVEN`s at once is
an error, and the message names both sections so you can see which two you have
collided. See [the section `GIVEN`](../../reference/syntax/section-given.md)
for the full rules.

---

## Step 3: Encode the Rule

Now translate the legal text directly:

```l4
-- Section 3: Prohibition on selling alcohol
DECIDE `the person must not sell alcohol`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`
    AND NOT `the person is a public house`
    AND NOT `the person is a hotel`
    AND (
        `the person has an unspent conviction for fraud`
        OR `the person has an unspent conviction for providing misleading information`
        OR `the person has an alcohol banning order`
    )
```

The rule declares no inputs of its own — there is no rule `GIVEN` above it. It
reads all seven names from the section heading.

### Matching the Legal Text

Notice how closely the L4 tracks the legislation:

| Legal Text                                  | L4                                                     |
| ------------------------------------------- | ------------------------------------------------------ |
| "the person is a body corporate"            | `` `the person is a body corporate` ``                 |
| "the person is not a public house or hotel" | `` NOT `..is a public house` AND NOT `..is a hotel` `` |
| "any of the following applies"              | `(...OR...OR...)`                                      |

This is worth the effort. An encoding that uses the statute's own words can be
checked against the statute line by line, by a lawyer who does not read L4 at
all. An encoding that paraphrases cannot.

### Asking before the blanks are filled

Ask the rule for an answer with none of the seven facts supplied and it tells
you so, naming the first thing it needed:

```
I could not continue evaluating, because I needed to know the value of
  `the person is a body corporate`
but it is an assumed term.
```

Two words in that message are worth unpacking. "Evaluating" is L4's word for
working the rule out. An **"assumed term"** is a name the file assumes someone
will supply for the case in hand, and never settles for itself — which is
exactly what a `GIVEN` is, whether you wrote it under the heading as a section
`GIVEN` or above one rule as a rule `GIVEN`. So the message reads: _I got as
far as limb (a) and stopped, because nobody has told me whether this person is
a body corporate._

That is not a bug and it is not a failure of the rule. It is the rule telling
you which blank is still empty — one blank, the first one it needed, in the
order the rule reads them. Fill that one and ask again, and it will name the
next one it needs.

---

## Step 4: Write Test Cases

A test is a scenario plus the answer you expect. Three scenarios are enough to
pin down the shape of section 3: an exempt case, a prohibited case, and a clean
case. Each gets a named company, so that the reasoning can be followed in
words.

_Proposed, not landed (2026-09-04): supplying a value with `WITH` at an
instruction such as `#EVAL` is not in the version of L4 you have. It is being
built now, so the three blocks below will not run until it arrives, and they
are not in the downloadable file. Until then, supply the facts from outside the
file instead — from a web form, from `l4 batch`, or from a program asking the
published rule. See "Supplying a case today", below, which is the way that
works today._

`WITH` hands the rule its answers: one line for each blank, written as
`` `name` IS value ``, with commas between them. (If you have met `WITH`
building a record — `T WITH f IS 1, g IS TRUE` — this is the same word doing
the same job, filling named slots.)

```l4
{-
Scenario 1: Blue Anchor Ltd, a corporate pub (exempt)
- Body corporate: Yes
- For profit: Yes
- Public house: Yes (exempt!)
Expected: FALSE (not prohibited, because it is a public house)
-}
#EVAL `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS TRUE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS TRUE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS FALSE

{-
Scenario 2: Riverside Drinks Ltd, a banned corporate (prohibited)
- Body corporate: Yes
- For profit: Yes
- Public house: No
- Hotel: No
- Banning order: Yes
Expected: TRUE (prohibited)
-}
#EVAL `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS FALSE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS FALSE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS TRUE

{-
Scenario 3: Meridian Wines Ltd, a clean corporate (not prohibited)
- Body corporate: Yes
- For profit: Yes
- No exemption, but nothing disqualifying either
Expected: FALSE (not prohibited: no limb of (d) is made out)
-}
#EVAL `the person must not sell alcohol` WITH
    `the person is a body corporate` IS TRUE,
    `the person engages in business for profit` IS TRUE,
    `the person is a public house` IS FALSE,
    `the person is a hotel` IS FALSE,
    `the person has an unspent conviction for fraud` IS FALSE,
    `the person has an unspent conviction for providing misleading information` IS FALSE,
    `the person has an alcohol banning order` IS FALSE
```

Scenario 1 is the interesting one. Blue Anchor Ltd has an unspent fraud
conviction, so limb (d) is satisfied — but it is a public house, so limb (c) is
not, and the prohibition does not bite. A test that only ever exercised the
obvious cases would never have revealed an encoding that dropped limb (c).

### Supplying a case today

The seven names are not only documentation. They are the list of questions the
tools ask. Whoever does the asking — a member of the public filling in a web
form, another program, or you at a command prompt — is the rule's
**"caller"**, and the seven names are exactly what the caller has to hand in.

Mark the rule `@export`. An **"annotation"** is a line beginning with `@`
that tells the tools something about the rule underneath it, without changing
what that rule decides; `@export` says _this is a rule outsiders may ask_.
Writing it does not by itself put your rule anywhere: it tells the tools which
rules to offer when the file is served. Once it is there, every fact the rule
reads becomes a fact the caller has to supply. That includes facts the rule
reaches indirectly: L4 follows the chain of rules all the way down, so a fact
read by a rule that this rule relies on is asked for too.

```l4
@export Decide whether a person is prohibited from selling alcohol under s.3
DECIDE `the person must not sell alcohol`
IF  ...
```

Now write your scenarios out as a file of cases. The format is JavaScript
Object Notation (**"JSON"**), the plain-text format these tools read and write:
square brackets hold the list of cases, and each case is one set of curly
braces pairing each of the seven names with `true` or `false`. Save the block
below as `cases.json`, in the same folder as your `.l4` file:

```json
[
  {
    "the person is a body corporate": true,
    "the person engages in business for profit": true,
    "the person is a public house": true,
    "the person is a hotel": false,
    "the person has an unspent conviction for fraud": true,
    "the person has an unspent conviction for providing misleading information": false,
    "the person has an alcohol banning order": false
  }
]
```

Then open a command prompt — a terminal window in which you type commands
rather than click them — move to the folder holding those two files, and type:

```bash
l4 batch encoding-legislation-example.l4 --inputs cases.json
```

`l4` is the L4 command-line tool, the same one
[Your First L4 File](first-l4-file.md) used to run a file. `batch` is its
instruction for running one `@export`ed rule over a whole file of cases, and
`--inputs` says which file the cases are in — that name is the downloadable
example file, so put your own file's name there if you called it something
else. If you have never used a command
prompt, there is a whole tutorial on the command-line interface
(**"CLI"**): [Using the l4 CLI](l4-cli.md) installs the tool and walks through
it one command at a time.

You get one line of output for each case in the file. It repeats the case it
was given, under `input`, and gives the answer it worked out, under `output`.
`diagnostics` lists any complaints L4 has about the file, `status` says whether
the run got through, and `trace` would hold the step-by-step reasoning if you
had asked for it. The seven facts echoed back are elided here as `{…}` to keep
the line readable:

```
{"diagnostics":[],"input":{…},"output":[{"result":false,"trace":null}],"status":"success"}
```

`"result":false` — Blue Anchor Ltd is exempt, which is scenario 1's expected
answer. `"diagnostics":[]` is an empty list, so L4 found nothing to complain
about in the file.

The same list of seven drives every other way of asking the rule, and this is
where declaring it once pays for itself twice over. Generate a guided web
interview from this file and it asks exactly seven yes-or-no questions, one per
name, worded from the name itself, with the `@desc` you wrote beside each name
in step 2 as the help text under the question:

```yaml
id: q_the_person_engages_in_business_for_profit
question: |
  the person engages in business for profit
fields:
  - "the person engages in business for profit": the_person_engages_in_business_for_profit
    datatype: yesnoradio
    help: "Does the person engage in business for profit?"
```

Publish the rule as a service and the request it accepts requires exactly those
same seven fields. One list, written once, in one place, and every way of
asking the rule reads it.

---

## Step 5: Break the Rule into Named Sub-rules

The single rule in step 3 is faithful, but it is a wall of text. For anything
larger, say each idea once and give it a name:

```l4
-- Sub-rule: Is this a commercial enterprise?
DECIDE `is commercial enterprise`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`

-- Sub-rule: Is this an exempt establishment?
DECIDE `is exempt establishment`
IF  `the person is a public house`
    OR `the person is a hotel`

-- Sub-rule: Does the person have disqualifying factors?
DECIDE `has disqualifying factors`
IF  `the person has an unspent conviction for fraud`
    OR `the person has an unspent conviction for providing misleading information`
    OR `the person has an alcohol banning order`

-- Main rule: the prohibition, assembled from the three sub-rules
DECIDE `the person must not sell alcohol (tidied)`
IF  `is commercial enterprise`
    AND NOT `is exempt establishment`
    AND `has disqualifying factors`
```

This version is easier to read and easier to maintain, and — this is the part
that surprises people — splitting the rule up costs nothing in the questions
anybody is asked.

Each sub-rule reads the section's seven names directly, so none of them needs
inputs of its own. The main rule still asks the caller for the same seven
facts, because those are the facts its sub-rules between them read, and L4
follows the chain of rules all the way down to work out what to ask for.
Splitting a rule up does not change a single question the form asks.

### Sub-headings inside a section

Once a section holds several rules, it helps to group them. `§§` — two section
marks instead of one — starts a subsection _inside_ the section above it, the
way s.3(1) and s.3(2) sit inside s.3:

```l4
§ `Imaginary Alcohol Act - Section 3`
    GIVEN `the person is a body corporate` IS A BOOLEAN
          ...

§§ `Main rule`

§§ `Sub-rules`
```

A `§§` does not start a fresh section, so it does not cut the rules under it
off from anything above. **Rules under a `§§` still read the section `GIVEN`
declared at the top of the section.** The column rule from step 2 is about
where a `GIVEN` is written, not about which heading a rule happens to sit
under: the seven names reach every rule beneath the `§` heading, including the
ones tucked under `§§` sub-headings.

---

## Step 6: Add Documentation

Link back to the source legislation, so the next reader can find it:

```l4
{-
Imaginary Alcohol Act 2024
==========================

Section 3 - Prohibition on Sale of Alcohol

This section implements the prohibition in s.3, which prevents
certain commercial entities from selling alcohol if they have
disqualifying factors (fraud, misleading information, or banning
orders).

Exemptions:
- Public houses (s.3(c))
- Hotels (s.3(c))

"Unspent conviction" follows the Rehabilitation of Offenders
Act interpretation - see s.2 for definitions.
-}
```

---

## Complete Example

Here is the whole downloadable file:
[encoding-legislation-example.l4](encoding-legislation-example.l4). It runs
today, start to finish, and it differs in three ways from the fragments above,
each deliberate:

- it keeps **both** encodings side by side, so you can compare them — the
  single rule that tracks the clauses of s.3 keeps the name
  `the person must not sell alcohol`, and the version assembled from sub-rules
  is named `the person must not sell alcohol (tidied)`;
- each of the seven names carries a `@desc`, the question a member of the
  public is shown;
- it ends with five `#CHECK` lines, which report what kind of thing each rule
  answers with, rather than working any of them out. `#CHECK` needs no facts
  supplied, so it runs whether or not anybody has filled the blanks in.

```l4
-- Companion file for encoding-legislation.md
--
-- Section 3 of the Imaginary Alcohol Act 2024, encoded twice: once as a single
-- rule that mirrors the provision clause by clause, and once broken into named
-- sub-rules that say each idea once.
--
-- The seven facts about the person -- the inputs of section 3 -- are declared
-- once, as a section GIVEN indented under the section heading. Every rule below
-- reads them; none of them repeats the list.

§ `Imaginary Alcohol Act - Section 3`
    GIVEN `the person is a body corporate` IS A BOOLEAN @desc Is the person a body corporate?
          `the person engages in business for profit` IS A BOOLEAN @desc Does the person engage in business for profit?
          `the person is a public house` IS A BOOLEAN @desc Is the person a public house?
          `the person is a hotel` IS A BOOLEAN @desc Is the person a hotel?
          `the person has an unspent conviction for fraud` IS A BOOLEAN @desc Does the person have an unspent conviction for fraud?
          `the person has an unspent conviction for providing misleading information` IS A BOOLEAN @desc Does the person have an unspent conviction for providing misleading information?
          `the person has an alcohol banning order` IS A BOOLEAN @desc Is the person subject to an alcohol banning order?

{-
Imaginary Alcohol Act 2024
==========================

Section 3 - Prohibition on Sale of Alcohol

This section implements the prohibition in s.3, which prevents certain
commercial entities from selling alcohol if they have disqualifying factors
(fraud, misleading information, or banning orders).

Exemptions:
- Public houses (s.3(c))
- Hotels (s.3(c))

"Unspent conviction" follows the Rehabilitation of Offenders Act
interpretation - see s.2 for definitions.
-}

§§ `Main rule`

@export Decide whether a person is prohibited from selling alcohol under s.3
DECIDE `the person must not sell alcohol`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`
    AND NOT `the person is a public house`
    AND NOT `the person is a hotel`
    AND (
        `the person has an unspent conviction for fraud`
        OR `the person has an unspent conviction for providing misleading information`
        OR `the person has an alcohol banning order`
    )

§§ `Sub-rules`

-- Sub-rule: Is this a commercial enterprise?
DECIDE `is commercial enterprise`
IF  `the person is a body corporate`
    AND `the person engages in business for profit`

-- Sub-rule: Is this an exempt establishment?
DECIDE `is exempt establishment`
IF  `the person is a public house`
    OR `the person is a hotel`

-- Sub-rule: Does the person have disqualifying factors?
DECIDE `has disqualifying factors`
IF  `the person has an unspent conviction for fraud`
    OR `the person has an unspent conviction for providing misleading information`
    OR `the person has an alcohol banning order`

-- The same prohibition, assembled from the sub-rules.
DECIDE `the person must not sell alcohol (tidied)`
IF  `is commercial enterprise`
    AND NOT `is exempt establishment`
    AND `has disqualifying factors`

§§ `Checks`

-- #CHECK reports what kind of thing a rule answers with. Every rule below
-- answers a yes-or-no question (a BOOLEAN), and every one of them has the same
-- seven blanks, filled from outside the file: by a web form, by
-- `l4 batch FILE --inputs cases.json`, or by a caller of the published service.

#CHECK `the person must not sell alcohol`
#CHECK `the person must not sell alcohol (tidied)`
#CHECK `is commercial enterprise`
#CHECK `is exempt establishment`
#CHECK `has disqualifying factors`
```

_Proposed, not landed (2026-09-04): the tests in step 4 use `#EVAL … WITH`,
which is not in the version of L4 you have. That is why they are absent from
the file above: they would not run. Until `WITH` arrives, supply the facts from
outside the file, the way "Supplying a case today" shows._

---

## Tips for Encoding Legislation

### 1. Preserve Legal Language

Use the exact terms from the legislation wherever you can:

```l4
-- ✅ Good: matches the statute
GIVEN `the person is a body corporate` IS A BOOLEAN

-- ❌ Less good: paraphrased
GIVEN isCompany IS A BOOLEAN
```

The name is not only for you. It is the wording the generated web form puts in
front of a member of the public, and the field name a caller is asked for when
the rule is published as a service. A paraphrase that drifts from the statute
drifts everywhere at once.

### 2. Carry Inert Text — Recitals, Preambles, Purpose Clauses

Not every part of a legal document is a rule. Recitals, preambles, _whereas_
clauses, purpose statements, statements of principle — the throat-clearing at
the start of a chapter — gate no decision and work nothing out. But an
_isomorphic_ encoding (one that mirrors the source, so a lawyer can check it
line by line) still has to carry them, verbatim and correctly numbered.

Reach for the `hierarchy` library. A **"library"** is a file of ready-made
names somebody else has written, which your file may borrow instead of writing
them again; `IMPORT hierarchy` at the top of your file borrows this one, and
every name in it — `item`, `render outline` and the rest — is then usable
below. (See [IMPORT](../../reference/libraries/IMPORT.md) for the details of
borrowing.)

What `hierarchy` gives you is the outline: a tree of **text** (`item "…"`),
written as a bullet list and rendered with automatic numbering. Each item is
text and nothing more — it is never worked out, only carried — so it may say
anything at all, including wording that would never be valid L4 logic:

```l4
IMPORT hierarchy

`recital scheme` MEANS LIST UpperAlpha, Decimal, LowerRoman

`recitals` MEANS
  item "RECITALS"
    • item "the Company is engaged in the business of software development;"
    • item "the Consultant has expertise in legal engineering; and"
    • item "the parties wish to record the terms of their engagement, namely"
      • item "the scope of services;"
      • item "the fees payable; and"
      • item "the term and termination."

#EVAL `render outline` `recital scheme` `recitals`
```

Three things in that block are new. `recital scheme` is a list of _numbering
styles_, one for each level of the outline: `UpperAlpha` (A, B, C), then
`Decimal` (1, 2, 3), then `LowerRoman` (i, ii, iii). Those three, along with
`LowerAlpha`, `UpperRoman` and `Bulleted`, are the six styles the library
offers; they are written as bare words with no backticks because each is a
single word. And `render outline` is a rule from the library that is given two
things — first the scheme, then the outline — and gives back the numbered text.
Naming two things in a row after a rule's name, as
`` `render outline` `recital scheme` `recitals` `` does, is how a rule with two
inputs is asked in L4.

The heading is carried verbatim; the rest is numbered by depth. You pick the
_style_ per level (`recital scheme` is upper-alpha, then decimal, then
lower-roman) and the renderer assigns the actual markers:

```
RECITALS
A      the Company is engaged in the business of software development;
B      the Consultant has expertise in legal engineering; and
C      the parties wish to record the terms of their engagement, namely
C.1    the scope of services;
C.2    the fees payable; and
C.3    the term and termination.
```

**The rule of thumb.** Ask of each passage: _does it gate any decision, or work
out any value?_ If it does neither, it is inert. Do not force it into a
`DECIDE` or a `GIVEN` — there is nothing to decide and no fact to supply — and
do not drop it either, because you would lose fidelity to the source. Capture
it as a `hierarchy` outline instead.

The `•` bullet nests children under a parent to any depth, with no `LIST` and
no parentheses. When the drafting needs an irregular sequence — an inserted
"2A", a restart — three more names from the library pin or reset a marker
without disturbing its neighbours. Each takes the place of an `item`:
`labeled "2b" "Late payment"` slots a pinned marker in and lets the next
sibling keep the number it had; `numbered "2b" "Late payment"` pins it and
bumps the next sibling on; `restartAt 7 "Recital seven"` resumes the counting
from 7. See
[Optimising Natural-Language Generation](../natural-language-functions/optimising-natural-language-generation.md#literal-recitals--carrying-prose-that-isnt-computed)
for the contrast with `@nlg`, which renders prose _from_ logic; recitals are
prose that simply _is_.

### 3. Handle "And/Or" Carefully

Legal "or" is usually inclusive — any one or more of the listed things, not
exactly one of them:

```l4
-- "A, B, or C" usually means "A OR B OR C"
condition1 OR condition2 OR condition3
```

### 4. Watch for Implicit Negation

"not a public house or hotel" can be read two ways, and only one of them is
what the drafter meant:

```l4
-- Almost certainly intended: NOT (public house OR hotel)
NOT (`is public house` OR `is hotel`)

-- Almost certainly not: (NOT public house) OR (NOT hotel)
```

The second reading is satisfied by a public house, because a public house is
not a hotel. If in doubt, write the case out and ask whether the answer is the
one the drafter would recognise.

### 5. Test Edge Cases

- All conditions true
- All conditions false
- Each exemption on its own
- Each disqualifying factor on its own

### 6. One Section, One Subject

A section `GIVEN` works because a section is usually about one thing — one
person, one issuer, one application. If you find yourself declaring facts about
two unrelated subjects under one heading, that is a sign the encoding wants two
sections, the way the statute has two.

---

## What You Learned

- How to read a provision for its logical shape before writing any L4
- How a rule is a question with blanks, and how `GIVEN` names the blanks — the
  rule's inputs
- The difference between a fact the document settles (`MEANS`) and a fact it
  leaves open (`GIVEN`)
- How to declare a section's shared facts once, as a section `GIVEN` under the
  heading, indented past the `§`
- Why the column matters, and what the error looks like when it is wrong
- How `@desc` turns a name into the question a member of the public is shown
- How to encode AND/OR conditions
- What a rule says when it is asked before its blanks are filled, and why that
  is an answer rather than a failure
- How to carry inert recital and preamble text as a `hierarchy` outline
- How to break a rule into named sub-rules, and group them under `§§`
  sub-headings, without changing the questions asked
- How to supply a case from outside the file: a `cases.json` file of cases and
  `l4 batch` at a command prompt
- How to migrate an existing `ASSUME`

---

## Next Steps

- [The section `GIVEN`](../../reference/syntax/section-given.md) - Full rules for
  facts declared once for a whole section
- [Common Patterns](../../reference/patterns/common-patterns.md) - More L4 patterns
- [Foundation Course Module 1](../../courses/foundation/module-1-first-rule.md) - Deep dive on legal rules
- [Encoding with a large language model](../llm-integration/llm-getting-started.md) -
  Using a large language model (**"LLM"**) to help with encoding
