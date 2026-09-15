# Cell: vanilla — answer the queries directly, no encoding

Derived from Kant et al. Appendix A.3.1.

You are given the full text of an insurance contract and nine questions about whether a claim
in a given scenario is covered under its terms.

- Assume that the policy agreement has been signed, and the premium has been paid on time.
- Assume that all other conditions are satisfied, and no exclusions apply unless explicitly
  referenced in the query.

Your task, for each of the nine questions:

1. Evaluate whether the claim described is covered under the insurance contract.
2. Answer with **only** one of: `Yes`, `No`, `I do not know`.
3. Do not provide any explanations or reasoning.

## Inputs

- Contract: `fixtures/chubb-policy.txt`
- Questions: `fixtures/queries-blind.md`

## Output contract

Write `answers.json` in your trial directory:

```json
{
  "1": "<Yes | No | I do not know>",
  "2": "<Yes | No | I do not know>",
  "3": "...",
  "4": "...",
  "5": "...",
  "6": "...",
  "7": "...",
  "8": "...",
  "9": "..."
}
```

Exactly nine keys, `"1"` through `"9"`. Each value is exactly `Yes`, `No`, or `I do not know`.
Nothing else in the file.
