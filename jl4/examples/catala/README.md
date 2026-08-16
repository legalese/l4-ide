# `l4 catala` exhibits

Six L4 sources and the literate Catala they compile to. The goldens under
`expected/` are byte-for-byte what `l4 catala <file>.l4` prints, and
`jl4/tests-cli/Main.hs` pins them.

Every golden here has been run through the real toolchain (catala 1.2.1). The
repeatable way to do that is the R9 harness, which finds the toolchain on PATH,
in `CATALA_EXE`/`CLERK_EXE`, or in an opam switch, and skips with one line when
it finds none:

```
node etc/validate-catala.mjs
```

It runs both layers. `catala typecheck` says the emitted module is well-formed
and well-typed. `clerk test` is the interesting one: it re-runs each `#[test]`
scope and compares the ` ```catala-test-cli ` blocks, whose expected values were
computed by **L4's** evaluator, along with the Mode A/B equivalence grids
emitted under R4. A green `clerk test` is therefore evidence that the two
languages agree on those points — the middle tier of the OpenFisca doc's
three-tier claim ladder (golden / executed round-trip / law-validated), never
the third.

| file           | what it exercises                                                                                                                       |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `benefit.l4`   | spec Appendix A: `UNLESS` proviso → exception ladder, `WHERE` → `let … in`, a cross-decision call, one `#EVAL`                            |
| `bands.l4`     | a three-band rate table with nested guards — the case that pins the ladder's priority direction — plus `#ASSERT`                          |
| `statute.l4`   | the R8 weave: `§`/`§§` headings, inert scaffolding as law text, `@ref` citations, `@export <desc>` → `#[description]`, an enum + `CONSIDER` |
| `flat-tax.l4`  | a port of `../openfisca/flat-tax.l4`: R11 elides the never-inspected `period` string                                                     |
| `household.l4` | a port of `../openfisca/household.l4`: `LIST OF` group entity, `sum`∘`map` absorbed by R5, two R11 elisions                              |
| `tariff.l4`    | `CONSIDER` on an enumeration → `match`, and `TYPICALLY` → a `context` variable with an in-scope default (R10)                             |

The two ports compile **unchanged** from their OpenFisca originals — the same
L4 file feeds both backends, and what makes it Catala-clean is R11 rather than
any edit. The originals stay where they are (the OpenFisca goldens pin them);
these copies exist so this directory is self-contained.

The module name Catala sees comes from the **output file's** basename, so these
are checked under the name Catala wants (`flat-tax.catala_en` declares
`Module FlatTax`, so the harness stages it as `FlatTax.catala_en`) and compared
against the goldens as printed to stdout, where the module name comes from the
L4 basename.
