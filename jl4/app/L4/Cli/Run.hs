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

import L4.EvaluateLazy (EvalDirectiveResult(..), EvalDirectiveValue(..), AssertionOutcome(..), ReductionOutcome(..), Refusal(..), prettyAssertionOutcome, prettyEvalException)
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
      -- Exit code is based on Shake rule results, NOT on the log stream.
      -- The LSP rule publishes #EVAL results as Information-severity
      -- diagnostics via the logger, so a file with passing `#EVAL`s still
      -- produces non-empty `errs` — treating that as failure would be a
      -- false positive. A directive that crashed during evaluation
      -- (e.g. a CONSIDER hole) is a real failure, though. So is an #ASSERT
      -- whose expression RAISED: it did not evaluate cleanly, and it was
      -- exiting 0 only because the exception was hidden inside
      -- @Assertion False@. A clean @Assertion Fails@ stays exit 0, and so does
      -- an @Assertion (FailsBecause _)@, a failed @#ASSERT REFUSED@.
      --
      -- A REFUSAL is not a crash. The model declined to answer and said why:
      -- that is a determinate outcome of the program, so @l4 run@ exits 0.
      -- (Errors keep exit 1; the two must not be conflated, which is the whole
      -- point of REFUSE.)
      evalOk = all
        (\r -> case r.result of
          Reduction (ReducedErrored _) -> False
          Assertion (Errored _)        -> False
          _                            -> True)
        evalResults
      -- A module the file imports can be broken while the file's own typecheck
      -- still reports success (an import cycle's error attaches to an imported
      -- file), so also require that no blocking Error diagnostic was published
      -- anywhere in the import closure. 'hasBlockingError' leaves out the
      -- evaluator's own diagnostics (source "eval"), so a failed #ASSERT, which
      -- is published as one at Error severity, still exits 0; a directive that
      -- crashed is what 'evalOk' is for.
      overallOk = typecheckOk && evalOk && not (hasBlockingError diags)

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

----------------------------------------------------------------------------
-- JSON shape
----------------------------------------------------------------------------

evalResultToJson :: EvalDirectiveResult -> Aeson.Value
evalResultToJson MkEvalDirectiveResult{range = mRange, result, trace = _} =
  Aeson.object $
    [ Key.fromString "range" Aeson..= fmap prettySrcRange mRange
    , Key.fromString "kind"  Aeson..= kindText
    , Key.fromString "value" Aeson..= valueJson
    ] <> errorField
  where
    (kindText, valueJson, errorField) = case result of
      Assertion Holds         -> ("assertion" :: Text, Aeson.Bool True, [])
      Assertion Fails         -> ("assertion", Aeson.Bool False, [])
      -- A failed #ASSERT REFUSED is a false assertion that says why.
      Assertion a@(FailsBecause _) ->
        ("assertion", Aeson.Bool False, [Key.fromString "error" Aeson..= prettyAssertionOutcome a])
      -- A REFUSED assertion keeps kind "assertion" with a null value, and its
      -- reason under "refused" — NOT under "error". A consumer that reads
      -- every non-boolean assertion out of "error" would report a designed
      -- outcome as a defect.
      Assertion (Refused ref) ->
        ("assertion", Aeson.Null,
         [Key.fromString "refused" Aeson..= Aeson.object [Key.fromString "reason" Aeson..= ref.message]])
      -- An assertion that raised keeps kind "assertion" (it IS one, and a
      -- consumer counting assertions must still see it) with a null value —
      -- neither true nor false — and the reason under "error".
      Assertion a@(Errored _) -> ("assertion", Aeson.Null, [Key.fromString "error" Aeson..= prettyAssertionOutcome a])
      -- A refusing #EVAL gets its OWN kind. It is neither a value nor an
      -- error, and a consumer must be able to tell all three apart.
      Reduction (ReducedRefused ref) ->
        ("refused", Aeson.Null,
         [Key.fromString "reason" Aeson..= ref.message])
      -- 'prettyEvalException', not 'show': 'show' leaks the raw Haskell
      -- constructor names of the exception into the JSON (as on unstable,
      -- 75e08b55e). A multi-clause group's no-match error would otherwise
      -- print its internal 'MkPmGroup' record.
      Reduction (ReducedErrored exc) ->
        ("error", Aeson.String (Text.unlines ("evaluation exception:" : prettyEvalException exc)), [])
      Reduction (Reduced val) -> ("value", Aeson.String (renderEvalValue (Reduction (Reduced val))), [])
