> **Status (re-audited 2026-07-07 against `origin/unstable`):** 9 of 11 tracker items done.
> Both mapped GitHub issues — **#635** ("Critical L4 decision service improvements") and
> **#636** ("Decision service optimization into interpreted/compiled runtime vs incremental
> query") — are resolved on their own actual scope; see below. This document itself stays
> in `todo/` because it also tracks two follow-on items (10, 11) that remain genuinely
> unimplemented, even though neither is required to close #635/#636.
>
> - **Correction to the 2026-07-03 audit:** Item 7 (Import/Export Coordination) is in fact
>   **done**, not open. The 2026-07-03 note was stale. Evidence: `4e1c7cd1` (fixed IMPORT
>   resolution on the precompiled fast path, Nov 2025), `cb05e57d`/`e9b62118` ("Require
>   explicit @export annotations, collect exports from imports", Mar 2026),
>   `jl4-service/src/Compiler.hs:523` `collectAllDeclares` (walks transitive imports),
>   `jl4-lsp/app/LSP/L4/Handlers.hs:849-877` (pre-order walk of the transitive-import tree
>   for `l4/getExportedFunctions`). Issue #635's own checklist already had this item
>   checked off (evidence `4e1c7cd1`) as far back as Dec 2025.
> - **Confirmed done:** Item 9 ASSUME Parameter Requirements — PR
>   [smucclaw/l4-ide#893](https://github.com/smucclaw/l4-ide/pull/893) (merged 2026-04-14)
>   promotes ASSUMEs referenced by an `@export` DECIDE into required caller-supplied
>   parameters (`jl4-core/src/L4/Export.hs`, `doc/reference/types/ASSUME.md`,
>   `jl4-core/test/ExportValidationSpec.hs`). This is a simpler mechanism than the
>   TYPICALLY-based design originally envisioned for this item, and does not depend on
>   Items 10/11.
> - **Confirmed done earlier:** Items 1, 2/3, 5, 6, 8. Item 8 (Performance) /
>   issue #636 is additionally corroborated by the `jl4-service` control-plane/data-plane
>   split (`DeploymentLoader.hs`, `ControlPlane.hs`, `DataPlane.hs`) with async
>   compile-on-first-request and `CompiledModule` caching, plus a live incremental
>   `POST .../query-plan` endpoint (`jl4-service/src/Backend/DecisionQueryPlan.hs`,
>   `jl4-service/src/DataPlane.hs:92`) backed by a real BDD engine in the
>   `jl4-query-plan` package (`L4.Decision.BooleanDecisionQuery`, `L4.Decision.QueryPlan`).
> - **Item 4 (Boolean Minimization):** explicitly deferred by the maintainer to a separate
>   issue, [smucclaw/l4-ide#638](https://github.com/smucclaw/l4-ide/issues/638) ("for
>   consideration" — see issue #635's own checklist), so it does not block closing #635.
>   Noteworthy: the `jl4-query-plan` BDD engine above (elicitation ordering / "don't care"
>   pruning) already implements much of what #638 asks for, but this has not yet been
>   connected back to #638 and #638 remains open — out of scope for this pass.
> - **Still genuinely OPEN (this document's own scope, not required by #635/#636):**
>   Item 10 TYPICALLY Defaults (no `TYPICALLY` keyword anywhere in `jl4-core/src`; its own
>   spec `TYPICALLY-DEFAULTS-SPEC.md` already self-reports "REVERTED"), and Item 11 Runtime
>   Input State (`RUNTIME-INPUT-STATE-SPEC.md` self-reports "BLOCKED", depends on Item 10).
>   Both were exploratory follow-ons discovered during the original planning session, not
>   line items in either GitHub issue's checklist, and superseded — for the purpose that
>   motivated them (Item 9) — by the simpler ASSUME-promotion mechanism above. They remain
>   correctly tracked by their own independent spec files in `specs/todo/`.

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
| 7    | Import/Export Coordination             | 📋 Needs spec | -                                     | ✅ **Done** (commits 4e1c7cd1, cb05e57d) | Transitive-import export/DECLARE collection in jl4-service + jl4-lsp |
| 8    | Performance Optimization               | ✅ Complete   | `PERFORMANCE-OPTIMIZATION-SPEC.md`    | ✅ **Done**                   | Precompiled modules cached at load time; see also issue #636 (control/data-plane split, incremental query-plan endpoint) |
| 9    | ASSUME Parameter Requirements          | 📋 Needs spec | -                                     | ✅ **Done** (PR #893/#780)    | ASSUMEs referenced by `@export` DECIDEs promoted to required params (simpler than TYPICALLY route) |
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

**Completed (re-audited 2026-07-07 against `origin/unstable`):**

- ~~Item 1 (Conditional Trace)~~ ✅
- ~~Items 2+3 (JSONDECODE)~~ ✅
- ~~Item 5 (Dynamic File Management)~~ ✅
- ~~Item 6 (EXPORT syntax)~~ ✅
- ~~Item 7 (Import/Export Coordination)~~ ✅ (4e1c7cd1, cb05e57d/e9b62118)
- ~~Item 8 (Performance)~~ ✅ (also resolves issue #636)
- ~~Item 9 (ASSUME)~~ ✅ (PR #893/#780)

**Remaining — out of scope for issues #635/#636, tracked independently:**

1. **Item 4 (Boolean Minimization)** — deferred by the maintainer to issue #638; not
   required to close #635. (A BDD-based query-plan engine already exists in
   `jl4-query-plan`/`jl4-service/src/Backend/DecisionQueryPlan.hs` and partially overlaps
   with #638's ask, but has not been connected back to that issue.)
2. **Item 10 (TYPICALLY)** — reverted (heisenbug); needs fresh implementation approach.
   Not a line item of #635/#636; see `TYPICALLY-DEFAULTS-SPEC.md`.
3. **Item 11 (Runtime Input State)** — blocked on Item 10. Not a line item of #635/#636;
   see `RUNTIME-INPUT-STATE-SPEC.md`.

## Recent Related PRs

- #664: Websessions-to-decision-service auto-push integration (completes Item 5)
- #662: Selective security vulnerability fixes (build infrastructure)
- #650: SPLIT and CHARAT string primitives
- #649: Push saved programs from websessions to decision service
- #647: Mixfix and postfix notation support
- #644: JSONENCODE, JSONDECODE, FETCH, POST, ENV, CONCAT, AS STRING
