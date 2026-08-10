# `etc/go/` — the "⟨body of law⟩: go" pipeline orchestrator

One instruction names a subject; the pipeline takes it from source text through an L4
encoding to every projection, gate and conversion report. The driver, libraries and phase
scripts are subject-generic: everything the pipeline knows about one body of law lives in a
per-subject sidecar under `etc/go/subjects/<id>/`. `regcf` (SEC Regulation Crowdfunding) is
the inaugural, replay-milestone subject, not the scope — the BNA smoke test (PR #195) is the
same pipeline pointed at a different statute, and it will slot in as a second sidecar.

Everything here has an exit code. Everything that is a judgement lives in the
skill at `.claude/skills/running-the-l4-pipeline/`. Scripts never call a model;
the skill never writes a status.

The spec is [`specs/todo/single-instruction-demo/ORCHESTRATOR.md`](../../specs/todo/single-instruction-demo/ORCHESTRATOR.md),
which states in the present tense what runs today and what is scaffolded and
cannot run. The pipeline it serves is `specs/todo/single-instruction-demo/SPEC.md`.

## Usage

```
etc/go/go.sh run     --milestone g1 --subject <id> [--run-id ID] [--through STAGE]
                     [--only STAGE] [--waive HG1=REASON] [--fixed-now ISO8601]
etc/go/go.sh doctor  [--milestone g1|g2] [--subject <id>]
etc/go/go.sh plan    [--milestone g1|g2] [--subject <id>]
etc/go/go.sh status  [--run-id ID]
etc/go/go.sh verify  [--run-id ID] [--gates]
etc/go/go.sh gc      [--keep N]
etc/go/go.sh help
```

Milestone `g2` is the de novo path; its stages validate deposits rather than producing them, and
— since 2026-08-09 — measure the deposited encoding itself (house rules, assertions, `l4
verify`, emit-only DMN, and the §8 comparator). `plan --milestone g2` says which deposits a
subject has. `g2 COMPLETE` is completeness of accounting over those stages, not a claim that a
de novo run happened: a run with every deposit absent is COMPLETE over `SKIPPED` receipts.

`<id>` names a sidecar directory under `etc/go/subjects/` (today: `regcf`). While exactly
one sidecar exists, `--subject` may be omitted and defaults to it; with several, naming one
is mandatory. An unknown subject exits 2 listing the available sidecars and the recipe for
adding one.

A first run. On a machine where this repo (any worktree) has been built, no
exports are needed — `run` discovers `l4` and `jl4-lsp` from `dist-newstyle`
and says so; `doctor` forecasts what the run will and will not produce:

```
etc/go/go.sh doctor --milestone g1
etc/go/go.sh run --milestone g1 --subject regcf
```

On a machine with no build anywhere, point `L4` at a prebuilt binary first:

```
export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
```

That stops at HG1 with exit 3 and tells you how to grant the gate. To proceed
without a signature, waive it on the record:

```
etc/go/go.sh run --milestone g1 --subject regcf \
  --waive HG1="G1 replays the already-reviewed committed corpus"
```

## Subjects

A subject sidecar is four files in `etc/go/subjects/<id>/`:

| file                 | role                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `subject.json`       | the machine-readable descriptor: id, display name, legal citation, source entry URL, corpus module paths (`corpus.main`, optional `corpus.wizard`), per-subject check floors (`checks.min_dated_arms`, `checks.min_assertions`), a `legs` object — one entry per projection leg, with its golden/cases paths — and an optional `denovo` object saying where the G2 deposits live (`bundle`, `register`, `fork_register`, `modules`, `surface_map`; plus `checks` — the deposit's own floors — and per-leg `legs` declarations), whose paths need not exist |
| `pins.json`          | the CLI surface the stage table reads, measured against that subject's corpus                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `known-defects.json` | measured defects used as negative controls; empty groups say why they are empty                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `NOTES.md`           | free-prose idiosyncrasies of the corpus, for humans and the skill. **No script reads it.**                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `explainer/`         | optional. The subject's checked-in explainer narrative — `manifest.json` (the document's spine), `provenance.json` (per file: its digest, who drafted it, the sources it was drafted from with their digests, and its review state) and one markdown file per part. Declared explicitly in `subject.json`'s `explainer.dir`, never discovered, so a mistyped directory is an error rather than a silently empty document.                                                                                                                                  |

`etc/go/lib/subject.mjs` resolves and validates a sidecar (unknown keys refused; a leg entry
naming a missing golden is a hard error naming the path) and exports it to the driver as
`GO_S_*` environment variables. **The `legs` object is the leg declaration**: a p7 stage is a
declared member of the milestone iff `legs` has its entry, and the wizard-dependent halves of
p0/p3/p6/p7-mcp engage iff `corpus.wizard` is present. So a future subject with no wizard and
no regulative rules (no bpmn/lts legs, no NLG goldens) simply omits those entries, and
`COMPLETE` still means what it says. To add a subject, copy an existing sidecar and re-measure
every value in it against the new corpus — the pins and floors are measurements, not defaults.

## Exit codes

Extending `etc/check-bpmn-kie.sh`'s 0/1/2/3/4:

| code | meaning                                                     |
| ---- | ----------------------------------------------------------- |
| 0    | clean                                                       |
| 1    | a finding                                                   |
| 2    | usage                                                       |
| 3    | a human gate is not satisfied                               |
| 4    | broken — a harness defect, never a finding about the corpus |
| 5    | a stage was SKIPPED while `L4_GO_REQUIRED=1`                |

## Environment

| variable             | effect                                                                                                                                                                                                                                                                                                                                                                                                               |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `L4`                 | path to a prebuilt `l4`. When unset, `run` and `doctor` **discover** one under `dist-newstyle` — this worktree's own first, then the newest among sibling worktrees (`lib/toolchain.sh`); explicit always wins, and the run refuses only when discovery also finds nothing. This orchestrator never runs `cabal`; the build lock is a shared resource and concurrent invocations in one worktree corrupt each other. |
| `JL4_LIBRARY_PATH`   | defaults to `<repo>/jl4-core/libraries`                                                                                                                                                                                                                                                                                                                                                                              |
| `JL4_LSP_CMD`        | a prebuilt `jl4-lsp`, for the ladder leg; discovered the same way as `L4` when unset. Absent even after discovery ⇒ that leg is `SKIPPED` with a named reason.                                                                                                                                                                                                                                                       |
| `JL4_GO_SERVICE_URL` | a **loopback** `jl4-service` for the MCP leg. The URL is parsed, not string-trimmed, and userinfo is refused outright — `http://127.0.0.1:8080@REALHOST/` reads as loopback to a naive parser and as credentials-for-REALHOST to curl. A non-loopback host is refused: an outward-facing deployment is HG2's subject, not an environment variable's.                                                                 |
| `L4_GO_RUNDIR`       | where runs live (default `$TMPDIR/l4-go`). Never the tree.                                                                                                                                                                                                                                                                                                                                                           |
| `L4_GO_REQUIRED`     | `1` ⇒ any `SKIPPED` stage is fatal (exit 5), which is what CI wants                                                                                                                                                                                                                                                                                                                                                  |
| `L4_GO_FIXED_NOW`    | pins the clock threaded into every `run`/`check`/`render` (default `2025-01-31T00:00:00Z`)                                                                                                                                                                                                                                                                                                                           |

## Requirements

**Start with `etc/go/go.sh doctor`.** It forecasts, before any stage spends
time, which declared stages will run whole and which will not, each with its
remedy — at the front door instead of one ten-minute run at a time. What it
checks: the `l4` and `jl4-lsp` binaries (with discovery), `npm`/`npx`/`tsx`,
`zip`/`curl`, and the service URL against the same loopback fence the MCP
stage applies; `mvn`/graphviz absences print as notes. It does **not** see
gates, deposit presence (g2) or oracle verdicts — those stay the stages' own
account. Exit 0 = environmental wants met, 1 = something will not run whole,
2 = no usable `l4` anywhere.

`node` and `bash` for everything. `npx` for the DMN and BPMN interchange gates
(it fetches `dmn-moddle`/`bpmn-moddle` into its own cache — network needed the
first time only). `npm` plus `JL4_LSP_CMD` for the ladder leg. `graphviz`
optionally, to render the LTS DOT to SVG. `mvn` + JDK 17/21 for the DMN engine
harnesses on the `p7-dmn` leg (reachable since PR #194 landed the corpus cases
file). Every absence produces a `SKIPPED` receipt naming what is missing and
what it was needed for.

### Getting `l4` and `jl4-lsp` without building them

`L4` and `JL4_LSP_CMD` want prebuilt binaries, and this driver never builds
them. On a workstation with worktrees the usual answer is discovery (see
Environment above): any sibling worktree's `dist-newstyle` counts, so most
machines that have ever built the repo need no exports at all. The rest of
this section is for machines with no build anywhere — say, a cloud sandbox
whose setup script is capped at a few minutes.

The alternative is a prerelease archive from the **release shelf,
[`legalese/prereleases`](https://github.com/legalese/prereleases/releases)** —
a dedicated repo whose workflow checks out this repo's `unstable`, builds, and
publishes there: one archive per platform, under tags of the form
`unstable-<YYYYMMDD>-<short-sha>` where the SHA names this repo's commit.

The shelf exists because releases and tags are repo-scoped, not
branch-scoped: prereleases published HERE landed beside the stable
`l4-ide-build-<n>` extension releases on a page this repo's maintainers keep
for the stable track (the one published here, 2026-08-05, was deleted within
days). This repo used to carry the workflow as
`.github/workflows/unstable-prerelease.yml`; it was retired 2026-08-11 in
favour of the shelf's copy, which is proven end to end (dry run 31352348001,
real publish 31353772360, release `unstable-20260810-2e183e5` — all shelf-side
run ids). To cut a new build: `gh workflow run prerelease.yml --repo
legalese/prereleases` (dry_run defaults true; uncheck to publish).

The URL is constructible from the tag and the platform, so no page-scraping:

```
https://github.com/legalese/prereleases/releases/download/<tag>/l4-<tag>-<platform>.tar.gz
```

with `<platform>` one of `linux-x64`, `darwin-arm64`, `win32-x64`. Each archive
extracts to a directory of its own name holding `l4`, `jl4-lsp`, a `libraries/`
copy of the standard library, and a `BUILD-INFO.txt` naming the commit it came
from. A `SHA256SUMS` file covering all three archives is attached to the same
release.

```bash
TAG=<pick one from https://github.com/legalese/prereleases/releases>
PLATFORM=linux-x64   # or darwin-arm64, win32-x64
BASE=https://github.com/legalese/prereleases/releases/download/$TAG

curl -fsSLO "$BASE/l4-$TAG-$PLATFORM.tar.gz"
curl -fsSLO "$BASE/SHA256SUMS"
sha256sum --ignore-missing -c SHA256SUMS   # macOS without coreutils: shasum -a 256 --ignore-missing -c SHA256SUMS
tar -xzf "l4-$TAG-$PLATFORM.tar.gz"

export L4="$PWD/l4-$TAG-$PLATFORM/l4"
export JL4_LSP_CMD="$PWD/l4-$TAG-$PLATFORM/jl4-lsp"
```

Three things worth knowing:

- **These are prereleases, and they say so.** They are built from `unstable`,
  the integration branch, and are flagged `prerelease`. The shelf hosts
  nothing else, but `/releases/latest` still will not find them — read the
  releases list, or use the tag you were given.
- **Leave `JL4_LIBRARY_PATH` alone.** The standard library is compiled into the
  binary; the `libraries/` directory in the archive is there for standalone use
  outside a checkout. Inside the repo the driver already points it at
  `<repo>/jl4-core/libraries`.
- **macOS may quarantine the download.** Clear it with
  `xattr -dr com.apple.quarantine "l4-$TAG-darwin-arm64"`.

Be wary of the binary bundled inside the published VS Code extension: it is
built from `main`, which trails `unstable`, and the 2026-07-18 build predated
the `l4 export` subcommand entirely. Before relying on one, run `l4 --help`
and check the subcommand list includes `export` — the same vintage check the
shelf's smoke test applies to every archive it publishes.

## Selftests

```
node etc/go/selftest.mjs [--with-driver]
node etc/go/lib/assert-report.selftest.mjs
```

## The de novo deposit contracts

The three registers the G2 stages write into — source bundle (P1), external modifications (P2),
fork register (P4) — are defined under
[`specs/todo/single-instruction-demo/schemas/`](../../specs/todo/single-instruction-demo/schemas/)
and checked by one validator:

```
node etc/go/lib/register-validate.mjs <fork-register|external-modifications|source-bundle> <file> [peer-file ...]
node etc/go/lib/register-validate.mjs --rules <schema>
```

Peer files let the cross-file rules run — a fork citing a modification, a modification routing to
a fork, a disposition table joined against the bundle's annotation inventory. A cross-file rule
whose peer is absent prints `skip` with a reason; it never passes quietly. Exit `0` clean · `1` a
finding · `2` usage or a schema the validator cannot fully enforce.

**Nothing in the pipeline writes one, and nothing will.** Producing a bundle or a sweep needs
outward network access this orchestrator does not take, and producing an encoding or a fork
inventory needs a model it does not call. What the stages own is the other half: since 2026-08-03,
`p1-ingest`, `p2-sweep`, `p3-encode`, `p4-forks` and `p5-gate` are milestone `g2`'s declared
members and each VALIDATES its deposit — `SKIPPED` when it is not there, `DEGRADED` naming every
rule that fired against it, `PASS` over a hashed artifact. Since 2026-08-09 the measurement
stages run over the deposit too: the driver resolves one module set per milestone
(`GO_MODULES`), so `p3-check` (house rules + `denovo.checks` floors), `p6-tests` (the deposit's
own `#ASSERT`s), `p8-verify` (`l4 verify`) and `p7-dmn` (emit-only — no golden exists for a
deposit) measure the deposited encoding itself, and `p8-diff` runs the §8 comparator below. A
subject says where its deposits live in `subject.json`'s optional `denovo` section (`bundle`,
`register`, `fork_register`, `modules`, `surface_map`, plus `checks` floors and per-leg `legs`
declarations); those paths need not exist, because an unwritten deposit is a missing
prerequisite, not a misconfiguration. `etc/go/go.sh plan --milestone g2 --subject <id>` prints
each one's state.

## The §8 diff oracle

G2's acceptance comparator: two encodings of one body of law, compared by **what they answer**
rather than by their text (they share no identifiers, so a textual diff is 100% different and 0%
informative).

```
node etc/go/lib/denovo-diff.mjs run --map <surface-map.json> --out <dir> [--max-rows N]
```

The map — schema `specs/todo/single-instruction-demo/schemas/surface-map.schema.json`, fixture
`schemas/fixtures/regcf-identity.surface-map.json` — declares the pairing: two modules, the shared
fact slots with each side's L4 type name, and one entry per compared decision. The oracle seeds a
battery from the subject's cases file, perturbs it one field at a time, evaluates both sides
through a generated probe module, and emits `denovo-diff.{json,md,rows.json}`. Exit `0` total
agreement · `1` at least one divergence, which under SPEC.md §8 is the **better** outcome · `2`
usage · `4` broken.

It **never triages**: every witness reads `UNTRIAGED`, because SPEC.md §8's three dispositions are
judgements and belong to the reviewer. Read the report's **Sensitivity** table alongside its
agreement counts — a (pair, fact) leaf the battery perturbed without ever moving an answer is a
surface on which agreement is silence rather than evidence.

Design, limits and the verbatim self-tests:
[`DENOVO-DIFF-ORACLE.md`](../../specs/todo/single-instruction-demo/DENOVO-DIFF-ORACLE.md).
**`p8-diff` calls it** (a declared g2 stage, 2026-08-09) over the surface map the sidecar declares
in `denovo.surface_map`, following the deposit contract — no map declared or deposited is a
`SKIPPED` receipt naming the key; comparator exits 2/4 (harness errors) are `DEGRADED`; exits 0/1
are a completed measurement, because a divergence is §8's better pass, never a failure. Writing
the map and the module, and triaging any witness, remain agent/reviewer acts.

`selftest.mjs` proves the status lattice can still say no: that every status is
producible, that `PASS` is rejected with a null, failing, or _weak_ oracle, that
a `BROKEN` receipt cannot yield a `COMPLETE` milestone, and that editing,
deleting or rewriting a journal record breaks the chain. It also proves the
subject resolver refuses an unknown subject (listing the available sidecars), a
descriptor naming a nonexistent golden, and a descriptor carrying an unknown
key. `--with-driver` also
drives the whole G1 pipeline twice and asserts that the second run re-executes
nothing but the two stages that declare no inputs (`p9-report`, `p9-explain`) —
the only mechanical check that `replayed` means anything. It also asserts that
every declared g1 stage sequenced at or after `p6-tests` is gated by HG1, which
is the one invariant whose violation is silent in every other direction.

## The two documents a run produces

| file             | what it is                                                                                                                                                                                         |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `report.md`      | the AUDIT account, rendered by `p9-report` from `journal.ndjson` and nothing else. Its template may not contain a two-digit number; every figure is a placeholder resolved from a journal row.     |
| `explainer.html` | the READER-facing sibling, rendered by `p9-explain`. It explains the body of law and, interleaved with that, what happened when somebody made it executable. `explainer.md` carries the same text. |

Both are written into the run directory and never into the tree; copying either
anywhere a third party can see it is publication, which is P10, which is HG2's.

The explainer's discipline is the report's, adapted to a document that must
carry prose and figures. Run facts are placeholders resolved from the journal.
Every OTHER number lives in a narrative file under
`etc/go/subjects/<id>/explainer/`, where it must be a placeholder or a citation
— `[$5,000,000](src:path#L151)` — whose source line the renderer re-opens and
matches before printing it. A citation that does not resolve prints the figure
followed by a visible complaint and degrades the stage. Narrative that has not
been reviewed renders behind a draft banner; no signer is enrolled today, so all
of it does, and `p9-explain` rides `DEGRADED` for that reason. Design and
rulings: [`EXPLAINER-REPORT-SPEC.md`](../../specs/todo/single-instruction-demo/EXPLAINER-REPORT-SPEC.md).

Provenance is maintained with:

```
node etc/go/lib/narrative-provenance.mjs <subject> [--check | --bless]
```

`--check` (the default) reports every narrative file whose text or whose cited
sources have moved since the record was written, and exits 1 if any has.
`--bless` rewrites those digests **and clears the affected records' review
state**, because a review signed over one text and one set of sources says
nothing about a different text or different sources. It will not invent a
`drafted_from` for a file that has no record: what a paragraph was drafted from
is a fact about how it was written, and no tool can observe it afterwards.

`assert-report.selftest.mjs` mutates a real captured `l4 run --json` envelope
ten ways to prove the assertion checker can be red. It exists because `l4 run`
exits **0** on a failed `#ASSERT`, so neither the exit code nor the envelope's
`ok` field can be the oracle.

## Common errors

**`go.sh: L4 is unset, and no built l4 was discovered…`** — no explicit `L4`
and discovery found nothing under `dist-newstyle` here or in sibling worktrees.
Point `L4` at a prebuilt binary, or build one in a _different_ worktree. The
orchestrator will not build one.

**`GATE HG1: REFUSED — no signer is enrolled.`** — the shipped state.
`specs/todo/single-instruction-demo/gate-allowed-signers` carries no public key,
so nothing verifies. Enrol a key, or waive the gate with a reason that will
appear in the report. A waiver binds to the sha256 of the corpus files it was
granted over: edit one and the gate re-opens, for that run and every resume of
it. **HG2 cannot be waived** — `--waive HG2=…` exits 2, because its subject is
anything outward-facing and that decision is not an agent's.

**`the CLI surface the stage table depends on has moved`** (exit 4) — a
discovery call returned a set that differs from the subject's
`etc/go/subjects/<id>/pins.json`. The message names the exact strings.
Re-verify the phase scripts against the new surface, then update the pin.

**`known-defects[…]: X NO LONGER REPRODUCES`** (exit 4) — a measured defect used
as a negative control has been fixed. Delete the entry from the subject's
`etc/go/subjects/<id>/known-defects.json`; a stale negative control is a lie
about what the leg measures.

**`subject '<id>' has no sidecar`** (exit 2) — the subject is not set up. The
message lists the available sidecars and the four files a new one needs; see
the Subjects section above.
