# feat(proleg): jl4-proleg — canonical PROLEG front end and a burden-of-proof monad

**What this adds**

A new, self-contained Haskell package `jl4-proleg` that teaches the repo to read and write
**canonical PROLEG** — Satoh's Prolog-based encoding of the Japanese Civil Code (JURISIN 2010) —
and that implements **burden of proof as a first-class programming construct**. Before this, the
tree had no way to ingest a PROLEG rulebase at all, and no representation of *which party must
establish which fact*: a defeasible rule could be evaluated to true or false, but the answer carried
no attribution. After this, a `.pl` file in the canonical dialect parses to a typed AST and prints
back to canonical source (`parse . print == id` on the AST), and a derivation carries an
**obligation ledger** alongside its truth value, so a failed claim reports not just "not
established" but "and here is who failed to discharge the burden". The same construct is written a
second time in L4 itself (`l4/burden.l4`), so the burden algebra is executable in the language, not
only in the compiler that hosts it.

**Why**

Two gaps drove it. First, PROLEG is the largest existing corpus of machine-executable civil-code
rules and the natural import source for L4; getting there needs a front end for its concrete syntax,
and this is the phase-1 half (read + print) of the eventual two-way transpiler. Second, and more
fundamental: PROLEG's `plaintiff`/`defendant` arguments are a *burden* role, and the standing
danger is that a transpiler quietly synthesises them into L4 `PARTY … MUST` obligations — conflating
"who must prove it" with "who is on the hook". Making burden its own typed layer, with its own
combination laws, is what makes that conflation a type error rather than a judgement call. The
source commits name no upstream issue number.

**What's in it**

_Haskell library (4 modules, `src/L4/Proleg/`)_

- `Syntax.hs` — the canonical-PROLEG AST: `Program`/`Clause` (rule, exception, procedural
  declaration, fact), Prolog `Term` (var, atom, int, string, compound, list-with-tail), and the
  JUF litigation layer `ProcDecl` = `allege` / `provide_evidence` / `admission` / `plausible`.
  Clauses are kept in source order; the rulebase/factbase split is a *view*, not a parse-time
  partition.
- `Parser.hs` — a hand-rolled backtracking recursive-descent parser (a small `P` monad over
  `String`), deliberately written against `base` + `text` only so the front end compiles without
  the rest of the jl4 build. Covers the canonical dialect; recognition is by clause shape.
- `Print.hs` — the canonical printer. It normalises layout (one conjunct per line) rather than
  preserving bytes; the law it targets is `parse (print p) == p` on the AST, and the module says so
  in its header, which is the honest framing — this is *not* an exact-printer.
- `Burden.hs` — `type Provable = MaybeT (Writer [Obligation])`, with `prove`, `established`,
  `unestablished`, `conj`, `disj`, `notProven`, `flipBurden`, `absent`, `resolve`, `obligations`.
  `conj`/`disj` are deliberately **accumulating, not short-circuiting**, so the ledger reflects the
  rule rather than the run; `MaybeT` is on the outside precisely so the ledger survives a failed
  proof.

_Tests (2 test-suites)_

- `test/Roundtrip.hs` — parses each fixture, prints it, re-parses, asserts AST equality.
- `test/Burden.hs` — replays the lease judgement through the monad: 8 assertions covering the
  outcome of each claim and defence, the party attribution of two ledger entries, and
  `flipBurden`'s involution and subject-swap laws.

_Fixtures (2 `.pl` files)_

`examples/lease.pl` (65 lines) is the JURISIN 2010 Appendix A rulebase + factbase — Japanese Civil
Code Art. 612 plus the Supreme Court rule of 1966.1.27 — in the propositional (0-arity) dialect;
its header names it the phase-2 anchor, the file a PROLEG→L4 translation must agree with on `#EVAL`.
`examples/minor-duress.pl` (56 lines) is the first-order dialect: rescission by a minor buyer,
defeated by duress, from Satoh's alice/bob real-estate demonstration, with predicates carrying
positional untyped arguments — the phase-3 anchor for type reconstruction. Its header records that
the original slides contain identifier typos (`minifestation_by_duress`, `Maniester`, `Mnifestee`)
which untyped Prolog tolerates silently and which are corrected in the fixture, noting that this is
exactly the class of latent bug a name-and-type-checked target is meant to surface.

_The construct in L4 (`l4/burden.l4`, 185 lines)_

`Provable` as an L4 record (`MAYBE BOOLEAN` truth + `LIST OF Obligation`), with the combinators
rewritten as L4 functions — L4 has no `Monad` class, so the monad lives in the engine and the
algebra surfaces as explicit combinators. The file then encodes the lease factbase and closes with
7 `#EVAL`s and 4 `#ASSERT`s.

_Docs (2 files)_

- `docs/proleg-concrete-syntax.md` (104 lines) — the grammar the front end parses: lexical
  structure, the `<=` operator table, EBNF, the rulebase/factbase distinction, the defeasibility
  and burden semantics to preserve, and an explicit **dialect note** on Modular-PROLEG/PIL
  (`#Country` tags, `negation/1`, `solve/3` phases) marked out of scope for phase 1.
- `docs/burden-of-proof.md` (265 lines) — the theory note. It identifies the construct as the
  coreader/env comonad upgraded to a `Writer` monad once the subject carries a monoid, argues the
  transformer stacking order as a *semantic* choice (keep blame on failure), reads the monoid
  identity as the legal *presumption* (`(∨, False)` = innocent-until-proven-guilty vs `(∧, True)`
  = rebuttable presumption of the claim; same elements, different unit, different morality),
  distinguishes rebuttable presumption (identity) from conclusive presumption / *jus cogens*
  (absorbing element), gives the PROLEG ↔ `Provable` ↔ ASP correspondence table, and states the
  non-conflation rule that burden must never be routed into an L4 deontic obligation. It carries an
  honest **Status** paragraph: `resolve` currently fixes the unit to `False` for every proposition,
  and making the presumption per-proposition is named as the next refinement.

**Evidence**

The source commit reports its results qualitatively, and this PR does not go beyond them:

> `L4.Proleg.{Syntax,Parser,Print}`: hand-rolled PROLEG AST + term reader (base+text only);
> parse/print roundtrip on the JURISIN lease and minor/duress fixtures.
> `L4.Proleg.Burden`: the `Provable = MaybeT (Writer [Obligation])` burden monad; reproduces the
> lease judgement with a party-attributed obligation ledger.
> `l4/burden.l4`: the burden construct expressed in L4, validated via jl4-cli.

`docs/burden-of-proof.md` §6.1 states the same result as a validated worked example: evaluating
`contract_end` over the `examples/lease.pl` factbase "reproduces the paper's judgement" — the
plaintiff prevails, the defendant's `get_approval_of_sublease` defence fails because its facts are
alleged but not `plausible`, the `nonabuse_of_confidence` defence is defeated by the plaintiff's
`abuse_of_confidence` (exception-of-exception), and the ledger attributes each of those two facts to
the right party. **No quantitative claims — no pass counts, coverage percentages or agreement
rates — were made in the source commits**, and none are asserted here. The corpus-scale PROLEG
validation (2009–2022 bar exam) is cited in the docs as background on the *dialect*, not as a result
of this package.

**Independence**

This is as close to standalone as anything in the split.

- **Build**: the library's only dependencies are `base`, `text` and `transformers`. It does **not**
  depend on `jl4-core`, `jl4`, or any other package in the tree, by design — the parser module
  header says so explicitly ("so the PROLEG front end stays standalone and compiles without the rest
  of the jl4 build"). `transformers` is already a dependency of `jl4`, `jl4-lsp` and `jl4-service`
  on `main`, so no new resolver constraint is introduced.
- **One line outside the manifest**: the package must be registered in `cabal.project`
  (`  ./jl4-proleg`). No theme in the split owns `cabal.project`, so this PR should carry that
  single added line. It is purely additive — it does **not** touch the `./jl4-actus-analyzer` entry,
  whose removal now rides in [#257](https://github.com/legalese/l4-ide/pull/257) (formerly the **actus-archive** theme).
- **Goldens**: none, and none are needed. `jl4-proleg/l4/burden.l4` sits outside every glob
  `jl4/tests/Main.hs` walks (`jl4/examples/ok/**`, `legal/**`, `not-ok/**`, `jl4-core/libraries/*`),
  so it neither requires a `tests/` directory nor can trip `etc/check-corpus-goldens.mjs`. Its two
  Haskell test-suites are self-checking and read only this package's own fixtures. Nothing here
  encodes behaviour owned by another theme.
- **Language features**: `burden.l4` uses only constructs already present on `main` — `MAYBE`/`JUST`/
  `NOTHING`, record `DECLARE`/`WITH`, `CONSIDER`/`WHEN`, `FOLLOWED BY`, `'s` projection, `#EVAL`,
  `#ASSERT`, `§§` sections. It does not depend on any of the language-core work consolidated in #257.
- **Reverse dependencies** (siblings that cite *this*, not the other way round): the **specs**
  theme's `specs/done/STATE-AS-LEDGER-SPEC.md` names `jl4-proleg/src/L4/Proleg/Burden.hs` as the
  already-implemented Writer lane it generalises, and cites this package's transformer-order choice,
  its bearer≠establishment reading and its non-conflation rule. The **papers** theme's ICAIL
  submission (`paper/icail/l4-icail.tex` and the Japanese `l4-icail-ja.tex`) has an appendix
  `app:burden` / `app:burdenl4` that quotes `Burden.hs` and `burden.l4` as figures. Those two themes
  read better with this one landed, but neither is *blocked* by it.
- **CI**: the package is wired into no workflow beyond whatever `cabal build all` / `cabal test all`
  picks up once it is in `cabal.project`. Reviewers should expect the two new test-suites to start
  running on the Haskell job.

**Risk if rejected**

Dropping this loses the only PROLEG ingest path in the tree and the only implementation of burden of
proof as an attributable, composable value — which is the construct the ICAIL paper's appendix and
`STATE-AS-LEDGER-SPEC.md`'s Writer lane both point at, so both would ship with dangling references
to code that does not exist. Nothing else breaks: no sibling compiles against this package, and no
golden or test outside `jl4-proleg/` observes it.

**Provenance**

No numbered `unstable` PR maps to this theme — the manifest lists none, and the work reached
`unstable` as direct commits:

- `f82099c3` — `jl4-proleg: PROLEG<->L4 transpiler scaffold + burden-of-proof monad` (9 Jun 2026)
- `12166c63` — `fix(jl4-proleg): correct roundtrip test fixture paths for cabal test` (6 Jul 2026)
  — `cabal test` runs test binaries with cwd set to the package directory, not the repo root, so
  the fixture paths are relative to `jl4-proleg/`. Folded in; the fixed paths are what this PR
  carries.
- `0b6091c2` — `chore(format): prettier --write docs/specs added by batched PRs` (formatting only,
  touching `docs/proleg-concrete-syntax.md` among many files; the reformatted text is what is
  carried here).
## Blast radius

**12 new files**, 1 modified.

Build registration only:

- `cabal.project` — registers the package in the build

**No file outside the new jl4-proleg package is touched, and no existing production source is modified.**

The package is **inert with respect to the rest of the tree, in both directions**:

- **Nothing depends on it.** No `.cabal` in the repo lists `jl4-proleg`; no source outside
  `jl4-proleg/` imports `L4.Proleg`; it appears in no nix, release or CI configuration.
- **It depends on nothing here.** Its `build-depends` are `base`, `text` and `transformers`. It does
  not link `jl4-core` and references no compiler type.

That second point is the one that matters, and it is where `jl4-actus-analyzer` differed: that
package *did* list `jl4-core` and *did* pattern-match `MkTypedName`, so it sat in `cabal build all`
as a hostage — widening a constructor in the compiler broke it, which is exactly why removing it
became a mandatory member of the #257 interlock. `jl4-proleg` cannot do that.

Removing it later, should it not earn its keep, is `rm -rf jl4-proleg/` plus one line of
`cabal.project`, with no possibility of regression elsewhere.

