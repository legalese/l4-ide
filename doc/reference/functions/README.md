# Functions

A function takes inputs and computes a result from them. In L4 each rule is a function: `GIVEN` names and types its inputs, `GIVETH` states the type of its result, and `DECIDE` or `MEANS` gives the expression that computes it. A function without inputs is a named value.

```l4
GIVEN age IS A NUMBER
GIVETH A BOOLEAN
DECIDE `is an adult` age IF age >= 18
```

## Pages

- [DECIDE](DECIDE.md): define a value or a function, including `DECIDE … IF` and functions written as several clauses
- [GIVEN and GIVETH](GIVEN.md): declare the inputs and the result type
- [MEANS](MEANS.md): define without `DECIDE`
- [LET and WHERE](LET.md): local definitions before or after an expression
- [YIELD](YIELD.md): functions without a name
- [AKA](AKA.md): more than one name for the same function, value, type or section

## Mixfix functions

A function's name does not have to come first. In a **mixfix** function, the `GIVEN` inputs are placed between the words of the name, so a call reads like a sentence:

```l4
GIVEN mom IS A STRING
      dad IS A STRING
      kid IS A STRING
GIVETH A STRING
mom and dad `have a baby named` kid MEANS
    CONCAT "mother: ", mom, ", father: ", dad, ", child: ", kid

#EVAL "alice" and "bob" `have a baby named` "carol"
```

- A call uses the same word order as the definition.
- Inputs can come before, between or after the words, so a function can be infix (``applicant `is entitled to` benefit``) or postfix (`n squared`).
- A word of the name can be a quoted identifier with spaces, such as `` `is entitled to` ``, so the words can be legal phrases.
- The words that are not inputs act as keywords of that function. When a call mixes inputs and words, L4 finds the function by those words.

A mixfix function cannot be written as [several clauses](DECIDE.md#several-clauses); use `CONSIDER` in its body.

When to use mixfix, with worked examples: [Make rules read like law](../../tutorials/natural-language-functions/optimising-natural-language-generation.md).

## Related pages

- [Types](../types/README.md): types of inputs and results
- [Operators](../operators/README.md): operators inside expressions
- [Control flow](../control-flow/README.md): `IF`, `BRANCH` and `CONSIDER`
