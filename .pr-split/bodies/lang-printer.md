# fix(print): make prettyLayout re-emit source that means the same thing, and lock both printers with corpus-wide invariants

**What this adds.** L4 has two printers, and this PR repairs and guards both. `L4.Print.prettyLayout`
— the AST printer that `l4 batch` and the REPL use to reconstruct a module and re-run the front end
on it — could not render its own corpus back into parseable source, and where it *did* parse it
sometimes dropped brackets and silently changed the answer. It now emits source that re-parses,
re-type-checks and evaluates the same, with a new `prettyLayout round-trip` property asserted over
every file the golden suite type-checks. Separately, `exactprint` (what `l4 format` emits) gains an
`exactprint identity` invariant asserting `exactprint(parse f) == readFile f` for the whole corpus,
which replaces the per-file `.ep.golden` files as the real guard. After this lands, `l4 batch` works
on the Reg CF wizard, and neither printer can regress into mangling source without a test going red.

**Why.** `l4 batch` was reported broken in smucclaw/l4-ide#932: reconstructing `regcf-wizard.l4`
produced text the parser rejected (`incorrect indentation (got 75, should be greater than 180)`), so
the command failed before evaluating anything. `prettyLayout` had **no test of its own** — the
`.ep.golden` files guard the *other* printer — which is how it drifted that far. The exactprint side
has the mirror problem: a `.ep.golden` blesses whatever exactprint currently emits, so it silently
recorded mangled output for years (issue smucclaw/l4-ide#919: `PARTY Tenant DOES pay AT 30` printing
as `PARTY 30 / DOES Tenant AT pay`, exit 0). Both invariants exist so that the failure mode is a red
test rather than a quietly corrupted corpus.

## What's in it

**3 Haskell modules under `jl4-core/src/L4/` (+682 / −62)**

- `L4/Print.hs` (+536 / −62) — the bulk of the change. Grouped:
  - _Parseability._ Every structural line break becomes `vcatHard`, because prettyprinter's
    `vcat`/`vsep` separators are `FlatAlt Line _` and the Unbounded layout flattens them away inside
    a `group`, jamming keywords together (`PARTY AliceMUST deliverWITHIN 5HENCE FULFILLED`).
    `CONSIDER` branches and `HAS` fields go one per line without the comma separator (a trailing
    comma is eaten by whatever comma list the branch body ended in — that pair of facts *is* #932);
    `BRANCH` and `POST` gain `hang 2`; `LET`/`WHERE`/`Event` gain `align`; `DIVIDED` becomes
    `DIVIDED BY`; `TIMEZONE IS` is printed rather than dropped; an anonymous section no longer
    increments the `§` level (which had shifted every heading out by one and broke
    section-qualified resolution).
  - _Grouping, i.e. the silent-wrong-answer class._ New `parensIfOpenTailed` brackets a chain
    operand whose rendering has an open tail (comma list, clause list, binding group) or which is
    itself a connective. `scanOp` now caramelises as it descends, so a chain stored as
    `App __AND__` flattens properly instead of being re-bracketed into a nest that needs none.
  - _Names._ `mixfixHeadKeyword` prints a canonical mixfix name (`_ plus _`) by its head keyword, and
    is deliberately narrowed to names with a leading or trailing slot so it cannot rename an author's
    backtick-quoted `` `a _ b` ``. `QualifiedName` emits the real syntax `` `Section A`.name `` instead
    of the debugging gloss `name (qualified at section …)`. A bare word that spells a reserved word
    is now backticked (the prelude's set-difference operator is literally named `LESS`), with a
    one-element `keywordsUsableAsNames` exception for `LIST`.
  - _Gensym leak._ `OptionallyTypedName` drops a type annotation the checker invented, so
    `GIVEN x YIELD x` no longer prints `GIVEN x IS x12`.
  - _Round-trip of flags and clitics._ `DECIDE` re-emits its `@desc` (whose leading keywords carry
    `@export` / `@nonexhaustive`); the genitive clitic prints as `'s`, not `'S`, so
    recipient-qualified `RECORD`/`COMMIT`/`RECALL` re-lex; `FETCH`/`ENV` print as prefix keywords
    rather than `ENV OF "HOME"`; an inert element prints as the bare string literal it is, not
    `... "text"` (`...` is the infix AND operator).
  - Nested type applications, pattern arguments and `WITHIN`/`HENCE`/`LEST` bodies gain
    `parensIfNeeded`; obligations print via `group (hang 2 …)` so a `#TRACE` (line-oriented) keeps
    its `AT … WITH`.
- `L4/Print/Columnar.hs` (new, 129 lines) — a standalone, AST-agnostic ditto-grid emitter
  (`Cell`/`Grid`/`DittoOpts`/`renderDittoGrid`) that collapses repeated guard tokens in a `BRANCH`
  arm block to column-aligned carets (`^`), plus a ditto-aware `MultiWayIf` printer
  (`prettyLayoutDitto`) in `L4.Print`. **No AST node is added** — the parser never produces ditto (it
  is expanded in the lexer), so ditto stays an emission concern. Column width is measured with
  megaparsec's `Text.Megaparsec.Unicode.isWideChar`, the same function the lexer advances columns
  with, so a CJK or emoji glyph cannot silently misalign the caret grid.
- `L4/Parser/Anno.hs` (+17) — one new combinator, `optionalHole`: an optional component that
  contributes no `AnnoHole` when absent shifts every later hole by one and silently drops the last
  field's tokens, because `flattenConcreteNodes` zips holes against constructor fields positionally.
  This contributes exactly one empty hole instead.

**6 hspec specs under `jl4-core/test/` (574 lines, all new)** — `PrintRoundtripSpec` (prettyLayout
output re-parses: `DIVIDED BY`, prefix `EXPONENT`, `TIMEZONE IS`, GIVEN-parametrised `DECLARE`),
`FormatFidelitySpec` (exactprint identity for `TIMEZONE IS`, `UNLESS`, non-ASCII string literals,
multi-clause pattern `DECIDE`), `EventExactPrintSpec` (both `PARTY … DOES … AT …` clause orders plus
the multiline form), `BulletParserSpec` (the `•` bullet list syntax, including three misalignment
cases that must hard-fail to parse and the pinned `indentedGE` corner case), `RefAnnotationSpec`
(`@ref` attachment to AST nodes) and `DirectiveAmbiguitySpec` (an ambiguous-but-well-typed expression
under `#ASSERT` / `TIMEZONE IS` must be a diagnostic, not a process-killing `error` out of
`runCheckUnique`).

**The two corpus-wide invariants, in `jl4/tests/Main.hs`** (this PR's slice of that shared file) —
`describe "exactprint identity (source round-trips l4 format)"` and
`describe "prettyLayout round-trip (filter -> print -> parse; #932)"`, each `forM_` over
`ok/**` + `legal/**` + `jl4-core/libraries/*.l4`, with **no exclusions and no known-failure list**.
The round-trip body asserts three things per file: no inference-variable gensym reaches the output,
the printed text re-parses, the printed text re-type-checks. Two debugging affordances travel with
it: `JL4_PRETTY_DUMP_DIR` writes the whole emitted module as a plain `.l4` you can run `l4 check` on,
and `JL4_EVALDIFF` writes the *unfiltered* print beside each source file for the evaluation
differential (both documented in `CLAUDE.md` §3.2 / §3.2.1).

**1 new corpus example + 9 goldens** — `jl4/examples/ok/ref-annotation.l4` with its four
`jl4-test` goldens (the `@ref`-attachment fixture); four `.ep.golden` deltas that restore a postfix
mixfix operand exactprint had been dropping (`DECIDE same_module_postfix IS \`is even\`` →
`… IS 4 \`is even\``, and three more in `time-tests` / `postfix-with-variables` /
`mixfix-cross-module-postfix-call`); and one `.schema.golden` delta where builtin types now emit real
JSON Schema (`"type": "string"`) instead of a dangling `$ref: "#/$defs/STRING"`.

**Cabal slices** — `jl4-core.cabal` gains `L4.Print.Columnar` as an exposed module, the six new spec
modules in the test suite, and a `megaparsec >= 9.7` bound (that is the version that exports
`isWideChar`; `Columnar.hs` is its only importer in the tree).

## Evidence

Quoted from the source PRs.

**The #932 repair (#214).** Red control on the pre-fix tree at `regcf-wizard.l4:186`:
`incorrect indentation (got 75, should be greater than 180)`. Green: `l4 batch … -e "can this company
raise"` exits 0 and returns the assessment. The property measured against the pre-fix tree
(`22309472` plus the property):

| leg | pre-fix | after |
| --- | --- | --- |
| filter → print → **parse** | **50 / 300 fail** | 0 |
| filter → print → **type-check** | **24 / 300 fail** | 0 |
| gensym in output | **8 files** | 0 |

"(82 total, disjoint — the gensym check short-circuits.)"

**The silent-wrong-answer class (#214).** Measured by evaluation differential (`JL4_EVALDIFF`):
`prettyConj` printed chain operands bare, so `(TRUE OR FALSE) AND FALSE` and
`TRUE OR (FALSE AND FALSE)` both printed as `TRUE OR FALSE AND FALSE`. Through `l4 batch`, with no
diagnostic anywhere: `ok/logic.l4` went from `LIST TRUE, TRUE, FALSE, FALSE` to
`LIST TRUE, TRUE, TRUE, TRUE`; an assertion in `legal/regcf/regcf.l4` went **satisfied → failed**; a
deontic `PROVIDED` guard in `ceo-performance-award.l4` re-associated; `(NOT TRUE) OR TRUE` became
`NOT (TRUE OR TRUE)`. After the fix: "**288 of 291 comparable files identical**", the three that
differ stamping wall-clock transaction time and disagreeing with themselves across two runs of the
original.

**Attack surface (#214).** "21 hand-built probes through the real `l4 batch` pipeline", including
mixfix with `@infixl` fixity where evaluation is preserved (`1 quop 2 opdue 3` = 7,
`1 andop 2 hadop 3` = 1006), DEONTIC chains, CONSIDER patterns, backticked record fields, the clitic
form, sections and qualification, keyword-named identifiers, and "24 precedence-discriminating
expressions".

**The exactprint invariant (#130).** "New `FormatFidelitySpec` (jl4-core) round-trips each family;
**10/11 cases fail against the pre-fix parser** (the escaped-literal case coincidentally matches,
since old code decoded `\214`→Ö and re-escaped back)." "Whole corpus swept: **0/243** ok/legal/
libraries files non-identity under `l4 format`." "23 stale `.ep.golden` files were regenerated to
byte-identity with their sources."

**Event exactprint (#125).** "New `EventExactPrintSpec` round-trip tests (`exactprint . parse ≡ id`)
for both clause orders and the multiline form — all three fail against the old code."

**Bullet syntax (#109).** "`jl4-core-test`: all unit tests pass, including 9 new `BulletParserSpec`
cases." On the pinned `indentedGE` corner case: "A corpus sweep found **0 of 571 `.l4` files** hit
this today, so the behavior is pinned with a regression test … rather than the parser being
narrowed."

**Suite banners at the respective tips.** #214: `jl4-test` 2550/0, `jl4-core-test` 269/0,
`l4-cli-test` 202/0 (+79 pending), `jl4-service-test` 311/0, `jl4-lsp-test` 10/0, `cabal test all`
exit 0. #130: "jl4-core 219/0, jl4 goldens 1412/0 (incl. the new invariant)". #125: "jl4-core 169/0,
jl4 goldens 1120/0". #109: "full golden suite green (1116 examples)". #182: `jl4-test` 2062/0,
`jl4-core-test` 269/0. These are whole-tree figures at their tips, not figures for this slice.

**The honest bound, quoted (#214).** Two mixfix operators sharing a head keyword, arity and argument
type vector print to the same text; the corpus witness is `ok/mixfix-garden-path.l4`, "whose own
comment predicts it". It fails **loudly**, is **not a regression** (pre-fix it printed
`` `_ tax on _ item costing _ as VAT in _` ``, defined nowhere), and only via the unfiltered print.
Re-emitting the surface form instead "was **built, measured and rejected**": definitions print from
their restructured AppForm, so `ok/fixity-nary-guard.l4`'s `1 andop 2 hadop 3` stopped resolving.
Recorded at the function and in `CLAUDE.md` §3.2.2.

## Independence

**This PR does not compile on `main` alone.** `L4/Print.hs` pattern-matches AST shapes that
`lang-syntax-typecheck` and `lang-eval-ledger` ship:

- `MkTypedName` / `MkOptionallyTypedName` carry an extra `TYPICALLY` field on `unstable` (5 and 4
  fields; `main` has 4 and 3) — **lang-syntax-typecheck**.
- The `Exponent` constructor of `Expr` is *removed* on `unstable`, and this printer no longer has an
  arm for it — **lang-syntax-typecheck**.
- `Record` / `ReadCell` / `RecallMode` do not exist on `main`; the clitic-printing arms are theirs —
  **lang-eval-ledger**.

This edge is real but does not appear in `.pr-split/DEPENDENCIES.md`, because `depcheck.mjs`
resolves *module* imports and `L4.Syntax` is a module `main` already has. It is a
constructor-level dependency, not an import-level one.

**Five of the six new specs test other themes' code.** They live here because they are printer- and
exactprint-fidelity tests, but the behaviour each asserts arrives elsewhere and each is red without
it: `EventExactPrintSpec` and `FormatFidelitySpec` need the `ToConcreteNodes`/parser anno-capture
fixes in `L4/Syntax.hs` and `L4/Parser.hs`; `BulletParserSpec` needs the `•` lexer/parser rules;
`RefAnnotationSpec` needs `L4/Parser/ResolveAnnotation.hs` and `annRef`; `DirectiveAmbiguitySpec`
needs the `L4/TypeCheck.hs` repair — **all four files are owned by lang-syntax-typecheck**. Only
`PrintRoundtripSpec` tests code in this PR.

**Two of the golden deltas likewise encode other themes' behaviour.** The four `.ep.golden` files
record the restored postfix-mixfix operand from `fix(parser): add missing anno hole for funcName in
mixfixPostfixOp` — **lang-syntax-typecheck**. `mixfix-garden-path.schema.golden` records the repaired
`L4/JsonSchema.hs` output — **service-cli**. `ref-annotation.l4` and its four goldens are the fixture
for the `@ref` feature — **lang-syntax-typecheck** again.

**What is genuinely this PR's own:** `L4/Print.hs`, `L4/Print/Columnar.hs`, `L4/Parser/Anno.hs`,
`PrintRoundtripSpec.hs`, and the two invariants in `jl4/tests/Main.hs`. Nothing here is needed by a
sibling at compile time — no other theme's module imports `L4.Print.Columnar`, and `L4.Print` is
already on `main`.

**Ordering.** Land **lang-syntax-typecheck** first (and **lang-eval-ledger** before or with it);
then this. `service-cli` may land in any order relative to this one — only the single
`.schema.golden` line depends on it, and if it slips that golden can be reverted to what `main`
emits.

**Note on the `prettyLayout round-trip` property.** It has no exclusion list by design, so it is
sensitive to whatever `.l4` files are in `ok/**` and `legal/**` when it runs. The corpora that
`corpus-legal-new` and `corpus-regcf` add were part of the 300 files it was measured green over; if
those land after this PR, the property simply covers fewer files, and if they land before, it covers
them too. No corpus is known to fail it.

## Risk if rejected

`l4 batch` and the REPL stay broken on any module whose reconstruction the printer cannot render
(50/300 corpus files failed to re-parse before this), and — worse — the printer keeps silently
re-associating connectives, so `l4 batch` continues to return wrong answers with no diagnostic on
`ok/logic.l4`, `legal/regcf/regcf.l4` and `ceo-performance-award.l4`. Both printer invariants
disappear with it, leaving `.ep.golden` files as the only guard, which is exactly the arrangement
that blessed the mangled output in the first place; and `corpus-legal-new`'s
`promissory-note.golden`, which records the one-line residual obligation this printer produces, goes
red the moment that theme lands.

## Provenance

Unstable PRs folded into this one:

- **#214** — `mengwong/printer-batch-and-gensym`: the `prettyLayout` repair (parseability, grouping,
  gensym, mixfix head keyword, clitic) and the `prettyLayout round-trip` property.
- **#130** — `mengwong/format-fidelity`: `FormatFidelitySpec` and the `exactprint identity`
  invariant (the parser/lexer half of that PR is `lang-syntax-typecheck`).
- **#125** — `mengwong/fix-event-exactprint`: `EventExactPrintSpec` (the `L4/Syntax.hs` fix itself is
  `lang-syntax-typecheck`).
- **#109** — `mengwong/bullet-list-syntax`: `BulletParserSpec` (the `•` lexer/parser rules, the
  `hierarchy.l4` library and the docs are other themes).
- **#182** — `mengwong/bkm-phase05-oracle`: the `@desc` re-emission in the `Decide` printer, so a
  printed module does not lose its `@nonexhaustive` flag.

Three of the files here also carry work from unstable merges earlier than that list — `L4/Print.hs`
and `PrintRoundtripSpec.hs` from the `#66` print-round-trip batch merge and the `#83` dead-`Exponent`
removal, `L4/Print/Columnar.hs` from the `#42` dmnmd-to-L4 line, `L4/Parser/Anno.hs` from the
TYPICALLY salvage, and `RefAnnotationSpec.hs` / `DirectiveAmbiguitySpec.hs` from the `@ref`
attachment and `#56` ambiguity-crash work — which the file-level split assigns here because the
affected files are printer and printer-fidelity files.
