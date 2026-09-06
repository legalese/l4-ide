# Residual: One Word, Three Disciplines

What remains to be performed, what remains to be decided, and who gets to decide it.

---

L4's trace semantics, economics' incomplete contract theory, and public-law doctrine all
reach for the same word — _residual_ — and they are not using it by accident. This sidebar
traces the word through the three fields and shows why a formal-methods toolchain ends up
caring about all three senses at once.

---

## Where L4 got the word

When a regulative rule consumes an event stream, one of the
[three possible outcomes](regulative-rules.md#the-three-possible-outcomes) is neither
`FULFILLED` nor `BREACH` but a **residual obligation**: the contract in its current state,
clock partly used up, partially-completed chains ready to resume — the contract frozen
mid-flight, as a first-class value. [`EVALTRACE`](../../reference/regulative/EVENT.md)
advances a `DEONTIC` through a list of events and returns the residual; feeding that residual
more events later is how a long-running contract is executed piece by piece.

The intellectual lineage is precise. Brzozowski (1964) defined the _derivative_ of a formal
language: the residual language after consuming a prefix — everything that could still be
said, given what has been said so far. The Copenhagen school of contract formalisation
(Andersen, Elsborg, Henglein, Simonsen & Stefansen 2006; then Hvitved's CSL, 2012) lifted
that construction from languages to contracts: the residual contract after an event is the
derivative of the contract with respect to that event. L4's trace semantics stands in this
line.

Two properties define this sense of the word:

1. **The residual is entailed.** Nothing in it is new. The original contract plus the trace
   determine it completely; computing it is mechanical.
2. **The residual is a quotient.** It is the contract _divided by_ the trace — and this is
   not a metaphor. In ordered algebra the operation adjoint to composition is literally
   called the residual (residuated lattices, Ward & Dilworth 1939; Lambek's syntactic
   calculus, 1958). The formal residual is what division looks like when the things being
   divided are obligations.

## The economists' residual

The 2016 Nobel Prize in Economics went to Oliver Hart and Bengt Holmström for contract
theory, and the Hart half rests on one premise: **no real contract can specify every
contingency.** Foresight is bounded, drafting is costly, and many contingencies are
unverifiable by a court even when both parties can see them. (Simon 1951 spotted the germ in
the employment relation: a wage does not buy an enumerated task list, it buys _authority_
within a zone of acceptance.)

Once completeness is off the table, the design question inverts. It is no longer "what should
the contract say?" but **"who decides, when the contract runs out?"** — the allocation of
**residual control rights**. Grossman & Hart (1986) and Hart & Moore (1990) built the modern
theory of the firm on this: to _own_ an asset just is to hold the residual control rights
over it — the right to decide every use the contract does not reach — and the boundary of the
firm is drawn where allocating those residual rights one way rather than another is
efficient. The balance-sheet sibling is the **residual claimant** (Alchian & Demsetz 1972):
equity is whatever income remains after every fixed claim is paid.

## The two residuals are duals

Both senses answer the question "what remains?" — with respect to opposite complements:

|                  | formal residual (CSL, L4)               | residual control rights (Grossman–Hart–Moore)    |
| ---------------- | --------------------------------------- | ------------------------------------------------ |
| the remainder of | performance of the specified terms      | the space of contingencies _beyond_ the terms    |
| determined by    | contract + trace: entailed, computable  | nothing — that is precisely the point            |
| operation        | quotient: divide the contract by events | complement: subtract the contract from the world |
| discharged by    | further events                          | a decision, by whoever holds the right           |
| lives            | inside the specification                | in its gaps                                      |

One is what remains _of_ the ink; the other is what remains _beyond_ it. A full account of a
contract's life needs both halves: `EVALTRACE` computes the first, and ownership structures,
discretion clauses ("the Lender may, in its sole discretion…"), and ultimately courts
allocate the second.

## Public law: the residual at constitutional scale

The bridge to jurisprudence even comes with matching names: the economics of rule
incompleteness belongs to Oliver Hart, and the jurisprudence of rule incompleteness to
H.L.A. Hart — unrelated, but the same discovery made from two directions: _the load-bearing
part of a rule system is where the rules run out._

A constitution is a polity's master agreement, and it is the most incomplete contract there
is: drafted once, amended rarely, applied to centuries of unforeseen contingencies. Public
law, read through incomplete-contract eyes, is the **allocation of residual decision rights
across institutions** — and the vocabulary is not imported from economics; it was already
there:

- **Prerogative.** Dicey defined the royal prerogative as "the residue of discretionary or
  arbitrary authority, which at any given time is legally left in the hands of the Crown."
  The executive's reserve powers are a residual _by name_.
- **Federalism is a residuary clause.** The US Tenth Amendment reserves undelegated powers to
  the states; Canada's "Peace, Order, and good Government" clause grants the residue to the
  centre. Same clause-shape, opposite allocations — proof that residual assignment is a
  _design parameter_, and that constitutional drafters knew they were setting it.
- **Open texture.** H.L.A. Hart (_The Concept of Law_, ch. VII, borrowing "open texture" from
  Waismann) argued that every natural-language rule has a fringe of unprovided-for cases.
  Holmes: judges "do and must legislate, but they can do so only interstitially." Dworkin:
  discretion is "like the hole in a doughnut … an area left open by a surrounding belt of
  restriction." Interpretation doctrine is the fight over who fills the hole.
- **Who holds the interpretive residual.** _Chevron_ (1984) allocated the resolution of
  statutory ambiguity to administrative agencies; _Loper Bright_ (2024) reallocated it to the
  courts. Forty years of US administrative law can be read as a quarrel over a single
  residual-rights clause of the administrative state.
- **What happens when you draft the residual into the text.** The Armed Career Criminal Act's
  catch-all — "or otherwise involves conduct that presents a serious potential risk of
  physical injury to another" — was known, in so many words, as the **residual clause**, and
  the Supreme Court struck it down as unconstitutionally vague (_Johnson v. United States_,
  2015): a residual so open-textured that leaving its allocation to case-by-case guesswork
  violated due process. Its benign cousin is the residuary clause of a will, which behaves
  well because it sweeps up _property_ (an enumerable domain) rather than _conduct_ (an open
  one) — and intestacy statutes are society's residuary clause of last resort.
- **The limit case.** Schmitt's dictum that the sovereign is "he who decides on the
  exception" is the residual-rights observation pushed to its extreme: the exception is the
  ultimate unprovided-for contingency, and sovereignty is the ultimate residual control
  right.

## Why a formal-methods toolchain cares

Formalisation cannot shrink the economists' residual by wishing — but it does something the
prose never did: it **locates the boundary**. Encoding a statute or a contract in L4 forces
every contingency into one of two bins. Either it is _inside_ the specification, where the
residual-after-trace is computable, or it is _outside_, where someone's discretion will have
to act. The toolchain makes the second bin visible:

- [Exhaustiveness checking](../type-system/exhaustiveness.md) lists the cases a determination
  fails to handle. In incomplete-contract terms it is a **residual-rights detector**: a
  machine-generated inventory of the contingencies for which no decision has been allocated
  to anyone.
- The dual defect is a contingency covered _twice_, incompatibly — obliged by one clause,
  prohibited by another. (An early L4 pilot found exactly this double bind in live secondary
  legislation.) Incompleteness and inconsistency are the two compile-time diagnoses of a rule
  system; discretion is the runtime patch for the first, and litigation for the second.
- A reparation clause (`LEST`) is the contract _internalising_ its own residual. Aghion &
  Bolton (1992) analysed debt covenants as contingent control: upon default, decision rights
  shift to the creditor. That is exactly the shape of a specified reparation — an event that
  triggers a _designed_ reallocation of control which would otherwise have been fought over
  as residual.
- Contract-law scholarship even has the information-forcing version: Ayres & Gertner's
  "penalty defaults" set the gap-filling rule to what the parties would _not_ want, precisely
  to force them to specify. A checker that warns instead of guessing is the same policy,
  enforced by tooling.

The aim of formalisation is therefore **not to eliminate the residual**. Hart & Moore's
economics says you cannot; H.L.A. Hart's jurisprudence says you should not — open texture is
what lets a rule system meet genuinely novel cases without seizing up. The aim is to know
_exactly where the specification ends, and who is standing there when it does_: to convert
surprise discretion into designed discretion. `EVALTRACE` tells you what is still owed; the
exhaustiveness report tells you where the rules run out; and the allocation of what happens
_there_ is the part of the system that was never going to be code — but which now, at least,
has a map.

## Coda: designed discretion

Many rules name the holder of their residual right on their face: "unless the Minister
otherwise determines"; "the Registrar may waive this requirement"; "we reserve the right to
modify these terms". An honest type for such a rule is not `BOOLEAN` but _defeasible-by-x_
`BOOLEAN` — the wrapper names the actor who may put a thumb on the scale, and the thumb comes
in three legally distinct strengths: a **determination** fixes the answer for one case; a
**variation** rewrites the rule prospectively for everyone; a **dispensation** disapplies the
rule for a named person while leaving it intact for the rest. Courts review the three
differently — and, strikingly, private and public discretion have already converged in the
case law: _Braganza v BP Shipping_ [2015] UKSC 17 imported public-law rationality review into
contractual discretion, so one constructor genuinely serves both. (L4's design work on making
these wrappers first-class lives in the `SUBJECT TO / NOTWITHSTANDING` spec; it is proposed,
not yet part of the language.)

The logic underneath is prettier than it has any right to be. A constructive derivation
carries its proof; a conclusion the rules neither establish nor refute is the undecided
middle — which is exactly the residual. A discretionary power is a licence to decide the
undecided middle, and its exercise is a logged, localised application of the law of excluded
middle: _the excluded middle is precisely what the Minister supplies._ Discretion is classical
reasoning admitted into a constructive system at named points, by named actors, leaving a
named trace — which is why a fiat answer's explanation ("by determination of the Minister,
under the power conferred by s 34(2), recorded at t") is not a failure of auditability but a
perfectly honest citation.

(One last discipline uses the word, and earns its cameo: in complex analysis, integrate a
function around one of its singularities and everything well-behaved cancels — what survives
is called the _residue_. Rule systems behave the same way. Circle a statute tightly enough
and what you find living at its singular points is the discretion.)

---

## Further reading

- J. Brzozowski, "Derivatives of Regular Expressions," _JACM_ 11(4), 1964.
- J. Andersen, E. Elsborg, F. Henglein, J. G. Simonsen & C. Stefansen, "Compositional
  Specification of Commercial Contracts," _STTT_ 8(6), 2006.
- T. Hvitved, _Contract Formalisation and Modular Implementation of Domain-Specific Contract
  Languages_, PhD thesis, University of Copenhagen, 2012.
- H. Simon, "A Formal Theory of the Employment Relationship," _Econometrica_ 19(3), 1951.
- S. Grossman & O. Hart, "The Costs and Benefits of Ownership," _J. Political Economy_ 94(4),
  1986; O. Hart & J. Moore, "Property Rights and the Nature of the Firm," _J. Political
  Economy_ 98(6), 1990.
- A. Alchian & H. Demsetz, "Production, Information Costs, and Economic Organization,"
  _American Economic Review_ 62(5), 1972.
- P. Aghion & P. Bolton, "An Incomplete Contracts Approach to Financial Contracting," _Review
  of Economic Studies_ 59(3), 1992.
- I. Ayres & R. Gertner, "Filling Gaps in Incomplete Contracts: An Economic Theory of Default
  Rules," _Yale Law Journal_ 99, 1989.
- H.L.A. Hart, _The Concept of Law_, 1961, ch. VII; F. Waismann, "Verifiability," 1945.
- A.V. Dicey, _Introduction to the Study of the Law of the Constitution_, 1885.
- R. Dworkin, _Taking Rights Seriously_, 1977.
- _Chevron U.S.A. v. NRDC_, 467 U.S. 837 (1984); _Loper Bright Enterprises v. Raimondo_, 603
  U.S. 369 (2024); _Johnson v. United States_, 576 U.S. 591 (2015).
- C. Schmitt, _Political Theology_, 1922.
