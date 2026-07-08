# Binary Decision Diagrams (ROBDD)

A **Reduced Ordered Binary Decision Diagram** (ROBDD) is a canonical, compressed
representation of a Boolean function. L4 uses ROBDDs as the substrate for
[query planning](README.md): reasoning about a Boolean-valued decision without
knowing every input yet.

This is a reference for the data structure and its operations. For how L4 turns
a decision into an interactive wizard on top of it, see the
[Query Planner](README.md).

## What it represents

A Boolean function maps an assignment of its variables to `TRUE` or `FALSE`. For
example, `age >= 18 AND (citizen OR resident)` is a Boolean function of three
atoms — `age >= 18`, `citizen`, `resident`. A truth table lists all `2^n` rows;
a decision tree branches on one variable at a time. An ROBDD is the same idea as
a decision tree, but shared and pruned so that equal functions have **exactly one**
representation.

## Structure

An ROBDD is a rooted directed acyclic graph (DAG):

- **Terminal nodes** `0` (`FALSE`) and `1` (`TRUE`).
- **Decision nodes**, each labelled with a variable and holding two edges:
  `low` (the variable is `FALSE`) and `high` (the variable is `TRUE`).

Two invariants make it canonical:

- **Ordered** — every path from the root to a terminal visits variables in the
  same fixed order, and never revisits a variable.
- **Reduced** — two reductions are applied exhaustively:
  1. **no redundant tests**: a node whose `low` and `high` point to the same
     child is deleted (the variable does not affect the outcome there);
  2. **no duplicate subgraphs**: structurally identical nodes are shared, not
     copied (hash-consing).

The consequence (Bryant, 1986) is **canonicity**: for a fixed variable order,
two Boolean functions are equal **if and only if** their ROBDDs are the same
graph. Equivalence checking, tautology checking, and satisfiability all become
pointer comparisons or a single walk of the DAG.

## Core operations

L4's implementation exposes the standard ROBDD toolkit:

| Operation    | Meaning                                                             |
| ------------ | ------------------------------------------------------------------- |
| `mk`         | construct a node, applying the two reductions (hash-consed)         |
| `var` / `neg`| an atom, and negation                                               |
| `apply`      | combine two ROBDDs under a connective (`AND`, `OR`, `IMPLIES`, …)    |
| `restrict`   | fix one variable to `TRUE`/`FALSE` — the *cofactor* (see below)      |
| `support`    | the set of variables the function actually depends on               |
| `nodeCount`  | the size of the DAG                                                  |

`restrict` is the operation that powers query planning: fixing an atom to a known
value yields the ROBDD of the *remaining* decision. When a `restrict` collapses
the graph to a terminal, the outcome is **determined** — no further questions
are needed.

## Model counting

Counting the assignments that lead to `1` (the satisfying assignments) is a
linear walk of the DAG. Weighting each variable by a probability instead of
counting uniformly gives the probability that the function is `TRUE`. This is the
primitive an information-gain [question-ordering policy](README.md#question-ordering)
is built on, and the point at which a per-atom prior from
[TYPICALLY](../types/TYPICALLY.md) enters.

## Variable ordering ≠ question ordering

The variable **order** fixes the shape of the diagram. A good order can keep an
ROBDD small; a bad order can make it exponentially large. But the order never
changes *which* function the ROBDD represents — it is a size/performance concern,
internal to the data structure.

This is distinct from the **question order** a wizard asks a user, which is a
dynamic, per-session decision about what to ask next given the answers so far.
Conflating the two is a common trap; the [Query Planner](README.md) covers the
question-ordering policy.

## Implementation notes

L4 carries two hand-rolled ROBDD implementations that mirror each other — one in
TypeScript (`ts-shared/boolean-analysis/src/robdd.ts`, used by the browser-side
web-app generator and partial evaluator) and one in Haskell
(`jl4-query-plan/src/L4/Decision/BooleanDecisionQuery.hs`, used server-side).
There is deliberately **no external BDD library** dependency; the graphs L4
builds from a single decision are small, and a self-contained implementation
keeps the two runtimes in step.

## See also

- [Query Planner](README.md) — the wizard and question-ordering policy built on
  top of ROBDDs
- [TYPICALLY](../types/TYPICALLY.md) — per-atom priors that feed the ordering
  policy
- R. E. Bryant, "Graph-Based Algorithms for Boolean Function Manipulation,"
  *IEEE Transactions on Computers*, 1986 — the canonical-form result
