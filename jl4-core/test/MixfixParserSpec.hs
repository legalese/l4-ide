{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
module MixfixParserSpec (spec) where

import Base hiding (listToMaybe)
import Data.Maybe (listToMaybe)
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (buildMixfixHintRegistry, execProgramParserWithHintPass)
import L4.Syntax (AppForm (..), Decide (..), Expr (..), Module (..), Name, Section (..), TopDecl (..), pattern Var, rawName, rawNameToText)
import Test.Hspec

spec :: Spec
spec =
  describe "Mixfix parser hint pass" $ do
    it "parses a simple mixfix module with registry hints" $ do
      let uri = toNormalizedUri (Uri "file:///mixfix-parser-spec")
          parsed = execProgramParserWithHintPass uri mixfixFixture
      case parsed of
        Left errs ->
          expectationFailure $
            "Parser failed with: " <> show errs
        Right (moduleAst, hints, _warnings) ->
          hints `shouldBe` buildMixfixHintRegistry moduleAst

    it "accepts multiline mixfix and postfix invocations when aligned" $ do
      let uri = toNormalizedUri (Uri "file:///mixfix-multiline-spec")
          parsed = execProgramParserWithHintPass uri multilineFixture
      case parsed of
        Left errs ->
          expectationFailure $
            "Parser failed with: " <> show errs
        Right (moduleAst, _hints, _warnings) -> do
          postfixBody <- expectBody "demo_multiline_postfix" moduleAst
          mixfixBody <- expectBody "demo_multiline_mixfix" moduleAst
          chainBody <- expectBody "demo_multiline_chain" moduleAst
          assertPostfix postfixBody
          assertBinary mixfixBody
          assertChain chainBody

    describe "exact-print round-trip (issue #918)" $ do
      -- `l4 format` is exactprint of the parsed AST, so exactprint must be
      -- the identity on source text. Before the fix, infix mixfix call
      -- sites were rewritten to prefix form (`1 UNION 2` -> `UNION 1 2`)
      -- and chained keywords were printed twice.
      it "round-trips the mixfix fixture (bare + backticked, binary + ternary)" $
        roundTrips mixfixFixture

      it "round-trips the multiline fixture (aligned mixfix + postfix)" $
        roundTrips multilineFixture

      it "round-trips the issue-918 repro (UNION call sites stay infix)" $
        roundTrips issue918Fixture

      it "round-trips an unparenthesized chain without reordering tokens" $
        -- `1 UNION 2 UNION 3` does not typecheck (arity), but formatting
        -- happens before typechecking and must not reorder tokens.
        roundTrips (unionPrologue <> "chain MEANS 1 UNION 2 UNION 3\n")

      it "round-trips infix call sites with trailing comments" $
        roundTrips (unionPrologue <> "commented MEANS 1 UNION 2 -- trailing note\n")

roundTrips :: T.Text -> Expectation
roundTrips src =
  case execProgramParserWithHintPass uri src of
    Left errs ->
      expectationFailure $ "Parser failed with: " <> show errs
    Right (moduleAst, _hints, _warnings) ->
      case exactprint moduleAst of
        Left err -> expectationFailure $ "exactprint failed: " <> show err
        Right printed -> printed `shouldBe` src
  where
    uri = toNormalizedUri (Uri "file:///mixfix-roundtrip-spec")

unionPrologue :: T.Text
unionPrologue =
  T.unlines
    [ "IMPORT prelude"
    , ""
    , "GIVEN p IS A NUMBER"
    , "      q IS A NUMBER"
    , "GIVETH A NUMBER"
    , "p UNION q MEANS p + q"
    , ""
    ]

issue918Fixture :: T.Text
issue918Fixture =
  unionPrologue
    <> T.unlines
      [ "single MEANS 1 UNION 2"
      , ""
      , "nested MEANS (1 UNION 2) UNION 3"
      , ""
      , "backtick MEANS 1 `UNION` 2"
      ]

assertPostfix :: Expr Name -> Expectation
assertPostfix expr =
  case expr of
    App _ funcName [Var _ radiusName] -> do
      rawNameText funcName `shouldBe` "squared"
      rawNameText radiusName `shouldBe` "radius"
    _ -> expectationFailure $ "Expected postfix App but got: " <> show expr

assertBinary :: Expr Name -> Expectation
assertBinary expr =
  case expr of
    App _ funcName [Var _ baseName, Var _ exponentName] -> do
      rawNameText funcName `shouldBe` "raised to"
      rawNameText baseName `shouldBe` "base"
      rawNameText exponentName `shouldBe` "exponent"
    _ -> expectationFailure $ "Expected binary mixfix App but got: " <> show expr

assertChain :: Expr Name -> Expectation
assertChain expr =
  case expr of
    App _ funcName [Var _ payerName, Var _ payeeName, Var _ keywordName, Var _ ledgerName] -> do
      rawNameText funcName `shouldBe` "remits"
      rawNameText payerName `shouldBe` "payer"
      rawNameText payeeName `shouldBe` "payee"
      rawNameText keywordName `shouldBe` "to settle"
      rawNameText ledgerName `shouldBe` "ledger"
    _ -> expectationFailure $ "Expected ternary mixfix chain but got: " <> show expr

expectBody :: T.Text -> Module Name -> IO (Expr Name)
expectBody target modu =
  case lookupDecideBody target modu of
    Nothing -> do
      let names = decideNames modu
      expectationFailure ("Unable to find Decide named " <> T.unpack target <> ". Available: " <> show (map T.unpack names))
      fail "unreachable"
    Just body -> pure body

decideNames :: Module Name -> [T.Text]
decideNames (MkModule _ _ (MkSection _ _ _ decls)) =
  [ rawNameText fn
  | Decide _ (MkDecide _ _ (MkAppForm _ fn _ _) _) <- decls
  ]

lookupDecideBody :: T.Text -> Module Name -> Maybe (Expr Name)
lookupDecideBody target (MkModule _ _ (MkSection _ _ _ decls)) =
  listToMaybe
    [ body
    | Decide _ (MkDecide _ _ (MkAppForm _ fn _ _) body) <- decls
    , rawNameText fn == target
    ]

rawNameText :: Name -> T.Text
rawNameText = rawNameToText . rawName

mixfixFixture :: T.Text
mixfixFixture =
  T.unlines
    [ "§ `Mixfix Operators With Variables`"
    , ""
    , "-- Regression tests ensuring mixfix operators (beyond pure postfix) accept bare"
    , "-- variables as operands, both at top level and within LET...IN blocks."
    , "--"
    , "-- These tests complement postfix coverage in postfix-with-variables.l4."
    , ""
    , "IMPORT prelude"
    , ""
    , "-- Simple binary mixfix operator."
    , "GIVEN left IS A NUMBER, right IS A NUMBER"
    , "left `mixadd` right MEANS left + right"
    , ""
    , "-- Ternary mixfix operator with two keywords."
    , "GIVEN base IS A NUMBER, delta IS A NUMBER, cap IS A NUMBER"
    , "base `climb` delta `toward` cap MEANS base + delta + cap"
    , ""
    , "-- Another ternary operator whose keywords can be written without backticks."
    , "GIVEN start IS A NUMBER, pivot IS A NUMBER, finish IS A NUMBER"
    , "start `via` pivot `onto` finish MEANS start + pivot + finish"
    , ""
    , "-- ====================================================================="
    , "-- Tests: binary mixfix with bare variables"
    , "-- ====================================================================="
    , ""
    , "GIVEN x IS A NUMBER"
    , "mixfixVarInfixBacktick MEANS x `mixadd` 5"
    , ""
    , "#EVAL mixfixVarInfixBacktick OF 7"
    , "-- Expected: 12"
    , ""
    , "-- Mixfix analogue of the original postfix bug:"
    , "-- Previously, bare variables like `x mixadd 5` could be mis-parsed similarly to `x squared`."
    , "GIVEN x_bug IS A NUMBER"
    , "mixfixOriginalShape MEANS x_bug mixadd 5"
    , ""
    , "#EVAL mixfixOriginalShape OF 3"
    , "-- Expected: 8"
    , ""
    , "-- LET...IN scope still sees bare variables."
    , "GIVEN z IS A NUMBER"
    , "mixfixVarInfixLet MEANS"
    , "  LET tmp BE z + 1"
    , "  IN tmp mixadd 2"
    , ""
    , "#EVAL mixfixVarInfixLet OF 4"
    , "-- Expected: 7"
    , ""
    , "-- ====================================================================="
    , "-- Tests: ternary mixfix with bare variables"
    , "-- ====================================================================="
    , ""
    , "GIVEN a IS A NUMBER, b IS A NUMBER"
    , "mixfixVarMultiBacktick MEANS a `climb` b `toward` 10"
    , ""
    , "#EVAL mixfixVarMultiBacktick OF 2, 3"
    , "-- Expected: 15"
    , ""
    , "GIVEN c IS A NUMBER, d IS A NUMBER"
    , "mixfixVarMultiBare MEANS c via d onto 1"
    , ""
    , "#EVAL mixfixVarMultiBare OF 5, 6"
    , "-- Expected: 12"
    ]

multilineFixture :: T.Text
multilineFixture =
  T.unlines
    [ "IMPORT prelude"
    , ""
    , "GIVEN n IS A NUMBER"
    , "n squared MEANS n * n"
    , ""
    , "GIVEN radius IS A NUMBER"
    , "demo_multiline_postfix radius MEANS"
    , "  radius"
    , "  `squared`"
    , ""
    , "GIVEN base IS A NUMBER"
    , "      exponent IS A NUMBER"
    , "base `raised to` exponent MEANS base * exponent"
    , ""
    , "demo_multiline_mixfix base exponent MEANS"
    , "  base"
    , "  `raised to`"
    , "  exponent"
    , ""
    , "GIVEN payer IS A NUMBER"
    , "      payee IS A NUMBER"
    , "      ledger IS A NUMBER"
    , "payer `remits` payee `to settle` ledger MEANS payer + payee + ledger"
    , ""
    , "demo_multiline_chain payer payee ledger MEANS"
    , "  payer"
    , "  `remits`"
    , "  payee"
    , "  `to settle`"
    , "  ledger"
    ]
