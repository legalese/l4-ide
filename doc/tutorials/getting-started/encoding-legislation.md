# Encode legislation

Turn a legal provision into L4 that mirrors the text, test it, declare its facts once, run it on a file of cases, and use an AI assistant to draft larger pieces.

**Before you start:** [Install L4 and write your first rule](first-l4-file.md) and [Test your rules](testing-your-rules.md).

**Complete examples:** [encoding-legislation-example.l4](encoding-legislation-example.l4) for Steps 1 to 4, and [encoding-legislation-section-given-example.l4](encoding-legislation-section-given-example.l4) for Steps 5 and 6.

---

## The provision

We will encode this section of an imaginary Alcohol Act:

> **Section 3.** A person must not sell alcohol if:
> (a) the person is a body corporate;
> (b) the person engages in business for profit;
> (c) the person is not a public house or hotel; and
> (d) any of the following applies:
> (i) the person has an unspent conviction for fraud;
> (ii) the person has an unspent conviction for providing misleading information; or
> (iii) the person has an alcohol banning order.

---

## Step 1: Analyse the structure

Before writing code, find:

1. **The outcome**: "must not sell alcohol".
2. **The conditions**: (a), (b), (c) and (d), which must all hold.
3. **The alternatives**: (d)(i), (d)(ii) and (d)(iii), of which any one is enough.

The logical shape is:

```
(a) AND (b) AND (c) AND ((d)(i) OR (d)(ii) OR (d)(iii))
```

---

## Step 2: Write the rule

Each fact the section depends on becomes an input, named in the words of the statute. Each condition becomes one line, with a comment pointing to its paragraph:

```l4
§ `Imaginary Alcohol Act 2024, section 3`

GIVEN `the person is a body corporate`                                            IS A BOOLEAN
      `the person engages in business for profit`                                 IS A BOOLEAN
      `the person is a public house`                                              IS A BOOLEAN
      `the person is a hotel`                                                     IS A BOOLEAN
      `the person has an unspent conviction for fraud`                            IS A BOOLEAN
      `the person has an unspent conviction for providing misleading information` IS A BOOLEAN
      `the person has an alcohol banning order`                                   IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `the person must not sell alcohol` IF
        `the person is a body corporate`                                              -- (a)
    AND `the person engages in business for profit`                                   -- (b)
    AND NOT (`the person is a public house` OR `the person is a hotel`)               -- (c)
    AND (    `the person has an unspent conviction for fraud`                         -- (d)(i)
         OR  `the person has an unspent conviction for providing misleading information` -- (d)(ii)
         OR  `the person has an alcohol banning order`)                               -- (d)(iii)
```

| Legal text                                  | L4                                                                  |
| ------------------------------------------- | ------------------------------------------------------------------- |
| "the person is a body corporate"            | `` `the person is a body corporate` ``                              |
| "the person is not a public house or hotel" | ``NOT (`the person is a public house` OR `the person is a hotel`)`` |
| "any of the following applies"              | `( ... OR ... OR ... )`                                             |

The facts are `GIVEN` inputs, so a caller, a test or a deployed API supplies them. When several rules read the same facts, declare them once for the whole section instead: see [Step 5](#step-5-declare-the-facts-once-for-a-section).

---

## Step 3: Test it

Add tests that state the expected outcome. A rule can be called with its inputs named, ``rule WITH `input` IS value``, one input per line, which keeps long test cases readable:

```l4
-- A corporate pub is exempt under (c), even with a fraud conviction.
#ASSERT NOT `the person must not sell alcohol` WITH
    `the person is a body corporate`                                            IS TRUE
    `the person engages in business for profit`                                 IS TRUE
    `the person is a public house`                                              IS TRUE
    `the person is a hotel`                                                     IS FALSE
    `the person has an unspent conviction for fraud`                            IS TRUE
    `the person has an unspent conviction for providing misleading information` IS FALSE
    `the person has an alcohol banning order`                                   IS FALSE

-- A company with a banning order is prohibited.
#ASSERT `the person must not sell alcohol` WITH
    `the person is a body corporate`                                            IS TRUE
    `the person engages in business for profit`                                 IS TRUE
    `the person is a public house`                                              IS FALSE
    `the person is a hotel`                                                     IS FALSE
    `the person has an unspent conviction for fraud`                            IS FALSE
    `the person has an unspent conviction for providing misleading information` IS FALSE
    `the person has an alcohol banning order`                                   IS TRUE
```

`l4 run` prints `assertion satisfied` for each. Use `#ASSERT` (or `#EVAL` and compare the result yourself), not `#CHECK`: `#CHECK` only type-checks and never evaluates the rule.

Cover at least:

- each exemption on its own;
- each disqualifying factor on its own;
- the case where nothing in (d) applies;
- a person outside the section altogether, for example not a body corporate.

---

## Step 4: Name the parts

For longer provisions, give each part of the test a name. `WHERE` defines the parts after the rule, so the main condition reads like a summary of the section:

```l4
GIVEN `the person is a body corporate`                                            IS A BOOLEAN
      `the person engages in business for profit`                                 IS A BOOLEAN
      `the person is a public house`                                              IS A BOOLEAN
      `the person is a hotel`                                                     IS A BOOLEAN
      `the person has an unspent conviction for fraud`                            IS A BOOLEAN
      `the person has an unspent conviction for providing misleading information` IS A BOOLEAN
      `the person has an alcohol banning order`                                   IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `the person must not sell alcohol` IF
        `is a commercial enterprise`          -- (a) and (b)
    AND NOT `is an exempt establishment`      -- (c)
    AND `has a disqualifying factor`          -- (d)
    WHERE
        `is a commercial enterprise` MEANS
                `the person is a body corporate`
            AND `the person engages in business for profit`

        `is an exempt establishment` MEANS
                `the person is a public house`
            OR  `the person is a hotel`

        `has a disqualifying factor` MEANS
                `the person has an unspent conviction for fraud`
            OR  `the person has an unspent conviction for providing misleading information`
            OR  `the person has an alcohol banning order`
```

The inputs and the tests stay the same, so the tests from Step 3 confirm that the refactored rule still means the same thing.

---

## Step 5: Declare the facts once for a section

Step 4 split the rule into parts, and every part reads the same seven facts. Written as a `GIVEN` on each rule, those seven names would be repeated again and again, and a mistyped name in one copy is a different fact: L4 treats `the person is a hotel` and `the person is an hotel` as two facts, and a form built from the file asks about both.

Legal drafters already have a device for this. "In this Part, 'the issuer' means …" declares a name once, at the top of a stretch of provisions, and every provision below is entitled to use it. A **"section `GIVEN`"** is that sentence, made machine-readable: one `GIVEN`, written under the section heading and indented past the `§`, naming a fact that every rule in that section may read. The `GIVEN` you have used so far, written immediately above one rule, is a **"rule `GIVEN`"**: it lists that rule's own inputs, and no other rule can read them.

Section 3 as a section `GIVEN`, with the seven facts named once:

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

A name can carry one more thing: `@desc`, a plain-words note shown beside the blank when a member of the public fills it in.

```l4
    GIVEN `the person is a body corporate` IS A BOOLEAN @desc Is the person a body corporate?
```

The rules and the form both use the name; the `@desc` is its help text. The companion file for this step, [encoding-legislation-section-given-example.l4](encoding-legislation-section-given-example.l4), carries a `@desc` on all seven names.

`GIVEN` names a fact the document leaves open, to be supplied one case at a time. It is the opposite of `MEANS`, which fixes a fact once and for all. A statutory definition ("'body corporate' means a company registered under Part 2") is a `MEANS`, because it says the same thing in every case. "The person" is a `GIVEN`, because it is a different person every time the section is applied.

Rules beneath the heading declare no inputs of their own, since there is no rule `GIVEN` above them: they read the seven names from the heading. That makes it cheap to say each idea once and give it a name:

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

Splitting the rule up costs nothing in the questions anybody is asked. Each sub-rule reads the section's seven names directly, and the main rule still asks for the same seven facts, because L4 follows the chain of rules all the way down to work out what to ask for.

The companion file keeps both encodings side by side: the single rule that tracks the clauses of s.3, `the person must not sell alcohol`, and the version assembled from sub-rules, `the person must not sell alcohol (tidied)`. It ends with five `#CHECK` lines, which report what kind of thing each rule answers with, rather than working any of them out. `#CHECK` needs no facts supplied, so it runs whether or not anybody has filled the blanks in.

### Sub-headings inside a section

Once a section holds several rules, it helps to group them. `§§`, two section marks instead of one, starts a subsection _inside_ the section above it, the way s.3(1) and s.3(2) sit inside s.3. A `§§` does not start a fresh section, so rules under it still read the section `GIVEN` declared at the top: the seven names reach every rule beneath the `§` heading, including the ones tucked under `§§` sub-headings. The companion file groups its rules under three sub-headings: Main rule, Sub-rules and Checks.

### The column rule

The indentation is not decoration. **A `GIVEN` belongs to the section when its keyword starts to the right of the heading's `§`.** A `GIVEN` at column 1 means what it has always meant: it is the rule `GIVEN` of the one declaration immediately below it.

```l4
-- ✅ Right: a section GIVEN, for the whole of section 3
§ `Imaginary Alcohol Act - Section 3`
    GIVEN `the person is a body corporate` IS A BOOLEAN

-- ❌ Wrong: a rule GIVEN, for the next rule only
§ `Imaginary Alcohol Act - Section 3`

GIVEN `the person is a body corporate` IS A BOOLEAN
```

Get it wrong and the first rule below quietly takes the names as its own. The rules that then go wrong are the later ones using them, one message each:

```
I could not find a definition for the identifier

  `the person is a body corporate`

which I have inferred to be of type:
...
```

An **"identifier"** is L4's word for a name, and the "type" it goes on to mention is the kind of thing that name holds. So the message says: _this name is used here, and I cannot see anywhere it was declared._ If you meet that error, or `unexpected §` at a `§§` below the names, check the column before you check anything else.

### Asking before the blanks are filled

Ask a rule for an answer with none of the seven facts supplied and it tells you so, naming every fact it is waiting for:

```
I could not continue evaluating, because I needed to know the values of
  `the person is a body corporate`
  `the person engages in business for profit`
  `the person is a public house`
  `the person is a hotel`
  `the person has an unspent conviction for fraud`
  `the person has an unspent conviction for providing misleading information`
  `the person has an alcohol banning order`
but they are assumed terms.
```

An **"assumed term"** is a name the file assumes someone will supply for the case in hand, and never settles for itself, which is exactly what a `GIVEN` is, whether you wrote it under the heading or above one rule. So the message reads: _I could not finish, because nobody has told me any of these seven facts about this person._ That is not a bug and it is not a failure of the rule. It is the rule telling you which blanks are still empty. Fill some of them and ask again: it names the ones still missing, and once the facts you have given settle the answer, it answers. Tell it only that the person is not a body corporate, and the answer is `FALSE` whatever the other six are, because limb (a) already fails.

### Migrating an existing `ASSUME`

Older L4 wrote these facts as `ASSUME`s at the left margin. Files you have already written go on working exactly as before: L4 still accepts them, still checks them, and still publishes their rules as services. But for a fact the rules of a section share, the section `GIVEN` is now the form to reach for. To migrate `ASSUME x IS A T`, move the line under the heading of the section whose rules read it, indent it past the `§`, and write `GIVEN x IS A T`. The two behave identically: both name a fact nobody has supplied yet, and both are asked for in the same way when someone supplies a case. See [ASSUME](../../reference/types/ASSUME.md).

### Two sections, the same name

Two sections may declare the same name for different things, exactly as statutes do ("for the purposes of sections 1 and 2, 'proceeds' means …; for the purposes of section 3, 'proceeds' means …"). Each section's rules read their own. A rule placed where it can see two same-named section `GIVEN`s at once is an error, and the message names both sections so you can see which two you have collided. See [the section `GIVEN`](../../reference/syntax/section-given.md) for the full rules.

---

## Step 6: Run it on a file of cases

The seven names are not only documentation. They are the list of questions the tools ask. Whoever does the asking (a member of the public filling in a web form, another program, or you at a command prompt) is the rule's **"caller"**, and the seven names are exactly what the caller has to hand in.

Mark the rule `@export`. An **"annotation"** is a line beginning with `@` that tells the tools something about the rule underneath it, without changing what that rule decides; `@export` says _this is a rule outsiders may ask_. Writing it does not by itself put your rule anywhere: it tells the tools which rules to offer when the file is served. Once it is there, every fact the rule reads becomes a fact the caller has to supply, including facts the rule reaches indirectly, through the rules it relies on.

```l4
@export Decide whether a person is prohibited from selling alcohol under s.3
DECIDE `the person must not sell alcohol`
IF  ...
```

Now write your scenarios out as a file of cases. The format is JavaScript Object Notation (**"JSON"**), the plain-text format these tools read and write: square brackets hold the list of cases, and each case is one set of curly braces pairing each of the seven names with `true` or `false`. Save the block below as `cases.json`, in the same folder as the companion file:

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

Then, at a command prompt in that folder, type:

```bash
l4 batch encoding-legislation-section-given-example.l4 --inputs cases.json
```

`batch` is the `l4` command for running one `@export`ed rule over a whole file of cases, and `--inputs` says which file the cases are in. If you have never used a command prompt, [Using the l4 CLI](l4-cli.md) installs the tool and walks through it one command at a time.

You get one line of output for each case in the file. It repeats the case it was given, under `input`, and gives the answer it worked out, under `output`. `diagnostics` lists any complaints L4 has about the file, `status` says whether the run got through, and `trace` is always empty here: `l4 batch` does not carry the reasoning. `presumed` would list any fact the answer took a default for because the case left it out; these rules have no defaults, so it is empty. The seven facts echoed back are elided here as `{…}` to keep the line readable:

```
{"diagnostics":[],"input":{…},"output":[{"result":false,"trace":null}],"presumed":[],"status":"success"}
```

`"result":false`: this is a corporate pub, which is exempt under (c), so it is not prohibited. `"diagnostics":[]` is an empty list, so L4 found nothing to complain about in the file.

The same list of seven drives every other way of asking the rule, and this is where declaring it once pays for itself twice over. Generate a guided web interview from the file and it asks exactly seven yes-or-no questions, one per name, worded from the name itself, with the `@desc` you wrote as the help text under the question:

```yaml
id: q_the_person_engages_in_business_for_profit
question: |
  the person engages in business for profit
fields:
  - "the person engages in business for profit": the_person_engages_in_business_for_profit
    datatype: yesnoradio
    help: "Does the person engage in business for profit?"
```

Publish the rule as a service and the request it accepts requires exactly those same seven fields. One list, written once, in one place, and every way of asking the rule reads it.

---

## Carry inert text: recitals, preambles, purpose clauses

Not every part of a legal document is a rule. Recitals, preambles, _whereas_ clauses, purpose statements, statements of principle (the throat-clearing at the start of a chapter) gate no decision and work nothing out. But an _isomorphic_ encoding (one that mirrors the source, so a lawyer can check it line by line) still has to carry them, verbatim and correctly numbered.

Reach for the `hierarchy` library. A **"library"** is a file of ready-made names somebody else has written, which your file may borrow instead of writing them again; `IMPORT hierarchy` at the top of your file borrows this one, and every name in it (`item`, `render outline` and the rest) is then usable below. See [IMPORT](../../reference/libraries/README.md#import) for the details of borrowing.

What `hierarchy` gives you is the outline: a tree of **text** (`item "…"`), written as a bullet list and rendered with automatic numbering. Each item is text and nothing more (it is never worked out, only carried), so it may say anything at all, including wording that would never be valid L4 logic:

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

Three things in that block are new. `recital scheme` is a list of _numbering styles_, one for each level of the outline: `UpperAlpha` (A, B, C), then `Decimal` (1, 2, 3), then `LowerRoman` (i, ii, iii). Those three, along with `LowerAlpha`, `UpperRoman` and `Bulleted`, are the six styles the library offers; they are written as bare words with no backticks because each is a single word. And `render outline` is a rule from the library that is given two things, first the scheme and then the outline, and gives back the numbered text. Naming two things in a row after a rule's name, as `` `render outline` `recital scheme` `recitals` `` does, is how a rule with two inputs is asked in L4.

The heading is carried verbatim; the rest is numbered by depth. You pick the _style_ per level and the renderer gives back one line of text per item, printed as a single `LIST` and laid out here one to a row:

```
RECITALS
A      the Company is engaged in the business of software development;
B      the Consultant has expertise in legal engineering; and
C      the parties wish to record the terms of their engagement, namely
C.1    the scope of services;
C.2    the fees payable; and
C.3    the term and termination.
```

**The rule of thumb.** Ask of each passage: _does it gate any decision, or work out any value?_ If it does neither, it is inert. Do not force it into a `DECIDE` or a `GIVEN`, because there is nothing to decide and no fact to supply, and do not drop it either, because you would lose fidelity to the source. Capture it as a `hierarchy` outline instead.

The `•` bullet nests children under a parent to any depth, with no `LIST` and no parentheses. When the drafting needs an irregular sequence (an inserted "2A", a restart), three more names from the library pin or reset a marker without disturbing its neighbours. Each takes the place of an `item`: `labeled "2b" "Late payment"` slots a pinned marker in and lets the next sibling keep the number it had; `numbered "2b" "Late payment"` pins it and bumps the next sibling on; `restartAt 7 "Recital seven"` resumes the counting from 7. See [Optimising Natural-Language Generation](../natural-language-functions/optimising-natural-language-generation.md#literal-recitals--carrying-prose-that-isnt-computed) for the contrast with `@nlg`, which renders prose _from_ logic; recitals are prose that simply _is_.

---

## Tips

**Keep the statute's words.** `` `the person is a body corporate` `` lets a lawyer check the rule against the text; `isCompany` does not.

**Read "or" carefully.** In legislation, "A, B or C" usually means any one or more of them: `A OR B OR C`.

**Watch negations.** "Not a public house or hotel" normally means neither: `NOT (pub OR hotel)`. The other reading, `NOT pub OR NOT hotel`, is true for almost everyone and is rarely intended. When the text is ambiguous, write down which reading you chose, in a comment or a test.

**Keep the source next to the code.** The complete example puts the text of section 3 in a `{- ... -}` comment above the rule and marks each condition with its paragraph number.

**One section, one subject.** A section `GIVEN` works because a section is usually about one thing: one person, one issuer, one application. If you find yourself declaring facts about two unrelated subjects under one heading, that is a sign the encoding wants two sections, the way the statute has two.

---

## Drafting with an AI assistant

An AI assistant can draft L4 from legislation quickly, but it can also misread the law. Use it for the first draft, and let the type checker and a human reviewer decide whether the draft is right. In VS Code, Legalese AI already knows L4 syntax and sees the type checker's errors after every edit; see [Draft rules with Legalese AI](../llm-integration/composing-l4-with-ai.md). The prompts below work with any assistant.

### The workflow

1. **Segment.** Split the legislation into self-contained pieces: one article or section each, with its number, and with the definitions it uses. Segment inert passages (recitals, preambles, purpose clauses) separately from operative rules and flag them as such: they gate no decision and compute nothing, so they are carried as an outline, not encoded as a `DECIDE` or a `GIVEN`. See [Carry inert text](#carry-inert-text-recitals-preambles-purpose-clauses).
2. **Extract.** Ask the assistant for the types and inputs the piece needs.
3. **Draft.** Ask for the L4 rule.
4. **Check.** Run `l4 check`, then the tests, then review the draft against the text.
5. **Iterate.** Give the errors and your review notes back to the assistant.

### Prompt: extract types

```
You are analysing legislation to encode it in L4, a programming language
for law.

Legislation:
"""
Article 2 - Interpretation
In this Law -
"charitable purpose" means any of the purposes specified in Schedule 1;
"charity" means an entity that is established for charitable purposes only;
"governor" means any person who is responsible for the control and
management of the administration of a registered charity;
"""

List every defined term that should become a type. For each, say:
1. its name;
2. whether it is a fixed list of choices or a record with fields;
3. its choices or fields, with their types;
4. which other types or provisions it refers to.
```

### Prompt: draft the rule

```
Write L4 for the provision below.

L4 basics:
- Records: DECLARE Charity HAS `purposes` IS A LIST OF Purpose
- Choices: DECLARE Purpose IS ONE OF `relief of poverty`, `advancement of education`
- Rules: GIVEN `the entity` IS A Charity
         GIVETH A BOOLEAN
         DECIDE `meets the charity test` IF ... AND ...
- Names with spaces go in backticks; fields are read with 's.
- List functions such as all, any, map and filter need IMPORT prelude.
- Facts every rule in an article needs: a GIVEN on the line after the
  § heading, indented past the §.

Provision:
"""
Article 5 - Charity test
An entity meets the charity test if -
(a) all of its purposes are charitable purposes; and
(b) it satisfies the public benefit requirement.
"""

Types already defined:
- Charity, with `purposes` (a LIST OF Purpose)
- Purpose, a list of the charitable purposes

Use the words of the provision as names. Mark each condition with a
comment giving its paragraph, and add #ASSERT tests for each paragraph.
```

### Prompt: fix an error

Paste the checker's message exactly as `l4 check` printed it:

```
l4 check reported this error:

    I could not find a definition for the identifier

      Purpose

The types defined in the file are CharitablePurpose and Charity.
Fix the draft and explain the change.
```

### Problems to look for

| In the draft                                 | Problem                   | Fix                                  |
| -------------------------------------------- | ------------------------- | ------------------------------------ |
| `purposes IS A Purpose`                      | Should be a list          | `purposes IS A LIST OF Purpose`      |
| `entity purposes`                            | Field access without `'s` | `entity's purposes`                  |
| `IF x = TRUE`                                | Redundant comparison      | `IF x`                               |
| `x == 5`                                     | Not L4                    | `x = 5` or `x EQUALS 5`              |
| `any`, `all`, `map` without `IMPORT prelude` | Unknown name              | Add `IMPORT prelude` at the top      |
| `#CHECK rule WITH ...` used as a test        | `#CHECK` only type-checks | `#ASSERT rule WITH ...`              |
| An exception the text does not contain       | Invented law              | Remove it, or record why it is there |

### When the draft depends on something not yet encoded

Sometimes a provision rests on another one you have not encoded yet. Suppose Article 5(b) above refers to a public benefit requirement set out in Article 7, which nobody has encoded. Leave that dependency as an unfilled blank on purpose, as a section `GIVEN` under the article's heading, rather than letting the assistant invent a definition:

```l4
-- Art 5(b) is not encoded yet. Until Article 7 is written, the public
-- benefit requirement is a fact the caller supplies for each case.
§ `Article 5 - Charity test`
    GIVEN entity IS A Charity
          `satisfies public benefit` IS A BOOLEAN
```

L4 accepts the file as it stands, and a rule marked `@export` asks the caller for that fact alongside the entity. The blank is honest: it says the public benefit requirement has not been encoded yet, rather than pretending an answer. See [the section `GIVEN`](../../reference/syntax/section-given.md).

### Review checklist

- Types and names match the definitions in the legislation.
- Every condition in the text appears in the rule, and nothing else does.
- Cross-references point to the right provisions.
- There are tests for each paragraph and for the edges (thresholds, empty lists, exemptions).
- Inert text (recitals, preambles) is carried as an outline, not dropped.
- `l4 check` passes and every `#ASSERT` is satisfied.

**Example:** a reviewed draft of a governor-disqualification article, with its tests: [governor-disqualification-example.l4](governor-disqualification-example.l4)

### Keep a record

Commit the source text, the prompts and the L4 together, and note which assistant produced the draft. [Manage rules in git and CI](version-control-for-rules.md) shows how.

An assistant can misread a legal structure, miss a cross-reference, or invent an interpretation. A draft that type-checks can still be wrong: only the tests and the review show whether it says what the law says.

---

## Next steps

- [The section `GIVEN`](../../reference/syntax/section-given.md): the full rules for facts declared once for a whole section.
- [Common patterns](common-patterns.md): more ways to structure rules.
- [Make rules read like law](../natural-language-functions/optimising-natural-language-generation.md): names and shapes that render as readable prose.
- [Real regulatory schemes](../../courses/advanced/module-a1-regulatory.md): a longer encoding exercise in the Advanced course.
