# SG Child Support Package — conversion report

**Subject:** the SG Child Support Package and the merged childcare-leave entitlement, announced at
the Singapore National Day Rally on **23 August 2026**; and the **Child Development Co-Savings Act
2001**, the statute any of it would have to amend.

**Encoded:** 2026-08-25 · **Status:** `draft` · **HG1: waived, on the record.** No domain expert
has reviewed this against the sources.

> **This encodes an announcement, not law.** No Bill has been introduced; the Child Development
> Co-Savings Act 2001 is unamended. Every figure this encoding produces at a rule date on or after
> 1 April 2027 states a **policy intention**. **This is not legal advice.**

---

## 1. Why encode a scheme like this at all

Because the interesting question about a benefit scheme is never "what does the brochure say" — it
is **"what does this cost, and who is worse off"**, and neither is legible from the announcement.

An announcement gives you a headline (`up to $62,000 per child`), a handful of component amounts,
and a set of transition dates. What it does not give you is the **cross-product**: 20 birth cohorts
× 4 birth orders × 5 components × 3 transition cliffs, each of which either does or does not apply.
That is 1,388 questions in this encoding alone, and a human reading the web page answers none of
them. Once the scheme is executable:

- **Costing becomes multiplication instead of estimation.** Per-child entitlements come from the
  rules; population figures come from the agency. The two multiply. §7 does this, and §7.1 explains
  why the OpenFisca bridge matters for agencies that already microsimulate.
- **Cliffs become visible.** Two children born a day apart differ by $10,000 (§4.1). Nobody
  designed that; it falls out of a cohort boundary, and only an executable scheme shows it.
- **Silences become findings.** The Act contains four mechanisms the announcement does not mention.
  Each is a decision somebody will have to make before a Bill is drafted, and each is on the record
  here (§5) instead of being discovered during implementation.
- **The transition can be priced separately from the steady state**, which matters because the
  transition is where this scheme's money and its problems both are.

---

## 2. What was encoded, and how it was checked

Six modules, one shared ontology, 1,534 lines of L4:

| module | what it holds |
| --- | --- |
| `sg-child-support-domain.l4` | the nouns: `Child`, `Parent`, calendar-year and exact-age arithmetic, the rule-version predicate, and the `Interpretation` record carrying the two materialised forks |
| `sg-csp.l4` | the money: the Baby Bonus Cash Gift and Large Families Scheme being replaced, the five Package lines, the transition, and the lifetime comparison |
| `sg-childcare-leave.l4` | CDCSA ss 12B, 12C, 12CA in the shape they are written, plus the announced arm, plus the s 12B(8) obligation as a regulative rule |
| `sg-child-support.l4` | the composition and the four `@export` decision functions |
| `sg-csp-openfisca.l4` | the money projected into the subset `l4 openfisca` accepts, asserting itself equal to `sg-csp.l4` |
| `sg-child-support-cases.l4` | 71 scenario assertions |

**79 assertions, 0 failed** (71 scenario + 8 projection cross-checks).

### 2.1 The check that matters most

`life.gov.sg` publishes the scheme as a **six-row birth-cohort table**. The first assertion group
reproduces it row for row, from the rules rather than from the table:

| born | five Package lines | reached by |
| --- | --- | --- |
| 2027-04-01 onward | **$62,000** | the full Package |
| 2026-01-01 – 2027-03-31 | **$57,000** | Gift top-up + Credits + cap + PSEA |
| 2023-02-14 – 2025-12-31 | **$53,000** | (a 2023 birth; later years rise as Credit years accrue) |
| 2015-01-01 – 2023-02-13 | **$43,000** | Credits + cap + PSEA; no Gift |
| 2010-01-01 – 2014-12-31 | **$12,000** | Credits + PSEA only; the CDA has closed |
| 2009 | **$10,000** | the PSEA top-up and nothing else |

If the encoding reproduces the published table row by row, the cohort logic is right. If it did
not, no downstream figure would be worth reading. **It does.**

The headline is reached by exactly one cohort. Every existing child collects less, and the encoding
says by how much rather than repeating the headline.

---

## 3. The Package is a large increase. Three things in it are not.

Nothing below says families are worse off — they are substantially better off, and the encoding
asserts that too. The findings are about **which lines move which way**, which the headline
conceals.

### 3.1 The cash line falls for every child born since February 2023

The $10,000 Baby Gift replaces a Baby Bonus Cash Gift of **$11,000**, or **$13,000** for a third or
subsequent child. It is a floor, so nothing already paid is recovered — but the remaining
instalments stop.

| born | 1st child | 2nd | 3rd | 5th |
| --- | --- | --- | --- | --- |
| 2015 – 2022 | $0 | $0 | $0 | $0 |
| 2023 | −$1,000 | −$1,000 | −$2,400 | −$2,400 |
| 2024 onward | **−$1,000** | **−$1,000** | **−$3,000** | **−$3,000** |

It is the one line of the Package that goes **down**, and it goes down **three times as far for a
third or subsequent child** — the birth orders the scheme it replaces was built to favour.

### 3.2 The co-matching cap is cut for every child but the first, and there is a deadline

Government co-matching into a Child Development Account is capped by birth order today: **$4,000 /
$7,000 / $9,000 / $15,000**. From **1 October 2027** every cap becomes **$5,000**. A first child
gains $1,000. Everyone else loses, and the loss is **headroom that lapses on a date**:

| birth order | cap to 30 Sep 2027 | cap after | headroom lost if nothing saved |
| --- | --- | --- | --- |
| 1st | $4,000 | $5,000 | — (gains $1,000) |
| 2nd | $7,000 | $5,000 | **$2,000** |
| 3rd | $9,000 | $5,000 | **$4,000** |
| 5th | $15,000 | $5,000 | **$10,000** |

This is the one finding a family can **act on**: a family with a fifth child born before 1 April
2027 has until **30 September 2027** to save $15,000 into the CDA, and $10,000 of matching turns on
whether they do. §4 of the app computes it for any amount already matched.

### 3.3 "The Government will cover the cost" has four words after it

CDCSA s 12B(9) makes the employer pay the employee's gross rate for every day of leave; s 12C lets
them reclaim **days four to six only**, at not more than **$500 a day**. So today the employer bears
the first three days in full. The Rally said the Government would cover all child-related leave
**"up to the reimbursement limit"** — reported unchanged at $500 a day, while the day count roughly
doubles.

Below $500 a day the employer's cost goes to **zero**. Above it, the employer pays the excess on
every one of the doubled days, and past a crossover the total **rises**:

| gross daily rate | 1 child: today → announced | 3 children: today → announced |
| --- | --- | --- |
| $400 | $1,200 → **$0** | $1,200 → **$0** |
| $800 | $2,400 → $2,400 (break-even) | $2,400 → **$3,600** |
| $1,200 | $3,600 → **$5,600** | $3,600 → **$8,400** |

The crossover is a gross daily rate of about **$800 with one child** and about **$667 with three**.
Above it, an employer of well-paid parents pays **more** under a reform announced as removing the
burden from employers.

Two caveats, both material. This counts **childcare leave only** — maternity, paternity, adoption
and shared parental leave are outside this encoding (register entry `M3`), so the figure is a
**lower bound**. And it rides on fork **F7**: that the employee keeps their gross rate and the
employer bears the excess. On the rival reading — the structure s 12B(10) already uses — the
*employee* is capped instead and takes a pay cut on leave days. Either way somebody bears the
excess; the fork decides who, and nobody has decided it.

---

## 4. Cliffs the announcement does not mention

### 4.1 One day, $10,000

Two first children, born **13 and 14 February 2023** — the day before and the first day of the
Budget 2023 Cash Gift enhancement:

|  | born 13 Feb 2023 | born 14 Feb 2023 |
| --- | --- | --- |
| five Package lines | **$43,000** | **$53,000** |
| lifetime cash received | $8,000 | $10,000 |

The Package-side gap is **$10,000**; counted over both their lifetimes it is **$2,000**, because the
earlier child was paid $8,000 in 2023 and the later child's $11,000 was cut to $10,000. Both numbers
are true and they answer different questions, which is why the encoding computes them with different
functions and the app labels which is which.

### 4.2 The commencement cliff is smaller than it looks

A first child born **31 March 2027** gets $57,000 of Package lines; one born **1 April 2027** gets
$62,000. The $5,000 gap is the CDA First Step Grant, which the earlier child already received under
the outgoing scheme. On a lifetime footing they are much closer — which is the transition working.

---

## 5. Nine forks, two materialised

Full detail in `registers/fork-register.json`. Two survive both readings and are **fields of one
`Interpretation` record**, so both execute and the case suite shows what turns on the difference:

- **F1 — is the harmonised $5,000 co-matching cap a lifetime total or fresh headroom?**
  life.gov.sg says "all caps adjust to $5,000" and does not say. **$5,000 per child** turns on it,
  concentrated on the largest families. The fork *opens* on 1 October 2027; before that both
  readings agree, which the case suite asserts.
- **F2 — does the service-duration graduation survive the merger?** The Act gives 2–6 days graduated
  by months served; the announcement states one number per family size and is silent on part-year
  service. A half-year employee gets **4 days or 8**.

Seven more are resolved at encode time. The one worth a reader's attention is **F5**: the Act's
per-child lifetime caps (42 days of childcare leave, 12 of extended) **cannot** survive a scheme
offering 8–12 days a year for twelve years, and the announcement does not say what replaces them.
The announced arm therefore answers **per relevant period only**. That is a real gap, on the record.

Three further silences are recorded rather than resolved away: the **s 12B(1B) bar** on a natural
father in defined circumstances (F6), which no announcement repeals; the **commencement date** of
the merged leave scheme (F3), which does not exist and is a labelled placeholder here; and the
**rounding rule** for a fractional graduated day (F2), which is the encoding's own construction and
says so.

---

## 6. What the encoding refuses to answer

- **Baby Bonus rates before 1 January 2015.** The scheme has been re-rated repeatedly since 2001 and
  this encoding holds two cohorts' rates. Below that floor the *comparison* functions stop with a
  named `ASSUME` bottom rather than quote a rate nobody measured. The **Package-side** answer is
  total from a 2009 birth onward.
- **Maternity, paternity, adoption and shared parental leave** (`M3`), which makes §3.3 a lower
  bound.
- **Preschool fee reductions and the BTO changes**, announced at the same Rally. The preschool
  measure is stated as a *target* ("we aim to reduce fees to $150 a month" by 2030) rather than a
  rule, and the subsidy detail is deferred to early 2027; there is not yet enough to encode. The BTO
  ballot change (one extra chance per citizen child aged 18 and below, from February 2027) is
  encodable and was left out for scope, not for difficulty.
- **Edusave**, which makes up the difference between the Package's "$62,000" and the speech's
  "almost $70,000".

---

## 7. Costing the scheme

Per-child entitlements come from the encoding; population figures are the analyst's. The
multiplication is the point.

For a full post-commencement cohort at **$62,000** per child, of which **$57,000** is unconditional
payment and **$5,000** is a co-matching *cap* that depends on families saving:

| citizen births a year | at 100% co-matching take-up | at 70% | at 0% |
| --- | --- | --- | --- |
| 28,000 | **$1.74bn** | **$1.69bn** | **$1.60bn** |
| 30,000 | $1.86bn | $1.82bn | $1.71bn |

That is the **steady-state** commitment for one birth cohort, birth to 17 — what the scheme costs
each year once every cohort is in the system — not a cash-flow forecast. Disbursements spread over
eighteen years, and the **transition years cost more**, because roughly 610,000 existing children
are being brought into Child Credits and the PSEA top-up at once. §6 of the app recomputes all of
this against any figures you put in.

Only one line is behavioural. The other four are entitlements that follow from facts the agency
already holds.

### 7.1 The OpenFisca bridge, for agencies that already microsimulate

Flat per-cohort arithmetic is the wrong tool for distributional questions — *which* families gain,
how the gain interacts with means-tested subsidies, what happens at the household rather than the
child level. Agencies that ask those questions already run **OpenFisca** microsimulations against
population microdata, and L4 exports to it:

```
l4 openfisca sg-csp-openfisca.l4 -o sg_child_support.py
```

emits `projections/openfisca/sg_child_support.py` — a runnable `TaxBenefitSystem` with **12
variables and 6 NumPy-vectorised formulas**, each carrying its `@export` description as its label,
ready for `SimulationBuilder`. The rules stay in L4; the microdata stays in the agency's model.

**Two honest limitations.**

The exporter's v1 subset does **not** accept the date builtins (`YMD`, `DATE_YEAR`) or `WHERE`/`LET`
bindings, and `sg-csp.l4` — written to be read against the source — uses both throughout. Pointing
`l4 openfisca` at it fails with four named reasons. That is why `sg-csp-openfisca.l4` exists: it
restates the money lines in the accepted subset, taking a **birth year plus three boolean cohort
flags** where the main encoding takes a date. **Every date-banded scheme will hit this**, and it is
the single change that would most improve the bridge.

A projection that is never compared is a fork nobody declared. So the projection **asserts itself
equal to `sg-csp.l4`** over five cohort bands and a non-citizen — 8 assertions, all passing. If the
two ever disagree, the assertions fail.

*(The exporter also emits `definition_period = MONTH` for every variable, where an annual benefit
would more naturally be `YEAR`. Worth checking before an agency wires it into a live model.)*

---

## 8. Evidence

| artifact | what it is |
| --- | --- |
| `registers/source-bundle.json` | six documents with sha256 over the bytes fetched, including the **instrument** — the CDCSA — whose provisions produced four of the nine forks |
| `registers/external-modifications.json` | four searches with their coverage limits stated, and four findings; the sweep's central result is a **checked negative**: no Bill exists |
| `registers/fork-register.json` | nine forks; readings, the one taken, and why |
| `source/fetch.sh` | re-runs the fetch reproducibly |
| `app/` | a single-file browser tool; every number in it came from `l4 run --json` |
| `projections/openfisca/` | the emitted OpenFisca module |
| `tests/*.golden` | four goldens per module |

All three registers validate against the schemas in
`specs/todo/single-instruction-demo/schemas/`.

**What has *not* been done:** no domain expert has reviewed this against the sources; HG1 is waived
on the record. Fork-register completeness is unfalsifiable and is not claimed — what can be said is
how the list was built (every figure traced to a rule, then ss 12B/12C/12CA read line by line
against the announcement, entering each unmentioned mechanism). That procedure finds silences. It
does not find a reading nobody thought of.

---

## 9. The pipeline run

Driven by `etc/go/go.sh` in `legalese/l4-ide`, subject `sg-child-support`, encoding `primary`.
Run `2026-08-25-423e1cb8-001`. **VERDICT: COMPLETE.**

| stage | status | what it means here |
| --- | --- | --- |
| `p0-preflight` | PASS | toolchain and sidecar resolve |
| `p3-check` | **PASS** | every module typechecks; both automatable house rules hold |
| `p6-tests` | **PASS** | 79 assertions across six modules, 0 failed |
| `p8-verify` | **PASS** | propositional consistency of the boolean decision skeleton |
| `p7-lts` | NOT-BUILT | the labelled-transition-system projection has no implementation |
| `p7-mcp` | SKIPPED | no `JL4_GO_SERVICE_URL`; the deployable zip was still built and hashed (23,320 bytes) |
| `p7-akn` | UNVERIFIED | 40,936 bytes of Akoma Ntoso 3.0 emitted, well-formed; no oracle strong enough to license PASS |
| `p9-cost` | PASS | the run's own cost, attested and attributed |
| `p9-report` | PASS | all 11 required sections; 5 render ABSENT with a stated reason |
| `p9-explain` | SKIPPED | no checked-in explainer narrative for this subject |

`p3-check` was **DEGRADED on an earlier run** with a real finding: seven `ELSE IF` sites against
the house rule preferring `BRANCH`. They were converted and the assertions re-run unchanged; the
finding was a defect in the encoding, not noise from the checker.

### 9.1 What `p8-verify` actually proved, and what it did not

`p8-verify` is an SMT consistency check over the **boolean** decision skeleton: it looks for
unsatisfiable guards, dead branches, vacuous guards and unreachable outcomes. It reported
**0 findings** across all six modules, with all five of its negative and positive controls
reproducing — so the leg is demonstrably capable of red.

**Read the skipped column before reading that as a clean bill of health:**

| module | decisions | analysed | skipped (non-boolean) |
| --- | ---: | ---: | ---: |
| `sg-child-support-domain` | 5 | 1 | 4 |
| `sg-csp` | 39 | **1** | **38** |
| `sg-childcare-leave` | 20 | 3 | 17 |
| `sg-csp-openfisca` | 11 | 0 | 11 |
| `sg-child-support` | 7 | 0 | 7 |

This subject is **arithmetic**, not propositions: 96 of its 107 decisions return a number, and the
rung-1 checker does not reach them. The evidence that the money is right is the **79 assertions**
and the row-for-row reproduction of the published cohort table (§2.1) — not this leg. A reader who
took `p8-verify: PASS` as "the entitlements are verified" would be reading it for a claim it does
not make.

### 9.1b A compiler defect this corpus found

The `prettyLayout` round-trip property (`jl4/tests/Main.hs`, #932) — print a module, re-parse it,
re-type-check it — **failed on two of these six modules**, and the cause is a defect in the printer
rather than in the encoding.

`prettyLayout` re-emits a mixfix application in the uncurried `f OF a, b` form and drops the
interior keywords. Inside one module that is self-consistent: it strips the keywords from the
*definition* too, so the printed module re-parses. **Across a module boundary only the call site is
rewritten** — the imported definition still demands its keyword — and the printed source no longer
type-checks:

```
`today's cost` MEANS `the employer's cost under the Act for` OF parent, `rule date`
      →  Expected keyword `on` but found `rule date`
```

It is **intermittent**, which is why no existing corpus caught it. A cross-module call survives
wherever the printer happens to parenthesise it — `(`the year` OF child, 1)` re-parses fine — and
fails only where the call is the whole right-hand side of a binding or a record field, where the
commas go ambiguous. `regcf` and `sg-succession` keep their interior-keyword definitions and their
uses in the same module, so neither ever exercised the cross-module path.

**What was done about it.** The encoding's cross-module surface was renamed to head-keyword-only
(`` `days of leave under the Act` parent day `` rather than
`` `days of leave under the Act for` parent `on` day ``), which costs some of the prose readability
the house style exists for and is therefore recorded as a **workaround, not a preference**. All 79
assertions pass unchanged after the rename — it moved names, not values. The defect and the
suggested fix (parenthesise every multi-argument `OF` the printer emits, which makes the
round-trip independent of position) are written up for upstream and reproduced in `NOTES.md` §9.

This is the round-trip property doing exactly the job `CLAUDE.md` §3.2 describes: it has no
known-failure list, so a corpus that trips it either gets fixed or turns the suite red for the next
person. It also found something no reviewer would have.

### 9.2 Independently checkable

```
etc/go/go.sh verify --run-id 2026-08-25-423e1cb8-001 --gates
  journal chain: verifies (22 records)
  artifacts: 39 recorded, 39 still hash as recorded
  gate HG1: waived — [reason on the record]
  VERDICT: COMPLETE
```

No build, no model, no network. `HG1` was **waived, not signed**, and the waiver's reason is the
honest one: the encoding states an announcement, no Bill exists for an expert to review it against,
and a signature over a moving target would be worth less than the sentence saying so. The waiver
binds to the corpus digest — edit any module and the gate re-opens.

---

## 10. What this cost

Requested so that a reader can price the capability rather than guess at it. Every token figure
below is **measured** from the session transcript; every dollar figure is that measurement
multiplied by Anthropic's published list price for `claude-opus-5` as at 2026-08-26
([platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing)):
$5/MTok base input, $10/MTok 1-hour cache write, $0.50/MTok cache hit, $25/MTok output.

Scope: from the first retrieval to the final report — retrieval, statutory reading, encoding,
debugging, golden regeneration, the pipeline run, the app, the OpenFisca projection, the registers,
the deposit and this document. One model, `claude-opus-5`; no subagents, no workflows, so nothing
is attributable to fan-out.

| line | tokens | rate | cost | share |
| --- | ---: | ---: | ---: | ---: |
| Cache reads (hits) | 76,274,229 | $0.50 / MTok | **$38.14** | 71% |
| Cache writes (1h TTL) | 832,674 | $10.00 / MTok | **$8.33** | 16% |
| Output — incl. ~91,262 reasoning | 283,153 | $25.00 / MTok | **$7.08** | 13% |
| Fresh (uncached) input | 474 | $5.00 / MTok | $0.00 | 0% |
| Web search | 6 searches | $10 / 1,000 | $0.06 | 0% |
| **Total** | | | **$53.61** | |

Wall clock **90 minutes** (20:49:19Z → 22:19:25Z), of which the pipeline's own stage execution was
**98 seconds**; 237 API requests over 253 tool calls. So roughly **$0.60 a minute**, and about
**3.5¢ per line of committed L4** (1,536 lines across six modules).

Three caveats, because each of them moves the number:

- **Cache reads are 71% of the bill, and they are the price of a long single-context session.**
  Nothing here is a defect — re-reading a 200-file worktree from cache is what makes an hour-long
  encoding coherent — but it means the cost scales with *session length*, not with the size of the
  law. A shorter subject in a shorter session is cheaper than this per unit of output, and a
  compaction resets the multiplier.
- **The cache-write line assumes the 1-hour TTL this session ran under.** At the 5-minute TTL
  ($6.25/MTok) the same run prices at **$50.48**.
- **Do not sum the transcript naively.** A raw sum over usage records double-counts, because a
  single API request appears once per streamed record; `etc/go/lib/cost-ledger.mjs` dedupes by
  `requestId` and warns that the naive sum over-reports by ~2.2×. Every figure above is deduped.
  Taken naively this run would have read as roughly **$118**, which is wrong by more than double.

For comparison, the pipeline's own attested ledger (`go-run-cost-ledger.json`), snapshotted at
22:16:03Z — three minutes before the session ended — recorded 231 requests and 277,311 output
tokens. The difference is the tail of the run, not a disagreement in method.

**What is not in this figure:** no domain-expert review (HG1 was waived, §9.2), no deployment, and
no human drafting time. It is the machine cost of one operator saying *"SG Child Support Package:
go"* and reading what came back.
