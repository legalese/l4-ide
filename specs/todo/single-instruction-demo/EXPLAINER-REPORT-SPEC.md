# The Explainer Report — a lay-and-encoding companion to the conversion report

_Status (2026-08-03): **BUILT at v0**, on branch `mengwong/go-explainer`. What exists in the
tree: the stage `etc/go/phases/p9-explain.sh`, declared in `G1_STAGES` and gated by HG1; the
renderer `etc/go/report/render-explainer.mjs` over `etc/go/report/explainer-template.md`; the
supporting libraries `etc/go/lib/narrative.mjs` (provenance, drift, the citation checker, the
lint), `etc/go/lib/dmn-tables.mjs` and `etc/go/report/md-lite.mjs`; and the Reg CF narrative at
`etc/go/subjects/regcf/explainer/` — twenty-one parts, a manifest, and a provenance record._

_**What is NOT built, named rather than implied.** (1) **E17's signature verification.** There is
no `etc/go/lib/narrative-verify.sh` and no `reviews/` directory; the provenance record carries a
review state and the renderer derives `stale` from moved digests, but nothing checks a signature,
so a hand-written `"state": "reviewed"` would be believed. No section claims review today, so the
document is honest in practice and the mechanism is not yet closed. (2) **E14's
diagram-interchange serializer**, deferred by this spec to v1 (§8.4). (3) The g2 declaration
(§3.7), deliberately. Everything else below describes behaviour measured against the tree._

_**First proved end to end on 2026-08-03.** A real `g1` run of subject `regcf` —
`2026-08-03-3f45e62b-004`, HG1 waived on the record, verdict `COMPLETE` — rendered the document from
its own journal: 21 narrative sections, 45 citations with 0 unchecked and 0 unresolved, 0 deposit
findings, all 8 spine slots present, 1 slot rendered `ABSENT` with its reason, 9 figures inlined
(6 ladder + 3 state machines). `p9-explain` reports `DEGRADED`, which is the correct state while no
signer is enrolled. Four reader-visible defects were found by looking at the rendered HTML rather
than at the renderer, and are fixed: a nested code-span-inside-link left two NUL bytes in the
anchor text (§7.2), three inlined GraphViz pictures collided on `graph0`/`node1`/`edge1` (§8.2), a
narrative line with nested backticks drew its backticks as text (§7.2), and the deployment
subsection printed a tool COUNT under the label "Tools the deployment reported" (§9)._

_**One deviation from the text below**, recorded where it was made rather than left to be
discovered: §6.2's "verbatim" check compares the quotation and the cited window with leading `--`
comment markers dropped and whitespace runs collapsed, on both sides. A sentence in the corpus is
usually a run of comment lines, so a byte-literal check could only ever quote a fragment shorter
than a line. "Verbatim" therefore means "these words, in this order, in the cited window", not
"these bytes", and `etc/go/lib/narrative.mjs` says so at the function._

---

### Adversarial review, 2026-08-03 — what it found and what is still true

_Three reviewers attacked the v0 build on three axes: the pipeline invariants, the licensing of
every claim in the shipped narrative, and the document as a lay reader meets it. Everything below
is the state of the tree after the repairs, re-proved by run `2026-08-03-fb0d33bc-001` (`g1`,
subject `regcf`, HG1 waived on the record, verdict `COMPLETE`, `verify --gates` = 55 recorded / 55
still hash as recorded). That run rendered **87 citations, 0 unchecked, 0 unresolved, 0 deposit
findings**, up from 45/0/0/0, and every non-`PASS` receipt's reason now reaches the audit report._

**Two claims this spec used to make that were false, and are now repaired in code:**

1. **"P9 is untouched" was true of the files and false of the report.** `render-report.mjs`
   narrates `p7-*` by filter and every other stage by name; `p9-explain` had no site, and it is
   `DEGRADED` by construction while any narrative section is unreviewed — which is its normal
   state. So `report.md` printed, under its own verdict, "every non-PASS receipt carries a reason
   that appears below", and one did not. Measured on run `2026-08-03-3f45e62b-004`: five of six.
   The fix adds a `## Every other stage that reported` section computed **by subtraction** from a
   named set, so a future stage lands there by default rather than vanishing —
   `render-report.mjs`, `report/template.md` and `p9-report.sh`'s heading list each moved by a few
   lines. **D2's invariant is what survives untouched, and it was re-proved**: a typed number
   appended to either template still exits 4 (`TEMPLATE DEFECT`), and the structural check still
   reports every required section present. `selftest.mjs` gained the general assertion whose
   absence allowed this — every non-`PASS` reason reaches the report, including a stage no section
   narrates — replacing a hard-coded five-stage list that could only ever confirm what somebody
   had already thought of.

2. **HG1 did not cover the narrative it gates.** `p9-explain` is HG1-gated because it publishes
   prose, but the gate binds to `corpus_digest`, which covered the two L4 modules and nothing else.
   Measured: waive HG1, edit `explainer/orientation.md`, re-run `--only p9-explain` with no new
   grant — the gate stayed open and the replaced prose went into the document; `--bless` then
   cleared the drift banner too. `go.sh` now folds the whole deposit into that digest at `g1`
   (25 files, printed by `go.sh plan`), so editing a narrative file — or blessing one, which
   rewrites `provenance.json` — re-opens the gate. `selftest.mjs` asserts it against the driver.

**Repairs to what the document said about itself.** It claimed every statement about the law
carried a link while its own table recorded five sections at zero citations; the coverage
paragraph is now computed from that table and names the sections that carry none (two remain, both
framing prose: `pictures.intro` and `sweep`). It printed `run verdict COMPLETE` with no gates row
over a journal whose HG1 was waived; the gates now ride in the header. The attested copy printed
`INCOMPLETE` while the derived copy printed `COMPLETE` over the same run, because a render taken
before `run_end` recomputed a verdict; it now declines to state one, so neither copy is wrong and
the two differ only in a record count and that row. The review banner described a signature
mechanism in the present tense; it now says the gap is a missing **verifier**, not a missing key.
The markdown carrier emitted six repo-relative image links from a document under `TMPDIR` — six
broken links, measured — and now names each figure's file instead, with the header saying only the
HTML carries pictures.

**Repairs to the narrative itself**, each of which was an unlicensed or wrong claim: the call to
action's first command started nothing (`./dev-start.sh` prints instructions; `service-only` runs
the service), its poll used `--fail` against a route whose normal first answer is 404, it
enumerated five tool kinds against six exports, and it reused a deployment id that collides with a
stale one in the default store. Tool names now ride on the `p7-mcp` receipt as a metric, so the
document prints the measured list and the prose enumerates nothing. Three dead acts were reported
as two; a 2022 enumeration of five moved figures was six; a sentence read "by a different
instruction" where its own cited line reads "by the same instruction"; the accredited-investor
carve-out was stated undated and uncited; the reporting-exit fidelity quotation stopped
mid-sentence, before the half that says the exporter chose a different lowering rather than
refusing.

**One leg was reporting a stale absence as a live finding.** `p7-bpmn` said the BPMN-to-DMN
`businessRuleTask` wiring was "NOT BUILT and has no checker", citing `PROCESS-TRACK.md` §8.3 —
which now reads "BUILT 2026-08-02". The goldens carry two `businessRuleTask` each and
`etc/check-bpmn-dmn-refs.mjs` is the checker CI already runs. The leg now runs it against the
committed DMN and reports `PASS`; the explainer was republishing the stale text verbatim to a lay
reader beside a table row showing the wiring present.

_**Still not built, and not fixed by this pass.** (1) **E17's signature verification** — unchanged
and now stated plainly in the document itself rather than described as a missing signer.
(2) **E14's diagram-interchange serializer** (§8.4). (3) The **derived copy of the explainer is
attested by nothing** — only the preliminary copy under `artifacts/` carries a hash. The audit
report has the same property; making the reader-facing copy the receipted one needs a journal
record written after `run_end`, which nothing in the ledger can do today. (4) **Citations render
as coordinates, not links** — a reader cannot click through to a source line. (5) The
**law thread is shorter than the encoding thread** — measured 1.8:1 by word count before this
pass, narrowed by lengthening the two shortest law sections, not eliminated. (6) The
**intermediary-obligations requirement group still has no section of its own**; the document now
says so in three places instead of dropping it silently._

**One-line summary.** The conversion report is an **audit** document: it accounts for what a run
did, refuses to print a number that has no journal row, and is unreadable to anyone who is not
already inside the project. The explainer is its **reader-facing sibling**: it explains
Regulation Crowdfunding to a lay reader _and_, interleaved with that, explains what happened when
somebody tried to make Regulation Crowdfunding executable. It is a separate artifact rendered from
the same journal by a separate stage, it may make no claim the audit report cannot support, and —
the whole design problem — it must carry prose and figures and numbers without becoming a second
place where numbers are typed by hand.

**Cross-references.** R-numbers here are the **E-series**, scoped to this document; cite them
elsewhere as `EXP-En`. The pipeline's own series is `SI-Rn`
([SPEC.md](./SPEC.md) §9); the DMN exporter's is `R-n`
([DMN-EXPORT-PROGRAM-MODEL-SPEC.md](../DMN-EXPORT-PROGRAM-MODEL-SPEC.md) §0). This document owns
the explainer's decisions and overrides none of theirs.

---

## 0. Ruling register

| ruling                                                                             | state                                          | detail |
| ---------------------------------------------------------------------------------- | ---------------------------------------------- | ------ |
| **E1** — narrative is drafted, checked in, reviewed                                | **ANSWERED 2026-08-03 (Meng)** — D1            | §5     |
| **E2** — separate sibling artifact; P9 untouched                                   | **ANSWERED 2026-08-03 (Meng)** — D2            | §2     |
| **E3** — Reg CF first; subject-generic; BNA out of scope                           | **ANSWERED 2026-08-03 (Meng)** — D3            | §4.1   |
| **E4** — a declared, HG1-gated stage `p9-explain`, g1 only                         | **ANSWERED 2026-08-03 (this spec)**            | §3     |
| **E5** — duplicate the journal fold; do not refactor `render-report.mjs`           | **ANSWERED 2026-08-03 (this spec)**            | §3.5   |
| **E6** — every figure is placeholder-resolved or citation-checked                  | **ANSWERED 2026-08-03 (this spec)**            | §6.2   |
| **E7** — no number may be sourced from `README.md` or `PROJECTIONS.md` prose       | **ANSWERED 2026-08-03 (this spec)**            | §6.4   |
| **E8** — narrative prose may not carry run-status vocabulary                       | **ANSWERED 2026-08-03 (this spec)**            | §6.5   |
| **E9** — for the explainer the HTML is the document and the markdown is the record | **ANSWERED 2026-08-03 (this spec)**            | §7.1   |
| **E10** — a closed markdown subset, lint-enforced, zero dependencies               | **ANSWERED 2026-08-03 (this spec)**            | §7.2   |
| **E11** — ladder SVGs inline verbatim: unmodified, untrimmed, boxed                | **ANSWERED 2026-08-03 (this spec)**            | §8.1   |
| **E12** — the LTS picture is environment-conditional; no committed DOT renders     | **ANSWERED 2026-08-03 (this spec)**            | §8.2   |
| **E13** — DMN tables are extracted from the emitted XML; dmnmd is a cross-check    | **ANSWERED 2026-08-03 (this spec)**            | §8.3   |
| **E14** — the BPMN/DMN diagram-interchange serializer is deferred to v1, costed    | **ANSWERED 2026-08-03 (this spec)**            | §8.4   |
| **E15** — the call to action is stand-it-up-yourself; no live-deployment claim     | **ANSWERED 2026-08-03 (this spec)**            | §9     |
| **E16** — the cross-link is one-way: explainer → report, never the reverse         | **ANSWERED 2026-08-03 (this spec)**            | §2.3   |
| **E17** — per-section narrative signatures; the run gate is not extended           | **ANSWERED 2026-08-03 (this spec)**            | §5.5   |
| **E18** — report versioning                                                        | **OPEN**, inherits `SI-R7`                     | §13    |
| **E19** — where the DI serializer belongs                                          | **OPEN**                                       | §13    |
| **E20** — narrative generated rather than drafted                                  | **OPEN**, D1 rules it drafted for now          | §13    |
| **E21** — the report has THREE jobs: the law, the encoding, and L4 itself          | **ANSWERED 2026-08-05 (Meng)**                 | §14.1  |
| **E22** — the SPINE: one interaction walked in depth; the road not taken is listed | **ANSWERED 2026-08-05 (Meng)**                 | §14.2  |
| **E23** — verbosity permitted; repetition across reports expected (reverses DRY)   | **ANSWERED 2026-08-05 (Meng)**                 | §14.3  |
| **E24** — the spine walked twice, pre-L4 and L4, through personas                  | **ANSWERED 2026-08-05 (Meng)**                 | §14.4  |
| **E25** — the exhibits; wizard screenshot capture is NEW ENGINEERING, not built    | **ANSWERED 2026-08-05 (Meng)**                 | §14.5  |
| **E26** — the fabrication boundary: invented material is structurally distinct     | **ANSWERED 2026-08-05**                        | §14.6  |
| **E27** — register: technical and CNL material in relatively simple language       | **ANSWERED 2026-08-05 (Meng)**                 | §14.7  |
| **E28** — interpretive forks get a spine slot (S9), fed by `fork-register.json`    | **ANSWERED 2026-08-05**; S9 **BUILT** same day | §14.8  |
| **E29** — reading order: pre-L4 context, then applications, then encoding+language | **ANSWERED 2026-08-05 (Meng)**; NOT BUILT      | §14.9  |
| **E30** — `S10` process + glossary; subject-independent text INCLUDED, not linked  | **ANSWERED 2026-08-05 (Meng)**; NOT BUILT      | §14.10 |

**Evidence legend.** **[M]** = I ran it or read it out of the tree at `5f79ff64` while writing this
spec. **[G]** = taken from the ground-truth research passes that preceded this document, and cited
to a file:line I did not personally re-execute. Everything else is design, and is written in the
conditional.

---

## 1. Why a second document, and what its second job is

### 1.1 The audit report cannot do this job, by construction

`etc/go/report/template.md` is **forbidden to contain a digit-run of length two or more** outside a
short allowlist, and `render-report.mjs:87` refuses to render a template that does **[M]**. That
rule exists for a stated reason — the header of the template records that `PROJECTIONS.md` once
published a fidelity heading, a per-code table and two line counts that its own artifacts
contradicted **[M]** — and it is enforced in CI (`.github/workflows/pr-checks.yml:268-281`, which
renders against an empty run directory and asserts _both_ that no `TEMPLATE DEFECT` fires _and_
that the renderer got as far as `no run_begin`, proving the check was reached) **[M]**.

A document that may not contain "$5,000,000", "six exclusion limbs", "one year", or "2016-05-16"
cannot explain Regulation Crowdfunding. That is not a defect in the audit report. It is what makes
the audit report worth reading. So the explainer is a **different document with a different
discipline for the same purpose** (§6), not a relaxation of the report's.

### 1.2 The two jobs, and why they interleave

Meng's framing, 2026-08-03: the report must explain **the law** and **the L4 treatment of the
formalization**, "not two documents, and not two bolted-together halves — the two threads
interleave."

The second thread is the part no other legal explainer can produce. A reader should come away
understanding what Reg CF requires **and** what happened when somebody tried to make it
executable: where the prose was vague and the code could not be, what the type system refused,
where an ambiguity had to fork into competing readings, what each projection makes visible that
the others hide, and what the encoding honestly failed to capture.

Two consequences bind the design:

1. **Interleaving is a data-model property, not a writing instruction.** §4.2 gives every body
   section an optional `encoding` companion. `encoding: null` is legal and renders nothing —
   which operationalises "where there is not an honest observation, say nothing rather than
   padding". A section cannot be padded into existence by a drafter who feels a gap; it can only
   be filled by a claim that carries a citation.
2. **The encoding thread is held to the _same_ discipline as the law thread.** "The type system
   caught a subtle bug" with no citation is exactly the sentence this project exists to make
   impossible. §6.2's citation grammar applies to both threads without exception.

### 1.3 The material exists and is unusually good

The Reg CF corpus already carries, in the tree, the raw material for the second thread: the
`WITHIN`-on-a-`SHANT` bug that made a prohibition sunset at day 365 **[G:** `regcf.l4:616-628` **]**;
the totality checker refusing to certify the reporting spine **[G:**
`jl4/examples/dmn/expected/regcf-corpus.fidelity.txt:323-325` **]**; the `NUMBER` → `MAYBE NUMBER`
change that made a wrong answer unrepresentable after a human, not a type, found it **[G]**; the
half-open interval the CFR does not decide **[G:** `regcf.l4:718-723` **]**; the fifteen
`D-RULEDATE-UNBOUND` scenarios DMN cannot express **[G]**; the BPMN `F1` finding that a prohibition
has no shape **[G]**. None of that is invented for the explainer. All of it is quotable, and §6.2
requires it be quoted rather than paraphrased.

---

## 2. The artifact contract

### 2.1 Filenames and where they are written

Exactly two files, named as siblings of the audit report's two:

| file             | written to                       | by                                      | attested?                                   |
| ---------------- | -------------------------------- | --------------------------------------- | ------------------------------------------- |
| `explainer.md`   | `$GO_OUT` (`$GO_RUN/artifacts/`) | `p9-explain.sh` (preliminary render)    | **yes** — hashed on the stage's own receipt |
| `explainer.html` | `$GO_OUT`                        | `p9-explain.sh` (preliminary render)    | **yes**                                     |
| `explainer.md`   | `$GO_RUN`                        | `go.sh`, after `run_end` (final render) | **no** — derived, re-derivable by anyone    |
| `explainer.html` | `$GO_RUN`                        | `go.sh`, after `run_end`                | **no**                                      |

This is the audit report's pattern, copied deliberately and for its stated reasons
(`p9-report.sh:31-45` **[M]**): the preliminary render proves the renderer works and that every
section this spec requires is present, while the final render carries the run's own verdict,
which does not exist until `run_end`. The final render is not attested **because** anyone can
re-run the renderer over the journal and get the same bytes, which is a stronger guarantee than a
hash of a file somebody could have replaced.

**Nothing is ever written into the tree.** The narrative source files live in the tree (§5) and
are read-only to the stage. The rendered explainer lives only in a run directory. Copying it
somewhere a third party can see it is publication, which is P10, which is HG2's.

**Never write into `$GO_OUT` after the receipt has hashed it.** `verify-run.mjs` re-hashes every
artifact a receipt names and files a `CHANGED` finding, and `go.sh` flips the verify exit to 1
**[G]**. That is precisely why the final render targets `$RUN`.

### 2.1a Amendment 2026-08-03 — where D2's "P9 untouched" actually bit

D2 says the audit report's strict no-typed-numbers invariant must survive completely untouched, and
it does — re-proved by appending a typed number to each template and watching both renderers exit 4
with `TEMPLATE DEFECT`, and by re-running `p9-report.sh`'s own section-presence check.

Three files in the report's closure nevertheless moved, deliberately, and the reason is that
leaving them alone would have made `report.md` print a false sentence about itself on every run.
The gloss under a `COMPLETE` verdict promises "every non-PASS receipt carries a reason that appears
below"; `render-report.mjs` narrates `p7-*` by filter and everything else by hard-wired name, so a
stage outside both had no site. That hole was latent while `p9-report` was the only such stage
(it emits `PASS` or a hard failure and nothing else) and became live the moment `p9-explain`
existed, because `p9-explain` is `DEGRADED` whenever any narrative section is unreviewed, which is
its normal state.

The repair is a `## Every other stage that reported` section whose membership is computed by
**subtraction** from a named set, in `render-report.mjs`, plus the heading in `report/template.md`
and in `p9-report.sh`'s required list. Reading "P9 untouched" as "no byte of these files may move"
would have preserved the letter of D2 by publishing a falsehood, which is the trade this whole
document exists to refuse.

### 2.2 What is _not_ produced

No sidecar figure directory. Figures are either inlined into `explainer.html` (§8.1) or referenced
by repo-relative path from `explainer.md`. A run directory does not accumulate copies of committed
SVGs, because a copy is a thing that can drift from its original with nothing to catch it.

### 2.3 E16 — the cross-link is one-way

#### The ruling

`explainer.md` links to `report.md` — in its header, and again wherever it cites a run fact.
`report.md` **does not link to `explainer.md`**.

Two reasons, both mechanical.

1. `report.md`'s content is entirely placeholder-resolved from 24 keys defined at
   `render-report.mjs:449` **[M]**, and an unresolved placeholder is exit 4 **[M:**
   `render-report.mjs:485` **]**. A link to the explainer would need a 25th key, which means
   editing `render-report.mjs` — the file D2 protects.
2. More importantly: the explainer may **not exist** for a given run. It can `SKIP` (a subject with
   no narrative), it can be absent from `declared_stages` on an older journal, and it is
   HG1-gated so it can refuse. A report that links to a document that was never produced is a
   report making a claim about the run that the journal does not support — the exact failure this
   whole apparatus exists to prevent.

#### The case against this ruling, honestly

A reader who lands on `report.md` will not discover the explainer. That is a real cost, and the
mitigation is weak: `go.sh` prints `go: report $RUN/report.md` at the end of a run **[M:**
`go.sh:789` **]** and would gain a matching `go: explainer $RUN/explainer.md` line, printed only
when the file exists. That is a terminal line, not a document link, and it does not survive the
report being copied elsewhere.

#### What this ruling does not decide

It does not decide what happens at **publication** (P10). A published pair may well want mutual
links, because at that point both documents exist and are immutable. That is P10's problem and
`SI-R1`'s layout question, not this document's.

---

## 3. E4 — the wiring: a declared, gated stage

### 3.1 The ruling

The explainer is a **new phase script `etc/go/phases/p9-explain.sh`**, declared in `G1_STAGES`
immediately after `p9-report`, added to `gated_by_HG1` on the adjacent line, declaring **no**
`--inputs`, and **not declared at g2**.

```sh
# etc/go/go.sh, replacing the current :234-235
G1_STAGES+=(p9-report p9-explain)
gated_by_HG1="$gated_by_HG1 p9-report p9-explain"
```

The two appends stay adjacent so they cannot drift **[M:** they are adjacent today at
`go.sh:234-235` **]**.

### 3.2 Why declared rather than a side effect of `p9-report`

A stage that is declared appears in `run_begin`'s `declared_stages`, and `milestoneVerdict`
reports `INCOMPLETE` for any declared stage with no receipt **[G:** `verdict.mjs:177` **]**. That is
the property we want: a run that produced no explainer says so in its verdict. Folding the render
into `p9-report.sh` would make the explainer's absence invisible, and would put a second, riskier
render inside the script whose `PASS` currently means something narrow and well-defined.

It also keeps D2 clean: `render-report.mjs` and `template.md` are not opened by this build.

### 3.3 Why HG1-gated

`SPEC.md` §7.3: HG1 blocks P6 onward. The explainer publishes reviewed narrative; an ungated
explainer stage would render HG1-unreviewed prose and **every downstream honesty check would report
clean**, because the gate check is `[[ " $gated_by_HG1 " == *" $s "* ]]` with an empty default
**[G:** `go.sh:580-607` **]**, `verify-run.mjs` reads the gated set out of `run_begin` so it would
agree with the omission **[G]**, and the report's Gates table prints gate rows, not gate coverage
**[G]**.

There is **no assertion anywhere in the tree** that every declared stage after `p6-tests` is in
`gated_by_HG1` **[G]**. §11 adds one.

### 3.4 Why no `--inputs`

Same argument as `p9-report.sh:16-28`, verbatim in force **[M]**: the explainer is a function of
the journal, and the journal grows while the stage runs. A stage cannot digest its own future.
Declaring an inputs set that omitted the journal would let a stale explainer render as `replayed`
over a journal that had since changed.

The narrative files are _also_ inputs, and they are _not_ declared either, for the same reason:
declaring them and not the journal is the under-declared-digest hazard in its most damaging form.
Their digests are instead recorded as **receipt metrics** (§5.4), which is where a claim about
content belongs.

**The cost, named.** `p9-explain` becomes a **second** never-replaying stage, and two selftest
assertions are written against there being exactly one (`selftest.mjs:877-880` asserts
`executed.length === 1 && executed[0] === "p9-report"`; `:881-884` asserts
`secondPass.length - 1`) **[M]**. §11 rewrites both as set comparisons against a named
never-replaying set, rather than bumping the constant to 2 — bumping a magic number is how the
next stage breaks it again.

A second cost, read rather than run **[G]**: `gate-payload.mjs:38-40` filters only on
`!r.replayed_from`, so every re-execution of a never-replaying stage appends a row to the HG1
payload. In practice this is masked because `go.sh` skips `gate-verify.sh` entirely while the
grant state is `open`, so the payload is rebuilt only when the corpus digest has moved — at which
point refusal is correct anyway. **I did not run this**; it is a reading of three sites and it
should be exercised by §11's harness before the build lands.

### 3.5 E5 — duplicate the fold; do not refactor `render-report.mjs`

#### The ruling

`p9-explain`'s renderer **copies** the journal fold rather than importing a lifted helper.
Specifically it re-implements, byte-for-behaviour:

- `begin` = **first** `run_begin`; `end` = **last** `run_end`;
- `stageEnds` = **latest row per stage wins**, via the `new Map(rows.map(r => [r.stage, r]))`
  idiom (`render-report.mjs:106` **[M]**, matched by `verify-run.mjs:48` **[G]**);
- `run.verdict` = `end?.verdict ?? milestoneVerdict(...).verdict` — the **recorded** verdict wins
  over a recomputation **[G:** `render-report.mjs:464` **]**.

It **imports** the things that are already real ES modules: `etc/go/lib/ledger.mjs` (`verify`,
`read`, `sha256File`, `sha256Text`, `digestSet`) and `etc/go/lib/verdict.mjs` (`STATUSES`,
`milestoneVerdict`) **[G]**. It never calls `ledger.append`.

#### Why not the obvious refactor

Lifting the fold into `etc/go/lib/journal-fold.mjs` and importing it from both is the better
engineering and is **refused here** for two measured reasons:

1. D2 says P9's invariant survives completely untouched, and the cheapest way to keep a promise
   about a file is not to edit it.
2. `selftest.mjs:1014-1026` asserts things about `render-report.mjs`'s **source text** — it must
   contain the literal `"journal.ndjson"` and must not match `/readFileSync\((?!TEMPLATE)[^)]*fidelity/`
   **[G]**. A refactor that moved path construction into a library could remove the first literal
   and turn that assertion red for a reason unrelated to anything it is testing.

#### The case against this ruling, honestly

Duplicated logic drifts, and this particular logic drifting is _exactly_ the failure the explainer
exists to avoid: two documents disagreeing about one run. The mitigation is not "be careful", it is
an oracle — §11's `folds-agree` selftest runs both renderers over a fixture journal that contains a
resumed run, a replayed receipt, a `BROKEN` row and a post-`run_end` `stage_end`, and asserts the
derived verdict and the per-stage status map are identical. If that test cannot be written, this
ruling is wrong and the refactor should happen instead.

#### What this ruling does not decide

Whether a later PR, not bound by D2, should do the lift. It probably should. It would then delete
the duplication and keep the equality test as a regression.

### 3.6 What else must be updated, and what must not

| site                                              | action                                                                                    | why                                                                                        |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `go.sh:226-235`                                   | add stage + gate                                                                          | §3.1                                                                                       |
| `go.sh:240` (`g2` override)                       | **no change**                                                                             | not declared at g2                                                                         |
| `cmd_plan --milestone g1` (`go.sh:321-347`)       | **no change**                                                                             | derives its table from the two lists **[G]**                                               |
| `cmd_plan_g2` (`go.sh:270-319`)                   | **no change**                                                                             | hand-written, and the stage is not declared at g2 **[G]**                                  |
| `verify-run.mjs`                                  | **no change**                                                                             | reads `declared_stages`/`gated_stages` from the journal; no stage id is hard-coded **[G]** |
| `selftest.mjs:877-884`                            | rewrite as set comparison                                                                 | §3.4                                                                                       |
| `.github/workflows/pr-checks.yml`                 | add a digit check for the explainer template; add a grep asserting `plan` names the stage | §11                                                                                        |
| `.claude/skills/running-the-l4-pipeline/SKILL.md` | update the worked-example run output                                                      | it lists stage rows and nothing machine-checks it **[G]**                                  |
| `etc/go/README.md`                                | describe the artifact pair                                                                | prettier runs over it                                                                      |
| `etc/go/lib/subject.mjs`                          | add `explainer` to the top-level key allowlist + a validation branch                      | §5.2                                                                                       |

`etc/go/report/render-report.mjs` and `etc/go/report/template.md`: **not opened**.

### 3.7 Why not declared at g2

At g2 the pipeline validates _deposits_ — a source bundle, a modification register, a fork
register, a de novo module. No subject has any of those on a branch today
(`subject.json`'s own `_comment` says so **[M]**), so a g2 explainer would have a de novo encoding
to describe and no de novo encoding to describe it from.

**The case against, honestly:** the g2 story — "a machine re-derived this statute from source and
here is where it disagreed with the humans" — is the single most compelling thing this pipeline
will ever have to explain, and it is a shame to leave the explainer out of it. **What would change
this ruling:** the first subject with a deposited de novo module and a populated fork register. At
that point the stage joins `G2_STAGES`, gains a row in the hand-written `cmd_plan_g2` table, gains
a name in `selftest.mjs:1993-2005`, and joins the g2 `gated_by_HG1` override at `go.sh:240`.

---

## 4. The document: spine, sections, and what licenses each

### 4.1 E3 — the spine is fixed; the body is per-subject

#### The ruling

This spec fixes a **nine-slot spine** — eight as originally ruled, plus **S9** added by E28 on
2026-08-05 and not yet implemented (see the note under the table). It does **not** fix the body
sections. The body is
declared per subject in `etc/go/subjects/<id>/explainer/manifest.json`, so Reg CF's thirteen
sections and the BNA's eventual N are the same machinery with different manifests.

A spine slot may be **declined** by the manifest, and a declined slot renders its decline reason —
it is never silently dropped. That is `p9-report.sh`'s rule for the audit report's nine headings,
carried over: _"a report that quietly drops a section it has nothing to say about is the failure
this stage exists to prevent"_ **[M:** `p9-report.sh:61-62` **]**.

#### The spine

| slot   | heading                    | what it is                                                                       |
| ------ | -------------------------- | -------------------------------------------------------------------------------- |
| **S1** | Orientation                | what this body of law is for, who it binds, what the bargain is                  |
| **S2** | The rules                  | the body — N subject-declared sections, each with an optional encoding companion |
| **S3** | Pictures                   | ladder, LTS, BPMN, DMN — one subsection per projection that ran                  |
| **S4** | Time                       | which rules were in force when, and what it took to say so                       |
| **S5** | Limits                     | what the encoding could not capture                                              |
| **S6** | What was never searched    | the external-modification hole, stated in the audit report's own words           |
| **S7** | Use it                     | the call to action                                                               |
| **S8** | How to check this document | provenance, review states, and the re-derivation command                         |
| **S9** | Where the law is unsettled | interpretive forks: both readings, the reading taken, and why (E28, §14.8)       |

**S9 was RULED and BUILT on 2026-08-05**, in that order and within the day. The renderer now
reports `all 9 spine slots present` **[M]**, and it renders two ways: from the subject's
`fork-register.json` when one is declared, and ABSENT-with-a-reason when none is — where the
reason is phrased as the CLAIM it is ("this encoding registers no interpretive forks") rather than
as a gap. Reg CF declares one, with three forks. **S10 (E30) is ruled and NOT built.** See §14.8
and §14.10.

### 4.2 The licence table

"Licence" answers: **what makes it legitimate to print this?** Every section has exactly one
licensing source, and a defined rendering when that licence is absent.

| section         | licensed by                                                                                              | renders when absent                                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| S1              | narrative section `orientation` + its provenance record                                                  | `**ABSENT.** <what S1 would have said>. No narrative section named \`orientation\` exists for this subject; §5's manifest declares none.` |
| S2._n_.law      | narrative part `law` of manifest entry _n_                                                               | ABSENT, naming the manifest entry                                                                                                         |
| S2._n_.encoding | narrative part `encoding` of manifest entry _n_                                                          | **nothing at all** — `encoding: null` is a legal, silent declination (§1.2)                                                               |
| S3.ladder       | the `p7-ladder` **receipt** + the committed SVGs it attests                                              | ABSENT, naming `p7-ladder` and whether it was declared, skipped or degraded                                                               |
| S3.lts          | the `p7-lts` receipt **and** the presence of `state-graphs/*.svg` in the run                             | §8.2's two-level ABSENT                                                                                                                   |
| S3.bpmn         | the `p7-bpmn` receipt + the emitted `.bpmn` and `.fidelity.txt` artifacts                                | ABSENT, naming `p7-bpmn`                                                                                                                  |
| S3.dmn          | the `p7-dmn` receipt + the emitted `.dmn` and `.fidelity.txt`; cross-checked against `p7-dmn-md`         | ABSENT, naming `p7-dmn`                                                                                                                   |
| S4              | narrative part + `src:` citations into the corpus's dated arms                                           | ABSENT                                                                                                                                    |
| S5              | narrative part + `src:` citations into the corpus's own limit comments                                   | ABSENT                                                                                                                                    |
| S6              | the **`p2-sweep` receipt if it exists**, else `render-report.mjs:315`'s refusal sentence quoted verbatim | see §4.3                                                                                                                                  |
| S7              | the `p7-mcp` receipt (for the measured tool list) + narrative for the prose                              | §9's two-level ABSENT                                                                                                                     |
| S8              | `provenance.json` + the stage's own receipt metrics                                                      | never absent — this section is the stage's self-description                                                                               |

Every run fact printed anywhere in the document — a verdict, a status, a count, an artifact
digest — is a `{{…}}` placeholder resolved from the journal fold (§3.5), never from narrative
prose. That is §6.1.

### 4.3 S6 is quoted, not rewritten

The audit report already contains the exactly-right paragraph, and it was written with care
**[M:** `render-report.mjs:315` **]**:

> `p2-sweep` is not declared at this milestone. Nothing was searched, so nothing may be reported as
> searched, and this report makes no claim that the encoding is current with respect to courts,
> C&DIs, no-action letters, or rules in flight. (At `g2` the stage validates a deposited register —
> but note that validating a register is not performing a sweep: no procedure enumerates the
> searches that should have run.)

**Ruling (part of E6's family, recorded here):** S6 **quotes this sentence** rather than composing a
lay-reader-friendly softening of it. A softened version is a different claim, and the difference
would be invisible to a reader.

This matters for Meng's brief, which asks for "practice directions and runtime influences from
court judgements". For SEC rules the analogue is C&DIs, no-action letters and staff bulletins, and
the honest position is that **this repo has never looked** — the strings appear only in pipeline
specs describing what a sweep _would_ search for, never attached to a Reg CF finding **[G]**.
There is no third option that stays true: either S6 renders the refusal, or somebody runs a P2
sweep and deposits `denovo/external-modifications.json` first.

Note also `p2-sweep.sh`'s own caveat, which S6 must not overclaim past **[G]**: whether a sweep was
_wide enough_ is unfalsifiable by construction — a register that searched nothing validates exactly
as cleanly as one that searched everything.

### 4.4 The Reg CF body, as a worked instance of S2

Not normative — this is what `etc/go/subjects/regcf/explainer/manifest.json` would declare, and it
is here so the spine is legible. Each row's encoding companion is a claim the corpus can license;
each is cited in the ground-truth passes and would be cited again, per §6.2, at the site.

| #   | law thread                                                           | encoding companion                                                                                                                                                                                       |
| --- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | The bargain: five conditions up front, three continuing restrictions | the root decision is an `AND` of exactly five calls, and the three deontic rules are deliberately **not** conjuncts of it — Rule 100(a)(4)'s proviso, encoded as structure                               |
| 2   | Who may not use it (Rule 100(b))                                     | drafted as disqualifiers, so encoded as six limbs disjoined then negated **once**; the mirrored wiki page lists four, and a missing rung in a six-rung ladder is visible where a missing sentence is not |
| 3   | How much one investor may put in                                     | the statute is ambiguous and the Commission glossed it twice; the encoding does not resolve it, it **dates both resolutions**                                                                            |
| 4   | What you must disclose                                               | the assurance ordering is _our invention, not the rule's_, and the corpus says so; the COVID window is a **banded typed refusal**, not a guess                                                           |
| 5   | What you may say (Rule 204)                                          | a bounded `SHANT` sunsets — the bug where an issuer advertising on day 400 evaluated compliant, and why the trace output could not have caught it                                                        |
| 6   | What you owe afterwards (Rules 202/203)                              | the totality checker **refused to certify** the reporting spine and said so rather than assuming                                                                                                         |
| 7   | What buyers may do (Rule 501)                                        | the one-year endpoint the rule does not decide: "a drafter who cared could remove the question with four words"                                                                                          |
| —   | —                                                                    | (S4 takes the temporal thread)                                                                                                                                                                           |

---

## 5. E1 — the narrative provenance model

Meng's ruling D1, in full: the lay narrative is **agent-drafted, checked in, and HG1-reviewed**. It
lives in the subject directory with a provenance record naming the source it was drafted from, so a
later run can detect drift when the source text changes. Unreviewed narrative must render visibly
marked as draft / "claimed, not verified".

### 5.1 File layout

```
etc/go/subjects/<id>/explainer/
  manifest.json                 # ordered spine + body declaration
  provenance.json               # one record per narrative file
  orientation.md
  s2-01-the-bargain.law.md
  s2-01-the-bargain.encoding.md
  s2-02-who-may-not-use-it.law.md
  s2-02-who-may-not-use-it.encoding.md
  ...
  time.law.md
  time.encoding.md
  limits.encoding.md
  call-to-action.md
  reviews/
    orientation.md.sig          # detached SSH signature, present only when reviewed
    ...
```

Flat, one file per part. The `.law.md` / `.encoding.md` split is what makes `encoding: null` a
_file that does not exist_ rather than a section a drafter has to remember to leave empty.

`NOTES.md` in the same subject directory is **not** reused: it is explicitly free prose that
scripts never read (`subject.mjs:6-9` **[G]**), and overloading it would make it script-read, which
is a change to what it is.

### 5.2 `manifest.json`, and the `subject.json` key

`subject.mjs` refuses any unknown top-level key in `subject.json` **[M:** `subject.mjs:165-176` **]**.
So the subject declares its explainer explicitly:

```json
"explainer": { "dir": "etc/go/subjects/regcf/explainer" }
```

**Ruling (E1-a): explicit declaration, not directory discovery.** Convention-over-configuration
would work and needs no schema change; it is refused because a mistyped directory name would then
yield a fully-ABSENT explainer with no error anywhere — the "absence experienced as breakage"
failure mode. A subject that declares no `explainer` key gets a clean `go_skip` with a named
reason, which is a different and honest outcome.

`manifest.json` shape:

```json
{
  "explainer_schema": 1,
  "title": "SEC Regulation Crowdfunding, explained — and what happened when we made it executable",
  "spine": {
    "orientation": { "file": "orientation.md" },
    "body": [
      {
        "id": "the-bargain",
        "heading": "The bargain: five conditions, three continuing duties",
        "law": "s2-01-the-bargain.law.md",
        "encoding": "s2-01-the-bargain.encoding.md"
      },
      { "id": "…", "heading": "…", "law": "…", "encoding": null }
    ],
    "pictures": { "intro": "pictures.md" },
    "time": { "law": "time.law.md", "encoding": "time.encoding.md" },
    "limits": { "law": null, "encoding": "limits.encoding.md" },
    "sweep": { "declined": null },
    "call_to_action": { "file": "call-to-action.md" }
  }
}
```

A spine slot is either filled, or carries `"declined": "<reason>"`, which renders as a stated
declination. `"declined": null` is a **schema error**, not a silent decline — a decline must carry
a reason for the same reason a waiver must (`go.sh:556` **[G]**: a waiver with no reason cannot be
printed in the report).

### 5.3 `provenance.json` — the record's fields

One record per narrative file, keyed by path relative to the explainer directory.

```json
{
  "narrative_schema": 1,
  "records": [
    {
      "file": "s2-02-who-may-not-use-it.law.md",
      "sha256": "sha256:…",
      "drafted_by": "claude-opus-5",
      "drafted_on": "2026-08-03",
      "drafted_from": [
        {
          "path": "jl4/examples/legal/regcf/regcf.l4",
          "sha256": "sha256:…",
          "anchor": "L254-L322"
        },
        {
          "path": "jl4/examples/legal/regcf/README.md",
          "sha256": "sha256:…",
          "anchor": "§3.6"
        }
      ],
      "review": {
        "state": "unreviewed",
        "reviewer": null,
        "reviewed_on": null,
        "reviewed_sha256": null,
        "reviewed_sources": [],
        "signature": null
      }
    }
  ]
}
```

Field notes:

- **`drafted_from[]` is the drift anchor and it is mandatory and non-empty.** A narrative file with
  no declared source is not draftable; the stage refuses the deposit (`DEGRADED`, not `BROKEN` —
  see §5.4).
- **`anchor` is documentation, not a check.** Line ranges move. The digest is the check; the anchor
  tells a human reviewer where to look. Saying so here prevents a later reader from believing the
  anchor is verified.
- **`reviewed_sources` is a snapshot, not a pointer.** It records the source digests _as at review
  time_, which is what makes review drift (§5.4-3) distinguishable from narrative drift.
- **`review.state` ∈ `unreviewed | reviewed | stale`**, and `stale` is **never written by a human** —
  it is derived at render time (§5.4-3) and written only into the receipt and the rendering.

### 5.4 Drift detection — three independent classes

At stage time, for every record: re-hash `file`, re-hash every `drafted_from[].path`, and compare.

| #   | class               | test                                                                                                | rendering                                                                                                                                                                                        | receipt                             |
| --- | ------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------- |
| 1   | **narrative drift** | `sha256(file) ≠ record.sha256`                                                                      | section renders behind `**UNRECORDED EDIT.** This text has changed since its provenance record was written (recorded `<a>`, on disk `<b>`). Nothing below has been checked against its sources.` | `DEGRADED`, reason names the file   |
| 2   | **source drift**    | `sha256(drafted_from[i].path) ≠ recorded`                                                           | section renders behind `**SOURCE MOVED.** Drafted from \`<path>\` at \`<a>\`; that file now hashes \`<b>\`. The prose below may describe text that no longer exists.`                            | `DEGRADED`, reason names the source |
| 3   | **review drift**    | `state == "reviewed"` and (`reviewed_sha256 ≠ sha256(file)` or any `reviewed_sources[i]` ≠ current) | `state` becomes `stale`; section renders the §5.6 draft banner with `— the review no longer covers this text`                                                                                    | `DEGRADED`                          |

**Why `DEGRADED` and not `BROKEN`.** `BROKEN` is defined as _"a defect in the phase script, never a
finding about the corpus"_ (`receipt.mjs:162` **[G]**). Provenance drift is a finding about the
deposit. `BROKEN` is reserved for: unparseable JSON, a manifest naming a file that does not exist,
a schema violation, and a renderer crash.

**Ruling (E1-b): drift degrades and renders; it never suppresses.** A drifted section is still
printed, behind its banner. Suppression would let a stale explainer look tidy, and would let a
drafter make an inconvenient section disappear by touching its source. This mirrors
`render-report.mjs:461-463`, which prints `**DOES NOT VERIFY**` and renders anyway **[G]** — an
explainer that silently refuses a broken chain becomes the laundering channel this design closes.

### 5.5 E17 — the review signature, and why the run gate is not extended

#### The ruling

A review is a **detached SSH signature over a per-section payload**, verified with the same
machinery the run gates use — `ssh-keygen -Y verify` against
`specs/todo/single-instruction-demo/gate-allowed-signers` — under a **distinct namespace,
`l4-go-narrative`**. The run-level HG1 gate is **not** extended to cover narrative content.

The payload is a deterministic rendering, and nothing in it is typed by hand:

```
l4-go narrative review
subject: regcf
file: s2-02-who-may-not-use-it.law.md
sha256: sha256:…
sources:
  jl4/examples/legal/regcf/regcf.l4  sha256:…
  jl4/examples/legal/regcf/README.md sha256:…
```

Verification lives in a new `etc/go/lib/narrative-verify.sh`, shaped on `etc/go/gate-verify.sh`
(which is 0/3/2 for verified/refused/usage **[M]**).

**Status 2026-08-03: NOT BUILT, and the document now says the right thing about it.**
`grep -rn 'l4-go-narrative\|narrative-verify' etc/go/` matches nothing. `driftFor` reads
`record.review.state`, a plain JSON string, so a hand-written `"state": "reviewed"` with matching
digests renders as reviewed, with a named reviewer, behind no banner and past no check. The v0
banner said the gap was that "this repository has no enrolled signer" — true, and the wrong gap to
name: the missing piece is a **verifier**, not a key, and a reader deciding what a future
`reviewed` row is worth needs to know which. The banner now says so. Nothing in this deposit claims
review, so the document is honest today by having nothing to be wrong about; that is not the same
as the mechanism being closed.

#### Why not fold narrative digests into the HG1 payload

Because they are different objects with different lifetimes. HG1's payload is **journal-derived and
run-scoped** (`gate-payload.mjs` builds it from `run_begin` plus the executed receipts and the
corpus digests carried as `p0-preflight` metrics **[M]**). A narrative section's review is a
property of **content that outlives the run**: reviewing a paragraph once should not have to be
redone on the next run over an unchanged corpus. Binding it to the run gate would force exactly
that.

And it would lose the granularity D1 requires: a single run gate cannot say "sections 1-4 reviewed,
section 5 draft", which is the state every real document is in for most of its life.

#### The consequence, stated plainly and in the present tense

`gate-allowed-signers` **ships with zero enrolled keys** — I counted **[M]**. So on the day this is
built, **every narrative section is `unreviewed`, every section renders the §5.6 draft banner, and
the stage's receipt is `DEGRADED` for that reason.** That is the correct v0 state and the status
header of the rendered document must say it, in the present tense, without softening.

#### The case against this ruling, honestly

Two signature schemes with two namespaces is more machinery than a project this size wants, and a
reader has to understand both. The alternative — one gate covering corpus and narrative together —
is genuinely simpler, and if per-section granularity turns out not to matter in practice (because
in practice a whole explainer is reviewed in one sitting), it is the better design. **What would
overturn this ruling:** a measured run of the review workflow showing that per-section state was
never actually used.

### 5.6 How an unreviewed draft is marked

Three levels, all required:

1. **Document header.** A banner immediately under the title, before any content:
   `**{{narrative.draft_count}} of {{narrative.section_count}} sections in this document are AGENT-DRAFTED AND NOT REVIEWED.** They are marked individually below. A drafted section is a claim, not a finding.`
   Both figures are `{{…}}` placeholders resolved from the stage's own metrics (§6.1), never typed.
2. **Section banner.** Immediately under each affected heading:
   `**DRAFT — claimed, not verified.** Drafted by \`<drafted_by>\` on \`<drafted_on>\` from <sources>. No reviewer has signed this text.`The phrase *claimed, not verified* is the house phrase already used by`receiptBlock`
(`render-report.mjs:262-277` **[G]**) and is deliberately reused so the two documents read the
   same way.
3. **§S8.** A table of every section with its review state, reviewer, and the sources it was
   drafted from — with digests. This is the section a sceptic reads first.

In the HTML the banner also carries a visual treatment (a left rule and a muted background), which
is the only place in this design where presentation carries meaning; §7.3 requires the marking to
survive with CSS disabled, so the text banner is load-bearing and the styling is not.

---

## 6. The discipline: how a document full of numbers stays honest

This is the section the rest of the design exists to serve.

### 6.1 Run facts are placeholders. Full stop.

Anything the journal knows — verdicts, statuses, stage names, artifact digests, record counts,
gate states, section counts, draft counts — appears **only** as `{{…}}` in the explainer template
and in narrative files, resolved by the same mechanism `render-report.mjs:480-498` uses **[M]**:
flat string-key lookup, and an unresolved key is a **hard exit 4**.

The explainer template is subject to the **same bare-digit-run check** as the report template
(`render-report.mjs:77-96` **[M]**), with the same allowlist, run before the journal is opened, and
wired into CI as its own step (§11) — because the existing CI leg names `render-report.mjs` by
path and gives a sibling template no coverage **[G]**.

### 6.2 E6 — every other number is a checked citation

#### The ruling

A digit-run of length ≥ 2 in a **narrative** file must be inside one of exactly two constructs:

**(a) a placeholder**, `{{…}}`, resolved from the journal (§6.1); or

**(b) a cited figure**, written as a markdown link with a repo scheme:

```
[$5,000,000](src:jl4/examples/legal/regcf/regcf.l4#L150)
[six exclusion limbs](src:jl4/examples/legal/regcf/regcf.l4#L309-L316 "verbatim")
[1340/1340 on both engines](art:regcf-corpus.fidelity.txt#L1 "unchecked: engine run reported by the p7-dmn receipt, not by this line")
```

Schemes:

| scheme | resolves to                                                                                | additional check                                                                                            |
| ------ | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `src:` | a repo-root-relative path, read from the working tree                                      | —                                                                                                           |
| `art:` | a file this run's journal attests, matched by basename against the receipt's `artifacts[]` | the file's **current** sha256 must equal the **recorded** one, or the citation is marked `ARTIFACT CHANGED` |

Check modes, selected by the link title:

| mode                | title                   | check                                                                                                                                                |
| ------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **digit** (default) | none                    | strip every non-digit from the link text; require that digit string to occur, as a digit substring ignoring separators, within the cited line window |
| **verbatim**        | `"verbatim"`            | require the link text to occur as a literal substring within the window                                                                              |
| **unchecked**       | `"unchecked: <reason>"` | no content check; the reason is **rendered**, and the occurrence is **counted**                                                                      |

A citation whose target file is missing, whose line is out of range, or whose check fails renders
the figure followed by `⚠ CITATION DOES NOT RESOLVE — <detail>` and degrades the receipt.

The count of `unchecked` citations is a **receipt metric and is printed in §S8**, following P8's
precedent for `nested_not_visited`: _an exclusion nobody can size is an exclusion nobody believes_
(`SPEC.md` §P8 **[M]**).

#### Why this is the right shape

It converts the explainer's central risk into an oracle. "Must not become a second place where
numbers are typed by hand" is not enforceable as a rule about drafting; it is enforceable as a
rule about **re-reading the source at render time**. Every number in the finished document is
either derived from the journal or is a quotation whose source line was opened and matched while
the document was being built.

It also gives the reader something no legal explainer has: every figure is a link to the line of
code or of statute it came from.

#### Known incompleteness, recorded rather than hidden

- **Dates do not digit-match.** `2016-05-16` normalises to `20160516`; the corpus writes
  `Date 16 5 2016`. Date citations must use `"verbatim"` against a quoted fragment, or
  `"unchecked:"`. The lint cannot tell a drafter which — this is a drafting rule with a checker
  that catches the _failure_, not one that prevents the mistake.
- **Window containment is not semantic containment.** `5000000` appearing at the cited line does
  not prove the sentence around it is true. The check bounds transcription error; it does not
  bound misreading. Say so in §S8.

  **MEASURED 2026-08-05, because this stopped being hypothetical.** `limits.encoding.md` carried
  "The one-year restricted period is [365 days](src:…/regcf.l4#L250) — wrong across a leap year".
  The defect was then repaired, and the repair replaced line 250 with a comment arguing _against_
  the flat count: "A flat 365 also fails to generalise inside its own Part". The digits `365` are
  still at line 250, so **the citation kept resolving while the sentence it supported became
  false** — and the source now says the opposite of the prose that cites it. Worse, the failure is
  self-concealing: a check that goes green is read as evidence, so a passing citation makes the
  stale sentence _harder_ to notice than an uncited one.

  The one signal that did fire was **source drift** (§5.3): `regcf.l4`'s hash moved, so every
  section drafted from it rendered `SOURCE MOVED`. That is the only mechanism in this design that
  catches semantic inversion, which makes clearing it a claim rather than a chore — see **E31**.

- **`art:` matches by basename.** Two artifacts with the same basename in one run would be
  ambiguous. No run produces such a pair today; the lint should refuse the ambiguity rather than
  pick one.

### 6.3 The lint runs before the render

A narrative file that violates §6.2 does not render with a warning — it fails the **deposit
check**, before any HTML exists, and the stage reports `DEGRADED` naming file and line. Rationale:
§6.2 is a property of the checked-in text, and a property of checked-in text should be reported
against the text, at a location a person can go fix.

The same pass enforces §7.2's markdown subset and §6.5's reserved vocabulary. One pass, one report,
one list of file:line complaints.

### 6.4 E7 — no number may be sourced from `README.md` or `PROJECTIONS.md` prose

#### The ruling

`src:` citations may point at `jl4/examples/legal/<subject>/README.md` and `PROJECTIONS.md` for
**arguments and quotations**, and may **never** be the source of a figure — a count, a size, a line
number, a fidelity total. Figures come from the corpus, from an emitted artifact, or from the
journal.

#### Why — measured

The ground-truth pass re-derived those documents' own numbers against the tree and found, at
`5f79ff64`:

- `PROJECTIONS.md` states the corpus is **1,236 lines**; `wc -l` says **1,224** **[M]**.
- `README.md` §7 and `PROJECTIONS.md` §5 both say **five `@export`s**; there are **six** **[M** — I
  counted the eight `@export` occurrences and confirmed two are inside comments at
  `regcf-wizard.l4:25` and `:614`, leaving real annotations at `:548, :564, :585, :593, :603, :617`
  **]**.
- Three documents give three different values for the longest record field: 291, 285, 288 **[G]**.
- The BPMN fidelity table in `PROJECTIONS.md` §3 disagrees with the committed goldens on every
  row, and names a finding code the files no longer carry **[G]**.
- Two documents disagree on one ladder figure's scene dimensions **[G]**.

Those are not sloppy documents; they are careful documents that were correct when written. That is
the point: **prose about artifacts drifts from artifacts, and the explainer must read the artifact.**
The DMN fidelity counts, by contrast, reproduced exactly from the committed fidelity report **[G]** —
which is what a figure that is re-derived rather than transcribed looks like.

### 6.5 E8 — narrative prose may not carry run-status vocabulary

#### The ruling

Narrative files may not contain the reserved status vocabulary except inside a `{{…}}` placeholder.
Reserved = `verdict.mjs`'s `STATUSES` (`PASS, DEGRADED, NOT-EXECUTABLE, NOT-REGENERATED, UNVERIFIED,
NOT-BUILT, SKIPPED, BROKEN` **[G]**) plus `COMPLETE`, `INCOMPLETE`, and the phrases `all tests pass`,
`all assertions pass`, `fully verified`.

#### Why

This is the mechanical half of "the explainer must never be able to make a claim the audit report
cannot support". A narrative that says "all 70 assertions pass" is a run claim frozen into prose; it
will be true on the day it is drafted and false the first time a test regresses, and it will keep
saying so with total confidence. `{{tests.assertions_passed}} of {{tests.assertions_total}}` cannot.

#### What this ruling does not decide

It does not stop a narrative from _discussing_ verification — "the totality checker refused to
certify this rule" is a claim about the encoding, licensed by a citation into the fidelity report,
and is exactly the second-thread content this document wants. The rule bans **status words about
this run**, not vocabulary about the work.

#### Amended 2026-08-03 — case

The check was anchored to the uppercase literal, so it caught `DEGRADED` and missed `degraded`.
MEASURED on the shipped deposit: `limits.encoding.md` carried "The pipeline's encoding check rides
degraded on that count" — a run status frozen into prose, true only because `p3-check` happened to
be `DEGRADED` on the run that drafted it, and invisible to the one check that exists to catch that.

Seven of the ten words are now matched **in any case**: `DEGRADED`, `NOT-EXECUTABLE`,
`NOT-REGENERATED`, `UNVERIFIED`, `NOT-BUILT`, `SKIPPED`, `INCOMPLETE`
(`narrative.mjs`'s `CASE_INSENSITIVE_STATUS_WORDS`). Three are **not**: `PASS`, `BROKEN` and
`COMPLETE` are ordinary English and occur in ordinary sentences — "one house rule broken and
tolerated" was a real false positive in this deposit — and a lint that cries wolf is a lint a
drafter routes around. All ten remain banned in their uppercase spelling, where they are
unambiguous. The split is recorded here because it is a real hole: a narrative writing "the leg
passed" in lower case is still uncaught.

---

## 7. The renderer

### 7.1 E9 — the HTML is the document; the markdown is the record

#### The ruling

For the **audit report**, `report.md` is the report and the HTML is a `<pre>` convenience that says
so in its own first paragraph (`render-report.mjs:508-517` **[M]**). For the **explainer**, that is
inverted: `explainer.html` is the document a reader reads, and `explainer.md` is the record.

#### Why

The audit report is text; a `<pre>` loses nothing. The explainer contains ladder diagrams, decision
tables and a lay reader. A figure that only renders in HTML makes the markdown the lesser carrier,
and pretending otherwise would be a claim about the document that the document contradicts.

`explainer.md` therefore references figures by repo-relative path
(`![…](../../jl4/examples/legal/regcf/figures/regcf-rule-100b.svg)`) and `explainer.html` **inlines
the same SVG bytes**. Both carry the same text, the same banners and the same citations; they
differ only in how a figure travels.

Each file states its own role in its first line, as the report's HTML does.

### 7.2 E10 — a closed markdown subset, lint-enforced, zero dependencies

#### The ruling

A new `etc/go/report/md-lite.mjs`, written for this document and used **only** by it, renders a
**closed subset** of markdown to HTML. It is never wired into `render-report.mjs` (D2).

The subset — blocks: ATX headings `#`–`####`; paragraphs; unordered and ordered lists (one level of
nesting); GFM pipe tables; fenced code blocks; block quotes; horizontal rules; and a raw-HTML
passthrough restricted to a **whitelist of exactly `<figure>`, `<figcaption>`, `<svg>…</svg>`, and
`<div class="…">` with a class from a fixed set.** Inline: `**bold**`, `_italic_`, `` `code` ``,
and links, which must use one of the schemes in §6.2 or be an external `https:` URL.

Anything outside the subset — reference links, setext headings, HTML comments, images with a
non-repo path, nested block quotes, footnotes, and **two adjacent backticks** — is **rejected by the
lint** (§6.3) at file:line.

`MD-BACKTICK` was added on 2026-08-03 because the "rejected rather than mangled" property above was
being asserted and not held. A code span in this subset takes one backtick and cannot nest, so a
narrative line reading `` `"(1)" ... transfer's `to the issuer of the securities`` ``closed the
span at the inner backtick and drew the remainder — including a bare pair of backticks — as ordinary
sentence text. MEASURED in the rendered explainer of run`2026-08-03-3f45e62b-002`. The narrative was
repaired to quote the excerpt in a fenced block; the lint is what stops the next one being silent.
The check deliberately fires on the two-backtick sequence rather than on backtick PARITY, because a
code span **wrapped across two source lines** is legal — `mdToHtml` joins a paragraph's lines before
rendering it, and two Reg CF narrative files rely on that.

#### Why a lint rather than a tolerant renderer

Markdown degrades silently: an unrecognised construct becomes paragraph text and a sentence quietly
changes meaning. In a legal explainer a silently mangled sentence is the worst available failure. A
closed subset with a refusing lint makes the failure loud and puts it at a line number.

#### Why not a dependency

There is no markdown engine, no viz library, no diagram renderer in any of this repo's nineteen
`package.json` files; the root's runtime deps are `husky`, `lint-staged`, `prettier@3.4.2`, `turbo`,
`typescript` **[G]**. The audit report's HTML wrapper carries a comment saying its minimality is
deliberate **[M]**. Adding the project's first markdown dependency to publish a document is a large
change disguised as a small one.

#### The case against this ruling, honestly

Hand-written markdown renderers are a classic tar pit, and the subset will be argued with by every
future drafter. The counter-argument is that the subset is small, the lint makes violations visible
rather than silent, and the alternative — a dependency — is worse for a document whose whole claim
is that you can check everything in it yourself.

### 7.3 Escaping, and one bug not to inherit

`render-report.mjs`'s `escapeHtml` (`:511-512` **[M]**) replaces `&`, `<`, `>` — and **not** `"` or
`'`. That is safe there because it is only ever used in text nodes and a `<title>`. The explainer
puts text into **attributes** (`alt`, `title`, `href`, `class`), so `md-lite.mjs` must escape
quotes as well. Copying the three-replacement version into an attribute context is an injection
bug; this sentence exists so nobody does.

Styling: one inline `<style>` element, no external resources of any kind, and the document must be
legible with CSS disabled (§5.6-2). Dark mode is handled by `@media (prefers-color-scheme: dark)`
on the page chrome only — the figures are handled by §8.1.

---

## 8. Figures: what can be drawn, and what honestly cannot

### 8.1 E11 — ladder SVGs inline verbatim: unmodified, untrimmed, boxed

#### The ruling

The six committed ladder SVGs at `jl4/examples/legal/regcf/figures/` are inlined into
`explainer.html` **byte-for-byte**. They are not edited, not re-laid-out, and not trimmed.

**Amended 2026-08-03.** `explainer.md` used to carry `![slug](jl4/examples/…/figures/x.svg)`, a
repo-relative path emitted into a document that lives under `TMPDIR` — MEASURED on run
`2026-08-03-3f45e62b-004`, six of six targets did not resolve relative to the file, so the record
carried six broken links and called them figures. An absolute path would resolve on the machine
that rendered it and nowhere else. The markdown carrier now **names** each figure's source file and
draws nothing, and the document's second paragraph says so above the fold: only the HTML carries
pictures. The same applies to the state-machine figures, which previously carried an italic caption
with no image markup at all and no note that the picture was elsewhere.

Each is wrapped in a `<figure>` whose caption is the `why` string that already exists beside the
figure's entry in the subject's demo entry point — so the "key decisions" selection is read from
where it already lives, not re-decided in the explainer.

**Three constraints, recorded not solved:**

1. **They are light-theme only.** Each opens with an opaque full-bleed `<rect … fill="#ffffff"/>`
   **[M:** confirmed on `regcf-rule-100b.svg` line 2 **]**. The ruling is to **box them on a white
   card** in dark mode, not to strip the rect. Stripping it is editing the artifact, and the
   artifact is the evidence.
2. **They are self-contained.** No `xlink:href`, no `<image>`, no `@import`, no `url(` in any of the
   seven **[M:** counted, zero in each; re-counted 2026-08-09 over the seventh, `regcf-resale-limb-4`
   **]**. They inline with no CSP or dependency concern at all.
3. **One of the seven is unusable as a page asset, and the explainer must not fix that.** The root
   exemption figure is 3027 × 185 — a strip sixteen times wider than tall — because an `AND` is a
   series circuit whose scene width is the sum of its children's **[G]**. The ruling: render it in a
   horizontally scrolling container at full fidelity, with a caption that states the width and says
   why, and a link to the file. **Trimming is transcription** — the figures' own README says so —
   and a trimmed ladder is a different rule.

   This bullet read "three of the six" until 2026-08-09, and the other two were wide for a different
   reason: leaf labels never wrap, and Rule 501(a)(4)'s leaf printed at 301 characters because it
   **was** the CFR's whole sentence in one field name. That field is now six, under a decision of
   its own, and the longest leaf in any regcf figure is 108 characters. The wrapping limitation is
   unchanged; what changed is that nothing here trips it. Note which repair worked: decomposing a
   name that hid four statutory alternatives, not a layout feature.

The drift guard on these figures (`ts-shared/ladder-svg/test/regcf-figures.test.ts`) is
**one-directional**: a leaf added to the L4 and absent from a figure still passes **[G]**. §S8 says
so. The explainer inherits that limit; it does not repair it.

### 8.2 E12 — the LTS picture is environment-conditional

#### The constraint, stated first

**There is no in-repo path from DOT to SVG.** `l4 state-graph` emits DOT to stdout;
`etc/go/lib/split-digraphs.mjs` is an **oracle**, not a renderer — it counts `digraph` blocks and
cross-checks them against the BPMN discovery call's independent count of regulative rules, and its
only file output is splitting the concatenation **[G]**. `p7-lts.sh` renders SVGs only if `dot` is
on `PATH`, and says so in its own note: _"graphviz absent; DOT emitted but not rendered"_ **[G]**.
DOT carries no coordinates, so writing a serializer would mean writing a layout engine.

Four options were costed. **(a)** require graphviz and mark the section ABSENT when it is missing.
**(b)** commit rendered SVGs into the subject directory the way the ladder figures are committed.
**(c)** write a DOT layout engine. **(d)** `specs/research/mermaid-planb/ghsim.mjs`, which reads
`node_modules/mermaid/dist/mermaid.min.js` — not in any workspace `package.json`, so research
scaffolding with unvendored deps, not an in-tree renderer **[G]**.

#### The ruling

**(a).** The LTS subsection renders at two levels:

- **`p7-lts` receipt present, `state-graphs/*.svg` present in the run** → inline them, captioned
  with the rule name read from the DOT `label=` attribute (the split filenames are
  `01-rule-1.dot`, `02-rule-2.dot`, `03-rule-3.dot` and **do not say which rule is which**
  **[G]**), and carry the leg's own `INTERIM` label, which rides in the receipt's status.
- **receipt present, no SVGs** → `**ABSENT.** The three state machines were emitted as GraphViz DOT
and not rendered: no \`dot\` binary was on PATH for this run. This repository has no DOT-to-SVG
  path of its own — DOT carries no coordinates, so rendering it means running a layout engine. The
  DOT is at \`<paths>\` and \`dot -Tsvg\` reproduces the picture.`
- **no receipt** → the ordinary stage-ABSENT rendering.

**(b) is refused for v0**, and this is the interesting half: committed SVGs would make the picture
reproducible, but there is **no drift guard for them**. The ladder figures have one (weak,
one-directional, §8.1); a committed LTS render would have none at all, and a committed picture that
silently stops matching its source is worse than an absent one. That is the ruling's whole basis,
and building a drift guard is what would overturn it.

#### The identifier collision, found by inlining them for the first time

The first branch above was unexercised until run `2026-08-03-3f45e62b-002`, which had `dot` on PATH
and inlined all three. `dot` numbers its nodes and edges from one **per file**, so each graph
defines `graph0`, `node1`, `edge1` and so on; an `<svg>` element is not an identifier scope, so all
three landed in one document namespace — MEASURED: 27 definitions of 9 names, against 31 distinct
ids in the whole page. Nothing referenced them, so nothing drew wrong, but a DOT using a gradient or
a clip path emits `url(#…)` and the first definition would then win for every picture.

**So the renderer prefixes each LTS figure's identifiers with that figure's own key, in the HTML
carrier only**, and the subsection says so in its own prose with the count. The `.svg` and `.dot`
artifacts on disk are untouched. This is consistent with §8.1 rather than an exception to it: the
ladder subsection tells the reader its figures are inlined byte for byte, and the ladder exporter
emits **no `id` at all** (MEASURED: zero across all six committed figures), so a ladder figure is
never rewritten. The LTS caption claims only that the picture was rendered from the emitted DOT by
the local `dot`, which stays true.

#### What this ruling costs

Meng's brief asks for "an LTS visualisation of key processes". On a machine without graphviz the
explainer does not have one. That is recorded, not hidden — and the proper LTS visualiser is
independently unbuilt (`SPEC.md` §5 **[M]**), so the interim is all there ever was.

### 8.3 E13 — DMN tables are extracted from the emitted XML

#### The ruling

The DMN subsection derives its tables from the **emitted `.dmn` artifact** with a narrow extractor
(`etc/go/lib/dmn-tables.mjs`, new): read `<decisionTable>`, its `<input>`/`<output>`/`<rule>`
children and its `hitPolicy`, and render each as an HTML table with its annotation column intact.

The exhibit is the **rule-date table**: `hitPolicy="UNIQUE"`, an input typed `date`, half-open FEEL
intervals, and an annotation column carrying the Federal Register citation for each regime **[G]**.
Nothing else in the projection set shows the temporal axis as a _table_, and no other legal
explainer has one to show.

#### On the objection that this is a second table renderer

`jl4-core/src/L4/Dmn/Markdown.hs` already emits pipe tables, and its own header warns against two
hand-maintained exporters that quietly disagree **[G]**. The objection does not land, because the
two read **different things**: `Markdown.hs` reads the L4 IR; the extractor reads the **emitted
artifact**. A view of the artifact is what a fidelity report is.

And the overlap is converted into an **oracle**: where `p7-dmn-md` emitted a table, the extractor's
table for the same decision must agree on input count, output count and rule count. A disagreement
is a **finding** — `DEGRADED`, reason naming the decision — not a drift.

#### Why the dmnmd artifact is still rendered, and why it is the best thing in the section

For Reg CF, `regcf-corpus.dmn.md` is **11 lines carrying one table**, beside a **301-line**
all-blocking loss report, against a `.dmn` carrying 67 decisions and 12 decision tables **[G]**.
`p7-dmn-md.sh`'s own receipt calls it _"the most honest artifact in the set and the least useful
one, which is why it ships."_ The explainer prints the one table, prints the loss-code histogram
beside it, and says what the pairing means: a lossless-looking document and a document that tells
you what it lost are different kinds of object, and only one of them can be trusted.

Every count in that subsection is `art:`-cited into the fidelity report or placeholder-resolved
from the `p7-dmn` receipt's metrics. None is typed.

### 8.4 E14 — the BPMN/DMN diagram-interchange serializer is deferred to v1

> **BPMN HALF DISCHARGED 2026-08-06, see §8.4.1.** The BPMN serializer is built
> (`etc/bpmn-to-svg.mjs`), wired into `p7-bpmn`, and its output is inlined by `bpmnSubsection()`
> on the same terms as the ladder figures. **The DMN DRG half of this ruling remains deferred and
> is unchanged.** The text below is retained because it records why the deferral was right at the
> time and because §13's E19 cites it.

#### The measurement that makes it feasible

Both exporters already emit full diagram interchange: `regcf-corpus.dmn` carries 198 `DMNShape` and
360 `DMNEdge` with `<dc:Bounds x=… y=… width=… height=…>`, and `regcf-reporting.bpmn` carries 24
`BPMNShape` and 18 `BPMNEdge` with real `<di:waypoint>` polylines **[G]**. **The coordinates are
already computed and committed.** So an SVG of a BPMN process or of the DMN DRG needs a
_serializer_ — rects, text, polylines; on the order of two hundred lines of pure node with zero
dependencies — and not a layout engine. This is the opposite of the LTS situation and it is worth
stating the contrast explicitly, because "we can't draw the LTS" invites the wrong inference about
BPMN.

#### The ruling

**v0 does not build it.** The BPMN subsection in v0 renders: the process's fidelity findings, the
`F1` finding **quoted verbatim** (_"A prohibition is not an activity at all and BPMN has no negative
shape for one, so read literally this diagram instructs the reader to perform the very act the rule
forbids"_ **[G]**), the `P-DEADLINE` observation that single-sourcing the period names is what costs
the timer, and a link to the `.bpmn` artifact. **v1 adds the serializer** and inlines the pictures.

Deferring is a scope call, not a technical one: v0's job is to prove the document's _discipline_
works end to end, and adding a graphics serializer to that first landing doubles its surface for no
gain in the property being proved.

#### What v0 must say while the picture is missing

Not "coming soon". The subsection renders the fidelity material and a stated absence with its
reason — the same shape as every other ABSENT in this design. §13 tracks E19: whether the serializer
belongs here or in `l4 export`, where every consumer would get it.

### 8.4.1 E14-BPMN — ANSWERED 2026-08-06: build it, and light-only like the ladders

#### What was measured before deciding

The build-vs-buy question was settled against `bpmn-js`, the reference renderer, on evidence rather
than preference **[M, 2026-08-06]**:

| question                                    | answer                                                                                                                                                                                                                         |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Is there a headless route to `bpmn-js`?     | Only via Chromium. Camunda Modeler 5.49.0 has **no** CLI export — `--help`/`--version` are swallowed as feature flags and the GUI launches. `bpmn-to-image`'s SVG normalises to the same digest as driving puppeteer directly. |
| Is its output reproducible across machines? | **No.** Its geometry comes from real font metrics: 14 `<tspan>` under Arial, 15 under Times, 19 under Courier — a metrically different fallback re-wraps the labels, not just shifts them.                                     |
| Can its output be themed?                   | No — the palette is baked in as inline `style` attributes. Moot under the ruling below, but recorded.                                                                                                                          |
| Does §8.2's objection carry over?           | **No, and this is the deciding fact.** §8.2 rejected a DOT serializer because "DOT carries no coordinates, so writing a serializer would mean writing a layout engine". The BPMN DI carries every coordinate.                  |
| Does ruling E9 permit a runtime renderer?   | **No.** `explainer.md` references each figure by path and `explainer.html` inlines the same bytes. A picture that exists only after a JS engine runs has no bytes to reference.                                                |

E14 above estimated "on the order of two hundred lines of pure node with zero dependencies". The
built renderer is **524 lines, 352 of them code** (the balance is comment), **zero dependencies**,
and renders **12/12** `.bpmn` files in the repo **byte-deterministically** — each rendered twice to
equal sha256 **[M]**. The estimate was right about the order of magnitude and about the
dependencies.

#### The ruling

1. **Build it, do not buy it.** `etc/bpmn-to-svg.mjs`. It covers the closed vocabulary
   `L4.Bpmn.IR` emits and **throws** on anything else; `p7-bpmn` turns that throw into a DEGRADED
   receipt. This is deliberate: a new node kind must announce itself, because a legal diagram that
   is silently missing an element is worse than no diagram — the reader cannot tell anything is
   absent.
2. **`bpmn-js` is retained as a dev-time conformance oracle, not a pipeline phase.** It is the
   reference, and a hand-written transform is an unattested transcription without one. Concretely:
   the emitted DI omits `isMarkerVisible` entirely (zero occurrences corpus-wide **[M]**), so the
   exclusive gateway draws as a bare unmarked diamond — and that is known to be _correct_ rather
   than a defect only because `bpmn-js` does the same.
3. **Light-theme only, on an opaque white ground — the same rule §8.1-1 already applies to the
   ladders.** RULED by Meng 2026-08-06: **these figures may go to print.** A diagram that inverts
   under a reader's theme is a different picture from the one that was attested, and the attestation
   is over bytes, not over an appearance. The renderer therefore emits an opaque full-bleed
   `<rect … fill="#ffffff"/>` and hard-codes its ink. As with the ladders, the remedy in dark mode
   is to keep the **figure card** light, never to strip the rect.
4. **Zero `id` attributes, no `<style>` element, no classes.** Both are inlining hazards rather
   than aesthetics. An `<svg>` is not an identifier scope, so a shared `id` collides across the
   figures sharing `explainer.html` — the hazard `namespaceIds()` exists to fix for the GraphViz
   pictures. A `<style>` block is likewise unscoped, so a selector such as `.lbl` would match the
   host document. Avoiding both is what lets these figures be inlined byte for byte on the ladders'
   terms instead of being rewritten on the way in.

#### What review changed

Two claims made while deciding this were **wrong and were corrected before landing**; they are
recorded so nobody restores them:

- _"bpmn-js output breaks on a Linux runner without Arial."_ **Overstated.** Naming an absent font
  changes nothing — the stack falls back to a metric-compatible face. Only a metrically _different_
  face re-wraps. The risk is real but conditional on the CI image's font package, and it is **not**
  the decisive argument; items 1, 4 and E9 are.
- _"Theming is decisive."_ **It is not**, because ruling 3 above makes both renderers light-only.
  It was cited as decisive before §8.1-1 was re-read.

Still open, and deliberately not guessed at: what a real Linux CI image resolves `Arial,
sans-serif` to. No container runtime exists on the machine that measured this. It is answerable in
one command the day one does, and it bears only on the rejected option.

### 8.5 One more carrier, with a caveat

The `.sentences` carrier beside each ladder figure — "N ways this can be satisfied" — is the closest
thing to generated prose in the tree, and it is excellent for OR-rooted decisions. It **degrades on
conjunctions**: an `And` cross-joins into a single product, so the root exemption's file reads "1
way this can be satisfied" with all five conjuncts run together and no connective **[G]**. Ruling
(part of E11): use `.sentences` for OR-rooted decisions only, and never as a substitute for the
ladder on an AND-rooted one.

---

## 9. E15 — the call to action

### The constraint

**The live-deployment claim cannot be made from this repo.** `p7-mcp.sh` refuses any non-loopback
`JL4_GO_SERVICE_URL` with exit 3 citing HG2, accepting exactly `localhost`, `127.0.0.1`, `::1`,
`[::1]`, `0.0.0.0` **[G]**. `known-defects.json`'s `mcp` group has `"measured_on": null` and an
empty defect list, with a comment saying it is empty on purpose because no service was reachable
**[M]**. The wizard's deployment half is prepared and not performed **[G]**. Nothing in the tree
ties a Reg CF deployment to any named host.

### The ruling

The CTA is **"here is how to stand it up yourself"**, end-to-end verifiable, and it never says the
corpus is deployed. It renders at two levels:

- **`p7-mcp` receipt shows a loopback deployment happened** → the measured tool list, read from the
  receipt/artifacts, with a `curl` for each.
- **otherwise** → the standing-up instructions plus
  `**ABSENT.** No deployment was reached in this run, so no tool list is reported. Deploying to a host other people can reach is outward-facing and is gated (HG2); this document therefore describes how to run it on your own machine and claims nothing about a hosted service.`

It must **never** name `jl4.legalese.com` or `dev.jl4.legalese.com`.

**Correction, 2026-08-03: "the measured tool list" above is not available from the receipt, and the
first branch printed a count under that label.** The `p7-mcp` receipt of run
`2026-08-03-3f45e62b-002` carries `tools=10`, `corpus_tools=6`, `functions=6` and **no metric holding
the names** — the names are printed only into that leg's log artifact. The renderer read
`metrics.tools` and rendered `Tools the deployment reported: \`10\``, which labelled a number as a
list and used the total where the leg's own reason is careful to say the module contributed 6 and
the remaining 4 are jl4-service's generic file-browsing tools.

**Closed 2026-08-03.** The interim fix — print both counts and say where the names live — left the
narrative free to enumerate the tools by hand, which it did, describing **five** kinds against six
exports. `p7-mcp.sh` now records `tool_names` as a metric on both the `PASS` and the count-mismatch
receipt, the renderer prints the measured list, and the CTA prose enumerates nothing. Adding the
metric touches `p7-mcp.sh`, which the earlier note declined to touch as neighbouring discipline;
that was the wrong call, because the alternative was a hand-typed list in a document whose entire
argument is that hand-typed lists go stale — and it did, within one build.

### Three named traps the CTA must route around

Each was measured elsewhere and each would make the CTA wrong:

1. **The deploy POST answers 202 with `status: "compiling"`, asynchronously.** A `tools/list`
   issued in that window returns HTTP 200 carrying only the service's four generic tools and none
   of the module — a green-looking zero-tool result that blames the corpus. The CTA **must** poll
   `/deployments/<id>` for `.status == "ready"` first **[G]**.
2. **`GET` on any `.mcp` route is HTTP 405 by design** (MCP Streamable HTTP is POST-only); a `curl`
   without `--fail` swallows it **[G]**. Every CTA `curl` on a `.mcp` route carries `--fail`.

   **Amended 2026-08-03: `--fail` is wrong on the polling step, and the CTA had it there.**
   `GET /deployments/<id>` answers **404 while the deployment record does not yet exist** — measured
   in this run's own `p7-mcp` log, `HTTP 404 state=unreachable functions=0 (waited 0s)` as the first
   poll — and `p7-mcp.sh` deliberately omits `--fail` for exactly that reason. A reader following
   the CTA verbatim got a non-zero exit on the normal first answer. `--fail` belongs on every
   `.mcp` call and on the deploy POST; it does not belong on the poll.

3. **Two documentation defects must not be copied.** `GET /webmcp.js` is **404, not the documented
   301** — the string does not appear in `jl4-service/src` at all; and `data-tools=auto`'s
   threshold is **≤ 10, not ≤ 20** **[G]**. The CTA uses `/.webmcp/embed.js` and does not quote a
   threshold it has not read from the source.

   The CTA also does not claim to have exercised the browser embed. It says so at the site: the
   `data-scope` block is documented rather than measured here, and the run's own evidence covers
   the JSON-RPC endpoint only.

4. **The trace does not quote the regulation, and the CTA used to say it did.** A reasoning node
   carries the resolved name and a pretty-printed expression; there is no citation field. What
   makes this corpus's trace readable as law is that its field names ARE the regulation's words —
   a property of the encoding, not of the tool. The CTA now states that dependency instead of
   claiming the tool supplies it, and quotes the service README's own sentence for the route. Note
   also that `?trace=full` is a **REST** parameter on
   `/deployments/{id}/functions/{fn}/evaluation`, not something to append to the `.mcp` JSON-RPC
   endpoint the previous step introduced; the CTA had the two adjacent with no route in between.

And the CTA must not hide the three limitations that a reader will otherwise discover as breakage:
`/state-graphs` returns `{"graphs":[]}` for the deployed façade because `extractStateGraphs` does
not follow `IMPORT`; the façade's `/ladder` has two leaves and `/query-plan` returns empty `asks`
and `inputs`, which is a structural consequence of proper single-sourcing rather than an oversight;
and a client must join query-plan and ladder responses on `unique`, not `atomId`.

**Amended 2026-08-03: "whose intersection is empty" was a borrowed claim, sharpened.**
`PROJECTIONS.md` measures an empty intersection **inside a single `/query-plan` payload** (the
`ranked` atom ids against the embedded ladder's), and concludes a client cannot join those two.
`ts-apps/regcf-wizard/README.md` measures **across two responses** and names the working key,
`unique`. The CTA took the cross-response framing from one source and the "empty intersection"
from the other, producing a generalisation neither had measured — and the literal intersection
across two responses is not empty, because the query-plan payload embeds the ladder. The narrative
now says only what both sources support: join on `unique`, because the two sides number their atoms
independently. This is the user-level `CLAUDE.md` rule 2 failing inside the document written to make
that failure impossible.

**And a fourth trap, added 2026-08-03: a stale deployment of the same id.** `dev-start.sh`'s default
store is `/tmp/jl4-store`, deployment ids are reused, and a `regcf` left there by an earlier session
answers `ready` **immediately** — so trap 1's poll, which exists to stop you reading a half-compiled
deployment, does not fire, and you read somebody else's corpus with no error anywhere. Reproduced:
a stale deployment served five module tools where the current façade has six, and the missing one
was the temporal control the CTA calls out by name. The CTA now starts the service with a fresh
`JL4_SERVICE_STORE`. (`p7-mcp.sh` was never exposed: its deployment id carries the run id.)

---

## 10. What this is NOT

1. **Not a second audit report.** It cannot make a claim `report.md` cannot support. Mechanically:
   every run fact is placeholder-resolved from the same journal fold (§3.5, pinned by §11's
   equality test); narrative prose may not carry run-status vocabulary (§6.5); and a section whose
   licensing receipt is absent or non-`PASS` renders the receipt's status, not the narrative's
   confidence (§4.2).

2. **Not a second place where numbers are typed by hand.** Every digit-run in the finished document
   is placeholder-resolved from the journal or is a citation whose source line is re-read and
   matched at render time (§6.2). Figures from `README.md`/`PROJECTIONS.md` prose are banned
   outright, with the measured drift that motivated it (§6.4).

3. **Not a relaxation of P9's invariant.** `etc/go/report/template.md` and
   `etc/go/report/render-report.mjs` are not opened by this build. The explainer's own template
   gets the same digit check and its own CI step (§11).

4. **Not legal advice, and not a substitute for the regulation.** The document is an explanation of
   an encoding of a rule, and every claim about the rule is a citation into the rule. Where the
   encoding takes an interpretive position the source does not compel — the assurance ordering, the
   half-open resale interval, the exhaustive/exclusive reading of the investment-limit limbs — the
   explainer says so at the site, in the corpus's own words.

5. **Not published.** Rendering into a run directory is not publication. Copying it anywhere a
   third party can see it is P10 and is HG2's. This build adds no outward-facing surface and no
   network call.

6. **Not a fork register, and not evidence one exists.** Reg CF has **zero** `AMBIGUITY` markers and
   no fork register; the paths `subject.json` declares under `denovo/` do not exist on this branch
   **[M]**, per its own comment. The explainer must not imply otherwise. Its interpretive-choice
   material comes from prose at the site and from the corpus's own honest-limits list.

7. **Not a replacement for the corpus's `README.md`.** Those documents argue with a specific
   external page and carry the encoding's own long-form reasoning. The explainer cites them for
   arguments and never for figures (§6.4).

8. **Not a place where an unreviewed claim can look reviewed.** Every unreviewed section is marked
   three times over (§5.6), and today — with zero enrolled signers **[M]** — that is every section.

---

## 11. Verification plan

_Landed 2026-08-03 alongside the build, except where a row says otherwise. `node
etc/go/selftest.mjs` runs all of it with no binary and no network._

**Selftest, `etc/go/selftest.mjs`.** New assertions:

| #   | assertion                                                                                                                                                                                                                                                     |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| V1  | **the two folds agree** — both renderers over one fixture journal containing a resume, a replayed receipt, a `BROKEN` row and a post-`run_end` `stage_end`, producing identical verdict and per-stage status map (§3.5)                                       |
| V2  | **every declared stage sequenced after `p6-tests` is in `gated_by_HG1`** — the assertion that does not exist today (§3.3)                                                                                                                                     |
| V3  | an unreviewed narrative section renders the draft banner, and the document header's draft count matches the number of banners — **landed**                                                                                                                    |
| V4  | narrative drift, source drift and review drift each render their banner and each degrade the receipt (§5.4) — **landed at the unit level** (`driftFor` over a fixture, all three classes); the end-to-end rendering of each banner is not separately asserted |
| V5  | a citation that does not resolve renders `⚠ CITATION DOES NOT RESOLVE` and degrades the receipt; a resolving one renders clean                                                                                                                               |
| V6  | a bare digit-run in a narrative file that is neither placeholder nor citation fails the lint at file:line                                                                                                                                                     |
| V7  | a reserved status word in a narrative file fails the lint (§6.5)                                                                                                                                                                                              |
| V8  | a markdown construct outside §7.2's subset fails the lint                                                                                                                                                                                                     |
| V9  | the rendered HTML escapes quotes in every attribute context (§7.3) — **landed** as a check on `escapeAttr` and on a rendered `title=` attribute, not as a sweep over every attribute the renderer emits                                                       |
| V10 | an explainer template containing a bare digit-run exits 4 with `TEMPLATE DEFECT`                                                                                                                                                                              |
| V11 | an unresolved `{{…}}` exits 4                                                                                                                                                                                                                                 |
| V12 | **rewrite** `selftest.mjs:877-884` as a set comparison against the named never-replaying stages, not a hard-coded count (§3.4)                                                                                                                                |

**CI, `.github/workflows/pr-checks.yml`.** Two new steps, mirroring the existing template check's
two-assertion shape (assert no `TEMPLATE DEFECT` **and** assert the renderer got far enough for the
check to have run):

- the **explainer** template carries no transcribed measurement;
- `go.sh plan --milestone g1` names `p9-explain` (the existing self-description step greps for
  stage names and would otherwise go stale silently **[G]**).

**Formatting.** `.prettierignore` does not exclude `etc/`, and `package.json` runs
`prettier --check .` **[M]**. Every new `.mjs`, `.md` and `.json` under `etc/go/` — including every
narrative file — must be formatted with `npx prettier@3.4.2`.

**Skill drift.** `check-skill-drift.mjs` compares commands and flags, not stage names **[G]**, so
adding the stage does not trip it — but `SKILL.md`'s worked-example output lists stage rows and
nothing machine-checks it. Update it in the same PR.

---

## 12. Sequencing

**v0 — the discipline, proved end to end.** Stage + gate + wiring (§3); provenance model and drift
detection (§5); the citation grammar, its lint, and the reserved vocabulary (§6); `md-lite` and the
two renders (§7); ladder figures inlined (§8.1); DMN tables extracted with the dmnmd cross-check
(§8.3); LTS environment-conditional (§8.2); BPMN as fidelity material (§8.4); the CTA (§9); the
verification plan (§11). Reg CF's narrative drafted, checked in, and — with no signer enrolled —
rendering entirely as draft.

**v1 — the pictures.** The diagram-interchange serializer for BPMN and the DMN DRG (§8.4, E19), and
whatever E18 rules about versioning.

**v2 — the second subject.** The BNA, which is what tests D3's claim that nothing here is
Reg CF-shaped. Explicitly out of scope now.

---

## 13. Open rulings

- **E18 — versioning.** Inherits `SI-R7` (_per-run immutable, or a living document?_) and does not
  pre-empt it. One observation feeds it: the explainer answers it **twice, differently, by
  construction** — its narrative is checked in and versioned by git, so it is a living document;
  its renders live in run directories and are per-run immutable. If `SI-R7` lands on "per-run,
  immutable, latest linked", the explainer already satisfies it. Owner: whoever rules `SI-R7`.
- **E19 — where the diagram-interchange serializer belongs.** In `etc/go/lib/` where only the
  explainer sees it, or in `l4 export` beside the emitters that already compute the coordinates,
  where the IDE, the wizard and any future consumer would get it too? The second is obviously better
  and is a much bigger change. Owner: Meng, at v1.
- **E20 — whether the narrative should be generated rather than drafted.** D1 rules it drafted for
  now. The `.sentences` carrier and `l4 nlg` both produce prose, and neither is lay-readable — the
  NLG golden linearises `#ASSERT` directives, which is a fine "what we tested, in English" exhibit
  and useless as narrative **[G]**. Recorded so a later reader does not re-discover it as an idea.

---

## 14. The 2026-08-05 rulings: the triple task, the spine, and the fabrication boundary

Rulings from Meng on 2026-08-05, after reading the first real `g1` explainer, plus one of my own
(E31) forced by the work of discharging them. They do not replace §§1-13; they change **who the
existing sections are written for** and add two slots. Numbered from E21 and appended rather than
woven in, because §§1-13's numbers are cited from `SPEC.md` §P9.1 and from `ORCHESTRATOR.md`, and
renumbering a cited section is a breaking change for no benefit.

**Implementation status, per ruling, because "none of them" stopped being true within hours of
being written.** All of it shipped on 2026-08-05, within hours of the ruling.

| ruling                        | status                                                                                    |
| ----------------------------- | ----------------------------------------------------------------------------------------- |
| E28 — `S9`, the forks slot    | **built** — renderer, heading, deposit schema, subject register, gate entry               |
| E29 — the reading order       | **built** — the template renders context → applications → mechanism                       |
| E30 — `S10` and the glossary  | **slot and content built; the SHARING mechanism is not.** See §14.10                      |
| E31 — re-anchoring is a claim | **built** — it is a rule about an operation that was performed                            |
| E21-E27                       | **not built.** No persona structure, no illustrative-block marking, no screenshot capture |

Each subsection restates its own status in more detail; where a subsection and this table disagree,
believe the subsection and fix this table. That instruction is not decorative — this paragraph has
now been wrong twice, both times by asserting "none of these is built" after something was.

### 14.1 E21 — three jobs, not two

**E21 — the report has THREE jobs, not two. ANSWERED 2026-08-05 (Meng).** D2 and the dual brief
had it explain **the law** and **this law's encoding**. A third is now required: **L4 itself**.
Every reader is assumed a novice in all three, so each report doubles as a **mini-tutorial in the
language**. This does not add a section; it changes who the existing sections are written for.
Consequence for §6's licensing grammar: a claim about _the law_ is licensed by the source text, a
claim about _the encoding_ by the encoding, and a claim about _the language_ by `doc/**` or by the
construct's own appearance in the report — a tutorial sentence with no construct on the page to
point at is a feature tour, which E22 forbids.

### 14.2 E22 — the spine, and the road not taken

**E22 — the SPINE. ANSWERED 2026-08-05 (Meng).** Each report picks **one** interaction with the
law — the **most common** one, the core decision and/or the core process — and organises itself
around it. Language features are explained **where they appear in the spine**, at the moment the
reader meets them, and not as a systematic tour of L4. A feature that does not appear in the
spine does not get taught. The spine is a per-subject choice and belongs in the subject's
manifest, so the renderer can state which interaction was chosen and a reviewer can disagree
with the choice.

**And the road not taken is named. AMENDED 2026-08-05 (Meng).** Choosing one interaction to
walk in depth risks a reader concluding the system only handles that one. So the other
motivations for coming to this law — the less common questions, the other personas, the
provisions the spine passes over — are **listed**, briefly, with the remark that **they receive
the same treatment in the L4 system and can be queried the same way, and are omitted here only
for brevity**. A list plus that sentence costs a paragraph and forecloses the misreading.

**The list is DERIVED, not written.** "These are handled too" is a coverage claim, and this
document does not print unlicensed claims. So the non-spine list is generated from the
encoding's own decision surface — the decisions and exported entry points that exist but are
not on the spine — rather than hand-authored. That way it cannot overclaim (it can only name
what is actually encoded), it cannot silently go stale as the encoding grows, and a reader who
doubts it can query any item on it and find out. Where a provision is in the source but NOT
encoded, that is a limit and belongs in Limits, not in this list.

### 14.3 E23 — verbosity permitted, repetition expected

**E23 — verbosity is PERMITTED and repetition across reports is EXPECTED. ANSWERED 2026-08-05
(Meng).** Two instructions that both cut against the usual instinct, so both are recorded
explicitly. (a) The author **may wax verbose** and go into depth where the spine warrants it;
brevity is not a virtue here. (b) **Every report is read alone.** A reader cannot be assumed to
have read any other report, so a report must **not** cross-reference a sibling for its basics,
and **the same material appearing in five reports is correct, not duplication to be factored
out.** Do not introduce a shared "about L4" chapter and link to it. This reverses DRY on purpose:
the unit of delivery is one report, not the corpus.

**CLARIFIED 2026-08-05, because E30 needs the boundary to be exact: E23 forbids sending the
reader AWAY, not authoring text once.** The two are different operations that a careless reading
runs together:

- **Reference** — a report says "see the Reg CF report for what a fork is". **Forbidden.** The
  reader does not have that report, and now cannot finish this one.
- **Inclusion** — a block is authored once and rendered **verbatim into every report that
  declares it**, so the words are physically present in each. **Permitted, and preferred.**

What E23 protects is that a report is complete in the reader's hands. Inclusion satisfies that in
full. Re-drafting the same explanation independently for each subject does not merely cost more —
it is actively **worse**, because five slightly different definitions of "fork" across five
reports is a defect the reader has no way to detect. E30 governs which content qualifies.

### 14.4 E24 — the spine walked twice, through personas

**E24 — the before/after narrative, through personas. ANSWERED 2026-08-05 (Meng).** The spine is
walked twice. **First in a pre-L4 world**: a small cast of user personas meets the
legislation as it is published, and the report is honest about what they actually do — read the
prose, build a spreadsheet, phone a lawyer, guess. **Then in an L4 world**: the same personas,
the same questions, and how the affordances change with digital support. The comparison IS the
argument, and it is made concrete by persona rather than asserted in the abstract.

### 14.5 E25 — the exhibits

**E25 — the exhibits. ANSWERED 2026-08-05 (Meng), scope; engineering NOT built.** The L4 half of
E24 is shown, not described: the **diagrams** the pipeline already emits (ladder, LTS, BPMN,
DMN); the **wizard application** that falls out of the encoding, **with screenshots**; **worked
conversations over MCP**; and the **exports and extractions** — OpenFisca, DMN, BPMN — each
presented as "here is the same rule, arriving in a system that already exists". Status, stated
plainly: the diagrams and the exports are produced by legs that run today; **wizard screenshot
capture does not exist and is new engineering** (a headless browser capture, deposited as a run
artifact with a receipt like any other, so a screenshot is attested rather than pasted).

### 14.6 E26 — the fabrication boundary

**E26 — THE FABRICATION BOUNDARY. ANSWERED 2026-08-05, the ruling this document most needs.**
E24's personas and E25's MCP conversations are **invented**. Everything else in this document
obeys a rule that a claim with no licence cannot be printed, and invented material collides with
it head-on. The resolution is not to relax the rule but to make the two kinds of content
**structurally distinguishable**:

1. Invented material is **visibly marked as invented at the point of use**, in the rendered
   document, not only in a preamble a reader may skip.
2. Invented material **never carries a citation**. The citation grammar means "re-read at render
   time and matched"; attaching it to a hypothetical would poison the one signal the reader has.
3. Invented material **never asserts a measured number**. A persona may be told "you may invest
   up to X" where X is a placeholder resolved from the encoding; the persona may not be given a
   figure the report has not otherwise licensed.
4. A conversation that shows a **real tool's real output** and one that **illustrates what such a
   conversation would look like** are different artifacts and must not be confusable. If a
   transcript is real, it is an artifact of the run with a receipt; if it is illustrative, it says
   so where it sits.
5. The lint enforces what it can — the reserved-status-word check already refuses run-status
   vocabulary in narrative; an analogous check should refuse a citation inside a block flagged
   illustrative.

### 14.7 E27 — meet them where they are

**E27 — register: "meet them where they are". ANSWERED 2026-08-05 (Meng).** Technical material,
and the **low-code CNL** material especially, is introduced in **relatively simple language**. The
reader is a domain expert, not a programmer, and the encoding style exists precisely so that they
need not become one. Where a term of art is unavoidable it is glossed at first use, in the same
sentence, without sending the reader elsewhere (which E23 forbids anyway).

### 14.8 E28 — interpretive forks get a structural slot

**E28 — interpretive forks get a STRUCTURAL SLOT, not a drafter's discretion. ANSWERED
2026-08-05.** Meng recalled, on 2026-08-05, that the explainer already covers interpretive
ambiguities and alternative interpretations. Measured against the real `g1` run of
2026-08-03: it half does, and the half it does not is the half that matters.

**What is there.** One genuinely good passage, in "How much may be raised", opening _"The
statute is ambiguous, the regulator glossed it twice, and the encoding resolves neither"_ —
the §4(a)(6)(B) greater-of/lesser-of problem, argued from the source. **[M]**

**What is not.** `fork` does not appear in `explainer-template.md` at all: there is **no spine
slot** for interpretive forks. Across the whole rendered document, ambiguity is discussed
**twice, both in that one passage**. And Reg CF has **no committed fork register** for a slot to
render from. **[M]**

So the coverage exists as **prose a drafter happened to write**, not as **structure fed by a
register** — which means it is at the drafter's discretion and will silently go missing on the
next subject. That is precisely the failure mode the spine's ABSENT-with-a-reason design exists
to prevent, and Reg CF escaped it only because whoever wrote that section noticed.

**Ruled:** interpretive forks get their own spine slot, fed by the subject's
`fork-register.json` (schema `specs/todo/single-instruction-demo/schemas/fork-register.schema.json`, R4's one-`Interpretation`-
record shape). Where a subject has no register the slot renders **ABSENT with the reason**, like
every other slot, so "this encoding registered no ambiguities" becomes a visible claim someone
can disagree with rather than an absence nobody notices. Where a register exists, each fork
renders with **both readings, the reading taken, and why** — the fields R4 already requires.

This is newly buildable: the de novo run started 2026-08-05 produces the first
`fork-register.json` Reg CF has ever had. Note the honest bound the register itself carries —
**completeness is unfalsifiable in principle**, so the slot may claim internal consistency and
must never claim exhaustiveness.

### 14.9 E29 — the reading order: context, then payoff, then mechanism

**E29 — the spine LEADS with the pre-L4 world, then the applications, then the encoding and the
language intermingled. ANSWERED 2026-08-05 (Meng).** E24 established that the spine is walked
twice; E29 fixes the order of the walk and what sits between the halves:

1. **Before L4** — the world as it is. The personas of E24 meeting the legislation as published:
   reading the prose, building a spreadsheet, phoning a lawyer, guessing. This is context, and it
   comes first because nothing after it means anything without it.
2. **What becomes possible** — the L4-enabled applications, **immediately**: the wizard, the MCP
   conversations, the exports into systems that already exist, the diagrams. The payoff arrives
   before the mechanism, so a reader who stops early still leaves with the thing that would make
   them want more.
3. **How it is done** — the encoding walked alongside the language tutorial, **intermingled rather
   than sequential**. Not "here is the encoding, now here is L4", but the encoding explained in
   L4's terms as each construct is met, which is E22's teach-it-where-it-appears rule applied to
   the ordering of the document rather than only to the choice of what to teach.

**Why this order and not the obvious one.** The instinct is to explain the language, then the
encoding, then what you can do with it — mechanism before payoff. That order serves the author,
who already knows why it matters, and fails the reader, who does not yet. It also front-loads
exactly the material E27 says is hardest for a non-programmer, at the point where their motivation
is lowest.

**Interaction with §4.1's slot table.** Slot IDs are stable identifiers, not positions. E29 changes
where slots are RENDERED, not what they are called, and no slot is renumbered by it. The template's
order is the document's order; the table's order is historical.

**Status: BUILT 2026-08-05, as far as the parts that exist allow.** The template now renders
`orientation → cta → pictures → S10 → body → time → forks → limits → sweep → provenance`, and
`p9-explain`'s required-heading list follows it. No slot was renamed and no ID moved, exactly as the
paragraph above requires.

**What is built is parts 2 and 3, not part 1.** E29's opening — the personas of E24 meeting the
legislation as published, before any of this exists — depends on **E24, which is not built**. What
stands at the head of the document today is the existing orientation slot, which describes the law
and the parties but does not walk a persona through the pre-L4 world. So the order is right and the
first movement is thinner than E29 asks for; when E24 lands, it lands in a slot that is already in
the correct position.

**And the reorder was not free, which is the part worth recording.** Moving a section changes the
truth of every sentence that located itself by position. Three had to be repaired: orientation's
"the next section takes those in turn" (the next section is no longer the rules), its "the sections
below take seven of the eight", and the call-to-action's "the **How much** section above". The
house style of referring to sections **by name** — which most of the deposit already used — is what
made this three sentences rather than thirty, and is the rule to keep following.

### 14.10 E30 — "How this process works", a glossary, and the shared-content rule

**E30 — the report explains its own process, defines its own jargon, and may do both from text
authored once. ANSWERED 2026-08-05 (Meng).** Two problems, one ruling.

**The first problem is jargon.** The existing explanations assume the writer's context. _Encoding_,
_projection_, _fork_, _spine_, _slot_, _fidelity_, _golden_, _deontic_, _regulative_ and
_constitutive_, _ladder_, _corpus_, _replay_, _de novo_, _gate_ — every one of these is a term of
art this project uses freely and a new reader has no purchase on. E27 already requires simple
language and glossing at first use; E30 adds the **reference** a reader returns to when the gloss
has scrolled off.

**The second problem is that the process is invisible.** A reader who does not know what
formalisation IS cannot judge whether it was done well. So the report explains **the steps, the
slots, and the motivation for each** — and the motivation is the load-bearing half. A slot
described without its reason is ceremony; a slot described with it ("this one exists because the
coverage it holds used to depend on a drafter noticing") teaches the reader what to be suspicious
of.

**Ruled: a slot, `S10`, "How this works, and what the words mean."** Rendered at the head of E29's
third part, where the reader first needs it. It carries the process narrative and the glossary
together, because a glossary detached from the process it names is a word list.

**This does not reopen E22.** A glossary is a **reference**, not a teaching path: it is skippable,
non-linear, and consulted on demand. E22's rule that features are taught where they appear in the
spine is untouched — the glossary is where a reader who forgot goes to look up, not where they are
sent to learn.

#### The shared-content rule

Text that is **subject-independent** may be authored once and **included verbatim** in every report
that declares it. Text that is **subject-dependent** may not. The test is mechanical: **does the
sentence mention this body of law?** "A fork is a place where the source does not settle a
question" is shared. "Reg CF's three forks are…" is not.

This is E23-compatible by the clarification recorded in §14.3: shared blocks are **included**, not
referenced, so every report still stands alone in the reader's hands. The gains are consistency
first and cost second — five independently drafted definitions of "fork" is a defect the reader
cannot detect, and re-authoring boilerplate every run pays tokens for the privilege of introducing
that defect.

**The cost, which must not be wished away: a shared block's blast radius is every report.** An
unreviewed or stale shared section propagates silently into all of them, which is strictly worse
than a per-report error a reader might catch in context. So sharing does not buy an exemption from
§5's provenance model — it **needs it more**:

1. A shared block carries **its own provenance record and its own review state**, exactly as a
   per-subject narrative section does.
2. Every report that includes one **names the version it included**, so a report rendered against
   an older shared block is detectable rather than invisible.
3. Its citations resolve **against sources that are themselves subject-independent** — `doc/**`,
   the language reference, this spec. A shared block citing `regcf.l4` is a category error and
   should fail the lint.
4. A shared block is **never** the place a measured number lives. Numbers are per-run and per
   subject; a shared block that quotes one has already gone stale for every other report.

**Status: the SLOT and its CONTENT are BUILT; the SHARING is NOT. 2026-08-05.**

Built: `S10` is a spine slot with a renderer (`howItWorksSection`), a template heading, optional
manifest validation, a `p9-explain` required-heading entry, and Reg CF content — process narrative,
slot-by-slot table with the reason for each, and a glossary of the fifteen terms this ruling lists.
Rendered under E29's order at run `2026-08-05-b4fdf406-001`: 22 sections, 92 citations, none
unresolved.

**Not built, deliberately: the inclusion machinery.** There is no shared-block store, no
include-with-version, and no lint refusing a subject-dependent citation inside a shared block. The
content is written to be shareable — it names no regulation, and its two citations resolve against
`etc/go/go.sh` and `etc/go/phases/p6-tests.sh`, both subject-independent — but it lives as an
ordinary per-subject narrative file with an ordinary provenance record.

**Why stop there.** Inclusion pays off at the SECOND subject and costs at the first. One subject
with a shared-block mechanism has all of the machinery and none of the consistency benefit the
mechanism exists for, and a half-built store is worse than either end: it looks like sharing works.
The move, when a second subject arrives, is a file move plus a manifest key — which is the whole
reason the content was written subject-independent now rather than retrofitted later.

**One thing E30 did not anticipate, found by building it.** The reserved-status-word lint (§6.5)
bans `DEGRADED`, `SKIPPED` and their case variants from narrative prose — which makes a glossary
entry for _gate_ unable to name the statuses it is defining. Fenced blocks are exempt from the lint,
so the vocabulary can be shown in one; the constraint is real and worth knowing before drafting.

**And one defect the build surfaced, now a lint.** S10's deposit used `##` for its sub-sections,
putting five headings at the same level as `## The rules` and breaking the printed outline. The
spine slot owns `#` and `##`; a narrative file's own headings start at `###`. This is now
**N-HEADING** in `lintNarrative`, with a selftest, because it was invisible until the page was
printed and certain to recur. A generated artifact inlined into a slot can do the same thing and
N-HEADING does not reach it — see the outstanding `regcf-corpus.dmn.md` case.

### 14.11 E31 — re-anchoring a provenance record is a CLAIM, not a chore

**E31 — clearing `SOURCE MOVED` asserts a re-reading, and may only be done after one. RULED
2026-08-05 (mine, not Meng's — forced by performing the operation and noticing what it would have
let me get away with).**

When a source file changes, every narrative record drafted from it stops matching and each affected
section renders `SOURCE MOVED` (§5.3). Updating the record's `drafted_from[].sha256` clears that
banner. Call it **re-anchoring**.

**Re-anchoring asserts: somebody re-read this prose against the new source and it still holds.** It
is a factual claim about work performed. A three-line script can do it in a second, which is
precisely the problem — it is the cheapest lie in this design to tell, it silences the one alarm
that catches semantic inversion (§6.2), and nothing downstream can tell a re-anchor that followed a
re-reading from one that did not.

So:

1. **Re-anchor only after re-reading**, section by section, against the source as it now stands.
   What counts as re-reading is checking each factual claim in the section, not skimming the diff.
2. **`drafted_on` does NOT move on a re-anchor.** It is the date the prose was written, and it
   resolves `{{as_of}}` (§6.2) — so bumping it on a section whose sentences did not change asserts
   that section's dollar figures were re-checked against the law that day. Re-reading prose against
   moved _code_ establishes nothing about the _law_. Move `drafted_on` only when the sentences
   moved. **MEASURED 2026-08-05:** exactly three of the twenty-one Reg CF narrative files use
   `{{as_of}}`, and all three are about the investment caps — the figures where the distinction
   bites hardest.
3. **Re-anchoring never touches `review`.** A re-anchor is not a signature. A section that was
   unreviewed stays unreviewed and keeps its draft banner; a section that was `reviewed` and has
   gone `stale` is not un-stale-d by re-anchoring, because the reviewer, not the drafter, is the
   one whose claim went out of date.
4. **Re-anchoring a CITATION is a different operation and is safe.** Moving `#L722` to `#L760`
   because lines shifted is verified by the checker itself — it either resolves against the new
   window or it does not. That may be done mechanically and in bulk. It is only the record-level
   source hash, which no checker validates, that carries a claim.

**What discharged it here, so the bar is legible rather than aspirational.** The 2026-08-05
re-anchor of the Reg CF narrative re-read all twenty-one sections against their current sources
using nine read-only agents, each finding reported with `file:line` evidence, and each finding then
handed to a second agent whose instruction was to refute it. Two findings were raised and both were
refuted — correctly, having been drawn against committed `HEAD` while the repair sat in the working
tree. Confirmed findings: zero. **That number is the point of the exercise and not a formality: had
it been non-zero, the re-anchor would have been a lie in exactly as many places.**

---

_What §§1-13 do not claim: I built nothing, ran no `cabal`, `l4` or `npm` command, and made no
commit other than this spec and its pointer in `SPEC.md` §P9.1. Every **[M]** in §§1-13 is a read
or a count against the tree at `5f79ff64` on 2026-08-03; every **[G]** is carried from the four
ground-truth research passes that preceded this spec and is cited to the file:line it came from,
not re-executed here. Where those two disagree with each other, believe neither and measure._

_**§14 was written on 2026-08-05 and its evidence is scoped separately**, because the sentence
above would otherwise vouch for measurements taken two days after it was written — which is
exactly the drift this document spends §6 preventing. §14's **[M]** marks are reads against the
tree at `47ea0f42`, plus the `g1` run of 2026-08-05 (`2026-08-05-d912648b-001`), which is the
first run of the pipeline over the post-anniversary Reg CF corpus and the source of the
`all 8 spine slots present` count and the 82 findings §14.8 relies on. **Which of §14's rulings are
built is a table in §14's preamble, and that table is the copy to believe** — do not restate it
here, or in a commit message, or in a sibling spec. A blanket "§14 is unbuilt" stopped being true on
the day it was written, and the count of built rulings has already moved twice since._
