# corpus(regcf): 17 CFR Part 227 — the mirror corpus, its wizard façade, and an independent de novo encoding

**What this adds**

This adds the repository's flagship legal corpus: SEC Regulation Crowdfunding (17 CFR Part 227)
formalised in L4, plus everything built around it. After this PR the tree contains an executable
statement of Reg CF that answers questions about issuer eligibility, offering limits, per-investor
investment limits, disclosure tiers, advertising, ongoing reporting and resale restrictions — and
it answers them *as at a chosen rule date*, so the same investor asking the same question gets
2016's answer, 2017's, 2021's or 2022's depending on which regime you evaluate under. A separate
wizard façade (`regcf-wizard.l4`) exposes a small citizen-facing subset through `@export`ed
functions, so the corpus can be deployed to `jl4-service` and reached over REST and MCP. And
`denovo/` carries a *second, independent* encoding of the same Part, built from a
provenance-headed ingest of the eCFR, so the two encodings can be diffed against each other
rather than each being checked only against itself.

**Why**

Reg CF is the unit of comparison for the Lexipedia-superset programme (spec
`specs/todo/lexipedia-superset/SPEC.md`; the programme is tracked upstream at
smucclaw/l4-ide#136 and answers the critique in smucclaw/l4-ide#135). The claim under test is
that a wiki page which retypes the law in prose cannot avoid drifting from it, whereas a corpus
that binds each figure once and projects everything else cannot drift that way. That claim needed
a real body of law encoded at real size before it was worth anything. Formalising the Part found
nine divergences on the mirrored page — the first of which is a substantive misstatement of law,
not a stale number (§3 of the README) — and gave the DMN, BPMN, ladder, wizard and orchestrator
work a subject with genuine legal shape to be measured against.

---

## What's in it

62 files under `jl4/examples/legal/regcf/` (plus three goldens elsewhere — see Independence),
22,687 insertions.

### The mirror corpus

`regcf.l4`, **1,436 lines, 83 `#ASSERT` lines**. Constitutive material is `DECIDE`/`MEANS`
predicates carrying the regulation's own words in the field names; the obligation tail is
regulative (`PARTY … MUST` / `SHANT` / `WITHIN` / `HENCE` / `LEST`). Every rule carries an `@ref`
CFR or Federal Register citation. The investor limit is a formula, not the 5%/10% fork the
mirrored page draws. There is a boundary assertion on each side of every numeric threshold.

Scope is deliberately the mirrored page's eight requirement groups — no more, no less, because
the page is the unit of comparison. What is *not* modelled is listed explicitly in README §1 and
§5 (funding-portal registration, bad-actor disqualification detail, Rules 205/206, and the Rule
201 itemisation beyond the financial-statement tiers).

**The rule-version axis.** Seven dated constants, four regimes each (2016-05-16 commencement /
2017-04-12 / 2021-03-15 / 2022-09-20), as newest-first `BRANCH` chains selected on
`RULES EFFECTIVE DATE`, each arm citing its Federal Register amendatory instruction in-band. Both
*shape* changes are dated too — the lesser→greater measure flip and the accredited-investor
carve-out, which did not exist before 2021. Rule dates below commencement land on a deliberate
`ASSUME` bottom, so a question about 2015 refuses loudly instead of answering wrongly.

### The wizard façade

`regcf-wizard.l4`, **939 lines, 8 `@export`ed functions, 29 `#ASSERT` lines** — the deployable
surface (`can-this-company-raise`, `investment-limit-check`, `raise-check`,
`reporting-exit-check`, `resale-check`, plus the rule-date control). It exists as a separate file
because the corpus itself cannot be deployed: its field names are the CFR's own sentences, and
#162 measured 23 of the corpus's 41 field names over the service's 60-character sanitisation cap
(longest 288), with `227.503(a)` and `227.201` both truncating to `section-227`.
`tests/regcf.schema.golden` therefore reads `No @export annotations found in file`, as intended —
the corpus stays authoritative and the façade carries the deployment surface.

### Documentation

- `README.md`, 796 lines — scope boundary, the full threshold table (figure / what it governs /
  citation / in force since / previous value), the four regimes, the nine divergences with
  sources, and an explicit list of what could not be expressed.
- `PROJECTIONS.md`, 486 lines — every artifact cut from the corpus, the exact command that
  regenerates it, its fidelity notes, and for each one *what that projection cannot say*. That
  last column is the point of the file.
- `figures/README.md`, 212 lines.

### Figures

28 committed files: **7 decisions × 4 carriers** — `.mmd` (mermaid), `.svg`, `.txt`, and
`.sentences`, a prose carrier emitting one sentence per way a rule can be satisfied. All are
output of `npm run demo:regcf`; nothing here is hand-drawn.

### The interpretive fork register

`fork-register.json`, **7 entries** — `F-501A-LEAPDAY`, `F-501A-ENDPOINT`, `F-4A6B-MEASURE`,
`F-100A1-CAP-vs-STATUTE`, `F-501A4-NEXUS`, `F-501A4-DETERMINER`, `F-501A4-SIMILAR`. These are
places where the text admits more than one reading, moved out of prose a drafter chose to write
and into structure the explainer renders whether or not anyone remembers. The file states plainly
in its own note that completeness is unfalsifiable: seven entries is not a claim that there are
seven.

### The de novo run (`denovo/`)

An independent second encoding of the same Part, produced from its own ingest rather than from
`regcf.l4`, so the two can be compared:

- **P1, the source bundle** — all 22 sections of Part 227 as eCFR XML (2026-08-03), the GovInfo
  annual edition as an independent copy, the versioner's currency and section-version records,
  and `§ 230.501` + `§ 270.3a-9` (the two provisions outside the Part its operative text depends
  on for meaning). `part227.txt` is the provenance-headed artifact the encoding reads, pinned by
  sha256, and `assemble-source.py` rebuilds it from the captured XML so the digest is reproducible
  rather than asserted.
- **P2, the external-modification sweep** — `external-modifications.json`, the record of the
  litigation and amendment searches confirming nothing binding has moved the Part since
  2023-03-01, with controls run on the same endpoints so a near-zero count reads as a finding
  rather than as a broken query.
- **P3, the encoding** — `regcf-denovo.l4`, **3,646 lines, 39 `#ASSERT` lines**, covering all 22
  sections (§§ 227.100, 201–206, 300–305, 400–404, 501–504) against the mirror corpus's
  page-scoped eight groups. Contested readings are *parameters*, not choices: one `Interpretation`
  record threads through every decision that depends on one, with paired input fields, so no fork
  is hidden inside a single fact the user supplies.
- **P4, the register and surface map** — `denovo/fork-register.json` (26 entries) and
  `surface-map.json`, which declares which decisions of the two encodings are comparable and
  which are blocked. The de novo register is deliberately kept separate from the corpus register;
  the corpus register's note says so and says why.

### Goldens

Four per `.l4` file — `.golden`, `.ep.golden`, `.nlg.golden`, `.schema.golden` — for `regcf.l4`,
`regcf-wizard.l4` and `denovo/regcf-denovo.l4`: **12 files**.

### Corpus repairs that rode along

Worth calling out because they are substantive statements of law, not tidying:

- **Rule 501(a)'s "one year" is a calendar anniversary, not 365 days.** The restricted period was
  encoded as the constant `365`, which is wrong by exactly one day for any holding spanning a 29
  February, and `365` appears nowhere in Part 227.
- **Rule 501(a)(4) decomposed into six fields.** It was one ~300-character boolean carrying the
  CFR's whole sentence, so a party had to self-assess four alternatives at once and, having
  answered no, could not say which they had ruled out.
- **A false count of law corrected in the copy a citizen reads.** 17 CFR 227.501(c) lists
  fourteen comma-separated relationships; four live sites said thirteen. Three were corrected —
  including `regcf-wizard.l4`, the only copy a citizen reads. The fourth,
  `denovo/regcf-denovo.l4`, was deliberately left alone, because it is the independent encoding
  and correcting it would contaminate the comparison.

---

## Evidence

Quoted from the source PRs and commit messages. Nothing below is re-run here.

**The corpus and its assertions**

- #139: "`l4 check`: succeeds. `jl4-test`: **1486 examples, 0 failures**, goldens generated", with
  "110 `#ASSERT`s satisfied" at that revision.
- #139, on the headline divergence: "An investor with $60,000 income and $200,000 net worth is
  limited to **$10,000** under the rule in force. Under the page's stated rule: **$3,000**. The
  page understates this investor's lawful capacity by **3.3×**."
- #172: "`jl4-test`: **1849 examples, 0 failures**"; "Corpus 70 assertions, wizard 22 assertions,
  all green under both pinned dates and the ambient harness clock"; "Corpus DMN export: 102
  decisions".
- #162: `cabal test jl4:jl4-test` **1841 examples, 0 failures**; every DMN/BPMN golden through the
  CLI with no flags, "12/14 byte-identical; the 2 XML fidelity reports differ only in the source
  filename in each citation".

**Behaviour preservation under corpus edits**

- Rule 501(a)(4) decomposition (`3f06cdc6`): "with the source-location lines filtered out, the
  diff to regcf.golden and regcf-wizard.golden is pure addition — 12 added lines, zero removed,
  zero changed values. Every one of the 74 pre-existing `#ASSERT`s still holds."
- Regeneration check (`f273d158`): "the 28 ladder files are byte-identical after
  `npm run demo:regcf`, and `cabal test jl4:jl4-test` reports 'Golden and Actual output didn't
  change' for the DMN, the dmnmd and all six BPMN goldens (**2255 examples, 0 failures**)."
  Engines before and after the decomposition: KIE 8.44.0.Final "21 case(s), 1449/1449 decision(s)
  SUCCEEDED, 1449/1449 value(s), 315/315 service output value(s) → 22 case(s), 1540/1540
  decision(s) SUCCEEDED, 1540/1540 value(s), 330/330 service output value(s)"; Camunda 8.7.6
  "69 decision(s) parsed, 21 case(s), 1449/1449 → 70 decision(s) parsed, 22 case(s), 1540/1540".
  "0 errors and 0 warnings on both, before and after. … No outcome moved."
- Field renames (#205): "diff oracle 9036/9036 agreed, 0 diverged; both engines still 1072/1072."
- Enumeration labels (#208): "inert never shadows active — 77 labels across 3 corpora, semantics
  byte-identical, engines unmoved."
- Atom ids (#210): "ladder ∩ query-plan atom ids 0/2 → 2/2 on Reg CF, 0/11 → 11/11 on Charities."
- Corpus execution (#194): "the Reg CF corpus executes — 67/67 values on KIE and Camunda, 14/14
  service outputs value-checked."
- Calendar-anniversary fix (`4fec076e`): the clamp was "MEASURED 2026-08-05 on Drools/KIE
  8.44.0.Final and Camunda 8.7.6 (zeebe-dmn), six cases each, L4 and both engines agreeing."

**The de novo run**

- P1 (`2fdc3d7f`): "The GPO edition differs from the eCFR in exactly one block over 101,803
  characters"; the annotation inventory is "ten FR documents, each resolved to a govinfo granule
  and then VERIFIED BY CONTENT", a check that caught four of the ten cites resolving to the wrong
  granule.
- P2 (`de560f55`): "Eleven recorded searches, fourteen entries, six disposition rows covering all
  ten markers of the P1 bundle's annotation inventory. `p2-sweep: PASS`, 29 rules checked."
  CourtListener returns 1 and 0 for the two queries while same-session controls return
  "527 / 885 / 1,492,372", "so the index is healthy and the near-zero count is the finding, not a
  broken query"; govinfo FR search over 2023-03-02..today returns 0 documents containing "17 CFR
  Part 227", independently agreeing with the versioner's `latest_amendment_date` of 2023-03-01.
- P3 (`8c8ec9d4`): "3,646 lines, 41 DECIDEs, 30 DECLAREs, 15 regulative rules, 242 @refs, 10
  @export entry points, 39 `#ASSERT`s green under both 2026-08-05 and the pipeline's fixed-now."
- P4 (`6711f373`): 26 register entries; "`go.sh --only p4-forks` PASSes, 18 rules checked"; the
  surface map "declares four runnable pairs and eight blocked ones".
- The two-encoding diff earning its keep (`4fec076e`): the leap-day defect was "found by the §8
  diff oracle, not by either side's tests: while `Transfer` carried only an elapsed day count, the
  leap case was INEXPRESSIBLE, so neither this corpus's assertions nor the de novo encoding's
  could reach it. Only comparing the two encodings against each other did."
- Surface-map repair (`024ffe46`): after re-keying, "the oracle now runs 80/80 agreed, 0
  diverged."

**Measured here, for this split** (`git show` / `wc -l` / `grep -c` on `origin/unstable`): the
file, line and assertion counts in *What's in it*. Note one live drift: #203 corrected
`PROJECTIONS.md` to "1,236 lines, 70 assertions" and that was true when written, but `regcf.l4` is
now 1,436 lines with 83 `#ASSERT` lines — the doc is stale again by exactly the mechanism it
documents, and a reviewer may reasonably ask for it to be re-measured before merge.

---

## Independence

This PR is **not** standalone, and the dependencies run one way — it is the *input* to the
projection themes, not their output.

**It needs, to compile at all:**

- `RULES EFFECTIVE DATE` / `EVAL UNDER RULES EFFECTIVE AT`, dated `BRANCH` chains, `DATE`
  literals, `TIMEZONE`, `MAYBE`, and the `@ref` / `@desc` / `@export` annotations — owned by
  **lang-syntax-typecheck** and **lang-eval-ledger**.
- `IMPORT prelude` and `IMPORT daydate`, including `daydate`'s Calendar Arithmetic section
  (`add months` / `add years`, with the month-end clamp) that the 501(a) anniversary fix moved in
  from `actus-schedule` — owned by **lang-imports-stdlib**.

Without those, `regcf.l4` does not typecheck and `jl4-test` goes red.

**Its goldens encode other themes' behaviour.** The `.ep.golden` files are byte-for-byte copies of
their sources and are safe. `tests/regcf.golden` is not: commit `07a95495` in **lang-printer**
(#214) rewrote 161 of its lines when `prettyLayout` was repaired, and `f39cea88` re-derived it
again when a rebase moved every line reference. `.nlg.golden` output is shaped by the clitic and
enumeration-label work in #205 / #208. If any of those land after this PR, these goldens need
re-blessing — that is expected churn, not a defect.

**Three files in this manifest are not Reg CF files at all**, and they carry *code* changes owned
elsewhere:

- `jl4/examples/lsp/hover/tests/desc-hover.hover.golden` — the `@desc` leading-space trim from
  #162 (`L4.Syntax.getDesc`), owned by **lsp**.
- `jl4/examples/ok/tests/export-explicit-default.schema.golden` and
  `export-no-explicit-default.schema.golden` — the same trim plus a JSON-Schema change
  (`"$ref": "#/$defs/NUMBER"` → inline `"type": "number"`), owned by **service-cli**.

They are routed here only because the Reg CF work is what forced them. **If lsp and service-cli
land separately, these three should travel with their code, not with this PR.**

**What it does not need.** Nothing here depends on **dmn-export**, **bpmn-export**, **ladder-viz**
or **go-pipeline** to compile or to pass its own four goldens. Their Reg CF artifacts
(`jl4/examples/dmn/expected/regcf-corpus.*`, the three Reg CF BPMN goldens, the ladder drift test
`ts-shared/ladder-svg/test/regcf-figures.test.ts`) live in those themes and will need
re-derivation whenever the corpus text moves — which is the intended relationship, not a
circularity. Two smaller couplings are worth naming honestly: `figures/*` are committed *output*
of `npm run demo:regcf` and are inert here, and `denovo/surface-map.json` is *read* by the
denovo-diff oracle in **go-pipeline**, so it is data this PR ships for a consumer that lands
elsewhere. The `fork-register.json` files are validated against a schema owned outside this
theme.

**`denovo/` is the most self-contained part** — an ingest, an encoding, a register, a surface map
and four goldens, with no code of its own.

## Risk if rejected

Drop this and there is no Reg CF: the DMN, BPMN, ladder, wizard, service-deployment and `go`
orchestrator themes all take this corpus as their subject, so their expected artifacts have
nothing to regenerate from and a large fraction of the branch's measured claims become
unreproducible. Nothing in the compiler or the language breaks — this is data and prose — but the
Lexipedia-superset programme loses the exhibit its entire argument rests on, and the two-encoding
diff that caught the 501(a) leap-day defect goes with it.

## Provenance

Folded from these `unstable` PRs. Several span other themes; only the Reg CF corpus portion of
each is taken here.

- **#139** — `corpus(regcf): mirror SEC Regulation Crowdfunding (17 CFR Part 227) in L4`
- **#162** — `feat(regcf): cut BPMN from the corpus itself; triage every projection finding`
- **#172** — `feat(regcf): the rule-version axis — C1 complete, temporally closed, OpenFisca-informed`
- **#178** — `feat(dmn): law time on a date axis — rule-date input, UNIQUE interval tables, D-RULEDATE`
- **#180** — `feat(dmn): hydration for computed fields + MAYBE→null (R8-d′) + isJust recognition`
- **#193** — `feat(go): the "SEC Regulation Crowdfunding: go" orchestrator — milestone G1`
- **#194** — `dmn(R12+R13): the Reg CF corpus executes — 67/67 values on KIE and Camunda, 14/14 service outputs value-checked`
- **#203** — `docs(regcf): repair two measured drifts — 992→1,236 lines, 55→70 assertions`
- **#205** — `refactor(regcf): drop the redundant leading "is " from 11 field names`
- **#206** — `fix(dmn): three exporter defects closed with failing negative controls (#936, #933, #937); +4 regcf seeds`
- **#208** — `Enumeration labels: inert never shadows active — 77 labels across 3 corpora`
- **#210** — `fix(atomid): ladder ∩ query-plan atom ids 0/2 → 2/2 on Reg CF, 0/11 → 11/11 on Charities`
- **#214** — `fix(print): make prettyLayout round-trip, and stop it silently changing the answer`
- **#224** — `The explainer stage, a BPMN renderer, the grouping tutorial, and the de novo Reg CF run`
