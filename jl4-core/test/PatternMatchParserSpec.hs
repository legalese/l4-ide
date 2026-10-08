{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

-- | Unit tests for Phase 1 pattern matching in function definitions: multiple
-- DECIDE/MEANS clauses sharing a head name are grouped into a single 'MkDecide'
-- whose body is a nested CONSIDER, while ordinary single-clause definitions are
-- left untouched. See specs/todo/PATTERN-MATCHING-SPEC.md.
module PatternMatchParserSpec (spec) where

import Base
import Control.Exception (evaluate)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import GHC.Clock (getMonotonicTime)
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

  -- A run of clauses that starts no group is read once, not once for each of
  -- its clauses: a file of n lines @f x MEANS i@ was read about n * n / 2
  -- times, and 4,000 lines took minutes to check (review of
  -- legalese/l4-ide#545, round 2). Timed by the ratio of two sizes, not by a
  -- bound in seconds, so that a slow machine does not fail it: four times the
  -- lines take about four times as long when parsing is linear, and sixteen
  -- times as long when it is quadratic. The larger size is timed again when
  -- it looks slow, so that one pause does not fail it either.
  it "parses a run of same-headed definitions in time linear in its length" $ do
    let file k = T.unlines [ "f x MEANS " <> T.pack (show i) | i <- [1 .. k :: Int] ]
        timeParse k = do
          src <- evaluate (file k)
          _ <- evaluate (T.length src)
          t0 <- getMonotonicTime
          n <- length <$> parseDecides src
          t1 <- getMonotonicTime
          n `shouldBe` k
          pure (t1 - t0)
        fastest k tries = minimum <$> traverse (const (timeParse k)) [1 .. tries :: Int]
    small <- fastest 250 3
    let ratio large = large / max small 1.0e-3
        settle tries = do
          large <- timeParse 1000
          if ratio large < 8 || tries <= (1 :: Int) then pure (ratio large) else min (ratio large) <$> settle (tries - 1)
    r <- settle 3
    r `shouldSatisfy` (< 8)

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

parseDecides :: T.Text -> IO [Decide Name]
parseDecides src =
  case execProgramParser (toNormalizedUri (Uri "file:///pattern-match-spec")) src of
    Left errs ->
      fail ("Parser failed with: " <> show (NE.toList errs))
    Right (MkModule _ _ (MkSection _ _ _ _ decls), _warnings) ->
      pure [ d | Decide _ d <- decls ]

decideHeadText :: Decide Name -> T.Text
decideHeadText (MkDecide _ _ (MkAppForm _ n _ _) _) = rawNameToText (rawName n)

-- | Is the desugared body a CONSIDER-based decision tree? We look through any
-- leading @LET ... IN@: to keep the emitted tree linear (rather than
-- exponential) in the number of clauses, each non-final clause binds the
-- desugaring of the remaining clauses to a fresh nullary local via @LET ... IN@,
-- and the decision CONSIDER is that LET's body. A single-clause desugar has no
-- fall-through and so is a bare CONSIDER.
decideBodyIsConsider :: Decide Name -> Bool
decideBodyIsConsider (MkDecide _ _ _ body) = go body
  where
    go = \ case
      Consider {}  -> True
      LetIn _ _ e  -> go e
      _            -> False
