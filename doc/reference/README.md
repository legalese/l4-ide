# Language Reference

The reference describes exactly what each part of L4 is and does. To learn the language step by step, take a [course](../courses/README.md); to get a particular job done, see the [tutorials](../tutorials/README.md).

| If you want to…                           | Go to                              |
| ----------------------------------------- | ---------------------------------- |
| Look up a single keyword or symbol        | [Glossary](GLOSSARY.md)            |
| Find the L4 version of code you know      | [Cheat sheet](cheat-sheet.md)      |
| Understand an error or warning            | [Error messages](errors/README.md) |
| Find a function for dates, money or lists | [Library](#library), further down  |

## Language

### [Types and data](types/README.md)

Describe the things your rules talk about: people, contracts, amounts, dates. The overview lists the built-in types (BOOLEAN, NUMBER, STRING, DATE) and the ready-made ones (LIST, MAYBE, EITHER).

| Page                            | What it covers                                                                                            |
| ------------------------------- | --------------------------------------------------------------------------------------------------------- |
| [DECLARE](types/DECLARE.md)     | Records with HAS, enumerations with ONE OF, computed fields, type synonyms, parameterised types, A and AN |
| [ASSUME](types/ASSUME.md)       | A name with a type but no value, for facts supplied from outside; how it works with `@export`             |
| [FOR ALL](types/for-all.md)     | Functions that work for values of any type                                                                |
| [Coercions](types/coercions.md) | Converting between NUMBER, STRING, DATE and other types                                                   |

### [Definitions](functions/README.md)

Write values, rules and functions, and give them inputs.

| Page                                                         | What it covers                                                                   |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| [DECIDE](functions/DECIDE.md)                                | Define a value, a function or a rule; DECIDE … IF; several clauses, one per case |
| [GIVEN and GIVETH](functions/GIVEN.md)                       | Name and type the inputs; state the type of the result                           |
| [MEANS](functions/MEANS.md)                                  | The body of a definition, and computed fields in records                         |
| [LET and WHERE](functions/LET.md)                            | Local definitions, before or after an expression                                 |
| [YIELD](functions/YIELD.md)                                  | Functions without a name                                                         |
| [AKA](functions/AKA.md)                                      | Other names for a definition, a type or a section                                |
| [Mixfix definitions](functions/README.md#mixfix-definitions) | Names with words between the inputs, so a call reads like a sentence             |

### [Control flow](control-flow/README.md)

Choose between cases.

| Page                                 | What it covers                                                   |
| ------------------------------------ | ---------------------------------------------------------------- |
| [IF](control-flow/IF.md)             | A choice between two values; several conditions                  |
| [BRANCH](control-flow/BRANCH.md)     | Several conditions checked in order, with an OTHERWISE           |
| [CONSIDER](control-flow/CONSIDER.md) | Choosing by the shape of a value; missing and redundant branches |

### [Operators](operators/README.md)

Combine and compare values. The overview covers word and symbol forms (`AND` or `&&`), precedence, and AND and OR across several lines (`...`, `..`).

| Page                                           | What it covers                                                   |
| ---------------------------------------------- | ---------------------------------------------------------------- |
| [AND, OR, NOT, IMPLIES](operators/logical.md)  | Truth tables, conditions over several lines, order of evaluation |
| [UNLESS](operators/UNLESS.md)                  | Exceptions: "A, unless B"                                        |
| [Arithmetic](operators/arithmetic/README.md)   | PLUS, MINUS, TIMES, DIVIDED BY, MODULO; exact numbers            |
| [Comparisons](operators/comparisons/README.md) | EQUALS, GREATER THAN, LESS THAN, AT LEAST, AT MOST               |

### [Regulative rules](regulative/README.md)

Obligations, permissions and prohibitions: who must, may or must not do what, by when, and what follows. The overview shows the parts of a rule and how to test one with `#TRACE`.

| Page                                                     | What it covers                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)           | Who acts, and whether they must, may or must not (MUST NOT); DO               |
| [Deadlines and consequences](regulative/consequences.md) | WITHIN, HENCE and LEST, FULFILLED and BREACH, PROVIDED, EXACTLY, RAND and ROR |
| [BECAUSE](regulative/BECAUSE.md)                         | The reason given for a breach                                                 |
| [DEONTIC](regulative/DEONTIC.md)                         | The type of a regulative rule, and how a rule is evaluated                    |
| [EVENT](regulative/EVENT.md)                             | What a party did and when; WAIT UNTIL                                         |

### [Syntax and directives](syntax/README.md)

How an L4 file is written, on one page:

- **Text and layout:** [layout](syntax/README.md#layout), [comments](syntax/README.md#comments), [identifiers](syntax/README.md#identifiers), [literals](syntax/README.md#literals)
- **Files:** [IMPORT](syntax/README.md#import), [§ sections](syntax/README.md#sections)
- **Annotations:** [`@desc`, `@nlg`, `@ref`, `@export`](syntax/README.md#annotations)
- **Directives:** [`#EVAL`, `#CHECK`, `#ASSERT`, `#TRACE`](syntax/README.md#directives)
- **Legal phrasing:** [genitive 's](syntax/README.md#genitive), [OF](syntax/README.md#of), [ditto ^](syntax/README.md#ditto), [AND and OR over several lines](syntax/README.md#asyndetic-and-and-or)

## Library

### [Built-in functions](builtins/README.md)

Functions every L4 file can use without `IMPORT`:

- [Numbers](builtins/README.md#numbers), [text](builtins/README.md#text), [dates](builtins/README.md#dates), [times of day](builtins/README.md#times-of-day), [date and time together](builtins/README.md#date-and-time-together)
- [Looking across days](builtins/README.md#looking-across-days) and [regulative traces](builtins/README.md#regulative-traces)
- [HTTP and JSON](builtins/http-json.md): FETCH, POST, ENV, JSONENCODE, JSONDECODE

### [Standard libraries](libraries/README.md)

Libraries you load with [`IMPORT`](libraries/README.md#import):

| Group                     | Libraries                                                                                                                                                               |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core                      | [prelude](libraries/prelude.md) (lists, MAYBE, EITHER, pairs), [math](libraries/math.md)                                                                                |
| Dates and time            | [daydate](libraries/daydate.md), [time](libraries/time.md), [datetime](libraries/datetime.md), [timezone](libraries/timezone.md), [excel-date](libraries/excel-date.md) |
| Money and finance         | [currency](libraries/currency.md), [holdings](libraries/holdings.md), [actus](libraries/actus.md)                                                                       |
| Legal entities and places | [legal-persons](libraries/legal-persons.md), [jurisdiction](libraries/jurisdiction.md)                                                                                  |
| AI                        | [llm](libraries/llm.md)                                                                                                                                                 |

### [Error messages](errors/README.md)

What the compiler's errors and warnings mean and how to fix them, grouped by kind: [layout and syntax](errors/README.md#layout-and-syntax), [types](errors/README.md#types), [names and imports](errors/README.md#names-and-imports), [definitions and clauses](errors/README.md#definitions-and-clauses), [pattern matching](errors/README.md#pattern-matching), [regulative rules](errors/README.md#regulative-rules) and [export](errors/README.md#export).
