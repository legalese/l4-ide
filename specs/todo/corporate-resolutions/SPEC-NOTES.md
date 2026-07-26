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

**A2 — Recusal breaks quorum.** An interested director must disclose and (typically, per the
constitution) abstain. If enough directors are interested, abstention drops the meeting below
quorum and the board deadlocks — it can neither act nor validly decline to. Same shape as the
deontic race condition found in the government pilot: a double bind arising from the interaction
of two independently-reasonable rules. Strong candidate for the flagship _finding_.

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

- [ ] Pull the model constitution Schedules from SSO; note the lawplain gap (§7.5).
- [ ] Read `SUBJECT-TO-NOTWITHSTANDING-SPEC.md` — does it already handle §2.1's markers?
- [ ] Extract the mandatory/default partition from `CoA1967` Part on meetings, using the §2.1 stock
      phrases. Small, mechanical, high-value, and independently checkable.
- [ ] Encode the general-meeting machinery for a private company limited by shares. Members' side
      only; leave the board side for a second pass.
- [ ] Spike **P2f** (Lengauer–Tarjan dominators over `StateGraph`) against it — answered as a set
      of acts, no picture. This is the real first deliverable.
- [ ] Try A2 (recusal-breaks-quorum) as the flagship finding.
- [ ] Only then revisit whether a DAG rendering earns its keep, against P2's gate.
