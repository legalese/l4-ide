{-# LANGUAGE OverloadedRecordDot, OverloadedStrings #-}
-- | The digest key ("L4.Viz.AtomKey", R3c) through the ladder and over the corpus.
--
-- Three things. The corpus never reaches the digest (its largest leaf is 313 nodes
-- and the threshold is 2,048), so no id there changes, and no text key can be
-- mistaken for a digest. Where a digest IS forced onto the corpus (threshold 0) it
-- sorts the terms into exactly the classes the text key does, which is the
-- evidence that it identifies the same trees. And a drafter's @LET@ and the text
-- written out are one atom at any size.
module AtomKeySweepSpec (spec) where

import Control.Monad (filterM)
import Data.Char (isAsciiUpper)
import qualified Data.IntMap.Strict as IntMap
import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Optics (cosmosOf, gplate, toListOf)
import System.Timeout (timeout)

import L4.Syntax (Decide (..), Expr (..), Resolved, foldTopLevelDecides)
import L4.Viz.AtomKey (digestKey, digestPrefix, digestThreshold, textKey)
import qualified L4.Viz.VizExpr as V
import LSP.L4.Rules (TypeCheckResult (..))
import qualified LSP.L4.Viz.Ladder as Ladder

import CheckSource (checkSource)
import CorpusSweep (checkAll, corpus)
import Test.Hspec

-- | Every leaf of a drawing, as its label and its atomId.
leaves :: V.IRExpr -> [(T.Text, T.Text)]
leaves = \case
  V.And _ xs -> concatMap leaves xs
  V.Or _ xs -> concatMap leaves xs
  V.Not _ x -> leaves x
  V.Implies _ p q _ -> leaves p <> leaves q
  V.UBoolVar _ nm _ _ a _ _ -> [(nm.label, a)]
  V.App _ nm args a _ -> (nm.label, a) : concatMap leaves args
  _ -> []

draw :: String -> T.Text -> IO (V.FunDecl, Ladder.VizState)
draw stem source = do
  (verId, tc) <- checkSource stem source
  let cfg = Ladder.mkVizConfig verId tc.module' tc.substitution False
  case foldTopLevelDecides (\d -> [d]) tc.module' of
    [d] -> case Ladder.doVisualize d cfg of
      Right (info, st) -> pure (info.funDecl, st)
      Left err -> fail ("could not draw: " <> T.unpack (Ladder.prettyPrintVizError err))
    other -> fail ("expected one rule, found " <> show (length other))

-- | @LET a0 BE x IN LET a1 BE a0 AND y OR a0 IN ... a(n-1)@: each local names the one
-- before it twice, so what it means doubles with each and the source does not.
doublingChain :: Int -> T.Text
doublingChain n =
  T.unlines $
    [ "GIVEN x IS A BOOLEAN"
    , "      y IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "DECIDE chain x y IS"
    , "  LET a0 BE x"
    , "  IN"
    ]
      <> concat
        [ [indent i <> "LET a" <> name i <> " BE a" <> name (i - 1) <> " AND y OR a" <> name (i - 1), indent i <> "IN"]
        | i <- [1 .. n - 1]
        ]
      <> [indent n <> "a" <> name (n - 1)]
  where
    indent i = T.replicate (2 + i) " "
    name = T.pack . show

-- | A rule with a LET (or a WHERE local) that names a sum of @k@ numbers, and the
-- same sum written out again beside it. The sum has 2k + 3 nodes.
bigLocal :: String -> Int -> T.Text
bigLocal how k =
  T.unlines $
    [ "GIVEN x IS A NUMBER"
    , "      ok IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    ]
      <> case how of
        "let" ->
          [ "DECIDE `big let` x ok IF"
          , "  (LET big BE " <> sumOf <> " > 0 IN big) AND ok AND NOT " <> sumOf <> " > 0"
          ]
        _ ->
          [ "DECIDE `big where` x ok IF"
          , "        big AND ok AND NOT " <> sumOf <> " > 0"
          , "    WHERE"
          , "        big MEANS " <> sumOf <> " > 0"
          ]
  where
    sumOf = T.intercalate " + " ("x" : [T.pack (show i) | i <- [1 .. k]])

spec :: Spec
spec = describe "the digest key, through the ladder and across the corpus" $ do
  it "no leaf key of the corpus is a digest, and every one begins as a text key does" $ do
    files <- corpus ["../jl4/examples/ok", "../jl4/examples/legal"]
    length files `shouldSatisfy` (> 100)
    checked <- checkAll files
    let keys =
          [ k
          | (_, verId, tc) <- checked
          , let cfg = Ladder.withCallExpansions (Ladder.mkVizConfig verId tc.module' tc.substitution False)
          , d <- foldTopLevelDecides (\d' -> [d']) tc.module'
          , Right (_, st) <- [Ladder.doVisualize d cfg]
          , k <- IntMap.elems (Ladder.getLeafKeys st)
          ]
        -- a leaf key may carry the suffix of a per-occurrence leaf; its head is the term's
        isDigest k = digestPrefix `T.isPrefixOf` k
        beginsLikeText k = maybe False (isAsciiUpper . fst) (T.uncons k)
    length keys `shouldSatisfy` (> 500)
    take 5 (filter isDigest keys) `shouldBe` []
    take 5 (filter (not . beginsLikeText) keys) `shouldBe` []

  it "forced onto the corpus, the digest sorts terms into the classes the text key does" $ do
    everything <- corpus ["../jl4/examples/ok", "../jl4/examples/legal"]
    files <- filterM (fmap (\t -> "WHERE" `T.isInfixOf` t || "LET " `T.isInfixOf` t) . T.readFile) everything
    checked <- checkAll files
    let terms =
          [ (textKey env t, fmap fst (digestKey env t), hasScope t)
          | (_, verId, tc) <- checked
          , let cfg = Ladder.mkVizConfig verId tc.module' tc.substitution False
          , d@(MkDecide _ _ _ body) <- foldTopLevelDecides (\d' -> [d']) tc.module'
          , Right (_, st) <- [Ladder.doVisualize d cfg]
          , let env = Ladder.getKeyEnv st
          , t <- toListOf (cosmosOf (gplate @(Expr Resolved))) body
          ]
        hasScope = \case
          Where {} -> True
          LetIn {} -> True
          _ -> False
        digested = [(tk, dk) | (tk, Just dk, _) <- terms]
        classes f = Map.fromListWith (<>) [(a, [b]) | (a, b) <- f]
        splitsText = [k | (k, ds) <- Map.toList (classes digested), length (nub ds) > 1]
        splitsDigest = [k | (k, ts) <- Map.toList (classes [(dk, tk) | (tk, dk) <- digested]), length (nub ts) > 1]
    -- worth something only if it digested a lot, and terms with locals among them
    length digested `shouldSatisfy` (> 1000)
    length [() | (_, Just _, True) <- terms] `shouldSatisfy` (> 5)
    length splitsText `shouldBe` 0
    length splitsDigest `shouldBe` 0
    -- and it was the digest: every one of them begins with the prefix
    all (T.isPrefixOf digestPrefix . snd) digested `shouldBe` True

  it "a drafter's LET, or WHERE local, and the same text written out are one atom, over the threshold too" $ do
    -- a sum of 1,100 numbers has 2,203 nodes, past the threshold of 2,048
    let k = digestThreshold `div` 2 + 76
    mapM_
      ( \how -> do
          (fd, st) <- draw ("digest-" <> how) (bigLocal how k)
          let ids = map snd (leaves fd.body)
          case ids of
            [local, other, written] -> do
              local `shouldBe` written
              local `shouldNotBe` other
            _ -> expectationFailure ("expected three leaves, found " <> show (map fst (leaves fd.body)))
          -- and the local's key is a digest, so the equality is the digest's
          let keys = IntMap.elems (Ladder.getLeafKeys st)
          length (filter (T.isPrefixOf digestPrefix) keys) `shouldSatisfy` (>= 2)
      )
      ["let", "where"]

  it "a chain of 20 doubling LETs is drawn, and keyed by a digest the length of a hash" $ do
    r <- timeout 120000000 (draw "digest-chain-20" (doublingChain 20))
    (fd, st) <- maybe (fail "drawing a chain of 20 LETs did not finish in 120 s") pure r
    length (leaves fd.body) `shouldBe` 1
    let keys = IntMap.elems (Ladder.getLeafKeys st)
    length keys `shouldBe` 1
    map T.length keys `shouldBe` [T.length digestPrefix + 40]
    all (T.isPrefixOf digestPrefix) keys `shouldBe` True
