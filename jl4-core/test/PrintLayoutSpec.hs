{-# LANGUAGE OverloadedStrings #-}

-- | The layout L4's printer renders through ('L4.Print.Layout'): the same
-- output as prettyprinter's Unbounded layout, without its quadratic cost
-- on long lines (smucclaw/l4-ide#1075).
module PrintLayoutSpec (spec) where

import Control.Exception (evaluate)
import qualified Data.Text as Text
import Prettyprinter
import System.CPUTime (getCPUTime)
import Test.Hspec
import Test.Hspec.QuickCheck (modifyMaxSuccess, prop)
import Test.QuickCheck

import L4.Print (docText)
import L4.Print.Layout (layoutUnboundedLocal)

spec :: Spec
spec = describe "L4.Print.Layout" $ do
  -- Byte-identical to the library is the whole contract: every golden and
  -- every printed value relies on it. The documents are built from the
  -- public combinators only, which cannot make an explicit 'Fail', the one
  -- input the two layouts may treat differently. 'column', 'nesting',
  -- 'width' and 'pageWidth' choose between two documents, so a layout that
  -- read a position wrongly would print the other one.
  modifyMaxSuccess (const 3000) $
    prop "lays out every document exactly as layoutPretty Unbounded does" $
      forAll (sized (genDoc . min 64)) \ d ->
        layoutUnboundedLocal d === layoutPretty (LayoutOptions Unbounded) d

  -- The shape L4.Print relies on: 'group' around a hard line inside
  -- 'align' keeps the vertical layout, because flattening would fail.
  it "keeps a hard line inside align inside group" $
    docText (group ("GIVEN" <+> align (vsepHard ["a", "b"])))
      `shouldBe` "GIVEN a\n      b"

  it "flattens a group whose flat form fits" $
    docText (group ("a" <> line <> "b") <> hardline <> "c")
      `shouldBe` "a b\nc"

  -- Printing a value whose text is one long line used to take time
  -- quadratic in the number of groups on that line: prettyprinter checks
  -- each group's flat form by reading on to the next line break, so every
  -- group read the whole rest of the line. #1075's residual at WAIT UNTIL
  -- 30 prints as one such line of about 1.1 million characters, and spent
  -- 22 of its 23 seconds there.
  --
  -- Timed as in ConsiderScaleSpec: by a ratio, in CPU time, measured again
  -- when it is short of clearly quadratic. The same characters are printed
  -- both ways: one line of n groups, and 16 lines of n/16 groups each,
  -- whose line breaks stop the library's reading. So linear time gives a
  -- ratio of about 1 and the library's quadratic time about 16; the test
  -- fails at 4.
  it "prints one long line of groups in time linear in its length" $ do
    let n = 16000 :: Int
        groups is = [group (pretty i <> line <> "RAND") | i <- is]
        oneLine = hsep (groups [1 .. n])
        sixteenLines = vsepHard
          [hsep (groups [k * m + 1 .. (k + 1) * m]) | let m = n `div` 16, k <- [0 .. 15]]
        time d = do
          t0 <- getCPUTime
          len <- evaluate (Text.length (docText d))
          t1 <- getCPUTime
          pure (fromIntegral (t1 - t0) :: Double, len)
        fastest d tries = do
          rs <- traverse (const (time d)) [1 .. tries :: Int]
          pure (minimum (map fst rs), maximum (map snd rs))
    (short, lenShort) <- fastest sixteenLines 3
    let ratio long = long / max short 1.0e9
        settle tries = do
          (long, lenLong) <- time oneLine
          -- The same text either way, bar the 15 line breaks.
          lenLong `shouldBe` lenShort
          let r = ratio long
          if r < 4 || r >= 8 || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
    r <- settle 3
    r `shouldSatisfy` (< 4)

-- | 'vsep' with breaks 'group' cannot flatten, as L4.Print's 'vcatHard'.
vsepHard :: [Doc ann] -> Doc ann
vsepHard = concatWith (\ x y -> x <> hardline <> y)

-- | A document of about @n@ nodes, from prettyprinter's public combinators.
genDoc :: Int -> Gen (Doc Int)
genDoc n
  | n <= 1 = leaf
  | otherwise =
      frequency
        [ (2, leaf)
        , (4, (<>) <$> half <*> half)
        , (1, (<+>) <$> half <*> half)
        , (4, group <$> sub)
        , (1, nest <$> choose (-2, 4) <*> sub)
        , (3, align <$> sub)
        , (1, hang <$> choose (0, 4) <*> sub)
        , (1, indent <$> choose (0, 4) <*> sub)
        , (2, flatAlt <$> half <*> half)
        , (1, annotate <$> choose (0, 3) <*> sub)
        , (1, vsep <$> docs)
        , (1, sep <$> docs)
        , (1, fillSep <$> docs)
        , (1, fillCat <$> docs)
        , (1, vcat <$> docs)
        , (1, cat <$> docs)
        , (1, hsep <$> docs)
        , (1, (\ a b -> column \ c -> if even c then a else b) <$> half <*> half)
        , (1, (\ a b -> nesting \ i -> if even i then a else b) <$> half <*> half)
        , (1, (\ a b -> pageWidth \ w -> case w of Unbounded -> a; _ -> b) <$> half <*> half)
        , (1, fill <$> choose (0, 6) <*> sub)
        , (1, fillBreak <$> choose (0, 6) <*> sub)
        , (1, (\ a b -> width a \ w -> if even w then b else mempty) <$> half <*> half)
        , (1, fuse <$> elements [Shallow, Deep] <*> sub)
        , (1, unAnnotate <$> sub)
        , (1, encloseSep "[" "]" "," <$> docs)
        ]
  where
    sub = genDoc (n - 1)
    half = genDoc (n `div` 2)
    docs = do
      k <- choose (0, 4)
      vectorOf k (genDoc (n `div` max 1 k))

leaf :: Gen (Doc Int)
leaf =
  elements
    [ mempty, "a", "bc", "xyz", " ", "  "
    , line, line', softline, softline', hardline
    , pretty (12 :: Int), "(" <> line' <> ")"
    , pretty (Text.pack "two\nlines")
    ]
