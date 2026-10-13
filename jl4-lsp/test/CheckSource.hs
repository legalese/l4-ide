{-# LANGUAGE OverloadedRecordDot, PatternSynonyms, TupleSections #-}
-- | Type-check a source text the way the language server does, and return the
-- checked module with the identifier of its document.
module CheckSource (checkSource) where

import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath (takeDirectory, (</>))

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult, pattern TypeCheck)

-- | Check @source@ as a file called @stem.l4@. Two sources checked under different
-- stems are two documents (two URIs), as two files are.
checkSource :: String -> T.Text -> IO (VersionedTextDocumentIdentifier, TypeCheckResult)
checkSource stem source = do
  tmp <- getTemporaryDirectory
  let path = tmp </> "jl4-lsp-test-check-source" </> (stem <> ".l4")
  createDirectoryIfMissing True (takeDirectory path)
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mRes) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure $ fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc
  maybe (fail ("fixture " <> stem <> " did not type-check")) pure mRes
