# The §7.3 gate — an LLM-reader PROXY, RUN 2026-09-16

**Status: RUN 2026-09-16, as a proxy. It is not the gate, and this file records no verdict on the
gate.** [`LTS-VISUALISER.md`](../../specs/todo/lexipedia-superset/LTS-VISUALISER.md) §7.3 gates the
two-plane picture on a **reader** experiment — can readers answer _what do I owe, what discharges it,
what breaches it_ from the plain list (`l4 lts`), and does a picture add _where am I_ and _what
happens after_ (§1.1a)? No human has been shown anything. What was run is the proxy the
[`README.md`](./README.md) in this directory prepares: fresh LLM readers, each shown **one** artifact
for one contract and nothing else, asked the five questions, scored against `truth.json`. The
scored rows are in [`results.json`](./results.json); every number below is computed from that file
and nothing else. The primary evidence behind those rows — each reader's prompt and verbatim
answers, each judge's prompt and verbatim output, and the model ids — is under
[`transcripts/`](./transcripts/readings.json), recovered from the run's own transcripts by
[`extract-transcripts.mjs`](./extract-transcripts.mjs) on 2026-09-16 (the first commit of this
file carried only the scored rows, which a reviewer rightly called unauditable).

## 1. Method

| item         | value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| contracts    | the four in the README: `contracts` (`aContract`, third link of a HENCE chain), `every-run-example` (`the tenancy`, an `EVERY` barrier with 2 of 3 signed), `tenancy` (`receipts`, an `EACH` fork at its outset), `promissory-note` (`Payment Obligations`, one late payment sitting in the first `LEST` arm)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| artifacts    | **A** the `l4 lts` list at default flags · **B** the `l4 state-graph` DOT source, as text · **C** the P1 BPMN 2.0 XML, as text. B and C readers also got `history.txt` (the position in plain words); A readers got only the list, which states its own position. Full reader-facing text: `manifest.json` — **that file, not the `B.dot` next to it, is what a B reader saw.** The two have been different since 2026-09-23; the `binary` row says why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| questions    | the five in `manifest.json`, identical for every contract: Q1 _what is owed right now, and by whom_ · Q2 _which event(s) would discharge it_ · Q3 _which event(s) or deadline(s) would put someone in breach_ · Q4 _where in the contract are we — which rule, branch or state is live_ · Q5 _what happens after the next discharging event_. Q1–Q3 are §1.1a's three clauses; Q4–Q5 are the two things §1.1a says a list cannot do                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| readers      | two Claude models, `haiku` = `claude-haiku-4-5-20251001` and `sonnet` = `claude-sonnet-5` (`transcripts/readings.json`, `model_id`). Each reader was a fresh, single-turn Claude Code subagent (harness 2.1.272) with **no tools** but the answer form, and no other context: one artifact (plus `history.txt` for B and C), then the five questions, with the instruction _"if the artifact does not let you answer, say 'cannot tell from this' — do not guess"_ (`transcripts/prompts/<contract>.<artifact>.txt`, byte-identical across the four readings of a cell). Each (contract, artifact, model) cell was run **twice** (`repeat` 0 and 1), so 4 × 3 × 2 × 2 = **48 readings, 240 scored answers**. `extract-transcripts.mjs` checks that no reader used any other tool                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| judge        | one `claude-opus-5` judge per contract (`transcripts/judge.json`), shown `truth.json` and all twelve readings of that contract (`transcripts/judge/<contract>.prompt.txt`), scoring each answer **0 or 1** with a one-line rationale per reading. **One scoring rule is in the prompt, verbatim:** _"Score each answer 1 if it is correct against the truth (same obligations/parties/events/deadline, allowing paraphrase; 'cannot tell' is 0 unless the truth says the artifact cannot say it, in which case 'cannot tell' is 1 and a confident wrong answer is 0), else 0."_ **A second rule is not in the prompt and is inferred from the rationales:** an answer that is incomplete but asserts nothing wrong scores 1 (`every-run-example/B/haiku/0`: _"omits the day-14 deadline (incomplete, not wrong)"_). Neither was applied uniformly: `promissory-note/A/haiku/0` Q4 _"names only the section, not the live LEST/penalty arm"_ scored 0 (incomplete, nothing wrong); `promissory-note/A/haiku/1` Q3 _"hedged 'cannot tell' but substantively reports the truth"_ scored 1, while `tenancy/A/sonnet/1` Q2 _"states the right inference but then retracts to 'cannot tell' as its verdict"_ scored 0. So a count that turns on either rule is ±2, not exact |
| recorded     | under `transcripts/`: the twelve reader prompts verbatim; the 48 readings' verbatim answers (`answers`, the accepted answer form; `answer_text`, the prose the reader wrote before it, empty for the 22 readers that filled the form directly) with model id, timestamps and token usage; the four judge prompts and outputs verbatim. `extract-transcripts.mjs` asserts `results.json` == judge output and judge input == reader output, both exact; one reader (`promissory-note/C/sonnet/0`) had its first answer form rejected by the schema (missing `a2`, `a4`) and its second accepted, and both attempts are kept (`rejected_attempts`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| not recorded | the harness system prompt a Claude Code subagent runs under (not in the transcript, so not reproducible here); the readers' and judges' thinking (present in the transcripts as signatures only, `thinking_redacted_in_transcript`); effort settings (the transcript fields are null, i.e. harness default); temperature. A rerun outside the harness, with a bare API call, would remove the first                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| binary       | the artifacts the readers were shown were cut with the `lts/p2-stack` build at `0139c6c5`, as the README records; the truth answers were read off `lts.json` (Q1–Q3) and `probes.out` / `B.dot` (Q4–Q5). **The four `B.dot` files on disk are no longer that text.** They were re-cut on 2026-09-21 and again on 2026-09-23, from `lts/draw-what-it-means`, where five fixes changed what `l4 state-graph` writes on a node and on an arrow. The reading is frozen and the artifact is not: `manifest.json` and `transcripts/` still carry the text the readers were given, and every number in this file is scored against that text and not against the file now in the directory. Regenerating them to agree would put 48 committed readings against a packet nobody read                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |

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

### 3.1 The list's Q2 misses are all in the "What could not be tried" section

Q2 (_what discharges it_) is where the list loses to both pictures pooled: 8/16 against 15/16 and
14/16. Every one of the eight misses is on a contract where the list **refused the what-if**:

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
`history.txt` tells B and C readers in plain words. This is the one place where the A readers were
given strictly less information than B and C (the README says so), and the Q4 column on that
contract is confounded by it.

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
then, still, (v) the reader experiment §7.3 actually asks for. None of these is decided here.
