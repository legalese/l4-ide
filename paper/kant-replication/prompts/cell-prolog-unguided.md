# Cell: prolog-unguided

Derived from Kant et al. Appendix A.3.2, which is two prompts — one for the policy encoding,
one for the claim encodings. Both are reproduced below in substance.

## Step 1 — encode the policy

Given the insurance contract, translate the document into valid Prolog rules so that a Prolog
query can be run on the code regarding whether or not some claim is covered under the policy,
and receive the correct answer to the question.

- **Fully define all predicates and DO NOT define any facts**, only rules that can be used to
  answer queries on this insurance contract.
- Assume that all dates/times in any query to this code (apart from the claimant's age) will be
  given **relative to the effective date** of the policy — there will never be a need to
  calculate the time elapsed between two dates. Take dates relative to the effective date into
  account when writing this encoding.
- Assume that the agreement has been signed and the premium has been paid (on time). There is
  no need to encode rules or facts for these conditions.

Ensure that:

1. The legal text is appropriately translated into correct Prolog rules.
2. The output does not redefine, misuse, or conflict with any built-in Prolog predicates.
3. If dynamic predicates are necessary, they are declared and managed correctly.
4. All predicates used, including those referenced in the query, are fully defined and
   error-free, to prevent issues like "procedure does not exist".
5. Logical relationships, conditions, and dependencies in the text are faithfully represented
   in the Prolog rules to ensure accurate query results.

## Step 2 — encode each of the nine questions as a query

For each question, encode it into a Prolog query such that it can be run on your encoding of
the contract, returning the correct answer to the question.

Ensure that:

1. The output does not redefine, misuse, or conflict with any built-in Prolog predicates.
2. If dynamic predicates are necessary, they are declared and managed correctly.
3. All predicates used are fully defined and error-free.
4. Logical relationships, conditions and dependencies are faithfully represented.
5. **No absolute dates/times (apart from the claimant's age) are encoded in your query.** Only
   dates/times relative to the effective date of the policy.
6. Set any facts/rules/parameters such that **ALL conditions** for the policy to apply which
   are **unrelated** to the query are satisfied.
7. Set any facts/rules/parameters such that **NO exclusions** which would prevent the policy
   from applying, and which are **unrelated** to the query, are satisfied.

## Inputs

- Contract: `fixtures/chubb-policy.txt`
- Questions: `fixtures/queries-blind.md`

## Output contract

Two files in your trial directory.

**`policy.pl`** — your encoding of the contract. Rules only, no claim facts.

**`queries.pl`** — nine predicates `q1/0` through `q9/0`, one per question, each succeeding
exactly when the answer to that question is "yes" and failing when it is "no". This is where
the per-claim facts belong. For example:

```prolog
q1 :- covered(claim_1).
```

Both files are consulted together, `policy.pl` first. `queries.pl` may define facts.

**You may check that your files load** (`swipl -q -g halt policy.pl queries.pl` should be
silent). **You may not run q1..q9 or otherwise test your encoding against the questions.**
Record in `NOTES.md` whether you ran a load check and what it said.
