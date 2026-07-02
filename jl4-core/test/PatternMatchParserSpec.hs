{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

-- | Unit tests for Phase 1 pattern matching in function definitions: multiple
-- DECIDE/MEANS clauses sharing a head name are grouped into a single 'MkDecide'
-- whose body is a nested CONSIDER, while ordinary single-clause definitions are
-- left untouched. See specs/todo/PATTERN-MATCHING-SPEC.md.
module PatternMatchParserSpec (spec) where

import Base
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import L4.Parser (execProgramParser)
import L4.Syntax
import Test.Hspec

spec :: Spec
spec = describe "Pattern-matching DECIDE desugaring (parser)" $ do
  it "groups multiple literal/variable clauses into one CONSIDER-bodied Decide" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE factorial 0 IS 1"
          , "DECIDE factorial n IS n * factorial (n - 1)"
          ]
    decides <- parseDecides src
    -- A single merged Decide, not two.
    map decideHeadText decides `shouldBe` ["factorial"]
    map decideBodyIsConsider decides `shouldBe` [True]

  it "groups constructor-pattern clauses (EMPTY / FOLLOWED BY) into one Decide" $ do
    let src = T.unlines
          [ "GIVEN list IS A LIST OF NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE len EMPTY IS 0"
          , "DECIDE len (x FOLLOWED BY xs) IS 1 + len xs"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["len"]
    map decideBodyIsConsider decides `shouldBe` [True]

  it "desugars a single clause that uses a literal pattern" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE isZero 0 IS 1"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["isZero"]
    map decideBodyIsConsider decides `shouldBe` [True]

  it "leaves an ordinary single variable-clause definition untouched" $ do
    let src = T.unlines
          [ "GIVEN x IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE double x IS x * 2"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["double"]
    -- Not desugared to a CONSIDER: the body is the ordinary arithmetic expr.
    map decideBodyIsConsider decides `shouldBe` [False]

  it "keeps two differently-named functions as two separate Decides" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE inc 0 IS 1"
          , "DECIDE inc n IS n + 1"
          , ""
          , "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE dec 0 IS 0"
          , "DECIDE dec n IS n - 1"
          ]
    decides <- parseDecides src
    map decideHeadText decides `shouldBe` ["inc", "dec"]

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

parseDecides :: T.Text -> IO [Decide Name]
parseDecides src =
  case execProgramParser (toNormalizedUri (Uri "file:///pattern-match-spec")) src of
    Left errs ->
      fail ("Parser failed with: " <> show (NE.toList errs))
    Right (MkModule _ _ (MkSection _ _ _ decls), _warnings) ->
      pure [ d | Decide _ d <- decls ]

decideHeadText :: Decide Name -> T.Text
decideHeadText (MkDecide _ _ (MkAppForm _ n _ _) _) = rawNameToText (rawName n)

decideBodyIsConsider :: Decide Name -> Bool
decideBodyIsConsider (MkDecide _ _ _ body) =
  case body of
    Consider {} -> True
    _           -> False
