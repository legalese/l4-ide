# `l4 catala` exhibits

Three L4 sources and the literate Catala they compile to. The goldens under
`expected/` are byte-for-byte what `l4 catala <file>.l4` prints, and
`jl4/tests-cli/Main.hs` pins them.

Every golden here has been run through the real toolchain (catala 1.2.1):

```
opam exec --switch=catala -- clerk start          # once, in a scratch directory
opam exec --switch=catala -- catala typecheck Benefit.catala_en
opam exec --switch=catala -- clerk test Benefit.catala_en
```

`clerk test` is the interesting one: it re-runs each `#[test]` scope and
compares the ` ```catala-test-cli ` blocks, whose expected values were computed
by **L4's** evaluator. A green `clerk test` is therefore evidence that the two
languages agree on those points — the middle tier of the OpenFisca doc's
three-tier claim ladder (golden / executed round-trip / law-validated), never
the third.

| file | what it exercises |
| ---- | ----------------- |
| `benefit.l4` | spec Appendix A: `UNLESS` proviso → exception ladder, `WHERE` → `let … in`, a cross-decision call, one `#EVAL` |
| `bands.l4` | a three-band rate table with nested guards — the case that pins the ladder's priority direction — plus `#ASSERT` |
| `statute.l4` | the R8 weave: `§`/`§§` headings, inert scaffolding as law text, `@ref` citations, `@export <desc>` → `#[description]`, an enum + `CONSIDER` |

The module name Catala sees comes from the **output file's** basename, so these
are generated with `-o Benefit.catala_en` when run against the toolchain, and to
stdout (module name from the L4 basename) when compared against the goldens.
