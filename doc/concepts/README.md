# Concepts

These pages explain why L4 works the way it does: the choices behind its syntax, how it models legal rules, and what its type system guarantees. Read them after you have tried a feature. For what a keyword does, see the [Reference](../reference/README.md); for step-by-step guides, see the [Tutorials](../tutorials/README.md).

## Language design

- [Design principles](language-design/principles.md): the five principles behind L4, and the style of writing that follows from them.
- [Reading like the law](language-design/linguistic-syntax.md): how L4 borrows from English grammar so that code can be checked against its source text.

## Legal modeling

- [Definitions and duties](legal-modeling/constitutive-vs-regulative.md): why L4 keeps rules that define things apart from rules that impose duties.
- [Exceptions and defaults](legal-modeling/default-reasoning.md): how to encode a general rule followed by its exceptions.
- [How obligations unfold](legal-modeling/regulative-rules.md): a contract as something that waits for events and moves through time.

## Types

- [Types as legal categories](type-system/algebraic-types.md): records and enumerations as the shapes of legal definitions.
- [Exhaustiveness](type-system/exhaustiveness.md): why L4 checks that a determination handles every case.
- [Type theory](type-system/type-theory.md): the formal foundations, for readers who know type theory.
