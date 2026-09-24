# The White-Hat Bad Man

### Applications of Formal Methods in Law — from the serial comma to strategic logic

_Working paper for the "applications" facet of the L4 papers series._
_Draft 2026-07. Target venue: ProLaLa (Programming Languages and the Law, POPL workshop) primary; FM industry-track or JURIX as alternates._

_Candidate titles:_ **"The Bad Man Wears a White Hat: Responsible Disclosure for Legislation"** · **"Loopholes are CVEs: A Threat-Model Reading of Legal Drafting"** · **"∀∃ Law."**

_(This memo merges two prior brainstorms — `OUTLINE.md` (the weight-ladder + honest ship/roadmap map) and `thoughts.md` (the correspondence catalog + ∀∃ spine + Construct/Check/Monitor + the Design-by-Contract cap-table study). Both are folded in below.)_

---

## 0. Placement in the series

The L4 papers facet together to describe one system from different angles:

| Facet                                 | Angle                                                              | Venue         |
| ------------------------------------- | ------------------------------------------------------------------ | ------------- |
| L4 intro                              | what it is                                                         | ICAIL         |
| Bounded Deontics                      | theory: obligation as derived, bounded necessity                   | JURIX         |
| Determinacy frontier / detect≠resolve | empirical: an ambiguity-tax measurement                            | Cambridge CLS |
| CNL affordances                       | HCI/linguistics: syntax you cannot get wrong                       | CNL workshop  |
| **This paper — FM applications**      | **"so what can you _do_ with it": formal methods over legal text** | **ProLaLa**   |

Where **Bounded Deontics** _defines_ the properties (a `MUST` is a dominator/landmark relative to a goal; deontic force is the rank-gap between comply and breach), this facet is about _searching for their violation_ — and, more broadly, about the whole ladder of computational techniques legal text will bear, from the lightest (parse it) to the heaviest (game it). It is the applied sibling of the theory paper.

---

## 1. Thesis — Holmes's Bad Man in a hat

Each recurring legal pathology is a **known software bug class**, and each bug class has a **matching verification technique**. Our three existing case studies aren't anecdotes — they are three points on one map:

- comma/scope cases → **parse ambiguity** (formal grammars),
- the PDPA breach-notice study → **race condition** (timed automata / UPPAAL),
- _Poh Yuan Nie_ → **logic minimisation** (Boolean algebra).

Seen as a map, the empty cells are the research opportunities (§3). The unifying adversary who makes running the verifier worthwhile is **Holmes's Bad Man**, recast as the adversary in a threat model.

Holmes's Bad Man ("The Path of the Law," 1897) is usually read as epistemology: to know the law, predict what courts will _do_ to a man who cares only for consequences — the external point of view (Hart's foil). Operationally he is a **threat model**: amoral, capable, optimising against the _letter_. That is exactly the adversary formal verification posits. **The Bad Man and the model-checker's `∃`-search are the same character.** The only thing the amoral verifier leaves open is which **hat** he wears:

- **Black hat** — runs the verifier on the _letter_ seeking a counterexample to the _spirit_: a trace legal-in-letter yet abusive. Exploit-finding. Tax avoidance is `argmax` over the code; a clever structuring is a proof-carrying attack.
- **White hat** — same capability, disclosure ethic. Finds the _same_ counterexample and hands it to the drafter, so the defect is patched at drafting time (a cheap amendment) rather than at litigation time (a multimillion-dollar comma). A **legislative red team**.
- **Gray hat** — the aggressive-but-lawful planner who finds the exploit and quietly _uses_ it, publishing nothing. The disclosure regime (§9) exists to convert him.

**Key move:** both hats run the _same tool_. The verifier is amoral; it just returns a counterexample. Society's whole advantage reduces to letting the white hats run it _first_. Formal methods let the drafter **play the Bad Man in simulation** and pre-empt him — that is, **internalize the external point of view** (Holmes's cynical, adversarial search) precisely in order to strengthen the rule _from the internal point of view_ (Hart), so that it holds when the real bad man arrives. The hat is a role you put on and take off, and a tool can wear it tirelessly — on every draft, over the entire state space, at a cost far below a litigator's hourly rate.

> **The reframe.** _Loophole-finding is exploit-finding._ The letter of the law is the **model**; the spirit of the law is the **property**; a loophole is a **counterexample**. Our pilots already exhibit this: a model checker found a deontic double-bind (a race condition) in live regulation, and an ambiguity in an insurance payout formula that leaked money. Those were white-hat finds.

**Bounded-Deontics quantification.** An exploit is a _reachable state where, in the agent's ordering, breach ⪰ comply_ — the fine-is-a-price gap gone non-positive. The theory facet defines the force; this facet searches for where it has failed.

**The Holmes inversion.** The Bad Man's edge was superior _prediction_, bought from expensive counsel — the asymmetry _was_ the product. Make outcomes formally computable behind a reasoner API and the asymmetry collapses: the "man on the street" gets the Bad Man's crystal ball. Formal methods are simultaneously the black hat's weapon, the white hat's shield, _and_ the equaliser that dissolves the asymmetry Holmes's Bad Man lived on.

---

## 2. The `∀∃` spine

The hats correspond to which **quantifier** you attack:

- A **loophole** is an _existential witness_: `∃` a fact pattern such that a party complies in letter yet defeats the spirit. Finding it is SAT / model-checking's home turf.
- An **impossible-compliance trap** (the government double-bind; the PDPA race) is _refutation of a universal_: `∀` fact pattern, `∃` a compliant action — and the trap is a fact pattern where **no** compliant action exists.
- **Good law** is a `∀∃` property (everyone can always comply) with **no** `∃`-witnessed spirit-violations.

This is the theoretical backbone, and it dovetails with Bounded Deontics: the `∀`-side is dischargeability (every obligation can be met on some path); the `∃`-side is the exploit search.

---

## 3. The correspondence catalog (the survey contribution)

The paper's survey backbone: a systematic bug-class ↔ legal-pathology ↔ technique mapping. Empty-exemplar rows are where to point the next studies.

| Software bug class               | Legal pathology                           | Technique                                                       | Exemplar                                                                         |
| -------------------------------- | ----------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Parse ambiguity (multiple trees) | Comma / modifier-scope ambiguity          | CFG ambiguity detection; disambiguation canons as grammar rules | Oakhurst, Rogers v Bell, **Lockhart v US** (last-antecedent vs series-qualifier) |
| Redundant logic                  | Subsumed / equivalent conditions          | Boolean minimisation (Quine–McCluskey, Karnaugh)                | _Poh Yuan Nie_                                                                   |
| Dead code / unreachable branch   | Vacuous proviso; inoperative clause       | SAT / reachability (is any branch satisfiable?)                 | —                                                                                |
| Race / deadlock                  | Conflicting timed obligations             | Timed automata, TCTL (UPPAAL)                                   | PDPA breach notice                                                               |
| Deontic conflict                 | Double-bind (must ∧ must-not)             | Defeasible deontic logic (Governatori)                          | government pilot                                                                 |
| Dangling pointer                 | Cross-ref to repealed/renumbered section  | Referential-integrity / linker check                            | amendment drift                                                                  |
| Type / unit error                | Currency, date, rate mixed in a formula   | Type & dimension checking                                       | insurance payout leak                                                            |
| Discontinuity / overflow         | Benefit cliff, tax notch                  | Abstract interpretation; monotonicity proof                     | NZ OpenFisca                                                                     |
| Information leak                 | Purpose limitation, Chinese wall          | Information-flow types; Brewer–Nash                             | PDPA/GDPR, conflicts of interest                                                 |
| Missing input validation         | Non liquet / open texture                 | Totality & exhaustiveness checking                              | —                                                                                |
| Regression                       | A redline silently breaks a party's need  | Semantic diff / equivalence checking                            | scenario-tests, statically                                                       |
| Exploit / CVE                    | Loophole                                  | Model-checking as counterexample search                         | tax avoidance                                                                    |
| Non-monotonicity                 | Lesser crime, greater sentence            | Monotonicity verification                                       | sentencing guidelines                                                            |
| Discrimination                   | Protected-attribute dependence            | Metamorphic / counterfactual-fairness testing                   | anti-discrimination law                                                          |
| Interval / off-by-one            | Overlapping or gapped eligibility windows | Interval arithmetic                                             | statute of limitations                                                           |
| Constraint conflict              | Choice-of-law / conflicts of laws         | Constraint solving (SMT)                                        | multi-jurisdiction deal                                                          |
| Priority paradox                 | "Notwithstanding" / "subject to" cycles   | Override graph as argumentation framework (Dung)                | precedence clauses                                                               |
| Spec ↔ impl mismatch            | Smart contract vs the prose it encodes    | Refinement / bisimulation                                       | on-chain vs off-chain                                                            |

Rows 1, 2, 4 are anchored by the three existing case studies.

**The deep structure.** Most of these reduce to **three query shapes** over different object models: _satisfiability_ (can this ever happen — dead letters, conflicts), _reachability / dominance_ (must this, or can this, happen on the way to a goal — the Bounded-Deontics `MUST`, races, loopholes), and _monotonicity / ordering_ (does the value move the right way — cliffs, proportionality). A single DSL with one object model (the labelled transition system) can host all three; that is L4's bet.

---

## 4. The ladder, by weight (Jackson's "lightweight formal methods," extended upward)

The same catalog, _ordered by cost_: the light end pays off immediately and cheaply; the heavy end is the research frontier. For each rung — phenomenon, formal object, query, exhibit, L4 status.

### 4.1 Formal grammars / parsing — the lightest weight

**Phenomenon.** Syntactic and scope ambiguity is parse-tree multiplicity: an ambiguous sentence is one a grammar assigns more than one derivation.

**Exhibits.**

- **Oakhurst Dairy** — _O'Connor v. Oakhurst Dairy_, 851 F.3d 69 (1st Cir. 2017). Maine's overtime exemption: "canning, processing, … packing for shipment **or** distribution of" perishables. Missing serial comma → is _"packing for shipment or distribution"_ one activity or two? ~US$5M; the Maine legislature later "recompiled" the statute to use semicolons.
- **Rogers v. Bell Aliant** — the "million-dollar comma," CRTC Decisions 2006-45 then 2007-75. A comma in a termination clause; resolved on the **French-language version** of the same contract — a second, independent model used as a cross-check (bilingual drafting is redundant encoding, and redundancy catches bugs).
- **Lockhart v. United States**, 577 U.S. 347 (2016) — the rule of the last antecedent vs the series-qualifier canon, argued to the Supreme Court. The canons of construction _are_ grammar-disambiguation rules; formalizing the grammar makes them precise.

**The move.** Ambiguity becomes a _measurable, flaggable_ quantity: parse under a legal grammar, count derivations, flag >1. A **controlled natural language** goes further — its grammar forbids the ambiguous sentence _by construction_. (Seam with the **CNL affordances** facet; "how much ambiguity was avoidable" is the **determinacy-frontier** facet's metric.)

**Status.** Nearest-to-shipping. L4's surface syntax and the CNL work already trade on unambiguous grammar; the "count the parses of this English clause and flag" tool is a small, high-value build.

### 4.2 Propositional / Boolean logic — light

**Phenomenon.** Statutory elements and contract conditions are Boolean formulas over predicates; many drafting questions are decidable Boolean queries.

**Exhibit.** **Poh Yuan Nie** — _[2022] SGCA 74_ (s415 cheating). One strand of the argument reduces to **Boolean minimisation / equivalence**: two ways of stating the elements coincide, or one offence is subsumed by another. (The series keystone, here wearing its Boolean hat.)

**Worked example (in this collection).** The fully reproducible treatment lives beside this memo at [`the-letter-and-the-spirit/`](the-letter-and-the-spirit/) — the public essay _"The Letter and the Spirit."_ It runs the three mechanical moves end-to-end: enumerate the four readings (an L4 `CONSIDER` type), find the forged-degree counterexample, and prove Explanation 1 _otiose_ — where the presumption against surplusage **is** the don't-care / dead-code test, proved two ways that must agree (Z3 shows the Boolean difference ∂(cheat)/∂(conceal) ≡ 0 across the no-property region; Espresso _deletes_ the literal), and drawn as a dead rung on the s415 ladder. `bash reproduce.sh` re-derives every `TRUE`/`FALSE`/`PROVED` in the essay. It is the concrete instance of this paper's slogan — \*a Boolean argument is a contradiction-**detector**, never a contradiction-**resolver\*** — the machine lays out the board, finds the breaking case, and proves the dead clause; the court alone decides the witness is _absurd_.

**Queries.** Satisfiability (`UNSAT` ⇒ dead letter — a benefit no one can qualify for, an offence with no possible instance); equivalence / subsumption (does offence _A_ entail _B_? charge-stacking, double jeopardy); redundancy / minimal unsat core (which condition does the work; which subset makes rules contradictory); exhaustiveness / coverage (do the cases _partition_ the fact space — L4's `CONSIDER` check; the complement of the union is the gap); weighted-voting games (quorum, supermajority, protective provisions → Banzhaf/Shapley: is a "minority-protective" provision _actually_ protective, or is the holder a **dummy** — or a **dictator**?).

**Status.** L4 has the object logic and partial exhaustiveness checking. SAT/equivalence over it is a short reach via an off-the-shelf solver.

### 4.3 Types & static analysis — medium

**Phenomenon.** A contract or statute _is a program_; the compiler-warning catalogue transfers almost verbatim.

| Software defect              | Legal analogue                                                     |
| ---------------------------- | ------------------------------------------------------------------ |
| undefined variable           | term used but never **defined**                                    |
| broken import / dangling ref | "as defined in §X" where §X defines no such thing                  |
| unreachable / dead code      | a clause no path ever activates                                    |
| unused binding               | a defined term never used                                          |
| type / unit error            | a formula adding a _rate_ to a _principal_; a money/time confusion |

- **Referential integrity — the linker for legislation.** A statute book is a graph of cross-references; amendments repeal/renumber and leave dangling pointers. Pure link analysis, _no semantics required_ → a cheap, decisive early win ("it doesn't even compile"). Also catches undefined-term uses and shadowed definitions.
- **Units/dimensions & refinement types.** The **insurance payout ambiguity** from our pilots (a units/formula defect that leaked money); waterfalls that must not double-count a dollar; an amount that _must be ≥ 0_; a date that _must fall after commencement_.
- **The Hohfeldian type system.** Every right carries a correlative duty → a dangling entitlement is a _type error_. Dependent types make "right ⇒ correlative duty" unrepresentable-if-wrong — where Hohfeld's jural relations stop being a metaphor and become a checkable typing discipline.

**Status.** Well-formedness and scope checks are natural extensions of the L4 type checker; some already exist.

### 4.4 Temporal logic & model checking — heavy

**Phenomenon.** Deadlines, concurrency, and deontic conflict — where a static read cannot see the bug because it lives in the _interaction over time_.

**Exhibits.**

- **PDPA data-breach notification race condition** (our UPPAAL study). Interacting clocks (assessment window vs notify-the-regulator window) reach a state where timely compliance is impossible — a **double-bind**, invisible to inspection, found by exhausting the timed state space.
- The **government-agency race condition** from our regulatory pilot — the same shape, in live secondary legislation affecting citizens.

**Properties (temporal-logic queries over the object-level LTS — the "letter"):**

- **Safety:** `AG ¬(O φ ∧ F φ)` — no reachable state both obliges and forbids the same act.
- **Liveness / dischargeability:** `AG (O φ → EF discharge(φ))` — every obligation can eventually be met (the `∀∃`-side); a state where you owe something you can _never_ pay is a trap.
- **Deadlock-freedom:** the contract can always progress to a settled terminal state.
- **The Bounded-Deontics `MUST` is itself a CTL landmark query:** an action on _every_ path to the goal (`¬EF(goal ∧ ¬did(a))`). This rung _operationalizes the theory facet_.

**Direct ancestor.** Pace, Prisacariu & Schneider, _Model Checking Contracts — A Case Study_ (ATVA 2007, LNCS 4762:82–97) — the contract language **CL** (deontic O/P/F over a dynamic logic of actions, with explicit **contrary-to-duty reparations**, Chisholm's paradox made operational), compiled and model-checked for conflicts and superfluous clauses. Our contribution over it: the same discipline driven from a **human-writable DSL** with an isomorphic surface syntax, tied to obligation _derived_ (not declared).

**Status.** Roadmap. jl4 _ships_ the object level and extracts the LTS (`StateGraph.hs`, served over REST); the model-checking backend is designed, not built (`verification-backend-lowering-spec` in flight).

### 4.5 Strategic / game logic (ATL) & mechanism design — heaviest

**Phenomenon.** Not "is there a bad path" but "can a party _force_ a bad outcome regardless of others."

**Formal object.** Alternating-time temporal logic: `⟨⟨A⟩⟩ ◇ φ` — coalition _A_ has a strategy guaranteeing φ (Alur–Henzinger–Kupferman; Wooldridge). **Holmes's Bad Man is an ATL adversary**, and a loophole is `⟨⟨BadMan⟩⟩ (reach goal ∧ avoid sanction)` — a _strategy_, not merely a path.

**Mechanism design / deterrence.** When breach is a priced option (Becker 1968; Cooter's _prices vs sanctions_ 1984), the "force" of a `MUST` is the rank-gap Bounded Deontics measures; ATL asks whether the _incentives_ make the good outcome an equilibrium. Sanctions-as-prices is where the modal quietly downgrades from `MUST` to `MAY-at-a-cost`.

**Status.** Research frontier; depends on the §4.4 backend plus a game solver. The flagship worked example (§7) lives here.

### 4.6 Beyond the ladder (orthogonal techniques)

Not every catalog row sits on the weight spectrum; three deserve their own footing:

- **Anti-discrimination as metamorphic testing.** Counterfactual fairness is a metamorphic relation: flip the protected attribute, hold all else, the outcome must not move. A value-laden doctrine gets a crisp checkable spec (disparate impact ≈ a metamorphic invariant).
- **Separation of duties / Chinese walls.** Brewer–Nash (1989) was invented to formalise a legal-ethical rule; procurement, governance, four-eyes controls are RBAC-with-SoD → verify "can any single actor complete this sensitive transaction alone?"
- **Standard-of-proof / evidential reasoning as probabilistic model checking** (PRISM) — "on the balance of probabilities" as quantitative reachability; a guard against the Sally-Clark / blue-bus statistics-in-court disasters. (Note: this is the one place probability _is_ wanted — at the fact-finding layer, not the rule graph; cf. §5's constituted-not-caused point.)
- **Semantic diff / equivalence checking of drafts.** Borrow EDA's equivalence checking: between draft _n_ and _n+1_, diff the _set of satisfying models_, not the text — "this redline changed nothing except the payout when the claimant is over 65 and the loss exceeds the sub-limit." A provably complete account of what a redline _did_. QA → verification.
- **Monotonicity as a property, not a test.** Upgrade the NZ/HSpec sampling from examples to a `∀`-claim: "earning one more dollar never leaves a claimant worse off." Prove it by abstract interpretation, or get a witness cliff.
- **Tax code as optimisation.** The loophole is the `argmax`; SMT-solve the code for minimal liability — the black hat's search, mechanised.
- **Override graph as a Dung argumentation framework.** "Notwithstanding", "subject to", "save as otherwise provided" are rule-priority operators; a cycle in the override graph is a priority paradox, detectable as a graph property (Bench-Capon / Sartor).

---

## 5. Methodology — Construct / Check / Monitor

Verification has two poles plus a runtime mode; the two "inspiration" papers land one each.

- **Construct (deductive; types/proofs).** _Bailey, "A General Library of Legal Components," ProLaLa 2022_ — composable, **verified** components in Lean 4 (dependent types) across civil procedure, securities, property, trusts, tax, contracts (demo `ammkrn/prolala_demo`). Correctness _by construction_ — the seL4/CompCert move for statutes; the defect is unrepresentable. Answers the fragmentation lament (a standard library abolishes wheel-reinvention) and realises the platform/PostScript vision. This is where the Hohfeldian type system (§4.3) stops being a metaphor.
- **Check (algorithmic; counterexample).** _Pace, Prisacariu & Schneider, ATVA 2007_ — CL compiled to a model and model-checked for conflicts and superfluous clauses. Note the venue: **ATVA, not ICAIL/JURIX** — the verification community walking into law (the "engineers in the room" thesis). This is the Bad Man's `∃`-search, packaged.
- **Monitor (runtime verification).** Same Pace/Schneider lineage — watch a _deployed_ obligation against its spec. Neither construct nor check but _watch_: reasoner-API tool-calling observing obligations fire in real time.

> ### Sidebar — Correctness by construction: the defect that cannot be written
>
> Assurance comes in two dual flavours. **Verify-after** takes a finished artifact and hunts it for defects — the Bad Man's `∃`-search, model checking, the whole "Check" column. **Construct-so-it-cannot-be-wrong** builds the artifact from parts whose composition is _guaranteed_ to hold the property, so the defect is never merely _caught_ — it is **unrepresentable**. The software pedigree is deep: Dijkstra's original _correctness by construction_; **seL4** (a machine-checked microkernel) and **CompCert** (a formally verified C compiler), where the proof is produced alongside the code, not bolted on after; the typed-functional-programming school of _"make illegal states unrepresentable"_ and _"parse, don't validate"_; and stepwise **refinement** (B-method / Event-B), where an implementation is derived from a specification by correctness-preserving steps.
>
> **Translated to law,** correctness by construction means: stop drafting freehand prose and then hunting for loopholes, and instead **assemble** a contract or statute from a library of components — Bailey's Lean modules (§5, "Construct") — each shipping _with its own proof and property suite_, so the composition inherits both. The **Hohfeldian type system** (§4.3) is the same idea at the type layer: make "a right without its correlative duty" a _type error_, not a bug to be found later. And a **CNL whose grammar forbids the ambiguous sentence** (§4.1) is the lightest instance of all — correctness by construction at the level of syntax, where the million-dollar comma simply cannot be typed. The three sit on one spine: unrepresentable-by-grammar, unrepresentable-by-type, unrepresentable-by-proof.
>
> **The slogan** is the shift from _"did we write what we meant?"_ (a question you answer by testing) to _"we cannot write what we do not mean"_ (a question the medium answers for you). It is the deepest possible answer to the fragmentation lament and to the tyranny of Word: a clause you _import_ rather than _paste_ arrives already proven.
>
> **The catch, stated honestly.** Correctness by construction guarantees the artifact meets its **specification** — not that the specification captures **legislative intent**. It relocates the trust boundary from the drafting to the spec, and it does not defeat **open texture**: where the law is genuinely vague, no proof can decide what was left undecided. Construction is greenfield (you must author the new law in the disciplined form); the existing brownfield corpus still needs ingestion and _checking_. L4's bet (§5) is precisely the bridge between them — ingest the messy artifact, then refactor it toward the library so that next time, the defect cannot be written.

**L4's white space = the ingestion bridge.** Bailey builds new law from proven parts (greenfield); Pace checks a contract someone hand-encoded in CL. Neither does **isomorphic ingestion of existing law**. L4's distinctive contribution: ingest the messy existing artifact (LLM does the parse), lower it to a form you can both **check** for the Bad Man's counterexamples _and_ refactor toward a **verified component library**. Defensible because the pilots show ingestion works.

**Steal from Bailey.** A _component_ reframes scenario-tests: a verified "escrow" / "cure-period" / "limitation-clock" ships _with its own proofs and property suite_, so composing it inherits both — the difference between copy-pasting a clause and importing a proven module. That is the cleanest argument against Word.

> ### Sidebar — Formalization as an ambiguity detector: the fork, not the guess
>
> The reflex of an LLM asked to translate a clause into L4 is to return its **single best reading** — and that is exactly the wrong thing, because the confident guess _destroys the evidence_. Silently collapsing an ambiguity hides the very defect the white hat is hunting. The fix is to run the encoder in **enumerate mode**: emit the _distinct admissible readings_ as a fan of encodings, not one. Every translation choice-point where the model must commit — modifier attachment (Oakhurst's comma), quantifier scope, the referent of "such", a defeasible priority, "and/or" — is a **candidate ambiguity site**. Self-consistency helps localize them mechanically: sample N encodings, cluster them into distinct L4 readings; where the samples _disagree_, the model's own entropy has pointed at the fork.
>
> **The formal layer is the filter that separates theoretical from consequential.** A fork only matters if the readings _behave differently_. So formalize each and run a **semantic diff** (§4.6): if the readings agree on every reachable fact pattern, the ambiguity is harmless — do not flag it. If they diverge, you have found a _consequential_ ambiguity — and the checker hands back the **witness fact pattern** that distinguishes them. An enumerate-mode encoder pointed at Maine's overtime exemption would have emitted two encodings and then produced, automatically, the worker who _distributes but does not pack_ — the exact scenario worth ~US$5M in _Oakhurst_. This is the move that turns a fan of guesses into a bug report: the LLM _widens_, the formal layer _tests_, and only the forks that survive the test reach a human.
>
> **Detect ≠ resolve.** The honest output is the fork plus its witness, escalated to a drafter or a court — _not_ a fabricated commitment to one branch. This is how the pipeline respects Hart's **open texture**: surfacing alternatives is precisely _making the nondeterminism explicit in the transition system_ instead of collapsing it, and model-checking over the union of readings then catches the second-order question — does _any_ admissible reading create a double-bind? The LLM's job is to widen, the formal layer's to test, the human's to choose. It also _measures_ the **avoidable-ambiguity tax** (the CLS-determinacy facet): how much consequential ambiguity a given drafting style actually incurs, counted in surviving forks.
>
> **The honest catch.** Not every fork is a real ambiguity — some are just model error. The formal layer prunes the obvious noise (a "reading" that type-errors or is internally inconsistent is discarded, not adjudicated), but telling a _genuine_ interpretive fork from a bad parse still needs human judgement, and many sites multiply combinatorially, so the semantic-diff filter to _consequential_ forks is what keeps it tractable. The faithfulness/trust-boundary problem (§13) does not vanish — but a system that surfaces its alternatives is strictly **more honest than one that buries a single guess**, and that is the whole point: an encoder that admits _"this could mean two things, and here is the case where it matters"_ is doing a lawyer's job, not a stochastic parrot's.

---

## 6. The Missing Test Suite — what contracts leave out

Every serious codebase ships with tests — often more test code than production code. Contracts and statutes ship with **none**. A contract is all "production code" — operative provisions — and _zero_ assertions: no `assert`, no worked example, no "given this scenario, expect this outcome," no regression suite, no coverage report. The recitals gesture at intent but do not execute. This is the starkest single gap between what programmers and lawyers produce from the same raw material — a precise specification of how a complicated system should behave.

**Why the suite is missing is instructive: you cannot test prose.** The absent tests are downstream of the absent _execution model_. Give a contract an operational semantics — lower it to an L4 transition system — and the tests become _possible_; and only then does their absence become _conspicuous_. Formalization does not merely enable testing; it reveals that the tests were missing all along, and that the parties had been shipping a spec no one could run.

**What contracts leave out** — the silences, each one an untested branch:

- the **unconsidered fact pattern** — the case nobody imagined (open texture; the §4.2 exhaustiveness gap);
- the **interaction between clauses** — each fine alone, the composition non-compliant (the cross-document breach of §7);
- the **temporal edge** — deadlines that collide (the PDPA race, §4.4);
- the **intent behind the text** — the _spirit_ is never written down in runnable form; the recital is not an assertion;
- the **counterparty's private scenarios** — the dozen situations each side quietly cares about, never surfaced onto the table;
- the **"what if it goes wrong" branch** — contrary-to-duty and reparation, chronically under-specified;
- the **boundary and the units** — the off-by-one, the currency/rate confusion (the insurance-formula leak).

**The negotiation-stage move.** Imagine that, at negotiation, each party writes down the dozen scenarios it cares about most, and these become _tests_ that run as the contract iterates across drafts. The payoffs are exactly software's: (a) each party gains confidence its needs are represented; (b) the latest edit — from _either_ side — has not silently broken anything (regression); (c) negotiation shifts from redline-and-hope to **requirement-and-verify**; and (d) genuine disagreement gets _localized_ — the failing tests are precisely where the parties actually differ, so they negotiate the substance instead of fighting over wording. It is test-driven development for contracts: write the scenarios first, then draft to pass them.

**A taxonomy of the missing tests** (each maps to a rung of the ladder):

- **Example-based** (unit tests): "claimant aged 67, loss \$50k → payout \$X." The concrete worry, pinned.
- **Property-based / `∀`-assertions:** "the total payout never exceeds the sub-limit"; "earning one more dollar never lowers net income" (monotonicity, §4.6) — the leap from a handful of examples to the _whole_ domain.
- **Adversarial / red-team** (the Bad Man's `∃`-search): "there is _no_ fact pattern in which a party complies in letter yet defeats the spirit." The loophole written down as a test you want to keep green.
- **Regression:** pin the behavior of prior drafts and prior commitments (the accreting corporate-constitution invariant set, §7).
- **Coverage / exhaustiveness:** every case handled; the untested branch is the gap (§4.2).

**The empirical anchor.** The New Zealand entitlements pilot: government benefit tools carrying only a handful of hand-written tests. Parsing them into a Haskell/HSpec environment and generating tests across the _entire_ scenario domain surfaced a miscalculation that affected real people's entitlements. The missing suite was, literally, missing; supplying it found the bug. The existence proof that the gap is both real and consequential.

**Where the tests come from** — three sources, none of which requires the parties to become programmers:

1. **The parties** — their scenarios, elicited at negotiation.
2. **The formal properties** — safety, liveness, dischargeability, monotonicity, no-double-bind: the _spirit_ recast as domain-general assertions any well-formed contract should pass. A **"legal lint"** / standard property suite — the same discipline by which Bailey's verified components ship _with_ their proof and property suites (§5).
3. **Generation** — property-based fuzzing over the fact space, and, for free, the **witness fact patterns** the enumerate-mode encoder emits when it finds a consequential ambiguity (the §5 sidebar) become regression tests the moment they are resolved.

**The reframing.** "The missing test suite" is the practitioner-facing name for this entire paper. Every rung of the ladder is a _kind of test_: a parse-ambiguity check, a dead-letter SAT query, a race-condition model-check, a monotonicity proof, a semantic diff between two drafts. The correspondence catalog (§3) _is_ the missing test suite, itemized; the Bad Man is the author of its adversarial half. What formalization ultimately supplies is not execution for its own sake but **the assertions that were never written down** — the tests contracts have always lacked, because until there was something to run them against, there was no point in writing them.

---

## 7. Worked case study — the corporate constitution as executable spec

Probably the best single case study: it lights up all three modes at once, and the reader immediately believes the bug is real.

**Motivating defect (inter-document, inter-temporal).** An investor's pre-emption right (Series A side letter, 2021) is violated by a later share issuance (Series B board resolution, 2023). _No single instrument is wrong_ — the **composition** is non-compliant. Human diligence is structurally built to miss this (nobody re-reads every prior side letter against the new issuance). A cross-module breach, not a syntax error in one file.

**Formal picture — Design by Contract, exactly.**

- cap table = **state**; each corporate act (issue, transfer, buyback, option grant, conversion, redemption) = a **guarded transition**; constitution + SHAs + side letters = **invariants and guards**.
- Meyer's pre/post/invariant map onto: condition precedent = **precondition**; covenant/deliverable = **postcondition**; continuing representation = **class invariant**; protective provision ("shall not issue senior stock without preferred consent") = **guard requiring an authorization token** (→ access control, the SoD/Brewer–Nash row). `issueShares()` has a precondition; pre-emption is one conjunct.

**All three modes in one example:**

- **Monitor** — validate each proposed act against the accreted corpus (runtime verification of a live sequence of corporate acts).
- **Check** — two commitments can be _jointly_ UNSAT: promise A a pre-emptive top-up to hold 15%, promise B a hard 20% floor; a large enough round makes both impossible (the deontic-conflict cell).
- **Construct** — a **library** of standard verified rights: pre-emption, drag, tag, transfer-ROFR, protective provisions, the liquidation waterfall (itself a payout-formula → the SMT/insurance-leak row) — each a reusable module carrying its own proofs.

**Sharpenings that separate a real formalisation from a toy:**

- "Testable property" → **invariant** (`∀` reachable states), and invariants _accumulate_: a company is a growing conjunction of commitments signed at different times by overlapping-but-not-identical parties. Risk is two-sided — a new act violates an old invariant, or a new invariant contradicts an old one.
- Pre-emption is **waivable and timed**. The correct property is _not_ "H's % never drops" but "no new issue _unless_ H got a conforming offer and the window elapsed." Decomposes into invariant (the floor) + timed protocol (offer-and-15-days — the PDPA clock again) + deontic guard (permission to issue _conditioned on_ completing the protocol, with a contrary-to-duty branch if skipped). The model must distinguish "H was diluted" (maybe fine — waived) from "H was never given the chance" (the breach). **Drawing that line _is_ the product.**
- **The taxonomy is the formalisation.** "ROFR on new issues" is, strictly, the _pre-emption / participation_ right; ROFR usually names first dibs on a _transfer_ of existing shares. Different trigger, different transition. Whether pre-emption is even a default depends on jurisdiction + charter (statutory in the UK, CA2006 s.561; opt-in only under Delaware DGCL §102(b)(3)).
- **Amending the constitution is a meta-transition.** Articles change by special resolution, but entrenched class rights need the class's consent — transitions that rewrite the invariant set itself, gated by higher-order guards. **Hart's rules of change made executable**; the genuine frontier.

**Hats + SOR white space.** Black hat: a board runs a dilutive down-round hoping nobody re-reads the 2021 side letter. White hat: the same checker, run before close, flags the paperwork as non-compliant while the fix is cheap. Third buyer: **M&A diligence**, running the checker over a target's entire corporate history to surface standing breaches as priced liabilities. The fundable gap: Carta / Pulley _record_ the cap table but hold **no formal model of the commitments**, so they'll book an issuance that breaches a side letter. Cap-table SOR **+ a verifier that refuses the non-compliant transition** is the white space.

---

## 8. Where L4 fits — the honest implemented/roadmap map

A map of the ladder against what actually ships (mirroring the Bounded-Deontics §7 discipline of not overclaiming):

- **Shipping / near-shipping (light end):** unambiguous grammar & CNL surface (§4.1); type/well-formedness & scope checks, incl. the linker (§4.3); object logic + partial `CONSIDER` exhaustiveness (§4.2); object-level LTS extraction (`StateGraph.hs`) served over REST.
- **Designed, not yet built (heavy end):** SAT/equivalence backend (§4.2); model checking + the dominator/landmark query (§4.4); ATL / game solving (§4.5). A `verification-backend-lowering-spec` is in flight.

The map is itself a contribution: it says _which_ legal-FM wins are reachable now (the light end pays off immediately and cheaply — the serial-comma checker and the exhaustiveness check ship first) and _which_ need the verification backend. The value doesn't wait for the heavy machinery.

**A reality check, in the appropriate spirit.** To the legal practitioner still losing a Friday afternoon to Word's automatic paragraph numbering — the list that renumbers itself the instant you glance away, the "Heading 3" that will not stay applied — model-checking a deontic contract for strategic exploits reads as science fiction: a cure for problems they have not yet earned the luxury of having. Fair. We record only, and entirely without further comment, that assembling _this very memo_ required renumbering a dozen sections **by hand**, in a plain-text file, because the tooling for _that_ is apparently also still science fiction. Which is exactly the point of the honest map: the light end of the ladder (§4.1–§4.3) — a serial-comma linter, a dangling-cross-reference check — is not science fiction but a Tuesday, and shipping it is how one earns the right to the heavy end.

---

## 9. Policy — the legislative CVE / responsible disclosure

If statutes are code and loopholes are CVEs, rules-as-code's missing complement is a **disclosure culture**: a legislative CVE registry, coordinated-disclosure windows, bounties for defects in draft legislation and published tax rules. Maine's post-_Oakhurst_ semicolon fix is the reactive version; the point is to **move the fix left, before enactment** — from litigation-time (a multimillion-dollar comma) to drafting-time (a cheap amendment). The gray hat is the reason the regime is needed; the white hat is who it recruits.

---

## 10. Related work / positioning

- **PL ⋈ Law movement** (distinct from classical AI-and-law): ProLaLa workshop, **Catala** (Merigoux et al., default logic for tax), Blawx, L4 — plus the **ATVA/CL verification lineage** (Prisacariu & Schneider, contract automata, runtime monitoring). Position the paper here.
- **Bailey (ProLaLa 2022)** — the Lean 4 library of verified legal components; the "construct" pole and the "legal stdlib" answer to fragmentation.
- **Kowalski, Sadri, Sergot et al., _The British Nationality Act as a Logic Program_** (CACM 1986) — the canonical rules-as-code precedent; negation-as-failure ↔ closed-world ↔ "everything not prohibited is permitted."
- **Governatori et al.** — defeasible deontic logic, contrary-to-duty, and _Regorous_ business-process compliance (the compliance-checking incumbent to position against).
- **Bench-Capon / Sartor / Wyner** — argumentation frameworks, value-based reasoning (the override-graph reading, §4.6).
- **Brewer–Nash** (Chinese Wall, 1989); **Nissenbaum** (contextual integrity) — the information-flow reading of privacy law.
- **Alur–Henzinger–Kupferman; Wooldridge** — ATL and strategic ability (§4.5); **Jackson** — lightweight FM / Alloy (the light end of the ladder).
- Legal-theory substrate already in hand: **Hohfeld** (jural relations as an algebra), **Hart** (primary/secondary rules; open texture = nondeterminism), **Holmes** (the Bad Man), **Searle** (constitutive rules).

**L4's position:** not a point tool for one rung, but a **single human-writable object model (the LTS) spanning the whole ladder**, from a serial-comma linter to an ATL game — with obligation _derived_ (Bounded Deontics) rather than declared, traces that double as explanations, and an **ingestion bridge** no incumbent offers.

---

## 11. Suggested paper structure

1. Framing — bug class ↔ legal pathology ↔ technique; the Bad Man as threat model (§1).
2. The correspondence catalog (§3) — the survey contribution.
3. `∀∃` law (§2) — the theoretical spine; loophole = `∃`-witness, impossible-compliance = `∀`-refutation.
4. The ladder by weight (§4) — expository ordering, anchored exhibits, honest status.
5. Construct / Check / Monitor (§5) — methodology; L4's ingestion bridge between the Lean-library and CL-model-checking poles.
6. The missing test suite (§6) — the practitioner framing: contracts ship with no tests; the catalog _is_ that suite, itemised.
7. Worked case study: the corporate constitution (§7) — all three modes.
8. Policy: the legislative CVE / responsible disclosure (§9).
9. The Holmes inversion — democratising the Bad Man's prediction (§1).

---

## 12. Contribution claims

1. A **weight-ordered taxonomy** and a **correspondence catalog** of formal methods over legal text, each row anchored (where possible) to a real legal exhibit (Oakhurst, Rogers, Lockhart, Poh Yuan Nie, the PDPA race, ROFR).
2. The **white-hat/black-hat Bad Man** frame with its **`∀∃`** formalisation, unifying loophole-hunting and drafting-time verification, grounded in Holmes/Hart and _quantified_ by Bounded Deontics (exploit = reachable state where breach ⪰ comply).
3. **Corporate constitution / ROFR-as-invariants** (cap-table regression testing, Design-by-Contract) as a novel, high-value application beyond existing legal-FM work.
4. The **Construct/Check/Monitor** methodology positioning L4's **ingestion bridge** as the white space between the two inspiration papers.
5. A practitioner reframing — **the missing test suite**: contracts ship with no executable scenarios, and formalization supplies the example-based, property-based, adversarial, and regression tests they always lacked.
6. An **honest implemented/roadmap map** for a single-object-model DSL across the whole ladder — a guide to which legal-FM wins are reachable now.
7. A policy proposal: the **legislative CVE / responsible-disclosure** regime.

---

## 13. Open questions / where it's hard

- **Open texture / vagueness:** formal methods make it _visible_ (where the model branches) but don't resolve it — how much to leave as explicit nondeterminism? (Overlaps the CLS-determinacy facet, which measures it.)
- **Meta-transitions** (rules of change, entrenched rights) — modelling acts that change which future acts are permitted.
- **Faithfulness of ingestion:** the LLM parse is the trust boundary; the isomorphism claim needs its own validation story.
- **Jurisdiction-dependence of defaults** (statutory pre-emption, etc.) — the invariant set is charter + contract + jurisdiction.
- **Why we get to drop probability (mostly).** Legal consequences are largely **constituted, not caused** (Searle): "the deadline lapses → breach" is stipulated and certain, not a probabilistic bet. So the rule graph carries no beliefs — world-uncertainty relocates to the _fact base_ (fact-finding), not the transition system. That is why the tool is model checking over a finite LTS, and why L4 sits at the **necessity pole** (ordinal ordering, no probability) — with the one exception of §4.6's standard-of-proof reasoning, which is probabilistic precisely because it lives at the fact-finding layer.
- **Venue / next demo.** ProLaLa fits best. First live demo: _ROFR/cap-table_ is the most novel and product-relevant; the _PDPA race condition_ is the most proven (re-do it natively over the L4 LTS as the flagship reproduction). Draw boundaries with sibling facets: the ambiguity metric is shared with CLS-determinacy, the dominator query with Bounded Deontics — _cite across_, don't duplicate.

---

## References / sources

_Verified this session:_

- Gordon J. Pace, Cristian Prisacariu, Gerardo Schneider. _Model Checking Contracts — A Case Study._ ATVA 2007, LNCS 4762, pp. 82–97. (dblp: `dblp.org/rec/conf/atva/PacePS07.html`)
- Chris Bailey. _A General Library of Legal Components._ ProLaLa 2022 (POPL workshop). Lean 4. (demo: `github.com/ammkrn/prolala_demo`) — `popl22.sigplan.org/details/prolala-2022-papers/13`

_Cases:_

- _O'Connor v. Oakhurst Dairy_, 851 F.3d 69 (1st Cir. 2017) — serial-comma overtime case.
- _Rogers Communications Inc. v. Bell Aliant_ — CRTC Telecom Decisions 2006-45 (first) and 2007-75 (reversal via the French text) — the "million-dollar comma."
- _Lockhart v. United States_, 577 U.S. 347 (2016) — last-antecedent vs series-qualifier canon.
- _Poh Yuan Nie v. PP_, [2022] SGCA 74 — s415; Boolean-minimisation strand.

_Already in the series bibliography (`bounded-deontics.bib`):_

- Holmes 1897 (_The Path of the Law_); Hart 1961 (_The Concept of Law_); Searle 1969/1995 (constitutive rules); Becker 1968; Cooter 1984; Alur–Henzinger–Kupferman 2002; Wooldridge 2005; Pearl 1993.

_To add:_

- Daniel Jackson, _Software Abstractions_ (Alloy; lightweight FM).
- Guido Governatori et al. (defeasible deontic logic; _Regorous_).
- Denis Merigoux et al., _Catala_ (POPL/ICFP).
- Tom Hvitved (contract calculus / trace semantics).
- Kowalski, Sadri, Sergot et al., _The British Nationality Act as a Logic Program_, CACM 1986.
- Brewer & Nash, _The Chinese Wall Security Policy_, 1989; Helen Nissenbaum, _contextual integrity_.
- Hohfeld, _Fundamental Legal Conceptions_ (1913/1917).
