<!--
Status (2026-09-23): an EVIDENCE RECORD, not a spec. This is the dossier the §5.1.3 anchor-slot
cards were written from (EVERY-EACH-QUANTIFIER-SPEC.md §2.6 records how each was marked, on
2026-09-21). It was written on 2026-09-15 to a session scratch directory, which was later lost;
this copy was recovered from the writer's own transcript on 2026-09-23 and is otherwise the text
as written. The prior-art reports (`reports/*.md`), the two proposals (`proposals/*.md`) and the
scratch copy of the spec (`spec-unstable.md`) it cites were session files and are NOT in the
tree, so a citation of the form "per `reports/X.md` §Y" cannot be followed from here. Line
numbers are on the commits it names, not on today's tree.
-->

# The Anchor-Slot Bench — rulings for §5.1.3 of `EVERY-EACH-QUANTIFIER-SPEC.md`

Synthesised 2026-09-15 (session every-each) from seven prior-art reports (`reports/*.md`), two
design proposals (`proposals/minimal.md`, `proposals/maximal.md`), and an adversarial pass in which
every finding was put to two independent checkers: a finding is **confirmed** only when both upheld
it, **refuted** only when both refuted it. Counts: minimal — 26 confirmed (4 fatal), 3 refuted;
maximal — 40 confirmed (5 fatal), 1 refuted. The four refuted findings are in Appendix A and are
not resurrected here.

Trees. The spec is read at `unstable` `e578654c` (§5 is byte-identical at `388f8605`, the reference
checkout's HEAD; the scratchpad copy `spec-unstable.md` has the line numbers cited as `spec:N`).
Track 6 is **committed locally** as `5a851da5` on branch `every/anchors`
(`~/src/legalese/l4wt/every-anchors`, unpushed, unmerged) with an **uncommitted overlay** on 16
tracked files (Machine.hs mtime 20:27, binary rebuilt 20:31) that applies several of the repairs the
adversarial pass asked for; where a card depends on the overlay it says so, because a proposal that
cites 5a851da5 alone is already stale. **READ** marks what I opened this session; everything
attributed to a primary paper was read by the report's author, not by me, and is cited as "per
`reports/X.md` §Y".

House style follows §2.5 and §2.2.7.8: one question per card; options; what decided it; the spec
amendment in draft words; confidence. Cards B1–B7 are the seven the brief asked for; B8 and B9 were
added because the evidence forced two questions that belong to Meng and to nobody else.

---

## 0. One-page summary

**The question** (Meng, 2026-09-15, verbatim in `CONTEXT.md:10-14`): stanzas for `THE OPENING`,
what the default reference point is without it, and whether "the more general notion" — the anchor
slot as an expression over trace time points — answers the dangling / re-entrancy / spelling
concerns that declined it (W3, 2026-09-08).

**What the seven traditions agree on.** (1) A window's opening is an instant computed from the
anchor, never an event a party performs; it dangles only when its anchor does, and never on its own
— every report supports H3, and W3's stated reason conflated the two (timed-csp §Verdict H3;
timed-automata §Verdict H3; mtl-tptl §Verdict H3; event-calculus §Verdict H3; bpmn §Verdict H3;
legal-time §Verdict H3; corpus §Verdict H3). (2) No formalism has a **noun** for the lower edge — MTL
writes an interval endpoint, TPTL a second bound on one frozen variable, Symboleo `Date.add(p, 3,
days)`, BPMN token arrival, statute a defined term (mtl-tptl §Spelling 1; event-calculus §Spelling;
legal-time §Worked example). (3) The enclosing obligation's own points are **binders**, bound where
the continuation is evaluated; they cannot dangle and they rebind per instance for free (TPTL's
freeze quantifier, AH94 Def. 3 and §2.3.1, per mtl-tptl §Dangling 1 / §Re-entrancy; Timed CSP's
prefix shift, per timed-csp §Mechanism; UPPAAL's per-instance clocks, per timed-automata). (4) No
tradition puts a bare NUMBER on the time axis; the anchor's sort is a date or instant with a unit
(bpmn §Verdict H1; corpus §Spelling — `ny-environmental-7.3.golden:18` prints `WITHIN 740775`, a date
serial consumed as a duration). (5) No tradition makes the **drafter** record a lifecycle point:
Symboleo and ecXML emit them automatically (event-calculus §Verdict H2 (i)). (6) When an anchor does
not exist, no read tradition supplies a default: ECA and Timed CSP say _not enabled_, TMDL-persistent
says _watch_, Camunda halts, Catala aborts, and Tonetta's `def` is a model constant; five of the six
reports that consider a language default to the origin refuse it (PA-1, P9 confirmed).

**Where they split.** _Freeze vs live_: timed automata, Symboleo and TMDL-persistent evaluate an
anchor at the edge, live (timed-automata §Verdict H2); Camunda, TMDL-non-persistent and Davies'
event precondition freeze it once (bpmn §Re-entrancy; event-calculus §Mechanism; timed-csp
§Dangling). The corpus is on freeze's side only because all 12 cross-rule references precede the
arming (corpus §Verdict H2). _Does `AFTER` re-anchor_: CSL and BPMN's natural shape say yes,
`after 3D within 30D` is [τ+3, τ+33] (event-calculus §Mechanism; bpmn §Worked example); MTL, TPTL
and UPPAAL draw both edges on one clock (mtl-tptl §Spelling; timed-automata §Worked example); R-X5
chose the latter. _Reaching another rule's point_: Symboleo by name (`Fulfilled(obligations.x)`),
ecXML by narrative, CSL not at all — a clause sees only its lexical ancestors — and Timed CSP only
through a synchronised timer process (event-calculus §Mechanism; timed-csp §Mechanism); statute
cites by section (legal-time §Verdict H2).

**The two proposals.** _Minimal_ (`proposals/minimal.md`): the three nouns become NUMBER-valued
expressions in the continuation's scope, nearest-enclosing; `THE OPENING` is `THE JOIN + d`; zero
keywords, track 6's `Anchor` node retires; other rules' points go through the ledger (`COMMIT` /
`RECALL`), frozen at first scrutiny, `MAYBE` refused so the drafter writes the default. _Maximal_
(`proposals/maximal.md`): a `Point` grammar — four frozen INSTANT binders (`ARMING`, `OPENING`,
`JOIN`, `DEADLINE`), live look-ups `THE Noun OF rule [FOR p]` and `THE FIRST/LAST Pattern` over an
auto-written lifecycle log, a `PENDING` state, `AFTER`/`BEFORE` reserved, T1's sorts assumed built.
**Both fail on the same fatal point**: the machine runs the operands of `RAND`, the members of a
barrier and the branches of a fork **sequentially over the whole event stream** (`Machine.hs@388f8605:1124-1130`,
`:1797-1804`, `:2205-2208`), so any cross-rule read — a frozen `RECALL` or a live `THE JOIN OF r` —
is decided by operand order, not trace order: the same trace is FULFILLED with `seller RAND buyer`
and BREACHED with `buyer RAND seller` (minimal SEM-2; maximal SEM-1/R2, probed). Neither proposal
costs the scheduler or two-pass evaluation that would fix it.

**Recommendation.** Not either proposal. Take the minimal's surface — nouns as ordinary values in
the continuation's scope, `THE OPENING` as arithmetic, zero keywords (B1, B2) — with the reach rule
stated as **lexical**, which is what the mechanism already does and what the freeze quantifier means
(B1). Rule the day-counting default in s 50(a)'s words and leave the calendar to the library and the
sort to T1 (B6). Amend W3's words, not its mark (B7). **Decline both cross-rule channels for now**
(B3): neither is coherent on today's machine; when an event-major step lands, prefer by-name over
drafter-`RECORD`. Keep freeze for binders, refuse `MAYBE` in the slot, and record _pending_ as the
general slot's answer with its cost named (B4). Rule re-entrancy as per-instance for binders and
ordinal-explicit for look-ups (B5). Ratify track 6's overlay repairs — delete-not-shadow, the
barrier's latest member deadline, the empty cast — as rulings, not build decisions (B9), and fix
`THE JOIN` under `LEST` and in a kept `SHANT` by modal, per §5.2's own three arms (B8).

---

## 1. The cards at a glance

| id  | question, in a phrase                                                        | recommended                                                                        | confidence |
| --- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ---------- |
| B1  | are the three nouns values, or anchor-only syntax; what becomes of `Anchor`? | (b) values, lexically scoped; `Anchor` collapses to `Maybe (Expr n)`               | medium     |
| B2  | `THE OPENING`: a fourth value, `THE JOIN + d`, or stays declined?            | (a) arithmetic; R-X5's bare-edge default stated; empty-window check owed           | medium     |
| B3  | another rule's point: ledger idiom, by-name syntax, or neither?              | (c) neither now — lexical reach + argument passing; by-name when a scheduler lands | high (now) |
| B4  | freeze at arming over the past; what a `NOTHING` there means                 | (a) freeze for binders, `MAYBE` refused; (c) pending recorded as the slot's answer | medium     |
| B5  | re-entrancy: last occurrence by default, or explicit?                        | (b) binders per instance; look-ups ordinal-explicit, scoped since arming           | medium     |
| B6  | the day-counting convention; library or language?                            | (a) document s 50(a) for both edges; calendar in the library; day sort under T1    | high       |
| B7  | is W3 amended, and in what words?                                            | (b) mark stands; reason retracted; measurement amended, words below                | high       |
| B8  | `THE JOIN` under `LEST`, and in a kept `SHANT`'s `HENCE`                     | (b) by modal, per §5.2: violating stamp / the deadline; refuse for MUST/MAY LEST   | medium     |
| B9  | a barrier's `THE DEADLINE` with no `ONCE`-line `WITHIN`; the empty cast      | (a) latest member act deadline; empty cast joined at arming                        | high       |

---

## 2. The cards

### B1 — Lifecycle nouns as VALUES vs anchor-only syntax; what track 6's `Anchor` node becomes

**The question.** Do `THE JOIN`, `THE DEADLINE`, `THE ARMING` become ordinary expressions in the
continuation's scope (usable in `PROVIDED`, a `COMMIT` value, a `WHERE`, arithmetic in the `OF`
slot), or stay a four-constructor syntax node reachable only after `OF`?

**Options.**

- (a) **Anchor-only syntax**, as built: `Anchor n = AnchorJoin | AnchorDeadline | AnchorArming |
AnchorAt (Expr n)` (`Syntax.hs:585-592` at 5a851da5, READ via checker votes); the nouns are
  matched by spelling after `OF`; `THE JOIN + 3` does not parse. Bolt `± Expr` onto the noun
  constructors to write S1 but not S6 (minimal R-M1(c)).
- (b) **Values, lexically scoped.** One `Expr` constructor `Lifecycle Anno LifecyclePoint`; a noun
  denotes the nearest obligation enclosing the position where it is **written**, a `WHERE`-bound
  alias carries that binding inward, and a continuation handed on as a value receives an outer point
  by **argument** (`HENCE k THE JOIN`) — the CSL template-parameter device (per event-calculus
  §Mechanism). `Anchor` collapses to `Deadline { duration :: Expr n, anchor :: Maybe (Expr n) }`.
- (c) **Values, dynamically scoped**: a noun denotes the obligation the continuation is attached to
  _when it runs_, which is what track 6's overlay now does for handed-on values (`Handoff` frame,
  `rebindLifecycle`, overlay `Machine.hs:1770`, `:2584-2591`; spec overlay §5.1.1.1 "Threading,
  chosen: … rebound into its value", READ).

**What the literature and the corpus say.** Every formalism with time values makes the enclosing
points values in scope: TPTL freezes the current time to a name (`x.φ`, AH94 §2.2.3, per mtl-tptl
§Mechanism); Symboleo makes every lifecycle event a `Point` usable in `Date.add` (`Symboleo.xtext:189-271`,
per event-calculus §Mechanism); CSL's `remaining z` binds the deadline as a number (Hvitved §2.3,
per event-calculus). The freeze quantifier is **lexical**: `x.` and `y.` are distinct variables
both visible in the inner scope (AH94 Def. 3; §2.3.2 "constraints between distant contexts", per
mtl-tptl §Mechanism and PA-3 checkers, who read `out-ah94.txt:223-238, 331-336`). The
overall-budget clause — acknowledge, then resolve, all within 30 of receipt — is the BCM10 Thm. 9
witness and needs the outer point captured from two levels down (mtl-tptl §Spelling 3).

The corpus never spells a noun: `JOIN`, `DEADLINE`, `ARMING`, `OPENING` occur 0 times as
identifiers (corpus §Spelling; `corpus-hits.md` §Other counts), and every re-anchored or opening-edge
window it has is arithmetic over a `DATE` (`the day after (das Fristende zu f)`,
`fristberechnung.l4:326`; `Publish date PLUS 14`, `ny-environmental-7.3.l4:64-65`).

What the adversarial pass established about each option (confirmed unless marked):

- (a) is built and works, but its reach is bounded: `THE ARMING` two levels down names the middle
  obligation, and a four-obligation chain cannot reach the first join (PA-3 checker 2; track 6 spec
  §5.1.1.1 "whether a deeper continuation should be able to reach the outermost arming is open").
- (b)'s mechanism already exists and is lexical whether or not the proposal says so: a `WHERE`
  local is an `Unevaluated _ expr env` thunk closed over the environment at `WHERE` time, which
  `continueWithFollowup` has already `bindLifecycle`d with the OUTER point; a later inner hand-off
  builds a new map and does not touch the captured one, and `rebindLifecycle` rewrites only
  obligation-shaped values, never a NUMBER thunk (F4, both checkers; PA-3 checker 1 **ran**
  `probe-where-under-hence.l4` on the track 6 binary: a `WHERE received MEANS 10` at the outer
  `HENCE`-body level reaches an inner `OF received` across a nested hand-off, deadline 40). The
  minimal proposal's §4 R-Q7B row denies this ("not lexical capture") — that denial is false of its
  own mechanism (F4).
- (b)'s ARMING needs a mechanism the minimal proposal does not give it: `THE ARMING` at top level
  falls back to the act frame's own `armed` (`Machine.hs:1563` at 5a851da5) and on a join line to
  `ctx.time` in `Barrier3`; collapsing `Contract4` to `continueExpr env e` loses both, flips the
  `after delivery` witness (19 → 14) and turns `own arming` into a run-time refusal (F1, both
  checkers, reasoned from code). Repair: insert-if-absent at the arming site and in `Barrier3`
  (`Map.insertWith (\_ old -> old)`), or a fifth check-time refusal for `ARMING` outside a
  continuation.
- (b) with `THE …` only as an `Expr` alternative does not let a noun be a juxtaposed application
  argument: `atomicExpr'` is `lit | nameAsApp | paren expr` (`Parser.hs:2028-2032`), so S2's
  `maximum1 THE JOIN (…)` fails at `THE`; write `(THE JOIN)` or add `Lifecycle` to `atomicExpr'`, and
  say which, because `parensIfNeeded` treating it as atomic in the printer would otherwise break the
  §3.2 round trip (F10, both checkers, probed with the `IF`/`NOT` analogue).
- (c) was built by the overlay to cure a real defect — at 5a851da5, factoring an inline continuation
  into a named rule silently moved its deadline, 45 → 60 (minimal SEM-5, **refuted** only because
  the overlay had already fixed it; Appendix A) — and it is the right answer for _handed-on
  obligation values_. It is not recoverable for NUMBER aliases (a thunk's env is fixed at creation,
  F4 checker 2), so (b) and (c) are not rivals: obligation values rebind dynamically at hand-off,
  NUMBER aliases capture lexically. Record both.
- Cost: `Percent`/`Inert`/`AsString` are matched in 16–23 files; a new `Expr` constructor touches
  ~21 modules under `-Wall -Werror` (R7 checkers); retiring the noun constructors touches
  `Desugar.hs`, `Parser/ResolveAnnotation.hs`, `TypeCheck/Annotation.hs`, `Export/Document.hs`
  (which **renders** anchors, `anchorProse`, and must render the noun, not refuse), `TypeCheck/Types.hs`,
  `ContractFrame.hs`, `Parser.hs`, `MLIR/Schema.hs`, `Backend/Jl4.hs`, plus spec §5.1.1.1 and
  §11.0.1 (F9). A token-less enum keeps the keyword highlight if both `Expr` `ToSemTokens` instances
  gain a `Lifecycle{}` arm (F3 **refuted**; Appendix A).

**Recommended: (b), with (c) retained for obligation values.** What decided it: the freeze
quantifier is lexical and the machine is already lexical for NUMBER thunks, so ruling (b) records
what exists and answers §5.1.1.1's open item; the two-level witness `of the arming` (deadline
5 + 40 = 45, `run-anchors.l4:100-124`) shows bare nouns reach one hop, and the `WHERE` capture is the
only device that reaches further without a ledger. Option (a) cannot write S6's `COMMIT `received
at` IS THE JOIN` or any `PROVIDED` over a point. The sort stays `NUMBER` until T1 lands (B6); the
five check-time refusals track 6 prints (`NoEnclosingObligation`, `OnJoinLine`, `JoinUnderLest`,
`EnclosingHasNoDeadline`, `AnchorNotAnInstant`; `TypeCheck/Types.hs:217, 406-420`, READ) move to
`inferExpr`'s `Lifecycle` arm with their text unchanged — refusals 1, 3 and 4 are **ratified by this
card**, 2 is B8's, 5 is B4's.

**Amends.** §2.4: replace `Anchor ::= 'THE' (JOIN|DEADLINE|ARMING) | Expr` with

> `Expr ::= … | 'THE' ('JOIN' | 'DEADLINE' | 'ARMING')  -- a lifecycle point of the nearest enclosing obligation, by spelling; a NUMBER on the trace's scale (an INSTANT under T1)` > `TemporalConstraint ::= 'WITHIN' Expr ['OF' Expr]  -- OF is the anchor throughout the duration slot (§5.1.1.1); a Lifecycle is atomic in application position`

§5.1.1, R-Q7B, add after "matched by spelling":

> **Amended 2026-09-15 (B1).** The three nouns are expressions, not a syntax node reachable only
> after `OF`. Scope is **lexical**: a noun denotes the nearest obligation enclosing the position
> where it is written; a `WHERE`-bound name over a noun carries that value into deeper
> continuations, which is how "acknowledge, then resolve, all within 30 days of receipt" is
> written; a continuation that arrives as a value (`GIVEN k IS A DEONTIC …`, a top-level rule named
> in a `HENCE`) is re-anchored to the obligation it is attached to when it runs (§5.1.1.1's
> `Handoff`) and receives any outer point as an argument. The four check-time refusals of
> §5.1.1.1 items 1, 3, 4, 5 are ruled, not build decisions. `THE ARMING` with no enclosing binding
> is the obligation's own arming (top level) or the `EVERY`'s (join line), bound at the arming site
> and in `Barrier3` only when absent.

§5.1.1.1: the "Syntax" paragraph re-cites `Deadline { duration, anchor :: Maybe (Expr n) }`; the
"Printers and exporters" paragraph adds `Export/Document.hs` and `Nlg.hs` as **rendering** the noun.
§11.0.1's ledger entry gains the constructor change and the file list above.

**Confidence: medium.** The lexical claim is measured for `WHERE` locals on the track 6 binary and
reasoned from code for the nouns-as-Expr form (nothing with `THE JOIN` as an expression has been
built or run). The cost is larger than either proposal counted.

---

### B2 — `THE OPENING`: a computed fourth value, `THE JOIN + offset`, or stays declined

**The question.** How is the re-anchored window — Meng's "after a three-day cooling-off period,
within 30 days starting at the end of it", [13, 43] on the worked trace — spelled, and does a fourth
lifecycle noun return to do it?

**Options.**

- (a) **Not a value.** `THE OPENING` is `THE JOIN + d` (or `THE ARMING + d`, `THE DEADLINE + d`),
  written as arithmetic in the closing edge's `OF`; with track 7, `AFTER d WITHIN w OF (THE JOIN + d)`
  — or, bound once, `AFTER 0 OF opening WITHIN 30 OF opening WHERE opening MEANS THE JOIN + 3`.
  R-X5's "AFTER does not re-anchor" stands, with the bare-edge default stated (below).
- (b) **A fourth bound value** computed from the `AFTER` edge when written, refused otherwise (the
  maximal's binder; the spec's own "rejected spelling" at §5.1.2, `WITHIN 30 OF THE OPENING`).
- (c) **Make `AFTER` re-anchor**, so the sentence is bare `AFTER 3 WITHIN 30` (CSL Fig. 2.6;
  BPMN's natural shape) — amends R-X5 and puts the statutory two-offset window ("not less than 2 nor
  more than 4 months after", _Dodds_) onto the hand arithmetic instead.
- (d) **Stays declined as ruled**; write [13, 43] by hand as `WITHIN 33` and enforce the opening
  with a `PROVIDED` guard, as `ny-environmental-7.3.l4:60-74` does today.

**What the literature and the corpus say.** No formalism names the lower edge (mtl-tptl §Spelling 1
"Nobody names a window's lower edge"; event-calculus §Spelling "No language has a noun for 'the
opening'"); the legal tradition names it by a **defined term** — "the end of the cooling-off
period", or reg 31(2)'s "the first day of the 14 days mentioned in regulation 30" (legal-time
§Spelling; P12 checkers read reg 31(2) live: "beginning with the first day of the 14 days mentioned
in regulation 30(2) to (6)"). C and D are the same TPTL formula, `y.F(order ∧ 3 ≤ y ≤ 33)`
(mtl-tptl §Worked example); in Timed CSP the opening is the `;` after `WAIT 3` (timed-csp §Worked
example); in UPPAAL a reset at the silent edge is the same timed language as no reset
(timed-automata §Worked example). On (c): CSL's reduction rule is `after e1 within e2 ⇓τ (τ+n1,
τ+n1+n2)` — CSL re-anchors (Hvitved Fig. 2.6, per event-calculus §Mechanism), and BPMN's boundary
timer starts at token arrival, so [13, 43] is the shape a modeller draws by default and [13, 40]
needs a sub-process (bpmn §Worked example). MTL's `F_{[3,33]}`, TPTL's one variable and UPPAAL's
one clock draw both edges from one anchor (mtl-tptl §Spelling; timed-automata §Worked example).

Corpus: 0 deontic encodings of a re-anchored window; 0 `OF THE OPENING`; 2 inert ones
(`fristberechnung.l4:179, :326`, BGB §§ 187(1), 190), goldened, whose header declines the deontic
layer because `WITHIN` "takes a bare NUMBER, holds no unit and counts ticks on a nameless axis"
(Punkt 8, `:1352-1355`, per corpus §Mechanism 1 and PA-9 checkers who READ it). The four nouns:
0 identifier uses.

What the adversarial pass established:

- (b)'s binder has no value when the opening is a point-form look-up (`AFTER (THE LAST …) WITHIN 30
OF THE OPENING`: live or frozen-NOTHING, two answers; maximal SEM-3 (iii), P1), and the maximal
  reinstated the declined spelling with no card (R8, both checkers).
- (a)'s arithmetic is mis-stated in the minimal's own S1 gloss: under the machine's convention
  `WITHIN 30 OF (THE JOIN + 4)` closes at 44, not the [14, 43] the day-granular statute gives; the
  correct spellings are `WITHIN 29 OF (THE JOIN + 4)` or `WITHIN 30 OF (THE JOIN + 3)` (PA-5, both
  checkers; checker 2 **ran** all three on the track 6 binary). This is B6's convention question
  showing up in B2's example.
- Per-edge `OF` with the minimal's "both default to the continuation's default" reading is
  unflagged: under the equally available "an edge with no `OF` inherits the other edge's anchor"
  reading, S1 opens at 16, not 13 (F2, both checkers; spec §5.1.2's "Both edges measure from the
  same anchor" is ambiguous between them). And two explicit `OF`s can make an empty window (`AFTER 5
OF THE DEADLINE WITHIN 30`, join 10, deadline 100) with no diagnostic (SEM-8 checker 2); the
  spec's owed compile-time check (`AFTER 30 BEFORE 5`, §5.1.2 "What this sketch owes") is not
  addressed by either proposal (R14).

**Recommended: (a).** What decided it: every tradition writes the opening as arithmetic or a defined
term; the `WHERE`-bound single spelling is the defined-term idiom in L4 and removes the double
spelling of the offset; (b) needs `AFTER` (track 7) and a fifth refusal for an opening that does not
exist; (c) is attested (CSL, BPMN) but reverses Meng's own R-X5 modify and moves the more common
statutory shape (two offsets, one anchor — 9 corpus encodings, all inert or Boolean, `corpus-hits.md`
§Opening edge) onto the hand arithmetic. (d) is where the corpus lives today and is the fallback if
B1 is not taken.

**Amends.** §5.1.2, after "**`AFTER` does not re-anchor.**":

> **Read as ruled 2026-09-15 (B2):** an edge with no `OF` counts from the continuation's default
> origin (§5.1), never from the other edge's anchor. The re-anchored window is written on the
> closing edge — `AFTER 3 WITHIN 30 OF (THE JOIN + 3)`, or with the opening named once,
> `AFTER 0 OF opening WITHIN 30 OF opening WHERE opening MEANS THE JOIN + 3` — and is [13, 43] on the
> exclusive-day convention (§5.1.2.2). A window whose closing instant precedes its opening is a check
> error when both offsets are literals and a run-time diagnostic otherwise, in the same place R-X6's
> early-act diagnostic is raised.

§5.1.3: the "rejected spelling" block at §5.1.2 stays labelled rejected; its replacement is the
sentence above. Docs: `doc/reference/regulative/README.md` gains the `WHERE opening MEANS` idiom
once track 7 lands.

**Confidence: medium.** High that no noun is wanted; medium on the bare-edge default, which the spec
text supports both ways and which nothing built can measure until `AFTER` exists.

---

### B3 — References to OTHER rules' points: ledger idiom only, or by-name syntax

**The question.** When one rule's deadline is measured from another rule's lifecycle point — a
sibling's join, a barrier's completion, another statute section's deadline — how is the reference
made?

**Options.**

- (a) **The ledger idiom, drafter-written** (minimal H2): the referenced rule `COMMIT`s its point
  (`COMMIT `delivered at` IS THE JOIN`), the referring rule `RECALL`s it in the `OF` slot; no new
  syntax.
- (b) **By name** (maximal): `THE JOIN OF rule [FOR member]`, `THE FIRST/LAST [PARTY p DOES]
Pattern`, read from a lifecycle log the machine writes itself; `RuleRef` is a `MEANS`-bound name.
- (c) **Neither, now.** Ancestors' points by lexical capture (B1's `WHERE`), handed-on continuations
  by argument, the counterfactual "as it would have ended" by the `LEST` binder (below); no
  sibling channel until the machine can order sibling reads by trace position.
- (d) Both (a) and (b).

**What the literature and the corpus say.** Symboleo, TMDL, ecXML and timed contract automata name
**any** rule's point; CSL restricts to lexical ancestors and threads instants sideways by template
parameter (event-calculus §Verdict H1; Hvitved §2.3.4 per event-calculus §Mechanism). Timed CSP
reaches another process's past only by synchronisation — Roscoe's timer-as-a-process, `setup` /
`timesout` — and warns that shared absolute stamps create synchronisations "when there is no
mechanism to achieve it" (timed-csp §Mechanism, §Re-entrancy; TPC §14.5). Statute cites the other
rule by section, "as determined in accordance with Article 9(2)", which is closer to a name than a
cell (legal-time §Verdict H2). No tradition makes the drafter record the point (event-calculus
§Verdict H2 (i)); a forgotten `COMMIT` is a wrong-answer-exit-0 the prior art lacks.

Corpus: 12 cross-rule references, every one arming-at-the-event or inert; 23 files use the ledger,
**0** use `RECALL` with `WITHIN` (corpus §Verdict H2; `corpus-hits.md` §Other counts). The one
statute that needs the reference — UK SI 2013/3134 reg 31(2)/(3), Directive 2011/83 Art 10 — is
unencoded.

What the adversarial pass established — this is the finding that decides the card:

- **Both channels are order-dependent on today's machine, and fatally so.** `ValROp` pushes
  `RBinOp1` and applies the LEFT regulative operand to the full `[time, events]`; only when it has
  returned does `RBinOp1` apply the RIGHT operand to the same full stream (`Machine.hs@388f8605:1124-1130`,
  `:1797-1804`); barrier members and fork branches are likewise run one after another over the whole
  stream (`:2205-2208`, `:2153-2158`). There is no global event-stepped scheduler; a `#TRACE` takes
  one regulative expression, so sibling rules co-run only as `a RAND b`. Minimal SEM-2 **probed**
  (`refute-minimal-sem/p5-sibling-ledger.l4`, re-run by both checkers): `(seller delivers WITHIN 60
HENCE COMMIT …) RAND (buyer pays WITHIN 30 OF (fromMaybe 0 (RECALL …)))`, Deliver@10, Pay@35 —
  seller-left FULFILLED, buyer-left BREACHED at deadline 30; with a Ping@1 the frozen anchor reads
  the COMMIT made at trace-time 10, information from the future. Maximal SEM-1/R2 **probed**
  (`refutations/maximal-sem/order.l4`): `delivery RAND payment` FULFILLED, `payment RAND delivery`
  a residual. SEM-2 checker 1 showed the order dependence is pre-existing `RAND` semantics that a
  cross-rule read merely exposes. The maximal's M5 "visible iff it precedes in trace order" is a
  semantics its described mechanism (a log "threaded like the ledger") cannot compute; the repair is
  a two-pass evaluation with a static acyclicity check, or an event-major machine — a rewrite of
  `Contract1..11`, `RBinOp1/2`, `Barrier1..4` and the fork fold — costed by neither proposal.
- The minimal's supporting number, "matches 12/12 corpus cases", is vacuous: none of the 12 reads
  a cell, so (a), (b) and pending all match 12/12 (PA-2, both checkers). Its precedents for
  freeze-with-default — Camunda 7 `reevaluateTimeCycleWhenDue`, TMDL non-persistent — are a
  timeCycle re-evaluation flag and a rule that never arms when the anchor is unprovable, not a
  drafter default (PA-2; checker 1 READ `camunda7.txt:583-600`, `gov2007.txt:150-170, 349-358`).
- The minimal's S6, offered as the clause "enclosing-only nouns cannot express", is expressible with
  bare `OF THE ARMING` at depth 2 — the enclosing's arming _is_ the receipt instant — so its
  `fromMaybe THE ARMING (RECALL …)` default equals the recorded value and the golden would pass for
  the wrong reason (SEM-7, both checkers; checker 2 ran depth-2 and depth-3 variants: 40 and 42).
  The inexpressibility claim bites only at depth ≥ 3, where B1's `WHERE` capture is the answer.
- The counterfactual reference — reg 31(3) "12 months after the day on which it would have ended
  under regulation 30", Art 10(1) — does **not** need a sibling channel: reg 31(3) nests as reg 30's
  `LEST`, where `THE DEADLINE` is bound although the join never fired (minimal PA-4 **refuted** on
  exactly this; Appendix A; checker 1 ran the nested encoding on the track 6 binary: residual `MAY
cancel WITHIN 289` = 10 + 14 + 365). The minimal never says this and nominates regs 30–31 as the
  test "exercising S6" without a sketch (F6); the maximal's S6 mis-models Art 10 (SEM-8: cap runs
  from the end of the initial period, not `THE ARMING PLUS 365`; both checkers READ Arts 9–10).
- The maximal's by-name form has further unruled semantics: `THE JOIN OF <barrier>` without `FOR`
  is ambiguous between the barrier's firing and member completions logged as joins (SEM-4); a
  mutual `THE DEADLINE OF` reference passes the self-reference guard and leaves two MUSTs pending
  forever, loud but undetected statically (SEM-6); look-ups are read from a global prefix, so an
  occurrence before the referring obligation armed silently anchors its window into the past (P3);
  `THE Noun OF r` lives in a log with no trace position, so same-stamp visibility is undefined for
  computed points (SEM-5); the bare recorded-event anchor R-Q7 requires (`OF notice`,
  `README.md:82-95`) is dropped from the grammar without a card (R4).
- Minimal R-M4(i) ("same-stamp visibility") is mis-scoped: the dependence is on operand order over
  the whole trace, not same-stamp ties (SEM-2). The ledger's rows carry wall-clock `at=`, not
  trace-time valid time (SEM-2, SEM-6 checkers READ the printed `Official record`).

**Recommended: (c) now; when the machine gains an event-major step or two-pass evaluation, (b)
by name over an auto-written log, keyed by instance — never drafter-`RECORD`.** What decided it:
the fatal probes above; the fact that the three shapes the corpus and the cited statutes actually
need — ancestor reach (S6 at depth ≥ 3), handed-on continuations, the counterfactual deadline — are
each writable without a sibling channel; and event-calculus §Verdict H2 (i) on the forgettable
`COMMIT`. The `RECORD`/`RECALL` idiom remains legal L4 for **data**; this card rules only that a
`RECALL` in an anchor whose cell is committed by a `RAND`/`ROR` sibling is a documented hazard
(machine order) until the scheduler exists — a warning, not a refusal, because the checker cannot
see operand order.

**Amends.** §5.1.3 (replacing "The direction, as this spec reads it"):

> **Scoped 2026-09-15 (B3).** The slot is an expression over instants the continuation can reach
> **lexically**: its own points (B1), a `WHERE`-bound name over an ancestor's point, an argument
> passed to a handed-on continuation, a `DATE`, and (under `LEST`) the missed deadline of the
> enclosing obligation — which is how "12 months after the day on which it would have ended under
> regulation 30" (SI 2013/3134 reg 31(3)) is written, as reg 30's `LEST`. A reference to a
> **sibling** rule's point — by `RECALL` of a cell it wrote, or by a name — is **not ruled and not
> supported**: the machine applies the operands of `RAND`/`ROR`, a barrier's members and a fork's
> branches one after another to the whole event stream (`Machine.hs:1124-1130`, `:1797-1804`,
> `:2205-2208`), so such a read is decided by operand order, not by trace order (measured
> 2026-09-15: the same trace FULFILLED under `seller RAND buyer`, BREACHED under `buyer RAND
seller`). A sibling channel waits on an event-major machine step or a two-pass evaluation with a
> static acyclicity check over rule references; when one lands, the reference is by rule name over
> a log the machine writes at each transition, keyed by instance, and never by a cell the drafter
> must remember to write. `RECALL` in an anchor is legal for recorded **data** and is documented as
> reading the ledger in machine order.

§8.3 (RAND/ROR): one sentence that regulative conjunction is sequential over the whole stream and
that `RAND` commutes only while operands do not communicate. `doc/reference/control-flow/REFUSE.md:119`
("commit to no demand order at all") is owed a qualifier (R2 checker 1).

**Confidence: high** that neither channel is coherent today (two probes, four checkers); **medium**
on the eventual preference for by-name.

---

### B4 — The freeze rule: the anchor evaluated once at arming over the past, and what a `NOTHING` there means

**The question.** When is the `OF` expression evaluated, and what does the machine do when it has no
value?

**Options.**

- (a) **Freeze**, as built: forced once at the first scrutinised event after arming (`Contract4`
  → `Contract4b`), `MAYBE` refused at check time (`AnchorNotAnInstant`), so the drafter writes the
  default (`fromMaybe THE ARMING (RECALL …)`) and the language never supplies one (minimal R-M3(a)).
- (b) **Live**: re-forced on every scrutinised event until non-`NOTHING`; the event-clock, Symboleo
  and TMDL-persistent reading (maximal M6(a)).
- (c) **Pending**: a `NOTHING` closing edge arms the obligation with no deadline — performable,
  cannot breach, a loud residual `deadline: PENDING (awaiting …)` — and a `NOTHING` opening edge is
  R-X6's nullity; the drafter's backstop is `BEFORE <date>` or an explicit `orElse` (maximal
  M2(a)/M3(a)).
- (d) A check error unless an `orElse`/`BEFORE` is present.

**What the literature and the corpus say.** The prior art divides by whether the reference is a
binder or a look-up (mtl-tptl §Dangling 1–2). Binders cannot dangle — closedness (AH94 Def. 3) makes
an unbound reference static, and progress guarantees `y + c` is passed. For look-ups, **no read
source makes a default mandatory and drafter-written** (PA-1, both checkers, against the primaries):
AFH94 guards with `x_a = ⊥ ∨ x_a > 5` as an opt-in disjunct and every other comparison with ⊥ is
false, so the language default is _disabled_ (`afh94.txt:176-177, 251-278`, READ by the checkers);
Tonetta's `def` is a constant in the signature valued by the model, not written by anyone
(`out-tonetta.txt:318-334`); Timed CSP's unarmed `TOC` never fires and "the safer rule is pending"
(timed-csp §Verdict H2); TMDL-persistent and Symboleo `HappensAfter` watch δ and "cannot be violated
before then" (event-calculus §Verdict H2 (ii)); Camunda raises an incident and halts, Catala aborts
(bpmn §Dangling). Directive 2011/83 recital 40 is the legal shape of pending: the right to withdraw
exists before possession, the clock has not started (legal-time §Dangling (a)). Freeze is safe
exactly when the anchor precedes the arming (timed-automata §Verdict H2), which is every one of the
corpus's 12 cases (corpus §Verdict H2) — and is what `HENCE` already gives.

What the adversarial pass established:

- On the freeze as built, "forced once, at the first scrutinised event" is false for the **join
  line**: a join-line `OF e` is forced at `barrierFinish`, after every member has run, and a demoted
  join-line deadline is forced once per member as well — N + 1 evaluations at two trace instants
  (SEM-6, both checkers; probes `p7`–`p10` ran on the track 6 binary; the overlay's spec now states
  it "as a limit"). The rule must name both evaluation points.
- At 5a851da5 an absent lifecycle slot fell through to the OUTER obligation's value —
  `bindLifecycle` used `maybe id (Map.insert …)`, so an empty-cast barrier nested under `WITHIN 10`
  read 10 + 5 = 15, exit 0 (SEM-1, both checkers; probed). The overlay repairs it with `Map.delete`
  (`Machine.hs:2571-2575` working tree; doc-comment records "measured before this was a delete:
  10 + 5 = 15, exit 0"). What remains after the repair is a **loud run-time refusal**, not a static
  one, for an empty cast with no `ONCE`-line `WITHIN` (refusal 6) and a value attached where the
  position does not exist (refusal 7) — so the minimal's "no run-time dangling" is over-strong even
  post-fix.
- The minimal's `fromMaybe THE ARMING (RECALL …)` idiom is the wrong-answer-exit-0 class the
  timed-automata report spells out (`MUST pay WITHIN 30 OF delivery` armed at 0, delivery 10, pay 35
  → BREACH, silently) and it fires whenever any event is scrutinised before the sibling's `COMMIT`
  lands (PA-1, PA-2). The minimal's §3 cites the sources above as support for the opposite of what
  they say (PA-1).
- The maximal's pending has its own holes: a `HENCE` entered while the enclosing closing edge is
  `NOTHING` binds `THE DEADLINE` (declared INSTANT, frozen) to a value that does not exist (SEM-3 (i),
  P1); the arithmetic `NOTHING PLUS 3` is grammatical and unsorted — GRS 2011's `⊥ ± d = ⊥` is the
  convention to adopt (P8, `grs2011.txt:160` READ by the checkers); a mutual `THE DEADLINE OF`
  cycle is two MUSTs pending forever with no static check (SEM-6); and `PENDING` is uncosted where
  results are classified, though a `ValObligation` with a `NOTHING` closing edge already routes
  through `Barrier1` and `RBinOp2` at zero cost, leaving only `Barrier3`'s `assertTime` on a pending
  `ONCE`-line point (SEM-10, narrowed by its checkers).

**Recommended: (a) for binders and for any anchor expression that cannot be `NOTHING`, which is
every anchor B3 leaves in scope; (c) recorded as the ruled semantics of the general slot, to be
built with B3's scheduler; (d) meanwhile — `MAYBE` in the slot stays a check error and the language
supplies no default.** What decided it: with sibling reads declined (B3) every admitted anchor is an
ancestor's point, an argument, a `DATE`, or the bound `THE DEADLINE`, all of which exist by
construction, so freeze is exact and the join-line double evaluation is the only rule to state. When
a look-up is admitted, (b) live and (c) pending are the tradition's two answers and (c) is the one
whose failure is loud; (a)-with-a-drafter-default is the one whose failure is silent, and the
minimal's own precedents for it were misread.

**Amends.** §5.1.1.1 "Resolution and arithmetic", replace the first sentence:

> An **act-line** anchor is resolved once, at the first event the obligation scrutinises after
> arming (`Contract4`); a **join-line** anchor is resolved when the join fires, at `barrierFinish`,
> and — when the join-line deadline is demoted to the members (R-T2) — once more per member at that
> member's first event. Both are stated as the rule, not a limit (B4, 2026-09-15). A hand-off binds
> or deletes all three lifecycle uniques; an absent point is a loud run-time refusal (refusals 6–7),
> never the outer obligation's value.

§5.1.3, after B3's paragraph:

> **A `NOTHING` anchor (B4).** A `MAYBE`-typed expression in the slot is a check error
> (`AnchorNotAnInstant`); the language never substitutes the origin or any other value. When the
> sibling channel of B3 is built, a closing anchor that has no value leaves the obligation
> **pending** — performable (the act counts), unable to breach, printed as `deadline: PENDING
(awaiting …)` and never `FULFILLED` — and an opening anchor that has no value makes an act a
> nullity with R-X6's diagnostic; `NOTHING ± d` is `NOTHING`; the drafter's backstop is `BEFORE
<date>` beside `WITHIN`, the earlier defined edge closing. Not built.

**Confidence: medium.** The freeze facts are measured; the pending semantics is a recorded
direction with two named gaps (`THE DEADLINE` under a pending `HENCE`; static cycle detection).

---

### B5 — Re-entrancy: last occurrence by default, or explicit

**The question.** When the referenced rule fires more than once, which occurrence does a reference
denote?

**Options.**

- (a) **Last occurrence by default**, `THE FIRST` as the opt-in (maximal M4(a); the clock definition).
- (b) **Per-instance for binders; explicit for look-ups.** The enclosing obligation's own points
  rebind at every hand-off (built); a look-up carries a mandatory selector (`FIRST`/`LAST`, or for
  the ledger idiom `RECALL` = last-write / `RECALL ALL` + `maximum`/`minimum`), scoped to occurrences
  at or after the referring obligation's arming unless the drafter says otherwise.
- (c) The drafter's choice by `RECALL` vs `RECALL ALL` + `min`/`max`, no scoping rule (minimal §3).

**What the literature and the corpus say.** A clock is last-write-wins by definition (Alur–Dill
"since the last reset"; AFH `x_a` = largest preceding position, per timed-automata §Re-entrancy);
but **which occurrence an anchor denotes is decided by which instance is asking** — AFH Thm. 6 stores
the anchoring pair in the control state, UPPAAL instantiates a clock per template instance
(timed-automata §Re-entrancy); Timed CSP binds the first `a` in scope by prefix and re-occurrence is
a per-timer drafting choice (reset renaming; timed-csp §Re-entrancy). Binders rebind per evaluation
(AH94 §2.3.1 (1) vs (4), per mtl-tptl §Re-entrancy) — the machine already does this for pattern
bindings and for the lifecycle uniques. The law never uses min/max over a list; it picks one
occurrence with an ordinal adjective — "the last good" (Art 9(2)(b)(i), a **barrier**: last of a
known set, not latest-so-far), "the first good" (Art 9(2)(b)(iii), READ live by the P12 checkers),
_Waltham Forest_'s "the first day on which the authority has sufficient evidence" — the first
satisfaction of a **state**, not an event (legal-time §Re-entrancy; PA-6 both checkers).

Corpus: no encoding names an occurrence; `RECALL ALL` + `maximum`/`minimum` appears in 0 temporal
contexts (corpus §Re-entrancy).

What the adversarial pass established: the maximal's three citations for "LAST by default" do not
support it — Art 9(2)(b)(i) is the barrier, Symboleo-JS's slot is "the runtime's shortcut, not the
semantics" (paper semantics instantiate per trigger), and its S6 "info again, last wins" is not what
Art 10(2) says (P4); a global-prefix `THE LAST` anchors a window into the past for an occurrence
before the referring obligation armed (P3, probed: a MAY closing 19 on an obligation armed at 50 is
silently lapsed); the minimal cites the timed-automata report for `RECALL ALL + minimum = s ↾ A +
first` when that report lists it as a contradiction (PA-6); a state's first satisfaction cannot be a
min over event-written cells unless the onset is recorded (PA-6). For binders, per-instance is
already built and witnessed (`bindLifecycle` per hand-off; the fork's per-branch `THE JOIN`,
minimal S3; the overlay's recursive `cycle n` probe in SEM-5's refutation: 40, then 60).

**Recommended: (b).** What decided it: the tradition's default is last-write for a _clock_ but
instance-scoped for a _reference_, and the law spells the ordinal every time; a language default of
LAST is the silent-wrong-answer class when the referring rule armed after an earlier occurrence.
Since B3 defers look-ups, what this card rules now is the principle and the ledger idiom's
discipline: `RECALL` (last write) and `RECALL ALL` + `maximum`/`minimum` are faithful for **event**
occurrences; first-satisfaction of a state needs its onset committed. Davies' `e ∉ σ(P)` — an
anchor may not read what the anchored rule itself writes — is a checker rule to add when the channel
lands (minimal R-M5 (b); timed-csp §Re-entrancy); for the pattern form it must cover the rule's own
action, not only a `RuleRef` (P11).

**Amends.** §5.1.3, after B4's paragraph:

> **Re-entrancy (B5).** The enclosing obligation's points rebind at every hand-off, so a rule that
> fires twice gives each continuation its own `THE JOIN`, `THE DEADLINE`, `THE ARMING` — a fork's
> branches and a recursive rule's iterations each see their own (witnesses: `run-anchors.l4`'s fork
> and recursion stanzas). A look-up, when built, names its occurrence — `FIRST` or `LAST`, or for a
> recorded cell `RECALL` (last write) / `RECALL ALL` with `maximum` or `minimum` — and by default
> ranges over occurrences at or after the referring obligation's arming; an earlier occurrence is
> reachable only by an explicit `… EVER`-style opt-in, unruled. The first instant a _state_ held is
> not an event and needs its onset recorded. An anchor may not read a point or cell the anchored
> rule itself produces (Davies' `e ∉ σ(P)`), checked statically.

**Confidence: medium.** The principle is well sourced; the scoping default is a design choice with
one counter-case (a genuinely global reference, timed-automata §Re-entrancy) the opt-in covers.

---

### B6 — The day-counting convention the NUMBER scale assumes; library or language

**The question.** Which counting rule does `WITHIN d OF a` (and, when built, `AFTER d OF a`)
follow — trigger day excluded or included, closing day included — and is the calendar a library
matter or a language one?

**Options.**

- (a) **Language states the default; library owns the calendar.** The machine's rule is `stamp >
deadline` expires, so `WITHIN 14 OF (day 10)` accepts day 24: SG Interpretation Act s 50(a) / Reg
  1182/71 Art 3(1) / BGB § 187(1), the exclusive-trigger-day rule. State it in the manual for both
  edges. "Beginning with" is `WITHIN N − 1` by hand. Months, month-end clamps, holidays and business
  days are `daydate`/`fristberechnung` functions over `DATE`, and the deontic layer receives a
  computed instant.
- (b) A `BEGINNING WITH` marker in the language selecting § 187(2).
- (c) Purely library: the anchor is always a `DATE` and the library computes the day; `WITHIN`
  takes the result (`WITHIN 0 OF <computed day>` / `BEFORE <date>`).
- (d) T1 gives the anchor a **day** sort with a bridge in both directions under a fixed epoch, and a
  `DATE` point under a floating epoch is a check error.

**What the literature and the corpus say.** The law has five separately codified rules — exclusive
trigger day by default (s 50(a); Art 3(1); § 187(1); NZ s 54; AU s 36; _Zoan v Rouamba_ [23]); an
inclusive "beginning with" chosen by spelling (_Trow_, a 2:1 split; § 187(2)); the closing day
included to 24:00; corresponding-date months with a clamp (_Dodds v Walker_); and a holiday roll with
a place parameter (§ 193, CPR 2.8) — and no instant anchors at all (legal-time §Mechanism). Which
convention a `WITHIN` follows is unmarked (legal-time §Spelling). `fristberechnung.l4:29-44` treats
the § 187(1)/(2) choice as an interpretive **input**, a three-constructor `ONE OF` (PA-5 checkers
READ it), and its Punkt 8 declines `WITHIN` for want of a unit. The backends all carry the unit in
the literal and refuse a bare number on the time axis; FEEL types `date + number` as `null`
(bpmn §Verdict H1). _Waltham Forest_ turned on one day.

Measured: `run-anchors.l4:44-56` + `tests/run-anchors.golden:5-19` (READ): `WITHIN 5 OF THE JOIN`
with the join at 8 — Deliver AT 13 FULFILLED, AT 14 BREACHED "deadline … 13". So `WITHIN d OF a`
is (a, a + d]: exclusive trigger day, closing day included, at integer granularity.

What the adversarial pass established: the minimal's S1 gloss is off by one on exactly this (PA-5);
the maximal has no `INSTANT → DATE` bridge at all — arithmetic is `INSTANT ± DURATION` only, so a
drafter cannot hand `THE JOIN` to `the day after` or `add months` (P5); under a floating `COMMENCING`
no lift exists and the maximal does not say what `BEFORE (YMD …)` does then (SEM-7); its "existing
goldens: zero" cannot hold with `WITHIN 740775` in a goldened legal file and 8–9 goldened files
with non-literal NUMBER durations (SEM-7); `AFTER`'s inclusivity at `a + d` is fixed by the `> s`
nullity rule but stated in no manual sentence (P5). Both reports and both proposals agree the anchor's
sort should not be a bare NUMBER (bpmn, corpus; PA-9; M1).

**Recommended: (a) now, with (d) as T1's shape.** What decided it: the machine already implements
the majority statutory default and a golden pins it; the calendar is five rules with jurisdiction
parameters, which is a library (R-Q7C's note already lists it as one); a `BEGINNING WITH` keyword
would mark one of five rules and leave the others unmarked. The one **language** consequence is
T1's: the anchor's sort must be a day so that § 187's distinction "has somewhere to live"
(legal-time §Verdict H1), with `DATE ↔ INSTANT` under a fixed epoch and a check error for a `DATE`
point under a floating one.

**Amends.** New §5.1.2.2 (or a paragraph at the end of §5.1.2):

> **Counting convention — RULED 2026-09-15 (B6).** `WITHIN d OF a` admits an act stamped at most
> `a + d` and expires at the first later stamp: the day of the anchoring event is excluded and the
> last day is included, which is Interpretation Act 1965 (SG) s 50(a), Reg 1182/71 Art 3(1) and BGB
> § 187(1); pinned by `run-anchors.l4:44-56`. `AFTER d OF a` admits an act stamped `a + d` or later.
> A period "beginning with" the anchoring day is `WITHIN d − 1`. Months, the corresponding-date rule
> and its clamp, holidays and business days are the date library's (`daydate.l4`,
> `fristberechnung.l4`), applied to a `DATE` before it enters the slot. No convention marker is
> added to the language. The manual states this in s 50(a)'s words for both edges.

§5.1.2.1 (T1), append:

> **What the anchor slot needs from T1 (B6).** The instant sort must lift from and lower to `DATE`
> under a fixed commencement, so a lifecycle point can be handed to the calendar library and its
> result returned to the slot; under a floating commencement a `DATE` point in the slot is a check
> error naming `COMMENCING`. A bare `NUMBER` in a point position is a check error once the sorts are
> separated; until then the nouns are `NUMBER` and §5.1.2.1's silent scale mixing applies to them —
> `doc/` says so.

**Confidence: high** on the default and the library/language split (one golden, five statutes);
**medium** on T1's shape, which is ruled but unbuilt.

---

### B7 — Whether W3 is amended, and in what words

**The question.** Does the decline of `THE OPENING` (W3, marked `a`, 2026-09-07T22:37Z) stand, and
what does §5.1.3 say about why?

**Options.**

- (a) Stands unchanged: reason and measurement as recorded.
- (b) **Mark stands; reason retracted; measurement amended** — declined because no tradition names
  the lower edge and arithmetic writes it, not because a computed instant dangles.
- (c) Reversed: `THE OPENING` returns as a binder (the maximal's S1).

**What the literature and the corpus say.** All seven reports support H3: the opening instant is
computed from the anchor and cannot dangle or re-enter apart from it (§0 above). No formal tradition
has the noun (B2). The measurement: 0 deontic encodings of a re-anchored window still; ≥ 1 inert
(`fristberechnung.l4`, landed 2026-09-14, after W3) that declined the deontic layer on the record
(corpus §Verdict H3); UK SI 2013/3134 reg 31(2) names another rule's opening by defined term, in
force, unencoded — "the need is zero only because the statute has not been encoded" (legal-time
§Verdict H3). The cooling-off count (2 files, both source text) holds exactly (corpus §Mechanism).

What the adversarial pass established: reinstating the noun needs a card (R8) — that card is B2,
recommended against; counting `fristberechnung.l4` as evidence of need for `THE JOIN + d` reads as a
win for a NUMBER-sorted design that cannot meet Punkt 8's objection — the inert need is unlocked by
T1, not by this design (PA-9); "the 2026-09-08 reason — dangling and re-entrancy" over-attributes:
the W3 gloss names only the window that never opens, and re-entrancy is raised against the general
scheme (F11).

**Recommended: (b).** What decided it: the mark was "decline on measurement" and the measurement
stands for the deontic layer; the stated reason is contradicted 7/7 and should not be left in a
document readers believe; the amended measurement must say which design unlocks the inert case.

**Amends.** §5.1.3, replace the paragraph beginning "So §5.1.2's `WITHIN 30 OF THE OPENING` is
**not** the ruled spelling" with:

> **W3 stands; its reason is retracted; its measurement is amended (B7, 2026-09-15).** The
> re-anchored window has no noun because no tradition read has one — MTL's interval endpoint, TPTL's
> second bound on one frozen variable, Symboleo's `Date.add`, BPMN's token arrival, statute's defined
> term — and because `THE JOIN + d` writes it (B2). The reason recorded on 2026-09-08, that a fourth
> anchor "would need its own answer for a window that never opens", conflated the opening instant
> with a party's act: the instant is computed from the join and exists whenever the join does; only
> the join can fail to fire, and that is R-Q7B's question, not W3's (all seven prior-art reports,
> 2026-09-15). Measurement, re-taken 2026-09-15 on `unstable` `388f8605`: 0 deontic encodings of a
> re-anchored window; 2 inert ones in `jl4/examples/ok/closing-the-loop/fristberechnung.l4:179,
:326` (BGB §§ 187(1), 190), goldened, whose Punkt 8 declines `WITHIN` for want of a unit — a need
> T1 unlocks, not this ruling; cooling-off in 2 files, both source text; `WITHIN … OF` in 2 lines,
> both the application `OF` in a never-parsed experiment. One statute in force names another rule's
> opening by defined term, SI 2013/3134 reg 31(2), unencoded; encoding regs 30–31 is the acceptance
> test for B1–B6 (B3 shows reg 31(3) needs no sibling channel).

**Confidence: high.**

---

### B8 — `THE JOIN` under `LEST`, and in a kept `SHANT`'s `HENCE`: refuse, or bind by modal

**The question.** Where the "join" is not a performance — under `LEST`, and in the `HENCE` of a
prohibition that was kept — what does `THE JOIN` denote, and does §5.2's three-arm rule reach the
nouns?

**Options.**

- (a) **As built**: `THE JOIN` under any `LEST` is a check error (`JoinUnderLest`, refusal 2, "a
  build decision open to Meng's ruling"); a kept `SHANT`'s `HENCE` binds `THE JOIN` to the stamp of
  whatever event revealed the expiry, "today's unanchored clock said out loud" (overlay spec
  §5.1.1.1, `README.md:96-97`, READ).
- (b) **By modal, per §5.2.** `SHANT` under `LEST` fires on the violating act, so `THE JOIN` is that
  act's stamp (§5.2's third arm, `spec:1968`; `Machine.hs:1676-1679`); a kept `SHANT` (and a lapsed
  `MAY` routed to `HENCE`) achieves at its deadline, so `THE JOIN` is the deadline instant (the
  R-Q5 review note, spec `:1247` "Success time by modal … `SHANT`/`MAY` at the deadline"; §3.4
  `:1481` "a `SHANT` or `MAY` barrier achieves at the deadline", READ); `MUST`/`DO`/`MAY` under
  `LEST` keep the refusal.
- (c) `THE JOIN` is `NOTHING` under `LEST` (a `MAYBE`), forcing a drafter default.

**What the literature and the corpus say.** CSL stamps blame at `max(τ, τ2)`, the deadline
(event-calculus §Dangling); Symboleo emits `Violated(o)` as a nameable point at the violating event
(`Symboleo.xtext`, per event-calculus §Mechanism; P2 checkers); the spec's own §5.2 rules the `LEST`
origin "by layer and then by modal" with the `SHANT` arm at the violating event's stamp
(`spec:1960-1968`, READ), and its R-Q5 review note already says success time is at the deadline for
`SHANT`/`MAY`. The corpus has `SHANT … WITHIN … LEST … WITHIN` (`ok/prohibition.l4:28-32`) and five
`SHANT … HENCE FULFILLED LEST BREACH` in `regcf-denovo.l4` (P13 checkers).

What the adversarial pass established: at 5a851da5 and in the overlay, a respected `SHANT`'s `THE
JOIN` is the stamp of whatever **unrelated** event revealed the expiry — Bob signs at 12 → refund
due 17; at 30 → 35; nobody → the refund itself reveals it, 45 — for a prohibition discharged at 10
in every trace (minimal SEM-4, both checkers; probed, including `WAIT UNTIL` pseudo-events). Under
the proposals that stamp becomes a drafter-readable value arithmetic builds on. The overlay records
"binding a kept `SHANT`'s join to its deadline … not done: it would part `OF THE JOIN` from the
unanchored default, which §5.2's track is the one to move" (spec overlay, "Raised and NOT changed",
READ) — i.e. it is waiting on exactly this ruling. The maximal collapses §5.2 to "the closing edge
in force at the revealing event" and never mentions `SHANT`, leaving the `SHANT` reparation origin
unnameable (R1, both checkers; P13; SEM-3 (ii)); the `SHANT` violation path fires the `LEST` with a
matched event and `henceEnv`, structurally a join (R1 checker 2). Neither proposal carded the five
refusals as rulings (F5, both checkers) and the spec §5.1.1 lists "whether an anchored `WITHIN`
under `LEST` may name `THE JOIN` at all" as unsettled (`spec:1714-1717`, READ). R9 asks for this
card by name ("M12 — `THE JOIN` under `LEST` by modal").

**Recommended: (b).** What decided it: §5.2 already rules the origin by modal and the machine already
does it for the unanchored clock; a noun that names a different instant from the default it is
supposed to say out loud is the defect SEM-4 measured; the third-party-controls-the-cure-period
defect §5.2 was written to remove reappears under `HENCE` for a kept `SHANT` unless the join is the
deadline. Refusal 2 is kept for `MUST`/`DO`/`MAY` under `LEST` — there the join genuinely did not
fire, and `THE DEADLINE` is the noun.

**Amends.** §5.2, append:

> **The nouns under `LEST` and for a kept prohibition — RULED 2026-09-15 (B8).** By modal, as the
> origin is. Under a `SHANT`'s `LEST` the join is the violating act: `THE JOIN` is its stamp and
> `THE DEADLINE` the prohibition's closing edge (or a check error when it has none). Under a
> `MUST`/`DO`/`MAY` `LEST` no act completed the obligation: `THE JOIN` is a check error
> (`JoinUnderLest`, §5.1.1.1 refusal 2, ruled) and `THE DEADLINE` is the deadline actually missed
> (B9's layer rule). In the `HENCE` of a kept `SHANT`, or of a `MAY` that lapsed to `HENCE`, the
> obligation achieved at its deadline (R-Q5, §3.4): `THE JOIN` is the deadline instant, not the
> stamp of the event that happened to reveal it, and the unanchored `HENCE` clock moves with it
> when §5.2 is built. Measured before this ruling: the same kept prohibition, discharged at 10, gave
> `THE JOIN` = 12, 30, 40 depending on which bystander acted next.

§5.1.1.1: refusal 2's text becomes "`THE JOIN` under a `MUST`/`DO`/`MAY` `LEST` — refused: the join
did not fire; under a `SHANT`'s `LEST` it is the violating act (§5.2)"; the "For a kept `SHANT`"
sentence in the enclosing-obligation paragraph and `README.md`'s matching paragraph are rewritten
to the deadline.

**Confidence: medium.** The rule is the spec's own; what is uncertain is the blast radius on the
unanchored `SHANT`-`HENCE` clock, which §5.2's track owns and has not measured.

---

### B9 — A barrier's `THE DEADLINE` with no `ONCE`-line `WITHIN`; the empty cast

**The question.** In the `HENCE` of a barrier whose `ONCE ALL HAVE` line carries no `WITHIN`, what is
`THE DEADLINE` — and what does an empty cast bind?

**Options.**

- (a) **The latest of the members' act deadlines**, kept as a running maximum, so neither who
  completed last nor the roll's order moves it; an empty cast is joined at its arming and takes the
  `ONCE` line's `WITHIN` when written, else refuses loudly naming the empty cast (the overlay:
  `Barrier2b` `dueLatest`, `BarrierEmpty`, `barrierJoined`, refusal 6).
- (b) The act deadline of the member whose completion fired the join (5a851da5 as committed).
- (c) Refuse `THE DEADLINE` in a barrier `HENCE` unless the `ONCE` line carries a `WITHIN`.

**What the literature and the corpus say.** R-Q7B's own motivation is "the cure period runs from
the date performance fell due, not from the day the last party finally signed" (`spec:1673-1674`,
READ) — a multi-party signing, i.e. this case. The machine's own principle refuses a barrier `HENCE`
that mentions the member variable because "there is no member for the variable to denote"
(`Machine.hs:2183-2189` at 5a851da5) — yet (b) made `THE DEADLINE` denote one member's, chosen by
event order. UPPAAL's obligation is an invariant on the location, one clock for the group
(timed-automata §Mechanism); the barrier's join is `t_last` (spec §3.4 Rule 2), which defines the
stamp and not which member's deadline.

What the adversarial pass established: under (b), `EVERY Tenant t MUST Sign WITHIN (period of t)
ONCE ALL HAVE HENCE … WITHIN 5 OF THE DEADLINE`, Alice's period 10, Bob's 20, both timely —
Alice@3, Bob@4 → FULFILLED (deadline 25); Bob@3, Alice@4 → BREACHED "15"; a tie → 15 by roll order
(minimal SEM-3, both checkers; probed). The overlay implements (a) with a three-trace golden
(`per member`, `run-anchors.l4:288-310`, READ: both rolls and a tie, all 20 + 5 = 25) and routes the
empty cast through `Barrier3`/`Barrier4` (`nobody, bounded as a whole`, 35; `nobody, act deadline
only`, refusal 6). Both checkers: "the fix is uncommitted and the proposal text still does not state
the max rule". Under `LEST` the layer rule already holds — the failing member's act deadline when a
member expired, the `ONCE` line's when the group was late (`the tenancy, a member late`, 19;
`the tenancy, the group late`, 35) — and both proposals mis-attribute S2's 35 to "the `ONCE` line's,
R-T2" when S2 has no `ONCE`-line `WITHIN` (PA-7, F10, SEM-9). The same-stamp tie-break in `Barrier2`
(`t >= stamp -> step.tLast` keeps the first-rolled member's residual stream) is a separate live defect
that flips a `HENCE`'s verdict with cast order on today's machine and is owed its own issue, not a
ruling (maximal SEM-5; §3 below).

**Recommended: (a), ratified as a ruling.** What decided it: order-independence; R-Q7B's own gloss;
(c) would refuse the clause R-Q7B was motivated by. On the empty cast, the choice between "no
`dueLatest` → refuse" and "arming + act `WITHIN` in the `EVERY`'s environment" was decided by the act
`WITHIN` possibly mentioning the member (refusal 4's reasoning; overlay spec, READ).

**Amends.** §5.1.1.1 "`THE DEADLINE` under a barrier": the overlay's paragraph is adopted verbatim
with its header changed from a build decision to **RULED 2026-09-15 (B9)**, and §5.1.1's R-Q7B block
gains one sentence:

> Under a barrier, `THE DEADLINE` in the `HENCE` is the `ONCE` line's `WITHIN` when written and
> otherwise the latest of the members' act deadlines — the instant by which all performance fell
> due — never the completer's, which would move with signing order (B9). Under the `LEST` it is the
> deadline actually missed: the failing member's, or the `ONCE` line's when everyone acted but the
> last act was late. An empty cast is joined at its arming; with no `ONCE`-line `WITHIN` it has no
> `THE DEADLINE` and the run refuses, naming the empty cast.

**Confidence: high.** Measured three ways on the overlay binary; the only open point is that the
overlay is uncommitted.

---

## 3. Owed, not carded

Things the evidence produced that are not Meng's to rule but must not be lost:

- **`Barrier2`'s same-stamp tie-break picks the `HENCE`'s residual stream by cast order**, so
  `EVERY p IN (LIST Alice, Bob) … ONCE ALL HAVE HENCE PARTY Escrow MUST release WITHIN 0` with
  Alice@25, release@25, Bob@25 is FULFILLED, and `(LIST Bob, Alice)` on the identical trace is a
  residual (maximal SEM-5, probed twice, with distinct-stamp controls). A live defect on `unstable`
  today, independent of anchors; file it upstream (smucclaw/l4-ide) and fix the tie-break to trace
  order.
- **Commit the overlay.** Every repair B4, B8, B9 lean on is in the working tree of
  `~/src/legalese/l4wt/every-anchors` and on no commit; any proposal citing 5a851da5 alone is stale
  (SEM-9, PA-8, F11). The branch is unpushed.
- **`doc/`** (repo `CLAUDE.md` §6): `doc/reference/regulative/README.md` and `EVERY.md` carry the
  overlay's text; B2's `WHERE opening MEANS` idiom, B6's s 50(a) sentence for both edges, and B8's
  kept-`SHANT` rewrite are owed in the PR that lands each. `doc/reference/control-flow/REFUSE.md:119`
  is owed the `RAND` sequencing qualifier (B3).
- **Corpus**: `ny-environmental-7.3.l4:74` (`WITHIN 740775`) and `module-a2-cross-cutting-examples.l4:406-412`
  (a `LEST` duration read as an absolute day) are wrong today and want `BEFORE <date>` /
  `OF THE ARMING` once T1 lands (corpus §Spelling); not this bench's to fix.
- **Spec hygiene**: `Machine.hs:1612` (spec `:1253`, `:1596`) and `:1669-1671` are stale on
  `388f8605` — the join-stamp write is `:1640` and `:1547`, `continueWithFollowup` is `:1905-1911`
  (maximal SEM-9, R10); §5.1.2's `AFTER` cost counts six lines for `AFTER` only, `BEFORE` adds eight,
  all under `jl4/experiments/`, none goldened (R11).
- **The recorded-event anchor** R-Q7 requires (`WITHIN 5 days OF notice`) has no ruled spelling once
  the slot is an expression: an action constructor is neither `NUMBER` nor `DATE` (R4). It is B3's
  pattern look-up (`THE LAST notice`) and waits with B3; `README.md`'s `WITHIN` section was rewritten
  by track 6 with examples that check.

---

## Appendix A — Raised and refuted

Each was refuted by both of its checkers; none is resurrected above.

- **minimal SEM-5** — "the same obligation text changes meaning silently when factored into a named
  rule: `THE ARMING` = enclosing's arming inline, own arming when named (45 → 60)". True at
  5a851da5 and false on the overlay: the `Handoff` frame and `rebindLifecycle` rebind the hand-off's
  `Lifecycle` into the continuation value, so the finding's own probe `p1-refactor.l4` gives 45 for
  inline and factored alike on the 20:31 binary; a recursive named rule binds per instance (40, then
  60). Residual, recorded at B1: `THE JOIN`/`THE DEADLINE` are still refused by the checker in a
  top-level named rule (loud, `NoEnclosingObligation`), and the fix is uncommitted.
- **minimal PA-4** — "the design's channel cannot carry reg 31(3)'s counterfactual deadline". The
  premise that reg 31(3) must be a concurrent sibling of reg 30 is an encoding choice the statute
  contradicts: reg 30(1) reads "unless regulation 31 applies", and reg 31(3)'s "the day on which it
  would have ended under regulation 30" is the enclosing obligation's missed deadline, bound under
  `LEST` for a lapsed `MAY` (checker 1 ran it: residual `MAY cancel WITHIN 289` = 10 + 14 + 365, reg
  30's join never having fired). What survives is B3's note that neither proposal writes the sketch.
- **minimal F3** — "`Lifecycle Anno` + a token-less enum cannot keep `JOIN`/`DEADLINE`/`ARMING`
  highlighted as keywords". It can: a `Lifecycle{} -> withTokenType identIsKeyword …` arm in both
  `Expr` `ToSemTokens` instances (the shape the branch already uses for `Anchor` and `Type'`), with
  `ReadCell`'s `RecallMode` as the precedent for a token-less enum under a derived `ToConcreteNodes`;
  the token stream is byte-identical to the committed golden. The finding's supporting claim that
  `RAction` has a hand-written `ToSemTokens` instance is false (both are derived). Nit kept at B1:
  say the arm lands in both phases.
- **maximal P14** — "'S6 is inexpressible under (b)' is sharpened beyond the report". It is not:
  the legal-time report says in terms that freeze-at-arming "cannot express" Art 10(2)'s moving
  deadline, and both checkers built the "separate obligation" route three ways on today's binary —
  `RAND` does not shorten the running window, `ROR` is first-info-wins and nullifies a valid early
  withdrawal once a `HENCE` is attached, the recursive form still nullifies it. A frozen sibling
  builds the new window; nothing frozen cuts the running one. (That the maximal's S6 also mis-models
  Art 10 on the cap is SEM-8, confirmed, and does not touch this.)

---

## Appendix B — Not checked

- Nothing in this synthesis was built or run by the synthesiser; every probe result is the
  checkers', re-run by two of them on the every-anchors binary of 20:31 or the installed `l4` of
  13:57. The nouns-as-`Expr` form (B1) has never been parsed: F1, F4, F10 are reasoned from code.
- The overlay's Machine.hs was read through its `git diff` and the checkers' quotations, not
  line by line; line numbers in the working tree drift from the `5a851da5` and `388f8605` numbers
  the reports cite, and both are given where they differ.
- Primary sources: I read the spec (`e578654c`, `5a851da5`, and the overlay), track 6's `README.md`,
  `run-anchors.l4:44-58, :288-343, :496-501` and its golden head, and `TypeCheck/Types.hs`'s refusal
  constructors. AH94, AFH94, GRS 2011, Tonetta 2017, Davies 1991, Hvitved 2012, Governatori 2007,
  the Symboleo sources, the BPMN/DMN/Catala/OpenFisca texts, and the statutes and cases are cited as
  the reports and the checkers read them. Art 9(2)(b)(iii) was READ live only by the P12/P4
  checkers; reg 31(2)–(3) by the F6/P12 checkers via a Wayback copy (legislation.gov.uk returned an
  empty body to others).
- B2's bare-edge default (F2) and empty-window check cannot be measured until `AFTER` (track 7)
  exists; B4's pending state and B3's scheduler are unbuilt designs with stated gaps; B6's T1 shape
  is ruled and unbuilt.
- Whether "bounded freeze depth" (bare nouns reach one hop) is strictly weaker than full TPTL over
  rational stamps is a recollection in PA-3 checker 2, unverified against BCM10; the drafting
  argument for B1's `WHERE` capture does not depend on it.
- The `RAND` order dependence (B3) was probed with two-operand shapes only; `ROR`, nested
  `RAND` under a barrier, and the fork fold were reasoned from `runQuantifiedFold` and not run.
- The severity downgrades some checkers suggested (SEM-3 minimal → "state the rule; commit the fix";
  SEM-10 maximal → narrowed; P2 → re-targeted to the opening edge; R6 → conclusion partly wrong,
  argument passing suffices) are reflected in the cards' wording but the findings' own severity
  labels were not re-adjudicated here.

## Sources

`reports/{timed-csp,timed-automata,mtl-tptl,event-calculus-contracts,bpmn-dmn-catala,legal-time-computation,corpus}.md`
and `reports/corpus-hits.md`; `proposals/{minimal,maximal}.md`; the adversarial results as supplied
to the synthesiser (67 findings, four refuted); `spec-unstable.md` (= `e578654c`, §5 lines 1580–2010),
`spec-5a851da5.md` (§5.1.1.1 lines 1743–1906) and `git diff` of the spec in
`~/src/legalese/l4wt/every-anchors`; `Machine.388f8605.hs`; the every-anchors working tree at
2026-09-15 20:5x (16 modified files over `5a851da5`; branch `every/anchors`, no remote).
