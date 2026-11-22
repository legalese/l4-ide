-- | @l4 export yscript FILE@ — compile the pure-propositional-logic fragment of an
-- L4 module to AustLII DataLex's @yscript@ rule language.
--
-- One-way only (no import), and all-or-nothing (R5, spec §5): selection and
-- lowering live in @jl4-core@ ('L4.Yscript.Lower' \/ 'L4.Yscript.Emit') so the
-- CLI only handles option parsing, loading + type checking the file, and
-- writing the output. Unlike @l4 export docassemble@\/@l4 export@ there is no
-- fidelity report and no @--fail-on@ severity ladder to gate on — a refusal
-- here means the module could not be compiled at all, not that something was
-- carried with degraded fidelity, so the only outcomes are "wrote the file"
-- (exit 0) and "wrote nothing, said why" (exit non-zero).
module L4.Cli.Yscript
  ( YscriptOptions (..)
  , yscriptOptionsParser
  , yscriptCmd
  ) where

import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Yscript.Emit (renderYscript)
import L4.Yscript.Lower (lowerModule, renderLowerError)

import L4.Cli.Common

data YscriptOptions = YscriptOptions
  { ysFile   :: FilePath
  , ysOutput :: Maybe FilePath
  }

yscriptOptionsParser :: Parser YscriptOptions
yscriptOptionsParser = YscriptOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to compile to yscript")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the generated yscript source to FILE instead of stdout"
            )
        )

yscriptCmd :: YscriptOptions -> IO ()
yscriptCmd opts = do
  -- yscript has no NOW/TODAY-sensitive constructs in its exportable fragment
  -- (R1/R2: pure propositional logic), so there is no --fixed-now to plumb.
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig opts.ysFile \nfp -> do
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
            ( "l4 export yscript: cannot compile this module to yscript:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right rules -> do
          let out = renderYscript rules
          case opts.ysOutput of
            Just f  -> Text.writeFile f out
            Nothing -> Text.putStr out
          exitSuccess
