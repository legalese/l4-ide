# British Nationality Act 1981, section 1 — the de novo smoke-test corpus

`bna.l4` formalises **section 1 of the British Nationality Act 1981 (c. 61)** — acquisition of
British citizenship by birth or adoption in the United Kingdom — as an isomorphic, inert-style L4
encoding of the current consolidated text. It is the de novo (G2) encoding subject for the demo
pipeline smoke test: a fresh statute, encoded by hand through the stages the `go` orchestrator will
someday drive automatically, "as is traditional" (Sergot, Sadri, Kowalski, Kriwaczek, Hammond &
Cory, _The British Nationality Act as a Logic Program_, CACM 29(5) 370–386, 1986).

**The law is stated as in force on 4 July 2026.** Every quoted rule text is verbatim from the
legislation.gov.uk revised version of s 1 (its own banner: "up to date with all changes known to be
in force on or before 04 July 2026"), retrieved 2026-08-02 via Wayback Machine captures of the same
URLs (legislation.gov.uk itself sat behind an AWS WAF challenge). Full provenance, the verbatim
section text with its F1–F19 amendment markers and C1–C5 modification notes, and the s 50
definitional extracts are in [`source-s1.txt`](source-s1.txt) in this directory.

The pre-existing `jl4/examples/legal/british-citizen-act.l4` is an unrelated toy and shares nothing
with this corpus.

## Why this lives in jl4/examples/legal/

The CI glob `legal/**/*.l4` is recursive, so `bna/bna.l4` is typechecked, exactprinted,
NLG-rendered and schema-checked on every CI run. Files under `jl4/experiments/` get no coverage.

## Scope

| s 1 provision | encoded as                                                                                         |
| ------------- | -------------------------------------------------------------------------------------------------- |
| (1)           | `` `a British citizen by virtue of subsection (1) or (2)` `` — birth + parent-status limbs         |
| (1A)          | `` `a British citizen by virtue of subsection (1A)` `` — armed-forces route                        |
| (2)           | `` `deemed by subsection (2) to satisfy subsection (1)` `` — rebuttable foundling presumption      |
| (3)           | `` `entitled to be registered under subsection (3)` `` — BOOLEAN entitlement predicate             |
| (3A)          | `` `entitled to be registered under subsection (3A)` `` — BOOLEAN entitlement predicate            |
| (4)           | `` `entitled to be registered under subsection (4)` `` — BOOLEAN entitlement predicate             |
| (5), (5A)     | `` `a British citizen by virtue of subsection (5)` `` over an `AdoptionCase` record                |
| (6)           | `` `a British citizen notwithstanding cesser of the order — subsection (6)` `` — an invariance     |
| (7)           | folded into (4) as the discretionary escape from the residence limb; the exercise is an input      |
| (8)           | definitional pointer to s 50 "settled"; carried by the settled-parent field's `@ref`, not expanded |
| (9)           | the dated constant `` `the relevant day` `` = 13 January 2010                                      |

Facts are threaded as one `GIVEN` record per subject — `PersonProfile` for the birth and
registration limbs, `AdoptionCase` for (5)/(5A)/(6). There is no top-level `ASSUME`. The
registration **process** is out of scope: (3)/(3A)/(4) are encoded as "is entitled to be
registered" predicates, with the good-character restriction (modification C3, IANA 2006 s 58 →
s 41A) as a separate grant-gate predicate `` `registration may be granted` `` so the s 1
entitlements stay textually pure.

## Scoped out (inputs, not stubs — each field carries an `@ref` to the provision that construes it)

- **"settled"** — the s 50(2)–(5) construction (ordinary residence free of immigration-law time
  restriction; the s 50(4) exemption carve-back specific to s 1(1) and its diplomatic-immunity
  exception; the s 50(5) unlawful-presence subtraction) arrives as an already-construed input fact.
- **"member of the armed forces"** — s 50(1A)–(1B) (Armed Forces Act 2006 regular/reserve forces
  minus the deemed-member cases).
- **section 10A citizenship** — the EU withdrawal agreement registration route (S.I. 2021/743); an
  input flag read by the (3)/(3A)/(4) chapeau.
- **good character** — s 41A content; the input flag asserts satisfaction "where the requirement
  applies" (applications under (3)/(3A)/(4) by persons aged 10+).
- **s 14** (British citizen "by descent" classification), **s 3** (discretionary registration of
  minors), **Sch. 2** (statelessness routes) — conceptual neighbours, noted only.
- **HFEA parental-order modifications** (C1/C4/C5, S.I. 2010/985 and 2018/1412) — not modelled.
- **Modification C2** (S.I. 1972/1613 art. 6, as inserted by S.I. 1982/1649 art. 3) — "explains"
  s 1(1) by treating certain persons exempt from immigration control as settled; its substance
  rides inside the settled-as-input scope-out above, so it is neither encoded nor separately
  modelled.
- **Historic texts** — no rule-version axis: the pre-2002 (no qualifying territories), pre-2010 (no
  armed-forces route) and pre-2021 (no s 10A words) versions are not encoded. The F-key dates in
  `source-s1.txt` are the raw material for that axis if a later pass wants it.

## Ambiguity register (each recorded at its site in `bna.l4` as an `-- AMBIGUITY:` comment)

| #   | site                 | question and reading taken                                                                                       |
| --- | -------------------- | ---------------------------------------------------------------------------------------------------------------- |
| A1  | (1)/(2)/(3)/(4)      | "after commencement": birth **on** 1 Jan 1983 counts — commencement is an instant; encoded `AT LEAST 1983-01-01` |
| A2  | (1)(b)               | "that territory" = the particular territory of birth, not any qualifying territory                               |
| A3  | (2)                  | "new-born infant" undefined; new-born-ness is an input fact for the fact-supplier                                |
| A4  | (2)                  | "unless the contrary is shown": one rebuttal flag; rebutting either deemed limb defeats the deeming              |
| A5  | (1A)                 | "on or after the relevant day" qualifies both places of birth, not only territory births                         |
| A6  | (3)/(3A)/(4) chapeau | "by virtue of … (2)" read as "(1) as read with (2)"; citizenship via other routes is NOT excluded by the words   |
| A7  | (3)                  | "while he is a minor" distributes over both limbs — parent's change of status AND application during minority    |
| A8  | (4)                  | "each of the first ten years of that person's life" = life-years; encoded as max-days-per-year ≤ 90 (equivalent) |
| A9  | (4)                  | day-counting convention for absences left to the fact-supplier's certified count                                 |
| A10 | (5)(a)               | the appointed-day condition qualifies the **making** of qualifying-territory court orders                        |
| A11 | (5A)(b)              | joint adopters: each habitually resident within (UK ∪ designated territory); same-place not required             |
| A12 | C3 (not s 1 text)    | good character restricts the **grant**, not the s 1 entitlement — hence the separate gate predicate              |

Fork machinery is deliberately not used (ruling R4 is unruled); prose comments are the smoke-test
answer.

## Tests

42 `#ASSERT` scenarios (plus one `#EVAL`), grouped per subsection with boundary pairs at
commencement (1983-01-01), the appointed day (2002-05-21), the relevant day (2010-01-13) and the
90-day absence ceiling; at least one negative per encoded subsection. Lead fixtures include
Sergot et al.'s Peter (born in the U.K. on 3 May 1983 to a British-citizen parent, per the paper's
Figure 4 APES dialogue), a chapeau-isolating Peter variant with both s 1(3) limbs satisfied, a
foundling and his rebutted twin, an armed-forces child, a child of visitors, a ten-year applicant
of bad character, and a Gibraltar adoption order. Verified green with:

```
JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 check jl4/examples/legal/bna/bna.l4
JL4_LIBRARY_PATH=<repo>/jl4-core/libraries l4 run   jl4/examples/legal/bna/bna.l4
```

Greenness is judged from the run log's `assertion satisfied` / `assertion failed` lines, not the
exit code: `l4 run` exits 0 even when an assertion fails (measured; see `SMOKE-REPORT.md` §3.2).

## Projection artifacts

- `bna.dmn` + `bna.fidelity.txt` — the DMN 1.3 export (`l4 export --to dmn --flavor camunda
--fidelity-report`): 43 decisions, one decision table, **zero blocking notes**, and it **executes
  green on both engines** against `bna.cases.json` (KIE 1075/1075 + 325/325 service outputs,
  Camunda 1075/1075). Until #196 landed the YMD lowering, the 3 dated constants emitted raw L4 and
  both engines refused the file whole; that history and the cause isolation that pinned it are in
  `SMOKE-REPORT.md` §1.
- `bna.dmn.md` + `bna.dmn.fidelity.txt` — the dmn-md export; header-only for this corpus (every
  decision is a literal expression or a table dmnmd cannot carry).
- `bna.cases.json` — 25 cases x 43 expect pins, every pin derived from the L4 source under the
  activation contract (see its `note` block).
- `SMOKE-REPORT.md` — what ran end to end, the hand-driven stage ledger for the `go` orchestrator,
  and the measured findings.

## What the 1986 paper did vs what this does

The 1986 paper translated the Act **as enacted in 1981** — the first four parts, plus the Part 5
definitions and the schedules those parts needed, approximately 50 of the Act's 73 pages — into
extended Horn clauses, using negation as failure for its defaults and exceptions, to argue that
legislation could be executed as a logic program; the running demonstration (December 1983, on a
128-kbyte micro) was a ~150-rule subset dealing with acquisition of British citizenship, the paper
estimating the complete act at about 500 rules. This encoding covers only section 1, but of the **current
consolidated text** — qualifying territories (2002), the armed-forces route (2010), the s 10A
exclusion (2021), the substituted adoption provisions — with the verbatim statutory prose riding
inline as inert carriers and boundary tests asserting each limb, so the file is auditable against
the statute line by line. Where the paper leaned on negation as failure for the foundling
presumption, this encoding makes rebuttal an explicit input fact, and it separates the s 1
entitlement from the s 41A grant restriction that post-dates the paper by twenty years.
