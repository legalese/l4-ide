# Advanced course

Techniques for modelling real legal systems in L4. It assumes you have completed the [Foundation course](../foundation/README.md) or already write L4.

The course covers real regulatory schemes, patterns that cut across many rules (timing, notices, appeals), contracts in depth, and how to structure, test and deploy a real rulebase. Take the modules in order.

## Modules

- [Module A1: Real regulatory schemes](module-a1-regulatory.md): the three-layer approach, definitions and cross-references, built on a charity regulation example.
- [Module A2: Cross-cutting concerns](module-a2-cross-cutting.md): deadlines, notice and cure, appeals, escalation and grace periods.
- [Module A3: Contracts in depth](module-a3-contracts.md): payment terms, recursive obligations and penalties, built on a promissory note.
- [Module A4: Production patterns](module-a4-production.md): structuring a real rulebase into files and sections, testing it, and getting it ready to deploy.

## Example code

Modules A1 to A3 each come with a complete, validated example file:

- [module-a1-regulatory-examples.l4](module-a1-regulatory-examples.l4): a charity registration scheme
- [module-a2-cross-cutting-examples.l4](module-a2-cross-cutting-examples.l4): timing, notices, appeals and escalation
- [module-a3-contracts-examples.l4](module-a3-contracts-examples.l4): a loan contract with recursive obligations

More real-world encodings, including a complete promissory note, are in the [legal examples](https://github.com/legalese/l4-ide/tree/main/jl4/examples/legal) of the L4 repository.

## After this course

For a specific task, see the [Tutorials](../../tutorials/README.md); for the theory behind L4, [Concepts](../../concepts/README.md). Then apply what you have learned to the rules of your own domain.
