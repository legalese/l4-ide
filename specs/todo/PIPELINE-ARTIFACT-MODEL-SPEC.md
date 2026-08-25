# The pipeline as an artifact graph: phases, witnesses, and what the labels are for

_Status: **rulings recorded; all thirteen implemented.** Written 2026-08-20 on branch
`mengwong/sg-succession`, out of the conversation that added the pipeline's second subject
(`sg-succession`) and found that several of its central nouns name the wrong things._

\_What IS implemented, and where: **R1** (`corpus` → `encoding`, commit `dd55a6c8`), **R7** and
**R8** (cross-run replay with a closed ineligible list, and borrowed artifacts copied rather than
referenced, commit `41a7b5ac`), **R10** (the three senses of "corpus" deliberately retained), and
**R12** (`encoding.state`, and `go.sh new-subject` on top of it — see §3.12 for the third closure
that neither candidate had), **R6** + **R11** together (`etc/go/lib/store.mjs`, the blessing
ledger, and `go.sh store`), and **R4** (`etc/go/lib/readset.mjs` and `go.sh readset` — the read-set
is recorded on every `stage_end`, and journal schema 4 enforces that it re-folds to its own digest).
**R5** (`store diff` labels each divergence by phase class, and refuses to call an encode
divergence a fork without evidence the sources matched) and **R13** (`go.sh subject-report`).
**R2** and **R3** (the `denovo` split, and `--encoding <id>` in place of an origin sentinel), and
**R9** (`--milestone` retired; the stage set, the HG1 set and the gate digest all derived from the
selected encoding — see §3.9).

_The count above read "eleven of thirteen" until R9 landed, which undercounted by one: it tallied
the **bold** markers in §3's table, and R12's row carries its date instead of the marker while
§3.12 and this same paragraph both record it as implemented. Corrected here rather than in R12's
row, which is not this change's to restate._

What would make those present tense is named per ruling in §3.\_

_Why this document exists at all: the rulings below were reached in conversation and existed
nowhere else. `CLAUDE.md` §4 — a decision is recorded in its owning document or it is not
decided — and the specific failure it guards against had already happened once here, when a
report committed to `legalese/canon` described an encoding that no longer existed because nobody
had a document saying what the report was an account **of**._

---

## 1. One-line summary

_Written as the diagnosis, in the present tense of 2026-08-20. All thirteen rulings have since
landed; read it as the statement of the problem, not of the tree._

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

**The error this spec exists to stop: extrinsic labels stored as intrinsic configuration.**
`subject.json` **had** a `denovo` object — a schema key named after an ordinal — and the milestone
flag `--milestone g1|g2` **selected** a stage set by a label denoting a tooling capability. Both
made a subject's _position in its own history_ something you declared rather than something the
graph answers.

_Past tense as of 2026-08-25, and left standing rather than rewritten because it is the diagnosis
the thirteen rulings were reached from._ §3.2 and §3.3 split the `denovo` object; §3.9 retired the
flag, which now refuses. The distinction above is the load-bearing part and has not changed.

## 3. Rulings

| ruling | status                     | one line                                                                                                |
| ------ | -------------------------- | ------------------------------------------------------------------------------------------------------- |
| R1     | **ANSWERED · IMPLEMENTED** | the subject's L4 is `encoding`, not `corpus`, §3.1                                                      |
| R2     | **ANSWERED · IMPLEMENTED** | the fetched legal text is `natlang_sources`; `denovo` is SPLIT, not renamed, §3.2                       |
| R3     | **ANSWERED · IMPLEMENTED** | phase identity is intrinsic; ordinals are extrinsic and are not schema keys, §3.3                       |
| R4     | **ANSWERED · IMPLEMENTED** | blindness is a recorded read-set, not a flag; freshness is derived from it, §3.4                        |
| R5     | **ANSWERED · IMPLEMENTED** | a diff means a different thing per phase, and an encoding diff is a fork only if upstream matched, §3.5 |
| R6     | **ANSWERED · IMPLEMENTED** | artifacts are witnesses: they accumulate and are compared, not clobbered, §3.6                          |
| R7     | **ANSWERED · IMPLEMENTED** | replay crosses run boundaries, except for a closed list of stages, §3.7                                 |
| R8     | **ANSWERED · IMPLEMENTED** | a run directory stays self-contained; borrowed artifacts are copied, §3.8                               |
| R9     | **ANSWERED · IMPLEMENTED** | G0–G4 are capability milestones, not lifecycle phases, and have stopped being run labels, §3.9          |
| R10    | **ANSWERED · IMPLEMENTED** | three other senses of "corpus" are retained deliberately, §3.10                                         |
| R11    | **ANSWERED · IMPLEMENTED** | the HG1 blessing is a durable ledger edge, and the serving path defaults to deny, §3.11                 |
| R12    | ANSWERED 2026-08-20, §3.12 | a subject may declare `encoding.state: "unwritten"`; `go.sh new-subject` scaffolds one, §3.12           |
| R13    | **ANSWERED · IMPLEMENTED** | reporting is run-oriented; a subject-level fold is needed, and it is not a union, §3.13                 |

### 3.1 R1 — the subject's L4 is `encoding` — ANSWERED, IMPLEMENTED

"Corpus" was doing four jobs: the subject's L4 modules, the repository of encodings
(`legalese/canon`, "a corpus of L4 encodings"), the fetched legal text, and an external legal
database (lawplain's "Singapore legal corpus"). The first had the worst word for it — an encoding
is not a corpus of anything — and the overloading made _"did the agent read the corpus?"_
unanswerable, because an encoding agent always reads the fetched text and may or may not read a
prior encoding.

`encoding.main` / `.wizard` / `.modules`; `GO_S_ENCODING*`; `GO_ENCODING_FILES`. Verified as a
pure rename: `go.sh plan` byte-identical for both subjects including the gate digest.

### 3.2 R2 — the fetched legal text is `natlang_sources` — ANSWERED, IMPLEMENTED 2026-08-24

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

**Implemented 2026-08-24, as a SPLIT rather than a rename** — which is what the paragraph above
deferred until R6 existed, and R6 shipped on 2026-08-21.

`denovo` bundled six keys across four unrelated kinds of thing. Each now sits under what it _is_:

| was                    | is now                     | because it is                         |
| ---------------------- | -------------------------- | ------------------------------------- |
| `denovo.bundle`        | `natlang_sources.bundle`   | the fetched legal text                |
| `denovo.register`      | `natlang_sources.register` | the case-law sweep's findings         |
| `denovo.fork_register` | `comparison.fork_register` | a declaration relating two encodings  |
| `denovo.surface_map`   | `comparison.surface_map`   | ditto                                 |
| `denovo.modules`       | `encodings.<id>.modules`   | a second **encoding** of the same law |
| `denovo.checks`        | `encodings.<id>.checks`    | floors measuring **that** encoding    |

**The floors' pairing became structural rather than a convention.** `checks` used to sit in a
parallel object, and the rule "a stage running over the deposit reads the deposit floor" was
something the reader had to hold in their head. Now the floors are _inside_ the encoding they
measure, so a committed floor cannot be applied to a deposit and a deposit floor cannot be applied
to the committed one.

**`GO_MODULES_ORIGIN=corpus|denovo` is gone entirely** rather than half-renamed, which is what
§3.10 required of a pair. `subject.mjs` takes `--encoding <id>` and resolves the SELECTED encoding
into the ordinary `GO_S_ENCODING_MODULES` and `GO_S_MIN_*` names, so a stage reads the encoding it
was handed and never asks which one it is. That is what let `p3-check`, `p6-tests`, `p7-dmn` and
`p8-verify` **delete** their per-origin arms rather than rename them.

`p7-dmn`'s arm survives, and its re-keying is the most instructive part of the change: the leg
runs emit-only for a deposit because there is no golden to diff against. The true question was
never "which pass is this" but **"is there a golden?"** — which the sidecar answers directly. Keyed
on the declaration, a future additional encoding that acquired a golden would be diffed without
anybody editing the script.

**An id names an occasion, not a position.** `encodings["cleanroom-2026-08"]` is a fact about the
job; "de novo" was a fact about the job's place in a sequence. `primary` is reserved for the
committed encoding.

_Superseded 2026-08-25 by R9, and recorded rather than rewritten because the reasoning is what
matters:_ this ruling left `--milestone g2` alive as a legacy spelling, TRANSLATED into a selection
and refusing when a subject declared more than one — the refusal being, as written here, "the
clearest statement of why the rename happened". R9 went further and retired the flag outright,
because a translation that still works keeps the ordinal executable. `undeclared` took over the one
case the translation was genuinely needed for. See §3.9.

**And the word "de novo" is no longer needed for the thing it was reaching for.** §3.3 asked for
the pipeline to _"stop needing either word"_, and R4 is what made that reachable: "produced without
reading a prior encoding" is `readset.independence()`, a question asked of the graph rather than a
property declared in a sidecar. That closure was not available when this ruling was written.

**Three defects the build found**, each recorded because each is the same shape — a diagnostic that
survives a rename and starts pointing at nothing:

- The deposit path on a subject declaring no additional encoding showed the **committed**
  encoding's seven modules as the deposit set. A plan that confidently describes the wrong artifact is worse
  than one that says `undeclared`.
- The same case made every skip reason say `encoding.modules`, telling the reader to edit the
  committed encoding when what they need is to create an `encodings` entry. There are **three**
  cases — `primary`, a real id, and `undeclared` — and collapsing any two gives advice about the
  wrong key.
- Two selftest assertions on the old `module_origin` metric survived green because their guard was
  never satisfied: latent tests asserting a fact that had stopped being true.

**Deliberately NOT renamed, with reasons** (the §3.10 discipline):

- `etc/go/lib/denovo-diff.mjs` and its `denovo-diff.{json,md}` outputs. R5 already re-reads it as
  the general `encode`-phase comparator; the name is a module filename, not a schema key, a
  stage-set name or a config value, and its outputs are named inside committed receipts.
- The corpus directory `jl4/examples/legal/<id>/denovo/` and the module `regcf-denovo.l4`. Renaming
  the module means regenerating its four goldens, which needs a build — a separate change, and one
  this ruling does not require.

### 3.3 R3 — phase identity is intrinsic — ANSWERED, IMPLEMENTED 2026-08-24

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

### 3.4 R4 — blindness is a read-set, not a flag — ANSWERED, IMPLEMENTED 2026-08-24

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

**Implemented 2026-08-24.** `etc/go/lib/readset.mjs`, `etc/go/lib/readset-cli.mjs`, and
`go.sh readset`.

_The members are a PROOF of the fold, not an annotation beside it._ `ledger.manifestText`
renders exactly the fields `ledger.digestMembers` returns, so `refold(members) === inputs_digest`
by construction — checkable offline, with no filesystem, no store and no surviving run directory.
`refold` lives in `ledger.mjs` beside the frozen format it inverts, so nobody edits one half
without seeing the other. `receipt.mjs` REFUSES a read-set that does not re-fold, and
`ledger.verify` catches one doctored and re-chained afterwards. That is what makes the read-set
worth trusting, and it is why the members are recorded rather than a second, independently
derived list.

_Recorded on `stage_end`, and this matters._ `stage_begin` also carries `inputs_digest`, and was
the first choice — wrongly. A REPLAYED stage writes no `stage_begin` at all, because it never
began and a receipt may not exceed its evidence; a read-set carried only there would vanish for
exactly the stages whose freshness R4 wants to know about. `stage_end` is the row that always
exists, and R8 requires a run directory to be answerable by someone holding only that directory.

_Nothing derived is stored._ Role, freshness, independence and comparability are all computed at
query time. Freshness keeps Make's meaning — a newer prerequisite exists — and its ordering is
**append order in the store index, never a timestamp**, so the verdict does not depend on when it
was asked. A `text:` param nobody supplies reads `unknown`, never `current`: assuming one
unchanged is precisely the §3.7a bug, where the binary and the stdlib moved and no digest noticed.

_Two defects the build found, both recorded because each is a trap for the next reader._ The
store's blessing path re-admits every `covers[]` member under the pseudo-stage `covers`, whose
`rel` is `tree:<abs>`; letting that record outrank the tree check classified every corpus module
of a blessed run as `unknown` — a worse answer than the filesystem gives for free. And the query
must resolve a prerequisite **exactly as a run would**: a `command -v l4` fallback reported every
stage of a clean run stale, because the driver had discovered a binary under a sibling worktree's
`dist-newstyle` while the PATH held an unrelated one. Nothing had moved; two resolutions had
disagreed, and a freshness tool that cries wolf is one nobody reads twice.

_Measured on `sg-succession`._ Editing one corpus module (`sg-wills.l4`) turns exactly the four
stages that read it STALE, each naming the moved member, while the projection stages that read
only the entry module stay `current`. A digest could have said only that four stages changed.

### 3.5 R5 — a diff means something different per phase — ANSWERED, IMPLEMENTED 2026-08-24

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

**Implemented 2026-08-24** in `go.sh store diff`, which now reads every divergence through the
class of the phase that produced it (`readset.PHASE_CLASS`, keyed on what a stage DOES, which is
what makes it nameable at all under §3.3).

The comparability precondition needed somewhere to live that OUTLIVES THE JOURNAL. Read-sets are
recorded on receipts, and receipts live in run directories that last two to five days — the exact
half-life R11 exists to escape. So the fold over a witness's `natlang_sources` members rides on
the store admission itself as `sources_digest` (store schema 1 → 2), and `store diff` can still
refuse to call a difference a fork long after the run that produced it is gone. It is derived, but
it is a fact about **that admission**, fixed forever, and so has the same standing as the
`inputs_digest` beside it; what must never be stored is a fact about _history_, which is
recomputed.

`sources_digest` is **null**, never the empty fold, when a witness recorded no sources at all.
"This witness recorded no sources" and "its sources hashed to X" are different claims, and
conflating them would make two source-less encodings look comparable — the spurious fork this
ruling exists to prevent.

**Which is the case that holds today for every subject in the tree.** No subject has run
`p1-ingest` for real, so no read-set contains a `natlang_sources` member, so an encode divergence
reports `NOT ESTABLISHED as a fork: … Absence of evidence is not comparability`. That is the
honest answer, and stating it plainly is worth more than machinery that pretends otherwise.

### 3.6 R6 — artifacts are witnesses — ANSWERED, IMPLEMENTED 2026-08-21

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

**IMPLEMENTED 2026-08-21.** `etc/go/lib/store.mjs`, at `$L4_GO_STORE` (default the XDG state dir,
never `$TMPDIR`). An artifact record now carries `rel` — its identity within a run, subdirectories
included — and `cas`, a place the original bytes can still be fetched. `sha256` remains the CLAIM
the receipt made; `cas` is where to get them, which is what upgrades `verify`'s `CHANGED` from an
accusation into a diff.

The comparator is `go.sh store diff`, keyed on `(stage, inputs_digest, rel)`. A key holding more
than one distinct hash is a producer that did not converge over inputs the pipeline calls
identical — and convergence is silence, so the output is the disagreement itself. Artifacts that
embed their own run path (`p0-preflight`'s `tripwire.json`) can never dedupe; those pairs are
labelled `SELF-REFERENTIAL` with the exact substring that triggered the label, and never filtered,
because filtering hides a real finding the day the heuristic is wrong.

`gc` did not change. `store gc` is a separate verb over a different thing, collecting by
reachability before age — run directories are a cache, the object store is evidence.

Selftested end to end at the property that matters: **a borrow succeeds after the donor run
directory has been deleted entirely.**

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

### 3.9 R9 — G0–G4 are capability milestones — ANSWERED, IMPLEMENTED 2026-08-25

SPEC.md §6 is headed _"Gaps → milestones"_: G0 spec accepted, G1 the pipeline can replay, G2 it can
validate-and-diff a blind re-derivation, G3 every projection executes, G4 published. They describe
**what the tooling can do, in the order it was built**.

They are not phases a subject passes through, and using them as run labels (`--milestone g1`) is
what makes _"how can G1 run before G2?"_ a reasonable question to ask — as it was asked, by the
person who commissioned the spec. Runs should be labelled by what they do; the capability
milestones belong in a changelog.

**IMPLEMENTED 2026-08-25.** A run is about **one subject and one encoding of it**, and `--encoding`
is the only thing that selects it. G0–G4 survive in `SPEC.md` §6, where they are capability
descriptions and correct; nothing labels a run with them any more.

#### The value space is the driver's own, in both directions

`--encoding` takes exactly the three values `GO_S_ENCODING_ID` can hold, so what you type and what
the driver reports back are the same words:

| value        | means                                                                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `primary`    | the committed encoding. The default; the flag may be omitted.                                                                                                    |
| `<id>`       | that additional encoding, named. `subject.mjs` refuses an id the subject does not declare, and lists the ones it does.                                           |
| `undeclared` | the deposit path over a subject that declares **none** — a forecast of what would have to be deposited. Refused, with a list, when the subject does declare one. |

**A keyword meaning "the additional one" was designed and rejected.** It reads as the obvious
convenience, and it is this ruling's own defect wearing a new word: _the additional one_ is a
POSITION, so it changes meaning silently as a subject's declarations grow and breaks loudly the day
a second is declared — which `regcf` is one edit away from. §3.3 is the rule; an ordinal is not a
name however it is spelled. `--mode` beside `--encoding` was rejected for a sharper reason: two
flags encoding one fact can disagree, and that disagreement was **already reachable** — see the
`fbcd0470…` measurement below.

#### `--milestone` refuses; it is not translated and not silently unknown

A translating shim keeps the ordinal executable, which is three of the four things this ruling
removes. A plain "unknown option" teaches nothing. So it refuses at parse time with exit 2 and the
translation table, and the message hands over `subject.mjs <subject> --encodings` for the ids.

It is deliberately **not** spelled as a `case` arm: `check-skill-drift.mjs` decides a flag exists by
looking for its arm in `go.sh`, so an arm would make the drift guard green over any stale
`--milestone` line left in the skill — the one sweep this ruling depends on being complete.

_That guard had to be repaired to make the sentence true._ It tested `goSrc.includes("--milestone)")`,
a bare substring, which the **comment explaining why there is no arm** satisfies. It reported the
retired flag as still accepted. The test is now line-anchored, because a declaration and a mention
of one are different things and only the anchor tells them apart.

#### What the flag was doing, and where each job went

| job                                 | now                                                                                                                                    |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| which stages run                    | the encoding: `primary` → `PRIMARY_STAGES`, otherwise `DEPOSIT_STAGES`. Contents unchanged — R9 retires the label, not the stage sets. |
| which module set the stages iterate | already R2/R3's: `GO_MODULES` from the selected encoding. Only the label mention was left to delete.                                   |
| which stages HG1 gates              | **derived**: every declared stage from P6 onward, minus `gated_by_HG2`.                                                                |
| what a gate binds to                | **derived**: `GO_MODULES`, plus every deposit a declared stage of this run reads.                                                      |

The gating rule is SPEC.md §7.3's own sentence — _HG1 blocks P6 onward_ — written once and applied,
in place of one hand-kept list per stage set. Measured byte-equal to both lists it replaces, in
order, on every selection the tree can express. It subtracts `gated_by_HG2` rather than capping at
`< 10`: a stage carries one gate, and `< 10` would only be a coincidence of `p10-publish`'s number.
`verify-run.mjs` reports a finding for any gate that gates a declared stage and has no record, so a
`p10-publish` that ever became declared would otherwise demand an HG1 record it must never have.

The digest rule iterates **deposits**, not stages: `manifestText` sorts but does not dedupe, and
`p1-ingest`, `p2-sweep`, `p4-forks` and `p5-gate` all read all three natlang and comparison
deposits, so a stage-major union would contribute a path twice and change the hash.

#### Two gate digests moved, both deliberately, and both were wrong before

Neither is bound by any signature: no committed file names them, and the six blessings in the live
store are all `waived`, over two other digests.

- **`--encoding <id>` alone ran the PRIMARY stage set over the DEPOSIT module.** Measured on the
  pre-R9 tree: `plan --subject regcf --encoding cleanroom-2026-08` printed _"milestone g1"_, the
  primary stage list, and a 25-member gate digest `fbcd0470…` — the deposit's module beside the
  committed encoding's narrative deposit, which is neither of the two documented sets. It is now
  `1e801642…`, the 5-member deposit set. This is the concrete evidence against `--mode`: it would
  have made that incoherent state a first-class, spellable input.
- **A deposit run over a subject with nothing deposited bound HG1 to the committed encoding.**
  `GO_MODULES` is empty there by design, while the digest branch still folded in
  `GO_S_ENCODING_MODULES`, which with no `--encoding` passed resolves to the PRIMARY modules. So
  `sg-succession` bound a gate to `11092f74…`: three deposits plus seven committed modules, and the
  `text:no-additional-encoding-declared=` sentinel written for exactly that case was unreachable
  because the array was never empty. Binding to `GO_MODULES` makes it `5ac0d975…`, the three
  deposits, and the sentinel is reachable again for a subject declaring no deposits at all.

  _This bullet first read "…seven committed modules **the run never read**", and the review
  measured that clause false._ `p3-encode` was the one measurement stage of five that read
  `GO_S_ENCODING_MODULES` directly instead of the `GO_MODULES` the driver resolved — its four
  siblings all carried the fallback — so on this path it typechecked all seven committed modules
  and wrote `PASS` with an oracle reading _"the deposit is L4 the toolchain accepts"_, for a
  deposit that does not exist, while its own `plan` row said `undeclared`. The defect predates R9
  (it is identical at `36a34a23`), but R9 made the state first-class and spellable and then
  asserted it away, which is the failure `CLAUDE.md`'s anti-drift rules exist to catch. Repaired in
  the same PR: the stage now reads `GO_MODULES`, reports `SKIPPED` naming a key the schema still
  has, and two tests pin it — one on the driver-produced state the old fixture could not reach.

The two unchanged selections stayed byte-identical: `regcf` primary `6b2191ee…` (26 files),
`sg-succession` primary `c0841f89…` (7). Both hash **absolute** paths (`digestSet` over
`GO_ENCODING_FILES`), so they reproduce in a checkout at this worktree's path and not elsewhere;
what is portable is the derivation, not the number. The live `regcf` primary value is now
`e8d030fb…`, because this change re-anchored `explainer/how-it-works.md`'s `src:etc/go/go.sh#L29`
to `#L38` — the header rewrite moved the line it quotes verbatim — and rewrote that one provenance
row. That is HG1 correctly re-opening over an edited deposit; with the original narrative bytes the
derivation still yields `6b2191ee…`.

#### Journal schema 5

`run_begin.milestone` is replaced by `run_begin.encoding`. One field, not two: the mode is
derivable (primary iff `encoding === "primary"`), and two fields encoding one fact can disagree.

This also closes a gap R2/R3 left: after the split, a journal could not say WHICH additional
encoding a run was about. `g2` named an ordinal, and no reader can recover an id from it — so
`verify-run.mjs` and the report renderer report a schema-4 row as `legacy:g2` rather than guessing.
`gate-payload.mjs` emits whichever identity line the journal actually carries, keyed on the field
and not the schema number, so a signature taken over a schema-4 payload still verifies.

An in-flight schema-4 run cannot be resumed by this binary: `ledger.append` refuses to put two
schemas in one chain. That is the existing, deliberate behaviour (§5.1), not a new one.

#### One silent wrong answer this shook out

`gate-payload.mjs` chose its refusal ARM by `begin.milestone === "g2"`. Dropping the field flipped
it to the other arm, which still refused — same exit code, same absence of a signable document —
while telling the reader to _"run p0-preflight in this run"_. `p0-preflight` is not in
`DEPOSIT_STAGES` and `--only p0-preflight` intersects to nothing, so the advice could not be
followed: a correct refusal silently downgraded to an impossible instruction. The arm now keys on
`declared_stages`, which every schema from 2 onward records, so both spellings resolve to the same
advice. Pinned by three fixtures.

#### R4's graph was considered for `stages_for`, and cannot answer it

§4.3 says R9 must follow R4 because _"a mechanism that answers 'what should run?' cannot be removed
before the graph can answer it instead."_ Recorded here because the sentence invites a reading it
does not support: `readset.mjs` classifies phases and queries **recorded** read-sets, and there is
no stage→stage prerequisite edge anywhere in the tree. It can answer _what did this stage read_ and
_is this artifact stale_; it cannot answer _which stages should run for this selection_. R9 does not
remove that mechanism — it **re-keys** it, from a capability label to the selected encoding — so
the premise of §4.3's blocker never triggers. R4 still had to come first, for the other three jobs.

### 3.10 R10 — three senses of "corpus" are retained — ANSWERED, IMPLEMENTED

Deliberately **not** renamed by R1, each a different and legitimate sense:

- `etc/check-corpus-goldens.mjs` and "corpus files" — the repo's body of `.l4` **examples**.
- the `corpus_sha_*` receipt metrics and `corpus_sha8` in run ids — written into hash-chained
  journals, and journals from earlier runs are already committed in `legalese/canon`. Renaming
  would split the journal format for no benefit today.
- `GO_MODULES_ORIGIN=corpus|denovo` — a two-valued sentinel whose other value is deferred under R2.
  Renaming one half of a pair is worse than renaming neither.

### 3.11 R11 — the blessing must become a first-class edge — ANSWERED, IMPLEMENTED 2026-08-21

If artifacts accumulate as equal witnesses, _"which one did the domain expert review?"_ must stay
answerable. Today HG1 binds to a digest over the files at `encoding.main`, so the blessing is an
implicit property of whichever file sits at that path.

Under R6 that is no longer sufficient, and the failure mode is the worst one available: **a
confident answer served from an unreviewed encoding.** The blessing must be an edge in the store —
_this signature, over this artifact digest, by this signer, at this time_ — and the serving path
must refuse to answer from an artifact that has no such edge.

_This is the ruling most likely to be got wrong by building R6 first and R11 later._

**IMPLEMENTED 2026-08-21, together with R6 and for exactly that reason.** A blessing is now a record
in `blessings/`, one file per record under `wx`, chained and never swept — carrying `covers[]` (the
corpus itemised), the signer, the payload digest, and the signature BYTES rather than a path into a
run directory. The reviewed bytes are admitted to the store, so "show me what was reviewed" is a
fetch and not a name.

`signer` and `payload_digest` had been declared fields since the beginning and were never once
populated: `gate-verify.sh` computed the identity and fingerprint purely to print them at a human.

The three constraints below are enforced rather than intended:

1. `servability()` is written once and exported; `store cat`, `store gc` and the refusal all call it.
2. `produced_under` is DERIVED inside `receipt.mjs` from `run_begin.gated_stages` plus the journal's
   own gate rows — never a `--blessing` flag, which would re-open for any phase script the
   asymmetry that makes `receipt.mjs` the only writer of a claim. Asserted over the source.
3. `go_require_blessing` gates the act that actually serves. `p7-mcp` POSTs a deployment BEFORE it
   writes any receipt, so no receipt-level rule can see it; the refusal sits in front of the first
   mutating request. A waiver lets it proceed and PRINTS its reason.

And `verdict.mjs` Rule 7: a gated stage may write no status but `BROKEN` while it carries no
blessing. That converts the load-bearing safety property from an ordering into a structure — until
now the only thing stopping a gated stage from running unblessed was that the gate check precedes
the replay lookup in one `while` loop, with no test, and no loop at all around a phase script
invoked directly, which `SKILL.md` tells readers to do.

**What is NOT closed.** `produced_under` is stamped by the driver, which is the same party
`verify --gates` exists to distrust, and after `gc` the run journal that corroborates it may be
gone. `store verify` re-checks the claim against the naming run's journal while that run survives;
after that, an admission is corroborated only by the fields the same driver wrote in the same
breath. The honest closure is a signature over the index record itself. Stated plainly because the
stakes rose: this is now a claim in a durable store rather than in a directory the OS deletes.

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

### 3.13 R13 — reporting needs a subject-level fold — ANSWERED, IMPLEMENTED 2026-08-24

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

**Implemented 2026-08-24** as `etc/go/lib/subject-report.mjs` and `go.sh subject-report`.

**The `STALE` in the table above was re-spelled, and the change is the substantive part.** As
first written it read _"a receipt exists, but over an older digest"_. That is not R4's staleness,
and R4's is the better one:

- a digest can differ with **no** prerequisite newer — a param changed the _question_ rather than
  the answer;
- a prerequisite can be newer with the digest **unmoved**: that is the whole of §3.7a, where the
  clock, the stdlib and the `IMPORT` closure were real input changes that moved no digest;
- a digest says only THAT something moved. A read-set says WHICH member, and the report names it.

One concept, one mechanism. Shipping the digest-only spelling first would have baked the weaker
notion into the surface everyone reads, which is why R4 was sequenced ahead of this ruling rather
than the other way round.

**The phase universe is built widest-first** — what the driver says is _declarable_, then what the
subject has _declared_, then what the store has _recorded_. A universe built only from declared
stages cannot contain a phase nobody ever declared, and such a phase then vanishes from the report
entirely; an absent row reads as "accounted for elsewhere" exactly as R12's did. Measured on
`sg-succession`: seven phases report `NEVER RUN`, none of which appeared at all before the
declarable set was threaded through.

**The evidence horizon is printed.** Journals expire; the store outlives them but records only
stages that produced an artifact, so a SKIPPED stage leaves no trace there. A fold that quietly
narrowed its evidence would turn "I cannot see it" into "it never happened". A journal whose chain
does not verify is excluded and the exclusion is announced, because folding it in would let a
hand-edited row set a phase's state for the whole subject.

---

## 4. What this does not settle

Three of the four questions this section opened with were **settled by building** — one on
2026-08-21 by R6/R11, one on 2026-08-24 by noticing that the answer had already been made in code
and written down nowhere, and one on 2026-08-25 by R9. They are recorded here rather than deleted:
the resolution is the interesting part, and a reader who remembers the open question deserves to
find its answer where they left it. Per-bullet status is what to trust below; the section heading
does not track it.

### 4.1 Where the store lives — SETTLED 2026-08-21, and `gc` became a reference policy

`$L4_GO_STORE`, defaulting to `${XDG_STATE_HOME:-$HOME/.local/state}/l4-go/store`
(`etc/go/lib/store.mjs:64`). What fixed it was not taste but a half-life: a blessing recorded only
in a run journal under `$TMPDIR` expires in two to five days, silently, because the operating
system reaps it. **Never `$TMPDIR`** is the whole of the ruling; the XDG state dir is merely the
nearest conventional directory that satisfies it.

`gc` was **retained, as a reference policy** — the bullet offered "reference policy or retired" and
the answer is the first. It collects by **reachability first and age second**
(`etc/go/lib/store-cli.mjs:165-205`): blessed bytes and every `covers[]` member are roots, and no
age policy may reach them. Age alone would have made a signature's half-life a function of how long
ago somebody signed it — the same defect as `$TMPDIR`, relocated to a better directory.

### 4.2 Comparison is BOTH, and dependency is what separates them — SETTLED 2026-08-24

The question was posed as exclusive and is not. Both exist in the tree, both are correct, and the
rule that tells them apart is:

> A comparison whose result something **depends on** is a **phase**: it consumes a declared input
> set, earns a receipt, and sits in the graph. A comparison you **ask a question with** is a
> **query**: it ranges over unbounded history, has no fixed input set, and produces no receipt.

`p8-diff`, over `etc/go/lib/denovo-diff.mjs`, is a phase — its verdict gates acceptance, so
something downstream depends on it. `go.sh store diff` is a query — _"show me the encoding
divergences for this subject where the sources were identical"_ ranges over every run ever
recorded, and nothing consumes its answer. They are not two implementations of one idea, and R5 is
what tells a caller which of the two they are asking for.

This is recorded because the decision had already been **made in code and written down nowhere**:
the store's comparator shipped as a CLI verb rather than as a stage, and that choice _was_ the
ruling. `CLAUDE.md` §4 is about exactly this failure — a decision taken in one medium and left out
of the document that owns the question.

### 4.3 The remaining questions

- **Whether `--milestone` survives R9 at all — SETTLED 2026-08-25: it does not.** The question was
  posed here after measuring that it was **one flag doing four separable jobs** — which files the
  gate digest binds to, which module set the stages iterate, which stages are HG1-gated, and which
  stages run at all — plus three cosmetic uses. The first was the damaging one: same subject, same
  tree, different flag → different gate digest → **a different thing signed**, which is R3's
  complaint exactly.

  All four jobs are now answered by the selected encoding, and the flag refuses. §3.9 records the
  ruling, the two gate digests that moved and why each was wrong before, and the value space that
  replaced it. Two notes for a reader arriving from this bullet: the line numbers it cited are long
  stale and are left as written, because they were true when the count was taken; and its closing
  clause — _"a mechanism that answers 'what should run?' cannot be removed before the graph can
  answer it instead"_ — invites a reading §3.9 had to refuse. R4's graph classifies phases and
  queries recorded read-sets; it holds no stage→stage prerequisite edge and cannot answer which
  stages a selection should run. R9 **re-keys** that mechanism rather than removing it. R4 still
  had to land first, for the other three jobs.

- **The cost of retention** under R6 at real corpus sizes — and it is **still unmeasured**, which
  is a stronger statement than it was. The working store on 2026-08-24 holds 860 KB across 193
  objects and 312 index records, but **every one of those records carries `subject: null` and
  `run_id: null`**, and their timestamps span a single afternoon (`2026-08-20T15:21Z` to
  `21:05Z`) — the session that built R6 itself. **No pipeline run has ever populated this store.**
  The number is test debris, and quoting it as a retention measurement would be measuring the
  wrong thing; it is recorded here in that character so nobody quotes it as the right one.
  What the same sweep _does_ establish, and much more sharply, is R11's premise: of **92 run
  directories under `$TMPDIR/l4-go`, zero still hold a `journal.ndjson`** — four days after the
  measurement that found sixteen of them surviving. A blessing kept only in a run journal is now
  observed to have a half-life shorter than the week it took to write this paragraph.

## 5. What review changed

### 5.1 The R4/R5/R13 build, reviewed by attack — 2026-08-24

Five independent lenses attacked the implementation, each finding backed by three skeptics
instructed to refute it. **Six refutation attempts were made and none succeeded.** The findings
are recorded because each is a trap for the next reader, and every one now has a regression test.

- **The produced-artifact half of freshness stopped working, one commit after it started.**
  `freshness` built its newest-admission map with two literal **NUL bytes** between the key's
  fields and looked it up with two **spaces**, so every produced member missed and reported
  `unknown` — "I did not look", wearing the same word as "I looked and it had not moved". All five
  review lenses found it independently. The separator is now an escape, both ends go through one
  `witnessKey()`, and a test reads the file as BYTES and asserts it contains no raw NUL.

  _Provenance, corrected by a reviewer's git archaeology and then re-measured — because the first
  account written here was wrong in a way that mattered._ Counting NUL bytes in the blob at each
  commit: the R4 commit had **four**, on lines 166 and 189, so both ends matched and freshness
  worked as shipped. The R5/R13 commit had **two**, on line 166 alone: the lookup was rewritten in
  that commit and its NULs became spaces in the process.

  So this was **a regression introduced by editing a line whose separator could not be seen**, and
  not a defect present from the start. That is the sharper lesson: an invisible byte does not
  merely survive review, it is silently destroyed by an ordinary edit to its own line. It is also
  why `witnessKey()` is the right repair rather than re-synchronising two spellings — with one
  function there are no longer two ends that can drift apart.

  A related signal, recorded separately because it is about tooling rather than about this bug:
  the first attempt to write that file used a shell heredoc, and the tool REFUSED it for "control
  characters that would be hidden in the approval dialog". That refusal was correct, and it was
  routed around with a writer that accepted the same bytes silently. The same guard fired again,
  on the same content, while writing this note.

- **A missing subject could produce a confident wrong answer, not just a missing one.**
  `rolesFor` stamped `subject` on store-resolved members and not on run-resolved ones, so a
  run-origin member keyed on an empty subject. With the separator repaired that is not merely a
  miss: it **false-matches a `subject: null` record left by an unrelated run**, reporting STALE
  against a stranger's bytes.

- **`gc` deleted every run directory, gate-holding ones included, while printing "kept N".**
  Pre-existing, and it fired **by default on macOS**: `TMPDIR` ends in a slash, so the run base
  carries a double slash that `ls` preserves and node's resolver collapses. The keep-list compared
  path strings, the two spellings of the same directory compared unequal, and nothing was ever
  kept. It destroyed three run directories during the review that found it. Membership is now by
  run id — a basename is immune to every path-form difference there is.

- **Resuming a run across the schema 3 → 4 bump would have made its journal permanently
  unverifiable** ("one chain, two binaries"), destroying the property the chain exists to provide.
  `append` now refuses, which is the house rule applied to itself: an unknown schema is BROKEN,
  not guessed at.

- Three narrower ones, all fixed: `refold` threw on a malformed `read_set` member, turning "this
  journal is wrong" into "the tool is wrong"; `store diff` read only the FIRST admission of each
  sha, hiding a disagreement between two runs that read different sources; and `receipt.mjs`
  classified read-sets against an **empty** store index, which made `sources_digest` structurally
  null for exactly the cross-run case it exists to serve.

- **`subject-report`'s declarable universe was empty of primary-path stages**, because the
  primary stage list (then `G1_STAGES`, renamed `PRIMARY_STAGES` by R9) is
  assembled only for commands that resolve a subject and `subject-report` was not one of them. And
  it ordered runs **lexicographically by run id**, which sorts date, then a _content hash_, then
  counter — so two runs on one day over different corpora sorted arbitrarily. Runs are now ordered
  by the start time the journal itself recorded. That is not the clock re-entering freshness:
  freshness still compares content and never a timestamp, but "which run is most recent" is an
  inherently temporal question the id cannot answer.

### 5.2 The original document

Written in one pass out of a working conversation, so there is no second reviewer yet. Two claims
in it were **corrected mid-conversation** and are recorded here in their corrected form, because
each was believed for a while:

- _"the first report would have said something different but it was clobbered"_ — checked against
  the surviving run directory and **false**: both reports were `g1` runs and their §P1 paragraphs
  are byte-identical. Nothing was lost. The real defect was R12's, one level down.
- _"blindness is whether the agent read the corpus"_ — ill-formed, because an encoding agent always
  reads the fetched text. Corrected to R4's read-set, which is what makes the fourth question
  (comparability) expressible at all.
