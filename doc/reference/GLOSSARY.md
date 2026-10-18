# Glossary

Every keyword, operator, type, directive and annotation in L4, with a one-line meaning and a link to the page that describes it. Functions are listed under [Built-in functions](builtins/README.md) and [Standard libraries](libraries/README.md).

## Functions

| Keyword                | Meaning                                                                                                                         | Reference                                     |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **DECIDE**             | Defines a value, a function or a rule; one definition or several clauses                                                        | [DECIDE](functions/DECIDE.md)                 |
| **MEANS**              | Gives the body of a function, a value or a computed field                                                                       | [MEANS](functions/MEANS.md)                   |
| **IS**                 | Gives the body after `DECIDE name`; also states a type (`IS A NUMBER`)                                                          | [DECIDE](functions/DECIDE.md)                 |
| **IF** (after DECIDE)  | `DECIDE x IF condition` defines a BOOLEAN                                                                                       | [DECIDE](functions/DECIDE.md)                 |
| **GIVEN**              | Names and types the inputs of one rule or function: a "rule `GIVEN`"                                                            | [GIVEN and GIVETH](functions/GIVEN.md)        |
| **GIVEN** (under a §)  | Declares a name once for a whole section, a "section `GIVEN`": an input every rule in the section reads, supplied for each case | [Section GIVEN](syntax/section-given.md)      |
| **GIVETH** / **GIVES** | States the type of the result                                                                                                   | [GIVEN and GIVETH](functions/GIVEN.md#giveth) |
| **LET** ... **IN**     | Local definitions before an expression                                                                                          | [LET and WHERE](functions/LET.md)             |
| **BE** / **MEAN**      | Alternatives to IS and MEANS in a LET binding                                                                                   | [LET and WHERE](functions/LET.md)             |
| **WHERE**              | Local definitions after an expression                                                                                           | [LET and WHERE](functions/LET.md#where)       |
| **YIELD**              | A function without a name: `GIVEN n YIELD n + 1`                                                                                | [YIELD](functions/YIELD.md)                   |
| **AKA**                | Another name for the same function, value, type or section                                                                      | [AKA](functions/AKA.md)                       |
| Several clauses        | A rule written as one line per case: `DECIDE price Red IS 1`                                                                    | [DECIDE](functions/DECIDE.md#several-clauses) |

## Types

| Keyword                      | Meaning                                                                                                                                                                                                                                                                                                                                                                                       | Reference                       |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| **DECLARE**                  | Defines a new type                                                                                                                                                                                                                                                                                                                                                                            | [DECLARE](types/DECLARE.md)     |
| **HAS**                      | Lists the fields of a record, including computed fields with MEANS                                                                                                                                                                                                                                                                                                                            | [DECLARE](types/DECLARE.md)     |
| **ONE OF**                   | Lists the alternatives of an enumeration                                                                                                                                                                                                                                                                                                                                                      | [DECLARE](types/DECLARE.md)     |
| **IS A** / **IS AN**         | States a type: `age IS A NUMBER`                                                                                                                                                                                                                                                                                                                                                              | [DECLARE](types/DECLARE.md)     |
| **A** / **AN** / **THE**     | Articles before a type name; they do not change the meaning                                                                                                                                                                                                                                                                                                                                   | [DECLARE](types/DECLARE.md)     |
| **OF**                       | Applies a type or a constructor to its arguments: `LIST OF NUMBER`, `PAIR OF x, y`                                                                                                                                                                                                                                                                                                            | [DECLARE](types/DECLARE.md)     |
| **WITH**                     | Builds a record by field name: `Person WITH name IS "Ann"`                                                                                                                                                                                                                                                                                                                                    | [DECLARE](types/DECLARE.md)     |
| **ASSUME**                   | Declares a name and the kind of thing it stands for, without giving it a value. Deprecated 2026-09-04; it still reads, checks and exports as before. A fact to be supplied per case is now a section [`GIVEN`](syntax/section-given.md); a case the model does not cover is now [`REFUSE`](control-flow/REFUSE.md); an uninterpreted type is now [`DECLARE T`](types/DECLARE.md#opaque-types) | [ASSUME](types/ASSUME.md)       |
| **TYPICALLY**                | Default value for a field of a record, for one rule's own input, for a section `GIVEN`, or for an assumed name                                                                                                                                                                                                                                                                                | [TYPICALLY](types/TYPICALLY.md) |
| **TYPE**                     | The type of types, for type inputs: `GIVEN a IS A TYPE`                                                                                                                                                                                                                                                                                                                                       | [FOR ALL](types/for-all.md)     |
| **FOR ALL**                  | Introduces type variables in a type                                                                                                                                                                                                                                                                                                                                                           | [FOR ALL](types/for-all.md)     |
| **FUNCTION FROM** ... **TO** | A function type: `FUNCTION FROM NUMBER TO BOOLEAN`                                                                                                                                                                                                                                                                                                                                            | [Types](types/README.md)        |
| **AS**                       | `x AS STRING` turns a value into text                                                                                                                                                                                                                                                                                                                                                         | [Coercions](types/coercions.md) |

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

| Keyword                          | Meaning                                                                                                                                    | Reference                            |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ |
| **IF** ... **THEN** ... **ELSE** | Chooses between two values                                                                                                                 | [IF](control-flow/IF.md)             |
| **BRANCH**                       | A multi-way conditional: a list of `IF ... THEN` lines and an `OTHERWISE`                                                                  | [BRANCH](control-flow/BRANCH.md)     |
| **CONSIDER**                     | Pattern matching: picks a branch by the shape of a value                                                                                   | [CONSIDER](control-flow/CONSIDER.md) |
| **WHEN**                         | One branch of a CONSIDER                                                                                                                   | [CONSIDER](control-flow/CONSIDER.md) |
| **OTHERWISE**                    | The branch for every remaining case, in CONSIDER and BRANCH                                                                                | [CONSIDER](control-flow/CONSIDER.md) |
| **EXACTLY**                      | In a pattern, matches a given value. In a regulative rule it is deprecated: a name in an action already refers to the thing it names       | [CONSIDER](control-flow/CONSIDER.md) |
| **REFUSE**                       | Declines to answer: this case is outside what the model covers. No later rule can turn a refusal into an answer; only the boundary sees it | [REFUSE](control-flow/REFUSE.md)     |

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

| Keyword              | Meaning                                                                                                                              | Reference                                                         |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- |
| **PARTY**            | Who the rule applies to                                                                                                              | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **MUST**             | Obligation                                                                                                                           | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **MAY**              | Permission                                                                                                                           | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **SHANT / MUST NOT** | Prohibition; the two are synonyms                                                                                                    | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md#shant-and-must-not) |
| **DO**               | The bare form, with no modal word: it behaves as MUST, with the same defaults (`FULFILLED`, `BREACH`) when HENCE or LEST is left out | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)                    |
| **EVERY**            | One obligation per member of a group (`EVERY Tenant t IN tenants`)                                                                   | [EVERY](regulative/EVERY.md)                                      |
| **WHO**              | Narrows the group by a condition naming the member                                                                                   | [EVERY](regulative/EVERY.md)                                      |
| **WHOSE**            | As `WHO`; the first word of each line is a field of the member                                                                       | [EVERY](regulative/EVERY.md)                                      |
| **ONCE ALL HAVE**    | Join line: the continuation fires once, after every member                                                                           | [EVERY](regulative/EVERY.md)                                      |
| **UPON EACH**        | Join line: the continuation fires once per member who acts                                                                           | [EVERY](regulative/EVERY.md)                                      |
| **PROVIDED**         | A condition the action must meet                                                                                                     | [Deadlines and consequences](regulative/consequences.md)          |
| **AFTER**            | The window's opening edge: after a duration, or on a date                                                                            | [AFTER](regulative/AFTER.md)                                      |
| **WITHIN**           | The deadline, the window's closing edge, counted from when the rule starts; `OF` says where it counts from                           | [Deadlines and consequences](regulative/consequences.md)          |
| **BEFORE**           | The deadline as an absolute date: the window closes on that date                                                                     | [AFTER](regulative/AFTER.md)                                      |
| **HENCE**            | What follows when the rule is complied with                                                                                          | [Deadlines and consequences](regulative/consequences.md)          |
| **LEST**             | What follows when it is not                                                                                                          | [Deadlines and consequences](regulative/consequences.md)          |
| **FULFILLED**        | The end state: nothing more is owed                                                                                                  | [Deadlines and consequences](regulative/consequences.md)          |
| **BREACH**           | The end state: a rule was broken; `BREACH BY party BECAUSE reason`                                                                   | [Deadlines and consequences](regulative/consequences.md)          |
| **BY**               | Names the party in `BREACH BY`                                                                                                       | [Deadlines and consequences](regulative/consequences.md)          |
| **RAND**             | Both rules apply at once                                                                                                             | [Deadlines and consequences](regulative/consequences.md)          |
| **ROR**              | Either rule may be complied with                                                                                                     | [Deadlines and consequences](regulative/consequences.md)          |
| **BECAUSE**          | The reason given for a breach                                                                                                        | [BECAUSE](regulative/BECAUSE.md)                                  |
| **DOES**             | In a trace event: `PARTY Seller DOES deliver AT 3`                                                                                   | [EVENT](regulative/EVENT.md)                                      |
| **AT**               | The time of an event, or the start time of a `#TRACE`                                                                                | [EVENT](regulative/EVENT.md)                                      |

## Files and modules

| Keyword         | Meaning                                                                                            | Reference                                        |
| --------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **IMPORT**      | Uses the definitions of another file or a library                                                  | [Standard libraries](libraries/README.md#import) |
| **TIMEZONE IS** | Sets the document's time zone, a name from the Internet Assigned Numbers Authority (IANA) database | [timezone](libraries/timezone.md)                |
| `§`             | Starts a section of the document; `§§` a subsection                                                | [Sections](syntax/sections.md)                   |

## Directives

| Directive         | Meaning                                                                                               | Reference                                            |
| ----------------- | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `#EVAL`           | Evaluates an expression and shows the result                                                          | [Syntax and directives](syntax/README.md#directives) |
| `#EVALTRACE`      | Evaluates and shows each step                                                                         | [Syntax and directives](syntax/README.md#directives) |
| `#CHECK`          | Shows the type of an expression without evaluating it                                                 | [Syntax and directives](syntax/README.md#directives) |
| `#ASSERT`         | Reports an error unless the expression is TRUE                                                        | [Syntax and directives](syntax/README.md#directives) |
| `#ASSERT REFUSED` | Asserts that an expression refuses; add `BECAUSE "..."` to require the refusal message too            | [REFUSE](control-flow/REFUSE.md)                     |
| `#TRACE`          | Runs a regulative rule against events: `#TRACE rule AT 0 WITH ...`; `STARTING AT` is the same as `AT` | [Syntax and directives](syntax/README.md#directives) |

## Annotations

| Annotation             | Meaning                                                                                                                                | Reference                                             |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `@desc`                | A description of a definition, shown in tools and APIs                                                                                 | [Syntax and directives](syntax/README.md#annotations) |
| `@nlg`, `[...]`        | Wording used when a rule is put into natural language                                                                                  | [Syntax and directives](syntax/README.md#annotations) |
| `@ref`, `<<...>>`      | A reference to the legal source                                                                                                        | [Syntax and directives](syntax/README.md#annotations) |
| `@ref-src`, `@ref-map` | Where references are looked up: `@ref-map` maps names to URLs for `@ref`; `@ref-src` is accepted and ignored (CSV loading was removed) | [Syntax and directives](syntax/README.md#annotations) |
| `@export`              | Publishes a function as an API endpoint when the file is deployed                                                                      | [Syntax and directives](syntax/README.md#annotations) |
| `@export default`      | The function a deployment calls when no function is named                                                                              | [Syntax and directives](syntax/README.md#annotations) |

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

| Term                    | Meaning                                                                                                                                                                                                                  | Reference                                                |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| **Regulative rule**     | A rule about behaviour: who MUST, MAY or SHANT do what, by when, and what follows                                                                                                                                        | [Regulative rules](regulative/README.md)                 |
| **Constitutive rule**   | A rule that defines, classifies or calculates, written with DECIDE or MEANS                                                                                                                                              | [Functions](functions/README.md)                         |
| **Deontic modality**    | Obligation (MUST), permission (MAY) or prohibition (SHANT/MUST NOT)                                                                                                                                                      | [PARTY, MUST, MAY, SHANT](regulative/PARTY.md)           |
| **Defeasibility**       | A general rule giving way to an exception ("unless", "notwithstanding"), written with UNLESS or branches                                                                                                                 | [UNLESS](operators/UNLESS.md)                            |
| **Mixfix**              | A name with inputs between its words, such as ``borrower `pays` lender``, so a call reads like a sentence                                                                                                                | [Functions](functions/README.md)                         |
| **Isomorphism**         | Code that follows the structure of the legal text, clause for clause                                                                                                                                                     | [Concepts](../concepts/README.md)                        |
| **Residual obligation** | What is still owed after some events: the DEONTIC value a `#TRACE` gives. On the word's parallel senses in economics and public law, see [Residual: One Word, Three Disciplines](../concepts/legal-modeling/residual.md) | [DEONTIC](regulative/DEONTIC.md)                         |
| **Reparation**          | A further obligation that follows a breach, written in a LEST                                                                                                                                                            | [Deadlines and consequences](regulative/consequences.md) |
| **Clauses**             | A rule written as one line per case, each with values to match in place of its inputs; the first match applies                                                                                                           | [DECIDE](functions/DECIDE.md#several-clauses)            |
| **Exhaustiveness**      | Whether the branches of a CONSIDER, or the clauses of a rule, cover every case; L4 warns when they do not                                                                                                                | [CONSIDER](control-flow/CONSIDER.md)                     |

## Actors and actions

Key concepts in L4 legal modeling, alphabetically ordered. The page [Actors, Actions, and Agreement](../concepts/legal-modeling/actors-and-actions.md) develops them.

| Term                             | Meaning                                                                                                                                                                                                                                                                                                                                                                                                                     | Reference                                                                             |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| **actor (value-actor encoding)** | In a regulative rule, actors are **values** (constructors of one `Actor` sum type) rather than types. Actions carry their actor(s) as ordinary record fields. The contract head `DEONTIC Actor Action` is therefore monomorphic, which lets one contract drive mixed-actor events natively without subtyping or GADTs                                                                                                       | [Actors and actions](../concepts/legal-modeling/actors-and-actions.md)                |
| **actor-correctness**            | The well-formedness property enforced at compile time: in `PARTY p MUST a` and `PARTY p DOES a`, the party `p` must equal the _performer_ of action `a`. Violations produce a diagnostic naming the performer: `` `eat` is performed by `Eater`, not by `Drinker`. `` The check is value-level (complements type-level checks) and is silent when the actor or action cannot be resolved statically                         | [Actors and actions](../concepts/legal-modeling/actors-and-actions.md)                |
| **duplex action**                | An action type that carries **both directions** of a bilateral event. The performer is identified by position (the subject-first canon), so the same type covers both `aliceToBob` (performer: Alice) and `bobToAlice` (performer: Bob) without requiring two separate action types                                                                                                                                         | [Actors and actions, section 3](../concepts/legal-modeling/actors-and-actions.md)     |
| **non-delegable duty**           | An obligation that the bound party must discharge personally, modelled by requiring a bare `Perform` action (no `Procure` wrapper) in that obligation slot. Contrast with a delegable duty, which permits a `Procure`-wrapped action. See _procurement_                                                                                                                                                                     | [Actors and actions, section 6](../concepts/legal-modeling/actors-and-actions.md)     |
| **parameterised action**         | An action whose actors are not fixed at definition time but supplied as arguments at the use site, e.g. `PARTY Alice MUST send Alice Bob WITHIN 10`. (Before the pattern-reference rule shipped, this needed the deprecated `EXACTLY` keyword: `MUST EXACTLY send Alice Bob`.)                                                                                                                                              | [Actors and actions](../concepts/legal-modeling/actors-and-actions.md)                |
| **performer**                    | The actor who must carry out an action: the **first actor-typed field in positional order** in the action record (the subject-first canon). For an obligation `PARTY p MUST a`, the compiler checks that `p` equals `a`'s performer                                                                                                                                                                                         | [Actors and actions](../concepts/legal-modeling/actors-and-actions.md)                |
| **procurement / Procure**        | A higher-order action pattern: `Procure HAS procurer IS AN Actor, inner IS AN Action`. It models "X undertakes to procure that Y performs action Y": the outer obligation binds the _procurer_; the inner action retains its own performer. Procurement nests (delegation chains). A stranger cannot procure an instance that already names another procurer; the principal cannot directly perform the inner action either | [Actors and actions, section 6](../concepts/legal-modeling/actors-and-actions.md)     |
| **subject-first canon**          | The positional convention by which the performer of an action is the **first actor-typed field in the record**, mirroring English Subject-Verb-Object order. This makes multi-actor actions duplex and unambiguous without extra type-system machinery                                                                                                                                                                      | [Actor-actions theory, section 2](../concepts/legal-modeling/ACTOR-ACTIONS-THEORY.md) |
