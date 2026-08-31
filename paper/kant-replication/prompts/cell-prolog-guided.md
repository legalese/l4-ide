# Cell: prolog-guided

Follows the pattern of Kant et al. Appendix A.3.3 — the model is given the policy text,
documentation defining a valid claim (the fact vocabulary), and documentation of the
supporting predicates it may call. That documentation is the expert's guidance.

Below is all of the text that pertains to an insurance policy. The text defines all conditions
and exclusions that determine whether a claimant's claim is covered.

- Encode a Prolog rule **`covered(C)`**, true exactly when the claim `C` is covered.
- You are given a set of **claim facts** that will be defined in any query to `covered(C)`.
  These are of the form `claim_Fact(C, Value)`. Under each, the valid inputs for `Value` (or
  the type of valid input) are listed. **Use ALL OF — and ONLY — these claim facts.**
- You are given a set of **supporting, pre-defined predicates**. **Use these** rather than
  writing your own equivalents, and do not redefine them.
- `covered(C)` must incorporate all relevant criteria from the policy.

## Inputs

- Contract: `fixtures/chubb-policy.txt`
- Fact vocabulary and supporting predicates: `bench/schema-prolog.md`
- Questions: `fixtures/queries-blind.md`

## Output contract

Two files in your trial directory.

**`policy.pl`** — your `covered(C)` rule and whatever helper rules it needs. Include the two
supporting predicates from the schema verbatim so the file is self-contained. **No claim
facts.**

**`queries.pl`** — nine predicates `q1/0` through `q9/0`, each succeeding exactly when the
answer to that question is "yes". Each defines the claim facts for its own claim using the
`claim_*` vocabulary, setting every fact **unrelated** to the question so that all conditions
for coverage are satisfied and no exclusions are triggered. For example:

```prolog
q1 :- covered(c1).
claim_agreement_signed(c1, true).
claim_hospitalization_month(c1, 3).
% ... all 18 facts, for each of the nine claims
```

**You may check that your files load** (`swipl -q -g halt policy.pl queries.pl` should be
silent). **You may not run q1..q9 or otherwise test your encoding against the questions.**
Record in `NOTES.md` whether you ran a load check and what it said.
