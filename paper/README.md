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
