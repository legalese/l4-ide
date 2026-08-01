# Sets

Set-theoretic collections: `SET OF a` with union, intersection, difference, membership, and subset — plus operator overloads that make L4's `PLUS` and `MINUS` do the right thing when their operands are sets. Part of the prelude; available after `IMPORT prelude`.

Sets exist in L4 because legal drafting needs them: "residents of New York **and** New Jersey may apply" builds a _union of people_, while "cruel **and** unusual" conjoins two _conditions_. Same word, two operations — and the type system tells them apart: on sets the union operation is spelled `UNION`, while `AND` stays sentence-level conjunction. See the [tutorial](../../tutorials/set-operators/sets-and-the-two-ands.md) for the full story (its [Sets in one minute](../../tutorials/set-operators/sets-and-the-two-ands.md#sets-in-one-minute) section is a from-scratch primer if union/intersection/subset are unfamiliar).

### Location

[jl4-core/libraries/prelude.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/prelude.l4) — the `Sets` section.

### The type

```l4
DECLARE SET OF a
  HAS elements IS A LIST OF a
```

A `SET OF a` is a wrapper around a list in which **order and duplicates are irrelevant**: membership, subset, `set equals`, and `setSize` all ignore them. Construct sets with `setFromList` (which deduplicates) rather than the raw constructor.

### Functions

| Function                | Signature                        | Description                                       |
| ----------------------- | -------------------------------- | ------------------------------------------------- |
| `emptySet`              | `SET OF a`                       | The set with no elements                          |
| `setFromList`           | `LIST OF a → SET OF a`           | Build a set from a list, discarding duplicates    |
| `setToList`             | `SET OF a → LIST OF a`           | The distinct elements, as a list                  |
| `setSize`               | `SET OF a → NUMBER`              | The number of distinct elements                   |
| ``x `is in` s``         | `a → SET OF a → BOOLEAN`         | Membership                                        |
| `` p `is subset of` q`` | `SET OF a → SET OF a → BOOLEAN`  | Every element of `p` is in `q`                    |
| ``p `set equals` q``    | `SET OF a → SET OF a → BOOLEAN`  | Extensional equality (mutual subset)              |
| `p UNION q`             | `SET OF a → SET OF a → SET OF a` | `p ∪ q` — "the members of p and of q"             |
| `p INTERSECT q`         | `SET OF a → SET OF a → SET OF a` | `p ∩ q` — "those in both"                         |
| ``p `LESS` q``          | `SET OF a → SET OF a → SET OF a` | `p \ q` — "all employees LESS those on probation" |
| `p WITHOUT q`           | `SET OF a → SET OF a → SET OF a` | Alias for `` `LESS` ``, no backticks needed       |

`UNION`, `INTERSECT`, and `WITHOUT` are ordinary identifiers and work **bare** at call sites. `LESS` must be written `` `LESS` `` (backticked) because bare `LESS` is the lexer keyword that starts `LESS THAN`.

These word operators have **no precedence**: parenthesize compounds, e.g. `A UNION (B INTERSECT C)`.

### Operator overloads

| Operator     | On sets, means | Notes                                                               |
| ------------ | -------------- | ------------------------------------------------------------------- |
| `p PLUS q`   | `UNION`        | Bare **and precedence-correct**: `a PLUS b MINUS c` needs no parens |
| `p MINUS q`  | `` `LESS` ``   | Ditto (Oracle SQL's `MINUS` is the precedent)                       |
| `p AND q`    | _error_        | The set overload was **removed 2026-07-28** — write `UNION`         |
| `p OR q`     | _error_        | Ditto — write `UNION`                                               |
| `p EQUALS q` | _error_        | Deliberately ambiguous — write `` `set equals` `` (see below)       |

**Caution — sets are not arithmetic.** Union is idempotent (`A PLUS A` is `A`) and has no inverse: `(A PLUS B) MINUS B` is **not** `A` in general.

**Why `AND`/`OR` on sets no longer resolve to union:** the overloads existed (the two-ANDs design of the spec's §D4) but a second candidate for `__AND__`/`__OR__` made typechecking **exponential — base 3 in the depth of `AND`/`OR` chains**: a flat 15-operand boolean conjunction took 71.75s, 16+ operands never finished, and a real 27-operand statutory disjunction extrapolated to about a year ([smucclaw/l4-ide#929](https://github.com/smucclaw/l4-ide/issues/929)). Term-level union is now written `UNION` explicitly. A typechecker fix (an overload pre-filter, [legalese/l4-ide#169](https://github.com/legalese/l4-ide/pull/169)) has since removed the blow-up for such chains, so reinstating the overloads is now a semantic question, not a performance one — see SET-OPERATORS-SPEC §16.3 for the recorded ruling and its conditions.

### Equality: use `set equals`, not `EQUALS`

Bare `EQUALS` on two sets is a compile-time ambiguity error, **on purpose**. Builtin structural equality would be order-sensitive (`{1,2}` ≠ `{2,1}` as lists), which is silently wrong for sets; rather than pick wrongly, L4 makes you choose explicitly:

```l4
(setFromList (LIST 2, 1, 1)) `set equals` (setFromList (LIST 1, 2))   -- TRUE
```

### Known limit: the quotient is one level deep

Order/duplicate-insensitivity applies to a set's **elements**, compared with builtin structural equality. It does not compose:

- `SET OF SET OF a` compares inner sets by representation — `{{1,2}}` and `{{2,1}}` are _different_ elements;
- a set wrapped in any container (a record field, `PAIR`, `LIST`, `MAYBE`) compares structurally under bare `EQUALS`, with no diagnostic. Compare set-valued fields with `` `set equals` `` field-wise instead of comparing whole records.

See [set-operators-nested.l4](https://github.com/legalese/l4-ide/blob/main/jl4/examples/ok/set-operators-nested.l4), which pins this behavior.

### Variadic construction

A set of **two or more** elements can be written directly as `SET OF "refuge", "residence"` or `SET OF NY, NJ` — the arguments collect into a list automatically (the route-α typechecker elaboration). `setFromList (LIST …)` still works and is equivalent.

Two boundary cases to know:

- **A single element cannot use bare `SET OF`.** The collection only fires for two or more arguments; with one argument, `SET OF x` reads `x` as the contents _list_, so `SET OF "carol"` is a type error (a string is not a list). Write `setFromList (LIST "carol")` or `SET OF LIST "carol"` for a singleton.
- **A single list argument is taken literally:** `SET OF LIST 1, 2` is the two-element set `{1, 2}` (the list is the contents), not a one-element set containing a list.

### Example: Set Operations

[sets-example.l4](sets-example.l4)

**See the [Sets tutorial](../../tutorials/set-operators/sets-and-the-two-ands.md) for the legal-drafting motivation, and [SET-OPERATORS-SPEC](../../../specs/todo/SET-OPERATORS-SPEC.md) for the design record, including the case law.**
