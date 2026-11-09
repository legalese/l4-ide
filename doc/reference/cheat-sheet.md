# Cheat sheet

This page is a quick translation guide for developers coming from Python, JavaScript/TypeScript, Java, Haskell, SQL, or other languages. Find the construct you already know in the left columns, then look right for the L4 equivalent.

## Quick Reference Table

| Concept                  | Other Languages                                                   | L4 Equivalent                          | Example                                                |
| ------------------------ | ----------------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------ |
| Struct / class / record  | `class` (Python/Java)<br>`interface` (TS)<br>`data` (Haskell)     | `DECLARE ... HAS`                      | `DECLARE Person HAS name IS A STRING, age IS A NUMBER` |
| Enum / union / variant   | `enum` (Java/TS/Rust)<br>`data` (Haskell)<br>`Union` (Python)     | `DECLARE ... IS ONE OF`                | `DECLARE Color IS ONE OF Red, Green, Blue`             |
| Function definition      | `def` (Python)<br>`function` (JS)<br>`fn` (Rust)<br>`=` (Haskell) | `MEANS` or `DECIDE`                    | `total MEANS x + y`                                    |
| Switch / case / match    | `switch` (JS/Java)<br>`match` (Rust/Python)<br>`case` (Haskell)   | `CONSIDER ... WHEN`                    | `CONSIDER status WHEN Active THEN "ok"`                |
| Multi-way if / cond      | `if/elif` (Python)<br>chained ternary (JS)<br>guards (Haskell)    | `BRANCH`                               | `BRANCH IF x > 0 THEN "pos" OTHERWISE "non-pos"`       |
| If-else / ternary        | `if/else`, `? :` (JS/Java)<br>`if` (Haskell)                      | `IF ... THEN ... ELSE`                 | `IF age >= 18 THEN "adult" ELSE "minor"`               |
| Lambda / arrow function  | `lambda` (Python)<br>`=>` (JS/TS)<br>`\x ->` (Haskell)            | `GIVEN ... YIELD`                      | `GIVEN n YIELD n > 0`                                  |
| Let / const / local var  | `let` (JS/Rust)<br>local var (Python/Java)<br>`let` (Haskell)     | `WHERE` or `LET ... IN`                | `result MEANS x + y WHERE x MEANS 1, y MEANS 2`        |
| Null / nil / None        | `None` (Python)<br>`null` (JS/Java)<br>`Nothing` (Haskell)        | `MAYBE` (`NOTHING` / `JUST`)           | `email IS A MAYBE STRING`                              |
| Null check               | `if x is None` (Python)<br>`x == null` (JS)                       | `CONSIDER ... WHEN NOTHING`            | `CONSIDER val WHEN NOTHING THEN 0 WHEN JUST x THEN x`  |
| Array / list             | `list` (Python)<br>`Array` (JS)<br>`[]` (Haskell)                 | `LIST OF`                              | `scores IS A LIST OF NUMBER`                           |
| List literal             | `[1,2,3]` (Python/JS/Haskell)                                     | `LIST`                                 | `LIST 1, 2, 3`                                         |
| Bullet list (vertical)   | `- x` per line (YAML/Markdown)                                    | `•` at line offside                    | `• 1` / `• 2` per line `== LIST 1, 2` (nests as args)  |
| Empty list               | `[]` (Python/JS/Haskell)                                          | `EMPTY`                                | `CONSIDER xs WHEN EMPTY THEN 0`                        |
| Dot notation / property  | `obj.field` (JS/Python/Java)<br>`^. field` (Haskell lens)         | `'s` (possessive)                      | `person's age`, `company's ceo's name`                 |
| String concatenation     | `+` (JS/Python)<br>`++` (Haskell)<br>`concat` (Java)              | `CONCAT`                               | `CONCAT "Hello, ", name, "!"`                          |
| Modulo / remainder       | `%` (JS/Python/Java)<br>`mod` (Haskell)                           | `MODULO`                               | `n MODULO 2 EQUALS 0`                                  |
| toString / type cast     | `str()` (Python)<br>`String()` (JS)<br>`show` (Haskell)           | `TOSTRING`                             | `TOSTRING 42`                                          |
| map / filter / all / any | `map()`, `filter()` (JS/Python)<br>`map` (Haskell)                | `map`, `filter`, `all`, `any`          | `all (GIVEN n YIELD n > 0) numbers`                    |
| Namespace / module       | `import` (Python/JS)<br>`module` (Haskell)<br>`package` (Java)    | `IMPORT` / `§` sections                | `IMPORT prelude`                                       |
| Equality check           | `==` (JS/Python/Java/Haskell)                                     | `EQUALS` or `=`                        | `x EQUALS 5`                                           |
| Assignment               | `=` (Python/JS)<br>`x = 5` (Java)                                 | None -- use `MEANS`                    | `x MEANS 5`                                            |
| Return statement         | `return` (JS/Python/Java)                                         | None -- expression-based               | Last expression is the result                          |
| Semicolons / braces      | `;` `{}` (JS/Java)<br>`:` (Python)                                | None -- layout-sensitive               | Indentation determines grouping                        |
| Try / catch / exceptions | `try/except` (Python)<br>`try/catch` (JS/Java)                    | None -- use `MAYBE` or `EITHER`        | Errors represented as values                           |
| Comments (single line)   | `#` (Python)<br>`//` (JS/Java)<br>`--` (Haskell/SQL)              | `--`                                   | `-- this is a comment`                                 |
| Comments (multi-line)    | `"""` (Python)<br>`/* */` (JS/Java)<br>`{- -}` (Haskell)          | `{- -}`                                | `{- multi-line comment -}`                             |
| Boolean literals         | `True`/`False` (Python)<br>`true`/`false` (JS/Java)               | `TRUE` / `FALSE`                       | `DECIDE `is valid` IF TRUE`                            |
| Type annotation          | `: int` (Python)<br>`: number` (TS)<br>`:: Int` (Haskell)         | `IS A Type` / `GIVETH A Type`          | `GIVEN x IS A NUMBER GIVETH A BOOLEAN`                 |
| Function call with args  | `f(a, b)` (most languages)<br>`f a b` (Haskell)                   | `f OF a, b` or `f a b`                 | `add OF 3, 4`                                          |
| Arithmetic               | `+`, `-`, `*`, `/` (all languages)                                | `PLUS`, `MINUS`, `TIMES`, `DIVIDED BY` | `capital PLUS capital TIMES rate`                      |

## L4 Has No...

L4 is a pure functional language designed for legal specifications. Several constructs familiar from imperative languages are deliberately absent.

| Missing Construct          | Why                                                                                                                       | What to Use Instead                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Assignment / mutation**  | All values are immutable. No side effects means no hidden state changes, which is critical for auditable legal reasoning. | `MEANS` to bind names to expressions.                                  |
| **Loops** (`for`, `while`) | Iteration implies mutable state.                                                                                          | Recursion, or `map`/`filter`/`all`/`any` from the prelude.             |
| **Null / nil / None**      | The "billion dollar mistake." Missing values must be handled explicitly.                                                  | `MAYBE` type with `NOTHING` and `JUST`. Pattern match with `CONSIDER`. |
| **Exceptions**             | Thrown exceptions break referential transparency and make reasoning about code unreliable.                                | `MAYBE` or `EITHER` types to represent failure as data.                |
| **Semicolons / braces**    | L4 uses layout-sensitive syntax (like Python and Haskell).                                                                | Indentation determines block structure.                                |
| **Implicit coercion**      | No silent type conversions. Types must match explicitly.                                                                  | `TOSTRING` for explicit conversion.                                    |
| **Mutable variables**      | See assignment above. There is no `let x = 1; x = 2`.                                                                     | Each `MEANS` or `WHERE` binding is a permanent definition.             |
| **Return statements**      | Every construct is an expression that produces a value.                                                                   | The last (or only) expression in a definition is its value.            |

These omissions are by design. Legal rules must be deterministic, traceable, and auditable. Pure functional semantics guarantee that the same inputs always produce the same outputs, with no hidden dependencies.

## See Also

- [Glossary](GLOSSARY.md) -- index of all language features
- [Types](types/README.md) -- L4's type system (DECLARE, MAYBE, LIST, etc.)
- [Functions](functions/README.md) -- defining computations (MEANS, DECIDE, GIVEN, GIVETH)
- [Control flow](control-flow/README.md) -- conditionals and pattern matching ([IF](control-flow/IF.md), [BRANCH](control-flow/BRANCH.md), [CONSIDER](control-flow/CONSIDER.md))
- [Operators](operators/README.md) -- arithmetic, comparison, logical, and string operators
- [Syntax and directives](syntax/README.md) -- layout rules, comments, backtick identifiers, annotations
- [Standard libraries](libraries/README.md) -- prelude, daydate, math, and the other standard libraries
