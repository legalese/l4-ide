-- | @l4 trace FILE [--format dot|png|svg] [-o DIR]@ —
-- render evaluation traces of @#EVALTRACE@ directives as GraphViz.
--
-- Rules for where output goes:
--
-- * @--format dot@ with no @-o@: DOT text goes to stdout (redirect with @>@).
-- * @--format dot@ with @-o DIR@: one @.dot@ file per @#EVALTRACE@ is auto-split
--   into the directory, named @\<basename\>-eval\<n\>.dot@.
-- * @--format png@ or @--format svg@: @-o DIR@ is required (binary files can't
--   share stdout). Needs the @dot@ executable from Graphviz on PATH.
module L4.Cli.Trace
  ( TraceOptions(..)
  , traceOptionsParser
  , traceCmd
  ) where

import Base (for_, forM_)
import qualified Base.Text as Text
import qualified Data.Text.IO as TIO
import Control.Exception (try, IOException)
import Options.Applicative
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode(..), exitFailure, exitSuccess)
import System.FilePath (takeBaseName, (</>))
import System.IO (hPutStrLn, stderr, withBinaryFile, IOMode(WriteMode))
import System.Process (CreateProcess(..), StdStream(..), createProcess, proc, waitForProcess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.EvaluateLazy (EvalDirectiveResult(..), EvalConfig, readFixedNowEnv, resolveEvalConfig)
import qualified L4.EvaluateLazy.GraphViz2 as GraphViz2

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data TraceOptions = TraceOptions
  { traceFile                 :: FilePath
  , traceFormat               :: GraphVizFormat
  , traceOutputDir            :: Maybe FilePath
  , traceOptimize             :: Bool
  , traceNoDeduplicateBindings :: Bool
  , traceFixedNow             :: FixedNowOpt
  }

traceOptionsParser :: Parser TraceOptions
traceOptionsParser = TraceOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file containing #EVALTRACE directives")
  <*> option graphVizFormatReader
        ( long "format"
        <> metavar "FORMAT"
        <> value DotFormat
        <> showDefaultWith graphVizFormatExt
        <> help "Output format: dot | png | svg (png/svg require --output-dir)"
        )
  <*> optional (strOption
        ( long "output-dir"
        <> short 'o'
        <> metavar "DIR"
        <> help "Auto-split output into this directory, one file per #EVALTRACE"
        ))
  <*> switch (long "optimize" <> help "Collapse function lookups and simple paths in the trace")
  <*> switch (long "no-deduplicate-bindings" <> help "Disable binding deduplication (enabled by default)")
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

traceCmd :: TraceOptions -> IO ()
traceCmd opts = do
  -- Validate format/output-dir combination first.
  case (opts.traceFormat, opts.traceOutputDir) of
    (PngFormat, Nothing) -> do
      hPutStrLn stderr "Error: --format png requires --output-dir (PNG files can't share stdout)"
      exitFailure
    (SvgFormat, Nothing) -> do
      hPutStrLn stderr "Error: --format svg requires --output-dir (SVG files can't share stdout)"
      exitFailure
    _ -> pure ()

  -- `l4 trace` needs the tracing-enabled EvalConfig variant.
  evalConfig <- makeTraceEvalConfig opts

  (errs, (mTc, mEval)) <- runOneshot evalConfig opts.traceFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mtc   <- Shake.use Rules.SuccessfulTypeCheck uri
    meval <- Shake.use Rules.EvaluateLazy uri
    pure (mtc, meval)
  putDiagnostics errs

  case mEval of
    Nothing -> do
      hPutStrLn stderr "Error: evaluation failed — cannot produce trace"
      exitFailure
    Just evalResults -> do
      let mModule = case mTc of
            Just tc | tc.success -> Just tc.module'
            _                    -> Nothing
          gvOpts = GraphViz2.defaultGraphVizOptions
            { GraphViz2.collapseFunctionLookups = opts.traceOptimize
            , GraphViz2.collapseSimplePaths     = opts.traceOptimize
            , GraphViz2.deduplicateBindings     = not opts.traceNoDeduplicateBindings
            }

      case (opts.traceOutputDir, opts.traceFormat) of
        -- DOT to stdout.
        (Nothing, DotFormat) -> do
          for_ evalResults \result ->
            case result.trace of
              Just tr -> TIO.putStrLn (GraphViz2.traceToGraphViz gvOpts mModule tr)
              Nothing -> pure ()
          exitSuccess

        -- Auto-split into a directory for any format.
        (Just outDir, fmt) -> do
          createDirectoryIfMissing True outDir
          let baseName = takeBaseName opts.traceFile
          forM_ (zip [1 :: Int ..] evalResults) \(idx, result) ->
            case result.trace of
              Just tr -> do
                let dotContent = GraphViz2.traceToGraphViz gvOpts mModule tr
                    dotFile    = outDir </> baseName <> "-eval" <> show idx <> ".dot"
                TIO.writeFile dotFile dotContent
                case fmt of
                  DotFormat -> hPutStrLn stderr ("Generated: " <> dotFile)
                  PngFormat -> do
                    let pngFile = outDir </> baseName <> "-eval" <> show idx <> ".png"
                    ok <- renderWithDot "png" dotFile pngFile
                    if ok
                      then hPutStrLn stderr ("Generated: " <> dotFile <> " and " <> pngFile)
                      else exitFailure
                  SvgFormat -> do
                    let svgFile = outDir </> baseName <> "-eval" <> show idx <> ".svg"
                    ok <- renderWithDot "svg" dotFile svgFile
                    if ok
                      then hPutStrLn stderr ("Generated: " <> dotFile <> " and " <> svgFile)
                      else exitFailure
              Nothing -> pure ()
          exitSuccess

        -- (Nothing, PngFormat | SvgFormat) was rejected up top already.
        (Nothing, _) -> exitFailure

-- | Render a @.dot@ file to @outFile@ via Graphviz's @dot@, capturing its
-- stdout into the file directly.
--
-- Runs @dot@ as a bare process with an explicit argument list (no shell), so
-- paths containing spaces or shell metacharacters — @foo bar/@, @$(...)@,
-- @;rm -rf@ — are passed through verbatim instead of being word-split or
-- executed. Returns 'True' on success; on a missing @dot@ executable or a
-- non-zero exit it prints a diagnostic and returns 'False'.
renderWithDot :: String -> FilePath -> FilePath -> IO Bool
renderWithDot formatFlag dotFile outFile = do
  result <-
    try (withBinaryFile outFile WriteMode \hOut -> do
          (_, _, _, ph) <- createProcess
            (proc "dot" ["-T" <> formatFlag, dotFile]) { std_out = UseHandle hOut }
          waitForProcess ph)
      :: IO (Either IOException ExitCode)
  case result of
    Left err -> do
      hPutStrLn stderr
        ("Error: could not run 'dot' (is Graphviz installed and on PATH?): " <> show err)
      pure False
    Right ExitSuccess -> pure True
    Right (ExitFailure n) -> do
      hPutStrLn stderr
        ("Error: dot exited with code " <> show n <> " while rendering " <> dotFile)
      pure False

-- `l4 trace` uses its own EvalConfig with tracing switched on.
makeTraceEvalConfig :: TraceOptions -> IO EvalConfig
makeTraceEvalConfig opts = do
  envFixed <- readFixedNowEnv
  let tp = makeTracePolicyForTrace opts.traceFormat opts.traceOutputDir
  resolveEvalConfig (opts.traceFixedNow.unFixedNow <|> envFixed) tp

-- Silence `unused-top-binds` nag for Text.pack re-export via Base.Text.
_unusedText :: ()
_unusedText = let _ = Text.pack "" in ()
