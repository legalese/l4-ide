> **Status (audited 2026-07-03):** PARTIAL — 8 of 11 items done; 3 still open (7, 10, 11).
> - Newly done since this tracker: Item 9 ASSUME Parameter Requirements (PR #893/#780 — ASSUMEs promoted to `@export` params, exposed in decision-service/wizard). Item 4 Boolean Minimization spec moved to `specs/done/` (epic #638); core impl not yet found in `jl4-core/src`.
> - Confirmed done earlier: Items 1, 2/3, 5, 6, 8.
> - Still OPEN: Item 10 TYPICALLY (no `TYPICALLY` in jl4-core; spec still in todo), Item 11 Runtime Input State (blocked on 10), Item 7 Import/Export Coordination (no impl/spec).

# Issue #635 Planning and Implementation Status

Planning session: 2025-11-28
Implementation started: 2025-11-29

## Status Overview

This document tracks both specification writing and implementation progress for Issue #635.

| Item | Description                            | Spec Status   | Spec File                             | Implementation Status         | Notes                                           |
| ---- | -------------------------------------- | ------------- | ------------------------------------- | ----------------------------- | ----------------------------------------------- |
| 1    | Conditional Decision Trace Returns     | ✅ Complete   | `CONDITIONAL-TRACE-SPEC.md`           | ✅ **Done** (commit 131dd4a0) | X-L4-Trace header and ?trace= param implemented |
| 2    | IDE Directive Filtering                | ✅ Complete   | `DECISION-SERVICE-JSONDECODE-SPEC.md` | ✅ **Done** (commit fc320987) | JSONDECODE-based approach, all 18 tests pass    |
| 3    | Enhanced YAML Support (nested objects) | ✅ Complete   | `DECISION-SERVICE-JSONDECODE-SPEC.md` | ✅ **Done** (commit fc320987) | Included in JSONDECODE implementation           |
| 4    | Boolean Minimization                   | ✅ Complete   | `BOOLEAN-MINIMIZATION-SPEC.md`        | ⏳ Todo                       | Larger feature - see Issue #638                 |
| 5    | Dynamic File Management                | ✅ Complete   | See `jl4-websessions/README.md`       | ✅ **Done** (PR #664)         | Auto-push from websessions to decision service  |
| 6    | EXPORT API Syntax                      | ✅ Complete   | `EXPORT-SYNTAX-SPEC.md`               | ✅ **Done** (May 2025)        | All 4 phases implemented                        |
| 7    | Import/Export Coordination             | 📋 Needs spec | -                                     | ⏳ Todo                       | Depends on Item 6 implementation                |
| 8    | Performance Optimization               | ✅ Complete   | `PERFORMANCE-OPTIMIZATION-SPEC.md`    | ✅ **Done**                   | Precompiled modules cached at load time         |
| 9    | ASSUME Parameter Requirements          | 📋 Needs spec | -                                     | ⏳ Todo                       | Can be done independently                       |
| 10   | TYPICALLY Defaults                     | ✅ Complete   | `TYPICALLY-DEFAULTS-SPEC.md`          | ⚠️ **Reverted**               | Initial impl had heisenbug - needs fresh start  |
| 11   | Runtime Input State                    | ✅ Complete   | `RUNTIME-INPUT-STATE-SPEC.md`         | ⚠️ **Blocked**                | Depends on Item 10 (TYPICALLY)                  |

**Legend:**

- ✅ Complete
- 🔄 In Progress / Partially Done
- ⏳ Todo / Not Started
- 📋 Needs Specification
- ⚠️ Reverted / Blocked

## Key Design Decisions

### JSONDECODE-Based Query Injection (Items 2, 3)

Instead of building Haskell AST nodes that get pretty-printed to L4, generate L4 wrapper code that uses `JSONDECODE` to deserialize input JSON directly. This:

- Strips all IDE directives from source
- Handles nested objects automatically via bidirectional type checking
- Eliminates code injection concerns

### EXPORT Syntax (Item 6)

Extend `@desc` annotation with convention-based keywords:

```l4
@desc default export This is the main function
GIVEN x IS A Number @desc The input value
GIVETH A Number
myFunction x MEANS ...
```

Key finding: `@desc` is currently parsed but **never attached** to AST nodes. Phase 1 must fix this attachment.

### Performance (Item 8)

Core insight: `execEvalExprInContextOfModule` already exists and evaluates against pre-compiled modules. The decision service just needs to:

1. Cache `TypeCheckResult` at load time
2. Build `Expr Resolved` directly (not via text concatenation)
3. Call the fast evaluation path

Expected: 10x improvement sequential, 100x for parallel batch.

### Conditional Trace (Item 1)

Add `X-L4-Trace: none | full` header. When `none`:

- Use `#EVAL` instead of `#EVALTRACE`
- Return empty reasoning tree

## Implementation Priority Suggestion

**Completed:**

- ~~Item 1 (Conditional Trace)~~ ✅
- ~~Items 2+3 (JSONDECODE)~~ ✅
- ~~Item 5 (Dynamic File Management)~~ ✅
- ~~Item 6 (EXPORT syntax)~~ ✅
- ~~Item 8 (Performance)~~ ✅

**Remaining (suggested order):**

1. **Item 7 (Import/Export)** - Now unblocked by Item 6
2. **Item 9 (ASSUME)** - Can be done independently
3. **Item 4 (Boolean Minimization)** - Larger project, separate epic
4. **Item 10 (TYPICALLY)** - Needs fresh implementation approach
5. **Item 11 (Runtime Input State)** - After Item 10

## Recent Related PRs

- #664: Websessions-to-decision-service auto-push integration (completes Item 5)
- #662: Selective security vulnerability fixes (build infrastructure)
- #650: SPLIT and CHARAT string primitives
- #649: Push saved programs from websessions to decision service
- #647: Mixfix and postfix notation support
- #644: JSONENCODE, JSONDECODE, FETCH, POST, ENV, CONCAT, AS STRING
