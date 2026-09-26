{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The read-set of an @\@export@ is transitive: an ASSUME read by a helper
-- the export reaches (a module-level DECIDE, a WHERE-local, a mutually
-- recursive pair) is a parameter of the export, in the schema that
-- 'L4.Export.getExportedFunctions' and 'L4.FunctionSchema' publish. Before
-- this was so, the schema listed only the export body's own references, so
-- a request that validated against it could still get stuck on an assumed
-- term at evaluation time.
module ExportReadSetSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (ExportedFunction(..), ExportedParam(..), getExportedFunctions)
import L4.FunctionSchema (Parameters(..), Parameter(..), parametersFromDecide)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))

-- | The parameter names of the single export in a source snippet.
exportParamNames :: Text -> Either [Text] [Text]
exportParamNames source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> case getExportedFunctions r.tcdModule of
      [ef] -> Right (map (.paramName) ef.exportParams)
      efs  -> Left ["expected exactly one export, got " <> Text.pack (show (length efs))]

-- | The JSON-schema 'Parameters' of the single export in a source snippet.
exportSchema :: Text -> Either [Text] Parameters
exportSchema source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> case getExportedFunctions r.tcdModule of
      [ef] -> Right (parametersFromDecide r.tcdModule ef.exportDecide)
      efs  -> Left ["expected exactly one export, got " <> Text.pack (show (length efs))]

-- | The GIVEN/ASSUME name-clash errors a snippet raises.
nameClashErrors :: Text -> Either [Text] [CheckErrorWithContext]
nameClashErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e | e@MkCheckErrorWithContext{kind = ExportAssumeNameClash _ _} <- r.tcdErrors ]

helperReadsAssume :: Text
helperReadsAssume = Text.unlines
  [ "ASSUME x IS A NUMBER"
  , "g MEANS x PLUS 1"
  , ""
  , "@export f adds"
  , "GIVEN y IS A NUMBER"
  , "GIVETH A NUMBER"
  , "f y MEANS g PLUS y"
  ]

spec :: Spec
spec = do
  describe "transitive export read-set" $ do
    it "lists an ASSUME read only by a module-level helper" $ do
      exportParamNames helperReadsAssume `shouldBe` Right ["y", "x"]

    it "lists an ASSUME read only by a WHERE-local helper" $ do
      let src = Text.unlines
            [ "ASSUME x IS A NUMBER"
            , ""
            , "@export helper in WHERE reads the ASSUME"
            , "GIVEN y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f y MEANS h PLUS y"
            , "  WHERE"
            , "    h MEANS x PLUS 1"
            ]
      exportParamNames src `shouldBe` Right ["y", "x"]

    it "reaches an ASSUME through mutual recursion (and terminates)" $ do
      let src = Text.unlines
            [ "ASSUME x IS A NUMBER"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "even n MEANS IF n EQUALS 0 THEN x ELSE odd (n MINUS 1)"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "odd n MEANS IF n EQUALS 0 THEN 0 ELSE even (n MINUS 1)"
            , ""
            , "@export mutual recursion reaches the ASSUME"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f n MEANS even n"
            ]
      exportParamNames src `shouldBe` Right ["n", "x"]

    it "does not list an ASSUME no reachable definition reads" $ do
      let src = Text.unlines
            [ "ASSUME x IS A NUMBER"
            , "ASSUME z IS A NUMBER"
            , "g MEANS x PLUS 1"
            , "unrelated MEANS z PLUS 1"
            , ""
            , "@export f adds"
            , "GIVEN y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f y MEANS g PLUS y"
            ]
      exportParamNames src `shouldBe` Right ["y", "x"]

  describe "function schema for read ASSUMEs" $ do
    it "requires a helper-read ASSUME exactly once" $ do
      case exportSchema helperReadsAssume of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps -> do
          ps.required `shouldBe` ["y", "x"]
          Map.keys ps.parameterMap `shouldBe` ["x", "y"]

    it "carries the ASSUME's own @desc into the schema" $ do
      let src = Text.unlines
            [ "@desc the offset added by the helper"
            , "ASSUME x IS A NUMBER"
            , "g MEANS x PLUS 1"
            , ""
            , "@export f adds"
            , "GIVEN y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f y MEANS g PLUS y"
            ]
      case exportSchema src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps ->
          fmap (.parameterDescription) (Map.lookup "x" ps.parameterMap)
            `shouldBe` Just "the offset added by the helper"

  describe "GIVEN / ASSUME name clash" $ do
    let clash = Text.unlines
          [ "ASSUME x IS A NUMBER"
          , "g MEANS x PLUS 1"
          , ""
          , "@export f adds"
          , "GIVEN x IS A NUMBER"
          , "GIVETH A NUMBER"
          , "f x MEANS g PLUS x"
          ]

    it "is reported as a check error" $ do
      case nameClashErrors clash of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right es -> length es `shouldBe` 1

    it "is not reported when the names differ" $ do
      case nameClashErrors helperReadsAssume of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right es -> es `shouldBe` []

    it "keeps one property and one required entry for the clashing name" $ do
      case exportSchema clash of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps -> do
          ps.required `shouldBe` ["x"]
          Map.keys ps.parameterMap `shouldBe` ["x"]
