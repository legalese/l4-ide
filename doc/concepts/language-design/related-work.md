# Related Work: Tables, Trees, Diagrams, and Order

The reading behind [Flowcharts, Decision Tables, and Real Logic](logic-not-flowcharts.md).

That document makes four kinds of claim — about flowcharts, about decision tables,
about diagrams that share structure, and about the order in which questions get
asked. All four have deep literatures, and **most of what is casually said about
them in the rules-as-code world is wrong**, ours included: an earlier draft of that
document levelled four criticisms at DMN, three of which turned out to be false.

This page is the corrective. It is organised by claim, so you can check us.

> **A note on the shape of this field.** The most striking finding was not any
> single paper. It was that the pieces of this puzzle sit in **separate rooms**.
> The decision-table verification community (Vanthienen, PROLOGA), the BDD/formal-
> methods community (Bryant, Wegener), and the AI & Law community have each held a
> third of the answer for decades — and they do not cite one another. A full-text
> search of the journal _Artificial Intelligence and Law_ for "binary decision
> diagram" returns **zero** results. A full-text search of the canonical DMN
> semantics papers for the same phrase returns **zero**. There are exactly three
> exceptions anywhere, in three different communities, none citing the others.
> Much of what looks like open ground is actually just unswept floor.

---

## 1. Decision tables are old, good, and checkable

The claim in the main document is _not_ that decision tables are weak. It is that
their **analysable fragment is not the fragment you are told to write**. Everything
below is the evidence that they are strong.

- **Montalbano, M.** (1962). "Tables, Flow Charts, and Program Logic." _IBM Systems
  Journal_ 1(1):51–63.
  [PDF](http://bitsavers.org/pdf/ibm/IBM_Systems_Journal/011/ibmsj0101E.pdf)
  — **The origin.** Completeness and consistency checking of decision tables, in the
  first volume of the journal, **fifty-three years before DMN**. Shows constructively
  that one table yields a _storage_-optimal flowchart and a _different_ _time_-optimal
  one — i.e. that the tree is an evaluation strategy, not the meaning. His ordering
  heuristic ("ask those questions first which will make the two differentiated groups
  of rule identifiers as similar in size as possible") is an information-gain
  criterion **twenty-four years before ID3**.

- **Vanthienen, J., Mues, C., Wets, G. & Delaere, K.** (1998). "A tool-supported
  approach to inter-tabular verification." _Expert Systems with Applications_
  15(3–4):277–285. [DOI](https://doi.org/10.1016/S0957-4174%2898%2900047-5)
  — Verification **across chains of linked tables**: circular dependencies, sub-tables
  that can never fire, with the dependency structure drawn as a directed graph. A
  Decision Requirements Graph in all but name, seventeen years early. Implemented in
  the PROLOGA tool.

- **Vanthienen, J. & Robben, F.** (1993). "Developing legal knowledge based systems
  using decision tables." _ICAIL '93_, 282–291.
  [DOI](https://doi.org/10.1145/158976.159011)
  — The AI-and-Law-side ancestor: legal knowledge-based systems on decision tables,
  with verification built in from the start.

- **Calvanese, D., Dumas, M., Laurson, Ü., Maggi, F. M., Montali, M. & Teinemaa, I.**
  (2016). "Semantics and Analysis of DMN Decision Tables." _BPM 2016_, LNCS 9850.
  [DOI](https://doi.org/10.1007/978-3-319-45348-4_13) ·
  [arXiv](https://arxiv.org/abs/1603.07466). Extended as "Semantics, Analysis and
  Simplification of DMN Decision Tables", _Information Systems_ 78:112–125, 2018.
  [DOI](https://doi.org/10.1016/j.is.2018.01.010)
  — DMN's modern semantics. Each rule is read as a **hyper-rectangle** in the input
  space; gaps and overlaps are found by geometric sweep. This is not a whiteboard
  result: it is the algorithm inside Drools and Trisotech today. **Confined to S-FEEL,
  single table.**

- **Vandevelde, S., Callewaert, B. & Vennekens, J.** (2022). "Context-Aware
  Verification of DMN." _HICSS-55_.
  [AISeL](https://aisel.aisnet.org/hicss-55/os/business_rule/3/)
  — Discharges **whole-graph** consistency to an SMT solver (IDP-Z3), and finds rules
  that are dead **only in context** — unfireable not because of anything in their own
  table, but because of what the tables upstream can actually produce. The claim
  "you cannot check across a DRD" is false, and this is why.

- **Grohé, L., Corea, C. & Delfmann, P.** (2021). "DMN 1.0 Verification Capabilities:
  An Analysis of Current Tool Support." _BPM 2021_.
  [DOI](https://doi.org/10.1007/978-3-030-85440-9_3)
  — And yet: of **fourteen** DMN tools surveyed, **five** support any verification at
  all. The survey's own word for the industry's coverage is "alarmingly low." The
  theory exists; it is not shipped.

- **OMG.** _Decision Model and Notation (DMN), Version 1.3_ (2021).
  [Spec](https://www.omg.org/spec/DMN/1.3/PDF)
  — Read §9.1 in the standard's own voice: "**few if any complete decision models can
  be defined using S-FEEL** … Developers and users are therefore encouraged to use …
  **full FEEL**." Every result above lives in S-FEEL. That gap is the whole argument.

---

## 2. Tables and trees denote the same thing; only trees pick an order

- **Hyafil, L. & Rivest, R. L.** (1976). "Constructing Optimal Binary Decision Trees
  is NP-Complete." _Information Processing Letters_ 5(1):15–17.
  [DOI](https://doi.org/10.1016/0020-0190%2876%2990095-8)
  — The classic. Turning a rule base into a _minimal-cost_ interrogation is NP-hard,
  and has been known to be for fifty years. This is why every practical policy,
  including L4's, is greedy.

- **Mues, C., Baesens, B., Files, C. M. & Vanthienen, J.** (2004). "Decision diagrams
  in machine learning: an empirical study on real-life credit-risk data." _Expert
  Systems with Applications_ 27(2):257–264.
  [DOI](https://doi.org/10.1016/j.eswa.2004.02.001)
  — States the main document's DAG-vs-tree point in their own words: decision trees
  suffer "the **inherent replication of isomorphic subtrees**", whereas a decision
  diagram is "a rooted, acyclic digraph instead of a tree." The four duplicate
  `permitted` boxes in our flowchart exhibit are this, in the wild.

---

## 3. Order is a property of the evaluation, not of the rule

The main document distinguishes three senses of "order" — the rule's (none), the
statute's (which the ladder mirrors), and the interrogation's (which L4 optimises).
The formal backing:

- **Bryant, R. E.** (1986). "Graph-Based Algorithms for Boolean Function
  Manipulation." _IEEE Transactions on Computers_ C-35(8):677–691.
  [DOI](https://doi.org/10.1109/TC.1986.1676819)
  — The ROBDD, and the sentence the whole argument turns on: the variable ordering
  you choose changes the diagram's **size** enormously, but has **"no effect on the
  correctness of the results."** Order belongs to the evaluation. A flowchart is a
  notation that cannot tell the two apart.

- **Bollig, B. & Wegener, I.** (1996). "Improving the Variable Ordering of OBDDs is
  NP-Complete." _IEEE Transactions on Computers_ 45(9):993–1002.
  [DOI](https://doi.org/10.1109/12.537122)
  — And choosing the size-optimal order is itself intractable. Note this is a
  **different** NP-hardness from Hyafil & Rivest: that one minimises _questions asked_,
  this one minimises _diagram nodes_. They share a word and nothing else.

- **Darwiche, A. & Marquis, P.** (2002). "A Knowledge Compilation Map." _JAIR_
  17:229–264. [DOI](https://doi.org/10.1613/jair.989)
  — Why compiling to a diagram is worth it at all. Satisfiability is NP-complete; on
  an ROBDD it is **O(1)**. The hardness has not vanished, it has been **displaced into
  compilation**. Pay once, offline; then answer unboundedly many queries cheaply. This
  is the architecture of L4's wizard.

- **Bench-Capon, T. & Coenen, F.** (1992). "Isomorphism and legal knowledge based
  systems." _Artificial Intelligence and Law_ 1(1):65–86.
  [DOI](https://doi.org/10.1007/BF00118479)
  — Where the word **isomorphism** comes from in this field, and why a formalisation
  that mirrors the source text's structure is maintainable in a way that one which
  optimises it away is not. This is the reason the ladder keeps the statute's order.

---

## 4. Asking good questions in a good order is a fifty-year-old problem

L4's [query-plan wizard](../../reference/query-planning/README.md) picks the next
question by information gain over a compiled ROBDD. Every ingredient of that is old,
and the lineage is worth knowing.

- **Shwayder, K.** (1974). "Extending the Information Theory Approach to Converting
  Limited-Entry Decision Tables to Computer Programs." _CACM_ 17(9):532–537.
  [DOI](https://doi.org/10.1145/361147.361117)
  — **Entropy-driven test ordering from a rule base, in 1974.** The direct ancestor.

- **Aucher, G., Berbinau, J. & Morin, M.-L.** (2019). "Principles for a Judgement
  Editor Based on Binary Decision Diagrams." _Journal of Applied Logics — IfCoLog_
  6(5):781–814. [HAL](https://inria.hal.science/hal-02273483)
  — **The closest existing work to L4's wizard**, and it comes from the bench: built
  with the French _Cour de cassation_, it compiles legal rules to a BDD **whose nodes
  are the questions put to the judge**, and adds a second BDD to reconcile substantive
  legal reasoning with the _procedural_ order that trial protocol imposes — which is a
  sharper version of our three-orders distinction, arrived at independently. They do
  not _optimise_ the question order. That is the only gap L4 fills.

- **Golovin, D. & Krause, A.** (2011). "Adaptive Submodularity: Theory and
  Applications in Active Learning and Stochastic Optimization." _JAIR_ 42:427–486.
  [DOI](https://doi.org/10.1613/jair.3278)
  — The near-optimality guarantee for greedy question selection. If you say
  "near-optimal", this is what you are relying on.

- **Ünlüyurt, T.** (2004). "Sequential testing of complex systems: a review."
  _Discrete Applied Mathematics_ 142(1–3):189–205.
  [DOI](https://doi.org/10.1016/j.dam.2002.08.001)
  — The field this problem actually belongs to. It has a name and a survey.

- **Hadzic, T. et al.** (2004) / **Andersen, H. R., Hadzic, T. & Pisinger, D.** (2010).
  "Interactive Cost Configuration Over Decision Diagrams." _JAIR_ 37:99–139.
  [DOI](https://doi.org/10.1613/jair.2905)
  — Compile the rule base to a BDD offline, then drive a **backtrack-free** interview
  off it, so the user can never be led into a dead end. Architecturally, a legal wizard
  — built for product configuration, and commercialised as Configit.

- **Lamy, J.-B. et al.** (2024). "Adaptive questionnaires for facilitating patient data
  entry in clinical decision support systems." _BMC Medical Informatics and Decision
  Making_ 24:326. [DOI](https://doi.org/10.1186/s12911-024-02742-6)
  — ⚠️ **The sobering one.** Solves exactly this problem end-to-end, and finds that a
  **frequency heuristic** performs about as well as anything cleverer. Any claim that a
  sophisticated policy asks fewer questions should be measured against that baseline,
  not against a strawman.

---

## Further Reading

- [Flowcharts, Decision Tables, and Real Logic](logic-not-flowcharts.md) — the argument this reading supports
- [Design Principles](principles.md)
- [Query Planning](../../reference/query-planning/README.md) — what L4 actually does with the ROBDD

_The full research record — including the sources we checked and rejected, the
citation traps, and an honest account of what this project got wrong before it got it
right — is kept out of the documentation proper, in
`specs/research/DMN-STEELMAN.md`._
