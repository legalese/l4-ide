# Corporate resolutions as LTS deontics — notes toward a spec

Status: **notes**, not yet a spec. Captured 2026-07-27.
Branch: `docs/corporate-resolutions-spec`. Worktree: `~/src/legalese/l4wt/corporate-resolutions`.

---

## 1. The arc

Represent **corporate decision-making machinery** — shareholder AGMs and EGMs, directors'
resolutions, written resolutions, requisitions, notice periods, quorum, majority thresholds — in
L4's LTS deontics, and draw the **dependency structure** as a DAG or equivalent.

Source law, as a starting point:

- **Companies Act 1967** (`CoA1967`) — the mandatory floor and the default rules.
- **Companies (Model Constitutions) Regulations 2015** (`S 833/2015`) — First Schedule: model
  constitution for a private company limited by shares. Second Schedule: company limited by
  guarantee. Prescribed under s36(1)(a) and (b).

The governing observation: **a company constitution has a broad but bounded configuration space.**
That is what makes it a good L4 target — see §2, which is the load-bearing argument for the whole
arc.

---

## 2. Why the bounded configuration space is the point

This is not "encode one company's constitution." It is a **product line**: a fixed base with
bounded, declared variability. Encode the base once; each company is a delta.

### 2.1 The Act marks its own variability, lexically

The strongest evidence that this is tractable: the Act _tells you_ which of its rules a
constitution may override, in a small number of stock phrases. Verified against `CoA1967`:

| Marker                                                          | Meaning                         | Example                                               |
| --------------------------------------------------------------- | ------------------------------- | ----------------------------------------------------- |
| `So far as the constitution does not make other provision…`     | **default** — replaceable       | s179(1), voting rights                                |
| `despite anything in its constitution`                          | **mandatory** — not overridable | s176(1), directors must convene an EGM on requisition |
| `despite any provision in the constitution of the company`      | **mandatory**                   | s180(1), member's right to attend and vote            |
| `Any provision in a company's constitution is void insofar as…` | **mandatory + voiding**         | s178(1)                                               |

So the mandatory/default partition is not something we have to infer by interpretation — it is
surface-marked. That makes extraction tractable and reviewable, and it means an encoding can be
_checked_ against the Act rather than merely coexisting with it.

This is the same phenomenon `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` already deals with. Worth
checking whether that spec's machinery covers these forms before inventing anything.

### 2.2 The resulting structure

```
company = Act(mandatory)  ∧  (constitution ⊕ Act(default))
```

- **Act mandatory rules** — the floor. A constitution purporting to contract out is void.
- **Act default rules** — apply unless the constitution provides otherwise.
- **Model constitution** — the prescribed off-the-shelf configuration; adopted whole, in part, or
  replaced.
- **A given company** — a delta against the model.

That is a feature model. The variability is real but enumerable, which is exactly the shape that
repays formalisation: one encoding amortises across every company that adopts the model
constitution, which in Singapore is a very large number of private companies.

### 2.3 The relevant provisions (verified section numbers)

| s         | Subject                                                                               |
| --------- | ------------------------------------------------------------------------------------- |
| 175       | AGM required                                                                          |
| 175A      | When a company need not hold an AGM                                                   |
| 176       | Directors must convene EGM on members' requisition — _despite the constitution_       |
| 177       | Quorum — two or more members holding ≥10% of issued shares                            |
| 178       | Constitution provisions void insofar as they affect voting rights on a poll           |
| 179       | Voting rights — _default_, "so far as the constitution does not make other provision" |
| 180       | Right to attend and vote — _mandatory_                                                |
| 181       | Proxies                                                                               |
| 182       | Court may order a meeting where calling one is impracticable                          |
| 183       | Members' requisition to circulate resolutions                                         |
| 184       | Special resolution — majority of not less than 75%                                    |
| 184A–184F | Resolutions by written means                                                          |
| 184G      | Sole-member company may pass resolutions by recording and signing                     |

Directors' meetings are largely _not_ in the Act — they are constitutional. That asymmetry is
itself interesting: the members' side is heavily regulated, the board's side is mostly
configuration. It also means the board side is where a constitution can most easily create a
defect the Act will not catch.

### 2.4 The anchoring worked example: issuing new shares

The motivating chain: _to issue new shares the directors must first offer them to existing
shareholders; to do that they need shareholder approval; that needs a meeting; that needs notice._
Every resolution is an edge; the interesting structure is the dominators.

Verified against `CoA1967`, the chain is **not quite** that — and each correction is load-bearing.

| Step                | Source                                                                                                                                                                                                   | Note                                            |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Directors may issue | **s161(1)** — _"Despite anything in a company's constitution, the directors must not, without the prior approval of the company in general meeting, exercise any power of the company to issue shares."_ | **Mandatory.** Not overridable.                 |
| Offer to existing   | **The constitution — _not_ the Act**                                                                                                                                                                     | See below. Configurable, and droppable.         |
| General meeting     | s175 / s177                                                                                                                                                                                              | Quorum s177(1)                                  |
| Notice              | s177(2) ordinary; **s184(1)** special                                                                                                                                                                    | **14 days private, 21 days public** — see below |

**Correction 1 — there is no offer-to-existing-members step at all, in either layer.** Now checked
against the actual First Schedule text (`sso.agc.gov.sg/SL/CoA1967-S833-2015?ProvIds=Sc1-`), not
just the Act:

- **"Pre-emption" appears zero times in `CoA1967`.** Unlike UK CA2006 s561, Singapore has no general
  statutory pre-emption right on new issues for private companies.
- **The model constitution has no pre-emption on issue.** Para 7(1) reads in full: _"Without
  prejudice to any special rights previously conferred on the holders of any existing shares or
  class of shares but subject to the Act, shares in the company may be issued by the directors."_
  The only fetter is "subject to the Act" — which picks up s161's general-meeting approval and
  nothing else.
- **The model constitution has no ROFR on transfer either.** Paras 24–27 impose no offer round. What
  they impose is categorically different: **para 26 — the directors _may decline_ to lodge a notice
  of transfer if the shares are not fully paid, the company has a lien, or _"the directors do not
  approve of the transferee"_.**

**That last point is a modelling trap worth stating explicitly.** A directors' veto and a
pre-emption right are both loosely called "transfer restrictions" and are **different deontic
objects**: para 26(b) is a _discretionary permission held by the board_, with no stated criteria and
no procedure; a ROFR is an _obligation on the seller_ plus _correlative rights in the other
members_, with a mandatory sequence and a clock. An encoding that files both under "restriction"
has already lost the distinction that matters. (Hohfeld earns his keep here.)

**So the motivating chain of §2.4 does not exist for a default-configured Singapore private
company.** The only prerequisite the default stack imposes on a share issue is s161 approval. Every
protective step founders and investors _assume_ is there — pre-emption, ROFR, tag-along — exists
only if someone put it in **user space** (§2.5). Meng's point is therefore stronger than first
stated: this is not a case where user space _also_ defines these rights; it is the case where user
space is the _only_ place they are defined.

Two consequences worth carrying forward:

1. **The default configuration is minority-hostile.** No pre-emption, no ROFR, no tag — and the
   _directors_ get a discretionary veto over who may become a member. That is a quotable fact and it
   explains why an SHA is universal in Singapore startup practice: it is not belt-and-braces, it is
   the only place the protections live.
2. **The graph must colour edges by provenance and by layer**, since almost every interesting edge
   turns out to originate outside both the Act and the constitution.

**Correction 2 — 21 days is the public-company figure.** s184(1) after Act 36/2014 splits it:
**(a) private company — not less than 14 days'** written notice; **(b) public company — not less
than 21 days'**. Ordinary meetings are ≥14 days under s177(2), "or such longer period as is
provided in the constitution" — a **one-directional default**: a constitution may lengthen notice
but not shorten it. That is a lattice, not a free choice, and it is a nice small test of whether
the encoding can express bounded variability rather than mere overriding.

**Correction 3, and the one that justifies the whole approach — notice is not a dominator.**
s184(2) lets a special resolution be passed on **short notice** where a majority in number holding
**≥95% of total voting rights** so agree. That is a bypass edge. So "21/14 days' notice" does
**not** dominate "special resolution passed" — there exists a path to the resolution that never
passes through the notice node.

This is the payoff. A hand-drawn dependency DAG shows notice as a hard prerequisite, because that
is what everyone believes. **Lengauer–Tarjan says otherwise, and it is right.** The algorithm
corrects the intuition rather than merely illustrating it — which is exactly the argument P2 §7.3's
gate demands of any picture, and it is an argument about the _analysis_, not the rendering. It also
generalises: consent-based short-notice waivers, unanimous-assent (Duomatic-style) routes, and
s182 court-ordered meetings are all bypass edges, and every one of them is a false dominator in the
naive graph.

**A fourth wrinkle — edges decay.** s161(3): approval to issue shares continues in force only until
the conclusion of the next AGM (or when that AGM was due). So the approval edge has a **lifetime**,
and a plan that sequences other steps too slowly silently invalidates its own prerequisite. That is
§3(3) temporal feasibility, and it is not visible in any static graph at all.

---

### 2.5 Pre-emption and ROFR also live in "user space" — the layer stack

§2.4 establishes that neither the Act nor the model constitution supplies pre-emption or ROFR at
all. Both are defined **in shareholders' agreements, investment agreements and side letters** — and
that is what makes this case study interesting rather than merely detailed.

**The model constitution itself points at that layer.** Para 49(1) sets 14 days' notice for general
meetings _"Subject to the provisions of the Act relating to special resolutions **and any agreement
amongst persons who are entitled to receive notices of general meetings from a company**"_. So the
constitution expressly subordinates one of its own defaults to a private agreement it never names
and cannot see. That is a cross-layer reference written into the public document — and a
ready-made hook for the encoding, since it means layer composition is not something we are imposing
on the material. The material already does it.

| Layer         | Instrument                          | Public?               | Amendment threshold                | Binds                                       |
| ------------- | ----------------------------------- | --------------------- | ---------------------------------- | ------------------------------------------- |
| kernel        | Companies Act                       | yes                   | Parliament                         | everyone                                    |
| system config | Constitution                        | **yes — filed**       | special resolution, 75% (s26(1))   | company + all members incl. future (s39(1)) |
| user space    | Shareholders' agreement (SHA)       | **no**                | usually unanimity or class consent | **only its parties**                        |
| per-deal      | Subscription / investment agreement | no                    | as drafted                         | its parties                                 |
| per-process   | Side letters (incl. SAFE pro rata)  | no, often undisclosed | bilateral, but MFN-linked          | its parties                                 |

**Why terms migrate down into user space.** Four pragmatics, and the second is the one people get
backwards:

1. **Publicity.** The constitution is filed and public. Nobody wants liquidation preferences, veto
   schedules or ROFR mechanics legible to competitors and to the next round's investors. The real
   deal therefore lives in the SHA.
2. **Amendment threshold — the crucial inversion.** The constitution changes on 75% (s26(1)), so a
   10% holder has no protection in it. An SHA typically changes only by unanimity or defined-class
   consent. **The private layer is the _stronger_ lock.** This is the single biggest reason
   investors insist on SHA terms rather than trusting the articles, and it inverts the naive
   intuition that the "constitutional" layer is more fundamental. Any model that ranks layers by
   formality rather than by amendment threshold will get precedence exactly wrong.
3. **Who is bound.** The constitution binds all members automatically, including future ones
   (s39(1) — it binds "as if it had been signed and sealed by each member"). An SHA binds only its
   parties, hence **deeds of adherence**: a transfer is conditioned on the transferee acceding. Miss
   one and the SHA **silently leaks** — the ROFR chain acquires a hole that no document review
   surfaces, because every document is individually fine.
4. **Remedy.** SHA breach is ordinary contract — damages, specific performance, injunction — and it
   can bind shareholders _inter se_ as to how they vote, which the statutory contract does poorly.

**The Russell limit, and it is good law here.** A company cannot validly fetter its statutory power
to alter its own constitution; but the very same agreement is valid as a personal covenant _between
the shareholders_. `Russell v Northern Bank Development Corp` [1992] 1 WLR 588 is endorsed by the
Singapore Court of Appeal in **_The Wellness Group Pte Ltd v Paris Investment Pte Ltd_ [2018] SGCA
47** ("a shareholders' agreement to exercise their votes in a particular way is valid and
enforceable by the courts") and discussed in **_Golden Harvest Films Distribution v Golden Village
Multiplex_ [2006] SGCA 44**.

Formally this is the important bit: **the same clause is void as against the company and
enforceable as against the shareholders.** Validity is a predicate over _who is bound_, not a
position in a hierarchy. **An encoding that models layer precedence as a total order gets this
wrong**, and so does every diagram that draws the stack as strata.

**The conformity clause and its lag.** SHAs almost always provide that, in conflict, as between the
shareholders the SHA prevails and the parties _shall vote to amend the constitution to conform_.
That is an obligation to bring one layer into agreement with another — deontic, with a temporal lag,
and **during the lag the layers genuinely disagree**. It is also, in practice, among the
most-breached clauses in the stack: the amendment is simply never made, and years later the public
document and the private deal say different things. That is a standing, checkable defect.

**ROFR is a family, not a right.** These must be distinguished because they interact:

- pre-emption on **issue** (pro rata / participation) — anti-dilution
- pre-emption on **transfer** / **ROFR** — offer before selling
- **ROFO** — offer first, at a named price
- **tag-along** (co-sale) — minority joins the majority's sale
- **drag-along** — majority compels the minority to sell

The bugs live in the interaction: overlapping or inconsistent time windows; one "Transfer Notice"
serving two regimes that define it differently; drag firing while a ROFR window is still open;
permitted-transferee carve-outs that differ between the constitution and the SHA.

**MFN is a fixpoint.** A side letter with a most-favoured-nation clause defines its own content by
reference to the set of all _other_ side letters. Two holders each with MFN are mutually referential.
Does a stable assignment exist, and is it unique? This is the **same shape** as van der Meyden's
circularity, relocated — and note that **MFN is one of YC's own SAFE variants**.

**Where the two arcs converge.** YC's post-2018 SAFE unbundled the pro rata right into a **separate
side letter**. Pro rata is pre-emption on issue, defined in user space — and it must be honoured in
the very equity round in which the SAFE converts, whose share count is determined by that same
conversion. **How many shares the holder may take up pro rata depends on the post-round cap table,
which depends on how many shares their SAFE just converted into.** That is a second circularity
stacked on the one [[yc-safe-executable]] catalogues, and his single-SAFE analysis scopes to
conversion and does not appear to reach it. Worth checking against the 2025 book before claiming it.

**Why this makes the case study better, not merely bigger.** Counsel drafts the SHA; the company
secretary maintains the constitution; the CFO maintains the cap table; the founder signs the side
letters. Each document is reviewed by someone competent. **The composition is reviewed by nobody.**
That is precisely the System-of-Record gap this project exists to close, and corporate governance
may demonstrate it more cleanly than contracts generally, because the layers are crisply separated
and each has a different owner.

---

## 3. What "dependency" means here — four distinct relations

"Draw a DAG of the dependencies" is underspecified; there are at least four relations, and they
want different renderings. Worth deciding early which one is the product.

1. **Prerequisite / enablement.** To pass X you must first do Y. _Issue shares → member approval →
   general meeting → notice period → quorum._ This is the DAG people picture, and it is the one
   with a crisp graph-theoretic answer (§4).
2. **Authority provenance.** Who holds the power to do this, and where does it come from — the Act,
   the constitution, or a delegation? Less a DAG than a lattice with an override relation, and it
   is where §2.1's mandatory/default marking pays off.
3. **Temporal.** Notice periods, deadlines, the interval between requisition and meeting. Not a
   DAG at all — it is arithmetic over dates, and its interesting output is _feasibility_: can this
   sequence be completed in the time available?
4. **Conditional / defeasible.** Quorum met? Interested director recused? Class rights engaged?
   These modulate whether an edge exists at all, which means the "DAG" is really a family of DAGs
   indexed by facts. That is the honest complication.

**Recommendation:** lead with (1), because it has a real algorithm and a real answer. Treat (3) as a
separate feasibility check rather than trying to draw it. (4) is the reason the picture cannot be
static.

---

## 4. Where this lands in existing machinery — the honest read

This arc walks straight into `specs/todo/lexipedia-superset/LTS-VISUALISER.md` (the P2 spec, 1022
lines, revision 2, post-adversarial-review). Two things there matter, and one of them is a caution.

### 4.1 The caution: P2's picture is deliberately gated

P2 was narrowed by review. Its two-plane picture (P2d) and animator (P2e) are **gated** behind an
experiment: build them **only if** readers demonstrably cannot answer the question from a plain
bulleted list (P2a′), and the off-the-shelf BPMN token simulator cannot either (P2a). The spec is
blunt about it:

> **This document does not know whether the picture beats the list.** Nobody has tried.

It also corrects an earlier over-claim: the token-animation literature (Maslov et al.) found
animation did **not** significantly improve comprehension directly — it reduced extraneous
cognitive load, which in turn predicted comprehension. So "a picture will help" is not warranted
from the armchair.

**So: do not spec a new corporate-resolutions diagram as though the visualiser question were
open.** It has been argued, and the ruling is "prove it beats a list first."

### 4.2 The opportunity: this is a _different question_, and it lands on the ungated piece

P2's lead question is about a **position** in a single contract: _what do I owe right now, what
discharges it, what breaches it._ That is what the list baseline is good at.

Meng's corporate-resolutions question is about **prerequisites** across a body of procedural
norms: _what must happen before I can do this._ That is a different question, and it is one P2's
own §1.1a concedes the list handles badly:

> What the list plainly cannot do is show **where** in the contract you are, or **what happens
> after** what you are about to do.

More importantly, the prerequisite question already has a named deliverable in P2's staging table —
**P2f**:

> `dom_s(J)` by Lengauer–Tarjan over `StateGraph`, answered as a **set of acts** — printable as a
> list or as an annotation on P1's BPMN. **No new picture required.**

**Dominators are exactly the prerequisite relation.** A node `d` dominates `n` when every path to
`n` passes through `d` — i.e. _you cannot pass this resolution without first having done that_.
"You cannot validly pass a special resolution without 21 days' notice and quorum" is a dominator
claim, and Lengauer–Tarjan computes it.

And critically: **P2f is unbundled from the gate entirely** and depends only on P0, which has
shipped. So the corporate-resolutions arc can proceed on the ungated, algorithmically-grounded
piece without waiting on the contested picture.

### 4.3 Consequences

- The first deliverable is **not** a diagram. It is a dominator query over the state graph of a
  company's constitutional machinery, answered as a set of required acts.
- If a picture is warranted later, corporate resolutions may be the domain that supplies the
  empirical warrant §7.4 says is currently missing — a genuine prerequisite DAG is a better case
  for a graph than a single contract's token position.
- Existing hooks: `StateGraph` + `stateGraphToDot` (ship today), BPMN export (P1, shipped at
  `cfeaea5d`), `stategraph-junctions`.

---

## 5. Candidate analyses — the bug-finding side

The interesting output is not only the picture. It is what a checker finds. Candidates, roughly in
order of how demonstrable they are:

**A1 — Constitution ⊗ Act consistency.** Does this constitution purport to do something the Act's
mandatory rules void? s178 literally declares such provisions void; s176 and s180 override the
constitution outright. Static, decidable given §2.1's marking, and the direct analogue of the SAFE
static analysis. _This is the flagship: a founder uploads their constitution and gets told which
clauses are void._

**A2 — Interested-director deadlock. Now verified in the model constitution's own text, and it is
sharper than "recusal breaks quorum".** The operative paragraphs:

- **85(1)** — _"A director **must not vote** in respect of any transaction or proposed transaction
  with the company in which the director is interested…"_ — a prohibition, not a convention.
  **85(2)** — if the director votes anyway, _"the director's vote must not be counted."_
- **86** — _"The quorum … may be fixed by the directors, and unless so fixed is **2**."_
- **87(2)** — where the number of directors falls below quorum, the continuing directors _"may not
  act except for the purpose of increasing the number of directors … or … summoning a general
  meeting."_

Take the very common two-founder, two-director company, and any transaction both are interested in
— a founder loan, a related-party services agreement, an issue of shares to themselves. Then:

**The meeting is quorate but structurally incapable of deciding.** Para 85 prohibits _voting_, not
_attending_, so the quorum of 2 under para 86 is satisfied; there are simply no votes that may be
counted. That is a cleaner double bind than a quorum failure — the board is validly convened and
can transact nothing.

**And para 87(2)'s escape hatch does not reach it.** 87(2) is triggered by the _number_ of directors
falling below quorum — vacancies — not by universal disqualification from voting. So the model
constitution provides a relief valve for one kind of board paralysis and not for the structurally
similar one. A human reading 87 assumes they are covered; a reachability check finds in seconds that
they are not.

Same shape as the deontic race condition found in the government pilot: a double bind emerging from
two independently reasonable rules. **This is the flagship finding candidate**, and unlike most of
this file it needs no new machinery to demonstrate — the rules are short, verified, and the
counterexample is a two-person company.

Caveats to state when writing it up: s156 disclosure sits alongside this; para 85 is a default a
bespoke constitution or an SHA routinely disapplies; and members can ratify. The point is precisely
that **the default configuration deadlocks**, which is a statement about the model constitution, not
about every company.

**A3 — AGM dispensation interactions.** s175A lets a company dispense with AGMs; s184F(2) already
carves out resolutions mentioned in s175A(1). What else silently requires a meeting that a
dispensed-AGM company can no longer convene by default?

**A4 — Written-resolution exclusions.** Some things cannot be done by written means. A constitution
saying "any resolution may be passed by written means" over-reaches. Checkable against s184A–184G.

**A5 — Temporal feasibility.** Given notice periods and a deadline (statutory filing, a
contractual long-stop, a financing condition), is the required sequence completable _at all_?
Purely arithmetic, needs no picture, and answers a question founders actually ask.

**A6 — Authority chains.** Can the board do this alone, or does it need the members? Renders as
provenance annotation, not a graph.

### Cross-layer targets (from §2.5)

**A7 — Conformity drift.** The SHA obliges the parties to conform the constitution. Diff what the
constitution says against what the SHA requires it to say. Purely mechanical once both are encoded,
and it finds a defect that is near-universal in practice and invisible to single-document review.

**A8 — Per-party validity, not precedence.** Resolve conflicts with a `Russell`-aware predicate:
void as against the company, enforceable between shareholders. **Test that the encoding refuses to
express this as a total order** — if layer precedence typechecks as a ranking, the model is wrong.

**A9 — Transfer-regime interaction.** ROFR / ROFO / tag / drag: are the windows consistent, is the
priority total, and can two regimes fire on the same Transfer Notice with different deadlines?

**A10 — Adherence-chain integrity.** Is every current holder actually a party to the SHA? A missing
deed of adherence is a hole in the ROFR chain that no document review finds.

**A11 — MFN fixpoint.** With multiple MFN side letters, does a stable assignment of terms exist, and
is it unique? Same shape as the SAFE's circularity.

**A12 — Pro rata ⊗ conversion.** The convergence case of §2.5. Bridges to [[yc-safe-executable]].

### Failure modes to use as the test corpus

Drawn from how these documents actually go wrong in practice, and each is a scenario the encoding
should reproduce:

- **Deed of adherence never signed** — transferee unbound, ROFR chain holed.
- **Constitution never conformed** to the SHA, per A7.
- **Pre-emption waived informally** to close a round fast, with no written waiver — leaving a
  voidable issue. This is the classic seed-round diligence finding, and it is a _procedural_
  defect that the arithmetic of the cap table cannot show.
- **Cap-table drift** — options granted outside the pool, SAFEs untracked, side letters forgotten.
- **Notice mechanics** — deemed-receipt clauses, email vs post, and a ROFR clock whose start date
  nobody recorded.
- **Definitional divergence** — "Transfer", "Permitted Transferee", "Investor Majority" defined
  differently across constitution, SHA and SSA. Cheap to check, embarrassing to find late.

---

## 6. Connections to existing work

- **`bitemporal-ledger` / State-as-a-Ledger.** `RECORD`/`COMMIT`/`ATTEST`/`RECALL` _is_ the
  statutory minute book and register of resolutions. This may be the most natural real-world
  justification the ledger feature has — a resolution register is bitemporal by nature (when it was
  passed vs when it was recorded vs when it took effect).
- **`deontic-actor-indexed-actions`.** Actors are everything here: "the directors may", "the
  members in general meeting shall", "an interested director must not vote". Actor-indexed
  deontics is the right primitive and it has shipped.
- **`temporal-rule-version`.** Constitutions are amended by special resolution; the Act is amended
  by Parliament. Which version governed the meeting held last March is a real question.
- **`SUBJECT-TO-NOTWITHSTANDING-SPEC.md`.** The override markers of §2.1.
- **`lexipedia-superset` / P2.** §4.

---

## 7. Open questions

1. **Jurisdiction.** Singapore `CoA1967` + `S 833/2015` is the stated start. UK CA2006 + the Model
   Articles are the obvious second, and are close enough in structure to test whether the encoding
   abstracts. Delaware is _not_ close — it has no model constitution in this sense, which is
   relevant to the SAFE arc's Delaware shape. Do the two arcs need to meet?
2. **Which relation is the product** — §3's four. Leaning (1) prerequisite, via dominators.
3. **Members vs board asymmetry.** The Act regulates general meetings heavily and board meetings
   barely. Does the encoding treat them uniformly, or are they genuinely different machines?
4. **Is a DAG even sound?** §3(4) — conditional edges mean it is a family of graphs indexed by
   facts, not one graph. Does the product show one graph per fact-set, or a graph with guarded
   edges? P2 §5.2 says explicitly that it _does not draw guards_. That constraint bites here.
5. **Corpus gap.** lawplain's record for `S 833/2015` is 935 characters — the enacting regulations
   only. **The Schedules containing the actual model constitution text are not in the corpus body.**
   Need to pull from SSO directly. Check whether this is a general lawplain limitation for
   scheduled instruments, since it would affect other corpora too.
6. **Who is the user?** A founder checking their own constitution (→ A1, wizard-shaped) is a very
   different product from a company secretary planning a resolution sequence (→ A5 + dominators).
   Probably the founder first, on the bowling-pin logic.

---

## 8. Next actions

- [x] ~~Pull the model constitution Schedules from SSO~~ — done; text at `sso.agc.gov.sg/SL/CoA1967-S833-2015?ProvIds=Sc1-`.
      **lawplain gap confirmed and still open**: its `S 833/2015` record is 935 chars (enacting
      regulations only), so the Schedules are absent from the corpus. SSO 403s WebFetch but serves
      a normal browser UA. Worth checking whether scheduled instruments are systematically thin.
- [ ] Read `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` — does it already handle §2.1's markers?
- [ ] Extract the mandatory/default partition from `CoA1967` Part on meetings, using the §2.1 stock
      phrases. Small, mechanical, high-value, and independently checkable.
- [ ] **Encode §2.4's share-issue chain end to end** — s161 approval, constitutional pre-emption,
      meeting, quorum, notice, plus the s184(2) short-notice bypass and the s161(3) expiry. Small,
      self-contained, and it is the example everything else is explained against.
- [ ] Encode the rest of the general-meeting machinery for a private company limited by shares.
      Members' side only; leave the board side for a second pass.
- [ ] Spike **P2f** (Lengauer–Tarjan dominators over `StateGraph`) against it — answered as a set
      of acts, no picture. This is the real first deliverable. **Acceptance test: it must report
      that notice does _not_ dominate a passed special resolution** (§2.4, correction 3). If it
      says otherwise, the bypass edge was not modelled and the encoding is wrong.
- [ ] Try A2 (recusal-breaks-quorum) as the flagship finding.
- [ ] Only then revisit whether a DAG rendering earns its keep, against P2's gate.
