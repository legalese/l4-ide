# Exports: running your L4 in other people's systems

L4 is where a rule is written down once, precisely. It is rarely where the rule needs to _live_.
The benefits agency already runs OpenFisca. The legal-aid charity already publishes
docassemble interviews. The bank's business analysts already open DMN tables in Camunda. The
academic team already has a Catala pipeline. Asking all of them to adopt a new language is a bad
trade, and an unnecessary one.

So L4 compiles **out**. Each export takes the rules you have written and re-expresses them in a
system that already has users, semantics, tooling and an install base — and each one is a genuine
piece of software with its own community, not a format we invented.

Every export is spelled the same way: `l4 export FORMAT FILE`. `l4 export --help` lists the
formats, and `l4 export FORMAT --help` lists one format's options. The one backend that also reads
its notation back does so with `l4 import FORMAT FILE`.

| Neighbour                         | What it is                                                          | What you get from L4                                                           | Command                              |
| --------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------ |
| **[docassemble](docassemble.md)** | open-source guided interviews used across access-to-justice work    | a working interview that asks the citizen only what it needs                   | `l4 export docassemble`              |
| **[OpenFisca](openfisca.md)**     | the microsimulation engine behind several countries' benefit models | a runnable Python module of tax/benefit variables                              | `l4 export openfisca`                |
| **[Catala](catala.md)**           | a literate language for law, with a proof assistant behind it       | a literate module pairing statute text with its logic                          | `l4 export catala`                   |
| **[Blawx](blawx.md)**             | a visual, blocks-based rules tool over the s(CASP) reasoner         | a Blawx project you can open, run and explain                                  | `l4 export blawx`, `l4 import blawx` |
| **[DMN and BPMN](dmn-bpmn.md)**   | the OMG standards for decision tables and process diagrams          | decision tables and process models for standard engines                        | `l4 export dmn`, `dmn-md`, `bpmn`    |
| **[yscript](yscript.md)**         | AustLII DataLex's decades-old Rules-as-Code rule language           | a consultation with a `Why?`/`How?`/`What if?` explanation apparatus, for free | `l4 export yscript`                  |

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
- **Hand a consultation to AustLII's decades-old Rules-as-Code explanation engine, for its
  `Why?`/`How?`/`What if?` apparatus.** → [yscript](yscript.md)

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
document (Blawx prints one kind of note, for a dropped `TYPICALLY`; see
[below](#what-each-export-does-with-typically)): an itemised list of everything the target notation could not carry, at three severities.

| Severity     | Meaning                                               |
| ------------ | ----------------------------------------------------- |
| **Blocking** | the target cannot express this at all                 |
| **Lossy**    | it survived, but with meaning shaved off              |
| **Advisory** | it survived; here is a difference worth knowing about |

Pass `--fail-on blocking|lossy|advisory` to make the command exit non-zero at that severity. The
default is `none`, and deliberately so: **Blocking usually describes the target's limits rather
than a defect in your file**, and fires on most realistic exports. Read the report; do not assume
a clean exit means a complete translation.

OpenFisca, Catala and yscript do not emit fidelity reports. They rely on refusal — plus, in
Catala's case, a machine-checked equivalence argument and a block of notes at the top of the
emitted module — see those pages. yscript's refusal is
whole-run rather than per-element: any offender anywhere in the exported closure means nothing is
written at all, not a smaller document with notes about what was cut.

## What each export does with `TYPICALLY`

[`TYPICALLY`](../reference/types/TYPICALLY.md) gives a name a default: the value to use when nothing
supplies one. A default is a statement about what to presume, so an export either carries it into a
mechanism of the target that means the same thing, or says that it could not. **None of them drops
it quietly, and none of them replaces it with a default of the target's own.**

| Export                            | A rule's own `GIVEN`                                              | A section `GIVEN` or `ASSUME`                | A record field                                                  |
| --------------------------------- | ----------------------------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------- |
| **[docassemble](docassemble.md)** | pre-fills the question (`default:`), and says so (`DA-TYPICALLY`) | the same                                     | the same                                                        |
| **[OpenFisca](openfisca.md)**     | the variable's `default_value`                                    | refused (the export reads no section inputs) | the variable's `default_value`                                  |
| **[Catala](catala.md)**           | a `context` variable with an in-scope default                     | the same                                     | dropped; the notes block says so                                |
| **[Blawx](blawx.md)**             | dropped; `R-TYPICALLY` on stderr and in the `.pl` header          | dropped, the same way                        | dropped, the same way                                           |
| **[DMN](dmn-bpmn.md)**            | dropped; `D-TYPICALLY` in the fidelity report (lossy)             | dropped, the same way                        | dropped, the same way                                           |
| **[BPMN](dmn-bpmn.md)**           | dropped; `P-TYPICALLY` in the fidelity report (lossy)             | dropped, the same way                        | dropped, the same way, when the drawn rule's condition reads it |
| **[yscript](yscript.md)**         | not exportable (a rule with `GIVEN`s is refused already)          | **refused**, naming the fact and its default | not exportable                                                  |

Three things the table cannot show:

- **A default the checker does not yet accept still gets one of these answers.** `TYPICALLY` must
  be a literal today. When it is allowed to be an expression, OpenFisca will turn it into a formula
  that a supplied input overrides (and refuse an expression it cannot lower), Catala will lower it
  as the in-scope definition, DMN, BPMN and Blawx will print it in their notes, docassemble will
  refuse it (or skip that export with a blocking note), and yscript will refuse it. No export is left with an arm that never saw one.
- **A default written in an imported file counts when the export reads it.** DMN, dmn-md, BPMN and
  Catala report it, and name the imported module in the note. OpenFisca, Blawx, docassemble and
  yscript refuse an imported `ASSUME` or an imported record field that the exported rule reads
  (measured on the 2026-10-03 build: exit 1, nothing written), so none of them can carry one away
  unannounced. A default on an imported rule's own `GIVEN` is not reported, because the exported
  rule reaches that rule by calling it, and a call supplies every argument.
- **OpenFisca is the one target that cannot be left to say nothing.** It gives every variable a
  default whether or not you wrote one (`0.0`, `False`, the first member of an enum), so a
  `TYPICALLY` it did not write out would be silently replaced by that. It maps every default, and
  refuses the ones with no OpenFisca value.

## What these exports are not

**They are one-way.** With one exception these compile L4 _out_, not back in. Blawx alone can read
its own format back with `l4 import blawx` (see [Blawx](blawx.md)). Do not plan a workflow in
which someone edits the generated artifact and expects the L4 to follow.

**They do not replace the source.** The generated artifact is a projection. When the law changes,
change the L4 and re-export; editing the OpenFisca Python or the DMN XML directly puts the two out
of step with nothing to detect it.

## Going deeper

Each page ends with pointers to the worked examples in `jl4/examples/` and to the design spec that
owns the rulings for that backend. The examples are the ones the test suite pins, so they are
guaranteed to be current — they cannot drift without turning CI red.
