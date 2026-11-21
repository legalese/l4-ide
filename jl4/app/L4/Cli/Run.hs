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

import Base (for_, toList)
import Data.IORef (readIORef)
import Data.Maybe (isNothing)
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

import L4.EvaluateLazy (EvalConfig (..), EvalDirectiveResult(..), EvalDirectiveValue(..), AssertionOutcome(..), ReductionOutcome(..), Refusal(..), prettyAssertionOutcome, prettyEvalException, prettyReductionOutcome, undeterminedJson)
import L4.EvaluateLazy.Exceptions (Budget (..), EvalException (..), UserEvalException (..), stopsTheRun)
import L4.Print (termNeedText)
import L4.Parser.SrcSpan (prettySrcRange, prettySrcRangeM)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data RunOptions = RunOptions
  { runFile      :: FilePath
  , runJsonOut   :: Bool
  , runTrace     :: TraceTextMode
  , runFixedNow  :: FixedNowOpt
  , runLimits    :: EvalLimitsOpt
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
        <> help "Show the trace of each #EVALTRACE directive in the text output: none | full (--json output carries no trace)"
        )
  <*> fixedNowParser
  <*> evalLimitsParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

runCmd :: RunOptions -> IO ()
runCmd opts = do
  -- A trace is collected only to be printed, and only by the text output:
  -- 'evalResultToJson' carries none, and collecting one under --json would cost
  -- time and memory for a value that is dropped (and put its text into the
  -- diagnostics). So --json asks for none.
  let traceMode = if opts.runJsonOut then TraceTextNone else opts.runTrace
  evalConfig <- withEvalLimits opts.runLimits =<< makeRunEvalConfig traceMode opts.runFixedNow
  (errs, diags, (mTc, mEval)) <- runOneshotWithDiagnostics evalConfig opts.runFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mtc   <- Shake.use Rules.SuccessfulTypeCheck uri
    meval <- Shake.use Rules.EvaluateLazy uri
    pure (mtc, meval)
  -- smucclaw/l4-ide#1075, ruling L2: a time or memory stop stops the run.
  -- When it was an imported file's own #EVAL that went over, no result of
  -- this file need say so (this file may have none), so the run fails here
  -- and says where it stopped.
  stopped <- maybe (pure Nothing) readIORef evalConfig.runStop

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
      -- A FAILED #ASSERT fails the run too (ruled by Meng 2026-09-29): an
      -- assertion is a test, and a test runner that exits 0 on a failing test
      -- cannot gate anything. See 'evalDirectiveFailsRun' for which outcomes
      -- count; a REFUSED assertion and every other #EVAL value do not.
      --
      -- "Crash" is every 'EvalException', which is broader than a CONSIDER
      -- hole. It notably includes 'Stuck': an ASSUME-style module typechecks
      -- but cannot evaluate ("I needed to know the value of x but it is an
      -- assumed term"), so `l4 run` over one now exits 1 where it used to exit
      -- 0. That is the intent — a module that cannot evaluate should not
      -- report success — but it is the widest-reaching consequence of the
      -- ruling, so it is called out here rather than left to be rediscovered.
      evalFailed = any evalDirectiveFailsRun evalResults
      -- Exit code is otherwise based on Shake rule results and structural
      -- diagnostics, NOT on the raw log stream. #EVAL directive outcomes are
      -- published as source="eval" diagnostics (Information for values, Error
      -- for a failed assertion / eval exception); 'hasBlockingError' excludes
      -- source="eval", so #EVAL outcomes reach the exit code only through
      -- 'evalFailed' above. Non-#EVAL Error diagnostics (parse/type errors,
      -- failed imports, an import cycle) do fail the run — including cycles
      -- whose diagnostic the engine attaches to a transitively-imported file
      -- rather than the entry.
      overallOk = typecheckOk && not (hasBlockingError diags) && not evalFailed && isNothing stopped
      -- the stop, said on stderr unless a result of this file already says it
      stopUnsaid = case stopped of
        Just (b, at) | not (any (resultSaysStop . (.result)) evalResults) ->
          Just ("l4 run: " <> prettySrcRangeM at <> ": "
                <> Text.unwords (prettyEvalException (UserEvalException (OverBudget b))))
        _ -> Nothing

  if opts.runJsonOut
    then do
      BSL8.putStrLn $ Aeson.encode $ Aeson.object
        [ Key.fromString "file"        Aeson..= opts.runFile
        , Key.fromString "ok"          Aeson..= overallOk
        , Key.fromString "diagnostics" Aeson..= diagnosticsToJson errs
        , Key.fromString "results"     Aeson..= map evalResultToJson evalResults
        ]
      for_ stopUnsaid (Text.hPutStrLn stderr)
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
          case (stopUnsaid, errs) of
            (Just said, _) -> Text.hPutStrLn stderr said
            (Nothing, []) | null evalResults ->
                 Text.hPutStrLn stderr "Run failed (file may be empty, unparseable, or not found)"
            _ -> pure ()
          exitFailure

-- | Does this result say that the run stopped: it went over the time or
-- memory limit, or was not evaluated because an earlier one did?
resultSaysStop :: EvalDirectiveValue -> Bool
resultSaysStop = \ case
  Reduction (ReducedErrored e) -> saysStop e
  Assertion (Errored e)        -> saysStop e
  _                            -> False
  where
    saysStop = \ case
      UserEvalException (OverBudget b)     -> stopsTheRun b
      UserEvalException (NotEvaluated _ _) -> True
      _                                    -> False

-- | Does this directive fail @l4 run@ (see 'runCmd')? It does if it crashed
-- during evaluation, if it is undetermined, or if it is an @#ASSERT@ that
-- evaluated to false. A value, a refusal, and a satisfied assertion do not.
evalDirectiveFailsRun :: EvalDirectiveResult -> Bool
evalDirectiveFailsRun r = case r.result of
  Reduction (ReducedErrored _) -> True
  Reduction (Reduced _)        -> False
  -- A REFUSAL is not a crash. The model declined to answer and said why: that
  -- is a determinate outcome of the program, so @l4 run@ exits 0. (Errors keep
  -- exit 1; the two must not be conflated, which is the whole point of REFUSE.)
  Reduction (ReducedRefused _) -> False
  -- An assertion whose expression RAISED did not evaluate cleanly: it is the
  -- same crash as a raising #EVAL, and the ruling above covers every
  -- 'EvalException'.
  Assertion (Errored _)      -> True
  -- A refused assertion is neither true nor false: the model declined to
  -- answer, which is a designed outcome, as for a refusing #EVAL above.
  Assertion (Refused _)      -> False
  Assertion Holds            -> False
  -- A clean false is a failed test (ruled by Meng 2026-09-29).
  Assertion Fails            -> True
  Assertion (FailsBecause _) -> True
  -- An UNDETERMINED directive is no answer at all, as a Stuck one always
  -- was, so it fails the run as the ruling above has every Stuck do
  -- (UNKNOWN-EVALUATION-SPEC §4.7.4, U1b, U7b).
  Reduction (ReducedUndetermined _) -> True
  Assertion (Undetermined _)        -> True

----------------------------------------------------------------------------
-- JSON shape
----------------------------------------------------------------------------

evalResultToJson :: EvalDirectiveResult -> Aeson.Value
evalResultToJson MkEvalDirectiveResult{range = mRange, result, trace = _, notes = ns} =
  Aeson.object $
    [ Key.fromString "range" Aeson..= fmap prettySrcRange mRange
    , Key.fromString "kind"  Aeson..= kindText
    , Key.fromString "value" Aeson..= valueJson
    ] <> errorField
    -- what the run reported without failing (an early act, R-X6; an empty
    -- window), only when there is any, so the object of a directive with
    -- none is unchanged. A JSON consumer that read only "value" was handed
    -- the silent nullity R-X6 forbids (adversarial pass of 2026-09-16, G1).
    <> [ Key.fromString "notes" Aeson..= ns | not (null ns) ]
  where
    (kindText, valueJson, errorField) = case result of
      Assertion Holds         -> ("assertion" :: Text, Aeson.Bool True, [])
      Assertion Fails         -> ("assertion", Aeson.Bool False, [])
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
      Assertion a@(Errored exc) -> ("assertion", Aeson.Null, [Key.fromString "error" Aeson..= prettyAssertionOutcome a] <> limitField exc)
      -- An UNDETERMINED assertion keeps kind "assertion", as a refused one
      -- does, since a consumer counting assertions must still count it, with
      -- a null value and what it waits on under "undetermined" (decided by
      -- Claude overnight 2026-10-03, pending Meng's review;
      -- UNKNOWN-EVALUATION-SPEC §8 step 3).
      Assertion (Undetermined _) ->
        ("assertion", Aeson.Null,
         [Key.fromString "undetermined" Aeson..= undeterminedJson result])
      -- An UNDETERMINED #EVAL gets its OWN kind, as a refusing one does: it
      -- is neither a value nor an error. "needs" names what it waits on, each
      -- once, in the order evaluation reached it, and "message" is the
      -- default report's text (UNKNOWN-EVALUATION-SPEC §4.7.4).
      Reduction o@(ReducedUndetermined needs) ->
        ("undetermined", Aeson.Null,
         [ Key.fromString "needs"   Aeson..= map termNeedText (toList needs)
         , Key.fromString "message" Aeson..= prettyReductionOutcome o
         ])
      -- A refusing #EVAL gets its OWN kind. It is neither a value nor an
      -- error, and a consumer must be able to tell all three apart.
      Reduction (ReducedRefused ref) ->
        ("refused", Aeson.Null,
         [Key.fromString "reason" Aeson..= ref.message])
      -- 'prettyEvalException', not 'show': 'show' leaks the raw Haskell
      -- constructor names of the exception into the JSON.
      Reduction (ReducedErrored exc) ->
        ("error", Aeson.String (Text.unlines ("evaluation exception:" : prettyEvalException exc)), limitField exc)
      Reduction (Reduced val) -> ("value", Aeson.String (renderEvalValue (Reduction (Reduced val))), [])
    -- smucclaw/l4-ide#1075: a directive the machine stopped for going over
    -- a budget says which one, as jl4-service's "@limit" does, so that a
    -- consumer can tell "stopped" from "wrong" without reading the text.
    -- One that was not evaluated, because an earlier one stopped the run,
    -- names that limit too, and says it was not evaluated (decided by
    -- Claude 2026-11-21, pending Meng's review). Only such directives have the keys. The names of the counted
    -- budgets are decided by Claude 2026-11-21, pending Meng's review.
    limitField :: EvalException -> [(Key.Key, Aeson.Value)]
    limitField = \ case
      UserEvalException (OverBudget b)     -> [Key.fromString "limit" Aeson..= budgetName b]
      UserEvalException (NotEvaluated b _) ->
        [Key.fromString "limit" Aeson..= budgetName b, Key.fromString "evaluated" Aeson..= False]
      _                                    -> []
    budgetName :: Budget -> Text
    budgetName = \ case
      OpenObligations {}     -> "obligations"
      JoinedBreaches {}      -> "breaches"
      ClosureApplications {} -> "applications"
      TimeLimit {}           -> "time"
      MemoryLimit {}         -> "memory"
