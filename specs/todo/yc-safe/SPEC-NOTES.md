# YC SAFE as executable configuration — notes toward a spec

Status: **notes**, not yet a spec. Captured 2026-07-27.
Branch: `docs/yc-safe-spec`. Worktree: `~/src/legalese/l4wt/yc-safe`.

---

## 1. The arc

Encode the Y Combinator SAFE once, as L4, and make it something entrepreneurs and
investors _execute_ rather than _read_.

The shape of a deal becomes three artifacts:

1. **Founder team as JSON** — the cap table side: who holds what, option pool,
   outstanding shares.
2. **Investors as JSON** — one blob per note: money in, valuation cap, discount,
   MFN, pro-rata side letter, date.
3. **The SAFE contract as L4** — the instrument itself, parameterised over (1)
   and (2).

Load (1) and (2) into (3) and you get:

- **A PDF** that a lawyer or a founder can sign, with the L4 encoding carried
  along inside the file itself (XMP / embedded stream — see §5).
- **A simulation surface**: both sides can run scenarios — what happens at a
  $8M pre, at a $30M pre, on an acqui-hire, on a dissolution — _before_ signing,
  and again at every subsequent draft.
- **Next-round paperwork that falls out of the L4** rather than being re-typed:
  conversion schedule, updated cap table, the Series Seed / NVCA set.

The unifying claim: the SAFE is already a program. It is just currently written
in prose and executed by hand, inconsistently, by spreadsheet.

### Why the SAFE specifically

It is close to an ideal first target for a "legal app store" instrument:

- **Short.** ~5 pages. Isomorphic formalisation is tractable in full, not in part.
- **Numeric.** Its core is arithmetic, so its bugs are _demonstrable in dollars_,
  not arguable in principle.
- **Standardised.** YC publishes it; it is not negotiated line-by-line. One
  encoding serves thousands of deals — the economics of formalisation work.
- **Versioned.** Pre-Money (2013) → Post-Money (2018). A natural test of the
  temporal rule-version axis (see `TEMPORAL-RULE-VERSION-DESIGN.md`).
- **Already has an adversary.** See §2 — someone has done the bug-finding by
  hand, so we have ground truth to reproduce.
- **Right persona.** Founders and angels, not lawyers. The overserved-nonconsumer
  bowling pin.

---

## 2. Prior art: van der Meyden & Maher

The scholar is **Ron van der Meyden** (UNSW Sydney), working with **Michael J.
Maher** (Reasoning Research Institute). This is not one paper — it is a
multi-year project with a book at the end of it.

Project page: <https://cgi.cse.unsw.edu.au/~meyden/research/projects/SAFE.html>

| Output                                                                                       | Detail                                                                                                                                                                                               |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Book** — _Simple Agreements for Future Equity (SAFE), Smart Contracts for Venture Finance_ | van der Meyden & Maher, Springer Series in Blockchain Technologies, **2025**. <https://link.springer.com/book/10.1007/978-981-96-3920-5>                                                             |
| _Simple Agreements for Future Equity — not so simple?_                                       | Apr 2023. [SAFEnss.pdf](https://cgi.cse.unsw.edu.au/~meyden/research/SAFEnss.pdf) — **the core bug-finding paper**                                                                                   |
| _A Game Theoretic Analysis of Liquidity Events in Convertible Instruments_                   | Nov 2021, arXiv:2111.12237                                                                                                                                                                           |
| _Can SAFE contracts be smart?_                                                               | Jan 2022                                                                                                                                                                                             |
| _On Conversion of Multiple SAFE Contracts_                                                   | Apr 2023                                                                                                                                                                                             |
| _Architecture for Smart SAFE Contracts_                                                      | BRAINS 2021. [safe-smart-arch-short.pdf](https://cgi.cse.unsw.edu.au/~meyden/research/safe-smart-arch-short.pdf), longer [safe-arch.pdf](https://cgi.cse.unsw.edu.au/~meyden/research/safe-arch.pdf) |
| _Smart (Legal) Contracts: A Case Study using SAFEs_                                          | Oct 2022 overview talk. [SAFEoverview.pdf](https://cgi.cse.unsw.edu.au/~meyden/research/SAFEoverview.pdf)                                                                                            |
| _Building Smart SAFEs_                                                                       | William Coulter, Honours thesis. [coulter-thesis.pdf](https://cgi.cse.unsw.edu.au/~meyden/research/coulter-thesis.pdf)                                                                               |
| Seminar: _SAFE Contract Financial Design Issues_                                             | <https://youtu.be/j90fSgbX3n4>                                                                                                                                                                       |

The four working papers were folded into the 2025 book.

### The hook

The concluding paragraph of _not so simple?_ is, almost verbatim, our spec:

> The diversity of convertible instruments, and the potential for multiple
> instances of such instruments with different parameters to be combined on a
> company's cap table, suggests that **an automated analysis that takes as input
> a formal description of the contracts would be beneficial**, and presents a
> direction that could be interesting to pursue in future work.

He did the analysis by hand and named the automation as future work. We build the
automation. That is a clean, citable, non-competitive relationship to the prior
art — and a natural collaboration approach.

### Scope of his analysis (important for calibrating ours)

He analyses the **Pre-Money SAFE with valuation cap and no discount**, in a
scenario with a **single** SAFE outstanding. The multiple-SAFE case is the
separate 2023 paper. Several findings below (notably D4) _do not arise_ in the
other variants — cap-and-discount, discount-only, MFN, and all the Post-Money
forms convert on price alone.

---

## 3. The findings to reproduce automatically

These are the ground-truth targets. An encoding + analysis pass that rediscovers
these is a validated static analyser.

### D1 — The four-equation inconsistency (his Proposition 1)

A standard equity round satisfies four equations, each individually reasonable:

|                 |                                                                                 |
| --------------- | ------------------------------------------------------------------------------- |
| `(ms_pnew)`     | `m_new = s_new · p_new` — money in equals shares times price                    |
| `(vsp_pre)`     | `v_pre = s_f · p_new` — pre-money valuation is existing shares at the new price |
| `(vsp_post)`    | `v_post = S_post · p_new` — post-money valuation is all shares at the new price |
| `(vm_pre,post)` | `v_post = v_pre + m_new` — the company gained exactly the new cash              |

**When a convertible converts, these four are jointly inconsistent.** The proof
collapses to `p_new · s_safe = 0`, contradicting the assumption that the SAFE
holder gets a nonzero number of shares at a nonzero price.

Nobody paid new money for the SAFE holder's shares, so value has to come from
somewhere; the four equations jointly deny that it can.

**Therefore every execution of a SAFE silently abandons at least one of these
equations, and the contract never says which.** Which one you drop _is_ the
choice of conversion method. This is the root defect; D2–D7 are its shadows.

_Mechanisation:_ trivially checkable. UNSAT over four linear equations plus
nonzero side conditions. This is the "hello world" of the analysis.

### D2 — "Pre-Money Valuation" is two different things

The SAFE can be accounted for as a **liability** or on the **cap table**. Each
view picks a different consistent subset of D1's equations, and each implies a
different reading of the term "Pre-Money Valuation" — a term the contract uses
without defining which sense it means.

Notably: the two views yield essentially the same _proportional_ shareholdings,
but get there through different arithmetic and different intermediate values.

### D3 — Method proliferation

Because of D2, at least five conversion methods are used in practice for one
instrument:

| Method                     | Conservative for new investor? | Notes                                                                                    |
| -------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------- |
| **Standard**               | **No**                         | Appears to be YC's intended method                                                       |
| **Percent-Ownership**      | Yes                            | Equivalent to Discounted Valuation                                                       |
| **Discounted Valuation**   | Yes                            | Costs the founders, relative to Standard                                                 |
| **Dollars-Invested**       | No                             | The practical compromise; least principled                                               |
| **Zero-Round (two-stage)** | Varies                         | Artificial round forces conversion first; has Standard and Discounted-Valuation flavours |

_"Conservative"_ is his term for the property that immediately after issuance,
the investor holds shares worth at least the money they put in. It is exactly a
checkable postcondition.

### D4 — `v_pre` and `p_new` are left unconstrained

The Pre-Money SAFE's Equity Financing clause uses Pre-Money Valuation, Price,
**and** Company Capitalization as inputs — but never states that they are related
by `(vsp_pre)`, i.e. `v_pre = s_f · p_new`.

So a round can be _constructed_ to violate it. The Percent-Ownership method does
exactly that. Consequences:

- Legally questionable.
- Economically questionable: it opens a **price gap** (see D5).

If one reads the clause as intending to deliver the _maximum_ shares to the SAFE
holder, the implied constraints are:

- `v_pre ≤ c` ⟹ `p_new ≤ c / s_f`
- `v_pre > c` ⟹ `p_new > c / s_f`

Many relations satisfy this; `p_new = v_pre / s_f` is the simplest, and the SAFE
Primer's own worked examples compute price that way — evidence the constraint was
_intended_ but never written down. **The fix was available and cheap: state the
clause in terms of price alone.** The Post-Money SAFE does exactly this.

_This is the flagship "avoidable ambiguity tax" example._

### D5 — Ranges where the SAFE simply cannot convert

Under the conservative Discounted Valuation method, **there exist valuations at
which the contract has no defined behaviour.** Not a disputed outcome — no
outcome. A totality failure in a signed financial instrument.

_Mechanisation:_ this is a coverage/totality obligation, and the most compelling
demo. "Your contract is undefined on this input range, here is the range."

### D6 — Circularity

The SAFE's value depends on the company's valuation, which depends on the SAFE.

- **Cap Table accounting:** need the share price, which needs the SAFE's share
  count, which needs the valuation/price.
- **Liability accounting:** need the company's value, which needs the SAFE
  valued first, which needs the company's value.

Resolvable by writing it as equations and solving — but that means the SAFE is a
**fixpoint, not a straight-line calculation**, and in at least one method the
solution requires finding roots of a polynomial. Root _selection_ is then a
further undetermined choice. His footnote flags this as a specific obstacle to
blockchain implementation.

_Relevant to us:_ an L4 encoding must either express the fixpoint honestly or
pick a resolution and say so. Good pressure-test for the evaluator.

### D7 — The intended method loses the new investor money on day one

Under the Standard method, the new equity investor's shares are worth **less than
they just paid**, immediately, because the SAFE holder's shares dilute them
without adding cash. An immediate unrealised loss, by construction.

_Mechanisation:_ `∀ inputs. value_post(new_investor) ≥ m_new` — find the
counterexample. Nonlinear real arithmetic (products of variables); Z3's nlsat or
dReal territory.

### D8 — Two-round collusion against the SAFE holder

Founders and the new investor can **split one raise into two equity rounds**,
choosing the pre-money valuations deliberately to minimise the SAFE holder's
resulting stake. The paper derives the _optimal_ such collusion.

Legal recourse rests on the "bona fide" and "series of transactions" language —
weak, expensive to litigate, and **absent entirely** if the SAFE is automated on
an open blockchain, which is exactly the setting he cares about.

_Mechanisation:_ two tiers.

- Existence — `∃ a two-round split making the SAFE holder strictly worse off than
the one-round baseline` — is an ordinary SMT query.
- Optimality — the _best_ such split — is optimisation (νZ / OptiMathSAT).

This is the one that reframes cleanly as **adversarial search: loopholes as
exploits.** Same move as the deontic race-condition find, but over arithmetic
instead of temporal logic.

### D9 — Deferred interpretation

If the parties fix a Pre-Money Valuation _before_ agreeing the conversion method
(which he has evidence happens in practice), the outcome depends on **coalition
formation between the three parties** — social factors, not arithmetic. His
recommendation to founders: settle the accounting view and conversion method up
front, and make sure all three parties share that understanding.

_This is a product requirement, not just a finding._ The tool should force that
choice to be explicit at drafting time — which is precisely what encoding in L4
does, since the encoding cannot be left underdetermined.

### D10 — The instrument contradicts its own Primer

The Pre-Money SAFE's construction implies `(vsp_pre)`, which corresponds to
**Liability** accounting. But the SAFE Primer explicitly says:

> A safe is not a debt instrument … an outstanding safe would be referenced on
> the company's cap table like any other convertible security

i.e. **Cap Table** accounting. The math and the official explanation of the math
disagree. The Post-Money SAFE is more coherent here.

_Mechanisation:_ not directly — this is a document-vs-document consistency
finding. But it is a good argument for encoding the Primer's worked examples as
**test cases** and watching them fail against the instrument's own text. Cheap,
and very legible to a non-technical audience.

---

## 4. What this needs from L4 — honest assessment

### Fits the existing machinery

- **Parties as records.** House style is a record threaded as one `GIVEN`
  parameter, not top-level `ASSUME` — see `l4-house-style-given-records`. So
  `founders : LIST OF Holder`, `notes : LIST OF SafeNote`. The JSON-in maps
  straight onto this.
- **Scenarios as tests.** Already the model: each party contributes the dozen
  scenarios they care about, and they run on every draft.
- **Version axis.** Pre-Money vs Post-Money SAFE is a real instance of
  `EVAL UNDER RULES EFFECTIVE AT`, which is merged and CI-covered.
- **Liquidity / dissolution events.** These _are_ deontic and temporal, so the
  regulative machinery applies to the event side even though the conversion side
  is arithmetic.

### Gaps

- **The analysis backend is arithmetic, not deontic.** D1/D5/D7/D8 want SMT over
  (nonlinear) reals plus an optimisation mode. That is a different backend from
  the LTL/model-checking used for the deontic race-condition work. Relates to
  `verification-backend-lowering-spec`.
- **Fixpoints (D6).** Does the evaluator express the circular definition
  honestly, or does the encoding have to pre-solve it? Needs a decision. If we
  pre-solve, we have silently made the same undocumented choice the contract
  makes, and the encoding stops being isomorphic.
- **PDF + XMP output is a new target.** Today we transpile to Markdown. See §5.
- **The "underdetermined" findings (D2/D3/D9) are not bugs in a model — they are
  the _absence_ of a model.** You cannot find them by analysing one encoding.
  See §6, which is the more interesting research point.

---

## 5. The PDF carrier — design note

Goal: the signed PDF _is_ the machine-readable contract; no separate repo to
drift out of sync.

Two mechanisms, and we probably want both:

- **XMP packet** — ISO-standard XML metadata in the PDF. Right home for
  identity and integrity: encoding version, L4 source hash, which SAFE variant,
  which conversion method was agreed (D9!), party JSON hash.
- **Embedded file stream (PDF/A-3)** — right home for the _payload_: the actual
  `.l4` source and the party JSON. This is exactly how Factur-X / ZUGFeRD
  embeds structured invoices in a human-readable PDF, and how PDF/A-3 is meant
  to be used. Proven pattern, existing tooling, existing legal acceptance in the
  EU e-invoicing world.

Precedent matters here: "we did what e-invoicing already does" is a much easier
sell to a general counsel than "we invented a metadata convention."

Open: signature interaction. Embedding must happen _before_ signing, or the
signature breaks. So the pipeline is generate → embed → sign, and the L4 is
inside the signed envelope. That is the strong version — the encoding is part of
what was executed, not an annotation bolted on afterwards.

---

## 6. The research angle: this is a determinacy-frontier case study

The most valuable finding is not any single bug. It is that **the most
standardised, most widely used, most heavily lawyered contract in startup
finance — revised once specifically to fix these issues — still does not
determine its own arithmetic.**

That is the `determinacy-frontier` / `detect ≠ resolve` facet in the papers
series, with an unusually strong empirical base:

- The ambiguity is **quantifiable in dollars** — the spread between conversion
  methods on the same facts is the ambiguity tax, and it is computable.
- The tax is **demonstrably avoidable** — D4's fix (state the clause in price
  alone) was available, costs nothing, and YC actually shipped it in 2018. So we
  can price the delay: five years of deals executed under the ambiguous version.
- Formalisation **detects** D2/D3/D9 without **resolving** them. The encoding
  forks into a family of models, one per resolution choice, and the finding is
  "the prose does not tell you which member you are in." That is the seam,
  stated in an instrument every reader of the paper has personally signed.

Connects to: `poh-yuan-nie-415` (same detect≠resolve structure), the Cambridge
CLS facet, and the `avoidable-ambiguity-tax` sub-analysis.

---

## 7. Open questions

1. **Isomorphic or idiomatic?** Isomorphic encoding preserves the ambiguity
   (good — it is the finding). An executable product needs a resolved encoding.
   Do we ship both, with the resolved one declaring which equations it abandons?
   Leaning yes, and that declaration is itself a product feature (D9).
2. **Which variant first?** Post-Money with cap is today's default deal and is
   the better-constructed instrument. Pre-Money with cap and no discount is what
   he analysed and where the bugs are. Probably: encode Post-Money for the
   product, Pre-Money for the paper.
3. **Multiple SAFEs.** Real cap tables stack notes with different caps and
   dates. His single-SAFE analysis is the easy case; the 2023 companion paper is
   the real one. Products must handle stacking from day one; do the analyses?
4. **Book vs papers.** The 2025 Springer book supersedes the four working
   papers. Need to read it before committing to the findings list above — it may
   have corrections, and it may already contain some of the automation.
5. **Reach out to van der Meyden?** He named this automation as future work and
   is a formal-methods person, not a competitor. Low-cost, potentially high-value.
6. **Jurisdiction and standing.** The SAFE is Delaware-shaped. Does the encoding
   carry that, or is it abstract over corporate law?
7. **What paperwork actually falls out?** Conversion schedule and updated cap
   table are clear. The Series Seed / NVCA set (charter amendment, SPA, IRA,
   voting agreement, ROFR/co-sale) is a much bigger NLG job — see
   `tnr-nlg-roundtrip`. Scope this before promising it.

---

## 8. Next actions

- [ ] Read the 2025 Springer book; reconcile against §3 above.
- [ ] Pull the actual YC SAFE texts (both generations, all variants) into a corpus.
- [ ] Encode the Post-Money SAFE with cap, single note. Smallest useful thing.
- [ ] Encode the SAFE Primer's worked examples as tests (cheap D10 check).
- [ ] Spike D1 as an SMT query — four equations, prove UNSAT. Proves the pipeline.
- [ ] Decide the fixpoint question (D6) before the encoding hardens.
- [ ] Promote these notes to a real spec once 1–3 are done.
