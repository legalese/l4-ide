-- | @l4 run FILE@ — typecheck and evaluate an L4 file, printing
-- diagnostics and the results of every @#EVAL@ / @#EVALTRACE@ directive.
--
-- Text output by default; @--json@ flips to a machine-readable envelope
-- suitable for editors, CI, and the writing-l4-rules skill.
module L4.Cli.Run
  ( RunOptions(..)
  , runOptionsParser
  , runCmd
  ) where

import Base (for_)
import Base.Text (Text)
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.EvaluateLazy (EvalDirectiveResult(..), EvalDirectiveValue(..))
import L4.Parser.SrcSpan (prettySrcRange)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data RunOptions = RunOptions
  { runFile      :: FilePath
  , runJsonOut   :: Bool
  , runTrace     :: TraceTextMode
  , runFixedNow  :: FixedNowOpt
  }

runOptionsParser :: Parser RunOptions
runOptionsParser = RunOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to evaluate")
  <*> switch (long "json" <> help "Emit a JSON envelope instead of human text")
  <*> option traceTextModeReader
        ( long "trace"
        <> short 't'
        <> metavar "MODE"
        <> value TraceTextFull
        <> showDefaultWith renderTraceTextMode
        <> help "Trace text mode for #EVALTRACE: none | full"
        )
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

runCmd :: RunOptions -> IO ()
runCmd opts = do
  evalConfig <- makeEvalConfig opts.runFixedNow
  (errs, diags, (mTc, mEval)) <- runOneshotWithDiagnostics evalConfig opts.runFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mtc   <- Shake.use Rules.SuccessfulTypeCheck uri
    meval <- Shake.use Rules.EvaluateLazy uri
    pure (mtc, meval)

  let typecheckOk = case mTc of
        Just tc | tc.success -> True
        _                    -> False
      evalResults = case mEval of
        Just rs -> rs
        Nothing -> []
      -- A directive that CRASHED during evaluation — an eval exception, e.g. a
      -- CONSIDER reached with no branch matching the scrutinee — fails the run.
      -- Ruled by Meng 2026-08-01: `l4 run` should be loud and faily on a
      -- crashed #EVAL rather than exit 0 with the crash buried in the output.
      -- If silence is ever wanted, add a `-q`/`--quiet-eval` option that
      -- restores exit 0 for this case; do NOT flip the default back.
      --
      -- Note the deliberate asymmetry: a crash is a failure, but an `Assertion
      -- False` (a directive that evaluated cleanly to a false assertion) is
      -- NOT, and neither is any other #EVAL outcome. Only the crash was ruled
      -- on; widening this to assertions is a separate decision.
      --
      -- "Crash" is every 'EvalException', which is broader than a CONSIDER
      -- hole. It notably includes 'Stuck': an ASSUME-style module typechecks
      -- but cannot evaluate ("I needed to know the value of x but it is an
      -- assumed term"), so `l4 run` over one now exits 1 where it used to exit
      -- 0. That is the intent — a module that cannot evaluate should not
      -- report success — but it is the widest-reaching consequence of the
      -- ruling, so it is called out here rather than left to be rediscovered.
      evalCrashed = any evalDirectiveCrashed evalResults
      -- Exit code is otherwise based on Shake rule results and structural
      -- diagnostics, NOT on the raw log stream. #EVAL directive outcomes are
      -- published as source="eval" diagnostics (Information for values, Error
      -- for a failed assertion / eval exception); 'hasBlockingError' excludes
      -- source="eval", so #EVAL outcomes reach the exit code only through
      -- 'evalCrashed' above. Non-#EVAL Error diagnostics (parse/type errors,
      -- failed imports, an import cycle) do fail the run — including cycles
      -- whose diagnostic the engine attaches to a transitively-imported file
      -- rather than the entry.
      overallOk = typecheckOk && not (hasBlockingError diags) && not evalCrashed

  if opts.runJsonOut
    then do
      BSL8.putStrLn $ Aeson.encode $ Aeson.object
        [ Key.fromString "file"        Aeson..= opts.runFile
        , Key.fromString "ok"          Aeson..= overallOk
        , Key.fromString "diagnostics" Aeson..= diagnosticsToJson errs
        , Key.fromString "results"     Aeson..= map evalResultToJson evalResults
        ]
      if overallOk then exitSuccess else exitFailure
    else do
      -- Plain text: diagnostics first (stderr), then eval results (stdout).
      putDiagnostics errs
      for_ (zip [1 :: Int ..] evalResults) \(idx, r) ->
        Text.putStrLn (renderEvalOutput opts.runTrace idx r <> "\n")
      if overallOk
        then do
          -- Only say "success" when there are no eval results, so output
          -- stays grep-friendly and CI-readable.
          if null evalResults
            then Text.putStrLn "Checking succeeded."
            else pure ()
          exitSuccess
        else do
          case errs of
            [] | null evalResults ->
                 Text.hPutStrLn stderr "Run failed (file may be empty, unparseable, or not found)"
            _ -> pure ()
          exitFailure

-- | Did this directive crash during evaluation, rather than produce a value or
-- an assertion outcome? A crashed directive fails @l4 run@ (see 'runCmd'); a
-- directive that merely evaluated to @Assertion False@ does not.
evalDirectiveCrashed :: EvalDirectiveResult -> Bool
evalDirectiveCrashed r = case r.result of
  Reduction (Left _) -> True
  Reduction (Right _) -> False
  Assertion _         -> False

----------------------------------------------------------------------------
-- JSON shape
----------------------------------------------------------------------------

evalResultToJson :: EvalDirectiveResult -> Aeson.Value
evalResultToJson MkEvalDirectiveResult{range = mRange, result, trace = _} =
  Aeson.object
    [ Key.fromString "range" Aeson..= fmap prettySrcRange mRange
    , Key.fromString "kind"  Aeson..= kindText
    , Key.fromString "value" Aeson..= valueJson
    ]
  where
    (kindText, valueJson) = case result of
      Assertion b             -> ("assertion" :: Text, Aeson.Bool b)
      Reduction (Left exc)    -> ("error" :: Text, Aeson.String (Text.unlines ["evaluation exception:", Text.pack (show exc)]))
      Reduction (Right val)   -> ("value" :: Text, Aeson.String (renderEvalValue (Reduction (Right val))))
