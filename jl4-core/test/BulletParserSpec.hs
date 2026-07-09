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

  describe "known corner case: a bare name at a vertical LIST's item column" $ do
    -- indentedGE (>=, not just >) is what lets a child bullet line up
    -- directly under its parent's head word (see the "singleton"/"multiple
    -- bullet-block arguments" groups above). The same relaxation also
    -- applies when a bare, unsaturated identifier is itself a vertical
    -- LIST's item — such a name and a LIST's items share one EQ column, so
    -- an aligned bullet block that follows is absorbed as the name's
    -- ARGUMENT rather than treated as the next sibling LIST item. This is
    -- pinned as the intended behaviour (rather than narrowed) because it
    -- only bites a bare name that is itself arity-overloaded across a 0-arg
    -- and a list-taking definition (e.g. `item`, or the month constants in
    -- daydate.l4) — a combination that, as of this test, no file in the
    -- repository's corpus hits (see the bullet-list-syntax branch's review
    -- notes). Wrap the name in parens, e.g. `(reverse)`, to force it back
    -- into a standalone sibling LIST item instead.
    it "absorbs an aligned bullet block into a preceding bare LIST item as its argument" $ do
      expr <- decideExprNamed "xs" $ Text.unlines
        [ "DECIDE xs IS"
        , "  LIST"
        , "    reverse"
        , "    \x2022 1"
        , "    \x2022 2"
        ]
      case expr of
        List _ [App _ fn [List _ [_, _]]] -> rawNameText fn `shouldBe` "reverse"
        _ -> expectationFailure $ "Expected LIST [reverse [1,2]], got: " <> show expr

    it "parens around the bare name keep it a separate sibling LIST item" $ do
      expr <- decideExprNamed "xs" $ Text.unlines
        [ "DECIDE xs IS"
        , "  LIST"
        , "    (reverse)"
        , "    \x2022 1"
        , "    \x2022 2"
        ]
      case expr of
        List _ [App _ fn [], List _ [_, _]] -> rawNameText fn `shouldBe` "reverse"
        _ -> expectationFailure $ "Expected LIST [reverse, [1,2]], got: " <> show expr
