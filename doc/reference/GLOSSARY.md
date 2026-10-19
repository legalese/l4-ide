# Glossary

Every keyword, operator, type, directive and annotation in L4, with a one-line meaning and a link to the page that describes it. Functions are listed under [Built-in functions](builtins/README.md) and [Standard libraries](libraries/README.md).

## Functions

| Keyword                | Meaning                                                                  | Reference                                     |
| ---------------------- | ------------------------------------------------------------------------ | --------------------------------------------- |
| **DECIDE**             | Defines a value, a function or a rule; one definition or several clauses | [DECIDE](functions/DECIDE.md)                 |
| **MEANS**              | Gives the body of a function, a value or a computed field                | [MEANS](functions/MEANS.md)                   |
| **IS**                 | Gives the body after `DECIDE name`; also states a type (`IS A NUMBER`)   | [DECIDE](functions/DECIDE.md)                 |
| **IF** (after DECIDE)  | `DECIDE x IF condition` defines a BOOLEAN                                | [DECIDE](functions/DECIDE.md)                 |
| **GIVEN**              | Names and types the inputs of a function                                 | [GIVEN and GIVETH](functions/GIVEN.md)        |
| **GIVETH** / **GIVES** | States the type of the result                                            | [GIVEN and GIVETH](functions/GIVEN.md#giveth) |
| **LET** ... **IN**     | Local definitions before an expression                                   | [LET and WHERE](functions/LET.md)             |
| **BE** / **MEAN**      | Alternatives to IS and MEANS in a LET binding                            | [LET and WHERE](functions/LET.md)             |
| **WHERE**              | Local definitions after an expression                                    | [LET and WHERE](functions/LET.md#where)       |
| **YIELD**              | A function without a name: `GIVEN n YIELD n + 1`                         | [YIELD](functions/YIELD.md)                   |
| **AKA**                | Another name for the same function, value, type or section               | [AKA](functions/AKA.md)                       |
| Several clauses        | A rule written as one line per case: `DECIDE price Red IS 1`             | [DECIDE](functions/DECIDE.md#several-clauses) |

## Types

| Keyword                      | Meaning                                                                            | Reference                       |
| ---------------------------- | ---------------------------------------------------------------------------------- | ------------------------------- |
| **DECLARE**                  | Defines a new type                                                                 | [DECLARE](types/DECLARE.md)     |
| **HAS**                      | Lists the fields of a record, including computed fields with MEANS                 | [DECLARE](types/DECLARE.md)     |
| **ONE OF**                   | Lists the alternatives of an enumeration                                           | [DECLARE](types/DECLARE.md)     |
| **IS A** / **IS AN**         | States a type: `age IS A NUMBER`                                                   | [DECLARE](types/DECLARE.md)     |
| **A** / **AN** / **THE**     | Articles before a type name; they do not change the meaning                        | [DECLARE](types/DECLARE.md)     |
| **OF**                       | Applies a type or a constructor to its arguments: `LIST OF NUMBER`, `PAIR OF x, y` | [DECLARE](types/DECLARE.md)     |
| **WITH**                     | Builds a record by field name: `Person WITH name IS "Ann"`                         | [DECLARE](types/DECLARE.md)     |
| **ASSUME**                   | Declares a name with a type but no definition                                      | [ASSUME](types/ASSUME.md)       |
| **TYPE**                     | The type of types, for type inputs: `GIVEN a IS A TYPE`                            | [FOR ALL](types/for-all.md)     |
| **FOR ALL**                  | Introduces type variables in a type                                                | [FOR ALL](types/for-all.md)     |
| **FUNCTION FROM** ... **TO** | A function type: `FUNCTION FROM NUMBER TO BOOLEAN`                                 | [Types](types/README.md)        |
| **AS**                       | `x AS STRING` turns a value into text                                              | [Coercions](types/coercions.md) |

## Built-in types

| Type           | Meaning                                                           | Reference                                    |
| -------------- | ----------------------------------------------------------------- | -------------------------------------------- |
| **NUMBER**     | Whole numbers and exact fractions                                 | [Types](types/README.md)                     |
| **STRING**     | Text                                                              | [Types](types/README.md)                     |
| **BOOLEAN**    | `TRUE` or `FALSE`                                                 | [Types](types/README.md)                     |
| **DATE**       | A calendar date                                                   | [Types](types/README.md)                     |
| **TIME**       | A time of day, with no date or time zone                          | [Types](types/README.md)                     |
| **DATETIME**   | A moment in time, with a time zone                                | [Types](types/README.md)                     |
| **LIST**       | A list of values of one type; also writes a list: `LIST 1, 2, 3`  | [Types](types/README.md)                     |
| **MAYBE**      | A value that may be missing: `JUST x` or `NOTHING`                | [Types](types/README.md)                     |
| **EITHER**     | One of two values: `LEFT x` or `RIGHT y`                          | [Types](types/README.md)                     |
| **PAIR**       | Two values together, from the prelude                             | [prelude](libraries/prelude.md#pairs)        |
| **Dictionary** | Keys mapped to values, from the prelude                           | [prelude](libraries/prelude.md#dictionaries) |
| **DEONTIC**    | The type of a regulative rule: `DEONTIC party action`             | [DEONTIC](regulative/DEONTIC.md)             |
| **PROVISION**  | An older name for DEONTIC                                         | [DEONTIC](regulative/DEONTIC.md)             |
| **EVENT**      | Something a party did at a time, for traces: `EVENT party action` | [EVENT](regulative/EVENT.md)                 |

## Constants and constructors

| Name                                              | Meaning                                                                | Reference                                |
| ------------------------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------- |
| **TRUE** / **FALSE**                              | The two BOOLEAN values                                                 | [Types](types/README.md)                 |
| **JUST** / **NOTHING**                            | A present or a missing MAYBE value                                     | [Types](types/README.md)                 |
| **LEFT** / **RIGHT**                              | The two sides of an EITHER                                             | [Types](types/README.md)                 |
| **EMPTY**                                         | The empty list                                                         | [Types](types/README.md)                 |
| **TODAY**, **NOW**, **CURRENTTIME**, **TIMEZONE** | The current date, moment and time of day, and the document's time zone | [Built-in functions](builtins/README.md) |

## Control flow

| Keyword                          | Meaning                                                                              | Reference                            |
| -------------------------------- | ------------------------------------------------------------------------------------ | ------------------------------------ |
| **IF** ... **THEN** ... **ELSE** | Chooses between two values                                                           | [IF](control-flow/IF.md)             |
| **BRANCH**                       | A multi-way conditional: a list of `IF ... THEN` lines and an `OTHERWISE`            | [BRANCH](control-flow/BRANCH.md)     |
| **CONSIDER**                     | Pattern matching: picks a branch by the shape of a value                             | [CONSIDER](control-flow/CONSIDER.md) |
| **WHEN**                         | One branch of a CONSIDER                                                             | [CONSIDER](control-flow/CONSIDER.md) |
| **OTHERWISE**                    | The branch for every remaining case, in CONSIDER and BRANCH                          | [CONSIDER](control-flow/CONSIDER.md) |
| **EXACTLY**                      | In a pattern, matches a given value; in a regulative rule, matches an action exactly | [CONSIDER](control-flow/CONSIDER.md) |

## Operators

| Operator                         | Meaning                                                     | Reference                                      |
| -------------------------------- | ----------------------------------------------------------- | ---------------------------------------------- |
| **AND**, `&&`, `...`             | Both are true                                               | [AND, OR, NOT, IMPLIES](operators/logical.md)  |
| **OR**, `\|\|`, `..`             | At least one is true                                        | [AND, OR, NOT, IMPLIES](operators/logical.md)  |
| **NOT**                          | Negation                                                    | [AND, OR, NOT, IMPLIES](operators/logical.md)  |
| **IMPLIES**, `=>`                | If the first is true, so is the second                      | [AND, OR, NOT, IMPLIES](operators/logical.md)  |
| **UNLESS**                       | `a UNLESS b` is `a AND NOT b`, binding more loosely than OR | [UNLESS](operators/UNLESS.md)                  |
| **PLUS**, `+`                    | Addition; also adds days to a date                          | [Arithmetic](operators/arithmetic/README.md)   |
| **MINUS**, `-`                   | Subtraction                                                 | [Arithmetic](operators/arithmetic/README.md)   |
| **TIMES**, `*`                   | Multiplication                                              | [Arithmetic](operators/arithmetic/README.md)   |
| **DIVIDED BY**, `/`              | Division                                                    | [Arithmetic](operators/arithmetic/README.md)   |
| **MODULO**                       | Remainder of a division of whole numbers                    | [Arithmetic](operators/arithmetic/README.md)   |
| `%`                              | Percent after a number: `5%` is 0.05                        | [Arithmetic](operators/arithmetic/README.md)   |
| **EQUALS**, `=`                  | Equality                                                    | [Comparisons](operators/comparisons/README.md) |
| **GREATER THAN**, **ABOVE**, `>` | Greater than                                                | [Comparisons](operators/comparisons/README.md) |
| **LESS THAN**, **BELOW**, `<`    | Less than                                                   | [Comparisons](operators/comparisons/README.md) |
| **AT LEAST**, `>=`               | Greater than or equal                                       | [Comparisons](operators/comparisons/README.md) |
| **AT MOST**, `<=`                | Less than or equal                                          | [Comparisons](operators/comparisons/README.md) |
| **FOLLOWED BY**                  | Puts an item in front of a list                             | [Operators](operators/README.md)               |
| **CONCAT**                       | Joins strings: `CONCAT "a", "b"`                            | [Built-in functions](builtins/README.md#text)  |
| `'s`                             | Reads a field: `person's age`                               | [Syntax and directives](syntax/README.md)      |

## Regulative rules

| Keyword              | Meaning                                                                               | Reference                                                         |
| -------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| **PARTY**            | Who the rule applies to                                                               | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **MUST**             | Obligation                                                                            | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **MAY**              | Permission                                                                            | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **SHANT / MUST NOT** | Prohibition; the two are synonyms                                                     | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md#shant-and-must-not) |
| **DO**               | An action neither required nor forbidden; without HENCE and LEST it behaves like MUST | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **PROVIDED**         | A condition the action must meet                                                      | [Deadlines and consequences](regulative/consequences.md)          |
| **WITHIN**           | The deadline, counted from when the rule starts                                       | [Deadlines and consequences](regulative/consequences.md)          |
| **HENCE**            | What follows when the rule is complied with                                           | [Deadlines and consequences](regulative/consequences.md)          |
| **LEST**             | What follows when it is not                                                           | [Deadlines and consequences](regulative/consequences.md)          |
| **FULFILLED**        | The end state: nothing more is owed                                                   | [Deadlines and consequences](regulative/consequences.md)          |
| **BREACH**           | The end state: a rule was broken; `BREACH BY party BECAUSE reason`                    | [Deadlines and consequences](regulative/consequences.md)          |
| **BY**               | Names the party in `BREACH BY`                                                        | [Deadlines and consequences](regulative/consequences.md)          |
| **RAND**             | Both rules apply at once                                                              | [Deadlines and consequences](regulative/consequences.md)          |
| **ROR**              | Either rule may be complied with                                                      | [Deadlines and consequences](regulative/consequences.md)          |
| **BECAUSE**          | The reason given for a breach                                                         | [BECAUSE](regulative/BECAUSE.md)                                  |
| **DOES**             | In a trace event: `PARTY Seller DOES deliver AT 3`                                    | [EVENT](regulative/EVENT.md)                                      |
| **AT**               | The time of an event, or the start time of a `#TRACE`                                 | [EVENT](regulative/EVENT.md)                                      |

## Files and modules

| Keyword         | Meaning                                             | Reference                                        |
| --------------- | --------------------------------------------------- | ------------------------------------------------ |
| **IMPORT**      | Uses the definitions of another file or a library   | [Standard libraries](libraries/README.md#import) |
| **TIMEZONE IS** | Sets the document's time zone, an IANA name         | [timezone](libraries/timezone.md)                |
| `§`             | Starts a section of the document; `§§` a subsection | [Syntax and directives](syntax/README.md)        |

## Directives

| Directive    | Meaning                                                                                               | Reference                                            |
| ------------ | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `#EVAL`      | Evaluates an expression and shows the result                                                          | [Syntax and directives](syntax/README.md#directives) |
| `#EVALTRACE` | Evaluates and shows each step                                                                         | [Syntax and directives](syntax/README.md#directives) |
| `#CHECK`     | Shows the type of an expression without evaluating it                                                 | [Syntax and directives](syntax/README.md#directives) |
| `#ASSERT`    | Reports an error unless the expression is TRUE                                                        | [Syntax and directives](syntax/README.md#directives) |
| `#TRACE`     | Runs a regulative rule against events: `#TRACE rule AT 0 WITH ...`; `STARTING AT` is the same as `AT` | [Syntax and directives](syntax/README.md#directives) |

## Annotations

| Annotation             | Meaning                                                           | Reference                                             |
| ---------------------- | ----------------------------------------------------------------- | ----------------------------------------------------- |
| `@desc`                | A description of a definition, shown in tools and APIs            | [Syntax and directives](syntax/README.md#annotations) |
| `@nlg`, `[...]`        | Wording used when a rule is put into natural language             | [Syntax and directives](syntax/README.md#annotations) |
| `@ref`, `<<...>>`      | A reference to the legal source                                   | [Syntax and directives](syntax/README.md#annotations) |
| `@ref-src`, `@ref-map` | Where references are looked up                                    | [Syntax and directives](syntax/README.md#annotations) |
| `@export`              | Publishes a function as an API endpoint when the file is deployed | [Syntax and directives](syntax/README.md#annotations) |
| `@export default`      | The function a deployment calls when no function is named         | [Syntax and directives](syntax/README.md#annotations) |

## Symbols

| Symbol             | Meaning                                                    | Reference                                 |
| ------------------ | ---------------------------------------------------------- | ----------------------------------------- |
| `--`, `//`         | A comment to the end of the line                           | [Syntax and directives](syntax/README.md) |
| `{- -}`, `/* */`   | A comment over several lines                               | [Syntax and directives](syntax/README.md) |
| `` ` ` ``          | Backticks around a name with spaces: `` `the applicant` `` | [Syntax and directives](syntax/README.md) |
| `"..."`            | A STRING                                                   | [Syntax and directives](syntax/README.md) |
| `^`                | Ditto: repeats the word above                              | [Syntax and directives](syntax/README.md) |
| `( )`              | Groups an expression                                       | [Syntax and directives](syntax/README.md) |
| `,`                | Separates list items and arguments after OF                | [Syntax and directives](syntax/README.md) |
| `` `_` ``          | In a pattern, matches anything                             | [CONSIDER](control-flow/CONSIDER.md)      |
| `_` between digits | Groups digits: `100_000` is 100000                         | [Syntax and directives](syntax/README.md) |

## Terms

| Term                    | Meaning                                                                                                        | Reference                                                |
| ----------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **Regulative rule**     | A rule about behaviour: who MUST, MAY or SHANT do what, by when, and what follows                              | [Regulative rules](regulative/README.md)                 |
| **Constitutive rule**   | A rule that defines, classifies or calculates, written with DECIDE or MEANS                                    | [Functions](functions/README.md)                         |
| **Deontic modality**    | Obligation (MUST), permission (MAY) or prohibition (SHANT/MUST NOT)                                            | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)           |
| **Defeasibility**       | A general rule giving way to an exception ("unless", "notwithstanding"), written with UNLESS or branches       | [UNLESS](operators/UNLESS.md)                            |
| **Mixfix**              | A name with inputs between its words, such as ``borrower `pays` lender``, so a call reads like a sentence      | [Functions](functions/README.md)                         |
| **Isomorphism**         | Code that follows the structure of the legal text, clause for clause                                           | [Concepts](../concepts/README.md)                        |
| **Residual obligation** | What is still owed after some events: the DEONTIC value a `#TRACE` gives                                       | [DEONTIC](regulative/DEONTIC.md)                         |
| **Reparation**          | A further obligation that follows a breach, written in a LEST                                                  | [Deadlines and consequences](regulative/consequences.md) |
| **Clauses**             | A rule written as one line per case, each with values to match in place of its inputs; the first match applies | [DECIDE](functions/DECIDE.md#several-clauses)            |
| **Exhaustiveness**      | Whether the branches of a CONSIDER, or the clauses of a rule, cover every case; L4 warns when they do not      | [CONSIDER](control-flow/CONSIDER.md)                     |
