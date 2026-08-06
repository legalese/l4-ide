# Grouping and Precedence: What Binds to What

**Time:** 15 minutes. **Prerequisites:** [Your First L4 File](first-l4-file.md).

Every formal language has to answer one question before it can mean anything:

> Given `a OR b AND c` — what binds tighter?

This is the lightest formal method there is. No proofs, no model checker, no temporal logic. Just a
grammar that answers the question the same way every time. And it is the one formal method that
legal drafting has never adopted — which is why a comma has cost real litigants millions of dollars,
more than once.

This page is about how L4 answers it, and what changes when the answer is forced to be visible.

---

## 1. Three ways to say what binds to what

A conventional programming language gives you two mechanisms:

**A precedence table.** `AND` binds tighter than `OR`, so `a OR b AND c` parses as `a OR (b AND c)`.
The rule lives in the language definition, not in your file. You are expected to have memorised it.

**Parentheses.** When the table gives you the wrong grouping, or when you want a reader to see the
grouping without consulting the table, you write it out: `(a OR b) AND c`.

Natural language has neither. It has punctuation, convention, and the reasonable-reader standard —
which is to say, it has litigation. A statute is a formal document with no formal grammar, so
"what binds to what" is decided years later by whoever is holding the losing end of it.

L4 adds a third mechanism, and makes it the primary one:

**Layout.** Indentation is the grouping.

```l4
-- (a OR b) AND c
            `a`
        OR  `b`
    AND `c`

-- a OR (b AND c)
        `a`
    OR      `b`
        AND `c`
```

The deeper block binds first. You can check that these really differ rather than taking it on
trust — with `a` true and `b`, `c` false, the first is FALSE and the second is TRUE:

```l4
#EVAL `left grouped`  TRUE FALSE FALSE   -- FALSE
#EVAL `right grouped` TRUE FALSE FALSE   -- TRUE
```

### L4 will tell you when you have not decided

Put an `AND` and an `OR` at the **same** indentation and the compiler objects:

```
AND and OR operators appear at the same indentation level (column 5). This may indicate
a precedence error - please use indentation to clarify precedence; in a pinch,
parentheses may also be used.
```

That is this entire page, enforced by the tool. Mixing the two operators at one depth is exactly
the state a comma leaves a sentence in: two readings, no decision. Note that `...` counts as `AND`
and `..` counts as `OR`, so the check sees through the asyndetic sugar.

It is a **warning**, not an error — the file still compiles, because sometimes you really do mean
the default. But an unexplained one in a statutory encoding is a fork you have not registered.

### The form to watch for

Write the same expression on **one line** and the warning does not fire at all:

```l4
DECIDE `one line` IF `a` OR `b` AND `c`
```

Here L4 falls back on the conventional table — `AND` binds tighter — so this is `a OR (b AND c)`,
and `#EVAL` with `TRUE FALSE FALSE` returns TRUE. Add parentheses to get the other reading and it
returns FALSE. Measured, both.

Notice what that means for review. The one-line form is the one that most **resembles the statute**:
a single flowing clause, no visual structure, exactly like the sentence it came from. And it is the
one where the grouping is decided by a precedence table your legal reviewer has never read. **When
you are encoding law, break mixed `AND`/`OR` across lines even when it fits on one.** The extra
lines are where the decision becomes reviewable.

---

## 2. Why layout, and not parentheses

Two reasons, and the second is the real one.

**Parentheses are already spoken for.** In L4 they group expressions and wrap arguments —
`` `add years` (transfer's `date issued`) 1 ``. Overloading one symbol for statutory limb structure,
in exactly the place where a reader must not have to guess, is how you get a language nobody can
review.

**Layout cannot be omitted.** This is the point. You can write English prose and simply _decline_ to
say what binds to what — and drafters do it constantly, usually without noticing. You cannot write
L4 without indenting something. The bracketing decision is **mandatory**, and once made it is
**visible** to anyone reading the file, including a reader who does not know the language.

That is a genuine formal-methods property arriving through the back door of typography. The
encoding cannot be silent on a question the source was silent on. Somebody has to decide, in the
open, and sign their name to the file.

And it costs the quoted words nothing. Indentation is invisible to the text itself: the statutory
prose rides along verbatim as [inert scaffolding](../../concepts/language-design/linguistic-syntax.md),
and the structure sits in the whitespace around it. You have not edited the law to formalise it.

---

## 3. Three cases where this was the whole dispute

Each of these is a different failure. Learn to tell them apart — the repair differs.

### Chew — _bracketing_

**The defect:** a comma inside a mixed AND/OR, where the grouping decides an element of a criminal
offence.

_Chew v The Queen_ concerned a provision prohibiting an officer from making improper use of their
position "to gain, directly or indirectly, an advantage" or "to cause detriment to the corporation".
Does the advantage/detriment clause state the **purpose** the officer must have had, or merely a
**result** that followed? The High Court divided.

Here is a first attempt, and it is worth seeing because **the compiler rejects the ambiguity rather
than the code**:

```l4
DECIDE `contravenes s 229(4)` IF
        "An officer or employee of a corporation shall not"
    ... `makes improper use of his position`
    ..  "as such an officer or employee,"          -- `..` is OR, at column 5
    AND     "to gain, directly or indirectly, an advantage"   -- AND, also column 5
        ...     `an advantage for himself`
            OR  `an advantage for any other person`
        OR  `detriment to the corporation`
```

Two warnings, at column 5 and column 9 — an `AND` and an `OR` tied at each depth. The tool is
asking the question the comma left open.

The repair is to commit to a shape. Here the gain/detriment limbs become a flat disjunction, one
level in from the conduct they qualify:

```l4
DECIDE `contravenes s 229(4)` IF
        "An officer or employee of a corporation shall not"
    ... `makes improper use of his position`
    ... "as such an officer or employee,"
    AND     "to gain, directly or indirectly, an advantage"
        ..  `an advantage for himself`
        ..  `an advantage for any other person`
        ..  "or to cause"
        ..  `detriment to the corporation`
```

No warnings, and it means what it looks like: improper use **and** at least one of the three
consequences. `#EVAL` with improper use, no advantage to anyone, but detriment caused returns TRUE;
drop the detriment and it returns FALSE.

Changing the third line from `..` to `...` is not a fudge — that line is an **inert string**, which
evaluates to the identity of whichever operator holds it (FALSE under OR, TRUE under AND), so it
cannot change the result either way. What it changes is the _reviewability_: the operators no longer
tie.

There is no third option where the file compiles clean and the question stays open. **The comma
became a choice you can see.**

### Oakhurst — _tokenization_

**The defect:** a _missing_ serial comma, so that what looks like one item may be two.

Maine's overtime exemption listed "the canning, processing, preserving, freezing, drying, marketing,
storing, **packing for shipment or distribution of**" certain foods. Delivery drivers distributed
but did not pack. So: is the last item **one** activity (packing, for either shipment or
distribution) or **two** (packing-for-shipment, and distribution)?

The First Circuit found it genuinely ambiguous, construed the exemption narrowly against the
employer, and the drivers won. The case settled for a reported $5 million. Judge Barron opened the
opinion: "For want of a comma, we have this case."

This is a **leaf-count** question, and it is the one that hides best, because both readings look
identical until you count:

```l4
-- One activity: "packing", qualified by either destination.
    ..  "packing for shipment or distribution"
        ... `packs the goods`

-- Two activities: packing-for-shipment, and distribution.
    ..  "packing for shipment"   ... `packs the goods for shipment`
    ..  "or distribution"        ... `distributes the goods`
```

**The lesson that generalises:** a name is read as a label, not as a proposition. If you put a
disjunction inside a field name, nobody audits it — not your reviewer, not your diagram, not your
wizard. Lift the disjuncts out and let the scaffolding carry the words. Maine later amended the
statute to use semicolons; the encoding would have forced the question on day one.

### Rogers — _attachment_

**The defect:** a comma that is _present_, scoping a trailing proviso further than one party
expected.

A support-structure agreement for utility poles ran "for a period of five (5) years …, and
thereafter for successive five (5) year terms, unless and until terminated by one year prior notice
in writing by either party." Does the termination right attach only to the **successive** terms, or
to the **initial** term as well?

The CRTC first read the comma as scoping both, letting the counterparty terminate early. Rogers then
pointed at the **French-language version** of the same agreement, which was unambiguous — and the
Commission reversed itself. (CRTC Telecom Decision 2006-45, reversed by 2007-75. The cost is
variously reported; verify against the decisions before citing a figure.)

The two readings, again as depth:

```l4
-- The notice right attaches to the renewal terms only.
    ..      "for a period of five (5) years"        ... `initial term is running`
        ..  "and thereafter for successive terms"   ... `a renewal term is running`
            ... NOT `one year notice has been given`

-- The notice right attaches to both.
    ...     "for a period of five (5) years"        ... `initial term is running`
        ..  "and thereafter for successive terms"   ... `a renewal term is running`
    ... NOT `one year notice has been given`
```

**Rogers is the case that argues for this whole approach**, and it does so from the bench rather
than from a manifesto. What resolved it was a _second, parallel, authoritative text_ that could not
express the ambiguity. That is exactly what an L4 encoding is. The regulator accepted the argument
in 2006.

---

## 4. "That's not law, that's grammar"

Experienced lawyers often wave this away. Commas are trivia; real law is doctrine, policy,
interpretation. The reasonable reader will understand.

Two answers.

**There are no trivial security holes.** No engineer has ever reported a buffer overflow and been
told it doesn't count because it's only an off-by-one. The severity of a defect is not the size of
the mistake; it is the size of what the mistake reaches. A comma that decides whether an initial
term can be terminated reaches the entire value of the contract. You cannot be a little bit
pregnant.

**And the empirical record is one-sided.** Oakhurst: reportedly $5 million. Rogers: a
multi-million-dollar contract reopened. Chew: a criminal conviction, in the High Court, on the
meaning of a clause. If this were trivia it would not keep arriving at final courts of appeal.

The house on the sand and the house on the rock are, above ground, the same house. They differ only
in the part nobody looks at. Rain fell, the floods came, the winds blew and beat upon that house —
"and great was the fall of it." (Matthew 7:24-27.)

---

## 5. What to do, in practice

1. **Write the source text in first, as inert strings.** Get the words down before you get the
   structure down; you will find the ambiguity while typing.
2. **When you cannot tell what binds to what, write both indentations.** Two files, or two private
   predicates. If you cannot construct a fact pattern that separates them, the ambiguity is
   harmless. If you can, you have found a fork.
3. **Register the fork rather than resolving it silently.** Record the readings, the reading taken,
   why, and the witness that separates them. A resolved ambiguity with no record is indistinguishable
   from an ambiguity nobody noticed.
4. **Never put a disjunction inside a field name.** See Oakhurst above. If the source runs disjuncts
   together without labelling them, decompose. If the source _defines_ the span as a term of art,
   leave it whole — splitting it would invent structure the drafter overrode.
5. **Check the other language version, if there is one.** Rogers turned on it. Bilingual
   jurisdictions ship a second authoritative text for free, and it is a natural experiment in
   whether your reading is forced or merely available.

---

## Where next

- [Linguistic Syntax](../../concepts/language-design/linguistic-syntax.md) — why inert scaffolding is
  structure and not decoration, and how the inert path qualifies a leaf name
- [Encoding Legislation](encoding-legislation.md) — the full workflow from statute to L4
- [Default Reasoning and Exceptions](../../concepts/legal-modeling/default-reasoning.md) — the
  general-rule-plus-exception shape these limbs usually sit inside
