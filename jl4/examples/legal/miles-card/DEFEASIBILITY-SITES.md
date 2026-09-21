# Defeasibility sites in the miles-card corpus

A register of every place in this corpus where a native defeasibility construct would have collapsed several hand-written guards into one rule.

Compiled 2026-09-21 from the `DEFEASIBILITY SITES` comment block at the foot of each issuer module, as those blocks stand after the second encoding pass.
It answers spec §4.5 of `SPEC-miles-card-l4-encoding.md` in `mengwong/homelab` at `docs/projects/miles-card/`, which asks for this list and says why: "That list is a requirements document for the construct, derived from a real text, sized to two PDFs instead of a statute book."

## What this list is, and what it is not

**It is a requirements document for a language feature.**
Each entry names a place where the shape of the source text and the shape of the L4 that encodes it came apart, and says what a construct would have recovered.
The closing classification is the actual input to a design: it says which shapes recur, how often, and what each one asks for, which is not the same question as which site was hardest to write.

**It is not a bug list.**
A site is not a defect.
Every module in this corpus type-checks and every assertion in it passes; the sites record a cost paid in legibility and in reviewability, not a wrong answer.
Two entries do mention defects, because the flattening caused them — the CHAGEE rule at yuu SITE 3, which could never fire, and HSBC SITE 2's carve-back, which now has no rule at it — and both were found and fixed or pinned in the second pass.
Defects found while encoding are recorded in the second-pass reports, not here.

**It is not the fork register.**
A fork is a place where the held document admits two readings and the encoding takes one.
A site is a place where the document is clear and the *encoding* could not say it the way the document says it.
The two overlap at SHAPE E below, where the document contradicts itself, and those entries are cross-referenced rather than restated.
`dbs-yuu.l4` carries the only in-module `FORKS` block in the corpus.

**It is not a list of places L4 refused to compile.**
Nothing here failed to lower.
Every one of these encodings works; the complaint is about what a reader auditing the encoding against the PDF has to do.

## The toolchain measurement

Measured 2026-09-21 in this worktree, at `04319ed13`, and it goes slightly further than the spec's own measurement, which covered `jl4/src` only.

`DESPITE`, `SUBJECT TO`, `NOTWITHSTANDING`, `defeasible` and `OVERRIDES` have **zero** occurrences in `jl4/src`, which reproduces the spec's figure.
In `jl4-core/src` they are not zero, and it is worth saying what they are, because the count alone would read as a contradiction.
Every occurrence is in a *backend*, describing a downstream target's defeasibility rather than L4's own: `defeasible` is 16 hits, all in `L4/Blawx/`, where `brDefeasible` mirrors Blawx's own checkbox; `OVERRIDES` is 4, three of them Blawx's `ORDER_OVERRIDES` operator-precedence constant and one a comment; `SUBJECT TO` is 7, all lowercase prose or Blawx's `subject to applicability` field; `DESPITE` is 1, an ordinary English word in a comment in `L4/Catala/IR.hs`.
`NOTWITHSTANDING` is zero everywhere.

The Blawx field is not a counter-example to the claim, it sharpens it.
`L4/Blawx/Lower.hs:1532` writes `brDefeasible = False` unconditionally, and `L4/Blawx/IR.hs:594` says why in terms: "Mode A (v1): 'brDefeasible' is always 'False' — the checkbox states the truth, no defeat rules exist."
The only path that can set it `True` is `L4/Blawx/Parse.hs:448`, which reads a workspace someone else authored.
So L4 can *recognise* defeasibility in a foreign format it imports and cannot *express* it in its own surface syntax, which is the gap this register is about.

## How to read an entry

Each entry gives four things, in this order.

**Clause** — the provision in the issuer's document, cited as the module cites it.
**Shape in the text** — a one-line label from the classification in the closing section, followed by a brief quote.
**L4 shape used instead** — the rule or rules that carry it, named, so the entry can be checked against the module.
**Bought** — what a native construct would have recovered, in one sentence, taken from the encoder's own entry rather than restated more strongly.

Modules appear in corpus order.
Every site keeps the number its module gave it, including the `2a` and `3a` that the second pass inserted into `dbs-yuu.l4` rather than renumbering around.

---

# 1. `dbs-yuu.l4` — 8 sites

Block at `dbs-yuu.l4:1507`.
The first pass recorded 6; the second pass added SITE 2a and SITE 3a and added paragraphs to SITE 2 and SITE 3.

### SITE 1 — cl.6 general rule, defeated by cl.9's Eligible Spend exclusions

**Clause.** cl.6 (`§§ 6 — Base Rewards`) read against cl.9 (`§§ 9 — Eligible Spend`).
**Shape in the text.** SHAPE A, general rule plus exception list: cl.6 awards Base Rewards on every S$1 at a listed Spend Category, and cl.9 then carves out six classes (a) to (f), plus a description list (i), plus DBS's open discretion (ii).
**L4 shape used instead.** `the Base Rewards points per dollar` opens with a guard `IF NOT (the transaction is Eligible Spend) THEN 0`, so the exception is evaluated before the rule it defeats and the general rule is written as the `OTHERWISE` arm.
The reader meets the exceptions first and the rule last, which is the reverse of the document's order, and the conjunction of seven negations is flatter than the text, which reads as one definition with a list hanging off it.
**Bought.** cl.6 stated once as itself, with cl.9 attached as a defeater, preserving the document's order and letting the two be cited separately.

### SITE 2 — cl.9(f) and cl.9(i), a general exclusion defeated by a start date

**Clause.** cl.9(f) and cl.9(i) (`§§ 9 — Eligible Spend`).
**Shape in the text.** SHAPE B, a dated row inside an undated list: one MCC table in which fourteen rows carry an asterisk meaning "*With effect from 1 May 2026", and one description list in which two of nineteen entries are date-stamped the same way.
**L4 shape used instead.** Each list is split in two — `cl.9(f) excludes the MCC at all times` beside `cl.9(f) excludes the MCC from 1 May 2026`, and `cl.9(i) lists a pattern the transaction carries at all times` beside `cl.9(i) lists a pattern the transaction carries from 1 May 2026` — and the caller ORs them with a date comparison.
The document's single table becomes two rules that must be kept in step by hand, and a row moved between them is a silent error.
**Bought.** One table, one row per MCC, with the effective date as an attribute of the row rather than as its address.
This is the one entry in the corpus where the encoder records something actually lost rather than merely made harder to read: splitting by date forces the split to be the list's address, so an entry cannot sit in both halves, and cl.9(i)'s AXS family holds two undated terms and one dated one, so one had to be dropped.

### SITE 2a — cl.9(c) and cl.9(d) overlap, and the encoding cannot say so

**Clause.** cl.9(c) and cl.9(d) (`§§ 9 — Eligible Spend`).
**Shape in the text.** SHAPE H, defeasible in form with the gap in the fact model: cl.9(c) excludes "My Preferred Payment Plan ("MP3") monthly transactions" and cl.9(d) excludes "0% interest-free Instalment Payment Plan ("IPP") transaction(s)", two named products in two limbs.
**L4 shape used instead.** Both are `Instalment plan transaction`, one domain constructor, so `cl.9(d) excludes the transaction` is a strict subset of `cl.9(c) excludes the transaction` and fires on exactly the same postings.
Both rules are written anyway, because a reader checking cl.9(d) should find a rule called cl.9(d), and the cost is that the citation cannot say which limb excluded a given posting.
**Bought.** Nothing, and the entry says so: this is a domain question rather than a defeasibility one, and two constructors would fix it at the price of asking a cardholder to know whether their instalment plan was MP3 or IPP.

### SITE 3 — cl.8 Participating Merchants, defeated by Appendix 1 per merchant

**Clause.** cl.8 (`§§ 8 — Participating Merchants`) read against Appendix 1 (`§§ Appendix 1 — merchant-specific exclusions`).
**Shape in the text.** SHAPE A, general rule plus exception list: cl.8 lists eleven Participating Merchants and says in terms that it "excludes products listed in Appendix 1", and Appendix 1 then gives each merchant its own exclusion block, separately headed for Base, for Bonus, and for both.
**L4 shape used instead.** Two hand-written predicates, `Appendix 1 denies Base Rewards` and `Appendix 1 denies Bonus Rewards`, each an OR-chain of merchant-specific conditions consulted as an early guard.
The Appendix's per-merchant structure is flattened into two lists keyed by which reward the exclusion bites, so a reader checking one merchant against the document must visit both predicates.
**Bought.** One block per merchant, mirroring the Appendix's own layout, each defeating cl.8 for that merchant only.
This site has already cost one defect: the CHAGEE row is a positive condition among exclusions, and its rule was written to run off the cl.8 test, which carries cl.8's own "made in Singapore" gate, so the rule read "at CHAGEE as a Participating Merchant, and not in Singapore" and could never fire — found and fixed in the second pass.

### SITE 3a — Appendix 1's SimplyGo row, unencodable on the facts held

**Clause.** Appendix 1, SimplyGo (`§§ Appendix 1 — merchant-specific exclusions`).
**Shape in the text.** SHAPE H, defeasible in form with the gap in the fact model: "Applicable to Base and Bonus Rewards: Points will not be awarded for Top-Up transactions."
**L4 shape used instead.** Nothing.
A top-up and a ride arrive as the same merchant, the same description family and the same charge kind, so no rule can separate them, and the nearest charge kind that would is already spent by cl.9(c) and would make the rule vacuous.
The row reaches the caller as a `conditions` sentence, and an assertion pins the divergence so that it fails the day the fact arrives.
**Bought.** Nothing: this is a missing fact, not a missing construct, and the honest fix is in the domain.

### SITE 4 — Appendix 1's 7-Eleven row, an exception defeated in turn by a date

**Clause.** Appendix 1, 7-Eleven (`§§ Appendix 1 — merchant-specific exclusions`).
**Shape in the text.** SHAPE C, an exception to an exception: bonus is denied on the American Express, and then restored "With effect from 13 Aug 2026" by the next sentence of the same cell.
**L4 shape used instead.** A three-way conjunction inside one OR-arm of `Appendix 1 denies Bonus Rewards` — merchant AND card AND date-before.
The restoration is encoded only as the negation of the denial's date limb, and there is no rule anywhere that says "Amex earns at 7-Eleven from 13 Aug 2026", though that is what the document says.
**Bought.** A two-level defeat — cl.7(a) defeated by the Amex exclusion, itself defeated by the 13 Aug 2026 restoration — with each level citable, which is how the cell reads.

### SITE 5 — Appendix 1's closing sentence, a cross-cutting defeater

**Clause.** Appendix 1, closing sentence, read over cl.7 (`§§ 7 — Bonus Rewards`).
**Shape in the text.** SHAPE D, a cross-cutting defeater: "DBS will not award Bonus Rewards on transactions that do not earn Base Rewards from yuu/Participating Merchants, unless otherwise stated."
One sentence conditions every bonus rule in the document on the outcome of every base rule, and then reopens itself with "unless otherwise stated".
**L4 shape used instead.** The first guard of `the Bonus Rewards points per dollar` re-invokes `the Base Rewards points per dollar` and tests it for zero.
The bonus computation therefore depends on the base computation as a value, which is an implementation of the sentence rather than a statement of it, and the "unless otherwise stated" escape is not represented at all.
**Bought.** The sentence written once, at module scope, as a defeater over the whole bonus layer, with somewhere to hang its own exception.

### SITE 6 — Appendix 1's Singtel row against cl.8, a contradiction rather than an exception

**Clause.** cl.8 (`§§ 8 — Participating Merchants`) against Appendix 1, Singtel.
**Shape in the text.** SHAPE E, a contradiction: cl.8 lists Singtel as a Participating Merchant, Appendix 1 denies Base Rewards on "all transactions" at it, and the same Appendix cell then lists three categories excluded from "Base and Bonus", which have no work to do if no base is ever earned.
**L4 shape used instead.** The denial wins, the closing sentence carries it into the bonus, and the answer is marked `Unconfirmed` with the contradiction spelled out in `conditions`.
The encoding must pick, and it picks the lower answer.
**Bought.** The ability to record that two provisions of one document are in conflict and let the conflict surface, which is the property spec §2 wants from Catala's default calculus, rather than resolving it by fiat inside a `BRANCH` and reporting the fact in prose.

---

# 2. `dbs-womans-world.l4` — 6 sites

Block at `dbs-womans-world.l4:1068`.
The second pass kept all six and rewrote SITE 2 and SITE 6, whose `L4 SHAPE` paragraphs had become false.

### SITE 1 — cl.11, the eight-limb exclusion list

**Clause.** cl.11 (`§§ 11. Definitions and Exclusion, Online spend`).
**Shape in the text.** SHAPE A, general rule plus exception list: "Online spend refers to retail transaction ... made via the Internet ...", immediately qualified by "excluding the following transactions: (i) ... (viii)".
One general norm, eight defeaters, and limb (viii) is open-ended.
**L4 shape used instead.** `clause 11 excludes the transaction from online spend`, a `BRANCH` of eight arms each delegating to a named limb rule, consumed by `the transaction is online spend` as `flagged AND NOT (excluded)`.
The general rule and its defeaters are two rules that must be read together, and the reader has to hold the polarity inversion in their head.
**Bought.** One rule stating the general norm with eight `SUBJECT TO` limbs attached at the point of statement, in the document's order, with no hand-written negation and no second rule to keep in step.
The priority order is currently carried only by `BRANCH`'s first-match semantics, which is an implementation detail standing in for a legal one.

### SITE 2 — cl.11 Table 1 and Table 2, the two enumerated defeaters

**Clause.** cl.11, Tables 1 and 2 (`§§ 11. Definitions and Exclusion, Online spend`).
**Shape in the text.** SHAPE A, general rule plus exception list, at scale: 57 MCCs and 90 transaction terms, revised by the issuer at will.
**L4 shape used instead.** The two tables are now encoded differently, which the entry records as a finding in itself.
Table 1 is an OR chain of 57 numeric disjuncts generated from the source text by a script, and must be regenerated whenever DBS republishes.
Table 2 is 19 `elem` tests over the shared domain's `Description pattern` enumeration, the 90 printed terms having been read once into 19 families, with the string matching that decides which families a statement line carries happening in layer 1 rather than here.
**Bought.** For Table 1, an exception declared over a SET literal rather than a disjunction, so the list is data the rule cites rather than logic the rule is made of, and so two issuers' lists could be compared.
Table 2 has most of that already, at a different cost: the mapping from 90 printed terms to 19 families is a judgement made once, recorded in a comment beside the rule, and checkable only by reading it.

### SITE 3 — cl.11(viii) read with cl.3, cl.5 and cl.7, the issuer's open discretion

**Clause.** cl.11(viii) with cl.3, cl.5 and cl.7 (`§§ 11. Definitions and Exclusion, Online spend`).
**Shape in the text.** SHAPE F, an open defeater that cannot be enumerated: "any other transactions determined by DBS from time to time", alongside DBS's power to vary or terminate without notice, to make a final decision, and to postpone awarding.
Four open-ended discretions that defeat any answer, none with a stated trigger, one of them purporting to defeat the *review* of the answer rather than the answer.
**L4 shape used instead.** `clause 11 viii, DBS has otherwise determined the transaction to be excluded` returns `FALSE`, plus condition strings on the answer.
The discretion is visible in the rule list but has no effect, which the entry calls the most honest thing a total function can do with it.
**Bought.** A defeater that is declared and undischarged — an answer stamped "defeasible by cl.11(viii), cl.3, cl.5, cl.7" as a first-class part of its type, rather than as prose in a list of strings that nothing checks.

### SITE 4 — cl.12, excluding by reference to a document this corpus does not hold

**Clause.** cl.12 (`§§ 12. Definitions and Exclusion, Overseas spend`).
**Shape in the text.** SHAPE F, an open defeater that cannot be read: "excluding transactions which are excluded from the awarding of DBS Points as set out in the DBS Rewards Programme Terms and Conditions."
**L4 shape used instead.** The exception is not encoded at all, because it cannot be — the text that states it is not held — and a condition string says so.
cl.6 does the same thing for the whole document.
**Bought.** An exception site that can be named and left open, so that "this rule has a known unenumerated defeater" is a fact the type system carries rather than a sentence in a list.
This is the incorporation-by-reference case, and the entry calls it the one where the difference between "no exception applies" and "the exception cannot be read" is worth money.

### SITE 5 — cl.11's definition against cl.13's determination

**Clause.** cl.11 against cl.13 (`§§ 13 and 14. How DBS determines an online transaction, and the transaction date`).
**Shape in the text.** SHAPE E, a contradiction by displacement: cl.11 defines online spend by the cardholder's act ("made via the Internet") and cl.13 says DBS determines it by the merchant's indicator, and neither is stated as an exception to the other.
**L4 shape used instead.** cl.13 wins by construction — no rule in this module reads `payment channel` or `credential`.
The displacement is recorded in a comment and in the illustrations, and it is invisible in the rules.
**Bought.** The ability to write cl.11 as drafted and then let cl.13 override it, so the encoding contains both clauses and states which governs, instead of containing one clause and a comment about the other.
A reader auditing this file against the document currently finds cl.11's "via the Internet" nowhere in the code.

### SITE 6 — cl.15 and cl.20, the two products in one document

**Clause.** cl.15 and cl.20 (`§§ 15 to 19. DBS Woman's World Card, 10X Rewards on Online Spend and 3X Rewards on Overseas Spend` and `§§ 20 to 23. DBS Woman's Card, 5X Rewards on Online Spend, OUT OF SCOPE`).
**Shape in the text.** SHAPE G, scope stated by exception rather than by structure: cl.15 confines cl.16-19 to the Woman's World Card, cl.20 confines cl.21-23 to the Woman's Card, and cl.1-14 govern both.
**L4 shape used instead.** cl.15 as a predicate, `the Woman's World mechanics apply to`, asserted in both directions but not applied; cl.20-23 simply absent.
The first pass applied it as a guard on the exported rule that `REFUSE`d any other card, but `REFUSE` is outside the v1 Catala fragment, so the guard went and the predicate stayed — the encoding now states the scope without enforcing it and relies on the composer to dispatch.
**Bought.** More than it would have before, and something a defeasibility operator does not give: a scope stated as a TYPE, a rule that can only be applied to the card it is scoped to, would survive a lowering that has no notion of refusal, because it would never need to run to refuse.
The entry says in terms that this "is not the shape a DESPITE or SUBJECT TO would give it".

---

# 3. `citi-rewards.l4` — 5 sites

Block at `citi-rewards.l4:1901`.
The second pass kept all five; SITE 1's want shrank and SITE 5's did not, and the contrast between them is the entry that carries the most design information in this module.

### SITE 1 — cl.5, the Qualifying Charge

**Clause.** cl.5 (`§§ 5 — the Qualifying Charge test`).
**Shape in the text.** SHAPE A, general rule plus exception list, already inverted by the draftsman: "A charge ... which does not arise from any: (i) ... (xii)".
The rule is "every charge qualifies", the twelve limbs are the exception list, and the draftsman has folded the exceptions into the definition.
**L4 shape used instead.** `a Qualifying Charge` txn MEANS `NOT (clause 5 excludes this charge txn)`, with the exclusions as a separate OR-chain over two families — a `CONSIDER` on the kind of posting for limbs (i) to (iii), and the exclusion list's two tables for limbs (iv) to (xii).
**Bought.** Little, and the entry is recorded for the opposite reason to the others: the text is already in the shape a defeasible construct produces, so the double negation is faithful.
What changed in the second pass is worth keeping, because it shrank a want rather than satisfying it — the first pass asked for a three-valued answer for limbs known to exist but not testable, and once the domain carried `charge kind` the three limbs became ordinary testable guards, leaving a much smaller residue of GST and the channel a bill payment was made through.

### SITE 2 — cl.6(ii) against its own two exclusions

**Clause.** cl.6(ii) (`§§ 6(ii) — the online limb`).
**Shape in the text.** SHAPE A, general rule plus exception list, inline: "a Qualifying Charge made at an online retail merchant, EXCLUDING mobile wallet and travel-related transactions".
**L4 shape used instead.** One rule with three conjuncts, two of them negated — `clause 6(ii) but for the indicator`, which ANDs the Qualifying Charge test with NOT wallet and NOT travel.
**Bought.** The priority ordering, which is currently invisible: written as `online earns 10X` DESPITE `a mobile wallet does not` DESPITE `travel does not`, a reader sees the general rule and its defeaters as separate statements with a stated precedence, and a reviewer compares three sentences to three sentences.
As conjuncts, the general rule and its exceptions have the same syntactic weight, which is exactly what the source does not say.

### SITE 3 — cl.6(i) against cl.6(ii), and the wallet

**Clause.** cl.6(i) against cl.6(ii) (`§§ 6(i) — the Merchant Category limb`, `§§ 6(ii) — the online limb`, `§§ 6 and 7 — the disjunction`).
**Shape in the text.** SHAPE G, the reach of a defeater stated by its absence: a disjunction where one disjunct carries an exception that the other does not.
The entry calls this the site that motivates the whole module.
**L4 shape used instead.** Two named limbs and an explicit OR, plus a cascade in the top-level `BRANCH` that tries limb (i) first.
**Bought.** Scoped defeaters, so that the asymmetry is a thing on the page rather than a thing a reviewer must fail to find.
Today a reader has to notice that `clause 6(i) — the Merchant Category limb` does not mention the credential, and noticing an absence is the hardest kind of review.

### SITE 4 — cl.5(xii) and the exclusion list's own commencement

**Clause.** cl.5(xii) (`§§ 5(xii) — the excluded Merchant Categories`, `§§ 5(xii) — the excluded merchants and merchant descriptions`, `§§ When each held document took effect`).
**Shape in the text.** SHAPE B, a dated exception, here at whole-document scale: a rule that incorporates a second document by reference, where the second document carries its own effective date and says of itself that it "may be updated from time to time".
**L4 shape used instead.** An AND of a date guard with the list tests, inside `clause 5(xii) excludes this charge`.
**Bought.** Temporal defeasance: the list is not one rule but a series of revisions, each defeating its predecessor from a stated date, and holding two revisions by hand means two guarded copies of a forty-line table.
A native construct would let the revision be a dimension of the rule rather than a copy of it, and the entry points at `EVAL UNDER RULES EFFECTIVE AT` in this repo as the near neighbour worth comparing.

### SITE 5 — the non-exhaustive list

**Clause.** cl.5's exclusion list, paragraph 4 (`§§ 5(xii) — the excluded merchants and merchant descriptions`).
**Shape in the text.** SHAPE F, an open defeater that no fact can close: "such as but not limited to", and "the above excluded Merchant Category Codes ... is not exhaustive".
An exception list that admits it is incomplete.
**L4 shape used instead.** The listed members only, with a condition string saying the list is open.
**Bought.** Nothing syntactic, since no construct can enumerate an open set, but it marks the boundary between the two reasons this module can answer `FALSE` to `clause 5 excludes this charge`: because the charge is outside the list, or because the list is admittedly incomplete.
The entry insists on the contrast with SITE 1 — SITE 1 wanted three-valuedness for a reason a new FACT could discharge and a new fact discharged most of it, whereas SITE 5's openness is in the DOCUMENT, so no fact can ever close it.
It is now joined by a second kind of unknowing that is ours rather than the issuer's: four rows of the list that this corpus holds but cannot classify, and today both kinds are strings.

---

# 4. `hsbc-revolution.l4` — 8 sites

Block at `hsbc-revolution.l4:1755`.
The second pass kept all eight and rewrote SITES 1, 2 and 3 to match a new fact model; SITES 4 to 8 are unchanged.

### SITE 1 — cl.4, the eighteen-bullet exclusion list

**Clause.** cl.4 (`§§ 4. Qualifying Transactions`).
**Shape in the text.** SHAPE A, general rule plus exception list attached by one word: "'Qualifying Transactions' refers to posted retail purchases …, and shall exclude the following transactions:", followed by 18 bullets.
**L4 shape used instead.** Not one rule but four.
The general limb is never stated at all — nothing in this module says "a posted retail purchase qualifies" — and the exclusions are three separate predicates, `cl.4 — the description names a transaction the clause excludes`, `cl.4 — the kind of charge is one the clause excludes`, and the MCC test, filling the first three arms of the top-level `BRANCH` so they defeat everything below them.
**Bought.** The general limb would be written, which is the part that has gone missing here, and the entry calls this the most expensive thing on its list.
As it stands the positive rule exists only as the absence of a match, so a reader cannot check the encoding against the chapeau, because there is no sentence to compare it to.
The `Charge kind` fact makes that sharper rather than softer: the chapeau admits "POSTED retail purchases", and `Retail purchase` versus `Pre-authorisation` is now a fact the module can see and still does not act on, because no bullet tells it to.

### SITE 2 — cl.4 bullet 10, "Tax payments (except HSBC Tax Payment Facility)"

**Clause.** cl.4 bullet 10, with cl.4.2 row 44 (`§§ 4. Qualifying Transactions`, `§§ 4.2 The Merchant Category Codes that earn no Reward points`).
**Shape in the text.** SHAPE C, an exception to an exception in one parenthesis: MCC 9311 is excluded by cl.4.2 row 44, and the HSBC facility is carved back in.
**L4 shape used instead.** Nothing — this is a defeasibility site with no rule at it.
The carve-back used to test the statement string, and moving off strings took the test away while the shared domain has no constructor to put in its place; the two fixtures that used to differ now answer identically, and an assertion pins that.
**Bought.** Nothing, which the entry says is what makes it worth keeping: a construct that let the carve-back out-rank the exclusion would still have nothing to say about which transactions it applies to.
This is the site that says the expressive gap is sometimes in the facts, not the logic.

### SITE 3 — cl.4.2 laid over cl.4

**Clause.** cl.4.2 over cl.4 (`§§ 4.2 The Merchant Category Codes that earn no Reward points`).
**Shape in the text.** SHAPE G, two different operations with the same effect: cl.4 says certain transactions are not Qualifying Transactions, and cl.4.2 says transactions at certain MCCs "WILL NOT EARN REWARD POINTS".
The second is a zero-earning rule over the top of the first, not a carve-out from it.
**L4 shape used instead.** Separate arms of the top-level `BRANCH` — two for cl.4, one for `cl.4.2 — the MCC earns no Reward points` — all returning the same zero answer, because on this document the two lists are disjoint and the distinction cannot change an outcome.
The arms are separate; the answer is not.
**Bought.** The distinction survives a revision: if a future revision put an MCC on both lists, the collapsed encoding would answer zero and say nothing, whereas a construct with explicit priority would surface the overlap.
The disjointness is asserted in the illustrations so that the day it stops being true, something fails.

### SITE 4 — cl.8 as the residual of cl.7

**Clause.** cl.8 read against cl.7 (`§§ 7. Eligible Transactions`, `§§ 7.1 The Reward points awarded`).
**Shape in the text.** SHAPE I, a default defined by subtraction: "1 Reward point for every SGD1 charged on ALL OTHER Qualifying Transactions THAT ARE NOT ELIGIBLE TRANSACTIONS".
**L4 shape used instead.** The `OTHERWISE` arm of the `BRANCH`, which the entry calls the one site where the flat-cascade shape is a genuinely good fit.
**Bought.** Very little.
It is recorded because it is the base case that makes the other sites legible as departures from it.

### SITE 5 — cl.7's heading against cl.7's table

**Clause.** cl.7's category heading against cl.7's MCC table (`§§ 7. Eligible Transactions`).
**Shape in the text.** SHAPE E, a contradiction within one clause: the heading reads "Dining EXCLUDING HOTEL DINING", and the table three rows above it admits 7011 (Lodging), under which hotel dining posts.
The heading carves out what the table lets in.
**L4 shape used instead.** The table wins and the heading is encoded nowhere, surviving only as a comment, because the clause's operative words are "that fall within any one of the following MCCs".
**Bought.** This is the site that most wants Catala's conflict behaviour: a native defeater would let the heading be encoded as a rule, and the two would then be visibly incomparable on a hotel restaurant charge, which is the honest answer.
Encoded by hand, the encoder's judgement is silently baked in and the reader never learns there was a question.

### SITE 6 — cl.2, the Programme period

**Clause.** cl.2 (`§§ 2. The Programme period`, `§§ Assembling the answer`).
**Shape in the text.** SHAPE D, a cross-cutting defeater over the whole instrument rather than an exception to a rule: "The Programme period starts from 1 April 2026".
**L4 shape used instead.** A wrapper rule that recomputes the answer and then re-lists all twelve fields of the `Rate answer` to change two of them, because L4 has no record-update form.
**Bought.** A module-level `SUBJECT TO` would remove the twelve-field copy entirely.
The copy is the kind of code that goes wrong when the record gains a thirteenth field, and nothing would warn.

### SITE 7 — cl.5's inclusive list against a credential it does not name

**Clause.** cl.5 (`§§ 5. Selected Contactless Payments`).
**Shape in the text.** SHAPE F, an open defeater: "a contactless terminal mode WHICH INCLUDES Visa payWave, Apple Pay, Google Pay and Samsung Pay" is an open list, so the clause does not say whether a third-party proxy card is in or out.
**L4 shape used instead.** A hand-written `AND NOT (credential EQUALS Via Amaze)` conjunct, plus a branch of its own returning the cl.8 rate at `Unconfirmed` status.
The gap is decided here, and marked as decided.
**Bought.** A construct that distinguishes "this rule does not reach the case" from "this rule excludes the case".
Today both are spelled `NOT`.

### SITE 8 — the FAQ against the T&C, a conflict between SOURCES

**Clause.** the held FAQ Q2 against cl.5 read with cl.7 (`§§ 5. Selected Contactless Payments`, `§§ 7. Eligible Transactions`).
**Shape in the text.** SHAPE E, a contradiction, and the only one in the corpus that runs between two documents rather than inside one: the FAQ says "With effect from 15 July 2024, contactless payment transactions will earn 1 HSBC Reward point", and the T&C makes a contactless tap an Eligible Transaction at 10 or 20 points.
They cannot both be right.
**L4 shape used instead.** The T&C is encoded, the FAQ is not encoded at all, and the conflict is carried as a string in `conditions` on every contactless answer.
**Bought.** A priority relation between DOCUMENTS rather than between clauses — "the later dated instrument defeats the earlier" stated once, instead of the encoder resolving it silently and leaving a note.
The entry calls this the one site on its list that is not about the document's internal structure, and the one the corpus exists to find.

---

# 5. `uob-ladys-solitaire.l4` — 6 sites

Block at `uob-ladys-solitaire.l4:1461`.
The first pass recorded 5; the second pass discharged SITE 5's prediction and added SITE 6.

### SITE 1 — cl.2(b) read against cl.32, cl.34 and cl.35

**Clause.** cl.2(b) against cl.32, cl.34 and cl.35 (`§§ 32. UNI$ will not be awarded for:`, `§§ 34. UNI$ will not be awarded for the following Merchant Transaction Codes`, `§§ 35. Excluded transaction descriptions`).
**Shape in the text.** SHAPE A, general rule plus exception list: cl.2(b) grants the Base UNI$ unconditionally, "the reward of UNI$1 for every S$5.00 spent ... on a Card", and three later clauses withdraw it from named classes — twenty-two kinds of transaction, thirty-nine MCCs, thirty-nine descriptions — each drafted as a flat "UNI$ will not be awarded for", with no cross-reference back to cl.2(b) and none to each other.
**L4 shape used instead.** The grant is not written where the document writes it: it is the `OTHERWISE` arm of a four-arm `BRANCH` whose first arm is `no UNI$ is awarded for this transaction`, a disjunction of the three withholdings (`§§ The withholding cascade`).
The general rule has been turned inside out into the residue of its own exceptions, and cl.2(b)'s text now appears at a place the document does not put it.
**Bought.** `the Base UNI$ applies` stated once at cl.2(b), with cl.32, cl.34 and cl.35 each written at its own clause as DESPITE it.
Order between the three withholdings would then be the language's problem rather than the author's, and adding a fourth — which cl.36 expressly reserves the right to do, "without giving any reason or prior notice" — would be a local edit instead of a new disjunct in a rule three sections away.

### SITE 2 — heading A and cl.4(b) read against the same three withholdings

**Clause.** heading A and cl.4(b) against cl.32, cl.34, cl.35 (`§§ 4(b) and 5 — spending in an elected Preferred Rewards Category`).
**Shape in the text.** SHAPE D, a cross-cutting defeater: the Bonus UNI$ entitlement is granted twice over, by heading A's rate line and by cl.4(b)'s "You will be eligible to earn Bonus UNI$ for every S$5.00 of spending in your Preferred Rewards Categories", and defeated by the same three lists, which never mention it.
**L4 shape used instead.** The withholding arm is placed FIRST in the `BRANCH` so that it defeats the category arm below it.
Priority is encoded as line order, which is the thing a reviewer cannot check against the document, because the document states no order.
**Bought.** The defeat stated once and applying to both grants, instead of being re-earned by the position of an arm.
The assertion that a PAYPAL* line at a Dining MCC earns nothing is today a test of arm order; it would become a test of the law.

### SITE 3 — cl.6(b)'s per-category cap inside its own card-wide cap

**Clause.** cl.6(b) (`§§ 6(b) and 8 — the cap that governs, and the date it is attributed by`).
**Shape in the text.** SHAPE G, a ceiling stated by exception: one sentence states a general ceiling of 2,700 UNI$ a calendar month and then a stricter one that partitions it, "with each Preferred Rewards Category capped at 1,350 UNI$".
The stricter limb always governs a single transaction; the general one can only ever bind across categories.
**L4 shape used instead.** The general figure is not represented at all.
The module returns `the Bonus UNI$ cap for one Preferred Rewards Category`, 1,350 UNI$ expressed as dollars, and mentions the card-wide figure only in a comment and an assertion, because `Cap` holds one number.
**Bought.** Both ceilings carried, the narrower marked as `SUBJECT TO` the wider, so a projection could show a cardmember both "S$750 left in Dining" and "S$1,500 across both" without the module having to decide in advance which one the reader wanted.

### SITE 4 — cl.6(b) against cl.6(c), and cl.6(b) against its own predecessor

**Clause.** cl.6(b) and cl.6(c) (`§§ 6(b) and 8 — the cap that governs, and the date it is attributed by`).
**Shape in the text.** SHAPE H, defeasible in form with the gap elsewhere: two overlapping defeasances in one clause, cl.6(c) stating a different cap for the Metal card and so defeating cl.6(b) by cardholder type, and cl.6(b)'s own Note defeating the former figure by date, "From 1 August 2025 ... will be revised from 3,600 UNI$ ... to 2,700 UNI$".
**L4 shape used instead.** Neither is encoded.
The Metal card has no constructor in the shared domain, and the pre-August-2025 figure is dropped on the ground that this document is the August 2025 version; both are recorded in prose.
**Bought.** Less here than elsewhere, and the entry is explicit about it: the missing piece is a Card constructor and a rule-version axis, not a defeasibility operator.
It is listed because the TEXT has the defeasible shape even though the fix is somewhere else.

### SITE 5 — a dated row inside an undated list, twice in this module

**Clause.** cl.34 and cl.35 (`§§ 34. UNI$ will not be awarded for the following Merchant Transaction Codes`, `§§ 35. Excluded transaction descriptions`).
**Shape in the text.** SHAPE B, a dated row inside an undated list: cl.34 is one table under one operative sentence with five of thirty-nine codes carrying a parenthetical commencement such as "(with effect from 1 August 2022)" or "(wef 1 October 2024)", and cl.35 is one bulleted list under one operative sentence with two of thirty-nine entries doing the same, "AMAZE* (wef 1 October 2024)" and "NORWDS* (wef 21 Jul 2024)".
The exception is not to the rule but to the rule's reach in time, written inline in a cell or a bullet.
**L4 shape used instead.** Each list is split by commencement date and rejoined by a disjunction, with every dated limb guarded by a date comparison — `34 — this Merchant Category Code is excluded whatever the date` beside `34 — this Merchant Category Code is excluded from 1 August 2022` and `34 — this Merchant Category Code is excluded from 1 October 2024`, all three rejoined by `34 — no UNI$ is awarded for this Merchant Transaction Code`.
cl.35 carries the same three-part scaffolding thirty lines later, as `35 — this transaction description is excluded whatever the date`, `35 — this transaction description is excluded from 1 October 2024`, and `35 — no UNI$ is awarded for this transaction description`.
One printed table becomes three L4 rules and a three-way OR, and so does one printed bullet list, and the two splits do not use the same number of parts for the same reason.
**Bought.** Each list kept whole, with a commencement annotation on the rows that carry one, which the entry says is closer to a temporal-qualification construct than to DESPITE.
The first pass predicted this shape would recur "in at least three places"; cl.35 is now encoded and the prediction is discharged rather than merely repeated, with the same three-rule scaffolding written twice in one file, thirty lines apart.

### SITE 6 — cl.35's "AMAZE*" against its own "AMAZE*TRANSIT"

**Clause.** cl.35 (`§§ 35. Excluded transaction descriptions`).
**Shape in the text.** SHAPE H, defeasible in form with the resolution falling out of the fact model: two bullets in one list, one dated and one not, whose matches overlap, since every "AMAZE*TRANSIT" line is also an "AMAZE*" line.
Read alone, the dated bullet says an Amaze transit ride before 1 October 2024 earns; read with the undated "TRANSIT*" bullet three rows down, it does not.
**L4 shape used instead.** Nothing, and that is the finding.
The resolution falls out of the encoding for free, because a line carries a LIST of description families and the undated TRANSIT disjunct is reached before the AMAZE gate is consulted, with an assertion pinning it — which is the only thing that makes the free resolution a checked one.
**Bought.** Nothing, which the entry says out loud because it sits in a block whose other entries all want something.
A defeasibility operator answers "which rule wins"; this is two rules that agree, reached by different routes, and the encoding that makes them agree is the LIST.

---

# 6. `posb-passion.l4` — 7 sites, plus 2 recorded non-sites

Block at `posb-passion.l4:983`, which carries its own count line: "COUNT: 7 defeasibility sites, plus 2 recorded non-sites."
The second pass kept all seven and promoted a second non-site.

### SITE 1 — clause 5(ii), the Food Republic and Food Junction withdrawal

**Clause.** cl.5(ii) (`§§ Clause 5 — Participating Stores`).
**Shape in the text.** SHAPE B, a dated exception inside an undated list: six BreadTalk Group brands are Participating Stores, followed by a parenthetical withdrawing two of them "[w]ith effect from 27 October 2024".
**L4 shape used instead.** The membership disjunction inside `cl.5 — the transaction is at a Participating Store` carries a date guard on its last arm, admitting the Food Republic and Food Junction constructors only while the transaction date is at most 26 October 2024.
The general rule and its exception are fused into one boolean, and the "26 October" boundary is an artefact of expressing "from the 27th" as "at most the 26th" — a date the document never mentions.
**Bought.** The list stays a plain list of six names, and the withdrawal is its own dated rule that defeats two of them.
The reader sees the amendment as an amendment, and so does a diff, when the issuer withdraws a seventh brand.

### SITE 2 — clause 5(iii), Mandai on-site purchases

**Clause.** cl.5(iii), with Appendix 1's restatement (`§§ Clause 5 — Participating Stores`).
**Shape in the text.** SHAPE B, a dated exception inside an undated list: four parks are Participating Stores, "(with effect from 1 December 2023 only online ticketing sites will be eligible)", and Appendix 1 says the same thing again in different words under "DBS funded Stores".
**L4 shape used instead.** A second conjunct on the membership test, disjoining a before-the-date escape with a payment-channel test.
**Bought.** One rule for membership and one dated exception for the channel — and the Appendix's restatement could then be attached to the same exception instead of being silently dropped as a duplicate, which is what this encoding does.

### SITE 3 — clause 5(iv), Singtel recurring bill payments

**Clause.** cl.5(iv) (`§§ Clause 5 — Participating Stores`).
**Shape in the text.** SHAPE A, general rule plus exception: a general admission of two Singtel channels with an untimed carve-out, "excluding Singtel recurring bill payments".
**L4 shape used instead.** An inline negated guard, `AND NOT (paid by card on file or recurring billing c)`, which is where a `NOT` has to be parenthesised by hand or it will swallow the rest of the conjunction.
**Bought.** The carve-out as a named exception that can be cited on its own in the answer's `conditions`, rather than collapsing into a generic "not a Participating Store".

### SITE 4 — Appendix 1 against clause 7, the scope question

**Clause.** Appendix 1 against cl.7 (`§§ Appendix 1 — the Exclusion List`, `§§ Clause 6 and clause 7 — Base Points, and clause 8 — POSB Bonus Points`).
**Shape in the text.** SHAPE A, general rule plus exception list, with the subordination stated only in a header: a general earning rule of 3X at Participating Stores, and a separate Exclusion List whose header scopes it to clause 7(b)(i) while its entries speak of clause 7's and clause 8's own vocabulary.
**L4 shape used instead.** An exclusion predicate tested as its own `BRANCH` arm placed BEFORE the earning arms, inside `the PAssion answer of`.
Nothing in the language records that the arm is an exception to clause 7 rather than an independent rule, and nothing checks that it was placed early enough.
**Bought.** The exclusion written as subordinate to clause 7, so its priority is stated rather than encoded as line order.
Ordering that is load-bearing and invisible is the failure mode.

### SITE 5 — Appendix 1 (Singtel) against clause 5(iv), the sharpest one

**Clause.** Appendix 1's Singtel entry against cl.5(iv) (`§§ Appendix 1 — the Exclusion List`, `§§ Clause 5 — Participating Stores`).
**Shape in the text.** SHAPE E, a contradiction: cl.5(iv) admits SingtelShop! and Singtel Exclusive Retailers as Participating Stores, and Appendix 1 then says "Base points will not be awarded for all in-stores and online purchases" at those same stores.
Two provisions of one document reach opposite results on identical facts, and neither says which yields.
**L4 shape used instead.** A dedicated `BRANCH` arm above the earning arms, `Appendix 1 (Singtel) — base points are withheld on every Singtel purchase`, returning 0 with a `conditions` string that names the conflict in words.
**Bought.** Exactly the thing Catala's default calculus does: two applicable rules with no stated priority should RAISE A CONFLICT rather than let the author pick one by writing it higher up the file.
The entry calls this the site that most wants the construct, and the one where the hand encoding is least honest, because it silently resolves what the document leaves open.

### SITE 6 — Appendix 1 (foodpanda, Gojek), the PayPal description

**Clause.** Appendix 1's foodpanda and Gojek entries (`§§ Appendix 1 — the Exclusion List`).
**Shape in the text.** SHAPE A, general rule plus exception: two Participating Stores whose points are withheld for transactions carrying a particular description, from a stated date.
**L4 shape used instead.** `Appendix 1 (foodpanda, Gojek) — a PayPal-described transaction from 1 February 2024`, a three-conjunct predicate in its own `BRANCH` arm — the merchant, membership of the PayPal description family in the transaction's description patterns, and the date.
**Bought.** Little on the logic.
The site is recorded because it is the cheapest exception in the document and it still costs a whole rule plus an ordering commitment.

### SITE 7 — clause 3 against the whole instrument

**Clause.** cl.3 (`§§ Clause 3 — the Promotion Period`).
**Shape in the text.** SHAPE D, a cross-cutting defeater over the whole instrument: every operative clause is written unconditionally, and clause 3 defeats all of them outside a stated period.
**L4 shape used instead.** The first-match cascade tests the period as one arm among eight, which makes a temporal scope over the whole document look like a peer of "this merchant is not on the list".
**Bought.** A temporal scope on the section, so that expiry is a property of the instrument rather than a guard every rule has to remember to consult.
The cost of getting this wrong is a module that keeps answering confidently about a dead promotion.

### The two recorded non-sites

**Appendix 1's SKU-level exclusions** — plastic bags, tobacco, delivery charges, gift cards, infant formula, sushi, dim sum, bundle deals, bill discounts.
These are exceptions in form, but no defeasibility construct would help: the facts they turn on are basket contents, and the `Transaction` model has no basket.
The gap is in the fact model, not in the logic, and they ride on a `conditions` string.

**Clause 4's "retail transactions" limb and clause 11's "only posted transactions"** — recorded because they used to look like sites.
Both were carried as prose caveats while the fact model had no way to say what kind of posting a transaction was, and the domain's `Charge kind` supplies it, so both are now guards rather than notes.
What clause 11 still cannot say is that a refund is SUBTRACTED from the month's total, because this module is handed the Month position already netted and an answer about one transaction is the wrong place to net a different one.

---

# 7. `flat-cards.l4` — 0 sites

`flat-cards.l4:67` says so in terms: "NO DEFEASIBILITY SITES. There is no text, so there are no exceptions to record. The section at the foot of every other module in this corpus is absent here by construction, not by omission."

No T&C is held for either card in this module, so there is nothing to encode and nothing that could have come apart from it.
The module's figures are headline rates, and every answer carries `Unconfirmed` status for that reason.
This is the control case for the whole register: a module with no document has no sites, which is the expected result and confirms that a site is a property of an encoded text rather than of L4.

---

# 8. Count per module

| module | sites | non-sites | notes |
| --- | ---: | ---: | --- |
| `dbs-yuu.l4` | **8** | 0 | first pass 6; second pass added SITE 2a and SITE 3a |
| `dbs-womans-world.l4` | **6** | 0 | count unchanged; SITE 2 and SITE 6 rewritten |
| `citi-rewards.l4` | **5** | 0 | count unchanged; SITE 1's want shrank |
| `hsbc-revolution.l4` | **8** | 0 | count unchanged; SITES 1, 2, 3 rewritten |
| `uob-ladys-solitaire.l4` | **6** | 0 | first pass 5; second pass added SITE 6 |
| `posb-passion.l4` | **7** | 2 | count unchanged; a second non-site promoted |
| `flat-cards.l4` | **0** | 0 | by construction, no text held |
| **total** | **40** | **2** | |

Two of the forty entries, yuu SITE 2a and yuu SITE 3a, are numbered as sub-sites rather than renumbered into the sequence, so the highest site number in `dbs-yuu.l4` is 6 while the module holds 8 entries.
They are counted here as sites because their module's own second-pass report counts them that way: "Two new entries in the defeasibility block, now eight sites."

---

# 9. Shape classification — the requirements input

This is the part that is actually a specification input, because it says which shapes recur and therefore what a construct has to handle.
Each of the 40 entries is assigned exactly ONE primary shape, so the counts sum to 40.
Several entries have a secondary character — a dated carve-back is both SHAPE B and SHAPE C — and where that is so the entry above says both, while the table below counts the primary only.

| shape | description | count | where |
| --- | --- | ---: | --- |
| **A** | **General rule with an exception list, encoded with the exception evaluated first, reversing the document's order** | **11** | yuu 1, 3; Woman's 1, 2; Citi 1, 2; HSBC 1; UOB 1; PAssion 3, 4, 6 |
| **B** | **A dated row inside an undated list; a commencement written inline in a cell or bullet** | **5** | yuu 2; Citi 4; UOB 5; PAssion 1, 2 |
| **C** | **An exception to an exception; a carve-back inside a carve-out** | **2** | yuu 4; HSBC 2 |
| **D** | **A cross-cutting defeater; one provision conditioning an entire layer or the whole instrument** | **4** | yuu 5; HSBC 6; UOB 2; PAssion 7 |
| **E** | **A contradiction the encoding must resolve by fiat; two provisions reach opposite results and neither yields** | **5** | yuu 6; Woman's 5; HSBC 5, 8; PAssion 5 |
| **F** | **An open defeater that cannot be enumerated, or one that cannot be read because the text is not held** | **4** | Woman's 3, 4; Citi 5; HSBC 7 |
| **G** | **Scope or ceiling stated by exception rather than by structure; a defeater whose reach must be read off an absence** | **4** | Woman's 6; Citi 3; HSBC 3; UOB 3 |
| **H** | **Defeasible in form, but the gap is in the fact model or the domain rather than in the logic** | **4** | yuu 2a, 3a; UOB 4, 6 |
| **I** | **The base case: a default defined by subtraction from the rule above it** | **1** | HSBC 4 |
| | **total** | **40** | |

## What the shape counts say

**SHAPE A is the bulk of the corpus and the plainest requirement.**
Eleven of forty sites are one general rule with a list of exceptions hanging off it, and in every one of them the encoding inverts the document: the exception becomes the first `BRANCH` arm or a negated conjunct, and the general rule becomes the `OTHERWISE`.
Two of the eleven go further than inversion — HSBC SITE 1 never states the general limb at all, and UOB SITE 1 relocates cl.2(b) to a place the document does not put it — so the audit that a reviewer must perform has no sentence to compare against.
A construct that let the general rule be written where the document writes it, with the exceptions attached as defeaters, would address eleven sites and would be checkable clause by clause.

**SHAPE B recurs across four of the six documented modules and is not a defeasibility operator's job.**
Every issuer amends a list by writing a commencement date inside one row, and every module answers by splitting the list into a dated part and an undated part and rejoining them with an OR.
UOB SITE 5 writes that three-rule scaffolding twice in one file, thirty lines apart, and yuu SITE 2 records the only outright LOSS in the register: splitting by date makes the date the list's address, so an entry that is partly dated and partly not cannot be stated, and one AXS term had to be dropped.
What these five want is a commencement annotation on a row, or a rule-version axis, and this repo already has `EVAL UNDER RULES EFFECTIVE AT` as the near neighbour worth comparing.

**SHAPE E is the smallest group that matters most, and it is the one the corpus exists to test.**
Five contradictions, and in four of them the encoding picks a winner and reports the loss in a `conditions` string: yuu SITE 6 picks the lower answer, HSBC SITE 5 lets the table beat the heading, PAssion SITE 5 puts the exclusion higher in the file, and Woman's SITE 5 drops cl.11 out of the code entirely.
HSBC SITE 8 is the outlier and the sharpest, because the conflict runs between two DOCUMENTS rather than inside one, so the fix is a priority relation over instruments rather than over clauses.
These are the sites that want Catala's refuse-to-answer, and they are the reason spec §2 makes Catala transpilability a hard requirement rather than a nice-to-have: an encoding that silently resolves a conflict has destroyed the finding the exercise was built to produce.

**SHAPE F is the case no construct can close, and it needs a type rather than an operator.**
Four sites where the defeater is real and unenumerable — an issuer's open discretion, a list that says it is not exhaustive, an inclusive list that does not say whether a proxy card is in, and an incorporation by reference to a document the corpus does not hold.
All four ask for the same thing in different words: the ability to distinguish "no applicable defeater" from "no KNOWN applicable defeater", carried in the answer's type instead of in a string.
Citi SITE 5 makes the sharpest version of the argument by contrast with Citi SITE 1 — SITE 1's want was discharged by adding a FACT, and SITE 5's cannot be, because its openness is in the document.

**SHAPE H is the control group, and it is a quarter the size of SHAPE A.**
Four sites have the defeasible shape in the text and would gain nothing from a defeasibility operator, because the obstacle is a missing constructor, a missing card type, or a resolution the fact model already supplies for free.
Keeping them in the register is what makes the other counts trustworthy: a list in which every entry wanted the feature would be evidence of nothing.
HSBC SITE 2 states the general principle best — "the expressive gap is sometimes in the facts, not the logic" — and it is worth noting that the second pass moved work in BOTH directions, discharging most of Citi SITE 1's want by adding `charge kind` while opening HSBC SITE 2 by removing a string test.

---

# 10. What each site asks for

The shape classification says what the TEXT looks like.
This second axis says what each entry's own closing sentence ASKS FOR, which is a different question and a more direct requirements input.
Assignments are read off the entry's "what a native construct would buy" sentence, not inferred from its shape.

| asks for | count | where |
| --- | ---: | --- |
| **A defeasibility operator** — DESPITE, SUBJECT TO, or a stated priority between rules | **19** | yuu 1, 3, 4, 5; Woman's 1, 2, 5; Citi 2, 3; HSBC 1, 3, 6; UOB 1, 2, 3; PAssion 1, 2, 3, 4 |
| **A neighbouring construct** — a commencement annotation, a rule-version axis, scope-as-a-type, priority between documents, or conflict-raising | **13** | yuu 2, 6; Woman's 3, 4, 6; Citi 4, 5; HSBC 5, 7, 8; UOB 5; PAssion 5, 7 |
| **No construct** — the gap is in the fact model, the domain, or the held sources, or the entry says little or nothing is bought | **8** | yuu 2a, 3a; Citi 1; HSBC 2, 4; UOB 4, 6; PAssion 6 |
| | **40** | |

Roughly half the register wants the operator the spec went looking for, a third wants something adjacent to it, and a fifth wants nothing from the language at all.
That ratio is the headline finding of the exercise, and it is worth stating plainly: a `DESPITE` keyword would address 19 of 40 sites, which is a strong result for a single construct and also a warning against treating the register as a mandate for one.

Of the 13 neighbours, four ask specifically for conflict-raising rather than resolution (yuu 6, HSBC 5, PAssion 5, and HSBC 8 in its document-level form), three ask for a temporal or rule-version dimension (yuu 2, Citi 4, UOB 5), three ask for an open or undischarged defeater to be carried in a type (Woman's 3, Woman's 4, Citi 5), one asks for scope as a type (Woman's 6), one asks for "does not reach" to be distinguishable from "excludes" (HSBC 7), and one asks for a temporal scope over a section (PAssion 7).

---

# 11. What this register does not claim, and where it differs from its sources

**Three module counts differ from the first-pass figures.**
`dbs-yuu.l4` holds 8 entries where the first pass recorded 6, and `uob-ladys-solitaire.l4` holds 6 where it recorded 5.
Both are second-pass additions and both are confirmed by their own reports, which say "now eight sites" and "Defeasibility sites: 6 (was 5)".
`posb-passion.l4` holds 7 sites and 2 non-sites where the first pass recorded 7 and 1.
No module's block is shorter than its report claims, and none is missing.

**One phrase inside a block reads loosely against its own contents, and it is recorded rather than corrected.**
`uob-ladys-solitaire.l4` SITE 6 says it is "worth saying out loud in a list of five sites that all want one".
The block holds six sites, so the phrase must mean the other five; but two of those five say in terms that a defeasibility operator is not what they want — SITE 4 says "the missing piece is a Card constructor and a rule-version axis, not a defeasibility operator", and SITE 5 says its want is "closer to a temporal-qualification construct than to DESPITE".
The sentence is a leftover from the five-site first pass and its "all" does not survive the second.
This register counts UOB at 6 sites and assigns SITE 4 and SITE 6 to the "no construct" column accordingly.

**The shape assignments in §9 are this register's work, not the encoders'.**
Each module's block describes its own sites' shapes in prose; none of them uses a shared vocabulary, and the letters A to I are imposed here so the counts can be added up.
Where an entry's shape is genuinely mixed the entry above says so, and the table counts one shape only.
A reader who disagrees with an assignment can re-cut the table without re-reading the corpus, because every row names its sites.

**The §10 assignments are read from the encoders' own sentences.**
Where an entry says "nothing", "little", or names a different construct, that is what it is counted as, even where a defeasibility operator would arguably also have helped.
This is deliberate, because the point of the axis is to record what the person who wrote the encoding wanted at the moment they hit the site.

**Nothing here was re-derived from the source PDFs.**
Every quotation is taken from the module block that quotes it, and every rule name was checked to exist in the module it is attributed to.
The clause numbering follows each module's own citation style, which is not normalised here, so a grep for a clause finds the module that spells it that way.
The styles differ between issuers and, in `posb-passion.l4`, within one module: its defeasibility block and its `§§` headings write "clause 5" and "Clause 3" while its rule names write `cl.5` and `cl.3`, and both spellings appear throughout the file.
HSBC subdivides to a second level, `cl.4.2`, which the other modules do not.
