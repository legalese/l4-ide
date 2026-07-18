# Sets

Set-theoretic collections: `SET OF a` with union, intersection, difference, membership, and subset — plus operator overloads that make L4's `AND`, `OR`, `PLUS`, and `MINUS` do the right thing when their operands are sets. Part of the prelude; available after `IMPORT prelude`.

Sets exist in L4 because legal drafting needs them: "residents of New York **and** New Jersey may apply" builds a *union of people*, while "cruel **and** unusual" conjoins two *conditions*. Same word, two operations — and the type system tells them apart. See the [tutorial](../../tutorials/set-operators/sets-and-the-two-ands.md) for the full story.

### Location

[jl4-core/libraries/prelude.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/prelude.l4) — the `Sets` section.

### The type

```l4
DECLARE SET OF a
  HAS elements IS A LIST OF a
```

A `SET OF a` is a wrapper around a list in which **order and duplicates are irrelevant**: membership, subset, `set equals`, and `setSize` all ignore them. Construct sets with `setFromList` (which deduplicates) rather than the raw constructor.

### Functions

| Function                | Signature                              | Description                                       |
| ----------------------- | -------------------------------------- | ------------------------------------------------- |
| `emptySet`              | `SET OF a`                             | The set with no elements                          |
| `setFromList`           | `LIST OF a → SET OF a`                 | Build a set from a list, discarding duplicates    |
| `setToList`             | `SET OF a → LIST OF a`                 | The distinct elements, as a list                  |
| `setSize`               | `SET OF a → NUMBER`                    | The number of distinct elements                   |
| `` x `is in` s ``       | `a → SET OF a → BOOLEAN`               | Membership                                        |
| `` p `is subset of` q`` | `SET OF a → SET OF a → BOOLEAN`        | Every element of `p` is in `q`                    |
| `` p `set equals` q ``  | `SET OF a → SET OF a → BOOLEAN`        | Extensional equality (mutual subset)              |
| `p UNION q`             | `SET OF a → SET OF a → SET OF a`       | `p ∪ q` — "the members of p and of q"             |
| `p INTERSECT q`         | `SET OF a → SET OF a → SET OF a`       | `p ∩ q` — "those in both"                         |
| `` p `LESS` q ``        | `SET OF a → SET OF a → SET OF a`       | `p \ q` — "all employees LESS those on probation" |
| `p WITHOUT q`           | `SET OF a → SET OF a → SET OF a`       | Alias for `` `LESS` ``, no backticks needed       |

`UNION`, `INTERSECT`, and `WITHOUT` are ordinary identifiers and work **bare** at call sites. `LESS` must be written `` `LESS` `` (backticked) because bare `LESS` is the lexer keyword that starts `LESS THAN`.

These word operators have **no precedence**: parenthesize compounds, e.g. `A UNION (B INTERSECT C)`.

### Operator overloads

| Operator     | On sets, means | Notes                                                                 |
| ------------ | -------------- | --------------------------------------------------------------------- |
| `p PLUS q`   | `UNION`        | Bare **and precedence-correct**: `a PLUS b MINUS c` needs no parens   |
| `p MINUS q`  | `` `LESS` ``   | Ditto (Oracle SQL's `MINUS` is the precedent)                         |
| `p AND q`    | `UNION`        | Term-level "and" — see the two-ANDs discussion in the tutorial        |
| `p OR q`     | `UNION`        | Union too: "NY and NJ residents" = "NY or NJ residents"               |
| `p EQUALS q` | *error*        | Deliberately ambiguous — write `` `set equals` `` (see below)         |

**Caution — sets are not arithmetic.** Union is idempotent (`A PLUS A` is `A`) and has no inverse: `(A PLUS B) MINUS B` is **not** `A` in general.

### Equality: use `set equals`, not `EQUALS`

Bare `EQUALS` on two sets is a compile-time ambiguity error, **on purpose**. Builtin structural equality would be order-sensitive (`{1,2}` ≠ `{2,1}` as lists), which is silently wrong for sets; rather than pick wrongly, L4 makes you choose explicitly:

```l4
(setFromList (LIST 2, 1, 1)) `set equals` (setFromList (LIST 1, 2))   -- TRUE
```

### Known limit: the quotient is one level deep

Order/duplicate-insensitivity applies to a set's **elements**, compared with builtin structural equality. It does not compose:

- `SET OF SET OF a` compares inner sets by representation — `{{1,2}}` and `{{2,1}}` are *different* elements;
- a set wrapped in any container (a record field, `PAIR`, `LIST`, `MAYBE`) compares structurally under bare `EQUALS`, with no diagnostic. Compare set-valued fields with `` `set equals` `` field-wise instead of comparing whole records.

See [set-operators-nested.l4](https://github.com/legalese/l4-ide/blob/main/jl4/examples/ok/set-operators-nested.l4), which pins this behavior.

### Variadic construction (separate PR)

With the route-α typechecker elaboration ([#123](https://github.com/legalese/l4-ide/pull/123)), a set can be written directly as `SET OF "refuge", "residence"` or `SET OF NY, NJ` — the arguments collect into a list automatically. Until that lands, write `setFromList (LIST …)`.

### Example: Set Operations

[sets-example.l4](sets-example.l4)

**See the [Sets tutorial](../../tutorials/set-operators/sets-and-the-two-ands.md) for the legal-drafting motivation, and [SET-OPERATORS-SPEC](https://github.com/legalese/l4-ide/blob/docs/set-operators-spec/specs/todo/SET-OPERATORS-SPEC.md) for the design record, including the case law.**
