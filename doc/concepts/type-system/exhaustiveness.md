# Exhaustiveness

Totality as a legal-safety property: every case of a determination handled.

---

## The Legal Problem

A legal determination over a closed category must have an answer for **every** member of the category. A visa decision procedure that handles "granted" and "refused" but not "withdrawn" is not a smaller version of the right procedure — it is a procedure with a hole in it. In software, the hole surfaces as an unhandled case at the worst possible moment: on the first real input that falls into the forgotten category.

Law is unusually exposed to this failure mode, for two reasons:

1. **Legal categories are closed enumerations.** Statutes define exhaustive lists ("'person' means (a)…, (b)…, or (c)…"), so "cover every case" is a well-defined, checkable demand. See [Algebraic Types](algebraic-types.md) on why these lists become sum types.
2. **Legal categories change.** Amendments add variants: a new visa class, a new entity type, a new ground of refusal. Every determination written against the old category is now potentially incomplete — and nothing about its text looks wrong.

**Exhaustiveness checking** (totality over the scrutinised type) turns both problems into compiler diagnostics.

---

## What the Checker Does

When a `CONSIDER` expression scrutinises a value of an algebraic type, L4's type checker compares the branches against the type's full constructor set. A complete match is silent:

```l4
DECLARE `visa status` IS ONE OF
    Granted
    Refused HAS reason IS A STRING
    Withdrawn

GIVEN status IS A `visa status`
GIVETH A STRING
`outcome letter` MEANS
    CONSIDER status
    WHEN Granted THEN "Your visa has been granted."
    WHEN Refused r THEN r
    WHEN Withdrawn THEN "Your application was withdrawn."
```

### Missing branches

If a constructor is not covered, the checker emits a warning listing exactly what still needs to be handled:

```l4
GIVEN status IS A `visa status`
GIVETH A STRING
`incomplete letter` MEANS
    CONSIDER status
    WHEN Granted THEN "Your visa has been granted."
    WHEN Refused r THEN r
```

```
Warning: The following branches still need to be considered:

  WHEN Withdrawn THEN
```

### Redundant branches

The dual check also fires: a branch that can never be reached (for example, a second `WHEN Granted` after the first) is flagged:

```
Warning: The following CONSIDER branch is redundant:

  WHEN Granted THEN "duplicate branch - unreachable"
```

Redundancy matters legally too — an unreachable branch is usually a sign that the author _believed_ some case was being handled there, when in fact an earlier branch is absorbing it.

### The amendment scenario

The payoff comes when a category grows. Add a fourth variant to `` `visa status` `` and every checked `CONSIDER` site that scrutinises it — every letter template, every fee rule, every appeal-rights determination — immediately warns that the new case "still needs to be considered". The legislature's amendment becomes a checklist of code sites to revisit. This is the property flattened boolean encodings cannot offer: a bundle of independent `IF` tests has no notion of "covering" a category, so nothing notices when the category changes.

---

## Caveats and Escape Hatches

### Primitive types are not checked

The analysis works by enumerating constructors, so it applies only to algebraic types with a finite, known constructor set. Scrutinees of the primitive types `NUMBER`, `STRING`, and `DATE` are skipped — their values (numeric and string literals, dates) cannot be enumerated, so neither missing-case nor redundancy warnings are produced for them:

```l4
GIVEN n IS A NUMBER
GIVETH A STRING
`describe count` MEANS
    CONSIDER n
    WHEN 0 THEN "none"
    OTHERWISE "some"    -- no warning either way; supply OTHERWISE yourself
```

`BOOLEAN`, with exactly `TRUE` and `FALSE`, _is_ analysed — a `CONSIDER` covering only `WHEN TRUE` warns about the missing `WHEN FALSE` branch. Other builtin container types (`MAYBE`, `EITHER`, `LIST`) are not yet analysed.

The practical consequence: when a statutory category is modelled as a `STRING` (status codes, category letters), the safety property is silently lost. Declare an enumeration instead — it is precisely what makes the completeness of your determinations checkable.

The check applies wherever the `CONSIDER` appears — in a rule's main body and equally inside `WHERE`- or `LET`-bound local definitions.

### OTHERWISE trades checking for coverage

`OTHERWISE` is a catch-all branch. It makes any match complete, and thereby switches the missing-case warning off — including for variants added in the future, which it will absorb without comment. Use it when the remaining cases genuinely share one treatment; avoid it when each case of a determination deserves an explicit decision.

### What happens if a hole is hit at runtime

Exhaustiveness warnings are compile-time advice, not a runtime guard. If evaluation actually reaches a `CONSIDER` with no matching branch, that evaluation fails with an error naming the offending value:

```
The value
  Withdrawn
reached a CONSIDER that has no branch for it.
Add a WHEN branch for this case, or a catch-all OTHERWISE branch.
The typechecker's exhaustiveness warning lists all missing branches.
```

`l4 run` exits non-zero when any directive crashes this way. The warning exists so you find the hole before an applicant does.

---

## Why Warnings, Not Errors

L4 reports incomplete matches as **warnings**: the program still compiles and runs. This is a deliberate choice about how legal encoding actually proceeds.

- **Encoding is incremental.** A statute is formalised provision by provision. While the work is in progress, determinations are legitimately partial — the encoder is often deliberately deferring the hard case (the one that needs a policy decision) while validating the easy ones with `#EVAL`. A hard error would force placeholder branches everywhere, which are worse than an honest warning: a placeholder _looks_ handled.
- **Existing code keeps working.** Tightening the checker over time (covering more scrutinee types, sharper redundancy analysis) must not break rulebases that previously compiled. Warnings allow the analysis to improve without invalidating legacy encodings.

The intended discipline: treat the warnings as a completeness report. A finished, production-ready determination should compile with none — at that point, every case of every closed category it examines has an explicit, reviewed answer.

---

## Summary

| Property                                          | Behaviour                                                                |
| ------------------------------------------------- | ------------------------------------------------------------------------ |
| Missing case in `CONSIDER`                        | Compile-time warning listing the uncovered branches                      |
| Unreachable branch                                | Compile-time warning that the branch is redundant                        |
| `NUMBER` / `STRING` / `DATE` scrutinee            | Not analysed — values can't be enumerated                                |
| `BOOLEAN` and declared enumerations (`IS ONE OF`) | Fully analysed                                                           |
| `MAYBE` / `EITHER` / `LIST` scrutinee             | Not yet analysed                                                         |
| `CONSIDER` inside `WHERE` / `LET`                 | Analysed like any other                                                  |
| `OTHERWISE`                                       | Completes the match, disables missing-case warnings                      |
| Hole reached at runtime                           | Evaluation fails, naming the unmatched value; `l4 run` exits non-zero    |
| Severity                                          | Warning, not error — the file still evaluates and its `#EVAL`s still run |

---

## Further Reading

- [Algebraic Types](algebraic-types.md) — Why legal categories become sum types in the first place
- [CONSIDER Reference](../../reference/control-flow/CONSIDER.md) — Full pattern-matching syntax
- [Constitutive vs Regulative Rules](../legal-modeling/constitutive-vs-regulative.md) — Where determinations sit in the larger architecture
