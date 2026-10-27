{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | How the surfaces in core that report a directive's result report a
-- refusal: as an outcome of its own, which is neither a success nor a
-- failure, and which the editor shows as a warning.
module RefusalReportSpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Foldable (toList)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text

import L4.API (l4CodeLenses, l4Eval, l4EvalDirective)
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Diagnostic (DiagnosticSeverity (..), SimpleDiagnostic (..), evalResultToDiagnostic)
import qualified L4.EvaluateLazy as EL
import L4.TracePolicy (apiDefaultPolicy)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

-- | One directive for each way a directive comes out, a line each from line 4.
outcomesModule :: Text
outcomesModule = Text.unlines
  [ "GIVETH A NUMBER"
  , "`not modelled` MEANS REFUSE \"not modelled\""
  , ""
  , "#EVAL `not modelled`"
  , "#ASSERT `not modelled` EQUALS 1"
  , "#ASSERT REFUSED `not modelled`"
  , "#ASSERT 1 EQUALS 2"
  , "#EVAL 1 DIVIDED BY 0"
  , "#ASSERT (1 DIVIDED BY 0) EQUALS 1"
  , "#EVAL 1 PLUS 1"
  ]

-- | The directives of 'outcomesModule', in order, by what they come to.
outcomeNames :: [String]
outcomeNames =
  [ "a refusing #EVAL"
  , "a refused #ASSERT"
  , "a satisfied #ASSERT REFUSED"
  , "a failed #ASSERT"
  , "an #EVAL that raises"
  , "an #ASSERT that raises"
  , "an answered #EVAL"
  ]

results :: Text -> IO [EL.EvalDirectiveResult]
results src = case checkWithImports emptyVFS src of
  Left errs -> do
    expectationFailure ("the module did not check:\n" <> Text.unpack (Text.unlines errs))
    pure []
  Right r -> case filter ((== SError) . TC.severity) r.tcdErrors of
    [] -> do
      cfg <- EL.resolveEvalConfigWithSafeMode Nothing apiDefaultPolicy True
      snd <$> EL.execEvalModuleWithEnv cfg r.tcdEntityInfo mempty r.tcdModule
    errs -> do
      expectationFailure ("the module did not check: " <> show (length errs) <> " errors")
      pure []

decode :: Text -> Aeson.Value
decode t = case Aeson.eitherDecodeStrict (Text.encodeUtf8 t) of
  Right v -> v
  Left e -> error ("not JSON: " <> e <> "\n" <> Text.unpack t)

field :: Text -> Aeson.Value -> Maybe Aeson.Value
field k = \case
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

spec :: Spec
spec = describe "reporting a refusal" $ do
  -- The severity the editor shows for each outcome. The language server, and
  -- with it `l4 run`'s diagnostics, and the browser editor's evaluation all
  -- take it from here.
  it "gives a refusal warning severity, a failure and an evaluation that raises error severity, and an answer information" $ do
    rs <- results outcomesModule
    zip outcomeNames (map ((.sdSeverity) . evalResultToDiagnostic) rs) `shouldBe` zip outcomeNames
      [ DSWarning, DSWarning, DSInformation, DSError, DSError, DSError, DSInformation ]

  -- The browser editor calls 'l4Eval': a refusal there has no success, true or
  -- false, and carries the severity the editor shows it with.
  it "is neither a success nor a failure to the editor's l4Eval, and carries warning severity" $ do
    out <- decode <$> l4Eval outcomesModule
    field "success" out `shouldBe` Just (Aeson.Bool True)
    case field "results" out of
      Just (Aeson.Array rs) ->
        zip outcomeNames [ (field "success" r, field "severity" r) | r <- toList rs ] `shouldBe` zip outcomeNames
          [ (Just Aeson.Null, Just (Aeson.Number 2))
          , (Just Aeson.Null, Just (Aeson.Number 2))
          , (Just (Aeson.Bool True), Just (Aeson.Number 3))
          , (Just (Aeson.Bool False), Just (Aeson.Number 1))
          , (Just (Aeson.Bool False), Just (Aeson.Number 1))
          , (Just (Aeson.Bool False), Just (Aeson.Number 1))
          , (Just (Aeson.Bool True), Just (Aeson.Number 3))
          ]
      other -> expectationFailure ("expected a results array, got " <> show other)

  -- The Inspector of the browser editor calls 'l4EvalDirective' for one
  -- directive. A refusal, of an #EVAL or of an #ASSERT, has a null success
  -- there.
  it "is neither a success nor a failure to the editor's l4EvalDirective" $ do
    let successAt line = field "success" . decode <$> l4EvalDirective outcomesModule line 1 "#ASSERT"
    refusedAssert <- successAt 5
    refusedAssert `shouldBe` Just Aeson.Null
    refusingEval <- successAt 4
    refusingEval `shouldBe` Just Aeson.Null
    failed <- successAt 7
    failed `shouldBe` Just (Aeson.Bool False)
    held <- successAt 6
    held `shouldBe` Just (Aeson.Bool True)

  -- The Inspector asks 'l4EvalDirective' when it holds no result of 'l4Eval'
  -- for the directive, so the two give each directive one success.
  it "gives each directive the success l4Eval gives it, to the editor's l4EvalDirective" $ do
    out <- decode <$> l4Eval outcomesModule
    let evalSuccesses = case field "results" out of
          Just (Aeson.Array rs) -> [ field "success" r | r <- toList rs ]
          _ -> []
    directiveSuccesses <- mapM
      (\line -> field "success" . decode <$> l4EvalDirective outcomesModule line 1 "#EVAL")
      [4 .. 10]
    length evalSuccesses `shouldBe` length outcomeNames
    zip outcomeNames directiveSuccesses `shouldBe` zip outcomeNames evalSuccesses

  -- The code lens over a directive names it, and the editor passes the name
  -- back when it asks for the directive's result.
  it "names an #ASSERT REFUSED in its code lens, beside the other directives" $ do
    let lenses = decode (l4CodeLenses outcomesModule "file:///outcomes.l4" 1)
        labelAt line = case lenses of
          Aeson.Array ls ->
            [ label
            | l <- toList ls
            , Just (Aeson.Number n) <- [field "range" l >>= field "startLineNumber"]
            , n == fromIntegral line
            , Just (Aeson.Array args) <- [field "command" l >>= field "arguments"]
            , Aeson.String label <- drop 2 (toList args)
            ]
          _ -> []
    map labelAt [4 :: Int, 5, 6] `shouldBe` [["#EVAL"], ["#ASSERT"], ["#ASSERT REFUSED"]]
