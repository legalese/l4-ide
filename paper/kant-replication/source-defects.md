# Defects in the source artifact: `fixtures/chubb-policy.txt`

**Artifact swept:** `/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/c1881847-0452-4e2d-bab9-49cb2315f002/scratchpad/kant-repl/fixtures/chubb-policy.txt`
(54 lines, 3,573 bytes; Appendix A.1 of Kant et al. 2025, arXiv 2502.17638)

**Scope.** These are defects **in the policy text itself**, not in anybody's Prolog/L4 encoding of it.
Line numbers are the fixture's; clause numbers are the document's. All quotations are verbatim
(`grep`/`sed`), with the fixture's hard line-wraps removed where a sentence spans lines.

**Method note.** The whole document is three sections (`1.x`, `2.x`, `3.x`), three ALL-CAPS headings,
and two flat enumerations. It contains **no definitions section**, **no monetary amount of any kind**,
and the word "apply" appears affirmatively **only in a heading that is a question** (`3.1 Where does Your
Policy apply?`) — never in an operative grant. Those three facts generate most of what follows.

---

## Summary table

| #   | Defect                                                                                                                                                                                   | Clause / line              | Class                                  | Benchmark queries it touches |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- | -------------------------------------- | ---------------------------- |
| D1  | No insuring clause; "benefit" never defined or quantified                                                                                                                                | whole doc                  | missing operative provision            | all 9                        |
| D2  | `Section 5` cited twice; no Section 4 or 5 exists                                                                                                                                        | 1.2 (L18), 3.5.1 (L50)     | dangling cross-reference               | 3, 4                         |
| D3  | §1.1(3) and §1.2 disagree during the pendency window                                                                                                                                     | L12 vs L16–17              | two places, one rule, no agreement     | **3** (decides its gold)     |
| D4  | §2.1 item 5 does not fit its own chapeau; forces a silent causal/status split                                                                                                            | L23–29                     | enumeration/chapeau mismatch           | **9**, 2, 6                  |
| D5  | "in a timely fashion" points at a §1.3 condition carrying **two** deadlines                                                                                                              | L12, L16–17 vs L19–21      | under-specified term                   | 4, 6, 9                      |
| D6  | §1.2 fraud/misrepresentation clause: scope of "material", self-contradictory object, undefined "the Company", unbounded "there is fraud"                                                 | L14–17                     | conj./disj. ambiguity + undefined term | 5, 8                         |
| D7  | Cancelation has no effective moment — prospective or retroactive is unstated                                                                                                             | 1.2                        | temporal gap                           | **4**                        |
| D8  | Singapore statute cited under New York governing law                                                                                                                                     | 3.2.1 (L36) vs 3.3.1 (L45) | conditions in two places that disagree | —                            |
| D9  | §3.2.1 internal conflicts: dangling "such parties", drift to "difference", arbitration-award condition precedent vs 60-day suit bar, proof-of-claim reference to non-existent provisions | L34–43                     | dangling refs + regime conflict        | —                            |
| D10 | "at the signing of the policy" — whose signature?                                                                                                                                        | 3.5.1 vs 1.1(1) vs 3.6     | ambiguity                              | —                            |
| D11 | §3.1.1 grants coverage unqualified, contradicting §1.1 and §2.1                                                                                                                          | L32                        | conflict                               | all                          |
| D12 | Event-time vs hospitalization-time anchors used inconsistently                                                                                                                           | 1.1, 2.1 chapeau, 2.1(5)   | temporal inconsistency                 | 2, 6, 9                      |
| D13 | §3.6 breaks the numbering and layout pattern (heading run into body; no 3.6.1)                                                                                                           | L52–54                     | machine-processing hazard              | 3, 4                         |
| D14 | Circular reference chain: 1.2 → "Section 5" → 3.6 → "Section 1" → 1.2                                                                                                                    | L18, L54                   | circularity                            | —                            |
| D15 | Roster of terms used but never defined                                                                                                                                                   | throughout                 | undefined terms                        | **5**, 1–9                   |
| D16 | §1.1 list carries "and" after both item 2 and item 3                                                                                                                                     | L10–13                     | list-connective defect                 | —                            |
| D17 | Defined-term casing not observed; "We"/"Our" never appear                                                                                                                                | throughout                 | drafting hygiene                       | —                            |
| D18 | §1.3: cataphoric "the medical provider in question"; covenant drafted, condition relied on                                                                                               | L19–21                     | reference + modality                   | 4, 6, 9                      |
| D19 | §3.4.1 "or someone else" is unbounded and unanchored                                                                                                                                     | L47                        | undefined party                        | —                            |
| D20 | No claim notice, proof-of-loss, or payment-timing provisions exist                                                                                                                       | whole doc                  | structural omission                    | —                            |

---

## Severe

### D1 — The policy never grants coverage or defines a benefit

**Quoted text (§1.1, lines 7–8):**

> `1.1 The payment of any benefit under this policy is conditioned on the policy being in effect at the time of the hospitalization for sickness or accidental injury on which the claim for such benefit is premised.`

**Quoted text (§2.1, line 23):**

> `2.1 Your policy will not apply to, and no benefit will be paid with respect to, any event causing sickness or accidental injury arising directly or indirectly out of:`

**What is wrong.** Both sentences presuppose "benefit" as a term already fixed, and nothing fixes it.
There is no insuring agreement, no schedule of benefits, no covered-expense definition, and no amount:

```
$ grep -n -E '\$|[0-9]+,[0-9]{3}|percent|%' chubb-policy.txt   →  (no monetary amounts anywhere)
$ grep -n -iE 'means|defined|definition|shall mean' chubb-policy.txt  →  (none)
```

The document specifies **when the policy is in effect** (§1) and **when it does not apply** (§2), and
never specifies **what it does**. The only affirmative statement that the policy does anything for the
insured is §3.1.1's `Your Policy insures You twenty-four (24) hours a day anywhere in the world` — which
states coverage's _time and place_ while naming no peril and no payment.

**Effect on encoding.** A `covered(C)` predicate has no positive branch to write. Every encoder is
forced to synthesise the missing rule as "covered ⟺ in-effect ∧ ¬excluded", i.e. to invent the
insuring clause. Two encoders can invent different ones (e.g. does the hospitalization itself have to
be medically necessary? in-term? within the 24/7 worldwide scope of §3.1.1?) and both remain faithful
to the text.

**Effect on answering.** All five `"gold": "Yes"` answers in `queries.json` (ids 2, 3, 7, 9) are not
_derivable_ from the artifact — they are derivable only from the _absence_ of a firing exclusion. A
strict reader who answers "I do not know" because the document never says what the policy pays is
scored wrong. Since `A31-vanilla.txt` offers exactly three response options — `"Yes"`, `"No"`, or
`"I do not know"` — this defect systematically penalises the most textually careful behaviour, and it
does so on 4 of 9 items (44% of the benchmark).

---

### D2 — Two live cross-references to a "Section 5" that does not exist

Every cross-reference in the document, exhaustively:

```
$ grep -o -n 'Section [0-9][0-9.]*' chubb-policy.txt
12:Section 1.3
16:Section 1.3
18:Section 5
50:Section 5
54:Section 1
```

The document's highest section number is **3**. There is no Section 4 and no Section 5 — the last
clause is `3.6` (line 52) and the file ends at line 54.

**Quoted text (§1.2, lines 17–18):**

> `It will also be automatically canceled at midnight, US Eastern time then in effect, on the last day of the policy term described in Section 5 below.`

**Quoted text (§3.5.1, lines 50–51):**

> `3.5.1 The premium described in Section 5 below shall be paid in one lump sum at the signing of the policy.`

**What is wrong.** Both are dangling. Worse, they are the **two money-and-time clauses**: the automatic
expiry date and the premium. The intended targets are almost certainly §3.6 (`Policy Term`) and §3.5
(`Premium`) respectively — but §3.5.1 pointing at "Section 5" for "the premium described" is circular
even after repair, because §3.5 _is_ §3.5.1, and it describes no premium (see D1: no amount exists).
Both also say "below" while §3.5.1 and §3.6 sit at the very end of the document; from line 50, nothing
is below except §3.6.

**Effect on encoding.** An encoder resolving `Section 5` finds nothing and must either (a) guess §3.6,
(b) drop the term-expiry rule, or (c) emit an undefined predicate. Option (b) silently deletes §1.1(4)'s
only automatic trigger. Option (c) is exactly the `"procedure does not exist"` failure that
`A32-unguided-policy.txt` §4 warns generators against — so the prompt's own quality bar is unmeetable
against this text.

**Effect on answering.** Queries 3 and 4 turn on the interaction of policy term, cancelation and the
§1.3 condition; the clause that fixes when the policy automatically ends points at nothing.

---

### D3 — §1.1(3) and §1.2 state the same condition and disagree during the pendency window

**Quoted text (§1.1, lines 9–13):**

> `The policy will be in effect if:` > `1. This agreement is signed,` > `2. The applicable premium for the policy period has been paid, and` > `3. The condition set out in Section 1.3 is still pending or has been satisfied in a timely fashion, and` > `4. The policy has not been canceled.`

**Quoted text (§1.2, lines 14–17):**

> `1.2 Cancelation will be deemed to have occurred if there is fraud, or any misrepresentation or material withholding of any information provided by you to the Company in connection with any communication or information relating to this policy, or if the condition set out in Section 1.3 has not been satisfied in a timely fashion.`

**What is wrong.** The §1.3 condition is tested **twice, by two clauses, with different wording**, and
the tests are not equivalent:

- §1.1(3) is satisfied by `still pending` **or** `has been satisfied in a timely fashion`.
- §1.2 deems cancelation when the condition `has not been satisfied in a timely fashion` — **with no
  pendency carve-out**.

At month 5, the confirmation has not been supplied. §1.1(3) holds (pending). §1.2, read literally,
also holds — the condition has not been satisfied — so cancelation is deemed, so §1.1(4) fails, so the
policy is not in effect. **§1.1(3) and §1.1(4) return opposite answers on the same fact.**

The presence of the `still pending` disjunct in §1.1(3) and its absence in §1.2 is the signature of the
defect: the drafter saw the pendency problem and repaired it in one of the two places. Note that a
reader cannot escape §1.2 by preferring §1.1(3), because §1.1(4) _routes through_ §1.2 — the in-effect
test requires both.

**Effect on encoding.** A generator that lowers §1.2 faithfully produces
`canceled :- \+ satisfied_timely(wellness_condition).` and a generator that lowers §1.1(3) faithfully
produces `in_effect :- (pending ; satisfied_timely).` Conjoining them yields a rule that is
**unsatisfiable during months 0–7** — the exact interval in which most of the benchmark's fact patterns
sit. Neither encoder made an error.

**Effect on answering.** This is outcome-determinative for query 3:

> `"will my policy apply if I was hospitalized for pneumonia 5 months after the policy's effective date, and my age at the time of hospitalization is 65?"`, `"gold": "Yes"`, rationale `"1.1(3) 1.3 condition still pending at 5 months"`

The answer key cites §1.1(3) and is silent on §1.2. A model that reads the cancelation clause — the
clause the in-effect test explicitly incorporates by reference — answers "No" and is marked wrong for
reading the document more completely.

---

### D4 — §2.1 item 5 does not fit its chapeau, and forces an unsignalled causal/status split

**Quoted text (§2.1, lines 23–29, unwrapped):**

> `2.1 Your policy will not apply to, and no benefit will be paid with respect to, any event causing sickness or accidental injury arising directly or indirectly out of: 1. Skydiving; or 2. Service in the military; or 3. Service as a fire fighter; or 4. Service in the police; or 5. If your age at the time of the hospitalization is equal to or greater than 80 years of age.`

**What is wrong — three distinct faults in one enumeration.**

**(a) Grammatical.** Items 1–4 are noun phrases that complete the chapeau's preposition. Item 5 is a
finite conditional clause beginning `If`. Substituting item 5 into the chapeau yields:

> "…any event causing sickness or accidental injury arising directly or indirectly out of **if your age
> at the time of the hospitalization is equal to or greater than 80 years of age**."

That is not a sentence. Item 5 is the only item that cannot be read through its own chapeau.

**(b) Logical.** Age is not a thing an injury can arise out of, directly or indirectly. So item 5 must
be read as a **flat status exclusion** severed from the chapeau's causal test, while items 1–4 are read
**causally**. **Nothing in the text signals the switch.** The list presents five items under one
preposition with one connective (`; or`) and expects the reader to apply two different logical forms.

**(c) It makes the benchmark's own answer key contestable.** The gold rationale for query 9 is
`"2.1(4) requires the injury to arise out of police service; a son's bite does not"` — the causal
reading. The gold rationale for query 2 is `"2.1(5) threshold is >= 80"` — the status reading. Both are
correct; they are just not both available from a uniform reading of one list.

**Effect on encoding.** The natural mechanical lowering is uniform:

```prolog
excluded(C) :- claim_cause(C, skydiving).
excluded(C) :- claim_cause(C, military_service).
excluded(C) :- claim_cause(C, firefighter_service).
excluded(C) :- claim_cause(C, police_service).
excluded(C) :- claim_age(C, A), A >= 80.
```

…which requires the encoder to notice, unprompted, that the fifth clause takes a different argument
from the first four. An encoder that instead lowers all five uniformly as status predicates
(`is_firefighter(C)`, `is_police_officer(C)`, `age_at_least_80(C)`) is being **more** faithful to the
list's parallel surface form, and gets query 9 wrong.

**Effect on answering.** Query 9 —

> `"will my policy apply if I was hospitalized due to my son biting me in the ankle, proof of my wellness visit was provided 6 months after the effective date, and I was serving as a police officer at the time of hospitalization?"`, `"gold": "Yes"`

— is graded against the causal reading of item 4 while the same document grades query 2 against the
status reading of item 5. The `arising directly or indirectly out of` language is also unusually broad
("indirectly"), so even under the causal reading, whether an off-duty injury to a serving police
officer is "indirectly" out of police service is genuinely arguable. This item is measuring the model's
guess about which of two readings the answer key adopted, not its legal reasoning.

---

## High

### D5 — "in a timely fashion" names a single deadline; §1.3 contains two

**Quoted text (§1.3, lines 19–21, unwrapped):**

> `1.3 No later than the 7th month anniversary of the effective date of this policy, you will supply us with written confirmation from the medical provider in question of a wellness visit for yourself with a qualified medical provider occurring no later than the 6th month anniversary of the effective date of this policy.`

**What is wrong.** §1.3 imposes **two** deadlines: the **visit** must occur by the 6-month anniversary,
and the **confirmation** must be supplied by the 7-month anniversary. Both §1.1(3) and §1.2 then refer
back to it in the singular — `satisfied in a timely fashion` — without saying which deadline "timely"
measures, or whether it means both.

Compounding this, the attachment of `occurring no later than the 6th month anniversary` is itself
ambiguous: its nearest head is `a wellness visit for yourself with a qualified medical provider`
(visit-by-month-6), but it can be read as attaching to `written confirmation` (confirmation-by-month-6),
which would then contradict the 7-month deadline opening the same sentence.

**Effect on encoding.** `satisfied_timely` needs two facts (visit date, confirmation date) but the
clauses that consume it supply the vocabulary for one. Encoders will variously produce
`ConfDate =< 7`, `VisitDate =< 6`, or `VisitDate =< 6, ConfDate =< 7`.

**Effect on answering.** The query set silently adopts the confirmation-only reading and never states a
visit date:

- q4: `"I had given confirmation of my wellness visit 8 months after the policy's effective date"` → gold `No` (8 > 7)
- q6: `"proof of my wellness visit was provided 6.5 months after the policy's effective date"` → gold `Yes` on this limb
- q9: `"proof of my wellness visit was provided 6 months after the effective date"` → gold `Yes`

Under `VisitDate =< 6, ConfDate =< 7` all three are **under-determined**, because no query gives a visit
date. An encoder that captures both of §1.3's deadlines — the more faithful encoding — cannot answer
any of them and must either fail or fabricate the missing fact. Note this collides directly with
`A32-unguided-query.txt` instruction 6, which tells the query generator to set unrelated parameters so
that all conditions are satisfied: the generator must decide whether the visit date is "related" to a
query that mentions only the proof date.

---

### D6 — §1.2's fraud clause: four independent faults in one sentence

**Quoted text (§1.2, lines 14–16):**

> `Cancelation will be deemed to have occurred if there is fraud, or any misrepresentation or material withholding of any information provided by you to the Company in connection with any communication or information relating to this policy`

**(a) The scope of "material" is genuinely ambiguous.** Two parses:

- **Parse A:** `[any misrepresentation] or [material withholding]` — _any_ misrepresentation cancels,
  however trivial; only withholdings need be material.
- **Parse B:** `any material [misrepresentation or withholding]` — materiality governs both.

The adjective sits immediately before `withholding`, favouring A; ordinary insurance practice and the
symmetry of the two nouns favour B. Parse A makes an immaterial slip on any form a total forfeiture of
coverage. This is a live conjunctive/disjunctive-scope ambiguity that changes outcomes.

**(b) The object of both nouns is self-contradictory.** `withholding of any information provided by
you` — you cannot withhold information you provided. Read literally, the withholding limb is a null
set and cancels nothing. Likewise `misrepresentation … of any information provided by you`: the
information provided _is_ the representation; one does not misrepresent one's own representation. The
drafter presumably meant "misrepresentation in, or material withholding from, information provided by
you," but that is not what the text says.

**(c) `the Company` is undefined.** It occurs exactly once in the document
(`grep -c Company` → 1). The insurer is defined as `CODEX INSURANCE LIMITED ("us")` (line 2) and
referred to throughout as `Us`/`us`/`our`. Whether `the Company` is the insurer, an affiliate, or a
broker is unstated. If `the Company` ≠ `us`, then misrepresentations made **to the insurer** trigger no
cancelation at all.

**(d) `there is fraud` binds no actor and no time.** Not "fraud by you", not "fraud in connection with
this policy" — the fraud limb is grammatically severed from the `provided by you to the Company`
qualifier that governs the other two limbs. Read literally, fraud by _anyone_, including the insurer,
cancels the policy. And `any communication or information relating to this policy` has no temporal
bound, so a misstatement in a post-loss claim letter cancels the policy — as of when is unstated (see D7).

**Effect on encoding.** `canceled` requires an actor-and-materiality-parameterised predicate the text
does not license. Encoders will silently pick one parse; the parses differ in outcome.

**Effect on answering.** Queries 5 and 8 both stipulate the absence of fraud/misrepresentation
(`"I did not commit fraud or misrepresentation"`, `"I did not commit fraud"`), which tells us the
benchmark treats §1.2 as live and expects it to be encoded — while leaving the encoder to guess (a),
(c) and (d).

---

### D7 — Cancelation has no effective moment

**What is wrong.** §1.2 says `Cancelation will be deemed to have occurred if …` and never says **when**.
§1.1 fixes the test moment precisely — `the policy being in effect at the time of the hospitalization` —
so the cancelation date is load-bearing, and it is missing. Three readings are all available:

1. Cancelation takes effect **when the triggering fact occurs** (e.g. midnight after the 7-month
   anniversary passes unsatisfied) — prospective.
2. Cancelation is **deemed to have occurred** _ab initio_ — "deemed to have occurred" is retroactive
   language, and would void claims that arose while the condition was still pending.
3. Cancelation takes effect **when the insurer declares it** — no such mechanism exists in the document;
   there is no notice-of-cancelation provision, and no cure period or refund.

The clause also provides no way to un-cancel: supplying the confirmation late does not restore the policy.

**Effect on answering.** This decides query 4:

> `"will my policy apply if I was hospitalized due to a fall while traveling abroad and I had given confirmation of my wellness visit 8 months after the policy's effective date?"`, `"gold": "No"`

The query **does not say when the hospitalization occurred**. Under reading 1, a hospitalization in
month 3 is covered (the condition was pending; the policy was in effect at the time of hospitalization
per §1.1) and the gold answer is wrong. Under reading 2 it is not covered and the gold is right. The
item is only answerable once the reader silently adopts either retroactivity or the assumption that the
hospitalization post-dates month 8 — neither of which is in the artifact or the query.

---

### D8 — A Singapore statute is cited under New York governing law

**Quoted text (§3.2.1, lines 35–36):**

> `the dispute or disagreement must be referred to arbitration in accordance with the provisions of the Arbitration Act (Cap. 10) and any statutory modification or re-enactment thereof then in force`

**Quoted text (§3.3.1, line 45):**

> `3.3.1 Your Policy is governed by the laws of New York.`

**What is wrong.** `(Cap. 10)` is Singapore's chapter-numbering convention for its Arbitration Act.
New York has no "Cap." numbering and no statute called the Arbitration Act; New York arbitration is
governed by CPLR Article 75 (and the FAA). The arbitration clause and the choice-of-law clause point
at **two different legal systems**, and §1.2's `US Eastern time` and §3.4.1's `United States currency`
side with New York while §3.2.1 sides with Singapore. This is a paste residue: the underlying document
is a Singapore-form policy (the fixture filename is `chubb-policy.txt`) with an American choice of law
laid over it, and the anonymisation to `CODEX INSURANCE LIMITED` did not reach the statutory citation.

**Effect.** Not exercised by the nine queries, but it is a straightforward factual defect in a document
presented as a gold standard, and any downstream use of the fixture for choice-of-law, procedural or
jurisdictional reasoning inherits an unresolvable conflict.

---

## Medium

### D9 — §3.2.1 contains four further internal faults

**Quoted text (§3.2.1, lines 34–43, unwrapped):**

> `3.2.1 If any dispute or disagreement arises regarding any matter pertaining to or concerning this Policy, the dispute or disagreement must be referred to arbitration in accordance with the provisions of the Arbitration Act (Cap. 10) and any statutory modification or re-enactment thereof then in force, such arbitration to be commenced within three (3) months from the day such parties are unable to settle the dispute or difference. If You fail to commence arbitration in accordance with this clause, it is agreed that any cause of action and any right to make a claim that You have or may have against Us shall be extinguished completely. Where there is a dispute or disagreement, the issuance of a valid arbitration award shall also be a condition precedent to our liability under this Policy. In no case shall You seek to recover on this Policy before the expiration of sixty (60) days after written proof of claim has been submitted to Us in accordance with the provisions of this Policy.`

**(a) `such parties` has no antecedent.** The word "parties" does not occur anywhere earlier in the
document (`grep -n parties` → line 37 only). `such` is an anaphoric determiner pointing at a noun that
was never introduced. The parties are named only as `us` and `You` in the unnumbered preamble.

**(b) Terminology drift within one sentence.** The clause says `dispute or disagreement` three times
(lines 34, 35, 40) and then `the dispute or difference` (line 38) — with the definite article, as though
"difference" had been introduced. It had not. Whether "difference" is a synonym or a distinct
(broader) category is unstated, and the three-month limitation attaches to the undefined one.

**(c) The limitation clock has no computable start.** `three (3) months from the day such parties are
unable to settle the dispute or difference` — nothing defines, evidences, or dates the moment of being
"unable to settle". A limitation period that **extinguishes all rights completely** runs from an
unascertainable date.

**(d) Two incompatible dispute regimes are stacked.** `the issuance of a valid arbitration award shall
also be a condition precedent to our liability` (mandatory arbitration; no liability without an award)
sits beside `In no case shall You seek to recover on this Policy before the expiration of sixty (60)
days after written proof of claim has been submitted` — a standard suit-limitation clause that
presupposes recovery by action. If arbitration is mandatory and an award is a condition precedent, the
60-day rule regulates a proceeding the clause has just abolished.

**(e) A dangling reference to provisions that do not exist.** `written proof of claim has been submitted
to Us in accordance with the provisions of this Policy` — **the Policy contains no proof-of-claim
provisions.** There is no notice clause, no proof-of-loss requirement, no form, no deadline, and no
addressee. See D20.

---

### D10 — "at the signing of the policy" — whose signature?

**Quoted text (§3.5.1, lines 50–51):**

> `3.5.1 The premium described in Section 5 below shall be paid in one lump sum at the signing of the policy.`

The document contains **two distinct signing events**:

- §1.1(1), line 10: `1. This agreement is signed,` — passive, actor unstated, most naturally _your_ signature.
- §3.6, lines 52–53: `The term of this policy will begin on the date accepted by Us as signified by our signature of the policy (the effective date)`.

`at the signing of the policy` names neither. Since the effective date is fixed by **our** signature,
and the premium condition in §1.1(2) is a precondition to the policy being in effect, the ambiguity
determines whether the premium falls due **before** or **after** the effective date — and, because all
the benchmark's dates are expressed relative to the effective date, whether "paid on time" is even a
relative-time question. `A31-vanilla.txt` and `A32-unguided-policy.txt` both instruct that the premium
be assumed paid on time, which papers over the defect for these nine queries but not for reuse.

Related: §1.1(2) says `The applicable premium for the policy period has been paid` — "applicable" and
"policy period" imply a schedule of premiums across periods, while §3.5.1 mandates `one lump sum` for a
one-year term. See D15 on the four spellings of the term/period concept.

---

### D11 — §3.1.1 grants coverage unqualified

**Quoted text (§3.1.1, line 32):**

> `3.1.1 Your Policy insures You twenty-four (24) hours a day anywhere in the world.`

**What is wrong.** This is the **only** affirmative statement in the document that the policy insures
anyone, and it carries no "subject to the terms, conditions, limitations and exclusions of this Policy"
qualifier — the phrase such clauses invariably carry, precisely because they read as unconditional
grants. As drafted, §3.1.1 says coverage is continuous and worldwide, while §1.1 conditions all benefits
on the policy being in effect and §2.1 removes whole classes of events.

**Effect on encoding.** An encoder looking for the missing insuring clause (D1) will find §3.1.1 and
may lower it as `covered(C) :- true.`, or as a scope predicate, or ignore it. There is no textual basis
for choosing. Note query 4's `"a fall while traveling abroad"` exists specifically to exercise §3.1.1's
worldwide limb, so the benchmark does treat it as operative.

---

### D12 — Event-time and hospitalization-time anchors are used inconsistently

Three temporal anchors, in three clauses that must be evaluated together:

| clause                | quoted anchor                                                                           | anchored to     |
| --------------------- | --------------------------------------------------------------------------------------- | --------------- |
| §1.1 (L7–8)           | `at the time of the hospitalization`                                                    | hospitalization |
| §2.1 chapeau (L23–24) | `any event causing sickness or accidental injury arising directly or indirectly out of` | the event       |
| §2.1(5) (L29)         | `If your age at the time of the hospitalization is`                                     | hospitalization |

**What is wrong.** Items 1–4 of §2.1 are tested at the time of the **event** (that is what the chapeau's
causal language anchors to); item 5, under the same chapeau, is expressly tested at the time of the
**hospitalization**. These diverge whenever the event and the hospitalization are separated in time —
which is common (an injury at 79 with a hospitalization at 80; a skydiving injury hospitalised weeks
later; a chronic sickness). The document supplies no rule for the gap.

**Effect on encoding.** The encoder needs at least two date/age facts per claim (age at event, age at
hospitalization) but the text names only one and the query set supplies only `age at the time of
hospitalization`. Queries 2, 6 and 9 all use the hospitalization anchor, so the divergence is invisible
in scoring — and therefore an encoder that models it correctly gains nothing while an encoder that
collapses the two loses nothing.

---

### D13 — §3.6 breaks the document's numbering and layout pattern

**Quoted text (lines 52–54):**

> `3.6 Policy Term The term of this policy will begin on the date accepted by Us as signified by our signature of the policy (the effective date) and will last for a period of one year from that date, unless previously canceled pursuant to Section 1 above.`

Every other subsection of Section 3 puts its heading on its own line and its text in a numbered
`N.N.N` sub-clause:

```
31:3.1 Where does Your Policy apply?
32:3.1.1 Your Policy insures You twenty-four (24) hours a day anywhere in the world.
33:3.2 Arbitration
34:3.2.1 If any dispute or disagreement arises …
44:3.3 Laws of New York
45:3.3.1 Your Policy is governed by the laws of New York.
46:3.4 US Currency
47:3.4.1 All payments by You to Us …
49:3.5 Premium
50:3.5.1 The premium described in Section 5 below …
52:3.6 Policy Term The term of this policy will begin …      ← heading run into body; no 3.6.1
```

**What is wrong.** §3.6 is the only subsection whose heading is not separated from its text and the only
one with no `.1` child. The heading `Policy Term` is indistinguishable from the start of the sentence
without semantic parsing.

**Effect on encoding.** Any chunker, section-splitter or retrieval step keyed on the `^\d+\.\d+\.\d+`
pattern — the pattern the other five subsections establish — **silently drops §3.6 entirely**. §3.6 is
the clause that defines the effective date and the one-year term: the anchor for every relative date in
the benchmark, and the referent §1.2's broken `Section 5` was reaching for (D2). Losing it is silent,
not an error, and it degrades queries 3 and 4. For a fixture whose whole purpose is to be fed to
automated encoders, this is a real hazard, not cosmetics.

---

### D14 — Circular cross-reference chain

- §1.2 (L17–18): the policy `will also be automatically canceled … on the last day of the policy term described in Section 5 below` — cancelation is defined by reference to the term.
- The only clause describing the term is §3.6 (L52–54), which says the term `will last for a period of one year from that date, unless previously canceled pursuant to Section 1 above` — the term is defined by reference to cancelation.

Each of the two clauses defines itself in terms of the other, and one leg of the loop is additionally
broken (D2: "Section 5" does not exist). An encoder that follows the references literally produces
mutually recursive rules with no base case.

**Also in §1.2, a dangling pronoun.** Line 17: `It will also be automatically canceled at midnight …`.
The subject of the two preceding clauses is `Cancelation`; the nearest noun phrase is `the condition set
out in Section 1.3`. The intended antecedent — "the policy" — is the subject of neither. Read to its
grammatical antecedent, the sentence says _cancelation will be canceled_.

---

## Low, but worth recording

### D15 — Terms used but never defined

The document has no definitions clause (`grep -iE 'means|defined|definition|shall mean'` → nothing).
The following operative terms are used without definition:

| term                                                                    | first use             | why it matters                                                                                                                                                                  |
| ----------------------------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `benefit`                                                               | §1.1 L7               | never quantified or described — see D1                                                                                                                                          |
| `sickness` / `accidental injury`                                        | §1.1 L8               | **decides query 5** (see below)                                                                                                                                                 |
| `hospitalization`                                                       | §1.1 L8               | inpatient? overnight? emergency-room attendance?                                                                                                                                |
| `still pending`                                                         | §1.1(3) L12           | **decides query 3**; the pendency window is nowhere delimited                                                                                                                   |
| `in a timely fashion`                                                   | §1.1(3) L12, §1.2 L17 | two candidate deadlines — see D5                                                                                                                                                |
| `the Company`                                                           | §1.2 L15              | used once; the insurer is `us` — see D6(c)                                                                                                                                      |
| `wellness visit`                                                        | §1.3 L20              | no content, duration, or scope specified                                                                                                                                        |
| `qualified medical provider`                                            | §1.3 L21              | qualified by whom, under which jurisdiction's licensure?                                                                                                                        |
| `the medical provider in question`                                      | §1.3 L20              | see D18                                                                                                                                                                         |
| `dispute` / `disagreement` / `difference`                               | §3.2.1 L34, L38       | three words, unclear whether two or three concepts — D9(b)                                                                                                                      |
| `unable to settle`                                                      | §3.2.1 L37            | starts a rights-extinguishing clock — D9(c)                                                                                                                                     |
| `someone else`                                                          | §3.4.1 L47            | see D19                                                                                                                                                                         |
| `policy period` / `policy term` / `term of this policy` / `Policy Term` | L11, L18, L52         | four spellings of what appears to be one concept, none defined; "policy period" (§1.1(2)) additionally implies multiple premium periods, contradicting §3.5.1's single lump sum |

**The sharpest instance is query 5.** Its gold answer is `No` on the rationale
`"1.1 requires sickness or accidental injury; self-inflicted intentional injury is neither"` —

> `"will my policy apply if I was hospitalized for punching my own face to show off for my friends and I did not commit fraud or misrepresentation?"`

That answer turns **entirely** on the boundary of `accidental injury`, a term the artifact never
defines, and there is no self-inflicted-injury exclusion in §2.1 to carry the weight instead. The
reasoning is imported from general insurance law, not from the document. An encoder confined to the
four corners of the text — which is what `A32-unguided-policy.txt` asks for
(`translate the document into valid Prolog rules`) — has no predicate to write and cannot reach the
gold answer. Query 5 is unanswerable from the artifact alone.

### D16 — §1.1's enumeration carries "and" twice

Lines 10–13: item 1 ends `signed,`; item 2 ends `has been paid, and`; item 3 ends
`in a timely fashion, and`; item 4 ends `has not been canceled.` The conjunction appears after **both**
the penultimate and antepenultimate items. Conventional drafting places it once, before the final item.
Because `∧` is associative the truth-conditions are unaffected, but the doubled connective invites a
reading in which items 1–3 form one closed set and item 4 is appended separately, and it is exactly the
surface cue a naive segmenter uses to find a list boundary.

### D17 — Defined terms are declared but not observed

The preamble (lines 2–4) defines the parties in specific cases:
`CODEX INSURANCE LIMITED ("us")` — lowercase — and `________________ ("You")` — capitalised. Measured
usage across the file:

```
You 7   you 2   Your 4   your 2   Us 5   us 2   Our 0   our 2   We 0   we 0   Policy 8   policy 15
```

Both parties and the policy itself are referred to in both cases, sometimes within a single sentence:
line 47, `All payments by You to Us and by Us to You or someone else under your policy` (capital
`You`/`Us`, lowercase `your policy`); line 41, `condition precedent to our liability` (lowercase `our`,
against 5 capitalised `Us`). `We` and `Our` never appear at all, though §3.6 uses `Us` and `our` for the
same actor in one sentence: `the date accepted by Us as signified by our signature`. Section 1 and
Section 2 use lowercase `you`/`your`/`policy` throughout; Section 3 switches to capitals. Since the
preamble makes the capitalised forms the defined terms, a strict reader must ask whether lowercase
`policy` in §1 and §2 denotes the same thing as capitalised `Policy` in §3.

### D18 — §1.3: a cataphoric definite reference, and covenant/condition confusion

**(a)** `written confirmation from **the medical provider in question** of a wellness visit for yourself
with **a qualified medical provider**` (lines 20–21). The definite, anaphoric phrase `the medical
provider in question` precedes its own antecedent, the indefinite `a qualified medical provider`, in the
same sentence. At the point `in question` is read, no provider has been put in question. Strictly, the
two phrases could denote different people — confirmation _from_ one provider _about_ a visit with
another.

**(b)** §1.3 is drafted as a **covenant** (`you will supply us with …`) but §1.1(3) and §1.2 both call it
`the condition set out in Section 1.3`. The distinction is not cosmetic: a breached promise sounds in
damages and does not by itself defeat coverage, whereas an unfulfilled condition does. §1.3 itself
states no consequence for non-performance; the consequence lives only in §1.1(3) and §1.2, which do not
agree with each other (D3). The document also uses `will` for the obligation here, `shall` in §3.5.1 and
§3.2.1, and `must` in §3.2.1 and §3.4.1 — three modals for what appear to be three obligations of the
same force.

### D19 — §3.4.1's "someone else"

**Quoted text (line 47–48):**

> `3.4.1 All payments by You to Us and by Us to You or someone else under your policy must be in United States currency.`

`someone else` is an unbounded, undefined third party. No provision of the policy authorises payment to
anyone other than You: there is no assignment clause, no beneficiary designation, no direct-payment-to-
provider clause, and no third-party-beneficiary clause. The currency clause therefore contemplates a
payee the rest of the document does not create. Either a payee class is missing elsewhere, or this
phrase is residue from a longer form.

### D20 — Structural omissions

Provisions a policy of this shape normally carries, which are entirely absent, and which the text
nevertheless assumes:

- **Claim notice and proof of loss** — §3.2.1 requires `written proof of claim … submitted to Us in
accordance with the provisions of this Policy`, and no such provisions exist (D9(e)). No deadline,
  no form, no addressee, no consequence of late notice.
- **Payment timing** — nothing says when a benefit becomes payable once a claim is accepted.
- **Cancelation notice, cure period, and premium refund** — §1.2 cancels; nothing says whether notice is
  required, whether the insured may cure, or whether unearned premium is returned (relevant because
  §3.5.1 requires the entire year's premium up front).
- **Renewal** — §3.6 fixes a one-year term with no renewal or non-renewal mechanism, while §1.1(2)'s
  `the applicable premium for the policy period` implies renewable periods.
- **Age eligibility at inception** — §2.1(5) excludes claims at age ≥ 80 but the policy has no maximum
  issue age, so a 79-year-old may pay a full year's premium up front and lose coverage mid-term on a
  birthday, with no refund provision.

---

## What this means for the benchmark

Five of the nine queries in `fixtures/queries.json` have gold answers that depend on a defect above
rather than on the artifact's plain meaning:

| query | gold | the defect its gold answer rests on                                                                                         |
| ----- | ---- | --------------------------------------------------------------------------------------------------------------------------- |
| 3     | Yes  | **D3** — cites §1.1(3) and ignores §1.2, which the in-effect test incorporates by reference                                 |
| 4     | No   | **D7** — needs cancelation to be retroactive, or needs a hospitalization date the query omits; also **D5**                  |
| 5     | No   | **D15** — turns wholly on `accidental injury`, a term the artifact never defines and no §2.1 exclusion covers               |
| 6     | No   | **D5** — the visit-date limb of §1.3 is unstated, so the wellness limb is under-determined (skydiving still disposes of it) |
| 9     | Yes  | **D4** — requires the causal reading of §2.1(4) while query 2's gold requires the status reading of §2.1(5)                 |

The pattern is consistent: the answer key resolves each of the artifact's ambiguities in one direction
without recording the choice, so a model or encoder that resolves it the other way — often the more
textually faithful way — is scored as having reasoned badly. Because the paper's headline result is
that guided Prolog encoding reaches **1.00** on this set (`queries.json → paper_results.guided_prolog`),
and the guided pipeline (`A33-guided.txt`) supplies the encoder with a **pre-specified fact vocabulary
and supporting predicates**, a substantial part of what that vocabulary contributes may be the
disambiguation decisions the source document declines to make. Any measurement built on this fixture
inherits D1–D20; a reported accuracy difference between two approaches on these nine items may register
which approach happened to guess the answer key's readings.

**Minimum repairs before reuse:** resolve `Section 5` (D2), add the pendency carve-out to §1.2 or delete
the redundant test (D3), re-cast §2.1(5) as a separate clause outside the causal chapeau (D4), state
which of §1.3's two deadlines "timely" measures (D5), fix the cancelation effective date (D7), and
either define `sickness or accidental injury` or drop query 5 (D15).
