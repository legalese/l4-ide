# The L4 Papers — toward a _Book of L4_

A faceted series of academic papers about **L4**, each aimed at a different
venue/audience, all drawing on the one L4 system and its computational-law thesis.
They are written to _facet together_: the ICAIL paper is the broad introduction each
of the others zooms into. Once the papers go out, the intention is to consolidate them
(with the concept notes below) into a single **Book of L4**; this file is the assembly
index.

What the Book is and is not — the argument and the worked cases, written for programmers first,
never the language reference — is recorded under [Positioning](#positioning--what-the-book-is-for-and-what-it-is-not) below.

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

## Positioning — what the Book is for, and what it is not

_Recorded 2026-09-03, from a session that asked whether a book is a fool's errand when readers
outsource reading to models, and whether the effort belongs in the Claude Code skill instead. The
numbers below were checked that day against the linked sources; re-check before quoting them._

**The Book is the argument and the worked cases. It is not the language reference.** The
reference — syntax, the `l4` CLI, the stdlib, the projections — lives in the skill
([`skills/writing-l4-rules/`](../skills/writing-l4-rules/)), in [`doc/reference/`](../doc/reference/),
and in whatever agent-facing surface (an `llms.txt`) the docs grow. Nothing in the Book should be a
thing its reader would rather ask a model.

The evidence behind that split is **not** a general collapse of reading. It is a collapse of
_reading-to-look-something-up_ while _reading-an-argument_ holds:

| Measure                                           | Change                                    | Period                      | Checked against                                                                                                                                                                                         |
| ------------------------------------------------- | ----------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stack Overflow monthly questions                  | >200k → <50k                              | 2014 → late 2025            | [devclass](https://www.devclass.com/ai-ml/2026/01/05/dramatic-drop-in-stack-overflow-questions-as-devs-look-elsewhere-for-help/4079575)                                                                 |
| Wikipedia human pageviews                         | −8% YoY                                   | 2025                        | [Wikimedia via gHacks](https://www.ghacks.net/2025/10/20/wikipedia-sees-decline-in-human-pageviews-says-ai-is-to-blame/)                                                                                |
| Google click-through when an AI Overview is shown | 8%, vs 15% without                        | 2025                        | [Pew via ODSC](https://odsc.medium.com/pew-study-google-users-click-less-when-ai-summaries-appear-in-search-results-cc003baf6a35)                                                                       |
| Share of docs traffic that is agents              | 15% → 66%; human page loads still growing | Jan → Jul 2026              | [Mintlify midyear report](https://www.mintlify.com/blog/state-of-docs-traffic)                                                                                                                          |
| _Learning Go_ (O'Reilly) copies sold              | 20k → 13k                                 | 1st ed. 2021 → 2nd ed. 2024 | [author, on HN](https://news.ycombinator.com/item?id=48273030); most revenue is platform, and the platform is losing to LLMs                                                                            |
| The Pragmatic Bookshelf                           | laid off most staff, closed submissions   | 2025                        | [HN](https://news.ycombinator.com/item?id=46194863). The "40% YoY nonfiction fall" quoted there is hearsay from an author's email and contradicts Circana; treat as a computing-category figure at best |
| Circana print units, all books                    | 762.4M, +0.3%; flat in H1 2026            | 2025                        | [Publishers Weekly](https://www.publishersweekly.com/pw/by-topic/industry-news/financial-reporting/article/99417-print-book-sales-rose-slightly-in-2025.html)                                           |
| Adult fiction / adult nonfiction print            | +5.7% / −5.8%                             | H1 2026                     | [Publishers Weekly](https://www.publishersweekly.com/pw/by-topic/industry-news/financial-reporting/article/100790-print-book-sales-flat-in-first-half-of-2026.html), which names no AI cause            |

The literacy decline proper is real — NAEP grade-12 reading at its lowest since the series began
in 1992 ([NCES](https://www.nationsreportcard.gov/reports/reading/2024/g12/national-trends/)),
PIAAC US adult literacy down 12 points 2017→2023
([NCES](https://nces.ed.gov/surveys/piaac/2023/national_results.asp)), daily reading for pleasure
28%→16% of adults 2004→2023
([iScience](<https://www.cell.com/iscience/fulltext/S2589-0042(25)01549-4>)) — but its fieldwork
predates generative AI. It is a smartphone, pedagogy and pandemic story that AI arrives into. The
controlled AI-offloading studies are thin: MIT's _Your Brain on ChatGPT_
([arXiv 2506.08872](https://arxiv.org/abs/2506.08872)) is n=54 and under methodological challenge
([arXiv 2601.00856](https://arxiv.org/pdf/2601.00856)); the best-designed, Bastani et al.
([PNAS 2025](https://www.pnas.org/doi/10.1073/pnas.2422633122), ~1000 students), finds
**unguarded** GPT lowers unaided exam scores while GPT **with tutoring guardrails** does not. The
publishing industry's own warning
([IPA, Oct 2025](https://internationalpublishers.org/has-the-time-come-is-ai-weakening-reading-skills/))
is an argument from Naomi Baron's _Reader Bot_, not a sales series.

Three things follow, and together they are the position:

1. **Law is a citation discipline.** Drafting offices, regulators and law reviews cite treatises.
   A skill cannot go in a footnote. The legitimacy rules-as-code needs requires a citable anchor,
   and the Book is it. This is the _legitimacy_ reader; which human reader comes _first_ is
   settled below, and it is not this one.
2. **The second reader is the model.** L4 has almost no public text. A skill reaches one Claude in
   one harness; open full text on the web reaches every model at the next training run. Reader
   outsourcing is a reason to write the Book, not a reason to skip it — **provided the Book is
   open-licensed and crawlable in full**. A paywalled, print-only Book fails its second reader
   entirely.
3. **One corpus, not two.** The skill's examples are drawn from the Book's worked cases — the
   [case studies](case-studies/), Reg CF, _Poh Yuan Nie_, the British Nationality Act, the
   [unauthorised-practice sidebar](political-economy/SIDEBAR-unauthorised-practice.md) — and are
   not maintained in parallel. The Book is the _why_ and the cases; the skill is the _how_.

> **Discipline: the skill must explain, not only emit.** Bastani's guardrail result cuts against a
> skill that simply writes the L4 for the user — that produces users who cannot read L4. The skill
> should teach as it goes and point at the Book; the Book should exist to be pointed at.

**Which human reader first: the programmer.** Observation recorded 2026-09-03: the world contains
many more working programmers than working lawyers, and the Book's audience should prefer the
former. The headcounts, checked that day:

| Population                                     | Count            | As of                               | Checked against                                                                                                       |
| ---------------------------------------------- | ---------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Developers, professional / all incl. hobbyists | 36.5M / 47.2M    | Q1 2025                             | [SlashData](https://www.slashdata.co/post/global-developer-population-trends-2025-how-many-developers-are-there)      |
| Developers, narrower definition                | 27M              | 2024                                | [Evans Data](https://evansdata.com/press/viewRelease.php?pressID=365)                                                 |
| Lawyers, United States                         | 1.32M active     | Jan 2024                            | [ABA via Wikipedia](https://en.wikipedia.org/wiki/Attorneys_in_the_United_States)                                     |
| Lawyers, Brazil                                | 1.34M practising | 2023                                | [OAB via Wikipedia](https://en.wikipedia.org/wiki/Order_of_Attorneys_of_Brazil)                                       |
| Lawyers, India                                 | 1.3M             | 2011 RTI figure; later guesses 1.5M | [Legally India](https://www.legallyindia.com/the-bench-and-the-bar/rti-reveals-number-of-lawyers-india-20130218-3448) |
| Lawyers, China                                 | 0.65M            | 2022                                | [Statista](https://www.statista.com/statistics/224787/number-of-lawyers-in-china/)                                    |

No primary source counts lawyers worldwide; the four largest bars sum to about 4.6M and the usual
extrapolation is 6–7M. So the honest ratio is **four to eight times, not ten** — the order of
magnitude does not survive checking. The conclusion does not need it. Three reasons that do not
depend on the headcount:

- **It is the strategy already on record.** Not targeting lawyers first is the Christensen move
  the project is built on: the SME founder who would rather write code than pay fees is the first
  bowling pin, and PostScript's readers were developers and printer makers, not designers.
- **Programmers build the ecosystem.** The platform play needs people who write against the
  language. A book that recruits them compounds; a book that persuades lawyers does not.
- **Programmers already buy argument-books in technical form.** SICP, _Types and Programming
  Languages_, _Designing Data-Intensive Applications_ are exactly the "argument and worked cases,
  not reference" shape ruled above. There is no corresponding genre a practising lawyer buys.

The caveat is in the same Stack Overflow survey cited above: early- and mid-career developers go
to AI first, and the ones who still read are the experienced ones. Write for them. The lawyer,
the drafting office and the law review remain the legitimacy reader of point 1 — the second human
audience, not the first.

There is a positive reason to prefer the senior developer, not only the survival-of-reading one
(observation recorded the same day). As raw software construction approaches a solved problem —
the model writes the code — the developer's remaining work moves up the stack, to specification:
saying precisely what a system must do, for whom, under which conditions, and what happens when
it does not. Follow that move far enough and it lands in the neighbourhood of law, which is
specification of behaviour for systems whose moving parts are people. The senior developer
arriving there is the Book's natural reader: already fluent in types, tests and invariants, newly
in need of deontics, defeasibility and interpretation. This is the old observation that a
requirements engineer can out-wordsmith a lawyer, turned from an anecdote into an audience.

**What would overturn this.** Argument-shaped reading joining the collapse (fiction and backlist
turning down; law reviews ceasing to cite books), experienced programmers joining the AI-first
cohort, or the open web ceasing to feed model training. None was the case on 2026-09-03.
