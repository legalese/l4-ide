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
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr, withBinaryFile, IOMode(WriteMode))
import System.Process (CreateProcess(..), StdStream(..), createProcess, proc, waitForProcess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.EvaluateLazy (EvalDirectiveResult(..), EvalConfig(..), readFixedNowEnv, resolveEvalConfig, traceUnavailable)
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
          finish evalResults

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
          finish evalResults

        -- (Nothing, PngFormat | SvgFormat) was rejected up top already.
        (Nothing, _) -> exitFailure
  where
    -- A trace that could not be built is a graph of one node. Exit 0 would pass
    -- it off as the trace of something trivial.
    finish evalResults
      | any (maybe False traceUnavailable . (.trace)) evalResults = do
          hPutStrLn stderr "Error: a trace could not be built (internal error during trace post-processing); its graph has one node saying so"
          exitFailure
      | otherwise = exitSuccess

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
            (proc "dot" ["-T" <> formatFlag, dotArg]) { std_out = UseHandle hOut }
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
  where
    -- dot takes any argument starting with '-' as an option, "--" included, so
    -- a (necessarily relative) path like "-out/x.dot" goes as "./-out/x.dot".
    dotArg = case dotFile of { '-' : _ -> "." </> dotFile; _ -> dotFile }

-- `l4 trace` uses its own EvalConfig with tracing switched on.
--
-- For l4-cli-test only: with @JL4_TEST_FAIL_TRACE_POSTPROCESS@ set to exactly
-- @1@, every trace's post-processing fails, so the test can check that a trace
-- that cannot be built exits 1. No known input makes it fail any more, and the
-- exit is decided here, in the binary. Only @l4 trace@ reads the variable; the
-- language server and the service do not.
makeTraceEvalConfig :: TraceOptions -> IO EvalConfig
makeTraceEvalConfig opts = do
  envFixed <- readFixedNowEnv
  failTrace <- lookupEnv "JL4_TEST_FAIL_TRACE_POSTPROCESS"
  let tp = makeTracePolicyForTrace opts.traceFormat opts.traceOutputDir
  cfg <- resolveEvalConfig (opts.traceFixedNow.unFixedNow <|> envFixed) tp
  pure $ if failTrace == Just "1"
    then cfg { tracePostprocessor = const (error "postprocessTrace: failure injected by JL4_TEST_FAIL_TRACE_POSTPROCESS=1") }
    else cfg

-- Silence `unused-top-binds` nag for Text.pack re-export via Base.Text.
_unusedText :: ()
_unusedText = let _ = Text.pack "" in ()
