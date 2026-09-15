# Cell: l4-guided

A mechanical translation of `cell-prolog-guided.md`. Only the language and the output contract
differ.

Below is all of the text that pertains to an insurance policy. The text defines all conditions
and exclusions that determine whether a claimant's claim is covered.

- Encode a function **`covered`**, from a `Claim` to a `BOOLEAN`, true exactly when the claim
  is covered.
- You are given a **`Claim` record type** whose fields are the facts that will be supplied in
  any query. **Use ALL OF — and ONLY — these fields.**
- You are given a set of **supporting, pre-defined helpers**. **Use these** rather than writing
  your own equivalents, and do not redefine them.
- `covered` must incorporate all relevant criteria from the policy.

## Inputs

- Contract: `fixtures/chubb-policy.txt`
- Fact vocabulary and supporting helpers: `bench/schema-l4.md`
- Questions: `fixtures/queries-blind.md`
- L4 language reference: the `writing-l4-rules` skill, and `doc/reference/cheat-sheet.md`

## Output contract

Two files in your trial directory.

**`policy.l4`** — the `DECLARE`s and helpers from the schema, verbatim, so the file is
self-contained, plus your `covered` function and whatever helpers it needs. **No claim data.**

**`apply.l4`** — nine `#EVAL` directives, one per question, each evaluating to `TRUE` exactly
when the answer to that question is "yes". Each builds its own `Claim`, setting every field
**unrelated** to the question so that all conditions for coverage are satisfied and no
exclusions are triggered. Each `#EVAL` line **must carry the token `q1` … `q9`**:

```l4
IMPORT policy
q1 MEANS Claim WITH ...
#EVAL covered q1
```

Selection is by that label, not by position, so extra `#EVAL`s are permitted **provided** they
do not carry a bare `q<digit>` token — name any sensitivity probes `Q4b`, `S4` or similar.

**You may check that your files typecheck** (`l4 check apply.l4`). **You may not run the nine
evaluations or otherwise test your encoding against the questions.** Record in `NOTES.md`
whether you ran a check and what it said.
