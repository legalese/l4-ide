# Steelmanning DMN

Research memo for `doc/concepts/language-design/logic-not-flowcharts.md`, section
_"Decision tables: better than flowcharts, still not the substrate"_ — and, as it turned
out, for three other sentences in that document that are also wrong.

---

## 0. Bottom line up front

We are wrong more often than we are right in that section, and a DMN-literate reviewer
would notice.

| #   | Our claim                                                    | Verdict                                                                                                                                                      |
| --- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | "No computation. A table yields a chosen row, not a number." | **FALSE.** Output cells are _expressions_ — arithmetic is legal even in S-FEEL. `Collect+` sums across rules.                                                |
| 2   | "No composition or sharing. `n` conditions is `2ⁿ` rows."    | **FALSE twice.** Don't-care cells kill the `2ⁿ`. The DRG gives real composition — the spec says "functional composition" in those words.                     |
| 3   | "No obligations over time."                                  | **TRUE, and now citable** — but it is a scope statement, not an objection. A sharper point is available.                                                     |
| 4   | "Not solver-checkable across rules."                         | **FALSE.** Intra-table checking dates to **1962**; _inter-tabular_ checking to **1998**; and cross-DRD semantic verification is **implemented** (SMT, 2022). |

Three further errors found while checking:

- **"a table is a truth table… _order-independent_"** — false for `First` and `Priority`
  hit policies, which are explicitly rule-ordered.
- **"DMN itself splits them — decision tables _and trees_ for the logic"** — DMN has no
  decision trees. The string "decision tree" occurs **zero** times in the DMN 1.3 spec (I
  grepped it; "tree" occurs once, unrelated).
- **"[the ladder] is _order-independent_"** — visibly false, and we should not want it to
  be true. See §5.

**What actually survives — and it is sharper than what we had:**

> DMN's analysable fragment is **S-FEEL**. Its own specification says "few if any complete
> decision models can be defined using S-FEEL" and tells you to use full FEEL instead. The
> tables that _compute_ — computed outputs, `Collect`-and-sum — fall outside the analysable
> fragment **by construction**. So the fragment you can verify is not the fragment you are
> told to write. And the one published system that handles generic FEEL gives up on static
> verification entirely and falls back to random testing.

That is defensible at ICAIL, JURIX or CLS. "Tables can't compute" and "tables can't
compose" are not.

---

## 1. Sources

Primary source is the OMG spec: I downloaded **DMN 1.3**
([omg.org/spec/DMN/1.3/PDF](https://www.omg.org/spec/DMN/1.3/PDF), 232pp), converted it to
text and grepped it. Every § number and quotation is from that document unless noted. I
also read in full: Calvanese et al. (BPM 2016), Calvanese et al. (Semantic DMN, TPLP 2019),
Batoulis & Weske (BPM demos 2017), Vandevelde et al. (cDMN), Bryant (1986), and Bench-Capon
& Coenen (1992).

⚠️ **Two corrections to things I initially drafted and got wrong**, recorded so they don't
get published:

1. I wrote "nobody checks the DRG." **False** — see §2.4(iii).
2. I implied cross-DRG verification is "a theorem, not a tool." **False** — there is a
   working SMT-backed implementation (HICSS-55, 2022).

---

## 2. The steelman

### 2.1 Criticism 1 — "No computation" → **false; delete it**

**DMN §8.2.9, in its entirety:** "A rule output entry is an expression." Not a constant.
`Income * 0.03` is a legal output cell.

**And this holds even at the restricted conformance level.** §9.5.3, on the use of S-FEEL
in decision tables: "Each output entry SHALL be a **simple expression** (grammar rule 3)" —
and S-FEEL grammar rule 3 is `simple expression = arithmetic expression | simple value |
comparison`. So arithmetic in an output cell is available at **Conformance Level 2**, the
S-FEEL-only level. A fee schedule with computed cells is a plain, conformant S-FEEL table.

**Tables also aggregate across rows.** The `Collect` hit policy (§8.2.10) takes an operator
— `+` (sum), `<` (min), `>` (max), `#` (count): "**+ (sum): the result of the decision table
is the sum of all the outputs.**" A `C+` table over a fee schedule _is_ a summation over
matched rules — precisely the case we said tables cannot do.

**What honestly survives** is only the spec's own next sentence: "Other policies, such as
more complex manipulations on the outputs, can be performed by post-processing the output
list **(outside the decision table)**." So the table is not _where the computation lives_ —
its cells are expressions in a different language, and anything past sum/min/max/count
leaves the table entirely. Our "that bolt-on is the tell" line is fine. The sentence before
it is not, and it is the kind of error that ends a reviewer's goodwill on page one.

---

### 2.2 Criticism 2 — "No composition or sharing" → **false; and the `2ⁿ` is wrong too**

#### (a) The arithmetic is wrong

§8.2.5: "**A dash symbol ('-') can be used to mean any input value, i.e., the input is
irrelevant for the containing rule.**"

So a DMN rule is a **cube** (a partial assignment), not a _minterm_. `(A ∧ B) ∨ (C ∧ D)` is
**two rules plus a default**, not sixteen rows. We assert a blow-up that competent DMN
modelling does not suffer, and any practitioner will know it.

The blow-up is real only where the DNF is irreducible — parity being the standard witness
(no two minterms of XOR are adjacent, so its minimal DNF has `2ⁿ⁻¹` terms while a factored
form is linear). True and interesting. Not what we said.

#### (b) DMN has composition, and the spec uses the word

DMN is **two-level**: a _decision requirements_ level (the DRG, drawn as a DRD) and a
_decision logic_ level (tables and other boxed expressions). The composition is at the first
level, and it is real.

- **Decisions feed decisions.** §6.2.2.1: "Information Requirements may be drawn from Input
  Data elements to Decisions, **and from Decisions to other Decisions**."
- **A BKM is a function.** §5.3.2: "The interpretation of business knowledge models as
  functions in DMN means that the combination of business knowledge models … has **the clear
  semantics of functional composition**." §7.3.3: a BKM's logic "must be **a single FEEL
  boxed function definition**", it is "**reusable, invocable**", and it takes **parameters**.
- **Decision Services are encapsulation boundaries** (§5.3.3, §7.3.4), with `inputData` /
  `inputDecisions` / `encapsulatedDecisions` / `outputDecisions`.
- **Cross-model reuse is normative**, via `Import` (§6.3.3). Bruce Silver: "it is common to
  save BKMs in a library and simply import them into any decision model that needs that bit
  of logic."

**"Tables do not nest or factor, so shared sub-conditions are re-entered by hand" is
simply false.** The DMN answer is: don't nest the table — _hoist_ the shared sub-condition
into its own Decision or BKM and invoke it.

#### (c) Where DMN's composition actually runs out

- **No recursion, by fiat.** §7.3.3: "a BusinessKnowledgeModel element **SHALL not require
  itself, directly or indirectly**." Same SHALLs for Decisions (§7.3.1) and Decision
  Services (§7.3.4). DMN's decision logic is a **DAG of first-order functions**. (FEEL
  function definitions are expressions — grammar rule 55 — and whether a BKM body may name
  _itself_ is unsettled; the KIE team implements recursion while conceding "the DMN
  specification does not explicitly support or forbid functions calling themselves by name."
  So: forbidden at the requirements level, unspecified at the expression level,
  vendor-dependent in practice.)

- **DMN is propositional at the variable level.** The sharpest limit, and it comes from
  DMN's own friends. Vandevelde, Aerts & Vennekens (cDMN):

  > "In logical terms, the 'variables' of standard DMN correspond to **constants (i.e.,
  > 0-ary functions)**. cDMN extends these by adding n-ary functions and n-ary relations."

  No quantification, no relations, no predicates over a domain. You cannot say "_every_
  upper-floor window in the side elevation". They measured the cost: on the DM Community
  benchmark, **33.3% of challenges need universal quantification** and **37.5% need
  constraints** — neither expressible in standard DMN.

- **No algebraic data types, no pattern matching, no parametric polymorphism, and no
  exhaustiveness obligation.** FEEL's own feature list (§10.1): "Side-effect free / Simple
  data model with numbers, dates, strings, lists, and contexts / Simple syntax designed for
  a wide audience / **Three-valued logic (true, false, null)**."

- **But FEEL _is_ a real language, and we must say so.** `if/then/else`, `for … in …
return`, `some … satisfies`, `every … satisfies`, filters, path expressions, `instance
of`, contexts, lists, and **first-class anonymous function values** (rule 55) — hence
  higher-order functions and currying, both demonstrated by the KIE team. The spec calls it
  "a simple language with inspiration drawn from Java, JavaScript, XPath, SQL, PMML,
  **Lisp**, and many others" (§10.3). Calling FEEL "just cell formulas" is not arguing in
  good faith.

---

### 2.3 Criticism 3 — "No obligations over time" → **true, and now citable — but scope, not defect**

Of course a table cannot express "must, within 30 days, else…". DMN models _decisions_;
lifecycle is BPMN's and CMMN's job, and our own document concedes this two sections earlier.
Aimed at DMN, the bullet attacks a claim nobody made.

**Good news: there is now a clean citation for the temporal gap**, from inside the DMN
research community. Callewaert & Vennekens (TPLP 2024), on payroll:

> "**the DMN notation has no notion of time and thus temporal properties cannot be expressed
> in standard DMN**"

— which is why they bolt on a Discrete Functional **Event Calculus**. Use that instead of
asserting it ourselves.

Concede also: FEEL _has_ date/time/duration types and arithmetic, so a DMN model can
_compute_ `application date + duration("P30D")` and _classify_ "is it overdue?". What it
cannot do is **hold the obligation as a state** — pending, then fulfilled or breached, with
a reparation on breach.

**The sharper point: the BPMN seam is an association, not a semantics.**

- The link is `usingProcesses` / `usingTasks` — bare associations (§6.3.6).
- Cross-model validation is **optional and referential**: "An implementation **MAY** perform
  validation over the two (BPMN and DMN) models, to check, for example, that: A Decision is
  not associated with Tasks that are part of Processes not also associated with the
  Decision…" (Annex A).
- The spec concedes the pairing does not connect them: "this approach allows the
  relationships … to be defined and validated, **but does not of itself permit the decisions
  modeled in DMN to be executed automatically by processes modeled in BPMN**."
- The mechanism that _does_ connect them — a decision service called from a BPMN task — is
  in **Annex A, which is non-normative**.

That "soundness of decision-aware business processes" had to be _invented as research_ is
the proof. Batoulis & Weske check exactly two criteria across the seam — **decision deadlock
freedom** (every producible decision output satisfies some outgoing edge) and **dead branch
absence** (every edge condition is satisfied by some producible output). Real cross-notation
checking, but purely **control-flow reachability**. Empirically, 30% of 86 real insurer
processes violated one. Nobody checks a _deontic_ property across the seam, because there is
no deontic vocabulary on either side of it.

In L4, `PARTY/MUST/WITHIN/HENCE/LEST` and `GIVEN…MEANS` are one language with one semantics,
so one property can quantify over both.

---

### 2.4 Criticism 4 — "Not solver-checkable across rules" → **the most wrong of the four**

#### (i) Intra-table checking is a 1962 invention

**Montalbano (1962)**, in the first issue of the _IBM Systems Journal_, advertises in its
abstract: "A method of verifying both the **completeness and consistency** of a problem
description is given." That is **fifty-three years before DMN 1.0**.

The lineage is continuous: King 1968 (ambiguity = overlapping rules) → Ibramsha & Rajaraman
1978 → **CODASYL 1982** (whose annotated bibliography runs to **545** decision-table
publications) → Pawlak 1987 (rough sets) → Vanthienen & Dries 1994 (PROLOGA) → Murrell &
Plant 1995 → **Hoover & Chen 1995** → Zaidi & Levis 1997 (Petri nets) → Vanthienen/Mues/Aerts
1998 → Hewett & Leuchner 2003.

**Hoover & Chen (1995)** is the most damaging to any "DMN-first" story: their tool checks
tables for consistency and completeness by reporting inputs with **no output or more than one
output** — Calvanese et al.'s two analysis tasks, twenty years early, **using variants of
binary decision diagrams**. And Calvanese et al. cite it themselves.

#### (ii) Inter-tabular checking is a 1998 invention

This is the buried lede, and it is the single best fact in this memo.

**Vanthienen, Mues, Wets & Delaere (1998), "A tool-supported approach to inter-tabular
verification"** (_Expert Systems with Applications_ 15(3–4):277–285) states the problem in
our exact terms:

> existing systems "fail to detect anomalies that occur over **rule chains** — in a decision
> table based context this means that anomalies that occur due to **interactions between
> tables** are neglected. These anomalies are called **inter-tabular anomalies**."

And PROLOGA already had **condition subtables** — one table's conclusion feeding another's
condition, with the inter-tabular relationships "visualised by means of a **directed
graph**." _That is a DRG, twenty years before DMN's._ It detected **circular chains across
tables** ("CAR(X) is in fact a condition subtable of EXTRA(X)… a circular chain is found")
and **isolated-table anomalies**. Vanthienen/Mues/Aerts (1998) give the two-axis taxonomy:
**{redundancy, ambivalence, circularity, deficiency} × {intra-tabular, inter-tabular}**.

Calvanese et al. (2016) list "extend to DRGs" as _future work_ and do not cite the
inter-tabular paper at all. **The field re-derived the DRG and then spent six years catching
back up to where decision-table V&V already was before DMN existed.**

#### (iii) And cross-DRD semantic verification is implemented — I was wrong

I drafted "nobody checks the DRG." That is **false**, and the correction matters.

**Theory.** Calvanese, Montali, Dumas & Maggi, _"Semantic DMN"_ (TPLP 19(4):536–573, 2019)
formalises whole DRGs as _Decision Knowledge Bases_, encodes them into the description logic
**`ALCH(D)`**, and defines genuinely DRG-level reasoning tasks — completeness **of the DRG**,
output coverage, output determinability, I/O relationship — reducing them to DL concept
unsatisfiability, **ExpTime-complete**. They are explicit that the point is the interaction:
"incompleteness may be caused by **internal mismatches between decision tables interconnected
via information requirements**." _But they never implemented it_: "**We plan to realize this
implementation**."

**Implementation.** Vandevelde, Callewaert & Vennekens, _"Context-Aware Verification of DMN"_
(**HICSS-55, 2022**) closes the loop. They relativise the correctness criteria to the rest of
the graph: table `Tⱼ` must cover every input assignment **that the conjunction of all other
tables plus background knowledge actually permits**. Compiled to FO(·), discharged with
**IDP-Z3 (Z3 SMT underneath)**. Their worked example is exactly the scenario we claim is
unreachable: a "Risk Level" table that is sound, complete and unfireable-free **in isolation**
has two dead rules once the upstream "BMI Level" table is considered —

> "This is an example in which the error **cannot be found by considering either table in
> isolation**: it can only be detected by looking at both tables together."

It is implemented, it pinpoints the offending rules, and it demonstrates that the
isolated-table tools produce both **false positives and false negatives**. It costs ~1245 ms
vs 287 ms.

So: cross-decision consistency checking is **solved in principle and demonstrated in
practice**. We must say so plainly.

#### (iv) Also note: the DMN literature _rejects_ the solver route, and has a reason

Calvanese et al. considered SMT and declined:

> "while using a general solver to analyze decision tables is an option (e.g., an SMT solver
> such as Z3), this approach leads to a boolean output (is the set of rules satisfiable?), and
> **cannot natively highlight specific sets of rules that need to be added (missing rules), nor
> specific overlaps between pairs of rules that need to be resolved**."

Their algorithms are **computational geometry** (iso-oriented hyper-rectangles, sweep-line
spatial join), not SAT/SMT — a distinction worth getting right, since we have been sloppy
about "solver" as a term of art. (HICSS-55 answers the objection: _their_ solver does return
the offending rules.)

---

### 2.5 So what is left of criticism 4? The S-FEEL pincer.

Everything above is confined to one fragment. **Every** result — Calvanese's geometry,
Semantic DMN's ExpTime, HICSS-55's SMT, Batoulis & Weske's soundness — is defined over
**S-FEEL**.

- IS 2018's own conclusion: "the algorithms proposed in this article are **limited to DMN
  decision tables where the expressions are written in S-FEEL** … future work to extend them
  to support more complex types of expressions supported in the more expressive FEEL version."
- Semantic DMN: S-FEEL, and **single-hit policies only** — "S-FEEL does not provide
  list-handling constructs … hence only single-hit policies combine well with S-FEEL within a
  DRG." So `Collect`/`C+` — the _aggregating_ tables — are out of scope entirely.
- Both Calvanese formalisations define the output entry as mapping to **an object** — a
  constant, not an expression. So **computed-output tables are outside the analysable fragment
  by construction**.
- The tools agree: KIE **skips gap and overlap analysis for `COLLECT`** and throws
  `DMNDTAnalysisException` on generalized unary tests; Trisotech's manual says "**When
  generalized unary tests are used, it is no longer possible to use DT Analysis.**"

Now read the DMN specification's own §9.1, verbatim:

> "**Experience with DMN since its release has shown that few if any complete decision models
> can be defined using S-FEEL.** Individual decision tables can be defined using only S-FEEL
> but within a decision model there is generally at least one decision that requires FEEL.
> **Developers and users are therefore encouraged to use and implement the full FEEL
> specification rather than the S-FEEL subset.**"

The standard, in its own voice, says the analysable fragment is inadequate for real models —
and tells you to use the fragment nothing can analyse.

**Independent corroboration of the boundary**, from a different group — de Leoni, Felli &
Montali (ER 2018) on data-aware process nets:

> "**In the general case, verifying soundness of DPNs is undecidable**, due to … the
> possibility of manipulating [case data] so as to reconstruct **Turing-powerful computational
> devices**… **We isolate here a decidable class** … expressive enough to capture data-aware
> process models equipped with **S-FEEL** DMN decisions."

The decidable island is _defined_ as the one that captures S-FEEL. Two independent groups,
same boundary.

**And the corroborating negative:** the one paper that handles **generic FEEL** — Della Penna
& Melatti (2025) on BPMN+DMN execution and verification — **abandons static verification
entirely**, compiling FEEL to Java and doing **guided-random testing with coverage analysis**.
Exactly what you would expect if full FEEL defeats static analysis.

⚠️ **One thing we must NOT claim.** The Semantic DMN authors assert FEEL "**is
Turing-powerful**" — but they assert it with **no proof and no citation**, and I could find no
published proof. Cite it as _a claim by the leading DMN-formalisation group, who confine their
own analysis to S-FEEL accordingly_. Do **not** write "FEEL analysis has been proven
undecidable." Nobody proved that.

#### The defensible restatement

> Decision-table analysis in DMN is **real, rigorous, and old** — intra-table since 1962,
> inter-tabular since 1998, and cross-DRD (SMT-backed) since 2022. But **all of it lives
> inside S-FEEL**, with constant outputs and single-hit policies — which excludes every table
> that _computes_. The DMN specification itself says S-FEEL is inadequate for real models and
> tells you to use full FEEL. **You can verify the DMN you would not write, and you cannot
> verify the DMN you would.** And in the field it is worse than that: of fourteen DMN tools
> surveyed, five support any verification at all, and the survey's own word for the industry's
> coverage is "**alarmingly low**."

---

## 3. The tools — what actually ships

Reading a vendor's word "overlap" tells you nothing; it means at least four different things
across these products.

| Tool                      | Gap                               | Overlap                   | Subsumption                                                | Cross-table?              | Technique                                  |
| ------------------------- | --------------------------------- | ------------------------- | ---------------------------------------------------------- | ------------------------- | ------------------------------------------ |
| **KIE / Drools / Kogito** | ✅                                | ✅                        | ✅ (subsumption, masked, misleading, contraction, 1NF/2NF) | **No**                    | **Geometric sweep**, not a solver          |
| **Trisotech**             | ✅                                | ✅                        | ✅                                                         | **No**                    | Same lineage as KIE; internals unpublished |
| **SAP Signavio**          | ✅                                | ✅                        | ✖                                                         | ✖                        | **Undisclosed** (still, ten years on)      |
| **Camunda**               | ❌                                | ❌                        | ❌                                                         | —                         | **Pure executor.** Linting is BPMN-only    |
| **dmn-check**             | ❌ none                           | ⚠️ _string-equality only_ | ✅ shadowed rules                                          | DRD _linter_ (acyclicity) | **Syntactic linter**                       |
| **Corticon**              | ✅ (auto-generates missing rules) | ✅                        | ✖                                                         | No                        | **Exhaustive cross-product enumeration**   |
| **OpenRules**             | ✅                                | ✅                        | ✖                                                         | ✅ **YES**                | ✅ **Solver (CSP, JSR-331)**               |
| **IBM ODM**               | ⚠️ _column-local only_            | ⚠️ _column-local only_    | ✖                                                         | No                        | Interval checks **within a column**        |
| **Oracle Business Rules** | ✅                                | ✅                        | ✖                                                         | Loop detection only       | Enumeration                                |
| _(research)_ **DMN-IDP**  | ✅                                | ✅                        | ✅ unfireable rules                                        | ✅ **semantic, DRD-wide** | ✅ **IDP-Z3 (SMT)**                        |

Receipts:

- **KIE's `DMNDTAnalyser`** runs `findGaps` → `findOverlaps` → `computeMaskedRules` →
  `computeMisleadingRules` → `computeSubsumptions` → `computeContractions` →
  `compute1stNFViolations` → `compute2ndNFViolations`. It is the Calvanese geometric algorithm
  implemented directly (`Bound`, `Interval`, `Hyperrectangle`), with **zero SMT/CSP
  dependency**. And `analyse()` iterates `findAllChildren(DecisionTable.class)` and analyses
  **each table in isolation**.
- **IBM ODM's** famous "gap and overlap" is far weaker than its reputation: gaps are evaluated
  "for all the entries in a **given column**, or within partitioned groups of cells" — does
  _one column's_ intervals tile its domain, not "is there an uncovered _combination_ of
  inputs."
- **`dmn-check`'s** `ConflictingRuleValidator` groups rules by
  `Collectors.groupingBy(::extractInputEntriesTextContent)` — **the literal text of the input
  cells**. It catches byte-identical rules; it will not notice that `[1..10]` overlaps
  `[5..15]`.
- **OpenRules** is the only _product_ that crosses table boundaries: "Automatic validation of
  conflicts between rules **across all decision tables**… Creates constraints that correspond
  to the rules defined **in all decision tables**", on a JSR-331 CP solver.
- **The Hasić/Corea RCIS 2020 "DRD-level" tool** — the standard citation for DRD verification —
  turns out to be **structural, not semantic**. Its six DRD checks are: missing input column,
  missing output column, idle data input, missing (data) input, multiple (data) input,
  inconsistent type. All interface/graph well-formedness. The empirical follow-up confirms real
  DRD errors are **synchronisation bugs** (delete an input on the diagram, forget it in the
  table), not logical contradictions.

**Linter vs solver, precisely.** The entire _industrial_ DMN ecosystem's analysis is _geometric
enumeration_ inherited from Calvanese et al. — sound on interval/enum unary tests, and failing
outright the moment a general FEEL expression appears (KIE throws; Trisotech greys the button
out). Only OpenRules ships a solver. The only _semantic_ DRD-wide checker (DMN-IDP) is a
research prototype. Nobody, anywhere, does temporal or deontic conflict detection.

---

## 4. Decision tables ↔ decision trees

Load-bearing: if tables and trees are inter-convertible, a criticism aimed at one lands on the
other.

**They are, and the literature is enormous and old.** A decision table denotes a _function_; a
tree is a **sequential evaluation procedure** for it, and building the tree means **choosing an
order in which to test the conditions** — an order the table leaves open.

- **Montalbano (1962)** shows it constructively: the same table yields a storage-optimal
  flowchart and a _different_ time-optimal one. His ordering heuristic — "Ask those questions
  first which will make the two differentiated groups of rule identifiers as similar in size as
  possible" — is an information-gain heuristic **24 years before ID3**.
- **Reinwald & Soland (1966, 1967)** optimise the _same_ conversion under two _different_
  objectives (min average processing time; min storage). Two trees, one table.
- **King & Johnson (1975)** — the money quote: a general method for converting a table "to a
  **sequential testing procedure represented as a tree** … but **leaves open the question of the
  production of optimum or near optimum trees related to particular criteria**."
- **Lew (1978)** computes "the **optimal order of testing**" by DP — order _is_ the decision
  variable.
- **Moret (1982)**, _Computing Surveys_: trees and diagrams are "**sequential evaluation
  procedures**", explicitly spanning "decision table programming".
- **Hyafil & Rivest (1976)**: choosing the _best_ order is **NP-complete** — and they name the
  application: "**The problem of compiling decision tables is one such application.**"
- And in the DMN era, **Calvanese et al. went the other way** to build their benchmark: "we
  trained decision trees … **We then translated each trained decision tree into a DMN table by
  mapping each path from the root to a leaf of the tree into a rule.**" They note such tables are
  automatically complete and non-overlapping — because root-to-leaf paths partition the space.

**Four cautions we must respect:**

1. **Say "function", not "Boolean function".** The Boolean reading holds only for _limited-entry_
   tables — which is exactly why the classical papers all say "limited-entry" in their titles.
   DMN tables have numeric ranges; Calvanese's semantics is geometric, not truth-assignments.
2. **Scope the order claim to _condition-test order_.** A table _does_ impose an order over
   **rules** under `First` and `Priority` hit policies. Our flat "tables are order-independent"
   is **false**. The true claim: _no table fixes the order in which the conditions are tested;
   every tree does._
3. **The equivalence presupposes verification.** An incomplete or ambiguous table denotes a
   _relation_, not a function. "Same function" is a theorem **about verified tables** — which
   makes verification the precondition for the equivalence, not a nicety.
4. **The directions are asymmetric.** Tree → table is trivial (each path becomes a rule). Table →
   tree is the hard direction, and optimally hard.

**Payoff:** a table and a tree denote the same function, but the tree — like a flowchart —
commits to a condition-test order the law does not impose. The table is the more faithful of the
two. **A flowchart is a tree with the order baked in and the sharing thrown away.**

---

## 5. Order, ROBDDs, and the part that cuts against us

> **⚠️ Status note (the working tree moved under me).** While I was researching, the doc was
> edited: the ladder's "order-independent" claim is **already fixed** ("its layout **carries no
> semantic order**"), and a three-order section — _denotation / text / asking questions_ — has
> **already been written**, at lines ~252–275. It is right, and it is better phrased than my
> draft was.
>
> **So this section is no longer a proposal. It is the citation apparatus for prose that already
> exists.** Everything below backs up what the doc now says. Nothing below asks you to change it.
> The one thing I would still add to the doc is a footnote or two from the list here — right now
> the three-order argument is asserted on its own authority, and it does not need to be: it has a
> thirty-year pedigree and a standards body agreeing with it.

We cannot say "imposing an order is bad", because **L4 deliberately imposes one**: the wizard
ranks questions by information gain over a hand-rolled ROBDD (`ts-shared/boolean-analysis/`).

The distinction the doc draws — three notions of order — is exactly the one the literature draws.

### The three orders

**1. Denotational order — there is none.** The statute denotes a function; `AND`/`OR` are
commutative. This is the only sense in which the flowchart's invented sequence is a _category
error_.

**2. Reading order — the order of the words on the page.** "(i) obscure-glazed, and (ii)
non-opening — unless…". Carries **no truth-conditional weight**, but is not arbitrary: it is
the drafter's, it is what the citation `(b)(ii)` _refers to_, and it is what a lawyer checks
the formalisation against.

This is a named, defended principle in AI & Law: **isomorphism**. Bench-Capon & Coenen (1992)
define it as "the well defined correspondence of the knowledge base to the source texts", and
adopt Karpf's conditions, the second of which is:

> "**The representation preserves the structure of each legal source.**"

with the core demand that "there is a clear correspondence between items to be found in the
source material and items to be found in the knowledge base… **Ideally there would be a one to
one correspondence**." Routen (1989) puts the rationale in one line: "**some of the essential
content of a statute is embodied in the organisation of the text.**"

**And they make exactly our point, with exactly our kind of example.** Bench-Capon & Coenen
take a source subsection `S1` — "_A person shall be P if, and only if, he is Q or R and S_" —
and its flattened Horn-clause rendering `S2`, and observe:

> "**Whilst S1 and S2 are logically equivalent, there may well have been a motive in choosing
> to express the conditions for Pness in the form of S1 rather than S2.** Attaining strict
> isomorphism would thus preclude the use of horn clauses and Prolog."

_Logical equivalence is not a licence to reorganise._ That is the whole argument for keeping
the statute's own AND/OR shape in the picture — which is what a ladder does and a flowchart
does not. Their prescribed fix is an **intermediate representation** with 1:1 correspondence to
the source, compiled 1:many to the executable form, so that one can "follow links from source
to executable knowledge base" — which is, incidentally, exactly L4's architecture.

Their case for it is **validation and maintenance**, not elegance: "the validator may well be
reluctant to go through the kind of intellectual contortions necessary to **recast the source
in a normal form**"; and "if the structures differ, the result is that a small change to the
problem may ramify throughout the program." And they hold the line even against bad drafting:
"**even an inconveniently structured piece of legislation should have its structure
respected**" — because that structure "is familiar and available to the validating experts and
potential users."

Sergot et al. (1986) yoked the same two benefits to structural resemblance six years before the
word was applied: Prolog "proved to be sufficiently high level so that **our implementation
could resemble the style and structure of the actual text of the act. Such a resemblance is
important because it helps increase confidence in the accuracy of the implementation and makes
the implementation easier to maintain as the legislation changes.**"

**3. Interrogation order — the order you ask the questions in.** Chosen, not given. L4 computes
it by **information gain**: `IG = H(prior) − E[H(posterior)]` over weighted model counts on the
ROBDD (`decision-query.ts`). That is Quinlan's ID3 entropy criterion applied to _interrogation_
rather than _classification_ — and Montalbano was doing a crude version in 1962, Shwayder an
explicit Shannon-theoretic one in 1971.

**And the AI & Law literature already insists (2) and (3) must not be conflated.** Karpf's fifth
condition demanded the system behave "in the order following the procedural rules". Bench-Capon
& Coenen **reject** it, precisely because

> "it appears to **conflate the representation with the manipulation of the representation which
> gives rise to system behaviour**."

That is our distinction, in print, in 1992. The representation keeps the text's order; the
_manipulation_ of it is a separate matter, free to be optimised.

**Bench-Capon & Gordon (ICAIL 2009) then state it outright** — this is the single best citation
for the whole taxonomy:

> "**The order of the clauses in Prolog programs, which determines the order in which clauses are
> tested and can therefore hide the existence of conflicting clauses, was considered, but was
> felt to be a problem rather than a feature, and it was normally recommended that the effect of
> the Prolog clauses should be made independent of the order of execution.** … **But, if the order
> of the sections in the legislation is significant, and has a conventional interpretation that is
> agreed by legal experts, this should be reflected in the representation.** … The emphasis on
> correspondence between sections of legislation and rules of the representation in traditional
> work on isomorphism **may need to be extended** to take note of such relations as well."

Evaluation order: "a problem rather than a feature," to be made semantically inert. Text order:
significant, conventionally interpreted, and it "should be reflected in the representation."
Exactly our (2)/(3) split — and they concede "in the original work on isomorphism **the order of
sections in the legislation was little discussed**," and invite the extension.

Sergot et al. (1986) supply the pragmatic half — order changes the _dialogue_, not the _logic_:

> "**The quality of this interactive dialogue is sensitive to the order in which the different
> rules for acquiring citizenship are written, and to the order of the conditions within
> individual rules.** Relatively little effort was put into adjusting these to improve the
> interaction."

That is our wizard's job description, written in 1986 and explicitly left undone.

### ⚠️ A terminology collision we must defuse, not walk into

**"Isomorphism" means two opposite things in the two literatures we are joining**, and this memo
has been using both within a few paragraphs:

- **Bryant's sense (graph theory):** two function graphs are _isomorphic_ if they match in
  structure and attributes. Reduction _merges isomorphic subgraphs_. Here isomorphism is a test
  for **semantic identity between two representations**.
- **AI & Law's sense (Karpf, Bench-Capon):** the formalisation is _isomorphic_ to the **source
  text**. Here isomorphism is a correspondence between **a representation and a document**.

Bench-Capon & Gordon flag this themselves, noting that isomorphism in AI and Law "differs from
standard mathematical usage." If the doc uses both senses it must say which is which, or pick one
word and paraphrase the other. **Recommendation:** in `logic-not-flowcharts.md`, say "the ladder
_mirrors the statute's structure_" (avoid the word) and reserve "isomorphic" for the graph sense
if it appears at all.

### What the ROBDD literature contributes

Bryant (1986), read in full:

- **Reduction is sharing.** _Definition 5:_ "A function graph `G` is **reduced** if it contains
  no vertex `v` with `low(v) = high(v)`, nor does it contain distinct vertices `v` and `v′` such
  that the subgraphs rooted by `v` and `v′` are **isomorphic**." Those are precisely the two
  rules our `mk()` implements. **The "R" in ROBDD is the merging of the isomorphic subtrees a
  decision tree duplicates.**
- **Canonicity.** _Theorem 1:_ "For any Boolean function `f`, there is a **unique** (up to
  isomorphism) reduced function graph denoting `f`, and any other function graph denoting `f`
  contains more vertices" — _given a fixed variable order_.
- **Order affects size, not meaning.** "For some functions, the size of the graph representing
  the function is **highly sensitive to this ordering**." His §3.2: `x₁x₂+x₃x₄+x₅x₆` and
  `x₁x₄+x₂x₅+x₃x₆` "differ from each other only by a permutation of their arguments, yet one is
  denoted by a function graph with **8 vertices** while the other requires **16**." Generalised:
  `x₁x₂+…+x₂ₙ₋₁x₂ₙ` needs **2n+2** vertices; the permuted `x₁xₙ₊₁+…+xₙx₂ₙ` needs **2ⁿ⁺¹**.
- **Choosing the order well is hard, but choosing it _correctly_ is free.** ⚠️ _Be precise here_ —
  it is easy to overclaim. Bryant's own 1986 aside that ordering-minimisation "is itself a
  **coNP-Complete** problem" is **historical, not the citable result**. The rigorous statement is
  **Bollig & Wegener (1996)**: given _an OBDD_ for `f` and a size bound `s`, deciding whether some
  ordering yields ≤ `s` nodes is **NP-complete**. Note the input is an **OBDD** (not a truth table
  or circuit) — that is what makes it a real hardness result rather than an encoding artifact. And
  say "**improving** the variable ordering of an OBDD is NP-complete", _not_ "finding the optimal
  order is NP-complete." The best _exact_ algorithm is Friedman & Supowit's **O(n²·3ⁿ)** DP;
  everyone in practice uses heuristics, or Rudell's **sifting** (ICCAD 1993).
- **Some functions are bad under every order.** Integer multiplication's middle bits are
  exponential "**regardless of the ordering**" (Bryant 1986's appendix proves a 2^(n/8) lower
  bound). So is the **hidden weighted bit** function, which Bryant (1991) proved exponential for
  _all_ variable orderings and which "seems to be the simplest function with exponential OBDD
  size" (Bollig, Löbbing, Sauerhoff & Wegener 1999).

Bryant's 1992 survey says it even more plainly. **This is the single best sentence in the whole
literature for our thesis** — Bryant, on ordering heuristics:

> "Note that these heuristics do not need to find the best possible ordering — **the ordering
> chosen has no effect on the correctness of the results.** As long as an ordering can be found
> that avoids exponential growth, operations on OBDDs remain reasonably efficient." (§1.3)

Supported by:

> "**In principle, the variable ordering can be selected arbitrarily — the algorithms will operate
> correctly for any ordering.** In practice, selecting a satisfactory ordering is critical for the
> efficient symbolic manipulation." (§1.2)
>
> "**The form and size of the OBDD representing a function depends on the variable ordering.**"
> (§1.3)

Order is a _performance_ parameter with **no truth-conditional content whatsoever**. That is
exactly the status the statute's reading order has — and exactly the status a flowchart's arrows
falsely deny it. Note too that Bryant 1992's Figure 2 is captioned, in terms: "**Reduction of
Decision Tree to OBDD.**" The DAG _is_ the reduced tree.

So the BDD literature says exactly what we need: **the order is a property of the
representation, not of the function.** One function, many graphs; the ordering indexes the
_graph_, never the _function_; canonicity holds only _relative to_ a fixed order. Permuting it
cannot change what the law means — it changes only how big the picture is and how many questions
you ask.

**And DMN itself makes the same partition, normatively** — which is a gift, because it means DMN
already concedes the principle we are arguing from. §8.2.10 splits the hit policies into
order-free (`Unique`, `Any`, `Priority` — "**Note that priorities are independent from rule
sequence**") and order-semantic (`First`, `Rule order` — "the meaning depends on the order of the
rules"). And on the order-semantic ones it delivers this verdict:

> "Because of this order, **the table is hard to validate manually and therefore has to be used
> with care.**"

DMN's own standard says order-dependent _meaning_ is bad for validation. That is precisely the
currency the isomorphism argument trades in: **keeping evaluation order semantically inert is
what frees the reading order to track the statute.**

Our own spec already draws the line, and the rewrite must not contradict it:

> "**BDD variable reordering / sifting.** The variable order … only affects diagram _size_, not
> which question a user is asked. … **This is the common conflation to avoid.**"
> — `specs/todo/QUESTION-ORDERING-SPEC.md`

### ⚠️ Prior art on the wizard — we are not first, and we must not be caught saying we are

This is outside the DMN brief, but it turned up while verifying the ROBDD citations and it bears
directly on what we may claim.

- **Aucher, Berbinau & Morin (2019), "Principles for a Judgement Editor Based on Binary Decision
  Diagrams"** (_Journal of Applied Logics_ 6(5):781–814), built with the **Cour de cassation** and
  IRISA: legal rules for a litigation type are compiled to a propositional formula and rendered as
  a **BDD whose nodes _are_ the questions put to the judge**. They add a "Multi-BDD" to reconcile
  substantive legal reasoning with the _procedural_ order imposed by trial protocol — which is our
  reading-order/interrogation-order tension, in a courtroom. **This is the closest existing work to
  L4's query-plan wizard, and it is close.** What they apparently do _not_ do is **optimise** the
  question order; they take the BDD's own structure as the interview order. That is the seam we
  actually occupy.
- **Shwayder (1974)**, "Extending the Information Theory Approach to Converting Limited-Entry
  Decision Tables to Computer Programs" (_CACM_ 17(9):532–537): **entropy-driven test ordering out
  of a decision table, in 1974.** "Information gain as the interrogation objective" is not new in
  the abstract — only in this setting. Say so first, and it becomes a pedigree instead of an
  ambush.
- **Mues & Vanthienen (2004)**, "Efficient Rule Base Verification Using Binary Decision Diagrams"
  (DEXA): the decision-table community itself reaching for BDDs to check rule-base anomalies. And
  Mues, Baesens, Files & Vanthienen (2004) state our DAG-vs-tree point in their own words —
  decision trees suffer "the **inherent replication of isomorphic subtrees**", whereas a decision
  diagram is "a rooted, acyclic digraph instead of a tree."
- **Hadzic, Andersen et al.** (Configit lineage) compile a rule base to a BDD offline and drive a
  **backtrack-free** interactive configurator off it — architecturally identical to a legal wizard.
- **Lamy et al. (2024)** solve "minimise questions asked given a rule base" end-to-end in medicine,
  **prove the question-ordering problem NP-hard**, and then find a _dumb frequency heuristic_ good
  enough. A sobering baseline we should beat, or explain why we don't need to.

**Two verified negatives**, both useful:

- Calvanese et al. contain **zero** occurrences of "BDD" / "decision diagram" — their method is
  purely geometric. **Nobody has applied BDDs to DMN.**
- A full-text search of _Artificial Intelligence and Law_ for "binary decision diagram" returns
  **zero**; DBLP title searches of ICAIL and JURIX return only _argument_ diagrams. **The AI & Law
  community has essentially never used BDDs.**

**The honest, strongest, still-true claim:** _model-counting information gain over a compiled ROBDD
as the next-question policy for a rules-as-code legal engine appears to be new; every ingredient is
old and well-cited; the nearest competitor is Aucher et al. (2019), which puts the questions on BDD
nodes but does not optimise their order._

And one caveat to state out loud rather than be caught on: ID3's gain is computed over an empirical
_sample_, to induce a classifier that generalises. Ours is computed over the **model count of a
known Boolean function**, to minimise expected questions — no sampling, no noise, exact counts. Same
criterion, different semantics for the probability. Said aloud, that is a strength.

### The flowchart's actual sin, restated

Not "it has an order." Everything that _evaluates_ a predicate has one. Its sin is that it
**conflates all three**:

- it is not the **denotation** (there is no order there);
- it is not the **reading order** (it linearises and re-sequences the AND/OR tree, so you can no
  longer check it against the statute);
- it is not a principled **interrogation order** (it is whatever the drawer happened to pick,
  fixed for every user forever);

— and it presents that invented order **as if it were the law's meaning**. Worse, being a
_tree_, it **duplicates** shared sub-conditions instead of sharing them — the very redundancy
the "R" in ROBDD exists to remove.

A ladder keeps (1) and (2) aligned — the picture is the statute's own structure, and it is a
**DAG**, so it shares sub-terms — and keeps (3) explicitly separate, in a wizard, where the
order is computed, optimisable, per-user, and arguable. **The order is never in the picture.**

---

## 6. What survives — the defensible list

1. **The analysable fragment ≠ the recommended fragment.** All decidable DMN analysis is
   S-FEEL, single-hit, constant-output. The spec says "few if any complete decision models can
   be defined using S-FEEL" and tells you to use full FEEL. The tables that _compute_ are the
   tables you _cannot verify_. ✅ **Our best claim.**
2. **DMN is propositional where law is quantified.** Variables are "constants (i.e. 0-ary
   functions)"; no relations, no quantifiers, no sum types, no exhaustiveness check. ✅ **Our
   best expressiveness claim.**
3. **DMN's composition is first-order and non-recursive by fiat** (three explicit SHALLs). ✅
4. **DMN decision tables are a two-level (DNF-like) normal form** — factoring must happen
   _outside_ the table, which is why the DRG exists. ✅
5. **There is no joint DMN+BPMN semantics**, so no deontic property can span the seam; and DMN
   "has no notion of time" (Callewaert & Vennekens). ✅
6. **Verification exists but is not shipped.** 5 of 14 tools do any; "alarmingly low"; the only
   semantic DRD-wide checker is a research prototype. ✅
7. **A flowchart is a tree with the condition-test order baked in and the sharing thrown away.** ✅

**Abandon entirely:** "no computation"; "no composition or sharing"; "`2ⁿ` rows"; "not
solver-checkable across rules"; "tables are order-independent"; "DMN has decision trees"; "the
ladder is order-independent"; and any suggestion that nobody can check across a DRD.

---

## 7. Suggested rewrite

### 7a. Sentence-level fixes elsewhere — **re-checked against the live file**

Line numbers are from the doc as it stands _now_ (it grew flowchart exhibits while I worked).

- ✅ **ALREADY FIXED — no action.** The ladder's "order-independent" claim (was §"The right
  pictures for logic") now reads "its layout **carries no semantic order**", followed by the
  three-order passage at ~L252–275. Nothing to do; see §5.
- ❌ **STILL WRONG — L342**, §"But some law really _is_ process": "DMN itself splits them —
  decision tables **and trees** for the logic, BPMN for the flow." → delete "and trees". **DMN
  standardises no tree notation**; the string "decision tree" occurs **zero** times in the DMN 1.3
  spec.
- ❌ **STILL WRONG — L378**, §"Decision tables" intro: "They are **order-independent** — a table
  is a truth table with actions." → True only of `Unique`/`Any`/`Priority` hit policies. `First`
  and `Rule order` are **rule-ordered**, and DMN says so: "the meaning depends on the order of the
  rules… the table is hard to validate manually and therefore has to be used with care" (§8.2.10).
  Suggested: "They are **order-free in the cases that matter** — under the default `Unique` hit
  policy a table is a truth table with actions, and DMN itself warns that the order-dependent hit
  policies are 'hard to validate'."
- ❌ **L395**: "So tables **and trees** are welcome as _views and inputs_" — fine to keep _if_ the
  trees are ours, not DMN's; but given the fix at L342, consider "tables and trees" → "tables".

### 7b. The new "Decision tables" section

```markdown
## Decision tables: the strongest rival, and where it runs out

Decision tables — standardised in **DMN** — are the serious alternative, and it is worth being
precise about how much they get right, because most of what is casually said against them is
false.

They compute. A rule's output entry is not a constant but a _FEEL expression_, so a fee schedule
can compute `base + excess × rate` in the cell — and the `Collect` hit policy will sum, min, max
or count across every matching rule. They factor, too: a `-` cell means "irrelevant", so a rule
is a _cube_, not a row of a truth table, and `(A ∧ B) ∨ (C ∧ D)` costs two rules, not sixteen.
And DMN is not "decision tables": above them sits the **Decision Requirements Graph**, where a
shared sub-condition becomes its own decision node and a **Business Knowledge Model** is a
genuine parameterised function, invoked by name from as many decisions as you like. The spec
calls this, in as many words, "the clear semantics of **functional composition**."

They are also _checkable_, and have been for sixty years. Completeness and consistency checking
of decision tables dates to Montalbano (1962); checking anomalies _across chains of linked
tables_ — circular dependencies, dead sub-tables — was in Vanthienen's PROLOGA by 1998; and the
modern DMN account (Calvanese et al., 2016) reads each rule as a hyper-rectangle and sweeps for
gaps and overlaps, shipping in Drools and Trisotech. There is even a research prototype that
discharges whole-graph consistency to an SMT solver and finds rules that are dead only _in
context_. Anyone who tells you DMN cannot be verified has not looked.

So the objection is not that DMN is weak. It is narrower, and it is structural.

- **What you can verify is not what you are told to write.** Every one of those results —
  Calvanese's geometry, the description-logic completeness proof, the SMT prototype — is defined
  over **S-FEEL**, DMN's restricted sub-language, with _constant_ outputs and _single-hit_
  policies. Which puts the computing tables — the fee schedules, the payout formulas, the
  `Collect`-and-sum benefit tables — outside the verifiable fragment _by construction_. Drools
  skips gap analysis for `Collect`; Trisotech's manual says flatly that "when generalized unary
  tests are used, it is no longer possible to use DT Analysis." And the DMN specification's own
  §9.1 says: "**few if any complete decision models can be defined using S-FEEL** … Developers
  and users are therefore encouraged to use … **full FEEL**." The standard tells you to write in
  the fragment its own verification literature cannot check. The one published system that does
  handle generic FEEL gives up on static analysis and resorts to random testing.

- **And in practice it is not even shipped.** A survey of fourteen DMN tools found five that
  support any verification capability at all, and called the industry's coverage "alarmingly
  low." The analysis that does ship is per-table: Drools' analyser walks the tables and examines
  each in isolation. But the interesting contradiction in a body of law is rarely inside one
  table — it is _between_ provisions.

- **The logic is propositional where law is quantified.** DMN's variables are, in the words of
  the researchers who set out to extend it, "constants (i.e. 0-ary functions)." There are no
  relations, no quantifiers, no sum types. You cannot say "_every_ upper-floor window in the side
  elevation", nor "_one of_ the following grounds applies, and no other" — and nothing tells you
  when a case has fallen between them. A third of the DMN community's own benchmark problems need
  quantification the notation cannot express.

- **Obligation is out of scope, and the seam is not sealed.** A table classifies; it cannot hold
  "must, within 30 days, else…" as a _state_. DMN never claimed it could — that is BPMN's job.
  But the standard joins them with an _association_, not a semantics: an implementation "**MAY**"
  validate across the two models, and the link "does not of itself permit the decisions modeled
  in DMN to be executed automatically by processes modeled in BPMN." With no shared semantics
  across the seam, no property can span a decision and the obligation it triggers — which is
  precisely the property a lawyer cares about. As one DMN research group puts it: "the DMN
  notation has no notion of time and thus temporal properties cannot be expressed in standard
  DMN."

None of this makes tables bad. It makes them an excellent **view** — one L4 should import and
emit. It makes them a poor **substrate**: the moment the logic gets real you are writing FEEL,
and at that point you have a language, just not one with quantifiers, recursion, sum types,
obligations, or a checker that can read it.
```

---

## 8. Bibliography

**[V]** = read the paper or its abstract at the primary source; confirms the claim.
**[P]** = bibliographic record verified (dblp/publisher) but full text not read.
**[U]** = could not verify — **do not cite**.

### The standard

- **[V]** OMG, _Decision Model and Notation (DMN), Version 1.3_, 2021.
  <https://www.omg.org/spec/DMN/1.3/PDF> — downloaded and grepped. All § numbers and quotes
  above are from it. Direct grep confirms: **"decision tree" occurs 0 times.**

### DMN formal semantics, analysis, verification

- **[V]** Calvanese, Dumas, Laurson, Maggi, Montali, Teinemaa, "Semantics and Analysis of DMN
  Decision Tables", **BPM 2016**, LNCS 9850, 217–233.
  DOI [10.1007/978-3-319-45348-4_13](https://doi.org/10.1007/978-3-319-45348-4_13); arXiv
  [1603.07466](https://arxiv.org/abs/1603.07466). _Read in full._ S-FEEL; **single table**;
  hyper-rectangle sweep; gap/overlap/masked-rule detection; Conclusion names DRGs as **future
  work**.
  ⚠️ _Citation trap:_ arXiv has **10** references; the LNCS camera-ready has **13** (adding
  Hewett & Leuchner, Hoover & Chen, Zaidi & Levis). **Cite the LNCS version.**
- **[V]** Calvanese, Dumas, Laurson, Maggi, Montali, Teinemaa, "Semantics, Analysis and
  Simplification of DMN Decision Tables", **Information Systems** 78:112–125, 2018.
  DOI [10.1016/j.is.2018.01.010](https://doi.org/10.1016/j.is.2018.01.010). Adds **rule merging /
  simplification**. Still single-table, still S-FEEL — its conclusion says so explicitly.
- **[V]** Calvanese, **Montali**, **Dumas**, **Maggi**, "Semantic DMN: Formalizing and Reasoning
  About Decisions in the Presence of Background Knowledge", **TPLP 19(4):536–573, 2019**.
  DOI [10.1017/S1471068418000479](https://doi.org/10.1017/S1471068418000479); arXiv
  [1807.11615](https://arxiv.org/abs/1807.11615). _Read in full._ **The cross-DRG theory paper.**
  DRG + ontology → `ALCH(D)`; DRG-level completeness, output coverage, output determinability;
  **ExpTime-complete**. S-FEEL only; **single-hit only**; **never implemented** ("We plan to
  realize this implementation").
  ⚠️ **There is no Laurson on this paper.** Earlier version: RuleML+RR 2017, LNCS 10364,
  DOI [10.1007/978-3-319-61252-2_6](https://doi.org/10.1007/978-3-319-61252-2_6).
- **[V]** ⭐ **Vandevelde, Callewaert, Vennekens, "Context-Aware Verification of DMN", HICSS-55,
  2022**, pp. 6239–6246.
  [AISeL](https://aisel.aisnet.org/hicss-55/os/business_rule/3/) ·
  [PDF](https://lirias.kuleuven.be/server/api/core/bitstreams/db5875be-5062-475f-804f-0876e759f215/content).
  **The paper that refutes "nobody checks the DRD."** Relativises completeness/unfireable-rule
  checks to all other tables + background knowledge; DMN → FO(·) → **IDP-Z3 (Z3 SMT)**;
  implemented; demonstrates a table that is clean in isolation and has two dead rules in context.
  Limitation stated by the authors: FO(·) is undecidable in general, so domains must be
  restricted.
- **[V]** Hasić, **Corea**, Blatt, Delfmann, Serral, "A Tool for the Verification of Decision
  Model and Notation (DMN) Models", **RCIS 2020**, LNBIP 385, 536–542.
  DOI [10.1007/978-3-030-50316-1_35](https://doi.org/10.1007/978-3-030-50316-1_35). Source of "the
  DRD-level has been **strongly neglected**". ⚠️ **Mendling and Nagel are not authors.** ⚠️ Its
  six DRD checks are **structural** (missing/extra columns, idle inputs, type mismatch), **not
  semantic** — built on Camunda + custom graph algorithms, **no solver**.
- **[V]** Grohé, Corea, Delfmann, "DMN 1.0 Verification Capabilities: An Analysis of Current Tool
  Support", **BPM Forum 2021**, LNBIP 427, 37–53.
  DOI [10.1007/978-3-030-85440-9_3](https://doi.org/10.1007/978-3-030-85440-9_3). 14 tools; only
  **5** support any verification (DMN-Check, FICO, Flowable, Signavio, Trisotech); Signavio 15/26,
  Trisotech 11/26; Camunda none; coverage "**alarmingly low**".
- **[P]** Corea, Kampik, Delfmann, "Empirical Evidence of DMN Errors in the Wild — An SAP Signavio
  Case Study", **BPM 2023 Workshops**, LNBIP 492, 326–336.
  DOI [10.1007/978-3-031-50974-2_25](https://doi.org/10.1007/978-3-031-50974-2_25). 5,668 real
  models; **36.1%** contained some issue. Source of the "**26 error types**" taxonomy split across
  decision-table / DRD / DMN+BPMN levels. _(Full text paywalled; the count is PARTIAL.)_
- **[V]** Batoulis & Weske, "Soundness of Decision-Aware Business Processes", **BPM Forum 2017**,
  LNBIP 297, 106–124. DOI [10.1007/978-3-319-65015-9_7](https://doi.org/10.1007/978-3-319-65015-9_7);
  demo at CEUR [Vol-1920](https://ceur-ws.org/Vol-1920/BPM_2017_paper_184.pdf) _(read)_. Two
  criteria across the BPMN/DMN seam: **decision deadlock freedom**, **dead branch absence**. 30% of
  86 real insurer processes violated one.
- **[V]** de Leoni, Felli, Montali, "A Holistic Approach for Soundness Verification of
  Decision-Aware Process Models", **ER 2018**, 219–235; arXiv
  [1804.02316](https://arxiv.org/abs/1804.02316). **Independent corroboration of the S-FEEL
  boundary**: DPN soundness is undecidable in general ("Turing-powerful computational devices");
  the decidable class they isolate is the one that "capture[s] data-aware process models equipped
  with **S-FEEL** DMN decisions."
- **[P]** Della Penna & Melatti, "Automating Execution and Verification of BPMN+DMN Business
  Processes", arXiv [2512.15214](https://arxiv.org/abs/2512.15214), 2025. The one paper handling
  **generic FEEL** — and it **abandons static verification**, compiling FEEL to Java and doing
  **guided-random testing**.
- **[V]** Vandevelde, Aerts, Vennekens, **cDMN** — RuleML+RR 2020 (Best Paper),
  DOI [10.1007/978-3-030-57977-7_2](https://doi.org/10.1007/978-3-030-57977-7_2); extended in
  **TPLP** 2021, arXiv [2110.02610](https://arxiv.org/abs/2110.02610). _Read._ Source of "the
  'variables' of standard DMN correspond to **constants (i.e., 0-ary functions)**" and of the DM
  Community statistics (33.3% universal quantification; 37.5% constraints).
- **[V]** Callewaert & Vennekens, "Answer Set Programming for Flexible Payroll Management",
  **TPLP** 2024, arXiv [2403.12823](https://arxiv.org/abs/2403.12823). Source of "**the DMN
  notation has no notion of time and thus temporal properties cannot be expressed in standard
  DMN**"; adds a Discrete Functional Event Calculus.
- **[P]** Laurson & Maggi, "A Tool for the Analysis of DMN Decision Tables", **BPM Demos 2016**,
  CEUR [Vol-1789](https://ceur-ws.org/Vol-1789/bpm-demo-2016-paper11.pdf). The dmn-js
  implementation. Zero occurrences of "DRD"/"DRG" — purely single-table.

### Classical decision-table literature (all predating DMN)

- **[V]** **Montalbano, M., "Tables, Flow Charts, and Program Logic", _IBM Systems Journal_
  1(1):51–63, 1962.**
  <http://bitsavers.org/pdf/ibm/IBM_Systems_Journal/011/ibmsj0101E.pdf>. **The origin.** Abstract:
  "a method of verifying both the **completeness and consistency** of a problem description";
  storage- vs time-optimal conversion; a balance/entropy ordering heuristic.
- **[V]** ⭐ **Vanthienen, Mues, Wets, Delaere, "A tool-supported approach to inter-tabular
  verification", _Expert Systems with Applications_ 15(3–4):277–285, 1998.**
  DOI [10.1016/S0957-4174(98)00047-5](<https://doi.org/10.1016/S0957-4174(98)00047-5>).
  **The buried lede.** Anomalies "**due to interactions between tables**"; **inter-tabular
  anomalies**; circular chains across linked tables. _Not cited by Calvanese et al. 2016._
- **[V]** Vanthienen, Mues, Aerts, "An illustration of verification and validation in the modelling
  phase of KBS development", **DKE** 27(3):337–352, 1998.
  DOI [10.1016/S0169-023X(98)80003-7](<https://doi.org/10.1016/S0169-023X(98)80003-7>). _Read._
  Two-axis taxonomy: **{redundancy, ambivalence, circularity, deficiency} × {intra-tabular,
  inter-tabular}**; condition subtables visualised as a **directed graph**.
- **[V]** Vanthienen & Dries, "Illustration of a decision table tool…" (**PROLOGA**), _Int. J. AI
  Tools_ 3(2):267–288, 1994.
  DOI [10.1142/S0218213094000133](https://doi.org/10.1142/S0218213094000133).
- **[V]** Hoover & Chen, "Tablewise, a decision table tool", **COMPASS 1995**, 97–108.
  DOI [10.1109/CMPASS.1995.521890](https://doi.org/10.1109/CMPASS.1995.521890). Completeness +
  consistency via **variants of binary decision diagrams** — a nice historical rhyme with our
  ROBDD.
- **[V]** Pollack, "Conversion of limited-entry decision tables to computer programs", **CACM**
  8(11):677–682, 1965. DOI [10.1145/365660.365681](https://doi.org/10.1145/365660.365681).
- **[V]** Reinwald & Soland, "…to Optimal Computer Programs I: Minimum Average Processing Time",
  **JACM** 13(3):339–358, 1966.
  DOI [10.1145/321341.321343](https://doi.org/10.1145/321341.321343); **II: Minimum Storage
  Requirement**, JACM 14(4):742–756, 1967.
  DOI [10.1145/321420.321433](https://doi.org/10.1145/321420.321433).
- **[V]** King, P.J.H., "Ambiguity in Limited Entry Decision Tables", **CACM** 11(10):680–684,
  **1968**. DOI [10.1145/364096.364113](https://doi.org/10.1145/364096.364113). _(CACM, 1968 — not
  the Computer Journal, not the 1970s.)_
- **[V]** King & Johnson, "The conversion of decision tables to sequential testing procedures",
  **Computer Journal** 18(4):298–306, 1975.
  DOI [10.1093/comjnl/18.4.298](https://doi.org/10.1093/comjnl/18.4.298).
- **[V]** Shwayder, "…a proposed modification to Pollack's algorithm", **CACM** 14(2):69–73, 1971.
  DOI [10.1145/362515.362518](https://doi.org/10.1145/362515.362518). Shannon-entropy ordering
  heuristic.
- **[V]** Verhelst, "The conversion of limited-entry decision tables to optimal and near-optimal
  flowcharts", **CACM** 15(11):974–980, 1972.
  DOI [10.1145/355606.361883](https://doi.org/10.1145/355606.361883).
- **[P]** Lew, "Optimal conversion of extended-entry decision tables with general cost criteria",
  **CACM** 21(4):269–279, 1978. DP over "the optimal order of testing."
- **[V]** Pooch, "Translation of Decision Tables", **ACM Computing Surveys** 6(2):125–151, 1974.
  DOI [10.1145/356628.356630](https://doi.org/10.1145/356628.356630). The contemporaneous survey.
- **[V]** Moret, "Decision Trees and Diagrams", **ACM Computing Surveys** 14(4):593–623, 1982.
  DOI [10.1145/356893.356898](https://doi.org/10.1145/356893.356898). Trees/diagrams as
  "**sequential evaluation procedures**"; spans decision-table programming.
- **[V]** Hyafil & Rivest, "Constructing Optimal Binary Decision Trees is NP-Complete", **IPL**
  5(1):15–17, 1976.
  DOI [10.1016/0020-0190(76)90095-8](<https://doi.org/10.1016/0020-0190(76)90095-8>).
  ⚠️ _Be precise:_ the theorem is about **identification** (min expected tests to identify an
  unknown object). It is legitimate to cite for decision tables **only because the authors say
  so**: "The problem of compiling decision tables is one such application." Quote that clause.
- **[V]** CODASYL Decision Table Task Group, _A Modern Appraisal of Decision Tables_, ACM, 1982.
  Annotated bibliography of **545** decision-table publications. The one citation for "this field
  is old."
- **[V]** Zaidi & Levis, "Validation and verification of decision making rules", **Automatica**
  33(2):155–169, 1997.
  DOI [10.1016/S0005-1098(96)00165-3](<https://doi.org/10.1016/S0005-1098(96)00165-3>). Petri-net
  encoding; rule _chains_ are first-class.
- **[V]** Murrell & Plant, "Decision tables: formalisation, validation and verification", **STVR**
  5(2):107–132, 1995. DOI [10.1002/stvr.4370050204](https://doi.org/10.1002/stvr.4370050204).
- **[V]** Hewett & Leuchner, "Restructuring decision tables for elucidation of knowledge", **DKE**
  46(3):271–290, 2003.
- **[P]** Pawlak, "Decision tables — a rough set approach", **Bull. EATCS** 33:85–95, 1987.
  _(Page range cited inconsistently as 85–95 / 85–96; no DOI. This is the 1987 bulletin article,
  not the 1991 book.)_
- **[P]** Metzner & Barnes, _Decision Table Languages and Systems_, ACM Monograph Series, Academic
  Press, 1977. _(Existence/metadata only.)_

### BDDs and variable ordering

- **[V]** **Bryant, R.E., "Graph-Based Algorithms for Boolean Function Manipulation", _IEEE Trans.
  Computers_ C-35(8):677–691, 1986.**
  DOI [10.1109/TC.1986.1676819](https://doi.org/10.1109/TC.1986.1676819) ·
  <https://www.cs.cmu.edu/~bryant/pubdir/ieeetc86.pdf>. _Read in full._ Definition 5 (reduced = no
  redundant vertex, no two isomorphic subgraphs); Theorem 1 (canonicity given a fixed order);
  "the size of the graph … is **highly sensitive to this ordering**"; ordering minimisation is
  **coNP-complete**; Figure 2's 8-vs-16-vertex permutation example; integer multiplication
  exponential **under every order**.
- **[V]** Bollig & Wegener, "Improving the Variable Ordering of OBDDs is NP-Complete", _IEEE Trans.
  Computers_ 45(9):993–1002, 1996. Given an OBDD for `f` and a size bound `s`, deciding whether
  some ordering yields ≤ `s` nodes is **NP-complete**.
- **[V]** Bryant, "Symbolic Boolean Manipulation with Ordered Binary-Decision Diagrams", _ACM
  Computing Surveys_ 24(3):293–318, 1992.
  DOI [10.1145/136035.136043](https://doi.org/10.1145/136035.136043). _Read._ **The cleanest
  statement of order-as-representation:** "In principle, the variable ordering can be selected
  arbitrarily — the algorithms will operate correctly for any ordering" (§1.2); "The form and size
  of the OBDD representing a function depends on the variable ordering" (§1.3).
- **[V]** Rudell, "Dynamic Variable Ordering for Ordered Binary Decision Diagrams", **ICCAD 1993**,
  42–47. DOI [10.1109/ICCAD.1993.580029](https://doi.org/10.1109/ICCAD.1993.580029). Introduces
  **sifting** — _the_ standard dynamic-reordering reference.
- **[V]** Friedman & Supowit, "Finding the Optimal Variable Ordering for Binary Decision Diagrams",
  _IEEE Trans. Computers_ 39(5):710–713, 1990.
  DOI [10.1109/12.53586](https://doi.org/10.1109/12.53586). Exact DP in **O(n²·3ⁿ)** (vs naïve
  O(n!·2ⁿ)); needs the truth table, so Ω(2ⁿ) space. _(Complexity figure attributed from the indexed
  abstract, not eyeballed in the full text.)_
- **[V]** Bryant, "On the Complexity of VLSI Implementations and Graph Representations of Boolean
  Functions with Application to Integer Multiplication", _IEEE Trans. Computers_ 40(2):205–213, 1991. DOI [10.1109/12.73590](https://doi.org/10.1109/12.73590). Introduces the **hidden weighted
  bit** function and proves exponential OBDD size **under every ordering**.
- **[V]** Bollig, Löbbing, Sauerhoff & Wegener, "On the Complexity of the Hidden Weighted Bit
  Function for Various BDD Models", _RAIRO — Theor. Inf. and Appl._ 33(2):103–115, 1999.
  <https://www.numdam.org/item/ITA_1999__33_2_103_0/> (open access). _Read._ The citable secondary
  source: HWB "seems to be the simplest function with exponential OBDD size", and "Bryant has
  proved that its OBDD size is **exponential for all variable orderings**."
- **[P]** Wegener, _Branching Programs and Binary Decision Diagrams_, SIAM, 2000. ISBN
  978-0-89871-458-6. DOI [10.1137/1.9780898719789](https://doi.org/10.1137/1.9780898719789).

### ⭐ Prior art on the query-plan wizard — engage with these, do not be ambushed

- **[V]** ⭐ **Aucher, Berbinau & Morin, "Principles for a Judgement Editor Based on Binary Decision
  Diagrams", _Journal of Applied Logics — IfCoLog_ 6(5):781–814, 2019.**
  <https://dblp.org/rec/journals/flap/AucherBM19.html> · HAL
  <https://inria.hal.science/hal-02273483>. **The closest existing work to L4's query-plan wizard.**
  Built with the **Cour de cassation**/IRISA: legal rules → propositional formula → **BDD whose
  nodes are the questions put to the judge**; a "Multi-BDD" reconciles substantive reasoning with
  the _procedural_ order of trial protocol. Apparently **does not optimise** the question order —
  which is precisely our contribution.
- **[V]** ⭐ **Shwayder, K., "Extending the Information Theory Approach to Converting Limited-Entry
  Decision Tables to Computer Programs", _CACM_ 17(9):532–537, 1974.**
  DOI [10.1145/361147.361117](https://doi.org/10.1145/361147.361117). **Entropy-driven test
  ordering from a decision table, in 1974** — the direct ancestor of our information-gain policy.
  Cite it _first_, and the pedigree becomes an asset.
- **[V]** Mues & Vanthienen, "Efficient Rule Base Verification Using Binary Decision Diagrams",
  **DEXA 2004**, LNCS 3180, 445–454.
  DOI [10.1007/978-3-540-30075-5_43](https://doi.org/10.1007/978-3-540-30075-5_43). The
  decision-table community (PROLOGA, and a DMN author) reaching for **BDDs to check rule-base
  anomalies**.
- **[V]** Mues, Baesens, Files & Vanthienen, "Decision diagrams in machine learning…", _Expert
  Systems with Applications_ 27(2):257–264, 2004.
  DOI [10.1016/j.eswa.2004.02.001](https://doi.org/10.1016/j.eswa.2004.02.001). States our
  DAG-vs-tree point in their own words: decision trees suffer "the **inherent replication of
  isomorphic subtrees**"; a decision diagram is "a rooted, acyclic digraph instead of a tree."
  _(Abstract PARTIAL — Elsevier 403.)_
- **[V]** Vanthienen & Robben, "Developing legal knowledge based systems using decision tables",
  **ICAIL 1993**, 282–291. DOI [10.1145/158976.159011](https://doi.org/10.1145/158976.159011). The
  AI&Law-side ancestor: legal KBS on decision tables + PROLOGA, with verification built in.
- **[V]** Hadzic, Subbarayan, Jensen, Andersen, Møller & Hulgaard, "Fast Backtrack-Free Product
  Configuration using a Precompiled Solution Space Representation", **PETO 2004**, 133–140.
  Compile the rule base to a BDD offline; drive a **backtrack-free** interview off it —
  architecturally identical to a legal wizard. (Spun out as Configit.) Companion: Andersen, Hadzic
  & Pisinger, "Interactive Cost Configuration Over Decision Diagrams", _JAIR_ 37:99–139, 2010,
  DOI [10.1613/jair.2905](https://doi.org/10.1613/jair.2905).
- **[V]** Golovin & Krause, "Adaptive Submodularity…", _JAIR_ 42:427–486, 2011.
  <https://www.jair.org/index.php/jair/article/view/10731>. Supplies the **near-optimality guarantee
  for greedy** max-information question selection — the citation our spec's "near-optimal" claim
  currently lacks.
- **[V]** Ünlüyurt, "Sequential testing of complex systems: a review", _Discrete Applied Math_
  142(1–3):189–205, 2004.
  DOI [10.1016/j.dam.2002.08.001](https://doi.org/10.1016/j.dam.2002.08.001). The survey of the
  field our next-question policy formally belongs to.
- **[V]** ⚠️ Lamy et al., "Adaptive questionnaires for facilitating patient data entry in clinical
  decision support systems", _BMC Med. Inform. Decis. Mak._ 24:326, 2024.
  DOI [10.1186/s12911-024-02742-6](https://doi.org/10.1186/s12911-024-02742-6). Solves
  "minimise questions asked given a rule base" end-to-end; **proves the question-ordering problem
  NP-hard**; and then finds a _dumb frequency heuristic_ good enough. **A sobering baseline — we
  should beat it or explain why we needn't.**
- **[V]** Raimondi & Lomuscio, "Automatic verification of multi-agent systems by model checking via
  OBDDs", _J. Applied Logic_ 5(2):235–251, 2007.
  DOI [10.1016/j.jal.2005.12.010](https://doi.org/10.1016/j.jal.2005.12.010). OBDD-based model
  checking of **deontic** systems (obligation, violation states).

### Two verified negatives — both usable in a related-work section

- **[V]** **Nobody has applied BDDs to DMN.** Full-text search of Calvanese et al. (both the BPM
  2016 and IS 2018 versions) for "binary decision diagram" / "BDD" / "OBDD" / "decision diagram"
  returns **zero occurrences**. Their method is purely geometric (hyper-rectangles + sweep-line).
- **[V]** **The AI & Law community has essentially never used BDDs.** Full-text search of the
  journal _Artificial Intelligence and Law_ for "binary decision diagram" returns **zero**; DBLP
  title searches of ICAIL and JURIX return only _argument_ diagrams and Aristotelian diagrams. The
  three exceptions found anywhere are Aucher et al. 2019, Gasiola 2025 (_Computer Law & Security
  Review_ 58:106189, DOI [10.1016/j.clsr.2025.106189](https://doi.org/10.1016/j.clsr.2025.106189) —
  the EU AI Act's risk classification as a BDD, conceptual not compiled), and Mues & Vanthienen
  2004 — **in three different communities, none citing the others.**

### Isomorphism in legal KR

- **[V]** **Bench-Capon & Coenen, "Isomorphism and legal knowledge based systems", _Artificial
  Intelligence and Law_ 1(1):65–86, 1992.**
  DOI [10.1007/BF00118479](https://doi.org/10.1007/BF00118479) ·
  <https://cgi.csc.liv.ac.uk/~tbc/publications/AILawIsomorphism.pdf>. _Read._ Isomorphism = "the
  well defined correspondence of the knowledge base to the source texts". Adopts Karpf's
  conditions incl. "**The representation preserves the structure of each legal source**" and the
  demand for "**a one to one correspondence**". **Rejects** Karpf's fifth (execution-order)
  condition because it "conflate[s] **the representation with the manipulation of the
  representation** which gives rise to system behaviour" — i.e. reading order ≠ interrogation
  order, stated in 1992.
- **[V]** ⭐ **Bench-Capon, T.J.M. & Gordon, T.F., "Isomorphism and Argumentation", ICAIL 2009,
  11–20.** DOI [10.1145/1568234.1568237](https://doi.org/10.1145/1568234.1568237) ·
  <https://intranet.csc.liv.ac.uk/~tbc/publications/ICAILTom.pdf>. **The single best citation for
  the reading-order ≠ evaluation-order distinction**, stated explicitly in §4.3: Prolog clause
  order is "a problem rather than a feature" and the representation should be "made independent of
  the order of execution"; but the order of _sections_ "is significant, and has a conventional
  interpretation … this should be reflected in the representation." Also concedes the gap we want
  to fill: "in the original work on isomorphism **the order of sections in the legislation was
  little discussed**," and that the theory "may need to be extended." Also flags that AI&Law
  isomorphism "differs from standard mathematical usage."
- **[V]** Sergot, Sadri, Kowalski, Kriwaczek, Hammond, Cory, "The British Nationality Act as a
  Logic Program", **CACM** 29(5):370–386, 1986.
  DOI [10.1145/5689.5920](https://doi.org/10.1145/5689.5920) ·
  <https://www.doc.ic.ac.uk/~rak/papers/British%20Nationality%20Act.pdf>. _Read._ Structural
  resemblance → "confidence in the accuracy of the implementation" + "easier to maintain as the
  legislation changes." And, for our three-order taxonomy: "the quality of this interactive
  dialogue **is sensitive to the order in which the different rules … are written**" — order
  changes the dialogue, not the logic.
  ⚠️ **Do not cite BNA as an exemplar of isomorphism.** Bench-Capon & Coenen say it "was **not
  necessarily supposed to reflect the structure of these sources**," and the paper itself admits
  later sections "require a more drastic restructuring." Cite it for the _rationale_, not the
  _achievement_.
- **[P]** Routen, T., "Hierarchically Organised Formalisations", **ICAIL 1989**, 242–250.
  DOI [10.1145/74014.74045](https://doi.org/10.1145/74014.74045). Source of the slogan "**some of
  the essential content of a statute is embodied in the organisation of the text**" — _verified as
  quoted in Bench-Capon & Coenen 1992, not read in the original._
- **[P]** Karpf, J., "Quality Assurance of Legal Expert Systems", Jurimatics, Copenhagen Business
  School, 1989. The five conditions. **Grey literature — I could not find the original.** Quoted
  verbatim and identically in two independent published sources 17 years apart, so the content is
  safe; but ⚠️ the issue number is cited inconsistently (No 8 vs No 2). **Cite it _via_
  Bench-Capon.**
- **[P]** ⚠️ **Routen, T., "On isomorphic formalisations", _Artificial Intelligence and Law_
  4(2):113–132, 1996.** DOI [10.1007/BF00116788](https://doi.org/10.1007/BF00116788). **THE
  COUNTER-CITE — know it before a reviewer does.** The same Routen who supplied the slogan later
  argued that isomorphism's requirements "have odd consequences" that "undermine the very idea of
  formalisation," amounting to "a reductio ad absurdum of the idea of formalising statute law."
  _(Publisher abstract only; full text bot-blocked. Verify before characterising it further.)_
- **[P]** Allen, L.E. & Saxon, C.S., "More IA Needed in AI…", **ICAIL 1991**, 53–61.
  DOI [10.1145/112646.112652](https://doi.org/10.1145/112646.112652). The natural foil: Allen's
  "normalization" programme _rewrites_ law into normal form — the anti-isomorphic position.

### Decision-tree induction

- **[V]** Quinlan, "Induction of Decision Trees", **Machine Learning** 1(1):81–106, 1986.
  DOI [10.1007/BF00116251](https://doi.org/10.1007/BF00116251). Information-gain split criterion.
- **[P]** Quinlan, _C4.5_, Morgan Kaufmann, 1993. **[P]** Breiman et al., _CART_, Wadsworth, 1984.
  ⚠️ _Wording caution:_ ID3/CART induce a tree **from data**, approximating an unknown function;
  the decision-table literature is given the function **exactly**. Say "the split order is an
  artifact of the induction procedure, not of the function represented." Do **not** say ID3
  "converts a table to a tree."

### Tool documentation (all fetched; quoted in §3)

- **[V]** Apache KIE/Drools `DMNValidator.java`, `DMNDTAnalyser.java` —
  <https://github.com/apache/incubator-kie-drools/tree/main/kie-dmn/kie-dmn-validation>
- **[V]** Drools DMN docs (`ANALYZE_DECISION_TABLE`) —
  <https://docs.drools.org/latest/drools-docs/drools/DMN/index.html>
- **[V]** Trisotech help — "When generalized unary tests are used, it is no longer possible to use
  DT Analysis." <https://cloud.trisotech.com/help/decision-modeler/decision-table.html>
- **[V]** Camunda DMN engine (executor only) —
  <https://docs.camunda.org/manual/latest/user-guide/dmn-engine/>
- **[V]** `red6/dmn-check` — <https://github.com/red6/dmn-check>
- **[V]** OpenRules Rule Solver manual (JSR-331 CSP; "across all decision tables") —
  <https://openrules.com/pdf/RulesSolver.UserManual.pdf>
- **[V]** Progress Corticon Completeness/Conflict Checkers —
  <https://documentation.progress.com/output/Corticon/5.7.2/html/corticon/the-completeness-checker.html>
- **[V]** IBM ODM decision-table checks (column-local) —
  <https://www.ibm.com/docs/en/odm/8.10?topic=verification-decision-table-checks>
- **[V]** Bruce Silver, "Why Does DMN Have BKMs?" — <https://methodandstyle.com/blog/why-bkms/>
- **[V]** KIE blog, "Functional Programming in DMN" (recursion, currying; "the DMN specification
  does not explicitly support or forbid functions calling themselves by name") —
  <https://blog.kie.org/2020/04/functional-programming-in-dmn-it-feels-like-recursing-my-university-studies-again.html>

### Rules as Code — weaker support than it looks; do not lean on it

- **[V]** NZ Service Innovation Lab, _Better Rules for Government Discovery Report_, 2018.
  <https://www.digital.govt.nz/dmsdocument/95-better-rules-for-government-discovery-report/html>
  Gestures at "an opportunity to have an **isomorphic output**", but its actual commitments are
  **equivalence** and **co-drafting "in unison"** — semantic correspondence, _not_ structural
  mirroring.
- **[P]** OECD (Mohun & Roberts), _Cracking the Code: Rulemaking for humans and machines_, OECD
  Working Papers on Public Governance No. 42, 2020.
  DOI [10.1787/3afe6ba5-en](https://doi.org/10.1787/3afe6ba5-en). ⚠️ **Metadata verified via
  Crossref; the content is NOT verified — oecd.org is bot-blocked and I could not read a single
  sentence.** Do not quote it.

⚠️ **Strategic caution:** Rules as Code is a _different claim_ from isomorphism — "draft the text
and the code together so no translation gap opens", versus "given a text that already exists, here
is what the code must look like." Conflating them is an easy way to get caught. Our argument is the
isomorphism one; cite AI & Law, not RaC.

### Could NOT verify — do not cite

- **[U]** **"FEEL is Turing-complete."** Asserted by the Semantic DMN authors ("It is
  Turing-powerful") with **no proof and no citation**; I found no published proof. Cite it as
  _their claim_, never as a result.
- **[U]** "jDecide" — could not establish that this product exists.
- **[U]** Decisions.com gap/overlap analysis — no documented feature found.
- **[U]** Kluza et al., "Understanding DMN: Research Directions and Trends", KSEM 2019 — closed
  access, no OA copy, no abstract retrievable. **I could not read one sentence of it.** Do not
  cite it for any claim.
- **[U]** Trisotech's DT Analysis _algorithm_ — never published. That it is geometric rather than
  solver-backed is an **inference** from shared lineage with KIE. Flag or omit.
- **[U]** "Interactive and Minimal Repair of Business Rule Bases" — **does not exist**. The real
  paper (Corea, Nagel, Mendling, Delfmann, BPM Forum 2021) repairs **Declare/LTL_f** models, and
  has nothing to do with DMN.
