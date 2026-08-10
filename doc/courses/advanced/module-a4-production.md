# Module A4: Production Patterns

In this module, you'll learn patterns for robust, maintainable L4 code in production environments.

## Learning Objectives

By the end of this module, you will be able to:

- Organize large L4 codebases
- Implement comprehensive testing strategies
- Debug common issues effectively
- Integrate L4 with other systems

---

## Organizing Large Codebases

### File Structure

For substantial legal models, organize files by domain:

```
my-legal-system/
├── types/
│   ├── parties.l4        -- Actor types
│   ├── actions.l4        -- Action types
│   ├── records.l4        -- Data records
│   └── enums.l4          -- Enumerations
├── rules/
│   ├── eligibility.l4    -- Eligibility rules
│   ├── obligations.l4    -- MUST/MAY/SHANT
│   ├── procedures.l4     -- Multi-step procedures
│   └── calculations.l4   -- Computational rules
├── tests/
│   ├── unit/
│   │   ├── eligibility-tests.l4
│   │   └── calculation-tests.l4
│   └── integration/
│       ├── happy-paths.l4
│       └── edge-cases.l4
└── main.l4               -- Main entry point with imports
```

### Using IMPORT

Split code across files and import:

```l4
-- main.l4
IMPORT "types/parties.l4"
IMPORT "types/actions.l4"
IMPORT "rules/eligibility.l4"
IMPORT "rules/obligations.l4"

-- Your main definitions here
```

### Sections for Organization

Within files, use sections:

```l4
§ `Charity Registration System`

§§ `Type Definitions`
-- All DECLARE statements

§§ `Eligibility Rules`
-- All eligibility-related DECIDE statements

§§ `Filing Obligations`
-- All DEONTIC-related rules

§§ `Helper Functions`
-- Utility functions

§§ `Tests`
-- #EVAL and #TRACE statements
```

---

## Testing Strategies

### Unit Tests with #EVAL

Test individual functions:

```l4
§ `Unit Tests`

-- Test helper functions
#EVAL `is adult` (Person "Test" 18)    -- TRUE (boundary)
#EVAL `is adult` (Person "Test" 17)    -- FALSE (below boundary)
#EVAL `is adult` (Person "Test" 100)   -- TRUE (well above)

-- Test calculations
#EVAL `monthly payment` (`Loan Terms` (USD 10000) 0.12 12)
-- Expected: approximately $888.49

-- Test with edge values
#EVAL `monthly payment` (`Loan Terms` (USD 0) 0.12 12)
-- Expected: $0 (no principal)
```

### Integration Tests with #TRACE

Test complete workflows:

```l4
§ `Integration Tests`

§§ `Happy Paths`

-- Complete successful workflow
#TRACE `complete procedure` `the test input` AT 0 WITH
    PARTY Actor1 DOES Action1 AT 5
    PARTY Actor2 DOES Action2 AT 15
    PARTY Actor1 DOES Action3 AT 25
-- Expected: FULFILLED

§§ `Edge Cases`

-- Boundary timing
#TRACE `time-sensitive rule` `the test input` AT 0 WITH
    PARTY Actor1 DOES Action1 AT 14  -- Exactly at deadline
-- Expected: FULFILLED (just in time)

#TRACE `time-sensitive rule` `the test input` AT 0 WITH
    PARTY Actor1 DOES Action1 AT 15  -- One day late
-- Expected: BREACH or enters late path

§§ `Failure Scenarios`

-- Missing required action
#TRACE `required action rule` `the test input` AT 0 WITH
    -- No actions performed
-- Expected: BREACH (timeout)
```

### Test Data Factory

Create reusable test data:

```l4
§ `Test Data Factory`

-- Valid test entities
`a valid person` MEANS Person "Valid Person" 30 FALSE (LIST)
`a valid charity` MEANS `Registered Charity` "Test Charity" "CH999" Active ...

-- Invalid test entities
`an underage person` MEANS Person "Minor" 16 FALSE (LIST)
`a bankrupt person` MEANS Person "Bankrupt" 40 TRUE (LIST)

-- Parameterized test data
GIVEN age IS A NUMBER
GIVETH A Person
`person with age` MEANS Person "Test" age FALSE (LIST)

-- Test: boundary conditions
#EVAL `is adult` (`person with age` 17)   -- FALSE
#EVAL `is adult` (`person with age` 18)   -- TRUE
#EVAL `is adult` (`person with age` 19)   -- TRUE
```

---

## Debugging Patterns

### Common Errors and Fixes

| Error                     | Likely Cause              | Fix                                           |
| ------------------------- | ------------------------- | --------------------------------------------- |
| "Type not in scope"       | Using type before DECLARE | Move DECLARE before use                       |
| "Expected BOOLEAN, got X" | Wrong type in IF          | Check condition returns BOOLEAN               |
| "Not enough arguments"    | Missing function args     | Count parameters in GIVEN                     |
| "Ambiguous parse"         | Missing parentheses       | Add parentheses around expressions            |
| "Unexpected indent"       | Inconsistent spacing      | Use consistent indentation (spaces, not tabs) |

### The Parentheses Rule

When in doubt, add parentheses:

```l4
-- ❌ Ambiguous
length charity's `the governors` > 0

-- ✅ Clear
length (charity's `the governors`) > 0

-- ❌ Ambiguous
all (GIVEN g YIELD g's `the age` >= 18) charity's `the governors`

-- ✅ Clear
all (GIVEN g YIELD g's `the age` >= 18) (charity's `the governors`)
```

### Debug with #EVAL

Isolate problems by evaluating sub-expressions:

```l4
-- Full expression fails
#EVAL `complex function` `the complex input`

-- Debug by breaking apart
#EVAL `the complex input`                           -- Check input is valid
#EVAL `the complex input`'s `the first field`       -- Check field access
#EVAL `helper function` (`the complex input`'s `the first field`)  -- Check helper
```

### Trace Intermediate Values

Use WHERE to name and inspect intermediate values:

```l4
GIVEN x IS A `Some Type`
GIVETH A Result
`debug me` MEANS
    `the final result`
    WHERE
        step1 MEANS `first operation` x
        step2 MEANS `second operation` step1
        step3 MEANS `third operation` step2
        `the final result` MEANS `final operation` step3

-- Debug by evaluating each step
#EVAL step1 WHERE step1 MEANS `first operation` `the test input`
#EVAL step2 WHERE ... -- and so on
```

---

## Integration Patterns

### JSON Input/Output

L4 supports JSON encoding and decoding for integration:

```l4
-- Encode a record to JSON
#EVAL JSONENCODE `my charity`

-- Decode JSON to a record
GIVEN `the JSON string` IS A STRING
GIVETH A MAYBE `Registered Charity`
`parse charity` MEANS JSONDECODE `the JSON string`
```

### Marking Rules for Deployment

Rules become API endpoints only when you mark them. Place `@export` directly
above a rule to expose it, add `@desc` to parameters so API consumers know
what each input means, and use `@export default` for the rule that should be
used when no rule name is specified:

```l4
@export Check whether a person is eligible
GIVEN person IS A Person @desc The person to check
GIVETH A BOOLEAN
DECIDE `is eligible` IF
    person's `the age` >= 21
    AND NOT person's `is bankrupt`
```

### Deploying to Legalese Cloud

Deploy from the VS Code extension: open the **L4 sidebar**, switch to the
**Deploy** tab, review the preview of exported rules, and click **Deploy**.
The extension uploads your file to Legalese Cloud, which compiles it and
serves the exported rules as a REST API:

```bash
# List the functions in a deployment
curl https://api.legalese.cloud/{orgSlug}/{deploymentId}/functions

# Evaluate a function
curl -X POST https://api.legalese.cloud/{orgSlug}/{deploymentId}/functions/is-eligible/evaluation \
  -H "Content-Type: application/json" \
  -d '{"arguments": {"person": {"the-age": 25, "is-bankrupt": false}}}'

# Ask which inputs still affect the outcome (interactive query plans)
curl -X POST https://api.legalese.cloud/{orgSlug}/{deploymentId}/functions/is-eligible/query-plan \
  -H "Content-Type: application/json" \
  -d '{"arguments": {}}'
```

Note the naming: function names in URLs and property names in JSON bodies are
sanitized — spaces become hyphens — so the rule `is eligible` is addressed as
`is-eligible`, and the field `the age` as `the-age`.

AI agents can call the same deployed rules through the built-in MCP server at
`https://mcp.legalese.cloud/{orgSlug}/{deploymentId}`.

> **Self-hosting note:** a self-hosted `jl4-service` serves the same
> data-plane API from your own host, e.g.
> `http://localhost:PORT/deployments/{deploymentId}/functions/...`.

For the complete walkthrough, see
[Exporting Rules for Deployment](../../tutorials/deploying-rules/exporting-rules-for-deployment.md).

### Web Form Generation

L4 can generate web forms from type definitions:

```l4
-- Types become form fields
DECLARE Application
    HAS `the name` IS A STRING          -- Text input
        `the age` IS A NUMBER           -- Number input
        `the status` IS A Status        -- Dropdown
        `the purposes` IS A LIST OF Purpose  -- Multi-select
```

The generated interface is not a static form. For a Boolean-valued decision, L4
drives it with the [query planner](../../reference/query-planning/README.md):
it asks the most decisive question first, skips questions that can no longer
change the answer, and stops as soon as the outcome is determined — turning a
flat form into a guided interview. The planner is built on a
[Reduced Ordered Binary Decision Diagram](../../reference/query-planning/robdd.md).

#### Default values with TYPICALLY

Many facts have a usual answer. Rather than make the user confirm every one, mark
it with [`TYPICALLY`](../../reference/types/TYPICALLY.md) — a _rebuttable
presumption_ attached to a field or parameter:

```l4
DECLARE Party
    HAS name IS A STRING
        `has capacity`   IS A BOOLEAN TYPICALLY TRUE
        `under duress`   IS A BOOLEAN TYPICALLY FALSE
        jurisdiction     IS A STRING  TYPICALLY "Singapore"
```

```l4
GIVEN
  age     IS A NUMBER  TYPICALLY 18
  married IS A BOOLEAN TYPICALLY FALSE
GIVETH A BOOLEAN
DECIDE `may purchase alcohol` IF age >= 18
```

The default is **metadata only** — it does not change how the rule evaluates.
Downstream consumers decide what to do with it: the generator prefills the field,
and the exported JSON schema surfaces it as the `default` keyword. Because a
strongly presumed fact is unlikely to swing the outcome, it is also the natural
per-atom prior the planner can use to push "usually true" questions to the bottom
of the ask-order — see
[question ordering](../../reference/query-planning/README.md#question-ordering).

For the full rules on where `TYPICALLY` may appear and how the default is
type-checked, see the [TYPICALLY reference](../../reference/types/TYPICALLY.md).

---

## Performance Considerations

### Avoid Deep Recursion

L4 uses lazy evaluation but deep recursion can be slow:

```l4
-- ❌ Potentially slow for large n
GIVEN n IS A NUMBER
GIVETH A NUMBER
`sum to n` MEANS
    IF n = 0 THEN 0
    ELSE n + `sum to n` (n - 1)

-- ✅ Better: use formula
`sum to n formula` MEANS n * (n + 1) / 2
```

### Use Prelude Functions

Prefer built-in functions over manual recursion:

```l4
-- ❌ Manual recursion
GIVEN xs IS A LIST OF NUMBER
GIVETH A NUMBER
`my sum` MEANS
    CONSIDER xs
    WHEN EMPTY THEN 0
    WHEN x FOLLOWED BY rest THEN x + `my sum` rest

-- ✅ Use prelude
`my sum` MEANS foldl (GIVEN acc, x YIELD acc + x) 0 xs
```

### Limit Trace Depth

When testing with #TRACE, limit scenario complexity:

```l4
-- ❌ Very long trace (slow)
#TRACE `loan contract` AT 0 WITH
    -- 360 monthly payments...

-- ✅ Test with shorter period
#TRACE `loan contract with` 3 AT 0 WITH  -- 3 payments
    PARTY `the borrower` DOES `pay` AT 30
    PARTY `the borrower` DOES `pay` AT 60
    PARTY `the borrower` DOES `pay` AT 90
```

---

## Deployment Checklist

Before deploying L4 code:

### Code Quality

- [ ] All #EVAL tests pass
- [ ] All #TRACE scenarios work correctly
- [ ] No ambiguous parses or type errors
- [ ] Code is properly sectioned and commented

### Test Coverage

- [ ] Happy path tested
- [ ] Boundary conditions tested
- [ ] Error cases tested
- [ ] All CONSIDER branches have tests

### Documentation

- [ ] Types documented with comments
- [ ] Complex rules explained
- [ ] External references (legislation) cited
- [ ] Examples provided

### Integration

- [ ] Rules marked with `@export` and parameters described with `@desc`
- [ ] Deploy tab preview shows the expected rules
- [ ] Input validation confirmed
- [ ] Error responses defined

---

## Exercise: Test a Rule Thoroughly

Take this eligibility rule: a person qualifies if they are at least 21 years
old and not bankrupt. Build a test data factory, write unit tests covering
both sides of the age boundary, and replace a manual recursion with a prelude
fold.

<details>
<summary>Solution</summary>

```l4
IMPORT prelude

DECLARE Person
    HAS `the name` IS A STRING
        `the age` IS A NUMBER
        `is bankrupt` IS A BOOLEAN

GIVEN person IS A Person
GIVETH A BOOLEAN
DECIDE `is eligible` IF
    person's `the age` >= 21
    AND NOT person's `is bankrupt`

-- Test data factory
GIVEN age IS A NUMBER
GIVETH A Person
`person with age` MEANS Person "Test" age FALSE

-- Boundary tests
#EVAL `is eligible` (`person with age` 20)        -- FALSE (below boundary)
#EVAL `is eligible` (`person with age` 21)        -- TRUE (at boundary)
#EVAL `is eligible` (`person with age` 22)        -- TRUE (above boundary)
#EVAL `is eligible` (Person "Bankrupt" 40 TRUE)   -- FALSE (bankrupt)

-- Prelude fold instead of manual recursion
GIVEN xs IS A LIST OF NUMBER
GIVETH A NUMBER
`total of` MEANS foldl (GIVEN acc, x YIELD acc + x) 0 xs

#EVAL `total of` (LIST 1, 2, 3)   -- 6
```

</details>

---

## Summary

| Area             | Best Practice                                               |
| ---------------- | ----------------------------------------------------------- |
| **Organization** | Split into files by domain, use sections                    |
| **Testing**      | Unit tests (#EVAL), integration tests (#TRACE)              |
| **Debugging**    | Isolate with #EVAL, use parentheses                         |
| **Integration**  | JSON for data exchange, `@export` + Legalese Cloud for APIs |
| **Performance**  | Prefer formulas over recursion, use prelude                 |

---

## Course Complete!

You've finished the Advanced Course. You now know how to:

- Model complete regulatory schemes using the three-layer approach
- Implement cross-cutting concerns (timing, notices, appeals)
- Build complex contracts with recursive obligations
- Organize and test production L4 code

### Continue Learning

- **[Tutorials](../../tutorials/README.md)** - Task-focused guides
- **[Concepts](../../concepts/README.md)** - Theoretical foundations
- **[Reference](../../reference/README.md)** - Complete syntax reference

### Get Help

- **GitHub Issues**: Report bugs or ask questions
- **Example Code**: Study `jl4/examples/legal/` and the `module-a*-examples.l4` files in this course
