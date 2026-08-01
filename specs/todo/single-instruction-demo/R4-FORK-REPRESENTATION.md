# R4 — representing interpretation forks: the `Interpretation` parameter

**Status: DRAFT design note, written 2026-08-01 at Meng's direction, developing the shape he
proposed ("a public interface to the decision that takes GIVEN interpretationChoice … delegate to
… private implementation … quickcheck over all choices"). R4 in [SPEC.md](./SPEC.md) §9 remains
OPEN until Meng rules on this note; nothing below is built.** The worked example uses real Reg CF
material but is illustrative, not committed corpus code.

---

## 1. The proposal

One fork point = one enumeration. All fork points in a corpus = fields of one record. The public
decision takes that record as an ordinary `GIVEN` parameter and delegates, by `CONSIDER` over the
relevant field, to a private per-reading implementation.

```l4
§ `Fork register: Rule 100(a)(2) — joint calculation of investment limits`

DECLARE `net worth basis`                    -- one fork point, one enum
  IS ONE OF individualReading, jointWithSpouseReading

DECLARE Interpretation                       -- the corpus's whole fork space
  HAS `net worth basis`  IS A `net worth basis` TYPICALLY individualReading
      -- one field per fork-register entry; grows as P4 finds forks.
      -- TYPICALLY on a record field is legal L4 (doc/reference/types/
      -- typically-example.l4) and is where a settling C&DI gets cited.

GIVEN interp IS AN Interpretation
      investor IS AN Investor
GIVETH A NUMBER
DECIDE `investment limit` MEANS              -- the PUBLIC interface
  CONSIDER interp's `net worth basis`
  WHEN individualReading      THEN `investment limit individually` investor
  WHEN jointWithSpouseReading THEN `investment limit jointly` investor
```

The private implementations (`investment limit individually`, `investment limit jointly`) are
plain decisions over the facts; each carries `@ref` citations to the text that licenses its
reading, and the fork-register entry (a P4 deliverable) cites both plus the ambiguity's source.

`TYPICALLY` on each field records the favoured reading — which is where a P2 sweep finding lands:
when the SEC's C&DI settles a fork, the settling instrument is cited at the `TYPICALLY` and the
fork stays encoded (the superseded reading remains, marked, exactly as the rule-version axis
keeps a repealed regime). A court striking a reading likewise demotes, never deletes.

## 2. Why this beats the three shapes §9 listed

- **Sibling modules per interpretation** duplicate the ~95% of text the readings share; the
  copies drift (this repo's own duplicated-document incidents are the evidence), and the diamond
  import problem returns. Right only for wholesale regime changes — which is what the temporal
  rule-version axis already handles for time. **The analogy is the argument**: `Interpretation`
  is to readings what `EVAL UNDER RULES EFFECTIVE AT` is to dates — a second explicit evaluation
  axis, passed as data, not forked as files.
- **Annotation-gated variants** are invisible to the type system: nothing checks that every
  reading is handled anywhere, and every tool grows a bespoke annotation reader.
- **Parallel `DECIDE`s with no selector** leave "which one governs?" unanswerable inside the
  artifact; every consumer must know all the private names.
- **This shape is checked by machinery that already shipped**: adding a reading to the enum makes
  every delegation site's `CONSIDER` non-exhaustive, which the oracle (PR #182, merged) reports —
  at clause-matrix level too, since PR #185 merged on 2026-08-01. A fork added in P4 that
  some public interface forgot to thread is a _compile-time_ finding, not a review hope.

## 3. What each downstream leg gets, for free

| leg                        | consequence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **wizard / query planner** | `interp` fields are ordinary askable atoms. Default posture: pinned by `TYPICALLY` (the favoured reading), surfaced as an expert-mode control exactly like the law-time control (PR #172's `under the rules effective on`). An "under the X reading" dropdown is the same UI pattern on a second axis.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| **DMN**                    | Verified against the tree 2026-08-01 (adversarial pass, file:line evidence in the session record): `interp` arrives as **one** `<inputData>` whose `variable typeRef="Interpretation"` resolves to the Phase-3 itemDefinition; the enum's `allowedValues` live on the **enum's own** itemDefinition, one `typeRef` hop away (no inputData ever carries allowedValues). The delegation `CONSIDER` lowers to a real `hitPolicy="UNIQUE"` decision table whose input column is the projection `interp.net_worth_basis` — a projection scrutinee is fully supported and draws no note — with `<inputValues>` from the constructor list. Each private reading is tier-1 (one call site), so arms render as bare FEEL names with `requiredDecision` edges; the shared `investor` parameters merge to one global (`D-PARAM-AS-INPUT`, Advisory ×1) and the output entries draw `D-COMPUTEDOUTPUT` (Advisory ×2). "Each fork is a distinct decision surface" (§9 R4) falls out of existing machinery rather than needing any. |
| **ladder / TNR / MCP**     | Per-reading ladders exist because per-reading decisions exist; the MCP/service trace records _which_ reading produced an answer, because the reading arrived as an argument — auditability is structural, not logged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **tests (P6)**             | See §4.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **report (P9)**            | Divergence witnesses (§4) are the "areas of disagreement" exhibits, generated rather than hand-curated.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |

## 4. "Quickcheck over all choices"

The fork space is a finite product (enums × fields), so **exhaustive enumeration beats random
generation there**; randomness is for the _fact_ side. Two property classes, both runnable with
existing infrastructure (`#EVAL`/`#ASSERT` per combination at L4 level; hspec/QuickCheck drivers
at the Haskell level; the wizard's model-counting ROBDD can count models per reading):

1. **Agreement (the safe core):** properties asserted `∀ interp` — where all readings concur, the
   answer is interpretation-independent and the report may say so with a straight face.
2. **Divergence witnesses:** searched fact patterns where two readings disagree, minimised and
   pinned as named test cases — P6's "test cases illustrate the differences between
   interpretations," discharged mechanically. Each witness cites its fork-register entry.

A third, for orderable forks (strict vs lenient readings): **monotonicity** — the strict reading
never permits what the lenient one forbids. Violations are findings about the _encoding_, found
before a human reviewer looks (HG1 reviews the fork register with witnesses in hand).

## 4.5 One drafting rule the DMN verification exposed

**Delegation arms must pass the facts binder unchanged; per-reading transformations of the facts
belong inside the private implementation, never at the call site.** Reason: tier-1 un-lifting
renders a call site as the callee's bare FEEL name and _discards the argument expression_ in
favour of the merged global input — sound precisely because the argument was the same binder
(`D-PARAM-AS-INPUT` is classified Faithful on that reasoning). Write
``WHEN jointWithSpouseReading THEN `investment limit jointly` (investor's spouse)`` and the
transformation is silently dropped in the DMN projection until Phase 5 BKMs exist. So:
`` `investment limit jointly` investor `` at the call site, and any spouse-reaching logic inside
`investment limit jointly` itself. The fork-register review checklist (HG1) should carry this
rule.

## 5. Boundaries, stated honestly

- **v1 scope is constitutive forks** (`DECIDE`s). A reading that changes a regulative rule's
  deadline or bearer can thread `interp` through the expressions a `PARTY … MUST … WITHIN`
  mentions, but a fork in the _rule structure itself_ (different HENCE/LEST topology per reading)
  has no design here yet; if P4 finds one in Reg CF, it comes back as an R4 amendment.
- **Interpretation-dependent _types_ are out**: a fork that changes a `DECLARE`'s shape is a
  sibling-module case after all; expected to be rare, none known in Reg CF.
- **Fork-space growth is multiplicative** across independent fields; the agreement/divergence
  split (§4) is what keeps the report readable when the product grows. The fork register, not the
  enum count, is the reviewed artifact.

## 6. If ruled, what changes where

SPEC.md §9 R4 flips to ANSWERED citing this note; P4's deliverable language gains "fork register
entries map 1:1 to `Interpretation` fields"; P6 gains the two property classes; no code changes
until the demo's encode phase runs.
