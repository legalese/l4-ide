{-# LANGUAGE OverloadedRecordDot, OverloadedStrings, PatternSynonyms, TupleSections #-}
-- | The size of a leaf with its locals put in ('AtomKey.inlinedSize'), against the
-- size 'Transform.inlineLocalBindings' actually leaves, over the corpus.
--
-- The estimate is what decides whether a leaf is keyed by the 'show' of its term or
-- by a digest of it, so it has to be the size of what the real pass leaves. Hand-built
-- shapes are in jl4-core's @AtomKeySpec@; this is every rule in the corpus, the ones
-- with a WHERE or a LET among them.
module AtomKeySizeSpec (spec) where

import Control.Monad (filterM, forM)
import Data.List (sort)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Optics (anyOf, cosmosOf, gplate, lengthOf)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri, toNormalizedFilePath)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Syntax (Decide (..), Expr (..), Resolved, foldTopLevelDecides)
import L4.TracePolicy (lspDefaultPolicy)
import qualified L4.Transform as Transform
import L4.Viz.AtomKey (digestThreshold, inlinedSize)
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)
import qualified LSP.L4.Viz.Ladder as Ladder

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
    firstFile <- case files of
      f : _ -> pure f
      [] -> fail "no corpus found"
    evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
    (_, results) <- oneshotL4ActionAndErrors evalConfig firstFile \_ ->
      forM files \f -> do
        let nfp = toNormalizedFilePath f
            uri = normalizedFilePathToUri nfp
        _ <- Shake.addVirtualFileFromFS nfp
        mTc <- Shake.use TypeCheck uri
        pure (f, fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc)
    -- The rules the ladder can draw, which are the boolean ones: only their leaves
    -- are keyed. (A rule with a literal clause, `DECIDE f 0 IS "zero"`, has a body
    -- that does not survive being walked whole, and nothing keys it.)
    let bodies =
          [ (f, body)
          | (f, Just (verId, tc)) <- results
          , tc.success
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

-- | Every @.l4@ file under the given directories, recursively.
corpus :: [FilePath] -> IO [FilePath]
corpus roots = concat <$> mapM walk roots
  where
    walk dir = do
      exists <- doesDirectoryExist dir
      if not exists
        then pure []
        else do
          entries <- sort <$> listDirectory dir
          concat <$> forM entries \e -> do
            let p = dir </> e
            isDir <- doesDirectoryExist p
            if isDir then walk p else pure [p | takeExtension p == ".l4"]
