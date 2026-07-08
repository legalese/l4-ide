-- | @l4 openfisca FILE@ — compile the decision-rule subset of an L4 file to a
-- runnable OpenFisca Python module.
--
-- Selection, lowering and emission live in @jl4-core@ ('L4.OpenFisca.Lower' /
-- 'L4.OpenFisca.Emit') so the CLI and any future LSP/service surface share one
-- implementation; this module only handles option parsing, loading + type
-- checking the file, and writing the output.
module L4.Cli.OpenFisca
  ( OpenFiscaOptions(..)
  , openFiscaOptionsParser
  , openFiscaCmd
  ) where

import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.OpenFisca.Emit (renderPackage)
import L4.OpenFisca.Lower (lowerModule, renderLowerError)

import L4.Cli.Common

data OpenFiscaOptions = OpenFiscaOptions
  { ofFile     :: FilePath
  , ofOutput   :: Maybe FilePath
  , ofFixedNow :: FixedNowOpt
  }

openFiscaOptionsParser :: Parser OpenFiscaOptions
openFiscaOptionsParser = OpenFiscaOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to compile to OpenFisca")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the generated Python to FILE instead of stdout"
            )
        )
  <*> fixedNowParser

openFiscaCmd :: OpenFiscaOptions -> IO ()
openFiscaCmd opts = do
  evalConfig <- makeEvalConfig opts.ofFixedNow
  (errs, mTc) <- runOneshot evalConfig opts.ofFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      -- Surface non-fatal diagnostics, but proceed: a clean type-check is the
      -- precondition that matters for lowering.
      putDiagnostics errs
      case lowerModule tc.module' of
        Left lerrs -> do
          putDiagnostics
            ( "l4 openfisca: cannot compile these decisions to OpenFisca:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right pkg -> do
          let out = renderPackage pkg
          case opts.ofOutput of
            Just f  -> Text.writeFile f out
            Nothing -> Text.putStr out
          exitSuccess
