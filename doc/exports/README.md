# Exports: running your L4 in other people's systems

L4 is where a rule is written down once, precisely. It is rarely where the rule needs to _live_.
The benefits agency already runs OpenFisca. The legal-aid charity already publishes
docassemble interviews. The bank's business analysts already open DMN tables in Camunda. The
academic team already has a Catala pipeline. Asking all of them to adopt a new language is a bad
trade, and an unnecessary one.

So L4 compiles **out**. Each export takes the rules you have written and re-expresses them in a
system that already has users, semantics, tooling and an install base — and each one is a genuine
piece of software with its own community, not a format we invented.

| Neighbour                         | What it is                                                          | What you get from L4                                         | Command          |
| --------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------ | ---------------- |
| **[docassemble](docassemble.md)** | open-source guided interviews used across access-to-justice work    | a working interview that asks the citizen only what it needs | `l4 docassemble` |
| **[OpenFisca](openfisca.md)**     | the microsimulation engine behind several countries' benefit models | a runnable Python module of tax/benefit variables            | `l4 openfisca`   |
| **[Catala](catala.md)**           | a literate language for law, with a proof assistant behind it       | a literate module pairing statute text with its logic        | `l4 catala`      |
| **[Blawx](blawx.md)**             | a visual, blocks-based rules tool over the s(CASP) reasoner         | a Blawx project you can open, run and explain                | `l4 blawx`       |
| **[DMN and BPMN](dmn-bpmn.md)**   | the OMG standards for decision tables and process diagrams          | decision tables and process models for standard engines      | `l4 export`      |

## Which one do I want?

Pick by what you need to _do_, not by which is most sophisticated:

- **Let a member of the public answer questions and get an answer.** → [docassemble](docassemble.md)
- **Simulate a policy over a population, or plug into an existing tax-benefit model.** →
  [OpenFisca](openfisca.md)
- **Put the statute text and the formal rule side by side for lawyers to check.** →
  [Catala](catala.md)
- **Let a subject-matter expert inspect and query the rules without reading code.** →
  [Blawx](blawx.md)
- **Hand the decision to a business-process team, or an engine they already run.** →
  [DMN and BPMN](dmn-bpmn.md)

## What all of them have in common

**They read the same annotation you already use.** An export compiles the rules you have marked
with `@export` — the same annotation described in
[Exporting Rules for Deployment](../tutorials/deploying-rules/exporting-rules-for-deployment.md).
A rule without `@export` stays internal and is not emitted.

**They are compilers, not converters.** Each one takes a _subset_ of L4, because no neighbour
speaks all of it. OpenFisca and docassemble want decision rules; Catala wants the constitutive
layer; BPMN wants the regulative layer. The subset is stated on each page, and the compiler tells
you when your file falls outside it rather than guessing.

**They would rather refuse than lie.** If emitting something would make the target say what your
L4 does not say, these backends stop and tell you. That is a deliberate design choice: a silently
wrong export is worse than no export, because it looks like it worked.

## Fidelity reports

Three of the exports — docassemble, DMN and BPMN — emit a **fidelity report** alongside the
document: an itemised list of everything the target notation could not carry, at three severities.

| Severity     | Meaning                                               |
| ------------ | ----------------------------------------------------- |
| **Blocking** | the target cannot express this at all                 |
| **Lossy**    | it survived, but with meaning shaved off              |
| **Advisory** | it survived; here is a difference worth knowing about |

Pass `--fail-on blocking|lossy|advisory` to make the command exit non-zero at that severity. The
default is `none`, and deliberately so: **Blocking usually describes the target's limits rather
than a defect in your file**, and fires on most realistic exports. Read the report; do not assume
a clean exit means a complete translation.

OpenFisca and Catala do not emit fidelity reports. They rely on refusal plus, in Catala's case, a
machine-checked equivalence argument — see those pages.

## What these exports are not

**They are one-way.** With one exception these compile L4 _out_, not back in. Blawx alone can read
its own format back with `l4 blawx --import` (see [Blawx](blawx.md)). Do not plan a workflow in
which someone edits the generated artifact and expects the L4 to follow.

**They do not replace the source.** The generated artifact is a projection. When the law changes,
change the L4 and re-export; editing the OpenFisca Python or the DMN XML directly puts the two out
of step with nothing to detect it.

## Going deeper

Each page ends with pointers to the worked examples in `jl4/examples/` and to the design spec that
owns the rulings for that backend. The examples are the ones the test suite pins, so they are
guaranteed to be current — they cannot drift without turning CI red.
