# Sections

`§`, `§§` and `§§§` divide a file into named, nested sections the way Parts and Divisions divide a statute — and those divisions decide which rules can use which names.

**Example file:** [sections-example.l4](sections-example.l4). It holds every example on this page that L4 accepts today, in the order the page presents them, apart from a few that the page marks as not being in it where they appear. Examples that produce an error are shown here in a fenced block only, with the message L4 gives; a file under `doc/` has to run cleanly, so they are not in the companion.

---

## 1. Headings and nesting: `§`, `§§`, `§§§`

A heading is a line that starts with one or more `§` marks and carries a name. The name may be an ordinary word or a backticked phrase, and a backticked phrase is the usual choice because statute headings have spaces and numerals in them.

```l4
§ `Part 1`
`short title` MEANS "the Licensing Act"

§§ `Division 1`
`applies to individuals` MEANS TRUE

§§§ `Subdivision A`
`exempt while under age` MEANS TRUE

§§ `Division 2`
`base fee` MEANS 300

§ `Part 2`
`licence term in years` MEANS 3

§§§§ `Rule 12`
`renewal window in days` MEANS 60
```

That file has this shape:

```
(the root — everything before the first heading)
§ Part 1
    §§ Division 1
        §§§ Subdivision A
    §§ Division 2
§ Part 2
    §§§§ Rule 12
```

### The words this page uses for the shape

- **The "root"** is everything written before the first heading. It belongs to no section. A file may have no headings at all, in which case all of it is the root.
- A section's **"parent"** is the section it sits inside; the sections inside it are its **"children"**. In the file above, `Division 1` and `Division 2` are children of `Part 1`, and `Part 1` is their parent.
- Two sections with the same parent are **"siblings"**: `Division 1` and `Division 2`.
- **"Ancestors"** are a section's parent, its parent's parent, and so on up to the root; **"descendants"** are its children, their children, and so on down. `Part 1` is an ancestor of `Subdivision A`; `Subdivision A` is a descendant of `Part 1`.
- Two sections that are neither ancestors nor descendants of one another and are not siblings are **"cousins"**: `Subdivision A` and `Rule 12`.
- A rule's **"ancestry"** is the chain running from the rule's own section, up through each enclosing section, to the root. `Subdivision A`'s ancestry is `Subdivision A`, then `Division 1`, then `Part 1`, then the root. This chain is the one idea section 2 turns on.

### Where a section ends

There is no closing mark. A section ends when the next heading tells it to, or at the end of the file.

| what comes next                       | what happens                                                              |
| ------------------------------------- | ------------------------------------------------------------------------- |
| a heading with the same number of `§` | the section ends; the new one is its sibling                              |
| a heading with fewer `§`              | the section ends, and so does every section enclosing it up to that level |
| a heading with more `§`               | the section does not end; the new one is its child                        |
| the end of the file                   | the section ends, and so does every section enclosing it                  |

**A deeper heading always nests exactly one level, whatever the difference in `§` count.** `§§§§ Rule 12` written under `§ Part 2` is a child of `Part 2`, not a great-grandchild of it; no invisible sections are created in between. A skipped level makes the next heading of that count a child, not a sibling.

**Repeating a heading name re-opens the same section.** A second `§ Part 1` further down the file adds to `Part 1` rather than starting a second, separate `Part 1`. Definitions written under either spelling live at the same place, and two definitions of one name across the two spellings collide exactly as two written side by side would.

---

## 2. What a rule can see

### Three words this page needs first

Four different lines can give a name a meaning, and the rest of this page needs one word that covers all four. Any line that gives a name a meaning is a **"declaration"** of that name:

- an ordinary definition — `` `base fee` MEANS 300 ``;
- a rule that lists its own inputs — `GIVEN … GIVETH … DECIDE …`;
- a kind of thing made with `DECLARE` — `DECLARE Person HAS …`;
- a name listed after a `GIVEN` written under a heading.

Note that `DECLARE` is only one of the four. Wherever this page says "declared" or "a declaration", it means any of them, not the `DECLARE` keyword in particular.

Two more words, used the same way throughout:

- A **"candidate"** is a declaration L4 is weighing up as it works out which declaration a name means.
- A name **"resolves"** when one candidate is left standing and L4 can say which declaration the name means. When more than one is left and nothing separates them, L4 stops and says so.

### The rule in two steps

When a rule uses a name, L4 works out which declaration is meant in two steps, in this order.

1. **Look up the chain.** Start at the rule's own section, then the section enclosing that, and so on out to the root. Take the first declaration of the name found on that chain, and stop looking. A nearer declaration takes precedence over a farther one.
2. **Only if the chain has none, look at the whole file.** Every declaration of that name anywhere in the file is a candidate. One candidate resolves. Two are an error, and L4 prints both.

There is a wrinkle in step 1 when the two declarations are **different kinds of thing** — one a number and one a piece of text, say. Nearness does not always settle that case, and the file's own running order can. It is set out in [Limits](#6-limits), and flagged again under the table below.

Two consequences of the two steps are worth stating separately, because they are the two halves readers most often guess wrongly:

1. **A section never hides a name from anywhere else in the file.** A rule can use a name declared in a sibling section, a cousin section, a section further down the file, or a section it encloses — provided that name is declared only once. Sections are not walls.
2. **A nearer declaration does take precedence over a farther one on the same ancestry.** A `Part` and a `Division` inside it may each declare `prescribed rate`; rules in the `Division` get the `Division`'s, rules elsewhere in the `Part` get the `Part`'s.

### The full table

Rows are the relationship between where a name is declared and where it is used. Columns are what kind of thing was declared. Every cell was measured on the version of L4 this page documents.

What the cell values mean:

| cell                 | what it says                                                                           |
| -------------------- | -------------------------------------------------------------------------------------- |
| `its own`            | the declaration in that very section is the one the rule reads                         |
| `resolves`           | the bare name works, and names the one declaration there is                            |
| `resolves if unique` | the bare name works provided the whole file declares that name exactly once            |
| `nearest wins`       | both declarations exist; the one nearer on the chain is the one read                   |
| `the ancestor's`     | the enclosing section's declaration is the one read                                    |
| **error**            | L4 stops and prints both candidates; qualify the use (section 3) or change one of them |
| `not possible`       | the arrangement cannot be written at all                                               |

| where the name is declared    | where it is used                 | `MEANS` / `DECIDE` | a rule with its own `GIVEN` | `DECLARE`          | section `GIVEN`    |
| ----------------------------- | -------------------------------- | ------------------ | --------------------------- | ------------------ | ------------------ |
| the same section              | there                            | its own            | its own                     | its own            | its own            |
| the root                      | inside a section                 | resolves           | resolves                    | resolves           | not possible       |
| inside a section              | at the root                      | resolves if unique | resolves if unique          | resolves if unique | resolves if unique |
| a parent section              | a child                          | nearest wins       | nearest wins                | nearest wins       | nearest wins       |
| a child section               | its parent                       | resolves if unique | resolves if unique          | resolves if unique | resolves if unique |
| a grandparent section         | a grandchild                     | nearest wins       | nearest wins                | nearest wins       | nearest wins       |
| a grandchild section          | its grandparent                  | resolves if unique | resolves if unique          | resolves if unique | resolves if unique |
| an earlier sibling            | a later sibling                  | resolves if unique | resolves if unique          | resolves if unique | resolves if unique |
| a later sibling               | an earlier sibling               | resolves if unique | resolves if unique          | resolves if unique | resolves if unique |
| a cousin                      | a cousin                         | resolves if unique | resolves if unique          | resolves if unique | resolves if unique |
| two sections, the same name   | in one of those two              | its own            | its own                     | its own            | its own            |
| two child sections, same name | in their shared parent           | **error**          | **error**                   | **error**          | **error**          |
| two sections, the same name   | in a third section under neither | **error**          | **error**                   | **error**          | **error**          |
| two sections, the same name   | in a child of one of them        | the ancestor's     | the ancestor's              | the ancestor's     | the ancestor's     |

Reading the table: **all four columns behave alike.** Ordinary definitions, rules that carry their own `GIVEN`, kinds of thing declared with `DECLARE`, and the names declared by a section `GIVEN` all follow one rule, so there is nothing extra to learn per column. The one place "not possible" appears is the root, which has no heading for a section `GIVEN` to be indented under.

**The one place the table is not the whole story is when the two declarations are different kinds of thing** — one a number and one a piece of text, for instance. L4 does not rank two declarations of different kinds against each other by nearness at all, so "nearest wins" can fail to apply, **and the answer can then be wrong with no error on screen**: which declaration a rule reads may be settled by which of the two is written first in the file. The advice is short — do not give one name to two different kinds of thing in one file — and the measurement behind it is in [Limits](#6-limits).

One note on wording before reading any L4 message. Where this page says "kind of thing", a message says "type": `of type NUMBER` beside a candidate is the message's way of saying that declaration is a number. The two phrases are the same idea in two vocabularies, and this page uses the plain one.

### Worked example: a sibling's name, unqualified

`filing deadline in days` is declared once, in `Division 5`. `Division 6` is its sibling and uses it by its bare name. No qualification is needed, because the file has exactly one declaration of it.

```l4
§ `Part 3`
`prescribed rate` MEANS 5

§§ `Division 5`
`late fee` MEANS `prescribed rate` TIMES 10
`filing deadline in days` MEANS 30

§§ `Division 6`
`extended deadline in days` MEANS `filing deadline in days` PLUS 14
```

`extended deadline in days` gives 44. `late fee` gives 50: `Division 5` does not declare `prescribed rate`, so the search walks up its ancestry to `Part 3` and finds it there.

### Worked example: a child re-declaring an ancestor's name

`Subdivision B` declares `prescribed rate` again, for itself.

```l4
§§§ `Subdivision B`
`prescribed rate` MEANS 7
`local charge` MEANS `prescribed rate` TIMES 10
```

`local charge` gives 70, not 50: `Subdivision B`'s own declaration is nearer on its ancestry than `Part 3`'s. Everywhere outside `Subdivision B`, `prescribed rate` is still 5 — `Part 3`'s `prescribed rate` gives 5, and `Division 5`'s `late fee` still gives 50. **A re-declaration reaches only its own section and that section's descendants.**

### Worked example: the same name in two sections

This is the drafting habit "in this Division, `age of majority` means 18" written twice, with different numbers, exactly as a statute writes it. Both Divisions also declare a rule of the same name, and each rule reads its own Division's number. (The companion declares Alex, a person aged 19, before the first heading.)

```l4
§ `Part 4`

§§ `Division 7`
`age of majority` MEANS 18
`alex is of age` MEANS alex's age AT LEAST `age of majority`

§§ `Division 8`
`age of majority` MEANS 21
`alex is of age` MEANS alex's age AT LEAST `age of majority`
```

Alex is 19. `` `Part 4`.`Division 7`.`alex is of age` `` gives `TRUE` and `` `Part 4`.`Division 8`.`alex is of age` `` gives `FALSE`. Neither rule had to say which `age of majority` it meant: each is in a section that declares one.

### Worked example: reading a name the sections below re-declare

Where it breaks down is a rule that is **not** inside either section. Add, anywhere in the file above that is not under `Division 7` or `Division 8` — this one does not check, so it is not in the companion:

```l4
§ `Part 6`
`years to wait` MEANS `age of majority` MINUS 19
```

Nothing on `Part 6`'s ancestry declares `age of majority`, so both Divisions' declarations become candidates, and neither is nearer:

```
There are multiple definitions for the identifier

  `age of majority`

and I do not have sufficient information to make a choice between them.
The options are:

  `Part 4`.`Division 8`.`age of majority` (defined at …) of type NUMBER
  `Part 4`.`Division 7`.`age of majority` (defined at …) of type NUMBER
```

The same message appears when the reading rule sits in the **parent** of two children that both declare the name. The candidates are printed with their section-qualified spellings — which is exactly the spelling that fixes it, and is what section 3 is about.

---

## 3. Saying which one you mean

### A qualified name

A **"qualified name"** names a section, then what is inside it, joined either with a dot or with `'s`. Both spellings mean the same thing and may be mixed in one chain.

```l4
§ `Part 5` AKA `the fees Part`
`prescribed fee` MEANS 250

§§ `Division 9` AKA `the discount Division`
`discount` MEANS 50

§ `Part 6`
`net fee dotted` MEANS
    `Part 5`.`prescribed fee` MINUS `Part 5`.`Division 9`.`discount`

`net fee genitive` MEANS
    `Part 5`'s `prescribed fee` MINUS `Part 5`'s `Division 9`'s `discount`

`net fee via alias` MEANS
    `the fees Part`'s `prescribed fee`
        MINUS `the fees Part`.`the discount Division`.`discount`
```

All three give 200. Chains nest as deeply as the headings do: `` `Part 1`.`Division 1`.`Subdivision A`.`exempt while under age` ``.

### Where a chain starts

**A chain always starts at an outermost heading** — one that is not written inside any other section — and then names every heading from there down to the thing wanted. There is no short form that starts partway down, so naming a sibling on its own does not work, even when the file has only one heading of that name. A rule in `Division 6` that wants `Division 5`'s `the fee` writes `` `Part 3`.`Division 5`.`the fee` ``. The short form `` `Division 5`.`the fee` `` is measured to give this, which reads like a misspelling and is not one:

```
I could not find a definition for the identifier

  `Division 5`.`the fee`

which I have inferred to be of type:

  NUMBER
```

The same holds for a parent naming its own child: `Part 3` writing `` `Division 5`.`the fee` `` gets the same message, and has to write the full chain too. Start the outermost heading at one `§` and keep the counts consecutive: a skipped level makes the next heading of that count a child, not a sibling.

### Aliases

A heading may carry an [`AKA`](../functions/AKA.md) — "also known as" — alias, and the alias works in a qualified name wherever the heading's own name does — at any position in the chain, and on both an outer and an inner heading at once. `` `the fees Part`'s `prescribed fee` `` and `` `Part 5`'s `prescribed fee` `` are the same name. Use it to give a long statutory heading a short working name.

### What qualification can and cannot reach

It can reach:

- anything declared in another section, from any relationship — a sibling, a cousin, an ancestor, a descendant, or from the root;
- a name that a nearer declaration has taken precedence over. Inside a section that re-declares `the rate`, `` `Part 7`.`the rate` `` still names the outer one;
- all four kinds of declaration: ordinary definitions, rules, kinds of thing declared with `DECLARE`, and the names declared by a section `GIVEN`.

It cannot reach:

- one of two declarations of the same name **in the same section**, because both print the same qualified spelling. Nothing distinguishes them; delete or rename one. See [Limits](#6-limits);
- the building of a record under a `DECLARE`'s [`AKA`](../functions/AKA.md) alias. Given `DECLARE Ticket AKA Coupon HAS price IS A NUMBER` in another section, ``GIVETH A `Part 5`.Coupon`` names the kind of thing under either name, but `Coupon WITH price IS 4` reports that it cannot find `Coupon`. Build the record with the `DECLARE`'s primary name, `Ticket`.

### When qualification is required

**Only when the bare name would be an error.** The plain case is the two error rows of the table in section 2, where two declarations of the same kind are equally far from the rule using them. A handful of narrower situations do the same thing — two declarations of different kinds, a name coming in through `IMPORT`, a rule used above where it is written — and each is set out in [Limits](#6-limits). Everywhere else qualification is permitted, not required: a bare name resolves whenever exactly one declaration of it exists in the file, whatever section that is in.

Qualifying anyway is good practice where a reader of the file would otherwise have to hunt: a cross-Part reference reads better as `` `Part 5`'s `prescribed fee` `` than as `prescribed fee`, and it will not silently start meaning something else if a second `prescribed fee` is added later.

---

## 4. The section GIVEN under these rules

A rule is told some facts about the case in front of it (its **"inputs"**, the names listed after `GIVEN`) and works out one answer from them (its **"output"**, named after `GIVETH`). A `GIVEN` written at column 1 lists the inputs of the one declaration below it — a **"rule GIVEN"**. A `GIVEN` indented under a heading declares an input shared by every rule in that section — a **"section GIVEN"**. [The section `GIVEN`](section-given.md) is that feature's own reference page; this section says only how it sits inside the rules above.

**It obeys exactly the table in section 2.** A name declared by a section `GIVEN` is found by the same ancestry-then-whole-file search as an ordinary definition, takes precedence over a farther one the same way, and is reachable by a qualified name the same way. There is no separate rule to learn.

```l4
§ `Part 7`
    GIVEN `the rate` IS A NUMBER

GIVETH A NUMBER
`ordinary charge` MEANS `the rate` TIMES 100

§§ `Division 12`

GIVETH A NUMBER
`sibling charge` MEANS `the rate` TIMES 200

§§ `Division 13`
    GIVEN `the rate` IS A STRING

GIVETH A STRING
`special rate description` MEANS `the rate`

GIVETH A NUMBER
`ordinary charge here` MEANS `Part 7`.`the rate` TIMES 300
```

- `sibling charge` is in `Division 12`, which declares nothing, so it walks up to `Part 7` and gets the number.
- `special rate description` is in `Division 13`, which declares its own, so it gets the text.
- `ordinary charge here` is in `Division 13` too, and reaches past its own declaration by qualifying.
- `ordinary charge` is in `Part 7` itself. `Division 13` is below it, not on its ancestry, so it gets `Part 7`'s number.

One detail of that example is worth naming, because it is the one case the table in section 2 sets aside. `Part 7`'s `the rate` is a number and `Division 13`'s is a piece of text — two **different kinds of thing** — and L4 does not rank two declarations of different kinds against each other by nearness. What settles the choice for `special rate description` is that rule's `GIVETH A STRING`: a rule that gives text can only be reading the text.

Rather than ask you to picture the difference, here is the same example with every `GIVETH` deleted and nothing else changed. This version does not check, so it is not in the companion:

```l4
§ `Part 7`
    GIVEN `the rate` IS A NUMBER

`ordinary charge` MEANS `the rate` TIMES 100

§§ `Division 12`

`sibling charge` MEANS `the rate` TIMES 200

§§ `Division 13`
    GIVEN `the rate` IS A STRING

`special rate description` MEANS `the rate`

`ordinary charge here` MEANS `Part 7`.`the rate` TIMES 300
```

Exactly one of the four rules now fails, `special rate description`, and this is the whole of what L4 says:

```
There are multiple definitions for the identifier

  `the rate`

and I do not have sufficient information to make a choice between them.
The options are:

  `Part 7`.`Division 13`.`the rate` (defined at …) of type STRING
  `Part 7`.`the rate` (defined at …) of type NUMBER
```

The other three rules survive for reasons that have nothing to do with `GIVETH`. `ordinary charge` sits in `Part 7`, and `Division 13`'s declaration is below it, not on its chain, so only one declaration was ever in the running. `sibling charge` sits in `Division 12`, which is likewise not under `Division 13`. `ordinary charge here` says which one it means. Only `special rate description` sits where both declarations are in the running, and its `GIVETH A STRING` was the only thing separating them.

Where the two declarations are the **same** kind of thing, nearness settles it on its own and no `GIVETH` is needed. Two lessons follow: write a `GIVETH` on every rule, and see [Limits](#6-limits) before you give one name to two different kinds of thing.

**Two sections declaring the same name declare two different things**, exactly as two Divisions each saying "in this Division, 'the applicant' means …" declare two different things:

```l4
§ `Part 8`

§§ `Division 14`
    GIVEN `the applicant` IS A Person

GIVETH A STRING
`name for Division 14` MEANS `the applicant`'s `full name`

§§ `Division 15`
    GIVEN `the applicant` IS A Person

GIVETH A STRING
`name for Division 15` MEANS `the applicant`'s `full name`
```

Each rule reads its own Division's `the applicant`: inside the file they are two separate names, and a change to one leaves the other alone. Filling them in for a real case is a different matter, and today it does not work. A fact reaches a rule from outside the file — entered on a web form, or written in a file and handed to `l4 batch`, the command that runs a published rule over cases someone else provides — and it arrives under the name as that name is written. Both are written `the applicant`, so nothing in what arrives says which of the two a value is for, and L4 reports the ambiguity rather than answering. That is one more reason to prefer the rename below whenever both names really have to be filled in for a case. Section 6 shows what filling a fact in looks like when the two names are distinct.

A rule that can see both at once is the error row of the table. Adding a rule directly under `§ Part 8`, outside both Divisions — this one does not check either, so it is not in the companion:

```l4
GIVETH A STRING
`name for the Part` MEANS `the applicant`'s `full name`
```

```
There are multiple definitions for the identifier

  `the applicant`

and I do not have sufficient information to make a choice between them.
The options are:

  `Part 8`.`Division 15`.`the applicant` (defined at …) of type Person
  `Part 8`.`Division 14`.`the applicant` (defined at …) of type Person
```

Two ways out today, and choosing between them is a drafting decision, not a technical one:

- **Hoist.** If the two Divisions were always talking about one applicant, delete both declarations and put one `GIVEN` under `§ Part 8`. Every rule beneath it then reads that one.
- **Rename.** If they are two different applicants, say so: `the individual applicant` and `the corporate applicant`. The error was the file telling you that one word is doing two jobs.

_**A third way out is not available today.** It is planned: saying at the point of use which section's `the applicant` is meant, written `` `name for the Part` WITH `the applicant` IS `the applicant` ``. Writing that now does not work. After a bare name, as here, L4 reads `WITH` as an attempt to build a record and answers `You are trying to apply … (which is not a function)`; after a rule that has already been given its own inputs, L4 cannot read the line at all and answers `unexpected WITH`. Proposed, not landed (2026-09-04); it arrives in a later version of L4. Until then: hoist or rename._

---

## 5. Diagnostics

Five of the six entries below are messages L4 puts on your screen; find yours by its first line. The sixth, [No error, but the wrong definition](#no-error-but-the-wrong-definition), is the case where nothing appears on screen at all and the answer is still wrong — start there if the file checks cleanly and a rule is reading a definition you did not intend.

### Two candidates, no way to choose

```
There are multiple definitions for the identifier

  `age of majority`

and I do not have sufficient information to make a choice between them.
The options are:

  `Part 4`.`Division 8`.`age of majority` (defined at …) of type NUMBER
  `Part 4`.`Division 7`.`age of majority` (defined at …) of type NUMBER
```

**What it means.** Nothing on the using rule's ancestry settled the name, and more than one declaration of it was left in the running. L4's messages say **identifier** where this page says **name**; the two words mean the same thing here. Three things to know when reading it:

- it is reported **at the place the name was used**. Neither declaration is flagged; `(defined at …)` beside each candidate is how you find them;
- each candidate is printed under its **section-qualified spelling**, which is the fix, copy-able as it stands. Ordinary definitions, rules, section `GIVEN`s and kinds of thing declared with `DECLARE` all print that way. A record's field name and the name used to build a record do not: they print bare, with no section in front (see [Three errors from one ambiguous `DECLARE`](#three-errors-from-one-ambiguous-declare) below);
- the candidates are listed **last-declared first**.

**The fix.** Qualify the use with the spelling the message printed. If the two declarations were meant to be one thing, hoist one declaration to a shared ancestor heading and delete the other; if they were meant to be two things, rename one.

### The same name twice in one section

```
There are multiple definitions for the identifier

  `the rate`

and I do not have sufficient information to make a choice between them.
The options are:

  `Part 7`.`the rate` (defined at …:3:11-21) of type NUMBER
  `Part 7`.`the rate` (defined at …:2:11-21) of type NUMBER
```

**What it means.** The same message, but look at the two candidates: they print the **same** qualified spelling and differ only in position. This is a name declared twice in one section — as an ordinary definition, a rule, a `DECLARE`, or twice on one heading's `GIVEN`.

**The fix.** Qualifying cannot help here, because there is no spelling that names one and not the other. Delete one, or rename one.

### A name that is not there

```
I could not find a definition for the identifier

  `prescibed rate`

which I have inferred to be of type:

  NUMBER
```

The last two lines report what kind of thing the surrounding rule needed the name to be, worked out from where it was used. They are a hint about the missing declaration, not a second fault.

**What it means.** The name is misspelled, or it has not been declared anywhere in the file. Because sections never hide a name, this message never means "declared in another section, and that section is out of reach" — that state does not exist. There is one place it appears for a name you can see on the page: a record built under a `DECLARE`'s [`AKA`](../functions/AKA.md) alias, described in [Limits](#6-limits).

**The fix.** Correct the spelling, or declare it. Backticked names are matched character for character, so a stray space or a capital counts.

### A section `GIVEN` that has been pushed back to column 1

```
This GIVEN starts at column 1, so it is the signature of the declaration
below it -- and that declaration never uses

  `the rate`

If `the rate` was meant as an input for the whole of

  § `Part 7`

indent the GIVEN so that it starts past the § of the heading:

  § <heading>
      GIVEN `the rate` IS A <type>
```

**What it means.** A `GIVEN` belongs to the section only when it starts at a column past the heading's `§` — that is, when the word `GIVEN` sits further from the left margin than the `§` above it. At column 1, hard against the left margin, it is the next declaration's own inputs instead; this is usually the result of a paste or a re-indent.

The message uses one of L4's internal words. **"Signature"** is its word for the list of a rule's own inputs — so "the signature of the declaration below it" means "the list of inputs belonging to the declaration written below it". The shape the message prints at the end is the correction. Above a `DECLARE` it arrives with two neighbouring errors about names in a signature not matching the definition's; above an `ASSUME`, alone.

**The fix.** Indent the `GIVEN` line, as the message shows. This check fires only when the declaration below is a `DECLARE` or an `ASSUME` that never uses the name; it deliberately does not fire on a `DECIDE`, because a rule that ignores one of its own inputs is an ordinary thing to write.

### Three errors from one ambiguous `DECLARE`

Two sections declare a kind of thing under one name — `DECLARE T HAS f IS A NUMBER` in each — and a rule elsewhere writes `(T WITH f IS 4)'s f`. That one line reports three errors, in this order.

First, the ambiguity about the name used to build the record. Note that the two candidates print **bare**, with no section in front, so this message's spelling is not the fix:

```
There are multiple definitions for the identifier

  T

and I do not have sufficient information to make a choice between them.
The options are:

  T (defined at …) of type FUNCTION FROM NUMBER TO T
  T (defined at …) of type FUNCTION FROM NUMBER TO T
```

(`FUNCTION FROM NUMBER TO T` is how L4 writes "something that is given a number and gives back a `T`". That is a description of the two `DECLARE`s — a kind of thing with one field is completed by giving that field a value — not a fault of its own.)

Second, at the same place, a complaint that `T` is not a rule and cannot be given inputs. The kind of thing is written as a name L4 made up for itself, which shifts whenever the file changes — ignore it:

```
You are trying to apply

  T (defined at …) of type T15

(which is not a function) to (named) arguments here.
```

Third, the same ambiguity again about the field name `f`, whose two candidates also print bare.

**What it means.** Only the first message is the real fault; the second and third are consequences of it.

**The fix.** Qualify the name that builds the record — `` `Part 1`.T WITH f IS 4 `` — or say which one the rule takes, ``GIVEN x IS A `Part 1`.T``. Fix the first message and the other two go with it.

### No error, but the wrong definition

There is no message for this one. The file checks, the editor is clean, the rule answers — and the answer is the one that belongs to a different section. Everything needed to work out what happened is on this page, so here it is assembled as a checklist.

1. **Does the rule's own section, or a section enclosing it, declare the name too?** If it does, that declaration won, and step 1 of [the rule in two steps](#the-rule-in-two-steps) never looked any further. This is the commonest cause. Remember that a re-declaration under a heading reaches every rule beneath that heading, including rules a long way further down the file — `Subdivision B`'s `prescribed rate` in section 2 is the shape of it.
2. **Are the two declarations different kinds of thing** — one a number and one a piece of text, say? Then nearness did not decide it, and the order the two are written in the file may have. This is the case set out in [Limits](#6-limits), and it is the one where the page cannot tell you in advance which way it will fall.
3. **Confirm which declaration the rule actually read.** Ask for each candidate by its own qualified spelling and compare the answers against the answer the rule gave. In the companion, `` #EVAL `Part 3`.`prescribed rate` `` gives 5 and `` #EVAL `Part 3`.`Division 6`.`Subdivision B`.`prescribed rate` `` gives 7, so `local charge` answering 70 read the second of the two. Where the two candidates are different kinds of thing rather than different values, `#CHECK` on the rule does the same job: it reports the kind of thing the rule gives, which tells you which of the two it read.

**The fix.** Qualify the use with the spelling of the one you meant, exactly as for the ambiguity message above. If the two declarations were meant to be one thing, hoist one to a shared ancestor heading and delete the other; if they were meant to be two things, rename one.

---

## 6. Limits

Stated plainly, so nothing here is a surprise later. Each was measured on the version of L4 this page documents.

**A rule that reads a section `GIVEN` cannot be run to an answer until the fact is filled in.** Nothing is broken, and the file is not wrong. Checking the file passes — `l4 check` prints `Check succeeded.` and the editor shows no error — and `#CHECK` still reports what kind of thing the rule gives. It is only asking for the answer, with `#EVAL`, that stops, and it stops by saying exactly what it is waiting for:

```
I could not continue evaluating, because I needed to know the value of
  `the rate`
but it is an assumed term.
```

The fact is filled in from outside the file. Three places do it: a person entering it on a web form; `l4 batch`, the command that runs a published rule over cases written in a file; and `jl4-service`, which answers the same questions over a network for other programs. All three send the fact under the name as it is written in the L4 file. The smallest complete example is `Part 7` from section 4 with `@export` written above the rule to publish it — that added line is why this block is not in the companion, whose `Part 7` is otherwise the same:

```l4
§ `Part 7`
    GIVEN `the rate` IS A NUMBER

@export
GIVETH A NUMBER
`ordinary charge` MEANS `the rate` TIMES 100
```

Save that as `charges.l4`, put the fact in a file beside it, and ask. The run below is measured:

```
$ cat case.json
{ "the rate": 0.2 }

$ l4 batch charges.l4 --inputs case.json
{"diagnostics":[],"input":{"the rate":0.2},"output":[{"result":20,"trace":null}],"status":"success"}
```

`"the rate"` in `case.json` is spelled exactly as the `GIVEN` line spells it, and 20 is `0.2 TIMES 100`. [The section `GIVEN`](section-given.md) gives the fuller account of what is published and how. _Proposed, not landed (2026-09-04): filling a fact in inside the file itself, so that one `#EVAL` can answer without any of this. It arrives in a later version of L4._

**Two declarations of one name that are different kinds of thing are not reliably separated by which section they are in.** This is the one place the table in section 2 is not the whole story. Where the two are the same kind of thing, nearest wins as described. Where they are different kinds, the order the file is written in can decide the outcome. Measured: with the number written first and the text second, the section's own declaration wins —

```l4
§ `Part 9`
`the limit` MEANS 500
`limit note` MEANS `the limit`

§ `Part 10`
`the limit` MEANS "not set"
```

— `limit note` gives 500. Move `§ Part 10` above `§ Part 9`, changing nothing else, and the same rule is an error naming both candidates. The advice is not to memorise which way round it goes: **do not use one name for two different kinds of thing in one file.** Qualify, or rename.

**Two sections that declare the same name cannot both be filled in for one case.** Inside the file the two names behave as the table says: each section's rules read their own. But a fact arrives from outside the file under the name as written, and both are written `the applicant`, so nothing in what arrives says which of the two is meant. Measured on a file whose `Division 14` and `Division 15` each declare `the applicant` and each publish a rule that reads it: `l4 batch` answers neither rule, though the file itself checks clean. Rename one of them if both have to be filled in; the two names were doing two jobs anyway.

**A name declared twice in the same section has no qualified way out.** Both candidates carry the same qualified spelling. Delete or rename one.

**One arrangement that looks resolvable is not.** Two child sections both re-declare a name, and their parent uses it, with one child's declaration written above the use and the other's below. Only one of the two could plausibly be meant, but the result is still the ambiguity error. Qualify the use.

**A forward reference to a rule that has a rule `GIVEN` and no `GIVETH` can be ambiguous.** If a rule is used in its own section before it is written, and the root declares a rule of the same name and the same shape, both stay in the running. The one-line fix is to **add a `GIVETH`** to the rule, which is good practice anyway; writing the rule above the use also works.

**Names arriving through `IMPORT` are never ranked by nearness.** A file can use the definitions written in another file by naming that file after `IMPORT` at the top — `IMPORT rates`, for the file `rates.l4`. A name arriving that way stays a candidate alongside the nearest declaration in the importing file rather than losing to it, so a collision between an imported name and a local one is an ambiguity rather than a silent choice. Measured: a file that imports a `the rate` and then declares its own `the rate` under a heading cannot use the bare name inside that heading — the message names both, one with its section and one with the other file. Qualifying the local one fixes it. The design intent is that an import is never silently overridden.

**`AKA` on a `DECLARE … HAS …` names the kind of thing, not the building of a record.** For `DECLARE Ticket AKA Coupon HAS price IS A NUMBER`, the alias resolves wherever the kind of thing is named, qualified or not; `Coupon WITH price IS 4` does not, and reports that it cannot find `Coupon`. Build records with the `DECLARE`'s primary name, `Ticket`. This is a property of [`AKA`](../functions/AKA.md), not of sections, but it shows up when qualifying across sections.

---

## Related keywords

- [`AKA`](../functions/AKA.md) — an alias for a heading or a definition, usable anywhere in a qualified name
- [`GIVEN`](../functions/GIVEN.md) — the inputs of one rule
- [The section `GIVEN`](section-given.md) — one `GIVEN` shared by every rule in a section

## See also

- [Section markers (§)](README.md#section-markers-) — the short summary in the keyword reference for this chapter
- [What a Section Needs to Know](../../tutorials/section-given/what-a-section-needs-to-know.md) — the tutorial that builds a two-section file from scratch
- [sections-example.l4](sections-example.l4) — the checked companion to this page
