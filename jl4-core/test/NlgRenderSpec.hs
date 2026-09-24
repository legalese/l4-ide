{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | @\@nlg@ escapes must be decoded by the time an annotation reaches a
-- reader — and this is the test that says so for @l4 render@.
--
-- __Why this file exists.__ The escape is decoded on the render side, in
-- 'L4.Nlg.unescapeNlgText', deliberately: the lexer keeps @\\%@ and @\\]@
-- verbatim so that exactprint can re-emit the source bytes. That design has a
-- failure mode with no natural witness — the decoder can be perfectly correct
-- and simply not be CALLED. Measured 2026-09-17: deleting every
-- 'L4.Nlg.unescapeNlgText' call site left the corpus goldens, the round-trip
-- property and all of 'NlgPercentSpec' green, while @l4 render@, the LSP
-- document webview and @l4 export blawx@ each emitted a literal backslash to the
-- reader. A unit test on the decoder cannot tell a wired decoder from an
-- orphaned one; it has to be driven end to end.
--
-- __Why not a @.nlg.golden@.__ No @.nlg.golden@ in the tree witnesses
-- annotation prose at all. That golden linearizes DIRECTIVES, and
-- @Linearize (Directive Resolved)@ routes @#EVAL@ through @linearize e@ rather
-- than @lin e@, so the annotation on the decide is skipped. The corpus file
-- @jl4\/examples\/ok\/nlg-percent.l4@ does carry the escapes, and its golden
-- shows @`the levy on` with 100@ — the bare name. It pins the lexer, not the
-- renderer.
module NlgRenderSpec (spec) where

import Test.Hspec

import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Export.Document (buildDocument, defaultExportConfig)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

-- | Source → the exported document, flattened to text. 'show' is deliberate:
-- it reaches every @Text@ in the IR without this test having to know which
-- constructor the annotation landed in, and it escapes a backslash as @\\\\@,
-- which is what lets the two assertions below distinguish decoded from raw.
rendered :: Text -> IO Text
rendered src = case checkWithImports emptyVFS src of
  Left errs -> fail' ("parse/import: " <> Text.unlines errs)
  Right r
    | errs@(_ : _) <- filter ((== SError) . TC.severity) r.tcdErrors ->
        fail' ("typecheck: " <> Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))
    | otherwise ->
        pure (Text.pack (show (buildDocument defaultExportConfig r.tcdModule [])))
 where
  fail' msg = do expectationFailure (Text.unpack msg); pure ""

-- | The module under test: one escaped percent pair and one escaped close
-- bracket.
--
-- __The annotation position is load-bearing and not obvious.__ It must be the
-- inline @[…]@ form on the appform, because that is the one
-- 'L4.Export.Document.unitRendering' renders AS the unit\'s description. A
-- LINE @\@nlg@ above a @DECIDE … IS …@ is not reached: measured
-- 2026-09-17, @l4 render --format text@ on that shape prints
-- @The levy on equals n × 2.@ — the implementation, not the annotation. That
-- is also why @jl4\/examples\/ok\/nlg-percent.l4@, which uses the line form,
-- cannot witness this no matter what golden is attached to it.
escapedModule :: Text
escapedModule =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`the levy on` n [a rate between 10\\%and\\%20 applied to %n%] MEANS n TIMES 2\n\
  \\n\
  \GIVEN m IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`the duty on` m [rate \\] per unit] MEANS m TIMES 3\n"

spec :: Spec
spec = describe "@nlg escapes are decoded on the way to a reader" $ do
  it "renders an escaped percent as a percent" $ do
    doc <- rendered escapedModule
    (("decoded", "10%and%20" `Text.isInfixOf` doc) :: (Text, Bool))
      `shouldBe` ("decoded", True)

  it "leaves no backslash in front of the rendered percent" $ do
    -- The other direction, so the assertion above cannot pass just because the
    -- needle happens to appear somewhere else. 'show' renders one source
    -- backslash as two, hence the doubling here.
    doc <- rendered escapedModule
    (("raw backslash absent", "10\\\\%and\\\\%20" `Text.isInfixOf` doc) :: (Text, Bool))
      `shouldBe` ("raw backslash absent", False)

  it "renders an escaped close bracket as a close bracket" $ do
    doc <- rendered escapedModule
    (("decoded", "rate ] per unit" `Text.isInfixOf` doc) :: (Text, Bool))
      `shouldBe` ("decoded", True)

  it "still renders ordinary prose and its parameter reference" $ do
    -- A positive control for the harness itself: if `rendered` silently
    -- produced an empty document, every assertion above would pass vacuously
    -- except the negative one, which would pass for the wrong reason.
    doc <- rendered escapedModule
    (("harness reached the annotation", "a rate between" `Text.isInfixOf` doc) :: (Text, Bool))
      `shouldBe` ("harness reached the annotation", True)
