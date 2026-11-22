{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | How the check of a nest of calls with one undefined name scales with its depth.
module VariadicRescueScaleSpec (spec) where

import Control.Exception (evaluate)
import Data.Text (Text)
import qualified Data.Text as Text
import System.Mem (getAllocationCounter)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))

spec :: Spec
spec = do
  scaling
  deepNest

scaling :: Spec
scaling = describe "a chain with one undefined name" $ do
  -- A chain of AND, OR, PLUS, `=` or a two-argument function with one
  -- undefined name at the end the checker reaches deepest used to double
  -- its time with every extra term: `l4 check` took 10 s at 20 terms and
  -- did not finish in two minutes at 24 (smucclaw/l4-ide#1049). Every call with two
  -- or more arguments re-checked its arguments in the variadic-construction
  -- rescue, which cannot apply to a name that is no constructor of one LIST
  -- field, and the rescue's own re-check did the same one level down.
  --
  -- Counted in the bytes this thread allocates, which nothing else running
  -- changes, as the ratio between a chain of 16 terms and one of 8. Linear
  -- cost gives a ratio near 2 and doubling per term gives 256; the test
  -- fails at 8.
  mapM_ chainScales
    [ ("AND, the name last", andChain)
    , ("OR, the name last", orChain)
    , ("PLUS, the name first", plusChain)
    , ("a nest of `=` over `<`, the name first", eqChain)
    , ("a function of two arguments, the name last", callChain)
    , ("PLUS with the prelude imported, the name first", plusPreludeChain)
    ]

chainScales :: (String, Int -> Text) -> Spec
chainScales (label, source) =
  it ("is checked in time that does not double with each term: " <> label) $ do
    let allocated k = do
          src <- evaluate (source k)
          _ <- evaluate (Text.length src)
          a0 <- getAllocationCounter
          errs <- case checkWithImports emptyVFS src of
            Left es -> fail ("the module failed to check: " <> show es)
            Right r -> evaluate (length r.tcdErrors)
          a1 <- getAllocationCounter
          pure (errs, fromIntegral (a0 - a1) :: Double)
    -- Whatever the first check of a module computes once, it computes here.
    _ <- allocated 2
    (errsSmall, small) <- allocated 8
    (errsLarge, large) <- allocated 16
    -- The undefined name was reported, at both sizes.
    (errsSmall > 0, errsLarge > 0) `shouldBe` (True, True)
    large / small `shouldSatisfy` (< 8)

-- p AND p AND ... AND nope
andChain :: Int -> Text
andChain k = booleanChain (Text.intercalate " AND " (replicate (k - 1) "p" <> ["nope"]))

orChain :: Int -> Text
orChain k = booleanChain (Text.intercalate " OR " (replicate (k - 1) "p" <> ["nope"]))

booleanChain :: Text -> Text
booleanChain body =
  Text.unlines
    [ "GIVEN x IS A NUMBER"
    , "      p IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "DECIDE `chain` IS"
    , "    " <> body
    ]

-- nope PLUS x PLUS ... PLUS x
plusChain :: Int -> Text
plusChain k =
  Text.unlines
    [ "GIVEN x IS A NUMBER"
    , "      p IS A BOOLEAN"
    , "GIVETH A NUMBER"
    , "DECIDE `chain` IS"
    , "    " <> Text.intercalate " PLUS " ("nope" : replicate (k - 1) "x")
    ]

-- IMPORT prelude, then nope PLUS x PLUS ... PLUS x: with the prelude in scope
-- PLUS has more than one candidate, so each level also forks.
plusPreludeChain :: Int -> Text
plusPreludeChain k = "IMPORT prelude\n\n" <> plusChain k

-- ((nope < 1) = (x < 2)) = (x < 3) ... = (x < k)
eqChain :: Int -> Text
eqChain k =
  Text.unlines
    [ "GIVEN x IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "DECIDE `chain` IS"
    , "    " <> foldl nest "(nope < 1)" [2 .. k]
    ]
 where
  nest acc i = "(" <> acc <> " = (x < " <> Text.pack (show i) <> "))"

-- f p (f p (... (f p nope)))
callChain :: Int -> Text
callChain k =
  Text.unlines
    [ "GIVEN a IS A BOOLEAN"
    , "      b IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "DECIDE f a b IS a AND b"
    , ""
    , "GIVEN p IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "DECIDE `chain` IS"
    , "    " <> foldr (\_ acc -> "f p (" <> acc <> ")") "nope" [1 .. k - 1]
    ]

-- A valid nest of variadic constructions is accepted at any depth: each call
-- of two arguments is read directly, fails on its arity, and is read again
-- by the rescue, which is what makes it valid. Nothing may cut that off.
deepNest :: Spec
deepNest = describe "a nest of variadic constructions" $
  it "is accepted 12 levels deep" $ do
    case checkWithImports emptyVFS (treeNest 12) of
      Left es -> fail ("the module failed to check: " <> show es)
      Right r -> length r.tcdErrors `shouldBe` 0

-- t MEANS Tree OF (Tree OF (... (Tree OF leaf, leaf) ...), leaf), leaf
treeNest :: Int -> Text
treeNest k =
  Text.unlines
    [ "DECLARE Tree"
    , "  HAS kids IS A LIST OF Tree"
    , ""
    , "leaf MEANS Tree OF EMPTY"
    , ""
    , "t MEANS " <> Text.drop 1 (Text.dropEnd 1 (foldr (\_ acc -> "(Tree OF " <> acc <> ", leaf)") "leaf" [1 .. k]))
    ]
