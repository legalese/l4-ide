# `jl4/examples/legal/` — encodings of real law, used as a regression corpus

Every `.l4` here is an encoding of an actual body of law, and every one of them is a **regression
test**: `jl4/tests/Main.hs` globs `legal/**/*.l4` and holds four goldens per file
(`tests/<stem>.{golden,ep.golden,nlg.golden,schema.golden}`). A compiler change that alters output
turns this directory red, which is the point of it.

## The corpus spans two repositories

Ruled by Meng on 2026-09-15 — the ruling is quoted verbatim in
[`specs/todo/CANON-REGRESSION-CORPUS-SPEC.md`](../../../specs/todo/CANON-REGRESSION-CORPUS-SPEC.md)
§1:

> we should write README and memory and other docs or scripts to note that regressions are to run
> against certain blessed dirs of the canon as well as what's in l4-ide

So the regression corpus is **this directory plus a blessed subset of
[`legalese/canon`](https://github.com/legalese/canon)**, vendored at a pinned SHA into
[`../canon/`](../canon/). Both are globbed by the same harness with the same semantics; neither is
more authoritative than the other as a test.

| | what it holds | who owns the files |
| --- | --- | --- |
| `legal/` (here) | encodings that are **not** in canon | this repository |
| [`canon/`](../canon/) | blessed canon directories, vendored | `legalese/canon`, at `etc/canon-pin.json`'s SHA |

**The difference that matters to you:** files here are edited here. Files under `canon/` are a
copy — edit them in canon and bump the pin. `canon/README.md` says how.

## What moved to canon, and where it is now

Two moves, and every encoding that left this directory is now vendored back under
[`../canon/`](../canon/) and globbed from there, goldens included.

**2026-09-16** (SPEC §4): `chubb` and `sg-succession`'s committed encoding.

**2026-09-23** (LODGER, SPEC §4.2): the rest of the subjects with a home in canon.

| was | is now |
| --- | --- |
| `chubb/chubb.l4` | `canon/us/chubb-hospital-cash/blind-inert/chubb.l4` |
| `chubb/denovo/chubb-denovo.l4` | `canon/us/chubb-hospital-cash/blind-guarded/chubb-denovo.l4` |
| `sg-succession/*.l4` (7) | `canon/sg/succession/*.l4` |
| `sg-succession/cleanroom-2026-08/*.l4` (6) | `canon/sg/succession/cleanroom/*.l4` |
| `regcf/regcf.l4`, `regcf/regcf-wizard.l4` | `canon/us/regcf/` |
| `regcf/denovo/regcf-denovo.l4` | `canon/us/regcf/cleanroom/` |
| `bna/bna.l4` | `canon/uk/bna-1981/` |
| `charities-cleanroom/charity-test.l4` | `canon/je/charities-2014/` |
| `miles-card/*.l4` (14) | `canon/contracts/payments/sg-miles-card/` |

The deposit registers (`fork-register.json`, `source-bundle.json`, `external-modifications.json`,
`surface-map.json`) went with them. They are vendored at `canon/<to>/registers/`, because the
mirror has carried `registers/*.json` since 2026-09-23. The prose, projections and reports went
to canon only. Find them in canon under `subjects/<path>/encodings/<row>/`, where each row's
`NOTES.md` maps old paths to new.

## What stayed, and why each one did

These directories hold no `.l4` any more, so the harness sees nothing in them. Each one stays
for a stated reason.

- **`regcf/README.md`, `regcf/PROJECTIONS.md`, `regcf/figures/`** (ruled 2026-09-23, M3). They
  describe this repository's own projections of the corpus. `ts-shared/ladder-svg` generates
  the figures and tests them, the DMN and BPMN exporter goldens under `../dmn/` and `../bpmn/`
  are what `PROJECTIONS.md` documents, and the Reg CF explainer cites `README.md` and
  `figures/README.md` by line and pins all three by `sha256`. So they are **not edited**:
  their own commands still say `jl4/examples/legal/regcf/regcf.l4`, and the corpus they
  describe is at `../canon/us/regcf/regcf.l4`, byte-identical to what they were written
  against.
- **`sg-succession/source/`, `sg-succession/cleanroom-2026-08/source/`** (M2). These are the
  Singapore Acts as fetched from SSO. Their source terms are undetermined, so canon pins them by
  `sha256` and does not hold them. The source bundles vendored under `../canon/sg/succession/`
  name these paths, which is why the digest checks still run.
- **`miles-card/source/`** (M2). These are the eight issuers' T&C PDFs, their text extractions
  and the two table generators. Canon's row names this directory as the authoritative copy, for
  the same reason.
- **`chubb/denovo/*.json`, `chubb/denovo/source/`**. These are chubb's deposit data, which stayed
  on 2026-09-16 and were not part of LODGER.

This is the ruling working as written, not an exception to it: *"there would also be some
corpora left inside jl4/examples/legal that are not in canon, and that's ok too."*

## What stays here as corpus, and why that is not a defect

A subject that is in canon **moves** there (moved, not lost). A subject that is not in canon
**stays here**, and the ruling says that is fine. As of 2026-09-23 that means the single-file
subjects: `anti-social.l4`, `british-citizen-act.l4`, `ceo-performance-award.l4`,
`directive-showcase.l4`, `imaginary-alcohol-act.l4`, `ny-environmental-7.3.l4` and
`promissory-note.l4`.

## Adding a file here

Four goldens ship in the same commit as the `.l4`, or the whole suite goes red for the next person
— `failFirstTime` is `True`, so a file with no `tests/` directory fails rather than quietly
blessing itself. `etc/check-corpus-goldens.mjs` runs on every PR with no path filter and names
what is missing. See `CLAUDE.md` §3.1 for the full rule and the two incidents that produced it.
