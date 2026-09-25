# The vendored canon mirror

**Do not edit anything in this directory.** It is a verbatim copy of blessed directories in
[`legalese/canon`](https://github.com/legalese/canon), taken at the SHA pinned in
[`etc/canon-pin.json`](../../../etc/canon-pin.json). Edits made here are lost the next time
anyone runs `--pull`, and CI fails before that on the first PR that touches them.

To change one of these files: **edit it in canon, then bump the pin.**

```bash
node etc/sync-canon.mjs --bump <canon-sha>   # repoint the pin and rewrite the mirror
node etc/sync-canon.mjs --check              # what CI runs; no build needed
```

## Why a copy at all

`jl4/examples/legal/` is the language's regression corpus. Meng ruled on 2026-09-15 that a
handful of directories in canon join it — the ruling is quoted verbatim in
[`specs/todo/CANON-REGRESSION-CORPUS-SPEC.md`](../../../specs/todo/CANON-REGRESSION-CORPUS-SPEC.md)
§1. Two shapes were considered; **vendoring won** because the cross-repo alternative makes every
output-changing compiler PR re-bless goldens in a second repository before it can merge, and
makes every local developer carry a checkout path (spec §5).

A checked-in copy of another repository's files is duplication. The pin plus the `Canon Mirror`
CI job is what makes it **detected** duplication rather than the silent kind: the job fails the
moment this tree and canon at the pin disagree.

## How the pin works

`etc/canon-pin.json` names the repository, a 40-hex SHA, and the blessed directories as
`{from, to}` pairs — `from` a path in canon, `to` a path under this directory.

- **`--check`** (CI, every PR, no build) diffs this tree against canon at the pin.
  A differing **source** file is fatal: it means the mirror was hand-edited, or the pin moved
  without a pull. A differing **golden** is reported and is *not* fatal — see below.
- **`--pull`** rewrites the mirror from the pin. It rewrites rather than merges, so a file canon
  dropped disappears here too instead of lingering and looking blessed.
- **`--bump <sha>`** repoints the pin and pulls.

## Goldens, and why a stale one is not a failure

These goldens came from canon. When the compiler's output moves, canon's copies go stale — and
that is ordinary, not broken: it is the reason the pin exists.

**`--check` cannot tell you which of two things happened**, and does not pretend to. A stale
canon golden and a hand-edit of the mirror produce the identical diff. The difference is
non-fatal because making it fatal would block every l4-ide PR on canon's blessing cadence, not
because a hand-edit has been ruled out — so read the diff rather than the exit code. The only
legitimate way to move a golden here is to re-bless it in canon and bump the pin.

The regression itself still runs: `canon/**` is an ordinary golden glob in `jl4/tests/Main.hs`,
with the same semantics as `legal/**` — four goldens per file, `failFirstTime`. If the suite goes
red here, the compiler's output moved; re-bless **in canon** and bump the pin.

Blessing anywhere else in this repository means deleting the stale `.golden` and running
`cabal test jl4-test` twice — once to write it and fail, once to prove it holds (CLAUDE.md §3.1).
**Do not do that here.** It would make this repository's copy disagree with canon silently, which
is the one thing the pin exists to prevent.

## The one place this is not verbatim

Two blessed directories keep a cases file one level down, at `cases/x.l4`, while its goldens sit
in the directory-level `tests/`. `jl4/tests/Main.hs` derives a golden's path as
`takeDirectory inputFile </> "tests"`, so it would look for `cases/tests/x.golden` — and canon
has no `cases/tests/` directory anywhere. **The mirror therefore hoists `cases/*.l4` to the
directory root**, which is the only layout in which canon's own goldens are the ones the harness
reads.

Measured rather than assumed: both layouts pass `l4 check`, so imports resolve either way and the
hoist is about goldens alone. `sync-canon.mjs` applies the rule in one function used by both
`--pull` and `--check`, so the two cannot disagree about it, and refuses on a name collision
rather than silently keeping one file.

## What is here, and what is not

Carried: `*.l4`, `tests/*.golden`, `encoding.json`, `SOURCE-LICENSE.md`, and `registers/*.json`
(one level deep). The registers joined on 2026-09-23 (LODGER): they are the deposits `etc/go`
reads, so without them a subject whose encoding lives in canon cannot run the pipeline's ingest,
sweep, fork and differential stages.

Not carried: `source/`, `report/`, `app/`, `projections/`, `NOTES.md`, `README.md`, and anything
below `registers/` that is not a top-level `.json`.
The list is an **allowlist** — a new kind of file in canon needs an edit to `included()` in
`sync-canon.mjs` before it appears here, rather than arriving by default.

## Licensing

Each directory carries the `SOURCE-LICENSE.md` that came with it. The quoted legal text keeps its
own terms; read that file, not this one, for any given subject.
