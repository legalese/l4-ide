# `l4 catala` exhibits

Seven L4 sources and the literate Catala they compile to, plus the
`--boolean-only` rendering of one of them. The goldens under `expected/` are
byte-for-byte what `l4 catala <file>.l4` prints, and `jl4/tests-cli/Main.hs`
pins them. `not-ok/` holds five sources that `l4 catala` **refuses**, each
because emitting it would have made the Catala say something other than the L4
says; `tests-cli` pins the refusals.

Every golden here has been run through the real toolchain (catala 1.2.1). The
repeatable way to do that is the R9 harness, which finds the toolchain on PATH,
in `CATALA_EXE`/`CLERK_EXE`, or in an opam switch, and skips with one line when
it finds none:

```
node etc/validate-catala.mjs
```

It runs three layers. `catala typecheck` says the emitted module is
well-formed and well-typed. `catala proof` says no two rungs of a Mode B
exception ladder can fire at once — the one check that would notice if the
ladder builder started emitting siblings instead of a linear chain; its
`NoEmptyError` half is reported but not enforced, because Z3 cannot encode our
structures and reports false positives (see the header of the harness, and
§8.4). `clerk test` is the interesting one: it re-runs each `#[test]`
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

The module name Catala sees comes from the **output file's** basename, with its
first letter capitalised — not a CamelCasing of it, so no file named
`flat-tax.catala_en` can host any module at all. These goldens are named after
their L4 sources, so the harness stages each one, under the name its own
`> Module` line claims, in its own scratch subdirectory (`flat-tax.catala_en`
declares `Module FlatTax`, and is staged as `flat-tax/FlatTax.catala_en`). Each
golden keeps its own directory because two goldens may legitimately declare the
same module — `bands.catala_en` and `bands-boolean-only.catala_en` are two
renderings of one source and both say `> Module Bands`. The goldens themselves
are compared against stdout, where the module name comes from the L4 basename.

`l4 catala -o` rejects an output basename that cannot be a Catala module name,
rather than writing a file the toolchain will refuse.

### `not-ok/`

| file                             | why it is refused                                                                                              |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `otherwise-not-last.l4`          | an `OTHERWISE` before a `WHEN` shadows it under first-match; an if/else chain assembled arms-then-default would not |
| `otherwise-not-last-enum.l4`     | the same, over constructor patterns, where Catala's `-- anything` must be written last                          |
| `local-name-shadow.l4`           | two `WHERE` locals mangle to one Catala identifier, and Catala's `let` shadows silently                         |
| `elided-string-compared.l4`      | whole-record equality reads the field R11 elided, so Catala compares a narrower record than L4 does (§8.11)      |
| `enum-constructor-collision.l4`  | two enumerations' constructors mangle to one capitalised name, which Catala reports as ambiguous                 |
