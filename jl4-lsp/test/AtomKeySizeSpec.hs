{-# LANGUAGE OverloadedRecordDot, OverloadedStrings #-}
-- | The size of a leaf with its locals put in ('AtomKey.inlinedSize'), against the
-- size 'Transform.inlineLocalBindings' actually leaves, over the corpus.
--
-- The estimate is what decides whether a leaf is keyed by the 'show' of its term or
-- by a digest of it, so it has to be the size of what the real pass leaves. Hand-built
-- shapes are in jl4-core's @AtomKeySpec@; this is every rule in the corpus, the ones
-- with a WHERE or a LET among them.
module AtomKeySizeSpec (spec) where

import Control.Monad (filterM)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Optics (anyOf, cosmosOf, gplate, lengthOf)

import L4.Syntax (Decide (..), Expr (..), Resolved, foldTopLevelDecides)
import qualified L4.Transform as Transform
import L4.Viz.AtomKey (digestThreshold, inlinedSize)
import LSP.L4.Rules (TypeCheckResult (..))
import qualified LSP.L4.Viz.Ladder as Ladder

import CorpusSweep (checkAll, corpus)
import Test.Hspec

spec :: Spec
spec = describe "the size of a leaf, locals put in" $ do
  -- The estimate is what decides, so it has to be the size of what the real pass
  -- leaves. Hand-built shapes are in jl4-core's AtomKeySpec; this is every rule in
  -- the corpus, the ones with a WHERE or a LET among them.
  it "across the corpus, the estimated size of every rule's body is the size inlineLocalBindings leaves" $ do
    -- Only a file that says WHERE or LET can have a local, so only those are
    -- checked. canon is not in this list because checking it takes a minute; it
    -- agreed too, when it was added to this list and run once (2026-10-12), and it
    -- is where most of the corpus's leaves with a local are.
    everything <- corpus ["../jl4/examples/ok", "../jl4/examples/legal"]
    files <- filterM (fmap (\t -> "WHERE" `T.isInfixOf` t || "LET " `T.isInfixOf` t) . T.readFile) everything
    length files `shouldSatisfy` (> 30)
    checked <- checkAll files
    -- The rules the ladder can draw, which are the boolean ones: only their leaves
    -- are keyed. (A rule with a literal clause, `DECIDE f 0 IS "zero"`, has a body
    -- that does not survive being walked whole, and nothing keys it.)
    let bodies =
          [ (f, body)
          | (f, verId, tc) <- checked
          , let cfg = Ladder.mkVizConfig verId tc.module' tc.substitution False
          , d@(MkDecide _ _ _ body) <- foldTopLevelDecides (\d' -> [d']) tc.module'
          , Right _ <- [Ladder.doVisualize d cfg]
          ]
        truth :: Expr Resolved -> Int
        truth = lengthOf (cosmosOf (gplate @(Expr Resolved))) . Transform.inlineLocalBindings
        hasScope = \case
          Where {} -> True
          LetIn {} -> True
          _ -> False
        -- the real pass is exponential on a chain of locals, which is what the estimate
        -- is for: only compare where the estimate says it is small
        problems = [(f, e, truth body) | (f, body) <- bodies, let e = inlinedSize body, e <= digestThreshold, e /= truth body]
    length bodies `shouldSatisfy` (> 50)
    -- the sweep is only worth something if locals are in it
    length [() | (_, body) <- bodies, anyOf (cosmosOf (gplate @(Expr Resolved))) hasScope body] `shouldSatisfy` (> 10)
    take 10 problems `shouldBe` []
