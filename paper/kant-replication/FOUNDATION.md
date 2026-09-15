# Foundation phase — replicating Kant et al. 2025 (arXiv 2502.17638) with L4 as the target language

**Status: foundation phase complete, measurement phase NOT started.** Nothing in this document
reports an L4-vs-Prolog accuracy comparison, because none has been run. What this phase produced is
the apparatus for one: a blind reference encoding, an audit of the benchmark's answer key, an audit
of the benchmark's source document, and a capability probe of the target language. Section 5 is the
proposed design for the measurement phase; it is a proposal, not a description of work done.

**Date:** 2026-08-31. **Run tree:** `/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/c1881847-0452-4e2d-bab9-49cb2315f002/scratchpad/kant-repl/`

**How to read the evidence markings.** Claims below are marked:

- [**verified**] — re-run or re-read by the consolidating agent, in this tree, at consolidation time.
  Commands and file:line references are given so the check is repeatable.
- [**sub-agent**] — reported by a sub-agent (the gold-label auditor, the fixture auditor, the L4
  prober, or one of the three encoders) and not independently re-derived here. Treat as a lead, not
  a fact.
- [**external**] — a claim about law or about the outside world that cannot be checked in this tree
  at all.

The distinction matters most in §1.4 and §4, where the argument turns on legal readings that no
command can settle.

---

## 0. What this phase did, in one page

The paper measures LLM accuracy at encoding one insurance policy into Prolog, in three arms
(vanilla / unguided / guided), scored against a nine-question answer key the paper's own authors
wrote. We are re-running it with L4 in place of Prolog. Before running anything, we did four things:

1. **Adversarially audited all nine gold labels** — asking of each, not "is this defensible?" but
   "what is the best available argument that the published answer is wrong?"
2. **Audited the policy fixture itself** for defects, independently of anyone's encoding of it.
3. **Probed L4** against the specific things this policy asks a language to express.
4. **Built three independent reference encodings** — three different house styles, by three
   encoders who were not shown the answer key — and only then compared their answers to the key.

The headline results:

- The paper's ground truth is **nine labels and nothing else**. Appendix A.2 gives each query
  followed by `Answer: "Yes."` or `Answer: "No."` — no clause citation, no rationale, no record of
  any interpretive choice. [**verified:** `scratchpad/kant.txt:747-770`]
- **Two independent measurements put a third of the key beyond the mechanical.** The gold auditor
  classed 7 of 9 as mechanical and 2 (Q4, Q5) as interpretive, and judged Q5's published label
  **not defensible**. The three blind encoders, working separately, each marked exactly the same
  three items — **Q4, Q5, Q9** — as "required a judgement". The union is 3 of 9.
- **The paper's own error analysis names the same three items.** Of its best vanilla model it says:
  _"errors mostly in Question 5, and it consistently failed to answer Questions 9 and 4"_
  [**verified:** `kant.txt:296-299`]. Three independent lines of evidence — an adversarial legal
  audit, three blind encoders, and the paper's own qualitative results — converge on {4, 5, 9}.
- **All three encodings scored 8/9 against the key, and all three missed the same one: Q4.**
  [**verified** by execution — see §1.3]. We think the encodings are right and the key is
  contestable there, and we set out why rather than deferring to the published label.
- **The fixture is a badly drafted document**: 20 recorded defects, including no insuring clause at
  all, two live cross-references to a section that does not exist, and a five-item exclusion list
  whose fifth item is not the same kind of thing as the other four. Five of the nine gold answers
  rest on one of those defects rather than on the document's plain meaning.
- **L4 expresses this policy more faithfully than Prolog did** — but the one convention the paper's
  own prompt imposes (all times relative to the effective date, so no date arithmetic is needed) is
  precisely the convention that disarms L4's main advantage. That is a threat to our measurement,
  not a point in our favour, and §5 treats it as one.

---

## 1. Where does the gold standard come from?

This is the central question, and the answer is uncomfortable enough to state bluntly: **the ground
truth is one team's unrecorded reading of an ambiguous document, published as nine bare labels.**
Every accuracy figure in the paper — 0.78 vanilla, 0.41–0.89 unguided, 1.00 guided — is a distance
from that reading.

### 1.1 What the key literally is

Appendix A.2 is titled _"Queries and Correct Answers for Empirical Evaluation on Chubb Contract"_.
Its entire content is a stipulated preamble plus nine query/answer pairs of this form
[**verified:** `kant.txt:747-770`]:

> All queries are preceded by the disclaimer: "Assuming all other conditions are met and no other
> exclusions apply (where by 'other,' I mean anything not referenced in the query that follows),…"
>
> Query 1: "will my policy apply if I was hospitalized by burns suffered while doing my duty as a
> firefighter?" Answer: "No."

There is no clause citation, no reasoning, and no note of any choice made. **The `paper_rationale`
fields in our own `fixtures/queries.json` are reconstructions, not transcriptions** — they were
written by whoever built the fixture, and the paper contains no such field. [**verified** by
diffing `fixtures/queries.json` against `kant.txt:747-770`]. Anywhere below where a "paper
rationale" is discussed, it is our reconstruction of the most likely reasoning, and it is fair to
the paper only in the sense that it is the strongest reading we could build for it.

That absence is itself the first finding. A key that records only its outputs cannot be audited,
cannot be disagreed with in detail, and cannot tell a downstream user which of its labels were hard.

Three further properties of the key are worth naming:

- **It is self-authored and self-scored.** The paper's authors wrote the policy excerpt (Appendix
  A.1, an anonymised and abridged Chubb form), wrote the queries, and wrote the answers. There is no
  external adjudication — no court, no claims manual, no independent panel.
- **Scoring was partly manual, over code that did not always run.** Footnote 3:
  _"The generated encodings often failed to run on SWISH due to its ambiguity. In such cases, we
  manually reasoned through the policy encodings and evaluated the claims."_ [**verified:**
  `kant.txt:274-277`]. So an unknown fraction of the reported Prolog accuracy is a human reading of
  non-executable Prolog, scored against a human-authored key, by the same humans.
- **The preamble does real work and cuts both ways.** "Assuming all other conditions are met and no
  other exclusions apply… where by 'other,' I mean anything not referenced in the query" is what
  makes the questions answerable at all — it clears away the signature, the premium, the term, and
  the four exclusions each query does not name. It is also, on Q4, the instruction that our encoders
  followed to an answer the key disagrees with (§1.3).

### 1.2 How much of the key is mechanical, and how much interpretive

Two measurements, taken by teams that did not see each other's work.

**Measurement A — adversarial audit of the labels.** For each query the auditor was asked to
construct the strongest case _against_ the published answer, then say whether the label survives.

| Q   | gold | class            | gold defensible?            | what decides it                                                        |
| --- | ---- | ---------------- | --------------------------- | ---------------------------------------------------------------------- |
| 1   | No   | mechanical       | yes                         | 2.1(3), an express exclusion the query names                           |
| 2   | Yes  | mechanical       | yes                         | 2.1(5), 78 < 80                                                        |
| 3   | Yes  | mechanical       | yes                         | 1.1(3) "still pending" at month 5                                      |
| 4   | No   | **interpretive** | yes, on the query's grammar | when the hospitalization occurred — a fact the query omits             |
| 5   | No   | **interpretive** | **NO**                      | the boundary of "accidental injury", a term the document never defines |
| 6   | No   | mechanical       | yes                         | 2.1(1), skydiving named in the query                                   |
| 7   | Yes  | mechanical       | yes                         | nothing fires; both volunteered facts are favourable                   |
| 8   | No   | mechanical       | yes                         | 2.1(2), military                                                       |
| 9   | Yes  | mechanical       | yes                         | 2.1(4) needs a causal nexus; a son's bite supplies none                |

Seven mechanical, two interpretive, one label the auditor judged **not defensible**. [**sub-agent**]

**Measurement B — the blind encoders.** Three encoders each built a full L4 module from the policy
text alone, then answered the nine queries from their own encoding, and each labelled every answer
`direct` or `required-a-judgement`. All three returned the **same** partition, independently:

|         | Q1     | Q2     | Q3     | Q4            | Q5            | Q6     | Q7     | Q8     | Q9            |
| ------- | ------ | ------ | ------ | ------------- | ------------- | ------ | ------ | ------ | ------------- |
| inert   | direct | direct | direct | **judgement** | **judgement** | direct | direct | direct | **judgement** |
| record  | direct | direct | direct | **judgement** | **judgement** | direct | direct | direct | **judgement** |
| guarded | direct | direct | direct | **judgement** | **judgement** | direct | direct | direct | **judgement** |

**Measurement C — the paper's own results, which we did not solicit and which agree.** Of
O1-preview in the vanilla arm the paper says [**verified:** `kant.txt:296-299`]:

> The vanilla LLM, in comparison, had a slightly lower average accuracy of 0.88 ± 0.02, **with
> errors mostly in Question 5, and it consistently failed to answer Questions 9 and 4.**

The three items the paper's strongest vanilla model gets wrong are exactly the three our encoders
flagged blind, and a superset of the two the auditor classed interpretive. Three methods, one
answer: **{4, 5, 9} is where this benchmark's ground truth stops being mechanical.**

**Two arithmetic observations about the published numbers**, offered as leads rather than findings:

1. Five of the seven vanilla models — Mistral-large, Gemini-1.5-pro, Claude-3.5-sonnet,
   Llama-3.1-405B, GPT-4o — score **exactly 0.78**, and the paper calls this _"a consistent accuracy
   of 0.78"_ [**verified:** `kant.txt:316-317`]. 7/9 = 0.7778. Five model families from five
   vendors miss exactly two of nine, with no variance across ten trials. The natural explanation is
   that two specific items are systematically decided the other way by every capable model — which
   is what you would expect if the key resolves an ambiguity against the reading a competent reader
   reaches. **The paper does not report which two.**
2. The narrative and the number for O1-preview vanilla do not reconcile. Failing Q4 and Q9
   _consistently_ caps accuracy at 7/9 = 0.78 before Q5's errors are counted, yet 0.88 is reported.
   Either "failed to answer" denotes something other than a scored miss (plausibly the "I do not
   know" option the vanilla prompt offers — `prompts/A31-vanilla.txt`), or the qualitative text and
   the table disagree. Either way, **the per-item data needed to interpret the aggregate is not
   published**, which is the direct source of design requirement R1 in §5.

### 1.3 The one disagreement — Q4 — and why we think the key is contestable, not our encodings

All three encodings answer **Yes** to Q4; the key says **No**. That is the only disagreement, and it
is unanimous. [**verified** by execution:

```
L4=/Users/mengwong/src/legalese/l4wt/callgraph-materiality/dist-newstyle/build/.../l4
JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/callgraph-materiality/jl4-core/libraries \
  $L4 run runs/encodings/apply-{inert,record,guarded}.l4
```

→ each yields `FALSE TRUE TRUE TRUE FALSE FALSE TRUE FALSE TRUE` for Q1..Q9, i.e.
No/Yes/Yes/**Yes**/No/No/Yes/No/Yes.]

The query is:

> "will my policy apply if I was hospitalized due to a fall while traveling abroad and I had given
> confirmation of my wellness visit 8 months after the policy's effective date?"

**The query never says when the hospitalization occurred, and clause 1.1 makes that the operative
moment.** 1.1 conditions payment on "the policy being in effect **at the time of the
hospitalization**", and 1.1(3) is satisfied while the 1.3 condition "is still pending". Before the
month-7 deadline the condition is pending, so the policy is in effect, so the claim is good — no
matter how late the confirmation eventually arrives. After month 7 it is not.

So the answer is a function of a fact the query omits, and each encoder resolved it by applying the
benchmark's own preamble mechanically. From `apply-inert.l4:69-72`:

```
-- Q4: … The month of the hospitalization is not referenced, so it takes the
--     favourable default (month 3): before month 7 the 1.3 condition is still
--     pending, so the late confirmation has not yet caused a cancelation.
q4 MEANS mkclaim 3 `Accidental injury` 40 (LIST `A cause not named in Section 2.1`) (JUST 1) (JUST 8) NOTHING NOTHING
```

**The guarded arm shipped the counterfactual in the same file, so the sensitivity is measured, not
argued.** `apply-guarded.l4:55-61` runs Q4 at month 7 and Q4b at month 9, identical in every other
respect:

```
`Q4 claim`  MEANS `a claim` `accidental injury` 7 40 `no named cause` (JUST 6) (JUST 8) FALSE FALSE FALSE
`Q4b claim` MEANS `a claim` `accidental injury` 9 40 `no named cause` (JUST 6) (JUST 8) FALSE FALSE FALSE
```

→ `Q4` = TRUE, `Q4b` = FALSE [**verified:** evaluations 4 and 5 of `apply-guarded.l4`]. The record
arm's `S4 fall abroad, hospitalization in month 9` does the same and also returns FALSE
[**verified:** evaluation 12 of `apply-record.l4`, source at `apply-record.l4:334-352`].

**Verdict: the encodings are correct and the key is contestable.** Specifically:

- The encodings are not wrong on their own terms. They applied the stipulated preamble — set every
  unreferenced fact to the value that lets the policy apply — to a fact the query does not reference.
  That is the rule the benchmark states.
- The best case for the key is grammatical, and it is a real argument: the query's pluperfect ("I
  **was hospitalized** … and I **had given** confirmation … 8 months after") sequences the
  confirmation _before_ the hospitalization, which puts the hospitalization after month 8, after
  cancellation. [**sub-agent** — this is the gold auditor's reasoning, and it is why that auditor
  rated Q4 defensible.]
- But that argument comes from the tense of the question, not from the policy, and **it points the
  opposite way to the benchmark's own preamble.** A system that follows the stated instruction is
  penalised; a system that instead parses English aspect is rewarded. That is not a measurement of
  legal reasoning.
- Corroboration that the gap is real and not our invention: the paper attributes O1-preview's Q4
  miss to _"ambiguity in encoding time-based conditions"_ [**verified:** `kant.txt:299-301`] — i.e.
  the paper noticed the symptom and diagnosed it as the encoder's problem rather than the query's.

**The honest score for Q4 is "under-determined".** We will report it both ways in the measurement
phase (§5, R2) rather than silently adopting either label.

### 1.4 Q5 — the label we think is wrong

This is the one place the audit says the published answer is **not defensible**, and it deserves to
be stated plainly rather than hedged.

> Q5: "will my policy apply if I was hospitalized for punching my own face to show off for my
> friends and I did not commit fraud or misrepresentation?" — **Answer: "No."**

After the preamble, exactly one thing can produce "No": a narrow reading of 1.1's phrase
"hospitalization **for sickness or accidental injury**". Every §2.1 exclusion is stipulated away,
because none is referenced. And **§2.1 contains no intentionally-self-inflicted-injury exclusion at
all** — the drafter enumerated skydiving, military, fire, police and age, and omitted self-harm.
[**verified** against `fixtures/chubb-policy.txt:23-29`].

So the "No" must be produced by construing an undefined term in the coverage grant against the
insured, in a document that has no definitions section whatever
(`grep -iE 'means|defined|definition|shall mean' chubb-policy.txt` → no matches [**verified**]),
while treating the absence of a self-harm exclusion as irrelevant.

The counter-argument, which the auditor found stronger: §3.3.1 makes the policy governed by New York
law, and New York abandoned the accidental-means/accidental-result distinction — the test is whether
the resulting **injury** was unintended from the insured's standpoint, not whether the act was
voluntary. A stunt punch is a deliberate act with an unintended fracture. [**external** — the
auditor cites *Miller v. Continental Ins. Co.*, 40 N.Y.2d 675 (1976); we have not verified the
citation or its holding, and it must be checked before this appears in anything published.]

Both encodings that answer "No" here do so by giving the claim a `Hospitalization Ground` /
`Basis of the hospitalization` constructor meaning "neither sickness nor accidental injury" — that
is, **the answer is set in the fact record, not derived by any rule.** The guarded arm shipped the
counterfactual: `Q5b claim` is identical but typed `accidental injury`, and returns TRUE
[**verified:** evaluations 6 and 7 of `apply-guarded.l4`, source at `apply-guarded.l4:63-71`]. The
record arm's `S5` does the same and also returns TRUE [**verified:** evaluation 10].

So on Q5 the benchmark is scoring the marshalling step, not the encoding step, and the label it
scores against is — on our audit — the weaker of the two readings under the policy's own choice of
law. The paper itself reports that its best model missed Q5 in **9 of 10 trials**
[**verified:** `kant.txt:290-296`], and diagnoses it as the model failing "to identify the primary
cause of the claim — whether it was sickness or accidental injury, **which are addressed indirectly
in the contract**". The paper's own words concede the term is not defined.

### 1.5 What this means for using "correctness" as an RL reward

The paper's §5 proposes [**verified:** `kant.txt:519-530`]:

> Our third proposal is to improve LLMs' ability to generate accurate Prolog encodings by
> incorporating reinforcement learning (RL) with synthetic data and feedback from a Prolog
> interpreter. One potential approach is to use RL with reward modeling, where the LLM generates
> logical encodings, executes them in a Prolog interpreter like SWISH, and receives **a reward
> signal based on correctness, consistency, and execution success**.

Three reward components. Two of them are unimpeachable:

- **execution success** is a property of the artifact — it runs or it does not;
- **consistency** is a property of the model — the same input gives the same output.

Neither needs a key. **Correctness does**, and on this benchmark correctness means _agreement with
nine unexplained labels, of which at least one is, on our audit, the weaker reading and at least one
is under-determined by its own query._

What follows is not "the paper is wrong to want a reward signal". It is that **this particular
signal rewards the wrong behaviours, and does so precisely on the items that distinguish a careful
encoder from a careless one:**

- **Q3 penalises reading the whole document.** The key's route to "Yes" runs through 1.1(3)'s "still
  pending". But 1.1(4) requires that the policy "has not been canceled", and 1.2 deems cancellation
  where the 1.3 condition "has not been satisfied in a timely fashion" — with no pendency carve-out.
  Read literally, 1.1(3) and 1.1(4) return opposite answers on the same month-5 fact, and an encoder
  that lowers 1.2 faithfully answers **No**. It is marked wrong for having read the clause that
  1.1(4) incorporates by reference. (Fixture defect **D3**; the same contradiction reappears in the
  L4 probe as two named readings that agree everywhere except on `Pending` — §3.2.)
- **Q4 penalises noticing that a fact is missing.** The operative clause needs a date the query does
  not supply. The correct output is "it depends when you were hospitalized"; the reward says No.
- **Q5 penalises noticing that a term is undefined and an exclusion absent.** The reward is for
  importing a self-harm exclusion the drafter did not write.
- **Q9 penalises a status reading of an exclusion list — while Q2 rewards one.** Q9's gold needs
  2.1(4) to be _causal_ ("a son's bite does not arise out of police service"); Q2's gold needs
  2.1(5) to be a _status bar_ (age ≥ 80, whatever the cause). Both are correct, but they are not
  both available from a uniform reading of a list the drafter presented under one chapeau with one
  connective. An encoder that lowers all five items uniformly — the more faithful thing to do given
  the surface form — must lose one of the two. (Fixture defect **D4**.)

Gradient-descending on that signal teaches a model to **guess the annotator's disambiguation**. In
a domain whose entire value proposition is that ambiguity gets surfaced rather than resolved
silently, that is close to an inverted objective.

Three constructive implications, which we carry into §5:

1. **Split the reward.** Execution success and consistency are cheap, objective, and safe to
   optimise. Correctness against an interpretive label is neither and should be weighted separately,
   if used at all.
2. **A key must ship its reasoning.** The minimum viable artifact is not `Answer: "No."` but
   `Answer: "No." because §X, on reading R, where the competing reading R' gives "Yes"`. Our
   ambiguity register (§4.2) is that artifact for our own encoding, and we will hold any extended
   query set to the same bar.
3. **Reward "I do not know" where the document is silent.** The vanilla prompt already offers three
   options — `"Yes"`, `"No"`, `"I do not know"` (`prompts/A31-vanilla.txt`) — and then the key
   permits only two. On Q4 the third option is the correct one, and the scoring cannot express it.

---

## 2. What the source fixture itself gets wrong

Twenty defects, in the policy text, independent of anybody's encoding of it. Full report with
verbatim quotations and line references: `runs/source-defects.md` (652 lines). [**sub-agent**], with
the specific items marked below re-checked here.

The fixture is `fixtures/chubb-policy.txt` — 54 lines, 3,573 bytes, Appendix A.1 of the paper. It is
three sections, two flat enumerations, and no definitions.

### 2.1 The four that change answers

**D1 — There is no insuring clause.** Nothing in the document says what benefit is payable, in what
amount, or on what trigger. §1.1 says only that "the payment of any benefit … is **conditioned on**"
the policy being in effect; §2.1 says when the policy "will not apply". The document specifies when
it is in force and when it does not apply, and never what it does.
`grep -nE '\$|percent|%' chubb-policy.txt` finds no monetary amount anywhere [**verified**]. The
only affirmative statement that the policy does anything is §3.1.1 — "insures You twenty-four (24)
hours a day anywhere in the world" — which names a time and a place and no peril and no payment.

Consequence: every encoder must **invent** the insuring clause as "covered ⟺ in-effect ∧ ¬excluded".
All four "Yes" golds (Q2, Q3, Q7, Q9) are therefore derived from the _absence_ of a firing exclusion,
not from any grant. A reader who answers "I do not know" because the document never says what the
policy pays is scored wrong on 4 of 9 items.

**D3 — §1.1(3) and §1.2 disagree during the pendency window.** The §1.3 condition is tested twice,
in different words: 1.1(3) is satisfied by "still pending **or** … satisfied in a timely fashion";
1.2 deems cancellation where the condition "has **not** been satisfied in a timely fashion" — with
no pendency carve-out. At month 5 both fire, so 1.1(3) holds and 1.1(4) fails on the same fact. The
`still pending` disjunct appearing in one clause and not the other is the signature of a drafter who
saw the problem and repaired it in one of the two places. **Decides Q3.**

**D4 — §2.1's fifth item does not fit its own chapeau.** The chapeau is "…any event causing sickness
or accidental injury arising directly or indirectly out of:", items 1–4 are bare noun phrases, and
item 5 is a finite conditional: "5. If your age at the time of the hospitalization is equal to or
greater than 80 years of age." [**verified:** `chubb-policy.txt:23-29`]. Substituted into the
chapeau it is not a sentence. So items 1–4 must be read causally and item 5 as a flat status bar,
and **nothing in the text signals the switch**. Q9's gold needs the causal reading; Q2's gold needs
the status reading. **Decides Q2 and Q9 jointly.**

**D7 — Cancellation has no effective moment.** §1.2 says cancellation "will be deemed to have
occurred if…" and never says when. Prospective, retroactive-ab-initio, and on-declaration are all
available; there is no notice provision, no cure period, no refund, and no reinstatement clause.
Since §1.1 fixes the test at "the time of the hospitalization", the cancellation date is
load-bearing and missing. **Decides Q4** — this is the same gap §1.3 above reaches from the other
side.

**D15 — No definitions section, and the missing definitions are the ones that decide items.** No
`means` / `defined` / `shall mean` anywhere [**verified**]. Undefined and operative:
`benefit` (D1), `sickness` / `accidental injury` (**decides Q5**), `hospitalization`,
`still pending` (**decides Q3**), `in a timely fashion` (two candidate deadlines — D5),
`the Company` (used exactly once; the insurer is defined as "us"), `wellness visit`,
`qualified medical provider`, `dispute` / `disagreement` / `difference`, `unable to settle`.

### 2.2 The rest, in brief

| #       | defect                                                                                                                                                                                                                                                                                                                                                                                                                                                | clause             |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| D2      | Two live cross-references to a "Section 5" that does not exist; the document's highest section is 3. Both are the money-and-time clauses (term expiry; premium).                                                                                                                                                                                                                                                                                      | 1.2, 3.5.1         |
| D5      | "in a timely fashion" names one deadline; §1.3 contains two (visit by month 6, confirmation by month 7). No query supplies a visit date, so a _more_ faithful encoding cannot answer Q4, Q6 or Q9.                                                                                                                                                                                                                                                    | 1.1(3), 1.2 vs 1.3 |
| D6      | The fraud clause has four faults in one sentence: "material" scope-ambiguous; "withholding of any information **provided by you**" is self-contradictory; "the Company" undefined; "there is fraud" binds no actor and no time.                                                                                                                                                                                                                       | 1.2                |
| D8      | A Singapore statute — "the Arbitration Act (Cap. 10)" — cited in a policy governed by the laws of New York. Template residue the anonymisation missed.                                                                                                                                                                                                                                                                                                | 3.2.1 vs 3.3.1     |
| D9      | §3.2.1 alone: "such parties" has no antecedent; "dispute or **difference**" drifts mid-clause; a rights-extinguishing clock runs from an unascertainable day; mandatory arbitration is stacked on a 60-day suit bar; "written proof of claim … in accordance with the provisions of this Policy" points at provisions that do not exist.                                                                                                              | 3.2.1              |
| D10     | "at the signing of the policy" — the document has two distinct signing events (1.1(1) yours, 3.6 ours, which fixes the effective date).                                                                                                                                                                                                                                                                                                               | 3.5.1              |
| D11     | §3.1.1 grants coverage unqualified, with no "subject to the terms, conditions and exclusions" saver.                                                                                                                                                                                                                                                                                                                                                  | 3.1.1              |
| D12     | Items 1–4 are tested at the time of the **event**; item 5 expressly at the time of the **hospitalization**. No rule for the gap.                                                                                                                                                                                                                                                                                                                      | 2.1                |
| D13     | §3.6 is the only subsection with its heading run into its body and no `N.N.N` child — so any chunker keyed on the pattern the other five establish **silently drops the clause that defines the effective date**.                                                                                                                                                                                                                                     | 3.6                |
| D14     | 1.2 defines cancellation by reference to the term; 3.6 defines the term by reference to cancellation. Mutual recursion, one leg of which is D2's dangling reference.                                                                                                                                                                                                                                                                                  | 1.2 / 3.6          |
| D16–D20 | Doubled "and" in §1.1's list; defined-term casing not observed ("We"/"Our" never appear); §1.3's cataphoric "the medical provider in question" precedes its own antecedent, and is drafted as a covenant while relied on as a condition; §3.4.1's unbounded "or someone else" names a payee the document never creates; and there are no claim-notice, proof-of-loss, payment-timing, cancellation-notice, cure, refund or renewal provisions at all. | various            |

### 2.3 The bottom line for the benchmark

Five of nine gold answers rest on a defect rather than on plain meaning: **Q3** on D3, **Q4** on D7
(and D5), **Q5** on D15, **Q6** on D5 (though skydiving disposes of it anyway), **Q9** on D4. The
pattern is consistent: the key resolves each ambiguity in one direction and records nothing, so an
encoder that resolves it the other way — often the more textually faithful way — is scored as having
reasoned badly.

Minimum repairs before this fixture is reused for anything: resolve "Section 5" (D2); add the
pendency carve-out to §1.2 or delete the redundant test (D3); re-cast §2.1(5) as a clause outside
the causal chapeau (D4); say which of §1.3's two deadlines "timely" measures (D5); fix the
cancellation effective date (D7); and either define "sickness or accidental injury" or drop Q5
(D15). **We are deliberately NOT applying these repairs** — the replication must run against the
paper's fixture as published, or it is not a replication. The repaired fixture is a candidate for a
separate, clearly-labelled arm (§5, R6).

---

## 3. What L4 can and cannot express here

Full probe with commands and outputs: `runs/l4-probe.md`; probe sources in `runs/probe/`. Binary
used: `/Users/mengwong/src/legalese/l4wt/callgraph-materiality/dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4`,
with `JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/callgraph-materiality/jl4-core/libraries`.

**Headline.** L4 expresses this policy more faithfully than the Prolog encodings the paper studied,
and the reason is not raw expressiveness. It is that the three things the paper found Prolog
smuggling past the reader — a calendar approximation, a two-valued reading of a three-valued
condition, and a homogeneous reading of a heterogeneous list — become things you have to _write
down_. But two of the four failure classes the paper observed survive into L4, one of them entirely,
and the paper's own prompt convention neutralises L4's best defence against a third. All three are
stated below as gaps.

### 3.1 What it does natively

- **Month-granular calendar arithmetic**, with the end-of-month convention documented and
  cross-validated. `jl4-core/libraries/daydate.l4:406` defines `add months`, `:421` `add years`
  [**verified**], and the comment at `:382-401` records that the day-clamp is what Excel's EDATE
  does and what FEEL's `date + duration("P1Y")` does on Drools/KIE 8.44.0 and Camunda 8.7.6,
  measured 2026-08-05 [**sub-agent** for the cross-engine measurement; the comment itself is
  [**verified**]]. So "the 6th month anniversary" is a computation with a recorded convention, not a
  guess. The probe shows the three candidate readings of a six-month anniversary of 31 Jan 2025
  diverging — 31 July (month-correct), 1 August (6 × average month), 30 July (180 days)
  [**sub-agent:** `runs/probe/p1-months.l4`].
- **Three-valued conditions**, either as a constitutive enum (`Pending` / `Satisfied timely` /
  `Missed`, derived from an assessment date) or via the regulative layer's native
  pending/fulfilled/breached. `MAYBE DATE` distinguishes "no visit" from "a late visit", which
  Prolog's negation-as-failure conflates.
- **DST-aware instants.** §1.2's "midnight, US Eastern time then in effect" is directly expressible;
  `jl4-core/libraries/timezone.l4` maps both `EST` and `EDT` to `America/New_York` so the tz
  database picks the offset for the actual date [**sub-agent:** `runs/probe/p6-cancellation-instant.l4`].
  Note this clause is **unencodable at all** under the paper's relative-months convention, which has
  no calendar and no zone.
- **Heterogeneous exclusion lists without flattening.** Items 1–4 take a `Hazardous activity`; item
  5 takes a `NUMBER` of years. There is no type at which all five are the same predicate, so the
  mismatch sits in the `DECLARE` where a reader sees it, and the two readings of item 5 can be
  written side by side as two named functions and their divergence exhibited on a witness fact
  [**sub-agent:** `runs/probe/p3-heterogeneous-list.l4`].

### 3.2 The contradiction the language forces into the open

Writing 1.1(3) three-valued exposes **D3** mechanically rather than as a matter of judgement. The
probe defines both readings of 1.2 and evaluates them on the same facts:

```l4
`1.2 cancels -- literal reading`                    MEANS NOT (`condition 1.3 status` f EQUALS `Satisfied timely`)
`1.2 cancels -- reading harmonised with 1.1(3)`     MEANS      `condition 1.3 status` f EQUALS Missed
```

They agree everywhere except on `Pending`, where the literal reading returns TRUE and the harmonised
one FALSE [**sub-agent:** `runs/probe/p2-threestate.l4`, evaluations 5 and 6]. That is exactly the
Q3 fork of §1.5, produced by the encoding rather than by an auditor.

### 3.3 The gaps — stated as gaps

**GAP 1 — `AND` for `OR` typechecks. The type system does not catch the paper's most-cited Prolog
failure.** DeepSeek-R1's documented error was treating §2.1's exclusions as conjunctive
[**verified:** `kant.txt:302-310`]. In L4 both versions are `BOOLEAN`-typed and both pass the
checker:

```
$ l4 check runs/probe/p4a-and-for-or.l4
Check succeeded.        (exit 0)
```

[**verified** — re-run at consolidation; exit 0.] Only a scenario test catches it: `l4 run` on the
same file evaluates the buggy conjunctive rule to FALSE on a plain skydiving claim and reports
`assertion failed`. **This is an argument for the negotiation-time test suite, not an argument
about types**, and it should not be sold as one.

**GAP 1a — a failed `#ASSERT` does not set a non-zero exit code.**
`printf '#ASSERT FALSE\n' > z1.l4 ; l4 run z1.l4 ; echo $?` → **0** [**verified** at consolidation].
The failure is machine-readable in the JSON envelope (`results[].value == false`, plus a
`DiagnosticSeverity_Error` diagnostic) but a CI step that checks only the exit status will not see
it. By contrast a check or parse error under `l4 run` _does_ exit 1. **Any harness we build must
parse `--json`, not trust `$?`.**

**GAP 2 — the paper's own prompt convention disarms the type checker.**
`prompts/A32-unguided-policy.txt` instructs: _"Assume that all dates/times in any query to this code
(apart from the claimant's age) will be given RELATIVE to the effective date … there will never be a
need to calculate the time elapsed between two dates."_ Under that convention "months since the
effective date" and "age in years" are both plain `NUMBER`s, and passing one where the other belongs
is silent:

```
$ l4 run runs/probe/p4b2a-unwrapped.l4
Result: TRUE            (exit 0, no diagnostics)
```

[**verified** at consolidation.] The file asks whether an insured is 80 or over and hands it 84
_months_. The policy excludes the claim and nothing complains. With honest types — real `DATE`s, or
nominal wrappers `Years of age` / `Months elapsed` — the same mistake is a check-time error
[**sub-agent:** `runs/probe/p4b-date-for-age.l4`, `p4b2-units.l4`]. **The convention adopted to make
Prolog tractable is the one that removes L4's advantage**, and §5 treats that as the sharpest threat
to the measurement rather than as a point scored.

**GAP 3 — absolute deontic deadlines (`BEFORE`) are not implemented.** The regulative layer's
`WITHIN` window always starts when its obligation becomes active, so nesting §1.3's two deadlines
silently converts an _absolute_ 7-month deadline into a 7-month window running from the wellness
visit — a different contract. Measured: with the visit at tick 120, confirmation at tick 300 is
FULFILLED (300 − 120 = 180 < 212) even though 300 is past the absolute deadline [**sub-agent:**
`runs/probe/p5-regulative.l4`]. This is documented, not a surprise:
`doc/reference/regulative/README.md:46` — `| BEFORE | Temporal deadline (absolute) | Not implemented |`
and `:406` — `## BEFORE (NOT YET IMPLEMENTED)`; `doc/concepts/legal-modeling/regulative-rules.md:185` —
_"There is no special syntax for anchoring a deadline to a named event"_ [**all three verified**].
**Consequence for this policy: clause 1.3 must be encoded constitutively, not regulatively.** All
three reference encodings did so. The regulative form is right only for §3.2.1's arbitration timer,
whose window genuinely is event-relative.

**GAP 4 — a missing branch over an enumerated ground is a warning, not an error.** A `CONSIDER` that
omits one of five exclusion grounds produces `The following branches still need to be considered:`
and then `Check succeeded.` at exit 0; `l4 run` reports the unhandled value at runtime and still
exits 0 [**sub-agent:** `runs/probe/p4e-nonexhaustive.l4`; consistent with the `@nonexhaustive`
annotation at `jl4-core/src/L4/TypeCheck.hs:659`]. So "did you handle every exclusion ground?" is a
real guarantee but an advisory one; enforcing it means treating warnings as errors in the harness.

**GAP 5 — a syntax trap not previously recorded: an `IMPORT` after a `§` section heading is silently
ineffective.** You get a cascade of "could not find a definition" errors for every library name,
which reads like a library-path problem and is not [**verified** at consolidation: the `§`-first
file produces the not-found error, the `IMPORT`-first file evaluates `Days in a week` to `7`].
Names do not become section-qualified either. **Put every `IMPORT` before the first `§`.** This
belongs in the `l4-syntax-traps` memory; it is not there.

### 3.4 Scorecard against the four Prolog failure classes the paper observed

| #   | failure class                                           | caught by L4?                                                                                                     | how                   |
| --- | ------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------- |
| a   | exclusions conjunctive where the text means disjunctive | **no** at check time; yes at run time _only if_ scenario tests exist                                              | GAP 1                 |
| b   | a date passed where an age was expected                 | **yes** at check time when the quantities are honestly typed; **no** when both are `NUMBER`                       | GAP 2                 |
| c   | reference to a rule that does not exist                 | **yes** at check time — and it reports the _inferred type_ of the missing definition, which is a usable stub spec | `p4c-missing-rule.l4` |
| d   | syntax error making the file unrunnable                 | **yes** at parse time, with caret, line, and expected-token set; exit 1                                           | `p4d-syntax-error.l4` |

Three of four, and the fourth is exactly the one the negotiation-time-tests thesis is about. Note
that (c) and (d) are the two the paper reports as most common in the unguided arm — "frequent syntax
errors in LLM-generated encodings" [**verified:** `kant.txt:511-513`] — so the measurement phase
should expect the L4 unguided cell to differ from the Prolog unguided cell most visibly there, and
should report _why a cell failed_, not only that it did.

---

## 4. The reference encoding

Three encoders each built a complete L4 module from the policy text, blind to the answer key, in
three different house styles:

| strategy  | file                                        | isomorphism | soundness | verdict        |
| --------- | ------------------------------------------- | ----------- | --------- | -------------- |
| **inert** | `runs/encodings/ref-inert.l4` (526 lines)   | 9           | **8**     | best-candidate |
| record    | `runs/encodings/ref-record.l4` (676 lines)  | 9           | 7.5       | best-candidate |
| guarded   | `runs/encodings/ref-guarded.l4` (536 lines) | 8           | 7         | acceptable     |

Scores are the reviewing auditors' [**sub-agent**]; line counts [**verified**].

### 4.1 Which won, and why

**The inert encoding is the reference.** It leads on both axes and, decisively, **it is the only one
of the three with no confirmed wrong answer on a path the top-level decision actually reaches.**

- The _guarded_ arm carries two confirmed logic errors: it extinguishes the claim while the
  arbitration window is still open, and its "still pending" window runs a month past the point at
  which clause 1.3 has become unsatisfiable (it tests only the month-7 confirmation deadline and
  ignores the month-6 visit deadline, so a claim with a definitively non-conforming visit at month
  6.5 is still treated as pending at month 7). It also silently drops 1.3's provenance and
  qualification requirements — the one undisclosed omission of operative text in any of the three.
- The _record_ arm carries the same arbitration defect plus an **invented lower bound** on
  arbitration commencement: the text states a deadline only, and the encoding adds a floor, so
  arbitration commenced _early_ fails the test and extinguishes the claim. That directly contradicts
  the file's own register entry refusing exactly that move on clause 1.3. Its `NOT` scoping at two
  sites is also carried by indentation alone — currently correct, but re-indenting a continuation
  line by four spaces silently inverts the top-level payability decision, with no type error and no
  test in the file to catch it.
- The _inert_ arm's worst faults are documentation faults: four comments defer to "the ambiguity
  note" / "the ambiguity register", and no such document existed. **§4.2 below is that document**,
  and the pointers in all three files are discharged by it. [**verified:** `grep -rn "ambiguity
  register\|ambiguity note" runs/encodings/*.l4` finds 12 pointers across the three files, and
  `ls runs/` confirmed no register file existed before this one.]

**A convergent finding worth more than the ranking: all three encodings share the same bug.** Every
one of them extinguishes the claim under §3.2.1 while the three-month arbitration window is still
open, because none gives the arbitration limb an "as at" moment — **even though all three built
careful three-valued pendency machinery for clause 1.3**, whose logical shape is identical. The
difference between the two clauses is not logical, it is lexical: **§1.3 is reachable through
1.1(3), which uses the words "still pending", and §3.2.1 says only "If You fail to commence".** You
get a three-valued treatment where the source text names the third value, and a two-valued one where
it does not. Three independent encoders, same omission, same cause.

And the benchmark cannot see it. **No query mentions a dispute**, so all three encodings default the
arbitration facts to inert and all three still score 8/9. A nine-item benchmark scores an encoding
only on the clauses its items happen to exercise, which is the substance of threat T5 in §5.

### 4.2 The ambiguity register

Every interpretive choice recorded by any of the three encoders, deduplicated and consolidated.
**"Divergence" flags a clause where the three arms did not choose alike** — those are the ones a
human should look at first. **"Decides"** names the benchmark item the choice controls, where it
controls one.

Where the register says "all three", that is agreement among our own encoders and carries no weight
beyond three careful readings converging.

#### Document-level

| #   | clause                   | the fork                                                                                                                                                                                      | taken                                                                                                                    | notes                                                                                                                      |
| --- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| A1  | the document as a whole  | There is no insuring clause, so "is a benefit payable" is strictly unanswerable / the text states a complete set of _necessary_ conditions and the answerable question is whether all are met | Necessary-conditions test. TRUE means "nothing in the policy as supplied defeats this claim", not "the insurer owes $X". | All three. Forced by **D1**. Stated in each module header so no reader mistakes the answer for an entitlement computation. |
| A2  | "Section 5" (1.2, 3.5.1) | Drafting error for §3.6 / §3.5 — or an omitted section carrying term, premium and benefit schedule                                                                                            | Read §3.6 for the term. Premium and benefit amounts are unrecoverable and not modelled.                                  | All three. Reading it as unresolvable would make the policy perpetual. **D2.**                                             |

#### Clause 1.1 — the in-effect test

| #   | clause                                                                                          | the fork                                                                                                                                                         | taken                                                                                                                          | notes                                                                                                                                                                                                                                                |
| --- | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A3  | 1.1, "at the time of the hospitalization"                                                       | All four limbs tested at that instant / only limb 4 is temporal                                                                                                  | One clock — the hospitalization month — for all four limbs.                                                                    | All three. The alternative lets a policyholder cure a lapse after the loss. **Load-bearing for Q4.**                                                                                                                                                 |
| A4  | 1.1's numbered list                                                                             | Definitional (iff) / sufficient but not necessary                                                                                                                | Definitional.                                                                                                                  | All three.                                                                                                                                                                                                                                           |
| A5  | 1.1, "the hospitalization **for sickness or accidental injury** on which the claim is premised" | A condition on coverage / a definite description identifying _which_ hospitalization                                                                             | A condition, encoded as its own named limb, with a third enum constructor for "neither".                                       | All three. This is an interpretive **addition**: 1.1 on its face conditions payment on the policy being in effect and does not on its face exclude anything. It is the only defensible reading given **D1**, and it is the limb that **decides Q5**. |
| A6  | 1.1(1), "This agreement is signed"                                                              | By You / by both — and is it vacuous, since 3.6 makes the effective date turn on _our_ signature?                                                                | A plain boolean. Since our signature is entailed by month 0 existing, the only signature 1.1(1) can still be testing is yours. | All three. Stipulated away by the benchmark prompt in any case.                                                                                                                                                                                      |
| A7  | 1.1(2) with 3.5.1                                                                               | 1.1(2) asks only whether the premium was paid; manner and timing are a separate promise / a premium not paid in one lump sum at signing is not "paid" for 1.1(2) | The first. 3.5.1 encoded as its own non-consumed decision.                                                                     | All three.                                                                                                                                                                                                                                           |
| A8  | 1.1(2), "the applicable premium for **the policy period**"                                      | One period (3.6 gives one year) / renewable periods requiring an indexed premium fact                                                                            | One period.                                                                                                                    | inert. Nothing in the text provides for renewal.                                                                                                                                                                                                     |

#### Clauses 1.1(3) and 1.3 — the wellness condition

| #   | clause                                                                                                                   | the fork                                                                                                                                                                                                     | taken                                                                                                                            | notes                                                                                                                                                                                                                                                                                                                                   |
| --- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A9  | 1.1(3), "**still pending**"                                                                                              | Pending while the month-7 deadline has not passed and the condition is unsatisfied / pending only while timely satisfaction remains _possible_, so it fails at month 6 once no conforming visit has occurred | The month-7 reading.                                                                                                             | All three. **The single most consequential choice in the encoding** — it decides every claim between months 6 and 7 with no visit, and it **decides Q3**. Note the guarded arm's auditor called the same choice a boundary error; the other two auditors did not. The disagreement is about the same reading, not about different code. |
| A10 | "satisfied **in a timely fashion**"                                                                                      | Timeliness attaches to both of 1.3's deadlines / only to the supply obligation                                                                                                                               | **Divergence.** inert and record: both deadlines. guarded: one composite obligation with month 7 as its only operative deadline. | **D5.** No query supplies a visit date, so under the both-deadlines reading Q4, Q6 and Q9 are strictly under-determined; each encoder filled the gap from the preamble instead.                                                                                                                                                         |
| A11 | 1.3, "written confirmation **from the medical provider in question**" of a visit "with a **qualified** medical provider" | Both qualifiers operative / descriptive colour                                                                                                                                                               | **Divergence.** inert and record encode both as facts; guarded drops both silently.                                              | Under guarded's encoding a confirmation the insured wrote himself, of a visit to an unqualified provider, satisfies 1.3. **D18.**                                                                                                                                                                                                       |
| A12 | 1.3, lower bound on the visit                                                                                            | Literal: "no later than the 6th month anniversary" is an upper bound only, so a visit predating the effective date qualifies / purposive: it must fall inside the policy period                              | Literal — one bound stated, one bound encoded.                                                                                   | record. Adding a floor would be repairing the drafting rather than encoding it.                                                                                                                                                                                                                                                         |
| A13 | 1.3, ordering                                                                                                            | Confirmation must postdate the visit it confirms / no ordering is stated                                                                                                                                     | No ordering encoded.                                                                                                             | record. Recorded rather than silently repaired.                                                                                                                                                                                                                                                                                         |
| A14 | 1.3, "no later than X"                                                                                                   | Inclusive of X / X is the first late day                                                                                                                                                                     | Inclusive.                                                                                                                       | guarded. The difference here is a whole month, not a day.                                                                                                                                                                                                                                                                               |

#### Clause 1.2 — cancellation

| #   | clause                                                               | the fork                                                                                                                                                   | taken                                                                                                                                                                                                                                                                    | notes                                                                                                                                                                                                                                                               |
| --- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A15 | 1.2, when a deemed cancellation takes effect                         | At the moment of the triggering conduct / _ab initio_, voiding claims already earned / undated, so conduct at any time defeats the claim                   | **DIVERGENCE, and the sharpest one.** inert and record date each ground and require it to precede the hospitalization; **guarded** makes the three conduct grounds undated booleans, so a misrepresentation made _after_ a good hospitalization still defeats the claim. | **D7.** All three are defensible; the text supplies no date. Note the direction: record and inert are pro-insured here, guarded pro-insurer. Not exercised by the nine queries — Q5 and Q8 only _negate_ the fraud limb — so the benchmark cannot distinguish them. |
| A16 | 1.2, scope of "**material**"                                         | "any misrepresentation" OR "material withholding" — the adjective sits on withholding only, so any trivial misstatement cancels / materiality governs both | The adjective on withholding only.                                                                                                                                                                                                                                       | All three. Recorded because it is harsh and probably unintended. **D6(a).**                                                                                                                                                                                         |
| A17 | 1.2, does "provided by you to the Company…" distribute over "fraud"? | Fraud stands alone before the comma, unqualified / the trailing qualifier reaches all three species                                                        | Fraud stands alone.                                                                                                                                                                                                                                                      | record. Read literally this means fraud by anyone, including the insurer, cancels. **D6(d).**                                                                                                                                                                       |
| A18 | 1.2, when cancellation for failure of 1.3 bites                      | Month 7 (the earliest moment it can be _said_ the condition was not timely satisfied) / month 6 / ab initio                                                | Month 7.                                                                                                                                                                                                                                                                 | inert; consistent with A9.                                                                                                                                                                                                                                          |
| A19 | 1.2 with 3.6, the last instant of the term                           | "midnight … on the last day" is inclusive, so month 12 is inside / a period of one year closes at the anniversary, so month 12 is outside                  | **Divergence.** inert: covered iff month < 12. record and guarded: covered iff month ≤ 12.                                                                                                                                                                               | One month apart. Unexercised: no query sits at the boundary.                                                                                                                                                                                                        |

#### Clause 2.1 — the exclusions

| #   | clause                                        | the fork                                                                                         | taken                                                                    | notes                                                                                                                                                                                                                        |
| --- | --------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A20 | 2.1, the five-item list                       | Disjunctive / conjunctive                                                                        | Disjunctive.                                                             | All three. Named explicitly because this is the paper's documented DeepSeek-R1 failure and, per **GAP 1**, the type checker will not catch it.                                                                               |
| A21 | 2.1(5)                                        | Free-standing status bar / read through the causal chapeau                                       | Free-standing.                                                           | All three. Item 5 alone begins "If" and does not parse under the chapeau. **D4. Decides Q2.**                                                                                                                                |
| A22 | 2.1(5), the threshold                         | "equal to or greater than 80" is inclusive / 80 is the first covered age                         | Inclusive — exactly 80 is excluded.                                      | guarded. Q6 (79) and the threshold (80) land on opposite sides.                                                                                                                                                              |
| A23 | 2.1 chapeau, what "arising … out of" modifies | The **event** arises out of the activity / the **sickness or injury** does                       | The event.                                                               | record, guarded. No fact pattern found on which they diverge.                                                                                                                                                                |
| A24 | 2.1(2)–(4), whose service                     | The insured's own / anyone's, so an injury caused by a third party's police service is excluded  | The insured's own.                                                       | inert, record. Under this reading an injury caused by _someone else's_ military, fire or police service is **not** excluded — a live gap on a natural fact pattern. **Bears on Q9.**                                         |
| A25 | 2.1, "**directly or indirectly**"             | One event may arise out of several activities, so the fact is a _set_ / a single proximate cause | A set (`LIST OF Cause`, or four independent booleans in the record arm). | All three. "Indirectly" is exactly the word that defeats a single-proximate-cause model — pneumonia contracted in hospital after a skydiving injury. **Decides Q9**, which turns on the chapeau's causal element being live. |

#### Section 3 — general conditions

| #   | clause                                                                                   | the fork                                                                                                                   | taken                                                                                                                                                                                         | notes                                                                                                                                                                                                                                                                                |
| --- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A26 | 3.1.1, 24-hour worldwide cover                                                           | Operative but only negatively (forecloses time/place limitations) / descriptive, drop it                                   | Kept as an unconditionally-satisfied named limb.                                                                                                                                              | All three — and all three auditors flagged the resulting constant-TRUE conjunct as dead weight that will show up in any call-graph, ladder or DMN projection. The defence is that silently dropping it leaves a reviewer unable to tell "considered and inert" from "missed".        |
| A27 | 3.2.1, what counts as "a dispute or disagreement"                                        | A declined claim is itself a disagreement, so the policy is arbitrate-first throughout / something narrower                | Not resolved in the encoding — supplied as a caller fact.                                                                                                                                     | record. The text gives no test whatever, and the choice swings the policy between "pay claims" and "arbitrate every claim".                                                                                                                                                          |
| A28 | 3.2.1, "the day such parties are unable to settle"                                       | A determinate ascertainable day / vague, so the three-month window has no fixed start                                      | Taken as a supplied fact, not computed.                                                                                                                                                       | record. **D9(c).**                                                                                                                                                                                                                                                                   |
| A29 | 3.2.1, "sixty (60) days" in a months-only clock                                          | 2 months / ≈1.97 months                                                                                                    | 2 months, bound to a named constant so the conversion is visible in one place.                                                                                                                | All three. **The one genuine encoded shortcut in each file**, disclosed in each. Harm is currently nil because the rule consuming it is not wired into the payability decision (A30).                                                                                                |
| A30 | 3.2.1, "In no case shall You seek to recover … before the expiration of sixty (60) days" | A bar on _when you may sue_ — the entitlement exists, the remedy is postponed / a further condition precedent to liability | Procedural. Encoded as its own decision and deliberately **not** consumed by the payability test.                                                                                             | All three. The drafter used "condition precedent to our liability" in the immediately preceding sentence and not in this one. Folding it in would turn "not yet enforceable" into "not covered" for every claim in its first two months.                                             |
| A31 | 3.2.1, the arbitration award as condition precedent                                      | Unmet award ⇒ FALSE at the time of asking / procedural only                                                                | Folded into the top-level decision but **gated on a dispute having arisen**, so it is vacuous on an undisputed claim.                                                                         | All three.                                                                                                                                                                                                                                                                           |
| A32 | 3.2.1, extinguishment while the window is open or unstarted                              | Nothing is extinguished until the three months have run / any dispute without commenced arbitration extinguishes           | **Divergence, and all three are partly wrong.** guarded handles the _unstarted_ case (no impasse day ⇒ nothing extinguished) but not the _open-window_ case; inert and record handle neither. | This is the shared bug of §4.1. Unexercised by the benchmark.                                                                                                                                                                                                                        |
| A33 | 3.2.1, "in accordance with the provisions of the Arbitration Act (Cap. 10)"              | Incorporated into the extinguishment trigger via "in accordance with this clause" / timing only                            | **Dropped by all three**, and disclosed by none of them at the point of dropping. A procedurally defective commencement counts as good in every arm.                                          | Related instrument-level finding: a Singapore statute inside a New York-law policy. **D8.**                                                                                                                                                                                          |
| A34 | 3.3.1, choice of law                                                                     | Operative on payability / a construction rule, not a condition                                                             | Not operative.                                                                                                                                                                                | guarded. But recorded in the file because the NY/Cap. 10 mismatch is a real finding for a human.                                                                                                                                                                                     |
| A35 | 3.6, cover before the effective date                                                     | The term is the only source of cover, so a negative month is outside / silence                                             | Outside. Encoded as a term-begun test.                                                                                                                                                        | All three — and all three placed it inside the 1.1 in-effect decision, which is an interpolation: it is a row that does not appear in 1.1's own enumeration, so a reader auditing against 1.1 alone will not find it there. record's and guarded's auditors both flagged it as such. |

**Register statistics.** 35 entries. Six divergences among the three arms (A10, A11, A15, A19, A32,
and partially A9). Four entries are outcome-determinative for the benchmark (A5→Q5, A9→Q3, A21→Q2,
A25 with A24→Q9), and A3 with A15 jointly control Q4. **Twenty-nine of the thirty-five are invisible
to the nine-question benchmark entirely.**

---

## 5. What this sets up: the measurement phase

### 5.1 The design

A **2 × 3 factorial**, model family held fixed, so that **target language** is the independent
variable rather than model identity:

|            | vanilla                                            | unguided                            | guided                                                                |
| ---------- | -------------------------------------------------- | ----------------------------------- | --------------------------------------------------------------------- |
| **Prolog** | (paper's §3.1; no encoding)                        | model writes Prolog from the policy | model writes Prolog against a supplied fact vocabulary and predicates |
| **L4**     | (identical to the Prolog vanilla cell — see below) | model writes L4 from the policy     | model writes L4 against a supplied fact vocabulary and helpers        |

The paper's own Limitations section invites exactly this: _"we … focused solely on Prolog as a logic
interpreter. Future work should incorporate a wider variety of models and interpreters to enhance
generalizability and robustness."_ [**verified:** `kant.txt:594-600`].

Six design requirements follow from this phase:

**R1 — Record and publish per-item answers, per trial.** The single largest interpretive obstacle in
the paper is that only aggregates are reported, so "0.78, consistently" cannot be resolved into
_which two_. Our harness must emit a per-trial, per-item table, and the write-up must include it.
This also lets us test the §1.2 hypothesis directly: if the five vanilla models plateauing at 0.78
are all missing the same two items, and those two are in {4, 5, 9}, that is a finding about the key,
not about the models.

**R2 — Dual scoring.** Score every run twice: (a) against the paper's key verbatim, for
comparability; (b) against a **defensibility-graded key** that marks Q4 under-determined and Q5
contested, and reports `mechanical-7` and `interpretive-2` as separate figures. Report both. Never
report (b) alone — that would be marking our own homework — and never report (a) alone, which is
what produces the inverted-objective problem of §1.5.

**R3 — Score the two generation steps separately.** In both languages there are two model calls: the
_encoding_ step (policy → rules) and the _marshalling_ step (query → facts). This phase proved the
marshalling step decides at least three of the nine answers with the encoding held constant —
Q4/Q4b, Q5/Q5b, Q9/Q9b in `apply-guarded.l4` all flip on the fact record alone [**verified**]. A
pipeline that lets one model do both is measuring their sum. So: **(i)** hold the facts fixed (from
the reference encoding's marshalling) and vary the encoding; **(ii)** hold the encoding fixed (our
reference) and vary the marshalling. Two numbers, reported separately.

**R4 — Derive both guided fact vocabularies from one schema.** The guided prompt hands the model a
pre-specified fact vocabulary and supporting predicates (`prompts/A33-guided.txt`), and this phase
established that the fact schema is where the interpretive load sits. If we author a Prolog schema
and an L4 schema independently, differences between the schemas — not the languages — will drive the
result, and the guided cell will silently measure whichever schema disambiguated better. Both must
be mechanical transliterations of one source, and the write-up must say that the guided cell
measures **schema plus language**, not language.

**R5 — Execute both arms, or hand-read both.** The paper's Prolog was scored partly by manual
reading of code that would not run (§1.1). If we execute the L4 and hand-read the Prolog, we are
comparing an executed artifact against a charitable reading of a non-executable one, and the
difference will look like a language effect. Either both arms run under an interpreter with
failures scored as failures, or both get the same charity — and the choice is reported.

**R6 — Keep the fixture as published.** The 20 defects of §2 stay in. A repaired-fixture arm is
worth running, but as a separate, clearly-labelled experiment, and its results must never be
reported in the same table as the replication.

### 5.2 Threats to validity uncovered by this phase

**T1 — The dependent variable is contestable.** At least 1 of 9 gold labels is, on our audit, the
weaker of two readings (Q5); at least 1 is under-determined by its own query (Q4). Between 11% and
33% of the score is agreement-with-an-annotator rather than correctness. _Mitigation:_ R1, R2.
_Residual risk:_ high. A 1-item difference is 11 accuracy points, and the two contested items are
worth 22.

**T2 — Nine binary items give no statistical power.** No comparison between two cells on nine binary
outcomes can separate a real effect from noise; the paper's own ±SEM figures range up to ±0.18
(GuidedCI/DeepSeek-R1 at 0.47 ± 0.18 [**verified:** `kant.txt:487-491`]), i.e. a confidence
interval spanning nearly three items. _Mitigation:_ n replicates per cell with within-cell variance
reported; treat aggregates as descriptive; lead with the per-item agreement matrix.
_Extending the query set is tempting and dangerous_ — the moment we author new items we author their
key, and we inherit §1 exactly. Any extension must ship its own adversarial audit and its own
register, or it is worse than nine items.

**T3 — The paper's own prompt convention neutralises L4's main advantage (GAP 2).** Relative-months
collapses ages and elapsed times onto `NUMBER`, and the resulting unit confusion is silent
[**verified**]. Keeping the convention hobbles L4; dropping it changes the fixture and breaks
comparability. _Mitigation:_ run the L4 unguided and guided cells **both ways** — under the paper's
convention and with honest `DATE`/wrapper types — and report both, with the delta labelled as the
cost of the convention rather than as an L4 result. Also note that clause 1.2's cancellation instant
is **unencodable at all** under the convention, in either language.

**T4 — Contamination.** The policy text (Appendix A.1) and all nine queries with their answers
(Appendix A.2) have been on arXiv since February 2025. Any model with a later cutoff may be
recalling the key rather than deriving it, and **this cuts against L4**: the vanilla cell is pure
recall risk, and the Prolog cells have published sibling encodings in the appendices while the L4
cells have none. _Mitigation:_ report cutoffs; run a paraphrase/perturbation control (permute the
ages and the month figures across their thresholds) and report the delta. A model that answers
correctly on the published numbers and incorrectly on the perturbed ones is recalling.

**T5 — Nine items exercise only a fraction of the instrument, so an encoding can be badly wrong and
still score 8/9.** Demonstrated: all three reference encodings share a confirmed logic error in
§3.2.1 and all three score 8/9, because no query mentions a dispute (§4.1). Never put in issue by
any query: the whole of §3.2.1 (arbitration, extinguishment, condition precedent, the sixty-day
bar), §3.3.1, §3.4.1, §3.5.1, 1.3's month-6 visit deadline, 1.3's three provenance requirements,
1.2's material-withholding limb, and 1.2's automatic end-of-term cancellation at its boundary.
1.1(1) and 1.1(2) are stipulated away by the prompts themselves. _Mitigation:_ report a **clause
coverage** figure alongside accuracy, and treat "encoded the unexercised clauses correctly" as a
separate, register-scored measure. This is where L4 has something to demonstrate that accuracy
cannot show.

**T6 — Our reference encoding is a reference, not a second gold.** It agrees with the key 8/9 in all
three strategies and disagrees on the same item. Use it as a _third comparison point_ — "does the
model's encoding agree with a careful, register-documented human-grade encoding?" — never as an
oracle. Its own shared bug (T5) is the standing reminder of why.

**T7 — The scoring harness must not trust exit codes (GAP 1a).** A failed `#ASSERT` exits 0
[**verified**]. Parse `l4 run --json` and check `results[].value`, or every L4 cell silently scores
as passing.

**T8 — Two of our sub-agents disagree about Q3, and the disagreement is unresolved.** The fixture
auditor says Q3's gold rests on defect D3 and that a model reading 1.2 faithfully answers "No" and
is marked wrong. The gold auditor says the harmonising reading is the only sane one — the literal
reading would cancel every policy on day one — and rates Q3 mechanical with high confidence. Both
can be true: the contradiction is real (the L4 probe exhibits it as two readings differing only on
`Pending`), and the harmonising reading is the better one. All three encoders took the harmonising
reading and all three answered Yes. _We are not treating this as settled_, and the measurement phase
should record whether models that answer "No" to Q3 do so because they read 1.2 — which would make
Q3 a fourth interpretive item, not a mechanical one.

**T9 — The harness's own memory system is a contamination channel into "blind" trials
[discovered 2026-09-01, during the k = 10 run].** Encoder sub-agents inherit the session's
project-memory index file, and until mid-run its line for this project read "benchmark fixture has
§2 DELETED, so Q5's gold is underivable" — result-adjacent content injected into every nominally
blind sandbox by the orchestration layer itself, outside the staged `inputs/` that the leak check
audits. Discovered because two trials (`k10/prolog-unguided/t5`, `k10/prolog-guided/t5`)
spontaneously disclosed it in their NOTES, both stating they did not use it. The empirical evidence
says the channel did not drive answers toward the key: the unguided cells SPLIT on Q5 in that same
run (some trials No via a derived trigger, some Yes, one vanilla abstention), the disclosing
unguided trial answered against the key's direction, and disclosure ran 2 of the first 21
completions. Disposition: (a) the channel was left CONSTANT for the whole as-published arm — every
one of the 40 k = 10 trials, and the 10 pilot trials before them, launched with the same index
content, so within-arm comparisons are unaffected; (b) the index was sanitized to finding-free
pointers immediately after the last as-published launch and before any restored-arm staging, so the
restored arm runs clean; (c) this is a limitation to report, not to repair retroactively. The
general lesson generalises beyond this study: an agent-orchestration harness that injects ambient
project state must be audited as part of the blinding boundary, exactly like the staged inputs.

### 5.3 What would make this replication worth publishing

Not "L4 scored higher than Prolog on nine questions" — T1 and T2 make that number close to
meaningless, and we should say so in the paper rather than let a reader infer it. The defensible
contributions this phase points to are:

1. **An audited answer key.** Nine labels with their competing readings, their class
   (mechanical/interpretive), and the clause each turns on — the artifact the original does not
   have, and the one the RL proposal in the paper's §5 would need before "correctness" is a safe
   reward.
2. **A defect inventory for a fixture other people are already citing.** Twenty items, with the five
   that change gold answers identified.
3. **Clause coverage as a metric alongside accuracy** — motivated by a demonstrated case (T5) where
   three independent encodings share a confirmed bug that the benchmark scores as 8/9.
4. **A concrete account of what the target language buys**: three of the four observed Prolog
   failure classes caught at check time, the fourth reachable only by scenario tests, one
   contradiction in the source document (D3) surfaced mechanically by three-valued typing — **and**
   the honest counterweight, that the benchmark's own relative-time convention removes the type
   safety that produces one of those three.

---

## Appendix — artifacts and how to re-derive the claims

```
kant-repl/
├── fixtures/
│   ├── chubb-policy.txt          54 lines — the paper's Appendix A.1, verbatim
│   └── queries.json              the nine queries + golds + the paper's reported accuracies
│                                 NB: its `paper_rationale` fields are OUR reconstruction
├── prompts/                      A31-vanilla, A32-unguided-{policy,query}, A33-guided
├── runs/
│   ├── FOUNDATION.md             this document
│   ├── source-defects.md         652 lines — the fixture audit (D1–D20)
│   ├── l4-probe.md               the L4 capability probe
│   ├── probe/                    p0–p7: the probe sources, one claim per file
│   └── encodings/
│       ├── ref-inert.l4          526 lines — THE REFERENCE
│       ├── ref-record.l4         676 lines
│       ├── ref-guarded.l4        536 lines
│       └── apply-{inert,record,guarded}.l4   the nine queries as fact records, plus
│                                             the Q4b/Q5b/Q9b and S4/S5/S9 sensitivity runs
└── ../kant.txt                   extracted text of arXiv 2502.17638
    ../kant2025-logical-llms.pdf  the paper
```

Reproduce the nine answers and the sensitivity runs:

```bash
L4=/Users/mengwong/src/legalese/l4wt/callgraph-materiality/dist-newstyle/build/aarch64-osx/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
export JL4_LIBRARY_PATH=/Users/mengwong/src/legalese/l4wt/callgraph-materiality/jl4-core/libraries
cd .../kant-repl/runs/encodings
for f in apply-inert apply-record apply-guarded; do $L4 run $f.l4; done
```

The evaluation order differs per file, so read them off this map rather than by position:

| file               | evaluation → item                                                                             |
| ------------------ | --------------------------------------------------------------------------------------------- |
| `apply-inert.l4`   | 1 = all-favourable baseline; 2–10 = Q1–Q9                                                     |
| `apply-record.l4`  | 1–9 = Q1–Q9; 10 = S5; 11 = S9; 12 = S4                                                        |
| `apply-guarded.l4` | 1–4 = Q1–Q4; **5 = Q4b**; 6 = Q5; **7 = Q5b**; 8 = Q6; 9 = Q7; 10 = Q8; 11 = Q9; **12 = Q9b** |

All three give **No / Yes / Yes / Yes / No / No / Yes / No / Yes** for Q1–Q9. The counterfactuals
(guarded Q4b/Q5b/Q9b; record S4/S5/S9) give FALSE / TRUE / FALSE and FALSE / TRUE / FALSE
respectively — i.e. each of the three judgement calls flips its item.

**Open items carried into the measurement phase.**

1. Verify the _Miller v. Continental_ citation and holding before any Q5 argument is published
   (§1.4, currently [**external**]).
2. Add the `IMPORT`-before-`§` trap to the `l4-syntax-traps` memory (§3.3, GAP 5).
3. Decide whether the three reference encodings' shared §3.2.1 bug is fixed before the measurement
   phase or left in as a documented control. Leaving it in is defensible — it is the evidence for
   T5 — but if it is fixed, fix it in all three or the arms stop being comparable.
4. Resolve T8: is Q3 a fourth interpretive item?
