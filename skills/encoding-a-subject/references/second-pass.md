# The second pass: an independent test author, and optionally a refuter

Both of these run in a **fresh session** that has not seen the encoding being written.
That is the whole point: a session that watched the encoding being built shares its reading of the source, and its tests will agree with the code for the same reason the code is wrong.

## The independent test author (recommended)

In the 2026-09-21 comparison this was the one extra stage that caught something: it wrote an expectation from the source, the encoding disagreed, and the disagreement was the one reading the comparison later scored as a departure from the source.
Hand it the brief, the sources and the encoding directory, with this prompt:

> You are an INDEPENDENT TEST AUTHOR. An L4 encoding of this subject is in `ENCODING_DIR`.
> Read the brief at `BRIEF` and the SOURCES in `INPUTS_DIR` first, and decide, from the sources alone, what the answers to a set of scenarios should be.
> Write those answers down before you open the encoding.
> Only then open the encoding, to learn its exported names, and write `ENCODING_DIR/tests-independent.l4` asserting the answers you decided.
> Cover: every cell of the answer table the brief asks for, in every vintage; every threshold on both sides; every date edge on both sides; at least one scenario per route through each schedule or list of conditions; commencement.
> An assertion that FAILS is a finding: leave it failing and list it, with the provision you read it from.
> Do not edit any other file.
> Run the file and report the numbers `check.sh` prints for it.

Then go through every failing assertion yourself, against the source.
Each one is either an encoding error (fix the encoding, keep the assertion), a test-author error (fix the assertion and say why in `NOTES.md`), or a genuine ambiguity (open a fork in the register, and keep both readings visible).
Do not resolve a disagreement by deleting the assertion.

## An adversarial refuter (optional)

Worth running on a subject with many constants or many dates, where one wrong cell is easy to miss.
Run one session per lens; each gets the brief, the sources, the encoding, and:

> You are an ADVERSARIAL REFUTER. An L4 encoding of this subject is in `ENCODING_DIR` with its `NOTES.md`.
> Your job is to find where it is WRONG against the sources.
> You are rewarded for every confirmed discrepancy and penalised for every false one, so every finding carries evidence: the probe you ran (an `#EVAL` in a scratch file OUTSIDE `ENCODING_DIR` that imports the modules) and the source text, with the provision cited.
> Classify each finding: `wrong-answer`, `silent-gap`, `invented-default`, `scope`, or `cosmetic`.
> Do not edit anything under `ENCODING_DIR`.
>
> Your lens: ⟨one of the lenses below⟩

Lenses that have paid off:

- **The answer table.** For every cell the brief asks for, in each vintage, read the source cell yourself and probe the encoding for the same cell. A number that matches for the wrong reason — the wrong provision cited, the wrong thing it attaches to — is a finding.
- **The law and its dates.** Check every provision in scope line by line: thresholds, routes through each schedule, validity and renewal, commencement and transitional dates. Probe boundary values — a threshold exactly at the limit, a date exactly on the edge. Every earlier-of or later-of deserves a probe on each side.
- **Refusals, defaults and scope.** Find every place the encoding answers something the sources do not: a default supplied where the text is silent, a vintage borrowing a number from another, a `FALSE` or `0` where `REFUSE` was owed. Check the reverse too: a `REFUSE` where the source does answer.

Then a repair session — or you — takes each finding, verifies it against the source, and either fixes the encoding and adds an assertion that would have caught it, or records why it does not hold.

## What not to expect

In the comparison, a full pipeline of refuters, repairers and integrators cost about ten times a single encoder and produced no more faithful answers.
Its final integrator also **overruled** the independent test author's objection — the one the comparison later sided with.
So treat the second pass as evidence for you to weigh, not as a stage whose output is accepted automatically.
