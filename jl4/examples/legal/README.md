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

## The migration happened — what left, and what deliberately did not

Done 2026-09-16. **`chubb` and `sg-succession`'s committed encodings are now in
[`../canon/`](../canon/)** and are globbed from there:

| was | is now |
| --- | --- |
| `chubb/chubb.l4` | `canon/us/chubb-hospital-cash/blind-inert/chubb.l4` |
| `chubb/denovo/chubb-denovo.l4` | `canon/us/chubb-hospital-cash/blind-guarded/chubb-denovo.l4` |
| `sg-succession/*.l4` (7) | `canon/sg/succession/*.l4` |

Their goldens moved with them. **45 files left this directory; not one was lost.**

**Two things stayed, and both are deliberate.**

**`sg-succession/cleanroom-2026-08/`** — 6 `.l4` and 24 goldens — is an encoding
canon holds but the pin does **not** bless, so **the mirror carries none of it**.
That is why it stayed: deleting it would have dropped six corpus files and their
goldens from the regression suite with nothing to replace them. It is fully
self-contained — every import is a sibling inside it — so it stands alone now that
its parent's top-level files have gone.

An earlier draft of this paragraph said the copy here was "the healthy one". It is
not, and the claim is retracted: the two copies' goldens are byte-identical but for
one column count, both were blessed by an older binary, and the diagnostic that
makes two files exit non-zero is Info-level and comes from `daydate.l4:104`, a
library neither copy owns. This copy is partly swept for clitic verbs and canon's
is not — less dirty, not healthy. Re-blessing canon's copy is boarded as a
canon-side job.

**The deposit JSONs** — `chubb/denovo/*.json` and
`sg-succession/cleanroom-2026-08/*.json` — stayed because **the mirror's allowlist
does not carry `registers/`**: it takes `.l4`, `tests/*.golden`, `encoding.json`
and `SOURCE-LICENSE.md` and nothing else. `etc/go/subjects/{chubb,sg-succession}`
still point at them here, and only their *corpus-module* paths were retargeted.
Whether `registers/*.json` should join the mirror is open, and is really the
question of how `etc/go` addresses a canon-hosted subject.

This is the ruling working as written, not an exception to it: *"there would also
be some corpora left inside jl4/examples/legal that are not in canon, and that's
ok too."*

## What stays here, and why that is not a defect

A subject that is already in canon **moves** there (moved, not lost). A subject that is not in
canon **stays here**, and the ruling says that is fine. As of 2026-09-15 that means `regcf`, `bna`,
`charities-cleanroom` and the single-file subjects (`anti-social.l4`,
`british-citizen-act.l4`, `ceo-performance-award.l4`, `directive-showcase.l4`,
`imaginary-alcohol-act.l4`, `ny-environmental-7.3.l4`, `promissory-note.l4`) live here and are
not scheduled to go anywhere.

~~`chubb/` and `sg-succession/` **are** duplicated in canon today and are the two the migration
retires.~~ **Done 2026-09-16 — see the section above.** The duplication is gone; what remains here
under those two names is the material the mirror does not carry, listed above.

## Adding a file here

Four goldens ship in the same commit as the `.l4`, or the whole suite goes red for the next person
— `failFirstTime` is `True`, so a file with no `tests/` directory fails rather than quietly
blessing itself. `etc/check-corpus-goldens.mjs` runs on every PR with no path filter and names
what is missing. See `CLAUDE.md` §3.1 for the full rule and the two incidents that produced it.
