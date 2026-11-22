-- | @l4 format FILE@ — print an L4 file back to stdout exactly as written.
--
-- The output is the exact-print of the parsed file ("L4.ExactPrint"): the
-- file's own layout, comments, spelling of every literal and line endings.
-- Exits 0 when the file parses, and 1 with the parse errors on stderr when it
-- does not.
module L4.Cli.Format
  ( FormatOptions(..)
  , formatOptionsParser
  , formatCmd
  ) where

import Control.Monad.IO.Class (liftIO)
import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (IOMode (ReadMode), hSetEncoding, hSetNewlineMode, noNewlineTranslation, stdout, utf8, withFile)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (fromNormalizedFilePath, normalizedFilePathToUri)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

newtype FormatOptions = FormatOptions
  { formatFile :: FilePath
  }

formatOptionsParser :: Parser FormatOptions
formatOptionsParser = FormatOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to print")

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

formatCmd :: FormatOptions -> IO ()
formatCmd opts = do
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mEp) <- runOneshot evalConfig opts.formatFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    -- Not 'Shake.addVirtualFileFromFS': it reads in text mode, which on
    -- Windows turns every CRLF into LF.
    src <- liftIO $ readFileAsWritten (fromNormalizedFilePath nfp)
    _ <- Shake.addVirtualFile nfp src
    Shake.use Rules.ExactPrint uri

  case mEp of
    Just ep -> do
      -- In text mode, stdout on Windows writes every LF as CRLF.
      hSetNewlineMode stdout noNewlineTranslation
      Text.putStr ep
      exitSuccess
    Nothing -> do
      putDiagnostics errs
      exitFailure

-- | Read a UTF-8 file with its line endings as they are on disk.
readFileAsWritten :: FilePath -> IO Text.Text
readFileAsWritten path = withFile path ReadMode \h -> do
  hSetEncoding h utf8
  hSetNewlineMode h noNewlineTranslation
  Text.hGetContents h
