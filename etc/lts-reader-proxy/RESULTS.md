# The §7.3 gate — an LLM-reader PROXY: RUN 1 (2026-09-16) and RUN 2 (2026-09-21)

**Status: two runs, both as a proxy. Neither is the gate, and this file records no verdict on the
gate.** [`LTS-VISUALISER.md`](../../specs/todo/lexipedia-superset/LTS-VISUALISER.md) §7.3 gates the
two-plane picture on a **reader** experiment — can readers answer _what do I owe, what discharges it,
what breaches it_ from the plain list (`l4 lts`), and does a picture add _where am I_ and _what
happens after_ (§1.1a)? No human has been shown anything, in either run. What was run is the proxy
the [`README.md`](./README.md) in this directory prepares: fresh LLM readers, each shown **one**
artifact for one contract and nothing else, asked the five questions, scored against `truth.json`.

| run       | date       | scored rows                                | primary evidence                                              | what the readers were shown                       |
| --------- | ---------- | ------------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------- |
| **run 1** | 2026-09-16 | [`results.json`](./results.json)           | [`transcripts/`](./transcripts/readings.json)                 | the **refusing** list; pre-#425/#401/#430 B and C |
| **run 2** | 2026-09-21 | [`results-run2.json`](./results-run2.json) | [`transcripts-run2/`](./transcripts-run2/) — **packets only** | the **repaired** list; re-cut B and C             |

Every number in this file is computed from those two files and nothing else. **§1–§5 are run 1 and
are kept unaltered as history**; §6 is run 2 and the delta. Read §6.1 before comparing any run-1
number against any run-2 number: the two runs did **not** hold the artifacts fixed — and §6.2 measures
what that cost, on four cells whose documents did not change at all.

---

# RUN 1 — 2026-09-16

The primary evidence behind run 1's rows — each reader's prompt and verbatim answers, each judge's
prompt and verbatim output, and the model ids — is under
[`transcripts/`](./transcripts/readings.json), recovered from the run's own transcripts by
[`extract-transcripts.mjs`](./extract-transcripts.mjs) on 2026-09-16 (the first commit of this file
carried only the scored rows, which a reviewer rightly called unauditable). **Run 2 did not repeat
that recovery and could not: see §6.3.**

## 1. Method

| item         | value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| contracts    | the four in the README: `contracts` (`aContract`, third link of a HENCE chain), `every-run-example` (`the tenancy`, an `EVERY` barrier with 2 of 3 signed), `tenancy` (`receipts`, an `EACH` fork at its outset), `promissory-note` (`Payment Obligations`, one late payment sitting in the first `LEST` arm)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| artifacts    | **A** the `l4 lts` list at default flags · **B** the `l4 state-graph` DOT source, as text · **C** the P1 BPMN 2.0 XML, as text. B and C readers also got `history.txt` (the position in plain words); A readers got only the list, which states its own position. Full reader-facing text: `manifest.json`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| questions    | the five in `manifest.json`, identical for every contract: Q1 _what is owed right now, and by whom_ · Q2 _which event(s) would discharge it_ · Q3 _which event(s) or deadline(s) would put someone in breach_ · Q4 _where in the contract are we — which rule, branch or state is live_ · Q5 _what happens after the next discharging event_. Q1–Q3 are §1.1a's three clauses; Q4–Q5 are the two things §1.1a says a list cannot do                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| readers      | two Claude models, `haiku` = `claude-haiku-4-5-20251001` and `sonnet` = `claude-sonnet-5` (`transcripts/readings.json`, `model_id`). Each reader was a fresh, single-turn Claude Code subagent (harness 2.1.272) with **no tools** but the answer form, and no other context: one artifact (plus `history.txt` for B and C), then the five questions, with the instruction _"if the artifact does not let you answer, say 'cannot tell from this' — do not guess"_ (`transcripts/prompts/<contract>.<artifact>.txt`, byte-identical across the four readings of a cell). Each (contract, artifact, model) cell was run **twice** (`repeat` 0 and 1), so 4 × 3 × 2 × 2 = **48 readings, 240 scored answers**. `extract-transcripts.mjs` checks that no reader used any other tool                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| judge        | one `claude-opus-5` judge per contract (`transcripts/judge.json`), shown `truth.json` and all twelve readings of that contract (`transcripts/judge/<contract>.prompt.txt`), scoring each answer **0 or 1** with a one-line rationale per reading. **One scoring rule is in the prompt, verbatim:** _"Score each answer 1 if it is correct against the truth (same obligations/parties/events/deadline, allowing paraphrase; 'cannot tell' is 0 unless the truth says the artifact cannot say it, in which case 'cannot tell' is 1 and a confident wrong answer is 0), else 0."_ **A second rule is not in the prompt and is inferred from the rationales:** an answer that is incomplete but asserts nothing wrong scores 1 (`every-run-example/B/haiku/0`: _"omits the day-14 deadline (incomplete, not wrong)"_). Neither was applied uniformly: `promissory-note/A/haiku/0` Q4 _"names only the section, not the live LEST/penalty arm"_ scored 0 (incomplete, nothing wrong); `promissory-note/A/haiku/1` Q3 _"hedged 'cannot tell' but substantively reports the truth"_ scored 1, while `tenancy/A/sonnet/1` Q2 _"states the right inference but then retracts to 'cannot tell' as its verdict"_ scored 0. So a count that turns on either rule is ±2, not exact |
| recorded     | under `transcripts/`: the twelve reader prompts verbatim; the 48 readings' verbatim answers (`answers`, the accepted answer form; `answer_text`, the prose the reader wrote before it, empty for the 22 readers that filled the form directly) with model id, timestamps and token usage; the four judge prompts and outputs verbatim. `extract-transcripts.mjs` asserts `results.json` == judge output and judge input == reader output, both exact; one reader (`promissory-note/C/sonnet/0`) had its first answer form rejected by the schema (missing `a2`, `a4`) and its second accepted, and both attempts are kept (`rejected_attempts`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| not recorded | the harness system prompt a Claude Code subagent runs under (not in the transcript, so not reproducible here); the readers' and judges' thinking (present in the transcripts as signatures only, `thinking_redacted_in_transcript`); effort settings (the transcript fields are null, i.e. harness default); temperature. A rerun outside the harness, with a bare API call, would remove the first                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| binary       | all artifacts were cut with the `lts/p2-stack` build at `0139c6c5`, as the README records; the truth answers were read off `lts.json` (Q1–Q3) and `probes.out` / `B.dot` (Q4–Q5)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

## 2. Results

Cells are _correct / readings_; each reading is one model × one repeat, so a cell holds 4 answers
per contract and 16 pooled.

### 2.1 Per contract

| contract              | artifact | Q1  | Q2  | Q3  | Q4  | Q5  | all       |
| --------------------- | -------- | --- | --- | --- | --- | --- | --------- |
| **contracts**         | A list   | 4/4 | 1/4 | 4/4 | 2/4 | 0/4 | 11/20 55% |
|                       | B DOT    | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
| **every-run-example** | A list   | 4/4 | 4/4 | 4/4 | 2/4 | 4/4 | 18/20 90% |
|                       | B DOT    | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
| **tenancy**           | A list   | 4/4 | 1/4 | 4/4 | 3/4 | 0/4 | 12/20 60% |
|                       | B DOT    | 3/4 | 4/4 | 2/4 | 4/4 | 4/4 | 17/20 85% |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 0/4 | 16/20 80% |
| **promissory-note**   | A list   | 4/4 | 2/4 | 3/4 | 0/4 | 0/4 | 9/20 45%  |
|                       | B DOT    | 2/4 | 3/4 | 3/4 | 3/4 | 3/4 | 14/20 70% |
|                       | C BPMN   | 2/4 | 2/4 | 2/4 | 2/4 | 2/4 | 10/20 50% |

### 2.2 Pooled over the four contracts

| artifact   | Q1        | Q2        | Q3        | Q4        | Q5        | Q1–Q3         | Q4–Q5         | all               |
| ---------- | --------- | --------- | --------- | --------- | --------- | ------------- | ------------- | ----------------- |
| **A** list | **16/16** | 8/16      | **15/16** | 7/16      | 4/16      | 39/48 **81%** | 11/32 **34%** | 50/80 **62.5%**   |
| **B** DOT  | 13/16     | **15/16** | 13/16     | **15/16** | **15/16** | 41/48 **85%** | 30/32 **94%** | 71/80 **88.75%**  |
| **C** BPMN | 14/16     | 14/16     | 14/16     | 14/16     | 10/16     | 42/48 **88%** | 24/32 **75%** | 66/80 **82.5%**   |
| all        | 43/48     | 37/48     | 42/48     | 36/48     | 29/48     | 122/144 85%   | 65/96 68%     | 187/240 **77.9%** |

Readings in which all five answers were right: A 2/16, B 10/16, C 8/16.

### 2.3 By reader model

| model  | A list    | B DOT       | C BPMN    |
| ------ | --------- | ----------- | --------- |
| haiku  | 22/40 55% | 33/40 82.5% | 36/40 90% |
| sonnet | 28/40 70% | 38/40 95%   | 30/40 75% |

The two repeats of a (contract, artifact, model) cell gave the identical five-vector in 16 of 24
cells. Two repeats is not enough to separate the models from the noise: sonnet beats haiku on A and
B and loses on C, and the C loss is one contract (`promissory-note`, §3.4) read the same wrong way
twice.

## 3. Where the misses are — sorted before they are interpreted

There are 53 misses in 240 answers. Classifying each by its judge rationale (`results.json`,
`rationale`), the three artifacts fail in **different kinds**, and that is the most useful thing in
the data:

| artifact   | misses | "cannot tell" (loud) | incomplete / vague | wrong assertion (silent) |
| ---------- | ------ | -------------------- | ------------------ | ------------------------ |
| **A** list | 30     | **25**               | 3                  | 2                        |
| **B** DOT  | 9      | 0                    | 2                  | **7**                    |
| **C** BPMN | 14     | 1                    | 0                  | **13**                   |

The list, when it fails, mostly says so; the pictures-as-text, when they fail, give a definite wrong
answer. Two qualifications. The reader prompt told every reader to say _"cannot tell from this"_
rather than guess (§1), so the loud failure was invited and the silent one was not; the asymmetry
is still real — the same instruction went to B and C readers, who nonetheless asserted — but its
size is partly the prompt's doing. And this classification is mine, from the rationales, and a
second reader of `results.json` could shift a case or two between "incomplete" and "wrong"; the
25-vs-0-vs-1 column would move by at most the two inconsistently scored rows §1 names.

**Run 2 does not reproduce this table, and §6.5 is where that is dealt with.** It is the single
largest qualitative difference between the runs.

### 3.1 The list's Q2 misses are all in the "What could not be tried" section

Q2 (_what discharges it_) is where the list loses to both pictures pooled: 8/16 against 15/16 and
14/16. Every one of the eight misses is on a contract where the list **refused the what-if**:

> **Repaired 2026-09-21, and RE-MEASURED the same day — see §6.7.** The refusal this section traces
> the Q2 deficit to is gone: the what-if now answers for the SET of acts a bound pattern variable
> describes, and all three contracts below print what discharges the obligation
> (LTS-VISUALISER.md §2.4, the bound-variable block; §7.7 point 2). **Every number in §1–§5 was
> scored against the output quoted below**, which is what run 1's readers were shown. The repaired
> output was put in front of 48 fresh readers on 2026-09-21; §6.7 has what happened.

- `contracts/A.txt` — _"B does return — the action binds `return`, which the what-if cannot choose"_
- `tenancy/A.txt` — _"… the action binds `amount`, which the what-if cannot choose"_ (three times)
- `promissory-note/A.txt` — _"… the action binds `Amount Transferred`, which the what-if cannot choose"_

That text is `jl4-core/src/L4/Lts/WhatIf.hs:525` (`PatVar _ v -> pure (Left ("the action binds …
which the what-if cannot choose"))`), printed by `jl4-core/src/L4/Lts/List.hs:216` under _"What
could not be tried:"_ — the limit `doc/reference/regulative/lts-list.md` states at its
[Limits](../../doc/reference/regulative/lts-list.md) section. On these three contracts the list
carries **no** "what would end it" line, so a reader has nothing to cite; the readers who scored 1
on those three contracts (4 of 12: `contracts` 1, `tenancy` 1, `promissory-note` 2) inferred that
doing the owed act discharges it, which the list never says, and the judge's "cannot tell = 0"
rule took the rest. On `every-run-example`, the one contract where the
what-if **could** be tried (Carol's `Sign` binds nothing open), the list scored **4/4** on Q2.

_(2026-09-19: the sibling refusal seen one step past the `tenancy` position — `probes.out:15`,
where the landlord's receipt was refused with the evaluator's own "Internal error: amount is not
in scope" — now reads the same "the action binds `amount`, which the what-if cannot choose"
sentence, made before any replay (`WhatIf.hs`, `closedAction`); `tenancy/probes.out` is re-cut
from that binary, so its line 15 is the new sentence. The three artifacts above are `PatVar`
refusals and were already worded this way; nothing in this measurement moves. The
`:525`/`:216` line numbers are as of the run.)_

So the Q2 gap measured here is a gap in **`WhatIf`'s coverage of open pattern variables**, not a
gap between a list and a picture. `truth.json`'s own Q2 answer for `contracts` is exactly the
sentence the list could print: _"any act by B on or before day 14 discharges it, because `return`
is a pattern variable that matches whatever action B does"_.

### 3.2 The list's Q5 misses have the same cause; §1.1a's prediction holds only where the what-if is refused

Q5 (_what happens after the next discharging event_): A 4/16, and all four are `every-run-example`,
where the list prints the continuation itself —

```
  What would move things along (neither ends nor breaches it):
    - Tenant OF "Carol" does Sign OF (Tenant OF "Carol") now (at 2) → then:
          · Landlord OF "Ms Ng" MUST Deliver (EXACTLY theLandlord) — due by 7 (5 from now)
```

§1.1a says _"what the list plainly cannot do is show … what happens after what you are about to
do."_ The list as built **does** show it, one step deep, whenever it can try the act (this is the
`→ then:` block, §7.6). It showed nothing on the other three contracts because it could not try the
act — §3.1 again. The prediction is confirmed in direction (Q4–Q5 pooled: list 34%, DOT 94%, BPMN
75%) and its stated reason is wrong in scope: the built list's Q5 ceiling is set by `WhatIf`, not by
being a list.

### 3.3 Q4 (_where are we_): the list gives the history, not the branch

A 7/16 on Q4, and the split is by model: haiku 1/8, sonnet 6/8. The list prints the event history
(`PARTY S DOES delivery AT 2 …`) and, for the barrier, _"2 of 3 have"_, but never names the branch
that was taken (`ELSE` vs `LEST`) or the arm we sit in. On `contracts` sonnet named the live
state — _"the return obligation now live and its deadline at 14"_ (`transcripts/readings.json`,
both repeats) — without naming the branch, and the judge credited it (_"correct state though
branch reasoning absent"_); on `tenancy` it was credited for "at the start". Haiku scored once in
eight readings — "cannot tell" five times, the section name alone twice. On `promissory-note` all four A readers scored
0: the list names the section and a deadline of `739769` but nothing in it says _the first
deadline was missed, the April payment did not count, and this is the penalty arm_ — which
`history.txt` tells B and C readers in plain words. (`739769` is the number these readers were
shown and is the number `truth.json` was keyed on, so the scores here stand; the tree now prints
`739752`, from `12055ae73` on 2026-09-17 — the day after this directory was cut — and both the
key and the artifacts have to move together at the next re-cut. `promissory-note/truth.json`'s
`drift` key has the substitutions.) This is the one place where the A readers were
given strictly less information than B and C (the README says so), and the Q4 column on that
contract is confounded by it.

> **That warning came true in run 2, in the half it named.** The 2026-09-21 re-cut moved `A.txt` to
> `739752` and left `truth.json` at `739769`, so run 2's `promissory-note` A readers were marked
> wrong for printing the number the tree prints. §6.6 quantifies it: it is the largest single
> defect in run 2.

### 3.4 The BPMN's misses are confident wrong answers; five sit squarely on the exporter's documented losses

Thirteen of C's fourteen misses are confident wrong answers. Five of them land squarely on a loss
that `C.fidelity.txt` for that contract names — the three `tenancy` Q5 answers (`[P-FORK]`) and
haiku's two `Boundary_4` answers on the note (`[P-DEADLINE]`). The other eight — sonnet's two
readings of the note, four misses each — contradict the plain-words `history.txt` the reader was
given (_"the plain installment amount, paid after the deadline"_), so no fidelity loss hid the
fact from them; those eight are at most _consistent_ with `[F4]` and `[P-DEADLINE]`, which is
weaker than being caused by them. Case by case:

- **`tenancy` Q5, 0/4.** Three readers said the landlord's receipt obligation starts _"after all
  tenants complete their payments"_; one said "cannot tell". The rule is `UPON EACH`: one payment
  starts that tenant's receipt while the others still owe. The BPMN draws a parallel multi-instance
  task whose outgoing flow fires once, after the last instance — which is `tenancy/C.fidelity.txt`
  **`[P-FORK] lossy`** verbatim: _"what is drawn fires once, for the group"_. The readers read the
  drawing correctly; the drawing is wrong, and says so in a report the readers were not shown.
- **`promissory-note`, sonnet 2/10 over two repeats.** Both readings credited the 3 April payment
  against the first installment task and placed the process at the split gateway, looping back —
  although `history.txt` said the payment was _"the plain installment amount, paid after the
  deadline"_. The guard that refuses it (`PROVIDED is money at least equal within error …`) is an
  opaque `conditionExpression` on the task's outgoing flow (**`[F4] lossy`**), the deadline is a
  boundary event carrying `Next Payment Due Date` as text (**`[P-DEADLINE] blocking`**), and the
  gateway arms are opaque (**`[P-BRANCHGUARD]`**). Haiku, on the same file, got Q1/Q2/Q4/Q5 right
  both times and Q3 wrong both times — asserting that `Boundary_4` fires and reaches Breach, when
  its own `<documentation>` says _"Nothing can fire it"_ (**`[P-DEADLINE] blocking`** on
  `Boundary_4`).

### 3.5 The DOT's misses

Seven wrong, two vague, none "cannot tell". `tenancy` Q3, haiku 0/2: "a timeout", naming neither
the `[7]` nor the `[5]` on the edge labels — vague, scored 0. `promissory-note`, haiku: repeat 0
placed the position at node 4 (all outstanding debts) instead of node 2 (penalty arm) and invented
a grace expiry around day 739701; repeat 1 credited the April payment and produced a running
balance. Sonnet, `promissory-note` repeat 1, packed all five answers into the first slot and got
Q5 wrong (payment returns to node 0 and loops; the DOT's edge is `2 -> 3`, Fulfilled). Sonnet,
`tenancy` repeat 1, opened Q1 with _"nothing is owed yet"_. The DOT is the artifact that most often
names the right node, and when it is misread it is misread with the same confidence as the BPMN.

### 3.6 The note is hardest for everyone

`promissory-note` is the only contract where all three artifacts fall below 75%: A 45%, B 70%,
C 50%. It is the one with a real `LEST` chain, day-serial clocks, a guard on the amount and a
breach edge that is drawn but unreachable — the README chose it for exactly those reasons. Nothing
here says which of those made it hard.

## 4. What this proxy can say

Stated as what the data supports, at its sample size, and no further:

1. **On Q1 and Q3 the list is not beaten.** Q1: list 16/16, DOT 13/16, BPMN 14/16. Q3: list
   15/16, DOT 13/16, BPMN 14/16. All five Q1 misses are on the pictures, and all five are definite
   wrong answers — one _"nothing is owed yet"_ on `tenancy`, four misplacing the note's position.
2. **On Q2 the list loses, and the whole of the loss is `WhatIf`'s refusal of open pattern
   variables** (§3.1). On the one contract where the what-if ran, the list was 4/4. That points at
   a list-side change — print what `truth.json` prints, _any act by B_, or try the act with the
   binder left open — that is much cheaper than a picture and can be re-measured with the same
   materials.
3. **On Q4–Q5 the list loses badly (34% vs 94% and 75%), in the direction §1.1a predicts** — and
   the reason §1.1a gives is only half right, because the built list already prints one step of
   "after" whenever it can try the act (§3.2). The residual claim is the Q4 one: the list gives a
   history, not a branch.
4. **The pictures-as-text fail silently; the list fails loudly** (§3). Of the list's 30 misses, 25
   are the reader saying it cannot tell — invited by the prompt's "do not guess" (§3); of the
   BPMN's 14, 13 are a wrong answer given as a fact, five of them squarely on losses
   `C.fidelity.txt` names and eight against a history the reader had in plain words (§3.4). A
   reader of the exported BPMN who is not also shown the fidelity report will, on these
   contracts, be told that receipts wait for every tenant.
5. **The DOT source as text is the best artifact overall** (89%, 10 of 16 perfect readings), and
   the one whose content most often carries all five answers.

**All five were re-measured on 2026-09-21, and only point 2 came back intact.** Point 1 held on Q1
and failed on Q3; point 3 half-reversed; points 4 and 5 were not reproduced at all. §6.8 is the
row-by-row account, and §6.2 is why most of it is drift rather than finding.

## 5. What this proxy cannot decide — the gate

- **It cannot decide §7.3.** The gate is about people; nobody here was a person. An LLM reader
  that infers a discharge the list did not print (§3.1) is not evidence that a member of the
  public would.
- **It says nothing about cognitive load** — the quantity §7.4's warrant (Maslov & Poelmans) is
  about. Right-answer counts are the measure §7.4 explicitly says token animation does _not_ move.
- **B and C were read as text, not looked at.** A DOT edge label and a BPMN `<documentation>`
  are strings to these readers. Whether a rendered graph helps or hurts a human — layout,
  colour, the position of the token — is untested in either direction; "DOT beats BPMN" here
  means one text serialisation was easier to read than another.
- **The A readers were disadvantaged on one contract by design** (§3.3): the promissory note's day
  serials were converted for B and C readers only. That should be equalised before any Q4 number
  on that contract is quoted.
- **The judge is an LLM too**, and its "cannot tell = 0" rule is a choice written into its prompt
  (§1), applied with two inconsistencies §1 names. Scoring "cannot tell"
  as a half-credit or as a separate outcome would raise A's pooled number materially (25 of its 30
  misses) and the pictures' hardly at all; the rule as applied is the right one for _"can the
  reader answer"_ and the wrong one for _"does the artifact mislead"_, and the two questions have
  opposite answers here.
- **Four contracts, two models, two repeats, no confidence intervals.** Differences of one or two
  answers in a column of sixteen are within what a second run could reverse (16 of 24 cells were
  stable across two repeats; 8 were not). The per-contract tables are the data; the pooled
  percentages are a summary of four cases, not a population estimate.

What would move the question forward, in cost order: (i) repair `WhatIf`'s open-binder refusal and
rerun the same 48 readings — cheap, and the README's regeneration path already exists; (ii) give
A readers the same calendar conversion as B and C; (iii) rerun outside the Claude Code harness,
with a bare API call and a fixed system prompt, so the one thing `transcripts/` still cannot show
is removed; (iv) a vision run, with B and C rendered, to separate _content_ from _drawing_; and
then, still, (v) the reader experiment §7.3 actually asks for.
**Item (i) was done on 2026-09-21 and is §6. Items (ii)–(v) are still open**, and (ii) is now
worse than open: §6.6.

---

# RUN 2 — 2026-09-21

Item (i) of run 1's cost-order list, executed: `WhatIf`'s open-binder refusal repaired, all twelve
artifacts re-cut on the repaired binary, and the same 48 readings taken again. Scored rows:
[`results-run2.json`](./results-run2.json). Every number in §6 is computed from that file.

## 6.1 What changed between the runs — and why almost nothing is attributable

**The runs did not hold the artifacts fixed.** Three separate things moved, and only the first is
the experiment. The re-cut commit (`e633e2e58`) classifies every changed file by cause and is the
primary record; the table below is that classification, plus which files it left alone.

| artifact  | what moved                                                                                                                                                                                                                                                                          | is it the experiment?                         |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **A** (a) | the bound-variable repair — `contracts`, `tenancy` and `promissory-note` now print what discharges the obligation where they printed a refusal                                                                                                                                      | **yes, by design. This is what run 2 tests.** |
| **A** (b) | unrelated `unstable` drift the same re-cut picked up: the breach line now appends _"the breach names, in order: …"_; a `LEST` is anchored at the missed deadline, so the note's reparation is day `739752`, not `739769`; the action text re-renders per member                     | **no.** Not this branch's, not the repair's   |
| **B**     | **one file of four.** `contracts/B.dot` only, a four-line label change (`B must payment OF fine` → `B must payment …`), which the committed golden `jl4/examples/state-graphs/aContract.dot` already carried at the branch base                                                     | **no.** Unrelated, and tiny                   |
| **C**     | **three files of four.** `tenancy/C.bpmn` (206 lines) and `every-run-example/C.bpmn` (19) are straight copies of BPMN goldens that moved pre-base — the multi-instance collection jBPM accepts, plus six corrected fidelity notes — and `contracts/C.bpmn` took the same label as B | **no.** Unrelated                             |

Note the correction this makes to the obvious framing: **A did not change only by design.** Row (b)
is unrelated drift on A, and §6.6 and §6.7.3 show it moved A's score further than the repair did.

**Method differences from run 1**, which weaken row-for-row comparison independently of the
artifacts:

| item     | run 1                                                     | run 2                                                                               |
| -------- | --------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| readers  | single-turn Claude Code subagents, harness default effort | inside a workflow, **medium** effort                                                |
| packet   | header named the artifact kind ("a diagram … in DOT")     | header is the bare word `Document` — run 2's readers were **more** blinded          |
| judging  | one rule in the prompt, a second inferred from rationales | **both rules stated verbatim to every judge**; §6.3 on whether they were held       |
| recorded | prompts, verbatim answers, judge outputs, model ids       | **packets only** (`transcripts-run2/`); answers and judge outputs were not captured |

## 6.2 The control — 27 of 80 answers flipped on documents that did not change

This is the most important number in either run, and it was available only because the re-cut left
most of B and one C alone.

**Four (contract, artifact) cells are byte-identical between the runs** — same artifact file, same
`history.txt`, same `truth.json`, same five questions:
`every-run-example/B`, `tenancy/B`, `promissory-note/B`, `promissory-note/C`. Sixteen readings,
**80 answers, on documents that did not move at all.**

| control cell          | run 1 (Q1…Q5) | run 2 (Q1…Q5) | run 1     | run 2     | delta   |
| --------------------- | ------------- | ------------- | --------- | --------- | ------- |
| `every-run-example` B | 4 4 4 4 4     | 3 4 2 4 3     | 20/20     | 16/20     | −4      |
| `tenancy` B           | 3 4 2 4 4     | 2 3 3 4 3     | 17/20     | 15/20     | −2      |
| `promissory-note` B   | 2 3 3 3 3     | 1 4 2 0 1     | 14/20     | 8/20      | −6      |
| `promissory-note` C   | 2 2 2 2 2     | 0 4 2 0 3     | 10/20     | 9/20      | −1      |
| **total**             |               |               | **61/80** | **48/80** | **−13** |

**27 of those 80 answers flipped — 33.8%.** On the gate's own window the control fell 35/48 → 30/48,
a **−5** drift on Q1–Q3 over inputs that did not change.

Set that beside the experiment: over the twenty cells whose document _did_ change, the total moved
**+7 of 160**. **The instrument moved further, on nothing, than the experiment moved on everything.**

Three things this does and does not license:

- **It does not retract the mechanistic findings.** `contracts` A Q2 going 1/4 → 4/4 is tied to a
  specific sentence that appeared in a specific artifact (§6.7.1); that is not drift.
- **It does retract every pooled across-run comparison in this file** — including the one §7.3's
  reopening condition is phrased in terms of. A difference of four or five answers in a
  48-answer column is exactly the size of the measured drift.
- **It is not a pure repeat**, and the caveat cuts both ways: the packet header and the effort
  setting also differ (§6.1), so the 33.8% is _reader framing plus model plus judge_ variance, not
  sampling variance alone. A true test-retest — same packets, same settings, twice — has never been
  run, and is now the cheapest thing anyone could do with these materials.

Run 1's limit (vi) said _"a one- or two-answer difference in a column of sixteen is within what a
rerun could reverse."_ It was right, and it was **understated**.

## 6.3 Auditability, and the ±2 caveat

Run 1's §1 closes with _"a count that turns on either rule is ±2, not exact"_, because one of the
two scoring rules was never written down and neither was applied uniformly. **That specific caveat
does not carry over to run 2, and the rationales bear that out**: run 2's rationales repeatedly cite
one another by row to justify equal treatment — _"scored identically to B/sonnet/1's Q3"_, _"the
same treatment given A/sonnet/0 and A/sonnet/1"_, _"applied uniformly across all four sonnet rows"_,
_"I scored the two phrasings identically rather than reading one as looser"_. Nothing of that kind
appears in run 1's rationales. Within a contract, run 2 is visibly more consistent than run 1.

**Two things replace it rather than removing it:**

1. **Across contracts, nothing was enforced.** There were four judge instances, one per contract, as
   in run 1. The boundary that decides most of run 2's zeroes — how much hedging turns _incomplete,
   scores 1_ into _a refusal, scores 0_ — is visibly drawn in different places. The `contracts`
   judge scored a hedged Q5 **1** because _"the answer first states the truth and only declines on
   what lies beyond"_; the `promissory-note` judge scored hedged Q1 and Q4 answers **0** for leaving
   the operative verdict _"undetermined"_. Those may be different facts, but nothing in the
   materials proves it, and §6.2 shows the aggregate consequence.
2. **One rationale contains a visible, uncorrected self-correction.**
   `every-run-example/B/haiku/1` begins _"Q4 scores 0 under rule 2 — wait, Q1 is the failure"_. The
   scores vector is `[0,1,1,1,1]`, which matches the corrected reading, so the **score** is right
   and the prose is untidy. It is left verbatim because it is the judge's output.

**And run 2 is less auditable than run 1 overall**, which is the more consequential limit: the
readers' verbatim answers and the judges' outputs were not captured.
[`transcripts-run2/README.md`](./transcripts-run2/README.md) states exactly what is and is not
there. The consequence: a run-2 rationale is the judge's report of an answer **nobody else can now
read**, so §6's classifications cannot be checked against the source text the way §3's can. Run 1
fixed this defect after a review; run 2 reintroduced it.

## 6.4 Results — run 2

### 6.4.1 Per contract

| contract              | artifact | Q1  | Q2  | Q3  | Q4  | Q5  | all       |
| --------------------- | -------- | --- | --- | --- | --- | --- | --------- |
| **contracts**         | A list   | 4/4 | 4/4 | 4/4 | 2/4 | 2/4 | 16/20 80% |
|                       | B DOT    | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
| **every-run-example** | A list   | 4/4 | 4/4 | 4/4 | 2/4 | 4/4 | 18/20 90% |
|                       | B DOT    | 3/4 | 4/4 | 2/4 | 4/4 | 3/4 | 16/20 80% |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
| **tenancy**           | A list   | 4/4 | 1/4 | 0/4 | 4/4 | 2/4 | 11/20 55% |
|                       | B DOT    | 2/4 | 3/4 | 3/4 | 4/4 | 3/4 | 15/20 75% |
|                       | C BPMN   | 3/4 | 4/4 | 4/4 | 4/4 | 4/4 | 19/20 95% |
| **promissory-note**   | A list   | 0/4 | 3/4 | 0/4 | 3/4 | 3/4 | 9/20 45%  |
|                       | B DOT    | 1/4 | 4/4 | 2/4 | 0/4 | 1/4 | 8/20 40%  |
|                       | C BPMN   | 0/4 | 4/4 | 2/4 | 0/4 | 3/4 | 9/20 45%  |

### 6.4.2 Pooled over the four contracts

| artifact   | Q1        | Q2        | Q3        | Q4    | Q5        | Q1–Q3         | Q4–Q5         | all               |
| ---------- | --------- | --------- | --------- | ----- | --------- | ------------- | ------------- | ----------------- |
| **A** list | **12/16** | 12/16     | 8/16      | 11/16 | 11/16     | 32/48 **67%** | 22/32 **69%** | 54/80 **67.5%**   |
| **B** DOT  | 10/16     | 15/16     | 11/16     | 12/16 | 11/16     | 36/48 **75%** | 23/32 **72%** | 59/80 **73.75%**  |
| **C** BPMN | 11/16     | **16/16** | **14/16** | 12/16 | **15/16** | 41/48 **85%** | 27/32 **84%** | 68/80 **85%**     |
| all        | 33/48     | 43/48     | 33/48     | 35/48 | 37/48     | 109/144 76%   | 72/96 75%     | 181/240 **75.4%** |

Readings in which all five answers were right: A 4/16, B 7/16, C 11/16.

### 6.4.3 By reader model

| model  | A list      | B DOT       | C BPMN    | total      |
| ------ | ----------- | ----------- | --------- | ---------- |
| haiku  | 23/40 57.5% | 30/40 75%   | 32/40 80% | 85/120 71% |
| sonnet | 31/40 77.5% | 29/40 72.5% | 36/40 90% | 96/120 80% |

The two repeats of a cell gave the identical five-vector in **14 of 24** cells, against run 1's 16
of 24 — so run 2 is, if anything, slightly noisier per cell, not tighter. Sonnet beats haiku on A
and C and loses on B; in run 1 it beat haiku on A and B and lost on C. **The model ordering is not
stable across runs on any artifact but A.**

## 6.5 The delta, whole

Run 2 minus run 1, per artifact and question. **Read it against §6.2: the control drifted −13 of 80
on documents that did not change, so no cell in this table is attributable except A's Q2, and even
that is one judge instance against another.**

| artifact   | Q1  | Q2     | Q3  | Q4  | Q5  | all     |
| ---------- | --- | ------ | --- | --- | --- | ------- |
| **A** list | −4  | **+4** | −7  | +4  | +7  | **+4**  |
| **B** DOT  | −3  | ±0     | −2  | −3  | −4  | **−12** |
| **C** BPMN | −3  | +2     | ±0  | −2  | +5  | **+2**  |

Pooled over everything the two runs are nearly equal — 187/240 against 181/240 — and that
near-equality is deceptive: the **composition** moved a great deal, in both directions, on all three
artifacts.

**The one qualitative finding of run 1 that run 2 flatly does not reproduce is §3's loud-vs-silent
split.** Classifying run 2's 59 misses the same way, from the rationales:

| artifact   | misses | "cannot tell" (loud) | incomplete / vague | wrong assertion (silent) |
| ---------- | ------ | -------------------- | ------------------ | ------------------------ |
| **A** list | 26     | 9                    | 2                  | **15**                   |
| **B** DOT  | 21     | 10                   | 0                  | 11                       |
| **C** BPMN | 12     | 7                    | 0                  | 5                        |

Run 1's headline — _the list fails loudly (25 of 30), the pictures fail silently (0 and 1 loud
refusals)_ — is gone. In run 2 the list's misses are majority **wrong assertions**, and both
pictures refuse freely. Part of A's shift is measurement, not behaviour: up to 8 of A's 15 wrong
assertions are the stale-key artifact of §6.6, and stripping those leaves A at 9 loud / 2 vague /
7 wrong — still not run 1's 25-vs-2. The classification is mine, from the rationales, with the added
weakness §6.3 gives it: **in run 2 I cannot check a rationale against the answer it describes.**

## 6.6 The largest single defect in run 2: the note's key was not corrected with its artifact

`promissory-note/truth.json` carries a `drift` key, written 2026-09-21, which says in terms:

> whoever re-cuts `A.txt` must, in the same change, replace 739769 → 739752, "3 June 2025" →
> "17 May 2025", "61 days from now" → "44" … Correcting this file while `A.txt` still says 739769
> would put the key and the readers' inputs on different trees, which is the same defect in the
> other direction.

**The re-cut moved `A.txt` and did not move the key.** `promissory-note/A.txt` now prints
_"due by 739752 (44 from now)"_ — the tree's number, correct — and `truth.json` still answers
_"by 3 June 2025 (day 739769; 61 days from now)"_. `git show e633e2e58 --name-only` confirms no
`truth.json` was touched. So run 2's four `promissory-note` A readers were **marked wrong for
printing the number the artifact printed**. It is in the rationales verbatim: _"Q1 names the right
parties and the right penalty amount (2369.28) but dates it 739752/44-from-now, which contradicts
truth.json's 739769/61"_; and, on one row, _"Q4 would otherwise have passed as
incomplete-but-clean"_.

Counting from `results-run2.json`, A has **11 misses on that contract, and 8 of them name the day
serial as a stated ground** — the whole of the Q1 column (0/4), three of the four Q3 misses, and one
Q4. Seven of the eight are inside Q1–Q3, the gate's own window.

**Stated as a range, not a re-score.** `promissory-note` A, as scored, is Q1 0/4 and Q3 0/4. Setting
aside only the four Q1 answers whose sole stated ground is the stale numeral puts A's pooled Q1–Q3
at **36/48**; setting aside all seven day-serial-grounded Q1–Q3 misses puts it at **39/48**, run 1's
figure exactly. The rows have **not** been re-scored, and the middle figure is the more defensible,
because the three Q3 rows each carry a second, independent ground (a breach assertion the truth
denies, or a refusal).

The key must be corrected and the note's artifacts re-cut **in one change** before any
`promissory-note` column from run 2 is quoted. Until then that contract's A columns are measuring
the key, not the list. Run 1's §3.3 predicted this defect by name; the re-cut walked into the half
of it the `drift` note did not spell out as loudly.

## 6.7 What run 2 found that run 1 could not have

Each of these is tied to a specific sentence in a specific artifact, which is what distinguishes
them from the pooled deltas §6.2 disqualifies.

### 6.7.1 The repair works, and on one contract it works completely

`contracts` A Q2: **1/4 → 4/4**. The refusal is gone and the list now prints _"B does anything now
(at 10) → fulfilled … this obligation's pattern matches any act by B: the rule binds `return`
rather than naming an act"_, which is very nearly `truth.json`'s own sentence. Q5 on the same
contract went 0/4 → 2/4, because the `→ then:` continuation now prints there too. That contract's
A total went 11/20 → 16/20. `contracts/B.dot` and `C.bpmn` were at 20/20 in both runs, so this cell
is not carried by the drift §6.2 measures.

### 6.7.2 But printing the answer does not guarantee it is read

`tenancy` A Q2: **1/4 → 1/4. No movement at all**, although the repair landed squarely on this
contract — `tenancy/A.txt` now lists all three tenants' payments under _"What would move things
along"_, each _"with any `amount`"_, with the replay's consequences. Three of four readers did not
use it: two haiku readers answered a bare _"cannot tell from this"_, and one sonnet reader recited
the payment acts and then stated that the artifact _"does not say what event(s) would actually
discharge what is owed"_. Only `sonnet/1` used the printed block.

This is the most uncomfortable result in either run: **the deficit run 1 diagnosed as "the list does
not print the discharge" was only partly that.** On `tenancy` the list now prints it and three of
four readers still failed the question.

One hypothesis the materials support and do not establish: the block prints under the heading
_"What would move things along (neither ends nor breaches it)"_, which does not contain the word
"discharge", while Q2 asks _"which event(s) would discharge what is owed"_ — and on `contracts`,
where the same repair scored 4/4, the heading reads _"What would discharge it (the contract ends
fulfilled)"_. Two headings, two outcomes, same repair. That is cheap to test by re-reading the one
cell with the headings swapped, and it is not tested here.

### 6.7.3 A line added for precision cost the list a whole column

`tenancy` A Q3: **4/4 → 0/4**, and the cause is identifiable. Run 1's `A.txt` printed

```
- nothing happens by 7 (the clock reaches 8) → Tenant OF "Alice" is in breach
```

and run 2's prints that line with a clause appended:

```
- nothing happens by 7 (the clock reaches 8) → Tenant OF "Alice" is in breach; the breach names, in order: Tenant OF "Alice", Tenant OF "Bob", Tenant OF "Carol"
```

That clause is a faithful rendering of `lts.json`, whose breach object carries `party: Alice` (the
blame) beside `names: [Alice, Bob, Carol]` (the members the breach names). `truth.json` Q3 answers
that the breach is **named to Alice**. All four run-2 readers read the appended clause as collective
breach — _"all three tenants are in breach"_, _"that single deadline is what puts all three in
breach"_, _"the breach names Alice, Bob, and Carol in that order"_ — where all four run-1 readers,
given the shorter line, got it right.

Stated at the strength the evidence supports: the appended clause is the only change to that part of
the artifact, and the column went from 4/4 to 0/4 across two models and two repeats. That is
correlational at n = 4 against n = 4 — and §6.2 is the reason to hold it loosely, since a four-answer
swing is the size of the measured drift. It is the strongest single signal in the rerun and it is
not proof.

**It is also not the repair's doing** — the clause is `unstable` drift the re-cut picked up (§6.1
row b) — so run 2 found a defect in a line nobody was measuring. If it holds, the fix is a wording
change, not a picture: the clause has to distinguish _who is in breach_ from _whose names the breach
carries_, which is the distinction `lts.json` already draws and the sentence does not.

## 6.8 What run 2 does to run 1's five findings

| run 1's finding                                              | run 2                                                                                                                                                                                                                                                                             |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1.** On Q1 and Q3 the list is not beaten (16/16, 15/16)    | **Q1 holds, Q3 does not.** Q1: A 12/16 vs B 10/16, C 11/16 — the list is still ahead, and further ahead once §6.6's four stale-key misses are set aside. **Q3: A 8/16 vs B 11/16, C 14/16 — the list is now behind both**, on §6.6 and §6.7.3                                     |
| **2.** The Q2 loss is entirely `WhatIf`'s refusal            | **Half held.** Q2 8/16 → 12/16 (+4). `contracts` 1/4 → 4/4; `promissory-note` 2/4 → 3/4; **`tenancy` 1/4 → 1/4** (§6.7.2). The refusal was a real cause and not the only one                                                                                                      |
| **3.** On Q4–Q5 the list loses badly (11/32 vs 30/32, 24/32) | **Reversed on the list's own side.** A 11/32 → **22/32**, level with B's 23/32 and behind C's 27/32. The `→ then:` continuation now prints on three contracts instead of one. B's and C's own drops are inside §6.2's drift                                                       |
| **4.** The list fails loudly, the pictures silently          | **Not reproduced** (§6.5). A's misses are majority wrong assertions even after §6.6's artifact is stripped; B and C both refuse freely                                                                                                                                            |
| **5.** The DOT is the best artifact (71/80)                  | **Not reproduced.** DOT 59/80, **BPMN 68/80 is the best**. Three of four B cells and one C cell did not change at all, and those alone account for −13 (§6.2), so this is drift and not a finding about serialisations. **Neither run's artifact ranking should be quoted again** |

## 6.9 The bearing on §7.3 — plainly, and in both directions

§7.3's ruling of 2026-09-21 (NO, P2d and P2e are not built) names three conditions that would
reopen it. The first is: _"the repaired list still failing Q1–Q3 when these same 48 readings are
rerun."_ That is this run.

**On the numbers as scored, the list fails. The condition is met.** Q1–Q3 pooled: **A 32/48,
B 36/48, C 41/48**. The repaired list is the **worst** of the three artifacts on the gate's own
three questions, where in run 1 it was within three answers of both. §7.3's point 1 rested on the
sharper claim that _"on Q1 and Q3 alone the list is ahead of both pictures"_; in run 2 it is ahead
on Q1 and behind both on Q3. **The ruling is therefore not confirmed by the measurement it named as
its reopening condition, and it goes back to Meng.**

**The same run also weakens §7.3's own stated counterweight.** Point 5 of the ruling is that _"on Q4
and Q5 the list loses badly — 11/32, against B's 30/32 and C's 24/32"_. In run 2 the list is at
22/32, level with the DOT. The repair moved the list on exactly the two questions §1.1a said a list
cannot answer.

**And the run cannot bear the weight of either reading.** This is not a softening of the verdict
above — it is the third fact Meng needs:

- **§6.2.** The control cells drifted **−13 of 80** on documents that did not change, and **−5 of
  48** inside the Q1–Q3 window. A's Q1–Q3 fell −7 in that window. The gap between A (32) and B (36)
  is four answers; the drift is five.
- **§6.6.** Seven of A's sixteen Q1–Q3 misses are scored against a **key left stale while the
  artifact was re-cut**. Correcting only the clearest four puts A at 36/48, level with B.
- **§6.7.3.** `tenancy` Q3 went 4/4 → 0/4 on a **one-clause wording change unrelated to the
  repair** — a list defect worth fixing, and not a fact about lists.

So: **nothing here shows that _a list_ cannot answer Q3.** A's Q3 column fell for two identified,
repairable reasons in the materials, on top of a drift larger than the effect.

**The recommendation to the ruling's owner, which is a recommendation and not a decision:** fix the
note's key and re-cut in one change; fix or re-word the breach-names clause; run the test-retest
§6.2 asks for, so the next comparison has an error bar; then re-run. Do not build P2d on this run,
and do not treat the 2026-09-21 ruling as confirmed either. §7.3 is where the decision belongs.

## 6.10 What run 2 still cannot decide

Every limit in §5 applies unchanged — no human read anything, no cognitive load was measured, B and
C were read as text, the judge is an LLM, four contracts and two repeats. Run 2 adds three of its
own:

1. **Its instrument moved more than its subject** (§6.2), so no pooled across-run number in this
   file survives as evidence.
2. **It is less auditable than run 1** (§6.3): no verbatim reader answers, no judge outputs.
3. **It was run against a key known to be stale** (§6.6), on the one contract the README picked for
   being hardest.

Run 1's cost-order list, restated with run 2's statuses: (i) repair and rerun — **DONE, and it is
§6, with the caveats above**; (ii) equalise the note's calendar conversion across A/B/C — **open,
and now urgent**, because the directory is carrying a key and an artifact on different trees;
(iii) rerun outside the harness with a bare API call and a fixed system prompt — **open**, and run 2
makes it the highest-value item on the list, since §6.2 shows the harness-and-judge variance is
larger than any effect measured so far; (iv) a vision run with B and C rendered — **open**; (v) the
reader experiment §7.3 actually asks for — **open**. A sixth is now added by §6.2: **a true
test-retest — the same packets, the same settings, twice — which has never been run and is the
cheapest of all of them.** None of these is decided here.
