{-# LANGUAGE LambdaCase, OverloadedRecordDot #-}
-- | 'cosmosExpr' against what it replaces, and the passes that skip a term they
-- cannot change against the passes they skip, on every rule of the corpus.
--
-- 'cosmosExpr' stands in for @cosmosOf (gplate \@(Expr Resolved))@ on the paths
-- that key and draw a leaf, and an atomId depends on the order it visits in (the
-- decode types of a key are collected in traversal order), so it must visit the
-- same expressions in the same order, not merely as many.
module CosmosExprSpec (spec) where

import Optics (cosmosOf, gplate, toListOf)
import Test.Hspec

import L4.Syntax (Decide (..), Expr (..), Resolved, cosmosExpr, foldTopLevelDecides)
import qualified L4.Transform as Transform
import L4.Viz.AtomKey (inlinedSize)
import LSP.L4.Rules (TypeCheckResult (..))

import CorpusSweep (checkAll, corpus)

-- | The body of every rule of the corpus.
bodies :: IO [Expr Resolved]
bodies = do
  files <- corpus ["../jl4/examples/ok", "../jl4/examples/legal"]
  checked <- checkAll files
  pure [b | (_, _, tc) <- checked, MkDecide _ _ _ b <- foldTopLevelDecides (\d -> [d]) tc.module']

spec :: Spec
spec = beforeAll bodies do
  describe "cosmosExpr" do
    it "visits the same expressions in the same order as cosmosOf over gplate, in every rule of the corpus" \rules -> do
      let walks = map (toListOf cosmosExpr) rules
      -- enough of them that agreeing is not an accident of what was left out
      length rules `shouldSatisfy` (> 500)
      sum (map length walks) `shouldSatisfy` (> 10000)
      [i | (i, b, w) <- zip3 [0 :: Int ..] rules walks, w /= toListOf (cosmosOf (gplate @(Expr Resolved))) b] `shouldBe` []

  -- The passes that put locals in rewrite a WHERE or a LET and nothing else, so
  -- 'Transform.inlineLocalBindings' returns a term with neither as it is. For a
  -- term with one it must still do what it did, which was both passes, always.
  describe "inlineLocalBindings" do
    it "gives what both of its passes give, in every rule of the corpus" \rules -> do
      -- A drafter's chain of locals that each name the one before twice is
      -- exponential once put in, in either order of passes; those are left out.
      let small = filter ((< 2000) . inlinedSize) rules
          reference = Transform.inlineLocalBindingsWhere (const True) . Transform.inlineGeneratedLets
          hasScope b = not (null [() | e <- toListOf cosmosExpr b, isScope e])
          isScope = \case
            Where {} -> True
            LetIn {} -> True
            _ -> False
      -- some of the rules have locals, so that agreeing is more than agreeing on the identity
      length (filter hasScope small) `shouldSatisfy` (> 30)
      [i | (i, b) <- zip [0 :: Int ..] small, Transform.inlineLocalBindings b /= reference b] `shouldBe` []
