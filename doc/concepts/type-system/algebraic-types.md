# Algebraic Types in L4

Why L4 builds its data model from algebraic data types — and why those types are a natural fit for legal structure.

---

## What Are Algebraic Types?

**Algebraic data types** (ADTs) are types built from two fundamental operations:

1. **Product types**: Combine multiple values (AND)
2. **Sum types**: Choose between alternatives (OR)

L4 uses ADTs extensively because they naturally map to legal structures. This article explains the mapping; for the full syntax of declaring and using types, see the [Types Reference](../../reference/types/README.md) and [DECLARE](../../reference/types/DECLARE.md).

---

## Product Types: Records

A **product type** combines multiple values together. In L4, these are **records**:

```l4
DECLARE Person
    HAS `name` IS A STRING
        `age` IS A NUMBER
        `email` IS A STRING
```

The set of possible `Person` values is the **product** (cross-product) of all field types:

```
Person = STRING × NUMBER × STRING
       = {all possible names} × {all possible ages} × {all possible emails}
```

Records model legal entities — the bundle of facts a legal instrument cares about:

```l4
DECLARE Contract
    HAS parties IS A LIST OF Party
        `effective date` IS A DATE
        obligations IS A LIST OF Obligation
```

For record construction and field access syntax (`Person "Alice Smith" 30 "alice@example.com"`, `alice's name`), see the [Types Reference](../../reference/types/README.md).

---

## Sum Types: Enumerations

A **sum type** represents a choice between alternatives. In L4, we use `IS ONE OF`:

```l4
DECLARE Status IS ONE OF
    Active
    Suspended
    Terminated
```

The set of possible `Status` values is the **sum** (union) of the variants:

```
Status = Active ∪ Suspended ∪ Terminated
       = 3 possible values
```

Variants can also carry data of their own:

```l4
DECLARE `payment status` IS ONE OF
    Pending
    Paid HAS `date paid` IS A DATE
             amount IS A NUMBER
    Rejected HAS reason IS A STRING
```

A `Paid` value always has a date and an amount; a `Rejected` value always has a reason; a `Pending` value carries nothing. Each alternative carries exactly the data that is relevant to it — there are no unused or "not applicable" fields.

For the full enumeration syntax, see [DECLARE](../../reference/types/DECLARE.md) and the [enum example](../../reference/types/enum-example.l4).

---

## Pattern Matching and Exhaustiveness

To work with sum types, use `CONSIDER`:

```l4
GIVEN status IS A `payment status`
GIVETH A STRING
`describe status` MEANS
    CONSIDER status
    WHEN Pending THEN "Payment pending"
    WHEN Paid d a THEN "Paid"
    WHEN Rejected r THEN r
```

### Exhaustiveness

L4 checks that a `CONSIDER` over an algebraic type covers all of its constructors. If a case is missing, the compiler emits a **warning**:

```l4
-- ⚠️ Warning: "The following branches still need to be considered: WHEN Rejected THEN"
CONSIDER status
WHEN Pending THEN "..."
WHEN Paid d a THEN "..."
```

The checker also warns about **redundant** branches that can never be reached. Two caveats:

- The check applies to algebraic types with a known, finite set of constructors. Scrutinees of primitive types (`NUMBER`, `STRING`, `DATE`) are not checked, because their values cannot be enumerated.
- A missing case is a warning, not a hard error — the program still compiles and runs.

See [Exhaustiveness](exhaustiveness.md) for why this check matters legally, and why it is a warning rather than an error.

### Otherwise

`OTHERWISE` is a catch-all branch:

```l4
CONSIDER status
WHEN Pending THEN "Not yet processed"
OTHERWISE "Already processed"
```

Note the trade-off: `OTHERWISE` silences the exhaustiveness check. If a new variant is added to the type later, the catch-all will absorb it silently instead of prompting you to decide how it should be handled.

---

## Why Algebraic Types Map to Legal Structure

This is the conceptual heart of the matter: legal drafting already uses the algebra, just informally.

### Closed enumerations are statutory categories

Legal definitions are typically **closed lists**:

> A "person" means—
> (a) a natural person; or
> (b) a body corporate; or
> (c) a partnership.

This maps directly to a sum type:

```l4
DECLARE Person IS ONE OF
    `natural person` HAS ...
    `body corporate` HAS ...
    partnership HAS ...
```

The closure is the point. Nothing is a `Person` unless it is one of the three listed alternatives — and nothing becomes one without amending the declaration, just as nothing enters the statutory definition without amending the statute. An open-ended encoding (say, a `STRING` holding "natural person") cannot express this: it admits values the law never defined, and the type checker has no way to notice.

### Sum types are alternative legal statuses

A legal status is usually **mutually exclusive**: a contract is draft _or_ executed _or_ terminated; a payment is pending _or_ paid _or_ rejected — never two at once. A sum type builds that exclusivity into the data model.

Compare the flattened alternative — a record of booleans:

```l4
-- ❌ Admits impossible states
DECLARE ContractFlags
    HAS `is draft` IS A BOOLEAN
        `is executed` IS A BOOLEAN
        `is terminated` IS A BOOLEAN
```

This type has 8 possible values, of which at most 3 describe a legally coherent contract. What does it mean for a contract to be simultaneously draft and terminated? The sum type version has exactly the 3 values the law contemplates. Illegal states are not merely avoided — they are **unrepresentable**.

### Products are required particulars

Where legal text prescribes what an entity must comprise, that is a product type:

> A "registered charity" must have—
>
> - a registered name
> - a registration number
> - at least one charitable purpose

```l4
DECLARE `registered charity`
    HAS `name` IS A STRING
        `registration number` IS A STRING
        purposes IS A LIST OF Purpose
```

A value of this type cannot be constructed with a particular missing — the type checker enforces the completeness that the statute demands.

### Variants with data mirror case-specific particulars

Legal consequences often depend on _which_ alternative applies, and each alternative comes with its own relevant facts: a rejected application has grounds for rejection; a granted one has a grant date. Attaching data to variants keeps each case's facts with that case, instead of a wide record where most fields are meaningless most of the time.

### Exhaustiveness is complete case analysis

A legal determination over a closed category must say what happens in **every** case — a tax rule that classifies entities must have an answer for each entity type:

```l4
CONSIDER entity
WHEN `natural person` p THEN `personal tax rules` p
WHEN `body corporate` c THEN `corporate tax rules` c
WHEN partnership p THEN `partnership tax rules` p
-- The compiler warns if a case is missing
```

When the legislature adds a fourth category, adding the variant to the declaration makes the checker flag every determination that has not yet decided how to handle it. The type system turns "we forgot about partnerships" from a silent gap into a visible diagnostic. This property is developed fully in [Exhaustiveness](exhaustiveness.md).

---

## Combining Product and Sum

Real models nest both freely:

```l4
-- Sum type whose variants are products
DECLARE Employment IS ONE OF
    Employed HAS employer IS A Company
                 `start date` IS A DATE
                 salary IS A NUMBER
    `Self-employed` HAS `business name` IS A STRING
    Unemployed HAS since IS A DATE

-- Product type containing a sum type
DECLARE Worker
    HAS `name` IS A STRING
        `employment status` IS AN Employment
```

And pattern matching reaches inside:

```l4
GIVEN worker IS A Worker
GIVETH A BOOLEAN
`is currently employed` MEANS
    CONSIDER worker's `employment status`
    WHEN Employed e s sal THEN TRUE
    OTHERWISE FALSE
```

---

## Recursive Types

Types can reference themselves, which is how nested, tree-shaped legal structures are modeled — most obviously the structure of a legal document itself:

```l4
DECLARE `legal document` IS ONE OF
    Section HAS number IS A STRING
                title IS A STRING
                content IS A LIST OF `legal document`
    Paragraph HAS text IS A STRING
    Definition HAS term IS A STRING
                   meaning IS A STRING
```

A section contains subsections, which contain paragraphs and definitions — arbitrarily deep, out of one three-variant declaration.

---

## Common Patterns

### Optional Values: MAYBE

```l4
DECLARE Person
    HAS `name` IS A STRING
        `middle name` IS A MAYBE STRING  -- Optional
```

`MAYBE` is itself a sum type — conceptually:

```
MAYBE a  =  NOTHING  |  JUST a
```

Optionality is explicit in the type, and `CONSIDER ... WHEN NOTHING ... WHEN JUST x ...` forces both possibilities to be handled. There is no null. See the [maybe example](../../reference/types/maybe-example.l4).

### Lists

Lists are also algebraic — conceptually a sum of "empty" and "an element followed by a rest", matched with:

```l4
CONSIDER items
WHEN EMPTY THEN "no items"
WHEN x FOLLOWED BY rest THEN "at least one item"
```

See the [list example](../../reference/types/list-example.l4).

---

## Summary

| Concept       | L4 Syntax                      | Mathematical View | Legal Reading             |
| ------------- | ------------------------------ | ----------------- | ------------------------- |
| Product type  | `DECLARE X HAS field1, field2` | X = A × B         | Required particulars      |
| Sum type      | `DECLARE X IS ONE OF A, B, C`  | X = A + B + C     | Closed statutory category |
| Sum with data | `A HAS field IS A Type`        | Tagged union      | Case-specific particulars |
| Pattern match | `CONSIDER x WHEN ...`          | Case analysis     | Complete determination    |
| Optional      | `MAYBE Type`                   | 1 + Type          | Explicitly optional fact  |
| List          | `LIST OF Type`                 | 1 + (Type × List) | Repeating particulars     |

---

## Further Reading

- [Exhaustiveness](exhaustiveness.md) - Totality of determinations as a legal-safety property
- [Types Reference](../../reference/types/README.md) - Detailed type reference
- [Type Theory](../../reference/types/type-theory.md) - Formal foundations of the type system
- [Foundation Course Module 2](../../courses/foundation/module-2-entities.md) - Hands-on with types
