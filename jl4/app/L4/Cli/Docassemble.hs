-- | @l4 docassemble FILE@ — compile the decision-rule subset of an L4 file to
-- a docassemble interview (a single self-contained YAML a stock docassemble
-- server runs unmodified), or, with @--package DIR@, to an installable
-- docassemble package tree (R11, M2).
--
-- Selection, lowering and emission live in @jl4-core@
-- ('L4.Docassemble.Lower' / 'L4.Docassemble.Emit') so the CLI and any future
-- LSP/service surface share one implementation; this module only handles
-- option parsing, loading + type checking the file, writing the output, and
-- fidelity-report placement. The package tree's /layout/ is decided in
-- jl4-core too ('L4.Docassemble.Emit.renderPackageTree'); what is left here is
-- putting bytes on disk — including copying the @.l4@ source rather than
-- re-encoding its text, because provenance means the bytes.
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
import qualified Data.Text.IO as TextIO
import Options.Applicative
import System.Directory
  (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (joinPath, replaceExtension, takeDirectory, takeFileName, (</>))

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Docassemble.Emit (renderPackage, renderPackageTree)
import L4.Docassemble.IR (DAFile (..), DAPackage, DAPackageTree (..))
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
  { daFile    :: FilePath
  , daOutput  :: Maybe FilePath
  , daPackage :: Maybe FilePath
  , daFailOn  :: FidelityGate
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
  <*> optional
        ( strOption
            ( long "package"
           <> metavar "DIR"
           <> help "Write an installable docassemble package tree (PEP 420 shape) into \
                   \DIR instead of a bare interview: pyproject.toml, MANIFEST.in, the \
                   \generated runtime module, the interview under data/questions, and \
                   \the .l4 source itself under data/sources. Cannot be combined with \
                   \--output, which writes a single file."
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
  -- RULING (M2, recorded at DOCASSEMBLE-EXPORT-SPEC.md §8.11): `--package DIR`
  -- and `-o FILE` are two different artifact shapes, and `-o` is already
  -- overloaded house-wide (FILE in eight verbs, DIR in `l4 trace`). Honouring
  -- one and silently ignoring the other is the failure mode with no precedent
  -- to lean on, so the combination is refused by name — before anything is
  -- read, let alone written.
  case (opts.daOutput, opts.daPackage) of
    (Just _, Just _) -> do
      hPutStrLn stderr
        "l4 docassemble: --package cannot be combined with --output: \
        \--package writes a directory tree, --output writes a single file. \
        \Pick one."
      exitFailure
    _ -> pure ()

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
        Right (pkg, report) ->
          case opts.daPackage of
            Just dir -> do
              tree <- writePackageTree dir opts.daFile pkg
              tripped <- reportFidelity opts (Just (dir </> joinPath (map Text.unpack tree.ptFidelity))) report
              if tripped then exitFailure else exitSuccess
            Nothing -> do
              let out = renderPackage pkg
              case opts.daOutput of
                Just f  -> Text.writeFile f out
                Nothing -> Text.putStr out
              tripped <- reportFidelity opts (fidelitySibling <$> opts.daOutput) report
              if tripped then exitFailure else exitSuccess

----------------------------------------------------------------------------
-- The installable package tree (R11, M2)
----------------------------------------------------------------------------

-- | Write the PEP 420 tree into @dir@ and report each path on stderr (the
-- @l4 trace --output-dir@ house pattern).
--
-- Clobber policy, RULED here and recorded at §8.11: regenerating in place is
-- the normal workflow, so an existing tree this command wrote is overwritten
-- without ceremony — but a directory holding anything else is refused, because
-- a docassemble package is a thing people edit and @dainstall --watch@, and
-- silently overwriting a hand-written @pyproject.toml@ is a data loss no
-- golden can see. \"A tree this command wrote\" is decided by the generator
-- marker on the first line of @pyproject.toml@, which is emitted by
-- 'renderPackageTree' and by nothing else.
writePackageTree :: FilePath -> FilePath -> DAPackage -> IO DAPackageTree
writePackageTree dir srcFile pkg = do
  let tree = renderPackageTree (Text.pack (takeFileName srcFile)) pkg
  guardClobber dir
  for_ tree.ptFiles \f -> writeRel dir f.dafPath f.dafBody
  -- The .l4 source is COPIED, not re-rendered: provenance means the bytes, so
  -- the encoding travels with its compilation rather than being re-encoded.
  let srcRel = relPath tree.ptSourceCopy
  createDirectoryIfMissing True (dir </> takeDirectory srcRel)
  copyFile srcFile (dir </> srcRel)
  hPutStrLn stderr ("l4 docassemble: wrote " <> Text.unpack tree.ptDistName <> " to " <> dir)
  for_ (map (relPath . (.dafPath)) tree.ptFiles <> [srcRel]) \rel ->
    hPutStrLn stderr ("l4 docassemble:   " <> (dir </> rel))
  pure tree

relPath :: [Text] -> FilePath
relPath = joinPath . map Text.unpack

writeRel :: FilePath -> [Text] -> Text -> IO ()
writeRel dir segments body = do
  let rel = relPath segments
  createDirectoryIfMissing True (dir </> takeDirectory rel)
  TextIO.writeFile (dir </> rel) body

-- | The first line 'renderPackageTree' writes into @pyproject.toml@. Nothing
-- else in this repo emits it, so its presence identifies a tree this command
-- owns and may overwrite.
packageMarker :: Text
packageMarker = "# Generated by `l4 docassemble --package`"

guardClobber :: FilePath -> IO ()
guardClobber dir = do
  isDir <- doesDirectoryExist dir
  when isDir do
    entries <- listDirectory dir
    unless (null entries) do
      let toml = dir </> "pyproject.toml"
      haveToml <- doesFileExist toml
      ours <- if haveToml
                then (packageMarker `Text.isPrefixOf`) <$> TextIO.readFile toml
                else pure False
      unless ours do
        hPutStrLn stderr $
          "l4 docassemble: refusing to write a package into " <> dir
            <> ": it is not empty and its pyproject.toml was not written by \
               \`l4 docassemble --package`. Regenerating over a previous run is \
               \fine; overwriting anything else is not. Remove the directory, or \
               \name an empty one."
        exitFailure

----------------------------------------------------------------------------
-- Fidelity placement (the L4.Cli.Export discipline)
----------------------------------------------------------------------------

-- | @interview.yml@ → @interview.fidelity.txt@, matching the golden-pair
-- shape of the DMN/BPMN exhibits.
fidelitySibling :: FilePath -> FilePath
fidelitySibling f = replaceExtension f ".fidelity.txt"

-- | Tally, report, gate. Returns 'True' when @--fail-on@ says this export
-- should exit non-zero.
--
-- The second argument is where the full report goes: a sibling
-- @.fidelity.txt@ beside @--output@, the same-stem file at the root of the
-- package tree under @--package@ (which @MANIFEST.in@ includes, so the loss
-- report ships with the package it describes), or 'Nothing' — stderr — for a
-- bare run to stdout.
reportFidelity :: DocassembleOptions -> Maybe FilePath -> FidelityReport -> IO Bool
reportFidelity opts mDest report = do
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
  case mDest of
    Just dest -> do
      Text.writeFile dest rendered
      hPutStrLn stderr ("l4 docassemble: fidelity report written to " <> dest)
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
