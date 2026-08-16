-- | @l4 docassemble FILE@ — compile the decision-rule subset of an L4 file to
-- a docassemble interview (a single self-contained YAML a stock docassemble
-- server runs unmodified).
--
-- Selection, lowering and emission live in @jl4-core@
-- ('L4.Docassemble.Lower' / 'L4.Docassemble.Emit') so the CLI and any future
-- LSP/service surface share one implementation; this module only handles
-- option parsing, loading + type checking the file, writing the output, and
-- fidelity-report placement.
--
-- The fidelity discipline copies @l4 export@ ("L4.Cli.Export"): the report is
-- never optional — a one-line tally goes to stderr whenever anything was
-- lost, and the full report is written to a sibling @.fidelity.txt@ beside
-- @--output@, or to stderr when the interview goes to stdout. The exit code
-- is opt-in and graduated via @--fail-on=blocking|lossy|advisory|none@
-- (default @none@: a Blocking note describes the target notation's limits,
-- not a defect in this file).
module L4.Cli.Docassemble
  ( DocassembleOptions (..)
  , docassembleOptionsParser
  , docassembleCmd
  ) where

import Base
import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (replaceExtension)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Docassemble.Emit (renderPackage)
import L4.Docassemble.Lower (lowerModule, renderLowerError)
import L4.Interchange.Fidelity
  (FidelityNote (..), FidelityReport (..), FidelitySeverity (..), renderReport)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

-- | How severe a fidelity note has to be before the command exits non-zero.
data FidelityGate
  = GateNever
  | GateBlocking
  | GateLossy
  | GateAdvisory
  deriving stock (Eq, Show)

data DocassembleOptions = DocassembleOptions
  { daFile   :: FilePath
  , daOutput :: Maybe FilePath
  , daFailOn :: FidelityGate
  }

fidelityGateReader :: ReadM FidelityGate
fidelityGateReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "none"     -> Right GateNever
    "never"    -> Right GateNever
    "blocking" -> Right GateBlocking
    "lossy"    -> Right GateLossy
    "advisory" -> Right GateAdvisory
    "any"      -> Right GateAdvisory
    other      -> Left $
      "Invalid --fail-on: " <> Text.unpack other
        <> " (expected none|blocking|lossy|advisory)"

docassembleOptionsParser :: Parser DocassembleOptions
docassembleOptionsParser = DocassembleOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to compile to a docassemble interview")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the generated interview YAML to FILE instead of stdout \
                   \(the fidelity report then goes to FILE with a .fidelity.txt extension)"
            )
        )
  <*> option fidelityGateReader
        ( long "fail-on"
       <> metavar "SEVERITY"
       <> value GateNever
       <> showDefaultWith (const "none")
       <> help
            "Exit non-zero when the fidelity report holds a note this severe or worse: \
            \none|blocking|lossy|advisory. Default none, because Blocking describes \
            \what docassemble cannot express, not a defect in this file."
        )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

docassembleCmd :: DocassembleOptions -> IO ()
docassembleCmd opts = do
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig opts.daFile \nfp -> do
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
      case lowerModule tc.module' of
        Left lerrs -> do
          putDiagnostics
            ( "l4 docassemble: cannot compile this module to a docassemble interview:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right (pkg, report) -> do
          let out = renderPackage pkg
          case opts.daOutput of
            Just f  -> Text.writeFile f out
            Nothing -> Text.putStr out
          tripped <- reportFidelity opts report
          if tripped then exitFailure else exitSuccess

----------------------------------------------------------------------------
-- Fidelity placement (the L4.Cli.Export discipline)
----------------------------------------------------------------------------

-- | @interview.yml@ → @interview.fidelity.txt@, matching the golden-pair
-- shape of the DMN/BPMN exhibits.
fidelitySibling :: FilePath -> FilePath
fidelitySibling f = replaceExtension f ".fidelity.txt"

-- | Tally, report, gate. Returns 'True' when @--fail-on@ says this export
-- should exit non-zero.
reportFidelity :: DocassembleOptions -> FidelityReport -> IO Bool
reportFidelity opts report = do
  let ns = report.notes
      countOf s = length [() | n <- ns, n.severity == s]
      tally = Text.intercalate ", "
        [ Text.pack (show c) <> " " <> label
        | (c, label) <-
            [ (countOf Blocking, "blocking")
            , (countOf Lossy,    "lossy")
            , (countOf Advisory, "advisory")
            ]
        , c > 0
        ]

  -- (1) The tally is unconditional: the export never silently drops what the
  --     source said, whether or not the caller knew to ask.
  unless (null ns) $
    hPutStrLn stderr . Text.unpack $
      "l4 docassemble: docassemble could not carry everything this module says — " <> tally

  -- (2) The full report, always, as its own artifact: a sidecar beside
  --     --output, stderr otherwise.
  let rendered = renderReport report
  case opts.daOutput of
    Just f -> do
      let sidecar = fidelitySibling f
      Text.writeFile sidecar rendered
      hPutStrLn stderr ("l4 docassemble: fidelity report written to " <> sidecar)
    Nothing -> Text.hPutStr stderr rendered

  pure (tripsGate opts.daFailOn ns)

-- | 'FidelitySeverity' derives 'Ord' in declaration order, so @Blocking <
-- Lossy < Advisory@: \"at least this severe\" is @<=@ the threshold.
tripsGate :: FidelityGate -> [FidelityNote] -> Bool
tripsGate gate ns = case threshold of
  Nothing -> False
  Just t  -> any (\n -> n.severity <= t) ns
 where
  threshold = case gate of
    GateNever    -> Nothing
    GateBlocking -> Just Blocking
    GateLossy    -> Just Lossy
    GateAdvisory -> Just Advisory
