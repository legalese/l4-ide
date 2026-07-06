# L4 Language Glossary

Complete reference index of all L4 language features. Links point to the consolidated reference pages which contain detailed documentation.

---

## Keywords

Keywords are reserved words that form the structure of L4 programs.

### Function Keywords

| Keyword                | Purpose                                                              | Reference                          |
| ---------------------- | -------------------------------------------------------------------- | ---------------------------------- |
| **AKA**                | Provides alternate names (aliases)                                   | [AKA](functions/AKA.md)            |
| **DECIDE**             | Defines a decision function                                          | [DECIDE](functions/DECIDE.md)      |
| **FUNCTION**           | Declares a function type                                             | [TYPE-KEYWORDS](types/keywords.md) |
| **GIVEN**              | Introduces function parameters                                       | [GIVEN](functions/GIVEN.md)        |
| **GIVETH** / **GIVES** | Specifies function return type                                       | [GIVETH](functions/GIVETH.md)      |
| **IN**                 | Used with LET for scoped bindings                                    | [LET](functions/LET.md)            |
| **LET**                | Introduces a local binding                                           | [LET](functions/LET.md)            |
| **MEANS**              | Defines the body of a function, decision, or computed field (method) | [MEANS](functions/MEANS.md)        |
| **WHERE**              | Introduces local declarations                                        | [WHERE](functions/WHERE.md)        |
| **YIELD**              | Creates anonymous functions (lambdas)                                | [YIELD](functions/YIELD.md)        |

### Control Flow Keywords

| Keyword       | Purpose                              | Reference                              |
| ------------- | ------------------------------------ | -------------------------------------- |
| **BRANCH**    | Alternative pattern matching keyword | [CONTROL-FLOW](control-flow/README.md) |
| **CONSIDER**  | Pattern matching on values           | [CONSIDER](control-flow/CONSIDER.md)   |
| **ELSE**      | Alternative branch of IF             | [CONTROL-FLOW](control-flow/README.md) |
| **IF**        | Conditional expression               | [IF](control-flow/IF.md)               |
| **THEN**      | Consequent branch of IF              | [CONTROL-FLOW](control-flow/README.md) |
| **OTHERWISE** | Default case in CONSIDER             | [CONTROL-FLOW](control-flow/README.md) |
| **WHEN**      | Introduces a pattern match case      | [CONSIDER](control-flow/CONSIDER.md)   |

### Logical Keywords

| Keyword           | Purpose                    | Reference                       |
| ----------------- | -------------------------- | ------------------------------- |
| **AND** / **...** | Logical conjunction        | [AND](operators/AND.md)         |
| **IMPLIES**       | Logical implication        | [IMPLIES](operators/IMPLIES.md) |
| **NOT**           | Logical negation           | [NOT](operators/NOT.md)         |
| **OR** / **..**   | Logical disjunction        | [OR](operators/OR.md)           |
| **UNLESS**        | Exception clause (AND NOT) | [UNLESS](operators/UNLESS.md)   |

### Comparison Keywords

| Keyword     | Purpose                     | Reference                                      |
| ----------- | --------------------------- | ---------------------------------------------- |
| **ABOVE**   | Synonym for GREATER THAN    | [COMPARISONS](operators/comparisons/README.md) |
| **BELOW**   | Synonym for LESS THAN       | [COMPARISONS](operators/comparisons/README.md) |
| **EQUALS**  | Equality test               | [COMPARISONS](operators/comparisons/README.md) |
| **GREATER** | Greater than comparison     | [COMPARISONS](operators/comparisons/README.md) |
| **LESS**    | Less than comparison        | [COMPARISONS](operators/comparisons/README.md) |
| **THAN**    | Comparison conjunction word | [COMPARISONS](operators/comparisons/README.md) |
| **LEAST**   | Used in "AT LEAST" (≥)      | [COMPARISONS](operators/comparisons/README.md) |
| **MOST**    | Used in "AT MOST" (≤)       | [COMPARISONS](operators/comparisons/README.md) |

### Type Keywords

| Keyword        | Purpose                                                                 | Reference                          |
| -------------- | ----------------------------------------------------------------------- | ---------------------------------- |
| **A** / **AN** | Type articles                                                           | [ARTICLES](types/A-AN.md)          |
| **ASSUME**     | Declares a variable of assumed type                                     | [ASSUME](types/ASSUME.md)          |
| **DECLARE**    | Defines a type                                                          | [DECLARE](types/DECLARE.md)        |
| **IS**         | Type assertion or definition                                            | [TYPE-KEYWORDS](types/keywords.md) |
| **HAS**        | Record field declaration (supports computed fields / methods via MEANS) | [TYPE-KEYWORDS](types/keywords.md) |
| **LIST**       | List type or list literal                                               | [TYPE-KEYWORDS](types/keywords.md) |
| **ONE OF**     | Used for enum types                                                     | [TYPE-KEYWORDS](types/keywords.md) |
| **OF**         | Type application or constructor pattern                                 | [TYPE-KEYWORDS](types/keywords.md) |
| **TYPE**       | The kind of types                                                       | [TYPE-KEYWORDS](types/keywords.md) |
| **WITH**       | Record construction with named fields                                   | [TYPE-KEYWORDS](types/keywords.md) |
| **FOR ALL**    | Universal quantifier for polymorphism                                   | [FOR ALL](types/for-all.md)        |

### Regulative Keywords

For expressing legal obligations, permissions, and prohibitions.

| Keyword       | Purpose                               | Reference                          |
| ------------- | ------------------------------------- | ---------------------------------- |
| **PARTY**     | Declares a legal party                | [PARTY](regulative/PARTY.md)       |
| **MUST**      | Obligation (deontic necessity)        | [MUST](regulative/MUST.md)         |
| **MAY**       | Permission (deontic possibility)      | [MAY](regulative/MAY.md)           |
| **SHANT**     | Prohibition                           | [SHANT](regulative/SHANT.md)       |
| **DO**        | Optionality (deontic possibility)     | [REGULATIVE](regulative/README.md) |
| **DOES**      | Action verb in directive              | [REGULATIVE](regulative/README.md) |
| **EXACTLY**   | Exact value matching on action        | [REGULATIVE](regulative/README.md) |
| **WITHIN**    | Temporal deadline (relative)          | [REGULATIVE](regulative/README.md) |
| **HENCE**     | Consequence on fulfillment            | [REGULATIVE](regulative/README.md) |
| **LEST**      | Consequence on breach                 | [REGULATIVE](regulative/README.md) |
| **BREACH**    | Terminal violation state              | [REGULATIVE](regulative/README.md) |
| **FULFILLED** | Terminal success state                | [REGULATIVE](regulative/README.md) |
| **BECAUSE**   | Justification or reason for breach    | [BECAUSE](regulative/BECAUSE.md)   |
| **PROVIDED**  | Guard condition on action             | [REGULATIVE](regulative/README.md) |
| **AT**        | Temporal specification                | [REGULATIVE](regulative/README.md) |
| **RAND**      | Parallel AND of obligations           | [REGULATIVE](regulative/README.md) |
| **ROR**       | Parallel OR of obligations            | [REGULATIVE](regulative/README.md) |
| **BEFORE**    | Temporal deadline (absolute, planned) | [REGULATIVE](regulative/README.md) |

### Arithmetic Keywords

| Keyword     | Purpose                   | Reference                                    |
| ----------- | ------------------------- | -------------------------------------------- |
| **PLUS**    | Addition                  | [ARITHMETIC](operators/arithmetic/README.md) |
| **MINUS**   | Subtraction               | [ARITHMETIC](operators/arithmetic/README.md) |
| **TIMES**   | Multiplication            | [ARITHMETIC](operators/arithmetic/README.md) |
| **DIVIDED** | Division (use with BY)    | [ARITHMETIC](operators/arithmetic/README.md) |
| **BY**      | Division conjunction word | [ARITHMETIC](operators/arithmetic/README.md) |
| **MODULO**  | Modulus (remainder)       | [ARITHMETIC](operators/arithmetic/README.md) |

### Other Keywords

| Keyword         | Purpose                               | Reference                          |
| --------------- | ------------------------------------- | ---------------------------------- |
| **IMPORT**      | Imports definitions from another file | [IMPORT](libraries/IMPORT.md)      |
| **TIMEZONE IS** | Sets document timezone (IANA name)    | [timezone](libraries/timezone.md)  |
| **TO**          | Function type return separator        | [SYNTAX](syntax/README.md)         |
| **OF**          | Positional argument / type syntax     | [TYPE-KEYWORDS](types/keywords.md) |

---

## Types

L4's type system includes primitive types, algebraic types, and polymorphic types.

For complete documentation, see **[Types Reference](types/README.md)**.

### Primitive Types

| Type         | Description                             |
| ------------ | --------------------------------------- |
| **NUMBER**   | Numeric values (integers and rationals) |
| **STRING**   | Text strings                            |
| **BOOLEAN**  | Truth values (TRUE, FALSE)              |
| **DATE**     | Calendar dates                          |
| **TIME**     | Wall-clock time-of-day (no timezone)    |
| **DATETIME** | Absolute point in time with timezone    |

### Polymorphic Types

| Type       | Description                               |
| ---------- | ----------------------------------------- |
| **LIST**   | Ordered collection of elements            |
| **MAYBE**  | Optional values (JUST x or NOTHING)       |
| **EITHER** | Choice between two values (LEFT or RIGHT) |

### Special Types

| Type         | Description       |
| ------------ | ----------------- |
| **TYPE**     | The kind of types |
| **FUNCTION** | Function types    |

---

## Operators

For complete documentation, see **[Operators Reference](operators/README.md)**.

### Symbolic Operators

| Operator | Textual Form         | Description           |
| -------- | -------------------- | --------------------- |
| `*`      | TIMES                | Multiplication        |
| `+`      | PLUS                 | Addition              |
| `-`      | MINUS                | Subtraction           |
| `/`      | DIVIDED BY           | Division              |
| `>=`     | AT LEAST             | Greater than or equal |
| `<=`     | AT MOST              | Less than or equal    |
| `>`      | GREATER THAN / ABOVE | Greater than          |
| `<`      | LESS THAN / BELOW    | Less than             |
| `=`      | EQUALS               | Equality              |
| `&&`     | AND                  | Logical conjunction   |
| `\|\|`   | OR                   | Logical disjunction   |
| `=>`     | IMPLIES              | Logical implication   |

### List Operators

| Operator        | Description                 |
| --------------- | --------------------------- |
| **FOLLOWED BY** | List cons (prepend element) |
| **EMPTY**       | Empty list                  |

### String Operators

| Operator   | Description                  |
| ---------- | ---------------------------- |
| **CONCAT** | String concatenation         |
| **APPEND** | String concatenation (infix) |

### Temporal Operators

| Operator   | Description              |
| ---------- | ------------------------ |
| **AT**     | Point in time            |
| **WITHIN** | Time duration constraint |

---

## Syntax Patterns

Special syntax features and patterns in L4.

For complete documentation, see **[Syntax Reference](syntax/README.md)**.

| Feature             | Description                                   |
| ------------------- | --------------------------------------------- |
| **Layout Rules**    | Indentation-based grouping                    |
| **Comments**        | `--` line comments and `{- -}` block comments |
| **Identifiers**     | Backtick-quoted identifiers                   |
| **Annotations**     | `@desc`, `@nlg`, `@ref`, `@export`            |
| **Directives**      | `#EVAL`, `#TRACE`, `#CHECK`, `#ASSERT`        |
| **Ditto**           | `^` copy from previous line                   |
| **Asyndetic**       | `...` (AND) and `..` (OR) implicit operators  |
| **Computed Fields** | Derived attributes / methods via MEANS in HAS |
| **Genitive**        | `'s` for record field access                  |
| **Section Markers** | `§` for document sections                     |

---

## Symbols

| Symbol | Name            | Purpose                    |
| ------ | --------------- | -------------------------- |
| `()`   | Parentheses     | Grouping, tuples           |
| `{}`   | Braces          | Block comments             |
| `[]`   | Square brackets | NLG inline annotations     |
| `<<>>` | Double angles   | Reference annotations      |
| `§`    | Section symbol  | Document sections          |
| `^`    | Caret           | Ditto (copy above)         |
| `,`    | Comma           | Separator                  |
| `;`    | Semicolon       | Statement separator        |
| `.`    | Dot             | Decimal point, punctuation |
| `...`  | Ellipsis        | Asyndetic AND              |
| `..`   | Double dot      | Asyndetic OR               |
| `:`    | Colon           | Type signature separator   |
| `%`    | Percent         | Percentage, NLG delimiter  |
| `'s`   | Genitive        | Possession/field access    |

---

## Literals

| Literal Type | Syntax                               | Example                           |
| ------------ | ------------------------------------ | --------------------------------- |
| **Integer**  | Digits                               | `42`, `-17`, `100_000`            |
| **Rational** | Digits with decimal point or percent | `3.14`, `-0.5`, `1_000.5`, `0.3%` |
| **String**   | Double quotes                        | `"hello world"`                   |
| **Boolean**  | TRUE or FALSE                        | `TRUE`, `FALSE`                   |
| **List**     | LIST or FOLLOWED BY                  | `LIST 1, 2, 3`                    |

Numeric literals accept `_` between digits as a visual thousand-separator (`100_000` = `100000`). Underscores must not lead or trail the digit run.

---

## Core Libraries

Libraries shipped with L4.

For complete documentation, see **[Libraries Reference](libraries/README.md)**.

| Library           | Purpose                              |
| ----------------- | ------------------------------------ |
| **prelude**       | Standard functions (always imported) |
| **daydate**       | Date calculations and temporal logic |
| **time**          | Wall-clock time-of-day operations    |
| **datetime**      | Absolute points in time (with tz)    |
| **timezone**      | IANA timezone constants              |
| **actus**         | ACTUS financial contract standards   |
| **excel-date**    | Excel date compatibility             |
| **math**          | Mathematical functions               |
| **currency**      | ISO 4217 currency handling           |
| **legal-persons** | Legal entity types                   |
| **jurisdiction**  | Jurisdiction definitions             |
| **llm**           | LLM API integration                  |

### Built-in Functions

These are built into the compiler (not a library):

#### Type Coercion

| Function       | Purpose             |
| -------------- | ------------------- |
| **TOSTRING**   | Convert to STRING   |
| **TONUMBER**   | Convert to NUMBER   |
| **TODATE**     | Convert to DATE     |
| **TOTIME**     | Convert to TIME     |
| **TODATETIME** | Convert to DATETIME |
| **TRUNC**      | Truncate number     |

See [coercions documentation](types/coercions.md) for details.

#### HTTP and JSON

| Function       | Purpose                      |
| -------------- | ---------------------------- |
| **FETCH**      | HTTP GET request             |
| **POST**       | HTTP POST request            |
| **ENV**        | Read environment variable    |
| **JSONENCODE** | Convert value to JSON string |
| **JSONDECODE** | Parse JSON string to value   |

See [HTTP and JSON documentation](builtins/http-json.md) for details.

---

## Directives

Compiler directives for testing and evaluation.

| Directive    | Purpose                       |
| ------------ | ----------------------------- |
| `#EVAL`      | Evaluate and print expression |
| `#EVALTRACE` | Evaluate with execution trace |
| `#TRACE`     | Contract/state graph tracing  |
| `#CHECK`     | Type check expression         |
| `#ASSERT`    | Assert truth value            |

---

## Annotations

Metadata annotations for documentation and generation.

| Annotation | Purpose                          |
| ---------- | -------------------------------- |
| `@desc`    | Human-readable description       |
| `@nlg`     | Natural language generation hint |
| `@ref`     | Cross-reference to legal source  |
| `@ref-src` | Source reference                 |
| `@ref-map` | Reference mapping                |
| `@export`  | Mark for export                  |

---

## Built-in Constants

| Constant        | Type           | Description                                                   |
| --------------- | -------------- | ------------------------------------------------------------- |
| **TRUE**        | BOOLEAN        | Boolean true value                                            |
| **FALSE**       | BOOLEAN        | Boolean false value                                           |
| **NOTHING**     | MAYBE a        | Absence of value                                              |
| **JUST**        | a → MAYBE a    | Present value constructor                                     |
| **LEFT**        | a → EITHER a b | Left alternative                                              |
| **RIGHT**       | b → EITHER a b | Right alternative                                             |
| **EMPTY**       | LIST a         | Empty list                                                    |
| **TODAY**       | DATE           | Current date (requires `TIMEZONE IS`)                         |
| **NOW**         | DATETIME       | Current date and time (defaults to UTC without `TIMEZONE IS`) |
| **CURRENTTIME** | TIME           | Current local time (requires `TIMEZONE IS`)                   |
| **TIMEZONE**    | STRING         | Document timezone (requires `TIMEZONE IS`)                    |

---

## Concepts

Key concepts in L4 legal modeling, alphabetically ordered.

| Concept | Definition |
| ------- | ---------- |
| **actor (value-actor encoding)** | In a regulative rule, actors are **values** (constructors of one `Actor` sum type) rather than types. Actions carry their actor(s) as ordinary record fields. The contract head `DEONTIC Actor Action` is therefore monomorphic, which lets one contract drive mixed-actor events natively without subtyping or GADTs. See [actors-and-actions.md](../concepts/legal-modeling/actors-and-actions.md). |
| **actor-correctness** | The well-formedness property enforced at compile time: in `PARTY p MUST a` and `PARTY p DOES a`, the party `p` must equal the *performer* of action `a`. Violations produce a diagnostic naming the performer: `` `eat` is performed by `Eater`, not by `Drinker`. `` The check is value-level (complements type-level checks) and is silent when the actor or action cannot be resolved statically. |
| **duplex action** | An action type that carries **both directions** of a bilateral event. The performer is identified by position (the subject-first canon), so the same type covers both `aliceToBob` (performer: Alice) and `bobToAlice` (performer: Bob) without requiring two separate action types. See [actors-and-actions.md §3](../concepts/legal-modeling/actors-and-actions.md). |
| **non-delegable duty** | An obligation that the bound party must discharge personally, modelled by requiring a bare `Perform` action (no `Procure` wrapper) in that obligation slot. Contrast with a delegable duty, which permits a `Procure`-wrapped action. See *procurement* and [actors-and-actions.md §6](../concepts/legal-modeling/actors-and-actions.md). |
| **parameterised action** | An action whose actors are not fixed at definition time but supplied as arguments at the use site. Introduced in a deontic slot with `EXACTLY` (e.g., `PARTY Alice MUST EXACTLY send Alice Bob WITHIN 10`). Without `EXACTLY`, an applied action expression does not parse in the action slot. |
| **performer** | The actor who must carry out an action — the **first actor-typed field in positional order** in the action record (the subject-first canon). For an obligation `PARTY p MUST a`, the compiler checks that `p` equals `a`'s performer. |
| **procurement / Procure** | A higher-order action pattern: `Procure HAS procurer IS AN Actor, inner IS AN Action`. It models "X undertakes to procure that Y performs action_Y" — the outer obligation binds the *procurer*; the inner action retains its own performer. Procurement nests (delegation chains). A stranger cannot procure an instance that already names another procurer; the principal cannot directly perform the inner action either. See [actors-and-actions.md §6](../concepts/legal-modeling/actors-and-actions.md). |
| **subject-first canon** | The positional convention by which the performer of an action is the **first actor-typed field in the record**, mirroring English Subject–Verb–Object order. This makes multi-actor actions duplex and unambiguous without extra type-system machinery. See [ACTOR-ACTIONS-THEORY.md §2](../concepts/legal-modeling/ACTOR-ACTIONS-THEORY.md). |

---

## Navigation

- **[Reference Home](README.md)** - Reference documentation overview
- **[Main Documentation](../README.md)** - Return to docs home
- **[Courses](../courses/README.md)** - Learning paths
- **[Tutorials](../tutorials/README.md)** - Task-oriented guides
- **[Concepts](../concepts/README.md)** - Understanding L4's design
- **[Specifications](https://github.com/legalese/l4-ide/tree/main/specs)** - Technical specifications
