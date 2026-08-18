-- | @l4 blawx FILE@ — compile the decision-rule subset of an L4 file to a
-- Blawx project: an import-shaped @.blawx@ fixture stream plus a sibling
-- @.pl@ dump of the concatenated s(CASP) (BLAWX-EXPORT-SPEC R1).
--
-- Selection and relationalization live in the shared middle-end
-- ('L4.Relational.Lower'); classification and emission live in
-- @jl4-core@ ('L4.Blawx.Lower' / 'L4.Blawx.Emit') so the CLI and any future
-- LSP/service surface share one implementation; this module only handles
-- option parsing, loading + type checking the file, and writing the output.
--
-- Output placement: with @--output FILE@ the @.blawx@ YAML goes to FILE and
-- the s(CASP) dump to FILE with a @.pl@ extension; without it the YAML goes
-- to stdout (a sibling of stdout does not exist, so no @.pl@ is written).
-- @--scasp@ selects the s(CASP) dump instead of the YAML, to stdout or
-- @--output@. A YAML destination that itself ends @.pl@ is refused — it
-- would be its own sibling, and the dump would clobber the YAML.
module L4.Cli.Blawx
  ( BlawxOptions(..)
  , blawxOptionsParser
  , blawxCmd
  ) where

import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (replaceExtension, takeExtension, takeFileName)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Blawx.Emit (renderBlawxYaml, renderPlDump)
import L4.Blawx.Lower (lowerBlawx)
import L4.Relational.IR (renderLowerError)
import L4.Relational.Lower (defaultLowerOptions, lowerModule)

import L4.Cli.Common

data BlawxOptions = BlawxOptions
  { bxFile   :: FilePath
  , bxOutput :: Maybe FilePath
  , bxScasp  :: Bool
  }

blawxOptionsParser :: Parser BlawxOptions
blawxOptionsParser = BlawxOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to compile to a Blawx project")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the .blawx YAML to FILE (plus the s(CASP) dump to FILE \
                   \with a .pl extension) instead of stdout"
            )
        )
  <*> switch
        ( long "scasp"
       <> help "Emit the concatenated s(CASP) dump instead of the .blawx YAML"
        )

blawxCmd :: BlawxOptions -> IO ()
blawxCmd opts = do
  -- A .blawx destination named *.pl would be its own sibling dump path
  -- (replaceExtension is a fixed point there), so the YAML would be written
  -- and immediately overwritten. Refuse up front rather than clobber.
  case opts.bxOutput of
    Just f | not opts.bxScasp, takeExtension f == ".pl" -> do
      hPutStrLn stderr
        ( "l4 blawx: -o " <> f <> " without --scasp would overwrite the .blawx \
          \YAML with its own sibling s(CASP) dump; pass --scasp for the dump, \
          \or choose a non-.pl output path" )
      exitFailure
    _ -> pure ()
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig opts.bxFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      -- Surface non-fatal diagnostics, but proceed: a clean type-check is the
      -- precondition that matters for lowering (the `l4 openfisca` posture).
      putDiagnostics errs
      case lowerModule defaultLowerOptions tc.entityInfo tc.module'
             >>= lowerBlawx of
        Left lerrs -> do
          putDiagnostics
            ( "l4 blawx: cannot compile these decisions to Blawx:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right doc -> do
          let source = Text.pack (takeFileName opts.bxFile)
              plDump = renderPlDump source doc
          if opts.bxScasp
            then case opts.bxOutput of
              Just f  -> Text.writeFile f plDump
              Nothing -> Text.putStr plDump
            else do
              let yaml = renderBlawxYaml doc
              case opts.bxOutput of
                Just f -> do
                  Text.writeFile f yaml
                  let sibling = replaceExtension f ".pl"
                  Text.writeFile sibling plDump
                  hPutStrLn stderr ("l4 blawx: s(CASP) dump written to " <> sibling)
                Nothing -> Text.putStr yaml
          exitSuccess
