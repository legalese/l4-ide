# Cell: l4-unguided

A mechanical translation of `cell-prolog-unguided.md`. Only the language and the output
contract differ. Two substitutions were required because the source instruction has no L4
analogue, and both are noted inline below.

## Step 1 — encode the policy

Given the insurance contract, translate the document into valid L4 so that it can be evaluated
regarding whether or not some claim is covered under the policy, and yield the correct answer.

- **Fully define all functions and DO NOT define any claim data**, only rules that can be used
  to answer queries on this insurance contract.
- Assume that all dates/times in any query to this code (apart from the claimant's age) will be
  given **relative to the effective date** of the policy — there will never be a need to
  calculate the time elapsed between two dates. Take dates relative to the effective date into
  account when writing this encoding.
- Assume that the agreement has been signed and the premium has been paid (on time). There is
  no need to encode rules for these conditions.

Ensure that:

1. The legal text is appropriately translated into correct L4.
2. The output does not shadow or conflict with names from the L4 prelude.
   _(substitution: the source says "built-in Prolog predicates")_
3. Any declared types are declared once and used consistently.
   _(substitution: the source's clause about dynamic predicates, which L4 has no analogue for)_
4. All functions used, including those referenced by the queries, are fully defined and
   error-free, so that nothing is left unresolved.
5. Logical relationships, conditions, and dependencies in the text are faithfully represented
   in the L4 rules to ensure accurate results.

## Step 2 — encode each of the nine questions

For each question, encode it so it can be evaluated against your encoding of the contract,
returning the correct answer.

Ensure that:

1. The output does not shadow or conflict with prelude names.
2. Any declared types are declared once and used consistently.
3. All functions used are fully defined and error-free.
4. Logical relationships, conditions and dependencies are faithfully represented.
5. **No absolute dates/times (apart from the claimant's age) are encoded in your query.** Only
   dates/times relative to the effective date of the policy.
6. Set any values/parameters such that **ALL conditions** for the policy to apply which are
   **unrelated** to the query are satisfied.
7. Set any values/parameters such that **NO exclusions** which would prevent the policy from
   applying, and which are **unrelated** to the query, are satisfied.

## Inputs

- Contract: `fixtures/chubb-policy.txt`
- Questions: `fixtures/queries-blind.md`
- L4 language reference: the `writing-l4-rules` skill, and `doc/reference/cheat-sheet.md`

## Output contract

Two files in your trial directory.

**`policy.l4`** — your encoding of the contract. Rules only, no claim data.

**`apply.l4`** — nine `#EVAL` directives, one per question, each evaluating to `TRUE` exactly
when the answer to that question is "yes". This is where the per-claim data belongs. Each
`#EVAL` line **must carry the token `q1` … `q9`** so the scorer can identify it:

```l4
IMPORT policy
q1 MEANS ...
#EVAL `covered` q1
```

Selection is by that label, not by position, so extra `#EVAL`s are permitted **provided** they
do not carry a bare `q<digit>` token — name any sensitivity probes `Q4b`, `S4` or similar.

**You may check that your files typecheck** (`l4 check apply.l4`). **You may not run the nine
evaluations or otherwise test your encoding against the questions.** Record in `NOTES.md`
whether you ran a check and what it said.
