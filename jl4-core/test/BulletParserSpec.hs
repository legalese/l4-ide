{-# LANGUAGE OverloadedStrings #-}
module BulletParserSpec (spec) where

import Base
import qualified Base.Text as Text
import L4.Parser (execProgramParserWithHintPass)
import L4.Syntax
  ( AppForm (..)
  , Decide (..)
  , Expr (..)
  , Lit (..)
  , Module (..)
  , Name
  , Section (..)
  , TopDecl (..)
  , rawName
  , rawNameToText
  )
import Test.Hspec

rawNameText :: Name -> Text
rawNameText = rawNameToText . rawName

-- | Parse a source snippet and return the body of the DECIDE (or bare
-- @name args MEANS ...@ definition) whose head is named @target@.
decideExprNamed :: Text -> Text -> IO (Expr Name)
decideExprNamed target src = do
  let uri = toNormalizedUri (Uri "file:///bullet-parser-spec")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      case [ body | Decide _ (MkDecide _ _ (MkAppForm _ nm _ _) body) <- decls, rawNameText nm == target ] of
        (body : _) -> pure body
        [] -> do
          expectationFailure $ "No DECIDE named " <> Text.unpack target <> " found among: " <> show decls
          error "unreachable"

-- | Assert that a source snippet fails to parse.
shouldFailToParse :: Text -> Expectation
shouldFailToParse src = do
  let uri = toNormalizedUri (Uri "file:///bullet-parser-spec-bad")
  case execProgramParserWithHintPass uri src of
    Left _ -> pure ()
    Right (m, _, _) -> expectationFailure $ "Expected a parse error, got: " <> show m

spec :: Spec
spec = describe "'•' bullet-list syntax" $ do
  describe "singleton lists" $ do
    it "parses a single-item plain bullet list" $ do
      expr <- decideExprNamed "xs" "DECIDE xs IS\n  \x2022 1"
      case expr of
        List _ [Lit _ (NumericLit _ _)] -> pure ()
        _ -> expectationFailure $ "Expected a 1-element List, got: " <> show expr

    it "parses a single bullet child in argument position" $ do
      expr <- decideExprNamed "solo" $ Text.unlines
        [ "IMPORT hierarchy"
        , ""
        , "DECIDE solo IS"
        , "  item \"Parent\""
        , "    \x2022 item \"OnlyChild\""
        ]
      case expr of
        App _ fn [_, List _ [App _ innerFn _]] -> do
          rawNameText fn `shouldBe` "item"
          rawNameText innerFn `shouldBe` "item"
        _ -> expectationFailure $ "Expected item txt [item OnlyChild], got: " <> show expr

  describe "multiple bullet-block arguments" $ do
    it "parses a bullet block alongside a preceding scalar argument" $ do
      -- `item "Parent" • child` — the bullet block is the SECOND of two
      -- juxtaposed arguments, not the sole one.
      expr <- decideExprNamed "withPreceding" $ Text.unlines
        [ "IMPORT hierarchy"
        , ""
        , "DECIDE withPreceding IS"
        , "  item \"Parent\""
        , "    \x2022 item \"a\""
        , "    \x2022 item \"b\""
        ]
      case expr of
        App _ fn [_, List _ [_, _]] -> rawNameText fn `shouldBe` "item"
        _ -> expectationFailure $ "Expected item txt [a, b], got: " <> show expr

    it "parses two sibling bullet blocks at different columns as two separate list arguments" $ do
      expr <- decideExprNamed "combined" $ Text.unlines
        [ "both xs ys MEANS LIST xs, ys"
        , ""
        , "DECIDE combined IS"
        , "  both"
        , "    \x2022 1"
        , "    \x2022 2"
        , "      \x2022 3"
        , "      \x2022 4"
        ]
      case expr of
        App _ fn [List _ [_, _], List _ [_, _]] -> rawNameText fn `shouldBe` "both"
        _ -> expectationFailure $ "Expected both [1,2] [3,4], got: " <> show expr

  describe "misalignment is rejected" $ do
    it "rejects a bullet marker glued to its body (no space)" $
      -- '\&' forces the hex escape to stop at U+2022 rather than greedily
      -- consuming the following digit as part of a longer codepoint.
      shouldFailToParse "DECIDE xs IS\n  \x2022\&1"

    it "rejects a dangling bullet marker with no same-line body" $
      shouldFailToParse "DECIDE xs IS\n  \x2022\n#EVAL xs"

    it "rejects a bullet block whose items drift to a new column mid-block" $
      shouldFailToParse "DECIDE xs IS\n  \x2022 1\n    \x2022 2"
