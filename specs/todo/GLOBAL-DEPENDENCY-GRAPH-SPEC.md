# Specification: Global Dependency Graph

## Motivation

The computed fields implementation (see `COMPUTED-FIELDS-SPEC.md`, "Cross-Record Cycles") revealed that L4 lacks a global dependency graph. Intra-record cycles between computed fields are caught at compile time, but cross-record cycles through top-level bindings are only caught at runtime by the lazy evaluator's blackhole detection. A global dependency graph would close this gap and enable several other analyses.

## Goals

A single global dependency graph supports three analyses:

1. **Cross-record cycle detection** — find strongly connected components involving computed fields across multiple DECLARE blocks and top-level DECIDE/MEANS definitions
2. **Dead code identification** — flag definitions that are unreachable from any entry point (LSP warning, not a hard error)
3. **Tree-shaking** — prune unreachable definitions from compilation output (JSON schema, decision service, web app generation)

All three are different queries over the same graph.

## Graph Structure

### Nodes

Every named definition is a node:

| Node kind             | Source                                                              |
| --------------------- | ------------------------------------------------------------------- |
| Top-level function    | `DECIDE f ...` / `MEANS` at top level                               |
| Computed field        | `DECLARE R HAS f IS A T MEANS expr` (desugared to synthetic DECIDE) |
| Stored field selector | `DECLARE R HAS f IS A T`                                            |
| Type constructor      | `DECLARE R HAS ...` / `DECLARE E IS ONE OF ...`                     |
| ASSUME parameter      | `ASSUME x IS A T`                                                   |

### Edges

A directed edge `A → B` means "evaluating A may require evaluating B":

| Edge source          | Edge target          | How to detect                                                                         |
| -------------------- | -------------------- | ------------------------------------------------------------------------------------- |
| Function body        | Variable reference   | `Var`/`App` nodes in the expression                                                   |
| Function body        | Field projection     | `Proj _ expr field` — edge to the selector `field` AND to whatever `expr` resolves to |
| Computed field MEANS | Sibling field        | Bare name reference (already detected by `exprFieldRefs`)                             |
| Computed field MEANS | Top-level definition | `Var`/`App` referencing a global name                                                 |
| Computed field MEANS | Nested projection    | `expr's field` chains                                                                 |

### Entry Points

Entry points are the roots for reachability analysis:

- `#EVAL` directives
- `#CHECK` directives
- Exported functions (decision service API)
- Contract directives

## Analysis Passes

### Pass 1: Build the Graph

Walk the full resolved AST (post-type-checking, so names are resolved to unique IDs). For each definition, collect its free-variable references as outgoing edges.

**Timing:** After type checking, before evaluation. The resolved AST has unique IDs on every name, eliminating ambiguity.

**Key insight:** This must run on the **resolved** AST (after type checking), not the parsed AST, because name resolution is needed to distinguish between local bindings and global references. The intra-record cycle detection in `Desugar.hs` works on the parsed AST because it only needs to match sibling field names, but the global graph needs fully resolved names.

### Pass 2: Cycle Detection

Run Tarjan's algorithm (or `Data.Graph.stronglyConnComp`) on the graph. Any SCC with more than one node, or a single node with a self-edge, is a cycle.

Report cycles involving at least one computed field as errors. Cycles involving only top-level functions are already possible in L4 (mutual recursion is valid) — only flag cycles that pass through computed fields, since those indicate non-terminating derived attributes.

That stays true after the scope ruling (ii): the checker for cycles of rules gives no warning on a cycle of functions, and lists it only in its report; see [Cycles of rules: rulings L3, L4 and the scope ruling](#cycles-of-rules-rulings-l3-l4-and-the-scope-ruling).

**Open question:** Should mutual recursion between top-level functions that happens to pass through a computed field projection always be an error? Or only when the cycle is "tight" (every node in the SCC is a computed field)?

### Pass 3: Reachability / Dead Code

Starting from entry points, compute the reachable set (BFS/DFS). Definitions not in the reachable set are dead code.

**Severity:** Warning, not error. Dead code may be intentional (library definitions, work in progress).

**LSP integration:** Grey out unreachable definitions. Offer "Remove unused definition" quick fix.

### Pass 4: Tree-Shaking (Optional)

For compilation targets that benefit from smaller output (JSON schema, web app generation), include only the reachable set. This is a straightforward filter once reachability is computed.

## Implementation Sketch

### Data Types

```haskell
-- | A node in the global dependency graph.
data DepNode
  = DepFunction Unique        -- top-level DECIDE/MEANS
  | DepComputedField Unique   -- computed field (synthetic DECIDE)
  | DepSelector Unique        -- stored field selector
  | DepConstructor Unique     -- type constructor
  | DepAssume Unique          -- ASSUME parameter
  deriving (Eq, Ord)

-- | The global dependency graph.
type DepGraph = Map DepNode (Set DepNode)
```

### Where It Lives

New module `L4.DependencyGraph` in `jl4-core`. Depends on the resolved AST (`Module Resolved`) and the entity info from type checking.

### Integration Points

| Caller                                            | Purpose                                                                        |
| ------------------------------------------------- | ------------------------------------------------------------------------------ |
| `TypeCheck.hs` / `doCheckProgramWithDependencies` | Run cycle detection after type checking; emit errors for computed-field cycles |
| `jl4-lsp` / LSP Rules                             | Dead code warnings, grey-out unreachable definitions                           |
| `JsonSchema.hs`                                   | Tree-shake definitions not reachable from exported functions                   |
| `EvaluateLazy`                                    | Potentially skip evaluation of unreachable definitions                         |

## Relation to Existing Code

- **`Desugar.hs:detectComputedFieldCycles`** — the intra-record cycle detection would remain as a fast, early check (runs before type checking on the parsed AST). The global graph is a more expensive check that runs after type checking and subsumes it for cross-record cases.
- **`Desugar.hs:exprFieldRefs`** — the `Foldable`-based name extraction could be reused or generalized for the global graph builder.
- **`EvaluateLazy/Machine.hs` blackhole detection** — remains as a runtime safety net. Even with compile-time detection, the blackhole mechanism catches cycles that arise from dynamic dispatch or patterns the static analysis is too conservative to prove safe.

## Estimated Scope

| Component                                    | Effort                                        |
| -------------------------------------------- | --------------------------------------------- |
| `L4.DependencyGraph` module (graph building) | Medium — walk resolved AST, collect edges     |
| Cycle detection (cross-record)               | Small — `stronglyConnComp` on the built graph |
| Dead code warnings                           | Small — BFS from entry points                 |
| LSP integration (grey-out)                   | Medium — wire into diagnostics                |
| Tree-shaking for JSON schema                 | Small — filter by reachable set               |

## Cycles of rules: rulings L3, L4 and the scope ruling

Status, 2026-11-22: proposed, not landed: this branch must not merge before `fix/runaway-lest-1075` lands L2's run-time stop, because ruling L3 ships only "after card L2’s run-time stop exists" (below).
It is built on `feat/cycle-report-1075`, which is not merged.
This is not the computed-field pass sketched above.
`L4.Cycles` (`jl4-core/src/L4/Cycles.hs`) finds the cycles among one module's definitions, top level and `WHERE`/`LET` alike, and asks of each whether it comes to an end, not only whether it exists (smucclaw/l4-ide#1075).
Its warnings are raised in `doCheckProgramWithDependencies` (`jl4-core/src/L4/TypeCheck.hs`), only on a module with no error; their text is in `jl4-core/src/L4/Cycles/Warning.hs`.
The page for a first-time reader is `doc/reference/regulative/rules-that-start-themselves-again.md`.

**"Multiplies" is a warning nobody can silence.**
Card L3: option A, accepted by Meng on 2026-11-20 at 22:49:58Z, with no note; bench "Recursion Limits", https://claude.ai/artifact/GaRTioL8pgDR5sHbEe8fKY (collection `l4-recursion-1120`); printed: "Accept option A. A warning with its own text that cannot be silenced; it names the rule and the operator that starts two copies, and says whether the growth is per missed deadline or bounded by a countdown." "Conditions: it ships only after the report-only pass over every tracked `.l4` file and after card L2’s run-time stop exists; each shape it fires on has a positive and a negative fixture."

- The report-only pass: met.
  It was measured before the scope ruling was given: 67 warnings and 23 goldens moved with every cycle in scope, against 2 and 3 with obligation cycles only.
  The 2 are "could not check" warnings; the third golden moves for a "no time" warning, which the scope ruling left as it was.
  Re-measured on this branch on 2026-11-21: all 1,602 tracked `.l4` files checked with the binary before and after, with identical exit codes and cycle warnings in exactly three files, none of them "multiplies".
- L2's run-time stop: **not met on this branch.**
  It is on `fix/runaway-lest-1075`, which has not landed in `unstable` (`git merge-base --is-ancestor` says so, 2026-11-21), so this branch must not merge before it.
- The fixtures: met.
  `jl4/examples/ok/cycles/` has a file for each warning a cycle of rules can draw, `multiplies.l4`, `no-time.l4` and `could-not-check.l4`, each with rules that draw it beside rules of the same shape that do not, and `marks.l4`, with an `@ends-because` above rules where it changes nothing.
  Their goldens pin the text of each warning and each note.
  `jl4-core/test/CyclesSpec.hs`, "an obligation cycle draws its alarms", has a positive and a negative case for each shape "multiplies" fires on: a `LEST`, the #1075 shape over two rules, a `HENCE`, a countdown, a barrier's `HENCE` and a `RECORD`'s `HENCE`.

**`@ends-because` silences "could not check", and nothing else.**
Card L4: accepted by Meng on 2026-11-20 at 22:50:17Z, with no note on the mark; bench "Recursion Limits", https://claude.ai/artifact/GaRTioL8pgDR5sHbEe8fKY (collection `l4-recursion-1120`); printed: "Accept, in principle now, built after the report-only count. One annotation, its name your choice (`@ends-because` suggested), with a mandatory reason." "Conditions: it silences only “could not check”, never “multiplies” or “no time”; only for the cycle containing the annotated definition, written on the definition the warning is reported on; each use emits one information-level message carrying its reason; no effect on runtime limits; the ruling is recorded in `GLOBAL-DEPENDENCY-GRAPH-SPEC.md`."

The name, as Meng wrote at 2026-11-20T22:55:57Z: "`@ends-because` sounds fine to me. Note an archaic alternative could have been `@determines` from contract language but we should probably resist the temptation."
So `@determines` was considered and declined; it is not an alias, and nothing reads it.

- "only for the cycle containing the annotated definition, written on the definition the warning is reported on": a cycle's "could not check" warning is reported on its first member in source order, and only a mark there silences it.
  Which member that is was decided by Claude 2026-11-22, pending Meng's review: the printed condition says only "the definition the warning is reported on".
  A mark above another member does not count, and the warning names that mark and says where it goes.
- "never "multiplies" or "no time"": both still fire under a mark, and when one of the cycle's members carries a mark, their text says that `@ends-because` does not silence them.
  "Multiplies" is reported on the member whose `HENCE` or `LEST` starts the copies, and names it.
- "each use emits one information-level message carrying its reason": every mark the checker accepts emits one, at the mark, saying what the mark did.
  It silenced the warning; it did not count, because the warning is shown on another definition; it could not silence "no time" or "multiplies"; or it changed nothing, on a cycle of functions, on a cycle L4 can see ends, or on no cycle L4 can see (`MarkOutcome`, `jl4-core/src/L4/Cycles/Warning.hs`).
  Reading "each use" as every mark, and not only one that silences a warning, follows the printed condition literally ('each use emits one information-level message'). The narrow reading is the alternative, for Meng's review (keeping the literal reading was decided by Claude 2026-11-22; the commit that builds it lists what the narrow reading would move).
  A mark the checker refuses is an error and emits nothing.
  There are two exceptions.
  A module with any error gets no cycle warnings and no notes at all; an exception decided by Claude 2026-11-21, pending Meng's review, so `jl4/examples/not-ok/tc/ends-because-misplaced.l4` has two accepted marks and no note.
  And of two marks stacked above one definition, the parser keeps the closer one and warns about the other, which emits no note (decided by Claude 2026-11-22, pending Meng's review).
- A mark above a definition L4 finds no way back to itself from also draws a warning that it sees nothing for the mark to explain, beside its note (decided by Claude 2026-11-22, pending Meng's review).
  L4 cannot see a cycle through a rule kept in a record or passed in as an input, so the warning says that the mark may still be right.
- "no effect on runtime limits": met.
  Nothing under `L4.Evaluate*` reads the mark (`git grep annEndsBecause -- 'jl4-core/src/L4/Evaluate*'` finds nothing, 2026-11-22).
- The printer keeps the mark through a re-print (`L4.Print`), and the evaluation differential of `CLAUDE.md` §3.2.1 found no change of meaning (2026-11-21): 481 round-trip files ran on both sides, 323 of them with `Result:` blocks, 6,784 per side; 321 are byte-identical, and the other 2 differ only in a file name inside a `Result:` body; `ok/ends-because-basic.l4` keeps its 4 marks and its 4 notes.

**The scope ruling (ii): a cycle of functions draws no warning.**
Answer (ii), given by Meng on 2026-11-21 at 09:03:09Z, with no note, as written: "RULING (ii) on the cycle checker's scope: the "could not check" warning fires only on obligation cycles (HENCE/LEST loops), not on plain function recursion; "multiplies" and "no time" unchanged; @ends-because still silences "could not check" on its own cycle." The same ruling: "function recursion stays in the report-only pass and is stopped at run time by L2's counts".

- Built in `L4.Cycles.alarms`, which returns no alarm for a `FunctionCycle`, so the checker and the report (`findingJSON`, written by `JL4_CYCLE_REPORT`) agree; the report still lists every cycle of functions.
- Guarded by tests: with that line removed (2026-11-21), four `jl4-core-test` cases fail (the three under "a function cycle draws no warning", and the note on a function cycle), and so do 21 `jl4-test` goldens: 20 that would gain a warning, three of them under `jl4/examples/canon/`, which with the three above make (i)'s 23, and `ok/ends-because-basic`, whose notes change.
- "stopped at run time by L2's counts": **not true on this branch.**
  The counts are on `fix/runaway-lest-1075`, not landed.
  Until they land, a function that calls itself forever without a blackhole keeps running, as `doc/reference/errors/README.md` ("Infinite loop detected") says.
- No warning text names a limit, a number of steps or a flag, since L2's are not on this branch.
- A mixed cycle, a rule that uses itself directly and also has a `HENCE` or `LEST` back to itself, is an obligation cycle under the literal reading of (ii): "could not check" fires on it, and a mark above it silences it.
  Decided by Claude 2026-11-21, pending Meng's review.
  Pinned by the mixed-cycle cases in `jl4-core/test/CyclesSpec.hs`: one rule (`obligation:unproved-self+fans`), two that use each other (`obligation:unproved-mutual+fans`), and a rule that only hands on by a `HENCE` to one that uses itself, where the warning names the rule that uses itself.
- Measured on this branch: three goldens move, `ok/deontic-breach-semantics` ("could not check" on `recursive lest`), `ok/every/run-after` ("could not check" on `retry`) and `ok/every/run-lest` ("no time" on `forthwith, forever`); none is under `jl4/examples/canon/`.

What review changed: the plan for this build said a mark on any member of the cycle silences its warning; the printed L4 condition says the definition the warning is reported on, and that is what was built.
A second review (2026-11-22) found texts that said more than L4 checks, and they were changed to say what L4 read: that it finds no way back, not that a rule never leads back; that it reads only a number written out, not that a time may be 0; and that a mixed cycle, which uses itself directly and through a `HENCE` or `LEST`, can draw "could not check".

## Open Questions

1. **Granularity of cycle errors:** Should the error message show the full cycle path (e.g., `Foo.x → globalBar → Bar.y → globalFoo → Foo.x`), or just list the involved definitions?

2. **Cross-module cycles:** If module A imports module B and both have computed fields that reference each other, should this be detected? The import resolution already detects cyclic imports, but computed field cycles could exist within a valid import DAG if the references are indirect.

3. **Performance:** For large codebases, building the full dependency graph after every edit may be expensive. Consider incremental updates (only rebuild subgraphs for changed modules) or lazy construction (build on demand for specific analyses).
