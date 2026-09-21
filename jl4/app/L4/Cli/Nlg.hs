-- | @l4 nlg FILE@ — linearize a module's directives to natural-language prose.
--
-- This is the CLI footing for the TNR/NLG round-trip leg. It is deliberately a
-- thin wrapper: the renderer is 'L4.Nlg.simpleLinearizer' in @jl4-core@, and
-- the payload is exactly what @jl4-test@'s @jl4NlgAnnotationsGolden@ writes into
-- @\<stem\>.nlg.golden@ —
--
-- @
-- Text.unlines (fmap Nlg.simpleLinearizer (toListOf (gplate \@(Directive Resolved)) mod'))
-- @
--
-- Sameness with the golden producer is the whole point of the command, and it is
-- load-bearing rather than incidental: before this existed, the only way to
-- regenerate an @.nlg.golden@ was @cabal test jl4:jl4-test@, which the @go@
-- orchestrator will not run (it never invokes cabal — the build lock is a shared
-- resource). That is why @etc\/go\/phases\/p7-tnr.sh@ could only ever report
-- @NOT-REGENERATED@. With this command the leg gets a real differential oracle:
-- regenerate, then diff against the committed golden.
--
-- So: if you change the payload expression below, you have moved @p7-tnr@ off
-- its golden and broken @jl4-test@ at the same time. Change both, in one commit,
-- or neither.
--
-- @--lang@ does not breach that. 'L4.Nlg.selectLanguage' 'Nothing' is the
-- identity, so the no-flag payload is byte-identical to the golden producer's
-- and stays that way by construction; the flag only moves an already-attached
-- rendering into the slot the payload already reads. Producing a bilingual
-- document SET is then two runs of this command differing in one argument,
-- which is the point of the flag.
--
-- Two post-processing steps the golden producer applies are deliberately NOT
-- applied here, because on this payload both are the identity:
--
--   * @stripAnsiCodes@ — the linearizer emits no escape sequences;
--   * @normalizeWhitespace@ — it rewrites only lines beginning @File:@,
--     @Hidden:@, @Range:@, @Source:@, @Severity:@, @Code:@ or @Message:@, which
--     are diagnostic labels and never appear in linearized prose.
--
-- The golden producer also appends a rendered-diagnostics block when the module
-- does /not/ typecheck. This command instead exits 1 with the diagnostics on
-- stderr and writes nothing, because a CLI that prints prose for a broken module
-- is a CLI that gets used to regenerate a golden from a broken module.
module L4.Cli.Nlg
  ( NlgOptions(..)
  , nlgOptionsParser
  , nlgCmd
  ) where

import Base
import qualified Base.Text as Text
import qualified Optics
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Lexer (LangTag (..))
import qualified L4.Nlg as Nlg
import L4.Syntax

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data NlgOptions = NlgOptions
  { nlgFile     :: FilePath
  , nlgOutput   :: Maybe FilePath
  , nlgLang     :: Maybe LangTag
  , nlgFixedNow :: FixedNowOpt
  }

nlgOptionsParser :: Parser NlgOptions
nlgOptionsParser = NlgOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to linearize")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write to FILE instead of stdout"
            )
        )
  <*> langOption "node"
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

nlgCmd :: NlgOptions -> IO ()
nlgCmd opts = do
  evalConfig <- makeEvalConfig opts.nlgFixedNow
  (errs, mTc) <- runOneshot evalConfig opts.nlgFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      putDiagnostics errs
      case opts.nlgOutput of
        Just f  -> Text.writeFile f (linearizeModule opts.nlgLang tc.module')
        Nothing -> Text.putStr (linearizeModule opts.nlgLang tc.module')
      exitSuccess

-- | The payload. Byte-identical to @jl4NlgAnnotationsGolden@'s @output_@ when
-- no language is requested — 'Nlg.selectLanguage' 'Nothing' is the identity,
-- so that holds by construction rather than by care.
linearizeModule :: Maybe LangTag -> Module Resolved -> Text
linearizeModule mlang mod'' =
  Text.unlines (fmap Nlg.simpleLinearizer directives)
  where
    mod' = Nlg.selectLanguage mlang mod''
    directives = Optics.toListOf (Optics.gplate @(Directive Resolved)) mod'
