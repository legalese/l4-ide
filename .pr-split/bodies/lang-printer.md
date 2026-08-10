# fix(print): make both printers round-trip, and lock them with corpus-wide invariants

**What this adds.** L4 has two printers, and this PR repairs one and guards both.
`L4.Print.prettyLayout` — the AST printer that `l4 batch` and the REPL use to reconstruct a module
and re-run the front end on it — had drifted to where it could not render its own corpus back into
parseable source, and where the output *did* parse it sometimes dropped brackets and silently changed
the answer. It now emits source that re-parses, re-type-checks and evaluates the same, and a new
`prettyLayout round-trip` property asserts that over every file the golden suite type-checks, with no
exclusions and no known-failure list. Alongside it, `exactprint` (what `l4 format` emits) gains an
`exactprint identity` invariant — `exactprint(parse f) == readFile f` for the whole corpus — which is
a real guard where the per-file `.ep.golden` files were not. After this lands, `l4 batch` works on the
Reg CF wizard, and neither printer can regress into mangling source without a test going red.

**Why.** `l4 batch` was reported broken in smucclaw/l4-ide#932: reconstructing `regcf-wizard.l4`
produced text the parser rejected (`incorrect indentation (got 75, should be greater than 180)`), so
the command failed before it evaluated anything. `prettyLayout` had **no test of its own** — the
`.ep.golden` files exercise the *other* printer — which is how it drifted that far unnoticed. The
exactprint side has the mirror problem: a `.ep.golden` blesses whatever exactprint currently emits, so
it silently recorded mangled output for years, which is smucclaw/l4-ide#919 (`PARTY Tenant DOES pay
AT 30` printing as `PARTY 30 / DOES Tenant AT pay`, exit 0, on every regulative corpus file). Both
invariants exist so that the failure mode of a printer bug is a red test, not a quietly corrupted
corpus.

## What's in it

### 3 Haskell modules under `jl4-core/src/L4/` (+682 / −62)

**`L4/Print.hs` (+536 / −62)** — the substance. Four groups:

- _Parseability._ Every structural line break becomes `vcatHard`, because prettyprinter's
  `vcat`/`vsep` separators are `FlatAlt Line _` and the Unbounded layout flattens them away inside a
  `group`, jamming keywords together (`PARTY AliceMUST deliverWITHIN 5HENCE FULFILLED`). `CONSIDER`
  branches and `HAS` fields print one per line *without* the comma separator — a trailing comma is
  eaten by whatever comma list the branch body ended in, and continuation lines must start at exactly
  the first branch's column; that pair of facts is #932. `BRANCH` and `POST` gain `hang 2`,
  `LET`/`WHERE`/`Event` gain `align`, `DIVIDED` becomes `DIVIDED BY`, `TIMEZONE IS` is printed rather
  than dropped, and an anonymous section no longer increments the `§` level (which had shifted every
  heading out by one and broken section-qualified resolution).
- _Grouping — the silent-wrong-answer class._ A new `parensIfOpenTailed` brackets a chain operand
  whose rendering has an open tail (comma list, clause list, binding group) **or** which is itself a
  connective, since `scanAnd`/`scanOr` flatten only their own operator and a bare nested connective
  hands its grouping back to the parser's precedence table. `scanOp` now caramelises as it descends,
  so a chain the checker left as `App __AND__` flattens properly instead of being re-bracketed into
  an associative nest that needs none. Comparisons were measured safe and stay bare.
- _Names._ `mixfixHeadKeyword` prints a canonical mixfix name (`_ plus _`) by its head keyword, and
  is deliberately narrowed to names with a leading or trailing slot so it cannot rename an author's
  backtick-quoted `` `a _ b` ``. `QualifiedName` emits the real syntax `` `Section A`.name `` instead
  of the debugging gloss `name (qualified at section …)`, which no parser accepts. A bare word that
  spells a reserved word is now backticked — the prelude's set-difference operator is literally named
  `LESS` — with a one-element `keywordsUsableAsNames` exception for `LIST`, documented with the
  `tokenAsName` grep that justifies it.
- _Round-tripping what the checker added or the lexer insists on._ `OptionallyTypedName` drops a type
  annotation the checker invented, so `GIVEN x YIELD x` no longer prints `GIVEN x IS x12`; `DECIDE`
  re-emits its `@desc`, whose leading keywords carry the `@export` / `@nonexhaustive` flags; the
  genitive clitic prints as `'s`, not `'S`, so recipient-qualified `RECORD`/`COMMIT`/`RECALL` re-lex;
  `FETCH`/`ENV` print as prefix keywords rather than `ENV OF "HOME"`; an inert element prints as the
  bare string literal it is, not `... "text"` (`...` is the infix AND operator). Nested type
  applications, pattern arguments and `WITHIN`/`HENCE`/`LEST` bodies gain `parensIfNeeded`, and an
  obligation prints via `group (hang 2 …)` so a line-oriented `#TRACE` keeps its `AT … WITH`.

Every one of these carries its measurement in a comment at the site, including the two that were
tried and rejected.

**`L4/Print/Columnar.hs` (new, 129 lines)** — a standalone, AST-agnostic ditto-grid primitive
(`Cell` / `Grid` / `DittoOpts` / `renderDittoGrid`) that collapses repeated guard tokens in a `BRANCH`
arm block to column-aligned carets (`^`), plus a ditto-aware `MultiWayIf` printer
(`prettyLayoutDitto` / `prettyLayoutDitto'`) in `L4.Print`. **Purely additive and not yet wired into
any live path** — it has no importer in the tree today, by design; PR #42 describes it as "a
ready-to-use building block", the counterpart to the ditto grid in dmnmd's `--to=l4` backend. No AST
node is added: the parser never produces ditto (the lexer expands it), so a `Ditto` constructor could
never round-trip. Column width is measured with megaparsec's `Text.Megaparsec.Unicode.isWideChar` —
the same function the lexer advances columns with — so a CJK or emoji glyph cannot silently misalign
the caret grid and copy the wrong token.

**`L4/Parser/Anno.hs` (+17)** — one new combinator, `optionalHole`. `flattenConcreteNodes` zips a
node's `AnnoHole`s against its constructor fields *positionally*, so an optional component that
contributes no hole when absent shifts every later hole by one and silently drops the last field's
tokens. This contributes exactly one empty hole instead.

### 6 hspec specs under `jl4-core/test/` (574 lines, all new)

| spec | asserts |
| --- | --- |
| `PrintRoundtripSpec` | `prettyLayout` output re-parses: `DIVIDED BY`, prefix `EXPONENT`, `TIMEZONE IS`, GIVEN-parametrised `DECLARE`/`ASSUME` |
| `FormatFidelitySpec` | `exactprint . parse ≡ id` for `TIMEZONE IS`, `UNLESS`, non-ASCII string literals, multi-clause pattern `DECIDE` |
| `EventExactPrintSpec` | the same identity for both `PARTY … DOES … AT …` clause orders and the multiline form |
| `BulletParserSpec` | the `•` bullet-list syntax — singletons, a bullet block beside a scalar arg, sibling blocks at different columns, three misalignments that must hard-fail, and the pinned `indentedGE` corner case |
| `RefAnnotationSpec` | `@ref` attaches to the following AST node, including the leading-`@ref`-is-not-the-Module regression |
| `DirectiveAmbiguitySpec` | an ambiguous-but-well-typed expression under `#ASSERT` / `TIMEZONE IS` is a diagnostic, not a process-killing `error` out of `runCheckUnique` |

### The two corpus-wide invariants (this PR's slice of `jl4/tests/Main.hs`)

`describe "exactprint identity (source round-trips l4 format)"` and
`describe "prettyLayout round-trip (filter -> print -> parse; #932)"`, each `forM_` over
`ok/**` + `legal/**` + `jl4-core/libraries/*.l4`. The round-trip body asserts three things per file:
no inference-variable gensym reaches the output, the printed text re-parses, and the printed text
re-type-checks — the last because parsing is necessary but not sufficient, since a printer that drops
a bracket produces source that parses into a *different* tree. Gensyms are named precisely (every
`InfVar` rendering in the module, matched at word boundaries) rather than pattern-matched as
"identifier ending in digits", which would false-positive on `identity1`, `const1a`, `s24`. Two
debugging affordances travel with it: `JL4_PRETTY_DUMP_DIR` writes the whole emitted module out as a
plain `.l4` you can run `l4 check` on (the output is thousands of columns wide), and `JL4_EVALDIFF`
writes the *unfiltered* print beside each source file for the by-hand evaluation differential. Both
are documented in `CLAUDE.md` §3.2 / §3.2.1, including the cleanup the second one requires.

### 1 new corpus example and 9 goldens

- `jl4/examples/ok/ref-annotation.l4` with its four `jl4-test` goldens — the fixture for `@ref` on
  expression-level nodes.
- Four `.ep.golden` deltas that restore a postfix-mixfix operand exactprint had been dropping:
  `DECIDE same_module_postfix IS \`is even\`` → `… IS 4 \`is even\``, plus the same shape in
  `time-tests`, `postfix-with-variables` and `mixfix-cross-module-postfix-call`.
- One `.schema.golden` delta where builtin types now emit real JSON Schema (`"type": "string"`)
  instead of a dangling `$ref: "#/$defs/STRING"` with no matching `$defs` entry.

### Cabal slices

`jl4-core.cabal` gains `L4.Print.Columnar` as an exposed module, the six new spec modules in the test
suite, and a `megaparsec >= 9.7` bound — 9.7.0 is where `Text.Megaparsec.Unicode.isWideChar` appears,
and `Columnar.hs` is its only importer in the tree.

## Evidence

Quoted from the source PRs.

**The #932 repair (#214).** Red control on the pre-fix tree at `regcf-wizard.l4:186`:
`incorrect indentation (got 75, should be greater than 180)`. Green:
`l4 batch .../regcf-wizard.l4 -e "can this company raise"` exits 0 and returns the assessment,
"including the very `CONCAT` the parser choked on". The property, measured against the pre-fix tree
(`22309472` plus the property):

| leg | pre-fix | after |
| --- | --- | --- |
| filter → print → **parse** | **50 / 300 fail** | 0 |
| filter → print → **type-check** | **24 / 300 fail** | 0 |
| gensym in output | **8 files** | 0 |

"(82 total, disjoint — the gensym check short-circuits.)"

**The silent-wrong-answer class (#214),** found by the evaluation differential and not by any test.
`prettyConj` printed chain operands bare, so `(TRUE OR FALSE) AND FALSE` and
`TRUE OR (FALSE AND FALSE)` both printed as `TRUE OR FALSE AND FALSE`. Through `l4 batch`, with no
diagnostic anywhere: `ok/logic.l4` went from `LIST TRUE, TRUE, FALSE, FALSE` to
`LIST TRUE, TRUE, TRUE, TRUE`; an assertion in `legal/regcf/regcf.l4` went **satisfied → failed**; the
`ceo-performance-award` deontic `PROVIDED` guard re-associated; `(NOT TRUE) OR TRUE` became
`NOT (TRUE OR TRUE)`. After the fix: "**288 of 291 comparable files identical**", the three that
differ stamping wall-clock transaction time and disagreeing with *themselves* across two runs of the
original.

**Attack surface (#214).** "21 hand-built probes through the real `l4 batch` pipeline", including
mixfix with `@infixl` fixity where **evaluation is preserved** (`1 quop 2 opdue 3` = 7,
`1 andop 2 hadop 3` = 1006), DEONTIC chains, CONSIDER with literal/nested/constructor patterns,
backticked record fields and the clitic form, sections and qualification, keyword-named identifiers
(`` `LESS` ``, `` `IF` ``, `` `AT` ``), and "24 precedence-discriminating expressions".

**The exactprint invariant (#130).** "New `FormatFidelitySpec` (jl4-core) round-trips each family;
**10/11 cases fail against the pre-fix parser** (the escaped-literal case coincidentally matches,
since old code decoded `\214`→Ö and re-escaped back)." "Whole corpus swept: **0/243**
ok/legal/libraries files non-identity under `l4 format`." "23 stale `.ep.golden` files were
regenerated to byte-identity with their sources."

**Event exactprint (#125).** "New `EventExactPrintSpec` round-trip tests (`exactprint . parse ≡ id`)
for both clause orders and the multiline form — all three fail against the old code."

**Bullet syntax (#109).** "`jl4-core-test`: all unit tests pass, including 9 new `BulletParserSpec`
cases." On the pinned `indentedGE` corner case: "A corpus sweep found **0 of 571 `.l4` files** hit
this today, so the behavior is pinned with a regression test (and the `(name)` parens workaround
documented) rather than the parser being narrowed."

**The `prettyLayout` re-parse work that preceded all of it (#66).** Four constructs whose printed form
did not parse (`x DIVIDED 2`, `... IS TYPEDECLARE ...`, a dropped `TIMEZONE IS`, an `Exponent` node
printed as ` TO THE POWER OF `), with "2 regenerated goldens: `float`, `lazytrace-exception`" and
"5 new round-trip unit tests"; suites `jl4-core-test` 51 · `jl4-test` 883 · `l4-cli-test` 20, all 0
failures. #66 also states plainly why `PrintRoundtripSpec` exists rather than an `ok/` fixture:
"`.ep.golden` is fed by **ExactPrint**, and `.nlg.golden` by the NLG linearizer — *neither routes
through `prettyLayout`*."

**`optionalHole` (#92).** "a new `optionalHole` combinator keeps ExactPrint hole alignment when an
optional clause is absent — otherwise trailing tokens were dropped".

**`@ref` (#48).** "`jl4-core`: 50/50 (incl. new leading-ref regression test). Goldens unchanged."

**The ditto primitive (#42).** No measurement is claimed: "Compiles (`cabal build jl4-core`) but is
**not yet wired** into the live emission/LSP path — a ready-to-use building block."

**Suite banners at the respective tips** — whole-tree figures, not figures for this slice. #214:
`jl4-test` 2550/0, `jl4-core-test` 269/0, `l4-cli-test` 202/0 (+79 pending), `jl4-service-test` 311/0,
`jl4-lsp-test` 10/0, `cabal test all` exit 0. #130: "jl4-core 219/0, jl4 goldens 1412/0 (incl. the new
invariant)". #125: "jl4-core 169/0, jl4 goldens 1120/0". #109: "full golden suite green (1116
examples)". #182: `jl4-test` 2062/0, `jl4-core-test` 269/0.

**The honest bound, quoted (#214).** Two mixfix operators sharing a head keyword, an arity and an
argument type vector print to the same text, and the module then fails to re-check with "There are
multiple definitions for the identifier". The corpus witness is `ok/mixfix-garden-path.l4`, "whose own
comment predicts it". It fails **loudly**, is **not a regression** (pre-fix the same file printed
`` `_ tax on _ item costing _ as VAT in _` ``, an identifier defined nowhere), and surfaces only via
the unfiltered print, since `l4 batch` strips the `#EVAL` directives where both call sites live.
Re-emitting the surface form instead "was **built, measured and rejected**": definitions print from
their restructured AppForm, so `ok/fixity-nary-guard.l4`'s `1 andop 2 hadop 3` stopped resolving
altogether. A real fix needs `L4.Mixfix.MixfixRegistry` threaded into the printer. Recorded at the
function and in `CLAUDE.md` §3.2.2. Also recorded as a readability trade rather than a defect:
`l4 batch`'s residual-value rendering under `#TRACE` now puts an obligation on one line, "a loss for
`promissory-note`'s huge record parties and a gain everywhere else".

## Independence

**This PR does not compile against `main` alone.** `L4/Print.hs` pattern-matches AST shapes that two
siblings ship:

- `MkTypedName` and `MkOptionallyTypedName` carry an extra `TYPICALLY` field on `unstable` (5 and 4
  fields respectively; `main` has 4 and 3) — **lang-syntax-typecheck**.
- The `Expr` constructor `Exponent` is *removed* on `unstable`, and this printer no longer has an arm
  for it — **lang-syntax-typecheck**.
- `Record` / `ReadCell` / `RecallMode` do not exist on `main` at all; the clitic-printing arms are
  theirs — **lang-eval-ledger**.

This edge is real and does not appear in `.pr-split/DEPENDENCIES.md`, because `depcheck.mjs` resolves
*module* imports and `L4.Syntax` is a module `main` already has. It is a constructor-level
dependency, not an import-level one, so it is worth stating explicitly rather than leaving to the
mechanical list.

**Five of the six new specs test other themes' code.** They live here because they are printer- and
exactprint-fidelity tests, but the behaviour each asserts arrives elsewhere, and each is red without
it: `EventExactPrintSpec` and `FormatFidelitySpec` need the `ToConcreteNodes` and parser
anno-capture fixes in `L4/Syntax.hs` and `L4/Parser.hs`; `BulletParserSpec` needs the `•` lexer and
parser rules; `RefAnnotationSpec` needs `L4/Parser/ResolveAnnotation.hs` and the `annRef` lens;
`DirectiveAmbiguitySpec` needs the `prune` repair in `L4/TypeCheck.hs`. **All of those files are
owned by lang-syntax-typecheck.** Only `PrintRoundtripSpec` tests code that is in this PR.

**Three of the goldens likewise encode other themes' behaviour.** The four `.ep.golden` deltas record
the restored postfix-mixfix operand from `fix(parser): add missing anno hole for funcName in
mixfixPostfixOp` — **lang-syntax-typecheck**. `mixfix-garden-path.schema.golden` records the repaired
`L4/JsonSchema.hs` output — **service-cli**. `ref-annotation.l4` and its four goldens are the corpus
fixture for the `@ref` feature — **lang-syntax-typecheck** again.

**What is genuinely this PR's own:** `L4/Print.hs`, `L4/Print/Columnar.hs`, `L4/Parser/Anno.hs`,
`PrintRoundtripSpec.hs`, and the two invariants in `jl4/tests/Main.hs`. In the other direction
nothing needs this PR at compile time — no module in the tree imports `L4.Print.Columnar`, and
`L4.Print` itself is already on `main`.

**Ordering.** Land **lang-syntax-typecheck** first, with **lang-eval-ledger** before or beside it;
then this. `service-cli` may land in any order relative to this one — a single `.schema.golden`
depends on it, and if it slips that one file can be reverted to what `main` emits.

**One property-shaped caveat.** The `prettyLayout round-trip` and `exactprint identity` blocks have
no exclusion list by design, so they cover whatever `.l4` files sit in `ok/**`, `legal/**` and
`jl4-core/libraries/` when they run. The corpora that `corpus-legal-new` and `corpus-regcf` add were
inside the 300 files the property was measured green over; if they land after this PR it simply
covers fewer files, and if before, it covers them too. No corpus in the tree is known to fail either
invariant. The converse is also worth flagging: because these two blocks enrol every corpus file
automatically, any *other* theme that adds a `.l4` under those globs is silently enrolling it here.

## Risk if rejected

`l4 batch` and the REPL stay broken on every module whose reconstruction the printer cannot render —
50 of 300 corpus files failed to re-parse before this — and, worse, the printer keeps silently
re-associating connectives, so `l4 batch` goes on returning wrong answers with no diagnostic on
`ok/logic.l4`, `legal/regcf/regcf.l4` and `ceo-performance-award.l4`. Both printer invariants
disappear with it, leaving the `.ep.golden` files as the only guard — which is exactly the
arrangement that blessed the mangled event output in the first place — and `corpus-legal-new`'s
`promissory-note.golden`, which records the one-line residual obligation this printer produces, goes
red the moment that theme lands.

## Provenance

Unstable PRs folded into this one:

- **#214** — `mengwong/printer-batch-and-gensym`: the `prettyLayout` repair (parseability, grouping,
  gensym leak, mixfix head keyword, clitic) and the `prettyLayout round-trip` property.
- **#130** — `mengwong/format-fidelity`: `FormatFidelitySpec` and the `exactprint identity`
  invariant. The parser and lexer half of that PR is `lang-syntax-typecheck`.
- **#125** — `mengwong/fix-event-exactprint`: `EventExactPrintSpec`. The `L4/Syntax.hs` fix it guards
  is `lang-syntax-typecheck`.
- **#109** — `mengwong/bullet-list-syntax`: `BulletParserSpec`. The `•` lexer and parser rules, the
  `hierarchy.l4` library and the docs are other themes.
- **#182** — `mengwong/bkm-phase05-oracle`: the `@desc` re-emission in the `Decide` printer, so a
  printed module does not lose its `@nonexhaustive` flag and resurrect a suppressed warning.

Several of these files also carry work from unstable merges earlier than that window, which the
file-level split assigns here because the affected files are printer or printer-fidelity files:

- **#66** (`fix/print-roundtrip`) — the first `prettyLayout` re-parse fixes and `PrintRoundtripSpec`.
- **#42** (`dmnmd-to-l4`) — `L4/Print/Columnar.hs` and `prettyLayoutDitto`.
- **#92** (`typically-salvage`) — `optionalHole` in `L4/Parser/Anno.hs`, and the `TYPICALLY` arms in
  the printer.
- **#83** (`refactor/remove-dead-exponent`) — the removal of the printer's `Exponent` arm.
- **#48** (`@ref` attachment) — `RefAnnotationSpec.hs`, `ok/ref-annotation.l4` and its four goldens.
- **#56** (`fix/tc-ambiguity-crash`) — `DirectiveAmbiguitySpec.hs`.
