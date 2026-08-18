-- | Goldens for the shared relational middle-end (@L4.Relational.{IR,Lower,Debug}@).
--
-- M1 ships no CLI verb, so __the Debug renderer is the only observation point__
-- the suite has and every golden here is a hostage to its format. That is
-- deliberate: it makes "the render of @benefit.l4@ inspected against Appendix A
-- of BLAWX-EXPORT-SPEC" a checkable claim rather than an aspiration, because the
-- render is recognisably Prolog-shaped.
--
-- The fixtures live under @jl4\/examples\/relational\/@, which is __outside every
-- corpus glob in @jl4\/tests\/Main.hs@__ (@ok\/**@, @legal\/**@, @not-ok\/tc\/**@,
-- @not-ok\/nlg\/**@, @lsp\/**@, @not-ok\/export-*@ — none matches
-- @relational\/…@, and @relational\/not-ok\/@ is not swept either because
-- @not-ok\/**@ is anchored at the examples root). So they need only the Debug
-- golden and not the exactprint\/NLG\/schema quartet — the same bargain
-- @jl4\/examples\/{dmn,openfisca,docassemble,bpmn,state-graphs}\/@ already take.
-- The cost, worth saying out loud rather than discovering later, is that these
-- seeds are also outside the exactprint-identity and prettyLayout round-trip
-- invariants, which sweep @okFiles \<\> legalFiles \<\> librariesFiles@ only.
--
-- Two golden shapes: 'goldenProgram' for a module that lowers, 'goldenErrors'
-- for a @not-ok@ fixture whose whole point is the batch of diagnostics.
module RelationalExport (spec) where

import Base
import qualified Base.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImportsAndUri, emptyVFS)
import L4.Relational.Debug (renderErrors, renderProgram)
import L4.Relational.Lower (defaultLowerOptions, lowerModule)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

import System.FilePath ((</>), takeBaseName)
import Test.Hspec
import Test.Hspec.Golden

spec :: FilePath -> Spec
spec examplesRoot = describe "relational export" $ do
  describe "seeds" $ do
    it "benefit.l4 — records, OR/UNLESS, value-position IF, WHERE helper" $
      goldenProgram examplesRoot "benefit.l4" "benefit"
    it "mortality.l4 — the minimal program" $
      goldenProgram examplesRoot "mortality.l4" "mortality"
    -- RSum/RCount/RMaximum/RAvg, and the one shape that needs a generator:
    -- `sum (map …)` becomes findall over the synthesised `member` predicate.
    it "scores.l4 — aggregates over a list field, and a map-projected one" $
      goldenProgram examplesRoot "scores.l4" "scores"
    -- The `[]` / `[X|Xs]` head split, `recursion: structural on argument 0`, the
    -- destructuring case that earns NO marker, and a WHERE-local recursion whose
    -- scrutinised argument sits AFTER the enclosing decision's threaded
    -- parameters (`structural on argument 2`).
    it "sumlist.l4 — structural recursion over a list" $
      goldenProgram examplesRoot "sumlist.l4" "sumlist"
    -- The materialised guard prefix, at the two lengths no other seed reaches:
    -- a BRANCH whose third arm negates two earlier guards, and a disjoint
    -- CONSIDER whose rows carry no prefix while its OTHERWISE carries all of
    -- them. Also the only seed with `@ref`/`@nlg`, and the only one that renders
    -- `match(…)` and a non-arithmetic inequality.
    it "tiers.l4 — BRANCH prefixes, enum discrimination, @ref/@nlg" $
      goldenProgram examplesRoot "tiers.l4" "tiers"
    -- Lowers SUCCESSFULLY and is asserted on its `stratification:` block, not on
    -- a failure: the Apt–Blair–Walker result is recorded, never enforced.
    it "unstratified.l4 — a cycle through a negation is recorded, not rejected" $
      goldenProgram examplesRoot "unstratified.l4" "unstratified"
    -- A computed (MEANS) BOOLEAN field is a desugared selector call, so in
    -- guard position it takes the call form (both polarities), never an RProj
    -- with an invented output argument.
    it "computed.l4 — computed BOOLEAN field as a guard, both polarities" $
      goldenProgram examplesRoot "computed.l4" "computed"
  describe "named rejections (batched)" $ do
    it "not-ok/deontic.l4" $
      goldenErrors examplesRoot ("not-ok" </> "deontic.l4") "not-ok-deontic"
    it "not-ok/higher-order.l4" $
      goldenErrors examplesRoot ("not-ok" </> "higher-order.l4") "not-ok-higher-order"
    it "not-ok/nonstructural.l4" $
      goldenErrors examplesRoot ("not-ok" </> "nonstructural.l4") "not-ok-nonstructural"
    -- The cycle no per-definition check can see, and the one the stratification
    -- result does NOT already record (contrast unstratified.l4, which lowers).
    it "not-ok/mutual.l4" $
      goldenErrors examplesRoot ("not-ok" </> "mutual.l4") "not-ok-mutual"
    -- Sort-based separation of an overloaded prelude aggregate: the recogniser
    -- matches `minimum` by name, and only the callee's result type says which
    -- `minimum` it is.
    it "not-ok/maybe-overload.l4" $
      goldenErrors examplesRoot ("not-ok" </> "maybe-overload.l4") "not-ok-maybe-overload"
    -- The R2-1 ruling's witness: a boolean output argument is dropped, so a
    -- boolean-valued call in value position is rejected loudly — in both its
    -- spellings (named decision, computed BOOLEAN field), in one batch.
    it "not-ok/bool-value-position.l4" $
      goldenErrors examplesRoot ("not-ok" </> "bool-value-position.l4") "not-ok-bool-value-position"

-- | Lower a fixture, INSISTING that L4 accepted it first.
--
-- @checkWithImports@ returns 'Left' only for a parse or import-resolution
-- failure; a module that parses but does not typecheck comes back 'Right' with
-- the diagnostics in @tcdErrors@. Reading only the 'Left' would let a fixture
-- that L4 rejects be asserted on anyway — which is how a golden ends up pinning
-- the exporter's treatment of a failed overload resolution rather than the
-- behaviour it claims to pin. Warnings and infos are left alone.
lowered :: FilePath -> FilePath -> IO Text
lowered examplesRoot srcPath = do
  src <- Text.readFile (examplesRoot </> "relational" </> srcPath)
  -- Check under the FIXTURE's own module name, not the default @main@: the
  -- module URI is what 'rpgSource' and every provenance comment print, so a
  -- shared name would make two goldens claim the same origin.
  case checkWithImportsAndUri emptyVFS (Text.pack (takeBaseName srcPath)) src of
    Left errs -> error ("source failed to parse: " <> show errs)
    Right tc
      | errs@(_ : _) <- filter ((== SError) . TC.severity) tc.tcdErrors ->
          error
            ( "source failed to typecheck: "
                <> Text.unpack (Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))
            )
      | otherwise ->
          pure $ case lowerModule defaultLowerOptions tc.tcdEntityInfo tc.tcdModule of
            Left es -> renderErrors es
            Right p -> renderProgram p

goldenProgram :: FilePath -> FilePath -> FilePath -> IO (Golden Text)
goldenProgram examplesRoot srcPath name =
  mkGolden examplesRoot name <$> lowered examplesRoot srcPath

-- | A @not-ok@ fixture. The render is 'renderErrors', and the golden's job is to
-- pin the KIND of each diagnostic — the rejection census counts by constructor,
-- so a golden that only saw prose would go green on a reclassified error.
goldenErrors :: FilePath -> FilePath -> FilePath -> IO (Golden Text)
goldenErrors examplesRoot srcPath name = do
  out <- lowered examplesRoot srcPath
  when (Text.isPrefixOf "relational program" out) $
    error (srcPath <> " lowered successfully; a not-ok fixture must not")
  pure (mkGolden examplesRoot name out)

mkGolden :: FilePath -> FilePath -> Text -> Golden Text
mkGolden examplesRoot name output =
  Golden
    { output
    , encodePretty = Text.unpack
    , writeToFile = Text.writeFile
    , readFromFile = Text.readFile
    , goldenFile = examplesRoot </> "relational" </> "expected" </> name
    , actualFile = Just (examplesRoot </> "relational" </> "expected" </> (name <> ".actual"))
    , failFirstTime = True
    }
