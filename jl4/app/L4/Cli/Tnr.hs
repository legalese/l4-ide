-- | @l4 tnr FILE@ — render an L4 module as legislative-style prose
-- (the \"Times New Roman\" version), in Markdown.
--
-- Phase 1 of @specs/todo/NLG-TNR-ROUNDTRIP-SPEC.md@. Output goes to stdout;
-- hidden HTML-comment anchors tie each provision back to its L4 node for
-- the future round-trip ingestion path (disable with @--no-anchors@).
module L4.Cli.Tnr
  ( TnrCliOptions(..)
  , tnrOptionsParser
  , tnrCmd
  ) where

import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import qualified L4.TNR as TNR

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data TnrCliOptions = TnrCliOptions
  { tnrFile      :: FilePath
  , tnrNoAnchors :: Bool
  , tnrFixedNow  :: FixedNowOpt
  }

tnrOptionsParser :: Parser TnrCliOptions
tnrOptionsParser = TnrCliOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to render")
  <*> switch (long "no-anchors" <> help "Suppress the hidden per-provision anchor comments used for round-tripping")
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

tnrCmd :: TnrCliOptions -> IO ()
tnrCmd opts = do
  evalConfig <- makeEvalConfig opts.tnrFixedNow
  (errs, mTc) <- runOneshot evalConfig opts.tnrFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Just tc | tc.success ->
      Text.putStr $
        TNR.renderModuleTnr
          TNR.MkTnrOptions{TNR.anchors = not opts.tnrNoAnchors}
          tc.module'
    _ -> do
      putDiagnostics errs
      Text.hPutStrLn stderr "tnr: file did not typecheck; cannot render"
      exitFailure
