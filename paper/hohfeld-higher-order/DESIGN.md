# Hohfeldian Relations as Higher-Order Deontics — design note (v0.1)

> Scaffold, 2026-07-18. Venue **not yet determined** — this note is deliberately
> venue-generic (no length/format constraints baked in). Candidate venues logged at
> the end. Sequel / second-order counterpart to the Bounded Deontics paper
> ("Deontics as Domination", `../bounded-deontics/`).

> **RESTRUCTURED 2026-07-18 → NOW A SECTION, NOT A STANDALONE PAPER.** A verified
> prior-art pass (deep-research `wf_dd21e9a3`) found the higher-order reading is the
> _received view_ (Fitch 1967, Makinson 1986, Markovich 2020 "higher-order rights"),
> formalised four ways (Kanger–Lindahl; Lindahl's _Spielraum_; Jones & Sergot
> counts-as; Gelati/Governatori/Rotolo/Sartor potestative `DeclPow`), already made
> **executable** (eFLINT 2020), and the square-of-opposition angle already published
> (Lima et al. 2021, _Legal Theory_ — opposite=contradictory, correlative=converse,
> extended to Blanché's hexagon + a logical cube). So the standalone conceptual claim
> is anticipated. The defensible residue is a _typed, functional, model-checked_
> instantiation only. **Deliverable is now a section draft** intended to `\input` into
> "Deontics as Domination":
>
> - `section-powers-as-higher-order-deontics.tex` — the section (copious prior-art
>   background for unfamiliar readers; concede-then-claim; wired to the main paper's
>   dominator / ∀-∃ static-runtime spine: immunity = safety/∀/`AG¬changed`, power =
>   liveness/∃/`EF`).
> - citations merged into `../bounded-deontics/draft/bounded-deontics.bib` (20 entries,
>   provenance-tiered; `fitch1967` and `dongroy2021` flagged UNVERIFIED). The section is
>   `\input` into `bd-draft.tex` after the boundary section.
>   The material below is retained as the fuller design record.

## Working title

- **"Deontics as Domination, Powers as Higher-Order Deontics"** (ties it to facet 2), or
- **"Hohfeld, Higher-Order"** / **"Powers as Operators: Hohfeldian Relations as
  Higher-Order Deontic Formulas."** Decide with venue.

## Thesis (one sentence)

Hohfeld's eight jural relations are not eight primitives but **two layers of
deontics**: the first-order square (right/duty, privilege/no-right) is ordinary
party-indexed `MAY`/`MUST`/`SHANT`; the second-order square (power/liability,
immunity/disability) is just **operators over the first-order layer** — a power is a
`MAY` whose _argument is another party's deontic position_.

## The central move: the mapping is FORCED, not chosen

Once we admit the CS notion of **higher-order formulas** (functions that take/return
functions; quantification over relations), Hohfeld's structure falls out as the
corresponding type/function hierarchy. We do not _encode_ the square — the square
_is_ the hierarchy. That is the paper's claim to non-triviality: not "powers are
higher-order" (old news — Hohfeld, Hart, Kelsen all say so informally) but that the
higher-order reading is the **canonical** one, and that reading it off mechanically
buys real things (verification, a jurisprudential unification, an executable
instantiation).

| Hohfeld                                                               | CS higher-order structure                                                                                                         |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| first-order relation (right/duty; privilege/no-right)                 | a **value** — `DeonticPosition`, i.e. party-indexed `MAY`/`MUST`/`SHANT`                                                          |
| **power**                                                             | a **function** `DeonticPosition -> DeonticPosition` (arrest = `person: MAY leave                                                  | -> SHANT leave`) |
| **correlative** (power <-> liability)                                 | the **two ends of one arrow** — empowered party = domain, liable party = codomain; one arrow under two projections, not two facts |
| **opposite / jural negation** (immunity, disability)                  | **negation at that order** — disability = ¬power, immunity = ¬liability, exactly as no-right/privilege negate at first order      |
| **power to confer powers** (Kelsen _Stufenbau_, Hart secondary rules) | genuine **higher-order function** `(DP->DP) -> (DP->DP)` — the empowerment tower is currying                                      |

### The canonical illustration

A policeman's **power to arrest** = the deontic `MAY` to **reset** your freedom of
movement from `MAY` to `SHANT`. In L4 (substrate already drafted in
`specs/todo/HOMOICONICITY-SPEC.md`, main l4-ide checkout):

```l4
-- base liberty (first-order)
§ `Freedom of Movement`
PARTY person MAY leave

-- police power to change that position (second-order: a MAY over a MAY)
§ `Police Detention`
PARTY officer MAY
  REVOKE (PARTY person MAY leave)
  PROVIDED officer `is on duty`
      AND officer `has reasonable suspicion of` person

-- legislative power to confer the police power (third-order: currying up the tower)
§ `Police Powers Act`
PARTY parliament MAY
  GRANT (PARTY officer MAY REVOKE (PARTY person MAY leave))
  PROVIDED `bill passed by majority`
```

## Two payoffs that fall straight out

**1. Hohfeld's own axes stop being mnemonic and become structural.** He drew
correlatives and opposites as a square because he _saw_ the symmetry but had no
calculus for it. The calculus is: correlative = the domain/codomain duality of an
arrow; opposite = negation at the appropriate order; and the "first-order /
second-order" that commentators pin on him is literally **the order of the function
type**.

**2. The second-order square splits by mode — the SAME ∀/∃ axis as "Deontics as
Domination".** Power/liability are higher-order **functions** — constructive, ∃, an
`EF`-reachability capability you can exercise. Immunity/disability are higher-order
**logic** — a quantified negation over the whole space of powers ("no power touches
my position" = ∀, `AG ¬changed`, a statically-checkable **safety** property). So
immunity = safety/∀/static, power = liveness/∃/runtime — the identical modal split
from the bounded-deontics paper, now one order up. This is what makes the series a
**ladder** rather than a pile: the ∀/∃ spine appears at ground level (facet 2) and
one level up (this facet).

## Honest caveat to state up front (strengthens the L4 claim, doesn't weaken it)

A power is **not a pure function** `DP -> DP`. Exercising it is a _guarded update on
the normative store_ (event-sourced, cf. state-as-ledger), conditioned by
`PROVIDED …`. The faithful type is closer to a **guarded update in a normative-state
monad** — `DP -> Maybe DP`, or `NormState -> NormState` — than a total function.
Stating this plainly pre-empts the first referee objection and it _strengthens_ the
executable-instantiation claim: L4 actually runs these updates against a live
factbase, which a pure-logic account does not.

## Place in the series (the order-theoretic tower)

- **Facet 2 — Bounded Deontics ("Deontics as Domination"):** the _first-order_ story.
  `MUST K (for goal J)` = K **dominates** J in the reachability graph.
- **This facet — Hohfeld, higher-order:** the _second-order_ story. Powers = functions
  from deontic positions to deontic positions; the empowerment chain = currying.
- Shared spine: the ∀/∃ → static/runtime lattice, reused one order up.

## Prior art — concede-then-claim (same posture as facet 2)

The claim is NOT "powers are higher-order" (old). Concede by name, then claim the
typed `MAY→SHANT` transform + the executable L4 instantiation + the modal (∀/∃) split
of the second-order square. To map before drafting:

- **Jones & Sergot 1996**, "institutionalised power" (the closest neighbour — power as
  the ability to effect institutional change).
- **Makinson 1986** on formalising Hohfeld.
- **Sergot's (n)C+ / `norg`**; **Governatori & Rotolo** on defeasible normative-position
  change; dynamic / update deontic logic (**Meyer**; **van der Meyden**).
- **Kelsen** _Stufenbau_; **Hart** secondary rules (rules of change/recognition/
  adjudication); **Raz** basic vs chained normative powers — the jurisprudential lineage
  (already surveyed in `HOMOICONICITY-SPEC.md`).
- Lindahl / Sartor on normative positions; Herrestad & Krogh on obligation-agency.

## Substrate already in hand

- `specs/todo/HOMOICONICITY-SPEC.md` (main l4-ide checkout) — Hohfeld/Kelsen/Hart/Raz
  survey; the freedom-of-movement / police-detention chain; the operator vocabulary
  `GRANT` / `REVOKE` / `WAIVE` / `EXTEND` / `CREATE` / `ASSIGN` / `PROCURE`; the
  "power = higher-order permission over lower-order deontic relations" definition.
- `jl4/experiments/regulative-powers.l4` — working experiment ("persons have freedom of
  movement, which is a Right").

## Open questions / next steps

- [ ] **Settle venue** (drives length/format). Candidates: **DEON** (Deontic Logic &
      Normative Systems — knows Jones–Sergot cold; theory core lands hardest; avoids
      overlap with facet 2's JURIX target) or **JURIX** (keeps the series annual +
      legally framed). Journal (AI & Law) for a full-length version.
- [ ] Pin the **MAY-vs-SHANT** distinction formally: `REVOKE` (extinguish a privilege)
      vs installing a `SHANT` (impose a duty-to-remain). Arrest arguably does both — is
      the right primitive one operator or two? This is the paper's sharpest own-able point.
- [ ] Decide the **type** of a power precisely (pure `DP→DP` vs guarded
      `NormState→NormState`) and reconcile with the event-sourced ledger semantics.
- [ ] Draft the **correspondence table as §2**, the ∀/∃ split as §3, the L4
      instantiation + worked chain (arrest → legislature → constitution) as §4.
- [ ] Worked legal example beyond arrest: a **power-of-attorney / agency** chain, or
      **delegated legislation** (constitution → statute → regulation → order) as the
      currying tower — pick one that a referee will find load-bearing, not toy.
