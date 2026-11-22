{-# LANGUAGE OverloadedRecordDot, PatternSynonyms, TupleSections #-}
-- | Type-check many corpus files in one language-server session, for the specs that
-- sweep the corpus.
module CorpusSweep (corpus, checkAll) where

import Control.Monad (forM)
import Data.List (sort)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri, toNormalizedFilePath)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)

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

-- | Each file, type-checked, with the document id the ladder wants; the files that
-- did not type-check are left out.
checkAll :: [FilePath] -> IO [(FilePath, VersionedTextDocumentIdentifier, TypeCheckResult)]
checkAll files = case files of
  [] -> pure []
  firstFile : _ -> do
    evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
    (_, results) <- oneshotL4ActionAndErrors evalConfig firstFile \_ ->
      forM files \f -> do
        let nfp = toNormalizedFilePath f
            uri = normalizedFilePathToUri nfp
        _ <- Shake.addVirtualFileFromFS nfp
        mTc <- Shake.use TypeCheck uri
        pure (f, fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc)
    pure [(f, verId, tc) | (f, Just (verId, tc)) <- results, tc.success]
