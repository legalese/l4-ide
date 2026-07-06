# A Burden-of-Proof Monad for Computational Law

*Specification and theory note for `L4.Proleg.Burden`.*

## Abstract

We give a compositional account of **burden of proof** as a programming
construct: a typed value paired with the party who must establish it. The
construct unifies several notions that recur across legal theory and contract
economics — negation-as-failure, standards of proof, residual rights, and
agent-indexed obligation — as instances of one schema: *a default over an
incomplete specification, indexed by a responsible party.* We identify the
precise functional-programming structure (the coreader comonad, upgraded to a
`Writer` monad over an obligation ledger), record its laws and the one
semantically-loaded design choice (monad-transformer stacking order), and fix the
correspondence to Satoh's PROLEG and to an Answer-Set-Programming image. The
construct is implemented in `L4.Proleg.Burden` and validated against the lease
judgement of Satoh et al. (2010).

## 1. Motivation: incompleteness and the residual

A legal instrument cannot anticipate every contingency, and a court cannot
*verify* every fact. Incomplete-contract theory (Grossman & Hart 1986; Hart &
Moore 1990) turns on the gap between what is *observable* and what is
*verifiable*: an explicit term can only condition on verifiable variables, so the
remaining region is governed by whoever holds the **residual right**. Burden of
proof is the legal system's rule for that region: *when a fact cannot be
established to the applicable standard, assign the adverse consequence to a
designated party.* Both are **completion devices for an incomplete specification**,
and both complete the gap by naming a *beneficiary of the default*.

This note makes that named-default first-class and inspectable.

## 2. The schema: `(position, party)`

Across three traditions the same syntactic move — indexing a normative position by
a party — carries three Hohfeldian-distinct meanings (Hohfeld 1913):

| Tradition | the party is the… | Hohfeld position |
|-----------|-------------------|------------------|
| Deontic / CSL (Hvitved 2011) | obligation-bearer, blamed on breach | duty (⟂ claim) |
| Property rights (Hart; GHM) | residual-control holder, who *decides* | power / privilege |
| Burden of proof (Satoh; JUF) | bearer of non-persuasion risk, who *loses* | liability |

Standard Deontic Logic's impersonal `O(p)` (von Wright 1951) is the degenerate
top row with the party erased — and the erasure is implicated in its paradoxes
(Ross 1944; the contrary-to-duty paradox, Chisholm 1963). The agentive tradition
(Belnap, Perloff & Xu 2001; Horty 2001) and Hvitved's contract DSL repair this by
making the agent — and the contrary-to-duty *reparation* — first-class. L4 follows
suit: a `Deonton` carries a `party` and a `LEST` reparation. **This note formalises
only the third row** (burden); the others have different combination laws (§7) and
must not be conflated with it.

## 3. From `Maybe Bool` to `Provable`

A proposition's evidential state has two independent dimensions:

* **truth** — established true, established false, or *undecided* (not proven to
  standard): naturally `Maybe a` (with `Nothing` = undecided);
* **burden** — *who* must establish it, and hence what the default is when
  undecided.

An earlier iteration captured the first dimension with a `Default a`
(≈ `Maybe a` + a fallback). Making the *party* explicit yields `Provable`.

```haskell
data Subject    = Plaintiff | Defendant
data Obligation = Obligation { onWhom :: Subject, what :: Text }
```

## 4. What it is, categorically

"A value carrying its evidential subject" is the **coreader / environment comonad**
`(Subject, a)` (Uustalu & Vene 2008): `extract` reads the value; the subject
travels with it. This is *always* lawful and asks nothing of `Subject`.

It becomes a **monad exactly when `Subject` carries a `Monoid`** — i.e. precisely
when one decides *how two burdens combine*. There is no sensible
`plaintiff <> defendant` (a conjunction of a plaintiff-borne and a
defendant-borne fact is established against *each* bearer separately). So we do not
merge subjects; we **accumulate** them. The free monoid over elementary burdens is
an **obligation ledger**, and the comonad-with-monoidal-annotation is then the
**`Writer` monad** (Wadler 1992). Stacked over the truth dimension:

```haskell
type Provable = MaybeT (Writer [Obligation])
--   Provable a  ≅  Writer [Obligation] (Maybe a)  ≅  ([Obligation], Maybe a)
```

The ledger produced as the `Writer` output **is the responsibility map**: a
projection of who bears which proposition, generated for free by composition.

### 4.1 Stacking order is a semantic choice

The two transformer orders are *not* isomorphic, and the difference is legally
meaningful:

| Type | iso | on a failed proof |
|------|-----|-------------------|
| `MaybeT (Writer w)` | `(w, Maybe a)` | **keeps** the ledger |
| `WriterT w Maybe`   | `Maybe (a, w)` | **discards** the ledger |

We want blame to survive failure — "this claim failed, *and here is who failed to
discharge the burden*" — so `MaybeT` is outside.

### 4.2 The identity is the presumption — "innocent until proven guilty"

Promoting the structure from a *semigroup* to a *monoid* forces a choice a
semigroup never has to make: the **identity element** — the value of a proposition
*before any evidence is combined in*. In the legal reading this unit is the
**presumption**, and fixing it is a constitutional act; the operation (evidence)
and the elements can be identical across two systems whose *identities* differ, and
that single difference reverses their morality.

Take the resolved truth of one proposition as a monoid. The carrier is `Bool`, but
there are two structures on it, De Morgan duals of each other:

| Monoid | identity | reading |
|--------|----------|---------|
| `(Bool, ∨, False)` | `False` | *presumption of innocence*: a charge is not established until a sufficient ground flips it true |
| `(Bool, ∧, True)`  | `True`  | *rebuttable presumption of the claim*: it stands until disproof flips it false |

Same elements, same shape, **different unit — different morality.** "Guilty until
proven innocent" is not a different *kind* of algebra; it is the same monoid with
the other identity. Burden of proof is exactly the **per-proposition choice of
identity** — the JUF assignment tags each ultimate fact with which presumption
governs it.

This pins down two earlier pieces:

* The `fallback` of the earlier `Default a` *is this identity*. That is why a bare
  `Maybe` was insufficient and the fallback had to be carried explicitly: the unit
  is a free, morally-loaded parameter, not a language default.
* `flipBurden` swaps the bearer, so — once the default is made bearer-sensitive
  (see Status) — it **De Morgan-dualises** this monoid, `(∨, False) ↔ (∧, True)`,
  swapping the presumption. Its involution law `flipBurden . flipBurden = id`
  mirrors `¬¬ = id`.

Two structures the identity opens up:

* **Identity vs. absorbing element.** A *rebuttable* presumption is the identity
  (evidence can move off it). A *conclusive / irrebuttable* presumption — or a
  *jus cogens* norm — is the **absorbing element** (`x ∧ False = False`,
  `x ∨ True = True`): no evidence moves it. The legal distinction rebuttable vs.
  conclusive is exactly identity vs. zero.
* **A regime in two parameters.** A legal morality is characterised by *(identity,
  threshold)* = *(who gets the benefit of the doubt, how much doubt is tolerated)*:
  the identity is the presumption, the threshold the `ProofStandard` of §8.
  Criminal law picks `(innocent, beyond-reasonable-doubt)`; the pair encodes the
  asymmetric cost of error — Blackstone's ratio (1769), "better that ten guilty
  escape than one innocent suffer" — as, in effect, a decision-theoretic loss
  function (cf. Holmström 1979; Hay & Spier 1997).

Finally, the **monad unit law** reads jurisprudentially: `return a >>= f = f a`
says the presumption *on its own* moves nothing — only evidence (`>>=`) does. A
system in which merely invoking a presumption changed the outcome would violate the
identity law, i.e. would not be this clean a monoid at all.

**Status.** `resolve` currently fixes the unit to `False` for every proposition
(the proponent bears the burden — the innocence-style default). Making the
presumption a per-proposition parameter — so propositions can carry different
identities and `flipBurden` dualises the default as well as the ledger — is the
immediate refinement.

## 5. Operational reading of the combinators

Let a *rule body* be a conjunction, an *exception* a defeater, and a *fact* a
primitive.

* `prove p c mx` — inject fact `c`, borne by `p`, with truth `mx`; records one
  obligation.
* `conj` / `disj` — body conjunction / alternative grounds. **Accumulating, not
  short-circuiting**: every conjunct's obligation is recorded even if an earlier
  one fails, so the responsibility map is *structural* (it reflects the rule, not
  the run). Conjunction needs only `Applicative` (`Writer`); full `Monad` is
  required only when a later conjunct's *shape* depends on an earlier proven value.
* `notProven` — negation as failure: holds iff its argument is not established,
  while still recording the argument's obligations.
* `flipBurden` — relabels a sub-derivation's obligations to `opposite`. An
  **involution**: `flipBurden . flipBurden = id`. It is the localised counterpart
  of PROLEG's `opposite(P)`: rather than threading a party parameter through the
  whole derivation, the flip happens once, at the exception boundary.
* `absent = notProven . flipBurden` — an exception/defeater borne by the opposing
  party: the rule survives unless the defeater is established.
* `resolve` — collapse to a closed-world boolean: established ⇒ `True`, otherwise
  the burden default (the bearer loses) ⇒ `False`. This recovers the `Default`
  fallback as `fromMaybe (defaultFor bearer)`.

### 5.1 Bearer ≠ establishment

The construct keeps *who bears a burden* separate from *whether the fact is
established*. In the lease example the six constitutive facts are the **plaintiff's**
burden (they are requirements of the cancellation claim) yet are **established via
the defendant's admission**. The ledger records the plaintiff as bearer; the truth
component records establishment. Admission, judicial notice, and presumptions all
live in this gap.

## 6. Correspondence

The same non-monotonic content has three faces; the transpiler must preserve the
mapping:

| Concept | PROLEG | `Provable` (value level) | ASP (relational level) |
|---------|--------|--------------------------|------------------------|
| defeater | `exception(H,E)` | `notProven` / `absent` | `not e` |
| closed world | implicit | `resolve` fallback | default negation |
| standard of proof | `plausible(F)` | fills the `Maybe` | choice / weak constraint |
| burden bearer | `opposite(P)` flip in `prove/2` | `flipBurden` (involution) | constraint deciding ties |
| responsibility map | — | the `Writer` ledger | the chosen literals per party |

Relationalising L4 (functions → predicates via A-normal-form flattening, adding an
output argument) sends `Provable`/NAF to ASP default negation, and stable-model
enumeration becomes scenario search — where deontic double-binds surface as
unsatisfiable cores (cf. the model-checking framing of loophole-finding).

### 6.1 Worked example (validated)

Encoding the factbase of `examples/lease.pl` (Satoh et al. 2010, App. A) and
evaluating `contract_end` with these combinators reproduces the paper's judgement:
the plaintiff prevails; the defendant's `get_approval_of_sublease` defence fails
(its facts are alleged but not *plausible*); the defendant's `nonabuse_of_confidence`
defence is itself defeated by the plaintiff's `abuse_of_confidence`
(exception-of-exception); and the ledger attributes `fact_of_abuse_of_confidence`
to the plaintiff and `fact_of_nonabuse_of_confidence` to the defendant. See
`test/Burden.hs`.

## 7. Scope and non-conflation

`Provable` formalises the **burden** role only. The **deontic** subject (CSL/L4:
on actions, with reparation) and the **control** subject (Hart: a single residual
holder, not a ledger) have different combination semantics and are *not* this
monad. The standing transpiler rule follows: PROLEG's `plaintiff`/`defendant` is a
burden-role and must be routed to this evidentiality layer — **never** synthesised
into an L4 `PARTY … MUST` obligation. A unified *responsibility map* with three
lanes (on-the-hook / who-decides / who-must-prove) is the right user-facing
artifact, but it is three projections, not one type.

## 8. Standards of proof (future work)

`plausible` is currently binary. Parameterising it by a `ProofStandard`
(preponderance / clear-and-convincing / beyond-reasonable-doubt) turns the gate
into a threshold on signal sufficiency — the size of the "who decides" premium
(Holmström 1979's informativeness principle in the procedural domain), and a knob
the impersonal account cannot express. Burden *allocation* is itself a
mechanism-design choice (least-cost evidence producer; Hay & Spier 1997).

## References

- Belnap, N., Perloff, M., & Xu, M. (2001). *Facing the Future: Agents and Choices in Our Indeterminist World.* OUP.
- Blackstone, W. (1769). *Commentaries on the Laws of England*, Book IV. (Blackstone's ratio.)
- Chisholm, R. (1963). Contrary-to-duty imperatives and deontic logic. *Analysis* 24(2).
- Dung, P. M. (1995). On the acceptability of arguments and its fundamental role in nonmonotonic reasoning, logic programming and n-person games. *Artificial Intelligence* 77.
- Flood, M. & Goodenough, O. (2017). Contract as automaton: the computational representation of financial agreements. OFR Working Paper.
- Governatori, G. (2005). Representing business contracts in RuleML. *Int. J. Cooperative Information Systems* 14.
- Grossman, S. & Hart, O. (1986). The costs and benefits of ownership. *J. Political Economy* 94.
- Hart, O. & Moore, J. (1990). Property rights and the nature of the firm. *J. Political Economy* 98.
- Hay, B. & Spier, K. (1997). Burdens of proof in civil litigation: an economic perspective. *J. Legal Studies* 26.
- Hohfeld, W. N. (1913). Some fundamental legal conceptions as applied in judicial reasoning. *Yale Law Journal* 23.
- Holmström, B. (1979). Moral hazard and observability. *Bell J. Economics* 10. (See also Holmström & Milgrom 1991, *JLEO* 7, on multitasking.)
- Horty, J. (2001). *Agency and Deontic Logic.* OUP.
- Hvitved, T. (2011). *Contract Formalisation and Modular Implementation of Domain-Specific Languages.* PhD thesis, U. Copenhagen. (See also Hvitved, Klaedtke & Zălinescu, *JLAP* 2011; Andersen et al., *STTT* 2006.)
- Satoh, K. et al. (2010/2011). PROLEG: an implementation of the presupposed ultimate fact theory of Japanese civil code by PROLOG technology. *JURISIN*, LNAI 7258.
- Uustalu, T. & Vene, V. (2008). Comonadic notions of computation. *ENTCS* 203.
- von Wright, G. H. (1951). Deontic logic. *Mind* 60.
- Wadler, P. (1992). The essence of functional programming. *POPL.*
