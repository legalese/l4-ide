# The corpus track — mirror, superset, wizard, scenarios

_Scoped 2026-07-27, **revised 2026-07-27 after adversarial review** (three lenses:
dependency claims, legal accuracy, argument strength). Track C of [SPEC.md](./SPEC.md).
Companion to [PROCESS-TRACK.md](./PROCESS-TRACK.md) (Track P) and
[GUARDED-ROWS.md](./GUARDED-ROWS.md) (Track D0) — the corpus is the thing both of those
export. The corpus itself lives at
[`jl4/examples/legal/regcf/`](../../../jl4/examples/legal/regcf/); its own README carries the
threshold table, the nine page divergences, and the honest list of what could not be
expressed, and is not restated here._

> **The review changed the substance, not just the wording.** Two blocking findings and five
> majors; every one is dispositioned in **[§9](#9-review-findings-and-their-disposition)**,
> which is the index to read first if you have seen the previous draft. The two that matter
> most: the "smallest increment" as previously written **shipped a legally wrong
> `investment limit`** (§6.1), and the temporal model **omitted the 2017-04-12 inflation
> adjustment** entirely (§2.4). Both are fixed here, re-verified against the Federal Register
> full text rather than against any secondary source.

---

## 0. Where the track actually stands

SPEC.md §4 gives Track C four rows and no build spec. That table understates C0 and
misdescribes C1. **C0 is built, green and CI-covered, and it already delivers three of
C1's four bullets** — because C0 overshot on _shape_ (a formula, three deontics, real
deadlines) while leaving C1's genuinely hard bullet, the rule-version axis, entirely
untouched.

The consequence is good news and awkward news at once. The good news: **M5 is not blocked
on language work.** The rule-version axis shipped (PR #89, merged `6b2c7f55`) and
`EVAL UNDER RULES EFFECTIVE AT` is a first-class `∀a. DATE → a → a` (since 2026-07-29; previously a `NUMBER` serial) over a _runtime_
serial, so a corpus author can pin a rule date today. The awkward news: C0 left a set of
gaps SPEC.md's C1 line does not name at all — no `@export`, no composed contract, three
dead `Action`s, two dutyless `Actor`s — and two of those are hard preconditions for C2 and
for Track P.

**One correction to how that good news was previously stated.** M5's _arithmetic_ is not
blocked on language work. M5's _demonstration_ is: a golden file containing two
hand-written `EQUALS` is observationally indistinguishable from two numbers typed into a
table, which is exactly what the page can already do. The thing a page cannot do is answer
**an arbitrary user's arbitrary inputs** under a chosen rule date, and that surface is C2.
So **M5 depends on C2**, and SPEC.md §5's M5 row has been corrected from `C1, C3, S2, S3`
to `C1, C2, C3, S2, S3`. See §6.3 and finding **F5** in §9.

| ID     | SPEC.md's line            | Reality on `unstable`, 2026-07-29                                                                                                                                                                                                                                                                                                                                                     |
| ------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **C0** | Mirror their eight groups | **Built.** 992 lines, 55 `#ASSERT` + 7 `#TRACE` + 1 `#EVAL`, all green, four goldens, in CI. Five of eight groups complete                                                                                                                                                                                                                                                            |
| **C1** | Four superset moves       | **Complete (2026-07-29).** Formula, deadlines and the resale deontic landed inside C0; the rule-version axis landed on `mengwong/regcf-rule-version` — seven dated constants, both dated shapes, R2 floor refusal, banded COVID refusal, pinned by the rule-version assertion group                                                                                                   |
| **C2** | Citizen wizard            | **C2a + C2b built; C2c prepared, not performed** (re-measured 2026-08-02). `regcf-wizard.l4` is 779 lines with **6** `@export` and 57 `@desc` — the rule-date question exists as `investment limit under the rules effective on`, so §3.3's last row is discharged. `TYPICALLY` is still **0**, corpus-wide. The frontend is `ts-apps/regcf-wizard`; see §3.6. **M5 depends on this** |
| **C3** | Scenario tests            | **Not started.** 55 boundary assertions exist; none is a party's scenario, and nothing gates a failure                                                                                                                                                                                                                                                                                |

Provenance: `jl4/examples/legal/regcf/regcf.l4` (992 lines; cut in `4c6a385d`,
`6ddbc68c`, `10e74b95`, then grown by PR #162's projection triage) and
`regcf-wizard.l4` (749 lines, PR #162 `65681a0a`). CI coverage via the `legal/**/*.l4` glob at
`jl4/tests/Main.hs:73`, joined into the "ok files" suite at `Main.hs:95`; four goldens
attach per file at `Main.hs:121-129`.

---

## 1. C0 — what the mirror covers, and the four things it does not

### 1.1 The eight groups

Their enumeration is not in SPEC.md §1.2 (which says only "eight numbered prose items");
it lives at `jl4/examples/legal/regcf/README.md:37-46` and is restated in the module header
at `regcf.l4:13-20`. Line refs below are `regcf.l4`.

| #     | Their heading            | Encoded at                                                                              | Verdict                                                                                                |
| ----- | ------------------------ | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **1** | Issuer eligibility       | `IssuerProfile` **155-162**; six limbs **164-206**; disjoined **208-218**; **220-224**  | **Complete — superset.** Carries (b)(5), which the page omits (README §3.6)                            |
| **2** | Offering limit           | `Offering` **229-233**; aggregate **240-245**; `DECIDE` **251-256**                     | **Complete — deliberately diverges.** Refuses the page's Rule 504 aggregation claim (README §3.5)      |
| **3** | Investor limits          | `InvestorProfile` **260-266**; selector **299-304**; **`investment limit` 306-319**     | **Complete, already a formula.** "greater of", not the page's "lesser of" (README §3.1)                |
| **4** | Disclosure               | tiers **354-369**; assurance **375-390**; `FormCFiling` **395-399**; **401-409**        | **Partial.** Tiers complete; Rule 201 itemisation collapses to one boolean at **398**; no duty to file |
| **5** | Intermediary obligations | `IntermediaryArrangement` **413-420**; **422-447**; `DECIDE` **449-455**                | **Partial.** Constitutively complete; **zero regulative content** despite the heading                  |
| **6** | Advertising              | `AdvertisingNotice` **459-465**; **471-486**; **DEONTIC 491-497**                       | **Complete, regulative.** Carries Rule 204(b)(3), which the page drops (README §3.8). See D1           |
| **7** | Ongoing reporting        | `ReportingStatus` **501-508**; five limbs **510-556**; **DEONTIC 563-573**              | **Partial.** Superset on termination (5 limbs vs their 3); Form C-U absent. See D2                     |
| **8** | Resale                   | `Transfer` **577-583**; window **591-596**; exceptions **598-610**; **DEONTIC 619-625** | **Complete, regulative**                                                                               |
| —     | _(no page slot)_         | `the transaction qualifies…` **635-649**                                                | Encoded; boolean only, composes none of the deontics                                                   |

### 1.2 The obligation tail exists in shape but not as a process

Three `GIVETH A DEONTIC Actor Action` functions, and they are the whole regulative layer:

| Rule                           | Line        | Deontic                                                       | `WITHIN`                                     |
| ------------------------------ | ----------- | ------------------------------------------------------------- | -------------------------------------------- |
| `advertising restriction`      | **491-497** | `PARTY Issuer SHANT advertise the terms of the offering`      | `days in the resale restricted period` (365) |
| `ongoing reporting obligation` | **563-573** | `MUST file a Form C-TR…` / `MUST file a Form C-AR…` + `HENCE` | 5 business days; 120 days                    |
| `resale restriction`           | **619-625** | `PARTY Purchaser SHANT transfer the securities`               | 365 days                                     |

So SPEC.md's C1 phrase _"the obligation tail with real deadlines"_ is **already
substantially delivered inside C0**: 120 days and 5 business days are named, `@ref`-cited
constants at **129-135**, and all seven `#TRACE`s residuate correctly
(`tests/regcf.golden:84-132, 143-158`). But the tail is thin in four specific ways:

1. **`LEST` count: 0.** No reparation, no secondary obligation. A missed C-AR
   `DEONTIC BREACHED`es and nothing follows. `HENCE` appears once (**573**), only to renew
   the same duty.
2. **Three disjoint fragments, not one process.** The top-level `DECIDE` at **643-649** is
   pure boolean and references none of the three deontics. **This is the finding that
   matters most for Track P0**: PROCESS-TRACK.md §4.1 says the exporter "cannot dodge P0"
   because the Reg CF tail forces the parallel gateway — but what `stateGraphToBpmn` will
   actually meet today is three unconnected mini-graphs plus an unrelated boolean blob.
   There is nothing to walk end to end. Lexipedia's hand-drawn BPMN, wrong as its ordering
   is, is at least _one_ connected flow.
3. **Three of seven declared `Action`s are dead** — each appears exactly once, in the
   `DECLARE` at **64-71**, and nowhere else: `file a Form C offering statement` (**65**),
   `file a Form C-U progress update` (**66**), `transmit funds to the issuer` (**71**).
4. **Two of four declared `Actor`s never bear a duty**: `Intermediary` (**60**) and
   `Investor` (**61**). Only `Issuer` and `Purchaser` appear after `PARTY`.

Also absent, against SPEC.md §2's "**have**" claims: `RECORD` / `COMMIT` / `ATTEST` /
`RECALL` — 0 occurrences. §2's "audit trail / evidence collection → have" row is a
capability claim about L4, not a statement about this corpus.

### 1.3 House style: GIVEN/record throughout — no `ASSUME`, and that matters twice

`grep -c ASSUME regcf.l4` → **0**. Every group declares a record and threads it as one
`GIVEN` parameter, per house style. The module fully evaluates: 55 concrete
`assertion satisfied` results, no `ValAssumed`, no `Stuck`.

Two consequences worth surfacing outside this track:

- **This is the shape the DMN exporter handles worst.** The `dmn-exporter-assume-shaped`
  finding is that the exporter models a module as global scalars; under GIVEN/record style
  it emits duplicate-named `inputData`, unevaluable `f(x)` invocations, no BKM, and records
  erased to `Any`. `regcf.l4` is the canonical GIVEN/record module, so **Track D1 cannot be
  demoed on the flagship corpus without exporter work first.** Not this track's work to fix,
  but this track's corpus that exposes it.
- **The top-level `DECIDE` at 636-643 takes six separate `GIVEN` parameters**, not one
  composite record — the one place the house style is not followed, and the one the wizard
  most wants to consume. (The ladder handles it: the "≤ 1 Given" restriction in the comment
  at `jl4-lsp/src/LSP/L4/Viz/Ladder.hs:279` is stale — `paramNamesFromGivens` at `:328-336`
  collects them all. The only hard throw is `InvalidDecideMustHaveBoolRetType` at `:310-311`.)

### 1.4 Three defects found while reading C0

**D1 — the advertising prohibition borrows the wrong deadline constant.** `regcf.l4:497`
writes `SHANT advertise the terms of the offering WITHIN days in the resale restricted period`
— the Rule 501(a) 365-day _resale_ window, reused as the Rule 204(a)(1) _advertising_
window. Rule 204 has no such period; the prohibition runs for the life of the offering. The
`§§ Periods` block (**123-146**) binds no advertising constant, so this reads as a
placeholder rather than a modelling choice. It is invisible in the goldens because `SHANT`
reports its deadline as the event time (`tests/regcf.golden:98-99` shows "deadline, which
was at 10" for an event at 10), so nothing tests it — precisely the silent-drift failure
mode README §3.3 levels at the wiki.

**D2 — Form C-U is bound, cited, and orphaned.** `business days to file a progress update`
= 5 exists at **137-139** with an `@ref` to 17 CFR 227.203(a)(3)(i), and the Action exists
at **66**, but nothing references either. README §2 lists the 5-business-day C-U deadline
in its threshold table as though it were encoded.

**D3 — two factual misstatements in the corpus's own prose, both about the 2022 release.**
Found by review; both are in text this track quotes as authority, so both must be fixed
before any of it is republished as an accuracy exhibit.

1. **"The SAME amendatory instruction"** (`regcf.l4:81-83`, and README §3.3 in the same
   words). It was the same _release_ and the same _effective day_, but **two separate
   amendatory instructions**: instruction **2.a** amends § 227.100(a)(2)(i), instruction
   **3.a** amends § 227.201(t)(1) (87 FR 57394, 57398 — quoted in full at §2.4 below).
   README §3.3's own block quote contains the string `3. Amend Sec. 227.201 by:`, so the
   quotation visibly refutes the sentence introducing it.
2. **"In `regcf.l4` the figure is bound once … and read by both consumers"** (README §3.3).
   False. `$124,000` is bound **three** times, because it is **three distinct legal
   parameters** that presently share a value: `income or net worth cut point` (**86**,
   Rule 100(a)(2)(i)-(ii), read at **302-304**), `maximum amount sold to any one investor in
a 12-month period` (**96**, Rule 100(a)(2)(ii), read at **314-316**), and `tier 1 ceiling`
   (**101**, Rule 201(t)(1), read at **358**). Three bindings is the _correct_ modelling —
   see §5.3, where the claim is restated in a form that survives.

D3 is a documentation fix, not a logic fix; it is **C0-f** in §1.5. It is deliberately
_not_ made in this commit, whose scope is the spec.

### 1.5 C0's residual, sized

| ID       | Work                                                                                                                                                                | ≈ new lines | Unblocks                                     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | -------------------------------------------- |
| **C0-a** | Fix D1: bind an advertising period (or drop the `WITHIN`) and add a `#TRACE` that would have caught it                                                              | ~8          | correctness                                  |
| **C0-b** | Fix D2: `PARTY Issuer MUST file a Form C-U progress update WITHIN 5` under Rule 203(a)(3)(i)                                                                        | ~14         | kills 1 dead Action                          |
| **C0-c** | Rule 203(a)(1) as a duty, not a boolean: `PARTY Issuer MUST file a Form C offering statement`                                                                       | ~14         | kills 1 dead Action, completes group 4       |
| **C0-d** | Intermediary duties as duties: Rules 302(b)(1), 303(a)(2), 303(b)(1) under `PARTY Intermediary MUST …`                                                              | ~30         | completes group 5, makes `Intermediary` live |
| **C0-e** | The composed contract — one `GIVETH A DEONTIC` conjoining all five with `RAND`                                                                                      | ~20         | **Track P0/P1**                              |
| **C0-f** | Fix D3: correct `regcf.l4:81-83` and README §3.3 — "same release, **separate** instructions 2.a and 3.a"; replace "bound once" with §5.3's three-parameters framing | ~10 (prose) | **the accuracy claim itself**                |

C0-f is small and should go first: it is prose in the two documents this track cites as its
own evidence of care, and an accuracy exhibit that misstates an amendatory instruction is
self-defeating regardless of how good the L4 is.

C0-e is the one with leverage outside this track. Its shape:

```l4
GIVEN `the deal` IS A RegCFTransaction
GIVETH A DEONTIC Actor Action
`Reg CF obligations` `the deal` MEANS
        `Form C filing obligation`      `the deal`
   RAND `progress update obligation`    `the deal`
   RAND `advertising restriction`       `the deal`'s notice
   RAND `ongoing reporting obligation` (`the deal`'s status) 3
   RAND `resale restriction`            `the deal`'s transfer
```

`RAND` is the regulative conjunction (`jl4-core/src/L4/Lexer.hs:260`,
`jl4-core/src/L4/Parser.hs:1554`), and it is exactly the `RAnd` constructor whose
indistinguishability from `ROr` is P0's bug (`StateGraph.hs:240-248`, PROCESS-TRACK.md §4).
So C0-e is simultaneously the corpus's missing spine _and_ P0's acceptance fixture: five
concurrent obligations, three bearers, different temporal extents — the thing
PROCESS-TRACK.md §4.1 says Lexipedia drew as a straight line and is not one.

**Scope check.** C0-a through C0-f stay inside SPEC.md §7: none adds a rule outside the
eight groups. C0-c/d/e re-encode material the page already asserts, in the register the
page cannot use.

---

## 2. C1 — the four superset moves

For each: what it demonstrates, the L4 shape, and whether the language support exists today.

### 2.0 The standard the four moves are measured against — **corrected**

The previous draft measured each move against "what their format **structurally cannot
hold**". Review demolished that standard on three of the four moves, using this document's
own companions as the refutation, and the demolition is accepted:

| Move                | The refutation of "structurally cannot hold"                                                                                                                                                                                        |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 — the formula     | **DMN is in their declared format** (SPEC.md §1.3 finding 1: "DMN is advertised and never used … ships primers for both"). A DMN decision table holds this formula fine. The failure is behavioural, not structural                 |
| 2 — the deadlines   | A deadline-carrying `LEST` **maps cleanly to a BPMN timer boundary interrupting event** — PROCESS-TRACK.md §3 calls it "the one line in that table where the notations genuinely agree". A diligent Camunda author draws it by hand |
| 3 — resale          | The page holds it in **one prose sentence**, which `regcf.l4:595` carries verbatim as inert prose. Nothing about it is unrepresentable                                                                                              |
| 4 — the regime axis | §2.4 below **typesets the four-regime table in Markdown**. If a page could not hold it, this document could not have printed it                                                                                                     |

**The standard that survives is evaluability, not representability.** Anything can be
typeset. Restated, and used for the rest of §2:

1. **It can be run.** A number in prose cannot be applied to _your_ income. A formula can.
2. **It can be wrong in a way someone notices.** Their "lesser of" (README §3.1) survived
   because nothing evaluates a sentence. A typechecked, asserted formula is falsifiable —
   and this very document was caught by that discipline twice (D3, §6.1).
3. **It answers arbitrary inputs, not enumerated ones.** A three-row table answers three
   rows. `investment limit` under a pinned rule date answers the whole product of (income ×
   net worth × prior sales × rule date).
4. **It is one artifact, so it cannot desynchronise from itself.** Their standing chore
   (SPEC.md §1.3 finding 3, "Notes for editors") is reconciliation between two
   representations. There is one here.

Points 1-3 are only _visible_ through an interactive surface. That is why **M5 now depends
on C2** (§0, §6.3): without the wizard, the increment in §6.1 is a golden file, and a golden
file with two expected values is observationally a two-row table.

### 2.1 The investor limit as a formula — **spent inside C0**

**Already done**, `regcf.l4:306-319`:

```l4
`investment limit` investor MEANS
    IF   `either annual income or net worth is less than the cut point` investor
    THEN IF   `minimum permitted investment` AT LEAST `five percent of the greater`
         THEN `minimum permitted investment`
         ELSE `five percent of the greater`
    ELSE IF   `ten percent of the greater` AT MOST `maximum amount sold to any one investor in a 12-month period`
         THEN `ten percent of the greater`
         ELSE `maximum amount sold to any one investor in a 12-month period`
    WHERE
        `five percent of the greater` MEANS 0.05 TIMES investor's `greater of annual income or net worth`
        `ten percent of the greater`  MEANS 0.10 TIMES investor's `greater of annual income or net worth`
```

> **Spelling updated 2026-07-31 to match the corpus.** `greater of annual income or net worth` is
> now a **computed field** on `InvestorProfile` rather than a standalone unary decide, so the read
> is a projection. See `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §4.4. The logic is unchanged; only the
> spelling of the read is.

**What it demonstrates — under §2.0's corrected standard.** Their page states the limit as
two prose sentences with a number in each. Prose cannot be evaluated, so it cannot be
_wrong in a way anyone notices_ — and theirs is wrong in the **shape** rather than the
number ("lesser of" for "greater of", README §3.1), understating one worked investor's
lawful capacity by 3.3×. A formula is checkable; a sentence is not. That is criterion 2, and
C0 already made it.

**Conceded: DMN could hold this.** DMN is in Lexipedia's own declared format and its primer
is on their site; a two-row decision table with an input expression per limb would express
the same function, and would be executable in a DMN engine. The honest residue is criterion
4 plus provenance: a DMN table has no place to bind `$124,000` to _its citation_
(17 CFR 227.100(a)(2)(i)-(ii)) and _its effective date_, no typechecker relating it to the
other seven groups, and no way to be told that its `tier 1 ceiling` and its cut point are
different parameters that happen to agree today. The claim is therefore **not** "DMN cannot
do this" — it is "they ship zero DMN, and even the DMN they would ship carries no
authority trail". Track D1 exports DMN precisely so this comparison can be made on their
terms rather than asserted.

**Consequences for Tracks D/L, consistent with GUARDED-ROWS.md §6.** `investment limit` is
number-returning, so `boolReturning` fails and it stays one opaque leaf under D0 — it is
precisely the D2 / §23 structured-table-leaf case. One wrinkle GUARDED-ROWS.md does not
anticipate: the two rate terms are `WHERE`-bound _inside_ the guarded chain (**317-319**),
so both `rowsToLadder` and `rowsToDmn` will meet a `Where`-wrapped body, not a bare
expression. And GUARDED-ROWS.md §5 tier 2 cites "an income-or-net-worth threshold split as
`< k` / `>= k`" as the flagship shape — but in the corpus as written that split lives inside
the **number**-returning `IF` at **310**, not in a boolean `BRANCH`. Tier 2 will not fire on
it until D2 lands. The _selector_ at **299-304** is boolean and already ladders fine.

### 2.2 The obligation tail with real deadlines — **mostly spent; the residue is C0-a…e**

Delivered at **491-497**, **563-573**, **619-625** with 365 / 120 / 5 as named `@ref`-cited
constants. What is left is §1.5, which is C0 residual rather than C1 novelty — recorded here
so the C1 line in SPEC.md §4 is not read as promising work that is already done.

**What it demonstrates — with the overclaim withdrawn.** The previous draft argued that
BPMN "cannot say that skipping this one is a breach" (PROCESS-TRACK.md §5 F1) and in the
next paragraph proposed a `LEST` whose only new content is a construct PROCESS-TRACK.md §3
says **does** map to BPMN. Both cannot be true. What is true:

- **A `LEST` arm maps to a timer boundary interrupting event.** Conceded outright;
  PROCESS-TRACK.md:65 is explicit ("a deadline-carrying `LEST` is exactly a timer boundary
  event"). A Camunda author draws it by hand.
- **What survives is criterion 1, not representability.** BPMN's boundary event is a
  _picture_ of the deadline. It does not consume an event stream and return a verdict. The
  `#TRACE` at `regcf.l4:912-913` files a Form C-TR at day 30 against a 5-day deadline and the
  engine answers `DEONTIC BREACHED … deadline, which was at 5`. The diagram is the input to
  that computation in a workflow engine; here it is an _output_ of the same source that
  produced the verdict, which is criterion 4.
- **What survives on the modality.** BPMN has no vocabulary distinguishing a duty from a
  permission from a prohibition. `SHANT` at **491** and `MUST` at **563** draw as the same
  box. That is a genuine notational gap, and it is the F1 point stated correctly.

One genuine C1 addition worth taking anyway: **one `LEST`.** Rule 100(b)(5) is a reparation
structure in disguise — an issuer that misses its annual reports is disqualified from the
_next_ offering (README §5.6 records that the temporal link between the two halves is
carried as a comment because it needs the rule-version axis to state properly). A `LEST`
arm on the C-AR duty pointing at the (b)(5) disqualifier would (a) give the state graph a
`LestTransition`, which is the one construct P1's exporter can emit at full fidelity — so it
is the **fidelity-report control case**, the row where BPMN loses nothing — and (b) close the
comment-only link README §5.6 flags. It is worth taking for those two reasons, not as
evidence of a gap.

### 2.3 Resale as a 12-month deontic constraint — **spent inside C0**

**Already done**, `regcf.l4:619-625`, as 365 days, with both endpoint and leap-year
infidelities flagged inline at **585-590** and in README §5.2.

**What it demonstrates — narrowed.** The previous draft's whole argument here attacked the
hand-drawn BPMN lane ("a lane that does nothing for six frames"). Review's objection stands:
the page does not hold the resale restriction in the diagram, it holds it in **one prose
sentence**, which `regcf.l4:595` carries verbatim as inert prose. Attacking their diagram
for a fact their prose states is attacking the wrong artifact.

Narrowed to what survives: the restriction binds a **different party** (`Purchaser`) for a
period that starts when the offering ends, and the question a holder actually asks is _"may
I sell on this date?"_ — an evaluation over a transfer date and an issuance date, which is
criterion 1 and which the sentence cannot answer. In L4 it is a separate deontic with its own
bearer and its own clock (`regcf.l4:619-625`), it composes into the same contract by `RAND`
(C0-e) without being sequenced after anything, and its `#TRACE` returns FULFILLED or
BREACHED for a concrete transfer. The BPMN criticism remains true of _their diagram_ and is
recorded in PROCESS-TRACK.md, but it is not this move's argument.

### 2.4 Thresholds on the rule-version axis — **the whole remaining C1**

> **Status (2026-07-29): BUILT**, on branch `mengwong/regcf-rule-version`, exactly to this
> section's prescription — §6.2 steps 1, 1b, 2 and 2b in one change, because trap 5 makes
> them one unit. All seven moved constants carry four-regime dated arms; the lesser→greater
> shape and the accredited carve-out are dated; the R2 floor is a deliberate `ASSUME`
> bottom (an arm that reaches it stops with "…is an assumed term", naming the refusal —
> not the deprecated module-parameter ASSUME style, no input routes through it); the
> 201(z)/(bb) COVID window is a **banded refusal** in `financial statements required`
> (decided 2026-07-29 — see §2.4.1). Every claim below this note describes the tree
> **before** that change and is kept as the build spec it was; the paragraph-opening grep
> now counts the dated arms rather than 0.

`grep -c "RULES EFFECTIVE\|EVAL UNDER" regcf.l4` → **0**. The `§§ Thresholds` block
(**73-121**) binds **nine** constants, **eight** of them dollar figures, all flat: **79**
`MEANS 5000000`, **86** `MEANS 124000`, **91** `MEANS 2500`, **96** `MEANS 124000`, **101**
`MEANS 124000`, **106** `MEANS 618000`, **111** `MEANS 1235000`, **121** `MEANS 10000000`;
plus the headcount at **116** `MEANS 300`. **Seven of the nine have moved** and so need dated
bodies (**79, 86, 91, 96, 101, 106, 111**); the two at **116** and **121** have never been
amended — adopted at 80 FR 71388 and untouched by both inflation releases (confirmed against
instructions 5-6 of 82 FR 17545 and 2-3 of 87 FR 57398, neither of which touches § 227.202)
— so they stay single-arm. README §5.9 states the gap explicitly. _(The previous draft said
"all eleven dollar figures", echoing README §2; neither count is right. Counted here from
the source.)_

**Language support: BUILT.** Merged via `ac161031` → `6b2c7f55` (PR #89).

| Thing                                                  | Location                                                                                   |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `RULES EFFECTIVE DATE` — nullary `DATE` builtin        | `jl4-core/src/L4/TypeCheck/Environment.hs:142`; evaluator `Machine.hs:3742-3774`           |
| `EVAL UNDER RULES EFFECTIVE AT` — `∀a. NUMBER → a → a` | `Environment.hs:78`; type `:321-324`                                                       |
| 8-axis `TemporalContext`, pure `applyEvalClauses`      | `jl4-core/src/L4/TemporalContext.hs:33-56, 85-105`                                         |
| T6 read-fingerprint cache (`WHNFWhen`)                 | `TemporalContext.hs:107-196`; `Machine.hs:605-646, 2982-3046`                              |
| Working golden + tutorial                              | `jl4/examples/ok/temporal-rule-version-spike.l4`; `doc/tutorials/multi-temporal-modeling/` |

The fallback chain (`Machine.hs:3747-3774`, design §6 Q1 option (b)) is worth naming because
it is a jurisprudential win rather than a default: pinned rule time, else **valid time** —
law-time tracks fact-time, i.e. the presumption against retroactivity — else localized
today. Pin the _facts_ to 2022 and you get the 2022 law with no separate argument.

#### 2.4.1 The regime table — **corrected: four regimes, three boundaries**

The previous draft said "three regimes, two independent boundaries" and left the earliest
row open-ended at `… – 2021-03-14`. **That was wrong.** It omitted the **2017-04-12**
inflation adjustment, which moved every Reg CF dollar figure then in existence. The
correction matters more than a footnote: the previous table asserted `$1,070,000 / $107,000 /
$2,200` for a left edge running back to Reg CF's commencement, and those were **not** the law
for the first eleven months of the regulation's life.

Reg CF commenced **2016-05-16** (80 FR 71388, Nov. 16, 2015; Part 227 text at 71537,
amendatory instruction 4: "Effective May 16, 2016, part 227 is revised to read as follows").
Every modelled constant, every boundary:

| In force                    | 100(a)(1) offering limit | Limb test (both limbs) | Cut point 100(a)(2) | Floor 100(a)(2)(i) | Cap 100(a)(2)(ii) | Tier 1 201(t)(1) | Tier 2 201(t)(2) | First-time ceiling 201(t)(3) | Accredited carve-out                   |
| --------------------------- | ------------------------ | ---------------------- | ------------------- | ------------------ | ----------------- | ---------------- | ---------------- | ---------------------------- | -------------------------------------- |
| **2016-05-16 – 2017-04-11** | $1,000,000               | **lesser** of          | $100,000            | $2,000             | $100,000          | $100,000         | $500,000         | $1,000,000                   | none — limit applies to every investor |
| **2017-04-12 – 2021-03-14** | $1,070,000               | **lesser** of          | $107,000            | $2,200             | $107,000          | $107,000         | $535,000         | $1,070,000                   | none                                   |
| **2021-03-15 – 2022-09-19** | $5,000,000               | **greater** of         | $107,000            | $2,200             | $107,000          | $107,000         | $535,000         | $1,070,000                   | **added**                              |
| **2022-09-20 – present**    | $5,000,000               | **greater** of         | $124,000            | $2,500             | $124,000          | $124,000         | $618,000         | $1,235,000                   | yes                                    |

**Provenance — the Federal Register full text, instruction by instruction.** Verified for
this revision by fetching each release's own text, not README §2 and not eCFR prose:

| Boundary       | Release / citation                                                                                          | Amendatory instructions                                                                                                                                                                                                                                                             |
| -------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **2016-05-16** | Crowdfunding, Rel. 33-9974, **80 FR 71388** (doc 2015-28220), Part 227 text at **71537**                    | Instr. 4 revises Part 227. (a)(1) `$1,000,000`; (a)(2)(i) "greater of $2,000 or 5 percent of the **lesser**… less than $100,000"; (a)(2)(ii) "10 percent of the **lesser**…, not to exceed an amount sold of $100,000"                                                              |
| **2017-04-12** | Rel. 33-10332, **82 FR 17545** (doc 2017-06797), _Inflation Adjustments … Titles I and III of the JOBS Act_ | Instr. **5**: (a)(1) `$1,000,000`→`$1,070,000`; (a)(2)(i) `$2,000`→`$2,200` and `$100,000`→`$107,000`; (a)(2)(ii) both `$100,000`→`$107,000`. Instr. **6**: (t)(1) →`$107,000`; (t)(2) →`$107,000` and `$500,000`→`$535,000`; (t)(3) both →`$535,000` and `$1,000,000`→`$1,070,000` |
| **2021-03-15** | Rel. 33-10884, **86 FR 3496** (doc 2020-24749)                                                              | Instr. **3**: revises (a)(1) to `$5,000,000`; revises (a)(2) intro to add "Where the purchaser is not an accredited investor (as defined in Rule 501)"; revises (a)(2)(i)/(ii) from "lesser" to "**greater** of the investor's annual income or net worth"                          |
| **2022-09-20** | Rel. 33-11098, **87 FR 57394** at **57398** (doc 2022-19867)                                                | Instr. **2**: (a)(2)(i) `$2,200`→`$2,500` and `$107,000`→`$124,000`; (a)(2)(ii) both `$107,000`→`$124,000`. Instr. **3**: (t)(1) →`$124,000`; (t)(2) →`$124,000` and `$535,000`→`$618,000`; (t)(3) both →`$618,000` and `$1,070,000`→`$1,235,000`                                   |

Two consequences of reading the instructions rather than a table:

- **The 2022 cut point and the tier-1 ceiling moved by _separate_ instructions** — **2.a** for
  § 227.100(a)(2), **3.a** for § 227.201(t)(1) — of the same release, on the same day. The
  corpus comment at `regcf.l4:81-83` and README §3.3 say "the SAME amendatory instruction".
  That is defect **D3** (§1.4), fixed by **C0-f**.
- **The $5,000,000 offering limit was deliberately not adjusted in 2022** (87 FR at 57397:
  the March 2021 increase "more than account[s] for inflation"). So the offering limit and
  the investor figures genuinely do move on different dates — the observation the previous
  draft was reaching for, and it survives with the corrected table.

**One further regime, deliberately not modelled.** The COVID-19 temporary rules (85 FR 27116
eff. 2020-05-04, Rule 201(z); extended by 86 FR 3496 instr. 5 as Rule 201(bb) for
2021-03-01 → 2022-08-28) let an eligible issuer offering **more than $107,000 and not more
than $250,000** supply CEO-certified rather than reviewed financial statements — a temporary
carve-out from the Rule 201(t)(2) tier. It is named here so that "the regime table is
complete for the constants we model" is a bounded claim rather than an implied one:
`financial statements required` under a rule date inside those windows is **not** correct
without it. C1 does not model it; the floor arm (§2.4.3, ruling **R2**) does not catch it,
because it sits _inside_ the answerable window. This is recorded as a known limitation in
`regcf/README.md §5` rather than papered over. Whoever encodes the tier ceilings must decide
whether to encode 201(z)/(bb) or to refuse rule dates in `2020-05-04 … 2022-08-28` for
`financial statements required` specifically.

> **Decided 2026-07-29: refuse, and refuse in the band, not blanket.** The relief could
> only ever change the answer for an aggregate **above the then-tier-1 ceiling and at most
> $250,000**; outside that band the ordinary tiers were unaffected, so in-window questions
> outside the band still answer (and two assertions pin that). Inside the band the
> eligibility conditions turn on facts the corpus does not model (organization age, prior
> delinquency), so the arm stops on a typed `ASSUME` bottom naming Rule 201(z)/(bb) rather
> than guessing. Documented in `regcf/README.md §5`.

#### 2.4.2 The shape a C1 author writes

Constants keep their names; only the bodies change. Note that a fully dated constant needs
**three** arms, not two, and a floor arm — see §2.4.3:

```l4
IMPORT daydate                     -- `Date d m y` is daydate.l4:48-56, not a builtin
TIMEZONE IS "America/New_York"     -- REQUIRED; see trap 1 below

-- Rule 100(a)(1). $1,000,000 as adopted; $1,070,000 from 2017-04-12
-- (82 FR 17545 instr. 5.a); $5,000,000 from 2021-03-15 (86 FR 3496 instr. 3);
-- deliberately NOT adjusted by the 2022 inflation release (87 FR at 57397).
@ref 17 CFR 227.100(a)(1) — offering maximum
GIVETH A NUMBER
`offering maximum in a 12-month period` MEANS
    BRANCH IF `the rules in force include` `the 2021 amendments`           THEN 5000000
           IF ^                            `the 2017 inflation adjustment` THEN 1070000
           IF ^                            `Reg CF commenced`              THEN 1000000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`

-- Rule 100(a)(2) cut point. $100,000 as adopted; $107,000 from 2017-04-12
-- (82 FR 17545 instr. 5.b/5.c); $124,000 from 2022-09-20 (87 FR 57398 instr. 2).
@ref 17 CFR 227.100(a)(2)(i)-(ii) — income/net-worth cut point
GIVETH A NUMBER
`income or net worth cut point` MEANS
    BRANCH IF `the rules in force include` `the 2022 inflation adjustment` THEN 124000
           IF ^                            `the 2017 inflation adjustment` THEN 107000
           IF ^                            `Reg CF commenced`              THEN 100000
           OTHERWISE `no Regulation Crowdfunding figure exists before commencement on 2016-05-16`
```

_(Amended 2026-07-29: an earlier revision of this sketch — and the first implementation cut
from it — wrote these as nested `IF … ELSE IF` staircases. A cascade of `ELSE IF` is a
`BRANCH` that was not written as one: the shipped form above is flat first-match, one line
per regime, `^` dittos carrying the repeated guard head, `OTHERWISE` as the R2 floor
refusal, with named amendment dates (`` `the 2021 amendments` `` MEANS `Date 15 3 2021`
etc.) and a shared `` `the rules in force include` `` helper rather than inline
`DATE_SERIAL` comparisons. Each dated constant now reads as its §2.4.1 regime-table row —
and normalises to a multi-row GuardedRows table, which the DMN exporter can carry as an
actual decision table.)_

#### 2.4.3 What it demonstrates — restated as evaluability

Under §2.0 the claim is **not** that a page cannot hold the table above; this document just
printed it. The claim is threefold and each part is checkable:

1. **A page has one version axis, and it is the wrong one.** DokuWiki gives you "the page as
   of revision _r_". The law gives you "the rules in force on day _d_". Those are different
   functions, and their page format offers no way to express the second. §5.3 shows the
   observable consequence on their own page: two transcriptions of two parameters that moved
   together, one updated and one not, with nothing to tell a reader which is which.
2. **The boundaries are not aligned.** The offering limit last moved 2021-03-15; the investor
   figures last moved 2022-09-20; the shape (lesser → greater) moved 2021-03-15 only. A
   single "last updated: 2026-06-19" stamp asserts currency for all of them jointly and
   evidences it for none.
3. **The payoff is answering arbitrary inputs, not printing regimes.** Criterion 3 in §2.0.
   `investment limit` under a pinned rule date is a total function over (income × net worth ×
   rule date); the table above enumerates four rows. This is the part that only becomes
   visible through **C2**, which is why M5 now depends on it.

**Five traps this move must clear, none of them optional.**

1. **`TIMEZONE` is absent from `regcf.l4` and is required.** `grep -c TIMEZONE regcf.l4`
   → 0. An unpinned `RULES EFFECTIVE DATE` read with no timezone declared raises a
   `UserError` (`Machine.hs:3773-3774`). Add `TIMEZONE IS "America/New_York"` in the same
   commit as the first temporal threshold, or all 55 assertions go red at once.
2. **The unpinned fallback is a clock.** With `TIMEZONE` set, an unpinned read resolves to
   "today". In the golden suite that is deterministic — `jl4/tests/Main.hs:64-66` pins
   `2025-01-31T15:45:30Z` — and 2025-01-31 sits in the current regime, so C0's 55
   assertions keep their answers. But they keep them **by luck of the harness clock**, and
   a developer running `l4 run` by hand gets the real today. See ruling **R3**.
3. **Nothing below the earliest modelled date is safe.** With only the 2022-09-20 boundary
   encoded, `EVAL UNDER RULES EFFECTIVE AT (DATE_SERIAL (Date 1 1 2019))` returns the "greater
   of" shape, which was not the law. Phase 2's generated "not in force on ⟨day⟩" arm
   (`TEMPORAL-RULE-VERSION-DESIGN.md:348-352`) is the designed answer and is **not built**.
   C1 must hand-write a floor arm. **Settled at R2: the floor is 2016-05-16**, Reg CF's
   commencement — not "whatever the earliest encoded boundary happens to be".
4. **Per-arm citation has no home.** The inert-prose idiom the corpus uses everywhere
   (`"…" ... expr`) rides the asyndetic AND/OR operators (`Lexer.hs:149-150`), which are
   boolean-only. `investment limit` is `GIVETH A NUMBER` (**308**) and carries no inert
   prose — it cannot. So each dated arm's authority can only be a `--` comment.
   Phase 2's `@label` (`TEMPORAL-RULE-VERSION-DESIGN.md:326-336`) is what that gap is for.
5. **THE CLOSURE TRAP — dating _some_ of the constants a function reads is worse than
   dating none.** This is the trap that actually bit: the previous draft's §5.2/§6.1
   instructed that "only `income or net worth cut point` (86) and `minimum permitted
investment` (91) need dated bodies; the formula at 306-319 is untouched". False.
   `investment limit`'s limb (ii) reads a **third** constant —
   `maximum amount sold to any one investor in a 12-month period` (`regcf.l4:96`, read at
   **314-316**) — which moved `$107,000 → $124,000` on the same day, in the same release
   (87 FR 57398 instr. 2.b, "In paragraph (a)(2)(ii), removing the two references to
   `$107,000`"). Left flat, the function is anachronistic **inside its own answerable
   window**:

   ```l4
   -- Under the previous draft's minimal edit, this returns 124000.
   -- The law on 2022-06-01 capped the limb-(ii) answer at 107000.
   #EVAL `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2022))
   #      (`investment limit` (`an investor with` FALSE 1240000 1240000 0))
   ```

   The corpus already asserts exactly this input at `regcf.l4:795` (`EQUALS 124000`), and
   none of the previously specified tests touched it — the M5 fixture ($110k/$115k) sits in a
   band where the cap never binds, so the demo would have passed while the function was
   wrong for every limb-(ii) investor above ~$1,070,000. That is a **confidently wrong
   answer** — the failure mode R2 itself brands as worse than the page's staleness — and it
   is precisely the half-updated defect §5.3 prosecutes, transposed onto us.

   **The rule this trap yields, and it is a hard acceptance condition:**

   > **Temporal closure.** A function is dateable only when **every constant in its
   > transitive read set** is dated over the same window, and it carries a floor arm at the
   > window's start. Dating a proper subset is a defect, not an increment.

   The read sets, computed once here so no one has to recompute them:

   | Function                                            | Transitive read set of dateable constants                                                                                                                                                                  | Also date the **shape**?                                                                      |
   | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
   | `offering is within the offering limit` (**251**)   | `offering maximum in a 12-month period` (**79**)                                                                                                                                                           | no                                                                                            |
   | **`investment limit` (306-319)**                    | `income or net worth cut point` (**86**), `minimum permitted investment` (**91**), `maximum amount sold to any one investor…` (**96**)                                                                     | **yes** — `greater of annual income or net worth` (**290-293**), lesser→greater on 2021-03-15 |
   | `investor is within the investment limit` (**337**) | the three above                                                                                                                                                                                            | **yes**, plus the accredited carve-out at **339**, which did not exist before 2021-03-15      |
   | `financial statements required` (**357**)           | `tier 1 ceiling` (**101**), `tier 2 ceiling` (**106**), `first-time issuer review ceiling` (**111**)                                                                                                       | no — but see the 201(z)/(bb) COVID window in §2.4.1                                           |
   | `the transaction qualifies…` (**643-649**)          | **all seven** of the above (79, 86, 91, 96, 101, 106, 111) — via `issuer is eligible`, `offering is within…`, `investor is within…`, `intermediary obligations are met`, `disclosure requirements are met` | yes, both                                                                                     |

   The last row is the one that matters for C2: §3.3 makes the rule date an ordinary wizard
   question, and the boolean entry point at **643-649** reaches every constant that has ever
   moved. **So "the rule date as wizard input" is not available until all seven are dated**
   (and, for the tier ceilings, until the 201(z)/(bb) window in §2.4.1 is either encoded or
   explicitly refused).

#### 2.4.4 Prior art: OpenFisca's ten years on one time axis (researched 2026-07-29)

OpenFisca is the closest production system to this track — ~4,000 dated parameter files in
the French corpus alone — and it was surveyed before the axis landed here (source readings
against `openfisca/openfisca-core@master`; doc pages
[legislation_parameters](https://openfisca.org/doc/coding-the-legislation/legislation_parameters.html),
[40_legislation_evolutions](https://openfisca.org/doc/coding-the-legislation/40_legislation_evolutions.html),
[reforms](https://openfisca.org/doc/coding-the-legislation/reforms.html)). Five findings,
each with a consequence for us:

1. **It versions law on exactly one time axis — and it is fact-time.** `Simulation._run_formula`
   passes one `period` to both formula dispatch and parameter lookup
   (`simulations/simulation.py:335-351`); there is no as-of-law argument anywhere in core.
   The only escape is a `Reform`, which is not a date but a whole second copy of the
   tax-benefit system (`reforms/reform.py:9`). **L4's `EVAL UNDER RULES EFFECTIVE AT` is
   precisely the thing OpenFisca lacks**: law-time as a value rather than an object
   identity, making "2019 facts under 2021 rules" an ordinary query instead of a fork.
2. **Dated values are half-open intervals scanned newest-first** — `values:` keyed by ISO
   date, sorted reverse-chronologically, first entry ≤ instant wins
   (`parameters/parameter.py:77-80, 213-217`). Structurally identical to our
   newest-first `IF … AT LEAST` chains, which is reassuring: two systems converged on the
   same shape.
3. **Out-of-range behaviour is split, and half of it is dangerous.** A parameter read
   before its first value **fails loud** (`ParameterNotFoundError`); a formula evaluated
   outside its dated window **fails silent**, substituting the type default — zero
   (`simulations/simulation.py:159-161`). A silent zero for "no rule in force" is how a
   wrong number reaches a filing. **This is R2's floor-refusal design vindicated by
   counterexample**: our pre-commencement bottom is loud on both constants and shapes.
4. **Per-value legal citation exists only as hand-rolled, unvalidated metadata.** The
   French minimum-wage file carries a date-keyed `reference` map to Legifrance URLs, an
   `official_journal_date` map (effective date → publication date), and a
   `last_value_still_valid_on` freshness stamp — none of which the engine reads or checks
   (`parameters/config.py:25`). The community reinvented **per-arm citation** (our trap 4)
   and **transaction-time** (our latent `tcRuleEncodingTime`) in the only place available
   to them. Consequence for Phase 2: `@label` should be a _required, checked_ field of a
   dated arm, not optional metadata — an uncited amendment should fail the lint (R6) —
   and the rule-version axis should connect to the bitemporal ledger rather than remain a
   separate feature, because OpenFisca's users demonstrably needed the third axis and had
   nowhere to put it.
5. **Period-start resolution erases mid-year boundaries.** `parameters(period)` resolves a
   year-period to the law as of 1 January (`tax_benefit_system.py:465-466`), so a
   threshold moving on 16 May is invisible to an annual computation. Every Reg CF boundary
   is mid-year. Our rule date is day-resolved, so we do not inherit the bug — but the
   general hazard (a fact-_period_ straddling a rule-version boundary) is real here too:
   Rule 100(a)(2)'s 12-month aggregation window can straddle a release, which is exactly
   the K-b scenario §4.3 marks "the corpus cannot answer today". Name it, do not paper it.

**Language support: SPECIFIED but not built** — and the C1 spec should name the cost rather
than hide it.

| Phase   | What                                                                       | Cost of its absence to C1                                                                                                                                                                                          |
| ------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Phase 2 | `@effective` / `@repealed` / `@label` on same-named `DECIDE`s (`:326-365`) | Every dated threshold is a hand-written `IF … AT LEAST … THEN … ELSE`, and **nothing lints** that the arms are exhaustive, non-overlapping, or cited. Verbosity plus an unchecked invariant — not a capability gap |
| Phase 3 | `l4 diff-eval` (`:366-388`)                                                | No encoding-history counterfactual. Git works by hand                                                                                                                                                              |

**Language support: ABSENT.**

- `@effective` / `@repealed` decorators — `jl4-core/src/L4/Parser/ResolveAnnotation.hs:766`
  is the whole recognition test, and it reads
  `token == "export" || token == "default"`. **`nonexhaustive` is not recognised in this
  tree either** (the previous draft listed it; corrected).
- **Any external seed for the rule-version axis.** `initialTemporalContext`
  (`TemporalContext.hs:70-81`) hardcodes `tcRuleValidTime = Nothing`; the sole seed site is
  `EvaluateLazy.hs:511`. `JL4_FIXED_NOW` seeds _system_ time only. There is no
  `--rules-effective-at` flag and no jl4-service parameter.

**The workaround is in-language, cheap, and should become the C1/C2/S3 convention.**
Because the builtin is `∀a. DATE → a → a` (a serial `NUMBER` still evaluates, but no longer typechecks) and its argument is forced through the ordinary
frame protocol (`Machine.hs:1092-1099`, `serial <- expectNumber val`; the previous draft
cited `:1074`, which is a different frame), the rule date may be any runtime-computed value
— including one supplied by `@export`ed JSON invocation:

```l4
GIVEN `rule date` IS A DATE     @desc Which version of the rules should apply?
      investor    IS AN InvestorProfile
GIVETH A NUMBER
`investment limit under rules effective` `rule date` investor MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL `rule date`) (`investment limit` investor)
```

**The rule date becomes an ordinary wizard question.** No plumbing, no flag, no service
change. This is the single most load-bearing idiom in the whole track — and per trap 5 it is
**unsafe until every constant in the entry point's read set is dated**, which for the
boolean top level means all seven that have ever moved (79, 86, 91, 96, 101, 106, 111).

### 2.5 The C1 ledger, in one place

| C1 bullet (SPEC.md §4)                  | Status                                                                   | Language support                                                 |
| --------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| investor limit as a **formula**         | **Done** — `regcf.l4:306-319`                                            | built                                                            |
| obligation tail with **real deadlines** | **Mostly done** — 491-497, 563-573, 619-625. Residue = §1.5 + one `LEST` | built                                                            |
| resale as a **12-month deontic**        | **Done** — `regcf.l4:619-625`                                            | built                                                            |
| thresholds on the **rule-version axis** | **Done 2026-07-29** — see the §2.4 status note                           | **built**; Phase 2 ergonomics and the "not in force" arm are not |

**Nothing in C1 is blocked on language work.** `EVAL UNDER RULES EFFECTIVE AT` and
`RULES EFFECTIVE DATE` are shipped, typed, evaluated and covered by a blessed CI golden
(`jl4/examples/ok/tests/temporal-rule-version-spike.golden` — 7 vs 9 under two rule dates,
including the flip **back** to the old regime, which is the cache-revalidation case). What is
absent is _ergonomics_ (Phase 2 decorators, gap/overlap linting, per-arm citation) and an
_external seed_ (no `--rules-effective-at`), and §2.4's in-language idiom routes around the
seed entirely. The honest blocker on **M5** is not the language; it is **C2** (§0, §6.3) and
temporal closure (trap 5).

---

## 3. C2 — the citizen wizard

> **Status correction (2026-07-29).** When this section was written (2026-07-27), C2 was not
> started. **C2a has since shipped** — PR #162 (`65681a0a`) landed `regcf-wizard.l4`:
> 749 lines, 55 `@desc`, and **five** exports rather than §3.2's prescribed two. The two
> prescribed roles are both covered — `@export default` returning the assessment record, plus
> a boolean entry point for `/query-plan` — and three further audience-specific entry points
> (investor 12-month limit, resale restriction, reporting termination) ride along. Four
> goldens (`tests/regcf-wizard.{golden,ep.golden,nlg.golden,schema.golden}`) are in CI.
> Still open, exactly as §3.3's table says: `TYPICALLY` priors (0 occurrences) and **the
> rule-date question**, which stays gated on C1 temporal closure; C2b (frontend answer
> layer) and C2c (deploy) are untouched. The §0 table said "Not started, and blocked on
> `@export`" — true when written, stale once #162 merged without updating this document;
> both sites corrected 2026-07-29.

### 3.1 The façade pattern, reused verbatim

The precedent is `jl4/experiments/housing-act-wizard.l4` (252 lines, commit `c8452a58`) plus
`ts-apps/housing-wizard/` (commit `fefceb1e`); the build log is
`specs/todo/housing-act-citizen-wizard-demo.md`, Phases 0-1 complete. The recipe is five
mechanical parts:

1. **`IMPORT` the authoritative module** (`housing-act-wizard.l4:1-4`). The corpus is
   untouched; the façade is purely additive.
2. **One flat input record, `@desc` on every field** (`:46-51`). Booleans, numbers and
   enums only — no nested records. **The `@desc` strings become the form's question text;
   there is no other source.**
3. **Routing functions** that build each authoritative record from the flat input
   (`:64-85`), with every interpretation call documented in-file (`:31-41`).
4. **Calls to the real predicates** (`:89-99`) — the corpus stays the single source of truth.
5. **One flat presentation record + `@export default`** (`:55-60`, `:172-181`).

The justification is stated at `housing-act-wizard.l4:23-29`: a façade is required whenever
the authoritative top level is deeply nested or non-JSON-typed. **Reg CF hits the first
condition**: `the transaction qualifies for the section 4(a)(6) exemption` (`regcf.l4:636-643`)
takes six separate records.

### 3.2 The one architectural correction over the housing precedent: **two exports, not one**

`buildDecisionQueryCacheFromCompiled` calls `LadderViz.doVisualize`
(`jl4-service/src/Backend/DecisionQueryPlan.hs:181-183`), which throws
`InvalidDecideMustHaveBoolRetType` (`jl4-lsp/src/LSP/L4/Viz/Ladder.hs:310-311`) for any
non-boolean body, surfacing as **HTTP 400**. The housing façade's `@export default` returns
a `PossessionAssessment` record — so **it cannot be query-planned**, which is why
progressive disclosure stayed a Phase-3 stretch there and was never built.

C2 must therefore expose **two** exported entry points off one façade:

| Export                                         | Returns                  | Drives                                                          |
| ---------------------------------------------- | ------------------------ | --------------------------------------------------------------- |
| `regcf transaction qualifies`                  | `BOOLEAN`                | `POST …/query-plan` — elicitation, ranked asks, ladder, verdict |
| `assess a Reg CF offering` (`@export default`) | `RegCFAssessment` record | the answer card — which limb failed, which rule, the citation   |

The boolean one is nearly free: `regcf.l4:643-649` is already an `AND` of five named
predicates, which is exactly the shape the ROBDD wants.

### 3.3 What the corpus must provide

| Need                       | Why                                                                                                                                                            | Reg CF today                                                                                                                                                                                                                       |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`@desc` on every field** | The only source of question text                                                                                                                               | **0.** And Reg CF field names are verbatim statutory prose — the one at `regcf.l4:161` is 184 characters — so every one needs plain English                                                                                        |
| **`@export`**              | Schema, evaluation and query-plan all key off it                                                                                                               | **0.** `tests/regcf.schema.golden` reads `No @export annotations found in file`                                                                                                                                                    |
| **A boolean top-level**    | `/query-plan` 400s otherwise                                                                                                                                   | **Have** — `regcf.l4:642-649`                                                                                                                                                                                                      |
| **`TYPICALLY` priors**     | v2 info-gain ordering; on **boolean binders only** — `QUESTION-ORDERING-SPEC.md:96` names mapping `age TYPICALLY 18` to `P(age >= 18)` as the correctness trap | **0.** Corpus-wide, `TYPICALLY` appears only in `ok/typically-basic.l4` and four `not-ok` fixtures. **No legal corpus uses it.** Reg CF would be its first real use                                                                |
| **Textual statute order**  | `collectVarOrder` is first-occurrence DFS, so the ROBDD variable order _is_ reading order — a free isomorphism                                                 | **Have.** Do not reorder to "tidy"                                                                                                                                                                                                 |
| **The rule date as input** | §2.4's parameterised façade — **and the bearer of the M5 argument**, since criterion 3 (arbitrary inputs) is invisible in a golden file                        | **Have**, as of C2a: `investment limit under the rules effective on` takes `rule date IS A DATE`. Temporal closure landed first, so the gate below was cleared, not bypassed. ~~new. **Gated on temporal closure** (§2.4 trap 5)~~ |

### 3.4 What the service must expose — all of it already exists

| Need                     | Endpoint                                                            | Ref                                                                |
| ------------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Form schema              | `GET /deployments/{id}/functions/{fn}` → `AnnotatedFunctionSummary` | `jl4-service/src/DataPlane.hs:89`                                  |
| Evaluate                 | `POST …/{fn}/evaluation`                                            | `DataPlane.hs:90`                                                  |
| **Elicitation + ladder** | `POST …/{fn}/query-plan`                                            | `DataPlane.hs:92`; response `Backend/DecisionQueryPlan.hs:222-231` |
| Process graphs           | `GET …/{fn}/state-graphs[/{name}]`                                  | `DataPlane.hs:93-94`                                               |
| "Show the law" panel     | `GET /deployments/{id}/files?file=&identifier=&search=`             | `FileBrowser.hs:43-47`                                             |

Two findings the whole programme should take, not just C2:

- **The query-plan response already carries `ladder :: Maybe RenderAsLadderInfo`**
  (`Backend/DecisionQueryPlan.hs:231`). So **Track S1 is ~90 % served today**; only a GET
  convenience route is missing. That also makes Track E mode 2 cheap.
- **Clients must switch on `verdict`, not `determined`** — the code comment at
  `Backend/DecisionQueryPlan.hs:224-226` says a UI that switches on `determined` "will
  sooner or later tell someone they complied with a rule that never reached them".

Deployment: `nix/jl4-service/configuration.nix` used to hardcode two pre-seeded bundles
(`classic`, `thailand-cosmetics`); prod `jl4.legalese.com/service/health` reports
`ready:2, total:2`, dev reports 4. **Neither `housing-wizard` nor `regcf` is deployed
anywhere — that is still true.** A `regcf` entry now sits in that `bundles` default and a
`regcf-wizard` nginx module is imported (both landed with C2b), but the module defaults to off
and no rebuild has been run; see §3.6. CORS is permissive (`Application.hs:168-172`); the
binding constraint is the wizard's own `<meta>` CSP `connect-src` — pinned to
`http://localhost:8080` in `housing-wizard`, and a list including the loopback and Legalese
origins in `regcf-wizard`, where same-origin serving makes `'self'` sufficient in production.

### 3.5 Reuse vs build

_Written before C2b. Every item under "Must build" below is now built; **§3.6** records what
was built, four wire facts this survey did not have, and where C2c stops._

**Reuse as-is.** The five-part façade recipe; the generic schema→widget renderer
(`ts-apps/housing-wizard/src/lib/schema/{types,classify,build-tree,form-logic,labels}.ts`
plus `components/FieldRenderer.svelte` and `widgets/*` — ~230 LOC of pure TS, unit-tested);
the four Phase-0 wire facts (`specs/todo/housing-act-citizen-wizard-demo.md:156-171` —
per-function schema endpoint, `contents.result.value.<Type>` envelope, spaced-key arguments,
`x-sanitized-name`); `config.ts`'s three env vars; the entire query-plan stack including
TYPICALLY priors.

**Must build.** `regcf-wizard.l4` (the façade, with `@desc` on every field); the two exports
(§3.2); `TYPICALLY` on the boolean binders; the answer layer (~370 LOC — `api/types.ts`,
`validateAssessment`, `AnswerCard.svelte`; the MUST/MAY badge has no Reg CF analogue, the
equivalent is "qualifies / which limb failed / which rule"); **progressive disclosure**,
which does not exist client-side at all — the backend loop is finished and unexercised;
deployment. Also: `toArguments`'s return type (`form-logic.ts:97-101`) is cast to
`{situation: FormState}` and needs generalising for a multi-root form.

Two known traps: `l4 batch` is **unusable with a spaced backtick entry-point name** (its
wrapper codegen mis-parses `` `assess …` `` as five identifiers,
`housing-act-citizen-wizard-demo.md:167-169`); and stringified numbers are a verified 422.

### 3.6 What C2b built, and where C2c stops — 2026-08-02

`ts-apps/regcf-wizard` (SvelteKit SPA, `adapter-static`, no SSR). It re-implements no law:
every figure, sentence and citation is a field of a response from `jl4-service` evaluating
`regcf-wizard.l4`. `check` / `lint` / `test` / `build` are green (47 unit tests), and the app
was exercised against a **loopback** `jl4-service` on `127.0.0.1` — never against a deployed
host.

**The entry page is a hub, not a questionnaire.** The corpus exports five decision surfaces
for two audiences; one linear form would ask a founder about resale restrictions and an
investor about audited financials. The **ladder is embedded in the entry page** (SPEC.md §7,
G3) — static on the hub, interactive inside the step-by-step surface, both via the PR #177
`LadderController`.

**Progressive disclosure.** §3.5 recorded that this "does not exist client-side at all — the
backend loop is finished and unexercised". It is now exercised, over
`POST …/can this company raise/query-plan`: one question at a time, in the service's `ranked`
order restricted to `stillNeeded`, stopping the moment the **verdict** settles. Measured: with
limb 1 bound false the response is `verdict:"Fails", stillNeeded:[]`, so limb 2 is never put —
the observable difference from a form. The client switches on `verdict`, never on `determined`
(§3.4's warning, and `determined` is `null` for four of the six verdicts).

**Four wire facts this build establishes, none of them in the earlier survey.**

1. **A ladder exists only for a `DECIDE` returning `BOOLEAN`.** `GET …/{fn}/ladder` is 200 for
   `can this company raise` and 400 for the other five exports. Record-returning answer
   surfaces have no picture, by construction.
2. **`unique`, not `atomId`, joins the ladder to the query plan.** The two payloads carry
   different UUIDv5s for the same atom, and binding by the ladder's atomId returns 200 and
   silently changes nothing. Detail and the pinning test in EMBEDDABLE.md §5.1.
3. **A scalar return is not wrapped under its return-type name.** A record arrives as
   `{"value":{"RaiseAssessment":{…}}}`; the `NUMBER`-returning law-time export arrives as
   `{"value":7500}`. A client that always peeled a wrapper would read the number as `undefined`.
4. **An L4 `DATE` parameter reaches the wire as `{"type":"string","format":"date"}`**, and the
   root node of a **two-parameter** export emits **no `propertyOrder`** — only
   `required:["rule date","facts"]`. Ordering by `Object.keys` would put the four investor
   questions ahead of the date they are to be judged against, inverting R8's own derivation.
   `toArguments`'s `{situation: FormState}` cast (§3.5's last note) is generalised accordingly.

**R8, discharged.** The investor surface asks a fact date, derives the rule date from it,
**discloses** the derivation ("Applying the rules in force on 1 June 2016, because that is
when the investment was made"), and offers an override that pins law-time independently and
says so instead. Three calls, one form: the citation-carrying prose from
`investment limit check`, and two comparable numbers from the law-time export asked at two
explicit rule dates. Live, for one investor (income $150,000, net worth $80,000, invested $0,
not accredited): **2016-06-01 → $4,000, 2018-01-01 → $4,000, 2022-09-20 → $7,500,
2023-01-01 → $7,500.** No regime table lives client-side; the page compares, the engine
explains.

**C2c stops before the deploy.** Committed and inert: `nix/regcf-wizard/package.nix` (the SPA
build, `BASE_PATH` + `VITE_JL4_BASE_URL` baked in), `nix/regcf-wizard/configuration.nix` (an
nginx location at `/regcf/`, **`enable` defaulting to false**), the `regcf` entry in
`nix/jl4-service/configuration.nix`'s `bundles`, and the import in `nix/configuration.nix`.
The bundle half is verified by replicating the module's own `ExecStartPre` — copying the whole
corpus directory into a store and starting the service, which reported `exportCount: 6` and
`ready:1, total:1`, ignoring `figures/`, `tests/` and the two `.md` files. Same-origin serving
means the app's CSP `connect-src 'self'` already covers the service, so **no CSP edit is
needed to deploy**.

Two things are true and must not be read past: **the nix expressions have not been evaluated**
(there is no `nix` in the environment they were written in — they are reviewed by eye against
`nix/jl4-web`, and that is all), and **no `nixos-rebuild` has been run**. Nothing is served
anywhere as a result of this work. The remaining act is one line —
`services.regcf-wizard.enable = true;` — plus
`nixos-rebuild switch --flake .#jl4-dev --target-host root@dev.jl4.legalese.com`.

---

## 4. C3 — scenario tests

### 4.1 The mechanism that exists, and the gate that does not

Five in-file directives (`jl4-core/src/L4/Parser.hs:595-617`). Two matter:

- **`#ASSERT e` / `NOT e` / `e EQUALS v`** — the scenario-test primitive, and the only
  directive that _declares intent_. `e` must typecheck as `BOOLEAN`.
- **`#TRACE c AT t WITH PARTY p DOES a AT t' …`** — the regulative counterpart: runs a
  contract over a party-event stream to FULFILLED or BREACH. Required for the obligation
  tail, because **a `DEONTIC` cannot be `EQUALS`-compared in `#ASSERT`**
  (`.claude/skills/writing-l4-rules/references/drafting-patterns.md:253-263`). Assert the
  boolean; trace the deontic.

**`l4 run` does not fail on a failed `#ASSERT`.** `jl4/app/L4/Cli/Run.hs:75-84` computes
`overallOk = typecheckOk && not (hasBlockingError diags)`, and `hasBlockingError`
(`jl4/app/L4/Cli/Common.hs:215-219`) explicitly excludes `source == "eval"` — which is how
assertion outcomes are published. The comment at `Run.hs:75-81` says this is deliberate
contract preservation. A failed assertion renders as `"assertion failed"` and shows as an
Error in the IDE, but the process exits 0.

**So the only CI gate is the golden suite.** `jl4/tests/Main.hs:73` globs `legal/**/*.l4`;
`:121-129` attaches four goldens per file, of which `.golden` records one
`assertion satisfied` / `assertion failed` line per directive, **keyed by `file:line:col`**.

**Consequence for how C3 may be described.** Until R5 lands, C3 delivers a **regression
detector, not a verdict**: a golden text diff that goes red when an answer moves, with no
notion of an expected value that a party asserted and no exit code that says "your scenario
broke". SPEC.md §2's superset line "tests as negotiated scenarios" is therefore **half
earned** today — the artifact exists and is checkable in CI, the _gate_ does not. Say
"scenarios, checked in CI by golden diff" until (a) or (b) ships; do not say "tests that
fail". This is not a caveat to bury: an exhibit whose thesis is _"a wiki page has no
typechecker and no CI"_ (SPEC.md §1.3 finding 4) must be exact about what its own CI
actually enforces.

**`#ASSERT` is line-oriented, and the previous draft's exemplars would not have parsed.**
`directive` uses `singleLineExpr` (`jl4-core/src/L4/Parser.hs:591-617`, definition at
`:1285-1310`). The _initial_ expression parses normally, but **operator continuations** are
guarded: `singleLineExpressionCont` requires the operator token to be on the directive's own
line, or the line to begin with the `#` continuation marker. So a two-line
`#ASSERT `EVAL UNDER RULES EFFECTIVE AT` (…)\n    (…) EQUALS 11500` drops the `EQUALS 11500`
— the directive would assert a `NUMBER` (a type error) and leave a dangling expression. The
shipped spike (`jl4/examples/ok/temporal-rule-version-spike.l4`) is single-line throughout,
and every exemplar in this document has been rewritten to the **named-binding form**:

```l4
`I-3 limit under the 2022 rules` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2022))
    (`investment limit` `an investor just under the new cut point`)

#ASSERT `I-3 limit under the 2022 rules` EQUALS 11500
```

This is better than the `#` continuation marker anyway: it keeps the directive on one line,
and it makes the pinned evaluation a **first-class citable object**, which is the same
convention §4.3 wants for fixtures.

Two consequences C3 must design around:

1. **Inserting a line above an assertion re-baselines the whole golden.** A scenario block
   that grows churns the golden on every edit — the exact opposite of the "did the latest
   edit break anything?" signal C3 wants. **Mitigation: scenarios live in their own file
   with their own golden.**
2. **`jl4/experiments/` matches no glob and gets no CI at all.** The 11 `#ASSERT`s in
   `housing-act-wizard.l4:226-245` are not run by CI. `regcf/README.md:15-31` calls this out
   as "a known gap, not a convention worth copying". **C3's scenarios must live under
   `jl4/examples/legal/`.** Beware the self-import collision: an L4 file cannot `IMPORT` a
   library sharing its own basename, so `regcf-scenarios.l4` importing `regcf` is fine.

### 4.2 What Reg CF has today, and why it is not C3

`regcf.l4` carries 55 `#ASSERT` (**750-981**), 7 `#TRACE` (**879-933**), 9 named fixtures
(**653-747**), organised into eight `§§` groups mirroring the eight requirement groups, with
at least one case on each side of all 16 numeric thresholds (README §4). Five top-level
composite cases sit at **945-981**.

These are **drafter-authored correctness tests** — boundary and limb coverage. There is no
party framing, no "scenario I care about" naming, no ownership, and nothing that reads as a
negotiation artifact. The five composites at **977-981** are the nearest existing thing and
are the natural seed.

### 4.3 Whose scenarios, in what form, run by what

The negotiation-stage idea transposed to a regulation: **a rule has parties too, and each
one has a dozen situations it needs the rule to keep answering the same way.** Reg CF's
parties are already declared at `regcf.l4:58-62`.

**First, the objection that reshaped this section.** The previous draft's four exemplar
scenarios were not new content. Three already exist verbatim in C0 — the intermediary one at
`regcf.l4:843-848`, the regulator one at `regcf.l4:978`
(`the delinquent-issuer case qualifies`), the issuer ceiling one at `regcf.l4:832-834` — and
the fourth was the §5.2 M5 pair, presented twice. Relabelling an existing assertion with a
party name demonstrates nothing that C0 did not already demonstrate.

**The admission criterion, stated so it can be enforced.** A C3 scenario must satisfy at
least one of:

- **(K-a) It composes across groups.** It exercises two or more of the eight requirement
  groups jointly, so it can break when either moves. C0's assertions are single-group by
  construction (they are threshold-boundary tests).
- **(K-b) It straddles a rule boundary.** Its answer differs by rule date, so it is a
  regression test on the temporal model rather than on one number.
- **(K-c) It is a temporal trace, not a predicate.** It is a `#TRACE` over an event stream
  whose FULFILLED/BREACHED outcome is the assertion.

If a proposed scenario satisfies none, it is a C0 boundary assertion and belongs in
`regcf.l4`. Four that qualify, with the criterion each meets:

| Whose            | The question they are protecting                                        | Scenario                                                                                                                                                                                             | K         | New?                                       |
| ---------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------ |
| **Issuer**       | "Does the raise I planned survive the tier and the ceiling _together_?" | A first-time issuer raising exactly `first-time issuer review ceiling` qualifies with **reviewed** financials, and the _same_ raise by a repeat issuer does not — one input flipped, two groups move | K-a       | yes                                        |
| **Investor**     | "My 12-month lookback straddles the inflation release."                 | $60,000 already sold under the pre-2022 rules plus a new subscription priced under the post-2022 rules: does aggregation under Rule 100(a)(2) use one cut point or two?                              | K-b       | yes                                        |
| **Intermediary** | "My platform's 21-day timer must keep discharging the rule."            | A `#TRACE`: issuer files Form C on day 0, intermediary opens on day 21, one sale on day 21 and one on day 20 — the second breaches Rule 303(a)(2) while the transaction otherwise qualifies          | K-c       | yes                                        |
| **Regulator**    | "The delinquent-filer limb must keep biting after a reparation."        | A `#TRACE` on the C-AR duty with the C0-e composed contract: miss the 120-day deadline, take the `LEST` arm, and the (b)(5) limb then blocks the _next_ offering (closing README §5.6's comment)     | K-a + K-c | yes, and depends on C0-e + the §2.2 `LEST` |

The investor row is deliberately the hard one, and it is the scenario that makes the temporal
axis _load-bearing_ rather than decorative: Rule 100(a)(2) aggregates "during the 12-month
period preceding the date of such transaction", so a transaction on 2022-10-01 aggregates
purchases made under the pre-2022 cut point against a post-2022 cap. **Nothing in the corpus
answers that today**, and it is the question a real intermediary's compliance system has to
answer. Note the honest possibility that the answer is "the corpus cannot express this yet" —
in which case the scenario's value is that it says so in CI, and README §5 gains an entry.

**Form: named `MEANS` fixtures plus single-line `#ASSERT`, grouped per party by `§§`
heading, in `jl4/examples/legal/regcf/regcf-scenarios.l4`, with `#TRACE` for anything
deontic.** Named fixtures make a scenario a first-class citable object — Reg CF already does
this nine times (**653-747**) — and per §4.1 the named-binding form is also what keeps a
pinned `#ASSERT` on one line.

**Every scenario carries its own rule date.** Per §2.4 trap 2, an unpinned assertion rides
the harness clock. The C3 convention is therefore that a scenario is written pinned, as a
named binding plus a one-line assertion:

```l4
§§ `Investor scenarios — owned by the investor side`

-- I-3. The 2022 inflation adjustment HALVES my capacity by moving me across
-- the (i)/(ii) boundary. Both answers are correct for their date.
`I-3 investor` MEANS `an investor with` FALSE 110000 115000 0

`I-3 limit under the 2022 rules` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2022)) (`investment limit` `I-3 investor`)

`I-3 limit under the 2023 rules` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2023)) (`investment limit` `I-3 investor`)

#ASSERT `I-3 limit under the 2022 rules` EQUALS 11500
#ASSERT `I-3 limit under the 2023 rules` EQUALS 5750

-- I-4. THE CLOSURE REGRESSION (§2.4 trap 5). This investor is above the
-- limb-(ii) cap, so the answer is the CAP, which also moved on 2022-09-20.
-- Under a partially dated module this returns 124000 and is wrong.
`I-4 investor` MEANS `an investor with` FALSE 1240000 1240000 0

`I-4 limit under the 2022 rules` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2022)) (`investment limit` `I-4 investor`)

#ASSERT `I-4 limit under the 2022 rules` EQUALS 107000
```

I-4 is **mandatory, not illustrative**: it is the single assertion that would have caught the
blocking defect in the previous draft, and it must land in the same commit as the first dated
constant. I-3 is the M5 pair and is cross-referenced from §5.2 rather than counted twice.

**Run by what.** Today: the golden suite, whose failure message is a text diff. That is a
regression detector, not a verdict. C3 needs one of:

- **(a) `l4 run --fail-on-assert`** — a one-condition change behind a flag: relax the
  `_source /= Just "eval"` filter at `Common.hs:219` when the option is set. Small, and it
  preserves the existing contract by default.
- **(b) An out-of-band runner over `l4 run --json`** — `Run.hs:86-94` already emits
  `{file, ok, diagnostics, results}` with per-directive results.

**Not (c):** neither `l4 batch` (`jl4/app/L4/Cli/Batch.hs`) nor `POST …/evaluation/batch`
(`jl4-service/src/Types.hs:376-430`) has any notion of an _expected_ output — both are bulk
evaluators, not test runners — and `l4 batch` is currently broken for spaced backtick entry
points. See **R5**.

### 4.4 What C3 does **not** demonstrate, stated plainly

The negotiation-stage story (CLAUDE.md's "each party defined a dozen scenarios") has two
halves: **scenarios as executable artifacts**, and **parties authoring their own**. C3
delivers the first. It does not deliver the second, and the difference should not be
smudged:

- **One drafter wearing four hats is not four parties.** Nobody at an issuer, an
  intermediary or the SEC writes any of this. Party attribution is a `§§` heading and a
  comment (**R4**), with no type, no ownership and no authoring path.
- **A regulation has no negotiation stage.** The transposition is real but analogical: the
  parties to Reg CF cannot renegotiate it. The genuine analogue is _regulatory impact
  review_ — "does this amendment change any answer I depend on?" — which is what K-b
  scenarios actually test, and which is a real workflow (an intermediary re-running its
  compliance suite the week an inflation release drops).
- **So the claim C3 earns is:** _"the scenarios a party would bring are expressible,
  citable, and re-run automatically when the rules or the encoding move."_ The multi-party
  authoring claim belongs to the contract-drafting use case, not to a regulation mirror,
  and should be made there with a `@owner`-style construct behind it (**R4**).

Deployment is unaffected: `Backend/Jl4.hs:770` strips IDE directives before deploying
(`DirectiveFilter.hs:34-40` drops `#EVAL`/`#EVALTRACE`/`#CHECK`/`#ASSERT` and keeps
`#TRACE`), so a scenario-heavy corpus still deploys cleanly.

---

## 5. M5, scripted end to end

SPEC.md §8: _"ask the same question under two different rule dates and get two different
answers, each correct for its date."_

**M5 is not blocked on language work — but it is not one edit away either.** The machinery
shipped and is CI-covered; the corpus has zero temporal constructs. Two corrections to how
the previous draft staged it:

1. **Blocked on temporal closure** (§2.4 trap 5). The demonstrated function must have its
   _whole_ read set dated. For `investment limit` that is three constants plus the
   lesser→greater shape, not the two the previous draft named.
2. **Blocked on C2 for the argument, not the arithmetic** (§0, §2.0). Two `EQUALS` in a
   golden file are two numbers; the claim that beats a page is _"put in your own figures and
   your own date"_, which needs the wizard.

Neither blocker is language work, and neither has a fallback worth designing.

_The L4 in this section is written against the shipped builtins and the existing fixture
constructors, but has **not been executed** — this pass was documentation-only and ran no
build. Treat the arithmetic as verified (it is hand-checked against the Federal Register text
quoted in §2.4.1) and the syntax as **unverified** except for the one point §4.1 settles: all
`#ASSERT`s are written single-line over named bindings, because the multi-line form does not
parse._

### 5.0 Who actually asks a law-time question

The previous draft never named an audience for whom "which version of the rules?" is a
natural question, and **R8** conceded that no citizen thinks that way. Three real consumers,
so the feature is not justified by the demo alone:

| Consumer                    | The question                                                                                                                                                           | Why fact-time alone does not answer it                                                                                            |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Intermediary compliance** | "Rule 100(a)(2) aggregates over the preceding 12 months. A subscription today has a lookback window straddling 2022-09-20. Which cut point governs the earlier sales?" | The window spans two regimes at once; there is no single date to pin. This is C3's K-b investor scenario                          |
| **Auditor / dispute**       | "This transaction closed on 2022-06-01. Was it lawful **then**?"                                                                                                       | Needs the rules of the past applied to facts of the past — exactly `RULES EFFECTIVE AT`, and exactly what a current page destroys |
| **Drafter impact review**   | "The next inflation release is due around 2027 (README §2). Which of my 55 assertions change?"                                                                         | A counterfactual over a _future_ rule date against present facts. Fact-time cannot express it at all                              |

Only the second is served by R8's fallback (law-time tracks fact-time). The first and third
need the axis pinned independently — which is why the axis exists as its own clock rather
than as a derived one.

### 5.1 The warm-up — one number, two boundaries

**Setup.** `regcf.l4:79` becomes the three-arm dated body in §2.4.2. Add `TIMEZONE` and
`IMPORT daydate`. This constant's read set is itself, so closure is trivial.

**The question.** _May a clean issuer raise $3,000,000 in a single Reg CF offering?_

```l4
`W offering` MEANS `an offering of` 0 3000000 FALSE

`W within the limit in 2016` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 9 2016)) (`offering is within the offering limit` `W offering`)

`W within the limit in 2021 January` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 1 2021)) (`offering is within the offering limit` `W offering`)

`W within the limit in 2021 June` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2021)) (`offering is within the offering limit` `W offering`)

#ASSERT NOT `W within the limit in 2016`
#ASSERT NOT `W within the limit in 2021 January`
#ASSERT     `W within the limit in 2021 June`
```

| Rule date  | Limit in force | $3,000,000 | Authority                                                                      |
| ---------- | -------------- | ---------- | ------------------------------------------------------------------------------ |
| 2016-09-01 | $1,000,000     | **No**     | 17 CFR 227.100(a)(1) as adopted, 80 FR 71388, Part 227 text at 71537           |
| 2021-01-01 | $1,070,000     | **No**     | as adjusted by Rel. 33-10332, 82 FR 17545 instr. 5.a, effective **2017-04-12** |
| 2021-06-01 | $5,000,000     | **Yes**    | Rel. 33-10884, 86 FR 3496 instr. 3, effective 2021-03-15                       |

The three-row version is now the warm-up rather than the two-row version, because the
2017-04-12 row is exactly the boundary the previous draft dropped, and printing it is the
cheapest possible guard against dropping it again.

### 5.2 The headline — same investor, two dates, and the answer moves the wrong way

The offering-limit pair is clean but unsurprising: a limit went up, more became allowed. The
investor limit is the one that lands the argument, because the answer moves **counter to
intuition**: an _inflation adjustment_ **halves** this investor's lawful capacity by moving
them across a limb boundary.

**The investor.** Annual income **$110,000**, net worth **$115,000**, no prior Reg CF
purchases, not accredited.

**The question.** _What is the most this person may lawfully invest under Reg CF in a
12-month period?_

| Rule date      | Cut point | Floor  | Cap      | Limb | Arithmetic                                        | Answer      |
| -------------- | --------- | ------ | -------- | ---- | ------------------------------------------------- | ----------- |
| **2022-06-01** | $107,000  | $2,200 | $107,000 | (ii) | both ≥ $107,000 → min(10 % × $115,000, $107,000)  | **$11,500** |
| **2023-06-01** | $124,000  | $2,500 | $124,000 | (i)  | $110,000 < $124,000 → max($2,500, 5 % × $115,000) | **$5,750**  |

Both rows now print the **whole read set**, not just the constant that happens to bind. That
is the discipline §2.4 trap 5 exists to enforce: if a row of this table has a blank column,
the function is not closed over that date.

```l4
`an investor just under the new cut point` MEANS `an investor with` FALSE 110000 115000 0

`limit for that investor under the 2022 rules` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2022))
    (`investment limit` `an investor just under the new cut point`)

`limit for that investor under the 2023 rules` MEANS
  `EVAL UNDER RULES EFFECTIVE AT` (DATE_SERIAL (Date 1 6 2023))
    (`investment limit` `an investor just under the new cut point`)

#ASSERT `limit for that investor under the 2022 rules` EQUALS 11500
#ASSERT `limit for that investor under the 2023 rules` EQUALS 5750
```

**Why this is cheap — restated correctly.** `regcf.l4:788-789` already asserts the cut-point
boundary behaviour of the (i)/(ii) selector, so the fixtures and the boundary reasoning are
free. But the previous draft's sizing was **wrong and shipped a wrong answer**:

> _Previous draft, deleted:_ "Only `income or net worth cut point` (86) and
> `minimum permitted investment` (91) need dated bodies; the formula at 306-319 is
> untouched."

`investment limit` reads a **third** constant,
`maximum amount sold to any one investor in a 12-month period` (**96**), at **314-316**, and
that constant moved on the same day by the same release (87 FR 57398 instr. 2.b). With it
left flat, a query pinned to 2022-06-01 for an investor at $1,240,000 returns $124,000 where
the law said $107,000 — on an input `regcf.l4:795` already exercises. The demo fixture
($110k/$115k) escapes only because the cap does not bind in that band, so nothing in the
previously specified test set would have caught it. **Assertion I-4 in §4.3 is the mandatory
guard.** The corrected sizing is in §6.1.

### 5.3 The citation trail, for each answer

Every step is `@ref`-backed today, and the wizard's "why" panel walks the same chain:

> **Line numbers in this table, and in the two tables above it, are STALE as of 2026-07-31 and are
> not being renumbered.** `greater of annual income or net worth` and its `lesser of` twin were
> converted from standalone unary decides into **computed fields** on `DECLARE InvestorProfile`
> (`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` §4.4), which moved them up the file and shifted everything
> after them. The `@ref` citations are unaffected — the `@ref` above the `DECLARE` still carries
> 17 CFR 227.100(a)(2), and the "greater of" reasoning is still where it was relative to its own
> rule. Renumbering by hand would be a large diff whose correctness nobody can check at review
> time, and re-deriving these tables is its own task; saying they are stale is the honest
> intermediate. **Grep for the names, not the line numbers.**

| Step                              | Source                                                                     | Citation                                             |
| --------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------- |
| Which limb applies                | `either annual income or net worth is less than the cut point` **299-304** | `@ref` **299** — 17 CFR 227.100(a)(2)(i)             |
| The cut point on that date        | `income or net worth cut point` **86**                                     | `@ref` **84** — 227.100(a)(2)(i)-(ii), FR 2022-19867 |
| Why the cut point differs by date | the dated arm                                                              | Release 33-11098, 87 FR 57394 at 57398               |
| "greater of", not "lesser of"     | `greater of annual income or net worth` **290-293**                        | `@ref` **287**; the reasoning at **271-286**         |
| The 5 % / 10 % rates              | `WHERE` bindings **318-319**                                               | `@ref` **306**                                       |
| The floor                         | `minimum permitted investment` **91**                                      | `@ref` **89**                                        |

**Against the page — restated, because the previous version of this paragraph was wrong
twice.** What is on their page: `$107,000` in group 3 (investor limits) and `$124,000` in
group 4 (financial-statement tier 1). What the previous draft said about it, and why each
half fails:

| Previous claim                                            | Correction                                                                                                                                                                                                                                                                            |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "both moved … by the **same amendatory instruction**"     | Same **release** and same **day**; **different instructions** — 87 FR 57398 instr. **2.a** for § 227.100(a)(2)(i), instr. **3.a** for § 227.201(t)(1). Defect **D3**; also in `regcf.l4:81-83` and README §3.3                                                                        |
| "the figure is bound **once** and read by both consumers" | False. It is bound **three** times, at **86**, **96** and **101**, because they are **three distinct legal parameters** — the cut point, the per-investor cap, and the tier-1 ceiling — sitting in two different rules, read by three different consumers (**302**, **314**, **358**) |

**And three bindings is the right answer, not a lapse.** These parameters agree at
`$124,000` today by coincidence of the rounding table (87 FR 57394, Tables 1 and 2 — same
`$100,000` baseline, same inflation factor). They are not the same figure: they governed
different questions from the day Reg CF commenced, and a future release could move one
without the other, exactly as the 2021 release moved 100(a)(1) alone. Collapsing them into
one binding would be a modelling error that the next amendment would expose.

**So the corrected contrast is about _linkage_, not about arity.** Their page holds two
numbers with nothing relating either to its rule, its instruction, or its date — so when one
was updated and the other was not, no reader and no tool could tell which half was current.
`regcf.l4` holds three bindings, each carrying its own `@ref` to its own paragraph, each
about to carry its own effective date, and each with the typechecker and 55 assertions
standing between it and a silent divergence. **One artifact with three cited parameters beats
two uncited transcriptions of one number** — and the sharp end of the claim is that the
previous version of _this very paragraph_ was caught being wrong about it, by review reading
the source. Nothing on their page can be caught that way.

**Honest limit on the claim.** M5 demonstrates **one clock** — when the _law_ changed. SPEC
§2's "Version History" row promises two, and should stay `partial`:

| Clock                             | Mechanism                                  | Status                                                                                |
| --------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------- |
| when the **law** changed          | `RULES EFFECTIVE DATE` / `tcRuleValidTime` | **built**                                                                             |
| when the **encoding** changed     | git; `l4 diff-eval`; `tcRuleEncodingTime`  | **absent** — git by hand, tooling is Phase 3, the axis is latent (stamped, no reader) |
| when a **fact** was recorded/held | ledger `Provenance.txTime` / `vtFrom`      | built (PR #111) — but a _third_ pair, about facts, not rules                          |

Claiming encoding-history counterfactuals at M5 would overstate the tree.

---

## 6. Staging

### 6.1 The smallest **correct** increment

The previous draft's "smallest increment that visibly beats their page" was two dated
constants and two assertions. It was not correct (§2.4 trap 5) and it was not a
demonstration (§2.0). Both are fixed by making the unit **one temporally closed function**
rather than one edited number.

**Step 1 — `investment limit`, closed. ≈ 45 lines of L4, no language work, no frontend.**

| Piece                                                                                          | Why it is in the minimum                                                                                                          |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `IMPORT daydate` + `TIMEZONE IS "America/New_York"`                                            | Trap 1; without it all 55 assertions go red                                                                                       |
| `income or net worth cut point` (**86**) — three arms: 100000 / 107000 / 124000                | Read by the selector at **302-304**                                                                                               |
| `minimum permitted investment` (**91**) — three arms: 2000 / 2200 / 2500                       | Read by limb (i) at **311-312**                                                                                                   |
| **`maximum amount sold to any one investor…` (**96**) — three arms: 100000 / 107000 / 124000** | **Read by limb (ii) at 314-316. Omitted by the previous draft; this is the blocking fix**                                         |
| `greater of annual income or net worth` (**290-293**) — dated lesser→greater at 2021-03-15     | The **shape** is a dated body too. Without it the function is wrong for every investor whose income ≠ net worth before 2021-03-15 |
| A floor arm refusing rule dates before **2016-05-16**                                          | Ruling **R2**. Below commencement there is no Reg CF to answer for                                                                |
| Fixture + I-3 pair (§5.2) **and I-4, the cap regression** (§4.3)                               | I-4 is the assertion that fails if closure is broken                                                                              |
| Re-bless `tests/regcf.golden`                                                                  | Keyed by `file:line:col`, so it re-baselines wholesale                                                                            |

That is the whole investor-limit temporal model — **four regimes, three boundaries, one
shape change** — and it is the unit at which the answer is right for every input, not just
for the cherry-picked fixture. It costs about twice the previous draft's estimate and is the
first point at which the exhibit's own accuracy standard is met.

**Step 1 is necessary and not sufficient.** It produces a golden file, which is
observationally two typed numbers (§2.0). The increment that _visibly_ beats their page is
**step 1 + step 7 (C2a) + step 9 (C2c)**: the same function behind a form, where a reader
supplies their own income, their own net worth and their own date, and gets an answer with a
citation trail. That is criterion 3, and it is the honest headline.

**The §5.1 warm-up** costs one more closed constant (`offering maximum in a 12-month
period`, **79**, three arms, read set = itself) and is worth having early precisely because
its 2016/2017 rows are the guard against re-dropping the 2017-04-12 boundary.

### 6.2 Order of work

| Step   | Work                                                                                                                                                 | Depends on   | Doable now?                                                       |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ----------------------------------------------------------------- |
| **0**  | **C0-f** — the D3 prose fixes in `regcf.l4:81-83` and README §3.3                                                                                    | —            | **DONE 2026-07-29** (with steps 1-2b)                             |
| 1      | **C1-T** — `investment limit` **closed**: cut point + floor + **cap** + the lesser→greater shape + 2016-05-16 floor arm; `TIMEZONE`; I-3 **and I-4** | —            | **DONE 2026-07-29** — §2.4 status note                            |
| **1b** | **C1-T1b** — `investor is within the investment limit` closed: the accredited carve-out at **337-341**, which did not exist before 2021-03-15        | 1            | **DONE 2026-07-29**                                               |
| 2      | **C1-T2** — `offering maximum` closed (three arms incl. 2017-04-12)                                                                                  | 1            | **DONE 2026-07-29**                                               |
| **2b** | **C1-T3** — the three tier ceilings closed, **and** the documented banded refusal for the 201(z)/(bb) COVID window (§2.4.1 decision note)            | 1            | **DONE 2026-07-29** — unblocks the rule date as a wizard question |
| 3      | **C0-a/b** — D1 and D2 fixes                                                                                                                         | —            | **yes**, independent                                              |
| 4      | **C0-c/d** — Form C and intermediary duties                                                                                                          | —            | **yes**                                                           |
| 5      | **C0-e** — the composed `RAND` contract                                                                                                              | 3, 4         | **yes** — and it unblocks **P0**                                  |
| 6      | **C3** — `regcf-scenarios.l4`, party-grouped, rule-date-pinned, K-a/b/c only                                                                         | 1, 5         | **yes**; the _gate_ needs (a) or (b) — see **R5**                 |
| 7      | **C2a** — `regcf-wizard.l4` façade, `@desc`, two exports, `TYPICALLY`, the rule-date question                                                        | 1, 1b, 2, 2b | **yes**                                                           |
| 8      | **C2b** — frontend answer layer + progressive disclosure + **the applied-rule-date disclosure** (R8)                                                 | 7            | **DONE 2026-08-02** — `ts-apps/regcf-wizard`; §3.6                |
| 9      | **C2c** — deploy to `dev.jl4.legalese.com`                                                                                                           | 7            | **PREPARED, NOT PERFORMED** — §3.6; the module defaults to off    |
| —      | Phase 2 `@effective` ergonomics; `l4 diff-eval`                                                                                                      | —            | **not built.** C1 does not wait for either                        |

**M5 = steps 1, 1b, 2, 2b, 6, 7, 8, 9.** Steps 1-2b are the arithmetic; 7-9 are the argument. A
run that stops after step 1 has a correct golden file and no exhibit.

Nothing on this list is blocked on language work. The only two items that _would_ be nicer
with language work — per-arm citations and gap/overlap linting on dated arms — are
verbosity and an unchecked invariant, and both are named rather than hidden (**R6**).

### 6.3 Milestone mapping

- **M3** (mirror page) needs C0 + C2 + M2. C0's residual (§1.5) is not strictly required for
  M3 acceptance criterion 1 ("every one of their eight requirements traceable to `.l4`
  source") — but criterion 2 ("the BPMN we emit describes the same obligation tail") **is**
  blocked on C0-e, because without it there is no connected graph to emit.
- **M5** (superset page) needs **C1 + C2 + C3 + S2 + S3**. The previous mapping omitted C2
  and said "step 1 alone satisfies the §8 acceptance sentence"; that reading is withdrawn.
  §8's sentence — _"ask the same question under two different rule dates and get two
  different answers"_ — is satisfied _literally_ by two `EQUALS` lines in a golden file, and
  a golden file is not a page. Nothing in M5's previous dependency row could **ask** anything:
  C2 is the only interactive bearer, and it is an M3-track item. **SPEC.md §5's M5 row is
  corrected to `C1, C2, C3, S2, S3`** in this commit. The acceptance sentence should be read
  with its own subject restored: someone asks, at a URL, with their own figures.

---

## 7. Constraints this track works under

- **SPEC.md §7.** Not a full formalisation of 17 CFR 227. C0 is bounded by their page; C1
  extends only where it demonstrates something their format cannot **evaluate** (§2.0 — the
  "structurally cannot hold" phrasing in SPEC.md §7 is the one this track no longer uses).
  Every item in §1.5 and §2 re-encodes material already on their page, in a register the page
  cannot use — none reaches outside the eight groups. Rules 400-404, the Rule 503(a) detail,
  Rule 205 and Rule 206 stay out. The **2020 COVID temporary rules** (201(z)/(bb)) are
  in-scope material this track deliberately does not model; see §2.4.1.
- **The standing courtesy constraint (SPEC.md §1).** Everything about their site comes from
  reading published pages. No scraping, no bulk fetching, no account creation. CC BY-SA 4.0
  attribution wherever republished — already carried at `regcf/README.md:351-355`.
- **House style.** Thread a record as one `GIVEN` parameter. No new corpus in `ASSUME` style
  — `ASSUME`d terms are uninterpreted (`ValAssumed`/`Stuck`), so they typecheck but do not
  evaluate, and C3's whole point is that the assertions run.
- **Primary sources only.** No figure in this corpus came from the mirrored page
  (`regcf/README.md:9-12`); the dated regimes in §2.4.1 were re-verified for this revision by
  fetching the **full text of each of the four releases** (docs 2015-28220, 2017-06797,
  2020-24749, 2022-19867) from the Federal Register and reading the amendatory instructions
  and the as-adopted regulatory text directly — not README §2, not eCFR prose, and not the
  previous draft. That is how the missing 2017-04-12 boundary surfaced. **Any future
  revision that touches a figure or a date must do the same**, and cite the instruction
  number, because the failure mode here is not "we cannot find the number" but "we copied a
  number that was true of a different decade".

---

## 8. Rulings

R1, R2, R5 and R8 were open in the previous draft. Review closed or forced three of them and
changed the shape of the fourth; the reasoning is kept so the decision is auditable.

- **R1 — How far back does the rule-version axis go? — SETTLED: to commencement,
  2016-05-16. Four regimes, three boundaries.** The previous draft offered a menu of "two
  regimes or three" and leaned two. **The menu never contained the right answer**, because it
  omitted the 2017-04-12 adjustment (§2.4.1). More decisively, the choice is not free:
  §2.4 trap 5 shows that a partially dated function answers **confidently and wrongly inside
  its own answerable window**, so "fewer regimes" does not buy a smaller correct artifact —
  it buys a smaller wrong one. The unit of work is therefore a **temporally closed
  function**, and for `investment limit` closure means all four regimes plus the
  lesser→greater shape at **290-293**. The accredited carve-out at **337-341** is closure for
  `investor is within the investment limit`, one level up, and lands with step **1b**.
- **R2 — What happens below the earliest modelled rule date? — SETTLED: option (a), a floor
  arm at 2016-05-16.** The previous draft left this open and leant (a); review showed leaving
  it open was not tenable, because the same reasoning that condemns a 2019 query condemns the
  2016-2017 window the previous model got wrong _inside_ its own table. Decision: every dated
  constant carries an explicit floor arm at Reg CF's commencement (80 FR 71388 instr. 4,
  "Effective May 16, 2016"), and a rule date below it is a curated refusal, not an answer.
  Phase 2's generated "not in force on ⟨day⟩" arm
  (`TEMPORAL-RULE-VERSION-DESIGN.md:348-352`) remains the designed replacement and is not
  built; the hand-written arm is the interim and should be written so Phase 2 can delete it.
  **Note the limit of this ruling:** a floor arm catches queries _below_ the window. It does
  **not** catch the two failure modes that actually bit — a constant left undated _inside_
  the window (trap 5) and an omitted boundary _inside_ the window (2017-04-12). Those need
  closure discipline and primary-source verification respectively, not a floor.
- **R3 — Do C0's 55 existing assertions get pinned? — RESOLVED 2026-07-29: pin none,
  document the dependency.** The 55 assertions state the _current_ law and stay unpinned;
  the dependency on the harness clock (`jl4/tests/Main.hs:64-66`, fixed `2025-01-31`, which
  sits in the current regime) is documented at the head of the rule-version assertion group
  in `regcf.l4` and in README §5. Every assertion in the rule-version group itself is
  pinned and immune. After the next inflation release (~2027) the 55 must either be pinned
  to the pre-release regime or re-verified against the new figures — that chore is now
  written where the next editor will trip over it, instead of latent.
- **R4 — Party attribution for scenarios.** L4 has no `SCENARIO` or `OWNER` construct; `§§`
  headings and comments are the only grouping. Is a section-name convention enough to carry
  the negotiation story, or does C3 want a real construct? A construct is a language change
  and out of this track's scope; a convention is free and untyped. Leaning convention, with
  the question recorded so a later `@owner` decorator has a motivating corpus.
- **R5 — What is C3's pass/fail gate? — NARROWED to (a), with a standing disclosure until it
  ships.** (a) `l4 run --fail-on-assert`, a one-condition change at `Common.hs:219` behind a
  flag; (b) an external runner over `l4 run --json`. Choosing (a): it is smaller, it puts the
  verdict where a drafter already looks, and it preserves the existing exit-code contract by
  default (`Run.hs:76-84` documents that contract as deliberate). Neither `l4 batch` nor the
  batch endpoint is a candidate — neither carries an expected value. **Until (a) lands, C3
  must be described as "scenarios checked in CI by golden diff", never as "tests that
  fail"** (§4.1). An exhibit built on "a wiki has no CI" cannot be loose about what its own
  CI enforces.
- **R6 — Do dated arms need a lint before C1 ships, or after?** Nothing checks that the arms
  of a hand-written `IF DATE_SERIAL RULES EFFECTIVE DATE AT LEAST … THEN … ELSE` chain are
  exhaustive, non-overlapping, or cited; and per-arm citation has no home at all for
  number-returning bodies (§2.4 trap 4). This is a real lint gap that the wiki-parity
  argument should own rather than hide — the criticism levelled at their page is that
  nothing validates it. Leaning: ship C1 with the gap named in `regcf/README.md §5`, and
  treat it as the motivating case for Phase 2 rather than a blocker.
- **R7 — Which advertising deadline?** D1 (§1.4) has the Rule 204(a)(1) prohibition
  borrowing the 365-day resale constant. Rule 204 has no period; the prohibition runs for
  the life of the offering. Options: bind an `offering period` constant sourced from the
  `Offering` record; drop the `WITHIN` entirely if the deontic layer permits an unbounded
  `SHANT`; or model it as bounded by the offering's own closing date. Needs someone to check
  what an unbounded `SHANT` does to the residuation before choosing.
- **R8 — Does the wizard ask for the rule date, or fix it? — SETTLED: ask a fact date,
  _disclose_ the derived rule date, and allow an override.** The previous draft leant to the
  middle option (ask "when did/will you invest?" and let the valid-time fallback at
  `Machine.hs:3755-3758` make law-time track fact-time) and stopped there. Review's objection
  is correct and fatal to stopping there: under that option **our wizard also presents one
  slider**, which collapses the very distinction §2.4.3 stakes the argument on. The
  resolution keeps the option and adds the missing third piece:

  1. **Ask the fact date** — "when did you (or will you) invest?" — the only question a
     citizen can answer.
  2. **Disclose the derived rule date in the answer card**: _"Applying the rules in force on
     1 June 2022, because that is when you invested."_ This is the whole point. One input,
     two clocks, and the derivation **shown** — with a citation to the release that set each
     figure. A wiki cannot show this because it never computed it; its single slider is page
     revision time, which is unrelated to the law, and it has no derivation to display.
  3. **Allow an override** — an advanced control that pins the rule date independently. Not
     for citizens. For the auditor and the drafter of §5.0, whose questions cannot be
     expressed as a fact date at all.

  Piece 2 is a **frontend acceptance requirement**, added to step 8 in §6.2. Without it, the
  wizard is one slider and the objection stands.

---

## 9. Review findings and their disposition

Adversarial review, 2026-07-27, three lenses. Seven findings; **none dropped**. Six accepted
and fixed, one accepted in part with the residue rebutted in place. The two verdicts of
`DEFECTIVE` were both about §2.4/§5.2/§6.1, and both are addressed by the same structural
change: **temporal closure as the unit of work** (§2.4 trap 5).

| #      | Severity     | Finding                                                                                                                                                                                                                        | Disposition                                                                                                                                                                                                                                                                                                               | Where                            |
| ------ | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| **F1** | **blocking** | §5.2/§6.1's minimal increment leaves the limb-(ii) cap (`regcf.l4:96`) undated, so `investment limit` answers $124,000 under 2022-06-01 rules where the law said $107,000                                                      | **ACCEPTED, FIXED.** Verified: the cap is read at **314-316** and moved by 87 FR 57398 instr. 2.b. Trap 5 now states the closure rule; §6.1 dates it; assertion **I-4** is mandatory                                                                                                                                      | §2.4 trap 5, §5.2, §6.1, §4.3    |
| **F2** | **blocking** | The same defect restated: "each correct for its date" fails on the demoed function under the demo's own pinned date; refutable by one follow-up query                                                                          | **ACCEPTED, FIXED** — same fix. Also extended to the three tier ceilings, which the composite path reaches once the rule date becomes a wizard input (step **2b**, new)                                                                                                                                                   | §2.4 trap 5 read-set table, §6.2 |
| **F3** | major        | The temporal model omits the **2017-04-12** adjustment (Rel. 33-10332, 82 FR 17545): "three regimes, two boundaries" undercounts, and the earliest table row asserts figures that were not the law for 2016-05-16 → 2017-04-11 | **ACCEPTED, FIXED.** Independently re-verified from the FR full text of all four releases. §2.4.1 is now four regimes / three boundaries with every constant and every instruction number                                                                                                                                 | §2.4.1, §5.1, R1                 |
| **F4** | major        | §5.3's "the figure is bound once and read by both consumers" is false (three bindings), and "the same amendatory instruction" is false (instr. 2.a and 3.a)                                                                    | **ACCEPTED, FIXED**, and the claim **rebuilt rather than deleted**: three bindings is correct modelling because they are three legal parameters. The corpus/README copies are **D3 / C0-f**                                                                                                                               | §5.3, §1.4 D3, §1.5 C0-f         |
| **F5** | major        | "Structurally cannot hold" is unestablished for three of four C1 moves and self-refuting for the fourth; and M5's dependency row has no interactive bearer                                                                     | **ACCEPTED.** The standard is replaced by **evaluability** (§2.0), each move's claim narrowed with the concession stated, and **M5 now depends on C2** in both this document and SPEC.md §5                                                                                                                               | §2.0, §2.1-2.4.3, §0, §6.3       |
| **F6** | major        | The minimal M5 deliverable is observationally two typed numbers, and no audience is named for whom a rule-date question is natural — while R8 concedes it is unnatural for the audience we have                                | **ACCEPTED IN PART.** §5.0 names three real law-time consumers; §6.1 concedes step 1 is an engineering checkpoint, not the exhibit. **Rebutted in part at R8**: the one-slider objection is answered not by denying it but by requiring the derived rule date to be _disclosed_ — one input, two clocks, derivation shown | §5.0, §6.1, R8                   |
| **F7** | major        | C3's exemplars are three relabelled C0 assertions plus C1's pair double-counted; the pass/fail gate is an open ruling                                                                                                          | **ACCEPTED, FIXED.** Admission criteria **K-a/K-b/K-c** added and all four exemplars replaced with scenarios that satisfy them; R5 narrowed to (a) with a standing disclosure; §4.4 concedes outright what C3 does _not_ demonstrate                                                                                      | §4.3, §4.4, R5                   |

**Minor corrections also taken** (from the first lens, which returned `SOUND`): multi-line
`#ASSERT` does not parse — all exemplars rewritten as named bindings plus single-line
assertions (§4.1); `Machine.hs:1074` → `:1092-1099`; `ResolveAnnotation.hs` is at
`jl4-core/src/L4/Parser/` and recognises `export`/`default` only, not `nonexhaustive`;
`housing-act-wizard.l4` is 252 lines, not 253; `Main.hs:117-128` → `:121-129`;
`TemporalContext.hs` `applyEvalClauses` at `:85-105`, not `:83`.

**What survived refutation, and is therefore load-bearing.** The first lens verified against
source that: `EVAL UNDER RULES EFFECTIVE AT` is built, typed `∀a. DATE → a → a` (2026-07-29; previously `NUMBER`)
(`Environment.hs:78`, `:321-324`), evaluated (`Machine.hs:1092-1099`) and CI-covered by a
blessed golden that includes the flip _back_ to the old regime; `RULES EFFECTIVE DATE` and
its three-step fallback chain are real (`Machine.hs:3742-3774`); the durational prohibition
and the three-deontic obligation tail exist as claimed; the specified-vs-built ledger is
accurate throughout (Phase 2/3 design-only; no external seed; `l4 run` exits 0 on a failed
assert); every corpus count reproduces; and the M5 arithmetic hand-checks at both dates. The
second lens likewise confirmed all four effective dates, the 87 FR 57398 instructions
verbatim, Rule 204(a)(1) containing no time period (so **D1** is legally right), and the
§5.2 arithmetic against the rule text at both pinned dates. **No finding was that we assumed
a language feature that does not exist.** Every defect was in the legal model or in the
argument — which is the failure mode this exhibit is supposed to be better at, and the reason
none of them is being minimised here.
