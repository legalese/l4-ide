# Diagnostic codes

Every diagnostic `jl4-lsp` reports has a stable string code in the LSP `code` field, so tools never need to match on message text. `jl4-lsp-test` checks this list against the source.

**A code is API.** It is a descriptive slug, `area/what-happened`, not a number. A code is not renamed casually and is never reused for something else, even after its diagnostic is gone. Rewording a message does not change its code. A code never contains anything the user wrote.

The area says what kind of finding it is, not which stage reported it: a warning from the type checker has a `lint/` code and the source `check`.

Each diagnostic also has a `codeDescription` whose `href` comes from one formula, with no table:

```text
https://legalese.com/l4/reference/errors#<code with / replaced by ->
```

`check/unknown-identifier` links to `...#check-unknown-identifier`. Entries of the [error reference](../doc/reference/errors/README.md) take a code through an explicit anchor. A code with no entry links to the top of that page.

## Seeing a code from the command line

`l4` prints each diagnostic as a block on stderr, with the code on its own line, indented two spaces:

```text
File:     example.l4
  Hidden:   no
  Range:    2:11-2:11
  Source:   parser
  Severity: DiagnosticSeverity_Error
  Code:     parse/unexpected-plus
  Message:
```

Match it with `^\s*Code:\s+(\S+)$`.

- `l4 check` shows `parse/`, `check/`, `lint/`, `import/`, `file/` and `internal/` codes. It does not evaluate, so it shows no `eval/` codes.
- `l4 run` also shows `eval/` codes, including those of passing directives.
- `l4 check --json` has the same blocks as strings in `diagnostics`.

## parse/

| Code                      | Meaning                                                                  |
| ------------------------- | ------------------------------------------------------------------------ |
| `parse/indentation`       | A token is not indented as the construct it is in requires.              |
| `parse/unexpected-<kind>` | A token of this kind cannot come here, see below.                        |
| `parse/syntax-error`      | Any other syntax error, including a character that cannot start a token. |

`<kind>` is one of:

- A keyword, spelled as the language spells it, such as `parse/unexpected-WITH`: `A`, `ABOVE`, `AKA`, `ALL`, `AN`, `AND`, `AS`, `ASSUME`, `AT`, `BE`, `BECAUSE`, `BELOW`, `BRANCH`, `BREACH`, `BY`, `CONCAT`, `CONSIDER`, `DECIDE`, `DECLARE`, `DIVIDED`, `DO`, `DOES`, `ELSE`, `ENV`, `EQUALS`, `EXACTLY`, `FETCH`, `FOLLOWED`, `FOR`, `FROM`, `FUNCTION`, `GIVEN`, `GIVES`, `GIVETH`, `GREATER`, `HAS`, `HENCE`, `IF`, `IMPLIES`, `IMPORT`, `IN`, `IS`, `LEAST`, `LESS`, `LEST`, `LET`, `LIST`, `MAY`, `MEAN`, `MEANS`, `MINUS`, `MODULO`, `MOST`, `MUST`, `NOT`, `OF`, `ONE`, `OR`, `OTHERWISE`, `PARTY`, `PLUS`, `POST`, `PROVIDED`, `RAND`, `ROR`, `SHANT`, `STARTING`, `THAN`, `THE`, `THEN`, `TIMES`, `TO`, `TYPE`, `UNLESS`, `WHEN`, `WHERE`, `WITH`, `WITHIN`, `YIELD`.
- One of these words:
  - values: `identifier`, `number`, `string`, `genitive` (`'s`);
  - layout and the rest: `annotation`, `caret`, `comment`, `directive`, `end-of-input`, `symbol`, `whitespace`;
  - punctuation: `close-brace`, `close-bracket`, `close-paren`, `colon`, `comma`, `dot`, `ellipsis`, `ellipsis-or`, `open-brace`, `open-bracket`, `open-paren`, `percent`, `ref-close`, `ref-open`, `section-sign`, `semicolon`;
  - operators: `and`, `divided-by`, `double-equals`, `equals`, `greater-equals`, `greater-than`, `implies`, `less-equals`, `less-than`, `minus`, `not-equals`, `or`, `plus`, `times`.

## check/

| Code                                 | Meaning                                                            |
| ------------------------------------ | ------------------------------------------------------------------ |
| `check/ambiguous-identifier`         | Several definitions fit this name, and none can be chosen.         |
| `check/ambiguous-operator`           | Several types fit this operator, and none can be chosen.           |
| `check/ambiguous-type`               | Several types have this name, and none can be chosen.              |
| `check/clause-pattern-count`         | Clauses have another number of patterns than the GIVEN has inputs. |
| `check/cyclic-computed-fields`       | Computed fields depend on each other in a ring.                    |
| `check/cyclic-type-synonyms`         | Type synonyms refer to each other in a ring.                       |
| `check/duplicate-name`               | A name occurs twice where names must be distinct.                  |
| `check/export-clauses-without-given` | An `@export` of clauses with no GIVEN.                             |
| `check/export-event-type`            | An `@export` takes or returns an EVENT.                            |
| `check/export-function-input`        | An `@export` has an input of a function type.                      |
| `check/internal-error`               | A bug in the checker.                                              |
| `check/invalid-type-parameter`       | A parameter of a type declaration is not of type TYPE.             |
| `check/missing-named-arguments`      | A call with named arguments leaves some out.                       |
| `check/mixfix-mismatch`              | An expression does not match the mixfix form of a rule.            |
| `check/name-not-in-definition`       | A name in the signature is not in the definition.                  |
| `check/name-not-in-signature`        | A name in the definition is not in the signature.                  |
| `check/not-a-function`               | Something that is not a function is applied to arguments.          |
| `check/result`                       | The answer to a `#CHECK`. Severity Information.                    |
| `check/supplied-computed-field`      | A record constructor supplies a computed field.                    |
| `check/type-mismatch`                | A value has another type than the place it is in requires.         |
| `check/type-synonym-chain-too-long`  | A chain of type synonyms is too long to follow.                    |
| `check/unknown-identifier`           | Nothing in scope defines this name.                                |
| `check/wrong-argument-count`         | A function is applied to the wrong number of arguments.            |
| `check/wrong-type-argument-count`    | A type is applied to the wrong number of arguments.                |

## lint/

Warnings, except `lint/redundant-lang-en`, which is a hint.

| Code                               | Source   | Meaning                                                     |
| ---------------------------------- | -------- | ----------------------------------------------------------- |
| `lint/ambiguous-nlg`               | `parser` | Two `@nlg` in one language on one name.                     |
| `lint/and-or-same-indentation`     | `linter` | AND and OR at one indentation.                              |
| `lint/annotation-not-attached`     | `parser` | An `@nlg` attached to nothing.                              |
| `lint/annotation-without-location` | `parser` | An annotation with no source location: a bug.               |
| `lint/clause-arity-changed`        | `check`  | A definition after clauses that is not another clause.      |
| `lint/empty-nlg`                   | `parser` | An `@nlg` with no text.                                     |
| `lint/lang-overridden`             | `parser` | A `@lang` line that a later one overrides.                  |
| `lint/lone-lang-tag`               | `parser` | An `@nlg` tag that nothing else in the module backs.        |
| `lint/misplaced-clause-annotation` | `check`  | An annotation above a later clause.                         |
| `lint/non-exhaustive-clauses`      | `check`  | A multi-clause definition does not cover all cases.         |
| `lint/non-exhaustive-match`        | `check`  | A CONSIDER does not cover all cases.                        |
| `lint/redundant-branch`            | `check`  | A CONSIDER branch that is never reached.                    |
| `lint/redundant-lang-en`           | `linter` | A `@lang en` line that can go.                              |
| `lint/ref-after-code`              | `parser` | A `@ref` after code on its line, with nothing following it. |
| `lint/ref-not-attached`            | `parser` | A `@ref` with nothing after it to attach to.                |
| `lint/spaced-nlg-slot`             | `parser` | A `% name %` slot with spaces, which prints as plain text.  |
| `lint/unreachable-clause`          | `check`  | A clause that is never used.                                |

## eval/

Severity Information for `eval/result` and `eval/assertion-passed`, Error for the rest. An `#ASSERT` that raises has the code of what it raised, not `eval/assertion-failed`.

| Code                           | Meaning                                                     |
| ------------------------------ | ----------------------------------------------------------- |
| `eval/assertion-failed`        | An `#ASSERT` evaluated to FALSE.                            |
| `eval/assertion-passed`        | An `#ASSERT` evaluated to TRUE.                             |
| `eval/division-by-zero`        | A division by zero.                                         |
| `eval/infinite-loop`           | A value defined in terms of itself.                         |
| `eval/internal-error`          | A bug in the evaluator.                                     |
| `eval/non-exhaustive-patterns` | No branch or clause matched a value at run time.            |
| `eval/not-an-integer`          | An operation that needs integers got something else.        |
| `eval/result`                  | The result of a directive.                                  |
| `eval/stack-overflow`          | Evaluation went too deep.                                   |
| `eval/stuck`                   | Evaluation needs the value of an ASSUME'd term.             |
| `eval/unsupported-equality`    | Equality on values that do not support it.                  |
| `eval/user-error`              | A user-facing evaluation error, such as a missing TIMEZONE. |

## import/

| Code                       | Meaning                                                                                                                                        |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `import/cycle`             | Files import each other in a ring.                                                                                                             |
| `import/module-has-errors` | An imported module has errors, or could not be checked.                                                                                        |
| `import/module-not-found`  | No module has this name.                                                                                                                       |
| `import/self-import`       | A file imports itself.                                                                                                                         |
| `import/self-dependency`   | Walking the files that depend on this one came back to it. A file that imports itself does that, and so does an `IMPORT` that finds no module. |

## file/

| Code              | Meaning                                     |
| ----------------- | ------------------------------------------- |
| `file/io-error`   | Reading a file failed.                      |
| `file/not-found`  | The file does not exist.                    |
| `file/unreadable` | The contents of the file are not available. |

## internal/

Bugs in the server, to report, not to fix in the document.

| Code                         | Meaning                                   |
| ---------------------------- | ----------------------------------------- |
| `internal/exactprint-failed` | The file could not be printed back.       |
| `internal/rule-exception`    | A compile step stopped with an exception. |
