# Module A4: Production patterns

In this module, you'll learn how to structure a real rulebase so that it stays traceable to its source, easy to test, and ready to deploy.

## Learning Objectives

By the end of this module, you will be able to:

- Organise a rulebase into files and sections that mirror the source text
- Share types between files with `IMPORT`
- Keep tests beside the rules they check, and build test data that is easy to vary
- Isolate a problem quickly
- Get a rulebase ready for deployment

---

## Organizing a Rulebase

### File Structure

Keep the layout simple, and let it follow the instrument you are encoding:

```
charity-rules/
├── README.md              # what these rules encode: which instrument, which version
└── rules/
    ├── shared-types.l4    # DECLAREs used by several files
    ├── registration.l4    # Part 2 of the Law, with its §§ Tests section
    ├── governors.l4       # Part 3, with its §§ Tests section
    └── enforcement.l4     # Part 5: notices and appeals, with its §§ Tests section
```

Guidelines:

- **Mirror the source text.** One file per part of the statute or per contract, named after it, with `§` sections that follow the source's numbering. Every change to the code can then be traced to a clause.
- **Shared vocabulary in one place.** Put the `DECLARE`s that several files need in one file, and `IMPORT` it. A file in the same folder is imported by its name.
- **Tests live with the rules.** Keep each rule's checks in a `§§ Tests` section of the same file, so that a change to a rule and the change to its tests travel together.

[Manage rules in git and CI](../../tutorials/getting-started/version-control-for-rules.md) builds on this layout with commit discipline, review, and a CI check for every change.

### Sharing Types with IMPORT

The shared file holds the vocabulary:

```l4
-- shared-types.l4
§ `Shared types`

DECLARE Person
    HAS `the name` IS A STRING
        `the age` IS A NUMBER
        `bankrupt` IS A BOOLEAN
```

Each rule file imports it by name; a name with a hyphen goes in backticks. (If the shared file lives in another folder, write its path in backticks instead, relative to the file that imports it: ``IMPORT `../shared/shared-types` ``.)

```l4
-- governors.l4
IMPORT `shared-types`

§ `Part 3: Governors`

§§ `Article 19: Who may be a governor`

-- A person may be a governor if they are an adult and not bankrupt.
GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `the person may be a governor` IF
        person's `the age` AT LEAST 18
    AND NOT person's `bankrupt`

§§ `Tests`

`an adult` MEANS Person "Ann" 18 FALSE
`a minor` MEANS Person "Ben" 17 FALSE
`a bankrupt adult` MEANS Person "Cy" 40 TRUE

#ASSERT `the person may be a governor` `an adult`
#ASSERT NOT `the person may be a governor` `a minor`
#ASSERT NOT `the person may be a governor` `a bankrupt adult`
```

`l4 run governors.l4` reports each assertion as satisfied, or tells you which one failed.

---

## Testing a Rulebase

[Test your rules](../../tutorials/getting-started/testing-your-rules.md) covers the testing directives step by step: `#EVAL` to look at a value, `#ASSERT` to state what a value must be, `#CHECK` to confirm a type, and `#TRACE` to run a regulative rule against a timeline. In a real rulebase, three habits matter most:

- **Assert, don't just evaluate.** An `#EVAL` shows a result for you to read; an `#ASSERT` fails the run when the result is wrong, so CI can catch it.
- **Test both sides of every boundary.** For "at least 18", test 17 and 18. For a deadline of 14 days, trace an event on day 14 and one after it.
- **Cover every path of a regulative rule**: compliance, a missed deadline, and each `LEST` fallback.

### Test Data Factory

A function that builds test data from the one value you want to vary keeps boundary tests short:

```l4
DECLARE Person
    HAS `the name` IS A STRING
        `the age` IS A NUMBER
        `bankrupt` IS A BOOLEAN

GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is adult` IF person's `the age` AT LEAST 18

-- Test data factory
GIVEN age IS A NUMBER
GIVETH A Person
`person with age` MEANS Person "Test" age FALSE

-- Boundary tests
#ASSERT NOT `is adult` (`person with age` 17)
#ASSERT `is adult` (`person with age` 18)
#ASSERT `is adult` (`person with age` 19)
```

---

## Debugging Patterns

[Fix errors](../../tutorials/getting-started/debugging-type-errors.md) explains the common error messages and how to fix each one. Two habits help in a large rulebase:

**When in doubt, add parentheses.** A field access passed to a function needs them:

```
length (charity's `the governors`) > 0
all (GIVEN g YIELD g's `the age` >= 18) (charity's `the governors`)
```

**Isolate the failing part.** When a rule gives a surprising answer, evaluate its parts one at a time, starting from the input:

```
#EVAL `the test charity`                                  -- is the input what you think?
#EVAL `the test charity`'s `the governors`                -- is the field right?
#EVAL `the person may be a governor` `the first governor` -- does the helper agree?
```

---

## Getting Ready to Deploy

Rules become API endpoints only when you mark them. Place `@export` directly above a rule to expose it, and add `@desc` to each input so that callers know what it means:

```l4
DECLARE Person
    HAS `the age` IS A NUMBER
        `bankrupt` IS A BOOLEAN

@export Check whether a person is eligible
GIVEN person IS A Person @desc The person to check
GIVETH A BOOLEAN
DECIDE `is eligible` IF
    person's `the age` >= 21
    AND NOT person's `bankrupt`
```

[Deploy your rules](../../tutorials/deploying-rules/exporting-rules-for-deployment.md) takes it from there: deploying from VS Code or the command line, calling the deployed rules over REST, reading the JSON answers, and exposing the rules to AI agents. Test directives such as `#ASSERT` and `#TRACE` stay in the file; deployment ignores them. For calling other services from L4, see [HTTP and JSON](../../reference/builtins/http-json.md).

A self-hosted `jl4-service` serves the same data-plane API from your own host, e.g. `http://localhost:PORT/deployments/{deploymentId}/functions/...`.

Three features matter once a rule is published as a service. [`TYPICALLY`](../../reference/types/TYPICALLY.md) marks a usual answer, so a caller can leave that fact out and the answer says, under `presumed`, that it relied on the default. The [query planner](../../reference/query-planning/README.md), built on a [Reduced Ordered Binary Decision Diagram](../../reference/query-planning/robdd.md), asks the most decisive question first, skips questions that can no longer change the answer, and stops as soon as the outcome is determined, which turns a flat form into a guided interview. And a published rule may decline to answer: when a case falls outside what the encoding covers, the rule gives back a refusal, an outcome of its own that nothing downstream can mistake for a decision. [When a Rule Cannot Answer](../../tutorials/refuse/when-a-rule-cannot-answer.md) shows how to write one, when not to, and how to test that a case does refuse.

### Keep It Fast

- **Prefer library functions to hand-written recursion.** `foldl (GIVEN acc, x YIELD acc + x) 0 xs` from the prelude says what it does and needs no base case.
- **Prefer a formula to a loop** where the law gives one: the sum of 1 to n is `n * (n + 1) / 2`.
- **Keep `#TRACE` scenarios short.** Test a 30-year loan contract with a version of three instalments; the same rule on a short timeline exercises the same paths.

### Deployment Checklist

**Code quality**

- [ ] `l4 check` passes with no errors
- [ ] Every `#ASSERT` is satisfied and every `#TRACE` gives the expected result
- [ ] No missing-case warnings left, or each one is deliberate
- [ ] Sections follow the source, and rules cite the provisions they encode

**Test coverage**

- [ ] Happy path tested
- [ ] Both sides of every boundary tested
- [ ] Every `CONSIDER` branch and every `LEST` fallback reached by a test

**Deployment**

- [ ] Rules marked with `@export`, and every input described with `@desc`
- [ ] The Deploy tab preview shows the expected rules
- [ ] A few calls to the deployed API return the answers your tests expect

---

## Exercise: Test a Rule Thoroughly

Take this eligibility rule: a person qualifies if they are at least 21 years old and not bankrupt. Build a test data factory, assert the results on both sides of the age boundary and for a bankrupt person, and add the total of a list with a prelude fold instead of hand-written recursion.

<details>
<summary>Solution</summary>

```l4
IMPORT prelude

DECLARE Person
    HAS `the name` IS A STRING
        `the age` IS A NUMBER
        `bankrupt` IS A BOOLEAN

GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is eligible` IF
    person's `the age` >= 21
    AND NOT person's `bankrupt`

§§ `Tests`

-- Test data factory
GIVEN age IS A NUMBER
GIVETH A Person
`person with age` MEANS Person "Test" age FALSE

-- Boundary tests
#ASSERT NOT `is eligible` (`person with age` 20)
#ASSERT `is eligible` (`person with age` 21)
#ASSERT `is eligible` (`person with age` 22)
#ASSERT NOT `is eligible` (Person "Bankrupt" 40 TRUE)

-- Prelude fold instead of manual recursion
GIVEN xs IS A LIST OF NUMBER
GIVETH A NUMBER
`total of` MEANS foldl (GIVEN acc, x YIELD acc + x) 0 xs

#ASSERT `total of` (LIST 1, 2, 3) EQUALS 6
```

</details>

---

## Summary

| Area             | Best Practice                                                        |
| ---------------- | -------------------------------------------------------------------- |
| **Organization** | One file per part of the source, `§` sections, shared types IMPORTed |
| **Testing**      | `#ASSERT` in a `§§ Tests` section of each file; test every boundary  |
| **Debugging**    | Isolate with `#EVAL`; add parentheses                                |
| **Deployment**   | `@export` and `@desc`, then deploy to Legalese Cloud                 |
| **Performance**  | Prefer library functions and formulas; keep traces short             |

You have completed the Advanced course. For a specific task, see the [Tutorials](../../tutorials/README.md); for the theory behind L4, [Concepts](../../concepts/README.md).
