# The L4 Papers — toward a _Book of L4_

A faceted series of academic papers about **L4**, each aimed at a different
venue/audience, all drawing on the one L4 system and its computational-law thesis.
They are written to _facet together_: the ICAIL paper is the broad introduction each
of the others zooms into. Once the papers go out, the intention is to consolidate them
(with the concept notes below) into a single **Book of L4**; this file is the assembly
index.

## Papers

| Facet                                           | Directory                                                | What it is                                                                                                                                                           |
| ----------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Introduction to L4**                          | [`icail/`](icail/)                                       | The broad intro paper (EN + JA): CSL / event-calculus framing, surface syntax, PROLEG/burden appendix.                                                               |
| **Deontics as Domination** _(Bounded Deontics)_ | [`bounded-deontics/`](bounded-deontics/)                 | Goal-bounded obligation as derived dominator-necessity; the Holmes/Hart two-ordering reading. Includes the second-order **powers as higher-order deontics** section. |
| **The determinacy frontier**                    | [`cls-determinacy-frontier/`](cls-determinacy-frontier/) | Empirical facet: classifying judgments into determinacy strata (detect≠resolve). _Design note._                                                                      |
| **CNL syntactic affordances**                   | [`cnl-affordances/`](cnl-affordances/)                   | The surface-syntax/HCI facet (Cognitive Dimensions; the CNL design space). _Design note._                                                                            |
| **Formal methods in law**                       | [`formal-methods-in-law/`](formal-methods-in-law/)       | The "white-hat Bad Man" ladder of FM over legal text; includes the reproducible _Letter and the Spirit_ worked example.                                              |
| **Seeing Like a Citizen**                       | [`political-economy/`](political-economy/)               | The political economy of legal legibility as civic infrastructure. _Design note._                                                                                    |
| **Hohfeld, higher-order**                       | [`hohfeld-higher-order/`](hohfeld-higher-order/)         | Hohfeldian powers as higher-order deontics. **Now a section of _Deontics as Domination_** (see its `DESIGN.md`), not a standalone paper.                             |

## Planned — placeholder, not yet started

| Facet                                          | Source notes                                                                                                                                                                                        | What it would be                                                                                       |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **Who May Change the Rules** _(working title)_ | [`yc-safe/`](../specs/todo/yc-safe/SPEC-NOTES.md) · [`corporate-resolutions/`](../specs/todo/corporate-resolutions/SPEC-NOTES.md) · [`godel-loophole/`](../specs/todo/godel-loophole/SPEC-NOTES.md) | Self-reference in normative systems, across three worked instruments. **No directory yet, by design.** |

_The first two spec-note links resolve once `docs/yc-safe-spec` and
`docs/corporate-resolutions-spec` merge; only `docs/godel-loophole-spec` is on this branch._

Three arcs that look unrelated are one problem. The YC SAFE's value depends on the valuation that
depends on the SAFE — an **arithmetic fixpoint**. Corporate governance asks who may change the rule
that says who may change the rules — **layered amendment authority**. Article V applies the amendment
rule to itself — an **open regress**, and the leading reconstruction of what Gödel is said to have
found in 1947.

The candidate spine, if it survives contact with the work: **a self-amendment regress is closed
exactly when the meta-rule lives in a layer the actor cannot reach.** Singapore company law closes
it — s26 and s26A of the Companies Act sit in the statute, outside the constitution they govern, and
entrenchment is removable only by unanimity. The US Constitution cannot, because Article V is inside
the document it governs. The testbed ladder runs **Love Letter** (rules do not change) → **Fluxx**
(finite, fixed deck) → **Nomic** (open, player-authored), and is chosen so the encoding fails cheaply
before it is pointed at real law.

Prior art to distinguish from, not to rediscover: **van der Meyden & Maher** on the SAFE (2025
Springer book), **Ellul & Pace** on Nomic (_SoliNomic_, 2022 — and Pace is already a named direct
ancestor in [`formal-methods-in-law/`](formal-methods-in-law/)), and the **Ross–Hart–Suber**
self-amendment literature that long predates the Gödel framing.

> **Discipline: write this after the work ships, not before.** The value of all three arcs is that
> they produce checkable findings; a paper drafted ahead of them would be an argument about what we
> expect to find. Two of the three arcs currently have no code at all, and one of them — the Gödel
> case — has **no ground truth by construction**, since Gödel never wrote his contradiction down.
> This row exists so the facet is not forgotten, not so it can be started.

## Case studies

Worked L4 analyses of real instruments — not full papers, but valuable writing and a
source of appendix / worked-example material. See [`case-studies/`](case-studies/):
the Jersey Covid-19 Gathering Control Order and the Charities (Jersey) Law 2014.

## Concept notes (to fold into the Book)

Longer-form essays and design notes from the L4 documentation that belong in the Book
even though they are not academic papers:

- [**Flowcharts, Decision Tables, and Real Logic**](../doc/concepts/language-design/logic-not-flowcharts.md)
  — why L4 is a _language_ rather than a flowchart or decision-table builder, and why
  the flowchart, the instinctive first choice, is usually the _wrong picture_.
