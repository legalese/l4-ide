{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The GraphViz stub for a connective's skipped right operand
-- (UNKNOWN-EVALUATION-SPEC §8 step 2). No shipped renderer turns
-- 'showUnevaluated' on, so nothing else exercises the stub: with it on, a
-- short-circuited AND draws its right operand as a grey node labelled with
-- the operand's source text, on a dashed edge labelled "skipped"; with it
-- off, or when the right operand was evaluated, there is no such edge.
module GraphVizStubSpec (spec) where

import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.GraphViz2 (traceToGraphViz)
import L4.EvaluateLazy.GraphVizOptions (GraphVizOptions (..), defaultGraphVizOptions)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.EvaluateLazy.Trace (EvalTrace)
import L4.TracePolicy (apiDefaultPolicy)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0)

-- | The trace of a source's one @#EVALTRACE@.
traceOf :: Text.Text -> IO EvalTrace
traceOf src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r | not r.tcdSuccess -> fail ("typecheck failed: " <> show r.tcdErrors)
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      case [ t | MkEvalDirectiveResult {trace = Just t} <- results ] of
        [t] -> pure t
        ts  -> fail ("expected one trace, got " <> show (length ts))

dotWith :: Bool -> Text.Text -> IO Text.Text
dotWith unevaluated src = do
  t <- traceOf src
  pure (traceToGraphViz defaultGraphVizOptions {showUnevaluated = unevaluated} Nothing t)

shortCircuited, evaluated :: Text.Text
shortCircuited = "#EVALTRACE FALSE AND (2 GREATER THAN 1)\n"
evaluated      = "#EVALTRACE TRUE AND (2 GREATER THAN 1)\n"

spec :: Spec
spec = describe "GraphViz stub for a skipped connective operand (UNKNOWN-EVALUATION-SPEC §8 step 2)" $ do
  it "draws the skipped right operand as a stub under its own text, on a dashed \"skipped\" edge" $ do
    dot <- dotWith True shortCircuited
    -- the stub: the operand's own text, in the grey a stub is filled with
    dot `shouldSatisfy` Text.isInfixOf "1 [label=\"2 GREATER THAN 1\"\n      ,fillcolor=\"#e0e0e0\""
    -- its edge from the connective: dashed, and labelled
    dot `shouldSatisfy` Text.isInfixOf "0 -> 1 ["
    dot `shouldSatisfy` Text.isInfixOf ",label=skipped\n           ,style=dashed]"

  it "draws no stub with showUnevaluated off, which is every shipped renderer's setting" $ do
    dot <- dotWith False shortCircuited
    dot `shouldNotSatisfy` Text.isInfixOf "skipped"

  it "draws no stub when the right operand was evaluated" $ do
    dot <- dotWith True evaluated
    dot `shouldNotSatisfy` Text.isInfixOf "skipped"
