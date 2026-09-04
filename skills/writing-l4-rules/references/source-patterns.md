# From the words on the page to L4: a phrasebook

Keyed on **what the source text says**. [drafting-patterns.md](drafting-patterns.md) is keyed on the
L4 shape — reach for that one when you know which shape you want; reach for this one when you are
looking at a sentence of statute or contract and do not.

Each entry has five parts:

- **If the source says** — the drafting phrase, with a real quotation from the encoded corpus in
  this repository and its file and line.
- **It is doing** — the legal job the phrase performs, in a sentence or two. Most encoding mistakes
  are here, not in the syntax: the same word (`means`, `refuses`, `prescribed`) does two different
  jobs in two different places.
- **Write** — the L4 pattern. Every snippet on this page was run before it went in.
- **Not** — the shape a model reaches for first, and why it is wrong.
- **See** — where the shape is treated at length.

**How this phrasebook is laid out.** The entries live in eleven area files under
[source-patterns/](source-patterns/), one file per area, and this page is the index: each area
below links to its file and lists **every** entry in it. Entries are numbered _area_._entry_, so 4.3
is the third entry of area 4, and each one has a stable anchor of the form `#e4-3`. **Area 11, when
the encoding cannot answer, is sequestered last on purpose** — `REFUSE` is obscure enough that you
could encode a dozen laws or contracts and never use it, so it is kept out of the way of the ten
areas you will use every day. An entry's title quotes the drafting phrase itself, so a contract's
**"WHEREAS"** and a statute's "unless the context otherwise requires" appear below in the source's
own words rather than under an L4 name.

**This index is generated from the area files, and it is complete.** An earlier version of it listed
25 of the entries that existed and marked three areas "entries to come" when those areas were fully
written; a trial encoder navigating from it skipped the three areas the contract in front of them
most needed. If you add an entry to an area file, add its line here in the same change.

## What is new, and what is not here yet

**New in this release.**

- The **section `GIVEN`** — a `GIVEN` indented under a `§` heading, declaring an input that every
  rule in that section reads without re-declaring it. A `GIVEN` at column 1 is unchanged: it is the
  signature of the one declaration below it, a **rule `GIVEN`**. Indentation is the whole
  difference.
- **`REFUSE "message"`** — an expression at any type that stops the evaluation and says why. Nothing
  downstream can catch it; only the boundary (the directive, the command line, the application
  programming interface, the web form) sees it. That guarantee is about a refusal something
  **forces**: evaluation is lazy, so a refusal you store inside a value instead of returning may
  never run at all, and the caller gets an ordinary answer.
  [Entry 11.8](source-patterns/11-when-the-encoding-cannot-answer.md#e11-8) measures both halves.
  `TBD`, from the prelude, is the refusal that means "not written yet".
- **`ASSUME` is deprecated for declaring inputs, and still works.** It parses, type-checks and
  exports exactly as before, and emits no warning. Write new inputs as a record parameter or a
  section `GIVEN`; see
  [entry 11.7](source-patterns/11-when-the-encoding-cannot-answer.md#e11-7) for migrating an old one.

**Proposed, not landed (2026-09-04). Do not write these.**

- Supplying a **section `GIVEN`** or an `ASSUME`d name from inside the file, at a directive or at
  a call in a body: `` #EVAL f WITH `the reading` IS `the strict reading` ``.
  What `WITH` can name today is a rule's **own** inputs, so `#EVAL f WITH x IS 25` works where
  `f` is `GIVEN x …`; naming anything that is not one of the rule's own inputs is a check error,
  not a parse error (the rule's real inputs are reported unsupplied, and the name you wrote is
  reported undefined). A parse error, `unexpected WITH`, is what you get only when a positional
  value precedes the `WITH`, as in ``#EVAL `tax on` 100 WITH rate IS 0.2``. Section-`GIVEN`
  values are supplied from outside: a web form, `l4 batch FILE --inputs cases.json`, or the
  service request.
- Discharge — the compiler working out which inputs an entry point actually reads and asking for
  exactly those.
- `TYPICALLY` as a default the caller may omit. Today it is metadata: the input is still required.
- A dedicated `SUBJECT TO` / `NOTWITHSTANDING` construct. **Neither is a keyword** — there is no
  token for either in the lexer.
  [Entry 2.2](source-patterns/02-conditions-and-logic.md#e2-2) says what to write instead.
- Per-backend handling of a refusal in the export targets.

## The distinction that decides half of these entries

> **"The law does not apply, or is not in force" is the law's own answer, and stays an ordinary
> value or gate. "The model does not cover this" is the encoder's answer, and is a refusal.**

The first is determinate, and the law provides for it: savings and transitional provisions reach
back into exactly that period, so something must be there for them to reach. The second is a
recusal — the encoder declines, no party may read the decline as a decision in their favour, and the
matter goes to another bench. A refusal is unreachable by construction, so **if you find yourself
wanting a savings provision to reach past a `REFUSE`, the `REFUSE` was wrong.**

---

## The eleven areas

### 1. Definitions and scope

[source-patterns/01-definitions-and-scope.md](source-patterns/01-definitions-and-scope.md)

- **1.1** ["In this Act, X means Y" — the term the text fixes](source-patterns/01-definitions-and-scope.md#e1-1)
- **1.2** ["the grantee", "the personal representative" — the role the case fills](source-patterns/01-definitions-and-scope.md#e1-2)
- **1.3** ["a person ('P')", "(the 'Purchaser')" — the parenthetical label](source-patterns/01-definitions-and-scope.md#e1-3)
- **1.4** ["For the purposes of this section, X means …" — the same word, defined twice](source-patterns/01-definitions-and-scope.md#e1-4)
- **1.5** ["unless the context otherwise requires", and a provision two readings are open on](source-patterns/01-definitions-and-scope.md#e1-5)
- **1.6** ["… under section 9", where section 9 is not in the slice you are encoding](source-patterns/01-definitions-and-scope.md#e1-6)
- **1.7** ["In this Agreement, 'Effective Date' means 1 January 2026" — the contract's own definitions clause](source-patterns/01-definitions-and-scope.md#e1-7)
- **1.8** ["'Funding portal' means a broker … that does not …" — the definition with a condition inside it](source-patterns/01-definitions-and-scope.md#e1-8)
- **1.9** ["has the meaning given by Article 6", "within the meaning of section 3" — the definition that points elsewhere](source-patterns/01-definitions-and-scope.md#e1-9)
- **1.10** ["specified in the Schedule" — the definition that lives in a Schedule](source-patterns/01-definitions-and-scope.md#e1-10)
- **1.11** [A defined term used in clause 2 and defined in clause 12](source-patterns/01-definitions-and-scope.md#e1-11)
- **1.12** ["In this Act" against "In this Part" — the same word at two scopes](source-patterns/01-definitions-and-scope.md#e1-12)
- **1.13** [Where the illustrations live](source-patterns/01-definitions-and-scope.md#e1-13)

### 2. Conditions and logic

[source-patterns/02-conditions-and-logic.md](source-patterns/02-conditions-and-logic.md)

- **2.1** ["This section does not apply where …" — the gate and the exemption](source-patterns/02-conditions-and-logic.md#e2-1)
- **2.2** ["Subject to section N", "Notwithstanding anything in this Act"](source-patterns/02-conditions-and-logic.md#e2-2)
- **2.3** ["if …", "where …", "in any case where …" — the ordinary condition](source-patterns/02-conditions-and-logic.md#e2-3)
- **2.4** ["No will shall be valid unless it is in writing" — the "unless" that is a requirement](source-patterns/02-conditions-and-logic.md#e2-4)
- **2.5** ["provided that", "provided, however, that" — two jobs, and the second reorders your arms](source-patterns/02-conditions-and-logic.md#e2-5)
- **2.6** ["any of the following", "all of the following" — the chapeau and its numbered limbs](source-patterns/02-conditions-and-logic.md#e2-6)
- **2.7** ["includes", "including but not limited to", "or other similar circumstance"](source-patterns/02-conditions-and-logic.md#e2-7)
- **2.8** ["and" — the conjunction and the union](source-patterns/02-conditions-and-logic.md#e2-8)
- **2.9** ["either … or", "either, but not both", "both … and"](source-patterns/02-conditions-and-logic.md#e2-9)
- **2.10** [Numbered rules read in order — `BRANCH` as the first-match ladder](source-patterns/02-conditions-and-logic.md#e2-10)
- **2.11** ["(a) X; (b) Y; and (c) Z, or (d) W" — the list that mixes "and" with "or"](source-patterns/02-conditions-and-logic.md#e2-11)

### 3. Quantities and calculation

[source-patterns/03-quantities-and-calculation.md](source-patterns/03-quantities-and-calculation.md)

- **3.1** ["such other amount as may be prescribed" — the power, exercised](source-patterns/03-quantities-and-calculation.md#e3-1)
- **3.2** ["2% of the value", "a fee of $50" — a rate and an amount](source-patterns/03-quantities-and-calculation.md#e3-2)
- **3.3** ["not less than", "exceeds", "at least", "not more than" — the boundary](source-patterns/03-quantities-and-calculation.md#e3-3)
- **3.4** ["the lesser of", "the greater of", "whichever is the higher"](source-patterns/03-quantities-and-calculation.md#e3-4)
- **3.5** ["the aggregate of", "the sum of", "taken together with"](source-patterns/03-quantities-and-calculation.md#e3-5)
- **3.6** ["where the amount exceeds X but does not exceed Y" — thresholds, bands and rate tables](source-patterns/03-quantities-and-calculation.md#e3-6)
- **3.7** ["whichever is greater, but not exceeding" — a floor and a cap](source-patterns/03-quantities-and-calculation.md#e3-7)
- **3.8** ["rounded down to the nearest dollar" — and the rounding L4 does not do](source-patterns/03-quantities-and-calculation.md#e3-8)
- **3.9** ["the number of" — counting, and who does the counting](source-patterns/03-quantities-and-calculation.md#e3-9)
- **3.10** ["$25,000", "$2.5 billion" — money, and figures too large to type](source-patterns/03-quantities-and-calculation.md#e3-10)
- **3.11** ["15% per annum", pro rata — the rate whose period lives in its name](source-patterns/03-quantities-and-calculation.md#e3-11)
- **3.12** [The prelude names the arithmetic in this area needs](source-patterns/03-quantities-and-calculation.md#e3-12)

### 4. Dates and periods

[source-patterns/04-dates-and-periods.md](source-patterns/04-dates-and-periods.md)

- **4.1** ["This Act comes into force on …", "applies to a death on or after …"](source-patterns/04-dates-and-periods.md#e4-1)
- **4.2** ["Nothing in this Act shall affect …", "continues to apply" — savings and transitional](source-patterns/04-dates-and-periods.md#e4-2)
- **4.3** ["within 14 days after the change" — the deadline whose unit only you know](source-patterns/04-dates-and-periods.md#e4-3)
- **4.4** ["not less than 14 days nor more than 60 days after publication" — the window](source-patterns/04-dates-and-periods.md#e4-4)
- **4.5** ["on or before", "beginning with the day", "not later than" — the boundary days](source-patterns/04-dates-and-periods.md#e4-5)
- **4.6** ["at the time of", "as at the date of" — a status frozen at an instant](source-patterns/04-dates-and-periods.md#e4-6)
- **4.7** ["the law in force at the time", "as at 1 June 2023" — the rule-version axis](source-patterns/04-dates-and-periods.md#e4-7)
- **4.8** ["as amended by", "substituted by" — an amendment that changes the shape](source-patterns/04-dates-and-periods.md#e4-8)
- **4.9** ["within 6 calendar months", "the first anniversary" — periods of months and years](source-patterns/04-dates-and-periods.md#e4-9)
- **4.10** ["within five business days", "a calendar month" — the unit with a calendar behind it](source-patterns/04-dates-and-periods.md#e4-10)
- **4.11** ["a grace period of ten days" — the second deadline](source-patterns/04-dates-and-periods.md#e4-11)
- **4.12** [The `daydate` names this area uses, and how to find the rest](source-patterns/04-dates-and-periods.md#e4-12)

### 5. Duties, powers and consequences

[source-patterns/05-duties-powers-consequences.md](source-patterns/05-duties-powers-consequences.md)

- **5.1** ["may be granted", "may be made", "may be revoked" — the passive `may`](source-patterns/05-duties-powers-consequences.md#e5-1)
- **5.2** ["shall", "must" — the duty, and the "must" that is only a condition](source-patterns/05-duties-powers-consequences.md#e5-2)
- **5.3** ["must not", "shall not", "no person shall" — the prohibition](source-patterns/05-duties-powers-consequences.md#e5-3)
- **5.4** ["the court may", "the tenant may terminate" — the active permission](source-patterns/05-duties-powers-consequences.md#e5-4)
- **5.5** ["is entitled to", "is not required to", "it shall not be necessary"](source-patterns/05-duties-powers-consequences.md#e5-5)
- **5.6** ["if P fails to do so, P must …" — the reparation that follows a breach](source-patterns/05-duties-powers-consequences.md#e5-6)
- **5.7** ["commits an offence and is liable to a fine not exceeding $1,000"](source-patterns/05-duties-powers-consequences.md#e5-7)
- **5.8** ["by giving five business days' notice" — the notice, and the period it opens](source-patterns/05-duties-powers-consequences.md#e5-8)
- **5.9** ["shall …", with no time stated](source-patterns/05-duties-powers-consequences.md#e5-9)
- **5.10** ["termination for breach" — the breach is a fact, the remedy is the duty](source-patterns/05-duties-powers-consequences.md#e5-10)
- **5.11** [Reading a duty back: the `#TRACE` event block](source-patterns/05-duties-powers-consequences.md#e5-11)

### 6. Parties and things

[source-patterns/06-parties-and-things.md](source-patterns/06-parties-and-things.md)

- **6.1** ["the Company shall pay the Contractor" — two parties, one act](source-patterns/06-parties-and-things.md#e6-1)
- **6.2** ["the notice must contain the following particulars" — a record, one field per limb](source-patterns/06-parties-and-things.md#e6-2)
- **6.3** ["a person", "a body corporate" — one type with alternatives, not two flags](source-patterns/06-parties-and-things.md#e6-3)
- **6.4** ["each of", "every", "all of the following persons" — `all` over a list](source-patterns/06-parties-and-things.md#e6-4)
- **6.5** ["any of", "one or more of", "at least one" — `any` over a list](source-patterns/06-parties-and-things.md#e6-5)
- **6.6** ["the same person" — identity is a field you compare, never the whole record](source-patterns/06-parties-and-things.md#e6-6)
- **6.7** ["the following persons in the following order" — rank, then filter to the best rank](source-patterns/06-parties-and-things.md#e6-7)
- **6.8** ["residents of New York and New Jersey may apply" — the "and" that is a union](source-patterns/06-parties-and-things.md#e6-8)
- **6.9** ["the Registrar", "the Minister", "the court" — an office is a party, a name is not](source-patterns/06-parties-and-things.md#e6-9)
- **6.10** [The named case, and the helper that builds one — mixfix segments may open with punctuation](source-patterns/06-parties-and-things.md#e6-10)

### 7. Presumptions and defaults

[source-patterns/07-presumptions-and-defaults.md](source-patterns/07-presumptions-and-defaults.md)

- **7.1** ["shall be deemed to be", "shall be treated as"](source-patterns/07-presumptions-and-defaults.md#e7-1)
- **7.2** ["unless the contrary is shown", "until the contrary is proved"](source-patterns/07-presumptions-and-defaults.md#e7-2)
- **7.3** ["in the absence of agreement", "unless otherwise agreed" — a value the parties may displace](source-patterns/07-presumptions-and-defaults.md#e7-3)
- **7.4** [`TYPICALLY` — what it does today, and what it does not](source-patterns/07-presumptions-and-defaults.md#e7-4)
- **7.5** ["no presumption shall arise" — a definition carrier, not a boolean](source-patterns/07-presumptions-and-defaults.md#e7-5)
- **7.6** ["no will shall be revoked by any presumption" — abolishing a doctrine](source-patterns/07-presumptions-and-defaults.md#e7-6)
- **7.7** ["may be varied by the will", "subject to any contrary direction" — the default a whole rule sits under](source-patterns/07-presumptions-and-defaults.md#e7-7)

### 8. Judgement and discretion

[source-patterns/08-judgement-and-discretion.md](source-patterns/08-judgement-and-discretion.md)

- **8.1** ["may reasonably be regarded as", "of a like nature" — the open standard](source-patterns/08-judgement-and-discretion.md#e8-1)
- **8.2** ["if satisfied on reasonable grounds that" — record who was satisfied](source-patterns/08-judgement-and-discretion.md#e8-2)
- **8.3** ["has a reasonable basis for believing", "reasonably designed", "in the exercise of reasonable care" — whose belief?](source-patterns/08-judgement-and-discretion.md#e8-3)
- **8.4** ["in the opinion of the Registrar", "if the court is satisfied" — a determination is a record, not a flag](source-patterns/08-judgement-and-discretion.md#e8-4)
- **8.5** ["in its sole discretion", "as the court thinks fit" — say who is eligible, do not pick](source-patterns/08-judgement-and-discretion.md#e8-5)
- **8.6** ["for any sufficient reason", "may in a particular case direct otherwise" — compute the default, not the discretion](source-patterns/08-judgement-and-discretion.md#e8-6)
- **8.7** ["the Company may, in its reasonable opinion, reject" — the discretion that is also a power](source-patterns/08-judgement-and-discretion.md#e8-7)

### 9. Text that is not a rule

[source-patterns/09-text-that-is-not-a-rule.md](source-patterns/09-text-that-is-not-a-rule.md)

- **9.1** ["[Repealed]" — a section number with nothing under it](source-patterns/09-text-that-is-not-a-rule.md#e9-1)
- **9.2** ["WHEREAS:", "The parties wish to record" — recitals](source-patterns/09-text-that-is-not-a-rule.md#e9-2)
- **9.3** ["The purpose of this Act is …" — long titles, preambles, purpose clauses](source-patterns/09-text-that-is-not-a-rule.md#e9-3)
- **9.4** [Headings, part titles and marginal notes](source-patterns/09-text-that-is-not-a-rule.md#e9-4)
- **9.5** ["Note:", "for information only", explanatory notes](source-patterns/09-text-that-is-not-a-rule.md#e9-5)
- **9.6** ["Without prejudice to section 12, …"](source-patterns/09-text-that-is-not-a-rule.md#e9-6)
- **9.7** [Governing law, entire agreement, notices — the back-of-the-contract boilerplate](source-patterns/09-text-that-is-not-a-rule.md#e9-7)
- **9.8** [A Schedule that is prose](source-patterns/09-text-that-is-not-a-rule.md#e9-8)
- **9.9** [Whatever you carried — pin it](source-patterns/09-text-that-is-not-a-rule.md#e9-9)

### 10. "For the avoidance of doubt"

[source-patterns/10-for-the-avoidance-of-doubt.md](source-patterns/10-for-the-avoidance-of-doubt.md)

- **10.1** ["For the avoidance of doubt, X" — the declaratory case](source-patterns/10-for-the-avoidance-of-doubt.md#e10-1)
- **10.2** [The same clause, when the assertion fails](source-patterns/10-for-the-avoidance-of-doubt.md#e10-2)
- **10.3** ["Nothing in this clause prevents …", "Nothing in this Act shall affect …"](source-patterns/10-for-the-avoidance-of-doubt.md#e10-3)
- **10.4** ["It is declared that …", "This clause is without prejudice to clause 12"](source-patterns/10-for-the-avoidance-of-doubt.md#e10-4)
- **10.5** [When the clause is about a fact you take as an input](source-patterns/10-for-the-avoidance-of-doubt.md#e10-5)

### 11. When the encoding cannot answer

[source-patterns/11-when-the-encoding-cannot-answer.md](source-patterns/11-when-the-encoding-cannot-answer.md)

- **11.1** ["The Minister may by regulations prescribe …" — the power, not exercised](source-patterns/11-when-the-encoding-cannot-answer.md#e11-1)
- **11.2** ["[amount to be inserted]", a clause not yet drafted](source-patterns/11-when-the-encoding-cannot-answer.md#e11-2)
- **11.3** ["…, if any", "where there is no …"](source-patterns/11-when-the-encoding-cannot-answer.md#e11-3)
- **11.4** ["must be a positive number", a date that does not exist — invalid input](source-patterns/11-when-the-encoding-cannot-answer.md#e11-4)
- **11.5** [Scope this encoding deliberately does not cover](source-patterns/11-when-the-encoding-cannot-answer.md#e11-5)
- **11.6** [Testing a refusal](source-patterns/11-when-the-encoding-cannot-answer.md#e11-6)
- **11.7** [Migrating an existing `ASSUME`](source-patterns/11-when-the-encoding-cannot-answer.md#e11-7)
- **11.8** [A refusal only refuses when something forces it](source-patterns/11-when-the-encoding-cannot-answer.md#e11-8)
- **11.9** [Exercising a rule that reads a section `GIVEN`](source-patterns/11-when-the-encoding-cannot-answer.md#e11-9)
- **11.10** ["such amount as the parties may agree", "on terms to be agreed"](source-patterns/11-when-the-encoding-cannot-answer.md#e11-10)
- [The questions to ask, in order](source-patterns/11-when-the-encoding-cannot-answer.md#e11-questions)

---

**Numbering.** These entries were one flat run of 25 until 2026-09-04, when they became eleven
areas. Every cross-reference inside the phrasebook, in `SKILL.md` and in `regulative.md` now names
the new _area_._entry_ number; the old-to-new table that stood here has been removed because nothing
uses it any more. If you meet an "entry 17" anywhere, it predates the split and the mapping is in
`scratchpad/docs/cookbook-map.md`.
