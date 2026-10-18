# Concepts

These pages explain why L4 works the way it does: the choices behind its syntax, how it models legal rules, and what its type system guarantees. Read them after you have tried a feature. For what a keyword does, see the [Reference](../reference/README.md); for step-by-step guides, see the [Tutorials](../tutorials/README.md).

## Language design

- [Design principles](language-design/principles.md): the five principles behind L4, and the style of writing that follows from them.
- [Reading like the law](language-design/linguistic-syntax.md): how L4 borrows from English grammar so that code can be checked against its source text.
- [Flowcharts, Decision Tables, and Real Logic](language-design/logic-not-flowcharts.md): why L4 is a language with derived diagrams, not a flowchart or decision-table builder.
- [Related Work: Tables, Trees, Diagrams, and Order](language-design/related-work.md): the reading behind that page, organised by claim so that you can check us.

## Legal modeling

- [Definitions and duties](legal-modeling/constitutive-vs-regulative.md): why L4 keeps rules that define things apart from rules that impose duties.
- [Exceptions and defaults](legal-modeling/default-reasoning.md): how to encode a general rule followed by its exceptions.
- [How obligations unfold](legal-modeling/regulative-rules.md): a contract as something that waits for events and moves through time.
- [The Regulative Layer, Whole](legal-modeling/regulative-layer-whole.md): the separate ideas that make up an obligation in L4, told as questions about one tenancy.
- [Five Kinds of No Answer](legal-modeling/non-answers.md): what a person can mean by "there is no answer": a value that may be absent, a failure with a reason, a fact nobody has supplied, a law not in force, and a model that does not cover the case.
- [Residual: One Word, Three Disciplines](legal-modeling/residual.md): how L4's residual obligation relates to residual control rights in incomplete contract theory and to residual discretionary power in public law.

## Types

- [Types as legal categories](type-system/algebraic-types.md): records and enumerations as the shapes of legal definitions.
- [Exhaustiveness](type-system/exhaustiveness.md): why L4 checks that a determination handles every case.
- [Type theory](type-system/type-theory.md): the formal foundations, for readers who know type theory.

## Neighbouring systems

- [Blawx and s(CASP)](neighbours/blawx-and-scasp.md): Jason Morris's block-based rules-as-code tool and the goal-directed answer set programming underneath it, for L4 readers.

## Reviewing

- [Reviewing Encoded Law](reviewing/reviewing-encoded-law.md): who checks an encoding against the law, and what their sign-off means.
