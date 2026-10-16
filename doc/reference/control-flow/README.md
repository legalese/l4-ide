# Control flow

L4 has no statements, only expressions, so choosing between results is done with expressions that give a value.
`IF` and `BRANCH` choose by conditions; `CONSIDER` chooses by the shape of a value. In each, every outcome must have the same type.

## Pages

- [IF](IF.md): `IF … THEN … ELSE`, one condition and two outcomes
- [BRANCH](BRANCH.md): several conditions, tried from top to bottom, with `OTHERWISE`
- [CONSIDER](CONSIDER.md): pattern matching with `WHEN … THEN` and `OTHERWISE`, and the check for missing branches

A function can also be written as [several clauses](../functions/DECIDE.md#several-clauses), one per case, which means the same as a `CONSIDER`.
Conditions are combined with [AND, OR, NOT, IMPLIES](../operators/logical.md) and [UNLESS](../operators/UNLESS.md).

The [Foundation course, module 3](../../courses/foundation/module-3-control-flow.md) teaches these step by step.
