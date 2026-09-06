# Catala

## What Catala is

[Catala](https://catala-lang.org) is a programming language built specifically for writing down
law. It comes out of programming-languages research, and it makes two commitments that no
general-purpose language makes.

The first is **literate**. A Catala program interleaves the text of the statute with the code that
formalises it: you read the article, then immediately the rule derived from it. The document is
simultaneously the legal source and the executable artifact, which is what makes it reviewable by
a lawyer who does not read code.

The second is **defaults and exceptions**. Legislation is not written as a decision procedure; it
is written as a general rule, followed by provisos that override it, followed sometimes by
exceptions to the provisos. Catala's semantics is built around exactly that shape, so a proviso is
expressed _as_ an exception to a rule rather than being flattened by hand into a nest of
conditionals. Catala can then check, mechanically, that no two exceptions can fire at once.

Catala compiles to ordinary languages (OCaml, Python and others) and has been used to reimplement
parts of real tax and benefit law.

## Why compile L4 to it

L4 and Catala are close cousins solving the same problem, which makes the export unusually
high-fidelity — and unusually useful as a cross-check.

- **You get a document a lawyer can review.** The emitted module weaves your `§` headings, inert
  scaffolding and `@ref` citations into the Catala source as law text, so the statute and the
  formalisation sit side by side on the page.
- **Provisos stay provisos.** An L4 `UNLESS` becomes a Catala exception ladder rather than being
  compiled away, so the structure a drafter would recognise survives into the target.
- **You get machine-checked agreement between two independent implementations.** This is the real
  prize. The generated module carries test scopes whose expected values were computed by **L4's**
  evaluator; running Catala's own `clerk test` then checks Catala's answers against them. Two
  languages with separately written evaluators agreeing on the same rules is far stronger evidence
  than either being self-consistent.
- **Catala's prover can inspect the ladder.** `catala proof` verifies that no two rungs of an
  exception ladder can fire simultaneously.

## The command

```
l4 catala FILE
```

Compiles the constitutive subset of `FILE` to a literate Catala module, printed to standard output.

| Flag             | Effect                                                                             |
| ---------------- | ---------------------------------------------------------------------------------- |
| `--output FILE`  | write the generated `.catala_en` to `FILE` instead of stdout                       |
| `--boolean-only` | emit only the plain boolean rendering — no exception ladders, no equivalence grids |

One sharp edge worth knowing before it bites: Catala takes a module's name from the **output
file's** basename, capitalised — not CamelCased. A file named `flat-tax.catala_en` therefore
cannot host any module at all, so `l4 catala --output` rejects a basename that could not be a legal
Catala module name rather than writing a file the toolchain would refuse.

## What it consumes

The **constitutive subset** — the definitional layer of L4. `WHERE` bindings become `let … in`,
`CONSIDER` over an enumeration becomes a `match`, `UNLESS` provisos become exception ladders, and
`TYPICALLY` becomes a Catala `context` variable carrying an in-scope default.

A pleasant consequence of both backends taking the same subset: the OpenFisca examples compile to
Catala **unchanged**. The same L4 file feeds both bridges with no edits.

## What doesn't survive

Catala does not emit a fidelity report. Instead it **refuses**: where emitting something would make
the Catala assert what the L4 does not, the compiler stops. The examples directory keeps five
sources specifically to pin those refusals.

The one systematic elision is that a value the rules never actually inspect — a `period` string
threaded through but never read, say — is dropped rather than modelled, since Catala's type system
has no place to put it.

## Where to look

- **Worked examples:** `jl4/examples/catala/`, with byte-for-byte goldens pinned by the test suite
  and a `not-ok/` directory of deliberate refusals.
- **Design and rulings:** `CATALA-EXPORT-SPEC.md` under `specs/`.
- **Evidence:** the goldens have been run through the real toolchain at Catala 1.2.1 —
  `catala typecheck`, `catala proof`, and `clerk test` — via `etc/validate-catala.mjs`, which skips
  cleanly when no toolchain is installed.
