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

## What stays here, and why that is not a defect

A subject that is already in canon **moves** there (moved, not lost). A subject that is not in
canon **stays here**, and the ruling says that is fine. As of 2026-09-15 that means `regcf`, `bna`,
`charities-cleanroom` and the single-file subjects (`anti-social.l4`,
`british-citizen-act.l4`, `ceo-performance-award.l4`, `directive-showcase.l4`,
`imaginary-alcohol-act.l4`, `ny-environmental-7.3.l4`, `promissory-note.l4`) live here and are
not scheduled to go anywhere.

`chubb/` and `sg-succession/` **are** duplicated in canon today and are the two the migration
retires — see spec §4. **That migration has not happened.** Until it does, both copies exist and
both are globbed; do not treat the duplication as settled either way.

## Adding a file here

Four goldens ship in the same commit as the `.l4`, or the whole suite goes red for the next person
— `failFirstTime` is `True`, so a file with no `tests/` directory fails rather than quietly
blessing itself. `etc/check-corpus-goldens.mjs` runs on every PR with no path filter and names
what is missing. See `CLAUDE.md` §3.1 for the full rule and the two incidents that produced it.
