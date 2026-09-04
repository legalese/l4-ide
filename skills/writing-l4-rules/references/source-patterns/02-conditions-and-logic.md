# 2. Conditions and logic

One area of the phrasebook. The index, the preamble and the other ten areas are in
[source-patterns.md](../source-patterns.md).

<a id="e2-1"></a>

## 2.1 "This section does not apply where …" — the gate and the exemption

**If the source says**

> `s 28(2) — "Subsection (1) shall not apply where the grantee is the Public Trustee or a trust company."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:2715`

**It is doing** switching something off — and the scale matters. A whole Act (a gate consulted
first), one section (an outcome the caller must handle), one duty (an exemption), or one limb of a
calculation.

**Write**, for a duty, the duty **not arising at all**. "s 28(2) is an exemption from the duty
[capitals in the original], not a permission to omit it, so it is encoded by the duty not arising at
all rather than by a `MAY`" (`:2716-2717`).

```l4
@ref Probate and Administration Act 1934 s 28(1), s 28(2)
GIVEN gr IS A Grantee
GIVETH A DEONTIC Grantee `An act under the Probate and Administration Act`
`s 28 — the grantee shall take an oath` gr MEANS
    IF   `s 28(2) — the grantee is the Public Trustee or a trust company` gr
    THEN FULFILLED
    ELSE PARTY gr
         MUST  `take an oath in the prescribed form`
         WITHIN 14
```

For a **section** whose result a caller reads, make "this section is silent" a named member of the
section's own result type, as in [entry 4.1](04-dates-and-periods.md#e4-1) — so a caller matching on the result has to handle it. For
a **limb**, append `UNLESS` and name the defeater; for a whole Act, a boolean gate consulted before
anything else.

**Not** `REFUSE`, twice over: the statute has decided this case, and it has decided it in a way a
later provision may need to read. **Not** `MAY` for an exemption — a permission not to do it is a
different legal animal from a duty that never arose, and it exports differently.

**See** [regulative.md](../regulative.md) for `MUST`/`MAY` polarity and residuals;
[drafting-patterns.md](../drafting-patterns.md), "Total enum over `MAYBE`", for the named-outcome shape;
<https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md>
for `UNLESS`.

---

<a id="e2-2"></a>

## 2.2 "Subject to section N", "Notwithstanding anything in this Act"

**If the source says**

> `s 27(1) opens "Notwithstanding anything in this Act", so it is asked FIRST: a soldier in actual military service or a mariner at sea may make a will with no writing, no signature, no witnesses and no majority`
>
> — the encoding's note at `jl4/examples/legal/sg-succession/sg-wills.l4:712-715`, on Wills Act
> 1838 s 27(1)

**It is doing** declaring an express priority between two provisions.

**There is no construct for it.** `SUBJECT TO` and `NOTWITHSTANDING` are **not keywords today** —
the lexer has no token for either. A dedicated construct is proposed, not landed (2026-09-04).

**Write** the priority in one of the three ways the corpus uses. The first — arm order — looks like
this:

```l4
@ref Wills Act 1838 s 27(1), s 4, s 6
GIVEN w IS A Will
GIVETH A BOOLEAN
`the will is formally valid` w MEANS
  BRANCH
    IF   w's `made by a soldier in actual military service or a mariner at sea`
    THEN TRUE
    IF   NOT w's `the testator had attained the age of 21 years`
    THEN FALSE
    OTHERWISE w's `signed by the testator and attested by two witnesses`
```

1. **Arm order.** `BRANCH` is first-match, so the overriding provision goes first, and the order
   is the Act's own — record that in a comment, because the order is now load-bearing.

   **Where the Act states no priority, the order is yours, and the comment must say so.** A `BRANCH`
   over several sections has to put them in _some_ order even when no section says "notwithstanding"
   or "subject to" — most Acts do not. Writing "the Act's own order of priority" over an order you
   invented is a false claim in the one place a later reader will trust it. Write instead what you
   actually did and why, in the reader's terms: reach first, force second, exemption third,
   computation last.

   ```l4
   -- ARM ORDER. The Act states no priority between ss 3, 5 and 6. This order is
   -- the ENCODING's, chosen so each arm only runs where the ones above it did not
   -- decide the case: does the Act reach this transaction at all (s 6), is it in
   -- force for it (ss 1, 5), does s 2 apply to it (s 3), and only then the sum.
   ```

   Two consequences worth stating on the same comment: an arm that is genuinely disjoint from the
   others could sit anywhere, and reordering the arms is a change to the law the file states, not a
   tidy-up.

2. **`UNLESS` naming the overriding rule**, where the override subtracts from a conclusion rather
   than replacing it — the snippet below.
3. **The override in the name of the decision** —
   `` DECIDE `a British citizen notwithstanding cesser of the order — subsection (6)` ``
   (`jl4/examples/legal/bna/bna.l4:572`), with assertions on both sides.

```l4
GIVEN w IS A Will
GIVETH A BOOLEAN
`a grant of probate may issue on the will` w MEANS
    `the will is formally valid` w
    UNLESS `a caveat is in force against the estate`
    WHERE `a caveat is in force against the estate` MEANS FALSE
```

**Not** a grep for "subject to". The phrase does both jobs in this corpus, and the commoner one is
not the priority operator. Measured 2026-09-04 over the 26 files under `jl4/examples/legal/`: 173
occurrences, of which 89 sit inside a backticked name — 21 distinct names, every one of them a
**status** rather than a priority, headed by `` `subject to the requirement to file reports pursuant
to section 13 or section 15(d) of the Exchange Act` `` (`jl4/examples/legal/regcf/regcf.l4:283`, and
five more sites in that file). Every occurrence in `regcf.l4` is of that kind. The real priority
operator does appear, in the succession files, and there it is handled by technique 3 above: the
override is written into the **name** of the rule — `` `s 8(3) — probate may be granted to one or
more of the persons so appointed, subject to section 6` ``
(`jl4/examples/legal/sg-succession/cleanroom-2026-08/probate-administration-act.l4:898`), whose first
rung carries the words themselves as an inert string, `"Subject to section 6,"` (`:899`). Read which
one you have before encoding it.

**Not** an override of a refusal. A "subject to" provision overrides a **conclusion**; a refusal is
not a conclusion and nothing can override it.

**See** <https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md>
(its table maps "Subject to section N" to `UNLESS` naming that section's rule) and
[drafting-patterns.md](../drafting-patterns.md), "Conditional / proviso limb" and "Only in a case where
X applies".

---

<a id="e2-3"></a>

## 2.3 "if …", "where …", "in any case where …" — the ordinary condition

**If the source says**

> `s 5A(1): "This section applies where — (a) the court makes an order under section 5 (called in this section the access order) giving a person (X) access to a child; and (b) the order is breached by the person (Y) who is required by the order to give X access to the child."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/guardianship-of-infants-act.l4:587-592`

**It is doing** stating the facts that have to hold before the provision has anything to say.
Statutory "where" is almost always "if": it introduces a condition, not a place and not a scope.
Both words map to the same thing, and the commonest of all encoding jobs is this one.

**Write** the condition as the body of a boolean decision, and let the name say what is being
decided rather than what is being asked:

```l4
@ref Guardianship of Infants Act 1934 s 5A(1) — "This section applies where — (a) … ; and (b) …"
GIVEN breach IS A `A breach of an access order`
GIVETH A BOOLEAN
DECIDE `section 5A applies to the breach` IF
        breach's `the court makes an order under section 5 giving X access to a child`
    AND breach's `the order is breached by Y`

#ASSERT `section 5A applies to the breach` `a breach on both limbs`
```

`DECIDE … IF` is the form for a rule that answers yes or no. `IF … THEN … ELSE …` is the form for a
rule that answers with a **value**, and it needs the `ELSE`: leave it off and the parser stops at the
end of the definition with `unexpected end of input / expecting %, ELSE, OF, or space token`.

**Not** L4's `WHERE`. It is a block of local definitions, not the statute's "where", and reaching for
it because the section did produces a parse error that names none of that. This —

```l4
GIVEN `the order is breached by Y` IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `section 5A applies` IF
    `the section applies`
    WHERE `the order is breached by Y`
```

— stops with

```
    unexpected end of input
    expecting AKA, MEANS, OF, or space token
```

because `WHERE` wants a definition, `name MEANS …`, after it.

**Not**, either, `IF cond THEN TRUE ELSE FALSE`. It type-checks, nothing warns, and it puts a
decision node in the ladder diagram and a question in the generated wizard where the source has only
a condition.

**See** [gotchas.md](../gotchas.md), "`DECIDE`: IS vs MEANS vs IF" for choosing the form and
"`LET … IN` vs `WHERE`" for what `WHERE` is actually for;
<https://legalese.com/l4/reference/control-flow/IF.md>.

---

<a id="e2-4"></a>

## 2.4 "No will shall be valid unless it is in writing" — the "unless" that is a requirement

**If the source says**

> `"No will shall be valid unless it is in writing and executed in the manner mentioned in subsection (2)."`
>
> — quoted in the encoding at `jl4/examples/legal/sg-succession/sg-wills.l4:110-111`, on Wills Act
> 1838 s 6(1)

**It is doing** stating a **necessary condition**, in the negative-plus-exception form legal drafting
prefers. "No X unless C" is "X only if C", which is "C is required for X" — a conjunct of the
validity test. It is not a defeasible general rule with a carve-out, which is the other job the word
"unless" does (entry [2.2](#e2-2), and the exceptions of entry [2.1](#e2-1)).

**Tell them apart by asking what survives the removal of the clause.** Strike "unless it is in
writing" and every will is valid — so the clause is doing the _making_, and it is a conjunct. Strike
"unless a caveat is in force" from a grant provision and grants still issue on the ordinary
conditions — so that clause is _subtracting_, and it is an `UNLESS`.

**Write** it positively, as the conjunction of the requirements, one named rule per subsection:

```l4
@ref Wills Act 1838 s 6(1) — "No will shall be valid unless it is in writing and executed in the manner mentioned in subsection (2)"
GIVEN w IS A Will
GIVETH A BOOLEAN
`the will is in writing and executed in the manner mentioned in subsection (2)` w MEANS
        w's `in writing`
    AND `the will is executed in the manner mentioned in subsection (2)` w

@ref Wills Act 1838 s 6(2)
GIVEN w IS A Will
GIVETH A BOOLEAN
`the will is executed in the manner mentioned in subsection (2)` w MEANS
        w's `signed at the foot or end by the testator`
    AND w's `the signature was made or acknowledged before 2 witnesses present at the same time`
```

Keep the burden where the section puts it. The corpus says so in terms: the prohibition with an
exception "must be encoded that way round, with the burden on the propounder, not softened into a
permission" (`jl4/examples/legal/sg-succession/cleanroom-2026-08/family-domain.l4:1176-1182`).

**Not** a word-for-word transcription onto `UNLESS`. `A UNLESS B` is `A AND NOT B`, so

```l4
`the will is valid` w MEANS
    TRUE UNLESS w's `in writing`
```

answers `FALSE` for a will that **is** in writing — the exact inversion of the section. It
type-checks, it produces no diagnostic, and `l4 run` exits 0.

**See** <https://legalese.com/l4/concepts/legal-modeling/default-reasoning.md> for the `UNLESS` that
really is an exception, and [drafting-patterns.md](../drafting-patterns.md), "Negative limb — `NOT`
atom, and the negated disjunction", for "not granted via any of (i)–(iii)", where the negation
scopes a whole list and De Morgan's law is the thing to get right.

---

<a id="e2-5"></a>

## 2.5 "provided that", "provided, however, that" — two jobs, and the second reorders your arms

**If the source says**

> `"(a) Exemption. An issuer may offer or sell securities in reliance on section 4(a)(6) of the Securities Act of 1933, provided that:"`
>
> — `jl4/examples/legal/regcf/regcf.l4:898`, quoting 17 CFR (the Code of Federal Regulations)
> § 227.100(a)

**It is doing** one of two quite different things, and the encoding differs completely.

1. **"provided that:" as a colon before a list** — the drafter's word for "if all of the
   following". Encode it as the conjunction it is.
2. **"provided, however, that …" mid-sentence** — a real proviso, which carves a case out of the
   clause it is attached to and often **decides that case the opposite way**. Encode it as an arm
   that is tested **before** the clause it qualifies.

**Write**, for job 1, the chapeau as an inert string over the conjoined limbs:

```l4
@ref 17 CFR 227.100(a)(1)-(3)
GIVEN issuer IS AN IssuerProfile
GIVETH A BOOLEAN
`the issuer may rely on section 4(a)(6)` issuer MEANS
        "(a) Exemption. An issuer may offer or sell securities in reliance on section 4(a)(6) of the Securities Act of 1933, provided that:"
    ... "(1)" ... issuer's `the aggregate amount sold in the preceding 12 months is within the limit`
    ... "(2)" ... issuer's `each investor's aggregate purchases are within the investor limit`
    AND "(3)" ... issuer's `the transaction is conducted through one intermediary that complies with section 4A(a)`
```

For job 2, put the proviso arm first and say in a comment that the order is not the source's.
§ 227.201(t)(3) requires audited financial statements above $618,000 "provided, however, that" a
first-time issuer up to $1,235,000 needs only reviewed ones — so the proviso **inverts its own main
clause** (`jl4/examples/legal/regcf/denovo/regcf-denovo.l4:1777-1785`):

```l4
@ref 17 CFR 227.201(t)(1)-(3) — the (t)(3) proviso is tested before the (t)(3) main clause
GIVEN issuer IS AN IssuerProfile
GIVETH A `financial statement requirement`
DECIDE `the financial statements required` issuer IS
    BRANCH IF issuer's `the aggregate target offering amount` AT MOST 124000
           THEN `tax return information certified by the principal executive officer`
           IF issuer's `the aggregate target offering amount` AT MOST 618000
           THEN `financial statements reviewed by an independent public accountant`
           -- the proviso, out of citation order and labelled as such
           IF     NOT issuer's `previously sold securities in reliance on section 4(a)(6)`
              AND issuer's `the aggregate target offering amount` AT MOST 1235000
           THEN `financial statements reviewed by an independent public accountant`
           OTHERWISE `financial statements audited by an independent public accountant`
```

**Not** the arms in citation order. Written that way — general limb above proviso — the same file
answers `` `financial statements audited by an independent public accountant` `` for a first-time
issuer raising $1,000,000, which is wrong, with no error, no warning and exit 0. The corpus flags
this as `"the cleanest numeric decision in the part, and the one most likely to be encoded WRONG"`
(`regcf-denovo.l4:1777-1785`).

**See** [drafting-patterns.md](../drafting-patterns.md), "Conditional / proviso limb — `(NOT X) OR
Y`", for the proviso that only ever _subtracts_ (it is a limb, not an arm), and entry
[2.2](#e2-2) for arm order and the comment it obliges you to write.

---

<a id="e2-6"></a>

## 2.6 "any of the following", "all of the following" — the chapeau and its numbered limbs

**If the source says**

> `"unless such securities are transferred:"` — the chapeau, carried verbatim into the encoding at
> `jl4/examples/legal/regcf/regcf.l4:859`, over limbs `"(1)"` … `"(4)"` of 17 CFR § 227.501(a)

**It is doing** distributing one condition over a numbered list. The chapeau tells you which
operator: "any of the following" and a list ending "; or" are disjunctive; "all of the following"
and a list ending "; and" are conjunctive. The numbering is not decoration — it is how a reader
navigates back to the source, and it belongs in the encoding.

**Write** the disjunctive form with the chapeau as an inert string, one rung per numbered limb, the
`..` sugar on every rung but the last and the keyword spelled on the last:

```l4
@ref 17 CFR 227.501(a)(1)-(3)
GIVEN transfer IS A Transfer
GIVETH A BOOLEAN
`transfer falls within an exception in Rule 501(a)` transfer MEANS
        "unless such securities are transferred:"
    ..  "(1)" ... transfer's `to the issuer of the securities`
    ..  "(2)" ... transfer's `to an accredited investor`
    OR  "(3)" ... transfer's `as part of an offering registered with the Commission`
```

The conjunctive form takes `...` and `AND`. Where the limbs are themselves named rules rather than
record fields, drop the inert scaffolding and write the plain conjunction. That is what the corpus
does for the early-close conditions of 17 CFR § 227.304(b)
(`jl4/examples/legal/regcf/denovo/regcf-denovo.l4:2375-2384`): each numbered condition is a rule of
its own, named for the paragraph it comes from, and the top rule applies those rules to `offering`
rather than reading fields off it.

```l4
@ref 17 CFR 227.304(b) — the conjunctive conditions on an early close
GIVEN offering IS AN OfferingProfile
GIVETH A BOOLEAN
DECIDE `the issuer may close the offering early` offering IF
        offering's `sum of the investment commitments` AT LEAST offering's `target offering amount`
    AND offering's `new offering deadline` LESS THAN offering's `deadline identified in the issuer's offering materials`
    AND `304(b)(1) — the offering remained open for at least 21 days` offering
    AND `304(b)(2) — the early-close notice says what it must` offering
```

**Count the conjuncts against the paragraph including its chapeau.** The corpus's own version of this
rule has **six**, not the four the paragraph numbers: limbs (1) to (4) as named rules, plus the two
inline comparisons shown above — that the new deadline falls before the deadline in the offering
materials, which only the chapeau states, and that the commitments reach the target. A count taken
off the numbered list alone drops a condition nobody numbered.

**Not** `..` under a conjunctive chapeau. The two sugars differ by one character, and the wrong one
is not a type error. Four conjunctive conditions written as an inert-string chain with `..` where
`...` was meant answer `TRUE` for an offering that met only the first of them. Nothing warns;
`l4 run` exits 0. This is the whole reason the last rung spells its keyword — a chain that only ever
says `..` never says what kind of chain it is, and a chain of nothing but `..` reads as `OR`
(measured).

**Not** a limb whose name is the limb's entire sentence. Lift each disjunct to a short atom and let
the inert strings carry the statutory words; a 288-character field name defeats the ladder diagram,
the sentence renderer and the wizard at once.

**See** [drafting-patterns.md](../drafting-patterns.md), "Spell the last connective — `..` … `OR`,
and `...` … `AND`" for the ruling, `"When the source supplies no label, DECOMPOSE"` for the limb that
hides four disjuncts inside one, and "Layout expresses scope even where the operator is associative"
for why an inert string's indentation is load-bearing; [gotchas.md](../gotchas.md), "Asyndetic
operators `...` and `..`".

---

<a id="e2-7"></a>

## 2.7 "includes", "including but not limited to", "or other similar circumstance"

**If the source says**

> `"The decomposition STOPS HERE. 17 CFR 227.501(c) defines 'member of the family of the purchaser or the equivalent' with 'includes' — an open list of 14 relationships plus adoptive ones. Enumerating them would encode an open term as a closed one, which is a worse fidelity loss than the one this decomposition repairs."`
>
> — the encoder's note at `jl4/examples/legal/regcf/regcf.l4:768-772`

**It is doing** naming examples without exhausting the category. "Includes" is not "means" (entry
[1.1](01-definitions-and-scope.md#e1-1)); a list introduced by it stays open, and the residue is
exactly where the litigated cases live.

**Write** the named examples **plus a limb for the residue**, phrased as a question someone has to
answer rather than as a catch-all that is true by construction:

```l4
@ref 17 CFR 227.501(a)(4), (c) — (c) defines the term with "includes", so the list is open
DECLARE Transfer HAS
    `the transferee is a child of the purchaser`      IS A BOOLEAN
    `the transferee is a grandchild of the purchaser` IS A BOOLEAN
    -- The limb "includes" leaves open. It is a question someone has to answer,
    -- not a catch-all that is TRUE by construction.
    `the transferee is otherwise a member of the family of the purchaser or the equivalent within § 227.501(c)` IS A BOOLEAN

GIVEN transfer IS A Transfer
GIVETH A BOOLEAN
`the transferee is a member of the family of the purchaser or the equivalent` transfer MEANS
        "(c)"
    ..  transfer's `the transferee is a child of the purchaser`
    ..  transfer's `the transferee is a grandchild of the purchaser`
    OR  transfer's `the transferee is otherwise a member of the family of the purchaser or the equivalent within § 227.501(c)`
```

The alternative the corpus actually took is **one atom**: where the open term is defined elsewhere
and you are not encoding the definition, keep the whole phrase as a single boolean input and record
in a comment why you stopped. Both are honest; enumerating and stopping is not.

**Not** a closed `IS ONE OF` over the named examples. The unlisted case then cannot be written down
at all — the file will not compile:

```
    I could not find a definition for the identifier

      niece

    which I have inferred to be of type:

      `A family relationship`
```

That error is the good outcome. The bad one is the encoding that compiles and quietly answers "no"
to every relationship the drafter did not list.

**See** [drafting-patterns.md](../drafting-patterns.md), "Do NOT decompose a term the source
defines" (its test: if the source defines the span, it is one atom however many "or"s are inside it)
and "Checkbox relation-on-an-entity — independent BOOLEAN flags + a disjunction" for the closed
kinship list, which is the shape this one is not.

---

<a id="e2-8"></a>

## 2.8 "and" — the conjunction and the union

**If the source says**

> `AMBIGUITY A1 — "sport that involves physical skill and exertion". Reading (i) CONJUNCTIVE: the sport must involve both physical skill and physical exertion. … Reading (ii) DISJUNCTIVE-ish / hendiadys … TAKEN: (i), conjunctive.`
>
> — `jl4/examples/legal/charities-cleanroom/charity-test.l4:244-251`, on Charities (Jersey) Law 2014
> Article 6(2)(c)

**It is doing** one of two jobs, and the word does not tell you which. "Cruel **and** unusual
punishments" (United States Constitution, Eighth Amendment) joins two **conditions about one
thing**: both must hold. "Residents of New York **and** New Jersey may apply" joins two **groups
into a bigger group**: being in either one qualifies you. The second is set union, and union is
disjunctive one level down.

**Write** the two with two spellings. Sentence-level conjunction keeps `AND`; term-level union is
written `UNION`:

```l4
@ref Charities (Jersey) Law 2014, Articles 6(1)(h) and 6(2)(c)
-- "and" joins two CONDITIONS about the same activity: AND, and the reading is
-- recorded because the source does not settle it.
GIVEN purpose IS A Purpose
GIVETH A BOOLEAN
`(h) — the advancement of public participation in sport` purpose MEANS
        "(h)" ... purpose's `the advancement of public participation in sport`
    ... "(2)(c)" ... purpose's `sport that involves physical skill and exertion`

-- "and" joins two GROUPS of people into a bigger group: UNION, never AND.
`new yorkers`   MEANS setFromList (LIST "alice", "bob")
`new jerseyans` MEANS setFromList (LIST "carol")
`residents of New York and New Jersey` MEANS `new yorkers` UNION `new jerseyans`
```

**Record the reading in a comment wherever the source leaves it open**, as the charities encoding
does. The conjunctive/hendiadys choice there decides whether darts and tug-of-war are sports for the
purposes of the head, and nothing in the text settles it.

**Not** `AND` between two sets. It is a type error, on purpose, and the message says so:

```
    The first argument of function

      `__AND__` (predefined)

    is expected to be of type

      BOOLEAN

    but is here of type

      SET OF STRING
```

The error is the feature: it fires at the exact token where a human once had to choose between the
two readings, and writing `UNION` records that they chose. `OR` between two sets is the same error,
and "residents of New York or New Jersey" is also `UNION` — the word in the source does not
decide it.

**See** [sets.md](../sets.md) for the whole vocabulary and its traps (`` `set equals` `` never bare
`EQUALS`; `` `LESS` `` needs backticks; word operators have no precedence) and
<https://legalese.com/l4/tutorials/set-operators/sets-and-the-two-ands.md>, which walks the two
readings through decided cases in which the same court read the same word both ways.

---

<a id="e2-9"></a>

## 2.9 "either … or", "either, but not both", "both … and"

**If the source says**

> `s 5A(6): "In respect of a breach of an access order, X may do either, but not both, of the following: (a) make an application under subsection (2); (b) bring proceedings to punish Y for contempt of court in respect of that breach."`
>
> — `jl4/examples/legal/sg-succession/cleanroom-2026-08/guardianship-of-infants-act.l4:685`

**It is doing** two different things depending on the three words after "either". Bare "either … or"
is ordinary inclusive disjunction — write `OR` and stop. "Either, but not both" is an **election**:
the section forbids one of the four combinations, and the forbidden one is a state the parties can
actually get themselves into.

**Write** an election as a type with one constructor per state, so the forbidden combination is
nameable and the rule about it has something to be about:

```l4
@ref Guardianship of Infants Act 1934 s 5A(6)(a)-(b) — "X may do either, but not both, of the following"
DECLARE `What X has done in respect of the breach` IS ONE OF
    `neither`
    `made an application under subsection (2)`
    `brought proceedings to punish Y for contempt of court in respect of that breach`
    `both made an application under subsection (2) and brought proceedings for contempt`

GIVEN `what X has done` IS A `What X has done in respect of the breach`
GIVETH A BOOLEAN
DECIDE `X has kept within the election permitted by section 5A(6)` IF
    CONSIDER `what X has done`
    WHEN `both made an application under subsection (2) and brought proceedings for contempt` THEN FALSE
    OTHERWISE TRUE
```

The corpus calls this `"THE ONE GENUINE EXCLUSIVE CHOICE IN THE ACT … Four states, not two booleans"`
(`guardianship-of-infants-act.l4:686-687`). "Both … and" is the mirror image and needs nothing
special: it is `AND`.

**Write** the enumeration in the source's own order, and give the "neither" state a name. A drafter
who says "either, but not both" has usually not said what happens if X does neither, and an
encoding that cannot express "neither" has decided that question by accident.

**Not** two independent booleans. Both flags set is then an ordinary value of the record, `OR` over
them answers `TRUE`, and nothing anywhere in the file says the section forbids it — "a pair of
independent flags would let a reader think the section merely prefers one route"
(`guardianship-of-infants-act.l4:688-689`).

**See** [drafting-patterns.md](../drafting-patterns.md), "Total enum over `MAYBE` — where the source
names the absent case", for the same move applied to outcomes;
<https://legalese.com/l4/reference/control-flow/CONSIDER.md>.

---

<a id="e2-10"></a>

## 2.10 Numbered rules read in order — `BRANCH` as the first-match ladder

**If the source says**

> `"In effecting such distribution, the following rules shall be observed."`
>
> — `jl4/examples/legal/sg-succession/sg-isa.l4:303`, quoting Intestate Succession Act 1967 s 7

**It is doing** setting out a list of rules meant to be worked through in order, each with its own
antecedent. Mutual exclusivity is usually implicit: the corpus notes that the nine distribution
rules "are mutually exclusive once read together, but the Act does not say so" (`sg-isa.l4:305-306`).

**Write** one `BRANCH` arm per numbered rule, in the Act's order, each guarded by the condition that
rule states, with the rule's own words in a comment above it:

```l4
@ref Intestate Succession Act 1967 s 7 rules 1, 2 and 4 — "the following rules shall be observed"
GIVEN c IS A Case
GIVETH A NUMBER
`the spouse's share under section 7` c MEANS
  BRANCH
    -- Rule 1: "If an intestate dies leaving a surviving spouse, no issue and
    -- no parent, the spouse shall be entitled to the whole of the estate."
    IF   c's `a spouse survives` AND (NOT c's `issue survive`) AND (NOT c's `a parent survives`)
    THEN 1
    -- Rule 2: "If an intestate dies leaving a surviving spouse and issue, the
    -- spouse shall be entitled to one-half of the estate."
    IF   c's `a spouse survives` AND c's `issue survive`
    THEN 1 DIVIDED BY 2
    -- Rule 4: spouse, no issue, but a parent.
    IF   c's `a spouse survives` AND (NOT c's `issue survive`) AND c's `a parent survives`
    THEN 1 DIVIDED BY 2
    OTHERWISE 0
```

`BRANCH` is first-match, so it gives the ladder "its own shape — one arm per rule, in the Act's
order, with the guard each rule states" (`sg-isa.l4:309-310`). Prefer it to nested `ELSE IF` for a
numbered list: the arms stay at one indentation, so an amendment that inserts a rule is a one-arm
diff rather than a re-nesting, and the shape of the code is the shape of the section. Keep each
arm's guard **complete** even where an earlier arm has already excluded part of it — the redundancy
is what lets a reader check one arm against one rule without holding the others in their head.

**Two layouts are in use, and the alignment rule is the same for both: every arm must begin
strictly to the right of the column where `BRANCH` starts.** The snippet above uses the layout this
area prefers — `BRANCH` alone on its line, the `IF`s and the `OTHERWISE` indented beneath it. The
other layout puts the first `IF` on the `BRANCH` line itself:

```l4
GIVEN hours IS A NUMBER
GIVETH A STRING
`the band for` hours MEANS
  BRANCH IF hours AT MOST 0  THEN "no hours"
         IF hours AT MOST 40 THEN "first band only"
         OTHERWISE "both bands"
```

_(Probe `r8-branch-layout.l4`, exit 0, no errors: both layouts check, and the two rules agree.)_
Arms need not line up with **each other** — a later arm at a different column than the first is
accepted (probe `r8c-branch-layoutb-misaligned.l4`, exit 0) — but an arm at or left of the `BRANCH`
column is rejected, and the message names the column, not the construct (probe
`r8b-branch-misaligned.l4`, exit 1):

```
      |
    8 |   OTHERWISE (40 TIMES 120) PLUS ((hours MINUS 40) TIMES 150)
      |   ^
    incorrect indentation (got 3, should be greater than 3)
```

Whichever layout you pick, keep it for the whole file. `SKILL.md`'s key-idioms bullet states the
same measured rule for both layouts.

**Not** a `BRANCH` with no `OTHERWISE`. It is a parse error, and the error is reported against the
**next top-level line**, not against the `BRANCH`:

```
       |
    15 | #EVAL 1
       | ^
    incorrect indentation (got 1, should be greater than 3)
```

A blank line before that next line does not help. If you see an indentation complaint about a line
that looks fine, look upward for an unterminated `BRANCH`.

**Not** an arm order you invented, presented as the Act's. Entry [2.2](#e2-2) says what to write in
the comment instead, and why the distinction matters more here than anywhere else in the file.

**See** [drafting-patterns.md](../drafting-patterns.md), "Enumerated cases (Case A / B / C)", for a
list of cases with no order to it, and <https://legalese.com/l4/reference/control-flow/IF.md>.

---

<a id="e2-11"></a>

## 2.11 "(a) X; (b) Y; and (c) Z, or (d) W" — the list that mixes "and" with "or"

**If the source says** a paragraph list whose connectives are not all the same — the common shape is
several conjuncts followed by a disjunctive alternative, and the reader is left to work out which
items the "or" reaches. This entry has no corpus witness, and that is the finding: running the
26 files under `jl4/examples/legal/` produced **no** same-column `AND`/`OR` warning at all
(measured 2026-09-04), because the encodings decompose a mixed list into named limbs before it can
arise. The shape below is the one you will produce if you transcribe such a list rung by rung
instead.

**It is doing** more than one thing at once, and the source's punctuation is usually not enough to
say what. Getting it wrong is not a type error: the two bracketings are both booleans.

**Write** the grouping with **indentation**, so the operand structure is visible at a glance:

```l4
GIVEN claim IS A Claim
GIVETH A BOOLEAN
`a ground for possession is made out` claim MEANS
            claim's `the tenant is in arrears`
        AND claim's `the arrears exceed two months rent`
    OR      claim's `the tenant has abandoned the premises`
```

Indentation is not decoration here: it **decides** the grouping, and where it disagrees with operator
precedence, indentation wins. Measured 2026-09-04 on the same three operands and the same two
operators with only the columns changed — with the `OR` indented deeper than the `AND`, the rule
reads `(a OR b) AND c` and answers `FALSE` for `a` = `TRUE`, `b` = `FALSE`, `c` = `FALSE`; with the
`AND` indented deeper it reads `a OR (b AND c)` and answers `TRUE` for those same inputs. Only when
every operator sits at one column does precedence decide, and then `AND` binds tighter than `OR`
(measured: `TRUE OR TRUE AND FALSE` is `TRUE`, not `FALSE`; `FALSE AND TRUE OR TRUE` is `TRUE`, not
`FALSE`) — which is the reading the snippet above spells out anyway, so a reader who checks the
indentation against the paragraph never has to know the precedence table.

**Not** `AND` and `OR` at the same column. The linter says so, twice, once per operator:

```
    AND and OR operators appear at the same indentation level (column 5). This may indicate a
    precedence error - please use indentation to clarify precedence; in a pinch, parentheses may
    also be used.
```

It is a warning, not an error, so `l4 run` still exits 0 and prints an answer. Treat it as an error:
it fires exactly where the source text was ambiguous and you did not notice.

**See** [drafting-patterns.md](../drafting-patterns.md), "Layout expresses scope even where the
operator is associative", for the companion case — where the operands include inert strings, moving a
line's depth leaves the truth value untouched and changes the _law_ the file states instead, so
neither a diagnostic nor a test will catch it;
<https://legalese.com/l4/reference/operators/README.md>.
