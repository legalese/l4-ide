# The pipeline as an artifact graph: phases, witnesses, and what the labels are for

_Status: **rulings recorded; four of thirteen implemented.** Written 2026-08-20 on branch
`mengwong/sg-succession`, out of the conversation that added the pipeline's second subject
(`sg-succession`) and found that several of its central nouns name the wrong things._

_What IS implemented, and where: **R1** (`corpus` → `encoding`, commit `dd55a6c8`), **R7** and
**R8** (cross-run replay with a closed ineligible list, and borrowed artifacts copied rather than
referenced, commit `41a7b5ac`), **R10** (the three senses of "corpus" deliberately retained), and
**R12** (`encoding.state`, and `go.sh new-subject` on top of it — see §3.12 for the third closure
that neither candidate had). Everything else on this page is a decision, not a description: there
is no artifact store, no read-set, no per-phase comparator and no subject-level report. What would
make the rest of the present tense true is named per ruling in §3._

_Why this document exists at all: the rulings below were reached in conversation and existed
nowhere else. `CLAUDE.md` §4 — a decision is recorded in its owning document or it is not
decided — and the specific failure it guards against had already happened once here, when a
report committed to `legalese/canon` described an encoding that no longer existed because nobody
had a document saying what the report was an account **of**._

---

## 1. One-line summary

The pipeline's stages already declare a dependency graph and do not use it as one; its nouns name
positions in a history (`denovo` = "the second pass") rather than things (`natlang_sources` = "the
fetched legal text"); and its artifacts are treated as build products to be clobbered when they
are in fact **witnesses whose disagreement is the product**.

## 2. The distinction everything else follows from

**Intrinsic** — what a job _is_. An agentic download ran, sourcing legislation from SSO or
legislation.gov.uk or lawplain. An agentic research pass ran, looking for case law. An agentic
encoding pass ran, producing L4. Each consumed some artifacts and produced others.

**Extrinsic** — labels applied from outside, by counting: "the first time", "the second time",
"de novo", "cleanroom", "G1", "G2". These are facts about a subject's _history_. They are answers
to queries over the artifact graph.

A phase-1 download is a phase-1 download whether it is the first or the fifth. Nothing about the
job changes; what changes is what else exists to compare it against.

**The error this spec exists to stop: extrinsic labels are currently stored as intrinsic
configuration.** `subject.json` has a `denovo` object — a schema key named after an ordinal. The
milestone flag `--milestone g1|g2` selects a stage set by a label that denotes a tooling
capability. Both make a subject's _position in its own history_ something you declare rather than
something the graph answers.

## 3. Rulings

| ruling | status                     | one line                                                                                                |
| ------ | -------------------------- | ------------------------------------------------------------------------------------------------------- |
| R1     | **ANSWERED · IMPLEMENTED** | the subject's L4 is `encoding`, not `corpus`, §3.1                                                      |
| R2     | **ANSWERED**               | the fetched legal text is `natlang_sources`; `denovo` is deferred, not half-renamed, §3.2               |
| R3     | **ANSWERED**               | phase identity is intrinsic; ordinals are extrinsic and are not schema keys, §3.3                       |
| R4     | **ANSWERED**               | blindness is a recorded read-set, not a flag; freshness is derived from it, §3.4                        |
| R5     | **ANSWERED**               | a diff means a different thing per phase, and an encoding diff is a fork only if upstream matched, §3.5 |
| R6     | **ANSWERED**               | artifacts are witnesses: they accumulate and are compared, not clobbered, §3.6                          |
| R7     | **ANSWERED · IMPLEMENTED** | replay crosses run boundaries, except for a closed list of stages, §3.7                                 |
| R8     | **ANSWERED · IMPLEMENTED** | a run directory stays self-contained; borrowed artifacts are copied, §3.8                               |
| R9     | **ANSWERED**               | G0–G4 are capability milestones, not lifecycle phases, and should stop being run labels, §3.9           |
| R10    | **ANSWERED · IMPLEMENTED** | three other senses of "corpus" are retained deliberately, §3.10                                         |
| R11    | **OPEN**                   | if artifacts are equal witnesses, the HG1 blessing must become a first-class edge, §3.11                |
| R12    | ANSWERED 2026-08-20, §3.12 | a subject may declare `encoding.state: "unwritten"`; `go.sh new-subject` scaffolds one, §3.12           |
| R13    | **OPEN**                   | reporting is run-oriented; a subject-level fold is needed, and it is not a union, §3.13                 |

### 3.1 R1 — the subject's L4 is `encoding` — ANSWERED, IMPLEMENTED

"Corpus" was doing four jobs: the subject's L4 modules, the repository of encodings
(`legalese/canon`, "a corpus of L4 encodings"), the fetched legal text, and an external legal
database (lawplain's "Singapore legal corpus"). The first had the worst word for it — an encoding
is not a corpus of anything — and the overloading made _"did the agent read the corpus?"_
unanswerable, because an encoding agent always reads the fetched text and may or may not read a
prior encoding.

`encoding.main` / `.wizard` / `.modules`; `GO_S_ENCODING*`; `GO_ENCODING_FILES`. Verified as a
pure rename: `go.sh plan` byte-identical for both subjects including the gate digest.

### 3.2 R2 — the fetched legal text is `natlang_sources` — ANSWERED, deferred

Named for the axis that matters: **natural language** versus the formal language it is encoded
into. `sources` alone was rejected because jl4-service's deploy API already uses `sources` for the
**L4 zip** — the opposite meaning.

`natlang_sources` also covers phase 1 and phase 2 together, which is correct: legislation and case
law are the same kind of thing, differing by role, and the source-bundle schema's `role` enum
(`current · historical · amendment · instrument · guidance · corroboration · scholarship`) already
spans both.

**Deliberately not yet applied, and this is not a half-finished rename.** `denovo` currently
bundles the sources together with modules, checks and a surface map. Renaming it wholesale would
move the category error under a better word. Splitting it needs §3.6's store first.

### 3.3 R3 — phase identity is intrinsic — ANSWERED

Phases are named by what they do: `source` (agentic download), `research` (agentic case-law
sweep), `encode` (agentic encoding), then the projections. Ordinals — first, second, "de novo",
"cleanroom" — are queries over history and appear in no schema key, no stage-set name and no
config value.

The immediate consequence: **"de novo" is the wrong word for the pass it currently names.** It
means _anew, from the beginning_, and the run it labels **requires a predecessor** — SPEC.md §8's
acceptance diff compares a blind re-derivation _against the committed encoding_. A descriptor whose
`denovo.modules` names a corpus module is refused outright. The vocabulary is inverted — the word
meaning "no prior" is attached to the pass that needs one, while the pass that genuinely has no
prior (§3.12) has no name.

_(This paragraph also read, when written: "a subject whose `encoding.main` does not exist cannot be
resolved at all". That was true on 2026-08-20 morning and is no longer — §3.12's `encoding.state`
gives exactly that subject a home, later the same day. It was a measurement of the tree offered as
evidence for a claim about vocabulary, and the vocabulary claim survives it, which is why the
sentence is retracted here rather than the ruling being reopened.)_

"Cleanroom" is the accurate term of art for the second pass and is **already used for it in this
repo**, two lines apart in the same file: `charities-cleanroom/README.md` reads _"encoded de novo"_
in its title and _"A cleanroom smoke test"_ in its first sentence. But see R4: even "cleanroom" is
trying to be a flag for something that is properly an edge, so the right move is not to rename
`denovo` to `cleanroom` — it is to stop needing either word.

### 3.4 R4 — blindness is a read-set, not a flag — ANSWERED

An encoding agent **always** reads _some_ corpus — the fetched legal text. So "blind" was only ever
meaningful against one sense of the word: blind to _prior L4 encodings of the same law_.

Three independent provenance edges had been conflated into one boolean:

| edge                                       | determines                                      |
| ------------------------------------------ | ----------------------------------------------- |
| which `natlang_sources` artifact was read  | **what law is encoded**, and hence its currency |
| whether a prior `encoding` was read        | **whether this is an independent witness**      |
| whether the `research` artifacts were read | **whether case law is accounted for**           |

Only the second is blindness. The first is not a quality at all — it is the dependency edge.

**Record the producer's complete read-set on each artifact, and all three fall out**, plus a fourth:

- **freshness** — compare the read-set against the newest artifacts available for those sources.
  Freshness is therefore _derived_, never stored, and "stale" keeps its exact Make meaning: a newer
  prerequisite exists.
- **independence** — does the read-set contain an encoding artifact for this subject?
- **comparability** — do two encodings share the same `natlang_sources` read-set? (See R5.)

A `blind: true` flag cannot express the fourth at all, which is what settles it.

### 3.5 R5 — a diff means something different per phase — ANSWERED

A uniform "diff the artifacts" layer would mislabel three different events:

| phase             | a diff between runs means  | it is                                                                            |
| ----------------- | -------------------------- | -------------------------------------------------------------------------------- |
| `natlang_sources` | the fetched text moved     | a **currency event** — the law changed, or the publisher revised it. Not a fork. |
| `research`        | new authority surfaced     | a **sweep finding** — routes to the external-modification register               |
| `encode`          | same sources, different L4 | an **interpretive fork** — the fork register's actual subject                    |

**An encoding diff is an interpretive fork only if the upstream read-sets were identical.**
Otherwise it is two encodings of two different texts, and calling their difference a fork is
spurious. This is the load-bearing constraint on the whole comparison layer, and it is why
content-addressing (R6) is a requirement and not an optimisation.

`etc/go/lib/denovo-diff.mjs` survives this reframing unchanged: it already compares **behaviourally**
— by what two encodings _answer_ over a battery, never by their text. It stops being "the G2
acceptance test" and becomes the general `encode`-phase comparator, callable between any two
encoding artifacts.

### 3.6 R6 — artifacts are witnesses — ANSWERED

Make clobbers because a rebuild is deterministic and the artifact is fungible. Neither holds here:
the producer is a non-deterministic agent, so two runs over identical inputs yield **different**
artifacts, and that difference is the product rather than waste.

So the store accumulates rather than overwrites, content-addressed by
`(phase, upstream-digest, content-hash)`, with run directories holding references. Today artifacts
live in `$TMPDIR/l4-go/<run-id>/artifacts/`, in a location designed to be discarded, with no
cross-run identity. Identical fetches dedupe under content addressing, so retention is cheaper than
it sounds.

**"Designed to be discarded" is not a figure of speech, and the measurement is the argument.**
Re-measured 2026-08-20: **92 run directories, of which 16 still hold a journal.** The other 76 are
empty shells — `$TMPDIR`'s own cleaner had already removed their contents, leaving the directory.
Every `regcf` journal in the store is gone; the 16 survivors are all `sg-succession`. From directory
mtimes, **files last roughly two to five days.**

Three consequences, each of which changes a decision:

- The evidence base for cross-run replay is not "everything since August", it is **this week**. A
  toolchain tweak measured against a run from a fortnight ago has nothing to replay from.
- `gc` retention policies calibrated in months are calibrating something that does not exist. The
  reaper is the real retention policy, and nobody chose it.
- A blessing recorded only in a run journal has the same half-life. **R11's requirement to leave
  `$TMPDIR` is not an architectural preference; it is the observation that a human signature
  currently expires in under a week, silently, for reasons no one decided.**

_What would make this true: an artifact store outside `$TMPDIR`, and `gc` becoming a policy over
references rather than a delete of the only copy._

### 3.7 R7 — replay crosses run boundaries — ANSWERED, IMPLEMENTED

Each stage's `--inputs` already names its own script, the checkers it calls and (folded in by
`go.sh`) the sha256 of the `l4` binary. That is a dependency graph; only the lookup was one run
wide. A stage now borrows a receipt from an earlier run of the **same subject** when the inputs
digest is byte-identical.

**Two stages may never cross a run boundary**, as a closed list in `lib/ledger.mjs`
(`CROSS_RUN_INELIGIBLE`) rather than a heuristic, because the digest covers files and not the
world: `p7-mcp` posts to a live jl4-service and reads the tool list back, so a borrowed `PASS`
could assert a deployment that is not there; and `p2-sweep` exists _because_ time has passed, so a
six-month-old sweep has unchanged inputs and a stale answer. Both still replay **within** a run, so
resuming an interrupted run is unaffected.

Measured, touching only `p7-akn.sh`: six stages replayed (`p0-preflight`, `p3-check`, `p6-tests`, `p8-verify`, `p7-lts`, `p7-wizard`); `p7-akn` re-executed because its digest moved, and `p7-mcp` because it is ineligible. `p9-report` and `p9-explain` declare no inputs and never replay by design.

#### 3.7a What the digest still does not cover — found 2026-08-20, two closed

"The digest covers files and not the world" is quoted above to justify a two-stage exclusion list.
A read of every `--inputs` block found the sentence is truer than that list assumed: ten things a
stage's output demonstrably depends on that no `--inputs` line named. Two were closed on the spot
because they make cross-run replay itself unsound; the rest are recorded here rather than fixed,
because each needs a decision and an unrecorded gap is one nobody can decide about.

**Closed — the pinned clock.** `--fixed-now` is passed to `l4` by seven stages (`p3-check`,
`p3-encode`, `p6-tests`, `p7-akn`, `p7-tnr`, `p7-wizard`, `p8-verify`) and appeared in no stage's
inputs. Two runs of the same subject, same tree, same binary and a **different** `--fixed-now`
produced byte-identical digests, and `findReplayableAcrossRuns` filters on subject and digest only
— so the second run borrowed the first run's answer **about a different point in legal time**. For a
pipeline whose subject is what the law says as at a date, that is the worst available form of a
stale replay. Each of the seven now declares `text:fixed_now=…`, per stage rather than folded
centrally like the binary's sha, so only the stages that read the clock re-run when it moves;
measured, the seven digests move and `p0-preflight` and `p7-lts` do not.

**Closed — a borrowed artifact could be laundered.** See §3.8.

**Closed — the standard library was an input to every stage and was in nothing.** Found by an
adversarial attack on the _proposed_ design; it turned out to be live in the tree, so it is recorded
at length. Every module of every subject opens with `IMPORT prelude` and `IMPORT daydate` (7 of 7
for `sg-succession`), so those files are inputs to every `l4 check`, `l4 run`, `l4 export` and
`l4 verify` the pipeline performs. They were in **no** digest — not the gate's `GO_ENCODING_FILES`,
not any stage's `--inputs` — and the path is an environment variable the driver exports with the
caller's value winning.

**MEASURED.** Copy `jl4-core/libraries`; change `__GEQ__` on `DATE` from `AT LEAST` to
`GREATER THAN`, one word; point `JL4_LIBRARY_PATH` at the copy. `sg-paa.l4` still reports **79
assertions, 0 failed**, byte-identical to the baseline, while a date-boundary `#EVAL` goes
**TRUE → FALSE**. Every oracle stays green and the answer moves — under a signature a human gave for
something else. The corpus's own 178 assertions cannot see it, because it asserts the boundary on
the days either side of the one the mutation moves. (Control: a cruder mutation, `add months`
shifted by one, _is_ caught — 7 of 79 fail. The suite is a real partial defence, and it is the
boundary cases it misses, which is exactly where an attacker aims.)

The indictment is in the driver's own comment. `go.sh` folds the `l4` binary's sha into every digest
_because_ "the `l4` binary is an input to every stage and is declared by none: no phase script can
see the path the driver was handed." `JL4_LIBRARY_PATH` is an input to every stage, declared by
none, invisible to every phase script — and, unlike the binary, caller-settable. The reasoning was
written and not applied to the second case; `etc/go/README.md`'s "**Leave `JL4_LIBRARY_PATH`
alone**" is the design conceding that a value in the trust base was held by operator discipline.

Now folded as `text:l4-stdlib=…` in the same `printf` as the binary, so no stage can get one and
miss the other, via `etc/go/lib/stdlib-digest.mjs`. Keyed by **basename and content**, not absolute
path — a library resolves by basename, so that is its identity, and two worktrees with identical
libraries must not re-execute everything. `p0-preflight` records `l4_stdlib`/`l4_stdlib_sha`, and
the gate payload grows a **toolchain** section naming what the answer depends on, since a signer
shown seven corpus hashes and nothing else is blessing an answer whose other half they cannot see.

Two things this does **not** close, recorded rather than implied. The library is not in
`GO_ENCODING_FILES`, so editing it does not re-open a granted HG1 — it invalidates the _replay_ and
moves the _payload_, which is weaker than a gate re-opening and is the right conservative default
only until someone rules on whether HG1 blesses the stdlib. And `jl4-service` resolves `daydate`
from **its own** copy, so the deployed endpoint is a third unattested library this fix does not
reach; that containment is why the attack could not reach a served answer.

**Closed — the lookup preferred a corpus hash to a clock.** `findReplayableAcrossRuns` ordered its
candidates with `readdirSync().sort().reverse()`. A run id is `YYYY-MM-DD-<corpus_sha8>-NNN`, so
that orders by date, then by the **corpus hash**, then by sequence — and a content hash's order
carries no meaning whatever. Within one day the greater `sha8` outranked the temporally later run,
so a stage could borrow an older receipt while a newer execution over byte-identical inputs sat in
the store. Reachable whenever a day holds runs over different corpora and a stage's declared inputs
are narrow enough to match across them (`p7-wizard` names only the wizard module). Now ordered by
`run_begin.ts` descending, with a run whose `ts` is unreadable sorting **last** so a malformed
journal cannot outrank a well-formed one.

The selection rule is unchanged and deliberately so: **the most recent execution over these inputs
wins, never the best status.** A lookup that preferred a `PASS` to a more recent `DEGRADED` would be
status shopping, which is the erosion this codebase refuses everywhere else — and it is exactly the
"improvement" a freshly-touched ordering function invites. Both properties are selftested, and the
old ordering fails the new fixture.

**Recorded, not closed.** In rough order of blast radius:

| gap                                                              | why it matters                                                                                                                                                                                                                                                                                                  |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the transitive `IMPORT` closure of a declared entry module       | every projection leg declares its entry point only, so editing `sg-wills.l4` re-opens the **gate** (it is in `encoding.modules`) while `p7-akn`, `p7-wizard`, `p7-lts` and `p7-tnr` all replay receipts describing the pre-edit encoding                                                                        |
| the adjudication layer                                           | `lib/phase-prelude.sh` is sourced by all 22 phases and declared by none; `receipt.mjs`, `verdict.mjs`, `ledger.mjs` likewise. Editing `ORACLE_CLASSES` changes what statuses are legal for every future receipt and moves no digest, so eligible stages replay their old status instead of being re-adjudicated |
| checkers a stage invokes but does not declare                    | `probe.mjs`, `discover.mjs`, `corpus-metrics.mjs`, `label-order.mjs`, `known-defects.mjs`, `plan-shape.mjs`, `fidelity-counts.mjs`, `bpmn-to-svg.mjs` — several of which produce the metrics the receipt carries                                                                                                |
| `p7-mcp`'s zip is built from seven modules, its digest names two | cross-run replay is blocked here, but **within**-run is not: `--only p7-mcp --run-id <id>` after editing `sg-paa.l4` replays                                                                                                                                                                                    |
| `p7-ladder`'s committed figures                                  | its oracle diffs against them, and unlike `p7-dmn`/`p7-dmn-md`/`p7-tnr` it does not declare its golden                                                                                                                                                                                                          |
| `JL4_LSP_CMD`                                                    | a second binary, on the same footing as `L4` in discovery, hashed nowhere; rebuild `jl4-lsp` alone and the stage driving it replays                                                                                                                                                                             |
| `subject.json` itself                                            | scalar keys (`legs`, `ladder.npm_script`, `citation`) can change with no digest movement; only the two floors are folded as `text:` literals                                                                                                                                                                    |

### 3.8 R8 — a run directory stays self-contained — ANSWERED, IMPLEMENTED

_Amended 2026-08-20: the copy path re-hashed, which is the one thing the rule it implements
forbids. See the end of this section._

`--artifacts-from` resolves its hash inside the current journal, so it structurally cannot name
another run's receipt — and referencing another run's files would be worse, because `gc` prunes run
directories and `go.sh verify` re-hashes every artifact a receipt names, so a borrowed path would
dangle and verification of a healthy run would fail.

Borrowed artifacts are therefore **copied in**. The invariant this preserves is the one that makes
`verify` worth anything to a second party: **a run directory is checkable on its own, by someone who
has only that directory.** Measured on a run with five borrowed stages: 44 artifacts recorded, 44
still hash as recorded.

The receipt records `replayed_from_run`, and the report names the run the evidence was earned in
rather than saying it is "on this journal", which for a borrowed row is false.

**The copy laundered, until 2026-08-20.** `receipt.mjs` states the rule for within-run replay in its
own comment: artifact records are copied **verbatim**, never re-hashed, because "Re-hashing would
launder a file that changed after the original receipt was written" — keeping the original sha256 is
what lets `verify` report `CHANGED`. The cross-run path cannot copy the records, for the reason in
the first paragraph, so it copies the **files** and records them with `--artifact`, which re-hashes.
That is precisely the laundering the rule forbids: a donor artifact tampered with after its receipt
was written reported `CHANGED` under `verify` in its own run and `matches` in the borrowing one,
because the borrowing receipt recorded the new hash as though it were the measured one.

`etc/go/lib/donor-check.mjs` now checks every donor artifact against its recorded sha256 **before
any file is copied**, and a finding **refuses the borrow** rather than repairing it — a donor
artifact that no longer matches its own receipt means the receipt is not evidence, so the stage
executes. It also refuses a donor whose artifact is gone (the copy would silently skip it, leaving
the receipt claiming a file it does not have) and a donor with two artifacts sharing a basename (the
copy flattens to basename, so one would overwrite the other — `p7-lts` already writes into a
`state-graphs/` subdirectory, so this is close to reachable rather than theoretical).

### 3.9 R9 — G0–G4 are capability milestones — ANSWERED

SPEC.md §6 is headed _"Gaps → milestones"_: G0 spec accepted, G1 the pipeline can replay, G2 it can
validate-and-diff a blind re-derivation, G3 every projection executes, G4 published. They describe
**what the tooling can do, in the order it was built**.

They are not phases a subject passes through, and using them as run labels (`--milestone g1`) is
what makes _"how can G1 run before G2?"_ a reasonable question to ask — as it was asked, by the
person who commissioned the spec. Runs should be labelled by what they do; the capability
milestones belong in a changelog.

### 3.10 R10 — three senses of "corpus" are retained — ANSWERED, IMPLEMENTED

Deliberately **not** renamed by R1, each a different and legitimate sense:

- `etc/check-corpus-goldens.mjs` and "corpus files" — the repo's body of `.l4` **examples**.
- the `corpus_sha_*` receipt metrics and `corpus_sha8` in run ids — written into hash-chained
  journals, and journals from earlier runs are already committed in `legalese/canon`. Renaming
  would split the journal format for no benefit today.
- `GO_MODULES_ORIGIN=corpus|denovo` — a two-valued sentinel whose other value is deferred under R2.
  Renaming one half of a pair is worse than renaming neither.

### 3.11 R11 — the blessing must become a first-class edge — OPEN

If artifacts accumulate as equal witnesses, _"which one did the domain expert review?"_ must stay
answerable. Today HG1 binds to a digest over the files at `encoding.main`, so the blessing is an
implicit property of whichever file sits at that path.

Under R6 that is no longer sufficient, and the failure mode is the worst one available: **a
confident answer served from an unreviewed encoding.** The blessing must be an edge in the store —
_this signature, over this artifact digest, by this signer, at this time_ — and the serving path
must refuse to answer from an artifact that has no such edge.

_This is the ruling most likely to be got wrong by building R6 first and R11 later._

**Four constraints on any implementation, from a design review run 2026-08-20** (three independent
designs, judged against the surveyed invariants, then attacked from the safety, migration and
erosion angles). Recorded here because each was reached by measurement and would otherwise have to
be rediscovered:

1. **Write the serving predicate once.** Three separate erosion attacks — `gc` collecting servable
   objects, a graft reintroducing a forbidden field, and a flag satisfying R11's only live check —
   turned out to be the same defect: "an object is servable iff…" gets written once in `gc`'s
   retention roots, once in the blessing lookup, and once in the refusal, and the copies disagree
   about `waived`. One exported `servability(rec)` that all three call is the only version in which
   that sentence is a fact about the code rather than a claim about three of them.

2. **Derive the blessing inside the receipt writer; never accept it as a flag.** `receipt.mjs` is
   the only journal writer precisely so that no caller can assert a status it did not earn. Passing
   a `--blessing` from the driver re-opens that asymmetry for any phase script, debug flag or future
   agent. `run_begin.gated_stages` already exists and is already what `verify-run.mjs` trusts
   _instead of_ the driver, so the derivation needs no new channel.

3. **Gate the act that actually serves.** `p7-mcp` POSTs to a live `jl4-service` **before it writes
   any receipt**, so no receipt-level rule can see it; `p10-publish` exits 3 and has never run.
   Wiring only the latter would let R11 be marked implemented while the pipeline's one real serving
   act stays unchecked. (Measured caveat: `p10-publish` does not source `phase-prelude.sh` and CI
   asserts its exit 3, so adding a prelude-dependent check there fails CI as `rc=2, expected 3`.)

4. **Validate blessing records the way receipts are validated.** Gate rows bypass `checkReceipt`
   today — it is applied only under `case stage_end` — so a row claiming `satisfied` with a null
   signature is written without complaint. In a run directory that is disposable; in a durable
   ledger it is permanent. HG2's unwaivability in particular has to move out of `go.sh`'s prose and
   into the writer, because a waived-HG2 claim in a ledger nothing sweeps could never be taken back.

**And one thing the review changed about the order of work.** The safety attack found that the L4
standard library was an input to every stage and in no digest (§3.7a), which under a durable ledger
would have converted an under-specified binding into a **permanent, itemised, quotable false claim
naming a real human** — while R6's own comparator stayed silent, because its witness key is computed
from the same under-declared set the gate is. Both the gate's binding and the comparator's key fail
together when that set is wrong. That is now fixed; it was not when the designs were written, and
building R6 first would have made it durable.

### 3.12 R12 — a first encoding has no home — ANSWERED 2026-08-20

**The problem, as measured before this ruling was implemented:** a subject whose `encoding.main` did
not exist could not be resolved at all (`corpus.main`/`encoding.main` was `mustExist`), so no
milestone could run on a body of law nobody had encoded. And a first pass could not be registered as
its own de novo deposit either, because the resolver refuses a de novo module that is also an
encoding module — that half still holds.

So the most consequential work in the pipeline — fetch, sweep, encode, fork, for the first time —
is **unmilestoned agent work that produces no receipt**. That is precisely how, for
`sg-succession`, three registers were built, hand-validated with `register-validate.mjs` and
committed while the pipeline held no receipt for any of them; eight runs had happened, all `g1`,
and the reports correctly said the source bundle was ABSENT.

Two candidate closures were on the table:

1. a phase set for the first pass, permitting `encoding == the artifact under review` because there
   is nothing to diff, with the comparator reporting `NOT-APPLICABLE` rather than `SKIPPED` — a
   different and more honest status;
2. relax the resolver so a subject may be declared before its encoding exists, letting the source
   and research phases run and deposit first, with `encoding.main` required only from the
   projection phases onward. Closer to how the work actually proceeds, but it weakens a check that
   currently catches typos in every declared path.

**RULED: neither, and the objection to (2) is what produced the answer.** Candidate 2's weakness is
real and is the same one `subject.mjs` already refuses further down its own file, where the
explainer is required to be an EXPLICIT DECLARATION rather than a discovered directory, because "a
mistyped directory name would then yield a fully-ABSENT explainer with no error anywhere — absence
experienced as breakage". Tolerating absence turns every typo into a silent skip. So absence is
**declared**, not tolerated:

```json
"encoding": { "state": "unwritten", "main": "jl4/examples/legal/sg-tax/sg-tax.l4" }
```

and the declaration is checked in **both directions**. With `state` absent or `"written"` — what
every existing sidecar means — `main`, `wizard` and every module must exist, byte-for-byte the old
rule, so a typo still fails loudly naming the path. With `state: "unwritten"` they must **not**
exist: depositing the first module without flipping the state is itself an error, naming the file
and the one-line edit. A declaration that is checked when it stops being true cannot rot into a lie.

Nothing downstream needed teaching, which is the evidence that this is the right seam rather than a
convenient one. The stages already report a declared module that is not a file as `SKIPPED` with the
deposit instruction attached (`p3-check`, `p6-tests`, `p8-verify`, via `go_skip`), and `digestSet`
already records a missing path as `ABSENT` rather than skipping it — so an unwritten encoding has a
real gate digest. **Measured**: the `sg-tax` scaffold planned at digest
`7715…7638a1` with the file absent and `96ff…33efe2` once a one-line module was deposited, so an HG1
granted before the encoding existed cannot survive the encoding arriving. That is the property that
makes registering-before-encoding safe rather than merely possible.

On top of it, `etc/go/go.sh new-subject <id> --citation … --source-url …` scaffolds a sidecar that
`plan --subject <id>` accepts at once. It writes `subject.json` from the arguments and refuses the
ones with no defensible default; it does **not** write the encoding, because that would falsify the
state it just declared. `pins.json` and `known-defects.json` are emitted **empty and marked
unmeasured** — both are measurement records, pins probed against a real binary and defects observed
on a stated date, and a scaffolder that emitted plausible contents would be manufacturing exactly
the evidence this pipeline exists to demand. It would also be believed, because a file that looks
measured is not distinguishable from one that is. The stages that need them refuse loudly instead:
`p0-preflight` reports BROKEN on a pin-set mismatch, and `known-defects.mjs` refuses with "no group
`<name>`".

Seventeen selftests cover it, including both directions of the declaration, the digest movement, and
the assertion that the scaffolded measurement files claim nothing.

What this ruling does **not** close: the first pass still produces no receipt for its own fetch,
sweep and encode work. `encoding.state` gives that work a registered subject to happen against and a
gate digest that moves when it lands, but the phases themselves remain unmilestoned — that is R4 and
R11, and R12 was the precondition, not the substitute.

### 3.13 R13 — reporting needs a subject-level fold — OPEN

`p9-report` renders **one run's** journal. No single run exercises every phase, so no single report
is the account of the subject: `sg-succession`'s `g1` report marks §P1 and §P2 **ABSENT** while its
`g2` report marks the measurement stages **SKIPPED**, and both are correct about their own run.

**The fold is not a union.** A receipt binds to the digest it ran over, so evidence from two runs is
jointly meaningful only where both ran over the same inputs. A subject-level report must resolve
each phase to one of three states:

| state       | meaning                                                                                |
| ----------- | -------------------------------------------------------------------------------------- |
| `CURRENT`   | a receipt exists over today's digest                                                   |
| `STALE`     | a receipt exists, but over an older digest — shown, marked, with the digest it covered |
| `NEVER RUN` | no receipt at any milestone                                                            |

`NEVER RUN` is the state that would have caught R12's failure. Today a report says a phase is "not
declared at this milestone" — true, and readable as "accounted for elsewhere" when nothing had
accounted for it anywhere.

---

## 4. What this does not settle

- **Where the store lives**, and whether `gc` becomes a reference policy or is retired.
- **Whether comparison is a phase or a query.** The argument for query: _"show me the encoding
  divergences for this subject where the sources were identical"_ is a question, not a build step.
- **Whether `--milestone` survives R9 at all.** Once staleness is computed from the graph, a
  pre-cut stage set is a filter one would rarely reach for.
- **The cost of retention** under R6 at real corpus sizes. 2.7 MB across 86 runs is not evidence
  about a subject with a decade of sources.

## 5. What review changed

Written in one pass out of a working conversation, so there is no second reviewer yet. Two claims
in it were **corrected mid-conversation** and are recorded here in their corrected form, because
each was believed for a while:

- _"the first report would have said something different but it was clobbered"_ — checked against
  the surviving run directory and **false**: both reports were `g1` runs and their §P1 paragraphs
  are byte-identical. Nothing was lost. The real defect was R12's, one level down.
- _"blindness is whether the agent read the corpus"_ — ill-formed, because an encoding agent always
  reads the fetched text. Corrected to R4's read-set, which is what makes the fourth question
  (comparability) expressible at all.
