# Specification: giving notice — a built-in action whose effect is derived, not observed

> **Status (2026-10-10): PROPOSED, not landed; nothing here is built and nothing is ruled.**
> Meng asked, through session `l4-pitch` on 2026-10-10, that sending a notice be a first-class action available by default to any party, plus user-defined notice types.
> `l4-pitch` wrote the requirements memo this spec condenses, from world knowledge and not a research pass; its case and statute citations are marked as recalled below and must be checked before anything relies on them.
> Session `ledger` wrote this file and added the parts that touch the ledger and the norm log; every claim about the tree is cited to `origin/unstable` @ `539cad5fd`.
> **Companion documents:** `specs/done/STATE-AS-LEDGER-SPEC.md` (the ledger); `specs/todo/IN-RELIANCE-ON-SPEC.md` (§4.2, a speech-act `ATTEST`); `specs/todo/presumption-assertion/CONTRACT.md` (defaults and unknowns); `specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md`; and `specs/todo/NORM-LOG-SPEC.md`, which is on draft PR legalese/l4-ide#499 and not on `unstable` (its N3, N5, N10 and N12 recur below).

---

## 0. Thesis

The law separates the moments in a notice's life — written, dispatched, delivered, read — and lets each rule choose which of them makes the notice **effective**.
Effectiveness is therefore a conclusion a rule draws from observations, not an observation itself.
L4 today has one moment: `NOTIFY` v1 makes dispatch and delivery a single write, so it cannot say what the postal rule exists to say — that an acceptance posted and lost is still effective at posting.

## 1. What exists (measured)

- **`NOTIFY` v1 is a recipient-qualified `RECORD`.** `RECORD q's <cell> IS <v>` is written by the acting party into q's own ledger, routed by `RouteNotify` (`jl4-core/src/L4/Evaluate/Ledger.hs:262`, applied at `jl4-core/src/L4/EvaluateLazy/Machine.hs:1379`, chosen in `runRecord` at `:4325-4331`), stamped with `source = NOTIFY`; demo `jl4/experiments/notify-v1.l4`.
  The sender writes the recipient's inbox in the same step it acts, so dispatch is delivery: no lost letter, no bounce, no refusal, no interval.
- **Its 2026-06-22 design review left constraints this spec inherits** (PR #31):
  - `NOTIFY` must not become a reserved keyword, because corpus files already use it as an ordinary name (`jl4/experiments/misleadingPriceLists.l4`, `jl4/experiments/jerseyCharities2-annual-returns.l4`);
  - the inbox is the recipient's own ledger, so a received notice is indistinguishable from a self-written entry (v1 assumed cooperative parties);
  - party identity is keyed on the rendered party value, so two spellings of one party are two inboxes, silently.
- **The ledger's two time stamps are the wrong axis for notice timing.** `txTime` is one wall-clock value per run and `vtFrom` is a calendar `Day` (`Ledger.hs:69-76`); neither is the contract clock.
  The right pair is the norm log's `effective` and `observed` contract instants (NORM-LOG N3, accepted 2026-09-27), and black-ink entries do not carry them until NORM-LOG N12, which is open.
  **So notices are N12's first consumer**: the postal rule is "effective at the dispatch instant, observed by the addressee later, or never".
- `ATTEST` is a pure synonym of `COMMIT` today (`IN-RELIANCE-ON-SPEC.md` §4.2 proposes giving it a speech-act meaning).

## 2. The moments, and rules that pick among them

| moment     | what it is                                      | who can assert it              |
| ---------- | ----------------------------------------------- | ------------------------------ |
| written    | the notice exists                               | the sender                     |
| dispatched | it left the sender's control                    | the sender, or a carrier       |
| delivered  | it reached the addressee's sphere               | the addressee, or a carrier    |
| read       | the addressee knew                              | the addressee                  |
| effective  | the legal consequence — derived, never asserted | a rule, from the moments above |

Rules that choose differently (all **recalled, not checked**, except where attributed):

| rule                                                                                                                                                                  | effective at                          | confidence                                                 |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| postal rule for a posted acceptance: _Adams v Lindsell_ (1818), _Household Fire v Grant_ (1879)                                                                       | dispatch, even if lost                | recalled                                                   |
| its limits: not for revocation (_Byrne v Van Tienhoven_, 1880); post must be reasonable (_Henthorn v Fraser_, 1892); excludable (_Holwell Securities v Hughes_, 1974) | receipt                               | recalled                                                   |
| instantaneous channels: _Entores v Miles Far East_ (1955), _Brinkibon v Stahag Stahl_ (1983)                                                                          | receipt                               | recalled                                                   |
| deemed receipt by statute, e.g. UK Interpretation Act 1978 s 7                                                                                                        | a computed day, rebuttable            | recalled                                                   |
| CISG Art 27 (Part III notices) beside Arts 18(2), 24 (acceptance)                                                                                                     | dispatch for one, reach for the other | recalled                                                   |
| UNCITRAL Model Law on Electronic Commerce Art 15; Singapore Electronic Transactions Act                                                                               | dispatch and receipt defined apart    | recalled                                                   |
| Vietnam Law 08/2022/QH15 Art 19(3), Art 46(1): no late-notice exclusion for force majeure; reduction only in proportion to loss                                       | a notice clock with an excuse         | read in the gazette text by session `l4-pitch`, 2026-10-10 |

## 3. Requirements, condensed

The two that matter most come first.

- **R2 — observations and effect are different things.** Dispatched, Delivered, Read, Bounced, Returned and Refused are ledger entries, each written by whoever can assert it (§2). Effective is computed from them by the notice's regime. A lost letter has a Dispatched entry, no Delivered entry, and under the postal rule still an effect.
- **R4 — say which moment a clock runs from.** "Within 5 days of giving notice" and "within 5 days of receiving notice" are different promises, so rule language needs both "notice was given" and "notice took effect". Where a text says only "notice", the encoder surfaces the choice as a fork rather than picking. `l4-pitch` reports that most claim clocks in the Vietnamese insurance corpus leave this unstated.
- **R1 — a built-in `give notice` action**, in scope for every party without a declaration; payload sender, addressees, type, content, channel, address. User-defined notice types refine it with required content and validators.
- **R3 — the regime is data, chosen by precedence, and defeasible**: the instrument's notice clause, then statute for the governing law and channel, then the common-law default for the channel, then a library default; each choice recorded with its provenance. Presets: DISPATCH, RECEIPT, ACTUAL KNOWLEDGE, DEEMED(n business days, rebuttable or conclusive).
- **R5 — "received?" is unknown until there is evidence**, and a deeming rule is a rebuttable default over that unknown (a `TYPICALLY`, overturned by a Returned entry). The epistemic gap is visible in the per-party ledgers: the sender's holds Dispatched, the addressee's holds nothing yet.
- **R6 — races between channels** (a telephoned revocation overtaking a posted acceptance) need an order on entries and a rule for one tick; inside a compound that is NORM-LOG N10.
- **R7 — time arithmetic as a library**: business days by place, holidays, cut-off hours, time zones, clear days, inclusive and exclusive counting.
- **R8 — validity is not effectiveness**: wrong form, not signed, wrong address, wrong officer; types carry validators.
- **R9 — who gives and receives**: agents, registered offices, joint addressees (one or all?) — a notice to a class is an `EVERY` fan-out or barrier.
- **R10 — evidence and burden**: certificate of posting, registered receipt, tracking, server log, read receipt; candidate homes are a speech-act `ATTEST` (`IN-RELIANCE-ON-SPEC.md` §4.2) and the burden-of-proof module in package `jl4-proleg`, on branch `claude/wave3a-03-proleg` and not on `unstable`.
- **R11–R13** — an acknowledgment is a notice that needs no acknowledgment; withdrawal that arrives no later than the notice (CISG Art 15(2), recalled); change of address redirects later notices; notices to regulators and to the world (publication).

## 4. Recommendations on `l4-pitch`'s open questions — assumed, not ruled

- **`give notice` sits above `NOTIFY`.** Giving notice writes Dispatched to the sender's own ledger; Delivered and Read are separate entries written by the addressee or a carrier, as trace events. v1's `RECORD q's` stays as what it is — a sender writing straight into the recipient's ledger — and is the receipt-on-dispatch special case, not the general mechanism. `give notice` must be library sugar, not a keyword (§1).
- **Regimes are library data** with a module default and a per-clause override, and every selection is recorded with its provenance so a reviewer sees which rule was assumed.
- **Effective is computed on read, not stored.** Storing observations and deriving effect keeps deeming defeasible (a later Returned entry rebuts it) and keeps machine conclusions apart from party assertions, as NORM-LOG N5 does for fates. Reads are as of the reader's contract instant, which needs N12.
- **Discrete time:** dispatch, delivery and reading may share one tick; ordering on one tick is NORM-LOG N10's tie case and inherits its answer.
- **An unspecified regime defaults and flags a fork** rather than refusing, because instruments are usually silent (R4); the flag is the same "assumed, not ruled" shape as the presumption work (`specs/todo/presumption-assertion/CONTRACT.md`).

## 5. Golden scenarios to write first

1. Posted acceptance, letter lost.
2. Posted acceptance; a revocation by telephone arrives first.
3. Notice sent to the wrong address.
4. Addressee refuses delivery.
5. Email bounces.
6. Notice sent at 17:30 on the Friday before a public holiday.
7. A rebuttable deeming rule, rebutted by returned mail.
8. A conclusive deeming rule, same facts.
9. Joint addressees; only one receives.
10. A notice in defective form that is actually read.
11. A withdrawal that arrives with the notice.
12. A claim notice "within 5 days", the same events under a dispatch regime and under a receipt regime.

## 6. Dependencies

- NORM-LOG N12 (contract instants on black ink, as-of `RECALL`): needed before any notice clock can be read correctly.
- NORM-LOG N10 (operand order) and its run-time check: channel races inside a compound.
- The presumption and assertion bench (cards C1–C6, open): deeming as a rebuttable default.
- `IN-RELIANCE-ON-SPEC.md` §4.2: whether `ATTEST` becomes the speech act that carries evidence of dispatch or receipt.
