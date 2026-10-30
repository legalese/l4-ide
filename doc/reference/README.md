# Language Reference

The reference describes exactly what each part of L4 is and does. To learn the language step by step, take a [course](../courses/README.md); to get a particular job done, see the [tutorials](../tutorials/README.md).

| Go to                                 | If you want to…                                                        |
| ------------------------------------- | ---------------------------------------------------------------------- |
| [Glossary](GLOSSARY.md)               | Look up a single keyword or symbol                                     |
| [Cheat sheet](cheat-sheet.md)         | Find the L4 version of code you know                                   |
| [Error messages](errors/README.md)    | Understand an error or warning                                         |
| [Override phrases](lint/overrides.md) | Check that "subject to" and "notwithstanding" are kept by the encoding |
| [Library](#library)                   | Find a function for dates, money or lists (further down the page)      |

## Language

### [Types](types/README.md)

Describe the things your rules talk about: people, contracts, amounts, dates. The overview lists the built-in types (BOOLEAN, NUMBER, STRING, DATE) and the ready-made ones (LIST, MAYBE, EITHER).

| Page                                   | What it covers                                                                                                          |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| [DECLARE](types/DECLARE.md)            | Records with HAS, enumerations with ONE OF, computed fields, type synonyms, opaque types, parameterised types, A and AN |
| [ASSUME (deprecated)](types/ASSUME.md) | The older spelling of an input, an opaque type or a refusal, and what to write instead                                  |
| [TYPICALLY](types/TYPICALLY.md)        | A default value that stands until a fact is supplied: a rebuttable presumption                                          |
| [FOR ALL](types/for-all.md)            | Functions that work for values of any type                                                                              |
| [Coercions](types/coercions.md)        | Converting between NUMBER, STRING, DATE and other types                                                                 |

### [Functions](functions/README.md)

Rules in L4 are functions: they take inputs and compute a result.

| Page                                                     | What it covers                                                                   |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- |
| [DECIDE](functions/DECIDE.md)                            | Define a value, a function or a rule; DECIDE … IF; several clauses, one per case |
| [GIVEN and GIVETH](functions/GIVEN.md)                   | Name and type the inputs; state the type of the result                           |
| [MEANS](functions/MEANS.md)                              | The body of a definition, and computed fields in records                         |
| [LET and WHERE](functions/LET.md)                        | Local definitions, before or after an expression                                 |
| [YIELD](functions/YIELD.md)                              | Functions without a name                                                         |
| [WITH](functions/WITH.md)                                | Supply a call's arguments by name                                                |
| [AKA](functions/AKA.md)                                  | Other names for a definition, a type or a section                                |
| [Mixfix functions](functions/README.md#mixfix-functions) | Names with words between the inputs, so a call reads like a sentence             |

### [Control flow](control-flow/README.md)

Choose between cases.

| Page                                 | What it covers                                                   |
| ------------------------------------ | ---------------------------------------------------------------- |
| [IF](control-flow/IF.md)             | A choice between two values; several conditions                  |
| [BRANCH](control-flow/BRANCH.md)     | Several conditions checked in order, with an OTHERWISE           |
| [CONSIDER](control-flow/CONSIDER.md) | Choosing by the shape of a value; missing and redundant branches |
| [REFUSE](control-flow/REFUSE.md)     | Decline to answer, and say why                                   |

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

| Page                                                     | What it covers                                                                                                                       |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)           | Who acts, and whether they must, may or must not (MUST NOT); DO                                                                      |
| [Deadlines and consequences](regulative/consequences.md) | WITHIN, BEFORE, HENCE and LEST, FULFILLED and BREACH, PROVIDED, what a name in an action means (EXACTLY is deprecated), RAND and ROR |
| [BECAUSE](regulative/BECAUSE.md)                         | The reason given for a breach                                                                                                        |
| [DEONTIC](regulative/DEONTIC.md)                         | The type of a regulative rule, and how a rule is evaluated                                                                           |
| [EVENT](regulative/EVENT.md)                             | What a party did and when; WAIT UNTIL                                                                                                |
| [AFTER](regulative/AFTER.md)                             | When the window opens: the opening edge, after WITHIN's closing edge                                                                 |
| [EVERY](regulative/EVERY.md)                             | An obligation on every member of a group at once                                                                                     |
| [What is owed now: `l4 lts`](regulative/lts-list.md)     | Given what has happened, what is owed, what would discharge it                                                                       |
| [The state graph](regulative/STATE-GRAPH.md)             | A map of a regulative rule: every state it can be in                                                                                 |

### [Syntax and directives](syntax/README.md)

How an L4 file is written, on one page:

- **Text and layout:** [layout](syntax/README.md#layout), [comments](syntax/README.md#comments), [identifiers](syntax/README.md#identifiers), [literals](syntax/README.md#literals)
- **Files:** [IMPORT](syntax/README.md#import), [§ sections](syntax/README.md#sections), [sections in full](syntax/sections.md), [the section `GIVEN`](syntax/section-given.md), [field opening](syntax/field-opening.md)
- **Annotations:** [`@desc`, `@nlg`, `@ref`, `@export`](syntax/README.md#annotations)
- **Directives:** [`#EVAL`, `#CHECK`, `#ASSERT`, `#TRACE`](syntax/README.md#directives)
- **Legal phrasing:** [genitive 's](syntax/README.md#genitive), [OF](syntax/README.md#of), [ditto ^](syntax/README.md#ditto), [AND and OR over several lines](syntax/README.md#asyndetic-and-and-or)

### [Query planning](query-planning/README.md)

Turn a Boolean decision into an interactive question-and-answer wizard: which question to ask next, and when the outcome is already settled. The [ROBDD page](query-planning/robdd.md) describes the canonical Boolean form the planner is built on.

## Library

### [Built-in functions](builtins/README.md)

Functions every L4 file can use without `IMPORT`:

- [Numbers](builtins/README.md#numbers), [text](builtins/README.md#text), [dates](builtins/README.md#dates), [times of day](builtins/README.md#times-of-day), [date and time together](builtins/README.md#date-and-time-together)
- [Looking across days](builtins/README.md#looking-across-days) and [regulative traces](builtins/README.md#regulative-traces)
- [HTTP and JSON](builtins/http-json.md): FETCH, POST, ENV, JSONENCODE, JSONDECODE

### [Standard libraries](libraries/README.md)

Libraries you load with [`IMPORT`](libraries/README.md#import), the prelude included; [how IMPORT finds libraries](libraries/resolution.md) is for people who run the tools or develop a library:

| Group                     | Libraries                                                                                                                                                               |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core                      | [prelude](libraries/prelude.md) (lists, MAYBE, EITHER, pairs), [sets](libraries/sets.md), [math](libraries/math.md)                                                     |
| Dates and time            | [daydate](libraries/daydate.md), [time](libraries/time.md), [datetime](libraries/datetime.md), [timezone](libraries/timezone.md), [excel-date](libraries/excel-date.md) |
| Money and finance         | [currency](libraries/currency.md), [holdings](libraries/holdings.md), [actus](libraries/actus.md)                                                                       |
| Legal entities and places | [legal-persons](libraries/legal-persons.md), [jurisdiction](libraries/jurisdiction.md)                                                                                  |
| AI                        | [llm](libraries/llm.md)                                                                                                                                                 |
| Open and closed worlds    | [negation-as-failure](libraries/negation-as-failure.md) (`MAYBE BOOLEAN` under an open- or closed-world default)                                                        |

### [Error messages](errors/README.md)

What the compiler's errors and warnings mean and how to fix them, grouped by kind: [layout and syntax](errors/README.md#layout-and-syntax), [types](errors/README.md#types), [names and imports](errors/README.md#names-and-imports), [definitions and clauses](errors/README.md#definitions-and-clauses), [pattern matching](errors/README.md#pattern-matching), [regulative rules](errors/README.md#regulative-rules) and [export](errors/README.md#export).
