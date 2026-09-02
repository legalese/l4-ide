# Default Reasoning and Exceptions

How L4 encodes the law's most common shape: a general rule, followed by exceptions.

---

## Law Is Defeasible

Legal rules are rarely absolute. The characteristic pattern of legal drafting is a **general rule subject to exceptions**:

> A person who satisfies the residence requirement is eligible for the benefit, **unless** the person has been disqualified under section 12.

The rule holds _by default_; the exception _defeats_ it in particular cases. Legal theorists call this **defeasibility**, and it runs all the way through statutes and contracts: "unless", "except where", "subject to section 9", "this section does not apply to…".

Crucially, the legal text keeps the rule and its exceptions **separate**. The general rule states the normal case; each exception is its own clause, often its own subsection, added and amended independently. An encoding that wants to stay reviewable against the text should preserve that separation.

---

## UNLESS: The Exception Operator

L4 provides `UNLESS` for exactly this structure. Semantically it is just conjunction with a negation — `A UNLESS B` means `A AND NOT B` — but its **precedence** is what makes it an exception operator: it binds looser than both `AND` and `OR`, so it carves its exception out of the _entire_ rule that precedes it.

```l4
ASSUME `is a citizen` IS A BOOLEAN
ASSUME `has resided for 5 years` IS A BOOLEAN
ASSUME `has been disqualified` IS A BOOLEAN

DECIDE `is eligible` IF
      `is a citizen`
  AND `has resided for 5 years`
  UNLESS `has been disqualified`
```

This evaluates as `(citizen AND resided) AND NOT disqualified` — the whole eligibility test, subject to the exception — without any parentheses. The code has the same shape as the sentence: rule first, exception last.

See [UNLESS](../../reference/operators/UNLESS.md) for the precedence details and truth table.

---

## Why Not Flatten Into Boolean Logic?

`A UNLESS B` is logically equivalent to `A AND NOT B`, so why does the operator matter? Because the two encodings differ in everything _except_ their truth table.

Consider a rule with an exception that itself has an exception (a very common statutory shape):

> The holder of a licence may drive.
> A licence under suspension does not authorise driving —
> unless the suspension has been stayed by court order.

Flattened into one boolean expression:

```l4
-- ❌ Truth-functionally correct, structurally opaque
DECIDE `may drive (flattened)` IF
    `holds licence`
    AND (NOT `licence suspended` OR `suspension stayed by court order`)
```

This is correct, but the drafting structure is gone. Nothing in the code corresponds to "the suspension provision"; the exception-to-the-exception has been absorbed into a `NOT … OR …` that has to be mentally re-derived to check against the text. When the legislature adds a second stay condition, there is no obvious place to put it.

The isomorphic encoding names each layer:

```l4
-- ✅ One named rule per provision
DECIDE `suspension is operative` IF
    `licence suspended`
    UNLESS `suspension stayed by court order`

DECIDE `may drive` IF
    `holds licence`
    UNLESS `suspension is operative`
```

Now the code has the same architecture as the statute:

- `` `may drive` `` is the general rule, with the suspension provision as its exception
- `` `suspension is operative` `` is the suspension provision, with the stay as _its_ exception

Each provision of the source text is one named rule; each "unless" in the text is one `UNLESS` in the code.

---

## Layering Exceptions

The named-rule pattern scales to any depth of exception nesting. Each layer follows the same recipe:

1. State the rule for the normal case.
2. Append `UNLESS` and name the defeater.
3. If the defeater itself has exceptions, define it as its own rule with its own `UNLESS`.

`UNLESS` can also be chained directly. Chained `UNLESS` nests to the right, so each further `UNLESS` is an exception to the exception before it:

```l4
-- a UNLESS b UNLESS c  ≡  a AND NOT (b AND NOT c)
`may drive` MEANS
    `holds licence` UNLESS `licence suspended` UNLESS `suspension stayed by court order`
```

This one-liner is equivalent to the two named rules above. It is fine for a quick exception-to-an-exception, but beyond one level of nesting, prefer named intermediate rules: the names document which provision each layer encodes, the intermediate conclusions (`` `suspension is operative` ``) become independently testable and reusable, and reviewers can trace each rule to its clause.

---

## Why Explicit Exception Structure Wins

### Amendments stay local

Laws change by amendment, and amendments are usually to exceptions: a new carve-out, a new condition on an existing carve-out. With explicit structure, the code change is as local as the legal change — one new `UNLESS` clause, or one edit inside the named defeater rule. With flattened logic, every amendment means re-deriving and re-simplifying a compound expression, and the diff no longer resembles the amending act.

### Review is clause-by-clause

A lawyer checking the encoding reads the statute one provision at a time. If the code is one named rule per provision, review is a side-by-side comparison. If the code is a normalised boolean formula, the reviewer must verify a logical transformation as well as a transcription — a much harder task, and the one most likely to hide errors.

### Burden structure is visible

"Rule unless exception" also tracks who typically has to establish what: the claimant proves the elements of the general rule; the party resisting invokes the exception. An encoding that keeps exceptions syntactically separate preserves this practical reading; a flattened formula erases it.

### The honest caveat

`UNLESS` is classical logic, not a non-monotonic defeasible logic: L4 does not infer priorities between rules or retract conclusions when new rules are added. What `UNLESS` gives you is the _structure_ of default-plus-exception, stated explicitly and checked by the type system — which is precisely what you need for an encoding that stays isomorphic to its source text.

---

## Summary

| Legal drafting pattern           | L4 encoding                                                  |
| -------------------------------- | ------------------------------------------------------------ |
| General rule                     | `DECIDE rule IF conditions`                                  |
| "…unless X"                      | `… UNLESS X` appended to the rule                            |
| Exception with its own exception | Name the exception as its own `DECIDE` with its own `UNLESS` |
| "Subject to section N"           | `UNLESS` naming a rule that encodes section N                |
| New carve-out enacted            | Add one `UNLESS` clause or edit one named rule               |

---

## Further Reading

- [UNLESS Reference](../../reference/operators/UNLESS.md) — Semantics, precedence, truth table
- [Constitutive vs Regulative Rules](constitutive-vs-regulative.md) — Where exception structure lives in the larger architecture
- [Design Principles](../language-design/principles.md) — Legal isomorphism, the principle this pattern serves
- [Common Patterns](../../reference/patterns/common-patterns.md) — More encoding patterns
