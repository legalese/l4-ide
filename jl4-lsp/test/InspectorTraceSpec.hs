{-# LANGUAGE OverloadedRecordDot #-}
-- | W8 (TYPICALLY-ONE-BEHAVIOUR-SPEC.md §4.2): the editor shows an evaluation
-- trace only as text, in the results inspector and in the diagnostic on the
-- directive, and both are the one printer ('prettyEvalDirectiveResult' and
-- its named-field variant). So a default that took effect shows in the editor
-- exactly when the text trace has it, and these cases hold that to what the
-- inspector actually sends: the real oneshot pipeline, the LSP's own trace
-- policy, and the inspector's own conversion. A directive with no trace
-- (an @#EVAL@) says it in a NOTE line after its answer (W11, §4.3).
module InspectorTraceSpec (spec) where

import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath ((</>))

import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.EvaluateLazy (EvalDirectiveResult (..), prettyEvalDirectiveResult, resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.L4.Inspector (DirectiveResult (..), DirectiveUpdateItem (..), evalDirectiveToResult, evalDirectiveToUpdateItem)
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import qualified LSP.L4.Rules as Rules

import Test.Hspec

-- | The directives' results, from a module written to a scratch file and
-- evaluated the way the language server evaluates it.
resultsOf :: String -> T.Text -> IO [EvalDirectiveResult]
resultsOf stem src = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-inspector-trace-spec"
      path = dir </> (stem <> ".l4")
  createDirectoryIfMissing True dir
  T.writeFile path src
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mResults) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.EvaluateLazy uri
  case mResults of
    Just rs -> pure rs
    Nothing -> expectationFailure "the module did not evaluate" >> pure []

source :: T.Text
source = T.unlines
  [ "§ `Rates`"
  , "    GIVEN `the rate` IS A NUMBER TYPICALLY 3"
  , ""
  , "GIVETH A NUMBER"
  , "doubled MEANS `the rate` TIMES 2"
  , ""
  , "#EVALTRACE doubled"
  , "#EVALTRACE doubled WITH `the rate` IS 5"
  , "#EVAL doubled"
  ]

spec :: Spec
spec = describe "a TYPICALLY default in the editor's trace (W8)" do
  it "reaches the inspector's text, and the diagnostic's, where the default was read" do
    results <- resultsOf "w8-inspector" source
    case results of
      [traced, supplied, plain] -> do
        let inspector r = case r.range of
              Just rng -> (evalDirectiveToResult mempty "#EVALTRACE" rng r).prettyText
              Nothing  -> ""
            pushed r = maybe "" (.prettyText) (evalDirectiveToUpdateItem mempty (\_ _ -> "") r)
            said t = "the rate took its default (declared at w8-inspector.l4:2:44-45)" `T.isInfixOf` t
        -- the traced directive that read the default says so, in all three,
        -- and once: its trace has it, so the NOTE line of W11 does not repeat it
        inspector traced `shouldSatisfy` said
        pushed traced `shouldSatisfy` said
        prettyEvalDirectiveResult traced `shouldSatisfy` said
        T.count "took its default" (inspector traced) `shouldBe` 1
        -- the value was given, so nothing was presumed
        inspector supplied `shouldSatisfy` (not . T.isInfixOf "took its default")
        -- and an #EVAL has no trace to show it in: it says so in a NOTE line
        -- after its answer (W11, TYPICALLY-ONE-BEHAVIOUR-SPEC.md §4.3), in
        -- the inspector and in the diagnostic alike
        T.lines (T.strip (inspector plain))
          `shouldBe` ["6", "NOTE: the rate took its default 3 (declared at w8-inspector.l4:2:44-45)"]
        let saidWithValue = T.isInfixOf "the rate took its default 3 (declared at w8-inspector.l4:2:44-45)"
        pushed plain `shouldSatisfy` saidWithValue
        prettyEvalDirectiveResult plain `shouldSatisfy` saidWithValue
      other -> expectationFailure ("expected three results, got " <> show (length other))
