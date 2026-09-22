# The §7.3 gate — an LLM-reader PROXY: RUN 1 (2026-09-16) and RUN 2 (2026-09-21)

**Status: two runs, both as a proxy. Neither is the gate, and this file records no verdict on the
gate.** [`LTS-VISUALISER.md`](../../specs/todo/lexipedia-superset/LTS-VISUALISER.md) §7.3 gates the
two-plane picture on a **reader** experiment — can readers answer _what do I owe, what discharges it,
what breaches it_ from the plain list (`l4 lts`), and does a picture add _where am I_ and _what
happens after_ (§1.1a)? No human has been shown anything, in either run. What was run is the proxy
the [`README.md`](./README.md) in this directory prepares: fresh LLM readers, each shown **one**
artifact for one contract and nothing else, asked the five questions, scored against `truth.json`.

| run       | date       | scored rows                                | primary evidence                                        | what the readers were shown                       |
| --------- | ---------- | ------------------------------------------ | ------------------------------------------------------- | ------------------------------------------------- |
| **run 1** | 2026-09-16 | [`results.json`](./results.json)           | [`transcripts/`](./transcripts/readings.json)           | the **refusing** list; pre-#425/#401/#430 B and C |
| **run 2** | 2026-09-21 | [`results-run2.json`](./results-run2.json) | [`transcripts-run2/`](./transcripts-run2/readings.json) | the **repaired** list; re-cut B and C             |

Every number in this file is computed from those two files and nothing else. **§1–§5 are run 1 and
are kept unaltered as history**; §6 is run 2 and the delta. **Run 2 was scored twice: §6.0 says what
was wrong with the first scoring and what replaced it, and the superseded rows are kept as
[`results-run2-superseded.json`](./results-run2-superseded.json).** Read §6.1 before comparing any
run-1 number against any run-2 number: the two runs did **not** hold the artifacts fixed — and §6.2
measures what that cost, on four cells whose documents did not change at all.

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

**Run 2 reproduces this table** — the list's misses are majority refusals, the DOT's majority wrong
assertions — and §6.5 carries run 2's version of it.

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
> `739752` and left `truth.json` at `739769`, so run 2's first scoring marked its `promissory-note` A
> readers wrong for printing the number the tree prints. The key has since been re-derived and all
> four contracts re-judged: §6.0 and §6.6. Run 1's own scores are unaffected — its readers were shown
> `739769` and its key said `739769`.

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
artifacts re-cut on the repaired binary, and the same 48 readings taken again.
Scored rows: [`results-run2.json`](./results-run2.json).
Every number in §6 is computed from that file.

## 6.0 Run 2 was scored twice, and only the second scoring is a result

**What happened, plainly.**
Run 2's first scoring judged `promissory-note` against an answer key that `12055ae73` (2026-09-17, `EVERY-EACH-QUANTIFIER-SPEC` §5.2) had invalidated.
That commit anchors a `LEST` at the **missed deadline** rather than at the act that reveals it, so the note's reparation falls due day **739752** (17 May 2025, 44 days from the position), not day 739769 (3 June 2025, 61 days).
The re-cut `A.txt` and `lts.json` have printed 739752 since `e633e2e58`; `truth.json` still said 739769 in three of its five answers.
**Readers who read the artifact correctly were therefore scored wrong** — and not only on the number: the stale key also made `A.txt`'s no-breach answer look like a refusal, and cost Q5 its witness.

**What was done about it.**
`truth.json` was re-derived from the tree (`9354b6cf4`): every answer and every evidence line re-read off the re-cut `A.txt`, `lts.json` and a regenerated `probes.out`, on a snapshot binary that reproduces the committed `A.txt` byte for byte.
Then **all four contracts were re-judged from scratch** against the repaired key, under the same two rules, by one judge rather than four.
The first scoring is kept as [`results-run2-superseded.json`](./results-run2-superseded.json) with a header note saying what it was; the numbers below are the re-judging, and **no figure from the superseded scoring should be quoted again**.

**What this bought, beyond the note.**
Re-judging all four contracts under one judge removes §6.3's first limit — that the incomplete-versus-refusal boundary was drawn in different places by four judge instances — and it moves far more than the note: **24 of 240 answers** are scored differently from the superseded scoring, on all four contracts and all three artifacts.
That is the measure of how much of run 2 was ever the judge rather than the reader, and it is why §6.2's control reads differently below.

**And run 2 is now auditable.**
The readers' verbatim answers were recovered and are committed as [`transcripts-run2/readings.json`](./transcripts-run2/readings.json), beside the packets that were already there.
So every rationale in `results-run2.json` can be checked against the answer it describes, which run 2's first write-up said could not be done.
The judges' own outputs from the first scoring are still not captured; the superseded file is all that survives of them.

**The scoring boundary, written down once so it is checkable.**
Both rules are run 1's, verbatim: an answer is 1 if it is correct against the truth, allowing paraphrase, and _"cannot tell" is 0 unless the truth says the artifact cannot say it_ (rule 1); an answer that is **incomplete but asserts nothing wrong** is 1 (rule 2).
The case they do not settle between them is the hedged answer, and it is decided here as follows, uniformly across all four contracts:

- an answer that **states the truth's operative content and then declines on what lies beyond it** is 1 — the hedge sits beside the answer, it does not replace it;
- an answer that states the content and then **retracts to a refusal as its verdict** is 0;
- a **bare refusal** is 0 wherever the artifact does carry the answer, and 1 where it genuinely does not;
- an answer that is true but **omits what the question asked for** is 1 under rule 2;
- an answer that **asserts something the truth contradicts, on the matter that question asks about**, is 0 — including where a correct sentence is followed by a false gloss.

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
is unrelated drift on A, and it is the source of both §6.0's stale key and §6.7.3's wording defect.

**Three method differences from run 1**, which weaken row-for-row comparison independently of the
artifacts, and which are the reason the across-run delta in §6.5 is weaker evidence than any
comparison made **inside** one run:

| item    | run 1                                                     | run 2                                                                           |
| ------- | --------------------------------------------------------- | ------------------------------------------------------------------------------- |
| readers | single-turn Claude Code subagents, harness default effort | inside a workflow, at **fixed medium** effort                                   |
| packet  | header named the artifact kind ("a diagram … in DOT")     | header is the bare word `Document` — run 2's readers were **more** blinded      |
| judging | one rule in the prompt, a second inferred from rationales | **both rules stated verbatim**, and (since §6.0) one judge across all contracts |

## 6.2 The control — the instrument is noisy per answer, and nearly flat in total

The re-cut left four (contract, artifact) cells alone: `every-run-example/B`, `tenancy/B`,
`promissory-note/B` and `promissory-note/C` are **byte-identical between the runs** — same artifact
file, same `history.txt`, same five questions. Sixteen readings, **80 answers, on documents that did
not move at all.** Their `truth.json` did move for the note, which §6.0 is about; the artifacts did
not.

| control cell          | run 1 (Q1…Q5) | run 2 (Q1…Q5) | run 1     | run 2     | delta  |
| --------------------- | ------------- | ------------- | --------- | --------- | ------ |
| `every-run-example` B | 4 4 4 4 4     | 3 4 4 4 4     | 20/20     | 19/20     | −1     |
| `tenancy` B           | 3 4 2 4 4     | 2 3 4 4 3     | 17/20     | 16/20     | −1     |
| `promissory-note` B   | 2 3 3 3 3     | 2 4 2 2 1     | 14/20     | 11/20     | −3     |
| `promissory-note` C   | 2 2 2 2 2     | 2 4 2 2 4     | 10/20     | 14/20     | **+4** |
| **total**             |               |               | **61/80** | **60/80** | **−1** |

**Read the two halves of this separately, because they say different things.**

- **Per answer the instrument is noisy: 23 of those 80 answers flipped, 28.8%** — on inputs that did
  not change. A single answer's score is not a stable measurement, and a one- or two-answer
  difference in a column of sixteen remains inside what a rerun could reverse. Run 1's limit (vi)
  said exactly this and it holds.
- **In total the instrument is nearly flat: −1 of 80, and +1 of 48 inside the gate's Q1–Q3 window.**
  The flips cancel. Set that beside the experiment: over the eight cells whose document **did**
  change, the total moved **+19 of 160**. **The experiment moved further, on the documents that
  changed, than the instrument moved on the ones that did not** — which is the condition a rerun has
  to meet before any of its deltas can be read, and run 2 meets it.

**This reverses the finding run 2's first write-up led with**, which was a control drift of −13 of 80
and the conclusion that _"the instrument moved further, on nothing, than the experiment moved on
everything"_. That −13 was mostly the four-judge scoring, not the readers: under one judge the same
80 answers total −1. What survives is the per-answer instability, which is real and is why §6.5's
across-run deltas are still the weakest numbers in this file.

The caveat cuts both ways and is unchanged: the packet header and the effort setting also differ
(§6.1), so the 28.8% is _reader framing plus model plus judge_ variance, not sampling variance
alone. **A true test-retest — same packets, same settings, twice — has still never been run**, and
is still the cheapest thing anyone could do with these materials.

## 6.3 Auditability

Run 1's §1 closes with _"a count that turns on either rule is ±2, not exact"_, because one of the
two scoring rules was never written down and neither was applied uniformly. **Neither half of that
caveat carries over to run 2 as it now stands.** Both rules were stated verbatim to every reader's
judge, the hedge boundary they leave open is written out in §6.0 and was applied across all four
contracts by one judge, and the readings the rationales describe are committed.

What replaces it is smaller and should be said anyway:

1. **One judge is uniform, not correct.** Consistency across contracts removes the failure mode run 2
   was first written up as having; it does not make the boundary in §6.0 the right boundary. A
   different line between _incomplete_ and _refusal_ would move several answers, and §6.0 names which
   kinds.
2. **The judge is an LLM**, unchanged from run 1 and unchanged by any of this.
3. **The first scoring's judge outputs were never captured**, so the 24 answers §6.0 counts as
   re-scored can be compared as scores and rationales but not as judging transcripts.

## 6.4 Results — run 2

### 6.4.1 Per contract

| contract              | artifact | Q1  | Q2  | Q3  | Q4  | Q5  | all       |
| --------------------- | -------- | --- | --- | --- | --- | --- | --------- |
| **contracts**         | A list   | 4/4 | 4/4 | 4/4 | 4/4 | 2/4 | 18/20 90% |
|                       | B DOT    | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
| **every-run-example** | A list   | 4/4 | 4/4 | 4/4 | 2/4 | 4/4 | 18/20 90% |
|                       | B DOT    | 3/4 | 4/4 | 4/4 | 4/4 | 4/4 | 19/20 95% |
|                       | C BPMN   | 4/4 | 4/4 | 4/4 | 4/4 | 4/4 | 20/20     |
| **tenancy**           | A list   | 4/4 | 1/4 | 1/4 | 4/4 | 2/4 | 12/20 60% |
|                       | B DOT    | 2/4 | 3/4 | 4/4 | 4/4 | 3/4 | 16/20 80% |
|                       | C BPMN   | 3/4 | 4/4 | 4/4 | 4/4 | 4/4 | 19/20 95% |
| **promissory-note**   | A list   | 4/4 | 4/4 | 3/4 | 4/4 | 3/4 | 18/20 90% |
|                       | B DOT    | 2/4 | 4/4 | 2/4 | 2/4 | 1/4 | 11/20 55% |
|                       | C BPMN   | 2/4 | 4/4 | 2/4 | 2/4 | 4/4 | 14/20 70% |

### 6.4.2 Pooled over the four contracts

| artifact   | Q1        | Q2        | Q3    | Q4    | Q5        | Q1–Q3         | Q4–Q5         | all               |
| ---------- | --------- | --------- | ----- | ----- | --------- | ------------- | ------------- | ----------------- |
| **A** list | **16/16** | 13/16     | 12/16 | 14/16 | 11/16     | 41/48 **85%** | 25/32 **78%** | 66/80 **82.5%**   |
| **B** DOT  | 11/16     | 15/16     | 14/16 | 14/16 | 12/16     | 40/48 **83%** | 26/32 **81%** | 66/80 **82.5%**   |
| **C** BPMN | 13/16     | **16/16** | 14/16 | 14/16 | **16/16** | 43/48 **90%** | 30/32 **94%** | 73/80 **91.25%**  |
| all        | 40/48     | 44/48     | 40/48 | 42/48 | 39/48     | 124/144 86%   | 81/96 84%     | 205/240 **85.4%** |

Readings in which all five answers were right: A 8/16, B 10/16, C 13/16.

**The same table with `promissory-note` removed**, because that is the contract whose key was the
subject of §6.0 and a reader is entitled to see the run without it:

| artifact   | Q1        | Q2    | Q3    | Q4    | Q5    | Q1–Q3         | all             |
| ---------- | --------- | ----- | ----- | ----- | ----- | ------------- | --------------- |
| **A** list | **12/12** | 9/12  | 9/12  | 10/12 | 8/12  | 30/36 **83%** | 48/60 **80.0%** |
| **B** DOT  | 9/12      | 11/12 | 12/12 | 12/12 | 11/12 | 32/36 **89%** | 55/60 **91.7%** |
| **C** BPMN | 11/12     | 12/12 | 12/12 | 12/12 | 12/12 | 35/36 **97%** | 59/60 **98.3%** |

**The two cuts do not agree about the list, and §6.9 does not hide that.** Pooled over all four
contracts the list is **not** last on Q1–Q3 (41 against 40 and 43); with the note removed it **is**
last (30 against 32 and 35). The note is now the one contract whose key has been re-derived from the
tree in the last day, which is an argument for the four-contract figure and not against it — but it
is also the contract where the list most outscores both pictures, so the cut is not neutral either
way. Both are stated; neither is the headline.

### 6.4.3 By reader model

| model  | A list    | B DOT     | C BPMN      | total        |
| ------ | --------- | --------- | ----------- | ------------ |
| haiku  | 28/40 70% | 30/40 75% | 33/40 82.5% | 91/120 75.8% |
| sonnet | 38/40 95% | 36/40 90% | 40/40 100%  | 114/120 95%  |

**The model gap is the largest single effect in either run — 23 answers of 120 — and it is larger
than every artifact gap in the table above.** Sonnet is ahead on all three artifacts, which run 1
was not: there it beat haiku on A and B and lost on C. Two repeats cannot separate the models from
the noise, but a gap this size on a run whose control totals −1 is worth saying plainly: **the
reader matters more than the artifact.** Whatever §7.3 is decided on, it is being decided on a
difference smaller than the difference between two of Anthropic's own models reading the same page.

The two repeats of a cell gave the identical five-vector in **17 of 24** cells, against run 1's 16 of
24 — marginally tighter, not noisier.

## 6.5 The delta, whole

Run 2 minus run 1, per artifact and question. **Read it against §6.1's three method changes and
§6.2's 28.8% per-answer flip rate:** the across-run comparison is the weakest kind of number in this
file, and a cell of ±2 in a column of sixteen carries no weight on its own.

| artifact   | Q1  | Q2     | Q3  | Q4     | Q5     | all     |
| ---------- | --- | ------ | --- | ------ | ------ | ------- |
| **A** list | ±0  | **+5** | −3  | **+7** | **+7** | **+16** |
| **B** DOT  | −2  | ±0     | +1  | −1     | −3     | **−5**  |
| **C** BPMN | −1  | +2     | ±0  | ±0     | +6     | **+7**  |

Pooled, run 1 is 187/240 and run 2 is 205/240. The list is the artifact that moved, +16 of 80, and
it moved on Q2, Q4 and Q5 — the three columns the repair prints into.

**Run 1's loud-versus-silent split is reproduced.** Run 2's first write-up reported it as the one
qualitative finding that did not survive; under the repaired key and one judging boundary it does.
Classifying run 2's 35 misses the same way §3 classifies run 1's:

| artifact   | misses | "cannot tell" (loud) | incomplete / vague | wrong assertion (silent) |
| ---------- | ------ | -------------------- | ------------------ | ------------------------ |
| **A** list | 14     | **10**               | 0                  | 4                        |
| **B** DOT  | 14     | 3                    | 0                  | **11**                   |
| **C** BPMN | 7      | 3                    | 0                  | 4                        |

The list still fails **loudly** (10 of 14) and the DOT still fails **silently** (11 of 14); the BPMN
is split. The classification is mine, from the rationales — and unlike run 2's first write-up, it can
now be checked against the readings themselves.

## 6.6 What the stale key was costing, measured

§6.0 says the note was judged against a key `12055ae73` had invalidated. This is what that cost, and
it is worth a section because the size of it is the reason no note column from the first scoring is
quotable.

`promissory-note` **A**, run 1 → superseded run-2 scoring → re-judged:

| column | run 1 | superseded | re-judged |
| ------ | ----- | ---------- | --------- |
| Q1     | 4/4   | **0/4**    | **4/4**   |
| Q2     | 2/4   | 3/4        | 4/4       |
| Q3     | 3/4   | **0/4**    | 3/4       |
| Q4     | 0/4   | 3/4        | 4/4       |
| Q5     | 0/4   | 3/4        | 3/4       |
| all    | 9/20  | 9/20       | **18/20** |

Every one of the four Q1 answers named the penalty amount and the day the artifact prints, and every
one was marked wrong for printing the tree's number. The note's A cell is not the list's worst in
this run; **it is the list's equal best, 18/20, level with `contracts`.**

Two further consequences of the same anchor move, which the first scoring could not see:

- **Q3 on the note is a no-breach answer, and the list is good at it.** `truth.json` says nothing
  puts the Borrower in breach from here — the obligation converts to a deadline-free "all
  outstanding debts" arm — and `A.txt` prints that conversion under the heading _"What would move
  things along (neither ends nor breaches it)"_. Three of four A readers reached that conclusion;
  the fourth asserted a breach. The pictures did worse on the same question (B 2/4, C 2/4) despite
  `B.dot` labelling the only Breach in-edge _"unreachable: no WITHIN"_.
- **The note's `history.txt` still carries the old conversion table** — _"day 739769 is 3 June
  2025"_ — and gives no conversion for 739752. That is the B and C readers' input, and it is **left
  as it is on purpose**: changing it now would mean the committed readings were taken against a
  packet that no longer exists. It is recorded here instead, and it is owed by the next re-cut.

## 6.7 What run 2 found that run 1 could not have

Each of these is tied to a specific sentence in a specific artifact, which is what distinguishes
them from the pooled deltas §6.5 holds loosely.

### 6.7.1 The repair works, and on two contracts it works completely

`contracts` A Q2: **1/4 → 4/4**. The refusal is gone and the list now prints _"B does anything now
(at 10) → fulfilled … this obligation's pattern matches any act by B: the rule binds `return`
rather than naming an act"_, which is very nearly `truth.json`'s own sentence. Q5 on the same
contract went 0/4 → 2/4. That contract's A total went 11/20 → 18/20.

`promissory-note` A Q2 went **2/4 → 4/4** on the same repair, and that contract's A total 9/20 →
18/20 (§6.6). `contracts/B.dot` and `C.bpmn` were at 20/20 in both runs, so neither cell is carried
by the drift §6.2 measures.

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
"discharge", while Q2 asks _"which event(s) would discharge what is owed"_ — and on `contracts` and
`promissory-note`, where the same repair scored 4/4, the heading reads _"What would discharge it
(the contract ends fulfilled)"_. Two headings, two outcomes, same repair. That is cheap to test by
re-reading the one cell with the headings swapped, and it is not tested here.

### 6.7.3 A line added for precision cost the list most of a column

`tenancy` A Q3: **4/4 → 1/4**, and the cause is identifiable. Run 1's `A.txt` printed

```
- nothing happens by 7 (the clock reaches 8) → Tenant OF "Alice" is in breach
```

and run 2's prints that line with a clause appended:

```
- nothing happens by 7 (the clock reaches 8) → Tenant OF "Alice" is in breach; the breach names, in order: Tenant OF "Alice", Tenant OF "Bob", Tenant OF "Carol"
```

That clause is a faithful rendering of `lts.json`, whose breach object carries `party: Alice` (the
blame) beside `names: [Alice, Bob, Carol]` (the members the breach names). `truth.json` Q3 answers
that the breach is **named to Alice**. Three of the four run-2 readers turned the appended clause
into a collective breach — _"all three tenants are in breach"_, _"the tenants will be in breach"_,
_"that single deadline is what puts all three in breach"_ — where all four run-1 readers, given the
shorter line, got it right. The fourth (`sonnet/1`) quoted the names in order **and** kept Alice as
the party in breach, which is the artifact read correctly; it is the existence proof that the clause
is ambiguous rather than wrong.

Stated at the strength the evidence supports: the appended clause is the only change to that part of
the artifact, and the column went from 4/4 to 1/4 across two models. That is n = 4 against n = 4 and
it is correlational — but §6.2's control now bounds the noise at −1 of 80 in total, so a three-answer
swing in one column is no longer inside the measured drift the way run 2's first write-up said it
was. It remains the strongest single signal in the rerun and it is not proof.

**It is also not the repair's doing** — the clause is `unstable` drift the re-cut picked up (§6.1
row b) — so run 2 found a defect in a line nobody was measuring. If it holds, the fix is a wording
change, not a picture: the clause has to distinguish _who is in breach_ from _whose names the breach
carries_, which is the distinction `lts.json` already draws and the sentence does not.

## 6.8 What run 2 does to run 1's five findings

| run 1's finding                                              | run 2                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1.** On Q1 and Q3 the list is not beaten (16/16, 15/16)    | **Q1 holds outright, Q3 does not.** Q1: A **16/16** against B 11/16 and C 13/16 — every Q1 miss in the run is on a picture, as in run 1. **Q3: A 12/16 against B 14/16 and C 14/16 — the list is behind both**, by two answers, on §6.7.3                           |
| **2.** The Q2 loss is entirely `WhatIf`'s refusal            | **Half held.** Q2 8/16 → 13/16 (+5). `contracts` 1/4 → 4/4; `promissory-note` 2/4 → 4/4; **`tenancy` 1/4 → 1/4** (§6.7.2). The refusal was a real cause and not the only one                                                                                        |
| **3.** On Q4–Q5 the list loses badly (11/32 vs 30/32, 24/32) | **Reversed.** A 11/32 → **25/32**, ahead of B's 26/32 by nothing and behind C's 30/32 by five. The `→ then:` continuation now prints on three contracts instead of one                                                                                              |
| **4.** The list fails loudly, the pictures silently          | **Reproduced** (§6.5): A 10 of 14 misses are refusals, B 11 of 14 are wrong assertions. Run 2's first write-up reported this as not reproduced; that was the stale key and four judging boundaries                                                                  |
| **5.** The DOT is the best artifact (71/80)                  | **Not reproduced.** DOT 66/80, **BPMN 73/80 is the best**, list 66/80 level with the DOT. Three of four B cells and one C cell did not change at all. **Neither run's artifact ranking should be quoted as a fact about serialisations** — see §6.4.3 on the models |

## 6.9 The bearing on §7.3 — plainly, and in both directions

§7.3's ruling of 2026-09-21 (NO, P2d and P2e are not built) names three conditions that would
reopen it. The first is: _"the repaired list still failing Q1–Q3 when these same 48 readings are
rerun."_ That is this run.

**On the re-judged numbers the condition is NOT met, and the ruling stands.** Q1–Q3 pooled over the
four contracts: **A 41/48, B 40/48, C 43/48.** The repaired list is not the worst of the three on the
gate's own three questions — it is second, one answer ahead of the DOT and two behind the BPMN, a
spread of three answers over 48, which is the same picture run 1 gave (39, 41, 42) and is what §7.3's
point 1 called _"not beaten"_. §7.3's sharper sub-claim splits: on **Q1 the list is unbeaten and now
perfect, 16/16**, with every Q1 miss in the run on a picture; on **Q3 it is behind both by two**,
which is the half that fails, and §6.7.3 identifies a specific, repairable sentence as its cause.

**Three things go to Meng alongside that, and none of them is a softening.**

- **The note-excluded cut disagrees.** Remove `promissory-note` and the list **is** last on Q1–Q3:
  30/36 against 32/36 and 35/36 (§6.4.2). The note is the contract whose key has just been
  re-derived from the tree, and it is also the contract where the list beats both pictures by seven
  answers; excluding it is not a neutral robustness check. Both cuts are in §6.4.2 and the four-
  contract figure is the run as designed.
- **§7.3's own counterweight is weakened.** Point 5 is that _"on Q4 and Q5 the list loses badly —
  11/32, against B's 30/32 and C's 24/32"_. In run 2 the list is at **25/32**, level with the DOT's
  26/32. The repair moved the list on exactly the two questions §1.1a says a list cannot answer.
- **The run's largest effect is not about artifacts at all.** Sonnet reads every artifact better
  than haiku by 23 answers of 120 (§6.4.3), which is larger than any A-versus-B-versus-C gap in the
  run. A three-answer spread on Q1–Q3 is being read off an instrument whose reader choice moves it
  seven times as far.

**What the run does not show, in either direction.** It does not show that a list cannot answer Q3:
A's Q3 column is held down by one identified wording defect (§6.7.3) that is not the repair's and is
a wording change to fix. Nor does it show the list is adequate: `tenancy` Q2 is 1/4 with the answer
printed on the page (§6.7.2), which is a finding about readers that no amount of printing fixes.

**The recommendation to the ruling's owner, which is a recommendation and not a decision:** re-word
the breach-names clause so it distinguishes who is in breach from whose names the breach carries;
re-cut the note's `history.txt` conversion table with its key (§6.6); run the test-retest §6.2 still
asks for, so the next comparison has an error bar. Those are cheap. **What this run does not support
is building P2d on it** — the gate's own question came back with the list second of three and
unbeaten on Q1.

## 6.10 What run 2 still cannot decide

Every limit in §5 applies unchanged — no human read anything, no cognitive load was measured, B and
C were read as text, the judge is an LLM, four contracts and two repeats. Run 2 adds two of its own:

1. **Its scoring boundary is uniform but not authoritative** (§6.0, §6.3). The line between
   _incomplete_ and _refusal_ decides ten of the list's fourteen misses; a different line moves the
   Q1–Q3 spread by more than the spread itself.
2. **The reader dominates the artifact** (§6.4.3). Until a run separates model from artifact — the
   same packets read by more models, or by one model many times — no artifact ranking from either
   run is a fact about serialisations.

Run 1's cost-order list, restated with run 2's statuses: (i) repair and rerun — **DONE, and it is
§6**; (ii) equalise the note's calendar conversion across A/B/C — **open**, and now narrowed to
`history.txt` alone, the key itself having been repaired (§6.0); (iii) rerun outside the harness
with a bare API call and a fixed system prompt — **open**, and §6.4.3 makes it the highest-value
item on the list, since the model gap is the largest effect in either run; (iv) a vision run with B
and C rendered — **open**; (v) the reader experiment §7.3 actually asks for — **open**. A sixth is
added by §6.2: **a true test-retest — the same packets, the same settings, twice — which has never
been run and is the cheapest of all of them.** None of these is decided here.
