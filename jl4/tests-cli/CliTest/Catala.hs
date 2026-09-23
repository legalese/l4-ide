-- | Black-box tests for @l4 catala@. Split out of @Main.hs@ so a release can
-- be sliced per backend.
module CliTest.Catala (spec, fixtures) where

import Data.List (isInfixOf, isPrefixOf)
import System.Exit (ExitCode(..))
import Test.Hspec

import CliTest.Common

-- | Files this module's tests need to exist. 'Main.main' checks every
-- module's list before hspec runs anything; nothing here is checked up front
-- today, because the files these tests read are named inline in the tests.
fixtures :: [FilePath]
fixtures = []

spec :: FilePath -> Spec
spec bin = do
  -- `l4 catala` (specs/todo/CATALA-EXPORT-SPEC.md). Each golden below has been
  -- run through the real toolchain — `catala typecheck` and `clerk test`
  -- against catala 1.2.1 — so the goldens are not merely "what the emitter
  -- currently prints"; see examples/catala/README.md.
  describe "l4 catala" $ do
    it "compiles the spec's Appendix A example to its golden Catala module" $
      expectGolden bin ["catala", "examples/catala/benefit.l4"]
                       "examples/catala/expected/benefit.catala_en"

    it "compiles a nested-guard rate table (the ladder-direction exhibit)" $
      expectGolden bin ["catala", "examples/catala/bands.l4"]
                       "examples/catala/expected/bands.catala_en"

    it "compiles the literate weave: § headings, inert law text, @ref, enums" $
      expectGolden bin ["catala", "examples/catala/statute.l4"]
                       "examples/catala/expected/statute.catala_en"

    -- The two OpenFisca seed-corpus ports named in the spec's P1 exit
    -- criterion (§10). Both compile unchanged from their OpenFisca originals;
    -- what makes them Catala-clean is R11's elision of the `period` plumbing
    -- string (and, in household, of `Person.name`).
    it "compiles the flat-tax port, eliding the OpenFisca period string (R11)" $
      expectGolden bin ["catala", "examples/catala/flat-tax.l4"]
                       "examples/catala/expected/flat-tax.catala_en"

    it "compiles the household port: group entity, LIST OF, absorbed sum (R5)" $
      expectGolden bin ["catala", "examples/catala/household.l4"]
                       "examples/catala/expected/household.catala_en"

    it "compiles CONSIDER-on-enum plus TYPICALLY → context (R10)" $
      expectGolden bin ["catala", "examples/catala/tariff.l4"]
                       "examples/catala/expected/tariff.catala_en"

    -- The coverage exhibit. An adversarial review found the other six goldens
    -- between them exercised two of the emitter's expression forms, so a
    -- regression in `match`, dates, `optional of`, `combine all`, `number of`,
    -- `contains`, `impossible`, a private toplevel or the R3 date helper would
    -- have been caught by nothing in the tree.
    it "compiles the coverage exhibit: dates, MAYBE, folds, a private toplevel" $
      expectGolden bin ["catala", "examples/catala/registry.l4"]
                       "examples/catala/expected/registry.catala_en"

    -- The @export-everything hatch, and the only file in this corpus carrying a
    -- module-level binder at all: before it, no golden exercised `collectAssumes`,
    -- `assumeClosure` or the `ssAssumes` threading, so the whole ASSUME path was
    -- emitted by code that nothing in the tree ran. It pins two things at once —
    -- that a section GIVEN becomes a scope `input`, and that `assumeClosure`'s
    -- fixpoint carries it TRANSITIVELY (`the top` never names the binder, reaches
    -- it only through `the middle`, and must still declare and forward it).
    it "compiles the @export chain, threading a section GIVEN as a scope input" $
      expectGolden bin ["catala", "examples/catala/export-chain.l4"]
                       "examples/catala/expected/export-chain.catala_en"

    -- The lowering scans the whole IMPORT closure, not just the entry module.
    -- Before 2026-09-21 it scanned only what it was handed, so a `DECLARE` next
    -- door was reported as "outside the v1 Catala fragment (§6)" — a message
    -- about the language, for a defect in the scan.
    it "compiles a decision built out of imported declarations and an imported helper" $
      expectGolden bin ["catala", "examples/catala/imports.l4"]
                       "examples/catala/expected/imports.catala_en"

    -- Reading the closure means the prelude's own declarations are visible too.
    -- They must not be EMITTED: an imported declaration reaches the artifact
    -- only when the emitted code reaches it. Assert on what is absent, because
    -- the golden above can only show what is present.
    it "emits no stdlib declaration for a module that merely imports the prelude" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/imports.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("declaration structure Assessment:" `isInfixOf`)
      sout `shouldSatisfy` ("declaration enumeration Band:" `isInfixOf`)
      -- Exactly one of each: the two the emitted code reaches. Anything the
      -- prelude contributes would show up as a third.
      length (filter ("declaration structure " `isPrefixOf`) (lines sout)) `shouldBe` 1
      length (filter ("declaration enumeration " `isPrefixOf`) (lines sout)) `shouldBe` 1

    -- R1 prunes to what an `@export` reaches, and a directive reaches things
    -- too: R7 makes each `#EVAL`/`#ASSERT` a `#[test]` scope, so a fixture
    -- named only in a directive's arguments is emitted code. Before 2026-09-21
    -- it was not collected and the directive was dropped, so only directives
    -- with literal arguments became tests.
    it "collects a fixture reached only from a directive and tests against it" $
      expectGolden bin ["catala", "examples/catala/fixtures.l4"]
                       "examples/catala/expected/fixtures.catala_en"

    it "emits every directive as a test scope when its arguments name fixtures" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/fixtures.l4"]
      code `shouldBe` ExitSuccess
      -- The three fixture-argument directives convert. The file's last two are
      -- skipped on purpose, so this asserts the absence of the CAUSE rather
      -- than of every skip note — which the numbering test below covers, and
      -- which a blanket absence test would contradict.
      sout `shouldSatisfy` (not . ("that is a lowering bug" `isInfixOf`))
      sout `shouldSatisfy` (not . ("was not collected as a helper" `isInfixOf`))
      for_ ["Test1", "Test2", "Test3"] $ \n ->
        sout `shouldSatisfy` (("#[test] declaration scope " ++ n ++ ":") `isInfixOf`)
      -- Nullary, unary, and a helper wrapping an exported call: all three are
      -- ordinary R1 toplevels, not a new emission kind for test data.
      sout `shouldSatisfy` ("declaration the_ordinary_household content Household" `isInfixOf`)
      sout `shouldSatisfy` ("declaration a_household_of content Household" `isInfixOf`)
      sout `shouldSatisfy` ("declaration in_tens content decimal" `isInfixOf`)

    -- A skip note quotes the DIRECTIVE's position, not the number of the test
    -- it would have been. Sharing one counter mislabelled every skip after the
    -- first — and because identical notes are deduplicated, the second one then
    -- vanished rather than appearing under the wrong number. The last two
    -- directives of `fixtures.l4` are both skipped, so this catches either half.
    it "numbers a skipped directive by its own position, and reports every one" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/fixtures.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("- directive 4 did not become a Catala" `isInfixOf`)
      sout `shouldSatisfy` ("- directive 5 did not become a Catala" `isInfixOf`)
      -- Three converted, so no note may claim a number a test scope also holds.
      for_ ["1", "2", "3"] $ \n ->
        sout `shouldSatisfy` (not . (("- directive " ++ n ++ " did not become") `isInfixOf`))

    -- R11 addendum, 2026-09-21: a structure every one of whose fields was
    -- elided cannot be emitted at all — catala 1.2.1 refuses a fieldless
    -- `declaration structure` AND the value `P { }`. The golden pins that the
    -- structure and the fields carrying it are both gone, and the test below it
    -- pins that both disappearances are disclosed rather than silent.
    it "elides a record whose every field is a STRING, and the fields that carry it" $
      expectGolden bin ["catala", "examples/catala/all-string-record.l4"]
                       "examples/catala/expected/all-string-record.catala_en"

    it "discloses an elided structure and the fields that vanish with it" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/all-string-record.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("structure `Provenance` is not emitted at all" `isInfixOf`)
      sout `shouldSatisfy`
        ("field `sources` of `Finding` has a type built from `Provenance`" `isInfixOf`)
      -- The empty structure and its value are what catala refuses; neither may
      -- reach the artifact. Assert that by what IS emitted rather than by
      -- searching for `Provenance { }`: the note above quotes that very string
      -- to explain why it cannot be written, so an absence test on it fails on
      -- its own disclosure. (It did, first time out.)
      sout `shouldSatisfy` (not . ("declaration structure Provenance:" `isInfixOf`))
      sout `shouldSatisfy` (not . ("data sources" `isInfixOf`))
      sout `shouldSatisfy`
        ("Finding { -- amount: (claimed * 2.0) -- settled: (claimed > 0.0) }" `isInfixOf`)

    -- R11's disclosure obligation is the point of these two, not the text: a
    -- narrower emitted record than its L4 source is a shape divergence a
    -- reader must be told about, so it goes in the notes block, not just on
    -- stderr.
    it "discloses every R11 elision in the emitted document's notes block" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/household.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("field `name` of `Person` is a STRING" `isInfixOf`)
      sout `shouldSatisfy` ("parameter `period` of `household income` is a STRING" `isInfixOf`)

    -- R10's cost, disclosed: the emitted scope is MORE PERMISSIVE than its
    -- source, because Catala lets a caller omit a `context` variable and L4
    -- does not let a caller omit anything.
    it "emits TYPICALLY as `context` + an in-scope default, and says so" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/tariff.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("context cap content decimal" `isInfixOf`)
      sout `shouldSatisfy` ("A Catala caller may omit it; an L4 caller may not." `isInfixOf`)
      sout `shouldSatisfy`
        ("match a.class with pattern -- Domestic : 0.2" `isInfixOf`)

    -- L4 has no way to omit an argument, so every ordinary test scope supplies
    -- the cap and the emitted `definition cap equals 500.0` is dead: change it
    -- and nothing fails. The twin scope omits it, over a directive whose cap
    -- actually binds, which is what makes the default observable.
    it "pins the R10 default with a twin test scope that omits the argument" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/tariff.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("#[test] declaration scope Test3Default:" `isInfixOf`)
      sout `shouldSatisfy`
        ("(output of TariffPayable with { -- a: Account { -- class: Industrial \
         \-- units_used: 2000.0 } }).tariff_payable" `isInfixOf`)

    -- R2 (§8.2) promised a lowering note at each coercion; R7 (§8.7) promised a
    -- human-legible companion to the exact-rational JSON block.
    it "emits R2's per-coercion note and R7's human-format companion line" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/registry.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("# R2 coercion: `decimal of` was inserted" `isInfixOf`)
      sout `shouldSatisfy` ("is ROUNDED here rather than refused" `isInfixOf`)
      sout `shouldSatisfy` ("{\"result\":\"2025-03-01\"}" `isInfixOf`)
      sout `shouldSatisfy` ("L4 computes that as: `DATE OF 1, 3, 2025`." `isInfixOf`)

    -- §6.1: L4's connectives short-circuit and Catala's `and`/`or` do not, so
    -- the emitter writes the conditional form. `benefit.l4`'s disjunction is
    -- the one the spec's Appendix A example turns on.
    it "emits AND/OR as short-circuiting conditionals, never Catala `and`/`or`" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/benefit.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy`
        ("(if (a.age >= 65.0) then true else a.is_veteran)" `isInfixOf`)
      sout `shouldNotSatisfy` (" or " `isInfixOf`)

    -- R4: the exception ladder is the PRIMARY emission, and it never ships
    -- without the apparatus that re-checks it.
    it "emits Mode B ladders together with their equivalence grid" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/bands.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("label rate_band_r1 exception rate_band_r2" `isInfixOf`)
      sout `shouldSatisfy` ("#[test] declaration scope RateBandEqvGrid:" `isInfixOf`)
      sout `shouldSatisfy` ("{\"all_agree\":true}" `isInfixOf`)

    -- R7: the expected values come from L4's evaluator, not from
    -- `clerk test --reset`. 0.25 is L4's answer for a 60000 income, and Catala
    -- prints exact rationals in JSON, so it has to appear as 1/4.
    it "fills test blocks with values L4 computed, as exact rationals" $ do
      Output code sout _ <- runL4 bin ["catala", "examples/catala/bands.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("$ catala test-scope Test1 --disable-warnings -F json" `isInfixOf`)
      sout `shouldSatisfy` ("{\"result\":\"1/4\"}" `isInfixOf`)
      sout `shouldSatisfy` ("{\"result\":\"2/5\"}" `isInfixOf`)

    it "--boolean-only drops the ladders and the grids that check them" $ do
      Output code sout _ <- runL4 bin ["catala", "--boolean-only", "examples/catala/bands.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldNotSatisfy` ("EqvGrid" `isInfixOf`)
      sout `shouldNotSatisfy` ("label rate_band_r1" `isInfixOf`)
      sout `shouldSatisfy` ("--boolean-only" `isInfixOf`)

    -- R4's escape flag had one test of three substring checks and no golden, so
    -- nothing re-ran its output through the toolchain. It has one now, and
    -- etc/validate-catala.mjs walks `expected/`, so the flag's output is under
    -- `catala typecheck`, `catala proof` and `clerk test` like everything else.
    it "pins the --boolean-only rendering as a golden the R9 harness checks" $
      expectGolden bin ["catala", "--boolean-only", "examples/catala/bands.l4"]
                       "examples/catala/expected/bands-boolean-only.catala_en"

    -- Catala wants the module name to be the file's basename with its first
    -- letter capitalised, so a basename it cannot spell is rejected here rather
    -- than by the toolchain after the file has been written.
    it "rejects an -o basename that cannot be a Catala module name" $ do
      Output code _ serr <- runL4 bin
        ["catala", "examples/catala/flat-tax.l4", "-o", "ft-out.catala_en"]
      code `shouldNotBe` ExitSuccess
      serr `shouldSatisfy` ("cannot be a Catala module name" `isInfixOf`)

    -- Two field names that mangle to one Catala identifier would silently
    -- conflate in Catala's flat per-structure namespace; the OpenFisca fixture
    -- has the same shape and serves both backends.
    it "rejects a name collision (distinct L4 names → same Catala identifier)" $
      expectFail bin ["catala", "examples/openfisca/not-ok/name-collision.l4"]

    -- Six shapes that used to compile to Catala saying something other than
    -- what the L4 says. Each fixture's header names the divergence; the point
    -- of the group is that `l4 catala` refuses rather than emitting quietly.
    -- `duplicate-type-name` became possible only once the lowering read the
    -- import closure (§8.1.2): two imported modules each declaring a `Thing`,
    -- which `l4 check` accepts and one flat Catala namespace cannot hold.
    for_ [ "otherwise-not-last"
         , "otherwise-not-last-enum"
         , "local-name-shadow"
         , "elided-string-compared"
         , "enum-constructor-collision"
         , "duplicate-type-name"
         ] $ \name ->
      it ("rejects " ++ name ++ " rather than changing its denotation") $
        expectFail bin ["catala", "examples/catala/not-ok/" ++ name ++ ".l4"]

    -- smucclaw/l4-ide#958. R1 emits an @export'd decision as a Catala SCOPE and
    -- every other reachable decision as a TOPLEVEL, and Catala allows a scope
    -- call only inside a scope — so a non-exported caller of an exported callee
    -- cannot be expressed. Until this refusal, `l4 catala` emitted that module,
    -- printed nothing at all, and exited 0; the invalid output was found only by
    -- running `catala typecheck` over it by hand, which reports "Scope calls are
    -- not allowed outside of a scope" (catala 1.2.1, exit 123).
    --
    -- Two fixtures because there were two emission sites: the direct call, and
    -- the combinator argument that R5 absorbs into `map each … among …`. The
    -- second carried no context check at all, so a fix to the first alone would
    -- have left it open.
    --
    -- The MESSAGE is asserted, not just the exit code. Exit 1 alone would be
    -- satisfied by a fixture that merely fails to typecheck — the same argument
    -- `expectVerifyFinding` makes above — and both fixtures typecheck cleanly,
    -- so a bare `expectFail` here would be a control over nothing.
    for_ [ ("export-chain-broken",     "the middle",  "the base")
         , ("export-chain-combinator", "all doubled", "double")
         ] $ \(name, caller, callee) ->
      it ("refuses " ++ name ++ ": a scope call would land outside a scope") $ do
        Output code _ serr <- runL4 bin
          ["catala", "examples/catala/not-ok/" ++ name ++ ".l4"]
        code `shouldNotBe` ExitSuccess
        -- names the caller, the callee, the rule, and the way out
        serr `shouldSatisfy` (("`" ++ caller ++ "`") `isInfixOf`)
        serr `shouldSatisfy` ((callee ++ "` is @export'd") `isInfixOf`)
        serr `shouldSatisfy`
          ("Catala allows a scope call only from inside another scope" `isInfixOf`)
        serr `shouldSatisfy` ("Mark this caller @export too" `isInfixOf`)

    it "fails on a file that does not typecheck" $
      expectFail bin ["catala", errorFixture]
  where
    for_ xs f = mapM_ f xs
